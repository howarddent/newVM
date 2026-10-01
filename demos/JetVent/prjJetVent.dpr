program prjJetVent;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {fmMain},
  uJetCalc in 'uJetCalc.pas',
  naca1135 in 'naca1135.pas',
  rayfanno in 'rayfanno.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
