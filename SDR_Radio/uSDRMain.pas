unit uSDRMain;

{*******************************************************************************

     Main form for the HackRF spectrum analyser. A TVMPlotStack (Graphs/
     uVMPlotStack.pas) - created and Parented to this form in code, same
     convention as Graphs/PlotStack's and Graphs/SpectrumDemo's own demo
     forms - is fed by EpochTimerTick, ~30 times/second, each tick pulling
     one 8192-sample complex IQ epoch off THackRFDevice's ring buffer
     (uHackRF.pas) via TryReadEpoch. At the full 20Msps default this is
     nowhere near draining every sample HackRF produces (that would be
     ~2441 epochs/second) - TryReadEpoch deliberately skips forward to the
     newest backlogged epoch each call (see its own comment), so the
     display always shows a live, up-to-date spectrum rather than slowly
     falling behind real time; the (very large) majority of raw samples
     are simply never looked at, exactly as a live spectrum analyser
     display is expected to behave.

     Per epoch, EpochTimerTick:
       1. TryReadEpoch returns a (1,8192) TVMobjZ of normalised complex
          IQ samples.
       2. newVMComplex.pas's PowerSpectrum(A: TVMobjZ): TVMobj - the same
          Hamming-window/FFT/|X|^2 building block Graphs/SpectrumDemo
          already uses for its (real-signal) synthetic demo - Hamming-
          windows and FFTs it, returning all 8192 bins of LINEAR power in
          standard (non-centred) FFT bin order: bin 0 is DC, bins
          1..4095 are increasingly positive baseband frequencies, bins
          4096..8191 are increasingly-less-negative frequencies back up
          to just below DC.
       3. That's reordered to ascending-frequency (most-negative first)
          via an FFT shift - built from newVM.pas's own SubMatrix/MergeLR
          (SubMatrix picks out each half, MergeLR places the upper-half
          bins first) rather than a hand-rolled swap loop, the same "reuse
          the existing matrix primitives" convention the rest of newVM
          follows.
       4. Converted to dB (10*Log10(P+eps), same epsilon convention as
          SpectrumDemo) and pushed via FPlot.AddGraph.

     TVMPlotStack.UseFrequencyAxis/XAxisMin/XAxisMax (added to
     uVMPlotStack.pas for this) are kept in sync with THackRFDevice's
     actual CenterFreqHz/SampleRateHz by UpdateFrequencyAxis, called after
     every successful StartRX or live retune - with the 95MHz/20Msps
     defaults this yields exactly the requested 85-105MHz span, and stays
     correct if the user changes either control.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, newVMComplex, uVMPlotStack, uHackRF;

const
  EpochSize = 8192;

type

  { TForm1 }

  TForm1 = class(TForm)
    AmpCheckBox: TCheckBox;
    ConnectButton: TButton;
    ControlPanel: TPanel;
    FreqEdit: TFloatSpinEdit;
    FreqLabel: TLabel;
    HintLabel: TLabel;
    LNAGainLabel: TLabel;
    LNATrackBar: TTrackBar;
    PeakDetectCheckBox: TCheckBox;
    RateCombo: TComboBox;
    RateLabel: TLabel;
    ResetViewButton: TButton;
    ShowAxesCheckBox: TCheckBox;
    StartStopButton: TButton;
    StatusLabel: TLabel;
    VGAGainLabel: TLabel;
    VGATrackBar: TTrackBar;
    procedure AmpCheckBoxChange(Sender: TObject);
    procedure ConnectButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FreqEditEditingDone(Sender: TObject);
    procedure LNATrackBarChange(Sender: TObject);
    procedure PeakDetectCheckBoxChange(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure StartStopButtonClick(Sender: TObject);
    procedure VGATrackBarChange(Sender: TObject);
  private
    FPlot: TVMPlotStack;
    FDevice: THackRFDevice;
    FEpochTimer: TTimer;
    procedure EpochTimerTick(Sender: TObject);
    procedure UpdateFrequencyAxis;
    procedure ReportError(const Where: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FDevice := THackRFDevice.Create;

  FPlot := TVMPlotStack.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'HackRF Spectrum Analyser';
  FPlot.XAxisTitle := 'Frequency (MHz)';
  FPlot.YAxisTitle := 'Power (dB)';
  FPlot.ZAxisTitle := 'Time';
  FPlot.MaxSeries := 60;
  FPlot.ClearStack;   // discard the component's own default demo data
  UpdateFrequencyAxis;   // shows the 85-105MHz default span even before Start

  FEpochTimer := TTimer.Create(Self);
  FEpochTimer.Interval := 30;
  FEpochTimer.Enabled := False;
  FEpochTimer.OnTimer := @EpochTimerTick;

  LNAGainLabel.Caption := Format('LNA Gain: %d dB', [LNATrackBar.Position]);
  VGAGainLabel.Caption := Format('VGA Gain: %d dB', [VGATrackBar.Position]);

  if HackRFLibLoaded then
    StatusLabel.Caption := 'Not connected'
  else
    StatusLabel.Caption := 'libhackrf runtime library not found';
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FEpochTimer) then FEpochTimer.Enabled := False;
  FDevice.Free;   // stops RX and closes the device itself, if still open
end;

procedure TForm1.ReportError(const Where: string);
begin
  StatusLabel.Caption := 'Error (' + Where + '): ' + FDevice.LastError;
end;

// (CenterFreqHz -+ SampleRateHz/2), in MHz - the default 95MHz/20Msps
// values yield exactly the requested 85-105MHz span; recomputed after
// every successful StartRX or live retune so the axis always matches
// what the device is actually doing.
procedure TForm1.UpdateFrequencyAxis;
begin
  FPlot.UseFrequencyAxis := True;
  FPlot.XAxisMin := (FDevice.CenterFreqHz - FDevice.SampleRateHz / 2) / 1e6;
  FPlot.XAxisMax := (FDevice.CenterFreqHz + FDevice.SampleRateHz / 2) / 1e6;
end;

procedure TForm1.ConnectButtonClick(Sender: TObject);
begin
  if FDevice.IsOpen then begin
    if FDevice.IsStreaming then StartStopButtonClick(Sender);   // stop first
    FDevice.Close;
    ConnectButton.Caption := 'Connect';
    StartStopButton.Enabled := False;
    StatusLabel.Caption := 'Not connected';
    Exit;
  end;

  if FDevice.Open then begin
    ConnectButton.Caption := 'Disconnect';
    StartStopButton.Enabled := True;
    StatusLabel.Caption := 'Connected (idle)';
  end else
    ReportError('open');
end;

// Applies the current UI settings (sample rate first - StartRX derives
// the baseband filter bandwidth from it - then frequency, gains, amp)
// and starts streaming; the reverse (stop) just tears streaming down.
// RateCombo is disabled while streaming, since changing sample rate
// invalidates the running epoch cadence/filter setup - stop first to
// pick a different one.
procedure TForm1.StartStopButtonClick(Sender: TObject);
var
  RateHz: Double;
begin
  if FDevice.IsStreaming then begin
    FEpochTimer.Enabled := False;
    if not FDevice.StopRX then ReportError('stop_rx');
    StartStopButton.Caption := 'Start';
    RateCombo.Enabled := True;
    StatusLabel.Caption := 'Connected (idle)';
    Exit;
  end;

  RateHz := StrToFloatDef(RateCombo.Text, 20) * 1e6;
  if not FDevice.SetSampleRateHz(RateHz) then begin ReportError('set_sample_rate'); Exit; end;
  if not FDevice.SetFrequencyHz(Round(FreqEdit.Value * 1e6)) then begin ReportError('set_freq'); Exit; end;
  FDevice.SetLNAGain(LNATrackBar.Position);
  FDevice.SetVGAGain(VGATrackBar.Position);
  FDevice.SetAmpEnable(AmpCheckBox.Checked);

  if not FDevice.StartRX then begin ReportError('start_rx'); Exit; end;

  UpdateFrequencyAxis;
  RateCombo.Enabled := False;
  StartStopButton.Caption := 'Stop';
  StatusLabel.Caption := Format('Streaming @ %.3f MHz, %.0f Msps',
    [FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  FEpochTimer.Enabled := True;
end;

// Live retune - hackrf_set_freq (and hence THackRFDevice.SetFrequencyHz)
// works whether or not RX is currently running.
procedure TForm1.FreqEditEditingDone(Sender: TObject);
begin
  if not FDevice.IsOpen then Exit;
  if FDevice.SetFrequencyHz(Round(FreqEdit.Value * 1e6)) then begin
    UpdateFrequencyAxis;
    if FDevice.IsStreaming then
      StatusLabel.Caption := Format('Streaming @ %.3f MHz, %.0f Msps',
        [FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  end else
    ReportError('set_freq');
end;

// LNA gain only accepts 8dB steps - snaps any in-between mouse-drag
// position down to the nearest valid one (re-assigning Position re-enters
// this handler once more with V already a multiple of 8, so it falls
// through to the label/device update below without looping further).
procedure TForm1.LNATrackBarChange(Sender: TObject);
var
  V: Integer;
begin
  V := (LNATrackBar.Position div 8) * 8;
  if V <> LNATrackBar.Position then begin
    LNATrackBar.Position := V;
    Exit;
  end;
  LNAGainLabel.Caption := Format('LNA Gain: %d dB', [V]);
  if FDevice.IsOpen then FDevice.SetLNAGain(V);
end;

// VGA gain only accepts 2dB steps - same snap-and-reenter approach as
// LNATrackBarChange above.
procedure TForm1.VGATrackBarChange(Sender: TObject);
var
  V: Integer;
begin
  V := (VGATrackBar.Position div 2) * 2;
  if V <> VGATrackBar.Position then begin
    VGATrackBar.Position := V;
    Exit;
  end;
  VGAGainLabel.Caption := Format('VGA Gain: %d dB', [V]);
  if FDevice.IsOpen then FDevice.SetVGAGain(V);
end;

procedure TForm1.AmpCheckBoxChange(Sender: TObject);
begin
  if FDevice.IsOpen then FDevice.SetAmpEnable(AmpCheckBox.Checked);
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.PeakDetectCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowPeakLabels := PeakDetectCheckBox.Checked;
end;

procedure TForm1.ResetViewButtonClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

procedure TForm1.EpochTimerTick(Sender: TObject);
var
  IQ: TVMobjZ;
  LinearPower, Shifted, PowerSpec: TVMobj;
  HalfN, k: Integer;
begin
  if not FDevice.TryReadEpoch(EpochSize, IQ) then Exit;

  LinearPower := PowerSpectrum(IQ);   // newVMComplex.pas - Hamming window + FFT + |X|^2

  HalfN := EpochSize div 2;
  // FFT shift: negative-frequency bins (upper half of LinearPower) first,
  // then DC and positive-frequency bins - ascending frequency order,
  // matching FPlot.XAxisMin..XAxisMax.
  Shifted := MergeLR(SubMatrix(LinearPower, 0, HalfN, 1, HalfN),
                      SubMatrix(LinearPower, 0, 0, 1, HalfN));

  PowerSpec := TVMobj.Create(1, EpochSize);
  for k := 0 to EpochSize - 1 do
    PowerSpec[0, k] := 10 * Log10(Shifted[0, k] + 1e-12);

  FPlot.AddGraph(PowerSpec);
end;

end.
