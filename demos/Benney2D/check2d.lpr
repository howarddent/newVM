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

program check2d;
{ Console checks of ubenney2dmodel, built with plain fpc (no LCL):
    fpc -O2 -Fu../.. -Fi../.. check2d.lpr
  1. the linear growth rate of one cos(kx x) cos(pi (y + W/2)/W) mode on
     a 1 mm film at 1 deg, against (I - G) kx^2 - G ky^2 - S (kx^2 + ky^2)^2
     = 3.7024 /s (the numpy prototype's figure);
  2. a 0.2 bump on the default 0.2 mm film to t = 20 s, serial then
     threaded: the same film both ways (numpy prototype: max H 1.093 at
     t = 10, 1.062 at 20), with the time each half took. On this
     hybrid-core machine pin it (taskset -c 2,4) to compare timings -
     unpinned runs vary up to 2x with which cores the threads land on. }
{$mode objfpc}{$H+}
uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  SysUtils, Math, cblas, newVM, newVMComplex, ubenney2dmodel;

procedure Linear(Threaded: Boolean);
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  H0: TVMobj;
  i, j: Integer;
  kx, ky, sig, a0, a1, msgok: Double;
  E: TVMobjZ;
  Msg: string;
begin
  P := DefaultBenney2DParams;
  P.Threaded := Threaded;
  P.hN := 1.0; P.Theta := DegToRad(1.0);     // the prototype's growth test
  P.SigmaRho := 72.0e3;
  P.Tol := 1e-9;               // absolute, and the mode is only 1e-4 high
  M := TBenney2DModel.Create(P);
  kx := 2 * Pi * 5 / P.Lx; ky := Pi / P.W;
  H0 := M.Flat;
  for j := 0 to P.Ny do
    for i := 0 to P.Nx - 1 do
      H0.DataPtr[j * P.Nx + i] := 1 + 1e-4 * Cos(kx * M.X.DataPtr[i]) * Cos(ky * (M.Y.DataPtr[j] + P.W / 2));
  E := M.ToModes(AddScalar(H0, -1));
  a0 := 0; for j := 0 to P.Ny do a0 := Max(a0, Sqrt(Sqr(E[j, 5].re) + Sqr(E[j, 5].im)));
  M.Start(H0, 1e-3);
  while M.Time < 1.0 do
    if not M.Advance(Msg) then begin WriteLn('FAILED ', Msg); Exit; end;
  E := M.ToModes(AddScalar(M.H, -1));
  a1 := 0; for j := 0 to P.Ny do a1 := Max(a1, Sqrt(Sqr(E[j, 5].re) + Sqr(E[j, 5].im)));
  // growth rate from the model's own coefficients
  sig := Ln(a1 / a0) / M.Time;
  WriteLn(Format('linear mode: measured growth %.4f /s at t = %.3f (%d steps, %d rejected)',
    [sig, M.Time, M.Steps, M.Rejected]));
  M.Free;
end;

procedure BumpRun(Threaded: Boolean; T: Double);
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  H0: TVMobj;
  Msg: string;
  next, t0: Double;
  i: Integer;
  mx, mn: Double;
begin
  P := DefaultBenney2DParams;
  P.Threaded := Threaded;
  M := TBenney2DModel.Create(P);
  WriteLn(Format('0.2 mm, %.2f deg: Re %.3f, Re_c %.3f, ratio %.3f; speed %.1f mm/s; fastest wavelength %.1f mm; growth %.4f /s',
    [RadToDeg(P.Theta), M.Re, M.ReCrit, M.Re / M.ReCrit, M.WaveSpeed, 2 * Pi / M.FastestK, M.MaxGrowth]));
  H0 := AddScalar(M.Bump(0.2, 60, 27), 1);
  M.Start(H0, 1e-3);
  next := 10; t0 := GetTickCount64 / 1000;
  while M.Time < T - 1e-9 do
  begin
    if not M.Advance(Msg) then begin WriteLn('FAILED ', Msg); Break; end;
    if M.Time >= next then
    begin
      mx := -1e9; mn := 1e9;
      for i := 0 to (P.Ny + 1) * P.Nx - 1 do begin mx := Max(mx, M.H.DataPtr[i]); mn := Min(mn, M.H.DataPtr[i]); end;
      WriteLn(Format('t %5.1f  min %.4f max %.4f  steps %d rej %d  dt %.4f  facts %d  wall %.1f s',
        [M.Time, mn, mx, M.Steps, M.Rejected, M.Dt, M.Factorisations, GetTickCount64 / 1000 - t0]));
      next := next + 10;
    end;
  end;
  WriteLn(Format('solve %.2f applyL %.2f modes %.2f', [M.SolveTime, M.ApplyLTime, M.ModesTime]));
  WriteLn(Format('threaded=%s: RHS calls %d, RHS wall %.2f s, x half %.2f s, y half %.2f s',
    [BoolToStr(Threaded, True), M.RHSCalls, M.RHSTime, M.XTime, M.YTime]));
  M.Free;
end;

{ 3. the excitation on a flat film: a = 0.005 hN (1 um), T = 1 s,
  run to t = 3 s. Along the centre line between x = 20 and 200 mm the
  wave should be ~a high (times the slow linear growth along the way)
  with wavelength c T. }
procedure Forced;
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  Msg: string;
  i, j0, nUp: Integer;
  x, xc, v, vprev, mx, mn, k, lam, xUp0, xUpLast: Double;
begin
  P := DefaultBenney2DParams;
  P.Excite := True;
  P.ExciteAmp := 0.005;
  P.ExcitePeriod := 1.0;
  M := TBenney2DModel.Create(P);
  M.Start(M.Flat, 1e-3);
  while M.Time < 3.0 - 1e-9 do
    if not M.Advance(Msg) then begin WriteLn('FAILED ', Msg); Exit; end;
  j0 := CentreRow(P);
  mx := -1; mn := 1; nUp := 0; vprev := 0; xUp0 := 0; xUpLast := 0;
  for i := 0 to P.Nx - 1 do
  begin
    x := M.X.DataPtr[i];
    v := M.H.DataPtr[j0 * P.Nx + i] - 1;
    if (x >= 20) and (x <= 200) then
    begin
      mx := Max(mx, v); mn := Min(mn, v);
      if (vprev < 0) and (v >= 0) then
      begin
        // the crossing, interpolated between the two grid points
        xc := x - (P.Lx / P.Nx) * v / (v - vprev);
        if nUp = 0 then xUp0 := xc;
        xUpLast := xc;
        Inc(nUp);
      end;
    end;
    vprev := v;
  end;
  lam := M.WaveSpeed * P.ExcitePeriod;
  k := 2 * Pi / lam;
  WriteLn(Format('excitation: a = %.4f, wavelength c T = %.1f mm, linear growth there %.4f /s',
    [P.ExciteAmp, lam, M.GrowthAt(k)]));
  WriteLn(Format('  centre line x 20..200 mm at t = 3 s: half peak-to-peak %.4f; mean up-crossing spacing %.1f mm (%d crossings)',
    [(mx - mn) / 2, (xUpLast - xUp0) / Max(1, nUp - 1), nUp]));
  WriteLn(Format('  steps %d, rejected %d', [M.Steps, M.Rejected]));
  M.Free;
end;

{ 4. the absorbing zone: the forced train of check 3 run to t = 15 s
  with and without it. Without, the train laps the periodic domain and
  builds up; with, the centre line upstream of the zone (x 20..180)
  should stay near a and very little should get past it (x 286..292, between the zone and
  the source). }
procedure Absorbing(Absorb: Boolean);
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  Msg: string;
  i, j0: Integer;
  x, v, up, dn: Double;
begin
  P := DefaultBenney2DParams;
  P.Excite := True;
  P.ExciteAmp := 0.005;
  P.ExcitePeriod := 1.0;
  P.Absorb := Absorb;
  M := TBenney2DModel.Create(P);
  M.Start(M.Flat, 1e-3);
  while M.Time < 15.0 - 1e-9 do
    if not M.Advance(Msg) then begin WriteLn('FAILED ', Msg); Exit; end;
  j0 := CentreRow(P);
  up := 0; dn := 0;
  for i := 0 to P.Nx - 1 do
  begin
    x := M.X.DataPtr[i];
    v := Abs(M.H.DataPtr[j0 * P.Nx + i] - 1);
    if (x >= 20) and (x <= 180) then up := Max(up, v);
    if (x >= 286) and (x <= 292) then dn := Max(dn, v);
  end;
  if Absorb then
    WriteLn(Format('absorbing zone x %.0f..%.0f mm, rate %.0f /s: a linear wave keeps %.2f %%',
      [M.AbsorbStart, M.AbsorbStart + P.AbsorbLength, P.AbsorbRate, 100 * (1 - M.AbsorbedFraction)]));
  WriteLn(Format('  absorb=%s, t = 15 s: max |H - 1| x 20..180: %.5f; x 286..292: %.5f; steps %d, rejected %d',
    [BoolToStr(Absorb, True), up, dn, M.Steps, M.Rejected]));
  M.Free;
end;

{ 5. the transverse modulation: m = 0.2, n = 2 on the check-3 source,
  t = 3 s. cos(2 pi (y + W/2)/W) is +1 at the walls and -1 on the centre
  line, so the wave between x = 20 and 200 mm should be (1 + m) a high at
  the wall and (1 - m) a on the centre line, ratio 1.5. }
procedure Modulated;
var
  P: TBenney2DParams;
  M: TBenney2DModel;
  Msg: string;
  i: Integer;
  x, aw, ac: Double;
begin
  P := DefaultBenney2DParams;
  P.Excite := True;
  P.ExciteAmp := 0.005;
  P.ExcitePeriod := 1.0;
  P.ExciteMod := 0.2;
  P.ExciteModN := 2;
  M := TBenney2DModel.Create(P);
  M.Start(M.Flat, 1e-3);
  while M.Time < 3.0 - 1e-9 do
    if not M.Advance(Msg) then begin WriteLn('FAILED ', Msg); Exit; end;
  aw := 0; ac := 0;
  for i := 0 to P.Nx - 1 do
  begin
    x := M.X.DataPtr[i];
    if (x >= 20) and (x <= 200) then
    begin
      aw := Max(aw, Abs(M.H.DataPtr[i] - 1));                              // row 0: y = +W/2
      ac := Max(ac, Abs(M.H.DataPtr[CentreRow(P) * P.Nx + i] - 1));      // y = 0
    end;
  end;
  WriteLn(Format('modulation m = 0.2, n = 2: wall %.5f (expect ~%.4f), centre %.5f (~%.4f), ratio %.3f (expect 1.5)',
    [aw, 1.2 * P.ExciteAmp, ac, 0.8 * P.ExciteAmp, aw / ac]));
  M.Free;
end;

begin
  InitializeCBLAS;
  Modulated;
  Absorbing(False);
  Absorbing(True);
  Forced;
  WriteLn('theory (prototype): 3.7024 /s');
  Linear(True);
  BumpRun(False, 20);
  BumpRun(True, 20);
end.
