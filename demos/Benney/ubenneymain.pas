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
         values: Re 5, We 250, eps 0.04, theta = pi/10 (18 deg), 30 time
         units, N = 512 points on -100 .. 100, a 0.2 bump at x = -85.
       - "Plot h - h0" (default on) draws the departure from the flat
         film: the waves here are a few per cent of h, invisible on
         ribbons drawn from h = 0.
     Stop sets the thread's Terminated flag, which the per-step callback
     turns into OdeInt's Stop - the original's Abandon flag.

     --snapshot=<prefix>: run with the defaults, save the window as
     <prefix>.bmp, print the memo and exit.

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
    FLastReport: QWord;
    procedure Step(x: Double; var Stop: Boolean);
    procedure PostProfile;
    procedure PostProgress;
  protected
    procedure Execute; override;
  public
    Flag: TErrFlags;
    constructor Create(AForm: TfmBenney; AModel: TBenneyModel;
      ATotalTime: Double; ASlices: Integer);
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

{ TBenneyThread }

constructor TBenneyThread.Create(AForm: TfmBenney; AModel: TBenneyModel;
  ATotalTime: Double; ASlices: Integer);
begin
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
  FStack.XAxisMin := -100;
  FStack.XAxisMax := 100;
  FStack.ClearStack;                  // drop the component's demo data
  SetupStack;
  WriteInfo(False, 0);

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
  FreeAndNil(FModel);
  FModel := TBenneyModel.Create(P);

  SetLength(FProfiles, 0);
  SetLength(FTimes, 0);
  FStack.ClearStack;
  SetupStack;
  ProgressBar1.Position := 0;
  FStartTick := GetTickCount64;
  SetRunning(True);
  WriteInfo(True, 0);

  FThread := TBenneyThread.Create(Self, FModel, seTime.Value, seSlices.Value);
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
  case FThread.Flag of
    TooManySteps: memInfo.Lines.Add('Stopped: too many steps');
    TooShortStep: memInfo.Lines.Add('Stopped: step size below the minimum');
  end;
  // OnTerminate runs in the main thread just before the thread frees
  // itself (FreeOnTerminate)
  FThread := nil;
  SetRunning(False);
  WriteInfo(False, Steps);
  if (FSnapshot <> '') and not Application.Terminated then
    Application.QueueAsyncCall(@DoSnapshot, 2);
end;

procedure TfmBenney.ProfileReady(const H: TVMobj; t: Double);
var
  n: Integer;
begin
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
    memInfo.Lines.Add('initial: h0 = 1 plus a 0.2 bump at x = -85');
    memInfo.Lines.Add('spectral derivatives (FFT_R2C/FFT_C2R)');
    memInfo.Lines.Add('Kaps-Rentrop stiff integrator, tol 1e-3,');
    memInfo.Lines.Add('Jacobian by central differences');
    memInfo.Lines.Add(Format('run to t = %.4g in %d slices', [seTime.Value, seSlices.Value]));
    memInfo.Lines.Add('');
    if Running then
      memInfo.Lines.Add(Format('Running... %d steps, %.1f s', [Steps, (GetTickCount64 - FStartTick) / 1000]))
    else if Assigned(FModel) and (Length(FProfiles) > 0) then
    begin
      memInfo.Lines.Add(Format('Done to t = %.4g: %d steps,', [FTimes[High(FTimes)], Steps]));
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
    end;
    memInfo.Lines.Add('');
    memInfo.Lines.Add('t = 0 at the front, later times behind.');
    memInfo.Lines.Add('Drag to rotate, wheel to zoom.');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('Note: like the original, derivatives');
    memInfo.Lines.Add('use integer wavenumbers - the domain');
    memInfo.Lines.Add('acts as 2 pi long (see ubenneymodel).');
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
