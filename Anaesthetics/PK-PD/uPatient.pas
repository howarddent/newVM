unit uPatient;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, OKCANCL2, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TdlgPatient = class(TOKRightDlg)
    GroupBox2: TGroupBox;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    RadioGroup1: TRadioGroup;
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  dlgPatient: TdlgPatient;

implementation

{$R *.dfm}

end.
