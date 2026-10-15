unit ubenneymain;

{*******************************************************************************

     Main form for the Benney demo: numerical solution of the 1-D Benney
     equation for a liquid film on an inclined plane (see ubenneymodel),
     integrated with the Kaps-Rentrop stiff solver (see ukapsrentrop),
     drawn as a waterfall on a TVMPlotStack - one ribbon per output time,
     t = 0 at the front and each later time one step further back
     (TVMPlotStack.NewestAtBack), so travelling waves show as diagonal ridges
     running back through the stack.

     The FPC/newVM port of the Delphi project Benney/prjkapstest
     (ukapsmain.pas, MtxVec + TeeChart): there the run went into a
     System.Threading task and the result was animated afterwards, one
     profile at a time, on a TLineSeries. Here:
       - A TThread (TBenneyThread) runs the integration and hands each
         profile to the form as soon as its output time is reached, so
         the stack builds up live; "Replay" re-adds the stored profiles
         one per timer tick, the equivalent of the original's "Plot".
       - The run is split into equal output intervals (Slices spin edit)
         with one OdeInt call each, rather than recording every accepted
         step, so the stack's depth axis is uniform in time.
       - The parameters the original fixed as constants (Re, We, eps,
         the inclination, the run time) are spin edits, defaulting to its
         values - We 250, eps 0.04, theta = pi/10 (18 deg), 30 time
         units, N = 512 points on -100 .. 100, a 0.2 bump at x = -85 -
         except Re, 3 rather than its 5, and the domain: "length" sets
         L (default 400, x on -200 .. 200) with the original's grid
         spacing kept (N = 2.56 L, so 1024 points), and the bump sits 15
         in from the left boundary, so a wave can travel further. With derivatives scaled by the
         domain length (ubenneymodel, ScaleByLength) Re 5 blows up at
         t ~ 3.5 - a genuine finite-time blow-up of the Benney equation,
         the same time at N = 512 and 1024 in scipy, h passing 100 - while
         Re 3, still above the instability threshold (5/6 cot theta =
         2.56), runs to t = 30 with the bump growing into waves.
       - "Plot h - h0" (default on) draws the departure from the flat
         film: the waves here are a few per cent of h, invisible on
         ribbons drawn from h = 0.
       - "start:" picks the initial condition: the original's Gaussian
         bump, or the exact solitary wave for the chosen Re
         (TBenneyModel.SolitaryWave, solved on the worker thread before
         the integration). From the solitary wave every slice carries
         that wave moved to x - c t as a white overlay
         (TVMPlotStack.SetSliceOverlay), and the memo reports how far
         the integration has drifted from it - a check on both
         calculations, until the unstable flat film's own growth (the
         film is unstable for Re > 2.56) eventually disturbs it.
     Stop sets the thread's Terminated flag, which the per-step callback
     turns into OdeInt's Stop - the original's Abandon flag.

     --snapshot=<prefix>: run with the defaults, save the window as
     <prefix>.bmp, print the memo and exit. --start=solitary starts from
     the solitary wave, --re=<value> sets Re (with or without snapshot).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, uVMPlotStack, ukapsrentrop, ubenneymodel;

type
  TfmBenney = class;

  { The integration, off the GUI thread }
  TBenneyThread = class(TThread)
  private
    FForm: TfmBenney;
    FModel: TBenneyModel;
    FTotalTime: Double;
    FSlices: Integer;
    // handed to the form through Synchronize
    FProfile: TVMobj;
    FTime: Double;
    FSteps: Integer;
    FSolitary: Boolean;
    FStatus: string;
    FLastReport: QWord;
    procedure SWProgress(const S: string);
    procedure PostStatus;
    procedure Step(x: Double; var Stop: Boolean);
    procedure PostProfile;
    procedure PostProgress;
  protected
    procedure Execute; override;
  public
    Flag: TErrFlags;
    // the solitary wave, when starting from one
    SolOK: Boolean;
    SolH: TVMobj;
    SolC, SolAmp, SolWidth: Double;
    SolX0: Double;                 // where its crest starts
    SolMsg: string;
    constructor Create(AForm: TfmBenney; AModel: TBenneyModel;
      ATotalTime: Double; ASlices: Integer; ASolitary: Boolean);
  end;

  { TfmBenney }

  TfmBenney = class(TForm)
    btnRun: TButton;
    btnStop: TButton;
    btnReplay: TButton;
    btnResetView: TButton;
    cbDeviation: TCheckBox;
    lblRe: TLabel;
    lblWe: TLabel;
    lblTheta: TLabel;
    lblEps: TLabel;
    lblTime: TLabel;
    lblSlices: TLabel;
    lblStart: TLabel;
    cbStart: TComboBox;
    memInfo: TMemo;
    pnlControls: TPanel;
    pnlPlot: TPanel;
    ProgressBar1: TProgressBar;
    seRe: TFloatSpinEdit;
    seWe: TFloatSpinEdit;
    seTheta: TFloatSpinEdit;
    seEps: TFloatSpinEdit;
    seTime: TFloatSpinEdit;
    seSlices: TSpinEdit;
    lblLength: TLabel;
    seLength: TSpinEdit;
    tmrReplay: TTimer;
    procedure btnReplayClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure cbDeviationChange(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure tmrReplayTimer(Sender: TObject);
  private
    FStack: TVMPlotStack;
    FModel: TBenneyModel;
    FThread: TBenneyThread;
    FProfiles: array of TVMobj;   // h at each output time
    FTimes: array of Double;
    FReplayIndex: Integer;
    FStartTick: QWord;
    FSnapshot: string;
    FLastFlag: TErrFlags;          // how the last run ended
    FStatusText: string;           // progress line while running
    // the solitary wave of the last run, if it started from one
    FSolValid: Boolean;
    FSolH: TVMobj;
    FSolC, FSolAmp, FSolWidth, FSolX0: Double;
    FSolMsg: string;
    FSolTried: Boolean;
    function OverlayAt(i: Integer): TVMobj;
    procedure ApplyLength(var P: TBenneyParams);
    procedure ThreadDone(Sender: TObject);
    procedure SetupStack;
    procedure ShowProfile(i: Integer);
    procedure ReplotAll;
    procedure WriteInfo(Running: Boolean; Steps: Integer);
    procedure DoSnapshot(Data: PtrInt);
    procedure SetRunning(Running: Boolean);
  public
    // called by the thread, through Synchronize
    procedure ProfileReady(const H: TVMobj; t: Double);
    procedure Status(const S: string);
    procedure Progress(t: Double; Steps: Integer);
  end;

var
  fmBenney: TfmBenney;

implementation

{$R *.lfm}

const
  Tolerance = 1e-3;      // the original's err
  FirstStep = 1e-5;      // and its h1
  MinStep = 0.0;         // and hmin

// largest |element| of a vector
function MaxAbs(const A: TVMobj): Double;
var
  i: Integer;
  P: PDouble;
begin
  Result := 0;
  P := A.DataPtr;
  for i := 0 to A.Rows * A.Cols - 1 do Result := Max(Result, Abs(P[i]));
end;

{ TBenneyThread }

constructor TBenneyThread.Create(AForm: TfmBenney; AModel: TBenneyModel;
  ATotalTime: Double; ASlices: Integer; ASolitary: Boolean);
begin
  FSolitary := ASolitary;
  FForm := AForm;
  FModel := AModel;
  FTotalTime := ATotalTime;
  FSlices := ASlices;
  FreeOnTerminate := True;     // OnTerminate (ThreadDone) drops the form's reference
  inherited Create(True);
end;

procedure TBenneyThread.Step(x: Double; var Stop: Boolean);
begin
  Inc(FSteps);
  FTime := x;
  // a step takes ~50 ms (the Jacobian is 2N right-hand sides), but
  // report no more than every 100 ms anyway
  if GetTickCount64 - FLastReport >= 100 then
  begin
    FLastReport := GetTickCount64;
    Synchronize(@PostProgress);
  end;
  Stop := Terminated;
end;

procedure TBenneyThread.SWProgress(const S: string);
begin
  FStatus := S;
  Synchronize(@PostStatus);
end;

procedure TBenneyThread.PostStatus;
begin
  FForm.Status(FStatus);
end;

procedure TBenneyThread.PostProfile;
begin
  FForm.ProfileReady(FProfile, FTime);
end;

procedure TBenneyThread.PostProgress;
begin
  FForm.Progress(FTime, FSteps);
end;

procedure TBenneyThread.Execute;
var
  y: TVMobj;
  k: Integer;
  h, t0, t1: Double;
begin
  Flag := OK;
  if FSolitary then
  begin
    FStatus := 'solving for the solitary wave...';
    Synchronize(@PostStatus);
    SolOK := FModel.SolitaryWave(SolH, SolC, SolAmp, SolWidth, SolMsg, @SWProgress);
    if not SolOK then Exit;          // ThreadDone reports SolMsg
    // SolitaryWave puts the crest at x = 0; start it near the left
    // boundary instead, a width (at least 15) in, so it has nearly the
    // whole domain to travel through. Shift is periodic, so the
    // tail ahead of the crest simply wraps round.
    SolX0 := -FModel.Params.Ax + Max(15, SolWidth);
    SolH := FModel.Shift(SolH, SolX0);
    y := CopyObj(SolH);
  end
  else
    y := FModel.InitialProfile;
  FProfile := CopyObj(y);
  FTime := 0;
  Synchronize(@PostProfile);
  h := FirstStep;
  Flag := OK;
  for k := 1 to FSlices do
  begin
    t0 := FTotalTime * (k - 1) / FSlices;
    t1 := FTotalTime * k / FSlices;
    Flag := OdeInt(y, t0, t1, Tolerance, h, MinStep,
      @FModel.Derivs, @FModel.Jacobn, @Step, h);
    if Flag <> OK then Break;
    FProfile := CopyObj(y);
    FTime := t1;
    Synchronize(@PostProfile);
  end;
  Synchronize(@PostProgress);
end;

{ TfmBenney }

procedure TfmBenney.FormCreate(Sender: TObject);
begin
  FStack := TVMPlotStack.Create(Self);
  FStack.Parent := pnlPlot;
  FStack.Align := alClient;
  FStack.Title := 'Benney equation - film on an inclined plane';
  FStack.XAxisTitle := 'x';
  FStack.UseFrequencyAxis := True;    // label X in x, not grid index
  FStack.NewestAtBack := True;        // t = 0 stays in front, later times go behind
  FStack.XAxisMin := -seLength.Value / 2;
  FStack.XAxisMax := seLength.Value / 2;
  FStack.ClearStack;                  // drop the component's demo data
  SetupStack;
  WriteInfo(False, 0);

  if Application.GetOptionValue('start') = 'solitary' then cbStart.ItemIndex := 1;
  if Application.GetOptionValue('re') <> '' then
    seRe.Value := StrToFloatDef(Application.GetOptionValue('re'), seRe.Value);
  if Application.GetOptionValue('length') <> '' then
    seLength.Value := StrToIntDef(Application.GetOptionValue('length'), seLength.Value);
  if Application.GetOptionValue('time') <> '' then
    seTime.Value := StrToFloatDef(Application.GetOptionValue('time'), seTime.Value);
  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then
    Application.QueueAsyncCall(@DoSnapshot, 0)
  else
    Application.QueueAsyncCall(@DoSnapshot, 1);   // start a run on opening
end;

procedure TfmBenney.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
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

procedure TfmBenney.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FModel);              // FormCloseQuery has seen the thread out
end;

procedure TfmBenney.SetupStack;
var
  n: Integer;
begin
  n := seSlices.Value + 1;
  // exactly the run: t = 0 sits at the back of the box (the stack no
  // longer fades with age - FadeWithAge is off by default)
  FStack.MaxSeries := n;
  FStack.ZAxisScale := seTime.Value / seSlices.Value;    // depth axis in time
  FStack.ZAxisTitle := 'time';
  if cbDeviation.Checked then
    FStack.YAxisTitle := 'h - h0'
  else
    FStack.YAxisTitle := 'h';
end;

procedure TfmBenney.SetRunning(Running: Boolean);
begin
  btnRun.Enabled := not Running;
  btnStop.Enabled := Running;
  btnReplay.Enabled := (not Running) and (Length(FProfiles) > 0);
  seRe.Enabled := not Running;
  seWe.Enabled := not Running;
  seTheta.Enabled := not Running;
  seEps.Enabled := not Running;
  seTime.Enabled := not Running;
  seSlices.Enabled := not Running;
  seLength.Enabled := not Running;
end;

procedure TfmBenney.btnRunClick(Sender: TObject);
var
  P: TBenneyParams;
begin
  if Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  P := DefaultBenneyParams;
  P.Re := seRe.Value;
  P.We := seWe.Value;
  P.Theta := DegToRad(seTheta.Value);
  P.Eps := seEps.Value;
  ApplyLength(P);
  FreeAndNil(FModel);
  FModel := TBenneyModel.Create(P);
  FStack.XAxisMin := -P.Ax;
  FStack.XAxisMax := P.Ax;

  SetLength(FProfiles, 0);
  SetLength(FTimes, 0);
  FStack.ClearStack;
  SetupStack;
  ProgressBar1.Position := 0;
  FStartTick := GetTickCount64;
  SetRunning(True);
  WriteInfo(True, 0);

  FSolTried := cbStart.ItemIndex = 1;
  FSolValid := False;
  FStatusText := '';
  FThread := TBenneyThread.Create(Self, FModel, seTime.Value, seSlices.Value, FSolTried);
  FThread.OnTerminate := @ThreadDone;
  FThread.Start;
end;

procedure TfmBenney.btnStopClick(Sender: TObject);
begin
  if Assigned(FThread) then FThread.Terminate;
  tmrReplay.Enabled := False;
end;

procedure TfmBenney.ThreadDone(Sender: TObject);
var
  Steps: Integer;
begin
  Steps := FThread.FSteps;
  FLastFlag := FThread.Flag;       // reported by WriteInfo
  if FSolTried then
  begin
    FSolMsg := FThread.SolMsg;
    FSolValid := FThread.SolOK;
  end;
  // OnTerminate runs in the main thread just before the thread frees
  // itself (FreeOnTerminate)
  FThread := nil;
  SetRunning(False);
  WriteInfo(False, Steps);
  if (FSnapshot <> '') and not Application.Terminated then
    Application.QueueAsyncCall(@DoSnapshot, 2);
end;

procedure TfmBenney.Status(const S: string);
begin
  FStatusText := S;
  // the wave is known as soon as the integration starts sending profiles
  if Assigned(FThread) and FThread.SolOK and not FSolValid then
  begin
    FSolValid := True;
    FSolH := CopyObj(FThread.SolH);
    FSolC := FThread.SolC;
    FSolAmp := FThread.SolAmp;
    FSolWidth := FThread.SolWidth;
    FSolX0 := FThread.SolX0;
  end;
  if Assigned(FThread) then WriteInfo(True, FThread.FSteps);
end;

{ The domain is -L/2 .. L/2 for the "length" L, with the original's
  grid spacing (512 points on 200) kept: N = 2.56 L, rounded to even.
  The Jacobian is dense (spectral derivatives), so a step costs about
  (N/512)^2 .. ^3 the original's: L = 400 is roughly 4-8x slower. }
procedure TfmBenney.ApplyLength(var P: TBenneyParams);
begin
  P.Ax := seLength.Value / 2;
  P.N := 2 * Round(1.28 * seLength.Value);
end;

function TfmBenney.OverlayAt(i: Integer): TVMobj;
begin
  Result := FModel.Shift(FSolH, FSolC * FTimes[i]);
end;

procedure TfmBenney.ProfileReady(const H: TVMobj; t: Double);
var
  n: Integer;
begin
  if Assigned(FThread) and FThread.SolOK and not FSolValid then
  begin
    FSolValid := True;
    FSolH := CopyObj(FThread.SolH);
    FSolC := FThread.SolC;
    FSolAmp := FThread.SolAmp;
    FSolWidth := FThread.SolWidth;
    FSolX0 := FThread.SolX0;
  end;
  n := Length(FProfiles);
  SetLength(FProfiles, n + 1);
  SetLength(FTimes, n + 1);
  FProfiles[n] := CopyObj(H);
  FTimes[n] := t;
  ShowProfile(n);
  ProgressBar1.Position := Round(100 * t / seTime.Value);
end;

procedure TfmBenney.Progress(t: Double; Steps: Integer);
begin
  ProgressBar1.Position := Round(100 * t / seTime.Value);
  if Assigned(FThread) then WriteInfo(True, Steps);
end;

procedure TfmBenney.ShowProfile(i: Integer);
begin
  if cbDeviation.Checked then
    FStack.AddGraph(AddScalar(FProfiles[i], -FModel.Params.h0))
  else
    FStack.AddGraph(FProfiles[i]);
  // the solitary wave at this slice's time, as a white line over every
  // fifth slice (on all of them it hid the ribbons); the stack holds
  // exactly the run (MaxSeries = slices + 1), so slice i is stack index i
  if FSolValid and (i mod 5 = 0) then
    if cbDeviation.Checked then
      FStack.SetSliceOverlay(i, AddScalar(OverlayAt(i), -FModel.Params.h0))
    else
      FStack.SetSliceOverlay(i, OverlayAt(i));
end;

procedure TfmBenney.ReplotAll;
var
  i: Integer;
begin
  FStack.ClearStack;
  SetupStack;
  for i := 0 to High(FProfiles) do ShowProfile(i);
end;

procedure TfmBenney.cbDeviationChange(Sender: TObject);
begin
  if not Assigned(FModel) then Exit;
  if tmrReplay.Enabled then Exit;      // the replay picks it up as it goes
  ReplotAll;
end;

procedure TfmBenney.btnReplayClick(Sender: TObject);
begin
  if Length(FProfiles) = 0 then Exit;
  FStack.ClearStack;
  SetupStack;
  FReplayIndex := 0;
  tmrReplay.Enabled := True;
end;

procedure TfmBenney.tmrReplayTimer(Sender: TObject);
begin
  if FReplayIndex > High(FProfiles) then
  begin
    tmrReplay.Enabled := False;
    Exit;
  end;
  ShowProfile(FReplayIndex);
  Inc(FReplayIndex);
end;

procedure TfmBenney.btnResetViewClick(Sender: TObject);
begin
  FStack.ResetView;
end;

procedure TfmBenney.WriteInfo(Running: Boolean; Steps: Integer);
var
  P: TBenneyParams;
  Rc, mn, mx, xmax: Double;
  i, im: Integer;
  YP: PDouble;
begin
  P := DefaultBenneyParams;
  P.Re := seRe.Value;
  P.We := seWe.Value;
  P.Theta := DegToRad(seTheta.Value);
  P.Eps := seEps.Value;
  ApplyLength(P);
  Rc := 5 / 6 / Tan(P.Theta);
  memInfo.Lines.BeginUpdate;
  try
    memInfo.Clear;
    memInfo.Lines.Add('1-D Benney equation');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('h_t + h^2 h_x + eps [ (2/5 Re h^6');
    memInfo.Lines.Add('  - cot(theta)/3 h^3) h_x');
    memInfo.Lines.Add('  + We eps^2/3 h^3 h_xxx ]_x = 0');
    memInfo.Lines.Add('');
    memInfo.Lines.Add(Format('Re %.4g   We %.4g   eps %.4g', [P.Re, P.We, P.Eps]));
    memInfo.Lines.Add(Format('theta %.4g deg (cot %.4g)', [seTheta.Value, 1 / Tan(P.Theta)]));
    memInfo.Lines.Add(Format('flat film unstable for Re > %.3g:', [Rc]));
    if P.Re > Rc then
      memInfo.Lines.Add('  unstable here - waves grow')
    else
      memInfo.Lines.Add('  stable here - the bump decays');
    memInfo.Lines.Add('');
    memInfo.Lines.Add(Format('N = %d, periodic on x = %.0f .. %.0f', [P.N, -P.Ax, P.Ax]));
    if cbStart.ItemIndex = 1 then
      memInfo.Lines.Add('initial: the solitary wave at this Re')
    else
      memInfo.Lines.Add(Format('initial: h0 = 1 plus a 0.2 bump at x = %.0f', [15 - P.Ax]));
    memInfo.Lines.Add('spectral derivatives (FFT_R2C/FFT_C2R)');
    memInfo.Lines.Add('Kaps-Rentrop stiff integrator, tol 1e-3,');
    memInfo.Lines.Add('Jacobian by central differences');
    memInfo.Lines.Add(Format('run to t = %.4g in %d slices', [seTime.Value, seSlices.Value]));
    memInfo.Lines.Add('');
    if FSolValid then
    begin
      memInfo.Lines.Add('Solitary wave (white overlay):');
      memInfo.Lines.Add(Format('  height %.4g above the film', [FSolAmp]));
      memInfo.Lines.Add(Format('  speed c = %.5g, width %.3g', [FSolC, FSolWidth]));
      memInfo.Lines.Add(Format('  crest starts at x = %.3g', [FSolX0]));
      memInfo.Lines.Add('  (flat film 1 far away; F(H) - cH = q)');
    end
    else if FSolTried and (FSolMsg <> '') and not Running then
    begin
      memInfo.Lines.Add('Solitary wave: ' + FSolMsg);
      memInfo.Lines.Add('  - nothing to integrate. Solitary waves');
      memInfo.Lines.Add('  exist for about 2.6 < Re < 5.6 here.');
    end;
    if FSolValid or (FSolTried and Running) then memInfo.Lines.Add('');
    if Running then
    begin
      if FStatusText <> '' then memInfo.Lines.Add(FStatusText);
      memInfo.Lines.Add(Format('Running... %d steps, %.1f s', [Steps, (GetTickCount64 - FStartTick) / 1000]));
    end
    else if Assigned(FModel) and (Length(FProfiles) > 0) then
    begin
      case FLastFlag of
        OK: memInfo.Lines.Add(Format('Done to t = %.4g: %d steps,', [FTimes[High(FTimes)], Steps]));
        Abandoned: memInfo.Lines.Add(Format('Stopped at t = %.4g: %d steps,', [FTimes[High(FTimes)], Steps]));
      else
        begin
          // the step size collapsed: at strong instability the Benney
          // equation itself blows up in finite time
          memInfo.Lines.Add(Format('FAILED after t = %.4g: the step size', [FTimes[High(FTimes)]]));
          memInfo.Lines.Add('  collapsed - the solution is blowing up');
          memInfo.Lines.Add('  (try a lower Re or a smaller bump).');
          memInfo.Lines.Add(Format('  %d steps,', [Steps]));
        end;
      end;
      memInfo.Lines.Add(Format('  %d right-hand sides, %.1f s', [FModel.Calls, (GetTickCount64 - FStartTick) / 1000]));
      YP := FProfiles[High(FProfiles)].DataPtr;
      mn := YP[0]; mx := YP[0]; im := 0;
      for i := 1 to FModel.Params.N - 1 do
      begin
        if YP[i] < mn then mn := YP[i];
        if YP[i] > mx then begin mx := YP[i]; im := i; end;
      end;
      xmax := FModel.X[im, 0];
      memInfo.Lines.Add(Format('  final h %.4f .. %.4f,', [mn, mx]));
      memInfo.Lines.Add(Format('  crest at x = %.1f', [xmax]));
      if FSolValid then
        memInfo.Lines.Add(Format('  max |h - H(x - c t)| = %.2g', [MaxAbs(FProfiles[High(FProfiles)] - OverlayAt(High(FProfiles)))]));
    end;
    memInfo.Lines.Add('');
    memInfo.Lines.Add('t = 0 at the front, later times behind.');
    memInfo.Lines.Add('Drag to rotate, wheel to zoom.');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('Derivatives are true d/dx: wavenumbers');
    memInfo.Lines.Add(Format('2 pi n/L, L = %d. The original used n', [seLength.Value]));
    memInfo.Lines.Add('(a 2 pi domain) - ScaleByLength False.');
  finally
    memInfo.Lines.EndUpdate;
  end;
end;

procedure TfmBenney.DoSnapshot(Data: PtrInt);
begin
  case Data of
    1: btnRunClick(nil);                 // normal start: run once
    0: btnRunClick(nil);                 // snapshot: run, then case 2
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
