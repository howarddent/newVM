program Burgers;

{*******************************************************************************

     Demo: shock formation in the inviscid Burgers equation, solved by a
     finite-volume scheme (exact Godunov flux, MUSCL, SSP-RK3) and shown
     as a waterfall on a TVMPlotStack against the exact entropy solution.
     See uburgersmain.pas and uburgersmodel.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uburgersmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBurgers, fmBurgers);
  Application.Run;
end.
