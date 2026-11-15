{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

unit uSpineView;

{*******************************************************************************

  The 3-D view of GlassSpine: the two dural sacs as glass tubes with the
  injectate inside, ray-marched in a GLSL fragment shader through two 3-D
  textures - the concentration (read back from OpenCL every frame) and the
  geometry (inside the dura, the cord, level rings). No CL-GL sharing:
  the read-back is 2.6 MB a frame, far below what the bus carries, and it
  works whichever GPU OpenGL happens to be on.

  FRAMES. Each sac is drawn with its own model-view
      M = T(offset) . View . Posture . T(-centre)
  Posture (uGlassSpineSim.PostureMatrix) turns the body into the world,
  where gravity is fixed and points down; View is the orbit camera. The
  two sacs sit side by side in the eye's frame, offset across the screen
  direction of their long axis, so they never overlap whatever the
  posture or the camera.

  MOUSE. Left drag orbits the camera (gravity stays world-down). Right
  drag turns the patient: across = roll, up and down = tilt; OnPosture is
  called so the form's sliders follow. Wheel zooms.

  SHADING. Front to back with premultiplied alpha:
    dura    at each crossing of the inside/outside boundary, a faint glass
            sheet with a Fresnel rim and a highlight (normals from the
            geometry texture's gradient); level boundaries tint it, and
            T4, T10 and L1 are drawn in red;
    cord    opaque, Lambert-shaded, ends the ray;
    drug    emission-absorption with opacity Opacity * sqrt(C) per mm, so
            a few per cent still shows.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, GraphType, IntfGraphics, FPImage,
  FPWritePNG, GL, GLext, OpenGLContext, uSpineGeom, uGlassSpineSim;

type
  TMat4 = array[0..15] of Single;   // column-major, as OpenGL wants
  TTextTex = record
    Tex: GLuint;
    W, H: Integer;
  end;

  TSpineView = class(TOpenGLControl)
  private
    FSim: TSpineSim;
    FInited: Boolean;
    FError: string;
    FProg: GLuint;
    FTexC, FTexG: GLuint;
    FGeomVersion: Integer;
    FYaw, FPitch, FDist: Single;
    FDragging, FTurning: Boolean;
    FLastX, FLastY: Integer;
    FLabels: array of TTextTex;
    FLabelTexts: array of string;
    FOnPosture: TNotifyEvent;
    procedure InitGL;
    procedure UploadGeometry;
    procedure RenderScene;
    function SacMatrix(s: Integer; const V: TMat4; out OffX, OffY: Single): TMat4;
    function TextTex(const S: string; AColor: TColor; Size: Integer; Bold: Boolean): Integer;
    procedure DrawText(Index: Integer; x, y: Single; CentreX: Boolean);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    DrugColor: array[0..1] of TColor;
    Titles: array[0..1] of string;
    Opacity: Single;            // per mm, at C = 1
    ShowLabels: Boolean;
    constructor Create(AOwner: TComponent); override;
    procedure Paint; override;
    procedure ResetView;
    procedure TitlesChanged;
    procedure SaveToPNG(const FileName: string);
    property Sim: TSpineSim read FSim write FSim;
    property OnPosture: TNotifyEvent read FOnPosture write FOnPosture;
    property LastError: string read FError;
  end;

implementation

const
  SacSeparation = 48.0;   // mm from each sac's centre to the screen midline

  VertexSrc =
    'varying vec3 vObj;'#10 +
    'void main() { vObj = gl_Vertex.xyz; gl_Position = ftransform(); }'#10;

  FragmentSrc =
    'uniform sampler3D uConc;'#10 +
    'uniform sampler3D uGeom;'#10 +
    'uniform vec3 uEye, uBoxMin, uBoxMax, uOrigin, uInvSize, uDrug, uLight;'#10 +
    'uniform float uDx, uStep, uOpacity;'#10 +
    'varying vec3 vObj;'#10 +
    'vec3 tc(vec3 p) { return (p - uOrigin + 0.5 * uDx) * uInvSize; }'#10 +
    'vec3 gradR(vec3 p) {'#10 +
    '  float h = 1.5 * uDx;'#10 +
    '  return vec3(texture3D(uGeom, tc(p + vec3(h,0,0))).r - texture3D(uGeom, tc(p - vec3(h,0,0))).r,'#10 +
    '              texture3D(uGeom, tc(p + vec3(0,h,0))).r - texture3D(uGeom, tc(p - vec3(0,h,0))).r,'#10 +
    '              texture3D(uGeom, tc(p + vec3(0,0,h))).r - texture3D(uGeom, tc(p - vec3(0,0,h))).r);'#10 +
    '}'#10 +
    'vec3 gradG(vec3 p) {'#10 +
    '  float h = 1.5 * uDx;'#10 +
    '  return vec3(texture3D(uGeom, tc(p + vec3(h,0,0))).g - texture3D(uGeom, tc(p - vec3(h,0,0))).g,'#10 +
    '              texture3D(uGeom, tc(p + vec3(0,h,0))).g - texture3D(uGeom, tc(p - vec3(0,h,0))).g,'#10 +
    '              texture3D(uGeom, tc(p + vec3(0,0,h))).g - texture3D(uGeom, tc(p - vec3(0,0,h))).g);'#10 +
    '}'#10 +
    'void main() {'#10 +
    '  vec3 dir = normalize(vObj - uEye);'#10 +
    '  vec3 inv = 1.0 / dir;'#10 +
    '  vec3 t1 = (uBoxMin - uEye) * inv, t2 = (uBoxMax - uEye) * inv;'#10 +
    '  vec3 tlo = min(t1, t2), thi = max(t1, t2);'#10 +
    '  float tIn = max(max(max(tlo.x, tlo.y), tlo.z), 0.0);'#10 +
    '  float tOut = min(min(thi.x, thi.y), thi.z);'#10 +
    '  if (tOut <= tIn) discard;'#10 +
    '  float jit = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);'#10 +
    '  float t = tIn + jit * uStep;'#10 +
    '  vec4 acc = vec4(0.0);'#10 +
    '  float prevIn = texture3D(uGeom, tc(uEye + dir * t)).r;'#10 +
    '  for (int i = 0; i < 3000; i++) {'#10 +
    '    if (t > tOut || acc.a > 0.97) break;'#10 +
    '    vec3 p = uEye + dir * t;'#10 +
    '    vec4 g = texture3D(uGeom, tc(p));'#10 +
    '    if ((g.r >= 0.5) != (prevIn >= 0.5)) {'#10 +
    '      vec3 n = gradR(p);'#10 +
    '      n = length(n) > 1e-4 ? normalize(n) : -dir;'#10 +
    '      float fres = pow(1.0 - abs(dot(n, dir)), 3.0);'#10 +
    '      if (dot(n, dir) > 0.0) n = -n;'#10 +
    '      float spec = 0.6 * fres * pow(max(dot(reflect(dir, n), uLight), 0.0), 12.0);'#10 +
    '      vec3 col = vec3(0.70, 0.82, 0.95);'#10 +
    '      float a = 0.05 + 0.40 * fres;'#10 +
    '      if (g.b > 0.25) { col = vec3(0.95, 0.95, 0.75); a += 0.22; }'#10 +
    '      if (g.a > 0.25) { col = vec3(1.0, 0.35, 0.30); a += 0.30; }'#10 +
    '      a = min(a, 0.9);'#10 +
    '      acc.rgb += (1.0 - acc.a) * (a * col + spec * vec3(1.0));'#10 +
    '      acc.a += (1.0 - acc.a) * a;'#10 +
    '    }'#10 +
    '    prevIn = g.r;'#10 +
    '    if (g.g > 0.5) {'#10 +
    '      float ta = t - uStep, tb = t;'#10 +
    '      for (int k = 0; k < 5; k++) {'#10 +
    '        float tm = 0.5 * (ta + tb);'#10 +
    '        if (texture3D(uGeom, tc(uEye + dir * tm)).g > 0.5) tb = tm; else ta = tm;'#10 +
    '      }'#10 +
    '      p = uEye + dir * tb;'#10 +
    '      vec3 n = gradG(p);'#10 +
    '      n = length(n) > 1e-4 ? -normalize(n) : -dir;'#10 +
    '      float lam = 0.35 + 0.65 * max(dot(n, uLight), 0.0);'#10 +
    '      acc.rgb += (1.0 - acc.a) * lam * vec3(0.93, 0.86, 0.72);'#10 +
    '      acc.a = 1.0;'#10 +
    '      break;'#10 +
    '    }'#10 +
    '    if (g.r > 0.5) {'#10 +
    '      float c = texture3D(uConc, tc(p)).r;'#10 +
    '      if (c > 0.0003) {'#10 +
    '        float a = 1.0 - exp(-uOpacity * sqrt(c) * uStep);'#10 +
    '        vec3 col = uDrug * (0.55 + 0.9 * sqrt(c));'#10 +
    '        acc.rgb += (1.0 - acc.a) * a * col;'#10 +
    '        acc.a += (1.0 - acc.a) * a;'#10 +
    '      }'#10 +
    '    }'#10 +
    '    t += uStep;'#10 +
    '  }'#10 +
    '  gl_FragColor = acc;'#10 +
    '}'#10;

  // levels labelled beside each sac (indices into uSpineGeom.LevelNames)
  LabelLevels: array[0..9] of Integer = (0, 2, 4, 6, 9, 11, 13, 15, 18, -1);

{ 4x4 helpers, column-major }

function MIdentity: TMat4;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result[0] := 1; Result[5] := 1; Result[10] := 1; Result[15] := 1;
end;

function MMul(const A, B: TMat4): TMat4;
var
  i, j, k: Integer;
  s: Single;
begin
  for j := 0 to 3 do
    for i := 0 to 3 do
    begin
      s := 0;
      for k := 0 to 3 do s := s + A[k * 4 + i] * B[j * 4 + k];
      Result[j * 4 + i] := s;
    end;
end;

function MTranslate(x, y, z: Single): TMat4;
begin
  Result := MIdentity;
  Result[12] := x; Result[13] := y; Result[14] := z;
end;

function MRotX(Deg: Single): TMat4;
var
  s, c: Single;
begin
  SinCos(DegToRad(Deg), s, c);
  Result := MIdentity;
  Result[5] := c; Result[6] := s; Result[9] := -s; Result[10] := c;
end;

function MRotY(Deg: Single): TMat4;
var
  s, c: Single;
begin
  SinCos(DegToRad(Deg), s, c);
  Result := MIdentity;
  Result[0] := c; Result[2] := -s; Result[8] := s; Result[10] := c;
end;

function MFrom3(const R: TMat3): TMat4;
var
  i, j: Integer;
begin
  Result := MIdentity;
  for i := 0 to 2 do
    for j := 0 to 2 do Result[j * 4 + i] := R[i, j];
end;

function MPerspective(FovY, Aspect, zn, zf: Single): TMat4;
var
  f: Single;
begin
  FillChar(Result, SizeOf(Result), 0);
  f := 1 / Tan(DegToRad(FovY) / 2);
  Result[0] := f / Aspect;
  Result[5] := f;
  Result[10] := (zf + zn) / (zn - zf);
  Result[11] := -1;
  Result[14] := 2 * zf * zn / (zn - zf);
end;

procedure MApply(const M: TMat4; x, y, z: Single; out ox, oy, oz, ow: Single);
begin
  ox := M[0] * x + M[4] * y + M[8] * z + M[12];
  oy := M[1] * x + M[5] * y + M[9] * z + M[13];
  oz := M[2] * x + M[6] * y + M[10] * z + M[14];
  ow := M[3] * x + M[7] * y + M[11] * z + M[15];
end;

{ TSpineView }

constructor TSpineView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DepthBits := 24;
  DrugColor[0] := RGBToColor(70, 150, 255);
  DrugColor[1] := RGBToColor(255, 165, 40);
  Opacity := 0.9;
  ShowLabels := True;
  ResetView;
end;

procedure TSpineView.ResetView;
begin
  // from the patient's right, a little above, head to the right
  FYaw := 0;
  FPitch := 12;
  FDist := 1000;
  Invalidate;
end;

procedure TSpineView.TitlesChanged;
var
  i: Integer;
begin
  // the label textures are rebuilt on the next paint
  if FInited and MakeCurrent then
    for i := 0 to High(FLabels) do glDeleteTextures(1, @FLabels[i].Tex);
  SetLength(FLabels, 0);
  SetLength(FLabelTexts, 0);
  Invalidate;
end;

function CompileShader(Kind: GLenum; const Src: string): GLuint;
var
  P: PGLchar;
  ok, n: GLint;
  Log: string;
begin
  Result := glCreateShader(Kind);
  P := PGLchar(Src);
  glShaderSource(Result, 1, @P, nil);
  glCompileShader(Result);
  glGetShaderiv(Result, GL_COMPILE_STATUS, @ok);
  if ok = 0 then
  begin
    SetLength(Log, 8192);
    n := 0;
    glGetShaderInfoLog(Result, 8192, @n, PGLchar(Log));
    SetLength(Log, n);
    raise Exception.Create('shader: ' + Log);
  end;
end;

procedure TSpineView.InitGL;
var
  ok: GLint;
begin
  if not (Load_GL_version_1_2 and Load_GL_version_2_0) then
    raise Exception.Create('OpenGL 2.0 with 3-D textures is needed');
  FProg := glCreateProgram();
  glAttachShader(FProg, CompileShader(GL_VERTEX_SHADER, VertexSrc));
  glAttachShader(FProg, CompileShader(GL_FRAGMENT_SHADER, FragmentSrc));
  glLinkProgram(FProg);
  glGetProgramiv(FProg, GL_LINK_STATUS, @ok);
  if ok = 0 then raise Exception.Create('the ray-march shader did not link');
  glGenTextures(1, @FTexC);
  glGenTextures(1, @FTexG);
  FGeomVersion := -1;
  FInited := True;
end;

procedure TSpineView.UploadGeometry;
var
  G: TSpineGeom;
  Px: array of Byte;
  i: Integer;
  f: Byte;
  procedure Params;
  begin
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  end;
begin
  G := FSim.Geom;
  SetLength(Px, 4 * Length(G.Flags));
  for i := 0 to High(G.Flags) do
  begin
    f := G.Flags[i];
    if f and (FlagFluid or FlagCord) <> 0 then Px[4 * i] := 255;
    if f and FlagCord <> 0 then Px[4 * i + 1] := 255;
    if f and FlagRing <> 0 then Px[4 * i + 2] := 255;
    if f and FlagKey <> 0 then Px[4 * i + 3] := 255;
  end;
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glBindTexture(GL_TEXTURE_3D, FTexG);
  Params;
  glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, G.NX, G.NY, G.NZ, 0, GL_RGBA, GL_UNSIGNED_BYTE, @Px[0]);
  glBindTexture(GL_TEXTURE_3D, FTexC);
  Params;
  glTexImage3D(GL_TEXTURE_3D, 0, GL_LUMINANCE16, G.NX, G.NY, G.NZ, 0, GL_LUMINANCE, GL_FLOAT, nil);
  glBindTexture(GL_TEXTURE_3D, 0);
  FGeomVersion := FSim.GeomVersion;
end;

function TSpineView.TextTex(const S: string; AColor: TColor; Size: Integer; Bold: Boolean): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, W, H: Integer;
  c: TFPColor;
  lum: Integer;
  Px: array of Byte;
  T: TTextTex;
  Key: string;
begin
  Key := Format('%s|%d|%d|%d', [S, AColor, Size, Ord(Bold)]);
  for x := 0 to High(FLabelTexts) do
    if FLabelTexts[x] = Key then Exit(x);
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Size := Size;
    if Bold then Bmp.Canvas.Font.Style := [fsBold];
    W := Bmp.Canvas.TextWidth(S) + 4;
    H := Bmp.Canvas.TextHeight(S) + 4;
    Bmp.SetSize(Max(1, W), Max(1, H));
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, W, H);
    Bmp.Canvas.Font.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.TextOut(2, 2, S);
    Img := Bmp.CreateIntfImage;
    try
      SetLength(Px, W * H * 4);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do
        begin
          c := Img.Colors[x, y];
          lum := (c.red shr 8 + c.green shr 8 + c.blue shr 8) div 3;
          // premultiplied, so it composites like the volume does
          Px[(y * W + x) * 4 + 0] := Red(AColor) * lum div 255;
          Px[(y * W + x) * 4 + 1] := Green(AColor) * lum div 255;
          Px[(y * W + x) * 4 + 2] := Blue(AColor) * lum div 255;
          Px[(y * W + x) * 4 + 3] := lum;
        end;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
  glGenTextures(1, @T.Tex);
  glBindTexture(GL_TEXTURE_2D, T.Tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, @Px[0]);
  glBindTexture(GL_TEXTURE_2D, 0);
  T.W := W;
  T.H := H;
  SetLength(FLabels, Length(FLabels) + 1);
  SetLength(FLabelTexts, Length(FLabelTexts) + 1);
  FLabels[High(FLabels)] := T;
  FLabelTexts[High(FLabelTexts)] := Key;
  Result := High(FLabels);
end;

procedure TSpineView.DrawText(Index: Integer; x, y: Single; CentreX: Boolean);
var
  T: TTextTex;
begin
  T := FLabels[Index];
  if CentreX then x := x - T.W / 2;
  y := y - T.H / 2;
  x := Round(x);
  y := Round(y);
  glEnable(GL_TEXTURE_2D);
  glBindTexture(GL_TEXTURE_2D, T.Tex);
  glColor4f(1, 1, 1, 1);
  glBegin(GL_QUADS);
  glTexCoord2f(0, 1); glVertex2f(x, y);
  glTexCoord2f(1, 1); glVertex2f(x + T.W, y);
  glTexCoord2f(1, 0); glVertex2f(x + T.W, y + T.H);
  glTexCoord2f(0, 0); glVertex2f(x, y + T.H);
  glEnd;
  glBindTexture(GL_TEXTURE_2D, 0);
  glDisable(GL_TEXTURE_2D);
end;

{ the sac's model-view: centre at the origin, posture, camera, then the
  sideways offset in the eye's frame }
function TSpineView.SacMatrix(s: Integer; const V: TMat4; out OffX, OffY: Single): TMat4;
var
  G: TSpineGeom;
  R: TMat4;
  ax, ay, az, aw, px, py, l, sg: Single;
begin
  G := FSim.Geom;
  R := MMul(V, MFrom3(PostureMatrix(FSim.TiltDeg, FSim.RollDeg)));
  // the long axis on screen, and the direction across it
  MApply(R, 0, 0, 1, ax, ay, az, aw);
  ax := ax - R[12];
  ay := ay - R[13];
  l := Sqrt(ax * ax + ay * ay);
  if l < 0.2 then
  begin
    px := 0; py := 1;
  end
  else
  begin
    px := -ay / l; py := ax / l;
    if (py < -0.01) or ((Abs(py) <= 0.01) and (px < 0)) then
    begin
      px := -px; py := -py;
    end;
  end;
  if s = 0 then sg := 1 else sg := -1;
  OffX := sg * px;
  OffY := sg * py;
  Result := MMul(MTranslate(sg * SacSeparation * px, sg * SacSeparation * py, 0),
    MMul(R, MTranslate(-G.SacX[s], -(G.Y0 + 0.5 * (G.NY - 1) * G.Dx), -0.5 * G.Length)));
end;

procedure TSpineView.RenderScene;
var
  G: TSpineGeom;
  P, V, M: TMat4;
  s, i, L, ti: Integer;
  ex, ey, ez, w, lx, ly, lz, bx0, bx1, by0, by1, bz0, bz1, x, y, z, sx, sy: Single;
  hx, hy, hz, nx, ny, gx, gy, cx, cy, cz, cw, glen, ox, oy: Single;
  col: TColor;
  function ToScreen(const MM: TMat4; px, py, pz: Single; out ssx, ssy: Single): Boolean;
  var
    a, b, c, d: Single;
  begin
    MApply(MM, px, py, pz, a, b, c, d);
    MApply(P, a, b, c, a, b, c, d);
    Result := d > 1e-3;
    if not Result then Exit;
    ssx := (a / d * 0.5 + 0.5) * Width;
    ssy := (b / d * 0.5 + 0.5) * Height;
  end;
begin
  glViewport(0, 0, Width, Height);
  glClearColor(0.07, 0.08, 0.10, 1);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  if (FSim = nil) or (FSim.Geom = nil) then Exit;
  G := FSim.Geom;
  if FGeomVersion <> FSim.GeomVersion then UploadGeometry;
  // this frame's concentration
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glBindTexture(GL_TEXTURE_3D, FTexC);
  glTexSubImage3D(GL_TEXTURE_3D, 0, 0, 0, 0, G.NX, G.NY, G.NZ, GL_LUMINANCE, GL_FLOAT, @FSim.HostC[0]);
  glBindTexture(GL_TEXTURE_3D, 0);

  P := MPerspective(30, Width / Max(1, Height), 20, 6000);
  V := MMul(MTranslate(0, 0, -FDist), MMul(MRotX(FPitch), MRotY(FYaw)));
  glMatrixMode(GL_PROJECTION);
  glLoadMatrixf(@P[0]);
  glMatrixMode(GL_MODELVIEW);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_LINE_SMOOTH);

  for s := 0 to 1 do
  begin
    M := SacMatrix(s, V, ox, oy);
    glLoadMatrixf(@M[0]);
    // the needle, from behind the back up to the injection point, angled
    // 20 degrees cephalad as a midline approach usually is
    FSim.Geom.InjectionPoint(FSim.Interspace, s, 0, x, y, z);
    glLineWidth(2.5);
    glBegin(GL_LINES);
    glColor4f(0.75, 0.75, 0.78, 1);
    glVertex3f(x, y + SourceDepthMM - 0.5, z);
    glVertex3f(x, y - 70, z - 25);
    glEnd;
    glLineWidth(1);

    // the volume: the back faces of the sac's half of the box; the
    // shader finds its own entry point
    bx0 := G.X0 - 0.5 * G.Dx + s * (G.NX div 2) * G.Dx;
    bx1 := bx0 + (G.NX div 2) * G.Dx;
    by0 := G.Y0 - 0.5 * G.Dx;
    by1 := by0 + G.NY * G.Dx;
    bz0 := G.Z0 - 0.5 * G.Dx;
    bz1 := bz0 + G.NZ * G.Dx;
    // the eye and the light in the body frame (M is rigid: eye = -A^T t)
    ex := -(M[0] * M[12] + M[1] * M[13] + M[2] * M[14]);
    ey := -(M[4] * M[12] + M[5] * M[13] + M[6] * M[14]);
    ez := -(M[8] * M[12] + M[9] * M[13] + M[10] * M[14]);
    hx := 0.35; hy := 0.55; hz := 0.76;   // towards the light, eye frame
    lx := M[0] * hx + M[1] * hy + M[2] * hz;
    ly := M[4] * hx + M[5] * hy + M[6] * hz;
    lz := M[8] * hx + M[9] * hy + M[10] * hz;
    glUseProgram(FProg);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_3D, FTexC);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_3D, FTexG);
    glUniform1i(glGetUniformLocation(FProg, 'uConc'), 0);
    glUniform1i(glGetUniformLocation(FProg, 'uGeom'), 1);
    glUniform3f(glGetUniformLocation(FProg, 'uEye'), ex, ey, ez);
    glUniform3f(glGetUniformLocation(FProg, 'uBoxMin'), bx0, by0, bz0);
    glUniform3f(glGetUniformLocation(FProg, 'uBoxMax'), bx1, by1, bz1);
    glUniform3f(glGetUniformLocation(FProg, 'uOrigin'), G.X0, G.Y0, G.Z0);
    glUniform3f(glGetUniformLocation(FProg, 'uInvSize'), 1 / (G.NX * G.Dx), 1 / (G.NY * G.Dx),
      1 / (G.NZ * G.Dx));
    col := DrugColor[s];
    glUniform3f(glGetUniformLocation(FProg, 'uDrug'), Red(col) / 255, Green(col) / 255, Blue(col) / 255);
    glUniform3f(glGetUniformLocation(FProg, 'uLight'), lx, ly, lz);
    glUniform1f(glGetUniformLocation(FProg, 'uDx'), G.Dx);
    glUniform1f(glGetUniformLocation(FProg, 'uStep'), 0.5 * G.Dx);
    glUniform1f(glGetUniformLocation(FProg, 'uOpacity'), Opacity);
    glBegin(GL_QUADS);
    // the six faces
    glVertex3f(bx0, by0, bz0); glVertex3f(bx1, by0, bz0); glVertex3f(bx1, by1, bz0); glVertex3f(bx0, by1, bz0);
    glVertex3f(bx0, by0, bz1); glVertex3f(bx0, by1, bz1); glVertex3f(bx1, by1, bz1); glVertex3f(bx1, by0, bz1);
    glVertex3f(bx0, by0, bz0); glVertex3f(bx0, by1, bz0); glVertex3f(bx0, by1, bz1); glVertex3f(bx0, by0, bz1);
    glVertex3f(bx1, by0, bz0); glVertex3f(bx1, by0, bz1); glVertex3f(bx1, by1, bz1); glVertex3f(bx1, by1, bz0);
    glVertex3f(bx0, by0, bz0); glVertex3f(bx0, by0, bz1); glVertex3f(bx1, by0, bz1); glVertex3f(bx1, by0, bz0);
    glVertex3f(bx0, by1, bz0); glVertex3f(bx1, by1, bz0); glVertex3f(bx1, by1, bz1); glVertex3f(bx0, by1, bz1);
    glEnd;
    glUseProgram(0);
    glActiveTexture(GL_TEXTURE1);
    glBindTexture(GL_TEXTURE_3D, 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_3D, 0);
  end;

  // labels and the gravity arrow, in pixels
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  if ShowLabels then
    for s := 0 to 1 do
    begin
      // on the side away from the other sac
      M := SacMatrix(s, V, ox, oy);
      nx := ox * 24;
      ny := oy * 24;
      for i := 0 to High(LabelLevels) do
      begin
        L := LabelLevels[i];
        if L < 0 then Continue;
        z := G.LevelZ0[L] + 0.5 * LevelLen[L];
        MApply(M, G.SacX[s], G.CenterY(z), z, cx, cy, cz, cw);
        cx := cx + nx; cy := cy + ny;
        MApply(P, cx, cy, cz, sx, sy, cz, cw);
        if cw <= 1e-3 then Continue;
        ti := TextTex(LevelNames[L], RGBToColor(200, 200, 190), 8, False);
        DrawText(ti, (sx / cw * 0.5 + 0.5) * Width, (sy / cw * 0.5 + 0.5) * Height, True);
      end;
      // the title, beyond the level labels at mid-lumbar
      z := G.LevelZ0[IdxT12];
      MApply(M, G.SacX[s], G.CenterY(z), z, cx, cy, cz, cw);
      cx := cx + nx * 2.4; cy := cy + ny * 2.4;
      MApply(P, cx, cy, cz, sx, sy, cz, cw);
      if (cw > 1e-3) and (Titles[s] <> '') then
      begin
        ti := TextTex(Titles[s], DrugColor[s], 10, True);
        DrawText(ti, (sx / cw * 0.5 + 0.5) * Width, (sy / cw * 0.5 + 0.5) * Height, True);
      end;
      // the head end
      if ToScreen(M, G.SacX[s], G.CenterY(G.Length), G.Length + 14, sx, sy) then
      begin
        ti := TextTex('head', RGBToColor(150, 220, 150), 8, True);
        DrawText(ti, sx, sy, True);
      end;
    end;

  // gravity: world down, as the camera sees it
  MApply(V, 0, -1, 0, gx, gy, cz, cw);
  gx := gx - V[12];
  gy := gy - V[13];
  glen := Sqrt(gx * gx + gy * gy);
  x := 46;
  y := 70;
  glLineWidth(3);
  glColor4f(0.95, 0.95, 0.95, 1);
  if glen > 0.05 then
  begin
    gx := gx / glen * 40;
    gy := gy / glen * 40;
    glBegin(GL_LINES);
    glVertex2f(x - gx / 2, y - gy / 2);
    glVertex2f(x + gx / 2, y + gy / 2);
    glVertex2f(x + gx / 2, y + gy / 2);
    glVertex2f(x + gx / 2 - 0.3 * gx + 0.2 * gy, y + gy / 2 - 0.3 * gy - 0.2 * gx);
    glVertex2f(x + gx / 2, y + gy / 2);
    glVertex2f(x + gx / 2 - 0.3 * gx - 0.2 * gy, y + gy / 2 - 0.3 * gy + 0.2 * gx);
    glEnd;
  end;
  glLineWidth(1);
  ti := TextTex('g', RGBToColor(240, 240, 240), 11, True);
  DrawText(ti, x + 22, y + 26, True);
end;

procedure TSpineView.Paint;
begin
  if not MakeCurrent then Exit;
  try
    if FError = '' then
    begin
      if not FInited then InitGL;
      RenderScene;
    end
    else
    begin
      glClearColor(0.3, 0.05, 0.05, 1);
      glClear(GL_COLOR_BUFFER_BIT);
    end;
  except
    on E: Exception do FError := E.Message;
  end;
  SwapBuffers;
end;

procedure TSpineView.SaveToPNG(const FileName: string);
var
  Px: array of Byte;
  Img: TFPMemoryImage;
  W: TFPWriterPNG;
  x, y, i: Integer;
  c: TFPColor;
begin
  if not MakeCurrent then Exit;
  if not FInited then InitGL;
  RenderScene;
  SetLength(Px, Width * Height * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, Width, Height, GL_RGBA, GL_UNSIGNED_BYTE, @Px[0]);
  Img := TFPMemoryImage.Create(Width, Height);
  W := TFPWriterPNG.Create;
  try
    for y := 0 to Height - 1 do
      for x := 0 to Width - 1 do
      begin
        i := ((Height - 1 - y) * Width + x) * 4;
        c.red := Px[i] * 257;
        c.green := Px[i + 1] * 257;
        c.blue := Px[i + 2] * 257;
        c.alpha := $FFFF;
        Img.Colors[x, y] := c;
      end;
    Img.SaveToFile(FileName, W);
  finally
    W.Free;
    Img.Free;
  end;
end;

procedure TSpineView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := Button = mbLeft;
  FTurning := Button = mbRight;
  FLastX := X;
  FLastY := Y;
end;

procedure TSpineView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then
  begin
    FYaw := FYaw + 0.4 * (X - FLastX);
    FPitch := EnsureRange(FPitch + 0.4 * (Y - FLastY), -89, 89);
    Invalidate;
  end
  else if FTurning and (FSim <> nil) then
  begin
    FSim.RollDeg := FSim.RollDeg + 0.5 * (X - FLastX);
    while FSim.RollDeg > 180 do FSim.RollDeg := FSim.RollDeg - 360;
    while FSim.RollDeg < -180 do FSim.RollDeg := FSim.RollDeg + 360;
    FSim.TiltDeg := EnsureRange(FSim.TiltDeg - 0.5 * (Y - FLastY), -90, 90);
    if Assigned(FOnPosture) then FOnPosture(Self);
    Invalidate;
  end;
  FLastX := X;
  FLastY := Y;
end;

procedure TSpineView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
  FTurning := False;
end;

function TSpineView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FDist := EnsureRange(FDist * Power(0.9, WheelDelta / 120), 150, 4000);
  Invalidate;
  Result := True;
end;

end.
