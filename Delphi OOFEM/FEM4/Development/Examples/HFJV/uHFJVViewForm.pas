unit uHFJVViewForm;

{ HFJVView's window: one steady jet-ventilation cycle of the abdominal
  wall and diaphragm, as anim_wall.py draws it, but live.

    left    the cavity (uWallView), its moving surfaces displaced and
            coloured by the outward displacement, with a colour bar;
    right   above: the front midline's displacement from pubis to
            xiphoid now (black) and its envelope over the cycle (grey);
            below: the lung volume over the cycle, the jet's on-time
            shaded, and the current instant.

  The data is a file written by `hfjvrun --anim=<file>`. "Open..." reads
  one; "Compute" runs hfjvrun (beside this program) for the rate,
  pressure, I:E, cannula and abdomen set in the second row, writes the
  file into mesh/ and shows it. A file already computed for the same
  settings is loaded rather than computed again. The torso takes about
  a minute (30 harmonics, ~1.3 s each), the box a few seconds. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, Process,
  newVM, uVMPlot2D, uWallAnim, uWallView;

type

  THFJVViewForm = class(TForm)
  private
    FAnim : TWallAnim;
    FDir : String;               // where the program and hfjvrun live

    pnlTop, pnlRow1, pnlRow2, pnlRight, pnlLeft : TPanel;
    FView : TWallView;
    FBar : TPaintBox;
    FProfile, FVolume : TVMPlot2D;
    FStatus : TStatusBar;

    btnOpen, btnPlay, btnReset, btnSave, btnCompute : TButton;
    tbFrame : TTrackBar;
    lblFrame, lblRun : TLabel;
    seExag : TFloatSpinEdit;
    seFps : TSpinEdit;
    cbEdges : TCheckBox;

    seRate : TSpinEdit;
    seDP, seIE : TFloatSpinEdit;
    cbCannula, cbAbdomen : TComboBox;
    pbRun : TProgressBar;

    FPlay, FPoll : TTimer;
    FProc : TProcess;
    FProcOut : String;
    FProcFile : String;
    FUpdating : Boolean;

    function AddLabel(AParent : TWinControl; const S : String) : TLabel;
    procedure Place(C : TControl; AParent : TWinControl; W : Integer);
    procedure FormResized(Sender : TObject);
    procedure OpenClick(Sender : TObject);
    procedure PlayClick(Sender : TObject);
    procedure ResetClick(Sender : TObject);
    procedure SaveClick(Sender : TObject);
    procedure ComputeClick(Sender : TObject);
    procedure FrameChange(Sender : TObject);
    procedure ExagChange(Sender : TObject);
    procedure FpsChange(Sender : TObject);
    procedure EdgesChange(Sender : TObject);
    procedure PlayTick(Sender : TObject);
    procedure PollTick(Sender : TObject);
    procedure BarPaint(Sender : TObject);
    procedure ShowFrame(j : Integer);
    procedure UpdatePlots(j : Integer);
    procedure SetRunning(R : Boolean);
  public
    constructor CreateNew(AOwner : TComponent; Num : Integer = 0); override;
    destructor Destroy; override;
    procedure LoadAnim(const Fn : String);
    // stops the animation at frame j
    procedure ShowFrameAt(j : Integer);
    function SaveSnapshot(const Prefix : String) : Boolean;
    // as the Compute button; Box picks the box abdomen
    procedure Compute(Box : Boolean);
    function Computing : Boolean;
    property Anim : TWallAnim read FAnim;
  end;

implementation

const
  CannulaNames : array[0..5] of String =
    ('Lindholm', 'Cook', 'Biro', '14G Venflon', '16G Venflon', '18G Venflon');

function DotFS : TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

constructor THFJVViewForm.CreateNew(AOwner : TComponent; Num : Integer);
var
  i : Integer;
begin
  inherited CreateNew(AOwner, Num);
  FDir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  Caption := 'HFJV - abdominal wall and diaphragm over one jet cycle';
  Width := 1380;
  Height := 820;
  Position := poScreenCenter;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 72;
  pnlTop.BevelOuter := bvNone;

  pnlRow1 := TPanel.Create(Self);
  pnlRow1.Parent := pnlTop;
  pnlRow1.Align := alTop;
  pnlRow1.Height := 36;
  pnlRow1.BevelOuter := bvNone;
  pnlRow1.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  pnlRow1.ChildSizing.ControlsPerLine := 100;
  pnlRow1.ChildSizing.HorizontalSpacing := 6;
  pnlRow1.ChildSizing.LeftRightSpacing := 6;
  pnlRow1.ChildSizing.TopBottomSpacing := 5;

  pnlRow2 := TPanel.Create(Self);
  pnlRow2.Parent := pnlTop;
  pnlRow2.Align := alClient;
  pnlRow2.BevelOuter := bvNone;
  pnlRow2.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
  pnlRow2.ChildSizing.ControlsPerLine := 100;
  pnlRow2.ChildSizing.HorizontalSpacing := 6;
  pnlRow2.ChildSizing.LeftRightSpacing := 6;
  pnlRow2.ChildSizing.TopBottomSpacing := 3;

  // row 1: the file and the animation
  btnOpen := TButton.Create(Self);
  btnOpen.Caption := 'Open...';
  btnOpen.OnClick := OpenClick;
  Place(btnOpen, pnlRow1, 80);

  btnPlay := TButton.Create(Self);
  btnPlay.Caption := 'Pause';
  btnPlay.OnClick := PlayClick;
  Place(btnPlay, pnlRow1, 70);

  AddLabel(pnlRow1, 'frame');
  tbFrame := TTrackBar.Create(Self);
  tbFrame.Min := 0;
  tbFrame.Max := 47;
  tbFrame.TickStyle := tsNone;
  tbFrame.OnChange := FrameChange;
  Place(tbFrame, pnlRow1, 260);
  lblFrame := AddLabel(pnlRow1, '');
  lblFrame.AutoSize := False;
  lblFrame.Width := 150;

  AddLabel(pnlRow1, 'exaggeration x');
  seExag := TFloatSpinEdit.Create(Self);
  seExag.MinValue := 0;
  seExag.MaxValue := 1000;
  seExag.Increment := 1;
  seExag.DecimalPlaces := 0;
  seExag.Value := 10;
  seExag.OnChange := ExagChange;
  Place(seExag, pnlRow1, 70);

  AddLabel(pnlRow1, 'frames/s');
  seFps := TSpinEdit.Create(Self);
  seFps.MinValue := 1;
  seFps.MaxValue := 60;
  seFps.Value := 12;
  seFps.OnChange := FpsChange;
  Place(seFps, pnlRow1, 55);

  cbEdges := TCheckBox.Create(Self);
  cbEdges.Caption := 'mesh';
  cbEdges.OnChange := EdgesChange;
  Place(cbEdges, pnlRow1, 60);

  btnReset := TButton.Create(Self);
  btnReset.Caption := 'Reset view';
  btnReset.OnClick := ResetClick;
  Place(btnReset, pnlRow1, 90);

  btnSave := TButton.Create(Self);
  btnSave.Caption := 'Save PNG...';
  btnSave.OnClick := SaveClick;
  Place(btnSave, pnlRow1, 95);

  // row 2: computing a new cycle with hfjvrun
  AddLabel(pnlRow2, 'rate /min');
  seRate := TSpinEdit.Create(Self);
  seRate.MinValue := 20;
  seRate.MaxValue := 1200;
  seRate.Increment := 10;
  seRate.Value := 200;
  Place(seRate, pnlRow2, 65);

  AddLabel(pnlRow2, 'driving pressure, bar');
  seDP := TFloatSpinEdit.Create(Self);
  seDP.MinValue := 0.5;
  seDP.MaxValue := 3.5;
  seDP.Increment := 0.25;
  seDP.DecimalPlaces := 2;
  seDP.Value := 2;
  Place(seDP, pnlRow2, 65);

  AddLabel(pnlRow2, 'I:E  1:');
  seIE := TFloatSpinEdit.Create(Self);
  seIE.MinValue := 0.5;
  seIE.MaxValue := 4;
  seIE.Increment := 0.5;
  seIE.DecimalPlaces := 1;
  seIE.Value := 1;
  Place(seIE, pnlRow2, 55);

  AddLabel(pnlRow2, 'cannula');
  cbCannula := TComboBox.Create(Self);
  cbCannula.Style := csDropDownList;
  for i := 0 to High(CannulaNames) do
    cbCannula.Items.Add(CannulaNames[i]);
  Place(cbCannula, pnlRow2, 120);
  cbCannula.ItemIndex := 2;

  AddLabel(pnlRow2, 'abdomen');
  cbAbdomen := TComboBox.Create(Self);
  cbAbdomen.Style := csDropDownList;
  cbAbdomen.Items.Add('torso (Defibrillation''s)');
  cbAbdomen.Items.Add('box 300 x 260 x 140 mm');
  Place(cbAbdomen, pnlRow2, 190);
  cbAbdomen.ItemIndex := 0;

  btnCompute := TButton.Create(Self);
  btnCompute.Caption := 'Compute';
  btnCompute.OnClick := ComputeClick;
  Place(btnCompute, pnlRow2, 90);

  pbRun := TProgressBar.Create(Self);
  pbRun.Min := 0;
  pbRun.Max := 30;
  Place(pbRun, pnlRow2, 140);

  lblRun := AddLabel(pnlRow2, '');

  // right: the midline and the lung volume
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 520;
  pnlRight.BevelOuter := bvNone;
  pnlRight.OnResize := FormResized;

  FProfile := TVMPlot2D.Create(Self);
  FProfile.Parent := pnlRight;
  FProfile.Align := alTop;
  FProfile.Height := 380;
  FProfile.Title := 'Front midline';
  FProfile.XAxisTitle := 'distance along the body, mm   (pubis left, xiphoid right)';
  FProfile.YAxisTitle := 'outward displacement, mm';

  FVolume := TVMPlot2D.Create(Self);
  FVolume.Parent := pnlRight;
  FVolume.Align := alClient;
  FVolume.Title := 'Lung volume (mean removed)';
  FVolume.XAxisTitle := 'time in the cycle, ms';
  FVolume.YAxisTitle := 'lung volume, mL';
  FVolume.LegendCorner := lcBottomRight;

  // left: the cavity and the colour bar
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alClient;
  pnlLeft.BevelOuter := bvNone;

  FBar := TPaintBox.Create(Self);
  FBar.Parent := pnlLeft;
  FBar.Align := alBottom;
  FBar.Height := 54;
  FBar.OnPaint := BarPaint;

  FView := TWallView.Create(Self);
  FView.Parent := pnlLeft;
  FView.Align := alClient;

  FPlay := TTimer.Create(Self);
  FPlay.Interval := 1000 div seFps.Value;
  FPlay.OnTimer := PlayTick;
  FPlay.Enabled := False;

  FPoll := TTimer.Create(Self);
  FPoll.Interval := 150;
  FPoll.OnTimer := PollTick;
  FPoll.Enabled := False;

  FAnim := TWallAnim.Create;
end;

destructor THFJVViewForm.Destroy;
begin
  FPlay.Enabled := False;
  FPoll.Enabled := False;
  if FProc <> nil then
  begin
    if FProc.Running then
      FProc.Terminate(1);
    FProc.Free;
  end;
  FAnim.Free;
  inherited Destroy;
end;

function THFJVViewForm.AddLabel(AParent : TWinControl; const S : String) : TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := S;
  Result.Layout := tlCenter;
  Result.Parent := AParent;
end;

procedure THFJVViewForm.Place(C : TControl; AParent : TWinControl; W : Integer);
begin
  C.Width := W;
  C.Constraints.MinWidth := W;
  C.Parent := AParent;
end;

procedure THFJVViewForm.FormResized(Sender : TObject);
begin
  FProfile.Height := pnlRight.ClientHeight * 11 div 20;
end;

procedure THFJVViewForm.LoadAnim(const Fn : String);
var
  A : TWallAnim;
  ie : Double;
begin
  A := TWallAnim.Create;
  try
    A.LoadFromFile(Fn);
  except
    A.Free;
    raise;
  end;
  FAnim.Free;
  FAnim := A;
  FView.SetAnim(FAnim);

  FUpdating := True;
  try
    tbFrame.Max := FAnim.Frames - 1;
    tbFrame.Position := 0;
    seExag.Value := Max(1, Round(0.025 / Max(FAnim.MaxDisp, 1E-9)));
    FView.Exaggeration := seExag.Value;
    seRate.Value := Round(FAnim.Rate);
    seDP.Value := FAnim.DrivingP;
    ie := (1 - FAnim.Ti) / Max(FAnim.Ti, 1E-6);
    seIE.Value := ie;
    cbAbdomen.ItemIndex := Ord(FAnim.IsBox);
  finally
    FUpdating := False;
  end;

  // the midline's envelope and the volume curve don't change per frame,
  // but TVMPlot2D's SetData replaces every series, so they're redrawn
  // with the current instant each frame (UpdatePlots)
  if FAnim.IsBox then
    FProfile.XAxisTitle := 'distance from the diaphragm end, mm'
  else
    FProfile.XAxisTitle := 'distance along the body, mm   (pubis left, xiphoid right)';
  FVolume.ClearXBands;
  FVolume.AddXBand(0, 1000 * FAnim.Ti * FAnim.Period, $00B3E9FF, 'jet on');
  FBar.Invalidate;
  ShowFrame(0);
  FPlay.Enabled := True;
  btnPlay.Caption := 'Pause';
end;

procedure THFJVViewForm.ShowFrameAt(j : Integer);
begin
  FPlay.Enabled := False;
  btnPlay.Caption := 'Play';
  if FAnim.Frames > 0 then
    ShowFrame(EnsureRange(j, 0, FAnim.Frames - 1));
end;

procedure THFJVViewForm.UpdatePlots(j : Integer);
var
  X, Yn, Ymax, Ymin, T, V : TVMobj;
  i, k, a, nm : Integer;
  lo, hi : Double;
begin
  nm := Length(FAnim.Mid);
  if nm >= 2 then
  begin
    X := TVMobj.Create(1, nm);
    Yn := TVMobj.Create(1, nm);
    Ymax := TVMobj.Create(1, nm);
    Ymin := TVMobj.Create(1, nm);
    for i := 0 to nm - 1 do
    begin
      a := FAnim.Mid[i];
      X[0, i] := 1000 * (FAnim.P[a].Y - FAnim.P[FAnim.Mid[0]].Y);
      Yn[0, i] := 1000 * FAnim.D[a][j];
      lo := Infinity; hi := -Infinity;
      for k := 0 to FAnim.Frames - 1 do
      begin
        lo := Min(lo, FAnim.D[a][k]);
        hi := Max(hi, FAnim.D[a][k]);
      end;
      Ymax[0, i] := 1000 * hi;
      Ymin[0, i] := 1000 * lo;
    end;
    FProfile.ClearSeries;
    FProfile.SetSeriesStyle(0, clBlack, 2.5, plsSolid, 'now');
    FProfile.SetSeriesStyle(1, $00999999, 1.5, plsDash, 'envelope over the cycle');
    FProfile.SetSeriesStyle(2, $00999999, 1.5, plsDash, '');
    FProfile.SetData(X, [Yn, Ymax, Ymin]);
  end;

  T := TVMobj.Create(1, FAnim.Frames + 1);
  V := TVMobj.Create(1, FAnim.Frames + 1);
  for k := 0 to FAnim.Frames do
  begin
    T[0, k] := 1000 * FAnim.Period * k / FAnim.Frames;
    V[0, k] := FAnim.VL[k mod FAnim.Frames];   // closed: the cycle repeats
  end;
  FVolume.ClearSeries;
  FVolume.SetSeriesStyle(0, $00D6782A, 2, plsSolid, 'lung volume');
  FVolume.SetSeriesStyle(1, $00D6782A, 0, plsNone, 'now', pmsCircle, 10);
  FVolume.SetData(T, [V]);
  FVolume.PlotXY(1000 * FAnim.TimeAt(j), FAnim.VL[j], 1);
end;

procedure THFJVViewForm.ShowFrame(j : Integer);
var
  FS : TFormatSettings;
begin
  if FAnim.Frames = 0 then
    Exit;
  FS := DotFS;
  FView.Frame := j;
  if tbFrame.Position <> j then
  begin
    FUpdating := True;
    tbFrame.Position := j;
    FUpdating := False;
  end;
  lblFrame.Caption := Format('t = %.0f of %.0f ms', [1000 * FAnim.TimeAt(j), 1000 * FAnim.Period], FS);
  UpdatePlots(j);
  FStatus.SimpleText := Format('%s   |   %.0f /min, %.2f bar, I:E 1:%.1f, %s   |   t = %.0f ms, %s   |   '
    + 'largest displacement %.2f mm, drawn x%.0f   |   %d nodes, %d moving',
    [ExtractFileName(FAnim.FileName), FAnim.Rate, FAnim.DrivingP,
     (1 - FAnim.Ti) / Max(FAnim.Ti, 1E-6), IfThen(FAnim.IsBox, 'box abdomen', 'torso abdomen'),
     1000 * FAnim.TimeAt(j), IfThen(FAnim.JetOn(j), 'jet ON', 'jet off'),
     1000 * FAnim.MaxDisp, FView.Exaggeration, FAnim.NbNodes, FAnim.NMoving], FS);
end;

procedure THFJVViewForm.BarPaint(Sender : TObject);
var
  C : TCanvas;
  x0, x1, y0, y1, x, i : Integer;
  r, g, b : Single;
  lim, v : Double;
  S : String;
  FS : TFormatSettings;
begin
  C := FBar.Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, FBar.Width, FBar.Height);
  if FAnim.Frames = 0 then
    Exit;
  FS := DotFS;
  lim := 1000 * FAnim.MaxDisp;
  x0 := FBar.Width div 6;
  x1 := FBar.Width - x0;
  y0 := 6;
  y1 := 22;
  for x := x0 to x1 do
  begin
    DispColour(2 * (x - x0) / Max(x1 - x0, 1) - 1, r, g, b);
    C.Pen.Color := RGBToColor(Round(255 * r), Round(255 * g), Round(255 * b));
    C.Line(x, y0, x, y1);
  end;
  C.Pen.Color := clGray;
  C.Brush.Style := bsClear;
  C.Rectangle(x0, y0, x1 + 1, y1);
  C.Font.Color := clBlack;
  C.Font.Size := 8;
  for i := -2 to 2 do
  begin
    v := lim * i / 2;
    x := x0 + Round((i + 2) / 4 * (x1 - x0));
    C.Line(x, y1, x, y1 + 3);
    S := FormatFloat('0.00', v, FS);
    C.TextOut(x - C.TextWidth(S) div 2, y1 + 4, S);
  end;
  S := 'outward displacement, mm  (blue inwards, red outwards; grey: rigid)';
  C.TextOut((x0 + x1 - C.TextWidth(S)) div 2, y1 + 17, S);
end;

procedure THFJVViewForm.OpenClick(Sender : TObject);
var
  D : TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Open an hfjvrun --anim file';
    D.InitialDir := FDir + 'mesh';
    D.Filter := 'Animation files (*.txt)|*.txt|All files|*';
    if D.Execute then
      LoadAnim(D.FileName);
  finally
    D.Free;
  end;
end;

procedure THFJVViewForm.PlayClick(Sender : TObject);
begin
  FPlay.Enabled := not FPlay.Enabled;
  if FPlay.Enabled then
    btnPlay.Caption := 'Pause'
  else
    btnPlay.Caption := 'Play';
end;

procedure THFJVViewForm.ResetClick(Sender : TObject);
begin
  FView.ResetView;
end;

procedure THFJVViewForm.SaveClick(Sender : TObject);
var
  D : TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Save the view, midline and volume plots';
    D.InitialDir := FDir + 'mesh';
    D.FileName := 'hfjvview';
    D.Filter := 'PNG prefix|*';
    if D.Execute then
    begin
      SaveSnapshot(ChangeFileExt(D.FileName, ''));
      FStatus.SimpleText := 'Saved ' + ChangeFileExt(D.FileName, '') + '_view/_profile/_volume.png';
    end;
  finally
    D.Free;
  end;
end;

function THFJVViewForm.SaveSnapshot(const Prefix : String) : Boolean;
begin
  Result := FView.SaveToPNG(Prefix + '_view.png');
  FProfile.SaveToPNG(Prefix + '_profile.png');
  FVolume.SaveToPNG(Prefix + '_volume.png');
end;

procedure THFJVViewForm.FrameChange(Sender : TObject);
begin
  if FUpdating then
    Exit;
  ShowFrame(tbFrame.Position);
end;

procedure THFJVViewForm.ExagChange(Sender : TObject);
begin
  if FUpdating then
    Exit;
  FView.Exaggeration := seExag.Value;
  ShowFrame(FView.Frame);
end;

procedure THFJVViewForm.FpsChange(Sender : TObject);
begin
  FPlay.Interval := Max(1, 1000 div Max(seFps.Value, 1));
end;

procedure THFJVViewForm.EdgesChange(Sender : TObject);
begin
  FView.ShowEdges := cbEdges.Checked;
end;

procedure THFJVViewForm.PlayTick(Sender : TObject);
begin
  if FAnim.Frames = 0 then
    Exit;
  ShowFrame((FView.Frame + 1) mod FAnim.Frames);
end;

procedure THFJVViewForm.SetRunning(R : Boolean);
begin
  btnCompute.Enabled := not R;
  btnOpen.Enabled := not R;
  FPoll.Enabled := R;
  if not R then
    pbRun.Position := 0;
end;

procedure THFJVViewForm.ComputeClick(Sender : TObject);
var
  Exe, Tag : String;
  FS : TFormatSettings;
begin
  FS := DotFS;
  Exe := FDir + 'hfjvrun';
  {$IFDEF WINDOWS}
  Exe := Exe + '.exe';
  {$ENDIF}
  if not FileExists(Exe) then
  begin
    MessageDlg('hfjvrun was not found beside this program (' + Exe + ').'#10
      + 'Build it first: see the header of hfjvrun.lpr.', mtError, [mbOK], 0);
    Exit;
  end;
  Tag := Format('anim_r%d_dp%.2f_ie%.1f_c%d', [seRate.Value, seDP.Value, seIE.Value,
    cbCannula.ItemIndex], FS);
  if cbAbdomen.ItemIndex = 1 then
    Tag := Tag + '_box';
  ForceDirectories(FDir + 'mesh');
  FProcFile := FDir + 'mesh' + PathDelim + Tag + '.txt';
  if FileExists(FProcFile) then
  begin
    LoadAnim(FProcFile);
    lblRun.Caption := 'already computed: ' + ExtractFileName(FProcFile);
    Exit;
  end;

  FProc.Free;
  FProc := TProcess.Create(nil);
  FProc.Executable := Exe;
  FProc.CurrentDirectory := FDir;
  FProc.Parameters.Add('--anim=' + FProcFile);
  FProc.Parameters.Add('--rate=' + IntToStr(seRate.Value));
  FProc.Parameters.Add('--dp=' + FormatFloat('0.00', seDP.Value, FS));
  FProc.Parameters.Add('--ie=' + FormatFloat('0.0', seIE.Value, FS));
  FProc.Parameters.Add('--cannula=' + IntToStr(cbCannula.ItemIndex));
  if cbAbdomen.ItemIndex = 1 then
    FProc.Parameters.Add('--box');
  FProc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcOut := '';
  try
    FProc.Execute;
  except
    on E : Exception do
    begin
      MessageDlg('Could not start hfjvrun: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  lblRun.Caption := 'building the model...';
  SetRunning(True);
end;

procedure THFJVViewForm.Compute(Box : Boolean);
begin
  cbAbdomen.ItemIndex := Ord(Box);
  ComputeClick(nil);
end;

function THFJVViewForm.Computing : Boolean;
begin
  Result := FPoll.Enabled;
end;

procedure THFJVViewForm.PollTick(Sender : TObject);
var
  Buf : array[0..4095] of Char;
  n, p, q, a, b : Integer;
  Tail, Line : String;
begin
  if FProc = nil then
    Exit;
  // keep the pipe drained, or hfjvrun blocks on a full one
  while FProc.Output.NumBytesAvailable > 0 do
  begin
    n := FProc.Output.Read(Buf, Min(SizeOf(Buf), FProc.Output.NumBytesAvailable));
    if n <= 0 then Break;
    SetString(Tail, PChar(@Buf[0]), n);
    FProcOut := FProcOut + Tail;
  end;
  // progress: the last "harmonic n of N"
  p := 0;
  q := Pos('harmonic ', FProcOut);
  while q > 0 do
  begin
    p := q;
    q := PosEx('harmonic ', FProcOut, p + 1);
  end;
  if p > 0 then
  begin
    Line := Copy(FProcOut, p + 9, 20);
    q := Pos(' of ', Line);
    if q > 0 then
    begin
      a := StrToIntDef(Copy(Line, 1, q - 1), 0);
      Line := Copy(Line, q + 4, MaxInt);
      q := 1;
      while (q <= Length(Line)) and (Line[q] in ['0'..'9']) do Inc(q);
      b := StrToIntDef(Copy(Line, 1, q - 1), 0);
      if b > 0 then
      begin
        pbRun.Max := b;
        pbRun.Position := a;
        lblRun.Caption := Format('harmonic %d of %d', [a, b]);
      end;
    end;
  end;
  if not FProc.Running then
  begin
    SetRunning(False);
    if (FProc.ExitStatus = 0) and FileExists(FProcFile) then
    begin
      lblRun.Caption := 'computed: ' + ExtractFileName(FProcFile);
      LoadAnim(FProcFile);
    end
    else
    begin
      lblRun.Caption := 'hfjvrun failed';
      MessageDlg('hfjvrun failed (exit ' + IntToStr(FProc.ExitStatus) + '):'#10
        + Copy(FProcOut, Max(1, Length(FProcOut) - 1500), MaxInt), mtError, [mbOK], 0);
    end;
  end;
end;

end.
