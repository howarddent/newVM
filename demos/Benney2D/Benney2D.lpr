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

program Benney2D;

{*******************************************************************************

     Demo: a thin water film falling down an inclined plate, in two
     dimensions - the 2-D Benney equation on a Fourier x Chebyshev grid,
     stepped semi-implicitly, with the x and y derivatives of each
     right-hand side on two threads. Shown as an animated TVMPlot3D
     surface beside a TVMPlotStack waterfall of the centre line.
     See ubenney2dmain.pas and ubenney2dmodel.pas; check2d.lpr holds the
     console checks (linear growth rate, threaded against serial).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ubenney2dmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBenney2D, fmBenney2D);
  Application.Run;
end.
