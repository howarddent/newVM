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

     LISTEN (FReceiver/FAMReceiver, uFMReceiver.pas's
     TFMBroadcastReceiver and uAMReceiver.pas's TAMBroadcastReceiver):
     two mode-specific receiver components, both pointed at the same
     FRFSource, demonstrating this project's onward-CPU-signal-processing
     story - each runs a full modular receive chain (local oscillator/
     mixer, rational resamplers, mode-specific demodulator - see
     uDSPBlocks.pas) on the wideband IQ stream and plays the result
     through the sound card (uWaveOutPlayer.pas). ModeCombo selects which
     ONE of the two is ever actually Active at a time (StartSelectedReceiver);
     TunedFrequencyHz/Volume are pushed to BOTH unconditionally regardless
     of which is currently listening (harmless on the inactive one - see
     e.g. TFMBroadcastReceiver.SetTunedFrequencyHz's own comment on why a
     write with no live chain built is a no-op beyond caching the value),
     which avoids needing to track "which receiver is current" separately
     in every frequency/volume-change handler. ListenFreqEdit is
     deliberately a SEPARATE control from FreqEdit: FreqEdit retunes the
     RF front end's own centre frequency (moving what's captured at
     all), while ListenFreqEdit only moves the active receiver's internal
     mixer within whatever's already captured - the two can legitimately
     differ (e.g. capture centred at 100.000MHz, 2Msps, listening to a
     station actually sitting at 99.500MHz within that capture), which is
     the whole point of doing the tuning in software rather than by
     retuning hardware. BandwidthTrackBar/SynchronousCheckBox are AM-only
     (uAMReceiver.pas's own TAMBroadcastReceiver.BandwidthHz/Synchronous)
     and hidden whenever FM is selected (ApplyListenModeVisibility); FM
     has no equivalent controls, since its own channel bandwidth is fixed
     by the broadcast-FM standard itself (see TFMBroadcastReceiver's own
     header comment). Like the rest of this form's controls, all of these
     are created in code in FormCreate rather than hand-placed in the
     .lfm, same reasoning as FRFSource/FAnalyser's own header comment
     above. All of them are Parented to ReceiverGroupBox (a plain
     TGroupBox, itself Parented to ControlPanel), not ControlPanel
     directly - keeps every receiver-related control visually grouped
     under one titled box instead of scattered loose among the spectrum-
     display controls that fill the rest of the panel; their own
     SetBounds coordinates are relative to the group box's own client
     area, not the panel's.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  uSDRDevice, uSDRRFSource, uVMPlotSDRSpectrum, uFreqKeypad, uFMReceiver,
  uAMReceiver;

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
    FReceiver: TFMBroadcastReceiver;
    FAMReceiver: TAMBroadcastReceiver;
    ListenCheckBox: TCheckBox;
    ModeCombo: TComboBox;
    ReceiverGroupBox: TGroupBox;
    ListenFreqLabel: TLabel;
    ListenFreqEdit: TFloatSpinEdit;
    ListenKeypadButton: TButton;
    BandwidthLabel: TLabel;
    BandwidthTrackBar: TTrackBar;
    SynchronousCheckBox: TCheckBox;
    ClickBlankerCheckBox: TCheckBox;
    VolumeLabel: TLabel;
    VolumeTrackBar: TTrackBar;
    AudioStatsLabel: TLabel;
    FFreqRetryTimer: TTimer;
    FEdgePanTimer: TTimer;
    FAudioStatsTimer: TTimer;
    FEdgePanDirection: Integer;
    procedure AnalyserGPUStatusKnown(Sender: TObject);
    procedure AnalyserCursorChanged(Sender: TObject);
    procedure ApplyDeviceCapabilities;
    procedure ApplyGainStageControl(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure GainStageTrackBarChanged(StageIndex: Integer; Lbl: TLabel; Bar: TTrackBar);
    procedure ApplyAllGains;
    procedure UpdateFrequencyAxis;
    procedure CommitFrequencyHz(Hz: QWord);
    procedure RFSourceFrequencyChanged(Sender: TObject);
    procedure ApplyFrequencyChangedUI;
    procedure FreqRetryTimerTick(Sender: TObject);
    procedure EdgePanTimerTick(Sender: TObject);
    procedure AudioStatsTimerTick(Sender: TObject);
    function RunFrequencyKeypad(MinHz, MaxHz: Double; out ResultHz: Double): Boolean;
    procedure UpdatePeakThreshold;
    procedure ReportError(const Where: string);
    procedure ApplyListenModeVisibility;
    procedure UpdateCursorBandwidth;
    procedure StartSelectedReceiver;
    procedure ListenCheckBoxChange(Sender: TObject);
    procedure ModeComboChange(Sender: TObject);
    procedure ListenFreqEditEditingDone(Sender: TObject);
    procedure ListenKeypadButtonClick(Sender: TObject);
    procedure BandwidthTrackBarChange(Sender: TObject);
    procedure SynchronousCheckBoxChange(Sender: TObject);
    procedure ClickBlankerCheckBoxChange(Sender: TObject);
    procedure VolumeTrackBarChange(Sender: TObject);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FRFSource := TSDRRFSource.Create(Self);
  FRFSource.OnFrequencyChanged := @RFSourceFrequencyChanged;

  // See RFSourceFrequencyChanged's own comment - retries applying the
  // completed retune's UI side effects shortly after a modal dialog
  // (e.g. the frequency keypad) closes, rather than doing GL/Invalidate
  // work while one might still be tearing down.
  FFreqRetryTimer := TTimer.Create(Self);
  FFreqRetryTimer.Interval := 50;
  FFreqRetryTimer.Enabled := False;
  FFreqRetryTimer.OnTimer := @FreqRetryTimerTick;

  // Drives EDGE PANNING - see AnalyserCursorChanged's own header comment
  // for the full rationale. Deliberately shorter than a typical async
  // retune's own round-trip (confirmed ~50-100ms in earlier testing -
  // see uSDRRFSource.pas's own ASYNC RETUNE header comment): ticks can
  // now fire faster than the hardware actually confirms each one, but
  // that's fine - TSDRControlThread.RequestFrequencyHz just coalesces to
  // "whatever was requested most recently", so extra ticks simply keep
  // the target fresh rather than piling up requests. The real point of
  // going shorter here is EdgePanFraction below shrinking to match, so
  // each individual step (and so each visible jump once the hardware
  // does catch up) is smaller - smoother-looking panning at roughly the
  // same overall %/sec rate, rather than a longer wait for one big jump.
  FEdgePanTimer := TTimer.Create(Self);
  FEdgePanTimer.Interval := 20;
  FEdgePanTimer.Enabled := False;
  FEdgePanTimer.OnTimer := @EdgePanTimerTick;
  FEdgePanDirection := 0;

  // Periodic readout of the audio pipeline's own diagnostic counters
  // (TWaveOutPlayer.UnderrunCount via AudioUnderrunCount, and - FM only -
  // TBasebandQueue.DropCount via AudioDropCount) - added specifically so
  // an audible click can be attributed to a real ALSA xrun versus a
  // dropped baseband epoch (FAcquireThread/FDemodThread falling behind)
  // versus neither (some other cause entirely), rather than guessing.
  // 1s is coarse enough not to matter for a slowly-incrementing counter
  // but frequent enough to correlate with what was just heard.
  FAudioStatsTimer := TTimer.Create(Self);
  FAudioStatsTimer.Interval := 1000;
  FAudioStatsTimer.Enabled := True;
  FAudioStatsTimer.OnTimer := @AudioStatsTimerTick;

  FAnalyser := TSDRSpectrumAnalyser.Create(Self);
  FAnalyser.Parent := Self;
  FAnalyser.Align := alClient;
  FAnalyser.Source := FRFSource;
  FAnalyser.EpochSize := StrToIntDef(EpochCombo.Text, DefaultSDREpochSize);
  FAnalyser.OnGPUStatusKnown := @AnalyserGPUStatusKnown;
  FAnalyser.OnCursorChange := @AnalyserCursorChanged;

  FAnalyser.WaterfallScrollRate := ScrollRateTrackBar.Position;
  ScrollRateLabel.Caption := Format('Scroll Rate: %d/s', [ScrollRateTrackBar.Position]);

  YOffsetTrackBar.Position := 0;
  YOffsetLabel.Caption := 'Y Zero: 0 dB';
  YGainTrackBar.Position := 10;
  YGainLabel.Caption := 'Y Gain: 1.0x';

  FReceiver := TFMBroadcastReceiver.Create(Self);
  FReceiver.Source := FRFSource;

  FAMReceiver := TAMBroadcastReceiver.Create(Self);
  FAMReceiver.Source := FRFSource;

  // All receiver controls (Listen/Mode/Frequency/Bandwidth/Synchronous/
  // Volume) live inside their own titled group box rather than loose in
  // ControlPanel - visually separates "how to receive" from the
  // spectrum-display controls that fill the rest of the panel. Every
  // child below is Parented to ReceiverGroupBox, not ControlPanel
  // directly, so their own SetBounds coordinates are relative to the
  // group box's client area, not the panel's.
  // Occupies the full right-hand column of ControlPanel, top to
  // (nearly) bottom - StatusLabel moved to its own full-width row under
  // the front-end controls (see the .lfm) specifically to clear this
  // whole column for the receiver panel, and ShowAxesCheckBox..
  // ShowAverageCheckBox were compacted to end by x=840 for the same
  // reason (see the .lfm) - so nothing on the left competes with this
  // box for space at any height.
  ReceiverGroupBox := TGroupBox.Create(Self);
  ReceiverGroupBox.Parent := ControlPanel;
  ReceiverGroupBox.SetBounds(860, 10, 420, 315);
  ReceiverGroupBox.Caption := 'Receiver';

  ListenCheckBox := TCheckBox.Create(Self);
  ListenCheckBox.Parent := ReceiverGroupBox;
  ListenCheckBox.SetBounds(10, 20, 90, 19);
  ListenCheckBox.Caption := 'Listen';
  ListenCheckBox.OnChange := @ListenCheckBoxChange;

  ModeCombo := TComboBox.Create(Self);
  ModeCombo.Parent := ReceiverGroupBox;
  ModeCombo.SetBounds(110, 18, 80, 23);
  ModeCombo.Style := csDropDownList;
  ModeCombo.Items.Add('FM');
  ModeCombo.Items.Add('AM');
  ModeCombo.ItemIndex := 0;
  ModeCombo.OnChange := @ModeComboChange;

  ListenFreqLabel := TLabel.Create(Self);
  ListenFreqLabel.Parent := ReceiverGroupBox;
  ListenFreqLabel.SetBounds(10, 62, 95, 15);
  ListenFreqLabel.Caption := 'Freq (MHz):';

  ListenFreqEdit := TFloatSpinEdit.Create(Self);
  ListenFreqEdit.Parent := ReceiverGroupBox;
  ListenFreqEdit.SetBounds(110, 58, 100, 23);
  ListenFreqEdit.DecimalPlaces := 3;
  ListenFreqEdit.Increment := 0.1;
  ListenFreqEdit.MinValue := 0;
  ListenFreqEdit.MaxValue := 999999;
  ListenFreqEdit.Value := FreqEdit.Value;
  ListenFreqEdit.OnEditingDone := @ListenFreqEditEditingDone;

  ListenKeypadButton := TButton.Create(Self);
  ListenKeypadButton.Parent := ReceiverGroupBox;
  ListenKeypadButton.SetBounds(220, 57, 100, 25);
  ListenKeypadButton.Caption := 'Keypad...';
  ListenKeypadButton.OnClick := @ListenKeypadButtonClick;

  // AM-only (ApplyListenModeVisibility hides these whenever FM is
  // selected) - see this unit's own header comment (LISTEN).
  BandwidthLabel := TLabel.Create(Self);
  BandwidthLabel.Parent := ReceiverGroupBox;
  BandwidthLabel.SetBounds(10, 100, 220, 15);

  BandwidthTrackBar := TTrackBar.Create(Self);
  BandwidthTrackBar.Parent := ReceiverGroupBox;
  BandwidthTrackBar.SetBounds(10, 118, 220, 30);
  // Position/10 = kHz, 0.1kHz steps - same "Position/10.0" convention
  // YGainTrackBar already uses for its own fractional control.
  BandwidthTrackBar.Min := Round(MinAMBandwidthHz / 100);
  BandwidthTrackBar.Max := Round(MaxAMBandwidthHz / 100);
  BandwidthTrackBar.Position := Round(DefaultAMBandwidthHz / 100);
  BandwidthTrackBar.Frequency := 10;
  BandwidthTrackBar.OnChange := @BandwidthTrackBarChange;

  SynchronousCheckBox := TCheckBox.Create(Self);
  SynchronousCheckBox.Parent := ReceiverGroupBox;
  SynchronousCheckBox.SetBounds(240, 122, 140, 19);
  SynchronousCheckBox.Caption := 'Synchronous';
  SynchronousCheckBox.OnChange := @SynchronousCheckBoxChange;

  // FM-only (ApplyListenModeVisibility hides this whenever AM is selected,
  // the opposite of BandwidthLabel/BandwidthTrackBar/SynchronousCheckBox
  // above - same row, since the two control sets are never shown
  // together) - toggles TFMBroadcastReceiver.ClickBlankerEnabled, i.e.
  // TFMDemodulator's own impulse blanker (see uDSPBlocks.pas's
  // TFMDemodulator.BlankerEnabled and uFMReceiver.pas's own
  // FClickBlankerEnabled for why this needs to be a live toggle rather
  // than always-on: tuned against one reception scenario, and a plausible
  // source of new artifacts in another).
  ClickBlankerCheckBox := TCheckBox.Create(Self);
  ClickBlankerCheckBox.Parent := ReceiverGroupBox;
  ClickBlankerCheckBox.SetBounds(10, 100, 220, 19);
  ClickBlankerCheckBox.Caption := 'Click Blanker';
  ClickBlankerCheckBox.Checked := True;
  ClickBlankerCheckBox.OnChange := @ClickBlankerCheckBoxChange;

  VolumeLabel := TLabel.Create(Self);
  VolumeLabel.Parent := ReceiverGroupBox;
  VolumeLabel.SetBounds(10, 160, 150, 15);
  VolumeLabel.Caption := 'Volume: 70%';

  VolumeTrackBar := TTrackBar.Create(Self);
  VolumeTrackBar.Parent := ReceiverGroupBox;
  VolumeTrackBar.SetBounds(10, 178, 220, 30);
  VolumeTrackBar.Min := 0;
  VolumeTrackBar.Max := 100;
  VolumeTrackBar.Position := 70;
  VolumeTrackBar.Frequency := 10;
  VolumeTrackBar.OnChange := @VolumeTrackBarChange;
  FReceiver.Volume := 0.7;
  FAMReceiver.Volume := 0.7;

  // See FAudioStatsTimer's own comment (above) for what this reports.
  AudioStatsLabel := TLabel.Create(Self);
  AudioStatsLabel.Parent := ReceiverGroupBox;
  AudioStatsLabel.AutoSize := True;   // 5 growing counters - don't clip
  AudioStatsLabel.ShowHint := True;   // hint carries the latest exception message, if any - see AudioStatsTimerTick
  AudioStatsLabel.SetBounds(10, 214, 400, 15);
  AudioStatsLabel.Caption := 'Audio: ring 0, acq-skip 0, drops 0, underruns 0, errors 0, dc-jump 0, clicks 0';

  BandwidthTrackBarChange(Self);   // sets BandwidthLabel's initial text
  ApplyListenModeVisibility;

  StatusLabel.Caption := 'Not connected';
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  if Assigned(FAnalyser) then FAnalyser.Active := False;
  if Assigned(FReceiver) then FReceiver.Active := False;
  if Assigned(FAMReceiver) then FAMReceiver.Active := False;
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

  // ListenFreqEdit isn't bounded any tighter than the device's own
  // hardware range here - it should really also stay within whatever's
  // currently captured (CenterFreqHz +- SampleRateHz/2), but that range
  // moves with every retune/rate change, so enforcing it precisely is
  // left as a soft user responsibility for this first cut (see this
  // unit's own header comment on ListenFreqEdit).
  ListenFreqEdit.MinValue := Caps.MinFreqHz / 1e6;
  ListenFreqEdit.MaxValue := Caps.MaxFreqHz / 1e6;
  ListenFreqEdit.Value := Caps.DefaultFreqHz / 1e6;

  // RateCombo's real items are only ever known here, post-Connect - but
  // on macOS (Cocoa widgetset, NSPopUpButton), a csDropDownList TComboBox
  // auto-fits its native control's width to content ONLY at first Show;
  // Items.Clear/.Add calls made afterward (i.e. always, for this combo)
  // never re-trigger that fit, leaving it stuck at its empty-at-creation
  // width forever - confirmed with an isolated throwaway LCL test: a
  // combo populated before first Show renders '10.667' in full, while an
  // identical one left empty until after Show and populated "late" (this
  // combo's own lifecycle) renders it clipped to '1' - reproducing the
  // exact symptom reported ("only shows one digit" above ~10Msps). Fixed
  // by giving RateCombo.Items.Strings a same-length placeholder in
  // uSDRMain.lfm ('10.667' - the widest realistic value across every
  // backend's SampleRates, e.g. RSP1A's 2-10.667Msps range) so the
  // native control auto-fits to a wide-enough size at that first Show,
  // which then persists through this Clear/Add regardless of platform -
  // same "pre-seed before first Show" idiom EpochCombo already gets for
  // free by having its own Items.Strings fully populated in the .lfm from
  // the start. Windows/GTK weren't observed to have this bug, but the
  // placeholder is harmless there either way.
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
  // Must come after UpdateFrequencyAxis - SpectrumCursorValue clamps
  // against the spectrum's current X-axis range, which UseFrequencyAxis/
  // XAxisMin/XAxisMax (set by UpdateFrequencyAxis) only just became valid
  // MHz bounds; set any earlier and this would clamp against the
  // constructor's own placeholder [0,1] domain instead.
  FAnalyser.SpectrumCursorValue := ListenFreqEdit.Value;
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
    FReceiver.Active := False;
    FAMReceiver.Active := False;
    ListenCheckBox.Checked := False;
    FEdgePanTimer.Enabled := False;
    FEdgePanDirection := 0;
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

// "select a station by dragging the cursor to a strong signal": fires on
// every real move of the spectrum's own draggable cursor (dragging,
// arrow keys, or FAnalyser.SpectrumCursorValue set programmatically -
// see uVMPlotSpectrum.pas's own OnCursorChange comment), and retunes
// FReceiver's software local oscillator to match, live, the same way
// ListenFreqEditEditingDone already does for typed entry - the two are
// just two different ways of moving the same "where within the capture
// am I listening" value. ListenFreqEdit is kept in sync purely so its
// displayed number doesn't silently go stale while dragging; it does NOT
// retune anything itself here (that would recurse into this handler via
// EditingDone, which only fires on focus loss/Enter, so no infinite loop
// either way).
//
// EDGE PANNING: dragging the cursor all the way to either edge of the
// currently-captured spectrum continuously retunes the RF front end's
// own centre frequency in that direction, for as long as the cursor
// stays at the edge - EdgePanTimerTick does the actual, repeated
// retuning (a fixed FRACTION of SampleRateHz per tick, not a one-shot
// jump), so the spectrum trace appears to scroll smoothly (right, when
// panning to lower frequencies at the left edge; left, at the right
// edge) rather than jumping abruptly. This handler's only job is
// updating FEdgePanDirection (-1/0/+1) and arming/disarming the timer to
// match wherever the cursor currently is; EdgePanTimerTick also
// explicitly re-pins SpectrumCursorValue to the current edge after each
// tick (see that method's own comment for why that's needed for this to
// stay self-sustaining) - which harmlessly re-enters this handler and
// re-confirms the SAME direction, not additional retuning (that only
// ever happens inside EdgePanTimerTick itself).
procedure TForm1.AnalyserCursorChanged(Sender: TObject);
begin
  ListenFreqEdit.Value := FAnalyser.SpectrumCursorValue;
  FReceiver.TunedFrequencyHz := FAnalyser.SpectrumCursorValue * 1e6;
  FAMReceiver.TunedFrequencyHz := FAnalyser.SpectrumCursorValue * 1e6;

  if FRFSource.IsOpen and (FAnalyser.XAxisMax > FAnalyser.XAxisMin) then begin
    if FAnalyser.SpectrumCursorValue <= FAnalyser.XAxisMin then
      FEdgePanDirection := -1
    else if FAnalyser.SpectrumCursorValue >= FAnalyser.XAxisMax then
      FEdgePanDirection := 1
    else
      FEdgePanDirection := 0;
  end else
    FEdgePanDirection := 0;
  FEdgePanTimer.Enabled := FEdgePanDirection <> 0;
end;

const
  // Fraction of SampleRateHz the centre frequency shifts per
  // FEdgePanTimer tick - proportional to sample rate (not a fixed Hz
  // value) so the visible scroll SPEED, in screen pixels/second, stays
  // roughly constant regardless of how wide the current capture is; a
  // fixed Hz/sec rate would look painfully slow on a wide capture and
  // dizzying on a narrow one. Scaled down to match FEdgePanTimer's own
  // 20ms interval (was 0.03 at 100ms, then 0.012 at 40ms) so the overall
  // rate - about 30% of SampleRateHz/second - stays roughly the same
  // throughout, just delivered in smaller, more frequent steps each time
  // the interval shortens, for smoother-looking motion; empirically
  // reasonable, not derived from anything more principled, revisit if it
  // still feels too fast/slow. 20ms sits right at Windows TTimer's own
  // real-world granularity floor (~15.6ms - see uSDRRFSource.pas's own
  // git history on TSDRPollThread for where this project first ran into
  // that limit), so this is close to as fast as a plain TTimer can
  // usefully go; a genuinely tighter tick would need a dedicated thread
  // the way that DSP-side polling does, not warranted here for what's
  // ultimately a cosmetic panning animation.
  EdgePanFraction = 0.006;

procedure TForm1.EdgePanTimerTick(Sender: TObject);
var
  NewCenterHz: Double;
begin
  if (FEdgePanDirection = 0) or not FRFSource.IsOpen then begin
    FEdgePanTimer.Enabled := False;
    Exit;
  end;

  NewCenterHz := FRFSource.CenterFreqHz + FEdgePanDirection * FRFSource.SampleRateHz * EdgePanFraction;
  NewCenterHz := EnsureRange(NewCenterHz, FRFSource.Capabilities.MinFreqHz, FRFSource.Capabilities.MaxFreqHz);
  CommitFrequencyHz(Round(NewCenterHz));

  // Re-pin the cursor to the edge it's panning from - without this, the
  // cursor's own absolute frequency (unchanged by the retune itself)
  // would drift slightly INSIDE the newly-shifted window each tick
  // (RecomputeBounds only re-clamps if a value falls OUTSIDE the new
  // axis range, and a small per-tick shift generally doesn't push it
  // that far), so continued genuine mouse movement would be needed to
  // keep it pinned at the edge - this keeps panning self-sustaining even
  // if the user's mouse is simply held stationary at the control's edge
  // (no fresh MouseMove events to re-clamp it otherwise).
  if FEdgePanDirection < 0 then
    FAnalyser.SpectrumCursorValue := FAnalyser.XAxisMin
  else
    FAnalyser.SpectrumCursorValue := FAnalyser.XAxisMax;
end;

// Shared by FreqEditEditingDone and KeypadButtonClick - live retune,
// works whether or not RX is currently running, on any backend. Async
// (TSDRRFSource.RequestFrequencyHz, uSDRRFSource.pas's own ASYNC RETUNE
// header comment) so a slow vendor driver call (confirmed, real-world:
// this used to freeze the whole application until Task Manager-killed)
// never blocks the GUI thread - RFSourceFrequencyChanged reports the
// actual outcome once it's known, rather than this returning it directly.
procedure TForm1.CommitFrequencyHz(Hz: QWord);
begin
  if not FRFSource.IsOpen then Exit;
  FRFSource.RequestFrequencyHz(Hz);
end;

// Fires once a RequestFrequencyHz call actually completes (see
// uSDRRFSource.pas's own OnFrequencyChanged/ASYNC RETUNE comments), via
// TThread.Queue - possibly well after CommitFrequencyHz itself already
// returned, and (unlike the original synchronous call, which could only
// ever run once any modal dialog had already fully closed) at an
// otherwise-unpredictable moment relative to the GUI's own state. If a
// modal dialog (e.g. the frequency keypad, uFreqKeypad.pas - the
// keypad's own commit button calls CommitFrequencyHz right before its
// ModalResult closes it) is still active/tearing down right now,
// UpdateFrequencyAxis's own Invalidate calls on FAnalyser's OpenGL
// controls would run concurrently with that teardown - defer via
// FFreqRetryTimer instead of risking it.
procedure TForm1.RFSourceFrequencyChanged(Sender: TObject);
begin
  if Application.ModalLevel > 0 then begin
    FFreqRetryTimer.Enabled := True;
    Exit;
  end;
  ApplyFrequencyChangedUI;
end;

procedure TForm1.FreqRetryTimerTick(Sender: TObject);
begin
  FFreqRetryTimer.Enabled := False;
  RFSourceFrequencyChanged(Self);   // re-checks ModalLevel; re-arms itself if still modal
end;

// See FAudioStatsTimer's own comment (FormCreate) for why this exists.
// Four counters, ordered upstream-to-downstream along the signal path, so
// whichever one is actually incrementing pinpoints the stage at fault:
//   ring      - TSDRRFSource.DeviceOverflowBytes (uSDRDevice.pas's
//               TSDRRingBuffer, the device-level USB-callback buffer)
//               overwriting itself because FPollThread isn't draining it
//               fast enough - a real IQ discontinuity before ANY of this
//               app's own DSP ever sees the data. Independent of which
//               receiver (if any) is active.
//   acq-skip  - TFMBroadcastReceiver/TAMBroadcastReceiver's own
//               AudioAcquireSkipCount: THIS receiver's own FSourceCursor
//               fell behind FStreamRing's capacity and had to jump
//               forward - a real IQ discontinuity one stage later than
//               "ring". Deliberately NOT TSDRRFSource.StreamSkipCount
//               (the aggregate across every consumer, spectrum analyser
//               included) - confirmed by testing that the spectrum
//               analyser's own cursor skips constantly by design (it
//               only ever wants the newest snapshot, not a continuous
//               stream) even with Listen off and no receiver acquiring
//               anything at all, which made the aggregate number
//               useless for attributing an audio click specifically -
//               see TSDRRFSource.pas's own TryReadEpoch 4-arg overload.
//   drops     - FM only (uAMReceiver.pas has no equivalent hand-off queue -
//               see its own header comment for why AM needs only one
//               thread) - TFMBroadcastReceiver.AudioDropCount,
//               FDemodThread falling behind FAcquireThread.
//   underruns - TWaveOutPlayer.UnderrunCount, the ALSA output ring itself
//               genuinely starving.
//   errors    - TFMBroadcastReceiver/TAMBroadcastReceiver.AudioErrorCount:
//               total exceptions caught and swallowed inside per-epoch DSP
//               processing (TFMAcquireThread/TFMDemodThread/TAMDSPThread's
//               own Execute methods) - each one is a silently dropped or
//               corrupted epoch that none of the four counters above can
//               see, since it happens INSIDE processing, not at an I/O
//               boundary. The most recent exception's own message is set
//               as this label's Hint (hover to read it) rather than
//               crammed into the caption itself.
//   dc-jump   - uSDRDevice.pas's DCCorrectionJumpCount: how many times
//               CorrectIQEpoch's blind, independently-recomputed-every-
//               epoch DC-offset estimate has jumped by more than
//               DCJumpThreshold from the previous epoch's own estimate.
//               Unlike every counter above, this ISN'T a dropped/skipped/
//               corrupted epoch - every sample is present and accounted
//               for - it's a genuine discontinuity CorrectIQEpoch itself
//               introduces into otherwise-intact data, the one candidate
//               left once ring/acq-skip/drops/underruns/errors are all
//               confirmed clean. Global (not per-receiver), since
//               CorrectIQEpoch runs once per TryReadEpoch regardless of
//               which receiver is listening.
//   clicks    - FM only (envelope/synchronous AM detection isn't a polar
//               discriminator and has no equivalent phase-wrap failure
//               mode) - TFMBroadcastReceiver.AudioClickCount, confirmed
//               FM click-noise events TFMDemodulator's own impulse
//               blanker has suppressed (see that class's own Process
//               comment, uDSPBlocks.pas) - a climbing count here IS the
//               originally-reported audible clicking, now caught and
//               silenced rather than heard.
// "ring"/"dc-jump" always come straight from FRFSource/uSDRDevice, active
// receiver or not; "acq-skip"/"drops"/"underruns"/"errors"/"clicks" only
// exist once a receiver is Active (StartSelectedReceiver guarantees at
// most one of FReceiver/FAMReceiver ever is), so they read 0 otherwise.
procedure TForm1.AudioStatsTimerTick(Sender: TObject);
begin
  if FReceiver.Active then begin
    AudioStatsLabel.Caption := Format('Audio: ring %d, acq-skip %d, drops %d, underruns %d, errors %d, dc-jump %d, clicks %d',
      [FRFSource.DeviceOverflowBytes, FReceiver.AudioAcquireSkipCount,
       FReceiver.AudioDropCount, FReceiver.AudioUnderrunCount, FReceiver.AudioErrorCount,
       DCCorrectionJumpCount, FReceiver.AudioClickCount]);
    AudioStatsLabel.Hint := FReceiver.LastError;
  end else if FAMReceiver.Active then begin
    AudioStatsLabel.Caption := Format('Audio: ring %d, acq-skip %d, drops -, underruns %d, errors %d, dc-jump %d, clicks -',
      [FRFSource.DeviceOverflowBytes, FAMReceiver.AudioAcquireSkipCount,
       FAMReceiver.AudioUnderrunCount, FAMReceiver.AudioErrorCount, DCCorrectionJumpCount]);
    AudioStatsLabel.Hint := FAMReceiver.LastError;
  end else begin
    AudioStatsLabel.Caption := Format('Audio: ring %d, acq-skip 0, drops 0, underruns 0, errors 0, dc-jump %d, clicks 0',
      [FRFSource.DeviceOverflowBytes, DCCorrectionJumpCount]);
    AudioStatsLabel.Hint := '';
  end;
end;

procedure TForm1.ApplyFrequencyChangedUI;
begin
  if not FRFSource.LastFrequencyChangeOk then begin
    ReportError('set_freq');
    Exit;
  end;
  // Reads back the CONFIRMED centre frequency (this only runs once the
  // async retune has actually completed - see uSDRRFSource.pas's own
  // ASYNC RETUNE header comment), so FreqEdit stays correct regardless
  // of which of the several ways a retune can be triggered
  // (FreqEditEditingDone, KeypadButtonClick, or the spectrum cursor's
  // own edge-panning in AnalyserCursorChanged) - KeypadButtonClick used
  // to be the only one that separately, manually kept FreqEdit in sync
  // before committing; AnalyserCursorChanged's edge-panning had no such
  // step and left FreqEdit stale, which is what this fixes centrally
  // rather than requiring every future retune call site to remember to
  // do it themselves.
  FreqEdit.Value := FRFSource.CenterFreqHz / 1e6;
  UpdateFrequencyAxis;
  if FRFSource.IsStreaming then
    StatusLabel.Caption := Format('Streaming (%s) @ %.3f MHz, %.3f Msps',
      [FRFSource.Capabilities.DeviceName, FRFSource.CenterFreqHz / 1e6, FRFSource.SampleRateHz / 1e6]);
end;

procedure TForm1.FreqEditEditingDone(Sender: TObject);
begin
  CommitFrequencyHz(Round(FreqEdit.Value * 1e6));
end;

// Runs the popup numeric keypad (uFreqKeypad.pas) with FAnalyser's own
// GPU/OpenCL repaint timer paused for the dialog's duration - confirmed,
// via direct Win32 message injection into the keypad's own controls
// (bypassing mouse/focus entirely), that its modal loop genuinely stops
// processing input while streaming - every button, including Cancel and
// the window's own Close button, silently did nothing - but ONLY while
// streaming; idle, the same dialog works fine. The one thing that
// differs is FAnalyser's own GUI-thread timer, driving GPU/OpenCL Paint
// calls on TVMPlotSpectrum/TVMPlotWaterfall roughly every 30ms; the
// leading theory is that call, when it fires from inside the keypad's
// *nested* modal message loop rather than the app's normal top-level
// one, hits a GL-driver/reentrancy issue neither control has otherwise
// been exercised against (this codebase has hit GL-vs-host-message-loop
// surprises before - see uVMPlotSpectrum.pas/uVMPlot3D.pas's own
// design-time-rendering history). Nothing behind a modal dialog is
// visible anyway, and FRFSource's own FPollThread keeps draining the
// device in the background regardless (streaming/acquisition isn't
// touched here, only this component's own repaint timer), so pausing it
// for the dialog's duration costs nothing and sidesteps whatever the
// exact mechanism is - confirmed via the same direct-message-injection
// technique that this actually restores normal, responsive click
// handling inside the keypad. Shared by both KeypadButtonClick (retunes
// the RF front end) and ListenKeypadButtonClick (retunes FReceiver's own
// software local oscillator) - identical dialog, different only in what
// each caller does with a committed ResultHz.
function TForm1.RunFrequencyKeypad(MinHz, MaxHz: Double; out ResultHz: Double): Boolean;
var
  WasAnalyserActive: Boolean;
begin
  WasAnalyserActive := FAnalyser.Active;
  FAnalyser.Active := False;
  try
    Result := ShowFrequencyKeypad(MinHz, MaxHz, ResultHz);
  finally
    FAnalyser.Active := WasAnalyserActive;
  end;
end;

// Opens the popup numeric keypad, clamped to whatever frequency range the
// connected device actually supports (or unclamped - 0/0 - if none is
// connected yet, since FreqEdit.MinValue/MaxValue still hold their
// generic .lfm defaults at that point rather than a real device's
// range). On a committed entry, keeps FreqEdit's own displayed value in
// sync before retuning, so the two controls never disagree with each
// other.
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

  if RunFrequencyKeypad(MinHz, MaxHz, ResultHz) then begin
    FreqEdit.Value := ResultHz / 1e6;
    CommitFrequencyHz(Round(ResultHz));
  end;
end;

// Same popup keypad, but for FReceiver's own software local oscillator
// (ListenFreqEdit) instead of the RF front end's centre frequency - the
// keypad-entry analogue of ListenFreqEditEditingDone, the same
// relationship KeypadButtonClick has to FreqEditEditingDone. Clamped to
// the same device-capability range as the centre-frequency keypad; in
// principle ListenFreqEdit should stay within the currently-captured
// bandwidth (CenterFreqHz +- SampleRateHz/2), but as with ListenFreqEdit
// itself (see this unit's own header comment), enforcing that precisely
// is left as a soft user responsibility.
procedure TForm1.ListenKeypadButtonClick(Sender: TObject);
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

  if RunFrequencyKeypad(MinHz, MaxHz, ResultHz) then begin
    ListenFreqEdit.Value := ResultHz / 1e6;
    FReceiver.TunedFrequencyHz := ResultHz;
    FAMReceiver.TunedFrequencyHz := ResultHz;
    FAnalyser.SpectrumCursorValue := ResultHz / 1e6;
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
// - a display-only shift of the whole trace, independent of YGain. Uses
// FAnalyser's own unified YOffset (uVMPlotSDRSpectrum.pas), not
// SpectrumYOffset, so this recolours the waterfall's own colour gradient
// in synchrony with the spectrum trace, not just the spectrum plot alone.
procedure TForm1.YOffsetTrackBarChange(Sender: TObject);
begin
  FAnalyser.YOffset := YOffsetTrackBar.Position;
  YOffsetLabel.Caption := Format('Y Zero: %d dB', [YOffsetTrackBar.Position]);
end;

// TTrackBar positions are integers, so this maps Position 1..50 to a
// 0.1x..5.0x gain in 0.1 steps (Position/10) rather than exposing
// TVMPlotSpectrum.YGain's real-valued range directly on the slider - see
// that property's own comment for what YGain does. Uses FAnalyser's own
// unified YGain (see YOffsetTrackBarChange's own comment for why).
procedure TForm1.YGainTrackBarChange(Sender: TObject);
var
  Gain: Double;
begin
  Gain := YGainTrackBar.Position / 10.0;
  FAnalyser.YGain := Gain;
  YGainLabel.Caption := Format('Y Gain: %.1fx', [Gain]);
end;

// Shows/hides the AM-only controls (BandwidthLabel/BandwidthTrackBar/
// SynchronousCheckBox) per ModeCombo - see this unit's own header
// comment (LISTEN) for why FM has no equivalent controls of its own.
procedure TForm1.ApplyListenModeVisibility;
var
  IsAM: Boolean;
begin
  IsAM := ModeCombo.Text = 'AM';
  BandwidthLabel.Visible := IsAM;
  BandwidthTrackBar.Visible := IsAM;
  SynchronousCheckBox.Visible := IsAM;
  ClickBlankerCheckBox.Visible := not IsAM;
end;

// Reflects whichever receiver's own channel bandwidth is currently
// selected as the shaded band drawn around the spectrum cursor (see
// uVMPlotSpectrum.pas's own CursorBandwidth property comment) - FM's is
// fixed (broadcast FM's own 200kHz channel spec, uFMReceiver.pas's
// DefaultBasebandRateHz), AM's tracks BandwidthTrackBar live, doubled -
// uAMReceiver.pas's own BasebandRateHz = BandwidthHz*2 is the full
// occupied RF span (both sidebands), not just the audio bandwidth the
// slider itself is labelled in.
procedure TForm1.UpdateCursorBandwidth;
begin
  if ModeCombo.Text = 'AM' then
    FAnalyser.SpectrumCursorBandwidth := (BandwidthTrackBar.Position * 100 * 2) / 1e6
  else
    FAnalyser.SpectrumCursorBandwidth := 0.2;
end;

// Activates whichever ONE of FReceiver/FAMReceiver ModeCombo currently
// selects - called from both ListenCheckBoxChange (turning Listen on)
// and ModeComboChange (switching mode while already listening). Only
// ever one of the two is Active at a time; the caller is responsible for
// having already stopped the other one first (both call sites do).
procedure TForm1.StartSelectedReceiver;
begin
  if ModeCombo.Text = 'AM' then begin
    // BandwidthTrackBarChange already keeps FAMReceiver.BandwidthHz in
    // sync live (see that handler's own comment) regardless of when it
    // was last touched, so no need to push it again here.
    FAMReceiver.Synchronous := SynchronousCheckBox.Checked;
    FAMReceiver.Active := True;
  end else
    FReceiver.Active := True;
end;

// Starts/stops the onward-CPU receive chain (uFMReceiver.pas/
// uAMReceiver.pas, per ModeCombo) - only meaningful once FRFSource is
// actually streaming, same requirement TFMBroadcastReceiver/
// TAMBroadcastReceiver's own SetActive enforces (Active silently stays
// False if Source isn't open yet).
procedure TForm1.ListenCheckBoxChange(Sender: TObject);
begin
  FReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAMReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAnalyser.SpectrumCursorValue := ListenFreqEdit.Value;
  if ListenCheckBox.Checked then
    StartSelectedReceiver
  else begin
    FReceiver.Active := False;
    FAMReceiver.Active := False;
  end;
end;

// Switches which receiver is actually running, live, if Listen is
// already checked - stop whichever was active, start the newly selected
// one at the same frequency (both receivers already have the right
// TunedFrequencyHz cached regardless of which was previously active -
// see this unit's own header comment, LISTEN).
procedure TForm1.ModeComboChange(Sender: TObject);
begin
  ApplyListenModeVisibility;
  UpdateCursorBandwidth;
  if ListenCheckBox.Checked then begin
    FReceiver.Active := False;
    FAMReceiver.Active := False;
    StartSelectedReceiver;
  end;
end;

// Live retune - only touches the receive chain's own mixer (see
// TFMBroadcastReceiver.SetTunedFrequencyHz's own comment for why this is
// safe to do without interrupting playback), works whether or not
// either receiver is currently Active. Also moves the spectrum cursor to
// match (which harmlessly re-fires AnalyserCursorChanged with the same
// values - see that handler's own comment), so the two ways of choosing
// a frequency - typing here, or dragging the cursor - always agree on
// where the cursor is drawn.
procedure TForm1.ListenFreqEditEditingDone(Sender: TObject);
begin
  FReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAMReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAnalyser.SpectrumCursorValue := ListenFreqEdit.Value;
end;

// AM Bandwidth slider (Position*100 = Hz, 0.1kHz steps) - pushed to
// FAMReceiver live, whether or not it's currently Active (harmless
// no-op there beyond caching the value - see
// TAMBroadcastReceiver.SetBandwidthHz's own comment for why applying it
// while Active is also safe, just not glitch-free).
procedure TForm1.BandwidthTrackBarChange(Sender: TObject);
begin
  BandwidthLabel.Caption := Format('AM Bandwidth: %.1f kHz', [BandwidthTrackBar.Position / 10.0]);
  FAMReceiver.BandwidthHz := BandwidthTrackBar.Position * 100;
  UpdateCursorBandwidth;
end;

// Safe to change live - see uDSPBlocks.pas's own TAMDemodulator header
// comment for why toggling this doesn't glitch the audio.
procedure TForm1.SynchronousCheckBoxChange(Sender: TObject);
begin
  FAMReceiver.Synchronous := SynchronousCheckBox.Checked;
end;

// See ClickBlankerCheckBox's own comment (FormCreate) for what this
// toggles. Safe to change live, whether or not FReceiver is currently
// Active - FClickBlankerEnabled is a plain field TFMBroadcastReceiver
// pushes into FDemod fresh every epoch, same as Volume.
procedure TForm1.ClickBlankerCheckBoxChange(Sender: TObject);
begin
  FReceiver.ClickBlankerEnabled := ClickBlankerCheckBox.Checked;
end;

procedure TForm1.VolumeTrackBarChange(Sender: TObject);
begin
  FReceiver.Volume := VolumeTrackBar.Position / 100.0;
  FAMReceiver.Volume := VolumeTrackBar.Position / 100.0;
  VolumeLabel.Caption := Format('Volume: %d%%', [VolumeTrackBar.Position]);
end;

end.
