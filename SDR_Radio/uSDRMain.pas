unit uSDRMain;

{*******************************************************************************

     Main form for the spectrum analyser. Talks only to the abstract
     TSDRDevice interface (uSDRDevice.pas) - never to THackRFDevice
     (uHackRF.pas) or TRTLSDRDevice (uRTLSDR.pas) directly - so it works
     identically regardless of which hardware is actually attached. A
     TVMPlotStack (Graphs/uVMPlotStack.pas) - created and Parented to this
     form in code, same convention as Graphs/PlotStack's and
     Graphs/SpectrumDemo's own demo forms - is fed by EpochTimerTick, up
     to ~30 times/second, each tick pulling one 8192-sample complex IQ
     epoch off FDevice's ring buffer via TryReadEpoch. TryReadEpoch
     deliberately skips forward to the newest backlogged epoch each call
     (see uSDRDevice.pas's TSDRRingBuffer), so the display always shows a
     live, up-to-date spectrum rather than falling behind real time,
     however much faster the device's own sample rate is than the GUI
     timer's cadence.

     AUTODETECTION: ConnectButtonClick doesn't assume any particular
     hardware - DetectAndOpenDevice tries THackRFDevice then
     TRTLSDRDevice in turn (actually attempting Open on each, not just
     checking whether a library loaded - a library can be installed with
     no matching hardware attached), and whichever one successfully opens
     becomes FDevice.

     CAPABILITY-DRIVEN UI: once a device is open, ApplyDeviceCapabilities
     reconfigures the control panel from FDevice.Capabilities -
     FreqEdit's bounds, RateCombo's offered sample rates, and up to three
     generic gain-stage controls (GainStage0/1 as trackbars for
     continuous or discrete-list stages, GainStage2 as a checkbox for a
     boolean stage - see that method's own comment for the slot-filling
     rule) relabelled and shown/hidden per Capabilities.GainStages. This
     is what makes the window itself look different for HackRF (three
     visible controls: LNA/VGA/RF Amp) versus RTL-SDR (two: Tuner
     Gain/Auto Gain) without any hardcoded "if HackRF then ... else
     ..." branch in the layout code - the whole panel is driven by
     whatever Capabilities the connected device actually reports.

     Per epoch, EpochTimerTick:
       1. TryReadEpoch returns a (1,8192) TVMobjZ of normalised,
          DC/I-Q-balance-corrected complex IQ samples (uSDRDevice.pas's
          CorrectIQEpoch, called inside each device's own TryReadEpoch).
       2. newVMComplex.pas's PowerSpectrum(A: TVMobjZ): TVMobj
          Hamming-windows and FFTs it, returning all 8192 bins of LINEAR
          power in standard (non-centred) FFT bin order.
       3. That's reordered to ascending-frequency (most-negative first)
          via an FFT shift - built from newVM.pas's own SubMatrix/MergeLR
          rather than a hand-rolled swap loop.
       4. Converted to dB (10*Log10(P+eps)) and pushed via FPlot.AddGraph.

     TVMPlotStack.UseFrequencyAxis/XAxisMin/XAxisMax are kept in sync with
     FDevice's actual CenterFreqHz/SampleRateHz by UpdateFrequencyAxis,
     called after every successful StartRX or live retune.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, newVMComplex, uVMPlotStack, uSDRDevice, uHackRF, uRTLSDR;

const
  EpochSize = 8192;

type

  { TForm1 }

  TForm1 = class(TForm)
    ConnectButton: TButton;
    ControlPanel: TPanel;
    FreqEdit: TFloatSpinEdit;
    FreqLabel: TLabel;
    GainStage0Label: TLabel;
    GainStage0TrackBar: TTrackBar;
    GainStage1Label: TLabel;
    GainStage1TrackBar: TTrackBar;
    GainStage2CheckBox: TCheckBox;
    HintLabel: TLabel;
    PeakDetectCheckBox: TCheckBox;
    PeakThresholdLabel: TLabel;
    PeakThresholdTrackBar: TTrackBar;
    RateCombo: TComboBox;
    RateLabel: TLabel;
    ResetViewButton: TButton;
    ShowAxesCheckBox: TCheckBox;
    StartStopButton: TButton;
    StatusLabel: TLabel;
    procedure ConnectButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FreqEditEditingDone(Sender: TObject);
    procedure GainStage0TrackBarChange(Sender: TObject);
    procedure GainStage1TrackBarChange(Sender: TObject);
    procedure GainStage2CheckBoxChange(Sender: TObject);
    procedure PeakDetectCheckBoxChange(Sender: TObject);
    procedure PeakThresholdTrackBarChange(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure StartStopButtonClick(Sender: TObject);
  private
    FPlot: TVMPlotStack;
    FDevice: TSDRDevice;
    FEpochTimer: TTimer;
    function DetectAndOpenDevice(out ErrMsg: string): TSDRDevice;
    procedure ApplyDeviceCapabilities;
    procedure ApplyGainStageControl(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure ApplyAllGains;
    procedure EpochTimerTick(Sender: TObject);
    procedure UpdateFrequencyAxis;
    procedure UpdatePeakThreshold;
    procedure ReportError(const Where: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FPlot := TVMPlotStack.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'Spectrum Analyser';
  FPlot.XAxisTitle := 'Frequency (MHz)';
  FPlot.YAxisTitle := 'Power (dB)';
  FPlot.ZAxisTitle := 'Time';
  FPlot.MaxSeries := 60;
  FPlot.ClearStack;   // discard the component's own default demo data

  FEpochTimer := TTimer.Create(Self);
  FEpochTimer.Interval := 30;
  FEpochTimer.Enabled := False;
  FEpochTimer.OnTimer := @EpochTimerTick;

  StatusLabel.Caption := 'Not connected';
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

// Tries each known backend in turn, actually attempting Open (not just
// checking whether its runtime library loaded - that only proves the
// library is installed, not that this specific hardware is attached).
// Whichever opens first wins; if HackRF and an RTL-SDR are both attached
// simultaneously, HackRF is preferred purely by trying it first - no
// other significance to the order. Returns nil (with a combined ErrMsg)
// if neither responds.
function TForm1.DetectAndOpenDevice(out ErrMsg: string): TSDRDevice;
var
  HackRF: THackRFDevice;
  RTLSDR: TRTLSDRDevice;
  Reasons: string;
begin
  Result := nil;
  Reasons := '';

  HackRF := THackRFDevice.Create;
  if HackRF.Open then begin
    Result := HackRF;
    Exit;
  end;
  Reasons := 'HackRF: ' + HackRF.LastError;
  HackRF.Free;

  RTLSDR := TRTLSDRDevice.Create;
  if RTLSDR.Open then begin
    Result := RTLSDR;
    Exit;
  end;
  Reasons := Reasons + '; RTL-SDR: ' + RTLSDR.LastError;
  RTLSDR.Free;

  ErrMsg := 'no SDR device found (' + Reasons + ')';
end;

// Configures GainStage0/1 (trackbars, for a gkContinuous or
// gkDiscreteList stage) or GainStage2 (a checkbox, for the first
// gkBoolean stage) from Capabilities.GainStages[StageIndex] - see this
// unit's own header comment for the "numeric stages fill slots 0/1 in
// order, first boolean stage fills slot 2" rule. A discrete-list stage's
// trackbar Position is an INDEX into DiscreteValues, not the value
// itself (irregular gain lists, e.g. RTL-SDR's 29 non-uniform steps,
// don't map onto a linear trackbar any other way); a continuous stage's
// Position IS the value directly, matching its own Min/Max/Step.
procedure TForm1.ApplyGainStageControl(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
var
  Stage: TSDRGainStage;
begin
  if (StageIndex < 0) or (StageIndex > High(FDevice.Capabilities.GainStages)) then begin
    Lbl.Visible := False;
    Bar.Visible := False;
    Exit;
  end;
  Stage := FDevice.Capabilities.GainStages[StageIndex];

  Lbl.Visible := True;
  Bar.Visible := True;
  case Stage.Kind of
    gkContinuous: begin
      Bar.Min := Round(Stage.Min);
      Bar.Max := Round(Stage.Max);
      Bar.Frequency := Max(Round(Stage.Step), 1);
      Bar.Position := Bar.Min;
      Lbl.Caption := Format('%s: %d', [Stage.Name, Bar.Position]);
    end;
    gkDiscreteList: begin
      Bar.Min := 0;
      Bar.Max := Max(High(Stage.DiscreteValues), 0);
      Bar.Frequency := 1;
      Bar.Position := Bar.Max div 2;   // a reasonable mid-range default
      if Length(Stage.DiscreteValues) > 0 then
        Lbl.Caption := Format('%s: %.1f dB', [Stage.Name, Stage.DiscreteValues[Bar.Position]])
      else
        Lbl.Caption := Stage.Name + ': n/a';
    end;
  end;
end;

// Common body for GainStage0TrackBarChange/GainStage1TrackBarChange -
// updates the label and, if a device is open, pushes the resulting real
// value through FDevice.SetGain. Discrete-list stages look the actual
// dB value up from Position (an index); continuous stages use Position
// directly, snapped to the stage's own Step first (same snap-and-reenter
// pattern the original LNA/VGA handlers used, generalised).
procedure TForm1.GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
var
  Stage: TSDRGainStage;
  V: Integer;
  Value: Double;
begin
  if (StageIndex < 0) or (StageIndex > High(FDevice.Capabilities.GainStages)) then Exit;
  Stage := FDevice.Capabilities.GainStages[StageIndex];

  case Stage.Kind of
    gkContinuous: begin
      V := Round(Stage.Step) * Round(Bar.Position / Max(Round(Stage.Step), 1));
      if V <> Bar.Position then begin
        Bar.Position := V;   // re-enters this handler with Position already snapped
        Exit;
      end;
      Value := V;
      Lbl.Caption := Format('%s: %d', [Stage.Name, V]);
    end;
    gkDiscreteList: begin
      if Length(Stage.DiscreteValues) = 0 then Exit;
      Value := Stage.DiscreteValues[Bar.Position];
      Lbl.Caption := Format('%s: %.1f dB', [Stage.Name, Value]);
    end;
  else
    Exit;
  end;

  if FDevice.IsOpen then FDevice.SetGain(StageIndex, Value);
end;

procedure TForm1.GainStage0TrackBarChange(Sender: TObject);
begin
  GainStageTrackBarChanged(0, GainStage0Label, GainStage0TrackBar);
end;

procedure TForm1.GainStage1TrackBarChange(Sender: TObject);
begin
  GainStageTrackBarChanged(1, GainStage1Label, GainStage1TrackBar);
end;

procedure TForm1.GainStage2CheckBoxChange(Sender: TObject);
begin
  if FDevice.IsOpen then FDevice.SetGain(2, Ord(GainStage2CheckBox.Checked));
end;

// Re-applies every currently-visible gain stage's control value to the
// device - called once from StartStopButtonClick before starting RX, so
// a device picks up whatever the user set the sliders/checkbox to before
// pressing Start (mirroring the individual OnChange handlers, which only
// apply live once already open/streaming).
procedure TForm1.ApplyAllGains;
begin
  if GainStage0TrackBar.Visible then GainStageTrackBarChanged(0, GainStage0Label, GainStage0TrackBar);
  if GainStage1TrackBar.Visible then GainStageTrackBarChanged(1, GainStage1Label, GainStage1TrackBar);
  if GainStage2CheckBox.Visible then FDevice.SetGain(2, Ord(GainStage2CheckBox.Checked));
end;

// Rebuilds the whole control panel from FDevice.Capabilities - see this
// unit's own header comment for the overall rationale. Called once, from
// ConnectButtonClick, right after a device is successfully opened.
procedure TForm1.ApplyDeviceCapabilities;
var
  Caps: TSDRCapabilities;
  i, NumericSlot: Integer;
  BooleanStage: Integer;
begin
  Caps := FDevice.Capabilities;

  Caption := 'newVM ' + Caps.DeviceName + ' Spectrum Analyser';
  FPlot.Title := Caps.DeviceName + ' Spectrum Analyser';

  FreqEdit.MinValue := Caps.MinFreqHz / 1e6;
  FreqEdit.MaxValue := Caps.MaxFreqHz / 1e6;
  FreqEdit.Value := Caps.DefaultFreqHz / 1e6;

  RateCombo.Items.Clear;
  for i := 0 to High(Caps.SampleRates) do
    RateCombo.Items.Add(FormatFloat('0.###', Caps.SampleRates[i] / 1e6));
  RateCombo.ItemIndex := RateCombo.Items.IndexOf(FormatFloat('0.###', Caps.DefaultSampleRateHz / 1e6));
  if RateCombo.ItemIndex < 0 then RateCombo.ItemIndex := RateCombo.Items.Count - 1;

  // Numeric (continuous/discrete-list) stages fill slots 0 then 1, in
  // Capabilities.GainStages' own order; the first boolean stage fills
  // slot 2 - see this unit's header comment.
  NumericSlot := 0;
  BooleanStage := -1;
  ApplyGainStageControl(-1, GainStage0Label, GainStage0TrackBar);
  ApplyGainStageControl(-1, GainStage1Label, GainStage1TrackBar);
  GainStage2CheckBox.Visible := False;

  for i := 0 to High(Caps.GainStages) do begin
    case Caps.GainStages[i].Kind of
      gkContinuous, gkDiscreteList: begin
        if NumericSlot = 0 then ApplyGainStageControl(i, GainStage0Label, GainStage0TrackBar)
        else if NumericSlot = 1 then ApplyGainStageControl(i, GainStage1Label, GainStage1TrackBar);
        Inc(NumericSlot);
      end;
      gkBoolean:
        if BooleanStage < 0 then BooleanStage := i;
    end;
  end;

  if BooleanStage >= 0 then begin
    GainStage2CheckBox.Visible := True;
    GainStage2CheckBox.Checked := False;
    GainStage2CheckBox.Caption := Caps.GainStages[BooleanStage].Name;
  end;
end;

procedure TForm1.ConnectButtonClick(Sender: TObject);
var
  ErrMsg: string;
begin
  if Assigned(FDevice) then begin
    if FDevice.IsStreaming then StartStopButtonClick(Sender);   // stop first
    FDevice.Free;
    FDevice := nil;
    ConnectButton.Caption := 'Connect';
    StartStopButton.Enabled := False;
    GainStage0Label.Visible := False; GainStage0TrackBar.Visible := False;
    GainStage1Label.Visible := False; GainStage1TrackBar.Visible := False;
    GainStage2CheckBox.Visible := False;
    RateCombo.Items.Clear;
    Caption := 'newVM SDR Spectrum Analyser';
    StatusLabel.Caption := 'Not connected';
    Exit;
  end;

  FDevice := DetectAndOpenDevice(ErrMsg);
  if not Assigned(FDevice) then begin
    StatusLabel.Caption := 'Error: ' + ErrMsg;
    Exit;
  end;

  ApplyDeviceCapabilities;
  UpdateFrequencyAxis;
  ConnectButton.Caption := 'Disconnect';
  StartStopButton.Enabled := True;
  StatusLabel.Caption := 'Connected (' + FDevice.Capabilities.DeviceName + ', idle)';
end;

// (CenterFreqHz -+ SampleRateHz/2), in MHz - recomputed after every
// successful StartRX or live retune so the axis always matches what the
// device is actually doing, whatever its sample rate.
procedure TForm1.UpdateFrequencyAxis;
begin
  FPlot.UseFrequencyAxis := True;
  FPlot.XAxisMin := (FDevice.CenterFreqHz - FDevice.SampleRateHz / 2) / 1e6;
  FPlot.XAxisMax := (FDevice.CenterFreqHz + FDevice.SampleRateHz / 2) / 1e6;
end;

// PeakThresholdTrackBar is a 0-100% slider, not an absolute dB value -
// the spectrum's actual dB scale isn't calibrated (no per-gain-setting
// dBm reference, and now two different devices besides), so an absolute
// slider range would be wrong for at least one of them. Instead this
// maps the % position through FPlot's own live auto-fit range
// (CurrentYMin/CurrentYMax) into the absolute Value-axis units
// TVMPlotStack.PeakThreshold actually wants. Called both from the
// slider's own OnChange and every epoch (see EpochTimerTick) so the
// effective threshold keeps tracking the live noise floor/dynamic range
// as they drift, without needing the slider touched again.
procedure TForm1.UpdatePeakThreshold;
begin
  FPlot.PeakThreshold := FPlot.CurrentYMin +
    (PeakThresholdTrackBar.Position / 100) * (FPlot.CurrentYMax - FPlot.CurrentYMin);
  PeakThresholdLabel.Caption := Format('Peak Threshold: %d%%', [PeakThresholdTrackBar.Position]);
end;

// Applies the current UI settings (sample rate first - some devices'
// StartRX derives filter/decimation setup from it - then frequency, then
// every visible gain control) and starts streaming; the reverse (stop)
// just tears streaming down. RateCombo is disabled while streaming,
// since changing sample rate invalidates the running epoch cadence -
// stop first to pick a different one.
procedure TForm1.StartStopButtonClick(Sender: TObject);
var
  RateHz: Double;
begin
  if FDevice.IsStreaming then begin
    FEpochTimer.Enabled := False;
    if not FDevice.StopRX then ReportError('stop_rx');
    StartStopButton.Caption := 'Start';
    RateCombo.Enabled := True;
    StatusLabel.Caption := 'Connected (' + FDevice.Capabilities.DeviceName + ', idle)';
    Exit;
  end;

  RateHz := StrToFloatDef(RateCombo.Text, FDevice.Capabilities.DefaultSampleRateHz / 1e6) * 1e6;
  if not FDevice.SetSampleRateHz(RateHz) then begin ReportError('set_sample_rate'); Exit; end;
  if not FDevice.SetFrequencyHz(Round(FreqEdit.Value * 1e6)) then begin ReportError('set_freq'); Exit; end;
  ApplyAllGains;

  if not FDevice.StartRX then begin ReportError('start_rx'); Exit; end;

  UpdateFrequencyAxis;
  RateCombo.Enabled := False;
  StartStopButton.Caption := 'Stop';
  StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
    [FDevice.Capabilities.DeviceName, FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  FEpochTimer.Enabled := True;
end;

// Live retune - works whether or not RX is currently running, on both
// backends.
procedure TForm1.FreqEditEditingDone(Sender: TObject);
begin
  if not (Assigned(FDevice) and FDevice.IsOpen) then Exit;
  if FDevice.SetFrequencyHz(Round(FreqEdit.Value * 1e6)) then begin
    UpdateFrequencyAxis;
    if FDevice.IsStreaming then
      StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
        [FDevice.Capabilities.DeviceName, FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  end else
    ReportError('set_freq');
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.PeakDetectCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowPeakLabels := PeakDetectCheckBox.Checked;
  UpdatePeakThreshold;
end;

procedure TForm1.PeakThresholdTrackBarChange(Sender: TObject);
begin
  UpdatePeakThreshold;
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

  // Recalibrate the % threshold against this epoch's just-updated
  // auto-fit range - see UpdatePeakThreshold's own comment for why this
  // runs every epoch rather than only when the slider moves.
  if FPlot.ShowPeakLabels then UpdatePeakThreshold;
end;

end.
