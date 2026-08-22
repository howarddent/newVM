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
