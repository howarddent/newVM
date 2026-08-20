unit uSDRMain;

{*******************************************************************************

     Main form for the spectrum analyser. Talks only through two
     installable Lazarus components (uSDRRFSource.pas's TSDRRFSource,
     uVMPlotSDRSpectrum.pas's TSDRSpectrumAnalyser) - never to
     THackRFDevice/TRTLSDRDevice/TSDRplayDevice, or to
     TVMPlotSpectrum/TVMPlotWaterfall, directly. This form used to own
     that logic itself (device autodetection, the capability-driven gain
     panel, the epoch-read/PowerSpectrum/fftshift/dB pipeline feeding two
     hand-created OpenGL controls) - it has all since moved into those two
     components specifically so it can be reused on any other form/
     project without dragging this form's own layout along with it; see
     each component unit's own header comment for the full rationale
     (notably: TSDRSpectrumAnalyser now runs the windowing/FFT on the GPU
     via newVMCL/OpenCL when available, falling back to the CPU
     otherwise - this form doesn't need to know which).

     FRFSource (TSDRRFSource) is created and Parented... - being
     non-visual, it just needs an Owner (Self) - in FormCreate, alongside
     FAnalyser (TSDRSpectrumAnalyser), which IS parented/aligned to fill
     the window below ControlPanel, same layout convention every other
     Graphs/SDR_Radio demo form here uses (create in code, Align to
     alClient). FAnalyser.Source is pointed at FRFSource once, up front -
     it's a design-time-style component link (like TDBGrid.DataSource),
     unaffected by whether a device is actually connected yet.

     AUTODETECTION: ConnectButtonClick calls FRFSource.Connect, which
     tries THackRFDevice, then TRTLSDRDevice, then TSDRplayDevice in turn
     (actually attempting Open on each, not just checking whether a
     library loaded - a library can be installed with no matching
     hardware attached) - whichever succeeds becomes the source's device.

     CAPABILITY-DRIVEN UI: once connected, ApplyDeviceCapabilities
     reconfigures the control panel from FRFSource.Capabilities -
     FreqEdit's bounds, RateCombo's offered sample rates, and up to three
     generic gain-stage controls (GainStage0/1 as trackbars for
     continuous or discrete-list stages, GainStage2 as a checkbox for a
     boolean stage - see that method's own comment for the slot-filling
     rule) relabelled and shown/hidden per Capabilities.GainStages. This
     is what makes the window itself look different for HackRF (three
     visible controls: LNA/VGA/RF Amp) versus RTL-SDR (two: Tuner
     Gain/Auto Gain) versus SDRplay, without any hardcoded "if HackRF
     then ... else ..." branch in the layout code.

     UseFrequencyAxis/XAxisMin/XAxisMax (both FAnalyser.SpectrumPlot and
     FAnalyser.WaterfallPlot support this) are kept in sync with
     FRFSource's actual CenterFreqHz/SampleRateHz by UpdateFrequencyAxis,
     called after every successful start or live retune. Peak detection
     (ShowPeakLabels/PeakThreshold) lives on FAnalyser.SpectrumPlot only -
     the front-on view is where it makes sense. YOffsetTrackBar/
     YGainTrackBar likewise only ever touch FAnalyser.SpectrumPlot's own
     YOffset/YGain - FAnalyser.WaterfallPlot's colour mapping is
     unaffected.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  uSDRDevice, uSDRRFSource, uVMPlotSDRSpectrum, uFreqKeypad;

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
    FRFSource: TSDRRFSource;
    FAnalyser: TSDRSpectrumAnalyser;
    procedure AnalyserGPUStatusKnown(Sender: TObject);
    procedure ApplyDeviceCapabilities;
    procedure ApplyGainStageControl(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure ApplyAllGains;
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
  FRFSource := TSDRRFSource.Create(Self);

  FAnalyser := TSDRSpectrumAnalyser.Create(Self);
  FAnalyser.Parent := Self;
  FAnalyser.Align := alClient;
  FAnalyser.Source := FRFSource;
  FAnalyser.EpochSize := StrToIntDef(EpochCombo.Text, DefaultSDREpochSize);
  FAnalyser.OnGPUStatusKnown := @AnalyserGPUStatusKnown;

  FAnalyser.WaterfallScrollRate := ScrollRateTrackBar.Position;
  ScrollRateLabel.Caption := Format('Scroll Rate: %d/s', [ScrollRateTrackBar.Position]);

  YOffsetTrackBar.Position := 0;
  YOffsetLabel.Caption := 'Y Zero: 0 dB';
  YGainTrackBar.Position := 10;
  YGainLabel.Caption := 'Y Gain: 1.0x';

  StatusLabel.Caption := 'Not connected';
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FAnalyser) then FAnalyser.Active := False;
  FRFSource.Free;   // stops RX and closes the device itself, if still open
end;

procedure TForm1.ReportError(const Where: string);
begin
  StatusLabel.Caption := 'Error (' + Where + '): ' + FRFSource.LastError;
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
  if (StageIndex < 0) or (StageIndex > High(FRFSource.Capabilities.GainStages)) then begin
    Lbl.Visible := False;
    Bar.Visible := False;
    Exit;
  end;
  Stage := FRFSource.Capabilities.GainStages[StageIndex];

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
// value through FRFSource.SetGain. Discrete-list stages look the actual
// dB value up from Position (an index); continuous stages use Position
// directly, snapped to the stage's own Step first (same snap-and-reenter
// pattern the original LNA/VGA handlers used, generalised).
procedure TForm1.GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
var
  Stage: TSDRGainStage;
  V: Integer;
  Value: Double;
begin
  if (StageIndex < 0) or (StageIndex > High(FRFSource.Capabilities.GainStages)) then Exit;
  Stage := FRFSource.Capabilities.GainStages[StageIndex];

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

  if FRFSource.IsOpen then FRFSource.SetGain(StageIndex, Value);
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
  if FRFSource.IsOpen then FRFSource.SetGain(2, Ord(GainStage2CheckBox.Checked));
end;

// Bias-T is a Capabilities.BoolOptions entry, not a gain stage (see
// uSDRDevice.pas's own comment on why those are kept separate) - always
// slot 0, since every current backend offers exactly one bool option.
procedure TForm1.BiasTCheckBoxChange(Sender: TObject);
begin
  if FRFSource.IsOpen then FRFSource.SetBoolOption(0, BiasTCheckBox.Checked);
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
  if GainStage2CheckBox.Visible then FRFSource.SetGain(2, Ord(GainStage2CheckBox.Checked));
  if BiasTCheckBox.Visible then FRFSource.SetBoolOption(0, BiasTCheckBox.Checked);
end;

// Rebuilds the whole control panel from FRFSource.Capabilities - see this
// unit's own header comment for the overall rationale. Called once, from
// ConnectButtonClick, right after a device is successfully opened.
procedure TForm1.ApplyDeviceCapabilities;
var
  Caps: TSDRCapabilities;
  i, NumericSlot: Integer;
  BooleanStage: Integer;
begin
  Caps := FRFSource.Capabilities;

  Caption := 'newVM ' + Caps.DeviceName + ' Spectrum Analyser';
  FAnalyser.SpectrumTitle := Caps.DeviceName + ' Spectrum';
  FAnalyser.WaterfallTitle := Caps.DeviceName + ' Waterfall';

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
  // above - every current backend offers exactly one, so it's always
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
  if FRFSource.IsOpen then begin
    if FRFSource.IsStreaming then StartStopButtonClick(Sender);   // stop first
    FRFSource.Disconnect;
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

  if not FRFSource.Connect(ErrMsg) then begin
    StatusLabel.Caption := 'Error: ' + ErrMsg;
    Exit;
  end;

  ApplyDeviceCapabilities;
  UpdateFrequencyAxis;
  ConnectButton.Caption := 'Disconnect';
  StartStopButton.Enabled := True;
  StatusLabel.Caption := 'Connected (' + FRFSource.Capabilities.DeviceName + ', idle)';
end;

// (CenterFreqHz -+ SampleRateHz/2), in MHz - recomputed after every
// successful start or live retune so the axis always matches what the
// device is actually doing, whatever its sample rate.
procedure TForm1.UpdateFrequencyAxis;
var
  Lo, Hi: Double;
begin
  Lo := (FRFSource.CenterFreqHz - FRFSource.SampleRateHz / 2) / 1e6;
  Hi := (FRFSource.CenterFreqHz + FRFSource.SampleRateHz / 2) / 1e6;
  FAnalyser.UseFrequencyAxis := True;
  FAnalyser.XAxisMin := Lo;
  FAnalyser.XAxisMax := Hi;
end;

// PeakThresholdTrackBar is a 0-100% slider, not an absolute dB value -
// the spectrum's actual dB scale isn't calibrated (no per-gain-setting
// dBm reference, and several different devices besides), so an absolute
// slider range would be wrong for at least one of them. Instead this
// maps the % position through FAnalyser.SpectrumPlot's own live auto-fit
// range (CurrentYMin/CurrentYMax) into the absolute Value-axis units
// TVMPlotSpectrum.PeakThreshold actually wants. Called both from the
// slider's own OnChange and whenever the effective threshold needs
// recalibrating against the live noise floor/dynamic range as they
// drift, without needing the slider touched again - see
// PeakDetectCheckBoxChange.
procedure TForm1.UpdatePeakThreshold;
begin
  FAnalyser.SpectrumPeakThreshold := FAnalyser.SpectrumCurrentYMin +
    (PeakThresholdTrackBar.Position / 100) *
    (FAnalyser.SpectrumCurrentYMax - FAnalyser.SpectrumCurrentYMin);
  PeakThresholdLabel.Caption := Format('Peak Threshold: %d%%', [PeakThresholdTrackBar.Position]);
end;

// Applies the current UI settings (sample rate first - some devices'
// StartStreaming derives filter/decimation setup from it - then every
// visible gain control) and starts streaming; the reverse (stop) just
// tears streaming down. RateCombo is disabled while streaming, since
// changing sample rate invalidates the running epoch cadence - stop
// first to pick a different one.
procedure TForm1.StartStopButtonClick(Sender: TObject);
var
  RateHz: Double;
begin
  if FRFSource.IsStreaming then begin
    FAnalyser.Active := False;
    FRFSource.StopStreaming;
    StartStopButton.Caption := 'Start';
    RateCombo.Enabled := True;
    EpochCombo.Enabled := True;
    StatusLabel.Caption := 'Connected (' + FRFSource.Capabilities.DeviceName + ', idle)';
    Exit;
  end;

  RateHz := StrToFloatDef(RateCombo.Text, FRFSource.Capabilities.DefaultSampleRateHz / 1e6) * 1e6;
  ApplyAllGains;

  if not FRFSource.StartStreaming(RateHz, Round(FreqEdit.Value * 1e6)) then begin
    ReportError('start_streaming');
    Exit;
  end;

  UpdateFrequencyAxis;
  RateCombo.Enabled := False;
  EpochCombo.Enabled := False;
  StartStopButton.Caption := 'Stop';
  // Deliberately no [GPU]/[CPU] tag here yet: UsingGPU/GPUStatusMessage
  // aren't known until the first epoch actually runs through
  // TSDRSpectrumAnalyser.ProcessEpoch (see that unit's OnGPUStatusKnown
  // comment) - AnalyserGPUStatusKnown appends it once that happens.
  StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
    [FRFSource.Capabilities.DeviceName, FRFSource.CenterFreqHz / 1e6, FRFSource.SampleRateHz / 1e6]);
  FAnalyser.Active := True;
end;

// Fired once per Start, from TSDRSpectrumAnalyser's first processed
// epoch, once GPU-vs-CPU is actually known (see that unit's
// OnGPUStatusKnown property comment).
procedure TForm1.AnalyserGPUStatusKnown(Sender: TObject);
begin
  if FAnalyser.UsingGPU then
    StatusLabel.Caption := StatusLabel.Caption + ' [GPU]'
  else
    StatusLabel.Caption := StatusLabel.Caption + ' [CPU: ' + FAnalyser.GPUStatusMessage + ']';
end;

// Shared by FreqEditEditingDone and KeypadButtonClick - live retune,
// works whether or not RX is currently running, on any backend.
procedure TForm1.CommitFrequencyHz(Hz: QWord);
begin
  if not FRFSource.IsOpen then Exit;
  if FRFSource.SetFrequencyHz(Hz) then begin
    UpdateFrequencyAxis;
    if FRFSource.IsStreaming then
      StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
        [FRFSource.Capabilities.DeviceName, FRFSource.CenterFreqHz / 1e6, FRFSource.SampleRateHz / 1e6]);
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
  if FRFSource.IsOpen then begin
    MinHz := FRFSource.Capabilities.MinFreqHz;
    MaxHz := FRFSource.Capabilities.MaxFreqHz;
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
  FAnalyser.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.ShowAverageCheckBoxChange(Sender: TObject);
begin
  FAnalyser.SpectrumShowAverage := ShowAverageCheckBox.Checked;
end;

procedure TForm1.PeakDetectCheckBoxChange(Sender: TObject);
begin
  FAnalyser.SpectrumShowPeakLabels := PeakDetectCheckBox.Checked;
  UpdatePeakThreshold;
end;

procedure TForm1.PeakThresholdTrackBarChange(Sender: TObject);
begin
  UpdatePeakThreshold;
end;

procedure TForm1.ScrollRateTrackBarChange(Sender: TObject);
begin
  FAnalyser.WaterfallScrollRate := ScrollRateTrackBar.Position;
  ScrollRateLabel.Caption := Format('Scroll Rate: %d/s', [ScrollRateTrackBar.Position]);
end;

// Epoch size only affects how many raw IQ samples are pulled per tick -
// nothing in FRFSource's own state depends on it, unlike sample rate, so
// this takes effect on the very next epoch with no need to stop/restart
// streaming. A smaller epoch means fewer FFT bins (coarser frequency
// resolution) but a cheaper FFT per epoch - the "smaller might improve
// performance" the control is for.
procedure TForm1.EpochComboChange(Sender: TObject);
begin
  FAnalyser.EpochSize := StrToIntDef(EpochCombo.Text, DefaultSDREpochSize);
end;

// See TVMPlotSpectrum.YOffset's own property comment (uVMPlotSpectrum.pas)
// - a display-only shift of the whole trace, independent of YGain.
procedure TForm1.YOffsetTrackBarChange(Sender: TObject);
begin
  FAnalyser.SpectrumYOffset := YOffsetTrackBar.Position;
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
  FAnalyser.SpectrumYGain := Gain;
  YGainLabel.Caption := Format('Y Gain: %.1fx', [Gain]);
end;

end.
