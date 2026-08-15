unit uspectrummain;

{*******************************************************************************

     Main form for the SpectrumDemo. On every FTimer tick (TimerTick),
     builds a fresh 4096-point power spectrum from scratch and pushes it
     into a TVMPlotStack (Graphs/uVMPlotStack.pas) - created and parented
     to this form in code, same as the other Graphs/ demos use their own
     TVMPlot2D/TVMPlot3D/TVMPlotStack - via AddGraph, so the resulting
     push cadence is itself what produces the waterfall's flowing motion.
     RateTrackBar (RateTrackBarChange) sets FTimer.Interval directly,
     anywhere from 20ms (~50 pushes/second, the fastest/default) down to
     1000ms (one push/second, the slowest) - see that method's own
     comment. TVMPlotStack's own Animate property (continuous between-push
     recession - see uVMPlotStack.pas's own ANIMATE rationale) is
     deliberately left at its default False at every rate: pushing a new
     graph already advances the stack, and turning Animate on as well
     would just make already-pushed slices drift an extra, uncontrolled
     amount between pushes on top of that - doubly noticeable, not
     smoother, at the slider's slow end.

     Per push, TimerTick:
       1. Fills a (1,SignalLength) TVMobj with fresh white noise -
          RandG(0,1) in a plain loop, NOT newVM's own TVMobj.fillRandom:
          fillRandom reseeds a fixed constant (777) on every call
          specifically so it's deterministic for the test suite (see
          newVM.pas's own header comment and newVMTests.pas's
          TestFillRandomDeterministic) - calling it here would push the
          exact same "random" vector every 20ms, i.e. a frozen spectrum,
          not a live one.
       2. Adds a fixed square-wave tone (FSquareWave, built once in
          FormCreate - see BuildSquareWave's own comment) via the ordinary
          same-type TVMobj '+' operator, so the spectrum shows a
          recognisable family of peaks (the tone's fundamental and odd
          harmonics) standing up out of the noise floor, rather than pure
          noise with nothing to visually anchor on.
       3. Multiplies the result elementwise by a Hamming window built once
          in FormCreate (FWindow) via the ordinary same-type TVMobj '*'
          operator, which newVM.pas's own header (and CLAUDE.md) documents
          as elementwise (Hadamard) for two same-type TVMobj operands -
          exactly what windowing needs, not a matrix product.
       4. FFT's the windowed signal via newVMComplex.pas's FFT_R2C
          (FFTW3-backed real-to-complex transform), returning the packed
          half-spectrum of length SignalLength div 2 + 1 (2049 for
          SignalLength=4096).
       5. Reduces that to a SpectrumLength=SignalLength div 2 (2048)
          -point power spectrum in dB (10*Log10(re^2+im^2+eps), eps
          guarding the log against an exact-zero bin) - one point per FFT
          bin from DC up to (but not including) the Nyquist bin, which is
          dropped purely to land on the requested round 2048 rather than
          FFT_R2C's own 2049.
       6. FPlot.AddGraph's the result - TVMPlotStack's own auto-fit value
          range (see its RecomputeBounds) rescales to whatever range these
          dB values actually span, no manual scaling needed here.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls,
  OneAPI, newVM, newVMComplex, uVMPlotStack;

const
  SignalLength = 4096;
  SpectrumLength = SignalLength div 2;   // 2048 - drops FFT_R2C's Nyquist bin

  // The imposed tone: a square wave completing exactly SquareWaveBin
  // cycles over the SignalLength-sample block - see BuildSquareWave's own
  // comment for why an integer bin count here is what keeps its harmonics
  // landing on exact FFT bins too, rather than smeared across several.
  // Chosen well clear of bin 0 (rather than e.g. a low bin like 60) so the
  // fundamental and its first couple of harmonics (900, 1500 - the next,
  // 2100, falls past SpectrumLength and is simply absent) sit spread
  // across the middle of the display, not crowded against the Bin axis
  // at the left edge where they're hard to pick out visually.
  SquareWaveBin = 300;
  SquareWaveAmplitude = 3.0;

type

  { TForm1 }

  TForm1 = class(TForm)
    ControlPanel: TPanel;
    ShowAxesCheckBox: TCheckBox;
    ResetViewButton: TButton;
    RateLabel: TLabel;
    RateTrackBar: TTrackBar;
    HintLabel: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure RateTrackBarChange(Sender: TObject);
  private
    FPlot: TVMPlotStack;
    FTimer: TTimer;
    FWindow: TVMobj;
    FSquareWave: TVMobj;
    procedure TimerTick(Sender: TObject);
    function BuildHammingWindow(N: Integer): TVMobj;
    function BuildSquareWave(N, FundamentalBin: Integer; Amplitude: Double): TVMobj;
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
  FSquareWave := BuildSquareWave(SignalLength, SquareWaveBin, SquareWaveAmplitude);

  FTimer := TTimer.Create(Self);
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
  // RateTrackBar.Position (set in the .lfm, 20ms) is the single source of
  // truth for the starting interval - this call both sets FTimer.Interval
  // from it and syncs RateLabel's text, the same thing RateTrackBarChange
  // does on every subsequent user drag, rather than duplicating "20" here.
  RateTrackBarChange(Self);
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

// A +-Amplitude square wave completing exactly FundamentalBin cycles over
// N samples (via the sign of a sine at that same bin, rather than a
// separate period/duty-cycle computation - simplest way to guarantee an
// exact integer cycle count). Built once in FormCreate, like FWindow,
// since it's the same fixed tone added to every tick's fresh noise - a
// square wave's Fourier series is the fundamental plus odd harmonics
// (3x, 5x, 7x, ...) at 1/3, 1/5, 1/7 ... of its amplitude, and because
// FundamentalBin is an integer, every one of those harmonics is *also*
// an integer bin - so the spectrum shows a whole family of clean,
// unsmeared peaks (at FundamentalBin, 3*FundamentalBin, 5*FundamentalBin,
// ...) rather than just one.
function TForm1.BuildSquareWave(N, FundamentalBin: Integer; Amplitude: Double): TVMobj;
var
  S: TVMobj;
  i: Integer;
begin
  S := TVMobj.Create(1, N);
  for i := 0 to N - 1 do
    if Sin(2 * Pi * FundamentalBin * i / N) >= 0 then
      S[0, i] := Amplitude
    else
      S[0, i] := -Amplitude;
  result := S;
end;

procedure TForm1.TimerTick(Sender: TObject);
var
  Raw, Toned, Windowed, PowerSpec: TVMobj;
  Spectrum: TVMobjZ;
  k: Integer;
  bin: TComplex16;
begin
  Raw := TVMobj.Create(1, SignalLength);
  for k := 0 to SignalLength - 1 do
    Raw[0, k] := RandG(0, 1);

  Toned := Raw + FSquareWave;
  Windowed := Toned * FWindow;
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

// RateTrackBar spans [20,1000] ms directly (its own Min/Max, set in the
// .lfm) - one spectrum push every 20ms (~50/s) at the fast end, one per
// second at the slow end, per the user's own ask. FTimer.Interval is set
// straight from the slider position; RateLabel's text is derived from it
// (1000/interval, rounded) purely for display, not a separate setting.
procedure TForm1.RateTrackBarChange(Sender: TObject);
begin
  FTimer.Interval := RateTrackBar.Position;
  RateLabel.Caption := Format('Generation rate: %d/s (%d ms)',
    [Round(1000 / RateTrackBar.Position), RateTrackBar.Position]);
end;

end.
