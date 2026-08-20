unit uSDRMain;

{*******************************************************************************

     Main form for the spectrum analyser. Talks only to the abstract
     TSDRDevice interface (uSDRDevice.pas) - never to THackRFDevice
     (uHackRF.pas) or TRTLSDRDevice (uRTLSDR.pas) directly - so it works
     identically regardless of which hardware is actually attached. Two
     components - created and Parented to this form in code, same
     convention as Graphs/PlotStack's and Graphs/SpectrumDemo's own demo
     forms - are stacked vertically: FSpectrumPlot (TVMPlotSpectrum,
     Graphs/uVMPlotSpectrum.pas), a flat front-on persistence spectrum
     with a movable frequency cursor and peak labels, docked above
     FWaterfallPlot (TVMPlotWaterfall, Graphs/uVMPlotWaterfall.pas), a
     classic scrolling 2D waterfall filling the rest of the window. Both
     are fed by EpochTimerTick, up to ~30 times/second, each tick pulling
     one FEpochSize-sample complex IQ epoch (EpochCombo, default 8192 -
     see DefaultEpochSize; a smaller epoch is a cheaper FFT/dB pass per
     tick at the cost of coarser frequency resolution, and takes effect
     on the very next tick with no need to stop/restart streaming, unlike
     sample rate) off FDevice's ring buffer via TryReadEpoch. TryReadEpoch
     deliberately skips forward to the newest
     backlogged epoch each call (see uSDRDevice.pas's TSDRRingBuffer), so
     the display always shows a live, up-to-date spectrum rather than
     falling behind real time, however much faster the device's own
     sample rate is than the GUI timer's cadence.

     AUTODETECTION: ConnectButtonClick doesn't assume any particular
     hardware - DetectAndOpenDevice tries THackRFDevice, then
     TRTLSDRDevice, then TSDRplayDevice in turn (actually attempting Open
     on each, not just checking whether a library loaded - a library can
     be installed with no matching hardware attached), and whichever one
     successfully opens becomes FDevice.

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
       1. TryReadEpoch returns a (1,FEpochSize) TVMobjZ of normalised,
          DC/I-Q-balance-corrected complex IQ samples (uSDRDevice.pas's
          CorrectIQEpoch, called inside each device's own TryReadEpoch).
       2. newVMComplex.pas's PowerSpectrum(A: TVMobjZ): TVMobj
          Hamming-windows and FFTs it, returning all FEpochSize bins of
          LINEAR power in standard (non-centred) FFT bin order.
       3. That's reordered to ascending-frequency (most-negative first)
          via an FFT shift - built from newVM.pas's own SubMatrix/MergeLR
          rather than a hand-rolled swap loop.
       4. Converted to dB (10*Log10(P+eps)) and pushed via both
          FSpectrumPlot.AddGraph and FWaterfallPlot.AddGraph - the same
          already-computed spectrum feeds both displays.

     UseFrequencyAxis/XAxisMin/XAxisMax (both components support this,
     same convention as TVMPlotStack originally introduced it) are kept in
     sync with FDevice's actual CenterFreqHz/SampleRateHz by
     UpdateFrequencyAxis, called after every successful StartRX or live
     retune. Peak detection (ShowPeakLabels/PeakThreshold) lives on
     FSpectrumPlot only - the front-on view is where it makes sense;
     FWaterfallPlot has no such feature. YOffsetTrackBar/YGainTrackBar
     likewise only ever touch FSpectrumPlot's own YOffset/YGain (a
     display-only Y transform - see that property's own comment in
     uVMPlotSpectrum.pas) - FWaterfallPlot's colour mapping is unaffected.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, newVMComplex, uVMPlotSpectrum, uVMPlotWaterfall, uSDRDevice,
  uHackRF, uRTLSDR, uSDRplay, uFreqKeypad;

const
  DefaultEpochSize = 8192;

type

  { TForm1 }

  TForm1 = class(TForm)
    BiasTCheckBox: TCheckBox;
    ConnectButton: TButton;
    ControlPanel: TPanel;
    EpochCombo: TComboBox;
    EpochLabel: TLabel;
    FreqEdit: TFloatSpinEdit;
    FreqLabel: TLabel;
    GainStage0Label: TLabel;
    GainStage0TrackBar: TTrackBar;
    GainStage1Label: TLabel;
    GainStage1TrackBar: TTrackBar;
    GainStage2CheckBox: TCheckBox;
    HintLabel: TLabel;
    KeypadButton: TButton;
    PeakDetectCheckBox: TCheckBox;
    PeakThresholdLabel: TLabel;
    PeakThresholdTrackBar: TTrackBar;
    RateCombo: TComboBox;
    RateLabel: TLabel;
    ScrollRateLabel: TLabel;
    ScrollRateTrackBar: TTrackBar;
    ShowAverageCheckBox: TCheckBox;
    ShowAxesCheckBox: TCheckBox;
    StartStopButton: TButton;
    StatusLabel: TLabel;
    YGainLabel: TLabel;
    YGainTrackBar: TTrackBar;
    YOffsetLabel: TLabel;
    YOffsetTrackBar: TTrackBar;
    procedure BiasTCheckBoxChange(Sender: TObject);
    procedure ConnectButtonClick(Sender: TObject);
    procedure EpochComboChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FreqEditEditingDone(Sender: TObject);
    procedure GainStage0TrackBarChange(Sender: TObject);
    procedure GainStage1TrackBarChange(Sender: TObject);
    procedure GainStage2CheckBoxChange(Sender: TObject);
    procedure KeypadButtonClick(Sender: TObject);
    procedure PeakDetectCheckBoxChange(Sender: TObject);
    procedure PeakThresholdTrackBarChange(Sender: TObject);
    procedure ScrollRateTrackBarChange(Sender: TObject);
    procedure ShowAverageCheckBoxChange(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure StartStopButtonClick(Sender: TObject);
    procedure YGainTrackBarChange(Sender: TObject);
    procedure YOffsetTrackBarChange(Sender: TObject);
  private
    PlotsPanel: TPanel;
    FSpectrumPlot: TVMPlotSpectrum;
    FWaterfallPlot: TVMPlotWaterfall;
    FDevice: TSDRDevice;
    FEpochTimer: TTimer;
    FEpochSize: Integer;
    function DetectAndOpenDevice(out ErrMsg: string): TSDRDevice;
    procedure ApplyDeviceCapabilities;
    procedure ApplyGainStageControl(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure ApplyAllGains;
    procedure EpochTimerTick(Sender: TObject);
    procedure UpdateFrequencyAxis;
    procedure CommitFrequencyHz(Hz: QWord);
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
  // PlotsPanel exists purely so FSpectrumPlot/FWaterfallPlot's alTop/
  // alClient docking is resolved against EACH OTHER, not against
  // ControlPanel (also alTop) as a third sibling - LCL docks same-Align
  // siblings by Z-order/creation order, and having TWO alTop controls
  // directly under Self (ControlPanel, then FSpectrumPlot) put the
  // later-created one ABOVE ControlPanel instead of below it (confirmed
  // by screenshot - FSpectrumPlot rendered at the very top of the
  // window). Giving the plots their own alClient container collapses
  // that to a single unambiguous alTop-vs-alClient pair at each level
  // (ControlPanel vs PlotsPanel; FSpectrumPlot vs FWaterfallPlot).
  PlotsPanel := TPanel.Create(Self);
  PlotsPanel.Parent := Self;
  PlotsPanel.Align := alClient;
  PlotsPanel.BevelOuter := bvNone;

  FSpectrumPlot := TVMPlotSpectrum.Create(Self);
  FSpectrumPlot.Parent := PlotsPanel;
  FSpectrumPlot.Align := alTop;
  FSpectrumPlot.Height := 320;
  FSpectrumPlot.Title := 'Spectrum';
  FSpectrumPlot.XAxisTitle := 'Frequency (MHz)';
  FSpectrumPlot.YAxisTitle := 'Power (dB)';
  FSpectrumPlot.ClearStack;   // discard the component's own default demo data

  FWaterfallPlot := TVMPlotWaterfall.Create(Self);
  FWaterfallPlot.Parent := PlotsPanel;
  FWaterfallPlot.Align := alClient;
  FWaterfallPlot.Title := 'Waterfall';
  FWaterfallPlot.XAxisTitle := 'Frequency (MHz)';
  FWaterfallPlot.ClearStack;

  FEpochTimer := TTimer.Create(Self);
  FEpochTimer.Interval := 30;
  FEpochTimer.Enabled := False;
  FEpochTimer.OnTimer := @EpochTimerTick;

  FWaterfallPlot.ScrollRate := ScrollRateTrackBar.Position;
  ScrollRateLabel.Caption := Format('Scroll Rate: %d/s', [ScrollRateTrackBar.Position]);

  FEpochSize := StrToIntDef(EpochCombo.Text, DefaultEpochSize);
  YOffsetTrackBar.Position := 0;
  YOffsetLabel.Caption := 'Y Zero: 0 dB';
  YGainTrackBar.Position := 10;
  YGainLabel.Caption := 'Y Gain: 1.0x';

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
// Whichever opens first wins; if more than one is attached simultaneously,
// the winner is decided purely by this order (HackRF, then RTL-SDR, then
// SDRplay) - no other significance to it. Returns nil (with a combined
// ErrMsg) if none respond.
function TForm1.DetectAndOpenDevice(out ErrMsg: string): TSDRDevice;
var
  HackRF: THackRFDevice;
  RTLSDR: TRTLSDRDevice;
  SDRplay: TSDRplayDevice;
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

  SDRplay := TSDRplayDevice.Create;
  if SDRplay.Open then begin
    Result := SDRplay;
    Exit;
  end;
  Reasons := Reasons + '; SDRplay: ' + SDRplay.LastError;
  SDRplay.Free;

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
      // Max before Min: TTrackBar silently clamps Min down to its CURRENT
      // Max if you assign a Min above it, and that clamp sticks even after
      // Max is raised afterward (only Position ends up wrong, silently -
      // no exception) - harmless for HackRF/RTL-SDR, whose own Min is
      // always 0, but hit for real switching devices once SDRplay's own
      // Min (20, NORMAL_MIN_GR) landed above whatever trackbar range was
      // already showing (e.g. this control's .lfm design-time default).
      // Setting Max first means Min is never assigned above the (already
      // wide enough) current range.
      Bar.Max := Round(Stage.Max);
      Bar.Min := Round(Stage.Min);
      Bar.Frequency := Max(Round(Stage.Step), 1);
      Bar.Position := Bar.Min;
      Lbl.Caption := Format('%s: %d%s', [Stage.Name, Bar.Position, Stage.UnitSuffix]);
    end;
    gkDiscreteList: begin
      Bar.Min := 0;
      Bar.Max := Max(High(Stage.DiscreteValues), 0);
      Bar.Frequency := 1;
      Bar.Position := Bar.Max div 2;   // a reasonable mid-range default
      if Length(Stage.DiscreteValues) > 0 then
        Lbl.Caption := Format('%s: %.1f%s', [Stage.Name, Stage.DiscreteValues[Bar.Position], Stage.UnitSuffix])
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
      Lbl.Caption := Format('%s: %d%s', [Stage.Name, V, Stage.UnitSuffix]);
    end;
    gkDiscreteList: begin
      if Length(Stage.DiscreteValues) = 0 then Exit;
      Value := Stage.DiscreteValues[Bar.Position];
      Lbl.Caption := Format('%s: %.1f%s', [Stage.Name, Value, Stage.UnitSuffix]);
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

// Bias-T is a Capabilities.BoolOptions entry, not a gain stage (see
// uSDRDevice.pas's own comment on why those are kept separate) - always
// slot 0, since both current backends offer exactly one bool option each.
procedure TForm1.BiasTCheckBoxChange(Sender: TObject);
begin
  if FDevice.IsOpen then FDevice.SetBoolOption(0, BiasTCheckBox.Checked);
end;

// Re-applies every currently-visible gain stage's/bool option's control
// value to the device - called once from StartStopButtonClick before
// starting RX, so a device picks up whatever the user set the
// sliders/checkboxes to before pressing Start (mirroring the individual
// OnChange handlers, which only apply live once already open/streaming).
procedure TForm1.ApplyAllGains;
begin
  if GainStage0TrackBar.Visible then GainStageTrackBarChanged(0, GainStage0Label, GainStage0TrackBar);
  if GainStage1TrackBar.Visible then GainStageTrackBarChanged(1, GainStage1Label, GainStage1TrackBar);
  if GainStage2CheckBox.Visible then FDevice.SetGain(2, Ord(GainStage2CheckBox.Checked));
  if BiasTCheckBox.Visible then FDevice.SetBoolOption(0, BiasTCheckBox.Checked);
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
  FSpectrumPlot.Title := Caps.DeviceName + ' Spectrum';
  FWaterfallPlot.Title := Caps.DeviceName + ' Waterfall';

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

  // BoolOptions (bias-T etc) are independent of the gain-stage slots
  // above - both current backends offer exactly one, so it's always
  // slot 0 here; a future device with none simply hides the checkbox.
  if Length(Caps.BoolOptions) > 0 then begin
    BiasTCheckBox.Visible := True;
    BiasTCheckBox.Checked := False;
    BiasTCheckBox.Caption := Caps.BoolOptions[0].Name;
  end else
    BiasTCheckBox.Visible := False;
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
    BiasTCheckBox.Visible := False;
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
var
  Lo, Hi: Double;
begin
  Lo := (FDevice.CenterFreqHz - FDevice.SampleRateHz / 2) / 1e6;
  Hi := (FDevice.CenterFreqHz + FDevice.SampleRateHz / 2) / 1e6;
  FSpectrumPlot.UseFrequencyAxis := True;
  FSpectrumPlot.XAxisMin := Lo;
  FSpectrumPlot.XAxisMax := Hi;
  FWaterfallPlot.UseFrequencyAxis := True;
  FWaterfallPlot.XAxisMin := Lo;
  FWaterfallPlot.XAxisMax := Hi;
end;

// PeakThresholdTrackBar is a 0-100% slider, not an absolute dB value -
// the spectrum's actual dB scale isn't calibrated (no per-gain-setting
// dBm reference, and now two different devices besides), so an absolute
// slider range would be wrong for at least one of them. Instead this
// maps the % position through FSpectrumPlot's own live auto-fit range
// (CurrentYMin/CurrentYMax) into the absolute Value-axis units
// TVMPlotSpectrum.PeakThreshold actually wants (peak detection is
// FSpectrumPlot-only - see this unit's own header comment). Called both
// from the slider's own OnChange and every epoch (see EpochTimerTick) so
// the effective threshold keeps tracking the live noise floor/dynamic
// range as they drift, without needing the slider touched again.
procedure TForm1.UpdatePeakThreshold;
begin
  FSpectrumPlot.PeakThreshold := FSpectrumPlot.CurrentYMin +
    (PeakThresholdTrackBar.Position / 100) * (FSpectrumPlot.CurrentYMax - FSpectrumPlot.CurrentYMin);
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
    EpochCombo.Enabled := True;
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
  EpochCombo.Enabled := False;
  StartStopButton.Caption := 'Stop';
  StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
    [FDevice.Capabilities.DeviceName, FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  FEpochTimer.Enabled := True;
end;

// Shared by FreqEditEditingDone and KeypadButtonClick - live retune,
// works whether or not RX is currently running, on both backends.
procedure TForm1.CommitFrequencyHz(Hz: QWord);
begin
  if not (Assigned(FDevice) and FDevice.IsOpen) then Exit;
  if FDevice.SetFrequencyHz(Hz) then begin
    UpdateFrequencyAxis;
    if FDevice.IsStreaming then
      StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
        [FDevice.Capabilities.DeviceName, FDevice.CenterFreqHz / 1e6, FDevice.SampleRateHz / 1e6]);
  end else
    ReportError('set_freq');
end;

procedure TForm1.FreqEditEditingDone(Sender: TObject);
begin
  CommitFrequencyHz(Round(FreqEdit.Value * 1e6));
end;

// Opens the popup numeric keypad (uFreqKeypad.pas), clamped to whatever
// frequency range the connected device actually supports (or
// unclamped - 0/0 - if none is connected yet, since FreqEdit.MinValue/
// MaxValue still hold their generic .lfm defaults at that point rather
// than a real device's range). On a committed entry, keeps FreqEdit's
// own displayed value in sync before retuning, so the two controls never
// disagree with each other.
procedure TForm1.KeypadButtonClick(Sender: TObject);
var
  ResultHz: Double;
  MinHz, MaxHz: Double;
begin
  if Assigned(FDevice) and FDevice.IsOpen then begin
    MinHz := FDevice.Capabilities.MinFreqHz;
    MaxHz := FDevice.Capabilities.MaxFreqHz;
  end else begin
    MinHz := 0;
    MaxHz := 0;
  end;

  if ShowFrequencyKeypad(MinHz, MaxHz, ResultHz) then begin
    FreqEdit.Value := ResultHz / 1e6;
    CommitFrequencyHz(Round(ResultHz));
  end;
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FSpectrumPlot.ShowAxes := ShowAxesCheckBox.Checked;
  FWaterfallPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.ShowAverageCheckBoxChange(Sender: TObject);
begin
  FSpectrumPlot.ShowAverage := ShowAverageCheckBox.Checked;
end;

procedure TForm1.PeakDetectCheckBoxChange(Sender: TObject);
begin
  FSpectrumPlot.ShowPeakLabels := PeakDetectCheckBox.Checked;
  UpdatePeakThreshold;
end;

procedure TForm1.PeakThresholdTrackBarChange(Sender: TObject);
begin
  UpdatePeakThreshold;
end;

procedure TForm1.ScrollRateTrackBarChange(Sender: TObject);
begin
  FWaterfallPlot.ScrollRate := ScrollRateTrackBar.Position;
  ScrollRateLabel.Caption := Format('Scroll Rate: %d/s', [ScrollRateTrackBar.Position]);
end;

// Epoch size only affects how many raw IQ samples TryReadEpoch pulls per
// tick (see EpochTimerTick) - nothing in FDevice's own state depends on
// it, unlike sample rate, so this takes effect on the very next epoch
// with no need to stop/restart streaming. A smaller epoch means fewer
// FFT bins (coarser frequency resolution) but a cheaper FFT per epoch
// and a shorter Hamming-window/FFT/dB-conversion pass - the "smaller
// might improve performance" the control is for.
procedure TForm1.EpochComboChange(Sender: TObject);
begin
  FEpochSize := StrToIntDef(EpochCombo.Text, DefaultEpochSize);
end;

// See TVMPlotSpectrum.YOffset's own property comment (uVMPlotSpectrum.pas)
// - a display-only shift of the whole trace, independent of YGain.
procedure TForm1.YOffsetTrackBarChange(Sender: TObject);
begin
  FSpectrumPlot.YOffset := YOffsetTrackBar.Position;
  YOffsetLabel.Caption := Format('Y Zero: %d dB', [YOffsetTrackBar.Position]);
end;

// TTrackBar positions are integers, so this maps Position 1..50 to a
// 0.1x..5.0x gain in 0.1 steps (Position/10) rather than exposing
// TVMPlotSpectrum.YGain's real-valued range directly on the slider - see
// that property's own comment for what YGain does.
procedure TForm1.YGainTrackBarChange(Sender: TObject);
var
  Gain: Double;
begin
  Gain := YGainTrackBar.Position / 10.0;
  FSpectrumPlot.YGain := Gain;
  YGainLabel.Caption := Format('Y Gain: %.1fx', [Gain]);
end;

procedure TForm1.EpochTimerTick(Sender: TObject);
var
  IQ: TVMobjZ;
  LinearPower, Shifted, PowerSpec: TVMobj;
  HalfN, k: Integer;
begin
  if not FDevice.TryReadEpoch(FEpochSize, IQ) then Exit;

  LinearPower := PowerSpectrum(IQ);   // newVMComplex.pas - Hamming window + FFT + |X|^2

  HalfN := FEpochSize div 2;
  // FFT shift: negative-frequency bins (upper half of LinearPower) first,
  // then DC and positive-frequency bins - ascending frequency order,
  // matching XAxisMin..XAxisMax on both plots.
  Shifted := MergeLR(SubMatrix(LinearPower, 0, HalfN, 1, HalfN),
                      SubMatrix(LinearPower, 0, 0, 1, HalfN));

  PowerSpec := TVMobj.Create(1, FEpochSize);
  for k := 0 to FEpochSize - 1 do
    PowerSpec[0, k] := 10 * Log10(Shifted[0, k] + 1e-12);

  FSpectrumPlot.AddGraph(PowerSpec);
  FWaterfallPlot.AddGraph(PowerSpec);

  // Recalibrate the % threshold against this epoch's just-updated
  // auto-fit range - see UpdatePeakThreshold's own comment for why this
  // runs every epoch rather than only when the slider moves.
  if FSpectrumPlot.ShowPeakLabels then UpdatePeakThreshold;
end;

end.
