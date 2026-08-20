unit uSDRDevice;

{*******************************************************************************

     Device-agnostic pieces shared by every concrete SDR backend
     (uHackRF.pas's THackRFDevice, uRTLSDR.pas's TRTLSDRDevice):

     - TSDRDevice, the abstract base class uSDRMain.pas actually talks
       to. Autodetection (trying each concrete device type in turn - see
       uSDRMain.pas's DetectAndOpenDevice) and the capability-driven UI
       (ApplyDeviceCapabilities) are both only possible because every
       backend presents the same interface here, regardless of how
       different the underlying hardware/library actually is.
     - TSDRCapabilities/TSDRGainStage, the device-agnostic description of
       what a connected device can do - populated once per device (see
       each concrete unit's own Capabilities setup) and read by
       uSDRMain.pas to decide what the control panel should look like.
       A gain stage's Value is always a real physical unit (dB, or 0/1
       for a boolean stage) in every case - turning a UI control's raw
       position into that value is the FORM's job (using a stage's own
       Kind/Min/Max/Step/DiscreteValues), not the device's.
       TSDRBoolOption/BoolOptions/SetBoolOption is the same idea for a
       simple on/off feature that isn't part of the gain chain (e.g.
       bias-T antenna power) - kept as its own list rather than a fourth
       gkBoolean gain stage, since it isn't one.
     - TSDRRingBuffer, the fixed-size byte ring with skip-to-newest-epoch
       behaviour originally written for THackRFDevice, now shared since
       both backends need the exact same "USB thread writes, GUI thread
       reads the newest epoch" pattern - only the raw byte -> complex
       sample conversion differs (HackRF: signed int8 pairs; RTL-SDR:
       unsigned uint8 pairs), which stays in each device's own
       TryReadEpoch.
     - CorrectIQEpoch, the DC-offset removal + Gram-Schmidt I/Q balance
       correction originally written for HackRF - moved here because it
       applies equally to RTL-SDR's R820T tuner, which is also a zero-IF
       design (see the routine's own comment for the full rationale).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, newVMComplex;

type
  TSDRByteArray = array of Byte;

  TSDRGainStageKind = (gkContinuous, gkDiscreteList, gkBoolean);

  // One tunable gain control, in device-agnostic terms - see this unit's
  // own header comment for the "Value is always a real physical unit"
  // convention every SetGain call follows regardless of Kind. That unit is
  // usually dB (every gkContinuous/gkDiscreteList stage HackRF/RTL-SDR
  // expose is), but isn't universally - SDRplay's RSP1A "LNA State" is a
  // gkDiscreteList of raw 0-9 state indices, not a dB value (the actual
  // attenuation per step varies by band and isn't a single published
  // table) - so the display suffix is a per-stage property rather than a
  // hardcoded assumption; see uSDRMain.pas's two label-formatting call
  // sites. Defaults to 'dB' (SetLength-zeroing a string gives '', so every
  // existing backend explicitly sets this rather than relying on a silent
  // default) purely as documentation of the existing convention, not a
  // magic empty-string special case.
  TSDRGainStage = record
    Name: string;
    Kind: TSDRGainStageKind;
    Min, Max, Step: Double;          // gkContinuous only
    DiscreteValues: array of Double; // gkDiscreteList only (real units, per UnitSuffix)
    UnitSuffix: string;              // e.g. 'dB', or '' for a unitless index like LNA State
  end;

  // A simple on/off device feature that isn't part of the receiver's
  // gain chain - e.g. bias-T antenna DC power - so it's kept separate
  // from GainStages/SetGain (which are specifically about amplification
  // stages) rather than folded into a fourth "gkBoolean" gain stage.
  TSDRBoolOption = record
    Name: string;
  end;

  TSDRCapabilities = record
    DeviceName: string;
    MinFreqHz, MaxFreqHz: Double;
    SampleRates: array of Double;    // Hz, ascending - offered in the UI as-is
    DefaultSampleRateHz: Double;
    DefaultFreqHz: QWord;
    GainStages: array of TSDRGainStage;
    BoolOptions: array of TSDRBoolOption;
  end;

  { TSDRDevice }
  TSDRDevice = class abstract
  protected
    FIsOpen: Boolean;
    FStreaming: Boolean;
    FCenterFreqHz: QWord;
    FSampleRateHz: Double;
    FLastError: string;
    FCapabilities: TSDRCapabilities;
  public
    function Open: Boolean; virtual; abstract;
    procedure Close; virtual; abstract;

    function SetFrequencyHz(Hz: QWord): Boolean; virtual; abstract;
    function SetSampleRateHz(Hz: Double): Boolean; virtual; abstract;
    // StageIndex indexes Capabilities.GainStages; Value is always a real
    // physical unit - dB for gkContinuous/gkDiscreteList, 0/1 for
    // gkBoolean (see this unit's own header comment).
    function SetGain(StageIndex: Integer; Value: Double): Boolean; virtual; abstract;
    // OptionIndex indexes Capabilities.BoolOptions.
    function SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean; virtual; abstract;

    function StartRX: Boolean; virtual; abstract;
    function StopRX: Boolean; virtual; abstract;

    // Called only from the GUI thread. Returns True and fills IQ (a
    // fresh (1,N) TVMobjZ) iff a full N-sample epoch was available.
    function TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean; virtual; abstract;

    property IsOpen: Boolean read FIsOpen;
    property IsStreaming: Boolean read FStreaming;
    property CenterFreqHz: QWord read FCenterFreqHz;
    property SampleRateHz: Double read FSampleRateHz;
    property LastError: string read FLastError;
    property Capabilities: TSDRCapabilities read FCapabilities;
  end;

  // Fixed-size byte ring buffer, one producer (a hardware read
  // thread/callback) and one consumer. Write silently overwrites the
  // oldest unwritten bytes when full, rather than ever blocking the
  // producer - see uHackRF.pas's original header comment (the behaviour
  // this class was extracted from, unchanged) for the full rationale.
  //
  // TryReadNewest reads a plain, lossless FIFO sequence - the oldest
  // NeedBytes not yet read, in order, nothing skipped or discarded (the
  // name is now a historical misnomer - see below). It used to
  // deliberately SKIP FORWARD to the newest full epoch whenever more
  // than one was backlogged, discarding the rest, which was the right
  // behaviour for its original sole caller (a live spectrum display
  // that only ever wanted the newest snapshot and was happy to drop
  // stale frames). That stopped being safe once TSDRRFSource
  // (uSDRRFSource.pas) became this buffer's ONLY reader - it now has to
  // deliver every sample losslessly to its own internal stream, which
  // is what actually feeds one or more independent downstream consumers
  // (each with their own "catch up" logic, per-consumer, at that
  // higher level - see TSDRRFSource.TryReadEpoch's own comment).
  // Skipping data here would silently corrupt that stream instead:
  // confirmed the hard way - real-time FM demodulation went from
  // "occasional pops and clicks, largely silent" to correct once this
  // method stopped discarding backlogged epochs. The one remaining
  // consumer of this class-level discard behaviour was TSDRRFSource's
  // OWN poll timer being too coarse to keep up sample-for-sample - fixed
  // there (PollTick now drains everything currently available in a
  // loop, rather than assuming one fixed-size read per timer tick) so
  // this buffer's producer side never has to fall back on its own
  // overwrite-when-full behaviour in normal operation either.
  { TSDRRingBuffer }
  TSDRRingBuffer = class
  private
    FRing: TSDRByteArray;
    FWriteIdx, FReadIdx, FFill: Integer;
    FLock: TCriticalSection;
  public
    constructor Create(SizeBytes: Integer);
    destructor Destroy; override;
    procedure Reset;
    // Called from the producer thread only.
    procedure Write(Buf: PByte; Len: Integer);
    // Called from the (single) consumer only.
    function TryReadNewest(NeedBytes: Integer; out Buf: TSDRByteArray): Boolean;
  end;

// DC-offset removal + I/Q gain/phase balance correction for one epoch's
// worth of complex samples from any zero-IF/direct-conversion receiver
// (HackRF's MAX2837, RTL-SDR's R820T both qualify). See the inline
// comments below for the two techniques; both are blind (no calibration
// signal needed) and recomputed fresh per call, so they track drift
// automatically. Mutates IQ in place.
procedure CorrectIQEpoch(var IQ: TVMobjZ);

implementation

{ TSDRRingBuffer }

constructor TSDRRingBuffer.Create(SizeBytes: Integer);
begin
  inherited Create;
  SetLength(FRing, SizeBytes);
  FWriteIdx := 0;
  FReadIdx := 0;
  FFill := 0;
  FLock := TCriticalSection.Create;
end;

destructor TSDRRingBuffer.Destroy;
begin
  FLock.Free;
  inherited Destroy;
end;

procedure TSDRRingBuffer.Reset;
begin
  FLock.Enter;
  try
    FWriteIdx := 0;
    FReadIdx := 0;
    FFill := 0;
  finally
    FLock.Leave;
  end;
end;

procedure TSDRRingBuffer.Write(Buf: PByte; Len: Integer);
var
  Overflow, FirstPart, RingLen: Integer;
begin
  RingLen := Length(FRing);
  FLock.Enter;
  try
    if Len >= RingLen then begin
      // More data arrived in one call than the whole ring holds - keep
      // only its most recent RingLen bytes.
      Move((Buf + (Len - RingLen))^, FRing[0], RingLen);
      FWriteIdx := 0;
      FReadIdx := 0;
      FFill := RingLen;
      Exit;
    end;

    FirstPart := RingLen - FWriteIdx;
    if FirstPart > Len then FirstPart := Len;
    Move(Buf^, FRing[FWriteIdx], FirstPart);
    if Len > FirstPart then
      Move((Buf + FirstPart)^, FRing[0], Len - FirstPart);
    FWriteIdx := (FWriteIdx + Len) mod RingLen;

    FFill := FFill + Len;
    if FFill > RingLen then begin
      // Ring is full - drop the oldest (Overflow) unread bytes rather
      // than blocking the producer.
      Overflow := FFill - RingLen;
      FReadIdx := (FReadIdx + Overflow) mod RingLen;
      FFill := RingLen;
    end;
  finally
    FLock.Leave;
  end;
end;

function TSDRRingBuffer.TryReadNewest(NeedBytes: Integer; out Buf: TSDRByteArray): Boolean;
var
  RingLen, Tail: Integer;
begin
  Result := False;
  RingLen := Length(FRing);

  FLock.Enter;
  try
    if FFill < NeedBytes then Exit;

    SetLength(Buf, NeedBytes);
    if FReadIdx + NeedBytes <= RingLen then
      Move(FRing[FReadIdx], Buf[0], NeedBytes)
    else begin
      Tail := RingLen - FReadIdx;
      Move(FRing[FReadIdx], Buf[0], Tail);
      Move(FRing[0], Buf[Tail], NeedBytes - Tail);
    end;
    FReadIdx := (FReadIdx + NeedBytes) mod RingLen;
    FFill := FFill - NeedBytes;
  finally
    FLock.Leave;
  end;

  Result := True;
end;

procedure CorrectIQEpoch(var IQ: TVMobjZ);
var
  N, i: Integer;
  SumRe, SumIm, MeanRe, MeanIm: Double;
  Iv, Qv, Pii, Piq, Pqq, g, k: Double;
begin
  N := IQ.Cols;

  // Remove DC offset: a zero-IF receiver's LO leakage/ADC bias shows up
  // as a constant offset in the raw IQ stream - which an FFT
  // concentrates entirely into the bin at 0Hz baseband, i.e. exactly the
  // tuned centre frequency once the display shifts the spectrum into
  // ascending-frequency order. That reads as a large, permanent "signal"
  // sitting on the LO frequency regardless of what's actually being
  // received. Subtracting each epoch's own mean I/Q before windowing/FFT
  // removes it with no calibration step, and naturally tracks any drift
  // in the offset itself (temperature, gain changes) since it's
  // recomputed fresh every epoch. Also accumulates Pii/Piq (sum of I*I
  // and I*Q over the now DC-free samples) in the same pass, for the
  // I/Q-imbalance correction below - no need for a separate summing loop.
  SumRe := 0; SumIm := 0;
  for i := 0 to N - 1 do begin
    SumRe := SumRe + IQ[0, i].re;
    SumIm := SumIm + IQ[0, i].im;
  end;
  MeanRe := SumRe / N;
  MeanIm := SumIm / N;

  Pii := 0; Piq := 0;
  for i := 0 to N - 1 do begin
    Iv := IQ[0, i].re - MeanRe;
    Qv := IQ[0, i].im - MeanIm;
    IQ[0, i] := Cplx(Iv, Qv);
    Pii := Pii + Iv * Iv;
    Piq := Piq + Iv * Qv;
  end;

  // Correct I/Q gain and phase imbalance: a zero-IF receiver whose I and
  // Q channels aren't perfectly matched in amplitude and phase mirrors
  // every real signal about the tuned centre frequency - unlike the DC
  // spike above, this "image" moves together with whatever real signal
  // produced it rather than sitting at a fixed offset. Standard blind
  // two-step fix, from Lyons' "Understanding Digital Signal Processing":
  // first, Gram-Schmidt orthogonalise Q against I (removes the
  // phase-imbalance component correlated with I - g is the projection of
  // Q onto I, in units of I's own power); then rescale the
  // orthogonalised Q back up to I's power (removes the amplitude
  // imbalance). Guarded against near-silent epochs (Pii/Pqq ~ 0) where
  // the estimate would be meaningless - those epochs pass through
  // uncorrected rather than risking a division blowing the correction up.
  if Pii > 1e-9 then begin
    g := Piq / Pii;
    Pqq := 0;
    for i := 0 to N - 1 do begin
      Iv := IQ[0, i].re;
      Qv := IQ[0, i].im - g * Iv;
      IQ[0, i] := Cplx(Iv, Qv);
      Pqq := Pqq + Qv * Qv;
    end;
    if Pqq > 1e-9 then begin
      k := Sqrt(Pii / Pqq);
      for i := 0 to N - 1 do
        IQ[0, i] := Cplx(IQ[0, i].re, IQ[0, i].im * k);
    end;
  end;
end;

end.
