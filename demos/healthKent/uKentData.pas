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

unit uKentData;

{*******************************************************************************

     The healthKent demo's data: Kent and Medway (the NHS Kent and Medway
     Integrated Care Board area - Kent County Council's twelve districts
     plus Medway), compiled in from kentdata.inc, which make_kent_data.py
     generates from the government and OpenStreetMap downloads listed in
     Sources below. No network is needed at run time.

       - 1107 LSOAs (2021): boundary rings, mid-2024 population, land area,
         English Indices of Deprivation 2025 (IMD and seven domains: score,
         national rank, national decile), built-up area
       - the 13 districts' coastline-clipped boundaries (the land mask)
       - built-up areas over 50,000 people (mid-2024, summed from LSOAs)
       - motorways, trunk roads, primary A roads and railways (OSM)

     All coordinates are British National Grid (OSGB36) metres.

     POPULATION BARYCENTRE: the population-weighted mean of the LSOA
     label points, sum(p_i x_i) / sum(p_i), computed with newVM: the
     populations as a (1, N) TVMobj times the (N, 2) [E N] matrix,
     divided by the population times a column of ones. With ~1,750 people
     per LSOA the label points stand in well for the people; ONS's own
     population-weighted LSOA centroids aren't on its open service. It is
     the point that minimises the population's summed squared distance -
     the mean, not the median, centre. The geographic centre is the area
     centroid of the districts' land (shoelace formula over every ring).

     BNG -> WGS84: inverse transverse Mercator on Airy 1830 (OS "A guide
     to coordinate systems in Great Britain"), then the 7-parameter
     Helmert OSGB36 -> WGS84 - the inverse of bng.py's transform; a few
     metres.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, newVM;

{$I kentdata.inc}

const
  RouteMotorway = 0;
  RouteTrunk = 1;
  RoutePrimary = 2;
  RouteRail = 3;
  MostDeprivedDecile = 1;
  NationalLsoaCount = 33755;       // LSOAs ranked in IoD 2025

type
  TSourceEntry = record
    Title, Publisher, Edition, Licence, URL, Use: string;
  end;
  TGlossaryEntry = record
    Term, Meaning: string;
  end;

const
  Sources: array[0..7] of TSourceEntry = (
    (Title: 'Lower layer Super Output Area population estimates (small area, 2021-based), mid-2024';
     Publisher: 'Office for National Statistics (via Nomis, dataset NM_2014_1)';
     Edition: 'mid-2024 estimates, released 7 November 2025 - the latest published';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://www.nomisweb.co.uk/datasets/pestsyoala';
     Use: 'Population of every LSOA (all ages, persons); population density, the barycentre and town populations are all built from it.'),
    (Title: 'English Indices of Deprivation 2025 - File 7: all ranks, scores, deciles and population denominators';
     Publisher: 'Ministry of Housing, Communities and Local Government';
     Edition: 'IoD2025, published 2025 (LSOA 2021 geography)';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://www.gov.uk/government/statistics/english-indices-of-deprivation-2025';
     Use: 'Index of Multiple Deprivation and its seven domains for each LSOA: score, rank of 33,755 in England, and national decile (1 = most deprived 10 %).'),
    (Title: 'Lower layer Super Output Areas (December 2021) Boundaries EW BFE (V10)';
     Publisher: 'Office for National Statistics, Open Geography Portal';
     Edition: 'December 2021 boundaries, full resolution, extent of the realm';
     Licence: 'Open Government Licence v3.0; contains OS data (c) Crown copyright and database right';
     URL: 'https://geoportal.statistics.gov.uk (service LSOA_2021_EW_BFE_V10_RUC)';
     Use: 'LSOA outlines (simplified to 12 m) and label points; drawn only inside the district coastline.'),
    (Title: 'Local Authority Districts (December 2024) Boundaries UK BFC';
     Publisher: 'Office for National Statistics, Open Geography Portal';
     Edition: 'December 2024, full resolution, clipped to the coastline';
     Licence: 'Open Government Licence v3.0; contains OS data (c) Crown copyright and database right';
     URL: 'https://geoportal.statistics.gov.uk (service Local_Authority_Districts_December_2024_Boundaries_UK_BFC)';
     Use: 'The 13 district outlines and the land mask (coastline) of the map.'),
    (Title: 'Standard Area Measurements for 2021 Statistical Geographies (V2)';
     Publisher: 'Office for National Statistics';
     Edition: 'March 2021 statistical geographies';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://geoportal.statistics.gov.uk (Standard Area Measurements)';
     Use: 'Land area of each LSOA (excluding tidal and large inland water), the denominator of population density.'),
    (Title: 'LSOA (2021) to Sub ICB Location to ICB to Cancer Alliance to LAD (2025) Lookup in England';
     Publisher: 'Office for National Statistics, Open Geography Portal';
     Edition: '2025';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://geoportal.statistics.gov.uk (service LSOA21_SICBL25_ICB25_CAL25_LAD25_EN_LU)';
     Use: 'Which LSOAs make up the NHS Kent and Medway ICB, and their districts.'),
    (Title: 'LSOA (2021) to Built Up Area (2022) to LAD (2022) Best Fit Lookup in EW (V2)';
     Publisher: 'Office for National Statistics, Open Geography Portal';
     Edition: 'Built-up areas 2022';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://geoportal.statistics.gov.uk (service LSOA21_BUA22_LAD22_RGN22_EW_LU_v2)';
     Use: 'Towns: each built-up area''s mid-2024 population is the sum of its LSOAs, its position their population-weighted mean.'),
    (Title: 'OpenStreetMap - highway=motorway/trunk/primary, railway=rail (no service track)';
     Publisher: 'OpenStreetMap contributors, via the Overpass API';
     Edition: 'snapshot of ' + OsmTimestamp;
     Licence: 'Open Database Licence (ODbL) 1.0 - (c) OpenStreetMap contributors';
     URL: 'https://www.openstreetmap.org/copyright';
     Use: 'Motorways, trunk roads (mostly primary routes), primary A roads and railways, simplified to 20 m.')
  );

  Glossary: array[0..9] of TGlossaryEntry = (
    (Term: 'LSOA'; Meaning: 'Lower layer Super Output Area: a Census 2021 statistical area of about 1,000-3,000 residents (400-1,200 households). Kent and Medway has 1,107.'),
    (Term: 'Mid-year population estimate'; Meaning: 'ONS estimate of the usual resident population on 30 June, rolled forward from the 2021 Census with births, deaths and migration.'),
    (Term: 'Population density'; Meaning: 'Mid-2024 population divided by the LSOA''s land area (ONS Standard Area Measurements), people per km2.'),
    (Term: 'IMD'; Meaning: 'Index of Multiple Deprivation 2025: a weighted combination of seven domains - income 22.5 %, employment 22.5 %, education 13.5 %, health 13.5 %, crime 9.3 %, barriers to housing and services 9.3 %, living environment 9.3 %.'),
    (Term: 'Decile'; Meaning: 'National tenth of the 33,755 LSOAs in England ranked by score: decile 1 is the most deprived 10 %, decile 10 the least deprived. Deciles are relative - decile 10 is the least deprived, not necessarily wealthy.'),
    (Term: 'Built-up area (BUA)'; Meaning: 'ONS 2022 definition of a town or city from land use (built-up land at 25 m resolution); Medway''s towns are separate BUAs (Gillingham, Chatham, Rochester).'),
    (Term: 'Population barycentre'; Meaning: 'Population-weighted mean position of the residents - where a rigid map with each person as an equal weight would balance. It minimises the summed squared distance to everyone.'),
    (Term: 'Geographic centre'; Meaning: 'Area centroid of the land: where the map would balance if every square kilometre weighed the same.'),
    (Term: 'British National Grid'; Meaning: 'The OS transverse Mercator grid (OSGB36): eastings and northings in metres; a grid reference such as TQ 87979 58078 names the 100 km square and the position inside it.'),
    (Term: 'ICB'; Meaning: 'Integrated Care Board: the NHS body planning health services for an area - here NHS Kent and Medway, covering the 12 Kent districts and Medway.')
  );

// density, people per km2
function LsoaDensity(i: Integer): Double;
function LsoaScoreOf(i, Domain: Integer): Double;
function LsoaRankOf(i, Domain: Integer): Integer;
function LsoaDecileOf(i, Domain: Integer): Integer;
// LSOA containing the point, or -1
function LsoaAt(E, N: Double): Integer;
// LSOA whose label point is nearest
function NearestLsoa(E, N: Double): Integer;
function NearestTown(E, N: Double; out DistKm: Double): Integer;
function LsoaBoxE0(i: Integer): Single;
function LsoaBoxE1(i: Integer): Single;
function LsoaBoxN0(i: Integer): Single;
function LsoaBoxN1(i: Integer): Single;

function TotalPopulation: Int64;
function TotalLandKm2: Double;
// population-weighted mean of the label points (newVM), over the LSOAs
// with Include[i] (all when Include is empty)
procedure PopulationBarycentre(const Include: array of Boolean; out E, N: Double);
procedure GeographicCentre(out E, N: Double);

procedure BNGToWGS84(E, N: Double; out Lat, Lon: Double);
function GridRef(E, N: Double): string;               // 'TQ 87979 58078'
function LatLonText(Lat, Lon: Double): string;        // '51.297N 0.678E'

implementation

var
  BoxE0, BoxE1, BoxN0, BoxN1: array[0..LsoaCount - 1] of Single;

function LsoaDensity(i: Integer): Double;
begin
  if LsoaLandKm2[i] > 0 then result := LsoaPop[i] / LsoaLandKm2[i]
  else result := NaN;
end;

function LsoaScoreOf(i, Domain: Integer): Double;
begin
  result := LsoaScore[i * DomainCount + Domain];
end;

function LsoaRankOf(i, Domain: Integer): Integer;
begin
  result := LsoaRank[i * DomainCount + Domain];
end;

function LsoaDecileOf(i, Domain: Integer): Integer;
begin
  result := LsoaDecile[i * DomainCount + Domain];
end;

function LsoaBoxE0(i: Integer): Single; begin result := BoxE0[i]; end;
function LsoaBoxE1(i: Integer): Single; begin result := BoxE1[i]; end;
function LsoaBoxN0(i: Integer): Single; begin result := BoxN0[i]; end;
function LsoaBoxN1(i: Integer): Single; begin result := BoxN1[i]; end;

procedure ComputeBoxes;
var
  i, k: Integer;
begin
  for i := 0 to LsoaCount - 1 do begin
    k := LsoaRingStart[LsoaRingFirst[i]];
    BoxE0[i] := LsoaPtE[k]; BoxE1[i] := LsoaPtE[k];
    BoxN0[i] := LsoaPtN[k]; BoxN1[i] := LsoaPtN[k];
    for k := LsoaRingStart[LsoaRingFirst[i]] to LsoaRingStart[LsoaRingFirst[i + 1]] - 1 do begin
      BoxE0[i] := Min(BoxE0[i], LsoaPtE[k]); BoxE1[i] := Max(BoxE1[i], LsoaPtE[k]);
      BoxN0[i] := Min(BoxN0[i], LsoaPtN[k]); BoxN1[i] := Max(BoxN1[i], LsoaPtN[k]);
    end;
  end;
end;

function LsoaAt(E, N: Double): Integer;
var
  i, r, k, k0, k1, j: Integer;
  c: Boolean;
begin
  for i := 0 to LsoaCount - 1 do begin
    if (E < BoxE0[i]) or (E > BoxE1[i]) or (N < BoxN0[i]) or (N > BoxN1[i]) then Continue;
    c := False;                                    // even-odd over all its rings
    for r := LsoaRingFirst[i] to LsoaRingFirst[i + 1] - 1 do begin
      k0 := LsoaRingStart[r];
      k1 := LsoaRingStart[r + 1] - 1;
      j := k1;
      for k := k0 to k1 do begin
        if ((LsoaPtN[k] > N) <> (LsoaPtN[j] > N)) and
           (E < LsoaPtE[k] + (N - LsoaPtN[k]) * (LsoaPtE[j] - LsoaPtE[k]) / (LsoaPtN[j] - LsoaPtN[k])) then
          c := not c;
        j := k;
      end;
    end;
    if c then Exit(i);
  end;
  result := -1;
end;

function NearestLsoa(E, N: Double): Integer;
var
  i: Integer;
  d, best: Double;
begin
  result := 0;
  best := Infinity;
  for i := 0 to LsoaCount - 1 do begin
    d := Sqr(LsoaLabelE[i] - E) + Sqr(LsoaLabelN[i] - N);
    if d < best then begin best := d; result := i; end;
  end;
end;

function NearestTown(E, N: Double; out DistKm: Double): Integer;
var
  i: Integer;
  d, best: Double;
begin
  result := 0;
  best := Infinity;
  for i := 0 to TownCount - 1 do begin
    d := Sqr(TownE[i] - E) + Sqr(TownN[i] - N);
    if d < best then begin best := d; result := i; end;
  end;
  DistKm := Sqrt(best) / 1000;
end;

function TotalPopulation: Int64;
var
  i: Integer;
begin
  result := 0;
  for i := 0 to LsoaCount - 1 do result := result + LsoaPop[i];
end;

function TotalLandKm2: Double;
var
  i: Integer;
begin
  result := 0;
  for i := 0 to LsoaCount - 1 do result := result + LsoaLandKm2[i];
end;

procedure PopulationBarycentre(const Include: array of Boolean; out E, N: Double);
var
  W, XY, Ones, Num, Den: TVMobj;
  i: Integer;
begin
  W := TVMobj.Create(1, LsoaCount);
  XY := TVMobj.Create(LsoaCount, 2);
  Ones := TVMobj.Create(LsoaCount, 1);
  for i := 0 to LsoaCount - 1 do begin
    if (Length(Include) = 0) or Include[i] then W[0, i] := LsoaPop[i] else W[0, i] := 0;
    XY[i, 0] := LsoaLabelE[i];
    XY[i, 1] := LsoaLabelN[i];
    Ones[i, 0] := 1;
  end;
  Num := MatMult(W, XY);          // (1, 2): sum p E, sum p N
  Den := MatMult(W, Ones);        // (1, 1): sum p
  if Den[0, 0] > 0 then begin
    E := Num[0, 0] / Den[0, 0];
    N := Num[0, 1] / Den[0, 0];
  end else begin
    E := NaN;
    N := NaN;
  end;
end;

procedure GeographicCentre(out E, N: Double);
var
  r, k, j: Integer;
  Ar, Cxr, Cyr, cr, x0, y0, W, Sx, Sy: Double;
begin
  // area-weighted mean of each land ring's centroid (shoelace, relative to
  // a local origin for precision). The district rings are islands and
  // mainland, with no holes, so every ring counts positive whatever its
  // winding.
  x0 := DistrictPtE[0];
  y0 := DistrictPtN[0];
  W := 0; Sx := 0; Sy := 0;
  for r := 0 to DistrictRingCount - 1 do begin
    Ar := 0; Cxr := 0; Cyr := 0;
    j := DistrictRingStart[r + 1] - 1;
    for k := DistrictRingStart[r] to DistrictRingStart[r + 1] - 1 do begin
      cr := (DistrictPtE[j] - x0) * (DistrictPtN[k] - y0) - (DistrictPtE[k] - x0) * (DistrictPtN[j] - y0);
      Ar := Ar + cr;
      Cxr := Cxr + (DistrictPtE[j] + DistrictPtE[k] - 2 * x0) * cr;
      Cyr := Cyr + (DistrictPtN[j] + DistrictPtN[k] - 2 * y0) * cr;
      j := k;
    end;
    if Ar = 0 then Continue;
    W := W + Abs(Ar) / 2;
    Sx := Sx + Abs(Ar) / 2 * Cxr / (3 * Ar);
    Sy := Sy + Abs(Ar) / 2 * Cyr / (3 * Ar);
  end;
  E := x0 + Sx / W;
  N := y0 + Sy / W;
end;

procedure BNGToWGS84(E, N: Double; out Lat, Lon: Double);
const
  a = 6377563.396; b = 6356256.909; F0 = 0.9996012717;
  N0 = -100000; E0 = 400000;
var
  e2, nn, phi0, lam0, phi, M, dphi, sphi, s, c, t, nu, rho, eta2,
  VII, VIII, IX, Xc, XI, XII, XIIA, dE, lam: Double;
  x, y, z, x2, y2, z2, sc, rx, ry, rz, p, aW, bW, e2W, nuW: Double;
  i: Integer;
begin
  e2 := 1 - (b * b) / (a * a);
  nn := (a - b) / (a + b);
  phi0 := DegToRad(49);
  lam0 := DegToRad(-2);
  phi := phi0;
  M := 0;
  repeat
    phi := (N - N0 - M) / (a * F0) + phi;
    dphi := phi - phi0;
    sphi := phi + phi0;
    M := b * F0 * ((1 + nn + 1.25 * nn * nn + 1.25 * nn * nn * nn) * dphi
       - (3 * nn + 3 * nn * nn + 21 / 8 * nn * nn * nn) * Sin(dphi) * Cos(sphi)
       + (15 / 8 * nn * nn + 15 / 8 * nn * nn * nn) * Sin(2 * dphi) * Cos(2 * sphi)
       - 35 / 24 * nn * nn * nn * Sin(3 * dphi) * Cos(3 * sphi));
  until Abs(N - N0 - M) < 1e-5;
  s := Sin(phi);
  c := Cos(phi);
  t := Tan(phi);
  nu := a * F0 / Sqrt(1 - e2 * s * s);
  rho := a * F0 * (1 - e2) / Power(1 - e2 * s * s, 1.5);
  eta2 := nu / rho - 1;
  VII := t / (2 * rho * nu);
  VIII := t / (24 * rho * nu * nu * nu) * (5 + 3 * t * t + eta2 - 9 * t * t * eta2);
  IX := t / (720 * rho * Power(nu, 5)) * (61 + 90 * t * t + 45 * Power(t, 4));
  Xc := 1 / (c * nu);
  XI := 1 / (c * 6 * nu * nu * nu) * (nu / rho + 2 * t * t);
  XII := 1 / (c * 120 * Power(nu, 5)) * (5 + 28 * t * t + 24 * Power(t, 4));
  XIIA := 1 / (c * 5040 * Power(nu, 7)) * (61 + 662 * t * t + 1320 * Power(t, 4) + 720 * Power(t, 6));
  dE := E - E0;
  phi := phi - VII * dE * dE + VIII * Power(dE, 4) - IX * Power(dE, 6);
  lam := lam0 + Xc * dE - XI * dE * dE * dE + XII * Power(dE, 5) - XIIA * Power(dE, 7);
  // OSGB36 (Airy) cartesian -> Helmert -> WGS84
  s := Sin(phi);
  nu := a / Sqrt(1 - e2 * s * s);
  x := nu * Cos(phi) * Cos(lam);
  y := nu * Cos(phi) * Sin(lam);
  z := (1 - e2) * nu * s;
  sc := -20.4894e-6;
  rx := DegToRad(0.1502 / 3600);
  ry := DegToRad(0.2470 / 3600);
  rz := DegToRad(0.8421 / 3600);
  x2 := 446.448 + (1 + sc) * x - rz * y + ry * z;
  y2 := -125.157 + rz * x + (1 + sc) * y - rx * z;
  z2 := 542.060 - ry * x + rx * y + (1 + sc) * z;
  aW := 6378137.0;
  bW := 6356752.3141;
  e2W := 1 - (bW * bW) / (aW * aW);
  p := Hypot(x2, y2);
  phi := ArcTan2(z2, p * (1 - e2W));
  for i := 1 to 10 do begin
    nuW := aW / Sqrt(1 - e2W * Sqr(Sin(phi)));
    phi := ArcTan2(z2 + e2W * nuW * Sin(phi), p);
  end;
  Lat := RadToDeg(phi);
  Lon := RadToDeg(ArcTan2(y2, x2));
end;

function GridRef(E, N: Double): string;
var
  e100, n100, l1, l2: Integer;
begin
  e100 := Floor(E / 100000);
  n100 := Floor(N / 100000);
  l1 := (19 - n100) - (19 - n100) mod 5 + (e100 + 10) div 5;
  l2 := ((19 - n100) * 5) mod 25 + e100 mod 5;
  if l1 > 7 then Inc(l1);
  if l2 > 7 then Inc(l2);
  result := Chr(Ord('A') + l1) + Chr(Ord('A') + l2) + ' '
    + Format('%.5d %.5d', [Floor(E) mod 100000, Floor(N) mod 100000]);
end;

function LatLonText(Lat, Lon: Double): string;
var
  NS, EW: string;
begin
  if Lat >= 0 then NS := 'N' else NS := 'S';
  if Lon >= 0 then EW := 'E' else EW := 'W';
  result := Format('%.4f%s %.4f%s', [Abs(Lat), NS, Abs(Lon), EW]);
end;

initialization
  ComputeBoxes;
end.
