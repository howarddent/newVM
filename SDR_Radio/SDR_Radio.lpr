program SDR_Radio;

{*******************************************************************************

     HackRF live spectrum analyser: 8192-sample complex IQ epochs,
     Hamming-windowed and FFT'd via newVM (newVMComplex.pas's
     PowerSpectrum), displayed as a scrolling waterfall in a TVMPlotStack
     (Graphs/uVMPlotStack.pas) with a real frequency axis. See
     uSDRMain.pas for the full per-epoch pipeline and uHackRF.pas for the
     libhackrf binding/ring-buffer this reads IQ data from.

     cthreads IS NEEDED ON DARWIN TOO, not just "the rest of Unix" - this
     app creates real TThread instances the moment streaming starts
     (TSDRRFSource's own TSDRPollThread/TSDRControlThread, plus
     uFMReceiver.pas/uAMReceiver.pas's DSP threads once Listen is enabled),
     and without a thread driver linked in, the FIRST TThread.Create on any
     platform aborts immediately with "Runtime error 232: no thread
     support compiled in." Confirmed by reproducing exactly the crash
     pressing Start caused ("crashes as soon as I press start, exit code
     232") with a standalone harness that mirrored the previous
     "UNIX and not DARWIN" IFDEF guard - the guard's implicit assumption
     (Darwin's Cocoa widgetset already provides thread support, so cthreads
     would be redundant there) does not hold for this app's own direct
     TThread usage; removing the DARWIN exclusion fixed it immediately,
     confirmed with the exact same harness re-run clean for 10s.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../newVMConfig.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uHackRF, uSDRMain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
