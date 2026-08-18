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
     through that general path. SetData is `overload`ed to also accept a
     single-precision TVMobjS directly (newVMSingle.pas) - promoted
     element-by-element to a TVMobj and handed to the double-precision
     overload, since every field this component itself holds (FVerts,
     FZMin/FZMax, etc) is already Double throughout; there is no
     single-precision-specific rendering path, only a single-precision
     entry point into the same one.

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
  Classes, SysUtils, Math, Controls, LCLType, Graphics, LResources,
  IntfGraphics, FPImage,
  GL, GLU, OpenGLContext,
  newVM, newVMSingle;

type
  TVMPlotDoubleArray = array of Double;

  // One surface grid point's render-ready state: world-space position,
  // unit normal (for lighting) and height-mapped colour - all precomputed
  // once in SetData rather than recomputed every frame. Ported unchanged
  // from uplot3dmain.pas's TSurfaceVertex.
  TVMPlotSurfaceVertex = record
    X, Y, Z: Double;
    NX, NY, NZ: Double;
    R, G, B: Double;
  end;

  // A title/axis-title/tick-label string rendered once to a GL texture -
  // see uVMPlot2D.pas's TEXT RENDERING note (same technique; Built tracks
  // whether TexID is a live GL resource, so FreeAllTextures/the destructor
  // can skip ones that were never (re)built).
  TVMPlotTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  { TVMPlot3D }

  TVMPlot3D = class(TOpenGLControl)
  private
    FRows, FCols: Integer;
    FVerts: array of array of TVMPlotSurfaceVertex;
    FZMin, FZMax: Double;
    FHasData: Boolean;
    FYaw, FPitch, FDistance: Double;
    FWireframe, FShowAxes, FShowLevelCurves: Boolean;
    FDragging: Boolean;
    FLastMouseX, FLastMouseY: Integer;

    FTitle, FXAxisTitle, FYAxisTitle, FZAxisTitle: string;
    FXTicks, FYTicks, FZTicks: TVMPlotDoubleArray;
    // FXTickPos/FYTickPos hold each tick's fractional (column,row) index -
    // i.e. its position in the SAME units SetData's world-position formula
    // ((pos - (FCols-1)/2) * WorldSize/(FCols-1), etc) expects - regardless
    // of what FXTicks/FYTicks themselves are labelled with. In index mode
    // (the default) a tick's label value and its position are the same
    // number; in domain mode (XAxisMin<>XAxisMax) they're not, since the
    // label is a data-space coordinate but the position is still expressed
    // in grid-index units - see RecomputeXYTicks.
    FXTickPos, FYTickPos: TVMPlotDoubleArray;
    FXAxisMin, FXAxisMax, FYAxisMin, FYAxisMax: Double;
    FZAxisMin, FZAxisMax: Double;
    FLightX, FLightY: Double;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex, FZAxisTitleTex: TVMPlotTextTexture;
    FXTickTex, FYTickTex, FZTickTex: array of TVMPlotTextTexture;

    procedure SetWireframe(AValue: Boolean);
    procedure SetShowAxes(AValue: Boolean);
    procedure SetShowLevelCurves(AValue: Boolean);
    procedure SetTitle(const AValue: string);
    procedure SetXAxisTitle(const AValue: string);
    procedure SetYAxisTitle(const AValue: string);
    procedure SetZAxisTitle(const AValue: string);
    procedure SetXAxisMin(AValue: Double);
    procedure SetXAxisMax(AValue: Double);
    procedure SetYAxisMin(AValue: Double);
    procedure SetYAxisMax(AValue: Double);
    procedure SetZAxisMin(AValue: Double);
    procedure SetZAxisMax(AValue: Double);
    procedure SetLightX(AValue: Double);
    procedure SetLightY(AValue: Double);
    procedure RecomputeXYTicks;
    procedure ComputeNormal(r, c: Integer);
    procedure HeightToColor(t: Double; out r, g, b: Double);
    procedure DrawAxisLines;
    procedure DrawAxisLabels;
    procedure DrawLevelCurves;
    function BuildDefaultDemoMatrix: TVMobj;
    procedure EmitVertex(r, c: Integer);
    procedure WorldToScreen(wx, wy, wz: Double; VW, VH: Integer;
      out sx, sy: Double; out infront: Boolean);
    procedure InvalidateTextures;
    procedure FreeTextTexture(var Tex: TVMPlotTextTexture);
    procedure FreeAllTextures;
    function CreateTextTexture(const S: string; FontSize: Integer;
      Bold: Boolean; TR, TG, TB: Byte): TVMPlotTextTexture;
    procedure BuildTextures;
    procedure DrawTextTexture(const Tex: TVMPlotTextTexture;
      X, Y, AngleDeg, HAlign, VAlign: Double);
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
    destructor Destroy; override;
    procedure Paint; override;
    procedure SetData(const M: TVMobj); overload;
    procedure SetData(const M: TVMobjS); overload;
    procedure ResetView;
  published
    property Wireframe: Boolean read FWireframe write SetWireframe;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes;
    property ShowLevelCurves: Boolean read FShowLevelCurves write SetShowLevelCurves;
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
    property YAxisTitle: string read FYAxisTitle write SetYAxisTitle;
    property ZAxisTitle: string read FZAxisTitle write SetZAxisTitle;
    // X/Y tick labels default to column/row index (useful for debugging -
    // "which grid cell is this"), the one thing always knowable about an
    // arbitrary matrix (see SetData's own comment). Setting XAxisMin/
    // XAxisMax (or YAxisMin/YAxisMax) to a genuinely different pair of
    // values switches that axis to label the actual solution-domain
    // coordinate instead - e.g. XAxisMin:=-1; XAxisMax:=1; for a matrix
    // sampled over x in [-1,1] - without changing the underlying grid
    // geometry at all, only how ticks are labelled/spaced. Leaving a pair
    // equal (the default, 0/0) keeps index labelling; this mirrors the
    // "range=0 means degenerate/unset" convention SetData's own ZRange
    // guard already uses.
    property XAxisMin: Double read FXAxisMin write SetXAxisMin;
    property XAxisMax: Double read FXAxisMax write SetXAxisMax;
    property YAxisMin: Double read FYAxisMin write SetYAxisMin;
    property YAxisMax: Double read FYAxisMax write SetYAxisMax;
    // Z defaults to auto-fit: SetData rescales whatever range the CURRENT
    // matrix's own values happen to span to the fixed on-screen height
    // every single call (see SetData's own comment) - fine for a static
    // plot, but for data whose value range itself evolves over many SetData
    // calls (an animated simulation, not just a one-shot surface), that
    // means the on-screen position of any particular DATA value - most
    // noticeably 0, e.g. a clamped-boundary simulation's own zero level -
    // silently drifts as the range changes, even though the data at that
    // value hasn't moved at all: reported from demos/Chebyshev/Wave2D_FPC,
    // whose animated Laplacian solve keeps a mathematically pinned boundary
    // (verified directly against the raw solution grid, not just the
    // rendered plot) that nonetheless appeared to visibly drift once
    // rendered, purely because the auto-fit range's midpoint moved as the
    // wave's own min/max evolved. Setting ZAxisMin/ZAxisMax to a genuinely
    // different pair (e.g. -1/1) switches to that fixed range instead - same
    // "equal pair means unset" convention as XAxisMin/XAxisMax above, and
    // like those, only takes effect from the next SetData call onward (there
    // is no cached source matrix to re-rescale immediately from just the
    // property setters - set these once before the first SetData call, as
    // XAxisMin/XAxisMax are already typically used, rather than expecting a
    // change mid-animation to retroactively affect an already-rendered
    // frame). Values outside the fixed range simply render outside the
    // usual [-ZScale/2,+ZScale/2] box rather than being clamped - consistent
    // with there being no such clamping for X/Y either.
    property ZAxisMin: Double read FZAxisMin write SetZAxisMin;
    property ZAxisMax: Double read FZAxisMax write SetZAxisMax;
    // XY direction of the OpenGL "headlamp" light Paint sets up (see its own
    // comment for why it's a camera-relative directional light rather than
    // a scene-fixed one) - each roughly -1..1, matching whatever a
    // Graphs/uVMLightPad.pas TVMLightPad feeds in, though nothing here
    // requires that control specifically; any code setting these directly
    // works too. Z stays fixed (see Paint) - only the XY direction is
    // exposed, per the feature's own "XY position" scope.
    property LightX: Double read FLightX write SetLightX;
    property LightY: Double read FLightY write SetLightY;
  end;

procedure Register;

implementation

const
  // Initial/reset camera framing - see CLAUDE.md's Graphs/ section for the
  // full story of how this was arrived at (several screenshotted
  // iterations, including wrong turns worth not retrying). In short: the
  // camera's actual WORLD position works out to
  // (-D*cos(pitch)*sin(yaw), D*sin(pitch), D*cos(pitch)*cos(yaw)) - see
  // Paint's headlamp-lighting comment for the derivation - and the
  // original FYaw=35, FPitch=45 gives a negative (below-the-surface) Z
  // there, which is the actual "looks like the underside" cause. FYaw=20,
  // FPitch=-45 makes that Z positive (camera above the surface) while
  // still keeping both Row's and Value's on-screen vertical directions
  // pointing up (their signs depend on cos(pitch) and
  // -cos(yaw)*sin(pitch) respectively - see WorldToScreen).
  DefaultYaw = 20.0;
  DefaultPitch = -45.0;
  DefaultDistance = 16.0;

  // Default headlamp light XY direction - see Paint's own comment for how
  // these two values were arrived at (screenshotted trial and error, not
  // derived). Now overridable at runtime via the LightX/LightY properties
  // (typically driven by a Graphs/uVMLightPad.pas TVMLightPad control - see
  // both demos' FormCreate) - these two constants are only the starting
  // point a freshly-created TVMPlot3D (and a freshly-created TVMLightPad,
  // which mirrors them as its own default) begin at.
  DefaultLightX = 0.5;
  DefaultLightY = -0.6;

  // World-space size of the rendered surface/axes, shared by SetData,
  // DrawAxisLines and WorldToScreen's world-position calculations.
  WorldSize = 8.0;
  ZScale = 2.5;

// "Nice" round tick step (1/2/5 x 10^n) closest to x - Heckbert's classic
// "Nice Numbers for Graph Labels" algorithm. Ported unchanged from
// uplot3dmain.pas (itself ported from uVMPlot2D.pas's NiceNum).
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

// Tick values spaced at a "nice" step, covering [lo,hi]. Ported unchanged
// from uplot3dmain.pas.
function ComputeTicks(lo, hi: Double; TargetCount: Integer): TVMPlotDoubleArray;
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

function FormatTick(v: Double): string;
begin
  result := FloatToStrF(v, ffGeneral, 4, 0);
end;

{ TVMPlot3D }

constructor TVMPlot3D.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  // See uVMPlot2D.pas's constructor comment: without this,
  // TCustomOpenGLControl (LazOpenGLContext) skips real GL rendering under
  // csDesigning, so the Form Designer would show a blank/inert control
  // even though SetData below succeeds and FHasData is True.
  Options := Options + [ocoRenderAtDesignTime];

  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FDistance := DefaultDistance;
  FWireframe := False;
  FShowAxes := True;
  FShowLevelCurves := False;
  FLightX := DefaultLightX;
  FLightY := DefaultLightY;
  FHasData := False;
  FTexturesBuilt := False;

  // Default to the same "sinc ripple" surface the Graphs/Plot3D demo builds
  // in its own FormCreate (uplot3dmain.pas's BuildDemoMatrix), so a
  // freshly-dropped component already shows a representative surface -
  // both in the Form Designer at design time and at runtime before any
  // real SetData call - rather than a blank dark viewport. Harmless to
  // overwrite later: a caller's own SetData (as the demo's FormCreate still
  // does) simply replaces this.
  Title := 'z = sin(r)/r  (sinc ripple)';
  XAxisTitle := 'Column';
  YAxisTitle := 'Row';
  ZAxisTitle := 'Value';
  SetData(BuildDefaultDemoMatrix);
end;

destructor TVMPlot3D.Destroy;
begin
  // See TVMPlot2D.Destroy's comment (uVMPlot2D.pas) for why this guards on
  // HandleAllocated - the same app-termination crash applies here, since
  // this component now also owns GL texture resources.
  if HandleAllocated and MakeCurrent then FreeAllTextures;
  inherited Destroy;
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

procedure TVMPlot3D.SetShowLevelCurves(AValue: Boolean);
begin
  if FShowLevelCurves = AValue then Exit;
  FShowLevelCurves := AValue;
  Invalidate;
end;

procedure TVMPlot3D.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetXAxisTitle(const AValue: string);
begin
  if FXAxisTitle = AValue then Exit;
  FXAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetYAxisTitle(const AValue: string);
begin
  if FYAxisTitle = AValue then Exit;
  FYAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetZAxisTitle(const AValue: string);
begin
  if FZAxisTitle = AValue then Exit;
  FZAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetXAxisMin(AValue: Double);
begin
  if FXAxisMin = AValue then Exit;
  FXAxisMin := AValue;
  RecomputeXYTicks;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetXAxisMax(AValue: Double);
begin
  if FXAxisMax = AValue then Exit;
  FXAxisMax := AValue;
  RecomputeXYTicks;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetYAxisMin(AValue: Double);
begin
  if FYAxisMin = AValue then Exit;
  FYAxisMin := AValue;
  RecomputeXYTicks;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetYAxisMax(AValue: Double);
begin
  if FYAxisMax = AValue then Exit;
  FYAxisMax := AValue;
  RecomputeXYTicks;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlot3D.SetZAxisMin(AValue: Double);
begin
  if FZAxisMin = AValue then Exit;
  FZAxisMin := AValue;
  Invalidate;
end;

procedure TVMPlot3D.SetZAxisMax(AValue: Double);
begin
  if FZAxisMax = AValue then Exit;
  FZAxisMax := AValue;
  Invalidate;
end;

procedure TVMPlot3D.SetLightX(AValue: Double);
begin
  if FLightX = AValue then Exit;
  FLightX := AValue;
  Invalidate;
end;

procedure TVMPlot3D.SetLightY(AValue: Double);
begin
  if FLightY = AValue then Exit;
  FLightY := AValue;
  Invalidate;
end;

// Rebuilds FXTicks/FYTicks (the label values) and FXTickPos/FYTickPos (their
// world-position-formula input, always in grid-index units - see the fields'
// own comment) from FCols/FRows plus whichever mode XAxisMin/XAxisMax (resp.
// YAxisMin/YAxisMax) currently select. Called from SetData (after FCols/
// FRows are updated) and from the four axis-range setters above - the
// latter so changing XAxisMin/XAxisMax alone (no new SetData call) is
// enough to relabel an already-displayed matrix, and so setting them
// *before* the first real SetData call (a common call order - see
// u2DBVPMain.pas's FormCreate) still lands on the right FCols/FRows once
// SetData itself re-runs this.
procedure TVMPlot3D.RecomputeXYTicks;
var
  i: Integer;
begin
  if FXAxisMin <> FXAxisMax then begin
    FXTicks := ComputeTicks(FXAxisMin, FXAxisMax, 5);
    SetLength(FXTickPos, Length(FXTicks));
    for i := 0 to High(FXTicks) do
      FXTickPos[i] := (FXTicks[i] - FXAxisMin) / (FXAxisMax - FXAxisMin) * (FCols - 1);
  end else begin
    FXTicks := ComputeTicks(0, FCols - 1, 5);
    FXTickPos := Copy(FXTicks, 0, Length(FXTicks));
  end;

  if FYAxisMin <> FYAxisMax then begin
    FYTicks := ComputeTicks(FYAxisMin, FYAxisMax, 5);
    SetLength(FYTickPos, Length(FYTicks));
    for i := 0 to High(FYTicks) do
      FYTickPos[i] := (FYTicks[i] - FYAxisMin) / (FYAxisMax - FYAxisMin) * (FRows - 1);
  end else begin
    FYTicks := ComputeTicks(0, FRows - 1, 5);
    FYTickPos := Copy(FYTicks, 0, Length(FYTicks));
  end;
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
// world Z is M's values linearly rescaled from [FZMin,FZMax] to
// [-ZScale/2,+ZScale/2] regardless of M's actual magnitude - so any real
// matrix, of any size or value range, renders at the same on-screen
// scale. Also computes the X/Y/Z axis tick values (RecomputeXYTicks for X/Y
// - column/row index by default, or the actual solution-domain coordinate
// if XAxisMin/XAxisMax or YAxisMin/YAxisMax have been set to a genuine
// range; Z from M's own actual value range by default, or from
// ZAxisMin/ZAxisMax when THAT'S been set to a genuine range instead - see
// ZAxisMin's own property comment for why a fixed range matters for
// animated data specifically). Ported from uplot3dmain.pas's BuildSurface,
// renamed to SetData for parity with
// TVMPlot2D's public entry point.
procedure TVMPlot3D.SetData(const M: TVMobj);
var
  r, c: Integer;
  ZRange, v, dxWorld, dyWorld, DataZMin, DataZMax: Double;
begin
  FRows := M.Rows;
  FCols := M.Cols;
  SetLength(FVerts, FRows, FCols);

  DataZMin := M[0, 0]; DataZMax := M[0, 0];
  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      v := M[r, c];
      if v < DataZMin then DataZMin := v;
      if v > DataZMax then DataZMax := v;
    end;
  if FZAxisMin <> FZAxisMax then begin
    FZMin := FZAxisMin;
    FZMax := FZAxisMax;
  end else begin
    FZMin := DataZMin;
    FZMax := DataZMax;
  end;
  ZRange := FZMax - FZMin;
  if ZRange = 0 then ZRange := 1;   // guard a constant matrix (or a degenerate fixed range)

  dxWorld := WorldSize / (FCols - 1);
  dyWorld := WorldSize / (FRows - 1);

  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      FVerts[r, c].X := (c - (FCols - 1) / 2) * dxWorld;
      FVerts[r, c].Y := (r - (FRows - 1) / 2) * dyWorld;
      FVerts[r, c].Z := ((M[r, c] - FZMin) / ZRange - 0.5) * ZScale;
    end;

  for r := 0 to FRows - 1 do
    for c := 0 to FCols - 1 do begin
      ComputeNormal(r, c);
      // FVerts[r,c].Z is already the [-ZScale/2,+ZScale/2] value above -
      // shift/rescale it back to a plain [0,1] fraction for the colour map.
      HeightToColor(FVerts[r, c].Z / ZScale + 0.5,
        FVerts[r, c].R, FVerts[r, c].G, FVerts[r, c].B);
    end;

  RecomputeXYTicks;
  FZTicks := ComputeTicks(FZMin, FZMax, 5);

  FHasData := True;
  InvalidateTextures;
  Invalidate;
end;

// Single-precision entry point: promotes M element-by-element into a
// double-precision TVMobj and delegates to the TVMobj overload above,
// rather than duplicating that whole grid/normal/tick/colour pipeline a
// second time for Single - every one of this component's own fields
// (FVerts, FZMin/FZMax, etc) is already Double throughout, so there's
// nothing single-precision-specific left to do once the promotion itself
// is done. The promotion is a plain O(Rows*Cols) loop, not a call into
// newVMComplex-style library machinery - negligible next to the
// ComputeNormal/HeightToColor work SetData(TVMobj) already does per
// element.
procedure TVMPlot3D.SetData(const M: TVMobjS);
var
  Converted: TVMobj;
  r, c: Integer;
begin
  Converted := TVMobj.Create(M.Rows, M.Cols);
  for r := 0 to M.Rows - 1 do
    for c := 0 to M.Cols - 1 do
      Converted[r, c] := M[r, c];
  SetData(Converted);
end;

// Standard heightmap normal via central differences of the (already
// world-scaled) Z grid, clamped to the grid edges; normalises (-dz/dx,
// -dz/dy, 1) to a unit vector for correct Gouraud lighting. Ported
// unchanged from uplot3dmain.pas.
// Default demo data: the same 51x51 "sinc ripple" surface (z = sin(r)/r,
// r = sqrt(x^2+y^2), r=0's removable singularity handled explicitly) built
// by the Graphs/Plot3D demo's own TForm1.BuildDemoMatrix - see the
// constructor's comment for why this exists.
function TVMPlot3D.BuildDefaultDemoMatrix: TVMobj;
const
  DemoRows = 51; DemoCols = 51;
  DemoExtent = 6.0;
var
  M: TVMobj;
  r, c: Integer;
  x, y, dist: Double;
begin
  M := TVMobj.Create(DemoRows, DemoCols);
  for r := 0 to DemoRows - 1 do begin
    y := -DemoExtent + 2 * DemoExtent * r / (DemoRows - 1);
    for c := 0 to DemoCols - 1 do begin
      x := -DemoExtent + 2 * DemoExtent * c / (DemoCols - 1);
      dist := Sqrt(x * x + y * y);
      if dist < 1e-6 then
        M[r, c] := 1.0
      else
        M[r, c] := Sin(dist) / dist;
    end;
  end;
  result := M;
end;

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

// Contour ("level curve") lines where the surface crosses each value in
// FZTicks - the same "nice" values already labelled on the Value axis, so
// a curve corresponds exactly to a value a viewer can read straight off
// that axis, rather than an arbitrarily-spaced set. Classic "marching
// triangles" contour extraction: each grid quad is split into two
// triangles (independent of the shading pass's own GL_TRIANGLE_STRIP
// topology in Paint - any consistent split works, since this is a
// separate height-field-only overlay computed straight from FVerts, not
// drawn as part of that triangle strip), and for each triangle/level
// pair, the (up to two) triangle edges whose endpoints straddle that
// level are linearly interpolated to find where Z=level crosses them -
// the resulting two points are joined with one line segment.
procedure TVMPlot3D.DrawLevelCurves;

  // Finds where edge (A,B) crosses level L, if it does, and records the
  // interpolated (X,Y) point into PX[Count]/PY[Count]. A perfectly flat
  // edge sitting exactly on the level is skipped rather than specially
  // handled - a vanishingly rare case for smooth data at a "nice" tick
  // level, not worth the extra bookkeeping.
  procedure TryEdge(const A, B: TVMPlotSurfaceVertex; L: Double;
    var PX, PY: array of Double; var Count: Integer);
  var
    t: Double;
  begin
    if Count >= 2 then Exit;
    if (A.Z < L) = (B.Z < L) then Exit;   // both above or both below - no crossing
    if Abs(B.Z - A.Z) < 1e-12 then Exit;  // flat edge exactly at the level
    t := (L - A.Z) / (B.Z - A.Z);
    PX[Count] := A.X + t * (B.X - A.X);
    PY[Count] := A.Y + t * (B.Y - A.Y);
    Inc(Count);
  end;

  procedure ContourTriangle(const A, B, C: TVMPlotSurfaceVertex; L: Double);
  var
    PX, PY: array[0..1] of Double;
    Count: Integer;
  begin
    Count := 0;
    TryEdge(A, B, L, PX, PY, Count);
    TryEdge(B, C, L, PX, PY, Count);
    TryEdge(C, A, L, PX, PY, Count);
    if Count = 2 then begin
      glVertex3d(PX[0], PY[0], L);
      glVertex3d(PX[1], PY[1], L);
    end;
  end;

var
  r, c, i: Integer;
  zRangeForTicks, worldLevel: Double;
begin
  zRangeForTicks := Max(FZMax - FZMin, 1e-9);
  glDisable(GL_LIGHTING);
  glColor3f(0.05, 0.05, 0.05);
  glLineWidth(1.5);
  glBegin(GL_LINES);
    for i := 0 to High(FZTicks) do begin
      if (FZTicks[i] <= FZMin) or (FZTicks[i] >= FZMax) then Continue;
      // FZTicks is in data space (M's actual values) - FVerts.Z is
      // already world-scaled (see SetData), so the level being tested
      // against needs the same [FZMin,FZMax] -> [-ZScale/2,+ZScale/2]
      // mapping applied to it first.
      worldLevel := ((FZTicks[i] - FZMin) / zRangeForTicks - 0.5) * ZScale;
      for r := 0 to FRows - 2 do
        for c := 0 to FCols - 2 do begin
          ContourTriangle(FVerts[r, c], FVerts[r, c + 1], FVerts[r + 1, c], worldLevel);
          ContourTriangle(FVerts[r, c + 1], FVerts[r + 1, c + 1], FVerts[r + 1, c], worldLevel);
        end;
    end;
  glEnd;
  glEnable(GL_LIGHTING);
end;

// Full-span X/Y/Z axis lines through the actual rendered extent (rather
// than a fixed short reference stub), plus a small point marker at each
// tick's exact 3D position - the numeric tick labels themselves are
// drawn separately in pixel space by DrawAxisLabels, once this frame's
// camera transform is known. Ported from uplot3dmain.pas's DrawAxisLines.
procedure TVMPlot3D.DrawAxisLines;
const
  HalfW = WorldSize / 2;
  HalfZ = ZScale / 2;
var
  i: Integer;
  zRangeForTicks: Double;
begin
  zRangeForTicks := Max(FZMax - FZMin, 1e-9);

  glDisable(GL_LIGHTING);
  glLineWidth(1.5);
  glBegin(GL_LINES);
    glColor3f(0.85, 0.25, 0.25); glVertex3d(-HalfW, 0, 0); glVertex3d(HalfW, 0, 0);
    glColor3f(0.25, 0.75, 0.25); glVertex3d(0, -HalfW, 0); glVertex3d(0, HalfW, 0);
    glColor3f(0.35, 0.55, 1.0);  glVertex3d(0, 0, -HalfZ); glVertex3d(0, 0, HalfZ);
  glEnd;

  glPointSize(4);
  glBegin(GL_POINTS);
    glColor3f(0.85, 0.25, 0.25);
    for i := 0 to High(FXTicks) do
      glVertex3d((FXTickPos[i] - (FCols - 1) / 2) * (WorldSize / (FCols - 1)), 0, 0);
    glColor3f(0.25, 0.75, 0.25);
    for i := 0 to High(FYTicks) do
      glVertex3d(0, (FYTickPos[i] - (FRows - 1) / 2) * (WorldSize / (FRows - 1)), 0);
    glColor3f(0.35, 0.55, 1.0);
    for i := 0 to High(FZTicks) do
      glVertex3d(0, 0, ((FZTicks[i] - FZMin) / zRangeForTicks - 0.5) * ZScale);
  glEnd;

  glEnable(GL_LIGHTING);
end;

// Projects a 3D world point to this frame's screen pixel coordinates by
// replaying - in plain Pascal, not via a GL matrix query - the exact
// camera transform Paint sets up on the GL matrix stack:
// glTranslatef(0,0,-FDistance); glRotatef(FPitch,1,0,0);
// glRotatef(FYaw,0,1,0); then gluPerspective(45,aspect,0.1,100). Done by
// hand rather than via gluProject since GLU's exact FPC signature isn't
// available to check locally (only a compiled glu.ppu, no bundled .pas
// source) and this camera transform is simple enough to duplicate
// directly with no ambiguity about what it computes. Ported unchanged
// from uplot3dmain.pas.
procedure TVMPlot3D.WorldToScreen(wx, wy, wz: Double; VW, VH: Integer;
  out sx, sy: Double; out infront: Boolean);
const
  FovYDeg = 45.0;
var
  yawRad, pitchRad, fovRad, tanHalfFov, aspect: Double;
  x1, y1, z1, x2, y2, z2, camZ, ndcX, ndcY: Double;
begin
  yawRad := FYaw * Pi / 180;
  pitchRad := FPitch * Pi / 180;

  // Ry(yaw) - matches glRotatef(FYaw,0,1,0), applied to the model first
  // (rightmost on the GL matrix stack = first to affect the vertex).
  x1 := wx * Cos(yawRad) + wz * Sin(yawRad);
  y1 := wy;
  z1 := -wx * Sin(yawRad) + wz * Cos(yawRad);

  // Rx(pitch) - matches glRotatef(FPitch,1,0,0), applied second.
  x2 := x1;
  y2 := y1 * Cos(pitchRad) - z1 * Sin(pitchRad);
  z2 := y1 * Sin(pitchRad) + z1 * Cos(pitchRad);

  // Translate by (0,0,-FDistance) - applied last (leftmost on the stack).
  camZ := z2 - FDistance;
  infront := camZ < -0.1;
  if not infront then Exit;   // behind/at the camera - sx/sy meaningless

  fovRad := FovYDeg * Pi / 180;
  tanHalfFov := Tan(fovRad / 2);
  aspect := VW / VH;

  ndcX := x2 / (-camZ * tanHalfFov * aspect);
  ndcY := y2 / (-camZ * tanHalfFov);

  sx := (ndcX * 0.5 + 0.5) * VW;
  sy := (ndcY * 0.5 + 0.5) * VH;
end;

// Marks cached title/tick GL textures for rebuild on the next paint -
// called whenever the title strings or the tick set (i.e. the data)
// change. Mirrors TVMPlot2D.InvalidateTextures.
procedure TVMPlot3D.InvalidateTextures;
begin
  FTexturesBuilt := False;
end;

procedure TVMPlot3D.FreeTextTexture(var Tex: TVMPlotTextTexture);
begin
  if Tex.Built then begin
    glDeleteTextures(1, @Tex.TexID);
    Tex.Built := False;
  end;
end;

procedure TVMPlot3D.FreeAllTextures;
var
  i: Integer;
begin
  FreeTextTexture(FTitleTex);
  FreeTextTexture(FXAxisTitleTex);
  FreeTextTexture(FYAxisTitleTex);
  FreeTextTexture(FZAxisTitleTex);
  for i := 0 to High(FXTickTex) do FreeTextTexture(FXTickTex[i]);
  for i := 0 to High(FYTickTex) do FreeTextTexture(FYTickTex[i]);
  for i := 0 to High(FZTickTex) do FreeTextTexture(FZTickTex[i]);
end;

// Renders S once via the LCL's font engine into a TBitmap, converts it to
// an RGBA buffer ((TR,TG,TB) text colour, alpha = 255-luminance so the
// white background drops out under normal alpha blending), and uploads it
// as a GL texture - see uVMPlot2D.pas's TEXT RENDERING note for the full
// rationale (same technique; unlike TVMPlot2D's always-black text, which
// suits its white plot background, this control's background is dark -
// glClearColor 0.12,0.12,0.16 - so the caller picks a colour instead, see
// BuildTextures). Must run with a current GL context.
function TVMPlot3D.CreateTextTexture(const S: string; FontSize: Integer;
  Bold: Boolean; TR, TG, TB: Byte): TVMPlotTextTexture;
var
  Bmp: TBitmap;
  IntfImg: TLazIntfImage;
  x, y, W, H: Integer;
  c: TFPColor;
  lum: Byte;
  TexPixels: array of Byte;
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
      SetLength(TexPixels, W * H * 4);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do begin
          c := IntfImg.Colors[x, y];
          lum := (c.red shr 8 + c.green shr 8 + c.blue shr 8) div 3;
          TexPixels[(y * W + x) * 4 + 0] := TR;
          TexPixels[(y * W + x) * 4 + 1] := TG;
          TexPixels[(y * W + x) * 4 + 2] := TB;
          TexPixels[(y * W + x) * 4 + 3] := 255 - lum;
        end;
    finally
      IntfImg.Free;
    end;

    glGenTextures(1, @result.TexID);
    glBindTexture(GL_TEXTURE_2D, result.TexID);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA,
      GL_UNSIGNED_BYTE, @TexPixels[0]);
    result.W := W;
    result.H := H;
    result.Built := True;
  finally
    Bmp.Free;
  end;
end;

// Builds every text texture the paint handler needs. Frees any previously
// built set first (FreeAllTextures) - Title/XAxisTitle/.../the data (hence
// tick labels) can change any number of times over this component's life.
// TitleR/G/B is yellow and LabelR/G/B a light grey - both chosen for
// contrast against the dark background (see CreateTextTexture's note);
// this was in fact a reported bug (the title used to render invisibly,
// black-on-black, before CreateTextTexture took a colour parameter at
// all).
procedure TVMPlot3D.BuildTextures;
const
  TitleR = 255; TitleG = 220; TitleB = 40;
  LabelR = 225; LabelG = 225; LabelB = 225;
var
  i: Integer;
begin
  FreeAllTextures;
  FTitleTex := CreateTextTexture(FTitle, 14, True, TitleR, TitleG, TitleB);
  FXAxisTitleTex := CreateTextTexture(FXAxisTitle, 10, False, LabelR, LabelG, LabelB);
  FYAxisTitleTex := CreateTextTexture(FYAxisTitle, 10, False, LabelR, LabelG, LabelB);
  FZAxisTitleTex := CreateTextTexture(FZAxisTitle, 10, False, LabelR, LabelG, LabelB);

  SetLength(FXTickTex, Length(FXTicks));
  for i := 0 to High(FXTicks) do
    FXTickTex[i] := CreateTextTexture(FormatTick(FXTicks[i]), 9, False, LabelR, LabelG, LabelB);

  SetLength(FYTickTex, Length(FYTicks));
  for i := 0 to High(FYTicks) do
    FYTickTex[i] := CreateTextTexture(FormatTick(FYTicks[i]), 9, False, LabelR, LabelG, LabelB);

  SetLength(FZTickTex, Length(FZTicks));
  for i := 0 to High(FZTicks) do
    FZTickTex[i] := CreateTextTexture(FormatTick(FZTicks[i]), 9, False, LabelR, LabelG, LabelB);
end;

// Draws Tex as a textured quad anchored at (X,Y) in the current (pixel-
// space) coordinate system, optionally rotated AngleDeg counterclockwise
// about that anchor. Ported unchanged from uVMPlot2D.pas/uplot3dmain.pas.
procedure TVMPlot3D.DrawTextTexture(const Tex: TVMPlotTextTexture;
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

// Draws the fixed-position main title, plus - when FShowAxes is set -
// every tick label and axis title at its current-frame screen position
// (WorldToScreen). Must run in a pixel-space glOrtho(0,VW,0,VH,...) pass -
// see Paint. Ported unchanged from uplot3dmain.pas.
procedure TVMPlot3D.DrawAxisLabels;
const
  HalfW = WorldSize / 2;
  HalfZ = ZScale / 2;
var
  i, VW, VH: Integer;
  sx, sy: Double;
  infront: Boolean;
begin
  VW := Width;
  VH := Height;

  glEnable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 1);

  if FTitle <> '' then
    DrawTextTexture(FTitleTex, VW / 2, VH - 18, 0, 0.5, 0.5);

  if FShowAxes then begin
    for i := 0 to High(FXTicks) do begin
      WorldToScreen((FXTickPos[i] - (FCols - 1) / 2) * (WorldSize / (FCols - 1)),
        0, 0, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FXTickTex[i], sx, sy - 8, 0, 0.5, 1);
    end;
    for i := 0 to High(FYTicks) do begin
      WorldToScreen(0, (FYTickPos[i] - (FRows - 1) / 2) * (WorldSize / (FRows - 1)),
        0, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FYTickTex[i], sx + 8, sy, 0, 0, 0.5);
    end;
    for i := 0 to High(FZTicks) do begin
      WorldToScreen(0, 0,
        ((FZTicks[i] - FZMin) / Max(FZMax - FZMin, 1e-9) - 0.5) * ZScale,
        VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FZTickTex[i], sx - 8, sy, 0, 1, 0.5);
    end;

    if FXAxisTitle <> '' then begin
      WorldToScreen(HalfW * 1.15, 0, 0, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FXAxisTitleTex, sx, sy, 0, 0.5, 0.5);
    end;
    if FYAxisTitle <> '' then begin
      WorldToScreen(0, HalfW * 1.15, 0, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FYAxisTitleTex, sx, sy, 0, 0.5, 0.5);
    end;
    if FZAxisTitle <> '' then begin
      WorldToScreen(0, 0, HalfZ * 1.2, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FZAxisTitleTex, sx, sy, 0, 0.5, 0.5);
    end;
  end;

  glDisable(GL_TEXTURE_2D);
end;

procedure TVMPlot3D.Paint;
var
  aspect: Double;
  r, c: Integer;
  lightPos: array[0..3] of GLfloat;
  ambient: array[0..3] of GLfloat;
begin
  if not MakeCurrent then Exit;
  if (Width = 0) or (Height = 0) then Exit;

  if not FTexturesBuilt then begin
    BuildTextures;
    FTexturesBuilt := True;
  end;

  glViewport(0, 0, Width, Height);
  aspect := Width / Height;

  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  gluPerspective(45.0, aspect, 0.1, 100.0);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  // Light position is specified while GL_MODELVIEW is still identity - i.e.
  // in EYE space, before the camera rotate/translate below is applied - so
  // it behaves as a "headlamp" fixed to the viewer rather than to the
  // scene: this is a directional light (w=0) specified in eye space, which
  // in eye space is relative to the camera (which looks down -Z), so it
  // always shines on whatever face is actually visible, regardless of
  // where the camera ends up in world space. This replaced an earlier
  // attempt at fixing "the surface looks like its underside" from some
  // camera angles by relying on GL_LIGHT_MODEL_TWO_SIDE with a scene-fixed
  // light instead: that flip is driven by GL's own winding-order-based
  // front/back test, which isn't guaranteed to agree with the normal
  // direction ComputeNormal computes independently, so it did not reliably
  // fix the reported symptom (lit from underneath, correct/topside not
  // lit). A camera-relative light sidesteps that mismatch entirely -
  // whichever face the camera actually sees is, by construction, the one
  // facing the light.
  //
  // The direction is offset up and to one side (rather than straight down
  // the view axis, i.e. (0,0,1,0)) deliberately: a headlamp aimed exactly
  // along the view direction lights every visible surface almost head-on,
  // which is technically correct but reads as flat/dim - there is no N.L
  // falloff to create the light/dark contrast that makes a Gouraud-shaded
  // surface look three-dimensional. Offsetting it keeps the "always lights
  // whatever's visible" guarantee (still eye-space-relative) while
  // restoring that directional shading.
  //
  // DefaultLightY (-0.6) is NEGATIVE despite that being meant to place the
  // light "above" the viewer - confirmed empirically (screenshotting +0.6
  // showed the surface's actual peak, which HeightToColor should render as
  // the most saturated red, rendering dark/muted while a lower side-slope
  // lit up instead - the signature of light hitting the underside of the
  // slopes; flipping the sign to -0.6 fixed it, the peak now reading as the
  // brightest point as expected) rather than derived, since reasoning
  // through eye-space sign conventions here has repeatedly not matched what
  // actually renders - see CLAUDE.md's Graphs/ section. Don't "correct"
  // that default back to a positive value without re-screenshotting.
  //
  // FLightX/FLightY (published as LightX/LightY, defaulting to
  // DefaultLightX/DefaultLightY above) are runtime-adjustable - typically
  // via a Graphs/uVMLightPad.pas TVMLightPad control, see both demos'
  // FormCreate - precisely so a user can drag the light to wherever best
  // reveals a given surface's shape, rather than being stuck with the one
  // fixed direction tuned above for the sinc-ripple demo data. Z stays
  // fixed at -0.65 (previously +0.65): reported as putting the light
  // behind the surface (relative to the default camera) rather than in
  // front of it - confirmed directly on the running demo, not re-derived
  // from eye-space reasoning about which sign should mean "in front" (see
  // the DefaultLightY comment above for why that reasoning has repeatedly
  // not matched what actually renders for this component). Only the XY
  // direction is exposed as a property; Z is not.
  lightPos[0] := FLightX; lightPos[1] := FLightY; lightPos[2] := -0.65; lightPos[3] := 0;
  glLightfv(GL_LIGHT0, GL_POSITION, @lightPos[0]);

  glTranslatef(0, 0, -FDistance);
  glRotatef(FPitch, 1, 0, 0);
  glRotatef(FYaw, 0, 1, 0);

  glClearColor(0.12, 0.12, 0.16, 1.0);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glShadeModel(GL_SMOOTH);

  glEnable(GL_LIGHTING);
  glEnable(GL_LIGHT0);
  glEnable(GL_COLOR_MATERIAL);
  glColorMaterial(GL_FRONT_AND_BACK, GL_AMBIENT_AND_DIFFUSE);
  glEnable(GL_NORMALIZE);
  // Kept as a second line of defence alongside the headlamp above: still
  // correctly flips the normal GL uses for any triangle whose winding
  // comes out back-facing to the camera, in case that ever disagrees with
  // ComputeNormal's own sign convention for some viewing angle.
  glLightModeli(GL_LIGHT_MODEL_TWO_SIDE, GL_TRUE);
  // GL's own default scene ambient (0.2,0.2,0.2,1) plus a single angled
  // directional light leaves parts of the surface facing away from that
  // light quite dark - raised here so the whole surface reads clearly
  // without flattening out the directional shading the angled light (see
  // above) provides.
  ambient[0] := 0.35; ambient[1] := 0.35; ambient[2] := 0.35; ambient[3] := 1;
  glLightModelfv(GL_LIGHT_MODEL_AMBIENT, @ambient[0]);

  if FShowAxes then DrawAxisLines;

  if FHasData then begin
    if FWireframe then
      glPolygonMode(GL_FRONT_AND_BACK, GL_LINE)
    else begin
      glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
      // Pushes the filled surface back very slightly in depth, so that
      // DrawLevelCurves' contour lines - sitting at the exact same depth
      // as the surface they're drawn on top of - don't z-fight with it
      // (flicker as GL arbitrarily picks the surface or the line for a
      // given pixel). Only needed in filled mode: GL_LINE mode has no
      // coplanar fill underneath a contour line to fight with.
      if FShowLevelCurves then begin
        glEnable(GL_POLYGON_OFFSET_FILL);
        glPolygonOffset(1.0, 1.0);
      end;
    end;

    for r := 0 to FRows - 2 do begin
      glBegin(GL_TRIANGLE_STRIP);
        for c := 0 to FCols - 1 do begin
          EmitVertex(r, c);
          EmitVertex(r + 1, c);
        end;
      glEnd;
    end;

    // Skipped in wireframe mode: the mesh's own grid lines already show
    // the surface's structure at least as clearly, and two independent
    // sets of thin lines at the same depth (mesh edges, contour lines)
    // would have the same z-fighting problem the polygon offset above
    // solves for filled-vs-line, without an equally simple fix.
    if (not FWireframe) and FShowLevelCurves then begin
      glDisable(GL_POLYGON_OFFSET_FILL);
      DrawLevelCurves;
    end;
  end;

  glDisable(GL_LIGHTING);
  glDisable(GL_DEPTH_TEST);

  // --- pixel-space pass: main title, axis titles, tick labels - see
  // DrawAxisLabels, which projects each 3D tick/title position through
  // this frame's camera transform (still on the matrix stack above) by
  // hand rather than switching to a pixel-space glOrtho/glViewport (as
  // uVMPlot2D.pas does) before computing positions, since WorldToScreen
  // needs FYaw/FPitch/FDistance/aspect, not the GL matrix state itself -
  // only the FINAL glOrtho/glViewport below (for drawing the resulting 2D
  // label quads) needs to be pixel-space. ---
  glViewport(0, 0, Width, Height);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  DrawAxisLabels;

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
  // Plain '+' on both axes - NOT the negated ('-') form uVMPlotStack.pas
  // uses. An earlier pass here copied PlotStack's negation on the (correct)
  // theory that both components should want the same "grab and turn"
  // trackball feel, but that was wrong: confirmed by direct testing (drag
  // left/right, drag up/down, on the actual running demo) that with the
  // negation in place, BOTH axes were still backwards here specifically -
  // dragging right rotated the surface as if dragged left, and same for
  // up/down - while uVMPlotStack.pas's own negated version genuinely feels
  // correct. Reverting to '+' on both axes fixes it. The two components'
  // camera setups differ in a way that plausibly explains needing opposite
  // signs despite an identical glRotatef(Pitch,1,0,0); glRotatef(Yaw,0,1,0)
  // sequence: this component additionally does glTranslatef(0,0,-FDistance)
  // *before* those rotates (an orbiting-camera setup - see Paint's own
  // camera-position derivation comment), whereas uVMPlotStack.pas has no
  // such translate (the object rotates in place in front of a fixed
  // orthographic eye) - but this is offered as a plausible explanation for
  // why they differ, not as something to re-derive the sign from in the
  // abstract; the sign itself is settled by the direct test above, not by
  // this reasoning. Don't "correct" this back to '-' by analogy with
  // PlotStack without re-testing on this component specifically.
  FYaw := FYaw + (X - FLastMouseX) * 0.5;
  // Clamped to [-89,89] rather than [-179,179] (an earlier, much wider
  // range this file used to have, dating from when DefaultPitch was
  // briefly 135 during camera-framing experiments - see CLAUDE.md's
  // Graphs/ section) - avoids ever crossing the pole at +-90 of this
  // sequential-Euler-angle camera, where yaw's felt direction would
  // otherwise visibly reverse mid-drag. Independent of, and additive
  // with, the sign fix above.
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
  {$I uvmplot3d_icon.lrs}
  RegisterComponents('newVM', [TVMPlot3D]);
end;

end.
