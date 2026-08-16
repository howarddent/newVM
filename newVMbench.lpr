program newVMbench;

{*******************************************************************************

     Timed performance comparison of the three most demanding operations -
     MatMult, LinearSolve, Invert - across N = 10, 100, 1000, for random
     matrices, across all four TVMobj* types: double-precision real
     (newVM.pas), single-precision real (newVMSingle.pas), double-precision
     complex (newVMComplex.pas), and single-precision complex
     (newVMComplexSingle.pas). Also times FFT/IFFT (complex double/single,
     round-tripped and checked against the original) and EigDecompose/
     EigDecomposeS (real double/single, checked via the defining equation
     A*v=lambda*v for every eigenpair, same verification approach as
     newVMTests.pas's own TestEigDecomposeSatisfiesEigenEquation) - see
     RunBenchmarksFFT/RunBenchmarksFFTSingle/RunBenchmarksEig/
     RunBenchmarksEigSingle below. EigDecompose uses its own, shorter NsEig
     list (10/50/100, not 1000): PurePascalEigHqr2's QR-iteration algorithm
     is the same asymptotic O(N^3) as LU-based Invert but with a materially
     larger constant factor (more scalar arithmetic per step, plus
     accumulating the eigenvector transformation matrix alongside the
     eigenvalues), so N=1000 in PUREPASCAL risks the benchmark taking
     drastically longer than the other operations' N=1000 rows for little
     extra insight. FFT/IFFT reuse the full Ns list unchanged - even
     PPDirectDFT's direct O(N^2) summation is only 10^6 operations at
     N=1000, comfortably fast either build.

     A second independent axis worth knowing about when reading a table
     this program prints: FFT/IFFT's library-vs-PUREPASCAL choice is driven
     by HAVE_FFTW, not PUREPASCAL - the two are independent defines (see
     newVM.pas's own architecture notes) - so a "PUREPASCAL forced, FFTW
     still found" build (the common case, since forcing PUREPASCAL doesn't
     touch newVMConfig.inc's separately-detected HAVE_FFTW) still times
     FFTW for the FFT/IFFT rows even while MatMult/LinearSolve/Invert/
     EigDecompose run their PUREPASCAL bodies. PrintBackend reports both
     axes separately so a results table stays self-documenting about
     exactly which combination produced it.

     One asymmetry worth knowing before reading the complex results: unlike
     every other LinearSolve*, LinearSolveZ and LinearSolveC have NO
     Accelerate branch at all - Apple's zgetrs_/cgetrs_ crash with an
     access violation whenever a factored pivot has an exactly-zero
     imaginary part (see cblas.pas's comments next to accel_zgetrf_/
     accel_zgetri_ and accel_cgetrf_/accel_cgetri_, and newVMComplex.pas's/
     newVMComplexSingle.pas's LinearSolveZ/LinearSolveC). So both always run
     their PurePascalLU?/PurePascalLU?Solve path, in BOTH builds - their two
     timings should come out essentially identical, and that's expected,
     not a bug in this benchmark.

     PUREPASCAL vs library-backed isn't a runtime switch in this codebase -
     it's decided at compile time by newVMConfig.inc (see newVM.pas's own
     header comment). So getting both numbers means building this program
     TWICE, with two different newVMConfig.inc contents, and running the
     resulting binaries separately:

       1. The real one for this machine (as ./newvmconfigure last wrote it -
          on a Mac with no MKL/IPP/OpenBLAS, that means Accelerate-backed
          MatMult/LinearSolve/Invert via the PUREPASCAL_BLAS/HAVE_ACCELERATE
          machinery added across several recent commits).
       2. A forced-PUREPASCAL variant - the same "force PUREPASCAL on in
          newVMConfig.inc, independent of what's actually installed" trick
          already used to verify the PUREPASCAL fallback bodies when they
          were first written (see newVM.pas's architecture notes).

     Build (no lazbuild/.lpi needed - same plain-fpc approach as
     newvmconfigure.lpr, since this doesn't need any LCL/GUI dependency):

       fpc -Fu. -Fi. newVMbench.lpr

     Run:

       ./newVMbench

     The program prints which backend it was actually built against (read
     straight from the same defines newVMConfig.inc set), so a results table
     assembled from two separate runs is self-documenting about which run
     was which.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I newVMConfig.inc}

uses
  SysUtils, cblas, hirestimer, OneAPI, newVM, newVMSingle, newVMComplex,
  newVMComplexSingle;

const
  Ns: array[0..2] of Integer = (10, 100, 1000);
  NsEig: array[0..2] of Integer = (10, 50, 100);  //see header comment: EigDecompose skips N=1000

{ Frobenius norm of a (possibly non-vector) matrix, computed directly over
  its buffer. Deliberately NOT implemented via Reshape(M, 1, Rows*Cols)+Norm
  - TDim is 0..65535 (see newVM.pas's MaxDim), so for N=1000 that Reshape
  call's NewCols=N*N=1,000,000 silently wraps at compile/runtime (a plain
  fpc build, unlike the project's .lpi, doesn't enable IncludeAssertionCode,
  so the resulting dimension mismatch assert doesn't fire either) and
  Reshape's cblas_dcopy then writes 1,000,000 elements into a buffer sized
  for the wrapped, much smaller NewCols - silent heap corruption that
  presents as the whole program hanging. Confirmed via a standalone
  reproduction outside this file before switching to this loop. }
function MatrixResidualNorm(const M: TVMobj): Double;
var
  i : Integer;
  sumsq : Double;
begin
  sumsq := 0;
  for i := 0 to M.Rows*M.Cols-1 do
    sumsq := sumsq + M.DataPtr[i]*M.DataPtr[i];
  result := Sqrt(sumsq);
end;

{ Single-precision analogue of MatrixResidualNorm above - same rationale,
  same DataPtr-flat-loop approach (TVMobjS exposes DataPtr, same as
  TVMobj). }
function MatrixResidualNormS(const M: TVMobjS): Single;
var
  i : Integer;
  sumsq : Single;
begin
  sumsq := 0;
  for i := 0 to M.Rows*M.Cols-1 do
    sumsq := sumsq + M.DataPtr[i]*M.DataPtr[i];
  result := Sqrt(sumsq);
end;

{ Complex analogue - TVMobjZ has no public DataPtr (unlike TVMobj/TVMobjS,
  its FData field is private with no raw-pointer accessor exposed), so
  this walks the public Element[r,c] indexer instead and sums each
  element's squared magnitude (re^2+im^2) directly - same Frobenius-norm
  result, no Reshape involved either way. }
function MatrixResidualNormZ(const M: TVMobjZ): Double;
var
  i, j : Integer;
  sumsq : Double;
begin
  sumsq := 0;
  for i := 0 to M.Rows-1 do
    for j := 0 to M.Cols-1 do
      sumsq := sumsq + M[i,j].re*M[i,j].re + M[i,j].im*M[i,j].im;
  result := Sqrt(sumsq);
end;

{ Single-precision complex analogue of MatrixResidualNormZ above - same
  rationale (TVMobjC has no public DataPtr either, same Element[r,c] walk). }
function MatrixResidualNormC(const M: TVMobjC): Single;
var
  i, j : Integer;
  sumsq : Single;
begin
  sumsq := 0;
  for i := 0 to M.Rows-1 do
    for j := 0 to M.Cols-1 do
      sumsq := sumsq + M[i,j].re*M[i,j].re + M[i,j].im*M[i,j].im;
  result := Sqrt(sumsq);
end;

procedure PrintBackend;
begin
  // MatMult/LinearSolve/Invert's choice of body is driven by the SAME
  // machine-wide PUREPASCAL_BLAS/PUREPASCAL/HAVE_ACCELERATE defines for
  // all four TVMobj* types (they all {$I} the same newVMConfig.inc) - so,
  // real/single behave identically here. Complex is the one exception,
  // called out separately below.
  Write('MatMult (real/single/complex) backend: ');
  {$IFDEF PUREPASCAL_BLAS}
  WriteLn('PUREPASCAL (plain Pascal triple loop)');
  {$ELSE}
  WriteLn('library-backed (cblas_?gemm)');
  {$ENDIF}
  Write('LinearSolve/Invert (real, single) backend: ');
  {$IFDEF PUREPASCAL}
    {$IFDEF HAVE_ACCELERATE}
  WriteLn('library-backed (Accelerate ?getrf_/?getri_/?getrs_)');
    {$ELSE}
  WriteLn('PUREPASCAL (PurePascalLU?/PurePascalLU?Solve)');
    {$ENDIF}
  {$ELSE}
  WriteLn('library-backed (LAPACKE_?getrf/?getri/?gesv/?getrs)');
  {$ENDIF}
  Write('Invert (complex double) backend: ');
  {$IFDEF PUREPASCAL}
    {$IFDEF HAVE_ACCELERATE}
  WriteLn('library-backed (Accelerate zgetrf_/zgetri_)');
    {$ELSE}
  WriteLn('PUREPASCAL (PurePascalLUZ/PurePascalLUSolveZ)');
    {$ENDIF}
  {$ELSE}
  WriteLn('library-backed (LAPACKE_zgetrf/zgetri)');
  {$ENDIF}
  WriteLn('LinearSolve (complex double) backend: PUREPASCAL always ',
    '(Accelerate zgetrs_ has a known crash bug - see cblas.pas) - ',
    'identical in both builds, not a bug in this benchmark');
  Write('Invert (complex single) backend: ');
  {$IFDEF PUREPASCAL}
    {$IFDEF HAVE_ACCELERATE}
  WriteLn('library-backed (Accelerate cgetrf_/cgetri_)');
    {$ELSE}
  WriteLn('PUREPASCAL (PurePascalLUC/PurePascalLUSolveC)');
    {$ENDIF}
  {$ELSE}
  WriteLn('library-backed (LAPACKE_cgetrf/cgetri)');
  {$ENDIF}
  WriteLn('LinearSolve (complex single) backend: PUREPASCAL always ',
    '(Accelerate cgetrs_ has the same known crash bug - see cblas.pas) - ',
    'identical in both builds, not a bug in this benchmark');
  Write('EigDecompose/EigDecomposeS (real double/single) backend: ');
  {$IFDEF PUREPASCAL}
  WriteLn('PUREPASCAL (PurePascalEigHqr2/PurePascalEigHqr2S)');
  {$ELSE}
  WriteLn('library-backed (LAPACKE_dgeev/sgeev)');
  {$ENDIF}
  Write('FFT/IFFT (complex double/single) backend: ');
  {$IFDEF HAVE_FFTW}
  WriteLn('library-backed (FFTW3 fftw_plan_dft_1d/fftwf_plan_dft_1d) - ',
    'independent of PUREPASCAL above, see this program''s own header comment');
  {$ELSE}
  WriteLn('PUREPASCAL (direct O(N^2) DFT - PPDirectDFT/PPDirectDFTS)');
  {$ENDIF}
  WriteLn;
end;

procedure RunBenchmarksDouble;
var
  i, N : Integer;
  A, B, C, Asolve, X, Ainv, Resid, IdentN : TVMobj;
  t0, t1 : Int64;
  msMatMult, msSolve, msInvert : Double;
  info : Integer;
  solveResidual, invertResidual : Double;
begin
  WriteLn('--- Double precision real (newVM.pas) ---');
  WriteLn('     N   MatMult(ms)   LinearSolve(ms)   Invert(ms)   ',
          'SolveResidual   InvertResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output); // progress marker - PUREPASCAL N=1000 can take a while

    A := TVMobj.Create(N, N);
    A.fillRandom;
    B := TVMobj.Create(N, N);
    B.fillRandom;

    // --- MatMult ---
    t0 := HighResTimer.MicroSeconds;
    C := MatMult(A, B);
    t1 := HighResTimer.MicroSeconds;
    msMatMult := (t1 - t0) / 1000.0;

    // --- LinearSolve --- (mutates its A argument, so solve against a
    // fresh copy; X starts as the random right-hand side and is
    // overwritten in place with the solution)
    Asolve := CopyObj(A);
    X := TVMobj.Create(N, 1);
    X.fillRandom;
    Resid := CopyObj(X); // keep the original RHS to check the residual after
    t0 := HighResTimer.MicroSeconds;
    info := LinearSolve(Asolve, X);
    t1 := HighResTimer.MicroSeconds;
    msSolve := (t1 - t0) / 1000.0;
    Resid := MatMult(A, X) - Resid;      // A*x - b, should be ~0
    solveResidual := Norm(Resid);
    if info <> 0 then solveResidual := -1; // flag a reported solve failure

    // --- Invert --- (never mutates A)
    t0 := HighResTimer.MicroSeconds;
    Ainv := Invert(A);
    t1 := HighResTimer.MicroSeconds;
    msInvert := (t1 - t0) / 1000.0;
    IdentN := TVMobj.Create(N, N);
    IdentN.Id;
    Resid := MatMult(A, Ainv) - IdentN;  // A*inv(A) - I, should be ~0
    invertResidual := MatrixResidualNorm(Resid);

    WriteLn(#13, Format('%6d %13.2f %17.2f %12.2f %15.2e %15.2e',
      [N, msMatMult, msSolve, msInvert, solveResidual, invertResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

procedure RunBenchmarksSingle;
var
  i, N : Integer;
  A, B, C, Asolve, X, Ainv, Resid, IdentN : TVMobjS;
  t0, t1 : Int64;
  msMatMult, msSolve, msInvert : Double;
  info : Integer;
  solveResidual, invertResidual : Single;
begin
  WriteLn('--- Single precision real (newVMSingle.pas) ---');
  WriteLn('     N   MatMult(ms)   LinearSolve(ms)   Invert(ms)   ',
          'SolveResidual   InvertResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjS.Create(N, N);
    A.fillRandom;
    B := TVMobjS.Create(N, N);
    B.fillRandom;

    // --- MatMultS ---
    t0 := HighResTimer.MicroSeconds;
    C := MatMultS(A, B);
    t1 := HighResTimer.MicroSeconds;
    msMatMult := (t1 - t0) / 1000.0;

    // --- LinearSolveS --- (mutates its A argument, so solve against a
    // fresh copy)
    Asolve := CopyObjS(A);
    X := TVMobjS.Create(N, 1);
    X.fillRandom;
    Resid := CopyObjS(X);
    t0 := HighResTimer.MicroSeconds;
    info := LinearSolveS(Asolve, X);
    t1 := HighResTimer.MicroSeconds;
    msSolve := (t1 - t0) / 1000.0;
    Resid := MatMultS(A, X) - Resid;      // A*x - b, should be ~0
    solveResidual := NormS(Resid);
    if info <> 0 then solveResidual := -1;

    // --- InvertS --- (never mutates A)
    t0 := HighResTimer.MicroSeconds;
    Ainv := InvertS(A);
    t1 := HighResTimer.MicroSeconds;
    msInvert := (t1 - t0) / 1000.0;
    IdentN := TVMobjS.Create(N, N);
    IdentN.Id;
    Resid := MatMultS(A, Ainv) - IdentN;  // A*inv(A) - I, should be ~0
    invertResidual := MatrixResidualNormS(Resid);

    WriteLn(#13, Format('%6d %13.2f %17.2f %12.2f %15.2e %15.2e',
      [N, msMatMult, msSolve, msInvert, solveResidual, invertResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

procedure RunBenchmarksComplex;
var
  i, N : Integer;
  A, B, C, Asolve, X, Ainv, Resid, IdentN : TVMobjZ;
  t0, t1 : Int64;
  msMatMult, msSolve, msInvert : Double;
  info : Integer;
  solveResidual, invertResidual : Double;
begin
  WriteLn('--- Double precision complex (newVMComplex.pas) ---');
  WriteLn('     N   MatMultZ(ms)  LinearSolveZ(ms)  InvertZ(ms)  ',
          'SolveResidual   InvertResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjZ.Create(N, N);
    A.fillRandom;
    B := TVMobjZ.Create(N, N);
    B.fillRandom;

    // --- MatMultZ ---
    t0 := HighResTimer.MicroSeconds;
    C := MatMultZ(A, B);
    t1 := HighResTimer.MicroSeconds;
    msMatMult := (t1 - t0) / 1000.0;

    // --- LinearSolveZ --- (always PurePascalLUZ - see this program's own
    // header comment and PrintBackend above)
    Asolve := CopyObjZ(A);
    X := TVMobjZ.Create(N, 1);
    X.fillRandom;
    Resid := CopyObjZ(X);
    t0 := HighResTimer.MicroSeconds;
    info := LinearSolveZ(Asolve, X);
    t1 := HighResTimer.MicroSeconds;
    msSolve := (t1 - t0) / 1000.0;
    Resid := MatMultZ(A, X) - Resid;      // A*x - b, should be ~0
    solveResidual := NormZ(Resid);
    if info <> 0 then solveResidual := -1;

    // --- InvertZ --- (never mutates A)
    t0 := HighResTimer.MicroSeconds;
    Ainv := InvertZ(A);
    t1 := HighResTimer.MicroSeconds;
    msInvert := (t1 - t0) / 1000.0;
    IdentN := TVMobjZ.Create(N, N);
    IdentN.Id;
    Resid := MatMultZ(A, Ainv) - IdentN;  // A*inv(A) - I, should be ~0
    invertResidual := MatrixResidualNormZ(Resid);

    WriteLn(#13, Format('%6d %13.2f %17.2f %12.2f %15.2e %15.2e',
      [N, msMatMult, msSolve, msInvert, solveResidual, invertResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

procedure RunBenchmarksComplexSingle;
var
  i, N : Integer;
  A, B, C, Asolve, X, Ainv, Resid, IdentN : TVMobjC;
  t0, t1 : Int64;
  msMatMult, msSolve, msInvert : Double;
  info : Integer;
  solveResidual, invertResidual : Single;
begin
  WriteLn('--- Single precision complex (newVMComplexSingle.pas) ---');
  WriteLn('     N   MatMultC(ms)  LinearSolveC(ms)  InvertC(ms)  ',
          'SolveResidual   InvertResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjC.Create(N, N);
    A.fillRandom;
    B := TVMobjC.Create(N, N);
    B.fillRandom;

    // --- MatMultC ---
    t0 := HighResTimer.MicroSeconds;
    C := MatMultC(A, B);
    t1 := HighResTimer.MicroSeconds;
    msMatMult := (t1 - t0) / 1000.0;

    // --- LinearSolveC --- (always PurePascalLUC - see this program's own
    // header comment and PrintBackend above)
    Asolve := CopyObjC(A);
    X := TVMobjC.Create(N, 1);
    X.fillRandom;
    Resid := CopyObjC(X);
    t0 := HighResTimer.MicroSeconds;
    info := LinearSolveC(Asolve, X);
    t1 := HighResTimer.MicroSeconds;
    msSolve := (t1 - t0) / 1000.0;
    Resid := MatMultC(A, X) - Resid;      // A*x - b, should be ~0
    solveResidual := NormC(Resid);
    if info <> 0 then solveResidual := -1;

    // --- InvertC --- (never mutates A)
    t0 := HighResTimer.MicroSeconds;
    Ainv := InvertC(A);
    t1 := HighResTimer.MicroSeconds;
    msInvert := (t1 - t0) / 1000.0;
    IdentN := TVMobjC.Create(N, N);
    IdentN.Id;
    Resid := MatMultC(A, Ainv) - IdentN;  // A*inv(A) - I, should be ~0
    invertResidual := MatrixResidualNormC(Resid);

    WriteLn(#13, Format('%6d %13.2f %17.2f %12.2f %15.2e %15.2e',
      [N, msMatMult, msSolve, msInvert, solveResidual, invertResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

{ FFT(A) then IFFT of that result should round-trip back to A (IFFT is
  normalized - see newVMComplex.pas's own IFFT comment) - timed separately,
  checked together via MatrixResidualNormZ(roundtrip - A). }
procedure RunBenchmarksFFT;
var
  i, N : Integer;
  A, F, R : TVMobjZ;
  t0, t1 : Int64;
  msFFT, msIFFT : Double;
  roundTripResidual : Double;
begin
  WriteLn('--- FFT/IFFT double precision complex (newVMComplex.pas) ---');
  WriteLn('     N   FFT(ms)   IFFT(ms)   RoundTripResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjZ.Create(1, N);
    A.fillRandom;

    t0 := HighResTimer.MicroSeconds;
    F := FFT(A);
    t1 := HighResTimer.MicroSeconds;
    msFFT := (t1 - t0) / 1000.0;

    t0 := HighResTimer.MicroSeconds;
    R := IFFT(F);
    t1 := HighResTimer.MicroSeconds;
    msIFFT := (t1 - t0) / 1000.0;

    R := R - A;  // should be ~0
    roundTripResidual := MatrixResidualNormZ(R);

    WriteLn(#13, Format('%6d %9.2f %10.2f %18.2e', [N, msFFT, msIFFT, roundTripResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

{ Single-precision analogue of RunBenchmarksFFT above - same round-trip
  approach, TVMobjC/FFT/IFFT (overloaded against newVMComplexSingle.pas's
  own TVMobjC) in place of TVMobjZ. }
procedure RunBenchmarksFFTSingle;
var
  i, N : Integer;
  A, F, R : TVMobjC;
  t0, t1 : Int64;
  msFFT, msIFFT : Double;
  roundTripResidual : Single;
begin
  WriteLn('--- FFT/IFFT single precision complex (newVMComplexSingle.pas) ---');
  WriteLn('     N   FFT(ms)   IFFT(ms)   RoundTripResidual');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjC.Create(1, N);
    A.fillRandom;

    t0 := HighResTimer.MicroSeconds;
    F := FFT(A);
    t1 := HighResTimer.MicroSeconds;
    msFFT := (t1 - t0) / 1000.0;

    t0 := HighResTimer.MicroSeconds;
    R := IFFT(F);
    t1 := HighResTimer.MicroSeconds;
    msIFFT := (t1 - t0) / 1000.0;

    R := R - A;  // should be ~0
    roundTripResidual := MatrixResidualNormC(R);

    WriteLn(#13, Format('%6d %9.2f %10.2f %18.2e', [N, msFFT, msIFFT, roundTripResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

{ Times EigDecompose and checks every eigenpair against the defining
  equation A*v = lambda*v (same verification newVMTests.pas's own
  TestEigDecomposeSatisfiesEigenEquation uses) - A*vcol is a genuine matrix
  product via the mixed TVMobj*TVMobjZ operator (see newVMComplex.pas's own
  header comment on why that mixed-type '*' is a real MatMultZ, unlike
  same-type Z*Z's element-wise '*'), and vcol*lambda is the complex-scalar
  overload. Reports the WORST (max) residual across all N eigenpairs, not
  the average - a single badly-conditioned eigenpair failing to satisfy the
  equation is exactly the kind of thing an average would hide. Uses NsEig
  (10/50/100), not Ns - see this program's own header comment for why
  N=1000 is skipped here specifically. }
procedure RunBenchmarksEig;
var
  i, j, N : Integer;
  A : TVMobj;
  EigenValues, EigenVectors, vcol, Av, lv, resid : TVMobjZ;
  t0, t1 : Int64;
  msEig, maxResidual, r : Double;
begin
  WriteLn('--- EigDecompose double precision (newVMComplex.pas) ---');
  WriteLn('     N   EigDecompose(ms)   MaxEigenResidual');
  for i := 0 to High(NsEig) do begin
    N := NsEig[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobj.Create(N, N);
    A.fillRandom;

    t0 := HighResTimer.MicroSeconds;
    EigDecompose(A, EigenValues, EigenVectors);
    t1 := HighResTimer.MicroSeconds;
    msEig := (t1 - t0) / 1000.0;

    maxResidual := 0;
    for j := 0 to N-1 do begin
      vcol := SubMatrixZ(EigenVectors, 0, j, N, 1);
      Av := A * vcol;                          // genuine matrix product (mixed real*complex)
      lv := vcol * EigenValues.Element[j, 0];  // complex-scalar multiply
      resid := Av - lv;
      r := MatrixResidualNormZ(resid);
      if r > maxResidual then maxResidual := r;
    end;

    WriteLn(#13, Format('%6d %18.2f %18.2e', [N, msEig, maxResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

{ Single-precision analogue of RunBenchmarksEig above - TVMobjS/TVMobjC/
  EigDecomposeS/SubMatrixC in place of TVMobj/TVMobjZ/EigDecompose/
  SubMatrixZ, otherwise identical approach. }
procedure RunBenchmarksEigSingle;
var
  i, j, N : Integer;
  A : TVMobjS;
  EigenValues, EigenVectors, vcol, Av, lv, resid : TVMobjC;
  t0, t1 : Int64;
  msEig : Double;
  maxResidual, r : Single;
begin
  WriteLn('--- EigDecompose single precision (newVMComplexSingle.pas) ---');
  WriteLn('     N   EigDecompose(ms)   MaxEigenResidual');
  for i := 0 to High(NsEig) do begin
    N := NsEig[i];
    Write('  N=', N, '...'); Flush(Output);

    A := TVMobjS.Create(N, N);
    A.fillRandom;

    t0 := HighResTimer.MicroSeconds;
    EigDecomposeS(A, EigenValues, EigenVectors);
    t1 := HighResTimer.MicroSeconds;
    msEig := (t1 - t0) / 1000.0;

    maxResidual := 0;
    for j := 0 to N-1 do begin
      vcol := SubMatrixC(EigenVectors, 0, j, N, 1);
      Av := A * vcol;                          // genuine matrix product (mixed real*complex)
      lv := vcol * EigenValues.Element[j, 0];  // complex-scalar multiply
      resid := Av - lv;
      r := MatrixResidualNormC(resid);
      if r > maxResidual then maxResidual := r;
    end;

    WriteLn(#13, Format('%6d %18.2f %18.2e', [N, msEig, maxResidual]));
    Flush(Output);
  end;
  WriteLn;
end;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  WriteLn('newVM performance benchmark (real double/single, complex double/single)');
  WriteLn('====================================================');
  PrintBackend;
  RunBenchmarksDouble;
  RunBenchmarksSingle;
  RunBenchmarksComplex;
  RunBenchmarksComplexSingle;
  RunBenchmarksFFT;
  RunBenchmarksFFTSingle;
  RunBenchmarksEig;
  RunBenchmarksEigSingle;
end.
