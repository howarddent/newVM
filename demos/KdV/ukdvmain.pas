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

unit ukdvmain;

{*******************************************************************************

     Main form for the KdV demo: two solitons of different heights, both
     launched at t = 0, the taller behind the shorter, integrated by the
     Korteweg-de Vries equation on a low-order Chebyshev grid (see
     ukdvmodel) and drawn as a waterfall on a TVMPlotStack - t = 0 at the
     front, each later time a step further back - so the taller, faster
     soliton shows as the steeper diagonal ridge, catching the shorter
     one up, merging with it and coming out ahead.

     Built on demos/Benney: the same Kaps-Rentrop integrator
     (../Benney/ukapsrentrop.pas) run on a TThread, one OdeInt call per
     output slice, each profile handed to the form through Synchronize so
     the stack builds up live, with Stop, Replay and Reset view.

     The ribbons are the scheme's own polynomial, s(x) q(x), evaluated on
     401 uniform points by barycentric interpolation (InterpMatrix,
     computed once per run, then one MatMult per slice). "Exact solution"
     overlays the exact two-soliton solution as a white line on every
     fifth slice, and the memo reports the largest difference from it,
     the conserved mass and the crests' phase shifts against the
     predicted ones.

     --snapshot=<prefix>: run with the defaults, save the window as
     <prefix>.bmp, print the memo and exit. --n=<N> sets the order.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, uVMPlotStack, ukapsrentrop, ukdvmodel;

type
  TfmKdV = class;

  { The integration, off the GUI thread }
  TKdVThread = class(TThread)
  private
    FForm: TfmKdV;
    FModel: TKdVModel;
    FTotalTime: Double;
    FSlices: Integer;
    FProfile: TVMobj;
    FTime: Double;
    FSteps: Integer;
    FLastReport: QWord;
    procedure Step(x: Double; var Stop: Boolean);
    procedure PostProfile;
    procedure PostProgress;
  protected
    procedure Execute; override;
  public
    Flag: TErrFlags;
    constructor Create(AForm: TfmKdV; AModel: TKdVModel;
      ATotalTime: Double; ASlices: Integer);
  end;

  { TfmKdV }

  TfmKdV = class(TForm)
    btnRun: TButton;
    btnStop: TButton;
    btnReplay: TButton;
    btnResetView: TButton;
    cbExact: TCheckBox;
    lblA1: TLabel;
    lblA2: TLabel;
    lblX1: TLabel;
    lblX2: TLabel;
    lblL: TLabel;
    lblN: TLabel;
    lblTime: TLabel;
    lblSlices: TLabel;
    memInfo: TMemo;
    pnlControls: TPanel;
    pnlPlot: TPanel;
    ProgressBar1: TProgressBar;
    seA1: TFloatSpinEdit;
    seA2: TFloatSpinEdit;
    seX1: TFloatSpinEdit;
    seX2: TFloatSpinEdit;
    seL: TFloatSpinEdit;
    seN: TSpinEdit;
    seTime: TFloatSpinEdit;
    seSlices: TSpinEdit;
    tmrReplay: TTimer;
    procedure btnReplayClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure cbExactChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure tmrReplayTimer(Sender: TObject);
  private
    FStack: TVMPlotStack;
    FModel: TKdVModel;
    FThread: TKdVThread;
    FInterp: TVMobj;               // interior points -> display grid
    FXDisp: array of Double;       // the display grid
    FProfiles: array of TVMobj;    // u at the interior points, per slice
    FTimes: array of Double;
    FReplayIndex: Integer;
    FStartTick: QWord;
    FSnapshot: string;
    FLastFlag: TErrFlags;
    FSteps: Integer;
    function ParamsFromForm: TKdVParams;
    function Display(const U: TVMobj): TVMobj;
    function ExactDisplay(t: Double): TVMobj;
    procedure ThreadDone(Sender: TObject);
    procedure SetupStack;
    procedure ShowProfile(i: Integer);
    procedure ReplotAll;
    procedure WriteInfo(Running: Boolean);
    procedure DoSnapshot(Data: PtrInt);
    procedure SetRunning(Running: Boolean);
  public
    procedure ProfileReady(const U: TVMobj; t: Double);
    procedure Progress(t: Double; Steps: Integer);
  end;

var
  fmKdV: TfmKdV;

implementation

{$R *.lfm}

const
  Tolerance = 1e-4;      // the spatial error (~1e-3 at N = 128) dominates
  FirstStep = 1e-4;
  MinStep = 0.0;
  DisplayPoints = 401;

{ TKdVThread }

constructor TKdVThread.Create(AForm: TfmKdV; AModel: TKdVModel;
  ATotalTime: Double; ASlices: Integer);
begin
  FForm := AForm;
  FModel := AModel;
  FTotalTime := ATotalTime;
  FSlices := ASlices;
  FreeOnTerminate := True;     // OnTerminate (ThreadDone) drops the form's reference
  inherited Create(True);
end;

procedure TKdVThread.Step(x: Double; var Stop: Boolean);
begin
  Inc(FSteps);
  FTime := x;
  if GetTickCount64 - FLastReport >= 100 then
  begin
    FLastReport := GetTickCount64;
    Synchronize(@PostProgress);
  end;
  Stop := Terminated;
end;

procedure TKdVThread.PostProfile;
begin
  FForm.ProfileReady(FProfile, FTime);
end;

procedure TKdVThread.PostProgress;
begin
  FForm.Progress(FTime, FSteps);
end;

procedure TKdVThread.Execute;
var
  y: TVMobj;
  k: Integer;
  h, t0, t1, Floor: Double;
begin
  y := FModel.InitialProfile;
  FProfile := CopyObj(y);
  FTime := 0;
  Synchronize(@PostProfile);
  // an absolute error test on the scale of the taller soliton
  Floor := Max(FModel.Params.A1, FModel.Params.A2);
  h := FirstStep;
  Flag := OK;
  for k := 1 to FSlices do
  begin
    t0 := FTotalTime * (k - 1) / FSlices;
    t1 := FTotalTime * k / FSlices;
    Flag := OdeInt(y, t0, t1, Tolerance, h, MinStep,
      @FModel.Derivs, @FModel.Jacobn, @Step, h, Floor);
    if Flag <> OK then Break;
    FProfile := CopyObj(y);
    FTime := t1;
    Synchronize(@PostProfile);
  end;
  Synchronize(@PostProgress);
end;

{ TfmKdV }

procedure TfmKdV.FormCreate(Sender: TObject);
begin
  FStack := TVMPlotStack.Create(Self);
  FStack.Parent := pnlPlot;
  FStack.Align := alClient;
  FStack.Title := 'KdV equation - two solitons';
  FStack.XAxisTitle := 'x';
  FStack.YAxisTitle := 'u';
  FStack.ZAxisTitle := 'time';
  FStack.UseFrequencyAxis := True;    // label X in x, not grid index
  FStack.NewestAtBack := True;        // t = 0 in front (the default anyway)
  FStack.ClearStack;                  // drop the component's demo data
  SetupStack;
  WriteInfo(False);

  if Application.GetOptionValue('n') <> '' then
    seN.Value := StrToIntDef(Application.GetOptionValue('n'), seN.Value);
  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then
    Application.QueueAsyncCall(@DoSnapshot, 0)
  else
    Application.QueueAsyncCall(@DoSnapshot, 1);   // start a run on opening
end;

procedure TfmKdV.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if Assigned(FThread) then
  begin
    FThread.Terminate;
    // the thread may be waiting in Synchronize: keep serving it until
    // its OnTerminate (ThreadDone) has run and cleared FThread
    while Assigned(FThread) do CheckSynchronize(20);
  end;
  CanClose := True;
end;

procedure TfmKdV.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FModel);
end;

function TfmKdV.ParamsFromForm: TKdVParams;
begin
  Result.N := seN.Value;
  Result.L := seL.Value;
  Result.A1 := seA1.Value;
  Result.A2 := seA2.Value;
  Result.X1 := seX1.Value;
  Result.X2 := seX2.Value;
end;

procedure TfmKdV.SetupStack;
begin
  FStack.MaxSeries := seSlices.Value + 1;   // exactly the run
  FStack.ZAxisScale := seTime.Value / seSlices.Value;
  FStack.XAxisMin := -seL.Value;
  FStack.XAxisMax := seL.Value;
end;

procedure TfmKdV.SetRunning(Running: Boolean);
begin
  btnRun.Enabled := not Running;
  btnStop.Enabled := Running;
  btnReplay.Enabled := (not Running) and (Length(FProfiles) > 0);
  seA1.Enabled := not Running;
  seA2.Enabled := not Running;
  seX1.Enabled := not Running;
  seX2.Enabled := not Running;
  seL.Enabled := not Running;
  seN.Enabled := not Running;
  seTime.Enabled := not Running;
  seSlices.Enabled := not Running;
end;

procedure TfmKdV.btnRunClick(Sender: TObject);
var
  i: Integer;
begin
  if Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  FreeAndNil(FModel);
  FModel := TKdVModel.Create(ParamsFromForm);
  FInterp := FModel.InterpMatrix(DisplayPoints);
  SetLength(FXDisp, DisplayPoints);
  for i := 0 to DisplayPoints - 1 do
    FXDisp[i] := seL.Value * (-1 + 2 * i / (DisplayPoints - 1));

  SetLength(FProfiles, 0);
  SetLength(FTimes, 0);
  FStack.ClearStack;
  SetupStack;
  ProgressBar1.Position := 0;
  FStartTick := GetTickCount64;
  FSteps := 0;
  SetRunning(True);
  WriteInfo(True);

  FThread := TKdVThread.Create(Self, FModel, seTime.Value, seSlices.Value);
  FThread.OnTerminate := @ThreadDone;
  FThread.Start;
end;

procedure TfmKdV.btnStopClick(Sender: TObject);
begin
  if Assigned(FThread) then FThread.Terminate;
  tmrReplay.Enabled := False;
end;

procedure TfmKdV.ThreadDone(Sender: TObject);
begin
  FSteps := FThread.FSteps;
  FLastFlag := FThread.Flag;
  FThread := nil;                  // it frees itself (FreeOnTerminate)
  SetRunning(False);
  WriteInfo(False);
  if (FSnapshot <> '') and not Application.Terminated then
    Application.QueueAsyncCall(@DoSnapshot, 2);
end;

function TfmKdV.Display(const U: TVMobj): TVMobj;
begin
  Result := MatMult(FInterp, U);
end;

function TfmKdV.ExactDisplay(t: Double): TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(DisplayPoints, 1);
  // u = 0 at both ends, as the scheme imposes (the exact solution's tails
  // there are below 1e-9 for solitons that stay inside the domain)
  for i := 1 to DisplayPoints - 2 do
    Result[i, 0] := FModel.ExactAt(FXDisp[i], t);
end;

procedure TfmKdV.ProfileReady(const U: TVMobj; t: Double);
var
  n: Integer;
begin
  n := Length(FProfiles);
  SetLength(FProfiles, n + 1);
  SetLength(FTimes, n + 1);
  FProfiles[n] := CopyObj(U);
  FTimes[n] := t;
  ShowProfile(n);
  ProgressBar1.Position := Round(100 * t / seTime.Value);
end;

procedure TfmKdV.Progress(t: Double; Steps: Integer);
begin
  FSteps := Steps;
  ProgressBar1.Position := Round(100 * t / seTime.Value);
  if Assigned(FThread) then WriteInfo(True);
end;

procedure TfmKdV.ShowProfile(i: Integer);
begin
  FStack.AddGraph(Display(FProfiles[i]));
  // the stack holds exactly the run, so slice i is stack index i
  if cbExact.Checked and (i mod 5 = 0) then
    FStack.SetSliceOverlay(i, ExactDisplay(FTimes[i]));
end;

procedure TfmKdV.ReplotAll;
var
  i: Integer;
begin
  FStack.ClearStack;
  SetupStack;
  for i := 0 to High(FProfiles) do ShowProfile(i);
end;

procedure TfmKdV.cbExactChange(Sender: TObject);
begin
  if not Assigned(FModel) or Assigned(FThread) or tmrReplay.Enabled then Exit;
  ReplotAll;
end;

procedure TfmKdV.btnReplayClick(Sender: TObject);
begin
  if Length(FProfiles) = 0 then Exit;
  FStack.ClearStack;
  SetupStack;
  FReplayIndex := 0;
  tmrReplay.Enabled := True;
end;

procedure TfmKdV.tmrReplayTimer(Sender: TObject);
begin
  if FReplayIndex > High(FProfiles) then
  begin
    tmrReplay.Enabled := False;
    Exit;
  end;
  ShowProfile(FReplayIndex);
  Inc(FReplayIndex);
end;

procedure TfmKdV.btnResetViewClick(Sender: TObject);
begin
  FStack.ResetView;
end;

// FPC's Format has no '+' flag
function Signed(v: Double): string;
begin
  if v < 0 then Result := Format('- %.2f', [-v]) else Result := Format('+ %.2f', [v]);
end;

{ The crest of each soliton in a display profile: the overall maximum is
  the taller one; the shorter one's is the largest maximum at least two
  of the taller one's widths away (they merge into one hump while the
  taller passes through, so it may not exist). }
procedure FindCrests(const U: TVMobj; const XD: array of Double;
  Width1: Double; out C1, C2: Double; out Has2: Boolean);
var
  i, i1, i2: Integer;
  P: PDouble;
begin
  P := U.DataPtr;
  i1 := 0;
  for i := 1 to U.Rows - 1 do if P[i] > P[i1] then i1 := i;
  C1 := XD[i1];
  i2 := -1;
  for i := 1 to U.Rows - 2 do
    if (Abs(XD[i] - C1) > 2 * Width1) and (P[i] >= P[i - 1]) and (P[i] >= P[i + 1])
      and ((i2 < 0) or (P[i] > P[i2])) then i2 := i;
  Has2 := (i2 >= 0) and (P[i2] > 0.1 * P[i1]);
  if Has2 then C2 := XD[i2] else C2 := NaN;
end;

procedure TfmKdV.WriteInfo(Running: Boolean);
var
  P: TKdVParams;
  k1, k2, err, e, t, mass, c1, c2, w1: Double;
  i, j, iBig, iSmall: Integer;
  D: TVMobj;
  DP: PDouble;
  has2: Boolean;
begin
  P := ParamsFromForm;
  k1 := Sqrt(2 * P.A1);
  k2 := Sqrt(2 * P.A2);
  memInfo.Lines.BeginUpdate;
  try
    memInfo.Clear;
    memInfo.Lines.Add('Korteweg-de Vries equation');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('  u_t + 6 u u_x + u_xxx = 0');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('Two solitons, both started at t = 0:');
    memInfo.Lines.Add('  u = a sech^2(k (x - x0 - c t)/2)');
    memInfo.Lines.Add('  k = sqrt(2a), speed c = 2a');
    memInfo.Lines.Add(Format('  1: a = %.3g at x = %.3g, c = %.3g', [P.A1, P.X1, 2 * P.A1]));
    memInfo.Lines.Add(Format('  2: a = %.3g at x = %.3g, c = %.3g', [P.A2, P.X2, 2 * P.A2]));
    if (P.A1 > P.A2) = (P.X1 < P.X2) then
      memInfo.Lines.Add(Format('  meet near t = %.3g', [(P.X2 - P.X1) / (2 * (P.A1 - P.A2))]))
    else if not SameValue(P.A1, P.A2) then
      memInfo.Lines.Add('  the faster one is ahead: no collision');
    memInfo.Lines.Add('initial: exact 2-soliton solution, t = 0');
    memInfo.Lines.Add('');
    memInfo.Lines.Add(Format('Chebyshev grid, order N = %d,', [P.N]));
    memInfo.Lines.Add(Format('  x = %.3g cos(pi j/N) on -%.3g .. %.3g', [P.L, P.L, P.L]));
    memInfo.Lines.Add('  u = (1-x)^2 (1+x) q(x): u(-L) = u(L)');
    memInfo.Lines.Add('  = u_x(L) = 0 built into the basis');
    memInfo.Lines.Add('  barycentric derivatives and display');
    memInfo.Lines.Add(Format('  centre spacing %.3g, soliton 1 width %.3g',
      [P.L * Sin(Pi / P.N), 4 / k1]));
    memInfo.Lines.Add('Kaps-Rentrop, tol 1e-4, analytic Jacobian');
    memInfo.Lines.Add(Format('run to t = %.4g in %d slices', [seTime.Value, seSlices.Value]));
    memInfo.Lines.Add('');
    if Running then
      memInfo.Lines.Add(Format('Running... %d steps, %.1f s',
        [FSteps, (GetTickCount64 - FStartTick) / 1000]))
    else if Assigned(FModel) and (Length(FProfiles) > 0) then
    begin
      t := FTimes[High(FTimes)];
      case FLastFlag of
        OK: memInfo.Lines.Add(Format('Done to t = %.4g: %d steps,', [t, FSteps]));
        Abandoned: memInfo.Lines.Add(Format('Stopped at t = %.4g: %d steps,', [t, FSteps]));
      else
        memInfo.Lines.Add(Format('FAILED after t = %.4g: step collapsed', [t]));
      end;
      memInfo.Lines.Add(Format('  %d right-hand sides, %.1f s',
        [FModel.Calls, (GetTickCount64 - FStartTick) / 1000]));
      // largest difference from the exact solution, over every slice
      err := 0; iBig := 0;
      for i := 0 to High(FProfiles) do
      begin
        D := FProfiles[i] - FModel.Exact(FTimes[i]);
        DP := D.DataPtr;
        e := 0;
        for j := 0 to D.Rows - 1 do e := Max(e, Abs(DP[j]));
        if e > err then begin err := e; iBig := i; end;
      end;
      memInfo.Lines.Add(Format('  max |u - exact| %.2g (t = %.3g)', [err, FTimes[iBig]]));
      memInfo.Lines.Add(Format('  at the end %.2g', [e]));
      // mass, by the trapezium rule on the display grid
      D := Display(FProfiles[High(FProfiles)]);
      DP := D.DataPtr;
      mass := 0;
      for i := 1 to DisplayPoints - 1 do
        mass := mass + 0.5 * (DP[i] + DP[i - 1]) * (FXDisp[i] - FXDisp[i - 1]);
      memInfo.Lines.Add(Format('  mass %.5f (exact 2(k1+k2) = %.5f)', [mass, FModel.Mass]));
      // crests against free motion
      w1 := 2 / Max(k1, k2);
      FindCrests(D, FXDisp, w1, c1, c2, has2);
      if P.A1 >= P.A2 then begin iBig := 1; iSmall := 2; end
      else begin iBig := 2; iSmall := 1; end;
      memInfo.Lines.Add('');
      memInfo.Lines.Add(Format('Crests at t = %.3g (free motion + shift):', [t]));
      memInfo.Lines.Add(Format('  taller  x = %.2f, expected %.2f %s',
        [c1, FModel.FreeCrest(iBig, t), Signed(FModel.PhaseShift(iBig))]));
      if has2 then
        memInfo.Lines.Add(Format('  shorter x = %.2f, expected %.2f %s',
          [c2, FModel.FreeCrest(iSmall, t), Signed(FModel.PhaseShift(iSmall))]))
      else
        memInfo.Lines.Add('  shorter: merged with the taller');
      memInfo.Lines.Add('  (the shift applies once they have passed)');
      if FModel.FreeCrest(iBig, t) + FModel.PhaseShift(iBig) > P.L - 2 * w1 then
        memInfo.Lines.Add('  the taller one has reached the boundary');
    end;
    memInfo.Lines.Add('');
    memInfo.Lines.Add('t = 0 at the front, later times behind.');
    if cbExact.Checked then
      memInfo.Lines.Add('White: the exact solution, every 5th slice.');
    memInfo.Lines.Add('Drag to rotate, wheel to zoom.');
  finally
    memInfo.Lines.EndUpdate;
  end;
end;

procedure TfmKdV.DoSnapshot(Data: PtrInt);
begin
  case Data of
    0, 1: btnRunClick(nil);
    2:
      begin
        Application.ProcessMessages;
        with GetFormImage do
        try
          SaveToFile(FSnapshot + '.bmp');
        finally
          Free;
        end;
        WriteLn(memInfo.Lines.Text);
        Application.Terminate;
      end;
  end;
end;

end.
