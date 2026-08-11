unit uVMPlot3D;

{*******************************************************************************

     TVMPlot3D - a reusable, droppable-on-a-form LCL component wrapping
     TOpenGLControl (LazOpenGLContext) that renders a real newVM (TVMobj)
     matrix as a lit, Gouraud-shaded height-field surface. This is the
     rendering engine of the Graphs/Plot3D demo (uplot3dmain.pas), lifted
     out into a standalone component the same way TVMPlot2D
     (uVMPlot2D.pas) was generalised from the Plot2D demo - see that
     unit's header for the shared rationale (component vs. per-form code,
     `Create` + `Parent` usage, the `newVMGraphs` design-time package).

     SetData(M) rescales M's value range to a fixed on-screen height and
     centres a fixed-extent (row,col) grid regardless of M's actual
     magnitude or Rows/Cols, so any real TVMobj matrix - not just the
     demo's own sinc-ripple data - renders at the same on-screen scale;
     BuildDemoMatrix in the Plot3D demo is one concrete example fed
     through that general path.

     Unlike TVMPlot2D, this component's camera is interactive by
     necessity - a static 3D projection of a height field is far less
     legible than one you can orbit - so mouse-drag-to-rotate and
     wheel-to-zoom are handled directly by the component itself
     (MouseDown/MouseMove/MouseUp/DoMouseWheel overrides), rather than
     requiring the host form to wire up OpenGLControl mouse events by
     hand the way the original demo did. Wireframe/solid and axis-gizmo
     visibility are published boolean properties (Wireframe/ShowAxes) a
     host UI (e.g. a TCheckBox) can bind to; ResetView restores the
     initial camera framing, mirroring the demo's ResetViewButton.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, LCLType,
  GL, GLU, OpenGLContext,
  newVM;

type
  // One surface grid point's render-ready state: world-space position,
  // unit normal (for lighting) and height-mapped colour - all precomputed
  // once in SetData rather than recomputed every frame. Ported unchanged
  // from uplot3dmain.pas's TSurfaceVertex.
  TVMPlotSurfaceVertex = record
    X, Y, Z: Double;
    NX, NY, NZ: Double;
    R, G, B: Double;
  end;

  { TVMPlot3D }

  TVMPlot3D = class(TOpenGLControl)
  private
    FRows, FCols: Integer;
    FVerts: array of array of TVMPlotSurfaceVertex;
    FHasData: Boolean;
    FYaw, FPitch, FDistance: Double;
    FWireframe, FShowAxes: Boolean;
    FDragging: Boolean;
    FLastMouseX, FLastMouseY: Integer;
    procedure SetWireframe(AValue: Boolean);
    procedure SetShowAxes(AValue: Boolean);
    procedure ComputeNormal(r, c: Integer);
    procedure HeightToColor(t: Double; out r, g, b: Double);
    procedure DrawAxes;
    procedure EmitVertex(r, c: Integer);
  protected
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(TheOwner: TComponent); override;
    procedure Paint; override;
    procedure SetData(const M: TVMobj);
    procedure ResetView;
  published
    property Wireframe: Boolean read FWireframe write SetWireframe;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes;
  end;

procedure Register;

implementation

const
  // Initial/reset camera framing - matches uplot3dmain.pas's FormCreate
  // and ResetViewButtonClick constants, tuned there by actually
  // screenshotting the running demo (see CLAUDE.md).
  DefaultYaw = 35.0;
  DefaultPitch = 45.0;
  DefaultDistance = 16.0;

{ TVMPlot3D }

constructor TVMPlot3D.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  FWireframe := False;
  FShowAxes := True;
  FHasData := False;
end;

procedure TVMPlot3D.SetWireframe(AValue: Boolean);
begin
  if FWireframe = AValue then Exit;
  FWireframe := AValue;
  Invalidate;
end;

procedure TVMPlot3D.SetShowAxes(AValue: Boolean);
begin
  if FShowAxes = AValue then Exit;
  FShowAxes := AValue;
  Invalidate;
end;

procedure TVMPlot3D.ResetView;
begin
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  Invalidate;
end;

// Populates FVerts from M: world X/Y form a grid of fixed total extent
// (WorldSize) centred on the origin regardless of M.Rows/M.Cols, and
// world Z is M's values linearly rescaled from [ZMin,ZMax] to
// [-ZScale/2,+ZScale/2] regardless of M's actual magnitude - so any real
// matrix, of any size or value range, renders at the same on-screen
// scale. Ported unchanged from uplot3dmain.pas's BuildSurface, renamed to
// SetData for parity with TVMPlot2D's public entry point.
procedure TVMPlot3D.SetData(const M: TVMobj);
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

  FHasData := True;
  Invalidate;
end;

// Standard heightmap normal via central differences of the (already
// world-scaled) Z grid, clamped to the grid edges; normalises (-dz/dx,
// -dz/dy, 1) to a unit vector for correct Gouraud lighting. Ported
// unchanged from uplot3dmain.pas.
procedure TVMPlot3D.ComputeNormal(r, c: Integer);
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
// Ported unchanged from uplot3dmain.pas.
procedure TVMPlot3D.HeightToColor(t: Double; out r, g, b: Double);
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

procedure TVMPlot3D.EmitVertex(r, c: Integer);
begin
  with FVerts[r, c] do begin
    glNormal3d(NX, NY, NZ);
    glColor3d(R, G, B);
    glVertex3d(X, Y, Z);
  end;
end;

// Three short RGB lines from the origin along X/Y/Z, for orientation
// reference while dragging the view around. Ported unchanged from
// uplot3dmain.pas.
procedure TVMPlot3D.DrawAxes;
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

procedure TVMPlot3D.Paint;
var
  aspect: Double;
  r, c: Integer;
  lightPos: array[0..3] of GLfloat;
begin
  if not MakeCurrent then Exit;
  if (Width = 0) or (Height = 0) then Exit;

  glViewport(0, 0, Width, Height);
  aspect := Width / Height;

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

  if FShowAxes then DrawAxes;

  if FHasData then begin
    if FWireframe then
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
  end;

  glDisable(GL_LIGHTING);
  SwapBuffers;
end;

procedure TVMPlot3D.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TVMPlot3D.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then begin
    FDragging := True;
    FLastMouseX := X;
    FLastMouseY := Y;
  end;
end;

procedure TVMPlot3D.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  FYaw := FYaw + (X - FLastMouseX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastMouseY) * 0.5, -89.0, 89.0);
  FLastMouseX := X;
  FLastMouseY := Y;
  Invalidate;
end;

procedure TVMPlot3D.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TVMPlot3D.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  FDistance := EnsureRange(FDistance - WheelDelta / 120 * 0.6, 3.0, 40.0);
  Invalidate;
  result := True;
end;

procedure Register;
begin
  RegisterComponents('newVM', [TVMPlot3D]);
end;

end.
