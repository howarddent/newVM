unit uThermEx1;

{ ThermEx1 - core temperature of an anaesthetised adult losing heat to a
  cold theatre. A head, a trunk and four limbs, each built from the
  compartments that belong in it, with conduction and blood perfusion.

  A 70 kg adult, 1.75 m tall and 5% body fat, generating heat at rest and
  losing it from the skin into a 16 C theatre while lying on a foam
  mattress. The question it answers is how the CORE temperature moves
  over the course of a case.

  THE COMPARTMENTS

  Four tissue compartments, innermost outward:

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

  Masses come to the 70 kg: 32.20 core, 31.50 muscle, 3.50 fat (the 5%),
  2.80 skin - the proportions of the 75 kg subject this model was first
  written for, scaled. Muscle at 45% and skin at 4% of body mass are
  ordinary figures for a lean adult, and the core is what is left.

  THE SEGMENTS

  The body is not one shape but six, each carrying the compartments that
  belong in it:

    head       a sphere                  core, muscle, fat, skin
    trunk      an elliptical cylinder    core, muscle, fat, skin
    two arms   circular cylinders        muscle, fat, skin
    two legs   circular cylinders        muscle, fat, skin

  Segment masses are 7.0% of the body for the head, 50.8% for the trunk,
  4.9% for each arm and 16.2% for each leg - the classic cadaver
  proportions (Dempster, Clauser), with the neck counted in the trunk and
  the hand and foot in their limb. Surface areas follow Lund and Browder's
  adult chart: 7% head, 34% trunk (neck, front, back, buttocks and
  perineum), 9.5% each arm and 20% each leg.

  Within a segment:

    skin and fat are shared out by surface area, so each lies at much
      the same depth all over the body, as the subcutaneous layers do
    a limb has no core, so everything else in it is muscle - its bone
      included, which is the price of three compartments
    the head's muscle is fixed at 0.40 kg - scalp, face and jaw - and
      the rest of it is core: brain, skull and what else is inside
    the trunk takes whatever core the head does not, and its muscle is
      what is then left of its mass

  which gives, in kg:

               core   muscle    fat   skin
    head       4.06     0.40   0.25   0.20
    trunk     28.14     5.28   1.19   0.95
    each arm      -     2.83   0.33   0.27
    each leg      -    10.08   0.70   0.56

  The report prints every one of them.

  A volume sets a segment's heat store and a surface area its loss, so
  both have to be right or the energy balance is wrong.

  The cylinders match both exactly. With k the axis ratio of the section
  (minor over major - 0.5 for the trunk, which lies twice as wide as it
  is deep, and 1 for a limb) and p1 = p1(k) the perimeter of the unit
  ellipse of that ratio, from Ramanujan's approximation (2*pi for a
  circle, 4.8442 at k = 0.5), matching the volume V and the area A gives

    a = p1*V/(pi*k*A),   b = k*a,   L = V/(pi*a*b)

  with the ends adiabatic, so the whole of the area is lateral. That puts
  the trunk at 334 mm wide by 167 mm deep and 0.78 m long, each arm at
  75 mm across and 0.74 m long, and each leg at 118 mm across and 1.00 m
  long - ordinary adult proportions, arrived at from the two fractions
  alone.

  A sphere has only its radius to set, so it cannot match both. Sized by
  volume, the head comes out at 103.9 mm radius with 0.136 m2 of surface
  against its nominal 0.129 m2, 5% over; the report works from the
  meshed area throughout, so that goes straight into the energy balance
  rather than being papered over.

  Every compartment boundary is a SIMILAR shape to the segment's outline,
  scaled by cumulative volume - concentric spheres in the head, similar
  ellipses in the trunk, concentric circles in the limbs - and every
  point is labelled by the size s of the similar shape through it: the
  radius in the head and limbs, and in the trunk the semi-major axis of
  the similar ellipse, s = sqrt(x^2 + (y/k)^2) about the axis. That is
  the radial coordinate the profile plot and the closed-form check use.

  What similar ellipses cost in the trunk is that a layer is thinner over
  the front and back than at the sides, by exactly the factor k, where a
  real skin layer is closer to constant thickness. The spheres and circles
  carry no such error.

  The patient lies supine with every segment resting on the cushion: the
  trunk along the middle, the head beyond its upper end, the arms at its
  sides and the legs below it. The segments are NOT joined. The neck,
  shoulder and hip ends are adiabatic, and the only thing that carries
  heat from one segment to another is the blood - which is how the
  classic multi-segment thermoregulation models, Stolwijk's among them,
  couple their segments too. It is also a fair account of the physiology:
  conduction along a limb, through a joint and the better part of a metre
  of tissue, is negligible beside what perfusion carries.

  GENERATION

  Generation is split by the organ-specific resting rates: brain 20% of
  basal, liver 21%, heart 9%, kidneys 8%, skeletal muscle 22%, the
  remainder 16%. The brain is the head's core, and liver, heart, kidneys
  and the remainder the trunk's, which puts 20% in the head core and 54%
  in the trunk core; muscle takes 23% and skin 3%, each shared among the
  segments by volume, and fat is held at zero. Of the 83.7 W total that
  is 16.7 W in the head's core, 45.2 W in the trunk's, 19.2 W in muscle
  and 2.5 W in skin. Note what the layers do to the volumetric rates -
  the head's core generates 4300 W/m3, the trunk's 1700 and muscle only
  640 - so the compartments matter as much for WHERE the heat appears as
  for how it conducts.

  PERFUSION

  Blood carries heat between the compartments far faster than tissue
  conducts it, and that is the mechanism behind redistribution - the
  early core fall after induction, as a vasodilated periphery draws on
  a warm core. The model carries it as the Pennes term, a volumetric
  exchange in each compartment with blood arriving at the pool
  temperature, distributed by the resting shares of cardiac output: 14%
  to the head's core (the brain), 61% to the trunk's, 18% to muscle, 5%
  to skin and 2% to fat, the last three shared among the segments by
  volume.

  The pool closes the loop, and with the segments unjoined it is also
  the only path between them. With no external source or sink of blood
  heat, a well-mixed pool sits at the FLOW-WEIGHTED MEAN tissue
  temperature, which makes the net perfusion heat identically zero -
  perfusion moves heat about and creates none. The report carries that
  net out and prints it, so the claim is checked rather than asserted.

  The pool is carried as a node of the model in its own right, joined to
  every perfused tissue node by a conduction link whose conductance is
  that node's Pennes conductance, and which stores no heat. A node with no
  heat capacity can only sit where what flows into it balances what flows
  out, which is exactly the flow-weighted mean, so the solver finds the
  pool temperature in the same linear system as the tissue. Perfusion is
  therefore implicit - no lag, no stability limit on the step - and a
  perfused steady state is a single static solve. That matters for the
  starting state; see THE TWO CASES.

  Before induction the skin's flow is shut, by the awake patient's
  thermoregulatory vasoconstriction, while the core, muscle and fat stay
  perfused. At t = 0 induction abolishes that tone and the skin opens to
  its full share - and heat flowing out from the core into newly perfused
  skin is the redistribution the run shows.

  Cardiac output is a parameter, 1 to 10 L/min, on a slider in the plot
  window. There is no zero - see CardiacOutputMin for why a body of these
  proportions has no balanced state without blood. What the slider shows,
  exposed at t = 0, is strongly non-linear: at 1 L/min the core falls
  0.76 C/h, at 5 it falls 1.44, and at 10 only 1.62 - once blood has
  flattened the internal resistance, more of it barely matters, because
  the bottleneck has moved to the skin surface.

  METABOLISM AND TEMPERATURE

  A body that has cooled does not go on generating heat at the rate it
  did at 37 C. Metabolic rate follows temperature the way any enzymatic
  process does, by van't Hoff's Q10 - the factor per 10 K - so the
  generation is scaled by

    Q10^((Tcore - 37)/10)

  Q10 is 2.0 here, near the low end of the 2 to 2.5 usually quoted for
  whole-body human metabolism in hypothermia, and worth 7.2% per degree.
  Over the exposed run at 5 L/min the core falls 2.9 C and generation
  with it, from 83.7 W to 68.6 W - 82% of the set-point rate - and that
  feeds back: less heat generated is faster cooling, which is less heat
  again.

  The scaling is read off the CORE temperature - the middle of the trunk -
  and applied to the whole body rather than node by node, which is the
  more defensible choice rather than the lazier one: published Q10
  figures are measured against core temperature and already contain the
  fact that the periphery cools further than the core. The full argument
  is in UpdateSources, which is where the scaling happens.

  Q10 = 1 removes the effect entirely and holds generation at 83.7 W.

  WHAT IS AND IS NOT IN THE MODEL

  In: conduction through every compartment of every segment, heat
  storage, metabolic generation where it actually arises and falling with
  temperature by Q10, blood perfusion, surface losses by convection and
  radiation into still air at 16 C from the exposed surface, and
  conduction through the cushion from the surface lying on it.

  Out, deliberately: conduction between segments, discussed under THE
  SEGMENTS; respiratory and cutaneous evaporative loss; vasomotor control,
  so the flow shares are fixed rather than responding to temperature; any
  distinction between arterial and venous blood beyond the single
  well-mixed pool, so the countercurrent exchange that keeps heat out of a
  cold limb is missing too; and the cushion's own transient warm-up,
  discussed under THE CUSHION.

  Two things about the generation in particular are still out. Shivering
  is one: muscle's share is the basal figure and cannot rise, which is
  right for a paralysed or deeply anaesthetised patient and wrong for a
  waking one. The other is that VO2 = 250 mL/min is an AWAKE resting
  figure, and anaesthesia itself depresses metabolic rate 20 to 30% at
  induction - a step change at t = 0, quite separate from the Q10 slide
  that follows, and not modelled. The model therefore starts some 20%
  warmer in its heat production than the patient it describes.

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

  Each segment has its own patch. On the trunk and the limbs it is the
  part of the section within 60 degrees of straight down - on the trunk's
  ellipse, broad and flat underneath where the radius of curvature is
  four times the minor semi-axis, that is about 38% of its surface, and on
  a round limb exactly a third. On the head it is the cap within 45
  degrees of straight down, the back of the skull, which is 15% of a
  sphere. Over the whole body that comes to 32% of the surface - the
  well-known clinical point that only some two thirds of the body surface
  is available to lose heat, arrived at here from the geometry rather than
  assumed.

  Radiation is applied to the exposed surface only: a surface in contact
  with foam has nothing to radiate to.

  THE GOWN

  Case 3 dresses the patient: a thin cotton gown over the front of the
  trunk and the arms - the segments GownSegments names - with a
  millimetre of still air trapped between it and the skin. The head and
  the legs stay bare, and the patch on the cushion is exactly as it was.

  It is built as elements, not as a surface coefficient. Every exposed
  skin face of a covered segment is extruded outward along the section's
  normal into a brick of still air a millimetre thick and a brick of
  cloth a millimetre thick on top of that (BuildGown), with the nodes
  shared between neighbouring faces so the gown is one continuous sheet.
  The room's conditions - the drape coefficient before induction, bare
  convection and radiation after it - then go on the cloth's OUTER face,
  and the skin beneath sees nothing but the air's own conduction. Heat
  crosses the gap by conduction alone: a millimetre of still air is far
  too thin to convect, and radiation across the gap is left out as
  specified. The cloth radiates at its own emissivity, 0.90, not the
  skin's 0.98.

  Elements rather than a series conductance because the two are not the
  same thing once radiation is on. A coefficient folded into the skin's
  boundary condition would have the skin's T^4 radiating, at the skin's
  temperature; what actually radiates is the cloth, several degrees
  colder, and the elements put the cloth's own temperature into that
  term for nothing. They also make the gown a thing the report can
  measure - its outer face is printed beside the skin under it - and
  keep its (small) heat capacity in the energy balance.

  What the gown is worth: 1 mm of air at 0.026 W/mK is 0.038 m2K/W, and
  1 mm of cotton cloth at 0.06 W/mK a further 0.017, so 0.055 m2K/W in
  all, about a third of a clo, in series with a surface resistance near
  0.12 m2K/W (convection at 3 W/m2K plus radiation near 5.5). That is a
  little under half again on the total resistance over the covered
  area, which is half of the exposed skin (0.633 m2 of 1.255). The
  result is under WHAT THE GOWN DOES TO THE ANSWER below.

  The closed-form check takes the gown out of the way - the uniform
  coefficient goes on the skin beneath it, and the cloth gets no
  condition, so nothing leaves through it - since the chains describe
  the tissue and nothing else. The one trace the gown still leaves is
  conduction ALONG its own sheet, which on the trunk carries a little
  heat from the warm side of the ellipse round to the cool one: the
  head and limbs check to the same digits as without it, and the
  trunk's spread column moves by a few thousandths of a kelvin. The
  draped calibration puts its coefficient on the cloth where there is
  cloth, and its update model carries the gown's resistance in series
  over the covered area, so it still converges in a few solves.

  What this leaves out is the cushion's own warm-up. Foam has a thermal
  diffusivity near 7e-7 m2/s, so 100 mm of it takes some four hours to
  settle into the straight-line profile the U value assumes, and for the
  first hour or so the patch behaves more like a semi-infinite solid at
  room temperature - about 0.65 W/m2K at half an hour, against the 0.37
  it tends to. On a 20 K difference that is a few watts out of ninety,
  and always in the direction of losing slightly more early on than the
  model says.

  VERIFICATION

  Each segment's layered profile is checked against a closed form, layer
  by layer, with the report printing both. There is one closed form per
  shape.

  The limbs are concentric circles and the head concentric spheres, both
  genuinely one-dimensional, so their chains are exact. For a solid
  generating uniformly and each shell outside it, carrying power Qin from
  within and generating its own at q, the drops are

    circle   solid  q*R^2/(4*kc)
             shell  (Qin - q*pi*s0^2*L)/(2*pi*kc*L) * ln(s1/s0)
                    + q*(s1^2 - s0^2)/(4*kc)
    sphere   solid  q*R^2/(6*kc)
             shell  (Qin - q*(4/3)*pi*s0^3)/(4*pi*kc) * (1/s0 - 1/s1)
                    + q*(s1^2 - s0^2)/(6*kc)

  The trunk's ellipse needs more care. A shell between s and s+ds has
  perimeter p1*s and, since similar ellipses are not parallel curves, a
  thickness that varies around it as k*ds/N with N = sqrt(sin^2 t + k^2
  cos^2 t). Integrating the conductance around the shell gives a total
  exactly as if the perimeter were Pc = pi*(1 + k^2)/k and the thickness
  uniform, so the circular chain carries over with 2*pi replaced by Pc and
  pi*r^2 by pi*k*s^2. Its solid part is exact at any k - a uniformly
  generating solid ellipse held at a fixed boundary temperature has the
  exact solution q*a^2*b^2/(2*kc*(a^2+b^2)) - but its shells are exact only
  in the thin-shell limit, since a layered ellipse has no genuinely
  one-dimensional solution.

  So the finite-element answer is the arbiter, and the check is run in a
  configuration where the chains are entitled to be right: one extra
  static solve with a UNIFORM surface coefficient, no cushion and no
  blood. With nothing crossing between segments, each segment's skin must
  then sit P/(h*A) above the room on its own generation P and its own
  area A, so the check also confirms that the segments really are
  independent. That solve prints the spread of temperature around each
  boundary as well, which is the size of the two-dimensional effect a
  chain cannot see - mesh noise on the head and limbs, real on the trunk.

  The draped coefficient itself is not taken from the chain. With the
  cushion in place the surface is not uniform and no chain can set it, so
  it is calibrated on the finite-element model directly, by secant
  iteration on static solves until the trunk's core sits at the set
  point.

  The model's other checks on itself run every step of every case. The
  balance column is generation minus surface loss minus the rate of change
  of stored energy, the two sides computed independently; and the net heat
  the blood delivers, which a pool that stores nothing must return to
  zero, is printed beside it. Case 1 used to add a third - held at a
  cardiac output of zero, nothing moved at all - but there is no zero on
  this body: see CardiacOutputMin. Run case 1 now and it moves, by design
  and not by error: the skin's blood flow opens at t = 0 with the drapes
  still on, and what follows is redistribution alone - see the note in
  Solve on why the starting state is built that way.

  This rests on the 3D elements being right. Hexahedra and prisms are
  checked in Examples/ThermSlab, which found and now guards two defects in
  them (TBrick_H8V1's node ordering and TBrick_W6V1's integration
  weights). The head's core is meshed in tetrahedra, TBrick_T4V1, which
  ThermSlab does not cover; the head's row in the closed-form check, and
  the energy balance the run prints at every step, are what check those.

  UNITS

  Everything is SI, and every temperature is in KELVIN. That is not
  optional: the radiation boundary condition evaluates T^4 directly and
  the framework applies no Celsius offset anywhere, so a model written in
  Celsius would silently compute the wrong radiative flux. Only the
  report converts back to Celsius.

  WHAT THE BODY SHAPE DOES TO THE ANSWER

  At 5 L/min, exposed at t = 0, the core falls 1.44 C/h - 2.9 C over the
  two hours - against the 2.33 C/h the single elliptical cylinder gave for
  a 75 kg subject (see git history before the segmented body). The two are
  not a like-for-like comparison, and the reasons they differ are the
  point of the change rather than noise around it:

    the old starting state had no blood in it, so switching all of the
    blood on at t = 0 was itself a large redistribution; here only the
    skin opens, and the rest of the body starts perfused
    the old draped state left the front skin at 28 C, cold for an awake
    patient under drapes; here it starts at 34, and a warmer skin loses
    more heat once bare - the loss is 203 W in the first minute against
    131 W - which is why the fall is not slower still
    the body is 70 kg instead of 75, with a head, limbs and a trunk of
    real proportions carrying the heat where it actually arises

  Of the 162 W leaving at the end, 3.9 W goes out through the foam, and
  generation is down to 68.6 W. The by-segment table shows each part of
  the body falling roughly together - the head's centre from 37.1 to 34.1,
  the arms' from 36.3 to 33.6, the legs' from 36.9 to 34.4 - because the
  blood, now open everywhere, holds them together.

  WHAT THE GOWN DOES TO THE ANSWER

  Case 3 against case 2, both at 5 L/min, both from the same 37 C core
  and both with the drapes off at t = 0:

                                     bare (2)     gowned (3)
    core after 2 h, C                  34.11         34.78
    core fall, C/h                     -1.44         -1.10
    loss in the first minute, W        203           173
    loss at the end, W                 162           144
    generation at the end, W           68.6          71.9
    front skin at the end, C           30.3          31.4
    gown's outer face at the end, C      -           26.9

  The gown takes a quarter off the rate of cooling. The cloth sits some
  five degrees below the skin under it - 29 C against 34 at t = 0, 27
  against 32 at the end - which is the air gap and the cloth dropping
  the whole of that between them, and it is the cloth's 27 C, not the
  skin's 32, that the room sees by convection and radiation. The head
  and the legs, still bare, lose exactly as they did; the trunk's loss at
  the end falls from 51.5 W to 37.8 and each arm's from 15.1 to 11.4.

  The drape coefficient the balanced start calibrates to is 3.70 W/m2K
  with the gown against 3.43 without: the same core needs the same heat
  out, and with the gown in series over half the front the surface
  beyond it has to be a little more open to pass it.

  THE THREE CASES

  All start from the same physiological steady state: a static solve
  with the drape coefficient calibrated so the body is exactly in
  balance with a 37 C core - which is what "the skin initially emits as
  much heat as is being generated" means once you work out what it
  implies. The patient is on the cushion from the start, in every case,
  because that is the clinical picture: what changes at induction is the
  drapes over the front, not what is underneath - and in case 3 the gown
  is part of what is underneath, worn under the drapes from the start.

  It is settled WITH blood flowing, at the awake patient's flows - the
  skin shut, everything else open - because on a body of these
  proportions nothing else can balance: see the note in Solve. At 5 L/min
  the calibration lands on a drape coefficient of 3.43 W/m2K, and the
  body sits where an awake, draped patient should - the centres of the
  head 37.1 C, the trunk 37.0, the legs 36.9 and the arms 36.3, the skin
  34 to 35 C at the front and 36 to 37 C on the cushion, losing 79 W to
  the room and 4.5 W through the foam.

    1  draped - the balanced state is simply held. At a cardiac output
       of zero nothing moves at all, which makes this the model's own
       check on itself; with blood flowing, redistribution alone still
       cools the core, drapes or no drapes.
    2  exposed - at t = 0 the drapes come off the front: its coefficient
       drops to bare-skin natural convection and radiation is switched
       on, while the contact patch carries on conducting into the
       cushion exactly as before. This is the tracking run.

    3  gowned - as 2, but the front of the trunk and the arms are under
       the cotton gown described under THE GOWN, so the bare coefficient
       and the radiation go on the cloth there and on the skin only over
       the head and legs. Everything else is as in 2, so the difference
       between the two runs is the gown and nothing else. }

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

  BodyMass = 70.0;          // kg - the compartment masses must add up to it
  BodySurfaceArea = 1.848;  // m2, DuBois for 70 kg / 1.75 m

  VO2 = 250.0;              // mL/min
  RQ = 0.8;                 // respiratory quotient

  CoreSetPointC = 37.0;     // the core the balanced start is built around

  // How metabolic heat production follows temperature: the factor it
  // changes by for a 10 K change, van't Hoff's Q10. Most enzymatic
  // processes sit between 2 and 3; whole-body human metabolism in
  // hypothermia is usually quoted near 2 to 2.5, which is 7 to 9% per
  // degree. 1.0 switches the whole effect off and holds generation at
  // the set-point rate whatever the temperature.
  //
  // The reference temperature is the core set point, so the factor is
  // exactly 1 in the balanced starting state by construction and the
  // calibration below is untouched by any of this.
  Q10 = 2.0;

  (******************** THE COMPARTMENTS ********************)

  NbLayers = 4;

  LayerCore = 0;
  LayerMuscle = 1;
  LayerFat = 2;
  LayerSkin = 3;

  (******************** THE SEGMENTS ********************)

  NbSegments = 6;

  SegHead = 0;
  SegTrunk = 1;
  SegArmL = 2;
  SegArmR = 3;
  SegLegL = 4;
  SegLegR = 5;

type

  // One compartment, over the whole body. Mass and density fix its
  // volume; GenShare is its fraction of the whole body's resting heat
  // output and FlowShare of the cardiac output; RadialDiv is how many
  // element layers it gets through its thickness in a cylinder, and is
  // ignored for whichever compartment is innermost there, which is
  // meshed unstructured.
  RLayerSpec = record

    Name : String[8];
    Mass : Double;        // kg, whole body
    Density : Double;     // kg/m3
    Cp : Double;          // J/kgK
    K : Double;           // W/mK
    GenShare : Double;    // of the total heat output
    FlowShare : Double;   // of the cardiac output
    RadialDiv : Integer;

  end;

  TSegmentShape = (ssSphere, ssCylinder);

  // One segment of the body. See THE SEGMENTS in the header for where
  // the fractions come from and how the compartment masses follow.
  RSegmentSpec = record

    Name : String[10];
    Shape : TSegmentShape;
    MassFrac : Double;        // of the body mass
    AreaFrac : Double;        // of the body surface area
    Aspect : Double;          // cylinders: section minor axis over major
    HasCore : Boolean;
    FixedMuscle : Double;     // kg; 0 derives it - see SetupGeometry
    CoreGen : Double;         // of the whole body's output, in this core
    CoreFlow : Double;        // of the cardiac output, to this core
    Side : Integer;           // -1 the patient's left (-x), +1 right, 0 midline
    ContactHalfAngleDeg : Double;
    MeshSize : Double;        // m, unstructured size in the innermost compartment
    NbCirc : Integer;         // cylinders: divisions per quadrant

  end;

const

  Layers : Array[0..NbLayers - 1] of RLayerSpec =
  (
    // Viscera plus skeleton: three quarters of the resting output in
    // under half the volume.
    (Name : 'core';   Mass : 32.20; Density : 1050; Cp : 3700; K : 0.52;
     GenShare : 0.74; FlowShare : 0.75; RadialDiv : 0),

    // Skeletal muscle at rest. GenShare is the BASAL share - this is
    // the one that would climb with exercise, and the reason the
    // compartment is separate.
    (Name : 'muscle'; Mass : 31.50; Density : 1050; Cp : 3600; K : 0.51;
     GenShare : 0.23; FlowShare : 0.18; RadialDiv : 6),

    // Non-metabolic, as specified.
    (Name : 'fat';    Mass :  3.50; Density :  900; Cp : 2300; K : 0.21;
     GenShare : 0.00; FlowShare : 0.02; RadialDiv : 3),

    // A millimetre or two of it, and thermally almost inert until
    // perfusion arrives.
    (Name : 'skin';   Mass :  2.80; Density : 1085; Cp : 3680; K : 0.37;
     GenShare : 0.03; FlowShare : 0.05; RadialDiv : 2)
  );

  Segments : Array[0..NbSegments - 1] of RSegmentSpec =
  (
    // The brain is this core: 20% of the resting output and 14% of the
    // cardiac output. Sized by volume, so its area is whatever a sphere
    // of that volume has. Rests on the back of the skull.
    (Name : 'head'; Shape : ssSphere; MassFrac : 0.070; AreaFrac : 0.070;
     Aspect : 1.0; HasCore : True; FixedMuscle : 0.40;
     CoreGen : 0.20; CoreFlow : 0.14; Side : 0;
     ContactHalfAngleDeg : 45.0; MeshSize : 0.025; NbCirc : 0),

    // Liver, heart, kidneys, gut and the rest. Takes whatever core the
    // head leaves, so its muscle is derived.
    (Name : 'trunk'; Shape : ssCylinder; MassFrac : 0.508; AreaFrac : 0.340;
     Aspect : 0.5; HasCore : True; FixedMuscle : 0;
     CoreGen : 0.54; CoreFlow : 0.61; Side : 0;
     ContactHalfAngleDeg : 60.0; MeshSize : 0.010; NbCirc : 12),

    (Name : 'left arm'; Shape : ssCylinder; MassFrac : 0.049; AreaFrac : 0.095;
     Aspect : 1.0; HasCore : False; FixedMuscle : 0;
     CoreGen : 0; CoreFlow : 0; Side : -1;
     ContactHalfAngleDeg : 60.0; MeshSize : 0.010; NbCirc : 8),

    (Name : 'right arm'; Shape : ssCylinder; MassFrac : 0.049; AreaFrac : 0.095;
     Aspect : 1.0; HasCore : False; FixedMuscle : 0;
     CoreGen : 0; CoreFlow : 0; Side : 1;
     ContactHalfAngleDeg : 60.0; MeshSize : 0.010; NbCirc : 8),

    (Name : 'left leg'; Shape : ssCylinder; MassFrac : 0.162; AreaFrac : 0.200;
     Aspect : 1.0; HasCore : False; FixedMuscle : 0;
     CoreGen : 0; CoreFlow : 0; Side : -1;
     ContactHalfAngleDeg : 60.0; MeshSize : 0.010; NbCirc : 8),

    (Name : 'right leg'; Shape : ssCylinder; MassFrac : 0.162; AreaFrac : 0.200;
     Aspect : 1.0; HasCore : False; FixedMuscle : 0;
     CoreGen : 0; CoreFlow : 0; Side : 1;
     ContactHalfAngleDeg : 60.0; MeshSize : 0.010; NbCirc : 8)
  );

  // Element layers through each shell of a sphere, outward from its
  // innermost compartment. The head's shells are a few millimetres
  // thick at most, so fewer than a cylinder's RadialDiv.
  SphereShellDiv : Array[LayerMuscle..LayerSkin] of Integer = (2, 2, 2);

  // Where the segments sit relative to each other. The segments are not
  // joined, so these gaps are only for the picture - nothing crosses
  // them.
  NeckGap = 0.05;           // m, top of the trunk to the head
  ArmGap = 0.02;            // m, side of the trunk to the arm
  LegGap = 0.01;            // m, between the legs
  HipGap = 0.02;            // m, bottom of the trunk to the legs

  (******************** PERFUSION ********************)

  // Blood, for the Pennes term.
  BloodDensity = 1050.0;    // kg/m3
  BloodCp = 3617.0;         // J/kgK

  // Cardiac output, L/min. 5 is a normal resting output; 10 is twice
  // that. There is no zero any more: with no blood at all nothing empties
  // the trunk's core, conduction alone cannot hold it at the set point at
  // any drape coefficient, and the balanced starting state does not exist.
  // 1 L/min - a fifth of resting, deep shock - is where the range starts.
  CardiacOutputMin = 1.0;
  CardiacOutputDefault = 5.0;
  CardiacOutputMax = 10.0;

  // Blood flow before induction, as a fraction of each compartment's
  // resting share. The awake patient's thermoregulatory vasoconstriction
  // is cutaneous - it closes down the skin's flow and its arteriovenous
  // shunts, and leaves the core, muscle and fat perfused - so the skin
  // starts shut and everything else open. Induction abolishes that tone,
  // and at t = 0 every compartment goes to its full share.
  PreInductionFlow : Array[0..NbLayers - 1] of Double = (1.0, 1.0, 1.0, 0.0);

  // What "no blood" means for the closed-form check. The blood pool is a
  // node joined to the tissue by conduction links, and with every link at
  // exactly zero it would be joined to nothing and the system singular;
  // this leaves it a millionth of its conductance, which carries a few
  // milliwatts - nothing, next to the 84 W the check is about.
  BloodOffFraction = 1E-6;

  (******************** ENVIRONMENT ********************)

  AmbientC = 16.0;          // theatre air and surrounding surfaces
  SkinEmissivity = 0.98;    // bare skin in the far infrared
  BareConvection = 3.0;     // W/m2K, natural convection over a supine body

  (******************** THE CUSHION ********************)

  // The foam mattress the patient lies on, carried as a series
  // conductance over the contact patch rather than as meshed foam - see
  // THE CUSHION in the header for what that assumes and what it costs.
  // How much of each segment rests on it is ContactHalfAngleDeg in the
  // segment table.
  PadThickness = 0.10;      // m
  PadConductivity = 0.040;  // W/mK, open-cell polyurethane foam
  PadUnderside = 5.0;       // W/m2K, foam to table top and the still air under it

  (******************** THE GOWN ********************)

  // A thin cotton garment over the front of the trunk and the arms - a
  // theatre gown - worn in CaseGowned only; the other two cases are
  // exactly as they were. It is carried as real elements rather than as
  // a surface coefficient: a layer of still air between the skin and
  // the cloth, then the cloth itself, each extruded outward from every
  // exposed skin face of the covered segments - see THE GOWN in the
  // header and BuildModel. Heat crosses the air by conduction only, and
  // the room sees the outer face of the cloth, by convection and
  // radiation, instead of the skin. The head and legs stay bare, and
  // the patch on the cushion is unchanged.
  GownSegments = [SegTrunk, SegArmL, SegArmR];

  AirGapThickness = 0.001;  // m, skin to cloth
  GownThickness = 0.001;    // m, the cloth

  // Still air at skin temperature.
  AirDensity = 1.16;        // kg/m3
  AirCp = 1007.0;           // J/kgK
  AirConductivity = 0.026;  // W/mK

  // A woven cotton fabric - mostly air held between fibres, which is why
  // the conductivity is a third of the fibre's own 0.16 W/mK and the
  // density a quarter of it.
  CottonDensity = 350.0;    // kg/m3
  CottonCp = 1300.0;        // J/kgK
  CottonConductivity = 0.06; // W/mK

  GownEmissivity = 0.90;    // cotton cloth in the far infrared

  (******************** MESH ********************)

  // Along each cylinder - nothing varies axially, since the ends are
  // adiabatic and everything is uniform along the length.
  NbAxial = 2;

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
  CaseGowned = 3;

type

  // A face of an element lying on the outer (skin) surface of one
  // segment. Supported means it is in contact with the cushion, so it
  // conducts through foam rather than losing heat to the room. Angle is
  // what decides that: on a cylinder, the section's parametric angle at
  // the face centre, measured from the major axis; on a sphere, the angle
  // between the face centre and straight down.
  //
  // Covered means the gown lies over it (CaseGowned, and only on the
  // exposed faces of GownSegments): the room then sees the cloth's outer
  // face, GownFaceIdx of element GownEle, whose nodes GownNode sit over
  // Node in the same order and whose area is GownArea - all set by
  // BuildModel, which is where the gown is extruded.
  RSkinFace = record

    Seg : Integer;
    Ele : Integer;
    FaceIdx : Integer;
    NbNodes : Integer;
    Node : Array[0..3] of Integer;
    Area : Double;
    Angle : Double;
    Supported : Boolean;

    Covered : Boolean;
    GownEle : Integer;
    GownFaceIdx : Integer;
    GownNode : Array[0..3] of Integer;
    GownArea : Double;

  end;

  // Which part of the surface, or of the body, a quantity refers to.
  // The cushion makes front and back genuinely different, so most of
  // what the model reports has to be asked for one or the other.
  TProfileSector = (psAll, psFront, psBack);

  TSegmentLayerArray = Array[0..NbSegments - 1, 0..NbLayers - 1] of Double;
  TSegmentArray = Array[0..NbSegments - 1] of Double;

  TThermalModel = class(TObject)

  private

    FCase : Integer;

    FGmsh : TGmsh;
    FEngine : TThermalEngine;

    FRho, FCp, FK : Array[0..NbLayers - 1] of TExpressionList;
    FHConv, FHPad, FTinf, FEmiss : TExpressionList;
    FGenSource : Array of TExpressionList;

    // The gown (CaseGowned). FHGown is the coefficient the room applies
    // to the cloth's outer face; FHUnderGown one applied to the skin
    // beneath it directly, zero except in the closed-form check, which
    // bypasses the gown - see SetSurfaceCoefficients.
    FAirRho, FAirCp, FAirK : TExpressionList;
    FCottonRho, FCottonCp, FCottonK : TExpressionList;
    FHGown, FHUnderGown, FGownEmiss : TExpressionList;

    // Per compartment, whole body
    FLayerVol : Array[0..NbLayers - 1] of Double;      // nominal
    FMeshLayerVol : Array[0..NbLayers - 1] of Double;  // as meshed
    FLayerPower : Array[0..NbLayers - 1] of Double;    // W

    // Per segment and compartment. A compartment a segment does not have
    // - the core of a limb - has zero mass, volume and power throughout.
    FSLMass : TSegmentLayerArray;        // kg
    FSLVol : TSegmentLayerArray;         // m3, nominal
    FSLMeshVol : TSegmentLayerArray;     // m3, as meshed
    FSLPower : TSegmentLayerArray;       // W
    FSLGen : TSegmentLayerArray;         // W/m3
    FSLOuter : TSegmentLayerArray;       // m, outer s
    FSLDrop : TSegmentLayerArray;        // K below the segment centre, at the outer boundary
    FSLFlow : TSegmentLayerArray;        // L/min
    FSLW : TSegmentLayerArray;           // 1/s perfusion rate
    FSLTau : TSegmentLayerArray;         // s, perfusion time constant

    // Per segment
    FSegInner : Array[0..NbSegments - 1] of Integer;       // innermost compartment present
    FSegVol : TSegmentArray;             // m3
    FSegPower : TSegmentArray;           // W
    FSegAreaNominal : TSegmentArray;     // m2, its share of the body surface
    FSegA, FSegB : TSegmentArray;        // m, outer semi-axes (the radius, twice, on a sphere)
    FSegLen : TSegmentArray;             // m, cylinders
    // A cylinder's axis runs through (Cx, Cy) from Z0 to Z0 + Len; a
    // sphere's centre is (Cx, Cy, Z0).
    FSegCx, FSegCy, FSegZ0 : TSegmentArray;
    FSegDrop : TSegmentArray;            // K, centre to skin by the closed form
    FSegMeshArea : TSegmentArray;        // m2
    FSegMeshAreaFront : TSegmentArray;
    FSegMeshAreaBack : TSegmentArray;
    FSegCentreNode : Array[0..NbSegments - 1] of Integer;

    FCardiacOutput : Double;   // L/min
    FTArt : Double;            // K, the well-mixed blood pool
    FPerfNet : Double;         // W, should be zero - see UpdateSources

    // The blood pool: one node, joined to every perfused tissue node by a
    // conduction link of the node's own Pennes conductance - see
    // BuildModel. FLinkFrac is how much of its conductance each
    // compartment's links currently carry, and FLinkK the material
    // expression that sets it.
    FPoolNode : Integer;                 // -1 with no blood flowing at all
    FNodePerfGL : Array of Array[0..NbLayers - 1] of Double;   // W/K at full flow
    FLinkRho, FLinkCp : TExpressionList;
    FLinkK : Array[0..NbLayers - 1] of TExpressionList;
    FLinkFrac : Array[0..NbLayers - 1] of Double;

    FMeshArea : Double;
    FMeshAreaFront : Double;             // exposed to the room
    FMeshAreaBack : Double;              // lying on the cushion
    FMeshAreaGown : Double;              // m2 of skin under the gown, of the front
    FSegMeshAreaGown : TSegmentArray;
    FGownArea : Double;                  // m2, the cloth's outer face as meshed
    FGownResistance : Double;            // m2K/W, still air and cloth in series
    FNbGownElements : Integer;
    FTotalMass : Double;

    FUPad : Double;                      // W/m2K through the cushion

    FHeatOutput : Double;                // W, whole body at the set point
    FMetFactor : Double;                 // Q10 scaling, 1 at the set point
    FHBalance : Double;                  // W/m2K, uniform surface, no cushion
    FHDraped : Double;                   // W/m2K, calibrated with the cushion
    FUniformWorstRound : Double;         // K, worst FE-analytic gap, head and limbs
    FUniformWorstTrunk : Double;         // K, the same on the trunk
    FUniformSpread : Double;             // K, worst spread around one trunk ellipse
    FNbCalibrations : Integer;           // static solves the calibration needed

    // Per element
    FEleVolume : TDoubleArray;
    FEleSeg : TIntegerArray;
    FEleLayer : TIntegerArray;

    // Per node
    FNodeCapacity : TDoubleArray;        // J/K lumped to the node
    FNodeQMet : TDoubleArray;            // W, metabolic generation
    FNodePerfG : TDoubleArray;           // W/K, perfusion conductance
    FNodeSeg : TIntegerArray;            // the segment it belongs to
    FNodeS : TDoubleArray;               // its s within that segment

    FSkin : Array of RSkinFace;
    FNbSkin : Integer;

    FCoreNode : Integer;

    // History
    FHistT, FHistCore, FHistSkin, FHistLoss, FHistStore : TDoubleArray;
    FHistSkinB, FHistLossB : TDoubleArray;   // the back, on the cushion
    FHistGown : TDoubleArray;                // C, the cloth's outer face (CaseGowned)
    FHistGen : TDoubleArray;                 // W, generation as it stood
    FHistTArt, FHistPerf : TDoubleArray;
    FNbHist : Integer;

    // The whole field, kept every SnapshotSeconds, for the gmsh
    // animation. 25 frames of some ten thousand nodes is a few megabytes,
    // so this is kept in full rather than rewritten to disk as the run
    // goes.
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
    procedure SetBloodFlow(const Frac : Array of Double);
    procedure UpdateSources;

    procedure SetupGeometry;

    function SegmentMass(Seg : Integer) : Double;
    function ShapeName(Seg : Integer) : String;
    function ElementNodeCount(Ele : Integer) : Integer;
    function NodeS(Seg, Node : Integer) : Double;

    procedure WriteGeoFile(const FileName : String);
    procedure BuildMesh;
    procedure CalcElementGeometry;
    procedure BuildModel;
    procedure BuildGown(MatAir, MatCotton : Integer);

    function Radiating : Boolean;

    function TotalEnergy : Double;
    procedure SurfaceLosses(UseRadiation : Boolean; out Front, Back : Double;
                            Seg : Integer = -1);
    function SurfaceLoss(UseRadiation : Boolean) : Double;
    function MeanSkinTemperature(Sector : TProfileSector; Seg : Integer = -1;
                                 Initial : Boolean = False) : Double;
    function MeanGownTemperature(Seg : Integer = -1;
                                 Initial : Boolean = False) : Double;

    procedure SetSurfaceCoefficients(HFront, UBack : Double;
                                     UniformOnSkin : Boolean = False);
    procedure VerifyAgainstAnalytic;
    procedure CalibrateDraped;

    procedure Expose;

    procedure ReportSetup;
    procedure ReportHistory;
    procedure ReportProfile;
    procedure ReportSegments;
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

    // The trunk's profile from its centre outward - see the comment on
    // the implementation for why the trunk.
    procedure GetRadialProfiles(Sector : TProfileSector;
                                out S, T0, TEnd : TVMobj);

    // For the plot window: the trunk's compartment boundaries, in mm,
    // innermost outward, and their names.
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

// The gmsh physical region of compartment Layer in segment Seg. The shells
// of a sphere are meshed in one extrusion and share a region of their own,
// ShellRegion, with the compartment told apart afterwards by radius - see
// CalcElementGeometry.
function RegionCode(Seg, Layer : Integer) : Integer;
begin

  Result := 10 * Seg + Layer + 1;

end;

function ShellRegion(Seg : Integer) : Integer;
begin

  Result := 10 * Seg + 10;

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

  // The gown's resistance per unit area, air and cloth in series - what
  // the calibration's update model and the report use; the elements
  // themselves carry the two layers separately.
  FGownResistance := AirGapThickness / AirConductivity +
                     GownThickness / CottonConductivity;

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

  FAirRho.Free;
  FAirCp.Free;
  FAirK.Free;
  FCottonRho.Free;
  FCottonCp.Free;
  FCottonK.Free;
  FHGown.Free;
  FHUnderGown.Free;
  FGownEmiss.Free;

  FLinkRho.Free;
  FLinkCp.Free;

  for i := 0 to NbLayers - 1 do
    FLinkK[i].Free;

  for i := 0 to Length(FGenSource) - 1 do
    FGenSource[i].Free;

  FGmsh.Free;

  inherited Destroy;

end;

function TThermalModel.InterfaceCount : Integer;
begin

  Result := NbLayers - 1 - FSegInner[SegTrunk];

end;

function TThermalModel.InterfaceMm(Index : Integer) : Double;
begin

  Result := FSLOuter[SegTrunk, FSegInner[SegTrunk] + Index] * 1000;

end;

function TThermalModel.InterfaceName(Index : Integer) : String;
var
  l : Integer;
begin

  l := FSegInner[SegTrunk] + Index;

  Result := Layers[l].Name + '/' + Layers[l + 1].Name;

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

function TThermalModel.SegmentMass(Seg : Integer) : Double;
var
  l : Integer;
begin

  Result := 0;

  for l := 0 to NbLayers - 1 do
    Result := Result + FSLMass[Seg, l];

end;

function TThermalModel.ShapeName(Seg : Integer) : String;
begin

  if Segments[Seg].Shape = ssSphere then
    Result := 'sphere'
  else if SameValue(Segments[Seg].Aspect, 1.0) then
    Result := 'cylinder'
  else
    Result := Format('ellipse %.2f', [Segments[Seg].Aspect], DotFS);

end;

function TThermalModel.ElementNodeCount(Ele : Integer) : Integer;
begin

  case FGmsh.ElementType[Ele] of
    GMSH_HEXA : Result := 8;
    GMSH_PRISM : Result := 6;
    GMSH_TETRA : Result := 4;
  else
    raise Exception.Create('Unexpected element type ' +
      IntToStr(FGmsh.ElementType[Ele]) + ' - this model meshes only ' +
      'hexahedra and prisms (the layers) and tetrahedra (the head''s core).');
  end;

end;

// A node's radial coordinate within its segment: the distance from the
// centre on a sphere, and on a cylinder the semi-major axis of the similar
// ellipse through it - the plain radius again on a round limb.
function TThermalModel.NodeS(Seg, Node : Integer) : Double;
begin

  if Segments[Seg].Shape = ssSphere then
    Result := Sqrt(Sqr(FGmsh.CoordX[Node] - FSegCx[Seg]) +
                   Sqr(FGmsh.CoordY[Node] - FSegCy[Seg]) +
                   Sqr(FGmsh.CoordZ[Node] - FSegZ0[Seg]))
  else
    Result := Sqrt(Sqr(FGmsh.CoordX[Node] - FSegCx[Seg]) +
                   Sqr((FGmsh.CoordY[Node] - FSegCy[Seg]) / Segments[Seg].Aspect));

end;

(*******************************************************************
  The segments, the compartments inside each, where they sit, and the
  temperature profile each implies.

  Masses first. Skin and fat are shared out by surface area; a segment
  without a core is muscle for the rest of its mass; a segment with a core
  and a FixedMuscle has that much muscle and the rest is core; and the one
  segment with a core and no FixedMuscle - the trunk - takes whatever core
  is left, its muscle then being the remainder of its own mass. That
  keeps every compartment's whole-body total exactly what the layer table
  says, whatever the segment fractions are, and it is checked below that
  nothing comes out negative.

  Shapes next, from each segment's volume and share of the surface - see
  THE SEGMENTS in the header for the cylinder formulas. Boundaries follow
  from cumulative volume, the shapes being similar:

    sphere     s_i = (3*V_cumulative_i/(4*pi))^(1/3)
    cylinder   s_i = sqrt(V_cumulative_i/(pi*k*L))

  Nothing is positioned by hand, so changing a mass, a density or a
  fraction moves the boundaries consistently.

  The closed-form profile is worked out here too, per segment, and used
  two ways: as a first guess at the surface coefficient that balances the
  trunk at the set point, and to check the finite-element answer in the
  uniform-surface reference solve that is the only configuration it
  describes. The formulas are set out under VERIFICATION in the header;
  the cylinder ones are written with the shape constants

    pi*k            section area inside s is pi*k*s^2
    pi*(1+k^2)/k    the chain's effective perimeter constant

  both of which are the circle's pi and 2*pi at k = 1.
********************************************************************)
procedure TThermalModel.SetupGeometry;
var

  s, l, Inner, Balance : Integer;

  CalEquiv, Vcum, Drop, Qin, s0, s1, q, k, p1, Kc, FA, FP, Len, P,
  Sum, Rest, CoreLeft, BalanceRest, Margin : Double;

begin

  // Caloric equivalent of oxygen, linear in RQ between the fat and
  // carbohydrate end points (4.686 kcal/L at RQ 0.707, 5.047 at 1.0).
  // At RQ 0.8 this gives 4.80 kcal/L, the standard table value.
  CalEquiv := 4.686 + (RQ - 0.707) * 1.232;

  FHeatOutput := (VO2 / 1000) * CalEquiv * 4184 / 60;

  (******************** THE TABLES ********************)

  // Guard the tables against each other, since a fraction that does not
  // add up would otherwise only show as a body of the wrong size.
  FTotalMass := 0;

  for l := 0 to NbLayers - 1 do
    FTotalMass := FTotalMass + Layers[l].Mass;

  if Abs(FTotalMass - BodyMass) > 1E-6 then
    raise Exception.Create(Format('The compartment masses come to %.2f kg, ' +
      'not the %.2f kg body mass.', [FTotalMass, BodyMass]));

  Sum := 0;

  for s := 0 to NbSegments - 1 do
    Sum := Sum + Segments[s].MassFrac;

  if Abs(Sum - 1) > 1E-6 then
    raise Exception.Create(Format('The segment mass fractions add up to %.4f, ' +
      'not 1.', [Sum]));

  Sum := 0;

  for s := 0 to NbSegments - 1 do
    Sum := Sum + Segments[s].AreaFrac;

  if Abs(Sum - 1) > 1E-6 then
    raise Exception.Create(Format('The segment area fractions add up to %.4f, ' +
      'not 1.', [Sum]));

  Sum := 0;

  for s := 0 to NbSegments - 1 do
    Sum := Sum + Segments[s].CoreGen;

  if Abs(Sum - Layers[LayerCore].GenShare) > 1E-6 then
    raise Exception.Create(Format('The segments'' core generation shares add up ' +
      'to %.4f, not the core compartment''s %.4f.', [Sum, Layers[LayerCore].GenShare]));

  Sum := 0;

  for s := 0 to NbSegments - 1 do
    Sum := Sum + Segments[s].CoreFlow;

  if Abs(Sum - Layers[LayerCore].FlowShare) > 1E-6 then
    raise Exception.Create(Format('The segments'' core flow shares add up ' +
      'to %.4f, not the core compartment''s %.4f.', [Sum, Layers[LayerCore].FlowShare]));

  (******************** MASSES ********************)

  Balance := -1;
  BalanceRest := 0;
  CoreLeft := Layers[LayerCore].Mass;

  for s := 0 to NbSegments - 1 do
  begin

    FSLMass[s, LayerSkin] := Layers[LayerSkin].Mass * Segments[s].AreaFrac;
    FSLMass[s, LayerFat] := Layers[LayerFat].Mass * Segments[s].AreaFrac;

    Rest := BodyMass * Segments[s].MassFrac -
            FSLMass[s, LayerSkin] - FSLMass[s, LayerFat];

    if not Segments[s].HasCore then
    begin
      FSLMass[s, LayerCore] := 0;
      FSLMass[s, LayerMuscle] := Rest;
    end
    else if Segments[s].FixedMuscle > 0 then
    begin
      FSLMass[s, LayerMuscle] := Segments[s].FixedMuscle;
      FSLMass[s, LayerCore] := Rest - Segments[s].FixedMuscle;
      CoreLeft := CoreLeft - FSLMass[s, LayerCore];
    end
    else
    begin

      if Balance >= 0 then
        raise Exception.Create('Only one segment can take the balance of the ' +
          'core - ' + Segments[Balance].Name + ' and ' + Segments[s].Name +
          ' both have a core and no fixed muscle mass.');

      Balance := s;
      BalanceRest := Rest;

    end;

  end;

  if Balance < 0 then
    raise Exception.Create('No segment takes the balance of the core - one ' +
      'segment with a core must leave FixedMuscle at zero.');

  FSLMass[Balance, LayerCore] := CoreLeft;
  FSLMass[Balance, LayerMuscle] := BalanceRest - CoreLeft;

  for s := 0 to NbSegments - 1 do
    for l := 0 to NbLayers - 1 do
    begin

      if (l = LayerCore) and not Segments[s].HasCore then
        Continue;

      if FSLMass[s, l] <= 0 then
        raise Exception.Create(Format('The %s comes out with %.3f kg of %s - ' +
          'check the segment and compartment tables.',
          [Segments[s].Name, FSLMass[s, l], Layers[l].Name]));

    end;

  (******************** VOLUMES ********************)

  for l := 0 to NbLayers - 1 do
  begin
    FLayerVol[l] := Layers[l].Mass / Layers[l].Density;
    FLayerPower[l] := 0;
  end;

  for s := 0 to NbSegments - 1 do
  begin

    FSegVol[s] := 0;
    FSegPower[s] := 0;
    FSegAreaNominal[s] := Segments[s].AreaFrac * BodySurfaceArea;

    if Segments[s].HasCore then
      FSegInner[s] := LayerCore
    else
      FSegInner[s] := LayerMuscle;

    for l := 0 to NbLayers - 1 do
    begin
      FSLVol[s, l] := FSLMass[s, l] / Layers[l].Density;
      FSegVol[s] := FSegVol[s] + FSLVol[s, l];
    end;

  end;

  (******************** SHAPES ********************)

  for s := 0 to NbSegments - 1 do
  begin

    Inner := FSegInner[s];
    Vcum := 0;

    for l := 0 to NbLayers - 1 do
      FSLOuter[s, l] := 0;

    if Segments[s].Shape = ssSphere then
    begin

      FSegA[s] := Power(3 * FSegVol[s] / (4 * Pi), 1 / 3);
      FSegB[s] := FSegA[s];
      FSegLen[s] := 0;

      for l := Inner to NbLayers - 1 do
      begin
        Vcum := Vcum + FSLVol[s, l];
        FSLOuter[s, l] := Power(3 * Vcum / (4 * Pi), 1 / 3);
      end;

    end
    else
    begin

      k := Segments[s].Aspect;

      // Ramanujan's second approximation to the perimeter of an ellipse
      // of semi-axes 1 and k. It is good to a few parts in 1e5 at k = 0.5
      // and exact at k = 1, where it returns 2*pi.
      p1 := Pi * (3 * (1 + k) - Sqrt((3 + k) * (1 + 3 * k)));

      // Match the segment's volume AND its surface area, with the ends
      // adiabatic so the whole area is lateral.
      FSegA[s] := p1 * FSegVol[s] / (Pi * k * FSegAreaNominal[s]);
      FSegB[s] := k * FSegA[s];
      FSegLen[s] := FSegVol[s] / (Pi * FSegA[s] * FSegB[s]);

      for l := Inner to NbLayers - 1 do
      begin
        Vcum := Vcum + FSLVol[s, l];
        FSLOuter[s, l] := Sqrt(Vcum / (Pi * k * FSegLen[s]));
      end;

    end;

    // A mass or density that puts a boundary outside the one beyond it
    // would mesh into nonsense rather than fail, so it is caught here.
    for l := Inner + 1 to NbLayers - 1 do
      if FSLOuter[s, l] <= FSLOuter[s, l - 1] then
        raise Exception.Create('The ' + Layers[l].Name + ' of the ' +
          Segments[s].Name + ' has no thickness - check the masses and ' +
          'densities in the tables.');

  end;

  (******************** PLACEMENT ********************)

  // Supine on the cushion, whose surface is the plane y = 0: every
  // segment's lowest point touches it, so each centre sits its own minor
  // semi-axis up. The body runs along z, head towards +z, and the
  // patient's left is -x.
  for s := 0 to NbSegments - 1 do
  begin

    FSegCy[s] := FSegB[s];

    case s of

      SegHead :
      begin
        FSegCx[s] := 0;
        FSegZ0[s] := FSegLen[SegTrunk] + NeckGap + FSegA[s];
      end;

      SegArmL, SegArmR :
      begin
        // Shoulder level with the top of the trunk, hanging towards the feet.
        FSegCx[s] := Segments[s].Side * (FSegA[SegTrunk] + ArmGap + FSegA[s]);
        FSegZ0[s] := FSegLen[SegTrunk] - FSegLen[s];
      end;

      SegLegL, SegLegR :
      begin
        FSegCx[s] := Segments[s].Side * (FSegA[s] + LegGap / 2);
        FSegZ0[s] := -HipGap - FSegLen[s];
      end;

    else
      begin
        FSegCx[s] := 0;
        FSegZ0[s] := 0;
      end;

    end;

  end;

  (******************** GENERATION ********************)

  // A core carries its segment's own share of the output; every other
  // compartment's share is spread over the segments by volume.
  for s := 0 to NbSegments - 1 do
    for l := 0 to NbLayers - 1 do
    begin

      if FSLMass[s, l] <= 0 then
        P := 0
      else if l = LayerCore then
        P := FHeatOutput * Segments[s].CoreGen
      else
        P := FHeatOutput * Layers[l].GenShare * FSLVol[s, l] / FLayerVol[l];

      FSLPower[s, l] := P;

      if FSLVol[s, l] > 0 then
        FSLGen[s, l] := P / FSLVol[s, l]
      else
        FSLGen[s, l] := 0;

      FSegPower[s] := FSegPower[s] + P;
      FLayerPower[l] := FLayerPower[l] + P;

    end;

  (******************** THE ANALYTIC PROFILE ********************)

  // Centre outward in each segment, accumulating the drop and the power
  // passing each boundary. FSLDrop[s, l] is the temperature at the OUTER
  // boundary of compartment l, relative to the segment's centre.
  for s := 0 to NbSegments - 1 do
  begin

    Inner := FSegInner[s];

    k := Segments[s].Aspect;
    Len := FSegLen[s];

    FA := Pi * k;
    FP := Pi * (1 + k * k) / k;

    Drop := 0;
    Qin := 0;

    for l := 0 to NbLayers - 1 do
      FSLDrop[s, l] := 0;

    for l := Inner to NbLayers - 1 do
    begin

      q := FSLGen[s, l];
      Kc := Layers[l].K;
      s1 := FSLOuter[s, l];

      if Segments[s].Shape = ssSphere then
      begin

        if l = Inner then
        begin
          // Solid sphere generating uniformly.
          Drop := Drop + q * s1 * s1 / (6 * Kc);
          Qin := q * 4 / 3 * Pi * s1 * s1 * s1;
        end
        else
        begin

          s0 := FSLOuter[s, l - 1];

          Drop := Drop +
            (Qin - q * 4 / 3 * Pi * s0 * s0 * s0) / (4 * Pi * Kc) * (1 / s0 - 1 / s1) +
            q * (s1 * s1 - s0 * s0) / (6 * Kc);

          Qin := Qin + q * 4 / 3 * Pi * (s1 * s1 * s1 - s0 * s0 * s0);

        end;

      end
      else
      begin

        if l = Inner then
        begin
          // Solid ellipse generating uniformly - exact at any axis ratio.
          Drop := Drop + q * FA * s1 * s1 / (2 * Kc * FP);
          Qin := q * FA * s1 * s1 * Len;
        end
        else
        begin

          s0 := FSLOuter[s, l - 1];

          Drop := Drop +
            (Qin - q * FA * s0 * s0 * Len) / (Kc * FP * Len) * Ln(s1 / s0) +
            q * FA * (s1 * s1 - s0 * s0) / (2 * Kc * FP);

          Qin := Qin + q * FA * (s1 * s1 - s0 * s0) * Len;

        end;

      end;

      FSLDrop[s, l] := Drop;

    end;

    FSegDrop[s] := Drop;

  end;

  // The cushion, as a series conductance: 100 mm of foam, then whatever
  // film the table and the still air beneath it offer.
  FUPad := 1 / (PadThickness / PadConductivity + 1 / PadUnderside);

  // What UNIFORM surface coefficient - no cushion - balances the trunk
  // at the set point on its own generation? This is the reference
  // configuration the closed forms are checked in, and the first guess
  // the calibration with the cushion starts from.
  Margin := CoreSetPointC - FSegDrop[SegTrunk] - AmbientC;

  if Margin <= 0 then
    raise Exception.Create('The trunk''s own centre-to-skin drop is more than ' +
      'the whole set-point-to-room difference - no surface could balance it.');

  FHBalance := FSegPower[SegTrunk] / (FSegAreaNominal[SegTrunk] * Margin);

  FHDraped := FHBalance;

end;

(*******************************************************************
  Geometry, one segment at a time, all in one gmsh file.

  A CYLINDER - the trunk and the limbs - is a disc of its innermost
  compartment inside similar elliptical (or, at k = 1, circular) annuli,
  one per outer compartment, extruded along its axis. The disc is meshed
  unstructured (triangles, hence prisms once extruded): it is one
  material with a smooth field and nothing about it needs structure.
  Every layer outside it is meshed structured instead, as four
  transfinite quadrants recombined into quads, hence hexahedra - the fat
  and skin are a few millimetres thick, and an unstructured mesher would
  either miss them or flood the whole model with elements that size.

    point   B+1               centre, embedded so the axis carries nodes
    point   B+10+4*L+q        boundary L at quadrant angle q
    line    B+100+4*L+q       quarter arc of boundary L, quadrant q
    line    B+200+4*L+q       radial line from boundary L to L+1 at angle q
    surface B+300             the disc
    surface B+400+4*L+q       annulus of compartment L, quadrant q

  with B = 10000 per segment, so no two segments' numbers meet. The
  quadrant corner points sit at parametric angle 0, 90, 180 and 270
  degrees, so the four arcs of a boundary are quarter ellipses - each
  under Pi, which is what the built-in kernel requires of an arc.

  A SPHERE - the head - cannot be extruded along an axis. Its core is a
  solid sphere of eight octant patches, meshed in tetrahedra, and its
  shells are grown out of that surface by extruding it along its own
  normals - gmsh's boundary-layer extrusion, one layer of prisms per
  division, with the heights set so element layers land exactly on the
  compartment boundaries. That extrusion is one gmsh volume per patch,
  not one per compartment, so all three shells share one physical region
  and CalcElementGeometry sorts their elements by radius.

  Order matters in the file. Every volume the head's extrusion creates is
  captured as the difference between the volume list before and after it,
  which only works if nothing else has been extruded yet - so spheres go
  first. Extrusions also number their new entities from the highest id in
  use, so the cylinders' extrusions all come after every cylinder's
  explicitly numbered entities, where they cannot collide with them.

  Element sizes differ between segments, so each gets a Constant size
  field over its innermost compartment, combined through a Min field.
  gmsh's habit of growing the interior size from the boundary is turned
  off, or the transfinite arcs would dictate the discs' mesh instead.
********************************************************************)
procedure TThermalModel.WriteGeoFile(const FileName : String);

  function PIdx(B, L, q : Integer) : Integer;
  begin
    Result := B + 10 + 4 * L + (q mod 4);
  end;

  function ArcId(B, L, q : Integer) : Integer;
  begin
    Result := B + 100 + 4 * L + q;
  end;

  function RadId(B, L, q : Integer) : Integer;
  begin
    Result := B + 200 + 4 * L + (q mod 4);
  end;

  function SegBase(s : Integer) : Integer;
  begin
    Result := 10000 * s;
  end;

  function Signed(B, v : Integer) : String;
  begin
    if v < 0 then
      Result := '-' + IntToStr(B - v)
    else
      Result := IntToStr(B + v);
  end;

const

  // The six poles of a sphere, as unit offsets from its centre: points
  // B+2 to B+7.
  Pole : Array[0..5, 0..2] of Integer =
    ((1,0,0), (0,1,0), (-1,0,0), (0,-1,0), (0,0,1), (0,0,-1));

  // Its twelve quarter circles, B+1 to B+12, as start and end point.
  SphArc : Array[0..11, 0..1] of Integer =
    ((2,3), (3,4), (4,5), (5,2), (2,6), (6,4),
     (4,7), (7,2), (3,6), (6,5), (5,7), (7,3));

  // Its eight octant patches, as signed quarter circles, oriented so the
  // normals point outward - which is the way the shells grow.
  SphPatch : Array[0..7, 0..2] of Integer =
    ((1,9,-5), (2,-6,-9), (3,-10,6), (4,5,10),
     (-1,-8,12), (-2,-12,-7), (-3,7,-11), (-4,11,8));

var

  F : TextFile;

  s, L, q, n, B, i, Inner : Integer;

  a, k, R, MaxSize : Double;

  Arcs, Rads, Vols, Counts, Heights, Srf, Fields : String;

begin

  AssignFile(F, FileName);

  SafeReWriteText(F);

  try

    MaxSize := 0;

    for s := 0 to NbSegments - 1 do
      MaxSize := Max(MaxSize, Segments[s].MeshSize);

    WriteLn(F, 'Mesh.MshFileVersion=1;');
    WriteLn(F, 'Mesh.MeshSizeExtendFromBoundary = 0;');
    WriteLn(F, 'Mesh.MeshSizeMax = ' + Num(MaxSize) + ';');

    (******************** SPHERES ********************)

    for s := 0 to NbSegments - 1 do
    begin

      if Segments[s].Shape <> ssSphere then
        Continue;

      B := SegBase(s);
      Inner := FSegInner[s];
      R := FSLOuter[s, Inner];

      WriteLn(F, Format('cl%d = %s;', [s, Num(Segments[s].MeshSize)]));

      WriteLn(F, Format('Point(%d) = {%s,%s,%s,cl%d};',
        [B + 1, Num(FSegCx[s]), Num(FSegCy[s]), Num(FSegZ0[s]), s]));

      for i := 0 to 5 do
        WriteLn(F, Format('Point(%d) = {%s,%s,%s,cl%d};',
          [B + 2 + i, Num(FSegCx[s] + R * Pole[i, 0]),
           Num(FSegCy[s] + R * Pole[i, 1]), Num(FSegZ0[s] + R * Pole[i, 2]), s]));

      for i := 0 to 11 do
        WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
          [B + 1 + i, B + SphArc[i, 0], B + 1, B + SphArc[i, 1]]));

      Srf := '';

      for i := 0 to 7 do
      begin

        WriteLn(F, Format('Curve Loop(%d) = {%s,%s,%s};',
          [B + 21 + i, Signed(B, SphPatch[i, 0]), Signed(B, SphPatch[i, 1]),
           Signed(B, SphPatch[i, 2])]));

        WriteLn(F, Format('Surface(%d) = {%d} In Sphere {%d};', [B + 31 + i, B + 21 + i, B + 1]));

        if i > 0 then
          Srf := Srf + ',';

        Srf := Srf + IntToStr(B + 31 + i);

      end;

      WriteLn(F, Format('Surface Loop(%d) = {%s};', [B + 40, Srf]));
      WriteLn(F, Format('Volume(%d) = {%d};', [B + 41, B + 40]));

      // A node at the very centre, for the closed-form check to read.
      WriteLn(F, Format('Point{%d} In Volume{%d};', [B + 1, B + 41]));

      WriteLn(F, Format('Physical Volume(%d) = {%d};',
        [RegionCode(s, Inner), B + 41]));

      // The shells: one extrusion along the normals, with a group of
      // element layers per compartment ending on its outer boundary.
      // Heights are measured from the core's surface.
      Counts := '';
      Heights := '';

      for L := Inner + 1 to NbLayers - 1 do
      begin

        if L > Inner + 1 then
        begin
          Counts := Counts + ',';
          Heights := Heights + ',';
        end;

        Counts := Counts + IntToStr(SphereShellDiv[L]);
        Heights := Heights + Num(FSLOuter[s, L] - R);

      end;

      WriteLn(F, Format('sb%d[] = Volume{:};', [s]));

      WriteLn(F, Format('sh%d[] = Extrude { Surface{%s}; Layers{{%s},{%s}}; Recombine; };',
        [s, Srf, Counts, Heights]));

      WriteLn(F, Format('sa%d[] = Volume{:};', [s]));
      WriteLn(F, Format('sa%d[] -= {sb%d[]};', [s, s]));

      WriteLn(F, Format('Physical Volume(%d) = {sa%d[]};', [ShellRegion(s), s]));

    end;

    (******************** CYLINDERS ********************)

    for s := 0 to NbSegments - 1 do
    begin

      if Segments[s].Shape <> ssCylinder then
        Continue;

      B := SegBase(s);
      Inner := FSegInner[s];
      k := Segments[s].Aspect;

      WriteLn(F, Format('cl%d = %s;', [s, Num(Segments[s].MeshSize)]));

      WriteLn(F, Format('Point(%d) = {%s,%s,%s,cl%d};',
        [B + 1, Num(FSegCx[s]), Num(FSegCy[s]), Num(FSegZ0[s]), s]));

      for L := Inner to NbLayers - 1 do
        for q := 0 to 3 do
        begin

          a := q * Pi / 2;

          // x = s*cos t, y = k*s*sin t - the similar ellipse of
          // semi-major axis s at parametric angle t.
          WriteLn(F, Format('Point(%d) = {%s,%s,%s,cl%d};',
            [PIdx(B, L, q), Num(FSegCx[s] + FSLOuter[s, L] * Cos(a)),
             Num(FSegCy[s] + k * FSLOuter[s, L] * Sin(a)), Num(FSegZ0[s]), s]));

        end;

      // Arcs at every boundary, and the radial lines joining
      // consecutive ones.
      for L := Inner to NbLayers - 1 do
      begin

        Arcs := '';

        for q := 0 to 3 do
        begin

          // A circle wherever the section is round: gmsh's Ellipse
          // needs a major axis to point along, and a circle has none.
          if SameValue(k, 1.0) then
            WriteLn(F, Format('Circle(%d) = {%d,%d,%d};',
              [ArcId(B, L, q), PIdx(B, L, q), B + 1, PIdx(B, L, q + 1)]))
          else
            // Start, centre, a point on the major axis, end.
            WriteLn(F, Format('Ellipse(%d) = {%d,%d,%d,%d};',
              [ArcId(B, L, q), PIdx(B, L, q), B + 1, PIdx(B, L, 0),
               PIdx(B, L, q + 1)]));

          if q > 0 then
            Arcs := Arcs + ',';

          Arcs := Arcs + IntToStr(ArcId(B, L, q));

        end;

        WriteLn(F, Format('Transfinite Line {%s} = %d;',
          [Arcs, Segments[s].NbCirc + 1]));

      end;

      for L := Inner to NbLayers - 2 do
      begin

        Rads := '';

        for q := 0 to 3 do
        begin

          WriteLn(F, Format('Line(%d) = {%d,%d};',
            [RadId(B, L, q), PIdx(B, L, q), PIdx(B, L + 1, q)]));

          if q > 0 then
            Rads := Rads + ',';

          Rads := Rads + IntToStr(RadId(B, L, q));

        end;

        // The layer OUTSIDE this pair of radii owns the divisions.
        WriteLn(F, Format('Transfinite Line {%s} = %d;',
          [Rads, Layers[L + 1].RadialDiv + 1]));

      end;

      // The disc.
      Arcs := '';

      for q := 0 to 3 do
      begin
        if q > 0 then
          Arcs := Arcs + ',';
        Arcs := Arcs + IntToStr(ArcId(B, Inner, q));
      end;

      WriteLn(F, Format('Line Loop(%d) = {%s};', [B + 299, Arcs]));
      WriteLn(F, Format('Plane Surface(%d) = {%d};', [B + 300, B + 299]));

      // A node on the axis at each station, for the closed-form check.
      WriteLn(F, Format('Point{%d} In Surface{%d};', [B + 1, B + 300]));

      // The annuli, quadrant by quadrant.
      for L := Inner + 1 to NbLayers - 1 do
        for q := 0 to 3 do
        begin

          n := (q + 1) mod 4;

          WriteLn(F, Format('Line Loop(%d) = {%d,%d,-%d,-%d};',
            [B + 500 + 4 * L + q, RadId(B, L - 1, q), ArcId(B, L, q),
             RadId(B, L - 1, n), ArcId(B, L - 1, q)]));

          WriteLn(F, Format('Plane Surface(%d) = {%d};',
            [B + 400 + 4 * L + q, B + 500 + 4 * L + q]));

          WriteLn(F, Format('Transfinite Surface {%d} = {%d,%d,%d,%d};',
            [B + 400 + 4 * L + q, PIdx(B, L - 1, q), PIdx(B, L, q),
             PIdx(B, L, n), PIdx(B, L - 1, n)]));

          WriteLn(F, Format('Recombine Surface {%d};', [B + 400 + 4 * L + q]));

        end;

    end;

    (******************** ELEMENT SIZES ********************)

    Fields := '';

    for s := 0 to NbSegments - 1 do
    begin

      B := SegBase(s);

      WriteLn(F, Format('Field[%d] = Constant;', [s + 1]));
      WriteLn(F, Format('Field[%d].VIn = %s;', [s + 1, Num(Segments[s].MeshSize)]));
      WriteLn(F, Format('Field[%d].IncludeBoundary = 1;', [s + 1]));

      if Segments[s].Shape = ssSphere then
      begin

        Srf := '';

        for i := 0 to 7 do
        begin
          if i > 0 then
            Srf := Srf + ',';
          Srf := Srf + IntToStr(B + 31 + i);
        end;

        WriteLn(F, Format('Field[%d].SurfacesList = {%s};', [s + 1, Srf]));
        WriteLn(F, Format('Field[%d].VolumesList = {%d};', [s + 1, B + 41]));

      end
      else
        WriteLn(F, Format('Field[%d].SurfacesList = {%d};', [s + 1, B + 300]));

      if s > 0 then
        Fields := Fields + ',';

      Fields := Fields + IntToStr(s + 1);

    end;

    WriteLn(F, Format('Field[%d] = Min;', [NbSegments + 1]));
    WriteLn(F, Format('Field[%d].FieldsList = {%s};', [NbSegments + 1, Fields]));
    WriteLn(F, Format('Background Field = %d;', [NbSegments + 1]));

    (******************** CYLINDER EXTRUSIONS ********************)

    // Extruded one surface at a time so each volume id can be captured
    // for its physical group; they still mesh conformally, because the
    // curves they share are meshed once.
    for s := 0 to NbSegments - 1 do
    begin

      if Segments[s].Shape <> ssCylinder then
        Continue;

      B := SegBase(s);
      Inner := FSegInner[s];

      WriteLn(F, Format('c%d[] = Extrude {0,0,%s} { Surface{%d}; Layers{%d}; Recombine; };',
        [s, Num(FSegLen[s]), B + 300, NbAxial]));

      WriteLn(F, Format('Physical Volume(%d) = {c%d[1]};', [RegionCode(s, Inner), s]));

      for L := Inner + 1 to NbLayers - 1 do
      begin

        Vols := '';

        for q := 0 to 3 do
        begin

          WriteLn(F, Format('v%d_%d_%d[] = Extrude {0,0,%s} { Surface{%d}; Layers{%d}; Recombine; };',
            [s, L, q, Num(FSegLen[s]), B + 400 + 4 * L + q, NbAxial]));

          if q > 0 then
            Vols := Vols + ',';

          Vols := Vols + Format('v%d_%d_%d[1]', [s, L, q]);

        end;

        WriteLn(F, Format('Physical Volume(%d) = {%s};', [RegionCode(s, L), Vols]));

      end;

    end;

  finally

    CloseFile(F);

  end;

end;

procedure TThermalModel.BuildMesh;
var

  ExitCode : Cardinal;

begin

  Say('Meshing the body with gmsh...');

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

{ Element volumes and compartments, the heat capacity lumped to each node,
  each node's segment and radial coordinate, and the list of faces lying
  on the skin.

  Volumes are taken by splitting each element into tetrahedra - three for
  a prism, six round the long diagonal for a hexahedron - which is exact
  for any element with planar faces. The cylinders' elements are straight
  extrusions and have them; the head's shell prisms are grown along
  slightly different normals at each corner, so their side faces are
  very nearly but not exactly planar, and the split is then a close
  approximation. Either way the report works from the MESHED volumes
  throughout, so nothing of that leaks into the energy balance. }
procedure TThermalModel.CalcElementGeometry;

  function TetVolume(n0, n1, n2, n3 : Integer) : Double;
  var
    ax, ay, az, bx, by, bz, cx, cy, cz : Double;
  begin

    ax := FGmsh.CoordX[n1] - FGmsh.CoordX[n0];
    ay := FGmsh.CoordY[n1] - FGmsh.CoordY[n0];
    az := FGmsh.CoordZ[n1] - FGmsh.CoordZ[n0];

    bx := FGmsh.CoordX[n2] - FGmsh.CoordX[n0];
    by := FGmsh.CoordY[n2] - FGmsh.CoordY[n0];
    bz := FGmsh.CoordZ[n2] - FGmsh.CoordZ[n0];

    cx := FGmsh.CoordX[n3] - FGmsh.CoordX[n0];
    cy := FGmsh.CoordY[n3] - FGmsh.CoordY[n0];
    cz := FGmsh.CoordZ[n3] - FGmsh.CoordZ[n0];

    Result := Abs(ax * (by * cz - bz * cy) - ay * (bx * cz - bz * cx) +
                  az * (bx * cy - by * cx)) / 6;

  end;

var

  i, j, f, n, nb, g, s, l, NbFaces : Integer;

  dx, dy, dz, rr, d, Best, HalfAngle, Threshold : Double;

  mx, my, mz, ax, ay, az, bx, by, bz, cx, cy, cz, px, py, pz : Double;

  OnSkin : Boolean;

  Nd : Array[0..7] of Integer;

  FN : Array[0..3] of Integer;

begin

  SetLength(FEleVolume, FGmsh.NbElements);
  SetLength(FEleSeg, FGmsh.NbElements);
  SetLength(FEleLayer, FGmsh.NbElements);
  SetLength(FNodeCapacity, FGmsh.NbNodes);
  SetLength(FNodeS, FGmsh.NbNodes);
  SetLength(FNodeSeg, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin
    FNodeCapacity[i] := 0;
    FNodeS[i] := 0;
    FNodeSeg[i] := -1;
  end;

  for l := 0 to NbLayers - 1 do
    FMeshLayerVol[l] := 0;

  for s := 0 to NbSegments - 1 do
  begin

    for l := 0 to NbLayers - 1 do
      FSLMeshVol[s, l] := 0;

    FSegMeshArea[s] := 0;
    FSegMeshAreaFront[s] := 0;
    FSegMeshAreaBack[s] := 0;
    FSegMeshAreaGown[s] := 0;

  end;

  FMeshArea := 0;
  FMeshAreaFront := 0;
  FMeshAreaBack := 0;
  FMeshAreaGown := 0;

  (******************** VOLUMES AND COMPARTMENTS ********************)

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    nb := ElementNodeCount(i);

    for j := 0 to nb - 1 do
      Nd[j] := FGmsh.ElementNode[i, j];

    case nb of
      4 : FEleVolume[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[3]);
      6 : FEleVolume[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[3]) +
                           TetVolume(Nd[1], Nd[2], Nd[3], Nd[4]) +
                           TetVolume(Nd[2], Nd[3], Nd[4], Nd[5]);
    else
      FEleVolume[i] := TetVolume(Nd[0], Nd[1], Nd[2], Nd[6]) +
                       TetVolume(Nd[0], Nd[2], Nd[3], Nd[6]) +
                       TetVolume(Nd[0], Nd[3], Nd[7], Nd[6]) +
                       TetVolume(Nd[0], Nd[7], Nd[4], Nd[6]) +
                       TetVolume(Nd[0], Nd[4], Nd[5], Nd[6]) +
                       TetVolume(Nd[0], Nd[5], Nd[1], Nd[6]);
    end;

    g := FGmsh.ElementPhysicalRegion[i] - 1;

    if g < 0 then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in no physical region.');

    s := g div 10;
    g := g mod 10;

    if s > NbSegments - 1 then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in physical ' +
        'region ' + IntToStr(FGmsh.ElementPhysicalRegion[i]) + ', which is ' +
        'not in any segment.');

    if g = 9 then
    begin

      // A shell of a sphere, meshed in one extrusion with the others and
      // told apart here by the mean radius of its nodes - which lies
      // strictly between two boundaries, since element layers end on them.
      //
      // The mean of the radii, NOT the radius of the element's centre. The
      // centre of a flat face sits inside the sphere its corners lie on, by
      // about a millimetre on this mesh - more than the skin is thick - so
      // the centre's radius put whole patches of skin into the fat, losing
      // their skin faces and giving them the fat's conductivity.
      rr := 0;

      for j := 0 to nb - 1 do
        rr := rr + Sqrt(Sqr(FGmsh.CoordX[Nd[j]] - FSegCx[s]) +
                        Sqr(FGmsh.CoordY[Nd[j]] - FSegCy[s]) +
                        Sqr(FGmsh.CoordZ[Nd[j]] - FSegZ0[s]));

      rr := rr / nb;

      g := FSegInner[s] + 1;

      while (g < NbLayers - 1) and (rr > FSLOuter[s, g]) do
        Inc(g);

    end
    else if g > NbLayers - 1 then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in physical ' +
        'region ' + IntToStr(FGmsh.ElementPhysicalRegion[i]) + ', which is ' +
        'not one of the compartments.');

    if FSLMass[s, g] <= 0 then
      raise Exception.Create('Element ' + IntToStr(i) + ' is in the ' +
        Layers[g].Name + ' of the ' + Segments[s].Name + ', which has none.');

    FEleSeg[i] := s;
    FEleLayer[i] := g;

    FSLMeshVol[s, g] := FSLMeshVol[s, g] + FEleVolume[i];
    FMeshLayerVol[g] := FMeshLayerVol[g] + FEleVolume[i];

    for j := 0 to nb - 1 do
    begin

      FNodeCapacity[Nd[j]] := FNodeCapacity[Nd[j]] +
        Layers[g].Density * Layers[g].Cp * FEleVolume[i] / nb;

      FNodeSeg[Nd[j]] := s;

    end;

  end;

  for i := 0 to FGmsh.NbNodes - 1 do
    if FNodeSeg[i] >= 0 then
      FNodeS[i] := NodeS(FNodeSeg[i], i);

  (******************** SKIN FACES ********************)

  FNbSkin := 0;
  SetLength(FSkin, FGmsh.NbElements);

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    // Only the outermost compartment carries skin faces, and never a
    // tetrahedron - those are only ever in the head's core.
    if FEleLayer[i] <> LayerSkin then
      Continue;

    nb := ElementNodeCount(i);

    if nb = 8 then
      NbFaces := 6
    else if nb = 6 then
      NbFaces := 5
    else
      Continue;

    s := FEleSeg[i];

    // A face is on the skin when every node of it sits nearer the outer
    // boundary than any node inside the skin can: past three quarters of
    // the way through it. That is looser than asking for the boundary
    // itself, which matters on the head, where the extrusion puts the
    // outer nodes on the sphere only as nearly as the normals are radial.
    Threshold := FSLOuter[s, LayerSkin] -
      0.25 * (FSLOuter[s, LayerSkin] - FSLOuter[s, LayerSkin - 1]);

    HalfAngle := DegToRad(Segments[s].ContactHalfAngleDeg);

    for j := 0 to nb - 1 do
      Nd[j] := FGmsh.ElementNode[i, j];

    for f := 0 to NbFaces - 1 do
    begin

      if nb = 8 then
        n := 4
      else
        n := PrismFaceNodes[f];

      OnSkin := True;

      for j := 0 to n - 1 do
      begin

        if nb = 8 then
          FN[j] := Nd[HexFace[f, j]]
        else
          FN[j] := Nd[PrismFace[f, j]];

        if FNodeS[FN[j]] < Threshold then
          OnSkin := False;

      end;

      if not OnSkin then
        Continue;

      // Area: half the magnitude of the cross product of two edges on a
      // triangle, and of the two diagonals on a (planar) quadrilateral.
      if n = 3 then
      begin

        ax := FGmsh.CoordX[FN[1]] - FGmsh.CoordX[FN[0]];
        ay := FGmsh.CoordY[FN[1]] - FGmsh.CoordY[FN[0]];
        az := FGmsh.CoordZ[FN[1]] - FGmsh.CoordZ[FN[0]];

        bx := FGmsh.CoordX[FN[2]] - FGmsh.CoordX[FN[0]];
        by := FGmsh.CoordY[FN[2]] - FGmsh.CoordY[FN[0]];
        bz := FGmsh.CoordZ[FN[2]] - FGmsh.CoordZ[FN[0]];

      end
      else
      begin

        ax := FGmsh.CoordX[FN[2]] - FGmsh.CoordX[FN[0]];
        ay := FGmsh.CoordY[FN[2]] - FGmsh.CoordY[FN[0]];
        az := FGmsh.CoordZ[FN[2]] - FGmsh.CoordZ[FN[0]];

        bx := FGmsh.CoordX[FN[3]] - FGmsh.CoordX[FN[1]];
        by := FGmsh.CoordY[FN[3]] - FGmsh.CoordY[FN[1]];
        bz := FGmsh.CoordZ[FN[3]] - FGmsh.CoordZ[FN[1]];

      end;

      cx := ay * bz - az * by;
      cy := az * bx - ax * bz;
      cz := ax * by - ay * bx;

      mx := 0;
      my := 0;
      mz := 0;

      for j := 0 to n - 1 do
      begin
        FSkin[FNbSkin].Node[j] := FN[j];
        mx := mx + FGmsh.CoordX[FN[j]];
        my := my + FGmsh.CoordY[FN[j]];
        mz := mz + FGmsh.CoordZ[FN[j]];
      end;

      mx := mx / n;
      my := my / n;
      mz := mz / n;

      FSkin[FNbSkin].Seg := s;
      FSkin[FNbSkin].Ele := i;
      FSkin[FNbSkin].FaceIdx := f;
      FSkin[FNbSkin].NbNodes := n;
      FSkin[FNbSkin].Area := 0.5 * Sqrt(cx * cx + cy * cy + cz * cz);

      if Segments[s].Shape = ssSphere then
      begin

        // The angle between this face and straight down, seen from the
        // centre. The patch on the cushion is the cap within
        // ContactHalfAngleDeg of it.
        dx := mx - FSegCx[s];
        dy := my - FSegCy[s];
        dz := mz - FSegZ0[s];

        rr := Sqrt(dx * dx + dy * dy + dz * dz);

        FSkin[FNbSkin].Angle := ArcCos(EnsureRange(-dy / rr, -1.0, 1.0));

        FSkin[FNbSkin].Supported := FSkin[FNbSkin].Angle <= HalfAngle;

      end
      else
      begin

        // Where this face sits round the section, as the ellipse's own
        // parametric angle: x = s*cos t, y = k*s*sin t, so dividing y
        // by k before taking the angle is what makes t come out. The
        // patch in contact with the cushion is the part within
        // ContactHalfAngleDeg of straight down, t = -90.
        FSkin[FNbSkin].Angle := ArcTan2((my - FSegCy[s]) / Segments[s].Aspect,
                                        mx - FSegCx[s]);

        FSkin[FNbSkin].Supported :=
          Abs(FSkin[FNbSkin].Angle + Pi / 2) <= HalfAngle;

      end;

      // The gown lies over the exposed faces of the segments it covers,
      // in the gowned case only. The elements themselves are built with
      // the model, since they are part of it - see BuildGown.
      FSkin[FNbSkin].Covered := (FCase = CaseGowned) and (s in GownSegments) and
                                not FSkin[FNbSkin].Supported;
      FSkin[FNbSkin].GownEle := -1;
      FSkin[FNbSkin].GownFaceIdx := -1;
      FSkin[FNbSkin].GownArea := 0;

      FMeshArea := FMeshArea + FSkin[FNbSkin].Area;
      FSegMeshArea[s] := FSegMeshArea[s] + FSkin[FNbSkin].Area;

      if FSkin[FNbSkin].Supported then
      begin
        FMeshAreaBack := FMeshAreaBack + FSkin[FNbSkin].Area;
        FSegMeshAreaBack[s] := FSegMeshAreaBack[s] + FSkin[FNbSkin].Area;
      end
      else
      begin
        FMeshAreaFront := FMeshAreaFront + FSkin[FNbSkin].Area;
        FSegMeshAreaFront[s] := FSegMeshAreaFront[s] + FSkin[FNbSkin].Area;
      end;

      if FSkin[FNbSkin].Covered then
      begin
        FMeshAreaGown := FMeshAreaGown + FSkin[FNbSkin].Area;
        FSegMeshAreaGown[s] := FSegMeshAreaGown[s] + FSkin[FNbSkin].Area;
      end;

      Inc(FNbSkin);

      if FNbSkin >= Length(FSkin) then
        SetLength(FSkin, Length(FSkin) * 2);

    end;

  end;

  SetLength(FSkin, FNbSkin);

  (******************** CENTRES ********************)

  // Each segment's centre node: the middle of a sphere, and on a cylinder
  // the axis half way along. The trunk's is the core the whole model
  // reports and holds at the set point.
  for s := 0 to NbSegments - 1 do
  begin

    px := FSegCx[s];
    py := FSegCy[s];

    if Segments[s].Shape = ssSphere then
      pz := FSegZ0[s]
    else
      pz := FSegZ0[s] + FSegLen[s] / 2;

    Best := MaxDouble;
    FSegCentreNode[s] := -1;

    for i := 0 to FGmsh.NbNodes - 1 do
    begin

      if FNodeSeg[i] <> s then
        Continue;

      d := Sqr(FGmsh.CoordX[i] - px) + Sqr(FGmsh.CoordY[i] - py) +
           Sqr(FGmsh.CoordZ[i] - pz);

      if d < Best then
      begin
        Best := d;
        FSegCentreNode[s] := i;
      end;

    end;

    if FSegCentreNode[s] < 0 then
      raise Exception.Create('The ' + Segments[s].Name + ' has no nodes - ' +
        'gmsh meshed nothing for it.');

  end;

  FCoreNode := FSegCentreNode[SegTrunk];

end;

procedure TThermalModel.BuildModel;
var

  i, j, nb, g, s, NbTissue, MatAir, MatCotton : Integer;

  Mat, LinkMat : Array[0..NbLayers - 1] of Integer;

  Node : Array[0..7] of Integer;

  EleType : NEleType;

  Q, GSum, px, py, pz, Len : Double;

begin

  FEngine := TThermalEngine.Create;

  FEngine.PenaltyMethod := True;

  // A direct solve - PARDISO, symmetric positive definite, which is what
  // soUMFPACK maps to - rather than the ILU0-preconditioned GMRES this
  // model used as a single cylinder. The body's mesh mixes millimetre-thin
  // skin layers with elements half a metre long and a blood-pool node
  // joined to thousands of others, and GMRES took most of a minute per
  // solve on it; the direct solve is under a second, and a transient is
  // a hundred and twenty of them.
  FEngine.SolverType := soUMFPACK;

  (******************** MATERIALS ********************)

  // One material per compartment, from the layer table - a compartment
  // is the same tissue whichever segment it is in.
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

  // The gown's two layers: still air, and cotton. Real densities and
  // heat capacities, so what little the gown stores is in the energy
  // balance rather than ignored - it is a few hundred joules per kelvin
  // against the body's quarter of a megajoule. Only the gowned case
  // builds elements from them, but the lists exist in every case so the
  // surface bookkeeping needs no special cases.
  FAirRho := TExpressionList.Create;
  FAirRho.AddExpression(0, 1000, Num(AirDensity), 'T');
  FAirCp := TExpressionList.Create;
  FAirCp.AddExpression(0, 1000, Num(AirCp), 'T');
  FAirK := TExpressionList.Create;
  FAirK.AddExpression(0, 1000, Num(AirConductivity), 'T');

  FCottonRho := TExpressionList.Create;
  FCottonRho.AddExpression(0, 1000, Num(CottonDensity), 'T');
  FCottonCp := TExpressionList.Create;
  FCottonCp.AddExpression(0, 1000, Num(CottonCp), 'T');
  FCottonK := TExpressionList.Create;
  FCottonK.AddExpression(0, 1000, Num(CottonConductivity), 'T');

  MatAir := FEngine.AddMaterial(Constant, FAirRho, FAirCp, FAirK);
  MatCotton := FEngine.AddMaterial(Constant, FCottonRho, FCottonCp, FCottonK);

  (******************** THE BLOOD POOL ********************)

  // Blood is carried as a node of its own, joined to every perfused tissue
  // node by a one-dimensional conduction link whose conductance is that
  // node's Pennes conductance, w*rho_b*c_b*V lumped to it. The links have
  // no density, so they store nothing, and the pool node therefore has no
  // heat capacity: the only temperature at which the heat flowing into it
  // balances the heat flowing out is
  //
  //   Tart = sum(G_i * T_i) / sum(G_i)
  //
  // - the flow-weighted mean - and the solver finds it as part of the same
  // linear system as the tissue, every step. So perfusion is IMPLICIT, and
  // it moves heat between compartments while creating none, both exactly,
  // with no iteration and no restriction on the step.
  //
  // One material per compartment, so that each compartment's flow can be
  // opened or closed on its own by rewriting that material's conductivity
  // - see SetBloodFlow. The link cross-section carries the conductance
  // itself, set against a reference conductivity of 1, so the conductivity
  // expression IS the fraction of full flow.
  FLinkRho := TExpressionList.Create;
  FLinkRho.AddExpression(0, 1000, '0', 'T');

  FLinkCp := TExpressionList.Create;
  FLinkCp.AddExpression(0, 1000, '0', 'T');

  for i := 0 to NbLayers - 1 do
  begin

    FLinkFrac[i] := 1;

    FLinkK[i] := TExpressionList.Create;
    FLinkK[i].AddExpression(0, 1000, '1', 'T');

    LinkMat[i] := FEngine.AddMaterial(Constant, FLinkRho, FLinkCp, FLinkK[i]);

  end;

  (******************** MESH ********************)

  FEngine.BeginAddMesh;

  NbTissue := FGmsh.NbNodes;

  for i := 0 to NbTissue - 1 do
    FEngine.AddNode(FGmsh.CoordX[i], FGmsh.CoordY[i], FGmsh.CoordZ[i]);

  GSum := 0;

  for i := 0 to NbTissue - 1 do
    GSum := GSum + FNodePerfG[i];

  // The pool sits a metre under the table, clear of every tissue node so
  // no link has zero length. Where it is changes nothing but the links'
  // cross-sections; with no flow at all there is nothing to join it to,
  // and it is left out rather than added as a node attached to nothing.
  if GSum > 0 then
  begin
    px := 0;
    py := -1.0;
    pz := FSegZ0[SegTrunk] + FSegLen[SegTrunk] / 2;
    FPoolNode := FEngine.AddNode(px, py, pz);
  end
  else
    FPoolNode := -1;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    nb := ElementNodeCount(i);

    case nb of
      8 : EleType := elHexa;
      6 : EleType := elPrism;
    else
      EleType := elTetra;
    end;

    for j := 0 to nb - 1 do
      Node[j] := FGmsh.ElementNode[i, j];

    FEngine.AddElement(Node, nb, EleType, Mat[FEleLayer[i]]);

  end;

  if FPoolNode >= 0 then
    for i := 0 to NbTissue - 1 do
      for g := 0 to NbLayers - 1 do
      begin

        if FNodePerfGL[i, g] <= 0 then
          Continue;

        Len := Sqrt(Sqr(FGmsh.CoordX[i] - px) + Sqr(FGmsh.CoordY[i] - py) +
                    Sqr(FGmsh.CoordZ[i] - pz));

        Node[0] := i;
        Node[1] := FPoolNode;

        // Conductance = area * conductivity / length, at conductivity 1.
        FEngine.AddElement(Node, 2, elBeam, LinkMat[g], FNodePerfGL[i, g] * Len);

      end;

  // The lumped capacities were sized to the tissue by CalcElementGeometry;
  // the pool node stores nothing, and the gown's nodes, if any, are
  // added to the tail by BuildGown. Re-sized here so a re-solve starts
  // clean rather than accumulating.
  SetLength(FNodeCapacity, FGmsh.NbNodes);

  FNbGownElements := 0;
  FGownArea := 0;

  if FCase = CaseGowned then
    BuildGown(MatAir, MatCotton);

  FEngine.EndAddMesh;

  (******************** RESTRAINTS ********************)

  // None: no temperature is prescribed anywhere. The convection at the
  // skin is what makes the system non-singular, and it is also the only
  // route out for the metabolic heat. Begin/End still have to be called
  // to size the engine's own bookkeeping.
  FEngine.BeginSetRestraints;
  FEngine.EndSetRestraints;

  (******************** METABOLIC GENERATION ********************)

  // There is no volumetric-source call on the engine, so each
  // compartment's generation is lumped to its nodes here - the same thing
  // the structural engine does internally for self weight. Scaled by the
  // MESHED volume of that compartment in that segment, so each receives
  // exactly its share of the total however coarsely the shapes are
  // polygonised.
  SetLength(FNodeQMet, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    FNodeQMet[i] := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    s := FEleSeg[i];
    g := FEleLayer[i];

    if FSLPower[s, g] <= 0 then
      Continue;

    nb := ElementNodeCount(i);

    Q := FSLPower[s, g] * (FEleVolume[i] / FSLMeshVol[s, g]) / nb;

    for j := 0 to nb - 1 do
      FNodeQMet[FGmsh.ElementNode[i, j]] := FNodeQMet[FGmsh.ElementNode[i, j]] + Q;

  end;

  // The static solves below run at the set point, where the Q10 factor
  // is 1 by construction, so the sources start unscaled; UpdateSources
  // takes it over once the transient begins.
  FMetFactor := 1;

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

  // Under the gown the room's coefficient moves out to the cloth's outer
  // face, and the skin beneath gets a coefficient of its own that is
  // zero except in the closed-form check, which needs the gown out of
  // the way - see SetSurfaceCoefficients. Both attached here, once, and
  // rewritten in place like the others.
  FHGown := TExpressionList.Create;
  FHGown.AddExpression(-1E9, 1E9, Num(FHDraped), 't');

  FHUnderGown := TExpressionList.Create;
  FHUnderGown.AddExpression(-1E9, 1E9, '0', 't');

  FGownEmiss := TExpressionList.Create;
  FGownEmiss.AddExpression(-1E9, 1E9, Num(GownEmissivity), 't');

  for i := 0 to FNbSkin - 1 do
    if FSkin[i].Supported then
      FEngine.AddFaceConvection(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FHPad, FTinf)
    else if FSkin[i].Covered then
    begin
      FEngine.AddFaceConvection(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FHUnderGown, FTinf);
      FEngine.AddFaceConvection(FSkin[i].GownEle, FSkin[i].GownFaceIdx, Constant, FHGown, FTinf);
    end
    else
      FEngine.AddFaceConvection(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FHConv, FTinf);

  (******************** INITIAL CONDITION ********************)

  FEngine.SetInitialTemperature(CoreSetPointC + Kelvin);

end;


{ Extrude the gown over every covered skin face: a hexahedron of still
  air standing on the face, then a hexahedron of cloth on top of it, each
  one layer thick. The room's conditions go on the cloth's outer face,
  and the skin beneath is joined to it by nothing but the air's own
  conduction - a millimetre of still air is far too thin to convect, and
  radiation across the gap is left out as specified.

  Node ordering: TBrick_H8V1 takes gmsh's, four nodes round the bottom
  face then the four above them in the same order, so a quad face's own
  nodes plus the nodes pushed out from them make a valid brick as they
  stand, and the outer face is then face 1 of the brick (see HexFace).
  The brick may come out left-handed, since a skin face's node order is
  whichever way the tissue element's own face table runs; the element
  takes its Jacobian in absolute value, so that costs nothing.

  The nodes are shared between adjacent faces, through a map from each
  skin node to the two pushed out from it, so the gown is one continuous
  sheet rather than a shingle of loose plates and heat can spread along
  it. Each node is pushed out along the section's OUTWARD NORMAL - on
  the trunk's ellipse x^2/a^2 + y^2/b^2 = 1 that is (x/a^2, y/b^2), not
  the radial direction - so the two layers are of even thickness all
  round. A sphere would be radial, though nothing spherical wears a gown
  at present.

  Where the gown stops - at the edge of the cushion patch, and at the
  ends of a cylinder - its own edges get no condition, which is
  adiabatic: two millimetres of edge against square metres of face.

  The new nodes' lumped capacities go on the tail of FNodeCapacity, so
  what the gown stores is in the energy balance like everything else. }
procedure TThermalModel.BuildGown(MatAir, MatCotton : Integer);
var

  i, j, s, nd, NbTissue : Integer;

  Mid, Outer : TIntegerArray;

  Node : Array[0..7] of Integer;

  x, y, z, nx, ny, nz, Len, Q : Double;

  ax, ay, az, bx, by, bz, cx, cy, cz : Double;

begin

  NbTissue := FGmsh.NbNodes;

  SetLength(Mid, NbTissue);
  SetLength(Outer, NbTissue);

  for i := 0 to NbTissue - 1 do
  begin
    Mid[i] := -1;
    Outer[i] := -1;
  end;

  for i := 0 to FNbSkin - 1 do
  begin

    if not FSkin[i].Covered then
      Continue;

    // Only the cylinders' skin is meshed in bricks, whose faces are all
    // quadrilaterals; the head's prisms have triangles, and the head
    // is bare. Extruding a triangle would want a prism, not a brick.
    if FSkin[i].NbNodes <> 4 then
      raise Exception.Create('BuildGown: a covered skin face is not a quadrilateral');

    s := FSkin[i].Seg;

    for j := 0 to 3 do
    begin

      nd := FSkin[i].Node[j];

      if Mid[nd] >= 0 then
        Continue;

      x := FGmsh.CoordX[nd];
      y := FGmsh.CoordY[nd];
      z := FGmsh.CoordZ[nd];

      if Segments[s].Shape = ssSphere then
      begin
        nx := x - FSegCx[s];
        ny := y - FSegCy[s];
        nz := z - FSegZ0[s];
      end
      else
      begin
        nx := (x - FSegCx[s]) / Sqr(FSegA[s]);
        ny := (y - FSegCy[s]) / Sqr(FSegB[s]);
        nz := 0;
      end;

      Len := Sqrt(nx * nx + ny * ny + nz * nz);

      nx := nx / Len;
      ny := ny / Len;
      nz := nz / Len;

      Mid[nd] := FEngine.AddNode(x + nx * AirGapThickness,
                                 y + ny * AirGapThickness,
                                 z + nz * AirGapThickness);

      Outer[nd] := FEngine.AddNode(x + nx * (AirGapThickness + GownThickness),
                                   y + ny * (AirGapThickness + GownThickness),
                                   z + nz * (AirGapThickness + GownThickness));

    end;

    for j := 0 to 3 do
    begin
      Node[j] := FSkin[i].Node[j];
      Node[j + 4] := Mid[FSkin[i].Node[j]];
    end;

    FEngine.AddElement(Node, 8, elHexa, MatAir);

    for j := 0 to 3 do
    begin
      Node[j] := Mid[FSkin[i].Node[j]];
      Node[j + 4] := Outer[FSkin[i].Node[j]];
      FSkin[i].GownNode[j] := Outer[FSkin[i].Node[j]];
    end;

    FSkin[i].GownEle := FEngine.AddElement(Node, 8, elHexa, MatCotton);
    FSkin[i].GownFaceIdx := 1;

    Inc(FNbGownElements, 2);

    // The outer face's area, measured the way CalcElementGeometry
    // measures a skin face: half the cross product of the diagonals.
    ax := FEngine.CoordX[FSkin[i].GownNode[2]] - FEngine.CoordX[FSkin[i].GownNode[0]];
    ay := FEngine.CoordY[FSkin[i].GownNode[2]] - FEngine.CoordY[FSkin[i].GownNode[0]];
    az := FEngine.CoordZ[FSkin[i].GownNode[2]] - FEngine.CoordZ[FSkin[i].GownNode[0]];

    bx := FEngine.CoordX[FSkin[i].GownNode[3]] - FEngine.CoordX[FSkin[i].GownNode[1]];
    by := FEngine.CoordY[FSkin[i].GownNode[3]] - FEngine.CoordY[FSkin[i].GownNode[1]];
    bz := FEngine.CoordZ[FSkin[i].GownNode[3]] - FEngine.CoordZ[FSkin[i].GownNode[1]];

    cx := ay * bz - az * by;
    cy := az * bx - ax * bz;
    cz := ax * by - ay * bx;

    FSkin[i].GownArea := 0.5 * Sqrt(cx * cx + cy * cy + cz * cz);

    FGownArea := FGownArea + FSkin[i].GownArea;

  end;

  (******************** CAPACITY ********************)

  SetLength(FNodeCapacity, FEngine.NbNodes);

  for i := NbTissue to FEngine.NbNodes - 1 do
    FNodeCapacity[i] := 0;

  for i := 0 to FNbSkin - 1 do
  begin

    if not FSkin[i].Covered then
      Continue;

    // Each brick's capacity lumped equally to its eight nodes, as the
    // tissue's is. A layer's volume is its face area times its
    // thickness, the inner face's for the air and the outer's for the
    // cloth - a millimetre's taper on a decimetre's radius is nothing.
    Q := AirDensity * AirCp * FSkin[i].Area * AirGapThickness / 8;

    for j := 0 to 3 do
    begin
      nd := FSkin[i].Node[j];
      FNodeCapacity[nd] := FNodeCapacity[nd] + Q;
      FNodeCapacity[Mid[nd]] := FNodeCapacity[Mid[nd]] + Q;
    end;

    Q := CottonDensity * CottonCp * FSkin[i].GownArea * GownThickness / 8;

    for j := 0 to 3 do
    begin
      nd := FSkin[i].Node[j];
      FNodeCapacity[Mid[nd]] := FNodeCapacity[Mid[nd]] + Q;
      FNodeCapacity[Outer[nd]] := FNodeCapacity[Outer[nd]] + Q;
    end;

  end;

end;

{ Whether the run applies radiation at the surface: the drapes stand in
  for it while they are on, and every case but the held one takes them
  off at t = 0. }
function TThermalModel.Radiating : Boolean;
begin

  Result := FCase <> CaseDraped;

end;

{ Distribute a cardiac output across the compartments of every segment
  and turn it into a per-node perfusion conductance.

  The Pennes bioheat term is a volumetric exchange with blood arriving at
  the arterial temperature,

    q_perf = w * rho_b * c_b * (Tart - T)   [W/m3]

  so lumping w*rho_b*c_b*V to the nodes of each element gives a
  conductance in W/K, which is all the rest of the model needs.

  Flow shares are the resting distribution of cardiac output. Brain 14%
  is the head's core; heart 4%, splanchnic 25%, kidneys 20% and bone and
  the rest 12% fall in the trunk's core, giving it 61%. Muscle takes 18%,
  skin 5% and fat 2%, each shared among the segments by meshed volume -
  so a given compartment is perfused at the same rate per unit volume in
  every segment that has it. Fat is perfused even though it is not
  metabolising - the two are different things, and it is the perfusion
  that matters for carrying heat. }
procedure TThermalModel.SetPerfusion(CardiacOutput : Double);
var

  i, g, s, j, nb : Integer;

  Flow, w : Double;

begin

  FCardiacOutput := Max(CardiacOutputMin, Min(CardiacOutputMax, CardiacOutput));

  SetLength(FNodePerfG, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    FNodePerfG[i] := 0;

  for s := 0 to NbSegments - 1 do
    for g := 0 to NbLayers - 1 do
    begin

      if FSLMeshVol[s, g] <= 0 then
        Flow := 0
      else if g = LayerCore then
        Flow := FCardiacOutput * Segments[s].CoreFlow
      else
        Flow := FCardiacOutput * Layers[g].FlowShare *
                FSLMeshVol[s, g] / FMeshLayerVol[g];

      FSLFlow[s, g] := Flow;

      // L/min to m3/s, then per unit volume of this compartment.
      if FSLMeshVol[s, g] > 0 then
        w := (Flow / 1000 / 60) / FSLMeshVol[s, g]
      else
        w := 0;

      FSLW[s, g] := w;

      if w > 0 then
        FSLTau[s, g] := Layers[g].Density * Layers[g].Cp / (w * BloodDensity * BloodCp)
      else
        FSLTau[s, g] := 0;

    end;

  // Kept per compartment as well as in total, because a node on a
  // boundary is perfused by both compartments either side of it, and each
  // compartment's flow is switched on its own - see SetBloodFlow.
  SetLength(FNodePerfGL, FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
    for g := 0 to NbLayers - 1 do
      FNodePerfGL[i, g] := 0;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    s := FEleSeg[i];
    g := FEleLayer[i];

    if FSLW[s, g] <= 0 then
      Continue;

    nb := ElementNodeCount(i);

    for j := 0 to nb - 1 do
    begin

      FNodePerfGL[FGmsh.ElementNode[i, j], g] :=
        FNodePerfGL[FGmsh.ElementNode[i, j], g] +
        FSLW[s, g] * BloodDensity * BloodCp * FEleVolume[i] / nb;

      FNodePerfG[FGmsh.ElementNode[i, j]] :=
        FNodePerfG[FGmsh.ElementNode[i, j]] +
        FSLW[s, g] * BloodDensity * BloodCp * FEleVolume[i] / nb;

    end;

  end;

end;

{ Open or close each compartment's blood flow, as a fraction of its full
  resting share: one value per compartment, innermost first. The links
  to the pool carry their conductance in their cross-section against a
  reference conductivity of 1, so rewriting each compartment's link
  conductivity to the fraction is all it takes - the engine re-reads
  material properties at every assembly. }
procedure TThermalModel.SetBloodFlow(const Frac : Array of Double);
var
  l : Integer;
begin

  for l := 0 to NbLayers - 1 do
  begin

    FLinkFrac[l] := Frac[l];

    FLinkK[l].Clear;
    FLinkK[l].AddExpression(0, 1000, Num(Frac[l]), 'T');

  end;

end;

{ Read the blood pool back from the solve just taken, and rewrite every
  node's metabolic source for the next.

  The pool closes the loop. Blood leaves it at Tart, exchanges with
  tissue and returns; with no external source or sink of blood heat, a
  well-mixed pool must sit at the FLOW-WEIGHTED MEAN tissue temperature,

    Tart = sum(G_i * T_i) / sum(G_i)

  and that makes sum(G_i * (Tart - T_i)) identically zero. So perfusion
  moves heat from warm compartments to cold ones and creates none, which
  is both the physics and the reason the energy-balance column in the
  report stays meaningful with perfusion switched on. With the segments
  unjoined, it is also the only way heat gets from one segment to
  another.

  None of that is done here any more. The pool is a node of the model,
  joined to the tissue by conduction links that store nothing - see
  BuildModel - so the solver puts it at the flow-weighted mean itself, in
  the same linear system and the same step as the tissue. Perfusion is
  therefore implicit: no lag, and no limit on the step beyond accuracy.
  All this reads is the pool's temperature, and the net heat the links
  carried, which is carried out and printed so that the zero is checked
  rather than asserted.

  METABOLISM FOLLOWS TEMPERATURE

  The other thing rewritten here is the generation itself. Tissue that
  has cooled does not go on producing heat at the rate it did at 37 C:
  metabolic rate falls with temperature by roughly Q10 per 10 K, so the
  metabolic term is scaled by

    Q10^((Tcore - Tset)/10)

  which is 1 at the set point and about 0.75 four degrees below it. This
  is why the report's generation is now a column rather than a constant,
  and why the energy-balance column has to be computed against the
  generation ACTUALLY in force at each step - see ReportHistory.

  The factor is taken from the CORE temperature and applied to the whole
  body, rather than each node being scaled by its own temperature. That
  looks like the cruder choice and is the more defensible one: published
  Q10 figures for whole-body human metabolism are measured against core
  temperature, and they already contain the fact that the periphery
  cools further than the core does. Scaling every node locally as well
  would count that twice.

  Scaled like the perfusion term, this is explicit and one step lagged,
  for the same reason and with a great deal more margin: the whole body
  cools over hours, so a 60 second step resolves it easily. }
procedure TThermalModel.UpdateSources;
var

  i, l : Integer;

  Numer, Denom, Q : Double;

begin

  if FPoolNode >= 0 then
    FTArt := FEngine.Temperature[FPoolNode]
  else
  begin

    // No flow at all, so there is no flow-weighted mean to take. Blood
    // that is not moving sits at the temperature of the tissue around
    // it, so the capacity-weighted mean stands in - it drives nothing
    // here, since every conductance is zero, and it keeps the pool
    // column of the report from reading absolute zero.
    Numer := 0;
    Denom := 0;

    for i := 0 to FGmsh.NbNodes - 1 do
    begin
      Numer := Numer + FNodeCapacity[i] * FEngine.Temperature[i];
      Denom := Denom + FNodeCapacity[i];
    end;

    if Denom > 0 then
      FTArt := Numer / Denom
    else
      FTArt := 0;

  end;

  // The heat the blood delivered to the tissue over the step just solved,
  // through the links at the flows they carried. The pool has no capacity,
  // so this is zero to the tolerance of the solve - carried out and printed
  // so that is checked rather than asserted.
  FPerfNet := 0;

  if FPoolNode >= 0 then
    for i := 0 to FGmsh.NbNodes - 1 do
      for l := 0 to NbLayers - 1 do
        if FNodePerfGL[i, l] > 0 then
          FPerfNet := FPerfNet + FNodePerfGL[i, l] * FLinkFrac[l] *
                      (FTArt - FEngine.Temperature[i]);

  // Metabolic rate against the core, referred to the set point - see
  // METABOLISM FOLLOWS TEMPERATURE above. At Q10 = 1 this is identically
  // 1 whatever the core is doing, which is the switch that turns the
  // whole effect off.
  FMetFactor := Power(Q10,
    (FEngine.Temperature[FCoreNode] - (CoreSetPointC + Kelvin)) / 10);

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    Q := FNodeQMet[i] * FMetFactor;

    FGenSource[i].Clear;
    FGenSource[i].AddExpression(-1E9, 1E9, Num(Q), 't');

  end;

end;

function TThermalModel.TotalEnergy : Double;
var
  i : Integer;
begin

  Result := 0;

  // Over every node with a capacity - the tissue, and the gown's when
  // it is worn; the pool node between them stores nothing.
  for i := 0 to Length(FNodeCapacity) - 1 do
    Result := Result + FNodeCapacity[i] * FEngine.Temperature[i];

end;

{ Heat leaving the skin - of the whole body, or of one segment - split
  between the surface exposed to the room and the patch lying on the
  cushion.

  The two are worth carrying separately, and not only for the report:
  they are the whole point of the cushion. Radiation is charged to the
  exposed faces alone, because those are the only ones Expose gives a
  radiation condition to - a surface pressed into foam has nothing to
  radiate to.

  Under the gown the exposed face the room sees is the cloth's outer
  one, so that is the temperature, area, coefficient and emissivity the
  loss is charged at there; the skin's own term beneath it is kept, but
  its coefficient is zero outside the closed-form check. }
procedure TThermalModel.SurfaceLosses(UseRadiation : Boolean;
                                      out Front, Back : Double;
                                      Seg : Integer);
var

  i, j : Integer;

  Tf, Tg, Tinf, h, u, hg, hu, Q : Double;

begin

  Front := 0;
  Back := 0;

  Tinf := AmbientC + Kelvin;

  h := FHConv.GetValue(0);
  u := FHPad.GetValue(0);
  hg := FHGown.GetValue(0);
  hu := FHUnderGown.GetValue(0);

  for i := 0 to FNbSkin - 1 do
  begin

    if (Seg >= 0) and (FSkin[i].Seg <> Seg) then
      Continue;

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    if FSkin[i].Supported then
    begin
      Back := Back + u * (Tf - Tinf) * FSkin[i].Area;
      Continue;
    end;

    if FSkin[i].Covered then
    begin

      Tg := 0;

      for j := 0 to 3 do
        Tg := Tg + FEngine.Temperature[FSkin[i].GownNode[j]];

      Tg := Tg / 4;

      Q := hu * (Tf - Tinf) * FSkin[i].Area +
           hg * (Tg - Tinf) * FSkin[i].GownArea;

      if UseRadiation then
        Q := Q + GownEmissivity * Sigma *
             (Tg * Tg * Tg * Tg - Tinf * Tinf * Tinf * Tinf) * FSkin[i].GownArea;

      Front := Front + Q;

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
  exposed part of it, or over the patch on the cushion - of the whole
  body, or of one segment - as the field now stands or as it stood at
  t = 0.

  A sector with no faces in it has no mean of its own, so the mean over
  the whole of that surface stands in. That only arises with a segment
  lifted off the cushion (ContactHalfAngleDeg = 0), where every face is
  exposed and the two answers coincide anyway - and it keeps a degenerate
  configuration from reporting a skin temperature of absolute zero. }
function TThermalModel.MeanSkinTemperature(Sector : TProfileSector;
                                           Seg : Integer;
                                           Initial : Boolean) : Double;
var

  i, j : Integer;

  Tf, A : Double;

begin

  Result := 0;
  A := 0;

  for i := 0 to FNbSkin - 1 do
  begin

    if (Seg >= 0) and (FSkin[i].Seg <> Seg) then
      Continue;

    if (Sector = psFront) and FSkin[i].Supported then
      Continue;

    if (Sector = psBack) and not FSkin[i].Supported then
      Continue;

    Tf := 0;

    for j := 0 to FSkin[i].NbNodes - 1 do
      if Initial then
        Tf := Tf + FTInitial[FSkin[i].Node[j]]
      else
        Tf := Tf + FEngine.Temperature[FSkin[i].Node[j]];

    Tf := Tf / FSkin[i].NbNodes;

    Result := Result + Tf * FSkin[i].Area;
    A := A + FSkin[i].Area;

  end;

  if A > 0 then
    Result := Result / A
  else if Sector <> psAll then
    Result := MeanSkinTemperature(psAll, Seg, Initial);

end;

{ Area-weighted mean temperature of the cloth's outer face - the surface
  the room actually sees over the trunk and arms in the gowned case - of
  the whole gown or of one segment's part of it, now or at t = 0. With no
  gown on the segment asked about (or no gown at all) there is nothing
  to average, and the exposed skin's mean stands in, so a caller printing
  both columns for every segment gets the surface the room sees either
  way. }
function TThermalModel.MeanGownTemperature(Seg : Integer;
                                           Initial : Boolean) : Double;
var

  i, j : Integer;

  Tg, A : Double;

begin

  Result := 0;
  A := 0;

  for i := 0 to FNbSkin - 1 do
  begin

    if (Seg >= 0) and (FSkin[i].Seg <> Seg) then
      Continue;

    if not FSkin[i].Covered then
      Continue;

    Tg := 0;

    for j := 0 to 3 do
      if Initial then
        Tg := Tg + FTInitial[FSkin[i].GownNode[j]]
      else
        Tg := Tg + FEngine.Temperature[FSkin[i].GownNode[j]];

    Tg := Tg / 4;

    Result := Result + Tg * FSkin[i].GownArea;
    A := A + FSkin[i].GownArea;

  end;

  if A > 0 then
    Result := Result / A
  else
    Result := MeanSkinTemperature(psFront, Seg, Initial);

end;

{ Rewrite the surface conditions in place. The engine holds the
  expression objects themselves and re-reads them at every assembly, so
  this is all it takes to move a coefficient between solves.

  The front's coefficient normally goes where the room is: on the skin
  where it is bare, on the cloth's outer face where the gown covers it.
  UniformOnSkin puts it on the skin everywhere and leaves the cloth's
  outer face with nothing - so nothing leaves through the gown, and all
  it can still do is conduct a little along its own sheet - which is
  the configuration the closed-form check needs, since its chains know
  nothing of a gown. }
procedure TThermalModel.SetSurfaceCoefficients(HFront, UBack : Double;
                                               UniformOnSkin : Boolean);
begin

  FHConv.Clear;
  FHConv.AddExpression(-1E9, 1E9, Num(HFront), 't');

  FHPad.Clear;
  FHPad.AddExpression(-1E9, 1E9, Num(UBack), 't');

  FHGown.Clear;
  FHUnderGown.Clear;

  if UniformOnSkin then
  begin
    FHGown.AddExpression(-1E9, 1E9, '0', 't');
    FHUnderGown.AddExpression(-1E9, 1E9, Num(HFront), 't');
  end
  else
  begin
    FHGown.AddExpression(-1E9, 1E9, Num(HFront), 't');
    FHUnderGown.AddExpression(-1E9, 1E9, '0', 't');
  end;

end;

{ Take the drapes off the front: its coefficient drops to bare-skin
  natural convection, and radiation - which the drapes were standing in
  for - becomes an explicit boundary condition of its own. The
  expression object is the one already handed to the engine, so
  rewriting it is enough; the assembly re-reads it every step.

  Nothing here touches the cushion. The patient does not get up off it
  at induction, so the contact patch keeps the conductance it had, and
  gets no radiation condition at all - it has nothing to radiate to.

  Nor does it take the gown off. Where the gown covers the skin the
  drapes come off the CLOTH: its outer face gets the bare coefficient and
  a radiation condition at the cloth's own emissivity, and the skin
  beneath goes on seeing nothing but the air layer. }
procedure TThermalModel.Expose;
var
  i : Integer;
begin

  FHConv.Clear;
  FHConv.AddExpression(-1E9, 1E9, Num(BareConvection), 't');

  FHGown.Clear;
  FHGown.AddExpression(-1E9, 1E9, Num(BareConvection), 't');

  for i := 0 to FNbSkin - 1 do
  begin

    if FSkin[i].Supported then
      Continue;

    if FSkin[i].Covered then
      FEngine.AddFaceRadiation(FSkin[i].GownEle, FSkin[i].GownFaceIdx, Constant,
                               FGownEmiss, FTinf)
    else
      FEngine.AddFaceRadiation(FSkin[i].Ele, FSkin[i].FaceIdx, Constant, FEmiss, FTinf);

  end;

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
    SetLength(FHistGown, Length(FHistT));
    SetLength(FHistGen, Length(FHistT));
    SetLength(FHistLoss, Length(FHistT));
    SetLength(FHistLossB, Length(FHistT));
    SetLength(FHistStore, Length(FHistT));
    SetLength(FHistTArt, Length(FHistT));
    SetLength(FHistPerf, Length(FHistT));
  end;

  SurfaceLosses(Radiating, LossFront, LossBack);

  FHistT[FNbHist] := Now_;
  FHistCore[FNbHist] := FEngine.Temperature[FCoreNode] - Kelvin;
  FHistSkin[FNbHist] := MeanSkinTemperature(psFront) - Kelvin;
  FHistSkinB[FNbHist] := MeanSkinTemperature(psBack) - Kelvin;
  FHistGown[FNbHist] := MeanGownTemperature - Kelvin;
  FHistLoss[FNbHist] := LossFront + LossBack;
  FHistLossB[FNbHist] := LossBack;

  if dt > 0 then
    FHistStore[FNbHist] := (E - FEnergyPrev) / dt
  else
    FHistStore[FNbHist] := 0;

  // The generation that was actually in force over the step just taken,
  // which is the one UpdateSources wrote at the END of the previous step
  // - hence recorded before the call below rewrites it. The balance
  // column is computed against this, not against FHeatOutput, or the
  // model's own first-law check would fail by however much the Q10
  // factor had moved.
  FHistGen[FNbHist] := FHeatOutput * FMetFactor;

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

  s, l : Integer;

  Cap : Double;

  Row, LenStr : String;

begin

  Say('');
  Say('================ SUBJECT AND MODEL ================');
  Say(Format('  Body mass                : %8.1f kg', [FTotalMass]));
  Say(Format('  VO2 / RQ                 : %8.0f mL/min at RQ %.2f', [VO2, RQ]));
  Say(Format('  Metabolic heat output    : %8.1f W  (at the %.0f C set point)',
    [FHeatOutput, CoreSetPointC]));
  Say(Format('  Q10                      : %8.2f  (%.1f%% per degree the core',
    [Q10, 100 * (Power(Q10, 0.1) - 1)]));
  Say('                                       falls; 1.0 would hold generation');
  Say('                                       fixed)');
  Say('');

  Say('  compartment    mass    volume     power');
  Say('                 (kg)       (L)       (W)');

  for l := 0 to NbLayers - 1 do
    Say(Format('  %-10s %8.2f %9.2f %9.1f',
      [Layers[l].Name, Layers[l].Mass, FLayerVol[l] * 1000, FLayerPower[l]]));

  Say('');
  Say('  segment    shape          mass  volume   surface (m2)   contact  on cushion   power');
  Say('                            (kg)     (L)  nominal meshed    (deg)         (%)     (W)');

  for s := 0 to NbSegments - 1 do
    Say(Format('  %-10s %-12s %6.2f %7.2f %7.3f %6.3f %8.0f %11.0f %7.1f',
      [Segments[s].Name, ShapeName(s), SegmentMass(s), FSegVol[s] * 1000,
       FSegAreaNominal[s], FSegMeshArea[s], Segments[s].ContactHalfAngleDeg,
       100 * FSegMeshAreaBack[s] / FSegMeshArea[s], FSegPower[s]]));

  // Thickness on the trunk is thinner over the front and back than at the
  // sides, by the axis ratio - the outer s here is the semi-major axis.
  Say('');
  Say('  segment     semi-axes    length       compartment mass (kg) / outer s (mm)');
  Say('                   (mm)       (m)        core        muscle         fat        skin');

  for s := 0 to NbSegments - 1 do
  begin

    if Segments[s].Shape = ssSphere then
      LenStr := '-'
    else
      LenStr := Format('%.3f', [FSegLen[s]]);

    Row := Format('  %-10s %5.1f x %5.1f %7s ',
      [Segments[s].Name, FSegA[s] * 1000, FSegB[s] * 1000, LenStr]);

    for l := 0 to NbLayers - 1 do
      if FSLMass[s, l] > 0 then
        Row := Row + Format('  %5.2f/%5.1f', [FSLMass[s, l], FSLOuter[s, l] * 1000])
      else
        Row := Row + Format('  %11s', ['-']);

    Say(Row);

  end;

  Say('  (s is the radius on the head and the limbs, and the semi-major axis');
  Say('  of the similar ellipse on the trunk.)');

  Cap := 0;

  for l := 0 to NbLayers - 1 do
    Cap := Cap + Layers[l].Mass * Layers[l].Cp;

  Say('');
  Say('  The segments are not joined: the neck, shoulder and hip ends are');
  Say('  adiabatic, and heat passes from one to another only in the blood.');
  Say('');
  Say(Format('  Surface nominal / meshed : %8.3f m2 / %.3f m2',
    [BodySurfaceArea, FMeshArea]));
  Say(Format('  Heat capacity            : %8.0f kJ/K', [Cap / 1000]));
  Say('');
  Say(Format('  Ambient                  : %8.1f C', [AmbientC]));
  Say('');
  Say(Format('  On the cushion           : %8.3f m2 (%.0f%% of the surface)',
    [FMeshAreaBack, 100 * FMeshAreaBack / FMeshArea]));
  Say(Format('  Exposed to the room      : %8.3f m2 (%.0f%%)',
    [FMeshAreaFront, 100 * FMeshAreaFront / FMeshArea]));
  Say(Format('  Cushion conductance      : %8.3f W/m2K  (%.0f mm of foam at %.3f',
    [FUPad, PadThickness * 1000, PadConductivity]));
  Say(Format('                                       W/mK, then %.1f W/m2K beneath)',
    [PadUnderside]));
  Say('');
  Say(Format('  Uniform-surface balance  : %8.2f W/m2K  (no cushion, trunk at the',
    [FHBalance]));
  Say('                                       set point - the analytic reference,');
  Say('                                       not the model''s own)');

  case FCase of

    CaseExposed :
      Say(Format('  Exposed at t=0           : %8.2f W/m2K convection + radiation e=%.2f',
        [BareConvection, SkinEmissivity]));

    CaseGowned :
    begin
      Say(Format('  Exposed at t=0           : %8.2f W/m2K convection + radiation, e=%.2f',
        [BareConvection, SkinEmissivity]));
      Say(Format('                                       on bare skin and e=%.2f on the gown',
        [GownEmissivity]));
      Say(Format('  Gown                     : %8.3f m2 of skin under it (%.0f%% of the',
        [FMeshAreaGown, 100 * FMeshAreaGown / FMeshAreaFront]));
      Say('                                       exposed surface): the front of the');
      Say(Format('                                       trunk and the arms, under %.1f mm of',
        [AirGapThickness * 1000]));
      Say(Format('                                       still air (k %.3f) and %.1f mm of cotton',
        [AirConductivity, GownThickness * 1000]));
      Say(Format('                                       (k %.3f) - %.4f m2K/W, %.2f clo, in',
        [CottonConductivity, FGownResistance, FGownResistance / 0.155]));
      Say('                                       series with the surface');
    end;

  else
    Say('  Exposed at t=0           :      no - the draped state is held');
  end;

  if FCase = CaseGowned then
    Say(Format('  Mesh                     : %8d nodes, %d elements, %d skin faces,',
      [FGmsh.NbNodes, FGmsh.NbElements, FNbSkin]))
  else
    Say(Format('  Mesh                     : %8d nodes, %d elements, %d skin faces',
      [FGmsh.NbNodes, FGmsh.NbElements, FNbSkin]));

  if FCase = CaseGowned then
    Say(Format('                                       plus %d gown elements on %d more nodes',
      [FNbGownElements, FEngine.NbNodes - FGmsh.NbNodes - 1]));

end;

{ The model's check on itself: one static solve with a UNIFORM surface
  coefficient, no cushion and no blood, compared boundary by boundary with
  the closed form SetupGeometry integrated for each segment.

  The reference configuration is not an evasion, it is the point. The
  closed forms describe a body losing heat evenly all over; with the
  cushion under it the model no longer is one, and comparing the two
  would only measure the cushion. Run it uniform and the chains are
  entitled to be right - exactly right on the head and limbs, whose
  concentric shapes really are one-dimensional - so anything beyond
  ordinary discretisation there means the compartments, the generation
  split, the shapes or the 3D elements are not doing what the closed forms
  assume.

  With nothing crossing between segments, each segment's skin sits
  P/(h*A) above the room on its own generation and its own meshed area,
  which is what the analytic column is referred to - so a segment that
  was somehow exchanging heat with another would show here too.

  The last column is what the chains cannot see: the spread of temperature
  among the nodes sitting on one boundary, which on the head and limbs is
  mesh noise and on the trunk's ellipse is the real two-dimensional part
  of the field. }
procedure TThermalModel.VerifyAgainstAnalytic;
const
  // The band of s counted as sitting on a boundary.
  BandTol = 0.0002;
var

  s, l, j, n : Integer;

  TSum, TLo, THi, TFE, TAn, TCentre, TSurf, Spread, Diff : Double;

  IsRound : Boolean;

begin

  Say('');
  Say('================ CHECK AGAINST THE CLOSED FORM ================');

  // On the skin everywhere, gown or no gown: the chains describe the
  // tissue, and the gown is left inert for the check.
  SetSurfaceCoefficients(FHBalance, FHBalance, True);

  // No blood: the closed forms know nothing of it.
  SetBloodFlow([BloodOffFraction, BloodOffFraction, BloodOffFraction, BloodOffFraction]);

  FEngine.CalcTemperature(caStatic, False);

  FUniformWorstRound := 0;
  FUniformWorstTrunk := 0;
  FUniformSpread := 0;

  Say(Format('  A uniform %.3f W/m2K over the whole surface, cushion lifted away',
    [FHBalance]));
  Say('  and no blood - the one configuration the closed forms describe. Each');
  Say('  segment''s skin is referred to its own balance, P/(h*A) above the room.');

  if FCase = CaseGowned then
  begin
    Say('  The gown is out of the way here - the coefficient is put on the skin');
    Say('  beneath it, and its cloth left with no condition - since the chains');
    Say('  describe the tissue alone. All it can still do is conduct a little');
    Say('  along its own sheet, round the trunk''s ellipse.');
  end;

  Say('');
  Say('  segment    boundary          s (mm)     FE (C)  analytic (C)   diff (K)  spread (K)');

  for s := 0 to NbSegments - 1 do
  begin

    IsRound := (Segments[s].Shape = ssSphere) or SameValue(Segments[s].Aspect, 1.0);

    TSurf := AmbientC + FSegPower[s] / (FHBalance * FSegMeshArea[s]);
    TCentre := TSurf + FSegDrop[s];

    TFE := FEngine.Temperature[FSegCentreNode[s]] - Kelvin;
    Diff := TFE - TCentre;

    if IsRound then
      FUniformWorstRound := Max(FUniformWorstRound, Abs(Diff))
    else
      FUniformWorstTrunk := Max(FUniformWorstTrunk, Abs(Diff));

    Say(Format('  %-10s %-14s %8.2f %10.3f %13.3f %10.3f %11s',
      [Segments[s].Name, 'centre', 0.0, TFE, TCentre, Diff, '-']));

    for l := FSegInner[s] to NbLayers - 1 do
    begin

      n := 0;
      TSum := 0;
      TLo := MaxDouble;
      THi := -MaxDouble;

      for j := 0 to FGmsh.NbNodes - 1 do
        if (FNodeSeg[j] = s) and (Abs(FNodeS[j] - FSLOuter[s, l]) < BandTol) then
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
      TAn := TCentre - FSLDrop[s, l];
      Diff := TFE - TAn;
      Spread := THi - TLo;

      if IsRound then
        FUniformWorstRound := Max(FUniformWorstRound, Abs(Diff))
      else
      begin
        FUniformWorstTrunk := Max(FUniformWorstTrunk, Abs(Diff));
        FUniformSpread := Max(FUniformSpread, Spread);
      end;

      Say(Format('  %-10s %-14s %8.2f %10.3f %13.3f %10.3f %11.3f',
        ['', Layers[l].Name + ' out', FSLOuter[s, l] * 1000, TFE, TAn, Diff, Spread]));

    end;

  end;

  Say('');
  Say(Format('  Worst difference on the head and limbs: %.3f K. Their closed forms',
    [FUniformWorstRound]));
  Say('  are exact - concentric spheres and circles really are one-dimensional -');
  Say('  so that is discretisation error and nothing else, and the check that');
  Say('  the shapes, the compartments, the generation split and the elements');
  Say('  (tetrahedra in the head''s core included) are all doing what the');
  Say('  closed forms assume.');
  Say('');
  Say(Format('  Worst on the trunk: %.3f K, and worst spread around one similar',
    [FUniformWorstTrunk]));
  Say(Format('  ellipse %.3f K. Neither is discretisation error. The trunk''s chain',
    [FUniformSpread]));
  Say('  shorts every similar ellipse to a single temperature, which puts the');
  Say('  thick side of the section in parallel with the thin one and can only');
  Say('  UNDERSTATE the resistance - so it is the trunk''s centre, above all,');
  Say('  that the model must put warmer than the chain does.');

end;

{ Find the drape coefficient that leaves the trunk's core at the set
  point, with the cushion in place.

  No closed form can say what it is. The exposed front and the patch on
  the foam sit at quite different temperatures and take quite different
  shares of the output, and no layer chain knows anything about that.

  So it is calibrated on the finite-element model itself. The draped
  problem is linear - conduction, and convection at the surface, with no
  radiation and no blood yet - and with the segments unjoined the trunk
  settles on its own generation alone, as a fixed internal resistance in
  series with its own surface conductance:

    Tcore = Tinf + P_trunk*(Rint + 1/(h*Afront + U*Aback))

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

  h, Target, Tinf, Tcore, GSurf, RInt, GNeed, P, AFront, ABack : Double;

  AGown, ABare, X, qa, qb : Double;

begin

  Say('');
  Say('================ THE DRAPED COEFFICIENT ================');

  // The whole body, since the blood joins every segment to every other:
  // no one segment settles on its own generation any more.
  P := FHeatOutput;
  AFront := FMeshAreaFront;
  ABack := FMeshAreaBack;

  // The gown's resistance is in series with the coefficient over the
  // part of the front it covers - so the update model below has to
  // carry it, or every solve would land short of the target and the
  // iteration crawl.
  AGown := FMeshAreaGown;
  ABare := AFront - AGown;

  if AFront <= 0 then
    raise Exception.Create('The whole body is on the cushion - there is ' +
      'nothing left to balance it through. Reduce ContactHalfAngleDeg.');

  // The awake patient's blood flow: open everywhere but the vasoconstricted
  // skin - see PreInductionFlow.
  SetBloodFlow(PreInductionFlow);

  Target := CoreSetPointC + Kelvin;
  Tinf := AmbientC + Kelvin;

  // The uniform-surface value is a first guess only: it was worked out for
  // the trunk alone, with no blood and nothing underneath it.
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

    // The surface's conductance to the room at this h: bare skin at h,
    // gowned skin at h in series with the gown, the cushion as it is.
    GSurf := h * ABare + AGown * h / (1 + h * FGownResistance) + FUPad * ABack;

    RInt := (Tcore - Tinf) / P - 1 / GSurf;

    GNeed := 1 / ((Target - Tinf) / P - RInt);

    if GNeed <= FUPad * ABack then
      raise Exception.Create('The cushion alone already loses more than the ' +
        'body generates at the set point - no drape coefficient can balance ' +
        'it. Check PadThickness and ContactHalfAngleDeg.');

    X := GNeed - FUPad * ABack;

    if AGown <= 0 then
      h := X / AFront
    else
    begin

      // h*ABare + AGown*h/(1 + h*Rg) = X, which multiplied out is
      //   ABare*Rg*h^2 + (ABare + AGown - X*Rg)*h - X = 0
      // and wants its positive root. With nothing bare the square term
      // goes, and the gown alone has to pass X - which it cannot if its
      // own conductance AGown/Rg is not even that much.
      qa := ABare * FGownResistance;
      qb := ABare + AGown - X * FGownResistance;

      if qa > 0 then
        h := (-qb + Sqrt(qb * qb + 4 * qa * X)) / (2 * qa)
      else if qb > 0 then
        h := X / qb
      else
        raise Exception.Create('The gown alone cannot pass what the body ' +
          'generates at the set point at any drape coefficient. Check ' +
          'the gown''s thickness and conductivities.');

    end;

  end;

  FHDraped := h;

  Say('');
  Say(Format('  Draped coefficient       : %8.3f W/m2K over the exposed %.0f%%',
    [FHDraped, 100 * FMeshAreaFront / FMeshArea]));

  if AGown > 0 then
    Say(Format('                                       (at the cloth over the %.0f%% of it gowned)',
      [100 * AGown / AFront]));
  Say(Format('  Uniform-surface value    : %8.3f W/m2K  (what it would take with',
    [FHBalance]));
  Say('                                       the patient off the cushion)');
  Say(Format('  Converged in             : %8d static solves', [FNbCalibrations]));

  if Abs(FEngine.Temperature[FCoreNode] - Target) >= CoreTolerance then
    Say(Format('  NOT converged - the core is %.3f C, wanted %.3f C',
      [FEngine.Temperature[FCoreNode] - Kelvin, CoreSetPointC]));

end;

{ The trunk's profile from the centre outward, front and back, at t = 0
  and at the end of the run.

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

  l : Integer;

  SF, F0, FE, SB, B0, BE : TVMobj;

  sWant, sSkin : Double;

begin

  GetRadialProfiles(psFront, SF, F0, FE);
  GetRadialProfiles(psBack, SB, B0, BE);

  Say('');
  Say('================ TRUNK PROFILE, FRONT AND BACK ================');
  Say(Format('  %d points to the front and %d to the back, grouped by s and',
    [SF.Cols, SB.Cols]));
  Say('  taken within 15 degrees of straight up and of straight down.');
  Say('');
  Say('  boundary          s (mm)   front t=0    back t=0   front end    back end');

  Say(Format('  %-14s %8.2f %11.3f %11.3f %11.3f %11.3f',
    ['centre', 0.0, F0[0, 0], B0[0, 0], FE[0, 0], BE[0, 0]]));

  for l := FSegInner[SegTrunk] to NbLayers - 1 do
  begin

    sWant := FSLOuter[SegTrunk, l] * 1000;

    Say(Format('  %-14s %8.2f %11.3f %11.3f %11.3f %11.3f',
      [Layers[l].Name + ' out', sWant,
       At(SF, F0, sWant), At(SB, B0, sWant),
       At(SF, FE, sWant), At(SB, BE, sWant)]));

  end;

  sSkin := FSLOuter[SegTrunk, LayerSkin] * 1000;

  Say('');
  Say(Format('  The skin is %.2f K warmer at the back than at the front before the',
    [At(SB, B0, sSkin) - At(SF, F0, sSkin)]));
  Say(Format('  run starts, and %.2f K warmer at the end of it. That gap is the',
    [At(SB, BE, sSkin) - At(SF, FE, sSkin)]));
  Say('  cushion: the same tissue, the same generation, and an order of magnitude');
  Say('  between what the two of them are losing heat into.');

  if At(SB, B0, FSLOuter[SegTrunk, FSegInner[SegTrunk]] * 1000) > F0[0, 0] then
  begin
    Say('');
    Say('  Note that the back of the core runs warmer than the centre itself.');
    Say('  With the cushion under it the temperature maximum is displaced');
    Say('  backwards, so the geometric centre - which is what this model reports');
    Say('  as the core, and what the calibration holds at the set point - is no');
    Say('  longer the hottest point in the body.');
  end;

end;

{ Each segment at the start of the run and at its end: its centre, its
  skin front and back, and what it is losing. The whole-body columns of
  the history hide how differently the segments behave - a limb makes
  little heat for the surface it has, and no core of its own to keep it
  warm - so this is where that shows. }
procedure TThermalModel.ReportSegments;
var

  s, c : Integer;

  Front, Back : Double;

  Row : String;

begin

  Say('');
  Say('================ BY SEGMENT ================');
  Say('  Centre is the middle of the segment - the centre of the head, the');
  Say('  axis half way along a cylinder. Skin is area-weighted over the exposed');
  Say('  front and over the patch on the cushion.');

  if FCase = CaseGowned then
  begin
    Say('  Gown is the outer face of the cloth, area-weighted, on the segments');
    Say('  that wear it - the surface the room sees there, where "skin front"');
    Say('  is the skin beneath it.');
  end;

  Say('');

  if FCase = CaseGowned then
  begin
    Say('  segment        centre (C)      skin front (C)      skin back (C)         gown (C)    lost at end (W)');
    Say('                 t=0     end       t=0     end       t=0     end       t=0     end      total  via pad');
  end
  else
  begin
    Say('  segment        centre (C)      skin front (C)      skin back (C)    lost at end (W)');
    Say('                 t=0     end       t=0     end       t=0     end      total  via pad');
  end;

  for s := 0 to NbSegments - 1 do
  begin

    c := FSegCentreNode[s];

    SurfaceLosses(Radiating, Front, Back, s);

    Row := Format('  %-10s %7.2f %7.2f   %7.2f %7.2f   %7.2f %7.2f',
      [Segments[s].Name,
       FTInitial[c] - Kelvin, FEngine.Temperature[c] - Kelvin,
       MeanSkinTemperature(psFront, s, True) - Kelvin,
       MeanSkinTemperature(psFront, s) - Kelvin,
       MeanSkinTemperature(psBack, s, True) - Kelvin,
       MeanSkinTemperature(psBack, s) - Kelvin]);

    if FCase = CaseGowned then
    begin
      if FSegMeshAreaGown[s] > 0 then
        Row := Row + Format('   %7.2f %7.2f',
          [MeanGownTemperature(s, True) - Kelvin, MeanGownTemperature(s) - Kelvin])
      else
        Row := Row + Format('   %7s %7s', ['-', '-']);
    end;

    Say(Row + Format('   %8.1f %8.2f', [Front + Back, Back]));

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
  Say(Format('  Generation is %.1f W at the %.0f C set point and follows the core',
    [Gen, CoreSetPointC]));
  Say(Format('  from there at Q10 = %.1f, so it is a column here rather than a', [Q10]));
  Say('  constant. The core is the middle of the trunk. The skin columns are');
  Say('  the exposed front and the patch on the cushion over the whole body,');
  Say('  area-weighted, and "via pad" is the part of the loss that goes out');
  Say('  through the foam.');
  Say('');
  Say('    time    core   front    back    pool      gen      lost   via pad     stored  balance     perf');
  Say('   (min)     (C)     (C)     (C)     (C)      (W)       (W)       (W)        (W)      (W)      (W)');

  for i := 0 to FNbHist - 1 do
  begin

    if (i mod ReportEvery <> 0) and (i <> FNbHist - 1) then
      Continue;

    // Against the generation in force over that step, not the set-point
    // value - see PostProcess.
    Bal := FHistGen[i] - FHistLoss[i] - FHistStore[i];

    Say(Format('  %6.1f  %6.2f  %6.2f  %6.2f  %6.2f %8.1f %9.1f %9.2f  %9.1f %8.2f %8.3f',
      [FHistT[i] / 60, FHistCore[i], FHistSkin[i], FHistSkinB[i], FHistTArt[i],
       FHistGen[i], FHistLoss[i], FHistLossB[i], FHistStore[i], Bal,
       FHistPerf[i]]));

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

    if FCase = CaseGowned then
      Say(Format('  Gown, outer face %.2f C -> %.2f C  (the front skin above is the' +
        ' skin beneath it, and the bare head and legs)',
        [FHistGown[0], FHistGown[FNbHist - 1]]));

    Say(Format('  Generation %.1f W -> %.1f W  (%.0f%% of the set-point rate, by Q10)',
      [FHistGen[0], FHistGen[FNbHist - 1],
       100 * FHistGen[FNbHist - 1] / FHeatOutput]));

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

{ The temperature profile through the trunk from its centre outward, at
  t=0 and as it now stands, for the whole section or for the front or back
  of it alone.

  The trunk rather than any other segment because it is where the core is
  - the temperature the model reports, calibrates and scales generation
  by - and because its section, broad and flat, is the one the cushion
  makes most of. The coordinate is s, the semi-major axis of the similar
  ellipse through a node, and every compartment boundary is a level set
  of it.

  ONE curve is not the whole result. An insulated back and an exposed
  front break the section's symmetry, and the difference between the two
  is the effect being modelled, so the caller asks for a sector: psFront
  takes the nodes within ProfileHalfAngleDeg of straight up, psBack those
  within the same angle of straight down, and psAll everything, which is
  still the right thing to plot when the surface is uniform.

  Nodes near the centre belong to every sector: there is no front or
  back within a few millimetres of the middle, and dropping them would
  leave each curve starting nowhere in particular.

  Nodes are grouped by s rather than plotted raw. The fat's structured
  layers sit at a few exact values of s and must stay distinct, since
  the steepest gradient is across them; the unstructured core scatters
  its nodes over every s and needs averaging or the curve is a band
  rather than a line. Grouping to a tolerance well under a fat layer
  does both. Residual spread within a group is real - it is the
  section's departure from being one-dimensional in s - and
  VerifyAgainstAnalytic measures it. }

procedure TThermalModel.GetRadialProfiles(Sector : TProfileSector;
                                          out S, T0, TEnd : TVMobj);
const
  // Well under the thinnest structured layer's node spacing, in the
  // skin, so those stay resolved.
  GroupTol = 0.0002;

  // Inside the core the mesh is unstructured and coarse, so a 0.2 mm
  // band catches only a node or two, and once a sector is asked for it
  // catches a fraction of one. Since the field is genuinely
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
  Near := 2 * Segments[SegTrunk].MeshSize;

  // Index sort by s - insertion sort over an index array, which is
  // ample for a few thousand nodes and keeps the node data untouched.
  SetLength(Idx, FGmsh.NbNodes);

  n := 0;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    if FNodeSeg[i] <> SegTrunk then
      Continue;

    if (Sector = psAll) or (FNodeS[i] <= Near) then
      Take := True
    else
    begin

      Ang := ArcTan2((FEngine.CoordY[i] - FSegCy[SegTrunk]) / Segments[SegTrunk].Aspect,
                     FEngine.CoordX[i] - FSegCx[SegTrunk]);

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
    if FNodeS[Idx[i]] < FSLOuter[SegTrunk, FSegInner[SegTrunk]] - 2 * CoreGroupTol then
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

  Gown : String;

begin

  AssignFile(F, CsvName);
  SafeReWriteText(F);

  try

    // gown_C is the cloth's outer face in the gowned case, and empty
    // otherwise - not the skin again, which would read as a gown at
    // skin temperature.
    WriteLn(F, 'time_s,time_min,core_C,skin_front_C,skin_back_C,gown_C,generated_W,' +
               'lost_W,lost_pad_W,stored_W,balance_W');

    for i := 0 to FNbHist - 1 do
    begin

      if FCase = CaseGowned then
        Gown := Format('%.4f', [FHistGown[i]], DotFS)
      else
        Gown := '';

      WriteLn(F, Format('%.1f,%.4f,%.4f,%.4f,%.4f,%s,%.3f,%.3f,%.3f,%.3f,%.3f',
        [FHistT[i], FHistT[i] / 60, FHistCore[i], FHistSkin[i], FHistSkinB[i],
         Gown, FHistGen[i], FHistLoss[i], FHistLossB[i], FHistStore[i],
         FHistGen[i] - FHistLoss[i] - FHistStore[i]], DotFS));

    end;

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

  SetLength(FSnap[FNbSnap], FGmsh.NbNodes);

  for i := 0 to FGmsh.NbNodes - 1 do
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

  The parsed .pos format repeats every vertex coordinate of every element
  in every frame, so the series runs to tens of megabytes in Examples/Data.
  That is the price of the format, not of the model.

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

  The view opens looking straight down on the patient, head at the top,
  with a clipping plane slicing every segment lengthways a little above
  the cushion, so what faces the viewer is the inside of every segment -
  the compartments and the gradient through them - rather than an opaque
  skin. The plane is at the height of the lowest segment centre, the
  arms', which cuts through the arms' axes and through the head, trunk
  and legs well inside their cores. }
procedure TThermalModel.WriteViewScript(const FileName : String);
var

  F : TextFile;

  i, j, s : Integer;

  Lo, Hi, YCut : Double;

begin

  Lo := MaxDouble;
  Hi := -MaxDouble;

  for i := 0 to FNbSnap - 1 do
    for j := 0 to Length(FSnap[i]) - 1 do
    begin
      if FSnap[i][j] < Lo then Lo := FSnap[i][j];
      if FSnap[i][j] > Hi then Hi := FSnap[i][j];
    end;

  YCut := MaxDouble;

  for s := 0 to NbSegments - 1 do
    YCut := Min(YCut, FSegCy[s]);

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
    WriteLn(F, '  View[i].Clip = 1;        // clipping plane 0, below');
    WriteLn(F, 'EndFor');
    WriteLn(F);
    WriteLn(F, 'View[0].Visible = 1;');
    WriteLn(F);
    WriteLn(F, '// Slice every segment lengthways, keeping what lies below the plane');
    WriteLn(F, '// - the half resting on the cushion - so looking down on it shows');
    WriteLn(F, '// the cut face: every compartment of every segment and the gradient');
    WriteLn(F, '// through them, rather than an opaque skin. The plane is at the');
    WriteLn(F, '// height of the arms'' axes, the lowest segment centre, which cuts');
    WriteLn(F, '// the head, trunk and legs well inside their cores.');
    WriteLn(F, '//');
    WriteLn(F, '// ClipWholeElements matters. Left at 0 the clip is a plain OpenGL');
    WriteLn(F, '// one, which cuts through the drawn surfaces and leaves the solid');
    WriteLn(F, '// hollow - a shell seen from inside. At 1 whole elements are');
    WriteLn(F, '// dropped instead, so the faces the cut exposes are real element');
    WriteLn(F, '// faces and carry the field, at the price of a stepped edge one');
    WriteLn(F, '// element deep. Note also that a second plane would not narrow');
    WriteLn(F, '// this to a slab: gmsh keeps an element that satisfies ANY');
    WriteLn(F, '// enabled plane, so two planes here draw the whole body again.');
    WriteLn(F, '// Move it, or add more, under Tools > Clipping.');
    WriteLn(F, 'General.ClipWholeElements = 1;');
    WriteLn(F, 'General.Clip0A = 0;');
    WriteLn(F, 'General.Clip0B = -1;');
    WriteLn(F, 'General.Clip0C = 0;');
    WriteLn(F, 'General.Clip0D = ' + Num(YCut) + ';');
    WriteLn(F);
    WriteLn(F, '// Look straight down on the patient, head at the top of the window');
    WriteLn(F, '// and the patient''s left on the right, as if standing over them.');
    WriteLn(F, '// Checked by rendering: -90 about x alone looks UP from under the');
    WriteLn(F, '// table at the backs, and 90 about x alone puts the head at the');
    WriteLn(F, '// bottom. gmsh fits the view to the model''s cross-section rather');
    WriteLn(F, '// than to a two-metre body seen end on, so it is scaled down to fit.');
    WriteLn(F, 'General.Trackball = 0;');
    WriteLn(F, 'General.RotationX = 90;');
    WriteLn(F, 'General.RotationY = 180;');
    WriteLn(F, 'General.RotationZ = 0;');
    WriteLn(F, 'General.ScaleX = 0.35;');
    WriteLn(F, 'General.ScaleY = 0.35;');
    WriteLn(F, 'General.ScaleZ = 0.35;');
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

  s, g : Integer;

  TightestRatio, Ratio : Double;

begin

  Say('');
  Say('================ PERFUSION ================');

  if FCardiacOutput <= 0 then
  begin
    // Unreachable through Solve, which clamps to CardiacOutputMin - kept so
    // the report says something sensible if that floor is ever lowered.
    Say('  Cardiac output 0 L/min - no blood flowing.');
    Exit;
  end;

  Say(Format('  Cardiac output           : %8.2f L/min', [FCardiacOutput]));
  Say('');
  Say('  segment    compartment    flow        w      conductance   time constant');
  Say('                          (L/min)    (1/s)       (W/K)          (min)');

  TightestRatio := 0;

  for s := 0 to NbSegments - 1 do
    for g := 0 to NbLayers - 1 do
    begin

      if FSLMeshVol[s, g] <= 0 then
        Continue;

      Say(Format('  %-10s %-10s %8.3f  %9.3e %12.2f %13.1f',
        [Segments[s].Name, Layers[g].Name, FSLFlow[s, g], FSLW[s, g],
         FSLW[s, g] * BloodDensity * BloodCp * FSLMeshVol[s, g],
         FSLTau[s, g] / 60]));

      if FSLTau[s, g] > 0 then
      begin
        Ratio := TimeStep / FSLTau[s, g];
        if Ratio > TightestRatio then
          TightestRatio := Ratio;
      end;

    end;

  Say('');
  Say('  Before induction the flows were those fractions of these:');
  Say(Format('  core %.2f, muscle %.2f, fat %.2f, skin %.2f - the skin shut by',
    [PreInductionFlow[LayerCore], PreInductionFlow[LayerMuscle],
     PreInductionFlow[LayerFat], PreInductionFlow[LayerSkin]]));
  Say('  vasoconstriction, and opened at t = 0.');
  Say('');
  Say(Format('  Blood pool (Tart)        : %8.2f C', [FTArt - Kelvin]));
  Say(Format('  Net perfusion heat       : %8.3f W  (must be zero: the pool',
    [FPerfNet]));
  Say('                                       stores nothing, so what one');
  Say('                                       compartment gives another takes)');
  Say(Format('  Step / shortest tau      : %8.3f  (perfusion is implicit, so this',
    [TightestRatio]));
  Say('                                       is about accuracy, not stability)');

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

  // The flows fix the links to the blood pool, which are elements of the
  // model, so they have to be known before it is built.
  SetPerfusion(CardiacOutput);

  BuildModel;

  ReportSetup;

  (******************** BALANCED STARTING STATE ********************)

  // Solved WITH blood flowing, at the awake patient's flows: everywhere
  // but the skin, which the thermoregulatory vasoconstriction has shut -
  // see PreInductionFlow. Induction abolishes that tone, and the skin's
  // flow opening at t = 0, alongside the drapes coming off, is the
  // clinical sequence; redistribution is then something the run shows
  // rather than something assumed into the initial condition.
  //
  // Solving it without any blood at all, as this model once did, is not
  // an option with a body of real proportions. The trunk's core makes 45 W
  // in a section 33 cm across, and conduction alone cannot carry that out
  // at any sensible skin temperature: holding the core at the set point
  // took a drape coefficient of 54 W/m2K and left the front skin at 17 C.
  // The long thin cylinder the model began with hid that, by spreading the
  // same heat through a body only 23 cm across. Blood is what empties a
  // core, so blood has to be in the starting state.
  //
  // It can be, because the pool is part of the linear system - see
  // BuildModel - so a perfused steady state is one static solve, not an
  // iteration on the pool temperature.
  //
  // The closed-form check runs first, with the blood shut off, in the
  // uniform configuration it describes; the calibration then overwrites
  // that field with the one the run actually starts from.
  VerifyAgainstAnalytic;

  CalibrateDraped;

  SurfaceLosses(False, LossFront, LossBack);

  Say('');
  Say(Format('  Draped steady state: core %.2f C, skin %.2f C at the front and',
    [FEngine.Temperature[FCoreNode] - Kelvin, MeanSkinTemperature(psFront) - Kelvin]));
  Say(Format('  %.2f C on the cushion, losing %.1f W to the room and %.1f W through',
    [MeanSkinTemperature(psBack) - Kelvin, LossFront, LossBack]));
  Say(Format('  the foam, against %.1f W generated.', [FHeatOutput]));

  if FCase = CaseGowned then
    Say(Format('  The gown''s outer face sits at %.2f C, over skin at %.2f C beneath it.',
      [MeanGownTemperature - Kelvin,
       (MeanSkinTemperature(psFront, SegTrunk) * FSegMeshAreaGown[SegTrunk] +
        MeanSkinTemperature(psFront, SegArmL) * FSegMeshAreaGown[SegArmL] +
        MeanSkinTemperature(psFront, SegArmR) * FSegMeshAreaGown[SegArmR]) /
       FMeshAreaGown - Kelvin]));

  // Every node the engine has - the gown's included, when it is worn -
  // since the gown's own t = 0 temperature is reported too.
  SetLength(FTInitial, FEngine.NbNodes);

  for i := 0 to FEngine.NbNodes - 1 do
    FTInitial[i] := FEngine.Temperature[i];

  // Frame zero of the gmsh animation is this state - the balanced one
  // the run starts from, before either the drapes or the blood.
  FNbSnap := 0;

  TakeSnapshot(0);

  // The pool and its net heat as they stand in the balanced state, at the
  // flows that state was settled with - which is where the zero is owed.
  UpdateSources;

  ReportPerfusion;

  // Induction: every compartment's blood flow goes to its full share -
  // the skin's opening being the change - see the note above.
  SetBloodFlow([1.0, 1.0, 1.0, 1.0]);

  (******************** TRANSIENT ********************)

  // The drapes come off in every case but the held one; what is under
  // them - bare skin, or the gown over the trunk and arms - is already
  // in the model.
  if Radiating then
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

  ReportSegments;

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
