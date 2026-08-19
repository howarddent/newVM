unit uFreqKeypad;

{*******************************************************************************

     A small modal numeric-entry keypad for setting a frequency -
     digits 0-9, a decimal point, and unit buttons (kHz/MHz/GHz),
     matching the keypad-style frequency entry real spectrum analysers
     use: type the digits, then press whichever unit the typed number is
     in - that press both scales it to Hz and commits/closes the dialog.
     A bare TFloatSpinEdit (uSDRMain.pas's own FreqEdit) is fine for
     nudging a frequency with the spinner arrows, but typing an exact
     value like "437.35" digit-by-digit is what this is for instead - the
     two are complementary, not a replacement of one by the other.

     Deliberately its own separate popup rather than embedded in
     uSDRMain.pas's already-packed horizontal control strip - a 2D button
     grid doesn't fit that layout, and a popup keypad is the recognised
     convention for this kind of entry anyway.

     Entry is a plain string built up one character at a time
     (DigitButtonClick/DecimalButtonClick), so leading/trailing zeros and
     a single decimal point behave exactly as typed - no live numeric
     parsing/reformatting happens until a unit button commits it.

     ShowFrequencyKeypad is the only thing callers need: it owns the
     form's create/show-modal/free lifecycle, and returns whether a unit
     button actually committed a value (vs. Cancel or the window being
     closed, both of which leave ResultHz untouched).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls;

type

  { TFreqKeypadForm }

  TFreqKeypadForm = class(TForm)
    CancelButton: TButton;
    ClearButton: TButton;
    DecimalButton: TButton;
    Digit0Button: TButton;
    Digit1Button: TButton;
    Digit2Button: TButton;
    Digit3Button: TButton;
    Digit4Button: TButton;
    Digit5Button: TButton;
    Digit6Button: TButton;
    Digit7Button: TButton;
    Digit8Button: TButton;
    Digit9Button: TButton;
    DisplayEdit: TEdit;
    GHzButton: TButton;
    kHzButton: TButton;
    MHzButton: TButton;
    procedure CancelButtonClick(Sender: TObject);
    procedure ClearButtonClick(Sender: TObject);
    procedure DecimalButtonClick(Sender: TObject);
    procedure DigitButtonClick(Sender: TObject);
    procedure UnitButtonClick(Sender: TObject);
  private
    FEntry: string;
    FMinHz, FMaxHz: Double;
    FResultHz: Double;
    procedure UpdateDisplay;
  public
    property MinHz: Double read FMinHz write FMinHz;
    property MaxHz: Double read FMaxHz write FMaxHz;
    property ResultHz: Double read FResultHz;
  end;

// Shows the keypad modally, starting from an empty entry (real keypads
// don't pre-fill the previous value - the whole point is typing a fresh
// one). MinHz/MaxHz (pass 0/0 for "no limit") clamp the committed
// result, matching whatever the connected device's own tunable range
// is. Returns True and sets ResultHz iff a unit button was actually
// pressed; Cancel or closing the window returns False with ResultHz
// untouched.
function ShowFrequencyKeypad(MinHz, MaxHz: Double; out ResultHz: Double): Boolean;

implementation

{$R *.lfm}

function ShowFrequencyKeypad(MinHz, MaxHz: Double; out ResultHz: Double): Boolean;
var
  Frm: TFreqKeypadForm;
begin
  Frm := TFreqKeypadForm.Create(nil);
  try
    Frm.MinHz := MinHz;
    Frm.MaxHz := MaxHz;
    Result := Frm.ShowModal = mrOK;
    if Result then ResultHz := Frm.ResultHz;
  finally
    Frm.Free;
  end;
end;

{ TFreqKeypadForm }

procedure TFreqKeypadForm.UpdateDisplay;
begin
  if FEntry = '' then
    DisplayEdit.Text := '0'
  else
    DisplayEdit.Text := FEntry;
end;

procedure TFreqKeypadForm.DigitButtonClick(Sender: TObject);
const
  MaxEntryLength = 12;
begin
  if Length(FEntry) >= MaxEntryLength then Exit;
  FEntry := FEntry + (Sender as TButton).Caption;
  UpdateDisplay;
end;

// One decimal point only - a second press while one is already present
// is simply ignored, rather than producing an unparseable string.
procedure TFreqKeypadForm.DecimalButtonClick(Sender: TObject);
begin
  if Pos('.', FEntry) > 0 then Exit;
  if FEntry = '' then FEntry := '0';   // "." alone reads as "0."
  FEntry := FEntry + '.';
  UpdateDisplay;
end;

procedure TFreqKeypadForm.ClearButtonClick(Sender: TObject);
begin
  FEntry := '';
  UpdateDisplay;
end;

procedure TFreqKeypadForm.CancelButtonClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

// The typed number, scaled by whichever unit button was pressed
// (kHz/MHz/GHz -> 1e3/1e6/1e9), clamped to [MinHz,MaxHz] if a real range
// was supplied (MinHz=MaxHz=0 means "no limit" - see
// ShowFrequencyKeypad's own comment), then closes the dialog reporting
// success. An empty entry has nothing to commit - the button press is
// simply ignored rather than committing a meaningless 0Hz.
procedure TFreqKeypadForm.UnitButtonClick(Sender: TObject);
var
  Value, Multiplier, Hz: Double;
  FS: TFormatSettings;
begin
  if FEntry = '' then Exit;
  // FEntry is built one keypress at a time with a literal '.'
  // (DecimalButtonClick), regardless of the system locale's own decimal
  // separator - parse it the same way, rather than via the locale-
  // dependent default TryStrToFloat, which would misparse it wherever
  // DecimalSeparator isn't '.'.
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(FEntry, Value, FS) then Exit;

  case (Sender as TButton).Caption of
    'kHz': Multiplier := 1.0e3;
    'MHz': Multiplier := 1.0e6;
    'GHz': Multiplier := 1.0e9;
  else
    Exit;
  end;

  Hz := Value * Multiplier;
  if (FMaxHz > FMinHz) then begin
    if Hz < FMinHz then Hz := FMinHz;
    if Hz > FMaxHz then Hz := FMaxHz;
  end;

  FResultHz := Hz;
  ModalResult := mrOK;
end;

end.
