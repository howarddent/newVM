unit uSDRRFSource;

{*******************************************************************************

     TSDRRFSource - a non-visual, installable Lazarus component wrapping
     everything hardware-specific about the SDR front end: USB device
     autodetection (uSDRDevice.pas's TSDRDevice, and each concrete backend
     - uHackRF.pas/uRTLSDR.pas/uSDRplay.pas), the capability-driven gain/
     frequency/sample-rate controls those backends expose, and the epoch
     read loop. Everything here already existed in uSDRMain.pas's TForm1
     (FDevice plus DetectAndOpenDevice/ApplyAllGains/etc.) - this unit
     pulls it out into its own component specifically so it can be dropped
     onto ANY form (design-time, via the component palette, same as
     Graphs/uVMPlot2D.pas's TVMPlot2D) rather than being wired by hand into
     one particular demo, and so a separate display component (see
     uVMPlotSDRSpectrum.pas's TSDRSpectrumAnalyser) can consume its output
     without depending on any GUI-layout specifics of uSDRMain.pas at all.

     MULTIPLE INDEPENDENT CONSUMERS (why TryReadEpoch takes a Cursor):
     uSDRDevice.pas's TSDRDevice.TryReadEpoch reads from a SINGLE-CONSUMER
     ring buffer (TSDRRingBuffer) - every successful read DESTRUCTIVELY
     removes those bytes, so only one caller can ever drain it correctly.
     This unit's very first version forwarded straight through to that
     (no Cursor, no internal buffering) - which worked fine as long as
     exactly one component ever called TryReadEpoch. It stopped working
     the moment a second one did (uFMReceiver.pas's TFMBroadcastReceiver,
     added alongside uVMPlotSDRSpectrum.pas's TSDRSpectrumAnalyser): the
     two components' own timers each called TryReadEpoch independently,
     each one silently stealing samples out from under the other -
     manifesting as garbled/discontinuous audio, and confirmed (once
     traced down) to explain every symptom reported testing it: warble,
     "sections repeated", and finally "no audio, just occasional clicks"
     once the receive chain was fast enough that the two consumers'
     timers were racing hard against each other for the same bytes.

     The fix: TSDRRFSource now owns its own internal, generously-sized
     circular buffer (FStreamRing) of complex samples, kept filled by a
     background thread (FPollThread) that's the ONLY thing that ever
     calls FDevice.TryReadEpoch - so there is still exactly one consumer
     of the single-consumer device-level ring buffer, satisfying its own
     contract. Every EXTERNAL caller instead reads from FStreamRing via
     TryReadEpoch(N, var Cursor, out IQ) - Cursor is an opaque running
     sample count (Int64) owned by the CALLER, not this component; each
     caller keeps their own, obtained once via NewStreamCursor, and
     TryReadEpoch never mutates FStreamRing itself - it only reads from
     it and advances the caller's own Cursor - so any number of
     independent consumers can each read the full, correct, unstolen
     stream at whatever epoch size and cadence suits them, falling
     behind and catching back up independently of each other. A
     consumer that falls behind by more than the ring's own capacity is
     skipped forward to the newest available window rather than handed
     stale/overwritten data - the same "don't fall behind" philosophy
     TSDRRingBuffer.TryReadNewest already uses for the single
     device-level buffer, just now applied per-consumer instead of
     globally.

     WHY A BACKGROUND THREAD, NOT A TTIMER: the first version of this
     fix used an ordinary TTimer (FPollTimer) on the GUI thread, looping
     each tick to drain everything currently available rather than
     assuming one fixed-size read per tick (see the git history of
     PollTick for that version). That closed the worst of the data loss
     but real-hardware testing still showed occasional dropouts: this
     component's poll timer shares the GUI thread with
     TSDRSpectrumAnalyser's own GPU/OpenCL processing, and whenever THAT
     blocked the thread for long enough, polling couldn't run at all -
     no amount of "loop to catch up once you finally get to run" helps
     if the device-level ring buffer (a few MB) overflows and starts
     silently overwriting itself before the GUI thread frees up. A
     dedicated thread for polling (FPollThread, a plain tight loop
     calling FDevice.TryReadEpoch with a short Sleep when nothing's
     ready) can never be blocked by GUI-thread work, so it keeps
     draining the hardware buffer regardless of how busy the spectrum
     display gets. FStreamLock (a TCriticalSection) protects FStreamRing/
     FStreamTotalWritten between this thread (the sole writer) and
     TryReadEpoch (called from the GUI thread, the reader(s)) - the same
     producer/consumer locking pattern TSDRRingBuffer itself already
     uses between the device's own USB callback thread and this one.

     ASYNC RETUNE (FControlThread, RequestFrequencyHz): each backend's own
     SetFrequencyHz (uHackRF.pas/uRTLSDR.pas/uSDRplay.pas) makes a
     synchronous, potentially slow call straight into the vendor driver/
     API whenever already streaming (e.g. SDRplay's sdrplay_api_Update -
     a real IPC round-trip to sdrplay_apiService.exe, not a fire-and-
     forget register write) - calling it directly from the GUI thread, as
     uSDRMain.pas's FreqEdit/keypad retune handlers originally did, froze
     the entire application's message loop for however long that call
     took under real concurrent load (this component's own FPollThread
     plus a running FMBroadcastReceiver plus TSDRSpectrumAnalyser's GPU
     work all competing for the same USB/IPC bandwidth) - long enough
     that a user watching Windows mark the window "Not Responding" would
     reasonably conclude it had hung outright and kill it via Task
     Manager. RequestFrequencyHz fixes this by handing the actual device
     call to a small dedicated background thread (FControlThread, same
     "one persistent thread, not a thread per call" shape as FPollThread
     itself - concurrent calls into the same device handle from multiple
     threads at once would be unsafe regardless of blocking) and
     returning immediately; FOnFrequencyChanged fires once the call has
     actually completed (success or failure - see LastFrequencyChangeOk),
     via TThread.Queue so the worker thread never waits on the GUI
     thread's own responsiveness to make progress. Only frequency is
     covered here, since that's what actually gets driven from a live
     control while streaming in this app (FreqEdit/the keypad) - SetGain/
     SetBoolOption carry the identical risk (the same backends route them
     through the same blocking vendor Update call while streaming) but
     aren't wired through this mechanism yet; extending it to them would
     follow the same shape if that ever becomes a reported problem too.

     OUTPUT STREAM: TryReadEpoch fills a (1,N) TVMobjC - SINGLE precision
     complex (newVMComplexSingle.pas), not the double-precision TVMobjZ
     TSDRDevice.TryReadEpoch itself returns - converted once, in
     PollTick, when each chunk is appended to FStreamRing (not
     per-consumer-call). Single precision because the primary consumer
     (TSDRSpectrumAnalyser) uploads it straight to the GPU via newVMCL,
     which is single-precision throughout (see newVMCL.pas's own header
     comment); doubling that up through TVMobjZ first would just be a
     wasted conversion.

     No published properties: unlike TVMPlot2D/3D's Title/colour/etc,
     there's nothing about a hardware connection that's meaningful to
     configure at design time (form design happens with no device
     attached) - every real setting here (frequency, sample rate, gain)
     only makes sense once Connect has actually opened a real device and
     its Capabilities are known, so those are ordinary runtime methods,
     same shape as TSDRDevice's own interface.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Math, OneAPI, newVMComplex, newVMComplexSingle,
  uSDRDevice, uHackRF, uRTLSDR, uSDRplay;

type
  // An opaque running sample count - owned and stored by the CALLER (one
  // per independent consumer), not by TSDRRFSource itself. Obtain a
  // fresh one via NewStreamCursor before the first TryReadEpoch call;
  // see this unit's own header comment for the full rationale.
  TSDRStreamCursor = Int64;

  TSDRRFSource = class;

  // Plain tight-loop poller - see this unit's own header comment
  // ("WHY A BACKGROUND THREAD, NOT A TTIMER") for why this can't just
  // be a TTimer. Sleeps briefly only when there was nothing to read,
  // so it neither busy-spins the CPU nor ever waits on GUI-thread
  // scheduling to keep draining the hardware buffer.
  { TSDRPollThread }
  TSDRPollThread = class(TThread)
  private
    FOwner: TSDRRFSource;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TSDRRFSource);
  end;

  // Runs FDevice.SetFrequencyHz off the GUI thread - see this unit's own
  // header comment ("ASYNC RETUNE") for why that call can otherwise
  // freeze the whole application. RequestFrequencyHz just records the
  // latest requested Hz under FLock and returns immediately; Execute
  // picks it up on its own schedule. Deliberately coalescing, not
  // queuing, successive requests: only the LAST one issued (e.g. several
  // keypad/spinner edits in quick succession) is ever worth actually
  // applying, the same way a human turning a real tuning knob only cares
  // where it ends up, not every intermediate value it passed through.
  { TSDRControlThread }
  TSDRControlThread = class(TThread)
  private
    FOwner: TSDRRFSource;
    FLock: TCriticalSection;
    FPendingHz: QWord;
    FHasPending: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TSDRRFSource);
    destructor Destroy; override;
    procedure RequestFrequencyHz(Hz: QWord);
  end;

  { TSDRRFSource }
  TSDRRFSource = class(TComponent)
  private
    FDevice: TSDRDevice;
    FLastError: string;

    FStreamRing: array of TComplex8;
    FStreamCapacity: Integer;
    FStreamTotalWritten: Int64;
    FStreamLock: TCriticalSection;
    FPollThread: TSDRPollThread;
    FPollChunkSamples: Integer;

    FControlThread: TSDRControlThread;
    FLastFrequencyChangeOk: Boolean;
    FOnFrequencyChanged: TNotifyEvent;

    function GetCapabilities: TSDRCapabilities;
    function GetIsOpen: Boolean;
    function GetIsStreaming: Boolean;
    function GetCenterFreqHz: QWord;
    function GetSampleRateHz: Double;
    function GetDeviceName: string;
    // Called only from FPollThread. Returns True iff a chunk was read
    // and appended to FStreamRing.
    function PollOnce: Boolean;
    // Called (via TThread.Queue, so on the main thread) once
    // FControlThread finishes applying a requested frequency - see this
    // unit's own ASYNC RETUNE header comment.
    procedure ControlThreadFrequencyApplied;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    // Tries each known backend in turn (same order/rationale as
    // uSDRMain.pas's original DetectAndOpenDevice: HackRF, then RTL-SDR,
    // then SDRplay - first to actually Open wins). Returns False (with
    // LastError/ErrMsg set) if none respond, or if already connected.
    function Connect(out ErrMsg: string): Boolean;
    procedure Disconnect;

    function StartStreaming(SampleRateHz: Double; FreqHz: QWord): Boolean;
    procedure StopStreaming;

    function SetFrequencyHz(Hz: QWord): Boolean;
    // Asynchronous equivalent of SetFrequencyHz - returns immediately;
    // see this unit's own ASYNC RETUNE header comment. Safe to call
    // whether or not currently streaming - while streaming the actual
    // device call runs on FControlThread; otherwise (no live vendor call
    // to block on - see each backend's own SetFrequencyHz) it runs
    // synchronously right here, but either way OnFrequencyChanged fires
    // exactly once per call once the outcome (LastFrequencyChangeOk) is
    // known, so callers don't need to special-case which path was taken.
    procedure RequestFrequencyHz(Hz: QWord);
    function SetGain(StageIndex: Integer; Value: Double): Boolean;
    function SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;

    // Call once per independent consumer (e.g. once when a component's
    // Source is assigned, or when it starts) to obtain a cursor starting
    // "caught up" - not attempting to replay history from before the
    // consumer subscribed.
    function NewStreamCursor: TSDRStreamCursor;

    // Called from the GUI thread. Cursor is this SPECIFIC caller's own
    // running position (see this unit's own header comment) - pass the
    // same variable back in on every call. Returns True and fills IQ (a
    // fresh (1,N) TVMobjC) iff N new samples were available for this
    // caller; advances Cursor by exactly N on success.
    function TryReadEpoch(N: Integer; var Cursor: TSDRStreamCursor; out IQ: TVMobjC): Boolean;

    property Capabilities: TSDRCapabilities read GetCapabilities;
    property IsOpen: Boolean read GetIsOpen;
    property IsStreaming: Boolean read GetIsStreaming;
    property CenterFreqHz: QWord read GetCenterFreqHz;
    property SampleRateHz: Double read GetSampleRateHz;
    property DeviceName: string read GetDeviceName;
    property LastError: string read FLastError;
    // Outcome of the most recently completed RequestFrequencyHz call -
    // meaningful once OnFrequencyChanged has fired for it (LastError
    // holds the reason on False, same as every other method here).
    property LastFrequencyChangeOk: Boolean read FLastFrequencyChangeOk;
    property OnFrequencyChanged: TNotifyEvent read FOnFrequencyChanged write FOnFrequencyChanged;
  end;

procedure Register;

implementation

const
  // How much of the stream FStreamRing holds at once, in seconds -
  // generous headroom over any current consumer's own per-call epoch
  // size/cadence, so ordinary scheduling jitter between independent
  // consumers never triggers the "fell behind, skip forward" path in
  // normal operation.
  StreamRingSeconds = 1.0;
  // Size of each individual FDevice.TryReadEpoch call FPollThread makes,
  // expressed as a duration for readability - small enough to keep
  // this thread's own added latency low (a consumer's request is
  // satisfied within a poll or two of becoming available), large enough
  // not to spin needlessly. FPollThread's own loop (not a fixed timer
  // interval - see this unit's own header comment) calls this
  // repeatedly, back-to-back, whenever data is ready, so unlike the
  // TTimer-based version this never has to correctly guess a real
  // firing interval.
  PollChunkMs = 5;
  // Safe margin under TVMobjZ's real per-dimension cap (TDim =
  // 0..MaxDim-1, MaxDim=65536 in newVM.pas - a bound from this
  // library's matrix-algebra heritage, never designed for audio-scale
  // per-call sample counts). PollChunkMs*SampleRateHz alone would
  // exceed this above ~13.1Msps (e.g. HackRF's own 16/20Msps modes),
  // which crashed FDevice.TryReadEpoch's TVMobjZ.Create with an
  // assertion INSIDE FPollThread - not just silencing one consumer's
  // audio the way the same bug did in TFMBroadcastReceiver (see that
  // unit's own ProcessOnce comment), but killing the single poll thread
  // every other consumer (including TSDRSpectrumAnalyser) depends on.
  MaxPollChunkSamples = 60000;

constructor TSDRRFSource.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FStreamLock := TCriticalSection.Create;
end;

destructor TSDRRFSource.Destroy;
begin
  StopStreaming;   // stops and waits for FPollThread, if running
  FDevice.Free;    // stops RX and closes the device itself, if still open
  FStreamLock.Free;
  inherited Destroy;
end;

{ TSDRPollThread }

constructor TSDRPollThread.Create(AOwner: TSDRRFSource);
begin
  inherited Create(False);   // start running immediately
  FOwner := AOwner;
  FreeOnTerminate := False;   // TSDRRFSource owns and frees this explicitly
end;

procedure TSDRPollThread.Execute;
begin
  while not Terminated do
    if not FOwner.PollOnce then Sleep(1);
end;

{ TSDRControlThread }

constructor TSDRControlThread.Create(AOwner: TSDRRFSource);
begin
  inherited Create(False);   // start running immediately
  FOwner := AOwner;
  FreeOnTerminate := False;   // TSDRRFSource owns and frees this explicitly
  FLock := TCriticalSection.Create;
end;

destructor TSDRControlThread.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TSDRControlThread.RequestFrequencyHz(Hz: QWord);
begin
  FLock.Enter;
  try
    FPendingHz := Hz;
    FHasPending := True;
  finally
    FLock.Leave;
  end;
end;

procedure TSDRControlThread.Execute;
var
  Hz: QWord;
  Have: Boolean;
begin
  while not Terminated do begin
    FLock.Enter;
    try
      Have := FHasPending;
      Hz := FPendingHz;
      FHasPending := False;
    finally
      FLock.Leave;
    end;

    if Have and Assigned(FOwner.FDevice) then begin
      // The potentially slow/blocking vendor call this whole thread
      // exists to keep off the GUI thread - see this unit's own ASYNC
      // RETUNE header comment.
      FOwner.FLastFrequencyChangeOk := FOwner.FDevice.SetFrequencyHz(Hz);
      if not FOwner.FLastFrequencyChangeOk then FOwner.FLastError := FOwner.FDevice.LastError;
      // Queue, not Synchronize - this thread must never wait on the GUI
      // thread's own message-loop responsiveness to make progress
      // (Synchronize would block Execute until the main thread gets
      // around to running the callback; Queue posts and moves on).
      TThread.Queue(nil, @FOwner.ControlThreadFrequencyApplied);
    end else
      Sleep(5);
  end;
end;

function TSDRRFSource.GetCapabilities: TSDRCapabilities;
begin
  if Assigned(FDevice) then Result := FDevice.Capabilities
  else Result := Default(TSDRCapabilities);
end;

function TSDRRFSource.GetIsOpen: Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen;
end;

function TSDRRFSource.GetIsStreaming: Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsStreaming;
end;

function TSDRRFSource.GetCenterFreqHz: QWord;
begin
  if Assigned(FDevice) then Result := FDevice.CenterFreqHz else Result := 0;
end;

function TSDRRFSource.GetSampleRateHz: Double;
begin
  if Assigned(FDevice) then Result := FDevice.SampleRateHz else Result := 0;
end;

function TSDRRFSource.GetDeviceName: string;
begin
  if Assigned(FDevice) then Result := FDevice.Capabilities.DeviceName else Result := '';
end;

function TSDRRFSource.Connect(out ErrMsg: string): Boolean;
var
  HackRF: THackRFDevice;
  RTLSDR: TRTLSDRDevice;
  SDRplay: TSDRplayDevice;
  Reasons: string;
begin
  Result := False;
  ErrMsg := '';
  if Assigned(FDevice) then begin
    ErrMsg := 'already connected';
    Exit;
  end;

  Reasons := '';

  HackRF := THackRFDevice.Create;
  if HackRF.Open then begin
    FDevice := HackRF;
    Result := True;
    Exit;
  end;
  Reasons := 'HackRF: ' + HackRF.LastError;
  HackRF.Free;

  RTLSDR := TRTLSDRDevice.Create;
  if RTLSDR.Open then begin
    FDevice := RTLSDR;
    Result := True;
    Exit;
  end;
  Reasons := Reasons + '; RTL-SDR: ' + RTLSDR.LastError;
  RTLSDR.Free;

  SDRplay := TSDRplayDevice.Create;
  if SDRplay.Open then begin
    FDevice := SDRplay;
    Result := True;
    Exit;
  end;
  Reasons := Reasons + '; SDRplay: ' + SDRplay.LastError;
  SDRplay.Free;

  ErrMsg := 'no SDR device found (' + Reasons + ')';
  FLastError := ErrMsg;
end;

procedure TSDRRFSource.Disconnect;
begin
  if not Assigned(FDevice) then Exit;
  StopStreaming;
  FreeAndNil(FDevice);
end;

function TSDRRFSource.StartStreaming(SampleRateHz: Double; FreqHz: QWord): Boolean;
begin
  Result := False;
  if not Assigned(FDevice) then Exit;
  if not FDevice.SetSampleRateHz(SampleRateHz) then begin
    FLastError := FDevice.LastError;
    Exit;
  end;
  if not FDevice.SetFrequencyHz(FreqHz) then begin
    FLastError := FDevice.LastError;
    Exit;
  end;
  Result := FDevice.StartRX;
  if not Result then begin
    FLastError := FDevice.LastError;
    Exit;
  end;

  // (Re)size the shared ring for this session's actual sample rate and
  // reset the write position - a fresh StartStreaming always starts a
  // fresh stream, so any previously-issued cursors naturally fall
  // behind and get skipped forward to the new start on their next call
  // (see TryReadEpoch's own "fell behind" handling) rather than needing
  // to be explicitly invalidated here.
  FStreamCapacity := Max(Round(SampleRateHz * StreamRingSeconds), 1);
  SetLength(FStreamRing, FStreamCapacity);
  FStreamTotalWritten := 0;
  FPollChunkSamples := Min(Max(Round(SampleRateHz * PollChunkMs / 1000), 256), MaxPollChunkSamples);

  FPollThread := TSDRPollThread.Create(Self);
  FControlThread := TSDRControlThread.Create(Self);
end;

procedure TSDRRFSource.StopStreaming;
begin
  // Stop FControlThread before FPollThread/FDevice.StopRX - any retune
  // it might currently be mid-call on should finish (or be abandoned via
  // WaitFor same as FPollThread) before the device itself is torn down.
  if Assigned(FControlThread) then begin
    FControlThread.Terminate;
    FControlThread.WaitFor;
    FreeAndNil(FControlThread);
  end;
  if Assigned(FPollThread) then begin
    FPollThread.Terminate;
    FPollThread.WaitFor;
    FreeAndNil(FPollThread);
  end;
  if Assigned(FDevice) and FDevice.IsStreaming then FDevice.StopRX;
end;

function TSDRRFSource.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.SetFrequencyHz(Hz);
  if not Result and Assigned(FDevice) then FLastError := FDevice.LastError;
end;

procedure TSDRRFSource.RequestFrequencyHz(Hz: QWord);
begin
  if Assigned(FControlThread) then
    FControlThread.RequestFrequencyHz(Hz)
  else begin
    // Not streaming - no live vendor call happens here (see each
    // backend's own SetFrequencyHz), so this is already fast/non-
    // blocking; apply it synchronously and fire the same completion
    // event immediately, so callers don't need to know or care which
    // path was actually taken.
    FLastFrequencyChangeOk := Assigned(FDevice) and FDevice.SetFrequencyHz(Hz);
    if not FLastFrequencyChangeOk and Assigned(FDevice) then FLastError := FDevice.LastError;
    if Assigned(FOnFrequencyChanged) then FOnFrequencyChanged(Self);
  end;
end;

procedure TSDRRFSource.ControlThreadFrequencyApplied;
begin
  if Assigned(FOnFrequencyChanged) then FOnFrequencyChanged(Self);
end;

function TSDRRFSource.SetGain(StageIndex: Integer; Value: Double): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen and FDevice.SetGain(StageIndex, Value);
end;

function TSDRRFSource.SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen and FDevice.SetBoolOption(OptionIndex, Value);
end;

// Called only from FPollThread - the ONLY caller of FDevice.TryReadEpoch
// (see this unit's own header comment for why that has to stay true for
// the single-consumer device-level ring buffer to work correctly at
// all). One FDevice.TryReadEpoch attempt per call; FPollThread's own
// Execute loop calls this back-to-back whenever it succeeds, so
// whatever's actually accumulated gets drained continuously rather than
// this needing to guess how much to ask for based on an assumed timer
// interval - see this unit's header comment for why a plain TTimer
// couldn't do this reliably.
function TSDRRFSource.PollOnce: Boolean;
var
  IQD: TVMobjZ;
  i, RingPos: Integer;
  Bin: TComplex16;
begin
  Result := False;
  if not (Assigned(FDevice) and FDevice.IsStreaming) then Exit;
  if not FDevice.TryReadEpoch(FPollChunkSamples, IQD) then Exit;

  FStreamLock.Enter;
  try
    RingPos := Integer(FStreamTotalWritten mod FStreamCapacity);
    for i := 0 to FPollChunkSamples - 1 do begin
      Bin := IQD[0, i];
      FStreamRing[RingPos] := Cplx8(Bin.re, Bin.im);
      RingPos := RingPos + 1;
      if RingPos >= FStreamCapacity then RingPos := 0;
    end;
    FStreamTotalWritten := FStreamTotalWritten + FPollChunkSamples;
  finally
    FStreamLock.Leave;
  end;
  Result := True;
end;

function TSDRRFSource.NewStreamCursor: TSDRStreamCursor;
begin
  FStreamLock.Enter;
  try
    Result := FStreamTotalWritten;
  finally
    FStreamLock.Leave;
  end;
end;

// Called from whichever thread the consumer itself runs on (every
// current consumer happens to be GUI-thread, but nothing here assumes
// that) - locked against FPollThread's own concurrent writes via the
// same FStreamLock TSDRRingBuffer's producer/consumer pair already uses
// for exactly this kind of cross-thread access.
function TSDRRFSource.TryReadEpoch(N: Integer; var Cursor: TSDRStreamCursor; out IQ: TVMobjC): Boolean;
var
  i, StartPos, RingPos: Integer;
begin
  Result := False;
  if FStreamCapacity = 0 then Exit;   // not streaming yet

  FStreamLock.Enter;
  try
    if FStreamTotalWritten - Cursor < N then Exit;

    // Fell behind further than the ring itself holds - the samples this
    // cursor would need have already been overwritten. Skip forward to
    // the newest available N-sample window, same "don't fall behind"
    // philosophy TSDRRingBuffer.TryReadNewest already uses for the
    // single device-level buffer.
    if FStreamTotalWritten - Cursor > FStreamCapacity then
      Cursor := FStreamTotalWritten - FStreamCapacity;

    IQ := TVMobjC.Create(1, N);
    StartPos := Integer(Cursor mod FStreamCapacity);
    RingPos := StartPos;
    for i := 0 to N - 1 do begin
      IQ[0, i] := FStreamRing[RingPos];
      RingPos := RingPos + 1;
      if RingPos >= FStreamCapacity then RingPos := 0;
    end;

    Cursor := Cursor + N;
    Result := True;
  finally
    FStreamLock.Leave;
  end;
end;

procedure Register;
begin
  RegisterComponents('SDR', [TSDRRFSource]);
end;

end.
