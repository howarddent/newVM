unit uAortaView;

{ The arterial tree of uAortaTree, drawn in OpenGL as a front view of the
  patient (their left on the right of the screen): each vessel a tube
  along a schematic course, coloured by the pressure at that point and
  instant, its width following the lumen's radius with the pulsation
  exaggerated. The branches that are pure resistances are grey stubs.
  Coloured rings mark the sites the form's plots follow.

  The courses are a drawing, not anatomy to scale: each vessel's nodes
  are spread evenly along its course, whose length on the screen is
  close to, but not exactly, the vessel's.

  Wheel zooms, drag pans. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, GL, OpenGLContext,
  IntfGraphics, FPimage, FPWritePNG, uArtery1D, uAortaTree;

type
  TPt = record
    X, Y: Single;
  end;

  TTextTex = record
    S: string;
    Tex: GLuint;
    W, H: Integer;
  end;

  TSiteMark = record
    Probe: Integer;
    Colour: TColor;
  end;

  TAortaView = class(TOpenGLControl)
  private
    FSim: TAortaSim;
    FFrame: Integer;
    FExag, FWidthScale: Double;
    FShowLabels: Boolean;
    FCX, FCY, FHalf: Double;
    FDragging: Boolean;
    FLastX, FLastY: Integer;
    FCourse: array of array of TPt;   { per vessel }
    FTex: array of TTextTex;
    procedure SetFrame(v: Integer);
    procedure SetExag(v: Double);
    procedure SetWidthScale(v: Double);
    procedure SetShowLabels(v: Boolean);
    procedure BuildCourses;
    { the point at fraction s of vessel v's course, and the unit normal }
    procedure CoursePoint(v: Integer; s: Double; out P, N: TPt);
    function JunctionPoint(j: Integer): TPt;
    function TextTex(const S: string): Integer;
    { Align: -1 the text ends at the point, 0 centred, 1 starts there }
    procedure DrawText(const S: string; wx, wy: Double; Align: Integer; R, G, B: Single);
    procedure DrawVessel(v: Integer);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    Sites: array of TSiteMark;
    constructor Create(AOwner: TComponent); override;
    procedure SetSim(ASim: TAortaSim);
    procedure ResetView;
    function RenderScene: Boolean;
    procedure Paint; override;
    function SaveToPNG(const FileName: string): Boolean;
    property Frame: Integer read FFrame write SetFrame;
    property Exaggeration: Double read FExag write SetExag;
    property WidthScale: Double read FWidthScale write SetWidthScale;
    property ShowLabels: Boolean read FShowLabels write SetShowLabels;
  end;

{ the colour at fraction v (0 .. 1) of the pressure scale }
procedure PressureColour(v: Double; out R, G, B: Single);

implementation

const
  { matplotlib's plasma }
  Plasma: array[0..7, 0..2] of Byte = (
    ($0D, $08, $87), ($54, $02, $A3), ($8B, $0A, $A5), ($B9, $32, $89),
    ($DB, $5C, $68), ($F4, $88, $47), ($FE, $BC, $2B), ($F0, $F9, $21));

procedure PressureColour(v: Double; out R, G, B: Single);
var
  f: Double;
  i: Integer;
begin
  f := EnsureRange(v, 0, 1) * High(Plasma);
  i := Min(Floor(f), High(Plasma) - 1);
  f := f - i;
  R := ((1 - f) * Plasma[i, 0] + f * Plasma[i + 1, 0]) / 255;
  G := ((1 - f) * Plasma[i, 1] + f * Plasma[i + 1, 1]) / 255;
  B := ((1 - f) * Plasma[i, 2] + f * Plasma[i + 1, 2]) / 255;
end;

function Pt(AX, AY: Double): TPt;
begin
  Result.X := AX; Result.Y := AY;
end;

constructor TAortaView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FExag := 5;
  FWidthScale := 1.0;
  FShowLabels := True;
  ResetView;
end;

procedure TAortaView.ResetView;
begin
  FCX := 6.5; FCY := -21; FHalf := 33;
  Invalidate;
end;

procedure TAortaView.SetSim(ASim: TAortaSim);
begin
  FSim := ASim;
  FFrame := 0;
  BuildCourses;
  Invalidate;
end;

procedure TAortaView.SetFrame(v: Integer);
begin
  if v = FFrame then Exit;
  FFrame := v;
  Invalidate;
end;

procedure TAortaView.SetExag(v: Double);
begin
  FExag := v; Invalidate;
end;

procedure TAortaView.SetWidthScale(v: Double);
begin
  FWidthScale := v; Invalidate;
end;

procedure TAortaView.SetShowLabels(v: Boolean);
begin
  FShowLabels := v; Invalidate;
end;

procedure TAortaView.BuildCourses;

  procedure Course(const VName: string; const C: array of Double);
  var
    i, k: Integer;
  begin
    for i := 0 to High(FSim.Tree.Vessels) do
      if SameText(FSim.Tree.Vessels[i].Name, VName) then
      begin
        SetLength(FCourse[i], Length(C) div 2);
        for k := 0 to High(FCourse[i]) do FCourse[i][k] := Pt(C[2 * k], C[2 * k + 1]);
      end;
  end;

begin
  SetLength(FCourse, 0);
  if (FSim = nil) or (FSim.Tree = nil) then Exit;
  SetLength(FCourse, Length(FSim.Tree.Vessels));
  { cm; the valve at (-1.5, 0), up the screen is towards the head }
  Course('ascending aorta', [-1.5, 0, -1.5, 4]);
  Course('aortic arch A', [-1.5, 4, -1.0, 5.2, 0, 5.6]);
  Course('aortic arch B', [0, 5.6, 1.6, 5.4, 2.5, 4.5]);
  Course('thoracic aorta A', [2.5, 4.5, 2.5, -0.7]);
  Course('thoracic aorta B', [2.5, -0.7, 1.0, -11]);
  Course('abdominal aorta A', [1.0, -11, 0.8, -16.3]);
  Course('abdominal aorta B', [0.8, -16.3, 0.8, -17.3]);
  Course('abdominal aorta C', [0.8, -17.3, 0.5, -27.9]);
  Course('abdominal aorta D', [0.5, -27.9, 0.5, -28.9]);
  Course('left common iliac', [0.5, -28.9, 4, -33.5]);
  Course('left external iliac', [4, -33.5, 8, -47]);
  Course('right common iliac', [0.5, -28.9, -3, -33.5]);
  Course('right external iliac', [-3, -33.5, -7, -47]);
  Course('left subclavian', [2.5, 4.5, 3.4, 6.2, 5, 7]);
  Course('left brachial', [5, 7, 12.5, 7.6, 14.6, 5, 17, -24]);
  Course('left radial', [17, -24, 19.5, -47]);
end;

procedure TAortaView.CoursePoint(v: Integer; s: Double; out P, N: TPt);
var
  i, m: Integer;
  tot, d, acc, f, tx, ty: Double;
begin
  m := High(FCourse[v]);
  tot := 0;
  for i := 0 to m - 1 do
    tot := tot + Hypot(FCourse[v][i + 1].X - FCourse[v][i].X, FCourse[v][i + 1].Y - FCourse[v][i].Y);
  acc := 0;
  for i := 0 to m - 1 do
  begin
    d := Hypot(FCourse[v][i + 1].X - FCourse[v][i].X, FCourse[v][i + 1].Y - FCourse[v][i].Y);
    if (s * tot <= acc + d) or (i = m - 1) then
    begin
      f := EnsureRange((s * tot - acc) / d, 0, 1);
      P.X := FCourse[v][i].X + f * (FCourse[v][i + 1].X - FCourse[v][i].X);
      P.Y := FCourse[v][i].Y + f * (FCourse[v][i + 1].Y - FCourse[v][i].Y);
      tx := (FCourse[v][i + 1].X - FCourse[v][i].X) / d;
      ty := (FCourse[v][i + 1].Y - FCourse[v][i].Y) / d;
      { at a bend, the mean of the two segments' directions }
      if (f > 0.999) and (i < m - 1) then
      begin
        d := Hypot(FCourse[v][i + 2].X - FCourse[v][i + 1].X, FCourse[v][i + 2].Y - FCourse[v][i + 1].Y);
        tx := tx + (FCourse[v][i + 2].X - FCourse[v][i + 1].X) / d;
        ty := ty + (FCourse[v][i + 2].Y - FCourse[v][i + 1].Y) / d;
        d := Hypot(tx, ty); tx := tx / d; ty := ty / d;
      end;
      N.X := -ty; N.Y := tx;
      Exit;
    end;
    acc := acc + d;
  end;
end;

function TAortaView.JunctionPoint(j: Integer): TPt;
var
  v: Integer;
begin
  Result := Pt(0, 0);
  for v := 0 to High(FSim.Tree.Vessels) do
  begin
    if FSim.Tree.Vessels[v].JIn = j then Exit(FCourse[v][0]);
    if FSim.Tree.Vessels[v].JOut = j then Exit(FCourse[v][High(FCourse[v])]);
  end;
end;

function TAortaView.TextTex(const S: string): Integer;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  Buf: array of Byte;
  i, tw, th, px, py: Integer;
begin
  for i := 0 to High(FTex) do
    if FTex[i].S = S then Exit(i);
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Size := 9;
    tw := Bmp.Canvas.TextWidth(S) + 2;
    th := Bmp.Canvas.TextHeight(S);
    Bmp.SetSize(tw, th);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, tw, th);
    Bmp.Canvas.Font.Color := clWhite;
    Bmp.Canvas.TextOut(1, 0, S);
    Img := Bmp.CreateIntfImage;
    try
      SetLength(Buf, tw * th);
      for py := 0 to th - 1 do
        for px := 0 to tw - 1 do
          Buf[(th - 1 - py) * tw + px] := Img.Colors[px, py].green shr 8;
    finally
      Img.Free;
    end;
  finally
    Bmp.Free;
  end;
  Result := Length(FTex);
  SetLength(FTex, Result + 1);
  FTex[Result].S := S; FTex[Result].W := tw; FTex[Result].H := th;
  glGenTextures(1, @FTex[Result].Tex);
  glBindTexture(GL_TEXTURE_2D, FTex[Result].Tex);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA, tw, th, 0, GL_ALPHA, GL_UNSIGNED_BYTE, @Buf[0]);
end;

procedure TAortaView.DrawText(const S: string; wx, wy: Double; Align: Integer; R, G, B: Single);
var
  k: Integer;
  sc, x0, y0: Double;
begin
  k := TextTex(S);
  { world to pixels }
  sc := Height / (2 * FHalf);
  x0 := Width / 2 + (wx - FCX) * sc;
  y0 := Height / 2 + (wy - FCY) * sc - FTex[k].H / 2;
  case Align of
    -1: x0 := x0 - FTex[k].W - 3;
    0: x0 := x0 - FTex[k].W / 2;
  else
    x0 := x0 + 3;
  end;
  x0 := Round(x0); y0 := Round(y0);
  glMatrixMode(GL_PROJECTION); glPushMatrix; glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glEnable(GL_TEXTURE_2D);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glBindTexture(GL_TEXTURE_2D, FTex[k].Tex);
  glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
  glColor4f(R, G, B, 1);
  glBegin(GL_QUADS);
  glTexCoord2f(0, 0); glVertex2f(x0, y0);
  glTexCoord2f(1, 0); glVertex2f(x0 + FTex[k].W, y0);
  glTexCoord2f(1, 1); glVertex2f(x0 + FTex[k].W, y0 + FTex[k].H);
  glTexCoord2f(0, 1); glVertex2f(x0, y0 + FTex[k].H);
  glEnd;
  glDisable(GL_TEXTURE_2D);
  glDisable(GL_BLEND);
  glPopMatrix;
  glMatrixMode(GL_MODELVIEW);
end;

procedure TAortaView.DrawVessel(v: Integer);
var
  Ve: TVessel;
  i, side, o: Integer;
  P, N: TPt;
  r0, hw, f, cr, cg, cb, e: Single;
begin
  Ve := FSim.Tree.Vessels[v];
  o := FSim.VOff[v];
  { two strips, edge to centre line, darker at the edges: a lit tube }
  for side := 0 to 1 do
  begin
    glBegin(GL_QUAD_STRIP);
    for i := 0 to Ve.NNode - 1 do
    begin
      CoursePoint(v, i / (Ve.NNode - 1), P, N);
      r0 := Sqrt(Ve.A0[i] / Pi);
      hw := Max(FWidthScale * r0, 2.5 * 2 * FHalf / Max(1, Height))
        * Max(0.2, 1 + FExag * (FSim.FrameR[FFrame][o + i] - 1));
      f := (FSim.FrameP[FFrame][o + i] - FSim.PMin) / (FSim.PMax - FSim.PMin);
      PressureColour(f, cr, cg, cb);
      if side = 0 then e := 1 else e := -1;
      glColor3f(0.42 * cr, 0.42 * cg, 0.42 * cb);
      glVertex2f(P.X + e * hw * N.X, P.Y + e * hw * N.Y);
      glColor3f(Min(1, 1.08 * cr + 0.04), Min(1, 1.08 * cg + 0.04), Min(1, 1.08 * cb + 0.04));
      glVertex2f(P.X + 0.15 * e * hw * N.X, P.Y + 0.15 * e * hw * N.Y);
    end;
    glEnd;
  end;
end;

function TAortaView.RenderScene: Boolean;
type
  TStub = record
    J: Integer;
    DX, DY: Single;
    Lab: string;
    Align: Integer;
    LX, LY: Single;   { the label's offset from the stub's end }
  end;
  TName = record
    S: string;
    X, Y: Single;
    Align: Integer;
  end;
const
  Stubs: array[0..14] of TStub = (
    (J: 0; DX: -2.8; DY: 0.7; Lab: 'coronaries'; Align: -1; LX: 0; LY: 0),
    (J: 1; DX: -2.4; DY: 3.0; Lab: 'brachiocephalic'; Align: -1; LX: 0; LY: 0),
    (J: 2; DX: -0.3; DY: 4.2; Lab: 'L common carotid'; Align: -1; LX: 0; LY: 0.6),
    (J: 14; DX: 0.6; DY: 3.0; Lab: 'L vertebral'; Align: 1; LX: 0; LY: 0.4),
    (J: 4; DX: 3.0; DY: 0.2; Lab: 'intercostals'; Align: 1; LX: 0; LY: 0),
    (J: 5; DX: -3.0; DY: -0.4; Lab: 'coeliac'; Align: -1; LX: 0; LY: 0),
    (J: 6; DX: 3.0; DY: 0.3; Lab: 'superior mesenteric'; Align: 1; LX: 0; LY: 0),
    (J: 7; DX: -3.0; DY: -1.0; Lab: 'renals'; Align: -1; LX: 0; LY: 0),
    (J: 8; DX: 3.0; DY: 0.4; Lab: 'inferior mesenteric'; Align: 1; LX: 0; LY: 0),
    (J: 10; DX: -1.4; DY: -3.2; Lab: 'internal iliacs'; Align: 0; LX: -2.1; LY: -1.3),
    (J: 12; DX: 1.4; DY: -3.2; Lab: ''; Align: 0; LX: 0; LY: 0),
    (J: 11; DX: 0.6; DY: -2.4; Lab: 'L common femoral'; Align: 0; LX: 0.6; LY: -1.3),
    (J: 13; DX: -0.6; DY: -2.4; Lab: 'R common femoral'; Align: 0; LX: -0.6; LY: -1.3),
    (J: 15; DX: -1.8; DY: -4.5; Lab: 'ulnar'; Align: 0; LX: 0; LY: -1.3),
    (J: 16; DX: 0.3; DY: -2.4; Lab: 'hand'; Align: 0; LX: 0; LY: -1.3));
  Names: array[0..7] of TName = (
    (S: 'ascending aorta'; X: -3.2; Y: 2.6; Align: -1),
    (S: 'arch'; X: 0.9; Y: 7.4; Align: 1),
    (S: 'thoracic aorta'; X: 4.2; Y: -6; Align: 1),
    (S: 'abdominal aorta'; X: 2.6; Y: -23; Align: 1),
    (S: 'L external iliac'; X: 7.6; Y: -40; Align: 1),
    (S: 'L subclavian'; X: 6.5; Y: 5.2; Align: 1),
    (S: 'L brachial'; X: 17.4; Y: -8; Align: 1),
    (S: 'L radial'; X: 19.8; Y: -36; Align: 1));
var
  v, i, k, pr: Integer;
  asp, rr, ang: Double;
  P, N, Q: TPt;
  cr, cg, cb: Single;
  Ve: TVessel;
begin
  Result := False;
  if not HandleAllocated or not MakeCurrent then Exit;
  glViewport(0, 0, Width, Height);
  glClearColor(0.07, 0.07, 0.10, 1);
  glClear(GL_COLOR_BUFFER_BIT);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_LIGHTING);
  glShadeModel(GL_SMOOTH);
  asp := Width / Max(1, Height);
  glMatrixMode(GL_PROJECTION); glLoadIdentity;
  glOrtho(FCX - FHalf * asp, FCX + FHalf * asp, FCY - FHalf, FCY + FHalf, -1, 1);
  glMatrixMode(GL_MODELVIEW); glLoadIdentity;
  Result := True;
  if (FSim = nil) or (FSim.Tree = nil) or (FSim.NFrames = 0) or (Length(FCourse) = 0) then Exit;
  FFrame := EnsureRange(FFrame, 0, FSim.NFrames - 1);

  { the resistive branches }
  glLineWidth(2);
  glColor3f(0.45, 0.45, 0.50);
  glBegin(GL_LINES);
  for i := 0 to High(Stubs) do
  begin
    P := JunctionPoint(Stubs[i].J);
    glVertex2f(P.X, P.Y);
    glVertex2f(P.X + Stubs[i].DX, P.Y + Stubs[i].DY);
  end;
  glEnd;
  glPointSize(5);
  glBegin(GL_POINTS);
  for i := 0 to High(Stubs) do
  begin
    P := JunctionPoint(Stubs[i].J);
    glVertex2f(P.X + Stubs[i].DX, P.Y + Stubs[i].DY);
  end;
  glEnd;

  { the larger vessels last at a junction, so they cover the smaller }
  for v := High(FSim.Tree.Vessels) downto 0 do DrawVessel(v);

  { a disc where vessels meet, so the tubes join }
  for v := 0 to High(FSim.Tree.Vessels) do
  begin
    Ve := FSim.Tree.Vessels[v];
    if not Ve.Aortic then Continue;
    i := Ve.NNode - 1;
    P := FCourse[v][High(FCourse[v])];
    rr := 0.9 * FWidthScale * Sqrt(Ve.A0[i] / Pi)
      * Max(0.2, 1 + FExag * (FSim.FrameR[FFrame][FSim.VOff[v] + i] - 1));
    PressureColour((FSim.FrameP[FFrame][FSim.VOff[v] + i] - FSim.PMin) / (FSim.PMax - FSim.PMin), cr, cg, cb);
    glBegin(GL_TRIANGLE_FAN);
    glColor3f(Min(1, 1.08 * cr + 0.04), Min(1, 1.08 * cg + 0.04), Min(1, 1.08 * cb + 0.04));
    glVertex2f(P.X, P.Y);
    glColor3f(0.62 * cr, 0.62 * cg, 0.62 * cb);
    for k := 0 to 24 do
    begin
      ang := 2 * Pi * k / 24;
      glVertex2f(P.X + rr * Cos(ang), P.Y + rr * Sin(ang));
    end;
    glEnd;
  end;

  { the sites the plots follow: a ring in the plot's colour }
  glLineWidth(2.5);
  for i := 0 to High(Sites) do
  begin
    pr := Sites[i].Probe;
    if (pr < 0) or (pr > High(FSim.Probes)) then Continue;
    for v := 0 to High(FSim.Tree.Vessels) do
      if FSim.Tree.Vessels[v] = FSim.Probes[pr].V then
      begin
        CoursePoint(v, FSim.Probes[pr].S, P, N);
        rr := 1.1 * FHalf / Max(1, Height) * 2 * 9;   { 9 px }
        glColor3ub(Red(Sites[i].Colour), Green(Sites[i].Colour), Blue(Sites[i].Colour));
        glBegin(GL_LINE_LOOP);
        for k := 0 to 23 do
        begin
          ang := 2 * Pi * k / 24;
          glVertex2f(P.X + rr * Cos(ang), P.Y + rr * Sin(ang));
        end;
        glEnd;
      end;
  end;

  { the valve }
  P := FCourse[0][0];
  glColor3f(0.9, 0.9, 0.9);
  glLineWidth(3);
  glBegin(GL_LINES);
  glVertex2f(P.X - 2.6, P.Y); glVertex2f(P.X + 2.6, P.Y);
  glEnd;

  if FShowLabels then
  begin
    DrawText('aortic valve (left ventricle)', P.X, P.Y - 1.5, 0, 0.9, 0.9, 0.9);
    for i := 0 to High(Stubs) do
      if Stubs[i].Lab <> '' then
      begin
        Q := JunctionPoint(Stubs[i].J);
        DrawText(Stubs[i].Lab, Q.X + Stubs[i].DX + Stubs[i].LX, Q.Y + Stubs[i].DY + Stubs[i].LY,
          Stubs[i].Align, 0.62, 0.62, 0.68);
      end;
    for i := 0 to High(Names) do
      DrawText(Names[i].S, Names[i].X, Names[i].Y, Names[i].Align, 0.95, 0.95, 0.95);
  end;
end;

procedure TAortaView.Paint;
begin
  if RenderScene then SwapBuffers;
end;

function TAortaView.SaveToPNG(const FileName: string): Boolean;
var
  W, H, px, py, o: Integer;
  Buf: array of Byte;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  c: TFPColor;
begin
  Result := False;
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
    for py := 0 to H - 1 do
      for px := 0 to W - 1 do
      begin
        o := ((H - 1 - py) * W + px) * 4;
        c.red := Buf[o] * 257;
        c.green := Buf[o + 1] * 257;
        c.blue := Buf[o + 2] * 257;
        c.alpha := alphaOpaque;
        Img.Colors[px, py] := c;
      end;
    Img.SaveToFile(FileName, Writer);
    Result := True;
  finally
    Writer.Free;
    Img.Free;
  end;
  Invalidate;
end;

procedure TAortaView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  FDragging := True;
  FLastX := X;
  FLastY := Y;
end;

procedure TAortaView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  sc: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  sc := 2 * FHalf / Max(1, Height);
  FCX := FCX - (X - FLastX) * sc;
  FCY := FCY + (Y - FLastY) * sc;
  FLastX := X;
  FLastY := Y;
  Invalidate;
end;

procedure TAortaView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TAortaView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FHalf := EnsureRange(FHalf * Power(0.9, WheelDelta / 120), 3, 80);
  Invalidate;
  Result := True;
end;

end.
