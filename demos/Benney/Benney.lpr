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

program Benney;

{*******************************************************************************

     Demo: numerical solution of the 1-D Benney equation for a liquid
     film flowing down an inclined plane, integrated with a Kaps-Rentrop
     stiff solver and shown as a waterfall on a TVMPlotStack - the
     FPC/newVM port of the Delphi/MtxVec project Benney/prjkapstest.
     See ubenneymain.pas, ubenneymodel.pas and ukapsrentrop.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ubenneymain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBenney, fmBenney);
  Application.Run;
end.
