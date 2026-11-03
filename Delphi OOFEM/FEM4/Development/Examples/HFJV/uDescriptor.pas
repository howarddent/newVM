unit uDescriptor;

{ A sparse linear descriptor system

      E x' = A x + b(t)

  assembled from triplets by any number of parts (the abdominal fluid,
  the lung, the chest wall, the jet), each taking a block of unknowns
  with NewDofs and adding its own entries. A row whose E part is empty
  is ALGEBRAIC - a constraint 0 = A x + b, such as the incompressible
  fluid's K phi = S v - and must be flagged with SetAlgebraic.

  The same two matrices serve both analyses:

  Frequency domain, x = Re(X exp(i w t)): (i w E - A) X = B, solved as
  the real system of twice the size

        [ -A   -wE ] [Xr]   [Br]
        [ wE    -A ] [Xi] = [Bi]

  by PARDISO (unsymmetric, so no assumptions about the parts' symmetry).

  Time domain: the trapezoidal rule on the differential rows,

        (E/dt - A/2) x1 = (E/dt + A/2) x0 + (b0 + b1)/2,

  and the algebraic rows imposed at the new time, -A x1 = b1. The
  trapezoidal rule is A-stable and conserves the energy of an undamped
  linear system, so a free oscillation keeps its amplitude; the
  algebraic rows are not averaged, since averaging a constraint between
  two times lets it oscillate step to step. The step matrix is
  factorised once (TPardisoFactor) and reused, so dt is fixed per
  stepper.

  An unknown's E row may couple to algebraic unknowns' rates - the
  fluid's momentum m v + rho S' phi is the differential quantity, with
  phi fixed by v through the constraint. That is the form in which the
  trapezoidal rule above is the rule for the equivalent ODE in v alone
  (phi is linear in v), so it keeps its stability. }

{$mode delphi}{$H+}

interface

uses SysUtils, newVM, newVMsparse;

type
  TVMobjArray = array of TVMobj;

  TTriplets = record
    R, C : TIntegerArray;
    V : TDoubleArray;
    Count : Integer;
    procedure Add(i, j : Integer; Value : Double);
    procedure Clear;
  end;

  TDescriptorSystem = class
  private
    FN : Integer;
    FE, FA : TTriplets;
    FAlg : TBooleanArray;
    FEm, FAm : TVMSparseMtx;
    FBuilt : Boolean;
  public
    function NewDofs(Count : Integer) : Integer;
    procedure AddE(i, j : Integer; Value : Double);
    procedure AddA(i, j : Integer; Value : Double);
    procedure SetAlgebraic(i : Integer);
    function IsAlgebraic(i : Integer) : Boolean;
    { Builds the sparse E and A from the triplets; called automatically. }
    procedure Build;
    { (i w E - A) X = B. Br, Bi and the results are (N,1). }
    procedure SolveFrequency(Omega : Double; const Br, Bi : TVMobj;
      out Xr, Xi : TVMobj);
    { The same for several right-hand sides on one factorisation. }
    procedure SolveFrequencyN(Omega : Double; const Br, Bi : array of TVMobj;
      out Xr, Xi : TVMobjArray);
    function MulE(const X : TVMobj) : TVMobj;
    function MulA(const X : TVMobj) : TVMobj;
    property N : Integer read FN;
  end;

  { Trapezoidal stepper at a fixed dt. B is evaluated by the caller. }
  TTrapezoidStepper = class
  private
    FSys : TDescriptorSystem;
    FDt : Double;
    FLU : TPardisoFactor;
  public
    constructor Create(Sys : TDescriptorSystem; Dt : Double);
    destructor Destroy; override;
    { One step from X0 with forcing B0 at t and B1 at t + dt. }
    function Step(const X0, B0, B1 : TVMobj) : TVMobj;
    { The step matrix's inverse applied to B: how the new state answers
      to an extra forcing B on the step's right-hand side. }
    function Solve(const B : TVMobj) : TVMobj;
    property Dt : Double read FDt;
  end;

implementation

{ TTriplets }

procedure TTriplets.Add(i, j : Integer; Value : Double);
begin
  if Count >= Length(R) then
  begin
    SetLength(R, 2 * Count + 1024);
    SetLength(C, 2 * Count + 1024);
    SetLength(V, 2 * Count + 1024);
  end;
  R[Count] := i;
  C[Count] := j;
  V[Count] := Value;
  Inc(Count);
end;

procedure TTriplets.Clear;
begin
  R := nil; C := nil; V := nil; Count := 0;
end;

function Trimmed(const T : TTriplets; out R, C : TIntegerArray;
  out V : TDoubleArray) : Integer;
begin
  R := Copy(T.R, 0, T.Count);
  C := Copy(T.C, 0, T.Count);
  V := Copy(T.V, 0, T.Count);
  Result := T.Count;
end;

{ TDescriptorSystem }

function TDescriptorSystem.NewDofs(Count : Integer) : Integer;
begin
  Result := FN;
  Inc(FN, Count);
  SetLength(FAlg, FN);
  FBuilt := False;
end;

procedure TDescriptorSystem.AddE(i, j : Integer; Value : Double);
begin
  Assert((i >= 0) and (i < FN) and (j >= 0) and (j < FN), 'AddE : index out of range');
  if Value <> 0 then FE.Add(i, j, Value);
  FBuilt := False;
end;

procedure TDescriptorSystem.AddA(i, j : Integer; Value : Double);
begin
  Assert((i >= 0) and (i < FN) and (j >= 0) and (j < FN), 'AddA : index out of range');
  if Value <> 0 then FA.Add(i, j, Value);
  FBuilt := False;
end;

procedure TDescriptorSystem.SetAlgebraic(i : Integer);
begin
  FAlg[i] := True;
end;

function TDescriptorSystem.IsAlgebraic(i : Integer) : Boolean;
begin
  Result := FAlg[i];
end;

procedure TDescriptorSystem.Build;
var
  R, C : TIntegerArray;
  V : TDoubleArray;
  k, n : Integer;
begin
  if FBuilt then Exit;
  for k := 0 to FE.Count - 1 do
    if FAlg[FE.R[k]] then
      raise Exception.CreateFmt('TDescriptorSystem : row %d is flagged ' +
        'algebraic but has an E entry', [FE.R[k]]);
  n := Trimmed(FE, R, C, V);
  // a zero diagonal keeps every row present in the pattern
  SetLength(R, n + FN); SetLength(C, n + FN); SetLength(V, n + FN);
  for k := 0 to FN - 1 do
  begin
    R[n + k] := k; C[n + k] := k; V[n + k] := 0;
  end;
  FEm := TripletsToSparse(FN, FN, R, C, V);
  n := Trimmed(FA, R, C, V);
  SetLength(R, n + FN); SetLength(C, n + FN); SetLength(V, n + FN);
  for k := 0 to FN - 1 do
  begin
    R[n + k] := k; C[n + k] := k; V[n + k] := 0;
  end;
  FAm := TripletsToSparse(FN, FN, R, C, V);
  FBuilt := True;
end;

function TDescriptorSystem.MulE(const X : TVMobj) : TVMobj;
begin
  Build;
  Result := SparseMatMult(FEm, X);
end;

function TDescriptorSystem.MulA(const X : TVMobj) : TVMobj;
begin
  Build;
  Result := SparseMatMult(FAm, X);
end;

procedure TDescriptorSystem.SolveFrequency(Omega : Double; const Br, Bi : TVMobj;
  out Xr, Xi : TVMobj);
var
  R, I : TVMobjArray;
begin
  SolveFrequencyN(Omega, [Br], [Bi], R, I);
  Xr := R[0];
  Xi := I[0];
end;

procedure TDescriptorSystem.SolveFrequencyN(Omega : Double; const Br, Bi : array of TVMobj;
  out Xr, Xi : TVMobjArray);
var
  j : Integer;
  T : TTriplets;
  k, i, nn : Integer;
  R, C : TIntegerArray;
  V : TDoubleArray;
  M : TVMSparseMtx;
  B, X : TVMobj;
  LU : TPardisoFactor;
begin
  Build;
  nn := FN;
  T.Clear;
  for k := 0 to FA.Count - 1 do
  begin
    T.Add(FA.R[k], FA.C[k], -FA.V[k]);
    T.Add(nn + FA.R[k], nn + FA.C[k], -FA.V[k]);
  end;
  for k := 0 to FE.Count - 1 do
  begin
    T.Add(FE.R[k], nn + FE.C[k], -Omega * FE.V[k]);
    T.Add(nn + FE.R[k], FE.C[k], Omega * FE.V[k]);
  end;
  for i := 0 to 2 * nn - 1 do
    T.Add(i, i, 0);
  Trimmed(T, R, C, V);
  M := TripletsToSparse(2 * nn, 2 * nn, R, C, V);
  SetLength(Xr, Length(Br));
  SetLength(Xi, Length(Br));
  LU := TPardisoFactor.Create(M, 11);
  try
    for j := 0 to High(Br) do
    begin
      B := TVMobj.Create(2 * nn, 1);
      Move(Br[j].DataPtr[0], B.DataPtr[0], nn * SizeOf(Double));
      Move(Bi[j].DataPtr[0], B.DataPtr[nn], nn * SizeOf(Double));
      X := LU.Solve(B);
      Xr[j] := TVMobj.Create(nn, 1);
      Xi[j] := TVMobj.Create(nn, 1);
      Move(X.DataPtr[0], Xr[j].DataPtr[0], nn * SizeOf(Double));
      Move(X.DataPtr[nn], Xi[j].DataPtr[0], nn * SizeOf(Double));
    end;
  finally
    LU.Free;
  end;
end;

{ TTrapezoidStepper }

constructor TTrapezoidStepper.Create(Sys : TDescriptorSystem; Dt : Double);
var
  T : TTriplets;
  k, i : Integer;
  R, C : TIntegerArray;
  V : TDoubleArray;
begin
  inherited Create;
  FSys := Sys;
  FDt := Dt;
  Sys.Build;
  T.Clear;
  for k := 0 to Sys.FE.Count - 1 do
    T.Add(Sys.FE.R[k], Sys.FE.C[k], Sys.FE.V[k] / Dt);
  for k := 0 to Sys.FA.Count - 1 do
    if Sys.FAlg[Sys.FA.R[k]] then
      T.Add(Sys.FA.R[k], Sys.FA.C[k], -Sys.FA.V[k])
    else
      T.Add(Sys.FA.R[k], Sys.FA.C[k], -0.5 * Sys.FA.V[k]);
  for i := 0 to Sys.N - 1 do
    T.Add(i, i, 0);
  Trimmed(T, R, C, V);
  FLU := TPardisoFactor.Create(TripletsToSparse(Sys.N, Sys.N, R, C, V), 11);
end;

destructor TTrapezoidStepper.Destroy;
begin
  FLU.Free;
  inherited Destroy;
end;

function TTrapezoidStepper.Step(const X0, B0, B1 : TVMobj) : TVMobj;
var
  EX, AX, Rhs : TVMobj;
  i : Integer;
  e, a, b0_, b1_ : PDouble;
  r : PDouble;
begin
  EX := FSys.MulE(X0);
  AX := FSys.MulA(X0);
  Rhs := TVMobj.Create(FSys.N, 1);
  e := EX.DataPtr; a := AX.DataPtr; b0_ := B0.DataPtr; b1_ := B1.DataPtr;
  r := Rhs.DataPtr;
  for i := 0 to FSys.N - 1 do
    if FSys.FAlg[i] then
      r[i] := b1_[i]
    else
      r[i] := e[i] / FDt + 0.5 * a[i] + 0.5 * (b0_[i] + b1_[i]);
  Result := FLU.Solve(Rhs);
end;

function TTrapezoidStepper.Solve(const B : TVMobj) : TVMobj;
begin
  Result := FLU.Solve(B);
end;

end.
