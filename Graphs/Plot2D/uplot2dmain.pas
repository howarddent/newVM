unit uplot2dmain;

{*******************************************************************************

     Main form for the Plot2D demo. Computes y = f(x) elementwise on a TVMobj
     (1 x NumPoints row vector, see newVM.pas) - the same function as
     demos/FunctionPlot - but renders it with raw OpenGL (TOpenGLControl,
     the LazOpenGLContext package, plus FPC's own GL unit) instead of
     TAChart: an anti-aliased line strip inside an orthographic projection
     auto-fitted to the data's bounding box, with axis scales (tick marks
     and value labels), a main title and axis titles drawn in GL rather
     than left to a charting component.

     BuildPlotData accepts any real TVMobj vector (row or column shaped,
     per newVM's (1,N)/(N,1) convention) plus title strings - the one
     concrete function plotted here is just a demonstration of that
     general path, the same way FunctionPlot's y=f(x) is one concrete use
     of TAChart.

     TEXT RENDERING: OpenGL 1.x has no built-in text. Rather than depend on
     a platform-specific font API (e.g. Windows' wglUseFontBitmaps) or
     guess at the exact signatures of FPC's compiled-only glut.ppu (no
     .pas source for it is bundled here to check against), every title/
     label string is rendered ONCE via the LCL's own font engine into a
     TBitmap, converted to an RGBA buffer (alpha = 255-luminance, so white
     background becomes fully transparent and black text becomes fully
     opaque - the same "read pixels via TLazIntfImage" trick
     demos/openglcontrol_demo.pas uses to load a PNG texture), uploaded as
     a GL texture, and cached (CreateTextTexture/BuildTextures, run once on
     the first paint) - then drawn every frame as a small textured,
     alpha-blended quad (DrawTextTexture, which also handles the Y axis
     title's 90-degree rotation, trivial for a textured quad since it is
     just GL geometry). This is fully portable LCL/GL, no platform-specific
     or guessed-at APIs.

     LAYOUT: the paint handler renders in two passes - a data-space pass
     (glOrtho over the data's bounding box, restricted to a shrunk
     glViewport that leaves fixed pixel margins around the control for the
     chrome below) for the border/gridlines/line-strip exactly as before,
     then a pixel-space pass (glOrtho(0,Width,0,Height,...) over the FULL
     control) for the title, axis titles, and tick marks/labels - whose
     positions are computed by mapping each tick's data value through the
     same data-to-plot-rectangle transform used for the data-space pass.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs,
  IntfGraphics, FPImage,
  GL, OpenGLContext,
  newVM;

type
  TDoubleArray = array of Double;

  // A title/axis-title/tick-label string rendered once to a GL texture -
  // see the TEXT RENDERING note above.
  TTextTexture = record
    TexID: GLuint;
    W, H: Integer;
  end;

  { TForm1 }

  TForm1 = class(TForm)
    OpenGLControl1: TOpenGLControl;
    procedure FormCreate(Sender: TObject);
    procedure OpenGLControl1Paint(Sender: TObject);
    procedure OpenGLControl1Resize(Sender: TObject);
  private
    FXData, FYData: array of Double;
    FXMin, FXMax, FYMin, FYMax: Double;
    FTitle, FXAxisTitle, FYAxisTitle: string;
    FXTicks, FYTicks: TDoubleArray;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex: TTextTexture;
    FXTickTex, FYTickTex: array of TTextTexture;
    procedure BuildPlotData(const X, Y: TVMobj;
      const ATitle, AXTitle, AYTitle: string);
    procedure DrawAxes;
    function CreateTextTexture(const S: string; FontSize: Integer;
      Bold: Boolean): TTextTexture;
    procedure BuildTextures;
    procedure DrawTextTexture(const Tex: TTextTexture;
      X, Y, AngleDeg, HAlign, VAlign: Double);
  end;

var
  Form1: TForm1;

const
  NumPoints = 1000;
  XRangeMin = -10.0;
  XRangeMax = 10.0;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  X, Y: TVMobj;
begin
  X := TVMobj.Create(1, NumPoints);
  X.linspace(XRangeMin, (XRangeMax - XRangeMin) / (NumPoints - 1));
  Y := Exp(-0.1 * Sqr(X)) * Sin(3 * X);   // y = exp(-0.1*x^2) * sin(3*x)
  BuildPlotData(X, Y, 'y = exp(-0.1x^2) . sin(3x)', 'x', 'y');
end;

// "Nice" round tick step (1/2/5 x 10^n) closest to x - Heckbert's classic
// "Nice Numbers for Graph Labels" algorithm, simplified to the single case
// this needs (rounding the step itself, not the axis bounds).
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

// Tick values spaced at a "nice" step, covering [lo,hi] - roughly
// TargetCount of them, each an exact multiple of the step so labels read
// as round numbers (e.g. 0, 2, 4, ... not 0.37, 2.37, 4.37, ...).
function ComputeTicks(lo, hi: Double; TargetCount: Integer): TDoubleArray;
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

// Compact, human-friendly tick label (e.g. "2", "0.5", "-1.25") rather
// than Double's full decimal expansion.
function FormatTick(v: Double): string;
begin
  result := FloatToStrF(v, ffGeneral, 4, 0);
end;

// Extracts a TVMobj vector pair into plain Double arrays for the paint
// handler (avoids a bounds-checked Element[] call per vertex per frame),
// computes the data's bounding box - with a margin - so the orthographic
// projection auto-fits it regardless of what X/Y contain, and precomputes
// "nice" tick values over that (padded) range. X and Y may each be either
// row (1,N) or column (N,1) shaped. Title strings are stored for
// BuildTextures to render once a GL context exists (see the TEXT
// RENDERING note above) - not done here, since this runs from FormCreate
// before OpenGLControl1 necessarily has a live context.
procedure TForm1.BuildPlotData(const X, Y: TVMobj;
  const ATitle, AXTitle, AYTitle: string);
const
  MarginFrac = 0.08;

  function VecLen(const V: TVMobj): Integer;
  begin
    result := V.Rows * V.Cols;
  end;

  function VecAt(const V: TVMobj; i: Integer): Double;
  begin
    if V.Rows = 1 then result := V[0, i] else result := V[i, 0];
  end;

var
  N, i: Integer;
  XMargin, YMargin: Double;
begin
  N := VecLen(Y);
  assert(VecLen(X) = N, 'BuildPlotData: X and Y must have the same length');
  SetLength(FXData, N);
  SetLength(FYData, N);
  for i := 0 to N - 1 do begin
    FXData[i] := VecAt(X, i);
    FYData[i] := VecAt(Y, i);
  end;

  FXMin := FXData[0]; FXMax := FXData[0];
  FYMin := FYData[0]; FYMax := FYData[0];
  for i := 1 to N - 1 do begin
    if FXData[i] < FXMin then FXMin := FXData[i];
    if FXData[i] > FXMax then FXMax := FXData[i];
    if FYData[i] < FYMin then FYMin := FYData[i];
    if FYData[i] > FYMax then FYMax := FYData[i];
  end;
  XMargin := (FXMax - FXMin) * MarginFrac;
  YMargin := (FYMax - FYMin) * MarginFrac;
  if XMargin = 0 then XMargin := 1;   // guard a constant-X vector
  if YMargin = 0 then YMargin := 1;   // guard a constant-Y vector
  FXMin := FXMin - XMargin; FXMax := FXMax + XMargin;
  FYMin := FYMin - YMargin; FYMax := FYMax + YMargin;

  FXTicks := ComputeTicks(FXMin, FXMax, 8);
  FYTicks := ComputeTicks(FYMin, FYMax, 6);

  FTitle := ATitle;
  FXAxisTitle := AXTitle;
  FYAxisTitle := AYTitle;
end;

// Border rectangle at the data bounds, plus X/Y=0 gridlines where those
// fall inside the plotted range. Drawn in the data-space pass, so these
// coordinates are data values, not pixels.
procedure TForm1.DrawAxes;
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

// Renders S once via the LCL's font engine into a TBitmap, converts it to
// an RGBA buffer (black text, alpha = 255-luminance so the white
// background drops out under normal alpha blending), and uploads it as a
// GL texture - see the TEXT RENDERING note in the unit header. Must run
// with a current GL context (called from BuildTextures, itself only
// called from the paint handler).
function TForm1.CreateTextTexture(const S: string; FontSize: Integer;
  Bold: Boolean): TTextTexture;
var
  Bmp: TBitmap;
  IntfImg: TLazIntfImage;
  x, y, W, H: Integer;
  c: TFPColor;
  lum: Byte;
  RGBA: array of Byte;
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
      SetLength(RGBA, W * H * 4);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do begin
          c := IntfImg.Colors[x, y];
          lum := (c.red shr 8 + c.green shr 8 + c.blue shr 8) div 3;
          RGBA[(y * W + x) * 4 + 0] := 0;
          RGBA[(y * W + x) * 4 + 1] := 0;
          RGBA[(y * W + x) * 4 + 2] := 0;
          RGBA[(y * W + x) * 4 + 3] := 255 - lum;
        end;
    finally
      IntfImg.Free;
    end;

    glGenTextures(1, @result.TexID);
    glBindTexture(GL_TEXTURE_2D, result.TexID);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, @RGBA[0]);
    result.W := W;
    result.H := H;
  finally
    Bmp.Free;
  end;
end;

// Builds every text texture the paint handler needs, once - the title/
// axis titles/tick values themselves don't change frame to frame, so
// there is no reason to re-render them via the LCL and re-upload every
// paint. Called lazily on the first paint (see OpenGLControl1Paint),
// mirroring the "AreaInitialized" once-only init pattern in
// lazarus/examples/openglcontrol/exampleform.pp.
procedure TForm1.BuildTextures;
var
  i: Integer;
begin
  FTitleTex := CreateTextTexture(FTitle, 14, True);
  FXAxisTitleTex := CreateTextTexture(FXAxisTitle, 10, False);
  FYAxisTitleTex := CreateTextTexture(FYAxisTitle, 10, False);

  SetLength(FXTickTex, Length(FXTicks));
  for i := 0 to High(FXTicks) do
    FXTickTex[i] := CreateTextTexture(FormatTick(FXTicks[i]), 8, False);

  SetLength(FYTickTex, Length(FYTicks));
  for i := 0 to High(FYTicks) do
    FYTickTex[i] := CreateTextTexture(FormatTick(FYTicks[i]), 8, False);
end;

// Draws Tex as a textured quad anchored at (X,Y) in the CURRENT (pixel-
// space, for every call site in this unit) coordinate system, optionally
// rotated AngleDeg counterclockwise about that anchor - trivial for a
// textured quad since it is just ordinary GL geometry, unlike a rotated
// bitmap font. HAlign/VAlign (0..1) place the anchor within the quad's
// own (unrotated) width/height: 0=left/bottom edge, 0.5=centre, 1=right/
// top edge - e.g. HAlign=0.5,VAlign=0 centres the text horizontally on X
// with its bottom edge at Y.
procedure TForm1.DrawTextTexture(const Tex: TTextTexture;
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

procedure TForm1.OpenGLControl1Paint(Sender: TObject);
const
  // Fixed pixel margins reserved around the data-space plot rectangle for
  // the title/axis-titles/tick labels - see the LAYOUT note in the unit
  // header. Independent of window size, so labels stay a constant size
  // regardless of how the control is resized.
  TopMargin = 34;
  BottomMargin = 55;
  LeftMargin = 65;
  RightMargin = 18;
var
  i, W, H, PlotLeft, PlotBottom, PlotW, PlotH: Integer;
  px, py: Double;
begin
  if not OpenGLControl1.MakeCurrent then Exit;
  W := OpenGLControl1.Width;
  H := OpenGLControl1.Height;
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

  // --- pass 1: data-space plot (border/gridlines/line-strip), restricted
  // to the shrunk plot rectangle so it doesn't overlap the chrome below ---
  glViewport(PlotLeft, PlotBottom, PlotW, PlotH);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(FXMin, FXMax, FYMin, FYMax, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glEnable(GL_LINE_SMOOTH);
  glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);

  DrawAxes;

  glColor3f(0.1, 0.3, 0.9);
  glLineWidth(2.0);
  glBegin(GL_LINE_STRIP);
    for i := 0 to High(FXData) do
      glVertex2d(FXData[i], FYData[i]);
  glEnd;

  // --- pass 2: pixel-space chrome (title/axis titles/tick marks/labels),
  // over the FULL control - tick positions are the data-space pass's
  // FXMin..FXMax/FYMin..FYMax mapped through the same plot-rectangle
  // transform "by hand", since this pass uses a different projection ---
  glViewport(0, 0, W, H);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, W, 0, H, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glDisable(GL_LINE_SMOOTH);

  glEnable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 1);
  DrawTextTexture(FTitleTex, W / 2, H - TopMargin / 2, 0, 0.5, 0.5);
  DrawTextTexture(FXAxisTitleTex, PlotLeft + PlotW / 2, 12, 0, 0.5, 0);
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

  OpenGLControl1.SwapBuffers;
end;

procedure TForm1.OpenGLControl1Resize(Sender: TObject);
begin
  OpenGLControl1.Invalidate;
end;

end.
