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

program PlotStack;

{*******************************************************************************

     Demo: a "waterfall" stack of TVMobj row vectors, each pushed in at the
     front (nearest the viewer) via TVMPlotStack.AddGraph, receding into
     the distance and fading to black as older graphs accumulate behind
     it - see Graphs/uVMPlotStack.pas for the component itself. "Add
     Graph" appends one more phase-shifted curve by hand; the Animate
     checkbox switches the whole stack between sitting still (only moving
     on "Add Graph") and continuously receding on its own. Drag to
     rotate, mouse wheel to zoom - see uplotstackmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uplotstackmain;

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
