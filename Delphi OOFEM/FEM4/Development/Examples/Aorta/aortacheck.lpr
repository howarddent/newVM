program aortacheck;

{ Checks of uArtery1D against exact results:
    1  a tapering vessel at rest stays at rest
    2  a small pulse travels at c0 with p = Zc q, and a matched end
       (R = Zc = rho c / A) reflects nothing
    3  an end resistance R reflects (R - Zc)/(R + Zc)
    4  a bifurcation transmits 2 Y0 / (Y0 + Y1 + Y2), Y = A / (rho c)
    5  steady flow loses rho K_R Q / A^2 of pressure per unit length
    6  volume is conserved: inflow less outflow is the change of volume
    7  with a Kelvin-Voigt wall a small sine wave has the wavenumber
       (w/c) / sqrt(1 + i w tau): its decay and its phase speed

  Build:  fpc -O2 -FUlib aortacheck.lpr }

{$mode delphi}{$H+}

uses
  SysUtils, StrUtils, Math, uArtery1D;

type
  TPulse = class
    Peak, T0, Width, Steady: Double;
    function Flow(t: Double): Double;
  end;

function TPulse.Flow(t: Double): Double;
begin
  Result := Steady + Peak * Exp(-Sqr((t - T0) / Width));
end;

type
  TSine = class
    Peak, Freq: Double;
    function Flow(t: Double): Double;
  end;

function TSine.Flow(t: Double): Double;
begin
  Result := Peak * Sin(2 * Pi * Freq * t);
end;

var
  Fails: Integer = 0;

procedure Check(const What: string; Value, Expected, Tol: Double);
var
  ok: Boolean;
begin
  ok := Abs(Value - Expected) <= Tol;
  if not ok then Inc(Fails);
  Writeln(Format('  %-58s %12.5g  (expected %.5g +- %.2g)  %s',
    [What, Value, Expected, Tol, IfThen(ok, 'ok', 'FAILED')]));
end;

{ a uniform vessel's radius whose Reymond wave speed is what it is; Zc }
function Zc(V: TVessel): Double;
begin
  Result := Rho * V.C0[0] / V.A0[0];
end;

procedure RestCase;
var
  T: TArterialTree;
  i, k: Integer;
  qm, am: Double;
begin
  Writeln('1  Tapering vessel at rest, closed at both ends');
  T := TArterialTree.Create;
  T.AddVessel('taper', 0, 1, 30, 1.4, 0.5, True);
  T.Build(0.5, 1, 1, 1);
  for i := 1 to 5000 do T.Step(1e-4);
  qm := 0; am := 0;
  with T.Vessels[0] do
    for k := 0 to NNode - 1 do
    begin
      qm := Max(qm, Abs(Q[k])); am := Max(am, Abs(A[k] / A0[k] - 1));
    end;
  Check('largest flow after 0.5 s, mL/s', qm, 0, 1e-9);
  Check('largest relative change of area', am, 0, 1e-12);
  T.Free;
end;

procedure PulseCase(RFactor: Double; const Title: string);
var
  T: TArterialTree;
  Pu: TPulse;
  V: TVessel;
  dt, z, pk1, tk1, pk2, p, c, tm: Double;
begin
  Writeln(Title);
  T := TArterialTree.Create;
  T.KR := 0;
  V := T.AddVessel('tube', 0, 1, 100, 1.0, 1.0, False);
  T.AddLeak(1, 'end', 1);
  T.SetInlet(0);
  T.Build(0.5, 1, 1, 1);
  z := Zc(V); c := V.C0[0];
  T.J[1].G := 1 / (RFactor * z);
  T.PV := T.P0;   { so the end resistance carries no flow at rest }
  T.Reset;
  Pu := TPulse.Create;
  Pu.Peak := 1; Pu.T0 := 0.05; Pu.Width := 0.012; Pu.Steady := 0;
  T.Inflow := Pu.Flow;
  dt := T.StableDt(0.5);
  pk1 := 0; tk1 := 0; pk2 := 0;
  tm := 50 / c;   { travel time to the middle }
  while T.Time < 0.05 + 3.6 * tm do
  begin
    T.Step(dt);
    p := V.PressureAt(0.5) - T.P0;
    if T.Time < 0.05 + 2 * tm then
    begin
      if p > pk1 then begin pk1 := p; tk1 := T.Time; end;
    end
    else if Abs(p) > Abs(pk2) then pk2 := p;
  end;
  Check('pulse reaches the middle after, ms', 1000 * (tk1 - 0.05), 1000 * tm, 0.3);
  Check('its height over Zc x the flow pulse', pk1 / z, 1, 0.01);
  Check('reflected over incident', pk2 / pk1, (RFactor - 1) / (RFactor + 1), 0.01);
  Pu.Free; T.Free;
end;

procedure BifurcationCase;
var
  T: TArterialTree;
  Pu: TPulse;
  V0, V1, V2: TVessel;
  dt, y0, y1, y2, pk0, pk1, pkr, p, tm: Double;
begin
  Writeln('4  Bifurcation: one vessel into two smaller ones, all ends matched');
  T := TArterialTree.Create;
  T.KR := 0;
  V0 := T.AddVessel('parent', 0, 1, 60, 1.0, 1.0, False);
  V1 := T.AddVessel('daughter 1', 1, 2, 60, 0.6, 0.6, False);
  V2 := T.AddVessel('daughter 2', 1, 3, 60, 0.45, 0.45, False);
  T.AddLeak(2, 'end', 1); T.AddLeak(3, 'end', 1);
  T.SetInlet(0);
  T.Build(0.5, 1, 1, 1);
  T.J[2].G := 1 / Zc(V1); T.J[3].G := 1 / Zc(V2);
  T.PV := T.P0;
  T.Reset;
  y0 := 1 / Zc(V0); y1 := 1 / Zc(V1); y2 := 1 / Zc(V2);
  Pu := TPulse.Create;
  Pu.Peak := 1; Pu.T0 := 0.05; Pu.Width := 0.012; Pu.Steady := 0;
  T.Inflow := Pu.Flow;
  dt := T.StableDt(0.5);
  pk0 := 0; pk1 := 0; pkr := 0;
  tm := 30 / V0.C0[0];
  while T.Time < 0.05 + 3.8 * tm do
  begin
    T.Step(dt);
    p := V0.PressureAt(0.5) - T.P0;
    if T.Time < 0.05 + 2 * tm then pk0 := Max(pk0, p)
    else if Abs(p) > Abs(pkr) then pkr := p;
    pk1 := Max(pk1, V1.PressureAt(0.3) - T.P0);
  end;
  Check('transmitted over incident', pk1 / pk0, 2 * y0 / (y0 + y1 + y2), 0.01);
  Check('reflected over incident', pkr / pk0, (y0 - y1 - y2) / (y0 + y1 + y2), 0.01);
  Pu.Free; T.Free;
end;

procedure SteadyCase;
var
  T: TArterialTree;
  Pu: TPulse;
  V: TVessel;
  dt, vol0, vin, vout, q: Double;
begin
  Writeln('5, 6  Steady flow through a uniform vessel; volume balance');
  T := TArterialTree.Create;
  V := T.AddVessel('tube', 0, 1, 40, 0.3, 0.3, False);
  T.AddLeak(1, 'end', 1);
  T.SetInlet(0);
  T.Build(0.5, 1, 1, 1);
  T.J[1].G := 1 / Zc(V);
  T.PV := T.P0;
  T.Reset;
  Pu := TPulse.Create;
  Pu.Peak := 0; Pu.T0 := 0; Pu.Width := 1; Pu.Steady := 0;
  T.Inflow := Pu.Flow;
  dt := T.StableDt(0.5);
  vol0 := T.Volume; vin := 0; vout := 0;
  while T.Time < 1.5 do
  begin
    { the flow is brought up smoothly to 5 mL/s over 0.2 s }
    if T.Time + dt < 0.2 then Pu.Steady := 5 * Sqr(Sin(0.5 * Pi * (T.Time + dt) / 0.2)) else Pu.Steady := 5;
    T.Step(dt);
    vin := vin + dt * Pu.Steady;
    vout := vout + dt * T.J[1].QLeak;
  end;
  q := V.FlowAt(0.5);
  Check('flow at the middle, mL/s', q, 5, 1e-4);
  Check('pressure gradient over rho K_R Q / A^2',
    (V.PressureAt(0.25) - V.PressureAt(0.75)) / 20 / (Rho * T.KR * q / Sqr(V.A[V.NNode div 2])), 1, 0.01);
  Check('volume in - out - stored, over volume in', (vin - vout - (T.Volume - vol0)) / vin, 0, 2e-3);
  Pu.Free; T.Free;
end;

procedure ViscousCase;
const
  Tau = 0.005; Freq = 8; X1 = 20; X2 = 60; L = 200;
var
  T: TArterialTree;
  Sn: TSine;
  V: TVessel;
  dt, c, w, th, m, kr_, al, t0, t1, p: Double;
  s1, c1, s2, c2, a1, a2, dph: Double;
begin
  Writeln('7  Sine wave in a uniform vessel with a viscoelastic wall');
  T := TArterialTree.Create;
  T.KR := 0;
  T.WallTau := Tau;
  V := T.AddVessel('tube', 0, 1, L, 1.0, 1.0, False);
  T.AddLeak(1, 'end', 1);
  T.SetInlet(0);
  T.Build(0.5, 1, 1, 1);
  c := V.C0[0];
  T.J[1].G := 1 / Zc(V);
  T.PV := T.P0;
  T.Reset;
  Sn := TSine.Create; Sn.Peak := 1; Sn.Freq := Freq;
  T.Inflow := Sn.Flow;
  w := 2 * Pi * Freq;
  th := ArcTan(w * Tau); m := Power(1 + Sqr(w * Tau), -0.25);
  kr_ := w / c * m * Cos(th / 2); al := w / c * m * Sin(th / 2);
  dt := T.StableDt(0.5);
  { two whole periods, after the start has passed and before the far
    end's reflection returns }
  t0 := 0.375; t1 := t0 + 2 / Freq;
  s1 := 0; c1 := 0; s2 := 0; c2 := 0;
  while T.Time < t1 do
  begin
    T.Step(dt);
    if T.Time > t0 then
    begin
      p := V.PressureAt(X1 / L) - T.P0;
      s1 := s1 + p * Sin(w * T.Time); c1 := c1 + p * Cos(w * T.Time);
      p := V.PressureAt(X2 / L) - T.P0;
      s2 := s2 + p * Sin(w * T.Time); c2 := c2 + p * Cos(w * T.Time);
    end;
  end;
  a1 := Sqrt(s1 * s1 + c1 * c1); a2 := Sqrt(s2 * s2 + c2 * c2);
  dph := ArcTan2(c1, s1) - ArcTan2(c2, s2);
  while dph < 0 do dph := dph + 2 * Pi;
  Check('amplitude at 60 cm over that at 20 cm', a2 / a1, Exp(-al * (X2 - X1)), 0.01);
  Check('phase lag over 40 cm, rad', dph, kr_ * (X2 - X1), 0.02);
  Check('phase speed over c0', w * (X2 - X1) / dph / c, w / kr_ / c, 0.005);
  Sn.Free; T.Free;
end;

begin
  FormatSettings.DecimalSeparator := '.';
  RestCase;
  PulseCase(1, '2  Small pulse in a uniform vessel with a matched end');
  PulseCase(3, '3  The same with an end resistance of 3 Zc');
  BifurcationCase;
  SteadyCase;
  ViscousCase;
  Writeln;
  if Fails = 0 then Writeln('All checks passed.') else Writeln(Fails, ' check(s) FAILED.');
  if Fails > 0 then Halt(1);
end.
