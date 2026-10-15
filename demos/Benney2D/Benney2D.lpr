program Benney2D;

{*******************************************************************************

     Demo: a thin water film falling down an inclined plate, in two
     dimensions - the 2-D Benney equation on a Fourier x Chebyshev grid,
     stepped semi-implicitly, with the x and y derivatives of each
     right-hand side on two threads. Shown as an animated TVMPlot3D
     surface beside a TVMPlotStack waterfall of the centre line.
     See ubenney2dmain.pas and ubenney2dmodel.pas; check2d.lpr holds the
     console checks (linear growth rate, threaded against serial).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ubenney2dmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBenney2D, fmBenney2D);
  Application.Run;
end.
