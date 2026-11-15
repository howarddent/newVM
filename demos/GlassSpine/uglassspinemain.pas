{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

unit uGlassSpineMain;

{*******************************************************************************

  GlassSpine's window: the 3-D view (uSpineView) of two glass dural sacs,
  a solution in each (hyperbaric and plain bupivacaine by default), the
  injectate's distribution by vertebral level on a TVMPlot2D beneath it,
  and the controls on the right. A second tab, "Methodology"
  (uGlassSpineMethod), explains how the simulation works. The simulation (uGlassSpineSim) runs on
  the GPU from Application.OnIdle, at a chosen multiple of real time.

  Posture: Tilt (+ head up, 90 = sitting, - = head down) and Roll (+90 =
  left lateral, 180 = prone), by the sliders, the preset buttons or a
  right drag in the view. Gravity stays world-down.

  Command line:
    --snapshot=<prefix>   inject, run to --time, save <prefix>.png (the
                          view), <prefix>_profile.png and <prefix>.bmp
                          (the window), print the readout, exit
    --time=<s>            simulated time for --snapshot (default 120)
    --tilt=<deg> --roll=<deg> --sol0=<n> --sol1=<n> --level=<n>
    --speed=<n>           index into the speed list
    --pulse=0             start with CSF pulsation off
    --tab=method          open on the Methodology tab

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls,
  ComCtrls, Spin, LCLType, LCLIntf, newVM, uVMPlot2D, uSpineGeom,
  uGlassSpineSim, uSpineView, uGlassSpineMethod;

type
  TSolution = record
    Name: string;
    Short: string;
    Baricity: Single;
  end;

  { TfmGlassSpine }

  TfmGlassSpine = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FSim: TSpineSim;
    FView: TSpineView;
    FPlot: TVMPlot2D;
    FLeft, FRight: TPanel;
    FPages: TPageControl;
    tsSim, tsMethod: TTabSheet;
    mmMethod: TMemo;
    tbTilt, tbRoll, tbOpacity: TTrackBar;
    lblTilt, lblRoll, lblTime, lblStatus: TLabel;
    cbSol: array[0..1] of TComboBox;
    cbLevel, cbNeedle, cbJet, cbSpeed: TComboBox;
    seDose, seDur: TFloatSpinEdit;
    btnPause: TButton;
    chkRoots, chkPulse: TCheckBox;
    seCardML, seHR, seRespML, seRR: TFloatSpinEdit;
    mmInfo: TMemo;
    FPaused, FUpdating: Boolean;
    FLastTick: QWord;
    FLastInfo, FLastPlot: QWord;
    FError: string;
    FFrames: Integer;
    FFpsStart: QWord;
    FFps: Single;
    FAutoEnd: QWord;
    FDebt: Double;       // simulated time owed to the clock, s
    function AddGroup(const ACaption: string; var Y: Integer; H: Integer): TGroupBox;
    function AddLabel(AParent: TWinControl; const ACaption: string; X, Y: Integer): TLabel;
    function AddCombo(AParent: TWinControl; X, Y, W: Integer; const Items: array of string;
      Index: Integer): TComboBox;
    function AddButton(AParent: TWinControl; const ACaption: string; X, Y, W: Integer;
      Handler: TNotifyEvent; ATag: Integer = 0): TButton;
    procedure BuildControls;
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure PostureSlider(Sender: TObject);
    procedure PostureFromView(Sender: TObject);
    procedure PresetClick(Sender: TObject);
    procedure SolutionChange(Sender: TObject);
    procedure InjectClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure PauseClick(Sender: TObject);
    procedure ResetViewClick(Sender: TObject);
    procedure RootsClick(Sender: TObject);
    procedure OpacityChange(Sender: TObject);
    procedure PulseChange(Sender: TObject);
    procedure PageChange(Sender: TObject);
    function AddSpin(AParent: TWinControl; X, Y, W: Integer; AMin, AMax, AInc, AValue: Double;
      Places: Integer): TFloatSpinEdit;
    procedure SyncPostureControls;
    procedure ApplyInjectionSettings;
    procedure UpdateTitles;
    procedure UpdateInfo;
    procedure UpdatePlot;
    procedure RunSnapshot(Data: PtrInt);
  end;

var
  fmGlassSpine: TfmGlassSpine;

const
  // baricity = density / CSF density, both at 37 C. Plain bupivacaine is
  // sold as isobaric but is slightly hypobaric at body temperature.
  Solutions: array[0..4] of TSolution = (
    (Name: 'Hyperbaric bupivacaine 0.5% in glucose 8% (b 1.020)'; Short: 'hyperbaric 1.020'; Baricity: 1.0200),
    (Name: 'Plain "isobaric" bupivacaine 0.5% (b 0.999 at 37 C)'; Short: 'plain 0.999'; Baricity: 0.9990),
    (Name: 'Exactly isobaric (b 1.000)'; Short: 'isobaric 1.000'; Baricity: 1.0000),
    (Name: 'Mildly hyperbaric (b 1.005)'; Short: 'hyperbaric 1.005'; Baricity: 1.0050),
    (Name: 'Hypobaric (b 0.995)'; Short: 'hypobaric 0.995'; Baricity: 0.9950));
  Speeds: array[0..5] of Single = (0.5, 1, 2, 5, 10, 20);
  NeedleIDs: array[0..2] of Single = (0.41, 0.26, 0.21);   // 22G, 25G, 27G lumen, mm

implementation

{$R *.lfm}

function OptValue(const Name: string; const Def: string): string;
var
  i: Integer;
  p: string;
begin
  Result := Def;
  p := '--' + Name + '=';
  for i := 1 to ParamCount do
    if Copy(ParamStr(i), 1, Length(p)) = p then Exit(Copy(ParamStr(i), Length(p) + 1, MaxInt));
end;

{ TfmGlassSpine }

function TfmGlassSpine.AddGroup(const ACaption: string; var Y: Integer; H: Integer): TGroupBox;
begin
  Result := TGroupBox.Create(Self);
  Result.Parent := FRight;
  Result.Caption := ACaption;
  Result.SetBounds(6, Y, FRight.Width - 12, H);
  Result.Anchors := [akLeft, akTop, akRight];
  Y := Y + H + 6;
end;

function TfmGlassSpine.AddLabel(AParent: TWinControl; const ACaption: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Left := X;
  Result.Top := Y;
end;

function TfmGlassSpine.AddCombo(AParent: TWinControl; X, Y, W: Integer; const Items: array of string;
  Index: Integer): TComboBox;
var
  i: Integer;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.Style := csDropDownList;
  Result.SetBounds(X, Y, W, 26);
  for i := 0 to High(Items) do Result.Items.Add(Items[i]);
  Result.ItemIndex := Index;
end;

function TfmGlassSpine.AddButton(AParent: TWinControl; const ACaption: string; X, Y, W: Integer;
  Handler: TNotifyEvent; ATag: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(X, Y, W, 26);
  Result.OnClick := Handler;
  Result.Tag := ATag;
end;

function TfmGlassSpine.AddSpin(AParent: TWinControl; X, Y, W: Integer; AMin, AMax, AInc,
  AValue: Double; Places: Integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 26);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.Increment := AInc;
  Result.DecimalPlaces := Places;
  Result.Value := AValue;
end;

procedure TfmGlassSpine.BuildControls;
var
  Y, s, i: Integer;
  G: TGroupBox;
  Names: array of string;
  sw: TShape;
begin
  FRight := TPanel.Create(Self);
  FRight.Parent := Self;
  FRight.Align := alRight;
  FRight.Width := 370;
  FRight.BevelOuter := bvNone;

  // two tabs left of the controls: the simulation, and a page of text
  // explaining how it works
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  tsSim := FPages.AddTabSheet;
  tsSim.Caption := 'Simulation';
  tsMethod := FPages.AddTabSheet;
  tsMethod.Caption := 'Methodology';
  FPages.OnChange := @PageChange;

  mmMethod := TMemo.Create(Self);
  mmMethod.Parent := tsMethod;
  mmMethod.Align := alClient;
  mmMethod.BorderSpacing.Around := 8;
  mmMethod.ReadOnly := True;
  mmMethod.WordWrap := True;
  mmMethod.ScrollBars := ssAutoVertical;
  mmMethod.Font.Size := 11;
  FillMethodology(mmMethod.Lines, FSim);
  mmMethod.SelStart := 0;

  FLeft := TPanel.Create(Self);
  FLeft.Parent := tsSim;
  FLeft.Align := alClient;
  FLeft.BevelOuter := bvNone;

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := FLeft;
  FPlot.Align := alBottom;
  FPlot.Height := 230;
  FPlot.Title := 'Injectate by level';
  FPlot.XAxisTitle := 'level';
  FPlot.YAxisTitle := 'injectate (mL)';

  FView := TSpineView.Create(Self);
  FView.Parent := FLeft;
  FView.Align := alClient;
  FView.Sim := FSim;
  FView.OnPosture := @PostureFromView;

  Y := 6;
  G := AddGroup('Posture (gravity stays world-down)', Y, 196);
  lblTilt := AddLabel(G, '', 8, 4);
  tbTilt := TTrackBar.Create(Self);
  tbTilt.Parent := G;
  tbTilt.SetBounds(4, 20, G.ClientWidth - 8, 30);
  tbTilt.Min := -90; tbTilt.Max := 90; tbTilt.Frequency := 15;
  tbTilt.OnChange := @PostureSlider;
  lblRoll := AddLabel(G, '', 8, 54);
  tbRoll := TTrackBar.Create(Self);
  tbRoll.Parent := G;
  tbRoll.SetBounds(4, 70, G.ClientWidth - 8, 30);
  tbRoll.Min := -180; tbRoll.Max := 180; tbRoll.Frequency := 30;
  tbRoll.OnChange := @PostureSlider;
  AddButton(G, 'Supine', 6, 106, 84, @PresetClick, 0);
  AddButton(G, 'Sitting', 92, 106, 84, @PresetClick, 1);
  AddButton(G, 'L lateral', 178, 106, 84, @PresetClick, 2);
  AddButton(G, 'R lateral', 264, 106, 84, @PresetClick, 3);
  AddButton(G, 'Prone', 6, 136, 84, @PresetClick, 4);
  AddButton(G, 'Head down 15', 92, 136, 128, @PresetClick, 5);
  AddButton(G, 'Head up 15', 222, 136, 126, @PresetClick, 6);

  G := AddGroup('Solutions', Y, 98);
  SetLength(Names, Length(Solutions));
  for i := 0 to High(Solutions) do Names[i] := Solutions[i].Name;
  for s := 0 to 1 do
  begin
    sw := TShape.Create(Self);
    sw.Parent := G;
    sw.SetBounds(6, 8 + 34 * s, 16, 16);
    sw.Brush.Color := FView.DrugColor[s];
    cbSol[s] := AddCombo(G, 28, 4 + 34 * s, G.ClientWidth - 34, Names, s);
    cbSol[s].OnChange := @SolutionChange;
  end;

  G := AddGroup('Injection', Y, 182);
  AddLabel(G, 'Interspace', 8, 8);
  cbLevel := AddCombo(G, 110, 4, 110, Interspaces, 1);
  AddLabel(G, 'Volume (mL)', 8, 40);
  seDose := TFloatSpinEdit.Create(Self);
  seDose.Parent := G;
  seDose.SetBounds(110, 36, 80, 26);
  seDose.MinValue := 0.5; seDose.MaxValue := 6; seDose.Increment := 0.5;
  seDose.DecimalPlaces := 1; seDose.Value := 3;
  AddLabel(G, 'over (s)', 200, 40);
  seDur := TFloatSpinEdit.Create(Self);
  seDur.Parent := G;
  seDur.SetBounds(260, 36, 80, 26);
  seDur.MinValue := 2; seDur.MaxValue := 120; seDur.Increment := 5;
  seDur.DecimalPlaces := 0; seDur.Value := 15;
  AddLabel(G, 'Needle', 8, 72);
  cbNeedle := AddCombo(G, 110, 68, 110, ['22G', '25G', '27G'], 1);
  AddLabel(G, 'Opening', 8, 104);
  cbJet := AddCombo(G, 110, 100, 230, ['facing cephalad', 'facing caudad', 'no jet'], 0);
  AddButton(G, 'Inject', 8, 134, 160, @InjectClick);
  AddButton(G, 'Clear', 176, 134, 160, @ClearClick);

  G := AddGroup('Run', Y, 128);
  AddLabel(G, 'Speed', 8, 8);
  cbSpeed := AddCombo(G, 60, 4, 110, ['x 0.5', 'real time', 'x 2', 'x 5', 'x 10', 'x 20'], 3);
  btnPause := AddButton(G, 'Pause', 180, 4, 76, @PauseClick);
  AddButton(G, 'View', 262, 4, 76, @ResetViewClick);
  lblTime := AddLabel(G, '', 8, 38);
  chkRoots := TCheckBox.Create(Self);
  chkRoots.Parent := G;
  chkRoots.SetBounds(8, 60, 330, 22);
  chkRoots.Caption := 'Cauda equina drag below the conus (estimate)';
  chkRoots.OnClick := @RootsClick;
  AddLabel(G, 'Visibility', 8, 88);
  tbOpacity := TTrackBar.Create(Self);
  tbOpacity.Parent := G;
  tbOpacity.SetBounds(80, 80, G.ClientWidth - 88, 30);
  tbOpacity.Min := 1; tbOpacity.Max := 40; tbOpacity.Position := 9;
  tbOpacity.OnChange := @OpacityChange;

  G := AddGroup('CSF pulsation (volume through T1 per cycle)', Y, 112);
  chkPulse := TCheckBox.Create(Self);
  chkPulse.Parent := G;
  chkPulse.SetBounds(8, 2, 330, 22);
  chkPulse.Caption := 'CSF moves with the heartbeat and breathing';
  chkPulse.Checked := True;
  AddLabel(G, 'Heartbeat', 8, 32);
  seCardML := AddSpin(G, 92, 28, 74, 0, 2, 0.05, 0.3, 2);
  AddLabel(G, 'mL at', 172, 32);
  seHR := AddSpin(G, 220, 28, 70, 30, 180, 5, 70, 0);
  AddLabel(G, '/min', 296, 32);
  AddLabel(G, 'Breathing', 8, 62);
  seRespML := AddSpin(G, 92, 58, 74, 0, 2, 0.05, 0.3, 2);
  AddLabel(G, 'mL at', 172, 62);
  seRR := AddSpin(G, 220, 58, 70, 4, 40, 1, 12, 0);
  AddLabel(G, '/min', 296, 62);
  chkPulse.OnClick := @PulseChange;
  seCardML.OnChange := @PulseChange;
  seHR.OnChange := @PulseChange;
  seRespML.OnChange := @PulseChange;
  seRR.OnChange := @PulseChange;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := FRight;
  lblStatus.Align := alBottom;
  lblStatus.WordWrap := True;
  lblStatus.AutoSize := True;
  lblStatus.BorderSpacing.Around := 6;

  mmInfo := TMemo.Create(Self);
  mmInfo.Parent := FRight;
  mmInfo.SetBounds(6, Y, FRight.Width - 12, 100);
  mmInfo.Anchors := [akLeft, akTop, akRight, akBottom];
  mmInfo.AnchorSideBottom.Control := lblStatus;
  mmInfo.ReadOnly := True;
  mmInfo.ScrollBars := ssAutoVertical;
  mmInfo.Font.Name := 'Monospace';
  mmInfo.Font.Size := 9;
end;

procedure TfmGlassSpine.FormCreate(Sender: TObject);
begin
  Caption := 'GlassSpine - spinal anaesthetic spread';
  Width := 1500;
  Height := 960;
  FPaused := False;
  try
    FSim := TSpineSim.Create(ExtractFilePath(ParamStr(0)) + 'glassspine.cl');
    FSim.Setup(1.25, 1);
  except
    on E: Exception do
    begin
      FError := E.Message;
      FreeAndNil(FSim);
    end;
  end;
  BuildControls;
  mmInfo.Height := FRight.ClientHeight - mmInfo.Top - 60;
  if FSim <> nil then
  begin
    FSim.TiltDeg := StrToFloatDef(OptValue('tilt', '0'), 0);
    FSim.RollDeg := StrToFloatDef(OptValue('roll', '0'), 0);
    cbSol[0].ItemIndex := EnsureRange(StrToIntDef(OptValue('sol0', '0'), 0), 0, High(Solutions));
    cbSol[1].ItemIndex := EnsureRange(StrToIntDef(OptValue('sol1', '1'), 1), 0, High(Solutions));
    cbLevel.ItemIndex := EnsureRange(StrToIntDef(OptValue('level', '1'), 1), 0, 2);
    cbSpeed.ItemIndex := EnsureRange(StrToIntDef(OptValue('speed', '3'), 3), 0, High(Speeds));
    chkPulse.Checked := OptValue('pulse', '1') <> '0';
    PulseChange(nil);
    FSim.Baricity[0] := Solutions[cbSol[0].ItemIndex].Baricity;
    FSim.Baricity[1] := Solutions[cbSol[1].ItemIndex].Baricity;
    ApplyInjectionSettings;
    lblStatus.Caption := Format('OpenCL on %s. %d x %d x %d cells of %.2f mm, %.0f mL CSF a sac. '
      + 'Left drag: camera. Right drag: turn the patient. Wheel: zoom.',
      [FSim.DeviceName, FSim.Geom.NX, FSim.Geom.NY, FSim.Geom.NZ, FSim.Geom.Dx,
       FSim.Geom.FluidCount[0] * FSim.Geom.CellVolume / 1000]);
  end
  else
    lblStatus.Caption := 'No simulation: ' + FError;
  UpdateTitles;
  SyncPostureControls;
  UpdateInfo;
  UpdatePlot;
  FPages.ActivePage := tsSim;
  if OptValue('tab', '') = 'method' then
  begin
    FPages.ActivePage := tsMethod;
    PageChange(nil);
  end;
  FLastTick := GetTickCount64;
  Application.OnIdle := @AppIdle;
end;

procedure TfmGlassSpine.FormDestroy(Sender: TObject);
begin
  Application.OnIdle := nil;
  FView.Sim := nil;
  FreeAndNil(FSim);
end;

procedure TfmGlassSpine.FormShow(Sender: TObject);
begin
  if OptValue('snapshot', '') <> '' then
    Application.QueueAsyncCall(@RunSnapshot, 0)
  else if OptValue('autorun', '') <> '' then
  begin
    // inject at once and run interactively for the given wall time
    InjectClick(nil);
    FAutoEnd := GetTickCount64 + Round(1000 * StrToFloatDef(OptValue('autorun', '10'), 10));
  end;
end;

procedure TfmGlassSpine.ApplyInjectionSettings;
begin
  if FSim = nil then Exit;
  FSim.Interspace := cbLevel.ItemIndex;
  FSim.DoseML := seDose.Value;
  FSim.DurationS := seDur.Value;
  FSim.NeedleIDmm := NeedleIDs[cbNeedle.ItemIndex];
  case cbJet.ItemIndex of
    0: FSim.JetDir := 1;
    1: FSim.JetDir := -1;
  else
    FSim.JetDir := 0;
  end;
end;

procedure TfmGlassSpine.UpdateTitles;
var
  s: Integer;
begin
  for s := 0 to 1 do FView.Titles[s] := Solutions[cbSol[s].ItemIndex].Short;
  FView.TitlesChanged;
end;

procedure TfmGlassSpine.SyncPostureControls;
var
  t, r: Single;
  d: string;
begin
  if FSim = nil then Exit;
  t := FSim.TiltDeg;
  r := FSim.RollDeg;
  FUpdating := True;
  tbTilt.Position := Round(t);
  tbRoll.Position := Round(r);
  FUpdating := False;
  if Abs(t) < 0.5 then d := 'level'
  else if t > 0 then d := Format('head up %.0f', [t])
  else d := Format('head down %.0f', [-t]);
  lblTilt.Caption := Format('Tilt %.0f deg (%s)', [t, d]);
  if Abs(r) < 10 then d := 'supine'
  else if Abs(Abs(r) - 180) < 10 then d := 'prone'
  else if Abs(r - 90) < 10 then d := 'left lateral'
  else if Abs(r + 90) < 10 then d := 'right lateral'
  else if r > 0 then d := 'turned to the left'
  else d := 'turned to the right';
  lblRoll.Caption := Format('Roll %.0f deg (%s)', [r, d]);
end;

procedure TfmGlassSpine.PostureSlider(Sender: TObject);
begin
  if FUpdating or (FSim = nil) then Exit;
  FSim.TiltDeg := tbTilt.Position;
  FSim.RollDeg := tbRoll.Position;
  SyncPostureControls;
  FView.Invalidate;
end;

procedure TfmGlassSpine.PostureFromView(Sender: TObject);
begin
  SyncPostureControls;
end;

procedure TfmGlassSpine.PresetClick(Sender: TObject);
const
  T: array[0..6] of Single = (0, 90, 0, 0, 0, -15, 15);
  R: array[0..6] of Single = (0, 0, 90, -90, 180, 0, 0);
var
  i: Integer;
begin
  if FSim = nil then Exit;
  i := TButton(Sender).Tag;
  FSim.TiltDeg := T[i];
  FSim.RollDeg := R[i];
  SyncPostureControls;
  FView.Invalidate;
end;

procedure TfmGlassSpine.SolutionChange(Sender: TObject);
var
  s: Integer;
begin
  if FSim = nil then Exit;
  for s := 0 to 1 do FSim.Baricity[s] := Solutions[cbSol[s].ItemIndex].Baricity;
  UpdateTitles;
end;

procedure TfmGlassSpine.InjectClick(Sender: TObject);
begin
  if FSim = nil then Exit;
  ApplyInjectionSettings;
  FSim.Reset;
  FSim.StartInjection;
  FLastTick := GetTickCount64;
  UpdateInfo;
  UpdatePlot;
end;

procedure TfmGlassSpine.ClearClick(Sender: TObject);
begin
  if FSim = nil then Exit;
  FSim.Reset;
  UpdateInfo;
  UpdatePlot;
  FView.Invalidate;
end;

procedure TfmGlassSpine.PauseClick(Sender: TObject);
begin
  FPaused := not FPaused;
  if FPaused then btnPause.Caption := 'Run' else btnPause.Caption := 'Pause';
  FLastTick := GetTickCount64;
end;

procedure TfmGlassSpine.ResetViewClick(Sender: TObject);
begin
  FView.ResetView;
end;

procedure TfmGlassSpine.RootsClick(Sender: TObject);
begin
  if FSim = nil then Exit;
  if chkRoots.Checked then FSim.RootsDrag := 5 else FSim.RootsDrag := 0;
end;

procedure TfmGlassSpine.PageChange(Sender: TObject);
begin
  // the closing "this run" section follows the current settings
  if FPages.ActivePage = tsMethod then
  begin
    FillMethodology(mmMethod.Lines, FSim);
    mmMethod.SelStart := 0;
  end;
end;

procedure TfmGlassSpine.PulseChange(Sender: TObject);
begin
  if FSim = nil then Exit;
  // takes effect at once; the flow changes smoothly from the next step
  FSim.Pulse := chkPulse.Checked;
  FSim.CardiacML := seCardML.Value;
  FSim.HeartRate := seHR.Value;
  FSim.RespML := seRespML.Value;
  FSim.RespRate := seRR.Value;
  seCardML.Enabled := chkPulse.Checked;
  seHR.Enabled := chkPulse.Checked;
  seRespML.Enabled := chkPulse.Checked;
  seRR.Enabled := chkPulse.Checked;
end;

procedure TfmGlassSpine.OpacityChange(Sender: TObject);
begin
  FView.Opacity := tbOpacity.Position / 10;
  FView.Invalidate;
end;

procedure TfmGlassSpine.AppIdle(Sender: TObject; var Done: Boolean);
var
  now_: QWord;
  dt: Double;
  n, i: Integer;
begin
  Done := False;
  now_ := GetTickCount64;
  dt := Min(0.1, (now_ - FLastTick) / 1000);
  FLastTick := now_;
  if (FSim <> nil) and not FPaused then
  begin
    try
      // whole steps only, the remainder carried to the next frame; at most
      // 40 a frame, so the window stays responsive when the GPU can't
      // keep up with the chosen speed (the shortfall is then dropped)
      FDebt := FDebt + dt * Speeds[cbSpeed.ItemIndex];
      n := Floor(FDebt / FSim.Dt);
      if n > 40 then
      begin
        n := 40;
        FDebt := 0;
      end
      else
        FDebt := FDebt - n * FSim.Dt;
      for i := 1 to n do FSim.Step;
      if n > 0 then FSim.ReadBack;
    except
      on E: Exception do
      begin
        FPaused := True;
        lblStatus.Caption := 'Stopped: ' + E.Message;
      end;
    end;
  end;
  FView.Invalidate;
  Inc(FFrames);
  if now_ - FFpsStart >= 1000 then
  begin
    FFps := FFrames * 1000 / (now_ - FFpsStart);
    FFrames := 0;
    FFpsStart := now_;
  end;
  if (FAutoEnd > 0) and (now_ > FAutoEnd) then
  begin
    FAutoEnd := 0;
    UpdateInfo;
    WriteLn(Format('%.1f fps, simulated %.1f s', [FFps, FSim.Time]));
    WriteLn(mmInfo.Lines.Text);
    FView.SaveToPNG(OptValue('png', 'autorun.png'));
    Halt(0);
  end;
  if now_ - FLastInfo > 250 then UpdateInfo;
  if now_ - FLastPlot > 500 then UpdatePlot;
  Sleep(1);
end;

procedure TfmGlassSpine.UpdateInfo;
var
  L: TStringList;
  s: Integer;
  ce, cd, peak: Single;
  i, pk: Integer;
  inj, dir: string;
  q: Double;
begin
  FLastInfo := GetTickCount64;
  if FSim = nil then Exit;
  if FSim.InjectStart < 0 then
    lblTime.Caption := Format('t = %.1f s   (press Inject)', [FSim.Time])
  else
  begin
    if FSim.Injecting then inj := ' - injecting' else inj := '';
    lblTime.Caption := Format('%.0f s since injection began%s', [FSim.Time - FSim.InjectStart, inj]);
  end;
  L := TStringList.Create;
  try
    for s := 0 to 1 do
    begin
      L.Add(Solutions[cbSol[s].ItemIndex].Name);
      L.Add(Format('  injected %.2f mL, in the sac %.2f mL', [FSim.Injected[s] / 1000,
        FSim.Present[s] / 1000]));
      ce := FSim.CephaladExtent(s, 0.01);
      cd := FSim.CaudalExtent(s, 0.01);
      if ce >= 0 then
        L.Add(Format('  C >= 1%%: %s up to %s', [LevelText(cd), LevelText(ce)]));
      ce := FSim.CephaladExtent(s, 0.05);
      if ce >= 0 then
        L.Add(Format('  C >= 5%%: up to %s', [LevelText(ce)]));
      pk := -1;
      peak := 0;
      for i := 0 to NLevels - 1 do
        if FSim.Profile[s, i] > peak then
        begin
          peak := FSim.Profile[s, i];
          pk := i;
        end;
      if pk >= 0 then
        L.Add(Format('  most at %s (%.2f mL)', [LevelNames[pk], peak]));
      L.Add('');
    end;
    L.Add('C is the injectate''s volume fraction;');
    L.Add('x5 mg/mL for a 0.5% solution.');
    if FSim.Pulse then
    begin
      q := FSim.PulseFlow(FSim.Time) / 1000;
      if q >= 0 then dir := 'into the sac' else dir := 'to the head';
      L.Add(Format('CSF at T1: %.2f mL/s %s;', [Abs(q), dir]));
      L.Add(Format('the dura holds %.2f mL extra.', [FSim.PulseDisp / 1000]));
    end
    else
      L.Add('No CSF pulsation.');
    L.Add(Format('Last step: %d drug sub-steps, max %.0f mm/s', [FSim.LastSubsteps, FSim.LastMaxSpeed]));
    L.Add(Format('%.0f frames/s', [FFps]));
    mmInfo.Lines.Assign(L);
  finally
    L.Free;
  end;
end;

procedure TfmGlassSpine.UpdatePlot;
var
  X, Y0, Y1: TVMobj;
  i: Integer;
  Pos: array[0..NLevels - 1] of Double;
  Lab: array[0..NLevels - 1] of string;
begin
  FLastPlot := GetTickCount64;
  if FSim = nil then Exit;
  X := TVMobj.Create(1, NLevels);
  Y0 := TVMobj.Create(1, NLevels);
  Y1 := TVMobj.Create(1, NLevels);
  for i := 0 to NLevels - 1 do
  begin
    X[0, i] := i;
    Y0[0, i] := FSim.Profile[0, i];
    Y1[0, i] := FSim.Profile[1, i];
    Pos[i] := i;
    Lab[i] := LevelNames[i];
  end;
  FPlot.SetData(X, [Y0, Y1]);
  FPlot.SetSeriesStyle(0, FView.DrugColor[0], 2, plsSolid, Solutions[cbSol[0].ItemIndex].Short,
    pmsCircle, 6);
  FPlot.SetSeriesStyle(1, FView.DrugColor[1], 2, plsSolid, Solutions[cbSol[1].ItemIndex].Short,
    pmsCircle, 6);
  FPlot.SetXTickLabels(Pos, Lab);
end;

procedure TfmGlassSpine.RunSnapshot(Data: PtrInt);
var
  Prefix: string;
  T, tEnd: Double;
  Bmp: TBitmap;
begin
  Prefix := OptValue('snapshot', 'glassspine');
  tEnd := StrToFloatDef(OptValue('time', '120'), 120);
  Application.OnIdle := nil;
  try
    if FSim = nil then raise Exception.Create(FError);
    Application.ProcessMessages;
    InjectClick(nil);
    T := 0;
    while T < tEnd - 0.5 * FSim.Dt do
    begin
      FSim.Advance(Min(1.0, tEnd - T));
      T := FSim.Time;
    end;
    FSim.ReadBack;
    UpdateInfo;
    UpdatePlot;
    Application.ProcessMessages;
    FView.SaveToPNG(Prefix + '.png');
    FPlot.SaveToPNG(Prefix + '_profile.png');
    FView.Repaint;
    FPlot.Repaint;
    Application.ProcessMessages;
    Bmp := GetFormImage;
    try
      Bmp.SaveToFile(Prefix + '.bmp');
    finally
      Bmp.Free;
    end;
    WriteLn(lblTime.Caption);
    WriteLn(mmInfo.Lines.Text);
    if FView.LastError <> '' then WriteLn('view: ', FView.LastError);
  except
    on E: Exception do WriteLn('snapshot failed: ', E.Message);
  end;
  Halt(0);
end;

end.
