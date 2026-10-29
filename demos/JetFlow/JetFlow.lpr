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

program JetFlow;

{*******************************************************************************

     Jet flow calculator: the oxygen flow through a jet cannula of any
     bore and length at a given driving pressure, with whether the jet is
     choked and its highest Mach number, lowest temperature and lowest
     pressure. The calculation is JetVent's (../JetVent/uJetCalcVM.pas,
     the Crane 3-20 flow estimate and the exit state from the mass flow);
     the form is ujetflowmain.pas.

     Command line, for scripted screenshots: --p=<bar gauge>, --d=<mm>,
     --l=<cm> set the inputs.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ujetflowmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmJetFlow, fmJetFlow);
  Application.Run;
end.
