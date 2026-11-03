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

  BY STEPPING. The trapezoidal stepper from rest, cycle after cycle,
  until one cycle repeats the last. Independent of the harmonics, so the
  two check each other.

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
    same - a sweep of rate changes neither. }
  TResponseCache = class
  private
    FOmega : TDoubleArray;
    FOut : array of array[0..13] of Double;
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
    of VT or MaxCycles; returns the last cycle. }
function CycleByStepping(Sys : TDescriptorSystem; Th : TThorax;
  StepsPerCycle, MaxCycles : Integer; Tol : Double) : TCycle;
function Summarise(const C : TCycle; Th : TThorax) : TCycleSummary;

  { Complex response to one harmonic of the jet pattern with unit
    complex amplitude: returns X (real and imaginary). }
procedure HarmonicResponse(Sys : TDescriptorSystem; Th : TThorax; Omega : Double;
  out Xr, Xi : TVMobj);

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

function CycleByHarmonics(Sys : TDescriptorSystem; Th : TThorax;
  NHarm, NS : Integer; Cache : TResponseCache) : TCycle;
var
  n, k : Integer;
  w, th_, cr, ci, Per, cs, sn : Double;
  // per-sample accumulation of the outputs
  Acc : TCycle;
  R : array[0..13] of Double;   // the 7 outputs of X, real then imaginary

  procedure Response(Omega : Double);
  // the outputs of the unit response at Omega, from the cache if there
  var
    Xr, Xi : TVMobj;
    S : TCycle;
    idx, j : Integer;
  begin
    if (Cache <> nil) and Cache.Find(Omega, idx) then
    begin
      for j := 0 to 13 do R[j] := Cache.FOut[idx][j];
      Exit;
    end;
    HarmonicResponse(Sys, Th, Omega, Xr, Xi);
    Alloc(S, 2);
    Sample(S, 0, Th, Xr);
    Sample(S, 1, Th, Xi);
    for j := 0 to 1 do
    begin
      R[7 * j] := S.VL[j]; R[7 * j + 1] := S.Vdi[j]; R[7 * j + 2] := S.PA[j];
      R[7 * j + 3] := S.Pt[j]; R[7 * j + 4] := S.Ppl[j]; R[7 * j + 5] := S.Qaw[j];
      R[7 * j + 6] := S.Qua[j];
    end;
    if Cache <> nil then
    begin
      idx := Cache.Add(Omega);
      for j := 0 to 13 do Cache.FOut[idx][j] := R[j];
    end;
  end;

  procedure AddHarm(ar, ai, wn : Double);
  // adds Re((ar + i ai) X exp(i wn t)) at every sample; every output is
  // linear in X, so the product can be taken on the outputs
  var
    kk, j : Integer;
    Yr, Yi : array[0..6] of Double;
  begin
    for j := 0 to 6 do
    begin
      Yr[j] := R[j] * ar - R[7 + j] * ai;
      Yi[j] := R[j] * ai + R[7 + j] * ar;
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
  // mean, at a tiny frequency
  Response(2 * Pi * 1e-5);
  AddHarm(Th.P.Ti, 0, 0);
  for n := 1 to NHarm do
  begin
    w := 2 * Pi * Th.P.Freq * n;
    th_ := 2 * Pi * n * Th.P.Ti;
    cr := Sin(th_) / (2 * Pi * n);
    ci := -(1 - Cos(th_)) / (2 * Pi * n);
    Response(w);
    AddHarm(2 * cr, 2 * ci, w);
  end;
  Acc.Cycles := 0; Acc.Change := 0;
  Result := Acc;
end;

function CycleByStepping(Sys : TDescriptorSystem; Th : TThorax;
  StepsPerCycle, MaxCycles : Integer; Tol : Double) : TCycle;
var
  St : TTrapezoidStepper;
  X, B0, B1 : TVMobj;
  dt, t, vt, mx, mn, ch : Double;
  cyc, k : Integer;
  Prev : TDoubleArray;
begin
  dt := 1 / (Th.P.Freq * StepsPerCycle);
  Alloc(Result, StepsPerCycle);
  SetLength(Prev, StepsPerCycle);
  X := TVMobj.Create(Sys.N, 1);
  St := TTrapezoidStepper.Create(Sys, dt);
  try
    t := 0;
    // the forcing is sampled mid-step, so an edge falls between steps
    B0 := Th.Forcing(Sys, t + 0.5 * dt);
    for cyc := 1 to MaxCycles do
    begin
      for k := 0 to StepsPerCycle - 1 do
      begin
        Result.T[k] := k * dt;
        Sample(Result, k, Th, X);
        B1 := Th.Forcing(Sys, t + 0.5 * dt);
        X := St.Step(X, B1, B1);
        t := t + dt;
      end;
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
  if B0.Rows = 0 then ;
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
