program Wave2D;

{*******************************************************************************

     Demo: Chebyshev-pseudospectral solution of the 2D wave equation
     u_tt = u_xx + u_yy on [-1,1]x[-1,1], leapfrog time-stepped in real time,
     ported from the Delphi/MtxVec/GLScene original at
     demos/Chebyshev/Wave2D - see uWave2DMain.pas and uWave2DGrid.pas for
     what changed and why. Reuses TCheb and BaryLag2D from
     demos/Chebyshev/NormalIntegration/uCheb.pas, same as ../2DChebBVP_FPC,
     and displays via TVMPlot3D (Graphs/uVMPlot3D.pas), same as
     ../2DChebBVP_FPC and Graphs/Plot3D.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uWave2DMain;

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
