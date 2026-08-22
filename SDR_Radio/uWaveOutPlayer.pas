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

     LINUX BACKEND (ALSA): non-Windows platforms play back via a runtime
     (dlopen) binding to libasound.so.2's "simple" PCM API
     (snd_pcm_open/set_params/writei/recover/close) - same
     LoadLibrary/GetProcedureAddress-once, tolerant-of-absence pattern
     this repo already uses for other optional runtime libraries
     (cblas.pas/OpenBLAS, fftw3.pas/FFTW, uRTLSDR.pas/uHackRF.pas), kept
     local to this unit since nothing else needs ALSA. The PCM device is
     opened with SND_PCM_NONBLOCK, and snd_pcm_set_params (channels=2,
     format=S16_LE, access=RW_INTERLEAVED, a ~100ms requested latency) is
     used instead of the individual hw_params calls - it's ALSA's own
     one-call convenience wrapper that picks sane defaults and leaves the
     stream prepared, so no separate snd_pcm_prepare call is needed. A
     single reused scratch buffer stands in for the Windows path's ring
     of WAVEHDRs, since ALSA already provides its own internal ring
     (sized via that latency parameter) - queueing here is just one
     snd_pcm_writei call per QueueStereo. Non-blocking mode means a full
     ALSA ring reports back as -EAGAIN rather than blocking the GUI
     thread, which this treats as "drop this epoch", exactly the
     Windows path's own documented behaviour above; any other negative
     return (e.g. -EPIPE, an underrun) is handed to snd_pcm_recover so
     playback resumes instead of staying wedged after the first glitch.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF WINDOWS}Windows,{$ENDIF} SysUtils, Math, newVMSingle;

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
    FPCMHandle: Pointer;          // snd_pcm_t*, opaque handle from ALSA
    FScratch: array of SmallInt;  // interleaved L/R, 16-bit PCM, reused across calls
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
    // Diagnostic only. On the ALSA (non-Windows) backend, counts real
    // xrun recoveries (snd_pcm_writei returning a negative error other
    // than -EAGAIN) - added while chasing an intermittently distorted
    // tone reported on real FM audio; see QueueStereo's own comment on
    // this branch. Always 0 on Windows (waveOut's ring-buffer design
    // doesn't have an equivalent recoverable-error notion).
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

var
  ALSAHandle: TLibHandle = NilHandle;
  snd_pcm_open: Tsnd_pcm_open;
  snd_pcm_close: Tsnd_pcm_close;
  snd_pcm_set_params: Tsnd_pcm_set_params;
  snd_pcm_writei: Tsnd_pcm_writei;
  snd_pcm_recover: Tsnd_pcm_recover;

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
begin
  assert(not FOpen, s + 'already open');

  if not InitializeALSA then Exit;   // no libasound.so.2 found - stay closed, same as before

  Handle := nil;
  if snd_pcm_open(@Handle, PAnsiChar('default'), SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK) <> 0 then
    Exit;

  // soft_resample=1, ~300ms requested latency - ALSA sizes its own
  // internal ring to this and leaves the stream prepared. Originally
  // 100ms, widened to match the Windows path's own 16-buffer (~320ms)
  // headroom after 100ms proved too tight in practice: a direct
  // speaker-test at the identical rate/format (48000Hz S16_LE stereo)
  // played several seconds clean with zero underruns using ALSA's own
  // much larger default buffer, which pointed squarely at our own
  // request being the tight part, not this machine's audio stack
  // (PipeWire's ALSA compatibility layer) - see QueueStereo's own
  // comment for the underrun-recovery path this headroom is meant to
  // make rare.
  if snd_pcm_set_params(Handle, SND_PCM_FORMAT_S16_LE, SND_PCM_ACCESS_RW_INTERLEAVED,
       2, SampleRateHz, 1, 300000) <> 0 then begin
    snd_pcm_close(Handle);
    Exit;
  end;

  FPCMHandle := Handle;
  SetLength(FScratch, MaxSamplesPerChannel * 2);
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
var
  N, i, Sent, Remaining: Integer;
  v: Single;
  Written: clong;
begin
  if not FOpen then Exit;
  N := L.Rows * L.Cols;
  if N > Length(FScratch) div 2 then
    N := Length(FScratch) div 2;   // clamp to the pre-sized buffer, same as Windows path

  // Same soft (tanh) saturation as the Windows path above - see its own
  // comment for why a hard clamp isn't used.
  for i := 0 to N - 1 do begin
    v := Tanh(L[0, i]);
    FScratch[i * 2] := Round(v * 32767);
    v := Tanh(R[0, i]);
    FScratch[i * 2 + 1] := Round(v * 32767);
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
  // room. This alone did NOT eliminate the reported "intermittent
  // distorted tone" on real FM audio, though - see Open's own comment
  // for the other half of the fix (widened buffering), and
  // UnderrunCount above for how to confirm which path is actually firing.
  Sent := 0;
  Remaining := N;
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

end.
