unit uDABDecoder;

{*******************************************************************************

     TDABDecoder - DAB (Eureka-147, ETSI EN 300 401) transmission mode I
     receiver, as far as the Fast Information Channel: enough to say which
     ensemble a multiplex is, which services it carries, and how well it
     is being received. No audio yet - the Main Service Channel, where the
     programmes themselves live, is the next step and reuses everything
     here up to the de-interleaver.

     INPUT is complex baseband at exactly 2.048 Msps, centred on the
     multiplex's own centre frequency (one of the Band III blocks - see
     uDABScanner.pas). 2.048 Msps is not a convenience: mode I's OFDM
     symbol is defined as 2048 samples at that rate, so any other rate
     would need a fractional resampler first. Samples are fed in whatever
     chunk size the caller likes (AddSamples) and Process consumes as many
     whole frames as are available. Nothing here is thread-aware: one
     decoder is owned by one thread (uDABScanner.pas's worker).

     THE SIGNAL (mode I)

       A 96 ms transmission frame of 196608 samples: a null symbol (2656
       samples of near-silence - the transmitter switches off), then 76
       OFDM symbols of 2552 samples each, every one a 504-sample cyclic
       prefix ("guard") followed by the 2048-sample useful part. 1536
       carriers, 1 kHz apart, at FFT bins -768..+768 with the centre one
       unused. Symbol 1 is the phase reference (PRS), a fixed, known
       pattern; symbols 2-4 are the FIC; 5-76 are the MSC. Every carrier
       is DQPSK - the information is the phase CHANGE from the same
       carrier in the previous symbol - so the PRS is what the first FIC
       symbol is differenced against.

     THE CHAIN HERE, per frame

       1. Frame timing, coarsely, from the null symbol: the minimum of a
          null-length moving sum of power. The depth of that minimum
          against the average is also the first test of whether there is
          a DAB signal on this block at all.
       2. Frequency, on first acquisition only, in two parts. The
          fractional part (within +-500 Hz) from the cyclic prefix: the
          prefix is a copy of the symbol's own tail, so correlating the
          two gives a phase equal to the frequency error times the 2048-
          sample lag. The integer part (whole carriers) from the PRS: its
          known carrier-to-carrier phase steps are matched against the
          received ones over a range of shifts - differential so that the
          not-yet-known fine timing (a phase slope across carriers)
          cancels out. After that the fractional estimate is tracked
          gently every frame from the four symbols actually decoded.
       3. Fine timing from the PRS: the received PRS spectrum times the
          conjugate of the known one, inverse-transformed, is the channel
          impulse response; its peak is where the symbol really started.
          The peak's prominence is the sync-is-real test from then on.
       4. FFT the PRS and the three FIC symbols, starting a few samples
          inside the guard (anything inside it is equally good, and early
          is safer than late against echoes), differentially demodulate
          each carrier against the previous symbol, and frequency de-
          interleave - carrier order on air is a fixed permutation of
          logical order, spreading a frequency-selective fade across many
          code bits rather than a burst of adjacent ones.
       5. Soft bits: real parts of a symbol's 1536 carriers then the
          imaginary parts, 3072 per symbol, 9216 per frame - four FIC
          blocks of 2304. Each is de-punctured back to the rate-1/4
          mother code (puncturing vectors PI16 x21, PI15 x3, then the
          tail vector), Viterbi decoded (K=7, generators 133/171/145/133
          octal), and the energy-dispersal PRBS (x^9+x^5+1, all ones)
          removed: 768 bits, three 256-bit FIBs.
       6. Each FIB is 30 bytes of FIGs plus a CRC-16 (CCITT, inverted).
          Only CRC-clean FIBs are parsed; the share that pass is the best
          single measure of how well the multiplex is being received,
          since it is exactly what a listener's audio will depend on.

     The FIGs used: 0/0 (ensemble id), 0/2 (services and their
     components - audio type DAB/MP2 or DAB+/HE-AAC, sub-channel), 1/0
     (ensemble label) and 1/1 (programme service label). Everything else
     is skipped by its length field.

     QUALITY is reported three ways. FICOkPercent, as above. SNRdB, from
     the null symbol: signal-plus-noise power over the symbols against
     noise power in the null - optimistic or pessimistic only by whatever
     TII carriers the transmitter puts in its nulls. MERdB, the
     modulation error ratio of the de-rotated DQPSK points against the
     ideal four - a direct measure of how cleanly the constellation is
     arriving, independent of the null.

     Every step above was first written and checked as a Python prototype
     against off-air recordings of 12B (BBC National DAB) and 11D (D1
     National) - all 360 FIBs over 3 s CRC-clean on both - and then
     ported here line for line.

     FFTs go through FFTW via fftw3.pas's plan cache: one 2048-point
     forward and one inverse plan, built on first use and only executed
     after that - safe from this decoder's worker thread, since cached-plan
     execution is thread-safe and planning is serialised there.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../newVMConfig.inc}

interface

uses
  SysUtils, Math, OneAPI, {$IFDEF HAVE_FFTW}fftw3,{$ENDIF} newVMComplexSingle;

const
  DABSampleRateHz = 2048000;

type
  TDABService = record
    SId: LongWord;
    ServiceLabel: string;   // '' until FIG 1/1 has arrived for it
    AudioType: string;      // 'DAB', 'DAB+', or '' if not yet known / not audio
    SubChId: Integer;       // primary audio sub-channel, -1 if not yet known
  end;
  TDABServiceArray = array of TDABService;

  TDABCplx = record
    re, im: Double;
  end;
  TDABCplxArray = array of TDABCplx;

  // One entry of FIG 0/1 (sub-channel organisation). StartCU/SizeCU are in
  // capacity units of 64 bits within each 55296-bit CIF.
  TDABSubChannel = record
    Valid: Boolean;
    StartCU, SizeCU: Integer;
    BitrateKbps: Integer;
    ShortForm: Boolean;      // True: UEP (table index); False: EEP
    UEPIndex: Integer;       // short form
    EEPOptionB: Boolean;     // long form: False = EEP-A, True = EEP-B
    ProtLevel: Integer;      // UEP 1..5, EEP 1..4
  end;

  // One logical frame (24 ms) of the selected sub-channel, after time
  // de-interleaving, Viterbi and energy dispersal: BitrateKbps*3 bytes.
  TDABLogicalFrameEvent = procedure(Sender: TObject; const Data: TBytes) of object;

  { TDABDecoder }
  TDABDecoder = class
  private
    // Sample buffer: FBuf[0] is absolute sample FBufStart.
    FBuf: array of TComplex8;
    FBufLen: Integer;
    FBufStart: Int64;

    FSynced: Boolean;
    FNextNull: Int64;       // expected absolute position of the next null symbol
    FLostCount: Integer;
    FGuardAdvance: Integer;  // how far before the end of the guard each FFT window starts
    FFreqHz: Double;        // current frequency correction (the measured offset)
    FFreqHintHz: Double;
    FHasFreqHint: Boolean;

    // statistics
    FFrames: Integer;
    FFibTotal, FFibOk: Integer;
    FSNRSum, FMERSum: Double;
    FAcquireAttempts: Integer;

    // results
    FEId: Integer;
    FEnsembleLabel: string;
    FServices: TDABServiceArray;
    FLastChangeFrame: Integer;

    // sub-channels (FIG 0/1) and the selected one's MSC state
    FSubChannels: array[0..63] of TDABSubChannel;
    FMSCSubCh: Integer;              // -1: FIC only
    FMSCActive: TDABSubChannel;      // the parameters FMSCPuncture was built for
    FMSCPuncture: array of Boolean;  // mother-code positions actually transmitted
    FMSCInfoBits: Integer;           // 24 * bitrate
    FMSCBits: Integer;               // SizeCU * 64
    FMSCPRBS: array of Byte;
    FTI: array[0..15] of array of Single;   // time de-interleaver: last 16 CIFs
    FTISlot: Integer;
    FTIFill: Integer;
    FLogicalFrames: Int64;
    FOnLogicalFrame: TDABLogicalFrameEvent;
    FMSCBitErrors, FMSCBitsChecked: Int64;

    // scratch
    FWin: TDABCplxArray;
    FSym: array[0..75] of TDABCplxArray;

    function Sample(Abs: Int64): TComplex8; inline;
    procedure Discard(UpTo: Int64);
    function FindNull(From: Int64; Count: Integer; out Depth: Double): Int64;
    function CPCorrelation(SymStart: Int64; NumSym: Integer): TDABCplx;
    procedure LoadWindow(Start: Int64; var W: TDABCplxArray);
    function PRSPeak(NullPos: Int64; out Ratio: Double; out Spread: Integer): Integer;
    function CoarseCarrierOffset(NullPos: Int64): Integer;
    function TryAcquire: Boolean;
    function TryDecodeFrame: Boolean;
    procedure DecodeFIC(const Soft: array of Single);
    function PrepareMSC: Boolean;
    procedure DecodeMSC;
    function GetSubChannel(Id: Integer): TDABSubChannel;
    procedure ParseFIB(const Fib: array of Byte);
    function FindService(SId: LongWord; AddIfMissing: Boolean): Integer;
    procedure Changed;
    function GetSNRdB: Double;
    function GetMERdB: Double;
    function GetFICOkPercent: Double;
  public
    constructor Create;
    procedure Reset;
    procedure AddSamples(const IQ: TVMobjC);
    // Decodes every whole frame currently buffered. Returns True if at
    // least one frame was decoded on this call.
    function Process: Boolean;
    // A starting estimate of the tuner's frequency error for this
    // multiplex (e.g. the previous multiplex's, scaled by frequency) -
    // narrows the whole-carrier search so a weak signal can't lock to a
    // wrong shift. Optional.
    procedure SetFrequencyHint(Hz: Double);
    // Starts decoding the Main Service Channel for one sub-channel (a
    // station's TDABService.SubChId), delivering its logical frames
    // through OnLogicalFrame. Takes effect once FIG 0/1 has described the
    // sub-channel; until then (and with Id = -1) only the FIC is decoded,
    // which costs a fraction of the CPU - 4 OFDM symbols per frame, not 76.
    procedure SelectSubChannel(Id: Integer);

    property Synced: Boolean read FSynced;
    property FramesDecoded: Integer read FFrames;
    property AcquireAttempts: Integer read FAcquireAttempts;
    property FibTotal: Integer read FFibTotal;
    property FibOk: Integer read FFibOk;
    property FICOkPercent: Double read GetFICOkPercent;
    property SNRdB: Double read GetSNRdB;
    property MERdB: Double read GetMERdB;
    property FrequencyOffsetHz: Double read FFreqHz;
    property EId: Integer read FEId;                    // -1 until known
    property EnsembleLabel: string read FEnsembleLabel;
    property Services: TDABServiceArray read FServices;
    // Frame number of the last time anything in the ensemble/service
    // list changed - lets a caller tell when the list has settled.
    property LastChangeFrame: Integer read FLastChangeFrame;
    property SubChannels[Id: Integer]: TDABSubChannel read GetSubChannel;
    property SelectedSubChannel: Integer read FMSCSubCh;
    property LogicalFrames: Int64 read FLogicalFrames;
    // Channel bit error rate of the selected sub-channel, before Viterbi:
    // the decoded bits re-encoded and compared with the received hard
    // decisions. A direct measure of how hard the error correction is
    // working - near 0 on a clean signal, and decoding fails well before
    // it reaches 0.1 at the common protection levels.
    function MSCChannelBER: Double;
    property OnLogicalFrame: TDABLogicalFrameEvent read FOnLogicalFrame write FOnLogicalFrame;
  end;

// Bit rate (kbit/s) of a sub-channel's protection settings, 0 if invalid.
function DABSubChannelBitrate(const S: TDABSubChannel): Integer;

// The FFT this unit uses, exposed for the next stage (MSC/audio) and for
// tests. In place, N = 2048 only. FFTW through fftw3.pas's plan cache
// (planned once, on first use, then only executed); a plain radix-2
// transform when FFTW isn't available.
procedure DABFFT(var A: TDABCplxArray; Inverse: Boolean);

implementation

const
  T_U = 2048;
  T_G = 504;
  T_S = T_U + T_G;
  T_NULL = 2656;
  T_F = 196608;
  NUM_CARRIERS = 1536;
  FIC_SYMBOLS = 3;
  FIC_BLOCK_BITS = 2304;
  FIC_INFO_BITS = 768;
  FIC_MOTHER_BITS = 4 * (FIC_INFO_BITS + 6);

  // Minimum distance of an FFT window start from the end of the guard
  // (see TryDecodeFrame for how the actual position is chosen).
  GUARD_ADVANCE = 16;
  // Null search half-width around where the next null is expected, once synced.
  TRACK_SEARCH = 600;
  // A null this much below the frame's average power is a real DAB null;
  // shallower than that and there is no ensemble here.
  MAX_NULL_DEPTH = 0.5;
  // Impulse-response peak over its mean power: a locked PRS gives
  // hundreds, noise a handful.
  MIN_PRS_RATIO = 20.0;
  FREQ_TRACK_GAIN = 0.3;

  // Phase reference symbol, ETSI EN 300 401 table 44 (h) and table 43
  // (mode I: k', i, n per 32-carrier block).
  PRS_H: array[0..3, 0..31] of Byte = (
    (0,2,0,0,0,0,1,1,2,0,0,0,2,2,1,1,0,2,0,0,0,0,1,1,2,0,0,0,2,2,1,1),
    (0,3,2,3,0,1,3,0,2,1,2,3,2,3,3,0,0,3,2,3,0,1,3,0,2,1,2,3,2,3,3,0),
    (0,0,0,2,0,2,1,3,2,2,0,2,2,0,1,3,0,0,0,2,0,2,1,3,2,2,0,2,2,0,1,3),
    (0,1,2,1,0,3,3,2,2,3,2,1,2,1,3,2,0,1,2,1,0,3,3,2,2,3,2,1,2,1,3,2));
  PRS_TAB: array[0..47, 0..2] of SmallInt = (
    (-768,0,1),(-736,1,2),(-704,2,0),(-672,3,1),(-640,0,3),(-608,1,2),(-576,2,2),(-544,3,3),
    (-512,0,2),(-480,1,1),(-448,2,2),(-416,3,3),(-384,0,1),(-352,1,2),(-320,2,3),(-288,3,3),
    (-256,0,2),(-224,1,2),(-192,2,2),(-160,3,1),(-128,0,1),(-96,1,3),(-64,2,1),(-32,3,2),
    (1,0,3),(33,3,1),(65,2,1),(97,1,1),(129,0,2),(161,3,2),(193,2,1),(225,1,0),
    (257,0,2),(289,3,2),(321,2,3),(353,1,3),(385,0,0),(417,3,2),(449,2,1),(481,1,3),
    (513,0,3),(545,3,3),(577,2,3),(609,1,0),(641,0,3),(673,3,0),(705,2,1),(737,1,1));

  CONV_POLYS: array[0..3] of Byte = ($5B, $79, $65, $5B);   // 133, 171, 145, 133 octal

  MSC_CIF_BITS = 55296;          // 864 CUs of 64 bits
  MSC_SYMBOLS_PER_CIF = 18;
  MSC_FIRST_SYMBOL = 4;          // 0 = PRS, 1..3 = FIC
  // Time interleaving delay map (EN 300 401 clause 12): bit i of a CIF
  // comes from the CIF this many places along the 16-CIF ring.
  TI_MAP: array[0..15] of Integer = (0, 8, 4, 12, 2, 10, 6, 14, 1, 9, 5, 13, 3, 11, 7, 15);

  // UEP sub-channel sizes, EN 300 401 table 6, indexed by FIG 0/1's
  // short-form table index: (size in CUs, protection level, kbit/s).
  UEP_SIZES: array[0..63, 0..2] of SmallInt = (
    (16,5,32), (21,4,32), (24,3,32), (29,2,32), (35,1,32),
    (24,5,48), (29,4,48), (35,3,48), (42,2,48), (52,1,48),
    (29,5,56), (35,4,56), (42,3,56), (52,2,56),
    (32,5,64), (42,4,64), (48,3,64), (58,2,64), (70,1,64),
    (40,5,80), (52,4,80), (58,3,80), (70,2,80), (84,1,80),
    (48,5,96), (58,4,96), (70,3,96), (84,2,96), (104,1,96),
    (58,5,112), (70,4,112), (84,3,112), (104,2,112),
    (64,5,128), (84,4,128), (96,3,128), (116,2,128), (140,1,128),
    (80,5,160), (104,4,160), (116,3,160), (140,2,160), (168,1,160),
    (96,5,192), (116,4,192), (140,3,192), (168,2,192), (208,1,192),
    (116,5,224), (140,4,224), (168,3,224), (208,2,224), (232,1,224),
    (128,5,256), (168,4,256), (192,3,256), (232,2,256), (280,1,256),
    (160,5,320), (208,4,320), (280,2,320),
    (192,5,384), (280,3,384), (416,1,384));

  // UEP puncturing, EN 300 401 table 8: (kbit/s, level, L1..L4, PI1..PI4).
  // Checked at start-up (CheckUEPTables) against table 6 - see there.
  UEP_PROFILES: array[0..63, 0..9] of SmallInt = (
    (32,5, 3,4,17,0, 5,3,2,0),    (32,4, 3,3,18,0, 11,6,5,0),
    (32,3, 3,4,14,3, 15,9,6,8),   (32,2, 3,4,14,3, 22,13,8,13),
    (32,1, 3,5,13,3, 24,17,12,17),
    (48,5, 4,3,26,3, 5,4,2,3),    (48,4, 3,4,26,3, 9,6,4,6),
    (48,3, 3,4,26,3, 15,10,6,9),  (48,2, 3,4,26,3, 24,14,8,15),
    (48,1, 3,5,25,3, 24,18,13,18),
    (56,5, 6,10,23,3, 5,4,2,3),   (56,4, 6,10,23,3, 9,6,4,5),
    (56,3, 6,12,21,3, 16,7,6,9),  (56,2, 6,10,23,3, 23,13,8,13),
    (64,5, 6,9,31,2, 5,3,2,3),    (64,4, 6,9,33,0, 11,6,5,0),
    (64,3, 6,12,27,3, 16,8,6,9),  (64,2, 6,10,29,3, 23,13,8,13),
    (64,1, 6,11,28,3, 24,18,12,18),
    (80,5, 6,10,41,3, 6,3,2,3),   (80,4, 6,10,41,3, 11,6,5,6),
    (80,3, 6,11,40,3, 16,8,6,7),  (80,2, 6,10,41,3, 23,13,8,13),
    (80,1, 6,10,41,3, 24,17,12,18),
    (96,5, 7,9,53,3, 5,4,2,4),    (96,4, 7,10,52,3, 9,6,4,6),
    (96,3, 6,12,51,3, 16,9,6,10), (96,2, 6,10,53,3, 22,12,9,12),
    (96,1, 6,13,50,3, 24,18,13,19),
    (112,5, 14,17,50,3, 5,4,2,5), (112,4, 11,21,49,3, 9,6,4,8),
    (112,3, 11,23,47,3, 16,8,6,9), (112,2, 11,21,49,3, 23,12,9,14),
    (128,5, 12,19,62,3, 5,3,2,4), (128,4, 11,21,61,3, 11,6,5,7),
    (128,3, 11,22,60,3, 16,9,6,10), (128,2, 11,21,61,3, 22,12,9,14),
    (128,1, 11,20,62,3, 24,17,13,19),
    (160,5, 11,19,87,3, 5,4,2,4), (160,4, 11,23,83,3, 11,6,5,9),
    (160,3, 11,24,82,3, 16,8,6,11), (160,2, 11,21,85,3, 22,11,9,13),
    (160,1, 11,22,84,3, 24,18,12,19),
    (192,5, 11,20,110,3, 6,4,2,5), (192,4, 11,22,108,3, 10,6,4,9),
    (192,3, 11,24,106,3, 16,10,6,11), (192,2, 11,20,110,3, 22,13,9,13),
    (192,1, 11,21,109,3, 24,20,13,24),
    (224,5, 12,22,131,3, 8,6,2,6), (224,4, 12,26,127,3, 12,8,4,11),
    (224,3, 11,20,134,3, 16,10,7,9), (224,2, 11,22,132,3, 24,16,10,15),
    (224,1, 11,24,130,3, 24,20,12,20),
    (256,5, 11,24,154,3, 6,5,2,5), (256,4, 11,24,154,3, 12,9,5,10),
    (256,3, 11,27,151,3, 16,10,7,10), (256,2, 11,22,156,3, 24,14,10,13),
    (256,1, 11,26,152,3, 24,19,14,18),
    (320,5, 11,26,200,3, 8,5,2,6), (320,4, 11,25,201,3, 13,9,5,10),
    (320,2, 11,26,200,3, 24,17,9,17),
    (384,5, 11,27,247,3, 8,6,2,7), (384,3, 11,24,250,3, 16,9,7,10),
    (384,1, 12,28,245,3, 24,20,14,23));

var
  PRS: TDABCplxArray;                       // by FFT bin
  Deint: array[0..NUM_CARRIERS - 1] of Integer;   // logical carrier n -> FFT bin
  ActiveBins: array of Integer;             // k = -768..766, k <> 0, k <> -1 (pairs k,k+1 both active)
  ConvOut: array[0..63, 0..1] of Byte;      // 4 output bits packed, bit j = generator j
  PRBS: array[0..FIC_INFO_BITS - 1] of Byte;
  FICPuncture: array[0..FIC_MOTHER_BITS - 1] of Boolean;
  FFTCos, FFTSin: array[0..T_U div 2 - 1] of Double;
  FFTRev: array[0..T_U - 1] of Integer;

{ ---- tables ---- }

// Puncturing vector PI_i (i = 1..24), 32 bits, keeps 8+i of them. The
// table in EN 300 401 (table 29) follows one rule: eight 4-bit groups
// that start as 1000 and gain a further 1 bit, group by group, in the
// order 0,4,2,6,1,5,3,7 - eight steps to make every group 1100, eight
// more for 1110, eight more for 1111. Generated rather than typed in.
function PunctureVector(i: Integer): string;
const
  Order: array[0..7] of Integer = (0, 4, 2, 6, 1, 5, 3, 7);
var
  Ones: array[0..7] of Integer;
  g, step: Integer;
begin
  for g := 0 to 7 do Ones[g] := 1;
  for step := 0 to i - 1 do Inc(Ones[Order[step mod 8]]);
  Result := '';
  for g := 0 to 7 do
    Result := Result + Copy('1111', 1, Ones[g]) + Copy('0000', 1, 4 - Ones[g]);
end;

procedure BuildTables;
var
  b, k, kp, i, n, j, s, reg, p, m, blk, rep: Integer;
  PiSeq: array[0..T_U - 1] of Integer;
  Ph: Double;
  Lfsr: Integer;
  Vec: string;

  function Parity(x: Integer): Integer;
  begin
    Result := 0;
    while x <> 0 do begin Result := Result xor (x and 1); x := x shr 1; end;
  end;

  procedure AddPunct(const V: string);
  var c: Integer;
  begin
    for c := 1 to Length(V) do begin
      FICPuncture[m] := V[c] = '1';
      Inc(m);
    end;
  end;

begin
  // PRS
  SetLength(PRS, T_U);
  for b := 0 to T_U - 1 do begin PRS[b].re := 0; PRS[b].im := 0; end;
  for i := 0 to 47 do begin
    kp := PRS_TAB[i, 0];
    for k := kp to kp + 31 do begin
      Ph := (System.Pi / 2) * (PRS_H[PRS_TAB[i, 1], k - kp] + PRS_TAB[i, 2]);
      b := (k + T_U) mod T_U;
      PRS[b].re := Cos(Ph);
      PRS[b].im := Sin(Ph);
    end;
  end;

  // Frequency interleaving: Pi(0)=0, Pi(i) = (13 Pi(i-1) + 511) mod 2048;
  // the values in 256..1792 other than 1024, in order, are the carriers.
  PiSeq[0] := 0;
  for i := 1 to T_U - 1 do PiSeq[i] := (13 * PiSeq[i - 1] + 511) mod T_U;
  n := 0;
  for i := 0 to T_U - 1 do
    if (PiSeq[i] >= 256) and (PiSeq[i] <= 1792) and (PiSeq[i] <> 1024) then begin
      Deint[n] := (PiSeq[i] - 1024 + T_U) mod T_U;
      Inc(n);
    end;
  assert(n = NUM_CARRIERS, 'uDABDecoder: frequency interleaver built wrong');

  SetLength(ActiveBins, 0);
  for k := -768 to 767 do
    if (k <> 0) and (k <> -1) then begin
      SetLength(ActiveBins, Length(ActiveBins) + 1);
      ActiveBins[High(ActiveBins)] := (k + T_U) mod T_U;
    end;

  // Convolutional encoder: state = previous six input bits, newest in
  // bit 5; the 7-bit register is input<<6 | state, and generator bit 6
  // taps the current input.
  for s := 0 to 63 do
    for b := 0 to 1 do begin
      reg := (b shl 6) or s;
      p := 0;
      for j := 0 to 3 do
        p := p or (Parity(reg and CONV_POLYS[j]) shl j);
      ConvOut[s, b] := p;
    end;

  // Energy dispersal PRBS, x^9 + x^5 + 1, register initialised to ones.
  Lfsr := $1FF;
  for i := 0 to FIC_INFO_BITS - 1 do begin
    b := ((Lfsr shr 8) xor (Lfsr shr 4)) and 1;
    PRBS[i] := b;
    Lfsr := ((Lfsr shl 1) or b) and $1FF;
  end;

  // FIC puncturing (mode I): 21 blocks of 128 mother bits at PI16, 3 at
  // PI15, then the 24-bit tail at 1100 x6.
  m := 0;
  Vec := PunctureVector(16);
  for blk := 1 to 21 do for rep := 1 to 4 do AddPunct(Vec);
  Vec := PunctureVector(15);
  for blk := 1 to 3 do for rep := 1 to 4 do AddPunct(Vec);
  AddPunct('110011001100110011001100');
  assert(m = FIC_MOTHER_BITS, 'uDABDecoder: FIC puncturing built wrong');

  // FFT twiddles and bit reversal.
  for i := 0 to T_U div 2 - 1 do begin
    FFTCos[i] := Cos(2 * System.Pi * i / T_U);
    FFTSin[i] := Sin(2 * System.Pi * i / T_U);
  end;
  for i := 0 to T_U - 1 do begin
    j := 0; n := i;
    for k := 1 to 11 do begin j := (j shl 1) or (n and 1); n := n shr 1; end;
    FFTRev[i] := j;
  end;
end;

{ ---- FFT ---- }

{$IFDEF HAVE_FFTW}
// TDABCplx is two Doubles, bit-identical to TComplex16, so the arrays go
// straight to FFTW. Cached plans are out-of-place only (see fftw3.pas),
// hence the scratch output copied back.
procedure DABFFT(var A: TDABCplxArray; Inverse: Boolean);
var
  Tmp: TDABCplxArray;
  i: Integer;
begin
  assert(Length(A) = T_U, 'DABFFT : length must be 2048');
  SetLength(Tmp, T_U);
  if Inverse then begin
    fftw_execute_dft(CachedPlanD(ftDFTBackward, T_U, @A[0], @Tmp[0]), PComplex16(@A[0]), PComplex16(@Tmp[0]));
    for i := 0 to T_U - 1 do begin
      A[i].re := Tmp[i].re / T_U;
      A[i].im := Tmp[i].im / T_U;
    end;
  end else begin
    fftw_execute_dft(CachedPlanD(ftDFTForward, T_U, @A[0], @Tmp[0]), PComplex16(@A[0]), PComplex16(@Tmp[0]));
    A := Tmp;
  end;
end;
{$ELSE}
procedure DABFFT(var A: TDABCplxArray; Inverse: Boolean);
var
  i, j, len, half, step, k: Integer;
  t: TDABCplx;
  wr, wi, xr, xi: Double;
begin
  assert(Length(A) = T_U, 'DABFFT : length must be 2048');
  for i := 0 to T_U - 1 do begin
    j := FFTRev[i];
    if j > i then begin t := A[i]; A[i] := A[j]; A[j] := t; end;
  end;
  len := 2;
  while len <= T_U do begin
    half := len div 2;
    step := T_U div len;
    i := 0;
    while i < T_U do begin
      for k := 0 to half - 1 do begin
        wr := FFTCos[k * step];
        if Inverse then wi := FFTSin[k * step] else wi := -FFTSin[k * step];
        xr := A[i + k + half].re * wr - A[i + k + half].im * wi;
        xi := A[i + k + half].re * wi + A[i + k + half].im * wr;
        A[i + k + half].re := A[i + k].re - xr;
        A[i + k + half].im := A[i + k].im - xi;
        A[i + k].re := A[i + k].re + xr;
        A[i + k].im := A[i + k].im + xi;
      end;
      Inc(i, len);
    end;
    len := len * 2;
  end;
  if Inverse then
    for i := 0 to T_U - 1 do begin
      A[i].re := A[i].re / T_U;
      A[i].im := A[i].im / T_U;
    end;
end;
{$ENDIF}

{ ---- CRC ---- }

function CRC16(const Data: array of Byte; Len: Integer): Word;
var
  i, b: Integer;
  Crc: Word;
begin
  Crc := $FFFF;
  for i := 0 to Len - 1 do begin
    Crc := Crc xor (Word(Data[i]) shl 8);
    for b := 1 to 8 do
      if (Crc and $8000) <> 0 then Crc := Word((Crc shl 1) xor $1021)
      else Crc := Word(Crc shl 1);
  end;
  Result := Crc xor $FFFF;
end;

{ ---- Viterbi ---- }

// Soft input: one value per mother-code bit, positive meaning 0, zero for
// a punctured (erased) bit. Returns NInfo decoded bits; the encoder is
// assumed to start and (after the six tail bits) end in state 0.
procedure Viterbi(const Soft: array of Single; NInfo: Integer; out Bits: TBytes);
var
  NSteps, t, s, b, ns, j, o: Integer;
  Metric, NewMetric: array[0..63] of Double;
  Decision: array of array[0..63] of Byte;   // packed: prev state (6 bits) | input bit << 6
  bm, c: Double;
  r: array[0..3] of Single;
begin
  NSteps := NInfo + 6;
  SetLength(Decision, NSteps);
  for s := 0 to 63 do Metric[s] := -1e30;
  Metric[0] := 0;
  for t := 0 to NSteps - 1 do begin
    for j := 0 to 3 do r[j] := Soft[4 * t + j];
    for s := 0 to 63 do NewMetric[s] := -1e31;
    for s := 0 to 63 do begin
      if Metric[s] <= -1e29 then Continue;
      for b := 0 to 1 do begin
        o := ConvOut[s, b];
        bm := 0;
        for j := 0 to 3 do
          if (o and (1 shl j)) = 0 then bm := bm + r[j] else bm := bm - r[j];
        c := Metric[s] + bm;
        ns := ((b shl 6) or s) shr 1;
        if c > NewMetric[ns] then begin
          NewMetric[ns] := c;
          Decision[t][ns] := s or (b shl 6);
        end;
      end;
    end;
    Metric := NewMetric;
  end;
  SetLength(Bits, NSteps);
  s := 0;
  for t := NSteps - 1 downto 0 do begin
    Bits[t] := Decision[t][s] shr 6;
    s := Decision[t][s] and 63;
  end;
  SetLength(Bits, NInfo);
end;

{ ---- labels ---- }

// FIG 1 labels: charset 0 is EBU Latin, whose printable ASCII range is
// all that UK broadcasters use in practice; charset 15 is UTF-8.
// Anything else is shown as '?' rather than guessed at.
function DecodeLabel(const D: array of Byte; Offset: Integer; Charset: Integer): string;
var
  i: Integer;
  c: Byte;
begin
  Result := '';
  for i := Offset to Offset + 15 do begin
    c := D[i];
    if Charset = 15 then Result := Result + Chr(c)
    else if (c >= $20) and (c < $7F) then Result := Result + Chr(c)
    else if c = 0 then Result := Result + ' '
    else Result := Result + '?';
  end;
  Result := TrimRight(Result);
end;

{ ---- MSC protection ---- }

function UEPProfileIndex(Kbps, Level: Integer): Integer;
var
  i: Integer;
begin
  for i := 0 to High(UEP_PROFILES) do
    if (UEP_PROFILES[i, 0] = Kbps) and (UEP_PROFILES[i, 1] = Level) then Exit(i);
  Result := -1;
end;

function DABSubChannelBitrate(const S: TDABSubChannel): Integer;
const
  EEPA: array[1..4] of Integer = (12, 8, 6, 4);     // CUs per 8 kbit/s
  EEPB: array[1..4] of Integer = (27, 21, 18, 15);  // CUs per 32 kbit/s
begin
  Result := 0;
  if not S.Valid then Exit;
  if S.ShortForm then
    Result := UEP_SIZES[S.UEPIndex, 2]
  else if (S.ProtLevel >= 1) and (S.ProtLevel <= 4) then begin
    if S.EEPOptionB then Result := S.SizeCU div EEPB[S.ProtLevel] * 32
    else Result := S.SizeCU div EEPA[S.ProtLevel] * 8;
  end;
end;

// The (L, PI) block sequence for a sub-channel - EN 300 401 clause 11:
// table 8 for UEP, the EEP-A/EEP-B formulas for EEP. Each L block is 128
// mother-code bits punctured by PI repeated four times. Returns False for
// protection settings this receiver doesn't recognise.
function SubChannelBlocks(const S: TDABSubChannel; out L, PI: array of Integer): Boolean;
var
  n, k, i: Integer;
begin
  Result := False;
  for i := 0 to 3 do begin L[i] := 0; PI[i] := 1; end;
  if not S.Valid then Exit;
  if S.ShortForm then begin
    k := UEPProfileIndex(UEP_SIZES[S.UEPIndex, 2], UEP_SIZES[S.UEPIndex, 1]);
    if k < 0 then Exit;
    for i := 0 to 3 do begin
      L[i] := UEP_PROFILES[k, 2 + i];
      PI[i] := Max(UEP_PROFILES[k, 6 + i], 1);
    end;
  end else if S.EEPOptionB then begin
    n := DABSubChannelBitrate(S) div 32;
    if n < 1 then Exit;
    L[0] := 24 * n - 3; L[1] := 3;
    case S.ProtLevel of
      1: begin PI[0] := 10; PI[1] := 9; end;
      2: begin PI[0] := 6;  PI[1] := 5; end;
      3: begin PI[0] := 4;  PI[1] := 3; end;
      4: begin PI[0] := 2;  PI[1] := 1; end;
    else Exit;
    end;
  end else begin
    n := DABSubChannelBitrate(S) div 8;
    if n < 1 then Exit;
    case S.ProtLevel of
      1: begin L[0] := 6 * n - 3; L[1] := 3; PI[0] := 24; PI[1] := 23; end;
      2: if n = 1 then begin L[0] := 5; L[1] := 1; PI[0] := 13; PI[1] := 12; end
         else begin L[0] := 2 * n - 3; L[1] := 4 * n + 3; PI[0] := 14; PI[1] := 13; end;
      3: begin L[0] := 6 * n - 3; L[1] := 3; PI[0] := 8; PI[1] := 7; end;
      4: begin L[0] := 4 * n - 3; L[1] := 2 * n + 3; PI[0] := 3; PI[1] := 2; end;
    else Exit;
    end;
  end;
  Result := True;
end;

// Table 6 and table 8 have to agree: for every UEP size entry, the info
// bits per CIF are 24 x the bit rate, and the punctured bits fill the
// sub-channel's CUs less 0..8 padding bits (table 8's own padding column).
// A wrong number in either table breaks exactly this - which is how a bad
// PI2 for 80 kbit/s level 1 (7 instead of 17, 400 bits short) was caught
// in the copy this was checked against.
procedure CheckUEPTables;
var
  i, j, k, Info, Coded: Integer;
begin
  for i := 0 to 63 do begin
    k := UEPProfileIndex(UEP_SIZES[i, 2], UEP_SIZES[i, 1]);
    assert(k >= 0, 'uDABDecoder: no UEP profile for table-6 entry ' + IntToStr(i));
    Info := 0; Coded := 12;
    for j := 0 to 3 do begin
      Info := Info + 32 * UEP_PROFILES[k, 2 + j];
      if UEP_PROFILES[k, 2 + j] > 0 then
        Coded := Coded + 4 * UEP_PROFILES[k, 2 + j] * (8 + UEP_PROFILES[k, 6 + j]);
    end;
    assert(Info = 24 * UEP_SIZES[i, 2], 'uDABDecoder: UEP info bits wrong, entry ' + IntToStr(i));
    assert((Coded <= 64 * UEP_SIZES[i, 0]) and (Coded >= 64 * UEP_SIZES[i, 0] - 8),
      'uDABDecoder: UEP coded bits wrong, entry ' + IntToStr(i));
  end;
end;

{ ---- TDABDecoder ---- }

constructor TDABDecoder.Create;
var
  i: Integer;
begin
  inherited Create;
  SetLength(FWin, T_U);
  for i := 0 to High(FSym) do SetLength(FSym[i], T_U);
  FMSCSubCh := -1;
  Reset;
end;

procedure TDABDecoder.Reset;
begin
  FBufLen := 0;
  FBufStart := 0;
  SetLength(FBuf, 0);
  FSynced := False;
  FLostCount := 0;
  FGuardAdvance := GUARD_ADVANCE;
  FFreqHz := 0;
  FFrames := 0;
  FFibTotal := 0;
  FFibOk := 0;
  FSNRSum := 0;
  FMERSum := 0;
  FAcquireAttempts := 0;
  FEId := -1;
  FEnsembleLabel := '';
  SetLength(FServices, 0);
  FLastChangeFrame := 0;
  FillChar(FSubChannels, SizeOf(FSubChannels), 0);
  FMSCActive.Valid := False;
  FTIFill := 0;
  FLogicalFrames := 0;
  FMSCBitErrors := 0;
  FMSCBitsChecked := 0;
end;

procedure TDABDecoder.SelectSubChannel(Id: Integer);
begin
  if (Id < -1) or (Id > 63) then Id := -1;
  FMSCSubCh := Id;
  FMSCActive.Valid := False;   // PrepareMSC rebuilds for the new one
  FTIFill := 0;
end;

function TDABDecoder.MSCChannelBER: Double;
begin
  if FMSCBitsChecked = 0 then Exit(NaN);
  Result := FMSCBitErrors / FMSCBitsChecked;
end;

function TDABDecoder.GetSubChannel(Id: Integer): TDABSubChannel;
begin
  if (Id < 0) or (Id > 63) then Result := Default(TDABSubChannel)
  else Result := FSubChannels[Id];
end;

// (Re)builds the de-puncturing pattern, PRBS and de-interleaver for the
// selected sub-channel whenever its FIG 0/1 description is new or has
// changed (a multiplex can reconfigure). False if there is nothing
// decodable selected yet.
function TDABDecoder.PrepareMSC: Boolean;
var
  S: TDABSubChannel;
  L, PI: array[0..3] of Integer;
  i, j, rep_, m, Lfsr, b: Integer;
  Vec: string;
begin
  Result := False;
  if FMSCSubCh < 0 then Exit;
  S := FSubChannels[FMSCSubCh];
  if not S.Valid then Exit;
  if FMSCActive.Valid and CompareMem(@S, @FMSCActive, SizeOf(S)) then Exit(True);
  if not SubChannelBlocks(S, L, PI) then Exit;

  FMSCInfoBits := 24 * DABSubChannelBitrate(S);
  FMSCBits := 64 * S.SizeCU;
  if (FMSCInfoBits <= 0) or (S.StartCU + S.SizeCU > 864) then Exit;

  SetLength(FMSCPuncture, 4 * (FMSCInfoBits + 6));
  m := 0;
  for i := 0 to 3 do begin
    if L[i] = 0 then Continue;
    Vec := PunctureVector(PI[i]);
    for j := 1 to L[i] do
      for rep_ := 1 to 4 do
        for b := 1 to 32 do begin
          FMSCPuncture[m] := Vec[b] = '1';
          Inc(m);
        end;
  end;
  Vec := '110011001100110011001100';
  for b := 1 to 24 do begin
    FMSCPuncture[m] := Vec[b] = '1';
    Inc(m);
  end;
  if m <> Length(FMSCPuncture) then Exit;   // tables disagree with the bit rate

  SetLength(FMSCPRBS, FMSCInfoBits);
  Lfsr := $1FF;
  for i := 0 to FMSCInfoBits - 1 do begin
    b := ((Lfsr shr 8) xor (Lfsr shr 4)) and 1;
    FMSCPRBS[i] := b;
    Lfsr := ((Lfsr shl 1) or b) and $1FF;
  end;

  for i := 0 to 15 do SetLength(FTI[i], FMSCBits);
  FTISlot := 0;
  FTIFill := 0;
  FMSCActive := S;
  Result := True;
end;

// The selected sub-channel's share of each of this frame's four CIFs:
// soft bits straight from the differential demodulation of the symbols
// it occupies, into the time de-interleaver, and - once 16 CIFs are in
// it - out as a logical frame through de-puncturing, Viterbi and energy
// dispersal.
procedure TDABDecoder.DecodeMSC;
var
  k, i, g, l, bit, n, b, j, Last, St, Bt, o, t: Integer;
  SymScale: array[0..75] of Double;
  Soft, Mother: array of Single;
  z1, z0: TDABCplx;
  d: Double;
  Bits: TBytes;
  Frame: TBytes;
begin
  if not PrepareMSC then Exit;

  // Per-symbol mean |differential| - the same normalisation the FIC uses,
  // so the Viterbi sees comparable soft values from every symbol.
  for l := 0 to 75 do SymScale[l] := 0;
  Last := -1;
  SetLength(Soft, FMSCBits);
  SetLength(Mother, Length(FMSCPuncture));

  for k := 0 to 3 do begin
    for i := 0 to FMSCBits - 1 do begin
      g := FMSCActive.StartCU * 64 + i;
      l := MSC_FIRST_SYMBOL + k * MSC_SYMBOLS_PER_CIF + g div (2 * NUM_CARRIERS);
      bit := g mod (2 * NUM_CARRIERS);
      if l <> Last then begin
        if SymScale[l] = 0 then begin
          d := 0;
          for n := 0 to NUM_CARRIERS - 1 do begin
            b := Deint[n];
            z1 := FSym[l][b]; z0 := FSym[l - 1][b];
            d := d + Sqrt(Sqr(z1.re * z0.re + z1.im * z0.im) + Sqr(z1.im * z0.re - z1.re * z0.im));
          end;
          SymScale[l] := Max(d / NUM_CARRIERS, 1e-30);
        end;
        Last := l;
      end;
      if bit < NUM_CARRIERS then begin
        b := Deint[bit];
        z1 := FSym[l][b]; z0 := FSym[l - 1][b];
        Soft[i] := (z1.re * z0.re + z1.im * z0.im) / SymScale[l];
      end else begin
        b := Deint[bit - NUM_CARRIERS];
        z1 := FSym[l][b]; z0 := FSym[l - 1][b];
        Soft[i] := (z1.im * z0.re - z1.re * z0.im) / SymScale[l];
      end;
    end;

    // Time de-interleave: bit i of the output comes from the CIF TI_MAP
    // places along the ring from the one just stored.
    Move(Soft[0], FTI[FTISlot][0], FMSCBits * SizeOf(Single));
    for i := 0 to FMSCBits - 1 do
      Soft[i] := FTI[(FTISlot + TI_MAP[i and 15]) and 15][i];
    FTISlot := (FTISlot + 1) and 15;
    if FTIFill < 16 then begin
      Inc(FTIFill);
      Continue;   // ring not yet full: nothing valid to output
    end;

    j := 0;
    for i := 0 to High(Mother) do
      if FMSCPuncture[i] then begin
        Mother[i] := Soft[j];
        Inc(j);
      end else
        Mother[i] := 0;
    Viterbi(Mother, FMSCInfoBits, Bits);

    // Re-encode and compare, for MSCChannelBER.
    St := 0;
    for t := 0 to FMSCInfoBits + 5 do begin
      if t < FMSCInfoBits then Bt := Bits[t] else Bt := 0;
      o := ConvOut[St, Bt];
      for n := 0 to 3 do
        if FMSCPuncture[4 * t + n] then begin
          Inc(FMSCBitsChecked);
          if ((o shr n) and 1) <> Ord(Mother[4 * t + n] < 0) then Inc(FMSCBitErrors);
        end;
      St := ((Bt shl 6) or St) shr 1;
    end;

    SetLength(Frame, FMSCInfoBits div 8);
    for i := 0 to High(Frame) do begin
      b := 0;
      for n := 0 to 7 do
        b := (b shl 1) or (Bits[i * 8 + n] xor FMSCPRBS[i * 8 + n]);
      Frame[i] := b;
    end;
    Inc(FLogicalFrames);
    if Assigned(FOnLogicalFrame) then FOnLogicalFrame(Self, Frame);
  end;
end;



procedure TDABDecoder.SetFrequencyHint(Hz: Double);
begin
  FFreqHintHz := Hz;
  FHasFreqHint := True;
end;

function TDABDecoder.Sample(Abs: Int64): TComplex8;
begin
  Result := FBuf[Abs - FBufStart];
end;

procedure TDABDecoder.AddSamples(const IQ: TVMobjC);
var
  N, i: Integer;
begin
  assert(IQ.Rows = 1, 'TDABDecoder.AddSamples : IQ must be a (1,N) row vector');
  N := IQ.Cols;
  if FBufLen + N > Length(FBuf) then
    SetLength(FBuf, Max(2 * Length(FBuf), FBufLen + N));
  for i := 0 to N - 1 do
    FBuf[FBufLen + i] := IQ[0, i];
  Inc(FBufLen, N);
end;

procedure TDABDecoder.Discard(UpTo: Int64);
var
  Drop: Integer;
begin
  Drop := Integer(UpTo - FBufStart);
  if Drop <= 0 then Exit;
  if Drop >= FBufLen then begin
    FBufStart := FBufStart + FBufLen;
    FBufLen := 0;
    Exit;
  end;
  Move(FBuf[Drop], FBuf[0], (FBufLen - Drop) * SizeOf(TComplex8));
  Dec(FBufLen, Drop);
  FBufStart := FBufStart + Drop;
end;

// Position (absolute) of the T_NULL-long window with least power whose
// start lies in [From, From+Count). Depth is that window's power over
// the average window's - well under 1 for a real null.
function TDABDecoder.FindNull(From: Int64; Count: Integer; out Depth: Double): Int64;
var
  i: Integer;
  Sum, Best, Total: Double;
  c: TComplex8;
  BestAt: Int64;
begin
  Sum := 0;
  for i := 0 to T_NULL - 1 do begin
    c := Sample(From + i);
    Sum := Sum + c.re * c.re + c.im * c.im;
  end;
  Best := Sum; BestAt := From; Total := Sum;
  for i := 1 to Count - 1 do begin
    c := Sample(From + i - 1);
    Sum := Sum - (c.re * c.re + c.im * c.im);
    c := Sample(From + i + T_NULL - 1);
    Sum := Sum + c.re * c.re + c.im * c.im;
    Total := Total + Sum;
    if Sum < Best then begin Best := Sum; BestAt := From + i; end;
  end;
  if Total > 0 then Depth := Best / (Total / Count) else Depth := 1;
  Result := BestAt;
end;

// Sum over NumSym consecutive symbols (the first starting, guard
// included, at SymStart) of guard * conj(the tail it copies).
function TDABDecoder.CPCorrelation(SymStart: Int64; NumSym: Integer): TDABCplx;
var
  l, i: Integer;
  a, b: TComplex8;
  p: Int64;
begin
  Result.re := 0; Result.im := 0;
  for l := 0 to NumSym - 1 do begin
    p := SymStart + Int64(l) * T_S;
    for i := 0 to T_G - 1 do begin
      a := Sample(p + i);
      b := Sample(p + i + T_U);
      Result.re := Result.re + a.re * b.re + a.im * b.im;
      Result.im := Result.im + a.im * b.re - a.re * b.im;
    end;
  end;
end;

// T_U samples from Start, frequency-corrected by FFreqHz against
// absolute sample index (so every window shares one continuous
// correction phase), forward FFT'd.
procedure TDABDecoder.LoadWindow(Start: Int64; var W: TDABCplxArray);
var
  i: Integer;
  c: TComplex8;
  Ph, cr, ci, Step, sr, si, t: Double;
begin
  Ph := -2 * System.Pi * Frac(FFreqHz * (Start / DABSampleRateHz));
  cr := Cos(Ph); ci := Sin(Ph);
  Step := -2 * System.Pi * FFreqHz / DABSampleRateHz;
  sr := Cos(Step); si := Sin(Step);
  for i := 0 to T_U - 1 do begin
    c := Sample(Start + i);
    W[i].re := c.re * cr - c.im * ci;
    W[i].im := c.re * ci + c.im * cr;
    t := cr * sr - ci * si;
    ci := cr * si + ci * sr;
    cr := t;
  end;
  DABFFT(W, False);
end;

// Channel impulse response from the PRS that follows the null at
// NullPos. Returns the signed offset of the EARLIEST significant path
// (within 10 dB of the strongest) - the true symbol start is NullPos +
// T_NULL + result - and in Spread how much later the latest significant
// path arrives. Ratio is the strongest path's power over the mean, the
// is-this-really-a-PRS test.
//
// Earliest rather than strongest, because in a single-frequency network
// the strongest signal is often not the first to arrive: the FFT window
// has to start after the latest path's symbol has begun and end before
// the earliest path's next one does, and anchoring on a later, stronger
// path would push the window past the guard and into the next symbol.
function TDABDecoder.PRSPeak(NullPos: Int64; out Ratio: Double; out Spread: Integer): Integer;
var
  i, Best, d, Earliest, Latest: Integer;
  Pw, BestPw, Total: Double;
  t: TDABCplx;
  P: array of Double;
begin
  LoadWindow(NullPos + T_NULL + T_G, FWin);
  for i := 0 to T_U - 1 do begin
    t := FWin[i];
    FWin[i].re := t.re * PRS[i].re + t.im * PRS[i].im;
    FWin[i].im := t.im * PRS[i].re - t.re * PRS[i].im;
  end;
  DABFFT(FWin, True);
  SetLength(P, T_U);
  Best := 0; BestPw := -1; Total := 0;
  for i := 0 to T_U - 1 do begin
    Pw := Sqr(FWin[i].re) + Sqr(FWin[i].im);
    P[i] := Pw;
    Total := Total + Pw;
    if Pw > BestPw then begin BestPw := Pw; Best := i; end;
  end;
  if Total > 0 then Ratio := BestPw / (Total / T_U) else Ratio := 0;
  if Best > T_U div 2 then Best := Best - T_U;

  // Significant paths within one guard interval either side of the peak.
  Earliest := Best; Latest := Best;
  for d := -T_G to T_G do
    if P[(Best + d + T_U) mod T_U] >= BestPw * 0.1 then begin
      if Best + d < Earliest then Earliest := Best + d;
      if Best + d > Latest then Latest := Best + d;
    end;
  Spread := Latest - Earliest;
  Result := Earliest;
end;

// Whole-carrier frequency offset: shift s maximising
// |sum_k D_rx[k+s] conj(D_prs[k])|, D[k] = Z[k+1] conj(Z[k]).
function TDABDecoder.CoarseCarrierOffset(NullPos: Int64): Integer;
var
  s, i, b, bs, Lo, Hi, Centre: Integer;
  Acc: TDABCplx;
  dr, dp: TDABCplx;
  v, Best: Double;
begin
  LoadWindow(NullPos + T_NULL + T_G, FWin);
  if FHasFreqHint then begin
    Centre := Round((FFreqHintHz - FFreqHz) / 1000);
    Lo := Centre - 2; Hi := Centre + 2;
  end else begin
    Lo := -35; Hi := 35;
  end;
  Best := -1; Result := 0;
  for s := Lo to Hi do begin
    Acc.re := 0; Acc.im := 0;
    for i := 0 to High(ActiveBins) do begin
      b := ActiveBins[i];
      bs := (b + s + T_U) mod T_U;
      // received differential at the shifted bin
      dr.re := FWin[(bs + 1) mod T_U].re * FWin[bs].re + FWin[(bs + 1) mod T_U].im * FWin[bs].im;
      dr.im := FWin[(bs + 1) mod T_U].im * FWin[bs].re - FWin[(bs + 1) mod T_U].re * FWin[bs].im;
      dp.re := PRS[(b + 1) mod T_U].re * PRS[b].re + PRS[(b + 1) mod T_U].im * PRS[b].im;
      dp.im := PRS[(b + 1) mod T_U].im * PRS[b].re - PRS[(b + 1) mod T_U].re * PRS[b].im;
      Acc.re := Acc.re + dr.re * dp.re + dr.im * dp.im;
      Acc.im := Acc.im + dr.im * dp.re - dr.re * dp.im;
    end;
    v := Sqr(Acc.re) + Sqr(Acc.im);
    if v > Best then begin Best := v; Result := s; end;
  end;
end;

// First lock: needs a frame's worth of null search plus the whole frame
// that follows the null (for the cyclic-prefix frequency estimate).
function TDABDecoder.TryAcquire: Boolean;
var
  NullPos: Int64;
  Depth, Ratio: Double;
  Cp: TDABCplx;
  Pk, Spread: Integer;
begin
  Result := False;
  if FBufLen < T_F + T_NULL + T_F then Exit;
  Inc(FAcquireAttempts);
  NullPos := FindNull(FBufStart, T_F, Depth);
  if Depth > MAX_NULL_DEPTH then begin
    Discard(FBufStart + T_F);   // no null - nothing here, try the next frame's worth
    Exit;
  end;
  // Fractional offset from the cyclic prefix, over all 76 symbols: the
  // correlation phase is -2 pi f T_U / Fs.
  Cp := CPCorrelation(NullPos + T_NULL, 76);
  FFreqHz := -ArcTan2(Cp.im, Cp.re) * DABSampleRateHz / (2 * System.Pi * T_U);
  FFreqHz := FFreqHz + 1000.0 * CoarseCarrierOffset(NullPos);
  Pk := PRSPeak(NullPos, Ratio, Spread);
  if Ratio < MIN_PRS_RATIO then begin
    Discard(NullPos + T_NULL);
    Exit;
  end;
  FSynced := True;
  FLostCount := 0;
  FNextNull := NullPos + Pk;
  Discard(FNextNull - TRACK_SEARCH);
  Result := True;
end;

function TDABDecoder.TryDecodeFrame: Boolean;
var
  NullPos, Sym0: Int64;
  Depth, Ratio, PNull, PSym, Snr, Scale, Resid: Double;
  Pk, l, n, b, i, NSym, Spread: Integer;
  c: TComplex8;
  d, z1, z0: TDABCplx;
  Soft: array of Single;
  MerErr, MerSig, Mag, Ir, Ii: Double;
  Cp: TDABCplx;
begin
  Result := False;
  // All 76 symbols when a sub-channel's MSC is wanted, otherwise just the
  // PRS and the three FIC symbols.
  if (FMSCSubCh >= 0) and FSubChannels[FMSCSubCh].Valid then NSym := 76 else NSym := 4;
  // Need: search window around the expected null, plus null + NSym symbols.
  if FBufStart + FBufLen < FNextNull + TRACK_SEARCH + T_NULL + Int64(NSym) * T_S + T_U then Exit;
  NullPos := FindNull(Max(FBufStart, FNextNull - TRACK_SEARCH), 2 * TRACK_SEARCH, Depth);
  Pk := PRSPeak(NullPos, Ratio, Spread);
  // Only the PRS peak decides whether lock still holds: Depth here is
  // measured against windows that nearly all overlap the null itself, so
  // it says nothing (unlike in TryAcquire, where the search spans a frame).
  if Ratio < MIN_PRS_RATIO then begin
    Inc(FLostCount);
    if FLostCount >= 3 then begin
      FSynced := False;
      Discard(FNextNull);
      Exit;
    end;
    Pk := 0;
    NullPos := FNextNull;
  end else begin
    FLostCount := 0;
    // Centre the FFT window in the span every path's guard covers - from
    // the latest path's symbol start to the earliest path's guard end -
    // for the most margin against timing jitter either way. Paths spread
    // wider than the guard leave no clean span; then just start late in
    // the guard, which favours the earlier (usually nearer) transmitter.
    if Spread < T_G - 2 * GUARD_ADVANCE then
      FGuardAdvance := (T_G - Spread) div 2
    else
      FGuardAdvance := GUARD_ADVANCE;
  end;
  Sym0 := NullPos + T_NULL + Pk;

  // Track the fractional frequency from the four symbols being decoded.
  Cp := CPCorrelation(Sym0, 4);
  // CPCorrelation is on raw samples; subtract what FFreqHz already accounts for.
  Resid := -ArcTan2(Cp.im, Cp.re) * DABSampleRateHz / (2 * System.Pi * T_U);
  Resid := Resid - (FFreqHz - 1000.0 * Round(FFreqHz / 1000.0));
  if Resid > 500 then Resid := Resid - 1000;
  if Resid < -500 then Resid := Resid + 1000;
  FFreqHz := FFreqHz + FREQ_TRACK_GAIN * Resid;

  for l := 0 to NSym - 1 do
    LoadWindow(Sym0 + Int64(l) * T_S + T_G - FGuardAdvance, FSym[l]);

  // Null-based SNR.
  PNull := 0;
  for i := 200 to T_NULL - 200 - 1 do begin
    c := Sample(Sym0 - T_NULL + i);
    PNull := PNull + c.re * c.re + c.im * c.im;
  end;
  PNull := PNull / (T_NULL - 400);
  PSym := 0;
  for i := 0 to 4 * T_S - 1 do begin
    c := Sample(Sym0 + i);
    PSym := PSym + c.re * c.re + c.im * c.im;
  end;
  PSym := PSym / (4 * T_S);
  if PNull > 0 then Snr := Max(PSym - PNull, 1e-12) / PNull else Snr := 1e6;

  // Differential demodulation, de-interleave, soft bits.
  SetLength(Soft, FIC_SYMBOLS * 2 * NUM_CARRIERS);
  MerErr := 0; MerSig := 0;
  for l := 1 to FIC_SYMBOLS do begin
    Scale := 0;
    for n := 0 to NUM_CARRIERS - 1 do begin
      b := Deint[n];
      z1 := FSym[l][b]; z0 := FSym[l - 1][b];
      d.re := z1.re * z0.re + z1.im * z0.im;
      d.im := z1.im * z0.re - z1.re * z0.im;
      Mag := Sqrt(Sqr(d.re) + Sqr(d.im));
      Scale := Scale + Mag;
      if Mag > 0 then begin
        Ir := Sign(d.re) / Sqrt(2); Ii := Sign(d.im) / Sqrt(2);
        MerErr := MerErr + Sqr(d.re / Mag - Ir) + Sqr(d.im / Mag - Ii);
      end;
      MerSig := MerSig + 1;
      Soft[(l - 1) * 2 * NUM_CARRIERS + n] := d.re;
      Soft[(l - 1) * 2 * NUM_CARRIERS + NUM_CARRIERS + n] := d.im;
    end;
    Scale := Scale / NUM_CARRIERS;
    if Scale > 0 then
      for n := 0 to 2 * NUM_CARRIERS - 1 do
        Soft[(l - 1) * 2 * NUM_CARRIERS + n] := Soft[(l - 1) * 2 * NUM_CARRIERS + n] / Scale;
  end;

  Inc(FFrames);
  FSNRSum := FSNRSum + Snr;
  if MerErr > 0 then FMERSum := FMERSum + MerSig / MerErr else FMERSum := FMERSum + 1e6;
  DecodeFIC(Soft);
  if NSym = 76 then DecodeMSC;

  FNextNull := Sym0 - T_NULL + T_F;
  Discard(FNextNull - TRACK_SEARCH);
  Result := True;
end;

procedure TDABDecoder.DecodeFIC(const Soft: array of Single);
var
  blk, i, j, f: Integer;
  Mother: array[0..FIC_MOTHER_BITS - 1] of Single;
  Bits: TBytes;
  Fib: array[0..31] of Byte;
begin
  for blk := 0 to 3 do begin
    j := blk * FIC_BLOCK_BITS;
    for i := 0 to FIC_MOTHER_BITS - 1 do
      if FICPuncture[i] then begin
        Mother[i] := Soft[j];
        Inc(j);
      end else
        Mother[i] := 0;
    Viterbi(Mother, FIC_INFO_BITS, Bits);
    for i := 0 to FIC_INFO_BITS - 1 do Bits[i] := Bits[i] xor PRBS[i];
    for f := 0 to 2 do begin
      for i := 0 to 31 do begin
        Fib[i] := 0;
        for j := 0 to 7 do
          Fib[i] := (Fib[i] shl 1) or Bits[f * 256 + i * 8 + j];
      end;
      Inc(FFibTotal);
      if CRC16(Fib, 30) = (Word(Fib[30]) shl 8 or Fib[31]) then begin
        Inc(FFibOk);
        ParseFIB(Fib);
      end;
    end;
  end;
end;

function TDABDecoder.FindService(SId: LongWord; AddIfMissing: Boolean): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FServices) do
    if FServices[i].SId = SId then Exit(i);
  Result := -1;
  if not AddIfMissing then Exit;
  Result := Length(FServices);
  SetLength(FServices, Result + 1);
  FServices[Result].SId := SId;
  FServices[Result].ServiceLabel := '';
  FServices[Result].AudioType := '';
  FServices[Result].SubChId := -1;
  Changed;
end;

procedure TDABDecoder.Changed;
begin
  FLastChangeFrame := FFrames;
end;

procedure TDABDecoder.ParseFIB(const Fib: array of Byte);
var
  i, Typ, Len, Ext, j, nc, c, Idx, Charset, SubId: Integer;
  PD: Boolean;
  Sc: TDABSubChannel;
  SId: LongWord;
  Lbl, Asc: string;
begin
  i := 0;
  while i < 30 do begin
    if Fib[i] = $FF then Break;
    Typ := Fib[i] shr 5;
    Len := Fib[i] and 31;
    if (Len = 0) or (i + 1 + Len > 30) then Break;
    j := i + 1;   // first data byte

    case Typ of
      0: begin
        Ext := Fib[j] and 31;
        PD := (Fib[j] and $20) <> 0;
        if Ext = 1 then begin
          // Sub-channel organisation: 3 bytes (short form, UEP) or 4
          // (long form, EEP) per sub-channel.
          c := j + 1;
          while c + 3 <= j + Len do begin
            Sc := Default(TDABSubChannel);
            Sc.Valid := True;
            SubId := Fib[c] shr 2;
            Sc.StartCU := ((Fib[c] and 3) shl 8) or Fib[c + 1];
            if (Fib[c + 2] and $80) = 0 then begin
              Sc.ShortForm := True;
              Sc.UEPIndex := Fib[c + 2] and 63;
              Sc.SizeCU := UEP_SIZES[Sc.UEPIndex, 0];
              Sc.ProtLevel := UEP_SIZES[Sc.UEPIndex, 1];
              Inc(c, 3);
            end else begin
              if c + 4 > j + Len then Break;
              Sc.EEPOptionB := ((Fib[c + 2] shr 4) and 7) = 1;
              Sc.ProtLevel := ((Fib[c + 2] shr 2) and 3) + 1;
              Sc.SizeCU := ((Fib[c + 2] and 3) shl 8) or Fib[c + 3];
              if ((Fib[c + 2] shr 4) and 7) > 1 then Sc.Valid := False;   // reserved option
              Inc(c, 4);
            end;
            Sc.BitrateKbps := DABSubChannelBitrate(Sc);
            if not CompareMem(@Sc, @FSubChannels[SubId], SizeOf(Sc)) then begin
              FSubChannels[SubId] := Sc;
              Changed;
            end;
          end;
        end else if (Ext = 0) and (Len >= 5) then begin
          if FEId <> (Fib[j + 1] shl 8 or Fib[j + 2]) then begin
            FEId := Fib[j + 1] shl 8 or Fib[j + 2];
            Changed;
          end;
        end else if (Ext = 2) and not PD then begin
          // Basic service and service component definition, programme services.
          c := j + 1;
          while c + 3 <= j + Len do begin
            SId := Fib[c] shl 8 or Fib[c + 1];
            nc := Fib[c + 2] and 15;
            Inc(c, 3);
            Idx := FindService(SId, True);
            while (nc > 0) and (c + 2 <= j + Len) do begin
              // TMId 00 = MSC stream audio; PS flag (bit 1 of the second byte) = primary.
              if ((Fib[c] shr 6) = 0) and (((Fib[c + 1] shr 1) and 1) = 1) then begin
                if (Fib[c] and 63) = 63 then Asc := 'DAB+' else Asc := 'DAB';
                if (FServices[Idx].AudioType <> Asc) or (FServices[Idx].SubChId <> Fib[c + 1] shr 2) then begin
                  FServices[Idx].AudioType := Asc;
                  FServices[Idx].SubChId := Fib[c + 1] shr 2;
                  Changed;
                end;
              end;
              Inc(c, 2);
              Dec(nc);
            end;
          end;
        end;
      end;
      1: begin
        Charset := Fib[j] shr 4;
        Ext := Fib[j] and 7;
        if (Ext = 0) and (Len >= 19) then begin
          Lbl := DecodeLabel(Fib, j + 3, Charset);
          if Lbl <> FEnsembleLabel then begin FEnsembleLabel := Lbl; Changed; end;
        end else if (Ext = 1) and (Len >= 19) then begin
          SId := Fib[j + 1] shl 8 or Fib[j + 2];
          Lbl := DecodeLabel(Fib, j + 3, Charset);
          Idx := FindService(SId, True);
          if FServices[Idx].ServiceLabel <> Lbl then begin
            FServices[Idx].ServiceLabel := Lbl;
            Changed;
          end;
        end;
      end;
    end;
    i := i + 1 + Len;
  end;
end;

function TDABDecoder.Process: Boolean;
begin
  Result := False;
  // Every TryAcquire with enough data consumes some of it (lock or not),
  // and a TryDecodeFrame that loses lock consumes up to where it was, so
  // this always makes progress until it runs short of samples.
  repeat
    if not FSynced then begin
      if FBufLen < T_F + T_NULL + T_F then Exit;
      TryAcquire;
      Continue;
    end;
    if TryDecodeFrame then Result := True
    else if FSynced then Exit;   // just waiting for more samples
  until False;
end;

function TDABDecoder.GetSNRdB: Double;
begin
  if FFrames = 0 then Exit(NaN);
  Result := 10 * Log10(FSNRSum / FFrames);
end;

function TDABDecoder.GetMERdB: Double;
begin
  if FFrames = 0 then Exit(NaN);
  Result := 10 * Log10(FMERSum / FFrames);
end;

function TDABDecoder.GetFICOkPercent: Double;
begin
  if FFibTotal = 0 then Exit(0);
  Result := 100.0 * FFibOk / FFibTotal;
end;

initialization
  BuildTables;
  CheckUEPTables;
end.
