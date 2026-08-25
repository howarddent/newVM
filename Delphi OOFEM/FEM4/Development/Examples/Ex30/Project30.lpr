program Project30;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit30 in 'Unit30.pas' {Form30},
  CXS.FEMLAP.Analytical in '..\..\Source\Analytical\CXS.FEMLAP.Analytical.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm30, Form30);
  Application.Run;
end.
