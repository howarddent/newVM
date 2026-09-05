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
  generation where it actually arises, blood perfusion, surface losses
  by convection and radiation into still air at 16 C from the exposed
  surface, and conduction through the cushion from the surface lying on
  it.

  Out, deliberately: respiratory and cutaneous evaporative loss;
  vasomotor control, so the flow shares are fixed rather than
  responding to temperature; any distinction between arterial and
  venous blood beyond the single well-mixed pool; and the cushion's own
  transient warm-up, discussed under THE CUSHION above.

  THE EQUIVALENT ELLIPTICAL CYLINDER

  A body is not a cylinder, and it is not circular in section either: a
  supine trunk is roughly twice as wide as it is deep. That matters here
  for two reasons - the conduction path from the core to the front and
  back is much shorter than the path out to the sides, and the shape has
  a broad flat underside for the cushion to press against. So the
  section is an ELLIPSE with its minor axis half its major, lying with
  the major axis horizontal.

  No single shape of a given family has both a human's volume and a
  human's surface area unless it is sized for both - real bodies have
  limbs, so their surface-to-volume ratio is much higher than a compact
  shape's - and since the surface area drives the loss and the volume
  drives the storage, both have to be right or the energy balance is
  wrong. With k the axis ratio (minor over major, so 0.5 here), the
  ellipse of semi-major axis a has cross-sectional area pi*k*a^2 and
  perimeter p1*a, where p1 = p1(k) is a shape constant computed by
  Ramanujan's approximation (2*pi for a circle, 4.8442 at k = 0.5).
  Matching both the volume V and the area A then gives

    a = p1*V/(pi*k*A),   b = k*a,   L = V/(pi*a*b)

  which is 116.6 mm by 58.3 mm over a 3.37 m length for this subject,
  against the 75.6 mm radius and 4.0 m of the circular cylinder this
  model began as. Set AspectRatio back to 1.0 and every formula in this
  unit collapses to that earlier circular case exactly, which is how the
  elliptical generalisation was checked.

  The length is not anatomical and is not meant to be; what it buys is
  that the model stores exactly the right amount of heat and loses it
  through exactly the right area. The ends are left adiabatic, so all
  the loss is through the lateral surface and the whole of the nominal
  body surface area is doing the work.

  Compartment boundaries are SIMILAR ellipses - same axis ratio, scaled
  by the cumulative volume, a_i = a*sqrt(V_i/V) - which puts the core
  boundary at 78.8 mm on the major axis and 39.4 mm on the minor, with
  32.0/16.0 mm of muscle over it, then 3.5/1.75 mm of fat and 2.3/1.13
  mm of skin. Every point is then labelled by the semi-major axis s of
  the similar ellipse through it, s = sqrt(x^2 + (y/k)^2), which is the
  natural radial coordinate here and the one the profile plot uses.

  What similar ellipses cost is that a layer is thinner over the front
  and back than at the sides, by exactly the factor k, where a real
  skin layer is closer to constant thickness. Constant-thickness layers
  would be offset curves rather than ellipses, which the mesher cannot
  draw as arcs and which would lose the single radial coordinate; the
  error is small next to what the shape itself buys, but it does bias
  the front and back slightly towards heat loss.

  THE CUSHION

  An anaesthetised patient is not suspended in the air: they lie on a
  foam mattress, and the part of them in contact with it loses heat
  through 100 mm of foam instead of into the room. The cushion is
  carried as a surface condition rather than as meshed foam - the
  contact patch gets a series conductance

    U = 1/(t/k_foam + 1/h_under)

  which is 0.37 W/m2K for 100 mm of open-cell polyurethane, against
  something near 9 W/m2K for bare skin losing heat by convection and
  radiation together. The back of the patient is, to a good
  approximation, insulated.

  The patch is the part of the surface within 60 degrees of straight
  down, which on this ellipse - broad and flat underneath, where the
  radius of curvature is a^2/b, four times the minor semi-axis - comes
  to about 38% of the body surface. That is the well-known clinical
  point that only some 60% of the body surface is available to lose
  heat, arrived at here from the geometry rather than assumed.

  Radiation is applied to the exposed surface only: a surface in contact
  with foam has nothing to radiate to.

  What this leaves out is the cushion's own warm-up. Foam has a thermal
  diffusivity near 7e-7 m2/s, so 100 mm of it takes some four hours to
  settle into the straight-line profile the U value assumes, and for the
  first hour or so the patch behaves more like a semi-infinite solid at
  room temperature - about 0.65 W/m2K at half an hour, against the 0.37
  it tends to. On a 20 K difference that is a few watts out of ninety,
  and always in the direction of losing slightly more early on than the
  model says.

  VERIFICATION

  The layered profile is still checked against a closed form, layer by
  layer, with the report printing both - but the closed form now has to
  work on an ellipse, and the way it does is worth setting out.

  Write the chain in the similar-ellipse coordinate s. A shell between s
  and s+ds has perimeter p1*s and, since similar ellipses are not
  parallel curves, a thickness that varies around it as k*ds/N with
  N = sqrt(sin^2 t + k^2 cos^2 t). Integrating the conductance around
  the shell gives a total that is exactly as if the perimeter were
  Pc = pi*(1 + k^2)/k and the thickness uniform, so the whole cylindrical
  chain carries over with 2*pi replaced by Pc and pi*r^2 by pi*k*s^2:

    core     dT = q*k^2*s^2 / (2*kc*(1 + k^2))
    shell    dT = (Qin - q*pi*k*s_in^2*L)/(kc*Pc*L) * ln(s_out/s_in)
                  + q*pi*k*(s_out^2 - s_in^2)/(2*kc*Pc)

  At k = 1 these are the circular formulas q*R^2/(4*kc) and the shell
  solution the earlier model used, unchanged. The core one is not an
  approximation at any k: a uniformly generating solid ellipse held at a
  fixed boundary temperature has the exact solution q*a^2*b^2/(2*kc*
  (a^2+b^2)), and that is what this returns. The shell one is exact in
  the thin-shell limit and an approximation between - a layered ellipse
  has no genuinely one-dimensional solution, unlike the circle.

  So the finite-element answer is the arbiter, and the check is run in a
  configuration where the analytic chain is entitled to be right: one
  extra static solve with a UNIFORM surface coefficient, no cushion,
  which is the only case the chain describes. That solve also prints the
  spread of temperature around each similar ellipse, which is the size
  of the two-dimensional effect the chain cannot see - mesh noise on a
  circle, real on an ellipse.

  The draped coefficient itself is no longer taken from the chain. With
  the cushion in place the surface is not uniform and the chain cannot
  set it, so it is calibrated on the finite-element model directly, by
  secant iteration on static solves until the core sits at the set point
  - which is both more honest and independent of the shape.

  Case 1 at a cardiac output of zero is the model's other check on
  itself: nothing should move, and nothing does - the core holds 37.00 C
  for the whole two hours, the surface loses exactly the 83.7 W being
  generated, and the stored energy does not budge. Run case 1 WITH
  perfusion and it does move, by design and not by error: the balanced
  state is settled conduction-only, so switching blood on at t = 0 is
  itself a change, and what follows is redistribution - see the note in
  Solve on why the starting state is built that way.

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

  WHAT THE SHAPE AND THE CUSHION DO TO THE ANSWER

  At 5 L/min, exposed at t = 0, the core now falls 2.08 C/h against the
  2.66 C/h of the circular cylinder with nothing underneath it - a fifth
  slower, and nearly all of that is the cushion rather than the shape.
  Of the 138 W leaving at the end of the run, 4 W goes out through the
  foam: the back of the patient has all but stopped losing heat, and its
  skin sits some 3.5 K warmer than the front's, a gap already 7 K wide
  in the balanced starting state. The drape coefficient the calibration
  lands on is 5.49 W/m2K, against the 2.69 the same ellipse would need
  with nothing underneath it, because the same 84 W now has to leave
  through 62% of the surface.

  Setting AspectRatio back to 1 and ContactHalfAngleDeg to 0 reproduces
  the earlier model exactly - a 75.6 mm radius over 4.01 m, the core
  boundary at 51.09 mm, an analytic drop of 4.889 K matched by the
  finite-element answer to 0.001 K, and 2.66 C/h - which is how this
  change was checked.

  THE TWO CASES

  Both start from the same physiological steady state: a static solve
  with the drape coefficient calibrated so the body is exactly in
  balance with a 37 C core - which is what "the skin initially emits as
  much heat as is being generated" means once you work out what it
  implies. The patient is on the cushion from the start, in both cases,
  because that is the clinical picture: what changes at induction is the
  drapes over the front, not what is underneath. So the calibrated
  coefficient now has to carry the whole metabolic output out through
  the 62% of the surface that is not lying on foam, and comes out near
  5.5 W/m2K rather than the 2.7 the fully surrounded cylinder needed.

    1  draped - the balanced state is simply held. At a cardiac output
       of zero nothing moves at all, which makes this the model's own
       check on itself; with blood flowing, redistribution alone still
       cools the core, drapes or no drapes.
    2  exposed - at t = 0 the drapes come off the front: its coefficient
       drops to bare-skin natural convection and radiation is switched
       on, while the contact patch carries on conducting into the
       cushion exactly as before. This is the tracking run. }

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
  // boundary ellipse; GenShare is its fraction of the whole body's
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

  (******************** SHAPE ********************)

  // Minor axis over major, for the elliptical section. 0.5 is a supine
  // trunk, twice as wide as it is deep. 1.0 gives back the circular
  // cylinder this model began as, exactly - every formula in this unit
  // reduces to the circular one at k = 1, which is how the elliptical
  // generalisation is checked.
  AspectRatio = 0.5;

  (******************** ENVIRONMENT ********************)

  AmbientC = 16.0;          // theatre air and surrounding surfaces
  SkinEmissivity = 0.98;    // bare skin in the far infrared
  BareConvection = 3.0;     // W/m2K, natural convection over a supine body

  (******************** THE CUSHION ********************)

  // The foam mattress the patient lies on, carried as a series
  // conductance over the contact patch rather than as meshed foam - see
  // THE CUSHION in the header for what that assumes and what it costs.
  PadThickness = 0.10;      // m
  PadConductivity = 0.040;  // W/mK, open-cell polyurethane foam
  PadUnderside = 5.0;       // W/m2K, foam to table top and the still air under it

  // Half-width of the contact patch, as the ellipse's parametric angle
  // either side of straight down. 60 degrees is about 38% of the body
  // surface on this section; 0 lifts the patient off the cushion
  // altogether, which is the model as it stood before.
  ContactHalfAngleDeg = 60.0;

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

  // How often the whole field is kept for the gmsh animation. Every
  // fifth minute over two hours is 25 frames including t = 0, one file
  // each - see WriteViewFiles for why they are separate files.
  SnapshotSeconds = 300.0;

  (******************** CASES ********************)

  CaseDraped = 1;
  CaseExposed = 2;

type

  // A face of an element lying on the outer (skin) surface. Supported
  // means it is in contact with the cushion, so it conducts through
  // foam rather than losing heat to the room; Angle is the ellipse's
  // parametric angle at its centre, measured from the major axis, and
  // is what decides that.
  RSkinFace = record

    Ele : Integer;
    FaceIdx : Integer;
    NbNodes : Integer;
    Node : Array[0..3] of Integer;
    Area : Double;
    Angle : Double;
    Supported : Boolean;

  end;

  // Which part of the surface, or of the body, a quantity refers to.
  // The cushion makes front and back genuinely different, so most of
  // what the model reports has to be asked for one or the other.
  TProfileSector = (psAll, psFront, psBack);

  TThermalModel = class(TObject)

  private

    FCase : Integer;

    FGmsh : TGmsh;
    FEngine : TThermalEngine;

    FRho, FCp, FK : Array[0..NbLayers - 1] of TExpressionList;
    FHConv, FHPad, FTinf, FEmiss : TExpressionList;
    FGenSource : Array of TExpressionList;

    // Geometry, per compartment
    FLayerVol : Array[0..NbLayers - 1] of Double;      // nominal
    FMeshLayerVol : Array[0..NbLayers - 1] of Double;  // as meshed
    FLayerA : Array[0..NbLayers - 1] of Double;        // outer semi-major axis
    FLayerPower : Array[0..NbLayers - 1] of Double;    // W
    FLayerGen : Array[0..NbLayers - 1] of Double;      // W/m3
    FLayerDrop : Array[0..NbLayers - 1] of Double;     // K below the centre
    FLayerFlow : Array[0..NbLayers - 1] of Double;     // L/min
    FLayerW : Array[0..NbLayers - 1] of Double;        // 1/s perfusion rate
    FLayerTau : Array[0..NbLayers - 1] of Double;      // s, perfusion time constant

    FCardiacOutput : Double;   // L/min
    FTArt : Double;            // K, the well-mixed blood pool
    FPerfNet : Double;         // W, should be zero - see UpdateSources

    FSemiMajor, FSemiMinor, FLength : Double;
    FShapeArea : Double;                 // pi*k, so section area = FShapeArea*s^2
    FShapePerim : Double;                // pi*(1+k^2)/k, the chain's effective 2*pi
    FMeshArea : Double;
    FMeshAreaFront : Double;             // exposed to the room
    FMeshAreaBack : Double;              // lying on the cushion
    FTotalMass : Double;

    FUPad : Double;                      // W/m2K through the cushion

    FHeatOutput : Double;                // W, whole body
    FHBalance : Double;                  // W/m2K, uniform surface, no cushion
    FHDraped : Double;                   // W/m2K, calibrated with the cushion
    FAnalyticDrop : Double;              // K, centre to skin surface
    FUniformDrop : Double;               // K, the same by FE in the reference solve
    FUniformSpread : Double;             // K, worst spread around one similar ellipse
    FNbCalibrations : Integer;           // static solves the calibration needed

    // Per element
    FEleVolume : TDoubleArray;
    FEleLayer : TDoubleArray;

    // Per node
    FNodeCapacity : TDoubleArray;        // J/K lumped to the node
    FNodeQMet : TDoubleArray;            // W, metabolic generation
    FNodePerfG : TDoubleArray;           // W/K, perfusion conductance
    FNodeS : TDoubleArray;               // similar-ellipse semi-major axis

    FSkin : Array of RSkinFace;
    FNbSkin : Integer;

    FCoreNode : Integer;

    // History
    FHistT, FHistCore, FHistSkin, FHistLoss, FHistStore : TDoubleArray;
    FHistSkinB, FHistLossB : TDoubleArray;   // the back, on the cushion
    FHistTArt, FHistPerf : TDoubleArray;
    FNbHist : Integer;

    // The whole field, kept every SnapshotSeconds, for the gmsh
    // animation. 25 frames of 4285 nodes is under a megabyte, so this
    // is kept in full rather than rewritten to disk as the run goes.
    FSnapTime : TDoubleArray;             // s
    FSnap : Array of TDoubleArray;        // C, by node
    FNbSnap : Integer;

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
    procedure SurfaceLosses(UseRadiation : Boolean; out Front, Back : Double);
    function SurfaceLoss(UseRadiation : Boolean) : Double;
    function MeanSkinTemperature(Sector : TProfileSector) : Double;

    procedure SetSurfaceCoefficients(HFront, UBack : Double);
    procedure VerifyAgainstAnalytic;
    procedure CalibrateDraped;

    procedure Expose;

    procedure ReportSetup;
    procedure ReportHistory;
    procedure ReportProfile;
    procedure ReportPerfusion;

    procedure WriteResults(const CsvName : String);

    procedure TakeSnapshot(AtTime : Double);
    procedure WriteViewFiles;
    procedure WriteViewScript(const FileName : String);

  public

    constructor Create(ACase : Integer);
    destructor Destroy; override;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure PostProcess;

    // Write the run out as a numbered series of gmsh views and open
    // gmsh on them. Frames are SnapshotSeconds apart.
    procedure ShowInGmsh;

    function SnapshotCount : Integer;

    procedure GetRadialProfiles(Sector : TProfileSector;
                                out S, T0, TEnd : TVMobj);

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
  ScrFile = DataDir + 'thermex1.scr';

  // One .pos per frame, numbered: ViewPrefix + '000.pos' upward.
  ViewPrefix = DataDir + 'thermex1_';

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
  FHPad.Free;
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

  Result := FLayerA[Index] * 1000;

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

{ The subject's heat output, the elliptical cylinder that carries it, and
  the uniform surface coefficient that would put the whole thing in
  balance at the core set point with nothing underneath it. All of it
  derived rather than tabulated, so changing the subject changes the
  model consistently - and the coefficient the run actually uses is
  calibrated from here, in CalibrateDraped, since the cushion puts it
  beyond what any closed form of this chain can say. }

(*******************************************************************
  The compartments, the elliptical cylinder that carries them, and the
  temperature profile they imply.

  The section is an ellipse of axis ratio k = AspectRatio, sized to
  reproduce both the body's volume and its surface area - see THE
  EQUIVALENT ELLIPTICAL CYLINDER in the header for the derivation of

    a = p1*V/(pi*k*A),   b = k*a,   L = V/(pi*a*b)

  where p1 is the perimeter of the unit ellipse of that ratio, taken
  from Ramanujan's second approximation.

  Two shape constants carry the ellipse through everything that follows,
  and both are 2*pi's circular value at k = 1:

    FShapeArea  = pi*k          section area inside s is FShapeArea*s^2
    FShapePerim = pi*(1+k^2)/k  the chain's effective perimeter constant

  Boundaries follow from the masses: each layer's volume is its mass
  over its density, and since the layers are SIMILAR ellipses of the
  same length, the cumulative volume fixes each outer semi-major axis as

    s_i = sqrt(V_cumulative_i / (FShapeArea * L))

  Nothing is positioned by hand, so changing a mass or a density moves
  the boundaries consistently.

  The analytic profile is worked out here too, and used two ways: as a
  first guess at the surface coefficient that balances the body at the
  core set point, and to check the finite-element answer afterwards in
  the uniform-surface reference solve that is the only configuration it
  describes. For the innermost layer - a solid ellipse generating
  uniformly - the drop from centre to its surface is

    q*FShapeArea*s^2 / (2*kc*FShapePerim)

  which is q*a^2*b^2/(2*kc*(a^2+b^2)), the exact solution of that
  problem, and q*R^2/(4*kc) at k = 1. For each shell outside it,
  carrying power Qin from within and generating its own, integrating

    dT/ds = -Q(s) / (kc*FShapePerim*L*s),
    Q(s)  = Qin + q*FShapeArea*(s^2 - s0^2)*L

  gives

    dT = (Qin - q*FShapeArea*s0^2*L)/(kc*FShapePerim*L) * ln(s1/s0)
         + q*FShapeArea*(s1^2 - s0^2)/(2*kc*FShapePerim)

  exact for every layer including the non-generating fat at k = 1, and
  exact in the thin-shell limit otherwise - see VERIFICATION.
********************************************************************)
procedure TThermalModel.SetupGeometry;
var

  i : Integer;

  CalEquiv, V, Vcum, qFlux, Drop, Qin, s0, s1, q, k, p1 : Double;

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

  k := AspectRatio;

  // Ramanujan's second approximation to the perimeter of an ellipse of
  // semi-axes 1 and k. It is good to a few parts in 1e5 at this ratio
  // and exact at k = 1, where it returns 2*pi.
  p1 := Pi * (3 * (1 + k) - Sqrt((3 + k) * (1 + 3 * k)));

  FShapeArea := Pi * k;
  FShapePerim := Pi * (1 + k * k) / k;

  // The equivalent elliptical cylinder: match the body's volume AND its
  // surface area, with the ends adiabatic so the whole area is lateral.
  FSemiMajor := p1 * V / (Pi * k * BodySurfaceArea);
  FSemiMinor := k * FSemiMajor;
  FLength := V / (Pi * FSemiMajor * FSemiMinor);

  Vcum := 0;

  for i := 0 to NbLayers - 1 do
  begin
    Vcum := Vcum + FLayerVol[i];
    FLayerA[i] := Sqrt(Vcum / (FShapeArea * FLength));
  end;

  // The cushion, as a series conductance: 100 mm of foam, then whatever
  // film the table and the still air beneath it offer.
  FUPad := 1 / (PadThickness / PadConductivity + 1 / PadUnderside);

  // Guard the layer table: a mass or density that puts a boundary
  // outside the one beyond it would mesh into nonsense rather than
  // fail, so it is caught here instead.
  for i := 1 to NbLayers - 1 do
    if FLayerA[i] <= FLayerA[i - 1] then
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

  // Centre outward, accumulating the drop and the power passing each
  // similar ellipse. FLayerDrop[i] is the temperature at layer i's
  // OUTER boundary, relative to the centre.
  Drop := 0;
  Qin := 0;

  for i := 0 to NbLayers - 1 do
  begin

    q := FLayerGen[i];
    s1 := FLayerA[i];

    if i = 0 then
    begin
      // Solid ellipse generating uniformly - exact at any axis ratio.
      Drop := Drop + q * FShapeArea * s1 * s1 / (2 * Layers[i].K * FShapePerim);
      Qin := q * FShapeArea * s1 * s1 * FLength;
    end
    else
    begin

      s0 := FLayerA[i - 1];

      Drop := Drop +
        (Qin - q * FShapeArea * s0 * s0 * FLength) /
          (Layers[i].K * FShapePerim * FLength) * Ln(s1 / s0) +
        q * FShapeArea * (s1 * s1 - s0 * s0) / (2 * Layers[i].K * FShapePerim);

      Qin := Qin + q * FShapeArea * (s1 * s1 - s0 * s0) * FLength;

    end;

    FLayerDrop[i] := Drop;

  end;

  FAnalyticDrop := Drop;

  // What UNIFORM surface coefficient - no cushion - balances generation
  // against loss with the core at the set point? This is the reference
  // configuration the analytic chain is checked in, and the first guess
  // the calibration with the cushion starts from.
  qFlux := FHeatOutput / BodySurfaceArea;

  FHBalance := qFlux / ((CoreSetPointC + Kelvin) - FAnalyticDrop - (AmbientC + Kelvin));

  FHDraped := FHBalance;

end;

(*******************************************************************
  Geometry: an elliptical disc of the innermost compartment inside
  similar elliptical annuli, one per outer layer, extruded along the
  axis.

  The core is meshed unstructured (triangles, hence prisms once
  extruded): it is one material with a smooth field and nothing about
  it needs structure. Every layer outside it is meshed structured
  instead, as four transfinite quadrants recombined into quads, hence
  hexahedra - the fat is 3.5 mm thick on the major axis and 1.75 mm on
  the minor, the skin 2.3 and 1.13, and an unstructured mesher would
  either miss them or flood the whole model with elements that size.

    point   1               centre
    point   10+4*L+q        boundary L at quadrant angle q
    line    100+4*L+q       quarter-ellipse arc of boundary L, quadrant q
    line    200+4*L+q       radial line from boundary L to L+1 at angle q
    surface 300             the core disc
    surface 400+4*L+q       annulus of layer L, quadrant q
    volume  physical L+1    layer L

  The quadrant corner points sit at parametric angle 0, 90, 180 and 270
  degrees, so they land on the axes and the four arcs of a boundary are
  quarter ellipses - each under Pi, which is what the built-in kernel
  requires of an elliptical arc.
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

        // x = s*cos t, y = k*s*sin t - the similar ellipse of
        // semi-major axis s at parametric angle t.
        WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
          [PIdx(L, q), Num(FLayerA[L] * Cos(a)),
           Num(AspectRatio * FLayerA[L] * Sin(a))]));

      end;

    // Arcs at every boundary, and the radial lines joining
    // consecutive ones.
    for L := 0 to NbLayers - 1 do
    begin

      Arcs := '';

      for q := 0 to 3 do
      begin

        // Start, centre, a point on the major axis, end. The layer's
        // own point at angle zero is on the major axis by construction,
        // so it serves as the third argument for all four quadrants.
        WriteLn(F, Format('Ellipse(%d) = {%d,1,%d,%d};',
          [ArcId(L, q), PIdx(L, q), PIdx(L, 0), PIdx(L, q + 1)]));

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

  Say('Meshing the elliptical cylinder with gmsh...');

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

  mx, my, HalfAngle : Double;

  OnSkin : Boolean;

  Nd : Array[0..7] of Integer;

begin

  // The contact patch, as an angle either side of straight down.
  HalfAngle := DegToRad(ContactHalfAngleDeg);

  SetLength(FEleVolume, FGmsh.NbElements);
  SetLength(FEleLayer, FGmsh.NbElements);
  SetLength(FNodeCapacity, FGmsh.NbNodes);
  SetLength(FNodeS, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin
    FNodeCapacity[i] := 0;

    // The semi-major axis of the similar ellipse through this node -
    // the radial coordinate everything in this model is organised by,
    // and the plain radius again at an axis ratio of 1.
    FNodeS[i] := Sqrt(Sqr(FGmsh.CoordX[i]) +
                      Sqr(FGmsh.CoordY[i] / AspectRatio));
  end;

  for i := 0 to NbLayers - 1 do
    FMeshLayerVol[i] := 0;

  FMeshArea := 0;
  FMeshAreaFront := 0;
  FMeshAreaBack := 0;

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
    // every node of the face sits on the outer ellipse.
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

          if FNodeS[FSkin[FNbSkin].Node[j]] < FSemiMajor - 1.0E-5 then
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

        // Where this face sits round the section, as the ellipse's own
        // parametric angle: x = s*cos t, y = k*s*sin t, so dividing y
        // by k before taking the angle is what makes t come out. The
        // patch in contact with the cushion is the part within
        // ContactHalfAngleDeg of straight down, t = -90.
        mx := 0;
        my := 0;

        for j := 0 to n - 1 do
        begin
          mx := mx + FGmsh.CoordX[FSkin[FNbSkin].Node[j]];
          my := my + FGmsh.CoordY[FSkin[FNbSkin].Node[j]];
        end;

        FSkin[FNbSkin].Angle := ArcTan2(my / (n * AspectRatio), mx / n);

        FSkin[FNbSkin].Supported :=
          Abs(FSkin[FNbSkin].Angle + Pi / 2) <= HalfAngle;

        FMeshArea := FMeshArea + FSkin[FNbSkin].Area;

        if FSkin[FNbSkin].Supported then
          FMeshAreaBack := FMeshAreaBack + FSkin[FNbSkin].Area
        else
          FMeshAreaFront := FMeshAreaFront + FSkin[FNbSkin].Area;

        Inc(FNbSkin);

        if FNbSkin >= Length(FSkin) then
          SetLength(FSkin, Length(FSkin) * 2);

      end;

    end;

  end;

  SetLength(FSkin, FNbSkin);

  // The core: at the centre, half way along.
  Base := MaxDouble;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    dz := Sqrt(Sqr(FNodeS[i]) + Sqr(FGmsh.CoordZ[i] - FLength / 2));

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

  // Two surface conditions, not one: the exposed front loses heat to
  // the room through FHConv, the contact patch conducts into the
  // cushion through FHPad. Both see the same far temperature - the foam
  // stands on a table in the same theatre - and both are read afresh at
  // every assembly, which is what lets the calibration below move the
  // front coefficient without rebuilding anything.
  FTinf := TExpressionList.Create;
  FTinf.AddExpression(-1E9, 1E9, Num(AmbientC + Kelvin), 't');

  FHConv := TExpressionList.Create;
  FHConv.AddExpression(-1E9, 1E9, Num(FHDraped), 't');

  FHPad := TExpressionList.Create;
  FHPad.AddExpression(-1E9, 1E9, Num(FUPad), 't');

  FEmiss := TExpressionList.Create;
  FEmiss.AddExpression(-1E9, 1E9, Num(SkinEmissivity), 't');

  for i := 0 to FNbSkin - 1 do
    if FSkin[i].Supported then
      FEngine.AddFaceConvection(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FHPad, FTinf)
    else
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
  begin

    // No flow at all, so there is no flow-weighted mean to take. Blood
    // that is not moving sits at the temperature of the tissue around
    // it, so the capacity-weighted mean stands in - it drives nothing
    // here, since every conductance is zero, and it keeps the pool
    // column of the report from reading absolute zero.
    Numer := 0;
    Denom := 0;

    for i := 0 to FEngine.NbNodes - 1 do
    begin
      Numer := Numer + FNodeCapacity[i] * FEngine.Temperature[i];
      Denom := Denom + FNodeCapacity[i];
    end;

    if Denom > 0 then
      FTArt := Numer / Denom
    else
      FTArt := 0;

  end;

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

{ Heat leaving the skin, split between the surface exposed to the room
  and the patch lying on the cushion.

  The two are worth carrying separately, and not only for the report:
  they are the whole point of the cushion. Radiation is charged to the
  exposed faces alone, because those are the only ones Expose gives a
  radiation condition to - a surface pressed into foam has nothing to
  radiate to. }
procedure TThermalModel.SurfaceLosses(UseRadiation : Boolean;
                                      out Front, Back : Double);
var

  i, j : Integer;

  Tf, Tinf, h, u, Q : Double;

begin

  Front := 0;
  Back := 0;

  Tinf := AmbientC + Kelvin;

  h := FHConv.GetValue(0);
  u := FHPad.GetValue(0);

  for i := 0 to FNbSkin - 1 do
  begin

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    if FSkin[i].Supported then
    begin
      Back := Back + u * (Tf - Tinf) * FSkin[i].Area;
      Continue;
    end;

    Q := h * (Tf - Tinf) * FSkin[i].Area;

    if UseRadiation then
      Q := Q + SkinEmissivity * Sigma *
           (Tf * Tf * Tf * Tf - Tinf * Tinf * Tinf * Tinf) * FSkin[i].Area;

    Front := Front + Q;

  end;

end;

function TThermalModel.SurfaceLoss(UseRadiation : Boolean) : Double;
var
  Front, Back : Double;
begin

  SurfaceLosses(UseRadiation, Front, Back);

  Result := Front + Back;

end;

{ Area-weighted mean skin temperature over the whole surface, over the
  exposed part of it, or over the patch on the cushion.

  A sector with no faces in it has no mean of its own, so the
  whole-surface mean stands in. That only arises with the patient lifted
  off the cushion (ContactHalfAngleDeg = 0), where every face is exposed
  and the two answers coincide anyway - and it keeps a degenerate
  configuration from reporting a skin temperature of absolute zero. }
function TThermalModel.MeanSkinTemperature(Sector : TProfileSector) : Double;
var

  i, j : Integer;

  Tf, A : Double;

begin

  Result := 0;
  A := 0;

  for i := 0 to FNbSkin - 1 do
  begin

    if (Sector = psFront) and FSkin[i].Supported then
      Continue;

    if (Sector = psBack) and not FSkin[i].Supported then
      Continue;

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    Result := Result + Tf * FSkin[i].Area;
    A := A + FSkin[i].Area;

  end;

  if A > 0 then
    Result := Result / A
  else if Sector <> psAll then
    Result := MeanSkinTemperature(psAll);

end;

{ Rewrite the two surface conditions in place. The engine holds the
  expression objects themselves and re-reads them at every assembly, so
  this is all it takes to move a coefficient between solves. }
procedure TThermalModel.SetSurfaceCoefficients(HFront, UBack : Double);
begin

  FHConv.Clear;
  FHConv.AddExpression(-1E9, 1E9, Num(HFront), 't');

  FHPad.Clear;
  FHPad.AddExpression(-1E9, 1E9, Num(UBack), 't');

end;

{ Take the drapes off the front: its coefficient drops to bare-skin
  natural convection, and radiation - which the drapes were standing in
  for - becomes an explicit boundary condition of its own. The
  expression object is the one already handed to the engine, so
  rewriting it is enough; the assembly re-reads it every step.

  Nothing here touches the cushion. The patient does not get up off it
  at induction, so the contact patch keeps the conductance it had, and
  gets no radiation condition at all - it has nothing to radiate to. }
procedure TThermalModel.Expose;
var
  i : Integer;
begin

  FHConv.Clear;
  FHConv.AddExpression(-1E9, 1E9, Num(BareConvection), 't');

  for i := 0 to FNbSkin - 1 do
    if not FSkin[i].Supported then
      FEngine.AddFaceRadiation(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FEmiss, FTinf);

end;

procedure TThermalModel.PostProcess;
var

  E, dt, Now_, LossFront, LossBack : Double;

begin

  Now_ := FEngine.Time;

  dt := Now_ - FTimePrev;

  E := TotalEnergy;

  if FNbHist >= Length(FHistT) then
  begin
    SetLength(FHistT, Length(FHistT) + 256);
    SetLength(FHistCore, Length(FHistT));
    SetLength(FHistSkin, Length(FHistT));
    SetLength(FHistSkinB, Length(FHistT));
    SetLength(FHistLoss, Length(FHistT));
    SetLength(FHistLossB, Length(FHistT));
    SetLength(FHistStore, Length(FHistT));
    SetLength(FHistTArt, Length(FHistT));
    SetLength(FHistPerf, Length(FHistT));
  end;

  SurfaceLosses(FCase = CaseExposed, LossFront, LossBack);

  FHistT[FNbHist] := Now_;
  FHistCore[FNbHist] := FEngine.Temperature[FCoreNode] - Kelvin;
  FHistSkin[FNbHist] := MeanSkinTemperature(psFront) - Kelvin;
  FHistSkinB[FNbHist] := MeanSkinTemperature(psBack) - Kelvin;
  FHistLoss[FNbHist] := LossFront + LossBack;
  FHistLossB[FNbHist] := LossBack;

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

  // Every fifth minute, keep the whole field for the gmsh animation.
  // Rounded rather than compared as reals: the times are exact
  // multiples of the step, but only once they have been through the
  // engine's own accumulation.
  if Round(Now_) mod Round(SnapshotSeconds) = 0 then
    TakeSnapshot(Now_);

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

  // Thickness is quoted both ways round the section: similar ellipses
  // are not parallel curves, so a layer is thinner over the front and
  // back than at the sides, by exactly the axis ratio.
  Say('  compartment    mass    volume   outer s   thickness (mm)      power   generation');
  Say('                 (kg)       (L)      (mm)    major    minor       (W)      (W/m3)');

  for i := 0 to NbLayers - 1 do
    Say(Format('  %-10s %7.2f %9.2f %9.2f %8.2f %8.2f %9.1f %11.0f',
      [Layers[i].Name, Layers[i].Mass, FLayerVol[i] * 1000,
       FLayerA[i] * 1000,
       1000 * (FLayerA[i] - IfThen(i = 0, 0, FLayerA[Max(i - 1, 0)])),
       1000 * AspectRatio *
         (FLayerA[i] - IfThen(i = 0, 0, FLayerA[Max(i - 1, 0)])),
       FLayerPower[i], FLayerGen[i]]));

  Cap := 0;

  for i := 0 to NbLayers - 1 do
    Cap := Cap + Layers[i].Mass * Layers[i].Cp;

  Say('');
  Say(Format('  Equivalent ellipse       : %6.1f x %.1f mm semi-axes, length %.2f m',
    [FSemiMajor * 1000, FSemiMinor * 1000, FLength]));
  Say(Format('  Axis ratio               : %8.2f  (1.0 is the circular cylinder',
    [AspectRatio]));
  Say('                                       this model began as)');
  Say(Format('  Surface nominal / meshed : %8.3f m2 / %.3f m2',
    [BodySurfaceArea, FMeshArea]));
  Say(Format('  Heat capacity            : %8.0f kJ/K', [Cap / 1000]));
  Say('');
  Say(Format('  Ambient                  : %8.1f C', [AmbientC]));
  Say('');
  Say(Format('  On the cushion           : %8.3f m2 (%.0f%% of the surface), within',
    [FMeshAreaBack, 100 * FMeshAreaBack / FMeshArea]));
  Say(Format('                                       %.0f deg of straight down',
    [ContactHalfAngleDeg]));
  Say(Format('  Exposed to the room      : %8.3f m2 (%.0f%%)',
    [FMeshAreaFront, 100 * FMeshAreaFront / FMeshArea]));
  Say(Format('  Cushion conductance      : %8.3f W/m2K  (%.0f mm of foam at %.3f',
    [FUPad, PadThickness * 1000, PadConductivity]));
  Say(Format('                                       W/mK, then %.1f W/m2K beneath)',
    [PadUnderside]));
  Say('');
  Say(Format('  Uniform-surface balance  : %8.2f W/m2K  (no cushion - the analytic',
    [FHBalance]));
  Say('                                       reference, not the model''s own)');

  if FCase = CaseExposed then
    Say(Format('  Exposed at t=0           : %8.2f W/m2K convection + radiation e=%.2f',
      [BareConvection, SkinEmissivity]))
  else
    Say('  Exposed at t=0           :      no - the draped state is held');

  Say(Format('  Mesh                     : %8d nodes, %d elements, %d skin faces',
    [FGmsh.NbNodes, FGmsh.NbElements, FNbSkin]));

end;

{ The model's check on itself: one static solve with a UNIFORM surface
  coefficient and no cushion, compared layer by layer with the closed
  form SetupGeometry integrated.

  The reference configuration is not an evasion, it is the point. The
  analytic chain describes a body losing heat evenly all over; with the
  cushion under it the model no longer is one, and comparing the two
  would only measure the cushion. Run it uniform and the chain is
  entitled to be right, so anything beyond ordinary discretisation means
  the compartments, the generation split, the shape constants or the 3D
  elements are not doing what it assumes.

  The last column is what the chain cannot see. It is the spread of
  temperature among the nodes sitting on one similar ellipse, which on a
  circle is mesh noise and on an ellipse is the real two-dimensional
  part of the field - the section is one-dimensional in s only to the
  extent that this stays small. }
procedure TThermalModel.VerifyAgainstAnalytic;
const
  // The band of s counted as sitting on a boundary.
  BandTol = 0.0002;
var

  i, j, n : Integer;

  TSum, TLo, THi, TFE, TAn, Centre, Skin, Spread : Double;

begin

  Say('');
  Say('================ CHECK AGAINST THE CLOSED FORM ================');

  SetSurfaceCoefficients(FHBalance, FHBalance);

  FEngine.CalcTemperature(caStatic, False);

  Centre := FEngine.Temperature[FCoreNode] - Kelvin;
  Skin := MeanSkinTemperature(psAll) - Kelvin;

  FUniformDrop := Centre - Skin;
  FUniformSpread := 0;

  Say(Format('  A uniform %.3f W/m2K over the whole surface, cushion lifted away',
    [FHBalance]));
  Say('  - the one configuration the closed form describes.');
  Say('');
  Say('  boundary          s (mm)     FE (C)  analytic (C)   diff (K)  spread (K)');

  Say(Format('  %-14s %8.2f %10.3f %13.3f %10.3f %11s',
    ['centre', 0.0, Centre, CoreSetPointC, Centre - CoreSetPointC, '-']));

  for i := 0 to NbLayers - 1 do
  begin

    n := 0;
    TSum := 0;
    TLo := MaxDouble;
    THi := -MaxDouble;

    for j := 0 to FEngine.NbNodes - 1 do
      if Abs(FNodeS[j] - FLayerA[i]) < BandTol then
      begin

        Inc(n);
        TSum := TSum + FEngine.Temperature[j];

        if FEngine.Temperature[j] < TLo then
          TLo := FEngine.Temperature[j];

        if FEngine.Temperature[j] > THi then
          THi := FEngine.Temperature[j];

      end;

    if n = 0 then
      Continue;

    TFE := TSum / n - Kelvin;
    TAn := CoreSetPointC - FLayerDrop[i];
    Spread := THi - TLo;

    if Spread > FUniformSpread then
      FUniformSpread := Spread;

    Say(Format('  %-14s %8.2f %10.3f %13.3f %10.3f %11.3f',
      [Layers[i].Name + ' out', FLayerA[i] * 1000, TFE, TAn, TFE - TAn, Spread]));

  end;

  Say('');
  Say(Format('  Centre to skin: %.3f K by the model, %.3f K by the layered closed',
    [FUniformDrop, FAnalyticDrop]));
  Say('  form, which integrates the exact solid-ellipse solution across the');
  Say('  generating core and the shell solution with internal generation across');
  Say('  each layer beyond it, both written with the shape constants pi*k and');
  Say('  pi*(1+k^2)/k in place of the circle pi and 2*pi.');
  Say('');
  Say(Format('  Worst spread around one similar ellipse: %.3f K.',
    [FUniformSpread]));

  if SameValue(AspectRatio, 1.0) then
  begin
    Say('  At an axis ratio of 1 both of those are discretisation error and');
    Say('  nothing else - the chain is exact on a circle, and this is the check');
    Say('  that the elliptical generalisation did not disturb it.');
  end
  else
  begin
    Say('  Neither of those is discretisation error. The chain shorts every');
    Say('  similar ellipse to a single temperature, and the spread is what it is');
    Say('  shorting out; doing so puts the thick side of the section in parallel');
    Say('  with the thin one, which can only UNDERSTATE the resistance, so the');
    Say('  model must come out with the larger centre-to-skin drop of the two -');
    Say('  as it does, by about a fifth at an axis ratio of 0.5. Set AspectRatio');
    Say('  to 1 and both columns collapse to a few thousandths of a kelvin,');
    Say('  which is the check that the shape constants themselves are right.');
  end;

end;

{ Find the drape coefficient that leaves the body in balance at the core
  set point, with the cushion in place.

  The old model read this straight off the analytic chain, which it
  could because the surface was uniform: one coefficient, one surface
  temperature, one equation. It cannot now. The exposed front and the
  patch on the foam sit at quite different temperatures and take quite
  different shares of the output, and no closed form of this layer chain
  knows anything about that.

  So it is calibrated on the finite-element model itself. The draped
  problem is linear - conduction, and convection at the surface, with no
  radiation yet - so the body is exactly a fixed internal resistance in
  series with a surface conductance:

    Tcore = Tinf + Q*(Rint + 1/(h*Afront + U*Aback))

  One static solve gives Rint, the next h follows from it, and because
  Rint moves only as far as the flux split between front and back
  shifts, this converges in two or three solves rather than by
  bisection. Each solve is cheap next to the transient that follows. }
procedure TThermalModel.CalibrateDraped;
const
  MaxIterations = 12;
  CoreTolerance = 0.001;      // K
var

  i : Integer;

  h, Target, Tinf, Tcore, GSurf, RInt, GNeed : Double;

begin

  Say('');
  Say('================ THE DRAPED COEFFICIENT ================');

  if FMeshAreaFront <= 0 then
    raise Exception.Create('The whole surface is on the cushion - there is ' +
      'nothing left to balance the body through. Reduce ContactHalfAngleDeg.');

  Target := CoreSetPointC + Kelvin;
  Tinf := AmbientC + Kelvin;

  // The uniform-surface value is the natural first guess: exactly right
  // in the limit of no cushion, and too low otherwise.
  h := FHBalance;

  FNbCalibrations := 0;

  Say('  solve   h (W/m2K)    core (C)');

  for i := 1 to MaxIterations do
  begin

    SetSurfaceCoefficients(h, FUPad);

    FEngine.CalcTemperature(caStatic, False);

    Inc(FNbCalibrations);

    Tcore := FEngine.Temperature[FCoreNode];

    Say(Format('  %5d %11.3f %11.3f', [i, h, Tcore - Kelvin]));

    if Abs(Tcore - Target) < CoreTolerance then
      Break;

    GSurf := h * FMeshAreaFront + FUPad * FMeshAreaBack;

    RInt := (Tcore - Tinf) / FHeatOutput - 1 / GSurf;

    GNeed := 1 / ((Target - Tinf) / FHeatOutput - RInt);

    if GNeed <= FUPad * FMeshAreaBack then
      raise Exception.Create('The cushion alone already loses more than the ' +
        'body generates at the set point - no drape coefficient can balance ' +
        'it. Check PadThickness and ContactHalfAngleDeg.');

    h := (GNeed - FUPad * FMeshAreaBack) / FMeshAreaFront;

  end;

  FHDraped := h;

  Say('');
  Say(Format('  Draped coefficient       : %8.3f W/m2K over the exposed %.0f%%',
    [FHDraped, 100 * FMeshAreaFront / FMeshArea]));
  Say(Format('  Uniform-surface value    : %8.3f W/m2K  (what it would take with',
    [FHBalance]));
  Say('                                       the patient off the cushion)');
  Say(Format('  Converged in             : %8d static solves', [FNbCalibrations]));

  if Abs(FEngine.Temperature[FCoreNode] - Target) >= CoreTolerance then
    Say(Format('  NOT converged - the core is %.3f C, wanted %.3f C',
      [FEngine.Temperature[FCoreNode] - Kelvin, CoreSetPointC]));

end;

{ The profile from the centre outward, front and back, at t = 0 and at
  the end of the run.

  One curve would do for a body losing heat evenly all over. With 100 mm
  of foam under a third of it, the front and the back are thermally
  different bodies, and the gap between them - there already in the
  balanced starting state, before the drapes ever come off - is what the
  cushion does. }
procedure TThermalModel.ReportProfile;

  // The profile value nearest a given s, in mm.
  function At(const Sc, T : TVMobj; sWant : Double) : Double;
  var
    j, jBest : Integer;
    Best, d : Double;
  begin

    Best := MaxDouble;
    jBest := 0;

    for j := 0 to Sc.Cols - 1 do
    begin

      d := Abs(Sc[0, j] - sWant);

      if d < Best then
      begin
        Best := d;
        jBest := j;
      end;

    end;

    Result := T[0, jBest];

  end;

var

  i : Integer;

  SF, F0, FE, SB, B0, BE : TVMobj;

  sWant, sSkin : Double;

begin

  GetRadialProfiles(psFront, SF, F0, FE);
  GetRadialProfiles(psBack, SB, B0, BE);

  Say('');
  Say('================ PROFILE, FRONT AND BACK ================');
  Say(Format('  %d points to the front and %d to the back, grouped by s and',
    [SF.Cols, SB.Cols]));
  Say('  taken within 30 degrees of straight up and of straight down.');
  Say('');
  Say('  boundary          s (mm)   front t=0    back t=0   front end    back end');

  Say(Format('  %-14s %8.2f %11.3f %11.3f %11.3f %11.3f',
    ['centre', 0.0, F0[0, 0], B0[0, 0], FE[0, 0], BE[0, 0]]));

  for i := 0 to NbLayers - 1 do
  begin

    sWant := FLayerA[i] * 1000;

    Say(Format('  %-14s %8.2f %11.3f %11.3f %11.3f %11.3f',
      [Layers[i].Name + ' out', sWant,
       At(SF, F0, sWant), At(SB, B0, sWant),
       At(SF, FE, sWant), At(SB, BE, sWant)]));

  end;

  sSkin := FSemiMajor * 1000;

  Say('');
  Say(Format('  The skin is %.2f K warmer at the back than at the front before the',
    [At(SB, B0, sSkin) - At(SF, F0, sSkin)]));
  Say(Format('  run starts, and %.2f K warmer at the end of it. That gap is the',
    [At(SB, BE, sSkin) - At(SF, FE, sSkin)]));
  Say('  cushion: the same tissue, the same generation, and an order of magnitude');
  Say('  between what the two of them are losing heat into.');

  if At(SB, B0, FLayerA[LayerCore] * 1000) > F0[0, 0] then
  begin
    Say('');
    Say('  Note that the back of the core runs warmer than the centre itself.');
    Say('  With the cushion under it the temperature maximum is displaced');
    Say('  backwards, so the geometric centre - which is what this model reports');
    Say('  as the core, and what the calibration holds at the set point - is no');
    Say('  longer the hottest point in the body.');
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
  Say(Format('  Generation is %.1f W throughout; the skin columns are the exposed',
    [Gen]));
  Say('  front and the patch on the cushion, area-weighted, and "via pad" is the');
  Say('  part of the loss that goes out through the foam.');
  Say('');
  Say('    time    core   front    back    pool       lost   via pad      stored   balance     perf');
  Say('   (min)     (C)     (C)     (C)     (C)        (W)       (W)         (W)       (W)      (W)');

  for i := 0 to FNbHist - 1 do
  begin

    if (i mod ReportEvery <> 0) and (i <> FNbHist - 1) then
      Continue;

    Bal := Gen - FHistLoss[i] - FHistStore[i];

    Say(Format('  %6.1f  %6.2f  %6.2f  %6.2f  %6.2f %10.1f %9.2f  %10.1f %9.2f %8.3f',
      [FHistT[i] / 60, FHistCore[i], FHistSkin[i], FHistSkinB[i], FHistTArt[i],
       FHistLoss[i], FHistLossB[i], FHistStore[i], Bal, FHistPerf[i]]));

  end;

  Say('');

  if FNbHist > 0 then
  begin

    Say(Format('  Core %.2f C -> %.2f C over %.0f min  (%.2f C, %.2f C/h)',
      [FHistCore[0], FHistCore[FNbHist - 1], FHistT[FNbHist - 1] / 60,
       FHistCore[FNbHist - 1] - FHistCore[0],
       (FHistCore[FNbHist - 1] - FHistCore[0]) / (FHistT[FNbHist - 1] / 3600)]));

    Say(Format('  Skin, front %.2f C -> %.2f C,  back %.2f C -> %.2f C',
      [FHistSkin[0], FHistSkin[FNbHist - 1],
       FHistSkinB[0], FHistSkinB[FNbHist - 1]]));

    if FHistLoss[FNbHist - 1] <> 0 then
      Say(Format('  Of the %.1f W leaving at the end, %.1f W goes through the cushion' +
        ' (%.0f%%)',
        [FHistLoss[FNbHist - 1], FHistLossB[FNbHist - 1],
         100 * FHistLossB[FNbHist - 1] / FHistLoss[FNbHist - 1]]));

  end;

  Say('');
  Say('  The balance column is generation minus surface loss minus the rate of');
  Say('  change of stored energy, and should be zero: it is the model checking');
  Say('  its own first law, the way the arch examples check thrust against');
  Say('  weight. Stored is computed from the nodal temperatures and the lumped');
  Say('  heat capacities, loss from the skin faces, so the two are independent.');

end;

{ The temperature profile from the centre outward, at t=0 and as it now
  stands, for the whole section or for the front or back of it alone.

  The coordinate is s, the semi-major axis of the similar ellipse
  through a node - the plain radius at an axis ratio of 1, and the
  coordinate every compartment boundary is a level set of either way.

  What has changed with the cushion is that ONE curve is no longer the
  whole result. The old circular model was symmetric by construction -
  uniform generation, a uniform lateral boundary condition, adiabatic
  ends - so the field collapsed without loss to a single curve. An
  insulated back and an exposed front break that, and the difference
  between the two is the effect being modelled, so the caller asks for
  a sector: psFront takes the nodes within ProfileHalfAngleDeg of
  straight up, psBack those within the same angle of straight down, and
  psAll everything, which is still the right thing to plot when the
  surface is uniform.

  Nodes near the centre belong to every sector: there is no front or
  back within a few millimetres of the middle, and dropping them would
  leave each curve starting nowhere in particular.

  Nodes are grouped by s rather than plotted raw. The fat's structured
  layers sit at a few exact values of s and must stay distinct, since
  the steepest gradient is across them; the unstructured core scatters
  its nodes over every s and needs averaging or the curve is a band
  rather than a line. Grouping to a tolerance well under a fat layer
  does both. Residual spread within a group is now real - it is the
  section's departure from being one-dimensional in s - and
  VerifyAgainstAnalytic measures it. }

procedure TThermalModel.GetRadialProfiles(Sector : TProfileSector;
                                          out S, T0, TEnd : TVMobj);
const
  // Well under the thinnest structured layer's node spacing - 1.13 mm
  // in the skin - so those stay resolved.
  GroupTol = 0.0002;

  // Inside the core the mesh is unstructured and 6 mm coarse, so a
  // 0.2 mm band catches only a node or two, and once a sector is asked
  // for it catches a fraction of one. Since the field is genuinely
  // two-dimensional there, whichever few angles a band happens to
  // contain sets its mean, and the curve comes out visibly ragged for
  // no better reason than which nodes fell where. A wider band inside
  // the core averages that away; there is no thin layer in there to
  // lose by it.
  CoreGroupTol = 0.0020;

  // Half-width of the front and back sectors. Wider takes in more nodes
  // per band, but the field varies with angle as well as with s, so a
  // wide sector averages over a real spread of temperatures and which
  // angles a band happens to contain then shows up as a wobble along
  // the curve. 15 degrees is the compromise: enough nodes to average,
  // narrow enough that what they are averaging is nearly one value.
  ProfileHalfAngleDeg = 15.0;
var

  i, j, n, m : Integer;

  Idx : Array of Integer;

  tmp : Integer;

  sSum, t0Sum, tESum, Ang, HalfAngle, Near, Tol : Double;

  Sv, T0v, TEv : TDoubleArray;

  Take : Boolean;

begin

  HalfAngle := DegToRad(ProfileHalfAngleDeg);

  // Inside this, a node counts as central and goes into every sector.
  Near := 2 * CoreMeshSize;

  // Index sort by s - insertion sort over an index array, which is
  // ample for a few thousand nodes and keeps the node data untouched.
  SetLength(Idx, FEngine.NbNodes);

  n := 0;

  for i := 0 to FEngine.NbNodes - 1 do
  begin

    if (Sector = psAll) or (FNodeS[i] <= Near) then
      Take := True
    else
    begin

      Ang := ArcTan2(FEngine.CoordY[i] / AspectRatio, FEngine.CoordX[i]);

      if Sector = psFront then
        Take := Abs(Ang - Pi / 2) <= HalfAngle
      else
        Take := Abs(Ang + Pi / 2) <= HalfAngle;

    end;

    if Take then
    begin
      Idx[n] := i;
      Inc(n);
    end;

  end;

  SetLength(Idx, n);

  for i := 1 to n - 1 do
  begin

    tmp := Idx[i];
    j := i - 1;

    while (j >= 0) and (FNodeS[Idx[j]] > FNodeS[tmp]) do
    begin
      Idx[j + 1] := Idx[j];
      Dec(j);
    end;

    Idx[j + 1] := tmp;

  end;

  SetLength(Sv, n);
  SetLength(T0v, n);
  SetLength(TEv, n);

  m := 0;
  i := 0;

  while i < n do
  begin

    j := i;
    sSum := 0;
    t0Sum := 0;
    tESum := 0;

    // Well clear of the innermost boundary, where the mesh turns
    // structured and the layers get thin?
    if FNodeS[Idx[i]] < FLayerA[LayerCore] - 2 * CoreGroupTol then
      Tol := CoreGroupTol
    else
      Tol := GroupTol;

    // Everything within that of where this group started.
    while (j < n) and (FNodeS[Idx[j]] - FNodeS[Idx[i]] <= Tol) do
    begin

      sSum := sSum + FNodeS[Idx[j]];
      t0Sum := t0Sum + FTInitial[Idx[j]];
      tESum := tESum + FEngine.Temperature[Idx[j]];

      Inc(j);

    end;

    Sv[m] := 1000 * sSum / (j - i);       // mm, for a readable axis
    T0v[m] := t0Sum / (j - i) - Kelvin;   // C
    TEv[m] := tESum / (j - i) - Kelvin;

    Inc(m);

    i := j;

  end;

  S := TVMobj.Create(1, m);
  T0 := TVMobj.Create(1, m);
  TEnd := TVMobj.Create(1, m);

  for i := 0 to m - 1 do
  begin
    S[0, i] := Sv[i];
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

    WriteLn(F, 'time_s,time_min,core_C,skin_front_C,skin_back_C,generated_W,' +
               'lost_W,lost_pad_W,stored_W,balance_W');

    for i := 0 to FNbHist - 1 do
      WriteLn(F, Format('%.1f,%.4f,%.4f,%.4f,%.4f,%.3f,%.3f,%.3f,%.3f,%.3f',
        [FHistT[i], FHistT[i] / 60, FHistCore[i], FHistSkin[i], FHistSkinB[i],
         FHeatOutput, FHistLoss[i], FHistLossB[i], FHistStore[i],
         FHeatOutput - FHistLoss[i] - FHistStore[i]], DotFS));

  finally

    CloseFile(F);

  end;

end;

{ Keep the whole temperature field as it stands, for the gmsh animation.

  Celsius, not Kelvin: this is the only thing in the model that leaves
  as a picture rather than a number, and a colour scale reading 305 to
  310 K tells a clinician nothing. }
procedure TThermalModel.TakeSnapshot(AtTime : Double);
var
  i : Integer;
begin

  if FNbSnap >= Length(FSnapTime) then
  begin
    SetLength(FSnapTime, FNbSnap + 32);
    SetLength(FSnap, FNbSnap + 32);
  end;

  SetLength(FSnap[FNbSnap], FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
    FSnap[FNbSnap][i] := FEngine.Temperature[i] - Kelvin;

  FSnapTime[FNbSnap] := AtTime;

  Inc(FNbSnap);

end;

function TThermalModel.SnapshotCount : Integer;
begin

  Result := FNbSnap;

end;

{ The run as a numbered series of gmsh views, ONE FRAME PER FILE.

  A single view carrying 25 time steps would animate in gmsh too, and
  would be a good deal smaller. Separate files are written instead so
  that the run is a set of similarly named files - thermex1_000.pos to
  thermex1_024.pos, zero-padded so they sort and match as one pattern -
  which is what gmsh's own file-pattern merging takes
  (General.WatchFilePattern = "thermex1_*.pos"), and what lets the whole
  series be brought in by a shell glob or by multi-selecting it under
  File > Merge.

  Worth knowing, since it is the obvious thing to try: opening
  thermex1_000.pos on its own does NOT pull the rest in. Tested on gmsh
  4.15.2, which has no "load all files with similar names" prompt of the
  kind some tools offer. The script below therefore names all 25
  explicitly, which needs no such feature and is what the View button
  opens.

  Each file is about 2.7 MB - the parsed .pos format repeats all 24
  vertex coordinates of every hexahedron in every frame - so the series
  comes to some 70 MB in Examples/Data. That is the price of the format,
  not of the model.

  Any higher-numbered files left over from a longer previous run are
  deleted, or the similar-name prompt would sweep them back in and the
  animation would end on frames from another solve. }
procedure TThermalModel.WriteViewFiles;
var

  i : Integer;

  FileName : String;

begin

  for i := 0 to FNbSnap - 1 do
  begin

    FileName := Format('%s%.3d.pos', [ViewPrefix, i]);

    FGmsh.OpenFile(FileName);

    FGmsh.WriteViewScalarNode(
      Format('T (C) at %.0f min', [FSnapTime[i] / 60]), FSnap[i], True);

    FGmsh.Close;

  end;

  i := FNbSnap;

  while FileExists(Format('%s%.3d.pos', [ViewPrefix, i])) do
  begin
    DeleteFile(Format('%s%.3d.pos', [ViewPrefix, i]));
    Inc(i);
  end;

end;

{ The gmsh script that opens the series: merge every frame, put them all
  on ONE colour scale, and set gmsh to animate by stepping through views
  rather than through time steps within a view.

  The common scale is the part that matters. Left to itself gmsh
  normalises each view to its own range, so every frame would be drawn
  with the same colours over a range that shrinks as the body cools, and
  a run that loses four degrees would look like a run that does nothing.
  Fixing CustomMin/CustomMax across all of them is what makes the
  animation show the cooling.

  No camera is set beyond squaring it up. The body is an extrusion along
  z with nothing varying axially, and gmsh's default view looks straight
  down z - so what faces the viewer is the elliptical section itself,
  which is the whole of the result. }
procedure TThermalModel.WriteViewScript(const FileName : String);
var

  F : TextFile;

  i, j : Integer;

  Lo, Hi : Double;

begin

  Lo := MaxDouble;
  Hi := -MaxDouble;

  for i := 0 to FNbSnap - 1 do
    for j := 0 to Length(FSnap[i]) - 1 do
    begin
      if FSnap[i][j] < Lo then Lo := FSnap[i][j];
      if FSnap[i][j] > Hi then Hi := FSnap[i][j];
    end;

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    WriteLn(F, '// Generated by ThermEx1 - do not edit, it is rewritten every');
    WriteLn(F, '// time the View button is pressed.');
    WriteLn(F, '//');
    WriteLn(F, Format('// %d frames, %.0f minutes apart, of case %d at %.1f L/min.',
      [FNbSnap, SnapshotSeconds / 60, FCase, FCardiacOutput]));
    WriteLn(F);

    for i := 0 to FNbSnap - 1 do
      WriteLn(F, Format('Merge "thermex1_%.3d.pos";', [i]));

    WriteLn(F);
    WriteLn(F, '// One scale for every frame. Without this each view normalises to');
    WriteLn(F, '// its own range and the cooling becomes invisible.');
    WriteLn(F, 'For i In {0:PostProcessing.NbViews-1}');
    WriteLn(F, '  View[i].RangeType = 2;   // custom');
    WriteLn(F, '  View[i].CustomMin = ' + Num(Lo) + ';');
    WriteLn(F, '  View[i].CustomMax = ' + Num(Hi) + ';');
    WriteLn(F, '  View[i].Visible = 0;');
    WriteLn(F, 'EndFor');
    WriteLn(F);
    WriteLn(F, 'View[0].Visible = 1;');
    WriteLn(F);
    WriteLn(F, '// Animate by stepping through the views, not through time steps');
    WriteLn(F, '// inside one view: each frame is its own view here, with a single');
    WriteLn(F, '// step in it. Press play in the status bar to run it, or the');
    WriteLn(F, '// buttons either side of play to step frame by frame; the up and');
    WriteLn(F, '// down arrow keys move from view to view as well. (The LEFT and');
    WriteLn(F, '// RIGHT arrows step time steps within a view, so they do nothing');
    WriteLn(F, '// here.)');
    WriteLn(F, 'PostProcessing.AnimationCycle = 1;');
    WriteLn(F, 'PostProcessing.AnimationDelay = 0.2;');
    WriteLn(F);
    WriteLn(F, '// Square on to the section - the body does not vary along its');
    WriteLn(F, '// length, so this is the whole picture.');
    WriteLn(F, 'General.RotationX = 0;');
    WriteLn(F, 'General.RotationY = 0;');
    WriteLn(F, 'General.RotationZ = 0;');
    WriteLn(F, 'General.Trackball = 0;');

  finally

    CloseFile(F);

  end;

end;

{ Write the frames and open gmsh on them. Called from the View button. }
procedure TThermalModel.ShowInGmsh;
var
  ExitCode : Cardinal;
begin

  if FNbSnap = 0 then
    raise Exception.Create('There is nothing to view yet - the model has ' +
      'not been run.');

  WriteViewFiles;

  WriteViewScript(ScrFile);

  WriteLn(Format('%d gmsh views written, %s000.pos upward.',
    [FNbSnap, ViewPrefix]));

  if not Sto_ShellExecute(GmshExecutable, [ScrFile], ExitCode) then
    raise Exception.Create('Could not run gmsh (' + GmshExecutable +
      '). Install gmsh, or edit GmshExecutable in uThermEx1.pas.');

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

  LossFront, LossBack : Double;

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
  // The closed-form check runs first, in the uniform configuration it
  // describes; the calibration then overwrites that field with the one
  // the run actually starts from.
  VerifyAgainstAnalytic;

  CalibrateDraped;

  SurfaceLosses(False, LossFront, LossBack);

  Say('');
  Say(Format('  Draped steady state: core %.2f C, skin %.2f C at the front and',
    [FEngine.Temperature[FCoreNode] - Kelvin, MeanSkinTemperature(psFront) - Kelvin]));
  Say(Format('  %.2f C on the cushion, losing %.1f W to the room and %.1f W through',
    [MeanSkinTemperature(psBack) - Kelvin, LossFront, LossBack]));
  Say(Format('  the foam, against %.1f W generated.', [FHeatOutput]));

  SetLength(FTInitial, FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
    FTInitial[i] := FEngine.Temperature[i];

  // Frame zero of the gmsh animation is this state - the balanced one
  // the run starts from, before either the drapes or the blood.
  FNbSnap := 0;

  TakeSnapshot(0);

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
  Say(Format('%d frames %.0f min apart held for the gmsh view.',
    [FNbSnap, SnapshotSeconds / 60]));

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
