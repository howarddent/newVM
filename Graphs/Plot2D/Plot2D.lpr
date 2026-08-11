program Plot2D;

{*******************************************************************************

     Demo: renders y = f(x) (same function as demos/FunctionPlot) via raw
     OpenGL (TOpenGLControl/GL unit) instead of TAChart - an anti-aliased
     line strip in an orthographic projection auto-fitted to the data's
     bounding box, with axis/border overlays drawn in GL - see
     uplot2dmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uplot2dmain;

begin
  InitializeCBLAS;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
