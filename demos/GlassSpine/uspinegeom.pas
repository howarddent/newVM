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

unit uSpineGeom;

{*******************************************************************************

  The spinal dural sac from S2 to T1 as a voxel grid, for GlassSpine.

  BODY FRAME (mm): x to the patient's left, y anterior, z cranial. The sac
  runs along z from z = 0 (the bottom of S2, where the dural sac ends) to
  the top of T1, where it is closed (the real subarachnoid space goes on
  to the cisterns; closing it there is a modelling choice).

  The centreline lies in the sagittal (y-z) plane and follows the supine
  curves of the spine: the lumbar lordosis is highest at L3, the thoracic
  kyphosis lowest at T8 (the MRI finding of Hirabayashi et al., Br J
  Anaesth 1995, which replaced the older teaching of T4). LevelY is the
  centreline's anterior offset at each level's midpoint, about 34 mm from
  L3 down to T8; the amplitude is an estimate, and Curvature scales it.
  Cross-sections are ellipses (LevelAX transverse, LevelAY antero-posterior
  half-widths), lumbar 17 x 15 mm, thoracic 14 x 13 mm, with rounded
  ends. The spinal cord is an elliptical solid from T1 down to the conus,
  which tapers to its tip at the L1-L2 disc. Below the conus the lumbar
  sac can be flagged as cauda equina (a Darcy drag in the solver).

  Segment lengths (vertebra plus disc) are adult averages, about 54 cm
  from S2 to T1. All of these are typical values chosen for the demo, not
  from one reference.

  Two sacs are built side by side along x in one grid (sac 0 at negative
  x, sac 1 at positive x), so two solutions can be run at once in one set
  of kernels. They share nothing: at least four solid cells lie between
  them.

  FLAGS (one byte per cell):
    FlagFluid  CSF space - the cells the solver updates
    FlagCord   spinal cord (solid, but inside the dura, for display)
    FlagSac1   the cell belongs to sac 1 (else sac 0)
    FlagRoots  cauda equina region (below the conus)
    FlagRing   within half a cell of a level boundary (display)
    FlagKey    a boundary of T4, T10 or L1 (display, drawn stronger)

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

const
  NLevels = 19;
  LevelNames: array[0..NLevels - 1] of string = ('S2', 'S1', 'L5', 'L4', 'L3',
    'L2', 'L1', 'T12', 'T11', 'T10', 'T9', 'T8', 'T7', 'T6', 'T5', 'T4', 'T3',
    'T2', 'T1');
  // segment length, vertebra plus disc (mm)
  LevelLen: array[0..NLevels - 1] of Single = (25, 25, 38, 38, 37, 36, 35,
    32, 30, 28, 27, 26, 25, 25, 24, 24, 23, 23, 23);
  // centreline anterior offset at the level's midpoint, supine (mm)
  LevelY: array[0..NLevels - 1] of Single = (-12, -2, 8, 15, 18, 16, 10, 3,
    -4, -10, -14, -16, -15.5, -14, -12, -9, -6, -3, 0);
  // dural sac half-widths: transverse (x) and antero-posterior (y), mm
  LevelAX: array[0..NLevels - 1] of Single = (6, 7.5, 8.5, 8.5, 8.5, 8.5,
    8.5, 8, 7.5, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7);
  LevelAY: array[0..NLevels - 1] of Single = (5, 6.5, 7.5, 7.5, 7.5, 7.5,
    7.5, 7, 6.8, 6.5, 6.5, 6.5, 6.5, 6.5, 6.5, 6.5, 6.5, 6.5, 6.5);
  // the cord: half-widths in the thoracic region and at the lumbar
  // enlargement (T11, T12); the conus runs through L1
  CordAX = 4.5;
  CordAY = 3.5;
  CordEnlargeAX = 5.0;
  CordEnlargeAY = 4.0;
  EndCap = 12.0;          // rounded ends of the sac, mm

  IdxL1 = 6;
  IdxT12 = 7;
  IdxT11 = 8;

  FlagFluid = 1;
  FlagCord = 2;
  FlagSac1 = 4;
  FlagRoots = 8;
  FlagRing = 16;
  FlagKey = 32;

  // the three usual interspaces; the value is the level above the needle
  // (the interspace is that level's caudal boundary)
  Interspaces: array[0..2] of string = ('L2-L3', 'L3-L4', 'L4-L5');
  InterspaceUpper: array[0..2] of Integer = (5, 4, 3);

type
  TSpineGeom = class
  public
    Dx: Single;              // cell size, mm
    Curvature: Single;       // scale on LevelY, 1 = as tabulated
    NX, NY, NZ: Integer;
    X0, Y0, Z0: Single;      // body coordinates of cell (0,0,0)'s centre
    SacX: array[0..1] of Single;   // body x of each sac's centreline
    LevelZ0: array[0..NLevels] of Single;  // caudal boundary of each level; [NLevels] = top
    Flags: array of Byte;
    Fluid: array of LongInt;        // indices of the fluid cells, ascending
    LevelOfK: array of SmallInt;    // the level each z layer lies in (-1 outside)
    FluidCount: array[0..1] of Integer;
    constructor Create(ADx, ACurvature: Single);
    function Index(i, j, k: Integer): Integer; inline;
    function CenterY(z: Single): Single;
    function HalfX(z: Single): Single;
    function HalfY(z: Single): Single;
    function Length: Single;
    // the needle's injection point (body mm) for an interspace, sac s:
    // midline, Depth mm inside the posterior dura
    procedure InjectionPoint(Inter, s: Integer; Depth: Single; out x, y, z: Single);
    // cell coordinates (fractional) of a body point
    procedure ToCell(x, y, z: Single; out ci, cj, ck: Single);
    // the level a body z lies in, as a fraction: 0 = bottom of S2,
    // NLevels = top of T1
    function LevelCoord(z: Single): Single;
    function CellVolume: Single;
  end;

implementation

{ smooth interpolation of a per-level table at body z: Catmull-Rom through
  the level midpoints, held flat beyond the end midpoints }
function Interp(const Tab: array of Single; Scale: Single; const Mid: array of Single;
  z: Single): Single;
var
  n, i: Integer;
  t, p0, p1, p2, p3: Single;
begin
  n := System.Length(Tab);
  if z <= Mid[0] then Exit(Tab[0] * Scale);
  if z >= Mid[n - 1] then Exit(Tab[n - 1] * Scale);
  i := 0;
  while (i < n - 2) and (z > Mid[i + 1]) do Inc(i);
  t := (z - Mid[i]) / (Mid[i + 1] - Mid[i]);
  p1 := Tab[i];
  p2 := Tab[i + 1];
  if i > 0 then p0 := Tab[i - 1] else p0 := 2 * p1 - p2;
  if i + 2 < n then p3 := Tab[i + 2] else p3 := 2 * p2 - p1;
  Result := Scale * 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
    + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
end;

var
  Mids: array[0..NLevels - 1] of Single;

constructor TSpineGeom.Create(ADx, ACurvature: Single);
var
  i, j, k, s, id, L, nf: Integer;
  x, y, z, yc, ax, ay, cap, tz, cx, cy, ex, ey, xmax, ymin, ymax: Single;
  ring: Byte;
  inSac, inCord: Boolean;
  f: Byte;
begin
  inherited Create;
  Dx := ADx;
  Curvature := ACurvature;
  LevelZ0[0] := 0;
  for i := 0 to NLevels - 1 do
  begin
    LevelZ0[i + 1] := LevelZ0[i] + LevelLen[i];
    Mids[i] := LevelZ0[i] + 0.5 * LevelLen[i];
  end;

  // the bounding box of one sac
  xmax := 0;
  ymin := 1e9;
  ymax := -1e9;
  z := 0;
  while z <= Length do
  begin
    xmax := Max(xmax, HalfX(z));
    ymin := Min(ymin, CenterY(z) - HalfY(z));
    ymax := Max(ymax, CenterY(z) + HalfY(z));
    z := z + 0.5;
  end;
  // two sacs, each with two solid cells of margin round it
  NX := 2 * (Ceil(2 * xmax / Dx) + 5);
  NY := Ceil((ymax - ymin) / Dx) + 5;
  NZ := Ceil(Length / Dx) + 5;
  X0 := -(NX - 1) * Dx / 2;
  Y0 := 0.5 * (ymin + ymax) - (NY - 1) * Dx / 2;
  Z0 := 0.5 * Length - (NZ - 1) * Dx / 2;
  SacX[0] := -(NX * Dx) / 4;
  SacX[1] := (NX * Dx) / 4;

  SetLength(Flags, NX * NY * NZ);
  SetLength(LevelOfK, NZ);
  nf := 0;
  FluidCount[0] := 0;
  FluidCount[1] := 0;
  for k := 0 to NZ - 1 do
  begin
    z := Z0 + k * Dx;
    LevelOfK[k] := -1;
    if (z >= 0) and (z < Length) then
    begin
      L := 0;
      while (L < NLevels - 1) and (z >= LevelZ0[L + 1]) do Inc(L);
      LevelOfK[k] := L;
    end;
    yc := CenterY(z);
    ax := HalfX(z);
    ay := HalfY(z);
    // rounded ends: the section shrinks as a quarter ellipse over EndCap
    cap := 1;
    if z < EndCap then
    begin
      tz := (EndCap - z) / EndCap;
      if tz >= 1 then cap := 0 else cap := Sqrt(1 - tz * tz);
    end
    else if z > Length - EndCap then
    begin
      tz := (z - (Length - EndCap)) / EndCap;
      if tz >= 1 then cap := 0 else cap := Sqrt(1 - tz * tz);
    end;
    // the cord's section at this z (zero below the conus tip)
    if z >= LevelZ0[IdxT12 + 1] then
    begin
      cx := CordAX;
      cy := CordAY;
      if z < LevelZ0[IdxT11 + 1] then
      begin
        cx := CordEnlargeAX;
        cy := CordEnlargeAY;
      end;
    end
    else if z >= LevelZ0[IdxL1] then
    begin
      // conus: tapers through L1 from the enlargement to a point
      tz := (z - LevelZ0[IdxL1]) / LevelLen[IdxL1];
      cx := CordEnlargeAX * Sqrt(tz);
      cy := CordEnlargeAY * Sqrt(tz);
    end
    else
    begin
      cx := 0;
      cy := 0;
    end;
    if z > Length - EndCap then
    begin
      cx := cx * cap;
      cy := cy * cap;
    end;
    // level-boundary rings for the display
    f := 0;
    for L := 1 to NLevels - 1 do
      if Abs(z - LevelZ0[L]) <= 0.5 * Dx then
      begin
        f := FlagRing;
        // T4's and T10's caudal boundaries, and L1's caudal boundary
        if (L = 15) or (L = 9) or (L = IdxL1) then f := f or FlagKey;
      end;
    ring := f;
    for j := 0 to NY - 1 do
    begin
      y := Y0 + j * Dx;
      for s := 0 to 1 do
        for i := s * (NX div 2) to s * (NX div 2) + NX div 2 - 1 do
        begin
          x := X0 + i * Dx - SacX[s];
          id := Index(i, j, k);
          inSac := False;
          if (cap > 0) and (z > 0) and (z < Length) then
          begin
            ex := x / (ax * cap);
            ey := (y - yc) / (ay * cap);
            inSac := ex * ex + ey * ey < 1;
          end;
          if not inSac then
          begin
            Flags[id] := 0;
            Continue;
          end;
          inCord := False;
          if (cx > 0) and (cy > 0) then
          begin
            ex := x / cx;
            ey := (y - yc) / cy;
            inCord := ex * ex + ey * ey < 1;
          end;
          f := ring;
          if s = 1 then f := f or FlagSac1;
          if inCord then
            f := f or FlagCord
          else
          begin
            f := f or FlagFluid;
            // the cauda equina fills the sac below the conus tip
            if z < LevelZ0[IdxL1] then f := f or FlagRoots;
            Inc(nf);
            Inc(FluidCount[s]);
          end;
          Flags[id] := f;
        end;
    end;
  end;
  SetLength(Fluid, nf);
  nf := 0;
  for id := 0 to High(Flags) do
    if Flags[id] and FlagFluid <> 0 then
    begin
      Fluid[nf] := id;
      Inc(nf);
    end;
end;

function TSpineGeom.Index(i, j, k: Integer): Integer;
begin
  Result := i + NX * (j + NY * k);
end;

function TSpineGeom.CenterY(z: Single): Single;
begin
  Result := Interp(LevelY, Curvature, Mids, z);
end;

function TSpineGeom.HalfX(z: Single): Single;
begin
  Result := Interp(LevelAX, 1, Mids, z);
end;

function TSpineGeom.HalfY(z: Single): Single;
begin
  Result := Interp(LevelAY, 1, Mids, z);
end;

function TSpineGeom.Length: Single;
begin
  Result := LevelZ0[NLevels];
end;

procedure TSpineGeom.InjectionPoint(Inter, s: Integer; Depth: Single; out x, y, z: Single);
begin
  z := LevelZ0[InterspaceUpper[Inter]];
  x := SacX[s];
  y := CenterY(z) - HalfY(z) + Depth;
end;

procedure TSpineGeom.ToCell(x, y, z: Single; out ci, cj, ck: Single);
begin
  ci := (x - X0) / Dx;
  cj := (y - Y0) / Dx;
  ck := (z - Z0) / Dx;
end;

function TSpineGeom.LevelCoord(z: Single): Single;
var
  L: Integer;
begin
  if z <= 0 then Exit(0);
  if z >= Length then Exit(NLevels);
  L := 0;
  while (L < NLevels - 1) and (z >= LevelZ0[L + 1]) do Inc(L);
  Result := L + (z - LevelZ0[L]) / LevelLen[L];
end;

function TSpineGeom.CellVolume: Single;
begin
  Result := Dx * Dx * Dx;
end;

end.
