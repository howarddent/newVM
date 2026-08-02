unit newVMSingle;

{*******************************************************************************

     Vector / Matrix objects leveraging intel mkl libraries (SINGLE PRECISION)

     Derived from newVM.pas (double precision original by Dr H. Dent,
     howard@hgrd.co.uk, 29 July 2026). Adapted for 32-bit float data using
     the MKL "S" (single-precision real) BLAS/LAPACK/VSL routines.

     Inspired by Dew MtxVec Library for fpc but does not distinguish
     between matrix and vector objects. Vectors are column dimension (*,1)
     or row dimension (1,*).

     NOTE: function names below (cblas_sgemm, lapacke_slaset, lapacke_sgesv,
     LAPACKE_slacpy, vsRngGaussian) are the standard MKL single-precision
     ("s") analogues of the "d" routines used in newVM.pas. Verify these
     are declared with matching names/signatures in your cblas / OneAPI
     Pascal bindings before compiling - if your bindings use different
     casing or parameter conventions, adjust the calls accordingly.

     OPERATOR OVERLOADS (algebraic expressions on TVMobjS) - the single-
     precision analogue of the ones added to newVM.pas: '+'/'-' element-
     wise via cblas_saxpy, unary '-' via cblas_sscal, '*' between two
     TVMobjS is matrix multiplication (delegates to MatMultS), and '*'/'/'
     against a Single scalar scale via cblas_sscal / IPP's ippsDivC_32f_I.

*******************************************************************************}

{$mode Delphi}{$H+}
{$Align 8}
{$Linklib 'mkl_rt.so'}
{$Linklib 'pthread'}
{$Linklib 'm'}
{$Linklib 'dl'}
//mkl_rt.so dlopen's libmkl_core.so (and friends) at runtime, which
//expects libm/pthread/dl to already be loaded into the process's
//global symbol table - without this you get errors like:
//  symbol lookup error: .../libmkl_core.so: undefined symbol: log10

interface

uses
  Classes, SysUtils, cblas, math, TestRegistry, OneAPI, Types;

Const
  MaxDimS = 65536;    //maximum dimensions of any array

Type
  TDimS = 0..MaxDimS-1;
  TDataSizeS = 1..MaxDimS*MaxDimS;
  TVectorS = Array of Single;   //maximum dimensions of any array


type

  { TVMobjS }

  TVMobjS = record
    private
      fData : TVectorS;  //Holds data for object
      frows, fcols : TDimS;
      function getelement(r,c: TDimS): Single;
      procedure setelement(r,c: TDimS; AValue: Single);
    public
      constructor create(r,c :TDimS);Overload;
      Constructor create(r,c: TDimS; const Values : TVectorS); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDimS]:Single read getelement write setelement; default;
      procedure fillRandom;
      procedure Id;
      function DataPtr: PSingle;                  //raw buffer, for MKL interop from other units
      property Rows: TDimS read frows;             //read-only dimension accessors
      property Cols: TDimS read fcols;

      { Operator overloads - see OPERATOR OVERLOADS note in the header above.
        Mode Delphi only supports operator overloading as "class operator"
        members of the record. }
      class operator +(const A, B: TVMobjS): TVMobjS;
      class operator -(const A, B: TVMobjS): TVMobjS;
      class operator -(const A: TVMobjS): TVMobjS;
      class operator *(const A, B: TVMobjS): TVMobjS;
      class operator *(const A: TVMobjS; const k: Single): TVMobjS;
      class operator *(const k: Single; const A: TVMobjS): TVMobjS;
      class operator /(const A: TVMobjS; const k: Single): TVMobjS;
      class operator =(const A, B: TVMobjS): Boolean;
  end;

function calcoffsetS(r,c,cols :TDimS):integer;inline;
function MatMultS( const A, B: TVMObjS): TVMobjS;
function LinearSolveS(var A, B: TVMObjS):integer;
function CopyObjS(Const A : TVMObjS):TVMobjS;

{ Elementwise transcendental/algebraic functions, via MKL VML (vs* routines
  in OneAPI.pas). Each returns a new TVMobjS of the same dimensions as A,
  with the function applied to every element. Marked "overload" since
  Sin/Cos/Sqr/Sqrt/Exp/Ln also exist in System/Math for plain numeric
  types - without "overload" the TVMobjS versions here would hide those
  entirely within this unit, breaking any plain Sqrt(x: Single) call. }
function Sin(const A: TVMobjS): TVMobjS; overload;
function Cos(const A: TVMobjS): TVMobjS; overload;
function Tan(const A: TVMobjS): TVMobjS; overload;
function Sinh(const A: TVMobjS): TVMobjS; overload;
function Sqr(const A: TVMobjS): TVMobjS; overload;
function Sqrt(const A: TVMobjS): TVMobjS; overload;
function Exp(const A: TVMobjS): TVMobjS; overload;
function Ln(const A: TVMobjS): TVMobjS; overload;

implementation

function calcoffsetS(r, c, cols: TDimS): integer;
begin
  result := r*cols+c;
end;

{ TVMobjS }

function TVMobjS.getelement(r,c: TDimS): Single;
var
   Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in getelement');
   Ix := calcoffsetS(r,c,cols);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobjS.setelement(r,c:TDimS; AValue: Single);
var
 Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in setelement');
   Ix := calcoffsetS(r,c,cols);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobjS.create(r,c :TDimS);
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

constructor TVMobjS.create(r,c : TDimS; const Values: TVectorS);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  frows := r;
  fcols := c;
  fdata := copy(Values,0,high(values)+1);
end;

function TVMobjS.writeMatrix: TStringList;
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

procedure TVMobjS.fillRandom;
//
// Single-precision Gaussian RNG. vsRngGaussian is the MKL VSL
// single-precision counterpart to vdRngGaussian used in newVM.pas.
//
const
  vslConst = 8388608;
  VSL_RNG_METHOD_GAUSSIAN_ICDF = 2;
var
  vsSTream : pointer;
begin
  vslNewStream(@vsStream,vslConst,777);
  vsRngGaussian(VSL_RNG_METHOD_GAUSSIAN_ICDF,vsStream,high(fdata)+1,@Fdata[0],0,1);
  vsldeleteStream(@vsStream);
end;

procedure TVMobjS.Id;
const
  s : string = 'Routine Id :';
begin
  //Check dimensions of matrices are compatible. A must be square
  assert(cols=rows,s +'Matrix A must be square');
  lapacke_slaset(CBlasRowMajor,'A',rows,cols,0,1,@Fdata[0],rows);
end;

function TVMobjS.DataPtr: PSingle;
begin
  result := @fdata[0];
end;



function MatMultS(const A, B: TVMObjS): TVMobjS;
const
  s : String = 'Routine MatMultS :';
var
  m,n,k : integer;
  C : TVMObjS;
begin
  m := A.Rows;
  n := B.Cols;
  k := A.Cols;
  //Check for compatibility of matrices
  assert(A.cols = B.rows,s+'columns of first matrix must equal rows of second');
  c := TVMObjS.Create(m,n);
  cblas_sgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
              m,n,k, { m, n, k }
              1,     { alpha   }
                @A.FData[0], k,
                @B.Fdata[0], n,
              1, {beta}
                @C.Fdata[0],n
             );
    result := C;
end;

function LinearSolveS(var A, B: TVMObjS):integer;
const
  s : String = 'Function LinearSolveS : ';
var
  ipiv : array of integer;
{ Direct linear solve for matrix A and Vectors B. On return A is in LU
  factored form and solution matrix is in B. Returns info from Lapacke}
begin
  assert(A.Cols = A.Rows,s+'Matrix A must be square');
  assert(A.Rows = B.Rows, s+'Matrix A and B have incompatible dimensions');
  setlength(ipiv,A.rows);
  LinearSolveS:= lapacke_sgesv(CBlasRowMajor,A.rows,B.cols,@A.Fdata[0],A.cols,@ipiv[0],@B.FData[0],B.cols);
end;

function CopyObjS(const A: TVMObjS): TVMobjS;
begin
  result := TVMObjS.Create(A.rows,A.cols);
  LAPACKE_slacpy(CBlasRowMajor,'A',A.rows,A.cols,@A.Fdata[0],a.cols,@result.fdata[0],result.cols);
end;

class operator TVMobjS.+(const A, B: TVMobjS): TVMobjS;
const
  s : String = 'Operator + (TVMobjS) : ';
begin
  assert((A.Rows=B.Rows) and (A.Cols=B.Cols), s+'matrix dimensions must match');
  result := CopyObjS(B);
  cblas_saxpy(A.Rows*A.Cols, 1, A.DataPtr, 1, result.DataPtr, 1);
end;

class operator TVMobjS.-(const A, B: TVMobjS): TVMobjS;
const
  s : String = 'Operator - (TVMobjS) : ';
begin
  assert((A.Rows=B.Rows) and (A.Cols=B.Cols), s+'matrix dimensions must match');
  result := CopyObjS(A);
  cblas_saxpy(A.Rows*A.Cols, -1, B.DataPtr, 1, result.DataPtr, 1);
end;

class operator TVMobjS.-(const A: TVMobjS): TVMobjS;
begin
  result := CopyObjS(A);
  cblas_sscal(A.Rows*A.Cols, -1, result.DataPtr, 1);
end;

class operator TVMobjS.*(const A, B: TVMobjS): TVMobjS;
begin
  result := MatMultS(A, B);
end;

class operator TVMobjS.*(const A: TVMobjS; const k: Single): TVMobjS;
begin
  result := CopyObjS(A);
  cblas_sscal(A.Rows*A.Cols, k, result.DataPtr, 1);
end;

class operator TVMobjS.*(const k: Single; const A: TVMobjS): TVMobjS;
begin
  result := A * k;
end;

class operator TVMobjS./(const A: TVMobjS; const k: Single): TVMobjS;
const
  s : String = 'Operator / (TVMobjS) : ';
begin
  assert(k<>0, s+'division by zero');
  result := CopyObjS(A);
  ippsDivC_32f_I(k, result.DataPtr, A.Rows*A.Cols);
end;

class operator TVMobjS.=(const A, B: TVMobjS): Boolean;
begin
  Result := (A.Rows = B.Rows) and (A.Cols = B.Cols) and
            CompareMem(A.DataPtr, B.DataPtr, A.Rows*A.Cols*SizeOf(Single));
end;

function Sin(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsSin(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Cos(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsCos(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Tan(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsTan(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sinh(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsSinh(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sqr(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsSqr(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Sqrt(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsSqrt(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Exp(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsExp(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

function Ln(const A: TVMobjS): TVMobjS;
begin
  result := TVMobjS.Create(A.Rows, A.Cols);
  vsLn(A.Rows*A.Cols, A.DataPtr, result.DataPtr);
end;

end.
