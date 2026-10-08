unit uDABAudio;

{*******************************************************************************

     TDABAudioDecoder - turns one sub-channel's logical frames (from
     uDABDecoder.pas's TDABDecoder.OnLogicalFrame, one every 24 ms) into
     stereo PCM, for either kind of DAB audio service:

     DAB (MPEG-1/2 Layer II, "MP2"). Each logical frame is one MP2 audio
     frame (24 ms at 48 kHz; half of one at 24 kHz), ancillary programme-
     associated data and all. The bytes go straight into libmpg123 in
     feed mode, which finds the frame headers itself and ignores the
     ancillary data.

     DAB+ (HE-AAC, ETSI TS 102 563). Five logical frames form a 120 ms
     audio superframe, and nothing in a single frame says which of the
     five it is:
       1. Superframe sync: a superframe starts with a 16-bit fire code (a
          CRC over the next 9 header bytes). Frames are queued, and a
          window of five is accepted when its first frame's fire code
          checks - before Reed-Solomon, or failing that after it, since
          errors in the header itself are exactly what RS is there to
          fix. A window that fails both is slid along by one frame.
       2. Reed-Solomon: the superframe is s = bitrate/8 interleaved
          RS(120,110) codewords - byte k of codeword j at superframe
          position j + k*s - shortened from RS(255,245) over GF(256)
          (x^8+x^4+x^3+x^2+1, generator roots alpha^0..alpha^9), each
          correcting up to 5 byte errors.
       3. The header says how the 110*s data bytes split into 2, 3, 4 or
          6 access units (AUs) - fewer, longer ones at the lower sample
          rates - each ending in its own CRC-16. AUs that fail their CRC
          are dropped, not decoded.
       4. Each good AU is one AAC frame for libfaad2, initialised from a
          two-byte AudioSpecificConfig built from the header: AAC-LC, the
          core sample rate, mono or stereo, and the 960-sample frame
          length (the only way to ask faad2 for it). SBR and PS are left
          to faad2's implicit signalling - it assumes SBR at core rates
          of 24 kHz and below, and outputs stereo whenever PS is present.

     OUTPUT is OnAudio with a left and a right TVMobjS at the codec's own
     output rate (48, 32, 24 or 16 kHz - the receiver opens the sound
     device at whatever this reports); mono services are duplicated to
     both channels.

     Not thread-aware: owned and fed by one thread (uDABReceiver.pas's).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, ctypes, newVMSingle, uDABCodecs;

type
  TDABAudioOutEvent = procedure(Sender: TObject; const L, R: TVMobjS; SampleRateHz: Integer) of object;

  { TDABAudioDecoder }
  TDABAudioDecoder = class
  private
    FIsDABPlus: Boolean;
    FBitrateKbps: Integer;
    FOnAudio: TDABAudioOutEvent;
    FLastError: string;
    FFormatText: string;

    // MP2
    FMpg: Pointer;
    FMpgRate, FMpgChannels: Integer;
    FPCM16: array of SmallInt;

    // DAB+
    FFrames: array[0..4] of TBytes;   // queued logical frames, oldest first
    FFrameCount: Integer;
    FSF: TBytes;                      // superframe being processed
    FAAC: Pointer;
    FAACHeader: Integer;              // header byte the decoder was set up for, -1 none

    // statistics
    FLogicalFrames, FSuperframes, FSyncSlips: Int64;
    FRSCorrected, FRSFailed: Int64;
    FAUsOk, FAUsBad: Int64;
    FAudioFrames: Int64;

    procedure FeedMP2(const Data: TBytes);
    procedure FeedDABPlus(const Data: TBytes);
    function ProcessSuperframe: Boolean;
    procedure DecodeAU(P: PByte; Len: Integer);
    procedure SetupAAC(Header: Byte);
    procedure Emit(const Interleaved: PSingle; Frames, Channels, Rate: Integer);
  public
    constructor Create(IsDABPlus: Boolean; BitrateKbps: Integer);
    destructor Destroy; override;
    procedure FeedLogicalFrame(const Data: TBytes);

    property OnAudio: TDABAudioOutEvent read FOnAudio write FOnAudio;
    property LastError: string read FLastError;
    property FormatText: string read FFormatText;   // e.g. 'HE-AAC v2, 48 kHz'
    property LogicalFrames: Int64 read FLogicalFrames;
    property Superframes: Int64 read FSuperframes;
    property SyncSlips: Int64 read FSyncSlips;
    property RSCorrectedBytes: Int64 read FRSCorrected;
    property RSFailedCodewords: Int64 read FRSFailed;
    property AUsOk: Int64 read FAUsOk;
    property AUsBad: Int64 read FAUsBad;
    property AudioFrames: Int64 read FAudioFrames;
  end;

// Reed-Solomon RS(255,245) over GF(256), as DAB+ uses it - exposed for the
// round-trip self-test. Cw is a full 255-byte codeword (DAB+'s shortened
// RS(120,110) is the last 120 bytes, the first 135 zero). Decode returns
// the number of bytes corrected, or -1 if uncorrectable.
procedure RSEncode(var Cw: array of Byte);
function RSDecode(var Cw: array of Byte): Integer;

function DABCRC16(P: PByte; Len: Integer): Word;

implementation

const
  RS_N = 255;
  RS_K = 245;
  RS_NROOTS = 10;
  RS_SHORT = 135;     // 255 - 120

var
  GFExp: array[0..511] of Byte;
  GFLog: array[0..255] of Integer;
  RSGen: array[0..RS_NROOTS] of Byte;   // generator, highest degree first

procedure BuildGF;
var
  i, x, j: Integer;
begin
  x := 1;
  for i := 0 to 254 do begin
    GFExp[i] := x;
    GFLog[x] := i;
    x := x shl 1;
    if x and $100 <> 0 then x := x xor $11D;
  end;
  for i := 255 to 511 do GFExp[i] := GFExp[i - 255];
  GFLog[0] := -1;

  // g(x) = prod_{j=0..9} (x + alpha^j), coefficients highest degree first.
  RSGen[0] := 1;
  for i := 1 to RS_NROOTS do RSGen[i] := 0;
  for j := 0 to RS_NROOTS - 1 do
    for i := j + 1 downto 1 do
      if RSGen[i - 1] <> 0 then
        RSGen[i] := RSGen[i] xor GFExp[GFLog[RSGen[i - 1]] + j];
end;

function GFMul(a, b: Byte): Byte; inline;
begin
  if (a = 0) or (b = 0) then Result := 0
  else Result := GFExp[GFLog[a] + GFLog[b]];
end;

function GFDiv(a, b: Byte): Byte; inline;
begin
  if a = 0 then Result := 0
  else Result := GFExp[(GFLog[a] - GFLog[b] + 255) mod 255];
end;

procedure RSEncode(var Cw: array of Byte);
var
  i, j: Integer;
  Fb: Byte;
  Par: array[0..RS_NROOTS - 1] of Byte;
begin
  for i := 0 to RS_NROOTS - 1 do Par[i] := 0;
  for i := 0 to RS_K - 1 do begin
    Fb := Cw[i] xor Par[0];
    for j := 0 to RS_NROOTS - 2 do
      Par[j] := Par[j + 1] xor GFMul(Fb, RSGen[j + 1]);
    Par[RS_NROOTS - 1] := GFMul(Fb, RSGen[RS_NROOTS]);
  end;
  for i := 0 to RS_NROOTS - 1 do Cw[RS_K + i] := Par[i];
end;

// Byte i of the codeword is the coefficient of x^(254-i). Syndromes,
// Berlekamp-Massey for the error locator, Chien search for its roots,
// Forney for the values (first consecutive root alpha^0).
function RSDecode(var Cw: array of Byte): Integer;
var
  S: array[0..RS_NROOTS - 1] of Byte;
  Lambda, B, T, Omega: array[0..RS_NROOTS] of Byte;
  i, j, r, L, Deg, Count, p: Integer;
  Delta, Xinv, Num, Den, Sum, AnyS: Byte;
  ErrPos: array[0..RS_NROOTS] of Integer;
  ErrX: array[0..RS_NROOTS] of Byte;
begin
  AnyS := 0;
  for j := 0 to RS_NROOTS - 1 do begin
    Sum := 0;
    for i := 0 to RS_N - 1 do
      Sum := GFMul(Sum, GFExp[j]) xor Cw[i];   // Horner at alpha^j
    S[j] := Sum;
    AnyS := AnyS or Sum;
  end;
  if AnyS = 0 then Exit(0);

  // Berlekamp-Massey.
  for i := 0 to RS_NROOTS do begin Lambda[i] := 0; B[i] := 0; end;
  Lambda[0] := 1; B[0] := 1;
  L := 0;
  for r := 0 to RS_NROOTS - 1 do begin
    Delta := 0;
    for i := 0 to L do
      if (i <= r) then Delta := Delta xor GFMul(Lambda[i], S[r - i]);
    // B := x*B
    for i := RS_NROOTS downto 1 do B[i] := B[i - 1];
    B[0] := 0;
    if Delta <> 0 then begin
      for i := 0 to RS_NROOTS do T[i] := Lambda[i] xor GFMul(Delta, B[i]);
      if 2 * L <= r then begin
        L := r + 1 - L;
        for i := 0 to RS_NROOTS do B[i] := GFDiv(Lambda[i], Delta);
      end;
      Lambda := T;
    end;
  end;
  Deg := 0;
  for i := 0 to RS_NROOTS do if Lambda[i] <> 0 then Deg := i;
  if (Deg <> L) or (L > RS_NROOTS div 2) then Exit(-1);

  // Chien search: an error at the coefficient of x^p has locator
  // X = alpha^p, a root of Lambda at X^-1.
  Count := 0;
  for p := 0 to RS_N - 1 do begin
    Sum := 0;
    Xinv := GFExp[(255 - p) mod 255];
    for i := L downto 0 do
      Sum := GFMul(Sum, Xinv) xor Lambda[i];
    if Sum = 0 then begin
      if Count > RS_NROOTS then Exit(-1);
      ErrPos[Count] := RS_N - 1 - p;
      ErrX[Count] := GFExp[p];
      Inc(Count);
    end;
  end;
  if Count <> L then Exit(-1);

  // Omega = S * Lambda mod x^10.
  for i := 0 to RS_NROOTS do Omega[i] := 0;
  for i := 0 to RS_NROOTS - 1 do
    for j := 0 to Min(L, i) do
      Omega[i] := Omega[i] xor GFMul(S[i - j], Lambda[j]);

  for j := 0 to Count - 1 do begin
    if ErrPos[j] < RS_SHORT then Exit(-1);   // "error" in the shortening zeros: miscorrection
    Xinv := GFDiv(1, ErrX[j]);
    Num := 0;
    for i := RS_NROOTS - 1 downto 0 do Num := GFMul(Num, Xinv) xor Omega[i];
    // Lambda'(x): formal derivative keeps the odd-power terms.
    Den := 0;
    i := 1;
    while i <= L do begin
      Den := Den xor GFMul(Lambda[i], GFExp[(GFLog[Xinv] * (i - 1)) mod 255]);
      Inc(i, 2);
    end;
    if Den = 0 then Exit(-1);
    // fcr = 0: e = X * Omega(X^-1) / Lambda'(X^-1)
    Cw[ErrPos[j]] := Cw[ErrPos[j]] xor GFMul(ErrX[j], GFDiv(Num, Den));
  end;
  Result := Count;
end;

// CRC-16 CCITT, initial all ones, inverted - the AU check (and the same
// CRC as a FIB's).
function DABCRC16(P: PByte; Len: Integer): Word;
var
  i, b: Integer;
  Crc: Word;
begin
  Crc := $FFFF;
  for i := 0 to Len - 1 do begin
    Crc := Crc xor (Word(P[i]) shl 8);
    for b := 1 to 8 do
      if (Crc and $8000) <> 0 then Crc := Word((Crc shl 1) xor $1021)
      else Crc := Word(Crc shl 1);
  end;
  Result := Crc xor $FFFF;
end;

// The DAB+ superframe fire code: G(x) = (x^11 + 1)(x^5 + x^3 + x^2 + x + 1),
// computed over header bytes 2..10, stored in bytes 0..1.
function FireCodeOk(P: PByte): Boolean;
var
  i, b: Integer;
  Crc: Word;
  Bit: Boolean;
begin
  Crc := 0;
  for i := 2 to 10 do
    for b := 7 downto 0 do begin
      Bit := (((P[i] shr b) and 1) <> 0) xor ((Crc and $8000) <> 0);
      Crc := Word(Crc shl 1);
      if Bit then Crc := Crc xor $782F;
    end;
  Result := (Crc = (Word(P[0]) shl 8 or P[1])) and ((P[0] or P[1] or P[2] or P[3]) <> 0);
end;

{ TDABAudioDecoder }

constructor TDABAudioDecoder.Create(IsDABPlus: Boolean; BitrateKbps: Integer);
var
  Err: cint;
begin
  inherited Create;
  FIsDABPlus := IsDABPlus;
  FBitrateKbps := BitrateKbps;
  FAACHeader := -1;
  if IsDABPlus then begin
    if not LoadFAAD then FLastError := 'DAB+ needs libfaad2 (faad), which was not found';
  end else begin
    if not LoadMPG123 then
      FLastError := 'DAB needs libmpg123, which was not found'
    else begin
      FMpg := mpg123_new(nil, @Err);
      if FMpg = nil then FLastError := 'mpg123_new failed'
      else begin
        mpg123_param(FMpg, MPG123_ADD_FLAGS, MPG123_QUIET, 0);
        // 16-bit output at either DAB rate; mono or stereo as transmitted.
        mpg123_format_none(FMpg);
        mpg123_format(FMpg, 48000, MPG123_MONO or MPG123_STEREO, MPG123_ENC_SIGNED_16);
        mpg123_format(FMpg, 24000, MPG123_MONO or MPG123_STEREO, MPG123_ENC_SIGNED_16);
        if mpg123_open_feed(FMpg) <> MPG123_OK then FLastError := 'mpg123_open_feed failed';
      end;
    end;
  end;
end;

destructor TDABAudioDecoder.Destroy;
begin
  if Assigned(FMpg) then mpg123_delete(FMpg);
  if Assigned(FAAC) then NeAACDecClose(FAAC);
  inherited Destroy;
end;

procedure TDABAudioDecoder.FeedLogicalFrame(const Data: TBytes);
begin
  Inc(FLogicalFrames);
  if FLastError <> '' then Exit;
  if Length(Data) = 0 then Exit;
  if FIsDABPlus then FeedDABPlus(Data) else FeedMP2(Data);
end;

procedure TDABAudioDecoder.Emit(const Interleaved: PSingle; Frames, Channels, Rate: Integer);
var
  L, R: TVMobjS;
  i: Integer;
begin
  if (Frames <= 0) or (Channels <= 0) then Exit;
  Inc(FAudioFrames);
  if not Assigned(FOnAudio) then Exit;
  L := TVMobjS.Create(1, Frames);
  R := TVMobjS.Create(1, Frames);
  for i := 0 to Frames - 1 do begin
    L[0, i] := Interleaved[i * Channels];
    if Channels >= 2 then R[0, i] := Interleaved[i * Channels + 1]
    else R[0, i] := L[0, i];
  end;
  FOnAudio(Self, L, R, Rate);
end;

{ ---- MP2 ---- }

procedure TDABAudioDecoder.FeedMP2(const Data: TBytes);
var
  Ret, Enc: cint;
  Ch: cint;
  Rate: clong;
  Done: csize_t;
  Frames, i: Integer;
  F: array of Single;
begin
  mpg123_feed(FMpg, @Data[0], Length(Data));
  if Length(FPCM16) = 0 then SetLength(FPCM16, 1152 * 2 * 4);
  repeat
    Done := 0;
    Ret := mpg123_read(FMpg, @FPCM16[0], Length(FPCM16) * 2, @Done);
    if Ret = MPG123_NEW_FORMAT then begin
      mpg123_getformat(FMpg, @Rate, @Ch, @Enc);
      FMpgRate := Rate;
      FMpgChannels := Ch;
      if Ch = 2 then FFormatText := Format('MP2, %d kHz, stereo', [Rate div 1000])
      else FFormatText := Format('MP2, %d kHz, mono', [Rate div 1000]);
    end;
    if (Done > 0) and (FMpgChannels > 0) then begin
      Frames := Done div (2 * FMpgChannels);
      SetLength(F, Frames * FMpgChannels);
      for i := 0 to High(F) do F[i] := FPCM16[i] / 32768.0;
      Emit(@F[0], Frames, FMpgChannels, FMpgRate);
    end;
  until (Ret = MPG123_NEED_MORE) or (Ret = MPG123_ERR) or (Ret = MPG123_DONE) or
        ((Ret = MPG123_OK) and (Done = 0));
end;

{ ---- DAB+ ---- }

procedure TDABAudioDecoder.FeedDABPlus(const Data: TBytes);
var
  i: Integer;
begin
  if FFrameCount = 5 then begin
    // Window full and not accepted as a superframe: slide by one.
    for i := 0 to 3 do FFrames[i] := FFrames[i + 1];
    FFrameCount := 4;
    Inc(FSyncSlips);
  end;
  FFrames[FFrameCount] := Copy(Data);
  Inc(FFrameCount);
  if FFrameCount < 5 then Exit;
  if ProcessSuperframe then FFrameCount := 0;
end;

// Assembles the five queued frames, error-corrects, and decodes every AU.
// False if this window isn't a superframe (fire code fails before and
// after RS).
function TDABAudioDecoder.ProcessSuperframe: Boolean;
var
  s, i, j, k, n, Corr, Failed, NumAUs, Total: Integer;
  Cw: array[0..RS_N - 1] of Byte;
  Fixed: TBytes;
  Header: Byte;
  AUStart: array[0..6] of Integer;
  P: PByte;
  RawOk: Boolean;
begin
  Result := False;
  n := Length(FFrames[0]);
  s := n div 24;                 // bitrate/8: one RS codeword per 8 kbit/s
  if (s < 1) or (n mod 24 <> 0) then Exit;
  SetLength(FSF, 5 * n);
  for i := 0 to 4 do
    if Length(FFrames[i]) = n then Move(FFrames[i][0], FSF[i * n], n)
    else Exit;

  RawOk := FireCodeOk(@FSF[0]);

  // Reed-Solomon, codeword by codeword, into a copy - a window that turns
  // out not to be a superframe must not be left "corrected".
  Fixed := Copy(FSF);
  Corr := 0;
  Failed := 0;
  for j := 0 to s - 1 do begin
    FillChar(Cw, RS_SHORT, 0);
    for k := 0 to 119 do Cw[RS_SHORT + k] := Fixed[j + k * s];
    i := RSDecode(Cw);
    if i < 0 then Inc(Failed)
    else if i > 0 then begin
      Inc(Corr, i);
      for k := 0 to 119 do Fixed[j + k * s] := Cw[RS_SHORT + k];
    end;
  end;
  if not (RawOk or FireCodeOk(@Fixed[0])) then Exit;

  Result := True;
  Inc(FSuperframes);
  // Only counted for a window accepted as a superframe - codewords from
  // windows that turned out to be misaligned say nothing about reception.
  Inc(FRSCorrected, Corr);
  Inc(FRSFailed, Failed);
  P := @Fixed[0];

  Header := P[2];
  case (Header shr 5) and 3 of     // dac_rate, sbr_flag
    0: NumAUs := 4;   // 32 kHz AAC
    1: NumAUs := 2;   // 16 kHz core + SBR
    2: NumAUs := 6;   // 48 kHz AAC
  else NumAUs := 3;   // 24 kHz core + SBR
  end;
  case NumAUs of
    2: AUStart[0] := 5;
    3: AUStart[0] := 6;
    4: AUStart[0] := 8;
  else AUStart[0] := 11;
  end;
  // 12-bit start addresses for AUs 1.. from byte 3, packed two per 3 bytes.
  for i := 1 to NumAUs - 1 do begin
    k := 3 + ((i - 1) * 3) div 2;
    if Odd(i) then AUStart[i] := (P[k] shl 4) or (P[k + 1] shr 4)
    else AUStart[i] := ((P[k] and $0F) shl 8) or P[k + 1];
  end;
  Total := 110 * s;
  AUStart[NumAUs] := Total;

  SetupAAC(Header);
  for i := 0 to NumAUs - 1 do begin
    n := AUStart[i + 1] - AUStart[i];
    if (AUStart[i] < 0) or (n < 3) or (AUStart[i + 1] > Total) then begin
      Inc(FAUsBad);
      Continue;
    end;
    if DABCRC16(@P[AUStart[i]], n - 2) <> (Word(P[AUStart[i] + n - 2]) shl 8 or P[AUStart[i] + n - 1]) then begin
      Inc(FAUsBad);
      Continue;
    end;
    Inc(FAUsOk);
    DecodeAU(@P[AUStart[i]], n - 2);
  end;
end;

// (Re)initialises faad2 whenever the superframe header's format bits
// change - see the header comment, step 4, for the AudioSpecificConfig.
procedure TDABAudioDecoder.SetupAAC(Header: Byte);
var
  Dac, Sbr, Stereo, Ps: Boolean;
  CoreSRIndex, ChCfg: Integer;
  Asc: array[0..1] of Byte;
  Cfg: PNeAACDecConfiguration;
  Rate: culong;
  Ch: cuchar;
  Kind: string;
begin
  Header := Header and $7F;   // ignore rfa
  if (FAAC <> nil) and (Header = FAACHeader) then Exit;
  if FAAC <> nil then NeAACDecClose(FAAC);
  FAACHeader := Header;
  Dac := (Header and $40) <> 0;
  Sbr := (Header and $20) <> 0;
  Stereo := (Header and $10) <> 0;
  Ps := (Header and $08) <> 0;
  if Dac then begin
    if Sbr then CoreSRIndex := 6 else CoreSRIndex := 3;   // 24 / 48 kHz
  end else begin
    if Sbr then CoreSRIndex := 8 else CoreSRIndex := 5;   // 16 / 32 kHz
  end;
  if Stereo then ChCfg := 2 else ChCfg := 1;
  Asc[0] := (2 shl 3) or (CoreSRIndex shr 1);                       // AOT 2, AAC-LC
  Asc[1] := ((CoreSRIndex and 1) shl 7) or (ChCfg shl 3) or 4;       // 960-sample frames

  FAAC := NeAACDecOpen();
  Cfg := NeAACDecGetCurrentConfiguration(FAAC);
  Cfg^.outputFormat := FAAD_FMT_FLOAT;
  Cfg^.dontUpSampleImplicitSBR := 0;
  NeAACDecSetConfiguration(FAAC, Cfg);
  if NeAACDecInit2(FAAC, @Asc[0], 2, @Rate, @Ch) < 0 then begin
    FLastError := 'faad2 rejected the DAB+ AudioSpecificConfig';
    NeAACDecClose(FAAC);
    FAAC := nil;
    Exit;
  end;
  if Sbr and Ps then Kind := 'HE-AAC v2'
  else if Sbr then Kind := 'HE-AAC'
  else Kind := 'AAC-LC';
  if Stereo or Ps then FFormatText := Format('%s, %d kHz, stereo', [Kind, IfThen(Dac, 48, 32)])
  else FFormatText := Format('%s, %d kHz, mono', [Kind, IfThen(Dac, 48, 32)]);
end;

procedure TDABAudioDecoder.DecodeAU(P: PByte; Len: Integer);
var
  Info: TNeAACDecFrameInfo;
  Out_: PSingle;
begin
  if FAAC = nil then Exit;
  FillChar(Info, SizeOf(Info), 0);
  Out_ := NeAACDecDecode(FAAC, @Info, P, Len);
  if (Info.error <> 0) or (Out_ = nil) or (Info.channels = 0) or (Info.samples = 0) then Exit;
  Emit(Out_, Info.samples div Info.channels, Info.channels, Info.samplerate);
end;

initialization
  BuildGF;
end.
