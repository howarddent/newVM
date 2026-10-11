unit unewsmain;

{*******************************************************************************

     Main form for the newsSpeak demo: today's top five Channel 4 News
     headlines, fetched, spoken, and their speech spectra stacked.

     THE FEED

     Channel 4 News publishes an RSS feed at
     https://www.channel4.com/news/feed - the one its own pages
     advertise in a <link rel="alternate" type="application/rss+xml">
     tag - with the newest stories first, about fifteen of them. Fetch
     is TFPHTTPClient over opensslsockets, exactly as
     demos/CanterburyRain does (including that demo's PreferOpenSSL3 fix
     for FPC 3.2.2's openssl unit - the OpenSSL 3 DLLs have to be beside
     the exe or on PATH). The feed is parsed with the RTL's XML reader
     (DOM/XMLRead): each <item>'s <title> (the headline), <description>
     (the standfirst, CDATA with the odd HTML tag, stripped) and
     <pubDate>. No HTML scraping and no third-party dependency - RSS is
     XML by definition. "Top five" means the feed's first five items,
     which is the newest five; the feed carries no ranking.

     SPEAKING, WITH A LIVE SPECTRUM

     Each headline is synthesised first (TVMSpeech.Synthesize - silent,
     into a TVMobj at the voice's own sample rate), then spoken aloud
     with Speak in SAPI's asynchronous mode, and while it plays a 30 ms
     timer analyses the synthesised waveform at the current playback
     position: a 46 ms Hamming-windowed slice (1024 samples at 22050 Hz),
     FFT_R2C, one-sided PSD in dB, resampled onto a fixed 0 .. 4 kHz
     grid and pushed to a TVMPlotSpectrum (Graphs/uVMPlotSpectrum.pas,
     the SDR analyser's front-on display) with AddGraph - so the
     spectrum moves with the speech, formants rising and falling
     syllable by syllable, with that component's short fade giving a
     little persistence. The playback position is wall-clock time since
     Speak was called (a TStopwatch-style GetTickCount64), which tracks
     SAPI's actual output closely enough for a display: the synthesised
     waveform IS the audio SAPI plays, rendered by the same voice at the
     same rate, so the two line up. When the elapsed time passes the
     waveform's duration the headline is finished and the next begins.
     No worker thread is needed - asynchronous Speak returns at once and
     everything else is timer-driven on the main thread.

     The reading is a sequence of items: an introduction - "News
     headlines from Channel 4 News on" followed by the date and time as
     words (SpokenDateTime: ordinal day, spoken year, twelve-hour clock,
     since digits come out as a jumble) - then each headline read in
     full, exactly as the feed gives it, with no number spoken before it,
     followed by the feed's summary of the story (its <description>, the
     standfirst shown under the headline in the memo), and finally the
     sign-off "These are the top five headlines today on Channel 4 News."
     Full stops are appended where missing so the style's sentence pause
     separates headline, summary and the next item.
     The voice is the female one, Zira, found by name (voice order isn't
     guaranteed) - or on Linux, where TVMSpeech runs on eSpeak NG, the
     first voice named '... - female', eSpeak's English (Great Britain)
     female variant - in TVMSpeech's ssCalm style. The spectrum is shown bare
     - ShowAxes and ShowCursor off and no title - just the moving trace
     over 0 .. 4 kHz; the status line says which headline is playing.
     Stop purges the speech engine and halts the sequence.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, fphttpclient, opensslsockets, openssl, DOM, XMLRead,
  newVM, newVMComplex, uVMSpeech, uVMPlotSpectrum;

const
  FeedUrl = 'https://www.channel4.com/news/feed';
  NumHeadlines = 5;
  SpecFmax = 4000.0;    // Hz, the live spectrum's range
  SpecBins = 400;       // fixed grid so every frame has the same length
  FrameSamples = 1024;  // analysis window, 46 ms at 22050 Hz
  TickMs = 30;          // display update interval

type
  THeadline = record
    Title, Standfirst, Published: string;
  end;
  THeadlines = array of THeadline;

  { TfmNews }

  TfmNews = class(TForm)
    btnFetch: TButton;
    btnRead: TButton;
    btnStop: TButton;
    lblStatus: TLabel;
    memHeadlines: TMemo;
    pnlLeft: TPanel;
    pnlTop: TPanel;
    procedure btnFetchClick(Sender: TObject);
    procedure btnReadClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FSpeech: TVMSpeech;
    FSpectrum: TVMPlotSpectrum;
    FHeadlines: THeadlines;
    FTimer: TTimer;
    FCurrent: Integer;        // item being spoken: 0 = intro, 1..N = headlines, N+1 = sign-off; -1 idle
    FStartTick: QWord;        // GetTickCount64 when Speak was called
    FWindow: TVMobj;          // the Hamming window, built once
    FReading: Boolean;
    function FetchHeadlines(out Err: string): THeadlines;
    function FrameSpectrum(Centre: Integer): TVMobj;
    procedure ShowHeadlines;
    procedure StartItem(Index: Integer);
    function ItemText(Index: Integer): string;
    function ItemLabel(Index: Integer): string;
    function SpokenDateTime: string;
    procedure FinishReading(const Msg: string);
    procedure TimerTick(Sender: TObject);
  end;

var
  fmNews: TfmNews;

implementation

{$R *.lfm}

const
  Ln10 = 2.302585092994046;

{ --- feed ---------------------------------------------------------------- }

// strips HTML tags and collapses whitespace - the standfirst comes as
// CDATA that occasionally carries a <p> or <a>
function StripHtml(const S: string): string;
var
  i: Integer;
  InTag: Boolean;
  c: Char;
begin
  Result := '';
  InTag := False;
  for i := 1 to Length(S) do
  begin
    c := S[i];
    if c = '<' then InTag := True
    else if c = '>' then InTag := False
    else if not InTag then
      if c in [#9, #10, #13] then Result := Result + ' ' else Result := Result + c;
  end;
  Result := Trim(StringReplace(Result, '  ', ' ', [rfReplaceAll]));
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
  Result := StringReplace(Result, '&#8217;', '''', [rfReplaceAll]);
  Result := StringReplace(Result, '&#8216;', '''', [rfReplaceAll]);
  Result := StringReplace(Result, '&#8220;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&#8221;', '"', [rfReplaceAll]);
end;

function TfmNews.FetchHeadlines(out Err: string): THeadlines;
var
  Client: TFPHTTPClient;
  Body: string;
  Doc: TXMLDocument;
  Stream: TStringStream;
  Items: TDOMNodeList;
  Item: TDOMNode;
  i, n: Integer;
  function ChildText(Node: TDOMNode; const Name: string): string;
  var
    C: TDOMNode;
  begin
    Result := '';
    C := Node.FirstChild;
    while C <> nil do
    begin
      if C.NodeName = UnicodeString(Name) then
      begin
        Result := UTF8Encode(C.TextContent);
        Exit;
      end;
      C := C.NextSibling;
    end;
  end;
begin
  Result := nil;
  Err := '';
  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.AllowRedirect := True;
      Client.IOTimeout := 30000;
      Client.AddHeader('User-Agent', 'Mozilla/5.0 (newVM newsSpeak demo)');
      Client.AddHeader('Accept', 'application/rss+xml, application/xml');
      Body := Client.Get(FeedUrl);
    except
      on E: Exception do
      begin
        Err := 'fetch failed: ' + E.Message;
        Exit;
      end;
    end;
  finally
    Client.Free;
  end;

  Stream := TStringStream.Create(Body);
  try
    try
      ReadXMLFile(Doc, Stream);
    except
      on E: Exception do
      begin
        Err := 'feed is not well-formed XML: ' + E.Message;
        Exit;
      end;
    end;
  finally
    Stream.Free;
  end;

  try
    Items := Doc.GetElementsByTagName('item');
    n := Min(NumHeadlines, Items.Count);
    SetLength(Result, n);
    for i := 0 to n - 1 do
    begin
      Item := Items[i];
      Result[i].Title := StripHtml(ChildText(Item, 'title'));
      Result[i].Standfirst := StripHtml(ChildText(Item, 'description'));
      Result[i].Published := ChildText(Item, 'pubDate');
    end;
    if n = 0 then Err := 'the feed has no items';
  finally
    Doc.Free;
  end;
end;

{ --- spectrum ------------------------------------------------------------- }

// one-sided PSD in dB of the FrameSamples-long slice of the synthesised
// waveform centred on sample Centre, resampled onto SpecBins points over
// 0 .. SpecFmax so every frame pushed to the display is the same length
function TfmNews.FrameSpectrum(Centre: Integer): TVMobj;
var
  N, NBins, Fs, k, j, Start: Integer;
  Fres, Peak, f, frac: Double;
  Seg, P, PdB: TVMobj;
  X: TVMobjZ;
  PP, DP, RP: PDouble;
begin
  N := FrameSamples;
  Fs := FSpeech.SampleRate;
  Start := EnsureRange(Centre - N div 2, 0, FSpeech.Waveform.Cols - N);
  Seg := SubMatrix(FSpeech.Waveform, 0, Start, 1, N) * FWindow;   // windowed slice
  X := FFT_R2C(Seg);
  NBins := N div 2 + 1;
  P := Sqr(GetRealPart(X)) + Sqr(GetImagPart(X));
  PP := P.DataPtr;
  Peak := 0;
  for k := 0 to NBins - 1 do if PP[k] > Peak then Peak := PP[k];
  // relative dB, 0 at the frame's own peak, floored at -60: the display
  // auto-fits its Y range to the frames it holds, so a fixed floor and a
  // fixed ceiling keep the axis still while the spectrum moves
  PdB := (10 / Ln10) * Ln(AddScalar(P * (1.0 / Max(Peak, 1e-12)), 1e-6));
  DP := PdB.DataPtr;
  for k := 0 to NBins - 1 do
    if DP[k] < -60 then DP[k] := -60;
  DP[0] := 0;   // pin the axis: one bin at the ceiling, DC carries nothing in speech anyway
  Fres := Fs / N;

  Result := TVMobj.Create(1, SpecBins);
  RP := Result.DataPtr;
  for j := 0 to SpecBins - 1 do
  begin
    f := SpecFmax * j / (SpecBins - 1);
    k := Trunc(f / Fres);
    if k >= NBins - 1 then RP[j] := DP[NBins - 1]
    else
    begin
      frac := f / Fres - k;
      RP[j] := DP[k] * (1 - frac) + DP[k + 1] * frac;
    end;
  end;
end;

{ --- reading, timer-driven ------------------------------------------------ }

const
  Ones: array[0..19] of string = ('zero', 'one', 'two', 'three', 'four', 'five', 'six',
    'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen',
    'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen');

// The date and time as words a voice reads naturally: "Sunday the
// eleventh of October, twenty twenty-six, at nine minutes past ten in the
// morning". Digits would be read as numbers but "11/10/2026 10:09" comes
// out as a jumble; ordinal day, spoken year and twelve-hour clock sound
// like a person. FormatDateTime does the names, the rest is by hand.
function TfmNews.SpokenDateTime: string;
const
  Tens: array[2..5] of string = ('twenty', 'thirty', 'forty', 'fifty');
  Ordinals: array[1..31] of string = ('first', 'second', 'third', 'fourth', 'fifth',
    'sixth', 'seventh', 'eighth', 'ninth', 'tenth', 'eleventh', 'twelfth',
    'thirteenth', 'fourteenth', 'fifteenth', 'sixteenth', 'seventeenth',
    'eighteenth', 'nineteenth', 'twentieth', 'twenty-first', 'twenty-second',
    'twenty-third', 'twenty-fourth', 'twenty-fifth', 'twenty-sixth',
    'twenty-seventh', 'twenty-eighth', 'twenty-ninth', 'thirtieth', 'thirty-first');
  function Num(n: Integer): string;   // 0 .. 59
  begin
    if n < 20 then Result := Ones[n]
    else if n mod 10 = 0 then Result := Tens[n div 10]
    else Result := Tens[n div 10] + '-' + Ones[n mod 10];
  end;
  function Minutes(n: Integer): string;   // "one minute", "two minutes"
  begin
    if n = 1 then Result := ' minute' else Result := ' minutes';
  end;
var
  Y, M, D, H, Mi, S, Ms: Word;
  Hour12: Integer;
  Clock, Part: string;
begin
  DecodeDate(Now, Y, M, D);
  DecodeTime(Now, H, Mi, S, Ms);
  Hour12 := H mod 12; if Hour12 = 0 then Hour12 := 12;
  if H < 12 then Part := 'in the morning'
  else if H < 18 then Part := 'in the afternoon'
  else Part := 'in the evening';
  if Mi = 0 then Clock := Num(Hour12) + ' o''clock'
  else if Mi = 15 then Clock := 'a quarter past ' + Num(Hour12)
  else if Mi = 30 then Clock := 'half past ' + Num(Hour12)
  else if Mi = 45 then Clock := 'a quarter to ' + Num(Hour12 mod 12 + 1)
  else if Mi < 30 then Clock := Num(Mi) + Minutes(Mi) + ' past ' + Num(Hour12)
  else Clock := Num(60 - Mi) + Minutes(60 - Mi) + ' to ' + Num(Hour12 mod 12 + 1);
  Result := Format('%s the %s of %s, %s %s, at %s %s',
    [FormatDateTime('dddd', Now), Ordinals[D], FormatDateTime('mmmm', Now),
     Num(Y div 100), Num(Y mod 100), Clock, Part]);
end;

// What item Index says: 0 the introduction with the date and time, 1..N a
// headline in full followed by the feed's summary of the story (the
// standfirst shown under it in the memo), N+1 the sign-off. Full stops
// are appended wherever missing so the style's sentence pause separates
// headline from summary and each item from the next.
function TfmNews.ItemText(Index: Integer): string;
var
  N: Integer;
begin
  N := Length(FHeadlines);
  if Index = 0 then
    Result := 'News headlines from Channel 4 News on ' + SpokenDateTime + '.'
  else if Index = N + 1 then
    Result := Format('These are the top %s headlines today on Channel 4 News.', [Ones[N]])
  else
  begin
    Result := FHeadlines[Index - 1].Title;
    if not (Result[Length(Result)] in ['.', '!', '?']) then Result := Result + '.';
    if FHeadlines[Index - 1].Standfirst <> '' then
    begin
      Result := Result + ' ' + FHeadlines[Index - 1].Standfirst;
      if not (Result[Length(Result)] in ['.', '!', '?']) then Result := Result + '.';
    end;
  end;
end;

function TfmNews.ItemLabel(Index: Integer): string;
begin
  if Index = 0 then Result := 'the introduction'
  else if Index = Length(FHeadlines) + 1 then Result := 'the sign-off'
  else Result := Format('headline %d: %s', [Index, FHeadlines[Index - 1].Title]);
end;

procedure TfmNews.StartItem(Index: Integer);
var
  Spoken: string;
  Theta: TVMobj;
begin
  FCurrent := Index;
  Spoken := ItemText(Index);
  lblStatus.Caption := 'Synthesising ' + ItemLabel(Index) + '...';
  Application.ProcessMessages;
  FSpeech.Synthesize(Spoken);
  if FWindow.Cols <> FrameSamples then
  begin
    Theta := TVMobj.Create(1, FrameSamples);
    Theta.linspace(0, 2 * Pi / (FrameSamples - 1));
    FWindow := AddScalar((-0.46) * Cos(Theta), 0.54);
  end;
  lblStatus.Caption := 'Reading ' + ItemLabel(Index);
  FSpeech.Async := True;
  FStartTick := GetTickCount64;
  FSpeech.Speak(Spoken);
end;

procedure TfmNews.TimerTick(Sender: TObject);
var
  Elapsed: Double;
  Pos: Integer;
begin
  if not FReading then Exit;
  Elapsed := (GetTickCount64 - FStartTick) / 1000.0;
  if Elapsed >= FSpeech.Duration + 0.3 then      // a little slack for SAPI's start-up
  begin
    if FCurrent + 1 <= Length(FHeadlines) + 1 then
      StartItem(FCurrent + 1)
    else
      FinishReading('Done - all headlines read.');
    Exit;
  end;
  Pos := Round(Elapsed * FSpeech.SampleRate);
  if (Pos >= 0) and (Pos < FSpeech.Waveform.Cols) then
    FSpectrum.AddGraph(FrameSpectrum(Pos));
end;

procedure TfmNews.FinishReading(const Msg: string);
begin
  FReading := False;
  FTimer.Enabled := False;
  FCurrent := -1;
  lblStatus.Caption := Msg;
  btnFetch.Enabled := True;
  btnRead.Enabled := True;
  btnStop.Enabled := False;
end;

{ --- the form ------------------------------------------------------------- }

procedure TfmNews.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FSpeech := TVMSpeech.Create(Self);
  FSpeech.Style := ssCalm;         // slower, a little lower, softer - see uVMSpeech.pas
  // the female voice, if there is one: Zira on a standard Windows install.
  // Picked by name rather than index since voice order isn't guaranteed.
  for i := 0 to FSpeech.Voices.Count - 1 do
    if Pos('Zira', FSpeech.Voices[i]) > 0 then
    begin
      FSpeech.Voice := i;
      Break;
    end;
  {$IFNDEF WINDOWS}
  // eSpeak (Linux): its English female variant, listed second
  for i := 0 to FSpeech.Voices.Count - 1 do
    if Pos(' - female', FSpeech.Voices[i]) > 0 then
    begin
      FSpeech.Voice := i;
      Break;
    end;
  {$ENDIF}

  FSpectrum := TVMPlotSpectrum.Create(Self);
  FSpectrum.Parent := Self;
  FSpectrum.Align := alClient;
  FSpectrum.UseFrequencyAxis := True;
  FSpectrum.XAxisMin := 0;
  FSpectrum.XAxisMax := SpecFmax;
  FSpectrum.FadeSeconds := 0.4;      // a little persistence between frames
  FSpectrum.ShowPeakLabels := False; // frame-by-frame labels just flicker
  FSpectrum.ShowAverage := False;
  FSpectrum.ShowCursor := False;     // no tuning cursor or MHz readout here
  FSpectrum.ShowAxes := False;       // just the moving spectrum, no frame or scales
  FSpectrum.Title := '';              // no title either - the status line says what is playing
  FSpectrum.XAxisTitle := 'frequency (Hz)';
  FSpectrum.YAxisTitle := 'relative level (dB)';
  FSpectrum.ClearStack;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TickMs;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;
  FCurrent := -1;
  FWindow := TVMobj.Create(1, 1);

  btnRead.Enabled := False;
  btnStop.Enabled := False;
  if FSpeech.Voices.Count > 0 then
    lblStatus.Caption := Format('%d voice(s), using %s. Press Fetch.', [FSpeech.Voices.Count, FSpeech.Voices[FSpeech.Voice]])
  else
    lblStatus.Caption := 'No speech voices found (SAPI on Windows, eSpeak NG on Linux). Press Fetch for the headlines.';
end;

procedure TfmNews.FormDestroy(Sender: TObject);
begin
  FTimer.Enabled := False;
  FSpeech.Stop;
end;

procedure TfmNews.ShowHeadlines;
var
  i: Integer;
begin
  memHeadlines.Lines.BeginUpdate;
  try
    memHeadlines.Clear;
    memHeadlines.Lines.Add(Format('Channel 4 News - top %d, fetched %s', [Length(FHeadlines), FormatDateTime('ddd d mmm yyyy hh:nn', Now)]));
    memHeadlines.Lines.Add('');
    for i := 0 to High(FHeadlines) do
    begin
      memHeadlines.Lines.Add(Format('%d. %s', [i + 1, FHeadlines[i].Title]));
      if FHeadlines[i].Standfirst <> '' then
        memHeadlines.Lines.Add('   ' + FHeadlines[i].Standfirst);
      memHeadlines.Lines.Add('   ' + FHeadlines[i].Published);
      memHeadlines.Lines.Add('');
    end;
  finally
    memHeadlines.Lines.EndUpdate;
  end;
end;

procedure TfmNews.btnFetchClick(Sender: TObject);
var
  Err: string;
begin
  lblStatus.Caption := 'Fetching ' + FeedUrl + ' ...';
  Application.ProcessMessages;
  Screen.Cursor := crHourGlass;
  try
    FHeadlines := FetchHeadlines(Err);
  finally
    Screen.Cursor := crDefault;
  end;
  if Err <> '' then
  begin
    lblStatus.Caption := Err;
    Exit;
  end;
  ShowHeadlines;
  FSpectrum.ClearStack;
  btnRead.Enabled := True;
  lblStatus.Caption := Format('%d headlines fetched. Press Read.', [Length(FHeadlines)]);
end;

procedure TfmNews.btnReadClick(Sender: TObject);
begin
  if FReading or (Length(FHeadlines) = 0) then Exit;
  FSpectrum.ClearStack;
  btnFetch.Enabled := False;
  btnRead.Enabled := False;
  btnStop.Enabled := True;
  FReading := True;
  StartItem(0);
  FTimer.Enabled := True;
end;

procedure TfmNews.btnStopClick(Sender: TObject);
begin
  FSpeech.Stop;
  FinishReading('Stopped.');
end;

{ FPC 3.2.2's openssl unit knows only the 1.0/1.1 library names - see
  demos/CanterburyRain/uWeatherData.pas, from which this is copied: on
  Unix the '.3' suffix goes first in DLLVersions (Ubuntu 24.04 has only
  OpenSSL 3), on Windows the OpenSSL 3 DLL names go in the first slots. }
procedure PreferOpenSSL3;
{$IFDEF WINDOWS}
begin
  DLLUtilName := 'libcrypto-3-x64.dll';
  DLLSSLName := 'libssl-3-x64.dll';
end;
{$ELSE}
var
  i: Integer;
begin
  if DLLVersions[1] = '.3' then Exit;
  for i := High(DLLVersions) downto Low(DLLVersions) + 1 do
    DLLVersions[i] := DLLVersions[i - 1];
  DLLVersions[1] := '.3';
  {$IFDEF DARWIN}
  DLLVersions[2] := '.3';   // openssl.pas copies entry 2 over entry 1 on macOS
  {$ENDIF}
end;
{$ENDIF}

initialization
  PreferOpenSSL3;
end.
