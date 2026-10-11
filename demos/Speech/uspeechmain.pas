unit uspeechmain;

{*******************************************************************************

     Main form for the Speech demo - exercises TVMSpeech (Graphs/
     uVMSpeech.pas) and shows what it hands back to newVM.

     The text in the memo is spoken through SAPI (Windows) or eSpeak NG
     (Linux) with the chosen voice,
     rate and volume (Speak), or rendered silently into the component's
     Waveform (Synthesize) and plotted: the whole utterance above as a
     time trace, and below it the power spectral density of the whole
     thing - mean removed, Hamming window, FFT_R2C, one-sided dB, the
     same recipe as demos/BioSpectra - cut at 5 kHz, above which a
     speech spectrum carries little of interest (the desktop voices,
     and eSpeak, render at 22050 Hz, so the Nyquist limit is 11 kHz). A "Play"
     button speaks the same text again so the trace and the sound can be
     matched by ear, and "Save WAV" writes the samples out.

     A speech waveform on a 2 s axis reads as the classic string of
     syllable bursts; the spectrum shows the voice's pitch harmonics as a
     comb below about 500 Hz on top of the broad formant humps - the
     structure a formant synthesiser would reproduce, which is where
     this component is meant to go next (see uVMSpeech.pas's header).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Spin,
  newVM, newVMComplex, uVMSpeech, uVMPlot2D;

type

  { TfmSpeech }

  TfmSpeech = class(TForm)
    btnPlay: TButton;
    btnSave: TButton;
    btnSpeak: TButton;
    btnStop: TButton;
    btnSynth: TButton;
    cbStyle: TComboBox;
    cbVoice: TComboBox;
    lblInfo: TLabel;
    lblStyle: TLabel;
    lblRate: TLabel;
    lblVoice: TLabel;
    lblVolume: TLabel;
    memText: TMemo;
    pnlControls: TPanel;
    pnlPlots: TPanel;
    dlgSave: TSaveDialog;
    seRate: TSpinEdit;
    seVolume: TSpinEdit;
    procedure btnPlayClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure btnSpeakClick(Sender: TObject);
    procedure btnStopClick(Sender: TObject);
    procedure btnSynthClick(Sender: TObject);
    procedure cbVoiceChange(Sender: TObject);
    procedure cbStyleChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure pnlPlotsResize(Sender: TObject);
    procedure seRateChange(Sender: TObject);
    procedure seVolumeChange(Sender: TObject);
  private
    FSpeech: TVMSpeech;
    FWavePlot, FSpecPlot: TVMPlot2D;
    procedure ApplySettings;
  end;

var
  fmSpeech: TfmSpeech;

implementation

{$R *.lfm}

const
  Ln10 = 2.302585092994046;
  SpecFmax = 5000.0;

{ TfmSpeech }

procedure TfmSpeech.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FSpeech := TVMSpeech.Create(Self);
  for i := 0 to FSpeech.Voices.Count - 1 do
    cbVoice.Items.Add(FSpeech.Voices[i]);
  if cbVoice.Items.Count > 0 then cbVoice.ItemIndex := 0;
  cbStyle.ItemIndex := 0;

  FWavePlot := TVMPlot2D.Create(Self);
  FWavePlot.Parent := pnlPlots;
  FWavePlot.Align := alTop;
  FWavePlot.Height := pnlPlots.Height div 2;
  FWavePlot.XAxisTitle := 'time (s)';
  FWavePlot.YAxisTitle := 'amplitude';
  FWavePlot.Title := 'Waveform - press Synthesize';
  FWavePlot.SetSeriesStyle(0, clBlue, 1.0, plsSolid, 'speech');

  FSpecPlot := TVMPlot2D.Create(Self);
  FSpecPlot.Parent := pnlPlots;
  FSpecPlot.Align := alClient;
  FSpecPlot.XAxisTitle := 'frequency (Hz)';
  FSpecPlot.YAxisTitle := 'PSD (dB)';
  FSpecPlot.Title := 'Power spectrum';
  FSpecPlot.SetSeriesStyle(0, clRed, 1.0, plsSolid, 'Hamming-windowed PSD');

  ApplySettings;
  lblInfo.Caption := Format('%d voice(s) installed', [FSpeech.Voices.Count]);
end;

procedure TfmSpeech.ApplySettings;
begin
  FSpeech.Voice := cbVoice.ItemIndex;
  FSpeech.Rate := seRate.Value;
  FSpeech.Volume := seVolume.Value;
  FSpeech.Style := TVMSpeechStyle(cbStyle.ItemIndex);
end;

procedure TfmSpeech.cbVoiceChange(Sender: TObject);  begin ApplySettings; end;
procedure TfmSpeech.cbStyleChange(Sender: TObject);  begin ApplySettings; end;
procedure TfmSpeech.seRateChange(Sender: TObject);   begin ApplySettings; end;
procedure TfmSpeech.seVolumeChange(Sender: TObject); begin ApplySettings; end;

procedure TfmSpeech.pnlPlotsResize(Sender: TObject);
begin
  if Assigned(FWavePlot) then
    FWavePlot.Height := pnlPlots.Height div 2;
end;

procedure TfmSpeech.btnSpeakClick(Sender: TObject);
begin
  FSpeech.Async := True;
  FSpeech.Speak(memText.Text);
end;

procedure TfmSpeech.btnStopClick(Sender: TObject);
begin
  FSpeech.Stop;
end;

procedure TfmSpeech.btnPlayClick(Sender: TObject);
begin
  FSpeech.Async := True;
  FSpeech.Speak(memText.Text);
end;

procedure TfmSpeech.btnSynthClick(Sender: TObject);
var
  N, NBins, kMax, k: Integer;
  T, Theta, W, Y, Xw, P, F, PdB: TVMobj;
  X: TVMobjZ;
  Mean, Sw2, Fres, Peak: Double;
  YP, WP, PP: PDouble;
begin
  Screen.Cursor := crHourGlass;
  try
    FSpeech.Synthesize(memText.Text);
  finally
    Screen.Cursor := crDefault;
  end;
  N := FSpeech.Waveform.Cols;

  // time trace
  T := TVMobj.Create(1, N);
  T.linspace(0, 1 / FSpeech.SampleRate);
  FWavePlot.Title := Format('Waveform: "%s" - %.2f s at %d Hz, %d samples',
    [Copy(StringReplace(memText.Text, LineEnding, ' ', [rfReplaceAll]), 1, 60), FSpeech.Duration, FSpeech.SampleRate, N]);
  FWavePlot.ClearSeries;
  FWavePlot.SetData(T, [FSpeech.Waveform]);

  // PSD of the whole utterance, as BioSpectra does it
  YP := FSpeech.Waveform.DataPtr;
  Mean := 0;
  for k := 0 to N - 1 do Mean := Mean + YP[k];
  Y := AddScalar(FSpeech.Waveform, -Mean / N);
  Theta := TVMobj.Create(1, N);
  Theta.linspace(0, 2 * Pi / (N - 1));
  W := AddScalar((-0.46) * Cos(Theta), 0.54);
  WP := W.DataPtr;
  Sw2 := 0;
  for k := 0 to N - 1 do Sw2 := Sw2 + Sqr(WP[k]);
  Xw := Y * W;
  X := FFT_R2C(Xw);
  NBins := N div 2 + 1;
  P := (Sqr(GetRealPart(X)) + Sqr(GetImagPart(X))) * (2 / (FSpeech.SampleRate * Sw2));
  PP := P.DataPtr;
  Peak := 0;
  for k := 0 to NBins - 1 do if PP[k] > Peak then Peak := PP[k];
  PdB := (10 / Ln10) * Ln(AddScalar(P, Max(Peak * 1e-12, 1e-300)));
  Fres := FSpeech.SampleRate / N;
  kMax := Min(NBins - 1, Trunc(SpecFmax / Fres));
  F := TVMobj.Create(1, kMax + 1);
  F.linspace(0, Fres);
  FSpecPlot.Title := Format('Power spectral density of the utterance, Hamming window, to %.0f Hz', [kMax * Fres]);
  FSpecPlot.ClearSeries;
  FSpecPlot.SetData(F, [SubMatrix(PdB, 0, 0, 1, kMax + 1)]);

  lblInfo.Caption := Format('%d voice(s). Style %s: synthesised %.2f s at %d Hz (%d samples), peak |x| = %.2f',
    [FSpeech.Voices.Count, cbStyle.Text, FSpeech.Duration, FSpeech.SampleRate, N, Max(Abs(MinValue(YP, N)), Abs(MaxValue(YP, N)))]);
  lblInfo.Hint := FSpeech.SSMLFor(memText.Text);
  lblInfo.ShowHint := FSpeech.Style <> ssPlain;
  btnSave.Enabled := True;
  btnPlay.Enabled := True;
end;

procedure TfmSpeech.btnSaveClick(Sender: TObject);
begin
  if dlgSave.Execute then
    FSpeech.SaveToWav(dlgSave.FileName);
end;

end.
