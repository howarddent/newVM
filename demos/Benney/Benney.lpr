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
