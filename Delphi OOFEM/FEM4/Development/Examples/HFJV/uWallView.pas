unit uWallView;

{ The abdominal cavity and its moving surfaces, in OpenGL, for HFJVView.

  The cavity's boundary is drawn as an opaque surface. The anterior wall
  and the diaphragm are pushed out along their outward normals by the
  displacement at the current frame, exaggerated, and coloured by it on
  a red-white-blue map (red outwards, blue inwards, white still; the
  colour scale is the largest displacement over the cycle, so it stays
  fixed while the animation runs). The rigid surfaces - back, flanks,
  pelvis, the rib band - are grey. This is anim_wall.py's picture.

  The view starts with the body lying supine and seen from the
  patient's left, a little from the feet and above: the front of the
  body up, the head to the right. Drag to turn,
  wheel to zoom. Shading is a headlamp computed per vertex here, with
  |n . L| so a surface is lit from whichever side is seen. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  FPImage, FPWritePNG,
  GL, GLU, OpenGLContext,
  uWallAnim;

type

  TWallView = class(TOpenGLControl)
  private
    FAnim : TWallAnim;
    FFrame : Integer;
    FExag : Double;
    FShowEdges : Boolean;
    FYaw, FPitch, FDistance : Double;
    FDragging : Boolean;
    FLastX, FLastY : Integer;
    procedure SetFrame(V : Integer);
    procedure SetExag(V : Double);
    procedure SetShowEdges(V : Boolean);
  protected
    procedure MouseDown(Button : TMouseButton; Shift : TShiftState; X, Y : Integer); override;
    procedure MouseMove(Shift : TShiftState; X, Y : Integer); override;
    procedure MouseUp(Button : TMouseButton; Shift : TShiftState; X, Y : Integer); override;
    function DoMouseWheel(Shift : TShiftState; WheelDelta : Integer;
                          MousePos : TPoint) : Boolean; override;
  public
    constructor Create(AOwner : TComponent); override;
    procedure SetAnim(A : TWallAnim);
    procedure ResetView;
    function RenderScene : Boolean;
    procedure Paint; override;
    function SaveToPNG(const FileName : String) : Boolean;
    property Frame : Integer read FFrame write SetFrame;
    // displacement drawn this many times its size
    property Exaggeration : Double read FExag write SetExag;
    property ShowEdges : Boolean read FShowEdges write SetShowEdges;
  end;

// the red-white-blue map, v in -1 .. 1 (blue in, red out)
procedure DispColour(v : Double; out R, G, B : Single);

implementation

const
  // seen from the patient's left, front up, head to the right - the
  // same way round as the midline plot (pubis left, xiphoid right)
  DefaultYaw = 205.0;
  DefaultPitch = 30.0;
  DefaultDistance = 0.85;

  // matplotlib's RdBu_r, eleven stops from -1 to 1
  Stops : array[0..10, 0..2] of Byte = (
    ($05, $30, $61), ($21, $66, $AC), ($43, $93, $C3), ($92, $C5, $DE),
    ($D1, $E5, $F0), ($F7, $F7, $F7), ($FD, $DB, $C7), ($F4, $A5, $82),
    ($D6, $60, $4D), ($B2, $18, $2B), ($67, $00, $1F));

  Rigid : array[0..2] of Single = (0.70, 0.70, 0.70);

procedure DispColour(v : Double; out R, G, B : Single);
var
  s, f : Double;
  i : Integer;
begin
  s := (EnsureRange(v, -1, 1) + 1) * 5;     // 0 .. 10
  i := Min(Floor(s), 9);
  f := s - i;
  R := ((1 - f) * Stops[i, 0] + f * Stops[i + 1, 0]) / 255;
  G := ((1 - f) * Stops[i, 1] + f * Stops[i + 1, 1]) / 255;
  B := ((1 - f) * Stops[i, 2] + f * Stops[i + 1, 2]) / 255;
end;

constructor TWallView.Create(AOwner : TComponent);
begin
  inherited Create(AOwner);
  FExag := 10;
  ResetView;
end;

procedure TWallView.ResetView;
begin
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  Invalidate;
end;

procedure TWallView.SetAnim(A : TWallAnim);
begin
  FAnim := A;
  FFrame := 0;
  Invalidate;
end;

procedure TWallView.SetFrame(V : Integer);
begin
  FFrame := V;
  Invalidate;
end;

procedure TWallView.SetExag(V : Double);
begin
  FExag := V;
  Invalidate;
end;

procedure TWallView.SetShowEdges(V : Boolean);
begin
  FShowEdges := V;
  Invalidate;
end;

function TWallView.RenderScene : Boolean;
var
  W, H, k, i, a, nn : Integer;
  // per vertex: displaced position (GL frame) and lit colour
  GX, GY, GZ : array of Single;
  CR, CG, CB, Shade : array of Single;
  cy, sy, cp, sp, nx, ny, nz, ex, ey, ez, sh, d, lim : Double;
  Lx, Ly, Lz : Double;
  r, g, b : Single;
  c : TV3;
begin
  Result := False;
  W := Width;
  H := Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  glViewport(0, 0, W, H);
  glClearColor(1, 1, 1, 1);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  Result := True;
  if (FAnim = nil) or (FAnim.NbNodes = 0) then
    Exit;

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(30.0, W / H, 0.05, 20.0);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glTranslated(0, 0, -FDistance);
  glRotated(FPitch, 1, 0, 0);
  glRotated(FYaw, 0, 1, 0);

  // The display frame is (across, along, up); the GL frame puts up on
  // screen up and the patient's right towards the eye, which leaves the
  // head on the left: GL = (-along, up, across), a proper rotation.
  c := FAnim.Centre;
  nn := FAnim.NbNodes;
  SetLength(GX, nn); SetLength(GY, nn); SetLength(GZ, nn);
  SetLength(CR, nn); SetLength(CG, nn); SetLength(CB, nn); SetLength(Shade, nn);
  cy := Cos(DegToRad(FYaw)); sy := Sin(DegToRad(FYaw));
  cp := Cos(DegToRad(FPitch)); sp := Sin(DegToRad(FPitch));
  Lx := 0.3; Ly := 0.55; Lz := 0.78;
  lim := Max(FAnim.MaxDisp, 1E-12);
  for k := 0 to nn - 1 do
  begin
    d := FAnim.D[k][FFrame];
    GX[k] := -(FAnim.P[k].Y - c.Y + FExag * d * FAnim.N[k].Y);
    GY[k] := FAnim.P[k].Z - c.Z + FExag * d * FAnim.N[k].Z;
    GZ[k] := FAnim.P[k].X - c.X + FExag * d * FAnim.N[k].X;
    // the normal in GL, then in eye space: Rx(pitch) Ry(yaw)
    nx := -FAnim.N[k].Y; ny := FAnim.N[k].Z; nz := FAnim.N[k].X;
    ex := cy * nx + sy * nz;
    ez := -sy * nx + cy * nz;
    ey := cp * ny - sp * ez;
    ez := sp * ny + cp * ez;
    sh := 0.42 + 0.58 * Abs(ex * Lx + ey * Ly + ez * Lz);
    DispColour(d / lim, r, g, b);
    CR[k] := r * sh; CG[k] := g * sh; CB[k] := b * sh;
    Shade[k] := sh;
  end;

  glEnable(GL_DEPTH_TEST);
  glDisable(GL_LIGHTING);
  glDisable(GL_CULL_FACE);
  glShadeModel(GL_SMOOTH);
  if FShowEdges then
  begin
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(1.0, 1.0);
  end;

  glBegin(GL_TRIANGLES);
  for k := 0 to FAnim.NbTris - 1 do
    for i := 0 to 2 do
    begin
      a := FAnim.Tri[3 * k + i];
      if FAnim.Surf[k] = 0 then
        glColor3f(Rigid[0] * Shade[a], Rigid[1] * Shade[a], Rigid[2] * Shade[a])
      else
        glColor3f(CR[a], CG[a], CB[a]);
      glVertex3f(GX[a], GY[a], GZ[a]);
    end;
  glEnd;

  if FShowEdges then
  begin
    glDisable(GL_POLYGON_OFFSET_FILL);
    glColor4f(0.25, 0.25, 0.25, 1);
    glLineWidth(1);
    glBegin(GL_LINES);
    for k := 0 to FAnim.NbTris - 1 do
      for i := 0 to 2 do
      begin
        a := FAnim.Tri[3 * k + i];
        glVertex3f(GX[a], GY[a], GZ[a]);
        a := FAnim.Tri[3 * k + (i + 1) mod 3];
        glVertex3f(GX[a], GY[a], GZ[a]);
      end;
    glEnd;
  end;
end;

procedure TWallView.Paint;
begin
  if not MakeCurrent then
    Exit;
  if RenderScene then
    SwapBuffers;
end;

function TWallView.SaveToPNG(const FileName : String) : Boolean;
var
  W, H, x, y, o : Integer;
  Buf : array of Byte;
  Img : TFPMemoryImage;
  Writer : TFPWriterPNG;
  c : TFPColor;
begin
  Result := False;
  if not HandleAllocated or not MakeCurrent then
    Exit;
  if not RenderScene then
    Exit;
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
      for x := 0 to W - 1 do
      begin
        o := ((H - 1 - y) * W + x) * 4;
        c.red := Buf[o] * 257;
        c.green := Buf[o + 1] * 257;
        c.blue := Buf[o + 2] * 257;
        c.alpha := alphaOpaque;
        Img.Colors[x, y] := c;
      end;
    Img.SaveToFile(FileName, Writer);
    Result := True;
  finally
    Writer.Free;
    Img.Free;
  end;
  Invalidate;
end;

procedure TWallView.MouseDown(Button : TMouseButton; Shift : TShiftState; X, Y : Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := True;
  FLastX := X;
  FLastY := Y;
end;

procedure TWallView.MouseMove(Shift : TShiftState; X, Y : Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
    Exit;
  FYaw := FYaw + (X - FLastX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastY) * 0.5, -89, 89);
  FLastX := X;
  FLastY := Y;
  Invalidate;
end;

procedure TWallView.MouseUp(Button : TMouseButton; Shift : TShiftState; X, Y : Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TWallView.DoMouseWheel(Shift : TShiftState; WheelDelta : Integer;
                                MousePos : TPoint) : Boolean;
begin
  FDistance := EnsureRange(FDistance * Power(0.9, WheelDelta / 120), 0.2, 5.0);
  Invalidate;
  Result := True;
end;

end.
