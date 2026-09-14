unit uPKPDTests;

{*******************************************************************************

     FPCUnit sanity tests for the ported PK/PD engine (uBodyStats.pas,
     uModel3Comp.pas, uKapsRentrop.pas). Not exhaustive - covers the known-
     value/cross-check style newVMTests.pas already uses for the underlying
     library (e.g. A*Invert(A)~=I): per-model V1/V2/V3 against the source
     drug table, a bolus initial condition, an eigendecomposition round trip,
     and Kaps-Rentrop vs RKF45 agreement on the same linear system.

     Run via the console test runner in PKPDtest.lpr.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Math,
  newVM, newVMComplex, uBodyStats, uModel3Comp, uKapsRentrop, utypes;

type

  { TPKPDTests }

  TPKPDTests = class(TTestCase)
  published
    procedure TestBMIKnownValue;
    procedure TestIBWKnownValue;
    procedure TestMarshV1V2V3;
    procedure TestKetamineDominoV1V2V3;
    procedure TestEleveldCe50KnownValue;
    procedure TestBolusInitialCondition;
    procedure TestEigenRoundTrip;
    procedure TestAnalyticVsRK4Agree;
    procedure TestKapsRentropVsRK45Agree;
    procedure TestLinkedInfusionRateMatches;
    procedure TestBolusInfusionCombinedInitialCondition;
    procedure TestConstantInfusionMatchesArbitraryInfusion;
    procedure TestExtraBolusAddsToConstPlasmaSolve;
    procedure TestExtraBolusAddsToArbitraryInfusion;
    procedure TestConstPlasmaHoldsTarget;
    procedure TestConstEffectHoldsTarget;
  end;

implementation

const
  Tol = 1e-6;

procedure TPKPDTests.TestBMIKnownValue;
begin
  // 70kg / (1.75m)^2 = 22.857...
  AssertTrue(Abs(BMI(70, 1.75) - 22.857142857) < 1e-6);
end;

procedure TPKPDTests.TestIBWKnownValue;
begin
  // round(22 * 1.75^2) = round(67.375) = 67
  AssertEquals(67, IBW(1.75, Male));
end;

procedure TPKPDTests.TestMarshV1V2V3;
var
  M : TM3Comp;
begin
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    AssertTrue(Abs(M.fModelParams.V1 - 0.228*70) < Tol);
    AssertTrue(Abs(M.fModelParams.V2 - 0.464*70) < Tol);
    AssertTrue(Abs(M.fModelParams.V3 - 2.89*70) < Tol);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestKetamineDominoV1V2V3;
// Domino et al. Clin Pharmacol Ther 36:645-653, 1984, human kinetic set -
// see Anaesthetics/PK-PD_FPC/DRUGS.C's ketamine()/kinetic_set=1.
var
  M : TM3Comp;
  V1 : Double;
begin
  M := TM3Comp.Create(Ketamine, Domino, 70, 1.75, 35, Male);
  try
    V1 := 0.063*70;
    AssertTrue(Abs(M.fModelParams.V1 - V1) < Tol);
    AssertTrue(Abs(M.fModelParams.V2 - V1*0.592/0.247) < Tol);
    AssertTrue(Abs(M.fModelParams.V3 - V1*0.590/0.0146) < Tol);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestEleveldCe50KnownValue;
var
  M : TM3Comp;
begin
  // Ce50 = Prop_Phi1 * exp(Prop_Phi7*(age-age_ref)) - independent of drug/model,
  // computed for every propofol model in TM3Comp.Create.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    AssertTrue(Abs(M.fModelParams.Ce50 - calc_Ce50(35)) < Tol);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestBolusInitialCondition;
var
  M : TM3Comp;
  R : TVMobj;
begin
  // First column of every bolus solve is [Bolus/V1, 0, 0, 0] at t=0.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := M.RK4_init_bolus_solve(140, 5, 10);
    AssertTrue(Abs(R[0,0]) < Tol);                       // t=0
    AssertTrue(Abs(R[1,0] - 140/M.fModelParams.V1) < 1e-4); // C1(0) = Bolus/V1
    AssertTrue(Abs(R[2,0]) < Tol);                        // C2(0) = 0
    AssertTrue(Abs(R[3,0]) < Tol);                        // C3(0) = 0
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestEigenRoundTrip;
var
  M : TM3Comp;
  Lhs, Rhs : TVMobj;
  r, c : Integer;
begin
  // DiffMatrix * EigenVecs ~= EigenVecs * Diag(Eigenvals)
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    Lhs := MatMult(M.fModelParams.DiffMatrix, M.fModelParams.EigenVecs);
    Rhs := MatMult(M.fModelParams.EigenVecs, Diag(M.fModelParams.Eigenvals));
    for r := 0 to 3 do
      for c := 0 to 3 do
        AssertTrue(Abs(Lhs[r,c] - Rhs[r,c]) < 1e-6);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestAnalyticVsRK4Agree;
var
  M : TM3Comp;
  A, N : TVMobj;
  i : Integer;
begin
  // The analytic (eigendecomposition-based) and RK4 numeric bolus solves
  // should agree closely at every sampled time point.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    A := M.Analytic_initBolus_solve(140, 5, 10);
    N := M.RK4_init_bolus_solve(140, 5, 10);
    AssertEquals(A.Cols, N.Cols);
    for i := 0 to A.Cols-1 do
      AssertTrue(Abs(A[1,i] - N[1,i]) < 1e-3);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestKapsRentropVsRK45Agree;
var
  M : TM3Comp;
  K, R : TVMobj;
begin
  // Kaps-Rentrop (stiff, implicit) and RKF45 (non-stiff, explicit) should
  // land on close to the same final plasma concentration for the same bolus.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    K := M.kaps_init_bolus_solve(140, 5, 10);
    R := M.RK45_init_bolus_solve(140, 5, 10);
    AssertTrue(Abs(K[0, K.Cols-1] - R[1, R.Cols-1]) < 5e-3);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestLinkedInfusionRateMatches;
var
  A : TM3Comp;
  R : TVMobj;
  Rate : TVMobj;
  i : Integer;
begin
  // The rate row a const-plasma solve reports (row 1) is exactly what a
  // rate-slaved second model would be driven with - the "Linked TCI"
  // feature's core data flow.
  A := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := A.RK45_const_plasma_solve(0, 2.5, 10, 10, 10);
    Rate := SubMatrix(R, 1, 0, 1, R.Cols);
    for i := 0 to R.Cols-1 do
      AssertTrue(Abs(Rate[0,i] - R[1,i]) < Tol);
  finally
    A.Free;
  end;
end;

procedure TPKPDTests.TestBolusInfusionCombinedInitialCondition;
var
  M : TM3Comp;
  R : TVMobj;
begin
  // RK45_bolus_infusion_solve's t=0 column must still show the bolus as the
  // initial condition (row layout: 0=time,1=rate,2..4=C1/C2/C3), exactly as
  // the plain bolus solves do, even though an infusion is also running.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := M.RK45_bolus_infusion_solve(140, 200, 5, 5, 10);
    AssertTrue(Abs(R[0,0]) < Tol);                           // t=0
    AssertTrue(Abs(R[2,0] - 140/M.fModelParams.V1) < 1e-4);  // C1(0) = Bolus/V1
    AssertTrue(Abs(R[3,0]) < Tol);                            // C2(0) = 0
    AssertTrue(Abs(R[4,0]) < Tol);                            // C3(0) = 0
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestConstantInfusionMatchesArbitraryInfusion;
var
  M : TM3Comp;
  R, Arb, RateVec : TVMobj;
  i, NumSteps : Integer;
begin
  // A pure constant-rate infusion (Bolus=0) via RK45_bolus_infusion_solve
  // should agree with the same fixed rate fed through Arbitrary_Infusion -
  // two different code paths computing the same physical scenario.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := M.RK45_bolus_infusion_solve(0, 200, 5, 5, 10);
    NumSteps := Round(5*60/10);
    RateVec := TVMobj.Create(1, NumSteps);
    for i := 0 to NumSteps-1 do RateVec[0,i] := 200;
    Arb := M.Arbitrary_Infusion(RateVec, 0, 5, 10);
    AssertEquals(R.Cols, Arb.Cols);
    for i := 0 to R.Cols-1 do
      AssertTrue(Abs(R[2,i] - Arb[2,i]) < 1e-3);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestExtraBolusAddsToConstPlasmaSolve;
var
  M : TM3Comp;
  R0, R50 : TVMobj;
begin
  // The UI's "Bolus" field is threaded into every infusion-type regimen's
  // own Extra_Bolus/ExtraBolus parameter rather than being a separate
  // dropdown entry - RK45_const_plasma_solve's t=0 C1 should therefore
  // shift by exactly ExtraBolus/V1 when a non-zero Extra_Bolus is passed.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R0 := M.RK45_const_plasma_solve(0, 2.5, 5, 5, 10);
    R50 := M.RK45_const_plasma_solve(50, 2.5, 5, 5, 10);
    AssertTrue(Abs((R50[2,0] - R0[2,0]) - 50/M.fModelParams.V1) < Tol);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestExtraBolusAddsToArbitraryInfusion;
var
  M : TM3Comp;
  RateVec, R0, R50 : TVMobj;
  i, NumSteps : Integer;
begin
  // Same check as TestExtraBolusAddsToConstPlasmaSolve, for
  // Arbitrary_Infusion's new ExtraBolus parameter (which
  // Bristol_10_8_6_Infusion/Bristol_12_9_6_Infusion also forward into) -
  // ExtraBolus is a direct mg dose, added on top of the mL-based Bolus
  // this method already scales by Concentration internally.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    NumSteps := Round(5*60/10);
    RateVec := TVMobj.Create(1, NumSteps);
    for i := 0 to NumSteps-1 do RateVec[0,i] := 200;
    R0 := M.Arbitrary_Infusion(RateVec, 20, 5, 10);
    R50 := M.Arbitrary_Infusion(RateVec, 20, 5, 10, 50);
    AssertTrue(Abs((R50[2,0] - R0[2,0]) - 50/M.fModelParams.V1) < Tol);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestConstPlasmaHoldsTarget;
var
  M : TM3Comp;
  R : TVMobj;
  i : Integer;
begin
  // The whole point of the "Constant Plasma Target" regimen: C1 (row 2)
  // must stay AT the target for the entire infusion, not just start there.
  // Regression test for a maintenance-rate formula that recovered the
  // peripheral amounts as M[1,0]*V2/M[2,0]*V3 instead of *V1 (see the
  // state-vector note above TM3Comp.diffY) - which over-subtracted the
  // return flow and let a 3 mcg/ml target sag to about 1.6 by 60 minutes,
  // while still looking plausible over the first minute or two.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := M.RK45_const_plasma_solve(0, 3.0, 60, 60, 10);
    for i := 0 to R.Cols-1 do
      AssertTrue('Cp drifted off target at t='+FloatToStr(R[0,i])+
        ' min: '+FloatToStr(R[2,i]), Abs(R[2,i] - 3.0) < 0.01);
  finally
    M.Free;
  end;
end;

procedure TPKPDTests.TestConstEffectHoldsTarget;
var
  M : TM3Comp;
  R : TVMobj;
  i : Integer;
begin
  // Companion to TestConstPlasmaHoldsTarget for the "Constant Effect
  // Target" regimen, which drives the same maintenance-rate formula: the
  // effect-site concentration Ce (row 5) peaks at the target at t=Tau (the
  // loading bolus is sized for exactly that by calc_eff_init_bolus), and
  // the infusion then has to hold it there. Only checked from 20 min on,
  // well past Tau plus the plasma/effect equilibration that follows it.
  M := TM3Comp.Create(Propofol, Marsh, 70, 1.75, 35, Male);
  try
    R := M.RK45_const_effect_solve(0, 3.0, 60, 60, 10);
    for i := 0 to R.Cols-1 do
      if R[0,i] >= 20 then
        AssertTrue('Ce drifted off target at t='+FloatToStr(R[0,i])+
          ' min: '+FloatToStr(R[5,i]), Abs(R[5,i] - 3.0) < 0.05);
  finally
    M.Free;
  end;
end;

initialization
  RegisterTest(TPKPDTests);
end.
