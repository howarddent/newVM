unit uSDRRFSource;

{*******************************************************************************

     TSDRRFSource - a non-visual, installable Lazarus component wrapping
     everything hardware-specific about the SDR front end: USB device
     autodetection (uSDRDevice.pas's TSDRDevice, and each concrete backend
     - uHackRF.pas/uRTLSDR.pas/uSDRplay.pas), the capability-driven gain/
     frequency/sample-rate controls those backends expose, and the epoch
     read loop. Everything here already existed in uSDRMain.pas's TForm1
     (FDevice plus DetectAndOpenDevice/ApplyAllGains/etc.) - this unit
     pulls it out into its own component specifically so it can be dropped
     onto ANY form (design-time, via the component palette, same as
     Graphs/uVMPlot2D.pas's TVMPlot2D) rather than being wired by hand into
     one particular demo, and so a separate display component (see
     uVMPlotSDRSpectrum.pas's TSDRSpectrumAnalyser) can consume its output
     without depending on any GUI-layout specifics of uSDRMain.pas at all.

     OUTPUT STREAM: TryReadEpoch returns a (1,N) TVMobjC - SINGLE precision
     complex (newVMComplexSingle.pas), not the double-precision TVMobjZ
     TSDRDevice.TryReadEpoch itself returns - converted here, once per
     epoch. Single precision because the only current consumer
     (TSDRSpectrumAnalyser) uploads it straight to the GPU via newVMCL,
     which is single-precision throughout (see newVMCL.pas's own header
     comment); doubling that up through TVMobjZ first would just be a
     wasted conversion. Any future onward-CPU-signal-processing consumer
     (the user's stated long-term goal - "leaving the CPU to manage
     onward signal processing of the stream") can call TryReadEpoch just
     as easily as the spectrum component does; nothing here is
     display-specific.

     No published properties: unlike TVMPlot2D/3D's Title/colour/etc,
     there's nothing about a hardware connection that's meaningful to
     configure at design time (form design happens with no device
     attached) - every real setting here (frequency, sample rate, gain)
     only makes sense once Connect has actually opened a real device and
     its Capabilities are known, so those are ordinary runtime methods,
     same shape as TSDRDevice's own interface.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, OneAPI, newVMComplex, newVMComplexSingle,
  uSDRDevice, uHackRF, uRTLSDR, uSDRplay;

type
  { TSDRRFSource }
  TSDRRFSource = class(TComponent)
  private
    FDevice: TSDRDevice;
    FLastError: string;
    function GetCapabilities: TSDRCapabilities;
    function GetIsOpen: Boolean;
    function GetIsStreaming: Boolean;
    function GetCenterFreqHz: QWord;
    function GetSampleRateHz: Double;
    function GetDeviceName: string;
  public
    destructor Destroy; override;

    // Tries each known backend in turn (same order/rationale as
    // uSDRMain.pas's original DetectAndOpenDevice: HackRF, then RTL-SDR,
    // then SDRplay - first to actually Open wins). Returns False (with
    // LastError/ErrMsg set) if none respond, or if already connected.
    function Connect(out ErrMsg: string): Boolean;
    procedure Disconnect;

    function StartStreaming(SampleRateHz: Double; FreqHz: QWord): Boolean;
    procedure StopStreaming;

    function SetFrequencyHz(Hz: QWord): Boolean;
    function SetGain(StageIndex: Integer; Value: Double): Boolean;
    function SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;

    // Called from the GUI thread, same convention as TSDRDevice's own
    // TryReadEpoch (which this wraps and converts). Returns True and
    // fills IQ (a fresh (1,N) TVMobjC) iff a full N-sample epoch was
    // available.
    function TryReadEpoch(N: Integer; out IQ: TVMobjC): Boolean;

    property Capabilities: TSDRCapabilities read GetCapabilities;
    property IsOpen: Boolean read GetIsOpen;
    property IsStreaming: Boolean read GetIsStreaming;
    property CenterFreqHz: QWord read GetCenterFreqHz;
    property SampleRateHz: Double read GetSampleRateHz;
    property DeviceName: string read GetDeviceName;
    property LastError: string read FLastError;
  end;

procedure Register;

implementation

destructor TSDRRFSource.Destroy;
begin
  FDevice.Free;   // stops RX and closes the device itself, if still open
  inherited Destroy;
end;

function TSDRRFSource.GetCapabilities: TSDRCapabilities;
begin
  if Assigned(FDevice) then Result := FDevice.Capabilities
  else Result := Default(TSDRCapabilities);
end;

function TSDRRFSource.GetIsOpen: Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen;
end;

function TSDRRFSource.GetIsStreaming: Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsStreaming;
end;

function TSDRRFSource.GetCenterFreqHz: QWord;
begin
  if Assigned(FDevice) then Result := FDevice.CenterFreqHz else Result := 0;
end;

function TSDRRFSource.GetSampleRateHz: Double;
begin
  if Assigned(FDevice) then Result := FDevice.SampleRateHz else Result := 0;
end;

function TSDRRFSource.GetDeviceName: string;
begin
  if Assigned(FDevice) then Result := FDevice.Capabilities.DeviceName else Result := '';
end;

function TSDRRFSource.Connect(out ErrMsg: string): Boolean;
var
  HackRF: THackRFDevice;
  RTLSDR: TRTLSDRDevice;
  SDRplay: TSDRplayDevice;
  Reasons: string;
begin
  Result := False;
  ErrMsg := '';
  if Assigned(FDevice) then begin
    ErrMsg := 'already connected';
    Exit;
  end;

  Reasons := '';

  HackRF := THackRFDevice.Create;
  if HackRF.Open then begin
    FDevice := HackRF;
    Result := True;
    Exit;
  end;
  Reasons := 'HackRF: ' + HackRF.LastError;
  HackRF.Free;

  RTLSDR := TRTLSDRDevice.Create;
  if RTLSDR.Open then begin
    FDevice := RTLSDR;
    Result := True;
    Exit;
  end;
  Reasons := Reasons + '; RTL-SDR: ' + RTLSDR.LastError;
  RTLSDR.Free;

  SDRplay := TSDRplayDevice.Create;
  if SDRplay.Open then begin
    FDevice := SDRplay;
    Result := True;
    Exit;
  end;
  Reasons := Reasons + '; SDRplay: ' + SDRplay.LastError;
  SDRplay.Free;

  ErrMsg := 'no SDR device found (' + Reasons + ')';
  FLastError := ErrMsg;
end;

procedure TSDRRFSource.Disconnect;
begin
  if not Assigned(FDevice) then Exit;
  if FDevice.IsStreaming then FDevice.StopRX;
  FreeAndNil(FDevice);
end;

function TSDRRFSource.StartStreaming(SampleRateHz: Double; FreqHz: QWord): Boolean;
begin
  Result := False;
  if not Assigned(FDevice) then Exit;
  if not FDevice.SetSampleRateHz(SampleRateHz) then begin
    FLastError := FDevice.LastError;
    Exit;
  end;
  if not FDevice.SetFrequencyHz(FreqHz) then begin
    FLastError := FDevice.LastError;
    Exit;
  end;
  Result := FDevice.StartRX;
  if not Result then FLastError := FDevice.LastError;
end;

procedure TSDRRFSource.StopStreaming;
begin
  if Assigned(FDevice) and FDevice.IsStreaming then FDevice.StopRX;
end;

function TSDRRFSource.SetFrequencyHz(Hz: QWord): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.SetFrequencyHz(Hz);
  if not Result and Assigned(FDevice) then FLastError := FDevice.LastError;
end;

function TSDRRFSource.SetGain(StageIndex: Integer; Value: Double): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen and FDevice.SetGain(StageIndex, Value);
end;

function TSDRRFSource.SetBoolOption(OptionIndex: Integer; Value: Boolean): Boolean;
begin
  Result := Assigned(FDevice) and FDevice.IsOpen and FDevice.SetBoolOption(OptionIndex, Value);
end;

function TSDRRFSource.TryReadEpoch(N: Integer; out IQ: TVMobjC): Boolean;
var
  IQD: TVMobjZ;
  i: Integer;
  Bin: TComplex16;
begin
  Result := False;
  if not Assigned(FDevice) then Exit;
  if not FDevice.TryReadEpoch(N, IQD) then Exit;

  IQ := TVMobjC.Create(1, N);
  for i := 0 to N - 1 do begin
    Bin := IQD[0, i];
    IQ[0, i] := Cplx8(Bin.re, Bin.im);
  end;
  Result := True;
end;

procedure Register;
begin
  RegisterComponents('SDR', [TSDRRFSource]);
end;

end.
