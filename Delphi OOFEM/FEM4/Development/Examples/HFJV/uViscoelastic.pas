unit uViscoelastic;

{ Constant-phase viscoelasticity as a finite set of relaxations, for the
  HFJV model's tissues (uThorax) and abdominal contents (uAbdomenFluid).

  A material whose dissipation is a fixed fraction eta (the hysteresivity)
  of its elastic storage at every frequency has the impedance (force per
  unit rate)

      Z(w) = A (i w)^(-alpha),   alpha = (2/pi) atan(1/eta)

  (Hantos et al. 1992): the resistance Re Z falls as w^-alpha, the dynamic
  stiffness -w Im Z rises slowly as w^(1-alpha). A is set so the stiffness
  at FRef is E.

  The fractional power is a positive spectrum of relaxations,

      (i w)^-alpha = (sin(alpha pi)/pi) int s^-alpha / (s + i w) ds ,

  and sampled at PerDecade points a decade in ln s between FMin and FMax
  each is a dashpot R_k in series with a spring, R_k / (1 + i w tau_k):
  one state p_k with tau_k p_k' + p_k = R_k Q. The spectrum below FMin is
  a spring E_0 (the quasi-static stiffness), the part above FMax a
  dashpot R_inf. Every term is positive, so the bank is passive and the
  same in the frequency and time domains. The units are whatever E's are:
  cmH2O/L for a tissue in uThorax, Pa/m for a foundation per unit area. }

{$mode delphi}{$H+}

interface

uses SysUtils, Math;

type
  { E_0 x + R_inf x' + sum p_k, tau_k p_k' + p_k = R_k x'. }
  TTissue = record
    E0, Rinf : Double;
    R, Tau : array of Double;
    Alpha, A : Double;      // the constant-phase Z = A (i w)^-alpha it stands for
  end;

{ Eta <= 0: the plain spring E with dashpot R, no relaxations. }
function MakeTissue(E, R, Eta, FRef, FMin, FMax : Double; PerDecade : Integer) : TTissue;
{ Z at w (rad/s): the bank's, or with Exact the constant-phase one. }
procedure TissueImpedance(const T : TTissue; w : Double; out Re, Im : Double; Exact : Boolean = False);

implementation

function MakeTissue(E, R, Eta, FRef, FMin, FMax : Double; PerDecade : Integer) : TTissue;
var
  wr, C, smin, smax, d, sk : Double;
  k, n : Integer;
begin
  if Eta <= 0 then
  begin
    Result.E0 := E; Result.Rinf := R;
    Result.R := nil; Result.Tau := nil;
    Result.Alpha := 1; Result.A := E;
    Exit;
  end;
  Assert((FRef > 0) and (FMin > 0) and (FMax > FMin) and (PerDecade > 0),
    'MakeTissue : bad constant-phase range');
  Result.Alpha := 2 / Pi * ArcTan(1 / Eta);
  wr := 2 * Pi * FRef;
  // stiffness -w Im Z = A sin(alpha pi/2) w^(1-alpha) is E at wr
  Result.A := E / Sin(Result.Alpha * Pi / 2) * Power(wr, Result.Alpha - 1);
  C := Result.A * Sin(Result.Alpha * Pi) / Pi;
  smin := 2 * Pi * FMin; smax := 2 * Pi * FMax;
  n := Round(Log10(smax / smin) * PerDecade);
  d := Ln(10) / PerDecade;
  SetLength(Result.R, n); SetLength(Result.Tau, n);
  for k := 0 to n - 1 do
  begin
    sk := smin * Power(10, (k + 0.5) / PerDecade);
    Result.R[k] := C * d * Power(sk, -Result.Alpha);
    Result.Tau[k] := 1 / sk;
  end;
  Result.E0 := C * Power(smin, 1 - Result.Alpha) / (1 - Result.Alpha);
  Result.Rinf := C * Power(smax, -Result.Alpha) / Result.Alpha;
end;

procedure TissueImpedance(const T : TTissue; w : Double; out Re, Im : Double; Exact : Boolean);
var
  k : Integer;
  m, ph, d : Double;
begin
  if Exact and (Length(T.R) > 0) then
  begin
    // A (i w)^-alpha = A w^-alpha (cos - i sin)(alpha pi/2)
    m := T.A * Power(w, -T.Alpha);
    ph := T.Alpha * Pi / 2;
    Re := m * Cos(ph); Im := -m * Sin(ph);
  end
  else
  begin
    Re := T.Rinf; Im := -T.E0 / w;
    for k := 0 to High(T.R) do
    begin
      d := 1 + Sqr(w * T.Tau[k]);
      Re := Re + T.R[k] / d;
      Im := Im - T.R[k] * w * T.Tau[k] / d;
    end;
  end;
end;

end.
