unit uLVView;

{ The finite-element left ventricle in motion, in OpenGL, for LVView.

  The wall's hexahedra are drawn at the current frame's displacements,
  true size (no exaggeration: the motion is large). Part of the wall can
  be cut away - a quarter or a half, by leaving out the elements of that
  sector - so the cavity, the wall's thickening and the long axis's
  shortening are seen; the cut follows the material, so it turns with
  the wall's twist. The surface is coloured by each element's sarcomere
  length (ls0 x fibre stretch) or active fibre stress, averaged to the
  nodes, on a scale fixed over the beat; or plainly.

  The long axis is upright with the apex down and the open base (the
  valve plane, which the model keeps flat) on top. Drag to turn, wheel
  to zoom. Shading is a headlamp computed per vertex here, with |n . L|
  so a surface is lit from whichever side is seen; endocardium and
  epicardium are shaded smoothly, the base and the cut faces flat. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  FPImage, FPWritePNG,
  GL, GLU, OpenGLContext,
  uLVAnim;

type
  TLVColourMode = (cmSarcomere, cmActive, cmPlain);
  TLVCut = (cutNone, cutQuarter, cutHalf);

  TLVFace = record
    N: array[0..3] of Integer;
    Kind: Integer;   { 0 endocardium, 1 epicardium, 2 flat (base, cut) }
  end;

  TLVView = class(TOpenGLControl)
  private
    FAnim: TLVAnim;
    FFrame: Integer;
    FMode: TLVColourMode;
    FCut: TLVCut;
    FShowEdges: Boolean;
    FYaw, FPitch, FDistance: Double;
    FDragging: Boolean;
    FLastX, FLastY: Integer;
    FFaces: array of TLVFace;
    procedure SetFrame(V: Integer);
    procedure SetMode(V: TLVColourMode);
    procedure SetCut(V: TLVCut);
    procedure SetShowEdges(V: Boolean);
    procedure BuildFaces;
    function Drawn(k: Integer): Boolean;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetAnim(A: TLVAnim);
    procedure ResetView;
    function RenderScene: Boolean;
    procedure Paint; override;
    function SaveToPNG(const FileName: string): Boolean;
    property Frame: Integer read FFrame write SetFrame;
    property ColourMode: TLVColourMode read FMode write SetMode;
    property Cut: TLVCut read FCut write SetCut;
    property ShowEdges: Boolean read FShowEdges write SetShowEdges;
  end;

{ the colour at fraction v (0 .. 1) of a mode's scale }
procedure MapColour(Mode: TLVColourMode; v: Double; out R, G, B: Single);

implementation

const
  DefaultYaw = -12.0;
  DefaultPitch = 18.0;
  DefaultDistance = 235.0;

  { matplotlib's RdBu_r: short sarcomeres blue, long red }
  RdBu: array[0..10, 0..2] of Byte = (
    ($05, $30, $61), ($21, $66, $AC), ($43, $93, $C3), ($92, $C5, $DE),
    ($D1, $E5, $F0), ($F7, $F7, $F7), ($FD, $DB, $C7), ($F4, $A5, $82),
    ($D6, $60, $4D), ($B2, $18, $2B), ($67, $00, $1F));
  { ColorBrewer's YlOrRd, from a pale relaxed wall }
  YlOrRd: array[0..8, 0..2] of Byte = (
    ($F2, $E6, $D8), ($FF, $ED, $A0), ($FE, $D9, $76), ($FE, $B2, $4C),
    ($FD, $8D, $3C), ($FC, $4E, $2A), ($E3, $1A, $1C), ($BD, $00, $26),
    ($80, $00, $26));
  Flesh: array[0..2] of Single = (0.80, 0.36, 0.33);

procedure MapColour(Mode: TLVColourMode; v: Double; out R, G, B: Single);
var
  s, f: Double;
  i: Integer;
begin
  v := EnsureRange(v, 0, 1);
  case Mode of
    cmSarcomere:
      begin
        s := v * 10;
        i := Min(Floor(s), 9);
        f := s - i;
        R := ((1 - f) * RdBu[i, 0] + f * RdBu[i + 1, 0]) / 255;
        G := ((1 - f) * RdBu[i, 1] + f * RdBu[i + 1, 1]) / 255;
        B := ((1 - f) * RdBu[i, 2] + f * RdBu[i + 1, 2]) / 255;
      end;
    cmActive:
      begin
        s := v * 8;
        i := Min(Floor(s), 7);
        f := s - i;
        R := ((1 - f) * YlOrRd[i, 0] + f * YlOrRd[i + 1, 0]) / 255;
        G := ((1 - f) * YlOrRd[i, 1] + f * YlOrRd[i + 1, 1]) / 255;
        B := ((1 - f) * YlOrRd[i, 2] + f * YlOrRd[i + 1, 2]) / 255;
      end;
  else
    R := Flesh[0]; G := Flesh[1]; B := Flesh[2];
  end;
end;

constructor TLVView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FCut := cutHalf;
  FShowEdges := True;
  ResetView;
end;

procedure TLVView.ResetView;
begin
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  Invalidate;
end;

{ The sector left out is centred on the model's -y, which faces the
  viewer at yaw 0. }
function TLVView.Drawn(k: Integer): Boolean;
var
  n, k0: Integer;
begin
  case FCut of
    cutQuarter: n := FAnim.NC div 4;
    cutHalf: n := FAnim.NC div 2;
  else
    n := 0;
  end;
  k0 := (3 * FAnim.NC) div 4 - n div 2;
  k := ((k - k0) mod FAnim.NC + FAnim.NC) mod FAnim.NC;
  Result := k >= n;
end;

procedure TLVView.BuildFaces;
var
  i, j, k, nf: Integer;

  procedure Add(a, b, c, d, Kind: Integer);
  begin
    if nf = Length(FFaces) then SetLength(FFaces, 2 * nf + 64);
    FFaces[nf].N[0] := a; FFaces[nf].N[1] := b; FFaces[nf].N[2] := c; FFaces[nf].N[3] := d;
    FFaces[nf].Kind := Kind;
    Inc(nf);
  end;

begin
  nf := 0;
  SetLength(FFaces, 0);
  if (FAnim = nil) or (FAnim.NN = 0) then Exit;
  with FAnim do
    for k := 0 to NC - 1 do
    begin
      if not Drawn(k) then Continue;
      for j := 0 to NL - 1 do
      begin
        Add(NodeId(0, j, k), NodeId(0, j, k + 1), NodeId(0, j + 1, k + 1), NodeId(0, j + 1, k), 0);
        Add(NodeId(NR, j, k), NodeId(NR, j, k + 1), NodeId(NR, j + 1, k + 1), NodeId(NR, j + 1, k), 1);
      end;
      for i := 0 to NR - 1 do
      begin
        Add(NodeId(i, NL, k), NodeId(i, NL, k + 1), NodeId(i + 1, NL, k + 1), NodeId(i + 1, NL, k), 2);
        for j := 0 to NL - 1 do
        begin
          if not Drawn(k - 1) then
            Add(NodeId(i, j, k), NodeId(i + 1, j, k), NodeId(i + 1, j + 1, k), NodeId(i, j + 1, k), 2);
          if not Drawn(k + 1) then
            Add(NodeId(i, j, k + 1), NodeId(i + 1, j, k + 1), NodeId(i + 1, j + 1, k + 1),
              NodeId(i, j + 1, k + 1), 2);
        end;
      end;
    end;
  SetLength(FFaces, nf);
end;

procedure TLVView.SetAnim(A: TLVAnim);
begin
  FAnim := A;
  FFrame := 0;
  BuildFaces;
  Invalidate;
end;

procedure TLVView.SetFrame(V: Integer);
begin
  FFrame := V;
  Invalidate;
end;

procedure TLVView.SetMode(V: TLVColourMode);
begin
  FMode := V;
  Invalidate;
end;

procedure TLVView.SetCut(V: TLVCut);
begin
  FCut := V;
  BuildFaces;
  Invalidate;
end;

procedure TLVView.SetShowEdges(V: Boolean);
begin
  FShowEdges := V;
  Invalidate;
end;

function TLVView.RenderScene: Boolean;
var
  W, H, nn, a, b, c, i, j, k, e, q, f, kind: Integer;
  P: array of Single;            { 3 nn, GL frame }
  Val, Cnt: array of Single;
  Col: array of Single;          { 3 nn }
  Nrm: array[0..1] of array of Single; { endocardium, epicardium: 3 nn }
  qn: array[0..3] of Integer;
  nv: array[0..2] of Double;
  cy, sy, cp, sp, lo, hi, v, len, sh, ex, ey, ez: Double;
  r, g, bl: Single;
  Fr: Integer;

  procedure QuadNormal(const n: array of Integer; var o: array of Double);
  var
    d1, d2: array[0..2] of Double;
    m: Integer;
  begin
    for m := 0 to 2 do
    begin
      d1[m] := P[3 * n[2] + m] - P[3 * n[0] + m];
      d2[m] := P[3 * n[3] + m] - P[3 * n[1] + m];
    end;
    o[0] := d1[1] * d2[2] - d1[2] * d2[1];
    o[1] := d1[2] * d2[0] - d1[0] * d2[2];
    o[2] := d1[0] * d2[1] - d1[1] * d2[0];
  end;

  { headlamp shading of a normal given in the GL frame }
  function Shade(nx, ny, nz: Double): Double;
  begin
    len := Sqrt(nx * nx + ny * ny + nz * nz);
    if len < 1e-12 then Exit(1);
    ex := cy * nx + sy * nz;
    ez := -sy * nx + cy * nz;
    ey := cp * ny - sp * ez;
    ez := sp * ny + cp * ez;
    Result := 0.40 + 0.60 * Abs(ex * 0.30 + ey * 0.50 + ez * 0.81) / len;
  end;

begin
  Result := False;
  W := Width;
  H := Height;
  if (W <= 0) or (H <= 0) then Exit;
  glViewport(0, 0, W, H);
  glClearColor(1, 1, 1, 1);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  Result := True;
  if (FAnim = nil) or (FAnim.Frames = 0) then Exit;
  Fr := EnsureRange(FFrame, 0, FAnim.Frames - 1);

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(30.0, W / H, 20.0, 3000.0);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glTranslated(0, 0, -FDistance);
  glRotated(FPitch, 1, 0, 0);
  glRotated(FYaw, 0, 1, 0);
  cy := Cos(DegToRad(FYaw)); sy := Sin(DegToRad(FYaw));
  cp := Cos(DegToRad(FPitch)); sp := Sin(DegToRad(FPitch));

  { model (x, y, z) -> GL (x, z, -y): the long axis upright }
  nn := FAnim.NN;
  SetLength(P, 3 * nn);
  for a := 0 to nn - 1 do
  begin
    P[3 * a] := FAnim.X[3 * a] + FAnim.U[Fr][3 * a];
    P[3 * a + 1] := FAnim.X[3 * a + 2] + FAnim.U[Fr][3 * a + 2] - FAnim.ZMid;
    P[3 * a + 2] := -(FAnim.X[3 * a + 1] + FAnim.U[Fr][3 * a + 1]);
  end;

  { node colours: the mean of the elements round each node }
  SetLength(Col, 3 * nn);
  if FMode = cmPlain then
    for a := 0 to nn - 1 do
    begin
      Col[3 * a] := Flesh[0]; Col[3 * a + 1] := Flesh[1]; Col[3 * a + 2] := Flesh[2];
    end
  else
  begin
    SetLength(Val, nn); SetLength(Cnt, nn);
    for a := 0 to nn - 1 do begin Val[a] := 0; Cnt[a] := 0; end;
    with FAnim do
      for i := 0 to NR - 1 do
        for j := 0 to NL - 1 do
          for k := 0 to NC - 1 do
          begin
            e := ElemId(i, j, k);
            if FMode = cmSarcomere then v := Lam[Fr][e] else v := Tact[Fr][e];
            for a := 0 to 1 do
              for b := 0 to 1 do
                for c := 0 to 1 do
                begin
                  q := NodeId(i + a, j + b, k + c);
                  Val[q] := Val[q] + v;
                  Cnt[q] := Cnt[q] + 1;
                end;
          end;
    if FMode = cmSarcomere then
    begin
      lo := FAnim.LamMin; hi := FAnim.LamMax;
    end
    else
    begin
      lo := 0; hi := Max(FAnim.TactMax, 1e-9);
    end;
    for a := 0 to nn - 1 do
    begin
      MapColour(FMode, (Val[a] / Max(Cnt[a], 1) - lo) / Max(hi - lo, 1e-9), r, g, bl);
      Col[3 * a] := r; Col[3 * a + 1] := g; Col[3 * a + 2] := bl;
    end;
  end;

  { smooth normals on the whole endocardium and epicardium }
  for kind := 0 to 1 do
  begin
    SetLength(Nrm[kind], 3 * nn);
    for a := 0 to 3 * nn - 1 do Nrm[kind][a] := 0;
    if kind = 0 then i := 0 else i := FAnim.NR;
    for j := 0 to FAnim.NL - 1 do
      for k := 0 to FAnim.NC - 1 do
      begin
        qn[0] := FAnim.NodeId(i, j, k); qn[1] := FAnim.NodeId(i, j, k + 1);
        qn[2] := FAnim.NodeId(i, j + 1, k + 1); qn[3] := FAnim.NodeId(i, j + 1, k);
        QuadNormal(qn, nv);
        for a := 0 to 3 do
          for b := 0 to 2 do
            Nrm[kind][3 * qn[a] + b] := Nrm[kind][3 * qn[a] + b] + nv[b];
      end;
  end;

  glEnable(GL_DEPTH_TEST);
  glDisable(GL_LIGHTING);
  glDisable(GL_CULL_FACE);
  glShadeModel(GL_SMOOTH);
  glEnable(GL_POLYGON_OFFSET_FILL);
  glPolygonOffset(1.0, 1.0);
  glBegin(GL_QUADS);
  for f := 0 to High(FFaces) do
  begin
    kind := FFaces[f].Kind;
    if kind = 2 then
    begin
      QuadNormal(FFaces[f].N, nv);
      sh := Shade(nv[0], nv[1], nv[2]);
    end;
    for a := 0 to 3 do
    begin
      q := FFaces[f].N[a];
      if kind < 2 then
        sh := Shade(Nrm[kind][3 * q], Nrm[kind][3 * q + 1], Nrm[kind][3 * q + 2]);
      glColor3f(Col[3 * q] * sh, Col[3 * q + 1] * sh, Col[3 * q + 2] * sh);
      glVertex3f(P[3 * q], P[3 * q + 1], P[3 * q + 2]);
    end;
  end;
  glEnd;
  glDisable(GL_POLYGON_OFFSET_FILL);

  if FShowEdges then
  begin
    glColor3f(0.18, 0.18, 0.18);
    glLineWidth(1);
    glBegin(GL_LINES);
    for f := 0 to High(FFaces) do
      for a := 0 to 3 do
      begin
        q := FFaces[f].N[a];
        b := FFaces[f].N[(a + 1) mod 4];
        if q = b then Continue;
        glVertex3f(P[3 * q], P[3 * q + 1], P[3 * q + 2]);
        glVertex3f(P[3 * b], P[3 * b + 1], P[3 * b + 2]);
      end;
    glEnd;
  end;
end;

procedure TLVView.Paint;
begin
  if not MakeCurrent then Exit;
  if RenderScene then SwapBuffers;
end;

function TLVView.SaveToPNG(const FileName: string): Boolean;
var
  W, H, x, y, o: Integer;
  Buf: array of Byte;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  c: TFPColor;
begin
  Result := False;
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

procedure TLVView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := True;
  FLastX := X;
  FLastY := Y;
end;

procedure TLVView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  FYaw := FYaw + (X - FLastX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastY) * 0.5, -89, 89);
  FLastX := X;
  FLastY := Y;
  Invalidate;
end;

procedure TLVView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TLVView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  FDistance := EnsureRange(FDistance * Power(0.9, WheelDelta / 120), 80, 1500);
  Invalidate;
  Result := True;
end;

end.
