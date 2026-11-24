unit uLVViewForm;

{ LVView's window: one steady beat of the finite-element left ventricle.

    left    the wall in motion (uLVView), cut open, coloured by sarcomere
            length or active fibre stress, with the phase of the cycle
            and the instant's figures above it and a colour bar below;
    right   the pressure-volume loop with the current point; under it
            the left ventricular, aortic root and left atrial pressures
            and the valve flows against time, ejection and filling
            shaded.

  The data is a file written by `lvrun --anim=<file>`. "Open..." reads
  one; "Compute" runs lvrun (beside this program) for the heart rate,
  number of beats and peak active stress in the second row, plus any
  further lvrun options typed in, writes the file into out/ and shows
  it. A file already computed for the same settings is loaded rather
  than computed again. Eight beats of the default mesh take about four
  minutes.

  Playback runs on the clock: at speed 1 a beat takes its real time. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs, Process,
  newVM, uVMPlot2D, uLVAnim, uLVView;

type

  TLVViewForm = class(TForm)
  private
    FAnim: TLVAnim;
    FDir: string;               // where the program and lvrun live

    pnlTop, pnlRow1, pnlRow2, pnlRight, pnlLeft: TPanel;
    FView: TLVView;
    FBar, FInfo: TPaintBox;
    FPV, FPress, FFlow: TVMPlot2D;
    FStatus: TStatusBar;

    btnOpen, btnPlay, btnReset, btnSave, btnCompute: TButton;
    tbFrame: TTrackBar;
    cbSpeed, cbColour, cbCut: TComboBox;
    cbEdges: TCheckBox;
    lblRun: TLabel;

    seHR, seBeats: TSpinEdit;
    seT0: TFloatSpinEdit;
    edExtra: TEdit;
    pbRun: TProgressBar;

    FPlay, FPoll: TTimer;
    FClock0: QWord;             // the tick at which cycle time was FTime0
    FTime0: Double;
    FProc: TProcess;
    FProcOut: string;
    FProcFile: string;
    FUpdating: Boolean;
    // the plots' fixed data
    FV, FP, FT, FPRoot, FPLA, FQAV, FQMV: TVMobj;

    function AddLabel(AParent: TWinControl; const S: string): TLabel;
    procedure Place(C: TControl; AParent: TWinControl; W: Integer);
    procedure RightResized(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ComputeClick(Sender: TObject);
    procedure FrameChange(Sender: TObject);
    procedure SpeedChange(Sender: TObject);
    procedure ColourChange(Sender: TObject);
    procedure CutChange(Sender: TObject);
    procedure EdgesChange(Sender: TObject);
    procedure PlayTick(Sender: TObject);
    procedure PollTick(Sender: TObject);
    procedure BarPaint(Sender: TObject);
    procedure InfoPaint(Sender: TObject);
    procedure ShowFrame(j: Integer);
    procedure UpdatePlots(j: Integer);
    procedure SetRunning(R: Boolean);
    function Speed: Double;
    procedure Restart(j: Integer);
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure LoadAnim(const Fn: string);
    // stops the animation at frame j
    procedure ShowFrameAt(j: Integer);
    function SaveSnapshot(const Prefix: string): Boolean;
    procedure SetLook(AColour, ACut: Integer);
    procedure Compute;
    function Computing: Boolean;
    // frames drawn a second, over n of them
    function Benchmark(n: Integer): Double;
    property Anim: TLVAnim read FAnim;
  end;

implementation

const
  Speeds: array[0..4] of Double = (1, 0.5, 0.25, 0.1, 0.05);
  // BGR
  ColLV = $002C2CD6;     // red
  ColRoot = $00B4771F;   // blue
  ColLA = $002CA02C;     // green

function DotFS: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

constructor TLVViewForm.CreateNew(AOwner: TComponent; Num: Integer);

  function Row(AAlign: TAlign; AHeight, Spacing: Integer): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := pnlTop;
    Result.Align := AAlign;
    Result.Height := AHeight;
    Result.BevelOuter := bvNone;
    Result.ChildSizing.Layout := cclLeftToRightThenTopToBottom;
    Result.ChildSizing.ControlsPerLine := 100;
    Result.ChildSizing.HorizontalSpacing := 6;
    Result.ChildSizing.LeftRightSpacing := 6;
    Result.ChildSizing.TopBottomSpacing := Spacing;
  end;

  function Combo(AParent: TWinControl; const Items: array of string; W, Index: Integer;
    Handler: TNotifyEvent): TComboBox;
  var
    i: Integer;
  begin
    Result := TComboBox.Create(Self);
    Result.Style := csDropDownList;
    for i := 0 to High(Items) do Result.Items.Add(Items[i]);
    Place(Result, AParent, W);
    Result.ItemIndex := Index;
    Result.OnChange := Handler;
  end;

begin
  inherited CreateNew(AOwner, Num);
  FDir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  Caption := 'Left ventricle - finite-element wall motion and pressure-volume loop';
  Width := 1440;
  Height := 880;
  Position := poScreenCenter;

  FStatus := TStatusBar.Create(Self);
  FStatus.Parent := Self;
  FStatus.SimplePanel := True;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 72;
  pnlTop.BevelOuter := bvNone;
  pnlRow1 := Row(alTop, 36, 5);
  pnlRow2 := Row(alClient, 36, 3);

  // row 1: the file and the animation
  btnOpen := TButton.Create(Self);
  btnOpen.Caption := 'Open...';
  btnOpen.OnClick := OpenClick;
  Place(btnOpen, pnlRow1, 80);

  btnPlay := TButton.Create(Self);
  btnPlay.Caption := 'Pause';
  btnPlay.OnClick := PlayClick;
  Place(btnPlay, pnlRow1, 70);

  tbFrame := TTrackBar.Create(Self);
  tbFrame.Min := 0;
  tbFrame.Max := 100;
  tbFrame.TickStyle := tsNone;
  tbFrame.OnChange := FrameChange;
  Place(tbFrame, pnlRow1, 300);

  AddLabel(pnlRow1, 'speed');
  cbSpeed := Combo(pnlRow1, ['real time', '1/2', '1/4', '1/10', '1/20'], 100, 2, SpeedChange);

  AddLabel(pnlRow1, 'colour');
  cbColour := Combo(pnlRow1, ['sarcomere length', 'active fibre stress', 'plain'], 160, 0, ColourChange);

  AddLabel(pnlRow1, 'cut away');
  cbCut := Combo(pnlRow1, ['nothing', 'a quarter', 'a half'], 110, 2, CutChange);

  cbEdges := TCheckBox.Create(Self);
  cbEdges.Caption := 'mesh';
  cbEdges.Checked := True;
  cbEdges.OnChange := EdgesChange;
  Place(cbEdges, pnlRow1, 65);

  btnReset := TButton.Create(Self);
  btnReset.Caption := 'Reset view';
  btnReset.OnClick := ResetClick;
  Place(btnReset, pnlRow1, 90);

  btnSave := TButton.Create(Self);
  btnSave.Caption := 'Save PNG...';
  btnSave.OnClick := SaveClick;
  Place(btnSave, pnlRow1, 95);

  // row 2: computing a new beat with lvrun
  AddLabel(pnlRow2, 'heart rate /min');
  seHR := TSpinEdit.Create(Self);
  seHR.MinValue := 40;
  seHR.MaxValue := 180;
  seHR.Increment := 5;
  seHR.Value := 70;
  Place(seHR, pnlRow2, 60);

  AddLabel(pnlRow2, 'beats to run');
  seBeats := TSpinEdit.Create(Self);
  seBeats.MinValue := 1;
  seBeats.MaxValue := 30;
  seBeats.Value := 8;
  Place(seBeats, pnlRow2, 55);

  AddLabel(pnlRow2, 'peak active stress T0, kPa');
  seT0 := TFloatSpinEdit.Create(Self);
  seT0.MinValue := 20;
  seT0.MaxValue := 400;
  seT0.Increment := 5;
  seT0.DecimalPlaces := 0;
  seT0.Value := 145;
  Place(seT0, pnlRow2, 65);

  AddLabel(pnlRow2, 'other lvrun options');
  edExtra := TEdit.Create(Self);
  edExtra.Hint := 'e.g. --cross=0  --sync  --mesh=4,16,24  --ppv=12  (see lvrun.lpr)';
  edExtra.ShowHint := True;
  Place(edExtra, pnlRow2, 220);

  btnCompute := TButton.Create(Self);
  btnCompute.Caption := 'Compute';
  btnCompute.OnClick := ComputeClick;
  Place(btnCompute, pnlRow2, 90);

  pbRun := TProgressBar.Create(Self);
  pbRun.Min := 0;
  pbRun.Max := 8;
  Place(pbRun, pnlRow2, 140);

  lblRun := AddLabel(pnlRow2, '');

  // right: the loop, the pressures and the flows
  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 640;
  pnlRight.BevelOuter := bvNone;
  pnlRight.OnResize := RightResized;

  FPV := TVMPlot2D.Create(Self);
  FPV.Parent := pnlRight;
  FPV.Title := 'Pressure-volume loop';
  FPV.XAxisTitle := 'left ventricular volume, mL';
  FPV.YAxisTitle := 'left ventricular pressure, mmHg';

  FPress := TVMPlot2D.Create(Self);
  FPress.Parent := pnlRight;
  FPress.Title := 'Pressures';
  FPress.XAxisTitle := '';
  FPress.YAxisTitle := 'mmHg';

  FFlow := TVMPlot2D.Create(Self);
  FFlow.Parent := pnlRight;
  FFlow.Title := 'Valve flows';
  FFlow.XAxisTitle := 'time from the start of depolarisation, ms';
  FFlow.YAxisTitle := 'mL/s';

  // left: the instant, the wall and the colour bar
  pnlLeft := TPanel.Create(Self);
  pnlLeft.Parent := Self;
  pnlLeft.Align := alClient;
  pnlLeft.BevelOuter := bvNone;

  FInfo := TPaintBox.Create(Self);
  FInfo.Parent := pnlLeft;
  FInfo.Align := alTop;
  FInfo.Height := 58;
  FInfo.OnPaint := InfoPaint;

  FBar := TPaintBox.Create(Self);
  FBar.Parent := pnlLeft;
  FBar.Align := alBottom;
  FBar.Height := 54;
  FBar.OnPaint := BarPaint;

  FView := TLVView.Create(Self);
  FView.Parent := pnlLeft;
  FView.Align := alClient;

  FPlay := TTimer.Create(Self);
  FPlay.Interval := 30;
  FPlay.OnTimer := PlayTick;
  FPlay.Enabled := False;

  FPoll := TTimer.Create(Self);
  FPoll.Interval := 150;
  FPoll.OnTimer := PollTick;
  FPoll.Enabled := False;

  FAnim := TLVAnim.Create;
  RightResized(nil);
end;

destructor TLVViewForm.Destroy;
begin
  FPlay.Enabled := False;
  FPoll.Enabled := False;
  if FProc <> nil then
  begin
    if FProc.Running then FProc.Terminate(1);
    FProc.Free;
  end;
  FAnim.Free;
  inherited Destroy;
end;

function TLVViewForm.AddLabel(AParent: TWinControl; const S: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := S;
  Result.Layout := tlCenter;
  Result.Parent := AParent;
end;

procedure TLVViewForm.Place(C: TControl; AParent: TWinControl; W: Integer);
begin
  C.Width := W;
  C.Constraints.MinWidth := W;
  C.Parent := AParent;
end;

// three plots stacked: placed by hand, since alTop controls created in
// code stack in an arbitrary order
procedure TLVViewForm.RightResized(Sender: TObject);
var
  H, W, h1, h2: Integer;
begin
  if FFlow = nil then Exit;
  H := pnlRight.ClientHeight;
  W := pnlRight.ClientWidth;
  h1 := H * 46 div 100;
  h2 := H * 27 div 100;
  FPV.SetBounds(0, 0, W, h1);
  FPress.SetBounds(0, h1, W, h2);
  FFlow.SetBounds(0, h1 + h2, W, H - h1 - h2);
end;

function TLVViewForm.Speed: Double;
begin
  Result := Speeds[EnsureRange(cbSpeed.ItemIndex, 0, High(Speeds))];
end;

// playback continues from frame j
procedure TLVViewForm.Restart(j: Integer);
begin
  if FAnim.Frames = 0 then Exit;
  FTime0 := FAnim.TimeAt(j);
  FClock0 := GetTickCount64;
end;

procedure TLVViewForm.LoadAnim(const Fn: string);
var
  A: TLVAnim;
  i, i0, n: Integer;
  FS: TFormatSettings;

  procedure Bands(P: TVMPlot2D; Captions: Boolean);
  var
    k, k0: Integer;
  begin
    P.ClearXBands;
    k0 := 0;
    for k := 1 to n do
      if (k = n) or (FAnim.S[k].Phase <> FAnim.S[k0].Phase) then
      begin
        case FAnim.S[k0].Phase of
          phEjection:
            P.AddXBand(1000 * FAnim.S[k0].T, 1000 * FAnim.S[k - 1].T, $009E9EFF,
              IfThen(Captions, 'ejection', ''));
          phFilling:
            P.AddXBand(1000 * FAnim.S[k0].T, 1000 * FAnim.S[k - 1].T, $00F0C8A0,
              IfThen(Captions, 'filling', ''));
        end;
        k0 := k;
      end;
  end;

begin
  A := TLVAnim.Create;
  try
    A.LoadFromFile(Fn);
  except
    A.Free;
    raise;
  end;
  FAnim.Free;
  FAnim := A;
  FView.SetAnim(FAnim);
  FS := DotFS;

  n := Length(FAnim.S);
  FV := TVMobj.Create(1, n); FP := TVMobj.Create(1, n); FT := TVMobj.Create(1, n);
  FPRoot := TVMobj.Create(1, n); FPLA := TVMobj.Create(1, n);
  FQAV := TVMobj.Create(1, n); FQMV := TVMobj.Create(1, n);
  for i := 0 to n - 1 do
  begin
    FV[0, i] := FAnim.S[i].VLV; FP[0, i] := FAnim.S[i].PLV;
    FT[0, i] := 1000 * FAnim.S[i].T;
    FPRoot[0, i] := FAnim.S[i].PRoot; FPLA[0, i] := FAnim.S[i].PLA;
    FQAV[0, i] := FAnim.S[i].QAV; FQMV[0, i] := FAnim.S[i].QMV;
  end;
  // the series are named by colour in the titles: a legend would cover
  // the curves in plots this low
  FPV.Title := Format('P-V loop:  EDV %.0f, ESV %.0f mL, EF %.0f %%',
    [FAnim.EDV, FAnim.ESV, 100 * (1 - FAnim.ESV / FAnim.EDV)], FS);
  FPress.Title := Format('LV (red) %.0f/%.0f, aortic root (blue) %.0f/%.0f, LA (green)',
    [FAnim.PeakP, FAnim.EDP, FAnim.AoSys, FAnim.AoDia], FS);
  FFlow.Title := Format('Aortic valve (blue) peak %.0f mL/s, mitral valve (green)', [FAnim.PeakFlow], FS);
  Bands(FPress, True);
  Bands(FFlow, False);

  FUpdating := True;
  try
    tbFrame.Max := FAnim.Frames - 1;
    tbFrame.Position := 0;
    seHR.Value := Round(60 / FAnim.Period);
  finally
    FUpdating := False;
  end;
  FBar.Invalidate;
  i0 := 0;
  ShowFrame(i0);
  Restart(i0);
  FPlay.Enabled := True;
  btnPlay.Caption := 'Pause';
end;

procedure TLVViewForm.ShowFrameAt(j: Integer);
begin
  FPlay.Enabled := False;
  btnPlay.Caption := 'Play';
  if FAnim.Frames > 0 then
    ShowFrame(EnsureRange(j, 0, FAnim.Frames - 1));
end;

function TLVViewForm.Benchmark(n: Integer): Double;
var
  i: Integer;
  t0: QWord;
begin
  FPlay.Enabled := False;
  t0 := GetTickCount64;
  for i := 1 to n do
  begin
    ShowFrame(i mod FAnim.Frames);
    Application.ProcessMessages;
  end;
  Result := 1000 * n / Max(GetTickCount64 - t0, 1);
end;

procedure TLVViewForm.SetLook(AColour, ACut: Integer);
begin
  cbColour.ItemIndex := EnsureRange(AColour, 0, 2);
  cbCut.ItemIndex := EnsureRange(ACut, 0, 2);
  ColourChange(nil);
  CutChange(nil);
end;

// TVMPlot2D's SetData replaces every series, so the fixed curves are
// set again each frame, then the current point added
procedure TLVViewForm.UpdatePlots(j: Integer);
var
  Sm: TLVSample;
begin
  Sm := FAnim.SampleAt(j);

  FPV.ClearSeries;
  FPV.SetSeriesStyle(0, ColLV, 2.5, plsSolid, '');
  FPV.SetSeriesStyle(1, ColLV, 0, plsNone, '', pmsCircle, 13);
  FPV.SetData(FV, [FP]);
  FPV.PlotXY(Sm.VLV, Sm.PLV, 1);

  FPress.ClearSeries;
  FPress.SetSeriesStyle(0, ColLV, 2, plsSolid, '');
  FPress.SetSeriesStyle(1, ColRoot, 2, plsSolid, '');
  FPress.SetSeriesStyle(2, ColLA, 2, plsSolid, '');
  FPress.SetSeriesStyle(3, ColLV, 0, plsNone, '', pmsCircle, 10);
  FPress.SetSeriesStyle(4, ColRoot, 0, plsNone, '', pmsCircle, 10);
  FPress.SetSeriesStyle(5, ColLA, 0, plsNone, '', pmsCircle, 10);
  FPress.SetData(FT, [FP, FPRoot, FPLA]);
  FPress.PlotXY(1000 * Sm.T, Sm.PLV, 3);
  FPress.PlotXY(1000 * Sm.T, Sm.PRoot, 4);
  FPress.PlotXY(1000 * Sm.T, Sm.PLA, 5);

  FFlow.ClearSeries;
  FFlow.SetSeriesStyle(0, ColRoot, 2, plsSolid, '');
  FFlow.SetSeriesStyle(1, ColLA, 2, plsSolid, '');
  FFlow.SetSeriesStyle(2, ColRoot, 0, plsNone, '', pmsCircle, 10);
  FFlow.SetSeriesStyle(3, ColLA, 0, plsNone, '', pmsCircle, 10);
  FFlow.SetData(FT, [FQAV, FQMV]);
  FFlow.PlotXY(1000 * Sm.T, Sm.QAV, 2);
  FFlow.PlotXY(1000 * Sm.T, Sm.QMV, 3);
end;

procedure TLVViewForm.ShowFrame(j: Integer);
var
  FS: TFormatSettings;
begin
  if FAnim.Frames = 0 then Exit;
  FS := DotFS;
  FView.Frame := j;
  if tbFrame.Position <> j then
  begin
    FUpdating := True;
    tbFrame.Position := j;
    FUpdating := False;
  end;
  UpdatePlots(j);
  FInfo.Invalidate;
  FStatus.SimpleText := Format('%s   |   %.0f /min   |   %d x %d x %d elements (wall, apex-base, round), %d nodes   |   '
    + '%d frames, %d time steps   |   sarcomere %.2f - %.2f um, active stress to %.0f kPa',
    [ExtractFileName(FAnim.FileName), 60 / FAnim.Period, FAnim.NR, FAnim.NL, FAnim.NC, FAnim.NN,
     FAnim.Frames, Length(FAnim.S) - 1, FAnim.Ls0 * FAnim.LamMin, FAnim.Ls0 * FAnim.LamMax,
     FAnim.TactMax], FS);
end;

procedure TLVViewForm.InfoPaint(Sender: TObject);
var
  C: TCanvas;
  Sm: TLVSample;
  FS: TFormatSettings;
  S: string;
begin
  C := FInfo.Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, FInfo.Width, FInfo.Height);
  if FAnim.Frames = 0 then
  begin
    C.Font.Size := 11;
    C.Font.Style := [];
    C.Font.Color := clGray;
    C.TextOut(12, 18, 'No beat loaded: Open an lvrun --anim file, or Compute one.');
    Exit;
  end;
  FS := DotFS;
  Sm := FAnim.SampleAt(FView.Frame);
  C.Font.Color := clBlack;
  C.Font.Size := 14;
  C.Font.Style := [fsBold];
  S := Format('%3.0f ms', [1000 * Sm.T], FS);
  C.TextOut(12, 4, S);
  case Sm.Phase of
    phEjection: C.Font.Color := $002020C0;
    phFilling: C.Font.Color := $00A06010;
  else
    C.Font.Color := $00505050;
  end;
  C.TextOut(110, 4, PhaseNames[Sm.Phase]);
  C.Font.Color := clBlack;
  C.Font.Size := 12;
  S := Format('LV %.0f mmHg, %.0f mL', [Sm.PLV, Sm.VLV], FS);
  C.TextOut(Max(400, FInfo.Width - C.TextWidth(S) - 16), 7, S);
  C.Font.Size := 10;
  C.Font.Style := [];
  S := Format('aortic root %.0f mmHg     left atrium %.1f mmHg     ', [Sm.PRoot, Sm.PLA], FS);
  if Sm.ZAV > 0.02 then
    S := S + Format('aortic valve open, %.0f mL/s     ', [Sm.QAV], FS)
  else
    S := S + 'aortic valve shut     ';
  if Sm.ZMV > 0.02 then
    S := S + Format('mitral valve open, %.0f mL/s', [Sm.QMV], FS)
  else
    S := S + 'mitral valve shut';
  C.TextOut(12, 34, S);
end;

procedure TLVViewForm.BarPaint(Sender: TObject);
var
  C: TCanvas;
  x0, x1, y0, y1, x, i: Integer;
  r, g, b: Single;
  lo, hi: Double;
  S: string;
  FS: TFormatSettings;
begin
  C := FBar.Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, FBar.Width, FBar.Height);
  if (FAnim.Frames = 0) or (FView.ColourMode = cmPlain) then Exit;
  FS := DotFS;
  if FView.ColourMode = cmSarcomere then
  begin
    lo := FAnim.Ls0 * FAnim.LamMin; hi := FAnim.Ls0 * FAnim.LamMax;
  end
  else
  begin
    lo := 0; hi := FAnim.TactMax;
  end;
  x0 := FBar.Width div 6;
  x1 := FBar.Width - x0;
  y0 := 6;
  y1 := 22;
  for x := x0 to x1 do
  begin
    MapColour(FView.ColourMode, (x - x0) / Max(x1 - x0, 1), r, g, b);
    C.Pen.Color := RGBToColor(Round(255 * r), Round(255 * g), Round(255 * b));
    C.Line(x, y0, x, y1);
  end;
  C.Pen.Color := clGray;
  C.Brush.Style := bsClear;
  C.Rectangle(x0, y0, x1 + 1, y1);
  C.Font.Color := clBlack;
  C.Font.Size := 8;
  C.Font.Style := [];
  for i := 0 to 4 do
  begin
    x := x0 + Round(i / 4 * (x1 - x0));
    C.Line(x, y1, x, y1 + 3);
    if FView.ColourMode = cmSarcomere then
      S := FormatFloat('0.00', lo + (hi - lo) * i / 4, FS)
    else
      S := FormatFloat('0', lo + (hi - lo) * i / 4, FS);
    C.TextOut(x - C.TextWidth(S) div 2, y1 + 4, S);
  end;
  if FView.ColourMode = cmSarcomere then
    S := 'sarcomere length, um  (element means; blue short, red long)'
  else
    S := 'active fibre stress, kPa  (element means)';
  C.TextOut((x0 + x1 - C.TextWidth(S)) div 2, y1 + 17, S);
end;

procedure TLVViewForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Open an lvrun --anim file';
    D.InitialDir := FDir + 'out';
    D.Filter := 'Animation files (*.txt)|*.txt|All files|*';
    if D.Execute then LoadAnim(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TLVViewForm.PlayClick(Sender: TObject);
begin
  FPlay.Enabled := not FPlay.Enabled;
  if FPlay.Enabled then
  begin
    Restart(FView.Frame);
    btnPlay.Caption := 'Pause';
  end
  else
    btnPlay.Caption := 'Play';
end;

procedure TLVViewForm.ResetClick(Sender: TObject);
begin
  FView.ResetView;
end;

procedure TLVViewForm.SaveClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Save the view and the plots';
    D.InitialDir := FDir + 'out';
    D.FileName := 'lvview';
    D.Filter := 'PNG prefix|*';
    if D.Execute then
    begin
      SaveSnapshot(ChangeFileExt(D.FileName, ''));
      lblRun.Caption := 'saved ' + ExtractFileName(ChangeFileExt(D.FileName, '')) + '_view/_pv/_pressure/_flow.png';
    end;
  finally
    D.Free;
  end;
end;

function TLVViewForm.SaveSnapshot(const Prefix: string): Boolean;
begin
  Result := FView.SaveToPNG(Prefix + '_view.png');
  FPV.SaveToPNG(Prefix + '_pv.png');
  FPress.SaveToPNG(Prefix + '_pressure.png');
  FFlow.SaveToPNG(Prefix + '_flow.png');
end;

procedure TLVViewForm.FrameChange(Sender: TObject);
begin
  if FUpdating then Exit;
  ShowFrame(tbFrame.Position);
  Restart(tbFrame.Position);
end;

procedure TLVViewForm.SpeedChange(Sender: TObject);
begin
  Restart(FView.Frame);
end;

procedure TLVViewForm.ColourChange(Sender: TObject);
begin
  FView.ColourMode := TLVColourMode(cbColour.ItemIndex);
  FBar.Invalidate;
end;

procedure TLVViewForm.CutChange(Sender: TObject);
begin
  FView.Cut := TLVCut(cbCut.ItemIndex);
end;

procedure TLVViewForm.EdgesChange(Sender: TObject);
begin
  FView.ShowEdges := cbEdges.Checked;
end;

procedure TLVViewForm.PlayTick(Sender: TObject);
var
  t: Double;
  j: Integer;
begin
  if FAnim.Frames = 0 then Exit;
  t := FTime0 + (GetTickCount64 - FClock0) / 1000 * Speed;
  t := t - FAnim.Period * Floor(t / FAnim.Period);
  j := FAnim.FrameAtTime(t);
  if j <> FView.Frame then ShowFrame(j);
end;

procedure TLVViewForm.SetRunning(R: Boolean);
begin
  btnCompute.Enabled := not R;
  btnOpen.Enabled := not R;
  FPoll.Enabled := R;
  if not R then pbRun.Position := 0;
end;

procedure TLVViewForm.ComputeClick(Sender: TObject);
var
  Exe, FileTag, Extra: string;
  FS: TFormatSettings;
  Parts: TStringArray;
  i: Integer;
begin
  FS := DotFS;
  Exe := FDir + 'lvrun';
  {$IFDEF WINDOWS}
  Exe := Exe + '.exe';
  {$ENDIF}
  if not FileExists(Exe) then
  begin
    MessageDlg('lvrun was not found beside this program (' + Exe + ').'#10
      + 'Build it first: see the header of lvrun.lpr.', mtError, [mbOK], 0);
    Exit;
  end;
  Extra := Trim(edExtra.Text);
  FileTag := Format('anim_hr%d_t0%.0f_b%d', [seHR.Value, seT0.Value, seBeats.Value], FS);
  for i := 1 to Length(Extra) do
    if Extra[i] in ['0'..'9', 'a'..'z', 'A'..'Z', '.', ','] then
      FileTag := FileTag + Extra[i]
    else if (Extra[i] = ' ') or (Extra[i] = '=') then
      FileTag := FileTag + '_';
  ForceDirectories(FDir + 'out');
  FProcFile := FDir + 'out' + PathDelim + FileTag + '.txt';
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
  FProc.Parameters.Add('--hr=' + IntToStr(seHR.Value));
  FProc.Parameters.Add('--beats=' + IntToStr(seBeats.Value));
  FProc.Parameters.Add('--t0=' + FormatFloat('0', seT0.Value, FS));
  Parts := Extra.Split([' '], TStringSplitOptions.ExcludeEmpty);
  for i := 0 to High(Parts) do FProc.Parameters.Add(Parts[i]);
  FProc.Options := [poUsePipes, poStderrToOutPut, poNoConsole];
  FProcOut := '';
  try
    FProc.Execute;
  except
    on E: Exception do
    begin
      MessageDlg('Could not start lvrun: ' + E.Message, mtError, [mbOK], 0);
      Exit;
    end;
  end;
  pbRun.Max := seBeats.Value;
  lblRun.Caption := 'filling the ventricle...';
  SetRunning(True);
end;

procedure TLVViewForm.Compute;
begin
  ComputeClick(nil);
end;

function TLVViewForm.Computing: Boolean;
begin
  Result := FPoll.Enabled;
end;

procedure TLVViewForm.PollTick(Sender: TObject);
var
  Buf: array[0..4095] of Char;
  n, p, q, beats: Integer;
  Tail: string;
begin
  if FProc = nil then Exit;
  // keep the pipe drained, or lvrun blocks on a full one
  while FProc.Output.NumBytesAvailable > 0 do
  begin
    n := FProc.Output.Read(Buf, Min(SizeOf(Buf), FProc.Output.NumBytesAvailable));
    if n <= 0 then Break;
    SetString(Tail, PChar(@Buf[0]), n);
    FProcOut := FProcOut + Tail;
  end;
  // progress: one line per beat after the table's heading
  p := Pos(' beat ', FProcOut);
  if p > 0 then
  begin
    beats := -1;
    q := PosEx(#10, FProcOut, p);
    while q > 0 do
    begin
      Inc(beats);
      q := PosEx(#10, FProcOut, q + 1);
    end;
    beats := EnsureRange(beats, 0, pbRun.Max);
    pbRun.Position := beats;
    if beats < pbRun.Max then
      lblRun.Caption := Format('beat %d of %d', [beats + 1, pbRun.Max]);
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
      lblRun.Caption := 'lvrun failed';
      MessageDlg('lvrun failed (exit ' + IntToStr(FProc.ExitStatus) + '):'#10
        + Copy(FProcOut, Max(1, Length(FProcOut) - 1500), MaxInt), mtError, [mbOK], 0);
    end;
  end;
end;

end.
