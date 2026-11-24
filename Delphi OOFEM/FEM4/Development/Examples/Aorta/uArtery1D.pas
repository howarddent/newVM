unit uArtery1D;

{ Pulse waves in a network of elastic arteries: the one-dimensional
  equations of blood flow, solved by finite elements.

  EQUATIONS   In each vessel, for the lumen area A(x,t) and the flow
  Q(x,t) (Hughes & Lubliner 1973; Formaggia, Lamponi & Quarteroni 2003,
  J Eng Math 47:251):

      A_t + Q_x = 0
      Q_t + (Q^2/A)_x + (A/rho) p_x = -K_R Q/A

  with a flat velocity profile in the momentum flux, Poiseuille's
  friction K_R = 8 pi nu (it matters only in the small arteries, where
  the profile is nearly parabolic) and the elastic wall

      p = P0 + beta(x) (sqrt A - sqrt A0(x)).

  A0 is the area at the reference pressure P0, and beta is set from the
  local wave speed there, c0^2 = beta sqrt(A0) / (2 rho). So beta is the
  wall's elastance: at a given area dp/dA is proportional to it, and the
  wave speed to its square root. Vessels taper: A0 and beta vary with x.

  In conservation form U_t + F_x = S, U = (A, Q), written about the rest
  state so that a tapering vessel at rest stays exactly at rest:

      F = (Q, Q^2/A + beta (A^1.5 - A0^1.5)/(3 rho))
      S = (0, -K_R Q/A - (beta'/rho)(2/3 A^1.5 - A sqrt A0 + A0^1.5/3)
                       + beta A0' (A - A0)/(2 rho sqrt A0)).

  FINITE ELEMENTS   Linear elements on each vessel and the second-order
  Taylor-Galerkin scheme (the finite-element Lax-Wendroff: Formaggia et
  al. 2003, section 4). With H = dF/dU and S_U = dS/dU,

      (U_new - U, psi) = dt (F + dt/2 H S, psi_x)
                         - dt^2/2 (S_U F_x, psi) - dt^2/2 (H F_x, psi_x)
                         + dt (S + dt/2 S_U S, psi)

  for every interior hat function psi, with the consistent mass matrix
  (one tridiagonal solve per vessel and step). It is explicit and stable
  for dt < h / (sqrt 3 (|u| + c)).

  ENDS AND JUNCTIONS   The end nodes carry the same Galerkin equation,
  with the flux through the end taken from the junction's state, so each
  vessel's volume changes by exactly dt (Q_in - Q_out). (Setting the end
  nodes directly from the characteristics, tried first, lost 3-5 % of
  the stroke volume.) The flow is subcritical, so one characteristic
  variable leaves each end: W = u + 4 (c - c0) at the far end and
  u - 4 (c - c0) at the near end (the departure from rest, so taper does
  not disturb it), taken from the end node. A junction of up to three
  vessel ends then solves, for the areas just outside,

      total pressure p + rho u^2 / 2 the same in every vessel,
      sum of the flows in + Qin(t) - G (p - PV) = 0,

  by Newton's method. G is the conductance of a branch that is not
  modelled, lumped as a pure resistance to the venous pressure PV; Qin
  is a prescribed inflow (the aortic valve's). One vessel end with a
  conductance is a terminal resistance; with an inflow, the inlet. A
  lumped branch may instead be a three-element Windkessel (TJunction.C)
  whose series resistance is the branch artery's characteristic
  impedance, sqrt(inertance / compliance) per unit length: that is how
  the branch's blood inertia and wall compliance appear to a wave.

  WALL VISCOELASTICITY   With WallTau > 0 the wall is a Kelvin-Voigt
  solid (Alastruey et al. 2011, J Biomech 44:2250):

      p = P0 + beta (sqrt A - sqrt A0) + Gamma / (A0 sqrt A) A_t,

  Gamma = (2/3) sqrt(pi) phi h for wall viscosity phi and thickness h.
  Since beta = (4/3) sqrt(pi) E h / A0, Gamma = WallTau beta A0 / 2 with
  WallTau = phi / E, the wall's retardation time: the one parameter. The
  viscosity is taken not to change with the elastance multiplier, so
  beta here is the unmultiplied one. With A_t = -Q_x the extra pressure
  puts a diffusion of the flow into the momentum equation,

      Q_t = ... + (A/rho) (g Q_x)_x,   g = Gamma / (A0 sqrt A),

  of diffusivity WallTau c^2, far too stiff to treat explicitly. It is
  split off: after each Taylor-Galerkin step, backward Euler on linear
  elements with a lumped mass (one more tridiagonal solve per vessel),
  first order in time. It leaves A alone, so volume is still conserved
  exactly. No viscous flux is applied at the vessels' ends, and the
  junctions match the elastic pressure only, as in Alastruey's scheme.
  A small wave exp(i (w t - k x)) then has k = (w/c) / sqrt(1 + i w
  WallTau): its loss per wavelength grows with frequency.

  Units: cm, g, s (pressures dyn/cm2; the callers convert to mmHg). }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math;

const
  Rho = 1.06;        { blood, g/cm3 }
  Visc = 0.04;       { poise }
  mmHg = 1333.22;    { dyn/cm2 }

type
  TFlowFn = function(t: Double): Double of object;

  TVessel = class
  private
    FF1, FF2, FL1, FL2, FSL, FR1, FR2, FD1, FD2, FCp: array of Double;
  public
    Name: string;
    NNode: Integer;
    Len, Dx: Double;
    RIn, ROut: Double;         { radii at P0, cm }
    Aortic: Boolean;
    JIn, JOut: Integer;        { junctions at x = 0 and x = Len }
    PRef: Double;
    A0, Beta, C0, DA0, DBeta: array of Double;
    Gam: array of Double;      { wall viscosity Gamma; all 0 = elastic }
    Viscous: Boolean;
    StiffUsed: Double;
    A, Q: array of Double;
    BndA, BndQ: array[0..1] of Double;   { the ends at the new time }
    { NElem elements; the wave speed at P0 from WaveSpeed(diameter),
      times sqrt(Stiff) }
    procedure Discretise(NElem: Integer; Stiff, APRef: Double);
    function Pressure(i: Integer): Double;
    function Speed(i: Integer): Double;
    { at the fraction s of the length }
    function PressureAt(s: Double): Double;
    function FlowAt(s: Double): Double;
    function Volume: Double;
    function Compliance: Double;      { dV/dp at rest, cm5/dyn }
    function MaxSignal: Double;       { largest |u| + c }
    procedure Advance(dt, KR: Double);
    { Gamma for the retardation time Tau (s) at the unmultiplied elastance }
    procedure SetWallTau(Tau: Double);
    { the wall's viscous pressure at node i, -g Q_x }
    function ViscousPressure(i: Integer): Double;
    { the split-off diffusion of Q over dt }
    procedure Relax(dt: Double);
  end;

  TJunction = record
    NV: Integer;
    V: array[0..2] of TVessel;
    AtEnd: array[0..2] of Boolean;
    G: Double;             { conductance of the lumped branches, cm5/(dyn s) }
    Fraction: Double;      { their share of the cardiac output }
    Leaks: string;         { their names }
    HasInflow: Boolean;
    { A compliance C makes the lumped branch a three-element Windkessel:
      1/G in series, then C beside R2, to the venous pressure. Pc is the
      pressure on C (the venous pressure when C = 0). }
    C, R2, Pc: Double;
    BranchR: Double;       { radius of the branch artery, cm; 0 = none given }
    BranchN: Integer;
    Zc: Double;            { the series impedance used, when C > 0 }
    P, QLeak: Double;      { after the last step }
  end;

  TArterialTree = class
  public
    Vessels: array of TVessel;
    J: array of TJunction;
    P0, PV, KR: Double;
    WallTau: Double;       { wall retardation time phi/E, s; 0 = elastic. Set before Build }
    Time: Double;
    Inflow: TFlowFn;
    constructor Create;
    destructor Destroy; override;
    function AddVessel(const AName: string; AJIn, AJOut: Integer;
      ALen, ARIn, AROut: Double; AAortic: Boolean): TVessel;
    { a branch not modelled, at junction Node, taking Fraction of the flow }
    { ARadius, ACount: the branch is ACount arteries of that radius (cm);
      their characteristic impedance is what a Windkessel bed puts in
      series. 0 at a vessel's end: that vessel's own. }
    procedure AddLeak(Node: Integer; const AName: string; AFraction: Double;
      ARadius: Double = 0; ACount: Integer = 1);
    procedure SetInlet(Node: Integer);
    { Elements of about HTarget (at least 4 a vessel); the elastance of
      the aortic vessels times AorticStiff and of the others times
      OtherStiff; the lumped branches' resistances in parallel RTotal. }
    { CPeriph > 0 turns each lumped branch into a Windkessel: in series
      the characteristic impedance rho c / A of the branch artery (of the
      vessel itself at a vessel's end), so a fast wave sees the artery it
      would enter and is not reflected; then the bed's share of CPeriph
      beside the rest of its resistance. }
    procedure Build(HTarget, AorticStiff, OtherStiff, RTotal: Double; CPeriph: Double = 0);
    procedure Reset;
    function StableDt(CFL: Double): Double;
    procedure Step(dt: Double);
    function Volume: Double;
    function Compliance: Double;
    function FindVessel(const AName: string): TVessel;
  end;

{ Wave speed at the reference pressure from the lumen diameter:
  c = 13.3 / d^0.3 (m/s, d in mm), the fit of Reymond et al. 2009
  (Am J Physiol 297:H208) to measured speeds. Returns cm/s for cm. }
function WaveSpeed(Diameter: Double): Double;

implementation

function WaveSpeed(Diameter: Double): Double;
begin
  Result := 100 * 13.3 / Power(10 * Diameter, 0.3);
end;

{ ---- TVessel ---- }

procedure TVessel.Discretise(NElem: Integer; Stiff, APRef: Double);
var
  i: Integer;
  r, c: Double;
begin
  NNode := NElem + 1;
  Dx := Len / NElem;
  PRef := APRef;
  SetLength(A0, NNode); SetLength(Beta, NNode); SetLength(C0, NNode);
  SetLength(DA0, NNode); SetLength(DBeta, NNode);
  SetLength(A, NNode); SetLength(Q, NNode);
  SetLength(Gam, NNode); Viscous := False; StiffUsed := Stiff;
  SetLength(FF1, NNode); SetLength(FF2, NNode); SetLength(FL1, NNode); SetLength(FL2, NNode);
  SetLength(FSL, NNode); SetLength(FR1, NNode); SetLength(FR2, NNode);
  SetLength(FD1, NNode); SetLength(FD2, NNode); SetLength(FCp, NNode);
  for i := 0 to NNode - 1 do
  begin
    r := RIn + (ROut - RIn) * i / NElem;
    c := WaveSpeed(2 * r) * Sqrt(Stiff);
    A0[i] := Pi * r * r;
    C0[i] := c;
    Beta[i] := 2 * Rho * c * c / Sqrt(A0[i]);
    A[i] := A0[i];
    Q[i] := 0;
    Gam[i] := 0;
  end;
  for i := 0 to NNode - 1 do
    if i = 0 then
    begin
      DA0[i] := (A0[1] - A0[0]) / Dx; DBeta[i] := (Beta[1] - Beta[0]) / Dx;
    end
    else if i = NNode - 1 then
    begin
      DA0[i] := (A0[i] - A0[i - 1]) / Dx; DBeta[i] := (Beta[i] - Beta[i - 1]) / Dx;
    end
    else
    begin
      DA0[i] := (A0[i + 1] - A0[i - 1]) / (2 * Dx); DBeta[i] := (Beta[i + 1] - Beta[i - 1]) / (2 * Dx);
    end;
end;

function TVessel.Pressure(i: Integer): Double;
begin
  Result := PRef + Beta[i] * (Sqrt(A[i]) - Sqrt(A0[i]));
  if Viscous then Result := Result + ViscousPressure(i);
end;

procedure TVessel.SetWallTau(Tau: Double);
var
  i: Integer;
begin
  Viscous := Tau > 0;
  for i := 0 to NNode - 1 do
    Gam[i] := Tau * Beta[i] / StiffUsed * A0[i] / 2;
end;

function TVessel.ViscousPressure(i: Integer): Double;
var
  dq: Double;
begin
  if i = 0 then dq := (Q[1] - Q[0]) / Dx
  else if i = NNode - 1 then dq := (Q[i] - Q[i - 1]) / Dx
  else dq := (Q[i + 1] - Q[i - 1]) / (2 * Dx);
  Result := -Gam[i] / (A0[i] * Sqrt(A[i])) * dq;
end;

procedure TVessel.Relax(dt: Double);
var
  i, n: Integer;
  kl, kr_, b, w, den: Double;

  function Ke(e: Integer): Double;   { element e, between nodes e and e + 1 }
  begin
    Result := dt / (Rho * Dx) * 0.5 * (Gam[e] / (A0[e] * Sqrt(A[e]))
      + Gam[e + 1] / (A0[e + 1] * Sqrt(A[e + 1])));
  end;

begin
  if not Viscous then Exit;
  n := NNode;
  { (w/A)(Qn - Q) + sum over the node's elements of Ke (Qn_i - Qn_j) = 0 }
  kl := 0;
  for i := 0 to n - 1 do
  begin
    if i < n - 1 then kr_ := Ke(i) else kr_ := 0;
    if (i = 0) or (i = n - 1) then w := 0.5 * Dx else w := Dx;
    b := w / A[i] + kl + kr_;
    FR2[i] := w / A[i] * Q[i];
    if i = 0 then den := b else
    begin
      den := b + kl * FCp[i - 1];
      FR2[i] := FR2[i] + kl * FR2[i - 1];
    end;
    FCp[i] := -kr_ / den;
    FR2[i] := FR2[i] / den;
    kl := kr_;
  end;
  for i := n - 2 downto 0 do FR2[i] := FR2[i] - FCp[i] * FR2[i + 1];
  for i := 0 to n - 1 do Q[i] := FR2[i];
end;

function TVessel.Speed(i: Integer): Double;
begin
  Result := Sqrt(Beta[i] * Sqrt(A[i]) / (2 * Rho));
end;

function TVessel.PressureAt(s: Double): Double;
var
  i: Integer;
  f: Double;
begin
  f := EnsureRange(s, 0, 1) * (NNode - 1);
  i := Min(Floor(f), NNode - 2);
  f := f - i;
  Result := (1 - f) * Pressure(i) + f * Pressure(i + 1);
end;

function TVessel.FlowAt(s: Double): Double;
var
  i: Integer;
  f: Double;
begin
  f := EnsureRange(s, 0, 1) * (NNode - 1);
  i := Min(Floor(f), NNode - 2);
  f := f - i;
  Result := (1 - f) * Q[i] + f * Q[i + 1];
end;

function TVessel.Volume: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to NNode - 2 do Result := Result + 0.5 * Dx * (A[i] + A[i + 1]);
end;

function TVessel.Compliance: Double;
var
  i: Integer;
  w: Double;
begin
  { dA/dp = 2 sqrt(A0) / beta = A0 / (rho c0^2) }
  Result := 0;
  for i := 0 to NNode - 1 do
  begin
    if (i = 0) or (i = NNode - 1) then w := 0.5 * Dx else w := Dx;
    Result := Result + w * A0[i] / (Rho * C0[i] * C0[i]);
  end;
end;

function TVessel.MaxSignal: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to NNode - 1 do
    Result := Max(Result, Abs(Q[i] / A[i]) + Speed(i));
end;

procedure TVessel.Advance(dt, KR: Double);
var
  i, e, n: Integer;
  sA, sA0, S2, d1, d2, Am, Qm, um, bm, sAm, sA0m, dBm, dA0m: Double;
  H21, H22, SUA, SUQ, hf1, hf2, sf2, m1, m2, w: Double;
begin
  n := NNode;
  for i := 0 to n - 1 do
  begin
    sA := Sqrt(A[i]); sA0 := Sqrt(A0[i]);
    FF1[i] := Q[i];
    FF2[i] := Q[i] * Q[i] / A[i] + Beta[i] * (A[i] * sA - A0[i] * sA0) / (3 * Rho);
    S2 := -KR * Q[i] / A[i]
      - DBeta[i] / Rho * (2 / 3 * A[i] * sA - A[i] * sA0 + A0[i] * sA0 / 3)
      + Beta[i] * DA0[i] / (2 * Rho * sA0) * (A[i] - A0[i]);
    FL1[i] := FF1[i] + 0.5 * dt * S2;
    FL2[i] := FF2[i] + 0.5 * dt * 2 * Q[i] / A[i] * S2;
    FSL[i] := S2 * (1 - 0.5 * dt * KR / A[i]);
    FR1[i] := 0; FR2[i] := 0;
  end;
  for e := 0 to n - 2 do
  begin
    d1 := FF1[e + 1] - FF1[e]; d2 := FF2[e + 1] - FF2[e];
    Am := 0.5 * (A[e] + A[e + 1]); Qm := 0.5 * (Q[e] + Q[e + 1]);
    um := Qm / Am;
    bm := 0.5 * (Beta[e] + Beta[e + 1]);
    sAm := Sqrt(Am); sA0m := Sqrt(0.5 * (A0[e] + A0[e + 1]));
    dBm := 0.5 * (DBeta[e] + DBeta[e + 1]); dA0m := 0.5 * (DA0[e] + DA0[e + 1]);
    H21 := -um * um + bm * sAm / (2 * Rho);
    H22 := 2 * um;
    SUA := KR * Qm / (Am * Am) - dBm / Rho * (sAm - sA0m) + bm * dA0m / (2 * Rho * sA0m);
    SUQ := -KR / Am;
    hf1 := d2;
    hf2 := H21 * d1 + H22 * d2;
    sf2 := SUA * d1 + SUQ * d2;
    m1 := 0.5 * (FL1[e] + FL1[e + 1]);
    m2 := 0.5 * (FL2[e] + FL2[e + 1]);
    FR1[e] := FR1[e] - dt * m1 + 0.5 * dt * dt * hf1 / Dx;
    FR2[e] := FR2[e] - dt * m2 + 0.5 * dt * dt * hf2 / Dx - 0.25 * dt * dt * sf2
      + dt * Dx * (2 * FSL[e] + FSL[e + 1]) / 6;
    FR1[e + 1] := FR1[e + 1] + dt * m1 - 0.5 * dt * dt * hf1 / Dx;
    FR2[e + 1] := FR2[e + 1] + dt * m2 - 0.5 * dt * dt * hf2 / Dx - 0.25 * dt * dt * sf2
      + dt * Dx * (FSL[e] + 2 * FSL[e + 1]) / 6;
  end;
  { the ends: the flux of the junction's state (BndA, BndQ) through the
    boundary, so the vessel's volume changes by exactly dt (Q_in - Q_out) }
  for i := 0 to 1 do
  begin
    if i = 0 then e := 0 else e := n - 1;
    m1 := BndQ[i];
    m2 := BndQ[i] * BndQ[i] / BndA[i]
      + Beta[e] * (BndA[i] * Sqrt(BndA[i]) - A0[e] * Sqrt(A0[e])) / (3 * Rho);
    if i = 0 then
    begin
      FR1[e] := FR1[e] + dt * m1; FR2[e] := FR2[e] + dt * m2;
    end
    else
    begin
      FR1[e] := FR1[e] - dt * m1; FR2[e] := FR2[e] - dt * m2;
    end;
  end;
  { consistent mass: Dx/6 (d[i-1] + 4 d[i] + d[i+1]) = R[i], with 2 on
    the diagonal at the ends. Thomas's algorithm. }
  for i := 0 to n - 1 do
  begin
    FR1[i] := FR1[i] * 6 / Dx; FR2[i] := FR2[i] * 6 / Dx;
  end;
  FCp[0] := 0.5;
  FR1[0] := FR1[0] / 2; FR2[0] := FR2[0] / 2;
  for i := 1 to n - 1 do
  begin
    if i = n - 1 then w := 2 - FCp[i - 1] else w := 4 - FCp[i - 1];
    FCp[i] := 1 / w;
    FR1[i] := (FR1[i] - FR1[i - 1]) / w;
    FR2[i] := (FR2[i] - FR2[i - 1]) / w;
  end;
  FD1[n - 1] := FR1[n - 1]; FD2[n - 1] := FR2[n - 1];
  for i := n - 2 downto 0 do
  begin
    FD1[i] := FR1[i] - FCp[i] * FD1[i + 1];
    FD2[i] := FR2[i] - FCp[i] * FD2[i + 1];
  end;
  for i := 0 to n - 1 do
  begin
    A[i] := A[i] + FD1[i];
    Q[i] := Q[i] + FD2[i];
  end;
end;

{ ---- TArterialTree ---- }

constructor TArterialTree.Create;
begin
  inherited Create;
  P0 := 80 * mmHg;
  PV := 0;
  KR := 8 * Pi * Visc / Rho;
end;

destructor TArterialTree.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(Vessels) do Vessels[i].Free;
  inherited Destroy;
end;

function TArterialTree.AddVessel(const AName: string; AJIn, AJOut: Integer;
  ALen, ARIn, AROut: Double; AAortic: Boolean): TVessel;
var
  k, m: Integer;
begin
  Result := TVessel.Create;
  Result.Name := AName;
  Result.JIn := AJIn; Result.JOut := AJOut;
  Result.Len := ALen; Result.RIn := ARIn; Result.ROut := AROut;
  Result.Aortic := AAortic;
  SetLength(Vessels, Length(Vessels) + 1);
  Vessels[High(Vessels)] := Result;
  m := Max(AJIn, AJOut);
  if m > High(J) then
  begin
    k := Length(J);
    SetLength(J, m + 1);
    while k <= m do
    begin
      J[k].NV := 0; J[k].G := 0; J[k].Fraction := 0; J[k].Leaks := ''; J[k].HasInflow := False; J[k].C := 0; J[k].R2 := 0; J[k].BranchR := 0; J[k].BranchN := 1; J[k].Zc := 0;
      Inc(k);
    end;
  end;
  with J[AJIn] do
  begin
    if NV > 2 then raise Exception.Create('AddVessel : more than three vessels at a junction');
    V[NV] := Result; AtEnd[NV] := False; Inc(NV);
  end;
  with J[AJOut] do
  begin
    if NV > 2 then raise Exception.Create('AddVessel : more than three vessels at a junction');
    V[NV] := Result; AtEnd[NV] := True; Inc(NV);
  end;
end;

procedure TArterialTree.AddLeak(Node: Integer; const AName: string; AFraction: Double;
  ARadius: Double; ACount: Integer);
begin
  J[Node].BranchR := ARadius; J[Node].BranchN := ACount;
  J[Node].Fraction := J[Node].Fraction + AFraction;
  if J[Node].Leaks <> '' then J[Node].Leaks := J[Node].Leaks + ', ';
  J[Node].Leaks := J[Node].Leaks + AName;
end;

procedure TArterialTree.SetInlet(Node: Integer);
begin
  J[Node].HasInflow := True;
end;

procedure TArterialTree.Build(HTarget, AorticStiff, OtherStiff, RTotal: Double; CPeriph: Double);
var
  i: Integer;
  tot, rb, z: Double;
  k: Integer;
begin
  for i := 0 to High(Vessels) do
    with Vessels[i] do
      if Aortic then
        Discretise(Max(4, Round(Len / HTarget)), AorticStiff, P0)
      else
        Discretise(Max(4, Round(Len / HTarget)), OtherStiff, P0);
  tot := 0;
  for i := 0 to High(J) do tot := tot + J[i].Fraction;
  for i := 0 to High(J) do
  begin
    J[i].G := 0; J[i].C := 0; J[i].R2 := 0;
    if (tot > 0) and (J[i].Fraction > 0) then
    begin
      rb := RTotal * tot / J[i].Fraction;
      if CPeriph > 0 then
      begin
        if J[i].BranchR > 0 then
          z := Rho * WaveSpeed(2 * J[i].BranchR) * Sqrt(OtherStiff)
            / (J[i].BranchN * Pi * Sqr(J[i].BranchR))
        else if J[i].NV = 1 then
        begin
          if J[i].AtEnd[0] then k := J[i].V[0].NNode - 1 else k := 0;
          z := Rho * J[i].V[0].C0[k] / J[i].V[0].A0[k];
        end
        else
          z := 0.1 * rb;
        z := Min(z, 0.5 * rb);
        J[i].Zc := z;
        J[i].G := 1 / z; J[i].R2 := rb - z;
        J[i].C := CPeriph * J[i].Fraction / tot;
      end
      else
        J[i].G := 1 / rb;
    end;
  end;
  for i := 0 to High(Vessels) do Vessels[i].SetWallTau(WallTau);
  Reset;
end;

procedure TArterialTree.Reset;
var
  i, k: Integer;
begin
  Time := 0;
  for i := 0 to High(Vessels) do
    with Vessels[i] do
      for k := 0 to NNode - 1 do
      begin
        A[k] := A0[k]; Q[k] := 0;
      end;
  for i := 0 to High(J) do
  begin
    J[i].P := P0;
    if J[i].C > 0 then
      J[i].Pc := PV + (P0 - PV) * J[i].R2 / (J[i].R2 + 1 / J[i].G)
    else
      J[i].Pc := PV;
    J[i].QLeak := J[i].G * (P0 - J[i].Pc);
  end;
end;

function TArterialTree.StableDt(CFL: Double): Double;
var
  i: Integer;
begin
  Result := MaxDouble;
  for i := 0 to High(Vessels) do
    Result := Min(Result, Vessels[i].Dx / Vessels[i].MaxSignal);
  Result := CFL * Result / Sqrt(3);
end;

function TArterialTree.Volume: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Vessels) do Result := Result + Vessels[i].Volume;
end;

function TArterialTree.Compliance: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(Vessels) do Result := Result + Vessels[i].Compliance;
end;

function TArterialTree.FindVessel(const AName: string): TVessel;
var
  i: Integer;
begin
  for i := 0 to High(Vessels) do
    if SameText(Vessels[i].Name, AName) then Exit(Vessels[i]);
  raise Exception.Create('FindVessel : no vessel ' + AName);
end;

procedure TArterialTree.Step(dt: Double);
var
  jn, k, m, it, i, b, p: Integer;
  WStar, Bet, Cz, Az: array[0..2] of Double;
  Sg: array[0..2] of Double;
  x, r, r1, dx_: array[0..2] of Double;
  Jm: array[0..2, 0..2] of Double;
  uu, pp: array[0..2] of Double;
  Qin, u, c, big, f, h, nrm, scale: Double;
  Ve: TVessel;

  procedure Resid(const xa: array of Double; var res: array of Double);
  var
    kk: Integer;
    cc, flow: Double;
  begin
    flow := Qin;
    for kk := 0 to J[jn].NV - 1 do
    begin
      cc := Sqrt(Bet[kk] * Sqrt(xa[kk]) / (2 * Rho));
      uu[kk] := WStar[kk] - Sg[kk] * 4 * (cc - Cz[kk]);
      pp[kk] := P0 + Bet[kk] * (Sqrt(xa[kk]) - Sqrt(Az[kk]));
      flow := flow + Sg[kk] * xa[kk] * uu[kk];
    end;
    res[0] := flow - J[jn].G * (pp[0] - J[jn].Pc);
    for kk := 1 to J[jn].NV - 1 do
      res[kk] := (pp[kk] + 0.5 * Rho * uu[kk] * uu[kk] - pp[0] - 0.5 * Rho * uu[0] * uu[0]) / scale;
  end;

begin
  for jn := 0 to High(J) do
  begin
    m := J[jn].NV;
    if m = 0 then Continue;
    if J[jn].HasInflow and Assigned(Inflow) then Qin := Inflow(Time + 0.5 * dt) else Qin := 0;
    for k := 0 to m - 1 do
    begin
      Ve := J[jn].V[k];
      if J[jn].AtEnd[k] then
      begin
        i := Ve.NNode - 1; b := i - 1; Sg[k] := 1;
      end
      else
      begin
        i := 0; b := 1; Sg[k] := -1;
      end;
      u := Ve.Q[i] / Ve.A[i]; c := Ve.Speed(i);
      WStar[k] := u + Sg[k] * 4 * (c - Ve.C0[i]);
      Bet[k] := Ve.Beta[i]; Cz[k] := Ve.C0[i]; Az[k] := Ve.A0[i];
      x[k] := Ve.A[i];
    end;
    scale := Rho * Cz[0] * Cz[0];
    for it := 1 to 30 do
    begin
      Resid(x, r);
      for k := 0 to m - 1 do
      begin
        h := 1e-7 * x[k];
        x[k] := x[k] + h;
        Resid(x, r1);
        x[k] := x[k] - h;
        for i := 0 to m - 1 do Jm[i, k] := (r1[i] - r[i]) / h;
      end;
      for i := 0 to m - 1 do dx_[i] := -r[i];
      for k := 0 to m - 1 do
      begin
        p := k; big := Abs(Jm[k, k]);
        for i := k + 1 to m - 1 do
          if Abs(Jm[i, k]) > big then begin big := Abs(Jm[i, k]); p := i; end;
        if p <> k then
        begin
          for i := 0 to m - 1 do begin f := Jm[k, i]; Jm[k, i] := Jm[p, i]; Jm[p, i] := f; end;
          f := dx_[k]; dx_[k] := dx_[p]; dx_[p] := f;
        end;
        for i := k + 1 to m - 1 do
        begin
          f := Jm[i, k] / Jm[k, k];
          for b := k to m - 1 do Jm[i, b] := Jm[i, b] - f * Jm[k, b];
          dx_[i] := dx_[i] - f * dx_[k];
        end;
      end;
      for i := m - 1 downto 0 do
      begin
        for b := i + 1 to m - 1 do dx_[i] := dx_[i] - Jm[i, b] * dx_[b];
        dx_[i] := dx_[i] / Jm[i, i];
      end;
      nrm := 0;
      for k := 0 to m - 1 do
      begin
        x[k] := x[k] + dx_[k];
        if x[k] <= 0 then
          raise Exception.CreateFmt('Step : a vessel collapsed at junction %d, t = %.4f s', [jn, Time]);
        nrm := Max(nrm, Abs(dx_[k]) / x[k]);
      end;
      if nrm < 1e-12 then Break;
    end;
    Resid(x, r);
    J[jn].P := pp[0];
    J[jn].QLeak := J[jn].G * (pp[0] - J[jn].Pc);
    if J[jn].C > 0 then
      J[jn].Pc := (J[jn].Pc + dt / J[jn].C * (J[jn].QLeak + PV / J[jn].R2))
        / (1 + dt / (J[jn].C * J[jn].R2))
    else
      J[jn].Pc := PV;
    for k := 0 to m - 1 do
    begin
      Ve := J[jn].V[k];
      if J[jn].AtEnd[k] then b := 1 else b := 0;
      Ve.BndA[b] := x[k];
      Ve.BndQ[b] := x[k] * uu[k];
    end;
  end;
  for k := 0 to High(Vessels) do
  begin
    Vessels[k].Advance(dt, KR);
    Vessels[k].Relax(dt);
  end;
  Time := Time + dt;
end;

end.
