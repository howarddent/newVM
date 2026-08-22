program SDR_Radio;

{*******************************************************************************

     HackRF live spectrum analyser: 8192-sample complex IQ epochs,
     Hamming-windowed and FFT'd via newVM (newVMComplex.pas's
     PowerSpectrum), displayed as a scrolling waterfall in a TVMPlotStack
     (Graphs/uVMPlotStack.pas) with a real frequency axis. See
     uSDRMain.pas for the full per-epoch pipeline and uHackRF.pas for the
     libhackrf binding/ring-buffer this reads IQ data from.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
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
