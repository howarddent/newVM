unit uDABScanner;

{*******************************************************************************

     TDABScanner - steps a TSDRRFSource through the Band III DAB blocks
     used in the UK (5A..13F), and on each one runs a TDABFICDecoder
     (uDABDecoder.pas) on the live IQ stream long enough to say whether
     there is an ensemble there, what it is called, which services it
     carries, and how well it is being received. A non-visual component
     with a Source property, the same "consumer points at a sibling
     TSDRRFSource" shape as TFMBroadcastReceiver.

     THE SOURCE MUST ALREADY BE STREAMING AT 2.048 Msps. Choosing and
     starting the stream is the host form's business (it owns the rate
     combo, the gain controls and the Start button); Start just refuses
     with a message if the rate is wrong, rather than reaching past the
     form to restart the hardware itself.

     RETUNING goes through Source.RequestFrequencyHz, called on the GUI
     thread via Synchronize - that call is documented as a GUI-thread one,
     and its completion event (OnFrequencyChanged) is what keeps the host
     form's frequency display in step, so the scan is visible on the main
     window as it happens. The worker then waits for Source.CenterFreqHz
     to report the new frequency, lets the front end settle, and only
     then takes a fresh stream cursor, so no sample from the previous
     block ever reaches the decoder.

     DWELL per block, measured in samples actually consumed rather than
     wall-clock time so a busy machine can't cut a block short:
       - no lock within NoSignalSecs: nothing here, move on;
       - locked but no CRC-clean FIB within NoFICSecs: a signal with a
         null-like dip but nothing decodable, move on;
       - FIC decoding: stay until the ensemble label and every listed
         service's label are in and nothing has changed for SettleFrames
         frames, or MaxDwellSecs, whichever is first. Labels are
         repeated on a cycle of a second or so, so a strong multiplex
         completes in 1-3 s; a marginal one uses the full dwell and is
         reported with whatever arrived.

     The tuner's frequency error measured on each ensemble found is kept
     (as ppm) and handed to the next block's decoder as a hint, which
     narrows its whole-carrier search - helpful on weak multiplexes, where
     the unconstrained search can settle on a wrong shift.

     Events are delivered on the GUI thread via Synchronize, so Stop must
     not simply block on the thread: it pumps CheckSynchronize while
     waiting, otherwise a worker waiting to deliver an event and a GUI
     waiting for the worker would deadlock.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, newVMComplexSingle, uSDRRFSource, uDABDecoder;

type
  TDABChannel = record
    Name: string;
    FreqHz: QWord;
  end;

  TDABScanResult = record
    Channel: TDABChannel;
    Found: Boolean;            // at least one CRC-clean FIB
    Locked: Boolean;           // OFDM sync achieved (Found implies this)
    EId: Integer;
    EnsembleLabel: string;
    Services: TDABServiceArray;
    SNRdB, MERdB, FICOkPercent, FreqOffsetHz: Double;
    DwellSecs: Double;
  end;

  TDABChannelStartEvent = procedure(Sender: TObject; Index, Count: Integer;
    const Channel: TDABChannel) of object;
  TDABChannelResultEvent = procedure(Sender: TObject; const R: TDABScanResult) of object;
  TDABScanFinishedEvent = procedure(Sender: TObject; Aborted: Boolean; const Msg: string) of object;

  TDABScanner = class;

  TDABScanThread = class(TThread)
  private
    FOwner: TDABScanner;
    // hand-over fields for the Synchronized calls
    FIndex: Integer;
    FChannel: TDABChannel;
    FResult: TDABScanResult;
    FMsg: string;
    FAborted: Boolean;
    FRetuneHz: QWord;
    procedure DoRetune;
    procedure DoChannelStart;
    procedure DoChannelResult;
    procedure DoFinished;
    function ScanChannel(const Ch: TDABChannel; HintPpm: Double; HavePpm: Boolean;
      out R: TDABScanResult): Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TDABScanner);
  end;

  { TDABScanner }
  TDABScanner = class(TComponent)
  private
    FSource: TSDRRFSource;
    FThread: TDABScanThread;
    FChannels: array of TDABChannel;
    FResults: array of TDABScanResult;
    FOnChannelStart: TDABChannelStartEvent;
    FOnChannelResult: TDABChannelResultEvent;
    FOnFinished: TDABScanFinishedEvent;
    FMaxDwellSecs: Double;
    FReturnFreqHz: QWord;
    procedure SetSource(AValue: TSDRRFSource);
    function GetScanning: Boolean;
    function GetResultCount: Integer;
    function GetResult(Index: Integer): TDABScanResult;
    function GetChannelCount: Integer;
    function GetChannel(Index: Integer): TDABChannel;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // Scans every block in Channels (the UK Band III list by default).
    // Returns False, with Msg saying why, if the source isn't ready.
    function Start(out Msg: string): Boolean;
    // Restricts the next scan to a subset, e.g. a single block.
    procedure SetChannels(const Names: array of string);
    procedure Stop;
    property Scanning: Boolean read GetScanning;
    property ResultCount: Integer read GetResultCount;
    property Results[Index: Integer]: TDABScanResult read GetResult;
    property ChannelCount: Integer read GetChannelCount;
    property Channels[Index: Integer]: TDABChannel read GetChannel;
  published
    property Source: TSDRRFSource read FSource write SetSource;
    property MaxDwellSecs: Double read FMaxDwellSecs write FMaxDwellSecs;
    property OnChannelStart: TDABChannelStartEvent read FOnChannelStart write FOnChannelStart;
    property OnChannelResult: TDABChannelResultEvent read FOnChannelResult write FOnChannelResult;
    property OnFinished: TDABScanFinishedEvent read FOnFinished write FOnFinished;
  end;

const
  // ETSI EN 300 401 table: Band III block centre frequencies. The UK uses
  // 5A..13F (national, local and small-scale multiplexes alike).
  UKDABChannelCount = 38;
  UKDABChannels: array[0..UKDABChannelCount - 1] of TDABChannel = (
    (Name: '5A';  FreqHz: 174928000), (Name: '5B';  FreqHz: 176640000),
    (Name: '5C';  FreqHz: 178352000), (Name: '5D';  FreqHz: 180064000),
    (Name: '6A';  FreqHz: 181936000), (Name: '6B';  FreqHz: 183648000),
    (Name: '6C';  FreqHz: 185360000), (Name: '6D';  FreqHz: 187072000),
    (Name: '7A';  FreqHz: 188928000), (Name: '7B';  FreqHz: 190640000),
    (Name: '7C';  FreqHz: 192352000), (Name: '7D';  FreqHz: 194064000),
    (Name: '8A';  FreqHz: 195936000), (Name: '8B';  FreqHz: 197648000),
    (Name: '8C';  FreqHz: 199360000), (Name: '8D';  FreqHz: 201072000),
    (Name: '9A';  FreqHz: 202928000), (Name: '9B';  FreqHz: 204640000),
    (Name: '9C';  FreqHz: 206352000), (Name: '9D';  FreqHz: 208064000),
    (Name: '10A'; FreqHz: 209936000), (Name: '10B'; FreqHz: 211648000),
    (Name: '10C'; FreqHz: 213360000), (Name: '10D'; FreqHz: 215072000),
    (Name: '11A'; FreqHz: 216928000), (Name: '11B'; FreqHz: 218640000),
    (Name: '11C'; FreqHz: 220352000), (Name: '11D'; FreqHz: 222064000),
    (Name: '12A'; FreqHz: 223936000), (Name: '12B'; FreqHz: 225648000),
    (Name: '12C'; FreqHz: 227360000), (Name: '12D'; FreqHz: 229072000),
    (Name: '13A'; FreqHz: 230784000), (Name: '13B'; FreqHz: 232496000),
    (Name: '13C'; FreqHz: 234208000), (Name: '13D'; FreqHz: 235776000),
    (Name: '13E'; FreqHz: 237488000), (Name: '13F'; FreqHz: 239200000));

procedure Register;

implementation

const
  EpochSamples = 16384;
  SettleMs = 120;            // after the retune is confirmed, before sampling
  RetuneTimeoutMs = 3000;
  NoSignalSecs = 0.8;        // no OFDM lock by now: nothing on this block
  NoFICSecs = 1.5;           // locked but not one clean FIB by now: give up
  SettleFrames = 12;         // ~1.2 s with nothing new in the FIC

{ TDABScanThread }

constructor TDABScanThread.Create(AOwner: TDABScanner);
begin
  FOwner := AOwner;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TDABScanThread.DoRetune;
begin
  FOwner.FSource.RequestFrequencyHz(FRetuneHz);
end;

procedure TDABScanThread.DoChannelStart;
begin
  if Assigned(FOwner.FOnChannelStart) then
    FOwner.FOnChannelStart(FOwner, FIndex, Length(FOwner.FChannels), FChannel);
end;

procedure TDABScanThread.DoChannelResult;
begin
  SetLength(FOwner.FResults, Length(FOwner.FResults) + 1);
  FOwner.FResults[High(FOwner.FResults)] := FResult;
  if Assigned(FOwner.FOnChannelResult) then
    FOwner.FOnChannelResult(FOwner, FResult);
end;

procedure TDABScanThread.DoFinished;
begin
  if Assigned(FOwner.FOnFinished) then
    FOwner.FOnFinished(FOwner, FAborted, FMsg);
end;

function TDABScanThread.ScanChannel(const Ch: TDABChannel; HintPpm: Double;
  HavePpm: Boolean; out R: TDABScanResult): Boolean;
var
  Dec: TDABFICDecoder;
  Cursor: TSDRStreamCursor;
  IQ: TVMobjC;
  Consumed: Int64;
  Secs: Double;
  t0: QWord;
  i: Integer;
  AllLabelled: Boolean;
begin
  Result := False;
  R := Default(TDABScanResult);
  R.Channel := Ch;
  R.EId := -1;
  R.SNRdB := NaN; R.MERdB := NaN; R.FreqOffsetHz := NaN;

  FRetuneHz := Ch.FreqHz;
  Synchronize(@DoRetune);
  t0 := GetTickCount64;
  while FOwner.FSource.CenterFreqHz <> Ch.FreqHz do begin
    if Terminated or not FOwner.FSource.IsStreaming then Exit;
    if GetTickCount64 - t0 > RetuneTimeoutMs then begin
      FMsg := 'retune to ' + Ch.Name + ' timed out';
      Exit;
    end;
    Sleep(10);
  end;
  Sleep(SettleMs);
  Cursor := FOwner.FSource.NewStreamCursor;

  Dec := TDABFICDecoder.Create;
  try
    if HavePpm then Dec.SetFrequencyHint(HintPpm * 1e-6 * Ch.FreqHz);
    Consumed := 0;
    repeat
      if Terminated then Exit;
      if not FOwner.FSource.IsStreaming then begin
        FMsg := 'the radio stopped streaming';
        Exit;
      end;
      if not FOwner.FSource.TryReadEpoch(EpochSamples, Cursor, IQ) then begin
        Sleep(5);
        Continue;
      end;
      Dec.AddSamples(IQ);
      Inc(Consumed, EpochSamples);
      Dec.Process;
      Secs := Consumed / DABSampleRateHz;

      if (Dec.FramesDecoded = 0) and (Secs >= NoSignalSecs) then Break;
      if (Dec.FibOk = 0) and (Secs >= NoFICSecs) then Break;
      if Dec.FibOk > 0 then begin
        AllLabelled := (Dec.EnsembleLabel <> '') and (Length(Dec.Services) > 0);
        for i := 0 to High(Dec.Services) do
          if Dec.Services[i].ServiceLabel = '' then AllLabelled := False;
        if AllLabelled and (Dec.FramesDecoded - Dec.LastChangeFrame >= SettleFrames) then Break;
      end;
    until Secs >= FOwner.FMaxDwellSecs;

    R.Locked := Dec.FramesDecoded > 0;
    R.Found := Dec.FibOk > 0;
    R.EId := Dec.EId;
    R.EnsembleLabel := Dec.EnsembleLabel;
    R.Services := Copy(Dec.Services);
    if R.Locked then begin
      R.SNRdB := Dec.SNRdB;
      R.MERdB := Dec.MERdB;
      R.FreqOffsetHz := Dec.FrequencyOffsetHz;
    end;
    R.FICOkPercent := Dec.FICOkPercent;
    R.DwellSecs := Secs;
    Result := True;
  finally
    Dec.Free;
  end;
end;

procedure TDABScanThread.Execute;
var
  i: Integer;
  Ppm: Double;
  HavePpm: Boolean;
  R: TDABScanResult;
begin
  FAborted := True;
  FMsg := '';
  HavePpm := False;
  Ppm := 0;
  try
    for i := 0 to High(FOwner.FChannels) do begin
      if Terminated then Break;
      FIndex := i;
      FChannel := FOwner.FChannels[i];
      Synchronize(@DoChannelStart);
      if not ScanChannel(FChannel, Ppm, HavePpm, R) then Break;
      if R.Found then begin
        Ppm := R.FreqOffsetHz / R.Channel.FreqHz * 1e6;
        HavePpm := True;
      end;
      FResult := R;
      Synchronize(@DoChannelResult);
      if i = High(FOwner.FChannels) then FAborted := False;
    end;
  except
    on E: Exception do FMsg := E.ClassName + ': ' + E.Message;
  end;
  if Terminated and (FMsg = '') then FMsg := 'stopped';
  if FOwner.FSource.IsStreaming then begin
    FRetuneHz := FOwner.FReturnFreqHz;
    Synchronize(@DoRetune);
  end;
  Synchronize(@DoFinished);
end;

{ TDABScanner }

constructor TDABScanner.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMaxDwellSecs := 6.0;
  SetChannels([]);
end;

destructor TDABScanner.Destroy;
begin
  Stop;
  inherited Destroy;
end;

procedure TDABScanner.SetChannels(const Names: array of string);
var
  i, j: Integer;
begin
  SetLength(FChannels, 0);
  for i := 0 to UKDABChannelCount - 1 do begin
    if Length(Names) > 0 then begin
      j := 0;
      while (j <= High(Names)) and not SameText(Names[j], UKDABChannels[i].Name) do Inc(j);
      if j > High(Names) then Continue;
    end;
    SetLength(FChannels, Length(FChannels) + 1);
    FChannels[High(FChannels)] := UKDABChannels[i];
  end;
end;

procedure TDABScanner.SetSource(AValue: TSDRRFSource);
begin
  if FSource = AValue then Exit;
  Stop;
  if Assigned(FSource) then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if Assigned(FSource) then FSource.FreeNotification(Self);
end;

procedure TDABScanner.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then begin
    Stop;
    FSource := nil;
  end;
end;

function TDABScanner.Start(out Msg: string): Boolean;
begin
  Result := False;
  Msg := '';
  if Scanning then begin Msg := 'already scanning'; Exit; end;
  if not Assigned(FSource) then begin Msg := 'no radio source'; Exit; end;
  if not FSource.IsStreaming then begin Msg := 'the radio is not streaming'; Exit; end;
  if Abs(FSource.SampleRateHz - DABSampleRateHz) > 1 then begin
    Msg := Format('DAB needs a 2.048 Msps stream (currently %.3f Msps)', [FSource.SampleRateHz / 1e6]);
    Exit;
  end;
  if Length(FChannels) = 0 then begin Msg := 'no channels to scan'; Exit; end;
  if Assigned(FThread) then FreeAndNil(FThread);   // a finished previous scan
  SetLength(FResults, 0);
  FReturnFreqHz := FSource.CenterFreqHz;
  FThread := TDABScanThread.Create(Self);
  Result := True;
end;

procedure TDABScanner.Stop;
begin
  if not Assigned(FThread) then Exit;
  FThread.Terminate;
  // See this unit's header: the worker may be waiting in Synchronize.
  while not FThread.Finished do
    CheckSynchronize(10);
  FreeAndNil(FThread);
end;

function TDABScanner.GetScanning: Boolean;
begin
  Result := Assigned(FThread) and not FThread.Finished;
end;

function TDABScanner.GetResultCount: Integer;
begin
  Result := Length(FResults);
end;

function TDABScanner.GetResult(Index: Integer): TDABScanResult;
begin
  Result := FResults[Index];
end;

function TDABScanner.GetChannelCount: Integer;
begin
  Result := Length(FChannels);
end;

function TDABScanner.GetChannel(Index: Integer): TDABChannel;
begin
  Result := FChannels[Index];
end;

procedure Register;
begin
  RegisterComponents('SDR', [TDABScanner]);
end;

end.
