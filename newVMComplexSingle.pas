unit newVMComplexSingle;

{*******************************************************************************

     Vector / Matrix objects leveraging intel mkl libraries (COMPLEX SINGLE)

     Derived from newVMComplex.pas (double-precision complex). Adapted for
     single-precision complex data using the MKL "C" (single-precision
     complex) BLAS/LAPACK routines - the complex analogue of MKL_Complex8 /
     C's float _Complex. Sibling of newVMSingle.pas (real single) the same
     way newVMComplex.pas is a sibling of newVM.pas (real double).

     Inspired by Dew MtxVec Library for fpc but does not distinguish
     between matrix and vector objects. Vectors are column dimension (*,1)
     or row dimension (1,*).

     TComplex8 ({re,im: Single}) and the lapacke_cgesv / lapacke_claset /
     lapacke_clacpy bindings live in OneAPI.pas, alongside their TComplex16
     / "z" counterparts - added there for exactly this unit.

     Notes carried over from newVMComplex.pas, equally true here:

     1) cblas_cgemm expects alpha/beta as pointers to a complex scalar
        (CBLAS C convention `const void *alpha`), so alpha/beta are passed
        as @alpha/@beta - unlike the real gemm routines, which take them
        by value.

     2) lapacke_claset takes its alpha/beta (off-diagonal/diagonal fill
        values) by value as complex scalars, matching the LAPACKE C
        signature - passed directly (not by pointer) here.

     3) MKL's VSL has no complex Gaussian generator. fillRandom instead
        reinterprets the complex data buffer as a Single array of twice
        the length (valid because TComplex8 is exactly two contiguous
        singles) and calls vsRngGaussian once, filling both the real and
        imaginary parts with independent N(0,1) samples.

     OPERATOR OVERLOADS (algebraic expressions on TVMobjC) - the single-
     precision analogue of the ones added to newVMComplex.pas:
       - '+'/'-' element-wise via cblas_caxpy; unary '-' via cblas_csscal
         (MKL's "scale a complex vector by a real scalar" routine).
       - '*' between two TVMobjC is matrix multiplication, delegating to
         MatMultC (cblas_cgemm).
       - '*'/'/' accept either a TComplex8 scalar (cblas_cscal) or a plain
         Single scalar (cblas_csscal); division computes the scalar
         reciprocal in Pascal first.
       - mixed-type '+', '-' and '*' against a real TVMobjS promote the
         real operand to complex via RealToComplexS, then delegate to the
         TVMobjC operators above.

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
  Classes, SysUtils, cblas, math, TestRegistry, OneAPI, Types, newVMSingle, fftw3;

Const
  MaxDimC = 65536;    //maximum dimensions of any array

Type
  TDimC = 0..MaxDimC-1;
  TDataSizeC = 1..MaxDimC*MaxDimC;

  TVectorC = Array of TComplex8;   //maximum dimensions of any array; TComplex8 declared in OneAPI


type

  { TVMobjC }

  TVMobjC = record
    private
      fData : TVectorC;  //Holds data for object
      frows, fcols : TDimC;
      function getelement(r,c: TDimC): TComplex8;
      procedure setelement(r,c: TDimC; AValue: TComplex8);
    public
      constructor create(r,c :TDimC);Overload;
      Constructor create(r,c: TDimC; const Values : TVectorC); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDimC]:TComplex8 read getelement write setelement; default;
      procedure fillRandom;
      procedure Id;
      procedure linspace(Start, increment: TComplex8);
      function Transpose: TVMObjC;
      property Rows: TDimC read frows;              //read-only dimension accessors
      property Cols: TDimC read fcols;

      { Operator overloads - see OPERATOR OVERLOADS note in the header above.
        Mode Delphi only supports operator overloading as "class operator"
        members of the record. The mixed real/complex forms are declared
        here (rather than on TVMobjS in newVMSingle.pas) because TVMobjC is
        the common operand in all of them, and only this unit sees both
        types. }
      class operator +(const A, B: TVMobjC): TVMobjC;
      class operator -(const A, B: TVMobjC): TVMobjC;
      class operator -(const A: TVMobjC): TVMobjC;
      class operator *(const A, B: TVMobjC): TVMobjC;
      class operator *(const A: TVMobjC; const k: TComplex8): TVMobjC;
      class operator *(const k: TComplex8; const A: TVMobjC): TVMobjC;
      class operator *(const A: TVMobjC; const k: Single): TVMobjC;
      class operator *(const k: Single; const A: TVMobjC): TVMobjC;
      class operator /(const A: TVMobjC; const k: TComplex8): TVMobjC;
      class operator /(const A: TVMobjC; const k: Single): TVMobjC;
      class operator +(const A: TVMobjC; const B: TVMobjS): TVMobjC;
      class operator +(const A: TVMobjS; const B: TVMobjC): TVMobjC;
      class operator -(const A: TVMobjC; const B: TVMobjS): TVMobjC;
      class operator -(const A: TVMobjS; const B: TVMobjC): TVMobjC;
      class operator *(const A: TVMobjC; const B: TVMobjS): TVMobjC;
      class operator *(const A: TVMobjS; const B: TVMobjC): TVMobjC;
      class operator =(const A, B: TVMobjC): Boolean;
  end;

function calcoffsetC(r,c,cols :TDimC):integer;inline;
function MatMultC( const A, B: TVMObjC): TVMobjC;
function LinearSolveC(var A, B: TVMObjC):integer;
function CopyObjC(Const A : TVMObjC):TVMobjC;
function InvertC(const A: TVMobjC): TVMobjC;  //matrix inverse, via LAPACKE_cgetrf+cgetri; leaves A untouched
function KronC(const A, B: TVMobjC): TVMobjC;  //Kronecker product - see Kron in newVM.pas
function DiagC(const A: TVMobjC): TVMobjC;  //column vector (n,1) -> (n,n) diagonal matrix - see Diag in newVM.pas
function NormC(const A: TVMobjC): Single;  //Euclidean norm (real-valued), via cblas_scnrm2 - see Norm in newVM.pas
function TraceC(const A: TVMobjC): TComplex8;  //sum of A's leading-diagonal elements - see Trace in newVM.pas
function Cplx8(re,im : Single): TComplex8;inline;
function RealToComplexS(const A : TVMobjS): TVMobjC;    //promotes a real single TVMobjS to a complex TVMobjC, im = 0
function GetRealPartS(const A : TVMobjC): TVMobjS;      //extracts the real component of A into a real single TVMobjS
function GetImagPartS(const A : TVMobjC): TVMobjS;      //extracts the imaginary component of A into a real single TVMobjS
procedure SplitComplexS(const A : TVMobjC; out RealPart, ImagPart: TVMobjS); //convenience: both parts in one call
procedure EigDecomposeS(const A : TVMobjS; out EigenValues, EigenVectors: TVMobjC); //eigenvalues/(right) eigenvectors of a real square matrix, via LAPACKE_sgeev

{ Elementwise transcendental/algebraic functions, via MKL VML (vc* routines
  in OneAPI.pas - complex-valued, principal-branch results). Each returns a
  new TVMobjC of the same dimensions as A, with the function applied to
  every element. Marked "overload" since Sin/Cos/Sqr/Sqrt/Exp/Ln also exist
  in System/Math for plain numeric types - without "overload" the TVMobjC
  versions here would hide those entirely within this unit. }
function Sin(const A: TVMobjC): TVMobjC; overload;
function Cos(const A: TVMobjC): TVMobjC; overload;
function Tan(const A: TVMobjC): TVMobjC; overload;
function Sinh(const A: TVMobjC): TVMobjC; overload;
function Sqr(const A: TVMobjC): TVMobjC; overload;
function Sqrt(const A: TVMobjC): TVMobjC; overload;
function Exp(const A: TVMobjC): TVMobjC; overload;
function Ln(const A: TVMobjC): TVMobjC; overload;
function MulObjC(const A, B: TVMObjC): TVMobjC;

{ Real<->complex and complex<->complex 1D FFTs, via FFTW3 (fftw3.pas) on
  the single-precision library - see the matching FFT_R2C..IFFT comment in
  newVMComplex.pas for the shape/mutation/normalization rules, which apply
  here identically. Marked "overload" because newVMComplex.pas declares
  the TVMobj/TVMobjZ (double) analogues of these same names. }
function FFT_R2C(const A: TVMobjS): TVMobjC; overload;         //real -> packed half-spectrum
function FFT_C2R(const A: TVMobjC; N: Integer): TVMobjS; overload; //packed half-spectrum -> real, normalized
function FFT(const A: TVMobjC): TVMobjC; overload;             //complex -> complex, forward
function IFFT(const A: TVMobjC): TVMobjC; overload;            //complex -> complex, inverse, normalized

implementation

function Cplx8(re,im: Single): TComplex8;
begin
  result.re := re;
  result.im := im;
end;

function calcoffsetC(r, c, cols: TDimC): integer;
begin
  result := r*cols+c;
end;

{ TVMobjC }

function TVMobjC.getelement(r,c: TDimC): TComplex8;
var
   Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in getelement');
   Ix := calcoffsetC(r,c,cols);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobjC.setelement(r,c:TDimC; AValue: TComplex8);
var
 Ix : Integer;
begin
   assert((r<rows) and (c<cols),'Dimensions don''t match in setelement');
   Ix := calcoffsetC(r,c,cols);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobjC.create(r,c :TDimC);
var
  i,N : integer;
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  frows := r;
  fcols := c;
  N := r*c;
  setLength(fData,N);
  for i := low(fdata) to high(fdata) do fdata[i] := Cplx8(0,0);
end;

constructor TVMobjC.create(r,c : TDimC; const Values: TVectorC);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  frows := r;
  fcols := c;
  fdata := copy(Values,0,high(values)+1);
end;

function TVMobjC.writeMatrix: TStringList;
const
  fieldwidth = 22;
var
   i,j,k,l: integer;
   s,t : String;
   v : TComplex8;
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

procedure TVMobjC.fillRandom;
//
// MKL's VSL RNG functions only generate real-valued distributions -
// there is no complex Gaussian generator. Because TComplex8 is laid
// out as two contiguous singles (re, im), we reinterpret the complex
// buffer as a plain Single array of twice the length and fill it with
// vsRngGaussian in a single call - this fills both the real and
// imaginary parts with independent N(0,1) samples.
//
const
  vslConst = 8388608;
  VSL_RNG_METHOD_GAUSSIAN_ICDF = 2;
var
  vsSTream : pointer;
  n : integer;
begin
  n := (high(fdata)+1)*2; //2 singles per complex element
  vslNewStream(@vsStream,vslConst,777);
  vsRngGaussian(VSL_RNG_METHOD_GAUSSIAN_ICDF,vsStream,n,PSingle(@Fdata[0]),0,1);
  vsldeleteStream(@vsStream);
end;

procedure TVMobjC.Id;
const
  s : string = 'Routine Id :';
var
  zero, one : TComplex8;
begin
  //Check dimensions of matrices are compatible. A must be square
  assert(cols=rows,s +'Matrix A must be square');
  zero := Cplx8(0,0);
  one  := Cplx8(1,0);
  lapacke_claset(CBlasRowMajor,'A',rows,cols,zero,one,@Fdata[0],rows);
end;

procedure TVMobjC.linspace(Start, increment: TComplex8);
const
  s : String ='routine linspace';
var
  i : integer;
begin
  assert(fdata <>nil,s+  ': MVObj Not Initialized');
  //IPP has no complex VectorSlope (ippsVectorSlope_32fc isn't exported by
  //libipps - only the real forms are), so build the arithmetic sequence
  //directly: FData[i] = Start + i*increment.
  for i := 0 to high(fdata) do
    FData[i] := Cplx8(start.re + i*increment.re, start.im + i*increment.im);
end;

function TVMobjC.Transpose:TVMObjC;
var
  temp : TDimC;
begin
  result := copyobjC(self);
  MKL_Cimatcopy('R','T',rows,cols,Cplx8(1,0),@result.FData[0],cols,rows);
//swap row and column numbers
  temp := self.rows;
  result.frows := self.cols;
  result.fcols := temp;
end;

function MatMultC(const A, B: TVMObjC): TVMobjC;
const
  s : String = 'Routine MatMultC :';
var
  m,n,k : integer;
  C : TVMObjC;
  alpha, beta : TComplex8;
begin
  m := A.Rows;
  n := B.Cols;
  k := A.Cols;
  //Check for compatibility of matrices
  assert(A.cols = B.rows,s+'columns of first matrix must equal rows of second');
  c := TVMObjC.Create(m,n);
  alpha := Cplx8(1,0);
  beta  := Cplx8(1,0);
  cblas_cgemm(CblasRowMajor, CblasNoTrans, CblasNoTrans,
              m,n,k, { m, n, k }
              @alpha,  { alpha - by pointer, per CBLAS complex convention }
                @A.FData[0], k,
                @B.Fdata[0], n,
              @beta, {beta}
                @C.Fdata[0],n
             );
    result := C;
end;

function LinearSolveC(var A, B: TVMObjC):integer;
const
  s : String = 'Function LinearSolveC : ';
var
  ipiv : array of integer;
{ Direct linear solve for matrix A and Vectors B. On return A is in LU
  factored form and solution matrix is in B. Returns info from Lapacke}
begin
  assert(A.Cols = A.Rows,s+'Matrix A must be square');
  assert(A.Rows = B.Rows, s+'Matrix A and B have incompatible dimensions');
  setlength(ipiv,A.rows);
  LinearSolveC:= lapacke_cgesv(CBlasRowMajor,A.rows,B.cols,@A.Fdata[0],A.cols,@ipiv[0],@B.FData[0],B.cols);
end;

function CopyObjC(const A: TVMObjC): TVMobjC;
begin
  result := TVMObjC.Create(A.rows,A.cols);
  LAPACKE_clacpy(CBlasRowMajor,'A',A.rows,A.cols,@A.Fdata[0],a.cols,@result.fdata[0],result.cols);
end;

function InvertC(const A: TVMobjC): TVMobjC;
const
  s : String = 'Function InvertC : ';
var
  ipiv : array of integer;
  info : integer;
{ Matrix inverse via LAPACKE_cgetrf (LU factorisation) followed by
  LAPACKE_cgetri (inverse from the LU factors), on a CopyObjC scratch
  buffer - both LAPACKE calls overwrite their input matrix in place,
  so A itself is left untouched. }
begin
  assert(A.Cols = A.Rows, s+'Matrix A must be square');
  result := CopyObjC(A);
  setlength(ipiv, A.rows);
  info := lapacke_cgetrf(CBlasRowMajor, A.rows, A.cols, @result.Fdata[0], A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_cgetrf failed (singular matrix?), info='+IntToStr(info));
  info := lapacke_cgetri(CBlasRowMajor, A.rows, @result.Fdata[0], A.cols, @ipiv[0]);
  assert(info = 0, s+'LAPACKE_cgetri failed (singular matrix?), info='+IntToStr(info));
end;

function KronC(const A, B: TVMobjC): TVMobjC;
var
  i, j, k, rowdest, coldest : integer;
  aval : TComplex8;
begin
  result := TVMobjC.Create(A.Rows*B.Rows, A.Cols*B.Cols);
  for i := 0 to A.Rows-1 do
    for j := 0 to A.Cols-1 do begin
      aval := A[i,j];
      for k := 0 to B.Rows-1 do begin
        rowdest := i*B.Rows + k;
        coldest := j*B.Cols;
        cblas_caxpy(B.Cols, @aval, @B.FData[k*B.Cols], 1, @result.FData[rowdest*result.Cols + coldest], 1);
      end;
    end;
end;

function DiagC(const A: TVMobjC): TVMobjC;
const
  s : String = 'Function DiagC : ';
begin
  assert(A.Cols = 1, s+'A must be a column vector (n,1)');
  result := TVMobjC.Create(A.Rows, A.Rows);
  cblas_ccopy(A.Rows, @A.FData[0], 1, @result.FData[0], A.Rows+1);
end;

function NormC(const A: TVMobjC): Single;
const
  s : String = 'Function NormC : ';
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  result := cblas_scnrm2(A.Rows*A.Cols, @A.FData[0], 1);
end;

function TraceC(const A: TVMobjC): TComplex8;
const
  s : String = 'Function TraceC : ';
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

function RealToComplexS(const A: TVMobjS): TVMobjC;
var
  n : integer;
begin
  //A is a real single TVMobjS (from newVMSingle.pas); result is the same
  //dimensions as a complex TVMobjC with imaginary parts all zero.
  n := A.Rows * A.Cols;
  result := TVMObjC.Create(A.Rows, A.Cols);  //zero-fills both re and im
  //TComplex8 = {re,im: Single} packed as two contiguous singles per
  //element, so result.FData viewed as a flat Single array has real
  //parts at even offsets (0,2,4,...) and imaginary parts at odd offsets.
  //cblas_scopy with a destination stride of 2 writes only into the real
  //slots; the imaginary slots are left at the zero the constructor set.
  //A.DataPtr (public accessor on TVMobjS) supplies the source buffer
  //without needing friend access to newVMSingle's private fields.
  cblas_scopy(n, A.DataPtr, 1, PSingle(@result.FData[0]), 2);
end;

function GetRealPartS(const A: TVMobjC): TVMobjS;
begin
  //A.FData, viewed as a flat Single array, has real parts at even
  //offsets (0,2,4,...). cblas_scopy with a source stride of 2, starting
  //at offset 0, pulls out every real component into a contiguous,
  //ordinary TVMobjS buffer (destination stride 1) - no per-element loop.
  result := TVMobjS.Create(A.rows, A.cols);
  cblas_scopy(A.rows*A.cols, PSingle(@A.FData[0]), 2, result.DataPtr, 1);
end;

function GetImagPartS(const A: TVMobjC): TVMobjS;
var
  pIm : PSingle;
begin
  //Same trick as GetRealPartS, but starting one single further in, so
  //the stride-2 walk lands on the imaginary slots (offsets 1,3,5,...)
  //instead of the real ones.
  result := TVMobjS.Create(A.rows, A.cols);
  pIm := PSingle(@A.FData[0]);
  inc(pIm);                              //step over the first real slot
  cblas_scopy(A.rows*A.cols, pIm, 2, result.DataPtr, 1);
end;

procedure SplitComplexS(const A: TVMobjC; out RealPart, ImagPart: TVMobjS);
begin
  //Convenience wrapper: two independent MKL scopy calls, one per part.
  RealPart := GetRealPartS(A);
  ImagPart := GetImagPartS(A);
end;

procedure EigDecomposeS(const A: TVMobjS; out EigenValues, EigenVectors: TVMobjC);
const
  s : String = 'Routine EigDecomposeS : ';
//
// General real nonsymmetric eigenvalue problem, via LAPACKE_sgeev - the
// single-precision counterpart to EigDecompose (newVMComplex.pas), which
// uses LAPACKE_dgeev. See that routine's comments for the full rationale;
// the unpacking logic is identical, just at single precision throughout.
//
var
  n, i, j, info : integer;
  Acopy : TVMobjS;
  wr, wi, vr : TVectorS;   //TVectorS = array of Single, exported by newVMSingle
begin
  assert(A.Rows = A.Cols, s+'Matrix A must be square');
  n := A.Rows;

  //LAPACKE_sgeev overwrites its input matrix in place, so run it on a
  //scratch copy and leave the caller's A untouched.
  Acopy := CopyObjS(A);

  SetLength(wr, n);
  SetLength(wi, n);
  SetLength(vr, n*n);

  //jobvl = 'N' : left eigenvectors not requested (vl unused -> nil, ldvl=n is a harmless placeholder)
  //jobvr = 'V' : right eigenvectors requested, returned in packed real form in vr
  info := LAPACKE_sgeev(CBlasRowMajor, 'N', 'V', n,
                          Acopy.DataPtr, n,
                          @wr[0], @wi[0],
                          nil, n,
                          @vr[0], n);
  assert(info = 0, s+'LAPACKE_sgeev failed, info='+IntToStr(info));

  //--- eigenvalues: one complex value per row, straight from wr/wi ---
  EigenValues := TVMobjC.Create(n,1);
  for i := 0 to n-1 do
    EigenValues.FData[i] := Cplx8(wr[i], wi[i]);

  //--- eigenvectors: unpack LAPACK's real/imaginary column pairing ---
  EigenVectors := TVMobjC.Create(n,n);
  j := 0;
  while j <= n-1 do begin
    if wi[j] = 0 then begin
      //real eigenvalue -> column j of vr IS the eigenvector, im = 0
      for i := 0 to n-1 do
        EigenVectors.FData[i*n+j] := Cplx8(vr[i*n+j], 0);
      inc(j);
    end else begin
      //complex-conjugate pair sharing columns j (real part) and j+1 (imag part)
      for i := 0 to n-1 do begin
        EigenVectors.FData[i*n+j]   := Cplx8(vr[i*n+j],  vr[i*n+j+1]);
        EigenVectors.FData[i*n+j+1] := Cplx8(vr[i*n+j], -vr[i*n+j+1]);
      end;
      inc(j,2);
    end;
  end;
end;

function ReciprocalC(const k: TComplex8): TComplex8;
const
  s : String = 'Operator / (TVMobjC) : ';
var
  d : Single;
begin
  d := k.re*k.re + k.im*k.im;
  assert(d<>0, s+'division by zero complex scalar');
  result.re :=  k.re/d;
  result.im := -k.im/d;
end;

class operator TVMobjC.+(const A, B: TVMobjC): TVMobjC;
const
  s : String = 'Operator + (TVMobjC) : ';
var
  one : TComplex8;
begin
  assert((A.rows=B.rows) and (A.cols=B.cols), s+'matrix dimensions must match');
  one := Cplx8(1,0);
  result := CopyObjC(B);
  cblas_caxpy(A.rows*A.cols, @one, @A.FData[0], 1, @result.FData[0], 1);
end;

class operator TVMobjC.-(const A, B: TVMobjC): TVMobjC;
const
  s : String = 'Operator - (TVMobjC) : ';
var
  negOne : TComplex8;
begin
  assert((A.rows=B.rows) and (A.cols=B.cols), s+'matrix dimensions must match');
  negOne := Cplx8(-1,0);
  result := CopyObjC(A);
  cblas_caxpy(A.rows*A.cols, @negOne, @B.FData[0], 1, @result.FData[0], 1);
end;

class operator TVMobjC.-(const A: TVMobjC): TVMobjC;
begin
  result := CopyObjC(A);
  cblas_csscal(A.rows*A.cols, -1, @result.FData[0], 1);
end;

class operator TVMobjC.*(const A, B: TVMobjC): TVMobjC;
begin
  result := MulObjC(A, B);
end;

class operator TVMobjC.*(const A: TVMobjC; const k: TComplex8): TVMobjC;
begin
  result := CopyObjC(A);
  cblas_cscal(A.rows*A.cols, @k, @result.FData[0], 1);
end;

class operator TVMobjC.*(const k: TComplex8; const A: TVMobjC): TVMobjC;
begin
  result := A * k;
end;

class operator TVMobjC.*(const A: TVMobjC; const k: Single): TVMobjC;
begin
  result := CopyObjC(A);
  cblas_csscal(A.rows*A.cols, k, @result.FData[0], 1);
end;

class operator TVMobjC.*(const k: Single; const A: TVMobjC): TVMobjC;
begin
  result := A * k;
end;

class operator TVMobjC./(const A: TVMobjC; const k: TComplex8): TVMobjC;
var
  r : TComplex8;
begin
  r := ReciprocalC(k);
  result := CopyObjC(A);
  cblas_cscal(A.rows*A.cols, @r, @result.FData[0], 1);
end;

class operator TVMobjC./(const A: TVMobjC; const k: Single): TVMobjC;
const
  s : String = 'Operator / (TVMobjC) : ';
begin
  assert(k<>0, s+'division by zero');
  result := CopyObjC(A);
  cblas_csscal(A.rows*A.cols, 1/k, @result.FData[0], 1);
end;

class operator TVMobjC.+(const A: TVMobjC; const B: TVMobjS): TVMobjC;
begin
  result := A + RealToComplexS(B);
end;

class operator TVMobjC.+(const A: TVMobjS; const B: TVMobjC): TVMobjC;
begin
  result := RealToComplexS(A) + B;
end;

class operator TVMobjC.-(const A: TVMobjC; const B: TVMobjS): TVMobjC;
begin
  result := A - RealToComplexS(B);
end;

class operator TVMobjC.-(const A: TVMobjS; const B: TVMobjC): TVMobjC;
begin
  result := RealToComplexS(A) - B;
end;

class operator TVMobjC.*(const A: TVMobjC; const B: TVMobjS): TVMobjC;
begin
  result := MatMultC(A, RealToComplexS(B));
end;

class operator TVMobjC.*(const A: TVMobjS; const B: TVMobjC): TVMobjC;
begin
  result := MatMultC(RealToComplexS(A), B);
end;

class operator TVMobjC.=(const A, B: TVMobjC): Boolean;
begin
  Result := (A.rows = B.rows) and (A.cols = B.cols) and
            CompareMem(@A.FData[0], @B.FData[0], A.rows*A.cols*SizeOf(TComplex8));
end;

function Sin(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcSin(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Cos(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcCos(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Tan(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcTan(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Sinh(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcSinh(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Sqr(const A: TVMobjC): TVMobjC;
begin
  //MKL VM has no vcSqr (complex Sqr isn't part of the VM function set,
  //unlike real vsSqr) - so square elementwise via vcMul(A, A) instead.
  result := TVMobjC.Create(A.rows, A.cols);
  vcMul(A.rows*A.cols, @A.FData[0], @A.FData[0], @result.FData[0]);
end;

function Sqrt(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcSqrt(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Exp(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcExp(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function Ln(const A: TVMobjC): TVMobjC;
begin
  result := TVMobjC.Create(A.rows, A.cols);
  vcLn(A.rows*A.cols, @A.FData[0], @result.FData[0]);
end;

function MulObjC(const A, B: TVMObjC): TVMobjC;
const
  s: string ='Routine MulObjC : ';
begin
  assert((a.rows=b.rows)and(a.cols=b.cols),s+'Dimensions of A and B must be the same');
  result := CopyObjC(A);
  vcMul(A.rows*A.cols, @A.FData[0], @B.FData[0], @result.FData[0]);
end;

function FFT_R2C(const A: TVMobjS): TVMobjC;
const
  s : String = 'Routine FFT_R2C : ';
var
  n, nc : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftwf_plan_dft_r2c_1d), s+'FFTW3 (single) library not loaded');
  nc := n div 2 + 1;
  if A.Cols = 1 then result := TVMobjC.Create(nc, 1) else result := TVMobjC.Create(1, nc);
  plan := fftwf_plan_dft_r2c_1d(n, A.DataPtr, PComplex8(@result.FData[0]), FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftwf_plan_dft_r2c_1d failed');
  fftwf_execute_dft_r2c(plan, A.DataPtr, PComplex8(@result.FData[0]));
  fftwf_destroy_plan(plan);
end;

function FFT_C2R(const A: TVMobjC; N: Integer): TVMobjS;
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
  assert(Assigned(fftwf_plan_dft_c2r_1d), s+'FFTW3 (single) library not loaded');
  if A.Cols = 1 then result := TVMobjS.Create(N, 1) else result := TVMobjS.Create(1, N);
  plan := fftwf_plan_dft_c2r_1d(N, PComplex8(@A.FData[0]), result.DataPtr, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftwf_plan_dft_c2r_1d failed');
  fftwf_execute_dft_c2r(plan, PComplex8(@A.FData[0]), result.DataPtr);
  fftwf_destroy_plan(plan);
  ippsDivC_32f_I(N, result.DataPtr, N);   //normalize, matching FFT_C2R(FFT_R2C(x), N) = x
end;

function FFT(const A: TVMobjC): TVMobjC;
const
  s : String = 'Routine FFT : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftwf_plan_dft_1d), s+'FFTW3 (single) library not loaded');
  result := TVMobjC.Create(A.Rows, A.Cols);
  plan := fftwf_plan_dft_1d(n, PComplex8(@A.FData[0]), PComplex8(@result.FData[0]), FFTW_FORWARD, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftwf_plan_dft_1d failed');
  fftwf_execute_dft(plan, PComplex8(@A.FData[0]), PComplex8(@result.FData[0]));
  fftwf_destroy_plan(plan);
end;

function IFFT(const A: TVMobjC): TVMobjC;
const
  s : String = 'Routine IFFT : ';
var
  n : integer;
  plan : fftw_plan;
begin
  assert((A.Rows=1) or (A.Cols=1), s+'A must be a vector (Rows=1 or Cols=1)');
  n := A.Rows*A.Cols;
  assert(Assigned(fftwf_plan_dft_1d), s+'FFTW3 (single) library not loaded');
  result := TVMobjC.Create(A.Rows, A.Cols);
  plan := fftwf_plan_dft_1d(n, PComplex8(@A.FData[0]), PComplex8(@result.FData[0]), FFTW_BACKWARD, FFTW_ESTIMATE or FFTW_PRESERVE_INPUT);
  assert(plan<>nil, s+'fftwf_plan_dft_1d failed');
  fftwf_execute_dft(plan, PComplex8(@A.FData[0]), PComplex8(@result.FData[0]));
  fftwf_destroy_plan(plan);
  cblas_csscal(n, 1.0/n, @result.FData[0], 1);  //normalize, matching IFFT(FFT(x)) = x
end;

end.
