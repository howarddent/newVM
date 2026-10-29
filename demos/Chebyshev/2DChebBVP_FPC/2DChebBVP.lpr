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

program TwoDChebBVP;

{*******************************************************************************

     Demo: Chebyshev-collocation solution of the 2D Poisson equation
     u_xx+u_yy = 10*sin(8x(y-1)), u=0 on the boundary of [-1,1]x[-1,1], ported
     from the Delphi/MtxVec original at demos/Chebyshev/2DChebBVP - see
     u2DBVPMain.pas. Reuses TCheb and BaryLag2D from
     demos/Chebyshev/NormalIntegration/uCheb.pas rather than duplicating
     them, same as ../ChebBVP_FPC's 1D demo (which reuses TCheb/BaryLag1D
     from the same unit), and displays via TVMPlot3D (Graphs/uVMPlot3D.pas),
     same as Graphs/Plot3D's demo.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, u2DBVPMain;

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
