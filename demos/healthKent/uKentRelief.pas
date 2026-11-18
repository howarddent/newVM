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

unit uKentRelief;

{*******************************************************************************

     The healthKent demo's physical map data: OS Terrain 50 heights on a
     100 m grid over Kent and Medway's box, and OpenStreetMap rivers and
     canals, both compiled in (physicaldata.inc, from make_physical_data.py).

     ReliefImage colours the grid as a shaded-relief picture: a height tint
     (ReliefTint, green lowland through yellow to brown on the Downs'
     tops) times a hillshade lit from the north-west at 45 deg, with the
     heights exaggerated (ReliefExaggeration), since Kent's slopes are
     gentle. A flat cell keeps its tint exactly. Row 0 is the south edge,
     as glTexImage2D wants it.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Math, Graphics;

{$I physicaldata.inc}

const
  RiverMain = 0;            // RiverKind: the main rivers, drawn heavier
  RiverMinor = 1;
  ReliefExaggeration = 5.0;
  ReliefTop = 250.0;        // m, the top of the tint scale

type
  TReliefPixels = array of Byte;   // RGB, ReliefCols x ReliefRows, south row first

// height in metres at (E, N), bilinear; NaN outside the grid
function ReliefHeight(E, N: Double): Double;
function ReliefTint(H: Double): TColor;     // the height tint alone, for the legend
procedure ReliefImage(out Pix: TReliefPixels);
// the highest grid cell (its centre) and its height
procedure ReliefHighest(out E, N, H: Double);

implementation

type
  TRGB = record h: Double; r, g, b: Byte; end;

const
  TintStops: array[0..6] of TRGB = (
    (h: 0;   r: 160; g: 204; b: 156), (h: 25;  r: 190; g: 218; b: 168),
    (h: 50;  r: 220; g: 229; b: 178), (h: 100; r: 240; g: 228; b: 168),
    (h: 150; r: 224; g: 200; b: 146), (h: 200; r: 204; g: 170; b: 124),
    (h: 250; r: 182; g: 142; b: 106));

function Cell(i, j: Integer): Double; inline;      // metres; i column, j row
begin
  i := EnsureRange(i, 0, ReliefCols - 1);
  j := EnsureRange(j, 0, ReliefRows - 1);
  result := ReliefDm[j * ReliefCols + i] / 10;
end;

function ReliefHeight(E, N: Double): Double;
var
  x, y, fx, fy: Double;
  i, j: Integer;
begin
  x := (E - ReliefE0) / ReliefCell - 0.5;           // cell centres at half cells
  y := (N - ReliefN0) / ReliefCell - 0.5;
  if (x < -0.5) or (y < -0.5) or (x > ReliefCols - 0.5) or (y > ReliefRows - 0.5) then Exit(NaN);
  i := Floor(x); j := Floor(y);
  fx := x - i; fy := y - j;
  result := (1 - fy) * ((1 - fx) * Cell(i, j) + fx * Cell(i + 1, j))
          + fy * ((1 - fx) * Cell(i, j + 1) + fx * Cell(i + 1, j + 1));
end;

procedure TintRGB(H: Double; out r, g, b: Double);
var
  k: Integer;
  f: Double;
begin
  H := EnsureRange(H, 0, ReliefTop);
  k := 0;
  while (k < High(TintStops) - 1) and (H > TintStops[k + 1].h) do Inc(k);
  f := (H - TintStops[k].h) / (TintStops[k + 1].h - TintStops[k].h);
  r := TintStops[k].r + f * (TintStops[k + 1].r - TintStops[k].r);
  g := TintStops[k].g + f * (TintStops[k + 1].g - TintStops[k].g);
  b := TintStops[k].b + f * (TintStops[k + 1].b - TintStops[k].b);
end;

function ReliefTint(H: Double): TColor;
var
  r, g, b: Double;
begin
  TintRGB(H, r, g, b);
  result := RGBToColor(Round(r), Round(g), Round(b));
end;

procedure ReliefImage(out Pix: TReliefPixels);
const
  Alt = Pi / 4;                                     // the light: 45 deg up,
  LX = -0.5;                                        // from the north-west
  LY = 0.5;                                         // (cos 45 x sin/cos 315)
  LZ = 0.70710678;
var
  i, j, k: Integer;
  dzx, dzy, nx, ny, nz, s, f, r, g, b: Double;
begin
  SetLength(Pix, 3 * ReliefCols * ReliefRows);
  for j := 0 to ReliefRows - 1 do
    for i := 0 to ReliefCols - 1 do begin
      dzx := ReliefExaggeration * (Cell(i + 1, j) - Cell(i - 1, j)) / (2 * ReliefCell);
      dzy := ReliefExaggeration * (Cell(i, j + 1) - Cell(i, j - 1)) / (2 * ReliefCell);
      s := 1 / Sqrt(1 + dzx * dzx + dzy * dzy);
      nx := -dzx * s; ny := -dzy * s; nz := s;
      f := (nx * LX + ny * LY + nz * LZ) / Sin(Alt);  // 1 on the flat
      f := EnsureRange(1 + 0.9 * (f - 1), 0.45, 1.2);
      TintRGB(Cell(i, j), r, g, b);
      k := 3 * (j * ReliefCols + i);
      Pix[k] := Min(255, Round(r * f));
      Pix[k + 1] := Min(255, Round(g * f));
      Pix[k + 2] := Min(255, Round(b * f));
    end;
end;

procedure ReliefHighest(out E, N, H: Double);
var
  k, best: Integer;
begin
  best := 0;
  for k := 1 to High(ReliefDm) do
    if ReliefDm[k] > ReliefDm[best] then best := k;
  E := ReliefE0 + ReliefCell * (best mod ReliefCols + 0.5);
  N := ReliefN0 + ReliefCell * (best div ReliefCols + 0.5);
  H := ReliefDm[best] / 10;
end;

end.
