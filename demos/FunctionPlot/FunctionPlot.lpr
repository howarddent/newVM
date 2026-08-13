program FunctionPlot;

{*******************************************************************************

     Demo: plots y = f(x) over the real line using TVMobj (newVM.pas) for
     the elementwise math and TAChart (TChart/TLineSeries) for display.

     The initial function is y = exp(-0.1*x^2) * sin(3*x), x in [-10,10],
     1000 points - see ufuncplotmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ufuncplotmain;

begin
  {$IFDEF HAVE_OPENBLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
