program KdV;

{*******************************************************************************

     Demo: two solitons of different heights, started at the same time,
     passing through each other under the Korteweg-de Vries equation,
     solved on a low-order Chebyshev grid with barycentric interpolation
     and integrated with demos/Benney's Kaps-Rentrop stiff solver, shown
     as a waterfall on a TVMPlotStack. See ukdvmain.pas and ukdvmodel.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ukdvmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmKdV, fmKdV);
  Application.Run;
end.
