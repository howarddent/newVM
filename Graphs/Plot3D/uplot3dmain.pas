unit uplot3dmain;

{*******************************************************************************

     Main form for the Plot3D demo. Builds a real TVMobj matrix (see
     newVM.pas) sampling z = sin(r)/r, r = sqrt(x^2+y^2) - the classic
     "sinc ripple" surface - over a 51x51 grid, then renders it as a lit,
     Gouraud-shaded height-field surface via raw OpenGL (TOpenGLControl,
     the LazOpenGLContext package, plus FPC's own GL/GLU units).

     BuildSurface(M: TVMobj) is written to accept any real TVMobj matrix,
     not just this demo's own data: it normalises M's value range to a
     fixed on-screen height regardless of the input's actual magnitude,
     and centres the (row,col) grid regardless of M's Rows/Cols - the
     sinc-ripple matrix built by BuildDemoMatrix is just one concrete
     example fed through that general path, the same way FunctionPlot's
     y=f(x) is one concrete use of TAChart.

     Mouse drag rotates the view (yaw/pitch), the mouse wheel zooms
     (camera distance), and a checkbox toggles solid/wireframe rendering -
     the "OpenGL enhanced" part of a 3D matrix graph over a flat 2D
     projection of the same data.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  Math,
  GL, GLU, OpenGLContext,
  newVM;

type

  // One surface grid point's render-ready state: world-space position,
  // unit normal (for lighting) and height-mapped colour - all precomputed
  // once in BuildSurface rather than recomputed every frame.
  TSurfaceVertex = record
    X, Y, Z: Double;
    NX, NY, NZ: Double;
    R, G, B: Double;
  end;

  { TForm1 }

  TForm1 = class(TForm)
    ControlPanel: TPanel;
    WireframeCheckBox: TCheckBox;
    ResetViewButton: TButton;
    HintLabel: TLabel;
    OpenGLControl1: TOpenGLControl;
    procedure FormCreate(Sender: TObject);
    procedure OpenGLControl1Paint(Sender: TObject);
    procedure OpenGLControl1Resize(Sender: TObject);
    procedure OpenGLControl1MouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpenGLControl1MouseMove(Sender: TObject; Shift: TShiftState;
      X, Y: Integer);
    procedure OpenGLControl1MouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure OpenGLControl1MouseWheel(Sender: TObject; Shift: TShiftState;
      WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure WireframeCheckBoxChange(Sender: TObject);
  private
    FRows, FCols: Integer;
    FVerts: array of array of TSurfaceVertex;
    FYaw, FPitch, FDistance: Double;
    FDragging: Boolean;
    FLastMouseX, FLastMouseY: Integer;
    function BuildDemoMatrix: TVMobj;
    procedure BuildSurface(const M: TVMobj);
    procedure ComputeNormal(r, c: Integer);
    procedure HeightToColor(t: Double; out r, g, b: Double);
    procedure DrawAxes;
    procedure EmitVertex(r, c: Integer);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FYaw := 35; FPitch := 45; FDistance := 16;
  BuildSurface(BuildDemoMatrix);
end;

// z = sin(r)/r, r = sqrt(x^2+y^2), x,y in [-Extent,Extent] - the classic
// "sombrero"/sinc-ripple demo surface. r=0's removable singularity (limit
// sin(r)/r -> 1) is handled explicitly rather than dividing by ~0.
function TForm1.BuildDemoMatrix: TVMobj;
const
  Rows = 51; Cols = 51;
  Extent = 6.0;
var
  M: TVMobj;
  r, c: Integer;
  x, y, dist: Double;
begin
  M := TVMobj.Create(Rows, Cols);
  for r := 0 to Rows - 1 do begin
    y := -Extent + 2 * Extent * r / (Rows - 1);
    for c := 0 to Cols - 1 do begin
      x := -Extent + 2 * Extent * c / (Cols - 1);
      dist := Sqrt(x * x + y * y);
      if dist < 1e-6 then
        M[r, c] := 1.0
      else
        M[r, c] := Sin(dist) / dist;
    end;
  end;
  result := M;
end;

// Populates FVerts from M: world X/Y form a grid of fixed total extent
// (WorldSize) centred on the origin regardless of M.Rows/M.Cols, and
// world Z is M's values linearly rescaled from [ZMin,ZMax] to
// [-ZScale/2,+ZScale/2] regardless of M's actual magnitude - so any real
// matrix, of any size or value range, renders at the same on-screen scale.
procedure TForm1.BuildSurface(const M: TVMobj);
const
  WorldSize = 8.0;
  ZScale = 2.5;
var
  r, c: Integer;
  ZMin, ZMax, ZRange, v, dxWorld, dyWorld: Double;
begin
  FRows := M.Rows;
  FCols := M.Cols;
  SetLength(FVerts, FRows, FCols);

  ZMin := M[0, 0]; ZMax := M[0, 0];
  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      v := M[r, c];
      if v < ZMin then ZMin := v;
      if v > ZMax then ZMax := v;
    end;
  ZRange := ZMax - ZMin;
  if ZRange = 0 then ZRange := 1;   // guard a constant matrix

  dxWorld := WorldSize / (FCols - 1);
  dyWorld := WorldSize / (FRows - 1);

  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      FVerts[r, c].X := (c - (FCols - 1) / 2) * dxWorld;
      FVerts[r, c].Y := (r - (FRows - 1) / 2) * dyWorld;
      FVerts[r, c].Z := ((M[r, c] - ZMin) / ZRange - 0.5) * ZScale;
    end;

  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      ComputeNormal(r, c);
      // FVerts[r,c].Z is already the [-ZScale/2,+ZScale/2] value above -
      // shift/rescale it back to a plain [0,1] fraction for the colour map.
      HeightToColor(FVerts[r, c].Z / ZScale + 0.5,
        FVerts[r, c].R, FVerts[r, c].G, FVerts[r, c].B);
    end;
end;

// Standard heightmap normal via central differences of the (already
// world-scaled) Z grid, clamped to the grid edges; normalises (-dz/dx,
// -dz/dy, 1) to a unit vector for correct Gouraud lighting.
procedure TForm1.ComputeNormal(r, c: Integer);
var
  cL, cR, rD, rU: Integer;
  dzdx, dzdy, nx, ny, nz, len: Double;
begin
  cL := Max(c - 1, 0); cR := Min(c + 1, FCols - 1);
  rD := Max(r - 1, 0); rU := Min(r + 1, FRows - 1);

  dzdx := (FVerts[r, cR].Z - FVerts[r, cL].Z) / (FVerts[r, cR].X - FVerts[r, cL].X);
  dzdy := (FVerts[rU, c].Z - FVerts[rD, c].Z) / (FVerts[rU, c].Y - FVerts[rD, c].Y);

  nx := -dzdx; ny := -dzdy; nz := 1.0;
  len := Sqrt(nx * nx + ny * ny + nz * nz);
  FVerts[r, c].NX := nx / len;
  FVerts[r, c].NY := ny / len;
  FVerts[r, c].NZ := nz / len;
end;

// Maps a value in [0,1] to an RGB colour via a 4-stop gradient - blue ->
// green -> yellow -> red - the classic "jet-lite" height colouring.
procedure TForm1.HeightToColor(t: Double; out r, g, b: Double);
begin
  if t < 0 then t := 0;
  if t > 1 then t := 1;
  if t < 1 / 3 then begin
    r := 0; g := 3 * t; b := 1 - 3 * t;
  end else if t < 2 / 3 then begin
    r := 3 * t - 1; g := 1; b := 0;
  end else begin
    r := 1; g := 1 - 3 * (t - 2 / 3); b := 0;
  end;
end;

procedure TForm1.EmitVertex(r, c: Integer);
begin
  with FVerts[r, c] do begin
    glNormal3d(NX, NY, NZ);
    glColor3d(R, G, B);
    glVertex3d(X, Y, Z);
  end;
end;

// Three short RGB lines from the origin along X/Y/Z, for orientation
// reference while dragging the view around.
procedure TForm1.DrawAxes;
const
  AxisLen = 3.0;
begin
  glDisable(GL_LIGHTING);
  glLineWidth(2.0);
  glBegin(GL_LINES);
    glColor3f(1, 0, 0); glVertex3d(0, 0, 0); glVertex3d(AxisLen, 0, 0);
    glColor3f(0, 1, 0); glVertex3d(0, 0, 0); glVertex3d(0, AxisLen, 0);
    glColor3f(0, 0, 1); glVertex3d(0, 0, 0); glVertex3d(0, 0, AxisLen);
  glEnd;
  glEnable(GL_LIGHTING);
end;

procedure TForm1.OpenGLControl1Paint(Sender: TObject);
var
  aspect: Double;
  r, c: Integer;
  lightPos: array[0..3] of GLfloat;
begin
  if not OpenGLControl1.MakeCurrent then Exit;
  if (OpenGLControl1.Width = 0) or (OpenGLControl1.Height = 0) then Exit;

  glViewport(0, 0, OpenGLControl1.Width, OpenGLControl1.Height);
  aspect := OpenGLControl1.Width / OpenGLControl1.Height;

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(45.0, aspect, 0.1, 100.0);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glTranslatef(0, 0, -FDistance);
  glRotatef(FPitch, 1, 0, 0);
  glRotatef(FYaw, 0, 1, 0);

  glClearColor(0.12, 0.12, 0.16, 1.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST);
  glShadeModel(GL_SMOOTH);

  glEnable(GL_LIGHTING);
  glEnable(GL_LIGHT0);
  glEnable(GL_COLOR_MATERIAL);
  glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
  glEnable(GL_NORMALIZE);
  lightPos[0] := 4; lightPos[1] := 6; lightPos[2] := 8; lightPos[3] := 1;
  glLightfv(GL_LIGHT0, GL_POSITION, @lightPos[0]);

  DrawAxes;

  if WireframeCheckBox.Checked then
    glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
  else
    glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);

  for r := 0 to FRows - 2 do begin
    glBegin(GL_TRIANGLE_STRIP);
      for c := 0 to FCols - 1 do begin
        EmitVertex(r, c);
        EmitVertex(r + 1, c);
      end;
    glEnd;
  end;

  glDisable(GL_LIGHTING);
  OpenGLControl1.SwapBuffers;
end;

procedure TForm1.OpenGLControl1Resize(Sender: TObject);
begin
  OpenGLControl1.Invalidate;
end;

procedure TForm1.OpenGLControl1MouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then begin
    FDragging := True;
    FLastMouseX := X;
    FLastMouseY := Y;
  end;
end;

procedure TForm1.OpenGLControl1MouseMove(Sender: TObject; Shift: TShiftState;
  X, Y: Integer);
begin
  if not FDragging then Exit;
  FYaw := FYaw + (X - FLastMouseX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastMouseY) * 0.5, -89.0, 89.0);
  FLastMouseX := X;
  FLastMouseY := Y;
  OpenGLControl1.Invalidate;
end;

procedure TForm1.OpenGLControl1MouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  FDragging := False;
end;

procedure TForm1.OpenGLControl1MouseWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  FDistance := EnsureRange(FDistance - WheelDelta / 120 * 0.6, 3.0, 40.0);
  OpenGLControl1.Invalidate;
  Handled := True;
end;

procedure TForm1.ResetViewButtonClick(Sender: TObject);
begin
  FYaw := 35; FPitch := 45; FDistance := 16;
  OpenGLControl1.Invalidate;
end;

procedure TForm1.WireframeCheckBoxChange(Sender: TObject);
begin
  OpenGLControl1.Invalidate;
end;

end.
