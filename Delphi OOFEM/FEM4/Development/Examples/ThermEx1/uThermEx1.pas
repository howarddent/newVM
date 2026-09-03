unit uThermEx1;

{ ThermEx1 - core temperature of an anaesthetised adult losing heat to a
  cold theatre. Conduction only.

  A 75 kg adult at 5% body fat, generating heat at rest and losing it
  from the skin into a 16 C theatre, modelled as a two-layer cylinder:
  lean body mass generating uniformly throughout, wrapped in a
  non-metabolic fat layer. The question it answers is how the CORE
  temperature moves over the course of a case.

  WHAT IS AND IS NOT IN THE MODEL

  In: conduction through lean tissue and fat, heat storage (the whole
  body's thermal mass), uniform metabolic generation, and surface losses
  by convection and radiation into still air at 16 C.

  Out, deliberately, for this first model: respiratory evaporative loss,
  cutaneous evaporation, and - importantly - BLOOD PERFUSION. The last
  one is not a detail. In a real anaesthetised patient the first hour is
  dominated by redistribution: vasodilation moves heat from core to
  periphery far faster than tissue conduction ever could. This model has
  no such mechanism, so it will understate how quickly the core falls
  early on, and its core-to-skin coupling is a conduction time constant
  of hours rather than the minutes perfusion would give. Treat the
  numbers as the conduction-only bound, not as a patient.

  THE EQUIVALENT CYLINDER

  A body is not a cylinder, and no single cylinder has both a human's
  volume and a human's surface area - real bodies have limbs, so their
  surface-to-volume ratio is much higher than a compact shape's. Since
  the surface area drives the loss and the volume drives the storage,
  both have to be right or the energy balance is wrong. So the cylinder
  is sized to reproduce BOTH:

    R = 2V/A,   L = V/(pi*R^2)

  giving 75.7 mm radius and 4.0 m length for this subject. The length is
  not anatomical and is not meant to be; what it buys is that the model
  stores exactly the right amount of heat and loses it through exactly
  the right area. The 75.7 mm radius is a fair mean tissue depth, closer
  to a limb's than a trunk's, which is the honest reading of a body whose
  area is mostly limbs. The ends are left adiabatic, so all the loss is
  through the lateral surface and the whole of the nominal body surface
  area is doing the work.

  VERIFICATION STATUS

  Verified, as of the element fixes described below.

  Global energy balance: case 1 holds the balanced state for two hours
  with the surface losing 83.7 W against 83.7 W generated and a
  first-law residual of 0.00 W. Case 2's residual runs 0.3 to 1.2 W
  against total flows of 170 to 270 W, shrinking as the transient
  settles - that remainder is the backward difference used for the
  stored-energy term and the one-step lag in the radiation
  linearisation, both of which shrink with the time step.

  Radial gradient: the balanced state now settles at a core of 37.02 C
  against the 37.00 C the balance was designed around, with the lean
  surface at 33.69 C and the skin at 33.22 C - all three matching the
  closed forms q*R^2/(4k) and Q*ln(r2/r1)/(2*pi*k*L) to the second
  decimal, the remaining 0.02 K being ordinary discretisation.

  It did not always. This model originally reported a lean drop of
  4.44 K against an exact 3.33 K, mesh-converged, and a case 2 energy
  residual of 30 to 70 W. Both traced to two defects in the framework's
  3D elements, found by ThermSlab (Examples/ThermSlab) and fixed:
  TBrick_H8V1's shape-function derivatives were written for a
  lexicographically ordered hexahedron while gmsh writes the cyclic
  order, and TBrick_W6V1's six-point integration rule carried weights
  whose product came to 3/4 of the reference volume, with two of its
  triangle points at 1/3 instead of 2/3. Run ThermSlab to confirm they
  are still right.

  UNITS

  Everything is SI, and every temperature is in KELVIN. That is not
  optional: the radiation boundary condition evaluates T^4 directly and
  the framework applies no Celsius offset anywhere, so a model written in
  Celsius would silently compute the wrong radiative flux. Only the
  report converts back to Celsius.

  THE TWO CASES

  Both start from the same physiological steady state: a static solve
  with the skin coefficient set so the body is exactly in balance with a
  37 C core - which is what "the skin initially emits as much heat as is
  being generated" means once you work out what it implies. That
  coefficient comes out at about 2.6 W/m2K, i.e. a draped patient; bare
  skin at 16 C would lose over three times the metabolic output and
  could never be in balance at 37 C.

    1  draped - the balanced state is simply held. Nothing should move,
       which makes this the model's own check on itself.
    2  exposed - at t = 0 the drapes come off: the coefficient drops to
       bare-skin natural convection and radiation is switched on. This
       is the tracking run. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math, newVM, newVMsparse,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.ThermalEngine,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh;

const

  (******************** THE SUBJECT ********************)

  BodyMass = 75.0;          // kg
  FatFraction = 0.05;       // of body mass
  BodySurfaceArea = 1.903;  // m2, DuBois for 75 kg / 1.75 m

  VO2 = 250.0;              // mL/min
  RQ = 0.8;                 // respiratory quotient

  CoreSetPointC = 37.0;     // the core the balanced start is built around

  (******************** TISSUE ********************)

  LeanDensity = 1050.0;     // kg/m3
  LeanCp = 3600.0;          // J/kgK
  LeanK = 0.50;             // W/mK

  FatDensity = 900.0;
  FatCp = 2300.0;
  FatK = 0.21;

  (******************** ENVIRONMENT ********************)

  AmbientC = 16.0;          // theatre air and surrounding surfaces
  SkinEmissivity = 0.98;      // bare skin in the far infrared
  BareConvection = 3.0;     // W/m2K, natural convection over a supine body

  (******************** MESH ********************)

  // Circumferential divisions per quadrant, so 4x this around. At 12 the
  // polygon under-states the true circle by 0.3% in area and 0.07% in
  // perimeter; the report uses the MESHED volume and area throughout, so
  // that discretisation never leaks into the energy balance.
  NbCircPerQuadrant = 12;

  NbFatRadial = 3;          // element layers through the 2.2 mm of fat
  NbAxial = 4;              // along the cylinder - nothing varies axially
  CoreMeshSize = 0.006;     // m, unstructured element size in the lean core

  (******************** TIME ********************)

  TimeStep = 60.0;          // s
  NbTimeSteps = 120;        // 2 hours
  ReportEvery = 10;         // console line every this many steps

  (******************** CASES ********************)

  CaseDraped = 1;
  CaseExposed = 2;

  (******************** POST-PROCESSING ********************)


type

  // A face of an element lying on the outer (skin) surface.
  RSkinFace = record

    Ele : Integer;
    FaceIdx : Integer;
    NbNodes : Integer;
    Node : Array[0..3] of Integer;
    Area : Double;

  end;

  TThermalModel = class(TObject)

  private

    FCase : Integer;

    FGmsh : TGmsh;
    FEngine : TThermalEngine;

    FRhoLean, FCpLean, FKLean : TExpressionList;
    FRhoFat, FCpFat, FKFat : TExpressionList;
    FHConv, FTinf, FEmiss : TExpressionList;
    FGenSource : Array of TExpressionList;

    // Geometry
    FROuter, FRLean, FLength, FFatThickness : Double;
    FRLeanMm : Double;
    FVolLean, FVolFat : Double;          // nominal, from mass and density
    FMeshVolLean, FMeshVolFat : Double;  // as actually meshed
    FMeshArea : Double;                  // as actually meshed

    FHeatOutput : Double;                // W, whole body
    FGenPerVolume : Double;              // W/m3 in the lean mass
    FHBalance : Double;                  // W/m2K that balances at the set point

    // Per element
    FEleVolume : TDoubleArray;
    FEleRegion : TDoubleArray;           // 1 lean, 2 fat

    // Per node
    FNodeCapacity : TDoubleArray;        // J/K lumped to the node
    FNodeR : TDoubleArray;               // radius from the axis

    FSkin : Array of RSkinFace;
    FNbSkin : Integer;

    FCoreNode : Integer;

    // History
    FHistT, FHistCore, FHistSkin, FHistLoss, FHistStore : TDoubleArray;
    FNbHist : Integer;

    FTInitial : TDoubleArray;
    FEnergyPrev : Double;
    FTimePrev : Double;

    FElapsed : Double;

    // Everything the run prints, kept so the plot window can show the
    // same text beside the graph rather than it living only in a
    // terminal that may not even be visible.
    FReport : TStringList;

    procedure Say(const S : String);

    procedure SetupGeometry;

    procedure WriteGeoFile(const FileName : String);
    procedure BuildMesh;
    procedure CalcElementGeometry;
    procedure BuildModel;

    function TotalEnergy : Double;
    function SurfaceLoss(UseRadiation : Boolean) : Double;
    function MeanSkinTemperature : Double;

    procedure Expose;

    procedure ReportSetup;
    procedure ReportHistory;
    procedure ReportProfile;

    procedure WriteResults(const CsvName : String);

  public

    constructor Create(ACase : Integer);
    destructor Destroy; override;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure PostProcess;

    procedure GetRadialProfiles(out R, T0, TEnd : TVMobj);

    // For the plot window: where the fat starts, in mm.
    property LeanRadiusMm : Double read FRLeanMm;
    property CaseNumber : Integer read FCase;

    // The run's console report, verbatim.
    property Report : TStringList read FReport;

    procedure Run;

  end;

implementation

const

  DataDir = '..' + PathDelim + 'Data' + PathDelim;

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  GmshExecutable = 'gmsh';
{$ENDIF}

  GeoFile = DataDir + 'thermex1.geo';
  MshFile = DataDir + 'thermex1.msh';
  CsvFile = DataDir + 'thermex1.csv';

  Kelvin = 273.15;
  Sigma = 5.6704E-8;        // Stefan-Boltzmann, as the elements use

  GeoTol = 1.0E-6;

  // Local face node numbering, copied from the element classes - see
  // CXS.FEMLAP.Brick_H8V1.pas and CXS.FEMLAP.Brick_W6V1.pas, where the
  // face tables are built. AddFaceConvection and AddFaceRadiation take
  // an index into these.
  HexFace : Array[0..5, 0..3] of Integer =
    ((0,1,2,3), (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7));

  PrismFace : Array[0..4, 0..3] of Integer =
    ((0,1,2,0), (3,4,5,0), (0,1,4,3), (1,2,5,4), (2,0,3,5));

  PrismFaceNodes : Array[0..4] of Integer = (3, 3, 4, 4, 4);

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

{ TThermalModel }

constructor TThermalModel.Create(ACase : Integer);
begin

  FCase := ACase;

  FReport := TStringList.Create;

  FGmsh := TGmsh.Create;

  FCoreNode := -1;

  SetupGeometry;

end;

destructor TThermalModel.Destroy;
var
  i : Integer;
begin

  FReport.Free;

  FEngine.Free;

  FRhoLean.Free;
  FCpLean.Free;
  FKLean.Free;
  FRhoFat.Free;
  FCpFat.Free;
  FKFat.Free;
  FHConv.Free;
  FTinf.Free;
  FEmiss.Free;

  for i := 0 to Length(FGenSource) - 1 do
    FGenSource[i].Free;

  FGmsh.Free;

  inherited Destroy;

end;

{ Everything the model prints goes through here, so the plot window can
  show the same report beside the graph. }
procedure TThermalModel.Say(const S : String);
begin

  WriteLn(S);

  FReport.Add(S);

end;

function TThermalModel.Constant(NodeId, ElementId : Integer) : Double;
begin

  Result := 0;

end;

{ The subject's heat output, the equivalent cylinder that carries it, and
  the skin coefficient that puts the whole thing in balance at the core
  set point. All of it derived rather than tabulated, so changing the
  subject changes the model consistently. }
procedure TThermalModel.SetupGeometry;
var

  CalEquiv, MassLean, MassFat, V, qFlux, dTLean, dTFat, TSkin : Double;

begin

  // Caloric equivalent of oxygen, linear in RQ between the fat and
  // carbohydrate end points (4.686 kcal/L at RQ 0.707, 5.047 at 1.0).
  // At RQ 0.8 this gives 4.80 kcal/L, the standard table value.
  CalEquiv := 4.686 + (RQ - 0.707) * 1.232;

  FHeatOutput := (VO2 / 1000) * CalEquiv * 4184 / 60;

  MassFat := BodyMass * FatFraction;
  MassLean := BodyMass - MassFat;

  FVolLean := MassLean / LeanDensity;
  FVolFat := MassFat / FatDensity;

  V := FVolLean + FVolFat;

  // The equivalent cylinder: match the body's volume AND its surface
  // area, with the ends adiabatic so the whole area is lateral.
  FROuter := 2 * V / BodySurfaceArea;
  FLength := V / (Pi * FROuter * FROuter);

  FRLean := Sqrt(FVolLean / (Pi * FLength));

  FFatThickness := FROuter - FRLean;

  FRLeanMm := FRLean * 1000;

  FGenPerVolume := FHeatOutput / FVolLean;

  // What surface coefficient balances generation against loss with the
  // core at the set point? Work inwards from the skin: a cylinder with
  // uniform generation drops q*R^2/(4k) from axis to lean surface, and
  // the fat adds a plane-wall drop on top.
  qFlux := FHeatOutput / BodySurfaceArea;

  dTLean := FGenPerVolume * FRLean * FRLean / (4 * LeanK);
  dTFat := qFlux * FFatThickness / FatK;

  TSkin := (CoreSetPointC + Kelvin) - dTLean - dTFat;

  FHBalance := qFlux / (TSkin - (AmbientC + Kelvin));

end;

(*******************************************************************
  Geometry: a disc of lean tissue inside an annulus of fat, extruded
  along the axis.

  The lean core is meshed unstructured (triangles, hence prisms once
  extruded) because nothing about it needs structure - it is one
  material with a smooth field. The fat annulus is meshed structured
  instead, as four transfinite quadrants recombined into quads, hence
  hexahedra: at 2.2 mm thick carrying the entire temperature drop to the
  skin, it needs its element layers placed deliberately rather than
  left to an unstructured mesher, which would either miss it or flood
  the whole model with tiny elements.

    point   1               axis
    point   2+q, 6+q        the two circles at 0, 90, 180, 270 degrees
    line    1+q, 5+q        inner and outer quadrant arcs
    line    9+q             radial lines joining them
    surface 21              lean disc
    surface 40+q            fat quadrants
    volume  physical 1      lean, physical 2 fat
********************************************************************)
procedure TThermalModel.WriteGeoFile(const FileName : String);
var

  F : TextFile;

  q, n : Integer;

  a : Double;

  Inner, Outer, Radial, FatVols : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, 'Mesh.MshFileVersion=1;');

    // gmsh grows the interior mesh size from the boundary by default,
    // which here means the transfinite arcs would dictate the core mesh
    // and CoreMeshSize would do nothing at all.
    WriteLn(F, 'Mesh.MeshSizeExtendFromBoundary = 0;');
    WriteLn(F, 'Mesh.MeshSizeMax = ' + Num(CoreMeshSize) + ';');

    WriteLn(F, 'cl = ' + Num(CoreMeshSize) + ';');

    WriteLn(F, 'Point(1) = {0,0,0,cl};');

    for q := 0 to 3 do
    begin

      a := q * Pi / 2;

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [2 + q, Num(FRLean * Cos(a)), Num(FRLean * Sin(a))]));

      WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
        [6 + q, Num(FROuter * Cos(a)), Num(FROuter * Sin(a))]));

    end;

    Inner := '';
    Outer := '';
    Radial := '';

    for q := 0 to 3 do
    begin

      n := (q + 1) mod 4;

      WriteLn(F, Format('Circle(%d) = {%d,1,%d};', [1 + q, 2 + q, 2 + n]));
      WriteLn(F, Format('Circle(%d) = {%d,1,%d};', [5 + q, 6 + q, 6 + n]));
      WriteLn(F, Format('Line(%d) = {%d,%d};', [9 + q, 2 + q, 6 + q]));

      if q > 0 then
      begin
        Inner := Inner + ',';
        Outer := Outer + ',';
        Radial := Radial + ',';
      end;

      Inner := Inner + IntToStr(1 + q);
      Outer := Outer + IntToStr(5 + q);
      Radial := Radial + IntToStr(9 + q);

    end;

    WriteLn(F, Format('Transfinite Line {%s,%s} = %d;',
      [Inner, Outer, NbCircPerQuadrant + 1]));

    WriteLn(F, Format('Transfinite Line {%s} = %d;', [Radial, NbFatRadial + 1]));

    WriteLn(F, Format('Line Loop(20) = {%s};', [Inner]));
    WriteLn(F, 'Plane Surface(21) = {20};');

    for q := 0 to 3 do
    begin

      n := (q + 1) mod 4;

      WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
        [30 + q, 9 + q, 5 + q, 9 + n, 1 + q]));

      WriteLn(F, Format('Plane Surface(%d) = {%d};', [40 + q, 30 + q]));

      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [40 + q, 2 + q, 6 + q, 6 + n, 2 + n]));

      WriteLn(F, Format('Recombine Surface {%d};', [40 + q]));

    end;

    // Extruded one surface at a time so each volume id can be captured
    // for its physical group; they still mesh conformally, because the
    // arcs they share are meshed once.
    WriteLn(F, Format('lean[] = Extrude {0,0,%s} { Surface{21}; Layers{%d}; Recombine; };',
      [Num(FLength), NbAxial]));

    WriteLn(F, 'Physical Volume(1) = {lean[1]};');

    FatVols := '';

    for q := 0 to 3 do
    begin

      WriteLn(F, Format('fat%d[] = Extrude {0,0,%s} { Surface{%d}; Layers{%d}; Recombine; };',
        [q, Num(FLength), 40 + q, NbAxial]));

      if q > 0 then
        FatVols := FatVols + ',';

      FatVols := FatVols + Format('fat%d[1]', [q]);

    end;

    WriteLn(F, Format('Physical Volume(2) = {%s};', [FatVols]));

  finally

    CloseFile(F);

  end;

end;

procedure TThermalModel.BuildMesh;
var

  ExitCode : Cardinal;

begin

  Say('Meshing the cylinder with gmsh...');

  if not Sto_ShellExecute(GmshExecutable, [GeoFile, '-3'], ExitCode, 120000, True) then
    raise Exception.Create('Could not run gmsh (' + GmshExecutable +
      '). Install gmsh, or edit GmshExecutable in uThermEx1.pas.');

  if ExitCode <> 0 then
    raise Exception.Create('gmsh failed with exit code ' + IntToStr(ExitCode));

  if not FileExists(MshFile) then
    raise Exception.Create('gmsh produced no mesh file (' + MshFile + ')');

  FGmsh.OpenFile(MshFile);
  FGmsh.ReadMesh;
  FGmsh.Close;

  Say(Format('  %d nodes, %d elements', [FGmsh.NbNodes, FGmsh.NbElements]));

end;

{ Element volumes, the heat capacity lumped to each node, and the list of
  faces lying on the skin.

  Both element types here are straight extrusions - a prism from a
  triangle, a hexahedron from a quadrilateral - so a volume is just its
  base area times the extrusion height, exactly. }
procedure TThermalModel.CalcElementGeometry;
var

  i, j, f, n, nb, g : Integer;

  Base, dz, x0, y0, x1, y1, a2 : Double;

  ax, ay, az, bx, by, bz, cx, cy, cz : Double;

  OnSkin : Boolean;

  Nd : Array[0..7] of Integer;

begin

  SetLength(FEleVolume, FGmsh.NbElements);
  SetLength(FEleRegion, FGmsh.NbElements);
  SetLength(FNodeCapacity, FGmsh.NbNodes);
  SetLength(FNodeR, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin
    FNodeCapacity[i] := 0;
    FNodeR[i] := Sqrt(Sqr(FGmsh.CoordX[i]) + Sqr(FGmsh.CoordY[i]));
  end;

  FMeshVolLean := 0;
  FMeshVolFat := 0;
  FMeshArea := 0;

  FNbSkin := 0;
  SetLength(FSkin, FGmsh.NbElements);

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] = GMSH_HEXA then
      nb := 8
    else if FGmsh.ElementType[i] = GMSH_PRISM then
      nb := 6
    else
      raise Exception.Create('Unexpected element type ' +
        IntToStr(FGmsh.ElementType[i]) + ' - this model meshes only ' +
        'hexahedra (fat) and prisms (lean).');

    for j := 0 to nb - 1 do
      Nd[j] := FGmsh.ElementNode[i, j];

    // Base area, in the z = const plane, by the shoelace formula.
    a2 := 0;
    n := nb div 2;

    for j := 0 to n - 1 do
    begin

      x0 := FGmsh.CoordX[Nd[j]];
      y0 := FGmsh.CoordY[Nd[j]];
      x1 := FGmsh.CoordX[Nd[(j + 1) mod n]];
      y1 := FGmsh.CoordY[Nd[(j + 1) mod n]];

      a2 := a2 + (x0 * y1 - x1 * y0);

    end;

    Base := Abs(a2) * 0.5;

    dz := Abs(FGmsh.CoordZ[Nd[n]] - FGmsh.CoordZ[Nd[0]]);

    FEleVolume[i] := Base * dz;

    g := FGmsh.ElementPhysicalRegion[i];

    if (g < 1) or (g > 2) then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in physical ' +
        'region ' + IntToStr(g) + ', which is neither lean (1) nor fat (2).');

    FEleRegion[i] := g;

    if g = 1 then
    begin
      FMeshVolLean := FMeshVolLean + FEleVolume[i];
      for j := 0 to nb - 1 do
        FNodeCapacity[Nd[j]] := FNodeCapacity[Nd[j]] +
          LeanDensity * LeanCp * FEleVolume[i] / nb;
    end
    else
    begin
      FMeshVolFat := FMeshVolFat + FEleVolume[i];
      for j := 0 to nb - 1 do
        FNodeCapacity[Nd[j]] := FNodeCapacity[Nd[j]] +
          FatDensity * FatCp * FEleVolume[i] / nb;
    end;

    (******************** SKIN FACES ********************)

    // Only the fat carries skin, and only its outward face: every node
    // of the face sits on the outer radius.
    if g = 2 then
    begin

      for f := 0 to 5 do
      begin

        if (nb = 6) and (f > 4) then
          Break;

        if nb = 8 then
          n := 4
        else
          n := PrismFaceNodes[f];

        OnSkin := True;

        for j := 0 to n - 1 do
        begin

          if nb = 8 then
            FSkin[FNbSkin].Node[j] := Nd[HexFace[f, j]]
          else
            FSkin[FNbSkin].Node[j] := Nd[PrismFace[f, j]];

          if FNodeR[FSkin[FNbSkin].Node[j]] < FROuter - 1.0E-5 then
            OnSkin := False;

        end;

        if not OnSkin then
          Continue;

        // Area of the (planar) quadrilateral face, half the magnitude
        // of the cross product of its diagonals.
        ax := FGmsh.CoordX[FSkin[FNbSkin].Node[2]] - FGmsh.CoordX[FSkin[FNbSkin].Node[0]];
        ay := FGmsh.CoordY[FSkin[FNbSkin].Node[2]] - FGmsh.CoordY[FSkin[FNbSkin].Node[0]];
        az := FGmsh.CoordZ[FSkin[FNbSkin].Node[2]] - FGmsh.CoordZ[FSkin[FNbSkin].Node[0]];

        bx := FGmsh.CoordX[FSkin[FNbSkin].Node[3]] - FGmsh.CoordX[FSkin[FNbSkin].Node[1]];
        by := FGmsh.CoordY[FSkin[FNbSkin].Node[3]] - FGmsh.CoordY[FSkin[FNbSkin].Node[1]];
        bz := FGmsh.CoordZ[FSkin[FNbSkin].Node[3]] - FGmsh.CoordZ[FSkin[FNbSkin].Node[1]];

        cx := ay * bz - az * by;
        cy := az * bx - ax * bz;
        cz := ax * by - ay * bx;

        FSkin[FNbSkin].Ele := i;
        FSkin[FNbSkin].FaceIdx := f;
        FSkin[FNbSkin].NbNodes := n;
        FSkin[FNbSkin].Area := 0.5 * Sqrt(cx * cx + cy * cy + cz * cz);

        FMeshArea := FMeshArea + FSkin[FNbSkin].Area;

        Inc(FNbSkin);

        if FNbSkin >= Length(FSkin) then
          SetLength(FSkin, Length(FSkin) * 2);

      end;

    end;

  end;

  SetLength(FSkin, FNbSkin);

  // The core: on the axis, half way along.
  Base := MaxDouble;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    dz := Sqrt(Sqr(FNodeR[i]) + Sqr(FGmsh.CoordZ[i] - FLength / 2));

    if dz < Base then
    begin
      Base := dz;
      FCoreNode := i;
    end;

  end;

end;

procedure TThermalModel.BuildModel;
var

  i, j, nb, MatLean, MatFat, g : Integer;

  Node : Array[0..7] of Integer;

  NodeQ : TDoubleArray;

  EleType : NEleType;

  Q : Double;

begin

  FEngine := TThermalEngine.Create;

  FEngine.PenaltyMethod := True;
  FEngine.SolverType := soGMRES;

  (******************** MATERIALS ********************)

  FRhoLean := TExpressionList.Create;
  FRhoLean.AddExpression(0, 1000, Num(LeanDensity), 'T');
  FCpLean := TExpressionList.Create;
  FCpLean.AddExpression(0, 1000, Num(LeanCp), 'T');
  FKLean := TExpressionList.Create;
  FKLean.AddExpression(0, 1000, Num(LeanK), 'T');

  MatLean := FEngine.AddMaterial(Constant, FRhoLean, FCpLean, FKLean);

  FRhoFat := TExpressionList.Create;
  FRhoFat.AddExpression(0, 1000, Num(FatDensity), 'T');
  FCpFat := TExpressionList.Create;
  FCpFat.AddExpression(0, 1000, Num(FatCp), 'T');
  FKFat := TExpressionList.Create;
  FKFat.AddExpression(0, 1000, Num(FatK), 'T');

  MatFat := FEngine.AddMaterial(Constant, FRhoFat, FCpFat, FKFat);

  (******************** MESH ********************)

  FEngine.BeginAddMesh;

  for i := 0 to FGmsh.NbNodes - 1 do
    FEngine.AddNode(FGmsh.CoordX[i], FGmsh.CoordY[i], FGmsh.CoordZ[i]);

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] = GMSH_HEXA then
    begin
      nb := 8;
      EleType := elHexa;
    end
    else
    begin
      nb := 6;
      EleType := elPrism;
    end;

    for j := 0 to nb - 1 do
      Node[j] := FGmsh.ElementNode[i, j];

    if nb = 8 then
    begin
    end;

    if Round(FEleRegion[i]) = 1 then
      g := MatLean
    else
      g := MatFat;

    FEngine.AddElement(Node, nb, EleType, g);

  end;

  FEngine.EndAddMesh;

  (******************** RESTRAINTS ********************)

  // None: no temperature is prescribed anywhere. The convection at the
  // skin is what makes the system non-singular, and it is also the only
  // route out for the metabolic heat. Begin/End still have to be called
  // to size the engine's own bookkeeping.
  FEngine.BeginSetRestraints;
  FEngine.EndSetRestraints;

  (******************** METABOLIC GENERATION ********************)

  // There is no volumetric-source call on the engine, so the uniform
  // generation is lumped to nodes here - the same thing the structural
  // engine does internally for self weight. Scaled by the MESHED lean
  // volume, so the model receives exactly FHeatOutput watts however
  // coarsely the circle is polygonised.
  SetLength(NodeQ, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    NodeQ[i] := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if Round(FEleRegion[i]) <> 1 then
      Continue;

    if FGmsh.ElementType[i] = GMSH_HEXA then
      nb := 8
    else
      nb := 6;

    Q := FHeatOutput * (FEleVolume[i] / FMeshVolLean) / nb;

    for j := 0 to nb - 1 do
      NodeQ[FGmsh.ElementNode[i, j]] := NodeQ[FGmsh.ElementNode[i, j]] + Q;

  end;

  SetLength(FGenSource, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    FGenSource[i] := nil;

    if NodeQ[i] <= 0 then
      Continue;

    FGenSource[i] := TExpressionList.Create;
    FGenSource[i].AddExpression(-1E9, 1E9, Num(NodeQ[i]), 't');

    FEngine.AddNodeSource(i, Constant, FGenSource[i]);

  end;

  (******************** SURFACE ********************)

  FTinf := TExpressionList.Create;
  FTinf.AddExpression(-1E9, 1E9, Num(AmbientC + Kelvin), 't');

  FHConv := TExpressionList.Create;
  FHConv.AddExpression(-1E9, 1E9, Num(FHBalance), 't');

  FEmiss := TExpressionList.Create;
  FEmiss.AddExpression(-1E9, 1E9, Num(SkinEmissivity), 't');

  for i := 0 to FNbSkin - 1 do
    FEngine.AddFaceConvection(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FHConv, FTinf);

  (******************** INITIAL CONDITION ********************)

  FEngine.SetInitialTemperature(CoreSetPointC + Kelvin);

end;

function TThermalModel.TotalEnergy : Double;
var
  i : Integer;
begin

  Result := 0;

  for i := 0 to FEngine.NbNodes - 1 do
    Result := Result + FNodeCapacity[i] * FEngine.Temperature[i];

end;

function TThermalModel.SurfaceLoss(UseRadiation : Boolean) : Double;
var

  i, j : Integer;

  Tf, Tinf, h : Double;

begin

  Result := 0;

  Tinf := AmbientC + Kelvin;
  h := FHConv.GetValue(0);

  for i := 0 to FNbSkin - 1 do
  begin

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    Result := Result + h * (Tf - Tinf) * FSkin[i].Area;

    if UseRadiation then
      Result := Result + SkinEmissivity * Sigma *
                (Tf * Tf * Tf * Tf - Tinf * Tinf * Tinf * Tinf) * FSkin[i].Area;

  end;

end;

function TThermalModel.MeanSkinTemperature : Double;
var

  i, j : Integer;

  Tf, A : Double;

begin

  Result := 0;
  A := 0;

  for i := 0 to FNbSkin - 1 do
  begin

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    Result := Result + Tf * FSkin[i].Area;
    A := A + FSkin[i].Area;

  end;

  if A > 0 then
    Result := Result / A;

end;

{ Take the drapes off: the skin coefficient drops to bare-skin natural
  convection, and radiation - which the drapes were standing in for -
  becomes an explicit boundary condition of its own. The expression
  objects are the ones already handed to the engine, so rewriting them
  is enough; the assembly re-reads them every step. }
procedure TThermalModel.Expose;
var
  i : Integer;
begin

  FHConv.Clear;
  FHConv.AddExpression(-1E9, 1E9, Num(BareConvection), 't');

  for i := 0 to FNbSkin - 1 do
    FEngine.AddFaceRadiation(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FEmiss, FTinf);

end;

procedure TThermalModel.PostProcess;
var

  E, dt, Now_ : Double;

begin

  Now_ := FEngine.Time;

  dt := Now_ - FTimePrev;

  E := TotalEnergy;

  if FNbHist >= Length(FHistT) then
  begin
    SetLength(FHistT, Length(FHistT) + 256);
    SetLength(FHistCore, Length(FHistT));
    SetLength(FHistSkin, Length(FHistT));
    SetLength(FHistLoss, Length(FHistT));
    SetLength(FHistStore, Length(FHistT));
  end;

  FHistT[FNbHist] := Now_;
  FHistCore[FNbHist] := FEngine.Temperature[FCoreNode] - Kelvin;
  FHistSkin[FNbHist] := MeanSkinTemperature - Kelvin;
  FHistLoss[FNbHist] := SurfaceLoss(FCase = CaseExposed);

  if dt > 0 then
    FHistStore[FNbHist] := (E - FEnergyPrev) / dt
  else
    FHistStore[FNbHist] := 0;

  Inc(FNbHist);

  FEnergyPrev := E;
  FTimePrev := Now_;

end;

procedure TThermalModel.ReportSetup;
begin

  Say('');
  Say('================ SUBJECT AND MODEL ================');
  Say(Format('  Body mass / fat          : %8.1f kg / %.2f kg (%.0f%%)',
    [BodyMass, BodyMass * FatFraction, FatFraction * 100]));
  Say(Format('  VO2 / RQ                 : %8.0f mL/min at RQ %.2f', [VO2, RQ]));
  Say(Format('  Metabolic heat output    : %8.1f W', [FHeatOutput]));
  Say(Format('  Generation in lean mass  : %8.0f W/m3', [FGenPerVolume]));
  Say('');
  Say(Format('  Equivalent cylinder      : R %6.1f mm, length %.2f m',
    [FROuter * 1000, FLength]));
  Say(Format('  Fat layer                : %8.2f mm', [FFatThickness * 1000]));
  Say(Format('  Volume  nominal / meshed : %8.2f L / %.2f L',
    [(FVolLean + FVolFat) * 1000, (FMeshVolLean + FMeshVolFat) * 1000]));
  Say(Format('  Surface nominal / meshed : %8.3f m2 / %.3f m2',
    [BodySurfaceArea, FMeshArea]));
  Say(Format('  Heat capacity            : %8.0f kJ/K',
    [(BodyMass - BodyMass * FatFraction) * LeanCp / 1000 +
     BodyMass * FatFraction * FatCp / 1000]));
  Say('');
  Say(Format('  Ambient                  : %8.1f C', [AmbientC]));
  Say(Format('  Draped coefficient       : %8.2f W/m2K  (balances at a %.0f C core)',
    [FHBalance, CoreSetPointC]));

  if FCase = CaseExposed then
    Say(Format('  Exposed at t=0           : %8.2f W/m2K convection + radiation e=%.2f',
      [BareConvection, SkinEmissivity]))
  else
    Say('  Exposed at t=0           :      no - the draped state is held');

  Say(Format('  Mesh                     : %8d nodes, %d elements, %d skin faces',
    [FGmsh.NbNodes, FGmsh.NbElements, FNbSkin]));

end;

procedure TThermalModel.ReportHistory;
var

  i : Integer;

  Gen, Bal : Double;

begin

  Gen := FHeatOutput;

  Say('');
  Say('================ CORE TEMPERATURE ================');
  Say('    time    core    skin     generated       lost      stored    balance');
  Say('   (min)     (C)     (C)           (W)        (W)         (W)        (W)');

  for i := 0 to FNbHist - 1 do
  begin

    if (i mod ReportEvery <> 0) and (i <> FNbHist - 1) then
      Continue;

    Bal := Gen - FHistLoss[i] - FHistStore[i];

    Say(Format('  %6.1f  %6.2f  %6.2f  %12.1f %10.1f  %10.1f %10.2f',
      [FHistT[i] / 60, FHistCore[i], FHistSkin[i], Gen,
       FHistLoss[i], FHistStore[i], Bal]));

  end;

  Say('');

  if FNbHist > 0 then
  begin

    Say(Format('  Core %.2f C -> %.2f C over %.0f min  (%.2f C, %.2f C/h)',
      [FHistCore[0], FHistCore[FNbHist - 1], FHistT[FNbHist - 1] / 60,
       FHistCore[FNbHist - 1] - FHistCore[0],
       (FHistCore[FNbHist - 1] - FHistCore[0]) / (FHistT[FNbHist - 1] / 3600)]));

    Say(Format('  Skin %.2f C -> %.2f C', [FHistSkin[0], FHistSkin[FNbHist - 1]]));

  end;

  Say('');
  Say('  The balance column is generation minus surface loss minus the rate of');
  Say('  change of stored energy, and should be zero: it is the model checking');
  Say('  its own first law, the way the arch examples check thrust against');
  Say('  weight. Stored is computed from the nodal temperatures and the lumped');
  Say('  heat capacities, loss from the skin faces, so the two are independent.');

end;

{ The radial temperature profile, at t=0 and as it now stands.

  The model is radially symmetric by construction - uniform generation,
  a uniform lateral boundary condition, adiabatic ends - so the whole
  three-dimensional field collapses without loss to a single curve
  against radius, which is why this replaces a field plot.

  Nodes are grouped by radius rather than plotted raw. The fat's
  structured layers sit at four exact radii and must stay distinct,
  since the ring's steepest gradient is across them; the unstructured
  lean core scatters its nodes over every radius and needs averaging or
  the curve is a band rather than a line. Grouping to a tolerance well
  under a fat layer does both: the four fat radii stay separate, and the
  many lean nodes at a given radius average to one point. Any residual
  spread within a group is the model's own departure from radial
  symmetry, which is mesh noise only. }
procedure TThermalModel.GetRadialProfiles(out R, T0, TEnd : TVMobj);
const
  // Well under the 0.74 mm fat layer spacing, so those stay resolved.
  GroupTol = 0.0002;
var

  i, j, n, m : Integer;

  Idx : Array of Integer;

  tmp : Integer;

  rSum, t0Sum, tESum : Double;

  Rv, T0v, TEv : TDoubleArray;

begin

  n := FEngine.NbNodes;

  // Index sort by radius - insertion sort over an index array, which is
  // ample for a few thousand nodes and keeps the node data untouched.
  SetLength(Idx, n);

  for i := 0 to n - 1 do
    Idx[i] := i;

  for i := 1 to n - 1 do
  begin

    tmp := Idx[i];
    j := i - 1;

    while (j >= 0) and (FNodeR[Idx[j]] > FNodeR[tmp]) do
    begin
      Idx[j + 1] := Idx[j];
      Dec(j);
    end;

    Idx[j + 1] := tmp;

  end;

  SetLength(Rv, n);
  SetLength(T0v, n);
  SetLength(TEv, n);

  m := 0;
  i := 0;

  while i < n do
  begin

    j := i;
    rSum := 0;
    t0Sum := 0;
    tESum := 0;

    // Everything within GroupTol of where this group started.
    while (j < n) and (FNodeR[Idx[j]] - FNodeR[Idx[i]] <= GroupTol) do
    begin

      rSum := rSum + FNodeR[Idx[j]];
      t0Sum := t0Sum + FTInitial[Idx[j]];
      tESum := tESum + FEngine.Temperature[Idx[j]];

      Inc(j);

    end;

    Rv[m] := 1000 * rSum / (j - i);       // mm, for a readable axis
    T0v[m] := t0Sum / (j - i) - Kelvin;   // C
    TEv[m] := tESum / (j - i) - Kelvin;

    Inc(m);

    i := j;

  end;

  R := TVMobj.Create(1, m);
  T0 := TVMobj.Create(1, m);
  TEnd := TVMobj.Create(1, m);

  for i := 0 to m - 1 do
  begin
    R[0, i] := Rv[i];
    T0[0, i] := T0v[i];
    TEnd[0, i] := TEv[i];
  end;

end;

procedure TThermalModel.ReportProfile;
var

  R, T0, TEnd : TVMobj;

begin

  GetRadialProfiles(R, T0, TEnd);

  Say('');
  Say(Format('  Radial profile: %d points from the axis to the skin', [R.Cols]));
  Say(Format('    t=0   axis %.2f C -> lean surface %.2f C -> skin %.2f C',
    [T0[0, 0], T0[0, R.Cols - NbFatRadial - 1], T0[0, R.Cols - 1]]));
  Say(Format('    end   axis %.2f C -> lean surface %.2f C -> skin %.2f C',
    [TEnd[0, 0], TEnd[0, R.Cols - NbFatRadial - 1], TEnd[0, R.Cols - 1]]));

end;

procedure TThermalModel.WriteResults(const CsvName : String);
var

  F : TextFile;

  i : Integer;

begin

  AssignFile(F, CsvName);
  SafeReWriteText(F);

  try

    WriteLn(F, 'time_s,time_min,core_C,skin_C,generated_W,lost_W,stored_W,balance_W');

    for i := 0 to FNbHist - 1 do
      WriteLn(F, Format('%.1f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f',
        [FHistT[i], FHistT[i] / 60, FHistCore[i], FHistSkin[i],
         FHeatOutput, FHistLoss[i], FHistStore[i],
         FHeatOutput - FHistLoss[i] - FHistStore[i]], DotFS));

  finally

    CloseFile(F);

  end;

end;

procedure TThermalModel.Run;
var

  Start : QWord;

  i : Integer;

begin

  Say('ThermEx1 - heat loss from an anaesthetised adult, case ' + IntToStr(FCase));
  Say('');

  WriteGeoFile(GeoFile);

  BuildMesh;

  CalcElementGeometry;

  BuildModel;

  ReportSetup;

  (******************** BALANCED STARTING STATE ********************)

  Say('');
  Say('Solving the draped steady state...');

  Start := GetTickCount64;

  FEngine.CalcTemperature(caStatic, False);

  Say(Format('  core %.2f C, skin %.2f C, loss %.1f W against %.1f W generated',
    [FEngine.Temperature[FCoreNode] - Kelvin, MeanSkinTemperature - Kelvin,
     SurfaceLoss(False), FHeatOutput]));

  SetLength(FTInitial, FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
    FTInitial[i] := FEngine.Temperature[i];

  (******************** TRANSIENT ********************)

  if FCase = CaseExposed then
    Expose;

  FEnergyPrev := TotalEnergy;
  FTimePrev := 0;
  FNbHist := 0;

  FEngine.Time := 0;
  FEngine.TimeInterval := TimeStep;
  FEngine.NbSteps := NbTimeSteps;
  FEngine.Tolerance := 1E-5;

  FEngine.SetEndPostIterationFunction(PostProcess);

  Say(Format('Running %d steps of %.0f s (%.1f h)...',
    [NbTimeSteps, TimeStep, NbTimeSteps * TimeStep / 3600]));

  FEngine.CalcTemperature(caTransient, True);

  FElapsed := GetTickCount64 - Start;

  ReportHistory;

  Say(Format('  Solve time: %.0f s', [FElapsed / 1000]));

  ReportProfile;

  WriteResults(CsvFile);

  Say('');
  Say('History written to ' + CsvFile);

end;

initialization

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DotFS.ThousandSeparator := #0;

end.
