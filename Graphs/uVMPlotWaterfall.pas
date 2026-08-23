unit uVMPlotWaterfall;

{*******************************************************************************

     TVMPlotWaterfall - the classic flat 2D scrolling spectrogram: X = a
     real axis (frequency, via UseFrequencyAxis/XAxisMin/XAxisMax - same
     convention as TVMPlotStack/TVMPlotSpectrum), colour-coded intensity
     (the same Low/Mid/High gradient those two use), newest row drawn at
     the top and scrolling continuously down to the bottom at a
     controllable rate. Built as TVMPlotSpectrum's (Graphs/
     uVMPlotSpectrum.pas) companion for the SDR_Radio spectrum analyser -
     that one the "front-on" persistence view, this one the scrolling
     history below it.

     Written the same standalone-TOpenGLControl-descendant way as every
     other Graphs/uVMPlot*.pas unit, NOT added to the newVMGraphs
     design-time package (same rationale as TVMPlotSpectrum's own header
     comment), and deliberately re-implementing rather than sharing the
     NiceNum/ComputeTicks/text-texture/colour-gradient boilerplate every
     sibling unit already duplicates.

     Usage:
       WF := TVMPlotWaterfall.Create(Self);
       WF.Parent := Self;
       WF.Align := alClient;
       WF.UseFrequencyAxis := True;
       WF.XAxisMin := 85; WF.XAxisMax := 105;   // MHz
       WF.ScrollRate := 10;    // rows/second
       WF.AddGraph(Y);         // Y: a newVM (1,N) or (N,1) TVMobj vector

     SCROLLING ("scrolling down at a controllable rate"): each held row's
     Age (in ROW-HEIGHT units here, not seconds - contrast
     TVMPlotSpectrum's Age, which is seconds) is advanced continuously by
     an internal timer (~30Hz) at ScrollRate row-heights/second,
     independent of how often AddGraph is actually called - so the visible
     scroll speed stays smooth and is driven purely by ScrollRate, not by
     the data's own push rate. A row is dropped (TrimStack) once its Age
     exceeds VisibleRows (how many row-heights span the control's full
     vertical extent) - same non-decreasing-Age/contiguous-tail trick
     TVMPlotStack.TrimStack and TVMPlotSpectrum.TrimStack both already use.
     AddGraph itself just inserts a new row at Age=0 - no separate
     per-push ageing step, unlike TVMPlotStack's discrete/optional mode -
     since the timer alone is what drives motion here.

     RENDERING: each held row is one GL_QUAD_STRIP spanning every bin - a
     top-edge vertex at world Y=Age and a bottom-edge vertex at
     Y=Age+1 per bin, so adjacent rows tile with no gaps as they scroll -
     each pair of vertices coloured via the same Low/Mid/High cubed-
     fraction gradient TVMPlotStack.DrawSlice/TVMPlotSpectrum.DrawSlice
     use (keyed to the auto-fit CurrentYMin/CurrentYMax across every held
     row), letting GL_SMOOTH interpolate a continuous-looking colour image
     purely from vertex colours - no textures, consistent with every other
     data-drawing routine in Graphs/ (textures are only ever used for text
     there). Unlike TVMPlotSpectrum, rows do NOT fade/dim with Age - they
     simply scroll off the bottom edge and get dropped, which is what
     "classic waterfall" actually looks like (compare TVMPlotSpectrum's
     phosphor-persistence fade, a deliberately different effect for a
     different display).

     The Y axis here is TIME, not a plotted quantity, so - unlike every
     other Graphs/uVMPlot*.pas unit - there is no YAxisTitle/numeric Y
     ticks; ShowAxes only toggles the border and X (frequency) ticks,
     matching how real waterfall displays usually leave the time axis
     unlabelled.

     YOFFSET/YGAIN ("zero point"/"colour contrast"): a direct port of
     TVMPlotSpectrum's own YOffset/YGain (uVMPlotSpectrum.pas - see that
     unit's own header comment for the full "zoom/pan the viewport
     around the raw auto-fit range, not the data itself" rationale,
     identical here) - the only difference is what the resulting
     FYMin/FYMax range actually DRIVES: TVMPlotSpectrum uses it for both
     a numeric Y axis AND the colour gradient, this control has no
     numeric Y axis at all, so it only ever affects DrawRow's own colour
     mapping. Existing purely so a host component (uVMPlotSDRSpectrum.pas's
     TSDRSpectrumAnalyser) can drive both this control's colours and
     TVMPlotSpectrum's own Y-axis/colours from the SAME pair of values,
     keeping the two displays' colour-to-power mapping in sync rather
     than each auto-fitting independently off its own held data (which
     could otherwise legitimately disagree, e.g. right after ClearStack
     when one control has more history than the other).

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

  // One held row's render-ready state - Age is in ROW-HEIGHT units here
  // (see this unit's own SCROLLING header comment), not seconds.
  TVMPlotWaterfallRow = record
    Y: array of Double;
    N: Integer;
    Age: Double;
  end;

  TVMPlotTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  { TVMPlotWaterfall }

  TVMPlotWaterfall = class(TOpenGLControl)
  private
    FRows: array of TVMPlotWaterfallRow;   // index 0 = most recently added
    FScrollRate: Double;
    FVisibleRows: Integer;
    FTimer: TTimer;

    FLowColor, FMidColor, FHighColor: TColor;
    FLowR, FLowG, FLowB: Double;
    FMidR, FMidG, FMidB: Double;
    FHighR, FHighG, FHighB: Double;

    FYMin, FYMax: Double;      // zoomed/panned colour range - see this unit's own YOFFSET/YGAIN header comment
    FFrontN: Integer;
    FPlotXMin, FPlotXMax: Double;
    FYOffset, FYGain: Double;  // colour-range zoom/pan - see this unit's own YOFFSET/YGAIN header comment

    FShowAxes: Boolean;
    FUseFreqAxis: Boolean;
    FXAxisMin, FXAxisMax: Double;
    FTitle, FXAxisTitle: string;
    FXTicks: TVMPlotDoubleArray;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex: TVMPlotTextTexture;
    FXTickTex: array of TVMPlotTextTexture;

    procedure SetScrollRate(AValue: Double);
    procedure SetVisibleRows(AValue: Integer);
    procedure SetYOffset(AValue: Double);
    procedure SetYGain(AValue: Double);
    procedure SetLowColor(AValue: TColor);
    procedure SetMidColor(AValue: TColor);
    procedure SetHighColor(AValue: TColor);
    procedure SetShowAxes(AValue: Boolean);
    procedure SetUseFrequencyAxis(AValue: Boolean);
    procedure SetXAxisMin(AValue: Double);
    procedure SetXAxisMax(AValue: Double);
    procedure SetTitle(const AValue: string);
    procedure SetXAxisTitle(const AValue: string);
    procedure TimerTick(Sender: TObject);
    procedure TrimStack;
    procedure RecomputeBounds;
    procedure DrawRow(const Row: TVMPlotWaterfallRow);
    function BuildDefaultDemoRow(Shift: Integer): TVMobj;
    procedure InvalidateTextures;
    procedure FreeTextTexture(var Tex: TVMPlotTextTexture);
    procedure FreeAllTextures;
    function CreateTextTexture(const S: string; FontSize: Integer;
      Bold: Boolean; TR, TG, TB: Byte): TVMPlotTextTexture;
    procedure BuildTextures;
    procedure DrawTextTexture(const Tex: TVMPlotTextTexture;
      X, Y, AngleDeg, HAlign, VAlign: Double);
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddGraph(const Y: TVMobj);
    procedure ClearStack;
  published
    // Row-heights/second the display continuously scrolls at, independent
    // of how often AddGraph is called - see this unit's own SCROLLING
    // header comment. 0 pauses the scroll.
    property ScrollRate: Double read FScrollRate write SetScrollRate;
    // How many row-heights span the control's full vertical extent -
    // together with ScrollRate this sets the display's effective time
    // span (VisibleRows/ScrollRate seconds).
    property VisibleRows: Integer read FVisibleRows write SetVisibleRows;
    // Zooms/pans the colour-mapping range around the (always raw,
    // untransformed) held data - see this unit's own YOFFSET/YGAIN
    // header comment; identical semantics to TVMPlotSpectrum's own
    // YOffset/YGain, just driving colour only here (no numeric Y axis).
    property YOffset: Double read FYOffset write SetYOffset;
    property YGain: Double read FYGain write SetYGain;
    property LowColor: TColor read FLowColor write SetLowColor;
    property MidColor: TColor read FMidColor write SetMidColor;
    property HighColor: TColor read FHighColor write SetHighColor;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes;
    property UseFrequencyAxis: Boolean read FUseFreqAxis write SetUseFrequencyAxis;
    property XAxisMin: Double read FXAxisMin write SetXAxisMin;
    property XAxisMax: Double read FXAxisMax write SetXAxisMax;
    property CurrentYMin: Double read FYMin;
    property CurrentYMax: Double read FYMax;
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
  end;

procedure Register;

implementation

const
  TopMargin = 34;
  BottomMargin = 30;
  LeftMargin = 65;
  RightMargin = 18;

  DefaultScrollRate = 10.0;
  DefaultVisibleRows = 100;
  TimerIntervalMs = 33;   // ~30 Hz

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

{ TVMPlotWaterfall }

constructor TVMPlotWaterfall.Create(TheOwner: TComponent);
var
  k, i: Integer;
begin
  inherited Create(TheOwner);
  Options := Options + [ocoRenderAtDesignTime];

  FScrollRate := DefaultScrollRate;
  FVisibleRows := DefaultVisibleRows;
  FYOffset := 0;
  FYGain := 1;
  SetLowColor(RGBToColor(0, 0, 139));
  SetMidColor(RGBToColor(224, 176, 255));
  SetHighColor(RGBToColor(255, 0, 0));
  FShowAxes := True;
  FUseFreqAxis := False;
  FXAxisMin := 0;
  FXAxisMax := 1;
  FTexturesBuilt := False;
  RecomputeBounds;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TimerIntervalMs;
  FTimer.Enabled := True;
  FTimer.OnTimer := @TimerTick;

  Title := 'Waterfall';
  XAxisTitle := 'Frequency';
  // AddGraph itself never ages existing rows (only the timer does - see
  // this unit's own SCROLLING header comment, deliberate for live data
  // where real time elapses between pushes) - but that means pushing
  // several rows back-to-back here, with no timer ticks in between, would
  // otherwise leave them all stacked at Age=0 instead of spread into a
  // history. Manually staggering them (same +1-per-existing-row step
  // TVMPlotStack.AddGraph applies unconditionally) is demo-construction-
  // only, not a change to AddGraph's own live-data behaviour.
  for k := 0 to 14 do begin
    AddGraph(BuildDefaultDemoRow(k));
    for i := 1 to High(FRows) do
      FRows[i].Age := FRows[i].Age + 1;
  end;
end;

destructor TVMPlotWaterfall.Destroy;
begin
  if HandleAllocated and MakeCurrent then FreeAllTextures;
  inherited Destroy;
end;

procedure TVMPlotWaterfall.SetScrollRate(AValue: Double);
const
  s = 'TVMPlotWaterfall.SetScrollRate : ';
begin
  assert(AValue >= 0, s + 'ScrollRate must not be negative');
  FScrollRate := AValue;
end;

procedure TVMPlotWaterfall.SetVisibleRows(AValue: Integer);
const
  s = 'TVMPlotWaterfall.SetVisibleRows : ';
begin
  assert(AValue > 0, s + 'VisibleRows must be positive');
  if FVisibleRows = AValue then Exit;
  FVisibleRows := AValue;
  TrimStack;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetYOffset(AValue: Double);
begin
  if FYOffset = AValue then Exit;
  FYOffset := AValue;
  RecomputeBounds;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetYGain(AValue: Double);
begin
  if FYGain = AValue then Exit;
  FYGain := AValue;
  RecomputeBounds;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetLowColor(AValue: TColor);
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

procedure TVMPlotWaterfall.SetMidColor(AValue: TColor);
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

procedure TVMPlotWaterfall.SetHighColor(AValue: TColor);
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

procedure TVMPlotWaterfall.SetShowAxes(AValue: Boolean);
begin
  if FShowAxes = AValue then Exit;
  FShowAxes := AValue;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetUseFrequencyAxis(AValue: Boolean);
begin
  if FUseFreqAxis = AValue then Exit;
  FUseFreqAxis := AValue;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetXAxisMin(AValue: Double);
begin
  if FXAxisMin = AValue then Exit;
  FXAxisMin := AValue;
  if FUseFreqAxis then begin
    RecomputeBounds;
    InvalidateTextures;
    Invalidate;
  end;
end;

procedure TVMPlotWaterfall.SetXAxisMax(AValue: Double);
begin
  if FXAxisMax = AValue then Exit;
  FXAxisMax := AValue;
  if FUseFreqAxis then begin
    RecomputeBounds;
    InvalidateTextures;
    Invalidate;
  end;
end;

procedure TVMPlotWaterfall.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotWaterfall.SetXAxisTitle(const AValue: string);
begin
  if FXAxisTitle = AValue then Exit;
  FXAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

// Advances every held row's Age by ScrollRate*(interval in seconds) -
// see this unit's own SCROLLING header comment.
procedure TVMPlotWaterfall.TimerTick(Sender: TObject);
var
  i: Integer;
  dAge: Double;
begin
  if Length(FRows) = 0 then Exit;
  dAge := FScrollRate * (FTimer.Interval / 1000.0);
  if dAge = 0 then Exit;
  for i := 0 to High(FRows) do
    FRows[i].Age := FRows[i].Age + dAge;
  TrimStack;
  Invalidate;
end;

// Drops every row whose Age has scrolled past VisibleRows - same
// contiguous-run-at-the-tail trick TVMPlotStack.TrimStack/
// TVMPlotSpectrum.TrimStack both already use.
procedure TVMPlotWaterfall.TrimStack;
var
  i, cut: Integer;
begin
  cut := Length(FRows);
  for i := 0 to High(FRows) do
    if FRows[i].Age >= FVisibleRows then begin
      cut := i;
      Break;
    end;
  if cut < Length(FRows) then SetLength(FRows, cut);
end;

procedure TVMPlotWaterfall.RecomputeBounds;
var
  i, j: Integer;
  RawMin, RawMax, Center, HalfSpan, Gain: Double;
begin
  if Length(FRows) = 0 then begin
    RawMin := -1;
    RawMax := 1;
    FFrontN := 0;
  end else begin
    RawMin := FRows[0].Y[0];
    RawMax := FRows[0].Y[0];
    for i := 0 to High(FRows) do
      for j := 0 to FRows[i].N - 1 do begin
        if FRows[i].Y[j] < RawMin then RawMin := FRows[i].Y[j];
        if FRows[i].Y[j] > RawMax then RawMax := FRows[i].Y[j];
      end;
    FFrontN := FRows[0].N;
  end;
  if RawMax - RawMin < 1e-9 then begin
    RawMin := RawMin - 1;
    RawMax := RawMax + 1;
  end;
  // Zoom/pan the colour-mapping range around the raw auto-fit range -
  // identical formula to TVMPlotSpectrum's own YOffset/YGain (see this
  // unit's own YOFFSET/YGAIN header comment). Gain guarded away from
  // 0/negative since it divides the span, same defensive floor
  // TVMPlotSpectrum's own RecomputeBounds uses.
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

  FXTicks := ComputeTicks(FPlotXMin, FPlotXMax, 6);
end;

procedure TVMPlotWaterfall.AddGraph(const Y: TVMobj);
const
  s = 'TVMPlotWaterfall.AddGraph : ';
var
  NewRow: TVMPlotWaterfallRow;
  i, n: Integer;
begin
  assert((Y.Rows = 1) or (Y.Cols = 1), s + 'Y must be a row or column vector');
  n := Y.Rows * Y.Cols;
  SetLength(NewRow.Y, n);
  if Y.Rows = 1 then
    for i := 0 to n - 1 do NewRow.Y[i] := Y[0, i]
  else
    for i := 0 to n - 1 do NewRow.Y[i] := Y[i, 0];
  NewRow.N := n;
  NewRow.Age := 0;

  SetLength(FRows, Length(FRows) + 1);
  for i := High(FRows) downto 1 do
    FRows[i] := FRows[i - 1];
  FRows[0] := NewRow;

  TrimStack;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotWaterfall.ClearStack;
begin
  SetLength(FRows, 0);
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

// A small Gaussian bump whose centre drifts with Shift, plus a flat noise
// floor - a moving feature makes the default demo data's scroll motion
// visually obvious (a static shape scrolling down looks the same as one
// that isn't moving at all, at a glance).
function TVMPlotWaterfall.BuildDefaultDemoRow(Shift: Integer): TVMobj;
const
  N = 120;
var
  M: TVMobj;
  i, centre: Integer;
begin
  M := TVMobj.Create(1, N);
  centre := (Shift * 5) mod N;
  for i := 0 to N - 1 do
    M[0, i] := 0.1 + 0.9 * Exp(-Sqr((i - centre) / 4.0));
  result := M;
end;

// Direct port of TVMPlotStack.DrawSlice's/TVMPlotSpectrum.DrawSlice's
// colour-gradient math (see either's own comment for the full "cubed
// fraction, two-stop piecewise blend" rationale, unchanged here), applied
// per-bin to a GL_QUAD_STRIP spanning the row's full width instead of a
// line or ribbon - see this unit's own RENDERING header comment for why a
// tiling quad-strip (not a fade) is the right choice for a classic
// waterfall.
procedure TVMPlotWaterfall.DrawRow(const Row: TVMPlotWaterfallRow);
var
  j: Integer;
  wx, denom, frac, yRange, t, topY, botY: Double;
  VR, VG, VB: array of Double;
begin
  if Row.Age >= FVisibleRows then Exit;
  if Row.N > 1 then denom := Row.N - 1 else denom := 1;
  yRange := FYMax - FYMin;
  topY := Row.Age;
  botY := Row.Age + 1;

  SetLength(VR, Row.N);
  SetLength(VG, Row.N);
  SetLength(VB, Row.N);
  for j := 0 to Row.N - 1 do begin
    if yRange > 0 then frac := (Row.Y[j] - FYMin) / yRange else frac := 0;
    frac := EnsureRange(frac, 0, 1);
    frac := frac * frac * frac;
    if frac <= 0.5 then begin
      t := frac / 0.5;
      VR[j] := FLowR + (FMidR - FLowR) * t;
      VG[j] := FLowG + (FMidG - FLowG) * t;
      VB[j] := FLowB + (FMidB - FLowB) * t;
    end else begin
      t := (frac - 0.5) / 0.5;
      VR[j] := FMidR + (FHighR - FMidR) * t;
      VG[j] := FMidG + (FHighG - FMidG) * t;
      VB[j] := FMidB + (FHighB - FMidB) * t;
    end;
  end;

  glBegin(GL_QUAD_STRIP);
    for j := 0 to Row.N - 1 do begin
      wx := FPlotXMin + (j / denom) * (FPlotXMax - FPlotXMin);
      glColor3d(VR[j], VG[j], VB[j]);
      glVertex2d(wx, topY);
      glVertex2d(wx, botY);
    end;
  glEnd;
end;

procedure TVMPlotWaterfall.InvalidateTextures;
begin
  FTexturesBuilt := False;
end;

procedure TVMPlotWaterfall.FreeTextTexture(var Tex: TVMPlotTextTexture);
begin
  if Tex.Built then begin
    glDeleteTextures(1, @Tex.TexID);
    Tex.Built := False;
  end;
end;

procedure TVMPlotWaterfall.FreeAllTextures;
var
  i: Integer;
begin
  FreeTextTexture(FTitleTex);
  FreeTextTexture(FXAxisTitleTex);
  for i := 0 to High(FXTickTex) do FreeTextTexture(FXTickTex[i]);
end;

function TVMPlotWaterfall.CreateTextTexture(const S: string; FontSize: Integer;
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

procedure TVMPlotWaterfall.BuildTextures;
const
  TitleR = 255; TitleG = 220; TitleB = 40;
  LabelR = 225; LabelG = 225; LabelB = 225;
var
  i: Integer;
begin
  FreeAllTextures;
  FTitleTex := CreateTextTexture(FTitle, 14, True, TitleR, TitleG, TitleB);
  FXAxisTitleTex := CreateTextTexture(FXAxisTitle, 10, False, LabelR, LabelG, LabelB);

  SetLength(FXTickTex, Length(FXTicks));
  for i := 0 to High(FXTicks) do
    FXTickTex[i] := CreateTextTexture(FormatTick(FXTicks[i]), 9, False, LabelR, LabelG, LabelB);
end;

procedure TVMPlotWaterfall.DrawTextTexture(const Tex: TVMPlotTextTexture;
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

procedure TVMPlotWaterfall.Paint;
var
  W, H, PlotLeft, PlotBottom, PlotW, PlotH, i: Integer;
  px: Double;
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

  // --- pass 1: data-space plot - Y (bottom,top) is (VisibleRows,0), i.e.
  // deliberately inverted from the usual bottom<top convention, so world
  // Y=0 (Age=0, newest) lands at the TOP of the viewport and Y=VisibleRows
  // (about to be dropped) at the bottom - see this unit's own SCROLLING
  // header comment. ---
  glViewport(PlotLeft, PlotBottom, PlotW, PlotH);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(FPlotXMin, FPlotXMax, FVisibleRows, 0, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  for i := High(FRows) downto 0 do
    DrawRow(FRows[i]);

  if FShowAxes then begin
    glColor3f(0.55, 0.55, 0.55);
    glBegin(GL_LINE_LOOP);
      glVertex2d(FPlotXMin, 0);
      glVertex2d(FPlotXMax, 0);
      glVertex2d(FPlotXMax, FVisibleRows);
      glVertex2d(FPlotXMin, FVisibleRows);
    glEnd;
  end;

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
    for i := 0 to High(FXTicks) do begin
      if (FXTicks[i] < FPlotXMin) or (FXTicks[i] > FPlotXMax) then Continue;
      px := PlotLeft + (FXTicks[i] - FPlotXMin) / (FPlotXMax - FPlotXMin) * PlotW;
      DrawTextTexture(FXTickTex[i], px, PlotBottom - 8, 0, 0.5, 1);
    end;
  end;

  glDisable(GL_TEXTURE_2D);

  SwapBuffers;
end;

procedure TVMPlotWaterfall.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure Register;
begin
  RegisterComponents('newVM', [TVMPlotWaterfall]);
end;

end.
