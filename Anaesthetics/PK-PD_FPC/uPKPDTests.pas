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
// Domino et al. Clin Pharmacol Ther 36:645-653, 1991, human kinetic set -
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

initialization
  RegisterTest(TPKPDTests);
end.
