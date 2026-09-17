program newVMsparserestartbench;

{*******************************************************************************

     Times newVMsparse.pas's FGMRESSolve across restart lengths (its
     Restart parameter), with and without ILU0, on two m=400 (160,000
     unknown) problems: a 2-D 5-point Laplacian (SPD) and the same stencil
     with an unsymmetric convection term. Runs at MKL's default thread
     count and at 1 thread. Each run reports its relative residual and
     flags any that didn't converge within MaxIter.

     Results on the development machine (Ryzen 9 7900, 12 threads, MKL
     2026.1), Tol=1e-10, MaxIter=20000:

       restart  unsym+ILU0  unsym plain  SPD+ILU0  SPD plain
          5       758 ms      572 ms     23.2 s   not converged
         10      1.08 s       764 ms     14.1 s   not converged
         20      1.49 s      1.31 s       8.8 s      13.8 s
         30      2.18 s      1.96 s       7.2 s      21.9 s
         50      3.23 s      4.25 s       5.2 s      28.9 s
        100      4.82 s      9.63 s      4.45 s      29.9 s
        150      3.80 s      16.2 s       6.8 s      31.8 s

     i.e. there is no single best restart - short restarts win on the
     unsymmetric problem and lose badly on the SPD one - so FGMRESSolve
     keeps its default of 150 and exposes Restart for callers to tune.
     1 thread vs 12 differs by only 5-40%. PardisoSolve solves both
     systems in under 200 ms (see newVMsparsetest.lpr).

     Build (plain fpc, same as newVMbench.lpr):

       fpc -Fu. -Fi. -Sa newVMsparserestartbench.lpr

     Run (takes several minutes):

       ./newVMsparserestartbench

*******************************************************************************}

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas, hirestimer, newVM, newVMsparse;

const
  M = 400;
  MaxIter = 20000;
  Tol = 1e-10;
  Restarts: array[0..6] of Integer = (5, 10, 20, 30, 50, 100, 150);

function BuildMatrix(Skew: Double): TVMSparseMtx;
var
  Ri, Ci: TIntegerArray;
  Vv: TDoubleArray;
  k, i, j, p: Integer;

  procedure Add(r, c: Integer; val: Double);
  begin
    Ri[k] := r; Ci[k] := c; Vv[k] := val; Inc(k);
  end;

begin
  SetLength(Ri, 5*M*M); SetLength(Ci, 5*M*M); SetLength(Vv, 5*M*M);
  k := 0;
  for i := 0 to M-1 do
    for j := 0 to M-1 do
    begin
      p := i*M+j;
      Add(p, p, 4.0);
      if i > 0 then Add(p, p-M, -1.0);
      if i < M-1 then Add(p, p+M, -1.0);
      if j > 0 then Add(p, p-1, -1.0 - Skew);
      if j < M-1 then Add(p, p+1, -1.0 + Skew);
    end;
  SetLength(Ri, k); SetLength(Ci, k); SetLength(Vv, k);
  result := TripletsToSparse(M*M, M*M, Ri, Ci, Vv);
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

procedure Sweep(const Name: string; const A: TVMSparseMtx; UseILU0: Boolean);
var
  B, X, Xtrue: TVMobj;
  i, ri: Integer;
  t, r: Double;
  label_, msg: string;
begin
  Xtrue := TVMobj.Create(M*M, 1);
  for i := 0 to M*M-1 do Xtrue.DataPtr[i] := Sin(0.01*i) + 1.0;
  B := SparseMatMult(A, Xtrue);
  if UseILU0 then label_ := Name + ' +ILU0' else label_ := Name + ' plain';
  for ri := Low(Restarts) to High(Restarts) do
  begin
    t := HighResTimer.MilliSeconds;
    try
      X := FGMRESSolve(A, B, UseILU0, MaxIter, Tol, Restarts[ri]);
      t := HighResTimer.MilliSeconds - t;
      r := RelResidual(A, X, B);
      msg := Format('%8.0f ms  resid=%.2e', [t, r]);
      if r >= 1e-8 then msg := msg + '  NOT CONVERGED';
    except
      on E: Exception do msg := 'ERROR ' + E.Message;
    end;
    WriteLn(Format('  %-14s restart=%3d  %s', [label_, Restarts[ri], msg]));
  end;
end;

var
  U, S: TVMSparseMtx;
  threadCounts: array[0..1] of Integer;
  k: Integer;
begin
  InitializeCBLAS;
  U := BuildMatrix(0.3);
  S := BuildMatrix(0.0);
  //an array, not "for nt in [a, b]" - that's a set constructor, which
  //iterates in ascending order and can't hold values above 255
  threadCounts[0] := GetMKLThreads;
  threadCounts[1] := 1;
  for k := Low(threadCounts) to High(threadCounts) do
  begin
    SetMKLThreads(threadCounts[k]);
    WriteLn('--- ', GetMKLThreads, ' thread(s), n=', M*M, ' ---');
    Sweep('unsym', U, True);
    Sweep('unsym', U, False);
    Sweep('SPD', S, True);
    Sweep('SPD', S, False);
  end;
  SetMKLThreads(0);
end.
