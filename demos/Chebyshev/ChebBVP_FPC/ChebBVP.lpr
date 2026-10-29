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

program ChebBVP;

{*******************************************************************************

     Demo: Chebyshev-collocation solution of the linear boundary-value
     problem u_xx = exp(4x), u(-1)=u(1)=0, ported from the Delphi/MtxVec
     original at demos/Chebyshev/ChebBVP - see uBVPMain.pas. Reuses TCheb/
     BaryLag1D from demos/Chebyshev/NormalIntegration/uCheb.pas rather
     than duplicating them.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uBVPMain, newvmgraphs;

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
