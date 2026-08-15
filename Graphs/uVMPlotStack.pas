unit uVMPlotStack;

{*******************************************************************************

     TVMPlotStack - a reusable, droppable-on-a-form LCL component wrapping
     TOpenGLControl (LazOpenGLContext) that renders a "waterfall"/stacked
     display of real newVM (TVMobj) row/column vectors: each call to
     AddGraph(Y) pushes a new curve in at the front of the stack (Z=0,
     nearest the viewer) and every previously-added curve recedes one
     step further back along the time (Z) axis. Modelled on the classic
     oscilloscope/spectrum-analyser "waterfall" display (also the style
     famously used for the Joy Division "Unknown Pleasures" cover) - see
     AddGraph/Paint below for how that look is actually produced. Built
     the same way TVMPlot2D/TVMPlot3D were (Graphs/uVMPlot2D.pas,
     Graphs/uVMPlot3D.pas) - a standalone TOpenGLControl descendant with
     its own Create+Parent usage, added to the newVMGraphs design-time
     package - and reuses those units' camera/text-texture techniques
     directly rather than reinventing them; see their own header comments
     for the parts not repeated here.

     Usage:
       Stack := TVMPlotStack.Create(Self);
       Stack.Parent := Self;
       Stack.Align := alClient;
       Stack.MaxSeries := 40;      // how many past graphs are kept/visible
       Stack.Animate := False;     // True: stack continuously recedes over time
       Stack.AddGraph(Y);          // Y: a newVM (1,N) or (N,1) TVMobj vector

     COMPOSITING ("new graphs hide overlapping features of previous
     graphs"): each graph is drawn as an OPAQUE filled ribbon from its
     curve down to a fixed floor plane, not just a line - so it has
     something behind it to occlude with. Every frame, Paint draws every
     currently-held slice back-to-front (oldest/furthest first, the
     just-added/nearest slice last) via plain sequential overdraw - a
     textbook painter's algorithm, deliberately NOT using the GL depth
     buffer (GL_DEPTH_TEST stays disabled throughout this component's 3D
     pass) - so a nearer ribbon's fragments simply overwrite whatever an
     older, farther ribbon already drew at the same screen pixels,
     including the axis lines behind it. This is simpler than depth-
     testing and matches the intended fixed-ish "look along the time
     axis" waterfall framing exactly; the trade-off (noted once, not
     re-derived per call site) is that orbiting the camera to view the
     stack from a sufifciently extreme angle can reveal draw-order
     artifacts a depth-tested renderer wouldn't have, since draw order is
     always oldest-to-newest regardless of where the camera actually is.

     COLOUR ("colour the amplitude with a gradient from lightblue to red
     so that peaks show up better against the noise background" + "fade
     [into the distance] as it retreats"): three independent effects, all
     driven by the same per-vertex glColor3d, relying on GL_SMOOTH
     interpolating linearly between vertices as it fills each triangle -
     - By value, across a ribbon's own top edge: each top-edge vertex is
       coloured by where its OWN data value (Slice.Y[j]) falls between the
       stack's current auto-fit FYMin/FYMax (the same range RecomputeBounds
       already tracks for the Value axis - not that one slice's own local
       min/max, which would just as happily paint an ordinary noise
       fluctuation red for being that slice's tallest point) - LowColor at
       the low end, HighColor at the high end (defaults light blue and
       red respectively), linearly interpolated per-channel. A genuine
       standout peak - well above where the bulk of the data (e.g. a
       noise floor) sits - reads as a hot red spike; ordinary fluctuations
       clustered lower in the range stay a cool blue, exactly the contrast
       "peaks show up better against noise" asks for.
     - Vertically, within one ribbon: the top-edge vertex carries the
       value-gradient colour above; the paired bottom/floor vertex is
       always pure black - so every ribbon still reads as "bright along
       its own curve, fading to black at its own floor" regardless of
       depth, same as before this gradient was added.
     - Along Z, across the whole stack: a slice's own brightness
       (computed once per slice as Intensity, in DrawSlice) is
       1 - Age/MaxSeries - i.e. a brand new slice (Age=0) renders at full
       gradient colour, and a slice about to be dropped (Age=MaxSeries)
       has faded to Intensity=0, i.e. pure black - which is also this
       component's background colour, so the oldest visible graphs melt
       into the background rather than popping out of existence when
       finally trimmed (TrimStack).
     A short GL_LINE_STRIP is additionally drawn along each ribbon's own
     top edge, in the same per-vertex colour boosted by a small fixed
     factor and clamped to 1 - a crisp highlight on top of the smooth
     interpolated fill, cheap enough to always draw.

     ANIMATE ("an option for the stack to be stationary or to move
     backwards over time"): FAnimate (published Animate) selects between
     two ways a slice's Age - and hence its world-space depth and
     brightness, both derived from Age/MaxSeries, see DrawSlice - changes
     over time:
     - Animate=False (default): Age only changes in discrete +1 steps,
       applied to every existing slice at the moment AddGraph adds the
       next one - so the whole stack sits still between calls, exactly
       like TVMPlot3D's static surface, and only "jumps back" one slot
       when a new graph arrives.
     - Animate=True: an internal TTimer (FTimer, ~30 Hz) continuously
       adds AnimationSpeed*(interval in seconds) to every slice's Age on
       every tick (TimerTick) - so the whole stack visibly, smoothly
       recedes over time even with no new AddGraph calls at all, and a
       newly-added slice simply joins in at Age=0 and starts ageing
       alongside the rest from that point on.
     Either way, TrimStack (called after both paths) drops any slice
     whose Age has reached MaxSeries - ages are always non-decreasing
     with array index (index 0 is the most recently added, and ageing
     only ever adds the same delta to every existing slice before a new
     Age=0 slice is inserted in front), so the slices to drop are always
     a single contiguous run at the tail, found once and truncated with a
     single SetLength.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, LCLType, Graphics, LResources,
  IntfGraphics, FPImage, ExtCtrls,
  GL, GLU, OpenGLContext,
  newVM;

type
  TVMPlotDoubleArray = array of Double;

  // One stacked graph's render-ready state: its own curve values (already
  // pulled out of the TVMobj AddGraph was given - see AddGraph, which
  // copies into this plain Double array rather than keeping a reference
  // to the caller's TVMobj, matching the rest of newVM's "the callee owns
  // an independent copy" convention) plus Age, the single value both its
  // world-space depth and its brightness are derived from every frame -
  // see DrawSlice.
  TVMPlotStackSlice = record
    Y: array of Double;
    N: Integer;
    Age: Double;
  end;

  // A title/axis-title/tick-label string rendered once to a GL texture -
  // identical technique and purpose to TVMPlot2D's/TVMPlot3D's own
  // TVMPlotTextTexture (uVMPlot2D.pas/uVMPlot3D.pas) - duplicated here
  // rather than shared, matching how those two units don't share it with
  // each other either.
  TVMPlotTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  { TVMPlotStack }

  TVMPlotStack = class(TOpenGLControl)
  private
    FSlices: array of TVMPlotStackSlice;   // index 0 = most recently added
    FMaxSeries: Integer;
    FAnimate: Boolean;
    FAnimationSpeed: Double;
    FTimer: TTimer;

    FLowColor, FHighColor: TColor;
    FLowR, FLowG, FLowB: Double;            // FLowColor, resolved+normalised
    FHighR, FHighG, FHighB: Double;         // FHighColor, resolved+normalised

    FYMin, FYMax: Double;                   // auto-fit across all held slices
    FYScale: Double;                        // Max(Abs(FYMin),Abs(FYMax)) - see DrawSlice
    FFrontN: Integer;                       // most-recent slice's point count

    FYaw, FPitch, FZoom: Double;
    FDragging: Boolean;
    FLastMouseX, FLastMouseY: Integer;

    FShowAxes: Boolean;
    FTitle, FXAxisTitle, FYAxisTitle, FZAxisTitle: string;
    FXTicks, FYTicks, FZTicks: TVMPlotDoubleArray;
    FTexturesBuilt: Boolean;
    FTitleTex, FXAxisTitleTex, FYAxisTitleTex, FZAxisTitleTex: TVMPlotTextTexture;
    FXTickTex, FYTickTex, FZTickTex: array of TVMPlotTextTexture;

    procedure SetMaxSeries(AValue: Integer);
    procedure SetAnimate(AValue: Boolean);
    procedure SetLowColor(AValue: TColor);
    procedure SetHighColor(AValue: TColor);
    procedure SetShowAxes(AValue: Boolean);
    procedure SetTitle(const AValue: string);
    procedure SetXAxisTitle(const AValue: string);
    procedure SetYAxisTitle(const AValue: string);
    procedure SetZAxisTitle(const AValue: string);
    procedure TimerTick(Sender: TObject);
    procedure TrimStack;
    procedure RecomputeBounds;
    procedure RecomputeZTicks;
    procedure DrawSlice(const Slice: TVMPlotStackSlice);
    procedure DrawAxisLines;
    procedure DrawAxisLabels;
    function BuildDefaultDemoSlice(Phase: Double): TVMobj;
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
    procedure AddGraph(const Y: TVMobj);
    procedure ClearStack;
    procedure ResetView;
  published
    // How many past graphs are retained/visible before fading fully to
    // black and being dropped (TrimStack) - also fixes how far back in
    // world space (and hence how dim) a given Age reads as, via
    // Age/MaxSeries - see DrawSlice.
    property MaxSeries: Integer read FMaxSeries write SetMaxSeries;
    // False (default): the stack only moves in discrete steps, one per
    // AddGraph call. True: an internal timer continuously recedes/fades
    // the whole stack, AddGraph calls or not - see this unit's own header
    // comment for the full ANIMATE rationale.
    property Animate: Boolean read FAnimate write SetAnimate;
    // Depth-units (i.e. Age) advanced per second while Animate is True.
    // 1.0 means a slice takes MaxSeries seconds to recede from the front
    // all the way to the vanishing point - same pacing a discretely-added
    // stack would show at one AddGraph per second.
    property AnimationSpeed: Double read FAnimationSpeed write FAnimationSpeed;
    // Endpoints of the value-based colour gradient painted along every
    // ribbon's top edge (LowColor at the auto-fit Value-axis minimum,
    // HighColor at its maximum) - see this unit's own COLOUR rationale for
    // the full picture, including how this gradient then also fades both
    // vertically (to black at the floor) and with Age (to black as a
    // slice recedes).
    property LowColor: TColor read FLowColor write SetLowColor;
    property HighColor: TColor read FHighColor write SetHighColor;
    property ShowAxes: Boolean read FShowAxes write SetShowAxes;
    property Title: string read FTitle write SetTitle;
    property XAxisTitle: string read FXAxisTitle write SetXAxisTitle;
    property YAxisTitle: string read FYAxisTitle write SetYAxisTitle;
    property ZAxisTitle: string read FZAxisTitle write SetZAxisTitle;
  end;

procedure Register;

implementation

const
  // Initial/reset camera framing. Rotation uses the same mouse-drag-orbit
  // model as TVMPlot3D (uVMPlot3D.pas) - see that unit's own header/Paint
  // comments for the general yaw/pitch rationale - but the PROJECTION
  // itself deliberately is NOT TVMPlot3D's gluPerspective: a wide-FOV
  // perspective camera sitting close to the stack (as an early version of
  // this component used) makes near ribbons loom much larger than far
  // ones, an "exaggerated"/fisheye-like look that is not how this kind of
  // stacked waterfall/spectrogram plot is conventionally drawn (compare
  // e.g. matplotlib's default 3D Axes3D projection, which is close to
  // orthographic). Paint therefore uses glOrtho instead - a true parallel
  // projection with NO perspective foreshortening at all, so a slice's
  // on-screen size never depends on how far back it's receded, only its
  // own data - only its position and (per DrawSlice) its brightness
  // change with Age. FZoom (published nowhere - driven by DoMouseWheel)
  // is the ortho view volume's half-height in world units, not a camera
  // distance - there is no camera position to speak of in an orthographic
  // projection, so Paint applies no glTranslatef at all, only the
  // yaw/pitch glRotatef pair.
  //
  // DefaultPitch/DefaultYaw are tuned to match the conventional "look down
  // and slightly across" angle typical of this style of plot (e.g. a
  // matplotlib Axes3D default view) - steep enough to see each slice's
  // own shape clearly from above, angled enough in yaw that the time axis
  // visibly recedes into the distance rather than each slice sitting
  // directly behind the last.
  DefaultYaw = 30.0;
  DefaultPitch = -25.0;
  DefaultZoom = 6.0;

  // World-space extent of the rendered stack, shared by AddGraph/DrawSlice
  // (via the private world-mapping formulas), DrawAxisLines and
  // WorldToScreen's world-position calculations - same "fixed on-screen
  // scale regardless of actual data" convention as TVMPlot3D's WorldSize/
  // ZScale.
  WorldWidth = 8.0;    // X extent - one slice's point-index span
  ValueScale = 3.0;    // Y extent - the auto-fit value range
  StackDepth = 14.0;   // Z extent - the full front-to-vanishing-point span
  HalfW = WorldWidth / 2;
  HalfH = ValueScale / 2;
  HalfD = StackDepth / 2;

  DefaultMaxSeries = 40;
  DefaultAnimationSpeed = 1.0;
  TimerIntervalMs = 33;   // ~30 Hz

// "Nice" round tick step (1/2/5 x 10^n) closest to x - Heckbert's classic
// "Nice Numbers for Graph Labels" algorithm. Ported unchanged from
// uVMPlot3D.pas/uVMPlot2D.pas.
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
// from uVMPlot3D.pas/uVMPlot2D.pas.
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

{ TVMPlotStack }

constructor TVMPlotStack.Create(TheOwner: TComponent);
var
  k: Integer;
begin
  inherited Create(TheOwner);
  // See uVMPlot2D.pas's/uVMPlot3D.pas's constructor comment: without this,
  // TCustomOpenGLControl (LazOpenGLContext) skips real GL rendering under
  // csDesigning, leaving the Form Designer blank even though AddGraph
  // below succeeds.
  Options := Options + [ocoRenderAtDesignTime];

  FMaxSeries := DefaultMaxSeries;
  FAnimate := False;
  FAnimationSpeed := DefaultAnimationSpeed;
  SetLowColor(RGBToColor(135, 206, 250));   // light blue
  SetHighColor(RGBToColor(255, 0, 0));      // red
  FShowAxes := True;
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FZoom := DefaultZoom;
  FTexturesBuilt := False;
  RecomputeZTicks;
  RecomputeBounds;

  FTimer := TTimer.Create(Self);
  FTimer.Interval := TimerIntervalMs;
  FTimer.Enabled := False;
  FTimer.OnTimer := @TimerTick;

  // Default demo data: a dozen phase-shifted decaying sine waves, built
  // and added via the same AddGraph path a real caller uses - see this
  // unit's header and TVMPlot3D.BuildDefaultDemoMatrix's own comment for
  // why this is a plain Math.Sin/Exp loop (TVMobj.Create/Element are
  // themselves plain dynamic-array operations, no MKL/IPP call involved)
  // rather than anything routed through newVM's elementwise-VML/operator-
  // overload path: calling into MKL/IPP from a constructor that also runs
  // inside the Lazarus IDE's own process (true for any RunAndDesignTime
  // package's components) has previously crashed the IDE outright.
  Title := 'Waterfall Stack';
  XAxisTitle := 'Index';
  YAxisTitle := 'Value';
  ZAxisTitle := 'Time';
  for k := 0 to 11 do
    AddGraph(BuildDefaultDemoSlice(k * 0.3));
end;

destructor TVMPlotStack.Destroy;
begin
  // See TVMPlot2D.Destroy's/TVMPlot3D.Destroy's comment (uVMPlot2D.pas/
  // uVMPlot3D.pas) for why this guards on HandleAllocated - same
  // app-termination crash applies here.
  if HandleAllocated and MakeCurrent then FreeAllTextures;
  inherited Destroy;
end;

procedure TVMPlotStack.SetMaxSeries(AValue: Integer);
const
  s = 'TVMPlotStack.SetMaxSeries : ';
begin
  assert(AValue > 0, s + 'MaxSeries must be positive');
  if FMaxSeries = AValue then Exit;
  FMaxSeries := AValue;
  TrimStack;
  RecomputeZTicks;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotStack.SetAnimate(AValue: Boolean);
begin
  if FAnimate = AValue then Exit;
  FAnimate := AValue;
  FTimer.Enabled := FAnimate;
end;

procedure TVMPlotStack.SetLowColor(AValue: TColor);
var
  Clr: TColor;
begin
  FLowColor := AValue;
  // Same ColorToRGB + and-$FF/shr-8/shr-16 byte extraction TVMPlot2D uses
  // for its own per-series LineColor (uVMPlot2D.pas) - resolves system
  // colours (e.g. clBtnFace) to real RGB first, same TColor byte layout.
  Clr := ColorToRGB(AValue);
  FLowR := (Clr and $FF) / 255;
  FLowG := ((Clr shr 8) and $FF) / 255;
  FLowB := ((Clr shr 16) and $FF) / 255;
  Invalidate;
end;

procedure TVMPlotStack.SetHighColor(AValue: TColor);
var
  Clr: TColor;
begin
  FHighColor := AValue;
  Clr := ColorToRGB(AValue);
  FHighR := (Clr and $FF) / 255;
  FHighG := ((Clr shr 8) and $FF) / 255;
  FHighB := ((Clr shr 16) and $FF) / 255;
  Invalidate;
end;

procedure TVMPlotStack.SetShowAxes(AValue: Boolean);
begin
  if FShowAxes = AValue then Exit;
  FShowAxes := AValue;
  Invalidate;
end;

procedure TVMPlotStack.SetTitle(const AValue: string);
begin
  if FTitle = AValue then Exit;
  FTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotStack.SetXAxisTitle(const AValue: string);
begin
  if FXAxisTitle = AValue then Exit;
  FXAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotStack.SetYAxisTitle(const AValue: string);
begin
  if FYAxisTitle = AValue then Exit;
  FYAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotStack.SetZAxisTitle(const AValue: string);
begin
  if FZAxisTitle = AValue then Exit;
  FZAxisTitle := AValue;
  InvalidateTextures;
  Invalidate;
end;

// Advances every held slice's Age by AnimationSpeed*(interval in seconds)
// - see this unit's own ANIMATE rationale. A no-op (but still scheduled)
// while the stack is empty.
procedure TVMPlotStack.TimerTick(Sender: TObject);
var
  i: Integer;
  dAge: Double;
begin
  if Length(FSlices) = 0 then Exit;
  dAge := FAnimationSpeed * (FTimer.Interval / 1000.0);
  for i := 0 to High(FSlices) do
    FSlices[i].Age := FSlices[i].Age + dAge;
  TrimStack;
  Invalidate;
end;

// Drops every slice whose Age has reached MaxSeries. FSlices is always
// kept newest (smallest Age, index 0) to oldest (largest Age) - ageing
// adds the same delta to every existing slice before a new Age=0 slice is
// inserted in front (AddGraph), and TimerTick likewise ages every slice
// uniformly - so ages are always non-decreasing with index, and whatever
// needs dropping is always a single contiguous run at the tail, found
// once and truncated with one SetLength.
procedure TVMPlotStack.TrimStack;
var
  i, cut: Integer;
begin
  cut := Length(FSlices);
  for i := 0 to High(FSlices) do
    if FSlices[i].Age >= FMaxSeries then begin
      cut := i;
      Break;
    end;
  if cut < Length(FSlices) then SetLength(FSlices, cut);
end;

// Recomputes the auto-fit value range (FYMin/FYMax, across every slice
// currently held) and the resulting FYTicks/FXTicks - FXTicks reflects
// only the most recently added slice's point count (FFrontN), the one
// most likely still relevant to a viewer, same rationale TVMPlot3D's
// index-based X/Y ticks use for an arbitrary matrix with no inherent
// domain. Called from AddGraph and ClearStack; deliberately NOT from
// TrimStack/TimerTick, since dropping/ageing a slice never changes what
// values are currently on screen.
//
// FYScale (Max(Abs(FYMin),Abs(FYMax))) is what DrawSlice/DrawAxisLines
// actually use to place a value in world space - see DrawSlice's own
// comment for why the mapping is anchored at value=0 (not at FYMin) so
// the stack's floor sits exactly in the X-T plane.
procedure TVMPlotStack.RecomputeBounds;
var
  i, j: Integer;
begin
  if Length(FSlices) = 0 then begin
    FYMin := -1;
    FYMax := 1;
    FFrontN := 0;
  end else begin
    FYMin := FSlices[0].Y[0];
    FYMax := FSlices[0].Y[0];
    for i := 0 to High(FSlices) do
      for j := 0 to FSlices[i].N - 1 do begin
        if FSlices[i].Y[j] < FYMin then FYMin := FSlices[i].Y[j];
        if FSlices[i].Y[j] > FYMax then FYMax := FSlices[i].Y[j];
      end;
    FFrontN := FSlices[0].N;
  end;
  if FYMax - FYMin < 1e-9 then begin
    FYMin := FYMin - 1;
    FYMax := FYMax + 1;
  end;
  FYScale := Max(Abs(FYMin), Abs(FYMax));
  if FYScale < 1e-9 then FYScale := 1;

  FYTicks := ComputeTicks(FYMin, FYMax, 5);
  if FFrontN > 1 then
    FXTicks := ComputeTicks(0, FFrontN - 1, 5)
  else
    FXTicks := ComputeTicks(0, 1, 2);
end;

// Recomputes FZTicks - "nice" Age values in [0,MaxSeries], independent of
// any actual data - called whenever MaxSeries changes (and once from
// Create). Kept separate from RecomputeBounds since it doesn't depend on
// FSlices at all: these tick positions stay fixed in world space even
// while Animate continuously moves the data ribbons past them, the same
// "grid stays still, data flows through it" effect a real oscilloscope
// waterfall display has.
procedure TVMPlotStack.RecomputeZTicks;
begin
  FZTicks := ComputeTicks(0, FMaxSeries, 5);
end;

procedure TVMPlotStack.ResetView;
begin
  FYaw := DefaultYaw;
  FPitch := DefaultPitch;
  FZoom := DefaultZoom;
  Invalidate;
end;

// The main entry point: pulls Y's values out into a new TVMPlotStackSlice
// (an independent copy, not a reference to Y - matching newVM's general
// "the callee owns its own data" convention, e.g. CopyObj), ages every
// already-held slice by one discrete step when Animate is False (see this
// unit's own ANIMATE rationale for why Animate=True skips that - those
// slices are already ageing continuously via FTimer), then inserts the
// new slice at index 0 (Age=0, front/nearest).
procedure TVMPlotStack.AddGraph(const Y: TVMobj);
const
  s = 'TVMPlotStack.AddGraph : ';
var
  NewSlice: TVMPlotStackSlice;
  i, n: Integer;
begin
  assert((Y.Rows = 1) or (Y.Cols = 1), s + 'Y must be a row or column vector');
  n := Y.Rows * Y.Cols;
  SetLength(NewSlice.Y, n);
  if Y.Rows = 1 then
    for i := 0 to n - 1 do NewSlice.Y[i] := Y[0, i]
  else
    for i := 0 to n - 1 do NewSlice.Y[i] := Y[i, 0];
  NewSlice.N := n;
  NewSlice.Age := 0;

  if not FAnimate then
    for i := 0 to High(FSlices) do
      FSlices[i].Age := FSlices[i].Age + 1;

  SetLength(FSlices, Length(FSlices) + 1);
  for i := High(FSlices) downto 1 do
    FSlices[i] := FSlices[i - 1];
  FSlices[0] := NewSlice;

  TrimStack;
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

procedure TVMPlotStack.ClearStack;
begin
  SetLength(FSlices, 0);
  RecomputeBounds;
  InvalidateTextures;
  Invalidate;
end;

// Default demo data: a decaying sine wave, phase-shifted per call - see
// the constructor's own comment for why this is deliberately a plain
// Math.Sin/Exp loop with no MKL/IPP involvement.
function TVMPlotStack.BuildDefaultDemoSlice(Phase: Double): TVMobj;
const
  N = 60;
var
  M: TVMobj;
  i: Integer;
  x: Double;
begin
  M := TVMobj.Create(1, N);
  for i := 0 to N - 1 do begin
    x := i / (N - 1) * 4 * Pi;
    M[0, i] := Sin(x + Phase) * Exp(-0.15 * x);
  end;
  result := M;
end;

// Draws one slice as an opaque filled ribbon (GL_TRIANGLE_STRIP, top
// vertex = the curve at its own value-gradient colour * Intensity, paired
// floor vertex = black) plus a crisp highlight line along its own top
// edge - see this unit's own COLOUR/COMPOSITING rationale for why. Skips
// slices that have already faded fully to black (Intensity<=0) - about to
// be dropped by TrimStack anyway, and invisible against the black
// background regardless.
//
// Each top-edge vertex's base colour (before the *Intensity fade below)
// is looked up once per vertex, into VR/VG/VB, from where that vertex's
// OWN Slice.Y[j] falls between the stack's global FYMin/FYMax (LowColor
// at the low end, HighColor at the high end) - not that one slice's own
// local min/max, which would just as happily paint an ordinary noise
// fluctuation red for merely being that slice's tallest point. Computed
// into arrays up front rather than inline in the two glBegin/glEnd loops
// below, since the highlight-line pass needs the same per-vertex colour
// (boosted) as the fill pass just used, and recomputing the gradient
// lookup a second time would be pure duplicated work.
//
// The floor vertex sits at world Y=0, not at FYMin/HalfH as an earlier
// version of this unit had it - i.e. the ribbon's base is the X-T plane
// (the plane containing the index and time axes), the plane a value of
// exactly 0 maps to, per the wy formula below (Y[j]/FYScale, not
// (Y[j]-FYMin)/(FYMax-FYMin)) - so a slice with negative values genuinely
// dips below that base plane rather than the base plane trailing the
// data's own minimum.
//
// wz anchors Age=0 (a just-added slice) at -HalfD and Age=FMaxSeries at
// +HalfD - i.e. NEGATIVE Z is nearest the viewer/front of the stack,
// POSITIVE Z is furthest/oldest, matching the axis-frame corner
// DrawAxisLines/DrawAxisLabels place at Z=-HalfD (Age=0). The mirror-image
// formula ((0.5-Age/FMaxSeries)*StackDepth) is what an earlier version of
// this unit used, and animated backwards - a slice visibly drifted
// towards the viewer as it aged rather than receding - because, under
// this component's default orthographic camera (DefaultYaw/DefaultPitch
// above), increasing world Z happens to project to a screen position
// further from the viewer, not closer; which world-Z direction reads as
// "away" is a fact about this specific camera's angles, not a fixed
// convention, so don't re-derive this sign from the rotation math alone
// without re-confirming against the actual rendered animation.
procedure TVMPlotStack.DrawSlice(const Slice: TVMPlotStackSlice);
var
  j: Integer;
  wx, wy, wz, intensity, denom, frac, yRange: Double;
  VR, VG, VB: array of Double;
begin
  intensity := 1 - Slice.Age / FMaxSeries;
  if intensity <= 0 then Exit;
  if intensity > 1 then intensity := 1;
  wz := (Slice.Age / FMaxSeries - 0.5) * StackDepth;
  if Slice.N > 1 then denom := Slice.N - 1 else denom := 1;
  yRange := FYMax - FYMin;

  SetLength(VR, Slice.N);
  SetLength(VG, Slice.N);
  SetLength(VB, Slice.N);
  for j := 0 to Slice.N - 1 do begin
    if yRange > 0 then frac := (Slice.Y[j] - FYMin) / yRange else frac := 0;
    if frac < 0 then frac := 0
    else if frac > 1 then frac := 1;
    // Cubed, not used linearly: FYMin/FYMax are the GLOBAL extremes across
    // every currently-held slice, so a single rare outlier at either end
    // (one deep noise null, one genuine tall peak) stretches the range far
    // wider than where the bulk of ordinary data actually sits - linear
    // interpolation over that full range would land most everyday values
    // in the gradient's washed-out middle (a muddy blue-red blend) rather
    // than clearly at the LowColor end. Cubing frac before interpolating
    // pulls typical/mid-range values back down towards 0 (LowColor) while
    // leaving frac=1 (the true max) at HighColor untouched - so the noise
    // floor reads as a clean, consistent LowColor and only genuine
    // standout peaks pull towards HighColor, which is the actual "peaks
    // show up better against the noise" effect asked for.
    frac := frac * frac * frac;
    VR[j] := (FLowR + (FHighR - FLowR) * frac) * intensity;
    VG[j] := (FLowG + (FHighG - FLowG) * frac) * intensity;
    VB[j] := (FLowB + (FHighB - FLowB) * frac) * intensity;
  end;

  glBegin(GL_TRIANGLE_STRIP);
    for j := 0 to Slice.N - 1 do begin
      wx := (j / denom - 0.5) * WorldWidth;
      wy := (Slice.Y[j] / FYScale) * HalfH;
      glColor3d(VR[j], VG[j], VB[j]);
      glVertex3d(wx, wy, wz);
      glColor3d(0, 0, 0);
      glVertex3d(wx, 0, wz);
    end;
  glEnd;

  glLineWidth(1.5);
  glBegin(GL_LINE_STRIP);
    for j := 0 to Slice.N - 1 do begin
      wx := (j / denom - 0.5) * WorldWidth;
      wy := (Slice.Y[j] / FYScale) * HalfH;
      glColor3d(Min(1.0, VR[j] * 1.3), Min(1.0, VG[j] * 1.3), Min(1.0, VB[j] * 1.3));
      glVertex3d(wx, wy, wz);
    end;
  glEnd;
end;

// Three white axis lines meeting at the stack's front-left corner - X=
// -HalfW (index 0), Y=0 (value 0, the X-T base plane every ribbon's floor
// sits in - see DrawSlice's own comment), Z=-HalfD (Age=0, the
// just-added/nearest slice's position) - rather than through the data's
// own centre, as TVMPlot3D's axes do: with the Index and Time axes lying
// flat in that Y=0 plane, this corner frame reads as the actual ground
// the stack sits on, and the Value axis is the one line that rises above
// (and dips below) it. Per-axis tick points are white too (no per-axis
// colour coding, matching the "white axes" requirement directly) -
// numeric labels are drawn separately in pixel space by DrawAxisLabels
// once this frame's camera transform is known.
procedure TVMPlotStack.DrawAxisLines;
var
  i: Integer;
begin
  glLineWidth(1.5);
  glColor3f(1, 1, 1);
  glBegin(GL_LINES);
    glVertex3d(-HalfW, -HalfH, -HalfD); glVertex3d(-HalfW, HalfH, -HalfD);
    glVertex3d(-HalfW, 0, -HalfD); glVertex3d(HalfW, 0, -HalfD);
    glVertex3d(-HalfW, 0, -HalfD); glVertex3d(-HalfW, 0, HalfD);
  glEnd;

  glPointSize(4);
  glColor3f(1, 1, 1);
  glBegin(GL_POINTS);
    for i := 0 to High(FYTicks) do
      glVertex3d(-HalfW, (FYTicks[i] / FYScale) * HalfH, -HalfD);
    for i := 0 to High(FXTicks) do
      glVertex3d((FXTicks[i] / Max(FFrontN - 1, 1) - 0.5) * WorldWidth, 0, -HalfD);
    for i := 0 to High(FZTicks) do
      glVertex3d(-HalfW, 0, (FZTicks[i] / FMaxSeries - 0.5) * StackDepth);
  glEnd;
end;

// Projects a 3D world point to this frame's screen pixel coordinates by
// replaying - in plain Pascal, not via a GL matrix query - the exact
// camera transform Paint sets up on the GL matrix stack: glRotatef(FPitch,
// 1,0,0); glRotatef(FYaw,0,1,0); then an orthographic glOrtho(-FZoom*
// aspect,FZoom*aspect,-FZoom,FZoom,-100,100). No perspective divide, and
// no camera translate to account for (see the DefaultYaw/DefaultPitch/
// DefaultZoom comment above for why) - unlike TVMPlot3D.WorldToScreen
// (uVMPlot3D.pas), this is a straight orthographic projection: a world
// point's screen position depends only on its rotated (x,y), scaled by
// the same FZoom-derived factor Paint's own glOrtho call uses, regardless
// of depth. infront is always True (an orthographic projection has no
// "behind the camera" case within the generous +-100 near/far range every
// point here sits well inside) - kept as an out parameter purely so every
// call site's existing "if infront then ..." guard keeps compiling
// unchanged.
procedure TVMPlotStack.WorldToScreen(wx, wy, wz: Double; VW, VH: Integer;
  out sx, sy: Double; out infront: Boolean);
var
  yawRad, pitchRad, aspect, halfW: Double;
  x1, y1, z1, x2, y2, ndcX, ndcY: Double;
begin
  yawRad := FYaw * Pi / 180;
  pitchRad := FPitch * Pi / 180;

  x1 := wx * Cos(yawRad) + wz * Sin(yawRad);
  y1 := wy;
  z1 := -wx * Sin(yawRad) + wz * Cos(yawRad);

  x2 := x1;
  y2 := y1 * Cos(pitchRad) - z1 * Sin(pitchRad);

  infront := True;

  aspect := VW / VH;
  halfW := FZoom * aspect;
  ndcX := x2 / halfW;
  ndcY := y2 / FZoom;

  sx := (ndcX * 0.5 + 0.5) * VW;
  sy := (ndcY * 0.5 + 0.5) * VH;
end;

procedure TVMPlotStack.InvalidateTextures;
begin
  FTexturesBuilt := False;
end;

procedure TVMPlotStack.FreeTextTexture(var Tex: TVMPlotTextTexture);
begin
  if Tex.Built then begin
    glDeleteTextures(1, @Tex.TexID);
    Tex.Built := False;
  end;
end;

procedure TVMPlotStack.FreeAllTextures;
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

// Renders S once via the LCL font engine into an RGBA GL texture, text
// colour (TR,TG,TB), alpha = 255-luminance. Identical technique to
// TVMPlot3D.CreateTextTexture (uVMPlot3D.pas) - see that function's own
// comment for the full rationale; duplicated rather than shared, same as
// WorldToScreen above.
function TVMPlotStack.CreateTextTexture(const S: string; FontSize: Integer;
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

// TitleR/G/B is a light yellow, LabelR/G/B a light grey - both chosen for
// contrast against the black background, same rationale as TVMPlot3D's
// BuildTextures (uVMPlot3D.pas).
procedure TVMPlotStack.BuildTextures;
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

procedure TVMPlotStack.DrawTextTexture(const Tex: TVMPlotTextTexture;
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
// see Paint. Structurally identical to TVMPlot3D.DrawAxisLabels
// (uVMPlot3D.pas), just against this component's own corner-frame axis
// geometry instead of through-the-origin axes.
procedure TVMPlotStack.DrawAxisLabels;
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
    for i := 0 to High(FYTicks) do begin
      WorldToScreen(-HalfW, (FYTicks[i] / FYScale) * HalfH,
        -HalfD, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FYTickTex[i], sx - 8, sy, 0, 1, 0.5);
    end;
    for i := 0 to High(FXTicks) do begin
      WorldToScreen((FXTicks[i] / Max(FFrontN - 1, 1) - 0.5) * WorldWidth, 0,
        -HalfD, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FXTickTex[i], sx, sy - 8, 0, 0.5, 1);
    end;
    for i := 0 to High(FZTicks) do begin
      WorldToScreen(-HalfW, 0, (FZTicks[i] / FMaxSeries - 0.5) * StackDepth,
        VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FZTickTex[i], sx - 8, sy - 8, 0, 1, 1);
    end;

    if FXAxisTitle <> '' then begin
      WorldToScreen(0, -HalfH * 0.15, -HalfD, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FXAxisTitleTex, sx, sy - 8, 0, 0.5, 1);
    end;
    if FYAxisTitle <> '' then begin
      WorldToScreen(-HalfW * 1.25, 0, -HalfD, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FYAxisTitleTex, sx, sy, 0, 0.5, 0.5);
    end;
    if FZAxisTitle <> '' then begin
      WorldToScreen(-HalfW, 0, 0, VW, VH, sx, sy, infront);
      if infront then DrawTextTexture(FZAxisTitleTex, sx - 24, sy, 0, 1, 0.5);
    end;
  end;

  glDisable(GL_TEXTURE_2D);
end;

// Unlit throughout - deliberately no GL_LIGHTING/normals anywhere in this
// component, unlike TVMPlot3D: the "bright top edge fading to black"
// look is a pure per-vertex colour gradient (see DrawSlice), not a
// lit-surface effect, and a black background/floor makes an actual light
// source unnecessary. GL_DEPTH_TEST is likewise never enabled - see this
// unit's own COMPOSITING rationale for why draw order alone is what
// produces "new graphs hide old ones" here.
procedure TVMPlotStack.Paint;
var
  aspect: Double;
  i: Integer;
begin
  if not MakeCurrent then Exit;
  if (Width = 0) or (Height = 0) then Exit;

  if not FTexturesBuilt then begin
    BuildTextures;
    FTexturesBuilt := True;
  end;

  glViewport(0, 0, Width, Height);
  aspect := Width / Height;

  // True orthographic projection - deliberately not gluPerspective - see
  // the DefaultYaw/DefaultPitch/DefaultZoom comment above for why. FZoom
  // is the view volume's half-height in world units (DoMouseWheel zooms
  // by shrinking/growing it, not by moving a camera); +-100 for near/far
  // comfortably clips nothing this component ever draws (StackDepth/
  // WorldWidth/ValueScale are all well under that).
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(-FZoom * aspect, FZoom * aspect, -FZoom, FZoom, -100, 100);

  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glRotatef(FPitch, 1, 0, 0);
  glRotatef(FYaw, 0, 1, 0);

  glClearColor(0, 0, 0, 1);
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT);
  glShadeModel(GL_SMOOTH);
  glDisable(GL_LIGHTING);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);

  // Back-to-front: oldest (largest Age, furthest) first, newest (Age~0,
  // nearest) last - see this unit's own COMPOSITING rationale for why
  // this plain draw order alone is enough for a nearer graph to hide an
  // older one's overlapping features.
  for i := High(FSlices) downto 0 do
    DrawSlice(FSlices[i]);

  // Axis lines/ticks are drawn AFTER every ribbon, not before - the
  // Index (X) axis sits at the same Z as the frontmost (Age=0) slice's
  // own floor (see DrawAxisLines), so with no depth test in play (see
  // this procedure's own header comment) an opaque frontmost ribbon
  // drawn on top of it would otherwise paint straight over it wherever
  // the curve swings through that row of pixels. Drawing axes last keeps
  // them always legible, in front of every graph, regardless of how tall
  // the frontmost one gets.
  if FShowAxes then DrawAxisLines;

  // --- pixel-space pass: main title, axis titles, tick labels - see
  // TVMPlot3D.Paint's own comment for why DrawAxisLabels runs against the
  // still-active 3D camera transform (via WorldToScreen) rather than
  // after switching to pixel space; only the final glOrtho/glViewport
  // below (for drawing the resulting 2D label quads) needs to be
  // pixel-space. ---
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glViewport(0, 0, Width, Height);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  DrawAxisLabels;

  SwapBuffers;
end;

procedure TVMPlotStack.Resize;
begin
  inherited Resize;
  Invalidate;
end;

procedure TVMPlotStack.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then begin
    FDragging := True;
    FLastMouseX := X;
    FLastMouseY := Y;
  end;
end;

procedure TVMPlotStack.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  FYaw := FYaw + (X - FLastMouseX) * 0.5;
  FPitch := EnsureRange(FPitch + (Y - FLastMouseY) * 0.5, -89.0, 89.0);
  FLastMouseX := X;
  FLastMouseY := Y;
  Invalidate;
end;

procedure TVMPlotStack.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  FDragging := False;
end;

function TVMPlotStack.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  // Smaller FZoom = smaller ortho view volume = zoomed in, same sign
  // convention (WheelDelta>0 zooms in) as the camera-distance version
  // this replaced.
  FZoom := EnsureRange(FZoom - WheelDelta / 120 * 0.3, 1.5, 20.0);
  Invalidate;
  result := True;
end;

procedure Register;
begin
  {$I uvmplotstack_icon.lrs}
  RegisterComponents('newVM', [TVMPlotStack]);
end;

end.
