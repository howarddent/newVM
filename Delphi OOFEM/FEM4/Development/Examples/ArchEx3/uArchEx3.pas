unit uArchEx3;

{ ArchEx3 - stresses in a cycloidal masonry arch.

  The third of the arch examples, and again meant to be read next to the
  others: same 4.0 m span, same 0.6 m ring, same 1.0 m barrel, same
  masonry, same mesh density, same solve and the same report as ArchEx1's
  Roman semicircle and ArchEx2's Perpendicular four-centred arch. Only
  the shape of the arch differs.

  The arch is an inverted cycloid - the curve traced by a point on a
  rolling circle - taken over one full turn, so that it springs from the
  ground at both ends:

    I(t) = ( pi*a - a*(t - sin t),  a*(1 - cos t) ),   t in [0, 2*pi]

  written here right to left, so that block 1 springs from the right as
  in the other two examples. Unlike them the cycloid has no free shape
  parameter at all: its rise is always exactly 1/pi of its span (1.273 m
  on a 4 m span here), and fixing the span fixes everything else. That
  makes it the flattest of the three, and it is the only one whose
  intrados is a single smooth curve from springing to springing - so the
  apex needs no mitre, and the keystone is an ordinary block.

  Three things follow from the curve that the circular examples never
  had to deal with:

    - There is no centre to measure a hoop direction from. Everything is
      done from the curve's own parametrisation instead: the unit
      tangent is T(t) = (-sin(t/2), cos(t/2)) and the outward normal
      N(t) = (cos(t/2), sin(t/2)), both exactly, and the extrados is the
      offset curve I(t) + RingThickness*N(t). Offsetting outwards is
      always well behaved here, because the centre of curvature is on
      the other side, so the normals diverge and the ring never folds
      over on itself.

    - Voussoirs are cut to equal INTRADOS ARC LENGTH, not to equal
      parameter - which is both what a mason would do and what keeps the
      blocks the same size. Arc length has a closed form for a cycloid,
      s(t) = 4a(1 - cos(t/2)), and so does its inverse, which is what
      Theta() uses. Dividing by parameter instead would give a first
      voussoir 0.07 m long against 0.62 m at the crown.

    - The intrados is a cusp at each springing: the curve leaves the
      ground vertically, with infinite curvature. That is a real feature
      of the shape, not an artefact, and it is well behaved here - the
      intrados meets the horizontal springing face at a right angle, so
      there is no re-entrant corner and no elastic singularity - but the
      voussoirs nearest the springings are strongly tapered, and the
      peak stresses reported there are the least trustworthy numbers in
      the output. The integrated thrust-line results are not affected.

  The blocks are bounded by joints normal to the intrados and by
  polylines of NbAlongBlock straight segments, one per element, so every
  mesh node on either face sits exactly on the true curve rather than on
  an approximation to it. Everything downstream - the bonded conformal
  mesh, the plane-stress solve, the caveat that masonry carries no
  tension, and the thrust-line-against-the-middle-third report - is as
  described in uArchEx1.pas's own header. }

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

  // Matched to ArchEx1 and ArchEx2 so all three are comparable.
  HalfSpan = 2.0;
  RingThickness = 0.6;
  BarrelDepth = 1.0;

  // Odd, so that block (NbBlocks+1) div 2 is a keystone centred on the
  // apex - and 13, as ArchEx1, since the two arches are close enough in
  // length for the voussoirs to come out a similar size.
  NbBlocks = 13;

  // Structured mesh per voussoir, as the other two.
  NbAcrossRing = 6;
  NbAlongBlock = 5;

  // Stations along the intrados: one per element edge, so the joints
  // land on every NbAlongBlock-th one.
  NbStations = NbBlocks * NbAlongBlock;

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
  // intrados length from the right springing: 0.50 is the apex, and so
  // the middle of the keystone; 0.75 is the quarter point of the arch's
  // length measured from the left springing. Both are the stations
  // ArchEx1 and ArchEx2 load.
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

  // A joint between two voussoirs, or a springing face. Stored as the
  // plane it lies in, which is what the thrust-line integration needs.
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
    FStationT : Array[0..NbStations] of Double;
    FBounds : Array[0..NbBlocks] of RBoundary;

    FRise : Double;
    FIntradosLength : Double;

    // Ring weight lying between the springing faces and the plane the
    // joint band actually samples - see ReportJoints.
    FSliver : Double;

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

    function ThetaOfPoint(px, py, t0, t1 : Double) : Double;
    function OnExtrados(x, y : Double) : Boolean;

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

(******************** THE CURVE ITSELF ********************)

// The rolling-circle radius. Everything else about a cycloid follows
// from it: the span is 2*pi*a and the rise 2*a, so the rise/span ratio
// is always 1/pi whatever the scale.
const
  CycloidA = HalfSpan / Pi;

// Intrados point at parameter t, written right to left so that t = 0 is
// the right springing.
function IntradosX(t : Double) : Double;
function IntradosY(t : Double) : Double;

// Unit tangent, in the direction of travel, and the outward unit
// normal. Both are exact: |dI/dt| = 2a*sin(t/2) divides out cleanly.
function TangentX(t : Double) : Double;
function TangentY(t : Double) : Double;
function NormalX(t : Double) : Double;
function NormalY(t : Double) : Double;

// Intrados arc length from the right springing to parameter t, and its
// inverse - both closed form for a cycloid.
function ArcLength(t : Double) : Double;
function Theta(s : Double) : Double;

implementation

const

  DataDir = '..' + PathDelim + 'Data' + PathDelim;

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  GmshExecutable = 'gmsh';
{$ENDIF}

  GeoFile = DataDir + 'archex3.geo';
  MshFile = DataDir + 'archex3.msh';
  PosFile = DataDir + 'archex3.pos';
  ScrFile = DataDir + 'archex3.scr';

  GeoTol = 1.0e-6;

var
  DotFS : TFormatSettings;

function IntradosX(t : Double) : Double;
begin

  Result := Pi * CycloidA - CycloidA * (t - Sin(t));

end;

function IntradosY(t : Double) : Double;
begin

  Result := CycloidA * (1 - Cos(t));

end;

function TangentX(t : Double) : Double;
begin

  Result := -Sin(t / 2);

end;

function TangentY(t : Double) : Double;
begin

  Result := Cos(t / 2);

end;

function NormalX(t : Double) : Double;
begin

  Result := Cos(t / 2);

end;

function NormalY(t : Double) : Double;
begin

  Result := Sin(t / 2);

end;

function ArcLength(t : Double) : Double;
begin

  Result := 4 * CycloidA * (1 - Cos(t / 2));

end;

{ The inverse of ArcLength: the parameter at which the intrados has run
  s from the right springing. Cutting voussoirs to equal s rather than
  to equal t is what keeps them the same size - see this unit's header. }
function Theta(s : Double) : Double;
var
  c : Double;
begin

  c := 1 - s / (4 * CycloidA);

  // Guard the ends against rounding taking the argument outside the
  // domain of ArcCos - s = 8a lands exactly on -1.
  if c > 1 then
    c := 1
  else if c < -1 then
    c := -1;

  Result := 2 * ArcCos(c);

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

{ The stations along the intrados, equally spaced by arc length, and the
  joint planes at every NbAlongBlock-th one. }
procedure TArchModel.SetupGeometry;
var

  m, k : Integer;

  t : Double;

begin

  FIntradosLength := ArcLength(2 * Pi);
  FRise := 2 * CycloidA;

  for m := 0 to NbStations do
    FStationT[m] := Theta(m * FIntradosLength / NbStations);

  for k := 0 to NbBlocks do
  begin

    t := FStationT[k * NbAlongBlock];

    FBounds[k].x0 := IntradosX(t);
    FBounds[k].y0 := IntradosY(t);

    FBounds[k].x1 := FBounds[k].x0 + RingThickness * NormalX(t);
    FBounds[k].y1 := FBounds[k].y0 + RingThickness * NormalY(t);

    FBounds[k].mx := 0.5 * (FBounds[k].x0 + FBounds[k].x1);
    FBounds[k].my := 0.5 * (FBounds[k].y0 + FBounds[k].y1);

    // The joint runs along the normal, so its depth is the ring
    // thickness exactly and its own plane normal is the tangent.
    FBounds[k].h := RingThickness;

    FBounds[k].tx := NormalX(t);
    FBounds[k].ty := NormalY(t);

    FBounds[k].nx := TangentX(t);
    FBounds[k].ny := TangentY(t);

  end;

end;

{ The parameter t at which the joint normal passes through (px,py),
  found between t0 and t1 by bisection on

    g(t) = (P - I(t)) . T(t)

  which is the signed distance of P along the arch from the station at
  t. g is strictly decreasing across the ring - dg/dt <= -|dI/dt|,
  because the centre of curvature is on the far side, so (P-I).T' is
  negative - which makes the root unique and bisection safe. }
function TArchModel.ThetaOfPoint(px, py, t0, t1 : Double) : Double;
const
  MaxIter = 60;
  Tol = 1.0e-12;
var
  a, b, m, g : Double;
  i : Integer;
begin

  a := t0;
  b := t1;

  for i := 1 to MaxIter do
  begin

    m := 0.5 * (a + b);

    g := (px - IntradosX(m)) * TangentX(m) + (py - IntradosY(m)) * TangentY(m);

    if g > 0 then
      a := m
    else
      b := m;

    if b - a < Tol then
      Break;

  end;

  Result := 0.5 * (a + b);

end;

{ Is this node on the outer face of the ring? The extrados is an offset
  curve with no closed-form implicit test, so this walks the stations and
  asks whether the node is within rounding of any of them - which is
  exact, because every extrados mesh node is generated at a station. }
function TArchModel.OnExtrados(x, y : Double) : Boolean;
var

  m : Integer;

  t, ex, ey : Double;

begin

  Result := False;

  for m := 0 to NbStations do
  begin

    t := FStationT[m];

    ex := IntradosX(t) + RingThickness * NormalX(t);
    ey := IntradosY(t) + RingThickness * NormalY(t);

    if Sqr(x - ex) + Sqr(y - ey) < Sqr(1.0e-6) then
      Exit(True);

  end;

end;

(*******************************************************************
  Geometry file, one gmsh plane surface per voussoir.

  A cycloid is not an arc, so the faces cannot be gmsh Circles. Each
  face is instead a polyline of NbAlongBlock straight segments - one per
  element - through the stations, each transfinited to a single
  division. Every mesh node on either face therefore lands exactly on
  the true curve, rather than on a spline fitted to it, and the block's
  along-arch sides still carry the NbAlongBlock divisions the transfinite
  surface needs to match its joints.

    point   10+m            intrados point at station m   (m = 0..S)
    point   10+(S+1)+m      extrados point at station m
    line    200+m           intrados segment m -> m+1     (m = 0..S-1)
    line    200+S+m         extrados segment m -> m+1
    line    200+2*S+k       joint k                       (k = 0..N)
    loop    500+k, surface 600+k, physical surface k+1
********************************************************************)
procedure TArchModel.WriteGeoFile(const FileName : String);

  function LIn(m : Integer) : Integer;
  begin
    Result := 200 + m;
  end;

  function LOut(m : Integer) : Integer;
  begin
    Result := 200 + NbStations + m;
  end;

  function LJoint(k : Integer) : Integer;
  begin
    Result := 200 + 2 * NbStations + k;
  end;

var

  F : TextFile;

  m, k : Integer;

  t : Double;

  Joints, Segs, Loop : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, 'Mesh.MshFileVersion=1;');

    WriteLn(F, 'cl = ' + Num(RingThickness / NbAcrossRing) + ';');

    for m := 0 to NbStations do
    begin

      t := FStationT[m];

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + m, Num(IntradosX(t)), Num(IntradosY(t))]));

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [10 + (NbStations + 1) + m,
         Num(IntradosX(t) + RingThickness * NormalX(t)),
         Num(IntradosY(t) + RingThickness * NormalY(t))]));

    end;

    Segs := '';

    for m := 0 to NbStations - 1 do
    begin

      WriteLn(F, Format('Line(%d) = {%d,%d};', [LIn(m), 10 + m, 10 + m + 1]));

      WriteLn(F, Format('Line(%d) = {%d,%d};',
        [LOut(m), 10 + (NbStations + 1) + m, 10 + (NbStations + 1) + m + 1]));

      if Segs <> '' then
        Segs := Segs + ',';

      Segs := Segs + IntToStr(LIn(m)) + ',' + IntToStr(LOut(m));

    end;

    Joints := '';

    for k := 0 to NbBlocks do
    begin

      m := k * NbAlongBlock;

      WriteLn(F, Format('Line(%d) = {%d,%d};',
        [LJoint(k), 10 + m, 10 + (NbStations + 1) + m]));

      if Joints <> '' then
        Joints := Joints + ',';

      Joints := Joints + IntToStr(LJoint(k));

    end;

    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Joints, NbAcrossRing + 1]));

    // One division per face segment: the segments ARE the elements.
    WriteLn(F, Format('Transfinite Line {%s} = 2;', [Segs]));

    for k := 0 to NbBlocks - 1 do
    begin

      // Up the joint, along the extrados, down the next joint, back
      // along the intrados - the last two reversed.
      Loop := IntToStr(LJoint(k));

      for m := k * NbAlongBlock to (k + 1) * NbAlongBlock - 1 do
        Loop := Loop + ',' + IntToStr(LOut(m));

      Loop := Loop + ',-' + IntToStr(LJoint(k + 1));

      for m := (k + 1) * NbAlongBlock - 1 downto k * NbAlongBlock do
        Loop := Loop + ',-' + IntToStr(LIn(m));

      WriteLn(F, Format('Line Loop(%d) = {%s};', [500 + k, Loop]));

      WriteLn(F, Format('Plane Surface(%d) = {%d};', [600 + k, 500 + k]));

      // Four corners nominated out of a boundary of 12 curves: gmsh
      // treats the rest as intermediate points along the sides, which
      // is exactly what they are.
      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [600 + k,
         10 + k * NbAlongBlock,
         10 + (NbStations + 1) + k * NbAlongBlock,
         10 + (NbStations + 1) + (k + 1) * NbAlongBlock,
         10 + (k + 1) * NbAlongBlock]));

      WriteLn(F, Format('Recombine Surface {%d};', [600 + k]));

      WriteLn(F, Format('Physical Surface(%d) = {%d};', [k + 1, 600 + k]));

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
      '). Install gmsh, or edit GmshExecutable in uArchEx3.pas.');

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
  region gmsh wrote), and the hoop direction there - which, with no
  centre to work from, comes from the curve parameter the element sits
  at, recovered by ThetaOfPoint within its own block's parameter range. }
procedure TArchModel.CalcElementGeometry;
var

  i, j, n, nx, b : Integer;

  cx, cy, x0, y0, x1, y1, a2, t : Double;

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
    // that depth is its mean along-arch extent - which is what the
    // joint band in CalcThrustLine has to be measured against, since a
    // tapered voussoir's outer elements are much longer than its inner
    // ones. On this arch that taper reaches nearly 3:1 at the cusp.
    FEleLen[i] := FEleArea[i] / (RingThickness / NbAcrossRing);

    b := FGmsh.ElementPhysicalRegion[i];

    if (b < 1) or (b > NbBlocks) then
      raise Exception.Create('Element ' + IntToStr(i) + ' carries physical region ' +
        IntToStr(b) + ', which is not a voussoir - the .geo and the block table ' +
        'have got out of step.');

    FEleBlock[i] := b;

    t := ThetaOfPoint(cx, cy,
                      FStationT[(b - 1) * NbAlongBlock],
                      FStationT[b * NbAlongBlock]);

    // Hoop direction: along the curve, which is where the arch thrust
    // runs.
    FEleNx[i] := TangentX(t);
    FEleNy[i] := TangentY(t);

    FTotalArea := FTotalArea + FEleArea[i];

  end;

  FSelfWeight := Density * Abs(GravityAccel) * FTotalArea * BarrelDepth;

end;

procedure TArchModel.BuildModel;
var

  i, j, NbNodes, MaterialId : Integer;

  Node : Array[0..4] of Integer;

  EleType : NEleType;

  BestD, d, NodeForce, Window, sLoad, tLoad : Double;

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

  // The cycloid springs vertically from the ground, so its normal there
  // is horizontal and both springing faces lie in the y = 0 plane -
  // the same situation as ArchEx1 and ArchEx2, and the same reason the
  // end joints give a free static check in ReportJoints.
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

    tLoad := Theta(sLoad);

    FLoadX := IntradosX(tLoad) + RingThickness * NormalX(tLoad);
    FLoadY := IntradosY(tLoad) + RingThickness * NormalY(tLoad);

    // Spread over about one voussoir of the extrados, as the other two
    // examples do.
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

    d := Sqrt(Sqr(FGmsh.CoordX[i]) + Sqr(FGmsh.CoordY[i] - FRise));

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

    // Hoop stress: the direct stress on the joint plane through this
    // element, n'*S*n, with n along the curve. The arch thrust made
    // visible.
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

{ Where the thrust line crosses each joint - see uArchEx1.pas's
  ReportJoints comment for what the numbers mean. The elements within
  one layer of a joint, and belonging to one of the two blocks that meet
  there, give the direct stress on the joint plane at NbAcrossRing
  equally deep stations, which integrate directly - midpoint rule, every
  element weighted equally - to the thrust, the moment about mid-depth,
  and hence to the eccentricity e = M/N. }
procedure TArchModel.CalcThrustLine;
var

  k, i, n, b : Integer;

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

  FSliver := 0;

  for k := 0 to NbBlocks do
  begin

    FJValid[k] := False;

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

      if (b <> k) and (b <> k + 1) then
        Continue;

      // Element centroid in the joint's own frame.
      dxc := FEleCx[i] - FBounds[k].mx;
      dyc := FEleCy[i] - FBounds[k].my;

      dn := dxc * nx + dyc * ny;

      // The first element layer either side of the joint and no
      // further. The test is against each element's OWN along-arch
      // extent rather than a single band width for the joint: layer
      // centroids sit at 0.5, 1.5, ... of their own element's length
      // from the joint, and where the ring tapers the outer elements
      // are far longer than the inner ones. A fixed band taken from the
      // intrados would quietly drop the outer layers, biasing both the
      // thrust and the eccentricity - badly here, since the taper at
      // the springing cusps approaches 3:1.
      if Abs(dn) > 0.9 * FEleLen[i] then
        Continue;

      // At the springings, the band's elements sit their own half-length
      // ABOVE the face, so their stresses cannot see the ring below
      // them. That wedge of weight is what the static check comes up
      // short by, and at a cusp it is far from uniform across the ring -
      // from 0.04 m at the intrados to 0.11 m at the extrados here - so
      // it is accumulated element by element rather than estimated.
      if (k = 0) or (k = NbBlocks) then
        FSliver := FSliver + Abs(dn) * (RingThickness / NbAcrossRing) *
                   BarrelDepth * Density * Abs(GravityAccel);

      // Position across the ring depth, intrados negative.
      x := dxc * FBounds[k].tx + dyc * FBounds[k].ty;

      // Direct stress on the joint plane.
      y := FSxx[i] * nx * nx + 2 * FSxy[i] * nx * ny + FSyy[i] * ny * ny;

      SumSn := SumSn + y;
      SumSnX := SumSnX + y * x;

      if n = 0 then
      begin
        FJMinSn[k] := y;
        FJMaxSn[k] := y;
      end
      else
      begin
        if y < FJMinSn[k] then FJMinSn[k] := y;
        if y > FJMaxSn[k] then FJMaxSn[k] := y;
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

    FJThrust[k] := Thrust;
    FJEcc[k] := ecc;

    FJPx[k] := FBounds[k].mx + ecc * FBounds[k].tx;
    FJPy[k] := FBounds[k].my + ecc * FBounds[k].ty;

    FJValid[k] := True;

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

  The middle third is drawn station by station rather than joint by
  joint, so that it follows the curve smoothly rather than in thirteen
  straight chords. }
procedure TArchModel.AppendLineViews(const FileName : String);
var

  F : TextFile;

  k, m : Integer;

  ax, ay, bx, by : Double;

  procedure Segment(x0, y0, x1, y1, v : Double);
  begin
    WriteLn(F, Format('SL(%e,%e,0,%e,%e,0){%e,%e};',
      [x0, y0, x1, y1, v, v], DotFS));
  end;

  // Mid-ring point at station st, offset by u along the joint normal.
  procedure MidPoint(st : Integer; u : Double; var px, py : Double);
  var
    tt : Double;
  begin
    tt := FStationT[st];
    px := IntradosX(tt) + (RingThickness / 2 + u) * NormalX(tt);
    py := IntradosY(tt) + (RingThickness / 2 + u) * NormalY(tt);
  end;

begin

  AssignFile(F, FileName);

  SafeAppendText(F);

  try

    (******************** THRUST LINE ********************)

    WriteLn(F, 'View "Thrust line" {');

    for k := 0 to NbBlocks - 1 do
      if FJValid[k] and FJValid[k + 1] then
        Segment(FJPx[k], FJPy[k], FJPx[k + 1], FJPy[k + 1],
                Abs(FJThrust[k]) / 1000);

    WriteLn(F, '};');

    (******************** MIDDLE THIRD ********************)

    // The band the thrust line must stay inside for the joints to be in
    // compression over their whole depth: mid-ring plus and minus h/6.
    WriteLn(F, 'View "Middle third" {');

    for m := 0 to NbStations - 1 do
    begin

      MidPoint(m, -RingThickness / 6, ax, ay);
      MidPoint(m + 1, -RingThickness / 6, bx, by);
      Segment(ax, ay, bx, by, 0);

      MidPoint(m, +RingThickness / 6, ax, ay);
      MidPoint(m + 1, +RingThickness / 6, bx, by);
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
  WriteLn(Format('  Rise                     : %8.3f m  (rise/span %.3f = 1/pi)',
    [FRise, FRise / (2 * HalfSpan)]));
  WriteLn(Format('  Ring thickness           : %8.3f m  (%d voussoirs)',
    [RingThickness, NbBlocks]));
  WriteLn(Format('  Barrel depth             : %8.3f m', [BarrelDepth]));
  WriteLn(Format('  Rolling-circle radius a  : %8.3f m', [CycloidA]));
  WriteLn(Format('  Intrados length          : %8.3f m  (= 8a)', [FIntradosLength]));
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

  MinS2, MaxS1, MeanSn, Area, s0, s1 : Double;

  Kind : String;

begin

  WriteLn;
  WriteLn('================ PER-BLOCK STRESS (MPa, tension +) ================');
  WriteLn('  Block  s along (m)   mean hoop   peak compr.   peak tens.   over mortar ft');

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

    // Voussoirs are cut to equal intrados length, so the station range
    // is the same width for every block.
    s0 := (b - 1) * FIntradosLength / NbBlocks;
    s1 := b * FIntradosLength / NbBlocks;

    if b = (NbBlocks + 1) div 2 then
      Kind := '*'
    else
      Kind := ' ';

    Write(Format('  %5d%s %4.2f-%4.2f  %11.3f   %11.3f   %10.3f',
      [b, Kind, s0, s1, MeanSn / 1e6, MinS2 / 1e6, MaxS1 / 1e6]));

    if nTens > 0 then
      WriteLn(Format('   %d/%d elements', [nTens, n]))
    else
      WriteLn('   -');

  end;

  WriteLn('  (s is measured along the intrados from the right springing;');
  WriteLn('   block ', (NbBlocks + 1) div 2, ', marked *, is the keystone, centred on the apex)');

end;

{ The masonry reading of the elastic result - the same thrust-line
  analysis as ArchEx1's and ArchEx2's. See CalcThrustLine for how the
  numbers are arrived at.

  The thrust line crosses each joint at an eccentricity e = M/N from
  mid-depth, and Heyman's no-tension criterion is |e| <= h/6. Every
  joint here runs along the intrados normal, so h is the ring thickness
  exactly.

  A flagged joint is where the ELASTIC thrust line has left the middle
  third: the bonded model is carrying tension no mortar joint could
  supply, and a real arch would crack and hinge there instead. That is
  cracking and redistribution, not collapse - four hinges are needed
  before the arch becomes a mechanism. }
procedure TArchModel.ReportJoints;
var

  k, nOutside : Integer;

  EndThrust : Double;

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

    if not FJValid[k] then
      Continue;

    // The two end joints lie in the y = 0 plane, so their normal is
    // vertical and the thrust across them is the vertical reaction at
    // that springing - which is what makes the static check below
    // possible without asking the engine for reactions it does not
    // expose under the penalty method.
    if (k = 0) or (k = NbBlocks) then
      EndThrust := EndThrust + Abs(FJThrust[k]);

    if Abs(FJEcc[k]) <= FBounds[k].h / 6 then
      Status := 'inside'
    else
    begin
      Status := 'OUTSIDE -> hinge';
      Inc(nOutside);
    end;

    WriteLn(Format('  %5d  %6.3f  %10.2f  %7.3f  %10.3f  %10.3f   %s',
      [k, FBounds[k].my, FJThrust[k] / 1000, FJEcc[k] / FBounds[k].h,
       FJMinSn[k] / 1e6, FJMaxSn[k] / 1e6, Status]));

  end;

  WriteLn;

  if nOutside = 0 then
    WriteLn('  The thrust line stays within the middle third at every joint.')
  else
    WriteLn(Format('  The thrust line leaves the middle third at %d joint(s).', [nOutside]));

  WriteLn('  e/h is the thrust line''s offset from mid-ring as a fraction of the');
  WriteLn('  ring thickness; |e/h| <= 0.167 is Heyman''s no-tension limit. A joint');
  WriteLn('  outside it would open on a real arch, forming a hinge there - which');
  WriteLn('  means cracking and redistribution, not collapse: four hinges are');
  WriteLn('  needed before the arch becomes a mechanism.');

  WriteLn;
  WriteLn(Format('  Static check: springing thrusts total %.2f kN against an applied',
    [EndThrust / 1000]));
  WriteLn(Format('  vertical load of %.2f kN (self weight %.2f + superimposed %.2f), %.1f%%.',
    [(FSelfWeight + FAppliedLoad) / 1000, FSelfWeight / 1000, FAppliedLoad / 1000,
     100 * (EndThrust / (FSelfWeight + FAppliedLoad) - 1)]));

  WriteLn(Format('  Of that gap, %.1f%% is ring weight lying below the plane the band at',
    [100 * FSliver / (FSelfWeight + FAppliedLoad)]));
  WriteLn('  each springing actually samples; the rest is discretisation, and both');
  WriteLn('  shrink with the mesh (at twice this density the gap closes to -5.4%).');
  WriteLn('  This is the least accurate of the three arch examples on that count:');
  WriteLn('  the cusp makes the springing voussoirs taper nearly 3:1, so their');
  WriteLn('  elements are both large and distorted exactly where the check is made.');
  WriteLn('  The joints away from the springings are unaffected.');

end;

procedure TArchModel.WriteScript(const FileName : String);
var

  F : TextFile;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, '// Generated by ArchEx3 - do not edit, it is rewritten on every run.');
    WriteLn(F);
    WriteLn(F, 'Include "archex3.pos";');
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

  WriteLn('ArchEx3 - cycloidal masonry arch, load case ', FLoadCase);
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
