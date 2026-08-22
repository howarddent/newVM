program newVMCLfft8192bench;

{*******************************************************************************

     Follow-up to newVMCLbench.lpr's FFT/IFFT comparison, narrowed to a
     single size (N=8192) but with much finer-grained timing: this program
     separates each side's very FIRST FFT/IFFT call from the average (plus
     min/max) of 100 REPEAT calls that follow, instead of newVMCLbench.lpr's
     single-call-per-N approach. Motivation: that program's GPU FFT numbers
     were flat at ~190-380ms across every N from 1024 to 16384 - i.e. NOT
     scaling with N the way a real O(N log N) transform should - which its
     own report attributed to newVMCL.pas creating and destroying a fresh
     clFFT plan (clfftCreateDefaultPlan/clfftBakePlan) on every single call,
     with the actual JIT kernel compilation cost suspected to dominate. This
     program tests that hypothesis directly: if plan/kernel setup cost is a
     one-time, amortisable cost (paid once per process, or once per unique
     transform configuration, then reused under the hood by the OpenCL/CUDA
     driver even though newVMCL.pas's own plan OBJECT is not cached), the
     100-repeat average should be dramatically faster than the first call.
     If instead each repeat costs roughly the same as the first, that would
     mean clFFT's plan creation is a genuine PER-CALL cost with no reuse at
     all under this usage pattern - a different and more consequential
     finding than the previous report assumed.

     Host side (newVMComplexSingle.pas, FFTW3-backed) is measured the exact
     same way for direct comparison - the previous report's hypothesis was
     that FFTW's own plan cache/estimate-mode strategy already makes this
     largely moot on the host, so the host's first-call and repeat-average
     numbers are expected to be close to each other (unlike the GPU side).

     Both FFT and IFFT get their own first-call and repeat-average figures,
     since the previous report also flagged an unexplained FFT-vs-IFFT
     asymmetry (GPU forward transform slow on every call, backward fast
     immediately) that a same-size, same-direction repeat measurement can
     help characterise (though not fully explain, absent instrumenting
     clFFT/the driver directly).

     Build:  fpc -Fu. -Fi. newVMCLfft8192bench.lpr
     Run:    ./newVMCLfft8192bench

*******************************************************************************}

{$mode objfpc}{$H+}
{$I newVMConfig.inc}

uses
  SysUtils, cblas, hirestimer, OneAPI, newVM, newVMSingle, newVMComplexSingle
  {$IFDEF HAVE_OPENCL}, OpenCLAPI, newVMCL{$ENDIF};

const
  N = 8192;
  Repeats = 100;
  DiagCount = 10;   // how many individual repeat-call timings to print for warm-up-curve diagnosis

function ResidualNormC(const M: TVMobjC): Single;
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

{ Host side: newVMComplexSingle.pas's FFT/IFFT (FFTW3-backed). Returns
  first-call and repeat-average/min/max timings for both directions, plus
  the round-trip residual (computed once, from the first call) as a
  correctness check. The first DiagCount individual repeat timings for
  each direction are also collected, to see whether any "warm-up" happens
  within the repeat loop itself rather than being fully paid on call 1. }
procedure RunHost(out msFirstFFT, msFirstIFFT: Double;
  out msAvgFFT, msMinFFT, msMaxFFT: Double;
  out msAvgIFFT, msMinIFFT, msMaxIFFT: Double;
  out roundTripResidual: Single;
  out DiagFFT, DiagIFFT: array of Double);
var
  RawData : array of Single;
  A, F, R : TVMobjC;
  t0, t1 : Int64;
  i, k : Integer;
  total, tms : Double;
begin
  SetLength(RawData, 2*N);
  for k := 0 to 2*N-1 do
    RawData[k] := Random*2.0 - 1.0;
  A := TVMobjC.Create(1, N);
  for k := 0 to N-1 do
    A[0, k] := Cplx8(RawData[2*k], RawData[2*k+1]);

  // --- first call, each direction ---
  t0 := HighResTimer.MicroSeconds; F := FFT(A); t1 := HighResTimer.MicroSeconds;
  msFirstFFT := (t1 - t0) / 1000.0;
  t0 := HighResTimer.MicroSeconds; R := IFFT(F); t1 := HighResTimer.MicroSeconds;
  msFirstIFFT := (t1 - t0) / 1000.0;

  R := R - A;
  roundTripResidual := ResidualNormC(R);

  // --- 100 repeats, FFT ---
  total := 0; msMinFFT := 1e18; msMaxFFT := 0;
  for i := 1 to Repeats do begin
    t0 := HighResTimer.MicroSeconds; F := FFT(A); t1 := HighResTimer.MicroSeconds;
    tms := (t1 - t0) / 1000.0;
    total := total + tms;
    if tms < msMinFFT then msMinFFT := tms;
    if tms > msMaxFFT then msMaxFFT := tms;
    if i <= DiagCount then DiagFFT[i-1] := tms;
  end;
  msAvgFFT := total / Repeats;

  // --- 100 repeats, IFFT (against the F left over from the last FFT repeat) ---
  total := 0; msMinIFFT := 1e18; msMaxIFFT := 0;
  for i := 1 to Repeats do begin
    t0 := HighResTimer.MicroSeconds; R := IFFT(F); t1 := HighResTimer.MicroSeconds;
    tms := (t1 - t0) / 1000.0;
    total := total + tms;
    if tms < msMinIFFT then msMinIFFT := tms;
    if tms > msMaxIFFT then msMaxIFFT := tms;
    if i <= DiagCount then DiagIFFT[i-1] := tms;
  end;
  msAvgIFFT := total / Repeats;
end;

{$IFDEF HAVE_OPENCL}
{ GPU side: newVMCL.pas's FFT/IFFT (clFFT-backed), exact same protocol as
  RunHost above - see this program's own header comment for why. }
procedure RunGPU(out msFirstFFT, msFirstIFFT: Double;
  out msAvgFFT, msMinFFT, msMaxFFT: Double;
  out msAvgIFFT, msMinIFFT, msMaxIFFT: Double;
  out roundTripResidual: Single;
  out DiagFFT, DiagIFFT: array of Double);
var
  RawData : array of Single;
  A, F, R : TVMobjCL;
  RHost : TVMobjS;
  t0, t1 : Int64;
  i, k : Integer;
  total, tms : Double;
  d_re, d_im : Single;
  sumsq : Single;
begin
  SetLength(RawData, 2*N);
  for k := 0 to 2*N-1 do
    RawData[k] := Random*2.0 - 1.0;
  A := TVMobjCL.Create(1, 2*N, RawData);

  // --- first call, each direction ---
  t0 := HighResTimer.MicroSeconds; F := FFT(A); t1 := HighResTimer.MicroSeconds;
  msFirstFFT := (t1 - t0) / 1000.0;
  t0 := HighResTimer.MicroSeconds; R := IFFT(F); t1 := HighResTimer.MicroSeconds;
  msFirstIFFT := (t1 - t0) / 1000.0;

  RHost := ToHost(R);
  sumsq := 0;
  for k := 0 to N-1 do begin
    d_re := RHost[0, 2*k]   - RawData[2*k];
    d_im := RHost[0, 2*k+1] - RawData[2*k+1];
    sumsq := sumsq + d_re*d_re + d_im*d_im;
  end;
  roundTripResidual := Sqrt(sumsq);

  // --- 100 repeats, FFT ---
  total := 0; msMinFFT := 1e18; msMaxFFT := 0;
  for i := 1 to Repeats do begin
    t0 := HighResTimer.MicroSeconds; F := FFT(A); t1 := HighResTimer.MicroSeconds;
    tms := (t1 - t0) / 1000.0;
    total := total + tms;
    if tms < msMinFFT then msMinFFT := tms;
    if tms > msMaxFFT then msMaxFFT := tms;
    if i <= DiagCount then DiagFFT[i-1] := tms;
  end;
  msAvgFFT := total / Repeats;

  // --- 100 repeats, IFFT (against the F left over from the last FFT repeat) ---
  total := 0; msMinIFFT := 1e18; msMaxIFFT := 0;
  for i := 1 to Repeats do begin
    t0 := HighResTimer.MicroSeconds; R := IFFT(F); t1 := HighResTimer.MicroSeconds;
    tms := (t1 - t0) / 1000.0;
    total := total + tms;
    if tms < msMinIFFT then msMinIFFT := tms;
    if tms > msMaxIFFT then msMaxIFFT := tms;
    if i <= DiagCount then DiagIFFT[i-1] := tms;
  end;
  msAvgIFFT := total / Repeats;
end;
{$ENDIF}

procedure PrintDiag(const Label_: string; const Diag: array of Double);
var
  i : Integer;
begin
  Write(Label_, ': ');
  for i := 0 to High(Diag) do
    Write(Format('%.2f ', [Diag[i]]));
  WriteLn;
end;

var
  msFirstFFT, msFirstIFFT, msAvgFFT, msMinFFT, msMaxFFT,
  msAvgIFFT, msMinIFFT, msMaxIFFT : Double;
  roundTripResidual : Single;
  DiagFFT, DiagIFFT : array[0..DiagCount-1] of Double;
  {$IFDEF HAVE_OPENCL}
  gpuOK : Boolean;
  {$ENDIF}
begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  WriteLn('newVM FFT first-call vs 100-repeat-average benchmark, N=', N);
  WriteLn('=======================================================');
  WriteLn;

  WriteLn('--- HOST (newVMComplexSingle.pas, FFTW3) ---');
  RunHost(msFirstFFT, msFirstIFFT, msAvgFFT, msMinFFT, msMaxFFT,
    msAvgIFFT, msMinIFFT, msMaxIFFT, roundTripResidual, DiagFFT, DiagIFFT);
  WriteLn(Format('First FFT:  %.4f ms', [msFirstFFT]));
  WriteLn(Format('First IFFT: %.4f ms', [msFirstIFFT]));
  WriteLn(Format('FFT  over %d repeats: avg %.4f ms, min %.4f ms, max %.4f ms', [Repeats, msAvgFFT, msMinFFT, msMaxFFT]));
  WriteLn(Format('IFFT over %d repeats: avg %.4f ms, min %.4f ms, max %.4f ms', [Repeats, msAvgIFFT, msMinIFFT, msMaxIFFT]));
  WriteLn(Format('RoundTripResidual: %.4e', [roundTripResidual]));
  PrintDiag('First 10 FFT repeat timings (ms)', DiagFFT);
  PrintDiag('First 10 IFFT repeat timings (ms)', DiagIFFT);
  WriteLn('HOST_RESULT ', Format('%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4e',
    [msFirstFFT, msFirstIFFT, msAvgFFT, msMinFFT, msMaxFFT, msAvgIFFT, msMinIFFT, msMaxIFFT, roundTripResidual]));
  WriteLn;

  {$IFDEF HAVE_OPENCL}
  gpuOK := OpenCLReady;
  if gpuOK then begin
    WriteLn('--- GPU (newVMCL.pas, clFFT) ---');
    RunGPU(msFirstFFT, msFirstIFFT, msAvgFFT, msMinFFT, msMaxFFT,
      msAvgIFFT, msMinIFFT, msMaxIFFT, roundTripResidual, DiagFFT, DiagIFFT);
    WriteLn(Format('First FFT:  %.4f ms', [msFirstFFT]));
    WriteLn(Format('First IFFT: %.4f ms', [msFirstIFFT]));
    WriteLn(Format('FFT  over %d repeats: avg %.4f ms, min %.4f ms, max %.4f ms', [Repeats, msAvgFFT, msMinFFT, msMaxFFT]));
    WriteLn(Format('IFFT over %d repeats: avg %.4f ms, min %.4f ms, max %.4f ms', [Repeats, msAvgIFFT, msMinIFFT, msMaxIFFT]));
    WriteLn(Format('RoundTripResidual: %.4e', [roundTripResidual]));
    PrintDiag('First 10 FFT repeat timings (ms)', DiagFFT);
    PrintDiag('First 10 IFFT repeat timings (ms)', DiagIFFT);
    WriteLn('GPU_RESULT ', Format('%.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4e',
      [msFirstFFT, msFirstIFFT, msAvgFFT, msMinFFT, msMaxFFT, msAvgIFFT, msMinIFFT, msMaxIFFT, roundTripResidual]));
  end else
    WriteLn('GPU (newVMCL.pas): OpenCL/clFFT not ready (', OpenCLLastError, ') - skipped');
  {$ELSE}
  WriteLn('GPU (newVMCL.pas): not built (HAVE_OPENCL inactive) - skipped');
  {$ENDIF}
end.
