unit uJetCalcVM;

{*******************************************************************************

     Jet cannula flow calculations - the newVM / newPolymath port of the
     Delphi uJetCalc.pas (kept alongside, unchanged, for reference).

     WHAT IS KEPT FROM THE ORIGINAL

     TCatheter: a named cannula with its length, bore, and the measured
     data taken on the bench at the seven driving pressures in DrivingP
     (0.5 .. 3.5 bar gauge) - jet flow, total (entrained) flow, and the
     stall pressures into 15 mm and 22 mm circuits. The measured vectors
     are now TVMobj row vectors (1 x NumPressures) rather than MtxVec
     Vectors.

     CalcFlow: the Darcy-Weisbach / Crane 3-20 estimate of jet flow from
     driving pressure, unchanged in substance - friction factor from the
     Moody formula at a Reynolds number taken at 342 m/s, K = inlet +
     f L/D + outlet, choking decided against the critical pressure ratio,
     and Crane's compressible-flow formula with the net expansion factor Y.
     The two Crane A-22 tables (critical pressure ratio and Y against K,
     for gamma = 1.4) were interpolated by a MtxVec PolyFit/PolyEval
     cubic in K. That cubic was a poor interpolant where the cannulas
     sit (K 2 - 7): the critical ratio up to 0.045 off the table, e.g.
     0.715 at K = 6.6 where the table gives 0.745. A higher order in K
     does not cure it - the table has only two points above K = 20, and
     a 5th-order fit swings to 8 (7th order: 650) between K = 40 and 100.
     The fit is now a cubic in ln K (TPolynomial.Fit, fitted once, lazily),
     within 0.003 of the table's ln-K interpolation below K = 20 and 0.006
     everywhere, with K clamped to the table's 1.2 .. 100.

     WHAT IS CORRECTED: THE MACH NUMBER

     The original took Mach = (Q / A) / 342: the volumetric flow at room
     conditions divided by the bore area, over a fixed speed of sound.
     Three things are wrong with that for a jet:

       1. The gas leaving the cannula is not at room density. The flow
          meter reads litres per minute at ambient pressure and
          temperature, so Q/A is the velocity the gas WOULD have at
          ambient density; at the exit it is colder (and, if choked,
          denser - still above ambient pressure), so the true exit
          velocity is the mass flow over the exit density and area.
       2. The speed of sound depends on temperature, a = sqrt(gamma R T),
          and the exit temperature is well below room temperature:
          accelerating the gas to several hundred m/s takes the enthalpy
          out of it, T = T0 - V^2 / (2 cp) (adiabatic, friction or not -
          Fanno flow conserves stagnation temperature).
       3. 342 m/s is roughly air at room temperature; for oxygen at
          293 K it is about 326 m/s, and at a choked exit about 298 m/s.

     ExitState therefore works from the mass flow m = rho_amb * Q and
     the exit conditions, in oxygen with gamma = 1.4 and R = 259.8
     J/(kg K):

       unchoked: the exit pressure is ambient, so rho_e = p_amb/(R T_e),
                 and with G = m/A continuity gives V = G R T_e / p_amb
                 while energy gives T_e = T0 - V^2/(2 cp). Eliminating
                 T_e leaves a quadratic in V with one positive root -
                 solved in closed form - then M = V / sqrt(gamma R T_e).
       choked:   if that M comes out >= 1 the exit is sonic (a constant-
                 bore cannula cannot pass M = 1 at its exit; the extra
                 expansion happens in the free jet outside). Then M = 1,
                 T_e = T0 * (T/Tt at M=1) from NACA 1135 Eq43, V = a_e,
                 rho_e = G / V, and p_e = rho_e R T_e, which comes out
                 above ambient - the under-expanded jet.

     So the Mach plot now saturates at 1, where the old one went on
     climbing past it, and the new "exit velocity" option shows V_e
     against the old Q/A for comparison. Everything else uses the
     ambient-density velocity exactly as the original did (the stall
     pressure in particular is the original's formula), since those were
     not in question.

     THE FREE JET (FreeJet)

     A choked exit is under-expanded: its static pressure is above
     ambient, and the jet goes on expanding outside the cannula, through
     M = 1 to supersonic. FreeJet gives the ideally expanded state,
     isentropic from the exit's stagnation pressure p0e = p_e / (p/pt at
     M = 1, NACA 1135 Eq44) down to ambient:
       M_j = sqrt(2/(gamma-1) * ((p0e/p_amb)^((gamma-1)/gamma) - 1)),
       T_j = T0 * (T/Tt at M_j, Eq43).
     That is the highest Mach number and lowest temperature in the jet;
     an unchoked jet's are its exit values. A real under-expanded jet
     overshoots in its shock cells, so its pressure dips below ambient
     and its Mach number above M_j for a short way - not modelled.

     THRUST

     Thrust is the exit-plane momentum flux plus the pressure thrust of
     an under-expanded exit: F = m V_e + (p_e - p_amb) A. Unchoked, p_e is
     ambient and only m V_e remains.

     CUSTOM CANNULAE

     CreateCustom builds a TCatheter of any length and bore, with no
     measured data, for the JetFlow calculator (demos/JetFlow): straight,
     with the metal cannulas' inlet loss of 1.0. ResistanceK and the
     CalcFlow overload with Sonic expose the Crane resistance coefficient
     and choking test inside CalcFlow.

     BENDS

     The original allowed for the Lindholm cannula's 45 degree bend by
     lengthening it (9.5 cm). The bend now has its own loss: BendExcessK
     adds Rennels & Hudson's smooth-bend coefficient (Pipe Flow, 2012,
     eq 10.3),
       K_b = f a r/d + (0.10 + 2.4 f) sin(a/2)
             + 6.6 f (sqrt(sin(a/2)) + sin(a/2)) / (r/d)^(4a/pi),
     less its first term f a r/d - the friction of the bend's arc, which
     the f L/D term already counts when Length is the cannula's whole
     centreline length, bend included. a is the bend angle (radians), r
     its centreline radius, d the bore, f the same Darcy friction factor
     as the straight run.

     INLET LOSS

     The original used an entry loss of 0.5 for every cannula. InletK is
     now per cannula: 1.0 for the metal ones (Lindholm, Cook, Biro), whose
     Luer fitting steps abruptly into the bore, and 0.5 for the Venflons,
     whose hubs taper into the cannula. The bores are as measured.

     MASS FLOW

     The original's "Mass flow kg/s x 1000" option actually computed
     DP - 0.5 rho V^2 / 1 bar - the driving pressure less a dynamic
     pressure, in bar - which is not a mass flow. MassFlow here is what
     the label says: rho_amb * Q in g/s (kg/s x 1000).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, newVM, newPolymath, naca1135;

const
  NumPressures = 7;
  DrivingP: array[0..NumPressures - 1] of Double = (0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5);  // bar gauge

  One_Bar = 101325.0;           // Pa, also taken as ambient pressure
  R_Temp = 293.0;               // K, room (stagnation) temperature
  Gamma_O2 = 1.4;
  R_O2 = 8314.46 / 32.0;        // J/(kg K), specific gas constant of O2
  Cp_O2 = Gamma_O2 * R_O2 / (Gamma_O2 - 1.0);
  O2_Density_RT = One_Bar / (R_O2 * R_Temp);   // 1.331 kg/m^3, as the original's constant
  O2_dyn_Viscosity_RT = 20.27e-6;              // Pa s
  S_GOxygen = 1.1044;           // specific gravity relative to air, for Crane

type
  TJetCath = (Lindholm, Cook, Biro, IV_14, IV_16, IV_18);

  { Exit conditions for one jet flow - see ExitState }
  TExitState = record
    MassFlow: Double;     // kg/s
    Velocity: Double;     // m/s, true exit velocity
    Mach: Double;         // <= 1
    Temperature: Double;  // K
    Density: Double;      // kg/m^3
    Pressure: Double;     // Pa, exit static pressure (> ambient when choked)
    Choked: Boolean;
  end;

  { The jet after expanding to ambient pressure - see FreeJet }
  TFreeJetState = record
    Mach: Double;         // highest in the jet (> 1 if the exit is choked)
    Temperature: Double;  // K, lowest in the jet
    Velocity: Double;     // m/s
    Pressure: Double;     // Pa, ambient
    ExitStagPressure: Double;  // Pa, stagnation pressure at the exit
  end;

  TCatheter = class
  private
    procedure SetGeometry(ALength, ADiameter: Double);
  public
    Name: string;
    Length, Diameter, Radius, Area: Double;    // Length along the centreline, bends included
    BendDeg, BendRD: Double;                     // bend angle (0 = straight) and radius / bore
    InletK: Double;                              // entry loss at the hub
    Reynolds_342: Integer;
    MeasuredFlow, EntrainedFlow: TVMobj;                       // l/min, 1 x NumPressures
    MeasuredStallFlow, MeasuredStall22, MeasuredStall15: TVMobj; // l/min; cmH2O; cmH2O
    constructor Create(Cath_Type: TJetCath);
    { any length and bore (m), no measured data }
    constructor CreateCustom(const AName: string; ALength, ADiameter: Double);

    { Crane resistance coefficient: InletK + f L/D + bend excess + outlet }
    function ResistanceK: Double;

    { scalar, one driving pressure (bar gauge) -> jet flow l/min }
    function CalcFlow(DP: Double): Double; overload;
    { the same, with Crane's verdict: Sonic when the pressure ratio
      reaches the critical one }
    function CalcFlow(DP: Double; out Sonic: Boolean): Double; overload;
    { the bend's loss beyond the friction of its arc - see the unit comment }
    function BendExcessK: Double;
    { the same over a vector of driving pressures }
    function CalcFlows(const DP: TVMobj): TVMobj;

    { velocity at ambient density, Q/A - the original's definition }
    function Velocity(const Flow: TVMobj): TVMobj;
    { exit conditions from the mass flow, see the unit comment }
    function ExitState(FlowLpm: Double): TExitState;
    function Mach(const Flow: TVMobj): TVMobj;
    function ExitVelocity(const Flow: TVMobj): TVMobj;
    { stall pressure (cmH2O) jetting into a circuit of bore D (m) - original formula }
    function Stall(const Flow: TVMobj; D: Double): TVMobj;
    { the same for one flow (l/min) }
    function StallPressure(FlowLpm, D: Double): Double;
    { rho_amb * Q, in g/s }
    function MassFlow(const Flow: TVMobj): TVMobj;
    { jet thrust (N) from an exit state, see the unit comment }
    function Thrust(const E: TExitState): Double;
  end;

{ Crane A-22 for gamma = 1.4: critical pressure ratio and net expansion
  factor Y against the resistance coefficient K - cubic fits to the table }
function CalcCritPRatio(k: Double; out Y: Double): Double;

function DrivingPressures: TVMobj;

{ the ideally expanded jet from an exit state }
function FreeJet(const E: TExitState): TFreeJetState;

implementation

const
  JetString: array[TJetCath] of string =
    ('Lindholm', 'Cook', 'Biro', '14G Venflon', '16G Venflon', '18G Venflon');

var
  CraneFitted: Boolean = False;
  CraneDP, CraneY: TPolynomial;

function DrivingPressures: TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(1, NumPressures);
  for i := 0 to NumPressures - 1 do
    Result[0, i] := DrivingP[i];
end;

procedure FitCrane;
var
  tabK, tabDP, tabY: TVMobj;
begin
  tabK  := TVMobj.Create(1, 12, [1.2, 1.5, 2.0, 3, 4, 6, 8, 10, 15, 20, 40, 100]);
  tabDP := TVMobj.Create(1, 12, [0.552, 0.576, 0.612, 0.662, 0.697, 0.737, 0.762, 0.784, 0.818, 0.839, 0.883, 0.926]);
  tabY  := TVMobj.Create(1, 12, [0.588, 0.606, 0.622, 0.639, 0.649, 0.671, 0.685, 0.695, 0.702, 0.710, 0.710, 0.710]);
  tabK := Ln(tabK);
  CraneDP := TPolynomial.Fit(tabK, tabDP, 3);
  CraneY  := TPolynomial.Fit(tabK, tabY, 3);
  CraneFitted := True;
end;

function CalcCritPRatio(k: Double; out Y: Double): Double;
begin
  if not CraneFitted then
    FitCrane;
  k := Ln(EnsureRange(k, 1.2, 100.0));
  Y := CraneY.Evaluate(k);
  Result := CraneDP.Evaluate(k);
end;

{ Moody friction factor, the omnicalc form of the original }
function MoodyF(Hyd_Diam, Reynolds, Surf_Roughness: Double): Double;
begin
  Result := 0.0055 * (1 + Power((2e4 * Surf_Roughness / Hyd_Diam) + (1e6 / Reynolds), 1 / 3));
end;

{ TCatheter }

constructor TCatheter.Create(Cath_Type: TJetCath);
begin
  InletK := 1.0;   // metal cannulas: the Luer fitting steps abruptly into the bore
  case Cath_Type of
    Lindholm:
      begin
        Length := 11.0e-2;  // overall, along the centreline
        Diameter := 2.0e-3;
        BendDeg := 45;
        BendRD := 2.0;      // ASSUMED: bend radius 4 mm, not measured
        MeasuredFlow      := TVMobj.Create(1, 7, [18.3, 30.8, 40.9, 50.7, 59.6, 68.4, 79.0]);
        EntrainedFlow     := TVMobj.Create(1, 7, [40, 66, 88, 113, 133, 150, 166]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [16, 27, 38, 46, 63, 72, 82]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 8, 11, 15, 21, 26, 30]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    Cook:
      begin
        Length := 7.5e-2;
        Diameter := 1.8e-3;
        MeasuredFlow      := TVMobj.Create(1, 7, [18.3, 30.8, 40.9, 50.7, 59.6, 68.4, 79.0]);
        EntrainedFlow     := TVMobj.Create(1, 7, [40, 66, 88, 113, 133, 150, 166]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [16, 27, 38, 46, 63, 72, 82]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 8, 11, 15, 21, 26, 30]);
        MeasuredStall15   := TVMobj.Create(1, 7, [4, 7, 24, 35, 47, 60, 75]);
      end;
    Biro:
      begin
        Length := 4e-1;
        Diameter := 2e-3;
        MeasuredFlow      := TVMobj.Create(1, 7, [15.75, 26.4, 36.2, 45.0, 53.3, 61.0, 69.7]);
        EntrainedFlow     := TVMobj.Create(1, 7, [25, 46, 63, 80, 95, 109, 125]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [15, 26, 36, 46, 58, 67, 78]);
        MeasuredStall22   := TVMobj.Create(1, 7, [1, 3, 4, 7, 10, 12, 15]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    IV_14:
      begin
        Length := 45e-3;
        Diameter := 1.5e-3;   // measured
        InletK := 0.5;   // the hub tapers smoothly into the cannula
        MeasuredFlow      := TVMobj.Create(1, 7, [14.4, 23.75, 31.6, 38.4, 44.7, 51.2, 57.6]);
        EntrainedFlow     := TVMobj.Create(1, 7, [37.7, 64, 80.7, 97, 111, 122, 134]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [14, 23, 31, 40, 47, 55, 64]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 4, 7, 10, 12, 15, 19]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    IV_16:
      begin
        Length := 45e-3;
        Diameter := 1.35e-3;   // measured
        InletK := 0.5;   // the hub tapers smoothly into the cannula
        MeasuredFlow      := TVMobj.Create(1, 7, [13.36, 20.62, 27.8, 33.9, 39.6, 45.7, 50.7]);
        EntrainedFlow     := TVMobj.Create(1, 7, [33, 57, 76, 88, 102, 112, 122]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [11, 20, 28, 34, 41, 47, 52]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 4, 7, 10, 13, 16, 19]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    IV_18:
      begin
        Length := 45e-3;
        Diameter := 0.9e-3;   // measured
        InletK := 0.5;   // the hub tapers smoothly into the cannula
        MeasuredFlow      := TVMobj.Create(1, 7, [7.0, 10.8, 14.3, 17.24, 20.28, 23.3, 26.38]);
        EntrainedFlow     := TVMobj.Create(1, 7, [28.7, 43.5, 54, 65, 66, 71, 79]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [5.6, 8.5, 11.8, 14.6, 16, 20, 22]);
        MeasuredStall22   := TVMobj.Create(1, 7, [1, 2, 4, 5, 6, 7, 9]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
  end;
  Name := JetString[Cath_Type];
  SetGeometry(Length, Diameter);
end;

constructor TCatheter.CreateCustom(const AName: string; ALength, ADiameter: Double);
begin
  Name := AName;
  InletK := 1.0;
  SetGeometry(ALength, ADiameter);
end;

procedure TCatheter.SetGeometry(ALength, ADiameter: Double);
begin
  Length := ALength;
  Diameter := ADiameter;
  Radius := Diameter / 2;
  Area := Pi * Sqr(Radius);
  Reynolds_342 := Round(342 * Diameter * O2_Density_RT / O2_dyn_Viscosity_RT);
end;

const
  k_outlet = 1.0;
  Roughness = 1e-6;

function TCatheter.BendExcessK: Double;
var
  f, a, s: Double;
begin
  if BendDeg <= 0 then
    Exit(0);
  f := MoodyF(Diameter, Reynolds_342, Roughness);
  a := DegToRad(BendDeg);
  s := Sin(a / 2);
  Result := (0.10 + 2.4 * f) * s + 6.6 * f * (Sqrt(s) + s) / Power(BendRD, 4 * a / Pi);
end;

function TCatheter.ResistanceK: Double;
begin
  Result := InletK + MoodyF(Diameter, Reynolds_342, Roughness) * Length / Diameter
            + BendExcessK + k_outlet;
end;

function TCatheter.CalcFlow(DP: Double): Double;
var
  Sonic: Boolean;
begin
  Result := CalcFlow(DP, Sonic);
end;

function TCatheter.CalcFlow(DP: Double; out Sonic: Boolean): Double;
// Jet flow from the Darcy-Weisbach equation, Crane 3-20 - as the original
var
  kactual, Y, surd: Double;
  DPAbs, PRatio, CritP, Actual_DP: Double;
begin
  DPAbs := DP + 1;
  PRatio := DP / DPAbs;
  kactual := ResistanceK;
  CritP := CalcCritPRatio(kactual, Y);   // is the flow choked?
  Sonic := PRatio >= CritP;
  if Sonic then Actual_DP := CritP * DPAbs else Actual_DP := DP;
  // Darcy-Weisbach / Crane
  surd := Sqrt(Actual_DP * DPAbs / (R_Temp * kactual * S_GOxygen));
  Result := 1000 * surd * Y * 0.3217 * Sqr(Diameter * 1000);
end;

function TCatheter.CalcFlows(const DP: TVMobj): TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(DP.Rows, DP.Cols);
  for i := 0 to DP.Cols - 1 do
    Result[0, i] := CalcFlow(DP[0, i]);
end;

function TCatheter.Velocity(const Flow: TVMobj): TVMobj;
begin
  Result := Flow * (1.0 / (60000 * Area));   // l/min -> m^3/s over the bore
end;

function TCatheter.ExitState(FlowLpm: Double): TExitState;
var
  G, a, c, V, Te: Double;
begin
  Result.MassFlow := O2_Density_RT * FlowLpm / 60000;   // kg/s
  G := Result.MassFlow / Area;                          // kg/(m^2 s)
  Result.Choked := False;

  if G <= 0 then
  begin
    Result.Velocity := 0; Result.Mach := 0; Result.Temperature := R_Temp;
    Result.Density := O2_Density_RT; Result.Pressure := One_Bar;
    Exit;
  end;

  // Unchoked trial, exit at ambient pressure. Continuity V = G R Te / p and
  // energy Te = T0 - V^2/(2 cp) combine to  a V^2 + V - c = 0  with
  // a = G R / (2 cp p), c = G R T0 / p; the positive root is V.
  a := G * R_O2 / (2 * Cp_O2 * One_Bar);
  c := G * R_O2 * R_Temp / One_Bar;
  V := (-1 + Sqrt(1 + 4 * a * c)) / (2 * a);
  Te := R_Temp - Sqr(V) / (2 * Cp_O2);
  Result.Mach := V / Sqrt(Gamma_O2 * R_O2 * Te);

  if Result.Mach >= 1.0 then
  begin
    // choked: sonic exit, T/Tt from NACA 1135 eq 43 at M = 1
    Result.Choked := True;
    Te := R_Temp * Eq43(1.0, Gamma_O2);
    V := Sqrt(Gamma_O2 * R_O2 * Te);
    Result.Mach := 1.0;
    Result.Density := G / V;
    Result.Pressure := Result.Density * R_O2 * Te;   // above ambient: under-expanded jet
  end
  else
  begin
    Result.Density := One_Bar / (R_O2 * Te);
    Result.Pressure := One_Bar;
  end;
  Result.Velocity := V;
  Result.Temperature := Te;
end;

function FreeJet(const E: TExitState): TFreeJetState;
var
  g: Double;
begin
  g := Gamma_O2;
  Result.Pressure := One_Bar;
  if not E.Choked then
  begin
    // already at ambient pressure: the exit is the extreme
    Result.Mach := E.Mach;
    Result.Temperature := E.Temperature;
    Result.Velocity := E.Velocity;
    Result.ExitStagPressure := E.Pressure / Eq44(E.Mach, g);
    Exit;
  end;
  // isentropic from the sonic exit's stagnation pressure down to ambient
  Result.ExitStagPressure := E.Pressure / Eq44(1.0, g);
  Result.Mach := Sqrt(2 / (g - 1) * (Power(Result.ExitStagPressure / One_Bar, (g - 1) / g) - 1));
  Result.Temperature := R_Temp * Eq43(Result.Mach, g);
  Result.Velocity := Result.Mach * Sqrt(g * R_O2 * Result.Temperature);
end;

function TCatheter.Mach(const Flow: TVMobj): TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(Flow.Rows, Flow.Cols);
  for i := 0 to Flow.Cols - 1 do
    Result[0, i] := ExitState(Flow[0, i]).Mach;
end;

function TCatheter.ExitVelocity(const Flow: TVMobj): TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(Flow.Rows, Flow.Cols);
  for i := 0 to Flow.Cols - 1 do
    Result[0, i] := ExitState(Flow[0, i]).Velocity;
end;

function TCatheter.Stall(const Flow: TVMobj; D: Double): TVMobj;
var
  CircuitArea: Double;
begin
  CircuitArea := Pi * Sqr(D / 2);
  // area * v^2 * rho / (100 * circuit area), v at ambient density - the original
  Result := Sqr(Velocity(Flow)) * (Area * O2_Density_RT / (100 * CircuitArea));
end;

function TCatheter.Thrust(const E: TExitState): Double;
begin
  Result := E.MassFlow * E.Velocity + (E.Pressure - One_Bar) * Area;
end;

function TCatheter.StallPressure(FlowLpm, D: Double): Double;
begin
  Result := Area * Sqr(FlowLpm / (60000 * Area)) * O2_Density_RT / (100 * Pi * Sqr(D / 2));
end;

function TCatheter.MassFlow(const Flow: TVMobj): TVMobj;
begin
  Result := Flow * (O2_Density_RT / 60);   // l/min * kg/m^3 / 60000 * 1000 = g/s
end;

end.
