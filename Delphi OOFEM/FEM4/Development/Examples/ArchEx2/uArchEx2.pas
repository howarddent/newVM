unit uArchEx2;

{ ArchEx2 - stresses in a Perpendicular (four-centred) masonry arch.

  The companion to ArchEx1, and meant to be read next to it: same span,
  same ring thickness, same barrel depth, same masonry, same mesh
  density, same solve, same report. Only the SHAPE of the arch differs,
  so any difference between the two reports is a difference between a
  Roman semicircle and a late-Gothic four-centred arch, and nothing else.

  The four-centred (Tudor) arch is the arch of the English Perpendicular
  style: a depressed pointed arch struck from four centres, two short
  radii at the springings and two long radii meeting at a point on the
  crown. Its construction here is parametric rather than copied from a
  pattern book, so that the proportions can be changed without redrawing
  anything:

    - the haunch arcs have radius r1, struck from centres on the
      springing line at the quarter points of the span (HaunchCentreX);
    - each crown arc has radius r2 (CrownRadius), struck from a centre
      BELOW the springing line and on the FAR side of the centreline -
      which is what makes the two crown arcs meet at an angle and give
      the arch its point, rather than running smoothly into each other
      as a three-centred basket handle would;
    - the crown centre is fixed by requiring tangency with the haunch
      arc at the junction, i.e. that the junction point and the two
      centres are collinear, so the intrados has no kink there;
    - with the defaults below (4.0 m span, r1 = 1.0, junction at 60
      degrees, r2 = 4.0) the arch rises 1.371 m - a rise/span of 0.34
      against the semicircle's 0.50 - and closes at the apex with an
      included angle of 14.4 degrees.

  The ring is divided into 14 voussoirs, 3 on each haunch arc and 4 on
  each crown arc, which comes out at almost equal voussoir lengths
  (0.349 m against 0.398 m). Unlike ArchEx1's semicircle there is no
  keystone: the two halves meet on a joint at the apex, mitred on the
  vertical centreline - the bisector of the two arcs' radial directions,
  which is where a mason would put it.

  Everything downstream of the geometry - the bonded conformal mesh, the
  plane-stress solve, the caveat that masonry carries no tension, and the
  thrust-line-against-the-middle-third report - is as described in
  uArchEx1.pas's own header. Two pieces of machinery did have to be
  generalised, because a four-centred arch has no single centre to
  measure from:

    - each voussoir carries its own arc centre, so the hoop direction is
      taken from the block's own arc rather than from the origin;
    - joints are found by distance from the joint PLANE, restricted to
      the two blocks that meet there, rather than by angle about a common
      centre. That also handles the apex joint, which is not radial to
      either arc. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, newVM, newVMsparse,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.StructuralEngine,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh;

const

  (******************** GEOMETRY (SI units: m, N, Pa) ********************)

  // Matched to ArchEx1 so the two are comparable: 4.0 m clear span,
  // 0.6 m ring, 1.0 m barrel.
  HalfSpan = 2.0;
  RingThickness = 0.6;
  BarrelDepth = 1.0;

  // Haunch arc centres, on the springing line at the quarter points of
  // the span. The haunch radius follows: HalfSpan - HaunchCentreX.
  HaunchCentreX = 1.0;

  // Where the haunch arc hands over to the crown arc, as an angle about
  // the haunch centre measured from the springing line.
  JunctionAngleDeg = 60.0;

  // Radius of the two crown arcs. Larger = flatter crown and a sharper
  // point; at CrownRadius = 3.0 the crown centre lands on the centreline
  // and the point disappears altogether, so keep this well above it.
  CrownRadius = 4.0;

  // Voussoirs per half arch: 3 + 4 = 7, so 14 in all, with a joint - not
  // a keystone - at the apex.
  NbHaunchBlocks = 3;
  NbCrownBlocks = 4;

  NbBlocks = 2 * (NbHaunchBlocks + NbCrownBlocks);

  // Structured mesh per voussoir, as ArchEx1: NbAcrossRing quads through
  // the ring by NbAlongBlock along the arc.
  NbAcrossRing = 6;
  NbAlongBlock = 5;

  (******************** MATERIAL ********************)

  Density = 2200.0;        // kg/m3 - limestone masonry
  ElasticModulus = 8.0e9;  // Pa
  PoissonRatio = 0.2;
  ThermalExpansion = 1.0e-5;

  GravityAccel = -9.81;    // m/s2, acting along -Y

  MortarTensileStrength = 1.0e5;

  (******************** LOADING ********************)

  LoadFraction = 0.25;

  LoadCaseSelfWeight = 1;
  LoadCaseCrown = 2;
  LoadCaseHaunch = 3;

  // Where the superimposed load sits, as a fraction of the arch's own
  // intrados length measured from the right springing. 0.50 is the apex;
  // 0.75 is the quarter point of the arch's length, measured from the
  // LEFT springing - the same position ArchEx1 loads (its 135 degrees is
  // 45 degrees of a 180 degree arc from that springing).
  CrownLoadPosition = 0.50;
  HaunchLoadPosition = 0.75;

  (******************** POST-PROCESSING ********************)

  ViewDisplacement = 0;
  ViewHoop = 3;

type

  // One of the four circular arcs the ring is struck from.
  RArc = record

    cx, cy : Double;   // centre
    r : Double;        // intrados radius

  end;

  // One voussoir: a slice of one arc between two joints.
  RBlock = record

    Arc : Integer;
    Ang0, Ang1 : Double;   // angles about the arc centre, radians
    EleLen : Double;       // along-arch length of one element

  end;

  // A radial joint between two voussoirs, or the mitred joint at the
  // apex, or a springing face. Stored as the plane it lies in, since
  // that is what the thrust-line integration needs, and it is the one
  // description that covers all three kinds.
  RJoint = record

    x0, y0 : Double;   // intrados end
    x1, y1 : Double;   // extrados end
    mx, my : Double;   // mid-joint
    tx, ty : Double;   // unit vector, intrados -> extrados
    nx, ny : Double;   // unit normal to the joint plane (along the arch)
    h : Double;        // joint depth, |P1 - P0|
    Band : Double;     // half-width of the element band either side

  end;

  TArchModel = class(TObject)

  private

    FLoadCase : Integer;

    FGmsh : TGmsh;
    FEngine : TStructuralEngine;

    FRho, FE, FPoisson, FAlpha : TExpressionList;
    FZero : TExpressionList;
    FNodeLoad : TExpressionList;

    // Geometry, built by SetupGeometry.
    FArcs : Array[0..3] of RArc;
    FBlocks : Array[1..NbBlocks] of RBlock;
    FJoints : Array[0..NbBlocks] of RJoint;

    FApexY, FApexYExt : Double;
    FIntradosLength : Double;

    FTotalArea : Double;
    FSelfWeight : Double;
    FAppliedLoad : Double;
    FNbLoadedNodes : Integer;
    FLoadX, FLoadY : Double;

    FElapsed : Double;

    FEleBlock : TDoubleArray;
    FEleArea : TDoubleArray;
    FEleCx, FEleCy : TDoubleArray;   // centroid per element
    FEleNx, FEleNy : TDoubleArray;   // unit hoop direction per element
    FSxx, FSyy, FSxy : TDoubleArray;
    FS1, FS2, FSn, FVonMises : TDoubleArray;

    FUx, FUy, FUz : TDoubleArray;

    FCrownNode : Integer;
    FNbRestrained : Integer;

    procedure SetupGeometry;
    function ExtradosPointAt(s : Double; var px, py : Double) : Boolean;
    function OnExtrados(x, y : Double) : Boolean;

    procedure WriteGeoFile(const FileName : String);
    procedure BuildMesh;
    procedure CalcElementGeometry;
    procedure BuildModel;

    procedure ReportSummary;
    procedure ReportBlocks;
    procedure ReportJoints;

    procedure WriteScript(const FileName : String);

  public

    constructor Create(ALoadCase : Integer);
    destructor Destroy; override;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure PostProcess;

    procedure Run(ViewResults : Boolean);

  end;

implementation

const

  DataDir = '..' + PathDelim + 'Data' + PathDelim;

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  GmshExecutable = 'gmsh';
{$ENDIF}

  GeoFile = DataDir + 'archex2.geo';
  MshFile = DataDir + 'archex2.msh';
  PosFile = DataDir + 'archex2.pos';
  ScrFile = DataDir + 'archex2.scr';

  GeoTol = 1.0e-6;

  // Arc indices into FArcs.
  ArcHaunchRight = 0;
  ArcCrownRight = 1;
  ArcCrownLeft = 2;
  ArcHaunchLeft = 3;

var
  DotFS : TFormatSettings;

function Num(v : Double) : String;
begin

  Result := Format('%.10f', [v], DotFS);

end;

procedure SafeReWriteText(var F : TextFile);
const
  MaxAttempts = 8;
  RetryDelayMs = 50;
var
  Attempt : Integer;
begin

  for Attempt := 1 to MaxAttempts do
  begin
    try
      ReWrite(F);
      Exit;
    except
      if Attempt = MaxAttempts then
        raise;
      Sleep(RetryDelayMs);
    end;
  end;

end;

{ TArchModel }

constructor TArchModel.Create(ALoadCase : Integer);
begin

  FLoadCase := ALoadCase;

  FGmsh := TGmsh.Create;

  FCrownNode := -1;

  SetupGeometry;

end;

destructor TArchModel.Destroy;
begin

  FEngine.Free;

  FRho.Free;
  FE.Free;
  FPoisson.Free;
  FAlpha.Free;
  FZero.Free;
  FNodeLoad.Free;

  FGmsh.Free;

  inherited Destroy;

end;

function TArchModel.Constant(NodeId, ElementId : Integer) : Double;
begin

  Result := 0;

end;

(*******************************************************************
  The four-centred construction, solved rather than drawn.

  Right half, with the springing at (HalfSpan, 0):

    haunch arc   centre A = (HaunchCentreX, 0), radius r1 = HalfSpan -
                 HaunchCentreX, swept from 0 (the springing) to phi (the
                 junction);
    crown arc    centre B, radius r2 = CrownRadius, swept from the
                 junction to the apex on the centreline.

  Tangency at the junction J means J and the two centres are collinear,
  and since both arcs curve the same way B lies at

    B = A + (r1 - r2) * (cos phi, sin phi)

  which puts it below the springing line and - for r2 > 2*HalfSpan -
  r1... in practice for any r2 large enough - on the far side of the
  centreline. The apex is then where that arc crosses x = 0:

    apexY = B.y + sqrt(r2^2 - B.x^2)

  and because B.x is not zero the tangent there is not horizontal, so
  the two halves meet at a point. The left half is the mirror image, and
  the whole ring is traversed as a single monotonic sweep: 0 -> phi
  about A, phi -> apex about B, then the mirror of that back down to
  180 degrees about the left haunch centre.
********************************************************************)
procedure TArchModel.SetupGeometry;
var

  k, b, ArcId : Integer;

  phi, r1, r2, t, AngJunction, AngApex, dAng, ang : Double;

  BandNext, BandPrev : Double;

begin

  phi := DegToRad(JunctionAngleDeg);

  r1 := HalfSpan - HaunchCentreX;
  r2 := CrownRadius;
  t := r1 - r2;

  FArcs[ArcHaunchRight].cx := HaunchCentreX;
  FArcs[ArcHaunchRight].cy := 0;
  FArcs[ArcHaunchRight].r := r1;

  FArcs[ArcCrownRight].cx := HaunchCentreX + t * Cos(phi);
  FArcs[ArcCrownRight].cy := t * Sin(phi);
  FArcs[ArcCrownRight].r := r2;

  // Mirror image about x = 0.
  FArcs[ArcCrownLeft].cx := -FArcs[ArcCrownRight].cx;
  FArcs[ArcCrownLeft].cy := FArcs[ArcCrownRight].cy;
  FArcs[ArcCrownLeft].r := r2;

  FArcs[ArcHaunchLeft].cx := -HaunchCentreX;
  FArcs[ArcHaunchLeft].cy := 0;
  FArcs[ArcHaunchLeft].r := r1;

  if Abs(FArcs[ArcCrownRight].cx) < GeoTol then
    raise Exception.Create('CrownRadius gives a crown centre on the centreline: ' +
      'the arch would close smoothly instead of at a point. Increase CrownRadius.');

  FApexY := FArcs[ArcCrownRight].cy +
            Sqrt(Sqr(r2) - Sqr(FArcs[ArcCrownRight].cx));

  FApexYExt := FArcs[ArcCrownRight].cy +
               Sqrt(Sqr(r2 + RingThickness) - Sqr(FArcs[ArcCrownRight].cx));

  // Angles about the crown centre of the junction and of the apex.
  AngJunction := ArcTan2(FArcs[ArcHaunchRight].cy + r1 * Sin(phi) - FArcs[ArcCrownRight].cy,
                         FArcs[ArcHaunchRight].cx + r1 * Cos(phi) - FArcs[ArcCrownRight].cx);

  AngApex := ArcTan2(FApexY - FArcs[ArcCrownRight].cy,
                     0 - FArcs[ArcCrownRight].cx);

  (******************** BLOCKS ********************)

  // Right haunch: blocks 1..NbHaunchBlocks, 0 -> phi about A.
  dAng := phi / NbHaunchBlocks;

  for b := 1 to NbHaunchBlocks do
  begin
    FBlocks[b].Arc := ArcHaunchRight;
    FBlocks[b].Ang0 := (b - 1) * dAng;
    FBlocks[b].Ang1 := b * dAng;
  end;

  // Right crown: junction -> apex about B.
  dAng := (AngApex - AngJunction) / NbCrownBlocks;

  for b := 1 to NbCrownBlocks do
  begin
    FBlocks[NbHaunchBlocks + b].Arc := ArcCrownRight;
    FBlocks[NbHaunchBlocks + b].Ang0 := AngJunction + (b - 1) * dAng;
    FBlocks[NbHaunchBlocks + b].Ang1 := AngJunction + b * dAng;
  end;

  // Left crown: apex -> junction about the mirrored centre, which in
  // mirrored angles runs from (Pi - AngApex) up to (Pi - AngJunction).
  for b := 1 to NbCrownBlocks do
  begin
    FBlocks[NbHaunchBlocks + NbCrownBlocks + b].Arc := ArcCrownLeft;
    FBlocks[NbHaunchBlocks + NbCrownBlocks + b].Ang0 := Pi - AngApex + (b - 1) * dAng;
    FBlocks[NbHaunchBlocks + NbCrownBlocks + b].Ang1 := Pi - AngApex + b * dAng;
  end;

  // Left haunch: (Pi - phi) -> Pi about the left haunch centre.
  dAng := phi / NbHaunchBlocks;

  for b := 1 to NbHaunchBlocks do
  begin
    FBlocks[NbHaunchBlocks + 2 * NbCrownBlocks + b].Arc := ArcHaunchLeft;
    FBlocks[NbHaunchBlocks + 2 * NbCrownBlocks + b].Ang0 := Pi - phi + (b - 1) * dAng;
    FBlocks[NbHaunchBlocks + 2 * NbCrownBlocks + b].Ang1 := Pi - phi + b * dAng;
  end;

  FIntradosLength := 0;

  for b := 1 to NbBlocks do
  begin

    ArcId := FBlocks[b].Arc;

    FBlocks[b].EleLen := FArcs[ArcId].r *
      Abs(FBlocks[b].Ang1 - FBlocks[b].Ang0) / NbAlongBlock;

    FIntradosLength := FIntradosLength +
      FArcs[ArcId].r * Abs(FBlocks[b].Ang1 - FBlocks[b].Ang0);

  end;

  (******************** JOINTS ********************)

  // Joint k sits between block k and block k+1, so it is the start of
  // block k+1 (and the end of block k). Every joint but the apex is
  // radial to the arc it belongs to; the apex joint is the mitre on the
  // centreline, which is the bisector of the two arcs' radial
  // directions and so vertical by symmetry.
  for k := 0 to NbBlocks do
  begin

    if k = NbBlocks div 2 then
    begin

      // The apex.
      FJoints[k].x0 := 0;
      FJoints[k].y0 := FApexY;
      FJoints[k].x1 := 0;
      FJoints[k].y1 := FApexYExt;

    end
    else
    begin

      if k < NbBlocks then
      begin
        b := k + 1;
        ang := FBlocks[b].Ang0;
      end
      else
      begin
        b := NbBlocks;
        ang := FBlocks[b].Ang1;
      end;

      ArcId := FBlocks[b].Arc;

      FJoints[k].x0 := FArcs[ArcId].cx + FArcs[ArcId].r * Cos(ang);
      FJoints[k].y0 := FArcs[ArcId].cy + FArcs[ArcId].r * Sin(ang);

      FJoints[k].x1 := FArcs[ArcId].cx + (FArcs[ArcId].r + RingThickness) * Cos(ang);
      FJoints[k].y1 := FArcs[ArcId].cy + (FArcs[ArcId].r + RingThickness) * Sin(ang);

    end;

    FJoints[k].mx := 0.5 * (FJoints[k].x0 + FJoints[k].x1);
    FJoints[k].my := 0.5 * (FJoints[k].y0 + FJoints[k].y1);

    FJoints[k].h := Sqrt(Sqr(FJoints[k].x1 - FJoints[k].x0) +
                         Sqr(FJoints[k].y1 - FJoints[k].y0));

    FJoints[k].tx := (FJoints[k].x1 - FJoints[k].x0) / FJoints[k].h;
    FJoints[k].ty := (FJoints[k].y1 - FJoints[k].y0) / FJoints[k].h;

    // Normal to the joint plane, i.e. along the arch.
    FJoints[k].nx := FJoints[k].ty;
    FJoints[k].ny := -FJoints[k].tx;

    // Reach the first element layer either side of the joint and no
    // further: layer centroids sit at 0.5, 1.5, ... element lengths
    // from the joint, and the two sides may have different element
    // lengths where a haunch block meets a crown block.
    BandPrev := MaxDouble;
    BandNext := MaxDouble;

    if k >= 1 then
      BandPrev := FBlocks[k].EleLen;

    if k < NbBlocks then
      BandNext := FBlocks[k + 1].EleLen;

    FJoints[k].Band := 0.9 * Min(BandPrev, BandNext);

  end;

end;


{ The extrados point radially outside the intrados point a distance s
  along the intrados from the right springing - i.e. indexed
  by intrados arc length, not by its own. That keeps a load position
  quoted as a fraction of the arch's length meaning the same thing on
  either face. }
function TArchModel.ExtradosPointAt(s : Double; var px, py : Double) : Boolean;
var

  b, ArcId : Integer;

  Len, ang : Double;

begin

  Result := False;

  if (s < 0) or (s > FIntradosLength) then
    Exit;

  for b := 1 to NbBlocks do
  begin

    ArcId := FBlocks[b].Arc;

    Len := FArcs[ArcId].r * Abs(FBlocks[b].Ang1 - FBlocks[b].Ang0);

    if (s <= Len) or (b = NbBlocks) then
    begin

      ang := FBlocks[b].Ang0 +
             (FBlocks[b].Ang1 - FBlocks[b].Ang0) * (s / Len);

      px := FArcs[ArcId].cx + (FArcs[ArcId].r + RingThickness) * Cos(ang);
      py := FArcs[ArcId].cy + (FArcs[ArcId].r + RingThickness) * Sin(ang);

      Exit(True);

    end;

    s := s - Len;

  end;

end;

{ Is this node on the outer face of the ring? True when it lies on the
  extrados circle of any of the four arcs - which is enough on its own,
  since the arcs are tangent-continuous and every one of them is offset
  by the same RingThickness, so no interior point of the ring can sit at
  the extrados radius of the arc it belongs to. }
function TArchModel.OnExtrados(x, y : Double) : Boolean;
var

  a : Integer;

  d : Double;

begin

  Result := False;

  for a := 0 to 3 do
  begin

    d := Sqrt(Sqr(x - FArcs[a].cx) + Sqr(y - FArcs[a].cy));

    if Abs(d - (FArcs[a].r + RingThickness)) < 1.0e-6 then
      Exit(True);

  end;

end;

(*******************************************************************
  Geometry file, one gmsh plane surface per voussoir, exactly as
  ArchEx1 - except that each block names its own arc centre, and the
  apex joint closes two straight lines rather than two radii.

    point   1+a             centre of arc a               (a = 0..3)
    point   10+k            intrados point at joint k     (k = 0..N)
    point   10+(N+1)+k      extrados point at joint k
    line    10+k            joint k, intrados -> extrados
    line    10+(N+1)+k      intrados arc of block k+1     (k = 0..N-1)
    line    10+(N+1)+N+k    extrados arc of block k+1
    loop    200+k, surface 500+k, physical surface k+1

  Adjacent blocks share the joint line, so the mesh is conformal across
  every joint including the apex.
********************************************************************)
procedure TArchModel.WriteGeoFile(const FileName : String);

  function LJoint(i : Integer) : Integer;
  begin
    Result := 10 + i;
  end;

  function LArcIn(i : Integer) : Integer;
  begin
    Result := 10 + (NbBlocks + 1) + i;
  end;

  function LArcOut(i : Integer) : Integer;
  begin
    Result := 10 + (NbBlocks + 1) + NbBlocks + i;
  end;

var

  F : TextFile;

  k, a, ArcId : Integer;

  Joints, Arcs : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, 'Mesh.MshFileVersion=1;');

    WriteLn(F, 'cl = ' + Num(RingThickness / NbAcrossRing) + ';');

    for a := 0 to 3 do
      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [1 + a, Num(FArcs[a].cx), Num(FArcs[a].cy)]));

    for k := 0 to NbBlocks do
    begin

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + k, Num(FJoints[k].x0), Num(FJoints[k].y0)]));

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + (NbBlocks + 1) + k, Num(FJoints[k].x1), Num(FJoints[k].y1)]));

    end;

    Joints := '';

    for k := 0 to NbBlocks do
    begin

      WriteLn(F, Format('Line(%d) = {%d,%d};',
        [LJoint(k), 10 + k, 10 + (NbBlocks + 1) + k]));

      if k > 0 then
        Joints := Joints + ',';

      Joints := Joints + IntToStr(LJoint(k));

    end;

    Arcs := '';

    for k := 0 to NbBlocks - 1 do
    begin

      ArcId := FBlocks[k + 1].Arc;

      // Circle(id) = {start, centre, end}. No arc here exceeds 20
      // degrees, well under gmsh's half-turn limit on one Circle.
      WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
        [LArcIn(k), 10 + k, 1 + ArcId, 10 + k + 1]));

      WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
        [LArcOut(k), 10 + (NbBlocks + 1) + k, 1 + ArcId,
         10 + (NbBlocks + 1) + k + 1]));

      if k > 0 then
        Arcs := Arcs + ',';

      Arcs := Arcs + IntToStr(LArcIn(k)) + ',' + IntToStr(LArcOut(k));

    end;

    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Joints, NbAcrossRing + 1]));
    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Arcs, NbAlongBlock + 1]));

    for k := 0 to NbBlocks - 1 do
    begin

      WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
        [200 + k, LJoint(k), LArcOut(k), LJoint(k + 1), LArcIn(k)]));

      WriteLn(F, Format('Plane Surface(%d) = {%d};', [500 + k, 200 + k]));

      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [500 + k, 10 + k, 10 + (NbBlocks + 1) + k,
         10 + (NbBlocks + 1) + k + 1, 10 + k + 1]));

      WriteLn(F, Format('Recombine Surface {%d};', [500 + k]));

      WriteLn(F, Format('Physical Surface(%d) = {%d};', [k + 1, 500 + k]));

    end;

  finally

    CloseFile(F);

  end;

end;

procedure TArchModel.BuildMesh;
var

  ExitCode : Cardinal;

begin

  WriteLn('Meshing ', NbBlocks, ' voussoirs with gmsh...');

  if not Sto_ShellExecute(GmshExecutable, [GeoFile, '-2'], ExitCode, 120000, True) then
    raise Exception.Create('Could not run gmsh (' + GmshExecutable +
      '). Install gmsh, or edit GmshExecutable in uArchEx2.pas.');

  if ExitCode <> 0 then
    raise Exception.Create('gmsh failed with exit code ' + IntToStr(ExitCode) +
      ' on ' + GeoFile);

  if not FileExists(MshFile) then
    raise Exception.Create('gmsh produced no mesh file (' + MshFile + ')');

  FGmsh.OpenFile(MshFile);
  FGmsh.ReadMesh;
  FGmsh.Close;

  WriteLn(Format('  %d nodes, %d elements', [FGmsh.NbNodes, FGmsh.NbElements]));

end;

{ Area and centroid of every element, its block (from the physical
  region gmsh wrote), and the hoop direction there - which, unlike
  ArchEx1's, is taken about the element's OWN arc centre. }
procedure TArchModel.CalcElementGeometry;
var

  i, j, n, nx, b, ArcId : Integer;

  cx, cy, x0, y0, x1, y1, a2, dx, dy, d : Double;

begin

  SetLength(FEleBlock, FGmsh.NbElements);
  SetLength(FEleArea, FGmsh.NbElements);
  SetLength(FEleCx, FGmsh.NbElements);
  SetLength(FEleCy, FGmsh.NbElements);
  SetLength(FEleNx, FGmsh.NbElements);
  SetLength(FEleNy, FGmsh.NbElements);

  FTotalArea := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] = GMSH_QUAD then
      n := 4
    else
      n := 3;

    cx := 0;
    cy := 0;
    a2 := 0;

    for j := 0 to n - 1 do
    begin

      nx := (j + 1) mod n;

      x0 := FGmsh.CoordX[FGmsh.ElementNode[i, j]];
      y0 := FGmsh.CoordY[FGmsh.ElementNode[i, j]];
      x1 := FGmsh.CoordX[FGmsh.ElementNode[i, nx]];
      y1 := FGmsh.CoordY[FGmsh.ElementNode[i, nx]];

      a2 := a2 + (x0 * y1 - x1 * y0);

      cx := cx + x0;
      cy := cy + y0;

    end;

    FEleArea[i] := Abs(a2) * 0.5;

    cx := cx / n;
    cy := cy / n;

    FEleCx[i] := cx;
    FEleCy[i] := cy;

    b := FGmsh.ElementPhysicalRegion[i];

    if (b < 1) or (b > NbBlocks) then
      raise Exception.Create('Element ' + IntToStr(i) + ' carries physical region ' +
        IntToStr(b) + ', which is not a voussoir - the .geo and the block table ' +
        'have got out of step.');

    FEleBlock[i] := b;

    ArcId := FBlocks[b].Arc;

    dx := cx - FArcs[ArcId].cx;
    dy := cy - FArcs[ArcId].cy;

    d := Sqrt(dx * dx + dy * dy);


    // Hoop direction: perpendicular to the radius of this element's own
    // arc, which is the direction the arch thrust runs in here.
    FEleNx[i] := -dy / d;
    FEleNy[i] := dx / d;

    FTotalArea := FTotalArea + FEleArea[i];

  end;

  FSelfWeight := Density * Abs(GravityAccel) * FTotalArea * BarrelDepth;

end;

procedure TArchModel.BuildModel;
var

  i, j, NbNodes, MaterialId : Integer;

  Node : Array[0..4] of Integer;

  EleType : NEleType;

  BestD, d, NodeForce, Window, sLoad : Double;

  IsLoaded : Array of Boolean;

begin

  FEngine := TStructuralEngine.Create;

  (******************** MATERIAL ********************)

  FRho := TExpressionList.Create;
  FRho.AddExpression(-1000, +1000, Num(Density), 'T');

  FE := TExpressionList.Create;
  FE.AddExpression(-1000, +1000, Num(ElasticModulus), 'T');

  FPoisson := TExpressionList.Create;
  FPoisson.AddExpression(-1000, +1000, Num(PoissonRatio), 'T');

  FAlpha := TExpressionList.Create;
  FAlpha.AddExpression(-1000, +1000, Num(ThermalExpansion), 'T');

  MaterialId := FEngine.AddMaterial(Constant, FRho, FE, FPoisson, FAlpha);

  // Penalty method + soGMRES, for the reasons given in uArchEx1.pas.
  FEngine.PenaltyMethod := True;
  FEngine.SolverType := soGMRES;

  (******************** MESH ********************)

  FEngine.BeginAddMesh;

  for i := 0 to FGmsh.NbNodes - 1 do
    FEngine.AddNode(FGmsh.CoordX[i], FGmsh.CoordY[i], FGmsh.CoordZ[i]);

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    NbNodes := 0;
    EleType := elNone;

    if FGmsh.ElementType[i] = GMSH_TRI then
    begin
      NbNodes := 3;
      EleType := elTri;
    end
    else if FGmsh.ElementType[i] = GMSH_QUAD then
    begin
      NbNodes := 4;
      EleType := elQuad;
    end;

    for j := 0 to NbNodes - 1 do
      Node[j] := FGmsh.ElementNode[i, j];

    FEngine.AddElement(Node, NbNodes, EleType, MaterialId, 0, 0, BarrelDepth);

  end;

  FEngine.EndAddMesh;

  (******************** RESTRAINTS ********************)

  // The haunch arcs start at angle 0 about centres on the springing
  // line, so both springing faces are horizontal at y = 0 - the same
  // situation as ArchEx1, and the same reason the end joints give a free
  // static check in ReportJoints.
  FZero := TExpressionList.Create;
  FZero.AddExpression(-1000, +1000, '0', 't');

  FEngine.BeginSetRestraints;

  FNbRestrained := 0;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    if Abs(FGmsh.CoordY[i]) < GeoTol then
    begin

      FEngine.SetNodeRestraint(i, Constant, FZero, diX);
      FEngine.SetNodeRestraint(i, Constant, FZero, diY);

      Inc(FNbRestrained);

    end;

  end;

  FEngine.EndSetRestraints;

  FEngine.SetInitialDeformation(0);

  (******************** LOADS ********************)

  FEngine.SelfWeight := True;
  FEngine.GravityValue := GravityAccel;
  FEngine.GravityDirection := diY;

  FAppliedLoad := 0;
  FNbLoadedNodes := 0;

  if FLoadCase <> LoadCaseSelfWeight then
  begin

    if FLoadCase = LoadCaseCrown then
      sLoad := CrownLoadPosition * FIntradosLength
    else
      sLoad := HaunchLoadPosition * FIntradosLength;

    if not ExtradosPointAt(sLoad, FLoadX, FLoadY) then
      raise Exception.Create('Load position falls outside the arch');

    // Spread over about one voussoir of the extrados, as ArchEx1 does.
    Window := 0.5 * FIntradosLength / NbBlocks;

    SetLength(IsLoaded, FGmsh.NbNodes);

    for i := 0 to FGmsh.NbNodes - 1 do
    begin

      // On the outer face, and within the window of the load point.
      // Both tests are needed: the window is about a third of the ring
      // depth, so proximity alone would also pick up the layer of
      // interior nodes just below the extrados.
      d := Sqrt(Sqr(FGmsh.CoordX[i] - FLoadX) + Sqr(FGmsh.CoordY[i] - FLoadY));

      IsLoaded[i] := (d <= Window) and
                     OnExtrados(FGmsh.CoordX[i], FGmsh.CoordY[i]);

      if IsLoaded[i] then
        Inc(FNbLoadedNodes);

    end;

    FAppliedLoad := LoadFraction * FSelfWeight;

    if FNbLoadedNodes > 0 then
    begin

      NodeForce := -FAppliedLoad / FNbLoadedNodes;

      FNodeLoad := TExpressionList.Create;
      FNodeLoad.AddExpression(-1000, +1000, Num(NodeForce), 't');

      for i := 0 to FGmsh.NbNodes - 1 do
        if IsLoaded[i] then
          FEngine.AddNodeSource(i, Constant, FNodeLoad, diY);

    end;

  end;

  (******************** CROWN NODE (for the deflection report) ********************)

  BestD := MaxDouble;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    d := Sqrt(Sqr(FGmsh.CoordX[i]) + Sqr(FGmsh.CoordY[i] - FApexY));

    if d < BestD then
    begin
      BestD := d;
      FCrownNode := i;
    end;

  end;

end;

procedure TArchModel.PostProcess;
var

  i : Integer;

  Stress : RStress;

  nx, ny, sxx, syy, sxy, avg, dif, rad : Double;

begin

  SetLength(FUx, FEngine.NbNodes);
  SetLength(FUy, FEngine.NbNodes);
  SetLength(FUz, FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
  begin

    FUx[i] := FEngine.Deformation[i, diX];
    FUy[i] := FEngine.Deformation[i, diY];
    FUz[i] := 0;

  end;

  SetLength(FSxx, FEngine.NbElements);
  SetLength(FSyy, FEngine.NbElements);
  SetLength(FSxy, FEngine.NbElements);
  SetLength(FS1, FEngine.NbElements);
  SetLength(FS2, FEngine.NbElements);
  SetLength(FSn, FEngine.NbElements);
  SetLength(FVonMises, FEngine.NbElements);

  for i := 0 to FEngine.NbElements - 1 do
  begin

    Stress := FEngine.Stress[i];

    sxx := Stress.Sxx;
    syy := Stress.Syy;
    sxy := Stress.Sxy;

    FSxx[i] := sxx;
    FSyy[i] := syy;
    FSxy[i] := sxy;

    avg := 0.5 * (sxx + syy);
    dif := 0.5 * (sxx - syy);
    rad := Sqrt(dif * dif + sxy * sxy);

    FS1[i] := avg + rad;
    FS2[i] := avg - rad;

    FVonMises[i] := Sqrt(Sqr(sxx) - sxx * syy + Sqr(syy) + 3 * Sqr(sxy));

    // Hoop stress: the direct stress on the radial plane through this
    // element, n'*S*n, with n the hoop direction of the element's own
    // arc. This is the arch thrust made visible.
    nx := FEleNx[i];
    ny := FEleNy[i];

    FSn[i] := sxx * nx * nx + 2 * sxy * nx * ny + syy * ny * ny;

  end;

  (******************** WRITE THE GMSH VIEWS ********************)

  FGmsh.OpenFile(PosFile);

  FGmsh.WriteViewVectorNode('Displacement', FUx, FUy, FUz, True);

  FGmsh.WriteViewScalarNode('Ux', FUx, False);
  FGmsh.WriteViewScalarNode('Uy', FUy, False);

  // Index ViewHoop - keep the constant in step if this order changes.
  FGmsh.WriteViewScalarElement('Hoop stress Sn', FSn, False);

  FGmsh.WriteViewScalarElement('S1 max principal', FS1, False);
  FGmsh.WriteViewScalarElement('S2 min principal', FS2, False);

  FGmsh.WriteViewScalarElement('Sxx', FSxx, False);
  FGmsh.WriteViewScalarElement('Syy', FSyy, False);
  FGmsh.WriteViewScalarElement('Sxy', FSxy, False);

  FGmsh.WriteViewScalarElement('VonMises', FVonMises, False);

  FGmsh.WriteViewScalarElement('Block', FEleBlock, False);

  FGmsh.Close;

end;

procedure TArchModel.ReportSummary;
var

  i : Integer;

  MaxComp, MaxTens : Double;

begin

  MaxComp := 0;
  MaxTens := 0;

  for i := 0 to FEngine.NbElements - 1 do
  begin

    if FS2[i] < MaxComp then
      MaxComp := FS2[i];

    if FS1[i] > MaxTens then
      MaxTens := FS1[i];

  end;

  WriteLn;
  WriteLn('================ ARCH SUMMARY ================');
  WriteLn(Format('  Span (intrados)          : %8.3f m', [2 * HalfSpan]));
  WriteLn(Format('  Rise                     : %8.3f m  (rise/span %.3f)',
    [FApexY, FApexY / (2 * HalfSpan)]));
  WriteLn(Format('  Ring thickness           : %8.3f m  (%d voussoirs)',
    [RingThickness, NbBlocks]));
  WriteLn(Format('  Barrel depth             : %8.3f m', [BarrelDepth]));
  WriteLn(Format('  Haunch / crown radius    : %8.3f m / %.3f m',
    [FArcs[ArcHaunchRight].r, FArcs[ArcCrownRight].r]));
  WriteLn(Format('  Intrados length          : %8.3f m', [FIntradosLength]));
  WriteLn(Format('  Ring area / self weight  : %8.3f m2 / %8.2f kN',
    [FTotalArea, FSelfWeight / 1000]));
  WriteLn(Format('  Superimposed load        : %8.2f kN  (%d extrados nodes)',
    [FAppliedLoad / 1000, FNbLoadedNodes]));
  WriteLn(Format('  Restrained nodes         : %8d  (both springings, X and Y)',
    [FNbRestrained]));
  WriteLn(Format('  Solve time               : %8.0f ms', [FElapsed]));
  WriteLn;
  WriteLn(Format('  Apex intrados settlement : %8.4f mm', [-FUy[FCrownNode] * 1000]));
  WriteLn(Format('  Peak compression         : %8.3f MPa', [MaxComp / 1e6]));
  WriteLn(Format('  Peak tension             : %8.3f MPa', [MaxTens / 1e6]));

end;

procedure TArchModel.ReportBlocks;
var

  b, i, n, nTens : Integer;

  MinS2, MaxS1, MeanSn, Area : Double;

  Kind : String;

begin

  WriteLn;
  WriteLn('================ PER-BLOCK STRESS (MPa, tension +) ================');
  WriteLn('  Block  arc      mean hoop   peak compr.   peak tens.   over mortar ft');

  for b := 1 to NbBlocks do
  begin

    n := 0;
    nTens := 0;

    MinS2 := 0;
    MaxS1 := 0;
    MeanSn := 0;
    Area := 0;

    for i := 0 to FEngine.NbElements - 1 do
    begin

      if Round(FEleBlock[i]) <> b then
        Continue;

      if n = 0 then
      begin
        MinS2 := FS2[i];
        MaxS1 := FS1[i];
      end
      else
      begin
        if FS2[i] < MinS2 then MinS2 := FS2[i];
        if FS1[i] > MaxS1 then MaxS1 := FS1[i];
      end;

      MeanSn := MeanSn + FSn[i] * FEleArea[i];
      Area := Area + FEleArea[i];

      if FS1[i] > MortarTensileStrength then
        Inc(nTens);

      Inc(n);

    end;

    if Area > 0 then
      MeanSn := MeanSn / Area;

    case FBlocks[b].Arc of
      ArcHaunchRight : Kind := 'haunch R';
      ArcCrownRight  : Kind := 'crown R ';
      ArcCrownLeft   : Kind := 'crown L ';
    else
      Kind := 'haunch L';
    end;

    Write(Format('  %5d  %s  %11.3f   %11.3f   %10.3f',
      [b, Kind, MeanSn / 1e6, MinS2 / 1e6, MaxS1 / 1e6]));

    if nTens > 0 then
      WriteLn(Format('   %d/%d elements', [nTens, n]))
    else
      WriteLn('   -');

  end;

  WriteLn('  (block 1 springs from the right; the apex joint is between blocks ',
    NbBlocks div 2, ' and ', NbBlocks div 2 + 1, ' - there is no keystone)');

end;

{ The masonry reading of the elastic result - the same thrust-line
  analysis as ArchEx1's, restated for an arch with four centres.

  At each joint the elements of the two blocks that meet there, and
  within one element layer of the joint plane, give the direct stress on
  that plane at NbAcrossRing equally deep stations through the ring. The
  thrust and the moment about mid-depth are then integrated over the
  joint directly, midpoint rule, one station per layer:

    N = t * h * mean(Sn)         M = t * h * mean(Sn * x)

  with x measured from mid-joint, intrados negative, so the thrust line
  crosses the joint at an eccentricity e = M/N = sum(Sn*x)/sum(Sn) and
  Heyman's no-tension criterion is |e| <= h/6. h is each joint's own
  depth, which is RingThickness on every radial joint but slightly more
  on the mitred apex joint, where the ring is crossed at an angle.

  Integrating rather than fitting a straight line across the ring is
  deliberate, though the two agree closely here. A line is the classical
  assumption and is what a shallow ring gives anyway, but this arch's
  haunch arcs carry a 0.6 m ring on a radius of only 1.0 m, where the
  hoop stress varies across the joint too sharply to be a line, and
  nothing about the middle-third rule needs one: the resultant's
  position is sum(Sn*x)/sum(Sn) whatever shape the stress block is.
  Every element in the band counts equally, because each stands for one
  equally deep slice of the joint; weighting by element area would
  quietly bias the result towards the extrados, where the elements are
  larger. ArchEx1 does the same, so the two reports are comparable.

  A flagged joint is where the ELASTIC thrust line has left the middle
  third: the bonded model is carrying tension no mortar joint could
  supply, and a real arch would crack and hinge there instead. That is
  cracking and redistribution, not collapse - four hinges are needed
  before the arch becomes a mechanism. }
procedure TArchModel.ReportJoints;
var

  k, i, n, nOutside, b : Integer;

  x, y, dxc, dyc, dn, nx, ny : Double;

  SumSn, SumSnX : Double;

  MinSn, MaxSn, Thrust, Moment, ecc, EndThrust, Sliver : Double;

  Status : String;

begin

  WriteLn;
  WriteLn('================ THRUST LINE AT THE JOINTS ================');
  WriteLn('  Joint  height   thrust N     e/h      Sn min      Sn max   middle third');
  WriteLn('           (m)       (kN)                (MPa)       (MPa)');

  nOutside := 0;
  EndThrust := 0;

  for k := 0 to NbBlocks do
  begin

    n := 0;
    SumSn := 0;
    SumSnX := 0;
    MinSn := 0; MaxSn := 0;

    nx := FJoints[k].nx;
    ny := FJoints[k].ny;

    for i := 0 to FEngine.NbElements - 1 do
    begin

      // Only the two blocks that actually meet at this joint. Without
      // this the joint PLANE, extended, would also sweep up elements
      // elsewhere on the ring - a plane is infinite, an arch is not.
      b := Round(FEleBlock[i]);

      if (b <> k) and (b <> k + 1) then
        Continue;

      // Element centroid in the joint's own frame.
      dxc := FEleCx[i] - FJoints[k].mx;
      dyc := FEleCy[i] - FJoints[k].my;

      dn := dxc * nx + dyc * ny;

      if Abs(dn) > FJoints[k].Band then
        Continue;

      // Position across the ring depth, intrados negative.
      x := dxc * FJoints[k].tx + dyc * FJoints[k].ty;

      // Direct stress on the joint plane.
      y := FSxx[i] * nx * nx + 2 * FSxy[i] * nx * ny + FSyy[i] * ny * ny;

      SumSn := SumSn + y;
      SumSnX := SumSnX + y * x;

      if n = 0 then
      begin
        MinSn := y;
        MaxSn := y;
      end
      else
      begin
        if y < MinSn then MinSn := y;
        if y > MaxSn then MaxSn := y;
      end;

      Inc(n);

    end;

    if n < 2 then
      Continue;

    // Midpoint-rule integration over the joint depth: every element in
    // the band stands for one equally deep slice, so the plain mean is
    // the integral divided by h.
    Thrust := BarrelDepth * FJoints[k].h * SumSn / n;
    Moment := BarrelDepth * FJoints[k].h * SumSnX / n;

    if Abs(Thrust) > 1e-9 then
      ecc := Moment / Thrust
    else
      ecc := 0;

    // The two end joints lie in the y = 0 plane, so their normal is
    // vertical and the thrust across them is the vertical reaction at
    // that springing - which is what makes the static check below
    // possible without asking the engine for reactions it does not
    // expose under the penalty method.
    if (k = 0) or (k = NbBlocks) then
      EndThrust := EndThrust + Abs(Thrust);

    if Abs(ecc) <= FJoints[k].h / 6 then
      Status := 'inside'
    else
    begin
      Status := 'OUTSIDE -> hinge';
      Inc(nOutside);
    end;

    WriteLn(Format('  %5d  %6.3f  %10.2f  %7.3f  %10.3f  %10.3f   %s',
      [k, FJoints[k].my, Thrust / 1000, ecc / FJoints[k].h,
       MinSn / 1e6, MaxSn / 1e6, Status]));

  end;

  WriteLn;

  if nOutside = 0 then
    WriteLn('  The thrust line stays within the middle third at every joint.')
  else
    WriteLn(Format('  The thrust line leaves the middle third at %d joint(s).', [nOutside]));

  WriteLn('  e/h is the thrust line''s offset from mid-ring as a fraction of the');
  WriteLn('  joint depth; |e/h| <= 0.167 is Heyman''s no-tension limit. A joint');
  WriteLn('  outside it would open on a real arch, forming a hinge there - which');
  WriteLn('  means cracking and redistribution, not collapse: four hinges are');
  WriteLn('  needed before the arch becomes a mechanism.');

  WriteLn;
  WriteLn(Format('  Static check: springing thrusts total %.2f kN against an applied',
    [EndThrust / 1000]));
  WriteLn(Format('  vertical load of %.2f kN (self weight %.2f + superimposed %.2f), %.1f%%.',
    [(FSelfWeight + FAppliedLoad) / 1000, FSelfWeight / 1000, FAppliedLoad / 1000,
     100 * (EndThrust / (FSelfWeight + FAppliedLoad) - 1)]));

  // Half an element of ring sits below the plane the band actually
  // samples, at each springing - weight the check cannot see. The rest
  // of the gap is discretisation; both halve when the mesh is halved.
  Sliver := 2 * Density * Abs(GravityAccel) * BarrelDepth * RingThickness *
            0.5 * ((FBlocks[1].Ang1 - FBlocks[1].Ang0) / NbAlongBlock) *
            (FArcs[FBlocks[1].Arc].r + RingThickness / 2);

  WriteLn(Format('  A check on the solve, not an identity: the band is sampled half an',
    []));
  WriteLn(Format('  element above the springing face, missing %.1f%% of the ring''s own',
    [100 * Sliver / (FSelfWeight + FAppliedLoad)]));
  WriteLn('  weight, and element stresses are centre values. Both shrink with the mesh.');

end;

procedure TArchModel.WriteScript(const FileName : String);
var

  F : TextFile;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, '// Generated by ArchEx2 - do not edit, it is rewritten on every run.');
    WriteLn(F);
    WriteLn(F, 'Include "archex2.pos";');
    WriteLn(F);
    WriteLn(F, '// Show only the displacement vector view while it animates.');
    WriteLn(F, 'For i In {0:PostProcessing.NbViews-1}');
    WriteLn(F, '  View[i].Visible = 0;');
    WriteLn(F, 'EndFor');
    WriteLn(F);
    WriteLn(F, Format('View[%d].Visible = 1;', [ViewDisplacement]));
    WriteLn(F, Format('View[%d].VectorType = 5;   // gmsh displacement mode',
      [ViewDisplacement]));
    WriteLn(F);
    WriteLn(F, '// Scale the animation to the solution: an arch of this stiffness');
    WriteLn(F, '// settles by a few hundredths of a millimetre, far below one pixel');
    WriteLn(F, '// at any fixed factor.');
    WriteLn(F, 'PeakFraction = 0.05;');
    WriteLn(F, Format('ModelLength = View[%d].MaxX - View[%d].MinX;',
      [ViewDisplacement, ViewDisplacement]));
    WriteLn(F, Format('UMax = View[%d].Max;', [ViewDisplacement]));
    WriteLn(F);
    WriteLn(F, 'If (UMax > 0)');
    WriteLn(F, '  PeakFactor = PeakFraction * ModelLength / UMax;');
    WriteLn(F, 'Else');
    WriteLn(F, '  PeakFactor = 0;');
    WriteLn(F, 'EndIf');
    WriteLn(F);
    WriteLn(F, 'NSteps = 40;');
    WriteLn(F);
    WriteLn(F, 'For i In {1:NSteps}');
    WriteLn(F, Format('  View[%d].DisplacementFactor = PeakFactor * i / NSteps;',
      [ViewDisplacement]));
    WriteLn(F, '  Draw;');
    WriteLn(F, 'EndFor');
    WriteLn(F);
    WriteLn(F, 'For i In {NSteps:1:-1}');
    WriteLn(F, Format('  View[%d].DisplacementFactor = PeakFactor * i / NSteps;',
      [ViewDisplacement]));
    WriteLn(F, '  Draw;');
    WriteLn(F, 'EndFor');
    WriteLn(F);
    WriteLn(F, '// Settle on the hoop stress: the arch thrust itself, negative');
    WriteLn(F, '// (compressive) everywhere a masonry arch is working properly.');
    WriteLn(F, Format('View[%d].Visible = 0;', [ViewDisplacement]));
    WriteLn(F, Format('View[%d].Visible = 1;', [ViewHoop]));
    WriteLn(F, 'Draw;');
    WriteLn(F);
    WriteLn(F, '// The other views (Ux, Uy, S1, S2, Sxx, Syy, Sxy, VonMises,');
    WriteLn(F, '// Block) are all loaded - tick them in the Post-processing tree.');

  finally

    CloseFile(F);

  end;

end;

procedure TArchModel.Run(ViewResults : Boolean);
var

  ExitCode : Cardinal;

  Start : QWord;

begin

  WriteLn('ArchEx2 - Perpendicular (four-centred) masonry arch, load case ', FLoadCase);
  WriteLn;

  WriteGeoFile(GeoFile);

  BuildMesh;

  CalcElementGeometry;

  BuildModel;

  FEngine.SetEndPostIterationFunction(PostProcess);

  WriteLn('Solving ', FEngine.NbNodes * 2, ' degrees of freedom...');

  Start := GetTickCount64;

  FEngine.CalcDeformation(caStatic, False);

  FElapsed := GetTickCount64 - Start;

  ReportSummary;
  ReportBlocks;
  ReportJoints;

  WriteLn;
  WriteLn('Results written to ', PosFile);

  WriteScript(ScrFile);

  if ViewResults then
    Sto_ShellExecute(GmshExecutable, [ScrFile], ExitCode);

end;

initialization

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DotFS.ThousandSeparator := #0;

end.
