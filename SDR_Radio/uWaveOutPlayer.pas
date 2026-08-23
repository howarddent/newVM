unit uWaveOutPlayer;

{*******************************************************************************

     TWaveOutPlayer - a minimal Win32 waveOut wrapper for streaming
     16-bit stereo PCM in real time, so uFMReceiver.pas's demodulated
     audio is actually audible rather than only ever a TVMobjS the caller
     has to do something else with. Deliberately not a general-purpose
     audio library - just enough to queue successive stereo buffers and
     have Windows play them back-to-back.

     winmm.dll is a fixed-name, always-present Windows system DLL (unlike
     the versioned MKL/IPP runtime DLLs this repository dynamically binds
     elsewhere - see OneAPI.pas's own header comment for why THOSE need
     LoadLibrary/GetProcAddress), so this uses plain static 'external'
     linkage throughout, same as any other stable Win32 API import.

     Uses a ring of WAVEHDR buffers (FBufferCount, default 16 - see
     below for why that's much larger than the "one or two ahead" a
     naive double/triple-buffering scheme would use) - QueueStereo
     interleaves+converts a TVMobjS pair to 16-bit PCM into the next free
     buffer and submits it via waveOutWrite; a buffer is "free" once
     Windows has finished playing it (WHDR_DONE set on its WAVEHDR,
     checked by polling - simpler and safe to call from the same
     GUI-thread timer tick that drives the whole DSP chain, rather than
     needing a callback thread). If no buffer is free when QueueStereo is
     called, the call is simply dropped rather than blocking - a dropped
     ~20ms buffer is a far smaller audible glitch than freezing the
     whole receive chain waiting for the sound card.

     Why 16 buffers (~320ms of headroom at the default 20ms epoch),
     not the usual 2-4: this timer shares the GUI thread with
     TSDRSpectrumAnalyser's own timer (uVMPlotSDRSpectrum.pas) - both are
     ordinary TTimer instances serviced by the same single-threaded
     Windows message loop, so an occasional slow spectrum/waterfall
     GPU tick delays this component's own tick right behind it. A
     shallow buffer (the original default was 4, ~80ms) drains during
     any such delay and produces an audible click once playback catches
     up empty - confirmed by testing: switching from 4 to 16 buffers
     measurably reduced audible clicks during normal use (spectrum
     analyser + Listen both active, the normal usage pattern). 16 is a
     pragmatic empirical choice, not a value derived from a specific
     worst-case delay measurement - if clicks are still audible, or a
     future change touches spectrum-side timing, it's the first knob to
     revisit; a real fix (moving audio DSP off the GUI thread) would
     remove the need to compensate with buffering depth at all, but is
     a much larger change.

     macOS BACKEND (CoreAudio AudioQueue, OUT OF PROCESS): plays back via
     AudioToolbox's AudioQueue services, but NOT in this process - see
     uSDRAudioIPC.pas's header comment for why: loading AudioToolbox by
     any means at all (static link or dynamic dlopen, before or after
     streaming starts) was confirmed, via a bare-console reproduction with
     no LCL/GUI involved, to silently break libhackrf's native USB
     transfer callback delivery in the same process (~98% read success
     dropped to 0%). Since this app's whole purpose is to stream from a
     live HackRF, AudioToolbox cannot be loaded here at all - so this
     backend instead spawns sdraudiohelper.lpr (a tiny standalone console
     program that owns the real AudioQueue and nothing else) as a child
     process at Open, and streams already-converted 16-bit PCM to it over
     its stdin pipe (uSDRAudioIPC.pas's protocol) via ordinary TProcess.
     QueueStereo's own tanh-soft-limit-and-scale-to-int16 conversion is
     unchanged and still runs in THIS process (it's plain float math, no
     AudioToolbox involved) - only the actual AudioQueue calls moved out.

     Buffering/ring/drop-rather-than-block behaviour lives entirely on the
     child side now (see sdraudiohelper.lpr) - this side has no visibility
     into individual buffer completion, so UnderrunCount stays 0 here for
     a different reason than the Windows/Linux backends' own documented
     "nothing genuine to count" (there, it's that the API doesn't surface
     it; here, it's that the API call happens in a different process).
     A QueueStereo call itself never blocks the caller (the demod thread):
     writing a few KB to a pipe whose reader is a tight read/play loop
     essentially never fills the OS pipe buffer at real-time audio rates,
     and any actual failure (helper crashed/exited) surfaces as a write
     exception, caught and treated as "player no longer open" - the same
     graceful-degradation contract as every other failure mode in this
     unit.

     Historical note: this backend used to call AudioQueueNewOutput/
     AllocateBuffer/EnqueueBuffer/Start/Stop/Dispose directly, in-process,
     exactly the way the Windows/Linux backends below still do for their
     own APIs - see this file's git history for that version, and
     sdraudiohelper.lpr's own header comment, which is where that code
     (buffer ring, completion callback, the SetExceptionMask GOTCHA - see
     that program for the fix, still required, just now applied in the
     child instead of here) now actually lives.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF}
  {$IFDEF DARWIN}Process, uSDRAudioIPC,{$ENDIF}
  SysUtils, Math, newVMSingle;

{$IFDEF WINDOWS}
const
  WAVE_FORMAT_PCM = 1;
  CALLBACK_NULL = 0;
  WHDR_DONE = $00000001;
  WHDR_PREPARED = $00000002;

type
  PWaveFormatEx = ^TWaveFormatEx;
  TWaveFormatEx = packed record
    wFormatTag: Word;
    nChannels: Word;
    nSamplesPerSec: DWord;
    nAvgBytesPerSec: DWord;
    nBlockAlign: Word;
    wBitsPerSample: Word;
    cbSize: Word;
  end;

  PWaveHdr = ^TWaveHdr;
  TWaveHdr = packed record
    lpData: PAnsiChar;
    dwBufferLength: DWord;
    dwBytesRecorded: DWord;
    dwUser: PtrUInt;
    dwFlags: DWord;
    dwLoops: DWord;
    lpNext: PWaveHdr;
    reserved: PtrUInt;
  end;
{$ENDIF}

type
  { TWaveOutPlayer }
  TWaveOutPlayer = class
  private
    FOpen: Boolean;
    {$IFDEF WINDOWS}
    FHandle: THandle;   // HWAVEOUT
    FBuffers: array of record
      Hdr: TWaveHdr;
      Data: array of SmallInt;   // interleaved L/R, 16-bit PCM
    end;
    FNextBuffer: Integer;
    {$ELSE}
      {$IFDEF DARWIN}
    FHelperProcess: TProcess;   // owns the real AudioQueue - see this unit's own header comment
    FMaxSamplesPerChannel: Integer;
    FScratch: array of SmallInt;  // interleaved L/R, 16-bit PCM, reused across calls
    FBufferCount: Integer;
      {$ELSE}
    FPCMHandle: Pointer;          // snd_pcm_t*, opaque handle from ALSA
    FScratch: array of SmallInt;  // interleaved L/R, 16-bit PCM, reused across calls
    // Target queued-frame level for the drift-compensation nudge in
    // QueueStereo - see that method's own comment.
    FLatencyTargetFrames: Integer;
      {$ENDIF}
    {$ENDIF}
    FUnderrunCount: Integer;
  public
    constructor Create(BufferCount: Integer = 16);
    destructor Destroy; override;
    // SampleRate in Hz; MaxSamplesPerChannel bounds how large a single
    // QueueStereo call may be (buffers are pre-sized once, at Open, to
    // avoid allocating on the real-time path).
    procedure Open(SampleRateHz, MaxSamplesPerChannel: Integer);
    procedure Close;
    procedure QueueStereo(const L, R: TVMobjS);
    property IsOpen: Boolean read FOpen;
    // Diagnostic only. On the ALSA backend, counts real xrun recoveries
    // (snd_pcm_writei returning a negative error other than -EAGAIN) -
    // added while chasing an intermittently distorted tone reported on
    // real FM audio; see QueueStereo's own comment on that branch. Always
    // 0 on Windows and on the macOS/CoreAudio backend - neither waveOut's
    // ring-buffer design nor AudioQueue's own completion-callback model
    // surfaces an equivalent recoverable-hardware-xrun notion this
    // property could meaningfully count (see this unit's own header
    // comment, macOS BACKEND, for why).
    property UnderrunCount: Integer read FUnderrunCount;
  end;

implementation

{$IFDEF WINDOWS}

function waveOutOpen(out phwo: THandle; uDeviceID: DWord; pwfx: PWaveFormatEx;
  dwCallback, dwInstance, fdwOpen: DWord): DWord; stdcall; external 'winmm.dll';
function waveOutClose(hwo: THandle): DWord; stdcall; external 'winmm.dll';
function waveOutPrepareHeader(hwo: THandle; pwh: PWaveHdr; cbwh: DWord): DWord; stdcall; external 'winmm.dll';
function waveOutUnprepareHeader(hwo: THandle; pwh: PWaveHdr; cbwh: DWord): DWord; stdcall; external 'winmm.dll';
function waveOutWrite(hwo: THandle; pwh: PWaveHdr; cbwh: DWord): DWord; stdcall; external 'winmm.dll';
function waveOutReset(hwo: THandle): DWord; stdcall; external 'winmm.dll';

constructor TWaveOutPlayer.Create(BufferCount: Integer);
begin
  inherited Create;
  SetLength(FBuffers, BufferCount);
  FNextBuffer := 0;
  FOpen := False;
end;

destructor TWaveOutPlayer.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TWaveOutPlayer.Open(SampleRateHz, MaxSamplesPerChannel: Integer);
const
  s = 'TWaveOutPlayer.Open : ';
var
  Fmt: TWaveFormatEx;
  i: Integer;
begin
  assert(not FOpen, s + 'already open');

  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.wFormatTag := WAVE_FORMAT_PCM;
  Fmt.nChannels := 2;
  Fmt.nSamplesPerSec := SampleRateHz;
  Fmt.wBitsPerSample := 16;
  Fmt.nBlockAlign := (Fmt.nChannels * Fmt.wBitsPerSample) div 8;
  Fmt.nAvgBytesPerSec := Fmt.nSamplesPerSec * Fmt.nBlockAlign;

  if waveOutOpen(FHandle, DWord(-1), @Fmt, 0, 0, CALLBACK_NULL) <> 0 then begin
    FOpen := False;
    Exit;
  end;

  for i := 0 to High(FBuffers) do begin
    SetLength(FBuffers[i].Data, MaxSamplesPerChannel * 2);
    FillChar(FBuffers[i].Hdr, SizeOf(TWaveHdr), 0);
    FBuffers[i].Hdr.dwFlags := WHDR_DONE;   // free until first use
  end;

  FOpen := True;
end;

procedure TWaveOutPlayer.Close;
var
  i: Integer;
begin
  if not FOpen then Exit;
  waveOutReset(FHandle);
  for i := 0 to High(FBuffers) do
    if (FBuffers[i].Hdr.dwFlags and WHDR_PREPARED) <> 0 then
      waveOutUnprepareHeader(FHandle, @FBuffers[i].Hdr, SizeOf(TWaveHdr));
  waveOutClose(FHandle);
  FOpen := False;
end;

procedure TWaveOutPlayer.QueueStereo(const L, R: TVMobjS);
var
  N, i, bufIdx: Integer;
  v: Single;
begin
  if not FOpen then Exit;
  N := L.Rows * L.Cols;
  bufIdx := FNextBuffer;

  // Buffer not yet finished playing - drop this call rather than block;
  // see this unit's own header comment for why.
  if (FBuffers[bufIdx].Hdr.dwFlags and WHDR_DONE) = 0 then Exit;

  if (FBuffers[bufIdx].Hdr.dwFlags and WHDR_PREPARED) <> 0 then
    waveOutUnprepareHeader(FHandle, @FBuffers[bufIdx].Hdr, SizeOf(TWaveHdr));

  if N > Length(FBuffers[bufIdx].Data) div 2 then
    N := Length(FBuffers[bufIdx].Data) div 2;   // clamp to the pre-sized buffer

  // Soft (tanh) saturation rather than a hard clamp - broadcast FM
  // content routinely modulates above the "nominal" 100% level on loud
  // passages (real-world loudness processing at the transmitter, not a
  // bug in this receive chain - TFMStereoDecoder's own FStereoGain is
  // an empirically-tuned average, not a per-station calibration), so
  // occasional peaks above 1.0 are expected rather than exceptional.
  // tanh(x) is close to linear (y~=x) for the levels normal program
  // material actually sits at, and saturates smoothly toward +-1 for
  // anything louder, instead of the harsh digital "flat-top" distortion
  // a hard clamp produces on exactly those peaks - confirmed as the
  // source of "clipping on higher volume music beats" once tuning and
  // the buffering fixes elsewhere made everything else in the chain
  // sound clean.
  for i := 0 to N - 1 do begin
    v := Tanh(L[0, i]);
    FBuffers[bufIdx].Data[i * 2] := Round(v * 32767);
    v := Tanh(R[0, i]);
    FBuffers[bufIdx].Data[i * 2 + 1] := Round(v * 32767);
  end;

  FillChar(FBuffers[bufIdx].Hdr, SizeOf(TWaveHdr), 0);
  FBuffers[bufIdx].Hdr.lpData := PAnsiChar(@FBuffers[bufIdx].Data[0]);
  FBuffers[bufIdx].Hdr.dwBufferLength := N * 4;   // 2 channels * 2 bytes

  waveOutPrepareHeader(FHandle, @FBuffers[bufIdx].Hdr, SizeOf(TWaveHdr));
  waveOutWrite(FHandle, @FBuffers[bufIdx].Hdr, SizeOf(TWaveHdr));

  FNextBuffer := (FNextBuffer + 1) mod Length(FBuffers);
end;

{$ELSE}
  {$IFDEF DARWIN}

// Path to sdraudiohelper, the child process that actually owns
// AudioToolbox - see this unit's own header comment and
// uSDRAudioIPC.pas for why that has to live outside this process.
// Expected to sit right next to the running SDR_Radio executable (they're
// built from the same repo and shipped together); no PATH search, no
// install-location guessing.
function HelperExePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'sdraudiohelper';
end;

constructor TWaveOutPlayer.Create(BufferCount: Integer);
begin
  inherited Create;
  FBufferCount := BufferCount;
  FHelperProcess := nil;
  FOpen := False;
end;

destructor TWaveOutPlayer.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TWaveOutPlayer.Open(SampleRateHz, MaxSamplesPerChannel: Integer);
const
  s = 'TWaveOutPlayer.Open : ';
var
  Header: TSDRAudioIPCHeader;
begin
  assert(not FOpen, s + 'already open');

  if not FileExists(HelperExePath) then begin
    FOpen := False;   // build sdraudiohelper.lpr - see this unit's own header comment
    Exit;
  end;

  FMaxSamplesPerChannel := MaxSamplesPerChannel;
  SetLength(FScratch, MaxSamplesPerChannel * 2);

  FHelperProcess := TProcess.Create(nil);
  FHelperProcess.Executable := HelperExePath;
  FHelperProcess.Options := [poUsePipes];
  try
    FHelperProcess.Execute;
  except
    FreeAndNil(FHelperProcess);
    FOpen := False;
    Exit;
  end;

  Header.Magic := SDRAudioIPCMagic;
  Header.SampleRateHz := SampleRateHz;
  Header.MaxSamplesPerChannel := MaxSamplesPerChannel;
  Header.BufferCount := FBufferCount;
  try
    FHelperProcess.Input.Write(Header, SizeOf(Header));
  except
    FHelperProcess.Terminate(0);
    FreeAndNil(FHelperProcess);
    FOpen := False;
    Exit;
  end;

  FOpen := True;
end;

procedure TWaveOutPlayer.Close;
begin
  if not FOpen then Exit;
  FOpen := False;
  // Closing the child's stdin is its cue to stop and exit cleanly (see
  // uSDRAudioIPC.pas's protocol) - a clean shutdown, not a kill.
  FHelperProcess.CloseInput;
  FHelperProcess.WaitOnExit;
  FreeAndNil(FHelperProcess);
end;

procedure TWaveOutPlayer.QueueStereo(const L, R: TVMobjS);
var
  N, i: Integer;
  v: Single;
  FrameLen: LongWord;
begin
  if not FOpen then Exit;
  N := L.Rows * L.Cols;
  if N > FMaxSamplesPerChannel then N := FMaxSamplesPerChannel;   // clamp to the pre-sized buffer

  // Same soft (tanh) saturation as the Windows/ALSA paths - see the
  // Windows path's own comment (above) for why a hard clamp isn't used.
  // This is plain float math, done here (not in the helper) so the
  // helper stays a pure CoreAudio conduit with nothing else to get wrong.
  for i := 0 to N - 1 do begin
    v := Tanh(L[0, i]);
    FScratch[i * 2] := Round(v * 32767);
    v := Tanh(R[0, i]);
    FScratch[i * 2 + 1] := Round(v * 32767);
  end;

  FrameLen := LongWord(N * 4);
  try
    FHelperProcess.Input.Write(FrameLen, SizeOf(FrameLen));
    FHelperProcess.Input.Write(FScratch[0], FrameLen);
  except
    // Helper crashed/exited - drop out gracefully rather than raise into
    // the demod thread, same contract as every other failure mode here.
    FOpen := False;
  end;
end;

  {$ELSE}

uses
  DynLibs, ctypes;

const
  ALSALibName = 'libasound.so.2';

  // snd_pcm_stream_t/snd_pcm_format_t/snd_pcm_access_t/open-mode values -
  // stable ABI constants from alsa/pcm.h, not probed at runtime (there's
  // no "list the enum" call - these are baked into every ALSA build).
  SND_PCM_STREAM_PLAYBACK = cint(0);
  SND_PCM_FORMAT_S16_LE = cint(2);
  SND_PCM_ACCESS_RW_INTERLEAVED = cint(3);
  SND_PCM_NONBLOCK = cint(1);

  ALSA_EAGAIN = 11;   // Linux errno.h EAGAIN - ALSA calls return -errno on failure

type
  Tsnd_pcm_open = function(pcm: PPointer; name: PAnsiChar; stream, mode: cint): cint; cdecl;
  Tsnd_pcm_close = function(pcm: Pointer): cint; cdecl;
  Tsnd_pcm_set_params = function(pcm: Pointer; format, access: cint; channels, rate: cuint;
    soft_resample: cint; latency: cuint): cint; cdecl;
  Tsnd_pcm_writei = function(pcm: Pointer; buffer: Pointer; size: culong): clong; cdecl;
  Tsnd_pcm_recover = function(pcm: Pointer; err, silent: cint): cint; cdecl;
  // delayp receives the number of frames currently QUEUED (written but not
  // yet played) - see QueueStereo's own comment on FLatencyTargetFrames
  // for what this is used for. Optional binding (probed like the rest,
  // not required for InitializeALSA to report success) since drift
  // compensation is a refinement, not a hard requirement for playback to
  // work at all.
  Tsnd_pcm_delay = function(pcm: Pointer; delayp: Pointer): cint; cdecl;

var
  ALSAHandle: TLibHandle = NilHandle;
  snd_pcm_open: Tsnd_pcm_open;
  snd_pcm_close: Tsnd_pcm_close;
  snd_pcm_set_params: Tsnd_pcm_set_params;
  snd_pcm_writei: Tsnd_pcm_writei;
  snd_pcm_recover: Tsnd_pcm_recover;
  snd_pcm_delay: Tsnd_pcm_delay;

function LoadALSAProc(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(ALSAHandle, Name);
end;

// Probe-once, degrade-gracefully - same contract as this repo's other
// optional runtime bindings: returns False (no exception) if libasound
// isn't installed, so Open below just leaves IsOpen False and the FM
// receive chain keeps running silently, same as before ALSA support
// existed.
function InitializeALSA: Boolean;
begin
  if ALSAHandle = NilHandle then begin
    ALSAHandle := LoadLibrary(ALSALibName);
    if ALSAHandle <> NilHandle then begin
      Pointer(snd_pcm_open)       := LoadALSAProc('snd_pcm_open');
      Pointer(snd_pcm_close)      := LoadALSAProc('snd_pcm_close');
      Pointer(snd_pcm_set_params) := LoadALSAProc('snd_pcm_set_params');
      Pointer(snd_pcm_writei)     := LoadALSAProc('snd_pcm_writei');
      Pointer(snd_pcm_recover)    := LoadALSAProc('snd_pcm_recover');
      Pointer(snd_pcm_delay)      := LoadALSAProc('snd_pcm_delay');
    end;
  end;
  Result := Assigned(snd_pcm_open) and Assigned(snd_pcm_set_params) and Assigned(snd_pcm_writei);
end;

constructor TWaveOutPlayer.Create(BufferCount: Integer);
begin
  inherited Create;
  FPCMHandle := nil;
  FOpen := False;
end;

destructor TWaveOutPlayer.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TWaveOutPlayer.Open(SampleRateHz, MaxSamplesPerChannel: Integer);
const
  s = 'TWaveOutPlayer.Open : ';
var
  Handle: Pointer;
  Silence: array of SmallInt;
  SilenceFrames, Sent: Integer;
  Written: clong;
begin
  assert(not FOpen, s + 'already open');

  if not InitializeALSA then Exit;   // no libasound.so.2 found - stay closed, same as before

  Handle := nil;
  if snd_pcm_open(@Handle, PAnsiChar('default'), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK) <> 0 then
    Exit;

  // soft_resample=1, ~1000ms requested latency - ALSA sizes its own
  // internal ring to this and leaves the stream prepared. Widened here
  // from an original 100ms, then 300ms, in successive earlier fixes -
  // but widening alone does NOT fix underruns, only delays them:
  // confirmed by instrumented testing (a standalone harness feeding a
  // synthetic tone at an exact 20ms/epoch cadence, zero SDR/DSP
  // involved) that even a 300ms buffer still drains steadily over time
  // with no compensation mechanism, because nothing paces production to
  // the SOUND CARD's own playback clock - any persistent mismatch
  // between how fast epochs are queued and how fast ALSA actually drains
  // them (real SDR hardware sample clock ppm error, OS scheduling
  // jitter, CPU contention from the concurrent DSP/GPU work - the exact
  // cause varies, but the buffer being finite means SOME cause always
  // eventually wins) accumulates without bound until it exceeds whatever
  // buffer size is configured. The real fix is QueueStereo's own
  // buffer-level feedback (drift compensation) below; THIS 1000ms value
  // is what gives that feedback loop enough headroom to actually
  // converge before a transient error (e.g. right after a real xrun's
  // recovery) empties the ring - empirically, 300ms was measured too
  // tight for the compensation to fully catch up in time (occasional
  // underruns still occurred over a 60s stress test), 1000ms was clean
  // over the same test. The one-time startup latency this adds is an
  // acceptable trade for a live FM receiver (not a real-time-critical
  // use case the way a call or game would be).
  if snd_pcm_set_params(Handle, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
       2, SampleRateHz, 1, 1000000) <> 0 then begin
    snd_pcm_close(Handle);
    Exit;
  end;

  FPCMHandle := Handle;
  SetLength(FScratch, MaxSamplesPerChannel * 2);
  // Target the QUEUED (not-yet-played) frame count at roughly the
  // midpoint of the requested ~1000ms ring - equal headroom against both
  // underrun (queue drains to empty) and overflow (queue fills, forcing
  // the NONBLOCK-drop path below) - see QueueStereo's own comment.
  FLatencyTargetFrames := Round(SampleRateHz * 0.5);

  // Pre-fill the ring with FLatencyTargetFrames of silence right away,
  // rather than leaving QueueStereo's drift compensation to climb there
  // organically over many calls - that climb is capped at MaxAdjustFrames
  // per call (QueueStereo's own comment), so starting from a genuinely
  // empty ring took several real seconds at the epoch rates this project
  // runs at, audible as a several-second "warbles, then settles" startup
  // transient even once uFMReceiver.pas's real-time deficit that
  // motivated drift compensation in the first place was otherwise fully
  // closed (see that unit's own header comment, "WHY TWO THREADS") - the
  // compensation mechanism was still doing real, necessary work every
  // single call for the first several seconds of every session, just to
  // reach the target level it should have started at. A single upfront
  // silent write reaches FLatencyTargetFrames instantly, so the very
  // first real QueueStereo call already starts near-target with nothing
  // left to compensate. Best-effort: if the ring can't accept the full
  // amount in one NONBLOCK pass (unlikely - it's completely empty at this
  // point), whatever didn't get written just means QueueStereo's own
  // compensation has a smaller, harmless gap left to close instead of the
  // original multi-second one.
  SilenceFrames := FLatencyTargetFrames;
  SetLength(Silence, SilenceFrames * 2);   // interleaved L/R, zero-filled by SetLength
  Sent := 0;
  while Sent < SilenceFrames do begin
    Written := snd_pcm_writei(FPCMHandle, @Silence[Sent * 2], culong(SilenceFrames - Sent));
    if Written <= 0 then begin
      if (Written < 0) and (Written <> -ALSA_EAGAIN) then
        snd_pcm_recover(FPCMHandle, cint(Written), 1);
      Break;
    end;
    Inc(Sent, Written);
  end;

  FOpen := True;
end;

procedure TWaveOutPlayer.Close;
begin
  if not FOpen then Exit;
  if FPCMHandle <> nil then snd_pcm_close(FPCMHandle);
  FPCMHandle := nil;
  FOpen := False;
end;

procedure TWaveOutPlayer.QueueStereo(const L, R: TVMobjS);
const
  // Max frames added/dropped in a single QueueStereo call - see the
  // DRIFT COMPENSATION comment below. Fixed (not proportional to N) so
  // the per-call audible impact stays constant regardless of epoch size;
  // applied every ~20ms this bounds the correctable drift rate to
  // MaxAdjustFrames/(epoch duration), e.g. 32/20ms =~ 3.3% (33000ppm) at
  // the default 20ms epoch - far more than any realistic SDR-hardware-
  // clock-vs-sound-card-clock ppm error or OS scheduling jitter.
  MaxAdjustFrames = 128;
  // Fraction of the current error corrected per call - see the comment
  // below for the geometric-convergence reasoning this value comes from.
  CompensationGain = 0.1;
var
  N, WriteN, Adjust, i, Sent, Remaining, Deadband: Integer;
  v: Single;
  Written: clong;
  DelayFrames: clong;
  Error: Integer;
begin
  if not FOpen then Exit;
  N := L.Rows * L.Cols;
  // Clamp to the pre-sized buffer, same as the Windows path - minus
  // MaxAdjustFrames, to always leave room for the drift-compensation pad
  // below even when a caller's epoch already fills the buffer to the
  // nominal limit.
  if N > Length(FScratch) div 2 - MaxAdjustFrames then
    N := Length(FScratch) div 2 - MaxAdjustFrames;

  // Same soft (tanh) saturation as the Windows path above - see its own
  // comment for why a hard clamp isn't used.
  for i := 0 to N - 1 do begin
    v := Tanh(L[0, i]);
    FScratch[i * 2] := Round(v * 32767);
    v := Tanh(R[0, i]);
    FScratch[i * 2 + 1] := Round(v * 32767);
  end;

  // DRIFT COMPENSATION: nothing paces QueueStereo calls to the sound
  // card's own playback clock - they arrive whenever the caller's DSP
  // chain produces an epoch (in turn paced by the SDR hardware's own
  // sample clock, which has its own independent ppm error against the
  // sound card's clock, on top of ordinary OS scheduling jitter). ANY
  // persistent mismatch, however small, means the ALSA ring's fill level
  // drifts monotonically toward empty (underrun) or full (forced drops
  // below) - and since the ring is finite, it WILL eventually get there
  // no matter how large Open's requested latency is, just later. Confirmed
  // by instrumented testing: a synthetic-tone harness with a fixed
  // 20ms/epoch cadence and no SDR/DSP involved at all still accumulated
  // underruns steadily (~1 every 4-6s after initial headroom) - widening
  // the buffer alone (see Open's own comment) only pushed this out, it
  // never eliminated it.
  //
  // The fix: read back how many frames are currently QUEUED (not yet
  // played) via snd_pcm_delay, and PROPORTIONALLY nudge toward
  // FLatencyTargetFrames (the ring's midpoint) by duplicating or dropping
  // a small number of frames this epoch. Proportional, not fixed-size:
  // correcting by CompensationGain (10%) of the current error each call
  // means the error itself shrinks geometrically (by a factor of
  // 1-CompensationGain per call) once inside the linear region, so it
  // converges smoothly rather than only ever crawling back at a fixed
  // rate - empirically confirmed against a synthetic-tone stress harness
  // (fixed 20ms/epoch cadence, no SDR involved) where a fixed single-
  // frame nudge was measured too small to keep up with the observed
  // drift rate at all, while this proportional version (clamped to
  // MaxAdjustFrames per call so a large one-off error, e.g. right after a
  // real underrun recovery, doesn't itself produce an audible artifact)
  // did. A dead-band (skip compensation for small, normal jitter around
  // the target) keeps this from firing needlessly on every single call.
  WriteN := N;
  if Assigned(snd_pcm_delay) and (N > 0) then begin
    if snd_pcm_delay(FPCMHandle, @DelayFrames) = 0 then begin
      Error := Integer(DelayFrames) - FLatencyTargetFrames;   // >0: too full, <0: too empty
      Deadband := FLatencyTargetFrames div 5;
      if Abs(Error) > Deadband then begin
        Adjust := Round(-Error * CompensationGain);
        if Adjust > MaxAdjustFrames then Adjust := MaxAdjustFrames;
        if Adjust < -MaxAdjustFrames then Adjust := -MaxAdjustFrames;
        WriteN := N + Adjust;
        if WriteN < 1 then WriteN := 1;
      end;
    end;
  end;
  if WriteN > N then
    // Pad: repeat the last frame (WriteN - N) times - simplest way to
    // extend by more than one frame without inventing new content;
    // confined to the epoch boundary, same as the single-frame version.
    for i := N to WriteN - 1 do begin
      FScratch[i * 2] := FScratch[(N - 1) * 2];
      FScratch[i * 2 + 1] := FScratch[(N - 1) * 2 + 1];
    end;

  // snd_pcm_writei in NONBLOCK mode does not just return the full count or
  // -EAGAIN - if the ring has SOME but not all of the requested room, it
  // writes only that many frames and returns that (smaller, positive)
  // count, same as a short write() on a socket. The first cut of this
  // backend treated any non-negative return as "fully queued", silently
  // dropping the unwritten remainder mid-epoch - splicing two unrelated
  // points in the waveform together, an audible click. Fixed here by
  // looping to send only the still-unwritten tail each pass; the loop
  // cannot block, since NONBLOCK mode still returns immediately (with
  // -EAGAIN once the ring is genuinely full) rather than waiting for
  // room. Neither this nor widened buffering alone eliminated the
  // reported "intermittent distorted tone" on real FM audio - see the
  // drift-compensation comment above for the fix that actually addresses
  // the root cause, and UnderrunCount above for how to confirm which
  // path is actually firing.
  Sent := 0;
  Remaining := WriteN;
  while Remaining > 0 do begin
    Written := snd_pcm_writei(FPCMHandle, @FScratch[Sent * 2], culong(Remaining));
    if Written < 0 then begin
      // -EAGAIN: ring is genuinely full right now - drop whatever's left
      // of this epoch rather than block, the same "drop rather than
      // stall the receive chain" contract the Windows path documents.
      // Any other negative error (e.g. -EPIPE, an underrun) is a real
      // xrun - counted (FUnderrunCount) and handed to snd_pcm_recover so
      // playback resumes instead of staying wedged after the first glitch.
      if Written <> -ALSA_EAGAIN then begin
        Inc(FUnderrunCount);
        snd_pcm_recover(FPCMHandle, cint(Written), 1);
      end;
      Break;
    end;
    if Written = 0 then Break;   // defensive - avoid spinning if ALSA ever reports this
    Inc(Sent, Written);
    Dec(Remaining, Written);
  end;
end;

  {$ENDIF}
{$ENDIF}

end.
