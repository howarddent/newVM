unit uDefibForm;

{ The window: the torso and its current in 3D on the left, the report on
  the right, and along the bottom the shock's current I(t) with a cursor
  at the moment shown, beside the controls.

  Play runs the shock in slow motion - its 14 ms over about six seconds,
  0.1 ms a frame - and loops; the slider steps through it by hand. The
  status line gives, at that moment, the current, the volume of tissue
  above the cloud's level, and how much of the myocardium is above the
  5 V/cm usually taken to defibrillate. The Shock buttons switch between
  the monophasic and biphasic waveforms; the field is the same solution
  either way, so only the waveform and the report are recomputed.

  Built in code rather than from a .lfm, like ThermEx1's window. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math, Graphics, Forms, Controls, StdCtrls, ExtCtrls,
  ComCtrls, Spin,
  newVM,
  uDefibModel, uDefibView, uVMPlot2D;

type

  TDefibForm = class(TForm)

  private

    FModel : TDefibModel;
    FView : TDefibView;
    FWave : TVMPlot2D;
    FMemo : TMemo;
    FTrack : TTrackBar;
    FPlay : TButton;
    FStatus : TLabel;
    FLines, FCloud, FOrgans, FBones : TCheckBox;
    FMono, FBi : TRadioButton;
    FLevel : TFloatSpinEdit;
    FTimer : TTimer;
    FFrame : Integer;

    procedure ShowFrame(N : Integer);
    procedure TrackChange(Sender : TObject);
    procedure PlayClick(Sender : TObject);
    procedure Tick(Sender : TObject);
    procedure OptionChange(Sender : TObject);
    procedure ResetClick(Sender : TObject);
    procedure WaveChange(Sender : TObject);

    // The waveform plot, captions and report, from the model's waveform.
    procedure ShowWaveform;

  public

    procedure Attach(AModel : TDefibModel);

    // Show the frame nearest time T (s).
    procedure ShowTime(T : Double);

    property View : TDefibView read FView;
    property Wave : TVMPlot2D read FWave;

  end;

implementation

procedure TDefibForm.Attach(AModel : TDefibModel);
var
  Bottom, Controls_, Right : TPanel;
  n : Integer;
  Lbl : TLabel;
  Reset : TButton;
begin

  FModel := AModel;

  Width := 1500;
  Height := 950;
  Position := poScreenCenter;

  (******************** BOTTOM: WAVEFORM AND CONTROLS ********************)

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 250;
  Bottom.BevelOuter := bvNone;

  Controls_ := TPanel.Create(Self);
  Controls_.Parent := Bottom;
  Controls_.Align := alRight;
  Controls_.Width := 470;
  Controls_.BevelOuter := bvNone;

  FWave := TVMPlot2D.Create(Self);
  FWave.Parent := Bottom;
  FWave.Align := alClient;

  n := Length(FModel.WaveT);
  FWave.XAxisTitle := 'time, ms';
  FWave.YAxisTitle := 'current, A';

  FPlay := TButton.Create(Self);
  FPlay.Parent := Controls_;
  FPlay.SetBounds(12, 10, 90, 30);
  FPlay.Caption := 'Play';
  FPlay.OnClick := PlayClick;

  Reset := TButton.Create(Self);
  Reset.Parent := Controls_;
  Reset.SetBounds(110, 10, 90, 30);
  Reset.Caption := 'Reset view';
  Reset.OnClick := ResetClick;

  FTrack := TTrackBar.Create(Self);
  FTrack.Parent := Controls_;
  FTrack.SetBounds(8, 46, 450, 30);
  FTrack.Min := 0;
  FTrack.Max := n - 1;
  FTrack.TickStyle := tsNone;
  FTrack.OnChange := TrackChange;

  FLines := TCheckBox.Create(Self);
  FLines.Parent := Controls_;
  FLines.SetBounds(12, 84, 100, 22);
  FLines.Caption := 'Field lines';
  FLines.Checked := True;
  FLines.OnChange := OptionChange;

  FCloud := TCheckBox.Create(Self);
  FCloud.Parent := Controls_;
  FCloud.SetBounds(112, 84, 115, 22);
  FCloud.Caption := 'Current cloud';
  FCloud.Checked := True;
  FCloud.OnChange := OptionChange;

  FOrgans := TCheckBox.Create(Self);
  FOrgans.Parent := Controls_;
  FOrgans.SetBounds(228, 84, 125, 22);
  FOrgans.Caption := 'Heart and lungs';
  FOrgans.Checked := True;
  FOrgans.OnChange := OptionChange;

  FBones := TCheckBox.Create(Self);
  FBones.Parent := Controls_;
  FBones.SetBounds(355, 84, 110, 22);
  FBones.Caption := 'Skeleton';
  FBones.Checked := True;
  FBones.OnChange := OptionChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Controls_;
  Lbl.SetBounds(12, 118, 220, 22);
  Lbl.Caption := 'Cloud shows |J| above, mA/cm2:';

  FLevel := TFloatSpinEdit.Create(Self);
  FLevel.Parent := Controls_;
  FLevel.SetBounds(240, 114, 90, 26);
  FLevel.DecimalPlaces := 1;
  FLevel.MinValue := 0.5;
  FLevel.MaxValue := 500;
  FLevel.Increment := 1;
  FLevel.Value := 50.0;
  FLevel.OnChange := OptionChange;

  Lbl := TLabel.Create(Self);
  Lbl.Parent := Controls_;
  Lbl.SetBounds(12, 150, 50, 22);
  Lbl.Caption := 'Shock:';

  FMono := TRadioButton.Create(Self);
  FMono.Parent := Controls_;
  FMono.SetBounds(62, 148, 110, 22);
  FMono.Caption := 'monophasic';
  FMono.Checked := not FModel.Biphasic;
  FMono.OnChange := WaveChange;

  FBi := TRadioButton.Create(Self);
  FBi.Parent := Controls_;
  FBi.SetBounds(175, 148, 100, 22);
  FBi.Caption := 'biphasic';
  FBi.Checked := FModel.Biphasic;
  FBi.OnChange := WaveChange;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Controls_;
  FStatus.SetBounds(12, 176, 450, 70);
  FStatus.AutoSize := False;
  FStatus.WordWrap := True;
  FStatus.Font.Style := [fsBold];

  (******************** RIGHT: REPORT ********************)

  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alRight;
  Right.Width := 560;
  Right.BevelOuter := bvNone;

  FMemo := TMemo.Create(Self);
  FMemo.Parent := Right;
  FMemo.Align := alClient;
  FMemo.ReadOnly := True;
  FMemo.ScrollBars := ssAutoBoth;
  FMemo.WordWrap := False;
  FMemo.Font.Name := 'Courier New';
  FMemo.Font.Size := 9;

  (******************** CENTRE: THE TORSO ********************)

  FView := TDefibView.Create(Self);
  FView.Parent := Self;
  FView.Align := alClient;
  FView.SetModel(FModel);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 40;
  FTimer.Enabled := False;
  FTimer.OnTimer := Tick;

  OptionChange(nil);
  ShowWaveform;
  ShowTime(FModel.TPeak);

end;

procedure TDefibForm.ShowWaveform;
var
  X, Y : TVMobj;
  i, n : Integer;
  Aniso : String;
begin

  n := Length(FModel.WaveT);
  X := TVMobj.Create(1, n);
  Y := TVMobj.Create(1, n);
  for i := 0 to n - 1 do
  begin
    X[0, i] := 1000 * FModel.WaveT[i];
    Y[0, i] := FModel.WaveI[i];
  end;

  FWave.ClearSeries;
  FWave.SetData(X, [Y]);
  FWave.SetSeriesStyle(0, RGBToColor(200, 150, 0), 2.0, plsSolid, 'shock current');

  if FModel.Biphasic then
    FWave.Title := Format('Biphasic truncated exponential, 200 J delivered into %.0f ohm',
      [FModel.Resistance])
  else
    FWave.Title := Format('Monophasic damped sine, 200 J setting, into %.0f ohm',
      [FModel.Resistance]);

  if FModel.Anisotropic then
    Aniso := ', anisotropic muscle'
  else
    Aniso := '';
  Caption := Format('Defibrillation - current of a 200 J %s shock through the torso%s',
    [FModel.WaveName, Aniso]);

  FMemo.Lines.Assign(FModel.Report);

  // The view's brightness is scaled to this waveform's peak.
  FView.SetModel(FModel);

end;

procedure TDefibForm.WaveChange(Sender : TObject);
begin
  if FBi.Checked = FModel.Biphasic then
    Exit;
  FModel.Biphasic := FBi.Checked;
  ShowWaveform;
  ShowTime(FModel.TPeak);
end;

procedure TDefibForm.ShowFrame(N : Integer);
var
  I, T, Vol, Fr : Double;
begin

  FFrame := EnsureRange(N, 0, High(FModel.WaveT));
  T := FModel.WaveT[FFrame];
  I := FModel.WaveI[FFrame];

  FView.SetCurrent(I);

  FWave.ClearXMarkers;
  FWave.AddXMarker(1000 * T, clRed, '');

  Vol := FModel.VolumeAbove(FView.JLevel, I);
  Fr := FModel.MyoFractionAbove(DefibFieldVcm * 100, I);

  FStatus.Caption := Format(
    't = %.2f ms     I = %.1f A'#10 +
    'tissue above %.1f mA/cm2: %.2f litres'#10 +
    'myocardium at %.0f V/cm or more: %.0f %%',
    [1000 * T, I, FView.JLevel / 10, 1000 * Vol, DefibFieldVcm, 100 * Fr]);

  if FTrack.Position <> FFrame then
    FTrack.Position := FFrame;

end;

procedure TDefibForm.ShowTime(T : Double);
begin
  ShowFrame(Round(T / WaveSample));
end;

procedure TDefibForm.TrackChange(Sender : TObject);
begin
  if FTrack.Position <> FFrame then
    ShowFrame(FTrack.Position);
end;

procedure TDefibForm.PlayClick(Sender : TObject);
begin
  FTimer.Enabled := not FTimer.Enabled;
  if FTimer.Enabled then
  begin
    FPlay.Caption := 'Pause';
    if FFrame >= High(FModel.WaveT) then
      ShowFrame(0);
  end
  else
    FPlay.Caption := 'Play';
end;

procedure TDefibForm.Tick(Sender : TObject);
begin
  if FFrame >= High(FModel.WaveT) then
    ShowFrame(0)
  else
    ShowFrame(FFrame + 1);
end;

procedure TDefibForm.OptionChange(Sender : TObject);
begin
  FView.ShowLines := FLines.Checked;
  FView.ShowCloud := FCloud.Checked;
  FView.ShowOrgans := FOrgans.Checked;
  FView.ShowBones := FBones.Checked;
  // mA/cm2 to A/m2.
  FView.JLevel := 10 * FLevel.Value;
  if Sender <> nil then
    ShowFrame(FFrame);
end;

procedure TDefibForm.ResetClick(Sender : TObject);
begin
  FView.ResetView;
end;

end.
