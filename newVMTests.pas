unit newVMTests;

{*******************************************************************************

     FPCUnit test suite for the five TVMobj* types (newVM.pas, newVMSingle.pas,
     newVMComplex.pas, newVMComplexSingle.pas, newVMI.pas).

     One TTestCase per type - TVMobjTests / TVMobjSTests / TVMobjZTests /
     TVMobjCTests - covering: construction and dimension validation, Element
     get/set (including out-of-range and the non-square addressing that
     calcoffset* used to get wrong), writeMatrix, fillRandom, Id, DataPtr
     (real types only), CopyObj* independence, MatMult*, LinearSolve*, Invert*,
     every operator overload (+, -, unary -, *, /, =) including the assertion
     paths, and the elementwise VML functions (Sin/Cos/Tan/Sinh/Sqr/Sqrt/Exp/Ln).
     The two complex types additionally cover RealToComplex*/GetRealPart*/
     GetImagPart*/SplitComplex*, EigDecompose* (verified via A*v = lambda*v,
     not hard-coded eigenvectors, since LAPACK doesn't guarantee a particular
     sign/normalisation), and the mixed real/complex operators.

     TVMobjITests (newVMI.pas, integer index array/matrix) covers the same
     "core object shape" subset - construction, Element get/set, writeMatrix,
     fillRandom (now bounded: TVMobjI.fillRandom takes explicit loBound/
     hiBound, unlike the fixed N(0,1) fillRandom on the other four types),
     Id, DataPtr, CopyObjI, plus Transpose and linspace - but none of
     MatMult/LinearSolve/Invert/operators/VML functions, since newVMI has no
     equivalents (BLAS/LAPACK/VML don't operate on plain integers).

     Run via the console test runner in newVMtest.lpr.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry,
  OneAPI, newVM, newVMSingle, newVMComplex, newVMComplexSingle, newVMI;

type

  { TVMobjTests - newVM.pas, real double }

  TVMobjTests = class(TTestCase)
  private
    procedure Raise_CreateZeroRows;
    procedure Raise_CreateZeroCols;
    procedure Raise_CreateValuesMismatch;
    procedure Raise_ElementRowOutOfRange;
    procedure Raise_ElementColOutOfRange;
    procedure Raise_IdNonSquare;
    procedure Raise_MatMultDimMismatch;
    procedure Raise_LinearSolveNonSquare;
    procedure Raise_InvertNonSquare;
    procedure Raise_OperatorAddDimMismatch;
    procedure Raise_ScalarDivByZero;
  published
    procedure TestCreateZeroFills;
    procedure TestCreateInvalidDimsAssert;
    procedure TestCreateWithValues;
    procedure TestCreateWithValuesMismatchAsserts;
    procedure TestElementRoundTripNonSquare;
    procedure TestElementOutOfRangeAsserts;
    procedure TestWriteMatrixRowCount;
    procedure TestFillRandomDeterministic;
    procedure TestFillRandomNonZero;
    procedure TestIdIdentity;
    procedure TestIdNonSquareAsserts;
    procedure TestDataPtrAddressable;
    procedure TestCopyObjIndependence;
    procedure TestMatMultKnownValues;
    procedure TestMatMultDimMismatchAsserts;
    procedure TestLinearSolveRecoversRHS;
    procedure TestLinearSolveNonSquareAsserts;
    procedure TestInvertRecoversIdentity;
    procedure TestInvertNonSquareAsserts;
    procedure TestOperatorAddSub;
    procedure TestOperatorUnaryNeg;
    procedure TestOperatorMulIsElementwise;
    procedure TestOperatorScalarMulDiv;
    procedure TestOperatorScalarDivByZeroAsserts;
    procedure TestOperatorDimMismatchAsserts;
    procedure TestOperatorEquality;
    procedure TestElementwiseTrig;
    procedure TestElementwiseSqrtSqr;
    procedure TestElementwiseExpLnRoundTrip;
    procedure TestDCT1SelfInverseRoundTrip;
    procedure TestDCT2DCT3InverseRoundTrip;
    procedure TestDCT4SelfInverseRoundTrip;
    procedure TestDST1SelfInverseRoundTrip;
    procedure TestDST2DST3InverseRoundTrip;
    procedure TestDST4SelfInverseRoundTrip;
    procedure TestFindKnownValues;
    procedure TestKronKnownValues;
  end;

  { TVMobjSTests - newVMSingle.pas, real single }

  TVMobjSTests = class(TTestCase)
  private
    procedure Raise_CreateZeroRows;
    procedure Raise_CreateZeroCols;
    procedure Raise_CreateValuesMismatch;
    procedure Raise_ElementRowOutOfRange;
    procedure Raise_ElementColOutOfRange;
    procedure Raise_IdNonSquare;
    procedure Raise_MatMultDimMismatch;
    procedure Raise_LinearSolveNonSquare;
    procedure Raise_InvertNonSquare;
    procedure Raise_OperatorAddDimMismatch;
    procedure Raise_ScalarDivByZero;
  published
    procedure TestCreateZeroFills;
    procedure TestCreateInvalidDimsAssert;
    procedure TestCreateWithValues;
    procedure TestCreateWithValuesMismatchAsserts;
    procedure TestElementRoundTripNonSquare;
    procedure TestElementOutOfRangeAsserts;
    procedure TestWriteMatrixRowCount;
    procedure TestFillRandomDeterministic;
    procedure TestFillRandomNonZero;
    procedure TestIdIdentity;
    procedure TestIdNonSquareAsserts;
    procedure TestDataPtrAddressable;
    procedure TestCopyObjIndependence;
    procedure TestMatMultKnownValues;
    procedure TestMatMultDimMismatchAsserts;
    procedure TestLinearSolveRecoversRHS;
    procedure TestLinearSolveNonSquareAsserts;
    procedure TestInvertRecoversIdentity;
    procedure TestInvertNonSquareAsserts;
    procedure TestOperatorAddSub;
    procedure TestOperatorUnaryNeg;
    procedure TestOperatorMulIsElementwise;
    procedure TestOperatorScalarMulDiv;
    procedure TestOperatorScalarDivByZeroAsserts;
    procedure TestOperatorDimMismatchAsserts;
    procedure TestOperatorEquality;
    procedure TestElementwiseTrig;
    procedure TestElementwiseSqrtSqr;
    procedure TestElementwiseExpLnRoundTrip;
    procedure TestDCT1SelfInverseRoundTrip;
    procedure TestDCT2DCT3InverseRoundTrip;
    procedure TestDCT4SelfInverseRoundTrip;
    procedure TestDST1SelfInverseRoundTrip;
    procedure TestDST2DST3InverseRoundTrip;
    procedure TestDST4SelfInverseRoundTrip;
    procedure TestFindKnownValues;
    procedure TestKronKnownValues;
  end;

  { TVMobjZTests - newVMComplex.pas, complex double }

  TVMobjZTests = class(TTestCase)
  private
    procedure Raise_CreateZeroRows;
    procedure Raise_CreateZeroCols;
    procedure Raise_CreateValuesMismatch;
    procedure Raise_ElementRowOutOfRange;
    procedure Raise_ElementColOutOfRange;
    procedure Raise_IdNonSquare;
    procedure Raise_MatMultDimMismatch;
    procedure Raise_LinearSolveNonSquare;
    procedure Raise_InvertNonSquare;
    procedure Raise_OperatorAddDimMismatch;
    procedure Raise_ScalarDivByZero;
  published
    procedure TestCreateZeroFills;
    procedure TestCreateInvalidDimsAssert;
    procedure TestCreateWithValues;
    procedure TestCreateWithValuesMismatchAsserts;
    procedure TestElementRoundTripNonSquare;
    procedure TestElementOutOfRangeAsserts;
    procedure TestWriteMatrixRowCount;
    procedure TestFillRandomDeterministic;
    procedure TestFillRandomNonZero;
    procedure TestIdIdentity;
    procedure TestIdNonSquareAsserts;
    procedure TestCopyObjIndependence;
    procedure TestMatMultKnownValues;
    procedure TestMatMultDimMismatchAsserts;
    procedure TestLinearSolveRecoversRHS;
    procedure TestLinearSolveNonSquareAsserts;
    procedure TestInvertRecoversIdentity;
    procedure TestInvertNonSquareAsserts;
    procedure TestOperatorAddSub;
    procedure TestOperatorUnaryNeg;
    procedure TestOperatorMulIsElementwise;
    procedure TestOperatorScalarMulDiv;
    procedure TestOperatorScalarDivByZeroAsserts;
    procedure TestOperatorDimMismatchAsserts;
    procedure TestOperatorEquality;
    procedure TestElementwiseTrig;
    procedure TestElementwiseSqrtSqr;
    procedure TestElementwiseExpLnRoundTrip;
    procedure TestRealToComplexPromotion;
    procedure TestGetRealGetImagSplit;
    procedure TestEigDecomposeSatisfiesEigenEquation;
    procedure TestMixedOperatorsAddSub;
    procedure TestMixedOperatorMatMultKnownValue;
    procedure TestFFTR2CC2RRoundTrip;
    procedure TestFFTC2CRoundTrip;
    procedure TestFFTR2CKnownDCValue;
    procedure TestKronKnownValues;
  end;

  { TVMobjCTests - newVMComplexSingle.pas, complex single }

  TVMobjCTests = class(TTestCase)
  private
    procedure Raise_CreateZeroRows;
    procedure Raise_CreateZeroCols;
    procedure Raise_CreateValuesMismatch;
    procedure Raise_ElementRowOutOfRange;
    procedure Raise_ElementColOutOfRange;
    procedure Raise_IdNonSquare;
    procedure Raise_MatMultDimMismatch;
    procedure Raise_LinearSolveNonSquare;
    procedure Raise_InvertNonSquare;
    procedure Raise_OperatorAddDimMismatch;
    procedure Raise_ScalarDivByZero;
  published
    procedure TestCreateZeroFills;
    procedure TestCreateInvalidDimsAssert;
    procedure TestCreateWithValues;
    procedure TestCreateWithValuesMismatchAsserts;
    procedure TestElementRoundTripNonSquare;
    procedure TestElementOutOfRangeAsserts;
    procedure TestWriteMatrixRowCount;
    procedure TestFillRandomDeterministic;
    procedure TestFillRandomNonZero;
    procedure TestIdIdentity;
    procedure TestIdNonSquareAsserts;
    procedure TestCopyObjIndependence;
    procedure TestMatMultKnownValues;
    procedure TestMatMultDimMismatchAsserts;
    procedure TestLinearSolveRecoversRHS;
    procedure TestLinearSolveNonSquareAsserts;
    procedure TestInvertRecoversIdentity;
    procedure TestInvertNonSquareAsserts;
    procedure TestOperatorAddSub;
    procedure TestOperatorUnaryNeg;
    procedure TestOperatorMulIsElementwise;
    procedure TestOperatorScalarMulDiv;
    procedure TestOperatorScalarDivByZeroAsserts;
    procedure TestOperatorDimMismatchAsserts;
    procedure TestOperatorEquality;
    procedure TestElementwiseTrig;
    procedure TestElementwiseSqrtSqr;
    procedure TestElementwiseExpLnRoundTrip;
    procedure TestRealToComplexPromotion;
    procedure TestGetRealGetImagSplit;
    procedure TestEigDecomposeSatisfiesEigenEquation;
    procedure TestMixedOperatorsAddSub;
    procedure TestMixedOperatorMatMultKnownValue;
    procedure TestFFTR2CC2RRoundTrip;
    procedure TestFFTC2CRoundTrip;
    procedure TestFFTR2CKnownDCValue;
    procedure TestKronKnownValues;
  end;

  { TVMobjITests - newVMI.pas, integer index array/matrix }

  TVMobjITests = class(TTestCase)
  private
    procedure Raise_CreateZeroRows;
    procedure Raise_CreateZeroCols;
    procedure Raise_CreateValuesMismatch;
    procedure Raise_ElementRowOutOfRange;
    procedure Raise_ElementColOutOfRange;
    procedure Raise_IdNonSquare;
    procedure Raise_FillRandomBadBounds;
    procedure Raise_GatherNoMatches;
  published
    procedure TestCreateZeroFills;
    procedure TestCreateInvalidDimsAssert;
    procedure TestCreateWithValues;
    procedure TestCreateWithValuesMismatchAsserts;
    procedure TestElementRoundTripNonSquare;
    procedure TestElementOutOfRangeAsserts;
    procedure TestWriteMatrixRowCount;
    procedure TestFillRandomDeterministic;
    procedure TestFillRandomWithinBounds;
    procedure TestFillRandomBadBoundsAsserts;
    procedure TestIdIdentity;
    procedure TestIdNonSquareAsserts;
    procedure TestDataPtrAddressable;
    procedure TestCopyObjIndependence;
    procedure TestTransposeSwapsDimsAndElements;
    procedure TestLinspaceKnownValues;
    procedure TestGatherReturnsIndexes;
    procedure TestGatherNoMatchesAsserts;
  end;

implementation

const
  DblTol = 1e-8;
  DblSolveTol = 1e-6;
  SngTol = 1e-3;
  SngSolveTol = 2e-2;

{===========================================================================
  TVMobjTests  (real double)
===========================================================================}

procedure TVMobjTests.Raise_CreateZeroRows;
var X: TVMobj;
begin
  X := TVMobj.Create(0, 3);
end;

procedure TVMobjTests.Raise_CreateZeroCols;
var X: TVMobj;
begin
  X := TVMobj.Create(3, 0);
end;

procedure TVMobjTests.Raise_CreateValuesMismatch;
var X: TVMobj;
begin
  X := TVMobj.Create(2, 2, [1, 2, 3]);
end;

procedure TVMobjTests.Raise_ElementRowOutOfRange;
var X: TVMobj; V: Double;
begin
  X := TVMobj.Create(2, 2);
  V := X[2, 0];
end;

procedure TVMobjTests.Raise_ElementColOutOfRange;
var X: TVMobj; V: Double;
begin
  X := TVMobj.Create(2, 2);
  V := X[0, 2];
end;

procedure TVMobjTests.Raise_IdNonSquare;
var X: TVMobj;
begin
  X := TVMobj.Create(2, 3);
  X.Id;
end;

procedure TVMobjTests.Raise_MatMultDimMismatch;
var A, B: TVMobj;
begin
  A := TVMobj.Create(2, 3);
  B := TVMobj.Create(2, 2);
  A := MatMult(A, B);
end;

procedure TVMobjTests.Raise_LinearSolveNonSquare;
var A, B: TVMobj;
begin
  A := TVMobj.Create(2, 3);
  B := TVMobj.Create(2, 1);
  LinearSolve(A, B);
end;

procedure TVMobjTests.Raise_InvertNonSquare;
var A: TVMobj;
begin
  A := TVMobj.Create(2, 3);
  A := Invert(A);
end;

procedure TVMobjTests.Raise_OperatorAddDimMismatch;
var A, B, C: TVMobj;
begin
  A := TVMobj.Create(2, 2);
  B := TVMobj.Create(3, 3);
  C := A + B;
end;

procedure TVMobjTests.Raise_ScalarDivByZero;
var A, B: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  B := A / 0.0;
end;

procedure TVMobjTests.TestCreateZeroFills;
var A: TVMobj; r, c: Integer;
begin
  A := TVMobj.Create(2, 3);
  AssertEquals('Rows', 2, A.Rows);
  AssertEquals('Cols', 3, A.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do
      AssertEquals('zero-fill', 0.0, A[r, c], DblTol);
end;

procedure TVMobjTests.TestCreateInvalidDimsAssert;
begin
  AssertException('zero rows', EAssertionFailed, @Raise_CreateZeroRows);
  AssertException('zero cols', EAssertionFailed, @Raise_CreateZeroCols);
end;

procedure TVMobjTests.TestCreateWithValues;
var A: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  AssertEquals(1.0, A[0, 0], DblTol);
  AssertEquals(2.0, A[0, 1], DblTol);
  AssertEquals(3.0, A[1, 0], DblTol);
  AssertEquals(4.0, A[1, 1], DblTol);
end;

procedure TVMobjTests.TestCreateWithValuesMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_CreateValuesMismatch);
end;

procedure TVMobjTests.TestElementRoundTripNonSquare;
var A: TVMobj; r, c: Integer;
begin
  //3x4, distinct value per cell - regression test for the calcoffset fix:
  //the old formula collided whenever r*c matched another pair's product.
  A := TVMobj.Create(3, 4, [1,2,3,4, 5,6,7,8, 9,10,11,12]);
  for r := 0 to 2 do
    for c := 0 to 3 do
      AssertEquals(Format('[%d,%d]', [r, c]), r*4 + c + 1, A[r, c], DblTol);
end;

procedure TVMobjTests.TestElementOutOfRangeAsserts;
begin
  AssertException('row out of range', EAssertionFailed, @Raise_ElementRowOutOfRange);
  AssertException('col out of range', EAssertionFailed, @Raise_ElementColOutOfRange);
end;

procedure TVMobjTests.TestWriteMatrixRowCount;
var A: TVMobj; S: TStringList;
begin
  A := TVMobj.Create(3, 4);
  S := A.writeMatrix;
  try
    AssertEquals(3, S.Count);
  finally
    S.Free;
  end;
end;

procedure TVMobjTests.TestFillRandomDeterministic;
var A, B: TVMobj;
begin
  //fillRandom seeds a fresh VSL stream with a hard-coded seed (777) every
  //call, so two same-sized fills are bit-for-bit identical.
  A := TVMobj.Create(3, 3);
  A.fillRandom;
  B := TVMobj.Create(3, 3);
  B.fillRandom;
  AssertTrue(A = B);
end;

procedure TVMobjTests.TestFillRandomNonZero;
var A: TVMobj;
begin
  A := TVMobj.Create(3, 3);
  A.fillRandom;
  AssertFalse(A[0, 0] = 0.0);
end;

procedure TVMobjTests.TestIdIdentity;
var A: TVMobj; r, c: Integer;
begin
  A := TVMobj.Create(3, 3);
  A.Id;
  for r := 0 to 2 do
    for c := 0 to 2 do
      if r = c then
        AssertEquals(1.0, A[r, c], DblTol)
      else
        AssertEquals(0.0, A[r, c], DblTol);
end;

procedure TVMobjTests.TestIdNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_IdNonSquare);
end;

procedure TVMobjTests.TestDataPtrAddressable;
var A: TVMobj; P: PDouble;
begin
  A := TVMobj.Create(2, 2);
  P := A.DataPtr;
  P^ := 42.0;
  AssertEquals(42.0, A[0, 0], DblTol);
end;

procedure TVMobjTests.TestCopyObjIndependence;
var A, B: TVMobj;
begin
  A := TVMobj.Create(2, 2);
  A.fillRandom;
  B := CopyObj(A);
  AssertTrue(A = B);
  B[1, 1] := B[1, 1] + 1;
  AssertFalse(A = B);
end;

procedure TVMobjTests.TestMatMultKnownValues;
var A, B, C: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobj.Create(2, 2, [5, 6, 7, 8]);
  C := MatMult(A, B);
  AssertEquals(19.0, C[0, 0], DblTol);
  AssertEquals(22.0, C[0, 1], DblTol);
  AssertEquals(43.0, C[1, 0], DblTol);
  AssertEquals(50.0, C[1, 1], DblTol);
end;

procedure TVMobjTests.TestMatMultDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_MatMultDimMismatch);
end;

procedure TVMobjTests.TestLinearSolveRecoversRHS;
const N = 3;
var A, B, Akeep, Bkeep, X: TVMobj; info, i: Integer;
begin
  A := TVMobj.Create(N, N);
  A.fillRandom;
  B := TVMobj.Create(N, 1);
  B.fillRandom;
  Akeep := CopyObj(A);
  Bkeep := CopyObj(B);
  info := LinearSolve(A, B);   //B is overwritten with the solution x
  AssertEquals('LAPACKE_dgesv info', 0, info);
  X := MatMult(Akeep, B);
  for i := 0 to N-1 do
    AssertEquals(Format('row %d', [i]), Bkeep[i, 0], X[i, 0], DblSolveTol);
end;

procedure TVMobjTests.TestLinearSolveNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_LinearSolveNonSquare);
end;

procedure TVMobjTests.TestInvertRecoversIdentity;
const N = 3;
var A, Ainv, Akeep, X: TVMobj; r, c: Integer; expected: Double;
begin
  A := TVMobj.Create(N, N);
  A.fillRandom;
  Akeep := CopyObj(A);
  Ainv := Invert(A);
  //A itself must be left untouched by Invert
  for r := 0 to N-1 do
    for c := 0 to N-1 do
      AssertEquals(Format('A[%d,%d] unmutated', [r, c]), Akeep[r, c], A[r, c], DblTol);
  X := MatMult(Akeep, Ainv);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      if r = c then expected := 1.0 else expected := 0.0;
      AssertEquals(Format('(A*Ainv)[%d,%d]', [r, c]), expected, X[r, c], DblSolveTol);
    end;
end;

procedure TVMobjTests.TestInvertNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_InvertNonSquare);
end;

procedure TVMobjTests.TestOperatorAddSub;
var A, B, S1, D1: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobj.Create(2, 2, [5, 6, 7, 8]);
  S1 := A + B;
  AssertTrue(S1 = TVMobj.Create(2, 2, [6, 8, 10, 12]));
  D1 := A - B;
  AssertTrue(D1 = TVMobj.Create(2, 2, [-4, -4, -4, -4]));
end;

procedure TVMobjTests.TestOperatorUnaryNeg;
var A: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  AssertTrue(-A = TVMobj.Create(2, 2, [-1, -2, -3, -4]));
  AssertTrue(-(-A) = A);
end;

procedure TVMobjTests.TestOperatorMulIsElementwise;
var A, B: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobj.Create(2, 2, [5, 6, 7, 8]);
  AssertTrue(A * B = mulObj(A, B));
  AssertTrue(A * B = TVMobj.Create(2, 2, [5, 12, 21, 32]));
end;

procedure TVMobjTests.TestOperatorScalarMulDiv;
var A: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  AssertTrue(A * 2.0 = TVMobj.Create(2, 2, [2, 4, 6, 8]));
  AssertTrue(2.0 * A = A * 2.0);
  AssertTrue(A / 2.0 = TVMobj.Create(2, 2, [0.5, 1, 1.5, 2]));
end;

procedure TVMobjTests.TestOperatorScalarDivByZeroAsserts;
begin
  AssertException(EAssertionFailed, @Raise_ScalarDivByZero);
end;

procedure TVMobjTests.TestOperatorDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_OperatorAddDimMismatch);
end;

procedure TVMobjTests.TestOperatorEquality;
var A, B: TVMobj;
begin
  A := TVMobj.Create(3, 3);
  A.fillRandom;
  AssertTrue(A = A);
  B := CopyObj(A);
  AssertTrue(A = B);
  B[0, 0] := B[0, 0] + 1;
  AssertFalse(A = B);
  B := TVMobj.Create(3, 4);
  AssertFalse(A = B);
end;

procedure TVMobjTests.TestElementwiseTrig;
var A, S, C, T: TVMobj;
begin
  A := TVMobj.Create(1, 3, [0, Pi/6, Pi/2]);
  S := Sin(A);
  C := Cos(A);
  T := Tan(TVMobj.Create(1, 1, [Pi/4]));
  AssertEquals(0.0, S[0, 0], DblTol);
  AssertEquals(0.5, S[0, 1], DblTol);
  AssertEquals(1.0, S[0, 2], DblTol);
  AssertEquals(1.0, C[0, 0], DblTol);
  AssertEquals(Sqrt(3)/2, C[0, 1], DblTol);
  AssertEquals(0.0, C[0, 2], DblTol);
  AssertEquals(1.0, T[0, 0], DblTol);
end;

procedure TVMobjTests.TestElementwiseSqrtSqr;
var A, R: TVMobj;
begin
  A := TVMobj.Create(1, 2, [-3, 4]);
  R := Sqrt(Sqr(A));
  AssertEquals(3.0, R[0, 0], DblTol);
  AssertEquals(4.0, R[0, 1], DblTol);
  AssertEquals(0.0, Sinh(TVMobj.Create(1,1,[0]))[0, 0], DblTol);
end;

procedure TVMobjTests.TestElementwiseExpLnRoundTrip;
var A, R: TVMobj;
begin
  A := TVMobj.Create(1, 2, [1, 2.5]);
  R := Ln(Exp(A));
  AssertEquals(1.0, R[0, 0], DblTol);
  AssertEquals(2.5, R[0, 1], DblTol);
end;

{ DCT/DST round-trip tests: FFTW's r2r transforms are unnormalized, so each
  self-inverse or mutual-inverse pair must be scaled back down to recover
  the original vector - see the DCT1..DST4 comment in newVM.pas for the
  scale factor per kind. }

procedure TVMobjTests.TestDCT1SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT1(A);
  C := DCT1(B) / (2*(N-1));
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestDCT2DCT3InverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT2(A);
  C := DCT3(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestDCT4SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT4(A);
  C := DCT4(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestDST1SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST1(A);
  C := DST1(B) / (2*(N+1));
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestDST2DST3InverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST2(A);
  C := DST3(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestDST4SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobj; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST4(A);
  C := DST4(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], DblTol);
end;

procedure TVMobjTests.TestFindKnownValues;
var A: TVMobj; R: TVMobjI; i, j: Integer;
begin
  A := TVMobj.Create(2, 3, [1, 2, 3, 4, 5, 6]);
  R := Find(A, cmpGT, 3);
  AssertEquals('Rows', A.Rows, R.Rows);
  AssertEquals('Cols', A.Cols, R.Cols);
  for i := 0 to 1 do
    for j := 0 to 2 do
      if A[i, j] > 3 then AssertEquals(Format('[%d,%d]', [i, j]), 1, R[i, j])
      else AssertEquals(Format('[%d,%d]', [i, j]), 0, R[i, j]);
  R := Find(A, cmpEQ, 4);
  AssertEquals(0, R[0, 0]); AssertEquals(0, R[0, 1]); AssertEquals(0, R[0, 2]);
  AssertEquals(1, R[1, 0]); AssertEquals(0, R[1, 1]); AssertEquals(0, R[1, 2]);
  R := Find(A, cmpLE, 2);
  AssertEquals(1, R[0, 0]); AssertEquals(1, R[0, 1]); AssertEquals(0, R[0, 2]);
end;

procedure TVMobjTests.TestKronKnownValues;
var A, B, K: TVMobj;
begin
  A := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobj.Create(2, 2, [0, 5, 6, 7]);
  K := Kron(A, B);
  AssertEquals('Rows', 4, K.Rows);
  AssertEquals('Cols', 4, K.Cols);
  AssertEquals(0, K[0,0], DblTol);  AssertEquals(5, K[0,1], DblTol);  AssertEquals(0, K[0,2], DblTol);  AssertEquals(10, K[0,3], DblTol);
  AssertEquals(6, K[1,0], DblTol);  AssertEquals(7, K[1,1], DblTol);  AssertEquals(12, K[1,2], DblTol); AssertEquals(14, K[1,3], DblTol);
  AssertEquals(0, K[2,0], DblTol);  AssertEquals(15, K[2,1], DblTol); AssertEquals(0, K[2,2], DblTol);  AssertEquals(20, K[2,3], DblTol);
  AssertEquals(18, K[3,0], DblTol); AssertEquals(21, K[3,1], DblTol); AssertEquals(24, K[3,2], DblTol); AssertEquals(28, K[3,3], DblTol);
end;

{===========================================================================
  TVMobjSTests  (real single)
===========================================================================}

procedure TVMobjSTests.Raise_CreateZeroRows;
var X: TVMobjS;
begin
  X := TVMobjS.Create(0, 3);
end;

procedure TVMobjSTests.Raise_CreateZeroCols;
var X: TVMobjS;
begin
  X := TVMobjS.Create(3, 0);
end;

procedure TVMobjSTests.Raise_CreateValuesMismatch;
var X: TVMobjS;
begin
  X := TVMobjS.Create(2, 2, [1, 2, 3]);
end;

procedure TVMobjSTests.Raise_ElementRowOutOfRange;
var X: TVMobjS; V: Single;
begin
  X := TVMobjS.Create(2, 2);
  V := X[2, 0];
end;

procedure TVMobjSTests.Raise_ElementColOutOfRange;
var X: TVMobjS; V: Single;
begin
  X := TVMobjS.Create(2, 2);
  V := X[0, 2];
end;

procedure TVMobjSTests.Raise_IdNonSquare;
var X: TVMobjS;
begin
  X := TVMobjS.Create(2, 3);
  X.Id;
end;

procedure TVMobjSTests.Raise_MatMultDimMismatch;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(2, 3);
  B := TVMobjS.Create(2, 2);
  A := MatMultS(A, B);
end;

procedure TVMobjSTests.Raise_LinearSolveNonSquare;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(2, 3);
  B := TVMobjS.Create(2, 1);
  LinearSolveS(A, B);
end;

procedure TVMobjSTests.Raise_InvertNonSquare;
var A: TVMobjS;
begin
  A := TVMobjS.Create(2, 3);
  A := InvertS(A);
end;

procedure TVMobjSTests.Raise_OperatorAddDimMismatch;
var A, B, C: TVMobjS;
begin
  A := TVMobjS.Create(2, 2);
  B := TVMobjS.Create(3, 3);
  C := A + B;
end;

procedure TVMobjSTests.Raise_ScalarDivByZero;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  B := A / 0.0;
end;

procedure TVMobjSTests.TestCreateZeroFills;
var A: TVMobjS; r, c: Integer;
begin
  A := TVMobjS.Create(2, 3);
  AssertEquals('Rows', 2, A.Rows);
  AssertEquals('Cols', 3, A.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do
      AssertEquals('zero-fill', 0.0, A[r, c], SngTol);
end;

procedure TVMobjSTests.TestCreateInvalidDimsAssert;
begin
  AssertException('zero rows', EAssertionFailed, @Raise_CreateZeroRows);
  AssertException('zero cols', EAssertionFailed, @Raise_CreateZeroCols);
end;

procedure TVMobjSTests.TestCreateWithValues;
var A: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  AssertEquals(1.0, A[0, 0], SngTol);
  AssertEquals(2.0, A[0, 1], SngTol);
  AssertEquals(3.0, A[1, 0], SngTol);
  AssertEquals(4.0, A[1, 1], SngTol);
end;

procedure TVMobjSTests.TestCreateWithValuesMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_CreateValuesMismatch);
end;

procedure TVMobjSTests.TestElementRoundTripNonSquare;
var A: TVMobjS; r, c: Integer;
begin
  A := TVMobjS.Create(3, 4, [1,2,3,4, 5,6,7,8, 9,10,11,12]);
  for r := 0 to 2 do
    for c := 0 to 3 do
      AssertEquals(Format('[%d,%d]', [r, c]), r*4 + c + 1, A[r, c], SngTol);
end;

procedure TVMobjSTests.TestElementOutOfRangeAsserts;
begin
  AssertException('row out of range', EAssertionFailed, @Raise_ElementRowOutOfRange);
  AssertException('col out of range', EAssertionFailed, @Raise_ElementColOutOfRange);
end;

procedure TVMobjSTests.TestWriteMatrixRowCount;
var A: TVMobjS; S: TStringList;
begin
  A := TVMobjS.Create(3, 4);
  S := A.writeMatrix;
  try
    AssertEquals(3, S.Count);
  finally
    S.Free;
  end;
end;

procedure TVMobjSTests.TestFillRandomDeterministic;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(3, 3);
  A.fillRandom;
  B := TVMobjS.Create(3, 3);
  B.fillRandom;
  AssertTrue(A = B);
end;

procedure TVMobjSTests.TestFillRandomNonZero;
var A: TVMobjS;
begin
  A := TVMobjS.Create(3, 3);
  A.fillRandom;
  AssertFalse(A[0, 0] = 0.0);
end;

procedure TVMobjSTests.TestIdIdentity;
var A: TVMobjS; r, c: Integer;
begin
  A := TVMobjS.Create(3, 3);
  A.Id;
  for r := 0 to 2 do
    for c := 0 to 2 do
      if r = c then
        AssertEquals(1.0, A[r, c], SngTol)
      else
        AssertEquals(0.0, A[r, c], SngTol);
end;

procedure TVMobjSTests.TestIdNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_IdNonSquare);
end;

procedure TVMobjSTests.TestDataPtrAddressable;
var A: TVMobjS; P: PSingle;
begin
  A := TVMobjS.Create(2, 2);
  P := A.DataPtr;
  P^ := 42.0;
  AssertEquals(42.0, A[0, 0], SngTol);
end;

procedure TVMobjSTests.TestCopyObjIndependence;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(2, 2);
  A.fillRandom;
  B := CopyObjS(A);
  AssertTrue(A = B);
  B[1, 1] := B[1, 1] + 1;
  AssertFalse(A = B);
end;

procedure TVMobjSTests.TestMatMultKnownValues;
var A, B, C: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobjS.Create(2, 2, [5, 6, 7, 8]);
  C := MatMultS(A, B);
  AssertEquals(19.0, C[0, 0], SngTol);
  AssertEquals(22.0, C[0, 1], SngTol);
  AssertEquals(43.0, C[1, 0], SngTol);
  AssertEquals(50.0, C[1, 1], SngTol);
end;

procedure TVMobjSTests.TestMatMultDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_MatMultDimMismatch);
end;

procedure TVMobjSTests.TestLinearSolveRecoversRHS;
const N = 3;
var A, B, Akeep, Bkeep, X: TVMobjS; info, i: Integer;
begin
  A := TVMobjS.Create(N, N);
  A.fillRandom;
  B := TVMobjS.Create(N, 1);
  B.fillRandom;
  Akeep := CopyObjS(A);
  Bkeep := CopyObjS(B);
  info := LinearSolveS(A, B);
  AssertEquals('LAPACKE_sgesv info', 0, info);
  X := MatMultS(Akeep, B);
  for i := 0 to N-1 do
    AssertEquals(Format('row %d', [i]), Bkeep[i, 0], X[i, 0], SngSolveTol);
end;

procedure TVMobjSTests.TestLinearSolveNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_LinearSolveNonSquare);
end;

procedure TVMobjSTests.TestInvertRecoversIdentity;
const N = 3;
var A, Ainv, Akeep, X: TVMobjS; r, c: Integer; expected: Single;
begin
  A := TVMobjS.Create(N, N);
  A.fillRandom;
  Akeep := CopyObjS(A);
  Ainv := InvertS(A);
  for r := 0 to N-1 do
    for c := 0 to N-1 do
      AssertEquals(Format('A[%d,%d] unmutated', [r, c]), Akeep[r, c], A[r, c], SngTol);
  X := MatMultS(Akeep, Ainv);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      if r = c then expected := 1.0 else expected := 0.0;
      AssertEquals(Format('(A*Ainv)[%d,%d]', [r, c]), expected, X[r, c], SngSolveTol);
    end;
end;

procedure TVMobjSTests.TestInvertNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_InvertNonSquare);
end;

procedure TVMobjSTests.TestOperatorAddSub;
var A, B, S1, D1: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobjS.Create(2, 2, [5, 6, 7, 8]);
  S1 := A + B;
  AssertTrue(S1 = TVMobjS.Create(2, 2, [6, 8, 10, 12]));
  D1 := A - B;
  AssertTrue(D1 = TVMobjS.Create(2, 2, [-4, -4, -4, -4]));
end;

procedure TVMobjSTests.TestOperatorUnaryNeg;
var A: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  AssertTrue(-A = TVMobjS.Create(2, 2, [-1, -2, -3, -4]));
  AssertTrue(-(-A) = A);
end;

procedure TVMobjSTests.TestOperatorMulIsElementwise;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobjS.Create(2, 2, [5, 6, 7, 8]);
  AssertTrue(A * B = MulObjS(A, B));
  AssertTrue(A * B = TVMobjS.Create(2, 2, [5, 12, 21, 32]));
end;

procedure TVMobjSTests.TestOperatorScalarMulDiv;
var A: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  AssertTrue(A * 2.0 = TVMobjS.Create(2, 2, [2, 4, 6, 8]));
  AssertTrue(2.0 * A = A * 2.0);
  AssertTrue(A / 2.0 = TVMobjS.Create(2, 2, [0.5, 1, 1.5, 2]));
end;

procedure TVMobjSTests.TestOperatorScalarDivByZeroAsserts;
begin
  AssertException(EAssertionFailed, @Raise_ScalarDivByZero);
end;

procedure TVMobjSTests.TestOperatorDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_OperatorAddDimMismatch);
end;

procedure TVMobjSTests.TestOperatorEquality;
var A, B: TVMobjS;
begin
  A := TVMobjS.Create(3, 3);
  A.fillRandom;
  AssertTrue(A = A);
  B := CopyObjS(A);
  AssertTrue(A = B);
  B[0, 0] := B[0, 0] + 1;
  AssertFalse(A = B);
  B := TVMobjS.Create(3, 4);
  AssertFalse(A = B);
end;

procedure TVMobjSTests.TestElementwiseTrig;
var A, S, C, T: TVMobjS;
begin
  A := TVMobjS.Create(1, 3, [0, Pi/6, Pi/2]);
  S := Sin(A);
  C := Cos(A);
  T := Tan(TVMobjS.Create(1, 1, [Pi/4]));
  AssertEquals(0.0, S[0, 0], SngTol);
  AssertEquals(0.5, S[0, 1], SngTol);
  AssertEquals(1.0, S[0, 2], SngTol);
  AssertEquals(1.0, C[0, 0], SngTol);
  AssertEquals(Sqrt(3)/2, C[0, 1], SngTol);
  AssertEquals(0.0, C[0, 2], SngTol);
  AssertEquals(1.0, T[0, 0], SngTol);
end;

procedure TVMobjSTests.TestElementwiseSqrtSqr;
var A, R: TVMobjS;
begin
  A := TVMobjS.Create(1, 2, [-3, 4]);
  R := Sqrt(Sqr(A));
  AssertEquals(3.0, R[0, 0], SngTol);
  AssertEquals(4.0, R[0, 1], SngTol);
  AssertEquals(0.0, Sinh(TVMobjS.Create(1,1,[0]))[0, 0], SngTol);
end;

procedure TVMobjSTests.TestElementwiseExpLnRoundTrip;
var A, R: TVMobjS;
begin
  A := TVMobjS.Create(1, 2, [1, 2.5]);
  R := Ln(Exp(A));
  AssertEquals(1.0, R[0, 0], SngTol);
  AssertEquals(2.5, R[0, 1], SngTol);
end;

{ DCT/DST round-trip tests - see the matching TVMobjTests tests above for
  why each pair needs the scale factor. }

procedure TVMobjSTests.TestDCT1SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT1(A);
  C := DCT1(B) / (2*(N-1));
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestDCT2DCT3InverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT2(A);
  C := DCT3(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestDCT4SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DCT4(A);
  C := DCT4(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestDST1SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST1(A);
  C := DST1(B) / (2*(N+1));
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestDST2DST3InverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST2(A);
  C := DST3(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestDST4SelfInverseRoundTrip;
const N = 5;
var A, B, C: TVMobjS; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5]);
  B := DST4(A);
  C := DST4(B) / (2*N);
  for i := 0 to N-1 do AssertEquals(A[0, i], C[0, i], SngTol);
end;

procedure TVMobjSTests.TestFindKnownValues;
var A: TVMobjS; R: TVMobjI; i, j: Integer;
begin
  A := TVMobjS.Create(2, 3, [1, 2, 3, 4, 5, 6]);
  R := Find(A, cmpGT, 3);
  AssertEquals('Rows', A.Rows, R.Rows);
  AssertEquals('Cols', A.Cols, R.Cols);
  for i := 0 to 1 do
    for j := 0 to 2 do
      if A[i, j] > 3 then AssertEquals(Format('[%d,%d]', [i, j]), 1, R[i, j])
      else AssertEquals(Format('[%d,%d]', [i, j]), 0, R[i, j]);
  R := Find(A, cmpEQ, 4);
  AssertEquals(0, R[0, 0]); AssertEquals(0, R[0, 1]); AssertEquals(0, R[0, 2]);
  AssertEquals(1, R[1, 0]); AssertEquals(0, R[1, 1]); AssertEquals(0, R[1, 2]);
  R := Find(A, cmpLE, 2);
  AssertEquals(1, R[0, 0]); AssertEquals(1, R[0, 1]); AssertEquals(0, R[0, 2]);
end;

procedure TVMobjSTests.TestKronKnownValues;
var A, B, K: TVMobjS;
begin
  A := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  B := TVMobjS.Create(2, 2, [0, 5, 6, 7]);
  K := KronS(A, B);
  AssertEquals('Rows', 4, K.Rows);
  AssertEquals('Cols', 4, K.Cols);
  AssertEquals(0, K[0,0], SngTol);  AssertEquals(5, K[0,1], SngTol);  AssertEquals(0, K[0,2], SngTol);  AssertEquals(10, K[0,3], SngTol);
  AssertEquals(6, K[1,0], SngTol);  AssertEquals(7, K[1,1], SngTol);  AssertEquals(12, K[1,2], SngTol); AssertEquals(14, K[1,3], SngTol);
  AssertEquals(0, K[2,0], SngTol);  AssertEquals(15, K[2,1], SngTol); AssertEquals(0, K[2,2], SngTol);  AssertEquals(20, K[2,3], SngTol);
  AssertEquals(18, K[3,0], SngTol); AssertEquals(21, K[3,1], SngTol); AssertEquals(24, K[3,2], SngTol); AssertEquals(28, K[3,3], SngTol);
end;

{===========================================================================
  TVMobjZTests  (complex double)
===========================================================================}

procedure TVMobjZTests.Raise_CreateZeroRows;
var X: TVMobjZ;
begin
  X := TVMobjZ.Create(0, 3);
end;

procedure TVMobjZTests.Raise_CreateZeroCols;
var X: TVMobjZ;
begin
  X := TVMobjZ.Create(3, 0);
end;

procedure TVMobjZTests.Raise_CreateValuesMismatch;
var X: TVMobjZ;
begin
  X := TVMobjZ.Create(2, 2, [Cplx(1,0), Cplx(2,0), Cplx(3,0)]);
end;

procedure TVMobjZTests.Raise_ElementRowOutOfRange;
var X: TVMobjZ; V: TComplex16;
begin
  X := TVMobjZ.Create(2, 2);
  V := X[2, 0];
end;

procedure TVMobjZTests.Raise_ElementColOutOfRange;
var X: TVMobjZ; V: TComplex16;
begin
  X := TVMobjZ.Create(2, 2);
  V := X[0, 2];
end;

procedure TVMobjZTests.Raise_IdNonSquare;
var X: TVMobjZ;
begin
  X := TVMobjZ.Create(2, 3);
  X.Id;
end;

procedure TVMobjZTests.Raise_MatMultDimMismatch;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 3);
  B := TVMobjZ.Create(2, 2);
  A := MatMultZ(A, B);
end;

procedure TVMobjZTests.Raise_LinearSolveNonSquare;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 3);
  B := TVMobjZ.Create(2, 1);
  LinearSolveZ(A, B);
end;

procedure TVMobjZTests.Raise_InvertNonSquare;
var A: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 3);
  A := InvertZ(A);
end;

procedure TVMobjZTests.Raise_OperatorAddDimMismatch;
var A, B, C: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2);
  B := TVMobjZ.Create(3, 3);
  C := A + B;
end;

procedure TVMobjZTests.Raise_ScalarDivByZero;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,0), Cplx(2,0), Cplx(3,0), Cplx(4,0)]);
  B := A / 0.0;
end;

procedure TVMobjZTests.TestCreateZeroFills;
var A: TVMobjZ; r, c: Integer;
begin
  A := TVMobjZ.Create(2, 3);
  AssertEquals('Rows', 2, A.Rows);
  AssertEquals('Cols', 3, A.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do begin
      AssertEquals('zero-fill re', 0.0, A[r, c].re, DblTol);
      AssertEquals('zero-fill im', 0.0, A[r, c].im, DblTol);
    end;
end;

procedure TVMobjZTests.TestCreateInvalidDimsAssert;
begin
  AssertException('zero rows', EAssertionFailed, @Raise_CreateZeroRows);
  AssertException('zero cols', EAssertionFailed, @Raise_CreateZeroCols);
end;

procedure TVMobjZTests.TestCreateWithValues;
var A: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,5), Cplx(2,6), Cplx(3,7), Cplx(4,8)]);
  AssertEquals(1.0, A[0, 0].re, DblTol); AssertEquals(5.0, A[0, 0].im, DblTol);
  AssertEquals(4.0, A[1, 1].re, DblTol); AssertEquals(8.0, A[1, 1].im, DblTol);
end;

procedure TVMobjZTests.TestCreateWithValuesMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_CreateValuesMismatch);
end;

procedure TVMobjZTests.TestElementRoundTripNonSquare;
var A: TVMobjZ; r, c: Integer;
begin
  A := TVMobjZ.Create(3, 4, [
    Cplx(1,-1),Cplx(2,-2),Cplx(3,-3),Cplx(4,-4),
    Cplx(5,-5),Cplx(6,-6),Cplx(7,-7),Cplx(8,-8),
    Cplx(9,-9),Cplx(10,-10),Cplx(11,-11),Cplx(12,-12)]);
  for r := 0 to 2 do
    for c := 0 to 3 do begin
      AssertEquals(Format('[%d,%d].re', [r, c]), r*4 + c + 1, A[r, c].re, DblTol);
      AssertEquals(Format('[%d,%d].im', [r, c]), -(r*4 + c + 1), A[r, c].im, DblTol);
    end;
end;

procedure TVMobjZTests.TestElementOutOfRangeAsserts;
begin
  AssertException('row out of range', EAssertionFailed, @Raise_ElementRowOutOfRange);
  AssertException('col out of range', EAssertionFailed, @Raise_ElementColOutOfRange);
end;

procedure TVMobjZTests.TestWriteMatrixRowCount;
var A: TVMobjZ; S: TStringList;
begin
  A := TVMobjZ.Create(3, 4);
  S := A.writeMatrix;
  try
    AssertEquals(3, S.Count);
  finally
    S.Free;
  end;
end;

procedure TVMobjZTests.TestFillRandomDeterministic;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(3, 3);
  A.fillRandom;
  B := TVMobjZ.Create(3, 3);
  B.fillRandom;
  AssertTrue(A = B);
end;

procedure TVMobjZTests.TestFillRandomNonZero;
var A: TVMobjZ;
begin
  A := TVMobjZ.Create(3, 3);
  A.fillRandom;
  AssertFalse((A[0, 0].re = 0.0) and (A[0, 0].im = 0.0));
end;

procedure TVMobjZTests.TestIdIdentity;
var A: TVMobjZ; r, c: Integer;
begin
  A := TVMobjZ.Create(3, 3);
  A.Id;
  for r := 0 to 2 do
    for c := 0 to 2 do begin
      if r = c then begin
        AssertEquals(1.0, A[r, c].re, DblTol);
        AssertEquals(0.0, A[r, c].im, DblTol);
      end else begin
        AssertEquals(0.0, A[r, c].re, DblTol);
        AssertEquals(0.0, A[r, c].im, DblTol);
      end;
    end;
end;

procedure TVMobjZTests.TestIdNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_IdNonSquare);
end;

procedure TVMobjZTests.TestCopyObjIndependence;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2);
  A.fillRandom;
  B := CopyObjZ(A);
  AssertTrue(A = B);
  B[1, 1] := Cplx(B[1, 1].re + 1, B[1, 1].im);
  AssertFalse(A = B);
end;

procedure TVMobjZTests.TestMatMultKnownValues;
var A, B, C: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,0), Cplx(2,0), Cplx(3,0), Cplx(4,0)]);
  B := TVMobjZ.Create(2, 2, [Cplx(5,0), Cplx(6,0), Cplx(7,0), Cplx(8,0)]);
  C := MatMultZ(A, B);
  AssertEquals(19.0, C[0, 0].re, DblTol);
  AssertEquals(22.0, C[0, 1].re, DblTol);
  AssertEquals(43.0, C[1, 0].re, DblTol);
  AssertEquals(50.0, C[1, 1].re, DblTol);
end;

procedure TVMobjZTests.TestMatMultDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_MatMultDimMismatch);
end;

procedure TVMobjZTests.TestLinearSolveRecoversRHS;
const N = 3;
var A, B, Akeep, Bkeep, X: TVMobjZ; info, i: Integer;
begin
  A := TVMobjZ.Create(N, N);
  A.fillRandom;
  B := TVMobjZ.Create(N, 1);
  B.fillRandom;
  Akeep := CopyObjZ(A);
  Bkeep := CopyObjZ(B);
  info := LinearSolveZ(A, B);
  AssertEquals('LAPACKE_zgesv info', 0, info);
  X := MatMultZ(Akeep, B);
  for i := 0 to N-1 do begin
    AssertEquals(Format('row %d re', [i]), Bkeep[i, 0].re, X[i, 0].re, DblSolveTol);
    AssertEquals(Format('row %d im', [i]), Bkeep[i, 0].im, X[i, 0].im, DblSolveTol);
  end;
end;

procedure TVMobjZTests.TestLinearSolveNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_LinearSolveNonSquare);
end;

procedure TVMobjZTests.TestInvertRecoversIdentity;
const N = 3;
var A, Ainv, Akeep, X: TVMobjZ; r, c: Integer; expected: TComplex16;
begin
  A := TVMobjZ.Create(N, N);
  A.fillRandom;
  Akeep := CopyObjZ(A);
  Ainv := InvertZ(A);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      AssertEquals(Format('A[%d,%d] unmutated (re)', [r, c]), Akeep[r, c].re, A[r, c].re, DblTol);
      AssertEquals(Format('A[%d,%d] unmutated (im)', [r, c]), Akeep[r, c].im, A[r, c].im, DblTol);
    end;
  X := MatMultZ(Akeep, Ainv);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      if r = c then expected := Cplx(1,0) else expected := Cplx(0,0);
      AssertEquals(Format('(A*Ainv)[%d,%d] re', [r, c]), expected.re, X[r, c].re, DblSolveTol);
      AssertEquals(Format('(A*Ainv)[%d,%d] im', [r, c]), expected.im, X[r, c].im, DblSolveTol);
    end;
end;

procedure TVMobjZTests.TestInvertNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_InvertNonSquare);
end;

procedure TVMobjZTests.TestOperatorAddSub;
var A, B, S1, D1: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,1), Cplx(2,2), Cplx(3,3), Cplx(4,4)]);
  B := TVMobjZ.Create(2, 2, [Cplx(5,-1), Cplx(6,-2), Cplx(7,-3), Cplx(8,-4)]);
  S1 := A + B;
  AssertTrue(S1 = TVMobjZ.Create(2, 2, [Cplx(6,0), Cplx(8,0), Cplx(10,0), Cplx(12,0)]));
  D1 := A - B;
  AssertTrue(D1 = TVMobjZ.Create(2, 2, [Cplx(-4,2), Cplx(-4,4), Cplx(-4,6), Cplx(-4,8)]));
end;

procedure TVMobjZTests.TestOperatorUnaryNeg;
var A: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,1), Cplx(2,2), Cplx(3,3), Cplx(4,4)]);
  AssertTrue(-A = TVMobjZ.Create(2, 2, [Cplx(-1,-1), Cplx(-2,-2), Cplx(-3,-3), Cplx(-4,-4)]));
  AssertTrue(-(-A) = A);
end;

procedure TVMobjZTests.TestOperatorMulIsElementwise;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,1), Cplx(2,0), Cplx(3,0), Cplx(4,-1)]);
  B := TVMobjZ.Create(2, 2, [Cplx(5,0), Cplx(6,1), Cplx(7,0), Cplx(8,0)]);
  AssertTrue(A * B = MulObjZ(A, B));
  AssertTrue(A * B = TVMobjZ.Create(2, 2, [Cplx(5,5), Cplx(12,2), Cplx(21,0), Cplx(32,-8)]));
end;

procedure TVMobjZTests.TestOperatorScalarMulDiv;
var A, P: TVMobjZ;
begin
  A := TVMobjZ.Create(1, 1, [Cplx(3,0)]);
  P := A * Cplx(0,2);
  AssertEquals(0.0, P[0,0].re, DblTol);
  AssertEquals(6.0, P[0,0].im, DblTol);
  AssertTrue(A * 2.0 = TVMobjZ.Create(1, 1, [Cplx(6,0)]));
  AssertTrue((A / Cplx(2,0)) * Cplx(2,0) = A);
  AssertTrue(A / 2.0 = TVMobjZ.Create(1, 1, [Cplx(1.5,0)]));
end;

procedure TVMobjZTests.TestOperatorScalarDivByZeroAsserts;
begin
  AssertException(EAssertionFailed, @Raise_ScalarDivByZero);
end;

procedure TVMobjZTests.TestOperatorDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_OperatorAddDimMismatch);
end;

procedure TVMobjZTests.TestOperatorEquality;
var A, B: TVMobjZ;
begin
  A := TVMobjZ.Create(3, 3);
  A.fillRandom;
  AssertTrue(A = A);
  B := CopyObjZ(A);
  AssertTrue(A = B);
  B[0, 0] := Cplx(B[0, 0].re + 1, B[0, 0].im);
  AssertFalse(A = B);
  B := TVMobjZ.Create(3, 4);
  AssertFalse(A = B);
end;

procedure TVMobjZTests.TestElementwiseTrig;
var A, S, C: TVMobjZ;
begin
  //Purely real input - complex Sin/Cos should agree with the real-valued case.
  A := TVMobjZ.Create(1, 2, [Cplx(0,0), Cplx(Pi/2,0)]);
  S := Sin(A);
  C := Cos(A);
  AssertEquals(0.0, S[0, 0].re, DblTol); AssertEquals(0.0, S[0, 0].im, DblTol);
  AssertEquals(1.0, S[0, 1].re, DblTol); AssertEquals(0.0, S[0, 1].im, DblTol);
  AssertEquals(1.0, C[0, 0].re, DblTol); AssertEquals(0.0, C[0, 0].im, DblTol);
  AssertEquals(0.0, C[0, 1].re, DblTol); AssertEquals(0.0, C[0, 1].im, DblTol);
end;

procedure TVMobjZTests.TestElementwiseSqrtSqr;
var A, R: TVMobjZ;
begin
  //Sqr has no vzSqr - implemented via vzMul(A,A) - so this also exercises that path.
  A := TVMobjZ.Create(1, 1, [Cplx(3,4)]);
  R := Sqrt(Sqr(A));
  //principal branch: sqrt((3+4i)^2) = 3+4i (already in the right half-plane)
  AssertEquals(3.0, R[0, 0].re, DblTol);
  AssertEquals(4.0, R[0, 0].im, DblTol);
end;

procedure TVMobjZTests.TestElementwiseExpLnRoundTrip;
var A, R: TVMobjZ;
begin
  A := TVMobjZ.Create(1, 1, [Cplx(0.5, 0.25)]);
  R := Ln(Exp(A));
  AssertEquals(0.5, R[0, 0].re, DblTol);
  AssertEquals(0.25, R[0, 0].im, DblTol);
end;

procedure TVMobjZTests.TestRealToComplexPromotion;
var RM: TVMobj; Z: TVMobjZ; r, c: Integer;
begin
  RM := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  Z := RealToComplex(RM);
  for r := 0 to 1 do
    for c := 0 to 1 do begin
      AssertEquals(RM[r, c], Z[r, c].re, DblTol);
      AssertEquals(0.0, Z[r, c].im, DblTol);
    end;
end;

procedure TVMobjZTests.TestGetRealGetImagSplit;
var Z: TVMobjZ; Re1, Im1, Re2, Im2: TVMobj;
begin
  Z := TVMobjZ.Create(2, 2, [Cplx(1,5), Cplx(2,6), Cplx(3,7), Cplx(4,8)]);
  Re1 := GetRealPart(Z);
  Im1 := GetImagPart(Z);
  AssertTrue(Re1 = TVMobj.Create(2, 2, [1,2,3,4]));
  AssertTrue(Im1 = TVMobj.Create(2, 2, [5,6,7,8]));
  SplitComplex(Z, Re2, Im2);
  AssertTrue(Re1 = Re2);
  AssertTrue(Im1 = Im2);
end;

procedure TVMobjZTests.TestEigDecomposeSatisfiesEigenEquation;
const N = 2;
var
  A: TVMobj;
  EVals, EVecs, vcol, Av, lv: TVMobjZ;
  i, j: Integer;
begin
  //Symmetric, well-conditioned, distinct real eigenvalues (1 and 3) - but we
  //verify the defining equation A*v = lambda*v rather than hard-coding the
  //eigenvectors themselves, since LAPACK doesn't guarantee their sign/phase.
  A := TVMobj.Create(N, N, [2, 1, 1, 2]);
  EigDecompose(A, EVals, EVecs);
  for j := 0 to N-1 do begin
    vcol := TVMobjZ.Create(N, 1);
    for i := 0 to N-1 do
      vcol[i, 0] := EVecs[i, j];
    Av := A * vcol;                 //mixed TVMobj * TVMobjZ
    lv := EVals[j, 0] * vcol;       //complex scalar * TVMobjZ
    for i := 0 to N-1 do begin
      AssertEquals(Format('eigvec %d row %d re', [j, i]), lv[i, 0].re, Av[i, 0].re, DblSolveTol);
      AssertEquals(Format('eigvec %d row %d im', [j, i]), lv[i, 0].im, Av[i, 0].im, DblSolveTol);
    end;
  end;
end;

procedure TVMobjZTests.TestMixedOperatorsAddSub;
var RM: TVMobj; Z, Sum1, Sum2, Diff1, Diff2: TVMobjZ; r, c: Integer;
begin
  RM := TVMobj.Create(2, 2, [1, 2, 3, 4]);
  Z := TVMobjZ.Create(2, 2, [Cplx(0,1), Cplx(0,1), Cplx(0,1), Cplx(0,1)]);
  Sum1 := RM + Z;
  Sum2 := Z + RM;
  AssertTrue(Sum1 = Sum2);
  for r := 0 to 1 do
    for c := 0 to 1 do begin
      AssertEquals(RM[r, c], Sum1[r, c].re, DblTol);
      AssertEquals(1.0, Sum1[r, c].im, DblTol);
    end;
  Diff1 := RM - Z;
  Diff2 := Z - RM;
  AssertTrue(Diff1 = -Diff2);
end;

procedure TVMobjZTests.TestMixedOperatorMatMultKnownValue;
var R: TVMobj; Z, P1, P2: TVMobjZ;
begin
  R := TVMobj.Create(1, 1, [3]);
  Z := TVMobjZ.Create(1, 1, [Cplx(0,2)]);
  P1 := R * Z;   //TVMobj * TVMobjZ
  P2 := Z * R;   //TVMobjZ * TVMobj
  AssertEquals(0.0, P1[0, 0].re, DblTol);
  AssertEquals(6.0, P1[0, 0].im, DblTol);
  AssertTrue(P1 = P2);
end;

procedure TVMobjZTests.TestFFTR2CC2RRoundTrip;
const N = 7;  //odd, exercises the length-parity case FFT_C2R's explicit N handles
var A, R: TVMobj; Z: TVMobjZ; i: Integer;
begin
  A := TVMobj.Create(1, N, [1, 2, 3, 4, 5, 6, 7]);
  Z := FFT_R2C(A);
  AssertEquals(N div 2 + 1, Z.Cols);
  R := FFT_C2R(Z, N);
  for i := 0 to N-1 do AssertEquals(A[0, i], R[0, i], DblTol);
end;

procedure TVMobjZTests.TestFFTC2CRoundTrip;
const N = 6;
var A, R: TVMobjZ; i: Integer;
begin
  A := TVMobjZ.Create(1, N, [Cplx(1,1), Cplx(2,-1), Cplx(3,0), Cplx(-1,2), Cplx(0,-3), Cplx(4,4)]);
  R := IFFT(FFT(A));
  //N=6 is composite, not a power of 2 - FFTW_ESTIMATE's generic codelets
  //for this size carry more rounding error than DblTol; DblSolveTol
  //(already used for LAPACK-derived results elsewhere in this suite) fits.
  for i := 0 to N-1 do begin
    AssertEquals(A[0, i].re, R[0, i].re, DblSolveTol);
    AssertEquals(A[0, i].im, R[0, i].im, DblSolveTol);
  end;
end;

procedure TVMobjZTests.TestFFTR2CKnownDCValue;
const N = 4;
var A: TVMobj; Z: TVMobjZ;
begin
  A := TVMobj.Create(1, N, [2, 2, 2, 2]);  //constant vector
  Z := FFT_R2C(A);
  //DC component (index 0) of a real FFT is the sum of all samples; a
  //constant vector's higher harmonics are all exactly zero.
  AssertEquals(8.0, Z[0, 0].re, DblTol);
  AssertEquals(0.0, Z[0, 0].im, DblTol);
  AssertEquals(0.0, Z[0, 1].re, DblTol);
  AssertEquals(0.0, Z[0, 1].im, DblTol);
end;

procedure TVMobjZTests.TestKronKnownValues;
var A, B, K: TVMobjZ;
begin
  A := TVMobjZ.Create(2, 2, [Cplx(1,1), Cplx(2,0), Cplx(0,1), Cplx(1,0)]);
  B := TVMobjZ.Create(2, 2, [Cplx(1,0), Cplx(0,0), Cplx(2,0), Cplx(-1,0)]);
  K := KronZ(A, B);
  AssertEquals('Rows', 4, K.Rows);
  AssertEquals('Cols', 4, K.Cols);
  //Row0: [1+1i, 0, 2, 0]
  AssertEquals(1, K[0,0].re, DblTol); AssertEquals(1, K[0,0].im, DblTol);
  AssertEquals(0, K[0,1].re, DblTol); AssertEquals(0, K[0,1].im, DblTol);
  AssertEquals(2, K[0,2].re, DblTol); AssertEquals(0, K[0,2].im, DblTol);
  AssertEquals(0, K[0,3].re, DblTol); AssertEquals(0, K[0,3].im, DblTol);
  //Row1: [2+2i, -1-1i, 4, -2]
  AssertEquals(2, K[1,0].re, DblTol);  AssertEquals(2, K[1,0].im, DblTol);
  AssertEquals(-1, K[1,1].re, DblTol); AssertEquals(-1, K[1,1].im, DblTol);
  AssertEquals(4, K[1,2].re, DblTol);  AssertEquals(0, K[1,2].im, DblTol);
  AssertEquals(-2, K[1,3].re, DblTol); AssertEquals(0, K[1,3].im, DblTol);
  //Row2: [0+1i, 0, 1, 0]
  AssertEquals(0, K[2,0].re, DblTol); AssertEquals(1, K[2,0].im, DblTol);
  AssertEquals(0, K[2,1].re, DblTol); AssertEquals(0, K[2,1].im, DblTol);
  AssertEquals(1, K[2,2].re, DblTol); AssertEquals(0, K[2,2].im, DblTol);
  AssertEquals(0, K[2,3].re, DblTol); AssertEquals(0, K[2,3].im, DblTol);
  //Row3: [0+2i, 0-1i, 2, -1]
  AssertEquals(0, K[3,0].re, DblTol);  AssertEquals(2, K[3,0].im, DblTol);
  AssertEquals(0, K[3,1].re, DblTol);  AssertEquals(-1, K[3,1].im, DblTol);
  AssertEquals(2, K[3,2].re, DblTol);  AssertEquals(0, K[3,2].im, DblTol);
  AssertEquals(-1, K[3,3].re, DblTol); AssertEquals(0, K[3,3].im, DblTol);
end;

{===========================================================================
  TVMobjCTests  (complex single)
===========================================================================}

procedure TVMobjCTests.Raise_CreateZeroRows;
var X: TVMobjC;
begin
  X := TVMobjC.Create(0, 3);
end;

procedure TVMobjCTests.Raise_CreateZeroCols;
var X: TVMobjC;
begin
  X := TVMobjC.Create(3, 0);
end;

procedure TVMobjCTests.Raise_CreateValuesMismatch;
var X: TVMobjC;
begin
  X := TVMobjC.Create(2, 2, [Cplx8(1,0), Cplx8(2,0), Cplx8(3,0)]);
end;

procedure TVMobjCTests.Raise_ElementRowOutOfRange;
var X: TVMobjC; V: TComplex8;
begin
  X := TVMobjC.Create(2, 2);
  V := X[2, 0];
end;

procedure TVMobjCTests.Raise_ElementColOutOfRange;
var X: TVMobjC; V: TComplex8;
begin
  X := TVMobjC.Create(2, 2);
  V := X[0, 2];
end;

procedure TVMobjCTests.Raise_IdNonSquare;
var X: TVMobjC;
begin
  X := TVMobjC.Create(2, 3);
  X.Id;
end;

procedure TVMobjCTests.Raise_MatMultDimMismatch;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(2, 3);
  B := TVMobjC.Create(2, 2);
  A := MatMultC(A, B);
end;

procedure TVMobjCTests.Raise_LinearSolveNonSquare;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(2, 3);
  B := TVMobjC.Create(2, 1);
  LinearSolveC(A, B);
end;

procedure TVMobjCTests.Raise_InvertNonSquare;
var A: TVMobjC;
begin
  A := TVMobjC.Create(2, 3);
  A := InvertC(A);
end;

procedure TVMobjCTests.Raise_OperatorAddDimMismatch;
var A, B, C: TVMobjC;
begin
  A := TVMobjC.Create(2, 2);
  B := TVMobjC.Create(3, 3);
  C := A + B;
end;

procedure TVMobjCTests.Raise_ScalarDivByZero;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,0), Cplx8(2,0), Cplx8(3,0), Cplx8(4,0)]);
  B := A / 0.0;
end;

procedure TVMobjCTests.TestCreateZeroFills;
var A: TVMobjC; r, c: Integer;
begin
  A := TVMobjC.Create(2, 3);
  AssertEquals('Rows', 2, A.Rows);
  AssertEquals('Cols', 3, A.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do begin
      AssertEquals('zero-fill re', 0.0, A[r, c].re, SngTol);
      AssertEquals('zero-fill im', 0.0, A[r, c].im, SngTol);
    end;
end;

procedure TVMobjCTests.TestCreateInvalidDimsAssert;
begin
  AssertException('zero rows', EAssertionFailed, @Raise_CreateZeroRows);
  AssertException('zero cols', EAssertionFailed, @Raise_CreateZeroCols);
end;

procedure TVMobjCTests.TestCreateWithValues;
var A: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,5), Cplx8(2,6), Cplx8(3,7), Cplx8(4,8)]);
  AssertEquals(1.0, A[0, 0].re, SngTol); AssertEquals(5.0, A[0, 0].im, SngTol);
  AssertEquals(4.0, A[1, 1].re, SngTol); AssertEquals(8.0, A[1, 1].im, SngTol);
end;

procedure TVMobjCTests.TestCreateWithValuesMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_CreateValuesMismatch);
end;

procedure TVMobjCTests.TestElementRoundTripNonSquare;
var A: TVMobjC; r, c: Integer;
begin
  A := TVMobjC.Create(3, 4, [
    Cplx8(1,-1),Cplx8(2,-2),Cplx8(3,-3),Cplx8(4,-4),
    Cplx8(5,-5),Cplx8(6,-6),Cplx8(7,-7),Cplx8(8,-8),
    Cplx8(9,-9),Cplx8(10,-10),Cplx8(11,-11),Cplx8(12,-12)]);
  for r := 0 to 2 do
    for c := 0 to 3 do begin
      AssertEquals(Format('[%d,%d].re', [r, c]), r*4 + c + 1, A[r, c].re, SngTol);
      AssertEquals(Format('[%d,%d].im', [r, c]), -(r*4 + c + 1), A[r, c].im, SngTol);
    end;
end;

procedure TVMobjCTests.TestElementOutOfRangeAsserts;
begin
  AssertException('row out of range', EAssertionFailed, @Raise_ElementRowOutOfRange);
  AssertException('col out of range', EAssertionFailed, @Raise_ElementColOutOfRange);
end;

procedure TVMobjCTests.TestWriteMatrixRowCount;
var A: TVMobjC; S: TStringList;
begin
  A := TVMobjC.Create(3, 4);
  S := A.writeMatrix;
  try
    AssertEquals(3, S.Count);
  finally
    S.Free;
  end;
end;

procedure TVMobjCTests.TestFillRandomDeterministic;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(3, 3);
  A.fillRandom;
  B := TVMobjC.Create(3, 3);
  B.fillRandom;
  AssertTrue(A = B);
end;

procedure TVMobjCTests.TestFillRandomNonZero;
var A: TVMobjC;
begin
  A := TVMobjC.Create(3, 3);
  A.fillRandom;
  AssertFalse((A[0, 0].re = 0.0) and (A[0, 0].im = 0.0));
end;

procedure TVMobjCTests.TestIdIdentity;
var A: TVMobjC; r, c: Integer;
begin
  A := TVMobjC.Create(3, 3);
  A.Id;
  for r := 0 to 2 do
    for c := 0 to 2 do begin
      if r = c then begin
        AssertEquals(1.0, A[r, c].re, SngTol);
        AssertEquals(0.0, A[r, c].im, SngTol);
      end else begin
        AssertEquals(0.0, A[r, c].re, SngTol);
        AssertEquals(0.0, A[r, c].im, SngTol);
      end;
    end;
end;

procedure TVMobjCTests.TestIdNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_IdNonSquare);
end;

procedure TVMobjCTests.TestCopyObjIndependence;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(2, 2);
  A.fillRandom;
  B := CopyObjC(A);
  AssertTrue(A = B);
  B[1, 1] := Cplx8(B[1, 1].re + 1, B[1, 1].im);
  AssertFalse(A = B);
end;

procedure TVMobjCTests.TestMatMultKnownValues;
var A, B, C: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,0), Cplx8(2,0), Cplx8(3,0), Cplx8(4,0)]);
  B := TVMobjC.Create(2, 2, [Cplx8(5,0), Cplx8(6,0), Cplx8(7,0), Cplx8(8,0)]);
  C := MatMultC(A, B);
  AssertEquals(19.0, C[0, 0].re, SngTol);
  AssertEquals(22.0, C[0, 1].re, SngTol);
  AssertEquals(43.0, C[1, 0].re, SngTol);
  AssertEquals(50.0, C[1, 1].re, SngTol);
end;

procedure TVMobjCTests.TestMatMultDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_MatMultDimMismatch);
end;

procedure TVMobjCTests.TestLinearSolveRecoversRHS;
const N = 3;
var A, B, Akeep, Bkeep, X: TVMobjC; info, i: Integer;
begin
  A := TVMobjC.Create(N, N);
  A.fillRandom;
  B := TVMobjC.Create(N, 1);
  B.fillRandom;
  Akeep := CopyObjC(A);
  Bkeep := CopyObjC(B);
  info := LinearSolveC(A, B);
  AssertEquals('LAPACKE_cgesv info', 0, info);
  X := MatMultC(Akeep, B);
  for i := 0 to N-1 do begin
    AssertEquals(Format('row %d re', [i]), Bkeep[i, 0].re, X[i, 0].re, SngSolveTol);
    AssertEquals(Format('row %d im', [i]), Bkeep[i, 0].im, X[i, 0].im, SngSolveTol);
  end;
end;

procedure TVMobjCTests.TestLinearSolveNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_LinearSolveNonSquare);
end;

procedure TVMobjCTests.TestInvertRecoversIdentity;
const N = 3;
var A, Ainv, Akeep, X: TVMobjC; r, c: Integer; expected: TComplex8;
begin
  A := TVMobjC.Create(N, N);
  A.fillRandom;
  Akeep := CopyObjC(A);
  Ainv := InvertC(A);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      AssertEquals(Format('A[%d,%d] unmutated (re)', [r, c]), Akeep[r, c].re, A[r, c].re, SngTol);
      AssertEquals(Format('A[%d,%d] unmutated (im)', [r, c]), Akeep[r, c].im, A[r, c].im, SngTol);
    end;
  X := MatMultC(Akeep, Ainv);
  for r := 0 to N-1 do
    for c := 0 to N-1 do begin
      if r = c then expected := Cplx8(1,0) else expected := Cplx8(0,0);
      AssertEquals(Format('(A*Ainv)[%d,%d] re', [r, c]), expected.re, X[r, c].re, SngSolveTol);
      AssertEquals(Format('(A*Ainv)[%d,%d] im', [r, c]), expected.im, X[r, c].im, SngSolveTol);
    end;
end;

procedure TVMobjCTests.TestInvertNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_InvertNonSquare);
end;

procedure TVMobjCTests.TestOperatorAddSub;
var A, B, S1, D1: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,1), Cplx8(2,2), Cplx8(3,3), Cplx8(4,4)]);
  B := TVMobjC.Create(2, 2, [Cplx8(5,-1), Cplx8(6,-2), Cplx8(7,-3), Cplx8(8,-4)]);
  S1 := A + B;
  AssertTrue(S1 = TVMobjC.Create(2, 2, [Cplx8(6,0), Cplx8(8,0), Cplx8(10,0), Cplx8(12,0)]));
  D1 := A - B;
  AssertTrue(D1 = TVMobjC.Create(2, 2, [Cplx8(-4,2), Cplx8(-4,4), Cplx8(-4,6), Cplx8(-4,8)]));
end;

procedure TVMobjCTests.TestOperatorUnaryNeg;
var A: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,1), Cplx8(2,2), Cplx8(3,3), Cplx8(4,4)]);
  AssertTrue(-A = TVMobjC.Create(2, 2, [Cplx8(-1,-1), Cplx8(-2,-2), Cplx8(-3,-3), Cplx8(-4,-4)]));
  AssertTrue(-(-A) = A);
end;

procedure TVMobjCTests.TestOperatorMulIsElementwise;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,1), Cplx8(2,0), Cplx8(3,0), Cplx8(4,-1)]);
  B := TVMobjC.Create(2, 2, [Cplx8(5,0), Cplx8(6,1), Cplx8(7,0), Cplx8(8,0)]);
  AssertTrue(A * B = MulObjC(A, B));
  AssertTrue(A * B = TVMobjC.Create(2, 2, [Cplx8(5,5), Cplx8(12,2), Cplx8(21,0), Cplx8(32,-8)]));
end;

procedure TVMobjCTests.TestOperatorScalarMulDiv;
var A, P: TVMobjC;
begin
  A := TVMobjC.Create(1, 1, [Cplx8(3,0)]);
  P := A * Cplx8(0,2);
  AssertEquals(0.0, P[0,0].re, SngTol);
  AssertEquals(6.0, P[0,0].im, SngTol);
  AssertTrue(A * 2.0 = TVMobjC.Create(1, 1, [Cplx8(6,0)]));
  AssertTrue((A / Cplx8(2,0)) * Cplx8(2,0) = A);
  AssertTrue(A / 2.0 = TVMobjC.Create(1, 1, [Cplx8(1.5,0)]));
end;

procedure TVMobjCTests.TestOperatorScalarDivByZeroAsserts;
begin
  AssertException(EAssertionFailed, @Raise_ScalarDivByZero);
end;

procedure TVMobjCTests.TestOperatorDimMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_OperatorAddDimMismatch);
end;

procedure TVMobjCTests.TestOperatorEquality;
var A, B: TVMobjC;
begin
  A := TVMobjC.Create(3, 3);
  A.fillRandom;
  AssertTrue(A = A);
  B := CopyObjC(A);
  AssertTrue(A = B);
  B[0, 0] := Cplx8(B[0, 0].re + 1, B[0, 0].im);
  AssertFalse(A = B);
  B := TVMobjC.Create(3, 4);
  AssertFalse(A = B);
end;

procedure TVMobjCTests.TestElementwiseTrig;
var A, S, C: TVMobjC;
begin
  A := TVMobjC.Create(1, 2, [Cplx8(0,0), Cplx8(Pi/2,0)]);
  S := Sin(A);
  C := Cos(A);
  AssertEquals(0.0, S[0, 0].re, SngTol); AssertEquals(0.0, S[0, 0].im, SngTol);
  AssertEquals(1.0, S[0, 1].re, SngTol); AssertEquals(0.0, S[0, 1].im, SngTol);
  AssertEquals(1.0, C[0, 0].re, SngTol); AssertEquals(0.0, C[0, 0].im, SngTol);
  AssertEquals(0.0, C[0, 1].re, SngTol); AssertEquals(0.0, C[0, 1].im, SngTol);
end;

procedure TVMobjCTests.TestElementwiseSqrtSqr;
var A, R: TVMobjC;
begin
  A := TVMobjC.Create(1, 1, [Cplx8(3,4)]);
  R := Sqrt(Sqr(A));
  AssertEquals(3.0, R[0, 0].re, SngTol);
  AssertEquals(4.0, R[0, 0].im, SngTol);
end;

procedure TVMobjCTests.TestElementwiseExpLnRoundTrip;
var A, R: TVMobjC;
begin
  A := TVMobjC.Create(1, 1, [Cplx8(0.5, 0.25)]);
  R := Ln(Exp(A));
  AssertEquals(0.5, R[0, 0].re, SngTol);
  AssertEquals(0.25, R[0, 0].im, SngTol);
end;

procedure TVMobjCTests.TestRealToComplexPromotion;
var RM: TVMobjS; Z: TVMobjC; r, c: Integer;
begin
  RM := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  Z := RealToComplexS(RM);
  for r := 0 to 1 do
    for c := 0 to 1 do begin
      AssertEquals(RM[r, c], Z[r, c].re, SngTol);
      AssertEquals(0.0, Z[r, c].im, SngTol);
    end;
end;

procedure TVMobjCTests.TestGetRealGetImagSplit;
var Z: TVMobjC; Re1, Im1, Re2, Im2: TVMobjS;
begin
  Z := TVMobjC.Create(2, 2, [Cplx8(1,5), Cplx8(2,6), Cplx8(3,7), Cplx8(4,8)]);
  Re1 := GetRealPartS(Z);
  Im1 := GetImagPartS(Z);
  AssertTrue(Re1 = TVMobjS.Create(2, 2, [1,2,3,4]));
  AssertTrue(Im1 = TVMobjS.Create(2, 2, [5,6,7,8]));
  SplitComplexS(Z, Re2, Im2);
  AssertTrue(Re1 = Re2);
  AssertTrue(Im1 = Im2);
end;

procedure TVMobjCTests.TestEigDecomposeSatisfiesEigenEquation;
const N = 2;
var
  A: TVMobjS;
  EVals, EVecs, vcol, Av, lv: TVMobjC;
  i, j: Integer;
begin
  A := TVMobjS.Create(N, N, [2, 1, 1, 2]);
  EigDecomposeS(A, EVals, EVecs);
  for j := 0 to N-1 do begin
    vcol := TVMobjC.Create(N, 1);
    for i := 0 to N-1 do
      vcol[i, 0] := EVecs[i, j];
    Av := A * vcol;
    lv := EVals[j, 0] * vcol;
    for i := 0 to N-1 do begin
      AssertEquals(Format('eigvec %d row %d re', [j, i]), lv[i, 0].re, Av[i, 0].re, SngSolveTol);
      AssertEquals(Format('eigvec %d row %d im', [j, i]), lv[i, 0].im, Av[i, 0].im, SngSolveTol);
    end;
  end;
end;

procedure TVMobjCTests.TestMixedOperatorsAddSub;
var RM: TVMobjS; Z, Sum1, Sum2, Diff1, Diff2: TVMobjC; r, c: Integer;
begin
  RM := TVMobjS.Create(2, 2, [1, 2, 3, 4]);
  Z := TVMobjC.Create(2, 2, [Cplx8(0,1), Cplx8(0,1), Cplx8(0,1), Cplx8(0,1)]);
  Sum1 := RM + Z;
  Sum2 := Z + RM;
  AssertTrue(Sum1 = Sum2);
  for r := 0 to 1 do
    for c := 0 to 1 do begin
      AssertEquals(RM[r, c], Sum1[r, c].re, SngTol);
      AssertEquals(1.0, Sum1[r, c].im, SngTol);
    end;
  Diff1 := RM - Z;
  Diff2 := Z - RM;
  AssertTrue(Diff1 = -Diff2);
end;

procedure TVMobjCTests.TestMixedOperatorMatMultKnownValue;
var R: TVMobjS; Z, P1, P2: TVMobjC;
begin
  R := TVMobjS.Create(1, 1, [3]);
  Z := TVMobjC.Create(1, 1, [Cplx8(0,2)]);
  P1 := R * Z;
  P2 := Z * R;
  AssertEquals(0.0, P1[0, 0].re, SngTol);
  AssertEquals(6.0, P1[0, 0].im, SngTol);
  AssertTrue(P1 = P2);
end;

procedure TVMobjCTests.TestFFTR2CC2RRoundTrip;
const N = 7;  //odd, exercises the length-parity case FFT_C2R's explicit N handles
var A, R: TVMobjS; Z: TVMobjC; i: Integer;
begin
  A := TVMobjS.Create(1, N, [1, 2, 3, 4, 5, 6, 7]);
  Z := FFT_R2C(A);
  AssertEquals(N div 2 + 1, Z.Cols);
  R := FFT_C2R(Z, N);
  for i := 0 to N-1 do AssertEquals(A[0, i], R[0, i], SngTol);
end;

procedure TVMobjCTests.TestFFTC2CRoundTrip;
const N = 6;
var A, R: TVMobjC; i: Integer;
begin
  A := TVMobjC.Create(1, N, [Cplx8(1,1), Cplx8(2,-1), Cplx8(3,0), Cplx8(-1,2), Cplx8(0,-3), Cplx8(4,4)]);
  R := IFFT(FFT(A));
  for i := 0 to N-1 do begin
    AssertEquals(A[0, i].re, R[0, i].re, SngTol);
    AssertEquals(A[0, i].im, R[0, i].im, SngTol);
  end;
end;

procedure TVMobjCTests.TestFFTR2CKnownDCValue;
const N = 4;
var A: TVMobjS; Z: TVMobjC;
begin
  A := TVMobjS.Create(1, N, [2, 2, 2, 2]);  //constant vector
  Z := FFT_R2C(A);
  //DC component (index 0) of a real FFT is the sum of all samples; a
  //constant vector's higher harmonics are all exactly zero.
  AssertEquals(8.0, Z[0, 0].re, SngTol);
  AssertEquals(0.0, Z[0, 0].im, SngTol);
  AssertEquals(0.0, Z[0, 1].re, SngTol);
  AssertEquals(0.0, Z[0, 1].im, SngTol);
end;

procedure TVMobjCTests.TestKronKnownValues;
var A, B, K: TVMobjC;
begin
  A := TVMobjC.Create(2, 2, [Cplx8(1,1), Cplx8(2,0), Cplx8(0,1), Cplx8(1,0)]);
  B := TVMobjC.Create(2, 2, [Cplx8(1,0), Cplx8(0,0), Cplx8(2,0), Cplx8(-1,0)]);
  K := KronC(A, B);
  AssertEquals('Rows', 4, K.Rows);
  AssertEquals('Cols', 4, K.Cols);
  //Row0: [1+1i, 0, 2, 0]
  AssertEquals(1, K[0,0].re, SngTol); AssertEquals(1, K[0,0].im, SngTol);
  AssertEquals(0, K[0,1].re, SngTol); AssertEquals(0, K[0,1].im, SngTol);
  AssertEquals(2, K[0,2].re, SngTol); AssertEquals(0, K[0,2].im, SngTol);
  AssertEquals(0, K[0,3].re, SngTol); AssertEquals(0, K[0,3].im, SngTol);
  //Row1: [2+2i, -1-1i, 4, -2]
  AssertEquals(2, K[1,0].re, SngTol);  AssertEquals(2, K[1,0].im, SngTol);
  AssertEquals(-1, K[1,1].re, SngTol); AssertEquals(-1, K[1,1].im, SngTol);
  AssertEquals(4, K[1,2].re, SngTol);  AssertEquals(0, K[1,2].im, SngTol);
  AssertEquals(-2, K[1,3].re, SngTol); AssertEquals(0, K[1,3].im, SngTol);
  //Row2: [0+1i, 0, 1, 0]
  AssertEquals(0, K[2,0].re, SngTol); AssertEquals(1, K[2,0].im, SngTol);
  AssertEquals(0, K[2,1].re, SngTol); AssertEquals(0, K[2,1].im, SngTol);
  AssertEquals(1, K[2,2].re, SngTol); AssertEquals(0, K[2,2].im, SngTol);
  AssertEquals(0, K[2,3].re, SngTol); AssertEquals(0, K[2,3].im, SngTol);
  //Row3: [0+2i, 0-1i, 2, -1]
  AssertEquals(0, K[3,0].re, SngTol);  AssertEquals(2, K[3,0].im, SngTol);
  AssertEquals(0, K[3,1].re, SngTol);  AssertEquals(-1, K[3,1].im, SngTol);
  AssertEquals(2, K[3,2].re, SngTol);  AssertEquals(0, K[3,2].im, SngTol);
  AssertEquals(-1, K[3,3].re, SngTol); AssertEquals(0, K[3,3].im, SngTol);
end;

{===========================================================================
  TVMobjITests  (integer index array/matrix, newVMI.pas)
===========================================================================}

procedure TVMobjITests.Raise_CreateZeroRows;
var X: TVMobjI;
begin
  X := TVMobjI.Create(0, 3);
end;

procedure TVMobjITests.Raise_CreateZeroCols;
var X: TVMobjI;
begin
  X := TVMobjI.Create(3, 0);
end;

procedure TVMobjITests.Raise_CreateValuesMismatch;
var X: TVMobjI;
begin
  X := TVMobjI.Create(2, 2, [1, 2, 3]);
end;

procedure TVMobjITests.Raise_ElementRowOutOfRange;
var X: TVMobjI; V: Integer;
begin
  X := TVMobjI.Create(2, 2);
  V := X[2, 0];
end;

procedure TVMobjITests.Raise_ElementColOutOfRange;
var X: TVMobjI; V: Integer;
begin
  X := TVMobjI.Create(2, 2);
  V := X[0, 2];
end;

procedure TVMobjITests.Raise_IdNonSquare;
var X: TVMobjI;
begin
  X := TVMobjI.Create(2, 3);
  X.Id;
end;

procedure TVMobjITests.Raise_FillRandomBadBounds;
var A: TVMobjI;
begin
  A := TVMobjI.Create(2, 2);
  A.fillRandom(5, 5);   //hiBound must be > loBound
end;

procedure TVMobjITests.Raise_GatherNoMatches;
var A, R: TVMobjI;
begin
  A := TVMobjI.Create(2, 2);   //all-zero, so nothing for Gather to find
  R := Gather(A);
end;

procedure TVMobjITests.TestCreateZeroFills;
var A: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(2, 3);
  AssertEquals('Rows', 2, A.Rows);
  AssertEquals('Cols', 3, A.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do
      AssertEquals('zero-fill', 0, A[r, c]);
end;

procedure TVMobjITests.TestCreateInvalidDimsAssert;
begin
  AssertException('zero rows', EAssertionFailed, @Raise_CreateZeroRows);
  AssertException('zero cols', EAssertionFailed, @Raise_CreateZeroCols);
end;

procedure TVMobjITests.TestCreateWithValues;
var A: TVMobjI;
begin
  A := TVMobjI.Create(2, 2, [1, 2, 3, 4]);
  AssertEquals(1, A[0, 0]);
  AssertEquals(2, A[0, 1]);
  AssertEquals(3, A[1, 0]);
  AssertEquals(4, A[1, 1]);
end;

procedure TVMobjITests.TestCreateWithValuesMismatchAsserts;
begin
  AssertException(EAssertionFailed, @Raise_CreateValuesMismatch);
end;

procedure TVMobjITests.TestElementRoundTripNonSquare;
var A: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(3, 4, [1,2,3,4, 5,6,7,8, 9,10,11,12]);
  for r := 0 to 2 do
    for c := 0 to 3 do
      AssertEquals(Format('[%d,%d]', [r, c]), r*4 + c + 1, A[r, c]);
end;

procedure TVMobjITests.TestElementOutOfRangeAsserts;
begin
  AssertException('row out of range', EAssertionFailed, @Raise_ElementRowOutOfRange);
  AssertException('col out of range', EAssertionFailed, @Raise_ElementColOutOfRange);
end;

procedure TVMobjITests.TestWriteMatrixRowCount;
var A: TVMobjI; S: TStringList;
begin
  A := TVMobjI.Create(3, 4);
  S := A.writeMatrix;
  try
    AssertEquals(3, S.Count);
  finally
    S.Free;
  end;
end;

procedure TVMobjITests.TestFillRandomDeterministic;
var A, B: TVMobjI; r, c: Integer;
begin
  //fillRandom seeds a fresh VSL stream with a hard-coded seed (777) every
  //call, so two same-sized/same-bounds fills are bit-for-bit identical -
  //same trick TestFillRandomDeterministic exploits in the other units,
  //just checked element-by-element since TVMobjI has no "=" operator.
  A := TVMobjI.Create(3, 3);
  A.fillRandom(0, 1000);
  B := TVMobjI.Create(3, 3);
  B.fillRandom(0, 1000);
  for r := 0 to 2 do
    for c := 0 to 2 do
      AssertEquals(Format('[%d,%d]', [r, c]), A[r, c], B[r, c]);
end;

procedure TVMobjITests.TestFillRandomWithinBounds;
var A: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(4, 4);
  A.fillRandom(10, 20);
  for r := 0 to 3 do
    for c := 0 to 3 do begin
      AssertTrue(Format('[%d,%d] >= loBound', [r, c]), A[r, c] >= 10);
      AssertTrue(Format('[%d,%d] < hiBound', [r, c]), A[r, c] < 20);
    end;
end;

procedure TVMobjITests.TestFillRandomBadBoundsAsserts;
begin
  AssertException(EAssertionFailed, @Raise_FillRandomBadBounds);
end;

procedure TVMobjITests.TestIdIdentity;
var A: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(3, 3);
  A.Id;
  for r := 0 to 2 do
    for c := 0 to 2 do
      if r = c then
        AssertEquals(1, A[r, c])
      else
        AssertEquals(0, A[r, c]);
end;

procedure TVMobjITests.TestIdNonSquareAsserts;
begin
  AssertException(EAssertionFailed, @Raise_IdNonSquare);
end;

procedure TVMobjITests.TestDataPtrAddressable;
var A: TVMobjI; P: PInteger;
begin
  A := TVMobjI.Create(2, 2);
  P := A.DataPtr;
  P^ := 42;
  AssertEquals(42, A[0, 0]);
end;

procedure TVMobjITests.TestCopyObjIndependence;
var A, B: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(2, 2);
  A.fillRandom(0, 1000);
  B := CopyObjI(A);
  for r := 0 to 1 do
    for c := 0 to 1 do
      AssertEquals(Format('[%d,%d]', [r, c]), A[r, c], B[r, c]);
  B[1, 1] := B[1, 1] + 1;
  AssertFalse(A[1, 1] = B[1, 1]);
end;

procedure TVMobjITests.TestTransposeSwapsDimsAndElements;
var A, T: TVMobjI; r, c: Integer;
begin
  A := TVMobjI.Create(2, 3, [1,2,3, 4,5,6]);
  T := A.Transpose;
  AssertEquals('Rows', 3, T.Rows);
  AssertEquals('Cols', 2, T.Cols);
  for r := 0 to 1 do
    for c := 0 to 2 do
      AssertEquals(Format('[%d,%d]', [r, c]), A[r, c], T[c, r]);
end;

procedure TVMobjITests.TestLinspaceKnownValues;
var A: TVMobjI; i: Integer;
begin
  A := TVMobjI.Create(1, 5);
  A.linspace(10, 2);
  for i := 0 to 4 do
    AssertEquals(Format('[0,%d]', [i]), 10 + i*2, A[0, i]);
end;

procedure TVMobjITests.TestGatherReturnsIndexes;
var A, R: TVMobjI;
begin
  //row-major linear indexes: [0,0]=0 [0,1]=1 [0,2]=2 [1,0]=3 [1,1]=4 [1,2]=5
  A := TVMobjI.Create(2, 3, [0, 5, 0, 3, 0, 7]);
  R := Gather(A);
  AssertEquals('Rows', 1, R.Rows);
  AssertEquals('Cols', 3, R.Cols);
  AssertEquals(1, R[0, 0]);
  AssertEquals(3, R[0, 1]);
  AssertEquals(5, R[0, 2]);
end;

procedure TVMobjITests.TestGatherNoMatchesAsserts;
begin
  AssertException(EAssertionFailed, @Raise_GatherNoMatches);
end;

initialization
  RegisterTest(TVMobjTests);
  RegisterTest(TVMobjSTests);
  RegisterTest(TVMobjZTests);
  RegisterTest(TVMobjCTests);
  RegisterTest(TVMobjITests);

end.
