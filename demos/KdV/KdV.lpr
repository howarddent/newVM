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

program KdV;

{*******************************************************************************

     Demo: two solitons of different heights, started at the same time,
     passing through each other under the Korteweg-de Vries equation,
     solved on a low-order Chebyshev grid with barycentric interpolation
     and integrated with demos/Benney's Kaps-Rentrop stiff solver, shown
     as a waterfall on a TVMPlotStack. See ukdvmain.pas and ukdvmodel.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ukdvmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmKdV, fmKdV);
  Application.Run;
end.
