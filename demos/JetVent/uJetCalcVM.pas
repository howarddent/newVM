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
     cubic; that is now TPolynomial.Fit(..., 3) and TPolynomial.Evaluate,
     fitted once (lazily) and reused for every call rather than refitted
     per call as before. Same cubic over the same table, so the same
     numbers - the fit is on K directly, as the original was, although a
     cubic spanning K = 1.2 .. 100 with most of the table below 20 is
     not a close interpolant at the low end; fitting against ln K would
     be better and is one line to change, but that would alter the
     calculated flows against the Delphi version, so it is left alone.

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

  TCatheter = class
  public
    Name: string;
    Length, Diameter, Radius, Area: Double;
    Reynolds_342: Integer;
    MeasuredFlow, EntrainedFlow: TVMobj;                       // l/min, 1 x NumPressures
    MeasuredStallFlow, MeasuredStall22, MeasuredStall15: TVMobj; // l/min; cmH2O; cmH2O
    constructor Create(Cath_Type: TJetCath);

    { scalar, one driving pressure (bar gauge) -> jet flow l/min }
    function CalcFlow(DP: Double): Double;
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
    { rho_amb * Q, in g/s }
    function MassFlow(const Flow: TVMobj): TVMobj;
  end;

{ Crane A-22 for gamma = 1.4: critical pressure ratio and net expansion
  factor Y against the resistance coefficient K - cubic fits to the table }
function CalcCritPRatio(k: Double; out Y: Double): Double;

function DrivingPressures: TVMobj;

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
  CraneDP := TPolynomial.Fit(tabK, tabDP, 3);
  CraneY  := TPolynomial.Fit(tabK, tabY, 3);
  CraneFitted := True;
end;

function CalcCritPRatio(k: Double; out Y: Double): Double;
begin
  if not CraneFitted then
    FitCrane;
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
  case Cath_Type of
    Lindholm:
      begin
        Length := 9.5e-2;  // lengthened to compensate 45 degree bend
        Diameter := 2.0e-3;
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
        Diameter := 1.5e-3;
        MeasuredFlow      := TVMobj.Create(1, 7, [14.4, 23.75, 31.6, 38.4, 44.7, 51.2, 57.6]);
        EntrainedFlow     := TVMobj.Create(1, 7, [37.7, 64, 80.7, 97, 111, 122, 134]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [14, 23, 31, 40, 47, 55, 64]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 4, 7, 10, 12, 15, 19]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    IV_16:
      begin
        Length := 45e-3;
        Diameter := 1.35e-3;
        MeasuredFlow      := TVMobj.Create(1, 7, [13.36, 20.62, 27.8, 33.9, 39.6, 45.7, 50.7]);
        EntrainedFlow     := TVMobj.Create(1, 7, [33, 57, 76, 88, 102, 112, 122]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [11, 20, 28, 34, 41, 47, 52]);
        MeasuredStall22   := TVMobj.Create(1, 7, [2, 4, 7, 10, 13, 16, 19]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
    IV_18:
      begin
        Length := 45e-3;
        Diameter := 0.9e-3;
        MeasuredFlow      := TVMobj.Create(1, 7, [7.0, 10.8, 14.3, 17.24, 20.28, 23.3, 26.38]);
        EntrainedFlow     := TVMobj.Create(1, 7, [28.7, 43.5, 54, 65, 66, 71, 79]);
        MeasuredStallFlow := TVMobj.Create(1, 7, [5.6, 8.5, 11.8, 14.6, 16, 20, 22]);
        MeasuredStall22   := TVMobj.Create(1, 7, [1, 2, 4, 5, 6, 7, 9]);
        MeasuredStall15   := TVMobj.Create(1, 7, [0, 0, 0, 0, 0, 0, 0]);
      end;
  end;
  Name := JetString[Cath_Type];
  Radius := Diameter / 2;
  Area := Pi * Sqr(Radius);
  Reynolds_342 := Round(342 * Diameter * O2_Density_RT / O2_dyn_Viscosity_RT);
end;

function TCatheter.CalcFlow(DP: Double): Double;
// Jet flow from the Darcy-Weisbach equation, Crane 3-20 - as the original
const
  k_inlet = 0.5;
  k_outlet = 1.0;
  Roughness = 1e-6;
var
  kactual, Y, surd: Double;
  DPAbs, PRatio, CritP, Actual_DP: Double;
  Sonic: Boolean;
begin
  DPAbs := DP + 1;
  PRatio := DP / DPAbs;
  kactual := k_inlet + MoodyF(Diameter, Reynolds_342, Roughness) * Length / Diameter + k_outlet;
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

function TCatheter.MassFlow(const Flow: TVMobj): TVMobj;
begin
  Result := Flow * (O2_Density_RT / 60);   // l/min * kg/m^3 / 60000 * 1000 = g/s
end;

end.
