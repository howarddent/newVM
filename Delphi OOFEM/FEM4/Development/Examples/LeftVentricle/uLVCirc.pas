unit uLVCirc;

{ The lumped circulation round the finite-element left ventricle: what
  fills it and what it ejects into. Units here are the physiologist's:
  mL, mmHg, s (areas cm2, lengths cm).

     pulmonary veins (p_pv) --R_pv--> left atrium --mitral valve--> LV
     LV --aortic valve--> aortic root (C_root) --L_ao, Z_c--> Windkessel
     (C_wk, R_p) --> p_out

  LEFT ATRIUM   p_LA = E(t) (V_LA - V0), E between EMin and EMax with a
     sin^2 atrial systole AtrialLead before the ventricle's activation.

  VALVES   Mynard, Davidson, Penny & Smolich 2012 (Int J Numer Meth
     Biomed Eng 28:626): an orifice of area zeta A with Bernoulli loss
     and inertance,
        dp = B q|q| + L dq/dt,  B = rho/(2 (zeta A)^2), L = rho l/(zeta A)
     and an opening state zeta in 0..1 driven by the pressure difference,
        dzeta/dt = (1 - zeta) Kvo dp   (dp > 0)
        dzeta/dt =      zeta  Kvc dp   (dp < 0).
     Rate coefficients and effective lengths are Mynard & Smolich 2015's
     (Ann Biomed Eng 43:1443), except the aortic valve's closing: with
     Mynard's law the closing slows as zeta falls, the backflow (2.0 mL,
     54 mL/s) is choked off over 22 ms and the root's pressure shows a
     notch of only 1 mmHg. The aortic valve instead closes as
        dzeta/dt = sqrt(zeta) Kvc dp   (SnapShut),
     shut in a finite time, with Kvc 16 chosen for a closing volume of
     2.4 mL (70 mL/s, cut off in 10 ms). A closed valve keeps LeakZeta of its area,
     so B stays finite; the leak is of order 0.01 mL/s.

  AORTIC ROOT AND AFTERLOAD   the root is a compliance (sinuses to the
     sinotubular junction), then the inertance and characteristic
     impedance of the proximal aorta into a two-element Windkessel. The
     later aorta model replaces everything beyond the root; (p_root,
     q_ao) is the interface.

  STEPPING   backward Euler. For a given new LV pressure the valves'
  zeta and q are closed-form functions of their pressure differences,
  which leaves four unknowns (V_LA, p_root, q_ao, p_wk) for a small
  Newton iteration with a finite-difference Jacobian. Trial does this
  without changing the state, so the ventricle's Newton iteration can
  call it at will; Commit accepts the last Trial. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math;

const
  mmHg = 0.133322; { kPa }
  RhoBlood = 1.06; { g/mL }

type
  TValve = record
    Area: Double;     { fully open effective area, cm2 }
    Len: Double;      { effective length, cm }
    Kvo, Kvc: Double; { opening, closing rate coefficients, 1/(mmHg s) }
    { closing as dzeta/dt = sqrt(zeta) Kvc dp: sqrt(zeta) falls at a rate
      that does not slacken as the valve nears shut, so it shuts in a
      finite time and the backflow is cut off, not choked slowly }
    SnapShut: Boolean;
    Zeta, Q: Double;  { state: opening 0..1, flow mL/s }
  end;

  TCircState = record
    VLA, PRoot, QAo, PWk: Double;
    ZMV, QMV, ZAV, QAV: Double;
  end;

  TLVCirc = class
  private
    FTrial: TCircState;
    FTrialOK: Boolean;
    procedure ValveStep(const V: TValve; dp, dt: Double; out Zeta, Q: Double);
    procedure Residual(const y: array of Double; PLV, t, dt: Double;
      var r: array of Double; out S: TCircState);
  public
    { parameters }
    Period: Double;               { cardiac cycle, s }
    PPv, RPv: Double;             { pulmonary venous pressure and resistance }
    LAV0, LAEMin, LAEMax: Double; { left atrium }
    AtrialLead, AtrialDur: Double;
    Mitral, Aortic: TValve;
    CRoot, LAo, Zc: Double;       { aortic root and proximal aorta }
    CWk, Rp, POut: Double;        { Windkessel }
    LeakZeta: Double;
    { state }
    S: TCircState;
    constructor Create;
    function LAElastance(t: Double): Double;
    function PLA(t: Double): Double; overload;
    function PLA(t, VLA: Double): Double; overload;
    { Net flow into the ventricle (mitral less aortic), mL/s, over a
      step dt ending at time t with the ventricle at PLV. }
    function Trial(PLV, t, dt: Double): Double;
    function TrialSlope(PLV, t, dt: Double; out QNet: Double): Double;
    procedure Commit(PLV, t, dt: Double);
  end;

implementation

constructor TLVCirc.Create;
begin
  inherited Create;
  Period := 60 / 70;
  PPv := 9.9; RPv := 0.03;
  LAV0 := 10; LAEMin := 0.18; LAEMax := 0.32;
  AtrialLead := 0.16; AtrialDur := 0.20;
  Mitral.Area := 5.1; Mitral.Len := 2.0; Mitral.Kvo := 26.7; Mitral.Kvc := 53.3;
  Aortic.Area := 4.0; Aortic.Len := 1.0; Aortic.Kvo := 26.7; Aortic.Kvc := 16; Aortic.SnapShut := True;
  CRoot := 0.08; LAo := 3.4e-4; Zc := 0.057;
  CWk := 1.9; Rp := 1.09; POut := 0;
  LeakZeta := 1e-5;
  S.VLA := 55; S.PRoot := 80; S.QAo := 0; S.PWk := 80;
  S.ZMV := 0; S.QMV := 0; S.ZAV := 0; S.QAV := 0;
end;

function TLVCirc.LAElastance(t: Double): Double;
var
  tau: Double;
begin
  { time since atrial activation, which starts AtrialLead before t = 0 }
  tau := t + AtrialLead;
  tau := tau - Period * Floor(tau / Period);
  if tau < AtrialDur then
    Result := LAEMin + (LAEMax - LAEMin) * Sqr(Sin(Pi * tau / AtrialDur))
  else
    Result := LAEMin;
end;

function TLVCirc.PLA(t, VLA: Double): Double;
begin
  Result := LAElastance(t) * (VLA - LAV0);
end;

function TLVCirc.PLA(t: Double): Double;
begin
  Result := PLA(t, S.VLA);
end;

procedure TLVCirc.ValveStep(const V: TValve; dp, dt: Double; out Zeta, Q: Double);
var
  ae, B, L, a, r: Double;
begin
  if dp > 0 then
    Zeta := (V.Zeta + dt * V.Kvo * dp) / (1 + dt * V.Kvo * dp)
  else if V.SnapShut then
    Zeta := Sqr(Max(0, Sqrt(V.Zeta) + 0.5 * dt * V.Kvc * dp))
  else
    Zeta := V.Zeta / (1 - dt * V.Kvc * dp);
  ae := V.Area * Max(Zeta, LeakZeta);
  B := RhoBlood / (2 * ae * ae) / 1333.22;
  L := RhoBlood * V.Len / ae / 1333.22;
  { L (q - q0)/dt + B q|q| = dp }
  a := L / dt;
  r := dp + a * V.Q;
  Q := 2 * r / (a + Sqrt(a * a + 4 * B * Abs(r)));
end;

procedure TLVCirc.Residual(const y: array of Double; PLV, t, dt: Double;
  var r: array of Double; out S: TCircState);
var
  V: TValve;
  pla_: Double;
begin
  S.VLA := y[0]; S.PRoot := y[1]; S.QAo := y[2]; S.PWk := y[3];
  pla_ := PLA(t, S.VLA);
  V := Mitral; V.Zeta := Self.S.ZMV; V.Q := Self.S.QMV;
  ValveStep(V, pla_ - PLV, dt, S.ZMV, S.QMV);
  V := Aortic; V.Zeta := Self.S.ZAV; V.Q := Self.S.QAV;
  ValveStep(V, PLV - S.PRoot, dt, S.ZAV, S.QAV);
  r[0] := S.VLA - Self.S.VLA - dt * ((PPv - pla_) / RPv - S.QMV);
  r[1] := CRoot * (S.PRoot - Self.S.PRoot) - dt * (S.QAV - S.QAo);
  r[2] := LAo * (S.QAo - Self.S.QAo) - dt * (S.PRoot - S.PWk - Zc * S.QAo);
  r[3] := CWk * (S.PWk - Self.S.PWk) - dt * (S.QAo - (S.PWk - POut) / Rp);
end;

function TLVCirc.Trial(PLV, t, dt: Double): Double;
const
  N = 4;
var
  y, r, r1, y1, dy: array[0..N - 1] of Double;
  Jm: array[0..N - 1, 0..N - 1] of Double;
  St: TCircState;
  it, i, j, k, p: Integer;
  h, big, f, nrm: Double;
begin
  y[0] := S.VLA; y[1] := S.PRoot; y[2] := S.QAo; y[3] := S.PWk;
  FTrialOK := False;
  for it := 1 to 60 do
  begin
    Residual(y, PLV, t, dt, r, St);
    nrm := 0;
    for i := 0 to N - 1 do nrm := Max(nrm, Abs(r[i]));
    if nrm < 1e-11 then begin FTrialOK := True; Break; end;
    for j := 0 to N - 1 do
    begin
      y1 := y;
      h := 1e-7 * Max(1, Abs(y[j]));
      y1[j] := y[j] + h;
      Residual(y1, PLV, t, dt, r1, St);
      for i := 0 to N - 1 do Jm[i, j] := (r1[i] - r[i]) / h;
    end;
    { Gaussian elimination with partial pivoting: Jm dy = -r }
    for i := 0 to N - 1 do dy[i] := -r[i];
    for k := 0 to N - 1 do
    begin
      p := k; big := Abs(Jm[k, k]);
      for i := k + 1 to N - 1 do
        if Abs(Jm[i, k]) > big then begin big := Abs(Jm[i, k]); p := i; end;
      if p <> k then
      begin
        for j := 0 to N - 1 do
        begin f := Jm[k, j]; Jm[k, j] := Jm[p, j]; Jm[p, j] := f; end;
        f := dy[k]; dy[k] := dy[p]; dy[p] := f;
      end;
      for i := k + 1 to N - 1 do
      begin
        f := Jm[i, k] / Jm[k, k];
        for j := k to N - 1 do Jm[i, j] := Jm[i, j] - f * Jm[k, j];
        dy[i] := dy[i] - f * dy[k];
      end;
    end;
    for i := N - 1 downto 0 do
    begin
      for j := i + 1 to N - 1 do dy[i] := dy[i] - Jm[i, j] * dy[j];
      dy[i] := dy[i] / Jm[i, i];
    end;
    nrm := 0;
    for i := 0 to N - 1 do
    begin
      y[i] := y[i] + dy[i];
      nrm := Max(nrm, Abs(dy[i]) / (1 + Abs(y[i])));
    end;
    if nrm < 1e-13 then begin FTrialOK := True; Break; end;
  end;
  Residual(y, PLV, t, dt, r, St);
  FTrial := St;
  Result := St.QMV - St.QAV;
end;

function TLVCirc.TrialSlope(PLV, t, dt: Double; out QNet: Double): Double;
const
  h = 1e-5;
begin
  Result := (Trial(PLV + h, t, dt) - Trial(PLV - h, t, dt)) / (2 * h);
  QNet := Trial(PLV, t, dt);
end;

procedure TLVCirc.Commit(PLV, t, dt: Double);
begin
  Trial(PLV, t, dt);
  if not FTrialOK then
    raise Exception.Create('TLVCirc.Commit : the circulation step did not converge');
  S := FTrial;
end;

end.
