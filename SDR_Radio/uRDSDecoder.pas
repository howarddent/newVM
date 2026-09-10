unit uRDSDecoder;

{*******************************************************************************

     TRDSDecoder - Radio Data System receiver for the broadcast-FM chain
     in uFMReceiver.pas. Takes the same multiplex signal TFMStereoDecoder
     takes (TFMDemodulator's output, 200kHz real - see uFMReceiver.pas's
     own chain description) and produces the station name, programme
     type, radiotext and programme identification carried on the 57kHz
     subcarrier.

     Nothing else in the chain changes: RDS is a second consumer of the
     multiplex, not a stage in the audio path, so an epoch is handed to
     this decoder and to the stereo decoder independently and the audio
     is unaffected by whether RDS is locked, present, or garbage.

     THE SIGNAL

     RDS lives on a 57kHz subcarrier - the third harmonic of the 19kHz
     stereo pilot, which is how it stays clear of the mono (0-15kHz) and
     stereo difference (23-53kHz) parts of the multiplex. It is DSB-SC:
     the carrier itself is suppressed, so there is nothing to lock a
     plain PLL onto and the carrier has to be recovered from the
     modulation. The data rate is 1187.5 bit/s, exactly 57000/48, and
     each bit is biphase (Manchester) coded, so every bit carries a
     transition in its own middle.

     THE CHAIN HERE

       1. Mix the multiplex against a 57kHz complex oscillator, bringing
          the subcarrier to zero. This is a real signal times a complex
          exponential, so the result is complex and the negative-
          frequency image is dealt with by the filtering that follows.
       2. Resample 200kHz -> 19kHz. That number is not arbitrary: 19000
          is exactly 16 x 1187.5, so a bit is exactly 16 samples and the
          timing loop below only ever has to correct for the small
          difference between the transmitter's clock and this receiver's,
          never for a fractional nominal period. The resampler's own
          anti-alias filter also does the real work of rejecting the
          stereo subcarrier, which lands at -19kHz after the mix and
          would otherwise fold directly onto the RDS baseband.
       3. Low-pass to 3kHz, complex, at the new rate - cheap here, and it
          keeps noise between 3 and 9.5kHz out of both the carrier loop
          and the bit decisions.
       4. A Costas loop recovers the suppressed carrier. Its 180 degree
          ambiguity - which arm of the loop is "in phase" is not
          determinable from a DSB-SC signal alone - costs nothing,
          because RDS differentially encodes its data precisely so that
          absolute polarity does not matter. See DecodeBits.
       5. A biphase correlator plus an early-late gate recovers the bit
          clock, and each bit is decided from the sign of the
          correlation.
       6. Differential decode, then block synchronisation by syndrome,
          then group decoding into the fields this exposes.

     WHAT COMES OUT

     ProgrammeService (the 8-character station name), RadioText (up to 64
     characters of free text), ProgrammeType (a number and its name), and
     ProgrammeIdentification (the 16-bit station code). All of them are
     read under a lock - see GetState - because they are written on
     uFMReceiver.pas's own demodulation thread and read on the GUI
     thread.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, syncobjs,
  newVMSingle, newVMComplexSingle, OneAPI,
  uDSPBlocks;

const
  // The subcarrier, the bit rate, and the rate this decoder works at.
  // RDSWorkRateHz / RDSBitRateHz is exactly RDSSamplesPerBit - see the
  // unit header for why that matters.
  RDSSubcarrierHz = 57000.0;
  RDSBitRateHz = 1187.5;
  RDSWorkRateHz = 19000.0;
  RDSSamplesPerBit = 16;

type
  // Which of the five offset words a 26-bit block carries. Cs is the
  // C-prime variant, used by version B groups in place of C.
  TRDSOffset = (roA, roB, roC, roCs, roD);

  { TRDSDecoder }
  TRDSDecoder = class
  private
    FSampleRateHz: Double;

    // Stage 1-3: down-conversion and band limiting
    FNCO: TNCO;
    FResampler: TRationalResamplerC;
    FLPFI, FLPFQ: TFIRFilterS;

    // Stage 4: Costas loop
    FCosPhase, FCosFreq, FCosAlpha, FCosBeta: Double;
    FLockI2, FLockQ2: Double;      // smoothed arm powers, for LockQuality
    FPilotLevel: Double;           // smoothed 19kHz amplitude - see PilotLevel
    FMPXLevel: Double;             // smoothed multiplex RMS - see MultiplexLevel
    FPilotCoeff: Double;           // Goertzel coefficient for 19kHz at SampleRateHz

    // Stage 5: bit clock
    FBitBuf: array of Single;      // circular, holds the recent I arm
    FBitBufHead: Integer;
    FMu: Double;                   // samples until the next bit decision
    FBitPeriod: Double;            // tracked, nominally RDSSamplesPerBit
    FHaveBits: Boolean;

    // Stage 6: differential decode, block sync, groups
    FPrevSymbol: Integer;
    FShift: LongWord;              // rolling 26-bit window
    FShiftCount: Integer;
    FSynced: Boolean;
    FBlockIndex: Integer;          // 0..3, which block is expected next
    FBitsToBlock: Integer;
    FBadBlocks: Integer;
    FBitsSinceSync: Int64;
    FGroupData: array[0..3] of Word;
    FGroupOK: array[0..3] of Boolean;

    // Decoded state, guarded by FLock
    FLock: TCriticalSection;
    FPI: Word;
    FHavePI: Boolean;
    FPTY: Byte;
    FHavePTY: Boolean;
    FTP, FTA: Boolean;
    FPSCand, FPSText: array[0..7] of Char;
    FRTCand, FRTText: array[0..63] of Char;
    FRTLength: Integer;
    FRTFlag: Integer;
    FGroupCount, FBlockErrorCount: Int64;

    procedure ProcessNarrow(const Z: TVMobjC);
    procedure DecideBit;
    procedure PushBit(Bit: Integer);
    procedure HandleBlock(Data: Word; OK: Boolean);
    procedure HandleGroup;
    procedure NudgeBitPhase;
  public
    constructor Create(SampleRateHz: Double);
    destructor Destroy; override;

    // One multiplex epoch, at SampleRateHz. Called from the demodulation
    // thread only.
    procedure Process(const Multiplex: TVMobjS);

    // Forget the station. Called on retune - the previous station's name
    // and text are worse than nothing once the receiver has moved.
    procedure Reset;

    // Thread-safe snapshot of everything decoded so far. Empty strings
    // where nothing has been decoded yet.
    procedure GetState(out PS, RT, PTYName, PIText: string;
                       out Groups, BlockErrors: Int64; out Locked: Boolean);

    // Two numbers that between them say WHERE a failure to decode is,
    // which no amount of staring at an empty station name will.
    //
    // SubcarrierLevel is the RMS of the 57kHz band after down-conversion
    // and filtering - i.e. how much signal is present where RDS lives at
    // all. Zero here means the station is not carrying RDS, or is too
    // weak, or the multiplex never reached this decoder; no amount of
    // loop tuning will help.
    //
    // LockQuality is the fraction of the recovered signal's power that
    // the Costas loop has managed to put on the in-phase arm. A locked
    // BPSK carrier puts nearly all of it there, so this runs towards 1;
    // noise alone splits evenly and sits at 0.5. Together they separate
    // "nothing to decode" from "something there but not locking" from
    // "locked but the bits are wrong".
    function SubcarrierLevel: Double;
    function LockQuality: Double;

    // The 19kHz stereo pilot's amplitude in the same multiplex, measured
    // by a single-bin Goertzel - one multiply-add per sample, against
    // the 165-tap bandpass a filter would have cost.
    //
    // This is here to answer the question the other two cannot. A pilot
    // is transmitted by every stereo broadcast and sits at a known
    // 9% of full deviation, so it is a calibrated reference for how well
    // the multiplex itself is being received. A healthy pilot with noise
    // at 57kHz means the station genuinely carries no RDS; a buried
    // pilot means the signal is too weak for either and the aerial is
    // the thing to fix, not the decoder.
    function PilotLevel: Double;

    // RMS of the whole multiplex, for scale. A discriminator fed noise
    // produces a LARGE output, not a small one, so a big multiplex with
    // no pilot in it is the signature of a signal below the FM
    // threshold - as against a small one, which would mean nothing is
    // reaching the demodulator at all.
    function MultiplexLevel: Double;
  end;

// 0..31 -> the EN 50067 programme-type names (the European RDS table -
// North American RBDS assigns several of these numbers differently; see
// the note in the implementation).
function RDSProgrammeTypeName(PTY: Byte): string;

implementation

const
  // The five offset words, from the RDS standard. A block is 26 bits:
  // 16 data bits followed by a 10-bit checkword, and the checkword is
  // the data's CRC with one of these XORed into it - which is what makes
  // a block self-identifying, since the syndrome of a correctly received
  // block comes out equal to its own offset word (see RDSSyndrome).
  OffsetWord: array[TRDSOffset] of Word =
    ($0FC, $198, $168, $350, $1B4);

  // Generator polynomial of the shortened cyclic (26,16) code:
  // x^10 + x^8 + x^7 + x^5 + x^4 + x^3 + 1.
  RDSGenerator = $5B9;

  // European (EN 50067) programme types. RBDS, used in North America,
  // shares the numbering only for a few entries - so a receiver built
  // for one and used with the other reports plausible nonsense rather
  // than obvious nonsense. This app de-emphasises at 75us, which is the
  // North American convention, but its RDS is the European table; if
  // that combination ever matters, this is the place it is decided.
  PTYNames: array[0..31] of string = (
    '', 'News', 'Current Affairs', 'Information',
    'Sport', 'Education', 'Drama', 'Culture',
    'Science', 'Varied', 'Pop Music', 'Rock Music',
    'Easy Listening', 'Light Classical', 'Serious Classical', 'Other Music',
    'Weather', 'Finance', 'Children''s Programmes', 'Social Affairs',
    'Religion', 'Phone In', 'Travel', 'Leisure',
    'Jazz Music', 'Country Music', 'National Music', 'Oldies Music',
    'Folk Music', 'Documentary', 'Alarm Test', 'Alarm');

function RDSProgrammeTypeName(PTY: Byte): string;
begin
  if PTY <= 31 then Result := PTYNames[PTY] else Result := '';
end;

{ Syndrome of a 26-bit block: the remainder of the block polynomial
  divided by the generator, done as plain long division rather than with
  a shift register - sixteen iterations per block is nothing here, and
  the loop below is obviously the definition rather than an encoding of
  it that has to be trusted.

  The useful consequence: a block whose checkword carries offset word O
  has syndrome exactly O. The division only ever touches bits 10 and
  above, so a block consisting of nothing but O in its low ten bits
  passes through untouched - and since the syndrome is linear and a
  correct codeword has syndrome zero, what comes out of a received block
  is the offset word itself. Block identification is therefore just a
  comparison, with no table of precomputed syndromes to get wrong. }
function RDSSyndrome(Block: LongWord): Word;
var
  i: Integer;
  Reg: LongWord;
begin
  Reg := Block and $3FFFFFF;
  for i := 25 downto 10 do
    if (Reg and (LongWord(1) shl i)) <> 0 then
      Reg := Reg xor (LongWord(RDSGenerator) shl (i - 10));
  Result := Reg and $3FF;
end;

{ TRDSDecoder }

constructor TRDSDecoder.Create(SampleRateHz: Double);
const
  // Costas loop bandwidth. The residual carrier offset after mixing
  // against a fixed 57kHz is only the receiver's own clock error - a few
  // hertz at worst - so this only has to acquire phase, and a narrow
  // loop keeps the recovered carrier clean on a weak signal.
  CostasBandwidthHz = 25.0;
  Zeta = 0.707;
var
  Theta, Denom: Double;
begin
  inherited Create;
  FSampleRateHz := SampleRateHz;
  FLock := TCriticalSection.Create;

  // Negative frequency: mixing against exp(-j*2*pi*57000*t) is what
  // brings the subcarrier down to zero rather than up to 114kHz.
  FPilotCoeff := 2 * Cos(2 * Pi * 19000.0 / SampleRateHz);

  FNCO := TNCO.Create(SampleRateHz, -RDSSubcarrierHz);
  FResampler := TRationalResamplerC.Create(SampleRateHz, RDSWorkRateHz, 2000);
  FLPFI := TFIRFilterS.Create(DesignLowpassFIR(3000, RDSWorkRateHz, 1500, 1.0));
  FLPFQ := TFIRFilterS.Create(DesignLowpassFIR(3000, RDSWorkRateHz, 1500, 1.0));

  // Same closed-form second-order loop constants TAMDemodulator's own
  // carrier PLL uses - see that constructor.
  Theta := CostasBandwidthHz / (RDSWorkRateHz * (Zeta + 1 / (4 * Zeta)));
  Denom := 1 + 2 * Zeta * Theta + Theta * Theta;
  FCosAlpha := (4 * Zeta * Theta) / Denom;
  FCosBeta := (4 * Theta * Theta) / Denom;

  // Two bits' worth, so the early-late gate can look a whole symbol back
  // and still have a sample either side of it.
  SetLength(FBitBuf, 4 * RDSSamplesPerBit);

  Reset;
end;

destructor TRDSDecoder.Destroy;
begin
  FNCO.Free;
  FResampler.Free;
  FLPFI.Free;
  FLPFQ.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TRDSDecoder.Reset;
var
  i: Integer;
begin
  FCosPhase := 0;
  FCosFreq := 0;
  FLockI2 := 0;
  FLockQ2 := 0;
  FPilotLevel := 0;
  FMPXLevel := 0;

  for i := 0 to High(FBitBuf) do FBitBuf[i] := 0;
  FBitBufHead := 0;
  FMu := RDSSamplesPerBit;
  FBitPeriod := RDSSamplesPerBit;
  FHaveBits := False;

  FPrevSymbol := 0;
  FShift := 0;
  FShiftCount := 0;
  FSynced := False;
  FBlockIndex := 0;
  FBitsToBlock := 0;
  FBadBlocks := 0;
  FBitsSinceSync := 0;
  for i := 0 to 3 do begin
    FGroupData[i] := 0;
    FGroupOK[i] := False;
  end;

  FLock.Acquire;
  try
    FPI := 0;
    FHavePI := False;
    FPTY := 0;
    FHavePTY := False;
    FTP := False;
    FTA := False;
    for i := 0 to 7 do begin FPSCand[i] := ' '; FPSText[i] := ' '; end;
    for i := 0 to 63 do begin FRTCand[i] := ' '; FRTText[i] := ' '; end;
    FRTLength := 0;
    FRTFlag := -1;
    FGroupCount := 0;
    FBlockErrorCount := 0;
  finally
    FLock.Release;
  end;
end;

procedure TRDSDecoder.Process(const Multiplex: TVMobjS);
var
  N, i: Integer;
  LO, Base, Narrow: TVMobjC;
  m: Single;
  G0, G1, G2, Power, SumSq: Double;
begin
  N := Multiplex.Rows * Multiplex.Cols;
  if N <= 0 then Exit;

  // Real signal times a complex exponential - done by hand rather than
  // through TComplexMixer, which takes a complex input. Note also that
  // mixed real/complex '*' in this library is a MATRIX product, not an
  // elementwise one (see the repository's own CLAUDE.md on operator
  // overloads), so an elementwise loop is the correct thing here in any
  // case.
  // Goertzel at 19kHz over this epoch, for the pilot diagnostic - folded
  // into the mixing loop below so it costs one pass, not two.
  G0 := 0;
  G1 := 0;
  G2 := 0;
  SumSq := 0;

  LO := FNCO.Generate(N);
  Base := TVMobjC.Create(1, N);
  for i := 0 to N - 1 do begin
    m := Multiplex[0, i];
    Base[0, i] := Cplx8(m * LO[0, i].re, m * LO[0, i].im);

    G0 := m + FPilotCoeff * G1 - G2;
    G2 := G1;
    G1 := G0;
    SumSq := SumSq + m * m;
  end;

  // Goertzel magnitude, scaled to the amplitude of a sinusoid at that
  // bin, then smoothed across epochs so a single quiet moment does not
  // read as a lost pilot.
  Power := G1 * G1 + G2 * G2 - FPilotCoeff * G1 * G2;
  if Power < 0 then Power := 0;
  FPilotLevel := FPilotLevel + 0.25 * (2 * Sqrt(Power) / N - FPilotLevel);
  FMPXLevel := FMPXLevel + 0.25 * (Sqrt(SumSq / N) - FMPXLevel);

  Narrow := FResampler.Process(Base);
  ProcessNarrow(Narrow);
end;

procedure TRDSDecoder.ProcessNarrow(const Z: TVMobjC);
const
  // Averaging for the lock indicator only - slow enough that a momentary
  // fade does not read as loss of lock.
  LockTau = 0.001;
var
  N, i: Integer;
  Re, Im, ReF, ImF: TVMobjS;
  I0, Q0, Ir, Qr, c, s, err, mag2: Double;
begin
  N := Z.Rows * Z.Cols;
  if N <= 0 then Exit;

  // A complex low-pass is two real ones - TFIRFilterS is real-only, and
  // reusing it keeps this on the same tested filter code the rest of the
  // chain uses rather than introducing a second implementation.
  Re := TVMobjS.Create(1, N);
  Im := TVMobjS.Create(1, N);
  for i := 0 to N - 1 do begin
    Re[0, i] := Z[0, i].re;
    Im[0, i] := Z[0, i].im;
  end;
  ReF := FLPFI.Process(Re);
  ImF := FLPFQ.Process(Im);

  for i := 0 to N - 1 do begin
    I0 := ReF[0, i];
    Q0 := ImF[0, i];

    // Rotate by the loop's current phase estimate.
    c := Cos(FCosPhase);
    s := Sin(FCosPhase);
    Ir := I0 * c + Q0 * s;
    Qr := -I0 * s + Q0 * c;

    // Costas error for BPSK. The product of the two arms is
    // (A^2/2)*sin(2*phase error) - the data sign appears squared and so
    // cancels, which is exactly what lets a Costas loop track a carrier
    // that is not there. Normalised by the magnitude so the loop
    // bandwidth does not move with signal strength.
    mag2 := Ir * Ir + Qr * Qr;
    if mag2 > 1E-12 then err := (Ir * Qr) / mag2 else err := 0;

    FCosFreq := FCosFreq + FCosBeta * err;
    FCosPhase := FCosPhase + FCosFreq + FCosAlpha * err;
    while FCosPhase > Pi do FCosPhase := FCosPhase - 2 * Pi;
    while FCosPhase < -Pi do FCosPhase := FCosPhase + 2 * Pi;

    FLockI2 := FLockI2 + LockTau * (Ir * Ir - FLockI2);
    FLockQ2 := FLockQ2 + LockTau * (Qr * Qr - FLockQ2);

    FBitBuf[FBitBufHead] := Ir;
    FBitBufHead := (FBitBufHead + 1) mod Length(FBitBuf);

    FMu := FMu - 1;
    if FMu <= 0 then begin
      DecideBit;
      FMu := FMu + FBitPeriod;
    end;
  end;
end;

{ One bit out of the in-phase arm, and the timing correction that keeps
  the next one in the right place.

  A biphase symbol is half a bit of one polarity followed by half a bit
  of the other, so correlating a bit-long window against [+1 x 8, -1 x 8]
  gives a peak exactly when the window sits on a symbol, with the sign of
  the symbol. That correlation is both the matched filter and the timing
  discriminator: an early-late gate compares the correlation magnitude
  one sample either side of where the loop currently thinks the symbol
  is, and steers towards whichever is larger.

  The alignment this converges to is not unique: a window half a bit out
  straddles two symbols, and when consecutive symbols happen to be equal
  it correlates just as strongly. What separates the two is that a
  correctly aligned window correlates strongly ALWAYS, and a half-bit-out
  window only half the time - so the average gradient points the right
  way, if not steeply. NudgeBitPhase exists for the case where it settles
  in the wrong place anyway. }
procedure TRDSDecoder.DecideBit;
const
  Kp = 0.05;      // phase correction, in samples per unit of error
  Ki = 0.0008;    // and the slow period correction underneath it
var
  OnTime, Early, Late, TErr, Denom: Double;
  Symbol: Integer;

  // Correlation of the bit-long window ending Offset samples before the
  // newest sample in the buffer. Offset 1 is the window the loop
  // currently believes in; 2 and 0 are one sample either side of it.
  function Corr(Offset: Integer): Double;
  var
    k, idx, n: Integer;
    acc: Double;
  begin
    n := Length(FBitBuf);
    acc := 0;
    for k := 0 to RDSSamplesPerBit - 1 do begin
      idx := ((FBitBufHead - Offset - RDSSamplesPerBit + k) mod n + n) mod n;
      if k < RDSSamplesPerBit div 2 then
        acc := acc + FBitBuf[idx]
      else
        acc := acc - FBitBuf[idx];
    end;
    Result := acc;
  end;

begin
  OnTime := Corr(1);
  Early := Corr(2);
  Late := Corr(0);

  Denom := Abs(Late) + Abs(Early);
  if Denom > 1E-9 then TErr := (Abs(Late) - Abs(Early)) / Denom else TErr := 0;

  FMu := FMu + Kp * TErr;
  FBitPeriod := FBitPeriod + Ki * TErr;
  // The transmitter's bit clock and this receiver's differ by their
  // combined oscillator error, which is parts per million - anything
  // further out than this is the loop misbehaving, not a real clock.
  FBitPeriod := EnsureRange(FBitPeriod, RDSSamplesPerBit - 0.1, RDSSamplesPerBit + 0.1);

  if OnTime > 0 then Symbol := 1 else Symbol := 0;

  // Differential decode. RDS encodes each data bit as a CHANGE of symbol
  // rather than as a symbol, which is what makes the Costas loop's 180
  // degree ambiguity harmless: invert every symbol and every change
  // between them is unaltered.
  if FHaveBits then
    PushBit(Symbol xor FPrevSymbol)
  else
    FHaveBits := True;
  FPrevSymbol := Symbol;
end;

{ Shift the bit clock half a symbol.

  The early-late gate can settle half a bit out - see DecodeBit - and
  when it does, no amount of waiting will produce a valid block, because
  every window straddles two symbols. Nothing in the timing loop can tell
  that has happened; only the total absence of block synchronisation
  can. So after a few seconds of finding no block A at all, this shifts
  deliberately and lets the loop resettle. On a station with no RDS at
  all it fires harmlessly for ever. }
procedure TRDSDecoder.NudgeBitPhase;
begin
  FMu := FMu + FBitPeriod / 2;
  FBitsSinceSync := 0;
end;

{ One recovered data bit into the 26-bit window, and the block
  synchronisation that runs off it.

  Unsynchronised, every bit is a candidate: the window's syndrome is
  compared against offset word A, and a match means the last 26 bits were
  a block A. That is a 1-in-1024 chance on random data, which sounds weak
  until you notice what follows - the next three blocks are then checked
  against B, C (or C') and D in turn, and four consecutive failures throw
  the synchronisation away again. A false lock costs one group and
  corrects itself. }
procedure TRDSDecoder.PushBit(Bit: Integer);
var
  Syn: Word;
  OK: Boolean;
begin
  FShift := ((FShift shl 1) or LongWord(Bit and 1)) and $3FFFFFF;
  if FShiftCount < 26 then Inc(FShiftCount);
  Inc(FBitsSinceSync);

  if not FSynced then begin
    if FShiftCount < 26 then Exit;

    if RDSSyndrome(FShift) = OffsetWord[roA] then begin
      FSynced := True;
      FBadBlocks := 0;
      FBitsSinceSync := 0;
      FGroupData[0] := Word((FShift shr 10) and $FFFF);
      FGroupOK[0] := True;
      FGroupOK[1] := False;
      FGroupOK[2] := False;
      FGroupOK[3] := False;
      FBlockIndex := 1;
      FBitsToBlock := 26;
    end
    // Roughly three and a half seconds of finding nothing - see
    // NudgeBitPhase for what this is really testing for.
    else if FBitsSinceSync > 4000 then
      NudgeBitPhase;

    Exit;
  end;

  Dec(FBitsToBlock);
  if FBitsToBlock > 0 then Exit;

  Syn := RDSSyndrome(FShift);
  case FBlockIndex of
    0: OK := Syn = OffsetWord[roA];
    1: OK := Syn = OffsetWord[roB];
    // Version B groups substitute C' for C, and which it is says nothing
    // this decoder needs - the version is already in block B.
    2: OK := (Syn = OffsetWord[roC]) or (Syn = OffsetWord[roCs]);
  else
    OK := Syn = OffsetWord[roD];
  end;

  HandleBlock(Word((FShift shr 10) and $FFFF), OK);
end;

procedure TRDSDecoder.HandleBlock(Data: Word; OK: Boolean);
begin
  FGroupData[FBlockIndex] := Data;
  FGroupOK[FBlockIndex] := OK;

  if OK then
    FBadBlocks := 0
  else begin
    Inc(FBadBlocks);
    FLock.Acquire;
    try
      Inc(FBlockErrorCount);
    finally
      FLock.Release;
    end;
  end;

  // A fade drops a block or two; being in the wrong place drops all of
  // them. Four in a row is the difference.
  if FBadBlocks >= 4 then begin
    FSynced := False;
    FBadBlocks := 0;
    FBitsSinceSync := 0;
    Exit;
  end;

  if FBlockIndex = 3 then begin
    HandleGroup;
    FBlockIndex := 0;
  end else
    Inc(FBlockIndex);

  FBitsToBlock := 26;
end;

{ A complete group, decoded into the fields this unit exposes.

  Only two group types are read. Type 0 carries the programme service
  name - the eight characters that are what anyone means by the station's
  name - two at a time, with their position given by the low two bits of
  block B. Type 2 carries radiotext, four characters at a time in version
  A and two in version B. Everything else (clock time, alternative
  frequencies, in-house data) is skipped: it would decode with the same
  machinery if it were ever wanted, but none of it is a station name or
  programme information.

  Characters are published only on the SECOND consecutive agreement at
  the same position. A bad block that passes its checkword by chance
  would otherwise put a wrong letter into the station name and leave it
  there until the station next sent that position; requiring two makes
  that vanishingly unlikely, at the cost of one extra group - under a
  tenth of a second - before a name first appears. }
procedure TRDSDecoder.HandleGroup;
var
  GroupType, Addr, i, Base, NewFlag: Integer;
  VersionB: Boolean;

  procedure PutPS(Position: Integer; Ch: Char);
  begin
    if (Position < 0) or (Position > 7) then Exit;
    if FPSCand[Position] = Ch then FPSText[Position] := Ch;
    FPSCand[Position] := Ch;
  end;

  procedure PutRT(Position: Integer; Ch: Char);
  begin
    if (Position < 0) or (Position > 63) then Exit;
    if FRTCand[Position] = Ch then FRTText[Position] := Ch;
    FRTCand[Position] := Ch;
  end;

begin
  FLock.Acquire;
  try
    Inc(FGroupCount);

    if FGroupOK[0] then begin
      FPI := FGroupData[0];
      FHavePI := True;
    end;

    // Everything below is addressed by block B; without it the group is
    // just four numbers.
    if not FGroupOK[1] then Exit;

    GroupType := (FGroupData[1] shr 12) and $0F;
    VersionB := ((FGroupData[1] shr 11) and 1) <> 0;
    FTP := ((FGroupData[1] shr 10) and 1) <> 0;
    FPTY := (FGroupData[1] shr 5) and $1F;
    FHavePTY := True;

    // Version B groups repeat the programme identification in block C,
    // so a station whose block A keeps failing is still identifiable.
    if VersionB and FGroupOK[2] then begin
      FPI := FGroupData[2];
      FHavePI := True;
    end;

    case GroupType of
      0: begin
           FTA := ((FGroupData[1] shr 4) and 1) <> 0;
           if FGroupOK[3] then begin
             Addr := FGroupData[1] and $03;
             PutPS(2 * Addr, Chr((FGroupData[3] shr 8) and $FF));
             PutPS(2 * Addr + 1, Chr(FGroupData[3] and $FF));
           end;
         end;

      2: begin
           // The A/B flag toggles when the station starts a new message;
           // without honouring it, the tail of the old text stays behind
           // the new one for as long as the new one is shorter.
           NewFlag := (FGroupData[1] shr 4) and 1;
           if (FRTFlag >= 0) and (NewFlag <> FRTFlag) then
             for i := 0 to 63 do begin
               FRTText[i] := ' ';
               FRTCand[i] := ' ';
             end;
           FRTFlag := NewFlag;

           Addr := FGroupData[1] and $0F;
           if VersionB then begin
             // 2B: two characters per group, 32 characters in all.
             if FGroupOK[3] then begin
               PutRT(2 * Addr, Chr((FGroupData[3] shr 8) and $FF));
               PutRT(2 * Addr + 1, Chr(FGroupData[3] and $FF));
             end;
           end else begin
             // 2A: four characters per group, from blocks C and D.
             Base := 4 * Addr;
             if FGroupOK[2] then begin
               PutRT(Base, Chr((FGroupData[2] shr 8) and $FF));
               PutRT(Base + 1, Chr(FGroupData[2] and $FF));
             end;
             if FGroupOK[3] then begin
               PutRT(Base + 2, Chr((FGroupData[3] shr 8) and $FF));
               PutRT(Base + 3, Chr(FGroupData[3] and $FF));
             end;
           end;
         end;
    end;
  finally
    FLock.Release;
  end;
end;

function TRDSDecoder.SubcarrierLevel: Double;
begin
  Result := Sqrt(Max(FLockI2 + FLockQ2, 0));
end;

function TRDSDecoder.PilotLevel: Double;
begin
  Result := FPilotLevel;
end;

function TRDSDecoder.MultiplexLevel: Double;
begin
  Result := FMPXLevel;
end;

function TRDSDecoder.LockQuality: Double;
var
  Total: Double;
begin
  Total := FLockI2 + FLockQ2;
  if Total > 1E-18 then Result := FLockI2 / Total else Result := 0;
end;

procedure TRDSDecoder.GetState(out PS, RT, PTYName, PIText: string;
                               out Groups, BlockErrors: Int64; out Locked: Boolean);
var
  i, CutAt: Integer;
  Buf: string;

  // RDS carries its own character set, most of which coincides with
  // ASCII over the printable range and none of which is worth rendering
  // faithfully here - anything outside becomes a space rather than a box.
  function Printable(Ch: Char): Char;
  begin
    if (Ch >= ' ') and (Ch <= '~') then Result := Ch else Result := ' ';
  end;

begin
  FLock.Acquire;
  try
    SetLength(Buf, 8);
    for i := 0 to 7 do Buf[i + 1] := Printable(FPSText[i]);
    PS := TrimRight(Buf);

    SetLength(Buf, 64);
    CutAt := 0;
    for i := 0 to 63 do begin
      // Carriage return ends the message; past it is whatever a previous,
      // longer one left behind.
      if (CutAt = 0) and (FRTText[i] = #13) then CutAt := i;
      Buf[i + 1] := Printable(FRTText[i]);
    end;
    if CutAt > 0 then Buf := Copy(Buf, 1, CutAt);
    RT := TrimRight(Buf);

    if FHavePTY then PTYName := RDSProgrammeTypeName(FPTY) else PTYName := '';
    if FHavePI then PIText := IntToHex(FPI, 4) else PIText := '';

    Groups := FGroupCount;
    BlockErrors := FBlockErrorCount;
    Locked := FSynced;
  finally
    FLock.Release;
  end;
end;

end.
