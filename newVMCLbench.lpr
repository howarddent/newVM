program newVMCLbench;

{*******************************************************************************

     Timed performance comparison, host (CPU, single precision) vs GPU
     (OpenCL/clFFT, single precision), of the two operations both sides
     actually implement: complex FFT/IFFT and real matrix multiply. Host
     side is newVMSingle.pas (TVMobjS, MatMultS) plus newVMComplexSingle.pas
     (TVMobjC, FFT/IFFT); GPU side is newVMCL.pas (TVMobjCL, MatMultCL,
     FFT/IFFT via clFFT). This is deliberately narrower than newVMbench.lpr
     (which times MatMult/LinearSolve/Invert/FFT/EigDecompose across all
     four TVMobj* types but has no GPU leg at all): newVMCL.pas's own SCOPE
     comment is explicit that it implements no LinearSolve/Invert/Det/etc -
     FFT and MatMult are the only two operations that exist on BOTH sides
     to compare.

     N runs 1024, 2048, 4096, 8192, 16384 (doublings from 1024) for BOTH
     the FFT vector length and the MatMult square-matrix dimension. Every
     size is exercised on both host and GPU with the SAME input data (see
     each Run*Comparison procedure's own comment for how), and every row
     reports not just the two timings but a correctness residual - both a
     round-trip check (IFFT(FFT(x))=x, A*inv... n/a here, so instead
     MatMultCL's result is cross-checked directly against MatMultS's own
     result on identical inputs) so a suspiciously-fast GPU number can be
     told apart from a genuinely-fast one.

     One asymmetry worth knowing before reading the MatMult numbers:
     MatMultCL's own naive kernel body (see newVMCL.pas's own comment on
     it) enqueues the kernel and returns WITHOUT waiting for it to finish -
     OpenCL command queues are asynchronous by design. To get a real
     execution-time number (not just "how long did it take to enqueue"),
     this program's timed region for the GPU MatMult case wraps the
     MatMultCL call TOGETHER WITH the ToHost(...) readback that follows it
     - ToHost's clEnqueueReadBuffer call is blocking (CL_TRUE) and, on
     newVMCL.pas's single in-order command queue, cannot complete before
     the previously-enqueued kernel does, so timing "MatMultCL + ToHost"
     together is the only way to observe the kernel's actual GPU execution
     time from outside newVMCL.pas's own private GQueue. This does mean
     the reported GPU MatMult time also includes one buffer readback - a
     deliberate, documented inclusion (a real caller pays for the readback
     too), not an oversight; the host MatMultS timing is, by contrast,
     already a "real" number as-is, since it's ordinary synchronous CPU
     code. FFT/IFFT need no such wrapping - newVMCL.pas's own FFT/IFFT
     already call clFinish before returning (see that unit's own source).

     Build (no lazbuild/.lpi needed - same plain-fpc approach as
     newvmconfigure.lpr/newVMbench.lpr):

       fpc -Fu. -Fi. newVMCLbench.lpr

     Run:

       ./newVMCLbench

     Requires HAVE_OPENCL to be active in newVMConfig.inc (regenerate via
     ./newvmconfigure on a machine with a working OpenCL + clFFT install)
     - if it isn't, this program still builds and runs, but prints a
     one-line notice and only exercises the host (CPU) side, with the GPU
     columns of each table left blank.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I newVMConfig.inc}

uses
  SysUtils, cblas, hirestimer, OneAPI, newVM, newVMSingle, newVMComplexSingle
  {$IFDEF HAVE_OPENCL}, OpenCLAPI, newVMCL{$ENDIF};

const
  Ns: array[0..4] of Integer = (1024, 2048, 4096, 8192, 16384);

{ Frobenius-norm-style residual over a flat single-precision buffer -
  same rationale as newVMbench.lpr's own MatrixResidualNormS (TVMobjS
  exposes DataPtr for a direct flat loop), reused here unchanged. }
function ResidualNormS(const M: TVMobjS): Single;
var
  i : Integer;
  sumsq : Single;
begin
  sumsq := 0;
  for i := 0 to M.Rows*M.Cols-1 do
    sumsq := sumsq + M.DataPtr[i]*M.DataPtr[i];
  result := Sqrt(sumsq);
end;

{ Complex analogue - TVMobjC has no public DataPtr (same reason
  newVMbench.lpr's own MatrixResidualNormC walks Element[r,c] instead),
  reused here unchanged. }
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

procedure PrintBackend;
begin
  WriteLn('MatMultS (host, newVMSingle.pas) backend: ');
  Write('  ');
  {$IFDEF PUREPASCAL_BLAS}
  WriteLn('PUREPASCAL (plain Pascal triple loop)');
  {$ELSE}
  WriteLn('library-backed (cblas_sgemm)');
  {$ENDIF}
  Write('FFT/IFFT (host, newVMComplexSingle.pas) backend: ');
  {$IFDEF HAVE_FFTW}
  WriteLn('library-backed (FFTW3 fftwf_plan_dft_1d)');
  {$ELSE}
  WriteLn('PUREPASCAL (direct O(N^2) DFT - PPDirectDFTS)');
  {$ENDIF}
  {$IFDEF HAVE_OPENCL}
  if OpenCLReady then
    WriteLn('GPU (newVMCL.pas) backend: OpenCL + clFFT, ready')
  else
    WriteLn('GPU (newVMCL.pas) backend: OpenCL/clFFT found at build time but ',
      'failed to initialise at runtime (', OpenCLLastError, ') - GPU rows skipped');
  {$ELSE}
  WriteLn('GPU (newVMCL.pas) backend: not built (HAVE_OPENCL inactive) - GPU rows skipped');
  {$ENDIF}
  WriteLn;
end;

{ FFT/IFFT comparison. Host and GPU are fed BIT-IDENTICAL input data: a
  single flat array of 2*N random Singles (interleaved re/im pairs) is
  generated once per N, then read into a host TVMobjC (newVMComplexSingle,
  N complex elements) via Element[0,i]:=Cplx8(re,im), and separately into
  a GPU TVMobjCL (newVMCL, 2*N real floats, clFFT's own interleaved
  layout - see newVMCL.pas's own header comment) via its Create(r,c,Values)
  literal overload - no data conversion in either direction, so any
  difference in the two sides' results traces to the transform itself,
  not to how the input was built. Reports each side's own round-trip
  residual (IFFT(FFT(x))-x) plus a cross-check residual comparing the two
  sides' FORWARD FFT results directly against each other (converting the
  host TVMobjC result to the same flat interleaved layout the GPU already
  uses) - a third number a round-trip check alone can't provide, since a
  round trip can look perfect even if forward and inverse share a
  compensating bug. }
procedure RunFFTComparison;
var
  i, N, k : Integer;
  RawData : array of Single;
  HostIn, HostF, HostR : TVMobjC;
  {$IFDEF HAVE_OPENCL}
  GPUIn, GPUF, GPUR : TVMobjCL;
  GPUFHost : TVMobjS;
  msGPUFFT, msGPUIFFT : Double;
  gpuRoundTripResidual, crossResidual : Single;
  d_re, d_im : Single;
  {$ENDIF}
  t0, t1 : Int64;
  msHostFFT, msHostIFFT : Double;
  hostRoundTripResidual : Single;
  gpuOK : Boolean;
begin
  WriteLn('--- FFT/IFFT: host (newVMComplexSingle.pas) vs GPU (newVMCL.pas) ---');
  WriteLn('     N   HostFFT(ms)  HostIFFT(ms)  HostRoundTrip   ',
          'GPUFFT(ms)  GPUIFFT(ms)  GPURoundTrip   Host-vs-GPU');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    {$IFDEF HAVE_OPENCL}
    gpuOK := OpenCLReady;
    {$ELSE}
    gpuOK := False;
    {$ENDIF}

    // one shared random buffer, fed to both sides unchanged (see header comment)
    SetLength(RawData, 2*N);
    for k := 0 to 2*N-1 do
      RawData[k] := Random*2.0 - 1.0;

    HostIn := TVMobjC.Create(1, N);
    for k := 0 to N-1 do
      HostIn[0, k] := Cplx8(RawData[2*k], RawData[2*k+1]);

    t0 := HighResTimer.MicroSeconds;
    HostF := FFT(HostIn);
    t1 := HighResTimer.MicroSeconds;
    msHostFFT := (t1 - t0) / 1000.0;

    t0 := HighResTimer.MicroSeconds;
    HostR := IFFT(HostF);
    t1 := HighResTimer.MicroSeconds;
    msHostIFFT := (t1 - t0) / 1000.0;

    HostR := HostR - HostIn;
    hostRoundTripResidual := ResidualNormC(HostR);

    {$IFDEF HAVE_OPENCL}
    if gpuOK then begin
      GPUIn := TVMobjCL.Create(1, 2*N, RawData);

      t0 := HighResTimer.MicroSeconds;
      GPUF := FFT(GPUIn);
      t1 := HighResTimer.MicroSeconds;
      msGPUFFT := (t1 - t0) / 1000.0;

      t0 := HighResTimer.MicroSeconds;
      GPUR := IFFT(GPUF);
      t1 := HighResTimer.MicroSeconds;
      msGPUIFFT := (t1 - t0) / 1000.0;

      GPUFHost := ToHost(GPUF);
      crossResidual := 0;
      for k := 0 to N-1 do begin
        d_re := GPUFHost[0, 2*k]   - HostF[0, k].re;
        d_im := GPUFHost[0, 2*k+1] - HostF[0, k].im;
        crossResidual := crossResidual + d_re*d_re + d_im*d_im;
      end;
      crossResidual := Sqrt(crossResidual);

      GPUFHost := ToHost(GPUR);
      gpuRoundTripResidual := 0;
      for k := 0 to N-1 do begin
        d_re := GPUFHost[0, 2*k]   - RawData[2*k];
        d_im := GPUFHost[0, 2*k+1] - RawData[2*k+1];
        gpuRoundTripResidual := gpuRoundTripResidual + d_re*d_re + d_im*d_im;
      end;
      gpuRoundTripResidual := Sqrt(gpuRoundTripResidual);

      WriteLn(#13, Format('%6d %12.2f %13.2f %14.2e %11.2f %12.2f %13.2e %13.2e',
        [N, msHostFFT, msHostIFFT, hostRoundTripResidual,
         msGPUFFT, msGPUIFFT, gpuRoundTripResidual, crossResidual]));
    end else
    {$ENDIF}
      WriteLn(#13, Format('%6d %12.2f %13.2f %14.2e %11s %12s %13s %13s',
        [N, msHostFFT, msHostIFFT, hostRoundTripResidual, '-', '-', '-', '-']));
    Flush(Output);
  end;
  WriteLn;
end;

{ MatMult comparison. Host and GPU are fed BIT-IDENTICAL input matrices:
  A and B are built once, host-side, via TVMobjS.fillRandom (the fixed-
  seed-777 generator - see newVMSingle.pas's own fillRandom comment), then
  the GPU side uploads those exact values via ToDevice, so there is no
  independent random draw on the GPU side to drift from the host one.
  Reports each side's own timing plus a residual comparing MatMultCL's
  downloaded result directly against MatMultS's - see this program's own
  header comment for why the GPU timing wraps ToHost as well as
  MatMultCL itself. }
procedure RunMatMultComparison;
var
  i, N : Integer;
  A, B, HostC : TVMobjS;
  {$IFDEF HAVE_OPENCL}
  GA, GB, GC : TVMobjCL;
  GPUCHost, Resid : TVMobjS;
  msGPUMatMult : Double;
  crossResidual : Single;
  {$ENDIF}
  t0, t1 : Int64;
  msHostMatMult : Double;
  gpuOK : Boolean;
begin
  WriteLn('--- MatMult: host (newVMSingle.pas, MatMultS) vs GPU (newVMCL.pas, MatMultCL) ---');
  WriteLn('     N   HostMatMult(ms)   GPUMatMult+Readback(ms)   Host-vs-GPU');
  for i := 0 to High(Ns) do begin
    N := Ns[i];
    Write('  N=', N, '...'); Flush(Output);

    {$IFDEF HAVE_OPENCL}
    gpuOK := OpenCLReady;
    {$ELSE}
    gpuOK := False;
    {$ENDIF}

    A := TVMobjS.Create(N, N);
    A.fillRandom;
    B := TVMobjS.Create(N, N);
    B.fillRandom;

    t0 := HighResTimer.MicroSeconds;
    HostC := MatMultS(A, B);
    t1 := HighResTimer.MicroSeconds;
    msHostMatMult := (t1 - t0) / 1000.0;

    {$IFDEF HAVE_OPENCL}
    if gpuOK then begin
      GA := ToDevice(A);
      GB := ToDevice(B);

      t0 := HighResTimer.MicroSeconds;
      GC := MatMultCL(GA, GB);
      GPUCHost := ToHost(GC);       // blocking readback - see header comment for why this is IN the timed region
      t1 := HighResTimer.MicroSeconds;
      msGPUMatMult := (t1 - t0) / 1000.0;

      Resid := GPUCHost - HostC;
      crossResidual := ResidualNormS(Resid);

      WriteLn(#13, Format('%6d %17.2f %25.2f %15.2e',
        [N, msHostMatMult, msGPUMatMult, crossResidual]));
    end else
    {$ENDIF}
      WriteLn(#13, Format('%6d %17.2f %25s %15s',
        [N, msHostMatMult, '-', '-']));
    Flush(Output);
  end;
  WriteLn;
end;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  WriteLn('newVM host-vs-GPU performance benchmark (FFT/IFFT, MatMult)');
  WriteLn('=============================================================');
  PrintBackend;
  RunFFTComparison;
  RunMatMultComparison;
end.
