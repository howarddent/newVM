unit uHackRF;

{*******************************************************************************

     Runtime (dlopen-based) binding to libhackrf, plus THackRFDevice - a
     thin wrapper that turns its background-thread RX callback into
     epochs of complex IQ (TVMobjZ) a GUI timer can pull from safely.

     WHY DLOPEN INSTEAD OF LINK-TIME EXTERNAL:
     Same rationale as fftw3.pas - on this development machine
     libhackrf0 is installed as a plain runtime package (libhackrf.so.0),
     with no libhackrf-dev, so there is neither a hackrf.h nor an
     unversioned libhackrf.so symlink for a link-time "external
     'hackrf';" declaration to resolve against. This unit instead
     LoadLibrary/GetProcedureAddress's the exact versioned .so name,
     resolved once in this unit's own initialization section, tolerant
     of the library being entirely absent (HackRFLibLoaded stays False;
     THackRFDevice.Open then fails cleanly with a descriptive
     LastError rather than crashing).

     The hackrf_transfer record layout, the callback ABI, and every
     bound function signature below were confirmed against the real,
     linked libhackrf.so.0 on this machine with a standalone throwaway
     probe program (opened the device, streamed live IQ for 1.5s,
     printed total bytes received) BEFORE being wired in here - same
     "verify the FFI assumption against the real library first"
     discipline the main newVM units use for their own by-value complex
     struct IPP bindings (see CLAUDE.md's OneAPI.pas section). The probe
     measured ~39.8MB/s at a requested 20Msps (20e6*2 bytes/sample =
     40MB/s expected), confirming both the struct layout and the
     interleaved-signed-int8-I/Q sample format.

     THREADING:
     hackrf_start_rx's callback runs on libhackrf's own libusb thread,
     not the GUI thread - it must return quickly and must never touch
     LCL/OpenGL state directly. OnRawData (invoked from that thread via
     the module-level cdecl HackRFRxCallback) only locks a
     TCriticalSection and copies raw bytes into a fixed-size ring
     buffer; TryReadEpoch (called from the GUI thread's own TTimer) is
     the only other thing that touches the ring, under the same lock.
     A full ring is simply overwritten (oldest unread bytes lost)
     rather than ever blocking the USB thread - a live spectrum display
     only ever wants the most recent data anyway. TryReadEpoch goes
     further: if more than one whole epoch is backlogged, it skips
     forward to the newest one rather than draining oldest-first, so
     the on-screen spectrum stays live instead of lagging behind
     real time as the GUI timer's ~30Hz cadence falls behind the
     ~2400 epochs/second a full 20Msps stream of 8192-sample epochs
     would otherwise produce.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, DynLibs, newVMComplex;

const
  {$IFDEF WINDOWS}
  HackRFLib = 'hackrf.dll';   // by convention, matching this repo's other
                               // runtime-bound libraries - not tested on
                               // Windows, no HackRF hardware available there
  {$ELSE}
  HackRFLib = 'libhackrf.so.0';
  {$ENDIF}

  // Ring buffer capacity - comfortably more than one GUI timer tick's
  // worth of data even at the full 20Msps (40MB/s -> ~26ms per MB), so a
  // brief GUI stall doesn't immediately start dropping the newest data.
  HackRFRingBytes = 4 * 1024 * 1024;

type
  Phackrf_device = Pointer;

  // Mirrors libhackrf's own hackrf_transfer struct exactly (confirmed via
  // the standalone probe - see this unit's header comment).
  hackrf_transfer = record
    device: Phackrf_device;
    buffer: PByte;
    buffer_length: Integer;
    valid_length: Integer;
    rx_ctx: Pointer;
    tx_ctx: Pointer;
  end;
  Phackrf_transfer = ^hackrf_transfer;

  Thackrf_sample_block_cb_fn = function(transfer: Phackrf_transfer): Integer; cdecl;

  Thackrf_init = function(): Integer; cdecl;
  Thackrf_exit = function(): Integer; cdecl;
  Thackrf_open = function(var device: Phackrf_device): Integer; cdecl;
  Thackrf_close = function(device: Phackrf_device): Integer; cdecl;
  Thackrf_start_rx = function(device: Phackrf_device; callback: Thackrf_sample_block_cb_fn; rx_ctx: Pointer): Integer; cdecl;
  Thackrf_stop_rx = function(device: Phackrf_device): Integer; cdecl;
  Thackrf_is_streaming = function(device: Phackrf_device): Integer; cdecl;
  Thackrf_set_freq = function(device: Phackrf_device; freq_hz: QWord): Integer; cdecl;
  Thackrf_set_sample_rate = function(device: Phackrf_device; freq_hz: Double): Integer; cdecl;
  Thackrf_set_lna_gain = function(device: Phackrf_device; value: LongWord): Integer; cdecl;
  Thackrf_set_vga_gain = function(device: Phackrf_device; value: LongWord): Integer; cdecl;
  Thackrf_set_amp_enable = function(device: Phackrf_device; value: Byte): Integer; cdecl;
  Thackrf_set_baseband_filter_bandwidth = function(device: Phackrf_device; bandwidth_hz: LongWord): Integer; cdecl;
  Thackrf_compute_baseband_filter_bw_round_down_lt = function(sample_rate_hz: LongWord): LongWord; cdecl;
  Thackrf_error_name = function(errcode: Integer): PAnsiChar; cdecl;

var
  hackrf_init: Thackrf_init;
  hackrf_exit: Thackrf_exit;
  hackrf_open: Thackrf_open;
  hackrf_close: Thackrf_close;
  hackrf_start_rx: Thackrf_start_rx;
  hackrf_stop_rx: Thackrf_stop_rx;
  hackrf_is_streaming: Thackrf_is_streaming;
  hackrf_set_freq: Thackrf_set_freq;
  hackrf_set_sample_rate: Thackrf_set_sample_rate;
  hackrf_set_lna_gain: Thackrf_set_lna_gain;
  hackrf_set_vga_gain: Thackrf_set_vga_gain;
  hackrf_set_amp_enable: Thackrf_set_amp_enable;
  hackrf_set_baseband_filter_bandwidth: Thackrf_set_baseband_filter_bandwidth;
  hackrf_compute_baseband_filter_bw_round_down_lt: Thackrf_compute_baseband_filter_bw_round_down_lt;
  hackrf_error_name: Thackrf_error_name;

  HackRFLibLoaded: Boolean = False;

type
  { THackRFDevice }
  THackRFDevice = class
  private
    FDevice: Phackrf_device;
    FOpen: Boolean;
    FStreaming: Boolean;
    FCenterFreqHz: QWord;
    FSampleRateHz: Double;
    FLastError: string;

    FRing: array of Byte;
    FWriteIdx, FReadIdx: Integer;
    FFill: Integer;   // bytes currently held, 0..HackRFRingBytes
    FLock: TCriticalSection;

    function CallFailed(RC: Integer; const Routine: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function Open: Boolean;
    procedure Close;

    function SetFrequencyHz(Hz: QWord): Boolean;
    function SetSampleRateHz(Hz: Double): Boolean;
    function SetLNAGain(dB: LongWord): Boolean;
    function SetVGAGain(dB: LongWord): Boolean;
    function SetAmpEnable(Enable: Boolean): Boolean;

    function StartRX: Boolean;
    function StopRX: Boolean;

    // Called only from HackRFRxCallback, on libhackrf's own USB thread.
    procedure OnRawData(Buf: PByte; Len: Integer);

    // Called only from the GUI thread. Returns True and fills IQ (a
    // fresh (1,N) TVMobjZ, normalised to [-1,1) per component) iff a
    // full N-sample epoch was available.
    function TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean;

    property IsOpen: Boolean read FOpen;
    property IsStreaming: Boolean read FStreaming;
    property CenterFreqHz: QWord read FCenterFreqHz;
    property SampleRateHz: Double read FSampleRateHz;
    property LastError: string read FLastError;
  end;

implementation

var
  HackRFHandle: TLibHandle = NilHandle;
  HackRFInited: Boolean = False;

function Load(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(HackRFHandle, Name);
end;

procedure LoadHackRFAddresses;
begin
  Pointer(hackrf_init)                                   := Load('hackrf_init');
  Pointer(hackrf_exit)                                   := Load('hackrf_exit');
  Pointer(hackrf_open)                                   := Load('hackrf_open');
  Pointer(hackrf_close)                                  := Load('hackrf_close');
  Pointer(hackrf_start_rx)                                := Load('hackrf_start_rx');
  Pointer(hackrf_stop_rx)                                 := Load('hackrf_stop_rx');
  Pointer(hackrf_is_streaming)                            := Load('hackrf_is_streaming');
  Pointer(hackrf_set_freq)                                := Load('hackrf_set_freq');
  Pointer(hackrf_set_sample_rate)                         := Load('hackrf_set_sample_rate');
  Pointer(hackrf_set_lna_gain)                            := Load('hackrf_set_lna_gain');
  Pointer(hackrf_set_vga_gain)                            := Load('hackrf_set_vga_gain');
  Pointer(hackrf_set_amp_enable)                          := Load('hackrf_set_amp_enable');
  Pointer(hackrf_set_baseband_filter_bandwidth)           := Load('hackrf_set_baseband_filter_bandwidth');
  Pointer(hackrf_compute_baseband_filter_bw_round_down_lt) := Load('hackrf_compute_baseband_filter_bw_round_down_lt');
  Pointer(hackrf_error_name)                              := Load('hackrf_error_name');
end;

function InitializeHackRFLib: Boolean;
begin
  if HackRFHandle = NilHandle then begin
    HackRFHandle := LoadLibrary(HackRFLib);
    if HackRFHandle <> NilHandle then LoadHackRFAddresses;
  end;
  Result := HackRFHandle <> NilHandle;
end;

// Module-level cdecl callback libhackrf's USB thread calls directly -
// rx_ctx (set from hackrf_start_rx's third argument, see StartRX) is the
// THackRFDevice instance that started this stream, cast back from the
// void* libhackrf hands it straight through unchanged.
function HackRFRxCallback(transfer: Phackrf_transfer): Integer; cdecl;
var
  Dev: THackRFDevice;
begin
  Dev := THackRFDevice(transfer^.rx_ctx);
  if Assigned(Dev) then
    Dev.OnRawData(transfer^.buffer, transfer^.valid_length);
  Result := 0;
end;

{ THackRFDevice }

constructor THackRFDevice.Create;
begin
  inherited Create;
  SetLength(FRing, HackRFRingBytes);
  FWriteIdx := 0;
  FReadIdx := 0;
  FFill := 0;
  FLock := TCriticalSection.Create;
  FCenterFreqHz := 95000000;
  FSampleRateHz := 20000000.0;
end;

destructor THackRFDevice.Destroy;
begin
  if FStreaming then StopRX;
  if FOpen then Close;
  FLock.Free;
  inherited Destroy;
end;

function THackRFDevice.CallFailed(RC: Integer; const Routine: string): Boolean;
begin
  Result := RC <> 0;
  if Result then begin
    if Assigned(hackrf_error_name) then
      FLastError := Routine + ' failed: ' + hackrf_error_name(RC)
    else
      FLastError := Routine + ' failed with code ' + IntToStr(RC);
  end;
end;

function THackRFDevice.Open: Boolean;
var
  RC: Integer;
begin
  Result := False;
  if FOpen then begin Result := True; Exit; end;

  if not HackRFLibLoaded then begin
    FLastError := 'libhackrf runtime library (' + HackRFLib + ') not found';
    Exit;
  end;

  if not HackRFInited then begin
    RC := hackrf_init();
    if CallFailed(RC, 'hackrf_init') then Exit;
    HackRFInited := True;
  end;

  FDevice := nil;
  RC := hackrf_open(FDevice);
  if CallFailed(RC, 'hackrf_open') then Exit;

  FOpen := True;
  Result := True;
end;

procedure THackRFDevice.Close;
begin
  if FStreaming then StopRX;
  if FOpen then begin
    hackrf_close(FDevice);
    FDevice := nil;
    FOpen := False;
  end;
end;

function THackRFDevice.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(hackrf_set_freq(FDevice, Hz), 'hackrf_set_freq') then Exit;
  FCenterFreqHz := Hz;
  Result := True;
end;

function THackRFDevice.SetSampleRateHz(Hz: Double): Boolean;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(hackrf_set_sample_rate(FDevice, Hz), 'hackrf_set_sample_rate') then Exit;
  FSampleRateHz := Hz;
  Result := True;
end;

function THackRFDevice.SetLNAGain(dB: LongWord): Boolean;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  Result := not CallFailed(hackrf_set_lna_gain(FDevice, dB), 'hackrf_set_lna_gain');
end;

function THackRFDevice.SetVGAGain(dB: LongWord): Boolean;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  Result := not CallFailed(hackrf_set_vga_gain(FDevice, dB), 'hackrf_set_vga_gain');
end;

function THackRFDevice.SetAmpEnable(Enable: Boolean): Boolean;
var
  V: Byte;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  if Enable then V := 1 else V := 0;
  Result := not CallFailed(hackrf_set_amp_enable(FDevice, V), 'hackrf_set_amp_enable');
end;

// Sets the baseband filter to the widest bandwidth not exceeding the
// current sample rate (hackrf_compute_baseband_filter_bw_round_down_lt),
// the same pairing libhackrf's own reference hackrf_transfer tool uses,
// then starts RX with HackRFRxCallback, passing Self as rx_ctx so the
// callback can find its way back to this instance's ring buffer.
function THackRFDevice.StartRX: Boolean;
var
  BW: LongWord;
begin
  Result := False;
  if not FOpen then begin FLastError := 'device not open'; Exit; end;
  if FStreaming then begin Result := True; Exit; end;

  FWriteIdx := 0; FReadIdx := 0; FFill := 0;

  BW := hackrf_compute_baseband_filter_bw_round_down_lt(Round(FSampleRateHz));
  if CallFailed(hackrf_set_baseband_filter_bandwidth(FDevice, BW), 'hackrf_set_baseband_filter_bandwidth') then Exit;

  if CallFailed(hackrf_start_rx(FDevice, @HackRFRxCallback, Pointer(Self)), 'hackrf_start_rx') then Exit;

  FStreaming := True;
  Result := True;
end;

function THackRFDevice.StopRX: Boolean;
begin
  Result := True;
  if not FStreaming then Exit;
  Result := not CallFailed(hackrf_stop_rx(FDevice), 'hackrf_stop_rx');
  FStreaming := False;
end;

procedure THackRFDevice.OnRawData(Buf: PByte; Len: Integer);
var
  Overflow, FirstPart, RingLen: Integer;
begin
  RingLen := Length(FRing);
  FLock.Enter;
  try
    if Len >= RingLen then begin
      // More data arrived in one callback than the whole ring holds -
      // keep only its most recent RingLen bytes.
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
      // than blocking this USB thread.
      Overflow := FFill - RingLen;
      FReadIdx := (FReadIdx + Overflow) mod RingLen;
      FFill := RingLen;
    end;
  finally
    FLock.Leave;
  end;
end;

function THackRFDevice.TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean;
const
  s = 'THackRFDevice.TryReadEpoch : ';
var
  NeedBytes, Epochs, SkipBytes, RingLen, Tail, i: Integer;
  Tmp: array of Byte;
  Re, Im, SumRe, SumIm, MeanRe, MeanIm: Double;
  Iv, Qv, Pii, Piq, Pqq, g, k: Double;
begin
  assert(N > 0, s + 'N must be positive');
  NeedBytes := N * 2;   // 2 bytes (I,Q) per complex sample
  Result := False;
  RingLen := Length(FRing);

  FLock.Enter;
  try
    if FFill < NeedBytes then Exit;

    // Skip forward to the newest full epoch if more than one is
    // backlogged, so the display tracks real time instead of lagging.
    Epochs := FFill div NeedBytes;
    if Epochs > 1 then begin
      SkipBytes := (Epochs - 1) * NeedBytes;
      FReadIdx := (FReadIdx + SkipBytes) mod RingLen;
      FFill := FFill - SkipBytes;
    end;

    SetLength(Tmp, NeedBytes);
    if FReadIdx + NeedBytes <= RingLen then
      Move(FRing[FReadIdx], Tmp[0], NeedBytes)
    else begin
      Tail := RingLen - FReadIdx;
      Move(FRing[FReadIdx], Tmp[0], Tail);
      Move(FRing[0], Tmp[Tail], NeedBytes - Tail);
    end;
    FReadIdx := (FReadIdx + NeedBytes) mod RingLen;
    FFill := FFill - NeedBytes;
  finally
    FLock.Leave;
  end;

  // Interleaved signed 8-bit I/Q, confirmed by the standalone probe -
  // see this unit's header comment. Normalised to roughly [-1,1), and
  // accumulated here (SumRe/SumIm) so the DC-removal pass below can
  // reuse this same loop's work rather than summing over IQ again.
  IQ := TVMobjZ.Create(1, N);
  SumRe := 0; SumIm := 0;
  for i := 0 to N - 1 do begin
    Re := ShortInt(Tmp[i * 2]) / 128.0;
    Im := ShortInt(Tmp[i * 2 + 1]) / 128.0;
    IQ[0, i] := Cplx(Re, Im);
    SumRe := SumRe + Re;
    SumIm := SumIm + Im;
  end;

  // Remove DC offset: HackRF is a direct-conversion (zero-IF) receiver,
  // so any LO leakage/ADC bias shows up as a constant offset in the raw
  // IQ stream - which an FFT concentrates entirely into the bin at 0Hz
  // baseband, i.e. exactly the tuned centre frequency once the display
  // shifts the spectrum into ascending-frequency order. That reads as a
  // large, permanent "signal" sitting on the LO frequency regardless of
  // what's actually being received. Subtracting each epoch's own mean
  // I/Q before windowing/FFT removes it with no calibration step, and
  // naturally tracks any drift in the offset itself (temperature, gain
  // changes) since it's recomputed fresh every epoch.
  // Also accumulates Pii/Piq (sum of I*I and I*Q over the now DC-free
  // samples) in the same pass, for the IQ-imbalance correction below -
  // no need for a separate summing loop over IQ.
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
  // Q channels aren't perfectly matched in amplitude and phase (HackRF's
  // MAX2837 front-end included) mirrors every real signal about the
  // tuned centre frequency - unlike the DC spike above, this "image"
  // moves together with whatever real signal produced it rather than
  // sitting at a fixed offset, which is how it was distinguished from a
  // fixed internal spur here. Standard blind (no calibration signal
  // needed) two-step fix, from Lyons' "Understanding Digital Signal
  // Processing": first, Gram-Schmidt orthogonalise Q against I (removes
  // the phase-imbalance component correlated with I - g is the
  // projection of Q onto I, in units of I's own power); then rescale the
  // orthogonalised Q back up to I's power (removes the amplitude
  // imbalance). Recomputed fresh every epoch, same as the DC removal
  // above, so it tracks any imbalance drift automatically. Guarded
  // against near-silent epochs (Pii/Pqq ~ 0) where the estimate would be
  // meaningless - those epochs pass through uncorrected rather than
  // risking a division blowing the correction up.
  //
  // CONFIRMED LIMITATION: at a 94.4MHz test tone (95MHz centre, 20Msps),
  // this correction did NOT remove a same-amplitude image observed
  // ~5.6MHz away, which tracks the real signal under retuning rather
  // than sitting at a fixed offset from the centre frequency (ruling out
  // both a zero-IF I/Q mirror - this correction targets exactly that,
  // and had no effect - and a fixed internal Fs/4-type digital spur).
  // Since this whole function only ever sees the already-digitised I/Q
  // stream, an image that survives correct I/Q balance must be entering
  // upstream of the ADC entirely - i.e. in HackRF's analog front-end.
  // 95MHz is well below the MAX2837 transceiver's native ~2.3-2.7GHz
  // band, so HackRF routes it through an internal upconversion mixer
  // (the RFFC5071) first; that mixer's own imperfect image rejection is
  // the most likely source, and by the time such an image reaches the
  // ADC it is physically indistinguishable from a real received signal -
  // no digital post-processing here can remove it. Left as a known,
  // accepted HackRF VHF hardware limitation rather than chased further.
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

  Result := True;
end;

initialization
  HackRFLibLoaded := InitializeHackRFLib;

finalization
  if HackRFInited and Assigned(hackrf_exit) then hackrf_exit();
  if HackRFHandle <> NilHandle then UnloadLibrary(HackRFHandle);

end.
