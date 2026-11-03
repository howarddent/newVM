unit uThorax;

{ Airways, lungs, chest wall and the jet, for the HFJV model.

  THE CIRCUIT

  Lumped, and linear in its unknowns. Pressures are relative to the
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

   upper airway     I_ua Q_ua' = p_t - R_ua Q_ua              (Q_ua out of the mouth)
   tracheal node    0 = Q_j - Q_ua - Q_aw                     (algebraic)
   lower airways    I_aw Q_aw' = p_t + dp_j - p_A - R_aw Q_aw
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

  WHAT IS LEFT OUT

  The upper airway's resistance is turbulent, R ~ K |Q|, in reality; it
  is linear here, so the mean airway pressure is only approximate. The
  lung is one compartment, with no pendelluft, and its tissue resistance
  is a constant rather than the constant-phase fall with frequency.
  Gas exchange is not modelled: VT/VD and f VT^2 (the CO2-elimination
  index of Slutsky and others) stand in for it. }

{$mode delphi}{$H+}

interface

uses SysUtils, Math, newVM, newVMsparse, uDescriptor, uAbdomenFluid, uJetCalcVM;

const
  cmH2O = 98.0665;      // Pa
  Litre = 1e-3;         // m3
  RUnit = cmH2O / Litre;            // cmH2O/(L/s) -> Pa s/m3
  EUnit = cmH2O / Litre;            // cmH2O/L     -> Pa/m3
  IUnit = cmH2O / Litre;            // cmH2O s2/L  -> Pa s2/m3
  PAtm = 101325.0;

type
  TJetSource = (jsMeasured, jsCalculated);

  { Everything in the clinical units of the literature: cmH2O, L, s. }
  TThoraxParams = record
    Raw, Iaw : Double;      // lower airways, below the jet
    Rua, Iua : Double;      // upper airway, above the jet to the mouth
    TracheaD : Double;      // m, for the jet's momentum
    EL, RL : Double;        // lung recoil and tissue resistance
    VFRC : Double;          // L, end-expiratory lung volume
    Erc, Rrc, Irc : Double; // rib cage
    Edi, Rdi, Idi : Double; // diaphragm and abdomen, when lumped
    VD : Double;            // L, anatomical dead space below the jet
    // jet
    Cannula : TJetCath;
    JetSource : TJetSource;
    DrivingP : Double;      // bar gauge
    Freq : Double;          // Hz
    Ti : Double;            // inspiratory fraction of the cycle
  end;

  TThorax = class
  private
    FFluid : TAbdomenFluid;
    FDiaSurf : Integer;
    FW : TDoubleArray;      // diaphragm weights, when FEM
    FCath : TCatheter;
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
    { Lung and diaphragm volume (m3) from a state vector. }
    function Vdi(const X : TVMobj) : Double;
    function VL(const X : TVMobj) : Double;
    function Qdi(const X : TVMobj) : Double;
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
    Rua := 2.0;  Iua := 0.012;
    TracheaD := 0.018;
    EL := 7.0;   RL := 0.5;
    VFRC := 2.2;
    Erc := 10.0; Rrc := 0.5; Irc := 0.004;
    Edi := 8.0;  Rdi := 0.5; Idi := 0.02;
    VD := 0.12;
    Cannula := Biro;
    JetSource := jsMeasured;
    // a typical setting: 2 bar gauge, 200 /min, I:E 1:1
    DrivingP := 2.0;
    Freq := 200 / 60;
    Ti := 0.5;
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
end;

procedure TThorax.AddToSystem(Sys : TDescriptorSystem; Fluid : TAbdomenFluid; DiaSurf : Integer);
var
  b : Integer;

  procedure Lumped(iV, iQ : Integer; E, R, I : Double);
  begin
    Sys.AddE(iV, iV, 1);  Sys.AddA(iV, iQ, 1);
    Sys.AddE(iQ, iQ, I * IUnit);
    Sys.AddA(iQ, iPpl, 1);
    Sys.AddA(iQ, iV, -E * EUnit);
    Sys.AddA(iQ, iQ, -R * RUnit);
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
  Assert((P.Iua > 0) and (P.Iaw > 0) and (P.Irc > 0),
    'TThorax : inertances must be positive (they make the flows differential)');
  FFluid := Fluid;
  FDiaSurf := DiaSurf;
  if FFluid <> nil then FW := FFluid.SurfaceWeights(DiaSurf) else FW := nil;
  SetupJet;

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
  Sys.AddE(iQua, iQua, P.Iua * IUnit);
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
  // lung tissue: 0 = p_A - p_pl - E_L V_L - R_L Q_L
  Sys.SetAlgebraic(iPpl);
  Sys.AddA(iPpl, iPA, 1);
  Sys.AddA(iPpl, iPpl, -1);
  AddVL(iPpl, -P.EL * EUnit);
  AddQL(iPpl, -P.RL * RUnit);
  // rib cage and (lumped) diaphragm
  Lumped(iVrc, iQrc, P.Erc, P.Rrc, P.Irc);
  if FFluid = nil then
    Lumped(iVdi, iQdi, P.Edi, P.Rdi, P.Idi)
  else
    FFluid.CouplePressure(Sys, DiaSurf, iPpl);
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
