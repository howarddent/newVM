unit uDefibView;

{ The torso and its current, in OpenGL.

  The torso is drawn as its skin surface in translucent red, with the
  ends at the neck and pelvis closed off, and the heart and lungs inside
  it in deeper and paler reds. The ribs, sternum and spine are
  translucent ivory, the ribs' costal cartilages bluish white. The pads
  are opaque grey. The current is
  drawn in two forms, each point coloured by which way the current
  there is flowing at this instant: yellow where it heads towards the
  apex of the heart (its component along the line to the apex is
  positive), blue where it heads away. With the 1 A solution's J at a
  point and the shock's I(t), that is the sign of I(t) J . (apex - P),
  so in the biphasic shock's second phase every colour flips. At the
  monophasic peak most of the current is yellow. It is blue where it
  leaves the top of the sternal pad upwards before turning down, and
  where it has already passed the apex, close to the apex pad.

    field lines   from the sternal pad to the apex pad, each carrying
                  the same share of the current, so where they crowd the
                  current density is high. Their brightness follows |I(t)|.
    current cloud a glowing point at the centre of every element whose
                  current density, at this instant, is above the chosen
                  level, brighter the further above it. This is what
                  visibly spreads: as I(t) rises, the region above the
                  level grows out from the pad edges into the chest, and
                  it shrinks back as I(t) falls.

  The current is drawn additively after the red, so it shows through the
  translucent torso without needing to be depth-sorted against it.

  The translucent surface is drawn in two passes - the faces turned away
  from the eye, then those turned towards it - which is exact for a
  convex body like the trunk's elliptical cylinder.

  Drag to turn, wheel to zoom. The world has the body along z, head
  towards +z, the front towards +y and the patient's left towards -x;
  the view stands the body upright, facing the viewer, so the patient's
  right is on the viewer's left as on a clinical picture. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  FPImage, FPWritePNG,
  GL, GLU, OpenGLContext,
  uDefibModel;

type

  TDefibView = class(TOpenGLControl)

  private

    FModel : TDefibModel;
    FCurrent : Double;          // A, now
    FIMax : Double;             // A, the scale for the brightness

    FYaw, FPitch, FDistance : Double;
    FDragging : Boolean;
    FLastX, FLastY : Integer;

    FShowLines : Boolean;
    FShowCloud : Boolean;
    FShowOrgans : Boolean;
    FShowBones : Boolean;
    FJLevel : Double;           // A/m2, the cloud's threshold
    FVolRef : Double;           // m3, a core element's volume
    FApex : TVec3;              // the heart's apex

    procedure DrawTorso(const Eye : TVec3);
    procedure DrawOrgan(const O : TOrgan; R, G, B, Alpha : Single);
    procedure DrawPads;
    procedure DrawSkeleton;
    procedure DrawCloud;
    procedure DrawLines;
    function Towards(const J, P : TVec3; Sg : Double) : Boolean;

    procedure SetShowLines(V : Boolean);
    procedure SetShowCloud(V : Boolean);
    procedure SetShowOrgans(V : Boolean);
    procedure SetShowBones(V : Boolean);
    procedure SetJLevel(V : Double);

  protected

    procedure MouseDown(Button : TMouseButton; Shift : TShiftState; X, Y : Integer); override;
    procedure MouseMove(Shift : TShiftState; X, Y : Integer); override;
    procedure MouseUp(Button : TMouseButton; Shift : TShiftState; X, Y : Integer); override;
    function DoMouseWheel(Shift : TShiftState; WheelDelta : Integer;
                          MousePos : TPoint) : Boolean; override;

  public

    constructor Create(AOwner : TComponent); override;

    procedure SetModel(AModel : TDefibModel);
    procedure SetCurrent(I : Double);
    procedure ResetView;

    function RenderScene : Boolean;
    procedure Paint; override;
    function SaveToPNG(const FileName : String) : Boolean;

    property ShowLines : Boolean read FShowLines write SetShowLines;
    property ShowCloud : Boolean read FShowCloud write SetShowCloud;
    property ShowOrgans : Boolean read FShowOrgans write SetShowOrgans;
    property ShowBones : Boolean read FShowBones write SetShowBones;

    // The cloud's level, A/m2.
    property JLevel : Double read FJLevel write SetJLevel;

  end;

implementation

const
  DefaultYaw = -40.0;
  DefaultPitch = 12.0;
  DefaultDistance = 1.75;

  // The cloud's brightness runs from its level to this many times it.
  CloudSpan = 10.0;

constructor TDefibView.Create(AOwner : TComponent);
begin
  inherited Create(AOwner);
  FShowLines := True;
  FShowCloud := True;
  FShowOrgans := True;
  FShowBones := True;
  FJLevel := 500.0;
  ResetView;
end;

procedure TDefibView.ResetView;
begin
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  Invalidate;
end;

procedure TDefibView.SetModel(AModel : TDefibModel);
var
  i, n : Integer;
begin
  FModel := AModel;
  FIMax := Max(AModel.IPeak, 1E-9);

  // The heart's long axis U[0] runs from base to apex.
  with AModel.Heart do
  begin
    FApex.X := C.X + R[0] * U[0].X;
    FApex.Y := C.Y + R[0] * U[0].Y;
    FApex.Z := C.Z + R[0] * U[0].Z;
  end;

  // The mean volume of a core element - the unstructured prisms that
  // fill most of the body.
  FVolRef := 0;
  n := 0;
  for i := 0 to AModel.NbEle - 1 do
    if AModel.EleTissue[i] = tiCore then
    begin
      FVolRef := FVolRef + AModel.EleVol[i];
      Inc(n);
    end;
  FVolRef := FVolRef / Max(n, 1);

  Invalidate;
end;

procedure TDefibView.SetCurrent(I : Double);
begin
  FCurrent := I;
  Invalidate;
end;

procedure TDefibView.SetShowLines(V : Boolean);
begin
  FShowLines := V;
  Invalidate;
end;

procedure TDefibView.SetShowCloud(V : Boolean);
begin
  FShowCloud := V;
  Invalidate;
end;

procedure TDefibView.SetShowOrgans(V : Boolean);
begin
  FShowOrgans := V;
  Invalidate;
end;

procedure TDefibView.SetShowBones(V : Boolean);
begin
  FShowBones := V;
  Invalidate;
end;

procedure TDefibView.SetJLevel(V : Double);
begin
  FJLevel := V;
  Invalidate;
end;

// The skin, back faces first then front, and the two end caps.
procedure TDefibView.DrawTorso(const Eye : TVec3);
var
  Pass, i, j, k : Integer;
  M : TDefibModel;
  cx, cy, cz, d, t, sh : Double;
  Ends : Array[0..1] of Double;
begin

  M := FModel;

  for Pass := 0 to 1 do
  begin

    // The caps at neck and pelvis: whichever faces away first.
    Ends[0] := 0;
    Ends[1] := M.Len;
    for k := 0 to 1 do
    begin
      d := (Eye.Z - Ends[k]) * IfThen(k = 0, -1, 1);
      if (d > 0) <> (Pass = 1) then
        Continue;
      glColor4f(0.85, 0.12, 0.12, 0.10);
      glBegin(GL_TRIANGLE_FAN);
      glVertex3d(0, M.Cy, Ends[k]);
      for j := 0 to 96 do
      begin
        t := 2 * Pi * j / 96;
        glVertex3d(M.A * Cos(t), M.Cy + M.B * Sin(t), Ends[k]);
      end;
      glEnd;
    end;

    glBegin(GL_QUADS);

    for i := 0 to Length(M.Skin) - 1 do
    begin

      cx := M.NX[M.Skin[i].N[0]];
      cy := M.NY[M.Skin[i].N[0]];
      cz := M.NZ[M.Skin[i].N[0]];
      d := (Eye.X - cx) * M.Skin[i].Nx + (Eye.Y - cy) * M.Skin[i].Ny;

      if (d > 0) <> (Pass = 1) then
        Continue;

      // A little shading from the normal against a light up and to the
      // viewer's left, so the shape reads.
      sh := 0.55 + 0.45 * Max(0, 0.5 * M.Skin[i].Nx * -1 + 0.8 * M.Skin[i].Ny);

      if Pass = 0 then
        glColor4f(0.55 * sh, 0.05, 0.05, 0.10)
      else
        glColor4f(0.95 * sh + 0.05, 0.10 * sh, 0.10 * sh, 0.16);

      for j := 0 to 3 do
        glVertex3d(M.NX[M.Skin[i].N[j]], M.NY[M.Skin[i].N[j]], M.NZ[M.Skin[i].N[j]]);

    end;

    glEnd;

  end;

end;

procedure TDefibView.DrawOrgan(const O : TOrgan; R, G, B, Alpha : Single);
const
  NLat = 18;
  NLon = 32;
var
  i, j, k, a : Integer;
  th, ph, sh : Double;
  P : TVec3;
  nx, ny, nz : Double;
begin

  glBegin(GL_QUADS);

  for i := 0 to NLat - 1 do
    for j := 0 to NLon - 1 do
      for k := 0 to 3 do
      begin

        a := i + Ord((k = 2) or (k = 3));
        th := Pi * a / NLat;
        ph := 2 * Pi * (j + Ord((k = 1) or (k = 2))) / NLon;

        nx := Sin(th) * Cos(ph);
        ny := Sin(th) * Sin(ph);
        nz := Cos(th);

        P.X := O.C.X + O.R[0] * nz * O.U[0].X + O.R[1] * nx * O.U[1].X + O.R[2] * ny * O.U[2].X;
        P.Y := O.C.Y + O.R[0] * nz * O.U[0].Y + O.R[1] * nx * O.U[1].Y + O.R[2] * ny * O.U[2].Y;
        P.Z := O.C.Z + O.R[0] * nz * O.U[0].Z + O.R[1] * nx * O.U[1].Z + O.R[2] * ny * O.U[2].Z;

        // Shade by how much the point faces the front (+y).
        sh := 0.6 + 0.4 * (nz * O.U[0].Y + nx * O.U[1].Y + ny * O.U[2].Y);
        glColor4f(R * sh, G * sh, B * sh, Alpha);
        glVertex3d(P.X, P.Y, P.Z);

      end;

  glEnd;

end;

procedure TDefibView.DrawPads;
var
  i, j : Integer;
  M : TDefibModel;
begin
  M := FModel;
  glBegin(GL_QUADS);
  for i := 0 to Length(M.PadFaces) - 1 do
  begin
    if M.PadFaces[i].Pad = PadAnode then
      glColor4f(0.80, 0.80, 0.84, 1)
    else
      glColor4f(0.68, 0.68, 0.74, 1);
    for j := 0 to 3 do
      glVertex3d(M.NX[M.PadFaces[i].N[j]] + 0.0005 * M.PadFaces[i].Nx,
                 M.NY[M.PadFaces[i].N[j]] + 0.0005 * M.PadFaces[i].Ny,
                 M.NZ[M.PadFaces[i].N[j]]);
  end;
  glEnd;
end;

// The ribs as bands round the wall's inner part, where the model has
// them, the sternum as a plate across them at the front, and the spine
// as a cylinder. Drawn from the same rules the elements were classified
// by, not from the elements, so the bands are smooth.
procedure TDefibView.DrawSkeleton;
const
  NSeg = 256;
var
  M : TDefibModel;
  k, j, sd : Integer;
  Z0, Z1, T, D, Ds, Yc, Zs0, Zs1 : Double;
  P : TVec3;
  Cart : Boolean;
begin

  M := FModel;
  D := WallThickness - RibDepth / 2;
  Ds := WallThickness - RibDepth;

  glBegin(GL_QUADS);

  // The spine, at the back, first: nothing here writes depth.
  Yc := M.Cy - M.CoreB + SpineInset;
  glColor4f(0.95, 0.92, 0.80, 0.30);
  for j := 0 to 31 do
  begin
    T := 2 * Pi * j / 32;
    glVertex3d(SpineRadius * Cos(T), Yc + SpineRadius * Sin(T), 0);
    glVertex3d(SpineRadius * Cos(T), Yc + SpineRadius * Sin(T), M.Len);
    T := 2 * Pi * (j + 1) / 32;
    glVertex3d(SpineRadius * Cos(T), Yc + SpineRadius * Sin(T), M.Len);
    glVertex3d(SpineRadius * Cos(T), Yc + SpineRadius * Sin(T), 0);
  end;

  for k := 0 to NbRibs - 1 do
  begin
    M.RibBand(k, Z0, Z1);
    for j := 0 to NSeg - 1 do
    begin
      T := 2 * Pi * (j + 0.5) / NSeg;
      P := M.WallPoint(T, D);
      if not M.RibPresent(k, P.X, P.Y) then
        Continue;
      if (P.Y > M.Cy) and (Abs(P.X) < SternumHalfWidth) and
         (M.Len - Z1 >= SternumTop) and (M.Len - Z0 <= SternumBottom) then
        Continue;
      Cart := M.RibCartilage(k, P.X, P.Y);
      if Cart then
        glColor4f(0.70, 0.80, 0.95, 0.30)
      else
        glColor4f(0.95, 0.92, 0.80, 0.45);
      P := M.WallPoint(2 * Pi * j / NSeg, D);
      glVertex3d(P.X, P.Y, Z0);
      glVertex3d(P.X, P.Y, Z1);
      P := M.WallPoint(2 * Pi * (j + 1) / NSeg, D);
      glVertex3d(P.X, P.Y, Z1);
      glVertex3d(P.X, P.Y, Z0);
    end;
  end;

  // The sternum: its front and back faces across the wall's rib layer.
  Zs0 := M.Len - SternumBottom;
  Zs1 := M.Len - SternumTop;
  glColor4f(0.95, 0.92, 0.80, 0.40);
  for sd := 0 to 1 do
  begin
    P := M.WallPoint(Pi / 2, IfThen(sd = 0, Ds, WallThickness));
    glVertex3d(-SternumHalfWidth, P.Y, Zs0);
    glVertex3d(SternumHalfWidth, P.Y, Zs0);
    glVertex3d(SternumHalfWidth, P.Y, Zs1);
    glVertex3d(-SternumHalfWidth, P.Y, Zs1);
  end;

  glEnd;

end;

// Elements above the level, largest |J| first so the loop stops at the
// first one below it.
procedure TDefibView.DrawCloud;
var
  k, e : Integer;
  M : TDefibModel;
  I, Jn, a, Span, Sg : Double;
begin

  M := FModel;
  Sg := Sign(FCurrent);
  I := Abs(FCurrent);
  if (I <= 0) or (FJLevel <= 0) then
    Exit;

  Span := Ln(CloudSpan);

  glPointSize(3.0);
  glBegin(GL_POINTS);

  for k := 0 to M.NbEle - 1 do
  begin
    e := M.EleByJ[k];
    Jn := M.EleJMag[e] * I;
    if Jn < FJLevel then
      Break;
    a := EnsureRange(Ln(Jn / FJLevel) / Span, 0, 1);
    // Weighted by the element's volume, so the brightness is the
    // volume of tissue above the level and the millimetre-thin skin
    // and fat elements do not paint bands at every axial layer.
    a := (0.05 + 0.30 * a) * Min(1.0, M.EleVol[e] / FVolRef);
    if Towards(M.EleJ[e], M.EleC[e], Sg) then
      glColor4f(1.0 * a, 0.85 * a, 0.10 * a, 1)
    else
      glColor4f(0.20 * a, 0.50 * a, 1.0 * a, 1);
    glVertex3d(M.EleC[e].X, M.EleC[e].Y, M.EleC[e].Z);
  end;

  glEnd;

end;

// Whether current density J (for 1 A) at P, times the sign Sg of the
// shock current, has a positive component towards the heart's apex.
function TDefibView.Towards(const J, P : TVec3; Sg : Double) : Boolean;
begin
  Result := Sg * (J.X * (FApex.X - P.X) + J.Y * (FApex.Y - P.Y) +
                  J.Z * (FApex.Z - P.Z)) > 0;
end;

// The lines were traced along J for +1 A, so each runs in the direction
// of flow; a segment's direction stands in for J at its midpoint.
procedure TDefibView.DrawLines;
var
  k, j : Integer;
  M : TDefibModel;
  a, Sg : Double;
  P0, P1, D, Mid : TVec3;
begin

  M := FModel;
  a := 0.6 * Abs(FCurrent) / FIMax;
  if a <= 0.003 then
    Exit;
  Sg := Sign(FCurrent);

  glLineWidth(1.6);
  glBegin(GL_LINES);

  for k := 0 to Length(M.Lines) - 1 do
    for j := 0 to Length(M.Lines[k]) - 2 do
    begin
      P0 := M.Lines[k][j];
      P1 := M.Lines[k][j + 1];
      D.X := P1.X - P0.X;
      D.Y := P1.Y - P0.Y;
      D.Z := P1.Z - P0.Z;
      Mid.X := (P0.X + P1.X) / 2;
      Mid.Y := (P0.Y + P1.Y) / 2;
      Mid.Z := (P0.Z + P1.Z) / 2;
      if Towards(D, Mid, Sg) then
        glColor4f(1.0 * a, 0.92 * a, 0.25 * a, 1)
      else
        glColor4f(0.25 * a, 0.55 * a, 1.0 * a, 1);
      glVertex3d(P0.X, P0.Y, P0.Z);
      glVertex3d(P1.X, P1.Y, P1.Z);
    end;

  glEnd;

  glLineWidth(1.0);

end;

function TDefibView.RenderScene : Boolean;
var
  MV : Array[0..15] of GLdouble;
  Eye : TVec3;
  W, H : Integer;
begin

  Result := False;
  W := Width;
  H := Height;
  if (W <= 0) or (H <= 0) then
    Exit;

  glViewport(0, 0, W, H);
  glClearColor(0.04, 0.04, 0.07, 1);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);

  if FModel = nil then
  begin
    Result := True;
    Exit;
  end;

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(35.0, W / H, 0.05, 20.0);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glTranslated(0, 0, -FDistance);
  glRotated(FPitch, 1, 0, 0);
  glRotated(FYaw, 0, 1, 0);
  // Stand the body up (z to screen up) facing the viewer (+y towards
  // the eye), then centre it.
  glRotated(180, 0, 1, 0);
  glRotated(-90, 1, 0, 0);
  glTranslated(0, -FModel.Cy, -FModel.Len / 2);

  // The eye in world coordinates, for ordering the translucent faces.
  glGetDoublev(GL_MODELVIEW_MATRIX, @MV[0]);
  Eye.X := -(MV[0] * MV[12] + MV[1] * MV[13] + MV[2] * MV[14]);
  Eye.Y := -(MV[4] * MV[12] + MV[5] * MV[13] + MV[6] * MV[14]);
  Eye.Z := -(MV[8] * MV[12] + MV[9] * MV[13] + MV[10] * MV[14]);

  glDisable(GL_LIGHTING);
  glDisable(GL_CULL_FACE);
  glEnable(GL_DEPTH_TEST);
  glDepthMask(GL_TRUE);
  glDisable(GL_BLEND);

  DrawPads;

  // Translucent tissue, without writing depth.
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDepthMask(GL_FALSE);

  if FShowOrgans then
  begin
    DrawOrgan(FModel.Lungs[0], 1.0, 0.55, 0.60, 0.10);
    DrawOrgan(FModel.Lungs[1], 1.0, 0.55, 0.60, 0.10);
    DrawOrgan(FModel.Heart, 0.95, 0.10, 0.15, 0.45);
  end;

  if FShowBones then
    DrawSkeleton;

  DrawTorso(Eye);

  // The current, added on top.
  glBlendFunc(GL_ONE, GL_ONE);

  if FShowCloud then
    DrawCloud;

  if FShowLines then
    DrawLines;

  // The heart once more, over the current, so it stays visible through
  // the current at its peak - as a red tint, turning the yellow through
  // it orange.
  if FShowOrgans then
  begin
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    DrawOrgan(FModel.Heart, 0.95, 0.05, 0.10, 0.30);
  end;

  glDepthMask(GL_TRUE);
  glDisable(GL_BLEND);

  Result := True;

end;

procedure TDefibView.Paint;
begin
  if not MakeCurrent then
    Exit;
  if RenderScene then
    SwapBuffers;
end;

function TDefibView.SaveToPNG(const FileName : String) : Boolean;
var
  W, H, x, y, o : Integer;
  Buf : Array of Byte;
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

procedure TDefibView.MouseDown(Button : TMouseButton; Shift : TShiftState; X, Y : Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := True;
  FLastX := X;
  FLastY := Y;
end;

procedure TDefibView.MouseMove(Shift : TShiftState; X, Y : Integer);
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

procedure TDefibView.MouseUp(Button : TMouseButton; Shift : TShiftState; X, Y : Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TDefibView.DoMouseWheel(Shift : TShiftState; WheelDelta : Integer;
                                 MousePos : TPoint) : Boolean;
begin
  FDistance := EnsureRange(FDistance * Power(0.9, WheelDelta / 120), 0.3, 5.0);
  Invalidate;
  Result := True;
end;

end.
