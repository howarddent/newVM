unit ubiospectramain;

{*******************************************************************************

     Main form for the BioSpectra demo: the time-domain trace and the power
     spectral density of three biological signals, one per tab - an ECG, an
     EEG and an invasive arterial blood pressure - each a 20-second excerpt
     of a PhysioNet record kept in data/ (see data/README.md for the
     records, byte ranges and licence) - then a fourth tab of frontal EEG
     under anaesthesia from VitalDB, and synthetic square and triangle
     waves, their Fourier synthesis, an EEG bispectrum and the bispectrum
     of the anaesthesia EEG after that, and last a clean and a distorted
     guitar note.

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
     f = k fs/N from 0 up to fs/2, the Nyquist frequency, either as Pxx
     itself - the "linear scale" box, ticked by default - or in decibels,
     (10/ln 10) * Ln(Pxx). The window and PSD scaling follow the usual periodogram
     definition, so a pure tone of amplitude A integrates to A^2/2 across
     its peak.

     An upper-frequency spin edit applies to all tabs; at 0 each signal
     uses its own default - 40 Hz for the ECG and both EEGs and 20 Hz for
     the arterial pressure, whose structure sits far below their Nyquist
     frequencies, and Nyquist for the synthetic signals.
     EEG spectra also start at 0.5 Hz, the conventional lower limit and
     delta's lower edge: below it the frontal lead's drift and eye
     movements peak 2-16 times higher than anything in the bands
     (measured on the three anaesthesia excerpts), which in linear units
     flattens the rest of the spectrum. Both EEG spectra carry the
     clinical bands - delta 0.5-4, theta 4-8, alpha 8-13, beta 13-30 Hz,
     gamma beyond - as labelled colour bars along the top of the plot and
     a faint tint beneath (TVMPlot2D's AddXBand).

     ANAESTHESIA EEG (the fourth tab)

     Frontal EEG in four states, in order of depth: awake, sedated,
     propofol maintenance and burst suppression. Three come from one
     anaesthetic in VitalDB (Seoul National
     University Hospital's open intra-operative database, CC BY 4.0, also
     on PhysioNet as vitaldb): case 655, a 52-year-old man having a
     videoscopic liver sectionectomy under total intravenous anaesthesia -
     propofol and remifentanil by target-controlled infusion, no volatile
     agent. The signal is the BIS Vista's channel 1 (BIS/EEG1_WAV), 128 Hz,
     in uV. Three 20 s excerpts, picked for clean signal by the case
     search data/README.md describes: awake before
     induction (BIS 94), maintenance (BIS 46, propofol Ce 4.0 ug/ml) and
     burst suppression (BIS 16, suppression ratio 61 %, later in the case
     when the propofol target went up to 5). VitalDB is not WFDB, so the
     data/ files are plain CSV - the three excerpts as columns, a 10 s
     trend of BIS, SQI, SR and both effect-site concentrations, and a few
     fields from the case table - read by LoadVitalDB.

     The sedated state comes from a second patient, case 574: a
     67-year-old woman having a peritoneal dialysis catheter removed under
     sedation-analgesia. Her propofol Ce is held at 1.0 ug/ml with
     remifentanil at 1.0 ng/ml, BIS ~84. Its files are the same kinds,
     vitaldb_574_*, with one column. Each case is a TAnaesCase (trend plus
     details); AnaesStateCase says which case each state comes from, and
     the trend plot shows the chosen state's case. At this light level the
     EEG is still awake-like: about the same power, the alpha still the
     ~9 Hz resting rhythm, and a little more beta. The slow waves and the
     frontal 11 Hz alpha appear only nearer loss of consciousness. It is a
     different patient, so the comparison is of spectral shape more than
     absolute power.

     The tab shows the whole-case trend at the top (BIS, SR, propofol
     Ce x10 to share the 0-100 axis, a dashed line at each excerpt,
     plotted point by point with PlotXY so each series can skip its own
     gaps), then the time trace and the PSD of the excerpt picked in the
     radio group, the PSD with the EEG bands marked. Stepping through the
     four shows the change: under propofol the power rises eightfold, slow-delta waves appear, and a frontal
     alpha near 11 Hz takes over (about ten times the awake alpha power,
     which peaks at ~9 Hz), while beta halves; in burst suppression the
     power falls back as the EEG goes flat between bursts. The memo
     tabulates BIS, SQI, SR and the concentrations over each excerpt, the
     RMS, the 0.5-30 Hz power with the delta/theta/alpha/beta shares
     (integrated from the linear PSD, ComputePSD's LinearFull option, so
     they ignore the dB and upper-frequency settings), the alpha power
     and the 7-14 Hz peak frequency.

     --snapshot=<prefix> opens this tab, saves its plots (<prefix>_trend,
     _time0..3 and _spectrum0..3 .png, one per excerpt), the whole window
     (<prefix>_window.bmp) and the EEG tab's spectrum
     (<prefix>_eeg_spectrum.png; _ecg_ and _abp_spectrum likewise), then the anaesthesia bispectrum tab's
     window for each display and state (<prefix>_bispectrumB0..3.bmp for
     |B|, _bispectrumdB0..3 for |B| in dB, _bispectrumb0..3 for
     bicoherence - TVMPlot3D has
     no SaveToPNG, but under GTK2 the form image includes the GL area),
     prints both tabs' memos and exits - for checking them unattended.

     SQUARE AND TRIANGLE WAVES (the fifth tab)

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

     SQUARE-WAVE SYNTHESIS (the sixth tab)

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

     EEG BISPECTRUM (the seventh tab)

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

     A "Signal" radio group swaps the EEG for a synthetic test signal that
     shows what quadratic phase coupling looks like when it is definitely
     there: two sine waves at fa and fb (spin edits, default 6 and 10 Hz)
     with random starting phases, put through the memoryless nonlinearity

       y = x + k x^2        (k from a spin edit, default 0.5)

     plus a little white noise. The square term is the whole point: with
     x = sin(2 pi fa t + pa) + sin(2 pi fb t + pb) it generates
     intermodulation products at 2fa, 2fb, fa+fb and |fa-fb| (and DC),
     every one of them with a phase that is a fixed combination of pa and
     pb - 2pa, 2pb, pa+pb, pa-pb - so each is phase-LOCKED to the two
     tones that made it. The bispectrum is built to detect exactly that:
     the bicoherence shows sharp peaks at (fa, fa), (fb, fb), (fb, fa) and
     (fb, fb-fa) - every pair of frequencies whose sum is one of the
     products - close to 1, against a floor near 1/sqrt(epochs)
     everywhere else - where the EEG
     shows a mostly flat surface with its low-frequency ridge. The same
     20 s / 300 s lengths and epoching as the EEG are used, the sampling
     rate matching the EEG's 250 Hz so the two are directly comparable, and
     the memo lists the expected peak positions beside what was found. At
     k = 0 the products vanish and so do the peaks, which is the cleanest
     demonstration of all: the power spectrum would still show the two
     tones either way, and only the bispectrum can tell the two cases
     apart.

     ANAESTHESIA BISPECTRUM (the eighth tab)

     The fourth tab's trend and 20 s trace on top (DrawAnaesTrend/
     DrawAnaesTrace, shared by both tabs; here without legends, which
     would cover plots this short - the trend's title names the colours),
     and in place of the PSD the bispectrum or bicoherence of the chosen
     state, on a TVMPlot3D. A bispectrum needs many epochs, so this uses
     300 s of each state (data/vitaldb_655_eeg300.csv, each containing its
     20 s excerpt: awake 745-1045 s, propofol 1890-2190 s, burst
     suppression 8314-8614 s - the last ending with its excerpt because
     the recording has a 16 s gap from 8619 s - and, from case 574,
     sedated 3300-3600 s), 299 epochs of 2 s and a
     bicoherence floor of 0.06. The computation is the seventh tab's,
     moved into ComputeBispectrum so both tabs share it, which gained a
     lower frequency limit: the surface starts at 1 Hz by default (a spin
     edit), because the frontal lead's drift and eye movements in the
     0-0.5 Hz bins make a peak near (0, 0) that otherwise sets the height
     scale and flattens everything else. Three displays: |B|, |B| in dB
     (10 log10 |B| re the surface's maximum, floored at -60 dB - |B|
     grows as amplitude cubed, so even from 1 Hz the delta corner dwarfs
     the rest on a linear scale; -40 dB still left awake and burst
     suppression mostly on the floor) and bicoherence, the default.

     The surface's title carries the state's SynchFastSlow, the BIS
     index's bispectral sub-parameter (Rampil 1998), and the memo all
     four: ln( sum |B| over 0.5-47 Hz / sum |B| over 40-47 Hz ), a band
     taken as the band of the sum frequency f1 + f2 (the published
     description doesn't say; both f1 and f2 in 40-47 Hz would put the sum
     past this 128 Hz EEG's Nyquist frequency), over f2 <= f1 with both
     >= 0.5 Hz - its own pass in SynchFastSlow, since it needs X up to
     47 Hz. Awake 5.35, sedated 3.69, propofol 7.05, burst suppression
     4.11 (the case 655 values matching a numpy calculation exactly): it rises as the fast activity falls away
     under propofol, then drops as the broadband bursts refill 40-47 Hz -
     the depth at which BIS leans on the burst suppression ratio instead.
     Not the monitor's own value, whose details are proprietary. The memo
     tabulates the mean bicoherence of all four states over four regions
     (delta x delta, alpha x alpha, alpha x delta, beta x beta) and each
     one's largest value with both frequencies >= 1 Hz: propofol gathers
     its coupling in the alpha band, peaking at (11.5, 10.5) Hz with 0.49
     - the frontal alpha is not sinusoidal, so its harmonic is locked to
     it - while its beta coupling drops to the floor; awake shows little
     beyond the eye-movement corner (delta 0.38); burst suppression is
     high everywhere (0.92 peak, 0.4-0.6 means), each burst a transient
     whose components start phase-aligned; sedated sits at the bias floor
     everywhere (0.05-0.07, peak 0.22), the nearest to Gaussian noise, and
     has the lowest SynchFastSlow - relatively more 40-47 Hz, most likely
     forehead EMG in an unparalysed patient. Checked against an independent
     numpy calculation, which agreed to two decimals. The awake 300 s
     deliberately avoid 1000-1300 s, where ECG spikes once a second give a
     bicoherence of ~0.9 everywhere.

     GUITAR DISTORTION (the ninth tab)

     Linear against nonlinear amplification, on one guitar note: the open
     G string (G3, 196 Hz) played clean on a nylon-string guitar and
     through heavy distortion on an electric, by the same player
     (Freesound "SpeedY", CC0; data/guitar_*.wav, 4 s at 44.1 kHz, made by
     data/fetch_guitar.py). The clean note is always the left column; the
     right is the distorted recording, or the clean note through a linear
     gain y = g x, or through a simulated soft clipper y = tanh(g x) -
     the controlled comparison, since the recordings also differ in
     instrument. Each column: 25 ms of the waveform from 0.3 s (or the
     whole note, decimated by 8), its PSD relative to its own peak,
     linear or in dB per the "Linear scale" box (linear, the default,
     shows the strong harmonics; dB the weak ones too), and |B| in dB or the bicoherence from ComputeBispectrum
     (0.1 s epochs, 50 Hz to 2 kHz by default, grid capped at 400 bins a
     side). The memo tabulates crest factor, harmonics within 30 dB, power
     above 1 kHz, the share of the |B| triangle within 30 dB of its
     maximum and the mean bicoherence for both. Measured: 6 harmonics
     within 30 dB of the strongest clean against 21 distorted, 0.6 % of
     the power above 1 kHz against 42 %, 0.8 % of the |B| triangle within
     30 dB of its maximum against 4.2 % (numpy agreed); "Clean x gain"
     reproduces the clean column exactly, as linearity says it must, and
     tanh(100 x) takes the crest factor from 17 to 1.7 dB and the |B|
     share to 3.4 %. Bicoherence is high on the harmonic
     lattice for any periodic note - a plucked string's harmonics are
     already phase-locked - so it is |B|'s spread across the lattice, not
     the bicoherence, that shows the distortion; the memo says so.
     Play buttons write the note, scaled to a 0.9 peak, to a temporary
     WAV and play it asynchronously: PlaySound (MMSystem) on Windows,
     paplay or aplay through TProcess on Linux.

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
  {$IFDEF WINDOWS} MMSystem, {$ENDIF}
  {$IFDEF UNIX} Process, {$ENDIF}
  newVM, newVMComplex, uVMPlot2D, uVMPlot3D;

const
  // the band SEF95 is taken over - the same 0.5-30 Hz as the anaesthesia
  // tab's total power and band percentages
  SEFLo = 0.5;
  SEFHi = 30.0;

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
    DefaultFmax: Double;      // spectrum limit when the spin edit is 0 (0 = Nyquist)
    Fmin: Double;             // spectrum starts here (0.5 Hz for EEG)
    EEGBands: Boolean;        // mark delta/theta/alpha/beta on the spectrum
  end;

  { what ComputeBispectrum reports beside the grid }
  TBispecInfo = record
    NumEp, NEp, KMax: Integer;   // epochs, samples per epoch, top bin
    KMin: Integer;               // bottom bin: the grid is (KMax-KMin+1) square
    Fres: Double;                // Hz per bin
    Peak, PeakF1, PeakF2: Double;   // largest value off the axes, and where
  end;

  { One VitalDB case on the anaesthesia tabs: its 10 s trend and its
    details. Trend columns, in Vals order: BIS, SQI (%), SR (%), propofol
    and remifentanil effect-site concentrations; NaN = not recorded. }
  TAnaesCase = record
    Id: string;
    Info: TStringList;          // 'field: value' lines from the case table
    T: array of Double;         // s from case start
    Vals: array[0..4] of array of Double;
  end;

  { TfmBio }

  TfmBio = class(TForm)
    cbAllSums: TCheckBox;
    cbLinear: TCheckBox;
    cbLevelCurves: TCheckBox;
    lblBiFmax: TLabel;
    lblEpoch: TLabel;
    lblFa: TLabel;
    lblFb: TLabel;
    lblK: TLabel;
    pnlBiSynth: TPanel;
    rgBiSignal: TRadioGroup;
    seFa: TFloatSpinEdit;
    seFb: TFloatSpinEdit;
    seK: TFloatSpinEdit;
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
    tsAnaes: TTabSheet;
    tsAnaesBi: TTabSheet;
    tsGuitar: TTabSheet;
    pnlGtrCtl: TPanel;
    rgGtrRight: TRadioGroup;
    lblGtrGain: TLabel;
    seGtrGain: TFloatSpinEdit;
    btnPlayL: TButton;
    btnPlayR: TButton;
    cbGtrWhole: TCheckBox;
    lblGtrFmax: TLabel;
    seGtrFmax: TFloatSpinEdit;
    lblGtrEpoch: TLabel;
    seGtrEpoch: TFloatSpinEdit;
    rgGtrKind: TRadioGroup;
    memGtr: TMemo;
    pnlGtr: TPanel;
    pnlABiCtl: TPanel;
    rgABi: TRadioGroup;
    lblABiFmax: TLabel;
    seABiFmax: TFloatSpinEdit;
    lblABiTo: TLabel;
    seABiFmin: TFloatSpinEdit;
    lblABiEpoch: TLabel;
    seABiEpoch: TFloatSpinEdit;
    rgABiKind: TRadioGroup;
    cbABiLevels: TCheckBox;
    memABi: TMemo;
    pnlABi: TPanel;
    memAnaes: TMemo;
    pnlAnaes: TPanel;
    pnlAnaesCtl: TPanel;
    rgAnaes: TRadioGroup;
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
    procedure AnaesPanelResize(Sender: TObject);
    procedure rgAnaesSelectionChanged(Sender: TObject);
    procedure AnaesBiChange(Sender: TObject);
    procedure cbABiLevelsChange(Sender: TObject);
    procedure AnaesBiPanelResize(Sender: TObject);
    procedure GuitarChange(Sender: TObject);
    procedure GuitarPanelResize(Sender: TObject);
    procedure btnPlayLClick(Sender: TObject);
    procedure btnPlayRClick(Sender: TObject);
  private
    FTabs: array[0..2] of TSignalTab;
    FSynthTime, FSynthSpec: TVMPlot2D;
    FSynTime, FSynSpec: TVMPlot2D;
    FBiPlot: TVMPlot3D;
    FEEGLong: TSignalExcerpt;   // the 300 s EEG excerpt, for the bispectrum only
    FBiSynthPhaseA, FBiSynthPhaseB: Double;   // the tones' random phases, drawn once
    // anaesthesia EEG tab: four states from two VitalDB cases (AnaesStateCase),
    // a 20 s excerpt of each, and each case's trend and details
    FAnaesCases: array[0..1] of TAnaesCase;
    FAnaesEEG: array[0..3] of TVMobj;          // 1 x N, uV
    FAnaesName: array[0..3] of string;
    FAnaesStart: array[0..3] of Double;        // s from its case's start
    FAnaesTrend, FAnaesTime, FAnaesSpec: TVMPlot2D;
    // anaesthesia bispectrum tab: 300 s of each state, its own copies of
    // the trend and trace plots, and the bispectrum surface
    FAnaesLong: array[0..3] of TVMobj;
    FAnaesLongStart: array[0..3] of Double;
    FABiTrend, FABiTime: TVMPlot2D;
    FABiPlot: TVMPlot3D;
    // guitar distortion tab: the two recorded notes, the pair currently
    // shown (left always the clean note), and per column a time trace,
    // a PSD and a bispectrum surface
    FGtrFs: Double;
    FGtrClean, FGtrDist: TVMobj;
    FGtrSig: array[0..1] of TVMobj;
    FGtrCol: array[0..1] of TPanel;
    FGtrTime, FGtrSpec: array[0..1] of TVMPlot2D;
    FGtrBi: array[0..1] of TVMPlot3D;
    {$IFDEF UNIX}
    FPlayer: TProcess;
    {$ENDIF}
    FSnapshot: string;   // --snapshot=<prefix>: save the anaesthesia tab's plots, print its memo, exit
    procedure LoadVitalDB;
    procedure LoadVitalDBEEG(const FileName: string; var Names: array of string;
      var Starts: array of Double; var Data: array of TVMobj);
    procedure LoadAnaesCase(const Id: string; var C: TAnaesCase);
    procedure DrawAnaesTrend(Plot: TVMPlot2D; j: Integer; Compact: Boolean = False);
    procedure DrawAnaesTrace(Plot: TVMPlot2D; j: Integer; Compact: Boolean = False);
    procedure ShowAnaesBispectrum;
    function TrendMean(const C: TAnaesCase; Which: Integer; T0, T1: Double): Double;
    function StateMean(j, Which: Integer; Long: Boolean = False): Double;
    procedure ShowAnaesthesia;
    function LoadWav16(const FileName: string; out Fs: Double): TVMobj;
    procedure SaveWav16(const FileName: string; const Data: TVMobj; Fs: Double);
    procedure StopPlayback;
    procedure PlayGuitar(c: Integer);
    procedure ShowGuitar;
    procedure SnapshotShow(Sender: TObject);
    procedure DoSnapshot(Data: PtrInt);
    function SyntheticBispectrumSignal(N: Integer; Fs: Double): TVMobj;
    { |B| or bicoherence of Data on the (f1, f2) grid up to Fmax (capped at
      Fs/4 so f1 + f2 stays below Nyquist), from Hamming-windowed epochs of
      EpochSec at 50 % overlap; a square matrix, row = f2, column = f1,
      starting at Fmin (bin KMin) - a lower limit keeps the low-frequency
      drift's huge values off the surface, where they flatten the rest }
    function ComputeBispectrum(const Data: TVMobj; Fs, EpochSec, Fmax: Double;
      Bicoh: Boolean; out Info: TBispecInfo; Fmin: Double = 0): TVMobj;
    { BIS's SynchFastSlow - see the function's own comment for the
      definition used }
    function SynchFastSlow(const Data: TVMobj; Fs, EpochSec: Double): Double;
    function DataDir: string;
    function LoadWFDB212(const DatFile, HeaFile: string; SigIndex: Integer;
      StartSec: Double): TSignalExcerpt;
    { one-sided PSD of Data at Fs: F is the frequency axis to the chosen
      upper limit, P the PSD (dB or linear per the check box) cut to match }
    procedure ComputePSD(const Data: TVMobj; Fs: Double; out F, P: TVMobj;
      out NBins: Integer; out Sw2: Double; LinearFull: Boolean = False;
      DefaultFmax: Double = 0; Fmin: Double = 0);
    procedure AddEEGBands(Plot: TVMPlot2D);
    { the frequency below which Pct per cent of Data's power between Lo and
      Hi Hz lies - SEF95 at Pct = 95 - from the linear, full-range PSD }
    function SpectralEdge(const Data: TVMobj; Fs, Pct: Double;
      Lo: Double = SEFLo; Hi: Double = SEFHi): Double;
    procedure MarkSpectralEdge(Plot: TVMPlot2D; Sef: Double);
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
  out NBins: Integer; out Sw2: Double; LinearFull: Boolean; DefaultFmax: Double;
  Fmin: Double);
var
  N, k, kMin, kMax: Integer;
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
  if not (cbLinear.Checked or LinearFull) then
  begin
    // 10 log10, floored 150 dB below the peak: the DC bin is exactly zero
    // after mean removal, and an absolute 1e-30 floor put it at -300 dB,
    // which stretched every dB axis for nothing
    XP := PP.DataPtr;
    Mean := 0;
    for k := 0 to NBins - 1 do if XP[k] > Mean then Mean := XP[k];
    PP := (10 / Ln10) * Ln(AddScalar(PP, Max(Mean * 1e-15, 1e-300)));
  end;

  // frequency axis, cut at the spin edit's upper limit if one is set, or
  // else at the signal's own default (40 Hz ECG/EEG, 20 Hz pressure), or else Nyquist
  Fmax := seFmax.Value;
  if Fmax <= 0 then Fmax := DefaultFmax;
  if LinearFull or (Fmax <= 0) or (Fmax > Fs / 2) then Fmax := Fs / 2;
  kMax := Min(NBins - 1, Trunc(Fmax / Fres));
  // and from Fmin up (EEG: 0.5 Hz - below it the frontal lead's drift and
  // eye movements would swamp a linear plot); never for LinearFull
  kMin := 0;
  if (Fmin > 0) and not LinearFull then kMin := Min(kMax, Ceil(Fmin / Fres - 1e-9));
  F := TVMobj.Create(1, kMax - kMin + 1);
  F.linspace(kMin * Fres, Fres);
  P := SubMatrix(PP, 0, kMin, 1, kMax - kMin + 1);
end;

{ the clinical EEG bands as labelled bars along the top of a spectrum;
  light colours, since the band captions are drawn in black }
procedure TfmBio.AddEEGBands(Plot: TVMPlot2D);
begin
  Plot.ClearXBands;
  Plot.AddXBand(0.5, 4, TColor($E3CEA6), 'delta');    // light blue   (BGR)
  Plot.AddXBand(4, 8, TColor($8ADFB2), 'theta');      // light green
  Plot.AddXBand(8, 13, TColor($6FBFFD), 'alpha');     // light orange
  Plot.AddXBand(13, 30, TColor($999AFB), 'beta');     // light red
  Plot.AddXBand(30, 1000, TColor($D6B2CA), 'gamma');  // lavender, seen only above 30 Hz
end;

{ Cumulative power over the bins from Lo up to Hi, interpolated linearly
  within the bin where it crosses Pct per cent of the total. Each bin's
  power is P[k]*df, taken as spread evenly over [f_k, f_k + df) - the
  same rectangle rule ShowAnaesthesia's band powers use }
function TfmBio.SpectralEdge(const Data: TVMobj; Fs, Pct: Double;
  Lo: Double; Hi: Double): Double;
var
  F, P: TVMobj;
  NBins, k: Integer;
  Sw2, Df, Tot, Cum, Target, Pk: Double;
  FP, PP: PDouble;
begin
  ComputePSD(Data, Fs, F, P, NBins, Sw2, True);
  Df := Fs / Data.Cols;
  FP := F.DataPtr;
  PP := P.DataPtr;
  Tot := 0;
  for k := 0 to F.Cols - 1 do
    if (FP[k] >= Lo) and (FP[k] < Hi) then Tot := Tot + PP[k] * Df;
  Result := NaN;
  if Tot <= 0 then Exit;
  Target := Tot * Pct / 100;
  Cum := 0;
  for k := 0 to F.Cols - 1 do
    if (FP[k] >= Lo) and (FP[k] < Hi) then
    begin
      Pk := PP[k] * Df;
      if Cum + Pk >= Target then
        Exit(FP[k] + Df * (Target - Cum) / Pk);
      Cum := Cum + Pk;
    end;
  Result := Hi;
end;

{ SEF95 as a labelled dashed line on an EEG spectrum }
procedure TfmBio.MarkSpectralEdge(Plot: TVMPlot2D; Sef: Double);
begin
  Plot.ClearXMarkers;
  if not IsNan(Sef) then
    Plot.AddXMarker(Sef, clBlack, Format('SEF95 %.1f Hz', [Sef]));
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
  FTabs[0].DefaultFmax := 40;      // ECG: QRS energy is below ~40 Hz (Nyquist 180)
  FTabs[1].DefaultFmax := 40;      // EEG: delta to gamma's lower end (Nyquist 125)
  FTabs[2].DefaultFmax := 20;      // arterial pressure: heart-rate harmonics (Nyquist 125)
  FTabs[1].Fmin := 0.5;            // the conventional EEG lower limit, as delta's
  FTabs[1].EEGBands := True;
  FEEGLong := LoadWFDB212(DataDir + 'slp01a_600s_300s.dat', DataDir + 'slp01a.hea', 2, 600);
  FEEGLong.Database := 'MIT-BIH Polysomnographic Database (slpdb)';
  Randomize;
  FBiSynthPhaseA := 2 * Pi * Random;
  FBiSynthPhaseB := 2 * Pi * Random;

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
      if EEGBands then AddEEGBands(SpecPlot);

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

  LoadVitalDB;
  FAnaesTrend := TVMPlot2D.Create(Self);
  FAnaesTrend.Parent := pnlAnaes;
  FAnaesTrend.Align := alTop;
  FAnaesTrend.XAxisTitle := 'time from start of case (s)';
  FAnaesTrend.YAxisTitle := 'BIS, SR, Ce';
  FAnaesTime := TVMPlot2D.Create(Self);
  FAnaesTime.Parent := pnlAnaes;
  FAnaesTime.Align := alTop;
  FAnaesTime.XAxisTitle := 'time (s)';
  FAnaesTime.YAxisTitle := 'uV';
  FAnaesSpec := TVMPlot2D.Create(Self);
  FAnaesSpec.Parent := pnlAnaes;
  FAnaesSpec.Align := alClient;
  FAnaesSpec.XAxisTitle := 'frequency (Hz)';
  AddEEGBands(FAnaesSpec);
  AnaesPanelResize(nil);

  FBiPlot := TVMPlot3D.Create(Self);
  FBiPlot.Parent := pnlBi;
  FBiPlot.Align := alClient;
  FBiPlot.XAxisTitle := 'f1 (Hz)';
  FBiPlot.YAxisTitle := 'f2 (Hz)';

  FABiTrend := TVMPlot2D.Create(Self);
  FABiTrend.Parent := pnlABi;
  FABiTrend.Align := alTop;
  FABiTrend.XAxisTitle := 'time from start of case (s)';
  FABiTrend.YAxisTitle := 'BIS, SR, Ce';
  FABiTime := TVMPlot2D.Create(Self);
  FABiTime.Parent := pnlABi;
  FABiTime.Align := alTop;
  FABiTime.XAxisTitle := 'time (s)';
  FABiTime.YAxisTitle := 'uV';
  FABiPlot := TVMPlot3D.Create(Self);
  FABiPlot.Parent := pnlABi;
  FABiPlot.Align := alClient;
  FABiPlot.XAxisTitle := 'f1 (Hz)';
  FABiPlot.YAxisTitle := 'f2 (Hz)';
  AnaesBiPanelResize(nil);

  // guitar distortion tab: two columns, each a time trace, a PSD and a
  // bispectrum surface
  FGtrClean := LoadWav16(DataDir + 'guitar_clean_G3.wav', FGtrFs);
  FGtrDist := LoadWav16(DataDir + 'guitar_distorted_G3.wav', FGtrFs);
  for i := 0 to 1 do
  begin
    FGtrCol[i] := TPanel.Create(Self);
    FGtrCol[i].Parent := pnlGtr;
    FGtrCol[i].BevelOuter := bvNone;
    if i = 0 then FGtrCol[i].Align := alLeft else FGtrCol[i].Align := alClient;
    FGtrTime[i] := TVMPlot2D.Create(Self);
    FGtrTime[i].Parent := FGtrCol[i];
    FGtrTime[i].Align := alTop;
    FGtrTime[i].XAxisTitle := 'time (s)';
    FGtrTime[i].YAxisTitle := 'amplitude';
    FGtrSpec[i] := TVMPlot2D.Create(Self);
    FGtrSpec[i].Parent := FGtrCol[i];
    FGtrSpec[i].Align := alTop;
    FGtrSpec[i].XAxisTitle := 'frequency (Hz)';
    FGtrBi[i] := TVMPlot3D.Create(Self);
    FGtrBi[i].Parent := FGtrCol[i];
    FGtrBi[i].Align := alClient;
    FGtrBi[i].XAxisTitle := 'f1 (Hz)';
    FGtrBi[i].YAxisTitle := 'f2 (Hz)';
  end;
  GuitarPanelResize(nil);

  ShowAll;
  ShowAnaesBispectrum;   // not in ShowAll: the PSD settings don't touch it

  // creating the GL controls on each sheet brings that sheet forward, so
  // the form would otherwise open on the last tab filled
  pcSignals.ActivePage := tsECG;

  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then
    OnShow := @SnapshotShow;
end;

procedure TfmBio.SnapshotShow(Sender: TObject);
begin
  Application.QueueAsyncCall(@DoSnapshot, 0);
end;

{ --snapshot=<prefix>: shows the anaesthesia tab (a never-shown tab's GL
  controls have no context), saves its trend, spectrum and each excerpt's
  time trace as <prefix>_trend.png, _spectrum.png, _time<n>.png, the
  window on the anaesthesia bispectrum and guitar tabs for each choice
  (_bispectrum*.bmp, _guitar_<dB|bicoh><n>.bmp), prints the memos and exits - for checking the tab without clicking through it }
procedure TfmBio.DoSnapshot(Data: PtrInt);
const
  KindTag: array[0..2] of string = ('B', 'dB', 'b');
  GtrTag: array[0..1] of string = ('dB', 'bicoh');   // not B/b: Windows file names ignore case
var
  i, j, k: Integer;
begin
  pcSignals.ActivePage := tsAnaes;
  Application.ProcessMessages;
  for i := 0 to rgAnaes.Items.Count - 1 do
  begin
    rgAnaes.ItemIndex := i;
    ShowAnaesthesia;
    Application.ProcessMessages;
    FAnaesTime.SaveToPNG(Format('%s_time%d.png', [FSnapshot, i]));
    FAnaesSpec.SaveToPNG(Format('%s_spectrum%d.png', [FSnapshot, i]));
  end;
  FAnaesTrend.SaveToPNG(FSnapshot + '_trend.png');
  with GetFormImage do
  try
    SaveToFile(FSnapshot + '_window.bmp');
  finally
    Free;
  end;
  pcSignals.ActivePage := tsEEG;
  Application.ProcessMessages;
  FTabs[1].SpecPlot.SaveToPNG(FSnapshot + '_eeg_spectrum.png');
  pcSignals.ActivePage := tsECG;
  Application.ProcessMessages;
  FTabs[0].SpecPlot.SaveToPNG(FSnapshot + '_ecg_spectrum.png');
  pcSignals.ActivePage := tsABP;
  Application.ProcessMessages;
  FTabs[2].SpecPlot.SaveToPNG(FSnapshot + '_abp_spectrum.png');
  pcSignals.ActivePage := tsAnaesBi;
  Application.ProcessMessages;
  for k := 0 to 2 do               // |B|, |B| in dB, bicoherence
    for i := 0 to rgABi.Items.Count - 1 do
    begin
      rgABiKind.ItemIndex := k;
      rgABi.ItemIndex := i;
      ShowAnaesBispectrum;
      Application.ProcessMessages;
      with GetFormImage do
      try
        SaveToFile(Format('%s_bispectrum%s%d.bmp', [FSnapshot, KindTag[k], i]));
      finally
        Free;
      end;
    end;
  pcSignals.ActivePage := tsGuitar;
  Application.ProcessMessages;
  for k := 0 to 1 do               // |B| in dB, bicoherence
    for i := 0 to rgGtrRight.Items.Count - 1 do
    begin
      rgGtrKind.ItemIndex := k;
      rgGtrRight.ItemIndex := i;
      ShowGuitar;
      Application.ProcessMessages;
      with GetFormImage do
      try
        SaveToFile(Format('%s_guitar_%s%d.bmp', [FSnapshot, GtrTag[k], i]));
      finally
        Free;
      end;
      // GetFormImage leaves the GL areas blank on Windows, so the 2D
      // plots themselves too (TVMPlot3D has no SaveToPNG)
      if k = 0 then
        for j := 0 to 1 do
        begin
          FGtrTime[j].SaveToPNG(Format('%s_guitar_%d_time%d.png', [FSnapshot, i, j]));
          FGtrSpec[j].SaveToPNG(Format('%s_guitar_%d_psd%d.png', [FSnapshot, i, j]));
        end;
      if k = 0 then WriteLn(memGtr.Lines.Text);
    end;
  WriteLn(memAnaes.Lines.Text);
  WriteLn(memABi.Lines.Text);
  Application.Terminate;
end;

procedure TfmBio.FormDestroy(Sender: TObject);
var
  i: Integer;
begin
  StopPlayback;
  for i := 0 to 2 do
    FTabs[i].Signal.HeaderLines.Free;
  FEEGLong.HeaderLines.Free;
  FAnaesCases[0].Info.Free;
  FAnaesCases[1].Info.Free;
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

{ Two tones through y = x + k x^2 plus noise - see the unit comment. The
  tones' phases are drawn once (FormCreate) and kept, so changing k or the
  frequencies re-synthesises the same realisation rather than a new one. }
function TfmBio.SyntheticBispectrumSignal(N: Integer; Fs: Double): TVMobj;
var
  T, X: TVMobj;
  k: Double;
  i: Integer;
  P: PDouble;
begin
  T := TVMobj.Create(1, N);
  T.linspace(0, 1 / Fs);
  k := seK.Value;
  X := Sin(AddScalar((2 * Pi * seFa.Value) * T, FBiSynthPhaseA))
     + Sin(AddScalar((2 * Pi * seFb.Value) * T, FBiSynthPhaseB));
  Result := X + k * Sqr(X);                        // the nonlinearity
  P := Result.DataPtr;
  for i := 0 to N - 1 do
    P[i] := P[i] + 0.05 * RandG(0, 1);             // a little white noise
end;

function TfmBio.ComputeBispectrum(const Data: TVMobj; Fs, EpochSec, Fmax: Double;
  Bicoh: Boolean; out Info: TBispecInfo; Fmin: Double): TVMobj;
var
  Fres, Mean, Sw2, Peak, PeakF1, PeakF2, Mag, Denom: Double;
  NTotal, NEp, Hop, NumEp, NBins, KMax, KMin, e, i, k, k1, k2: Integer;
  Theta, W, Seg, Segw, Grid: TVMobj;
  X: TVMobjZ;
  Xr, Xi: TVMobj;
  SP, WP: PDouble;
  // accumulators on the (k1, k2) grid, k2 <= k1
  Bre, Bim, P12, P3: array of array of Double;
  Pk: array of Double;   // E|X(k)|^2
  a1, b1, a2, b2, a3, b3, re, im: Double;
begin
  NTotal := Data.Cols;
  NEp := Round(EpochSec * Fs);
  if NEp > NTotal then NEp := NTotal;
  Hop := Max(1, NEp div 2);                     // 50 % overlap
  NumEp := (NTotal - NEp) div Hop + 1;
  NBins := NEp div 2 + 1;
  Fres := Fs / NEp;
  if (Fmax <= 0) or (Fmax > Fs / 4) then Fmax := Fs / 4;   // f1 + f2 must stay below Nyquist
  KMax := Min(Trunc(Fmax / Fres), (NBins - 1) div 2);
  KMin := 0;
  if Fmin > 0 then KMin := Min(KMax, Ceil(Fmin / Fres - 1e-9));

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
    Seg := SubMatrix(Data, 0, e * Hop, 1, NEp);
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
  Grid := TVMobj.Create(KMax - KMin + 1, KMax - KMin + 1);
  Peak := 0; PeakF1 := 0; PeakF2 := 0;
  for k1 := KMin to KMax do
    for k2 := KMin to k1 do
    begin
      Mag := Sqrt(Sqr(Bre[k1, k2]) + Sqr(Bim[k1, k2]));
      if Bicoh then
      begin
        Denom := Sqrt(P12[k1, k2] * P3[k1, k2]);
        if Denom > 0 then Mag := Mag / Denom else Mag := 0;
      end
      else
        Mag := Mag / (NumEp * Power(Fs * Sw2, 1.5));
      Grid[k2 - KMin, k1 - KMin] := Mag;    // row = f2, column = f1
      Grid[k1 - KMin, k2 - KMin] := Mag;
      if (Mag > Peak) and (k1 > 0) and (k2 > 0) then
      begin
        Peak := Mag; PeakF1 := k1 * Fres; PeakF2 := k2 * Fres;
      end;
    end;


  Info.NumEp := NumEp;
  Info.NEp := NEp;
  Info.KMax := KMax;
  Info.KMin := KMin;
  Info.Fres := Fres;
  Info.Peak := Peak;
  Info.PeakF1 := PeakF1;
  Info.PeakF2 := PeakF2;
  Result := Grid;
end;

{ SynchFastSlow, the bispectral sub-parameter of the BIS index (Rampil,
  Anesthesiology 1998):  ln( sum |B| over 0.5-47 Hz / sum |B| over 40-47 Hz ).
  The published description doesn't say how a band maps onto the (f1, f2)
  plane; here it is the band the SUM frequency f1 + f2 falls in - the
  only reading that fits a 128 Hz EEG, since f1 and f2 both in 40-47 Hz
  would put f1 + f2 beyond the 64 Hz Nyquist frequency. Sums run over the
  non-redundant triangle f2 <= f1 with f1, f2 >= 0.5 Hz; |B| is the
  magnitude of the epoch-averaged triple product (any scale factor
  cancels in the ratio). Natural log. Epochs, window and overlap as
  ComputeBispectrum. Needs X up to 47 Hz, beyond the plotted grid, so it
  is a separate pass. Checked against an independent numpy calculation. }
function TfmBio.SynchFastSlow(const Data: TVMobj; Fs, EpochSec: Double): Double;
var
  NTotal, NEp, Hop, NumEp, NBins, KTop, KLo, K40, e, i, k1, k2: Integer;
  Fres, Mean, Total, Fast, Mag, a1, b1, a2, b2, a3, b3, re, im: Double;
  Theta, W, Seg, Segw, Xr, Xi: TVMobj;
  X: TVMobjZ;
  SP: PDouble;
  Bre, Bim: array of array of Double;
begin
  Result := NaN;
  NTotal := Data.Cols;
  NEp := Min(Round(EpochSec * Fs), NTotal);
  Hop := Max(1, NEp div 2);
  NumEp := (NTotal - NEp) div Hop + 1;
  NBins := NEp div 2 + 1;
  Fres := Fs / NEp;
  KTop := Round(47 / Fres);
  KLo := Max(1, Round(0.5 / Fres));
  K40 := Round(40 / Fres);
  if KTop > NBins - 1 then Exit;                 // 47 Hz must be below Nyquist

  Theta := TVMobj.Create(1, NEp);
  Theta.linspace(0, 2 * Pi / (NEp - 1));
  W := AddScalar((-0.46) * Cos(Theta), 0.54);
  SetLength(Bre, KTop + 1, KTop + 1);
  SetLength(Bim, KTop + 1, KTop + 1);
  for e := 0 to NumEp - 1 do
  begin
    Seg := SubMatrix(Data, 0, e * Hop, 1, NEp);
    SP := Seg.DataPtr;
    Mean := 0;
    for i := 0 to NEp - 1 do Mean := Mean + SP[i];
    Segw := AddScalar(Seg, -Mean / NEp) * W;
    X := FFT_R2C(Segw);
    Xr := GetRealPart(X);
    Xi := GetImagPart(X);
    for k1 := KLo to KTop do
    begin
      a1 := Xr[0, k1]; b1 := Xi[0, k1];
      for k2 := KLo to Min(k1, KTop - k1) do     // f2 <= f1, f1 + f2 <= 47 Hz
      begin
        a2 := Xr[0, k2]; b2 := Xi[0, k2];
        a3 := Xr[0, k1 + k2]; b3 := Xi[0, k1 + k2];
        re := a1 * a2 - b1 * b2;
        im := a1 * b2 + b1 * a2;
        Bre[k1, k2] := Bre[k1, k2] + re * a3 + im * b3;
        Bim[k1, k2] := Bim[k1, k2] + im * a3 - re * b3;
      end;
    end;
  end;
  Total := 0;
  Fast := 0;
  for k1 := KLo to KTop do
    for k2 := KLo to Min(k1, KTop - k1) do
    begin
      Mag := Sqrt(Sqr(Bre[k1, k2]) + Sqr(Bim[k1, k2]));
      Total := Total + Mag;
      if k1 + k2 >= K40 then Fast := Fast + Mag;
    end;
  if Fast > 0 then Result := Ln(Total / Fast);
end;

procedure TfmBio.ShowBispectrum;
var
  Sig: TSignalExcerpt;
  Fs, Fres, Peak, PeakF1, PeakF2: Double;
  NTotal, NEp, NumEp, KMax: Integer;
  Grid: TVMobj;
  Info: TBispecInfo;
  Bicoh, Synth: Boolean;
  Expected: string;
  fa, fb: Double;
begin
  Synth := rgBiSignal.ItemIndex = 1;
  pnlBiSynth.Visible := Synth;
  if Synth then
  begin
    // same length and rate as the EEG excerpt, so the two are comparable
    Sig := FEEGLong;
    Sig.Data := SyntheticBispectrumSignal(FEEGLong.Data.Cols, FEEGLong.Fs);
    Sig.RecordName := 'synthetic';
    Sig.Description := Format('sin(2 pi %.3g t) + sin(2 pi %.3g t), then y = x + %.3g x^2', [seFa.Value, seFb.Value, seK.Value]);
    Sig.Units := 'unit';
  end
  else
    Sig := FEEGLong;          // the 300 s EEG excerpt, not the EEG tab's 20 s
  Fs := Sig.Fs;
  NTotal := Sig.Data.Cols;
  Bicoh := rgBiKind.ItemIndex = 1;
  Grid := ComputeBispectrum(Sig.Data, Fs, seEpoch.Value, seBiFmax.Value, Bicoh, Info);
  NumEp := Info.NumEp; NEp := Info.NEp; KMax := Info.KMax; Fres := Info.Fres;
  Peak := Info.Peak; PeakF1 := Info.PeakF1; PeakF2 := Info.PeakF2;

  if Synth then Expected := 'Two-tone test signal' else Expected := 'EEG';
  if Bicoh then
  begin
    FBiPlot.Title := Format('%s bicoherence b(f1,f2), %s, %d epochs of %.3g s', [Expected, Sig.RecordName, NumEp, NEp / Fs]);
    FBiPlot.ZAxisTitle := 'bicoherence';
    FBiPlot.ZAxisMin := 0; FBiPlot.ZAxisMax := 1;
  end
  else
  begin
    FBiPlot.Title := Format('%s bispectrum |B(f1,f2)|, %s, %d epochs of %.3g s', [Expected, Sig.RecordName, NumEp, NEp / Fs]);
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
    if Synth then
    begin
      fa := seFa.Value; fb := seFb.Value;
      memBi.Lines.Add('Bispectrum of a synthetic two-tone signal');
      memBi.Lines.Add('Signal:     ' + Sig.Description);
      memBi.Lines.Add('            + white noise, sd 0.05');
      memBi.Lines.Add(Format('Sampling:   %.6g Hz, %d samples (%.1f s)', [Fs, NTotal, NTotal / Fs]));
      memBi.Lines.Add('');
      memBi.Lines.Add('The x^2 term makes intermodulation products');
      memBi.Lines.Add('phase-locked to the tones that produce them:');
      memBi.Lines.Add(Format('  2fa   = %5.1f Hz   phase 2 pa', [2 * fa]));
      memBi.Lines.Add(Format('  2fb   = %5.1f Hz   phase 2 pb', [2 * fb]));
      memBi.Lines.Add(Format('  fa+fb = %5.1f Hz   phase pa + pb', [fa + fb]));
      memBi.Lines.Add(Format('  fb-fa = %5.1f Hz   phase pb - pa', [Abs(fb - fa)]));
      memBi.Lines.Add('so the bicoherence should peak near 1 at');
      memBi.Lines.Add(Format('  (f1, f2) = (%.3g, %.3g), (%.3g, %.3g), (%.3g, %.3g)', [fa, fa, fb, fb, Max(fa, fb), Min(fa, fb)]));
      memBi.Lines.Add(Format('  and (%.3g, %.3g) [the difference tone]', [Max(fa, fb), Abs(fb - fa)]));
      memBi.Lines.Add('and sit near the bias floor elsewhere. Set k = 0');
      memBi.Lines.Add('and the peaks vanish while the power spectrum');
      memBi.Lines.Add('still shows the two tones - only the bispectrum');
      memBi.Lines.Add('separates the two cases.');
    end
    else
    begin
      memBi.Lines.Add('Bispectrum of a 300 s EEG excerpt');
      memBi.Lines.Add('Record:     ' + Sig.RecordName + ' - ' + Sig.Description);
      memBi.Lines.Add(Format('Excerpt:    %.0f s to %.0f s of the record', [Sig.StartSec, Sig.StartSec + NTotal / Fs]));
      memBi.Lines.Add('            (the EEG tab shows its first 20 s)');
      memBi.Lines.Add(Format('Sampling:   %.6g Hz, %d samples (%.1f s)', [Fs, NTotal, NTotal / Fs]));
    end;
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
  ShowAnaesthesia;
  ShowSynthetic;
  ShowSynthesis;
  ShowBispectrum;
  ShowGuitar;
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
  Sw2, Mean, Mn, Mx, Sef: Double;
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
    ComputePSD(Signal.Data, Signal.Fs, F, P, NBins, Sw2, False, DefaultFmax, Fmin);
    SpecPlot.YAxisTitle := SpectrumYTitle(Signal.Units);
    SpecPlot.Title := Format('Power spectral density, Hamming window, N = %d, %.3f Hz resolution, %.4g to %.1f Hz', [N, Signal.Fs / N, F[0, 0], F[0, F.Cols - 1]]);
    SpecPlot.ClearSeries;
    SpecPlot.SetData(F, [P]);
    Sef := NaN;
    if EEGBands then
    begin
      Sef := SpectralEdge(Signal.Data, Signal.Fs, 95);
      MarkSpectralEdge(SpecPlot, Sef);
    end;

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
      if not IsNan(Sef) then
      begin
        Memo.Lines.Add(Format('  SEF95 %.1f Hz: 95%% of the power from', [Sef]));
        Memo.Lines.Add(Format('  %.1f to %.0f Hz lies below it (dashed line)', [SEFLo, SEFHi]));
      end;
      Memo.Lines.Add('');
      Memo.Lines.Add('Header (.hea):');
      Memo.Lines.AddStrings(Signal.HeaderLines);
    finally
      Memo.Lines.EndUpdate;
    end;
  end;
end;

{ --- the anaesthesia EEG tabs (VitalDB cases 655 and 574) ------------------- }

const
  AnaesFs = 128.0;                                        // BIS Vista EEG
  // states in order of depth: awake, sedated, propofol, burst suppression
  AnaesStates = 4;
  AnaesColour: array[0..AnaesStates - 1] of TColor = (clGray, $0000A0FF, clRed, clBlue);   // grey, orange, red, blue
  // which of FAnaesCases each state comes from: 0 = case 655, 1 = case 574
  AnaesStateCase: array[0..AnaesStates - 1] of Integer = (0, 1, 0, 0);
  AnaesShort: array[0..AnaesStates - 1] of string = ('awake', 'sedated', 'propofol', 'burst s.');
  // TAnaesCase.Vals columns
  tvBIS = 0; tvSQI = 1; tvSR = 2; tvPPF = 3; tvRFTN = 4;

{ one of the VitalDB EEG files: '#' comments - one of them naming the
  excerpts and their start times - a header row, then one row per sample
  with a column per excerpt }
procedure TfmBio.LoadVitalDBEEG(const FileName: string; var Names: array of string;
  var Starts: array of Double; var Data: array of TVMobj);
var
  Fmt: TFormatSettings;
  L, Parts, Items: TStringList;
  i, k, n, Row, FirstData: Integer;
  Line, Item: string;
  W: array of PDouble;
  function Num(const S: string): Double;
  begin
    if Trim(S) = '' then Result := NaN else Result := StrToFloat(Trim(S), Fmt);
  end;
begin
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  L := TStringList.Create;
  Parts := TStringList.Create;
  Items := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    Items.Delimiter := ',';
    Items.StrictDelimiter := True;
    L.LoadFromFile(FileName);
    FirstData := -1;
    for i := 0 to L.Count - 1 do
    begin
      Line := L[i];
      if (Line <> '') and (Line[1] = '#') then
      begin
        k := Pos('excerpts starting at', Line);
        if k > 0 then
        begin
          Items.DelimitedText := Copy(Line, Pos(':', Copy(Line, k, MaxInt)) + k, MaxInt);
          for n := 0 to Min(High(Starts), Items.Count - 1) do
          begin
            Item := Trim(Items[n]);
            Names[n] := StringReplace(Copy(Item, 1, LastDelimiter(' ', Item) - 1), '_', ' ', [rfReplaceAll]);
            Starts[n] := Num(Copy(Item, LastDelimiter(' ', Item) + 1, MaxInt));
          end;
        end;
      end
      else if FirstData < 0 then
        FirstData := i + 1;        // this line is the column header
    end;
    n := 0;
    for i := FirstData to L.Count - 1 do
      if Trim(L[i]) <> '' then Inc(n);
    SetLength(W, Length(Data));
    for k := 0 to High(Data) do
    begin
      Data[k] := TVMobj.Create(1, n);
      W[k] := Data[k].DataPtr;
    end;
    Row := 0;
    for i := FirstData to L.Count - 1 do
      if Trim(L[i]) <> '' then
      begin
        Parts.DelimitedText := L[i];
        for k := 0 to High(Data) do W[k][Row] := Num(Parts[k]);
        Inc(Row);
      end;
  finally
    Items.Free;
    Parts.Free;
    L.Free;
  end;
end;

{ one case's trend (time_s,BIS,SQI,SR,PPF_CE,RFTN_CE, empty where not
  recorded) and case-table details }
procedure TfmBio.LoadAnaesCase(const Id: string; var C: TAnaesCase);
var
  Fmt: TFormatSettings;
  L, Parts: TStringList;
  i, k, n: Integer;
  Line: string;
  function Num(const S: string): Double;
  begin
    if Trim(S) = '' then Result := NaN else Result := StrToFloat(Trim(S), Fmt);
  end;
begin
  Fmt := DefaultFormatSettings;
  Fmt.DecimalSeparator := '.';
  C.Id := Id;
  L := TStringList.Create;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ',';
    Parts.StrictDelimiter := True;
    L.LoadFromFile(DataDir + 'vitaldb_' + Id + '_trend.csv');
    SetLength(C.T, L.Count);
    for k := 0 to 4 do SetLength(C.Vals[k], L.Count);
    n := 0;
    for i := 0 to L.Count - 1 do
    begin
      Line := Trim(L[i]);
      if (Line = '') or (Line[1] = '#') or (Pos('time_s', Line) = 1) then Continue;
      Parts.DelimitedText := Line;
      if Parts.Count < 6 then Continue;
      C.T[n] := Num(Parts[0]);
      for k := 0 to 4 do C.Vals[k][n] := Num(Parts[k + 1]);
      Inc(n);
    end;
    SetLength(C.T, n);
    for k := 0 to 4 do SetLength(C.Vals[k], n);
  finally
    Parts.Free;
    L.Free;
  end;
  C.Info := TStringList.Create;
  C.Info.NameValueSeparator := ':';
  C.Info.LoadFromFile(DataDir + 'vitaldb_' + Id + '_case.txt');
end;

{ case 655's three excerpts (awake, propofol, burst suppression) become
  states 0, 2 and 3, case 574's one (sedated) state 1 }
procedure TfmBio.LoadVitalDB;
const
  Slot655: array[0..2] of Integer = (0, 2, 3);
var
  i: Integer;
  Names: array[0..2] of string;
  Starts: array[0..2] of Double;
  Data: array[0..2] of TVMobj;
  Names1: array[0..0] of string;
  Starts1: array[0..0] of Double;
  Data1: array[0..0] of TVMobj;
begin
  LoadAnaesCase('655', FAnaesCases[0]);
  LoadAnaesCase('574', FAnaesCases[1]);

  LoadVitalDBEEG(DataDir + 'vitaldb_655_eeg.csv', Names, Starts, Data);
  for i := 0 to 2 do
  begin
    FAnaesName[Slot655[i]] := Names[i];
    FAnaesStart[Slot655[i]] := Starts[i];
    FAnaesEEG[Slot655[i]] := Data[i];
  end;
  LoadVitalDBEEG(DataDir + 'vitaldb_655_eeg300.csv', Names, Starts, Data);
  for i := 0 to 2 do
  begin
    FAnaesLongStart[Slot655[i]] := Starts[i];
    FAnaesLong[Slot655[i]] := Data[i];
  end;

  LoadVitalDBEEG(DataDir + 'vitaldb_574_eeg.csv', Names1, Starts1, Data1);
  FAnaesName[1] := Names1[0];
  FAnaesStart[1] := Starts1[0];
  FAnaesEEG[1] := Data1[0];
  LoadVitalDBEEG(DataDir + 'vitaldb_574_eeg300.csv', Names1, Starts1, Data1);
  FAnaesLongStart[1] := Starts1[0];
  FAnaesLong[1] := Data1[0];
end;

{ mean of one of a case's trends over [T0, T1], ignoring gaps; NaN if
  nothing recorded }
function TfmBio.TrendMean(const C: TAnaesCase; Which: Integer; T0, T1: Double): Double;
var
  k, n: Integer;
begin
  Result := 0;
  n := 0;
  for k := 0 to High(C.T) do
    if (C.T[k] >= T0) and (C.T[k] <= T1) and not IsNan(C.Vals[Which][k]) then
    begin
      Result := Result + C.Vals[Which][k];
      Inc(n);
    end;
  if n > 0 then Result := Result / n else Result := NaN;
end;

{ state j's mean of trend Which over its 20 s excerpt, or (Long) its 300 s }
function TfmBio.StateMean(j, Which: Integer; Long: Boolean): Double;
begin
  if Long then
    Result := TrendMean(FAnaesCases[AnaesStateCase[j]], Which,
      FAnaesLongStart[j], FAnaesLongStart[j] + FAnaesLong[j].Cols / AnaesFs)
  else
    Result := TrendMean(FAnaesCases[AnaesStateCase[j]], Which,
      FAnaesStart[j], FAnaesStart[j] + FAnaesEEG[j].Cols / AnaesFs);
end;

procedure TfmBio.AnaesPanelResize(Sender: TObject);
begin
  if Assigned(FAnaesTrend) then
  begin
    // two alTop controls stack by Top, so pin it: trend first, then the trace
    FAnaesTrend.Top := 0;
    FAnaesTrend.Height := pnlAnaes.Height * 32 div 100;
    FAnaesTime.Top := FAnaesTrend.Height;
    FAnaesTime.Height := pnlAnaes.Height * 28 div 100;
  end;
end;

procedure TfmBio.rgAnaesSelectionChanged(Sender: TObject);
begin
  if Assigned(FAnaesTime) then
    ShowAnaesthesia;
end;

{ 'Propofol, BIS ~45' -> 'propofol, BIS ~45': only the first letter, so
  BIS keeps its capitals }
function LowerFirst(const S: string): string;
begin
  Result := S;
  if Result <> '' then Result[1] := LowerCase(Result[1]);
end;

{ the whole of the chosen state's case: BIS, suppression ratio and
  propofol effect-site concentration (x10 to share the 0-100 axis), with a
  dashed vertical line at the middle of each of that case's 20 s excerpts
  - on both anaesthesia tabs. Compact (the bispectrum tab's shorter plot)
  names the colours in the title instead of a legend, which would cover
  the plot at that height. }
procedure TfmBio.DrawAnaesTrend(Plot: TVMPlot2D; j: Integer; Compact: Boolean);
var
  i, k, c: Integer;
  function Nm(const S: string): string;
  begin
    if Compact then Result := '' else Result := S;
  end;
begin
  c := AnaesStateCase[j];
  Plot.ClearSeries;
  if Compact then
    Plot.Title := Format('Case %s: BIS (black), SR %% (green), propofol Ce x10 (purple)', [FAnaesCases[c].Id])
  else
    Plot.Title := Format('Case %s: BIS, SR (%%), propofol Ce (ug/ml x10) - dashed: excerpts', [FAnaesCases[c].Id]);
  Plot.LegendCorner := lcBottomRight;
  Plot.SetSeriesStyle(0, clBlack, 1.5, plsSolid, Nm('BIS'));
  Plot.SetSeriesStyle(1, clGreen, 1.0, plsSolid, Nm('SR %'));
  Plot.SetSeriesStyle(2, clPurple, 1.5, plsSolid, Nm('propofol Ce x10'));
  with FAnaesCases[c] do
    for k := 0 to High(T) do
    begin
      // BIS 0 with suppression well short of 100 % is a momentary loss of
      // signal, not an isoelectric EEG - left out rather than drawn as a dip
      if not IsNan(Vals[tvBIS][k]) and (Vals[tvBIS][k] > 0) then Plot.PlotXY(T[k], Vals[tvBIS][k], 0);
      if not IsNan(Vals[tvSR][k]) then Plot.PlotXY(T[k], Vals[tvSR][k], 1);
      if not IsNan(Vals[tvPPF][k]) then Plot.PlotXY(T[k], 10 * Vals[tvPPF][k], 2);
    end;
  k := 3;
  for i := 0 to AnaesStates - 1 do
    if AnaesStateCase[i] = c then
    begin
      Plot.SetSeriesStyle(k, AnaesColour[i], 2.0, plsDash, '');
      Plot.PlotXY(FAnaesStart[i] + 10, 0, k);
      Plot.PlotXY(FAnaesStart[i] + 10, 100, k);
      Inc(k);
    end;
end;

{ excerpt j's 20 s time trace }
procedure TfmBio.DrawAnaesTrace(Plot: TVMPlot2D; j: Integer; Compact: Boolean);
var
  T: TVMobj;
begin
  T := TVMobj.Create(1, FAnaesEEG[j].Cols);
  T.linspace(0, 1 / AnaesFs);
  Plot.Title := Format('Frontal EEG, %s - case %s, 20 s from %.0f s',
    [LowerFirst(rgAnaes.Items[j]), FAnaesCases[AnaesStateCase[j]].Id, FAnaesStart[j]]);
  Plot.ClearSeries;
  if Compact then
    Plot.SetSeriesStyle(0, AnaesColour[j], 1.0, plsSolid, '')
  else
    Plot.SetSeriesStyle(0, AnaesColour[j], 1.0, plsSolid, rgAnaes.Items[j]);
  Plot.SetData(T, [FAnaesEEG[j]]);
end;

procedure TfmBio.ShowAnaesthesia;
const
  BandLo: array[0..3] of Double = (0.5, 4, 8, 13);
  BandHi: array[0..3] of Double = (4, 8, 13, 30);
  BandName: array[0..3] of string = ('delta 0.5-4 Hz', 'theta 4-8 Hz', 'alpha 8-13 Hz', 'beta 13-30 Hz');
var
  i, j, k, b, N, NBins: Integer;
  Sw2, Df, Tot, Pk, PkF, Mean, Rms: Double;
  F, FL, P, PL: TVMobj;
  XP, FP: PDouble;
  Band: array[0..AnaesStates - 1, 0..3] of Double;
  TotP, Alpha, RmsV, Sef95, V: array[0..AnaesStates - 1] of Double;
  function C(ci: Integer; const Key: string): string;
  begin
    Result := Trim(FAnaesCases[ci].Info.Values[Key]);
  end;
  function RowN(const Name, Fm: string; const W: array of Double): string;
  var
    m: Integer;
  begin
    Result := Format('%-19s', [Name]);
    for m := 0 to High(W) do
      if IsNan(W[m]) then Result := Result + Format('%9s', ['-'])
      else Result := Result + Format('%9s', [Format(Fm, [W[m]])]);
  end;
  function TrendRow(const Name, Fm: string; Which: Integer): string;
  var
    m: Integer;
  begin
    for m := 0 to AnaesStates - 1 do V[m] := StateMean(m, Which);
    Result := RowN(Name, Fm, V);
  end;
  // at two spaces' indent, broken at spaces to fit the memo's width
  procedure AddWrapped(Text: string);
  const
    Width = 42;
  var
    k: Integer;
  begin
    while Length(Text) > Width do
    begin
      k := Width;
      while (k > 1) and (Text[k] <> ' ') do Dec(k);
      if k <= 1 then k := Width;
      memAnaes.Lines.Add('  ' + Copy(Text, 1, k - 1));
      Delete(Text, 1, k);
    end;
    memAnaes.Lines.Add('  ' + Text);
  end;
  procedure AddPatient(ci: Integer; const States: string);
  begin
    memAnaes.Lines.Add(Format('Case %s (%s):', [C(ci, 'caseid'), States]));
    memAnaes.Lines.Add(Format('  %s y %s, %s cm, %s kg, ASA %s', [C(ci, 'age'), C(ci, 'sex'), C(ci, 'height'), C(ci, 'weight'), C(ci, 'asa')]));
    AddWrapped(C(ci, 'opname') + ' (' + LowerCase(C(ci, 'approach')) + ')');
    memAnaes.Lines.Add('  for ' + LowerCase(C(ci, 'dx')));
    memAnaes.Lines.Add(Format('  anaesthesia %s to %s s, surgery %s to %s s', [C(ci, 'anestart'), C(ci, 'aneend'), C(ci, 'opstart'), C(ci, 'opend')]));
  end;
begin
  if not Assigned(FAnaesTime) then Exit;

  j := rgAnaes.ItemIndex;
  if j < 0 then j := 0;
  DrawAnaesTrend(FAnaesTrend, j);
  N := FAnaesEEG[j].Cols;
  DrawAnaesTrace(FAnaesTime, j);

  // the chosen excerpt's spectrum, to 40 Hz unless the spin edit says
  // otherwise, with the EEG bands marked along the top
  ComputePSD(FAnaesEEG[j], AnaesFs, F, P, NBins, Sw2, False, 40, 0.5);
  FAnaesSpec.YAxisTitle := SpectrumYTitle('uV');
  FAnaesSpec.Title := Format('PSD, %s - Hamming window, %.2f Hz bins', [LowerFirst(rgAnaes.Items[j]), AnaesFs / N]);
  FAnaesSpec.ClearSeries;
  FAnaesSpec.SetSeriesStyle(0, AnaesColour[j], 1.5, plsSolid, rgAnaes.Items[j]);
  FAnaesSpec.SetData(F, [P]);
  MarkSpectralEdge(FAnaesSpec, SpectralEdge(FAnaesEEG[j], AnaesFs, 95));

  // band powers, alpha peak and RMS from the linear, full-range PSD
  for i := 0 to AnaesStates - 1 do
  begin
    ComputePSD(FAnaesEEG[i], AnaesFs, FL, PL, NBins, Sw2, True);
    Df := AnaesFs / FAnaesEEG[i].Cols;
    XP := PL.DataPtr;
    FP := FL.DataPtr;
    Tot := 0;
    for b := 0 to 3 do Band[i, b] := 0;
    Pk := -1;
    PkF := NaN;
    for k := 0 to FL.Cols - 1 do
    begin
      if (FP[k] >= 0.5) and (FP[k] < 30) then Tot := Tot + XP[k] * Df;
      for b := 0 to 3 do
        if (FP[k] >= BandLo[b]) and (FP[k] < BandHi[b]) then
          Band[i, b] := Band[i, b] + XP[k] * Df;
      if (FP[k] >= 7) and (FP[k] <= 14) and (XP[k] > Pk) then
      begin
        Pk := XP[k];
        PkF := FP[k];
      end;
    end;
    TotP[i] := Tot;
    Alpha[i] := PkF;
    Sef95[i] := SpectralEdge(FAnaesEEG[i], AnaesFs, 95);
    XP := FAnaesEEG[i].DataPtr;
    Mean := 0;
    for k := 0 to FAnaesEEG[i].Cols - 1 do Mean := Mean + XP[k];
    Mean := Mean / FAnaesEEG[i].Cols;
    Rms := 0;
    for k := 0 to FAnaesEEG[i].Cols - 1 do Rms := Rms + Sqr(XP[k] - Mean);
    RmsV[i] := Sqrt(Rms / FAnaesEEG[i].Cols);
  end;

  memAnaes.Lines.BeginUpdate;
  try
    memAnaes.Clear;
    memAnaes.Lines.Add('Source:   VitalDB, Seoul National University');
    memAnaes.Lines.Add('          Hospital - open data, CC BY 4.0');
    memAnaes.Lines.Add('          (PhysioNet vitaldb 1.0.0), two cases:');
    AddPatient(0, 'awake, propofol, burst suppression');
    memAnaes.Lines.Add('  general anaesthetic, total intravenous -');
    memAnaes.Lines.Add('  propofol and remifentanil by target-');
    memAnaes.Lines.Add('  controlled infusion (Orchestra), no volatile');
    AddPatient(1, 'sedated');
    memAnaes.Lines.Add('  sedation-analgesia: propofol and');
    memAnaes.Lines.Add('  remifentanil by target-controlled infusion,');
    memAnaes.Lines.Add('  no volatile or nitrous oxide');
    memAnaes.Lines.Add('Times are from each case''s start.');
    memAnaes.Lines.Add('');
    memAnaes.Lines.Add('EEG:      BIS Vista frontal channel 1');
    memAnaes.Lines.Add(Format('          (BIS/EEG1_WAV), %.0f Hz, uV', [AnaesFs]));
    memAnaes.Lines.Add(Format('          20 s excerpts, N = %d, %.3f Hz bins', [N, AnaesFs / N]));
    memAnaes.Lines.Add('');
    memAnaes.Lines.Add(Format('%-19s%9s%9s%9s%9s', ['', AnaesShort[0], AnaesShort[1], AnaesShort[2], AnaesShort[3]]));
    for i := 0 to AnaesStates - 1 do V[i] := StrToFloat(FAnaesCases[AnaesStateCase[i]].Id);
    memAnaes.Lines.Add(RowN('case', '%.0f', V));
    memAnaes.Lines.Add(RowN('start (s)', '%.0f', FAnaesStart));
    memAnaes.Lines.Add(TrendRow('BIS', '%.0f', tvBIS));
    memAnaes.Lines.Add(TrendRow('SQI (%)', '%.0f', tvSQI));
    memAnaes.Lines.Add(TrendRow('suppression (%)', '%.0f', tvSR));
    memAnaes.Lines.Add(TrendRow('propofol Ce ug/ml', '%.1f', tvPPF));
    memAnaes.Lines.Add(TrendRow('remifent. Ce ng/ml', '%.1f', tvRFTN));
    memAnaes.Lines.Add(RowN('RMS (uV)', '%.1f', RmsV));
    memAnaes.Lines.Add(RowN('power 0.5-30 uV^2', '%.0f', TotP));
    for b := 0 to 3 do
    begin
      for i := 0 to AnaesStates - 1 do V[i] := 100 * Band[i, b] / TotP[i];
      memAnaes.Lines.Add(RowN('  ' + BandName[b] + ' %', '%.0f', V));
    end;
    for i := 0 to AnaesStates - 1 do V[i] := Band[i, 2];
    memAnaes.Lines.Add(RowN('alpha power uV^2', '%.0f', V));
    memAnaes.Lines.Add(RowN('peak 7-14 Hz (Hz)', '%.1f', Alpha));
    memAnaes.Lines.Add(RowN('SEF95 (Hz)', '%.1f', Sef95));
    memAnaes.Lines.Add('');
    memAnaes.Lines.Add('What to look for:');
    memAnaes.Lines.Add('- awake: small, broadband EEG with a fair');
    memAnaes.Lines.Add('  share of beta. The ~9 Hz peak is the');
    memAnaes.Lines.Add('  patient''s own resting alpha, reaching');
    memAnaes.Lines.Add('  the forehead from the back of the head;');
    memAnaes.Lines.Add('  the frontal lead also picks up eye');
    memAnaes.Lines.Add('  movement, which lands in delta');
    memAnaes.Lines.Add('- sedated (another patient, case 574):');
    memAnaes.Lines.Add('  propofol Ce 1.0 ug/ml with remifentanil');
    memAnaes.Lines.Add('  1.0 ng/ml takes BIS to the low 80s, yet');
    memAnaes.Lines.Add('  the EEG is still awake-like - the same');
    memAnaes.Lines.Add('  small power, the alpha still the ~9 Hz');
    memAnaes.Lines.Add('  resting rhythm, and more beta, not less');
    memAnaes.Lines.Add('  (the beta "excitation" of light propofol');
    memAnaes.Lines.Add('  sedation). The slow waves and the frontal');
    memAnaes.Lines.Add('  ~11 Hz alpha come only nearer loss of');
    memAnaes.Lines.Add('  consciousness. A different head and');
    memAnaes.Lines.Add('  electrode contact: compare the shape of');
    memAnaes.Lines.Add('  the spectrum more than its absolute power');
    memAnaes.Lines.Add('- propofol: everything grows (power x8),');
    memAnaes.Lines.Add('  large slow-delta waves appear, and the');
    memAnaes.Lines.Add('  alpha is a different rhythm - faster');
    memAnaes.Lines.Add('  (~11 Hz), ten times stronger, generated');
    memAnaes.Lines.Add('  frontally (the "anteriorised" alpha of');
    memAnaes.Lines.Add('  GABAergic anaesthesia); beta falls away');
    memAnaes.Lines.Add('- burst suppression: bursts separated by');
    memAnaes.Lines.Add('  near-flat EEG - deeper than surgery needs,');
    memAnaes.Lines.Add('  BIS in the teens. Being on/off rather');
    memAnaes.Lines.Add('  than stationary, its spectrum is an');
    memAnaes.Lines.Add('  average over two very different states');
    memAnaes.Lines.Add('');
    memAnaes.Lines.Add('BIS/SQI/SR and the effect-site');
    memAnaes.Lines.Add('concentrations are means over each excerpt');
    memAnaes.Lines.Add('from the 10 s trends in data/; the band');
    memAnaes.Lines.Add('powers integrate the linear PSD. SEF95,');
    memAnaes.Lines.Add('the dashed line on the spectrum, is the');
    memAnaes.Lines.Add('frequency below which 95% of the 0.5-30 Hz');
    memAnaes.Lines.Add('power lies - it falls as anaesthesia');
    memAnaes.Lines.Add('deepens and the power moves to slow waves.');
  finally
    memAnaes.Lines.EndUpdate;
  end;
end;

{ --- the anaesthesia bispectrum tab ---------------------------------------- }

procedure TfmBio.AnaesBiPanelResize(Sender: TObject);
begin
  if Assigned(FABiTrend) then
  begin
    FABiTrend.Top := 0;
    FABiTrend.Height := pnlABi.Height * 24 div 100;
    FABiTime.Top := FABiTrend.Height;
    FABiTime.Height := pnlABi.Height * 22 div 100;
  end;
end;

procedure TfmBio.AnaesBiChange(Sender: TObject);
begin
  if Assigned(FABiPlot) then
    ShowAnaesBispectrum;
end;

procedure TfmBio.cbABiLevelsChange(Sender: TObject);
begin
  if Assigned(FABiPlot) then
    FABiPlot.ShowLevelCurves := cbABiLevels.Checked;
end;

procedure TfmBio.ShowAnaesBispectrum;
const
  // regions of the (f1, f2) plane summarised in the memo, Hz
  RegName: array[0..3] of string = ('delta x delta  1-4 Hz', 'alpha x alpha  8-13 Hz', 'alpha x delta', 'beta x beta   13-30 Hz');
  RegF1Lo: array[0..3] of Double = (1, 8, 8, 13);
  RegF1Hi: array[0..3] of Double = (4, 13, 13, 30);
  RegF2Lo: array[0..3] of Double = (1, 8, 1, 13);
  RegF2Hi: array[0..3] of Double = (4, 13, 4, 30);
var
  i, j, r, k1, k2, n: Integer;
  Grid, BGrid: TVMobj;
  Info, BInfo: TBispecInfo;
  Bicoh: Boolean;
  T0, T1, f1, f2, Sum, Mx: Double;
  Reg: array[0..AnaesStates - 1, 0..3] of Double;
  PeakV, PeakA, PeakB, SFS, V: array[0..AnaesStates - 1] of Double;
  SFSText: string;
  function Row3(const Name, Fm: string; const Vs: array of Double): string;
  var
    m: Integer;
  begin
    Result := Format('%-23s', [Name]);
    for m := 0 to High(Vs) do
      if IsNan(Vs[m]) then Result := Result + Format('%9s', ['-'])
      else Result := Result + Format('%9s', [Format(Fm, [Vs[m]])]);
  end;
begin
  j := rgABi.ItemIndex;
  if j < 0 then j := 0;
  DrawAnaesTrend(FABiTrend, j, True);
  DrawAnaesTrace(FABiTime, j, True);

  // SynchFastSlow for all four states: the chosen one goes in the
  // surface's title, all three in the memo
  for i := 0 to AnaesStates - 1 do
    SFS[i] := SynchFastSlow(FAnaesLong[i], AnaesFs, seABiEpoch.Value);
  SFSText := Format(' - SynchFastSlow %.2f', [SFS[j]]);

  // the chosen state's surface
  // 0 = |B|, 1 = |B| in dB re its maximum, 2 = bicoherence
  Bicoh := rgABiKind.ItemIndex = 2;
  // from seABiFmin (default 1 Hz): the 0-0.5 Hz bins hold the frontal
  // lead's drift and eye movements, whose peak near (0, 0) would otherwise
  // set the height scale and flatten everything else
  Grid := ComputeBispectrum(FAnaesLong[j], AnaesFs, seABiEpoch.Value, seABiFmax.Value, Bicoh, Info, seABiFmin.Value);
  if Bicoh then
  begin
    FABiPlot.Title := Format('Bicoherence, %s%s', [LowerFirst(rgAnaes.Items[j]), SFSText]);
    FABiPlot.ZAxisTitle := 'bicoherence';
    FABiPlot.ZAxisMin := 0; FABiPlot.ZAxisMax := 1;
  end
  else if rgABiKind.ItemIndex = 1 then
  begin
    // |B| grows as amplitude cubed, so on a linear scale the delta corner
    // dwarfs everything: 10 log10 |B| re the surface's own maximum,
    // floored at -60 dB, shows the structure elsewhere
    Mx := 0;
    for k1 := 0 to Grid.Rows - 1 do
      for k2 := 0 to Grid.Cols - 1 do
        if Grid[k1, k2] > Mx then Mx := Grid[k1, k2];
    for k1 := 0 to Grid.Rows - 1 do
      for k2 := 0 to Grid.Cols - 1 do
        if (Mx > 0) and (Grid[k1, k2] > Mx * 1e-6) then
          Grid[k1, k2] := 10 * Log10(Grid[k1, k2] / Mx)
        else
          Grid[k1, k2] := -60;
    FABiPlot.Title := Format('Bispectrum |B| in dB, %s%s', [LowerFirst(rgAnaes.Items[j]), SFSText]);
    FABiPlot.ZAxisTitle := '|B| (dB re max)';
    FABiPlot.ZAxisMin := -60; FABiPlot.ZAxisMax := 0;
  end
  else
  begin
    FABiPlot.Title := Format('Bispectrum |B|, %s%s', [LowerFirst(rgAnaes.Items[j]), SFSText]);
    FABiPlot.ZAxisTitle := '|B| (uV^3)';
    FABiPlot.ZAxisMin := 0; FABiPlot.ZAxisMax := 0;   // from the data
  end;
  FABiPlot.XAxisMin := Info.KMin * Info.Fres; FABiPlot.XAxisMax := Info.KMax * Info.Fres;
  FABiPlot.YAxisMin := Info.KMin * Info.Fres; FABiPlot.YAxisMax := Info.KMax * Info.Fres;
  FABiPlot.ShowLevelCurves := cbABiLevels.Checked;
  FABiPlot.SetData(Grid);

  // bicoherence of all four states, whatever is displayed, so the memo
  // can compare them: the mean over each region (f2 <= f1 half), and the
  // largest value with both frequencies at least 1 Hz
  for i := 0 to AnaesStates - 1 do
  begin
    BGrid := ComputeBispectrum(FAnaesLong[i], AnaesFs, seABiEpoch.Value, seABiFmax.Value, True, BInfo);
    for r := 0 to 3 do
    begin
      Sum := 0; n := 0;
      for k1 := 0 to BInfo.KMax do
        for k2 := 0 to k1 do
        begin
          f1 := k1 * BInfo.Fres; f2 := k2 * BInfo.Fres;
          if (f1 >= RegF1Lo[r]) and (f1 < RegF1Hi[r]) and (f2 >= RegF2Lo[r]) and (f2 < RegF2Hi[r]) then
          begin
            Sum := Sum + BGrid[k2, k1];
            Inc(n);
          end;
        end;
      if n > 0 then Reg[i, r] := Sum / n else Reg[i, r] := NaN;
    end;
    PeakV[i] := 0; PeakA[i] := NaN; PeakB[i] := NaN;
    for k1 := 0 to BInfo.KMax do
      for k2 := 0 to k1 do
        if (k2 * BInfo.Fres >= 1) and (BGrid[k2, k1] > PeakV[i]) then
        begin
          PeakV[i] := BGrid[k2, k1];
          PeakA[i] := k1 * BInfo.Fres;
          PeakB[i] := k2 * BInfo.Fres;
        end;
  end;

  T0 := FAnaesLongStart[j];
  T1 := T0 + FAnaesLong[j].Cols / AnaesFs;
  memABi.Lines.BeginUpdate;
  try
    memABi.Clear;
    memABi.Lines.Add('Bispectrum of frontal EEG under anaesthesia');
    memABi.Lines.Add('VitalDB cases 655 and 574, BIS Vista channel 1,');
    memABi.Lines.Add(Format('%.0f Hz', [AnaesFs]));
    memABi.Lines.Add('(details on the Anaesthesia EEG tab)');
    memABi.Lines.Add('');
    memABi.Lines.Add(Format('Shown: %s (case %s)', [rgAnaes.Items[j], FAnaesCases[AnaesStateCase[j]].Id]));
    memABi.Lines.Add(Format('  300 s from %.0f to %.0f s; the trace above is', [T0, T1]));
    memABi.Lines.Add(Format('  its 20 s excerpt from %.0f s', [FAnaesStart[j]]));
    memABi.Lines.Add(Format('  BIS %.0f, SQI %.0f %%, SR %.0f %%, propofol %.1f ug/ml',
      [StateMean(j, tvBIS, True), StateMean(j, tvSQI, True), StateMean(j, tvSR, True), StateMean(j, tvPPF, True)]));
    memABi.Lines.Add('  (means over the 300 s)');
    memABi.Lines.Add(Format('Epochs: %d of %d samples (%.3g s), 50 %% overlap,', [Info.NumEp, Info.NEp, Info.NEp / AnaesFs]));
    memABi.Lines.Add(Format('  Hamming, mean removed; %.3g Hz bins,', [Info.Fres]));
    memABi.Lines.Add(Format('  surface f1, f2 = %.3g to %.4g Hz (the lower limit', [Info.KMin * Info.Fres, Info.KMax * Info.Fres]));
    memABi.Lines.Add('  keeps the low-frequency drift peak off it)');
    if Bicoh then
      memABi.Lines.Add(Format('Bicoherence bias floor ~1/sqrt(epochs) = %.2f', [1 / Sqrt(Info.NumEp)]));
    memABi.Lines.Add('');
    memABi.Lines.Add('Bicoherence, mean over each region (full grid):');
    memABi.Lines.Add(Format('%-23s%9s%9s%9s%9s', ['', AnaesShort[0], AnaesShort[1], AnaesShort[2], AnaesShort[3]]));
    for r := 0 to 3 do
    begin
      for i := 0 to AnaesStates - 1 do V[i] := Reg[i, r];
      memABi.Lines.Add(Row3(RegName[r], '%.2f', V));
    end;
    memABi.Lines.Add(Row3('largest (f1,f2 >= 1 Hz)', '%.2f', PeakV));
    memABi.Lines.Add(Row3('  at f1 (Hz)', '%.1f', PeakA));
    memABi.Lines.Add(Row3('  at f2 (Hz)', '%.1f', PeakB));
    memABi.Lines.Add('');
    memABi.Lines.Add(Row3('SynchFastSlow', '%.2f', SFS));
    memABi.Lines.Add('  = ln( sum|B| 0.5-47 Hz / sum|B| 40-47 Hz ),');
    memABi.Lines.Add('  a band meaning the sum frequency f1 + f2');
    memABi.Lines.Add('  (f2 <= f1, both >= 0.5 Hz). It rises from');
    memABi.Lines.Add('  awake to propofol as fast activity falls');
    memABi.Lines.Add('  away, and drops again in burst suppression,');
    memABi.Lines.Add('  whose broadband bursts refill 40-47 Hz - the');
    memABi.Lines.Add('  depth where BIS relies on the suppression');
    memABi.Lines.Add('  ratio instead. Not the monitor''s own value:');
    memABi.Lines.Add('  BIS''s exact band handling, smoothing and');
    memABi.Lines.Add('  artefact rejection are proprietary.');
    memABi.Lines.Add('');
    memABi.Lines.Add('What to look for:');
    memABi.Lines.Add('- propofol: the coupling gathers in the alpha');
    memABi.Lines.Add('  band, peaking near (11, 11) Hz - the frontal');
    memABi.Lines.Add('  alpha is not a pure sine, so its harmonic');
    memABi.Lines.Add('  near 22 Hz is phase-locked to it - while');
    memABi.Lines.Add('  beta coupling falls to the floor');
    memABi.Lines.Add('- sedated (case 574): flat, at the bias floor');
    memABi.Lines.Add('  in every region - the closest of the four');
    memABi.Lines.Add('  to Gaussian noise. Its SynchFastSlow is the');
    memABi.Lines.Add('  lowest: relatively more 40-47 Hz activity,');
    memABi.Lines.Add('  most likely forehead muscle (EMG) in an');
    memABi.Lines.Add('  unparalysed, lightly sedated patient - which');
    memABi.Lines.Add('  BIS sees too');
    memABi.Lines.Add('- clean data matters as much here: several');
    memABi.Lines.Add('  300 s windows near this one each hold a');
    memABi.Lines.Add('  single huge spike, and there the bicoherence');
    memABi.Lines.Add('  is ~0.7 everywhere');
    memABi.Lines.Add('- awake: little coupling except at low');
    memABi.Lines.Add('  frequencies, where eye movements - sharp,');
    memABi.Lines.Add('  non-sinusoidal - put locked harmonics');
    memABi.Lines.Add('- burst suppression: high everywhere. A burst');
    memABi.Lines.Add('  is a brief transient, so all its frequency');
    memABi.Lines.Add('  components start together, phase-aligned;');
    memABi.Lines.Add('  the signal is far from the stationary noise');
    memABi.Lines.Add('  the bispectrum is usually read against');
    memABi.Lines.Add('- the BIS index uses the bispectrum too: its');
    memABi.Lines.Add('  SynchFastSlow term (above; Rampil,');
    memABi.Lines.Add('  Anesthesiology 1998)');
    memABi.Lines.Add('- artefact matters: this case''s awake EEG at');
    memABi.Lines.Add('  1000-1300 s carries ECG spikes once a second,');
    memABi.Lines.Add('  and there the bicoherence is ~0.9 everywhere -');
    memABi.Lines.Add('  why those 300 s are not the awake excerpt');
    memABi.Lines.Add('');
    memABi.Lines.Add('Drag to rotate, wheel to zoom.');
  finally
    memABi.Lines.EndUpdate;
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

{ ---- guitar distortion tab ---- }

{ A 16-bit PCM WAV as a (1, N) TVMobj in [-1, 1), channels averaged }
function TfmBio.LoadWav16(const FileName: string; out Fs: Double): TVMobj;
var
  B: TBytes;
  fsm: TFileStream;
  p, ChunkSize, Channels, Bits, NFrames, i, ch: Integer;
  ChunkId: string;
  DataPos, DataSize: Integer;
  Sum: Double;
  RP: PDouble;
  function U16(At: Integer): Integer;
  begin
    Result := B[At] or (B[At + 1] shl 8);
  end;
  function Id4(At: Integer): string;
  begin
    Result := Chr(B[At]) + Chr(B[At + 1]) + Chr(B[At + 2]) + Chr(B[At + 3]);
  end;
  function U32(At: Integer): Integer;
  begin
    Result := B[At] or (B[At + 1] shl 8) or (B[At + 2] shl 16) or (B[At + 3] shl 24);
  end;
begin
  fsm := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    SetLength(B, fsm.Size);
    if Length(B) > 0 then fsm.ReadBuffer(B[0], Length(B));
  finally
    fsm.Free;
  end;
  if (Length(B) < 12) or (Id4(0) <> 'RIFF')
    or (Id4(8) <> 'WAVE') then
    raise Exception.Create(FileName + ' is not a WAV file');
  Fs := 0; Channels := 0; Bits := 0; DataPos := -1; DataSize := 0;
  p := 12;
  while p + 8 <= Length(B) do
  begin
    ChunkId := Id4(p);
    ChunkSize := U32(p + 4);
    if ChunkId = 'fmt ' then
    begin
      if U16(p + 8) <> 1 then
        raise Exception.Create(FileName + ': not PCM');
      Channels := U16(p + 10);
      Fs := U32(p + 12);
      Bits := U16(p + 22);
    end
    else if ChunkId = 'data' then
    begin
      DataPos := p + 8;
      DataSize := Min(ChunkSize, Length(B) - DataPos);
    end;
    Inc(p, 8 + ChunkSize + (ChunkSize and 1));   // chunks are word-aligned
  end;
  if (DataPos < 0) or (Bits <> 16) or (Channels < 1) then
    raise Exception.Create(FileName + ': only 16-bit PCM WAV is read');
  NFrames := DataSize div (2 * Channels);
  Result := TVMobj.Create(1, NFrames);
  RP := Result.DataPtr;
  for i := 0 to NFrames - 1 do
  begin
    Sum := 0;
    for ch := 0 to Channels - 1 do
      Sum := Sum + SmallInt(U16(DataPos + 2 * (i * Channels + ch)));
    RP[i] := Sum / (32768.0 * Channels);
  end;
end;

{ Data as a 16-bit mono WAV, normalised to a peak of 0.9 - for playback,
  so every note plays at the same peak level whatever its amplitude here }
procedure TfmBio.SaveWav16(const FileName: string; const Data: TVMobj; Fs: Double);
var
  fsm: TFileStream;
  N, i, Rate: Integer;
  Pk: Double;
  DP: PDouble;
  S: array of SmallInt;
  procedure Tag(const T: string);
  begin
    fsm.WriteBuffer(T[1], 4);
  end;
  procedure W32(V: LongWord);
  begin
    V := NtoLE(V);
    fsm.WriteBuffer(V, 4);
  end;
  procedure W16(V: Word);
  begin
    V := NtoLE(V);
    fsm.WriteBuffer(V, 2);
  end;
begin
  N := Data.Cols * Data.Rows;
  DP := Data.DataPtr;
  Pk := 0;
  for i := 0 to N - 1 do
    if Abs(DP[i]) > Pk then Pk := Abs(DP[i]);
  if Pk = 0 then Pk := 1;
  SetLength(S, N);
  for i := 0 to N - 1 do
    S[i] := NtoLE(SmallInt(Round(0.9 * 32767 * DP[i] / Pk)));
  Rate := Round(Fs);
  fsm := TFileStream.Create(FileName, fmCreate);
  try
    Tag('RIFF'); W32(36 + 2 * N); Tag('WAVE');
    Tag('fmt '); W32(16); W16(1); W16(1); W32(Rate); W32(2 * Rate); W16(2); W16(16);
    Tag('data'); W32(2 * N);
    if N > 0 then fsm.WriteBuffer(S[0], 2 * N);
  finally
    fsm.Free;
  end;
end;

procedure TfmBio.StopPlayback;
begin
  {$IFDEF WINDOWS}
  PlaySound(nil, 0, 0);
  {$ENDIF}
  {$IFDEF UNIX}
  if Assigned(FPlayer) then
  begin
    if FPlayer.Running then FPlayer.Terminate(0);
    FreeAndNil(FPlayer);
  end;
  {$ENDIF}
end;

{ Plays column c's note through the default output device, asynchronously:
  written to a temporary WAV, then PlaySound (Windows) or paplay/aplay
  (Linux). Starting one stops whatever was playing. }
procedure TfmBio.PlayGuitar(c: Integer);
var
  FileName: string;
  {$IFDEF UNIX}
  Exe: string;
  {$ENDIF}
begin
  StopPlayback;
  FileName := GetTempDir(False) + Format('biospectra_guitar_%d.wav', [c]);
  SaveWav16(FileName, FGtrSig[c], FGtrFs);
  {$IF DEFINED(WINDOWS)}
  if not PlaySound(PChar(FileName), 0, SND_FILENAME or SND_ASYNC or SND_NODEFAULT) then
    ShowMessage('Could not play ' + FileName);
  {$ELSEIF DEFINED(UNIX)}
  Exe := ExeSearch('paplay', GetEnvironmentVariable('PATH'));
  if Exe = '' then Exe := ExeSearch('aplay', GetEnvironmentVariable('PATH'));
  if Exe = '' then
  begin
    ShowMessage('Neither paplay nor aplay was found on the PATH');
    Exit;
  end;
  FPlayer := TProcess.Create(nil);
  FPlayer.Executable := Exe;
  FPlayer.Parameters.Add(FileName);
  FPlayer.Execute;
  {$ELSE}
  ShowMessage('Playback is implemented for Windows and Linux only');
  {$ENDIF}
end;

procedure TfmBio.btnPlayLClick(Sender: TObject);
begin
  PlayGuitar(0);
end;

procedure TfmBio.btnPlayRClick(Sender: TObject);
begin
  PlayGuitar(1);
end;

procedure TfmBio.GuitarChange(Sender: TObject);
begin
  if Assigned(FGtrBi[1]) then
    ShowGuitar;
end;

{ two equal columns; in each the trace takes the top 22 %, the PSD the
  next 30 % and the bispectrum the rest. Tops set explicitly: two alTop
  controls created in code stack in no guaranteed order }
procedure TfmBio.GuitarPanelResize(Sender: TObject);
var
  i: Integer;
begin
  if not Assigned(FGtrBi[1]) then Exit;
  FGtrCol[0].Width := pnlGtr.Width div 2;
  for i := 0 to 1 do
  begin
    FGtrTime[i].Top := 0;
    FGtrTime[i].Height := pnlGtr.Height * 22 div 100;
    FGtrSpec[i].Top := FGtrTime[i].Height;
    FGtrSpec[i].Height := pnlGtr.Height * 30 div 100;
  end;
end;

procedure TfmBio.ShowGuitar;
const
  GtrFmin = 50.0;        // Hz: the bispectrum surface starts here, clear of DC and handling noise
  GtrPSDFmax = 8000.0;   // Hz: the PSD's default upper limit (the global spin edit overrides)
  MaxGridBins = 400;     // bispectrum grid side, to bound memory and the 3D mesh
  ColColour: array[0..1] of TColor = (clBlue, clRed);
var
  c, d, i, k, hn, N, NBins, NShow, Step, i0, kF0, k0, k1, NH30, HTop, nTri, nNear: Integer;
  G, Fs, Sw2, Fres, Mx, Lvl, HMax, Tot, Above, Cent, BiSum, Fmax, Epoch: Double;
  T, F, P, Shown, GridB, GridC, Grid, PLin, FLin: TVMobj;
  SP, DP, PP: PDouble;
  Info, InfoC: TBispecInfo;
  Bicoh, Capped: Boolean;
  Lbl, ShortLbl: array[0..1] of string;
  H: array of Double;
  // per column: peak, RMS, crest factor (dB), f0, harmonics within 30 dB,
  // highest harmonic within 40 dB, % power above 1 kHz, spectral centroid,
  // % of the |B| triangle within 30 dB of its maximum, mean bicoherence
  StPeak, StRms, StCrest, StF0, StNH30, StHTop, StAbove, StCent, StNear, StBicoh: array[0..1] of Double;
  function Row2(const RowName, Fm: string; const V: array of Double): string;
  begin
    Result := Format('%-26s%11s%11s', [RowName, Format(Fm, [V[0]]), Format(Fm, [V[1]])]);
  end;
begin
  if not Assigned(FGtrBi[1]) then Exit;   // not yet built
  Fs := FGtrFs;
  G := seGtrGain.Value;
  seGtrGain.Enabled := rgGtrRight.ItemIndex in [1, 2];
  lblGtrGain.Enabled := seGtrGain.Enabled;

  // the pair: the clean note, and the chosen right-hand one
  FGtrSig[0] := FGtrClean;
  Lbl[0] := 'Clean (nylon, recorded)';
  ShortLbl[0] := 'Clean';
  case rgGtrRight.ItemIndex of
    1: begin
         FGtrSig[1] := G * FGtrClean;                    // an ideal linear amplifier
         Lbl[1] := Format('Clean x %g (linear gain)', [G]);
         ShortLbl[1] := Format('Clean x %g', [G]);
       end;
    2: begin
         // a symmetric soft clipper with small-signal gain G; newVM has no
         // elementwise tanh, so a loop
         N := FGtrClean.Cols;
         FGtrSig[1] := TVMobj.Create(1, N);
         SP := FGtrClean.DataPtr;
         DP := FGtrSig[1].DataPtr;
         for i := 0 to N - 1 do DP[i] := Tanh(G * SP[i]);
         Lbl[1] := Format('tanh(%g x clean) (simulated)', [G]);
         ShortLbl[1] := Format('tanh(%g x)', [G]);
       end;
  else
    FGtrSig[1] := FGtrDist;
    Lbl[1] := 'Distorted (electric, recorded)';
    ShortLbl[1] := 'Distorted';
  end;

  // bispectrum settings, the grid capped at MaxGridBins a side
  Epoch := seGtrEpoch.Value;
  Fmax := seGtrFmax.Value;
  Capped := Fmax > MaxGridBins * Fs / Round(Epoch * Fs);
  if Capped then Fmax := MaxGridBins * Fs / Round(Epoch * Fs);
  Bicoh := rgGtrKind.ItemIndex = 1;

  for c := 0 to 1 do
  begin
    N := FGtrSig[c].Cols;

    // time trace: 25 ms (about five periods) from 0.3 s, where the shape
    // shows, or the whole note every 8th sample, where the envelope does
    if cbGtrWhole.Checked then
    begin
      Step := 8;
      NShow := N div Step;
      T := TVMobj.Create(1, NShow);
      T.linspace(0, Step / Fs);
      Shown := TVMobj.Create(1, NShow);
      SP := FGtrSig[c].DataPtr;
      DP := Shown.DataPtr;
      for i := 0 to NShow - 1 do DP[i] := SP[i * Step];
      FGtrTime[c].Title := Format('%s: the whole %.0f s', [ShortLbl[c], N / Fs]);
    end
    else
    begin
      i0 := Round(0.3 * Fs);
      NShow := Round(0.025 * Fs);
      T := TVMobj.Create(1, NShow);
      T.linspace(i0 / Fs, 1 / Fs);
      Shown := SubMatrix(FGtrSig[c], 0, i0, 1, NShow);
      FGtrTime[c].Title := Format('%s: 25 ms from 0.3 s', [ShortLbl[c]]);
    end;
    FGtrTime[c].SetSeriesStyle(0, ColColour[c], 1.0, plsSolid, '');
    FGtrTime[c].ClearSeries;
    FGtrTime[c].SetData(T, [Shown]);

    // PSD, linear or dB per the "Linear scale" box, relative to its own
    // peak (1, or 0 dB) so the two compare by shape - and a linear gain
    // leaves it unchanged, as it should
    ComputePSD(FGtrSig[c], Fs, F, P, NBins, Sw2, False, GtrPSDFmax);
    PP := P.DataPtr;
    Mx := -1e300;
    for i := 0 to P.Cols - 1 do if PP[i] > Mx then Mx := PP[i];
    if cbLinear.Checked then
    begin
      for i := 0 to P.Cols - 1 do PP[i] := PP[i] / Mx;
      FGtrSpec[c].YAxisTitle := 'PSD re peak';
    end
    else
    begin
      for i := 0 to P.Cols - 1 do PP[i] := Max(PP[i] - Mx, -120);
      FGtrSpec[c].YAxisTitle := 'dB re peak';
    end;
    FGtrSpec[c].Title := Format('%s: PSD, %.2f Hz bins', [ShortLbl[c], Fs / N]);
    FGtrSpec[c].SetSeriesStyle(0, ColColour[c], 1.0, plsSolid, '');
    FGtrSpec[c].ClearSeries;
    FGtrSpec[c].SetData(F, [P]);

    // figures for the memo, from the linear PSD to Nyquist
    ComputePSD(FGtrSig[c], Fs, FLin, PLin, NBins, Sw2, True);
    PP := PLin.DataPtr;
    Fres := Fs / N;
    SP := FGtrSig[c].DataPtr;
    StPeak[c] := 0; StRms[c] := 0;
    for i := 0 to N - 1 do
    begin
      if Abs(SP[i]) > StPeak[c] then StPeak[c] := Abs(SP[i]);
      StRms[c] := StRms[c] + Sqr(SP[i]);
    end;
    StRms[c] := Sqrt(StRms[c] / N);
    StCrest[c] := 20 * Log10(StPeak[c] / StRms[c]);
    // f0: the strongest line between 80 Hz and 1 kHz may be a harmonic -
    // the distorted note's 2nd and 3rd outweigh its fundamental - so take
    // the largest divisor d whose 1/d frequency, still >= 80 Hz, carries
    // a line within 20 dB of it
    kF0 := Round(80 / Fres);
    for k := Round(80 / Fres) to Round(1000 / Fres) do
      if PP[k] > PP[kF0] then kF0 := k;
    StF0[c] := kF0 * Fres;
    for d := 2 to 8 do
      if kF0 * Fres / d >= 80 then
      begin
        k0 := Round((kF0 / d - 3 / Fres));
        k1 := Round((kF0 / d + 3 / Fres));
        Lvl := 0;
        for k := k0 to k1 do
          if PP[k] > Lvl then
          begin
            Lvl := PP[k];
            i0 := k;
          end;
        if Lvl >= 0.01 * PP[kF0] then StF0[c] := i0 * Fres;
      end;
    // harmonic hn's level: the PSD's largest value within 10 Hz of hn f0
    SetLength(H, 0);
    hn := 1;
    while (hn * StF0[c] <= 10000) and (hn * StF0[c] + 10 < Fs / 2) do
    begin
      k0 := Round((hn * StF0[c] - 10) / Fres);
      k1 := Round((hn * StF0[c] + 10) / Fres);
      Lvl := 0;
      for k := k0 to k1 do if PP[k] > Lvl then Lvl := PP[k];
      SetLength(H, hn);
      H[hn - 1] := Lvl;
      Inc(hn);
    end;
    HMax := 0;
    for k := 0 to High(H) do if H[k] > HMax then HMax := H[k];
    NH30 := 0; HTop := 0;
    for k := 0 to High(H) do
    begin
      if H[k] >= HMax * 1e-3 then Inc(NH30);
      if H[k] >= HMax * 1e-4 then HTop := k + 1;
    end;
    StNH30[c] := NH30;
    StHTop[c] := HTop;
    Tot := 0; Above := 0; Cent := 0;
    for k := 0 to PLin.Cols - 1 do
    begin
      Tot := Tot + PP[k];
      Cent := Cent + k * Fres * PP[k];
      if k * Fres > 1000 then Above := Above + PP[k];
    end;
    StAbove[c] := 100 * Above / Tot;
    StCent[c] := Cent / Tot;

    // bispectrum: |B| and bicoherence both, for the memo; one is shown
    GridB := ComputeBispectrum(FGtrSig[c], Fs, Epoch, Fmax, False, Info, GtrFmin);
    GridC := ComputeBispectrum(FGtrSig[c], Fs, Epoch, Fmax, True, InfoC, GtrFmin);
    Mx := 0;
    for k0 := 0 to GridB.Rows - 1 do
      for k1 := 0 to GridB.Cols - 1 do
        if GridB[k0, k1] > Mx then Mx := GridB[k0, k1];
    // over the independent triangle f2 <= f1 (row = f2, column = f1)
    nTri := 0; nNear := 0; BiSum := 0;
    for k1 := 0 to GridB.Cols - 1 do
      for k0 := 0 to k1 do
      begin
        Inc(nTri);
        if GridB[k0, k1] >= Mx * 1e-3 then Inc(nNear);
        BiSum := BiSum + GridC[k0, k1];
      end;
    StNear[c] := 100 * nNear / Max(1, nTri);
    StBicoh[c] := BiSum / Max(1, nTri);

    if Bicoh then
    begin
      Grid := GridC;
      FGtrBi[c].Title := ShortLbl[c] + ': bicoherence';
      FGtrBi[c].ZAxisTitle := 'bicoherence';
      FGtrBi[c].ZAxisMin := 0; FGtrBi[c].ZAxisMax := 1;
    end
    else
    begin
      // 10 log10 |B| re the surface's maximum, floored at -60 dB, as on the
      // anaesthesia bispectrum tab: on a linear scale the fundamental's
      // corner would hide everything else
      Grid := GridB;
      for k0 := 0 to Grid.Rows - 1 do
        for k1 := 0 to Grid.Cols - 1 do
          if (Mx > 0) and (Grid[k0, k1] > Mx * 1e-6) then
            Grid[k0, k1] := 10 * Log10(Grid[k0, k1] / Mx)
          else
            Grid[k0, k1] := -60;
      FGtrBi[c].Title := ShortLbl[c] + ': |B| in dB';
      FGtrBi[c].ZAxisTitle := '|B| (dB re max)';
      FGtrBi[c].ZAxisMin := -60; FGtrBi[c].ZAxisMax := 0;
    end;
    FGtrBi[c].XAxisMin := Info.KMin * Info.Fres; FGtrBi[c].XAxisMax := Info.KMax * Info.Fres;
    FGtrBi[c].YAxisMin := Info.KMin * Info.Fres; FGtrBi[c].YAxisMax := Info.KMax * Info.Fres;
    FGtrBi[c].SetData(Grid);
  end;

  memGtr.Lines.BeginUpdate;
  try
    memGtr.Clear;
    memGtr.Lines.Add('Linear and nonlinear amplification');
    memGtr.Lines.Add('of a guitar note');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('Open G string (G3, 196 Hz), one player,');
    memGtr.Lines.Add('Freesound "SpeedY", CC0: the first 4 s of');
    memGtr.Lines.Add(Format('each, %.0f Hz (see data/README.md)', [Fs]));
    memGtr.Lines.Add('  left:  ' + Lbl[0]);
    memGtr.Lines.Add('  right: ' + Lbl[1]);
    memGtr.Lines.Add('');
    memGtr.Lines.Add(Format('%-26s%11s%11s', ['', 'left', 'right']));
    memGtr.Lines.Add(Row2('peak', '%.3g', StPeak));
    memGtr.Lines.Add(Row2('RMS', '%.3g', StRms));
    memGtr.Lines.Add(Row2('crest factor (dB)', '%.1f', StCrest));
    memGtr.Lines.Add(Row2('f0 (Hz)', '%.1f', StF0));
    memGtr.Lines.Add(Row2('harmonics within 30 dB', '%.0f', StNH30));
    memGtr.Lines.Add(Row2('highest within 40 dB', '%.0f', StHTop));
    memGtr.Lines.Add(Row2('power above 1 kHz (%)', '%.1f', StAbove));
    memGtr.Lines.Add(Row2('spectral centroid (Hz)', '%.0f', StCent));
    memGtr.Lines.Add(Row2('|B| within 30 dB (% grid)', '%.1f', StNear));
    memGtr.Lines.Add(Row2('mean bicoherence', '%.2f', StBicoh));
    memGtr.Lines.Add('(harmonics counted to 10 kHz; |B| and');
    memGtr.Lines.Add(' bicoherence over the f2 <= f1 triangle)');
    memGtr.Lines.Add('');
    memGtr.Lines.Add(Format('Bispectrum: %d epochs of %.3g s, 50 %% overlap,', [Info.NumEp, Info.NEp / Fs]));
    memGtr.Lines.Add(Format('  Hamming, %.3g Hz bins, f1, f2 = %.0f-%.0f Hz', [Info.Fres, Info.KMin * Info.Fres, Info.KMax * Info.Fres]));
    if Capped then
      memGtr.Lines.Add(Format('  (upper limit cut to keep the grid to %d bins)', [MaxGridBins]));
    memGtr.Lines.Add(Format('  bicoherence bias floor ~1/sqrt(epochs) = %.2f', [1 / Sqrt(Info.NumEp)]));
    memGtr.Lines.Add('');
    memGtr.Lines.Add('A LINEAR amplifier, y = g x, scales every');
    memGtr.Lines.Add('component alike: the PSD by g^2 (+20 log10 g');
    memGtr.Lines.Add('dB at every frequency), the bispectrum by g^3,');
    memGtr.Lines.Add('and leaves the bicoherence untouched. No new');
    memGtr.Lines.Add('frequency can appear. Choose "Clean x gain":');
    memGtr.Lines.Add('relative to their peaks, the two PSDs and the');
    memGtr.Lines.Add('two surfaces are identical.');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('A NONLINEAR one, y = a1 x + a2 x^2 + a3 x^3 ...,');
    memGtr.Lines.Add('makes new components: x^2 turns f1 and f2');
    memGtr.Lines.Add('into f1 + f2 and f1 - f2, x^3 into 3 f1 and');
    memGtr.Lines.Add('2 f1 +- f2, and so on, each with a phase');
    memGtr.Lines.Add('fixed by the phases that made it - phase');
    memGtr.Lines.Add('coupling, which is what the bispectrum');
    memGtr.Lines.Add('  B(f1,f2) = E[X(f1) X(f2) X*(f1+f2)]');
    memGtr.Lines.Add('picks up.');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('What the recorded pair shows:');
    memGtr.Lines.Add('- PSD: the clean note is a fundamental and a');
    memGtr.Lines.Add('  handful of harmonics, gone by ~2 kHz;');
    memGtr.Lines.Add('  distortion lifts some twenty harmonics to');
    memGtr.Lines.Add('  within 30 dB of the strongest, far into');
    memGtr.Lines.Add('  the kHz range.');
    memGtr.Lines.Add('- time: the clean wave decays, the distorted');
    memGtr.Lines.Add('  one is compressed and sustains, with a');
    memGtr.Lines.Add('  lower crest factor - the guitarist''s');
    memGtr.Lines.Add('  reason for using it (tick "Whole note").');
    memGtr.Lines.Add('  The recording doesn''t look clipped: the');
    memGtr.Lines.Add('  amplifier''s and speaker''s filtering');
    memGtr.Lines.Add('  reshape the clipped wave. "Clean via tanh"');
    memGtr.Lines.Add('  shows the squaring itself.');
    memGtr.Lines.Add('- |B| (dB): one note''s harmonics, and every');
    memGtr.Lines.Add('  product of them, sit on the lattice');
    memGtr.Lines.Add('  (m f0, n f0). The clean note has peaks');
    memGtr.Lines.Add('  there already - a plucked string is not a');
    memGtr.Lines.Add('  sine, and its harmonics are locked to the');
    memGtr.Lines.Add('  fundamental - but its strong ones are near');
    memGtr.Lines.Add('  the origin and along the axes, the rest');
    memGtr.Lines.Add('  30-60 dB down. Distortion lifts the whole');
    memGtr.Lines.Add('  lattice towards the top of the scale (see');
    memGtr.Lines.Add('  "|B| within 30 dB" above).');
    memGtr.Lines.Add('- bicoherence does not separate them here.');
    memGtr.Lines.Add('  Being normalised, it is high on the');
    memGtr.Lines.Add('  lattice for any periodic note, clean or');
    memGtr.Lines.Add('  not: it tells coupled components from');
    memGtr.Lines.Add('  independent ones (the EEG bispectrum tab''s');
    memGtr.Lines.Add('  two-tone test), not how strong the');
    memGtr.Lines.Add('  coupling is. |B| shows how far it spreads.');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('With one note every product falls on a');
    memGtr.Lines.Add('harmonic of f0 anyway. Distort a chord and');
    memGtr.Lines.Add('the sum and difference tones land between');
    memGtr.Lines.Add('the notes'' harmonics - the "mud" of a');
    memGtr.Lines.Add('distorted chord, and why power chords are');
    memGtr.Lines.Add('fifths, whose products stay harmonic.');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('"Clean via tanh" passes the clean note');
    memGtr.Lines.Add('through y = tanh(g x), a symmetric soft');
    memGtr.Lines.Add('clipper with small-signal gain g. Being odd,');
    memGtr.Lines.Add('it adds only odd-order products (x^3, x^5,');
    memGtr.Lines.Add('...); asymmetric clipping would add even');
    memGtr.Lines.Add('ones. At high gain it clips even as the');
    memGtr.Lines.Add('note dies away, so it sustains too. The');
    memGtr.Lines.Add('recorded pair differ in more than the');
    memGtr.Lines.Add('amplifier - nylon against electric strings,');
    memGtr.Lines.Add('and a real amp''s filters - so the simulation');
    memGtr.Lines.Add('is the controlled comparison: same note,');
    memGtr.Lines.Add('only the transfer curve changed.');
    memGtr.Lines.Add('');
    memGtr.Lines.Add('Play left / Play right use the default');
    memGtr.Lines.Add('output device; each note is scaled to the');
    memGtr.Lines.Add('same peak, so the distorted one sounds');
    memGtr.Lines.Add('louder - its crest factor is lower.');
    memGtr.Lines.Add('Drag a surface to rotate, wheel to zoom.');
  finally
    memGtr.Lines.EndUpdate;
  end;
end;

end.
