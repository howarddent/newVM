unit uspectrummain;

{*******************************************************************************

     Main form for the SpectrumDemo. Every 20ms (FTimer/TimerTick), builds a
     fresh 4096-point power spectrum from scratch and pushes it into a
     TVMPlotStack (Graphs/uVMPlotStack.pas) - created and parented to this
     form in code, same as the other Graphs/ demos use their own
     TVMPlot2D/TVMPlot3D/TVMPlotStack - via AddGraph, so the resulting
     ~50-pushes/second cadence is itself what produces the waterfall's
     flowing motion. TVMPlotStack's own Animate property (continuous
     between-push recession - see uVMPlotStack.pas's own ANIMATE
     rationale) is deliberately left at its default False: pushing a new
     graph roughly every 20ms already advances the stack fast enough to
     read as continuous motion, and turning Animate on as well would just
     make already-pushed slices drift an extra, uncontrolled amount
     between pushes on top of that.

     Per push, TimerTick:
       1. Fills a (1,SignalLength) TVMobj with fresh white noise -
          RandG(0,1) in a plain loop, NOT newVM's own TVMobj.fillRandom:
          fillRandom reseeds a fixed constant (777) on every call
          specifically so it's deterministic for the test suite (see
          newVM.pas's own header comment and newVMTests.pas's
          TestFillRandomDeterministic) - calling it here would push the
          exact same "random" vector every 20ms, i.e. a frozen spectrum,
          not a live one.
       2. Multiplies it elementwise by a Hamming window built once in
          FormCreate (FWindow) via the ordinary same-type TVMobj '*'
          operator, which newVM.pas's own header (and CLAUDE.md) documents
          as elementwise (Hadamard) for two same-type TVMobj operands -
          exactly what windowing needs, not a matrix product.
       3. FFT's the windowed signal via newVMComplex.pas's FFT_R2C
          (FFTW3-backed real-to-complex transform), returning the packed
          half-spectrum of length SignalLength div 2 + 1 (2049 for
          SignalLength=4096).
       4. Reduces that to a SpectrumLength=SignalLength div 2 (2048)
          -point power spectrum in dB (10*Log10(re^2+im^2+eps), eps
          guarding the log against an exact-zero bin) - one point per FFT
          bin from DC up to (but not including) the Nyquist bin, which is
          dropped purely to land on the requested round 2048 rather than
          FFT_R2C's own 2049.
       5. FPlot.AddGraph's the result - TVMPlotStack's own auto-fit value
          range (see its RecomputeBounds) rescales to whatever range these
          dB values actually span, no manual scaling needed here.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls,
  OneAPI, newVM, newVMComplex, uVMPlotStack;

const
  SignalLength = 4096;
  SpectrumLength = SignalLength div 2;   // 2048 - drops FFT_R2C's Nyquist bin

type

  { TForm1 }

  TForm1 = class(TForm)
    ControlPanel: TPanel;
    ShowAxesCheckBox: TCheckBox;
    ResetViewButton: TButton;
    HintLabel: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
  private
    FPlot: TVMPlotStack;
    FTimer: TTimer;
    FWindow: TVMobj;
    procedure TimerTick(Sender: TObject);
    function BuildHammingWindow(N: Integer): TVMobj;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Randomize;   // free-running seed - see TimerTick's own comment for why
               // this demo generates its noise via RandG, not fillRandom

  FPlot := TVMPlotStack.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'Live Power Spectrum';
  FPlot.XAxisTitle := 'Bin';
  FPlot.YAxisTitle := 'Power (dB)';
  FPlot.ZAxisTitle := 'Time';
  FPlot.MaxSeries := 60;
  FPlot.ClearStack;   // discard the component's own default demo data

  FWindow := BuildHammingWindow(SignalLength);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 20;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FTimer.Enabled := False;
end;

// w[n] = 0.54 - 0.46*cos(2*pi*n/(N-1)), n=0..N-1 - the standard Hamming
// window. Built once here rather than in TimerTick, since it never
// changes once SignalLength is fixed.
function TForm1.BuildHammingWindow(N: Integer): TVMobj;
var
  W: TVMobj;
  i: Integer;
begin
  W := TVMobj.Create(1, N);
  for i := 0 to N - 1 do
    W[0, i] := 0.54 - 0.46 * Cos(2 * Pi * i / (N - 1));
  result := W;
end;

procedure TForm1.TimerTick(Sender: TObject);
var
  Raw, Windowed, PowerSpec: TVMobj;
  Spectrum: TVMobjZ;
  k: Integer;
  bin: TComplex16;
begin
  Raw := TVMobj.Create(1, SignalLength);
  for k := 0 to SignalLength - 1 do
    Raw[0, k] := RandG(0, 1);

  Windowed := Raw * FWindow;
  Spectrum := FFT_R2C(Windowed);

  PowerSpec := TVMobj.Create(1, SpectrumLength);
  for k := 0 to SpectrumLength - 1 do begin
    bin := Spectrum[0, k];
    PowerSpec[0, k] := 10 * Log10(bin.re * bin.re + bin.im * bin.im + 1e-12);
  end;

  FPlot.AddGraph(PowerSpec);
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.ResetViewButtonClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

end.
