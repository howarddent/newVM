unit uRTLSDR;

{*******************************************************************************

     Runtime (dlopen-based) binding to librtlsdr, plus TRTLSDRDevice - a
     TSDRDevice (uSDRDevice.pas) implementation for RTL2832U-based
     dongles (confirmed on this machine: a Realtek RTL2838 DVB-T stick
     with a Rafael Micro R820T tuner).

     WHY DLOPEN INSTEAD OF LINK-TIME EXTERNAL:
     Same rationale as uHackRF.pas/fftw3.pas - librtlsdr2 is installed as
     a plain runtime package (librtlsdr.so.2), no -dev package, no
     unversioned symlink. LoadLibrary/GetProcedureAddress against the
     exact versioned name, resolved once in this unit's initialization
     section, tolerant of the library being absent.

     Every bound function signature, the callback ABI, and the
     unsigned-8-bit sample format below were confirmed against the real,
     linked librtlsdr.so.2 and the physically attached dongle with a
     standalone throwaway probe program (opened the device, printed its
     name/tuner type/gain list, streamed ~4MB via rtlsdr_read_async,
     confirmed rtlsdr_cancel_async unblocks it cleanly) BEFORE being
     wired in here - same discipline uHackRF.pas's own probe used. The
     probe found: "Generic RTL2832U OEM", tuner type 5 (R820T), a
     29-entry gain list from 0 to 496 (tenths of dB, i.e. 0-49.6dB), and
     confirmed samples arrive as interleaved unsigned bytes centred
     around ~127 (not signed, unlike HackRF).

     THREADING - THE KEY DIFFERENCE FROM uHackRF.pas:
     hackrf_start_rx spawns its own libusb thread internally and returns
     immediately; rtlsdr_read_async does not - it BLOCKS the calling
     thread for the entire life of the stream, only returning once
     rtlsdr_cancel_async is called (from another thread). TRTLSDRDevice
     therefore runs it on its own TRTLSDRReadThread rather than just
     registering a callback and returning, unlike THackRFDevice.StartRX.
     The callback itself (RTLSDRRxCallback) still runs synchronously
     inside that blocking call - i.e. on TRTLSDRReadThread's own thread,
     not the GUI thread - so it follows the exact same "write into a
     TSDRRingBuffer, nothing else" discipline HackRF's callback does.

     GAIN MODEL:
     Unlike HackRF's two independent continuous stages plus a boolean
     amp, RTL-SDR exposes one gkDiscreteList stage (StageIndex 0, "Tuner
     Gain" - populated from rtlsdr_get_tuner_gains, so it reflects
     whatever this specific dongle's tuner chip actually supports, not a
     guessed table) plus one gkBoolean stage (StageIndex 1, "Auto Gain" -
     rtlsdr_set_tuner_gain_mode's manual/auto toggle; the separate
     RTL2832 digital-IF AGC, rtlsdr_set_agc_mode, is left at its default
     and not exposed - one real gain toggle is enough here).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, newVMComplex, uSDRDevice;

const
  {$IFDEF WINDOWS}
  RTLSDRLib = 'rtlsdr.dll';   // by convention, matching this repo's other
                               // runtime-bound libraries - not tested on
                               // Windows, no RTL-SDR hardware available there
  {$ELSE}
  RTLSDRLib = 'librtlsdr.so.2';
  {$ENDIF}

  // Ring buffer capacity - RTL-SDR's max practical sample rate (~3.2Msps,
  // 2 bytes/sample = 6.4MB/s) is far below HackRF's, so this could be
  // much smaller than HackRFRingBytes and still cover many GUI ticks;
  // kept the same size anyway for a single shared sense of "plenty of
  // headroom", not because RTL-SDR needs it.
  RTLSDRRingBytes = 4 * 1024 * 1024;

  // Practical tuned-frequency ranges per rtlsdr_get_tuner_type result,
  // used to populate Capabilities.MinFreqHz/MaxFreqHz per the actual
  // tuner chip on the attached dongle rather than one guess for every
  // RTL-SDR - see TunerFreqRange below. Values are the commonly-cited
  // practical ranges for each chip (not exact datasheet limits, and
  // E4000's real range has a ~1100-1250MHz gap this simplifies over) -
  // good enough for setting the frequency edit's bounds, not a precision
  // RF spec.
  TUNER_UNKNOWN = 0;
  TUNER_E4000   = 1;
  TUNER_FC0012  = 2;
  TUNER_FC0013  = 3;
  TUNER_FC2580  = 4;
  TUNER_R820T   = 5;
  TUNER_R828D   = 6;

type
  Prtlsdr_dev = Pointer;

  Trtlsdr_read_async_cb_t = procedure(buf: PByte; len: LongWord; ctx: Pointer); cdecl;

  Trtlsdr_get_device_count = function(): LongWord; cdecl;
  Trtlsdr_get_device_name = function(index: LongWord): PAnsiChar; cdecl;
  Trtlsdr_open = function(var dev: Prtlsdr_dev; index: LongWord): Integer; cdecl;
  Trtlsdr_close = function(dev: Prtlsdr_dev): Integer; cdecl;
  Trtlsdr_set_center_freq = function(dev: Prtlsdr_dev; freq: LongWord): Integer; cdecl;
  Trtlsdr_set_sample_rate = function(dev: Prtlsdr_dev; rate: LongWord): Integer; cdecl;
  Trtlsdr_set_tuner_gain_mode = function(dev: Prtlsdr_dev; manual: Integer): Integer; cdecl;
  Trtlsdr_set_tuner_gain = function(dev: Prtlsdr_dev; gain: Integer): Integer; cdecl;
  Trtlsdr_get_tuner_gains = function(dev: Prtlsdr_dev; gains: PInteger): Integer; cdecl;
  Trtlsdr_get_tuner_type = function(dev: Prtlsdr_dev): Integer; cdecl;
  Trtlsdr_set_tuner_bandwidth = function(dev: Prtlsdr_dev; bw: LongWord): Integer; cdecl;
  Trtlsdr_reset_buffer = function(dev: Prtlsdr_dev): Integer; cdecl;
  Trtlsdr_read_async = function(dev: Prtlsdr_dev; cb: Trtlsdr_read_async_cb_t; ctx: Pointer;
    buf_num: LongWord; buf_len: LongWord): Integer; cdecl;
  Trtlsdr_cancel_async = function(dev: Prtlsdr_dev): Integer; cdecl;
  Trtlsdr_set_bias_tee = function(dev: Prtlsdr_dev; on_: Integer): Integer; cdecl;

var
  rtlsdr_get_device_count: Trtlsdr_get_device_count;
  rtlsdr_get_device_name: Trtlsdr_get_device_name;
  rtlsdr_open: Trtlsdr_open;
  rtlsdr_close: Trtlsdr_close;
  rtlsdr_set_center_freq: Trtlsdr_set_center_freq;
  rtlsdr_set_sample_rate: Trtlsdr_set_sample_rate;
  rtlsdr_set_tuner_gain_mode: Trtlsdr_set_tuner_gain_mode;
  rtlsdr_set_tuner_gain: Trtlsdr_set_tuner_gain;
  rtlsdr_get_tuner_gains: Trtlsdr_get_tuner_gains;
  rtlsdr_get_tuner_type: Trtlsdr_get_tuner_type;
  rtlsdr_set_tuner_bandwidth: Trtlsdr_set_tuner_bandwidth;
  rtlsdr_reset_buffer: Trtlsdr_reset_buffer;
  rtlsdr_read_async: Trtlsdr_read_async;
  rtlsdr_cancel_async: Trtlsdr_cancel_async;
  rtlsdr_set_bias_tee: Trtlsdr_set_bias_tee;

  RTLSDRLibLoaded: Boolean = False;

type
  { TRTLSDRDevice }
  TRTLSDRDevice = class(TSDRDevice)
  private
    FDevice: Prtlsdr_dev;
    FRing: TSDRRingBuffer;
    FReadThread: TThread;

    function CallFailed(RC: Integer; const Routine: string): Boolean;
    procedure BuildCapabilities;
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

    // Called only from RTLSDRRxCallback, on FReadThread.
    procedure OnRawData(Buf: PByte; Len: Integer);

    function TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean; override;
  end;

implementation

var
  RTLSDRHandle: TLibHandle = NilHandle;

function Load(const Name: string): Pointer;
begin
  Result := GetProcedureAddress(RTLSDRHandle, Name);
end;

procedure LoadRTLSDRAddresses;
begin
  Pointer(rtlsdr_get_device_count) := Load('rtlsdr_get_device_count');
  Pointer(rtlsdr_get_device_name)  := Load('rtlsdr_get_device_name');
  Pointer(rtlsdr_open)             := Load('rtlsdr_open');
  Pointer(rtlsdr_close)            := Load('rtlsdr_close');
  Pointer(rtlsdr_set_center_freq)  := Load('rtlsdr_set_center_freq');
  Pointer(rtlsdr_set_sample_rate)  := Load('rtlsdr_set_sample_rate');
  Pointer(rtlsdr_set_tuner_gain_mode) := Load('rtlsdr_set_tuner_gain_mode');
  Pointer(rtlsdr_set_tuner_gain)   := Load('rtlsdr_set_tuner_gain');
  Pointer(rtlsdr_get_tuner_gains)  := Load('rtlsdr_get_tuner_gains');
  Pointer(rtlsdr_get_tuner_type)   := Load('rtlsdr_get_tuner_type');
  Pointer(rtlsdr_set_tuner_bandwidth) := Load('rtlsdr_set_tuner_bandwidth');
  Pointer(rtlsdr_reset_buffer)     := Load('rtlsdr_reset_buffer');
  Pointer(rtlsdr_read_async)       := Load('rtlsdr_read_async');
  Pointer(rtlsdr_cancel_async)     := Load('rtlsdr_cancel_async');
  Pointer(rtlsdr_set_bias_tee)     := Load('rtlsdr_set_bias_tee');
end;

function InitializeRTLSDRLib: Boolean;
begin
  if RTLSDRHandle = NilHandle then begin
    RTLSDRHandle := LoadLibrary(RTLSDRLib);
    if RTLSDRHandle <> NilHandle then LoadRTLSDRAddresses;
  end;
  Result := RTLSDRHandle <> NilHandle;
end;

// See TUNER_* constants above - practical tuned-frequency range per
// tuner chip, defaulting to the common R820T range for anything
// unrecognised.
procedure TunerFreqRange(TunerType: Integer; out MinHz, MaxHz: Double);
begin
  case TunerType of
    TUNER_E4000:  begin MinHz := 52.0e6;  MaxHz := 2200.0e6; end;
    TUNER_FC0012: begin MinHz := 22.0e6;  MaxHz := 948.6e6;  end;
    TUNER_FC0013: begin MinHz := 22.0e6;  MaxHz := 948.6e6;  end;
    TUNER_FC2580: begin MinHz := 146.0e6; MaxHz := 924.0e6;  end;
  else
    // TUNER_R820T, TUNER_R828D, TUNER_UNKNOWN, or anything else -
    // R820T/R828D is by far the most common chip in current dongles.
    MinHz := 24.0e6;
    MaxHz := 1766.0e6;
  end;
end;

// Module-level cdecl callback librtlsdr calls directly from inside the
// blocking rtlsdr_read_async - ctx is the TRTLSDRDevice instance that
// started this stream (see TRTLSDRReadThread.Execute), cast back from
// the void* librtlsdr hands through unchanged. Void-returning, unlike
// HackRF's int-returning callback - there's no per-call "stop now" signal
// here, only the separate rtlsdr_cancel_async call.
procedure RTLSDRRxCallback(buf: PByte; len: LongWord; ctx: Pointer); cdecl;
var
  Dev: TRTLSDRDevice;
begin
  Dev := TRTLSDRDevice(ctx);
  if Assigned(Dev) then Dev.OnRawData(buf, len);
end;

{ TRTLSDRReadThread }

type
  TRTLSDRReadThread = class(TThread)
  private
    FDevice: Prtlsdr_dev;
    FOwner: TRTLSDRDevice;
  public
    constructor Create(ADevice: Prtlsdr_dev; AOwner: TRTLSDRDevice);
    procedure Execute; override;
  end;

constructor TRTLSDRReadThread.Create(ADevice: Prtlsdr_dev; AOwner: TRTLSDRDevice);
begin
  inherited Create(True);   // suspended - caller starts it explicitly once assigned
  FDevice := ADevice;
  FOwner := AOwner;
  FreeOnTerminate := False;   // TRTLSDRDevice.StopRX Frees it itself, after WaitFor
end;

// Blocks here for the entire life of the stream - rtlsdr_read_async only
// returns once rtlsdr_cancel_async is called from StopRX (see this
// unit's header comment for why this needs its own thread at all, unlike
// HackRF). buf_num/buf_len of 0/0 uses librtlsdr's own default transfer
// buffering, same "trust the library's own sane defaults" convention
// HackRF's binding uses for its own transfer size.
procedure TRTLSDRReadThread.Execute;
begin
  rtlsdr_read_async(FDevice, @RTLSDRRxCallback, Pointer(FOwner), 0, 0);
end;

{ TRTLSDRDevice }

constructor TRTLSDRDevice.Create;
begin
  inherited Create;
  FRing := TSDRRingBuffer.Create(RTLSDRRingBytes);
  FCenterFreqHz := 95000000;
  FSampleRateHz := 2400000.0;

  // A default, device-independent Capabilities so this record isn't
  // garbage before Open succeeds - BuildCapabilities replaces
  // GainStages/MinFreqHz/MaxFreqHz with real, queried values once a
  // device is actually open (it needs the live device for
  // rtlsdr_get_tuner_gains/_get_tuner_type - see that method's own
  // comment).
  FCapabilities.DeviceName := 'RTL-SDR';
  FCapabilities.MinFreqHz := 24.0e6;
  FCapabilities.MaxFreqHz := 1766.0e6;
  SetLength(FCapabilities.SampleRates, 8);
  FCapabilities.SampleRates[0] := 0.25e6;
  FCapabilities.SampleRates[1] := 1.024e6;
  FCapabilities.SampleRates[2] := 1.536e6;
  FCapabilities.SampleRates[3] := 1.92e6;
  FCapabilities.SampleRates[4] := 2.048e6;
  FCapabilities.SampleRates[5] := 2.4e6;
  FCapabilities.SampleRates[6] := 2.56e6;
  FCapabilities.SampleRates[7] := 3.2e6;
  FCapabilities.DefaultSampleRateHz := 2.4e6;
  FCapabilities.DefaultFreqHz := 95000000;

  // Unlike GainStages, this doesn't need a live device to populate -
  // librtlsdr has no "does this dongle actually have bias-T hardware"
  // query, so it's simply always offered (as rtl_biast/most SDR
  // software does too); on a dongle with no bias-T circuit the call
  // just has no effect.
  SetLength(FCapabilities.BoolOptions, 1);
  FCapabilities.BoolOptions[0].Name := 'Bias-T (Antenna Power)';
end;

destructor TRTLSDRDevice.Destroy;
begin
  if FStreaming then StopRX;
  if FIsOpen then Close;
  FRing.Free;
  inherited Destroy;
end;

function TRTLSDRDevice.CallFailed(RC: Integer; const Routine: string): Boolean;
begin
  // librtlsdr's error convention is a plain negative int code with no
  // string-lookup function (unlike hackrf_error_name) - just report the
  // code itself.
  Result := RC <> 0;
  if Result then
    FLastError := Routine + ' failed with code ' + IntToStr(RC);
end;

// Replaces the constructor's placeholder MinFreqHz/MaxFreqHz/GainStages
// with values read from the live, just-opened device - see this unit's
// header comment ("GAIN MODEL") for why there are exactly two stages,
// and TunerFreqRange above for the per-chip frequency range table.
procedure TRTLSDRDevice.BuildCapabilities;
var
  RawGains: array[0..63] of Integer;
  NGains, i: Integer;
  TunerType: Integer;
begin
  TunerType := rtlsdr_get_tuner_type(FDevice);
  TunerFreqRange(TunerType, FCapabilities.MinFreqHz, FCapabilities.MaxFreqHz);

  NGains := rtlsdr_get_tuner_gains(FDevice, @RawGains[0]);
  if NGains < 0 then NGains := 0;
  if NGains > Length(RawGains) then NGains := Length(RawGains);

  SetLength(FCapabilities.GainStages, 2);
  FCapabilities.GainStages[0].Name := 'Tuner Gain';
  FCapabilities.GainStages[0].Kind := gkDiscreteList;
  SetLength(FCapabilities.GainStages[0].DiscreteValues, NGains);
  for i := 0 to NGains - 1 do
    FCapabilities.GainStages[0].DiscreteValues[i] := RawGains[i] / 10.0;   // tenths of dB -> dB

  FCapabilities.GainStages[1].Name := 'Auto Gain';
  FCapabilities.GainStages[1].Kind := gkBoolean;
end;

function TRTLSDRDevice.Open: Boolean;
var
  RC: Integer;
begin
  Result := False;
  if FIsOpen then begin Result := True; Exit; end;

  if not RTLSDRLibLoaded then begin
    FLastError := 'librtlsdr runtime library (' + RTLSDRLib + ') not found';
    Exit;
  end;

  if rtlsdr_get_device_count() = 0 then begin
    FLastError := 'no RTL-SDR device found';
    Exit;
  end;

  FDevice := nil;
  RC := rtlsdr_open(FDevice, 0);
  if CallFailed(RC, 'rtlsdr_open') then Exit;

  FIsOpen := True;
  BuildCapabilities;
  Result := True;
end;

procedure TRTLSDRDevice.Close;
begin
  if FStreaming then StopRX;
  if FIsOpen then begin
    rtlsdr_close(FDevice);
    FDevice := nil;
    FIsOpen := False;
  end;
end;

function TRTLSDRDevice.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(rtlsdr_set_center_freq(FDevice, LongWord(Hz)), 'rtlsdr_set_center_freq') then Exit;
  FCenterFreqHz := Hz;
  Result := True;
end;

function TRTLSDRDevice.SetSampleRateHz(Hz: Double): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if CallFailed(rtlsdr_set_sample_rate(FDevice, Round(Hz)), 'rtlsdr_set_sample_rate') then Exit;
  FSampleRateHz := Hz;
  Result := True;
end;

// StageIndex 0 (Tuner Gain, dB): switches to manual mode and sets the
// gain directly - librtlsdr wants tenths of dB. StageIndex 1 (Auto
// Gain): toggles tuner gain mode itself (manual=0 -> chip auto gain,
// 1 -> manual) - see this unit's header comment for why this is the one
// AGC toggle exposed here.
function TRTLSDRDevice.SetGain(StageIndex: Integer; Value: Double): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case StageIndex of
    0: begin
      if CallFailed(rtlsdr_set_tuner_gain_mode(FDevice, 1), 'rtlsdr_set_tuner_gain_mode') then Exit;
      Result := not CallFailed(rtlsdr_set_tuner_gain(FDevice, Round(Value * 10)), 'rtlsdr_set_tuner_gain');
    end;
    1: begin
      if Value <> 0 then
        Result := not CallFailed(rtlsdr_set_tuner_gain_mode(FDevice, 0), 'rtlsdr_set_tuner_gain_mode')
      else
        Result := not CallFailed(rtlsdr_set_tuner_gain_mode(FDevice, 1), 'rtlsdr_set_tuner_gain_mode');
    end;
  else
    FLastError := 'unknown gain stage ' + IntToStr(StageIndex);
  end;
end;

function TRTLSDRDevice.SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  case OptionIndex of
    0: Result := not CallFailed(rtlsdr_set_bias_tee(FDevice, Ord(Value)), 'rtlsdr_set_bias_tee');
  else
    FLastError := 'unknown bool option ' + IntToStr(OptionIndex);
  end;
end;

function TRTLSDRDevice.StartRX: Boolean;
begin
  Result := False;
  if not FIsOpen then begin FLastError := 'device not open'; Exit; end;
  if FStreaming then begin Result := True; Exit; end;

  FRing.Reset;

  if CallFailed(rtlsdr_set_tuner_bandwidth(FDevice, 0), 'rtlsdr_set_tuner_bandwidth') then Exit;
  if CallFailed(rtlsdr_reset_buffer(FDevice), 'rtlsdr_reset_buffer') then Exit;

  FReadThread := TRTLSDRReadThread.Create(FDevice, Self);
  FReadThread.Start;

  FStreaming := True;
  Result := True;
end;

// rtlsdr_cancel_async unblocks the read thread's rtlsdr_read_async call
// (see TRTLSDRReadThread.Execute); WaitFor then blocks the GUI thread
// briefly until that actually happens - the standard librtlsdr shutdown
// sequence, acceptable latency for a Stop button click.
function TRTLSDRDevice.StopRX: Boolean;
begin
  Result := True;
  if not FStreaming then Exit;
  if Assigned(FDevice) then
    Result := not CallFailed(rtlsdr_cancel_async(FDevice), 'rtlsdr_cancel_async');
  if Assigned(FReadThread) then begin
    FReadThread.WaitFor;
    FreeAndNil(FReadThread);
  end;
  FStreaming := False;
end;

procedure TRTLSDRDevice.OnRawData(Buf: PByte; Len: Integer);
begin
  FRing.Write(Buf, Len);
end;

function TRTLSDRDevice.TryReadEpoch(N: Integer; out IQ: TVMobjZ): Boolean;
const
  s = 'TRTLSDRDevice.TryReadEpoch : ';
var
  Tmp: TSDRByteArray;
  i: Integer;
begin
  assert(N > 0, s + 'N must be positive');
  Result := False;
  if not FRing.TryReadNewest(N * 2, Tmp) then Exit;

  // Interleaved UNSIGNED 8-bit I/Q, confirmed by the standalone probe -
  // see this unit's header comment. DC-centred at ~127.5, unlike
  // HackRF's signed samples centred at 0 - normalised to roughly [-1,1)
  // the same way, just with that offset subtracted first.
  IQ := TVMobjZ.Create(1, N);
  for i := 0 to N - 1 do
    IQ[0, i] := Cplx((Tmp[i * 2] - 127.5) / 127.5, (Tmp[i * 2 + 1] - 127.5) / 127.5);

  CorrectIQEpoch(IQ);
  Result := True;
end;

initialization
  RTLSDRLibLoaded := InitializeRTLSDRLib;

finalization
  if RTLSDRHandle <> NilHandle then UnloadLibrary(RTLSDRHandle);

end.
