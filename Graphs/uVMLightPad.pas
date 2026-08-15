unit uVMLightPad;

{*******************************************************************************

     TVMLightPad - a small, reusable circular "XY pad" LCL control for
     interactively steering TVMPlot3D's (Graphs/uVMPlot3D.pas) OpenGL
     headlamp light direction. Not tied to TVMPlot3D itself - it just
     exposes LightX/LightY (each roughly -1..1, clamped to the unit circle)
     and an OnChange event, the same "control exposes state + fires
     OnChange, host form forwards into the plot component's own property"
     pattern this repo's demos already use for Wireframe/ShowAxes checkboxes
     (see uplot3dmain.pas/u2DBVPMain.pas's *CheckBoxChange handlers) - so it
     stays a plain 2D control with no OpenGL/newVM dependency of its own,
     and any host form wires a one-line OnChange handler to whichever
     TVMPlot3D it wants to drive.

     Interaction: click-drag anywhere in the control sets LightX/LightY from
     the drag point, normalised so the pad's own radius maps to the unit
     circle and clamped to it (a click near a corner of the control doesn't
     produce a direction longer than 1). MouseCapture is set for the
     duration of the drag so a fast drag that briefly leaves the pad's small
     bounds keeps tracking rather than dropping the interaction.

     AXIS MAPPING - both LightX and LightY are the *negation* of where the
     dot sits, on both axes: dot on the left sends a positive LightX
     (surface lit as if from the right), dot on the right sends negative
     (lit from the left); dot at the top sends a negative LightY, dot at
     the bottom sends positive. Confirmed directly against the running
     demo, not derived (see uVMPlot3D.pas's own DefaultLightY comment for
     why eye-space light-direction sign shouldn't be reasoned about in the
     abstract for this component - the same caution applies here). The dot
     itself still visually follows the cursor 1:1 (UpdateFromMouse and
     Paint's dot-position code apply the same negation, so it cancels out
     for that purpose) - only the LightX/LightY *values* sent are mirrored
     relative to a naive "dot position = light position" mapping.

     A TGraphicControl, not a TCustomControl: it owns no child controls,
     needs no keyboard focus, and (like TLabel/TShape/TImage, the LCL's own
     TGraphicControl descendants) mouse events work perfectly well on it
     without a native window handle of its own - lighter weight than a full
     TCustomControl for a control this simple.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, LCLType;

type

  { TVMLightPad }

  TVMLightPad = class(TGraphicControl)
  private
    FLightX, FLightY: Double;
    FDragging: Boolean;
    FOnChange: TNotifyEvent;
    procedure SetLightX(AValue: Double);
    procedure SetLightY(AValue: Double);
    procedure UpdateFromMouse(X, Y: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer); override;
  public
    constructor Create(TheOwner: TComponent); override;
    // Sets both axes and fires OnChange once, rather than twice via the two
    // published setters below - what the drag interaction itself uses.
    procedure SetLightXY(AX, AY: Double);
  published
    property LightX: Double read FLightX write SetLightX;
    property LightY: Double read FLightY write SetLightY;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

procedure Register;

implementation

// Default light direction - matches TVMPlot3D's own pre-TVMLightPad default
// (see that unit's Paint), so a freshly-dropped/created pad starts in sync
// with a freshly-created TVMPlot3D's existing appearance rather than
// silently retargeting the light the moment a host form wires them together.
const
  DefaultLightX = 0.5;
  DefaultLightY = -0.6;
  DefaultPadSize = 90;
  PadMargin = 4;
  // TVMPlot3D's headlamp is a directional (not positional) light, so there's
  // no literal "distance from the object" to move - but pushing the XY
  // components further from zero relative to the fixed Z (0.65, see
  // TVMPlot3D.Paint) still steers the light towards a more extreme, grazing
  // angle, which is the visual effect a larger XY range is standing in for
  // here. MaxLightMagnitude is how far the pad's own edge maps to (so
  // dragging to the rim now reaches roughly atan(3/0.65) =~ 78 degrees off
  // the view axis, versus ~57 degrees when the pad clamped to the unit
  // circle) - raise it further for an even more extreme available angle.
  MaxLightMagnitude = 3.0;

constructor TVMLightPad.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  Width := DefaultPadSize;
  Height := DefaultPadSize;
  FLightX := DefaultLightX;
  FLightY := DefaultLightY;
end;

procedure TVMLightPad.SetLightX(AValue: Double);
begin
  SetLightXY(AValue, FLightY);
end;

procedure TVMLightPad.SetLightY(AValue: Double);
begin
  SetLightXY(FLightX, AValue);
end;

procedure TVMLightPad.SetLightXY(AX, AY: Double);
begin
  if (FLightX = AX) and (FLightY = AY) then Exit;
  FLightX := AX;
  FLightY := AY;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

// Maps a control-relative pixel point to a light direction: centred on the
// control, scaled so the drawn circle's own radius is length MaxLightMagnitude,
// and clamped to that radius so dragging out towards (or past) a corner of
// the control's bounding rectangle can't produce a direction longer than it.
procedure TVMLightPad.UpdateFromMouse(X, Y: Integer);
var
  cx, cy, r, nx, ny, len: Double;
begin
  cx := Width / 2;
  cy := Height / 2;
  r := Min(Width, Height) / 2 - PadMargin;
  if r < 1 then r := 1;
  nx := -(X - cx) / r * MaxLightMagnitude;   // negated on both axes - see header comment
  ny := -(Y - cy) / r * MaxLightMagnitude;
  len := Sqrt(nx * nx + ny * ny);
  if len > MaxLightMagnitude then begin
    nx := nx / len * MaxLightMagnitude;
    ny := ny / len * MaxLightMagnitude;
  end;
  SetLightXY(nx, ny);
end;

procedure TVMLightPad.MouseDown(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then begin
    FDragging := True;
    MouseCapture := True;
    UpdateFromMouse(X, Y);
  end;
end;

procedure TVMLightPad.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if FDragging then UpdateFromMouse(X, Y);
end;

procedure TVMLightPad.MouseUp(Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then begin
    FDragging := False;
    MouseCapture := False;
  end;
end;

// Dark circular pad (matching TVMPlot3D's own dark background) with a
// crosshair for reference and a small filled dot at the current LightX/
// LightY - deliberately yellow, the same colour TVMPlot3D's own Title text
// uses, so the pad reads as "the thing that controls the light" at a
// glance rather than needing a caption of its own.
procedure TVMLightPad.Paint;
var
  cx, cy, r, dotx, doty: Integer;
begin
  cx := Width div 2;
  cy := Height div 2;
  r := Min(Width, Height) div 2 - PadMargin;
  if r < 1 then r := 1;

  Canvas.Brush.Color := RGBToColor(30, 30, 38);
  Canvas.Pen.Color := RGBToColor(120, 120, 130);
  Canvas.Pen.Width := 1;
  Canvas.Ellipse(cx - r, cy - r, cx + r, cy + r);

  Canvas.Pen.Color := RGBToColor(65, 65, 75);
  Canvas.Line(cx - r, cy, cx + r, cy);
  Canvas.Line(cx, cy - r, cx, cy + r);

  // Matching negation to UpdateFromMouse's, so the dot still visually
  // follows the cursor 1:1 despite LightX/LightY themselves being mirrored.
  dotx := cx - Round(FLightX / MaxLightMagnitude * r);
  doty := cy - Round(FLightY / MaxLightMagnitude * r);
  Canvas.Brush.Color := RGBToColor(255, 220, 40);
  Canvas.Pen.Color := clBlack;
  Canvas.Ellipse(dotx - 5, doty - 5, dotx + 5, doty + 5);
end;

procedure Register;
begin
  RegisterComponents('newVM', [TVMLightPad]);
end;

end.
