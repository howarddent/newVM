unit uFMReceiver;

{*******************************************************************************

     TFMBroadcastReceiver - onward CPU-side signal processing of a
     TSDRRFSource's IQ stream (see uSDRRFSource.pas): a complete
     broadcast-FM receive chain built entirely from uDSPBlocks.pas's
     modular pieces, producing audible 48kHz stereo audio via
     uWaveOutPlayer.pas. A non-visual, installable Lazarus component
     (TComponent, same shape as TSDRRFSource itself) with a Source
     property pointing at a sibling TSDRRFSource - the standard
     "consumer points at a sibling component" link this project already
     uses for TSDRSpectrumAnalyser.Source (uVMPlotSDRSpectrum.pas).

     THE CHAIN (per epoch, EpochDurationMs worth of IQ at a time):
       1. Source.TryReadEpoch -> wideband IQ, at the RF source's own
          SampleRateHz (Fs_in - e.g. 2Msps on an SDRplay RSP1A).
       2. TComplexMixer, tuned to -(TunedFrequencyHz - Source.
          CenterFreqHz): shifts the selected station from wherever it
          sits within the wideband capture down to baseband (0Hz) - this
          is the "local quadrature oscillator + mixer" pair the design
          asked for, and is what lets TunedFrequencyHz move freely across
          the whole captured bandwidth without ever retuning the RF
          front end itself.
       3. TRationalResamplerC, Fs_in -> BasebandRateHz (200,000 - see
          below): a "rational re-sampler" cuts the wideband capture rate
          down to exactly the broadcast-FM channel rate, its own
          anti-alias filter (cutoff BasebandRateHz/2 = 100kHz) doubling
          as the channel-selectivity filter. BasebandRateHz = 200,000 is
          not arbitrary: a complex baseband signal's occupied bandwidth
          equals its sample rate (Nyquist on both sides), so sampling the
          selected channel at exactly 200kHz IS what gives it exactly the
          200kHz bandwidth broadcast FM standards call for - the sample
          rate and the bandwidth spec are the same number by
          construction, not two separate things kept in sync by hand.
       4. TFMDemodulator, at BasebandRateHz, PeakDeviationHz=75000 (the
          broadcast-FM standard's own peak deviation almost everywhere
          this hardware is likely used) -> the real FM multiplex signal
          (mono L+R, 19kHz pilot, 23-53kHz L-R subcarrier).
       5. TFMStereoDecoder, at BasebandRateHz, 75us de-emphasis (US
          broadcast-FM standard; most of the rest of the world uses 50us
          - see that class's own constructor comment) -> independent L/R
          audio, still at BasebandRateHz.
       6. Two TRationalResamplerS instances (BasebandRateHz -> 48,000),
          one per channel - the SAME reusable resampler class stage 3
          used, just real instead of complex, reused rather than a
          separate "final resample" concept: a rational resampler is a
          rational resampler regardless of where in the chain it sits.
       7. Volume-scaled, soft-limited, and queued to a TWaveOutPlayer for
          audible, real-time playback.

     Deliberately NOT reconfigured on every TunedFrequencyHz change: only
     the mixer's own oscillator frequency updates live (SetTunedFrequencyHz
     just touches FMixer.FrequencyHz, when the chain already exists) -
     rebuilding the resamplers/demodulator/stereo decoder on every retune
     would reset their internal filter delay lines and produce an audible
     glitch, and none of their own configuration (which only depends on
     Source.SampleRateHz/BasebandRateHz/AudioRateHz, none of which change
     when simply retuning within the same capture) actually needs to
     change for a retune anyway.

     WHY THIS RUNS ON ITS OWN THREAD, NOT A TTIMER: the first working
     version ran the whole chain (TryReadEpoch through QueueStereo) from
     an ordinary TTimer tick, on the GUI thread - same thread
     TSDRSpectrumAnalyser's own GPU/OpenCL processing runs on. Moving IQ
     ACQUISITION to a background thread (see uSDRRFSource.pas's own
     FPollThread) fixed data loss, but real-hardware testing still showed
     audible clicks/pops in the live app even though a WAV file generated
     by a single-threaded standalone harness (no spectrum analyser, no
     GUI contention) sounded clean end to end with the exact same chain
     and Source. The difference was exactly the GUI-thread contention
     itself: even with correct, lossless IQ data always available,
     running the DEMOD CHAIN and QueueStereo from a GUI timer still meant
     a slow spectrum tick could delay this component's own tick long
     enough to underrun TWaveOutPlayer's buffer - acquisition being
     lossless doesn't help if the audio never gets PRODUCED and QUEUED in
     time. Running the whole chain on a dedicated thread, independent of
     GUI-thread scheduling (the same rationale as uSDRRFSource.pas's own
     FPollThread), fixed that. FSource.TryReadEpoch is already
     thread-safe for this (see that unit's own FStreamLock);
     TWaveOutPlayer's Win32 waveOut calls are safe to make from any
     single thread as long as nothing else calls into the same
     TWaveOutPlayer instance concurrently, which nothing else here does.

     WHY TWO THREADS (FAcquireThread/FDemodThread), NOT ONE: live
     instrumented timing on real Raspberry Pi 5 + HackRF hardware showed
     the single combined thread averaging a few percent over its
     per-epoch real-time budget even after both DefaultEpochDurationMs's
     amortisation widening and the wideband resampler's TransitionBW
     widening (see their own comments) - a residual deficit small enough
     that neither lever closed it further without diminishing returns,
     but large enough that TWaveOutPlayer's drift compensation still
     fired on very nearly every epoch instead of occasionally, audible as
     a persistent low-level "motorboat" buzz plus occasional real
     underrun clicks. The chain was already naturally two halves of
     roughly comparable cost - FMixer+FResamplerToBaseband (running at
     the wideband Fs_in) versus FDemod+FStereoDecoder+FResamplerL/R
     (running at BasebandRateHz, but through five FIR filters/two
     resamplers) - so splitting it at exactly that seam, one thread per
     half, lets both run truly concurrently on this hardware's separate
     CPU cores instead of time-sharing one: FAcquireThread pushes each
     epoch's Baseband (TVMobjC, after the mixer+wideband-resample) onto
     FQueue; FDemodThread pops from FQueue and runs everything from
     FDemod onward through QueueStereo. This is the same "move the
     bottleneck off the contended thread" idea that originally justified
     moving IQ acquisition and then the whole chain off the GUI thread
     above - just applied one level deeper, now that the whole chain
     itself is the thing that needs a second core.

     FQueue (TBasebandQueue) is a small, bounded, thread-safe FIFO of
     Baseband epochs (capacity BasebandQueueCapacity below) - the handoff
     point between the two threads. Guarded by its own TCriticalSection,
     not FSource's FStreamLock (a different, unrelated resource). Full
     queue drops the OLDEST entry rather than blocking FAcquireThread -
     the same "don't fall behind, skip forward instead" philosophy
     uSDRRFSource.pas's own stream ring already uses - so a transient stall
     in FDemodThread degrades to a skipped baseband epoch (one bad epoch
     dropped, decoder state otherwise undisturbed - already how
     uSDRRFSource.pas's own TryReadEpoch and, before this change,
     TWaveOutPlayer's QueueStereo both treat "can't keep up" moments)
     rather than ever blocking acquisition and risking data loss further
     upstream. TVMobjC is a plain newVM-style record (value semantics via
     a reference-counted dynamic array, not a managed/refcounted object
     like newVMCL.pas's TVMobjCL) - handing one off by simple assignment
     (Push's Item parameter, Pop's out parameter) is safe here because
     each Baseband instance is produced fresh, once, by
     FResamplerToBaseband.Process's own TVMobjC.Create and never touched
     again by FAcquireThread after being pushed.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs,
  newVM, newVMSingle, newVMComplexSingle,
  uSDRRFSource, uDSPBlocks, uWaveOutPlayer;

const
  DefaultBasebandRateHz = 200000;    // = broadcast FM's own 200kHz channel bandwidth - see this unit's header comment
  DefaultAudioRateHz = 48000;
  DefaultPeakDeviationHz = 75000;
  DefaultDeEmphasisTauSeconds = 75e-6;   // US broadcast-FM standard; most of the rest of the world uses 50e-6

  {$IFDEF CPUAARCH64}
  // Widened from 20 to 32ms (ARM64/aarch64 builds only - see the
  // {$ELSE} branch below for why this doesn't apply elsewhere) after
  // live instrumented timing on real Raspberry Pi 5 + HackRF hardware
  // (at 2Msps, this unit's originally-tuned rate) showed
  // ProcessAcquireOnce/ProcessDemodOnce's fixed per-call overhead - a
  // fresh TVMobjC/TVMobjS.Create (and its underlying dynamic-array
  // allocation) for every one of the chain's intermediate stages, once
  // per epoch - was a real, measurable cost that a wider epoch amortises
  // over more samples without touching any filter's selectivity (unlike
  // loosening a TransitionBW, this trades only a little more end-to-end
  // audio latency, not signal quality). Reported audible symptom this
  // addressed: a periodic "motorboat" buzz at roughly the epoch rate -
  // TWaveOutPlayer's drift-compensation (uWaveOutPlayer.pas's
  // QueueStereo) firing on very nearly every epoch, not the occasional
  // few-percent nudge it's designed for, because the combined chain
  // (this was single-threaded at the time of this specific measurement)
  // was still averaging a hair over the 20ms/epoch real-time budget even
  // after uFMReceiver.pas's own wideband-resampler TransitionBW widening
  // (2.5%->10%) closed most, but not all, of the deficit on its own. 32,
  // not higher: chosen to land EXACTLY on MaxEpochSamples below at this
  // unit's originally-tuned 2Msps (32ms * 2,000,000 = 64,000) - pushed
  // right up against MaxEpochSamples's own raised ceiling (see that
  // constant's own comment) for the full amortisation benefit available
  // under TVMobjC/TVMobjS's hard 65535-per-dimension cap, without this
  // getting silently clamped back down before it's realised. Left in
  // place even after the two-thread split (FAcquireThread/FDemodThread -
  // see this unit's own header comment, "WHY TWO THREADS") fully closed
  // the real-time deficit on its own, for a little extra margin.
  DefaultEpochDurationMs = 32;
  // Raised from 60000 to 64000 (ARM64 only) alongside
  // DefaultEpochDurationMs's own 20->32ms widening above - still
  // comfortably under TVMobjC/TVMobjS's hard 65535-per-dimension cap
  // (see ProcessAcquireOnce's own comment for why that cap exists at
  // all), just closer to it for a little more of the same
  // fixed-per-call-overhead amortisation benefit.
  MaxEpochSamples = 64000;
  {$ELSE}
  // Original values, unchanged, for every non-ARM64 build (x86_64 Intel/
  // AMD - Linux or Windows - and any other architecture) - the widened
  // ARM64 values above trade a little audio latency for real-time
  // headroom this project's own Raspberry Pi 5 test hardware measurably
  // needed; a faster CPU doesn't need that trade, so this branch keeps
  // the tighter, lower-latency defaults that were already working on
  // those platforms rather than applying an ARM-specific compromise
  // everywhere.
  DefaultEpochDurationMs = 20;
  MaxEpochSamples = 60000;
  {$ENDIF}
  // The wideband resampler's TransitionBW, as a fraction of FsIn - see
  // BuildChain's own comment for the full rationale (why it scales with
  // FsIn at all, and why ARM64 widens it). Same ARM64-only trade as
  // DefaultEpochDurationMs/MaxEpochSamples above: real-time headroom this
  // project's Raspberry Pi 5 test hardware measurably needed, at the cost
  // of a little out-of-channel filter selectivity a faster CPU doesn't
  // need to trade away.
  {$IFDEF CPUAARCH64}
  WidebandTransitionBWFraction = 0.15;
  {$ELSE}
  WidebandTransitionBWFraction = 0.025;
  {$ENDIF}
  // FQueue's capacity - see this unit's own header comment ("WHY TWO
  // THREADS") for what this queue hands off. A few epochs' worth of
  // slack (at 32ms/epoch, 6 slots is ~190ms) absorbs ordinary short-term
  // scheduling jitter between the two threads without letting a
  // persistent stall balloon into unbounded latency - Push drops the
  // oldest entry once full rather than growing further.
  BasebandQueueCapacity = 6;

type
  TFMBroadcastReceiver = class;

  // The handoff point between FAcquireThread and FDemodThread - see this
  // unit's own header comment ("WHY TWO THREADS") for the full rationale.
  { TBasebandQueue }
  TBasebandQueue = class
  private
    FItems: array of TVMobjC;
    FHead, FCount: Integer;
    FLock: TCriticalSection;
  public
    constructor Create(Capacity: Integer);
    destructor Destroy; override;
    // Called only from FAcquireThread. Never blocks - drops the oldest
    // queued epoch if already at capacity (see BasebandQueueCapacity's
    // own comment).
    procedure Push(const Item: TVMobjC);
    // Called only from FDemodThread. Returns False (Item left
    // unassigned) if the queue is currently empty, same "nothing ready
    // yet, don't block" contract as TSDRRFSource.TryReadEpoch.
    function TryPop(out Item: TVMobjC): Boolean;
  end;

  // Stage A: TryReadEpoch through the wideband resample, pushing each
  // result onto FOwner.FQueue - see this unit's own header comment ("WHY
  // TWO THREADS") for the split's rationale. Plain tight loop, mirroring
  // uSDRRFSource.pas's own FPollThread.
  { TFMAcquireThread }
  TFMAcquireThread = class(TThread)
  private
    FOwner: TFMBroadcastReceiver;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TFMBroadcastReceiver);
  end;

  // Stage B: pops one Baseband epoch from FOwner.FQueue and runs
  // everything from FDemod through QueueStereo - see this unit's own
  // header comment ("WHY TWO THREADS") for the split's rationale.
  { TFMDemodThread }
  TFMDemodThread = class(TThread)
  private
    FOwner: TFMBroadcastReceiver;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TFMBroadcastReceiver);
  end;

  { TFMBroadcastReceiver }
  TFMBroadcastReceiver = class(TComponent)
  private
    FSource: TSDRRFSource;
    FSourceCursor: TSDRStreamCursor;
    FTunedFrequencyHz: Double;
    FVolume: Single;
    FEpochDurationMs: Integer;

    FMixer: TComplexMixer;
    FResamplerToBaseband: TRationalResamplerC;
    FDemod: TFMDemodulator;
    FStereoDecoder: TFMStereoDecoder;
    FResamplerL, FResamplerR: TRationalResamplerS;
    FPlayer: TWaveOutPlayer;
    FQueue: TBasebandQueue;
    FAcquireThread: TFMAcquireThread;
    FDemodThread: TFMDemodThread;
    FChainBuilt: Boolean;
    FLastError: string;

    procedure SetSource(AValue: TSDRRFSource);
    procedure SetTunedFrequencyHz(AValue: Double);
    function GetActive: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure BuildChain;
    procedure TeardownChain;
    // Called only from FAcquireThread (Stage A - see this unit's own
    // header comment, "WHY TWO THREADS"). Returns True iff an epoch was
    // actually read and pushed (so the thread's own loop knows whether
    // to yield briefly or keep going).
    function ProcessAcquireOnce: Boolean;
    // Called only from FDemodThread (Stage B). Returns True iff a queued
    // epoch was actually popped and processed through to QueueStereo.
    function ProcessDemodOnce: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Set if either thread's per-epoch processing raised an exception -
    // see their own Execute methods for why this is caught rather than
    // left to kill the thread. Empty string means no error has occurred.
    property LastError: string read FLastError;
    // Forwards TWaveOutPlayer.UnderrunCount - see that property's own
    // comment. 0 before Active is ever set True (FPlayer isn't open yet).
    function AudioUnderrunCount: Integer;
  published
    property Source: TSDRRFSource read FSource write SetSource;
    // Absolute RF frequency to listen to, in Hz - independent of
    // Source's own CenterFreqHz, as long as it falls within the
    // currently-captured bandwidth (CenterFreqHz +- SampleRateHz/2) -
    // see this unit's own header comment for how the mixer makes that
    // work. May be changed live while Active.
    property TunedFrequencyHz: Double read FTunedFrequencyHz write SetTunedFrequencyHz;
    property Volume: Single read FVolume write FVolume;
    property EpochDurationMs: Integer read FEpochDurationMs write FEpochDurationMs
      default DefaultEpochDurationMs;
    property Active: Boolean read GetActive write SetActive default False;
  end;

procedure Register;

implementation

constructor TFMBroadcastReceiver.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVolume := 1.0;
  FEpochDurationMs := DefaultEpochDurationMs;
  FPlayer := TWaveOutPlayer.Create;
end;

destructor TFMBroadcastReceiver.Destroy;
begin
  SetActive(False);   // stops and waits for both threads before tearing anything down
  FPlayer.Free;
  inherited Destroy;
end;

{ TBasebandQueue }

constructor TBasebandQueue.Create(Capacity: Integer);
begin
  inherited Create;
  SetLength(FItems, Capacity);
  FHead := 0;
  FCount := 0;
  FLock := TCriticalSection.Create;
end;

destructor TBasebandQueue.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TBasebandQueue.Push(const Item: TVMobjC);
var
  Cap, TailIdx: Integer;
begin
  FLock.Enter;
  try
    Cap := Length(FItems);
    if FCount = Cap then begin
      FHead := (FHead + 1) mod Cap;
      Dec(FCount);
    end;
    TailIdx := (FHead + FCount) mod Cap;
    FItems[TailIdx] := Item;
    Inc(FCount);
  finally
    FLock.Leave;
  end;
end;

function TBasebandQueue.TryPop(out Item: TVMobjC): Boolean;
begin
  FLock.Enter;
  try
    Result := FCount > 0;
    if Result then begin
      Item := FItems[FHead];
      FHead := (FHead + 1) mod Length(FItems);
      Dec(FCount);
    end;
  finally
    FLock.Leave;
  end;
end;

{ TFMAcquireThread }

constructor TFMAcquireThread.Create(AOwner: TFMBroadcastReceiver);
begin
  inherited Create(False);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TFMAcquireThread.Execute;
begin
  while not Terminated do
    // An unhandled exception here would otherwise silently and
    // PERMANENTLY kill this thread for the rest of the session (the
    // same class of failure ProcessAcquireOnce's own MaxEpochSamples
    // comment documents for one specific cause of it) - caught here so a
    // single bad epoch degrades to "one dropped epoch" (FOwner.LastError
    // set, logged for diagnosis) rather than silencing audio for good.
    try
      if not FOwner.ProcessAcquireOnce then Sleep(1);
    except
      on E: Exception do begin
        FOwner.FLastError := E.ClassName + ': ' + E.Message;
        Sleep(1);
      end;
    end;
end;

{ TFMDemodThread }

constructor TFMDemodThread.Create(AOwner: TFMBroadcastReceiver);
begin
  inherited Create(False);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TFMDemodThread.Execute;
begin
  while not Terminated do
    // Same exception-tolerance rationale as TFMAcquireThread.Execute above.
    try
      if not FOwner.ProcessDemodOnce then Sleep(1);
    except
      on E: Exception do begin
        FOwner.FLastError := E.ClassName + ': ' + E.Message;
        Sleep(1);
      end;
    end;
end;

procedure TFMBroadcastReceiver.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then FSource := nil;
end;

procedure TFMBroadcastReceiver.SetSource(AValue: TSDRRFSource);
begin
  if FSource = AValue then Exit;
  if Assigned(FSource) then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if Assigned(FSource) then begin
    FSource.FreeNotification(Self);
    // See uSDRRFSource.pas's own header comment: every independent
    // consumer of the shared stream needs its own cursor - this used to
    // be a single-consumer destructive read, which silently corrupted
    // both this component's own stream and TSDRSpectrumAnalyser's the
    // moment both were active on the same Source at once.
    FSourceCursor := FSource.NewStreamCursor;
  end;
end;

procedure TFMBroadcastReceiver.SetTunedFrequencyHz(AValue: Double);
begin
  FTunedFrequencyHz := AValue;
  // See this unit's own header comment for the sign: the mixer must
  // shift the station DOWN to baseband, i.e. by minus its offset from
  // the RF source's own centre frequency. FMixer.FrequencyHz is a plain
  // Double field read every FAcquireThread iteration - deliberately not
  // synchronised with this (GUI-thread) setter: a torn/stale read here
  // has no worse an effect than a one-epoch-late retune, and this
  // property is written far more often (a user dragging a frequency
  // control) than the cost of adding real synchronisation would justify.
  if FChainBuilt and Assigned(FSource) then
    FMixer.FrequencyHz := -(FTunedFrequencyHz - FSource.CenterFreqHz);
end;

function TFMBroadcastReceiver.GetActive: Boolean;
begin
  Result := Assigned(FAcquireThread);
end;

function TFMBroadcastReceiver.AudioUnderrunCount: Integer;
begin
  Result := FPlayer.UnderrunCount;
end;

procedure TFMBroadcastReceiver.SetActive(AValue: Boolean);
begin
  if AValue = Assigned(FAcquireThread) then Exit;
  if AValue then begin
    if not (Assigned(FSource) and FSource.IsOpen) then Exit;   // nothing to receive from yet
    BuildChain;
    // Start the consumer (Stage B) before the producer (Stage A) - purely
    // so FQueue never has a moment where FDemodThread doesn't exist yet
    // to drain it; harmless either way since Push never blocks, but this
    // ordering needs no justification for why it's safe to reverse.
    FDemodThread := TFMDemodThread.Create(Self);
    FAcquireThread := TFMAcquireThread.Create(Self);
  end else begin
    // Terminate/wait Stage A (the producer) first, then Stage B - so
    // FDemodThread has already stopped being fed before it's told to
    // stop, rather than the other way round (which would just mean it
    // exits after draining whatever's left in FQueue - not wrong either,
    // but this order is the more obviously-correct shutdown sequence).
    FAcquireThread.Terminate;
    FAcquireThread.WaitFor;
    FreeAndNil(FAcquireThread);
    FDemodThread.Terminate;
    FDemodThread.WaitFor;
    FreeAndNil(FDemodThread);
    TeardownChain;
  end;
end;

procedure TFMBroadcastReceiver.BuildChain;
const
  s = 'TFMBroadcastReceiver.BuildChain : ';
var
  FsIn: Double;
  MaxAudioSamples: Integer;
begin
  TeardownChain;
  assert(Assigned(FSource) and FSource.IsOpen, s + 'Source must be connected');
  FsIn := FSource.SampleRateHz;

  // TransitionBW arguments were loosened twice now after real-time
  // testing against actual hardware showed the tighter, longer filters
  // couldn't keep up with the wideband capture rate - TFIRFilterS/
  // TRationalResamplerC/S are all direct-form (O(N*NumTaps)), and
  // NumTaps roughly halves for each doubling of TransitionBW (see
  // ChooseNumTaps's own comment). This does NOT touch BasebandRateHz
  // itself (still exactly 200,000 - the actual 200kHz channel-bandwidth
  // spec, unchanged); it only loosens how sharply the antialiasing
  // filter rolls off at that boundary, trading a little out-of-channel
  // rejection for real-time headroom.
  //
  // The wideband resampler's TransitionBW is scaled PROPORTIONALLY to
  // FsIn (5%, i.e. 100kHz at the 2Msps this ratio is tuned and verified
  // against) rather than left as a fixed Hz value - this filter runs at
  // FsIn itself (an order of magnitude higher than every other filter in
  // the chain, which run at BasebandRateHz), so its absolute compute cost
  // per second of audio scales directly with FsIn for ANY fixed
  // TransitionBW-in-Hz. A fixed Hz value, validated only at one sample
  // rate, meant this stage silently got proportionally more expensive at
  // every higher sample rate a device offers (e.g. an SDRplay's 8-10Msps
  // modes) - confirmed as a real bug: audio worked at 2-3Msps and fell to
  // silence at higher rates once the DSP thread could no longer keep up
  // with real time and TWaveOutPlayer's buffer ran dry. Scaling
  // TransitionBW with FsIn keeps NumTaps - and so this stage's absolute
  // cost - roughly CONSTANT across every sample rate a device supports,
  // rather than tuned for one and silently breaking at others.
  //
  // Widened from 2.5% to 15% on ARM64 (WidebandTransitionBWFraction's own
  // comment) in stages (each widening roughly cuts this stage's NumTaps,
  // per ChooseNumTaps's own comment) after live instrumented timing on
  // real Raspberry Pi 5 + HackRF hardware showed the combined chain (this
  // was single-threaded at the time of this specific measurement)
  // averaging ~24ms against the original 20ms/epoch real-time budget - a
  // ~15-20% deficit, confirmed via a dedicated CPU core already fully
  // pegged (not GUI-thread contention), that made TWaveOutPlayer's drift
  // compensation (uWaveOutPlayer.pas's QueueStereo) fire on very nearly
  // every epoch instead of the occasional few-percent nudge it's designed
  // for - audible as a periodic "motorboat" buzz at roughly the epoch
  // rate, not the random click an occasional real underrun would
  // produce. This stage runs at FsIn itself, an order of magnitude above
  // every other filter in the chain, so it was the first, cheapest lever
  // to widen - but measurement after the first widening (2.5%->5%,
  // ~24ms->~22ms) showed it was only a modest contributor (~18% of
  // total), not the dominant one its FsIn-scaling alone would suggest, so
  // DefaultEpochDurationMs/MaxEpochSamples (fixed per-call overhead
  // amortisation - a "free" lever with no selectivity cost, unlike this
  // one) and, ultimately, the FAcquireThread/FDemodThread split (this
  // unit's own header comment, "WHY TWO THREADS") did the rest of the
  // real work of closing the deficit. Left at 15% on ARM64, not tightened
  // back down, purely for a little extra margin alongside those other
  // fixes.
  FMixer := TComplexMixer.Create(FsIn, -(FTunedFrequencyHz - FSource.CenterFreqHz));
  FResamplerToBaseband := TRationalResamplerC.Create(FsIn, DefaultBasebandRateHz,
    FsIn * WidebandTransitionBWFraction);
  FDemod := TFMDemodulator.Create(DefaultBasebandRateHz, DefaultPeakDeviationHz);
  FStereoDecoder := TFMStereoDecoder.Create(DefaultBasebandRateHz, DefaultDeEmphasisTauSeconds);
  FResamplerL := TRationalResamplerS.Create(DefaultBasebandRateHz, DefaultAudioRateHz, 8000);
  FResamplerR := TRationalResamplerS.Create(DefaultBasebandRateHz, DefaultAudioRateHz, 8000);
  FQueue := TBasebandQueue.Create(BasebandQueueCapacity);

  // Generous headroom over the nominal per-epoch audio sample count,
  // since TRationalResamplerS's output length can vary by a sample or
  // two either way depending on exact phase alignment.
  MaxAudioSamples := Round(DefaultAudioRateHz * FEpochDurationMs / 1000 * 2) + 64;
  FPlayer.Open(DefaultAudioRateHz, MaxAudioSamples);

  // A fresh cursor for this streaming session - StartStreaming resets
  // the source's own stream position, so a cursor left over from a
  // previous session (or from before Source was ever streaming) would
  // otherwise read as "hopelessly behind" and just skip-forward once,
  // rather than starting caught up cleanly.
  FSourceCursor := FSource.NewStreamCursor;

  FChainBuilt := True;
end;

procedure TFMBroadcastReceiver.TeardownChain;
begin
  if not FChainBuilt then Exit;
  FPlayer.Close;
  FreeAndNil(FMixer);
  FreeAndNil(FResamplerToBaseband);
  FreeAndNil(FDemod);
  FreeAndNil(FStereoDecoder);
  FreeAndNil(FResamplerL);
  FreeAndNil(FResamplerR);
  FreeAndNil(FQueue);
  FChainBuilt := False;
end;

function TFMBroadcastReceiver.ProcessAcquireOnce: Boolean;
var
  N: Integer;
  IQ, Baseband: TVMobjC;
begin
  Result := False;
  if not (FChainBuilt and Assigned(FSource)) then Exit;

  // TVMobjC/TVMobjS both cap any single dimension at 65535 (TDimC/TDimS
  // = 0..MaxDimC-1/MaxDimS-1, MaxDimC/MaxDimS = 65536 - a bound from
  // this library's matrix-algebra heritage, never designed for
  // audio-scale per-epoch sample counts). At FEpochDurationMs=20 that's
  // only exceeded above 3.27Msps - confirmed as the actual cause of
  // "works at 2-3Msps, silence at higher rates": TVMobjC.Create raised
  // an assertion once N passed 65535, and since this runs on
  // FAcquireThread (see this unit's own header comment), the unhandled
  // exception silently killed the thread rather than crashing visibly or
  // logging anything - audio just stopped. Every stage AFTER this one
  // only ever decimates (baseband/audio rates are always <= FsIn), so
  // capping N here keeps every downstream TVMobjC/TVMobjS safely under
  // the limit too. A capped N just means shorter (but still fully
  // correct - every DSP block here is stateful/streaming across calls)
  // epochs at high sample rates, not a functional loss.
  N := Round(FSource.SampleRateHz * FEpochDurationMs / 1000);
  if N > MaxEpochSamples then N := MaxEpochSamples;
  if not FSource.TryReadEpoch(N, FSourceCursor, IQ) then Exit;

  Baseband := FResamplerToBaseband.Process(FMixer.Process(IQ));
  FQueue.Push(Baseband);
  Result := True;
end;

function TFMBroadcastReceiver.ProcessDemodOnce: Boolean;
var
  Baseband: TVMobjC;
  Multiplex: TVMobjS;
  StereoL, StereoR, AudioL, AudioR: TVMobjS;
begin
  Result := False;
  if not FChainBuilt then Exit;
  if not FQueue.TryPop(Baseband) then Exit;

  Multiplex := FDemod.Process(Baseband);
  FStereoDecoder.Process(Multiplex, StereoL, StereoR);
  AudioL := FResamplerL.Process(StereoL);
  AudioR := FResamplerR.Process(StereoR);

  if FVolume <> 1.0 then begin
    AudioL := AudioL * FVolume;
    AudioR := AudioR * FVolume;
  end;

  FPlayer.QueueStereo(AudioL, AudioR);
  Result := True;
end;

procedure Register;
begin
  RegisterComponents('SDR', [TFMBroadcastReceiver]);
end;

end.
