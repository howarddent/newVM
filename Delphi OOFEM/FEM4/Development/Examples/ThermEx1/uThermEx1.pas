unit uThermEx1;

{ ThermEx1 - core temperature of an anaesthetised adult losing heat to a
  cold theatre. Four compartments, conduction and blood perfusion.

  A 75 kg adult at 5% body fat, generating heat at rest and losing it
  from the skin into a 16 C theatre. The question it answers is how the
  CORE temperature moves over the course of a case.

  THE COMPARTMENTS

  The body is four concentric compartments, innermost outward:

    core    the highly metabolising viscera - brain, heart, liver,
            kidneys, gut - lumped with the skeleton and everything else
            that is neither muscle, fat nor skin
    muscle  skeletal muscle, generating only its BASAL share here since
            this subject is not exercising; the share is what would rise,
            steeply, with exercise
    fat     non-metabolic, as specified
    skin    thin, barely metabolising, and thermally almost irrelevant
            while the model is conduction-only - it is here because
            perfusion is what makes it matter, and the compartment has
            to exist before the blood flow through it can

  Masses come to the 75 kg: 34.50 core, 33.75 muscle, 3.75 fat (the 5%),
  3.00 skin. Muscle at 45% and skin at 4% of body mass are ordinary
  figures for a lean adult, and the core is what is left.

  Generation is split by the organ-specific resting rates: brain 20% of
  basal, liver 21%, heart 9%, kidneys 8%, skeletal muscle 22%, the
  remainder 16% - which puts 74% in the core compartment, 23% in muscle
  and 3% in skin, with fat held at zero as specified. That is 62 W, 19 W
  and 3 W of the 83.7 W total. Note what the layers do to the
  volumetric rates: the core generates 1885 W/m3 and muscle only 599,
  so the compartments matter as much for WHERE the heat appears as for
  how it conducts.

  PERFUSION

  Blood carries heat between the compartments far faster than tissue
  conducts it, and that is the mechanism behind redistribution - the
  early core fall after induction, as a vasodilated periphery draws on
  a warm core. The model carries it as the Pennes term, a volumetric
  exchange in each compartment with blood arriving at the pool
  temperature, distributed by the resting shares of cardiac output:
  75% to the core compartment, 18% to muscle, 5% to skin, 2% to fat.

  The pool closes the loop. With no external source or sink of blood
  heat, a well-mixed pool sits at the FLOW-WEIGHTED MEAN tissue
  temperature, which makes the net perfusion heat identically zero -
  perfusion moves heat about and creates none. The report carries that
  net out and prints it, so the claim is checked rather than asserted.

  Cardiac output is a parameter, 0 to 10 L/min, on a slider in the plot
  window. Zero is the conduction-only model this began as. What it shows
  is strongly non-linear: at 0 the core falls 0.6 C/h, at 5 it falls
  2.7, and at 10 only 2.9 - once blood has flattened the internal
  resistance, more of it barely matters, because the bottleneck has
  moved to the skin surface.

  WHAT IS AND IS NOT IN THE MODEL

  In: conduction through all four compartments, heat storage, metabolic
  generation where it actually arises, blood perfusion, and surface
  losses by convection and radiation into still air at 16 C.

  Out, deliberately: respiratory and cutaneous evaporative loss;
  vasomotor control, so the flow shares are fixed rather than
  responding to temperature; and any distinction between arterial and
  venous blood beyond the single well-mixed pool.

  THE EQUIVALENT CYLINDER

  A body is not a cylinder, and no single cylinder has both a human's
  volume and a human's surface area - real bodies have limbs, so their
  surface-to-volume ratio is much higher than a compact shape's. Since
  the surface area drives the loss and the volume drives the storage,
  both have to be right or the energy balance is wrong. So the cylinder
  is sized to reproduce BOTH:

    R = 2V/A,   L = V/(pi*R^2)

  giving a 75.6 mm radius and 4.0 m length for this subject. The length
  is not anatomical and is not meant to be; what it buys is that the
  model stores exactly the right amount of heat and loses it through
  exactly the right area. The compartment boundaries then follow from
  the cumulative volumes, which puts the core at 51.1 mm, muscle out to
  71.9, fat to 74.1 and skin to 75.6 - so 20.8 mm of muscle over the
  viscera, 2.3 mm of fat and 1.5 mm of skin, all of which are sensible
  mean depths. The ends are left adiabatic, so all the loss is through
  the lateral surface and the whole of the nominal body surface area is
  doing the work.

  VERIFICATION

  The layered profile is checked against its own closed form, layer by
  layer, and the report prints both. SetupGeometry integrates the exact
  radial solution outward through the compartments - q*R^2/(4k) across
  the generating core, then the shell solution with internal generation
  for each layer beyond - and uses it twice over: to set the skin
  coefficient that balances the body at the core set point, and to check
  the finite-element answer afterwards.

  Case 1 is the model's other check on itself: nothing should move.

  This rests on the 3D elements being right, which they now are - see
  Examples/ThermSlab, which found and now guards two defects in them
  (TBrick_H8V1's node ordering and TBrick_W6V1's integration weights).
  Before those were fixed this model was a third out on its gradients.

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

  BodySurfaceArea = 1.903;  // m2, DuBois for 75 kg / 1.75 m

  VO2 = 250.0;              // mL/min
  RQ = 0.8;                 // respiratory quotient

  CoreSetPointC = 37.0;     // the core the balanced start is built around

  (******************** THE COMPARTMENTS ********************)

  NbLayers = 4;

  LayerCore = 0;
  LayerMuscle = 1;
  LayerFat = 2;
  LayerSkin = 3;

type

  // One compartment. Mass and density fix its volume, and so its
  // boundary radius; GenShare is its fraction of the whole body's
  // resting heat output; RadialDiv is how many element layers it gets
  // through its thickness, and is ignored for the innermost, which is
  // meshed unstructured.
  RLayerSpec = record

    Name : String[8];
    Mass : Double;        // kg
    Density : Double;     // kg/m3
    Cp : Double;          // J/kgK
    K : Double;           // W/mK
    GenShare : Double;    // of the total heat output
    FlowShare : Double;   // of the cardiac output
    RadialDiv : Integer;

  end;

const

  Layers : Array[0..NbLayers - 1] of RLayerSpec =
  (
    // Viscera plus skeleton: three quarters of the resting output in
    // under half the volume.
    (Name : 'core';   Mass : 34.50; Density : 1050; Cp : 3700; K : 0.52;
     GenShare : 0.74; FlowShare : 0.75; RadialDiv : 0),

    // Skeletal muscle at rest. GenShare is the BASAL share - this is
    // the one that would climb with exercise, and the reason the
    // compartment is separate.
    (Name : 'muscle'; Mass : 33.75; Density : 1050; Cp : 3600; K : 0.51;
     GenShare : 0.23; FlowShare : 0.18; RadialDiv : 6),

    // Non-metabolic, as specified.
    (Name : 'fat';    Mass :  3.75; Density :  900; Cp : 2300; K : 0.21;
     GenShare : 0.00; FlowShare : 0.02; RadialDiv : 3),

    // 1.5 mm of it, and thermally almost inert until perfusion arrives.
    (Name : 'skin';   Mass :  3.00; Density : 1085; Cp : 3680; K : 0.37;
     GenShare : 0.03; FlowShare : 0.05; RadialDiv : 2)
  );

  (******************** PERFUSION ********************)

  // Blood, for the Pennes term.
  BloodDensity = 1050.0;    // kg/m3
  BloodCp = 3617.0;         // J/kgK

  // Cardiac output, L/min. Zero is the conduction-only model this
  // started as; 5 is a normal resting output; 10 is twice that.
  CardiacOutputDefault = 5.0;
  CardiacOutputMax = 10.0;

  (******************** ENVIRONMENT ********************)

  AmbientC = 16.0;          // theatre air and surrounding surfaces
  SkinEmissivity = 0.98;    // bare skin in the far infrared
  BareConvection = 3.0;     // W/m2K, natural convection over a supine body

  (******************** MESH ********************)

  // Circumferential divisions per quadrant, so 4x this around. The
  // report uses the MESHED volume and area throughout, so the polygon's
  // small deficit never leaks into the energy balance.
  NbCircPerQuadrant = 12;

  NbAxial = 4;              // along the cylinder - nothing varies axially
  CoreMeshSize = 0.006;     // m, unstructured element size in the core

  (******************** TIME ********************)

  TimeStep = 60.0;          // s
  NbTimeSteps = 120;        // 2 hours
  ReportEvery = 10;         // console line every this many steps

  (******************** CASES ********************)

  CaseDraped = 1;
  CaseExposed = 2;

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

    FRho, FCp, FK : Array[0..NbLayers - 1] of TExpressionList;
    FHConv, FTinf, FEmiss : TExpressionList;
    FGenSource : Array of TExpressionList;

    // Geometry, per compartment
    FLayerVol : Array[0..NbLayers - 1] of Double;      // nominal
    FMeshLayerVol : Array[0..NbLayers - 1] of Double;  // as meshed
    FLayerR : Array[0..NbLayers - 1] of Double;        // outer radius
    FLayerPower : Array[0..NbLayers - 1] of Double;    // W
    FLayerGen : Array[0..NbLayers - 1] of Double;      // W/m3
    FLayerDrop : Array[0..NbLayers - 1] of Double;     // K below the axis
    FLayerFlow : Array[0..NbLayers - 1] of Double;     // L/min
    FLayerW : Array[0..NbLayers - 1] of Double;        // 1/s perfusion rate
    FLayerTau : Array[0..NbLayers - 1] of Double;      // s, perfusion time constant

    FCardiacOutput : Double;   // L/min
    FTArt : Double;            // K, the well-mixed blood pool
    FPerfNet : Double;         // W, should be zero - see UpdateSources

    FROuter, FLength : Double;
    FMeshArea : Double;
    FTotalMass : Double;

    FHeatOutput : Double;                // W, whole body
    FHBalance : Double;                  // W/m2K that balances at the set point
    FAnalyticDrop : Double;              // K, axis to skin surface

    // Per element
    FEleVolume : TDoubleArray;
    FEleLayer : TDoubleArray;

    // Per node
    FNodeCapacity : TDoubleArray;        // J/K lumped to the node
    FNodeQMet : TDoubleArray;            // W, metabolic generation
    FNodePerfG : TDoubleArray;           // W/K, perfusion conductance
    FNodeR : TDoubleArray;               // radius from the axis

    FSkin : Array of RSkinFace;
    FNbSkin : Integer;

    FCoreNode : Integer;

    // History
    FHistT, FHistCore, FHistSkin, FHistLoss, FHistStore : TDoubleArray;
    FHistTArt, FHistPerf : TDoubleArray;
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

    procedure SetPerfusion(CardiacOutput : Double);
    procedure UpdateSources;

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
    procedure ReportPerfusion;

    procedure WriteResults(const CsvName : String);

  public

    constructor Create(ACase : Integer);
    destructor Destroy; override;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure PostProcess;

    procedure GetRadialProfiles(out R, T0, TEnd : TVMobj);

    // For the plot window: the compartment boundaries, in mm, innermost
    // outward, and their names.
    function InterfaceCount : Integer;
    function InterfaceMm(Index : Integer) : Double;
    function InterfaceName(Index : Integer) : String;

    property CaseNumber : Integer read FCase;

    // The run's console report, verbatim.
    property Report : TStringList read FReport;

    // Mesh and measure the geometry - independent of the cardiac
    // output, so it is done once and Solve may then be called repeatedly.
    procedure Prepare;

    // Build, settle and run at this cardiac output. The plot window
    // calls this again whenever the slider moves.
    procedure Solve(CardiacOutput : Double);

    property CardiacOutput : Double read FCardiacOutput;

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

  for i := 0 to NbLayers - 1 do
  begin
    FRho[i].Free;
    FCp[i].Free;
    FK[i].Free;
  end;

  FHConv.Free;
  FTinf.Free;
  FEmiss.Free;

  for i := 0 to Length(FGenSource) - 1 do
    FGenSource[i].Free;

  FGmsh.Free;

  inherited Destroy;

end;

function TThermalModel.InterfaceCount : Integer;
begin

  Result := NbLayers - 1;

end;

function TThermalModel.InterfaceMm(Index : Integer) : Double;
begin

  Result := FLayerR[Index] * 1000;

end;

function TThermalModel.InterfaceName(Index : Integer) : String;
begin

  Result := Layers[Index].Name + '/' + Layers[Index + 1].Name;

end;

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

(*******************************************************************
  The compartments, and the temperature profile they imply.

  Radii follow from the masses: each layer's volume is its mass over
  its density, and since the layers are concentric cylinders of the same
  length, the cumulative volume fixes each outer radius as

    r_i = R * sqrt(V_cumulative_i / V_total)

  Nothing is positioned by hand, so changing a mass or a density moves
  the boundaries consistently.

  The analytic profile is worked out here too, and used two ways: to set
  the skin coefficient that balances the body at the core set point, and
  to check the finite-element answer afterwards. For the innermost layer
  - a solid cylinder generating uniformly - the drop from axis to its
  surface is q*R^2/(4k). For each shell outside it, carrying power Qin
  from within and generating its own, integrating

    dT/dr = -Q(r) / (2*pi*k*L*r),   Q(r) = Qin + q*pi*(r^2 - rin^2)*L

  gives

    dT = (Qin - q*pi*rin^2*L)/(2*pi*k*L) * ln(rout/rin)
         + q*(rout^2 - rin^2)/(4*k)

  which is exact for every layer including the non-generating fat.
********************************************************************)
procedure TThermalModel.SetupGeometry;
var

  i : Integer;

  CalEquiv, V, Vcum, qFlux, Drop, Qin, rin, rout, q : Double;

begin

  // Caloric equivalent of oxygen, linear in RQ between the fat and
  // carbohydrate end points (4.686 kcal/L at RQ 0.707, 5.047 at 1.0).
  // At RQ 0.8 this gives 4.80 kcal/L, the standard table value.
  CalEquiv := 4.686 + (RQ - 0.707) * 1.232;

  FHeatOutput := (VO2 / 1000) * CalEquiv * 4184 / 60;

  (******************** VOLUMES AND RADII ********************)

  V := 0;

  for i := 0 to NbLayers - 1 do
  begin
    FLayerVol[i] := Layers[i].Mass / Layers[i].Density;
    V := V + FLayerVol[i];
  end;

  FTotalMass := 0;

  for i := 0 to NbLayers - 1 do
    FTotalMass := FTotalMass + Layers[i].Mass;

  // The equivalent cylinder: match the body's volume AND its surface
  // area, with the ends adiabatic so the whole area is lateral.
  FROuter := 2 * V / BodySurfaceArea;
  FLength := V / (Pi * FROuter * FROuter);

  Vcum := 0;

  for i := 0 to NbLayers - 1 do
  begin
    Vcum := Vcum + FLayerVol[i];
    FLayerR[i] := Sqrt(Vcum / (Pi * FLength));
  end;

  // Guard the layer table: a mass or density that puts a boundary
  // outside the one beyond it would mesh into nonsense rather than
  // fail, so it is caught here instead.
  for i := 1 to NbLayers - 1 do
    if FLayerR[i] <= FLayerR[i - 1] then
      raise Exception.Create('Layer ' + Layers[i].Name + ' has no thickness - ' +
        'check the masses and densities in the layer table.');

  (******************** GENERATION ********************)

  for i := 0 to NbLayers - 1 do
  begin

    FLayerPower[i] := Layers[i].GenShare * FHeatOutput;

    if FLayerVol[i] > 0 then
      FLayerGen[i] := FLayerPower[i] / FLayerVol[i]
    else
      FLayerGen[i] := 0;

  end;

  (******************** THE ANALYTIC PROFILE ********************)

  // Axis outward, accumulating the drop and the power passing each
  // radius. FLayerTAnalytic[i] is the temperature at layer i's OUTER
  // boundary, relative to the axis.
  Drop := 0;
  Qin := 0;

  for i := 0 to NbLayers - 1 do
  begin

    q := FLayerGen[i];
    rout := FLayerR[i];

    if i = 0 then
    begin
      // Solid cylinder generating uniformly.
      Drop := Drop + q * rout * rout / (4 * Layers[i].K);
      Qin := q * Pi * rout * rout * FLength;
    end
    else
    begin

      rin := FLayerR[i - 1];

      Drop := Drop +
        (Qin - q * Pi * rin * rin * FLength) /
          (2 * Pi * Layers[i].K * FLength) * Ln(rout / rin) +
        q * (rout * rout - rin * rin) / (4 * Layers[i].K);

      Qin := Qin + q * Pi * (rout * rout - rin * rin) * FLength;

    end;

    FLayerDrop[i] := Drop;

  end;

  FAnalyticDrop := Drop;

  // What surface coefficient balances generation against loss with the
  // core at the set point?
  qFlux := FHeatOutput / BodySurfaceArea;

  FHBalance := qFlux / ((CoreSetPointC + Kelvin) - FAnalyticDrop - (AmbientC + Kelvin));

end;

(*******************************************************************
  Geometry: a disc of the innermost compartment inside concentric
  annuli, one per outer layer, extruded along the axis.

  The core is meshed unstructured (triangles, hence prisms once
  extruded): it is one material with a smooth field and nothing about
  it needs structure. Every layer outside it is meshed structured
  instead, as four transfinite quadrants recombined into quads, hence
  hexahedra - the fat is 2.3 mm thick and the skin 1.5 mm, and an
  unstructured mesher would either miss them or flood the whole model
  with elements that size.

    point   1               axis
    point   10+4*L+q        interface radius L at quadrant angle q
    line    100+4*L+q       arc of radius L, quadrant q
    line    200+4*L+q       radial line from radius L to L+1 at angle q
    surface 300             the core disc
    surface 400+4*L+q       annulus of layer L, quadrant q
    volume  physical L+1    layer L
********************************************************************)
procedure TThermalModel.WriteGeoFile(const FileName : String);

  function PIdx(L, q : Integer) : Integer;
  begin
    Result := 10 + 4 * L + (q mod 4);
  end;

  function ArcId(L, q : Integer) : Integer;
  begin
    Result := 100 + 4 * L + q;
  end;

  function RadId(L, q : Integer) : Integer;
  begin
    Result := 200 + 4 * L + (q mod 4);
  end;

var

  F : TextFile;

  L, q, n : Integer;

  a : Double;

  Arcs, Rads, Vols : String;

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

    for L := 0 to NbLayers - 1 do
      for q := 0 to 3 do
      begin

        a := q * Pi / 2;

        WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
          [PIdx(L, q), Num(FLayerR[L] * Cos(a)), Num(FLayerR[L] * Sin(a))]));

      end;

    // Arcs at every interface radius, and the radial lines joining
    // consecutive ones.
    for L := 0 to NbLayers - 1 do
    begin

      Arcs := '';

      for q := 0 to 3 do
      begin

        WriteLn(F, Format('Circle(%d) = {%d,1,%d};',
          [ArcId(L, q), PIdx(L, q), PIdx(L, q + 1)]));

        if q > 0 then
          Arcs := Arcs + ',';

        Arcs := Arcs + IntToStr(ArcId(L, q));

      end;

      WriteLn(F, Format('Transfinite Line {%s} = %d;',
        [Arcs, NbCircPerQuadrant + 1]));

    end;

    for L := 0 to NbLayers - 2 do
    begin

      Rads := '';

      for q := 0 to 3 do
      begin

        WriteLn(F, Format('Line(%d) = {%d,%d};',
          [RadId(L, q), PIdx(L, q), PIdx(L + 1, q)]));

        if q > 0 then
          Rads := Rads + ',';

        Rads := Rads + IntToStr(RadId(L, q));

      end;

      // The layer OUTSIDE this pair of radii owns the divisions.
      WriteLn(F, Format('Transfinite Line {%s} = %d;',
        [Rads, Layers[L + 1].RadialDiv + 1]));

    end;

    // The core disc.
    Arcs := '';

    for q := 0 to 3 do
    begin
      if q > 0 then
        Arcs := Arcs + ',';
      Arcs := Arcs + IntToStr(ArcId(0, q));
    end;

    WriteLn(F, Format('Line Loop(299) = {%s};', [Arcs]));
    WriteLn(F, 'Plane Surface(300) = {299};');

    // The annuli, quadrant by quadrant.
    for L := 1 to NbLayers - 1 do
      for q := 0 to 3 do
      begin

        n := (q + 1) mod 4;

        WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
          [500 + 4 * L + q, RadId(L - 1, q), ArcId(L, q),
           RadId(L - 1, n), ArcId(L - 1, q)]));

        WriteLn(F, Format('Plane Surface(%d) = {%d};',
          [400 + 4 * L + q, 500 + 4 * L + q]));

        WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
          [400 + 4 * L + q, PIdx(L - 1, q), PIdx(L, q),
           PIdx(L, n), PIdx(L - 1, n)]));

        WriteLn(F, Format('Recombine Surface {%d};', [400 + 4 * L + q]));

      end;

    // Extruded one surface at a time so each volume id can be captured
    // for its physical group; they still mesh conformally, because the
    // curves they share are meshed once.
    WriteLn(F, Format('core[] = Extrude {0,0,%s} { Surface{300}; Layers{%d}; Recombine; };',
      [Num(FLength), NbAxial]));

    WriteLn(F, 'Physical Volume(1) = {core[1]};');

    for L := 1 to NbLayers - 1 do
    begin

      Vols := '';

      for q := 0 to 3 do
      begin

        WriteLn(F, Format('v%d_%d[] = Extrude {0,0,%s} { Surface{%d}; Layers{%d}; Recombine; };',
          [L, q, Num(FLength), 400 + 4 * L + q, NbAxial]));

        if q > 0 then
          Vols := Vols + ',';

        Vols := Vols + Format('v%d_%d[1]', [L, q]);

      end;

      WriteLn(F, Format('Physical Volume(%d) = {%s};', [L + 1, Vols]));

    end;

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
  SetLength(FEleLayer, FGmsh.NbElements);
  SetLength(FNodeCapacity, FGmsh.NbNodes);
  SetLength(FNodeR, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin
    FNodeCapacity[i] := 0;
    FNodeR[i] := Sqrt(Sqr(FGmsh.CoordX[i]) + Sqr(FGmsh.CoordY[i]));
  end;

  for i := 0 to NbLayers - 1 do
    FMeshLayerVol[i] := 0;

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
        'hexahedra (the outer layers) and prisms (the core).');

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

    // Physical region 1..NbLayers, innermost outward.
    g := FGmsh.ElementPhysicalRegion[i] - 1;

    if (g < 0) or (g > NbLayers - 1) then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in physical ' +
        'region ' + IntToStr(g + 1) + ', which is not one of the ' +
        IntToStr(NbLayers) + ' compartments.');

    FEleLayer[i] := g;

    FMeshLayerVol[g] := FMeshLayerVol[g] + FEleVolume[i];

    for j := 0 to nb - 1 do
      FNodeCapacity[Nd[j]] := FNodeCapacity[Nd[j]] +
        Layers[g].Density * Layers[g].Cp * FEleVolume[i] / nb;

    (******************** SKIN FACES ********************)

    // Only the outermost layer carries skin, and only its outward face:
    // every node of the face sits on the outer radius.
    if g = NbLayers - 1 then
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

  i, j, nb, g : Integer;

  Mat : Array[0..NbLayers - 1] of Integer;

  Node : Array[0..7] of Integer;

  EleType : NEleType;

  Q : Double;

begin

  FEngine := TThermalEngine.Create;

  FEngine.PenaltyMethod := True;
  FEngine.SolverType := soGMRES;

  (******************** MATERIALS ********************)

  // One material per compartment, from the layer table.
  for i := 0 to NbLayers - 1 do
  begin

    FRho[i] := TExpressionList.Create;
    FRho[i].AddExpression(0, 1000, Num(Layers[i].Density), 'T');

    FCp[i] := TExpressionList.Create;
    FCp[i].AddExpression(0, 1000, Num(Layers[i].Cp), 'T');

    FK[i] := TExpressionList.Create;
    FK[i].AddExpression(0, 1000, Num(Layers[i].K), 'T');

    Mat[i] := FEngine.AddMaterial(Constant, FRho[i], FCp[i], FK[i]);

  end;

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

    FEngine.AddElement(Node, nb, EleType, Mat[Round(FEleLayer[i])]);

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

  // There is no volumetric-source call on the engine, so each layer's
  // generation is lumped to its nodes here - the same thing the
  // structural engine does internally for self weight. Scaled by the
  // MESHED volume of that layer, so each compartment receives exactly
  // its share of the total however coarsely the circle is polygonised.
  SetLength(FNodeQMet, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    FNodeQMet[i] := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    g := Round(FEleLayer[i]);

    if FLayerPower[g] <= 0 then
      Continue;

    if FGmsh.ElementType[i] = GMSH_HEXA then
      nb := 8
    else
      nb := 6;

    Q := FLayerPower[g] * (FEleVolume[i] / FMeshLayerVol[g]) / nb;

    for j := 0 to nb - 1 do
      FNodeQMet[FGmsh.ElementNode[i, j]] := FNodeQMet[FGmsh.ElementNode[i, j]] + Q;

  end;

  SetLength(FGenSource, FGmsh.NbNodes);

  // A source on EVERY node, not only the generating ones: perfusion
  // exchanges at every node in a perfused compartment, and UpdateSources
  // rewrites these in place each step rather than adding more.
  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    FGenSource[i] := TExpressionList.Create;
    FGenSource[i].AddExpression(-1E9, 1E9, Num(FNodeQMet[i]), 't');

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


{ Distribute a cardiac output across the compartments and turn it into a
  per-node perfusion conductance.

  The Pennes bioheat term is a volumetric exchange with blood arriving at
  the arterial temperature,

    q_perf = w * rho_b * c_b * (Tart - T)   [W/m3]

  so lumping w*rho_b*c_b*V to the nodes of each element gives a
  conductance in W/K, which is all the rest of the model needs.

  Flow shares are the resting distribution of cardiac output: brain 14%,
  heart 4%, splanchnic 25%, kidneys 20% and bone and the rest 14% all
  fall in this model's core compartment, giving it 75%; muscle takes
  18%, skin 5% and fat 2%. Fat is perfused even though it is not
  metabolising - the two are different things, and it is the perfusion
  that matters for carrying heat.

  Note what this does to the coupling. At 5 L/min the core's perfusion
  conductance is 237 W/K against a whole-body heat capacity of 269 kJ/K,
  so blood equilibrates the core with the pool on a time constant of
  about nine minutes, where conduction alone took hours. That is the
  redistribution mechanism the conduction-only model could not
  represent. }
procedure TThermalModel.SetPerfusion(CardiacOutput : Double);
var

  i, g, j, nb : Integer;

  Flow, w : Double;

begin

  FCardiacOutput := Max(0, Min(CardiacOutputMax, CardiacOutput));

  SetLength(FNodePerfG, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    FNodePerfG[i] := 0;

  for g := 0 to NbLayers - 1 do
  begin

    // L/min to m3/s, then per unit volume of this compartment.
    Flow := FCardiacOutput * Layers[g].FlowShare;

    FLayerFlow[g] := Flow;

    if FMeshLayerVol[g] > 0 then
      w := (Flow / 1000 / 60) / FMeshLayerVol[g]
    else
      w := 0;

    FLayerW[g] := w;

    if w > 0 then
      FLayerTau[g] := Layers[g].Density * Layers[g].Cp / (w * BloodDensity * BloodCp)
    else
      FLayerTau[g] := 0;

  end;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    g := Round(FEleLayer[i]);

    if FLayerW[g] <= 0 then
      Continue;

    if FGmsh.ElementType[i] = GMSH_HEXA then
      nb := 8
    else
      nb := 6;

    for j := 0 to nb - 1 do
      FNodePerfG[FGmsh.ElementNode[i, j]] :=
        FNodePerfG[FGmsh.ElementNode[i, j]] +
        FLayerW[g] * BloodDensity * BloodCp * FEleVolume[i] / nb;

  end;

end;

{ Rewrite every node's source as metabolic generation plus its perfusion
  exchange with the blood pool.

  The pool closes the loop. Blood leaves it at Tart, exchanges with
  tissue and returns; with no external source or sink of blood heat, a
  well-mixed pool must sit at the FLOW-WEIGHTED MEAN tissue temperature,

    Tart = sum(G_i * T_i) / sum(G_i)

  and that choice makes sum(G_i * (Tart - T_i)) identically zero. So
  perfusion moves heat from warm compartments to cold ones and creates
  none, which is both the physics and the reason the energy-balance
  column in the report stays meaningful with perfusion switched on -
  FPerfNet is carried out and printed precisely so that claim is checked
  rather than asserted.

  The exchange is evaluated at the temperatures from the previous solve,
  which makes it an explicit, one-step-lagged term. That is sound here
  because the perfusion time constants run from 4.5 minutes at the core
  with a doubled cardiac output up to 35 minutes in muscle, against a 60
  second step; ReportPerfusion prints the tightest ratio so the margin
  is visible rather than assumed. }
procedure TThermalModel.UpdateSources;
var

  i : Integer;

  Numer, Denom, Q : Double;

begin

  Numer := 0;
  Denom := 0;

  for i := 0 to FEngine.NbNodes - 1 do
  begin
    Numer := Numer + FNodePerfG[i] * FEngine.Temperature[i];
    Denom := Denom + FNodePerfG[i];
  end;

  if Denom > 0 then
    FTArt := Numer / Denom
  else
    FTArt := 0;

  FPerfNet := 0;

  for i := 0 to FEngine.NbNodes - 1 do
  begin

    Q := FNodeQMet[i];

    if FNodePerfG[i] > 0 then
    begin
      Q := Q + FNodePerfG[i] * (FTArt - FEngine.Temperature[i]);
      FPerfNet := FPerfNet + FNodePerfG[i] * (FTArt - FEngine.Temperature[i]);
    end;

    FGenSource[i].Clear;
    FGenSource[i].AddExpression(-1E9, 1E9, Num(Q), 't');

  end;

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
    SetLength(FHistTArt, Length(FHistT));
    SetLength(FHistPerf, Length(FHistT));
  end;

  FHistT[FNbHist] := Now_;
  FHistCore[FNbHist] := FEngine.Temperature[FCoreNode] - Kelvin;
  FHistSkin[FNbHist] := MeanSkinTemperature - Kelvin;
  FHistLoss[FNbHist] := SurfaceLoss(FCase = CaseExposed);

  if dt > 0 then
    FHistStore[FNbHist] := (E - FEnergyPrev) / dt
  else
    FHistStore[FNbHist] := 0;

  // Recompute the blood pool and every node's exchange from the field
  // just solved, for the next step to use. Without this the perfusion
  // term stays frozen at its t=0 values and goes on driving heat out of
  // a core that has already cooled - which inverts the profile, putting
  // the core below the skin, and is exactly what happened when this
  // call was missing.
  UpdateSources;

  FHistTArt[FNbHist] := FTArt - Kelvin;
  FHistPerf[FNbHist] := FPerfNet;

  Inc(FNbHist);

  FEnergyPrev := E;
  FTimePrev := Now_;

end;


procedure TThermalModel.ReportSetup;
var

  i : Integer;

  Cap : Double;

begin

  Say('');
  Say('================ SUBJECT AND MODEL ================');
  Say(Format('  Body mass                : %8.1f kg', [FTotalMass]));
  Say(Format('  VO2 / RQ                 : %8.0f mL/min at RQ %.2f', [VO2, RQ]));
  Say(Format('  Metabolic heat output    : %8.1f W', [FHeatOutput]));
  Say('');

  Say('  compartment    mass    volume   outer r  thickness    power   generation');
  Say('                 (kg)       (L)      (mm)       (mm)      (W)      (W/m3)');

  for i := 0 to NbLayers - 1 do
    Say(Format('  %-10s %7.2f %9.2f %9.2f %10.2f %8.1f %11.0f',
      [Layers[i].Name, Layers[i].Mass, FLayerVol[i] * 1000,
       FLayerR[i] * 1000,
       1000 * (FLayerR[i] - IfThen(i = 0, 0, FLayerR[Max(i - 1, 0)])),
       FLayerPower[i], FLayerGen[i]]));

  Cap := 0;

  for i := 0 to NbLayers - 1 do
    Cap := Cap + Layers[i].Mass * Layers[i].Cp;

  Say('');
  Say(Format('  Equivalent cylinder      : R %6.1f mm, length %.2f m',
    [FROuter * 1000, FLength]));
  Say(Format('  Surface nominal / meshed : %8.3f m2 / %.3f m2',
    [BodySurfaceArea, FMeshArea]));
  Say(Format('  Heat capacity            : %8.0f kJ/K', [Cap / 1000]));
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

{ The radial profile, and how it compares with the closed form the layer
  chain was integrated from in SetupGeometry. Anything beyond ordinary
  discretisation here means the compartments, the generation split or
  the elements are not doing what the analytic chain assumes. }
procedure TThermalModel.ReportProfile;
var

  i, j, iBest : Integer;

  R, T0, TEnd : TVMobj;

  Axis, Best, d, TFE, TAn : Double;

begin

  GetRadialProfiles(R, T0, TEnd);

  Say('');
  Say('================ RADIAL PROFILE ================');
  Say(Format('  %d points from the axis to the skin.', [R.Cols]));
  Say('');
  Say('  boundary          r (mm)     FE (C)  analytic (C)   diff (K)');

  Axis := T0[0, 0];

  Say(Format('  %-14s %8.2f %10.3f %13.3f %10.3f',
    ['axis', 0.0, Axis, CoreSetPointC, Axis - CoreSetPointC]));

  for i := 0 to NbLayers - 1 do
  begin

    // Nearest profile point to this compartment's outer radius.
    Best := MaxDouble;
    iBest := 0;

    for j := 0 to R.Cols - 1 do
    begin

      d := Abs(R[0, j] - FLayerR[i] * 1000);

      if d < Best then
      begin
        Best := d;
        iBest := j;
      end;

    end;

    TFE := T0[0, iBest];
    TAn := CoreSetPointC - FLayerDrop[i];

    Say(Format('  %-14s %8.2f %10.3f %13.3f %10.3f',
      [Layers[i].Name + ' out', FLayerR[i] * 1000, TFE, TAn, TFE - TAn]));

  end;

  Say('');
  Say(Format('  Axis to skin: %.3f K by the model, %.3f K by the layered closed',
    [Axis - T0[0, R.Cols - 1], FAnalyticDrop]));
  Say('  form. The analytic chain integrates q*R^2/(4k) across the generating');
  Say('  core and the shell solution with internal generation across each layer');
  Say('  beyond it, so agreement here checks the compartments, the generation');
  Say('  split and the 3D elements together.');

  if FNbHist > 0 then
  begin
    Say('');
    Say(Format('  At the end of the run: axis %.2f C, skin %.2f C',
      [TEnd[0, 0], TEnd[0, R.Cols - 1]]));
  end;

end;

procedure TThermalModel.ReportHistory;
var

  i : Integer;

  Gen, Bal : Double;

begin

  Gen := FHeatOutput;

  Say('');
  Say('================ CORE TEMPERATURE ================');
  Say('    time    core    skin    pool     generated       lost      stored   balance     perf');
  Say('   (min)     (C)     (C)     (C)           (W)        (W)         (W)       (W)      (W)');

  for i := 0 to FNbHist - 1 do
  begin

    if (i mod ReportEvery <> 0) and (i <> FNbHist - 1) then
      Continue;

    Bal := Gen - FHistLoss[i] - FHistStore[i];

    Say(Format('  %6.1f  %6.2f  %6.2f  %6.2f  %12.1f %10.1f  %10.1f %9.2f %8.3f',
      [FHistT[i] / 60, FHistCore[i], FHistSkin[i], FHistTArt[i], Gen,
       FHistLoss[i], FHistStore[i], Bal, FHistPerf[i]]));

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

{ Mesh and measure. Nothing here depends on the cardiac output, so it is
  done once and Solve may then be called as often as the slider moves. }
procedure TThermalModel.Prepare;
begin

  WriteGeoFile(GeoFile);

  BuildMesh;

  CalcElementGeometry;

end;

procedure TThermalModel.ReportPerfusion;
var

  g : Integer;

  TightestRatio, Ratio : Double;

begin

  Say('');
  Say('================ PERFUSION ================');

  if FCardiacOutput <= 0 then
  begin
    Say('  Cardiac output 0 L/min - conduction only, as the model began.');
    Exit;
  end;

  Say(Format('  Cardiac output           : %8.2f L/min', [FCardiacOutput]));
  Say('');
  Say('  compartment    flow        w      conductance   time constant');
  Say('                (L/min)    (1/s)       (W/K)          (min)');

  TightestRatio := 0;

  for g := 0 to NbLayers - 1 do
  begin

    Say(Format('  %-10s %8.2f  %9.3e %12.1f %13.1f',
      [Layers[g].Name, FLayerFlow[g], FLayerW[g],
       FLayerW[g] * BloodDensity * BloodCp * FMeshLayerVol[g],
       FLayerTau[g] / 60]));

    if FLayerTau[g] > 0 then
    begin
      Ratio := TimeStep / FLayerTau[g];
      if Ratio > TightestRatio then
        TightestRatio := Ratio;
    end;

  end;

  Say('');
  Say(Format('  Blood pool (Tart)        : %8.2f C', [FTArt - Kelvin]));
  Say(Format('  Net perfusion heat       : %8.3f W  (must be zero: the pool is',
    [FPerfNet]));
  Say('                                       the flow-weighted mean, so what');
  Say('                                       one compartment gives another takes)');
  Say(Format('  Step / shortest tau      : %8.3f  (explicit term, so this wants',
    [TightestRatio]));
  Say('                                       to stay well under 1)');

end;

{ Build at this cardiac output, settle to the balanced starting state,
  then run the case.

  The engine is rebuilt from scratch each time rather than patched:
  Expose adds radiation boundary conditions that would otherwise
  accumulate across re-solves, and rebuilding is cheap next to the
  transient.

  The starting state is solved without perfusion and perfusion then
  begins with the transient; the reason is set out where it happens. }
procedure TThermalModel.Solve(CardiacOutput : Double);
var

  Start : QWord;

  i : Integer;

begin

  FReport.Clear;

  Say('ThermEx1 - heat loss from an anaesthetised adult, case ' + IntToStr(FCase));
  Say('');

  Start := GetTickCount64;

  BuildModel;

  ReportSetup;

  (******************** BALANCED STARTING STATE ********************)

  // Solved WITHOUT perfusion, deliberately. Two reasons.
  //
  // Physically it is the right starting point: an awake, undraped
  // patient is vasoconstricted, and it is induction that opens the
  // periphery up. Switching perfusion on at t = 0 alongside the drapes
  // coming off is the clinical sequence, and redistribution is then
  // something the run shows rather than something assumed into the
  // initial condition.
  //
  // Numerically it avoids a trap. Settling a perfused steady state by
  // Picard iteration - solve, recompute the exchange, solve again -
  // diverges, and violently: the core's perfusion conductance is 237
  // W/K against about 5 W/K from the whole body to ambient, so the
  // iteration matrix has a spectral radius far above one and the field
  // reaches 1e80 within a few passes. An implicit treatment would need
  // the term inside the stiffness matrix, which the framework has no
  // call for - see the note on that in the header. In the TRANSIENT the
  // mass matrix supplies exactly that stabilising diagonal, which is
  // why the explicit term is safe there and not here.
  Say('');
  Say('Solving the draped steady state, conduction only...');

  FEngine.CalcTemperature(caStatic, False);

  Say(Format('  core %.2f C, skin %.2f C, loss %.1f W against %.1f W generated',
    [FEngine.Temperature[FCoreNode] - Kelvin, MeanSkinTemperature - Kelvin,
     SurfaceLoss(False), FHeatOutput]));

  SetLength(FTInitial, FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
    FTInitial[i] := FEngine.Temperature[i];

  // Perfusion starts here, with the transient - see the note above.
  SetPerfusion(CardiacOutput);
  UpdateSources;

  ReportPerfusion;

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

  Say('');
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

procedure TThermalModel.Run;
begin

  Prepare;

  Solve(CardiacOutputDefault);

end;

initialization

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DotFS.ThousandSeparator := #0;

end.
