unit uThorax;

{ Airways, lungs, chest wall and the jet, for the HFJV model.

  THE CIRCUIT

  Lumped, and linear in its unknowns but for one term, the upper
  airway's turbulent loss (below). Pressures are relative to the
  atmosphere, volumes are displacements from the end-expiratory state,
  flows are positive towards the alveoli.

        jet Qj, dpj
            |
   atm --[R_ua, I_ua]-- p_t --[R_aw, I_aw]--(+dpj)-- p_A --- alveolar gas C_g
       upper airway   trachea   lower airways          |
                                                    lung tissue E_L, R_L
                                                       |
                                                     p_pl ---- rib cage  E_rc, R_rc, I_rc
                                                          \--- diaphragm + abdomen

   upper airway     I_ua Q_ua' = p_t - R_ua Q_ua - K_ua |Q_ua| Q_ua   (Q_ua out of the mouth)
   tracheal node    0 = Q_j - Q_ua - Q_aw                     (algebraic)
   lower airways    I_aw Q_aw' = p_t + dp_j - p_A - R_aw Q_aw
                    (dp_j = dp_on - R_j Q_s while the jet is on: below)
   alveolar gas     C_g p_A' = Q_aw - Q_L ,  Q_L = Q_rc + Q_di
   lung tissue      0 = p_A - p_pl - E_L V_L - R_L Q_L       (algebraic)
   rib cage         V_rc' = Q_rc ; I_rc Q_rc' = p_pl - E_rc V_rc - R_rc Q_rc
   diaphragm        lumped:  V_di' = Q_di ; I_di Q_di' = p_pl - E_di V_di - R_di Q_di
                    or FEM:  the diaphragm surface of a TAbdomenFluid, with
                             p_pl as its outside pressure and
                             Q_di = -sum w_i v_i (its outward normal is cranial)

  V_L = V_rc + V_di is the lung's volume change and the tidal volume its
  peak-to-peak swing. C_g = V_FRC / P_atm is the isothermal compliance of
  the alveolar gas, which shunts flow at high frequency.

  THE TURBULENT UPPER AIRWAY

  The larynx, pharynx and mouth lose pressure as Rohrer's
  R_ua Q + K_ua |Q| Q: a laminar part and a turbulent part growing with
  the flow, in either direction. The defaults, R_ua 1.0 cmH2O/(L/s) and
  K_ua 1.0 cmH2O/(L/s)^2, are assumed rather than measured: they give
  the 2.0 cmH2O/(L/s) of the earlier linear model at 1 L/s, the order of
  the flows through the upper airway here. K_ua = 0 is the linear model.

  THE GLOTTIS

  An orifice of area A_g in the same path - every litre entrained or
  breathed out goes through it, since the jet enters below it - losing

      dp = k_g rho |Q| Q / (2 A_g^2),

  with k_g = 1.37: the entry loss 0.37 and the whole exit kinetic energy
  1.0 of Ishizaka and Flanagan's glottal flow (1972), rho 1.2 kg/m3 for
  the oxygen and air at body temperature. It is in series, so its K adds
  to K_ua; A_g 0.8 cm2 gives 1.31 cmH2O/(L/s)^2. Its gas, rho L_g / A_g
  over the vocal folds' depth L_g (1 cm), adds to I_ua: 0.0015
  cmH2O s2/L. A_g = 0 leaves the glottis out.

  The K term is the system's only nonlinearity, and it is in one row and
  one unknown. It is not put into A: it enters as a forcing on the upper
  airway's row, b_ua = -K_ua |Q_ua| Q_ua (UASource), which the solvers
  (uHFJVSolve) find self-consistently - by harmonic balance on Q_ua
  alone, or exactly within each time step. Everything that is linear -
  impedances, the system's matrices - sees R_ua only, which is the
  small-signal resistance about zero flow.

  THE JET

  One of JetVent's six bench cannulae (demos/JetVent/uJetCalcVM.pas,
  TCatheter) at driving pressure DP, opened for the inspiratory fraction
  Ti of each cycle. Its flow Q_on does not depend on the patient's
  pressures, which are a few cmH2O against bar. Its momentum acts as a
  pressure rise dp_on towards the lungs, which is what entrains: it
  drives the lower-airway flow above Q_j and draws the difference in
  through the upper airway. The two are applied as square waves.

  With JetSource = jsMeasured (the default) both come from the bench:
    Q_on   the measured jet flow, linear between the 0.5 .. 3.5 bar
           points (outside them, Crane's calculated flow, flagged);
    dp_on  the measured stall pressure. A jet's momentum flux is spread
           over the airway's cross-section, so stall pressure goes as
           1/D^2: the 22 mm figure is scaled by (22/D_trachea)^2, or,
           where a 15 mm series exists (the Cook), interpolated in 1/D^2
           between the two.
  jsCalculated uses Crane's flow and the momentum formula
  rho Q^2/(A_jet A_trachea) instead, which JetFlow found 4-33 % off the
  bench depending on the cannula.

  THE JET PUMP'S CHARACTERISTIC (JetPump, default on). A jet pump's
  pressure rise falls as it entrains more: from the stall pressure at no
  entrained flow to nothing at its free entrainment. Taken as the line
  through those two points,

      dp_j = dp_on - R_j Q_s ,   R_j = dp_on / Q_free ,

  with Q_s = -Q_ua the gas entrained through the upper airway and Q_free
  the bench's open-air entrainment (total less jet flow) at the same
  driving pressure. Using the open-air figure as the zero-pressure end is
  an assumption: the bench gives no entrainment into a tube against no
  back pressure. Q_s < 0 (gas pushed out of the mouth while the jet is
  on) extends the line, a pressure rise above stall. Without bench
  entrainment (outside 0.5 - 3.5 bar) R_j is 0, the constant stall
  pressure of the earlier model, as is JetPump off.

  The R_j term is time-varying (only while the jet is on), so it is not
  put into A either. It sits in the lower airway's branch, but a
  pressure source can be moved through the tracheal node, whose only
  other branches are the upper airway and the jet's ideal flow source:
  in the upper airway's row it is -R_j Q_s = R_j Q_ua, an extra
  resistance R_j to the upper airway's flow while the jet is on, and the
  tracheal node's unknown then reads p_t + R_j Q_ua. So the solvers
  treat it as part of the upper airway's forcing (UASource), and take
  R_j Q_ua back off the tracheal pressure when they sample it.

  THE TISSUES: CONSTANT PHASE

  Lung tissue, rib cage and the lumped diaphragm resist deformation as
  viscoelastic tissue does (Hantos et al. 1992): with hysteresivity eta,
  the ratio of dissipation to elastic storage, their impedance is

      Z(w) = A (i w)^(-alpha),   alpha = (2/pi) atan(1/eta),

  so the resistance Re Z falls as w^-alpha and the dynamic elastance
  -w Im Z rises slowly, as w^(1-alpha). A is set so the elastance at
  FRef (0.25 Hz, quiet breathing) is the E of the parameters; the
  resistance there is eta E / (2 pi FRef). Default eta 0.15 for lung and
  chest wall (respiratory tissues lie at 0.1 - 0.2, Fredberg and
  Stamenovic 1989). For the lung: R 0.67 cmH2O/(L/s) at 0.25 Hz, 0.064 at
  200 /min; elastance 7.0 and 9.0 cmH2O/L. Eta = 0 gives the earlier
  constant R and E.

  A fractional power is not a finite system, but it is a positive
  spectrum of relaxations, (i w)^-alpha = (sin(alpha pi)/pi)
  int s^-alpha/(s + i w) ds, and a sum of those is: sampled at
  TissuePerDecade points a decade in ln s between TissueFMin and
  TissueFMax (1 mHz to 1 kHz), each is a dashpot R_k in series with a
  spring, R_k/(1 + i w tau_k), one extra unknown p_k with

      tau_k p_k' + p_k = R_k Q .

  The part of the spectrum below the range is a spring E_0 (the
  quasi-static elastance, 0.59 E), the part above a resistance R_inf.
  Every R_k, E_0 and R_inf is positive, so the bank is passive and works
  unchanged in the frequency and time domains. With 3 a decade it is
  within 3 % of the constant-phase Z from 0.1 to 500 Hz (18 unknowns a
  tissue). TissueZ gives the bank's impedance.

  WHAT IS LEFT OUT

  The lung is one compartment, with no pendelluft.
  Gas exchange is not modelled: VT/VD and f VT^2 (the CO2-elimination
  index of Slutsky and others) stand in for it. }

{$mode delphi}{$H+}

interface

uses SysUtils, Math, newVM, newVMsparse, uDescriptor, uAbdomenFluid, uJetCalcVM, uViscoelastic;

const
  cmH2O = 98.0665;      // Pa
  Litre = 1e-3;         // m3
  RUnit = cmH2O / Litre;            // cmH2O/(L/s) -> Pa s/m3
  EUnit = cmH2O / Litre;            // cmH2O/L     -> Pa/m3
  IUnit = cmH2O / Litre;            // cmH2O s2/L  -> Pa s2/m3
  PAtm = 101325.0;

type
  TJetSource = (jsMeasured, jsCalculated);

  { TTissue (uViscoelastic) here is in clinical units: cmH2O, L, s. }

  TTissueKind = (tkLung, tkRibCage, tkDiaphragm);

  { Everything in the clinical units of the literature: cmH2O, L, s. }
  TThoraxParams = record
    Raw, Iaw : Double;      // lower airways, below the jet
    Rua, Iua : Double;      // upper airway, above the jet to the mouth
    Kua : Double;           // its turbulent loss, cmH2O/(L/s)^2 (0: linear)
    GlottisArea : Double;   // cm2 (0: no glottis)
    GlottisDepth : Double;  // cm, for its inertance
    GlottisK : Double;      // loss coefficient on rho Q^2 / (2 A^2)
    GasRho : Double;        // kg/m3
    TracheaD : Double;      // m, for the jet's momentum
    EL, RL : Double;        // lung recoil and tissue resistance (RL only if EtaL = 0)
    VFRC : Double;          // L, end-expiratory lung volume
    Erc, Rrc, Irc : Double; // rib cage
    Edi, Rdi, Idi : Double; // diaphragm and abdomen, when lumped
    // constant-phase tissue: hysteresivity (0: the constant R above),
    // E taken as the elastance at FRef (Hz)
    EtaL, EtaCW : Double;   // lung; rib cage and lumped diaphragm
    FRef : Double;
    TissueFMin, TissueFMax : Double; // Hz, the relaxation bank's range
    TissuePerDecade : Integer;
    VD : Double;            // L, anatomical dead space below the jet
    // jet
    Cannula : TJetCath;
    JetSource : TJetSource;
    DrivingP : Double;      // bar gauge
    Freq : Double;          // Hz
    Ti : Double;            // inspiratory fraction of the cycle
    JetPump : Boolean;      // dp_j falls with entrained flow (see the header)
  end;

  TThorax = class
  private
    FFluid : TAbdomenFluid;
    FDiaSurf : Integer;
    FW : TDoubleArray;      // diaphragm weights, when FEM
    FCath : TCatheter;
    FTis : array[TTissueKind] of TTissue;
  public
    P : TThoraxParams;
    // dofs
    iQua, iPt, iQaw, iPA, iPpl, iVrc, iQrc, iVdi, iQdi : Integer;
    QOn, DpOn : Double;     // jet flow (m3/s) and momentum pressure (Pa) while open
    QOnCalc, DpOnCalc : Double; // Crane / momentum-formula values, for comparison
    QOnBench, DpOnBench : Double; // bench values (NaN outside 0.5 .. 3.5 bar)
    BenchEntrained : Double; // bench total (jet + entrained) flow, m3/s, NaN if outside
    JetSonic : Boolean;
    JetNote : String;       // which source was used, and why
    QFree : Double;         // bench open-air entrainment, m3/s (NaN outside the bench)
    RJet : Double;          // the jet pump's falloff dp_on / Q_free, Pa s/m3 (0: constant dp_on)

    constructor Create;
    destructor Destroy; override;
    { Adds the circuit to Sys. Fluid = nil: lumped diaphragm. Otherwise
      the diaphragm is surface DiaSurf of Fluid, which must already be in
      Sys. Call after setting P. }
    procedure AddToSystem(Sys : TDescriptorSystem; Fluid : TAbdomenFluid; DiaSurf : Integer);
    { Sets QOn and DpOn from the cannula and driving pressure. }
    procedure SetupJet;
    { Jet on at time t? (on for the first Ti of each cycle) }
    function JetOn(t : Double) : Boolean;
    { The forcing vector at time t. }
    function Forcing(Sys : TDescriptorSystem; t : Double) : TVMobj;
    { The unit forcing pattern: Q_j = 1 m3/s with dp_j = DpOn/QOn Pa
      per m3/s, i.e. the jet's shape scaled; Fourier amplitudes multiply it. }
    function ForcingPattern(Sys : TDescriptorSystem) : TVMobj;
    { The glottis's turbulent loss and inertance, Pa s2/m6 and Pa s2/m3. }
    function GlottisKSI : Double;
    function GlottisISI : Double;
    { The upper airway's whole turbulent coefficient, K_ua plus the
      glottis, Pa s2/m6, and its whole inertance, Pa s2/m3. }
    function KuaSI : Double;
    function IuaSI : Double;
    { The turbulent loss and the jet pump's falloff as a forcing on the
      upper airway's row, Pa, at flow Q (m3/s) with the jet on for the
      fraction On (0, 1, or 1/2 at an edge): -K_ua |Q| Q - On R_j Q. }
    function UASource(Q, On : Double) : Double;
    { Whether the upper airway's forcing is non-zero: K_ua > 0 or R_j > 0. }
    function UANonlinear : Boolean;
    { The tracheal pressure from the tracheal node's unknown pt (see the
      header): pt - On R_j Q_ua. }
    function TrachealP(pt, Qua, On : Double) : Double;
    { A unit forcing on the upper airway's row. }
    function UAPattern(Sys : TDescriptorSystem) : TVMobj;
    { Lung and diaphragm volume (m3) from a state vector. }
    function Vdi(const X : TVMobj) : Double;
    function VL(const X : TVMobj) : Double;
    function Qdi(const X : TVMobj) : Double;
    { The tissue's impedance, SI, at w (rad/s): the bank's, or with
      Exact the constant-phase one it approximates. No inertance. }
    procedure TissueZ(Kind : TTissueKind; w : Double; out Re, Im : Double; Exact : Boolean = False);
    { The tissue's resistance (cmH2O/(L/s)) and dynamic elastance
      (cmH2O/L) at f Hz, from the bank. }
    procedure TissueRE(Kind : TTissueKind; f : Double; out R, E : Double);
    property Cath : TCatheter read FCath;
  end;


function DefaultThoraxParams : TThoraxParams;

implementation

function DefaultThoraxParams : TThoraxParams;
begin
  with Result do
  begin
    // adult male, anaesthetised and paralysed, supine
    Raw := 1.5;  Iaw := 0.008;
    Rua := 1.0;  Iua := 0.012;
    Kua := 1.0;
    GlottisArea := 0.8;
    GlottisDepth := 1.0;
    GlottisK := 1.37;
    GasRho := 1.2;
    TracheaD := 0.018;
    EL := 7.0;   RL := 0.5;
    VFRC := 2.2;
    Erc := 10.0; Rrc := 0.5; Irc := 0.004;
    Edi := 8.0;  Rdi := 0.5; Idi := 0.02;
    EtaL := 0.15; EtaCW := 0.15; FRef := 0.25;
    TissueFMin := 1e-3; TissueFMax := 1e3; TissuePerDecade := 3;
    VD := 0.12;
    Cannula := Biro;
    JetSource := jsMeasured;
    // a typical setting: 2 bar gauge, 200 /min, I:E 1:1
    DrivingP := 2.0;
    Freq := 200 / 60;
    Ti := 0.5;
    JetPump := True;
  end;
end;

constructor TThorax.Create;
begin
  inherited Create;
  P := DefaultThoraxParams;
end;

destructor TThorax.Destroy;
begin
  FCath.Free;
  inherited Destroy;
end;

{ Linear interpolation of a bench series (1 x 7, at DrivingP); NaN
  outside 0.5 .. 3.5 bar. }
function Bench(const V : TVMobj; DP : Double) : Double;
var
  i : Integer;
  f : Double;
begin
  if (DP < DrivingP[0] - 1e-9) or (DP > DrivingP[NumPressures - 1] + 1e-9) then
    Exit(NaN);
  i := 0;
  while (i < NumPressures - 2) and (DP > DrivingP[i + 1]) do Inc(i);
  f := (DP - DrivingP[i]) / (DrivingP[i + 1] - DrivingP[i]);
  Result := V[0, i] + f * (V[0, i + 1] - V[0, i]);
end;

procedure TThorax.SetupJet;
var
  lpm, s22, s15, x, x15, x22 : Double;
  Has15 : Boolean;
  i : Integer;
begin
  FCath.Free;
  FCath := TCatheter.Create(P.Cannula);
  lpm := FCath.CalcFlow(P.DrivingP, JetSonic);
  QOnCalc := lpm / 60000;
  // momentum formula, Pa: rho Q^2 / (A_jet A_trachea)
  DpOnCalc := FCath.StallPressure(lpm, P.TracheaD) * 100;

  QOnBench := Bench(FCath.MeasuredFlow, P.DrivingP) / 60000;
  BenchEntrained := Bench(FCath.EntrainedFlow, P.DrivingP) / 60000;
  s22 := Bench(FCath.MeasuredStall22, P.DrivingP);
  Has15 := False;
  for i := 0 to NumPressures - 1 do
    if FCath.MeasuredStall15[0, i] > 0 then Has15 := True;
  x := 1 / Sqr(P.TracheaD);
  x22 := 1 / Sqr(0.022);
  if Has15 then
  begin
    s15 := Bench(FCath.MeasuredStall15, P.DrivingP);
    x15 := 1 / Sqr(0.015);
    DpOnBench := (s22 + (s15 - s22) * (x - x22) / (x15 - x22)) * cmH2O;
  end
  else
    DpOnBench := s22 * (x / x22) * cmH2O;

  if (P.JetSource = jsMeasured) and not IsNan(QOnBench) then
  begin
    QOn := QOnBench;
    DpOn := DpOnBench;
    if Has15 then
      JetNote := 'bench flow; bench stall pressure interpolated in 1/D^2 between 15 and 22 mm'
    else
      JetNote := Format('bench flow; bench stall pressure into 22 mm scaled by (22/%.0f)^2',
        [1000 * P.TracheaD]);
  end
  else
  begin
    QOn := QOnCalc;
    DpOn := DpOnCalc;
    if P.JetSource = jsMeasured then
      JetNote := 'CALCULATED (Crane, momentum formula): driving pressure outside the bench''s 0.5 - 3.5 bar'
    else
      JetNote := 'calculated (Crane flow, momentum formula)';
  end;
  // the pump's characteristic, through stall and the open-air entrainment
  QFree := BenchEntrained - QOnBench;
  if P.JetPump and not IsNan(QFree) and (QFree > 0) and (DpOn > 0) then
    RJet := DpOn / QFree
  else
    RJet := 0;
end;

procedure TThorax.AddToSystem(Sys : TDescriptorSystem; Fluid : TAbdomenFluid; DiaSurf : Integer);
var
  b, k, pk : Integer;

  procedure Lumped(iV, iQ : Integer; const T : TTissue; I : Double);
  var
    k, pk : Integer;
  begin
    Sys.AddE(iV, iV, 1);  Sys.AddA(iV, iQ, 1);
    Sys.AddE(iQ, iQ, I * IUnit);
    Sys.AddA(iQ, iPpl, 1);
    Sys.AddA(iQ, iV, -T.E0 * EUnit);
    Sys.AddA(iQ, iQ, -T.Rinf * RUnit);
    // relaxations: tau_k p_k' + p_k = R_k Q, each p_k opposing
    for k := 0 to High(T.R) do
    begin
      pk := Sys.NewDofs(1);
      Sys.AddE(pk, pk, T.Tau[k]);
      Sys.AddA(pk, pk, -1);
      Sys.AddA(pk, iQ, T.R[k] * RUnit);
      Sys.AddA(iQ, pk, -1);
    end;
  end;

  // adds coef * Q_L to row r of A (Q_L = Q_rc + Q_di)
  procedure AddQL(r : Integer; coef : Double);
  var
    k : Integer;
  begin
    Sys.AddA(r, iQrc, coef);
    if FFluid = nil then
      Sys.AddA(r, iQdi, coef)
    else
      for k := 0 to High(FW) do
        if FW[k] <> 0 then Sys.AddA(r, FFluid.VBase + k, -coef * FW[k]);
  end;

  procedure AddVL(r : Integer; coef : Double);
  var
    k : Integer;
  begin
    Sys.AddA(r, iVrc, coef);
    if FFluid = nil then
      Sys.AddA(r, iVdi, coef)
    else
      for k := 0 to High(FW) do
        if FW[k] <> 0 then Sys.AddA(r, FFluid.EtaBase + k, -coef * FW[k]);
  end;

begin
  Assert((P.Kua >= 0) and (P.GlottisArea >= 0), 'TThorax : K_ua and the glottis''s area must not be negative');
  Assert((P.Iua > 0) and (P.Iaw > 0) and (P.Irc > 0),
    'TThorax : inertances must be positive (they make the flows differential)');
  FFluid := Fluid;
  FDiaSurf := DiaSurf;
  if FFluid <> nil then FW := FFluid.SurfaceWeights(DiaSurf) else FW := nil;
  SetupJet;
  FTis[tkLung] := MakeTissue(P.EL, P.RL, P.EtaL, P.FRef, P.TissueFMin, P.TissueFMax, P.TissuePerDecade);
  FTis[tkRibCage] := MakeTissue(P.Erc, P.Rrc, P.EtaCW, P.FRef, P.TissueFMin, P.TissueFMax, P.TissuePerDecade);
  FTis[tkDiaphragm] := MakeTissue(P.Edi, P.Rdi, P.EtaCW, P.FRef, P.TissueFMin, P.TissueFMax, P.TissuePerDecade);

  b := Sys.NewDofs(7);
  iQua := b; iPt := b + 1; iQaw := b + 2; iPA := b + 3; iPpl := b + 4;
  iVrc := b + 5; iQrc := b + 6;
  if FFluid = nil then
  begin
    b := Sys.NewDofs(2);
    iVdi := b; iQdi := b + 1;
  end
  else
  begin
    iVdi := -1; iQdi := -1;
  end;

  // upper airway
  Sys.AddE(iQua, iQua, IuaSI);
  Sys.AddA(iQua, iPt, 1);
  Sys.AddA(iQua, iQua, -P.Rua * RUnit);
  // tracheal node (b = Q_j)
  Sys.SetAlgebraic(iPt);
  Sys.AddA(iPt, iQua, -1);
  Sys.AddA(iPt, iQaw, -1);
  // lower airways (b = dp_j)
  Sys.AddE(iQaw, iQaw, P.Iaw * IUnit);
  Sys.AddA(iQaw, iPt, 1);
  Sys.AddA(iQaw, iPA, -1);
  Sys.AddA(iQaw, iQaw, -P.Raw * RUnit);
  // alveolar gas
  Sys.AddE(iPA, iPA, P.VFRC * Litre / PAtm);
  Sys.AddA(iPA, iQaw, 1);
  AddQL(iPA, -1);
  // lung tissue: 0 = p_A - p_pl - E_0 V_L - R_inf Q_L - sum p_k
  Sys.SetAlgebraic(iPpl);
  Sys.AddA(iPpl, iPA, 1);
  Sys.AddA(iPpl, iPpl, -1);
  AddVL(iPpl, -FTis[tkLung].E0 * EUnit);
  AddQL(iPpl, -FTis[tkLung].Rinf * RUnit);
  for k := 0 to High(FTis[tkLung].R) do
  begin
    pk := Sys.NewDofs(1);
    Sys.AddE(pk, pk, FTis[tkLung].Tau[k]);
    Sys.AddA(pk, pk, -1);
    AddQL(pk, FTis[tkLung].R[k] * RUnit);
    Sys.AddA(iPpl, pk, -1);
  end;
  // rib cage and (lumped) diaphragm
  Lumped(iVrc, iQrc, FTis[tkRibCage], P.Irc);
  if FFluid = nil then
    Lumped(iVdi, iQdi, FTis[tkDiaphragm], P.Idi)
  else
    FFluid.CouplePressure(Sys, DiaSurf, iPpl);
end;

procedure TThorax.TissueZ(Kind : TTissueKind; w : Double; out Re, Im : Double; Exact : Boolean);
begin
  TissueImpedance(FTis[Kind], w, Re, Im, Exact);
  Re := Re * RUnit; Im := Im * RUnit;
end;

procedure TThorax.TissueRE(Kind : TTissueKind; f : Double; out R, E : Double);
var
  w, re, im : Double;
begin
  w := 2 * Pi * f;
  TissueZ(Kind, w, re, im);
  R := re / RUnit;
  E := -w * im / RUnit;
end;

function TThorax.JetOn(t : Double) : Boolean;
var
  ph : Double;
begin
  ph := Frac(t * P.Freq);
  if ph < 0 then ph := ph + 1;
  Result := ph < P.Ti;
end;

function TThorax.Forcing(Sys : TDescriptorSystem; t : Double) : TVMobj;
begin
  Result := TVMobj.Create(Sys.N, 1);
  if JetOn(t) then
  begin
    Result.DataPtr[iPt] := QOn;
    Result.DataPtr[iQaw] := DpOn;
  end;
end;

function TThorax.ForcingPattern(Sys : TDescriptorSystem) : TVMobj;
begin
  Result := TVMobj.Create(Sys.N, 1);
  Result.DataPtr[iPt] := QOn;
  Result.DataPtr[iQaw] := DpOn;
end;

function TThorax.GlottisKSI : Double;
begin
  if P.GlottisArea <= 0 then Exit(0);
  Result := P.GlottisK * P.GasRho / (2 * Sqr(P.GlottisArea * 1e-4));
end;

function TThorax.GlottisISI : Double;
begin
  if P.GlottisArea <= 0 then Exit(0);
  Result := P.GasRho * P.GlottisDepth * 1e-2 / (P.GlottisArea * 1e-4);
end;

function TThorax.KuaSI : Double;
begin
  Result := P.Kua * cmH2O / Sqr(Litre) + GlottisKSI;
end;

function TThorax.IuaSI : Double;
begin
  Result := P.Iua * IUnit + GlottisISI;
end;

function TThorax.UASource(Q, On : Double) : Double;
begin
  Result := -KuaSI * Abs(Q) * Q - On * RJet * Q;
end;

function TThorax.UANonlinear : Boolean;
begin
  Result := (KuaSI > 0) or (RJet > 0);
end;

function TThorax.TrachealP(pt, Qua, On : Double) : Double;
begin
  Result := pt - On * RJet * Qua;
end;

function TThorax.UAPattern(Sys : TDescriptorSystem) : TVMobj;
begin
  Result := TVMobj.Create(Sys.N, 1);
  Result.DataPtr[iQua] := 1;
end;

function TThorax.Vdi(const X : TVMobj) : Double;
var
  k : Integer;
begin
  if FFluid = nil then Exit(X.DataPtr[iVdi]);
  Result := 0;
  for k := 0 to High(FW) do
    Result := Result - FW[k] * X.DataPtr[FFluid.EtaBase + k];
end;

function TThorax.Qdi(const X : TVMobj) : Double;
var
  k : Integer;
begin
  if FFluid = nil then Exit(X.DataPtr[iQdi]);
  Result := 0;
  for k := 0 to High(FW) do
    Result := Result - FW[k] * X.DataPtr[FFluid.VBase + k];
end;

function TThorax.VL(const X : TVMobj) : Double;
begin
  Result := X.DataPtr[iVrc] + Vdi(X);
end;

end.
