program newVMsparsetest;

{*******************************************************************************

     Correctness check (with timings) for newVMsparse.pas - the sparse unit
     has no FPCUnit coverage in newVMTests.pas, so this is its regression
     test. Exits non-zero if any check fails.

     Test problems: a 2-D 5-point Laplacian on an m x m grid (symmetric
     positive definite) and the same stencil with an added convection term
     on the east/west couplings (unsymmetric). The right-hand side is
     B := A*Xtrue for a known Xtrue, and every solve is checked by its
     relative residual |A*X-B|/|B| (not against Xtrue, so an
     ill-conditioned-but-correct solve still passes).

     Checks, at m=6 (small) and m=400 (160,000 unknowns):
       - SparseMatMult against two hand-computed rows
       - PardisoSolve, SymmetricPosDef=True (mtype 2) and False (mtype 11)
       - FGMRESSolve with and without ILU0
     then the large case again at 1 thread and at twice MKL's default,
     checking SetMKLThreads/GetMKLThreads along the way. MKL caps the
     thread count at the number of physical cores while its dynamic mode
     is on (the default), so the "twice default" request is only checked
     for not exceeding what was asked.

     Build (plain fpc, same as newVMbench.lpr - no LCL needed):

       fpc -Fu. -Fi. -Sa newVMsparsetest.lpr

     -Sa enables assertions, which the newVM units use for argument
     checking (the .lpi-based builds get this from IncludeAssertionCode).

     Run:

       ./newVMsparsetest

*******************************************************************************}

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, Math, cblas, hirestimer, newVM, newVMsparse;

var
  failures: Integer = 0;

procedure Check(const name: string; ok: Boolean; const detail: string);
begin
  if ok then WriteLn('PASS ', name, '  ', detail)
  else
  begin
    WriteLn('FAIL ', name, '  ', detail);
    Inc(failures);
  end;
end;

{ 2-D 5-point Laplacian on an m x m grid (SPD). Skew adds an unsymmetric
  convection term to the east/west couplings. }
function BuildMatrix(m: Integer; Skew: Double): TVMSparseMtx;
var
  Ri, Ci: TIntegerArray;
  Vv: TDoubleArray;
  k, i, j, p: Integer;

  procedure Add(r, c: Integer; val: Double);
  begin
    Ri[k] := r; Ci[k] := c; Vv[k] := val; Inc(k);
  end;

begin
  SetLength(Ri, 5*m*m); SetLength(Ci, 5*m*m); SetLength(Vv, 5*m*m);
  k := 0;
  for i := 0 to m-1 do
    for j := 0 to m-1 do
    begin
      p := i*m+j;
      Add(p, p, 4.0);
      if i > 0 then Add(p, p-m, -1.0);
      if i < m-1 then Add(p, p+m, -1.0);
      if j > 0 then Add(p, p-1, -1.0 - Skew);
      if j < m-1 then Add(p, p+1, -1.0 + Skew);
    end;
  SetLength(Ri, k); SetLength(Ci, k); SetLength(Vv, k);
  result := TripletsToSparse(m*m, m*m, Ri, Ci, Vv);
end;

function RelResidual(const A: TVMSparseMtx; const X, B: TVMobj): Double;
var
  AX: TVMobj;
  i: Integer;
  num, den: Double;
begin
  AX := SparseMatMult(A, X);
  num := 0; den := 0;
  for i := 0 to B.Rows*B.Cols-1 do
  begin
    num := num + Sqr(AX.DataPtr[i] - B.DataPtr[i]);
    den := den + Sqr(B.DataPtr[i]);
  end;
  result := Sqrt(num/den);
end;

function Timing(r, ms: Double): string;
begin
  result := Format('resid=%.3e  %.0f ms', [r, ms]);
end;

procedure RunAll(const tag: string; m: Integer);
var
  A, U: TVMSparseMtx;
  B, X, Xtrue, AX: TVMobj;
  n, i: Integer;
  t: Double;
  r: Double;
begin
  n := m*m;
  A := BuildMatrix(m, 0.0);
  U := BuildMatrix(m, 0.3);
  Xtrue := TVMobj.Create(n, 1);
  for i := 0 to n-1 do Xtrue.DataPtr[i] := Sin(0.01*i) + 1.0;

  //Known values with x = all ones: the corner row is 4-1-1 = 2, an
  //interior row is 4-1-1-1-1 = 0.
  B := TVMobj.Create(n, 1);
  for i := 0 to n-1 do B.DataPtr[i] := 1.0;
  AX := SparseMatMult(A, B);
  Check(tag+' SparseMatMult corner', SameValue(AX.DataPtr[0], 2.0, 1e-12), FloatToStr(AX.DataPtr[0]));
  Check(tag+' SparseMatMult interior', SameValue(AX.DataPtr[m+1], 0.0, 1e-12), FloatToStr(AX.DataPtr[m+1]));

  B := SparseMatMult(A, Xtrue);
  t := HighResTimer.MilliSeconds;
  X := PardisoSolve(A, B, True);
  t := HighResTimer.MilliSeconds - t;
  r := RelResidual(A, X, B);
  Check(tag+' Pardiso SPD', r < 1e-10, Timing(r, t));

  B := SparseMatMult(U, Xtrue);
  t := HighResTimer.MilliSeconds;
  X := PardisoSolve(U, B, False);
  t := HighResTimer.MilliSeconds - t;
  r := RelResidual(U, X, B);
  Check(tag+' Pardiso unsym', r < 1e-10, Timing(r, t));

  t := HighResTimer.MilliSeconds;
  X := FGMRESSolve(U, B, True, 2000, 1e-10);
  t := HighResTimer.MilliSeconds - t;
  r := RelResidual(U, X, B);
  Check(tag+' FGMRES+ILU0', r < 1e-8, Timing(r, t));

  t := HighResTimer.MilliSeconds;
  X := FGMRESSolve(U, B, False, 2000, 1e-10);
  t := HighResTimer.MilliSeconds - t;
  r := RelResidual(U, X, B);
  Check(tag+' FGMRES plain', r < 1e-8, Timing(r, t));
end;

var
  defaultThreads, requested: Integer;
begin
  InitializeCBLAS;
  defaultThreads := GetMKLThreads;
  WriteLn('Default MKL threads: ', defaultThreads);
  RunAll('small', 6);
  RunAll('large', 400);

  SetMKLThreads(1);
  Check('SetMKLThreads(1)', GetMKLThreads = 1, IntToStr(GetMKLThreads));
  RunAll('large/1thr', 400);

  requested := 2*defaultThreads;
  SetMKLThreads(requested);
  Check(Format('SetMKLThreads(%d)', [requested]),
    (GetMKLThreads >= 1) and (GetMKLThreads <= requested), 'got ' + IntToStr(GetMKLThreads));
  RunAll(Format('large/%dthr', [GetMKLThreads]), 400);

  SetMKLThreads(0);
  Check('SetMKLThreads(0) restores default', GetMKLThreads = defaultThreads, IntToStr(GetMKLThreads));

  WriteLn(failures, ' failure(s)');
  if failures > 0 then Halt(1);
end.
