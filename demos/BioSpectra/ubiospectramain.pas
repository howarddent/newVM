unit ubiospectramain;

{*******************************************************************************

     Main form for the BioSpectra demo: the time-domain trace and the power
     spectral density of three biological signals, one per tab - an ECG, an
     EEG and an invasive arterial blood pressure - each a 20-second excerpt
     of a PhysioNet record kept in data/ (see data/README.md for the
     records, byte ranges and licence) - plus a fourth tab of synthetic
     square and triangle waves for comparison.

     READING THE DATA

     The excerpts are raw WFDB format-212 bytes: two 12-bit two's-complement
     samples packed into three bytes (b0 + low nibble of b1 is sample 0,
     b2 + high nibble of b1 is sample 1), with the record's signals
     interleaved sample by sample. LoadWFDB212 decodes a whole excerpt,
     picks one signal by index, and converts ADC units to physical ones by
     the WFDB rule  physical = (adc - baseline) / gain , where gain and
     baseline come from the header's per-signal "gain(baseline)/units"
     field - baseline defaulting to the ADC-zero column when the
     parentheses are absent, as the WFDB spec says. Only the fields this
     demo displays are parsed; the header line's sampling frequency may be
     written "250/0.033333333(94)" (counter frequency and base counter
     appended), so it is cut at the first '/'.

     THE SPECTRUM (ComputePSD, shared by every tab)

     In order: the mean is removed (the DC line would otherwise dominate
     every plot, the pressure's especially, at ~90 mmHg); the trace is
     multiplied elementwise by a Hamming window
     w[n] = 0.54 - 0.46 cos(2 pi n/(N-1)), built as
     AddScalar(-0.46 * Cos(Theta), 0.54) over a linspace Theta; FFT_R2C
     (newVMComplex.pas, FFTW-backed) gives the packed half-spectrum of
     N div 2 + 1 bins; the one-sided power spectral density is
       Pxx[k] = 2 |X[k]|^2 / (fs * sum w^2)    (units^2 per Hz),
     without the factor 2 at DC and Nyquist, with |X|^2 as
     Sqr(GetRealPart(X)) + Sqr(GetImagPart(X)). It is plotted against
     f = k fs/N from 0 up to fs/2, the Nyquist frequency, either in
     decibels, (10/ln 10) * Ln(Pxx), or - the "linear scale" box - as
     Pxx itself. The window and PSD scaling follow the usual periodogram
     definition, so a pure tone of amplitude A integrates to A^2/2 across
     its peak.

     An upper-frequency spin edit (0 = Nyquist) lets the EEG's 0-40 Hz
     band be looked at on its own, since the interesting structure sits in
     the bottom third of its 125 Hz range; it applies to all tabs.

     SQUARE AND TRIANGLE WAVES (the fourth tab)

     Unit-amplitude square and triangle waves at a chosen fundamental f0,
     sampled at SynthFs = 1000 Hz for 20 s like the real signals, built by
     a loop over the phase (newVM has no elementwise Sign or Frac). Their
     Fourier series are the textbook ones - both odd harmonics only, the
     square's amplitudes 4/(pi n) falling as 1/n, 20 dB per decade, the
     triangle's 8/(pi^2 n^2) falling as 1/n^2, 40 dB per decade - and the
     memo lists the predicted amplitude of the first harmonics beside
     what integrating the PSD across each peak gives. A radio group
     shows the square wave, the triangle, or both overlaid; the time plot
     shows the first four periods only; the spectrum uses the whole 20 s.

     SQUARE-WAVE SYNTHESIS (the fifth tab)

     The square wave's Fourier series the other way round: the partial
     sums  S_K(t) = (4/pi) sum over k = 1..K of sin(2 pi n_k f0 t)/n_k  over the
     odd harmonics n_k = 1, 3, 5, ... , built term by term on newVM
     vectors - each term is one  (4/(pi n)) * Sin((2 pi n f0) * T)  added
     to the running sum. A spin edit sets K from 1 (the fundamental alone)
     to 10 (the fundamental plus the next nine odd harmonics, up to the
     19th), the time plot shows the ideal square wave dashed grey with
     either just S_K or, with "overlay every partial sum" ticked, all of
     S_1 .. S_K shaded from light to dark blue so the build-up reads as
     one picture, and the spectrum below is the PSD of S_K itself - K
     lines and nothing else. The memo lists the terms and, for S_K, the
     RMS error against the square wave and the peak overshoot, which never
     falls below about 9 % however many terms are added (Gibbs).

     EEG BISPECTRUM (the sixth tab)

     The power spectrum throws away phase; the bispectrum keeps the phase
     relation between pairs of frequencies and their sum,

       B(f1, f2) = E[ X(f1) X(f2) X*(f1 + f2) ]

     averaged over epochs, so it is large only where the components at
     f1, f2 and f1+f2 are phase-locked - quadratic phase coupling, which
     a Gaussian process never shows and an anaesthetised EEG famously does
     (the bispectral index, BIS, is built on exactly this). Averaging is
     what makes it usable - with the 20 s excerpt there were only 19
     epochs and the bicoherence floor sat near 0.23 - so this tab reads a
     separate 300 s excerpt of the same EEG (data/slp01a_600s_300s.dat,
     starting at the same 600 s; its first 20 s are the other tabs'
     excerpt exactly). That is cut into epochs of a chosen length (default
     2 s, 500 samples) at 50 % overlap - 299 of them - each mean-removed,
     Hamming-windowed and FFT'd
     with FFT_R2C; the triple product is accumulated on the (f1, f2) grid
     for f1, f2 up to the chosen limit (default 30 Hz, where the EEG's
     power lives) and f1 + f2 within the half-spectrum. Two things are
     offered: the bispectrum magnitude |B| itself, and the bicoherence

       b(f1, f2) = |B| / sqrt( E[|X(f1) X(f2)|^2] E[|X(f1+f2)|^2] )

     which divides out the power at the three frequencies and lies in
     [0, 1], so it reads as a fraction of the power that is phase-coupled
     rather than as power-weighted magnitude - with few epochs it has a
     bias floor of about 1/sqrt(epochs). Only the f2 <= f1 triangle is
     independent (B is symmetric in f1, f2), so the grid is filled on
     both sides from one computation. The result is a square TVMobj
     handed to a TVMPlot3D as a height field, its axis ranges set to the
     frequency limits so the ticks read in Hz; drag rotates, the wheel
     zooms, as that component always does.

     LAYOUT

     A TPageControl with one TTabSheet per signal; each sheet holds a memo
     (alRight) for the recording parameters and a panel (alClient) with
     the two TVMPlot2D controls created in code, time trace alTop at half
     height (kept there by the panel's OnResize) and spectrum alClient.
     The synthetic tab adds a strip with the fundamental-frequency spin
     edit.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, Spin,
  newVM, newVMComplex, uVMPlot2D, uVMPlot3D;

type
  { One signal excerpt plus what the header said about it }
  TSignalExcerpt = record
    Database, RecordName, Description, Units: string;
    Fs: Double;               // Hz
    Gain, Baseline: Double;   // adc = gain * physical + baseline
    AdcRes: Integer;          // bits
    NumSignals: Integer;      // in the record
    StartSec: Double;         // where the excerpt begins in the record
    HeaderLines: TStringList; // the raw .hea, for the memo
    Data: TVMobj;             // 1 x N, physical units
  end;

  TSignalTab = record
    Sheet: TTabSheet;
    Memo: TMemo;
    Plots: TPanel;
    TimePlot, SpecPlot: TVMPlot2D;
    Signal: TSignalExcerpt;
  end;

  { TfmBio }

  TfmBio = class(TForm)
    cbAllSums: TCheckBox;
    cbLinear: TCheckBox;
    cbLevelCurves: TCheckBox;
    lblBiFmax: TLabel;
    lblEpoch: TLabel;
    memBi: TMemo;
    pnlBi: TPanel;
    pnlBiCtl: TPanel;
    rgBiKind: TRadioGroup;
    seBiFmax: TFloatSpinEdit;
    seEpoch: TFloatSpinEdit;
    tsBispectrum: TTabSheet;
    lblF0: TLabel;
    lblSynF0: TLabel;
    lblTerms: TLabel;
    memSyn: TMemo;
    pnlSyn: TPanel;
    pnlSynCtl: TPanel;
    seSynF0: TFloatSpinEdit;
    seTerms: TSpinEdit;
    tsSynthesis: TTabSheet;
    lblFmax: TLabel;
    memSynth: TMemo;
    pnlSynth: TPanel;
    pnlSynthCtl: TPanel;
    pnlTop: TPanel;
    pcSignals: TPageControl;
    rgWave: TRadioGroup;
    seF0: TFloatSpinEdit;
    seFmax: TFloatSpinEdit;
    tsABP: TTabSheet;
    tsECG: TTabSheet;
    tsEEG: TTabSheet;
    tsSynth: TTabSheet;
    memABP: TMemo;
    memECG: TMemo;
    memEEG: TMemo;
    pnlABP: TPanel;
    pnlECG: TPanel;
    pnlEEG: TPanel;
    procedure cbLinearChange(Sender: TObject);
    procedure BispectrumChange(Sender: TObject);
    procedure cbLevelCurvesChange(Sender: TObject);
    procedure SynthesisChange(Sender: TObject);
    procedure SynPanelResize(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PlotsPanelResize(Sender: TObject);
    procedure rgWaveSelectionChanged(Sender: TObject);
    procedure seF0Change(Sender: TObject);
    procedure seFmaxChange(Sender: TObject);
    procedure SynthPanelResize(Sender: TObject);
  private
    FTabs: array[0..2] of TSignalTab;
    FSynthTime, FSynthSpec: TVMPlot2D;
    FSynTime, FSynSpec: TVMPlot2D;
    FBiPlot: TVMPlot3D;
    FEEGLong: TSignalExcerpt;   // the 300 s EEG excerpt, for the bispectrum only
    function DataDir: string;
    function LoadWFDB212(const DatFile, HeaFile: string; SigIndex: Integer;
      StartSec: Double): TSignalExcerpt;
    { one-sided PSD of Data at Fs: F is the frequency axis to the chosen
      upper limit, P the PSD (dB or linear per the check box) cut to match }
    procedure ComputePSD(const Data: TVMobj; Fs: Double; out F, P: TVMobj;
      out NBins: Integer; out Sw2: Double);
    function SpectrumYTitle(const Units: string): string;
    procedure ShowSignal(var Tab: TSignalTab);
    procedure ShowSynthetic;
    procedure ShowSynthesis;
    procedure ShowBispectrum;
    procedure ShowAll;
  end;

var
  fmBio: TfmBio;

const
  SynthFs = 1000.0;        // Hz
  SynthDuration = 20.0;    // s, as the PhysioNet excerpts

implementation

{$R *.lfm}

const
  Ln10 = 2.302585092994046;

{ TfmBio }

function TfmBio.DataDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'data' + PathDelim;
end;

function TfmBio.LoadWFDB212(const DatFile, HeaFile: string; SigIndex: Integer;
  StartSec: Double): TSignalExcerpt;
var
  Bytes: TBytes;
  fs: TFileStream;
  Fields: TStringArray;
  GainSpec, s: string;
  p, q, i, n, nFrames, b1, s0, s1: Integer;
  AdcZero: Integer;
  Samples: array of SmallInt;
begin
  Result := Default(TSignalExcerpt);
  Result.HeaderLines := TStringList.Create;
  Result.HeaderLines.LoadFromFile(HeaFile);
  Result.StartSec := StartSec;

  // record line: name nsig fs[/counter(base)] [nsamples ...]
  Fields := Result.HeaderLines[0].Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  Result.RecordName := Fields[0];
  Result.NumSignals := StrToInt(Fields[1]);
  s := Fields[2];
  p := Pos('/', s);
  if p > 0 then s := Copy(s, 1, p - 1);
  Result.Fs := StrToFloat(s, DefaultFormatSettings);

  // signal line: file fmt gain(baseline)/units adcres adczero initval checksum blocksize description
  Fields := Result.HeaderLines[1 + SigIndex].Split([' ', #9], TStringSplitOptions.ExcludeEmpty);
  GainSpec := Fields[2];
  Result.AdcRes := StrToInt(Fields[3]);
  AdcZero := StrToInt(Fields[4]);
  Result.Description := '';
  for i := 8 to High(Fields) do
    Result.Description := Trim(Result.Description + ' ' + Fields[i]);

  Result.Units := 'mV';                                   // the WFDB default
  p := Pos('/', GainSpec);
  if p > 0 then
  begin
    Result.Units := Copy(GainSpec, p + 1, MaxInt);
    GainSpec := Copy(GainSpec, 1, p - 1);
  end;
  Result.Baseline := AdcZero;
  p := Pos('(', GainSpec);
  if p > 0 then
  begin
    q := Pos(')', GainSpec);
    Result.Baseline := StrToFloat(Copy(GainSpec, p + 1, q - p - 1), DefaultFormatSettings);
    GainSpec := Copy(GainSpec, 1, p - 1);
  end;
  Result.Gain := StrToFloat(GainSpec, DefaultFormatSettings);
  if Result.Gain = 0 then Result.Gain := 200;             // WFDB default gain

  // format 212: 3 bytes -> 2 twelve-bit samples, signals interleaved
  fs := TFileStream.Create(DatFile, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Bytes, fs.Size);
    fs.ReadBuffer(Bytes[0], fs.Size);
  finally
    fs.Free;
  end;
  n := (Length(Bytes) div 3) * 2;
  SetLength(Samples, n);
  i := 0;
  while i < n do
  begin
    b1 := Bytes[(i div 2) * 3 + 1];
    s0 := Bytes[(i div 2) * 3] or ((b1 and $0F) shl 8);
    s1 := Bytes[(i div 2) * 3 + 2] or ((b1 and $F0) shl 4);
    if s0 > 2047 then Dec(s0, 4096);
    if s1 > 2047 then Dec(s1, 4096);
    Samples[i] := s0;
    Samples[i + 1] := s1;
    Inc(i, 2);
  end;

  nFrames := n div Result.NumSignals;
  Result.Data := TVMobj.Create(1, nFrames);
  for i := 0 to nFrames - 1 do
    Result.Data[0, i] := (Samples[i * Result.NumSignals + SigIndex] - Result.Baseline) / Result.Gain;
end;

procedure TfmBio.ComputePSD(const Data: TVMobj; Fs: Double; out F, P: TVMobj;
  out NBins: Integer; out Sw2: Double);
var
  N, k, kMax: Integer;
  Mean, Fmax, Fres: Double;
  Theta, W, Y, Xw, PP: TVMobj;
  X: TVMobjZ;
  XP: PDouble;
begin
  N := Data.Cols;
  Fres := Fs / N;

  // mean removal, Hamming window
  XP := Data.DataPtr;
  Mean := 0;
  for k := 0 to N - 1 do Mean := Mean + XP[k];
  Mean := Mean / N;
  Y := AddScalar(Data, -Mean);
  Theta := TVMobj.Create(1, N);
  Theta.linspace(0, 2 * Pi / (N - 1));
  W := AddScalar((-0.46) * Cos(Theta), 0.54);           // w[n] = 0.54 - 0.46 cos(2 pi n/(N-1))
  Sw2 := 0;
  XP := W.DataPtr;
  for k := 0 to N - 1 do Sw2 := Sw2 + Sqr(XP[k]);
  Xw := Y * W;                                          // elementwise

  // one-sided PSD from the packed half-spectrum
  X := FFT_R2C(Xw);
  NBins := N div 2 + 1;
  PP := Sqr(GetRealPart(X)) + Sqr(GetImagPart(X));      // |X|^2
  PP := PP * (2 / (Fs * Sw2));
  PP[0, 0] := PP[0, 0] / 2;                             // DC and Nyquist are not doubled
  if N mod 2 = 0 then PP[0, NBins - 1] := PP[0, NBins - 1] / 2;
  if not cbLinear.Checked then
  begin
    // 10 log10, floored 150 dB below the peak: the DC bin is exactly zero
    // after mean removal, and an absolute 1e-30 floor put it at -300 dB,
    // which stretched every dB axis for nothing
    XP := PP.DataPtr;
    Mean := 0;
    for k := 0 to NBins - 1 do if XP[k] > Mean then Mean := XP[k];
    PP := (10 / Ln10) * Ln(AddScalar(PP, Max(Mean * 1e-15, 1e-300)));
  end;

  // frequency axis, cut at the spin edit's upper limit if one is set
  Fmax := seFmax.Value;
  if (Fmax <= 0) or (Fmax > Fs / 2) then Fmax := Fs / 2;
  kMax := Min(NBins - 1, Trunc(Fmax / Fres));
  F := TVMobj.Create(1, kMax + 1);
  F.linspace(0, Fres);
  P := SubMatrix(PP, 0, 0, 1, kMax + 1);
end;

function TfmBio.SpectrumYTitle(const Units: string): string;
begin
  if cbLinear.Checked then
    Result := 'PSD (' + Units + '^2/Hz)'
  else
    Result := 'PSD (dB re 1 ' + Units + '^2/Hz)';
end;

procedure TfmBio.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FTabs[0].Sheet := tsECG; FTabs[0].Memo := memECG; FTabs[0].Plots := pnlECG;
  FTabs[1].Sheet := tsEEG; FTabs[1].Memo := memEEG; FTabs[1].Plots := pnlEEG;
  FTabs[2].Sheet := tsABP; FTabs[2].Memo := memABP; FTabs[2].Plots := pnlABP;

  FTabs[0].Signal := LoadWFDB212(DataDir + '100_60s_20s.dat', DataDir + '100.hea', 0, 60);
  FTabs[0].Signal.Database := 'MIT-BIH Arrhythmia Database (mitdb)';
  FTabs[1].Signal := LoadWFDB212(DataDir + 'slp01a_600s_20s.dat', DataDir + 'slp01a.hea', 2, 600);
  FTabs[1].Signal.Database := 'MIT-BIH Polysomnographic Database (slpdb)';
  FTabs[2].Signal := LoadWFDB212(DataDir + 'slp01a_600s_20s.dat', DataDir + 'slp01a.hea', 1, 600);
  FTabs[2].Signal.Database := 'MIT-BIH Polysomnographic Database (slpdb)';
  FEEGLong := LoadWFDB212(DataDir + 'slp01a_600s_300s.dat', DataDir + 'slp01a.hea', 2, 600);
  FEEGLong.Database := 'MIT-BIH Polysomnographic Database (slpdb)';

  for i := 0 to 2 do
    with FTabs[i] do
    begin
      TimePlot := TVMPlot2D.Create(Self);
      TimePlot.Parent := Plots;
      TimePlot.Align := alTop;
      TimePlot.Height := Plots.Height div 2;
      TimePlot.XAxisTitle := 'time (s)';
      TimePlot.YAxisTitle := Signal.Units;
      TimePlot.SetSeriesStyle(0, clBlue, 1.0, plsSolid, Signal.Description);

      SpecPlot := TVMPlot2D.Create(Self);
      SpecPlot.Parent := Plots;
      SpecPlot.Align := alClient;
      SpecPlot.XAxisTitle := 'frequency (Hz)';
      SpecPlot.SetSeriesStyle(0, clRed, 1.0, plsSolid, 'Hamming-windowed PSD');

      Plots.OnResize := @PlotsPanelResize;
    end;

  FSynthTime := TVMPlot2D.Create(Self);
  FSynthTime.Parent := pnlSynth;
  FSynthTime.Align := alTop;
  FSynthTime.Height := pnlSynth.Height div 2;
  FSynthTime.XAxisTitle := 'time (s)';
  FSynthTime.YAxisTitle := 'amplitude';
  FSynthSpec := TVMPlot2D.Create(Self);
  FSynthSpec.Parent := pnlSynth;
  FSynthSpec.Align := alClient;
  FSynthSpec.XAxisTitle := 'frequency (Hz)';

  FSynTime := TVMPlot2D.Create(Self);
  FSynTime.Parent := pnlSyn;
  FSynTime.Align := alTop;
  FSynTime.Height := pnlSyn.Height div 2;
  FSynTime.XAxisTitle := 'time (s)';
  FSynTime.YAxisTitle := 'amplitude';
  FSynSpec := TVMPlot2D.Create(Self);
  FSynSpec.Parent := pnlSyn;
  FSynSpec.Align := alClient;
  FSynSpec.XAxisTitle := 'frequency (Hz)';

  FBiPlot := TVMPlot3D.Create(Self);
  FBiPlot.Parent := pnlBi;
  FBiPlot.Align := alClient;
  FBiPlot.XAxisTitle := 'f1 (Hz)';
  FBiPlot.YAxisTitle := 'f2 (Hz)';

  ShowAll;

  // creating the GL controls on each sheet brings that sheet forward, so
  // the form would otherwise open on the last tab filled
  pcSignals.ActivePage := tsECG;
end;

procedure TfmBio.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to 2 do
    FTabs[i].Signal.HeaderLines.Free;
  FEEGLong.HeaderLines.Free;
end;

procedure TfmBio.PlotsPanelResize(Sender: TObject);
var
  i: Integer;
begin
  for i := 0 to 2 do
    if (FTabs[i].Plots = Sender) and Assigned(FTabs[i].TimePlot) then
      FTabs[i].TimePlot.Height := FTabs[i].Plots.Height div 2;
end;

procedure TfmBio.SynthPanelResize(Sender: TObject);
begin
  if Assigned(FSynthTime) then
    FSynthTime.Height := pnlSynth.Height div 2;
end;

procedure TfmBio.SynPanelResize(Sender: TObject);
begin
  if Assigned(FSynTime) then
    FSynTime.Height := pnlSyn.Height div 2;
end;

procedure TfmBio.SynthesisChange(Sender: TObject);
begin
  if Assigned(FSynTime) then
    ShowSynthesis;
end;

procedure TfmBio.BispectrumChange(Sender: TObject);
begin
  if Assigned(FBiPlot) then
    ShowBispectrum;
end;

procedure TfmBio.cbLevelCurvesChange(Sender: TObject);
begin
  if Assigned(FBiPlot) then
    FBiPlot.ShowLevelCurves := cbLevelCurves.Checked;
end;

procedure TfmBio.ShowBispectrum;
var
  Sig: TSignalExcerpt;
  Fs, Fres, Fmax, EpochSec, Mean, Sw2, Peak, PeakF1, PeakF2, Mag, Denom: Double;
  NTotal, NEp, Hop, NumEp, NBins, KMax, e, i, k, k1, k2: Integer;
  Theta, W, Seg, Segw, Grid: TVMobj;
  X: TVMobjZ;
  Xr, Xi: TVMobj;
  SP, WP: PDouble;
  // accumulators on the (k1, k2) grid, k2 <= k1
  Bre, Bim, P12, P3: array of array of Double;
  Pk: array of Double;   // E|X(k)|^2
  a1, b1, a2, b2, a3, b3, re, im: Double;
  Bicoh: Boolean;
begin
  Sig := FEEGLong;          // the 300 s EEG excerpt, not the EEG tab's 20 s
  Fs := Sig.Fs;
  NTotal := Sig.Data.Cols;
  EpochSec := seEpoch.Value;
  NEp := Round(EpochSec * Fs);
  if NEp > NTotal then NEp := NTotal;
  Hop := Max(1, NEp div 2);                     // 50 % overlap
  NumEp := (NTotal - NEp) div Hop + 1;
  NBins := NEp div 2 + 1;
  Fres := Fs / NEp;
  Fmax := seBiFmax.Value;
  if (Fmax <= 0) or (Fmax > Fs / 4) then Fmax := Fs / 4;   // f1 + f2 must stay below Nyquist
  KMax := Min(Trunc(Fmax / Fres), (NBins - 1) div 2);
  Bicoh := rgBiKind.ItemIndex = 1;

  // Hamming window for the epoch
  Theta := TVMobj.Create(1, NEp);
  Theta.linspace(0, 2 * Pi / (NEp - 1));
  W := AddScalar((-0.46) * Cos(Theta), 0.54);
  WP := W.DataPtr;
  Sw2 := 0;
  for i := 0 to NEp - 1 do Sw2 := Sw2 + Sqr(WP[i]);

  SetLength(Bre, KMax + 1, KMax + 1);
  SetLength(Bim, KMax + 1, KMax + 1);
  SetLength(P12, KMax + 1, KMax + 1);
  SetLength(P3, KMax + 1, KMax + 1);
  SetLength(Pk, 2 * KMax + 1);

  for e := 0 to NumEp - 1 do
  begin
    Seg := SubMatrix(Sig.Data, 0, e * Hop, 1, NEp);
    SP := Seg.DataPtr;
    Mean := 0;
    for i := 0 to NEp - 1 do Mean := Mean + SP[i];
    Segw := AddScalar(Seg, -Mean / NEp) * W;
    X := FFT_R2C(Segw);
    Xr := GetRealPart(X);
    Xi := GetImagPart(X);
    for k := 0 to 2 * KMax do
      Pk[k] := Pk[k] + Sqr(Xr[0, k]) + Sqr(Xi[0, k]);
    for k1 := 0 to KMax do
    begin
      a1 := Xr[0, k1]; b1 := Xi[0, k1];
      for k2 := 0 to k1 do
      begin
        a2 := Xr[0, k2]; b2 := Xi[0, k2];
        a3 := Xr[0, k1 + k2]; b3 := Xi[0, k1 + k2];
        // X1 * X2
        re := a1 * a2 - b1 * b2;
        im := a1 * b2 + b1 * a2;
        P12[k1, k2] := P12[k1, k2] + re * re + im * im;
        P3[k1, k2] := P3[k1, k2] + a3 * a3 + b3 * b3;
        // (X1 X2) * conj(X3)
        Bre[k1, k2] := Bre[k1, k2] + re * a3 + im * b3;
        Bim[k1, k2] := Bim[k1, k2] + im * a3 - re * b3;
      end;
    end;
  end;

  // fill the grid, both triangles, as |B| or bicoherence; scale |B| to
  // the PSD's units^3/Hz^2-ish convention per epoch so values are not
  // astronomically small
  Grid := TVMobj.Create(KMax + 1, KMax + 1);
  Peak := 0; PeakF1 := 0; PeakF2 := 0;
  for k1 := 0 to KMax do
    for k2 := 0 to k1 do
    begin
      Mag := Sqrt(Sqr(Bre[k1, k2]) + Sqr(Bim[k1, k2]));
      if Bicoh then
      begin
        Denom := Sqrt(P12[k1, k2] * P3[k1, k2]);
        if Denom > 0 then Mag := Mag / Denom else Mag := 0;
      end
      else
        Mag := Mag / (NumEp * Power(Fs * Sw2, 1.5));
      Grid[k2, k1] := Mag;    // row = f2, column = f1
      Grid[k1, k2] := Mag;
      if (Mag > Peak) and (k1 > 0) and (k2 > 0) then
      begin
        Peak := Mag; PeakF1 := k1 * Fres; PeakF2 := k2 * Fres;
      end;
    end;

  if Bicoh then
  begin
    FBiPlot.Title := Format('EEG bicoherence b(f1,f2), %s, %d epochs of %.3g s', [Sig.RecordName, NumEp, NEp / Fs]);
    FBiPlot.ZAxisTitle := 'bicoherence';
    FBiPlot.ZAxisMin := 0; FBiPlot.ZAxisMax := 1;
  end
  else
  begin
    FBiPlot.Title := Format('EEG bispectrum |B(f1,f2)|, %s, %d epochs of %.3g s', [Sig.RecordName, NumEp, NEp / Fs]);
    FBiPlot.ZAxisTitle := '|B| (' + Sig.Units + '^3)';
    FBiPlot.ZAxisMin := 0; FBiPlot.ZAxisMax := 0;   // from the data
  end;
  FBiPlot.XAxisMin := 0; FBiPlot.XAxisMax := KMax * Fres;
  FBiPlot.YAxisMin := 0; FBiPlot.YAxisMax := KMax * Fres;
  FBiPlot.ShowLevelCurves := cbLevelCurves.Checked;
  FBiPlot.SetData(Grid);

  memBi.Lines.BeginUpdate;
  try
    memBi.Clear;
    memBi.Lines.Add('Bispectrum of a 300 s EEG excerpt');
    memBi.Lines.Add('Record:     ' + Sig.RecordName + ' - ' + Sig.Description);
    memBi.Lines.Add(Format('Excerpt:    %.0f s to %.0f s of the record', [Sig.StartSec, Sig.StartSec + NTotal / Fs]));
    memBi.Lines.Add('            (the EEG tab shows its first 20 s)');
    memBi.Lines.Add(Format('Sampling:   %.6g Hz, %d samples (%.1f s)', [Fs, NTotal, NTotal / Fs]));
    memBi.Lines.Add('');
    memBi.Lines.Add(Format('Epochs:     %d of %d samples (%.3g s), 50 %% overlap', [NumEp, NEp, NEp / Fs]));
    memBi.Lines.Add('Window:     Hamming, mean removed per epoch');
    memBi.Lines.Add(Format('Resolution: %.4g Hz per bin', [Fres]));
    memBi.Lines.Add(Format('Grid:       f1, f2 = 0 .. %.4g Hz, %d x %d', [KMax * Fres, KMax + 1, KMax + 1]));
    memBi.Lines.Add(Format('            (f1 + f2 <= %.4g Hz, half the Nyquist)', [2 * KMax * Fres]));
    memBi.Lines.Add('');
    if Bicoh then
    begin
      memBi.Lines.Add('Shown: bicoherence');
      memBi.Lines.Add('  b = |B| / sqrt(E|X1 X2|^2  E|X3|^2), 0 .. 1');
      memBi.Lines.Add(Format('  bias floor ~ 1/sqrt(epochs) = %.2f', [1 / Sqrt(NumEp)]));
    end
    else
    begin
      memBi.Lines.Add('Shown: bispectrum magnitude');
      memBi.Lines.Add('  |B| = |E[X(f1) X(f2) X*(f1+f2)]|');
      memBi.Lines.Add('  (per epoch, window-normalised)');
    end;
    memBi.Lines.Add('');
    memBi.Lines.Add(Format('Largest off-axis value %.4g at', [Peak]));
    memBi.Lines.Add(Format('  f1 = %.3g Hz, f2 = %.3g Hz (sum %.3g Hz)', [PeakF1, PeakF2, PeakF1 + PeakF2]));
    memBi.Lines.Add('');
    memBi.Lines.Add('The surface is symmetric about f1 = f2;');
    memBi.Lines.Add('the f2 <= f1 triangle is the independent');
    memBi.Lines.Add('region. A ridge along the axes reflects');
    memBi.Lines.Add('the low-frequency power, not coupling;');
    memBi.Lines.Add('peaks off the axes mark frequency pairs');
    memBi.Lines.Add('whose phases are locked to their sum.');
    memBi.Lines.Add('Drag to rotate, wheel to zoom.');
  finally
    memBi.Lines.EndUpdate;
  end;
end;

procedure TfmBio.ShowAll;
var
  i: Integer;
begin
  if not Assigned(FSynthTime) then Exit;   // not yet built
  for i := 0 to 2 do
    ShowSignal(FTabs[i]);
  ShowSynthetic;
  ShowSynthesis;
  ShowBispectrum;
end;

procedure TfmBio.seFmaxChange(Sender: TObject);
begin
  ShowAll;
end;

procedure TfmBio.cbLinearChange(Sender: TObject);
begin
  ShowAll;
end;

procedure TfmBio.seF0Change(Sender: TObject);
begin
  if Assigned(FSynthTime) then
    ShowSynthetic;
end;

procedure TfmBio.rgWaveSelectionChanged(Sender: TObject);
begin
  if Assigned(FSynthTime) then
    ShowSynthetic;
end;

procedure TfmBio.ShowSignal(var Tab: TSignalTab);
var
  N, NBins, k: Integer;
  Sw2, Mean, Mn, Mx: Double;
  T, F, P: TVMobj;
  YP: PDouble;
begin
  with Tab do
  begin
    N := Signal.Data.Cols;

    // time trace
    T := TVMobj.Create(1, N);
    T.linspace(0, 1 / Signal.Fs);
    TimePlot.Title := Format('%s - %s, %.0f s excerpt from %.0f s', [Signal.RecordName, Signal.Description, N / Signal.Fs, Signal.StartSec]);
    TimePlot.ClearSeries;
    TimePlot.SetData(T, [Signal.Data]);

    YP := Signal.Data.DataPtr;
    Mean := 0; Mn := YP[0]; Mx := YP[0];
    for k := 0 to N - 1 do
    begin
      Mean := Mean + YP[k];
      if YP[k] < Mn then Mn := YP[k];
      if YP[k] > Mx then Mx := YP[k];
    end;
    Mean := Mean / N;

    // spectrum
    ComputePSD(Signal.Data, Signal.Fs, F, P, NBins, Sw2);
    SpecPlot.YAxisTitle := SpectrumYTitle(Signal.Units);
    SpecPlot.Title := Format('Power spectral density, Hamming window, N = %d, %.3f Hz resolution, to %.1f Hz', [N, Signal.Fs / N, F[0, F.Cols - 1]]);
    SpecPlot.ClearSeries;
    SpecPlot.SetData(F, [P]);

    // recording parameters
    Memo.Lines.BeginUpdate;
    try
      Memo.Clear;
      Memo.Lines.Add('Database:   ' + Signal.Database);
      Memo.Lines.Add('Record:     ' + Signal.RecordName);
      Memo.Lines.Add('Signal:     ' + Signal.Description);
      Memo.Lines.Add(Format('Signals in record: %d', [Signal.NumSignals]));
      Memo.Lines.Add('');
      Memo.Lines.Add(Format('Sampling frequency: %.6g Hz', [Signal.Fs]));
      Memo.Lines.Add(Format('ADC resolution:     %d bits', [Signal.AdcRes]));
      Memo.Lines.Add(Format('Gain:               %.6g adc units per %s', [Signal.Gain, Signal.Units]));
      Memo.Lines.Add(Format('Baseline:           %.6g adc units', [Signal.Baseline]));
      Memo.Lines.Add('Units:              ' + Signal.Units);
      Memo.Lines.Add('Storage format:     WFDB 212 (12-bit packed)');
      Memo.Lines.Add('');
      Memo.Lines.Add(Format('Excerpt:  %.0f s to %.0f s of the record', [Signal.StartSec, Signal.StartSec + N / Signal.Fs]));
      Memo.Lines.Add(Format('Samples:  %d  (%.1f s)', [N, N / Signal.Fs]));
      Memo.Lines.Add(Format('Mean %.4g, min %.4g, max %.4g %s', [Mean, Mn, Mx, Signal.Units]));
      Memo.Lines.Add('');
      Memo.Lines.Add('Spectrum: mean removed, Hamming window,');
      Memo.Lines.Add(Format('  FFT length %d, %d bins to Nyquist', [N, NBins]));
      Memo.Lines.Add(Format('  resolution %.4f Hz, Nyquist %.1f Hz', [Signal.Fs / N, Signal.Fs / 2]));
      if cbLinear.Checked then
        Memo.Lines.Add(Format('  one-sided PSD in %s^2/Hz, linear scale', [Signal.Units]))
      else
        Memo.Lines.Add(Format('  one-sided PSD in dB re 1 %s^2/Hz', [Signal.Units]));
      Memo.Lines.Add('');
      Memo.Lines.Add('Header (.hea):');
      Memo.Lines.AddStrings(Signal.HeaderLines);
    finally
      Memo.Lines.EndUpdate;
    end;
  end;
end;

procedure TfmBio.ShowSynthesis;
const
  MaxTerms = 10;
var
  NumTerms, k, n, NSamp, NShow, NBins, i: Integer;
  f0, Sw2, Rms, Peak: Double;
  T, Sq, Sum, F, P, TShow: TVMobj;
  Sums: array of TVMobj;
  Series: array of TVMobj;
  SqP, SumP: PDouble;
  nSer: Integer;
  Shade: Byte;
begin
  f0 := seSynF0.Value;
  NumTerms := seTerms.Value;
  NSamp := Round(SynthFs * SynthDuration);
  T := TVMobj.Create(1, NSamp);
  T.linspace(0, 1 / SynthFs);

  // the target, as on the previous tab
  Sq := TVMobj.Create(1, NSamp);
  SqP := Sq.DataPtr;
  for i := 0 to NSamp - 1 do
    if Frac(f0 * i / SynthFs) < 0.5 then SqP[i] := 1.0 else SqP[i] := -1.0;

  // the partial sums, each one term on from the last
  SetLength(Sums, NumTerms);
  Sum := TVMobj.Create(1, NSamp);                        // zero
  for k := 1 to NumTerms do
  begin
    n := 2 * k - 1;                                   // 1, 3, 5, ...
    Sum := Sum + (4 / (Pi * n)) * Sin((2 * Pi * n * f0) * T);
    Sums[k - 1] := Sum;
  end;

  // time plot: two periods, square wave dashed grey, then the sums
  NShow := Min(NSamp, Round(2 * SynthFs / f0));
  TShow := SubMatrix(T, 0, 0, 1, NShow);
  SetLength(Series, NumTerms + 1);
  Series[0] := SubMatrix(Sq, 0, 0, 1, NShow);
  FSynTime.SetSeriesStyle(0, clGray, 1.0, plsDash, 'square wave');
  nSer := 1;
  if cbAllSums.Checked then
    for k := 1 to NumTerms do
    begin
      Series[nSer] := SubMatrix(Sums[k - 1], 0, 0, 1, NShow);
      if k = NumTerms then
        FSynTime.SetSeriesStyle(nSer, clRed, 2.0, plsSolid, Format('n <= %d', [2 * k - 1]))
      else
      begin
        Shade := 200 - Round(150 * (k - 1) / Max(1, NumTerms - 1));   // light to dark blue
        // only the first and last sums get legend names, so a ten-entry
        // legend doesn't cover half the plot
        if k = 1 then
          FSynTime.SetSeriesStyle(nSer, RGBToColor(Shade, Shade, 255), 1.0, plsSolid, 'n = 1 (fundamental)')
        else
          FSynTime.SetSeriesStyle(nSer, RGBToColor(Shade, Shade, 255), 1.0, plsSolid, '');
      end;
      Inc(nSer);
    end
  else
  begin
    Series[1] := SubMatrix(Sums[NumTerms - 1], 0, 0, 1, NShow);
    FSynTime.SetSeriesStyle(1, clRed, 2.0, plsSolid, Format('sum to n = %d', [2 * NumTerms - 1]));
    nSer := 2;
  end;
  SetLength(Series, nSer);
  FSynTime.Title := Format('Square wave from its Fourier series: %d odd harmonic%s (n = 1 .. %d), f0 = %.3g Hz',
    [NumTerms, Copy('s', 1, Ord(NumTerms <> 1)), 2 * NumTerms - 1, f0]);
  FSynTime.ClearSeries;
  FSynTime.SetData(TShow, Series);

  // spectrum of the current sum
  ComputePSD(Sums[NumTerms - 1], SynthFs, F, P, NBins, Sw2);
  FSynSpec.YAxisTitle := SpectrumYTitle('unit');
  FSynSpec.SetSeriesStyle(0, clRed, 1.0, plsSolid, Format('PSD of the sum to n = %d', [2 * NumTerms - 1]));
  FSynSpec.Title := Format('Power spectral density of the partial sum, Hamming window, N = %d, to %.1f Hz', [NSamp, F[0, F.Cols - 1]]);
  FSynSpec.ClearSeries;
  FSynSpec.SetData(F, [P]);

  // error of the current sum against the square wave
  SumP := Sums[NumTerms - 1].DataPtr;
  Rms := 0; Peak := 0;
  for i := 0 to NSamp - 1 do
  begin
    Rms := Rms + Sqr(SumP[i] - SqP[i]);
    if Abs(SumP[i]) > Peak then Peak := Abs(SumP[i]);
  end;
  Rms := Sqrt(Rms / NSamp);

  memSyn.Lines.BeginUpdate;
  try
    memSyn.Clear;
    memSyn.Lines.Add('Fourier synthesis of a unit square wave');
    memSyn.Lines.Add(Format('Fundamental f0:     %.6g Hz', [f0]));
    memSyn.Lines.Add(Format('Sampling frequency: %.6g Hz', [SynthFs]));
    memSyn.Lines.Add(Format('Duration:           %.0f s  (%d samples)', [SynthDuration, NSamp]));
    memSyn.Lines.Add(Format('Terms added:        %d of %d', [NumTerms, MaxTerms]));
    memSyn.Lines.Add('');
    memSyn.Lines.Add('  S_K(t) = (4/pi) sum sin(2 pi n f0 t) / n');
    memSyn.Lines.Add('           over odd n = 1, 3, 5, ...');
    memSyn.Lines.Add('');
    memSyn.Lines.Add('   k    n   f (Hz)   amplitude 4/(pi n)');
    for k := 1 to NumTerms do
      memSyn.Lines.Add(Format('  %2d  %3d  %7.2f   %.4f', [k, 2 * k - 1, (2 * k - 1) * f0, 4 / (Pi * (2 * k - 1))]));
    memSyn.Lines.Add('');
    memSyn.Lines.Add(Format('RMS error vs square wave: %.4f', [Rms]));
    memSyn.Lines.Add(Format('Peak of the sum:          %.4f  (overshoot %.1f %% of the 2-unit jump)', [Peak, 100 * (Peak - 1) / 2]));
    memSyn.Lines.Add('');
    memSyn.Lines.Add('The RMS error keeps falling as terms are');
    memSyn.Lines.Add('added, but the overshoot at each edge does');
    memSyn.Lines.Add('not: it settles near 9 % (the Gibbs');
    memSyn.Lines.Add('phenomenon), only narrowing towards the edge.');
    memSyn.Lines.Add('The spectrum holds exactly K lines, one per');
    memSyn.Lines.Add('term, with nothing at the even harmonics.');
  finally
    memSyn.Lines.EndUpdate;
  end;
end;

procedure TfmBio.ShowSynthetic;
var
  N, NShow, NBins, i, h, k, k0, k1: Integer;
  f0, Phase, Sw2, Fres, SumSq, SumTri, ASq, ATri: Double;
  T, Sq, Tri, F, PSq, PTri, TShow: TVMobj;
  SqP, TriP: PDouble;
  PSqLin, PTriLin: TVMobj;
  dummyF: TVMobj;
  dummyN: Integer;
  dummyS: Double;
  WasLinear, ShowSq, ShowTri: Boolean;
  TimeSeries, SpecSeries: array of TVMobj;
  nSer: Integer;
  Title: string;
begin
  f0 := seF0.Value;
  ShowSq := rgWave.ItemIndex in [0, 2];
  ShowTri := rgWave.ItemIndex in [1, 2];
  N := Round(SynthFs * SynthDuration);
  T := TVMobj.Create(1, N);
  T.linspace(0, 1 / SynthFs);
  Sq := TVMobj.Create(1, N);
  Tri := TVMobj.Create(1, N);
  SqP := Sq.DataPtr;
  TriP := Tri.DataPtr;
  for i := 0 to N - 1 do
  begin
    Phase := Frac(f0 * i / SynthFs);                      // 0 .. 1 within the period
    if Phase < 0.5 then SqP[i] := 1.0 else SqP[i] := -1.0;
    TriP[i] := 1.0 - 4.0 * Abs(Phase - 0.5);              // -1 at 0, +1 at 1/2, -1 at 1
  end;

  // time plot: the first four periods, so the shape is visible at any f0
  NShow := Min(N, Round(4 * SynthFs / f0));
  TShow := SubMatrix(T, 0, 0, 1, NShow);
  case rgWave.ItemIndex of
    0: Title := 'Square wave';
    1: Title := 'Triangle wave';
  else Title := 'Square and triangle waves';
  end;
  FSynthTime.Title := Format('%s, f0 = %.3g Hz, unit amplitude - first %d periods of the %.0f s signal', [Title, f0, 4, SynthDuration]);

  // spectra
  ComputePSD(Sq, SynthFs, F, PSq, NBins, Sw2);
  ComputePSD(Tri, SynthFs, dummyF, PTri, dummyN, dummyS);

  // the chosen series, in a fixed order with fixed colours, whichever are on
  SetLength(TimeSeries, 2);
  SetLength(SpecSeries, 2);
  nSer := 0;
  if ShowSq then
  begin
    TimeSeries[nSer] := SubMatrix(Sq, 0, 0, 1, NShow);
    SpecSeries[nSer] := PSq;
    FSynthTime.SetSeriesStyle(nSer, clBlue, 1.5, plsSolid, 'square');
    FSynthSpec.SetSeriesStyle(nSer, clBlue, 1.0, plsSolid, 'square');
    Inc(nSer);
  end;
  if ShowTri then
  begin
    TimeSeries[nSer] := SubMatrix(Tri, 0, 0, 1, NShow);
    SpecSeries[nSer] := PTri;
    FSynthTime.SetSeriesStyle(nSer, $2CA02C, 1.5, plsSolid, 'triangle');
    FSynthSpec.SetSeriesStyle(nSer, $2CA02C, 1.0, plsSolid, 'triangle');
    Inc(nSer);
  end;
  SetLength(TimeSeries, nSer);
  SetLength(SpecSeries, nSer);

  FSynthTime.ClearSeries;
  FSynthTime.SetData(TShow, TimeSeries);
  FSynthSpec.YAxisTitle := SpectrumYTitle('unit');
  FSynthSpec.Title := Format('Power spectral density, Hamming window, N = %d, %.3f Hz resolution, to %.1f Hz', [N, SynthFs / N, F[0, F.Cols - 1]]);
  FSynthSpec.ClearSeries;
  FSynthSpec.SetData(F, SpecSeries);

  // memo: theory against the measured harmonic amplitudes (always from the
  // linear PSD, whatever the check box says)
  WasLinear := cbLinear.Checked;
  cbLinear.OnChange := nil;
  cbLinear.Checked := True;
  ComputePSD(Sq, SynthFs, dummyF, PSqLin, dummyN, dummyS);
  ComputePSD(Tri, SynthFs, dummyF, PTriLin, dummyN, dummyS);
  cbLinear.Checked := WasLinear;
  cbLinear.OnChange := @cbLinearChange;
  Fres := SynthFs / N;

  memSynth.Lines.BeginUpdate;
  try
    memSynth.Clear;
    memSynth.Lines.Add('Synthetic signals (no PhysioNet record)');
    memSynth.Lines.Add('Showing:            ' + Title);
    memSynth.Lines.Add(Format('Fundamental f0:     %.6g Hz', [f0]));
    memSynth.Lines.Add(Format('Sampling frequency: %.6g Hz', [SynthFs]));
    memSynth.Lines.Add(Format('Duration:           %.0f s  (%d samples)', [SynthDuration, N]));
    memSynth.Lines.Add('Amplitude:          1 (peak), zero mean');
    memSynth.Lines.Add('Units:              dimensionless');
    memSynth.Lines.Add('');
    memSynth.Lines.Add('Spectrum: mean removed, Hamming window,');
    memSynth.Lines.Add(Format('  FFT length %d, %d bins to Nyquist', [N, NBins]));
    memSynth.Lines.Add(Format('  resolution %.4f Hz, Nyquist %.1f Hz', [Fres, SynthFs / 2]));
    memSynth.Lines.Add('');
    memSynth.Lines.Add('Fourier series, odd harmonics n only:');
    if ShowSq then
      memSynth.Lines.Add('  square:   a_n = 4/(pi n)      ~ 1/n,   -20 dB/decade');
    if ShowTri then
      memSynth.Lines.Add('  triangle: a_n = 8/(pi^2 n^2)  ~ 1/n^2, -40 dB/decade');
    memSynth.Lines.Add('');
    memSynth.Lines.Add('Harmonic amplitude, theory / measured, the');
    memSynth.Lines.Add('latter as sqrt(2 sum P df) over +-5 bins:');
    Title := '  n  f (Hz)';
    if ShowSq then Title := Title + '  square       ';
    if ShowTri then Title := Title + '  triangle';
    memSynth.Lines.Add(Title);
    // (the linear PSDs are cut at the upper-frequency limit like the plots,
    // so only harmonics inside that range can be measured)
    h := 1;
    while (h <= 15) and (Round(h * f0 / Fres) + 5 < PSqLin.Cols) do
    begin
      k := Round(h * f0 / Fres);
      k0 := Max(0, k - 5); k1 := Min(PSqLin.Cols - 1, k + 5);
      SumSq := 0; SumTri := 0;
      for i := k0 to k1 do
      begin
        SumSq := SumSq + PSqLin[0, i];
        SumTri := SumTri + PTriLin[0, i];
      end;
      ASq := Sqrt(2 * SumSq * Fres);
      ATri := Sqrt(2 * SumTri * Fres);
      Title := Format(' %2d %7.2f', [h, h * f0]);
      if ShowSq then Title := Title + Format('  %.4f/%.4f', [4 / (Pi * h), ASq]);
      if ShowTri then Title := Title + Format('  %.5f/%.5f', [8 / (Sqr(Pi) * h * h), ATri]);
      memSynth.Lines.Add(Title);
      Inc(h, 2);
    end;
    memSynth.Lines.Add('');
    memSynth.Lines.Add('Even harmonics are absent; the small');
    memSynth.Lines.Add('values between peaks are the Hamming window''s');
    memSynth.Lines.Add('sidelobes, and sampling makes the square wave''s');
    memSynth.Lines.Add('edges land on sample instants, which slightly');
    memSynth.Lines.Add('perturbs its higher harmonics.');
  finally
    memSynth.Lines.EndUpdate;
  end;
end;

end.
