program O2Entrainment;

{*******************************************************************************

     Demo: the oxygen percentage delivered when an oxygen jet entrains room
     air, against the entrainment ratio (litres of air drawn in per litre
     of oxygen), on a TVMPlot2D - with the standard Venturi mask valve
     ratings and the trachea jet LES's measured ratio marked on the curve.
     See uo2entmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uo2entmain;

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
