unit uVMPlotSpectrum;

{*******************************************************************************

     TVMPlotSpectrum - a flat, front-on power-spectrum display: X = a real
     axis (frequency, via UseFrequencyAxis/XAxisMin/XAxisMax - same
     convention as TVMPlotStack, Graphs/uVMPlotStack.pas), Y = value (e.g.
     dB). Built for the SDR_Radio spectrum analyser as a companion to
     TVMPlotWaterfall (Graphs/uVMPlotWaterfall.pas) - this is the "front-on"
     view, that one the classic scrolling waterfall below it.

     Written the same way as every other Graphs/uVMPlot*.pas unit - a
     standalone TOpenGLControl descendant with its own Create+Parent usage,
     NOT added to the newVMGraphs design-time package (SDR_Radio creates it
     purely in code, same as it already did for TVMPlotStack, so palette
     registration isn't needed) - and deliberately re-implements rather than
     shares the boilerplate every sibling unit already duplicates
     (NiceNum/ComputeTicks/CreateTextTexture/DrawTextTexture, the
     Low/Mid/High colour-gradient math), matching this codebase's own
     established convention (see e.g. TVMPlot2D's/TVMPlot3D's own header
     comments on why they don't share this with each other either).

     Usage:
       Spec := TVMPlotSpectrum.Create(Self);
       Spec.Parent := Self;
       Spec.Align := alTop; Spec.Height := 320;
       Spec.UseFrequencyAxis := True;
       Spec.XAxisMin := 85; Spec.XAxisMax := 105;   // MHz
       Spec.AddGraph(Y);       // Y: a newVM (1,N) or (N,1) TVMobj vector

     PERSISTENCE/FADE ("latest spectrum added in the same colour scheme as
     the 3-D spectrum, fading in intensity over time"): unlike TVMPlotStack,
     where a slice's Age advances in discrete per-push steps (or optionally,
     via its own Animate toggle, continuously), every held slice's Age here
     is ALWAYS ticked forward continuously, in seconds, by an internal timer
     (~30Hz) - there is no discrete/optional mode, since continuous fade is
     this component's entire visual point. A slice's on-screen brightness is
     Max(0, 1 - Age/FadeSeconds) - a direct port of TVMPlotStack.DrawSlice's
     own Intensity multiply, just driven by elapsed seconds instead of
     Age/MaxSeries - and every slice past FadeSeconds is dropped
     (TrimStack), same contiguous-run-at-the-tail trick TVMPlotStack's own
     TrimStack uses (Age is non-decreasing with array index here too, for
     the same reason: ageing adds the same delta to every existing slice
     before a new Age=0 slice is inserted in front). Colour-by-value (the
     Low/Mid/High cubed-fraction gradient, keyed to the auto-fit
     CurrentYMin/CurrentYMax across every held slice) is ported byte-for-
     byte from TVMPlotStack.DrawSlice, just applied to a flat GL_LINE_STRIP
     instead of a filled 3D ribbon - see DrawSlice's own comment for why a
     plain overlaid line (not a ribbon down to a floor) is the right choice
     here: several overlaid *filled* ribbons at once would obscure each
     other, whereas thin overlaid lines - brightest/newest drawn last, same
     back-to-front order TVMPlotStack's own Paint uses - read cleanly as a
     phosphor-persistence trace.

     CURSOR: FCursorValue (published CursorValue) is a real X-axis value
     (whatever units XAxisMin/XAxisMax use), always kept inside
     [XAxisMin,XAxisMax] (or [0,FrontN-1] when UseFrequencyAxis is False -
     same domain XValueToFrac's own bin-index fallback uses). Read-only
     CursorReading linearly interpolates the frontmost (most recently added)
     slice's own Y at that X. Move it by dragging with the left mouse button
     anywhere in the plot area (MouseDown/MouseMove convert the click's pixel
     X straight to a data-space X, no need to precisely grab a thin line -
     the same "click anywhere to reposition" convention real spectrum
     analyser marker UIs use) or with the Left/Right arrow keys once focused
     (KeyDown, one bin of the frontmost slice's own N per press - TabStop is
     set in the constructor so a click - which already calls SetFocus - is
     enough to enable this). The cursor itself, plus a text label showing
     both CursorValue and CursorReading, is drawn on top of everything else
     every frame (DrawCursor) - the visual half of "read programmatically":
     the property pair below is for calling code, the on-screen label is for
     a human looking at the same display. OnCursorChange fires every time
     CursorValue actually moves - a drag, an arrow key, or a programmatic
     assignment alike - so calling code (SDR_Radio's uSDRMain.pas) can
     retune a receiver's own local oscillator live as the cursor is
     dragged onto a station, without needing to poll CursorValue itself.
     CursorBandwidth (see that property's own comment) draws a translucent
     shaded band around the cursor showing the tuned channel's actual
     occupied bandwidth, independent of the single-frequency cursor line.
     Besides dragging/arrow keys, the mouse wheel also nudges CursorValue
     by one CursorStep per notch (DoMouseWheel) - a finer-grained way to
     tune than a drag, without needing to click/focus the control first
     (mirroring TVMPlot3D's own wheel-to-zoom, uVMPlot3D.pas).

     BIG FREQUENCY READOUT: a second, fixed-position HUD element -
     independent of DrawCursor's own label, which follows the cursor's X
     position and would run off the visible plot area near either edge -
     shows CursorValue at a literal BigFreqDisplayHeight (50) pixel
     character height in the upper-right corner, so the currently selected
     frequency stays readable at a glance regardless of where in the
     spectrum the cursor itself currently sits. Drawn via DrawTextTextureH,
     which scales the (variable, font-metric-dependent) native texture size
     to an exact target pixel height rather than 1:1 like every other
     DrawTextTexture call in this unit - see that procedure's own comment.

     PEAK DETECTION: ShowPeakLabels/PeakThreshold/UpdatePeakLabel/
     DrawPeakMarker are a direct port of TVMPlotStack's own (confirmed
     working) multi-peak non-maximum-suppression logic, re-targeted at this
     component's flat (X,Y) data space instead of TVMPlotStack's
     (world-X,world-Y,world-Z) - carried over on request rather than dropped
     now that the cursor gives a manual way to read a frequency; the two are
     complementary, not a replacement of one by the other.

     YOFFSET/YGAIN ("zero point"/"vertical height of peaks"): implemented as
     a camera zoom/pan of the Y VIEWPORT (FYMin/FYMax, i.e. the glOrtho
     bounds), not a transform of the plotted data - an earlier version did
     the reverse (transformed the data and then auto-fit the viewport to
     that same transformed data), which is a no-op by construction: for any
     affine map applied identically to both a value and the range it's
     being fitted into, the fraction (value-min)/(max-min) is invariant of
     the map's own parameters, so the trace never visibly moved even though
     the axis tick numbers correctly updated. Keeping the plotted data,
     peak positions, and CursorReading in raw (untransformed) units and
     instead zooming/panning the viewport around them is what makes the
     transform actually visible - see RecomputeBounds and the properties'
     own comments for the full rationale.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, LCLType, Graphics, LResources,
  IntfGraphics, FPImage, ExtCtrls,
  GL, GLU, OpenGLContext,
  newVM;

type
  TVMPlotDoubleArray = array of Double;

  // One held trace's render-ready state - see this unit's own PERSISTENCE/
  // FADE comment for what Age means here (continuous seconds, unlike
  // TVMPlotStack's discrete-by-default Age).
  TVMPlotSpectrumSlice = record
    Y: array of Double;
    N: Integer;
    Age: Double;
  end;

  // Identical technique/purpose to every sibling unit's own
  // TVMPlotTextTexture - duplicated, not shared, matching this unit's own
  // header comment on why.
  TVMPlotTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  { TVMPlotSpectrum }

  TVMPlotSpectrum = class(TOpenGLControl)
  private
    FSlices: array of TVMPlotSpectrumSlice;   // index 0 = most recently added
    FFadeSeconds: Double;
    FTimer: TTimer;

    FLowColor, FMidColor, FHighColor: TColor;
    FLowR, FLowG, FLowB: Double;
    FMidR, FMidG, FMidB: Double;
    FHighR, FHighG, FHighB: Double;

    FYMin, FYMax: Double;      // Y viewport (glOrtho bounds / tick range) - raw auto-fit zoomed/panned by YOffset/YGain, see RecomputeBounds
    FFrontN: Integer;          // most-recent slice's point count
    FPlotXMin, FPlotXMax: Double;  // data-space X range actually drawn/ortho'd - see RecomputeBounds
    FYOffset, FYGain: Double;  // Y viewport zoom/pan - see RecomputeBounds

    FShowAxes: Boolean;
    FUseFreqAxis: Boolean;
    FXAxisMin, FXAxisMax: Double;
    FTitle, FXAxisTitle, FYAxisTitle: string;
    FXTicks, FYTicks: TVMPlotDoubleArray;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex: TVMPlotTextTexture;
    FXTickTex, FYTickTex: array of TVMPlotTextTexture;

    FShowPeakLabels: Boolean;
    FPeakThreshold: Double;
    FPeakCount: Integer;
    FPeakX, FPeakY: array of Double;          // data-space positions of the current peak markers
    FPeakLabelTex: array of TVMPlotTextTexture;

    FShowAverage: Boolean;
    FAverageCount: Integer;

    FCursorValue: Double;
    FCursorBandwidth: Double;
    FCursorLabelTex: TVMPlotTextTexture;
    FDragging: Boolean;
    FOnCursorChange: TNotifyEvent;
    FBigFreqTex: TVMPlotTextTexture;

    procedure SetFadeSeconds(AValue: Double);
    procedure SetLowColor(AValue: TColor);
    procedure SetMidColor(AValue: TColor);
    procedure SetHighColor(AValue: TColor);
    procedure SetShowAxes(AValue: Boolean);
    procedure SetUseFrequencyAxis(AValue: Boolean);
    procedure SetXAxisMin(AValue: Double);
    procedure SetXAxisMax(AValue: Double);
    procedure SetYOffset(AValue: Double);
    procedure SetYGain(AValue: Double);
    procedure SetShowPeakLabels(AValue: Boolean);
    procedure SetPeakThreshold(AValue: Double);
    procedure UpdatePeakLabel;
    procedure DrawPeakMarker;
    procedure SetShowAverage(AValue: Boolean);
    procedure SetAverageCount(AValue: Integer);
    procedure ComputeAverageSlice(out AvgY: TVMPlotDoubleArray; out N: Integer);
    procedure DrawAverageLine;
    procedure SetTitle(const AValue: string);
    procedure SetXAxisTitle(const AValue: string);
    procedure SetYAxisTitle(const AValue: string);
    procedure SetCursorValue(AValue: Double);
    procedure SetCursorBandwidth(AValue: Double);
    function GetCursorReading: Double;
    function CursorStep: Double;
    procedure UpdateCursorFromPixelX(PixelX: Integer);
    procedure DrawCursorBand;
    procedure TimerTick(Sender: TObject);
    procedure TrimStack;
    procedure RecomputeBounds;
    procedure DrawSlice(const Slice: TVMPlotSpectrumSlice);
    procedure DrawAxesBorder;
    procedure DrawCursor;
    function BuildDefaultDemoSlice(Phase: Double): TVMobj;
    procedure InvalidateTextures;
    procedure FreeTextTexture(var Tex: TVMPlotTextTexture);
    procedure FreeAllTextures;
    function CreateTextTexture(const S: string; FontSize: Integer;
      Bold: Boolean; TR, TG, TB: Byte): TVMPlotTextTexture;
    procedure BuildTextures;
    procedure DrawTextTexture(const Tex: TVMPlotTextTexture;
      X, Y, AngleDeg, HAlign, VAlign: Double);
    procedure DrawTextTextureH(const Tex: TVMPlotTextTexture;
      X, Y, TargetH, HAlign, VAlign: Double);
    function FormatBigFreqText: string;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddGraph(const Y: TVMobj);
    procedure ClearStack;
  published
    // How long (seconds) a trace takes to fade from full brightness to
    // black - see this unit's own PERSISTENCE/FADE header comment.
    property FadeSeconds: Double read FFadeSeconds write SetFadeSeconds;
    property LowColor: TColor read FLowColor write SetLowColor;
    property MidColor: TColor read FMidColor write SetMidColor;
    property HighColor: TColor read FHighColor write SetHighColor;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes;
    property UseFrequencyAxis: Boolean read FUseFreqAxis write SetUseFrequencyAxis;
    property XAxisMin: Double read FXAxisMin write SetXAxisMin;
    property XAxisMax: Double read FXAxisMax write SetXAxisMax;
    // Zooms/pans the Y viewport around the (always raw, untransformed)
    // plotted data - see RecomputeBounds for the exact formula. YOffset
    // ("zero point"/reference level, default 0): positive values pan the
    // viewport to show a LOWER slice of raw values, which makes the same
    // raw trace appear to shift UP on screen (and vice versa) - the trace
    // itself never moves in raw/data terms, only what window of it is
    // visible. YGain ("vertical height of peaks", default 1): values > 1
    // narrow the viewport around its own centre, so the same raw
    // peak-to-floor spread occupies a taller fraction of the plot (and
    // < 1 widens it, shrinking peaks) - matches a real spectrum analyser's
    // separate Scale/Div and Reference Level controls. Because the
    // viewport, not the data, is what changes, axis tick labels always
    // show genuine raw values for whatever's currently visible, and
    // pushing either control far enough clips part of the trace off the
    // top/bottom edge - exactly as on a real instrument.
    property YOffset: Double read FYOffset write SetYOffset;
    property YGain: Double read FYGain write SetYGain;
    property ShowPeakLabels: Boolean read FShowPeakLabels write SetShowPeakLabels;
    property PeakThreshold: Double read FPeakThreshold write SetPeakThreshold;
    // Draws an extra solid-white, unfaded line at every bin's average over
    // the AverageCount most-recently-added slices (capped to however many
    // are actually held, so it still draws - just over fewer slices - right
    // after startup or ClearStack) - smooths random per-epoch noise so real
    // peaks stand out against it. Averaged over the SAME raw values
    // everything else in this unit uses (see the YOFFSET/YGAIN header
    // comment), so it moves/scales with YOffset/YGain exactly like the
    // individual traces do.
    property ShowAverage: Boolean read FShowAverage write SetShowAverage;
    property AverageCount: Integer read FAverageCount write SetAverageCount;
    property CurrentYMin: Double read FYMin;
    property CurrentYMax: Double read FYMax;
    // See this unit's own CURSOR header comment.
    property CursorValue: Double read FCursorValue write SetCursorValue;
    property CursorReading: Double read GetCursorReading;
    // Width (in X-axis data units - e.g. MHz when UseFrequencyAxis) of a
    // translucent dark-blue band drawn centred on CursorValue, spanning
    // the full Y range - a "this is roughly how much spectrum the tuned
    // channel actually occupies" indicator (e.g. SDR_Radio sets this to
    // broadcast FM's own 200kHz channel bandwidth), independent of the
    // thin single-frequency cursor line itself. 0 (default) draws no
    // band at all, so existing standalone usage is unaffected.
    property CursorBandwidth: Double read FCursorBandwidth write SetCursorBandwidth;
    // Fires whenever CursorValue actually moves - see this unit's own
    // CURSOR/BIG FREQUENCY READOUT header comments.
    property OnCursorChange: TNotifyEvent read FOnCursorChange write FOnCursorChange;
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
    property YAxisTitle: string read FYAxisTitle write SetYAxisTitle;
  end;

procedure Register;

implementation

const
  // Fixed pixel margins around the data-space plot rectangle - same
  // technique/values as TVMPlot2D.Paint (uVMPlot2D.pas).
  TopMargin = 34;
  BottomMargin = 55;
  LeftMargin = 65;
  RightMargin = 18;

  DefaultFadeSeconds = 3.0;
  TimerIntervalMs = 33;   // ~30 Hz

  MaxPeakLabels = 10;
  MinPeakSeparationFrac = 0.01;
  MinPeakSeparationBins = 4;
  NoPeakThreshold = -1.0E300;

  DefaultAverageCount = 10;

  // Literal pixel character height of the big frequency HUD readout -
  // see this unit's own BIG FREQUENCY READOUT header comment.
  BigFreqDisplayHeight = 50;
  BigFreqMargin = 8;

function NiceNum(x: Double): Double;
var
  e: Integer;
  f, nf: Double;
begin
  if x <= 0 then begin result := 1; Exit; end;
  e := Floor(Log10(x));
  f := x / Power(10, e);
  if f < 1.5 then nf := 1
  else if f < 3 then nf := 2
  else if f < 7 then nf := 5
  else nf := 10;
  result := nf * Power(10, e);
end;

function ComputeTicks(lo, hi: Double; TargetCount: Integer): TVMPlotDoubleArray;
var
  step, first, v: Double;
  n: Integer;
begin
  step := NiceNum((hi - lo) / Max(TargetCount - 1, 1));
  first := Ceil(lo / step) * step;
  n := 0;
  SetLength(result, 0);
  v := first;
  while v <= hi + step * 1e-9 do begin
    SetLength(result, n + 1);
    result[n] := v;
    Inc(n);
    v := v + step;
  end;
end;

function FormatTick(v: Double): string;
begin
  result := FloatToStrF(v, ffGeneral, 4, 0);
end;

{ TVMPlotSpectrum }

constructor TVMPlotSpectrum.Create(TheOwner: TComponent);
var
  k: Integer;
begin
  inherited Create(TheOwner);
  Options := Options + [ocoRenderAtDesignTime];
  TabStop := True;   // needed for KeyDown (Left/Right cursor movement) to fire once clicked

  FFadeSeconds := DefaultFadeSeconds;
  SetLowColor(RGBToColor(0, 0, 139));
  SetMidColor(RGBToColor(224, 176, 255));
  SetHighColor(RGBToColor(255, 0, 0));
  FShowAxes := True;
  FUseFreqAxis := False;
  FXAxisMin := 0;
  FXAxisMax := 1;
  FShowPeakLabels := False;
  FPeakThreshold := NoPeakThreshold;
  FPeakCount := 0;
  FShowAverage := True;
  FAverageCount := DefaultAverageCount;
  FCursorValue := 0.5;
  FCursorBandwidth := 0;
  FYOffset := 0;
  FYGain := 1;
  FTexturesBuilt := False;
  RecomputeBounds;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TimerIntervalMs;
  FTimer.Enabled := True;   // always-on continuous fade - see this unit's PERSISTENCE/FADE comment
  FTimer.OnTimer := @TimerTick;

  Title := 'Spectrum';
  XAxisTitle := 'Frequency';
  YAxisTitle := 'Value';
  for k := 0 to 3 do
    AddGraph(BuildDefaultDemoSlice(k * 0.7));
end;

destructor TVMPlotSpectrum.Destroy;
begin
  if HandleAllocated and MakeCurrent then FreeAllTextures;
  inherited Destroy;
end;

procedure TVMPlotSpectrum.SetFadeSeconds(AValue: Double);
const
  s = 'TVMPlotSpectrum.SetFadeSeconds : ';
begin
  assert(AValue > 0, s + 'FadeSeconds must be positive');
  FFadeSeconds := AValue;
end;

procedure TVMPlotSpectrum.SetLowColor(AValue: TColor);
var
  Clr: TColor;
begin
  FLowColor := AValue;
  Clr := ColorToRGB(AValue);
  FLowR := (Clr and $FF) / 255;
  FLowG := ((Clr shr 8) and $FF) / 255;
  FLowB := ((Clr shr 16) and $FF) / 255;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetMidColor(AValue: TColor);
var
  Clr: TColor;
begin
  FMidColor := AValue;
  Clr := ColorToRGB(AValue);
  FMidR := (Clr and $FF) / 255;
  FMidG := ((Clr shr 8) and $FF) / 255;
  FMidB := ((Clr shr 16) and $FF) / 255;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetHighColor(AValue: TColor);
var
  Clr: TColor;
begin
  FHighColor := AValue;
  Clr := ColorToRGB(AValue);
  FHighR := (Clr and $FF) / 255;
  FHighG := ((Clr shr 8) and $FF) / 255;
  FHighB := ((Clr shr 16) and $FF) / 255;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetShowAxes(AValue: Boolean);
begin
  if FShowAxes = AValue then Exit;
  FShowAxes := AValue;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetUseFrequencyAxis(AValue: Boolean);
begin
  if FUseFreqAxis = AValue then Exit;
  FUseFreqAxis := AValue;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetXAxisMin(AValue: Double);
begin
  if FXAxisMin = AValue then Exit;
  FXAxisMin := AValue;
  if FUseFreqAxis then begin
    RecomputeBounds;
    InvalidateTextures;
    Invalidate;
  end;
end;

procedure TVMPlotSpectrum.SetXAxisMax(AValue: Double);
begin
  if FXAxisMax = AValue then Exit;
  FXAxisMax := AValue;
  if FUseFreqAxis then begin
    RecomputeBounds;
    InvalidateTextures;
    Invalidate;
  end;
end;

procedure TVMPlotSpectrum.SetYOffset(AValue: Double);
begin
  if FYOffset = AValue then Exit;
  FYOffset := AValue;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetYGain(AValue: Double);
begin
  if FYGain = AValue then Exit;
  FYGain := AValue;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetShowPeakLabels(AValue: Boolean);
begin
  if FShowPeakLabels = AValue then Exit;
  FShowPeakLabels := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetPeakThreshold(AValue: Double);
begin
  if FPeakThreshold = AValue then Exit;
  FPeakThreshold := AValue;
  if FShowPeakLabels then begin
    InvalidateTextures;
    Invalidate;
  end;
end;

procedure TVMPlotSpectrum.SetShowAverage(AValue: Boolean);
begin
  if FShowAverage = AValue then Exit;
  FShowAverage := AValue;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetAverageCount(AValue: Integer);
const
  s = 'TVMPlotSpectrum.SetAverageCount : ';
begin
  assert(AValue > 0, s + 'AverageCount must be positive');
  if FAverageCount = AValue then Exit;
  FAverageCount := AValue;
  Invalidate;
end;

// Direct port of TVMPlotStack.UpdatePeakLabel (uVMPlotStack.pas) onto this
// component's flat (X,Y) data space - see that function's own comment for
// the full non-maximum-suppression rationale, unchanged here. FPeakX/FPeakY
// replace its FPeakWX/FPeakWY/FPeakWZ (no Z/depth in a flat view).
//
// Runs against the SAME averaged array ComputeAverageSlice/DrawAverageLine
// use (over AverageCount slices), not the single noisy frontmost slice - a
// per-epoch random noise spike is far less likely to look like a local
// maximum once smoothed over several epochs, so this cuts false peaks
// without needing a change to the threshold/separation logic itself. This
// runs independently of whether the white average line is actually shown
// (FShowAverage only gates DrawAverageLine's own rendering).
procedure TVMPlotSpectrum.UpdatePeakLabel;
const
  PeakR = 255; PeakG = 255; PeakB = 120;
var
  AvgY: TVMPlotDoubleArray;
  N: Integer;
  CandIdx: array of Integer;
  CandVal: array of Double;
  NCand, MinSep, i, j, k: Integer;
  denom, TmpVal: Double;
  TmpIdx: Integer;
  Accepted: array of Integer;
  TooClose: Boolean;
begin
  FPeakCount := 0;
  if (not FShowPeakLabels) or (Length(FSlices) = 0) then Exit;

  ComputeAverageSlice(AvgY, N);
  if N = 0 then Exit;

  SetLength(CandIdx, N);
  SetLength(CandVal, N);
  NCand := 0;
  for j := 0 to N - 1 do begin
    // Data stays in raw units throughout (see this unit's own YOFFSET/YGAIN
    // header comment) - PeakThreshold is likewise raw, since it's derived
    // from CurrentYMin/CurrentYMax, which are now the raw-space viewport.
    if AvgY[j] < FPeakThreshold then Continue;
    if (j > 0) and (AvgY[j - 1] > AvgY[j]) then Continue;
    if (j < N - 1) and (AvgY[j + 1] > AvgY[j]) then Continue;
    CandIdx[NCand] := j;
    CandVal[NCand] := AvgY[j];
    Inc(NCand);
  end;

  for i := 1 to NCand - 1 do begin
    j := i;
    while (j > 0) and (CandVal[j] > CandVal[j - 1]) do begin
      TmpVal := CandVal[j]; CandVal[j] := CandVal[j - 1]; CandVal[j - 1] := TmpVal;
      TmpIdx := CandIdx[j]; CandIdx[j] := CandIdx[j - 1]; CandIdx[j - 1] := TmpIdx;
      Dec(j);
    end;
  end;

  MinSep := Max(Round(N * MinPeakSeparationFrac), MinPeakSeparationBins);
  if N > 1 then denom := N - 1 else denom := 1;
  SetLength(Accepted, 0);
  SetLength(FPeakX, MaxPeakLabels);
  SetLength(FPeakY, MaxPeakLabels);
  SetLength(FPeakLabelTex, MaxPeakLabels);

  for i := 0 to NCand - 1 do begin
    if FPeakCount >= MaxPeakLabels then Break;

    TooClose := False;
    for k := 0 to High(Accepted) do
      if Abs(CandIdx[i] - Accepted[k]) < MinSep then begin
        TooClose := True;
        Break;
      end;
    if TooClose then Continue;

    SetLength(Accepted, Length(Accepted) + 1);
    Accepted[High(Accepted)] := CandIdx[i];

    FPeakX[FPeakCount] := FPlotXMin + (CandIdx[i] / denom) * (FPlotXMax - FPlotXMin);
    FPeakY[FPeakCount] := CandVal[i];

    FPeakLabelTex[FPeakCount] := CreateTextTexture(FormatTick(FPeakX[FPeakCount]) + '  ' + FormatTick(FPeakY[FPeakCount]),
      10, True, PeakR, PeakG, PeakB);
    Inc(FPeakCount);
  end;
end;

// Small marker points at each accepted peak, drawn in the data-space pass
// (Paint already has the data-space glOrtho active when this is called).
procedure TVMPlotSpectrum.DrawPeakMarker;
var
  i: Integer;
begin
  if FPeakCount = 0 then Exit;
  glPointSize(7);
  glColor3f(1, 1, 1);
  glBegin(GL_POINTS);
    for i := 0 to FPeakCount - 1 do
      glVertex2d(FPeakX[i], FPeakY[i]);
  glEnd;
end;

procedure TVMPlotSpectrum.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetXAxisTitle(const AValue: string);
begin
  if FXAxisTitle = AValue then Exit;
  FXAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetYAxisTitle(const AValue: string);
begin
  if FYAxisTitle = AValue then Exit;
  FYAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.SetCursorValue(AValue: Double);
var
  OldValue: Double;
begin
  OldValue := FCursorValue;
  FCursorValue := EnsureRange(AValue, Min(FPlotXMin, FPlotXMax), Max(FPlotXMin, FPlotXMax));
  InvalidateTextures;
  Invalidate;
  // Only fires on an actual change - a drag generates one MouseMove (and
  // so one SetCursorValue call) per pixel, most of which land on the same
  // already-clamped value; firing OnCursorChange unconditionally would
  // mean SDR_Radio's uSDRMain.pas retunes FReceiver's mixer (and rewrites
  // ListenFreqEdit.Value) every such call for no actual change - harmless
  // but wasteful, so this guards it the same way every other setter in
  // this unit already guards its own Invalidate.
  if (FCursorValue <> OldValue) and Assigned(FOnCursorChange) then FOnCursorChange(Self);
end;

procedure TVMPlotSpectrum.SetCursorBandwidth(AValue: Double);
begin
  if FCursorBandwidth = AValue then Exit;
  FCursorBandwidth := AValue;
  Invalidate;
end;

// Shared step size for both the Left/Right arrow-key nudge (KeyDown) and
// mouse-wheel fine-tuning (DoMouseWheel) - one bin of the frontmost
// slice's own N, so wheel/arrow-key tuning granularity always matches the
// actual frequency resolution of whatever's currently displayed (e.g.
// SDR_Radio: capture bandwidth / EpochSize) rather than an arbitrary
// fixed step that would be too coarse or too fine depending on the
// current capture/epoch settings.
function TVMPlotSpectrum.CursorStep: Double;
begin
  if (Length(FSlices) > 0) and (FSlices[0].N > 1) then
    Result := (FPlotXMax - FPlotXMin) / (FSlices[0].N - 1)
  else
    Result := (FPlotXMax - FPlotXMin) * 0.01;
end;

// Linear interpolation of the frontmost (most recently added) slice's own
// Y at CursorValue - the "what's the reading at this frequency" half of
// this unit's own CURSOR feature. 0 if there's no data yet.
function TVMPlotSpectrum.GetCursorReading: Double;
var
  Slice: TVMPlotSpectrumSlice;
  frac, idxF, t: Double;
  i0, i1: Integer;
begin
  if Length(FSlices) = 0 then begin Result := 0; Exit; end;
  Slice := FSlices[0];
  if Slice.N = 0 then begin Result := 0; Exit; end;
  if Slice.N = 1 then begin Result := Slice.Y[0]; Exit; end;

  if FPlotXMax - FPlotXMin <> 0 then
    frac := (FCursorValue - FPlotXMin) / (FPlotXMax - FPlotXMin)
  else
    frac := 0;
  frac := EnsureRange(frac, 0, 1);
  idxF := frac * (Slice.N - 1);
  i0 := Floor(idxF);
  i1 := Min(i0 + 1, Slice.N - 1);
  t := idxF - i0;
  Result := Slice.Y[i0] * (1 - t) + Slice.Y[i1] * t;
end;

procedure TVMPlotSpectrum.UpdateCursorFromPixelX(PixelX: Integer);
var
  PlotW: Integer;
  frac: Double;
begin
  PlotW := Max(Width - LeftMargin - RightMargin, 1);
  frac := (PixelX - LeftMargin) / PlotW;
  SetCursorValue(FPlotXMin + EnsureRange(frac, 0, 1) * (FPlotXMax - FPlotXMin));
end;

// Advances every held slice's Age by (timer interval in seconds), always -
// see this unit's own PERSISTENCE/FADE header comment for why there is no
// optional/discrete mode here, unlike TVMPlotStack's Animate.
procedure TVMPlotSpectrum.TimerTick(Sender: TObject);
var
  i: Integer;
  dAge: Double;
begin
  if Length(FSlices) = 0 then Exit;
  dAge := FTimer.Interval / 1000.0;
  for i := 0 to High(FSlices) do
    FSlices[i].Age := FSlices[i].Age + dAge;
  TrimStack;
  Invalidate;
end;

// Drops every slice whose Age has reached FadeSeconds - same contiguous-
// run-at-the-tail trick as TVMPlotStack.TrimStack (uVMPlotStack.pas), for
// the same reason (Age is non-decreasing with array index here too).
procedure TVMPlotSpectrum.TrimStack;
var
  i, cut: Integer;
begin
  cut := Length(FSlices);
  for i := 0 to High(FSlices) do
    if FSlices[i].Age >= FFadeSeconds then begin
      cut := i;
      Break;
    end;
  if cut < Length(FSlices) then SetLength(FSlices, cut);
end;

// Recomputes the auto-fit value range (FYMin/FYMax across every held
// slice), FPlotXMin/FPlotXMax (the data-space X domain actually drawn/
// ortho'd - XAxisMin..XAxisMax when UseFrequencyAxis, else 0..FrontN-1,
// the bin-index fallback), and the resulting tick arrays.
procedure TVMPlotSpectrum.RecomputeBounds;
var
  i, j: Integer;
  RawMin, RawMax, Center, HalfSpan, Gain: Double;
begin
  if Length(FSlices) = 0 then begin
    RawMin := -1;
    RawMax := 1;
    FFrontN := 0;
  end else begin
    RawMin := FSlices[0].Y[0];
    RawMax := FSlices[0].Y[0];
    for i := 0 to High(FSlices) do
      for j := 0 to FSlices[i].N - 1 do begin
        if FSlices[i].Y[j] < RawMin then RawMin := FSlices[i].Y[j];
        if FSlices[i].Y[j] > RawMax then RawMax := FSlices[i].Y[j];
      end;
    FFrontN := FSlices[0].N;
  end;
  if RawMax - RawMin < 1e-9 then begin
    RawMin := RawMin - 1;
    RawMax := RawMax + 1;
  end;
  // Zoom/pan the viewport around the raw auto-fit range - see this unit's
  // own YOFFSET/YGAIN header comment for why the data itself stays raw and
  // only this window moves/scales. Gain guarded away from 0/negative since
  // it divides the span; the UI's own trackbar range already keeps it
  // positive, this is just a defensive floor.
  Center := (RawMin + RawMax) / 2;
  HalfSpan := (RawMax - RawMin) / 2;
  Gain := FYGain;
  if Gain < 0.01 then Gain := 0.01;
  HalfSpan := HalfSpan / Gain;
  FYMin := Center - HalfSpan - FYOffset;
  FYMax := Center + HalfSpan - FYOffset;

  if FUseFreqAxis then begin
    FPlotXMin := FXAxisMin;
    FPlotXMax := FXAxisMax;
  end else begin
    FPlotXMin := 0;
    if FFrontN > 1 then FPlotXMax := FFrontN - 1 else FPlotXMax := 1;
  end;

  FYTicks := ComputeTicks(FYMin, FYMax, 5);
  FXTicks := ComputeTicks(FPlotXMin, FPlotXMax, 6);

  FCursorValue := EnsureRange(FCursorValue, Min(FPlotXMin, FPlotXMax), Max(FPlotXMin, FPlotXMax));
end;

procedure TVMPlotSpectrum.AddGraph(const Y: TVMobj);
const
  s = 'TVMPlotSpectrum.AddGraph : ';
var
  NewSlice: TVMPlotSpectrumSlice;
  i, n: Integer;
begin
  assert((Y.Rows = 1) or (Y.Cols = 1), s + 'Y must be a row or column vector');
  n := Y.Rows * Y.Cols;
  SetLength(NewSlice.Y, n);
  if Y.Rows = 1 then
    for i := 0 to n - 1 do NewSlice.Y[i] := Y[0, i]
  else
    for i := 0 to n - 1 do NewSlice.Y[i] := Y[i, 0];
  NewSlice.N := n;
  NewSlice.Age := 0;

  SetLength(FSlices, Length(FSlices) + 1);
  for i := High(FSlices) downto 1 do
    FSlices[i] := FSlices[i - 1];
  FSlices[0] := NewSlice;

  TrimStack;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotSpectrum.ClearStack;
begin
  SetLength(FSlices, 0);
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

function TVMPlotSpectrum.BuildDefaultDemoSlice(Phase: Double): TVMobj;
const
  N = 200;
var
  M: TVMobj;
  i: Integer;
  x: Double;
begin
  M := TVMobj.Create(1, N);
  for i := 0 to N - 1 do begin
    x := i / (N - 1) * 4 * Pi;
    M[0, i] := Sin(x + Phase) * Exp(-0.15 * x);
  end;
  result := M;
end;

// Direct port of TVMPlotStack.DrawSlice's colour-gradient math
// (uVMPlotStack.pas - see that function's own comment for the full "cubed
// fraction, two-stop piecewise blend" rationale, unchanged here), applied
// to a flat GL_LINE_STRIP instead of a filled 3D ribbon - see this unit's
// own PERSISTENCE/FADE header comment for why a plain overlaid line is the
// right choice for several traces shown at once. Skips slices that have
// already faded fully to black.
procedure TVMPlotSpectrum.DrawSlice(const Slice: TVMPlotSpectrumSlice);
var
  j: Integer;
  wx, intensity, denom, frac, yRange, t: Double;
  VR, VG, VB: array of Double;
begin
  intensity := Max(0, 1 - Slice.Age / FFadeSeconds);
  if intensity <= 0 then Exit;
  if Slice.N > 1 then denom := Slice.N - 1 else denom := 1;
  yRange := FYMax - FYMin;

  SetLength(VR, Slice.N);
  SetLength(VG, Slice.N);
  SetLength(VB, Slice.N);
  for j := 0 to Slice.N - 1 do begin
    if yRange > 0 then frac := (Slice.Y[j] - FYMin) / yRange else frac := 0;
    frac := EnsureRange(frac, 0, 1);
    frac := frac * frac * frac;
    if frac <= 0.5 then begin
      t := frac / 0.5;
      VR[j] := (FLowR + (FMidR - FLowR) * t) * intensity;
      VG[j] := (FLowG + (FMidG - FLowG) * t) * intensity;
      VB[j] := (FLowB + (FMidB - FLowB) * t) * intensity;
    end else begin
      t := (frac - 0.5) / 0.5;
      VR[j] := (FMidR + (FHighR - FMidR) * t) * intensity;
      VG[j] := (FMidG + (FHighG - FMidG) * t) * intensity;
      VB[j] := (FMidB + (FHighB - FMidB) * t) * intensity;
    end;
  end;

  glLineWidth(1.5);
  glBegin(GL_LINE_STRIP);
    for j := 0 to Slice.N - 1 do begin
      wx := FPlotXMin + (j / denom) * (FPlotXMax - FPlotXMin);
      glColor3d(VR[j], VG[j], VB[j]);
      glVertex2d(wx, Slice.Y[j]);
    end;
  glEnd;
end;

// Computes each bin's mean over the AverageCount most-recently-added
// slices, shared by DrawAverageLine and UpdatePeakLabel (so peak detection
// sees exactly the same smoothed data the white average line shows). Only
// averages slices whose bin count matches the frontmost slice's (guards
// against a stray mismatched N right after an epoch-size change elsewhere
// in the held history); if fewer than AverageCount matching slices are
// held yet (e.g. just after startup/ClearStack), it simply averages over
// however many are actually available. N is returned as 0 (AvgY empty) if
// there's no data to average at all.
procedure TVMPlotSpectrum.ComputeAverageSlice(out AvgY: TVMPlotDoubleArray; out N: Integer);
var
  i, j, used: Integer;
begin
  N := 0;
  SetLength(AvgY, 0);
  if Length(FSlices) = 0 then Exit;
  N := FSlices[0].N;
  if N = 0 then Exit;

  SetLength(AvgY, N);
  for j := 0 to N - 1 do AvgY[j] := 0;
  used := 0;
  for i := 0 to High(FSlices) do begin
    if used >= FAverageCount then Break;
    if FSlices[i].N <> N then Continue;
    for j := 0 to N - 1 do AvgY[j] := AvgY[j] + FSlices[i].Y[j];
    Inc(used);
  end;
  if used = 0 then begin N := 0; Exit; end;
  for j := 0 to N - 1 do AvgY[j] := AvgY[j] / used;
end;

// Solid white, unfaded line at ComputeAverageSlice's own result - drawn
// after every individual DrawSlice call so it sits on top of the noisier
// per-epoch traces, enhancing real peaks against random noise.
procedure TVMPlotSpectrum.DrawAverageLine;
var
  AvgY: TVMPlotDoubleArray;
  N, j, denom: Integer;
  wx: Double;
begin
  if not FShowAverage then Exit;
  ComputeAverageSlice(AvgY, N);
  if N = 0 then Exit;

  if N > 1 then denom := N - 1 else denom := 1;
  glLineWidth(2.0);
  glColor3d(1, 1, 1);
  glBegin(GL_LINE_STRIP);
    for j := 0 to N - 1 do begin
      wx := FPlotXMin + (j / denom) * (FPlotXMax - FPlotXMin);
      glVertex2d(wx, AvgY[j]);
    end;
  glEnd;
end;

procedure TVMPlotSpectrum.DrawAxesBorder;
begin
  glColor3f(0.55, 0.55, 0.55);
  glBegin(GL_LINE_LOOP);
    glVertex2d(FPlotXMin, FYMin);
    glVertex2d(FPlotXMax, FYMin);
    glVertex2d(FPlotXMax, FYMax);
    glVertex2d(FPlotXMin, FYMax);
  glEnd;

  if (FYMin < 0) and (FYMax > 0) then begin
    glColor3f(0.35, 0.35, 0.35);
    glBegin(GL_LINES);
      glVertex2d(FPlotXMin, 0); glVertex2d(FPlotXMax, 0);
    glEnd;
  end;
end;

// Translucent dark-blue band spanning [CursorValue-CursorBandwidth/2,
// CursorValue+CursorBandwidth/2] across the full Y range - see
// CursorBandwidth's own property comment. Drawn in the data-space pass,
// before DrawCursor's own opaque line, so the thin single-frequency
// cursor still reads clearly on top of the wider band. Pass 1 disables
// GL_BLEND by default (Paint) since every other data-space draw call is
// fully opaque; this is the one exception, so it enables blending itself
// rather than requiring Paint to do it globally.
procedure TVMPlotSpectrum.DrawCursorBand;
var
  lo, hi: Double;
begin
  if FCursorBandwidth <= 0 then Exit;
  lo := FCursorValue - FCursorBandwidth / 2;
  hi := FCursorValue + FCursorBandwidth / 2;
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glColor4f(0.10, 0.16, 0.55, 0.32);
  glBegin(GL_QUADS);
    glVertex2d(lo, FYMin);
    glVertex2d(hi, FYMin);
    glVertex2d(hi, FYMax);
    glVertex2d(lo, FYMax);
  glEnd;
  glDisable(GL_BLEND);
end;

// A bright vertical line at CursorValue, spanning the full Y range - drawn
// in the data-space pass, distinct from the Low/Mid/High data gradient
// (cyan, which none of the three default gradient stops are close to).
procedure TVMPlotSpectrum.DrawCursor;
begin
  glColor3f(0, 1, 1);
  glLineWidth(1.0);
  glBegin(GL_LINES);
    glVertex2d(FCursorValue, FYMin);
    glVertex2d(FCursorValue, FYMax);
  glEnd;
end;

procedure TVMPlotSpectrum.InvalidateTextures;
begin
  FTexturesBuilt := False;
end;

procedure TVMPlotSpectrum.FreeTextTexture(var Tex: TVMPlotTextTexture);
begin
  if Tex.Built then begin
    glDeleteTextures(1, @Tex.TexID);
    Tex.Built := False;
  end;
end;

procedure TVMPlotSpectrum.FreeAllTextures;
var
  i: Integer;
begin
  FreeTextTexture(FTitleTex);
  FreeTextTexture(FXAxisTitleTex);
  FreeTextTexture(FYAxisTitleTex);
  for i := 0 to High(FXTickTex) do FreeTextTexture(FXTickTex[i]);
  for i := 0 to High(FYTickTex) do FreeTextTexture(FYTickTex[i]);
  for i := 0 to High(FPeakLabelTex) do FreeTextTexture(FPeakLabelTex[i]);
  FreeTextTexture(FCursorLabelTex);
  FreeTextTexture(FBigFreqTex);
end;

function TVMPlotSpectrum.CreateTextTexture(const S: string; FontSize: Integer;
  Bold: Boolean; TR, TG, TB: Byte): TVMPlotTextTexture;
var
  Bmp: TBitmap;
  IntfImg: TLazIntfImage;
  x, y, W, H: Integer;
  c: TFPColor;
  lum: Byte;
  TexPixels: array of Byte;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Size := FontSize;
    if Bold then Bmp.Canvas.Font.Style := [fsBold];
    W := Bmp.Canvas.TextWidth(S) + 4;
    H := Bmp.Canvas.TextHeight(S) + 4;
    if W < 1 then W := 1;
    if H < 1 then H := 1;
    Bmp.SetSize(W, H);

    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, W, H);
    Bmp.Canvas.Font.Size := FontSize;
    if Bold then Bmp.Canvas.Font.Style := [fsBold];
    Bmp.Canvas.Font.Color := clBlack;
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.TextOut(2, 2, S);

    IntfImg := Bmp.CreateIntfImage;
    try
      SetLength(TexPixels, W * H * 4);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do begin
          c := IntfImg.Colors[x, y];
          lum := (c.red shr 8 + c.green shr 8 + c.blue shr 8) div 3;
          TexPixels[(y * W + x) * 4 + 0] := TR;
          TexPixels[(y * W + x) * 4 + 1] := TG;
          TexPixels[(y * W + x) * 4 + 2] := TB;
          TexPixels[(y * W + x) * 4 + 3] := 255 - lum;
        end;
    finally
      IntfImg.Free;
    end;

    glGenTextures(1, @result.TexID);
    glBindTexture(GL_TEXTURE_2D, result.TexID);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, @TexPixels[0]);
    result.W := W;
    result.H := H;
    result.Built := True;
  finally
    Bmp.Free;
  end;
end;

procedure TVMPlotSpectrum.BuildTextures;
const
  TitleR = 255; TitleG = 220; TitleB = 40;
  LabelR = 225; LabelG = 225; LabelB = 225;
  CursorR = 0; CursorG = 255; CursorB = 255;
var
  i: Integer;
begin
  FreeAllTextures;
  FTitleTex := CreateTextTexture(FTitle, 14, True, TitleR, TitleG, TitleB);
  FXAxisTitleTex := CreateTextTexture(FXAxisTitle, 10, False, LabelR, LabelG, LabelB);
  FYAxisTitleTex := CreateTextTexture(FYAxisTitle, 10, False, LabelR, LabelG, LabelB);

  SetLength(FXTickTex, Length(FXTicks));
  for i := 0 to High(FXTicks) do
    FXTickTex[i] := CreateTextTexture(FormatTick(FXTicks[i]), 9, False, LabelR, LabelG, LabelB);

  SetLength(FYTickTex, Length(FYTicks));
  for i := 0 to High(FYTicks) do
    FYTickTex[i] := CreateTextTexture(FormatTick(FYTicks[i]), 9, False, LabelR, LabelG, LabelB);

  FCursorLabelTex := CreateTextTexture(
    FormatTick(FCursorValue) + '  ' + FormatTick(GetCursorReading),
    10, True, CursorR, CursorG, CursorB);

  // Rendered at a large native font size and then scaled to an exact
  // BigFreqDisplayHeight pixels by DrawTextTextureH - the font size here
  // just needs to be "large enough for crisp scaling", not exact.
  FBigFreqTex := CreateTextTexture(FormatBigFreqText, 32, True, CursorR, CursorG, CursorB);

  UpdatePeakLabel;
end;

procedure TVMPlotSpectrum.DrawTextTexture(const Tex: TVMPlotTextTexture;
  X, Y, AngleDeg, HAlign, VAlign: Double);
var
  x0, y0: Double;
begin
  x0 := -Tex.W * HAlign;
  y0 := -Tex.H * VAlign;
  glPushMatrix;
  glTranslated(X, Y, 0);
  if AngleDeg <> 0 then glRotated(AngleDeg, 0, 0, 1);
  glBindTexture(GL_TEXTURE_2D, Tex.TexID);
  glBegin(GL_QUADS);
    glTexCoord2f(0, 1); glVertex2d(x0, y0);
    glTexCoord2f(1, 1); glVertex2d(x0 + Tex.W, y0);
    glTexCoord2f(1, 0); glVertex2d(x0 + Tex.W, y0 + Tex.H);
    glTexCoord2f(0, 0); glVertex2d(x0, y0 + Tex.H);
  glEnd;
  glPopMatrix;
end;

// Like DrawTextTexture, but scales the texture's own (font-metric-
// dependent, not otherwise controllable to the pixel) native size to an
// exact TargetH pixel height, preserving aspect ratio - used only by the
// big frequency HUD readout (see this unit's own BIG FREQUENCY READOUT
// header comment), which needs a literal, guaranteed pixel height
// regardless of platform font rendering differences.
procedure TVMPlotSpectrum.DrawTextTextureH(const Tex: TVMPlotTextTexture;
  X, Y, TargetH, HAlign, VAlign: Double);
var
  Scale, w0, h0, x0, y0: Double;
begin
  if (not Tex.Built) or (Tex.H = 0) then Exit;
  Scale := TargetH / Tex.H;
  w0 := Tex.W * Scale;
  h0 := TargetH;
  x0 := X - w0 * HAlign;
  y0 := Y - h0 * VAlign;
  glBindTexture(GL_TEXTURE_2D, Tex.TexID);
  glBegin(GL_QUADS);
    glTexCoord2f(0, 1); glVertex2d(x0, y0);
    glTexCoord2f(1, 1); glVertex2d(x0 + w0, y0);
    glTexCoord2f(1, 0); glVertex2d(x0 + w0, y0 + h0);
    glTexCoord2f(0, 0); glVertex2d(x0, y0 + h0);
  glEnd;
end;

// The big HUD readout's own text - MHz-suffixed and 3-decimal-formatted
// to match ListenFreqEdit's own convention when this is genuinely a
// frequency axis; falls back to the same FormatTick every tick label
// already uses otherwise, since this component is also used standalone
// (Graphs/SpectrumDemo) with no frequency semantics at all.
function TVMPlotSpectrum.FormatBigFreqText: string;
begin
  if FUseFreqAxis then
    Result := FormatFloat('0.000', FCursorValue) + ' MHz'
  else
    Result := FormatTick(FCursorValue);
end;

procedure TVMPlotSpectrum.Paint;
var
  W, H, PlotLeft, PlotBottom, PlotW, PlotH, i: Integer;
  px, py: Double;
begin
  if not MakeCurrent then Exit;
  W := Width;
  H := Height;
  if (W = 0) or (H = 0) then Exit;

  if not FTexturesBuilt then begin
    BuildTextures;
    FTexturesBuilt := True;
  end;

  PlotLeft := LeftMargin;
  PlotBottom := BottomMargin;
  PlotW := Max(W - LeftMargin - RightMargin, 1);
  PlotH := Max(H - TopMargin - BottomMargin, 1);

  glClearColor(0, 0, 0, 1);
  glViewport(0, 0, W, H);
  glClear(GL_COLOR_BUFFER_BIT);
  glDisable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_LIGHTING);

  // --- pass 1: data-space plot ---
  glViewport(PlotLeft, PlotBottom, PlotW, PlotH);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(FPlotXMin, FPlotXMax, FYMin, FYMax, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  if FShowAxes then DrawAxesBorder;

  // Back-to-front: oldest (dimmest) first, newest (brightest) last, so a
  // crossing point always shows the most recent trace on top - same
  // compositing convention TVMPlotStack.Paint uses for its own back-to-
  // front slice order.
  for i := High(FSlices) downto 0 do
    DrawSlice(FSlices[i]);

  DrawAverageLine;
  DrawPeakMarker;
  DrawCursorBand;
  DrawCursor;

  // --- pass 2: pixel-space chrome ---
  glViewport(0, 0, W, H);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, W, 0, H, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 1);

  if FTitle <> '' then
    DrawTextTexture(FTitleTex, W / 2, H - TopMargin / 2, 0, 0.5, 0.5);

  if FShowAxes then begin
    if FXAxisTitle <> '' then
      DrawTextTexture(FXAxisTitleTex, PlotLeft + PlotW / 2, 12, 0, 0.5, 0);
    if FYAxisTitle <> '' then
      DrawTextTexture(FYAxisTitleTex, 14, PlotBottom + PlotH / 2, 90, 0.5, 1);

    for i := 0 to High(FXTicks) do begin
      if (FXTicks[i] < FPlotXMin) or (FXTicks[i] > FPlotXMax) then Continue;
      px := PlotLeft + (FXTicks[i] - FPlotXMin) / (FPlotXMax - FPlotXMin) * PlotW;
      DrawTextTexture(FXTickTex[i], px, PlotBottom - 8, 0, 0.5, 1);
    end;
    for i := 0 to High(FYTicks) do begin
      if (FYTicks[i] < FYMin) or (FYTicks[i] > FYMax) then Continue;
      py := PlotBottom + (FYTicks[i] - FYMin) / (FYMax - FYMin) * PlotH;
      DrawTextTexture(FYTickTex[i], PlotLeft - 8, py, 0, 1, 0.5);
    end;
  end;

  // Peak labels, anchored above their own marker point.
  for i := 0 to FPeakCount - 1 do begin
    px := PlotLeft + (FPeakX[i] - FPlotXMin) / (FPlotXMax - FPlotXMin) * PlotW;
    py := PlotBottom + (FPeakY[i] - FYMin) / (FYMax - FYMin) * PlotH;
    DrawTextTexture(FPeakLabelTex[i], px, py + 10, 0, 0.5, 0);
  end;

  // Cursor label, hanging down from just inside the plot's top edge -
  // anchored INSIDE the plot rect (VAlign=1, not above it) rather than
  // above the top margin, which would collide with the main Title label
  // sitting just above that (confirmed by screenshot - the two overlapped
  // when this was placed at PlotBottom+PlotH+4 with VAlign=0).
  px := PlotLeft + (FCursorValue - FPlotXMin) / (FPlotXMax - FPlotXMin) * PlotW;
  DrawTextTexture(FCursorLabelTex, px, PlotBottom + PlotH - 4, 0, 0.5, 1);

  // Big HUD frequency readout, fixed in the upper-right corner - see this
  // unit's own BIG FREQUENCY READOUT header comment for why this is
  // separate from the cursor label above (which tracks the cursor's own
  // X position instead of staying put).
  DrawTextTextureH(FBigFreqTex, W - BigFreqMargin, H - BigFreqMargin,
    BigFreqDisplayHeight, 1, 1);

  glDisable(GL_TEXTURE_2D);

  SwapBuffers;
end;

procedure TVMPlotSpectrum.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TVMPlotSpectrum.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then begin
    SetFocus;
    FDragging := True;
    UpdateCursorFromPixelX(X);
  end;
end;

procedure TVMPlotSpectrum.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then UpdateCursorFromPixelX(X);
end;

procedure TVMPlotSpectrum.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

// Left/Right move the cursor by one bin of the frontmost slice's own N -
// see this unit's own CURSOR header comment. Key := 0 marks the key
// handled, so it isn't also consumed as e.g. dialog/focus navigation.
procedure TVMPlotSpectrum.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  if (Key = VK_LEFT) or (Key = VK_RIGHT) then begin
    if Key = VK_LEFT then SetCursorValue(FCursorValue - CursorStep)
    else SetCursorValue(FCursorValue + CursorStep);
    Key := 0;
  end;
end;

// Fine-tunes CursorValue by one CursorStep per wheel notch (120 units in
// the LCL's own WheelDelta convention, matching TVMPlot3D.DoMouseWheel's
// same /120 usage, uVMPlot3D.pas) - fires whenever the mouse is over this
// control, regardless of focus/click state, so scrolling to fine-tune a
// station doesn't require clicking (and so dragging) first.
function TVMPlotSpectrum.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  Notches: Integer;
begin
  Notches := Round(WheelDelta / 120);
  if Notches <> 0 then SetCursorValue(FCursorValue + Notches * CursorStep);
  Result := True;
end;

procedure Register;
begin
  RegisterComponents('newVM', [TVMPlotSpectrum]);
end;

end.
