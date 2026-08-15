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
