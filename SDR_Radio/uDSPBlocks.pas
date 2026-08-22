unit uDSPBlocks;

{*******************************************************************************

     Modular, reusable single-precision DSP building blocks for onward
     CPU-side signal processing of a TSDRRFSource's IQ stream (see
     uSDRRFSource.pas) - written for uFMReceiver.pas's broadcast-FM
     receive chain, but each class here is a general-purpose primitive
     with no FM-specific assumptions baked in, so it can be reused for
     other onward-processing chains later:

     - TNCO: a local quadrature oscillator - a phase-continuous complex
       exponential generator (the "local oscillator" half of a classic
       mixer stage).
     - TComplexMixer: multiplies an IQ stream by its own internal TNCO,
       i.e. frequency-shifts ("tunes") a signal within a wider capture -
       the other half of a mixer stage. Composition (Mixer HAS-A NCO)
       rather than the mixer being the oscillator itself, since an NCO is
       independently useful/testable on its own.
     - TRationalResamplerC/TRationalResamplerS: arbitrary-ratio (L/M)
       sample-rate converters, complex and real respectively (same
       "duplicated per element-type flavour" convention the rest of this
       repository's newVM* units use - see the top-level CLAUDE.md). True
       polyphase implementations (see each class's own comment) - an
       upsample-by-L/filter/downsample-by-M resampler that never
       materialises the zero-stuffed intermediate signal, since doing so
       for the L=24 stage this unit's own FM receiver needs (200kHz ->
       48kHz) would be wastefully expensive.
     - TFMDemodulator: a polar (arctan-of-conjugate-product) FM
       discriminator - complex baseband in, real instantaneous-frequency
       signal out.
     - TFMStereoDecoder: a broadcast-FM stereo (pilot-tone) multiplex
       decoder - the real wideband signal TFMDemodulator produces in,
       independent L/R audio streams out (still at the multiplex sample
       rate - resampling to a final audio rate is the caller's job, via
       TRationalResamplerS, same as any other stage).
     - TAMDemodulator: envelope or synchronous (PLL-tracked, coherent) AM
       detector - complex baseband in, real mono audio out. See that
       class's own header comment for the two modes' own tradeoffs.

     Every stateful block here is a plain class (not a newVM record, and
     not an LCL TComponent) - these are internal processing-chain pieces
     with no visual surface and no Object-Inspector-editable design-time
     configuration, so a class matches this project's own precedent
     (TSDRRingBuffer in uSDRDevice.pas) better than either newVM's
     record-with-managed-fields style or the TComponent style
     uSDRRFSource.pas/uVMPlotSDRSpectrum.pas use for the two *installable*
     pieces of this project.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, OneAPI, newVM, newVMSingle, newVMComplexSingle;

type
  TFilterTaps = array of Single;

// Shared FIR design helpers (windowed-sinc, Hamming window - same window
// family already used throughout this repository, e.g.
// newVMComplexSingle.pas's own PowerSpectrum). TransitionBW is the
// desired transition-band width in Hz; NumTaps is derived from it via
// the standard Hamming-window rule of thumb (NumTaps =~ 3.3*Fs/BW),
// clamped to a sane range so a caller can't accidentally request an
// unusably short or a runaway-expensive filter.
function ChooseNumTaps(Fs, TransitionBW: Double): Integer;
// The actual windowed-sinc lowpass generator, for a caller-chosen
// NumTaps - factored out from DesignLowpassFIR so DesignBandpassFIR can
// build two lowpass responses at the SAME NumTaps/window (required for
// correct cancellation outside the passband) and subtract them.
function LowpassTapsFixedLen(Fc, Fs: Double; NumTaps: Integer; Gain: Double): TFilterTaps;
// Gain is the desired DC (passband) gain - 1.0 for an ordinary lowpass,
// or L for the interpolation half of a rational resampler (see
// TRationalResamplerC/S's own comment for why).
function DesignLowpassFIR(Fc, Fs, TransitionBW, Gain: Double): TFilterTaps;
// Bandpass-via-difference-of-lowpasses (DesignLowpassFIR(FHigh,...) -
// DesignLowpassFIR(FLow,...), same NumTaps/window) - a standard, simple,
// correct FIR bandpass construction; unity passband gain.
function DesignBandpassFIR(FLow, FHigh, Fs, TransitionBW: Double): TFilterTaps;

// A plain streaming direct-form FIR filter over a real, single-precision
// signal - persistent delay line, so consecutive Process calls behave as
// one continuous filtered stream regardless of how the caller chops it
// into epochs. Output is the same length as the input (no rate change) -
// this is the building block TFMStereoDecoder uses for its mono/pilot/
// subcarrier/de-emphasis sub-filters; TRationalResamplerC/S implement
// their own (rate-changing) filtering directly rather than using this.
type
  { TFIRFilterS }
  TFIRFilterS = class
  private
    FTaps: TFilterTaps;
    FHistory: array of Single;   // most recent (Length(FTaps)-1) input samples
  public
    constructor Create(const Taps: TFilterTaps);
    function Process(const X: TVMobjS): TVMobjS;
  end;

  // Local quadrature oscillator: a phase-continuous complex exponential
  // exp(j*2*Pi*FrequencyHz/SampleRateHz*n) generator. FrequencyHz may be
  // negative (shifts a signal DOWN in frequency when mixed against it -
  // see TComplexMixer) and may be changed live between Generate calls
  // (e.g. to retune) without any phase discontinuity at the boundary,
  // since the phase accumulator itself - not a per-call sample index -
  // is what's carried forward.
  { TNCO }
  TNCO = class
  private
    FSampleRateHz: Double;
    FFrequencyHz: Double;
    FPhase: Double;   // radians, kept wrapped to (-Pi,Pi] to avoid float drift over long runs
  public
    constructor Create(SampleRateHz, FrequencyHz: Double);
    function Generate(N: Integer): TVMobjC;
    property FrequencyHz: Double read FFrequencyHz write FFrequencyHz;
  end;

  // Frequency-shifts ("tunes") an IQ stream by multiplying it against its
  // own internal TNCO, elementwise - newVMComplexSingle.pas's '*'
  // operator between two same-shape TVMobjC operands is already
  // elementwise (Hadamard) per this repository's own convention (see the
  // top-level CLAUDE.md's "OPERATOR OVERLOADS" section), so this is
  // exactly IQIn * LO, no manual per-element loop needed.
  { TComplexMixer }
  TComplexMixer = class
  private
    FLO: TNCO;
    function GetFrequencyHz: Double;
    procedure SetFrequencyHz(AValue: Double);
  public
    constructor Create(SampleRateHz, FrequencyHz: Double);
    destructor Destroy; override;
    function Process(const IQIn: TVMobjC): TVMobjC;
    property FrequencyHz: Double read GetFrequencyHz write SetFrequencyHz;
  end;

  // Arbitrary-ratio (Fs_out/Fs_in = L/M, reduced to lowest terms via GCD)
  // sample-rate converter, complex signal. A genuine polyphase
  // implementation: it never builds the L-times zero-stuffed upsampled
  // signal a naive "upsample, filter, downsample" implementation would -
  // instead, for each output sample it selects the matching "polyphase
  // branch" (every Lth filter tap, starting at an offset that cycles
  // through 0..L-1 as the output advances) and convolves that branch
  // directly against the real (never-zero-stuffed) input history. This
  // matters here because this unit's own FM receiver chain needs a real
  // L=24 stage (200kHz -> 48kHz reduces to L/M = 24/125) - naively
  // zero-stuffing by 24x before filtering would be a 24x wasted-compute
  // multiplier for no benefit.
  //
  // The single FIR filter (Taps, designed once at Create) does double
  // duty as both the anti-imaging filter (removing spectral images the
  // upsample-by-L step would otherwise introduce) and the anti-aliasing
  // filter (preventing content above the final Nyquist folding back in
  // when downsampled by M) - standard for a polyphase resampler, since
  // both jobs need the same cutoff: min(Fs_in,Fs_out)/2. Designed with
  // Gain=L to pre-compensate for the DC-gain loss zero-stuffing would
  // otherwise cause (only 1 sample in L is ever non-zero), so the
  // resampler as a whole has unity passband gain.
  //
  // Continuity across calls: FHistory holds the most recent
  // Ceil(NumTaps/L) real input samples (so a fresh filter has enough
  // look-back to start producing correct output immediately after the
  // very first few calls' worth of startup transient); FInputCount/
  // FOutputCount are running totals (Int64, so they don't wrap during
  // any realistic capture session) that let each call pick up exactly
  // where the last one left off, regardless of how many samples each
  // call happens to pass in.
  { TRationalResamplerC }
  TRationalResamplerC = class
  private
    FTaps: TFilterTaps;
    FL, FM: Integer;
    FHistory: array of TComplex8;
    FInputCount, FOutputCount: Int64;
  public
    // TransitionBW controls filter sharpness/tap count the same way it
    // does for DesignLowpassFIR - see that function's own comment.
    constructor Create(FsIn, FsOut, TransitionBW: Double);
    function Process(const X: TVMobjC): TVMobjC;
  end;

  // Real-signal counterpart of TRationalResamplerC - identical algorithm,
  // Single/TVMobjS throughout instead of TComplex8/TVMobjC. See
  // TRationalResamplerC's own comment for the full rationale; not
  // repeated here.
  { TRationalResamplerS }
  TRationalResamplerS = class
  private
    FTaps: TFilterTaps;
    FL, FM: Integer;
    FHistory: array of Single;
    FInputCount, FOutputCount: Int64;
  public
    constructor Create(FsIn, FsOut, TransitionBW: Double);
    function Process(const X: TVMobjS): TVMobjS;
  end;

  // Polar (arctan-of-conjugate-product) FM discriminator: for each
  // sample, computes d = IQ[n] * conj(IQ[n-1]) (a genuine complex
  // multiply, done here by hand - see this unit's own header comment for
  // why: newVMComplexSingle.pas's own CMulC-family helpers are
  // implementation-private to that unit, not exported) and takes
  // ArcTan2(d.im, d.re) - the instantaneous phase change per sample,
  // which is proportional to instantaneous frequency deviation. Scaled
  // by FGain = SampleRateHz/(2*Pi*PeakDeviationHz) so the output is
  // normalised to +-1.0 at exactly +-PeakDeviationHz of frequency
  // deviation (broadcast FM's own peak deviation is +-75kHz almost
  // everywhere this hardware is likely to be used - see
  // uFMReceiver.pas). FPrevSample carries the last sample of one Process
  // call into the next, so the discriminator has no discontinuity at
  // epoch boundaries.
  { TFMDemodulator }
  TFMDemodulator = class
  private
    FGain: Single;
    FPrevSample: TComplex8;
    FHavePrev: Boolean;
  public
    constructor Create(SampleRateHz, PeakDeviationHz: Double);
    function Process(const IQ: TVMobjC): TVMobjS;
  end;

  // Broadcast-FM (pilot-tone, 38kHz-subcarrier) stereo multiplex decoder.
  // Input is TFMDemodulator's own output (the full FM multiplex: mono
  // L+R 0-15kHz, 19kHz pilot, L-R on a 23-53kHz double-sideband
  // suppressed-carrier subcarrier) at the SAME sample rate it was
  // demodulated at; output is independent real L/R streams, still at
  // that same rate (resampling down to a final audio rate, e.g. 48kHz,
  // is the caller's job - see TRationalResamplerS, used twice, in
  // uFMReceiver.pas).
  //
  // 38kHz subcarrier regeneration deliberately does NOT use a phase-
  // locked loop: PLLs are a feedback control system with their own
  // stability/lock-time/loop-filter tuning to get right, which is a lot
  // of extra complexity and failure surface for a first implementation.
  // Instead this uses the classic, simpler, unconditionally-stable
  // "squaring" technique - band-pass extract the ~19kHz pilot, then
  // SQUARE it sample-by-sample: for pilot[n] ~= A*cos(w*n+phi),
  // pilot[n]^2 = A^2/2 + A^2/2*cos(2*w*n+2*phi) (the standard
  // cos^2(x)=0.5+0.5*cos(2x) identity) - the cos(2*w*n+2*phi) term is
  // exactly the 38kHz subcarrier, AND at exactly the right phase (2x the
  // pilot's own phase), because the broadcast-FM standard itself defines
  // the subcarrier's phase as exactly double the pilot's - so squaring
  // reconstructs it directly, with no lock-acquisition delay and no loop
  // to detune. A second band-pass (~37-39kHz) then removes the squaring's
  // DC term, leaving just the regenerated subcarrier.
  //
  // Gain note: every sub-filter here is designed for unity passband gain
  // (DesignLowpassFIR/DesignBandpassFIR's own Gain parameter), but the
  // squaring step and the synchronous L-R downmix both introduce their
  // own scale factors that are impractical to track exactly by hand -
  // FStereoGain is an empirically-tuned (by ear, against real broadcast
  // audio - see uFMReceiver.pas's own verification notes) correction
  // applied to the recovered L-R signal before matrixing, not a
  // derived-from-first-principles constant.
  { TFMStereoDecoder }
  TFMStereoDecoder = class
  private
    FSampleRateHz: Double;
    FMonoLPF: TFIRFilterS;
    FPilotBPF: TFIRFilterS;
    FSubcarrierBPF: TFIRFilterS;
    FDSBSCBPF: TFIRFilterS;
    FStereoLPF: TFIRFilterS;
    FDeEmphasisL, FDeEmphasisR: Single;   // one-pole IIR state, mono/stereo already matrixed
    FDeEmphasisAlpha: Single;
    const FStereoGain = 2.0;
  public
    // TauSeconds is the de-emphasis time constant - 75e-6 (75us) for US
    // broadcast FM, 50e-6 (50us) for most of the rest of the world; see
    // uFMReceiver.pas for which this project defaults to and why.
    constructor Create(SampleRateHz, TauSeconds: Double);
    destructor Destroy; override;
    procedure Process(const Multiplex: TVMobjS; out L, R: TVMobjS);
  end;

  // Envelope or synchronous (coherent) AM demodulator: complex baseband
  // in (already mixed+resampled to the receiver's own channel bandwidth,
  // same input contract as TFMDemodulator), real mono audio out.
  //
  // ENVELOPE mode (Synchronous=False, the classic diode-detector
  // equivalent): audio[n] = |IQ[n]|, DC-blocked by subtracting a slow
  // running average (FDCAvg) - |IQ| always carries a large positive DC
  // offset (the average carrier amplitude) that has to be removed before
  // it's usable as audio, the same role a capacitor plays after a real
  // diode detector. Simple and unconditionally stable, but a null in the
  // CARRIER specifically (selective fading, common on shortwave/MW at
  // night) distorts the recovered envelope directly, and it gets none of
  // synchronous detection's extra noise/fading rejection.
  //
  // SYNCHRONOUS mode (Synchronous=True): a small 2nd-order PLL
  // (critically damped, proportional+integral loop filter - the same
  // standard digital-PLL design used throughout SDR/comms DSP, e.g. GNU
  // Radio's own control_loop, or Michael Rice's "Digital Communications"
  // carrier-synchronisation chapter) tracks the carrier's own
  // instantaneous phase (FPLLPhase/FPLLFreq) directly from the incoming
  // signal - no separate pilot/reference needed, since full-carrier AM's
  // own carrier IS the reference. Rotating IQ[n] by -FPLLPhase projects
  // it onto the carrier's own real axis: the in-phase component is the
  // coherently-demodulated (signed) envelope, and the (magnitude-
  // normalised) quadrature component is exactly the phase-detector error
  // signal a Costas-loop-style PLL needs to steer itself - the classic
  // "rotate-and-correlate" AM-sync technique (the same family of
  // technique TFMStereoDecoder's own DSB-SC downmix uses above, just
  // with a TRACKED rather than regenerated-by-squaring reference, since
  // AM's carrier - unlike FM's suppressed-carrier stereo subcarrier - is
  // already present in the signal to lock onto directly). Locking onto
  // the carrier's true phase/frequency this way - rather than assuming
  // it sits at exactly 0Hz after mixing, which real-world tuning error
  // and carrier drift never quite guarantee - keeps the demodulated
  // audio correct even with a small residual offset, and rejects noise/
  // fading on the quadrature axis a plain envelope detector can't.
  //
  // PLLBandwidthHz (loop bandwidth) is a fixed internal constant, not a
  // published/caller-facing setting - unlike the receiver's own channel
  // BandwidthHz (see uAMReceiver.pas), this is purely an implementation
  // detail of how fast the carrier tracker itself can respond: wide
  // enough to acquire lock quickly and follow ordinary drift, narrow
  // enough to average out modulation-induced phase wobble rather than
  // chasing it (which would distort the recovered audio).
  { TAMDemodulator }
  TAMDemodulator = class
  private
    FDCAvg: Single;
    FDCAlpha: Single;
    FPLLPhase, FPLLFreq: Double;
    FPLLAlpha, FPLLBeta: Double;
  public
    constructor Create(SampleRateHz: Double);
    function Process(const IQ: TVMobjC; Synchronous: Boolean): TVMobjS;
  end;

implementation

// A local GCD helper rather than relying on Math.Gcd's exact overload
// set (Int64 isn't guaranteed among its overloads across FPC versions) -
// trivial and self-contained.
function GcdInt64(a, b: Int64): Int64;
var
  t: Int64;
begin
  while b <> 0 do begin
    t := b;
    b := a mod b;
    a := t;
  end;
  Result := Abs(a);
end;

function ChooseNumTaps(Fs, TransitionBW: Double): Integer;
begin
  Result := Round(3.3 * Fs / TransitionBW);
  if Result mod 2 = 0 then Inc(Result);   // odd length -> exact linear phase
  if Result < 33 then Result := 33;
  if Result > 2001 then Result := 2001;
end;

function LowpassTapsFixedLen(Fc, Fs: Double; NumTaps: Integer; Gain: Double): TFilterTaps;
const
  s = 'LowpassTapsFixedLen : ';
var
  n, Mid: Integer;
  x, w, h, Sum: Double;
begin
  assert(NumTaps > 0, s + 'NumTaps must be positive');
  SetLength(Result, NumTaps);
  Mid := (NumTaps - 1) div 2;
  Sum := 0;
  for n := 0 to NumTaps - 1 do begin
    x := n - Mid;
    if x = 0 then
      h := 2 * Fc / Fs
    else
      h := Sin(2 * Pi * Fc / Fs * x) / (Pi * x);
    w := 0.54 - 0.46 * Cos(2 * Pi * n / (NumTaps - 1));   // Hamming
    h := h * w;
    Result[n] := h;
    Sum := Sum + h;
  end;
  for n := 0 to NumTaps - 1 do
    Result[n] := Result[n] * (Gain / Sum);
end;

function DesignLowpassFIR(Fc, Fs, TransitionBW, Gain: Double): TFilterTaps;
begin
  Result := LowpassTapsFixedLen(Fc, Fs, ChooseNumTaps(Fs, TransitionBW), Gain);
end;

function DesignBandpassFIR(FLow, FHigh, Fs, TransitionBW: Double): TFilterTaps;
var
  NumTaps, i: Integer;
  Hi, Lo: TFilterTaps;
begin
  NumTaps := ChooseNumTaps(Fs, TransitionBW);
  Hi := LowpassTapsFixedLen(FHigh, Fs, NumTaps, 1.0);
  Lo := LowpassTapsFixedLen(FLow, Fs, NumTaps, 1.0);
  SetLength(Result, NumTaps);
  for i := 0 to NumTaps - 1 do
    Result[i] := Hi[i] - Lo[i];
end;

{ TFIRFilterS }

constructor TFIRFilterS.Create(const Taps: TFilterTaps);
begin
  inherited Create;
  FTaps := Taps;
  SetLength(FHistory, Length(FTaps) - 1);   // zero-initialised by SetLength
end;

function TFIRFilterS.Process(const X: TVMobjS): TVMobjS;
var
  N, HistLen, i, j, tapIdx: Integer;
  Combined: array of Single;
  acc: Single;
begin
  N := X.Rows * X.Cols;
  HistLen := Length(FHistory);
  SetLength(Combined, HistLen + N);
  for i := 0 to HistLen - 1 do Combined[i] := FHistory[i];
  for i := 0 to N - 1 do Combined[HistLen + i] := X[0, i];

  Result := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do begin
    acc := 0;
    // Combined[HistLen+i] is the current sample; taps run oldest-first,
    // so tap[0] multiplies the OLDEST sample in the window - matches the
    // (Fc,Fs,NumTaps) design's centre-tap convention used throughout.
    for tapIdx := 0 to Length(FTaps) - 1 do begin
      j := HistLen + i - (Length(FTaps) - 1 - tapIdx);
      acc := acc + FTaps[tapIdx] * Combined[j];
    end;
    Result[0, i] := acc;
  end;

  for i := 0 to HistLen - 1 do
    FHistory[i] := Combined[N + i];
end;

{ TNCO }

constructor TNCO.Create(SampleRateHz, FrequencyHz: Double);
begin
  inherited Create;
  FSampleRateHz := SampleRateHz;
  FFrequencyHz := FrequencyHz;
  FPhase := 0;
end;

// Generates via complex-rotator recurrence (Current := Current * Rotator
// each sample) rather than calling Cos/Sin per sample - at the wideband
// capture rate (e.g. 40,000 samples per 20ms epoch at 2Msps) two
// transcendental calls per sample was real, measured overhead (this
// unit's own real-time budget is tight - see uFMReceiver.pas's own
// performance notes). Rotator/the initial Current are each still built
// from one Cos/Sin pair (cheap, O(1) per Generate call, not O(N)); the
// per-sample update is then just a complex multiply, done by hand for
// the same reason TFMDemodulator.Process does (newVMComplexSingle's own
// complex-scalar helpers are implementation-private to that unit).
// Periodic renormalisation (every 1024 samples) corrects the small
// magnitude drift repeated floating-point multiplication otherwise
// accumulates over a long-running receive session.
function TNCO.Generate(N: Integer): TVMobjC;
const
  TwoPi = 2 * Pi;
var
  i: Integer;
  Step: Double;
  Rotator, Current: TComplex8;
  re, im, mag: Single;
begin
  Result := TVMobjC.Create(1, N);
  Step := TwoPi * FFrequencyHz / FSampleRateHz;
  Rotator := Cplx8(Cos(Step), Sin(Step));
  Current := Cplx8(Cos(FPhase), Sin(FPhase));

  for i := 0 to N - 1 do begin
    Result[0, i] := Current;

    re := Current.re * Rotator.re - Current.im * Rotator.im;
    im := Current.re * Rotator.im + Current.im * Rotator.re;
    Current := Cplx8(re, im);

    if (i and 1023) = 1023 then begin
      mag := Sqrt(Current.re * Current.re + Current.im * Current.im);
      if mag > 0 then begin
        Current.re := Current.re / mag;
        Current.im := Current.im / mag;
      end;
    end;
  end;

  FPhase := ArcTan2(Current.im, Current.re);
end;

{ TComplexMixer }

constructor TComplexMixer.Create(SampleRateHz, FrequencyHz: Double);
begin
  inherited Create;
  FLO := TNCO.Create(SampleRateHz, FrequencyHz);
end;

destructor TComplexMixer.Destroy;
begin
  FLO.Free;
  inherited Destroy;
end;

function TComplexMixer.GetFrequencyHz: Double;
begin
  Result := FLO.FrequencyHz;
end;

procedure TComplexMixer.SetFrequencyHz(AValue: Double);
begin
  FLO.FrequencyHz := AValue;
end;

function TComplexMixer.Process(const IQIn: TVMobjC): TVMobjC;
var
  LO: TVMobjC;
begin
  LO := FLO.Generate(IQIn.Rows * IQIn.Cols);
  Result := IQIn * LO;   // elementwise complex multiply - see this unit's header comment
end;

{ TRationalResamplerC }

constructor TRationalResamplerC.Create(FsIn, FsOut, TransitionBW: Double);
const
  s = 'TRationalResamplerC.Create : ';
var
  G, L, M: Int64;
  HistLen: Integer;
begin
  inherited Create;
  assert((FsIn > 0) and (FsOut > 0), s + 'sample rates must be positive');
  G := GcdInt64(Round(FsIn), Round(FsOut));
  L := Round(FsOut) div G;
  M := Round(FsIn) div G;
  FL := L;
  FM := M;
  FTaps := DesignLowpassFIR(Min(FsIn, FsOut) / 2, FsIn * FL, TransitionBW, FL);
  HistLen := (Length(FTaps) + FL - 1) div FL;   // Ceil(NumTaps/L)
  SetLength(FHistory, HistLen);   // zero-initialised
  FInputCount := 0;
  FOutputCount := 0;
end;

function TRationalResamplerC.Process(const X: TVMobjC): TVMobjC;
var
  Nin, HistLen, i, combinedIdx, j, tapIdx: Integer;
  Combined: array of TComplex8;
  k, t, inputIdx, phase, maxOut: Int64;
  acc: TComplex8;
  Outp: array of TComplex8;
  OutCount: Integer;
begin
  Nin := X.Rows * X.Cols;
  HistLen := Length(FHistory);
  SetLength(Combined, HistLen + Nin);
  for i := 0 to HistLen - 1 do Combined[i] := FHistory[i];
  for i := 0 to Nin - 1 do Combined[HistLen + i] := X[0, i];

  // Upper bound on how many output samples this call could possibly
  // produce, so Outp can be sized once rather than grown repeatedly.
  maxOut := (Nin * FL) div FM + 2;
  SetLength(Outp, maxOut);
  OutCount := 0;

  k := FOutputCount;
  while True do begin
    t := k * FM;
    inputIdx := t div FL;
    if inputIdx > FInputCount + Nin - 1 then Break;
    phase := t mod FL;
    combinedIdx := Integer(inputIdx - FInputCount) + HistLen;

    acc := Cplx8(0, 0);
    j := 0;
    tapIdx := phase;
    while tapIdx < Length(FTaps) do begin
      acc.re := acc.re + FTaps[tapIdx] * Combined[combinedIdx - j].re;
      acc.im := acc.im + FTaps[tapIdx] * Combined[combinedIdx - j].im;
      tapIdx := tapIdx + FL;
      Inc(j);
    end;

    Outp[OutCount] := acc;
    Inc(OutCount);
    Inc(k);
  end;
  FOutputCount := k;

  for i := 0 to HistLen - 1 do
    FHistory[i] := Combined[Nin + i];
  FInputCount := FInputCount + Nin;

  Result := TVMobjC.Create(1, Max(OutCount, 1));
  for i := 0 to OutCount - 1 do Result[0, i] := Outp[i];
  if OutCount = 0 then Result[0, 0] := Cplx8(0, 0);   // TVMobjC.Create disallows zero-length
end;

{ TRationalResamplerS }

constructor TRationalResamplerS.Create(FsIn, FsOut, TransitionBW: Double);
const
  s = 'TRationalResamplerS.Create : ';
var
  G, L, M: Int64;
  HistLen: Integer;
begin
  inherited Create;
  assert((FsIn > 0) and (FsOut > 0), s + 'sample rates must be positive');
  G := GcdInt64(Round(FsIn), Round(FsOut));
  L := Round(FsOut) div G;
  M := Round(FsIn) div G;
  FL := L;
  FM := M;
  FTaps := DesignLowpassFIR(Min(FsIn, FsOut) / 2, FsIn * FL, TransitionBW, FL);
  HistLen := (Length(FTaps) + FL - 1) div FL;
  SetLength(FHistory, HistLen);
  FInputCount := 0;
  FOutputCount := 0;
end;

function TRationalResamplerS.Process(const X: TVMobjS): TVMobjS;
var
  Nin, HistLen, i, combinedIdx, j, tapIdx: Integer;
  Combined: array of Single;
  k, t, inputIdx, phase, maxOut: Int64;
  acc: Single;
  Outp: array of Single;
  OutCount: Integer;
begin
  Nin := X.Rows * X.Cols;
  HistLen := Length(FHistory);
  SetLength(Combined, HistLen + Nin);
  for i := 0 to HistLen - 1 do Combined[i] := FHistory[i];
  for i := 0 to Nin - 1 do Combined[HistLen + i] := X[0, i];

  maxOut := (Nin * FL) div FM + 2;
  SetLength(Outp, maxOut);
  OutCount := 0;

  k := FOutputCount;
  while True do begin
    t := k * FM;
    inputIdx := t div FL;
    if inputIdx > FInputCount + Nin - 1 then Break;
    phase := t mod FL;
    combinedIdx := Integer(inputIdx - FInputCount) + HistLen;

    acc := 0;
    j := 0;
    tapIdx := phase;
    while tapIdx < Length(FTaps) do begin
      acc := acc + FTaps[tapIdx] * Combined[combinedIdx - j];
      tapIdx := tapIdx + FL;
      Inc(j);
    end;

    Outp[OutCount] := acc;
    Inc(OutCount);
    Inc(k);
  end;
  FOutputCount := k;

  for i := 0 to HistLen - 1 do
    FHistory[i] := Combined[Nin + i];
  FInputCount := FInputCount + Nin;

  Result := TVMobjS.Create(1, Max(OutCount, 1));
  for i := 0 to OutCount - 1 do Result[0, i] := Outp[i];
  if OutCount = 0 then Result[0, 0] := 0;
end;

{ TFMDemodulator }

constructor TFMDemodulator.Create(SampleRateHz, PeakDeviationHz: Double);
begin
  inherited Create;
  FGain := SampleRateHz / (2 * Pi * PeakDeviationHz);
  FHavePrev := False;
end;

function TFMDemodulator.Process(const IQ: TVMobjC): TVMobjS;
var
  N, i: Integer;
  cur: TComplex8;
  d: TComplex8;
begin
  N := IQ.Rows * IQ.Cols;
  Result := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do begin
    cur := IQ[0, i];
    if not FHavePrev then begin
      Result[0, i] := 0;   // no prior sample yet - only ever happens on the very first output sample
    end else begin
      // d := cur * conj(prev)
      d.re := cur.re * FPrevSample.re + cur.im * FPrevSample.im;
      d.im := cur.im * FPrevSample.re - cur.re * FPrevSample.im;
      Result[0, i] := ArcTan2(d.im, d.re) * FGain;
    end;
    FPrevSample := cur;
    FHavePrev := True;
  end;
end;

{ TFMStereoDecoder }

constructor TFMStereoDecoder.Create(SampleRateHz, TauSeconds: Double);
begin
  inherited Create;
  FSampleRateHz := SampleRateHz;
  // Transition bandwidths chosen for real-time headroom, not maximum
  // selectivity - each halves roughly halves NumTaps (ChooseNumTaps'
  // own 3.3*Fs/TransitionBW rule), and TFIRFilterS's O(N*NumTaps) direct-
  // form cost was real, measured overhead at these sample rates/epoch
  // sizes - see uFMReceiver.pas's own performance notes.
  // Pilot/subcarrier passbands (18-20kHz, 37-39kHz) still have a wide
  // guard band either side to work with even at a loose 4kHz transition
  // (mono's 15kHz upper edge and the DSB-SC subcarrier's 23kHz lower
  // edge leave a clear 15-23kHz gap around the pilot; similarly for the
  // regenerated 38kHz subcarrier), so this doesn't meaningfully cost
  // selectivity in practice.
  FMonoLPF := TFIRFilterS.Create(DesignLowpassFIR(15000, SampleRateHz, 8000, 1.0));
  FPilotBPF := TFIRFilterS.Create(DesignBandpassFIR(18000, 20000, SampleRateHz, 4000));
  FSubcarrierBPF := TFIRFilterS.Create(DesignBandpassFIR(37000, 39000, SampleRateHz, 4000));
  FDSBSCBPF := TFIRFilterS.Create(DesignBandpassFIR(23000, 53000, SampleRateHz, 4000));
  FStereoLPF := TFIRFilterS.Create(DesignLowpassFIR(15000, SampleRateHz, 8000, 1.0));
  FDeEmphasisL := 0;
  FDeEmphasisR := 0;
  FDeEmphasisAlpha := (1 / SampleRateHz) / (TauSeconds + 1 / SampleRateHz);
end;

destructor TFMStereoDecoder.Destroy;
begin
  FMonoLPF.Free;
  FPilotBPF.Free;
  FSubcarrierBPF.Free;
  FDSBSCBPF.Free;
  FStereoLPF.Free;
  inherited Destroy;
end;

procedure TFMStereoDecoder.Process(const Multiplex: TVMobjS; out L, R: TVMobjS);
var
  N, i: Integer;
  Mono, Pilot, PilotSq, Subcarrier, DSBSC, StereoRaw, Stereo: TVMobjS;
  M, S: Single;
begin
  N := Multiplex.Rows * Multiplex.Cols;

  Mono := FMonoLPF.Process(Multiplex);

  // Regenerate the 38kHz subcarrier by squaring the extracted pilot -
  // see this unit's own header comment for why this needs no PLL.
  Pilot := FPilotBPF.Process(Multiplex);
  PilotSq := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do PilotSq[0, i] := Sqr(Pilot[0, i]);
  Subcarrier := FSubcarrierBPF.Process(PilotSq);

  // Synchronous demodulation of the L-R DSB-SC subcarrier: bandpass out
  // the 23-53kHz subcarrier region, multiply by the regenerated
  // (coherent, correct-phase) carrier, then lowpass to remove the
  // resulting ~76kHz image - standard DSB-SC coherent detection.
  DSBSC := FDSBSCBPF.Process(Multiplex);
  StereoRaw := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do StereoRaw[0, i] := DSBSC[0, i] * Subcarrier[0, i];
  Stereo := FStereoLPF.Process(StereoRaw);

  L := TVMobjS.Create(1, N);
  R := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do begin
    M := Mono[0, i];
    S := Stereo[0, i] * FStereoGain;
    // De-emphasis (single-pole IIR lowpass, time constant TauSeconds -
    // see this unit's own header comment) applied to the already-
    // matrixed L/R, matching standard receiver practice.
    FDeEmphasisL := FDeEmphasisL + FDeEmphasisAlpha * ((M + S) - FDeEmphasisL);
    FDeEmphasisR := FDeEmphasisR + FDeEmphasisAlpha * ((M - S) - FDeEmphasisR);
    L[0, i] := FDeEmphasisL;
    R[0, i] := FDeEmphasisR;
  end;
end;

{ TAMDemodulator }

constructor TAMDemodulator.Create(SampleRateHz: Double);
const
  // DC/carrier-average time constant for envelope-mode DC removal - fast
  // enough to track slow fading, slow enough not to eat into the lowest
  // audio frequencies (a shorter time constant would start removing
  // genuine low-frequency modulation, not just the DC carrier term).
  DCTauSeconds = 0.05;
  // Synchronous-mode carrier-tracking PLL loop bandwidth/damping - see
  // this unit's own TAMDemodulator header comment for why these are
  // fixed internal constants rather than exposed settings. Zeta=0.707
  // (critically damped) is the standard choice absent a specific reason
  // to under/over-damp - no overshoot/ringing on a sudden carrier step.
  PLLBandwidthHz = 30;
  Zeta = 0.707;
var
  Theta, Denom: Double;
begin
  inherited Create;
  FDCAvg := 0;
  FDCAlpha := 1 - Exp(-1 / (DCTauSeconds * SampleRateHz));
  FPLLPhase := 0;
  FPLLFreq := 0;
  // Standard digital 2nd-order PI loop-filter gain derivation (natural
  // frequency from the requested loop bandwidth, damping factor Zeta) -
  // the same closed-form used throughout digital PLL/Costas-loop design.
  Theta := PLLBandwidthHz / (SampleRateHz * (Zeta + 1 / (4 * Zeta)));
  Denom := 1 + 2 * Zeta * Theta + Theta * Theta;
  FPLLAlpha := (4 * Zeta * Theta) / Denom;
  FPLLBeta := (4 * Theta * Theta) / Denom;
end;

function TAMDemodulator.Process(const IQ: TVMobjC; Synchronous: Boolean): TVMobjS;
var
  N, i: Integer;
  re, im, rotI, rotQ, mag, phaseError, audio, c, s: Double;
begin
  N := IQ.Rows * IQ.Cols;
  Result := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do begin
    re := IQ[0, i].re;
    im := IQ[0, i].im;
    if Synchronous then begin
      // Rotate by -FPLLPhase (multiply by the tracked carrier's own unit
      // phasor, conjugated) - see this unit's own header comment
      // ("rotate-and-correlate").
      c := Cos(FPLLPhase);
      s := Sin(FPLLPhase);
      rotI := re * c + im * s;
      rotQ := im * c - re * s;
      mag := Sqrt(rotI * rotI + rotQ * rotQ);
      if mag > 1e-9 then phaseError := rotQ / mag else phaseError := 0;
      FPLLFreq := FPLLFreq + FPLLBeta * phaseError;
      FPLLPhase := FPLLPhase + FPLLFreq + FPLLAlpha * phaseError;
      // Keep phase wrapped - same reason TNCO.Generate wraps its own
      // FPhase (avoids float precision loss in Cos/Sin over long runs).
      if FPLLPhase > Pi then FPLLPhase := FPLLPhase - 2 * Pi
      else if FPLLPhase < -Pi then FPLLPhase := FPLLPhase + 2 * Pi;
      audio := rotI;   // in-phase component = the coherently-demodulated (signed) envelope
    end else
      audio := Sqrt(re * re + im * im);   // envelope detection

    FDCAvg := FDCAvg + FDCAlpha * (audio - FDCAvg);
    Result[0, i] := audio - FDCAvg;
  end;
end;

end.
