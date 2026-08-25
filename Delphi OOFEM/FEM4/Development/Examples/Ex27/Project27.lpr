program Project27;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit27 in 'Unit27.pas' {Form27};

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm27, Form27);
  Application.Run;
end.
