unit ubenney2dmain;

{*******************************************************************************

     Benney2D - a thin water film falling down an inclined plate, in two
     dimensions: the 2-D Benney equation (ubenney2dmodel.pas) on a
     Fourier (down the slope, periodic) x Chebyshev (across the plate,
     no-flux side walls) grid, stepped semi-implicitly, with the x and y
     derivatives of each right-hand side on two threads.

     Display:
       - left, a TVMPlot3D surface of the film's departure from the flat
         film, h - hN in micrometres, x down the slope and y across,
         updated as each output time is reached. The Chebyshev rows are
         interpolated onto equally spaced y (TVMPlot3D assumes an even
         grid). The surface keeps the plate's proportions: x and y to
         scale (TVMPlot3D.EqualAspect), and heights at a fixed vertical
         exaggeration, "height x" (default 5000; TVMPlot3D.ZExaggeration,
         with the 1e-3 for um over mm). The box is +-1/10 of the plate's
         longer side at that exaggeration - 6 um for 300 mm at 5000 x -
         the same for every frame, so frames compare directly; taller
         waves poke out of it. (Before this each frame was scaled to its
         own largest departure, which hid how the waves grew.)
       - right, the centre line y = 0 as a waterfall (TVMPlotStack, the
         1-D demo's picture), t = 0 in front.
       - after a run, Replay animates the surface again and the slider
         picks any frame.

     The defaults are 0.2 mm of water on an 11.2 deg plate 300 mm wide,
     300 mm periodic down the slope: Re 5.1, 1.2 x the onset of waves.
     A thicker film (or a steeper plate) takes the Benney equation out
     of its range and it blows up - see ubenney2dmodel.pas; the memo
     warns before a run.

     Excitation: "excite at x = 0" adds a line source across the plate
     at x = 0, a c cos(2 pi t/T) g(x) (ubenney2dmodel.pas), launching a
     wave train of thickness amplitude a (um here) and wavelength c T.
     "transverse (%)" and "half-waves" modulate it across the plate,
     1 + m cos(n pi (y + W/2)/W), seeding the 3-D structure a uniform
     source can't (default 10 %, n = 2).
     "Flat film" as the start shows it alone. The domain is periodic, so
     the train comes round to x = 0 after Lx/c (about 4 s by default) -
     unless "absorbing zone" is ticked: a smooth damping zone (length
     and peak rate set beside it) just before x = Lx relaxes the film
     to flat, so waves leave the domain and x = 0 acts as an inlet.

     Command line, for unattended checks: --snapshot=<prefix> runs,
     saves <prefix>.bmp (the window) and prints the memo; --time=<s>,
     --film=<mm>, --angle=<deg>, --serial (no derivative thread),
     --excite, --period=<s>, --amp=<um>, --mod=<%>, --modn=<n>,
     --absorb, --length=<mm>,
     --width=<mm>, --exag=<x> and --start=<0..3> (the start
     list's index) set the run.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, uVMPlot3D, uVMPlotStack, ubenney2dmodel;

type
  TfmBenney2D = class;

  { The integration, off the GUI thread }
  TBenney2DThread = class(TThread)
  private
    FForm: TfmBenney2D;
    FModel: TBenney2DModel;
    FH0: TVMobj;
    FTotalTime: Double;
    FFrames: Integer;
    FLastReport: QWord;
    // handed to the form through Synchronize
    FFrame: TVMobj;
    FFrameTime: Double;
    procedure PostFrame;
    procedure PostProgress;
  protected
    procedure Execute; override;
  public
    Failed: Boolean;
    FailMsg: string;
    constructor Create(AForm: TfmBenney2D; AModel: TBenney2DModel;
      const H0: TVMobj; ATotalTime: Double; AFrames: Integer);
  end;

  { TfmBenney2D }

  TfmBenney2D = class(TForm)
    btnRun: TButton;
    btnStop: TButton;
    btnReplay: TButton;
    btnResetView: TButton;
    cbThreads: TCheckBox;
    cbExcite: TCheckBox;
    lblPeriod: TLabel;
    lblAmp: TLabel;
    lblExcite: TLabel;
    sePeriod: TFloatSpinEdit;
    cbAbsorb: TCheckBox;
    lblZone: TLabel;
    lblRate: TLabel;
    seZone: TSpinEdit;
    seRate: TFloatSpinEdit;
    lblMod: TLabel;
    lblModN: TLabel;
    seMod: TFloatSpinEdit;
    seModN: TSpinEdit;
    lblExag: TLabel;
    seExag: TSpinEdit;
    seAmp: TFloatSpinEdit;
    cbStart: TComboBox;
    lblFilm: TLabel;
    lblAngle: TLabel;
    lblWidth: TLabel;
    lblLength: TLabel;
    lblNx: TLabel;
    lblNy: TLabel;
    lblTime: TLabel;
    lblFrames: TLabel;
    lblStart: TLabel;
    lblFrame: TLabel;
    memInfo: TMemo;
    pnlControls: TPanel;
    pnlPlot: TPanel;
    pnlRight: TPanel;
    ProgressBar1: TProgressBar;
    seFilm: TFloatSpinEdit;
    seAngle: TFloatSpinEdit;
    seWidth: TSpinEdit;
    seLength: TSpinEdit;
    seNx: TSpinEdit;
    seNy: TSpinEdit;
    seTime: TFloatSpinEdit;
    seFrames: TSpinEdit;
    tbFrame: TTrackBar;
    tmrReplay: TTimer;
    procedure btnReplayClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ParamChange(Sender: TObject);
    procedure seExagChange(Sender: TObject);
    procedure pnlRightResize(Sender: TObject);
    procedure tbFrameChange(Sender: TObject);
    procedure tmrReplayTimer(Sender: TObject);
  private
    FSurface: TVMPlot3D;
    FStack: TVMPlotStack;
    FModel: TBenney2DModel;
    FThread: TBenney2DThread;
    FInterp: TVMobj;                 // Chebyshev rows -> uniform rows
    FFrames: array of TVMobj;        // h - hN in um, (Nyd, Nx)
    FTimes: array of Double;
    FZBox: Double;                   // the surface box's half-height, um
    FShown: Integer;                 // the frame on the surface
    FReplayIndex: Integer;
    FStartTick: QWord;
    FSnapshot: string;
    FFailed: Boolean;
    FFailMsg: string;
    FRunTime: Double;                // wall time of the last run
    FUpdatingSlider: Boolean;
    function ReadParams: TBenney2DParams;
    procedure ApplyScale;
    procedure ThreadDone(Sender: TObject);
    procedure ShowFrame(i: Integer);
    procedure WriteInfo(Running: Boolean);
    procedure DoSnapshot(Data: PtrInt);
    procedure SetRunning(Running: Boolean);
  public
    // called by the thread, through Synchronize
    procedure FrameReady(const H: TVMobj; t: Double);
    procedure Progress;
  end;

var
  fmBenney2D: TfmBenney2D;

implementation

{$R *.lfm}

const
  FirstStep = 1e-3;        // s; the error control takes it from there
  DisplayRows = 101;       // uniform y rows on the surface

{ TBenney2DThread }

constructor TBenney2DThread.Create(AForm: TfmBenney2D; AModel: TBenney2DModel;
  const H0: TVMobj; ATotalTime: Double; AFrames: Integer);
begin
  FForm := AForm;
  FModel := AModel;
  FH0 := CopyObj(H0);
  FTotalTime := ATotalTime;
  FFrames := AFrames;
  FreeOnTerminate := True;      // OnTerminate (ThreadDone) drops the form's reference
  inherited Create(False);
end;

procedure TBenney2DThread.PostFrame;
begin
  FForm.FrameReady(FFrame, FFrameTime);
end;

procedure TBenney2DThread.PostProgress;
begin
  FForm.Progress;
end;

procedure TBenney2DThread.Execute;
var
  k: Integer;
  tk, tPrev, f: Double;
  HPrev: TVMobj;
  Msg: string;
begin
  try
    FModel.Start(FH0, FirstStep);
    FFrame := FH0;
    FFrameTime := 0;
    Synchronize(@PostFrame);
    k := 1;
    tPrev := FModel.Time;
    HPrev := FModel.H;
    while (k <= FFrames) and not Terminated do
    begin
      tPrev := FModel.Time;
      HPrev := FModel.H;
      if not FModel.Advance(Msg) then
      begin
        Failed := True;
        FailMsg := Msg;
        Break;
      end;
      // every output time passed in this step, linearly interpolated
      // between its two ends (steps are ~0.01 s, frames ~1 s apart)
      while (k <= FFrames) and (FModel.Time >= FTotalTime * k / FFrames - 1e-12) do
      begin
        tk := FTotalTime * k / FFrames;
        f := (tk - tPrev) / (FModel.Time - tPrev);
        FFrame := HPrev + (FModel.H - HPrev) * f;
        FFrameTime := tk;
        Synchronize(@PostFrame);
        Inc(k);
      end;
      if GetTickCount64 - FLastReport >= 200 then
      begin
        FLastReport := GetTickCount64;
        Synchronize(@PostProgress);
      end;
    end;
  except
    on E: Exception do
    begin
      Failed := True;
      FailMsg := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TfmBenney2D }

procedure TfmBenney2D.FormCreate(Sender: TObject);
begin
  FSurface := TVMPlot3D.Create(Self);
  FSurface.Parent := pnlPlot;
  FSurface.Align := alClient;
  FSurface.Title := 'Film thickness h - hN';
  FSurface.XAxisTitle := 'x down slope (mm)';
  FSurface.YAxisTitle := 'y across (mm)';
  FSurface.ZAxisTitle := 'um';
  FSurface.EqualAspect := True;

  FStack := TVMPlotStack.Create(Self);
  FStack.Parent := pnlRight;
  FStack.Align := alTop;
  FStack.Height := pnlRight.Height div 2;
  FStack.Title := 'Centre line, y = 0';
  FStack.XAxisTitle := 'x (mm)';
  FStack.YAxisTitle := 'h - hN (um)';
  FStack.ZAxisTitle := 'time (s)';
  FStack.UseFrequencyAxis := True;    // label X in mm, not grid index
  FStack.NewestAtBack := True;        // t = 0 in front
  FStack.ClearStack;

  if Application.HasOption('film') then
    seFilm.Value := StrToFloatDef(Application.GetOptionValue('film'), seFilm.Value);
  if Application.HasOption('angle') then
    seAngle.Value := StrToFloatDef(Application.GetOptionValue('angle'), seAngle.Value);
  if Application.HasOption('time') then
    seTime.Value := StrToFloatDef(Application.GetOptionValue('time'), seTime.Value);
  if Application.HasOption('serial') then cbThreads.Checked := False;
  if Application.HasOption('excite') then cbExcite.Checked := True;
  if Application.HasOption('absorb') then cbAbsorb.Checked := True;
  if Application.HasOption('mod') then
    seMod.Value := StrToFloatDef(Application.GetOptionValue('mod'), seMod.Value);
  if Application.HasOption('modn') then
    seModN.Value := StrToIntDef(Application.GetOptionValue('modn'), seModN.Value);
  if Application.HasOption('length') then
    seLength.Value := StrToIntDef(Application.GetOptionValue('length'), seLength.Value);
  if Application.HasOption('width') then
    seWidth.Value := StrToIntDef(Application.GetOptionValue('width'), seWidth.Value);
  if Application.HasOption('exag') then
    seExag.Value := StrToIntDef(Application.GetOptionValue('exag'), seExag.Value);
  if Application.HasOption('period') then
    sePeriod.Value := StrToFloatDef(Application.GetOptionValue('period'), sePeriod.Value);
  if Application.HasOption('amp') then
    seAmp.Value := StrToFloatDef(Application.GetOptionValue('amp'), seAmp.Value);
  if Application.HasOption('start') then
    cbStart.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('start'), 0), 0, 3);
  FSnapshot := Application.GetOptionValue('snapshot');
  WriteInfo(False);
  if FSnapshot <> '' then
    Application.QueueAsyncCall(@DoSnapshot, 0)
  else
    Application.QueueAsyncCall(@DoSnapshot, 1);   // start a run on opening
end;

procedure TfmBenney2D.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
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

procedure TfmBenney2D.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FModel);              // FormCloseQuery has seen the thread out
end;

procedure TfmBenney2D.pnlRightResize(Sender: TObject);
begin
  if Assigned(FStack) then FStack.Height := pnlRight.Height div 2;
end;

function TfmBenney2D.ReadParams: TBenney2DParams;
begin
  Result := DefaultBenney2DParams;
  Result.hN := seFilm.Value;
  Result.Theta := DegToRad(seAngle.Value);
  Result.W := seWidth.Value;
  Result.Lx := seLength.Value;
  Result.Nx := 2 * (seNx.Value div 2);
  Result.Ny := 2 * (seNy.Value div 2);
  Result.Threaded := cbThreads.Checked;
  Result.Excite := cbExcite.Checked;
  Result.ExcitePeriod := sePeriod.Value;
  Result.ExciteAmp := seAmp.Value / 1000 / seFilm.Value;   // um -> units of hN
  Result.ExciteMod := seMod.Value / 100;
  Result.ExciteModN := seModN.Value;
  Result.Absorb := cbAbsorb.Checked;
  Result.AbsorbLength := seZone.Value;
  Result.AbsorbRate := seRate.Value;
end;

procedure TfmBenney2D.ParamChange(Sender: TObject);
begin
  if not Assigned(FThread) then WriteInfo(False);
end;

procedure TfmBenney2D.SetRunning(Running: Boolean);
begin
  btnRun.Enabled := not Running;
  btnStop.Enabled := Running;
  btnReplay.Enabled := (not Running) and (Length(FFrames) > 1);
  tbFrame.Enabled := (not Running) and (Length(FFrames) > 1);
  seFilm.Enabled := not Running;
  seAngle.Enabled := not Running;
  seWidth.Enabled := not Running;
  seLength.Enabled := not Running;
  seNx.Enabled := not Running;
  seNy.Enabled := not Running;
  seTime.Enabled := not Running;
  seFrames.Enabled := not Running;
  cbStart.Enabled := not Running;
  cbThreads.Enabled := not Running;
  cbExcite.Enabled := not Running;
  sePeriod.Enabled := not Running;
  seAmp.Enabled := not Running;
  seMod.Enabled := not Running;
  seModN.Enabled := not Running;
  cbAbsorb.Enabled := not Running;
  seZone.Enabled := not Running;
  seRate.Enabled := not Running;
end;

procedure TfmBenney2D.btnRunClick(Sender: TObject);
var
  P: TBenney2DParams;
  H0: TVMobj;
begin
  if Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  P := ReadParams;
  FreeAndNil(FModel);
  FModel := TBenney2DModel.Create(P);
  FInterp := FModel.UniformRows(DisplayRows);

  // the start: a bump a quarter-wavelength wide at x = Lx/5 on the
  // centre line, and/or smooth noise of 0.1 % of the film, or neither
  // ("Flat film", for the excitation alone)
  H0 := FModel.Flat;
  if cbStart.ItemIndex in [0, 2] then
    if FModel.FastestK > 0 then
      H0 := H0 + FModel.Bump(0.2, P.Lx / 5, Pi / FModel.FastestK / 2)
    else
      H0 := H0 + FModel.Bump(0.2, P.Lx / 5, P.W / 10);
  if cbStart.ItemIndex in [0, 1] then
    H0 := H0 + FModel.Noise(1e-3, 20261015);

  SetLength(FFrames, 0);
  SetLength(FTimes, 0);
  FShown := -1;
  FFailed := False;
  FFailMsg := '';
  FSurface.XAxisMin := 0;
  FSurface.XAxisMax := P.Lx * (P.Nx - 1) / P.Nx;   // the grid's last point
  FSurface.YAxisMin := -P.W / 2;
  FSurface.YAxisMax := P.W / 2;
  ApplyScale;
  FStack.ClearStack;
  FStack.MaxSeries := seFrames.Value + 1;
  FStack.ZAxisScale := seTime.Value / seFrames.Value;
  FStack.XAxisMin := 0;
  FStack.XAxisMax := P.Lx;
  FUpdatingSlider := True;
  tbFrame.Max := seFrames.Value;
  tbFrame.Position := 0;
  FUpdatingSlider := False;
  ProgressBar1.Position := 0;

  FStartTick := GetTickCount64;
  FThread := TBenney2DThread.Create(Self, FModel, H0, seTime.Value, seFrames.Value);
  FThread.OnTerminate := @ThreadDone;
  SetRunning(True);
  WriteInfo(True);
end;

procedure TfmBenney2D.btnStopClick(Sender: TObject);
begin
  if Assigned(FThread) then FThread.Terminate;
  tmrReplay.Enabled := False;
end;

procedure TfmBenney2D.ThreadDone(Sender: TObject);
begin
  // OnTerminate runs in the main thread just before the thread frees
  // itself (FreeOnTerminate)
  FFailed := FThread.Failed;
  FFailMsg := FThread.FailMsg;
  FThread := nil;
  FRunTime := (GetTickCount64 - FStartTick) / 1000;
  SetRunning(False);
  WriteInfo(False);
  if (FSnapshot <> '') and not Application.Terminated then
    Application.QueueAsyncCall(@DoSnapshot, 2);
end;

procedure TfmBenney2D.FrameReady(const H: TVMobj; t: Double);
var
  n: Integer;
  F, Centre: TVMobj;
  P: TBenney2DParams;
begin
  P := FModel.Params;
  // h - hN in micrometres, on uniform y rows
  F := MatMult(FInterp, AddScalar(H, -1)) * (P.hN * 1000);
  n := Length(FFrames);
  SetLength(FFrames, n + 1);
  SetLength(FTimes, n + 1);
  FFrames[n] := F;
  FTimes[n] := t;
  // the centre line, straight from the Chebyshev grid (y = 0 is a row)
  Centre := TVMobj.Create(1, P.Nx);
  Move(H.DataPtr[CentreRow(P) * P.Nx], Centre.DataPtr^, P.Nx * SizeOf(Double));
  FStack.AddGraph(AddScalar(Centre, -1) * (P.hN * 1000));
  ShowFrame(n);
  FUpdatingSlider := True;
  tbFrame.Position := n;
  FUpdatingSlider := False;
  if Assigned(FThread) then
    ProgressBar1.Position := Round(100 * t / seTime.Value);
end;

{ The fixed height scale: heights seExag times their true size against
  x and y (um over mm: 1e-3), in a box of +-1/10 of the plate's longer
  side at that scale. }
procedure TfmBenney2D.ApplyScale;
begin
  FZBox := 0.1 * Max(seLength.Value, seWidth.Value) * 1000 / seExag.Value;
  FSurface.ZAxisMin := -FZBox;
  FSurface.ZAxisMax := FZBox;
  FSurface.ZExaggeration := seExag.Value / 1000;
end;

procedure TfmBenney2D.seExagChange(Sender: TObject);
begin
  ApplyScale;
  if (FShown >= 0) and (FShown <= High(FFrames)) then ShowFrame(FShown);
end;

procedure TfmBenney2D.ShowFrame(i: Integer);
begin
  if (i < 0) or (i > High(FFrames)) then Exit;
  FShown := i;
  FSurface.Title := Format('Film h - hN (um),  t = %.1f s,  heights x %d', [FTimes[i], seExag.Value]);
  FSurface.SetData(FFrames[i]);
  lblFrame.Caption := Format('t = %.1f s', [FTimes[i]]);
end;

procedure TfmBenney2D.Progress;
begin
  if Assigned(FModel) then
    ProgressBar1.Position := Round(100 * FModel.Time / seTime.Value);
  WriteInfo(True);
end;

procedure TfmBenney2D.tbFrameChange(Sender: TObject);
begin
  if FUpdatingSlider or Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  ShowFrame(tbFrame.Position);
end;

procedure TfmBenney2D.btnReplayClick(Sender: TObject);
begin
  if Length(FFrames) = 0 then Exit;
  FReplayIndex := 0;
  tmrReplay.Enabled := True;
end;

procedure TfmBenney2D.tmrReplayTimer(Sender: TObject);
begin
  if FReplayIndex > High(FFrames) then
  begin
    tmrReplay.Enabled := False;
    Exit;
  end;
  ShowFrame(FReplayIndex);
  FUpdatingSlider := True;
  tbFrame.Position := FReplayIndex;
  FUpdatingSlider := False;
  Inc(FReplayIndex);
end;

procedure TfmBenney2D.btnResetViewClick(Sender: TObject);
begin
  FSurface.ResetView;
  FStack.ResetView;
end;

procedure TfmBenney2D.WriteInfo(Running: Boolean);
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  Own: Boolean;
  ratio, k, mn, mx: Double;
  i: Integer;
  L: TStrings;
begin
  // the physics of the parameters on screen, from a model built for
  // them (cheap: no factorisation happens until a run)
  if Running and Assigned(FModel) then
  begin
    M := FModel;
    Own := False;
  end
  else
  begin
    M := TBenney2DModel.Create(ReadParams);
    Own := True;
  end;
  P := M.Params;
  L := memInfo.Lines;
  L.BeginUpdate;
  try
    L.Clear;
    L.Add('2-D Benney equation, water film on an');
    L.Add('inclined plate, in mm and s');
    L.Add('');
    L.Add('h_t + div q = 0, x down slope, y across:');
    L.Add(' q_x = gs/3nu h^3 + [2g^2s^2/15nu^3 h^6');
    L.Add('       - gc/3nu h^3] h_x + s/3rnu h^3 (lap h)_x');
    L.Add(' q_y = -gc/3nu h^3 h_y + s/3rnu h^3 (lap h)_y');
    L.Add('');
    L.Add(Format('film %.3g mm on %.3g deg; plate %.0f mm wide,', [P.hN, RadToDeg(P.Theta), P.W]));
    L.Add(Format('  %.0f mm periodic down the slope', [P.Lx]));
    L.Add(Format('water: nu %.3g mm^2/s, sigma/rho %.3g mm^3/s^2', [P.Nu, P.SigmaRho]));
    ratio := M.Re / M.ReCrit;
    L.Add(Format('Re = q/nu = %.3g, onset Re_c = %.3g: %.2f x', [M.Re, M.ReCrit, ratio]));
    if P.Excite then
      lblExcite.Caption := Format('wavelength c T = %.1f mm (fastest-growing %.1f mm, %.2f s)',
        [M.WaveSpeed * P.ExcitePeriod, 2 * Pi / Max(M.FastestK, 1e-12), 2 * Pi / Max(M.FastestK, 1e-12) / M.WaveSpeed])
    else
      lblExcite.Caption := '';
    if ratio <= 1 then
      L.Add('  below onset: the film is stable, waves decay')
    else
    begin
      k := M.FastestK;
      L.Add(Format('  fastest-growing wave %.1f mm, growth %.3g /s', [2 * Pi / k, M.MaxGrowth]));
      L.Add(Format('  (e-folds in %.0f s); waves move at %.1f mm/s', [1 / M.MaxGrowth, M.WaveSpeed]));
    end;
    if M.Re > 5.5 then
    begin
      L.Add('  WARNING: Re > ~5 is beyond the Benney');
      L.Add('  equation: it blows up (a 0.3 mm film does)');
    end
    else if ratio > 1.4 then
    begin
      L.Add('  WARNING: far above onset the Benney');
      L.Add('  equation blows up (0.2 mm at 1.5 x does)');
    end;
    if P.Excite then
    begin
      k := 2 * Pi / (M.WaveSpeed * P.ExcitePeriod);
      L.Add(Format('excitation at x = 0: %.3g um, period %.3g s', [P.ExciteAmp * P.hN * 1000, P.ExcitePeriod]));
      L.Add(Format('  = %.3g Hz; wavelength c T = %.1f mm,', [1 / P.ExcitePeriod, 2 * Pi / k]));
      if M.GrowthAt(k) > 0 then
        L.Add(Format('  grows at %.3g /s (fastest %.3g /s)', [M.GrowthAt(k), M.MaxGrowth]))
      else
        L.Add(Format('  decays at %.3g /s (too short to grow)', [-M.GrowthAt(k)]));
      L.Add(Format('  source a c cos(2 pi t/T) g(x), g %.0f mm wide', [P.ExciteWidth]));
      if P.ExciteMod > 0 then
      begin
        L.Add(Format('  x (1 + %.3g cos(%d pi (y + W/2)/W)) across:', [P.ExciteMod, P.ExciteModN]));
        k := 2 * Pi / (M.WaveSpeed * P.ExcitePeriod);
        L.Add(Format('  ky = %.3g /mm (%.0f mm), that part grows at %.3g /s',
          [P.ExciteModN * Pi / P.W, 2 * P.W / P.ExciteModN, M.GrowthAt2(k, P.ExciteModN * Pi / P.W)]));
      end;
      if not P.Absorb then
        L.Add(Format('  waves return to x = 0 after %.1f s (periodic)', [P.Lx / M.WaveSpeed]));
    end;
    if P.Absorb then
    begin
      L.Add(Format('absorbing zone x = %.0f .. %.0f mm, peak %.3g /s:',
        [M.AbsorbStart, M.AbsorbStart + P.AbsorbLength, P.AbsorbRate]));
      L.Add(Format('  a wave crossing it keeps %.2g %%', [100 * (1 - M.AbsorbedFraction)]));
      if M.AbsorbStart < 0 then
        L.Add('  WARNING: longer than the domain allows');
    end;
    L.Add('');
    L.Add(Format('grid: %d Fourier (dx %.2f mm) x %d Chebyshev', [P.Nx, P.Lx / P.Nx, P.Ny + 1]));
    L.Add(Format('  (dy %.2f mm at the walls, %.2f mid-plate)',
      [P.W / 2 * (1 - Cos(Pi / P.Ny)), P.W / 2 * Sin(Pi / P.Ny)]));
    L.Add('walls: no flux, h_y = h_yyy = 0');
    L.Add(Format('semi-implicit BDF2, adaptive, tol %.0e hN', [P.Tol]));
    if P.Threaded then
      L.Add('x and y derivatives on two threads')
    else
      L.Add('x and y derivatives one after the other');

    if Assigned(FModel) and (Length(FFrames) > 0) then
    begin
      L.Add('');
      if Running then
        L.Add(Format('Running... t = %.2f s, %.1f s', [FModel.Time, (GetTickCount64 - FStartTick) / 1000]))
      else if FFailed then
      begin
        L.Add(Format('FAILED after t = %.2f s:', [FModel.Time]));
        L.Add('  ' + FFailMsg);
      end
      else if FTimes[High(FTimes)] < seTime.Value - 1e-9 then
        L.Add(Format('Stopped at t = %.2f s', [FTimes[High(FTimes)]]))
      else
        L.Add(Format('Done to t = %.4g s in %.1f s', [FTimes[High(FTimes)], FRunTime]));
      L.Add(Format('  %d steps (%d rejected), dt now %.3g s', [FModel.Steps, FModel.Rejected, FModel.Dt]));
      L.Add(Format('  %d sets of mode factorisations', [FModel.Factorisations]));
      L.Add(Format('  right-hand sides %d: %.2f s', [FModel.RHSCalls, FModel.RHSTime]));
      L.Add(Format('    x half %.2f s, y half %.2f s', [FModel.XTime, FModel.YTime]));
      L.Add(Format('  mode solves %.2f s, L E %.2f s, x-transforms %.2f s',
        [FModel.SolveTime, FModel.ApplyLTime, FModel.ModesTime]));
      mn := 0; mx := 0;
      with FFrames[High(FFrames)] do
        for i := 0 to Rows * Cols - 1 do
        begin
          mn := Min(mn, DataPtr[i]);
          mx := Max(mx, DataPtr[i]);
        end;
      L.Add(Format('  latest h - hN: %.2f .. %.2f um', [mn, mx]));
    end;
    L.Add('');
    L.Add('Surface: drag to rotate, wheel to zoom;');
    L.Add('slider and Replay after a run.');
  finally
    L.EndUpdate;
    if Own then M.Free;
  end;
end;

procedure TfmBenney2D.DoSnapshot(Data: PtrInt);
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
