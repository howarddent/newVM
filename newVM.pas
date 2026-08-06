unit newVM;

{*******************************************************************************

     Vector / Matrix objects leveraging intel mkl libraries

     Dr H. Dent uk. email howard@hgrd.co.uk             29 July 2026

     Inspired by Dew MtxVec Library for fpc but does not  distinguish
     between matrix and vector objects. Vectors are column dimension (*,1)
     or row dimension (1.*).

     ADDITIONS (for interop with newVMComplex.pas):
       - public DataPtr function: raw pointer to the underlying double
         buffer, so other units can pass it straight into MKL calls
         without needing full friend access to the record internals.
       - public Rows / Cols read-only properties, so other units can
         query dimensions to size a matching object (e.g. for a real ->
         complex copy of the "same dimensions").
       These do not change any existing behaviour.

     OPERATOR OVERLOADS (algebraic expressions on TVMobj):
       - '+' and '-' are element-wise, via cblas_daxpy (Y := alpha*X + Y).
       - unary '-' negates via cblas_dscal.
       - '*' between two TVMobj is matrix multiplication, delegating to
         the existing MatMult (cblas_dgemm).
       - '*' and '/' against a plain Double scalar scale every element,
         via cblas_dscal and IPP's ippsDivC_64f_I respectively.
       These let expressions like  C := A*B + D;  or  C := 2*A - B/3;
       be written directly instead of via named routines.

*******************************************************************************}

{$mode delphi}{$H+}
{$Align 8}
{$IFDEF UNIX}
{$Linklib 'mkl_rt.so'}
{$Linklib 'pthread'}
{$Linklib 'm'}
{$Linklib 'dl'}
//The three libs above aren't used directly by this unit, but mkl_rt.so
//dlopen's libmkl_core.so (and friends) at runtime, which expects libm/
//pthread/dl to already be loaded into the process's global symbol table.
//Without this, you get errors like:
//  symbol lookup error: .../libmkl_core.so: undefined symbol: log10
//This is a Unix/ELF dynamic-linker quirk - Windows DLLs resolve their own
//imports independently, so mkl_rt.dll needs no such preload on Windows.
{$ENDIF}

interface

uses
  Classes, SysUtils,cblas,math,TestRegistry,OneAPI,Types,fftw3,newVMI;

Const
  MaxDim = 65536;    //maximum dimensions of any array

Type
  TDim = 0..MaxDim-1;
  TDataSize = 1..MaxDim*MaxDim;
  TVector = Array of Double;   //maximum dimensions of any array


type
  
  { TVMobj }

  TVMobj = record
    private
      fData : tVector;  //Holds data for object
      frows, fcols : TDim;
      function getelement(r,c: TDim): Double;
      procedure setelement(r,c: TDim; AValue: Double);
    public
      constructor create(r,c :tDim);Overload;
      Constructor create(r,c: TDim; const Values : TVector); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDim]:Double read getelement write setelement; default;
      procedure fillRandom;
      procedure Id;
      procedure linspace(Start, increment: Double);
      function Transpose: TVMObj;
      function DataPtr: PDouble;   //raw buffer, for MKL interop from other units
      property Rows: TDim read frows;              //read-only dimension accessors
      property Cols: TDim read fcols;
      class operator +(const A, B: TVMobj): TVMobj;
      class operator -(const A, B: TVMobj): TVMobj;
      class operator -(const A: TVMobj): TVMobj;
      class operator *(const A, B: TVMobj): TVMobj;
      class operator *(const A: TVMobj; const k: Double): TVMobj;
      class operator *(const k: Double; const A: TVMobj): TVMobj;
      class operator /(const A: TVMobj; const k: Double): TVMobj;
      class operator =(const A, B: TVMobj): Boolean;
    end;

function calcoffset(r,c,cols :TDim):integer;inline;
function MatMult( const A, B: TVMObj): TVMobj;
function LinearSolve(var A, B: TVMObj):integer;
function CopyObj(Const A : TVMObj):TVMobj;
function Invert(const A: TVMobj): TVMobj;  //matrix inverse, via LAPACKE_dgetrf+dgetri; leaves A untouched
{ Find - element-wise comparison of A against Value using Op (see
  TVMCompareOp in newVMI.pas: cmpEQ/cmpLT/cmpLE/cmpGT/cmpGE). Returns a
  same-shape TVMobjI with 1 where the criteria matches and 0 elsewhere.
  No MKL/IPP primitive produces a comparison mask, so this is a plain
  loop; marked "overload" since newVMSingle.pas declares the TVMobjS
  analogue of the same name. }
function Find(const A: TVMobj; Op: TVMCompareOp; Value: Double): TVMobjI; overload;
{ Kron - Kronecker matrix product of A (m,n) and B (p,q): an (m*p, n*q)
  result whose (i,j) block (each p x q) is A[i,j]*B. No BLAS/LAPACK
  routine computes a Kronecker product directly, so this places each
  block via cblas_daxpy (alpha=A[i,j]) row-by-row into the zero-filled
  result - the same "scale via axpy onto a fresh buffer" idiom the '+'/'-'
  operators use, just applied per source row instead of over the whole
  buffer at once, since a block's rows aren't contiguous in the result's
  row-major layout. }
function Kron(const A, B: TVMobj): TVMobj;

{ Elementwise transcendental/algebraic functions, via MKL VML (vd* routines
  in OneAPI.pas). Each returns a new TVMobj of the same dimensions as A,
  with the function applied to every element. Marked "overload" since
  Sin/Cos/Sqr/Sqrt/Exp/Ln also exist in System/Math for plain numeric
  types - without "overload" the TVMobj versions here would hide those
  entirely within this unit, breaking any plain Sqrt(x: Double) call. }
function Sin(const A: TVMobj): TVMobj; overload;
function Cos(const A: TVMobj): TVMobj; overload;
function Tan(const A: TVMobj): TVMobj; overload;
function Sinh(const A: TVMobj): TVMobj; overload;
function Sqr(const A: TVMobj): TVMobj; overload;
function Sqrt(const A: TVMobj): TVMobj; overload;
function Exp(const A: TVMobj): TVMobj; overload;
function Ln(const A: TVMobj): TVMobj; overload;
function mulObj(const A, B: TVMObj): TVMObj;

{ Real-to-real DCT/DST types I-IV, via FFTW3 (fftw3.pas) r2r transforms on
  the double-precision library. A must be a vector (Rows=1 or Cols=1); the
  result has the same shape. Input is never mutated (FFTW_PRESERVE_INPUT).
  These are UNNORMALIZED, matching FFTW's own convention: e.g. DCT1 applied
  twice returns the original scaled by 2*(N-1) - see FFTW's "1D Real-even/
  odd DFTs" documentation for the exact scale factor per kind. Marked
  "overload" for the same reason as Sin/Cos/etc above - newVMSingle.pas
  declares the TVMobjS analogues of these same names. }
function DCT1(const A: TVMobj): TVMobj; overload;  //FFTW_REDFT00
function DCT2(const A: TVMobj): TVMobj; overload;  //FFTW_REDFT10
function DCT3(const A: TVMobj): TVMobj; overload;  //FFTW_REDFT01 (inverse of DCT2, up to scale)
function DCT4(const A: TVMobj): TVMobj; overload;  //FFTW_REDFT11 (self-inverse, up to scale)
function DST1(const A: TVMobj): TVMobj; overload;  //FFTW_RODFT00
function DST2(const A: TVMobj): TVMobj; overload;  //FFTW_RODFT10
function DST3(const A: TVMobj): TVMobj; overload;  //FFTW_RODFT01 (inverse of DST2, up to scale)
function DST4(const A: TVMobj): TVMobj; overload;  //FFTW_RODFT11 (self-inverse, up to scale)

implementation

function calcoffset(r, c, cols: TDim): integer;
begin
  result := r*cols+c;
end;

{ TVMobj }

function TVMobj.getelement(r,c: TDim): Double;
var
   Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in getelement');
   Ix := calcoffset(r,c,cols);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobj.setelement(r,c:TDim; AValue: Double);
var
 Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in setelement');
   Ix := calcoffset(r,c,cols);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobj.create(r,c :tDim);
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

constructor TVMobj.create(r,c : TDim; const Values: TVector);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  frows := r;
  fcols := c;
  fdata := copy(Values,0,high(values)+1);
end;

function TVMobj.writeMatrix: TStringList;
const
  fieldwidth = 10;
var
   i,j,k,l: integer;
   s,t : String;
begin
  result:= TStringList.create;
  for i:=0 to rows-1 do begin // row by row
    s := '    ['+chr(9);//+chr(9);
    for j:=0 to cols-1 do begin
      t :=floatToStrf(FData[i*cols+j],fffixed,10,3);
      s := s + t;
      l := length(t);    // pad t to get constant length
     if l < fieldwidth then
      for k := 1 to fieldwidth-l do s := s +' ';
    end;
    s := s {+chr(9)}+']';
    result.add(s);
  end;
end;

procedure TVMobj.fillRandom;
//
// from c program at
//https://www.smcm.iqfr.csic.es/docs/intel/mkl/mkl_manual/sf/sf_vslusage.htm
// Timed for 1000x1000 loop 100ms intel mkl 2ms!
//
const
  vslConst = 8388608;
  VSL_RNG_METHOD_GAUSSIAN_ICDF = 2;
var
  vsSTream : pointer;
begin
  vslNewStream(@vsStream,vslConst,777);
  vdRngGaussian(VSL_RNG_METHOD_GAUSSIAN_ICDF,vsStream,high(fdata)+1,@Fdata[0],0,1);
  vsldeleteStream(@vsStream);
end;

procedure TVMobj.Id;
const
  s : string = 'Routine Id :';
begin
    //Check dimensions of matrices are compatible. A must be square and A.cols =
  // B.rows
  assert(cols=rows,s +'Matrix A must be square');
  lapacke_dlaset(CBlasRowMajor,'A',rows,cols,0,1,@Fdata[0],rows);
end;

function TVMobj.DataPtr: PDouble;
begin
  result := @fdata[0];
end;

procedure TVMObj.linspace(Start, increment: Double);
const
  s : String ='routine linspace';
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  ippsVectorSlope_64f(@FData[0],high(fdata)+1,start,increment);
end;

function TVMObj.Transpose:TVMObj;
var
  temp : TDim;
begin
  result := copyobj(self);
  MKL_Dimatcopy('R','T',rows,cols,1,result.DataPtr,cols,rows);
//swap row and column numbers
  temp := self.rows;
  result.frows := self.cols;
  result.fcols := temp;
end;


function MatMult(const A, B: TVMObj): TVMobj;
const
  s : String = 'Routine MatMult :';
var
  m,n,k,I : integer;
  C : TVMObj;
begin
  m := A.Rows;
  n := B.Cols;
  k := A.Cols;
  //Check for compatibilty of matrices
  assert(A.cols = B.rows,s+'columns of first matrix must equal rows of second');
  c := TVMObj.Create(m,n);
  //check library initialized
  cblas_dgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
              m,n,k, { m, n, k }
              1,     { alpha   }
                @A.FData[0], k,
                @B.Fdata[0], n,
              1, {beta}
                @C.Fdata[0],n
             );
    result := C;
end;

function LinearSolve(var A, B: TVMObj):integer;
const
  s : String = 'Function linear Solve : ';
var
  ipiv : array of integer;
{ Direct linear solve for matrix A and Vectors B. On return A is in LU
  factored form and solution matrix is in B. Returns info from Lapacke}
begin
  //Check dimensions of matrices are compatible. A must be square and A.cols =
  // B.rows
  assert(A.Cols = A.Rows,s+'Matrix A must be square');
  assert(A.Rows = B.Rows, s+'Matrix A and B have incompatible dimensions');
  setlength(ipiv,A.rows);
 linearSolve:= lapacke_dgesv(CBlasRowMajor,A.rows,B.cols,@A.Fdata[0],A.cols,@ipiv[0],@B.FData[0],B.cols);
end;

function CopyObj(const A: TVMObj): TVMobj;
begin
  result := TVMObj.Create(A.rows,A.cols);
  LAPACKE_dlacpy(CBlasRowMajor,'A',A.rows,A.cols,@A.Fdata[0],a.cols,@result.fdata[0],result.cols);
end;

function Invert(const A: TVMobj): TVMobj;
const
  s : String = 'Function Invert : ';
var
  ipiv : array of integer;
  info : integer;
{ Matrix inverse via LAPACKE_dgetrf (LU factorisation) followed by
  LAPACKE_dgetri (inverse from the LU factors). Runs on a CopyObj scratch
  buffer, like EigDecompose, since both LAPACKE calls overwrite their
  input matrix in place - A itself is left untouched. }
begin
  assert(A.Cols = A.Rows, s+'Matrix A must be square');
  result := CopyObj(A);
  setlength(ipiv, A.rows);
  info := lapacke_dgetrf(CBlasRowMajor, A.rows, A.cols, result.DataPtr, A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_dgetrf failed (singular matrix?), info='+IntToStr(info));
  info := lapacke_dgetri(CBlasRowMajor, A.rows, result.DataPtr, A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_dgetri failed (singular matrix?), info='+IntToStr(info));
end;

function Find(const A: TVMobj; Op: TVMCompareOp; Value: Double): TVMobjI;
var
  i, j : integer;
  matched : Boolean;
begin
  result := TVMobjI.Create(A.Rows, A.Cols);
  for i := 0 to A.Rows-1 do
    for j := 0 to A.Cols-1 do begin
      case Op of
        cmpEQ: matched := A[i,j] = Value;
        cmpLT: matched := A[i,j] < Value;
        cmpLE: matched := A[i,j] <= Value;
        cmpGT: matched := A[i,j] > Value;
        cmpGE: matched := A[i,j] >= Value;
      else
        matched := False;
      end;
      if matched then result[i,j] := 1 else result[i,j] := 0;
    end;
end;

function Kron(const A, B: TVMobj): TVMobj;
var
  i, j, k, rowdest, coldest : integer;
begin
  result := TVMobj.Create(A.Rows*B.Rows, A.Cols*B.Cols);
  for i := 0 to A.Rows-1 do
    for j := 0 to A.Cols-1 do
      for k := 0 to B.Rows-1 do begin
        rowdest := i*B.Rows + k;
        coldest := j*B.Cols;
        cblas_daxpy(B.Cols, A[i,j], @B.FData[k*B.Cols], 1, @result.FData[rowdest*result.Cols + coldest], 1);
      end;
end;

class operator TVMobj.+(const A, B: TVMobj): TVMobj;
const
  s : String = 'Operator + (TVMobj) : ';
begin
  assert((A.Rows=B.Rows) and (A.Cols=B.Cols), s+'matrix dimensions must match');
  result := CopyObj(B);
  cblas_daxpy(A.Rows*A.Cols, 1, A.DataPtr, 1, result.DataPtr, 1);
end;

class operator TVMobj.-(const A, B: TVMobj): TVMobj;
const
  s : String = 'Operator - (TVMobj) : ';
begin
  assert((A.Rows=B.Rows) and (A.Cols=B.Cols), s+'matrix dimensions must match');
  result := CopyObj(A);
  cblas_daxpy(A.Rows*A.Cols, -1, B.DataPtr, 1, result.DataPtr, 1);
end;

class operator TVMobj.-(const A: TVMobj): TVMobj;
begin
  result := CopyObj(A);
  cblas_dscal(A.Rows*A.Cols, -1, result.DataPtr, 1);
end;

class operator TVMobj.*(const A, B: TVMobj): TVMobj;
begin
  result := MulObj(A, B);
end;

class operator TVMobj.*(const A: TVMobj; const k: Double): TVMobj;
begin
  result := CopyObj(A);
  cblas_dscal(A.Rows*A.Cols, k, result.DataPtr, 1);
end;

class operator TVMobj.*(const k: Double; const A: TVMobj): TVMobj;
begin
  result := A * k;
end;

class operator TVMobj./(const A: TVMobj; const k: Double): TVMobj;
const
  s : String = 'Operator / (TVMobj) : ';
begin
  assert(k<>0, s+'division by zero');
  result := CopyObj(A);
  ippsDivC_64f_I(k, result.DataPtr, A.Rows*A.Cols);
end;

class operator TVMobj.=(const A, B: TVMobj): Boolean;
begin
  Result := (A.Rows = B.Rows) and (A.Cols = B.Cols) and
            CompareMem(A.DataPtr, B.DataPtr, A.Rows*A.Cols*SizeOf(Double));
end;

function Sin(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdSin(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Cos(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdCos(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Tan(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdTan(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sinh(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdSinh(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sqr(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdSqr(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sqrt(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdSqrt(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Exp(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdExp(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Ln(const A: TVMobj): TVMobj;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  vdLn(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function mulObj(const A, B: TVMObj): TVMObj;
const
  s: string ='Routine mulObj : ';
begin
  assert((a.rows=b.rows)and(a.cols=b.cols),s+'Dimensions of A and B must be the same');
  result := CopyObj(A);
  vdMul(A.rows*A.cols,A.Dataptr,B.DataPtr,Result.DataPtr);

end;

function r2rTransform(const A: TVMobj; kind: TFFTW_r2r_kind): TVMobj;
const
  s : String = 'Routine r2rTransform : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftw_plan_r2r_1d), s+'FFTW3 (double) library not loaded');
  result := TVMobj.Create(A.Rows, A.Cols);
  plan := fftw_plan_r2r_1d(n, A.DataPtr, result.DataPtr, kind, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftw_plan_r2r_1d failed');
  fftw_execute_r2r(plan, A.DataPtr, result.DataPtr);
  fftw_destroy_plan(plan);
end;

function DCT1(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_REDFT00);
end;

function DCT2(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_REDFT10);
end;

function DCT3(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_REDFT01);
end;

function DCT4(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_REDFT11);
end;

function DST1(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_RODFT00);
end;

function DST2(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_RODFT10);
end;

function DST3(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_RODFT01);
end;

function DST4(const A: TVMobj): TVMobj;
begin
  result := r2rTransform(A, FFTW_RODFT11);
end;

end.
