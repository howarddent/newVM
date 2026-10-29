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

program JetVent;

{*******************************************************************************

     Jet ventilation calculator - Free Pascal / newVM port of prjJetVent.dpr
     (the Delphi/MtxVec/TeeChart original, kept alongside for reference).

     Calculates jet flow, velocity, Mach number, stall pressure and mass
     flow for a set of jet cannulae over a range of driving pressures, and
     plots them against the measured values, on a TVMPlot2D. The
     calculations live in uJetCalcVM.pas (newVM vectors, newPolymath fits
     for the Crane A-22 tables, and a corrected Mach number from the gas
     state at the cannula exit rather than a fixed 342 m/s); the form is
     uJetMain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uJetMain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
