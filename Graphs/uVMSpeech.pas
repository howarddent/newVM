unit uVMSpeech;

{*******************************************************************************

     TVMSpeech - a text-to-speech component for Lazarus, Windows SAPI 5
     behind it, with the synthesised waveform available as a newVM TVMobj.

     WHAT IT DOES

       Speak(Text)        says Text through the default audio device, from
                          the thread it's called on (blocking) or in the
                          background (Async := True), with Stop to cut it off.
       Synthesize(Text)   renders Text to an in-memory 16-bit mono WAV via
                          SAPI's SpMemoryStream instead of the speakers, then
                          decodes that into a (1, N) TVMobj of samples in
                          [-1, 1] - Waveform - with SampleRate set from the
                          stream's format. Nothing is heard. This is the
                          bridge to the rest of newVM: plot it on a
                          TVMPlot2D, FFT it, filter it, whatever.
       Voices             the installed voices' names (a TStringList);
                          Voice selects one by index, Rate (-10..10) and
                          Volume (0..100) are SAPI's own ranges.
       SaveToWav(File)    writes the last Synthesize's audio as a WAV file.

     HOW SAPI IS DRIVEN

     Late-bound COM through IDispatch (ComObj's CreateOleObject and
     Variant dispatch), not an imported type library: the automation
     objects SAPI.SpVoice, SAPI.SpMemoryStream and SAPI.SpAudioFormat
     expose everything needed as dispatch properties and methods, and
     late binding keeps the unit free of a 100 KB sapi_tlb.pas and of
     any dependence on the type library being registered. The one
     non-obvious step is capturing audio: SpVoice.AudioOutputStream is
     set to an SpMemoryStream whose Format has been set to 16 kHz 16-bit
     mono (SAPI format code 22, SAFT16kHz16BitMono), Speak is called
     with the synchronous flag, and the stream's GetData returns the
     rendered PCM as a Variant byte array - raw samples, no WAV header,
     since SpMemoryStream holds bare data and the format lives in its
     Format object. AudioOutputStream is then put back to the default
     device so a later Speak is audible again. SAPI only renders at the
     requested format if the voice can, and the Windows desktop voices
     (David, Zira) in fact come back at 22050 Hz whatever is asked for -
     which is why the actual rate is read back from the stream's Format
     after rendering rather than assumed, and why SampleRate is a
     property rather than a constant.

     The Variant byte array comes back through VarArrayLock as raw
     SmallInt little-endian samples, converted to Double / 32768 into the
     TVMobj by a plain loop - there's nothing BLAS-shaped about a type
     conversion, and newVM's own Create(Values) wants a TVector.

     Speak with Async uses SAPI's own asynchronous flag (SVSFlagsAsync =
     1), so no thread is created here; Stop issues Speak('') with the
     purge flag (SVSFPurgeBeforeSpeak = 2), SAPI's documented way to
     cancel. Speaking and the component are both single-instance by
     nature - SpVoice is created once in the constructor and freed by
     releasing the Variant in the destructor.

     COM is initialised per thread by ComObj's own initialization
     (CoInitialize on the main thread), which is enough for an LCL
     application. The unit compiles only for Windows; on other targets
     everything is stubbed to raise, so a cross-platform project still
     builds (see the IFDEF WINDOWS blocks) - a macOS/Linux back end
     would go behind the same interface.

     PROSODY - THE STYLE PRESETS

     SAPI 5 parses XML in the text when Speak is given the SVSFIsXML
     flag (8). It understands both W3C SSML and its own older tag set,
     and for the desktop voices the two are NOT equally effective - measured
     here on David by rendering a sentence each way and pitch-tracking
     the result (autocorrelation over the voiced frames):

       plain                        98 Hz
       SSML <prosody pitch="-30%">  85 Hz     - a fraction of what was asked
       SSML <prosody pitch="x-low"> 89 Hz
       SAPI <pitch absmiddle="-5">  86 Hz
       SAPI <pitch absmiddle="-10"> 78 Hz     - the full range, -10 .. +10
       SAPI <pitch absmiddle="+10"> 118 Hz

     so the wrapper uses SAPI's native tags for pitch (<pitch absmiddle>,
     -10 .. 10, roughly semitone-ish steps) and rate (<rate absspeed>,
     -10 .. 10, the same scale as the Rate property), <volume level>
     (0 .. 100) and <silence msec> for pauses - all honoured in full.
     Style wraps whatever text is passed to Speak/Synthesize in that
     envelope before SAPI sees it (WrapSSML), and inserts silences at
     sentence and clause punctuation, with these presets:

       ssPlain      no wrapping at all - the text goes to SAPI as typed
       ssNewsreader rate -1, pitch 0, 250 ms at full stops, 120 ms at
                    commas - the measured, clause-by-clause read
       ssCalm       rate -2, pitch -3, volume 80, 450/200 ms silences
       ssHAL        rate -4, pitch -8, volume 70, 800 ms at full stops
                    and 350 ms at commas, and every sentence's final
                    clause nested a further 2 pitch steps down, the
                    gentle fall of an unhurried statement. Douglas Rain's
                    reading in 2001: slow, soft, low, almost without
                    stress - about 72 Hz against David's natural 98.

     The custom escape hatch: with Style = ssCustom the ProsodyRate/
     ProsodyPitch/ProsodyVolume/BreakSentenceMs/BreakClauseMs properties
     are used as given, so a caller can tune its own: rate and pitch on
     SAPI's -10 .. 10 scales, volume 0 .. 100 (100 = unchanged).

     What this can and cannot do: prosody tags change the DELIVERY -
     tempo, pitch level, pauses, loudness - and that is most of what
     makes a voice sound calm or hurried. They do not change the voice's
     timbre: David at -14 % pitch is still David, slower and lower. A
     deeper, smoother TIMBRE - formant shifting, a narrower pitch band
     enforced by pitch-tracking rather than by SAPI's own contour - is
     the signal-processing stage the Waveform property exists for, and
     is meant to follow this as a second step.

     Text is XML-escaped before wrapping (an '&' or '<' in a headline
     would otherwise break the parse), and SAPI gets the whole SSML
     document as one Speak call, so timing and breaks are rendered by
     the engine, not simulated here.

     This is a non-visual TComponent, not a control: drop it on a form or
     create it in code, as the demos/Speech demo does.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LResources,
  {$IFDEF WINDOWS} ComObj, Variants, ActiveX, {$ENDIF}
  newVM;

type
  EVMSpeech = class(Exception);

  TVMSpeechStyle = (ssPlain, ssNewsreader, ssCalm, ssHAL, ssCustom);

  { TVMSpeech }

  TVMSpeech = class(TComponent)
  private
    {$IFDEF WINDOWS}
    FVoice: Variant;          // SAPI.SpVoice
    FDefaultOutput: Variant;  // its original AudioOutputStream, to restore
    {$ENDIF}
    FVoices: TStringList;
    FVoiceIndex: Integer;
    FRate: Integer;
    FVolume: Integer;
    FAsync: Boolean;
    FWaveform: TVMobj;
    FSampleRate: Integer;
    FHasWaveform: Boolean;
    FStyle: TVMSpeechStyle;
    FProsodyRate, FProsodyPitch: Integer;   // SAPI's -10 .. 10 scales
    FProsodyVolume: Integer;                 // 0 .. 100, 100 = unchanged
    FBreakSentenceMs, FBreakClauseMs: Integer;
    procedure SetStyle(AValue: TVMSpeechStyle);
    function WrapSSML(const Text: string): string;
    function PrepareText(const Text: string; out IsXml: Boolean): string;
    procedure SetVoiceIndex(AValue: Integer);
    procedure SetRate(AValue: Integer);
    procedure SetVolume(AValue: Integer);
    procedure EnumerateVoices;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { say Text aloud; returns at once if Async, else when finished }
    procedure Speak(const Text: string);
    { cancel any speech in progress }
    procedure Stop;
    { render Text silently into Waveform / SampleRate }
    procedure Synthesize(const Text: string);
    { the last Synthesize's audio as a 16-bit mono WAV file }
    procedure SaveToWav(const FileName: string);

    property Voices: TStringList read FVoices;
    property Waveform: TVMobj read FWaveform;
    property SampleRate: Integer read FSampleRate;
    property HasWaveform: Boolean read FHasWaveform;
    { seconds of audio in Waveform }
    function Duration: Double;
    { the SSML that Speak/Synthesize would send for Text under the current
      Style - for inspection, e.g. a demo showing what the engine receives }
    function SSMLFor(const Text: string): string;
  published
    property Style: TVMSpeechStyle read FStyle write SetStyle default ssPlain;
    { these five are read only when Style = ssCustom; the presets set them }
    property ProsodyRate: Integer read FProsodyRate write FProsodyRate default 0;
    property ProsodyPitch: Integer read FProsodyPitch write FProsodyPitch default 0;
    property ProsodyVolume: Integer read FProsodyVolume write FProsodyVolume default 100;
    property BreakSentenceMs: Integer read FBreakSentenceMs write FBreakSentenceMs default 0;
    property BreakClauseMs: Integer read FBreakClauseMs write FBreakClauseMs default 0;
    property Voice: Integer read FVoiceIndex write SetVoiceIndex default 0;
    property Rate: Integer read FRate write SetRate default 0;       // -10 .. 10
    property Volume: Integer read FVolume write SetVolume default 100; // 0 .. 100
    property Async: Boolean read FAsync write FAsync default False;
  end;

procedure Register;

implementation

const
  SVSFDefault = 0;
  SVSFlagsAsync = 1;
  SVSFPurgeBeforeSpeak = 2;
  SVSFIsXML = 8;
  SAFT16kHz16BitMono = 22;   // SpeechAudioFormatType

{ TVMSpeech }

constructor TVMSpeech.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FVoices := TStringList.Create;
  FVoiceIndex := 0;
  FRate := 0;
  FVolume := 100;
  FAsync := False;
  FHasWaveform := False;
  FSampleRate := 0;
  FStyle := ssPlain;
  FProsodyRate := 0;
  FProsodyPitch := 0;
  FProsodyVolume := 100;
  FBreakSentenceMs := 0;
  FBreakClauseMs := 0;
  {$IFDEF WINDOWS}
  if not (csDesigning in ComponentState) then
  begin
    FVoice := CreateOleObject('SAPI.SpVoice');
    FDefaultOutput := FVoice.AudioOutputStream;
    EnumerateVoices;
  end;
  {$ENDIF}
end;

destructor TVMSpeech.Destroy;
begin
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then
  begin
    try
      FVoice.Speak('', SVSFPurgeBeforeSpeak);
    except
    end;
    FDefaultOutput := Unassigned;
    FVoice := Unassigned;
  end;
  {$ENDIF}
  FVoices.Free;
  inherited Destroy;
end;

procedure TVMSpeech.EnumerateVoices;
{$IFDEF WINDOWS}
var
  Tokens: Variant;
  i: Integer;
begin
  FVoices.Clear;
  Tokens := FVoice.GetVoices;
  for i := 0 to Tokens.Count - 1 do
    FVoices.Add(Tokens.Item(i).GetDescription);
end;
{$ELSE}
begin
  FVoices.Clear;
end;
{$ENDIF}

procedure TVMSpeech.SetVoiceIndex(AValue: Integer);
begin
  if (AValue < 0) or ((FVoices.Count > 0) and (AValue >= FVoices.Count)) then Exit;
  FVoiceIndex := AValue;
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then
    FVoice.Voice := FVoice.GetVoices.Item(AValue);
  {$ENDIF}
end;

procedure TVMSpeech.SetRate(AValue: Integer);
begin
  FRate := EnsureRange(AValue, -10, 10);
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then FVoice.Rate := FRate;
  {$ENDIF}
end;

procedure TVMSpeech.SetVolume(AValue: Integer);
begin
  FVolume := EnsureRange(AValue, 0, 100);
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then FVoice.Volume := FVolume;
  {$ENDIF}
end;

procedure TVMSpeech.SetStyle(AValue: TVMSpeechStyle);
begin
  FStyle := AValue;
  case AValue of
    ssPlain:      begin FProsodyRate := 0;  FProsodyPitch := 0;  FProsodyVolume := 100; FBreakSentenceMs := 0;   FBreakClauseMs := 0;   end;
    ssNewsreader: begin FProsodyRate := -1; FProsodyPitch := 0;  FProsodyVolume := 100; FBreakSentenceMs := 250; FBreakClauseMs := 120; end;
    ssCalm:       begin FProsodyRate := -2; FProsodyPitch := -3; FProsodyVolume := 80;  FBreakSentenceMs := 450; FBreakClauseMs := 200; end;
    ssHAL:        begin FProsodyRate := -4; FProsodyPitch := -8; FProsodyVolume := 70;  FBreakSentenceMs := 800; FBreakClauseMs := 350; end;
    ssCustom: ;   // leave whatever the caller set
  end;
end;

function XmlEscape(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
end;

{ Wraps Text in SAPI's own prosody tags (see the unit comment for why
  not SSML's) and inserts silences at punctuation. Sentences (ending
  . ! ?) get BreakSentenceMs; clauses (, ; : - ) get BreakClauseMs. For
  ssHAL each sentence's final clause is additionally nested two pitch
  steps lower, the gentle fall of an unhurried statement - the engine's
  own default contour rises and falls far more than Rain's reading did. }
function TVMSpeech.WrapSSML(const Text: string): string;
var
  i, n, clauseStart: Integer;
  body, sentence, c: string;
  procedure FlushClause(upTo: Integer; const brk: string; falling: Boolean);
  var
    piece: string;
  begin
    piece := Trim(Copy(Text, clauseStart, upTo - clauseStart + 1));
    if piece <> '' then
    begin
      piece := XmlEscape(piece);
      if falling then
        piece := Format('<pitch absmiddle="%d">', [EnsureRange(FProsodyPitch - 2, -10, 10)]) + piece + '</pitch>';
      sentence := sentence + piece + ' ';
    end;
    if brk <> '' then sentence := sentence + brk;
    clauseStart := upTo + 1;
  end;
begin
  n := Length(Text);
  body := '';
  sentence := '';
  clauseStart := 1;
  i := 1;
  while i <= n do
  begin
    c := Text[i];
    if (c = '.') or (c = '!') or (c = '?') then
    begin
      // a sentence end: the final clause of a HAL sentence falls
      FlushClause(i, '', FStyle = ssHAL);
      if FBreakSentenceMs > 0 then
        sentence := sentence + Format('<silence msec="%d"/>', [FBreakSentenceMs]);
      body := body + sentence;
      sentence := '';
    end
    else if (c = ',') or (c = ';') or (c = ':') or ((c = '-') and (i > 1) and (Text[i - 1] = ' ')) then
    begin
      FlushClause(i, '', False);
      if FBreakClauseMs > 0 then
        sentence := sentence + Format('<silence msec="%d"/>', [FBreakClauseMs]);
    end;
    Inc(i);
  end;
  FlushClause(n, '', FStyle = ssHAL);   // anything after the last stop
  body := body + sentence;

  // SAPI's own envelope: rate and pitch on their -10..10 scales, volume
  // 0..100 - all nested so each applies to the whole text
  Result := Format('<rate absspeed="%d"><pitch absmiddle="%d"><volume level="%d">%s</volume></pitch></rate>',
    [EnsureRange(FProsodyRate, -10, 10), EnsureRange(FProsodyPitch, -10, 10),
     EnsureRange(FProsodyVolume, 0, 100), body]);
end;

function TVMSpeech.PrepareText(const Text: string; out IsXml: Boolean): string;
begin
  IsXml := FStyle <> ssPlain;
  if IsXml then Result := WrapSSML(Text) else Result := Text;
end;

function TVMSpeech.SSMLFor(const Text: string): string;
var
  x: Boolean;
begin
  Result := PrepareText(Text, x);
end;

procedure TVMSpeech.Speak(const Text: string);
{$IFDEF WINDOWS}
var
  Prepared: string;
  IsXml: Boolean;
  Flags: Integer;
{$ENDIF}
begin
  {$IFDEF WINDOWS}
  if VarIsEmpty(FVoice) then raise EVMSpeech.Create('SAPI voice not available');
  FVoice.AudioOutputStream := FDefaultOutput;
  Prepared := PrepareText(Text, IsXml);
  Flags := SVSFDefault;
  if IsXml then Flags := Flags or SVSFIsXML;
  if FAsync then Flags := Flags or SVSFlagsAsync or SVSFPurgeBeforeSpeak;
  FVoice.Speak(Prepared, Flags);
  {$ELSE}
  raise EVMSpeech.Create('TVMSpeech: only the Windows (SAPI) back end exists yet');
  {$ENDIF}
end;

procedure TVMSpeech.Stop;
begin
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then
    FVoice.Speak('', SVSFPurgeBeforeSpeak);
  {$ENDIF}
end;

procedure TVMSpeech.Synthesize(const Text: string);
{$IFDEF WINDOWS}
var
  Stream, Fmt, Data: Variant;
  P: Pointer;
  N, i, Flags: Integer;
  S: PSmallInt;
  W: PDouble;
  Prepared: string;
  IsXml: Boolean;
begin
  if VarIsEmpty(FVoice) then raise EVMSpeech.Create('SAPI voice not available');
  Prepared := PrepareText(Text, IsXml);
  Flags := SVSFDefault;
  if IsXml then Flags := Flags or SVSFIsXML;

  Stream := CreateOleObject('SAPI.SpMemoryStream');
  Fmt := CreateOleObject('SAPI.SpAudioFormat');
  Fmt.&Type := SAFT16kHz16BitMono;   // Type is reserved; & escapes it for the dispatch call
  Stream.Format := Fmt;

  FVoice.AudioOutputStream := Stream;
  try
    FVoice.Speak(Prepared, Flags);   // synchronous: the stream is complete on return
  finally
    FVoice.AudioOutputStream := FDefaultOutput;
  end;

  FSampleRate := Stream.Format.GetWaveFormatEx.SamplesPerSec;
  Data := Stream.GetData;              // Variant array of bytes, raw PCM
  N := (VarArrayHighBound(Data, 1) - VarArrayLowBound(Data, 1) + 1) div 2;
  if N < 1 then raise EVMSpeech.Create('SAPI returned no audio');

  FWaveform := TVMobj.Create(1, N);
  W := FWaveform.DataPtr;
  P := VarArrayLock(Data);
  try
    S := PSmallInt(P);
    for i := 0 to N - 1 do
      W[i] := S[i] / 32768.0;
  finally
    VarArrayUnlock(Data);
  end;
  FHasWaveform := True;
end;
{$ELSE}
begin
  raise EVMSpeech.Create('TVMSpeech: only the Windows (SAPI) back end exists yet');
end;
{$ENDIF}

function TVMSpeech.Duration: Double;
begin
  if FHasWaveform and (FSampleRate > 0) then
    Result := FWaveform.Cols / FSampleRate
  else
    Result := 0;
end;

procedure TVMSpeech.SaveToWav(const FileName: string);
var
  F: TFileStream;
  N, i: Integer;
  W: PDouble;
  Samples: array of SmallInt;
  u32: LongWord;
  u16: Word;
  procedure WriteStr(const S: string); begin F.WriteBuffer(S[1], Length(S)); end;
begin
  if not FHasWaveform then raise EVMSpeech.Create('nothing synthesised yet');
  N := FWaveform.Cols;
  SetLength(Samples, N);
  W := FWaveform.DataPtr;
  for i := 0 to N - 1 do
    Samples[i] := Round(EnsureRange(W[i], -1.0, 1.0) * 32767);
  F := TFileStream.Create(FileName, fmCreate);
  try
    WriteStr('RIFF'); u32 := 36 + N * 2; F.WriteBuffer(u32, 4); WriteStr('WAVE');
    WriteStr('fmt '); u32 := 16; F.WriteBuffer(u32, 4);
    u16 := 1; F.WriteBuffer(u16, 2);                       // PCM
    u16 := 1; F.WriteBuffer(u16, 2);                       // mono
    u32 := FSampleRate; F.WriteBuffer(u32, 4);
    u32 := FSampleRate * 2; F.WriteBuffer(u32, 4);         // byte rate
    u16 := 2; F.WriteBuffer(u16, 2);                       // block align
    u16 := 16; F.WriteBuffer(u16, 2);                      // bits
    WriteStr('data'); u32 := N * 2; F.WriteBuffer(u32, 4);
    if N > 0 then F.WriteBuffer(Samples[0], N * 2);
  finally
    F.Free;
  end;
end;

procedure Register;
begin
  RegisterComponents('newVM', [TVMSpeech]);
end;

end.
