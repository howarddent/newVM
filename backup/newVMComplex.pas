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
  Classes, SysUtils, cblas, math, TestRegistry, OneAPI, Types, newVM;

Const
  MaxDimZ = 65536;    //maximum dimensions of any array

Type
  TDimZ = 0..MaxDimZ-1;
  TDataSizeZ = 1..MaxDimZ*MaxDimZ;

  //Double precision complex scalar - layout matches MKL_Complex16
  //(two contiguous doubles). Rename to match your bindings if they
  //already declare an equivalent type - see header notes above.
  {TComplex16 = record
    re, im : Double; }
  end;

  TVectorZ = Array of TComplex16;   //maximum dimensions of any array


type

  { TVMobjZ }

  TVMobjZ = record
    private
      fData : TVectorZ;  //Holds data for object
      rows, cols : TDimZ;
      function getelement(r,c: TDimZ): TComplex16;
      procedure setelement(r,c: TDimZ; AValue: TComplex16);
    public
      constructor create(r,c :TDimZ);Overload;
      Constructor create(r,c: TDimZ; const Values : TVectorZ); overload;
      function writeMatrix: TStringList;
      property Element[r,c:TDimZ]:TComplex16 read getelement write setelement; default;
      procedure fillRandom;
      procedure Id;
  end;

function calcoffsetZ(r,c :TDimZ):integer;inline;
function MatMultZ( const A, B: TVMObjZ): TVMobjZ;
function LinearSolveZ(var A, B: TVMObjZ):integer;
function CopyObjZ(Const A : TVMObjZ):TVMobjZ;
function Cplx(re,im : Double): TComplex16;inline;
function RealToComplex(const A : TVMobj): TVMobjZ;    //promotes a real double TVMobj to a complex TVMobjZ, im = 0
function GetRealPart(const A : TVMobjZ): TVMobj;      //extracts the real component of A into a real double TVMobj
function GetImagPart(const A : TVMobjZ): TVMobj;      //extracts the imaginary component of A into a real double TVMobj
procedure SplitComplex(const A : TVMobjZ; out RealPart, ImagPart: TVMobj); //convenience: both parts in one call
procedure EigDecompose(const A : TVMobj; out EigenValues, EigenVectors: TVMobjZ); //eigenvalues/(right) eigenvectors of a real square matrix, via LAPACKE_dgeev


implementation

function Cplx(re,im: Double): TComplex16;
begin
  result.re := re;
  result.im := im;
end;

function calcoffsetZ(r, c: TDimZ): integer;
begin
  result := (r*(c-1))+r-1;
end;

{ TVMobjZ }

function TVMobjZ.getelement(r,c: TDimZ): TComplex16;
var
   Ix : Integer;
begin
   assert((r<=rows) and (c<=cols),'Dimensions don''t match in getelement');
   Ix := calcoffsetZ(r,c);
   assert(Ix<= high(fdata),'Index out of range in get element');
   result := fdata[Ix];
end;

procedure TVMobjZ.setelement(r,c:TDimZ; AValue: TComplex16);
var
 Ix : Integer;
begin
   assert((r<=rows) and (c<=cols),'Dimensions don''t match in setelement');
   Ix := calcoffsetZ(r,c);
   assert(Ix <= high(fdata),'Index out of range in set element');
   fdata[Ix] := Avalue;
end;

constructor TVMobjZ.create(r,c :TDimZ);
var
  i,N : integer;
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  rows := r;
  cols := c;
  N := r*c;
  setLength(fData,N);
  for i := low(fdata) to high(fdata) do fdata[i] := Cplx(0,0);
end;

constructor TVMobjZ.create(r,c : TDimZ; const Values: TVectorZ);
begin
  assert((r>0) and (c>0),'rows and columns must be > 0');
  assert( (r*c) = high(values)+1,'Incompatible dimensions ');
  rows := r;
  cols := c;
  fdata := copy(Values,0,high(values)+1);
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
var
  ipiv : array of integer;
{ Direct linear solve for matrix A and Vectors B. On return A is in LU
  factored form and solution matrix is in B. Returns info from Lapacke}
begin
  assert(A.Cols = A.Rows,s+'Matrix A must be square');
  assert(A.Rows = B.cols, s+'Matrix A and B have incompatible dimensions');
  setlength(ipiv,A.rows);
  LinearSolveZ:= lapacke_zgesv(CBlasRowMajor,A.rows,B.cols,@A.Fdata[0],A.cols,@ipiv[0],@B.FData[0],B.cols);
end;

function CopyObjZ(const A: TVMObjZ): TVMobjZ;
begin
  result := TVMObjZ.Create(A.rows,A.cols);
  LAPACKE_zlacpy(CBlasRowMajor,'A',A.rows,A.cols,@A.Fdata[0],a.cols,@result.fdata[0],result.cols);
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



end.
