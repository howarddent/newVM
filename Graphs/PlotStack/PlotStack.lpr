program PlotStack;

{*******************************************************************************

     Demo: a "waterfall" stack of TVMobj row vectors, each pushed in at the
     front (nearest the viewer) via TVMPlotStack.AddGraph, receding into
     the distance and fading to black as older graphs accumulate behind
     it - see Graphs/uVMPlotStack.pas for the component itself. "Add
     Graph" appends one more phase-shifted curve by hand; the Animate
     checkbox switches the whole stack between sitting still (only moving
     on "Add Graph") and continuously receding on its own. Drag to
     rotate, mouse wheel to zoom - see uplotstackmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uplotstackmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
