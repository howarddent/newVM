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

  The ring is divided into 15 voussoirs: 3 on each haunch arc, 4 on each
  crown arc, and a keystone straddling the apex - so, as in ArchEx1, the
  block count is odd and the middle block is a keystone. That keystone is
  the one voussoir that does not belong to a single arc: half of it is
  struck from each crown centre, meeting on the mitred joint up the
  vertical centreline. It is therefore meshed as two gmsh surfaces
  sharing one physical region, which is what makes it a single block
  everywhere downstream - in the 'Block' view, in the per-block report,
  and in the joint list, where the apex is not a joint at all. Sizing the
  crown blocks at (NbCrownBlocks + 1/2) to the crown sweep leaves every
  voussoir within a few percent of the same length (0.349 m on the
  haunches against 0.354 m on the crown).

  Everything downstream of the geometry - the bonded conformal mesh, the
  plane-stress solve, the caveat that masonry carries no tension, and the
  thrust-line-against-the-middle-third report - is as described in
  uArchEx1.pas's own header. Two pieces of machinery did have to be
  generalised, because a four-centred arch has no single centre to
  measure from:

    - each voussoir carries its own arc centre, so the hoop direction is
      taken from the block's own arc rather than from the origin (and for
      the keystone, from whichever half of it the element sits in);
    - joints are found by distance from the joint PLANE, restricted to
      the two blocks that meet there, rather than by angle about a common
      centre. }

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

  // Voussoirs per half arch, either side of the keystone: 3 on the
  // haunch arc and 4 on the crown arc.
  NbHaunchBlocks = 3;
  NbCrownBlocks = 4;

  // 15 - odd, with the keystone in the middle.
  NbBlocks = 2 * (NbHaunchBlocks + NbCrownBlocks) + 1;

  KeystoneBlock = NbHaunchBlocks + NbCrownBlocks + 1;

  // 16 meshed segments, because the keystone is two of them - one per
  // crown arc - sharing the keystone's physical region.
  NbSegments = 2 * (NbHaunchBlocks + NbCrownBlocks + 1);

  // The segment boundary at the apex: the mitre inside the keystone,
  // which is a geometric edge but not a joint between blocks.
  ApexBoundary = NbHaunchBlocks + NbCrownBlocks + 1;

  // Structured mesh per voussoir, as ArchEx1: NbAcrossRing quads through
  // the ring by NbAlongBlock along the arc. Each half of the keystone is
  // half a voussoir long, so it gets half the divisions, rounded up.
  NbAcrossRing = 6;
  NbAlongBlock = 5;
  NbAlongHalfKeystone = (NbAlongBlock + 1) div 2;

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
  // intrados length measured from the right springing. 0.50 is the apex,
  // and so the middle of the keystone - the same station ArchEx1's crown
  // load lands on. 0.75 is the quarter point of the arch's length
  // measured from the LEFT springing, again as ArchEx1 (whose 135
  // degrees is 45 degrees of a 180 degree arc from that springing).
  CrownLoadPosition = 0.50;
  HaunchLoadPosition = 0.75;

  (******************** POST-PROCESSING ********************)

  ViewDisplacement = 0;
  ViewHoop = 3;

  // The three line views AppendLineViews adds after the ten field views.
  // 'Applied load' only exists when there is one, so it comes last.
  ViewThrustLine = 11;
  ViewMiddleThird = 12;
  ViewLoad = 13;

type

  // One of the four circular arcs the ring is struck from.
  RArc = record

    cx, cy : Double;   // centre
    r : Double;        // intrados radius

  end;

  // One meshed slice of one arc, between two boundaries. Every voussoir
  // is one segment except the keystone, which is two.
  RSegment = record

    Arc : Integer;
    Block : Integer;
    Ang0, Ang1 : Double;   // angles about the arc centre, radians
    Divisions : Integer;   // elements along the arch
    EleLen : Double;       // along-arch length of one element

  end;

  // A boundary between segments: a radial joint, the mitre at the apex,
  // or a springing face. Stored as the plane it lies in, since that is
  // what the thrust-line integration needs and it is the one description
  // that covers all three kinds.
  RBoundary = record

    x0, y0 : Double;   // intrados end
    x1, y1 : Double;   // extrados end
    mx, my : Double;   // mid-point
    tx, ty : Double;   // unit vector, intrados -> extrados
    nx, ny : Double;   // unit normal to the plane (along the arch)
    h : Double;        // depth, |P1 - P0|


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
    FSegments : Array[1..NbSegments] of RSegment;
    FBounds : Array[0..NbSegments] of RBoundary;

    FApexY, FApexYExt : Double;
    FIntradosLength : Double;

    FTotalArea : Double;
    FSelfWeight : Double;
    FAppliedLoad : Double;
    FNbLoadedNodes : Integer;
    FLoadX, FLoadY : Double;

    FElapsed : Double;

    // Per joint, filled by CalcThrustLine.
    FJThrust, FJEcc, FJMinSn, FJMaxSn : TDoubleArray;
    FJPx, FJPy : TDoubleArray;
    FJValid : Array of Boolean;

    FEleBlock : TDoubleArray;
    FEleArea : TDoubleArray;
    FEleCx, FEleCy : TDoubleArray;   // centroid per element
    FEleLen : TDoubleArray;          // along-arch extent per element
    FEleNx, FEleNy : TDoubleArray;   // unit hoop direction per element
    FSxx, FSyy, FSxy : TDoubleArray;
    FS1, FS2, FSn, FVonMises : TDoubleArray;

    FUx, FUy, FUz : TDoubleArray;

    FCrownNode : Integer;
    FNbRestrained : Integer;

    procedure SetupGeometry;
    function ExtradosPointAt(s : Double; var px, py : Double) : Boolean;
    function OnExtrados(x, y : Double) : Boolean;
    function ArcOfElement(BlockId : Integer; cx : Double) : Integer;
    function BlockKind(BlockId : Integer) : String;

    procedure WriteGeoFile(const FileName : String);
    procedure BuildMesh;
    procedure CalcElementGeometry;
    procedure BuildModel;

    procedure CalcThrustLine;
    procedure AppendLineViews(const FileName : String);

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

// Joint j sits at this segment boundary. The two differ because the
// boundary at the apex is inside the keystone, not between two blocks,
// so every joint above it is one boundary further along.
function JointBoundary(j : Integer) : Integer;

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

function JointBoundary(j : Integer) : Integer;
begin

  if j < ApexBoundary then
    Result := j
  else
    Result := j + 1;

end;

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

{ As SafeReWriteText, but opening an existing file to add to the end of
  it - AppendLineViews puts its views after the ones TGmsh has just
  written and closed. }
procedure SafeAppendText(var F : TextFile);
const
  MaxAttempts = 8;
  RetryDelayMs = 50;
var
  Attempt : Integer;
begin

  for Attempt := 1 to MaxAttempts do
  begin
    try
      Append(F);
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

{ Which arc an element belongs to. Every block but the keystone sits on
  one arc; the keystone straddles both crown arcs, and which half an
  element is in is decided by the side of the centreline it sits on -
  the mitre it is divided on being the centreline itself. }
function TArchModel.ArcOfElement(BlockId : Integer; cx : Double) : Integer;
var

  s : Integer;

begin

  if BlockId = KeystoneBlock then
  begin

    if cx >= 0 then
      Result := ArcCrownRight
    else
      Result := ArcCrownLeft;

    Exit;

  end;

  Result := ArcHaunchRight;

  for s := 1 to NbSegments do
    if FSegments[s].Block = BlockId then
      Exit(FSegments[s].Arc);

end;

function TArchModel.BlockKind(BlockId : Integer) : String;
begin

  if BlockId = KeystoneBlock then
    Result := 'keystone'
  else if BlockId <= NbHaunchBlocks then
    Result := 'haunch R'
  else if BlockId < KeystoneBlock then
    Result := 'crown R '
  else if BlockId <= KeystoneBlock + NbCrownBlocks then
    Result := 'crown L '
  else
    Result := 'haunch L';

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

  which puts it below the springing line and, for a large enough r2, on
  the far side of the centreline. The apex is then where that arc
  crosses x = 0:

    apexY = B.y + sqrt(r2^2 - B.x^2)

  and because B.x is not zero the tangent there is not horizontal, so
  the two halves meet at a point. The left half is the mirror image, and
  the whole ring is traversed as a single monotonic sweep: 0 -> phi
  about A, phi -> apex about B, then the mirror of that back down to
  180 degrees about the left haunch centre.

  The crown sweep is divided into NbCrownBlocks whole voussoirs plus the
  half keystone that reaches the apex - hence the division by
  (NbCrownBlocks + 0.5), which is what keeps the keystone the same size
  as its neighbours instead of half their size.
********************************************************************)
procedure TArchModel.SetupGeometry;
var

  b, s, ArcId : Integer;

  phi, r1, r2, t, AngJunction, AngApex, aCrown, dAng, ang : Double;



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

  aCrown := (AngApex - AngJunction) / (NbCrownBlocks + 0.5);

  (******************** SEGMENTS ********************)

  // Right haunch: segments 1..NbHaunchBlocks, 0 -> phi about A.
  dAng := phi / NbHaunchBlocks;

  for b := 1 to NbHaunchBlocks do
  begin
    FSegments[b].Arc := ArcHaunchRight;
    FSegments[b].Block := b;
    FSegments[b].Ang0 := (b - 1) * dAng;
    FSegments[b].Ang1 := b * dAng;
    FSegments[b].Divisions := NbAlongBlock;
  end;

  // Right crown: junction -> half a voussoir short of the apex.
  for b := 1 to NbCrownBlocks do
  begin
    s := NbHaunchBlocks + b;
    FSegments[s].Arc := ArcCrownRight;
    FSegments[s].Block := s;
    FSegments[s].Ang0 := AngJunction + (b - 1) * aCrown;
    FSegments[s].Ang1 := AngJunction + b * aCrown;
    FSegments[s].Divisions := NbAlongBlock;
  end;

  // Keystone, right half: up to the apex.
  s := ApexBoundary;
  FSegments[s].Arc := ArcCrownRight;
  FSegments[s].Block := KeystoneBlock;
  FSegments[s].Ang0 := AngApex - 0.5 * aCrown;
  FSegments[s].Ang1 := AngApex;
  FSegments[s].Divisions := NbAlongHalfKeystone;

  // Keystone, left half: away from the apex, mirrored.
  s := ApexBoundary + 1;
  FSegments[s].Arc := ArcCrownLeft;
  FSegments[s].Block := KeystoneBlock;
  FSegments[s].Ang0 := Pi - AngApex;
  FSegments[s].Ang1 := Pi - AngApex + 0.5 * aCrown;
  FSegments[s].Divisions := NbAlongHalfKeystone;

  // Left crown: on to the junction.
  for b := 1 to NbCrownBlocks do
  begin
    s := ApexBoundary + 1 + b;
    FSegments[s].Arc := ArcCrownLeft;
    FSegments[s].Block := s - 1;
    FSegments[s].Ang0 := Pi - AngApex + (b - 0.5) * aCrown;
    FSegments[s].Ang1 := Pi - AngApex + (b + 0.5) * aCrown;
    FSegments[s].Divisions := NbAlongBlock;
  end;

  // Left haunch: (Pi - phi) -> Pi about the left haunch centre.
  dAng := phi / NbHaunchBlocks;

  for b := 1 to NbHaunchBlocks do
  begin
    s := ApexBoundary + 1 + NbCrownBlocks + b;
    FSegments[s].Arc := ArcHaunchLeft;
    FSegments[s].Block := s - 1;
    FSegments[s].Ang0 := Pi - phi + (b - 1) * dAng;
    FSegments[s].Ang1 := Pi - phi + b * dAng;
    FSegments[s].Divisions := NbAlongBlock;
  end;

  FIntradosLength := 0;

  for s := 1 to NbSegments do
  begin

    ArcId := FSegments[s].Arc;

    FSegments[s].EleLen := FArcs[ArcId].r *
      Abs(FSegments[s].Ang1 - FSegments[s].Ang0) / FSegments[s].Divisions;

    FIntradosLength := FIntradosLength +
      FArcs[ArcId].r * Abs(FSegments[s].Ang1 - FSegments[s].Ang0);

  end;

  (******************** BOUNDARIES ********************)

  // Boundary b is the start of segment b+1 and the end of segment b.
  // All are radial to the arc they belong to except the one at the
  // apex, which is the mitre inside the keystone: the bisector of the
  // two crown arcs' radial directions there, and so vertical by
  // symmetry.
  for b := 0 to NbSegments do
  begin

    if b = ApexBoundary then
    begin

      FBounds[b].x0 := 0;
      FBounds[b].y0 := FApexY;
      FBounds[b].x1 := 0;
      FBounds[b].y1 := FApexYExt;

    end
    else
    begin

      if b < NbSegments then
      begin
        s := b + 1;
        ang := FSegments[s].Ang0;
      end
      else
      begin
        s := NbSegments;
        ang := FSegments[s].Ang1;
      end;

      ArcId := FSegments[s].Arc;

      FBounds[b].x0 := FArcs[ArcId].cx + FArcs[ArcId].r * Cos(ang);
      FBounds[b].y0 := FArcs[ArcId].cy + FArcs[ArcId].r * Sin(ang);

      FBounds[b].x1 := FArcs[ArcId].cx + (FArcs[ArcId].r + RingThickness) * Cos(ang);
      FBounds[b].y1 := FArcs[ArcId].cy + (FArcs[ArcId].r + RingThickness) * Sin(ang);

    end;

    FBounds[b].mx := 0.5 * (FBounds[b].x0 + FBounds[b].x1);
    FBounds[b].my := 0.5 * (FBounds[b].y0 + FBounds[b].y1);

    FBounds[b].h := Sqrt(Sqr(FBounds[b].x1 - FBounds[b].x0) +
                         Sqr(FBounds[b].y1 - FBounds[b].y0));

    FBounds[b].tx := (FBounds[b].x1 - FBounds[b].x0) / FBounds[b].h;
    FBounds[b].ty := (FBounds[b].y1 - FBounds[b].y0) / FBounds[b].h;

    // Normal to the plane, i.e. along the arch.
    FBounds[b].nx := FBounds[b].ty;
    FBounds[b].ny := -FBounds[b].tx;

  end;

end;

{ The extrados point radially outside the intrados point a distance s
  along the intrados from the right springing - i.e. indexed by intrados
  arc length, not by its own. That keeps a load position quoted as a
  fraction of the arch's length meaning the same thing on either face. }
function TArchModel.ExtradosPointAt(s : Double; var px, py : Double) : Boolean;
var

  seg, ArcId : Integer;

  Len, ang : Double;

begin

  Result := False;

  if (s < 0) or (s > FIntradosLength) then
    Exit;

  for seg := 1 to NbSegments do
  begin

    ArcId := FSegments[seg].Arc;

    Len := FArcs[ArcId].r * Abs(FSegments[seg].Ang1 - FSegments[seg].Ang0);

    if (s <= Len) or (seg = NbSegments) then
    begin

      ang := FSegments[seg].Ang0 +
             (FSegments[seg].Ang1 - FSegments[seg].Ang0) * (s / Len);

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
  Geometry file, one gmsh plane surface per segment - so one per
  voussoir, except the keystone, whose two halves are two surfaces
  sharing its physical region.

    point   1+a             centre of arc a               (a = 0..3)
    point   10+b            intrados point at boundary b  (b = 0..S)
    point   10+(S+1)+b      extrados point at boundary b
    line    10+b            boundary b, intrados -> extrados
    line    10+(S+1)+(s-1)  intrados arc of segment s     (s = 1..S)
    line    10+(S+1)+S+(s-1)  extrados arc of segment s
    loop    200+s, surface 500+s
    physical surface k       the segments of block k

  Adjacent segments share the boundary line, so the mesh is conformal
  across every joint, and across the keystone's own internal mitre.
********************************************************************)
procedure TArchModel.WriteGeoFile(const FileName : String);

  function LBound(i : Integer) : Integer;
  begin
    Result := 10 + i;
  end;

  function LArcIn(s : Integer) : Integer;
  begin
    Result := 10 + (NbSegments + 1) + (s - 1);
  end;

  function LArcOut(s : Integer) : Integer;
  begin
    Result := 10 + (NbSegments + 1) + NbSegments + (s - 1);
  end;

var

  F : TextFile;

  b, s, a, ArcId : Integer;

  Bounds, ArcsFull, ArcsHalf, Surfaces : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, 'Mesh.MshFileVersion=1;');

    WriteLn(F, 'cl = ' + Num(RingThickness / NbAcrossRing) + ';');

    for a := 0 to 3 do
      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [1 + a, Num(FArcs[a].cx), Num(FArcs[a].cy)]));

    for b := 0 to NbSegments do
    begin

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + b, Num(FBounds[b].x0), Num(FBounds[b].y0)]));

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + (NbSegments + 1) + b, Num(FBounds[b].x1), Num(FBounds[b].y1)]));

    end;

    Bounds := '';

    for b := 0 to NbSegments do
    begin

      WriteLn(F, Format('Line(%d) = {%d,%d};',
        [LBound(b), 10 + b, 10 + (NbSegments + 1) + b]));

      if b > 0 then
        Bounds := Bounds + ',';

      Bounds := Bounds + IntToStr(LBound(b));

    end;

    ArcsFull := '';
    ArcsHalf := '';

    for s := 1 to NbSegments do
    begin

      ArcId := FSegments[s].Arc;

      // Circle(id) = {start, centre, end}. No arc here exceeds 20
      // degrees, well under gmsh's half-turn limit on one Circle.
      WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
        [LArcIn(s), 10 + (s - 1), 1 + ArcId, 10 + s]));

      WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
        [LArcOut(s), 10 + (NbSegments + 1) + (s - 1), 1 + ArcId,
         10 + (NbSegments + 1) + s]));

      // Two division counts are in play - a whole voussoir's and a
      // keystone half's - so the arcs are transfinited in two groups.
      if FSegments[s].Divisions = NbAlongBlock then
      begin
        if ArcsFull <> '' then
          ArcsFull := ArcsFull + ',';
        ArcsFull := ArcsFull + IntToStr(LArcIn(s)) + ',' + IntToStr(LArcOut(s));
      end
      else
      begin
        if ArcsHalf <> '' then
          ArcsHalf := ArcsHalf + ',';
        ArcsHalf := ArcsHalf + IntToStr(LArcIn(s)) + ',' + IntToStr(LArcOut(s));
      end;

    end;

    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Bounds, NbAcrossRing + 1]));
    WriteLn(F, Format('Transfinite Line {%s} = %d;', [ArcsFull, NbAlongBlock + 1]));
    WriteLn(F, Format('Transfinite Line {%s} = %d;', [ArcsHalf, NbAlongHalfKeystone + 1]));

    for s := 1 to NbSegments do
    begin

      WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
        [200 + s, LBound(s - 1), LArcOut(s), LBound(s), LArcIn(s)]));

      WriteLn(F, Format('Plane Surface(%d) = {%d};', [500 + s, 200 + s]));

      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [500 + s, 10 + (s - 1), 10 + (NbSegments + 1) + (s - 1),
         10 + (NbSegments + 1) + s, 10 + s]));

      WriteLn(F, Format('Recombine Surface {%d};', [500 + s]));

    end;

    // One physical surface per voussoir. The keystone's two halves go
    // into one physical surface, which is what makes them a single
    // block everywhere the physical region is read back.
    for b := 1 to NbBlocks do
    begin

      Surfaces := '';

      for s := 1 to NbSegments do
        if FSegments[s].Block = b then
        begin
          if Surfaces <> '' then
            Surfaces := Surfaces + ',';
          Surfaces := Surfaces + IntToStr(500 + s);
        end;

      WriteLn(F, Format('Physical Surface(%d) = {%s};', [b, Surfaces]));

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
  SetLength(FEleLen, FGmsh.NbElements);
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

    // How far this element reaches along the arch. Every element spans
    // exactly one of the NbAcrossRing radial layers, so its area over
    // that depth is its mean along-arch extent - which is what the joint
    // band in CalcThrustLine measures against. On the haunch arcs here,
    // a 0.6 m ring on a 1.0 m radius, the outer elements are 1.6 times
    // the inner ones.
    FEleLen[i] := FEleArea[i] / (RingThickness / NbAcrossRing);

    b := FGmsh.ElementPhysicalRegion[i];

    if (b < 1) or (b > NbBlocks) then
      raise Exception.Create('Element ' + IntToStr(i) + ' carries physical region ' +
        IntToStr(b) + ', which is not a voussoir - the .geo and the segment table ' +
        'have got out of step.');

    FEleBlock[i] := b;

    ArcId := ArcOfElement(b, cx);

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

  // The thrust line and the middle third are not fields over the mesh,
  // so TGmsh has no method that writes them - they go straight into the
  // .pos as line views of their own once it has closed the file.
  CalcThrustLine;

  AppendLineViews(PosFile);

end;

{ Where the thrust line crosses each joint, which is what ReportJoints
  tabulates and what the 'Thrust line' view draws. See ReportJoints' own
  comment for what the numbers mean; this routine only produces them.

  There are NbBlocks+1 joints for NbSegments+1 boundaries, the odd one
  out being the mitre inside the keystone - JointBoundary maps between
  the two. The elements within one layer of a joint, and belonging to
  one of the two blocks that meet there, give the direct stress on the
  joint plane at NbAcrossRing equally deep stations, which integrate
  directly to the thrust, the moment about mid-depth, and hence to the
  eccentricity e = M/N. }
procedure TArchModel.CalcThrustLine;
var

  j, k, i, n, b : Integer;

  x, y, dxc, dyc, dn, nx, ny : Double;

  SumSn, SumSnX, Thrust, Moment, ecc : Double;

begin

  SetLength(FJThrust, NbBlocks + 1);
  SetLength(FJEcc, NbBlocks + 1);
  SetLength(FJMinSn, NbBlocks + 1);
  SetLength(FJMaxSn, NbBlocks + 1);
  SetLength(FJPx, NbBlocks + 1);
  SetLength(FJPy, NbBlocks + 1);
  SetLength(FJValid, NbBlocks + 1);

  for j := 0 to NbBlocks do
  begin

    k := JointBoundary(j);

    FJValid[j] := False;

    n := 0;
    SumSn := 0;
    SumSnX := 0;

    nx := FBounds[k].nx;
    ny := FBounds[k].ny;

    for i := 0 to FEngine.NbElements - 1 do
    begin

      // Only the two blocks that actually meet at this joint. Without
      // this the joint PLANE, extended, would also sweep up elements
      // elsewhere on the ring - a plane is infinite, an arch is not.
      b := Round(FEleBlock[i]);

      if (b <> j) and (b <> j + 1) then
        Continue;

      // Element centroid in the joint's own frame.
      dxc := FEleCx[i] - FBounds[k].mx;
      dyc := FEleCy[i] - FBounds[k].my;

      dn := dxc * nx + dyc * ny;

      // The first element layer either side of the joint and no
      // further. The test is against each element's OWN along-arch
      // extent rather than one band width for the whole joint, because
      // a voussoir's outer elements are longer than its inner ones:
      // layer centroids sit at 0.5, 1.5, ... of their own element's
      // length from the joint, so a band taken from the intrados only
      // keeps the outer layer while the taper stays under 1.8:1. This
      // arch's haunches taper 1.6:1 and so were inside that by a thin
      // margin - ArchEx3's cusped springings, at nearly 3:1, were not,
      // which is where this form was arrived at.
      if Abs(dn) > 0.9 * FEleLen[i] then
        Continue;

      // Position across the ring depth, intrados negative.
      x := dxc * FBounds[k].tx + dyc * FBounds[k].ty;

      // Direct stress on the joint plane.
      y := FSxx[i] * nx * nx + 2 * FSxy[i] * nx * ny + FSyy[i] * ny * ny;

      SumSn := SumSn + y;
      SumSnX := SumSnX + y * x;

      if n = 0 then
      begin
        FJMinSn[j] := y;
        FJMaxSn[j] := y;
      end
      else
      begin
        if y < FJMinSn[j] then FJMinSn[j] := y;
        if y > FJMaxSn[j] then FJMaxSn[j] := y;
      end;

      Inc(n);

    end;

    if n < 2 then
      Continue;

    // Midpoint-rule integration over the joint depth: every element in
    // the band stands for one equally deep slice, so the plain mean is
    // the integral divided by h.
    Thrust := BarrelDepth * FBounds[k].h * SumSn / n;
    Moment := BarrelDepth * FBounds[k].h * SumSnX / n;

    if Abs(Thrust) > 1e-9 then
      ecc := Moment / Thrust
    else
      ecc := 0;

    FJThrust[j] := Thrust;
    FJEcc[j] := ecc;

    FJPx[j] := FBounds[k].mx + ecc * FBounds[k].tx;
    FJPy[j] := FBounds[k].my + ecc * FBounds[k].ty;

    FJValid[j] := True;

  end;

end;

{ Adds the line views to the .pos: the thrust line itself, the two
  middle-third boundaries it has to stay between, and - when there is
  one - an arrow at the superimposed load. Together these turn the .pos
  into the diagram a masonry engineer would actually draw, rather than
  just a stress plot.

  Written by hand rather than through TGmsh, because none of it is a
  field over the mesh: the parsed .pos format takes bare line elements
  (SL) and vector points (VP) at arbitrary coordinates, which is exactly
  what a thrust line is.

  The middle third is drawn boundary by boundary rather than joint by
  joint, so that it follows the ring through the apex rather than
  cutting the corner across the keystone. }
procedure TArchModel.AppendLineViews(const FileName : String);
var

  F : TextFile;

  j, k : Integer;

  ax, ay, bx, by : Double;

  procedure Segment(x0, y0, x1, y1, v : Double);
  begin
    WriteLn(F, Format('SL(%e,%e,0,%e,%e,0){%e,%e};',
      [x0, y0, x1, y1, v, v], DotFS));
  end;

begin

  AssignFile(F, FileName);

  SafeAppendText(F);

  try

    (******************** THRUST LINE ********************)

    WriteLn(F, 'View "Thrust line" {');

    for j := 0 to NbBlocks - 1 do
      if FJValid[j] and FJValid[j + 1] then
        Segment(FJPx[j], FJPy[j], FJPx[j + 1], FJPy[j + 1],
                Abs(FJThrust[j]) / 1000);

    WriteLn(F, '};');

    (******************** MIDDLE THIRD ********************)

    // The band the thrust line must stay inside for the joints to be in
    // compression over their whole depth: mid-ring plus and minus h/6.
    WriteLn(F, 'View "Middle third" {');

    for k := 0 to NbSegments - 1 do
    begin

      ax := FBounds[k].mx - FBounds[k].tx * FBounds[k].h / 6;
      ay := FBounds[k].my - FBounds[k].ty * FBounds[k].h / 6;

      bx := FBounds[k + 1].mx - FBounds[k + 1].tx * FBounds[k + 1].h / 6;
      by := FBounds[k + 1].my - FBounds[k + 1].ty * FBounds[k + 1].h / 6;

      Segment(ax, ay, bx, by, 0);

      ax := FBounds[k].mx + FBounds[k].tx * FBounds[k].h / 6;
      ay := FBounds[k].my + FBounds[k].ty * FBounds[k].h / 6;

      bx := FBounds[k + 1].mx + FBounds[k + 1].tx * FBounds[k + 1].h / 6;
      by := FBounds[k + 1].my + FBounds[k + 1].ty * FBounds[k + 1].h / 6;

      Segment(ax, ay, bx, by, 0);

    end;

    WriteLn(F, '};');

    (******************** APPLIED LOAD ********************)

    if FAppliedLoad > 0 then
    begin

      WriteLn(F, 'View "Applied load" {');

      WriteLn(F, Format('VP(%e,%e,0){0,%e,0};',
        [FLoadX, FLoadY, -FAppliedLoad / 1000], DotFS));

      WriteLn(F, '};');

    end;

  finally

    CloseFile(F);

  end;

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

    Write(Format('  %5d  %s  %11.3f   %11.3f   %10.3f',
      [b, BlockKind(b), MeanSn / 1e6, MinS2 / 1e6, MaxS1 / 1e6]));

    if nTens > 0 then
      WriteLn(Format('   %d/%d elements', [nTens, n]))
    else
      WriteLn('   -');

  end;

  WriteLn('  (block 1 springs from the right; block ', KeystoneBlock,
    ' is the keystone, straddling the apex)');

end;

{ The masonry reading of the elastic result - the same thrust-line
  analysis as ArchEx1's, restated for an arch with four centres. See
  CalcThrustLine for how the numbers are arrived at.

  The thrust line crosses each joint at an eccentricity e = M/N from
  mid-depth, and Heyman's no-tension criterion is |e| <= h/6. h is each
  joint's own depth, which is RingThickness on every one of them here -
  the mitre where the ring is crossed at an angle is inside the
  keystone, and so not a joint.

  A flagged joint is where the ELASTIC thrust line has left the middle
  third: the bonded model is carrying tension no mortar joint could
  supply, and a real arch would crack and hinge there instead. That is
  cracking and redistribution, not collapse - four hinges are needed
  before the arch becomes a mechanism. }
procedure TArchModel.ReportJoints;
var

  j, nOutside : Integer;

  EndThrust, Sliver : Double;

  Status : String;

begin

  WriteLn;
  WriteLn('================ THRUST LINE AT THE JOINTS ================');
  WriteLn('  Joint  height   thrust N     e/h      Sn min      Sn max   middle third');
  WriteLn('           (m)       (kN)                (MPa)       (MPa)');

  nOutside := 0;
  EndThrust := 0;

  for j := 0 to NbBlocks do
  begin

    if not FJValid[j] then
      Continue;

    // The two end joints lie in the y = 0 plane, so their normal is
    // vertical and the thrust across them is the vertical reaction at
    // that springing - which is what makes the static check below
    // possible without asking the engine for reactions it does not
    // expose under the penalty method.
    if (j = 0) or (j = NbBlocks) then
      EndThrust := EndThrust + Abs(FJThrust[j]);

    if Abs(FJEcc[j]) <= FBounds[JointBoundary(j)].h / 6 then
      Status := 'inside'
    else
    begin
      Status := 'OUTSIDE -> hinge';
      Inc(nOutside);
    end;

    WriteLn(Format('  %5d  %6.3f  %10.2f  %7.3f  %10.3f  %10.3f   %s',
      [j, FBounds[JointBoundary(j)].my, FJThrust[j] / 1000,
       FJEcc[j] / FBounds[JointBoundary(j)].h,
       FJMinSn[j] / 1e6, FJMaxSn[j] / 1e6, Status]));

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
            0.5 * ((FSegments[1].Ang1 - FSegments[1].Ang0) / NbAlongBlock) *
            (FArcs[FSegments[1].Arc].r + RingThickness / 2);

  WriteLn('  A check on the solve, not an identity: the band is sampled half an');
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
    WriteLn(F, '// Settle on the masonry diagram: the hoop stress - the arch thrust');
    WriteLn(F, '// itself, negative (compressive) everywhere the arch is working');
    WriteLn(F, '// properly - with the thrust line drawn over it between the two');
    WriteLn(F, '// middle-third boundaries it has to stay inside.');
    WriteLn(F, Format('View[%d].Visible = 0;', [ViewDisplacement]));
    WriteLn(F, Format('View[%d].Visible = 1;', [ViewHoop]));
    WriteLn(F);
    WriteLn(F, Format('View[%d].Visible = 1;', [ViewThrustLine]));
    WriteLn(F, Format('View[%d].LineWidth = 4;', [ViewThrustLine]));
    WriteLn(F, Format('View[%d].ShowScale = 0;', [ViewThrustLine]));
    WriteLn(F, Format('View[%d].ColormapNumber = 9;   // grayscale, so it reads',
      [ViewThrustLine]));
    WriteLn(F, '                              // against the stress colours');
    WriteLn(F);
    WriteLn(F, Format('View[%d].Visible = 1;', [ViewMiddleThird]));
    WriteLn(F, Format('View[%d].LineWidth = 1;', [ViewMiddleThird]));
    WriteLn(F, Format('View[%d].ShowScale = 0;', [ViewMiddleThird]));

    if FAppliedLoad > 0 then
    begin
      WriteLn(F);
      WriteLn(F, '// The superimposed load, as an arrow at the point it acts.');
      WriteLn(F, Format('View[%d].Visible = 1;', [ViewLoad]));
      WriteLn(F, Format('View[%d].ShowScale = 0;', [ViewLoad]));
      WriteLn(F, Format('View[%d].ArrowSizeMax = 80;', [ViewLoad]));
    end;

    WriteLn(F);
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
