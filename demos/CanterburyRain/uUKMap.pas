unit uUKMap;

{*******************************************************************************

     TUKMapView - a small OpenGL (TOpenGLControl) outline map of the United
     Kingdom and Ireland for the CanterburyRain demo's location panel.

     Draws the coastline and land-border rings of uPlaces' outline table
     over a pale sea, every place in the location table as a small grey
     dot, and the selected place (Selected) as a larger red dot with a
     black rim. Clicking near a dot selects that place and fires
     OnSelectPlace, so the map works as a second way of choosing.

     PROJECTION: plain equirectangular with the longitude scaled by
     cos(54.5 deg) - the middle of the islands - so shapes are right there
     and within a few percent at either end; fitted to the control with
     equal x/y scale and a small margin, re-fitted on every paint.

     Like TVMPlot2D, Paint is MakeCurrent + RenderScene + SwapBuffers, and
     SaveToPNG renders and reads the back buffer back before any swap, so
     the map can be saved without a screen capture.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  FPImage, FPWritePNG,
  GL, OpenGLContext,
  uPlaces;

type
  TSelectPlaceEvent = procedure(Sender: TObject; Index: Integer) of object;

  { TUKMapView }

  TUKMapView = class(TOpenGLControl)
  private
    FSelected: Integer;
    FOnSelectPlace: TSelectPlaceEvent;
    FLonMin, FLonMax, FLatMin, FLatMax: Double;
    FScale, FOffX, FOffY: Double;     // projected degrees -> pixels
    procedure SetSelected(AValue: Integer);
    procedure FitView;
    procedure ToPixel(Lon, Lat: Double; out PX, PY: Double);
    function RenderScene: Boolean;
    procedure DrawDot(PX, PY, R: Double; Fill: TColor);
  protected
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(TheOwner: TComponent); override;
    procedure Paint; override;
    procedure Resize; override;
    function SaveToPNG(const FileName: string): Boolean;
    // Index into uPlaces.Places, or -1 for none
    property Selected: Integer read FSelected write SetSelected;
    property OnSelectPlace: TSelectPlaceEvent read FOnSelectPlace write FOnSelectPlace;
  end;

implementation

const
  MidLat = 54.5;          // projection reference latitude
  MarginPx = 8;
  ClickRadiusPx = 10;     // how close a click must be to a dot to select it

constructor TUKMapView.Create(TheOwner: TComponent);
var
  i: Integer;
begin
  inherited Create(TheOwner);
  FSelected := -1;
  FLonMin := OutlineLon[0]; FLonMax := FLonMin;
  FLatMin := OutlineLat[0]; FLatMax := FLatMin;
  for i := 1 to OutlinePointCount - 1 do begin
    FLonMin := Min(FLonMin, OutlineLon[i]); FLonMax := Max(FLonMax, OutlineLon[i]);
    FLatMin := Min(FLatMin, OutlineLat[i]); FLatMax := Max(FLatMax, OutlineLat[i]);
  end;
end;

procedure TUKMapView.SetSelected(AValue: Integer);
begin
  if FSelected = AValue then Exit;
  FSelected := AValue;
  Invalidate;
end;

// Equal x/y scale (in projected degrees) that fits the outline's bounds
// into the control, centred.
procedure TUKMapView.FitView;
var
  w, h: Double;
begin
  w := (FLonMax - FLonMin) * Cos(DegToRad(MidLat));
  h := FLatMax - FLatMin;
  FScale := Min((Width - 2 * MarginPx) / w, (Height - 2 * MarginPx) / h);
  FOffX := (Width - w * FScale) / 2;
  FOffY := (Height - h * FScale) / 2;
end;

procedure TUKMapView.ToPixel(Lon, Lat: Double; out PX, PY: Double);
begin
  PX := FOffX + (Lon - FLonMin) * Cos(DegToRad(MidLat)) * FScale;
  PY := FOffY + (Lat - FLatMin) * FScale;      // GL pixel space: y up
end;

procedure TUKMapView.DrawDot(PX, PY, R: Double; Fill: TColor);
const
  Segs = 20;
var
  i: Integer;
  a: Double;
  c: TColor;
begin
  c := ColorToRGB(Fill);
  glColor3ub(c and $FF, (c shr 8) and $FF, (c shr 16) and $FF);
  glBegin(GL_TRIANGLE_FAN);
    glVertex2d(PX, PY);
    for i := 0 to Segs do begin
      a := 2 * Pi * i / Segs;
      glVertex2d(PX + R * Cos(a), PY + R * Sin(a));
    end;
  glEnd;
  glColor3ub(0, 0, 0);
  glLineWidth(1.0);
  glBegin(GL_LINE_LOOP);
    for i := 0 to Segs - 1 do begin
      a := 2 * Pi * i / Segs;
      glVertex2d(PX + R * Cos(a), PY + R * Sin(a));
    end;
  glEnd;
end;

function TUKMapView.RenderScene: Boolean;
var
  r, i: Integer;
  px, py: Double;
begin
  result := False;
  if (Width = 0) or (Height = 0) then Exit;
  FitView;

  glViewport(0, 0, Width, Height);
  glClearColor(0.90, 0.94, 0.98, 1.0);          // pale sea
  glClear(GL_COLOR_BUFFER_BIT);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_LINE_SMOOTH);
  glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);

  // coastline and the land border
  glColor3f(0.25, 0.30, 0.35);
  glLineWidth(1.2);
  for r := 0 to OutlineRingCount - 1 do begin
    glBegin(GL_LINE_LOOP);
      for i := OutlineStart[r] to OutlineStart[r + 1] - 1 do begin
        ToPixel(OutlineLon[i], OutlineLat[i], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;

  // every place, then the selected one on top
  glEnable(GL_POINT_SMOOTH);
  glPointSize(3.5);
  glColor3f(0.55, 0.55, 0.60);
  glBegin(GL_POINTS);
    for i := 0 to PlaceCount - 1 do begin
      ToPixel(Places[i].Lon, Places[i].Lat, px, py);
      glVertex2d(px, py);
    end;
  glEnd;
  glDisable(GL_POINT_SMOOTH);
  if (FSelected >= 0) and (FSelected < PlaceCount) then begin
    ToPixel(Places[FSelected].Lon, Places[FSelected].Lat, px, py);
    DrawDot(px, py, 6, clRed);
  end;
  result := True;
end;

procedure TUKMapView.Paint;
begin
  if not MakeCurrent then Exit;
  if RenderScene then SwapBuffers;
end;

procedure TUKMapView.Resize;
begin
  inherited Resize;
  Invalidate;
end;

// Selects the place whose dot is nearest the click, if within
// ClickRadiusPx. Mouse y runs down, GL pixel y up.
procedure TUKMapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  i, Best: Integer;
  px, py, d, BestD: Double;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FitView;
  Best := -1;
  BestD := ClickRadiusPx;
  for i := 0 to PlaceCount - 1 do begin
    ToPixel(Places[i].Lon, Places[i].Lat, px, py);
    d := Hypot(px - X, py - (Height - Y));
    if d <= BestD then begin
      BestD := d;
      Best := i;
    end;
  end;
  if (Best >= 0) and (Best <> FSelected) then begin
    Selected := Best;
    if Assigned(FOnSelectPlace) then FOnSelectPlace(Self, Best);
  end;
end;

function TUKMapView.SaveToPNG(const FileName: string): Boolean;
var
  W, H, x, y, o: Integer;
  Buf: array of Byte;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  c: TFPColor;
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
        c.red := Buf[o] * 257;
        c.green := Buf[o + 1] * 257;
        c.blue := Buf[o + 2] * 257;
        c.alpha := alphaOpaque;
        Img.Colors[x, y] := c;
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
