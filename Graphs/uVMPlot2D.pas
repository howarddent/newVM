unit uVMPlot2D;

{*******************************************************************************

     TVMPlot2D - a reusable, droppable-on-a-form LCL component wrapping
     TOpenGLControl (LazOpenGLContext) that plots one or more newVM (TVMobj)
     vectors, each against its own X vector (see SetData vs PlotXY below
     for the two ways to get data in). This is the rendering engine of the
     Graphs/Plot2D demo (uplot2dmain.pas), lifted out into a standalone
     component so it isn't tied to that one form/function - see that unit's
     header for the original single-series version this was generalised
     from, and the TEXT RENDERING/LAYOUT notes there, which still apply
     unchanged (every title/tick label is rendered once via the LCL font
     engine into a cached GL texture; the paint handler renders in a
     data-space pass then a pixel-space chrome pass).

     Usage:
       Plot := TVMPlot2D.Create(Self);
       Plot.Parent := Self;
       Plot.Align := alClient;
       Plot.Title := 'y = sin(x), cos(x)';
       Plot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'sin(x)');
       Plot.SetSeriesStyle(1, clBlue, 1.5, plsDash, 'cos(x)');
       Plot.SetData(X, [YSin, YCos]);   // X, YSin, YCos: TVMobj row/col vectors

       // a third series drawn as points only, no connecting line:
       Plot.SetSeriesStyle(2, clGreen, 1.0, plsNone, 'samples', pmsCircle, 8.0);

       // built up one point at a time instead - e.g. streaming data -
       // rather than from a pre-built TVMobj vector:
       Plot.PlotXY(0.1, 0.4, 3);
       Plot.PlotXY(0.2, 0.55, 3);

     SetData takes a single TVMobj for X and an open array of up to
     VMPlotMaxSeries (10) TVMobj vectors for Y - each must be the same
     length as X (row or column shaped, either is accepted, matching
     newVM's (1,N)/(N,1) vector convention) - all sharing that one X for
     this call. PlotXY(X, Y, PlotLine) is the incremental alternative:
     appends a single (X,Y) point to series PlotLine, extending it by one
     point rather than replacing its whole dataset - each series keeps its
     own X internally, so PlotXY on one PlotLine never disturbs any other
     series, whether that series came from SetData or its own PlotXY
     calls (freely mixable on the same PlotLine too - it always appends to
     whatever's already there). Both recompute the combined bounding box/
     ticks from every series' data on every call, so either is fine for
     interactive/streaming use at a reasonable point rate, but repeated
     PlotXY calls against an already-large series aren't optimised for
     very high-frequency appends. Per-series LineColor/
     LineWidth/LineStyle (solid/dash/dot/none, via GL_LINE_STIPPLE)/
     MarkerShape/MarkerSize/Name are exposed both as a published `Series`
     collection (editable per-slot at design time in the Object Inspector)
     and via the SetSeriesStyle convenience method for runtime code.
     MarkerShape (square/diamond/circle, default none) draws a marker
     glyph at every data vertex, filled with the series' LineColor and
     outlined in black, at a constant pixel size set by MarkerSize -
     independent of LineStyle, so a series can show a line, markers, or
     both together; LineStyle=plsNone with a MarkerShape set gives a
     points-only series (no connecting line), e.g. for a discrete/
     collocation series plotted alongside a smooth interpolated one - see
     DrawMarker/DrawMarkers. A series' Name, when non-empty, both labels
     it in the auto-sized legend panel drawn in the top right of the plot
     rectangle (a colour/style-matched line swatch, a marker glyph if one
     is set, and the name) and is skipped from the legend entirely when
     left blank - so the legend only appears once at least one series has
     a Name set, and never needs disabling explicitly. Title/XAxisTitle/
     YAxisTitle are plain published string properties. All other
     published behaviour (Align, Anchors, Color, mouse/key events, etc.)
     comes straight from the inherited TOpenGLControl - nothing needs
     re-declaring for those.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, LResources,
  IntfGraphics, FPImage,
  GL, OpenGLContext,
  {$IFDEF UNIX}
  GLX,
  {$ENDIF}
  newVM;

const
  VMPlotMaxSeries = 10;

type
  // plsNone suppresses the connecting line entirely (appended, not
  // inserted, so it doesn't renumber the existing three - published
  // enum properties stream by name in .lfm files, not ordinal, so this
  // wasn't required for correctness, just tidiness). Combine with
  // MarkerShape below: plsNone + a MarkerShape draws point markers with
  // no connecting line ("display as a series of points"); a real
  // LineStyle + a MarkerShape draws both, matching how most charting
  // libraries combine markers with a line.
  TVMPlotLineStyle = (plsSolid, plsDash, plsDot, plsNone);

  // Point-marker glyphs drawn at each data vertex, independent of
  // LineStyle above. pmsNone (the default) draws nothing, preserving
  // every existing series' appearance exactly - markers are strictly
  // opt-in.
  TVMPlotMarkerShape = (pmsNone, pmsSquare, pmsDiamond, pmsCircle);

  { TVMPlotSeriesStyle }

  TVMPlotSeriesStyle = class(TCollectionItem)
  private
    FLineColor: TColor;
    FLineWidth: Single;
    FLineStyle: TVMPlotLineStyle;
    FMarkerShape: TVMPlotMarkerShape;
    FMarkerSize: Single;
    FName: string;
    procedure SetLineColor(AValue: TColor);
    procedure SetLineWidth(AValue: Single);
    procedure SetLineStyle(AValue: TVMPlotLineStyle);
    procedure SetMarkerShape(AValue: TVMPlotMarkerShape);
    procedure SetMarkerSize(AValue: Single);
    procedure SetName(const AValue: string);
  public
    constructor Create(ACollection: TCollection); override;
    function GetDisplayName: string; override;
  published
    property LineColor: TColor read FLineColor write SetLineColor;
    property LineWidth: Single read FLineWidth write SetLineWidth;
    property LineStyle: TVMPlotLineStyle read FLineStyle write SetLineStyle;
    // Marker fill is always LineColor (one colour per series, not a
    // separate marker palette) with a fixed black outline - see
    // TVMPlot2D.DrawMarker. MarkerSize is in pixels, constant regardless
    // of the data-space zoom/axis scale, the same convention LineWidth
    // already uses (glLineWidth is a pixel width too).
    property MarkerShape: TVMPlotMarkerShape read FMarkerShape write SetMarkerShape;
    property MarkerSize: Single read FMarkerSize write SetMarkerSize;
    // Legend label for this series - see the DrawLegend note on TVMPlot2D.
    // Left blank (the default), this series is simply omitted from the
    // legend rather than appearing with an empty label.
    property Name: string read FName write SetName;
  end;

  { TVMPlotSeriesStyles }

  TVMPlotSeriesStyles = class(TOwnedCollection)
  private
    function GetTypedItem(Index: Integer): TVMPlotSeriesStyle;
  protected
    procedure Update(Item: TCollectionItem); override;
  public
    constructor Create(AOwner: TPersistent);
    property Items[Index: Integer]: TVMPlotSeriesStyle read GetTypedItem; default;
  end;

  // A title/axis-title/tick-label string rendered once to a GL texture -
  // see the TEXT RENDERING note in uplot2dmain.pas.
  TVMPlotTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  TVMPlotDoubleArray = array of Double;
  TVMPlotSeriesData = array of Double;

  { TVMPlot2D }

  TVMPlot2D = class(TOpenGLControl)
  private
    FXData: array[0..VMPlotMaxSeries - 1] of TVMPlotSeriesData;
    FYData: array[0..VMPlotMaxSeries - 1] of TVMPlotSeriesData;
    FSeriesCount: Integer;
    FHasData: Boolean;
    // False only for the constructor's own default-demo SetData call -
    // see PlotXY's comment for why this matters (a fresh component's
    // first real PlotXY call should replace that placeholder, not append
    // to it).
    FUserDataStarted: Boolean;
    FXMin, FXMax, FYMin, FYMax: Double;
    FXTicks, FYTicks: TVMPlotDoubleArray;
    FTitle, FXAxisTitle, FYAxisTitle: string;
    FSeriesStyles: TVMPlotSeriesStyles;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex: TVMPlotTextTexture;
    FXTickTex, FYTickTex, FLegendTex: array of TVMPlotTextTexture;
    FVSync: Boolean;
    // See TVMPlot3D's own FSwapIntervalApplied comment (uVMPlot3D.pas) -
    // same idiom, mirrored here.
    FSwapIntervalApplied: Boolean;
    procedure SetVSync(AValue: Boolean);
    procedure ApplySwapInterval;
    procedure SetTitle(const AValue: string);
    procedure SetXAxisTitle(const AValue: string);
    procedure SetYAxisTitle(const AValue: string);
    procedure SetSeriesStyles(AValue: TVMPlotSeriesStyles);
    procedure InvalidateTextures;
    procedure FreeTextTexture(var Tex: TVMPlotTextTexture);
    procedure FreeAllTextures;
    function CreateTextTexture(const S: string; FontSize: Integer;
      Bold: Boolean): TVMPlotTextTexture;
    procedure BuildTextures;
    procedure DrawTextTexture(const Tex: TVMPlotTextTexture;
      X, Y, AngleDeg, HAlign, VAlign: Double);
    procedure DrawAxes;
    procedure ApplyLineStyle(const Style: TVMPlotSeriesStyle);
    procedure DrawMarker(PX, PY: Double; Shape: TVMPlotMarkerShape;
      MarkerSize: Single; FillColor: TColor);
    procedure DrawMarkers(PlotLeft, PlotBottom, PlotW, PlotH: Integer);
    procedure DrawLegend(PlotLeft, PlotBottom, PlotW, PlotH: Integer);
    procedure RecomputeBounds;
    procedure EnsureUserDataStarted;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure SetData(const X: TVMobj; const YSeries: array of TVMobj);
    procedure SetSeriesStyle(Index: Integer; AColor: TColor;
      ALineWidth: Single; AStyle: TVMPlotLineStyle; const AName: string = '';
      AMarkerShape: TVMPlotMarkerShape = pmsNone; AMarkerSize: Single = 6.0);
    // Appends one (X,Y) point to PlotLine's own data, extending its length
    // by one - the incremental, point-at-a-time counterpart to SetData's
    // all-at-once TVMobj vectors. See the header comment and
    // RecomputeBounds' own comment for the full contract.
    procedure PlotXY(X, Y: Double; PlotLine: Integer);
  published
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
    property YAxisTitle: string read FYAxisTitle write SetYAxisTitle;
    property Series: TVMPlotSeriesStyles read FSeriesStyles write SetSeriesStyles;
    // See TVMPlot3D's own VSync property comment (uVMPlot3D.pas) for the
    // full investigation - explicitly requests (True, default) or releases
    // (False) vsync-locked SwapBuffers, rather than leaving it to whatever
    // the platform's GL driver defaults to. Mirrored here for the same
    // reason: this component's Paint also ends in an unconditional
    // SwapBuffers with no swap-interval control of its own.
    property VSync: Boolean read FVSync write SetVSync default True;
  end;

procedure Register;

implementation

{$IFDEF WINDOWS}
// See TVMPlot3D's own identical block (uVMPlot3D.pas) for the full
// rationale - duplicated rather than shared, matching this codebase's
// general per-unit-self-contained convention (e.g. the four TVMobj* units
// themselves).
type
  TWglSwapIntervalEXT = function(interval: Integer): LongBool; stdcall;
var
  WglSwapIntervalEXTProc: TWglSwapIntervalEXT = nil;
  WglSwapIntervalResolved: Boolean = False;

function wglGetProcAddress(lpszProc: PAnsiChar): Pointer; stdcall;
  external 'opengl32.dll';
{$ENDIF}

const
  s = 'TVMPlot2D : ';

  // A 10-colour, mutually-distinguishable default palette (the classic
  // "tab10" categorical set) applied to the Series collection's slots at
  // construction, so multiple series are readable out of the box even if
  // the caller never touches SetSeriesStyle/the Series property.
  DefaultPaletteR: array[0..9] of Byte = (31, 255, 44, 214, 148, 140, 227, 127, 188, 23);
  DefaultPaletteG: array[0..9] of Byte = (119, 127, 160, 39, 103, 86, 119, 127, 189, 190);
  DefaultPaletteB: array[0..9] of Byte = (180, 14, 44, 40, 189, 75, 194, 127, 34, 207);

{ TVMPlotSeriesStyle }

constructor TVMPlotSeriesStyle.Create(ACollection: TCollection);
begin
  inherited Create(ACollection);
  FLineColor := clBlack;
  FLineWidth := 2.0;
  FLineStyle := plsSolid;
  FMarkerShape := pmsNone;
  FMarkerSize := 6.0;
end;

function TVMPlotSeriesStyle.GetDisplayName: string;
begin
  result := Format('Series %d', [Index]);
end;

procedure TVMPlotSeriesStyle.SetLineColor(AValue: TColor);
begin
  if FLineColor = AValue then Exit;
  FLineColor := AValue;
  Changed(False);
end;

procedure TVMPlotSeriesStyle.SetLineWidth(AValue: Single);
begin
  if FLineWidth = AValue then Exit;
  FLineWidth := AValue;
  Changed(False);
end;

procedure TVMPlotSeriesStyle.SetLineStyle(AValue: TVMPlotLineStyle);
begin
  if FLineStyle = AValue then Exit;
  FLineStyle := AValue;
  Changed(False);
end;

procedure TVMPlotSeriesStyle.SetMarkerShape(AValue: TVMPlotMarkerShape);
begin
  if FMarkerShape = AValue then Exit;
  FMarkerShape := AValue;
  Changed(False);
end;

procedure TVMPlotSeriesStyle.SetMarkerSize(AValue: Single);
begin
  if FMarkerSize = AValue then Exit;
  FMarkerSize := AValue;
  Changed(False);
end;

procedure TVMPlotSeriesStyle.SetName(const AValue: string);
begin
  if FName = AValue then Exit;
  FName := AValue;
  Changed(False);
end;

{ TVMPlotSeriesStyles }

constructor TVMPlotSeriesStyles.Create(AOwner: TPersistent);
begin
  inherited Create(AOwner, TVMPlotSeriesStyle);
end;

function TVMPlotSeriesStyles.GetTypedItem(Index: Integer): TVMPlotSeriesStyle;
begin
  result := TVMPlotSeriesStyle(inherited GetItem(Index));
end;

procedure TVMPlotSeriesStyles.Update(Item: TCollectionItem);
begin
  inherited Update(Item);
  if (GetOwner is TVMPlot2D) then begin
    // Covers a Name edit (which needs its legend-label texture rebuilt),
    // not just Color/Width/Style edits (which don't) - cheap enough that
    // singling out Name here isn't worth the extra bookkeeping, since
    // series style edits are rare (design time, or an explicit runtime
    // SetSeriesStyle call), never a per-frame thing.
    TVMPlot2D(GetOwner).InvalidateTextures;
    TVMPlot2D(GetOwner).Invalidate;
  end;
end;

// "Nice" round tick step (1/2/5 x 10^n) closest to x - Heckbert's classic
// "Nice Numbers for Graph Labels" algorithm, simplified to the single case
// this needs (rounding the step itself, not the axis bounds). Ported
// unchanged from uplot2dmain.pas.
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

// Tick values spaced at a "nice" step, covering [lo,hi]. Ported unchanged
// from uplot2dmain.pas.
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

// Compact, human-friendly tick label. Ported unchanged from uplot2dmain.pas.
function FormatTick(v: Double): string;
begin
  result := FloatToStrF(v, ffGeneral, 4, 0);
end;

// See TVMPlot3D's identical function (uVMPlot3D.pas) for the full
// rationale and the measured BuildTextures cost that motivated it (6-99ms
// per call on one Linux/GTK2 dev machine) - same fix, mirrored here since
// this component's SetData/PlotXY unconditionally called InvalidateTextures
// on every call too, which matters just as much for PlotXY's streaming/
// point-at-a-time use as it did for TVMPlot3D's animated SetData caller.
function TicksChanged(const OldT, NewT: TVMPlotDoubleArray): Boolean;
var
  i: Integer;
begin
  if Length(OldT) <> Length(NewT) then begin Result := True; Exit; end;
  for i := 0 to High(NewT) do
    if OldT[i] <> NewT[i] then begin Result := True; Exit; end;
  Result := False;
end;

{ TVMPlot2D }

constructor TVMPlot2D.Create(TheOwner: TComponent);
var
  i: Integer;
  Item: TVMPlotSeriesStyle;
  X, YSin, YCos: TVMobj;
  t, xv, env: Double;
const
  DemoPoints = 1000;
  DemoXMin = -10.0;
  DemoXMax = 10.0;
begin
  inherited Create(TheOwner);
  // TCustomOpenGLControl (LazOpenGLContext) skips real GL rendering under
  // csDesigning unless this option is set (TCustomOpenGLControl.
  // IsOpenGLRenderAllowed, openglcontext.pas) - without it, the component
  // would build default data below but the Form Designer would still show
  // a blank/inert control, never actually painting it.
  Options := Options + [ocoRenderAtDesignTime];

  FSeriesStyles := TVMPlotSeriesStyles.Create(Self);
  for i := 0 to VMPlotMaxSeries - 1 do begin
    Item := TVMPlotSeriesStyle(FSeriesStyles.Add);
    Item.LineColor := RGBToColor(DefaultPaletteR[i], DefaultPaletteG[i], DefaultPaletteB[i]);
  end;
  FSeriesCount := 0;
  FHasData := False;
  FTexturesBuilt := False;
  FVSync := True;
  FSwapIntervalApplied := False;

  // Default to the same "exp(-0.1x^2).{sin(3x),cos(3x)}" example the
  // Graphs/Plot2D demo builds in its own FormCreate (uplot2dmain.pas), so a
  // freshly-dropped component already shows a representative plot - both in
  // the Form Designer at design time and at runtime before any real
  // SetData call - rather than a blank white rectangle. Harmless to
  // overwrite later: a caller's own SetData (as the demo's FormCreate still
  // does) simply replaces this.
  //
  // Built via a plain per-element loop and scalar Math.Sin/Cos/Exp, NOT the
  // demo's own linspace/elementwise-VML/operator-overload version (which
  // calls into MKL/IPP) - this component's package is RunAndDesignTime, so
  // this constructor also runs inside the Lazarus IDE's own process when a
  // component is dropped from the palette, and calling into MKL/IPP from
  // there was observed to crash the IDE with an access violation (unlike
  // the standalone demo .exe, where the same MKL calls work fine). Plain
  // scalar Math calls sidestep that entirely and are what TVMPlot3D's own
  // BuildDefaultDemoMatrix already safely uses for the same reason.
  Title := 'y = exp(-0.1x^2) . {sin(3x), cos(3x)}';
  XAxisTitle := 'x';
  YAxisTitle := 'y';
  X := TVMobj.Create(1, DemoPoints);
  YSin := TVMobj.Create(1, DemoPoints);
  YCos := TVMobj.Create(1, DemoPoints);
  for i := 0 to DemoPoints - 1 do begin
    t := i / (DemoPoints - 1);
    xv := DemoXMin + t * (DemoXMax - DemoXMin);
    env := Exp(-0.1 * xv * xv);
    X[0, i] := xv;
    YSin[0, i] := env * Sin(3 * xv);
    YCos[0, i] := env * Cos(3 * xv);
  end;
  SetSeriesStyle(0, clRed, 2.0, plsSolid, 'exp(-0.1x^2).sin(3x)');
  SetSeriesStyle(1, clBlue, 1.5, plsDash, 'exp(-0.1x^2).cos(3x)');
  SetData(X, [YSin, YCos]);
  // SetData just marked FUserDataStarted via EnsureUserDataStarted, so a
  // later real SetData/PlotXY call knows to append/replace rather than
  // clear first - but this was the constructor's own placeholder data,
  // not a real caller's, so undo that: the component should still look
  // pristine to EnsureUserDataStarted's eyes until an actual caller does
  // something.
  FUserDataStarted := False;
end;

destructor TVMPlot2D.Destroy;
begin
  // MakeCurrent reads Handle, which forces (re-)creation of the native
  // widget if not already allocated - fine during normal operation, but
  // fatal during application termination, when the widget tree is already
  // tearing down and handle (re-)creation fails, yielding Handle=0 and a
  // 'LOpenGLSwapBuffers Handle=0' exception from the LCL's GLX backend.
  // Only attempt the GL cleanup if a handle already exists; if it doesn't,
  // there's no live GL context to leak from anyway - it's going away with
  // the window.
  if HandleAllocated and MakeCurrent then FreeAllTextures;
  FSeriesStyles.Free;
  inherited Destroy;
end;

procedure TVMPlot2D.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot2D.SetXAxisTitle(const AValue: string);
begin
  if FXAxisTitle = AValue then Exit;
  FXAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot2D.SetYAxisTitle(const AValue: string);
begin
  if FYAxisTitle = AValue then Exit;
  FYAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot2D.SetSeriesStyles(AValue: TVMPlotSeriesStyles);
begin
  FSeriesStyles.Assign(AValue);
  Invalidate;
end;

procedure TVMPlot2D.SetVSync(AValue: Boolean);
begin
  if FVSync = AValue then Exit;
  FVSync := AValue;
  FSwapIntervalApplied := False;
  Invalidate;
end;

// See TVMPlot3D.ApplySwapInterval's own comment (uVMPlot3D.pas) - identical
// logic, mirrored here since this component ends its own Paint in an
// unconditional SwapBuffers too.
procedure TVMPlot2D.ApplySwapInterval;
begin
  if FSwapIntervalApplied then Exit;
  {$IFDEF UNIX}
  if Assigned(glXSwapIntervalEXT) and Assigned(glXGetCurrentDisplay) and
     Assigned(glXGetCurrentDrawable) then
    glXSwapIntervalEXT(glXGetCurrentDisplay(), glXGetCurrentDrawable(), Ord(FVSync))
  else if Assigned(glXSwapIntervalMESA) then
    glXSwapIntervalMESA(Ord(FVSync));
  {$ENDIF}
  {$IFDEF WINDOWS}
  if not WglSwapIntervalResolved then begin
    Pointer(WglSwapIntervalEXTProc) := wglGetProcAddress('wglSwapIntervalEXT');
    WglSwapIntervalResolved := True;
  end;
  if Assigned(WglSwapIntervalEXTProc) then
    WglSwapIntervalEXTProc(Ord(FVSync));
  {$ENDIF}
  FSwapIntervalApplied := True;
end;

procedure TVMPlot2D.SetSeriesStyle(Index: Integer; AColor: TColor;
  ALineWidth: Single; AStyle: TVMPlotLineStyle; const AName: string = '';
  AMarkerShape: TVMPlotMarkerShape = pmsNone; AMarkerSize: Single = 6.0);
begin
  assert((Index >= 0) and (Index < VMPlotMaxSeries),
    s + 'SetSeriesStyle : Index out of range');
  FSeriesStyles[Index].LineColor := AColor;
  FSeriesStyles[Index].LineWidth := ALineWidth;
  FSeriesStyles[Index].LineStyle := AStyle;
  FSeriesStyles[Index].Name := AName;
  FSeriesStyles[Index].MarkerShape := AMarkerShape;
  FSeriesStyles[Index].MarkerSize := AMarkerSize;
end;

// Marks cached title/tick GL textures for rebuild on the next paint -
// called whenever the title strings or the tick set (i.e. the data) change.
// Does not touch FTexturesBuilt's sibling per-texture GL resources itself;
// the paint handler frees the old ones via FreeAllTextures before
// rebuilding, since that needs a current GL context.
procedure TVMPlot2D.InvalidateTextures;
begin
  FTexturesBuilt := False;
end;

procedure TVMPlot2D.FreeTextTexture(var Tex: TVMPlotTextTexture);
begin
  if Tex.Built then begin
    glDeleteTextures(1, @Tex.TexID);
    Tex.Built := False;
  end;
end;

procedure TVMPlot2D.FreeAllTextures;
var
  i: Integer;
begin
  FreeTextTexture(FTitleTex);
  FreeTextTexture(FXAxisTitleTex);
  FreeTextTexture(FYAxisTitleTex);
  for i := 0 to High(FXTickTex) do FreeTextTexture(FXTickTex[i]);
  for i := 0 to High(FYTickTex) do FreeTextTexture(FYTickTex[i]);
  for i := 0 to High(FLegendTex) do FreeTextTexture(FLegendTex[i]);
end;

// Recomputes the combined bounding box (every series' X and Y alike) -
// with a margin - so the orthographic projection auto-fits whatever's
// currently plotted, and precomputes "nice" tick values over that
// (padded) range. Shared by SetData and PlotXY - the only difference
// between them is how FXData/FYData/FSeriesCount got populated before
// this runs; from here on both are the same "replot everything" work.
// Scans every point of every series from scratch each call, which is
// fine for SetData (already O(total points) just to build FXData/FYData)
// and for interactive/streaming PlotXY use at a reasonable point rate,
// but isn't optimised for very high-frequency appends against an
// already-large series (each call is itself O(total points so far)).
procedure TVMPlot2D.RecomputeBounds;
const
  MarginFrac = 0.08;
var
  i, iser: Integer;
  XMargin, YMargin: Double;
  HasAny: Boolean;
begin
  HasAny := False;
  for iser := 0 to FSeriesCount - 1 do
    for i := 0 to High(FXData[iser]) do begin
      if not HasAny then begin
        FXMin := FXData[iser][i]; FXMax := FXData[iser][i];
        FYMin := FYData[iser][i]; FYMax := FYData[iser][i];
        HasAny := True;
      end else begin
        if FXData[iser][i] < FXMin then FXMin := FXData[iser][i];
        if FXData[iser][i] > FXMax then FXMax := FXData[iser][i];
        if FYData[iser][i] < FYMin then FYMin := FYData[iser][i];
        if FYData[iser][i] > FYMax then FYMax := FYData[iser][i];
      end;
    end;
  if not HasAny then Exit;  // every series still empty - nothing to fit

  XMargin := (FXMax - FXMin) * MarginFrac;
  YMargin := (FYMax - FYMin) * MarginFrac;
  if XMargin = 0 then XMargin := 1;   // guard a constant-X vector
  if YMargin = 0 then YMargin := 1;   // guard a constant-Y vector
  FXMin := FXMin - XMargin; FXMax := FXMax + XMargin;
  FYMin := FYMin - YMargin; FYMax := FYMax + YMargin;

  FXTicks := ComputeTicks(FXMin, FXMax, 8);
  FYTicks := ComputeTicks(FYMin, FYMax, 6);
end;

// Clears every series (both SetData's and PlotXY's storage - the two
// share the same FXData/FYData, there's no separate pool per method) the
// first time either a real SetData or a real PlotXY call happens - i.e.
// while FUserDataStarted is still False, meaning only the constructor's
// own default-demo SetData call has ever run (see the constructor's own
// comment: it explicitly resets FUserDataStarted to False again right
// after that call, precisely so this trigger still fires for the first
// real caller). Called from the very top of both SetData and PlotXY, so
// whichever of the two a caller reaches for first, the constructor's
// placeholder data is discarded in one shot rather than partially - a
// SetData call for just series 0, say, would otherwise leave series 1's
// old placeholder data (or a previous real caller's data - see below)
// sitting there untouched, since SetData only ever touches the series
// indices it's actually given. Without this shared trigger, a caller
// mixing SetData (for some series) with PlotXY (for others) - the
// combination the whole point of PlotXY was to support (see the header
// comment) - would see PlotXY silently append its points onto the tail
// of whatever stale data (constructor placeholder or otherwise) already
// occupied that series index, instead of starting it from scratch.
procedure TVMPlot2D.EnsureUserDataStarted;
var
  iser: Integer;
begin
  if FUserDataStarted then Exit;
  for iser := 0 to VMPlotMaxSeries - 1 do begin
    SetLength(FXData[iser], 0);
    SetLength(FYData[iser], 0);
  end;
  FSeriesCount := 0;
  FUserDataStarted := True;
end;

// Extracts X and up to VMPlotMaxSeries Y TVMobj vectors into plain Double
// arrays for the paint handler. Each of X/YSeries[i] may be either row
// (1,N) or column (N,1) shaped, per newVM's usual vector convention. X is
// shared across every series in this call (SetData's own contract - see
// PlotXY for the per-series-X alternative), so it's simply copied into
// each series' own FXData[iser] slot; internally, a series' X and Y
// values always live side by side, whichever of SetData/PlotXY put them
// there. FSeriesCount only ever grows here (never shrinks to
// Length(YSeries) if that's fewer than before) - the same "high water
// mark" convention PlotXY's own FSeriesCount update already uses -
// specifically so a SetData call that only touches, say, series 0 can't
// un-render a higher-numbered series PlotXY separately populated.
procedure TVMPlot2D.SetData(const X: TVMobj; const YSeries: array of TVMobj);

  function VecLen(const V: TVMobj): Integer;
  begin
    result := V.Rows * V.Cols;
  end;

  function VecAt(const V: TVMobj; idx: Integer): Double;
  begin
    if V.Rows = 1 then result := V[0, idx] else result := V[idx, 0];
  end;

var
  N, i, iser: Integer;
  XVals: TVMPlotSeriesData;
  // See TVMPlot3D.SetData's identical snapshot/compare (uVMPlot3D.pas) -
  // same rationale, mirrored here.
  OldXTicks, OldYTicks: TVMPlotDoubleArray;
begin
  assert((Length(YSeries) >= 1) and (Length(YSeries) <= VMPlotMaxSeries),
    s + 'SetData : between 1 and ' + IntToStr(VMPlotMaxSeries) + ' Y series required');
  EnsureUserDataStarted;
  N := VecLen(X);
  SetLength(XVals, N);
  for i := 0 to N - 1 do XVals[i] := VecAt(X, i);

  if Length(YSeries) > FSeriesCount then FSeriesCount := Length(YSeries);
  for iser := 0 to Length(YSeries) - 1 do begin
    assert(VecLen(YSeries[iser]) = N,
      s + 'SetData : every Y series must be the same length as X');
    FXData[iser] := Copy(XVals, 0, N);
    SetLength(FYData[iser], N);
    for i := 0 to N - 1 do FYData[iser][i] := VecAt(YSeries[iser], i);
  end;

  OldXTicks := FXTicks;
  OldYTicks := FYTicks;
  RecomputeBounds;

  FHasData := True;
  if TicksChanged(OldXTicks, FXTicks) or TicksChanged(OldYTicks, FYTicks) then
    InvalidateTextures;
  Invalidate;
end;

// Appends one (X,Y) point to PlotLine's own data - the incremental,
// point-at-a-time counterpart to SetData's all-at-once TVMobj vectors,
// e.g. for building a series up over time (streaming/interactive data)
// rather than from a pre-built vector. Unlike SetData, PlotLine's X isn't
// shared with any other series - each series has always stored its own
// FXData[iser] internally (see SetData above), so appending to just one
// series here needs no special-casing. If PlotLine is beyond the current
// FSeriesCount, this extends FSeriesCount to include it; any series in
// between that has never been touched by SetData/PlotXY simply renders
// as empty (no line, no markers) until it gets its own first call - the
// same "just works" behaviour RecomputeBounds/Paint/DrawMarkers already
// have for a zero-length series. Freely mixable with SetData (including
// on a different PlotLine than SetData's own series - see
// EnsureUserDataStarted for how the two share one "first real call"
// trigger) or with itself on the same PlotLine: a call here always
// appends to whatever's already there, regardless of which method put it
// there, except - via EnsureUserDataStarted - the very first real call
// this component has ever received.
procedure TVMPlot2D.PlotXY(X, Y: Double; PlotLine: Integer);
var
  n: Integer;
  // See TVMPlot3D.SetData's identical snapshot/compare (uVMPlot3D.pas) -
  // matters even more here than for SetData: PlotXY is meant for
  // high-frequency streaming/interactive callers, exactly the case where
  // rebuilding every text texture on every single point would hurt most.
  OldXTicks, OldYTicks: TVMPlotDoubleArray;
begin
  assert((PlotLine >= 0) and (PlotLine < VMPlotMaxSeries),
    s + 'PlotXY : PlotLine out of range');
  EnsureUserDataStarted;

  n := Length(FXData[PlotLine]) + 1;
  SetLength(FXData[PlotLine], n);
  SetLength(FYData[PlotLine], n);
  FXData[PlotLine][n - 1] := X;
  FYData[PlotLine][n - 1] := Y;

  if PlotLine + 1 > FSeriesCount then FSeriesCount := PlotLine + 1;

  OldXTicks := FXTicks;
  OldYTicks := FYTicks;
  RecomputeBounds;

  FHasData := True;
  if TicksChanged(OldXTicks, FXTicks) or TicksChanged(OldYTicks, FYTicks) then
    InvalidateTextures;
  Invalidate;
end;

// Border rectangle at the data bounds, plus X/Y=0 gridlines where those
// fall inside the plotted range. Ported unchanged from uplot2dmain.pas.
procedure TVMPlot2D.DrawAxes;
begin
  glColor3f(0.75, 0.75, 0.75);
  glBegin(GL_LINE_LOOP);
    glVertex2d(FXMin, FYMin);
    glVertex2d(FXMax, FYMin);
    glVertex2d(FXMax, FYMax);
    glVertex2d(FXMin, FYMax);
  glEnd;

  glColor3f(0.55, 0.55, 0.55);
  glBegin(GL_LINES);
    if (FYMin < 0) and (FYMax > 0) then begin
      glVertex2d(FXMin, 0); glVertex2d(FXMax, 0);
    end;
    if (FXMin < 0) and (FXMax > 0) then begin
      glVertex2d(0, FYMin); glVertex2d(0, FYMax);
    end;
  glEnd;
end;

// Sets the current GL colour/width/stipple pattern for one series, per its
// TVMPlotSeriesStyle. Dash/dot are drawn via the fixed-function GL_LINE_
// STIPPLE mechanism (no equivalent exists for GL_LINE_STRIP any other way
// in OpenGL 1.x); solid disables stippling outright rather than using an
// all-ones pattern, since a stipple factor still subtly affects
// anti-aliased line rendering on some drivers.
//
// GL_LINE_SMOOTH + GL_LINE_STIPPLE together silently draw nothing at all on
// this codebase's tested Apple Silicon/macOS OpenGL implementation (legacy
// compatibility-profile GL) - confirmed by A/B testing: a dashed/dotted
// GL_LINE_STRIP renders correctly with GL_LINE_SMOOTH disabled and not at
// all with it enabled, while a solid (unstippled) strip is unaffected
// either way. Root cause not pinned down further than "this driver doesn't
// support the combination" - Paint enables GL_LINE_SMOOTH for the whole
// data-space pass (for solid lines' antialiasing), so a stippled series
// must locally disable it here, right alongside enabling the stipple
// itself, rather than leaving Paint's blanket setting in effect. The
// tradeoff (dash/dot lines render aliased/jagged, solid ones stay
// antialiased) is strictly better than a dash/dot series not rendering at
// all - see git history for the two real demos (Graphs/Plot2D,
// demos/Chebyshev/NormalIntegration) whose second, dashed series silently
// failed to draw before this fix.
procedure TVMPlot2D.ApplyLineStyle(const Style: TVMPlotSeriesStyle);
var
  Clr: TColor;
begin
  Clr := ColorToRGB(Style.LineColor);
  glColor3ub(Clr and $FF, (Clr shr 8) and $FF, (Clr shr 16) and $FF);
  glLineWidth(Style.LineWidth);
  case Style.LineStyle of
    plsSolid: begin
      glDisable(GL_LINE_STIPPLE);
      glEnable(GL_LINE_SMOOTH);
    end;
    plsDash: begin
      glDisable(GL_LINE_SMOOTH);
      glEnable(GL_LINE_STIPPLE);
      glLineStipple(3, $00FF);
    end;
    plsDot: begin
      glDisable(GL_LINE_SMOOTH);
      glEnable(GL_LINE_STIPPLE);
      glLineStipple(2, $1111);
    end;
    plsNone: ;  //caller skips the line strip entirely - see Paint/DrawLegend
  end;
end;

// Draws one marker glyph centered at (PX,PY) in the current (pixel-space)
// coordinate system - called once per data vertex from DrawMarkers below,
// and once per row from DrawLegend for the legend's marker glyphs, so PX/
// PY/MarkerSize are all already in pixels regardless of caller. Filled
// with FillColor (a series' LineColor - markers don't get a separate fill
// colour of their own), outlined in a fixed thin black line - "filled
// according to linecolor with a black boundary" is the whole visual
// contract, so neither colour is a per-marker property. Fill and outline
// are two separate glBegin/glEnd passes (GL_POLYGON/GL_TRIANGLE_FAN for
// the fill, GL_LINE_LOOP for the outline) rather than one, since a single
// filled primitive can't also carry a differently-coloured edge in
// OpenGL 1.x fixed-function rendering.
procedure TVMPlot2D.DrawMarker(PX, PY: Double; Shape: TVMPlotMarkerShape;
  MarkerSize: Single; FillColor: TColor);
const
  CircleSegments = 16;
var
  h: Double;
  i: Integer;
  ang: Double;
  Clr: TColor;
begin
  if Shape = pmsNone then Exit;
  h := MarkerSize / 2;
  Clr := ColorToRGB(FillColor);

  glColor3ub(Clr and $FF, (Clr shr 8) and $FF, (Clr shr 16) and $FF);
  case Shape of
    pmsSquare: begin
      glBegin(GL_QUADS);
        glVertex2d(PX - h, PY - h);
        glVertex2d(PX + h, PY - h);
        glVertex2d(PX + h, PY + h);
        glVertex2d(PX - h, PY + h);
      glEnd;
    end;
    pmsDiamond: begin
      glBegin(GL_QUADS);
        glVertex2d(PX, PY - h);
        glVertex2d(PX + h, PY);
        glVertex2d(PX, PY + h);
        glVertex2d(PX - h, PY);
      glEnd;
    end;
    pmsCircle: begin
      glBegin(GL_TRIANGLE_FAN);
        glVertex2d(PX, PY);
        for i := 0 to CircleSegments do begin
          ang := 2 * Pi * i / CircleSegments;
          glVertex2d(PX + h * Cos(ang), PY + h * Sin(ang));
        end;
      glEnd;
    end;
  end;

  glColor3ub(0, 0, 0);
  glLineWidth(1.0);
  case Shape of
    pmsSquare: begin
      glBegin(GL_LINE_LOOP);
        glVertex2d(PX - h, PY - h);
        glVertex2d(PX + h, PY - h);
        glVertex2d(PX + h, PY + h);
        glVertex2d(PX - h, PY + h);
      glEnd;
    end;
    pmsDiamond: begin
      glBegin(GL_LINE_LOOP);
        glVertex2d(PX, PY - h);
        glVertex2d(PX + h, PY);
        glVertex2d(PX, PY + h);
        glVertex2d(PX - h, PY);
      glEnd;
    end;
    pmsCircle: begin
      glBegin(GL_LINE_LOOP);
        for i := 0 to CircleSegments - 1 do begin
          ang := 2 * Pi * i / CircleSegments;
          glVertex2d(PX + h * Cos(ang), PY + h * Sin(ang));
        end;
      glEnd;
    end;
  end;
end;

// Draws every series' markers (those with MarkerShape <> pmsNone), once
// per data vertex. Runs in pass 2 (pixel space, see Paint) rather than
// pass 1's data-space glOrtho, precisely so MarkerSize stays a constant
// pixel size regardless of the data-space zoom/aspect ratio - the same
// reason tick labels are pixel-space chrome rather than data-space text.
// PX/PY reuse the exact linear-map formula Paint's own tick-mark loop
// uses to go from a data value to a pixel position; unlike ticks, no
// FXMin/FXMax range check is needed here, since every data vertex is by
// construction within [FXMin,FXMax]x[FYMin,FYMax] (those bounds are
// computed FROM the data itself, padded outward - see SetData).
procedure TVMPlot2D.DrawMarkers(PlotLeft, PlotBottom, PlotW, PlotH: Integer);
var
  iser, i: Integer;
  PX, PY: Double;
begin
  for iser := 0 to FSeriesCount - 1 do begin
    if FSeriesStyles[iser].MarkerShape = pmsNone then Continue;
    for i := 0 to High(FXData[iser]) do begin
      PX := PlotLeft + (FXData[iser][i] - FXMin) / (FXMax - FXMin) * PlotW;
      PY := PlotBottom + (FYData[iser][i] - FYMin) / (FYMax - FYMin) * PlotH;
      DrawMarker(PX, PY, FSeriesStyles[iser].MarkerShape,
        FSeriesStyles[iser].MarkerSize, FSeriesStyles[iser].LineColor);
    end;
  end;
end;

// Renders S once via the LCL's font engine into a TBitmap, converts it to
// an RGBA buffer (black text, alpha = 255-luminance so the white
// background drops out under normal alpha blending), and uploads it as a
// GL texture. Ported unchanged from uplot2dmain.pas - see the TEXT
// RENDERING note there. Must run with a current GL context.
function TVMPlot2D.CreateTextTexture(const S: string; FontSize: Integer;
  Bold: Boolean): TVMPlotTextTexture;
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
          TexPixels[(y * W + x) * 4 + 0] := 0;
          TexPixels[(y * W + x) * 4 + 1] := 0;
          TexPixels[(y * W + x) * 4 + 2] := 0;
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

// Builds every text texture the paint handler needs. Frees any previously
// built set first (FreeAllTextures) - unlike the original single-shot
// demo, Title/XAxisTitle/YAxisTitle and the data (hence tick labels) can
// change any number of times over this component's life.
procedure TVMPlot2D.BuildTextures;
var
  i: Integer;
begin
  FreeAllTextures;
  FTitleTex := CreateTextTexture(FTitle, 14, True);
  FXAxisTitleTex := CreateTextTexture(FXAxisTitle, 10, False);
  FYAxisTitleTex := CreateTextTexture(FYAxisTitle, 10, False);

  SetLength(FXTickTex, Length(FXTicks));
  for i := 0 to High(FXTicks) do
    FXTickTex[i] := CreateTextTexture(FormatTick(FXTicks[i]), 8, False);

  SetLength(FYTickTex, Length(FYTicks));
  for i := 0 to High(FYTicks) do
    FYTickTex[i] := CreateTextTexture(FormatTick(FYTicks[i]), 8, False);

  SetLength(FLegendTex, FSeriesCount);
  for i := 0 to FSeriesCount - 1 do
    if FSeriesStyles[i].Name <> '' then
      FLegendTex[i] := CreateTextTexture(FSeriesStyles[i].Name, 9, False);
end;

// Draws Tex as a textured quad anchored at (X,Y) in the current (pixel-
// space) coordinate system, optionally rotated AngleDeg counterclockwise
// about that anchor. Ported unchanged from uplot2dmain.pas.
procedure TVMPlot2D.DrawTextTexture(const Tex: TVMPlotTextTexture;
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

// Auto-sized legend panel anchored to the top right corner of the data
// plot rectangle (PlotLeft/PlotBottom/PlotW/PlotH, in the same pixel-space
// coordinates as pass 2's title/tick chrome, hence called from there - not
// pass 1, since the panel and its text are a fixed pixel size regardless
// of the data-space glOrtho zoom). One row per series whose Name is
// non-empty, each a short colour/width/stipple-matched line swatch (via
// ApplyLineStyle, the same routine the data-space line strips use) beside
// its CreateTextTexture-rendered label (built into FLegendTex by
// BuildTextures, alongside the title/tick textures). Series with a blank
// Name are skipped entirely - both from sizing and from the row layout -
// so the panel simply doesn't appear until at least one series has a
// Name set. Two passes over the same series list (swatches, then labels)
// rather than interleaving, since each needs a different GL_TEXTURE_2D
// enable state and toggling it per-row would be wasteful.
procedure TVMPlot2D.DrawLegend(PlotLeft, PlotBottom, PlotW, PlotH: Integer);
const
  PanelInset = 10;  // gap between the plot rectangle's edges and the panel
  Padding = 8;      // gap between the panel's border and its content
  SwatchW = 26;
  SwatchGap = 6;
  RowGap = 4;
var
  i, RowCount, RowH, ContentW, BoxW, BoxH, X0, Y0, RowY: Integer;
begin
  RowCount := 0;
  ContentW := 0;
  RowH := 0;
  for i := 0 to FSeriesCount - 1 do
    if FSeriesStyles[i].Name <> '' then begin
      Inc(RowCount);
      ContentW := Max(ContentW, SwatchW + SwatchGap + FLegendTex[i].W);
      RowH := Max(RowH, FLegendTex[i].H);
    end;
  if RowCount = 0 then Exit;

  BoxW := ContentW + Padding * 2;
  BoxH := RowCount * RowH + (RowCount - 1) * RowGap + Padding * 2;
  X0 := PlotLeft + PlotW - BoxW - PanelInset;
  Y0 := PlotBottom + PlotH - BoxH - PanelInset;

  glDisable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 0.75);
  glBegin(GL_QUADS);
    glVertex2d(X0, Y0);
    glVertex2d(X0 + BoxW, Y0);
    glVertex2d(X0 + BoxW, Y0 + BoxH);
    glVertex2d(X0, Y0 + BoxH);
  glEnd;
  glColor3f(0.6, 0.6, 0.6);
  glBegin(GL_LINE_LOOP);
    glVertex2d(X0, Y0);
    glVertex2d(X0 + BoxW, Y0);
    glVertex2d(X0 + BoxW, Y0 + BoxH);
    glVertex2d(X0, Y0 + BoxH);
  glEnd;

  RowY := Y0 + BoxH - Padding;
  for i := 0 to FSeriesCount - 1 do begin
    if FSeriesStyles[i].Name = '' then Continue;
    RowY := RowY - RowH;
    if FSeriesStyles[i].LineStyle <> plsNone then begin
      ApplyLineStyle(FSeriesStyles[i]);
      glBegin(GL_LINES);
        glVertex2d(X0 + Padding, RowY + RowH / 2);
        glVertex2d(X0 + Padding + SwatchW, RowY + RowH / 2);
      glEnd;
    end;
    RowY := RowY - RowGap;
  end;
  glDisable(GL_LINE_STIPPLE);

  // Marker glyphs, own pass: DrawMarker sets its own fill/outline colours
  // per call (not the stippled/width-varying state ApplyLineStyle just
  // set up for the line swatches above), so interleaving it into the
  // loop above would mean re-establishing ApplyLineStyle's state after
  // every marker. Capped to RowH-2 so an oversized MarkerSize can't blow
  // out the legend row.
  RowY := Y0 + BoxH - Padding;
  for i := 0 to FSeriesCount - 1 do begin
    if FSeriesStyles[i].Name = '' then Continue;
    RowY := RowY - RowH;
    if FSeriesStyles[i].MarkerShape <> pmsNone then
      DrawMarker(X0 + Padding + SwatchW / 2, RowY + RowH / 2,
        FSeriesStyles[i].MarkerShape, Min(FSeriesStyles[i].MarkerSize, RowH - 2),
        FSeriesStyles[i].LineColor);
    RowY := RowY - RowGap;
  end;

  glEnable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 1);
  RowY := Y0 + BoxH - Padding;
  for i := 0 to FSeriesCount - 1 do begin
    if FSeriesStyles[i].Name = '' then Continue;
    RowY := RowY - RowH;
    DrawTextTexture(FLegendTex[i], X0 + Padding + SwatchW + SwatchGap,
      RowY + RowH / 2, 0, 0, 0.5);
    RowY := RowY - RowGap;
  end;
  glDisable(GL_TEXTURE_2D);
end;

procedure TVMPlot2D.Paint;
const
  // Fixed pixel margins reserved around the data-space plot rectangle for
  // the title/axis-titles/tick labels - independent of window size, so
  // labels stay a constant size regardless of how the control is resized.
  TopMargin = 34;
  BottomMargin = 55;
  LeftMargin = 65;
  RightMargin = 18;
var
  i, iser, W, H, PlotLeft, PlotBottom, PlotW, PlotH: Integer;
  px, py: Double;
begin
  if not MakeCurrent then Exit;
  W := Width;
  H := Height;
  if (W = 0) or (H = 0) then Exit;
  ApplySwapInterval;

  if not FTexturesBuilt then begin
    BuildTextures;
    FTexturesBuilt := True;
  end;

  PlotLeft := LeftMargin;
  PlotBottom := BottomMargin;
  PlotW := Max(W - LeftMargin - RightMargin, 1);
  PlotH := Max(H - TopMargin - BottomMargin, 1);

  glClearColor(1.0, 1.0, 1.0, 1.0);
  glViewport(0, 0, W, H);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  if FHasData then begin
    // --- pass 1: data-space plot (border/gridlines/line-strips) ---
    glViewport(PlotLeft, PlotBottom, PlotW, PlotH);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity;
    glOrtho(FXMin, FXMax, FYMin, FYMax, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity;

    glEnable(GL_LINE_SMOOTH);
    glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);

    DrawAxes;

    for iser := 0 to FSeriesCount - 1 do begin
      if FSeriesStyles[iser].LineStyle = plsNone then Continue;
      ApplyLineStyle(FSeriesStyles[iser]);
      glBegin(GL_LINE_STRIP);
        for i := 0 to High(FXData[iser]) do
          glVertex2d(FXData[iser][i], FYData[iser][i]);
      glEnd;
    end;
    glDisable(GL_LINE_STIPPLE);

    // --- pass 2: pixel-space chrome (title/axis titles/tick marks/labels) ---
    glViewport(0, 0, W, H);
    glMatrixMode(GL_PROJECTION);
    glLoadIdentity;
    glOrtho(0, W, 0, H, -1, 1);
    glMatrixMode(GL_MODELVIEW);
    glLoadIdentity;
    glDisable(GL_LINE_SMOOTH);

    glEnable(GL_TEXTURE_2D);
    glColor4f(1, 1, 1, 1);
    if FTitle <> '' then
      DrawTextTexture(FTitleTex, W / 2, H - TopMargin / 2, 0, 0.5, 0.5);
    if FXAxisTitle <> '' then
      DrawTextTexture(FXAxisTitleTex, PlotLeft + PlotW / 2, 12, 0, 0.5, 0);
    if FYAxisTitle <> '' then
      DrawTextTexture(FYAxisTitleTex, 14, PlotBottom + PlotH / 2, 90, 0.5, 1);
    glDisable(GL_TEXTURE_2D);

    glColor3f(0.55, 0.55, 0.55);
    glBegin(GL_LINES);
      for i := 0 to High(FXTicks) do begin
        if (FXTicks[i] < FXMin) or (FXTicks[i] > FXMax) then Continue;
        px := PlotLeft + (FXTicks[i] - FXMin) / (FXMax - FXMin) * PlotW;
        glVertex2d(px, PlotBottom); glVertex2d(px, PlotBottom - 5);
      end;
      for i := 0 to High(FYTicks) do begin
        if (FYTicks[i] < FYMin) or (FYTicks[i] > FYMax) then Continue;
        py := PlotBottom + (FYTicks[i] - FYMin) / (FYMax - FYMin) * PlotH;
        glVertex2d(PlotLeft, py); glVertex2d(PlotLeft - 5, py);
      end;
    glEnd;

    glEnable(GL_TEXTURE_2D);
    glColor4f(1, 1, 1, 1);
    for i := 0 to High(FXTicks) do begin
      if (FXTicks[i] < FXMin) or (FXTicks[i] > FXMax) then Continue;
      px := PlotLeft + (FXTicks[i] - FXMin) / (FXMax - FXMin) * PlotW;
      DrawTextTexture(FXTickTex[i], px, PlotBottom - 8, 0, 0.5, 1);
    end;
    for i := 0 to High(FYTicks) do begin
      if (FYTicks[i] < FYMin) or (FYTicks[i] > FYMax) then Continue;
      py := PlotBottom + (FYTicks[i] - FYMin) / (FYMax - FYMin) * PlotH;
      DrawTextTexture(FYTickTex[i], PlotLeft - 8, py, 0, 1, 0.5);
    end;
    glDisable(GL_TEXTURE_2D);

    // Point markers, drawn on top of the gridlines/ticks/line strips
    // beneath them but before the legend panel, which stays topmost
    // (its own semi-transparent background would otherwise be drawn
    // under any marker near the top-right corner).
    DrawMarkers(PlotLeft, PlotBottom, PlotW, PlotH);

    // Drawn last (on top of the border/gridlines/ticks/line strips already
    // painted, all of which are further from the top-right corner anyway).
    DrawLegend(PlotLeft, PlotBottom, PlotW, PlotH);
  end;

  SwapBuffers;
end;

procedure TVMPlot2D.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure Register;
begin
  {$I uvmplot2d_icon.lrs}
  RegisterComponents('newVM', [TVMPlot2D]);
end;

end.
