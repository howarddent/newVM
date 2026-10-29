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

program newsSpeak;

{*******************************************************************************

     Demo: fetches today's Channel 4 News headlines from its RSS feed,
     reads the top five aloud through TVMSpeech (Graphs/uVMSpeech.pas,
     Windows SAPI), with a live spectrum of the speech on a
     TVMPlotSpectrum as each headline plays - see unewsmain.pas.

     Needs the OpenSSL 3 DLLs beside the exe for the HTTPS fetch, as
     demos/CanterburyRain does (see CLAUDE.md's entry for that demo).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, unewsmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmNews, fmNews);
  Application.Run;
end.
