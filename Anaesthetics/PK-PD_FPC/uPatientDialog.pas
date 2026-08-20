unit uPatientDialog;

{*******************************************************************************

     Patient-entry dialog for the Anaesthetics/PK-PD_FPC demo.

     The original Anaesthetics/PK-PD/uPatient.pas was never finished - an
     empty TOKRightDlg descendant with an unused RadioGroup1 and no working
     fields, no OK/Cancel logic, and no .dfm at all. This is a real,
     functional replacement: weight/height/age/sex entry with basic range
     validation, used by uPKPDMain.pas's "Edit Patient..." button.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  uBodyStats;

type

  { TPatientDialogForm }

  TPatientDialogForm = class(TForm)
    GroupBox1: TGroupBox;
    LabelWeight: TLabel;
    EditWeight: TEdit;
    LabelHeight: TLabel;
    EditHeight: TEdit;
    LabelAge: TLabel;
    EditAge: TEdit;
    RadioGroupSex: TRadioGroup;
    ButtonOK: TButton;
    ButtonCancel: TButton;
    procedure ButtonOKClick(Sender: TObject);
  private
    FWeight, FHeight : Double;
    FAge : TAge;
    FSex : TSex;
    function ValidateAndStore: Boolean;
  public
    property Weight: Double read FWeight write FWeight;
    property Height: Double read FHeight write FHeight;
    property Age: TAge read FAge write FAge;
    property Sex: TSex read FSex write FSex;
    procedure LoadFromFields;
  end;

var
  PatientDialogForm: TPatientDialogForm;

implementation

{$R *.lfm}

{ TPatientDialogForm }

procedure TPatientDialogForm.LoadFromFields;
begin
  EditWeight.Text := FloatToStr(FWeight);
  EditHeight.Text := FloatToStr(FHeight);
  EditAge.Text := IntToStr(FAge);
  if FSex = Male then RadioGroupSex.ItemIndex := 0 else RadioGroupSex.ItemIndex := 1;
end;

function TPatientDialogForm.ValidateAndStore: Boolean;
var
  W, H : Double;
  A : Integer;
begin
  result := False;
  if (not TryStrToFloat(EditWeight.Text, W)) or (W <= 0) or (W > 500) then begin
    ShowMessage('Enter a valid weight in kg (0-500).');
    Exit;
  end;
  if (not TryStrToFloat(EditHeight.Text, H)) or (H <= 0) or (H > 2.5) then begin
    ShowMessage('Enter a valid height in metres (0-2.5).');
    Exit;
  end;
  if (not TryStrToInt(EditAge.Text, A)) or (A < 0) or (A > 110) then begin
    ShowMessage('Enter a valid age in years (0-110).');
    Exit;
  end;
  FWeight := W;
  FHeight := H;
  FAge := A;
  if RadioGroupSex.ItemIndex = 0 then FSex := Male else FSex := Female;
  result := True;
end;

procedure TPatientDialogForm.ButtonOKClick(Sender: TObject);
begin
  // Only close (and only take effect) once the entered values pass
  // validation - ButtonOK has no ModalResult set in the .lfm, so an invalid
  // entry just re-shows the message and leaves the dialog open.
  if ValidateAndStore then ModalResult := mrOK;
end;

end.
