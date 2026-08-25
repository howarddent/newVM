unit uAMReceiver;

{*******************************************************************************

     TAMBroadcastReceiver - onward CPU-side signal processing of a
     TSDRRFSource's IQ stream (see uSDRRFSource.pas): an AM receive
     chain built from uDSPBlocks.pas's modular pieces, producing audible
     48kHz mono audio (duplicated to both channels for TWaveOutPlayer -
     see uWaveOutPlayer.pas) via TAMDemodulator, with a caller-selectable
     channel bandwidth and envelope/synchronous demodulation mode. Same
     shape/conventions as uFMReceiver.pas's TFMBroadcastReceiver (a
     non-visual TComponent with a Source property pointing at a sibling
     TSDRRFSource) - see that unit's own header comment for the parts
     shared verbatim (why a background thread at all, the mixer/
     TunedFrequencyHz relationship, the 65535-per-dimension epoch cap,
     etc.) - not repeated here.

     THE CHAIN differs from FM's only in the middle two stages:
       1-2. Source.TryReadEpoch, TComplexMixer - identical to FM's own.
       3. TRationalResamplerC, Fs_in -> BasebandRateHz = BandwidthHz*2 -
          the same "sample rate IS the channel bandwidth" construction
          TFMBroadcastReceiver's own fixed 200kHz uses (see that unit's
          own BuildChain comment), just with a caller-chosen BandwidthHz
          instead of a fixed broadcast-FM spec - see BandwidthHz's own
          property comment for why *2.
       4. TAMDemodulator (envelope or synchronous - see uDSPBlocks.pas's
          own header comment on that class) -> real mono audio, still at
          BasebandRateHz. No stereo decode stage - AM broadcast carries
          no stereo subcarrier.
       5. ONE TRationalResamplerS, BasebandRateHz -> 48,000.
       6. Volume-scaled, queued to TWaveOutPlayer as identical L/R
          (mono) - QueueStereo itself already soft-limits (see that
          unit's own header comment).

     SINGLE-THREADED, UNLIKE TFMBroadcastReceiver's TWO-THREAD SPLIT:
     FM's own two-thread acquire/demod split (see uFMReceiver.pas's own
     header comment, "WHY TWO THREADS") exists because FM's demod stage -
     TFMStereoDecoder alone runs FIVE FIR filters plus two further
     resamplers - measurably couldn't keep up on a single core on real
     ARM64 hardware. AM's own demod stage (TAMDemodulator) is a plain
     O(N) loop with no filtering at all, and there's only one output
     resampler instead of two - an order of magnitude less per-sample
     work - so nothing here has shown any need for the same split; a
     single background thread (mirroring FM's own original, pre-split
     version - see that unit's git history) is more than adequate.
     Revisit if real-hardware testing ever shows otherwise, the same way
     FM's own split was only added after live instrumented timing
     actually showed a deficit, not preemptively.

     BANDWIDTH IS LIVE-CHANGEABLE, BUT NOT GLITCH-FREE: unlike
     TunedFrequencyHz (just a mixer NCO frequency, safe to change every
     epoch with no rebuild), BandwidthHz determines BasebandRateHz, which
     every stage from FResamplerToBaseband onward is built around -
     changing it means SetBandwidthHz tears down and rebuilds the whole
     chain on the spot (stop FDSPThread, TeardownChain, BuildChain,
     restart FDSPThread), resetting every stage's internal filter/
     resampler state. That produces a short audible discontinuity - the
     same kind of "click" a real radio's own bandwidth-filter switch
     makes - but is otherwise safe to do synchronously on whichever
     thread calls it (ordinarily the GUI thread, via a bandwidth slider):
     unlike uSDRRFSource.pas's own async device retune (see that unit's
     own ASYNC RETUNE header comment), nothing here calls into a vendor
     driver/IPC layer that might block for an unpredictable time - this
     only stops and restarts a plain CPU compute thread, which notices
     Terminated and exits promptly every iteration.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math,
  newVM, newVMSingle, newVMComplexSingle,
  uSDRRFSource, uDSPBlocks, uWaveOutPlayer;

const
  DefaultAMBandwidthHz = 5000;    // typical broadcast-AM audio bandwidth
  MinAMBandwidthHz = 1000;
  MaxAMBandwidthHz = 10000;
  DefaultAudioRateHz = 48000;
  DefaultEpochDurationMs = 20;
  // Same rationale/derivation as uFMReceiver.pas's own MaxEpochSamples -
  // see that constant's own comment for the full TVMobjC/TVMobjS
  // 65535-per-dimension story; AM has no ARM64-specific widening of its
  // own yet since nothing has shown a need for it (see this unit's own
  // header comment, SINGLE-THREADED).
  MaxEpochSamples = 60000;

type
  TAMBroadcastReceiver = class;

  // Plain tight loop, mirroring uSDRRFSource.pas's own FPollThread and
  // uFMReceiver.pas's original (pre-split) single-thread shape - see
  // this unit's own header comment (SINGLE-THREADED) for why AM doesn't
  // need FM's own two-thread split.
  { TAMDSPThread }
  TAMDSPThread = class(TThread)
  private
    FOwner: TAMBroadcastReceiver;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TAMBroadcastReceiver);
  end;

  { TAMBroadcastReceiver }
  TAMBroadcastReceiver = class(TComponent)
  private
    FSource: TSDRRFSource;
    FSourceCursor: TSDRStreamCursor;
    FTunedFrequencyHz: Double;
    FVolume: Single;
    FEpochDurationMs: Integer;
    FBandwidthHz: Double;
    FSynchronous: Boolean;

    FMixer: TComplexMixer;
    FResamplerToBaseband: TRationalResamplerC;
    FDemod: TAMDemodulator;
    FResamplerAudio: TRationalResamplerS;
    FPlayer: TWaveOutPlayer;
    FDSPThread: TAMDSPThread;
    FChainBuilt: Boolean;
    FLastError: string;
    // Diagnostic only - see TFMBroadcastReceiver's identical FAcquireSkipCount
    // for the rationale (counts only this receiver's own FSourceCursor skips).
    FAcquireSkipCount: Integer;
    // Diagnostic only - see TFMBroadcastReceiver's identical FErrorCount
    // for the rationale (total exceptions caught in TAMDSPThread.Execute).
    FErrorCount: Integer;

    procedure SetSource(AValue: TSDRRFSource);
    procedure SetTunedFrequencyHz(AValue: Double);
    procedure SetBandwidthHz(AValue: Double);
    function GetActive: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure BuildChain;
    procedure TeardownChain;
    // Called only from FDSPThread. Returns True iff an epoch was
    // actually processed (so the thread's own loop knows whether to
    // yield briefly or keep going).
    function ProcessOnce: Boolean;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Set if the DSP thread's per-epoch processing raised an exception -
    // see TAMDSPThread.Execute for why this is caught rather than left
    // to kill the thread. Empty string means no error has occurred.
    property LastError: string read FLastError;
    // Forwards TWaveOutPlayer.UnderrunCount - see that property's own
    // comment. 0 before Active is ever set True (FPlayer isn't open yet).
    function AudioUnderrunCount: Integer;
    // Forwards FAcquireSkipCount - see that field's own comment.
    function AudioAcquireSkipCount: Integer;
    // Forwards FErrorCount - see that field's own comment.
    function AudioErrorCount: Integer;
  published
    property Source: TSDRRFSource read FSource write SetSource;
    // Absolute RF frequency to listen to, in Hz - see
    // TFMBroadcastReceiver.TunedFrequencyHz's own comment; identical
    // relationship to Source's own CenterFreqHz here. May be changed
    // live while Active.
    property TunedFrequencyHz: Double read FTunedFrequencyHz write SetTunedFrequencyHz;
    // Channel/audio bandwidth in Hz, clamped to [MinAMBandwidthHz,
    // MaxAMBandwidthHz] - safe to change live while Active, but expect a
    // short audio discontinuity when you do (see this unit's own header
    // comment, BANDWIDTH IS LIVE-CHANGEABLE, BUT NOT GLITCH-FREE).
    property BandwidthHz: Double read FBandwidthHz write SetBandwidthHz;
    // False (default) = envelope detection, True = synchronous
    // (coherent, PLL-tracked) detection - see uDSPBlocks.pas's own
    // TAMDemodulator header comment for the tradeoff. Safe to change
    // live: TAMDemodulator.Process takes this as a per-call argument, so
    // toggling it doesn't reset the demodulator's own PLL/DC-average
    // state or glitch the audio.
    property Synchronous: Boolean read FSynchronous write FSynchronous;
    property Volume: Single read FVolume write FVolume;
    property EpochDurationMs: Integer read FEpochDurationMs write FEpochDurationMs
      default DefaultEpochDurationMs;
    property Active: Boolean read GetActive write SetActive default False;
  end;

procedure Register;

implementation

constructor TAMBroadcastReceiver.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVolume := 1.0;
  FEpochDurationMs := DefaultEpochDurationMs;
  FBandwidthHz := DefaultAMBandwidthHz;
  FPlayer := TWaveOutPlayer.Create;
end;

destructor TAMBroadcastReceiver.Destroy;
begin
  SetActive(False);   // stops and waits for FDSPThread before tearing anything down
  FPlayer.Free;
  inherited Destroy;
end;

{ TAMDSPThread }

constructor TAMDSPThread.Create(AOwner: TAMBroadcastReceiver);
begin
  inherited Create(False);
  FOwner := AOwner;
  FreeOnTerminate := False;
end;

procedure TAMDSPThread.Execute;
begin
  while not Terminated do
    // Same exception-tolerance rationale as uFMReceiver.pas's own thread
    // Execute methods - a single bad epoch degrades to "one dropped
    // epoch" (FOwner.LastError set, logged for diagnosis) rather than
    // silently, permanently killing this thread for the rest of the
    // session.
    try
      if not FOwner.ProcessOnce then Sleep(1);
    except
      on E: Exception do begin
        FOwner.FLastError := E.ClassName + ': ' + E.Message;
        Inc(FOwner.FErrorCount);
        Sleep(1);
      end;
    end;
end;

procedure TAMBroadcastReceiver.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then FSource := nil;
end;

procedure TAMBroadcastReceiver.SetSource(AValue: TSDRRFSource);
begin
  if FSource = AValue then Exit;
  if Assigned(FSource) then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if Assigned(FSource) then begin
    FSource.FreeNotification(Self);
    // See uSDRRFSource.pas's own header comment: every independent
    // consumer of the shared stream needs its own cursor.
    FSourceCursor := FSource.NewStreamCursor;
  end;
end;

procedure TAMBroadcastReceiver.SetTunedFrequencyHz(AValue: Double);
begin
  FTunedFrequencyHz := AValue;
  // See uFMReceiver.pas's own SetTunedFrequencyHz comment for the sign
  // and the "deliberately not synchronised" rationale - identical here.
  if FChainBuilt and Assigned(FSource) then
    FMixer.FrequencyHz := -(FTunedFrequencyHz - FSource.CenterFreqHz);
end;

procedure TAMBroadcastReceiver.SetBandwidthHz(AValue: Double);
var
  WasActive: Boolean;
begin
  AValue := EnsureRange(AValue, MinAMBandwidthHz, MaxAMBandwidthHz);
  if AValue = FBandwidthHz then Exit;
  FBandwidthHz := AValue;
  // Unlike TunedFrequencyHz (just an NCO frequency, updated live with no
  // rebuild), BandwidthHz changes BasebandRateHz itself - every stage
  // from FResamplerToBaseband onward has to be rebuilt from scratch,
  // resetting each one's internal filter/resampler state, so this can't
  // be applied glitch-free the way a retune can (a short audio
  // discontinuity is expected here, the same as a real radio's own
  // bandwidth-filter switch producing an audible "click"). Safe to do
  // synchronously, unlike uSDRRFSource.pas's own async device retune
  // (see that unit's own ASYNC RETUNE comment): this only stops/restarts
  // a plain CPU compute thread, with no vendor driver/IPC call involved,
  // so there's no risk of the GUI-freeze class of bug that motivated
  // that async design elsewhere.
  WasActive := Assigned(FDSPThread);
  if WasActive then SetActive(False);
  if WasActive then SetActive(True);
end;

function TAMBroadcastReceiver.GetActive: Boolean;
begin
  Result := Assigned(FDSPThread);
end;

function TAMBroadcastReceiver.AudioUnderrunCount: Integer;
begin
  Result := FPlayer.UnderrunCount;
end;

function TAMBroadcastReceiver.AudioAcquireSkipCount: Integer;
begin
  Result := FAcquireSkipCount;
end;

function TAMBroadcastReceiver.AudioErrorCount: Integer;
begin
  Result := FErrorCount;
end;

procedure TAMBroadcastReceiver.SetActive(AValue: Boolean);
begin
  if AValue = Assigned(FDSPThread) then Exit;
  if AValue then begin
    if not (Assigned(FSource) and FSource.IsOpen) then Exit;   // nothing to receive from yet
    BuildChain;
    FDSPThread := TAMDSPThread.Create(Self);
  end else begin
    FDSPThread.Terminate;
    FDSPThread.WaitFor;
    FreeAndNil(FDSPThread);
    TeardownChain;
  end;
end;

procedure TAMBroadcastReceiver.BuildChain;
const
  s = 'TAMBroadcastReceiver.BuildChain : ';
var
  FsIn, BasebandRateHz, AudioTransitionBW: Double;
  MaxAudioSamples: Integer;
begin
  TeardownChain;
  assert(Assigned(FSource) and FSource.IsOpen, s + 'Source must be connected');
  FsIn := FSource.SampleRateHz;

  // BasebandRateHz = BandwidthHz*2: a complex baseband signal centred on
  // the (mixed-to-0Hz) carrier occupies [-BandwidthHz,+BandwidthHz] for
  // ordinary double-sideband AM (both sidebands present), so 2*BandwidthHz
  // is the exact Nyquist rate for that span - the same "sample rate IS
  // the channel bandwidth" construction TFMBroadcastReceiver's own fixed
  // 200kHz uses (see that unit's own BuildChain comment), just with a
  // caller-chosen bandwidth instead of a fixed broadcast-FM spec.
  BasebandRateHz := FBandwidthHz * 2;

  // Wideband resampler TransitionBW scaled proportionally to FsIn, same
  // rationale as TFMBroadcastReceiver's own (see that unit's own
  // BuildChain comment for why a fixed Hz value silently breaks at
  // higher sample rates) - reusing FM's own original, non-ARM64-widened
  // fraction, since AM's much lighter downstream cost hasn't shown any
  // need for the extra headroom FM's heavier stereo-decode chain needed.
  FMixer := TComplexMixer.Create(FsIn, -(FTunedFrequencyHz - FSource.CenterFreqHz));
  FResamplerToBaseband := TRationalResamplerC.Create(FsIn, BasebandRateHz, FsIn * 0.025);
  FDemod := TAMDemodulator.Create(BasebandRateHz);
  // The final audio resampler's TransitionBW has to scale with
  // BasebandRateHz itself here, unlike TFMBroadcastReceiver's own fixed
  // 8000Hz (tuned for one fixed 200kHz BasebandRateHz) - AM's
  // BasebandRateHz varies with the caller's own BandwidthHz (2000-20000
  // Hz across the whole allowed range), always well under
  // DefaultAudioRateHz, so a fixed absolute Hz value would be larger
  // than the entire passband at the narrow end.
  AudioTransitionBW := BasebandRateHz * 0.2;
  FResamplerAudio := TRationalResamplerS.Create(BasebandRateHz, DefaultAudioRateHz, AudioTransitionBW);

  MaxAudioSamples := Round(DefaultAudioRateHz * FEpochDurationMs / 1000 * 2) + 64;
  FPlayer.Open(DefaultAudioRateHz, MaxAudioSamples);

  // A fresh cursor for this streaming session - see
  // TFMBroadcastReceiver.BuildChain's identical comment for why.
  FSourceCursor := FSource.NewStreamCursor;

  FChainBuilt := True;
end;

procedure TAMBroadcastReceiver.TeardownChain;
begin
  if not FChainBuilt then Exit;
  FPlayer.Close;
  FreeAndNil(FMixer);
  FreeAndNil(FResamplerToBaseband);
  FreeAndNil(FDemod);
  FreeAndNil(FResamplerAudio);
  FChainBuilt := False;
end;

function TAMBroadcastReceiver.ProcessOnce: Boolean;
var
  N: Integer;
  IQ, Baseband: TVMobjC;
  Audio: TVMobjS;
  Skipped: Boolean;
begin
  Result := False;
  if not (FChainBuilt and Assigned(FSource)) then Exit;

  // See uFMReceiver.pas's own ProcessAcquireOnce comment for the full
  // TVMobjC/TVMobjS 65535-per-dimension story - identical cap, applied
  // here for the same reason.
  N := Round(FSource.SampleRateHz * FEpochDurationMs / 1000);
  if N > MaxEpochSamples then N := MaxEpochSamples;
  if not FSource.TryReadEpoch(N, FSourceCursor, IQ, Skipped) then Exit;
  if Skipped then Inc(FAcquireSkipCount);

  Baseband := FResamplerToBaseband.Process(FMixer.Process(IQ));
  Audio := FResamplerAudio.Process(FDemod.Process(Baseband, FSynchronous));

  if FVolume <> 1.0 then Audio := Audio * FVolume;

  FPlayer.QueueStereo(Audio, Audio);   // mono - AM broadcast has no stereo subcarrier
  Result := True;
end;

procedure Register;
begin
  RegisterComponents('SDR', [TAMBroadcastReceiver]);
end;

end.
