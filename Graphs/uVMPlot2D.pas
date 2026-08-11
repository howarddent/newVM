unit uVMPlot2D;

{*******************************************************************************

     TVMPlot2D - a reusable, droppable-on-a-form LCL component wrapping
     TOpenGLControl (LazOpenGLContext) that plots one or more newVM (TVMobj)
     vectors against a shared X vector. This is the rendering engine of the
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

     SetData takes a single TVMobj for X and an open array of up to
     VMPlotMaxSeries (10) TVMobj vectors for Y - each must be the same
     length as X (row or column shaped, either is accepted, matching
     newVM's (1,N)/(N,1) vector convention). Per-series LineColor/
     LineWidth/LineStyle (solid/dash/dot, via GL_LINE_STIPPLE)/Name are
     exposed both as a published `Series` collection (editable per-slot at
     design time in the Object Inspector) and via the SetSeriesStyle
     convenience method for runtime code. A series' Name, when non-empty,
     both labels its line in the auto-sized legend panel drawn in the top
     right of the plot rectangle (a colour/style-matched line swatch plus
     the name) and is skipped from the legend entirely when left blank -
     so the legend only appears once at least one series has a Name set,
     and never needs disabling explicitly. Title/XAxisTitle/YAxisTitle are
     plain published string properties. All other published behaviour
     (Align, Anchors, Color, mouse/key events, etc.) comes straight from
     the inherited TOpenGLControl - nothing needs re-declaring for those.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics,
  IntfGraphics, FPImage,
  GL, OpenGLContext,
  newVM;

const
  VMPlotMaxSeries = 10;

type
  TVMPlotLineStyle = (plsSolid, plsDash, plsDot);

  { TVMPlotSeriesStyle }

  TVMPlotSeriesStyle = class(TCollectionItem)
  private
    FLineColor: TColor;
    FLineWidth: Single;
    FLineStyle: TVMPlotLineStyle;
    FName: string;
    procedure SetLineColor(AValue: TColor);
    procedure SetLineWidth(AValue: Single);
    procedure SetLineStyle(AValue: TVMPlotLineStyle);
    procedure SetName(const AValue: string);
  public
    constructor Create(ACollection: TCollection); override;
    function GetDisplayName: string; override;
  published
    property LineColor: TColor read FLineColor write SetLineColor;
    property LineWidth: Single read FLineWidth write SetLineWidth;
    property LineStyle: TVMPlotLineStyle read FLineStyle write SetLineStyle;
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
    FXData: TVMPlotDoubleArray;
    FYData: array[0..VMPlotMaxSeries - 1] of TVMPlotSeriesData;
    FSeriesCount: Integer;
    FHasData: Boolean;
    FXMin, FXMax, FYMin, FYMax: Double;
    FXTicks, FYTicks: TVMPlotDoubleArray;
    FTitle, FXAxisTitle, FYAxisTitle: string;
    FSeriesStyles: TVMPlotSeriesStyles;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex: TVMPlotTextTexture;
    FXTickTex, FYTickTex, FLegendTex: array of TVMPlotTextTexture;
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
    procedure DrawLegend(PlotLeft, PlotBottom, PlotW, PlotH: Integer);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure SetData(const X: TVMobj; const YSeries: array of TVMobj);
    procedure SetSeriesStyle(Index: Integer; AColor: TColor;
      ALineWidth: Single; AStyle: TVMPlotLineStyle; const AName: string = '');
  published
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
    property YAxisTitle: string read FYAxisTitle write SetYAxisTitle;
    property Series: TVMPlotSeriesStyles read FSeriesStyles write SetSeriesStyles;
  end;

procedure Register;

implementation

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

{ TVMPlot2D }

constructor TVMPlot2D.Create(TheOwner: TComponent);
var
  i: Integer;
  Item: TVMPlotSeriesStyle;
begin
  inherited Create(TheOwner);
  FSeriesStyles := TVMPlotSeriesStyles.Create(Self);
  for i := 0 to VMPlotMaxSeries - 1 do begin
    Item := TVMPlotSeriesStyle(FSeriesStyles.Add);
    Item.LineColor := RGBToColor(DefaultPaletteR[i], DefaultPaletteG[i], DefaultPaletteB[i]);
  end;
  FSeriesCount := 0;
  FHasData := False;
  FTexturesBuilt := False;
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

procedure TVMPlot2D.SetSeriesStyle(Index: Integer; AColor: TColor;
  ALineWidth: Single; AStyle: TVMPlotLineStyle; const AName: string = '');
begin
  assert((Index >= 0) and (Index < VMPlotMaxSeries),
    s + 'SetSeriesStyle : Index out of range');
  FSeriesStyles[Index].LineColor := AColor;
  FSeriesStyles[Index].LineWidth := ALineWidth;
  FSeriesStyles[Index].LineStyle := AStyle;
  FSeriesStyles[Index].Name := AName;
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

// Extracts X and up to VMPlotMaxSeries Y TVMobj vectors into plain Double
// arrays for the paint handler, computes the combined bounding box (X plus
// every Y series) - with a margin - so the orthographic projection
// auto-fits all series regardless of what they contain, and precomputes
// "nice" tick values over that (padded) range. Each of X/YSeries[i] may be
// either row (1,N) or column (N,1) shaped, per newVM's vector convention.
procedure TVMPlot2D.SetData(const X: TVMobj; const YSeries: array of TVMobj);
const
  MarginFrac = 0.08;

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
  XMargin, YMargin: Double;
begin
  assert((Length(YSeries) >= 1) and (Length(YSeries) <= VMPlotMaxSeries),
    s + 'SetData : between 1 and ' + IntToStr(VMPlotMaxSeries) + ' Y series required');
  N := VecLen(X);
  SetLength(FXData, N);
  for i := 0 to N - 1 do FXData[i] := VecAt(X, i);

  FSeriesCount := Length(YSeries);
  for iser := 0 to FSeriesCount - 1 do begin
    assert(VecLen(YSeries[iser]) = N,
      s + 'SetData : every Y series must be the same length as X');
    SetLength(FYData[iser], N);
    for i := 0 to N - 1 do FYData[iser][i] := VecAt(YSeries[iser], i);
  end;

  FXMin := FXData[0]; FXMax := FXData[0];
  FYMin := FYData[0][0]; FYMax := FYData[0][0];
  for i := 0 to N - 1 do begin
    if FXData[i] < FXMin then FXMin := FXData[i];
    if FXData[i] > FXMax then FXMax := FXData[i];
  end;
  for iser := 0 to FSeriesCount - 1 do
    for i := 0 to N - 1 do begin
      if FYData[iser][i] < FYMin then FYMin := FYData[iser][i];
      if FYData[iser][i] > FYMax then FYMax := FYData[iser][i];
    end;

  XMargin := (FXMax - FXMin) * MarginFrac;
  YMargin := (FYMax - FYMin) * MarginFrac;
  if XMargin = 0 then XMargin := 1;   // guard a constant-X vector
  if YMargin = 0 then YMargin := 1;   // guard a constant-Y vector
  FXMin := FXMin - XMargin; FXMax := FXMax + XMargin;
  FYMin := FYMin - YMargin; FYMax := FYMax + YMargin;

  FXTicks := ComputeTicks(FXMin, FXMax, 8);
  FYTicks := ComputeTicks(FYMin, FYMax, 6);

  FHasData := True;
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
procedure TVMPlot2D.ApplyLineStyle(const Style: TVMPlotSeriesStyle);
var
  Clr: TColor;
begin
  Clr := ColorToRGB(Style.LineColor);
  glColor3ub(Clr and $FF, (Clr shr 8) and $FF, (Clr shr 16) and $FF);
  glLineWidth(Style.LineWidth);
  case Style.LineStyle of
    plsSolid: glDisable(GL_LINE_STIPPLE);
    plsDash: begin
      glEnable(GL_LINE_STIPPLE);
      glLineStipple(3, $00FF);
    end;
    plsDot: begin
      glEnable(GL_LINE_STIPPLE);
      glLineStipple(2, $1111);
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
    ApplyLineStyle(FSeriesStyles[i]);
    glBegin(GL_LINES);
      glVertex2d(X0 + Padding, RowY + RowH / 2);
      glVertex2d(X0 + Padding + SwatchW, RowY + RowH / 2);
    glEnd;
    RowY := RowY - RowGap;
  end;
  glDisable(GL_LINE_STIPPLE);

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
      ApplyLineStyle(FSeriesStyles[iser]);
      glBegin(GL_LINE_STRIP);
        for i := 0 to High(FXData) do
          glVertex2d(FXData[i], FYData[iser][i]);
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
  RegisterComponents('newVM', [TVMPlot2D]);
end;

end.
