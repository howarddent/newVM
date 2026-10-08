unit uDABReceiver;

{*******************************************************************************

     TDABReceiver - plays one DAB or DAB+ station from a TSDRRFSource's
     IQ stream: uDABDecoder.pas's TDABDecoder (OFDM, FIC, the station's
     sub-channel of the MSC) feeding uDABAudio.pas's TDABAudioDecoder
     (MP2 or HE-AAC) feeding a TWaveOutPlayer, all on one worker thread -
     the same "consumer points at a sibling TSDRRFSource" component shape,
     and the same reasons for a thread rather than a timer, as
     TFMBroadcastReceiver (uFMReceiver.pas).

     THE SOURCE MUST ALREADY BE STREAMING AT 2.048 Msps, TUNED TO THE
     STATION'S MULTIPLEX - choosing the rate and the block is the host
     form's job, as for TDABScanner. A DAB station can't be tuned in
     software within a wider capture the way FM/AM are: a multiplex is
     1.536 MHz wide and the decoder needs exactly its centre.

     THE STATION is identified by its service ID (SId), not its sub-
     channel: the sub-channel and its protection come from the LIVE FIC
     (FIG 0/2 and 0/1) once the decoder has synchronised, because a
     multiplex can be reconfigured after the station list was scanned.
     Only the SId and the expected block come from the list.

     RETUNING the source (a different block, or the user moving the
     front end) is noticed by its centre frequency changing; the decoder
     chain is then thrown away and rebuilt, since everything in it -
     synchronisation, the time de-interleaver, the superframe queue - is
     specific to the signal it was locked to.

     AUDIO OUTPUT is always 48 kHz stereo, paced by the radio's own sample
     clock rather than by when the codec happens to produce it:
       - Every codec output rate (DAB+ at 32 or 48 kHz, i.e. 16 or 24 kHz
         cores doubled by SBR; MP2 at 48 or 24 kHz) is resampled here to
         48 kHz (TRationalResamplerS, the FM chain's resampler), so the
         sound device is opened once, at the rate PC sound hardware runs
         at, and never reopened when a station's format changes.
       - Decoded audio goes into a FIFO, and each 16384-sample IQ epoch
         (8 ms of signal) releases exactly 8 ms of audio (384 frames)
         from it. The codecs deliver in bursts - four 24 ms frames at once
         out of every 96 ms OFDM frame, or a whole 120 ms DAB+ superframe
         at a time - and TWaveOutPlayer's drift compensation, tuned for
         the FM receiver's steady 20 ms epochs, reads a burst that large
         as the buffer swinging past its dead-band and pads or truncates
         the audio to correct it: heard as a constant garble of small
         splices. Released at a steady cadence, the buffer level only
         moves with real clock drift, which is what the compensation is for.
       - Output starts once PrebufferMs of audio is queued (enough to
         ride out one burst), and whenever the FIFO runs dry - audio
         frames lost to reception errors - silence is released in their
         place, keeping the cadence: a gap, rather than the rest of the
         audio sliding to fill it. After a second of nothing it waits for
         the pre-buffer again.

     STATUS for the UI (Status) is a snapshot copied under a lock once
     per decoded frame, so the GUI thread can poll it at any time without
     touching the worker's objects.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, Math, newVMSingle, newVMComplexSingle,
  uSDRRFSource, uWaveOutPlayer, uDSPBlocks, uDABDecoder, uDABAudio;

type
  TDABReceiverStatus = record
    State: string;              // what the receiver is doing, in words
    Synced: Boolean;
    Playing: Boolean;
    FormatText: string;         // e.g. 'HE-AAC v2, 32 kHz, stereo'
    BitrateKbps: Integer;
    SNRdB, FICOkPercent: Double;
    ChannelBER: Double;         // MSC, before error correction
    AUsOk, AUsBad: Int64;       // DAB+ only
    RSFailed: Int64;            // DAB+ only: uncorrectable RS codewords
    AudioUnderruns: Integer;
    AudioSplices: Integer;      // player drift-compensation corrections
    BufferedMs: Integer;        // decoded audio waiting in the output FIFO
    LastError: string;
  end;

  TDABReceiver = class;

  TDABReceiverThread = class(TThread)
  private
    FOwner: TDABReceiver;
    FDec: TDABDecoder;
    FAudio: TDABAudioDecoder;
    FPlayer: TWaveOutPlayer;
    // 48 kHz output stage - see AUDIO OUTPUT in the header.
    FResampRate: Integer;
    FResampL, FResampR: TRationalResamplerS;
    FFifoL, FFifoR: array of Single;
    FFifoHead, FFifoCount: Integer;
    FOutputStarted: Boolean;
    FDueFrames: Double;
    FDryFrames: Integer;
    FSId: LongWord;
    FTunedHz: QWord;
    FState: string;
    procedure ResetChain;
    procedure DecoderLogicalFrame(Sender: TObject; const Data: TBytes);
    procedure AudioOut(Sender: TObject; const L, R: TVMobjS; SampleRateHz: Integer);
    procedure SelectStationIfKnown;
    procedure PublishStatus;
    procedure FifoPush(const L, R: TVMobjS);
    procedure ReleaseAudio(IQSamples: Integer);
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDABReceiver);
    destructor Destroy; override;
  end;

  { TDABReceiver }
  TDABReceiver = class(TComponent)
  private
    FSource: TSDRRFSource;
    FThread: TDABReceiverThread;
    FServiceId: LongWord;
    FVolume: Single;
    FLock: TCriticalSection;
    FStatus: TDABReceiverStatus;
    FServiceChanged: Boolean;
    procedure SetSource(AValue: TSDRRFSource);
    function GetActive: Boolean;
    procedure SetActive(AValue: Boolean);
    procedure SetServiceId(AValue: LongWord);
    function GetStatus: TDABReceiverStatus;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Status: TDABReceiverStatus read GetStatus;
    // The station to play. May be changed while Active - the chain is
    // rebuilt for it (the source must be retuned by the caller if it is
    // on another multiplex).
    property ServiceId: LongWord read FServiceId write SetServiceId;
  published
    property Source: TSDRRFSource read FSource write SetSource;
    // Starting needs Source streaming; stopping joins the thread and
    // closes the sound device.
    property Active: Boolean read GetActive write SetActive;
    property Volume: Single read FVolume write FVolume;   // 0..1, applied live
  end;

procedure Register;

implementation

const
  EpochSamples = 16384;
  OutputRateHz = 48000;
  MaxAudioSamples = 4096;     // per QueueStereo call; ReleaseAudio sends ~384
  PrebufferMs = 200;          // more than one DAB+ superframe (120 ms) or OFDM frame (96 ms)
  FifoMaxMs = 1000;           // beyond this the oldest audio is dropped
  DryResetMs = 1000;          // this long with nothing decoded: wait to re-buffer
  ResampleTransitionHz = 2000;

{ TDABReceiverThread }

constructor TDABReceiverThread.Create(AOwner: TDABReceiver);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  FPlayer := TWaveOutPlayer.Create;
  SetLength(FFifoL, OutputRateHz * FifoMaxMs div 1000);
  SetLength(FFifoR, Length(FFifoL));
  inherited Create(False);
end;

destructor TDABReceiverThread.Destroy;
begin
  FreeAndNil(FResampL);
  FreeAndNil(FResampR);
  FreeAndNil(FAudio);
  FreeAndNil(FDec);
  if Assigned(FPlayer) then begin
    FPlayer.Close;
    FPlayer.Free;
  end;
  inherited Destroy;
end;

procedure TDABReceiverThread.ResetChain;
begin
  FreeAndNil(FAudio);
  FreeAndNil(FDec);
  FDec := TDABDecoder.Create;
  FDec.OnLogicalFrame := @DecoderLogicalFrame;
  FTunedHz := FOwner.FSource.CenterFreqHz;
  FOwner.FLock.Enter;
  try
    FSId := FOwner.FServiceId;
    FOwner.FServiceChanged := False;
  finally
    FOwner.FLock.Leave;
  end;
  FState := 'Synchronising';
  // Anything queued belongs to the previous station or multiplex.
  FFifoHead := 0;
  FFifoCount := 0;
  FOutputStarted := False;
  FDueFrames := 0;
end;

// Once the FIC has told the decoder which sub-channel carries the
// station, and FIG 0/1 has described that sub-channel, start its MSC and
// an audio decoder of the right kind.
procedure TDABReceiverThread.SelectStationIfKnown;
var
  i: Integer;
  Sc: TDABSubChannel;
begin
  if FDec.SelectedSubChannel >= 0 then Exit;
  if not FDec.Synced then Exit;
  for i := 0 to High(FDec.Services) do
    if FDec.Services[i].SId = FSId then begin
      if FDec.Services[i].SubChId < 0 then Exit;
      Sc := FDec.SubChannels[FDec.Services[i].SubChId];
      if not Sc.Valid or (Sc.BitrateKbps <= 0) then Exit;
      FDec.SelectSubChannel(FDec.Services[i].SubChId);
      FAudio := TDABAudioDecoder.Create(FDec.Services[i].AudioType = 'DAB+', Sc.BitrateKbps);
      FAudio.OnAudio := @AudioOut;
      FState := 'Waiting for audio';
      Exit;
    end;
  if FDec.FramesDecoded > 40 then FState := 'Station not found on this multiplex'
  else FState := 'Reading the multiplex';
end;

procedure TDABReceiverThread.DecoderLogicalFrame(Sender: TObject; const Data: TBytes);
begin
  if Assigned(FAudio) then FAudio.FeedLogicalFrame(Data);
end;

procedure TDABReceiverThread.AudioOut(Sender: TObject; const L, R: TVMobjS; SampleRateHz: Integer);
begin
  if SampleRateHz <= 0 then Exit;
  if SampleRateHz = OutputRateHz then begin
    FifoPush(L, R);
    Exit;
  end;
  if SampleRateHz <> FResampRate then begin
    FreeAndNil(FResampL);
    FreeAndNil(FResampR);
    FResampL := TRationalResamplerS.Create(SampleRateHz, OutputRateHz, ResampleTransitionHz);
    FResampR := TRationalResamplerS.Create(SampleRateHz, OutputRateHz, ResampleTransitionHz);
    FResampRate := SampleRateHz;
  end;
  FifoPush(FResampL.Process(L), FResampR.Process(R));
end;

procedure TDABReceiverThread.FifoPush(const L, R: TVMobjS);
var
  N, i, Cap, Pos, Drop: Integer;
begin
  N := L.Rows * L.Cols;
  Cap := Length(FFifoL);
  if (N <= 0) or (N > Cap) then Exit;
  // Too far behind (the player stalled, or decoding caught up in a rush
  // after a hold-up): drop the oldest rather than let latency grow.
  if FFifoCount + N > Cap then begin
    Drop := FFifoCount + N - Cap;
    FFifoHead := (FFifoHead + Drop) mod Cap;
    Dec(FFifoCount, Drop);
  end;
  Pos := (FFifoHead + FFifoCount) mod Cap;
  for i := 0 to N - 1 do begin
    FFifoL[Pos] := L[0, i];
    FFifoR[Pos] := R[0, i];
    Inc(Pos);
    if Pos = Cap then Pos := 0;
  end;
  Inc(FFifoCount, N);
  FDryFrames := 0;
  FState := 'Playing';
end;

// Releases the audio due for IQSamples of received signal - see AUDIO
// OUTPUT in the header.
procedure TDABReceiverThread.ReleaseAudio(IQSamples: Integer);
var
  N, Take, i, Cap: Integer;
  L, R: TVMobjS;
  V: Single;
begin
  if not FOutputStarted then begin
    FDueFrames := 0;
    if FFifoCount < OutputRateHz * PrebufferMs div 1000 then Exit;
    FOutputStarted := True;
    if not FPlayer.IsOpen then FPlayer.Open(OutputRateHz, MaxAudioSamples);
  end;
  FDueFrames := FDueFrames + IQSamples * (OutputRateHz / DABSampleRateHz);
  N := Trunc(FDueFrames);
  if N <= 0 then Exit;
  FDueFrames := FDueFrames - N;
  N := Min(N, MaxAudioSamples - 256);

  Take := Min(N, FFifoCount);
  if Take < N then begin
    Inc(FDryFrames, N - Take);
    if FDryFrames >= OutputRateHz * DryResetMs div 1000 then begin
      FOutputStarted := False;   // nothing for a while: re-buffer before resuming
      Exit;
    end;
  end;

  V := FOwner.FVolume;
  L := TVMobjS.Create(1, N);   // zero-filled: the silence after Take
  R := TVMobjS.Create(1, N);
  Cap := Length(FFifoL);
  for i := 0 to Take - 1 do begin
    L[0, i] := FFifoL[FFifoHead] * V;
    R[0, i] := FFifoR[FFifoHead] * V;
    Inc(FFifoHead);
    if FFifoHead = Cap then FFifoHead := 0;
  end;
  Dec(FFifoCount, Take);
  FPlayer.QueueStereo(L, R);
end;

procedure TDABReceiverThread.PublishStatus;
var
  S: TDABReceiverStatus;
begin
  S := Default(TDABReceiverStatus);
  S.State := FState;
  S.SNRdB := NaN; S.ChannelBER := NaN; S.FICOkPercent := NaN;
  if Assigned(FDec) then begin
    S.Synced := FDec.Synced;
    S.SNRdB := FDec.SNRdB;
    S.FICOkPercent := FDec.FICOkPercent;
    S.ChannelBER := FDec.MSCChannelBER;
    if FDec.SelectedSubChannel >= 0 then
      S.BitrateKbps := FDec.SubChannels[FDec.SelectedSubChannel].BitrateKbps;
  end;
  if Assigned(FAudio) then begin
    S.FormatText := FAudio.FormatText;
    S.AUsOk := FAudio.AUsOk;
    S.AUsBad := FAudio.AUsBad;
    S.RSFailed := FAudio.RSFailedCodewords;
    S.LastError := FAudio.LastError;
    S.Playing := FState = 'Playing';
    // DAB+ checks every audio frame, so it can say when nothing is getting
    // through: superframes locked but every AU failing its CRC is a signal
    // too weak for this station's error protection, not a fault.
    if (FAudio.AUsOk = 0) and (FAudio.AUsBad >= 12) then
      S.State := 'Signal too weak to decode this station';
  end;
  S.AudioUnderruns := FPlayer.UnderrunCount;
  S.AudioSplices := FPlayer.CompensationCount;
  S.BufferedMs := FFifoCount * 1000 div OutputRateHz;
  FOwner.FLock.Enter;
  try
    FOwner.FStatus := S;
  finally
    FOwner.FLock.Leave;
  end;
end;

procedure TDABReceiverThread.Execute;
var
  Cursor: TSDRStreamCursor;
  IQ: TVMobjC;
  Frames: Integer;
  Changed: Boolean;
begin
  try
    ResetChain;
    Cursor := FOwner.FSource.NewStreamCursor;
    PublishStatus;
    while not Terminated do begin
      if not FOwner.FSource.IsStreaming then begin
        FState := 'The radio is not streaming';
        PublishStatus;
        Sleep(100);
        Continue;
      end;
      FOwner.FLock.Enter;
      try
        Changed := FOwner.FServiceChanged;
      finally
        FOwner.FLock.Leave;
      end;
      if Changed or (FOwner.FSource.CenterFreqHz <> FTunedHz) then begin
        ResetChain;
        Cursor := FOwner.FSource.NewStreamCursor;
      end;
      if not FOwner.FSource.TryReadEpoch(EpochSamples, Cursor, IQ) then begin
        Sleep(5);
        Continue;
      end;
      Frames := FDec.FramesDecoded;
      FDec.AddSamples(IQ);
      FDec.Process;
      ReleaseAudio(EpochSamples);
      if FDec.FramesDecoded <> Frames then begin
        SelectStationIfKnown;
        PublishStatus;
      end else if not FDec.Synced and (FState <> 'Synchronising') then begin
        FState := 'Synchronising';
        PublishStatus;
      end;
    end;
  except
    on E: Exception do begin
      FState := 'Stopped by an error';
      FOwner.FLock.Enter;
      try
        FOwner.FStatus.State := FState;
        FOwner.FStatus.LastError := E.ClassName + ': ' + E.Message;
      finally
        FOwner.FLock.Leave;
      end;
    end;
  end;
end;

{ TDABReceiver }

constructor TDABReceiver.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FLock := TCriticalSection.Create;
  FVolume := 0.7;
  FStatus.State := 'Stopped';
end;

destructor TDABReceiver.Destroy;
begin
  SetActive(False);
  FLock.Free;
  inherited Destroy;
end;

procedure TDABReceiver.SetSource(AValue: TSDRRFSource);
begin
  if FSource = AValue then Exit;
  SetActive(False);
  if Assigned(FSource) then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if Assigned(FSource) then FSource.FreeNotification(Self);
end;

procedure TDABReceiver.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then begin
    SetActive(False);
    FSource := nil;
  end;
end;

function TDABReceiver.GetActive: Boolean;
begin
  Result := Assigned(FThread);
end;

procedure TDABReceiver.SetActive(AValue: Boolean);
begin
  if AValue = GetActive then Exit;
  if AValue then begin
    if not (Assigned(FSource) and FSource.IsStreaming) then Exit;
    FThread := TDABReceiverThread.Create(Self);
  end else begin
    FThread.Terminate;
    FThread.WaitFor;   // no Synchronize in the worker, so a plain join is safe
    FreeAndNil(FThread);
    FLock.Enter;
    try
      FStatus := Default(TDABReceiverStatus);
      FStatus.State := 'Stopped';
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TDABReceiver.SetServiceId(AValue: LongWord);
begin
  FLock.Enter;
  try
    if FServiceId <> AValue then begin
      FServiceId := AValue;
      FServiceChanged := True;
    end;
  finally
    FLock.Leave;
  end;
end;

function TDABReceiver.GetStatus: TDABReceiverStatus;
begin
  FLock.Enter;
  try
    Result := FStatus;
  finally
    FLock.Leave;
  end;
end;

procedure Register;
begin
  RegisterComponents('SDR', [TDABReceiver]);
end;

end.
