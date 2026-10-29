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

program FilmWRM;

{*******************************************************************************

     Demo: a water film falling down an inclined plate, in two
     dimensions, by the weighted-residual model of Ruyer-Quil &
     Manneville - the model for films too thick for the Benney equation
     (demos/Benney2D), here a 1 mm film. Thickness and the two flow
     rates on a Fourier x cosine/sine grid, stepped semi-implicitly.
     Shown as an animated TVMPlot3D surface beside a TVMPlotStack
     waterfall of the centre line. See ufilmwrmmain.pas and
     ufilmwrmmodel.pas; checkwrm.lpr holds the console checks.

     cmem: glibc's allocator. Each step makes dozens of ~130 kB mode
     arrays; the RTL heap gives each one its own mmap, and the page
     faults cost as much as the arithmetic (a second of film: 3.6 s of
     wall time with the RTL heap, 2.6 s with cmem, system time 1.35 s
     against 0.14 s).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cmem, cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ufilmwrmmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmFilmWRM, fmFilmWRM);
  Application.Run;
end.
