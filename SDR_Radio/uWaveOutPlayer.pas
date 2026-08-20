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

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils, Math, newVMSingle;

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

  { TWaveOutPlayer }
  TWaveOutPlayer = class
  private
    FHandle: THandle;   // HWAVEOUT
    FOpen: Boolean;
    FBuffers: array of record
      Hdr: TWaveHdr;
      Data: array of SmallInt;   // interleaved L/R, 16-bit PCM
    end;
    FNextBuffer: Integer;
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
  end;

implementation

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

end.
