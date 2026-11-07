{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

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

{ A nonsingular matrix whose diagonal is EXPLICITLY STORED BUT ZERO, which
  is what FEM4's frequency-domain block systems look like (uDescriptor's
  FactorFrequency adds a zero diagonal entry to every row so that a sparse
  direct solver has a slot there). Solving it needs a genuine row
  interchange, so this is the regression test for a backend that fails to
  pivot - which an Accelerate build did, silently, returning NaN with an
  OK status, until its pivotTolerance was set to the library's own default
  rather than 0. Nothing else in this file needs pivoting at all. }
procedure ZeroDiagonalPivot;
var
  R, C: TIntegerArray;
  V: TDoubleArray;
  A: TVMSparseMtx;
  B, X: TVMobj;
  ok: Boolean;
begin
  SetLength(R, 4); SetLength(C, 4); SetLength(V, 4);
  //[[0 1],[1 0]] * (5,3) = (3,5)
  R[0]:=0; C[0]:=1; V[0]:=1.0;
  R[1]:=1; C[1]:=0; V[1]:=1.0;
  R[2]:=0; C[2]:=0; V[2]:=0.0;   //explicit zero diagonal
  R[3]:=1; C[3]:=1; V[3]:=0.0;
  A := TripletsToSparse(2, 2, R, C, V);
  B := TVMobj.Create(2,1); B.DataPtr[0] := 3.0; B.DataPtr[1] := 5.0;
  X := PardisoSolve(A, B, False);
  ok := SameValue(X.DataPtr[0], 5.0, 1e-12) and SameValue(X.DataPtr[1], 3.0, 1e-12);
  Check('zero-diagonal pivot', ok,
    Format('x = %.6f %.6f (expect 5, 3)', [X.DataPtr[0], X.DataPtr[1]]));
end;

var
  defaultThreads, requested: Integer;
begin
  InitializeCBLAS;
  ZeroDiagonalPivot;
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
