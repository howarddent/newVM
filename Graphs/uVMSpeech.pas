unit uVMSpeech;

{*******************************************************************************

     TVMSpeech - a text-to-speech component for Lazarus, Windows SAPI 5
     or (on Linux) eSpeak NG behind it, with the synthesised waveform
     available as a newVM TVMobj.

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
     application.

     THE LINUX BACK END - eSpeak NG

     On Linux the same interface is backed by libespeak-ng (synthesis)
     and libpulse-simple (playback), both bound at run time with
     LoadLibrary like fftw3.pas, so the unit builds with neither
     installed and only fails, with EVMSpeech, when speech is actually
     asked for. Both come with any desktop Ubuntu (libespeak-ng1 is
     pulled in by speech-dispatcher; libpulse-simple also talks to
     PipeWire through its pulse server).

       - Synthesis is eSpeak's AUDIO_OUTPUT_SYNCHRONOUS mode: espeak_Synth
         hands 16-bit mono PCM (22050 Hz) to a callback on the calling
         thread and returns when the text is done, so Synthesize collects
         it straight into Waveform - no device, no temporary file.
       - Speak renders the same way and plays the samples through
         pa_simple_write: on the calling thread when blocking, or on a
         small TThread when Async (the demos' .lpr files already pull in
         cthreads). Stop terminates that thread, which flushes the stream
         instead of draining it. espeak itself is only ever called from
         the thread Speak/Synthesize are called on, as it is not
         thread-safe.
       - Voices lists eSpeak's own voices, English first with English
         (Great Britain) at index 0 (so Voice = 0 is a sensible default),
         and each English voice followed by a female version (eSpeak's
         '+f3' variant, named '... - female'), then every other language.
         There are well over a hundred; it is a formant synthesiser, so
         every one of them sounds distinctly synthetic - but the formants
         in its spectrum are unusually clean.
       - Rate (-10..10) maps onto eSpeak's words per minute as
         175 * 3^(Rate/10), SAPI's own documented 1/3x .. 3x span, limited
         to eSpeak's 80..450; Volume (0..100) onto eSpeak's 0..200 scale
         where 100 is normal, so 100 here is eSpeak's normal level.
       - Prosody, measured the same way as SAPI's (pitch-tracked renders
         of one sentence): eSpeak's SSML <prosody pitch> also delivers
         only about half of what it asks (-20 % gave -10 %), while its
         PITCH parameter covers the range properly (0..100, 50 = the
         voice's own: 10 -> 72 Hz, 30 -> 84, 50 -> 101, 70 -> 124, 90 ->
         153 Hz). So the style's overall pitch, rate and volume are set
         as PARAMETERS before synthesis - pitch 50 + 3 per SAPI step,
         which puts -10 near SAPI's measured 78 Hz - and the SSML carries
         only the pauses (<break time>) and ssHAL's falling final clause
         (<prosody pitch="-8%">, about two of SAPI's steps once halved).
         As with SAPI's <rate absspeed>/<volume level>, a style other
         than ssPlain overrides Rate and Volume. eSpeak's RANGE parameter
         (intonation swing, 50 = normal) is also set per style - 40 for
         ssCalm, 20 for ssHAL, flattening the contour towards Rain's
         almost stressless delivery - which SAPI has no equivalent for.
         SSMLFor shows the SSML the engine receives, not the parameters.

     On other targets (macOS) everything is still stubbed to raise
     EVMSpeech, so a cross-platform project builds.

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
  {$IFDEF LINUX} DynLibs, ctypes, {$ENDIF}
  newVM;

type
  EVMSpeech = class(Exception);

  TVMSpeechStyle = (ssPlain, ssNewsreader, ssCalm, ssHAL, ssCustom);

  TSmallIntArray = array of SmallInt;

  { TVMSpeech }

  TVMSpeech = class(TComponent)
  private
    {$IFDEF WINDOWS}
    FVoice: Variant;          // SAPI.SpVoice
    FDefaultOutput: Variant;  // its original AudioOutputStream, to restore
    {$ENDIF}
    {$IFDEF LINUX}
    FEngineNames: TStringList;   // eSpeak voice name (+variant) per Voices entry
    FPlayer: TThread;            // the Async playback thread, if any
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
    {$IFDEF LINUX}
    function RenderPCM(const Text: string): TSmallIntArray;
    procedure ApplyEngineSettings;
    {$ENDIF}
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

{$IFDEF LINUX}
{ --- eSpeak NG and PulseAudio-simple, bound at run time --------------------- }

const
  AUDIO_OUTPUT_SYNCHRONOUS = 2;   // espeak_AUDIO_OUTPUT: PCM to the callback, Synth blocks
  espeakCHARS_UTF8 = 1;
  espeakSSML = $10;
  POS_CHARACTER = 1;
  EE_OK = 0;
  espeakRATE = 1;
  espeakVOLUME = 2;
  espeakPITCH = 3;
  espeakRANGE = 4;
  PA_STREAM_PLAYBACK = 1;
  PA_SAMPLE_S16LE = 3;

type
  TEspeakCallback = function(wav: PSmallInt; numsamples: cint; events: Pointer): cint; cdecl;
  {$PACKRECORDS C}
  TEspeakVoice = record
    name, languages, identifier: PChar;
    gender, age, variant, xx1: cuint8;
    score: cint;
    spare: Pointer;
  end;
  PEspeakVoice = ^TEspeakVoice;
  PPEspeakVoice = ^PEspeakVoice;
  TPaSampleSpec = record
    format: cint;
    rate: cuint32;
    channels: cuint8;
  end;
  {$PACKRECORDS DEFAULT}

var
  espeak_Initialize: function(output, buflength: cint; path: PChar; options: cint): cint; cdecl;
  espeak_SetSynthCallback: procedure(cb: TEspeakCallback); cdecl;
  espeak_Synth: function(text: Pointer; size: csize_t; position: cuint; position_type: cint;
    end_position: cuint; flags: cuint; unique_identifier: pcuint; user_data: Pointer): cint; cdecl;
  espeak_SetParameter: function(parameter, value, relative: cint): cint; cdecl;
  espeak_ListVoices: function(voice_spec: Pointer): PPEspeakVoice; cdecl;
  espeak_SetVoiceByName: function(name: PChar): cint; cdecl;

  pa_simple_new: function(server, name: PChar; dir: cint; dev, stream_name: PChar;
    ss: Pointer; map, attr: Pointer; error: pcint): Pointer; cdecl;
  pa_simple_write: function(s: Pointer; data: Pointer; bytes: csize_t; error: pcint): cint; cdecl;
  pa_simple_drain: function(s: Pointer; error: pcint): cint; cdecl;
  pa_simple_flush: function(s: Pointer; error: pcint): cint; cdecl;
  pa_simple_free: procedure(s: Pointer); cdecl;

  ESpeakTried, ESpeakOK, PulseTried, PulseOK: Boolean;
  ESpeakSampleRate: Integer;
  GCapture: TSmallIntArray;   // the callback's output (one synthesis at a time)
  GCaptureN: Integer;

{ eSpeak calls this from inside espeak_Synth, on the same thread, with each
  chunk of samples; a nil wav marks the end. Returning 0 means carry on. }
function CaptureCallback(wav: PSmallInt; numsamples: cint; events: Pointer): cint; cdecl;
begin
  Result := 0;
  if (wav = nil) or (numsamples <= 0) then Exit;
  if GCaptureN + numsamples > Length(GCapture) then
    SetLength(GCapture, Max(2 * Length(GCapture), GCaptureN + numsamples + 65536));
  Move(wav^, GCapture[GCaptureN], numsamples * SizeOf(SmallInt));
  Inc(GCaptureN, numsamples);
end;

function LoadESpeak: Boolean;
var
  H: TLibHandle;
begin
  if not ESpeakTried then
  begin
    ESpeakTried := True;
    H := LoadLibrary('libespeak-ng.so.1');
    if H = NilHandle then H := LoadLibrary('libespeak-ng.so');
    if H <> NilHandle then
    begin
      Pointer(espeak_Initialize) := GetProcedureAddress(H, 'espeak_Initialize');
      Pointer(espeak_SetSynthCallback) := GetProcedureAddress(H, 'espeak_SetSynthCallback');
      Pointer(espeak_Synth) := GetProcedureAddress(H, 'espeak_Synth');
      Pointer(espeak_SetParameter) := GetProcedureAddress(H, 'espeak_SetParameter');
      Pointer(espeak_ListVoices) := GetProcedureAddress(H, 'espeak_ListVoices');
      Pointer(espeak_SetVoiceByName) := GetProcedureAddress(H, 'espeak_SetVoiceByName');
      if Assigned(espeak_Initialize) and Assigned(espeak_SetSynthCallback) and Assigned(espeak_Synth)
        and Assigned(espeak_SetParameter) and Assigned(espeak_ListVoices) and Assigned(espeak_SetVoiceByName) then
      begin
        ESpeakSampleRate := espeak_Initialize(AUDIO_OUTPUT_SYNCHRONOUS, 500, nil, 0);
        if ESpeakSampleRate > 0 then
        begin
          espeak_SetSynthCallback(@CaptureCallback);
          ESpeakOK := True;
        end;
      end;
    end;
  end;
  Result := ESpeakOK;
end;

function LoadPulse: Boolean;
var
  H: TLibHandle;
begin
  if not PulseTried then
  begin
    PulseTried := True;
    H := LoadLibrary('libpulse-simple.so.0');
    if H <> NilHandle then
    begin
      Pointer(pa_simple_new) := GetProcedureAddress(H, 'pa_simple_new');
      Pointer(pa_simple_write) := GetProcedureAddress(H, 'pa_simple_write');
      Pointer(pa_simple_drain) := GetProcedureAddress(H, 'pa_simple_drain');
      Pointer(pa_simple_flush) := GetProcedureAddress(H, 'pa_simple_flush');
      Pointer(pa_simple_free) := GetProcedureAddress(H, 'pa_simple_free');
      PulseOK := Assigned(pa_simple_new) and Assigned(pa_simple_write) and Assigned(pa_simple_drain)
        and Assigned(pa_simple_flush) and Assigned(pa_simple_free);
    end;
  end;
  Result := PulseOK;
end;

{ Plays 16-bit mono samples through the default sink, in ~46 ms chunks so
  that Abort (the player thread's Terminated) is noticed promptly; an
  aborted stream is flushed, a finished one drained. Raises only when
  called without an abort flag, i.e. from a blocking Speak. }
function PlayPCM(const Samples: TSmallIntArray; Rate: Integer; Aborted: TThread): Boolean;
const
  Chunk = 1024;
var
  Spec: TPaSampleSpec;
  S: Pointer;
  Err: cint;
  i, n: Integer;
  function Stopped: Boolean;
  begin
    Result := (Aborted <> nil) and Aborted.CheckTerminated;
  end;
begin
  Result := False;
  Spec.format := PA_SAMPLE_S16LE;
  Spec.rate := Rate;
  Spec.channels := 1;
  S := pa_simple_new(nil, 'newVM', PA_STREAM_PLAYBACK, nil, 'TVMSpeech', @Spec, nil, nil, @Err);
  if S = nil then
  begin
    if Aborted = nil then
      raise EVMSpeech.CreateFmt('TVMSpeech: cannot open the audio output (PulseAudio error %d)', [Err]);
    Exit;
  end;
  try
    i := 0;
    while (i < Length(Samples)) and not Stopped do
    begin
      n := Min(Chunk, Length(Samples) - i);
      if pa_simple_write(S, @Samples[i], n * SizeOf(SmallInt), @Err) < 0 then Break;
      Inc(i, n);
    end;
    if Stopped then pa_simple_flush(S, @Err) else pa_simple_drain(S, @Err);
    Result := True;
  finally
    pa_simple_free(S);
  end;
end;

type
  { Async Speak's playback: owns its copy of the samples, so the caller can
    synthesise the next text while this one is still being heard }
  TVMSpeechPlayer = class(TThread)
  private
    FSamples: TSmallIntArray;
    FRate: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(const ASamples: TSmallIntArray; ARate: Integer);
  end;

constructor TVMSpeechPlayer.Create(const ASamples: TSmallIntArray; ARate: Integer);
begin
  FSamples := ASamples;
  FRate := ARate;
  FreeOnTerminate := False;
  inherited Create(False);
end;

procedure TVMSpeechPlayer.Execute;
begin
  PlayPCM(FSamples, FRate, Self);
end;
{$ENDIF}

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
  {$IFDEF LINUX}
  FEngineNames := TStringList.Create;
  if not (csDesigning in ComponentState) then
    EnumerateVoices;
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
  {$IFDEF LINUX}
  Stop;
  FEngineNames.Free;
  {$ENDIF}
  FVoices.Free;
  inherited Destroy;
end;

procedure TVMSpeech.EnumerateVoices;
{$IF DEFINED(WINDOWS)}
var
  Tokens: Variant;
  i: Integer;
begin
  FVoices.Clear;
  Tokens := FVoice.GetVoices;
  for i := 0 to Tokens.Count - 1 do
    FVoices.Add(Tokens.Item(i).GetDescription);
end;
{$ELSEIF DEFINED(LINUX)}
var
  List: PPEspeakVoice;
  i: Integer;
  VName, VId: string;
  English, Others: TStringList;
  procedure AddVoice(const Display, Engine: string);
  begin
    FVoices.Add(Display);
    FEngineNames.Add(Engine);
  end;
begin
  FVoices.Clear;
  FEngineNames.Clear;
  if not LoadESpeak then Exit;   // no engine: an empty list, as on a SAPI-less Windows
  English := TStringList.Create;
  Others := TStringList.Create;
  try
    List := espeak_ListVoices(nil);
    i := 0;
    while (List <> nil) and (List[i] <> nil) do
    begin
      VName := string(List[i]^.name);
      VId := string(List[i]^.identifier);
      if Pos('/en', VId) > 0 then
      begin
        if VId = 'gmw/en' then English.Insert(0, VName) else English.Add(VName);   // en-gb first
      end
      else
        Others.Add(VName);
      Inc(i);
    end;
    for i := 0 to English.Count - 1 do
    begin
      AddVoice(English[i], English[i]);
      AddVoice(English[i] + ' - female', English[i] + '+f3');
    end;
    Others.Sort;
    for i := 0 to Others.Count - 1 do
      AddVoice(Others[i], Others[i]);
  finally
    English.Free;
    Others.Free;
  end;
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
  function Pause(ms: Integer): string;
  begin
    {$IFDEF WINDOWS}
    Result := Format('<silence msec="%d"/>', [ms]);
    {$ELSE}
    Result := Format('<break time="%dms"/>', [ms]);
    {$ENDIF}
  end;
  procedure FlushClause(upTo: Integer; const brk: string; falling: Boolean);
  var
    piece: string;
  begin
    piece := Trim(Copy(Text, clauseStart, upTo - clauseStart + 1));
    if piece <> '' then
    begin
      piece := XmlEscape(piece);
      if falling then
        {$IFDEF WINDOWS}
        piece := Format('<pitch absmiddle="%d">', [EnsureRange(FProsodyPitch - 2, -10, 10)]) + piece + '</pitch>';
        {$ELSE}
        // relative to the PITCH parameter; eSpeak delivers ~half, so ~2 SAPI steps
        piece := '<prosody pitch="-8%">' + piece + '</prosody>';
        {$ENDIF}
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
        sentence := sentence + Pause(FBreakSentenceMs);
      body := body + sentence;
      sentence := '';
    end
    else if (c = ',') or (c = ';') or (c = ':') or ((c = '-') and (i > 1) and (Text[i - 1] = ' ')) then
    begin
      FlushClause(i, '', False);
      if FBreakClauseMs > 0 then
        sentence := sentence + Pause(FBreakClauseMs);
    end;
    Inc(i);
  end;
  FlushClause(n, '', FStyle = ssHAL);   // anything after the last stop
  body := body + sentence;

  {$IFDEF WINDOWS}
  // SAPI's own envelope: rate and pitch on their -10..10 scales, volume
  // 0..100 - all nested so each applies to the whole text
  Result := Format('<rate absspeed="%d"><pitch absmiddle="%d"><volume level="%d">%s</volume></pitch></rate>',
    [EnsureRange(FProsodyRate, -10, 10), EnsureRange(FProsodyPitch, -10, 10),
     EnsureRange(FProsodyVolume, 0, 100), body]);
  {$ELSE}
  // eSpeak: rate, pitch and volume go in as engine parameters (see the
  // unit comment), so the SSML is only the pauses and the falling clauses
  Result := '<speak>' + body + '</speak>';
  {$ENDIF}
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
  {$IF DEFINED(WINDOWS)}
  if VarIsEmpty(FVoice) then raise EVMSpeech.Create('SAPI voice not available');
  FVoice.AudioOutputStream := FDefaultOutput;
  Prepared := PrepareText(Text, IsXml);
  Flags := SVSFDefault;
  if IsXml then Flags := Flags or SVSFIsXML;
  if FAsync then Flags := Flags or SVSFlagsAsync or SVSFPurgeBeforeSpeak;
  FVoice.Speak(Prepared, Flags);
  {$ELSEIF DEFINED(LINUX)}
  Stop;
  if not LoadPulse then
    raise EVMSpeech.Create('TVMSpeech: libpulse-simple.so.0 not found - cannot play audio');
  if FAsync then
    FPlayer := TVMSpeechPlayer.Create(RenderPCM(Text), ESpeakSampleRate)
  else
    PlayPCM(RenderPCM(Text), ESpeakSampleRate, nil);
  {$ELSE}
  raise EVMSpeech.Create('TVMSpeech: no speech back end for this platform (SAPI on Windows, eSpeak NG on Linux)');
  {$ENDIF}
end;

procedure TVMSpeech.Stop;
begin
  {$IFDEF WINDOWS}
  if not VarIsEmpty(FVoice) then
    FVoice.Speak('', SVSFPurgeBeforeSpeak);
  {$ENDIF}
  {$IFDEF LINUX}
  if FPlayer <> nil then
  begin
    FPlayer.Terminate;   // the thread flushes the stream rather than draining it
    FPlayer.WaitFor;
    FreeAndNil(FPlayer);
  end;
  {$ENDIF}
end;

procedure TVMSpeech.Synthesize(const Text: string);
{$IF DEFINED(WINDOWS)}
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
{$ELSEIF DEFINED(LINUX)}
var
  PCM: TSmallIntArray;
  i: Integer;
  W: PDouble;
begin
  PCM := RenderPCM(Text);
  if Length(PCM) < 1 then raise EVMSpeech.Create('eSpeak returned no audio');
  FSampleRate := ESpeakSampleRate;
  FWaveform := TVMobj.Create(1, Length(PCM));
  W := FWaveform.DataPtr;
  for i := 0 to High(PCM) do
    W[i] := PCM[i] / 32768.0;
  FHasWaveform := True;
end;
{$ELSE}
begin
  raise EVMSpeech.Create('TVMSpeech: no speech back end for this platform (SAPI on Windows, eSpeak NG on Linux)');
end;
{$ENDIF}

{$IFDEF LINUX}
{ Voice, then the parameters - setting a voice resets eSpeak's pitch and
  range to that voice's own, so the order matters. A style other than
  ssPlain overrides Rate and Volume, as SAPI's absspeed/level tags do. }
procedure TVMSpeech.ApplyEngineSettings;
var
  r, v, Range: Integer;
begin
  if (FVoiceIndex >= 0) and (FVoiceIndex < FEngineNames.Count) then
    espeak_SetVoiceByName(PChar(FEngineNames[FVoiceIndex]));
  if FStyle = ssPlain then
  begin
    r := FRate;
    v := FVolume;
  end
  else
  begin
    r := FProsodyRate;
    v := FProsodyVolume;
  end;
  espeak_SetParameter(espeakRATE, EnsureRange(Round(175 * Power(3, EnsureRange(r, -10, 10) / 10)), 80, 450), 0);
  espeak_SetParameter(espeakVOLUME, EnsureRange(v, 0, 100), 0);
  if FStyle = ssPlain then
    espeak_SetParameter(espeakPITCH, 50, 0)
  else
    espeak_SetParameter(espeakPITCH, EnsureRange(50 + 3 * FProsodyPitch, 0, 100), 0);
  case FStyle of
    ssCalm: Range := 40;
    ssHAL:  Range := 20;
  else
    Range := 50;
  end;
  espeak_SetParameter(espeakRANGE, Range, 0);
end;

function TVMSpeech.RenderPCM(const Text: string): TSmallIntArray;
var
  Prepared: string;
  IsXml: Boolean;
  Flags: cuint;
  rc: cint;
begin
  if not LoadESpeak then
    raise EVMSpeech.Create('TVMSpeech: libespeak-ng.so.1 not found (apt install libespeak-ng1)');
  Prepared := PrepareText(Text, IsXml);
  ApplyEngineSettings;
  Flags := espeakCHARS_UTF8;
  if IsXml then Flags := Flags or espeakSSML;
  GCaptureN := 0;
  rc := espeak_Synth(PChar(Prepared), Length(Prepared) + 1, 0, POS_CHARACTER, 0, Flags, nil, nil);
  if rc <> EE_OK then
    raise EVMSpeech.CreateFmt('espeak_Synth failed (error %d)', [rc]);
  Result := Copy(GCapture, 0, GCaptureN);
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
