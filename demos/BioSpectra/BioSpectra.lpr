program BioSpectra;

{*******************************************************************************

     Demo: frequency spectra of three biological signals - an ECG, an EEG
     and an invasive arterial pressure - from PhysioNet records (20-second
     excerpts in data/, see data/README.md). Each signal has its own tab:
     the time-domain trace above, its Hamming-windowed power spectral
     density up to the Nyquist frequency below (newVMComplex's FFT_R2C over
     FFTW), and the recording parameters from the WFDB header in a memo
     alongside - see ubiospectramain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ubiospectramain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBio, fmBio);
  Application.Run;
end.
