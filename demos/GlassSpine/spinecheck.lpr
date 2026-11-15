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

program spinecheck;

{*******************************************************************************

  Headless checks of GlassSpine's solver (no OpenGL):
    - the geometry: grid, CSF volume per sac;
    - a sac with nothing injected stays at rest;
    - CSF pulsation alone: the axial flux at several levels against the
      prescribed one, and the divergence left over;
    - an injection in a given posture: spread, injectate accounted for,
      peak speed, and how fast the GPU runs it.

  Build:  fpc -O2 -Fu../.. -Fi../.. spinecheck.lpr
  Run:    ./spinecheck [--time=60] [--tilt=0] [--roll=0] [--dx=1.25]
                       [--level=1] [--iters=30] [--pulse=1] [--cardiac=0.3]
                       [--hr=70] [--resp=0.3] [--rr=12]

*******************************************************************************}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, DateUtils, uSpineGeom, uGlassSpineSim;

function Opt(const Name: string; Def: Double): Double;
var
  i: Integer;
  p: string;
begin
  Result := Def;
  p := '--' + Name + '=';
  for i := 1 to ParamCount do
    if Copy(ParamStr(i), 1, Length(p)) = p then
      Result := StrToFloat(Copy(ParamStr(i), Length(p) + 1, 99));
end;

const
  CheckLevels: array[0..3] of Integer = (4, 6, 11, 17);   // L3, L1, T8, T2 (mid-level)

var
  Sim: TSpineSim;
  T, tEnd, tNext: Double;
  s, L, i, k: Integer;
  qa, qp: Double;
  qa_s: Single;
  t0: TDateTime;
  wall: Double;
begin
  Sim := TSpineSim.Create(ExtractFilePath(ParamStr(0)) + 'glassspine.cl');
  try
    Sim.Interspace := Round(Opt('level', 1));
    Sim.PressureIters := Round(Opt('iters', 30));
    Sim.JetDir := Round(Opt('jet', 1));
    Sim.CFL := Opt('cfl', 0.3);
    Sim.Dt := Opt('dt', 0.01);
    Sim.Baricity[0] := Opt('b0', 1.02);
    Sim.Baricity[1] := Opt('b1', 0.999);
    Sim.CardiacML := Opt('cardiac', 0.3);
    Sim.HeartRate := Opt('hr', 70);
    Sim.RespML := Opt('resp', 0.3);
    Sim.RespRate := Opt('rr', 12);
    Sim.Setup(Opt('dx', 1.25), 1);
    with Sim.Geom do
    begin
      WriteLn(Format('device %s', [Sim.DeviceName]));
      WriteLn(Format('grid %d x %d x %d (%.2f mm), %d fluid cells, %.1f mL CSF per sac, sac %.0f mm long',
        [NX, NY, NZ, Dx, System.Length(Fluid), FluidCount[0] * CellVolume / 1000, Length]));
    end;

    // at rest: nothing injected, a second in the lateral position
    Sim.Pulse := False;
    Sim.RollDeg := 90;
    Sim.Advance(1.0);
    WriteLn(Format('at rest, 1 s lateral: max speed %.3g mm/s', [Sim.MaxSpeed]));

    // pulsation alone, supine: computed against prescribed axial flux
    Sim.Reset;
    Sim.RollDeg := 0;
    Sim.Pulse := True;
    WriteLn(Format('fluid cells joined only by an edge or corner: %d', [Sim.Isolated]));
    WriteLn(Format('pulsation: %.2f mL a beat at %.0f /min, %.2f mL a breath at %.0f /min',
      [Sim.CardiacML, Sim.HeartRate, Sim.RespML, Sim.RespRate]));
    for i := 1 to 6 do
    begin
      Sim.Advance(0.37);
      Write(Format('  t %4.2f s  q %7.0f mm^3/s  |div| dx/max|u| %.1e |', [Sim.Time,
        Sim.PulseFlow(Sim.Time), Sim.MaxDivergence / Max(1e-6, Sim.MaxSpeed), Sim.MaxSpeed]));
      for L in CheckLevels do
      begin
        k := Round((0.5 * (Sim.Geom.LevelZ0[L] + Sim.Geom.LevelZ0[L + 1]) - Sim.Geom.Z0) / Sim.Geom.Dx);
        qa := Sim.AxialFlux(0, k);
        qp := Sim.PrescribedAxialFlux(0, k);
        Write(Format(' %s %6.0f/%6.0f', [LevelNames[L], qa, qp]));
      end;
      WriteLn(Format('  max |u| %.1f mm/s', [Sim.MaxSpeed]));
      Sim.MaxDivergenceAt(k, qa_s);
      WriteLn(Format('    worst residual at k %d of %d, rms %.3g mm/s', [k, Sim.Geom.NZ, qa_s]));
    end;

    Sim.Reset;
    Sim.Pulse := Opt('pulse', 1) <> 0;
    Sim.TiltDeg := Opt('tilt', 0);
    Sim.RollDeg := Opt('roll', 0);
    WriteLn(Format('injecting %.1f mL over %.0f s at %s, tilt %.0f, roll %.0f, baricity %.4f / %.4f',
      [Sim.DoseML, Sim.DurationS, Interspaces[Sim.Interspace], Sim.TiltDeg, Sim.RollDeg,
       Sim.Baricity[0], Sim.Baricity[1]]));
    Sim.StartInjection;
    tEnd := Opt('time', 60);
    tNext := 5;
    t0 := Now;
    T := 0;
    while T < tEnd - 0.5 * Sim.Dt do
    begin
      Sim.Advance(Min(0.1, tEnd - T));
      Sim.ReadBack;
      T := Sim.Time;
      if T >= tNext - 1e-6 then
      begin
        wall := MilliSecondsBetween(Now, t0) / 1000;
        Write(Format('t %5.1f s  wall %5.1f s', [T, wall]));
        for s := 0 to 1 do
          Write(Format(' | sac %d: in %.2f mL, present %.2f mL, %s..%s',
            [s, Sim.Injected[s] / 1000, Sim.Present[s] / 1000,
             LevelText(Sim.CaudalExtent(s, 0.01)), LevelText(Sim.CephaladExtent(s, 0.01))]));
        WriteLn(Format(' | max |u| %.1f mm/s, %d sub, C %.1e..%.4f', [Sim.LastMaxSpeed, Sim.LastSubsteps, Sim.CMin, Sim.CMax]));
        tNext := tNext + Opt('every', 5);
      end;
    end;
    WriteLn('injectate per level (mL), sac 0 / sac 1, and peak C:');
    for L := NLevels - 1 downto 0 do
      WriteLn(Format('  %-4s %6.3f %6.3f   %5.3f %5.3f', [LevelNames[L], Sim.Profile[0, L],
        Sim.Profile[1, L], Sim.LevelMax[0, L], Sim.LevelMax[1, L]]));
  finally
    Sim.Free;
  end;
end.
