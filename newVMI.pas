unit newVMI;

{*******************************************************************************

     Integer array / matrix object leveraging Intel MKL/IPP libraries

     Dr H. Dent uk. email howard@hgrd.co.uk             06 Aug 2026

     Companion to newVM.pas/newVMSingle.pas/newVMComplex.pas/
     newVMComplexSingle.pas, for INDEX operations - pivot vectors, index
     lists, and other places that need an integer-valued (N,1)/(1,N)/
     (M,N) array built the same way as the other four TVMobj* types,
     rather than a full linear-algebra type. There is deliberately no
     MatMult/LinearSolve/operator-overload set here: BLAS/LAPACK don't
     operate on plain integers, and arithmetic on index arrays isn't
     needed for that role - just construction, element access, and
     integer-only initialisation.

     Mirrors the "core object shape" of TVMobj (see newVM.pas) as closely
     as MKL/IPP's integer support allows:
       - Element[r,c] get/set, calcoffsetI row-major addressing - same
         formula and conventions as calcoffset/calcoffsetS/Z/C.
       - fillRandom(loBound,hiBound) - fixed-seed (777) uniform integers
         in [loBound,hiBound), via MKL VSL's viRngUniform. This is the
         integer analogue of vdRngGaussian/vsRngGaussian used by the
         other units' fillRandom, but takes explicit bounds since a
         continuous N(0,1) fill (what the other units' no-argument
         fillRandom does) has no integer equivalent.
       - linspace(Start,increment) - integer arithmetic sequence, via
         IPP's ippsVectorSlope_32s, the integer sibling of
         ippsVectorSlope_64f/_32f used by newVM.pas/newVMSingle.pas.
       - Id - identity matrix. There is no LAPACKE_?laset for integers
         (LAPACK has no integer datatype), so this is a plain Pascal
         loop instead of a LAPACKE call.
       - Transpose - likewise, there is no MKL_?imatcopy for integers
         (only s/d/c/z exist), so this is also a plain loop rather than
         delegating to MKL_Dimatcopy/etc like the other units' Transpose.
       - CopyObjI - via IPP's ippsCopy_32s, the integer sibling of
         ippsCopy_64f.
       - DataPtr / Rows / Cols - same public accessors as the other
         units, for interop (e.g. handing an index vector's raw buffer
         to another routine without needing friend access).

     Also declares TVMCompareOp (=, <, <=, >, >=) - shared with newVM.pas's/
     newVMSingle.pas's Find function so both real units use the one type -
     and Gather, which takes a TVMobjI (typically Find's 0/1 output) and
     returns a 1-row TVMobjI of the row-major linear indexes of its
     non-zero elements.

*******************************************************************************}

{$mode delphi}{$H+}
{$Align 8}
{$I newVMConfig.inc}
{$IFDEF UNIX}
  {$IFDEF HAVE_MKL}
{$Linklib 'mkl_rt.so'}
{$Linklib 'pthread'}
{$Linklib 'm'}
{$Linklib 'dl'}
//mkl_rt.so dlopen's libmkl_core.so (and friends) at runtime, which
//expects libm/pthread/dl to already be loaded into the process's
//global symbol table - without this you get errors like:
//  symbol lookup error: .../libmkl_core.so: undefined symbol: log10
//Unix/ELF dynamic-linker quirk only - not needed for mkl_rt.dll on Windows.
  {$ENDIF}
{$ENDIF}

interface

uses
  Classes, SysUtils, OneAPI;

Const
  // See newVM.pas's own MaxDim comment - an arbitrary development-time
  // value, not a real limit, raised in step with it across every
  // parallel real/complex x double/single unit.
  MaxDimI = 2097152;    //maximum dimensions of any array

Type
  TDimI = 0..MaxDimI-1;
  TDataSizeI = 1..MaxDimI*MaxDimI;
  TVectorI = Array of Integer;

  //Comparison criteria for newVM.pas's/newVMSingle.pas's Find - declared
  //here (rather than duplicated in each real unit) so both units, and any
  //code that uses them together (e.g. newVMTests.pas), share one type
  //instead of two same-named enums colliding.
  TVMCompareOp = (cmpEQ, cmpLT, cmpLE, cmpGT, cmpGE);

type

  { TVMobjI }

  TVMobjI = record
    private
      fData : TVectorI;  //Holds data for object
      frows, fcols : TDimI;
      function getelement(r,c: TDimI): Integer;
      procedure setelement(r,c: TDimI; AValue: Integer);
    public
      constructor create(r,c :TDimI);Overload;
      Constructor create(r,c: TDimI; const Values : TVectorI); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDimI]:Integer read getelement write setelement; default;
      procedure fillRandom(loBound, hiBound: Integer);
      procedure Id;
      procedure linspace(Start, increment: Integer);
      function Transpose: TVMObjI;
      function DataPtr: PInteger;   //raw buffer, for interop from other units
      property Rows: TDimI read frows;              //read-only dimension accessors
      property Cols: TDimI read fcols;
    end;

function calcoffsetI(r,c,cols :TDimI):integer;inline;
function CopyObjI(Const A : TVMObjI):TVMobjI;
function Gather(const A: TVMobjI): TVMobjI;  //linear indexes of A's non-zero elements, row-major

implementation

function calcoffsetI(r, c, cols: TDimI): integer;
begin
  result := r*cols+c;
end;

{ TVMobjI }

function TVMobjI.getelement(r,c: TDimI): Integer;
var
   Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in getelement');
   Ix := calcoffsetI(r,c,cols);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobjI.setelement(r,c:TDimI; AValue: Integer);
var
 Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in setelement');
   Ix := calcoffsetI(r,c,cols);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobjI.create(r,c :TDimI);
var
  i,N : integer;
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  frows := r;
  fcols := c;
  N := r*c;
  setLength(fData,N);
  for i := low(fdata) to high(fdata) do fdata[i] := 0;
end;

constructor TVMobjI.create(r,c : TDimI; const Values: TVectorI);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  frows := r;
  fcols := c;
  fdata := copy(Values,0,high(values)+1);
end;

function TVMobjI.writeMatrix: TStringList;
const
  fieldwidth = 10;
var
   i,j,k,l: integer;
   s,t : String;
begin
  result:= TStringList.create;
  for i:=0 to rows-1 do begin // row by row
    s := '    ['+chr(9);
    for j:=0 to cols-1 do begin
      t := IntToStr(FData[i*cols+j]);
      s := s + t;
      l := length(t);    // pad t to get constant length
     if l < fieldwidth then
      for k := 1 to fieldwidth-l do s := s +' ';
    end;
    s := s +']';
    result.add(s);
  end;
end;

procedure TVMobjI.fillRandom(loBound, hiBound: Integer);
//
// Fixed-seed (777) uniform integers in [loBound,hiBound) - same seeding
// convention as the other units' fillRandom, so two same-sized/same-bounds
// fillRandom calls produce bit-identical data (exploited by tests via the
// deterministic-fill trick).
//
const
  s : string = 'Routine fillRandom : ';
{$IFDEF PUREPASCAL}
{ PUREPASCAL: no VSL, so this reseeds FPC's own Random() to the same
  constant (777) every call and draws via Random(hiBound-loBound) - the
  same "fixed seed -> bit-identical repeat calls" contract as the
  MKL-backed version, just via a different generator. }
var
  i : Integer;
begin
  assert(hiBound > loBound, s+'hiBound must be > loBound');
  RandSeed := 777;
  for i := 0 to high(fdata) do
    fdata[i] := loBound + Random(hiBound-loBound);
end;
{$ELSE}
const
  vslConst = 8388608;
  VSL_RNG_METHOD_UNIFORM_STD = 0;
var
  vsSTream : pointer;
begin
  assert(hiBound > loBound, s+'hiBound must be > loBound');
  vslNewStream(@vsStream,vslConst,777);
  viRngUniform(VSL_RNG_METHOD_UNIFORM_STD,vsStream,high(fdata)+1,@Fdata[0],loBound,hiBound);
  vsldeleteStream(@vsStream);
end;
{$ENDIF}

procedure TVMobjI.Id;
const
  s : string = 'Routine Id :';
var
  i, j : integer;
begin
  //Check dimensions of matrices are compatible - A must be square
  assert(cols=rows,s +'Matrix A must be square');
  for i := 0 to rows-1 do
    for j := 0 to cols-1 do
      if i=j then fdata[calcoffsetI(i,j,cols)] := 1
      else fdata[calcoffsetI(i,j,cols)] := 0;
end;

function TVMobjI.DataPtr: PInteger;
begin
  result := @fdata[0];
end;

procedure TVMObjI.linspace(Start, increment: Integer);
const
  s : String ='routine linspace';
{$IFDEF PUREPASCAL}
var
  i : Integer;
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  for i := 0 to high(fdata) do
    fdata[i] := Start + i*increment;
end;
{$ELSE}
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  ippsVectorSlope_32s(@FData[0],high(fdata)+1,start,increment);
end;
{$ENDIF}

function TVMObjI.Transpose:TVMObjI;
var
  i, j : integer;
begin
  //No MKL_?imatcopy exists for integers, so transpose via a plain loop
  //into a freshly-shaped result rather than an in-place swap.
  result := TVMObjI.Create(cols, rows);
  for i := 0 to rows-1 do
    for j := 0 to cols-1 do
      result.fdata[calcoffsetI(j,i,result.cols)] := fdata[calcoffsetI(i,j,cols)];
end;

function CopyObjI(const A: TVMObjI): TVMobjI;
begin
  result := TVMObjI.Create(A.rows,A.cols);
{$IFDEF PUREPASCAL}
  Move(A.fdata[0], result.fdata[0], A.rows*A.cols*SizeOf(Integer));
{$ELSE}
  ippsCopy_32s(A.DataPtr,result.DataPtr,A.rows*A.cols);
{$ENDIF}
end;

function Gather(const A: TVMobjI): TVMobjI;
//
// Examines A (typically the 0/1 output of newVM.pas's/newVMSingle.pas's
// Find) and returns a 1-row TVMobjI containing the row-major linear
// index (calcoffsetI convention) of every non-zero element of A, in
// ascending order. No IPP/MKL primitive exists for this (it's a
// variable-length compaction, not a fixed-shape vector op), so it's a
// plain Pascal loop, same rationale as Id/Transpose above.
//
const
  s : String = 'Function Gather : ';
var
  i, N, count : integer;
  idx : TVectorI;
begin
  N := A.rows*A.cols;
  setlength(idx, N);
  count := 0;
  for i := 0 to N-1 do
    if A.fData[i] <> 0 then begin
      idx[count] := i;
      inc(count);
    end;
  assert(count > 0, s+'A has no non-zero elements');
  setlength(idx, count);
  result := TVMObjI.Create(1, count, idx);
end;

end.
