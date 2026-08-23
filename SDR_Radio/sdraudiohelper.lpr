program sdraudiohelper;

{*******************************************************************************

     sdraudiohelper - the CHILD half of the out-of-process CoreAudio split
     documented in uSDRAudioIPC.pas and uWaveOutPlayer.pas's own header
     comment (macOS BACKEND). A deliberately tiny, single-purpose console
     program: read a THeader then a stream of PCM frames from stdin
     (uSDRAudioIPC.pas's protocol), play them via AudioQueue, exit cleanly
     on EOF. Nothing else - no HackRF, no LCL, no GUI - specifically so
     AudioToolbox is never loaded into the same process as a live HackRF
     stream (that combination is what silently killed libhackrf's USB
     callback delivery - see uSDRAudioIPC.pas for the confirmed repro).

     BUILD: plain `fpc sdraudiohelper.lpr`, no lazbuild/.lpi, same
     rationale as newvmconfigure.lpr's own header comment - this program
     has no LCL dependency and nothing platform-detected to configure, so
     a full Lazarus project is pure overhead. Only ever built/used on
     Darwin; harmless (and pointless) to build elsewhere, since
     uWaveOutPlayer.pas's Windows/Linux backends never spawn it.

     The actual AudioQueue binding subset (types, externals,
     SetExceptionMask GOTCHA, buffer-ring/completion-callback shape) is
     copied from uWaveOutPlayer.pas's own former in-process Darwin
     backend - see that unit's git history for the version this was split
     out of, and its still-current header comment for the full rationale
     behind each of those choices (buffer count, drop-vs-block, the FPU
     exception mask fix). Only the data source changed: buffers are now
     filled from stdin frames instead of directly from QueueStereo's own
     TVMobjS conversion.

*******************************************************************************}

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, Math, uSDRAudioIPC;

type
  OSStatus = LongInt;
  AudioQueueRef = Pointer;
  AudioFormatID = LongWord;
  AudioFormatFlags = LongWord;

  AudioStreamBasicDescription = record
    mSampleRate: Double;
    mFormatID: AudioFormatID;
    mFormatFlags: AudioFormatFlags;
    mBytesPerPacket: LongWord;
    mFramesPerPacket: LongWord;
    mBytesPerFrame: LongWord;
    mChannelsPerFrame: LongWord;
    mBitsPerChannel: LongWord;
    mReserved: LongWord;
  end;
  PAudioStreamBasicDescription = ^AudioStreamBasicDescription;

  AudioQueueBuffer = record
    mAudioDataBytesCapacity: LongWord;
    mAudioData: Pointer;
    mAudioDataByteSize: LongWord;
    mUserData: Pointer;
    mPacketDescriptionCapacity: LongWord;
    mPacketDescriptions: Pointer;
    mPacketDescriptionCount: LongWord;
  end;
  AudioQueueBufferRef = ^AudioQueueBuffer;

  AudioQueueOutputCallback = procedure(inUserData: Pointer; inAQ: AudioQueueRef;
    inBuffer: AudioQueueBufferRef); cdecl;

const
  kAudioFormatLinearPCM = $6C70636D;             // 'lpcm'
  kAudioFormatFlagIsSignedInteger = 1 shl 2;
  kAudioFormatFlagIsPacked = 1 shl 3;

function AudioQueueNewOutput(inFormat: PAudioStreamBasicDescription; inCallbackProc: AudioQueueOutputCallback;
  inUserData: Pointer; inCallbackRunLoop: Pointer; inCallbackRunLoopMode: Pointer; inFlags: LongWord;
  out outAQ: AudioQueueRef): OSStatus; cdecl; external name 'AudioQueueNewOutput';
function AudioQueueDispose(inAQ: AudioQueueRef; inImmediate: Boolean): OSStatus; cdecl; external name 'AudioQueueDispose';
function AudioQueueAllocateBuffer(inAQ: AudioQueueRef; inBufferByteSize: LongWord;
  out outBuffer: AudioQueueBufferRef): OSStatus; cdecl; external name 'AudioQueueAllocateBuffer';
function AudioQueueEnqueueBuffer(inAQ: AudioQueueRef; inBuffer: AudioQueueBufferRef;
  inNumPacketDescs: LongWord; inPacketDescs: Pointer): OSStatus; cdecl; external name 'AudioQueueEnqueueBuffer';
function AudioQueueStart(inAQ: AudioQueueRef; inStartTime: Pointer): OSStatus; cdecl; external name 'AudioQueueStart';
function AudioQueueStop(inAQ: AudioQueueRef; inImmediate: Boolean): OSStatus; cdecl; external name 'AudioQueueStop';

{$linkframework AudioToolbox}
// The one place in the whole SDR_Radio app allowed to link AudioToolbox -
// see uSDRAudioIPC.pas's header comment for why it must never be linked
// (statically OR dynamically) into the process that also owns the HackRF.

var
  AQ: AudioQueueRef;
  AQBuffers: array of record
    Buf: AudioQueueBufferRef;
    Free: Boolean;
  end;
  NextBuffer: Integer;

procedure AQOutputCallback(inUserData: Pointer; inAQ: AudioQueueRef; inBuffer: AudioQueueBufferRef); cdecl;
var
  Idx: PtrInt;
begin
  Idx := PtrInt(inBuffer^.mUserData);
  AQBuffers[Idx].Free := True;
end;

// Reads exactly Count bytes from stdin into Buf, looping over short pipe
// reads. Returns False on EOF/error before Count bytes were read (the
// normal, expected way this program learns the parent has called
// TWaveOutPlayer.Close / exited).
function ReadExact(var Buf; Count: LongInt): Boolean;
var
  P: PByte;
  Got: LongInt;
begin
  P := PByte(@Buf);
  while Count > 0 do begin
    Got := FileRead(StdInputHandle, P^, Count);
    if Got <= 0 then Exit(False);
    Inc(P, Got);
    Dec(Count, Got);
  end;
  Result := True;
end;

var
  Header: TSDRAudioIPCHeader;
  Fmt: AudioStreamBasicDescription;
  Status: OSStatus;
  i: Integer;
  FrameLen: LongWord;
  Scratch: array of Byte;
  WaitMs: Integer;
begin
  if not ReadExact(Header, SizeOf(Header)) then Halt(1);
  if Header.Magic <> SDRAudioIPCMagic then Halt(2);
  if (Header.MaxSamplesPerChannel = 0) or (Header.BufferCount = 0) then Halt(2);

  // See uWaveOutPlayer.pas's own header comment (GOTCHA) - must happen
  // before the first AudioQueue call in this process.
  SetExceptionMask([exInvalidOp, exOverflow, exUnderflow, exZeroDivide, exPrecision, exDenormalized]);

  FillChar(Fmt, SizeOf(Fmt), 0);
  Fmt.mSampleRate := Header.SampleRateHz;
  Fmt.mFormatID := kAudioFormatLinearPCM;
  Fmt.mFormatFlags := kAudioFormatFlagIsSignedInteger or kAudioFormatFlagIsPacked;
  Fmt.mChannelsPerFrame := 2;
  Fmt.mBitsPerChannel := 16;
  Fmt.mBytesPerFrame := (Fmt.mChannelsPerFrame * Fmt.mBitsPerChannel) div 8;
  Fmt.mFramesPerPacket := 1;
  Fmt.mBytesPerPacket := Fmt.mBytesPerFrame * Fmt.mFramesPerPacket;

  Status := AudioQueueNewOutput(@Fmt, @AQOutputCallback, nil, nil, nil, 0, AQ);
  if Status <> 0 then Halt(3);

  SetLength(AQBuffers, Header.BufferCount);
  for i := 0 to High(AQBuffers) do begin
    Status := AudioQueueAllocateBuffer(AQ, Header.MaxSamplesPerChannel * 4, AQBuffers[i].Buf);
    if Status <> 0 then Halt(3);
    AQBuffers[i].Buf^.mUserData := Pointer(PtrInt(i));
    AQBuffers[i].Free := True;
  end;
  NextBuffer := 0;

  AudioQueueStart(AQ, nil);

  SetLength(Scratch, Header.MaxSamplesPerChannel * 4);
  while ReadExact(FrameLen, SizeOf(FrameLen)) do begin
    if FrameLen = 0 then Continue;
    if FrameLen > LongWord(Length(Scratch)) then FrameLen := LongWord(Length(Scratch));
    if not ReadExact(Scratch[0], FrameLen) then Break;

    // The buffer ring is meant to always be several frames ahead of
    // playback (see uWaveOutPlayer.pas's own "why 16 buffers" comment) -
    // a short bounded wait here only ever matters if the parent has
    // burst far ahead of real time, and never blocks the PARENT (its
    // pipe write already completed once the OS pipe buffer accepted the
    // bytes, well before this loop iteration runs).
    WaitMs := 0;
    while (not AQBuffers[NextBuffer].Free) and (WaitMs < 50) do begin
      Sleep(1);
      Inc(WaitMs);
    end;
    if not AQBuffers[NextBuffer].Free then Continue;   // still busy - drop this frame

    Move(Scratch[0], AQBuffers[NextBuffer].Buf^.mAudioData^, FrameLen);
    AQBuffers[NextBuffer].Buf^.mAudioDataByteSize := FrameLen;
    AQBuffers[NextBuffer].Free := False;
    AudioQueueEnqueueBuffer(AQ, AQBuffers[NextBuffer].Buf, 0, nil);

    NextBuffer := (NextBuffer + 1) mod Length(AQBuffers);
  end;

  AudioQueueStop(AQ, True);
  AudioQueueDispose(AQ, True);
end.
