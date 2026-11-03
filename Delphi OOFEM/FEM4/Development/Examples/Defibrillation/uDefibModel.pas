unit uDefibModel;

{ Defibrillation - how the current of a 200 J monophasic shock spreads
  through a human torso, by finite elements on ThermEx1's trunk.

  THE TORSO

  The trunk of ThermEx1 (Examples/ThermEx1/uThermEx1.pas), its masses
  taken from that unit's own tables rather than copied numbers: the
  70 kg, 1.75 m, 5 % fat adult, whose trunk holds 50.8 % of the body
  mass in four compartments - core, muscle, fat and skin. ThermEx1 makes
  that trunk one elliptical cylinder; here it is a thorax on an abdomen,
  shaped from adult male anthropometry:

    abdomen  an elliptical cylinder AbdomenLength (0.43 m) from the
             perineum to the diaphragm, its depth TrunkAspect (0.72) of
             its breadth, as a man's waist is
    thorax   a truncated cone ThoraxLength (0.25 m) long, its base the
             diaphragm, where it meets the abdomen without a step, and
             its apex the root of the neck, whose section is NeckRatio
             (half) the diaphragm's

  The diaphragm is taken as flat, at the mean of its dome and its
  attachments to the costal margin. The size of the sections follows
  from the trunk's volume, so the masses are ThermEx1's: 323 mm wide by
  233 deep at the waist and 162 by 116 at the neck, 25.4 litres of
  abdomen and 8.6 of thorax. The cone is
  the thoracic cage and its wall; the shoulders and their broad girdle
  of muscle above the upper chest are left out with the arms.

  The compartments are similar ellipses sized by their masses, as in
  ThermEx1: about 12 mm of muscle, 3 mm of fat and 2 mm of skin at the
  sides, less in proportion at the front and back. Round the cone they
  keep those thicknesses all the way up, and only the core narrows.

  THE BODY'S SIZE

  Height and Weight (--height, --weight) change that man. The body's
  fat-free mass is Al-Sallami's (uBodyStats.freeFatMass, a man of
  BodyAge), which puts ThermEx1's 70 kg, 1.75 m man at 56 kg fat-free and
  20 % fat. Only his 3.5 kg of subcutaneous fat is a compartment; the rest
  of his fat is lumped into core and muscle. Another body is ThermEx1's
  plus the differences in fat-free mass and in fat from that man:

    lean   the trunk takes its mass share (50.8 %) of the change in
           fat-free mass: skin in proportion to the DuBois surface area,
           the rest shared between core and muscle as they already are
    fat    the trunk's fat layer takes TrunkFatShare (half) of the change
           in fat, since a man puts on fat mostly round the trunk
    length the abdomen and thorax in proportion to height

  The organs, ribs and pads keep their sizes and their distances below
  the root of the neck. A 120 kg, 1.80 m man (BMI 37, 37 % fat) gets a
  trunk of 60 litres, 425 x 306 mm at the waist, with 33 mm of fat at the
  side against 3 mm. His resistance is 131 ohm against 71, the fat
  taking 62 % of the power against 16 %, and the heart's share is 8.6 %
  against 11.2 %, with a mean myocardial field at the peak of 18 V/cm
  against 36. The fat is as thick over the chest as over the abdomen,
  where real fat is thinner, so the resistance is likely too high.

  The mesh is ThermEx1's for a cylinder - an unstructured disc of core
  extruded into prisms inside structured annuli of hexahedra - with
  finer divisions round the section and along the chest, since the pads
  are local where ThermEx1's heat flow was not. gmsh meshes that
  cylinder, and each node is then moved onto the body (ToBody):
  everything outside the core moves in by the same amount, and the core
  and chest wall shrink to fit. So the elements stay what they were
  meshed as, and only their size changes up the cone.

  For the current the core cannot stay one tissue: what the heart sees
  is decided by the low-conductivity lungs either side of it and the
  blood inside it. So three organs are placed in the chest as
  ellipsoids, and each core element whose centre lies in one takes its
  tissue:

    heart   an ellipsoid tilted down, forwards and to the left, its long
            axis base to apex, resting just above the diaphragm;
            myocardium 12 mm thick round a blood cavity of the same shape
    lungs   one either side, from the apex of the cone down to the
            diaphragm; the left one also wrapped LungWrapDepth round the
            heart's left side, front and back (InLungWrap), leaving the
            cardiac notch in front, the mediastinum behind and the
            diaphragm below as core

  The wrap matters little. The plain left lung already makes 69 % of
  what lies within 10 mm of the heart, the wrap 71 %, and wrapping every
  side but the diaphragm 88 % - and the heart's share of the current
  goes from 12.9 % to 12.9 % and 12.7 % (with the lung at 0.08 S/m, as
  it then was). Against the core's 0.15 the lung is too poor an
  insulator, in a layer this thin, to steer the current round the heart.
  The lung's own conductivity does more. 0.08, 0.04 (now the default,
  for inflated lung) and 0.02 S/m give a heart share of 12.9, 11.2 and
  9.3 % and a resistance of 66.2, 70.8 and 74.2 ohm. The mean myocardial
  field falls from 42.5 to 36.1 and 30.3 V/cm, while its maximum, at the
  heart's surface beside the lung, rises from 103 to 133 and 159 V/cm.

  At the 7 mm element size that staircases the organs' surfaces at
  element resolution and gives the ventricular wall one or two elements
  through its thickness - enough for the current around the heart, not
  for the detail within its wall.

  THE CHEST WALL AND SKELETON

  ThermEx1's muscle is only 12 mm thick at the sides and less at the
  front, so an 18 mm chest wall (muscle, 0.25 S/m) is added inside the
  core's boundary: a ring of constant thickness, meshed as one more
  structured annulus whose inner edge is a spline offset along the
  ellipse's normal. It keeps that thickness up the cone, while the core
  inside it narrows from 253 x 172 mm at the diaphragm to 92 x 56 at
  the neck. A thicker wall shunts more current round the heart, but not
  much: at 27 and 31 mm (the most the neck's curvature allows) the
  heart's share falls from 12.9 to 11.8 and 11.6 %, and the resistance
  from 66.2 to 60.8 and 59.7 ohm (lung at 0.08 S/m). Its inner 11 mm carries the skeleton, assigned element by
  element:

    ribs       twelve horizontal hoops 13 mm high at a 26 mm pitch,
               aligned with the chest's axial layers, from just below the
               root of the neck - the lower ones round the upper abdomen,
               below the diaphragm, as they are; bone, 0.02 S/m
    cartilage  the front 120 mm of ribs 1 to 10, 0.18 S/m; ribs 8 to 10,
               below the sternum, stop either side of the midline, and
               the floating ribs 11 and 12 stop at the sides
    sternum    a 36 mm plate at the front from 30 to 210 mm below the
               root of the neck
    spine      a 32 mm bone cylinder the length of the trunk, its axis
               30 mm in front of the back of the core - so leaning
               forward up the cone - through core and wall alike

  Real ribs slope down towards the front and are flattened, not
  rectangular; horizontal hoops get the gaps between them, which is
  what matters to the current.

  THE PHYSICS

  The current obeys div(sigma grad phi) = 0 in the tissue, which is the
  steady heat equation with sigma for the thermal conductivity and phi
  for the temperature. So the solver is TThermalEngine unchanged, its
  "temperature" a potential in volts and its node "heat source" a
  current in amperes.

  It is quasi-static, and that is a statement about time. Tissue at the
  frequencies in a defibrillator shock (a few hundred hertz) has
  omega*eps/sigma below 1e-2 even in fat, so charge relaxes in
  microseconds and the current pattern is set the instant the voltage
  is: it does not diffuse in from the pads. What changes over the shock
  is how much current flows, I(t), and every current density in the body
  scales with it. The model therefore solves once, for 1 A, and the time
  course is that field times I(t). What visibly spreads in the animation
  is the region where the current density exceeds a chosen level: it
  grows outward from the pad edges as I(t) rises and shrinks as it falls.

  THE PADS

  Two 80 x 120 mm self-adhesive pads in the standard anterolateral
  position: the sternal pad to the right of the upper sternum below the
  clavicle, the apex pad on the left mid-axillary line at the level of
  the apex. Each is a 1 mm sheet of metal-like conductivity (1e4 S/m)
  extruded on the skin faces it covers, which makes it an equipotential
  with no condition imposed on the skin itself - the current is free to
  crowd to the pad's edge, as it does. 1 A is injected into the sternal
  pad's sheet and the apex pad's sheet is held at 0 V, so the sternal
  pad's potential IS the transthoracic resistance in ohms. The gel and
  the skin-electrode interface are not modelled.

  The ends of the trunk, at the neck and the pelvis, are insulated, as
  they were for heat in ThermEx1: no current leaves into the head, arms
  or legs.

  THE SHOCK

  Monophasic (the default): a damped sine (Edmark/Lown), a 32 uF
  capacitor discharged through a 50 mH inductor and the device's own
  11 ohm into the patient. "200 J" is the energy setting, defined as the
  energy delivered into a 50 ohm load, so the capacitor is charged to
  store 200 J x 61/50 = 244 J (3.9 kV). The patient here is the torso's
  own computed resistance, and the current is the RLC discharge through
  it.

  Biphasic (Biphasic := True, --biphasic): a generic biphasic truncated
  exponential, not any one maker's. A 100 uF capacitor discharges
  straight into the patient, tau = R C. Phase 1 is truncated at 50 %
  tilt, t1 = tau ln 2; the bridge then reverses the pads for phase 2,
  two thirds as long, so the current steps from +I0/2 to -I0/2 and
  decays on. Both phases being fixed fractions of tau, the energy
  delivered is a fixed 1 - 2^(-10/3) = 90.1 % of what was stored,
  whatever the patient's resistance - the way such devices compensate
  for impedance - so the capacitor is charged to deliver exactly 200 J.
  The field pattern is the same for either waveform; only I(t) changes.

  CONDUCTIVITIES

  Typical low-frequency values of the kind used in torso defibrillation
  models (from Geddes and Baker's 1967 compilation and later model
  studies), isotropic by default: see TissueSigma. Skin is the least
  certain - dry stratum corneum is orders of magnitude more resistive
  than the 0.1 S/m used for gelled skin - and the core outside the heart
  and lungs lumps liver and gut into one 0.15 S/m. The lung's 0.04 S/m
  is an effective value with the air included. Air makes inflated lung
  less conductive than deflated, and published low-frequency values
  spread by a factor of two or so either way, so 0.04 (and the earlier
  0.08) are choices within that spread, not measurements.

  Anisotropic muscle (Anisotropic := True, --anisotropic): skeletal
  muscle conducts far better along its fibres than across them -
  Epstein and Foster (1983) measured about 0.52 and 0.076 S/m at low
  frequency, a ratio near 7. With the option the muscle layer and the
  chest wall take MuscleSigmaL along the fibres and MuscleSigmaT across,
  the fibres running round the trunk, horizontal and tangent to the
  section's ellipses - as pectoralis, serratus, latissimus and the
  intercostals do to a first approximation. Each such element gets its
  own tensor sigma_T I + (sigma_L - sigma_T) f f^T, f the fibre
  direction at its centre, through TThermalEngine's
  SetElementConductivityTensor. Heart and lungs stay isotropic.
  It raises the resistance from 71 to 85 ohm and the heart's share of
  the current from 11.2 to 12.6 % (66 to 80 ohm and 12.9 to 13.6 % with
  the lung at 0.08 S/m): across the fibres, which includes up
  and down the trunk, the wall now conducts less than a third as well,
  so it spreads the current along the body less and more crosses the
  core. (On ThermEx1's cylindrical trunk the change was larger, 12 to
  15 %.)

  UNITS

  SI throughout: metres, volts, amperes, siemens per metre. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math,
  newVM, newVMsparse,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.ThermalEngine,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh,
  uThermEx1,
  uBodyStats;

type

  TTissue = (tiCore, tiMuscle, tiFat, tiSkin, tiLung, tiMyocardium, tiBlood,
             tiWall, tiBone, tiCartilage, tiPad);

const

  TissueName : Array[TTissue] of String =
    ('core', 'muscle', 'fat', 'skin', 'lung', 'myocardium', 'blood',
     'chest wall', 'bone', 'cartilage', 'pad');

  // S/m - see CONDUCTIVITIES in the header.
  TissueSigma : Array[TTissue] of Double =
    (0.15, 0.25, 0.04, 0.10, 0.04, 0.25, 0.70, 0.25, 0.02, 0.18, 1.0E4);

  // The last tissue the report lists (the pads are not tissue).
  LastTissue = tiCartilage;

  // Skeletal muscle along and across its fibres, S/m (Epstein and
  // Foster 1983), for the anisotropic option.
  MuscleSigmaL = 0.52;
  MuscleSigmaT = 0.076;

  (******************** THE SHOCK ********************)

  ShockEnergy = 200.0;      // J, the setting: energy into RefLoad
  RefLoad = 50.0;           // ohm, the load the setting is defined into
  DeviceC = 32.0E-6;        // F
  DeviceL = 50.0E-3;        // H
  DeviceR = 11.0;           // ohm, the device's own series resistance

  // The biphasic truncated exponential: its capacitor, the tilt that
  // ends phase 1, and phase 2's length as a fraction of phase 1's.
  BiphasicC = 100.0E-6;     // F
  BiphasicTilt = 0.5;
  BiphasicRatio = 2.0 / 3.0;

  WaveDuration = 14.0E-3;   // s, how much of the discharge is kept
  WaveSample = 0.1E-3;      // s, one animation frame

  // The level a myocardial field is usually taken to need for
  // defibrillation, V/cm - what the report and the status line count
  // the heart against.
  DefibFieldVcm = 5.0;

  (******************** THE TORSO ********************)

  TrunkAspect = 0.72;       // depth over breadth, at every level
  AbdomenLength = 0.43;     // m, perineum to diaphragm, at RefHeight
  ThoraxLength = 0.25;      // m, diaphragm to the root of the neck, at RefHeight
  NeckRatio = 0.5;          // the neck root's section over the diaphragm's

  // The body's size (see THE BODY'S SIZE in the header). ThermEx1's
  // subject is BodyMass at RefHeight; any other size scales its trunk.
  RefHeight = 1.75;         // m
  BodyAge = 35;             // years, for the fat-free mass (Al-Sallami)
  // The share of fat above the reference man's that goes on the trunk.
  TrunkFatShare = 0.5;
  MinHeight = 1.40;
  MaxHeight = 2.20;
  MinWeight = 40.0;
  MaxWeight = 250.0;

  (******************** THE PADS ********************)

  PadWidth = 0.080;         // m, round the trunk
  PadHeight = 0.120;        // m, along it
  PadThickness = 0.001;     // m, the conducting sheet

  // Where the pads sit: the ellipse's parametric angle of the pad's
  // centre (90 deg is the front midline, below 90 the patient's right,
  // 180 the left side) and the centre's depth below the top of the trunk,
  // the root of the neck.
  SternalAngleDeg = 65.0;
  SternalDepth = 0.10;
  ApexAngleDeg = 165.0;
  ApexDepth = 0.21;

  PadAnode = 0;             // sternal: 1 A in
  PadCathode = 1;           // apex: held at 0 V

  (******************** THE CHEST WALL ********************)

  // A band of constant thickness inside the core's boundary: intercostal
  // and chest muscle, with the ribs, costal cartilages and sternum in
  // its inner part. It must stay thinner than the core ellipse's
  // smallest radius of curvature, b^2/a, all the way up the cone - about
  // 33 mm at the neck - for the inner curve to be smooth.
  WallThickness = 0.018;    // m
  WallDiv = 5;              // element divisions through it
  RibDepth = 0.011;         // m, the inner part of the wall the ribs take

  // Twelve ribs as horizontal hoops, each RibLayers axial layers of the
  // chest mesh high, one every RibPitch layers from layer RibFirstLayer
  // below ChestTop - so their edges are element boundaries.
  NbRibs = 12;
  RibLayers = 2;
  RibPitch = 4;
  RibFirstLayer = 3;
  NbTrueRibs = 10;          // ribs 11 and 12 float, stopping at the side
  FloatingRibX = 0.10;      // m, how far round the front they stop short
  CartilageX = 0.060;       // m, the front run of each rib that is cartilage

  // The sternum: a plate in the rib layer of the wall, at the front.
  SternumHalfWidth = 0.018;
  SternumTop = 0.030;       // m below the top of the trunk
  SternumBottom = 0.210;

  // The vertebral column: a cylinder through the whole trunk at the back.
  SpineRadius = 0.016;
  SpineInset = 0.030;       // m, its axis in front of the back of the core

  // The left lung's wrap round the heart (see InLungWrap): how far out
  // from the heart's surface it reaches; the x right of which it leaves
  // the heart's front bare (the cardiac notch) and its back to the
  // oesophagus and aorta; and the cosine, of the direction from the
  // heart's centre to the vertical, below which the heart sits on the
  // diaphragm instead.
  LungWrapDepth = 0.025;
  CardiacNotchX = -0.045;
  WrapBackX = -0.030;
  WrapFloorCos = -0.6;
  // How far out from the heart the report's tally of its surroundings
  // reaches.
  HeartContact = 0.010;

  (******************** THE MESH ********************)

  CircDiv = 32;             // element divisions per quadrant round the section
  CoreMeshSize = 0.007;     // m, the core disc's triangles

  // Along the trunk: coarse below the chest, fine through it, a layer
  // at the root of the neck. The fine zone runs from ChestBottom to
  // ChestTop below the top of the trunk.
  ChestTop = 0.02;
  ChestBottom = 0.384;      // 56 layers of ChestStep, so the ribs align
  ChestStep = 0.0065;
  AbdomenStep = 0.024;
  NeckStep = 0.015;

  NbFieldLines = 160;

type

  TVec3 = record
    X, Y, Z : Double;
  end;

  // An ellipsoid: centre, three unit axes and the semi-axis along each.
  TOrgan = record
    Name : String;
    C : TVec3;
    U : Array[0..2] of TVec3;
    R : Array[0..2] of Double;
  end;

  // A quadrilateral on the outside of the body or of a pad.
  TSurfFace = record
    N : Array[0..3] of Integer;
    Nx, Ny, Nz : Double;      // outward unit normal
    Area : Double;
    Ele : Integer;            // the element it belongs to
    Pad : Integer;            // -1, PadAnode or PadCathode
  end;

  TPolyline = Array of TVec3;

  TDefibModel = class(TObject)

  private

    FGmsh : TGmsh;
    FEngine : TThermalEngine;

    FLists : TList;           // every TExpressionList made, to free

    FReport : TStringList;

    FMeshDir, FGeoFile, FMshFile : String;

    // The trunk, as meshed: the cylinder of the abdomen's section. FA and
    // FB are the abdomen's, and the sections up the thorax are mapped
    // from these.
    FA, FB, FK, FLen, FCy : Double;
    FAbdLen, FThxLen : Double;                    // m, at this height
    FHeight, FWeight : Double;                    // m, kg
    FFatFree : Double;                            // kg, the body's fat-free mass
    FOuter : Array[0..NbLayers - 1] of Double;    // s of each boundary
    FArc : TDoubleArray;                          // outer ellipse arc length table
    FCoreA, FCoreB : Double;                      // the core's boundary
    FVolume : Double;                             // m3, the whole trunk

    // The wall's inner edge as meshed: the polar angle round the
    // section's centre of its point at each parametric angle.
    FInnerTh, FInnerT : TDoubleArray;

    // The nodes as gmsh meshed them, on the cylinder.
    FRefX, FRefY : TDoubleArray;

    FPadAngle, FPadZ : Array[0..1] of Double;

    // The hash grid of element centres the field lines are traced on
    FGridOrg : TVec3;
    FGridH : Double;
    FGridN : Array[0..2] of Integer;
    FCellStart, FCellItem : TIntegerArray;

    FAnisotropic, FBiphasic, FWrapLung : Boolean;
    FShockStart : Integer;    // the report's first line about the shock
    FRan : Boolean;

    procedure Say(const S : String);
    function NewList(const Expr, VarName : String) : TExpressionList;

    function S(X, Y : Double) : Double;
    function ArcAt(T : Double) : Double;

    // Depth of (X, Y) inside the meshed core ellipse along its normal,
    // and the parametric angle T of the nearest point on it.
    function FootInCore(X, Y : Double; out T : Double) : Double;

    // The parametric angle at which the wall's inner edge, as meshed,
    // lies at polar angle Theta round the section's centre.
    function InnerTAt(Theta : Double) : Double;

    // The point of the body that a node meshed at (X, Y, Z) on the
    // cylinder stands for.
    function ToBody(X, Y, Z : Double) : TVec3;
    function InPad(Pad : Integer; X, Y, Z : Double; Margin : Double) : Boolean;
    function RibAt(Z : Double) : Integer;

    procedure WriteGeoFile;
    procedure BuildMesh;
    procedure ClassifyElements;
    procedure FindSurface;
    procedure BuildEngine;
    procedure Solve;
    procedure PostProcess;
    procedure ComputeWaveform;
    procedure BuildGrid;
    function FieldAt(const P : TVec3; out J : TVec3) : Boolean;
    procedure TraceLines;
    procedure ReportResults;
    procedure SetBiphasic(V : Boolean);

    // The direction of the muscle fibres at (X, Y): horizontal, round the
    // trunk, tangent to the section's similar ellipses.
    function FibreDir(X, Y : Double) : TVec3;

    // Whether element i's conductivity is a tensor, and its current
    // density -sigma grad phi for a potential gradient Grad.
    function IsAnisotropic(i : Integer) : Boolean;
    function CurrentFrom(i : Integer; const Grad : TVec3) : TVec3;

  public

    // Nodes, tissue and pads alike
    NbNodes : Integer;
    NX, NY, NZ : TDoubleArray;
    Phi : TDoubleArray;              // V, for 1 A

    // Tissue elements (the pads' sheets are not among them)
    NbEle : Integer;
    EleTissue : Array of TTissue;
    EleC : Array of TVec3;           // centroid
    EleVol : TDoubleArray;           // m3
    EleJ : Array of TVec3;           // A/m2 for 1 A
    EleJMag : TDoubleArray;
    EleByJ : TIntegerArray;          // elements, largest |J| first

    // The outside of the body, and the outer faces of the pads
    Skin : Array of TSurfFace;
    PadFaces : Array of TSurfFace;
    PadArea : Array[0..1] of Double;

    Heart, Cavity : TOrgan;
    Lungs : Array[0..1] of TOrgan;
    // The heart grown by LungWrapDepth: the left lung's wrap is the part
    // of this shell on the heart's left, front and back (InLungWrap).
    WrapShell : TOrgan;

    // Volumes (m3) of each tissue within HeartContact of the heart.
    ContactVol : Array[TTissue] of Double;

    Resistance : Double;             // ohm, pad to pad

    // The shock
    V0 : Double;                     // V, charge
    WaveT, WaveI : TDoubleArray;     // s, A
    IPeak, TPeak, EDelivered : Double;

    // Myocardium's field per ampere, sorted ascending, and its volumes
    // in the same order - for "how much of the heart is above x V/cm".
    MyoE : TDoubleArray;             // V/m per A
    MyoVolCum : TDoubleArray;        // cumulative volume from the top
    MyoVol : Double;

    HeartFraction : Double;          // of the pad current, through the heart

    Lines : Array of TPolyline;

    constructor Create;
    destructor Destroy; override;

    // Sizes the body from ThermEx1's masses, Height and Weight, and
    // places the organs - no meshing. Run calls it first; other models
    // that share this torso (Examples/HFJV) call it alone.
    procedure SetupGeometry;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure Run;

    // Fraction of the myocardium's volume above Ecrit (V/m) at current I.
    function MyoFractionAbove(Ecrit, I : Double) : Double;

    // Volume (m3) of tissue whose |J| is at least Jcrit (A/m2) at current I.
    function VolumeAbove(Jcrit, I : Double) : Double;

    function OrganInside(const O : TOrgan; X, Y, Z : Double) : Boolean;

    // Whether a point outside the heart lies in the left lung's wrap
    // round it: within LungWrapDepth of the heart, on its left, except
    // the cardiac notch in front, the mediastinum behind and the
    // diaphragm below.
    function InLungWrap(X, Y, Z : Double) : Boolean;

    // The section at height Z: its size over the abdomen's (1 below the
    // diaphragm, NeckRatio at the root of the neck), how far in that
    // moves the skin and every compartment boundary outside the core,
    // and the core's size over the abdomen's core.
    function SectionScale(Z : Double) : Double;
    function SectionShift(Z : Double) : Double;
    function CoreScale(Z : Double) : Double;

    property A : Double read FA;
    property B : Double read FB;
    property Len : Double read FLen;
    property ThoraxLen : Double read FThxLen;
    property Cy : Double read FCy;
    property CoreA : Double read FCoreA;
    property CoreB : Double read FCoreB;

    // The point at parametric angle T of the core ellipse at height Z,
    // Depth inside that ellipse along its normal - so on the body; at
    // Z = 0, in the abdomen, it is also the cylinder as meshed. The z of
    // the result is Z.
    function WallPoint(T, Depth, Z : Double) : TVec3;

    // Depth of (X, Y) inside the core ellipse, along its normal - on the
    // cylinder as meshed, before ToBody.
    function DepthInCore(X, Y : Double) : Double;

    // The z range of rib k (0 = the first rib), and whether rib k is
    // present at section point (X, Y) - the floating ribs stop short of
    // the front - and cartilage rather than bone there.
    procedure RibBand(k : Integer; out Z0, Z1 : Double);
    function RibPresent(k : Integer; X, Y : Double) : Boolean;
    function RibCartilage(k : Integer; X, Y : Double) : Boolean;
    property Report : TStringList read FReport;

    // Set before Run, since it changes the solve.
    property Anisotropic : Boolean read FAnisotropic write FAnisotropic;
    // The left lung wrapped round the heart (default True; --no-wrap).
    property WrapLung : Boolean read FWrapLung write FWrapLung;
    // The body's height (m) and weight (kg), set before Run; ThermEx1's
    // 1.75 m and 70 kg by default (--height, --weight).
    property Height : Double read FHeight write FHeight;
    property Weight : Double read FWeight write FWeight;

    // Before or after Run. After it, the waveform and the report's shock
    // and heart sections are recomputed, without solving again.
    property Biphasic : Boolean read FBiphasic write SetBiphasic;

    // The waveform in a few words, for titles.
    function WaveName : String;

  end;

function Vec3(X, Y, Z : Double) : TVec3;

implementation

const

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  GmshExecutable = 'gmsh';
{$ENDIF}

  // Local face node numbering of a hexahedron, as in uThermEx1.pas and
  // CXS.FEMLAP.Brick_H8V1.pas.
  HexFace : Array[0..5, 0..3] of Integer =
    ((0,1,2,3), (4,5,6,7), (0,1,5,4), (1,2,6,5), (2,3,7,6), (3,0,4,7));

  ArcTableSize = 3600;

  // The chest wall's physical volume, after the four compartments.
  WallRegion = NbLayers + 1;

var
  DotFS : TFormatSettings;

function Vec3(X, Y, Z : Double) : TVec3;
begin
  Result.X := X;
  Result.Y := Y;
  Result.Z := Z;
end;

function Dot(const P, Q : TVec3) : Double;
begin
  Result := P.X * Q.X + P.Y * Q.Y + P.Z * Q.Z;
end;

function Cross(const P, Q : TVec3) : TVec3;
begin
  Result := Vec3(P.Y * Q.Z - P.Z * Q.Y, P.Z * Q.X - P.X * Q.Z, P.X * Q.Y - P.Y * Q.X);
end;

function Normalised(const P : TVec3) : TVec3;
var
  L : Double;
begin
  L := Sqrt(Dot(P, P));
  Result := Vec3(P.X / L, P.Y / L, P.Z / L);
end;

function Num(v : Double) : String;
begin
  Result := Format('%.10f', [v], DotFS);
end;

// An ellipsoid with its first axis along Axis and the second kept
// horizontal (perpendicular to z).
function MakeOrgan(const AName : String; const C, Axis : TVec3;
                   R0, R1, R2 : Double) : TOrgan;
begin
  Result.Name := AName;
  Result.C := C;
  Result.U[0] := Normalised(Axis);
  if Abs(Result.U[0].Z) > 0.999 then
    Result.U[1] := Vec3(1, 0, 0)
  else
    Result.U[1] := Normalised(Cross(Vec3(0, 0, 1), Result.U[0]));
  Result.U[2] := Cross(Result.U[0], Result.U[1]);
  Result.R[0] := R0;
  Result.R[1] := R1;
  Result.R[2] := R2;
end;

{ TDefibModel }

constructor TDefibModel.Create;
begin

  FReport := TStringList.Create;
  FLists := TList.Create;
  FGmsh := TGmsh.Create;

  FWrapLung := True;
  FHeight := RefHeight;
  FWeight := BodyMass;

  FMeshDir := 'mesh' + PathDelim;
  FGeoFile := FMeshDir + 'defibrillation.geo';
  FMshFile := FMeshDir + 'defibrillation.msh';

end;

destructor TDefibModel.Destroy;
var
  i : Integer;
begin

  FEngine.Free;

  for i := 0 to FLists.Count - 1 do
    TExpressionList(FLists[i]).Free;

  FLists.Free;
  FGmsh.Free;
  FReport.Free;

  inherited Destroy;

end;

function TDefibModel.Constant(NodeId, ElementId : Integer) : Double;
begin
  Result := 0;
end;

procedure TDefibModel.Say(const S : String);
begin
  WriteLn(S);
  FReport.Add(S);
end;

function TDefibModel.NewList(const Expr, VarName : String) : TExpressionList;
begin
  Result := TExpressionList.Create;
  Result.AddExpression(-1E9, 1E9, Expr, VarName);
  FLists.Add(Result);
end;

// The section's own radial coordinate, as in ThermEx1: the semi-major
// axis of the similar ellipse through (X, Y).
function TDefibModel.S(X, Y : Double) : Double;
begin
  Result := Sqrt(Sqr(X) + Sqr((Y - FCy) / FK));
end;

// Arc length along the outer ellipse from parametric angle -pi to T.
function TDefibModel.ArcAt(T : Double) : Double;
var
  f : Double;
  i : Integer;
begin
  f := (T + Pi) / (2 * Pi) * ArcTableSize;
  i := EnsureRange(Trunc(f), 0, ArcTableSize - 1);
  f := f - i;
  Result := FArc[i] + f * (FArc[i + 1] - FArc[i]);
end;

// Whether (X, Y, Z) lies over pad Pad's footprint on the skin: within
// half its width round the section, measured along the skin, and half
// its height along the trunk, each widened by Margin. The section at Z
// is the abdomen's scaled by SectionScale, so the arc round it is too;
// up the cone the height is measured along its slope at the point.
function TDefibModel.InPad(Pad : Integer; X, Y, Z : Double; Margin : Double) : Boolean;
var
  T, D, P, Sc, Slope : Double;
begin
  T := ArcTan2((Y - FCy) / FK, X);
  Sc := SectionScale(Z);
  P := FArc[ArcTableSize];
  D := ArcAt(T) - ArcAt(FPadAngle[Pad]);
  D := Sc * (D - P * Round(D / P));
  if FLen - Z < FThxLen then
    Slope := (1 - NeckRatio) / FThxLen * FA * Sqrt(Sqr(Cos(T)) + Sqr(FK * Sin(T)))
  else
    Slope := 0;
  Result := (Abs(D) <= PadWidth / 2 + Margin) and
            (Abs(Z - FPadZ[Pad]) * Sqrt(1 + Sqr(Slope)) <= PadHeight / 2 + Margin);
end;

function TDefibModel.SectionScale(Z : Double) : Double;
var
  h : Double;
begin
  h := FLen - Z;
  if h >= FThxLen then
    Result := 1
  else
    Result := NeckRatio + (1 - NeckRatio) * Max(0, h) / FThxLen;
end;

function TDefibModel.SectionShift(Z : Double) : Double;
begin
  Result := (1 - SectionScale(Z)) * FA;
end;

function TDefibModel.CoreScale(Z : Double) : Double;
begin
  Result := (FCoreA - SectionShift(Z)) / FCoreA;
end;

function TDefibModel.InnerTAt(Theta : Double) : Double;
var
  lo, hi, mid : Integer;
  f : Double;
begin
  lo := 0;
  hi := High(FInnerTh);
  while hi - lo > 1 do
  begin
    mid := (lo + hi) div 2;
    if FInnerTh[mid] <= Theta then
      lo := mid
    else
      hi := mid;
  end;
  f := (Theta - FInnerTh[lo]) / (FInnerTh[hi] - FInnerTh[lo]);
  Result := FInnerT[lo] + EnsureRange(f, 0, 1) * (FInnerT[hi] - FInnerT[lo]);
end;

(*******************************************************************
  From the cylinder gmsh meshed to the body. At height Z the outer
  surface is the abdomen's ellipse scaled by SectionScale, which moves
  it in by SectionShift along s - and every compartment boundary outside
  the core moves in by the same, so the skin, fat and muscle keep their
  thicknesses. The core ellipse is then the meshed one scaled by
  CoreScale; the chest wall keeps its constant thickness inside it, each
  point at the same depth below the same parametric angle; and the core
  within the wall is scaled along each ray from the centre to fill the
  wall's new inner edge. The three meet on their common boundaries, so
  the map is continuous and no element is torn or folded, as long as
  the wall stays thinner than the scaled core's radius of curvature,
  which SetupGeometry checks.
********************************************************************)
function TDefibModel.ToBody(X, Y, Z : Double) : TVec3;
var
  px, py, sp, f, d, T, mu, nl, rw : Double;
  Ex, Ey, Nx_, Ny_ : Double;

  procedure AtT(TT : Double);
  begin
    Ex := FCoreA * Cos(TT);
    Ey := FCoreB * Sin(TT);
    Nx_ := FCoreB * Cos(TT);
    Ny_ := FCoreA * Sin(TT);
    nl := Sqrt(Nx_ * Nx_ + Ny_ * Ny_);
    Nx_ := Nx_ / nl;
    Ny_ := Ny_ / nl;
  end;

begin

  px := X;
  py := Y - FCy;
  sp := S(X, Y);

  if sp >= FCoreA then
  begin
    f := (sp - SectionShift(Z)) / sp;
    Result := Vec3(f * px, FCy + f * py, Z);
    Exit;
  end;

  mu := CoreScale(Z);

  T := InnerTAt(ArcTan2(py, px));
  AtT(T);
  rw := Sqrt(Sqr(Ex - WallThickness * Nx_) + Sqr(Ey - WallThickness * Ny_));

  if Sqrt(px * px + py * py) < rw then
  begin
    f := Sqrt(px * px + py * py) / rw;
    Result := Vec3(f * (mu * Ex - WallThickness * Nx_),
                   FCy + f * (mu * Ey - WallThickness * Ny_), Z);
  end
  else
  begin
    d := FootInCore(X, Y, T);
    AtT(T);
    Result := Vec3(mu * Ex - d * Nx_, FCy + mu * Ey - d * Ny_, Z);
  end;

end;

function TDefibModel.OrganInside(const O : TOrgan; X, Y, Z : Double) : Boolean;
var
  D : TVec3;
  q : Double;
  i : Integer;
begin
  D := Vec3(X - O.C.X, Y - O.C.Y, Z - O.C.Z);
  q := 0;
  for i := 0 to 2 do
    q := q + Sqr(Dot(D, O.U[i]) / O.R[i]);
  Result := q <= 1;
end;

function TDefibModel.InLungWrap(X, Y, Z : Double) : Boolean;
var
  D : TVec3;
  dl : Double;
begin
  Result := False;
  if not OrganInside(WrapShell, X, Y, Z) then
    Exit;
  D := Vec3(X - Heart.C.X, Y - Heart.C.Y, Z - Heart.C.Z);
  dl := Sqrt(Dot(D, D));
  if (dl > 0) and (D.Z / dl < WrapFloorCos) then
    Exit;
  if D.Y >= 0 then
    Result := X < CardiacNotchX
  else
    Result := X < WrapBackX;
end;

function TDefibModel.WallPoint(T, Depth, Z : Double) : TVec3;
var
  nx_, ny_, nl, mu : Double;
begin
  mu := CoreScale(Z);
  nx_ := FCoreB * Cos(T);
  ny_ := FCoreA * Sin(T);
  nl := Sqrt(nx_ * nx_ + ny_ * ny_);
  Result := Vec3(mu * FCoreA * Cos(T) - Depth * nx_ / nl,
                 FCy + mu * FCoreB * Sin(T) - Depth * ny_ / nl, Z);
end;

// Newton on the parametric angle of the nearest point of the ellipse,
// started from the point's own angle - which converges for the points
// near the boundary this is asked about.
function TDefibModel.DepthInCore(X, Y : Double) : Double;
var
  T : Double;
begin
  Result := FootInCore(X, Y, T);
end;

function TDefibModel.FootInCore(X, Y : Double; out T : Double) : Double;
var
  px, py, c, sn, f, df, ab : Double;
  it : Integer;
begin
  px := X;
  py := Y - FCy;
  ab := Sqr(FCoreA) - Sqr(FCoreB);
  T := ArcTan2(py / FCoreB, px / FCoreA);
  for it := 1 to 12 do
  begin
    c := Cos(T);
    sn := Sin(T);
    f := -px * FCoreA * sn + py * FCoreB * c + ab * sn * c;
    df := -px * FCoreA * c - py * FCoreB * sn + ab * (c * c - sn * sn);
    if df = 0 then
      Break;
    T := T - f / df;
  end;
  Result := Sqrt(Sqr(px - FCoreA * Cos(T)) + Sqr(py - FCoreB * Sin(T)));
  if Sqr(px / FCoreA) + Sqr(py / FCoreB) > 1 then
    Result := -Result;
end;

procedure TDefibModel.RibBand(k : Integer; out Z0, Z1 : Double);
begin
  Z1 := FLen - ChestTop - (RibFirstLayer + RibPitch * k) * ChestStep;
  Z0 := Z1 - RibLayers * ChestStep;
end;

function TDefibModel.RibAt(Z : Double) : Integer;
var
  k : Integer;
  Z0, Z1 : Double;
begin
  Result := -1;
  for k := 0 to NbRibs - 1 do
  begin
    RibBand(k, Z0, Z1);
    if (Z > Z0) and (Z < Z1) then
    begin
      Result := k;
      Exit;
    end;
  end;
end;

// The floating ribs stop at the side; the lower true ribs, below the
// sternum, stop at the costal margin either side of the midline.
function TDefibModel.RibPresent(k : Integer; X, Y : Double) : Boolean;
var
  Z0, Z1 : Double;
begin
  Result := True;
  if Y <= FCy then
    Exit;
  RibBand(k, Z0, Z1);
  if k >= NbTrueRibs then
    Result := Abs(X) >= FloatingRibX
  else if FLen - Z1 > SternumBottom then
    Result := Abs(X) >= SternumHalfWidth + 0.012;
end;

function TDefibModel.RibCartilage(k : Integer; X, Y : Double) : Boolean;
begin
  Result := (k < NbTrueRibs) and (Y > FCy) and (Abs(X) < CartilageX);
end;

(*******************************************************************
  The trunk's compartment masses from ThermEx1's tables, exactly as its
  SetupGeometry finds them: skin and fat shared out by surface area, the
  head's core what is left of the head once its fixed muscle is taken,
  and the trunk taking the rest of the body's core with its muscle the
  remainder. Then the abdomen's ellipse, whose cylinder and the cone on
  it hold the trunk's volume, and the compartment boundaries as similar
  ellipses, from the skin in, each holding its compartment's volume
  over the whole trunk.

  With s the semi-major axis of a similar ellipse and SectionShift(z)
  = (1 - SectionScale(z)) a, the shell between boundaries P and Q at
  the abdomen (P > Q) holds pi k ((P^2 - Q^2) L - 2 (P - Q) D), D the
  integral of the shift along the trunk; given P and the volume, that
  is a quadratic for P - Q.
********************************************************************)
procedure TDefibModel.SetupGeometry;
var
  sg, l, i : Integer;
  CoreLeft, Rest, V, p1, T, dT, Area, I2, D, c, x, Pb, Ca, Cb, Ex, Ey, Nx_, Ny_, nl,
    MuTop, Vabd, Slant, AreaNow, FFMRef, dFat, dLean, SkinNew, fc : Double;
  Mass : Array[0..NbLayers - 1] of Double;
begin

  if not Segments[SegTrunk].HasCore or (Segments[SegTrunk].FixedMuscle > 0) then
    raise Exception.Create('ThermEx1''s trunk no longer takes the balance ' +
      'of the core - SetupGeometry here needs updating to match.');

  CoreLeft := Layers[LayerCore].Mass;

  for sg := 0 to NbSegments - 1 do
    if (sg <> SegTrunk) and Segments[sg].HasCore then
      CoreLeft := CoreLeft - (BodyMass * Segments[sg].MassFrac -
        (Layers[LayerSkin].Mass + Layers[LayerFat].Mass) * Segments[sg].AreaFrac -
        Segments[sg].FixedMuscle);

  Mass[LayerSkin] := Layers[LayerSkin].Mass * Segments[SegTrunk].AreaFrac;
  Mass[LayerFat] := Layers[LayerFat].Mass * Segments[SegTrunk].AreaFrac;
  Mass[LayerCore] := CoreLeft;

  Rest := BodyMass * Segments[SegTrunk].MassFrac - Mass[LayerSkin] - Mass[LayerFat];
  Mass[LayerMuscle] := Rest - CoreLeft;

  // That is ThermEx1's subject. Another size changes it by the
  // difference from it in fat-free mass and in fat: see THE BODY'S SIZE.
  if (FHeight < MinHeight) or (FHeight > MaxHeight) then
    raise Exception.CreateFmt('Height %.2f m is outside %.2f to %.2f m.',
      [FHeight, MinHeight, MaxHeight]);
  if (FWeight < MinWeight) or (FWeight > MaxWeight) then
    raise Exception.CreateFmt('Weight %.0f kg is outside %.0f to %.0f kg.',
      [FWeight, MinWeight, MaxWeight]);

  FFatFree := freeFatMass(BodyAge, Male, FWeight, FHeight);
  FFMRef := freeFatMass(BodyAge, Male, BodyMass, RefHeight);
  dFat := (FWeight - FFatFree) - (BodyMass - FFMRef);

  SkinNew := Mass[LayerSkin] * BSA(FWeight, FHeight) / BSA(BodyMass, RefHeight);
  dLean := Segments[SegTrunk].MassFrac * (FFatFree - FFMRef) - (SkinNew - Mass[LayerSkin]);
  fc := Mass[LayerCore] / (Mass[LayerCore] + Mass[LayerMuscle]);
  Mass[LayerCore] := Mass[LayerCore] + fc * dLean;
  Mass[LayerMuscle] := Mass[LayerMuscle] + (1 - fc) * dLean;
  Mass[LayerSkin] := SkinNew;
  Mass[LayerFat] := Mass[LayerFat] + TrunkFatShare * dFat;

  if Mass[LayerFat] < 0.2 then
    raise Exception.CreateFmt('A %.0f kg, %.2f m body leaves the trunk %.2f kg of fat ' +
      '- too lean for this model.', [FWeight, FHeight, Mass[LayerFat]]);

  V := 0;
  for l := 0 to NbLayers - 1 do
    V := V + Mass[l] / Layers[l].Density;

  FVolume := V;
  FK := TrunkAspect;
  FAbdLen := AbdomenLength * FHeight / RefHeight;
  FThxLen := ThoraxLength * FHeight / RefHeight;
  FLen := FAbdLen + FThxLen;

  // The integral along the trunk of SectionScale^2, which times pi k a^2
  // is the volume, and of the shift over a.
  I2 := FAbdLen + FThxLen * (1 + NeckRatio + Sqr(NeckRatio)) / 3;
  FA := Sqrt(V / (Pi * FK * I2));
  FB := FK * FA;
  D := FA * FThxLen * (1 - NeckRatio) / 2;

  // Lying on the plane y = 0, as in ThermEx1.
  FCy := FB;

  FOuter[NbLayers - 1] := FA;
  for l := NbLayers - 1 downto 1 do
  begin
    c := Mass[l] / Layers[l].Density / (Pi * FK);
    Pb := FOuter[l] * FLen - D;
    x := (Pb - Sqrt(Sqr(Pb) - FLen * c)) / FLen;
    FOuter[l - 1] := FOuter[l] - x;
  end;

  FCoreA := FOuter[LayerCore];
  FCoreB := FK * FOuter[LayerCore];

  // The core at the root of the neck, and the chest wall inside it.
  MuTop := CoreScale(FLen);
  if MuTop * Sqr(FCoreB) / FCoreA <= WallThickness then
    raise Exception.Create('The core at the root of the neck is too small for the ' +
      'chest wall to keep its thickness: raise NeckRatio or thin the wall.');

  // The wall's inner edge as meshed, by the polar angle of its points.
  SetLength(FInnerT, ArcTableSize + 1);
  SetLength(FInnerTh, ArcTableSize + 1);
  for i := 0 to ArcTableSize do
  begin
    T := -Pi + 2 * Pi * i / ArcTableSize;
    Ex := FCoreA * Cos(T);
    Ey := FCoreB * Sin(T);
    Nx_ := FCoreB * Cos(T);
    Ny_ := FCoreA * Sin(T);
    nl := Sqrt(Nx_ * Nx_ + Ny_ * Ny_);
    FInnerT[i] := T;
    FInnerTh[i] := ArcTan2(Ey - WallThickness * Ny_ / nl, Ex - WallThickness * Nx_ / nl);
    if i = 0 then
      FInnerTh[i] := -Pi
    else if i = ArcTableSize then
      FInnerTh[i] := Pi;
  end;

  // Ramanujan's perimeter of the unit ellipse of axis ratio k; the
  // cone's side taken as sloping by its mean radius.
  p1 := Pi * (3 * (1 + FK) - Sqrt((3 + FK) * (1 + 3 * FK)));
  Slant := Sqrt(1 + Sqr((1 - NeckRatio) * FA * (1 + FK) / 2 / FThxLen));
  AreaNow := p1 * FA * (FAbdLen + FThxLen * (1 + NeckRatio) / 2 * Slant);
  Area := Segments[SegTrunk].AreaFrac * BSA(FWeight, FHeight);
  Vabd := Pi * FK * Sqr(FA) * FAbdLen;

  Ca := FCoreA - WallThickness;
  Cb := FCoreB - WallThickness;

  // Arc length round the outer ellipse, for placing the pads.
  SetLength(FArc, ArcTableSize + 1);
  FArc[0] := 0;
  dT := 2 * Pi / ArcTableSize;

  for i := 1 to ArcTableSize do
  begin
    T := -Pi + (i - 0.5) * dT;
    FArc[i] := FArc[i - 1] + FA * Sqrt(Sqr(Sin(T)) + Sqr(FK * Cos(T))) * dT;
  end;

  FPadAngle[PadAnode] := DegToRad(SternalAngleDeg);
  FPadZ[PadAnode] := FLen - SternalDepth;
  FPadAngle[PadCathode] := DegToRad(ApexAngleDeg);
  FPadZ[PadCathode] := FLen - ApexDepth;

  // The organs, in the body's own coordinates. The heart's long axis
  // runs from the base, up, back and to the right, to the apex, down,
  // forward and to the left (-x), and it rests on the diaphragm, where
  // the cone is widest; inside the wall the section at its centre is
  // about 210 x 140 mm.
  Heart := MakeOrgan('heart', Vec3(-0.025, FCy + 0.012, FLen - 0.18),
                     Vec3(-0.60, 0.30, -0.75), 0.060, 0.042, 0.036);

  Cavity := Heart;
  Cavity.Name := 'cavity';
  for i := 0 to 2 do
    Cavity.R[i] := Heart.R[i] - 0.012;

  WrapShell := Heart;
  WrapShell.Name := 'lung wrap';
  for i := 0 to 2 do
    WrapShell.R[i] := Heart.R[i] + LungWrapDepth;

  // Either side of the mediastinum, from the apex of the cone to the
  // diaphragm, filling the ribcage's width and depth as it narrows -
  // what lies outside the wall's inner edge stays wall.
  Lungs[0] := MakeOrgan('right lung', Vec3(0.060, FCy - 0.005, FLen - 0.13),
                        Vec3(0, 0, 1), 0.120, 0.062, 0.072);
  Lungs[1] := MakeOrgan('left lung', Vec3(-0.060, FCy - 0.005, FLen - 0.13),
                        Vec3(0, 0, 1), 0.120, 0.062, 0.072);

  Say('THE TORSO - ThermEx1''s trunk as a thorax on an abdomen');
  Say(Format('  a man of %.0f kg and %.2f m (BMI %.1f), %.0f kg of it fat-free and %.0f %% fat ' +
    '(Al-Sallami)', [FWeight, FHeight, BMI(FWeight, FHeight), FFatFree,
    100 * (1 - FFatFree / FWeight)]));
  if not (SameValue(FWeight, BodyMass) and SameValue(FHeight, RefHeight)) then
    Say(Format('  scaled from ThermEx1''s %.0f kg, %.2f m: fat-free mass changed by %.1f kg ' +
      '(%.0f %% of it on the trunk), fat by %.1f kg (%.0f %% on the trunk)', [BodyMass, RefHeight,
      FFatFree - FFMRef, 100 * Segments[SegTrunk].MassFrac, dFat, 100 * TrunkFatShare]));
  Say(Format('  abdomen  %.0f mm wide, %.0f mm deep, %.2f m long, %.1f litres',
    [2000 * FA, 2000 * FB, FAbdLen, 1000 * Vabd]));
  Say(Format('  thorax   a truncated cone %.2f m long, from the abdomen''s section at ' +
    'the diaphragm', [FThxLen]));
  Say(Format('           to %.0f x %.0f mm at the root of the neck, %.1f litres',
    [2000 * NeckRatio * FA, 2000 * NeckRatio * FB, 1000 * (V - Vabd)]));
  Say(Format('  %.2f m long, %.1f litres, about %.2f m2 of skin (ThermEx1''s trunk %.2f)',
    [FLen, 1000 * V, AreaNow, Area]));
  Say('  compartment    kg   thick at the side, mm   sigma, S/m');
  for l := 0 to NbLayers - 1 do
    if l = LayerCore then
      Say(Format('  %-10s %7.2f   s %.1f at the diaphragm %7.3f',
        [Layers[l].Name, Mass[l], 1000 * FOuter[l], TissueSigma[TTissue(l)]]))
    else
      Say(Format('  %-10s %7.2f %14.1f %16.3f',
        [Layers[l].Name, Mass[l], 1000 * (FOuter[l] - FOuter[l - 1]), TissueSigma[TTissue(l)]]));
  Say(Format('  chest wall %.0f mm inside the core, %.2f S/m, with %d ribs ' +
    '(bone %.2f S/m,', [1000 * WallThickness, TissueSigma[tiWall], NbRibs,
    TissueSigma[tiBone]]));
  Say(Format('    cartilage %.2f at the front), sternum and spine; core inside it ' +
    '%.0f x %.0f mm', [TissueSigma[tiCartilage], 2000 * Ca, 2000 * Cb]));
  Say(Format('    at the diaphragm, %.0f x %.0f at the root of the neck',
    [2000 * (MuTop * FCoreA - WallThickness), 2000 * (MuTop * FCoreB - WallThickness)]));
  Say(Format('  heart: myocardium %.2f S/m round blood %.2f; lungs %.2f S/m',
    [TissueSigma[tiMyocardium], TissueSigma[tiBlood], TissueSigma[tiLung]]));
  if FAnisotropic then
    Say(Format('  ANISOTROPIC muscle and chest wall: %.2f S/m along fibres running ' +
      'round the trunk, %.3f across', [MuscleSigmaL, MuscleSigmaT]))
  else
    Say('  every tissue isotropic');
  Say('');

end;

(*******************************************************************
  The trunk alone, as ThermEx1's WriteGeoFile writes a cylinder: a disc
  of core, meshed unstructured, inside four transfinite quadrants per
  outer compartment, all extruded along z. Here the extrusion is graded
  - fine through the chest, coarse below it - and the physical volumes
  are simply the compartment numbers, 1 to 4.

  The chest wall is one more ring of transfinite quadrants just inside
  the core's ellipse, its inner edge a spline through points offset
  WallThickness along the ellipse's normal, so it is the same thickness
  all round. It is physical volume 5, and the core's disc fills the
  spline.
********************************************************************)
procedure TDefibModel.WriteGeoFile;

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

  // The wall's inner points, CircDiv per quadrant, the last of each
  // quadrant being the first of the next.
  function WPt(q, j : Integer) : Integer;
  begin
    if j >= CircDiv then
    begin
      q := q + 1;
      j := 0;
    end;
    Result := 1000 + (q mod 4) * CircDiv + j;
  end;

var
  F : TextFile;
  L, q, n, j, Na, Nc, Nn : Integer;
  ang, z1, z2 : Double;
  Arcs, Rads, Vols, Zones, Pts : String;
  P : TVec3;
begin

  ForceDirectories(FMeshDir);

  AssignFile(F, FGeoFile);
  ReWrite(F);

  try

    WriteLn(F, 'Mesh.MshFileVersion=1;');
    WriteLn(F, 'Mesh.MeshSizeExtendFromBoundary = 0;');
    WriteLn(F, 'Mesh.MeshSizeMax = ' + Num(CoreMeshSize) + ';');
    WriteLn(F, 'cl = ' + Num(CoreMeshSize) + ';');

    WriteLn(F, 'Point(1) = {0,' + Num(FCy) + ',0,cl};');

    for L := 0 to NbLayers - 1 do
      for q := 0 to 3 do
      begin
        ang := q * Pi / 2;
        WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};',
          [PIdx(L, q), Num(FOuter[L] * Cos(ang)), Num(FCy + FK * FOuter[L] * Sin(ang))]));
      end;

    for L := 0 to NbLayers - 1 do
    begin
      Arcs := '';
      for q := 0 to 3 do
      begin
        WriteLn(F, Format('Ellipse(%d) = {%d,1,%d,%d};',
          [ArcId(L, q), PIdx(L, q), PIdx(L, 0), PIdx(L, q + 1)]));
        if q > 0 then
          Arcs := Arcs + ',';
        Arcs := Arcs + IntToStr(ArcId(L, q));
      end;
      WriteLn(F, Format('Transfinite Line {%s} = %d;', [Arcs, CircDiv + 1]));
    end;

    for L := 0 to NbLayers - 2 do
    begin
      Rads := '';
      for q := 0 to 3 do
      begin
        WriteLn(F, Format('Line(%d) = {%d,%d};', [RadId(L, q), PIdx(L, q), PIdx(L + 1, q)]));
        if q > 0 then
          Rads := Rads + ',';
        Rads := Rads + IntToStr(RadId(L, q));
      end;
      WriteLn(F, Format('Transfinite Line {%s} = %d;', [Rads, Layers[L + 1].RadialDiv + 1]));
    end;

    // The chest wall: inner points, splines, radial lines, quadrants.
    for q := 0 to 3 do
      for j := 0 to CircDiv - 1 do
      begin
        P := WallPoint(q * Pi / 2 + j * Pi / (2 * CircDiv), WallThickness, 0);
        WriteLn(F, Format('Point(%d) = {%s,%s,0,cl};', [WPt(q, j), Num(P.X), Num(P.Y)]));
      end;

    for q := 0 to 3 do
    begin
      Pts := '';
      for j := 0 to CircDiv do
      begin
        if j > 0 then
          Pts := Pts + ',';
        Pts := Pts + IntToStr(WPt(q, j));
      end;
      WriteLn(F, Format('Spline(%d) = {%s};', [3000 + q, Pts]));
      WriteLn(F, Format('Line(%d) = {%d,%d};', [3100 + q, WPt(q, 0), PIdx(0, q)]));
    end;

    WriteLn(F, Format('Transfinite Line {3000,3001,3002,3003} = %d;', [CircDiv + 1]));
    WriteLn(F, Format('Transfinite Line {3100,3101,3102,3103} = %d;', [WallDiv + 1]));

    for q := 0 to 3 do
    begin
      n := (q + 1) mod 4;
      WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
        [3200 + q, 3100 + q, ArcId(0, q), 3100 + n, 3000 + q]));
      WriteLn(F, Format('Plane Surface(%d) = {%d};', [3300 + q, 3200 + q]));
      WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
        [3300 + q, WPt(q, 0), PIdx(0, q), PIdx(0, n), WPt(n, 0)]));
      WriteLn(F, Format('Recombine Surface {%d};', [3300 + q]));
    end;

    WriteLn(F, 'Line Loop(299) = {3000,3001,3002,3003};');
    WriteLn(F, 'Plane Surface(300) = {299};');
    WriteLn(F, 'Point{1} In Surface{300};');

    for L := 1 to NbLayers - 1 do
      for q := 0 to 3 do
      begin
        n := (q + 1) mod 4;
        WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
          [500 + 4 * L + q, RadId(L - 1, q), ArcId(L, q), RadId(L - 1, n), ArcId(L - 1, q)]));
        WriteLn(F, Format('Plane Surface(%d) = {%d};', [400 + 4 * L + q, 500 + 4 * L + q]));
        WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
          [400 + 4 * L + q, PIdx(L - 1, q), PIdx(L, q), PIdx(L, n), PIdx(L - 1, n)]));
        WriteLn(F, Format('Recombine Surface {%d};', [400 + 4 * L + q]));
      end;

    // Graded extrusion: abdomen, chest, neck.
    z1 := FLen - ChestBottom;
    z2 := FLen - ChestTop;
    Na := Max(1, Round(z1 / AbdomenStep));
    Nc := Max(1, Round((z2 - z1) / ChestStep));
    Nn := Max(1, Round((FLen - z2) / NeckStep));

    Zones := Format('Layers{{%d,%d,%d},{%s,%s,1}}',
      [Na, Nc, Nn, Num(z1 / FLen), Num(z2 / FLen)]);

    WriteLn(F, Format('c[] = Extrude {0,0,%s} { Surface{300}; %s; Recombine; };',
      [Num(FLen), Zones]));
    WriteLn(F, 'Physical Volume(1) = {c[1]};');

    for L := 1 to NbLayers - 1 do
    begin
      Vols := '';
      for q := 0 to 3 do
      begin
        WriteLn(F, Format('v%d_%d[] = Extrude {0,0,%s} { Surface{%d}; %s; Recombine; };',
          [L, q, Num(FLen), 400 + 4 * L + q, Zones]));
        if q > 0 then
          Vols := Vols + ',';
        Vols := Vols + Format('v%d_%d[1]', [L, q]);
      end;
      WriteLn(F, Format('Physical Volume(%d) = {%s};', [L + 1, Vols]));
    end;

    Vols := '';
    for q := 0 to 3 do
    begin
      WriteLn(F, Format('w_%d[] = Extrude {0,0,%s} { Surface{%d}; %s; Recombine; };',
        [q, Num(FLen), 3300 + q, Zones]));
      if q > 0 then
        Vols := Vols + ',';
      Vols := Vols + Format('w_%d[1]', [q]);
    end;
    WriteLn(F, Format('Physical Volume(%d) = {%s};', [WallRegion, Vols]));

  finally
    CloseFile(F);
  end;

end;

procedure TDefibModel.BuildMesh;
var
  ExitCode : Cardinal;
begin

  Say('Meshing the trunk with gmsh...');

  WriteGeoFile;

  if FileExists(FMshFile) then
    DeleteFile(FMshFile);

  if not Sto_ShellExecute(GmshExecutable, [FGeoFile, '-3'], ExitCode, 300000, True) then
    raise Exception.Create('Could not run gmsh (' + GmshExecutable +
      '). Install gmsh, or edit GmshExecutable in uDefibModel.pas.');

  if ExitCode <> 0 then
    raise Exception.Create('gmsh failed with exit code ' + IntToStr(ExitCode));

  if not FileExists(FMshFile) then
    raise Exception.Create('gmsh produced no mesh file (' + FMshFile + ')');

  FGmsh.OpenFile(FMshFile);
  FGmsh.ReadMesh;
  FGmsh.Close;

  Say(Format('  %d nodes, %d elements', [FGmsh.NbNodes, FGmsh.NbElements]));

end;

function EleNodeCount(T : Integer) : Integer;
begin
  case T of
    GMSH_HEXA : Result := 8;
    GMSH_PRISM : Result := 6;
    GMSH_TETRA : Result := 4;
  else
    raise Exception.Create('Unexpected gmsh element type ' + IntToStr(T));
  end;
end;

// Tissue, centroid and volume of every element. The volume splits each
// element into tetrahedra, as ThermEx1's CalcElementGeometry does.
procedure TDefibModel.ClassifyElements;

  function TetVolume(n0, n1, n2, n3 : Integer) : Double;
  var
    ax, ay, az, bx, by, bz, cx, cy, cz : Double;
  begin
    ax := NX[n1] - NX[n0]; ay := NY[n1] - NY[n0]; az := NZ[n1] - NZ[n0];
    bx := NX[n2] - NX[n0]; by := NY[n2] - NY[n0]; bz := NZ[n2] - NZ[n0];
    cx := NX[n3] - NX[n0]; cy := NY[n3] - NY[n0]; cz := NZ[n3] - NZ[n0];
    Result := Abs(ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) +
                  az * (bx * cy - by * cx)) / 6;
  end;

var
  i, j, nb, g, k : Integer;
  Nd : Array[0..7] of Integer;
  c, rc, P : TVec3;
  Tot, Vthx, Vwrap, Vc : Double;
  Vt : Array[TTissue] of Double;
  t : TTissue;
  Contact : TOrgan;
  Line : String;
  CoreDir : Array[0..2] of Double;
begin

  // Each node from the cylinder gmsh meshed onto the body.
  NbNodes := FGmsh.NbNodes;
  SetLength(NX, NbNodes);
  SetLength(NY, NbNodes);
  SetLength(NZ, NbNodes);
  SetLength(FRefX, NbNodes);
  SetLength(FRefY, NbNodes);

  for i := 0 to NbNodes - 1 do
  begin
    FRefX[i] := FGmsh.CoordX[i];
    FRefY[i] := FGmsh.CoordY[i];
    P := ToBody(FRefX[i], FRefY[i], FGmsh.CoordZ[i]);
    NX[i] := P.X;
    NY[i] := P.Y;
    NZ[i] := P.Z;
  end;

  NbEle := FGmsh.NbElements;
  SetLength(EleTissue, NbEle);
  SetLength(EleC, NbEle);
  SetLength(EleVol, NbEle);

  for t := Low(TTissue) to High(TTissue) do
  begin
    Vt[t] := 0;
    ContactVol[t] := 0;
  end;
  Vthx := 0;
  Vwrap := 0;
  for i := 0 to 2 do
    CoreDir[i] := 0;
  Contact := Heart;
  for i := 0 to 2 do
    Contact.R[i] := Heart.R[i] + HeartContact;

  for i := 0 to NbEle - 1 do
  begin

    nb := EleNodeCount(FGmsh.ElementType[i]);
    c := Vec3(0, 0, 0);
    rc := Vec3(0, 0, 0);

    for j := 0 to nb - 1 do
    begin
      Nd[j] := FGmsh.ElementNode[i, j];
      c.X := c.X + NX[Nd[j]];
      c.Y := c.Y + NY[Nd[j]];
      c.Z := c.Z + NZ[Nd[j]];
      rc.X := rc.X + FRefX[Nd[j]];
      rc.Y := rc.Y + FRefY[Nd[j]];
    end;

    EleC[i] := Vec3(c.X / nb, c.Y / nb, c.Z / nb);
    rc := Vec3(rc.X / nb, rc.Y / nb, 0);

    case nb of
      4 : EleVol[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[3]);
      6 : EleVol[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[3]) +
                       TetVolume(Nd[1], Nd[2], Nd[3], Nd[4]) +
                       TetVolume(Nd[2], Nd[3], Nd[4], Nd[5]);
    else
      EleVol[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[6]) +
                   TetVolume(Nd[0], Nd[2], Nd[3], Nd[6]) +
                   TetVolume(Nd[0], Nd[3], Nd[7], Nd[6]) +
                   TetVolume(Nd[0], Nd[7], Nd[4], Nd[6]) +
                   TetVolume(Nd[0], Nd[4], Nd[5], Nd[6]) +
                   TetVolume(Nd[0], Nd[5], Nd[1], Nd[6]);
    end;

    g := FGmsh.ElementPhysicalRegion[i] - 1;

    if (g < 0) or (g > WallRegion - 1) then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in physical region ' +
        IntToStr(g + 1) + ', not one of the four compartments or the chest wall.');

    if g = WallRegion - 1 then
      EleTissue[i] := tiWall
    else
      EleTissue[i] := TTissue(g);

    // The spine first, through core and wall alike, a set distance in
    // front of the back of the core at each height; then the bone and
    // cartilage in the wall's inner part, by depth in the wall as
    // meshed, which ToBody keeps; then the organs, which only replace
    // core, the heart winning over the lungs.
    if (EleTissue[i] in [tiCore, tiWall]) and
       (Sqr(EleC[i].X) + Sqr(EleC[i].Y - (FCy - CoreScale(EleC[i].Z) * FCoreB + SpineInset))
         <= Sqr(SpineRadius)) then
      EleTissue[i] := tiBone
    else if EleTissue[i] = tiWall then
    begin
      if DepthInCore(rc.X, rc.Y) >= WallThickness - RibDepth then
      begin
        k := RibAt(EleC[i].Z);
        if (EleC[i].Y > FCy) and (Abs(EleC[i].X) < SternumHalfWidth) and
           (FLen - EleC[i].Z > SternumTop) and (FLen - EleC[i].Z < SternumBottom) then
          EleTissue[i] := tiBone
        else if (k >= 0) and RibPresent(k, EleC[i].X, EleC[i].Y) then
        begin
          if RibCartilage(k, EleC[i].X, EleC[i].Y) then
            EleTissue[i] := tiCartilage
          else
            EleTissue[i] := tiBone;
        end;
      end;
    end
    else if g = LayerCore then
    begin
      if OrganInside(Cavity, EleC[i].X, EleC[i].Y, EleC[i].Z) then
        EleTissue[i] := tiBlood
      else if OrganInside(Heart, EleC[i].X, EleC[i].Y, EleC[i].Z) then
        EleTissue[i] := tiMyocardium
      else if OrganInside(Lungs[0], EleC[i].X, EleC[i].Y, EleC[i].Z) or
              OrganInside(Lungs[1], EleC[i].X, EleC[i].Y, EleC[i].Z) then
        EleTissue[i] := tiLung
      else if FWrapLung and InLungWrap(EleC[i].X, EleC[i].Y, EleC[i].Z) then
      begin
        EleTissue[i] := tiLung;
        Vwrap := Vwrap + EleVol[i];
      end;
    end;

    // What the heart touches.
    if not (EleTissue[i] in [tiMyocardium, tiBlood]) and
       OrganInside(Contact, EleC[i].X, EleC[i].Y, EleC[i].Z) then
    begin
      ContactVol[EleTissue[i]] := ContactVol[EleTissue[i]] + EleVol[i];
      // The core it touches, by where: below, in front, behind.
      if EleTissue[i] = tiCore then
      begin
        P := Vec3(EleC[i].X - Heart.C.X, EleC[i].Y - Heart.C.Y, EleC[i].Z - Heart.C.Z);
        if P.Z < WrapFloorCos * Sqrt(Dot(P, P)) then
          CoreDir[0] := CoreDir[0] + EleVol[i]
        else if P.Y >= 0 then
          CoreDir[1] := CoreDir[1] + EleVol[i]
        else
          CoreDir[2] := CoreDir[2] + EleVol[i];
      end;
    end;

    Vt[EleTissue[i]] := Vt[EleTissue[i]] + EleVol[i];
    if FLen - EleC[i].Z < FThxLen then
      Vthx := Vthx + EleVol[i];

  end;

  Say('  meshed volumes, litres:');
  Tot := 0;
  for t := tiCore to LastTissue do
  begin
    Say(Format('    %-11s %7.3f', [TissueName[t], 1000 * Vt[t]]));
    Tot := Tot + Vt[t];
  end;
  Say(Format('    total       %7.3f  (the trunk: %.3f), the thorax %.3f of it',
    [1000 * Tot, 1000 * FVolume, 1000 * Vthx]));
  if FWrapLung then
    Say(Format('  the left lung wrapped round the heart, %.0f mm deep: %.3f litres of it',
      [1000 * LungWrapDepth, 1000 * Vwrap]))
  else
    Say('  the left lung NOT wrapped round the heart (--no-wrap)');
  Vc := 0;
  for t := Low(TTissue) to High(TTissue) do
    Vc := Vc + ContactVol[t];
  Line := '';
  for t := Low(TTissue) to High(TTissue) do
    if ContactVol[t] > 0.005 * Vc then
      Line := Line + Format('  %s %.0f %%', [TissueName[t], 100 * ContactVol[t] / Vc]);
  Say(Format('  within %.0f mm of the heart:%s', [1000 * HeartContact, Line]));
  if Vc > 0 then
    Say(Format('    the core there: %.0f %% below it, %.0f %% in front, %.0f %% behind',
      [100 * CoreDir[0] / Vc, 100 * CoreDir[1] / Vc, 100 * CoreDir[2] / Vc]));

end;

// Every skin element's face lying on the outer surface: all four nodes
// in the outer quarter of the skin as meshed, as ThermEx1 finds its skin
// faces. The normal is the face's own, which up the cone leans out of
// the horizontal.
procedure TDefibModel.FindSurface;
var
  i, f, j, n : Integer;
  Thr, mx, my, mz, nx_, ny_, nz_, nl, ax, ay, az, bx, by, bz : Double;
  OnSkin : Boolean;
  Fc : TSurfFace;
  Nd : Array[0..3] of Integer;
begin

  Thr := FOuter[LayerSkin] - 0.25 * (FOuter[LayerSkin] - FOuter[LayerFat]);
  n := 0;
  SetLength(Skin, 16384);
  PadArea[0] := 0;
  PadArea[1] := 0;

  for i := 0 to NbEle - 1 do
  begin

    if (EleTissue[i] <> tiSkin) or (FGmsh.ElementType[i] <> GMSH_HEXA) then
      Continue;

    for f := 0 to 5 do
    begin

      OnSkin := True;
      mx := 0; my := 0; mz := 0;

      for j := 0 to 3 do
      begin
        Nd[j] := FGmsh.ElementNode[i, HexFace[f, j]];
        if S(FRefX[Nd[j]], FRefY[Nd[j]]) < Thr then
          OnSkin := False;
        mx := mx + NX[Nd[j]] / 4;
        my := my + NY[Nd[j]] / 4;
        mz := mz + NZ[Nd[j]] / 4;
      end;

      if not OnSkin then
        Continue;

      for j := 0 to 3 do
        Fc.N[j] := Nd[j];

      // The cross product of the diagonals, turned outward.
      ax := NX[Nd[2]] - NX[Nd[0]]; ay := NY[Nd[2]] - NY[Nd[0]]; az := NZ[Nd[2]] - NZ[Nd[0]];
      bx := NX[Nd[3]] - NX[Nd[1]]; by := NY[Nd[3]] - NY[Nd[1]]; bz := NZ[Nd[3]] - NZ[Nd[1]];
      nx_ := ay * bz - az * by;
      ny_ := az * bx - ax * bz;
      nz_ := ax * by - ay * bx;
      nl := Sqrt(nx_ * nx_ + ny_ * ny_ + nz_ * nz_);
      Fc.Area := 0.5 * nl;
      if nx_ * mx + ny_ * (my - FCy) < 0 then
        nl := -nl;
      Fc.Nx := nx_ / nl;
      Fc.Ny := ny_ / nl;
      Fc.Nz := nz_ / nl;

      Fc.Ele := i;
      Fc.Pad := -1;

      if InPad(PadAnode, mx, my, mz, 0) then
        Fc.Pad := PadAnode
      else if InPad(PadCathode, mx, my, mz, 0) then
        Fc.Pad := PadCathode;

      if Fc.Pad >= 0 then
        PadArea[Fc.Pad] := PadArea[Fc.Pad] + Fc.Area;

      if n >= Length(Skin) then
        SetLength(Skin, 2 * n);

      Skin[n] := Fc;
      Inc(n);

    end;

  end;

  SetLength(Skin, n);

  Say(Format('  %d faces on the skin; pads %.0f and %.0f cm2 as meshed (nominal %.0f)',
    [n, 1E4 * PadArea[0], 1E4 * PadArea[1], 1E4 * PadWidth * PadHeight]));

end;

(*******************************************************************
  The engine: one material per tissue, the conductivity standing in for
  the thermal conductivity (density and heat capacity are irrelevant to
  a static solve and set to 1). The pads are a 1 mm sheet of bricks
  extruded outward from every skin face they cover, sharing nodes so
  each is one continuous conductor - the same construction as
  ThermEx1's gown. 1 A goes into the sternal pad's outer nodes, shared
  equally, and the apex pad's outer nodes are held at 0 V.
********************************************************************)
procedure TDefibModel.BuildEngine;
var
  i, j, nd, nb, NbAn : Integer;
  Mat : Array[TTissue] of Integer;
  t : TTissue;
  Outer : TIntegerArray;
  Node : Array[0..7] of Integer;
  Src, Zero : TExpressionList;
  Fc : TSurfFace;
  nPad : Integer;
  Id, NbAniso : Integer;
  f : TVec3;
  dS : Double;
begin

  FEngine := TThermalEngine.Create;
  FEngine.PenaltyMethod := True;
  FEngine.SolverType := soUMFPACK;    // PARDISO, symmetric positive definite

  for t := Low(TTissue) to High(TTissue) do
    Mat[t] := FEngine.AddMaterial(Constant, NewList('1', 'T'), NewList('1', 'T'),
                                  NewList(Num(TissueSigma[t]), 'T'));

  FEngine.BeginAddMesh;
  NbAniso := 0;

  for i := 0 to NbNodes - 1 do
    FEngine.AddNode(NX[i], NY[i], NZ[i]);

  for i := 0 to NbEle - 1 do
  begin
    nb := EleNodeCount(FGmsh.ElementType[i]);
    for j := 0 to nb - 1 do
      Node[j] := FGmsh.ElementNode[i, j];
    case nb of
      8 : Id := FEngine.AddElement(Node, 8, elHexa, Mat[EleTissue[i]]);
      6 : Id := FEngine.AddElement(Node, 6, elPrism, Mat[EleTissue[i]]);
    else
      Id := FEngine.AddElement(Node, 4, elTetra, Mat[EleTissue[i]]);
    end;
    if IsAnisotropic(i) then
    begin
      // sigma_T I + (sigma_L - sigma_T) f f^T
      f := FibreDir(EleC[i].X, EleC[i].Y);
      dS := MuscleSigmaL - MuscleSigmaT;
      FEngine.SetElementConductivityTensor(Id,
        MuscleSigmaT + dS * f.X * f.X, MuscleSigmaT + dS * f.Y * f.Y,
        MuscleSigmaT + dS * f.Z * f.Z,
        dS * f.X * f.Y, dS * f.X * f.Z, dS * f.Y * f.Z);
      Inc(NbAniso);
    end;
  end;

  if FAnisotropic then
    Say(Format('  %d muscle and chest-wall elements given a fibre tensor', [NbAniso]));

  SetLength(Outer, NbNodes);
  for i := 0 to NbNodes - 1 do
    Outer[i] := -1;

  nPad := 0;
  SetLength(PadFaces, Length(Skin));

  for i := 0 to Length(Skin) - 1 do
  begin

    if Skin[i].Pad < 0 then
      Continue;

    for j := 0 to 3 do
    begin
      nd := Skin[i].N[j];
      if Outer[nd] < 0 then
        Outer[nd] := FEngine.AddNode(NX[nd] + Skin[i].Nx * PadThickness,
                                     NY[nd] + Skin[i].Ny * PadThickness,
                                     NZ[nd] + Skin[i].Nz * PadThickness);
    end;

    for j := 0 to 3 do
    begin
      Node[j] := Skin[i].N[j];
      Node[j + 4] := Outer[Skin[i].N[j]];
    end;

    Fc := Skin[i];
    Fc.Ele := FEngine.AddElement(Node, 8, elHexa, Mat[tiPad]);
    for j := 0 to 3 do
      Fc.N[j] := Outer[Skin[i].N[j]];

    PadFaces[nPad] := Fc;
    Inc(nPad);

  end;

  SetLength(PadFaces, nPad);

  FEngine.EndAddMesh;

  // Node arrays extended to the pads' outer nodes, which the pad faces
  // now refer to.
  NbNodes := FEngine.NbNodes;
  SetLength(NX, NbNodes);
  SetLength(NY, NbNodes);
  SetLength(NZ, NbNodes);
  for i := 0 to NbNodes - 1 do
  begin
    NX[i] := FEngine.CoordX[i];
    NY[i] := FEngine.CoordY[i];
    NZ[i] := FEngine.CoordZ[i];
  end;

  FEngine.BeginSetRestraints;

  Zero := NewList('0', 'T');

  for i := 0 to Length(PadFaces) - 1 do
    if PadFaces[i].Pad = PadCathode then
      for j := 0 to 3 do
        FEngine.SetNodeRestraint(PadFaces[i].N[j], Constant, Zero);

  FEngine.EndSetRestraints;

  // The 1 A, shared equally over the sternal pad's outer nodes, each
  // counted once. The sheet makes the pad an equipotential, so how it
  // is shared does not matter; the report checks the spread of
  // potential across the pad.
  SetLength(Outer, NbNodes);
  for i := 0 to NbNodes - 1 do
    Outer[i] := 0;

  NbAn := 0;
  for i := 0 to Length(PadFaces) - 1 do
    if PadFaces[i].Pad = PadAnode then
      for j := 0 to 3 do
        if Outer[PadFaces[i].N[j]] = 0 then
        begin
          Outer[PadFaces[i].N[j]] := 1;
          Inc(NbAn);
        end;

  Src := NewList(Num(1.0 / NbAn), 't');

  for i := 0 to NbNodes - 1 do
    if Outer[i] = 1 then
      FEngine.AddNodeSource(i, Constant, Src);

  Say(Format('  %d pad elements; 1 A shared over %d nodes of the sternal pad',
    [nPad, NbAn]));

end;

procedure TDefibModel.Solve;
var
  i : Integer;
  t0 : QWord;
begin

  Say('Solving for 1 A pad to pad...');
  t0 := GetTickCount64;

  FEngine.CalcTemperature(caStatic, False);

  SetLength(Phi, NbNodes);
  for i := 0 to NbNodes - 1 do
    Phi[i] := FEngine.Temperature[i];

  Say(Format('  solved in %.1f s', [(GetTickCount64 - t0) / 1000]));

end;

(*******************************************************************
  Current density in every element, as -sigma times the gradient of the
  least-squares linear fit to its nodes' potentials - exact on a
  tetrahedron, the element's mean gradient on a prism or a brick.
********************************************************************)
procedure TDefibModel.PostProcess;
var
  i, j, nb, m, k : Integer;
  Nd : Array[0..7] of Integer;
  c, d, gr : TVec3;
  M11, M12, M13, M22, M23, M33, r1, r2, r3, pm, det, sg : Double;
  VaMin, VaMax, Vc, Pdiss, PadI, Jn : Double;
  Pt : Array[TTissue] of Double;
  t : TTissue;
  Order : TIntegerArray;
  Key : TDoubleArray;
  Sum, Ext : TVec3;
  FluxSum : Double;

  procedure SortByKey(var Idx : TIntegerArray; const K_ : TDoubleArray; L, R : Integer);
  var
    a, b, tmp : Integer;
    p : Double;
  begin
    repeat
      a := L; b := R;
      p := K_[Idx[(L + R) div 2]];
      repeat
        while K_[Idx[a]] < p do Inc(a);
        while K_[Idx[b]] > p do Dec(b);
        if a <= b then
        begin
          tmp := Idx[a]; Idx[a] := Idx[b]; Idx[b] := tmp;
          Inc(a); Dec(b);
        end;
      until a > b;
      if L < b then SortByKey(Idx, K_, L, b);
      L := a;
    until a >= R;
  end;

begin

  SetLength(EleJ, NbEle);
  SetLength(EleJMag, NbEle);

  for t := Low(TTissue) to High(TTissue) do
    Pt[t] := 0;

  Pdiss := 0;

  for i := 0 to NbEle - 1 do
  begin

    nb := EleNodeCount(FGmsh.ElementType[i]);
    c := EleC[i];
    pm := 0;

    for j := 0 to nb - 1 do
    begin
      Nd[j] := FGmsh.ElementNode[i, j];
      pm := pm + Phi[Nd[j]] / nb;
    end;

    M11 := 0; M12 := 0; M13 := 0; M22 := 0; M23 := 0; M33 := 0;
    r1 := 0; r2 := 0; r3 := 0;

    for j := 0 to nb - 1 do
    begin
      d := Vec3(NX[Nd[j]] - c.X, NY[Nd[j]] - c.Y, NZ[Nd[j]] - c.Z);
      M11 := M11 + d.X * d.X; M12 := M12 + d.X * d.Y; M13 := M13 + d.X * d.Z;
      M22 := M22 + d.Y * d.Y; M23 := M23 + d.Y * d.Z; M33 := M33 + d.Z * d.Z;
      r1 := r1 + d.X * (Phi[Nd[j]] - pm);
      r2 := r2 + d.Y * (Phi[Nd[j]] - pm);
      r3 := r3 + d.Z * (Phi[Nd[j]] - pm);
    end;

    det := M11 * (M22 * M33 - M23 * M23) - M12 * (M12 * M33 - M23 * M13) +
           M13 * (M12 * M23 - M22 * M13);

    gr.X := (r1 * (M22 * M33 - M23 * M23) - M12 * (r2 * M33 - M23 * r3) +
             M13 * (r2 * M23 - M22 * r3)) / det;
    gr.Y := (M11 * (r2 * M33 - M23 * r3) - r1 * (M12 * M33 - M23 * M13) +
             M13 * (M12 * r3 - r2 * M13)) / det;
    gr.Z := (M11 * (M22 * r3 - r2 * M23) - M12 * (M12 * r3 - r2 * M13) +
             r1 * (M12 * M23 - M22 * M13)) / det;

    EleJ[i] := CurrentFrom(i, gr);
    EleJMag[i] := Sqrt(Dot(EleJ[i], EleJ[i]));

    // J.E, which is |J|^2/sigma where the tissue is isotropic.
    sg := -Dot(EleJ[i], gr) * EleVol[i];
    Pt[EleTissue[i]] := Pt[EleTissue[i]] + sg;
    Pdiss := Pdiss + sg;

  end;

  // The pads' potentials: the sternal pad should be one value across
  // its whole face, and the apex pad zero.
  VaMin := MaxDouble; VaMax := -MaxDouble; Vc := 0;

  for i := 0 to Length(PadFaces) - 1 do
    for j := 0 to 3 do
      if PadFaces[i].Pad = PadAnode then
      begin
        VaMin := Min(VaMin, Phi[PadFaces[i].N[j]]);
        VaMax := Max(VaMax, Phi[PadFaces[i].N[j]]);
      end
      else
        Vc := Max(Vc, Abs(Phi[PadFaces[i].N[j]]));

  Resistance := (VaMin + VaMax) / 2;

  // The current crossing the skin under the sternal pad, from the skin
  // elements' own current densities - an independent check on the 1 A.
  // Taken over the pad and a centimetre round it, since the current
  // crowds in at the pad's edge and the elements just outside it,
  // which share the edge's nodes, carry their share; beyond that the
  // skin is insulated and adds nothing but noise.
  PadI := 0;
  for i := 0 to Length(Skin) - 1 do
    if InPad(PadAnode,
             (NX[Skin[i].N[0]] + NX[Skin[i].N[2]]) / 2,
             (NY[Skin[i].N[0]] + NY[Skin[i].N[2]]) / 2,
             (NZ[Skin[i].N[0]] + NZ[Skin[i].N[2]]) / 2, 0.01) then
    begin
      Jn := -(EleJ[Skin[i].Ele].X * Skin[i].Nx + EleJ[Skin[i].Ele].Y * Skin[i].Ny +
              EleJ[Skin[i].Ele].Z * Skin[i].Nz);
      PadI := PadI + Jn * Skin[i].Area;
    end;

  Say('');
  Say('THE CURRENT, for 1 A pad to pad');
  Say(Format('  transthoracic resistance  %.1f ohm', [Resistance]));
  Say(Format('  sternal pad potential     %.3f to %.3f V (an equipotential to %.2f %%)',
    [VaMin, VaMax, 100 * (VaMax - VaMin) / Resistance]));
  Say(Format('  apex pad potential        within %.1e V of 0', [Vc]));
  Say(Format('  current into the skin at the sternal pad  %.3f A (should be 1)', [PadI]));
  Say(Format('  power in the tissue       %.2f W, against I^2 R = %.2f W', [Pdiss, Resistance]));
  Say('  where the power goes:');
  for t := tiCore to LastTissue do
    Say(Format('    %-11s %5.1f %%', [TissueName[t], 100 * Pt[t] / Pdiss]));

  // Elements by |J|, largest first, for the display.
  SetLength(EleByJ, NbEle);
  SetLength(Key, NbEle);
  for i := 0 to NbEle - 1 do
  begin
    EleByJ[i] := i;
    Key[i] := -EleJMag[i];
  end;
  SortByKey(EleByJ, Key, 0, NbEle - 1);

  // The myocardium's field per ampere, largest first, with cumulative
  // volume, so the fraction above any level is one search.
  m := 0;
  for i := 0 to NbEle - 1 do
    if EleTissue[i] = tiMyocardium then
      Inc(m);

  SetLength(Order, m);
  SetLength(Key, NbEle);
  k := 0;
  for i := 0 to NbEle - 1 do
    if EleTissue[i] = tiMyocardium then
    begin
      Order[k] := i;
      Key[i] := -EleJMag[i] / TissueSigma[tiMyocardium];
      Inc(k);
    end;

  if m > 1 then
    SortByKey(Order, Key, 0, m - 1);

  SetLength(MyoE, m);
  SetLength(MyoVolCum, m);
  MyoVol := 0;
  for i := 0 to m - 1 do
  begin
    MyoE[i] := EleJMag[Order[i]] / TissueSigma[tiMyocardium];
    MyoVol := MyoVol + EleVol[Order[i]];
    MyoVolCum[i] := MyoVol;
  end;

  // The current through the heart: the mean current through its slices
  // across the direction the current takes inside it. The integral of
  // J.n over the heart's volume is the integral along n of the current
  // through each slice, so dividing by the heart's extent along n gives
  // the mean slice current.
  Sum := Vec3(0, 0, 0);
  for i := 0 to NbEle - 1 do
    if EleTissue[i] in [tiMyocardium, tiBlood] then
    begin
      Sum.X := Sum.X + EleJ[i].X * EleVol[i];
      Sum.Y := Sum.Y + EleJ[i].Y * EleVol[i];
      Sum.Z := Sum.Z + EleJ[i].Z * EleVol[i];
    end;

  Ext := Normalised(Sum);
  FluxSum := Dot(Sum, Ext);
  HeartFraction := FluxSum /
    (2 * Sqrt(Sqr(Heart.R[0] * Dot(Ext, Heart.U[0])) +
              Sqr(Heart.R[1] * Dot(Ext, Heart.U[1])) +
              Sqr(Heart.R[2] * Dot(Ext, Heart.U[2]))));

end;

(*******************************************************************
  The discharge: q' = -i, L i' = q/C - R i, with R the device's own
  resistance plus the torso's, from the capacitor charged to store the
  setting's energy grossed up for the device's own loss into the
  reference 50 ohm (in a series discharge that runs to completion the
  load takes R_load/R_total of the stored energy, whatever the damping).
  RK4 at 1 us, kept every WaveSample.
********************************************************************)
procedure TDefibModel.ComputeWaveform;
const
  h = 1.0E-6;
var
  q, i_, Rt, E0, t, k1q, k1i, k2q, k2i, k3q, k3i, k4q, k4i : Double;
  n, Nout, Every, Step : Integer;
  Damping : String;

  procedure F(qq, ii : Double; out dq, di : Double);
  begin
    dq := -ii;
    di := (qq / DeviceC - Rt * ii) / DeviceL;
  end;

  // The biphasic truncated exponential, in closed form: I0 e^(-t/tau)
  // through phase 1, the same decay reversed through phase 2, then 0.
  procedure Biphasic_;
  var
    Tau, T1, T2, Frac_, I0, E1 : Double;
    k : Integer;
  begin
    Tau := Resistance * BiphasicC;
    T1 := -Tau * Ln(1 - BiphasicTilt);
    T2 := BiphasicRatio * T1;
    // The fraction of the stored energy delivered by the end of phase 2.
    Frac_ := 1 - Exp(-2 * (T1 + T2) / Tau);
    E0 := ShockEnergy / Frac_;
    V0 := Sqrt(2 * E0 / BiphasicC);
    I0 := V0 / Resistance;
    E1 := E0 * (1 - Exp(-2 * T1 / Tau));

    for k := 0 to Nout - 1 do
    begin
      t := k * WaveSample;
      WaveT[k] := t;
      // A nanosecond's grace, so rounding cannot move a sample at a
      // switch into the next phase.
      if t < T1 - 1E-9 then
        WaveI[k] := I0 * Exp(-t / Tau)
      else if t < T1 + T2 - 1E-9 then
        WaveI[k] := -I0 * Exp(-t / Tau)
      else
        WaveI[k] := 0;
    end;

    IPeak := I0;
    TPeak := 0;
    EDelivered := ShockEnergy;

    Say('');
    Say('THE SHOCK - biphasic truncated exponential');
    Say(Format('  %.0f uF straight into the torso, tau = RC = %.2f ms; charged to %.0f V ' +
      '(%.0f J stored)', [1E6 * BiphasicC, 1E3 * Tau, V0, E0]));
    Say(Format('  phase 1  %.2f ms to %.0f %% tilt, %.1f A falling to %.1f A, %.0f J',
      [1E3 * T1, 100 * BiphasicTilt, I0, I0 * (1 - BiphasicTilt), E1]));
    Say(Format('  phase 2  %.2f ms reversed, %.1f A falling to %.1f A, %.0f J',
      [1E3 * T2, -I0 * (1 - BiphasicTilt), -I0 * Exp(-(T1 + T2) / Tau),
       ShockEnergy - E1]));
    Say(Format('  %.0f J delivered into this torso (%.1f %% of the stored energy, ' +
      'at any resistance)', [EDelivered, 100 * Frac_]));
  end;

begin

  Nout := Round(WaveDuration / WaveSample) + 1;
  Every := Round(WaveSample / h);
  SetLength(WaveT, Nout);
  SetLength(WaveI, Nout);

  if FBiphasic then
  begin
    Biphasic_;
    Exit;
  end;

  E0 := ShockEnergy * (RefLoad + DeviceR) / RefLoad;
  V0 := Sqrt(2 * E0 / DeviceC);
  Rt := DeviceR + Resistance;

  q := DeviceC * V0;
  i_ := 0;
  t := 0;
  IPeak := 0;
  TPeak := 0;
  EDelivered := 0;
  WaveT[0] := 0;
  WaveI[0] := 0;

  for n := 1 to Nout - 1 do
  begin
    for Step := 1 to Every do
    begin
      F(q, i_, k1q, k1i);
      F(q + h / 2 * k1q, i_ + h / 2 * k1i, k2q, k2i);
      F(q + h / 2 * k2q, i_ + h / 2 * k2i, k3q, k3i);
      F(q + h * k3q, i_ + h * k3i, k4q, k4i);
      q := q + h / 6 * (k1q + 2 * k2q + 2 * k3q + k4q);
      i_ := i_ + h / 6 * (k1i + 2 * k2i + 2 * k3i + k4i);
      t := t + h;
      EDelivered := EDelivered + i_ * i_ * Resistance * h;
      if Abs(i_) > IPeak then
      begin
        IPeak := Abs(i_);
        TPeak := t;
      end;
    end;
    WaveT[n] := t;
    WaveI[n] := i_;
  end;

  Say('');
  Say('THE SHOCK - monophasic damped sine (Edmark/Lown)');
  Say(Format('  %.0f uF, %.0f mH, %.0f ohm in the device; charged to %.0f V (%.0f J stored)',
    [1E6 * DeviceC, 1E3 * DeviceL, DeviceR, V0, E0]));
  Say(Format('  peak current %.1f A at %.2f ms; %.0f J delivered into this torso',
    [IPeak, 1E3 * TPeak, EDelivered]));
  if Rt < 2 * Sqrt(DeviceL / DeviceC) then
    Damping := 'underdamped, a small reversed tail'
  else
    Damping := 'overdamped, no reversal';

  Say(Format('  2*sqrt(L/C) = %.0f ohm against %.0f ohm in the circuit: %s',
    [2 * Sqrt(DeviceL / DeviceC), Rt, Damping]));

end;

// Element centres binned on a uniform grid, for looking up the field
// near a point.
procedure TDefibModel.BuildGrid;
var
  i, c, ix, iy, iz : Integer;
  Count : TIntegerArray;
begin

  FGridH := 0.010;
  FGridOrg := Vec3(-FA - 0.01, -0.01, -0.01);
  FGridN[0] := Ceil((2 * FA + 0.02) / FGridH);
  FGridN[1] := Ceil((2 * FB + 0.02) / FGridH);
  FGridN[2] := Ceil((FLen + 0.02) / FGridH);

  SetLength(Count, FGridN[0] * FGridN[1] * FGridN[2] + 1);
  for i := 0 to Length(Count) - 1 do
    Count[i] := 0;

  for i := 0 to NbEle - 1 do
  begin
    ix := EnsureRange(Trunc((EleC[i].X - FGridOrg.X) / FGridH), 0, FGridN[0] - 1);
    iy := EnsureRange(Trunc((EleC[i].Y - FGridOrg.Y) / FGridH), 0, FGridN[1] - 1);
    iz := EnsureRange(Trunc((EleC[i].Z - FGridOrg.Z) / FGridH), 0, FGridN[2] - 1);
    Inc(Count[(iz * FGridN[1] + iy) * FGridN[0] + ix + 1]);
  end;

  for i := 1 to Length(Count) - 1 do
    Count[i] := Count[i] + Count[i - 1];

  FCellStart := Copy(Count);
  SetLength(FCellItem, NbEle);

  for i := 0 to NbEle - 1 do
  begin
    ix := EnsureRange(Trunc((EleC[i].X - FGridOrg.X) / FGridH), 0, FGridN[0] - 1);
    iy := EnsureRange(Trunc((EleC[i].Y - FGridOrg.Y) / FGridH), 0, FGridN[1] - 1);
    iz := EnsureRange(Trunc((EleC[i].Z - FGridOrg.Z) / FGridH), 0, FGridN[2] - 1);
    c := (iz * FGridN[1] + iy) * FGridN[0] + ix;
    FCellItem[Count[c]] := i;
    Inc(Count[c]);
  end;

end;

// The current density at P, inverse-distance weighted over the element
// centres within a grid cell or so. False outside the trunk.
function TDefibModel.FieldAt(const P : TVec3; out J : TVec3) : Boolean;
var
  ix, iy, iz, a, b, c, k, e : Integer;
  w, ws, d2, R2 : Double;
begin

  Result := False;
  J := Vec3(0, 0, 0);

  if (P.Z < 0) or (P.Z > FLen) or (S(P.X, P.Y) > FA - SectionShift(P.Z)) then
    Exit;

  ix := Trunc((P.X - FGridOrg.X) / FGridH);
  iy := Trunc((P.Y - FGridOrg.Y) / FGridH);
  iz := Trunc((P.Z - FGridOrg.Z) / FGridH);

  R2 := Sqr(1.2 * FGridH);
  ws := 0;

  for c := Max(0, iz - 1) to Min(FGridN[2] - 1, iz + 1) do
    for b := Max(0, iy - 1) to Min(FGridN[1] - 1, iy + 1) do
      for a := Max(0, ix - 1) to Min(FGridN[0] - 1, ix + 1) do
      begin
        k := (c * FGridN[1] + b) * FGridN[0] + a;
        for e := FCellStart[k] to FCellStart[k + 1] - 1 do
        begin
          d2 := Sqr(EleC[FCellItem[e]].X - P.X) + Sqr(EleC[FCellItem[e]].Y - P.Y) +
                Sqr(EleC[FCellItem[e]].Z - P.Z);
          if d2 > R2 then
            Continue;
          w := 1 / (d2 + 4E-6);
          ws := ws + w;
          J.X := J.X + w * EleJ[FCellItem[e]].X;
          J.Y := J.Y + w * EleJ[FCellItem[e]].Y;
          J.Z := J.Z + w * EleJ[FCellItem[e]].Z;
        end;
      end;

  if ws = 0 then
    Exit;

  J := Vec3(J.X / ws, J.Y / ws, J.Z / ws);
  Result := Dot(J, J) > 0;

end;

(*******************************************************************
  Field lines of the current, from the sternal pad to the apex pad.
  Each starts under the sternal pad at a point drawn in proportion to
  the current entering the skin there, so every line carries the same
  share of the current and their crowding IS the current density. Each
  then follows J (midpoint rule, 2 mm steps) until it reaches the skin
  under the apex pad.
********************************************************************)
procedure TDefibModel.TraceLines;
const
  StepLen = 0.002;
  MaxSteps = 1500;
var
  Faces : TIntegerArray;
  Cum : TDoubleArray;
  nf, i, k, f, n, Reached : Integer;
  Tot, Target, u, v, Jn, sp : Double;
  P, Q, J1, J2, D : TVec3;
  Line : TPolyline;
  Done : Boolean;
begin

  BuildGrid;

  nf := 0;
  SetLength(Faces, Length(Skin));
  SetLength(Cum, Length(Skin));
  Tot := 0;

  for i := 0 to Length(Skin) - 1 do
    if Skin[i].Pad = PadAnode then
    begin
      Jn := -(EleJ[Skin[i].Ele].X * Skin[i].Nx + EleJ[Skin[i].Ele].Y * Skin[i].Ny +
              EleJ[Skin[i].Ele].Z * Skin[i].Nz);
      Tot := Tot + Max(0, Jn) * Skin[i].Area;
      Faces[nf] := i;
      Cum[nf] := Tot;
      Inc(nf);
    end;

  SetLength(Lines, NbFieldLines);
  Reached := 0;

  for k := 0 to NbFieldLines - 1 do
  begin

    Target := (k + 0.5) / NbFieldLines * Tot;
    f := 0;
    while (f < nf - 1) and (Cum[f] < Target) do
      Inc(f);
    i := Faces[f];

    // A point within the face, by a low-discrepancy sequence.
    u := Frac(0.5 + k * 0.6180339887);
    v := Frac(0.5 + k * 0.7548776662);

    P.X := (1 - u) * (1 - v) * NX[Skin[i].N[0]] + u * (1 - v) * NX[Skin[i].N[1]] +
           u * v * NX[Skin[i].N[2]] + (1 - u) * v * NX[Skin[i].N[3]];
    P.Y := (1 - u) * (1 - v) * NY[Skin[i].N[0]] + u * (1 - v) * NY[Skin[i].N[1]] +
           u * v * NY[Skin[i].N[2]] + (1 - u) * v * NY[Skin[i].N[3]];
    P.Z := (1 - u) * (1 - v) * NZ[Skin[i].N[0]] + u * (1 - v) * NZ[Skin[i].N[1]] +
           u * v * NZ[Skin[i].N[2]] + (1 - u) * v * NZ[Skin[i].N[3]];

    P.X := P.X - 0.0005 * Skin[i].Nx;
    P.Y := P.Y - 0.0005 * Skin[i].Ny;
    P.Z := P.Z - 0.0005 * Skin[i].Nz;

    SetLength(Line, MaxSteps + 2);
    Line[0] := P;
    n := 1;
    Done := False;

    while (n <= MaxSteps) and not Done do
    begin

      if not FieldAt(P, J1) then
        Break;

      sp := Sqrt(Dot(J1, J1));
      D := Vec3(J1.X / sp, J1.Y / sp, J1.Z / sp);
      Q := Vec3(P.X + D.X * StepLen / 2, P.Y + D.Y * StepLen / 2, P.Z + D.Z * StepLen / 2);

      if FieldAt(Q, J2) then
      begin
        sp := Sqrt(Dot(J2, J2));
        D := Vec3(J2.X / sp, J2.Y / sp, J2.Z / sp);
      end;

      P := Vec3(P.X + D.X * StepLen, P.Y + D.Y * StepLen, P.Z + D.Z * StepLen);
      Line[n] := P;
      Inc(n);

      // Arrived: at the skin, over the apex pad.
      if (S(P.X, P.Y) > FA - SectionShift(P.Z) - 0.0015) and
         InPad(PadCathode, P.X, P.Y, P.Z, 0.004) and (n > 5) then
      begin
        Done := True;
        Inc(Reached);
      end;

    end;

    SetLength(Line, n);
    Lines[k] := Line;

  end;

  Say(Format('  %d field lines traced, %d of them reaching the apex pad',
    [NbFieldLines, Reached]));

end;

function TDefibModel.MyoFractionAbove(Ecrit, I : Double) : Double;
var
  lo, hi, mid : Integer;
  e : Double;
begin

  Result := 0;
  if (Length(MyoE) = 0) or (I = 0) then
    Exit;

  // MyoE is descending; find how many exceed Ecrit/|I|.
  e := Ecrit / Abs(I);
  lo := 0;
  hi := Length(MyoE);
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if MyoE[mid] >= e then
      lo := mid + 1
    else
      hi := mid;
  end;

  if lo > 0 then
    Result := MyoVolCum[lo - 1] / MyoVol;

end;

function TDefibModel.VolumeAbove(Jcrit, I : Double) : Double;
var
  k : Integer;
begin
  Result := 0;
  if I = 0 then
    Exit;
  k := 0;
  while (k < NbEle) and (EleJMag[EleByJ[k]] * Abs(I) >= Jcrit) do
  begin
    Result := Result + EleVol[EleByJ[k]];
    Inc(k);
  end;
end;

procedure TDefibModel.ReportResults;
var
  Emean, Vm : Double;
  i : Integer;
begin

  Say('');
  Say(Format('THE HEART, at the peak current of %.1f A', [IPeak]));
  Say(Format('  current through the heart   about %.1f %% of the pad current (%.1f A)',
    [100 * HeartFraction, HeartFraction * IPeak]));

  Emean := 0;
  Vm := 0;
  for i := 0 to NbEle - 1 do
    if EleTissue[i] = tiMyocardium then
    begin
      Emean := Emean + EleJMag[i] / TissueSigma[tiMyocardium] * EleVol[i];
      Vm := Vm + EleVol[i];
    end;
  Emean := Emean / Vm;

  if Length(MyoE) > 0 then
  begin
    Say(Format('  field in the myocardium     mean %.1f V/cm, from %.1f to %.1f',
      [Emean * IPeak / 100, MyoE[High(MyoE)] * IPeak / 100, MyoE[0] * IPeak / 100]));
    Say(Format('  myocardium at %.0f V/cm or more  %.0f %% of its volume',
      [DefibFieldVcm, 100 * MyoFractionAbove(DefibFieldVcm * 100, IPeak)]));
    Say(Format('  myocardium at 2.5 V/cm or more   %.0f %%',
      [100 * MyoFractionAbove(250, IPeak)]));
  end;

  Say('');
  Say('  Both are high against the literature: Lerman and Deale (1990) measured');
  Say('  about 4 % of the transthoracic current crossing the heart, in dogs, and');
  Say('  defibrillation is usually taken to need some 5 V/cm through most of the');
  Say('  myocardium, which a 200 J shock clears with modest margin. The chest');
  Say('  wall and ribs lower the heart''s share: the wall shunts current round the');
  Say('  ribcage, and the ribs push what enters through the gaps between them.');
  if FAnisotropic then
  begin
    Say('  Anisotropic muscle raises both the resistance (71 ohm isotropic) and the');
    Say('  heart''s share (11.2 % isotropic). Fibres round the trunk carry current');
    Say('  well only round it: across them - inwards, and up and down the trunk -');
    Say('  the muscle now conducts 0.076 S/m instead of 0.25, so the wall stops');
    Say('  spreading current along the body and away from the heart, and more of');
    Say('  it takes the short way through the core. Real chest-wall fibres run');
    Say('  obliquely and in layers, which this single direction leaves out.');
  end
  else
  begin
    Say('  Muscle is isotropic here; skeletal muscle conducts about seven times');
    Say('  better along its fibres than across them (run with --anisotropic).');
  end;
  Say('  Still missing: a lean, smooth trunk with no breasts or arms, and lungs');
  Say('  and heart as single conductivities.');
  if FBiphasic then
  begin
    Say('');
    Say('  A biphasic shock defibrillates at lower energy and peak current than a');
    Say('  monophasic one: the reversed second phase is thought to undo the charge');
    Say('  phase 1 leaves on cells it did not capture, so that 5 V/cm figure is');
    Say('  conservative for it.');
  end;

  Say('');
  Say('  The field pattern does not travel or diffuse: tissue relaxes charge in');
  Say('  microseconds, so every current density follows I(t) at once. What spreads');
  Say('  in the animation is the region above the chosen current density.');

end;

procedure TDefibModel.Run;
begin

  SetupGeometry;
  BuildMesh;
  ClassifyElements;
  FindSurface;
  BuildEngine;
  Solve;
  PostProcess;
  TraceLines;
  FShockStart := FReport.Count;
  ComputeWaveform;
  ReportResults;
  FRan := True;

end;

procedure TDefibModel.SetBiphasic(V : Boolean);
begin

  if V = FBiphasic then
    Exit;

  FBiphasic := V;

  if not FRan then
    Exit;

  while FReport.Count > FShockStart do
    FReport.Delete(FReport.Count - 1);

  ComputeWaveform;
  ReportResults;

end;

function TDefibModel.WaveName : String;
begin
  if FBiphasic then
    Result := 'biphasic truncated exponential'
  else
    Result := 'monophasic damped sine';
end;

function TDefibModel.FibreDir(X, Y : Double) : TVec3;
var
  gx, gy, L : Double;
begin
  // The normal of the similar ellipse through (X, Y) is the gradient of
  // X^2 + ((Y - Cy)/K)^2; the fibre is perpendicular to it, horizontal.
  gx := X;
  gy := (Y - FCy) / Sqr(FK);
  L := Sqrt(gx * gx + gy * gy);
  if L = 0 then
    Result := Vec3(1, 0, 0)
  else
    Result := Vec3(-gy / L, gx / L, 0);
end;

function TDefibModel.IsAnisotropic(i : Integer) : Boolean;
begin
  Result := FAnisotropic and (EleTissue[i] in [tiMuscle, tiWall]);
end;

function TDefibModel.CurrentFrom(i : Integer; const Grad : TVec3) : TVec3;
var
  f : TVec3;
  sg, gf : Double;
begin
  if IsAnisotropic(i) then
  begin
    // -(sigma_T grad + (sigma_L - sigma_T) (f.grad) f)
    f := FibreDir(EleC[i].X, EleC[i].Y);
    gf := (MuscleSigmaL - MuscleSigmaT) * Dot(f, Grad);
    Result := Vec3(-(MuscleSigmaT * Grad.X + gf * f.X),
                   -(MuscleSigmaT * Grad.Y + gf * f.Y),
                   -(MuscleSigmaT * Grad.Z + gf * f.Z));
  end
  else
  begin
    sg := TissueSigma[EleTissue[i]];
    Result := Vec3(-sg * Grad.X, -sg * Grad.Y, -sg * Grad.Z);
  end;
end;

initialization

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';

end.
