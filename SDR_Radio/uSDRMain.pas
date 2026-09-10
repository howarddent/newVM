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
  StdCtrls, ComCtrls, Spin, IniFiles, LazLogger,
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
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
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
    FShutdownDone: Boolean;

    // Remembered front-end state - see LoadSettings for what each holds
    // when nothing was remembered, and CaptureFrontEnd for how they are
    // kept current within a session.
    FPrefDevice: string;
    FPrefRateHz: Int64;
    FPrefGain0, FPrefGain1, FPrefGain2, FPrefBiasT: Integer;

    procedure ShutdownAll;
    function SettingsFileName: string;
    procedure SaveSettings;
    procedure LoadSettings;
    procedure CaptureFrontEnd;
    procedure SnapListenIntoSpan;
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

const
  // "nothing was remembered for this one" for the integer-valued
  // front-end preferences. A real trackbar position or 0/1 checkbox
  // state can never collide with it.
  PrefAbsent = Low(Integer);

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

  // Last, deliberately: ListenFreqEdit only exists a few lines above,
  // and takes its initial value from FreqEdit, so anything restored
  // before this point would just be overwritten again.
  LoadSettings;

  StatusLabel.Caption := 'Not connected';
end;

{ Both routes into shutdown call the same thing.

  OnClose is the one that matters: it fires while the window and its
  handle are still alive, with the widgetset fully up, which is the only
  point at which tearing down a GL context, a running audio backend and a
  USB device is unambiguously safe. OnDestroy runs far later - after the
  handle has gone on some widgetsets - and is kept here purely as a net
  for the paths that never raise OnClose at all (Application.Terminate
  called directly, a session ending under us). ShutdownAll is idempotent,
  so whichever arrives second does nothing. }
procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  ShutdownAll;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  ShutdownAll;
end;

{ Ordered shutdown: stop the demodulators, then release the device, then
  free the memory, and only then let the application close.

  This used to be four bare lines in FormDestroy, and the device was
  reported as still claimed after closing the window on some platforms.
  Three things about that old version explain it, and all three are what
  the structure below is for.

  FIRST, EVERY STAGE IS GUARDED. The old sequence deactivated the
  analyser, then the two receivers, then freed the RF source - in that
  order, unguarded, so an exception anywhere in the first three lines
  meant the fourth never ran and the device was left open with the
  process exiting around it. Those first three lines are exactly the ones
  that can raise: they tear down an OpenGL context and an audio backend,
  both of which are platform code with platform-specific failure modes.
  Releasing the hardware must not be reachable only through their
  success, so each stage below runs in its own try/except and the ones
  after it run regardless.

  SECOND, THE TIMERS GO OFF FIRST. FAudioStatsTimer fires every second
  and dereferences FReceiver, FAMReceiver and FRFSource unconditionally
  (see AudioStatsTimerTick); FEdgePanTimer and FFreqRetryTimer likewise
  reach into the source. Left running, any of them can land in the middle
  of the teardown below and fault on a half-freed object - which is
  precisely the kind of fault that appears on one platform and not
  another, since it depends entirely on where the tick happens to fall.

  THIRD, THE ORDER IS EXPLICIT RATHER THAN INHERITED. Everything here is
  owned by the form, so all of it would eventually be freed by component
  destruction anyway - but in whatever order TComponent happens to hold
  them, which is not something this unit should depend on. Consumers of
  the stream (the receivers, then the analyser) are stopped before the
  source they read from is torn down, and freed before it too. }
procedure TForm1.ShutdownAll;
var
  Failures: string;

  procedure Failed(const Stage: string; E: Exception);
  begin
    if Failures <> '' then Failures := Failures + '; ';
    Failures := Failures + Stage + ' (' + E.ClassName + ': ' + E.Message + ')';
  end;

begin
  if FShutdownDone then Exit;
  FShutdownDone := True;
  Failures := '';

  // 0. Nothing may fire into a half-torn-down object - see above.
  try
    if Assigned(FAudioStatsTimer) then FAudioStatsTimer.Enabled := False;
    if Assigned(FEdgePanTimer) then FEdgePanTimer.Enabled := False;
    if Assigned(FFreqRetryTimer) then FFreqRetryTimer.Enabled := False;
    FEdgePanDirection := 0;
  except
    on E: Exception do Failed('timers', E);
  end;

  // 1. Remembered settings, before anything that could fail has run. The
  //    values come from the two edit controls, which outlive all of
  //    this, so the only reason to do it this early is that a later
  //    stage failing must not cost the user their tuning.
  try
    SaveSettings;
  except
    on E: Exception do Failed('save_settings', E);
  end;

  // 2. Demodulators. Each stops and joins its own DSP threads and closes
  //    the audio backend (and, on macOS, ends the helper process that
  //    owns CoreAudio - see uWaveOutPlayer.pas), so this is the stage
  //    most likely to be slow and the one most likely to raise.
  try
    if Assigned(FReceiver) then FReceiver.Active := False;
  except
    on E: Exception do Failed('fm_receiver', E);
  end;

  try
    if Assigned(FAMReceiver) then FAMReceiver.Active := False;
  except
    on E: Exception do Failed('am_receiver', E);
  end;

  // 3. The analyser is the other consumer of the stream, and owns the GL
  //    context - stopped here, still inside the window's lifetime.
  try
    if Assigned(FAnalyser) then FAnalyser.Active := False;
  except
    on E: Exception do Failed('analyser', E);
  end;

  // 4. The device itself, now that nothing is reading from it. Stop and
  //    join the poll/control threads first, then close the hardware.
  //    Disconnect does both, but calling StopStreaming explicitly keeps
  //    the sequence readable and means a failure inside the thread join
  //    still leaves the close below to run.
  try
    if Assigned(FRFSource) then FRFSource.StopStreaming;
  except
    on E: Exception do Failed('stop_streaming', E);
  end;

  try
    if Assigned(FRFSource) then FRFSource.Disconnect;
  except
    on E: Exception do Failed('disconnect', E);
  end;

  // 5. Memory, consumers before source. FreeAndNil rather than Free so
  //    that anything reaching one of these later - a queued LCL message,
  //    a stray event - finds nil rather than a stale pointer.
  try
    FreeAndNil(FReceiver);
  except
    on E: Exception do Failed('free_fm_receiver', E);
  end;

  try
    FreeAndNil(FAMReceiver);
  except
    on E: Exception do Failed('free_am_receiver', E);
  end;

  try
    FreeAndNil(FAnalyser);
  except
    on E: Exception do Failed('free_analyser', E);
  end;

  try
    FreeAndNil(FRFSource);
  except
    on E: Exception do Failed('free_rf_source', E);
  end;

  // Reported, not swallowed - but not in a dialog either: this runs
  // while the window is on its way out, and a modal box at that point is
  // both unwelcome and, on some widgetsets, a good way to make the
  // teardown worse. The device is released either way by the time this
  // line is reached, which is the whole point of the guards above.
  if Failures <> '' then
    DebugLn('SDR_Radio shutdown: ' + Failures);
end;

{ WHERE THE REMEMBERED SETTINGS LIVE

  GetAppConfigFile(False) - per-user, not next to the executable. A
  program directory is very often read-only (Program Files, an app
  bundle, /usr/local/bin) and writing there either fails outright or is
  silently redirected somewhere the next run will not look. This gives a
  per-user path the OS already guarantees is writable, on every platform
  this app builds for. }
function TForm1.SettingsFileName: string;
begin
  Result := GetAppConfigFile(False);
end;

{ Frequencies are stored as INTEGER HERTZ, written and read as plain
  digit strings.

  Not as floating-point MHz: TIniFile's ReadFloat/WriteFloat go through
  the default format settings, so on a machine whose locale uses a comma
  as the decimal separator they would write "95,3" - which reads back
  correctly there and as nonsense anywhere else, including on the same
  machine after a locale change. Hertz is what the device API takes
  anyway (see CommitFrequencyHz and StartStopButtonClick, both of which
  convert the edit's MHz to Hz at the point of use), and a whole number
  of hertz has no separator to get wrong.

  It will not fit an Integer, either: 6 GHz is past 2^31, so
  WriteInteger/ReadInteger are not usable here. Hence plain strings and
  StrToInt64Def. }
{ Take the live front-end controls into the remembered state.

  Only meaningful while a device is open: the sample-rate list and every
  gain control are built by ApplyDeviceCapabilities from the connected
  radio's own capabilities, so before a connect they hold design-time
  placeholders that mean nothing. Hence the early exit - what is already
  remembered (from the file, or from an earlier connect this session) is
  better than what the controls would say.

  Called on disconnect and again at shutdown, which is what makes a
  reconnect within one session come back to where the user actually was
  rather than to whatever the file said at launch.

  The sample rate is taken from the CAPABILITY the combo's index refers
  to, not by parsing its text: the items are formatted with
  FormatFloat, so their text carries the locale's decimal separator, and
  reading it back would be one more thing to get wrong on a machine
  configured differently from the one that wrote it. }
procedure TForm1.CaptureFrontEnd;
var
  Caps: TSDRCapabilities;
begin
  if not FRFSource.IsOpen then Exit;

  Caps := FRFSource.Capabilities;
  FPrefDevice := Caps.DeviceName;

  if (RateCombo.ItemIndex >= 0) and (RateCombo.ItemIndex <= High(Caps.SampleRates)) then
    FPrefRateHz := Round(Caps.SampleRates[RateCombo.ItemIndex]);

  if GainStage0TrackBar.Visible then FPrefGain0 := GainStage0TrackBar.Position;
  if GainStage1TrackBar.Visible then FPrefGain1 := GainStage1TrackBar.Position;
  if GainStage2CheckBox.Visible then FPrefGain2 := Ord(GainStage2CheckBox.Checked);
  if BiasTCheckBox.Visible then FPrefBiasT := Ord(BiasTCheckBox.Checked);
end;

{ Bring the demodulator inside the span the radio is actually capturing.

  A remembered listen frequency is absolute, and the span it has to live
  in is the local oscillator plus or minus half the sample rate - so a
  perfectly reasonable saved pair (95 MHz local oscillator, 88 MHz
  demodulator) can describe a demodulator the receiver cannot reach,
  because 88 is nowhere in the 94-96 MHz being captured. Clamping it to
  the near edge is the useful answer: the cursor lands somewhere real,
  the receiver has signal to work on, and the user can retune the local
  oscillator to go and fetch the frequency they actually wanted.

  Computed from the source's own centre frequency and sample rate - the
  same two numbers UpdateFrequencyAxis builds the X axis from - rather
  than by reading the axis back off the plot. The plot clamps its cursor
  against the range it has actually recomputed bounds for, which is not
  necessarily the range just assigned to it, so the source is the
  authority here and the plot is told, not asked. }
procedure TForm1.SnapListenIntoSpan;
var
  LoMHz, HiMHz: Double;
begin
  if not FRFSource.IsOpen then Exit;
  if FRFSource.SampleRateHz <= 0 then Exit;

  LoMHz := (FRFSource.CenterFreqHz - FRFSource.SampleRateHz / 2) / 1e6;
  HiMHz := (FRFSource.CenterFreqHz + FRFSource.SampleRateHz / 2) / 1e6;

  if ListenFreqEdit.Value < LoMHz then
    ListenFreqEdit.Value := LoMHz
  else if ListenFreqEdit.Value > HiMHz then
    ListenFreqEdit.Value := HiMHz
  else
    Exit;   // already inside - leave it exactly where it was

  FReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAMReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
end;

procedure TForm1.SaveSettings;
var
  Ini: TIniFile;
begin
  // Whatever is live wins over whatever was loaded at launch.
  CaptureFrontEnd;

  ForceDirectories(ExtractFilePath(SettingsFileName));

  Ini := TIniFile.Create(SettingsFileName);
  try
    Ini.WriteString('Tuning', 'LocalOscillatorHz', IntToStr(Round(FreqEdit.Value * 1e6)));
    Ini.WriteString('Tuning', 'DemodulatorHz', IntToStr(Round(ListenFreqEdit.Value * 1e6)));

    // The front-end block is stamped with the radio it came from - see
    // LoadSettings/ApplyDeviceCapabilities for why that matters. Absent
    // entries are written as nothing at all rather than as a sentinel,
    // so a file that never saw a connect stays honest about it.
    if FPrefDevice <> '' then
      Ini.WriteString('FrontEnd', 'Device', FPrefDevice);
    if FPrefRateHz > 0 then
      Ini.WriteString('FrontEnd', 'SampleRateHz', IntToStr(FPrefRateHz));
    if FPrefGain0 <> PrefAbsent then
      Ini.WriteString('FrontEnd', 'GainStage0', IntToStr(FPrefGain0));
    if FPrefGain1 <> PrefAbsent then
      Ini.WriteString('FrontEnd', 'GainStage1', IntToStr(FPrefGain1));
    if FPrefGain2 <> PrefAbsent then
      Ini.WriteString('FrontEnd', 'GainStage2', IntToStr(FPrefGain2));
    if FPrefBiasT <> PrefAbsent then
      Ini.WriteString('FrontEnd', 'BiasT', IntToStr(FPrefBiasT));

    Ini.UpdateFile;
  finally
    Ini.Free;
  end;
end;

{ Restore what SaveSettings wrote, if it is still usable.

  Each value is applied only when it falls inside the control's current
  range, so a missing file, an empty entry, a hand-edited one, or one
  saved against a different radio all fall back to the existing default
  rather than being silently clamped to a bound and presented as though
  the user had chosen it.

  What this does NOT do is push the local oscillator at the hardware:
  nothing is connected this early, CommitFrequencyHz would return
  immediately anyway, and StartStopButtonClick reads FreqEdit.Value when
  streaming starts - so restoring the control is the whole job. The
  demodulator frequency does get pushed into both receivers, since they
  hold their own tuned frequency rather than reading the control. The
  analyser's cursor is deliberately left alone: it clamps against the
  spectrum's X axis, which is still the constructor's placeholder domain
  until a device is connected, and ConnectButtonClick already sets it at
  the point that range becomes real. }
procedure TForm1.LoadSettings;
var
  Ini: TIniFile;
  Hz: Int64;
  MHz: Double;

  function ReadPref(const Key: string): Integer;
  begin
    Result := StrToIntDef(Ini.ReadString('FrontEnd', Key, ''), PrefAbsent);
  end;

begin
  // Nothing remembered until proven otherwise. ApplyDeviceCapabilities
  // reads these on every connect, so they have to say "absent" rather
  // than zero on a first run - a gain of 0 is a real setting.
  FPrefDevice := '';
  FPrefRateHz := 0;
  FPrefGain0 := PrefAbsent;
  FPrefGain1 := PrefAbsent;
  FPrefGain2 := PrefAbsent;
  FPrefBiasT := PrefAbsent;

  if not FileExists(SettingsFileName) then Exit;

  Ini := TIniFile.Create(SettingsFileName);
  try
    Hz := StrToInt64Def(Ini.ReadString('Tuning', 'LocalOscillatorHz', ''), 0);
    MHz := Hz / 1e6;
    if (Hz > 0) and (MHz >= FreqEdit.MinValue) and (MHz <= FreqEdit.MaxValue) then
      FreqEdit.Value := MHz;

    Hz := StrToInt64Def(Ini.ReadString('Tuning', 'DemodulatorHz', ''), 0);
    MHz := Hz / 1e6;
    if (Hz > 0) and (MHz >= ListenFreqEdit.MinValue) and (MHz <= ListenFreqEdit.MaxValue) then begin
      ListenFreqEdit.Value := MHz;
      FReceiver.TunedFrequencyHz := MHz * 1e6;
      FAMReceiver.TunedFrequencyHz := MHz * 1e6;
    end;

    // The front end is only read here, not applied - none of these
    // controls mean anything until a device is open and
    // ApplyDeviceCapabilities has built them from its capabilities,
    // which is where these get used.
    FPrefDevice := Ini.ReadString('FrontEnd', 'Device', '');
    FPrefRateHz := StrToInt64Def(Ini.ReadString('FrontEnd', 'SampleRateHz', ''), 0);
    FPrefGain0 := ReadPref('GainStage0');
    FPrefGain1 := ReadPref('GainStage1');
    FPrefGain2 := ReadPref('GainStage2');
    FPrefBiasT := ReadPref('BiasT');
  finally
    Ini.Free;
  end;
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
  WantLOMHz, WantListenMHz, LoMHz, HiMHz: Double;
  PrefsMatch: Boolean;
begin
  Caps := FRFSource.Capabilities;

  // Remembered front-end settings only apply to the radio they were
  // saved from - see the gain block at the end of this method for why.
  PrefsMatch := (FPrefDevice <> '') and (FPrefDevice = Caps.DeviceName);

  Caption := 'newVM ' + Caps.DeviceName + ' Spectrum Analyser';
  FAnalyser.SpectrumTitle := Caps.DeviceName + ' Spectrum';
  FAnalyser.WaterfallTitle := Caps.DeviceName + ' Waterfall';

  // Where the user is already tuned survives a connect if the device can
  // reach it - which is what makes the remembered frequencies of the
  // last session actually stick. This used to overwrite both edits with
  // the device default unconditionally, so a restored setting would have
  // lasted only until Connect was pressed. It matters just as much
  // within a session: disconnect and reconnect the same radio and you
  // come back where you were rather than at its default.
  //
  // Both wanted values are read BEFORE the bounds are touched: setting
  // MinValue/MaxValue on a TFloatSpinEdit clamps its Value as a side
  // effect, so reading afterwards can hand back a bound rather than what
  // the user had.
  WantLOMHz := FreqEdit.Value;
  WantListenMHz := ListenFreqEdit.Value;

  LoMHz := Caps.MinFreqHz / 1e6;
  HiMHz := Caps.MaxFreqHz / 1e6;

  FreqEdit.MinValue := LoMHz;
  FreqEdit.MaxValue := HiMHz;
  if (WantLOMHz >= LoMHz) and (WantLOMHz <= HiMHz) then
    FreqEdit.Value := WantLOMHz
  else
    FreqEdit.Value := Caps.DefaultFreqHz / 1e6;

  // ListenFreqEdit isn't bounded any tighter than the device's own
  // hardware range here - it should really also stay within whatever's
  // currently captured (CenterFreqHz +- SampleRateHz/2), but that range
  // moves with every retune/rate change, so enforcing it precisely is
  // left as a soft user responsibility for this first cut (see this
  // unit's own header comment on ListenFreqEdit).
  ListenFreqEdit.MinValue := LoMHz;
  ListenFreqEdit.MaxValue := HiMHz;
  if (WantListenMHz >= LoMHz) and (WantListenMHz <= HiMHz) then
    ListenFreqEdit.Value := WantListenMHz
  else
    ListenFreqEdit.Value := Caps.DefaultFreqHz / 1e6;

  // The receivers hold their own tuned frequency rather than reading the
  // control, so whichever of the two branches above ran, they need
  // telling - the same three lines ListenFreqEditEditingDone does, minus
  // the analyser cursor, which ConnectButtonClick sets once
  // UpdateFrequencyAxis has made the axis range real.
  FReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;
  FAMReceiver.TunedFrequencyHz := ListenFreqEdit.Value * 1e6;

  // AND THE DEVICE HAS TO BE TOLD TOO, which is easy to miss because
  // nothing before this point does it. A freshly opened device sits on
  // whatever its own constructor defaulted to (100 MHz for all three
  // backends) until something tunes it, and the local oscillator is
  // only otherwise pushed at StartStreaming. It is the DEVICE's centre
  // frequency, not this edit, that UpdateFrequencyAxis builds the
  // spectrum's X axis from - so leaving the two disagreeing produces an
  // axis describing a span the radio is not tuned to.
  //
  // That was harmless while this method overwrote FreqEdit with the
  // device default unconditionally: edit and device then agreed by
  // construction. It stopped being harmless the moment the edit could
  // carry a remembered frequency into a connect. With a restored 95 MHz
  // against a device still on 100, the axis came out 99-101, the cursor
  // assignment in ConnectButtonClick clamped to 99, and the clamp fired
  // OnCursorChange - which overwrote the restored listen frequency with
  // the clamped value and, seeing the cursor sitting on XAxisMin,
  // started edge panning. The visible result was both halves of one
  // bug: frequencies not restored, and the cursor walking left with the
  // local oscillator falling behind it, indefinitely.
  FRFSource.SetFrequencyHz(Round(FreqEdit.Value * 1e6));

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

  // A remembered sample rate replaces that default, matched against the
  // capability values rather than against the combo's own text - the
  // items are FormatFloat'd, so their text carries the locale's decimal
  // separator and is the wrong thing to compare. Exact equality is
  // right here: both sides are the same Double out of the same
  // capability table, only one of them via a round-trip through the
  // settings file as whole hertz.
  if PrefsMatch and (FPrefRateHz > 0) then
    for i := 0 to High(Caps.SampleRates) do
      if Round(Caps.SampleRates[i]) = FPrefRateHz then begin
        RateCombo.ItemIndex := i;
        Break;
      end;

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

  // REMEMBERED GAINS AND SWITCHES, last of all - every control above has
  // by now been given this device's own range, so a saved value can be
  // checked against something real before being applied.
  //
  // Only when the file came from THIS radio. The slots are positional:
  // GainStage0 is "whatever the first numeric stage happens to be",
  // which is IF gain reduction (20-59 dB, where higher means LESS gain)
  // on an SDRplay and RF/LNA gain on a HackRF. A saved 30 is a
  // legitimate position in both and means close to opposite things, so a
  // bare range check would not catch the mistake - the device name has
  // to. Frequencies are exempt from this, deliberately: those are
  // absolute, and 95.3 MHz means 95.3 MHz whatever is receiving it.
  //
  // Assigning Position/Checked fires each control's own OnChange, which
  // is what pushes the value at the hardware - so this restores the
  // radio's state, not merely the look of the panel.
  if not PrefsMatch then Exit;

  if GainStage0TrackBar.Visible and (FPrefGain0 <> PrefAbsent)
     and (FPrefGain0 >= GainStage0TrackBar.Min) and (FPrefGain0 <= GainStage0TrackBar.Max) then
    GainStage0TrackBar.Position := FPrefGain0;

  if GainStage1TrackBar.Visible and (FPrefGain1 <> PrefAbsent)
     and (FPrefGain1 >= GainStage1TrackBar.Min) and (FPrefGain1 <= GainStage1TrackBar.Max) then
    GainStage1TrackBar.Position := FPrefGain1;

  if GainStage2CheckBox.Visible and (FPrefGain2 <> PrefAbsent) then
    GainStage2CheckBox.Checked := FPrefGain2 <> 0;

  if BiasTCheckBox.Visible and (FPrefBiasT <> PrefAbsent) then
    BiasTCheckBox.Checked := FPrefBiasT <> 0;
end;

procedure TForm1.ConnectButtonClick(Sender: TObject);
var
  ErrMsg: string;
begin
  if FRFSource.IsOpen then begin
    if FRFSource.IsStreaming then StartStopButtonClick(Sender);   // stop first
    // While the controls still describe a live device - a reconnect in
    // the same session should come back to where the user actually was,
    // not to whatever the settings file said at launch.
    CaptureFrontEnd;
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
  SnapListenIntoSpan;
  // Must come after UpdateFrequencyAxis - SpectrumCursorValue clamps
  // against the spectrum's current X-axis range, which UseFrequencyAxis/
  // XAxisMin/XAxisMax (set by UpdateFrequencyAxis) only just became valid
  // MHz bounds; set any earlier and this would clamp against the
  // constructor's own placeholder [0,1] domain instead.
  FAnalyser.SpectrumCursorValue := ListenFreqEdit.Value;

  // Setting the cursor fires OnCursorChange exactly as a drag does, and
  // if the value asked for lay outside the axis it arrives there
  // clamped, sitting precisely on XAxisMin or XAxisMax - which is what
  // AnalyserCursorChanged reads as "the user has dragged to the edge,
  // start panning". A remembered listen frequency outside the span the
  // radio currently captures is an ordinary thing to have saved, so
  // this cancels any pan the assignment above provoked. Edge panning is
  // for a cursor the USER pushed against the edge; it should never be
  // started by this form setting the cursor itself.
  FEdgePanDirection := 0;
  FEdgePanTimer.Enabled := False;

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
  // The span just changed - the sample rate chosen for this run may be
  // narrower than the one the device was sitting on when Connect built
  // the axis, so a demodulator frequency that was inside it then can be
  // outside it now.
  SnapListenIntoSpan;
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
