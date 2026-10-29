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

program checkwrm;

{ Console checks of ufilmwrmmodel.pas:
    fpc -O2 -Fu../.. -Fi../.. checkwrm.lpr && ./checkwrm }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  SysUtils, Math, cblas, newVM, ufilmwrmmodel;

function MaxDev(const H: TVMobj): Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to H.Rows * H.Cols - 1 do Result := Max(Result, Abs(H.DataPtr[i] - 1));
end;

function MeanH(const H: TVMobj): Double;
var i: Integer;
begin
  Result := 0;
  for i := 0 to H.Rows * H.Cols - 1 do Result := Result + H.DataPtr[i];
  Result := Result / (H.Rows * H.Cols);
end;

procedure RunTo(M: TFilmWRMModel; t: Double);
var Msg: string;
begin
  while M.Time < t do
    if not M.Advance(Msg) then
    begin
      WriteLn('  FAILED: ', Msg);
      Halt(1);
    end;
end;

var
  P: TFilmParams;
  M: TFilmWRMModel;
  H0: TVMobj;
  i, j: Integer;
  kx, ky, a1, a2, mn, mx, t0, wall, centre: Double;
begin
  InitializeCBLAS;
  // 1. one oblique mode grows at the linear rate
  P := DefaultFilmParams;
  P.Nx := 64; P.Ny := 16;
  M := TFilmWRMModel.Create(P);
  kx := 2 * Pi * 4 / P.Lx;
  ky := 2 * Pi / P.W;                   // n = 2
  H0 := M.Flat;
  for j := 0 to P.Ny do
    for i := 0 to P.Nx - 1 do
      H0.DataPtr[j * P.Nx + i] := 1 + 1e-6 * Cos(kx * M.X.DataPtr[i]) * Cos(ky * (M.Y.DataPtr[j] + P.W / 2));
  M.Start(H0, 1e-3);
  RunTo(M, 4); a1 := MaxDev(M.H);
  RunTo(M, 6); a2 := MaxDev(M.H);
  WriteLn(Format('1. mode kx %.4f ky %.4f: growth %.4f /s, theory %.4f (steps %d, rejected %d)',
    [kx, ky, Ln(a2 / a1) / (M.Time - 4), M.GrowthAt2(kx, ky), M.Steps, M.Rejected]));
  M.Free;

  // 2. y-uniform bump against the numpy 1-D prototype at t = 4.5 s: de-aliased
  //    N 256 0.394 .. 1.446, undealiased N 512/1024 0.386/0.383 .. 1.443
  P := DefaultFilmParams;
  P.Ny := 8;
  M := TFilmWRMModel.Create(P);
  H0 := M.Flat;
  for j := 0 to P.Ny do
    for i := 0 to P.Nx - 1 do
      H0.DataPtr[j * P.Nx + i] := 1 + 0.05 * Exp(-Sqr((M.X.DataPtr[i] - 60) / 10));
  t0 := Now;
  M.Start(H0, 1e-3);
  RunTo(M, 4.5);
  mn := 9; mx := 0;
  for i := 0 to M.H.Rows * M.H.Cols - 1 do
  begin
    mn := Min(mn, M.H.DataPtr[i]);
    mx := Max(mx, M.H.DataPtr[i]);
  end;
  WriteLn(Format('2. 1-D bump, t = %.2f: h %.3f .. %.3f hN (numpy 0.394 .. 1.446), mean %.6f, max |p| %.2e',
    [M.Time, mn, mx, MeanH(M.H), MaxDev(AddScalar(M.FlowP, 1))]));
  WriteLn(Format('   %d steps, %d rejected, %d inverses, beta %.2f, dt %.2e; %.1f s; RHS %.1f s (transforms %.1f)',
    [M.Steps, M.Rejected, M.Systems, M.Beta, M.Dt, (Now - t0) * 86400, M.RHSTime, M.TransTime]));
  M.Free;

  // 3. linear forced wave and its transverse modulation
  P := DefaultFilmParams;
  P.Excite := True; P.ExciteAmp := 1e-4; P.ExciteMod := 0.2; P.ExciteModN := 2;
  P.Absorb := True;
  M := TFilmWRMModel.Create(P);
  M.Start(M.Flat, 1e-3);
  RunTo(M, 2.0);
  wall := 0; centre := 0;
  for i := 0 to P.Nx - 1 do
    if (M.X.DataPtr[i] > 20) and (M.X.DataPtr[i] < M.AbsorbStart) then
    begin
      wall := Max(wall, Abs(M.H.DataPtr[i] - 1));
      centre := Max(centre, Abs(M.H.DataPtr[CentreRow(P) * P.Nx + i] - 1));
    end;
  WriteLn(Format('3. forced, a = 1e-4 hN, T = %.2f s: wall %.3e, centre %.3e hN, ratio %.3f (1.5); mean %.6f',
    [P.ExcitePeriod, wall, centre, wall / centre, MeanH(M.H)]));
  WriteLn(Format('   wave speed %.1f mm/s (kinematic %.1f), forced wavelength %.1f mm, growth %.3f /s',
    [M.WaveSpeed, M.KinematicSpeed, 2 * Pi / M.ForcedK(P.ExcitePeriod), M.GrowthAt(M.ForcedK(P.ExcitePeriod))]));
  M.Free;

  // 4. timing: the default 2-D grid, bump + noise, 1 s
  P := DefaultFilmParams;
  M := TFilmWRMModel.Create(P);
  H0 := M.Flat + M.Bump(0.2, P.Lx / 5, Pi / M.FastestK / 2) + M.Noise(1e-3, 20261015);
  t0 := Now;
  M.Start(H0, 1e-3);
  RunTo(M, 1.0);
  mn := 9; mx := 0;
  for i := 0 to M.H.Rows * M.H.Cols - 1 do
  begin
    mn := Min(mn, M.H.DataPtr[i]);
    mx := Max(mx, M.H.DataPtr[i]);
  end;
  WriteLn(Format('4. default grid %d x %d, t = 1 s: h %.3f .. %.3f; %d steps (%d rejected), dt %.2e; %.1f s wall',
    [P.Nx, P.Ny + 1, mn, mx, M.Steps, M.Rejected, M.Dt, (Now - t0) * 86400]));
  WriteLn(Format('   RHS %d calls %.1f s (transforms %.1f s), solves %.2f s, %d inverses',
    [M.RHSCalls, M.RHSTime, M.TransTime, M.SolveTime, M.Systems]));
  M.Free;
end.
