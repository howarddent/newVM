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

program PK_PD;

{*******************************************************************************

     Anaesthetics/PK-PD_FPC: a newVM/Lazarus port of the original Delphi/
     MtxVec PK/PD simulator (Anaesthetics/PK-PD/) - see uModel3Comp.pas and
     uPKPDMain.pas for the port itself and this project's approved plan for
     the overall rationale.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uPKPDMain, uPatientDialog;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.CreateForm(TPatientDialogForm, PatientDialogForm);
  Application.Run;
end.
