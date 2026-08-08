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
{$IFDEF UNIX}
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

interface

uses
  Classes, SysUtils, cblas, math, TestRegistry, OneAPI, Types, fftw3, newVMI;

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
      procedure linspace(Start, increment: Single);
      function Transpose: TVMObjS;
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
function InvertS(const A: TVMobjS): TVMobjS;  //matrix inverse, via LAPACKE_sgetrf+sgetri; leaves A untouched
{ Find - see newVM.pas's Find for the full description. Marked "overload"
  since newVM.pas declares the TVMobj analogue of the same name. }
function Find(const A: TVMobjS; Op: TVMCompareOp; Value: Single): TVMobjI; overload;
function KronS(const A, B: TVMobjS): TVMobjS;  //Kronecker product - see Kron in newVM.pas
function DiagS(const A: TVMobjS): TVMobjS;  //column vector (n,1) -> (n,n) diagonal matrix - see Diag in newVM.pas
function NormS(const A: TVMobjS): Single;  //Euclidean norm - see Norm in newVM.pas
function TraceS(const A: TVMobjS): Single;  //sum of A's leading-diagonal elements - see Trace in newVM.pas

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
function MulObjS(const A, B: TVMObjS): TVMObjS;

{ Real-to-real DCT/DST types I-IV, via FFTW3 (fftw3.pas) r2r transforms on
  the single-precision library - see the matching DCT1..DST4 comment in
  newVM.pas for the shape/mutation/normalization rules, which apply here
  identically. Marked "overload" because newVM.pas declares the TVMobj
  (double) analogues of these same names. }
function DCT1(const A: TVMobjS): TVMobjS; overload;  //FFTW_REDFT00
function DCT2(const A: TVMobjS): TVMobjS; overload;  //FFTW_REDFT10
function DCT3(const A: TVMobjS): TVMobjS; overload;  //FFTW_REDFT01 (inverse of DCT2, up to scale)
function DCT4(const A: TVMobjS): TVMobjS; overload;  //FFTW_REDFT11 (self-inverse, up to scale)
function DST1(const A: TVMobjS): TVMobjS; overload;  //FFTW_RODFT00
function DST2(const A: TVMobjS): TVMobjS; overload;  //FFTW_RODFT10
function DST3(const A: TVMobjS): TVMobjS; overload;  //FFTW_RODFT01 (inverse of DST2, up to scale)
function DST4(const A: TVMobjS): TVMobjS; overload;  //FFTW_RODFT11 (self-inverse, up to scale)

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

procedure TVMobjS.linspace(Start, increment: Single);
const
  s : String ='routine linspace';
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  ippsVectorSlope_32f(@FData[0],high(fdata)+1,start,increment);
end;

function TVMobjS.Transpose:TVMObjS;
var
  temp : TDimS;
begin
  result := copyobjS(self);
  MKL_Simatcopy('R','T',rows,cols,1,result.DataPtr,cols,rows);
//swap row and column numbers
  temp := self.rows;
  result.frows := self.cols;
  result.fcols := temp;
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

function InvertS(const A: TVMobjS): TVMobjS;
const
  s : String = 'Function InvertS : ';
var
  ipiv : array of integer;
  info : integer;
{ Matrix inverse via LAPACKE_sgetrf (LU factorisation) followed by
  LAPACKE_sgetri (inverse from the LU factors), on a CopyObjS scratch
  buffer - both LAPACKE calls overwrite their input matrix in place,
  so A itself is left untouched. }
begin
  assert(A.Cols = A.Rows, s+'Matrix A must be square');
  result := CopyObjS(A);
  setlength(ipiv, A.rows);
  info := lapacke_sgetrf(CBlasRowMajor, A.rows, A.cols, result.DataPtr, A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_sgetrf failed (singular matrix?), info='+IntToStr(info));
  info := lapacke_sgetri(CBlasRowMajor, A.rows, result.DataPtr, A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_sgetri failed (singular matrix?), info='+IntToStr(info));
end;

function Find(const A: TVMobjS; Op: TVMCompareOp; Value: Single): TVMobjI;
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

function KronS(const A, B: TVMobjS): TVMobjS;
var
  i, j, k, rowdest, coldest : integer;
begin
  result := TVMobjS.Create(A.Rows*B.Rows, A.Cols*B.Cols);
  for i := 0 to A.Rows-1 do
    for j := 0 to A.Cols-1 do
      for k := 0 to B.Rows-1 do begin
        rowdest := i*B.Rows + k;
        coldest := j*B.Cols;
        cblas_saxpy(B.Cols, A[i,j], @B.FData[k*B.Cols], 1, @result.FData[rowdest*result.Cols + coldest], 1);
      end;
end;

function DiagS(const A: TVMobjS): TVMobjS;
const
  s : String = 'Function DiagS : ';
begin
  assert(A.Cols = 1, s+'A must be a column vector (n,1)');
  result := TVMobjS.Create(A.Rows, A.Rows);
  cblas_scopy(A.Rows, A.DataPtr, 1, result.DataPtr, A.Rows+1);
end;

function NormS(const A: TVMobjS): Single;
const
  s : String = 'Function NormS : ';
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  result := cblas_snrm2(A.Rows*A.Cols, A.DataPtr, 1);
end;

function TraceS(const A: TVMobjS): Single;
const
  s : String = 'Function TraceS : ';
var
  i : integer;
begin
  assert(A.Rows = A.Cols, s+'Matrix A must be square');
  result := 0;
  for i := 0 to A.Rows-1 do
    result := result + A[i,i];
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
  result := MulObjS(A, B);
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

function MulObjS(const A, B: TVMObjS): TVMObjS;
const
  s: string ='Routine MulObjS : ';
begin
  assert((a.rows=b.rows)and(a.cols=b.cols),s+'Dimensions of A and B must be the same');
  result := CopyObjS(A);
  vsMul(A.rows*A.cols,A.Dataptr,B.DataPtr,Result.DataPtr);
end;

function r2rTransformS(const A: TVMobjS; kind: TFFTW_r2r_kind): TVMobjS;
const
  s : String = 'Routine r2rTransformS : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftwf_plan_r2r_1d), s+'FFTW3 (single) library not loaded');
  result := TVMobjS.Create(A.Rows, A.Cols);
  plan := fftwf_plan_r2r_1d(n, A.DataPtr, result.DataPtr, kind, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftwf_plan_r2r_1d failed');
  fftwf_execute_r2r(plan, A.DataPtr, result.DataPtr);
  fftwf_destroy_plan(plan);
end;

function DCT1(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_REDFT00);
end;

function DCT2(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_REDFT10);
end;

function DCT3(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_REDFT01);
end;

function DCT4(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_REDFT11);
end;

function DST1(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_RODFT00);
end;

function DST2(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_RODFT10);
end;

function DST3(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_RODFT01);
end;

function DST4(const A: TVMobjS): TVMobjS;
begin
  result := r2rTransformS(A, FFTW_RODFT11);
end;

end.
