unit uWave2DMain;

{*******************************************************************************

     Main form for the Wave2D_FPC demo - ported from the Delphi/GLScene
     original at demos/Chebyshev/Wave2D/Unit1.pas (form logic) and
     ufft_Wave.pas (numerical engine, now uWave2DGrid.pas - see that unit's
     own header comment for what changed and why). Displays the live
     evolving solution of TWave2DGrid as a TVMPlot3D height-field surface,
     same component 2DChebBVP_FPC and Graphs/Plot3D already use.

     Controls (same four as the original, same layout intent, just LCL
     controls instead of VCL ones):
       - RadioGroup1 selects the initial condition (TInitialFunc). Item
         order/captions match the original exactly ('Single Gaussian',
         'Centered Gaussian', 'Double Gaussian', 'Single Plane Wave') - note
         this does NOT match TInitialFunc's own declaration order
         (SingleG,DoubleG,CenteredG,SingleWave); RadioGroup1Click's case
         statement reproduces the original's own item-index-to-enum mapping
         exactly, not the enum's declaration order.
       - TrackBar1 controls animation speed via AnimTimer.Interval, the
         direct LCL equivalent of the original's GLCadencer1.FixedDeltaTime
         - higher trackbar position -> shorter interval -> Solve() called
         more often per second, matching the original's own
         "0.05/Position" formula (here: Round(50/Position) milliseconds).
       - btnRun/btnStop/btnReset and the Ready/Running/Halted status
         machine are a direct port of the original's SetStatus.

     Unlike the original - which used a bespoke GLHeightField height
     callback, a hand-rolled colorizer (uColorizer.pas), hand-placed
     GLFlatText/GLArrowLine axis labels, and its own mouse-drag-rotate/
     wheel-zoom camera handling - all of that is delegated entirely to
     TVMPlot3D here: height-field coloring, axis labels/ticks, and camera
     interaction are already built into the component (see
     Graphs/uVMPlot3D.pas's own header comment), so none of
     GLSceneViewer1MouseDown/MouseMove/FormMouseWheel/HeightField1GetHeight/
     uColorizer needed porting. FLightPad/LightPadChange follow the same
     TVMLightPad wiring 2DChebBVP_FPC and Graphs/Plot3D already established.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, uVMPlot3D, uVMLightPad, uWave2DGrid;

const
  ChebN = 32;   // matches the original T2DGrid.create(32)
  DispN = 65;   // display grid resolution (both axes) - see 2DChebBVP_FPC's
                // own header comment for the exact-midpoint rationale

type
  TWaveStatus = (wsReady, wsRunning, wsHalted);

  { TfmMain }

  TfmMain = class(TForm)
    ControlPanel: TPanel;
    RadioGroup1: TRadioGroup;
    SpeedLabel: TLabel;
    TrackBar1: TTrackBar;
    GroupBox1: TGroupBox;
    btnRun: TButton;
    btnStop: TButton;
    btnReset: TButton;
    AnimTimer: TTimer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
    procedure RadioGroup1Click(Sender: TObject);
    procedure AnimTimerTimer(Sender: TObject);
  private
    FGrid: TWave2DGrid;
    FPlot: TVMPlot3D;
    FLightPad: TVMLightPad;
    FInitialFunc: TInitialFunc;
    FStatus: TWaveStatus;
    procedure SetStatus(NewStatus: TWaveStatus);
    procedure LightPadChange(Sender: TObject);
    procedure DoReset;
  end;

var
  fmMain: TfmMain;

implementation

{$R *.lfm}

{ TfmMain }

procedure TfmMain.FormCreate(Sender: TObject);
var
  LightLabel: TLabel;
begin
  FInitialFunc := SingleG;
  FGrid := TWave2DGrid.Create(ChebN, DispN);

  FPlot := TVMPlot3D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := '2D Wave Equation: u_tt = u_xx + u_yy';
  FPlot.XAxisTitle := 'x';
  FPlot.YAxisTitle := 'y';
  FPlot.ZAxisTitle := 'u';
  // Label the X/Y axes with the actual solution-domain coordinate (PlotGrid
  // is sampled over an evenly-spaced [-1,1] display grid - see
  // TWave2DGrid.Create) rather than TVMPlot3D's default column/row index -
  // same reasoning as 2DChebBVP_FPC's own XAxisMin/Max/YAxisMin/Max use.
  FPlot.XAxisMin := -1;
  FPlot.XAxisMax := 1;
  FPlot.YAxisMin := -1;
  FPlot.YAxisMax := 1;
  // Z deliberately left at TVMPlot3D's default per-frame auto-fit rather
  // than a fixed ZAxisMin/ZAxisMax (see that property's own comment in
  // Graphs/uVMPlot3D.pas for the mechanism and why it was added): a fixed
  // range was tried here and does keep the zero level visually anchored as
  // the wave evolves, matching the original Delphi demo - the numerics
  // were already confirmed correct either way (the boundary is exactly
  // pinned in the raw solution grid regardless of how it's rendered - see
  // uWave2DGrid.pas's own header comment, PARALLELISM's final entry) - but
  // auto-fit's constantly-rescaling range was judged more visually
  // appealing for this demo, so kept as the default.
  FPlot.SetData(FGrid.PlotGrid);

  LightLabel := TLabel.Create(Self);
  LightLabel.Parent := ControlPanel;
  LightLabel.Left := 8;
  LightLabel.Top := 380;
  LightLabel.Caption := 'Light (drag)';
  FLightPad := TVMLightPad.Create(Self);
  FLightPad.Parent := ControlPanel;
  FLightPad.Left := 8;
  FLightPad.Top := 396;
  FLightPad.OnChange := @LightPadChange;
  FPlot.LightX := FLightPad.LightX;
  FPlot.LightY := FLightPad.LightY;

  AnimTimer.Interval := Round(50 / TrackBar1.Position);
  SetStatus(wsReady);
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FGrid.Free;
end;

procedure TfmMain.SetStatus(NewStatus: TWaveStatus);
begin
  FStatus := NewStatus;
  case FStatus of
    wsReady: begin
      btnRun.Enabled := True;
      btnStop.Enabled := False;
      btnReset.Enabled := False;
      AnimTimer.Enabled := False;
    end;
    wsRunning: begin
      btnRun.Enabled := False;
      btnStop.Enabled := True;
      btnReset.Enabled := False;
      AnimTimer.Enabled := True;
    end;
    wsHalted: begin
      btnRun.Enabled := True;
      btnStop.Enabled := False;
      btnReset.Enabled := True;
      AnimTimer.Enabled := False;
    end;
  end;
end;

procedure TfmMain.DoReset;
begin
  FGrid.InitialiseModel(FInitialFunc);
  FPlot.SetData(FGrid.PlotGrid);
  Caption := '2D Wave Equation: u_tt = u_xx + u_yy';
  SetStatus(wsHalted);
end;

procedure TfmMain.btnRunClick(Sender: TObject);
begin
  SetStatus(wsRunning);
end;

procedure TfmMain.btnStopClick(Sender: TObject);
begin
  SetStatus(wsHalted);
end;

procedure TfmMain.btnResetClick(Sender: TObject);
begin
  DoReset;
end;

procedure TfmMain.TrackBar1Change(Sender: TObject);
begin
  AnimTimer.Interval := Round(50 / TrackBar1.Position);
end;

procedure TfmMain.RadioGroup1Click(Sender: TObject);
begin
  case RadioGroup1.ItemIndex of
    0: FInitialFunc := SingleG;
    1: FInitialFunc := CenteredG;
    2: FInitialFunc := DoubleG;
    3: FInitialFunc := SingleWave;
  end;
  DoReset;
end;

procedure TfmMain.AnimTimerTimer(Sender: TObject);
var
  ElapsedUs: Int64;
begin
  ElapsedUs := FGrid.Solve;
  FPlot.SetData(FGrid.PlotGrid);
  Caption := Format('2D Wave Equation: u_tt = u_xx + u_yy   solve: %.2f ms   t = %.4f',
    [ElapsedUs / 1000, FGrid.t]);
end;

procedure TfmMain.LightPadChange(Sender: TObject);
begin
  FPlot.LightX := FLightPad.LightX;
  FPlot.LightY := FLightPad.LightY;
end;

end.
