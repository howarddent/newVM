unit uAortaViewForm;

{ AortaView's window: the pulse wave travelling from the aortic valve to
  the wrist and the groin.

    left    the arterial tree (uAortaView), coloured by pressure, the
            vessels' pulsation exaggerated; the instant's figures above
            and the colour scale below;
    right   pressure against time at the aortic root, the elbow, the
            wrist and the groin (the rings on the tree, in the same
            colours) with the current instant marked; pressure against
            distance from the valve at this instant, along the way to
            the wrist and to the groin - the wave itself; and the flows.

  The model is computed here (uAortaTree; a few seconds): "Compute" runs
  it for the aortic elastance, the other vessels' elastance, the
  compliance of the resistive beds (0: pure resistances) and the number
  of beats in the second row. The inflow is the left ventricle model's
  aortic valve flow, read from a file written by `lvrun --csv`.

  Playback runs on the clock, slowed by the chosen factor. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, Dialogs,
  newVM, uVMPlot2D, uArtery1D, uAortaTree, uAortaView;

type

  TAortaViewForm = class(TForm)
  private
    FSim: TAortaSim;
    FDir: string;
    pnlTop, pnlRow1, pnlRow2, pnlRight, pnlLeft: TPanel;
    FView: TAortaView;
    FBar, FInfo: TPaintBox;
    FTimePlot, FWavePlot, FFlowPlot: TVMPlot2D;
    FStatus: TStatusBar;
    btnPlay, btnReset, btnSave, btnCompute, btnOpen: TButton;
    tbFrame: TTrackBar;
    cbSpeed: TComboBox;
    cbLabels: TCheckBox;
    seExag, seStiff, seOther, seCPer, seTau: TFloatSpinEdit;
    seBeats: TSpinEdit;
    FPlay: TTimer;
    FClock0: QWord;
    FTime0: Double;
    FUpdating: Boolean;
    FComputeMs: Integer;
    // the plots' fixed data
    FT: TVMobj;
    FPSite: array[0..3] of TVMobj;
    FQ: array[0..3] of TVMobj;
    FX: array[0..1] of TVMobj;
    FSite: array[0..3] of Integer;
    FQSite: array[0..3] of Integer;
    function AddLabel(AParent: TWinControl; const S: string): TLabel;
    procedure Place(C: TControl; AParent: TWinControl; W: Integer);
    function FloatSpin(AParent: TWinControl; Lo, Hi, Step, V: Double; Dec, W: Integer): TFloatSpinEdit;
    procedure RightResized(Sender: TObject);
    procedure PlayClick(Sender: TObject);
    procedure ResetClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ComputeClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure FrameChange(Sender: TObject);
    procedure SpeedChange(Sender: TObject);
    procedure LookChange(Sender: TObject);
    procedure PlayTick(Sender: TObject);
    procedure BarPaint(Sender: TObject);
    procedure InfoPaint(Sender: TObject);
    procedure ShowFrame(j: Integer);
    procedure UpdatePlots(j: Integer);
    function Speed: Double;
    procedure Restart(j: Integer);
    function FrameTime(j: Integer): Double;
  public
    LVFile: string;
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    procedure SetModel(AStiff, AOther, ACPer: Double; ABeats: Integer; AWallTau: Double = 5);
    procedure Compute;
    procedure ShowFrameAt(j: Integer);
    function FrameAtTime(t: Double): Integer;
    function SaveSnapshot(const Prefix: string): Boolean;
    function Benchmark(n: Integer): Double;
  end;

implementation

const
  Speeds: array[0..5] of Double = (1, 0.5, 0.25, 0.1, 0.05, 0.02);
  // BGR: root red, elbow blue, wrist purple, groin green
  SiteCol: array[0..3] of TColor = ($002C2CD6, $00B4771F, $00BD6794, $002CA02C);
  SiteName: array[0..3] of string = ('aortic root', 'left brachial (elbow)',
    'left radial (wrist)', 'left common femoral');
  SiteShort: array[0..3] of string = ('root', 'elbow', 'wrist', 'groin');
  QName: array[0..3] of string = ('aortic root', 'thoracic aorta', 'left subclavian',
    'left radial (wrist)');
  QLegend: array[0..3] of string = ('aortic root', 'thoracic aorta', 'subclavian x 10', 'radial x 100');
  QScale: array[0..3] of Double = (1, 1, 10, 100);
  QCol: array[0..3] of TColor = ($002C2CD6, $000E7FFF, $00B4771F, $00BD6794);

constructor TAortaViewForm.CreateNew(AOwner: TComponent; Num: Integer);

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

  function Button(AParent: TWinControl; const S: string; W: Integer; Handler: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Caption := S;
    Result.OnClick := Handler;
    Place(Result, AParent, W);
  end;

  function Plot(const ATitle, AX, AY: string): TVMPlot2D;
  begin
    Result := TVMPlot2D.Create(Self);
    Result.Parent := pnlRight;
    Result.Title := ATitle;
    Result.XAxisTitle := AX;
    Result.YAxisTitle := AY;
  end;

var
  i: Integer;
begin
  inherited CreateNew(AOwner, Num);
  FDir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  LVFile := ExpandFileName(FDir + '..' + PathDelim + 'LeftVentricle' + PathDelim + 'out' + PathDelim + 'beat.csv');
  Caption := 'Aorta - the arterial pulse wave from the left ventricle to the wrist';
  Width := 1440;
  Height := 900;
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

  btnPlay := Button(pnlRow1, 'Pause', 70, PlayClick);
  tbFrame := TTrackBar.Create(Self);
  tbFrame.Min := 0;
  tbFrame.Max := 100;
  tbFrame.TickStyle := tsNone;
  tbFrame.OnChange := FrameChange;
  Place(tbFrame, pnlRow1, 320);
  AddLabel(pnlRow1, 'speed');
  cbSpeed := TComboBox.Create(Self);
  cbSpeed.Style := csDropDownList;
  cbSpeed.Items.CommaText := '"real time",1/2,1/4,1/10,1/20,1/50';
  Place(cbSpeed, pnlRow1, 100);
  cbSpeed.ItemIndex := 3;
  cbSpeed.OnChange := SpeedChange;
  AddLabel(pnlRow1, 'pulsation x');
  seExag := FloatSpin(pnlRow1, 1, 20, 1, 5, 0, 55);
  seExag.OnChange := LookChange;
  cbLabels := TCheckBox.Create(Self);
  cbLabels.Caption := 'names';
  cbLabels.Checked := True;
  cbLabels.OnChange := LookChange;
  Place(cbLabels, pnlRow1, 70);
  btnReset := Button(pnlRow1, 'Reset view', 90, ResetClick);
  btnSave := Button(pnlRow1, 'Save PNG...', 95, SaveClick);

  AddLabel(pnlRow2, 'aortic elastance x');
  seStiff := FloatSpin(pnlRow2, 0.25, 8, 0.25, 1, 2, 65);
  AddLabel(pnlRow2, 'iliacs and arm x');
  seOther := FloatSpin(pnlRow2, 0.25, 8, 0.25, 1, 2, 65);
  AddLabel(pnlRow2, 'bed compliance, mL/mmHg');
  seCPer := FloatSpin(pnlRow2, 0, 3, 0.1, 0.8, 2, 65);
  seCPer.Hint := 'Above 0 each bed is a Windkessel matched to its artery (allow about 25 beats). 0: pure resistances';
  seCPer.ShowHint := True;
  AddLabel(pnlRow2, 'wall viscosity, ms');
  seTau := FloatSpin(pnlRow2, 0, 30, 1, 5, 1, 60);
  seTau.Hint := 'Kelvin-Voigt wall: its retardation time, wall viscosity over Young''s modulus. 0: elastic wall';
  seTau.ShowHint := True;
  AddLabel(pnlRow2, 'beats');
  seBeats := TSpinEdit.Create(Self);
  seBeats.MinValue := 2;
  seBeats.MaxValue := 80;
  seBeats.Value := 25;
  Place(seBeats, pnlRow2, 55);
  btnCompute := Button(pnlRow2, 'Compute', 90, ComputeClick);
  btnOpen := Button(pnlRow2, 'Ventricle file...', 120, OpenClick);

  pnlRight := TPanel.Create(Self);
  pnlRight.Parent := Self;
  pnlRight.Align := alRight;
  pnlRight.Width := 700;
  pnlRight.BevelOuter := bvNone;
  pnlRight.OnResize := RightResized;
  FTimePlot := Plot('Pressure: root red, elbow blue, wrist purple, groin green', 'time in the cycle, ms', 'mmHg');
  FWavePlot := Plot('Pressure along the way to the wrist (purple) and the groin (green), now',
    'distance from the aortic valve, cm', 'mmHg');
  FFlowPlot := Plot('Flow',
    'time in the cycle, ms', 'mL/s');

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
  FBar.Height := 50;
  FBar.OnPaint := BarPaint;
  FView := TAortaView.Create(Self);
  FView.Parent := pnlLeft;
  FView.Align := alClient;

  FPlay := TTimer.Create(Self);
  FPlay.Interval := 25;
  FPlay.OnTimer := PlayTick;
  FPlay.Enabled := False;

  FSim := TAortaSim.Create;
  for i := 0 to 3 do FSite[i] := -1;
  RightResized(nil);
end;

destructor TAortaViewForm.Destroy;
begin
  FPlay.Enabled := False;
  FSim.Free;
  inherited Destroy;
end;

function TAortaViewForm.AddLabel(AParent: TWinControl; const S: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Caption := S;
  Result.Layout := tlCenter;
  Result.Parent := AParent;
end;

procedure TAortaViewForm.Place(C: TControl; AParent: TWinControl; W: Integer);
begin
  C.Width := W;
  C.Constraints.MinWidth := W;
  C.Parent := AParent;
end;

function TAortaViewForm.FloatSpin(AParent: TWinControl; Lo, Hi, Step, V: Double; Dec, W: Integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.MinValue := Lo;
  Result.MaxValue := Hi;
  Result.Increment := Step;
  Result.DecimalPlaces := Dec;
  Result.Value := V;
  Place(Result, AParent, W);
end;

procedure TAortaViewForm.RightResized(Sender: TObject);
var
  H, W, h1, h2: Integer;
begin
  if FFlowPlot = nil then Exit;
  H := pnlRight.ClientHeight;
  W := pnlRight.ClientWidth;
  h1 := H * 36 div 100;
  h2 := H * 36 div 100;
  FTimePlot.SetBounds(0, 0, W, h1);
  FWavePlot.SetBounds(0, h1, W, h2);
  FFlowPlot.SetBounds(0, h1 + h2, W, H - h1 - h2);
end;

function TAortaViewForm.Speed: Double;
begin
  Result := Speeds[EnsureRange(cbSpeed.ItemIndex, 0, High(Speeds))];
end;

function TAortaViewForm.FrameTime(j: Integer): Double;
begin
  Result := j * FSim.LV.Period / FSim.NFrames;
end;

function TAortaViewForm.FrameAtTime(t: Double): Integer;
begin
  if FSim.NFrames = 0 then Exit(0);
  Result := EnsureRange(Floor(t / FSim.LV.Period * FSim.NFrames), 0, FSim.NFrames - 1);
end;

procedure TAortaViewForm.SetModel(AStiff, AOther, ACPer: Double; ABeats: Integer; AWallTau: Double);
begin
  seStiff.Value := AStiff;
  seOther.Value := AOther;
  seCPer.Value := ACPer;
  seTau.Value := AWallTau;
  seBeats.Value := ABeats;
end;

procedure TAortaViewForm.Compute;
var
  i, k, n: Integer;
  tick: QWord;
begin
  if not FileExists(LVFile) then
  begin
    FStatus.SimpleText := LVFile + ' is not there: run lvrun --csv in LeftVentricle, or choose a file';
    Exit;
  end;
  FPlay.Enabled := False;
  Screen.Cursor := crHourGlass;
  FStatus.SimpleText := 'Computing...';
  Application.ProcessMessages;
  try
    FSim.LV.Load(LVFile);
    FSim.AorticStiff := seStiff.Value;
    FSim.OtherStiff := seOther.Value;
    FSim.CPeriph := seCPer.Value;
    FSim.WallTau := seTau.Value;
    FSim.Beats := seBeats.Value;
    tick := GetTickCount64;
    try
      FSim.Run;
    except
      on E: Exception do
      begin
        FStatus.SimpleText := 'The run failed: ' + E.Message;
        FSim.NFrames := 0;
        FView.SetSim(nil);
        Exit;
      end;
    end;
    FComputeMs := GetTickCount64 - tick;
  finally
    Screen.Cursor := crDefault;
  end;

  n := Length(FSim.TOut);
  FT := TVMobj.Create(1, n);
  for k := 0 to n - 1 do FT[0, k] := 1000 * FSim.TOut[k];
  for i := 0 to 3 do
  begin
    FSite[i] := FSim.ProbeIndex(SiteName[i]);
    FQSite[i] := FSim.ProbeIndex(QName[i]);
    FPSite[i] := TVMobj.Create(1, n);
    FQ[i] := TVMobj.Create(1, n);
    for k := 0 to n - 1 do
    begin
      FPSite[i][0, k] := FSim.Probes[FSite[i]].P[k];
      FQ[i][0, k] := QScale[i] * FSim.Probes[FQSite[i]].Q[k];
    end;
  end;
  for i := 0 to 1 do
  begin
    FX[i] := TVMobj.Create(1, Length(FSim.Paths[i].Nodes));
    for k := 0 to High(FSim.Paths[i].Nodes) do FX[i][0, k] := FSim.Paths[i].Nodes[k].Dist;
  end;
  SetLength(FView.Sites, 4);
  for i := 0 to 3 do
  begin
    FView.Sites[i].Probe := FSite[i];
    FView.Sites[i].Colour := SiteCol[i];
  end;
  FView.SetSim(FSim);
  FUpdating := True;
  tbFrame.Max := FSim.NFrames - 1;
  tbFrame.Position := 0;
  FUpdating := False;
  FBar.Invalidate;
  ShowFrame(0);
  Restart(0);
  FPlay.Enabled := btnPlay.Caption = 'Pause';
end;

procedure TAortaViewForm.UpdatePlots(j: Integer);
var
  k, n, i: Integer;
  t: Double;
  W: TVMobj;
begin
  t := 1000 * FrameTime(j);
  k := j * FSim.FrameEvery;

  FTimePlot.ClearSeries;
  for i := 0 to 3 do
  begin
    FTimePlot.SetSeriesStyle(i, SiteCol[i], 2, plsSolid, '');
    FTimePlot.SetSeriesStyle(4 + i, SiteCol[i], 0, plsNone, '', pmsCircle, 10);
  end;
  FTimePlot.SetData(FT, [FPSite[0], FPSite[1], FPSite[2], FPSite[3]]);
  for i := 0 to 3 do FTimePlot.PlotXY(t, FSim.Probes[FSite[i]].P[k], 4 + i);

  // the wave: both paths against distance; an unseen series holds the scale
  FWavePlot.ClearSeries;
  FWavePlot.SetSeriesStyle(0, SiteCol[2], 2.5, plsSolid, '');
  FWavePlot.SetSeriesStyle(1, SiteCol[3], 2.5, plsSolid, '');
  FWavePlot.SetSeriesStyle(2, clWhite, 0, plsNone, '');
  // the wrist's path whole; the groin's every fourth node, point by
  // point (each PlotXY refits the bounds, so few of them)
  n := Length(FSim.Paths[0].Nodes);
  W := TVMobj.Create(1, n);
  for k := 0 to n - 1 do W[0, k] := FSim.Paths[0].P[j][k];
  FWavePlot.SetData(FX[0], [W]);
  n := Length(FSim.Paths[1].Nodes);
  k := 0;
  while k < n do
  begin
    FWavePlot.PlotXY(FX[1][0, k], FSim.Paths[1].P[j][k], 1);
    if (k < n - 1) and (k + 4 > n - 1) then k := n - 1 else Inc(k, 4);
  end;
  FWavePlot.PlotXY(0, FSim.PMin, 2);
  FWavePlot.PlotXY(0, FSim.PMax, 2);

  k := j * FSim.FrameEvery;
  FFlowPlot.ClearSeries;
  for i := 0 to 3 do
  begin
    FFlowPlot.SetSeriesStyle(i, QCol[i], 2, plsSolid, QLegend[i]);
    FFlowPlot.SetSeriesStyle(4 + i, QCol[i], 0, plsNone, '', pmsCircle, 10);
  end;
  FFlowPlot.SetData(FT, [FQ[0], FQ[1], FQ[2], FQ[3]]);
  for i := 0 to 3 do FFlowPlot.PlotXY(t, QScale[i] * FSim.Probes[FQSite[i]].Q[k], 4 + i);
end;

procedure TAortaViewForm.ShowFrame(j: Integer);
var
  ir, ifm: Integer;
begin
  if FSim.NFrames = 0 then Exit;
  FView.Frame := j;
  if tbFrame.Position <> j then
  begin
    FUpdating := True;
    tbFrame.Position := j;
    FUpdating := False;
  end;
  UpdatePlots(j);
  FInfo.Invalidate;
  ir := FSite[2]; ifm := FSite[3];
  FStatus.SimpleText := Format('%s   |   %.0f /min, stroke volume %.1f mL   |   aortic elastance x %.2f, '
    + 'bed compliance %.2f mL/mmHg, wall %.0f ms   |   foot of the wave: wrist %.0f ms (%.1f m/s), groin %.0f ms (%.1f m/s)   |   '
    + '%d beats in %.1f s',
    [ExtractFileName(LVFile), 60 / FSim.LV.Period, FSim.LV.StrokeVolume, FSim.AorticStiff, FSim.CPeriph, FSim.WallTau,
     1000 * (FSim.Probes[ir].TFoot - FSim.Probes[0].TFoot), FSim.Probes[ir].PWV / 100,
     1000 * (FSim.Probes[ifm].TFoot - FSim.Probes[0].TFoot), FSim.Probes[ifm].PWV / 100,
     FSim.Beats, FComputeMs / 1000]);
end;

procedure TAortaViewForm.InfoPaint(Sender: TObject);
var
  C: TCanvas;
  i, k, x0: Integer;
  S: string;
begin
  C := FInfo.Canvas;
  C.Brush.Color := clBtnFace;
  C.FillRect(FInfo.ClientRect);
  if FSim.NFrames = 0 then
  begin
    C.Font.Size := 11;
    C.TextOut(10, 18, 'Press Compute.');
    Exit;
  end;
  k := FView.Frame * FSim.FrameEvery;
  C.Font.Size := 13;
  C.Font.Style := [fsBold];
  C.Font.Color := clBlack;
  C.TextOut(10, 4, Format('%.0f ms', [1000 * FrameTime(FView.Frame)]));
  C.Font.Size := 10;
  C.Font.Style := [];
  C.TextOut(110, 8, Format('valve flow %.0f mL/s', [FSim.LV.Flow(FrameTime(FView.Frame))]));
  x0 := 10;
  for i := 0 to 3 do
  begin
    C.Font.Color := SiteCol[i];
    C.Font.Style := [fsBold];
    S := Format('%s %.0f', [SiteShort[i], FSim.Probes[FSite[i]].P[k]]);
    C.TextOut(x0, 32, S);
    x0 := x0 + C.TextWidth(S) + 6;
    C.Font.Color := clGray;
    C.Font.Style := [];
    S := Format('(%.0f/%.0f)', [FSim.Probes[FSite[i]].Sys, FSim.Probes[FSite[i]].Dia]);
    C.TextOut(x0, 32, S);
    x0 := x0 + C.TextWidth(S) + 22;
  end;
  C.Font.Color := clBlack;
  C.TextOut(x0, 32, 'mmHg');
end;

procedure TAortaViewForm.BarPaint(Sender: TObject);
var
  C: TCanvas;
  i, x0, x1, w: Integer;
  r, g, b: Single;
  v, step: Double;
  S: string;
begin
  C := FBar.Canvas;
  C.Brush.Color := clBtnFace;
  C.FillRect(FBar.ClientRect);
  if FSim.NFrames = 0 then Exit;
  x0 := 60; x1 := FBar.Width - 60;
  w := x1 - x0;
  if w < 50 then Exit;
  for i := 0 to w - 1 do
  begin
    PressureColour(i / (w - 1), r, g, b);
    C.Pen.Color := RGBToColor(Round(255 * r), Round(255 * g), Round(255 * b));
    C.Line(x0 + i, 6, x0 + i, 24);
  end;
  C.Font.Size := 9;
  C.Font.Color := clBlack;
  C.Brush.Style := bsClear;
  if FSim.PMax - FSim.PMin > 200 then step := 50 else if FSim.PMax - FSim.PMin > 80 then step := 20 else step := 10;
  v := Ceil(FSim.PMin / step) * step;
  while v <= FSim.PMax do
  begin
    i := x0 + Round((v - FSim.PMin) / (FSim.PMax - FSim.PMin) * (w - 1));
    C.Pen.Color := clBlack;
    C.Line(i, 24, i, 29);
    S := Format('%.0f', [v]);
    C.TextOut(i - C.TextWidth(S) div 2, 30, S);
    v := v + step;
  end;
  C.TextOut(4, 8, 'mmHg');
end;

procedure TAortaViewForm.Restart(j: Integer);
begin
  FTime0 := FrameTime(j);
  FClock0 := GetTickCount64;
end;

procedure TAortaViewForm.PlayTick(Sender: TObject);
var
  t: Double;
  j: Integer;
begin
  if FSim.NFrames = 0 then Exit;
  t := FTime0 + (GetTickCount64 - FClock0) / 1000 * Speed;
  t := t - FSim.LV.Period * Floor(t / FSim.LV.Period);
  j := FrameAtTime(t);
  if j <> FView.Frame then ShowFrame(j);
end;

procedure TAortaViewForm.PlayClick(Sender: TObject);
begin
  if FPlay.Enabled then
  begin
    FPlay.Enabled := False;
    btnPlay.Caption := 'Play';
  end
  else
  begin
    Restart(FView.Frame);
    FPlay.Enabled := True;
    btnPlay.Caption := 'Pause';
  end;
end;

procedure TAortaViewForm.ResetClick(Sender: TObject);
begin
  FView.ResetView;
end;

procedure TAortaViewForm.SaveClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'PNG|*.png';
    D.DefaultExt := 'png';
    D.InitialDir := FDir + 'out';
    D.FileName := 'aortaview.png';
    if D.Execute then FView.SaveToPNG(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TAortaViewForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'lvrun --csv|*.csv';
    D.InitialDir := ExtractFilePath(LVFile);
    if D.Execute then
    begin
      LVFile := D.FileName;
      Compute;
    end;
  finally
    D.Free;
  end;
end;

procedure TAortaViewForm.ComputeClick(Sender: TObject);
begin
  Compute;
end;

procedure TAortaViewForm.FrameChange(Sender: TObject);
begin
  if FUpdating then Exit;
  ShowFrame(tbFrame.Position);
  Restart(tbFrame.Position);
end;

procedure TAortaViewForm.SpeedChange(Sender: TObject);
begin
  Restart(FView.Frame);
end;

procedure TAortaViewForm.LookChange(Sender: TObject);
begin
  FView.Exaggeration := seExag.Value;
  FView.ShowLabels := cbLabels.Checked;
end;

procedure TAortaViewForm.ShowFrameAt(j: Integer);
begin
  FPlay.Enabled := False;
  btnPlay.Caption := 'Play';
  ShowFrame(EnsureRange(j, 0, Max(0, FSim.NFrames - 1)));
end;

function TAortaViewForm.SaveSnapshot(const Prefix: string): Boolean;
begin
  Result := FView.SaveToPNG(Prefix + '_view.png');
  FTimePlot.SaveToPNG(Prefix + '_pressure.png');
  FWavePlot.SaveToPNG(Prefix + '_wave.png');
  FFlowPlot.SaveToPNG(Prefix + '_flow.png');
end;

function TAortaViewForm.Benchmark(n: Integer): Double;
var
  i: Integer;
  tick: QWord;
begin
  FPlay.Enabled := False;
  tick := GetTickCount64;
  for i := 0 to n - 1 do
  begin
    ShowFrame(i mod FSim.NFrames);
    Application.ProcessMessages;
  end;
  Result := n / Max(1, GetTickCount64 - tick) * 1000;
end;

end.
