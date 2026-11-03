unit uTorsoAbdomen;

{ The abdominal cavity of the Defibrillation torso, with a diaphragm
  dome and a pelvis, meshed in tetrahedra by gmsh, for the HFJV model.

  THE BODY

  Examples/Defibrillation's torso (TDefibModel.SetupGeometry, which
  sizes ThermEx1's trunk masses into an elliptical-cylinder abdomen
  under a truncated-cone thorax, and scales them with Height and Weight).
  Its coordinates are kept: x across the body (-x the patient's left),
  y up from the back, which lies on the table at y = 0, z along the body
  from the perineum. Supine, gravity is -y. The default 1.75 m, 70 kg
  man has a 323 x 233 mm abdomen 0.43 m long, with an 18 mm chest wall
  of muscle inside the core's ellipse running the length of the trunk.

  THE CAVITY

  Its boundary is the inner edge of that wall (TDefibModel.WallPoint at
  WallThickness), from the pelvic floor to the diaphragm, with:

    spine     the lumbar vertebrae and psoas as a ridge along the back
              midline, as far forward as the Defibrillation spine's
              front (SpineInset + SpineRadius) and SpineHalfWidth across,
              a raised cosine;
    pelvis    below the iliac crest the section narrows smoothly to the
              pelvic inlet at the brim and to the outlet at the pelvic
              floor (ellipses PelvisInlet, PelvisOutlet), moving back
              towards the sacrum as it goes; the floor is a shallow bowl;
    diaphragm a dome over the costal margin. Its rim, where it inserts,
              is Apposition above the lower edge of the rib cage; the
              dome rises from the rim to DomeRise above the trunk's flat
              Defibrillation diaphragm, as z = rim + (top - rim)(1 - r^p),
              r the fraction of the way out to the wall.

  The lower edge of the rib cage (the costal margin) is taken from the
  Defibrillation skeleton: at the front midline the bottom of the
  sternum (the xiphoid), at the sides the bottom of rib 10 (the last
  that reaches the front), behind the bottom of rib 12. Between them
  it follows a sharp inverted V, as the margin does.

  SURFACES

    1  anterior abdominal wall (moving): below the costal margin, above
       the pubis at the front and the iliac crest at the side, and round
       to the posterior axillary line;
    2  diaphragm (moving): above its rim;
    0  everything else, rigid: the back and loin, the band of lower rib
       cage between the costal margin and the diaphragm's insertion (the
       zone of apposition - in reality it moves with the rib cage), the
       bony pelvis and the pelvic floor.

  A moving node where its surface meets rigid is clamped, so the wall is
  held at the costal margin, pubis and loin, and the diaphragm at its
  insertion, by the rib band between them.

  MESHING

  The closed surface is written as a triangulated STL from these
  formulae (rings of points, from the pelvic floor up to the dome's
  apex), and gmsh reparametrises and remeshes it to MeshSize and fills it
  with tetrahedra (gmsh's own STL-remeshing workflow, its tutorial 13).
  The boundary faces are then classified from their centroids by the
  formulae, so surface edges staircase at element size. The landmarks
  below the costal margin are for the 1.75 m man and scale with height.

  WHAT IS LEFT OUT

  The liver, spleen and kidneys are not set apart from the bowel: the
  whole cavity is one fluid. The lower rib cage band is rigid. The dome
  is one dome, not a right one higher than the left. }

{$mode delphi}{$H+}

interface

uses SysUtils, Classes, Math, newVMsparse, uDefibModel,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.ShellExec, uAbdomenFluid;  // uAbdomenFluid last: its TVec3

const
  SurfRigid = 0;
  SurfWall = 1;
  SurfDiaphragm = 2;

type
  TTorsoAbdomen = class
  private
    FBody : TDefibModel;
    FScale : Double;          // height / 1.75 m
    FZx, FZr10, FZr12 : Double;
    function Smooth(e0, e1, x : Double) : Double;
    procedure Section(z : Double; out sx, sy, dy : Double);
  public
    // landmarks, m above the perineum (set by Setup)
    ZFloor, ZPubis, ZBrim, ZCrest, ZTop : Double;
    DomeRise, FloorDepth, DomePower : Double;
    CavA, CavB : Double;      // cavity half-width and half-depth in the abdomen
    MeshSize : Double;
    MeshDir : String;
    Log : TStrings;           // optional

    constructor Create(Height, Weight : Double);
    destructor Destroy; override;

    { Section parameter T (0 the patient's right side, pi/2 the front
      midline, -pi/2 the back) at height Z: the cavity's boundary point. }
    function WallAt(T, Z : Double) : TVec3;
    function CostalZ(T : Double) : Double;
    function RimZ(T : Double) : Double;
    function LowZ(T : Double) : Double;
    { the section parameter of a point, from its own section }
    function TOf(const P : TVec3) : Double;
    function Classify(const C, N : TVec3) : Integer;

    procedure WriteSTL(const FileName : String; NT, NBottom, NSide, NDome : Integer);
    { Writes the STL and .geo into MeshDir, runs gmsh unless the mesh is
      already there for these settings, and reads the tetrahedra. }
    procedure BuildMesh(out X, Y, Z : TDoubleArray; out Tets : TIntegerArray);
    property Body : TDefibModel read FBody;
  end;

implementation

const
  RefHeight_ = 1.75;
  {$IFDEF WINDOWS}
  GmshExe = 'c:\gmsh\gmsh.exe';
  {$ELSE}
  GmshExe = 'gmsh';
  {$ENDIF}
  // pelvis, 1.75 m man: half-axes (m) of the inlet and outlet, and how far
  // back of the abdomen's section centre each lies
  InletA = 0.066;  InletB = 0.058;  InletBack = 0.012;
  OutletA = 0.052; OutletB = 0.046; OutletBack = 0.022;
  SpineHalfWidth = 0.050;
  Apposition = 0.015;          // m, diaphragm insertion above the costal margin

function Num(v : Double) : String;
begin
  Result := FloatToStrF(v, ffGeneral, 9, 0, DefaultFormatSettings);
end;

constructor TTorsoAbdomen.Create(Height, Weight : Double);
var
  z0, z1 : Double;
  W : uDefibModel.TVec3;
begin
  inherited Create;
  FBody := TDefibModel.Create;
  FBody.Height := Height;
  FBody.Weight := Weight;
  FBody.SetupGeometry;
  FScale := Height / RefHeight_;
  ZFloor := 0.045 * FScale;
  ZPubis := 0.100 * FScale;
  ZBrim := 0.140 * FScale;
  ZCrest := 0.250 * FScale;
  FloorDepth := 0.015 * FScale;
  DomeRise := 0.065 * FScale;
  DomePower := 2.5;
  ZTop := (FBody.Len - FBody.ThoraxLen) + DomeRise;
  FZx := FBody.Len - SternumBottom;
  FBody.RibBand(9, z0, z1);  FZr10 := Min(z0, z1);
  FBody.RibBand(11, z0, z1); FZr12 := Min(z0, z1);
  W := FBody.WallPoint(0, WallThickness, 0.3);
  CavA := W.X;
  W := FBody.WallPoint(Pi / 2, WallThickness, 0.3);
  CavB := W.Y - FBody.Cy;
  MeshSize := 0.012;
  MeshDir := 'mesh' + PathDelim;
end;

destructor TTorsoAbdomen.Destroy;
begin
  FBody.Free;
  inherited Destroy;
end;

function TTorsoAbdomen.Smooth(e0, e1, x : Double) : Double;
var
  t : Double;
begin
  t := EnsureRange((x - e0) / (e1 - e0), 0, 1);
  Result := t * t * (3 - 2 * t);
end;

// scale of the section (x, y about its centre) and the centre's shift in y
procedure TTorsoAbdomen.Section(z : Double; out sx, sy, dy : Double);
var
  f : Double;
begin
  sx := 1; sy := 1; dy := 0;
  if z >= ZCrest then Exit;
  if z >= ZBrim then
  begin
    f := 1 - Smooth(ZBrim, ZCrest, z);   // 0 at the crest, 1 at the brim
    sx := 1 + f * (InletA * FScale / CavA - 1);
    sy := 1 + f * (InletB * FScale / CavB - 1);
    dy := -f * InletBack * FScale;
  end
  else
  begin
    f := 1 - Smooth(ZFloor, ZBrim, z);   // 0 at the brim, 1 at the floor
    sx := InletA / CavA * FScale + f * (OutletA - InletA) * FScale / CavA;
    sy := InletB / CavB * FScale + f * (OutletB - InletB) * FScale / CavB;
    dy := -(InletBack + f * (OutletBack - InletBack)) * FScale;
  end;
end;

function TTorsoAbdomen.WallAt(T, Z : Double) : TVec3;
var
  P : uDefibModel.TVec3;
  sx, sy, dy, yb, ybump, cy : Double;
begin
  // the wall's inner edge; above the abdomen the cone's
  P := FBody.WallPoint(T, WallThickness, Max(Z, 0));
  cy := FBody.Cy;
  // the spine's ridge along the back
  if P.Y < cy then
  begin
    // the back of the cavity at the midline
    yb := FBody.WallPoint(-Pi / 2, WallThickness, Max(Z, 0)).Y;
    if Abs(P.X) < SpineHalfWidth then
    begin
      ybump := yb + (SpineInset + SpineRadius - WallThickness) *
        0.5 * (1 + Cos(Pi * P.X / SpineHalfWidth));
      if P.Y < ybump then P.Y := ybump;
    end;
  end;
  Section(Z, sx, sy, dy);
  Result := Vec3(P.X * sx, cy + (P.Y - cy) * sy + dy, Z);
end;

function TTorsoAbdomen.CostalZ(T : Double) : Double;
var
  c : Double;
begin
  c := Sin(T);
  if c >= 0 then
    Result := FZr10 + (FZx - FZr10) * Power(c, 4)
  else
    Result := FZr10 + (FZr12 - FZr10) * 0.5 * (1 - Cos(Pi * Min(1, -2 * c)));
end;

function TTorsoAbdomen.RimZ(T : Double) : Double;
begin
  Result := CostalZ(T) + Apposition * FScale;
end;

function TTorsoAbdomen.LowZ(T : Double) : Double;
begin
  Result := ZCrest - (ZCrest - ZPubis) * Sqr(Max(0, Sin(T)));
end;

function TTorsoAbdomen.TOf(const P : TVec3) : Double;
var
  sx, sy, dy : Double;
begin
  Section(P.Z, sx, sy, dy);
  Result := ArcTan2((P.Y - FBody.Cy - dy) / (sy * CavB), P.X / (sx * CavA));
end;

function TTorsoAbdomen.Classify(const C, N : TVec3) : Integer;
var
  T : Double;
begin
  T := TOf(C);
  if C.Z >= RimZ(T) - 0.002 then
    Result := SurfDiaphragm
  else if (C.Z < CostalZ(T)) and (C.Z > LowZ(T)) and (Sin(T) > -0.4) then
    Result := SurfWall
  else
    Result := SurfRigid;
end;

procedure TTorsoAbdomen.WriteSTL(const FileName : String; NT, NBottom, NSide, NDome : Integer);
var
  Rings : array of array of TVec3;
  nr, i, j, k : Integer;
  T, r, s, zr, w : Double;
  C, Wp : TVec3;
  F : TextFile;
  Poles : array[0..1] of TVec3;

  procedure Facet(const A, B, D : TVec3);
  var
    n : TVec3;
    l : Double;
  begin
    n := Vec3((B.Y - A.Y) * (D.Z - A.Z) - (B.Z - A.Z) * (D.Y - A.Y),
              (B.Z - A.Z) * (D.X - A.X) - (B.X - A.X) * (D.Z - A.Z),
              (B.X - A.X) * (D.Y - A.Y) - (B.Y - A.Y) * (D.X - A.X));
    l := Sqrt(n.X * n.X + n.Y * n.Y + n.Z * n.Z);
    if l = 0 then Exit;
    WriteLn(F, ' facet normal ', Num(n.X / l), ' ', Num(n.Y / l), ' ', Num(n.Z / l));
    WriteLn(F, '  outer loop');
    WriteLn(F, '   vertex ', Num(A.X), ' ', Num(A.Y), ' ', Num(A.Z));
    WriteLn(F, '   vertex ', Num(B.X), ' ', Num(B.Y), ' ', Num(B.Z));
    WriteLn(F, '   vertex ', Num(D.X), ' ', Num(D.Y), ' ', Num(D.Z));
    WriteLn(F, '  endloop');
    WriteLn(F, ' endfacet');
  end;

  function SectionCentre(z : Double) : TVec3;
  var
    sx, sy, dy : Double;
  begin
    Section(z, sx, sy, dy);
    Result := Vec3(0, FBody.Cy + dy, z);
  end;

begin
  // rings from the pelvic floor (just above its pole) to the dome (just
  // below its apex); the poles are separate points
  nr := NBottom + NSide + 1 + NDome;
  SetLength(Rings, nr, NT);
  k := 0;
  // pelvic floor bowl: r from small to 1 at z = floor
  for i := 1 to NBottom do
  begin
    r := i / NBottom;
    for j := 0 to NT - 1 do
    begin
      T := 2 * Pi * j / NT;
      Wp := WallAt(T, ZFloor);
      C := SectionCentre(ZFloor);
      Rings[k, j] := Vec3(C.X + r * (Wp.X - C.X), C.Y + r * (Wp.Y - C.Y),
        ZFloor - FloorDepth * (1 - r * r));
    end;
    Inc(k);
  end;
  // sides: from the floor to the diaphragm's rim, following the rim
  for i := 1 to NSide + 1 do
  begin
    s := i / (NSide + 1);
    for j := 0 to NT - 1 do
    begin
      T := 2 * Pi * j / NT;
      zr := ZFloor + s * (RimZ(T) - ZFloor);
      Rings[k, j] := WallAt(T, zr);
    end;
    Inc(k);
  end;
  // the dome: r from 1 down to small
  for i := 1 to NDome do
  begin
    r := 1 - i / (NDome + 1);
    for j := 0 to NT - 1 do
    begin
      T := 2 * Pi * j / NT;
      zr := RimZ(T);
      Wp := WallAt(T, zr);
      C := SectionCentre(zr);
      w := 1 - Power(r, DomePower);
      Rings[k, j] := Vec3(C.X + r * (Wp.X - C.X), C.Y + r * (Wp.Y - C.Y),
        zr + (ZTop - zr) * w);
    end;
    Inc(k);
  end;
  Poles[0] := Vec3(0, SectionCentre(ZFloor).Y, ZFloor - FloorDepth);
  Poles[1] := Vec3(0, SectionCentre(ZTop).Y, ZTop);
  // the apex ring's centre: keep the pole above the mean of the last ring
  C := Vec3(0, 0, 0);
  for j := 0 to NT - 1 do
  begin
    C.X := C.X + Rings[nr - 1, j].X / NT;
    C.Y := C.Y + Rings[nr - 1, j].Y / NT;
  end;
  Poles[1].X := C.X; Poles[1].Y := C.Y;

  AssignFile(F, FileName);
  ReWrite(F);
  try
    WriteLn(F, 'solid abdomen');
    for j := 0 to NT - 1 do
      Facet(Poles[0], Rings[0, (j + 1) mod NT], Rings[0, j]);
    for i := 0 to nr - 2 do
      for j := 0 to NT - 1 do
      begin
        Facet(Rings[i, j], Rings[i, (j + 1) mod NT], Rings[i + 1, (j + 1) mod NT]);
        Facet(Rings[i, j], Rings[i + 1, (j + 1) mod NT], Rings[i + 1, j]);
      end;
    for j := 0 to NT - 1 do
      Facet(Rings[nr - 1, j], Rings[nr - 1, (j + 1) mod NT], Poles[1]);
    WriteLn(F, 'endsolid abdomen');
  finally
    CloseFile(F);
  end;
end;

procedure TTorsoAbdomen.BuildMesh(out X, Y, Z : TDoubleArray; out Tets : TIntegerArray);
var
  Tag, Stl, Geo, Msh : String;
  F : TextFile;
  G : TGmsh;
  ExitCode : Cardinal;
  i, j, n, nt : Integer;
  Map : TIntegerArray;
begin
  ForceDirectories(MeshDir);
  Tag := Format('abdomen_h%.0f_w%.0f_s%.0f', [100 * FBody.Height, FBody.Weight, 1000 * MeshSize]);
  Stl := MeshDir + Tag + '.stl';
  Geo := MeshDir + Tag + '.geo';
  Msh := MeshDir + Tag + '.msh';
  if not FileExists(Msh) then
  begin
    WriteSTL(Stl, 128, 6, 90, 18);
    AssignFile(F, Geo);
    ReWrite(F);
    try
      WriteLn(F, '// HFJV abdomen - written by uTorsoAbdomen');
      WriteLn(F, 'Mesh.MshFileVersion = 1;');
      WriteLn(F, 'Merge "', ExtractFileName(Stl), '";');
      // split the STL into smooth patches gmsh can reparametrise
      WriteLn(F, 'ClassifySurfaces{40 * Pi / 180, 1, 1, Pi};');
      WriteLn(F, 'CreateGeometry;');
      WriteLn(F, 'Surface Loop(1) = Surface{:};');
      WriteLn(F, 'Volume(1) = {1};');
      WriteLn(F, 'Physical Volume(1) = {1};');
      WriteLn(F, 'Mesh.MeshSizeMax = ', Num(MeshSize), ';');
      WriteLn(F, 'Mesh.MeshSizeMin = ', Num(MeshSize / 4), ';');
      WriteLn(F, 'Mesh.MeshSizeFromCurvature = 12;');
      WriteLn(F, 'Mesh.Optimize = 1;');
    finally
      CloseFile(F);
    end;
    if Log <> nil then Log.Add('Meshing the abdomen with gmsh...');
    if not Sto_ShellExecute(GmshExe, [Geo, '-3', '-o', Msh], ExitCode, 600000, True) then
      raise Exception.Create('Could not run gmsh (' + GmshExe + ').');
    if (ExitCode <> 0) or not FileExists(Msh) then
      raise Exception.CreateFmt('gmsh failed (exit code %d) - see %s', [ExitCode, Geo]);
  end;

  G := TGmsh.Create;
  try
    G.OpenFile(Msh);
    G.ReadMesh;
    G.Close;
    // tetrahedra only, and only the nodes they use
    SetLength(Map, G.NbNodes);
    for i := 0 to G.NbNodes - 1 do Map[i] := -1;
    nt := 0;
    SetLength(Tets, 4 * G.NbElements);
    for i := 0 to G.NbElements - 1 do
      if G.ElementType[i] = GMSH_TETRA then
      begin
        for j := 0 to 3 do Tets[4 * nt + j] := G.ElementNode[i, j];
        Inc(nt);
      end;
    SetLength(Tets, 4 * nt);
    n := 0;
    for i := 0 to 4 * nt - 1 do
      if Map[Tets[i]] < 0 then
      begin
        Map[Tets[i]] := n;
        Inc(n);
      end;
    SetLength(X, n); SetLength(Y, n); SetLength(Z, n);
    for i := 0 to G.NbNodes - 1 do
      if Map[i] >= 0 then
      begin
        X[Map[i]] := G.CoordX[i];
        Y[Map[i]] := G.CoordY[i];
        Z[Map[i]] := G.CoordZ[i];
      end;
    for i := 0 to 4 * nt - 1 do
      Tets[i] := Map[Tets[i]];
  finally
    G.Free;
  end;
end;

end.
