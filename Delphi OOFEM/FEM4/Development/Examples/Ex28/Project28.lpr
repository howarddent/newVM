program Project28;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit28 in 'Unit28.pas' {Form28};

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm28, Form28);
  Application.Run;
end.
