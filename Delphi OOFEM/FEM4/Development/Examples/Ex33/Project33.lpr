program Project33;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit33 in 'Unit33.pas' {Form33},
  CXS.FEMLAP.Analytical in '..\..\Source\Analytical\CXS.FEMLAP.Analytical.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm33, Form33);
  Application.Run;
end.
