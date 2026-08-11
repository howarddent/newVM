program Plot3D;

{*******************************************************************************

     Demo: renders a real TVMobj matrix - z = sin(r)/r, the "sinc ripple"
     surface - as a lit, Gouraud-shaded 3D height field via raw OpenGL
     (TOpenGLControl/GL/GLU units) instead of a flat 2D projection.
     Drag to rotate, mouse wheel to zoom, checkbox to toggle wireframe -
     see uplot3dmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uplot3dmain;

begin
  InitializeCBLAS;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
