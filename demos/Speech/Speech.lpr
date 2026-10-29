{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

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
