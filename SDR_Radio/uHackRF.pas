unit uHackRF;

{*******************************************************************************

     Runtime (dlopen-based) binding to libhackrf, plus THackRFDevice - a
     TSDRDevice (uSDRDevice.pas) implementation that turns HackRF's
     background-thread RX callback into epochs of complex IQ (TVMobjZ) a
     GUI timer can pull from safely.

     WHY DLOPEN INSTEAD OF LINK-TIME EXTERNAL:
     Same rationale as fftw3.pas - on the original Linux development
     machine libhackrf0 is installed as a plain runtime package
     (libhackrf.so.0), with no libhackrf-dev, so there is neither a
     hackrf.h nor an unversioned libhackrf.so symlink for a link-time
     "external 'hackrf';" declaration to resolve against. This unit
     instead LoadLibrary/GetProcedureAddress's the library, tried against
     a per-platform candidate name list (HackRFLibCandidates) rather than
     one fixed name, resolved once in this unit's own initialization
     section, tolerant of the library being entirely absent (HackRFLibLoaded
     stays False; THackRFDevice.Open then fails cleanly with a descriptive
     LastError rather than crashing).

     macOS: confirmed via a standalone probe against a real HackRF One,
     after installing MacPorts' hackrf port (`sudo port install hackrf`) -
     that port puts libhackrf.dylib/.0.dylib under /opt/local/lib, which is
     NOT on dyld's default search path (a bare 'libhackrf.dylib'
     LoadLibrary call fails even with the file right there), so
     HackRFLibCandidates includes that full path explicitly - same "bare
     name first, then a known absolute location" pattern uSDRplay.pas/
     OpenCLAPI.pas already use for their own non-standard-location
     libraries. Homebrew's own default prefixes are included too as a
     reasonable fallback, though not verified on this machine (MacPorts,
     not Homebrew, is what's actually installed here).

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
     the module-level cdecl HackRFRxCallback) only writes into a
     TSDRRingBuffer (uSDRDevice.pas - lock-protected internally);
     TryReadEpoch (called from the GUI thread's own TTimer) is the only
     other thing that touches it. See TSDRRingBuffer's own header
     comment for the "overwrite oldest rather than block the producer,
     skip forward to the newest epoch rather than lag" rationale this
     was originally written for and now shares with uRTLSDR.pas.

     GAIN MODEL:
     HackRF's three independent gain controls (LNA, VGA, RF amp) are
     exposed via Capabilities.GainStages, in that order, rather than as
     named methods - SetGain(StageIndex, Value) dispatches on
     StageIndex, matching the generic TSDRDevice interface uSDRMain.pas
     drives its capability-adaptive UI from (see that unit's own
     comment). StageIndex 0/1 (LNA/VGA) are gkContinuous with HackRF's
     real 8dB/2dB step granularity; StageIndex 2 (RF amp) is gkBoolean
     (Value 0/1).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, newVMComplex, uSDRDevice;

const
  {$IFDEF WINDOWS}
  HackRFLibCandidates: array[0..0] of string = ('hackrf.dll');
                               // by convention, matching this repo's other
                               // runtime-bound libraries - not tested on
                               // Windows, no HackRF hardware available there
  {$ELSE}
    {$IFDEF DARWIN}
  // MacPorts' hackrf port (confirmed via a standalone probe on a real
  // HackRF One + this exact install) puts libhackrf.dylib at
  // /opt/local/lib, which is NOT on dyld's default search path - a bare
  // 'libhackrf.dylib' LoadLibrary fails even with the file right there,
  // while the full path resolves - same "bare name first (for a possible
  // future PATH/DYLD_LIBRARY_PATH setup), then a known absolute location"
  // pattern uSDRplay.pas/OpenCLAPI.pas already use for their own
  // non-standard-location libraries. Homebrew's own hackrf formula
  // installs to /opt/homebrew/lib (Apple Silicon) or /usr/local/lib
  // (Intel) instead - not verified on this machine (MacPorts, not
  // Homebrew, is what's installed here), included as a reasonable
  // best-guess fallback rather than left out entirely, following the
  // installer's own documented default prefixes.
  HackRFLibCandidates: array[0..4] of string = (
    'libhackrf.dylib',
    '/opt/local/lib/libhackrf.dylib',
    '/opt/local/lib/libhackrf.0.dylib',
    '/opt/homebrew/lib/libhackrf.dylib',
    '/usr/local/lib/libhackrf.dylib'
  );
    {$ELSE}
  HackRFLibCandidates: array[0..0] of string = ('libhackrf.so.0');
    {$ENDIF}
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
  Thackrf_set_antenna_enable = function(device: Phackrf_device; value: Byte): Integer; cdecl;
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
  hackrf_set_antenna_enable: Thackrf_set_antenna_enable;
  hackrf_set_baseband_filter_bandwidth: Thackrf_set_baseband_filter_bandwidth;
  hackrf_compute_baseband_filter_bw_round_down_lt: Thackrf_compute_baseband_filter_bw_round_down_lt;
  hackrf_error_name: Thackrf_error_name;

  HackRFLibLoaded: Boolean = False;

type
  { THackRFDevice }
  THackRFDevice = class(TSDRDevice)
  private
    FDevice: Phackrf_device;
    FRing: TSDRRingBuffer;

    function CallFailed(RC: Integer; const Routine: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    function Open: Boolean; override;
    procedure Close; override;

    function SetFrequencyHz(Hz: QWord): Boolean; override;
    function SetSampleRateHz(Hz: Double): Boolean; override;
    function SetGain(StageIndex: Integer; Value: Double): Boolean; override;
    function SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean; override;

    function StartRX: Boolean; override;
    function StopRX: Boolean; override;

    // Called only from HackRFRxCallback, on libhackrf's own USB thread.
    procedure OnRawData(Buf: PByte; Len: Integer);

    function TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean; override;
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
  Pointer(hackrf_set_antenna_enable)                      := Load('hackrf_set_antenna_enable');
  Pointer(hackrf_set_baseband_filter_bandwidth)           := Load('hackrf_set_baseband_filter_bandwidth');
  Pointer(hackrf_compute_baseband_filter_bw_round_down_lt) := Load('hackrf_compute_baseband_filter_bw_round_down_lt');
  Pointer(hackrf_error_name)                              := Load('hackrf_error_name');
end;

function HackRFLibCandidateList: string;
var
  i: Integer;
begin
  Result := '';
  for i := Low(HackRFLibCandidates) to High(HackRFLibCandidates) do begin
    if i > Low(HackRFLibCandidates) then Result := Result + ', ';
    Result := Result + HackRFLibCandidates[i];
  end;
end;

function InitializeHackRFLib: Boolean;
var
  i: Integer;
begin
  if HackRFHandle = NilHandle then begin
    for i := Low(HackRFLibCandidates) to High(HackRFLibCandidates) do begin
      HackRFHandle := LoadLibrary(HackRFLibCandidates[i]);
      if HackRFHandle <> NilHandle then Break;
    end;
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
  FRing := TSDRRingBuffer.Create(HackRFRingBytes);
  FCenterFreqHz := 95000000;
  FSampleRateHz := 20000000.0;

  FCapabilities.DeviceName := 'HackRF';
  FCapabilities.MinFreqHz := 1.0e6;
  FCapabilities.MaxFreqHz := 6.0e9;
  SetLength(FCapabilities.SampleRates, 6);
  FCapabilities.SampleRates[0] := 2.0e6;
  FCapabilities.SampleRates[1] := 4.0e6;
  FCapabilities.SampleRates[2] := 8.0e6;
  FCapabilities.SampleRates[3] := 10.0e6;
  FCapabilities.SampleRates[4] := 16.0e6;
  FCapabilities.SampleRates[5] := 20.0e6;
  // Default to the lowest offered rate, not the highest - uFMReceiver.pas's
  // DSP chain (TRationalResamplerC's wideband antialiasing filter runs
  // directly at FsIn) is direct-form and single-threaded, and its own
  // header comment documents "audio worked at 2-3Msps and fell to silence
  // at higher rates once the DSP thread could no longer keep up with real
  // time" - 20Msps was ~7-10x that ceiling. RTL-SDR (2.4Msps) and SDRplay
  // (2.0Msps) already default within the sustainable range; HackRF alone
  // was defaulting to its hardware maximum, causing the shared stream
  // ring (uSDRRFSource.pas, 1 second of capacity) to fill faster than the
  // DSP thread could drain it - confirmed as the cause of a reported
  // periodic (~1s) audio glitch: once a consumer falls a full ring's
  // worth of RF time behind, TryReadEpoch hard-skips its cursor forward,
  // discarding whatever audio derived from the skipped samples. A single
  // FM channel only ever needs ~200kHz of that bandwidth regardless, so
  // there's no reception-quality reason to prefer a wider capture by
  // default.
  FCapabilities.DefaultSampleRateHz := 2.0e6;
  FCapabilities.DefaultFreqHz := 95000000;

  SetLength(FCapabilities.GainStages, 3);
  FCapabilities.GainStages[0].Name := 'LNA Gain';
  FCapabilities.GainStages[0].Kind := gkContinuous;
  FCapabilities.GainStages[0].Min := 0;
  FCapabilities.GainStages[0].Max := 40;
  FCapabilities.GainStages[0].Step := 8;
  FCapabilities.GainStages[0].UnitSuffix := 'dB';
  FCapabilities.GainStages[1].Name := 'VGA Gain';
  FCapabilities.GainStages[1].Kind := gkContinuous;
  FCapabilities.GainStages[1].Min := 0;
  FCapabilities.GainStages[1].Max := 62;
  FCapabilities.GainStages[1].Step := 2;
  FCapabilities.GainStages[1].UnitSuffix := 'dB';
  FCapabilities.GainStages[2].Name := 'RF Amp';
  FCapabilities.GainStages[2].Kind := gkBoolean;

  SetLength(FCapabilities.BoolOptions, 1);
  FCapabilities.BoolOptions[0].Name := 'Bias-T (Antenna Power)';
end;

destructor THackRFDevice.Destroy;
begin
  if FStreaming then StopRX;
  if FIsOpen then Close;
  FRing.Free;
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
  if FIsOpen then begin Result := True; Exit; end;

  if not HackRFLibLoaded then begin
    FLastError := 'libhackrf runtime library not found (tried: ' + HackRFLibCandidateList + ')';
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

  FIsOpen := True;
  Result := True;
end;

procedure THackRFDevice.Close;
begin
  if FStreaming then StopRX;
  if FIsOpen then begin
    hackrf_close(FDevice);
    FDevice := nil;
    FIsOpen := False;
  end;
end;

function THackRFDevice.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(hackrf_set_freq(FDevice, Hz), 'hackrf_set_freq') then Exit;
  FCenterFreqHz := Hz;
  Result := True;
end;

function THackRFDevice.SetSampleRateHz(Hz: Double): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(hackrf_set_sample_rate(FDevice, Hz), 'hackrf_set_sample_rate') then Exit;
  FSampleRateHz := Hz;
  Result := True;
end;

function THackRFDevice.SetGain(StageIndex: Integer; Value: Double): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case StageIndex of
    0: Result := not CallFailed(hackrf_set_lna_gain(FDevice, Round(Value)), 'hackrf_set_lna_gain');
    1: Result := not CallFailed(hackrf_set_vga_gain(FDevice, Round(Value)), 'hackrf_set_vga_gain');
    2: Result := not CallFailed(hackrf_set_amp_enable(FDevice, Ord(Value <> 0)), 'hackrf_set_amp_enable');
  else
    FLastError := 'unknown gain stage ' + IntToStr(StageIndex);
  end;
end;

function THackRFDevice.SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case OptionIndex of
    0: Result := not CallFailed(hackrf_set_antenna_enable(FDevice, Ord(Value)), 'hackrf_set_antenna_enable');
  else
    FLastError := 'unknown bool option ' + IntToStr(OptionIndex);
  end;
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
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if FStreaming then begin Result := True; Exit; end;

  FRing.Reset;

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
begin
  FRing.Write(Buf, Len);
end;

function THackRFDevice.TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean;
const
  s = 'THackRFDevice.TryReadEpoch : ';
var
  Tmp: TSDRByteArray;
  i: Integer;
begin
  assert(N > 0, s + 'N must be positive');
  Result := False;
  if not FRing.TryReadNewest(N * 2, Tmp) then Exit;

  // Interleaved signed 8-bit I/Q, confirmed by the standalone probe -
  // see this unit's header comment. Normalised to roughly [-1,1).
  IQ := TVMobjZ.Create(1, N);
  for i := 0 to N - 1 do
    IQ[0, i] := Cplx(ShortInt(Tmp[i * 2]) / 128.0, ShortInt(Tmp[i * 2 + 1]) / 128.0);

  CorrectIQEpoch(IQ);
  Result := True;
end;

initialization
  HackRFLibLoaded := InitializeHackRFLib;

finalization
  if HackRFInited and Assigned(hackrf_exit) then hackrf_exit();
  if HackRFHandle <> NilHandle then UnloadLibrary(HackRFHandle);

end.
