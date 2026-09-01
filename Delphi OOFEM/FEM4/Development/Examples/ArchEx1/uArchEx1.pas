unit uArchEx1;

{ ArchEx1 - stresses in a classic (Roman) semicircular masonry arch.

  The arch ring is built as NbBlocks separate voussoirs - wedge-shaped
  blocks bounded by two radial joints and by the intrados/extrados arcs -
  meshed block by block into a structured grid of quadrilaterals, then
  analysed as a plane-stress elastic body by TStructuralEngine under its
  own self weight plus (load cases 2 and 3) a superimposed point load.

  Because adjacent voussoirs share the geometric joint line, gmsh meshes
  them conformally: the joints are visible in the mesh and in the 'Block'
  view, but the model is BONDED across them - the elastic solve cannot
  open a joint or slide one block on another. That is the standard first
  analysis of a masonry arch, and it is still the informative one,
  provided the results are read the way this example's own report reads
  them: masonry has essentially no tensile strength, so wherever the
  bonded model reports tension across a joint, a real arch would instead
  crack and hinge there. ReportJoints therefore reduces the stress field
  back to the quantity a mason - or Heyman's limit analysis - cares
  about: the position of the thrust line at each joint, and the joints
  where it leaves the middle third of the ring, which is exactly the
  classical no-tension criterion.

  ArchEx2 runs the same analysis on a Perpendicular (four-centred) arch
  of the same span, ring, barrel, masonry and mesh density, so the two
  reports compare line for line. }

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

  // Odd, so that block (NbBlocks+1) div 2 is a true keystone straddling
  // the crown - the Roman arrangement.
  NbBlocks = 13;

  InnerRadius = 2.0;   // intrados radius -> 4.0 m clear span
  OuterRadius = 2.6;   // extrados radius -> 0.6 m ring thickness
  BarrelDepth = 1.0;   // out-of-plane depth of the barrel

  RingThickness = OuterRadius - InnerRadius;
  MidRadius = 0.5 * (InnerRadius + OuterRadius);

  // Structured mesh per voussoir: NbAcrossRing quads through the ring
  // thickness by NbAlongBlock quads along the arc. Six layers through the
  // thickness is what makes the joint-by-joint thrust-line integration in
  // ReportJoints meaningful - it needs the stress GRADIENT across the
  // ring, not just its average.
  NbAcrossRing = 6;
  NbAlongBlock = 5;

  (******************** MATERIAL ********************)

  Density = 2200.0;        // kg/m3 - limestone masonry
  ElasticModulus = 8.0e9;  // Pa
  PoissonRatio = 0.2;
  ThermalExpansion = 1.0e-5;

  GravityAccel = -9.81;    // m/s2, acting along -Y

  // Nominal direct tensile strength of a lime-mortar bed joint. Masonry
  // is conventionally taken as having none at all; 0.1 MPa is used here
  // only as a reporting threshold, to separate numerical noise from
  // tension a real joint could not carry.
  MortarTensileStrength = 1.0e5;

  (******************** LOADING ********************)

  // Superimposed point load, as a fraction of the ring's own weight. Load
  // cases 2 and 3 apply the same magnitude in different places, so that
  // comparing their reports isolates the effect of WHERE a load sits.
  LoadFraction = 0.25;

  LoadCaseSelfWeight = 1;
  LoadCaseCrown = 2;
  LoadCaseHaunch = 3;

  (******************** POST-PROCESSING ********************)

  // View indices inside archex1.pos, in the order PostProcess writes
  // them. archex1.scr drives these by number, so the two must agree.
  ViewDisplacement = 0;
  ViewHoop = 3;

type

  TArchModel = class(TObject)

  private

    FLoadCase : Integer;

    FGmsh : TGmsh;
    FEngine : TStructuralEngine;

    // Material / load expressions. TStructuralEngine keeps references to
    // these for the whole solve, so they are fields rather than locals.
    FRho, FE, FPoisson, FAlpha : TExpressionList;
    FZero : TExpressionList;
    FNodeLoad : TExpressionList;

    FTotalArea : Double;
    FSelfWeight : Double;    // magnitude, N
    FAppliedLoad : Double;   // magnitude, N
    FNbLoadedNodes : Integer;

    FElapsed : Double;

    // Per element, filled by CalcElementGeometry / PostProcess.
    FEleBlock : TDoubleArray;
    FEleArea, FEleR, FEleTheta : TDoubleArray;
    FSxx, FSyy, FSxy : TDoubleArray;
    FS1, FS2, FSn, FVonMises : TDoubleArray;

    // Per node.
    FUx, FUy, FUz : TDoubleArray;

    FCrownNode : Integer;
    FNbRestrained : Integer;

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

    // TDependantVarFunc. Every expression in this example is a constant,
    // so the dependant variable it is evaluated at is always 0.
    function Constant(NodeId, ElementId : Integer) : Double;

    // TCallbackFunc, run by TStructuralEngine once the solve finishes.
    procedure PostProcess;

    procedure Run(ViewResults : Boolean);

  end;

implementation

const

  DataDir = '..' + PathDelim + 'Data' + PathDelim;

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  // Bare name, resolved via $PATH by TProcess itself - matches a normal
  // `apt install gmsh`. Same convention as Ex37/Ex39/Ex42.
  GmshExecutable = 'gmsh';
{$ENDIF}

  GeoFile = DataDir + 'archex1.geo';
  MshFile = DataDir + 'archex1.msh';
  PosFile = DataDir + 'archex1.pos';
  ScrFile = DataDir + 'archex1.scr';

  // Geometric tolerance for picking nodes off the springing plane and off
  // the extrados: the mesh sits on exact circles, so anything well below
  // one element size does.
  GeoTol = 1.0e-6;

var
  // A locale-independent number format for the .geo and for load
  // expressions: gmsh's parser and CXS.FEMLAP.FormulaEval both want '.'
  // as the decimal separator, whatever the machine's locale says.
  DotFS : TFormatSettings;

function Num(v : Double) : String;
begin

  Result := Format('%.10f', [v], DotFS);

end;

{ Reset/ReWrite on a file another process (gmsh, or a virus scanner) may
  still hold briefly - see CXS.FEMLAP.Gmsh.pas's own SafeReset/SafeReWrite
  comment for the full story. The .geo written here is read by gmsh
  moments later and rewritten on the next run, so it is exposed to exactly
  the same transient sharing violation. }
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
  Geometry: one gmsh plane surface per voussoir.

  Entity ids are laid out by hand rather than with gmsh's newp/newl
  counters, so the Pascal side can refer to any of them directly:

    point   1               ring centre (the centre of every arc)
    point   10+k            intrados point at joint k      (k = 0..N)
    point   10+(N+1)+k      extrados point at joint k
    line    10+k            joint k, intrados -> extrados
    line    10+(N+1)+k      intrados arc of block k        (k = 0..N-1)
    line    10+(N+1)+N+k    extrados arc of block k
    loop    200+k, surface 500+k, physical surface k+1

  Adjacent blocks reference the SAME joint line, which is what makes the
  mesh conformal across a joint. The physical surface tag (1..N) comes
  back out of the .msh as each element's physical region, and is what
  ReportBlocks and the 'Block' view use to tell one voussoir from the
  next.
********************************************************************)
procedure TArchModel.WriteGeoFile(const FileName : String);

  function PIn(i : Integer) : Integer;
  begin
    Result := 10 + i;
  end;

  function POut(i : Integer) : Integer;
  begin
    Result := 10 + (NbBlocks + 1) + i;
  end;

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

  k : Integer;

  theta : Double;

  Joints, Arcs : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    // The framework's mesh reader (TGmsh.ReadMesh) parses the original
    // $NOD/$ELM format, so the .geo must ask for it explicitly - gmsh 4
    // writes version 4.1 otherwise.
    WriteLn(F, 'Mesh.MshFileVersion=1;');

    // Every curve is transfinite below, so this only ever applies to
    // geometry gmsh has no division count for. Kept so the file still
    // meshes if the transfinite lines are commented out.
    WriteLn(F, 'cl = ' + Num(RingThickness / NbAcrossRing) + ';');

    WriteLn(F, 'Point(1) = {0,0,0,cl};');

    for k := 0 to NbBlocks do
    begin

      theta := Pi * k / NbBlocks;

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [PIn(k), Num(InnerRadius * Cos(theta)), Num(InnerRadius * Sin(theta))]));

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [POut(k), Num(OuterRadius * Cos(theta)), Num(OuterRadius * Sin(theta))]));

    end;

    Joints := '';

    for k := 0 to NbBlocks do
    begin

      WriteLn(F, Format('Line(%d) = {%d,%d};', [LJoint(k), PIn(k), POut(k)]));

      if k > 0 then
        Joints := Joints + ',';

      Joints := Joints + IntToStr(LJoint(k));

    end;

    Arcs := '';

    for k := 0 to NbBlocks - 1 do
    begin

      // Circle(id) = {start, centre, end}. Each arc spans 180/NbBlocks
      // degrees, comfortably under the half-turn limit gmsh imposes on a
      // single Circle.
      WriteLn(F, Format('Circle(%d) = {%d,1,%d};', [LArcIn(k), PIn(k), PIn(k+1)]));
      WriteLn(F, Format('Circle(%d) = {%d,1,%d};', [LArcOut(k), POut(k), POut(k+1)]));

      if k > 0 then
        Arcs := Arcs + ',';

      Arcs := Arcs + IntToStr(LArcIn(k)) + ',' + IntToStr(LArcOut(k));

    end;

    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Joints, NbAcrossRing + 1]));
    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Arcs, NbAlongBlock + 1]));

    for k := 0 to NbBlocks - 1 do
    begin

      // Loop: up joint k, along the extrados, back down joint k+1, back
      // along the intrados.
      WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
        [200 + k, LJoint(k), LArcOut(k), LJoint(k+1), LArcIn(k)]));

      WriteLn(F, Format('Plane Surface(%d) = {%d};', [500 + k, 200 + k]));

      // Transfinite + Recombine turns each voussoir into a regular grid
      // of quadrilaterals rather than an unstructured triangulation -
      // both because it reads as masonry coursing, and because the stress
      // across the ring is then sampled on clean radial layers.
      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [500 + k, PIn(k), POut(k), POut(k+1), PIn(k+1)]));

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
      '). Install gmsh, or edit GmshExecutable in uArchEx1.pas.');

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

{ Centroid position (radius and angle from the +X axis) and area of every
  element, plus the total ring area the self weight is derived from. All
  of it comes straight from the mesh, so it stays correct if the mesh
  density or the block count is changed. }
procedure TArchModel.CalcElementGeometry;
var

  i, j, n, nx : Integer;

  cx, cy, x0, y0, x1, y1, a2 : Double;

begin

  SetLength(FEleBlock, FGmsh.NbElements);
  SetLength(FEleArea, FGmsh.NbElements);
  SetLength(FEleR, FGmsh.NbElements);
  SetLength(FEleTheta, FGmsh.NbElements);

  FTotalArea := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] = GMSH_QUAD then
      n := 4
    else
      n := 3;

    cx := 0;
    cy := 0;

    // Shoelace formula round the element's own node ring - the same area
    // the element class computes internally, but available here without
    // reaching into TStructuralEngine.
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

    FEleR[i] := Sqrt(cx * cx + cy * cy);
    FEleTheta[i] := ArcTan2(cy, cx);

    FEleBlock[i] := FGmsh.ElementPhysicalRegion[i];

    FTotalArea := FTotalArea + FEleArea[i];

  end;

  FSelfWeight := Density * Abs(GravityAccel) * FTotalArea * BarrelDepth;

end;

procedure TArchModel.BuildModel;
var

  i, j, NbNodes, MaterialId : Integer;

  Node : Array[0..4] of Integer;

  EleType : NEleType;

  x, y, r, theta, ThetaLoad, HalfWindow, BestD, d, NodeForce : Double;

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

  // The penalty method is what TStructuralEngine.SetNodalSources assumes:
  // with the elimination method it indexes b through FOldToNew, which is
  // -1 on a restrained degree of freedom.
  FEngine.PenaltyMethod := True;

  // soUMFPACK (MKL PARDISO) is known to return an all-zero displacement
  // vector for this framework's penalty-method systems on this machine -
  // see the note in Ex42's Unit42.pas. soGMRES solves the identical
  // assembled system correctly.
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

  // Both springings are built into massive abutments: every node on the
  // y = 0 plane - which the arch ring only touches on its two end joint
  // faces - is fully fixed.
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
      ThetaLoad := Pi / 2            // over the keystone
    else
      ThetaLoad := 3 * Pi / 4;       // over the left haunch, near quarter span

    // Half a voussoir either side of the load point, so a crown load
    // lands on the keystone and nothing else.
    HalfWindow := 0.5 * (Pi / NbBlocks);

    SetLength(IsLoaded, FGmsh.NbNodes);

    for i := 0 to FGmsh.NbNodes - 1 do
    begin

      x := FGmsh.CoordX[i];
      y := FGmsh.CoordY[i];

      r := Sqrt(x * x + y * y);
      theta := ArcTan2(y, x);

      IsLoaded[i] := (r > OuterRadius - GeoTol) and
                     (Abs(theta - ThetaLoad) <= HalfWindow + GeoTol);

      if IsLoaded[i] then
        Inc(FNbLoadedNodes);

    end;

    FAppliedLoad := LoadFraction * FSelfWeight;

    if FNbLoadedNodes > 0 then
    begin

      // Downwards, shared equally between the loaded extrados nodes.
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

    d := Sqrt(Sqr(FGmsh.CoordX[i]) + Sqr(FGmsh.CoordY[i] - InnerRadius));

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

  c, s, sxx, syy, sxy, avg, dif, rad : Double;

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

    // Principal stresses, tension positive: S1 is the algebraically
    // largest (the one masonry cannot carry), S2 the most compressive.
    avg := 0.5 * (sxx + syy);
    dif := 0.5 * (sxx - syy);
    rad := Sqrt(dif * dif + sxy * sxy);

    FS1[i] := avg + rad;
    FS2[i] := avg - rad;

    FVonMises[i] := Sqrt(Sqr(sxx) - sxx * syy + Sqr(syy) + 3 * Sqr(sxy));

    // Hoop (circumferential) stress: the direct stress on the radial
    // joint plane through this element, n'*S*n with n the unit vector
    // along the arch, n = (-sin(theta), cos(theta)). This is the arch
    // thrust made visible, and the quantity ReportJoints integrates.
    c := Cos(FEleTheta[i]);
    s := Sin(FEleTheta[i]);

    FSn[i] := sxx * s * s - 2 * sxy * s * c + syy * c * c;

  end;

  (******************** WRITE THE GMSH VIEWS ********************)

  FGmsh.OpenFile(PosFile);

  // The vector view goes first so it lands as gmsh's View[0]: it is the
  // one archex1.scr animates, and only a vector view can drive gmsh's
  // deformed-mesh display. Writing it with ReWriteFile = True is what
  // truncates the .pos; every later view appends.
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
  WriteLn(Format('  Span (intrados)          : %8.3f m', [2 * InnerRadius]));
  WriteLn(Format('  Rise                     : %8.3f m', [InnerRadius]));
  WriteLn(Format('  Ring thickness           : %8.3f m  (%d voussoirs)',
    [RingThickness, NbBlocks]));
  WriteLn(Format('  Barrel depth             : %8.3f m', [BarrelDepth]));
  WriteLn(Format('  Ring area / self weight  : %8.3f m2 / %8.2f kN',
    [FTotalArea, FSelfWeight / 1000]));
  WriteLn(Format('  Superimposed load        : %8.2f kN  (%d extrados nodes)',
    [FAppliedLoad / 1000, FNbLoadedNodes]));
  WriteLn(Format('  Restrained nodes         : %8d  (both springings, X and Y)',
    [FNbRestrained]));
  WriteLn(Format('  Solve time               : %8.0f ms', [FElapsed]));
  WriteLn;
  WriteLn(Format('  Crown intrados settlement: %8.4f mm', [-FUy[FCrownNode] * 1000]));
  WriteLn(Format('  Peak compression         : %8.3f MPa', [MaxComp / 1e6]));
  WriteLn(Format('  Peak tension             : %8.3f MPa', [MaxTens / 1e6]));

end;

procedure TArchModel.ReportBlocks;
var

  b, i, n, nTens : Integer;

  MinS2, MaxS1, MeanSn, Area, a0, a1 : Double;

begin

  WriteLn;
  WriteLn('================ PER-BLOCK STRESS (MPa, tension +) ================');
  WriteLn('  Block  arc (deg)    mean hoop   peak compr.   peak tens.   over mortar ft');

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

    // Blocks are numbered from the right springing round to the left.
    a0 := 180.0 * (b - 1) / NbBlocks;
    a1 := 180.0 * b / NbBlocks;

    Write(Format('  %5d  %5.1f-%5.1f  %11.3f   %11.3f   %10.3f',
      [b, a0, a1, MeanSn / 1e6, MinS2 / 1e6, MaxS1 / 1e6]));

    if nTens > 0 then
      WriteLn(Format('   %d/%d elements', [nTens, n]))
    else
      WriteLn('   -');

  end;

  WriteLn('  (keystone = block ', (NbBlocks + 1) div 2,
    '; block 1 springs from the right, block ', NbBlocks, ' from the left)');

end;

{ The masonry reading of the elastic result.

  At each of the NbBlocks+1 radial joints, the elements lying within a
  narrow angular band of the joint give the hoop stress Sn at
  NbAcrossRing equally deep stations through the ring. The thrust and
  the moment about mid-depth are integrated over the joint directly,
  midpoint rule, one station per layer:

    N = t * h * mean(Sn)         M = t * h * mean(Sn * x)

  with x = r - MidRadius, so the thrust line crosses the joint at an
  eccentricity e = M/N = sum(Sn*x)/sum(Sn) from the centre of the ring.
  Nothing here assumes the stress varies linearly across the joint - the
  resultant sits at that ratio whatever shape the stress block has - and
  every element counts equally, since each stands for one equally deep
  slice of the joint; weighting by element area would bias the result
  towards the extrados, where the elements are larger. ArchEx2 does the
  same, so the two examples' reports compare directly.

  Heyman's no-tension criterion is then simply |e| <= h/6: while the
  thrust line stays inside the middle third, the joint is in compression
  over its whole depth and the elastic answer is also a valid masonry
  answer. Outside it, the bonded model is carrying tension no mortar
  joint could supply, and a real arch would hinge at that joint instead.
  Four such hinges turn the arch into a mechanism, so the count and the
  placement of the flagged joints are the interesting output - compare
  load case 1's symmetric pattern (extrados at the crown, intrados at the
  haunches: the classical minimum-thrust line of a semicircular arch)
  against what the loaded cases do to it. Note that the flag says the
  ELASTIC thrust line has left the middle third, not that the arch has
  failed: a real arch redistributes as each hinge opens, and only a
  limit analysis that follows that redistribution can say how much more
  load it would take. }
procedure TArchModel.ReportJoints;
var

  k, i, n, nOutside : Integer;

  theta, band, x, y, EndThrust : Double;

  SumSn, SumSnX : Double;

  MinSn, MaxSn, Thrust, Moment, ecc, Sliver : Double;

  Status : String;

begin

  WriteLn;
  WriteLn('================ THRUST LINE AT THE JOINTS ================');
  WriteLn('  Joint  angle    thrust N     e/h      Sn min      Sn max   middle third');
  WriteLn('         (deg)       (kN)                (MPa)       (MPa)');

  // One element layer either side of the joint. Each element spans
  // 1/NbAlongBlock of a block, so its centroid sits half that from the
  // joint: 0.15 of a block reaches the first layer and no further.
  band := 0.15 * (Pi / NbBlocks);

  nOutside := 0;

  EndThrust := 0;

  for k := 0 to NbBlocks do
  begin

    theta := Pi * k / NbBlocks;

    n := 0;
    SumSn := 0;
    SumSnX := 0;
    MinSn := 0; MaxSn := 0;

    for i := 0 to FEngine.NbElements - 1 do
    begin

      if Abs(FEleTheta[i] - theta) > band then
        Continue;

      x := FEleR[i] - MidRadius;
      y := FSn[i];

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

    // Midpoint-rule integration over the ring depth: every element in
    // the band stands for one equally deep slice, so the plain mean is
    // the integral divided by the ring thickness.
    Thrust := BarrelDepth * RingThickness * SumSn / n;
    Moment := BarrelDepth * RingThickness * SumSnX / n;

    if Abs(Thrust) > 1e-9 then
      ecc := Moment / Thrust
    else
      ecc := 0;

    // The two end joints lie in the y = 0 plane, so their normal is
    // vertical and the thrust across them IS the vertical reaction at
    // that springing - which is what makes the equilibrium check below
    // possible without asking the engine for reactions it does not
    // expose under the penalty method.
    if (k = 0) or (k = NbBlocks) then
      EndThrust := EndThrust + Abs(Thrust);

    if Abs(ecc) <= RingThickness / 6 then
      Status := 'inside'
    else
    begin
      Status := 'OUTSIDE -> hinge';
      Inc(nOutside);
    end;

    WriteLn(Format('  %5d  %6.1f  %10.2f  %7.3f  %10.3f  %10.3f   %s',
      [k, 180.0 * k / NbBlocks, Thrust / 1000, ecc / RingThickness,
       MinSn / 1e6, MaxSn / 1e6, Status]));

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

  // Half an element of ring sits below the plane the band actually
  // samples, at each springing - weight the check cannot see. The rest
  // of the gap is discretisation; both halve when the mesh is halved.
  Sliver := 2 * Density * Abs(GravityAccel) * BarrelDepth * RingThickness *
            0.5 * ((Pi / NbBlocks) / NbAlongBlock) * MidRadius;

  WriteLn('  A check on the solve, not an identity: the band is sampled half an');
  WriteLn(Format('  element above the springing face, missing %.1f%% of the ring''s own',
    [100 * Sliver / (FSelfWeight + FAppliedLoad)]));
  WriteLn('  weight, and element stresses are centre values. Both shrink with the mesh.');

end;

{ A gmsh script rather than the raw .pos: it opens the .pos, animates the
  deformed shape from the vector view, then finishes on the hoop-stress
  plot, which is the result this example is actually about. The scalar
  views are drawn on the undeformed mesh, so they have to be hidden while
  the deformation animates, or they sit on top of it and nothing appears
  to move. }
procedure TArchModel.WriteScript(const FileName : String);
var

  F : TextFile;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, '// Generated by ArchEx1 - do not edit, it is rewritten on every run.');
    WriteLn(F);
    WriteLn(F, 'Include "archex1.pos";');
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

  WriteLn('ArchEx1 - masonry arch, load case ', FLoadCase);
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
