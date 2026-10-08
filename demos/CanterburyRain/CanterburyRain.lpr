program CanterburyRain;

{*******************************************************************************

     Demo: the weather in Canterbury, Kent over the last 12 complete
     months, downloaded fresh on every run - monthly rainfall as bars and
     daily maximum/minimum temperatures as box-and-whiskers, each against
     its 1991-2020 average, on TVMPlot2D charts. See uRainMain.pas (the
     form) and uWeatherData.pas (the download and the averaging).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uRainMain;

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
