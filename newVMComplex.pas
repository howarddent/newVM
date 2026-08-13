unit newVMComplex;

{*******************************************************************************

     Vector / Matrix objects leveraging intel mkl libraries (COMPLEX DOUBLE)

     Derived from newVM.pas (double precision original by Dr H. Dent,
     howard@hgrd.co.uk, 29 July 2026). Adapted for double-precision complex
     data using the MKL "Z" (double-precision complex) BLAS/LAPACK routines
     (the complex analogue of MKL_Complex16 / C's double _Complex).

     Inspired by Dew MtxVec Library for fpc but does not distinguish
     between matrix and vector objects. Vectors are column dimension (*,1)
     or row dimension (1,*).

     IMPORTANT ASSUMPTIONS - please verify against your actual bindings:

     1) TComplex16 below is a plain {re,im: Double} record chosen to match
        the memory layout of MKL_Complex16 (two contiguous IEEE-754
        doubles). If your OneAPI/cblas unit already declares MKL_Complex16
        (commonly with fields named "real"/"imag" rather than "re"/"im"),
        prefer that existing type instead of TComplex16 so the ABI matches
        exactly what the linked mkl_rt.so expects, and rename fields
        throughout this file accordingly.

     2) cblas_zgemm expects alpha/beta as pointers to a complex scalar
        (matching the CBLAS C convention `const void *alpha`), so alpha
        and beta are passed as @alpha/@beta here - unlike the real gemm
        routines which take alpha/beta by value.

     3) lapacke_zlaset takes its alpha/beta (off-diagonal/diagonal fill
        values) by value as complex scalars, matching the LAPACKE C
        signature - passed directly (not by pointer) here.

     4) MKL's VSL does not provide a complex Gaussian generator. fillRandom
        instead reinterprets the complex data buffer as a double array of
        twice the length (valid because TComplex16 is exactly two
        contiguous doubles) and calls vdRngGaussian once, filling both the
        real and imaginary parts with independent N(0,1) samples.

     Confirm function names/casing (cblas_zgemm, lapacke_zlaset,
     lapacke_zgesv, LAPACKE_zlacpy) match your cblas / OneAPI bindings.

     OPERATOR OVERLOADS (algebraic expressions on TVMobjZ):
       - '+' and '-' are element-wise, via cblas_zaxpy (alpha passed by
         pointer, per the CBLAS complex convention).
       - unary '-' negates via cblas_zdscal - MKL's "scale a complex
         vector by a real scalar" routine, used here with -1.
       - '*' between two same-type TVMobjZ is ELEMENT-WISE multiplication,
         delegating to MulObjZ (MKL VML's vzMul) - NOT matrix
         multiplication; use MatMultZ (cblas_zgemm) explicitly for a real
         matrix product.
       - '*' and '/' accept either a TComplex16 scalar (cblas_zscal) or a
         plain Double scalar (cblas_zdscal); division computes the scalar
         reciprocal in Pascal first, since there is no BLAS "divide by
         scalar" primitive.
       - mixed-type '+' and '-' against a real TVMobj promote the real
         operand to complex via RealToComplex, then delegate to the
         TVMobjZ operators above - so e.g.  Z := R + I;  (real matrix plus
         a complex identity) works without an explicit cast. Mixed-type
         '*' does NOT follow that pattern: TVMobjZ*TVMobj and
         TVMobj*TVMobjZ both call MatMultZ (real matrix multiplication)
         directly, not MulObjZ - so same-type Z*Z is element-wise but
         mixed-type Z*R/R*Z is a genuine matrix product (this is
         deliberately exercised by newVMTests.pas's
         TestEigDecomposeSatisfiesEigenEquation, via "Av := A * vcol"
         for the real eigenvector matrix A and complex eigenvector
         vcol). Know which one you're calling at each site - the two
         forms are not interchangeable despite looking identical.

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
  Classes, SysUtils, cblas, math, TestRegistry, OneAPI, Types, newVM, fftw3;

Const
  MaxDimZ = 65536;    //maximum dimensions of any array

Type
  TDimZ = 0..MaxDimZ-1;
  TDataSizeZ = 1..MaxDimZ*MaxDimZ;

  //Double precision complex scalar - layout matches MKL_Complex16
  //(two contiguous doubles). Rename to match your bindings if they
  //already declare an equivalent type - see header notes above.
  {TComplex16 = record
    re, im : Double;
  end; }

  TVectorZ = Array of TComplex16;   //maximum dimensions of any array


type

  { TVMobjZ }

  TVMobjZ = record
    private
      fData : TVectorZ;  //Holds data for object
      frows, fcols : TDimZ;
      fIpiv : array of Integer;  //cached LU pivot indices from LinearSolveZ, valid iff fLUFactored
      fLUFactored : Boolean;     //True once LinearSolveZ has LU-factorised this object in place (see LinearSolveZ)
      function getelement(r,c: TDimZ): TComplex16;
      procedure setelement(r,c: TDimZ; AValue: TComplex16);
    public
      constructor create(r,c :TDimZ);Overload;
      Constructor create(r,c: TDimZ; const Values : TVectorZ); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDimZ]:TComplex16 read getelement write setelement; default;
      procedure fillRandom;
      procedure Id;
      procedure linspace(Start, increment: TComplex16);
      function Transpose: TVMObjZ;
      property Rows: TDimZ read frows;              //read-only dimension accessors
      property Cols: TDimZ read fcols;
      property LU: Boolean read fLUFactored;  //True once LinearSolveZ has cached an LU factorisation of this object

      { Operator overloads - see OPERATOR OVERLOADS note in the header above.
        Mode Delphi only supports operator overloading as "class operator"
        members of the record. The mixed real/complex forms are declared
        here (rather than on TVMobj in newVM.pas) because TVMobjZ is the
        common operand in all of them, and only this unit sees both types. }
      class operator +(const A, B: TVMobjZ): TVMobjZ;
      class operator -(const A, B: TVMobjZ): TVMobjZ;
      class operator -(const A: TVMobjZ): TVMobjZ;
      class operator *(const A, B: TVMobjZ): TVMobjZ;
      class operator *(const A: TVMobjZ; const k: TComplex16): TVMobjZ;
      class operator *(const k: TComplex16; const A: TVMobjZ): TVMobjZ;
      class operator *(const A: TVMobjZ; const k: Double): TVMobjZ;
      class operator *(const k: Double; const A: TVMobjZ): TVMobjZ;
      class operator /(const A: TVMobjZ; const k: TComplex16): TVMobjZ;
      class operator /(const A: TVMobjZ; const k: Double): TVMobjZ;
      class operator +(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
      class operator +(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
      class operator -(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
      class operator -(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
      class operator *(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
      class operator *(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
      class operator =(const A, B: TVMobjZ): Boolean;
  end;

function calcoffsetZ(r,c,cols :TDimZ):integer;inline;
function MatMultZ( const A, B: TVMObjZ): TVMobjZ;
function LinearSolveZ(var A, B: TVMObjZ):integer;
function CopyObjZ(Const A : TVMObjZ):TVMobjZ;
function InvertZ(const A: TVMobjZ): TVMobjZ;  //matrix inverse, via LAPACKE_zgetrf+zgetri; leaves A untouched
function KronZ(const A, B: TVMobjZ): TVMobjZ;  //Kronecker product - see Kron in newVM.pas
function DiagZ(const A: TVMobjZ): TVMobjZ;  //column vector (n,1) -> (n,n) diagonal matrix - see Diag in newVM.pas
function NormZ(const A: TVMobjZ): Double;  //Euclidean norm (real-valued), via cblas_dznrm2 - see Norm in newVM.pas
function TraceZ(const A: TVMobjZ): TComplex16;  //sum of A's leading-diagonal elements - see Trace in newVM.pas
function DetZ(const A: TVMobjZ): TComplex16;  //determinant, via LAPACKE_zgetrf - see Det in newVM.pas
function FlipUDZ(const A: TVMobjZ): TVMobjZ;  //reverses row order - see FlipUD in newVM.pas
function FlipLRZ(const A: TVMobjZ): TVMobjZ;  //reverses each row's element order, via ippsFlip_64fc - see FlipLR in newVM.pas
function MergeUDZ(const A, B: TVMobjZ): TVMobjZ;  //stacks A above B - see MergeUD in newVM.pas
function MergeLRZ(const A, B: TVMobjZ): TVMobjZ;  //places A left of B - see MergeLR in newVM.pas
function ReshapeZ(const A: TVMobjZ; NewRows, NewCols: TDimZ): TVMobjZ;  //reinterprets A's elements with new dims - see Reshape in newVM.pas
function RepmatZ(const A: TVMobjZ; RowReps, ColReps: Integer): TVMobjZ;  //tiles A RowReps x ColReps - see Repmat in newVM.pas
function Cplx(re,im : Double): TComplex16;inline;
function RealToComplex(const A : TVMobj): TVMobjZ;    //promotes a real double TVMobj to a complex TVMobjZ, im = 0
function GetRealPart(const A : TVMobjZ): TVMobj;      //extracts the real component of A into a real double TVMobj
function GetImagPart(const A : TVMobjZ): TVMobj;      //extracts the imaginary component of A into a real double TVMobj
procedure SplitComplex(const A : TVMobjZ; out RealPart, ImagPart: TVMobj); //convenience: both parts in one call
procedure EigDecompose(const A : TVMobj; out EigenValues, EigenVectors: TVMobjZ); //eigenvalues/(right) eigenvectors of a real square matrix, via LAPACKE_dgeev

{ Elementwise transcendental/algebraic functions, via MKL VML (vz* routines
  in OneAPI.pas - complex-valued, principal-branch results). Each returns a
  new TVMobjZ of the same dimensions as A, with the function applied to
  every element. Marked "overload" since Sin/Cos/Sqr/Sqrt/Exp/Ln also exist
  in System/Math for plain numeric types - without "overload" the TVMobjZ
  versions here would hide those entirely within this unit. }
function Sin(const A: TVMobjZ): TVMobjZ; overload;
function Cos(const A: TVMobjZ): TVMobjZ; overload;
function Tan(const A: TVMobjZ): TVMobjZ; overload;
function Sinh(const A: TVMobjZ): TVMobjZ; overload;
function Sqr(const A: TVMobjZ): TVMobjZ; overload;
function Sqrt(const A: TVMobjZ): TVMobjZ; overload;
function Exp(const A: TVMobjZ): TVMobjZ; overload;
function Ln(const A: TVMobjZ): TVMobjZ; overload;
function MulObjZ(const A, B: TVMObjZ): TVMobjZ;

{ Real<->complex and complex<->complex 1D FFTs, via FFTW3 (fftw3.pas) on
  the double-precision library. All vector-only (Rows=1 or Cols=1, result
  keeps A's orientation); input is never mutated (FFTW_PRESERVE_INPUT).
  FFT_R2C's result is FFTW's packed half-spectrum, length N div 2 + 1 (the
  upper half is redundant for real input by conjugate symmetry); FFT_C2R
  needs the target real length N explicitly, since N div 2 + 1 alone
  doesn't determine whether N was even or odd. Unlike raw FFTW (which is
  unnormalized), FFT_C2R and IFFT here divide by N, so
  FFT_C2R(FFT_R2C(x), N) = x and IFFT(FFT(x)) = x. Marked "overload" since
  newVMComplexSingle.pas declares the TVMobjS/TVMobjC analogues of these
  same names. }
function FFT_R2C(const A: TVMobj): TVMobjZ; overload;         //real -> packed half-spectrum
function FFT_C2R(const A: TVMobjZ; N: Integer): TVMobj; overload; //packed half-spectrum -> real, normalized
function FFT(const A: TVMobjZ): TVMobjZ; overload;             //complex -> complex, forward
function IFFT(const A: TVMobjZ): TVMobjZ; overload;            //complex -> complex, inverse, normalized

implementation

function Cplx(re,im: Double): TComplex16;
begin
  result.re := re;
  result.im := im;
end;

function calcoffsetZ(r, c, cols: TDimZ): integer;
begin
  result := r*cols+c;
end;

{ TVMobjZ }

function TVMobjZ.getelement(r,c: TDimZ): TComplex16;
var
   Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in getelement');
   Ix := calcoffsetZ(r,c,cols);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobjZ.setelement(r,c:TDimZ; AValue: TComplex16);
var
 Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in setelement');
   Ix := calcoffsetZ(r,c,cols);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobjZ.create(r,c :TDimZ);
var
  i,N : integer;
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  frows := r;
  fcols := c;
  N := r*c;
  setLength(fData,N);
  for i := low(fdata) to high(fdata) do fdata[i] := Cplx(0,0);
  fLUFactored := False;
end;

constructor TVMobjZ.create(r,c : TDimZ; const Values: TVectorZ);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  frows := r;
  fcols := c;
  fdata := copy(Values,0,high(values)+1);
  fLUFactored := False;
end;

function TVMobjZ.writeMatrix: TStringList;
const
  fieldwidth = 22;
var
   i,j,k,l: integer;
   s,t : String;
   v : TComplex16;
begin
  result:= TStringList.create;
  for i:=0 to rows-1 do begin // row by row
    s := '    ['+chr(9);
    for j:=0 to cols-1 do begin
      v := FData[i*cols+j];
      t := floatToStrf(v.re,fffixed,10,3);
      if v.im >= 0 then
        t := t + '+' + floatToStrf(v.im,fffixed,10,3) + 'i'
      else
        t := t + '-' + floatToStrf(abs(v.im),fffixed,10,3) + 'i';
      s := s + t;
      l := length(t);    // pad t to get constant length
     if l < fieldwidth then
      for k := 1 to fieldwidth-l do s := s +' ';
    end;
    s := s+']';
    result.add(s);
  end;
end;

procedure TVMobjZ.fillRandom;
//
// MKL's VSL RNG functions only generate real-valued distributions -
// there is no complex Gaussian generator. Because TComplex16 is laid
// out as two contiguous doubles (re, im), we reinterpret the complex
// buffer as a plain double array of twice the length and fill it with
// vdRngGaussian in a single call - this fills both the real and
// imaginary parts with independent N(0,1) samples.
//
const
  vslConst = 8388608;
  VSL_RNG_METHOD_GAUSSIAN_ICDF = 2;
var
  vsSTream : pointer;
  n : integer;
begin
  n := (high(fdata)+1)*2; //2 doubles per complex element
  vslNewStream(@vsStream,vslConst,777);
  vdRngGaussian(VSL_RNG_METHOD_GAUSSIAN_ICDF,vsStream,n,PDouble(@Fdata[0]),0,1);
  vsldeleteStream(@vsStream);
end;

procedure TVMobjZ.Id;
const
  s : string = 'Routine Id :';
var
  zero, one : TComplex16;
begin
  //Check dimensions of matrices are compatible. A must be square
  assert(cols=rows,s +'Matrix A must be square');
  zero := Cplx(0,0);
  one  := Cplx(1,0);
  lapacke_zlaset(CBlasRowMajor,'A',rows,cols,zero,one,@Fdata[0],rows);
end;

procedure TVMobjZ.linspace(Start, increment: TComplex16);
const
  s : String ='routine linspace';
var
  i : integer;
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  //IPP has no complex VectorSlope (ippsVectorSlope_64fc isn't exported by
  //libipps - only the real forms are), so build the arithmetic sequence
  //directly: FData[i] = Start + i*increment.
  for i := 0 to high(fdata) do
    FData[i] := Cplx(start.re + i*increment.re, start.im + i*increment.im);
end;

function TVMobjZ.Transpose:TVMObjZ;
var
  temp : TDimZ;
begin
  result := copyobjZ(self);
  MKL_Zimatcopy('R','T',rows,cols,Cplx(1,0),@result.FData[0],cols,rows);
//swap row and column numbers
  temp := self.rows;
  result.frows := self.cols;
  result.fcols := temp;
end;

function MatMultZ(const A, B: TVMObjZ): TVMobjZ;
const
  s : String = 'Routine MatMultZ :';
var
  m,n,k : integer;
  C : TVMObjZ;
  alpha, beta : TComplex16;
begin
  m := A.Rows;
  n := B.Cols;
  k := A.Cols;
  //Check for compatibility of matrices
  assert(A.cols = B.rows,s+'columns of first matrix must equal rows of second');
  c := TVMObjZ.Create(m,n);
  alpha := Cplx(1,0);
  beta  := Cplx(1,0);
  cblas_zgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
              m,n,k, { m, n, k }
              @alpha,  { alpha - by pointer, per CBLAS complex convention }
                @A.FData[0], k,
                @B.Fdata[0], n,
              @beta, {beta}
                @C.Fdata[0],n
             );
    result := C;
end;

function LinearSolveZ(var A, B: TVMObjZ):integer;
const
  s : String = 'Function LinearSolveZ : ';
{ Direct linear solve for matrix A and Vectors B. On the first call for a
  given A, this LU-factorises A in place and solves for B via the combined
  LAPACKE_zgesv, caching the pivot indices on A and setting A.LU := True.
  A subsequent call against the same (already-factorised) A skips
  re-factorisation and reuses the cached LU factors/pivots via the cheaper
  LAPACKE_zgetrs (solve only) - much less work when the same A is solved
  against several different B's in turn. On return, A holds its LU-factored
  form (not the original matrix) and the solution is in B. Returns info
  from the underlying LAPACKE call. }
begin
  assert(A.Cols = A.Rows,s+'Matrix A must be square');
  assert(A.Rows = B.Rows, s+'Matrix A and B have incompatible dimensions');
  if A.LU then
    result := lapacke_zgetrs(CBlasRowMajor,'N',A.rows,B.cols,@A.Fdata[0],A.cols,@A.fIpiv[0],@B.FData[0],B.cols)
  else begin
    setlength(A.fIpiv,A.rows);
    result := lapacke_zgesv(CBlasRowMajor,A.rows,B.cols,@A.Fdata[0],A.cols,@A.fIpiv[0],@B.FData[0],B.cols);
    if result = 0 then A.fLUFactored := True;
  end;
end;

function CopyObjZ(const A: TVMObjZ): TVMobjZ;
begin
  result := TVMObjZ.Create(A.rows,A.cols);
  LAPACKE_zlacpy(CBlasRowMajor,'A',A.rows,A.cols,@A.Fdata[0],a.cols,@result.fdata[0],result.cols);
end;

function InvertZ(const A: TVMobjZ): TVMobjZ;
const
  s : String = 'Function InvertZ : ';
var
  ipiv : array of integer;
  info : integer;
{ Matrix inverse via LAPACKE_zgetrf (LU factorisation) followed by
  LAPACKE_zgetri (inverse from the LU factors), on a CopyObjZ scratch
  buffer - both LAPACKE calls overwrite their input matrix in place,
  so A itself is left untouched. }
begin
  assert(A.Cols = A.Rows, s+'Matrix A must be square');
  result := CopyObjZ(A);
  setlength(ipiv, A.rows);
  info := lapacke_zgetrf(CBlasRowMajor, A.rows, A.cols, @result.Fdata[0], A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_zgetrf failed (singular matrix?), info='+IntToStr(info));
  info := lapacke_zgetri(CBlasRowMajor, A.rows, @result.Fdata[0], A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_zgetri failed (singular matrix?), info='+IntToStr(info));
end;

function KronZ(const A, B: TVMobjZ): TVMobjZ;
var
  i, j, k, rowdest, coldest : integer;
  aval : TComplex16;
begin
  result := TVMobjZ.Create(A.Rows*B.Rows, A.Cols*B.Cols);
  for i := 0 to A.Rows-1 do
    for j := 0 to A.Cols-1 do begin
      aval := A[i,j];
      for k := 0 to B.Rows-1 do begin
        rowdest := i*B.Rows + k;
        coldest := j*B.Cols;
        cblas_zaxpy(B.Cols, @aval, @B.FData[k*B.Cols], 1, @result.FData[rowdest*result.Cols + coldest], 1);
      end;
    end;
end;

function DiagZ(const A: TVMobjZ): TVMobjZ;
const
  s : String = 'Function DiagZ : ';
begin
  assert(A.Cols = 1, s+'A must be a column vector (n,1)');
  result := TVMobjZ.Create(A.Rows, A.Rows);
  cblas_zcopy(A.Rows, @A.FData[0], 1, @result.FData[0], A.Rows+1);
end;

function NormZ(const A: TVMobjZ): Double;
const
  s : String = 'Function NormZ : ';
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  result := cblas_dznrm2(A.Rows*A.Cols, @A.FData[0], 1);
end;

function TraceZ(const A: TVMobjZ): TComplex16;
const
  s : String = 'Function TraceZ : ';
var
  i : integer;
begin
  assert(A.Rows = A.Cols, s+'Matrix A must be square');
  result.re := 0;
  result.im := 0;
  for i := 0 to A.Rows-1 do begin
    result.re := result.re + A[i,i].re;
    result.im := result.im + A[i,i].im;
  end;
end;

function DetZ(const A: TVMobjZ): TComplex16;
const
  s : String = 'Function DetZ : ';
var
  ipiv : array of integer;
  info, i, sign : integer;
  scratch : TVMobjZ;
  d : TComplex16;
begin
  assert(A.Cols = A.Rows, s+'Matrix A must be square');
  scratch := CopyObjZ(A);
  setlength(ipiv, A.rows);
  info := lapacke_zgetrf(CBlasRowMajor, A.rows, A.cols, @scratch.Fdata[0], A.cols, @ipiv[0]);
  assert(info >= 0, s+'LAPACKE_zgetrf reported an illegal argument, info='+IntToStr(info));
  sign := 1;
  for i := 0 to A.rows-1 do
    if ipiv[i] <> i+1 then sign := -sign;
  result := Cplx(sign, 0);
  for i := 0 to A.rows-1 do begin
    d := scratch[i,i];
    result := Cplx(result.re*d.re - result.im*d.im, result.re*d.im + result.im*d.re);
  end;
end;

function FlipUDZ(const A: TVMobjZ): TVMobjZ;
var
  i : integer;
begin
  result := TVMobjZ.Create(A.Rows, A.Cols);
  for i := 0 to A.Rows-1 do
    cblas_zcopy(A.Cols, @A.FData[i*A.Cols], 1, @result.FData[(A.Rows-1-i)*A.Cols], 1);
end;

function FlipLRZ(const A: TVMobjZ): TVMobjZ;
var
  i : integer;
begin
  result := TVMobjZ.Create(A.Rows, A.Cols);
  for i := 0 to A.Rows-1 do
    ippsFlip_64fc(@A.FData[i*A.Cols], @result.FData[i*A.Cols], A.Cols);
end;

function MergeUDZ(const A, B: TVMobjZ): TVMobjZ;
const
  s : String = 'Function MergeUDZ : ';
begin
  assert(A.Cols = B.Cols, s+'A and B must have the same number of columns');
  result := TVMobjZ.Create(A.Rows+B.Rows, A.Cols);
  cblas_zcopy(A.Rows*A.Cols, @A.FData[0], 1, @result.FData[0], 1);
  cblas_zcopy(B.Rows*B.Cols, @B.FData[0], 1, @result.FData[A.Rows*A.Cols], 1);
end;

function MergeLRZ(const A, B: TVMobjZ): TVMobjZ;
const
  s : String = 'Function MergeLRZ : ';
var
  i : integer;
begin
  assert(A.Rows = B.Rows, s+'A and B must have the same number of rows');
  result := TVMobjZ.Create(A.Rows, A.Cols+B.Cols);
  for i := 0 to A.Rows-1 do begin
    cblas_zcopy(A.Cols, @A.FData[i*A.Cols], 1, @result.FData[i*result.Cols], 1);
    cblas_zcopy(B.Cols, @B.FData[i*B.Cols], 1, @result.FData[i*result.Cols + A.Cols], 1);
  end;
end;

function ReshapeZ(const A: TVMobjZ; NewRows, NewCols: TDimZ): TVMobjZ;
const
  s : String = 'Function ReshapeZ : ';
begin
  assert(NewRows*NewCols = A.Rows*A.Cols, s+'NewRows*NewCols must equal A.Rows*A.Cols');
  result := TVMobjZ.Create(NewRows, NewCols);
  cblas_zcopy(A.Rows*A.Cols, @A.FData[0], 1, @result.FData[0], 1);
end;

function RepmatZ(const A: TVMobjZ; RowReps, ColReps: Integer): TVMobjZ;
const
  s : String = 'Function RepmatZ : ';
var
  i, j, r, destRow : integer;
begin
  assert((RowReps > 0) and (ColReps > 0), s+'RowReps and ColReps must be > 0');
  result := TVMobjZ.Create(A.Rows*RowReps, A.Cols*ColReps);
  for i := 0 to RowReps-1 do
    for r := 0 to A.Rows-1 do begin
      destRow := i*A.Rows + r;
      for j := 0 to ColReps-1 do
        cblas_zcopy(A.Cols, @A.FData[r*A.Cols], 1, @result.FData[destRow*result.Cols + j*A.Cols], 1);
    end;
end;

function RealToComplex(const A: TVMobj): TVMobjZ;
const
  s : String = 'Routine RealToComplex : ';
var
  n : integer;
begin
  //A is a real double TVMobj (from newVM.pas); result is the same
  //dimensions as a complex TVMobjZ with imaginary parts all zero.
  n := A.Rows * A.Cols;
  result := TVMObjZ.Create(A.Rows, A.Cols);  //zero-fills both re and im
  //TComplex16 = {re,im: Double} packed as two contiguous doubles per
  //element, so result.FData viewed as a flat double array has real
  //parts at even offsets (0,2,4,...) and imaginary parts at odd offsets.
  //cblas_dcopy with a destination stride of 2 writes only into the real
  //slots; the imaginary slots are left at the zero the constructor set.
  //A.DataPtr (public accessor added to TVMobj) supplies the source
  //buffer without needing friend access to newVM's private fields.
  cblas_dcopy(n, A.DataPtr, 1, PDouble(@result.FData[0]), 2);
end;

function GetRealPart(const A: TVMobjZ): TVMobj;
begin
  //A.FData, viewed as a flat double array, has real parts at even
  //offsets (0,2,4,...). cblas_dcopy with a source stride of 2, starting
  //at offset 0, pulls out every real component into a contiguous,
  //ordinary TVMobj buffer (destination stride 1) - no per-element loop.
  result := TVMobj.Create(A.rows, A.cols);
  cblas_dcopy(A.rows*A.cols, PDouble(@A.FData[0]), 2, result.DataPtr, 1);
end;

function GetImagPart(const A: TVMobjZ): TVMobj;
var
  pIm : PDouble;
begin
  //Same trick as GetRealPart, but starting one double further in, so
  //the stride-2 walk lands on the imaginary slots (offsets 1,3,5,...)
  //instead of the real ones.
  result := TVMobj.Create(A.rows, A.cols);
  pIm := PDouble(@A.FData[0]);
  inc(pIm);                              //step over the first real slot
  cblas_dcopy(A.rows*A.cols, pIm, 2, result.DataPtr, 1);
end;

procedure SplitComplex(const A: TVMobjZ; out RealPart, ImagPart: TVMobj);
begin
  //Convenience wrapper: two independent MKL dcopy calls, one per part.
  RealPart := GetRealPart(A);
  ImagPart := GetImagPart(A);
end;

procedure EigDecompose(const A: TVMobj; out EigenValues, EigenVectors: TVMobjZ);
const
  s : String = 'Routine EigDecompose : ';
//
// General real nonsymmetric eigenvalue problem, via LAPACKE_dgeev.
// Even for a real A, eigenvalues/eigenvectors can be complex, occurring
// in conjugate pairs - hence the complex TVMobjZ outputs.
//
// EigenValues  : n x 1 TVMobjZ, one eigenvalue per row.
// EigenVectors : n x n TVMobjZ, right eigenvectors as columns (matching
//                the ordering of EigenValues), each normalised to unit
//                Euclidean norm by LAPACK.
//
// LAPACKE_dgeev returns eigenvectors in packed real form: if eigenvalue
// j is real, column j of the raw output IS the eigenvector; if
// eigenvalues j and j+1 are a complex-conjugate pair, column j holds
// the real part and column j+1 holds the imaginary part of both
// v(j) = col(j) + i*col(j+1) and v(j+1) = col(j) - i*col(j+1). This
// routine unpacks that convention into genuinely complex columns.
//
var
  n, i, j, info : integer;
  Acopy : TVMobj;
  wr, wi, vr : TVector;   //TVector = array of Double, exported by newVM
begin
  assert(A.Rows = A.Cols, s+'Matrix A must be square');
  n := A.Rows;

  //LAPACKE_dgeev overwrites its input matrix in place, so run it on a
  //scratch copy and leave the caller's A untouched.
  Acopy := CopyObj(A);

  SetLength(wr, n);
  SetLength(wi, n);
  SetLength(vr, n*n);

  //jobvl = 'N' : left eigenvectors not requested (vl unused -> nil, ldvl=n is a harmless placeholder)
  //jobvr = 'V' : right eigenvectors requested, returned in packed real form in vr
  info := LAPACKE_dgeev(CBlasRowMajor, 'N', 'V', n,
                          Acopy.DataPtr, n,
                          @wr[0], @wi[0],
                          nil, n,
                          @vr[0], n);
  assert(info = 0, s+'LAPACKE_dgeev failed, info='+IntToStr(info));

  //--- eigenvalues: one complex value per row, straight from wr/wi ---
  EigenValues := TVMobjZ.Create(n,1);
  for i := 0 to n-1 do
    EigenValues.FData[i] := Cplx(wr[i], wi[i]);

  //--- eigenvectors: unpack LAPACK's real/imaginary column pairing ---
  EigenVectors := TVMobjZ.Create(n,n);
  j := 0;
  while j <= n-1 do begin
    if wi[j] = 0 then begin
      //real eigenvalue -> column j of vr IS the eigenvector, im = 0
      for i := 0 to n-1 do
        EigenVectors.FData[i*n+j] := Cplx(vr[i*n+j], 0);
      inc(j);
    end else begin
      //complex-conjugate pair sharing columns j (real part) and j+1 (imag part)
      for i := 0 to n-1 do begin
        EigenVectors.FData[i*n+j]   := Cplx(vr[i*n+j],  vr[i*n+j+1]);
        EigenVectors.FData[i*n+j+1] := Cplx(vr[i*n+j], -vr[i*n+j+1]);
      end;
      inc(j,2);
    end;
  end;
end;

function ReciprocalZ(const k: TComplex16): TComplex16;
const
  s : String = 'Operator / (TVMobjZ) : ';
var
  d : Double;
begin
  d := k.re*k.re + k.im*k.im;
  assert(d<>0, s+'division by zero complex scalar');
  result.re :=  k.re/d;
  result.im := -k.im/d;
end;

class operator TVMobjZ.+(const A, B: TVMobjZ): TVMobjZ;
const
  s : String = 'Operator + (TVMobjZ) : ';
var
  one : TComplex16;
begin
  assert((A.rows=B.rows) and (A.cols=B.cols), s+'matrix dimensions must match');
  one := Cplx(1,0);
  result := CopyObjZ(B);
  cblas_zaxpy(A.rows*A.cols, @one, @A.FData[0], 1, @result.FData[0], 1);
end;

class operator TVMobjZ.-(const A, B: TVMobjZ): TVMobjZ;
const
  s : String = 'Operator - (TVMobjZ) : ';
var
  negOne : TComplex16;
begin
  assert((A.rows=B.rows) and (A.cols=B.cols), s+'matrix dimensions must match');
  negOne := Cplx(-1,0);
  result := CopyObjZ(A);
  cblas_zaxpy(A.rows*A.cols, @negOne, @B.FData[0], 1, @result.FData[0], 1);
end;

class operator TVMobjZ.-(const A: TVMobjZ): TVMobjZ;
begin
  result := CopyObjZ(A);
  cblas_zdscal(A.rows*A.cols, -1, @result.FData[0], 1);
end;

class operator TVMobjZ.*(const A, B: TVMobjZ): TVMobjZ;
begin
  result := MulObjZ(A, B);
end;

class operator TVMobjZ.*(const A: TVMobjZ; const k: TComplex16): TVMobjZ;
begin
  result := CopyObjZ(A);
  cblas_zscal(A.rows*A.cols, @k, @result.FData[0], 1);
end;

class operator TVMobjZ.*(const k: TComplex16; const A: TVMobjZ): TVMobjZ;
begin
  result := A * k;
end;

class operator TVMobjZ.*(const A: TVMobjZ; const k: Double): TVMobjZ;
begin
  result := CopyObjZ(A);
  cblas_zdscal(A.rows*A.cols, k, @result.FData[0], 1);
end;

class operator TVMobjZ.*(const k: Double; const A: TVMobjZ): TVMobjZ;
begin
  result := A * k;
end;

class operator TVMobjZ./(const A: TVMobjZ; const k: TComplex16): TVMobjZ;
var
  r : TComplex16;
begin
  r := ReciprocalZ(k);
  result := CopyObjZ(A);
  cblas_zscal(A.rows*A.cols, @r, @result.FData[0], 1);
end;

class operator TVMobjZ./(const A: TVMobjZ; const k: Double): TVMobjZ;
const
  s : String = 'Operator / (TVMobjZ) : ';
begin
  assert(k<>0, s+'division by zero');
  result := CopyObjZ(A);
  cblas_zdscal(A.rows*A.cols, 1/k, @result.FData[0], 1);
end;

class operator TVMobjZ.+(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
begin
  result := A + RealToComplex(B);
end;

class operator TVMobjZ.+(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
begin
  result := RealToComplex(A) + B;
end;

class operator TVMobjZ.-(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
begin
  result := A - RealToComplex(B);
end;

class operator TVMobjZ.-(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
begin
  result := RealToComplex(A) - B;
end;

class operator TVMobjZ.*(const A: TVMobjZ; const B: TVMobj): TVMobjZ;
begin
  result := MatMultZ(A, RealToComplex(B));
end;

class operator TVMobjZ.*(const A: TVMobj; const B: TVMobjZ): TVMobjZ;
begin
  result := MatMultZ(RealToComplex(A), B);
end;

class operator TVMobjZ.=(const A, B: TVMobjZ): Boolean;
begin
  Result := (A.rows = B.rows) and (A.cols = B.cols) and
            CompareMem(@A.FData[0], @B.FData[0], A.rows*A.cols*SizeOf(TComplex16));
end;

function Sin(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzSin(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Cos(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzCos(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Tan(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzTan(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Sinh(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzSinh(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Sqr(const A: TVMobjZ): TVMobjZ;
begin
  //MKL VM has no vzSqr (complex Sqr isn't part of the VM function set,
  //unlike real vdSqr) - so square elementwise via vzMul(A, A) instead.
  result := TVMobjZ.Create(A.rows, A.cols);
  vzMul(A.rows*A.cols, @A.FData[0], @A.FData[0], @result.FData[0]);
end;

function Sqrt(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzSqrt(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Exp(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzExp(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Ln(const A: TVMobjZ): TVMobjZ;
begin
  result := TVMobjZ.Create(A.rows, A.cols);
  vzLn(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function MulObjZ(const A, B: TVMObjZ): TVMobjZ;
const
  s: string ='Routine MulObjZ : ';
begin
  assert((a.rows=b.rows)and(a.cols=b.cols),s+'Dimensions of A and B must be the same');
  result := CopyObjZ(A);
  vzMul(A.rows*A.cols, @A.FData[0], @B.FData[0], @result.FData[0]);
end;

function FFT_R2C(const A: TVMobj): TVMobjZ;
const
  s : String = 'Routine FFT_R2C : ';
var
  n, nc : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftw_plan_dft_r2c_1d), s+'FFTW3 (double) library not loaded');
  nc := n div 2 + 1;
  if A.Cols = 1 then result := TVMobjZ.Create(nc, 1) else result := TVMobjZ.Create(1, nc);
  plan := fftw_plan_dft_r2c_1d(n, A.DataPtr, PComplex16(@result.FData[0]), FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftw_plan_dft_r2c_1d failed');
  fftw_execute_dft_r2c(plan, A.DataPtr, PComplex16(@result.FData[0]));
  fftw_destroy_plan(plan);
end;

function FFT_C2R(const A: TVMobjZ; N: Integer): TVMobj;
const
  s : String = 'Routine FFT_C2R : ';
var
  nc : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  assert(N>0, s+'N must be > 0');
  nc := A.Rows*A.Cols;
  assert(nc = (N div 2 + 1), s+'A''s length must be N div 2 + 1');
  assert(Assigned(fftw_plan_dft_c2r_1d), s+'FFTW3 (double) library not loaded');
  if A.Cols = 1 then result := TVMobj.Create(N, 1) else result := TVMobj.Create(1, N);
  plan := fftw_plan_dft_c2r_1d(N, PComplex16(@A.FData[0]), result.DataPtr, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftw_plan_dft_c2r_1d failed');
  fftw_execute_dft_c2r(plan, PComplex16(@A.FData[0]), result.DataPtr);
  fftw_destroy_plan(plan);
  ippsDivC_64f_I(N, result.DataPtr, N);   //normalize, matching FFT_C2R(FFT_R2C(x), N) = x
end;

function FFT(const A: TVMobjZ): TVMobjZ;
const
  s : String = 'Routine FFT : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftw_plan_dft_1d), s+'FFTW3 (double) library not loaded');
  result := TVMobjZ.Create(A.Rows, A.Cols);
  plan := fftw_plan_dft_1d(n, PComplex16(@A.FData[0]), PComplex16(@result.FData[0]), FFTW_FORWARD, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftw_plan_dft_1d failed');
  fftw_execute_dft(plan, PComplex16(@A.FData[0]), PComplex16(@result.FData[0]));
  fftw_destroy_plan(plan);
end;

function IFFT(const A: TVMobjZ): TVMobjZ;
const
  s : String = 'Routine IFFT : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftw_plan_dft_1d), s+'FFTW3 (double) library not loaded');
  result := TVMobjZ.Create(A.Rows, A.Cols);
  plan := fftw_plan_dft_1d(n, PComplex16(@A.FData[0]), PComplex16(@result.FData[0]), FFTW_BACKWARD, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftw_plan_dft_1d failed');
  fftw_execute_dft(plan, PComplex16(@A.FData[0]), PComplex16(@result.FData[0]));
  fftw_destroy_plan(plan);
  cblas_zdscal(n, 1.0/n, @result.FData[0], 1);  //normalize, matching IFFT(FFT(x)) = x
end;

end.
