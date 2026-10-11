program Speech;

{*******************************************************************************

     Demo: the TVMSpeech text-to-speech component (Graphs/uVMSpeech.pas,
     Windows SAPI behind it). Type a sentence, pick a voice, speak it -
     and synthesise it silently into a newVM TVMobj to see the waveform
     and its spectrogram-style power spectrum on two TVMPlot2Ds. See
     uspeechmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uspeechmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmSpeech, fmSpeech);
  Application.Run;
end.
