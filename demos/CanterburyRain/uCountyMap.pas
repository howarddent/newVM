unit uCountyMap;

{*******************************************************************************

     TCountyMapView - the CanterburyRain demo's county rainfall map: an
     OpenGL (TOpenGLControl) map of the 218 UK counties and unitary
     authorities (uCountyRain's compiled-in ONS boundaries, British
     National Grid coordinates, drawn as they are - BNG is already a
     conformal projection of Great Britain), each county filled with the
     colour of its value, with county outlines, Ireland and the Isle of Man
     in grey for context, the selected county outlined in black and the
     selected place as a red dot. Clicking a county selects it and fires
     OnSelectCounty.

     FILLING: county outlines are concave and some have holes, which
     GL_POLYGON cannot fill. Each county is filled with the stencil-buffer
     method instead: every ring is drawn as a triangle fan from its first
     vertex with the stencil op INVERT (colour writes off), which leaves
     the stencil set exactly where the point is inside an odd number of
     rings - the even-odd rule, holes included - and then one quad over
     the county's bounding box is drawn in its colour where the stencil is
     set, zeroing it again for the next county. Needs a stencil buffer:
     StencilBits := 8 in the constructor, before the GL context exists.

     COLOURS (CountyColour, also used by the form's colour bar):
       cmTotal    sequential light yellow - green - blue - dark blue, Lo..Hi
       cmAnomaly  diverging about 0: white at 0, blues for positive values
                  (wetter than average), browns for negative (drier),
                  symmetric -Range..+Range
     A value of NaN (no data) is drawn light grey.

     Like TVMPlot2D, Paint is MakeCurrent + RenderScene + SwapBuffers, and
     SaveToPNG renders and reads the back buffer before any swap.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  FPImage, FPWritePNG,
  GL, OpenGLContext,
  uCountyRain;

type
  TCountyColourMode = (cmTotal, cmAnomaly);
  TSelectCountyEvent = procedure(Sender: TObject; County: Integer) of object;

  { TCountyMapView }

  TCountyMapView = class(TOpenGLControl)
  private
    FValues: TCountyValues;
    FHasValues: Boolean;
    FMode: TCountyColourMode;
    FLo, FHi: Double;
    FSelected: Integer;
    FPlaceE, FPlaceN: Double;
    FHasPlace: Boolean;
    FOnSelectCounty: TSelectCountyEvent;
    FEMin, FEMax, FNMin, FNMax: Double;      // extent, BNG metres
    FScale, FOffX, FOffY: Double;
    FBoxE0, FBoxE1, FBoxN0, FBoxN1: array[0..CountyCount - 1] of Single;
    procedure FitView;
    procedure ToPixel(E, N: Double; out PX, PY: Double);
    function RenderScene: Boolean;
    procedure SetSelected(AValue: Integer);
  protected
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(TheOwner: TComponent); override;
    procedure Paint; override;
    procedure Resize; override;
    // Values per county and how to colour them: cmTotal over Lo..Hi,
    // cmAnomaly over -Hi..+Hi (Lo ignored).
    procedure SetValues(const V: TCountyValues; AMode: TCountyColourMode; ALo, AHi: Double);
    procedure SetPlace(E, N: Double);
    function SaveToPNG(const FileName: string): Boolean;
    property Selected: Integer read FSelected write SetSelected;   // -1 none
    property OnSelectCounty: TSelectCountyEvent read FOnSelectCounty write FOnSelectCounty;
  end;

// The colour of value V on the scale (see the unit header).
function CountyColour(Mode: TCountyColourMode; V, Lo, Hi: Double): TColor;

implementation

const
  MarginPx = 8;

type
  TRGB = record r, g, b: Byte; end;

const
  // sequential: ColorBrewer YlGnBu
  SeqStops: array[0..6] of TRGB = (
    (r: 255; g: 255; b: 217), (r: 199; g: 233; b: 180), (r: 127; g: 205; b: 187),
    (r: 65; g: 182; b: 196), (r: 29; g: 145; b: 192), (r: 34; g: 94; b: 168),
    (r: 12; g: 44; b: 132));
  // diverging, from 0 (white) outwards: browns for negative, blues for positive
  BrownStops: array[0..5] of TRGB = (
    (r: 255; g: 255; b: 255), (r: 246; g: 232; b: 195), (r: 223; g: 194; b: 125),
    (r: 191; g: 129; b: 45), (r: 140; g: 81; b: 10), (r: 84; g: 48; b: 5));
  BlueStops: array[0..5] of TRGB = (
    (r: 255; g: 255; b: 255), (r: 209; g: 229; b: 240), (r: 146; g: 197; b: 222),
    (r: 67; g: 147; b: 195), (r: 33; g: 102; b: 172), (r: 5; g: 48; b: 97));

function Ramp(const Stops: array of TRGB; t: Double): TColor;
var
  i: Integer;
  f: Double;
begin
  t := EnsureRange(t, 0, 1) * High(Stops);
  i := Min(Trunc(t), High(Stops) - 1);
  f := t - i;
  result := RGBToColor(Round(Stops[i].r + f * (Stops[i + 1].r - Stops[i].r)),
                       Round(Stops[i].g + f * (Stops[i + 1].g - Stops[i].g)),
                       Round(Stops[i].b + f * (Stops[i + 1].b - Stops[i].b)));
end;

function CountyColour(Mode: TCountyColourMode; V, Lo, Hi: Double): TColor;
begin
  if IsNan(V) then Exit(RGBToColor(215, 215, 215));
  if Mode = cmTotal then
    result := Ramp(SeqStops, (V - Lo) / Max(Hi - Lo, 1e-9))
  else if V >= 0 then
    result := Ramp(BlueStops, V / Max(Hi, 1e-9))
  else
    result := Ramp(BrownStops, -V / Max(Hi, 1e-9));
end;

procedure GLColour(C: TColor);
begin
  C := ColorToRGB(C);
  glColor3ub(C and $FF, (C shr 8) and $FF, (C shr 16) and $FF);
end;

{ TCountyMapView }

constructor TCountyMapView.Create(TheOwner: TComponent);
var
  c, k: Integer;
begin
  inherited Create(TheOwner);
  StencilBits := 8;
  FSelected := -1;
  FMode := cmTotal;
  FEMin := CountyPtE[0]; FEMax := FEMin;
  FNMin := CountyPtN[0]; FNMax := FNMin;
  for k := 0 to CountyPointCount - 1 do begin
    FEMin := Min(FEMin, CountyPtE[k]); FEMax := Max(FEMax, CountyPtE[k]);
    FNMin := Min(FNMin, CountyPtN[k]); FNMax := Max(FNMax, CountyPtN[k]);
  end;
  // Ireland/Man widen the view westwards
  for k := 0 to High(CtxE) do begin
    FEMin := Min(FEMin, CtxE[k]);
    FNMin := Min(FNMin, CtxN[k]);
  end;
  for c := 0 to CountyCount - 1 do begin
    k := CountyRingStart[CountyRingFirst[c]];
    FBoxE0[c] := CountyPtE[k]; FBoxE1[c] := CountyPtE[k];
    FBoxN0[c] := CountyPtN[k]; FBoxN1[c] := CountyPtN[k];
    for k := CountyRingStart[CountyRingFirst[c]] to CountyRingStart[CountyRingFirst[c + 1]] - 1 do begin
      FBoxE0[c] := Min(FBoxE0[c], CountyPtE[k]); FBoxE1[c] := Max(FBoxE1[c], CountyPtE[k]);
      FBoxN0[c] := Min(FBoxN0[c], CountyPtN[k]); FBoxN1[c] := Max(FBoxN1[c], CountyPtN[k]);
    end;
  end;
end;

procedure TCountyMapView.SetValues(const V: TCountyValues; AMode: TCountyColourMode;
  ALo, AHi: Double);
begin
  FValues := V;
  FHasValues := True;
  FMode := AMode;
  FLo := ALo;
  FHi := AHi;
  Invalidate;
end;

procedure TCountyMapView.SetPlace(E, N: Double);
begin
  FPlaceE := E;
  FPlaceN := N;
  FHasPlace := True;
  Invalidate;
end;

procedure TCountyMapView.SetSelected(AValue: Integer);
begin
  if FSelected = AValue then Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TCountyMapView.FitView;
begin
  FScale := Min((Width - 2 * MarginPx) / (FEMax - FEMin), (Height - 2 * MarginPx) / (FNMax - FNMin));
  FOffX := (Width - (FEMax - FEMin) * FScale) / 2;
  FOffY := (Height - (FNMax - FNMin) * FScale) / 2;
end;

procedure TCountyMapView.ToPixel(E, N: Double; out PX, PY: Double);
begin
  PX := FOffX + (E - FEMin) * FScale;
  PY := FOffY + (N - FNMin) * FScale;
end;

function TCountyMapView.RenderScene: Boolean;
var
  c, r, k: Integer;
  px, py, x0, y0, x1, y1: Double;
  i: Integer;
  a: Double;

  procedure StencilRing(First, Last: Integer; const E, N: array of Single);
  var
    j: Integer;
  begin
    glBegin(GL_TRIANGLE_FAN);
      for j := First to Last do begin
        ToPixel(E[j], N[j], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;

  procedure FillStencilled(AColour: TColor; BE0, BN0, BE1, BN1: Double);
  begin
    glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glStencilFunc(GL_NOTEQUAL, 0, $FF);
    glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);        // and clear it for the next one
    GLColour(AColour);
    ToPixel(BE0, BN0, x0, y0);
    ToPixel(BE1, BN1, x1, y1);
    glBegin(GL_QUADS);
      glVertex2d(x0 - 1, y0 - 1); glVertex2d(x1 + 1, y0 - 1);
      glVertex2d(x1 + 1, y1 + 1); glVertex2d(x0 - 1, y1 + 1);
    glEnd;
  end;

  procedure BeginStencil;
  begin
    glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
    glStencilFunc(GL_ALWAYS, 0, $FF);
    glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
  end;

begin
  result := False;
  if (Width = 0) or (Height = 0) then Exit;
  FitView;
  glViewport(0, 0, Width, Height);
  glClearColor(0.88, 0.92, 0.96, 1.0);            // sea
  glClearStencil(0);
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glDisable(GL_BLEND);
  glDisable(GL_LINE_SMOOTH);

  // ---- fills (stencil) ----
  glEnable(GL_STENCIL_TEST);
  // Ireland and Man: one grey fill for all their rings
  BeginStencil;
  for r := 0 to CtxRingCount - 1 do
    StencilRing(CtxRingStart[r], CtxRingStart[r + 1] - 1, CtxE, CtxN);
  FillStencilled(RGBToColor(222, 222, 218), FEMin, FNMin, FEMax, FNMax);
  for c := 0 to CountyCount - 1 do begin
    BeginStencil;
    for r := CountyRingFirst[c] to CountyRingFirst[c + 1] - 1 do
      StencilRing(CountyRingStart[r], CountyRingStart[r + 1] - 1, CountyPtE, CountyPtN);
    if FHasValues then
      FillStencilled(CountyColour(FMode, FValues[c], FLo, FHi), FBoxE0[c], FBoxN0[c], FBoxE1[c], FBoxN1[c])
    else
      FillStencilled(RGBToColor(235, 235, 235), FBoxE0[c], FBoxN0[c], FBoxE1[c], FBoxN1[c]);
  end;
  glDisable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

  // ---- outlines ----
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_LINE_SMOOTH);
  glLineWidth(1.0);
  glColor4f(0.55, 0.55, 0.55, 1);
  for r := 0 to CtxRingCount - 1 do begin
    glBegin(GL_LINE_LOOP);
      for k := CtxRingStart[r] to CtxRingStart[r + 1] - 1 do begin
        ToPixel(CtxE[k], CtxN[k], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;
  glColor4f(0.25, 0.25, 0.28, 0.75);
  glLineWidth(0.8);
  for r := 0 to CountyRingCount - 1 do begin
    glBegin(GL_LINE_LOOP);
      for k := CountyRingStart[r] to CountyRingStart[r + 1] - 1 do begin
        ToPixel(CountyPtE[k], CountyPtN[k], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;
  if (FSelected >= 0) and (FSelected < CountyCount) then begin
    glColor4f(0, 0, 0, 1);
    glLineWidth(2.5);
    for r := CountyRingFirst[FSelected] to CountyRingFirst[FSelected + 1] - 1 do begin
      glBegin(GL_LINE_LOOP);
        for k := CountyRingStart[r] to CountyRingStart[r + 1] - 1 do begin
          ToPixel(CountyPtE[k], CountyPtN[k], px, py);
          glVertex2d(px, py);
        end;
      glEnd;
    end;
  end;
  glDisable(GL_LINE_SMOOTH);

  // ---- the selected place ----
  if FHasPlace then begin
    ToPixel(FPlaceE, FPlaceN, x0, y0);
    glColor3ub(220, 0, 0);
    glBegin(GL_TRIANGLE_FAN);
      glVertex2d(x0, y0);
      for i := 0 to 20 do begin
        a := 2 * Pi * i / 20;
        glVertex2d(x0 + 5 * Cos(a), y0 + 5 * Sin(a));
      end;
    glEnd;
    glColor3ub(0, 0, 0);
    glLineWidth(1.0);
    glBegin(GL_LINE_LOOP);
      for i := 0 to 19 do begin
        a := 2 * Pi * i / 20;
        glVertex2d(x0 + 5 * Cos(a), y0 + 5 * Sin(a));
      end;
    glEnd;
  end;
  result := True;
end;

procedure TCountyMapView.Paint;
begin
  if not MakeCurrent then Exit;
  if RenderScene then SwapBuffers;
end;

procedure TCountyMapView.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TCountyMapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  c: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FitView;
  c := CountyAt(FEMin + (X - FOffX) / FScale, FNMin + (Height - Y - FOffY) / FScale);
  if c >= 0 then begin
    Selected := c;
    if Assigned(FOnSelectCounty) then FOnSelectCounty(Self, c);
  end;
end;

function TCountyMapView.SaveToPNG(const FileName: string): Boolean;
var
  W, H, x, y, o: Integer;
  Buf: array of Byte;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  col: TFPColor;
begin
  result := False;
  if not HandleAllocated or not MakeCurrent then Exit;
  if not RenderScene then Exit;
  W := Width;
  H := Height;
  SetLength(Buf, W * H * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadBuffer(GL_BACK);
  glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, @Buf[0]);
  Img := TFPMemoryImage.Create(W, H);
  Writer := TFPWriterPNG.Create;
  try
    Writer.UseAlpha := False;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do begin
        o := ((H - 1 - y) * W + x) * 4;
        col.red := Buf[o] * 257;
        col.green := Buf[o + 1] * 257;
        col.blue := Buf[o + 2] * 257;
        col.alpha := alphaOpaque;
        Img.Colors[x, y] := col;
      end;
    Img.SaveToFile(FileName, Writer);
    result := True;
  finally
    Writer.Free;
    Img.Free;
  end;
  Invalidate;
end;

end.
