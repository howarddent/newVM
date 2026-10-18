unit ufilmwrmmain;

{*******************************************************************************

     FilmWRM - a water film falling down an inclined plate, in two
     dimensions, by the weighted-residual model of Ruyer-Quil &
     Manneville (ufilmwrmmodel.pas): the thickness h and the two flow
     rates q, p on a Fourier (down the slope, periodic) x cosine/sine
     (across the plate, mirror side walls) grid, stepped
     semi-implicitly, half the transforms of each right-hand side on a
     second thread. The form is Benney2D's, with the model swapped.

     Why a second demo: the Benney equation (demos/Benney2D) blows up
     for any film much thicker than 0.2 mm of water. This model doesn't:
     the defaults are the 1 mm film first asked for, on a 2 deg plate
     300 mm wide, 300 mm periodic down the slope - Re 114, 4.8 x the
     onset of waves (on 1 deg, 1.2 x onset, the waves grow too slowly
     to see on a 300 mm plate).

     Display:
       - left, a TVMPlot3D surface of h - hN in micrometres, x down the
         slope and y across, x and y to scale and heights at a fixed
         vertical exaggeration, "height x" (default 40: the waves are a
         large fraction of the 1 mm film). The box is +-1/10 of the
         plate's longer side at that exaggeration, 750 um by default,
         the same for every frame. The grid's rows are already evenly
         spaced; they go onto 101 display rows by the cosine series.
       - right, the centre line y = 0 as a waterfall (TVMPlotStack),
         t = 0 in front.
       - after a run, Replay animates the surface again and the slider
         picks any frame.

     Excitation: "excite at x = 0" adds a line source across the plate
     at x = 0, a hN c cos(2 pi t/T) g(x) with c = 3 qN/hN the kinematic
     wave speed. In this model the source also drives a second,
     strongly damped wave, and the wave it launches is about half of a
     at the default 0.3 s (checkwrm.lpr); the wavelength label uses the
     linear dispersion relation, not c T. "transverse (%)" and
     "half-waves" modulate the source across the plate, as in Benney2D.
     The domain is periodic, so the train comes round to x = 0 after
     about Lx/c - unless "absorbing zone" is ticked, which relaxes h, q
     and p to the flat film just before x = Lx.

     Second case, "OpenFOAM inclined plane" (the "case" list): the
     conditions of OpenFOAM's inclinedPlaneFilm tutorial - a 141 um
     film entering a 64 x 64 mm plate on 30 deg over a 10 um precursor
     film, round an 8 mm cylinder, under 1 m/s of air - by the same
     model on finite volumes (ufilmplanemodel.pas: the spectral model
     can't hold an inlet, an obstacle or a moving contact line). The
     surface is then h itself in um, the cylinder a post to the top of
     the box; Nx is the cells down the slope (square cells, Ny unused)
     and the first-row controls set the film, incline and plate.
     Selecting the case loads the tutorial's values; the default grid,
     256 x 128 on the half plate, takes about a minute for the 2.5 s
     on eight threads ("stepping on n threads"; unticked, one).
     demos/InclinedPlane/filmplane.lpr runs the same model from the
     command line and writes VTK frames for ParaView.

     Command line, for unattended checks: --snapshot=<prefix> runs,
     saves <prefix>.bmp (the window) and prints the memo; --time=<s>,
     --frames=<n>, --film=<mm>, --angle=<deg>, --serial (no transform
     thread), --excite, --period=<s>, --amp=<um>, --mod=<%>,
     --modn=<n>, --absorb, --length=<mm>, --width=<mm>, --nx=<n>,
     --exag=<x> and --start=<0..3> (the start list's index) set the
     run; --case=1 picks the inclined plane, with --theta=<deg>,
     --nocyl and --noshear.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, uVMPlot3D, uVMPlotStack, ufilmwrmmodel, ufilmplanemodel;

type
  TfmFilmWRM = class;

  { A run off the GUI thread, of either case }
  TRunThread = class(TThread)
  public
    Failed: Boolean;
    FailMsg: string;
  end;

  { The spectral model's integration }
  TFilmThread = class(TRunThread)
  private
    FForm: TfmFilmWRM;
    FModel: TFilmWRMModel;
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
    constructor Create(AForm: TfmFilmWRM; AModel: TFilmWRMModel;
      const H0: TVMobj; ATotalTime: Double; AFrames: Integer);
  end;

  { The inclined-plane case's integration: frame by frame, each frame
    the full plate's h in mm, cylinder cells -1 }
  TPlaneThread = class(TRunThread)
  private
    FForm: TfmFilmWRM;
    FModel: TFilmPlaneModel;
    FTotalTime: Double;
    FFrames: Integer;
    FFrame: TVMobj;
    FFrameTime: Double;
    procedure PostFrame;
  protected
    procedure Execute; override;
  public
    constructor Create(AForm: TfmFilmWRM; AModel: TFilmPlaneModel;
      ATotalTime: Double; AFrames: Integer);
  end;

  { TfmFilmWRM }

  TfmFilmWRM = class(TForm)
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
    lblCase: TLabel;
    cbCase: TComboBox;
    cbCylinder: TCheckBox;
    cbShear: TCheckBox;
    lblTheta: TLabel;
    seTheta: TFloatSpinEdit;
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
    procedure cbCaseChange(Sender: TObject);
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
    FModel: TFilmWRMModel;
    FPlane: TFilmPlaneModel;         // the inclined-plane case's model
    FThread: TRunThread;
    FPlaneRun: Boolean;              // the frames held are the plane case's
    FInterp: TVMobj;                 // grid rows -> display rows
    FFrames: array of TVMobj;        // h - hN in um, (Nyd, Nx); plane case: h in um
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
    function ReadParams: TFilmParams;
    function ReadPlaneParams: TPlaneParams;
    function PlaneCase: Boolean;
    procedure RunPlane;
    procedure WritePlaneInfo(Running: Boolean);
    procedure ApplyScale;
    procedure ThreadDone(Sender: TObject);
    procedure ShowFrame(i: Integer);
    procedure WriteInfo(Running: Boolean);
    procedure DoSnapshot(Data: PtrInt);
    procedure SetRunning(Running: Boolean);
  public
    // called by the thread, through Synchronize
    procedure FrameReady(const H: TVMobj; t: Double);
    procedure PlaneFrameReady(const H: TVMobj; t: Double);
    procedure Progress;
  end;

var
  fmFilmWRM: TfmFilmWRM;

implementation

{$R *.lfm}

const
  FirstStep = 1e-3;        // s; the error control takes it from there
  DisplayRows = 101;       // uniform y rows on the surface

{ TFilmThread }

constructor TFilmThread.Create(AForm: TfmFilmWRM; AModel: TFilmWRMModel;
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

procedure TFilmThread.PostFrame;
begin
  FForm.FrameReady(FFrame, FFrameTime);
end;

procedure TFilmThread.PostProgress;
begin
  FForm.Progress;
end;

procedure TFilmThread.Execute;
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

{ TPlaneThread }

constructor TPlaneThread.Create(AForm: TfmFilmWRM; AModel: TFilmPlaneModel;
  ATotalTime: Double; AFrames: Integer);
begin
  FForm := AForm;
  FModel := AModel;
  FTotalTime := ATotalTime;
  FFrames := AFrames;
  FreeOnTerminate := True;
  inherited Create(False);
end;

procedure TPlaneThread.PostFrame;
begin
  FForm.PlaneFrameReady(FFrame, FFrameTime);
end;

procedure TPlaneThread.Execute;
var
  k: Integer;
begin
  try
    FFrame := FModel.FullPlate(-1);
    FFrameTime := 0;
    Synchronize(@PostFrame);
    // frame by frame, each step stopping exactly on the frame time, as
    // filmplane.lpr does, so the two give the same frames
    k := 1;
    while (k <= FFrames) and not Terminated do
    begin
      if not FModel.AdvanceTo(FTotalTime * k / FFrames) then
      begin
        Failed := True;
        FailMsg := 'the film went NaN';
        Break;
      end;
      FFrame := FModel.FullPlate(-1);
      FFrameTime := FModel.Time;
      Synchronize(@PostFrame);
      Inc(k);
    end;
  except
    on E: Exception do
    begin
      Failed := True;
      FailMsg := E.ClassName + ': ' + E.Message;
    end;
  end;
end;

{ TfmFilmWRM }

procedure TfmFilmWRM.FormCreate(Sender: TObject);
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
  if Application.HasOption('nx') then
    seNx.Value := StrToIntDef(Application.GetOptionValue('nx'), seNx.Value);
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
  // the inclined-plane case: its defaults first, then any options above
  // that apply to it again over them
  if Application.HasOption('case') and (StrToIntDef(Application.GetOptionValue('case'), 0) = 1) then
  begin
    cbCase.ItemIndex := 1;
    cbCaseChange(nil);
    if Application.HasOption('film') then
      seFilm.Value := StrToFloatDef(Application.GetOptionValue('film'), seFilm.Value);
    if Application.HasOption('angle') then
      seAngle.Value := StrToFloatDef(Application.GetOptionValue('angle'), seAngle.Value);
    if Application.HasOption('time') then
      seTime.Value := StrToFloatDef(Application.GetOptionValue('time'), seTime.Value);
    if Application.HasOption('length') then
      seLength.Value := StrToIntDef(Application.GetOptionValue('length'), seLength.Value);
    if Application.HasOption('width') then
      seWidth.Value := StrToIntDef(Application.GetOptionValue('width'), seWidth.Value);
    if Application.HasOption('nx') then
      seNx.Value := StrToIntDef(Application.GetOptionValue('nx'), seNx.Value);
    if Application.HasOption('exag') then
      seExag.Value := StrToIntDef(Application.GetOptionValue('exag'), seExag.Value);
  end;
  if Application.HasOption('frames') then
    seFrames.Value := StrToIntDef(Application.GetOptionValue('frames'), seFrames.Value);
  if Application.HasOption('theta') then
    seTheta.Value := StrToFloatDef(Application.GetOptionValue('theta'), seTheta.Value);
  if Application.HasOption('nocyl') then cbCylinder.Checked := False;
  if Application.HasOption('noshear') then cbShear.Checked := False;
  SetRunning(False);
  FSnapshot := Application.GetOptionValue('snapshot');
  WriteInfo(False);
  if FSnapshot <> '' then
    Application.QueueAsyncCall(@DoSnapshot, 0)
  else
    Application.QueueAsyncCall(@DoSnapshot, 1);   // start a run on opening
end;

procedure TfmFilmWRM.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
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

procedure TfmFilmWRM.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FModel);              // FormCloseQuery has seen the thread out
  FreeAndNil(FPlane);
end;

procedure TfmFilmWRM.pnlRightResize(Sender: TObject);
begin
  if Assigned(FStack) then FStack.Height := pnlRight.Height div 2;
end;

function TfmFilmWRM.ReadParams: TFilmParams;
begin
  Result := DefaultFilmParams;
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

function TfmFilmWRM.PlaneCase: Boolean;
begin
  Result := cbCase.ItemIndex = 1;
end;

{ The inclined-plane case's parameters: the plate L x W centred on the
  cylinder, the inlet film and incline from the first row, Nx cells down
  the slope and square cells across the computed half. }
function TfmFilmWRM.ReadPlaneParams: TPlaneParams;
var
  dx: Double;
begin
  Result := DefaultPlaneParams;
  Result.hN := seFilm.Value;
  Result.Angle := seAngle.Value;
  Result.X0 := -seLength.Value / 2;
  Result.X1 := seLength.Value / 2;
  Result.Wd := seWidth.Value / 2;
  Result.Nx := seNx.Value;
  dx := seLength.Value / seNx.Value;
  Result.Ny := Max(4, Round(Result.Wd / dx));
  Result.Theta := seTheta.Value;
  Result.UseCyl := cbCylinder.Checked;
  Result.UseShear := cbShear.Checked;
  if not cbThreads.Checked then Result.Threads := 1;
end;

{ Switching case loads that case's conditions into the controls: the
  OpenFOAM tutorial's for the inclined plane, the 1 mm film's for the
  periodic plate. }
procedure TfmFilmWRM.cbCaseChange(Sender: TObject);
begin
  if PlaneCase then
  begin
    seFilm.Value := 0.141;
    seAngle.Value := 30;
    seLength.Value := 64;
    seWidth.Value := 64;
    seNx.Value := 256;
    seTime.Value := 2.5;
    seFrames.Value := 125;
    seExag.Value := 32;
    cbThreads.Caption := Format('stepping on %d threads', [DefaultPlaneParams.Threads]);
  end
  else
  begin
    seFilm.Value := 1;
    seAngle.Value := 2;
    seLength.Value := 300;
    seWidth.Value := 300;
    seNx.Value := 256;
    seNy.Value := 64;
    seTime.Value := 10;
    seFrames.Value := 100;
    seExag.Value := 40;
    cbThreads.Caption := 'transforms on two threads';
  end;
  SetRunning(Assigned(FThread));
  ParamChange(nil);
end;

procedure TfmFilmWRM.ParamChange(Sender: TObject);
begin
  if not Assigned(FThread) then WriteInfo(False);
end;

procedure TfmFilmWRM.SetRunning(Running: Boolean);
var
  Sp, Pl: Boolean;
begin
  // controls of the spectral model only, of the plane case only
  Sp := (not Running) and not PlaneCase;
  Pl := (not Running) and PlaneCase;
  btnRun.Enabled := not Running;
  btnStop.Enabled := Running;
  btnReplay.Enabled := (not Running) and (Length(FFrames) > 1);
  tbFrame.Enabled := (not Running) and (Length(FFrames) > 1);
  cbCase.Enabled := not Running;
  seFilm.Enabled := not Running;
  seAngle.Enabled := not Running;
  seWidth.Enabled := not Running;
  seLength.Enabled := not Running;
  seNx.Enabled := not Running;
  seNy.Enabled := Sp;              // the plane case's cells are square
  seTime.Enabled := not Running;
  seFrames.Enabled := not Running;
  cbStart.Enabled := Sp;
  cbThreads.Enabled := not Running;
  cbExcite.Enabled := Sp;
  sePeriod.Enabled := Sp;
  seAmp.Enabled := Sp;
  seMod.Enabled := Sp;
  seModN.Enabled := Sp;
  cbAbsorb.Enabled := Sp;
  seZone.Enabled := Sp;
  seRate.Enabled := Sp;
  cbCylinder.Enabled := Pl;
  cbShear.Enabled := Pl;
  seTheta.Enabled := Pl;
end;

procedure TfmFilmWRM.btnRunClick(Sender: TObject);
var
  P: TFilmParams;
  H0: TVMobj;
begin
  if Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  if PlaneCase then
  begin
    RunPlane;
    Exit;
  end;
  FPlaneRun := False;
  P := ReadParams;
  FreeAndNil(FModel);
  FModel := TFilmWRMModel.Create(P);
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
  FThread := TFilmThread.Create(Self, FModel, H0, seTime.Value, seFrames.Value);
  FThread.OnTerminate := @ThreadDone;
  SetRunning(True);
  WriteInfo(True);
end;

{ The OpenFOAM inclined-plane case: the full plate as a surface of h in
  um, x and y to scale, the cylinder a post up to the top of the box. }
procedure TfmFilmWRM.RunPlane;
var
  PP: TPlaneParams;
begin
  PP := ReadPlaneParams;
  FreeAndNil(FPlane);
  FPlane := TFilmPlaneModel.Create(PP);
  FPlaneRun := True;
  SetLength(FFrames, 0);
  SetLength(FTimes, 0);
  FShown := -1;
  FFailed := False;
  FFailMsg := '';
  FSurface.XAxisMin := FPlane.XC(0);
  FSurface.XAxisMax := FPlane.XC(PP.Nx - 1);
  FSurface.YAxisMin := -PP.Wd + FPlane.CellDy / 2;
  FSurface.YAxisMax := PP.Wd - FPlane.CellDy / 2;
  ApplyScale;
  FStack.ClearStack;
  FStack.Title := 'Centre line, y = 0 (the cylinder at 0)';
  FStack.YAxisTitle := 'h (um)';
  FStack.MaxSeries := seFrames.Value + 1;
  FStack.ZAxisScale := seTime.Value / seFrames.Value;
  FStack.XAxisMin := PP.X0;
  FStack.XAxisMax := PP.X1;
  FUpdatingSlider := True;
  tbFrame.Max := seFrames.Value;
  tbFrame.Position := 0;
  FUpdatingSlider := False;
  ProgressBar1.Position := 0;

  FStartTick := GetTickCount64;
  FThread := TPlaneThread.Create(Self, FPlane, seTime.Value, seFrames.Value);
  FThread.OnTerminate := @ThreadDone;
  SetRunning(True);
  WriteInfo(True);
end;

procedure TfmFilmWRM.PlaneFrameReady(const H: TVMobj; t: Double);
var
  n, i, Ny: Integer;
  F, Centre: TVMobj;
  post: Double;
begin
  // h in um; the cylinder (cells of -1) stands up to the top of the box
  post := FSurface.ZAxisMax;
  F := H * 1000.0;
  for i := 0 to F.Rows * F.Cols - 1 do
    if F.DataPtr[i] < 0 then F.DataPtr[i] := post;
  n := Length(FFrames);
  SetLength(FFrames, n + 1);
  SetLength(FTimes, n + 1);
  FFrames[n] := F;
  FTimes[n] := t;
  // the row just above y = 0, the cylinder at 0
  Ny := H.Rows div 2;
  Centre := TVMobj.Create(1, H.Cols);
  for i := 0 to H.Cols - 1 do
    Centre.DataPtr[i] := Max(0, H.DataPtr[Ny * H.Cols + i]) * 1000;
  FStack.AddGraph(Centre);
  ShowFrame(n);
  FUpdatingSlider := True;
  tbFrame.Position := n;
  FUpdatingSlider := False;
  if Assigned(FThread) then
    ProgressBar1.Position := Round(100 * t / seTime.Value);
  WriteInfo(Assigned(FThread));
end;

procedure TfmFilmWRM.btnStopClick(Sender: TObject);
begin
  if Assigned(FThread) then FThread.Terminate;
  tmrReplay.Enabled := False;
end;

procedure TfmFilmWRM.ThreadDone(Sender: TObject);
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

procedure TfmFilmWRM.FrameReady(const H: TVMobj; t: Double);
var
  n: Integer;
  F, Centre: TVMobj;
  P: TFilmParams;
begin
  FStack.Title := 'Centre line, y = 0';
  FStack.YAxisTitle := 'h - hN (um)';
  P := FModel.Params;
  // h - hN in micrometres, on uniform y rows
  F := MatMult(FInterp, AddScalar(H, -1)) * (P.hN * 1000);
  n := Length(FFrames);
  SetLength(FFrames, n + 1);
  SetLength(FTimes, n + 1);
  FFrames[n] := F;
  FTimes[n] := t;
  // the centre line, straight from the grid (y = 0 is a row)
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
procedure TfmFilmWRM.ApplyScale;
begin
  FZBox := 0.1 * Max(seLength.Value, seWidth.Value) * 1000 / seExag.Value;
  if FPlaneRun then
  begin
    // h itself, not h - hN: the same box height, from 0
    FSurface.ZAxisMin := 0;
    FSurface.ZAxisMax := 2 * FZBox;
  end
  else
  begin
    FSurface.ZAxisMin := -FZBox;
    FSurface.ZAxisMax := FZBox;
  end;
  FSurface.ZExaggeration := seExag.Value / 1000;
end;

procedure TfmFilmWRM.seExagChange(Sender: TObject);
var
  k, i: Integer;
  old: Double;
begin
  old := FSurface.ZAxisMax;
  ApplyScale;
  // the cylinder posts follow the box top
  if FPlaneRun then
    for k := 0 to High(FFrames) do
      with FFrames[k] do
        for i := 0 to Rows * Cols - 1 do
          if DataPtr[i] = old then DataPtr[i] := FSurface.ZAxisMax;
  if (FShown >= 0) and (FShown <= High(FFrames)) then ShowFrame(FShown);
end;

procedure TfmFilmWRM.ShowFrame(i: Integer);
begin
  if (i < 0) or (i > High(FFrames)) then Exit;
  FShown := i;
  if FPlaneRun then
  begin
    FSurface.Title := Format('Film h (um),  t = %.2f s,  heights x %d', [FTimes[i], seExag.Value]);
    lblFrame.Caption := Format('t = %.2f s', [FTimes[i]]);
  end
  else
  begin
    FSurface.Title := Format('Film h - hN (um),  t = %.1f s,  heights x %d', [FTimes[i], seExag.Value]);
    lblFrame.Caption := Format('t = %.1f s', [FTimes[i]]);
  end;
  FSurface.SetData(FFrames[i]);
end;

procedure TfmFilmWRM.Progress;
begin
  if FPlaneRun then Exit;
  if Assigned(FModel) then
    ProgressBar1.Position := Round(100 * FModel.Time / seTime.Value);
  WriteInfo(True);
end;

procedure TfmFilmWRM.tbFrameChange(Sender: TObject);
begin
  if FUpdatingSlider or Assigned(FThread) then Exit;
  tmrReplay.Enabled := False;
  ShowFrame(tbFrame.Position);
end;

procedure TfmFilmWRM.btnReplayClick(Sender: TObject);
begin
  if Length(FFrames) = 0 then Exit;
  FReplayIndex := 0;
  tmrReplay.Enabled := True;
end;

procedure TfmFilmWRM.tmrReplayTimer(Sender: TObject);
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

procedure TfmFilmWRM.btnResetViewClick(Sender: TObject);
begin
  FSurface.ResetView;
  FStack.ResetView;
end;

procedure TfmFilmWRM.WriteInfo(Running: Boolean);
var
  P: TFilmParams;
  M: TFilmWRMModel;
  Own: Boolean;
  ratio, k, kf, mn, mx, qmx, pmx: Double;
  i: Integer;
  L: TStrings;
begin
  if PlaneCase or (Running and FPlaneRun) then
  begin
    WritePlaneInfo(Running);
    Exit;
  end;
  // the physics of the parameters on screen, from a model built for
  // them (cheap: nothing is stepped until a run)
  if Running and Assigned(FModel) then
  begin
    M := FModel;
    Own := False;
  end
  else
  begin
    M := TFilmWRMModel.Create(ReadParams);
    Own := True;
  end;
  P := M.Params;
  L := memInfo.Lines;
  L.BeginUpdate;
  try
    L.Clear;
    L.Add('Weighted-residual film model (Ruyer-Quil &');
    L.Add('Manneville), water on an inclined plate, mm, s');
    L.Add('');
    L.Add('h_t + q_x + p_y = 0, flow rates Q = (q, p):');
    L.Add(' q_t = 5/6 [gs h - gc h h_x + Sg h (lap h)_x]');
    L.Add('   - 5/2 nu q/h^2 + 9/7 q Q.grad h/h^2');
    L.Add('   - 8/7 (Q.grad) q/h - 9/7 q div Q/h');
    L.Add(' p_t: the same with p, no gs h term');
    L.Add('');
    L.Add(Format('film %.3g mm on %.3g deg; plate %.0f mm wide,', [P.hN, RadToDeg(P.Theta), P.W]));
    L.Add(Format('  %.0f mm periodic down the slope', [P.Lx]));
    L.Add(Format('water: nu %.3g mm^2/s, sigma/rho %.3g mm^3/s^2', [P.Nu, P.SigmaRho]));
    ratio := M.Re / M.ReCrit;
    L.Add(Format('Re = q/nu = %.3g, onset Re_c = %.3g: %.2f x', [M.Re, M.ReCrit, ratio]));
    L.Add(Format('  flux %.3g mm^2/s, mean velocity %.3g mm/s', [M.qN, M.MeanVelocity]));
    k := M.FastestK;
    if P.Excite then
    begin
      kf := M.ForcedK(P.ExcitePeriod);
      if k > 0 then
        lblExcite.Caption := Format('wavelength %.1f mm (fastest-growing %.1f mm, %.3f s)',
          [2 * Pi / kf, 2 * Pi / k, 2 * Pi / k / M.WaveSpeed])
      else
        lblExcite.Caption := Format('wavelength %.1f mm', [2 * Pi / kf]);
    end
    else
      lblExcite.Caption := '';
    if (ratio <= 1) or (k = 0) then
      L.Add('  below onset: the film is stable, waves decay')
    else
    begin
      L.Add(Format('  fastest-growing wave %.1f mm, growth %.3g /s', [2 * Pi / k, M.MaxGrowth]));
      L.Add(Format('  (e-folds in %.2g s); it moves at %.1f mm/s', [1 / M.MaxGrowth, M.WaveSpeed]));
      L.Add(Format('  and crosses the plate in %.2g s', [P.Lx / M.WaveSpeed]));
    end;
    if M.Re > 300 then
    begin
      L.Add('  WARNING: Re > ~300 is turbulent territory,');
      L.Add('  beyond any laminar film model');
    end
    else if M.Re > 150 then
      L.Add('  NOTE: past Re ~150 the model is qualitative');
    if P.Excite then
    begin
      L.Add(Format('excitation at x = 0: %.3g um, period %.3g s', [P.ExciteAmp * P.hN * 1000, P.ExcitePeriod]));
      L.Add(Format('  = %.3g Hz; wavelength %.1f mm,', [1 / P.ExcitePeriod, 2 * Pi / kf]));
      if M.GrowthAt(kf) > 0 then
        L.Add(Format('  grows at %.3g /s (fastest %.3g /s)', [M.GrowthAt(kf), M.MaxGrowth]))
      else
        L.Add(Format('  decays at %.3g /s (too short to grow)', [-M.GrowthAt(kf)]));
      L.Add(Format('  source a hN 3u cos(2 pi t/T) g(x), g %.0f mm wide;', [P.ExciteWidth]));
      L.Add('  it launches about a/2 at T = 0.3 s');
      if P.ExciteMod > 0 then
      begin
        L.Add(Format('  x (1 + %.3g cos(%d pi (y + W/2)/W)) across:', [P.ExciteMod, P.ExciteModN]));
        L.Add(Format('  ky = %.3g /mm (%.0f mm), that part grows at %.3g /s',
          [P.ExciteModN * Pi / P.W, 2 * P.W / P.ExciteModN, M.GrowthAt2(kf, P.ExciteModN * Pi / P.W)]));
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
    L.Add(Format('grid: %d Fourier (dx %.2f mm) x %d cosine/sine', [P.Nx, P.Lx / P.Nx, P.Ny + 1]));
    L.Add(Format('  (dy %.2f mm), de-aliased by the 2/3 rule', [P.W / P.Ny]));
    L.Add('walls: mirrors, p = 0, h_y = h_yyy = 0');
    L.Add(Format('semi-implicit BDF2, adaptive, tol %.0e', [P.Tol]));
    if P.Threaded then
      L.Add('transforms split over two threads')
    else
      L.Add('transforms on one thread');

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
      L.Add(Format('  right-hand sides %d: %.2f s (transforms %.2f s)',
        [FModel.RHSCalls, FModel.RHSTime, FModel.TransTime]));
      L.Add(Format('  %d sets of 3 x 3 inverses, %.2f s of solves; beta %.2f',
        [FModel.Systems, FModel.SolveTime, FModel.Beta]));
      mn := 0; mx := 0;
      with FFrames[High(FFrames)] do
        for i := 0 to Rows * Cols - 1 do
        begin
          mn := Min(mn, DataPtr[i]);
          mx := Max(mx, DataPtr[i]);
        end;
      L.Add(Format('  latest h - hN: %.0f .. %.0f um (%.2f .. %.2f hN)',
        [mn, mx, 1 + mn / (P.hN * 1000), 1 + mx / (P.hN * 1000)]));
      qmx := 0; pmx := 0;
      for i := 0 to FModel.FlowQ.Rows * FModel.FlowQ.Cols - 1 do
      begin
        qmx := Max(qmx, FModel.FlowQ.DataPtr[i]);
        pmx := Max(pmx, Abs(FModel.FlowP.DataPtr[i]));
      end;
      L.Add(Format('  largest q %.3g qN, largest |p| %.3g qN', [qmx / M.qN, pmx / M.qN]));
    end;
    L.Add('');
    L.Add('Surface: drag to rotate, wheel to zoom;');
    L.Add('slider and Replay after a run.');
  finally
    L.EndUpdate;
    if Own then M.Free;
  end;
end;

{ The inclined-plane case's memo: the conditions, the model, and the
  run's progress. }
procedure TfmFilmWRM.WritePlaneInfo(Running: Boolean);
var
  PP: TPlaneParams;
  M: TFilmPlaneModel;
  Own: Boolean;
  L: TStrings;
  gsh, hmin, hmax, onset: Double;
begin
  // the conditions from a model built for the controls (cheap: nothing
  // is stepped), the run's figures from the run's own
  if Running and Assigned(FPlane) then
  begin
    M := FPlane;
    Own := False;
  end
  else
  begin
    M := TFilmPlaneModel.Create(ReadPlaneParams);
    Own := True;
  end;
  PP := M.Params;
  lblExcite.Caption := '';
  L := memInfo.Lines;
  L.BeginUpdate;
  try
    L.Clear;
    L.Add('OpenFOAM inclinedPlaneFilm case, by the');
    L.Add('weighted-residual model on finite volumes');
    L.Add('(ufilmplanemodel.pas), mm, s');
    L.Add('');
    L.Add(Format('plate %.0f x %.0f mm on %.3g deg, water at 300 K', [PP.X1 - PP.X0, 2 * PP.Wd, PP.Angle]));
    if PP.UseCyl then
      L.Add(Format('cylinder r = %.0f mm at the centre', [PP.RCyl]))
    else
      L.Add('no cylinder');
    L.Add(Format('inlet film %.0f um held at x = %.0f mm;', [PP.hN * 1000, PP.X0]));
    L.Add(Format('  the plate starts under a %.0f um precursor film', [PP.hB * 1000]));
    onset := 5 / 6 / Tan(DegToRad(PP.Angle));
    L.Add(Format('Re = q/nu = %.3g (onset of waves %.3g),', [M.qN / PlaneNuW, onset]));
    L.Add(Format('  q %.3g mm^2/s, mean velocity %.3g mm/s', [M.qN, M.qN / PP.hN]));
    L.Add(Format('  1-D front speed %.3g mm/s',
      [M.qN * (1 - Power(PP.hB / PP.hN, 3)) / (PP.hN - PP.hB)]));
    gsh := 5 / 6 * PlaneGrav * Sin(DegToRad(PP.Angle)) * PP.hN;
    if PP.UseShear then
    begin
      L.Add(Format('air 1 m/s: Blasius shear, 5/4 tau/rho %.3g', [M.AirShear(0)]));
      L.Add(Format('  mm^2/s^2 at x = 0 (gravity %.0f)', [gsh]));
    end
    else
      L.Add('no air shear');
    if PP.Theta > 0 then
      L.Add(Format('disjoining pressure: contact angle %.0f deg', [PP.Theta]))
    else
      L.Add('contact line: the precursor film alone');
    L.Add('');
    L.Add(Format('grid: %d x %d cells on the half y >= 0, dx %.3g mm,', [PP.Nx, PP.Ny, M.CellDx]));
    L.Add('  mirrored about y = 0; h at centres, q, p on faces');
    L.Add(Format('explicit SSP-RK3 on %d thread(s); the step is', [M.Threads]));
    L.Add('  held down by the drag');
    L.Add('  5/2 nu/h^2 in the precursor (~2e-5 s late on)');
    L.Add('walls and cylinder: free-slip, no flux, h_n = 0');
    L.Add('Not OpenFOAM''s physics: laminar drag, not Manning;');
    L.Add('  Blasius shear, not the coupled air; no random angle');
    L.Add('demos/InclinedPlane/filmplane.lpr writes the same run');
    L.Add('  as VTK frames for ParaView');
    if Own then FreeAndNil(M);

    if FPlaneRun and Assigned(FPlane) and (Length(FFrames) > 0) then
    begin
      M := FPlane;
      L.Add('');
      if Running then
        L.Add(Format('Running... t = %.2f s, %.1f s', [M.Time, (GetTickCount64 - FStartTick) / 1000]))
      else if FFailed then
      begin
        L.Add(Format('FAILED after t = %.2f s:', [M.Time]));
        L.Add('  ' + FFailMsg);
      end
      else if FTimes[High(FTimes)] < seTime.Value - 1e-9 then
        L.Add(Format('Stopped at t = %.2f s', [FTimes[High(FTimes)]]))
      else
        L.Add(Format('Done to t = %.4g s in %.1f s', [FTimes[High(FTimes)], FRunTime]));
      M.HRange(hmin, hmax);
      L.Add(Format('  %d steps, dt now %.3g s, clips %d', [M.Steps, M.LastDt, M.Clips]));
      L.Add(Format('  h %.1f .. %.1f um, largest |U| %.1f mm/s', [hmin * 1000, hmax * 1000, M.MaxSpeed]));
      L.Add(Format('  front (h > hN/2) at x = %.1f mm on y = 0,', [M.FrontX(0)]));
      L.Add(Format('  %.1f mm at the wall; mass %.2f mm^3 (half)', [M.FrontX(PP.Ny - 1), M.Mass]));
    end;
    L.Add('');
    L.Add('Surface: drag to rotate, wheel to zoom;');
    L.Add('slider and Replay after a run.');
  finally
    L.EndUpdate;
  end;
end;

procedure TfmFilmWRM.DoSnapshot(Data: PtrInt);
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
