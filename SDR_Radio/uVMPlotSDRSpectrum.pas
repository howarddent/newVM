unit uVMPlotSDRSpectrum;

{*******************************************************************************

     TSDRSpectrumAnalyser - a visual, installable Lazarus component that
     consumes the single-precision complex IQ stream from a TSDRRFSource
     (uSDRRFSource.pas, published Source property - the standard LCL
     "consumer points at a sibling component" pattern, same shape as
     TDBGrid.DataSource) and displays it as a live spectrum + waterfall,
     using the existing Graphs/uVMPlotSpectrum.pas / uVMPlotWaterfall.pas
     OpenGL controls internally (created and Parented to Self exactly the
     way uSDRMain.pas's TForm1 used to do it by hand - see that unit's git
     history) rather than reimplementing their rendering.

     GPU PIPELINE (the point of this component - "the FFT/spectrum
     display and waterfall will be handled by the GPU"): each epoch's
     Hamming windowing and FFT run on the GPU via newVMCL.pas
     (TVMobjCL), not the CPU. The pipeline, per epoch:
       1. Source.TryReadEpoch -> a (1,N) TVMobjC (single-precision
          complex, CPU).
       2. Interleaved into a (1,2N) TVMobjS (re0,im0,re1,im1,...) -
          clFFT's own CLFFT_COMPLEX_INTERLEAVED layout, which is exactly
          what newVMCL's FFT expects (see newVMCL.pas's own header
          comment) - and uploaded to the GPU via ToDevice.
       3. Multiplied (GPU, elementwise) by a cached Hamming-window
          buffer, itself uploaded once per distinct EpochSize and reused
          every epoch after that (EnsureWindowCL) - each window
          coefficient duplicated at both the re and im position of its
          bin, so ordinary elementwise '*' against the interleaved IQ
          buffer applies the same scalar to both parts of every complex
          sample in one GPU call.
       4. FFT'd on the GPU (newVMCL.FFT).
       5. Downloaded back via ToHost - only the epoch-sized spectrum
          itself crosses back to the CPU, not the windowing/FFT compute.
     What's deliberately left on the CPU: turning that spectrum into an
     ascending-frequency, dB-scaled trace (fftshift + 10*Log10) - a
     cheap O(N) pass with no GPU primitive worth adding for it (newVMCL's
     own scope was deliberately kept to Core+FFT+MatMult - see
     newVMCL.pas's header comment), matching the user's actual goal:
     move the expensive FFT/windowing work off the CPU, not literally
     every scalar operation.

     CPU FALLBACK: if OpenCL/newVMCL isn't available at all (HAVE_OPENCL
     undefined - see newVMConfig.inc) or clFFT/the OpenCL runtime don't
     actually initialise on this machine (OpenCLReady = False, checked
     once, lazily, on the first epoch), every epoch instead goes through
     newVMComplexSingle.pas's existing PowerSpectrum(TVMobjC): TVMobjS -
     the same Hamming-window+FFT+|X|^2 math, just CPU-side - so this
     component still works, just without the GPU offload, on a machine
     with no usable OpenCL device. UsingGPU reports which path is
     actually active, for diagnostics.

     Deliberately NOT a giant pass-through property list mirroring every
     TVMPlotSpectrum/TVMPlotWaterfall property: SpectrumPlot/WaterfallPlot
     are exposed directly (public, not published) so calling code sets
     ShowAxes/YOffset/YGain/ScrollRate/etc. straight on the real control,
     the same properties documented in uVMPlotSpectrum.pas/
     uVMPlotWaterfall.pas themselves - duplicating dozens of forwarding
     properties here would only be another place for them to drift out of
     sync. Only Source/EpochSize/Active/UpdateIntervalMs - genuinely new
     concepts this component itself introduces - are published.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

{$I ..\newVMConfig.inc}

uses
  Classes, SysUtils, Controls, ExtCtrls, Math,
  newVM, newVMSingle, newVMComplexSingle,
  {$IFDEF HAVE_OPENCL}
  OpenCLAPI, newVMCL,
  {$ENDIF}
  uVMPlotSpectrum, uVMPlotWaterfall, uSDRRFSource;

const
  DefaultSDREpochSize = 8192;
  DefaultSDRUpdateIntervalMs = 30;

type
  { TSDRSpectrumAnalyser }
  TSDRSpectrumAnalyser = class(TPanel)
  private
    FSpectrumPlot: TVMPlotSpectrum;
    FWaterfallPlot: TVMPlotWaterfall;
    FUpdateTimer: TTimer;
    FSource: TSDRRFSource;
    FEpochSize: Integer;
    FUseGPU, FGPUChecked: Boolean;
    FGPUStatusMessage: string;
    FOnGPUStatusKnown: TNotifyEvent;
    {$IFDEF HAVE_OPENCL}
    FWindowCL: TVMobjCL;
    FWindowEpochSize: Integer;
    {$ENDIF}
    procedure SetSource(AValue: TSDRRFSource);
    procedure SetEpochSize(AValue: Integer);
    function GetActive: Boolean;
    procedure SetActive(AValue: Boolean);
    function GetUpdateIntervalMs: Integer;
    procedure SetUpdateIntervalMs(AValue: Integer);
    procedure UpdateTick(Sender: TObject);
    procedure ProcessEpoch(const IQ: TVMobjC);
    function ProcessEpochCPU(const IQ: TVMobjC): TVMobj;
    {$IFDEF HAVE_OPENCL}
    procedure EnsureWindowCL;
    function ProcessEpochGPU(const IQ: TVMobjC): TVMobj;
    {$ENDIF}
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    property SpectrumPlot: TVMPlotSpectrum read FSpectrumPlot;
    property WaterfallPlot: TVMPlotWaterfall read FWaterfallPlot;
    property UsingGPU: Boolean read FUseGPU;
    property GPUStatusMessage: string read FGPUStatusMessage;
  published
    property Source: TSDRRFSource read FSource write SetSource;
    property EpochSize: Integer read FEpochSize write SetEpochSize default DefaultSDREpochSize;
    property Active: Boolean read GetActive write SetActive default False;
    property UpdateIntervalMs: Integer read GetUpdateIntervalMs write SetUpdateIntervalMs
      default DefaultSDRUpdateIntervalMs;
    // Fired once, from the first epoch after (re)connecting - GPU vs CPU
    // is only known once OpenCLReady has actually been probed (see
    // ProcessEpoch) - so calling code (e.g. a status bar) can report
    // UsingGPU/GPUStatusMessage as soon as they're meaningful, rather
    // than reading them synchronously right after Active := True, before
    // the first epoch has run.
    property OnGPUStatusKnown: TNotifyEvent read FOnGPUStatusKnown write FOnGPUStatusKnown;
  end;

procedure Register;

implementation

constructor TSDRSpectrumAnalyser.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;

  FSpectrumPlot := TVMPlotSpectrum.Create(Self);
  FSpectrumPlot.Parent := Self;
  FSpectrumPlot.Align := alTop;
  FSpectrumPlot.Height := 320;
  FSpectrumPlot.Title := 'Spectrum';
  FSpectrumPlot.XAxisTitle := 'Frequency (MHz)';
  FSpectrumPlot.YAxisTitle := 'Power (dB)';
  FSpectrumPlot.ClearStack;   // discard the component's own default demo data

  FWaterfallPlot := TVMPlotWaterfall.Create(Self);
  FWaterfallPlot.Parent := Self;
  FWaterfallPlot.Align := alClient;
  FWaterfallPlot.Title := 'Waterfall';
  FWaterfallPlot.XAxisTitle := 'Frequency (MHz)';
  FWaterfallPlot.ClearStack;

  FUpdateTimer := TTimer.Create(Self);
  FUpdateTimer.Interval := DefaultSDRUpdateIntervalMs;
  FUpdateTimer.Enabled := False;
  FUpdateTimer.OnTimer := @UpdateTick;

  FEpochSize := DefaultSDREpochSize;
  {$IFDEF HAVE_OPENCL}
  FWindowEpochSize := 0;
  {$ENDIF}
end;

procedure TSDRSpectrumAnalyser.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = FSource) then FSource := nil;
end;

procedure TSDRSpectrumAnalyser.SetSource(AValue: TSDRRFSource);
begin
  if FSource = AValue then Exit;
  if Assigned(FSource) then FSource.RemoveFreeNotification(Self);
  FSource := AValue;
  if Assigned(FSource) then FSource.FreeNotification(Self);
end;

procedure TSDRSpectrumAnalyser.SetEpochSize(AValue: Integer);
begin
  if AValue = FEpochSize then Exit;
  FEpochSize := AValue;
end;

function TSDRSpectrumAnalyser.GetActive: Boolean;
begin
  Result := FUpdateTimer.Enabled;
end;

procedure TSDRSpectrumAnalyser.SetActive(AValue: Boolean);
begin
  // Re-probe (and re-fire OnGPUStatusKnown) on every fresh start, even
  // though OpenCLReady itself is cheap to re-call once cached - so a
  // status bar wired to OnGPUStatusKnown updates on every Start, not just
  // the component's very first one.
  if AValue and not FUpdateTimer.Enabled then FGPUChecked := False;
  FUpdateTimer.Enabled := AValue;
end;

function TSDRSpectrumAnalyser.GetUpdateIntervalMs: Integer;
begin
  Result := FUpdateTimer.Interval;
end;

procedure TSDRSpectrumAnalyser.SetUpdateIntervalMs(AValue: Integer);
begin
  FUpdateTimer.Interval := AValue;
end;

procedure TSDRSpectrumAnalyser.UpdateTick(Sender: TObject);
var
  IQ: TVMobjC;
begin
  if not Assigned(FSource) then Exit;
  if not FSource.TryReadEpoch(FEpochSize, IQ) then Exit;
  ProcessEpoch(IQ);
end;

procedure TSDRSpectrumAnalyser.ProcessEpoch(const IQ: TVMobjC);
var
  PowerSpec: TVMobj;
begin
  {$IFDEF HAVE_OPENCL}
  if not FGPUChecked then begin
    FUseGPU := OpenCLReady;
    if FUseGPU then FGPUStatusMessage := '' else FGPUStatusMessage := OpenCLLastError;
    FGPUChecked := True;
    if Assigned(FOnGPUStatusKnown) then FOnGPUStatusKnown(Self);
  end;
  if FUseGPU then
    PowerSpec := ProcessEpochGPU(IQ)
  else
    PowerSpec := ProcessEpochCPU(IQ);
  {$ELSE}
  if not FGPUChecked then begin
    FGPUChecked := True;
    FUseGPU := False;
    FGPUStatusMessage := 'OpenCL/newVMCL not available in this build';
    if Assigned(FOnGPUStatusKnown) then FOnGPUStatusKnown(Self);
  end;
  PowerSpec := ProcessEpochCPU(IQ);
  {$ENDIF}

  FSpectrumPlot.AddGraph(PowerSpec);
  FWaterfallPlot.AddGraph(PowerSpec);
end;

// Hamming-window + FFT + |X|^2 (newVMComplexSingle.pas's existing
// PowerSpectrum(TVMobjC), CPU-side), then fftshift (ascending frequency:
// negative-frequency bins first, same as uSDRMain.pas's original
// MergeLR/SubMatrix-based shift, expressed here as a direct index
// remap) and dB conversion.
function TSDRSpectrumAnalyser.ProcessEpochCPU(const IQ: TVMobjC): TVMobj;
var
  LinearPower: TVMobjS;
  HalfN, k, srcBin: Integer;
begin
  LinearPower := newVMComplexSingle.PowerSpectrum(IQ);
  HalfN := FEpochSize div 2;
  Result := TVMobj.Create(1, FEpochSize);
  for k := 0 to FEpochSize - 1 do begin
    srcBin := (k + HalfN) mod FEpochSize;
    Result[0, k] := 10 * Log10(LinearPower[0, srcBin] + 1e-12);
  end;
end;

{$IFDEF HAVE_OPENCL}
procedure TSDRSpectrumAnalyser.EnsureWindowCL;
var
  WHost: TVMobjS;
  i: Integer;
  w: Single;
begin
  if FWindowEpochSize = FEpochSize then Exit;
  WHost := TVMobjS.Create(1, 2 * FEpochSize);
  for i := 0 to FEpochSize - 1 do begin
    w := 0.54 - 0.46 * cos(2 * Pi * i / (FEpochSize - 1));
    WHost[0, 2*i]   := w;
    WHost[0, 2*i+1] := w;
  end;
  FWindowCL := ToDevice(WHost);
  FWindowEpochSize := FEpochSize;
end;

function TSDRSpectrumAnalyser.ProcessEpochGPU(const IQ: TVMobjC): TVMobj;
var
  Interleaved, HostSpec: TVMobjS;
  IQCL, Windowed, Spec: TVMobjCL;
  i, HalfN, k, srcBin: Integer;
  re, im: Single;
begin
  EnsureWindowCL;

  Interleaved := TVMobjS.Create(1, 2 * FEpochSize);
  for i := 0 to FEpochSize - 1 do begin
    Interleaved[0, 2*i]   := IQ[0, i].re;
    Interleaved[0, 2*i+1] := IQ[0, i].im;
  end;

  IQCL := ToDevice(Interleaved);
  Windowed := IQCL * FWindowCL;
  Spec := FFT(Windowed);
  HostSpec := ToHost(Spec);

  HalfN := FEpochSize div 2;
  Result := TVMobj.Create(1, FEpochSize);
  for k := 0 to FEpochSize - 1 do begin
    srcBin := (k + HalfN) mod FEpochSize;
    re := HostSpec[0, 2*srcBin];
    im := HostSpec[0, 2*srcBin+1];
    Result[0, k] := 10 * Log10(re*re + im*im + 1e-12);
  end;
end;
{$ENDIF}

procedure Register;
begin
  RegisterComponents('SDR', [TSDRSpectrumAnalyser]);
end;

end.
