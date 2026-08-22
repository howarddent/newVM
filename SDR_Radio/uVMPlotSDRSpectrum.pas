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

     THREE BACKENDS, NOT TWO: the same GPU pipeline above also runs via
     newVMMetal.pas (TVMobjMTL, Apple's own Metal + MetalPerformanceShaders-
     Graph) wherever HAVE_METAL is defined (Darwin/Apple-Silicon machines -
     see newvmconfigure.lpr's own HAVE_METAL probe and newVMMetal.pas's
     header comment for why this exists alongside, not instead of,
     newVMCL.pas's OpenCL path) - same windowing/FFT/download steps,
     ToDeviceMTL/EnsureWindowMTL/FFT/ToHost in place of
     ToDevice/EnsureWindowCL/FFT/ToHost. ProcessEpoch picks a backend once,
     lazily, on the first epoch, preferring Metal, then OpenCL, then CPU -
     in practice at most one of HAVE_METAL/HAVE_OPENCL is ever defined on a
     given machine today (Metal is Darwin-only, OpenCL detection is
     deliberately left Windows-only - see newvmconfigure.lpr), so this
     ordering is mostly future-proofing rather than a live choice.

     CPU FALLBACK: if neither GPU backend is available at all (both
     HAVE_METAL and HAVE_OPENCL undefined - see newVMConfig.inc) or
     whichever backend IS compiled in doesn't actually initialise on this
     machine (MetalReady/OpenCLReady = False, checked once, lazily, on the
     first epoch), every epoch instead goes through newVMComplexSingle.pas's
     existing PowerSpectrum(TVMobjC): TVMobjS - the same Hamming-window+
     FFT+|X|^2 math, just CPU-side - so this component still works, just
     without the GPU offload, on a machine with no usable GPU backend.
     UsingGPU reports whether GPU offload is active at all, for
     diagnostics; GPUStatusMessage's own text distinguishes which backend
     (or lack thereof) is actually in play.

     PASS-THROUGH PROPERTIES: every display-relevant TVMPlotSpectrum/
     TVMPlotWaterfall property is also published here, forwarding straight
     to the real control (see uVMPlotSpectrum.pas/uVMPlotWaterfall.pas
     themselves for what each one actually does) - so both plots'
     appearance can be tuned from this component's own Object Inspector
     entry at design time, without needing to reach into SpectrumPlot/
     WaterfallPlot (still exposed, public, as an escape hatch for anything
     not forwarded here). Properties whose name and meaning are identical
     on both controls AND which uSDRMain.pas already always sets to the
     same value on both (ShowAxes, UseFrequencyAxis, XAxisMin, XAxisMax,
     XAxisTitle) are forwarded unprefixed, writing both controls together;
     everything else is prefixed Spectrum*/Waterfall* to stay unambiguous,
     since the two controls' values can otherwise differ (e.g. each has
     its own Title, and only TVMPlotSpectrum has YOffset/YGain/peak
     detection/averaging, only TVMPlotWaterfall has ScrollRate/
     VisibleRows).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

{$I ..\newVMConfig.inc}

uses
  Classes, SysUtils, Controls, ExtCtrls, Graphics, Math,
  newVM, newVMSingle, newVMComplexSingle,
  {$IFDEF HAVE_METAL}
  MetalAPI, newVMMetal,
  {$ENDIF}
  {$IFDEF HAVE_OPENCL}
  OpenCLAPI, newVMCL,
  {$ENDIF}
  uVMPlotSpectrum, uVMPlotWaterfall, uSDRRFSource;

const
  DefaultSDREpochSize = 8192;
  DefaultSDRUpdateIntervalMs = 30;

type
  // Which GPU backend (if any) ProcessEpoch picked on its first-epoch
  // check - see this unit's own header comment (THREE BACKENDS, NOT TWO)
  // for the Metal-then-OpenCL-then-CPU preference order this drives.
  TSDRGPUBackend = (gbCPU, gbMetal, gbOpenCL);

  { TSDRSpectrumAnalyser }
  TSDRSpectrumAnalyser = class(TPanel)
  private
    FSpectrumPlot: TVMPlotSpectrum;
    FWaterfallPlot: TVMPlotWaterfall;
    FUpdateTimer: TTimer;
    FSource: TSDRRFSource;
    FSourceCursor: TSDRStreamCursor;
    FEpochSize: Integer;
    FUseGPU, FGPUChecked: Boolean;
    FGPUBackend: TSDRGPUBackend;
    FGPUStatusMessage: string;
    FOnGPUStatusKnown: TNotifyEvent;
    FOnCursorChange: TNotifyEvent;
    {$IFDEF HAVE_METAL}
    FWindowMTL: TVMobjMTL;
    FWindowEpochSizeMTL: Integer;
    {$ENDIF}
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

    // Pass-through properties - see this unit's own header comment for
    // the unprefixed-vs-Spectrum*/Waterfall* naming rule.
    function GetShowAxes: Boolean;
    procedure SetShowAxes(AValue: Boolean);
    function GetUseFrequencyAxis: Boolean;
    procedure SetUseFrequencyAxis(AValue: Boolean);
    function GetXAxisMin: Double;
    procedure SetXAxisMin(AValue: Double);
    function GetXAxisMax: Double;
    procedure SetXAxisMax(AValue: Double);
    function GetXAxisTitle: string;
    procedure SetXAxisTitle(const AValue: string);
    function GetSpectrumTitle: string;
    procedure SetSpectrumTitle(const AValue: string);
    function GetSpectrumYAxisTitle: string;
    procedure SetSpectrumYAxisTitle(const AValue: string);
    function GetSpectrumFadeSeconds: Double;
    procedure SetSpectrumFadeSeconds(AValue: Double);
    function GetSpectrumLowColor: TColor;
    procedure SetSpectrumLowColor(AValue: TColor);
    function GetSpectrumMidColor: TColor;
    procedure SetSpectrumMidColor(AValue: TColor);
    function GetSpectrumHighColor: TColor;
    procedure SetSpectrumHighColor(AValue: TColor);
    function GetSpectrumYOffset: Double;
    procedure SetSpectrumYOffset(AValue: Double);
    function GetSpectrumYGain: Double;
    procedure SetSpectrumYGain(AValue: Double);
    function GetSpectrumShowPeakLabels: Boolean;
    procedure SetSpectrumShowPeakLabels(AValue: Boolean);
    function GetSpectrumPeakThreshold: Double;
    procedure SetSpectrumPeakThreshold(AValue: Double);
    function GetSpectrumShowAverage: Boolean;
    procedure SetSpectrumShowAverage(AValue: Boolean);
    function GetSpectrumAverageCount: Integer;
    procedure SetSpectrumAverageCount(AValue: Integer);
    function GetSpectrumCurrentYMin: Double;
    function GetSpectrumCurrentYMax: Double;
    function GetSpectrumCursorValue: Double;
    procedure SetSpectrumCursorValue(AValue: Double);
    function GetSpectrumCursorReading: Double;
    function GetSpectrumCursorBandwidth: Double;
    procedure SetSpectrumCursorBandwidth(AValue: Double);
    function GetWaterfallTitle: string;
    procedure SetWaterfallTitle(const AValue: string);
    function GetWaterfallScrollRate: Double;
    procedure SetWaterfallScrollRate(AValue: Double);
    function GetWaterfallVisibleRows: Integer;
    procedure SetWaterfallVisibleRows(AValue: Integer);
    function GetWaterfallLowColor: TColor;
    procedure SetWaterfallLowColor(AValue: TColor);
    function GetWaterfallMidColor: TColor;
    procedure SetWaterfallMidColor(AValue: TColor);
    function GetWaterfallHighColor: TColor;
    procedure SetWaterfallHighColor(AValue: TColor);
    function GetWaterfallCurrentYMin: Double;
    function GetWaterfallCurrentYMax: Double;

    procedure SpectrumCursorChanged(Sender: TObject);
    procedure UpdateTick(Sender: TObject);
    procedure ProcessEpoch(const IQ: TVMobjC);
    function ProcessEpochCPU(const IQ: TVMobjC): TVMobj;
    {$IFDEF HAVE_METAL}
    procedure EnsureWindowMTL;
    function ProcessEpochMetal(const IQ: TVMobjC): TVMobj;
    {$ENDIF}
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
    // Forwards SpectrumPlot's own OnCursorChange (uVMPlotSpectrum.pas) -
    // fires whenever SpectrumCursorValue moves (drag, arrow key, or
    // programmatic), so a host form (uSDRMain.pas) can retune a receiver's
    // local oscillator live as the cursor is dragged onto a station.
    property OnCursorChange: TNotifyEvent read FOnCursorChange write FOnCursorChange;

    // Shared - forwarded to both SpectrumPlot and WaterfallPlot together.
    property ShowAxes: Boolean read GetShowAxes write SetShowAxes;
    property UseFrequencyAxis: Boolean read GetUseFrequencyAxis write SetUseFrequencyAxis;
    property XAxisMin: Double read GetXAxisMin write SetXAxisMin;
    property XAxisMax: Double read GetXAxisMax write SetXAxisMax;
    property XAxisTitle: string read GetXAxisTitle write SetXAxisTitle;

    // SpectrumPlot-only.
    property SpectrumTitle: string read GetSpectrumTitle write SetSpectrumTitle;
    property SpectrumYAxisTitle: string read GetSpectrumYAxisTitle write SetSpectrumYAxisTitle;
    property SpectrumFadeSeconds: Double read GetSpectrumFadeSeconds write SetSpectrumFadeSeconds;
    property SpectrumLowColor: TColor read GetSpectrumLowColor write SetSpectrumLowColor;
    property SpectrumMidColor: TColor read GetSpectrumMidColor write SetSpectrumMidColor;
    property SpectrumHighColor: TColor read GetSpectrumHighColor write SetSpectrumHighColor;
    property SpectrumYOffset: Double read GetSpectrumYOffset write SetSpectrumYOffset;
    property SpectrumYGain: Double read GetSpectrumYGain write SetSpectrumYGain;
    property SpectrumShowPeakLabels: Boolean read GetSpectrumShowPeakLabels write SetSpectrumShowPeakLabels;
    property SpectrumPeakThreshold: Double read GetSpectrumPeakThreshold write SetSpectrumPeakThreshold;
    property SpectrumShowAverage: Boolean read GetSpectrumShowAverage write SetSpectrumShowAverage;
    property SpectrumAverageCount: Integer read GetSpectrumAverageCount write SetSpectrumAverageCount;
    property SpectrumCurrentYMin: Double read GetSpectrumCurrentYMin;
    property SpectrumCurrentYMax: Double read GetSpectrumCurrentYMax;
    property SpectrumCursorValue: Double read GetSpectrumCursorValue write SetSpectrumCursorValue;
    property SpectrumCursorReading: Double read GetSpectrumCursorReading;
    property SpectrumCursorBandwidth: Double read GetSpectrumCursorBandwidth write SetSpectrumCursorBandwidth;

    // WaterfallPlot-only.
    property WaterfallTitle: string read GetWaterfallTitle write SetWaterfallTitle;
    property WaterfallScrollRate: Double read GetWaterfallScrollRate write SetWaterfallScrollRate;
    property WaterfallVisibleRows: Integer read GetWaterfallVisibleRows write SetWaterfallVisibleRows;
    property WaterfallLowColor: TColor read GetWaterfallLowColor write SetWaterfallLowColor;
    property WaterfallMidColor: TColor read GetWaterfallMidColor write SetWaterfallMidColor;
    property WaterfallHighColor: TColor read GetWaterfallHighColor write SetWaterfallHighColor;
    property WaterfallCurrentYMin: Double read GetWaterfallCurrentYMin;
    property WaterfallCurrentYMax: Double read GetWaterfallCurrentYMax;
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
  FSpectrumPlot.OnCursorChange := @SpectrumCursorChanged;
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
  {$IFDEF HAVE_METAL}
  FWindowEpochSizeMTL := 0;
  {$ENDIF}
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
  if Assigned(FSource) then begin
    FSource.FreeNotification(Self);
    // Fresh independent cursor into the source's shared stream - see
    // uSDRRFSource.pas's own header comment for why every consumer needs
    // its own (TryReadEpoch used to be a single-consumer destructive
    // read, which silently corrupted both this component's own stream
    // and TFMBroadcastReceiver's the moment both were active at once).
    FSourceCursor := FSource.NewStreamCursor;
  end;
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
  if AValue and not FUpdateTimer.Enabled then begin
    FGPUChecked := False;
    // A fresh cursor for this streaming session - see
    // TFMBroadcastReceiver.BuildChain's identical comment for why.
    if Assigned(FSource) then FSourceCursor := FSource.NewStreamCursor;
  end;
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

function TSDRSpectrumAnalyser.GetShowAxes: Boolean;
begin
  Result := FSpectrumPlot.ShowAxes;
end;

procedure TSDRSpectrumAnalyser.SetShowAxes(AValue: Boolean);
begin
  FSpectrumPlot.ShowAxes := AValue;
  FWaterfallPlot.ShowAxes := AValue;
end;

function TSDRSpectrumAnalyser.GetUseFrequencyAxis: Boolean;
begin
  Result := FSpectrumPlot.UseFrequencyAxis;
end;

procedure TSDRSpectrumAnalyser.SetUseFrequencyAxis(AValue: Boolean);
begin
  FSpectrumPlot.UseFrequencyAxis := AValue;
  FWaterfallPlot.UseFrequencyAxis := AValue;
end;

function TSDRSpectrumAnalyser.GetXAxisMin: Double;
begin
  Result := FSpectrumPlot.XAxisMin;
end;

procedure TSDRSpectrumAnalyser.SetXAxisMin(AValue: Double);
begin
  FSpectrumPlot.XAxisMin := AValue;
  FWaterfallPlot.XAxisMin := AValue;
end;

function TSDRSpectrumAnalyser.GetXAxisMax: Double;
begin
  Result := FSpectrumPlot.XAxisMax;
end;

procedure TSDRSpectrumAnalyser.SetXAxisMax(AValue: Double);
begin
  FSpectrumPlot.XAxisMax := AValue;
  FWaterfallPlot.XAxisMax := AValue;
end;

function TSDRSpectrumAnalyser.GetXAxisTitle: string;
begin
  Result := FSpectrumPlot.XAxisTitle;
end;

procedure TSDRSpectrumAnalyser.SetXAxisTitle(const AValue: string);
begin
  FSpectrumPlot.XAxisTitle := AValue;
  FWaterfallPlot.XAxisTitle := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumTitle: string;
begin
  Result := FSpectrumPlot.Title;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumTitle(const AValue: string);
begin
  FSpectrumPlot.Title := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumYAxisTitle: string;
begin
  Result := FSpectrumPlot.YAxisTitle;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumYAxisTitle(const AValue: string);
begin
  FSpectrumPlot.YAxisTitle := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumFadeSeconds: Double;
begin
  Result := FSpectrumPlot.FadeSeconds;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumFadeSeconds(AValue: Double);
begin
  FSpectrumPlot.FadeSeconds := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumLowColor: TColor;
begin
  Result := FSpectrumPlot.LowColor;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumLowColor(AValue: TColor);
begin
  FSpectrumPlot.LowColor := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumMidColor: TColor;
begin
  Result := FSpectrumPlot.MidColor;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumMidColor(AValue: TColor);
begin
  FSpectrumPlot.MidColor := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumHighColor: TColor;
begin
  Result := FSpectrumPlot.HighColor;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumHighColor(AValue: TColor);
begin
  FSpectrumPlot.HighColor := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumYOffset: Double;
begin
  Result := FSpectrumPlot.YOffset;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumYOffset(AValue: Double);
begin
  FSpectrumPlot.YOffset := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumYGain: Double;
begin
  Result := FSpectrumPlot.YGain;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumYGain(AValue: Double);
begin
  FSpectrumPlot.YGain := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumShowPeakLabels: Boolean;
begin
  Result := FSpectrumPlot.ShowPeakLabels;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumShowPeakLabels(AValue: Boolean);
begin
  FSpectrumPlot.ShowPeakLabels := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumPeakThreshold: Double;
begin
  Result := FSpectrumPlot.PeakThreshold;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumPeakThreshold(AValue: Double);
begin
  FSpectrumPlot.PeakThreshold := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumShowAverage: Boolean;
begin
  Result := FSpectrumPlot.ShowAverage;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumShowAverage(AValue: Boolean);
begin
  FSpectrumPlot.ShowAverage := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumAverageCount: Integer;
begin
  Result := FSpectrumPlot.AverageCount;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumAverageCount(AValue: Integer);
begin
  FSpectrumPlot.AverageCount := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumCurrentYMin: Double;
begin
  Result := FSpectrumPlot.CurrentYMin;
end;

function TSDRSpectrumAnalyser.GetSpectrumCurrentYMax: Double;
begin
  Result := FSpectrumPlot.CurrentYMax;
end;

function TSDRSpectrumAnalyser.GetSpectrumCursorValue: Double;
begin
  Result := FSpectrumPlot.CursorValue;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumCursorValue(AValue: Double);
begin
  FSpectrumPlot.CursorValue := AValue;
end;

function TSDRSpectrumAnalyser.GetSpectrumCursorReading: Double;
begin
  Result := FSpectrumPlot.CursorReading;
end;

function TSDRSpectrumAnalyser.GetSpectrumCursorBandwidth: Double;
begin
  Result := FSpectrumPlot.CursorBandwidth;
end;

procedure TSDRSpectrumAnalyser.SetSpectrumCursorBandwidth(AValue: Double);
begin
  FSpectrumPlot.CursorBandwidth := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallTitle: string;
begin
  Result := FWaterfallPlot.Title;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallTitle(const AValue: string);
begin
  FWaterfallPlot.Title := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallScrollRate: Double;
begin
  Result := FWaterfallPlot.ScrollRate;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallScrollRate(AValue: Double);
begin
  FWaterfallPlot.ScrollRate := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallVisibleRows: Integer;
begin
  Result := FWaterfallPlot.VisibleRows;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallVisibleRows(AValue: Integer);
begin
  FWaterfallPlot.VisibleRows := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallLowColor: TColor;
begin
  Result := FWaterfallPlot.LowColor;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallLowColor(AValue: TColor);
begin
  FWaterfallPlot.LowColor := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallMidColor: TColor;
begin
  Result := FWaterfallPlot.MidColor;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallMidColor(AValue: TColor);
begin
  FWaterfallPlot.MidColor := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallHighColor: TColor;
begin
  Result := FWaterfallPlot.HighColor;
end;

procedure TSDRSpectrumAnalyser.SetWaterfallHighColor(AValue: TColor);
begin
  FWaterfallPlot.HighColor := AValue;
end;

function TSDRSpectrumAnalyser.GetWaterfallCurrentYMin: Double;
begin
  Result := FWaterfallPlot.CurrentYMin;
end;

function TSDRSpectrumAnalyser.GetWaterfallCurrentYMax: Double;
begin
  Result := FWaterfallPlot.CurrentYMax;
end;

procedure TSDRSpectrumAnalyser.SpectrumCursorChanged(Sender: TObject);
begin
  if Assigned(FOnCursorChange) then FOnCursorChange(Self);
end;

procedure TSDRSpectrumAnalyser.UpdateTick(Sender: TObject);
var
  IQ: TVMobjC;
begin
  if not Assigned(FSource) then Exit;
  if not FSource.TryReadEpoch(FEpochSize, FSourceCursor, IQ) then Exit;
  ProcessEpoch(IQ);
end;

// Picks a backend once, lazily, on the first epoch - preferring Metal,
// then OpenCL, then CPU (see this unit's own header comment, THREE
// BACKENDS, NOT TWO). At most one of HAVE_METAL/HAVE_OPENCL is ever
// defined on a given machine today, so in practice this resolves to
// "whichever GPU backend this build has, if it's actually ready, else
// CPU" - the explicit preference order only matters on a hypothetical
// future machine with both compiled in.
procedure TSDRSpectrumAnalyser.ProcessEpoch(const IQ: TVMobjC);
var
  PowerSpec: TVMobj;
begin
  if not FGPUChecked then begin
    FGPUBackend := gbCPU;
    FGPUStatusMessage := 'no GPU backend available in this build';
    {$IFDEF HAVE_METAL}
    if FGPUBackend = gbCPU then begin
      if MetalReady then begin
        FGPUBackend := gbMetal;
        FGPUStatusMessage := '';
      end else
        FGPUStatusMessage := MetalLastError;
    end;
    {$ENDIF}
    {$IFDEF HAVE_OPENCL}
    if FGPUBackend = gbCPU then begin
      if OpenCLReady then begin
        FGPUBackend := gbOpenCL;
        FGPUStatusMessage := '';
      end else
        FGPUStatusMessage := OpenCLLastError;
    end;
    {$ENDIF}
    FUseGPU := FGPUBackend <> gbCPU;
    FGPUChecked := True;
    if Assigned(FOnGPUStatusKnown) then FOnGPUStatusKnown(Self);
  end;

  case FGPUBackend of
    {$IFDEF HAVE_METAL}
    gbMetal: PowerSpec := ProcessEpochMetal(IQ);
    {$ENDIF}
    {$IFDEF HAVE_OPENCL}
    gbOpenCL: PowerSpec := ProcessEpochGPU(IQ);
    {$ENDIF}
    else PowerSpec := ProcessEpochCPU(IQ);
  end;

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

{$IFDEF HAVE_METAL}
// Metal analogue of EnsureWindowCL below - same cached-per-EpochSize
// Hamming window, uploaded once via ToDeviceMTL instead of ToDevice.
procedure TSDRSpectrumAnalyser.EnsureWindowMTL;
var
  WHost: TVMobjS;
  i: Integer;
  w: Single;
begin
  if FWindowEpochSizeMTL = FEpochSize then Exit;
  WHost := TVMobjS.Create(1, 2 * FEpochSize);
  for i := 0 to FEpochSize - 1 do begin
    w := 0.54 - 0.46 * cos(2 * Pi * i / (FEpochSize - 1));
    WHost[0, 2*i]   := w;
    WHost[0, 2*i+1] := w;
  end;
  FWindowMTL := ToDeviceMTL(WHost);
  FWindowEpochSizeMTL := FEpochSize;
end;

// Metal analogue of ProcessEpochGPU below - identical pipeline (interleave
// -> upload -> window -> FFT -> download -> fftshift+dB), ToDeviceMTL/
// TVMobjMTL/FFT/ToHost in place of ToDevice/TVMobjCL/FFT/ToHost.
function TSDRSpectrumAnalyser.ProcessEpochMetal(const IQ: TVMobjC): TVMobj;
var
  Interleaved, HostSpec: TVMobjS;
  IQMTL, Windowed, Spec: TVMobjMTL;
  i, HalfN, k, srcBin: Integer;
  re, im: Single;
begin
  EnsureWindowMTL;

  Interleaved := TVMobjS.Create(1, 2 * FEpochSize);
  for i := 0 to FEpochSize - 1 do begin
    Interleaved[0, 2*i]   := IQ[0, i].re;
    Interleaved[0, 2*i+1] := IQ[0, i].im;
  end;

  IQMTL := ToDeviceMTL(Interleaved);
  Windowed := IQMTL * FWindowMTL;
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
