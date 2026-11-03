unit uHFJVSolve;

{ The steady ventilator cycle, two ways, and what it means for the
  patient.

  BY HARMONICS. The jet is a square pulse on for the first Ti of each
  period T, so its forcing is the pattern b times

      s(t) = Ti + sum_n 2 Re( c_n exp(i n w t) ),
      c_n  = (1 - exp(-i 2 pi n Ti)) / (i 2 pi n)
           = (sin(2 pi n Ti) - i (1 - cos(2 pi n Ti))) / (2 pi n).

  Each harmonic is one complex solve, (i n w E - A) X_n = 2 c_n b, and
  the cycle is their sum. The mean (n = 0) is solved at a tiny
  frequency rather than at zero: the incompressible abdomen's volume
  constraint lives in the velocities, and at exactly zero frequency it
  drops out and leaves the system singular. In the limit the answer is
  the quasi-static one, which is what the mean is. Smooth quantities -
  the volumes - converge fast in n; the tracheal pressure jumps with the
  jet and shows Gibbs ringing at the edges.

  THE TURBULENT UPPER AIRWAY. Its loss -K |Q_ua| Q_ua is a forcing s(t)
  on one row (uThorax), so the cycle is the jet's linear response plus
  the linear response to s, and only Q_ua has to be found
  self-consistently. On M = 8 NHarm samples of the cycle,

      q = q_jet + L s(q),    s = -K |q| q,

  where q_jet is the jet's response and L maps samples of s to samples
  of Q_ua through the upper airway's own transfer function H_n
  (harmonics 0..NHarm): L is circulant, with first column
  l_d = (H_0 + sum_n 2 Re(H_n exp(i n w t_d))) / M. That is harmonic
  balance on one unknown, solved by Newton with the dense M x M
  Jacobian I + 2K L diag|q| - a few iterations. The other outputs then
  add their own response to s's harmonics. H_n costs a second
  right-hand side on each frequency's factorisation, kept in the cache.

  BY STEPPING. The trapezoidal stepper from rest, cycle after cycle,
  until one cycle repeats the last. Independent of the harmonics, so the
  two check each other. The turbulent loss is trapezoidal too: its old
  value goes into the step's right-hand side, and the new state is the
  linear step plus g times half the new value, where g is the step
  matrix's answer to a unit forcing on the upper airway's row. Q_ua then
  satisfies q + c |q| q = q_0 (c = K g_ua / 2), a quadratic solved in
  closed form, so the stepping is exact for the nonlinear system.

  THE FIGURES OF MERIT. The tidal volume VT is the swing in lung volume.
  At these frequencies it is near or below the dead space, so gas
  exchange is by augmented dispersion rather than bulk flow, and the
  usual index of CO2 elimination is f VT^2 (Slutsky et al. 1981, and
  much HFJV work since), reported in L^2/s alongside VT/VD. The mean
  alveolar pressure is the hyperinflation the jet causes; entrainment is
  the volume per cycle drawn in through the upper airway. }

{$mode delphi}{$H+}

interface

uses SysUtils, Math, newVM, newVMsparse, uDescriptor, uThorax;

type
  TCycle = record
    T : TDoubleArray;                       // s
    VL, Vdi, PA, Pt, Ppl, Qaw, Qua : TDoubleArray; // SI
    Cycles : Integer;                       // stepping: cycles run
    UAIter : Integer;                       // harmonics: Newton iterations for the upper airway
    Change : Double;                        // stepping: last-cycle change in VL, rel. to VT
  end;

  TCycleSummary = record
    VT, VTdi : Double;          // L; of which diaphragm (peak-to-peak of V_di)
    VLmean : Double;            // L
    PAmean, PAmax, PAmin : Double;   // cmH2O
    Ptmean, Ptmax : Double;     // cmH2O
    PplMean : Double;           // cmH2O
    JetVol, EntrainVol, ExhaledVol : Double; // L per cycle
    FVT2 : Double;              // L^2/s
    VTVD : Double;
  end;

  { The outputs CycleByHarmonics needs from each frequency's response,
    kept so that a sweep of rate solves each frequency once: harmonic n
    of one rate is often harmonic m of another (3 x 200 = 1 x 600 /min).
    Valid only while the system and the jet's forcing pattern stay the
    same - a sweep of rate changes neither. Holds the response to the
    jet's pattern (0..13) and to a unit forcing on the upper airway's row
    (14..27). }
  TResponseCache = class
  private
    FOmega : TDoubleArray;
    FOut : array of array[0..27] of Double;
  public
    function Find(Omega : Double; out Idx : Integer) : Boolean;
    function Add(Omega : Double) : Integer;
    procedure Clear;
  end;

  { Forced by the jet's harmonics 1..NHarm, sampled at NS points per
    cycle. Cache may be nil. }
function CycleByHarmonics(Sys : TDescriptorSystem; Th : TThorax;
  NHarm, NS : Integer; Cache : TResponseCache = nil) : TCycle;
  { Stepped from rest, StepsPerCycle per cycle, until VL repeats to Tol
    of VT or MaxCycles; returns the last cycle. After every cycle the
    state is shifted so that its mean over the cycle is the near-DC
    response to the cycle's mean forcing (jet plus turbulent loss): for
    a periodic trapezoidal cycle that holds exactly, so the steady state
    is unchanged, but the slow tissue relaxations (time constants up to
    minutes) no longer have to settle by stepping. }
function CycleByStepping(Sys : TDescriptorSystem; Th : TThorax;
  StepsPerCycle, MaxCycles : Integer; Tol : Double) : TCycle;
function Summarise(const C : TCycle; Th : TThorax) : TCycleSummary;

  { Complex response to one harmonic of the jet pattern with unit
    complex amplitude: returns X (real and imaginary). }
procedure HarmonicResponse(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  out Xr, Xi : TVMobj);
  { The jet's response and the response to a unit forcing on the upper
    airway's row, on one factorisation. }
procedure HarmonicResponses(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  out Xr, Xi, Ur, Ui : TVMobj);
  { The upper airway's turbulent loss over the steady cycle, as the
    forcing s(t) = S0 + sum_n 2 Re((Sr[n] + i Si[n]) exp(i n w t)) on its
    row (index 0 of Sr, Si unused), found by harmonic balance. Zero when
    K_ua = 0. Returns the Newton iterations. }
function UpperAirwaySource(Sys : TDescriptorSystem; Th : TThorax; NHarm : Integer;
  Cache : TResponseCache; out S0 : Double; out Sr, Si : TDoubleArray) : Integer;

implementation

function TResponseCache.Find(Omega : Double; out Idx : Integer) : Boolean;
var
  i : Integer;
begin
  for i := 0 to High(FOmega) do
    if Abs(FOmega[i] - Omega) <= 1e-9 * Omega then
    begin
      Idx := i;
      Exit(True);
    end;
  Idx := -1;
  Result := False;
end;

function TResponseCache.Add(Omega : Double) : Integer;
begin
  Result := Length(FOmega);
  SetLength(FOmega, Result + 1);
  SetLength(FOut, Result + 1);
  FOmega[Result] := Omega;
end;

procedure TResponseCache.Clear;
begin
  FOmega := nil;
  FOut := nil;
end;

procedure HarmonicResponse(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  out Xr, Xi : TVMobj);
var
  B, Z : TVMobj;
begin
  B := Th.ForcingPattern(Sys);
  Z := TVMobj.Create(Sys.N, 1);
  Sys.SolveFrequency(Omega, B, Z, Xr, Xi);
end;

procedure HarmonicResponses(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  out Xr, Xi, Ur, Ui : TVMobj);
var
  Z : TVMobj;
  R, I : TVMobjArray;
begin
  Z := TVMobj.Create(Sys.N, 1);
  Sys.SolveFrequencyN(Omega, [Th.ForcingPattern(Sys), Th.UAPattern(Sys)], [Z, Z], R, I);
  Xr := R[0]; Xi := I[0];
  Ur := R[1]; Ui := I[1];
end;

procedure Sample(var C : TCycle; k : Integer; Th : TThorax; const X : TVMobj);
begin
  C.VL[k] := Th.VL(X);
  C.Vdi[k] := Th.Vdi(X);
  C.PA[k] := X.DataPtr[Th.iPA];
  C.Pt[k] := X.DataPtr[Th.iPt];
  C.Ppl[k] := X.DataPtr[Th.iPpl];
  C.Qaw[k] := X.DataPtr[Th.iQaw];
  C.Qua[k] := X.DataPtr[Th.iQua];
end;

procedure Alloc(var C : TCycle; NS : Integer);
begin
  SetLength(C.T, NS); SetLength(C.VL, NS); SetLength(C.Vdi, NS);
  SetLength(C.PA, NS); SetLength(C.Pt, NS); SetLength(C.Ppl, NS);
  SetLength(C.Qaw, NS); SetLength(C.Qua, NS);
end;

type
  TResp = array[0..27] of Double;
  TRespArray = array of TResp;

{ The outputs of both unit responses at Omega, from the cache if there. }
procedure GetResponse(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  Cache : TResponseCache; out R : TResp);
var
  Xr, Xi, Ur, Ui : TVMobj;
  S : TCycle;
  idx, j, h : Integer;
begin
  if (Cache <> nil) and Cache.Find(Omega, idx) then
  begin
    for j := 0 to 27 do R[j] := Cache.FOut[idx][j];
    Exit;
  end;
  HarmonicResponses(Sys, Th, Omega, Xr, Xi, Ur, Ui);
  Alloc(S, 4);
  Sample(S, 0, Th, Xr);
  Sample(S, 1, Th, Xi);
  Sample(S, 2, Th, Ur);
  Sample(S, 3, Th, Ui);
  for h := 0 to 3 do
  begin
    j := 7 * h;
    R[j] := S.VL[h]; R[j + 1] := S.Vdi[h]; R[j + 2] := S.PA[h];
    R[j + 3] := S.Pt[h]; R[j + 4] := S.Ppl[h]; R[j + 5] := S.Qaw[h];
    R[j + 6] := S.Qua[h];
  end;
  if Cache <> nil then
  begin
    idx := Cache.Add(Omega);
    for j := 0 to 27 do Cache.FOut[idx][j] := R[j];
  end;
end;

{ The responses at the mean (a tiny frequency) and harmonics 1..NHarm. }
function AllResponses(Sys : TDescriptorSystem; Th : TThorax; NHarm : Integer;
  Cache : TResponseCache) : TRespArray;
var
  n : Integer;
begin
  SetLength(Result, NHarm + 1);
  GetResponse(Sys, Th, 2 * Pi * 1e-5, Cache, Result[0]);
  for n := 1 to NHarm do
    GetResponse(Sys, Th, 2 * Pi * Th.P.Freq * n, Cache, Result[n]);
end;

{ The jet's square pulse: s(t) = Ti + sum_n 2 Re(c_n exp(i n w t)). }
procedure JetCoef(Th : TThorax; n : Integer; out cr, ci : Double);
var
  th_ : Double;
begin
  th_ := 2 * Pi * n * Th.P.Ti;
  cr := Sin(th_) / (2 * Pi * n);
  ci := -(1 - Cos(th_)) / (2 * Pi * n);
end;

{ Harmonic balance on Q_ua: see the header. }
function BalanceUA(Th : TThorax; NHarm : Integer; const Resp : TRespArray;
  out S0 : Double; out Sr, Si : TDoubleArray) : Integer;
const
  MaxIter = 60;
var
  M, n, k, j, it : Integer;
  w, Kt, Per, cr, ci, t, mx, step : Double;
  q, qj, l, sv : TDoubleArray;
  Jac, Rhs : TVMobj;
  Done : Boolean;
begin
  SetLength(Sr, NHarm + 1);
  SetLength(Si, NHarm + 1);
  S0 := 0;
  Result := 0;
  Kt := Th.KuaSI;
  if Kt <= 0 then
    Exit;
  M := 8 * NHarm;
  w := 2 * Pi * Th.P.Freq;
  Per := 1 / Th.P.Freq;
  SetLength(q, M); SetLength(qj, M); SetLength(l, M); SetLength(sv, M);
  // the jet's Q_ua, and L's first column
  for k := 0 to M - 1 do
  begin
    t := Per * k / M;
    qj[k] := Th.P.Ti * Resp[0][6];
    l[k] := Resp[0][20];
    for n := 1 to NHarm do
    begin
      JetCoef(Th, n, cr, ci);
      qj[k] := qj[k] + 2 * ((cr * Resp[n][6] - ci * Resp[n][13]) * Cos(n * w * t)
                          - (cr * Resp[n][13] + ci * Resp[n][6]) * Sin(n * w * t));
      l[k] := l[k] + 2 * (Resp[n][20] * Cos(n * w * t) - Resp[n][27] * Sin(n * w * t));
    end;
    l[k] := l[k] / M;
  end;
  // Newton on F(q) = q - qj - L s(q) = 0
  q := Copy(qj);
  Done := False;
  for it := 1 to MaxIter do
  begin
    Result := it;
    for k := 0 to M - 1 do
      sv[k] := -Kt * Abs(q[k]) * q[k];
    Jac := TVMobj.Create(M, M);
    Rhs := TVMobj.Create(M, 1);
    mx := 0;
    for k := 0 to M - 1 do
    begin
      Rhs.DataPtr[k] := qj[k] - q[k];
      for j := 0 to M - 1 do
      begin
        Rhs.DataPtr[k] := Rhs.DataPtr[k] + l[(k - j + M) mod M] * sv[j];
        Jac.DataPtr[k * M + j] := 2 * Kt * l[(k - j + M) mod M] * Abs(q[j]);
      end;
      Jac.DataPtr[k * M + k] := Jac.DataPtr[k * M + k] + 1;
      mx := Max(mx, Abs(q[k]));
    end;
    if LinearSolve(Jac, Rhs) <> 0 then
      raise Exception.Create('BalanceUA : singular Jacobian');
    step := 0;
    for k := 0 to M - 1 do
    begin
      q[k] := q[k] + Rhs.DataPtr[k];
      step := Max(step, Abs(Rhs.DataPtr[k]));
    end;
    if step <= 1e-10 * Max(mx, 1e-9) then
    begin
      Done := True;
      Break;
    end;
  end;
  if not Done then
    raise Exception.Create('BalanceUA : the upper airway''s harmonic balance did not converge');
  // s's harmonics
  for k := 0 to M - 1 do
    sv[k] := -Kt * Abs(q[k]) * q[k];
  for n := 0 to NHarm do
  begin
    Sr[n] := 0; Si[n] := 0;
    for k := 0 to M - 1 do
    begin
      t := Per * k / M;
      Sr[n] := Sr[n] + sv[k] * Cos(n * w * t);
      Si[n] := Si[n] - sv[k] * Sin(n * w * t);
    end;
    Sr[n] := Sr[n] / M;
    Si[n] := Si[n] / M;
  end;
  S0 := Sr[0];
end;

function UpperAirwaySource(Sys : TDescriptorSystem; Th : TThorax; NHarm : Integer;
  Cache : TResponseCache; out S0 : Double; out Sr, Si : TDoubleArray) : Integer;
begin
  if Th.KuaSI <= 0 then
  begin
    SetLength(Sr, NHarm + 1);
    SetLength(Si, NHarm + 1);
    S0 := 0;
    Exit(0);
  end;
  Result := BalanceUA(Th, NHarm, AllResponses(Sys, Th, NHarm, Cache), S0, Sr, Si);
end;

function CycleByHarmonics(Sys : TDescriptorSystem; Th : TThorax;
  NHarm, NS : Integer; Cache : TResponseCache) : TCycle;
var
  n, k : Integer;
  w, cr, ci, Per, cs, sn, S0 : Double;
  Acc : TCycle;
  Resp : TRespArray;
  Sr, Si : TDoubleArray;

  // adds Re((ar + i ai) X exp(i wn t)) at every sample, X being the
  // response whose outputs start at R[o]; every output is linear in X,
  // so the product can be taken on the outputs
  procedure AddHarm(const R : TResp; o : Integer; ar, ai, wn : Double);
  var
    kk, j : Integer;
    Yr, Yi : array[0..6] of Double;
  begin
    for j := 0 to 6 do
    begin
      Yr[j] := R[o + j] * ar - R[o + 7 + j] * ai;
      Yi[j] := R[o + j] * ai + R[o + 7 + j] * ar;
    end;
    for kk := 0 to NS - 1 do
    begin
      cs := Cos(wn * Acc.T[kk]); sn := Sin(wn * Acc.T[kk]);
      Acc.VL[kk] := Acc.VL[kk] + Yr[0] * cs - Yi[0] * sn;
      Acc.Vdi[kk] := Acc.Vdi[kk] + Yr[1] * cs - Yi[1] * sn;
      Acc.PA[kk] := Acc.PA[kk] + Yr[2] * cs - Yi[2] * sn;
      Acc.Pt[kk] := Acc.Pt[kk] + Yr[3] * cs - Yi[3] * sn;
      Acc.Ppl[kk] := Acc.Ppl[kk] + Yr[4] * cs - Yi[4] * sn;
      Acc.Qaw[kk] := Acc.Qaw[kk] + Yr[5] * cs - Yi[5] * sn;
      Acc.Qua[kk] := Acc.Qua[kk] + Yr[6] * cs - Yi[6] * sn;
    end;
  end;

begin
  Per := 1 / Th.P.Freq;
  Alloc(Acc, NS);
  for k := 0 to NS - 1 do Acc.T[k] := Per * k / NS;
  Resp := AllResponses(Sys, Th, NHarm, Cache);
  // the jet
  AddHarm(Resp[0], 0, Th.P.Ti, 0, 0);
  for n := 1 to NHarm do
  begin
    w := 2 * Pi * Th.P.Freq * n;
    JetCoef(Th, n, cr, ci);
    AddHarm(Resp[n], 0, 2 * cr, 2 * ci, w);
  end;
  // the upper airway's turbulent loss
  Acc.UAIter := BalanceUA(Th, NHarm, Resp, S0, Sr, Si);
  if Acc.UAIter > 0 then
  begin
    AddHarm(Resp[0], 14, S0, 0, 0);
    for n := 1 to NHarm do
      AddHarm(Resp[n], 14, 2 * Sr[n], 2 * Si[n], 2 * Pi * Th.P.Freq * n);
  end;
  Acc.Cycles := 0; Acc.Change := 0;
  Result := Acc;
end;

function CycleByStepping(Sys : TDescriptorSystem; Th : TThorax;
  StepsPerCycle, MaxCycles : Integer; Tol : Double) : TCycle;
var
  St : TTrapezoidStepper;
  X, B0, B1, G : TVMobj;
  dt, t, vt, mx, mn, ch, Kt, c, q0, q, sNew, sOld, sSum, onSum : Double;
  cyc, k, i : Integer;
  Prev, XSum : TDoubleArray;
  Dr, Di : TVMobjArray;
  Z : TVMobj;
begin
  dt := 1 / (Th.P.Freq * StepsPerCycle);
  Alloc(Result, StepsPerCycle);
  SetLength(Prev, StepsPerCycle);
  X := TVMobj.Create(Sys.N, 1);
  Kt := Th.KuaSI;
  St := TTrapezoidStepper.Create(Sys, dt);
  try
    // how the new state answers to the turbulent loss at the new time
    // (half of it, the trapezoidal weight): q + c |q| q = q_0
    G := St.Solve(Th.UAPattern(Sys));
    c := 0.5 * Kt * G.DataPtr[Th.iQua];
    if (Kt > 0) and (c <= 0) then
      raise Exception.Create('CycleByStepping : the upper airway''s step response has the wrong sign');
    // near-DC responses to the jet's pattern and to a unit loss, at the
    // harmonic method's mean frequency
    Z := TVMobj.Create(Sys.N, 1);
    Sys.SolveFrequencyN(2 * Pi * 1e-5, [Th.ForcingPattern(Sys), Th.UAPattern(Sys)], [Z, Z], Dr, Di);
    SetLength(XSum, Sys.N);
    t := 0;
    for cyc := 1 to MaxCycles do
    begin
      for i := 0 to Sys.N - 1 do XSum[i] := 0;
      sSum := 0; onSum := 0;
      for k := 0 to StepsPerCycle - 1 do
      begin
        Result.T[k] := k * dt;
        Sample(Result, k, Th, X);
        for i := 0 to Sys.N - 1 do XSum[i] := XSum[i] + X.DataPtr[i];
        // the forcing is sampled mid-step, so an edge falls between steps
        B1 := Th.Forcing(Sys, t + 0.5 * dt);
        if Th.JetOn(t + 0.5 * dt) then onSum := onSum + 1;
        if Kt > 0 then
        begin
          // the old loss on the right-hand side (B0's half of it)
          B0 := Th.Forcing(Sys, t + 0.5 * dt);
          sOld := Th.UASource(X.DataPtr[Th.iQua]);
          B0.DataPtr[Th.iQua] := sOld;
          X := St.Step(X, B0, B1);
          q0 := X.DataPtr[Th.iQua];
          q := Sign(q0) * (Sqrt(1 + 4 * c * Abs(q0)) - 1) / (2 * c);
          sNew := Th.UASource(q);
          for i := 0 to Sys.N - 1 do
            X.DataPtr[i] := X.DataPtr[i] + 0.5 * sNew * G.DataPtr[i];
          sSum := sSum + 0.5 * (sOld + sNew);
        end
        else
          X := St.Step(X, B1, B1);
        t := t + dt;
      end;
      // shift the mean onto the near-DC response to the mean forcing
      for i := 0 to Sys.N - 1 do
        X.DataPtr[i] := X.DataPtr[i] + onSum / StepsPerCycle * Dr[0].DataPtr[i]
          + sSum / StepsPerCycle * Dr[1].DataPtr[i] - XSum[i] / StepsPerCycle;
      mx := MaxValue(Result.VL); mn := MinValue(Result.VL);
      vt := Max(mx - mn, 1e-30);
      ch := 0;
      if cyc > 1 then
        for k := 0 to StepsPerCycle - 1 do
          ch := Max(ch, Abs(Result.VL[k] - Prev[k]) / vt);
      Prev := Copy(Result.VL);
      Result.Cycles := cyc;
      Result.Change := ch;
      if (cyc > 2) and (ch < Tol) then Break;
    end;
  finally
    St.Free;
  end;
end;

function Summarise(const C : TCycle; Th : TThorax) : TCycleSummary;
var
  k, n : Integer;
  dt : Double;
begin
  n := Length(C.T);
  dt := 1 / (Th.P.Freq * n);
  with Result do
  begin
    VT := (MaxValue(C.VL) - MinValue(C.VL)) / Litre;
    VTdi := (MaxValue(C.Vdi) - MinValue(C.Vdi)) / Litre;
    VLmean := Mean(C.VL) / Litre;
    PAmean := Mean(C.PA) / cmH2O;
    PAmax := MaxValue(C.PA) / cmH2O;
    PAmin := MinValue(C.PA) / cmH2O;
    Ptmean := Mean(C.Pt) / cmH2O;
    Ptmax := MaxValue(C.Pt) / cmH2O;
    PplMean := Mean(C.Ppl) / cmH2O;
    JetVol := Th.QOn * Th.P.Ti / Th.P.Freq / Litre;
    EntrainVol := 0; ExhaledVol := 0;
    for k := 0 to n - 1 do
      if C.Qua[k] < 0 then EntrainVol := EntrainVol - C.Qua[k] * dt
      else ExhaledVol := ExhaledVol + C.Qua[k] * dt;
    EntrainVol := EntrainVol / Litre;
    ExhaledVol := ExhaledVol / Litre;
    FVT2 := Th.P.Freq * Sqr(VT);
    VTVD := VT / Th.P.VD;
  end;
end;

end.
