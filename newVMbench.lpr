program newVMbench;

{*******************************************************************************

     Timed performance comparison of newVM.pas's three most demanding
     operations - MatMult, LinearSolve, Invert - across N = 10, 100, 1000,
     for random double-precision matrices.

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
  SysUtils, cblas, hirestimer, newVM;

const
  Ns: array[0..2] of Integer = (10, 100, 1000);

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

procedure PrintBackend;
begin
  Write('MatMult backend:      ');
  {$IFDEF PUREPASCAL_BLAS}
  WriteLn('PUREPASCAL (plain Pascal triple loop)');
  {$ELSE}
  WriteLn('library-backed (cblas_dgemm)');
  {$ENDIF}
  Write('LinearSolve/Invert backend: ');
  {$IFDEF PUREPASCAL}
    {$IFDEF HAVE_ACCELERATE}
  WriteLn('library-backed (Accelerate dgetrf_/dgetri_/dgetrs_)');
    {$ELSE}
  WriteLn('PUREPASCAL (PurePascalLU/PurePascalLUSolve)');
    {$ENDIF}
  {$ELSE}
  WriteLn('library-backed (LAPACKE_dgetrf/dgetri/dgesv/dgetrs)');
  {$ENDIF}
  WriteLn;
end;

procedure RunBenchmarks;
var
  i, N : Integer;
  A, B, C, Asolve, X, Ainv, Resid, IdentN : TVMobj;
  t0, t1 : Int64;
  msMatMult, msSolve, msInvert : Double;
  info : Integer;
  solveResidual, invertResidual : Double;
begin
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
end;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  WriteLn('newVM.pas performance benchmark (double precision)');
  WriteLn('====================================================');
  PrintBackend;
  RunBenchmarks;
end.
