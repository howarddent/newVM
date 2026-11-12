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

unit uKentMap;

{*******************************************************************************

     TKentMapView - the healthKent demo's map: an OpenGL (TOpenGLControl)
     map of Kent and Medway's 1107 LSOAs (uKentData, British National Grid
     coordinates drawn as they are), each filled with the colour of its
     population density, a deprivation decile, or the expected heart
     attack and stroke admissions (per km2, or as a risk-factor ratio
     against England - SetColouring's Domain 0 or 1), with optional
     district and LSOA outlines, towns over 50,000, motorways, trunk
     roads, primary A roads, railways, the population barycentre, the
     heart attack and stroke barycentre (weighted by expected admissions)
     and
     geographic centre. Built on uCountyMap (CanterburyRain).

     SUB-AREAS (SetAreas): LSOAs outside the chosen North/East/West Kent
     areas are drawn grey whatever the fill, the chosen districts get a
     heavier outline, and ResetView fits the chosen districts. When more
     than one area is chosen, SetAreaCentre gives each its own population
     barycentre, heart attack and stroke barycentre and geographic centre,
     drawn smaller than the combined ones, the population one labelled
     with the area's name.

     FILLING AND CLIPPING (stencil, 8 bits):
       bit $80  land - every district (coastline-clipped) ring drawn as a
                triangle fan with INVERT: the even-odd rule
       bit $01  one LSOA at a time, the same way; then a quad over its
                bounding box drawn in its colour where the stencil is
                $81 (in this LSOA AND on land), clearing bit $01 again
     The LSOA boundaries run to mean low water, so the land test is what
     keeps the mudflats of the Thames, Medway and Swale estuaries sea-
     coloured. Routes and LSOA outlines are drawn where bit $80 is set, so
     roads and railways stop at the coast and at the area's edge.
     Needs StencilBits := 8 in the constructor.

     DRIVE TIMES (kcmDrive, SetDriveDomain): the fill is each LSOA's
     modelled drive time to the chosen hospital (or the nearer/nearest of
     several) in 10-minute bands, and the isochrones - 15, 30, 45 and 60
     minutes, from a 500 m grid - follow the speed scenario
     (SetDriveScenario: free-flow, morning peak, blue light) and are drawn on land, over any fill, when
     ShowIsochrones is set; the longest line of each is labelled. Hospitals
     (ShowHospitals) are red squares with a white cross, the chosen ones
     larger; with them, the best single site for the scenario is a green
     star (larger when it is the chosen domain), and the sites within 2 and
     5 minutes of its mean are outlined in green (DrawBestZones).

     VIEW: wheel zooms about the cursor (1x .. 40x), a left drag pans, a
     left click without a drag selects the LSOA under the cursor
     (OnSelectLsoa), ResetView fits the whole area again.

     LABELS: town names and the two centres' captions are text textures
     (TVMPlot2D's technique: the LCL draws the string on a bitmap, its
     darkness becomes the alpha), drawn on a translucent white box so
     they read over any fill.

     Like TVMPlot2D, Paint is MakeCurrent + RenderScene + SwapBuffers, and
     SaveToPNG renders and reads the back buffer before any swap.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics,
  IntfGraphics, FPImage, FPWritePNG,
  GL, OpenGLContext,
  uKentData;

type
  TKentColourMode = (kcmNone, kcmDensity, kcmDeprivation, kcmCvd, kcmDrive);
  TSelectLsoaEvent = procedure(Sender: TObject; Lsoa: Integer) of object;

  TKentCentres = record
    BE, BN, CE, CN, GE, GN: Double;   // population, admissions, geographic
  end;

  TKentTextTexture = record
    TexID: GLuint;
    W, H: Integer;
    Built: Boolean;
  end;

  { TKentMapView }

  TKentMapView = class(TOpenGLControl)
  private
    FMode: TKentColourMode;
    FDomain: Integer;
    FShowDistricts, FShowLsoaLines, FShowTowns: Boolean;
    FShowMotorways, FShowTrunk, FShowPrimary, FShowRail: Boolean;
    FShowBarycentre, FShowGeoCentre, FShowCvdBarycentre: Boolean;
    FShowIsochrones, FShowHospitals: Boolean;
    FDriveDomain, FDriveScenario: Integer;
    FIsoLabel: array[0..3] of Integer;   // longest line of each level, -1 none
    FBaryE, FBaryN, FGeoE, FGeoN, FCvdE, FCvdN: Double;
    FSelected: Integer;
    FAreas: TAreaSet;
    FLsoaOn, FDistrictOn: TBoolArray;
    FAreaC: array[0..AreaCount - 1] of TKentCentres;
    FOnSelectLsoa: TSelectLsoaEvent;
    FOnViewChange: TNotifyEvent;
    // view: full extent, zoom about a centre
    FEMin, FEMax, FNMin, FNMax: Double;
    FZoom, FCenE, FCenN: Double;
    FScale: Double;                 // pixels per metre at the current zoom
    // mouse
    FDragging, FDragged: Boolean;
    FDragX, FDragY: Integer;
    FDragCenE, FDragCenN: Double;
    // labels
    FTownTex: array[0..TownCount - 1] of TKentTextTexture;
    FBaryTex, FGeoTex, FCvdTex: TKentTextTexture;
    FAreaTex: array[0..AreaCount - 1] of TKentTextTexture;
    FHospTex: array[0..HospitalCount - 1] of TKentTextTexture;
    FIsoTex: array[0..3] of TKentTextTexture;
    FBestTex: TKentTextTexture;
    FTexBuilt: Boolean;
    procedure UpdateScale;
    procedure ToPixel(E, N: Double; out PX, PY: Double);
    procedure ToWorld(PX, PY: Double; out E, N: Double);
    function RenderScene: Boolean;
    procedure DrawRoutes;
    procedure DrawMarkers;
    procedure DrawIsochrones;
    procedure FindIsoLabels;
    procedure DrawIsoLabels;
    procedure DrawHospitals;
    procedure DrawBestZones;
    procedure DrawBestSite;
    procedure BuildTextures;
    procedure FreeTextures;
    function CreateTextTexture(const S: string; FontSize: Integer; Bold: Boolean): TKentTextTexture;
    procedure DrawLabel(const Tex: TKentTextTexture; X, Y: Double; LeftAlign: Boolean);
    procedure SetBool(var F: Boolean; V: Boolean);
    procedure SetSelected(AValue: Integer);
    procedure SetShowDistricts(V: Boolean);
    procedure SetShowLsoaLines(V: Boolean);
    procedure SetShowTowns(V: Boolean);
    procedure SetShowMotorways(V: Boolean);
    procedure SetShowTrunk(V: Boolean);
    procedure SetShowPrimary(V: Boolean);
    procedure SetShowRail(V: Boolean);
    procedure SetShowBarycentre(V: Boolean);
    procedure SetShowGeoCentre(V: Boolean);
    procedure SetShowCvdBarycentre(V: Boolean);
    procedure SetShowIsochrones(V: Boolean);
    procedure SetShowHospitals(V: Boolean);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure SetColouring(AMode: TKentColourMode; ADomain: Integer);
    procedure SetBarycentre(E, N: Double);
    procedure SetGeoCentre(E, N: Double);
    procedure SetCvdBarycentre(E, N: Double);
    procedure SetDriveDomain(D: Integer);      // isochrones and hospital highlight
    procedure SetDriveScenario(S: Integer);    // 0 free-flow, 1 peak, 2 blue light
    procedure SetAreas(S: TAreaSet);
    procedure SetAreaCentre(Area: Integer; const C: TKentCentres);   // NaN BE hides it
    procedure ResetView;
    // centre the view on (E, N) at zoom AZoom (1 = whole area)
    procedure SetView(E, N, AZoom: Double);
    function SaveToPNG(const FileName: string): Boolean;
    property Zoom: Double read FZoom;
    property Areas: TAreaSet read FAreas;
    property Selected: Integer read FSelected write SetSelected;    // -1 none
    property ShowDistricts: Boolean read FShowDistricts write SetShowDistricts;
    property ShowLsoaLines: Boolean read FShowLsoaLines write SetShowLsoaLines;
    property ShowTowns: Boolean read FShowTowns write SetShowTowns;
    property ShowMotorways: Boolean read FShowMotorways write SetShowMotorways;
    property ShowTrunk: Boolean read FShowTrunk write SetShowTrunk;
    property ShowPrimary: Boolean read FShowPrimary write SetShowPrimary;
    property ShowRail: Boolean read FShowRail write SetShowRail;
    property ShowBarycentre: Boolean read FShowBarycentre write SetShowBarycentre;
    property ShowGeoCentre: Boolean read FShowGeoCentre write SetShowGeoCentre;
    property ShowCvdBarycentre: Boolean read FShowCvdBarycentre write SetShowCvdBarycentre;
    property ShowIsochrones: Boolean read FShowIsochrones write SetShowIsochrones;
    property ShowHospitals: Boolean read FShowHospitals write SetShowHospitals;
    property DriveDomain: Integer read FDriveDomain;
    property DriveScenario: Integer read FDriveScenario;
    property OnSelectLsoa: TSelectLsoaEvent read FOnSelectLsoa write FOnSelectLsoa;
    property OnViewChange: TNotifyEvent read FOnViewChange write FOnViewChange;
  end;

const
  DensityLo = 10.0;       // people per km2, bottom of the (log) colour scale
  DensityHi = 15000.0;    // top
  CvdDensityLo = 0.03;    // expected admissions per km2 a year (log scale)
  CvdDensityHi = 50.0;
  CvdRatioSpan = 1.7;     // ratio scale 1/1.7 .. 1.7, log, white at 1
  clSea = TColor($EFE3CF);          // BGR: RGB(207, 227, 239)
  clLand = TColor($E9EFF2);         // RGB(242, 239, 233)
  clMotorway = TColor($B5550F);     // RGB(15, 85, 181)
  clTrunk = TColor($3A8A1F);        // RGB(31, 138, 58)
  clPrimary = TColor($0062C8);      // RGB(200, 98, 0)
  clRail = TColor($303030);
  clBary = TColor($1C1CD8);         // RGB(216, 28, 28)
  clCvdBary = TColor($A01E8C);      // RGB(140, 30, 160)
  clOutside = TColor($CFCFCF);      // LSOAs outside the chosen areas
  clHospital = TColor($2020C8);     // RGB(200, 32, 32)
  clBestSite = TColor($3C8C14);     // RGB(20, 140, 60)
  clBestZone = TColor($1E5A00);     // RGB(0, 90, 30), darker: the drive fill is green near it
  clIsochrone = TColor($9900D6);    // RGB(214, 0, 153)
  DriveBandMinutes = 10;            // fill bands
  DriveBandCount = 7;               // 0-10 .. 50-60, 60+
  IsoLevelCount = 4;
  IsoLevels: array[0..IsoLevelCount - 1] of Integer = (15, 30, 45, 60);

// fill colours, shared with the form's legend
function DensityColour(D: Double): TColor;           // people per km2
function DecileColour(Decile: Integer): TColor;      // 1 (most deprived) .. 10
function CvdDensityColour(D: Double): TColor;        // admissions per km2 a year
function CvdRatioColour(R: Double): TColor;          // against England, 1 = white
function DriveBandColour(Band: Integer): TColor;  // 0 .. DriveBandCount - 1
function DriveColour(Minutes: Double): TColor;
function LsoaFillColour(Mode: TKentColourMode; Domain, i: Integer; Scenario: Integer = 0): TColor;

implementation

const
  MarginPx = 10;
  MinZoom = 1.0;
  MaxZoom = 40.0;

type
  TRGB = record r, g, b: Byte; end;

const
  // ColorBrewer Purples, 9 classes
  PurpleStops: array[0..8] of TRGB = (
    (r: 252; g: 251; b: 253), (r: 239; g: 237; b: 245), (r: 218; g: 218; b: 235),
    (r: 188; g: 189; b: 220), (r: 158; g: 154; b: 200), (r: 128; g: 125; b: 186),
    (r: 106; g: 81; b: 163), (r: 84; g: 39; b: 143), (r: 63; g: 0; b: 125));
  // ColorBrewer RdBu, 10 classes: decile 1 (most deprived) dark red .. 10 dark blue
  DecileStops: array[1..10] of TRGB = (
    (r: 103; g: 0; b: 31), (r: 178; g: 24; b: 43), (r: 214; g: 96; b: 77),
    (r: 244; g: 165; b: 130), (r: 253; g: 219; b: 199), (r: 209; g: 229; b: 240),
    (r: 146; g: 197; b: 222), (r: 67; g: 147; b: 195), (r: 33; g: 102; b: 172),
    (r: 5; g: 48; b: 97));

  // ColorBrewer YlOrRd, 9 classes
  HeatStops: array[0..8] of TRGB = (
    (r: 255; g: 255; b: 204), (r: 255; g: 237; b: 160), (r: 254; g: 217; b: 118),
    (r: 254; g: 178; b: 76), (r: 253; g: 141; b: 60), (r: 252; g: 78; b: 42),
    (r: 227; g: 26; b: 28), (r: 189; g: 0; b: 38), (r: 128; g: 0; b: 38));
  // ColorBrewer RdBu, 9 classes, blue (lower risk) .. red (higher)
  RatioStops: array[0..8] of TRGB = (
    (r: 33; g: 102; b: 172), (r: 67; g: 147; b: 195), (r: 146; g: 197; b: 222),
    (r: 209; g: 229; b: 240), (r: 247; g: 247; b: 247), (r: 253; g: 219; b: 199),
    (r: 244; g: 165; b: 130), (r: 214; g: 96; b: 77), (r: 178; g: 24; b: 43));

  // ColorBrewer RdYlGn, 7 classes, reversed: near green .. far red
  DriveStops: array[0..DriveBandCount - 1] of TRGB = (
    (r: 26; g: 152; b: 80), (r: 145; g: 207; b: 96), (r: 217; g: 239; b: 139),
    (r: 255; g: 255; b: 191), (r: 254; g: 224; b: 139), (r: 252; g: 141; b: 89),
    (r: 215; g: 48; b: 39));

function Ramp(const Stops: array of TRGB; t: Double): TColor;
var
  i: Integer;
  f: Double;
begin
  t := EnsureRange(t, 0, 1) * High(Stops);
  i := Min(Trunc(t), High(Stops) - 1);
  f := t - i;
  result := RGBToColor(Round(Stops[i].r + f * (Stops[i + 1].r - Stops[i].r)),
                       Round(Stops[i].g + f * (Stops[i + 1].g - Stops[i].g)),
                       Round(Stops[i].b + f * (Stops[i + 1].b - Stops[i].b)));
end;

function DensityColour(D: Double): TColor;
begin
  if IsNan(D) or (D <= 0) then Exit(clLand);
  result := Ramp(PurpleStops, (Log10(D) - Log10(DensityLo)) / (Log10(DensityHi) - Log10(DensityLo)));
end;

function CvdDensityColour(D: Double): TColor;
begin
  if IsNan(D) or (D <= 0) then Exit(clLand);
  result := Ramp(HeatStops, (Log10(D) - Log10(CvdDensityLo)) / (Log10(CvdDensityHi) - Log10(CvdDensityLo)));
end;

function CvdRatioColour(R: Double): TColor;
begin
  if IsNan(R) or (R <= 0) then Exit(clLand);
  result := Ramp(RatioStops, 0.5 + 0.5 * Ln(R) / Ln(CvdRatioSpan));
end;

function DecileColour(Decile: Integer): TColor;
begin
  Decile := EnsureRange(Decile, 1, 10);
  with DecileStops[Decile] do result := RGBToColor(r, g, b);
end;

function DriveBandColour(Band: Integer): TColor;
begin
  with DriveStops[EnsureRange(Band, 0, DriveBandCount - 1)] do result := RGBToColor(r, g, b);
end;

function DriveColour(Minutes: Double): TColor;
begin
  if IsNan(Minutes) then Exit(clLand);
  result := DriveBandColour(Trunc(Minutes / DriveBandMinutes));
end;

function LsoaFillColour(Mode: TKentColourMode; Domain, i: Integer; Scenario: Integer): TColor;
begin
  case Mode of
    kcmDrive: result := DriveColour(LsoaDriveMinutes(i, Domain, Scenario));
    kcmDensity: result := DensityColour(LsoaDensity(i));
    kcmDeprivation: result := DecileColour(LsoaDecileOf(i, Domain));
    kcmCvd:
      if Domain = 0 then result := CvdDensityColour(LsoaCvdDensity(i))
      else result := CvdRatioColour(LsoaCvdRatio(i));
  else
    result := clLand;
  end;
end;

procedure GLColour(C: TColor; Alpha: Single = 1);
begin
  C := ColorToRGB(C);
  glColor4f((C and $FF) / 255, ((C shr 8) and $FF) / 255, ((C shr 16) and $FF) / 255, Alpha);
end;

{ TKentMapView }

constructor TKentMapView.Create(TheOwner: TComponent);
var
  k: Integer;
begin
  inherited Create(TheOwner);
  StencilBits := 8;
  FSelected := -1;
  FMode := kcmDensity;
  FShowDistricts := True;
  FShowTowns := True;
  FShowMotorways := True;
  FShowTrunk := True;
  FShowRail := True;
  FShowBarycentre := True;
  FDriveDomain := -1;
  FDriveScenario := 0;
  SetDriveDomain(DriveNearestDomain);
  FBaryE := NaN;
  FGeoE := NaN;
  FCvdE := NaN;
  for k := 0 to AreaCount - 1 do FAreaC[k].BE := NaN;
  SetAreas(AllAreas);
end;

destructor TKentMapView.Destroy;
begin
  if HandleAllocated and MakeCurrent then FreeTextures;
  inherited Destroy;
end;

// the chosen areas: grey the rest and fit the view to the chosen districts
procedure TKentMapView.SetAreas(S: TAreaSet);
var
  d, r, k: Integer;
  any: Boolean;
begin
  FAreas := S;
  FLsoaOn := AreaLsoaMask(S);
  FDistrictOn := AreaDistrictMask(S);
  any := False;
  for d := 0 to DistrictCount - 1 do begin
    if not FDistrictOn[d] and (S <> []) then Continue;
    for r := DistrictRingFirst[d] to DistrictRingFirst[d + 1] - 1 do
      for k := DistrictRingStart[r] to DistrictRingStart[r + 1] - 1 do begin
        if not any then begin
          FEMin := DistrictPtE[k]; FEMax := FEMin;
          FNMin := DistrictPtN[k]; FNMax := FNMin;
          any := True;
        end;
        FEMin := Min(FEMin, DistrictPtE[k]); FEMax := Max(FEMax, DistrictPtE[k]);
        FNMin := Min(FNMin, DistrictPtN[k]); FNMax := Max(FNMax, DistrictPtN[k]);
      end;
  end;
  ResetView;
end;

procedure TKentMapView.SetAreaCentre(Area: Integer; const C: TKentCentres);
begin
  FAreaC[Area] := C;
  Invalidate;
end;

procedure TKentMapView.ResetView;
begin
  FZoom := 1;
  FCenE := (FEMin + FEMax) / 2;
  FCenN := (FNMin + FNMax) / 2;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TKentMapView.SetView(E, N, AZoom: Double);
begin
  FZoom := EnsureRange(AZoom, MinZoom, MaxZoom);
  FCenE := E;
  FCenN := N;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

procedure TKentMapView.UpdateScale;
begin
  FScale := FZoom * Min((Width - 2 * MarginPx) / (FEMax - FEMin), (Height - 2 * MarginPx) / (FNMax - FNMin));
end;

procedure TKentMapView.ToPixel(E, N: Double; out PX, PY: Double);
begin
  PX := Width / 2 + (E - FCenE) * FScale;
  PY := Height / 2 + (N - FCenN) * FScale;
end;

procedure TKentMapView.ToWorld(PX, PY: Double; out E, N: Double);
begin
  E := FCenE + (PX - Width / 2) / FScale;
  N := FCenN + (PY - Height / 2) / FScale;
end;

procedure TKentMapView.SetColouring(AMode: TKentColourMode; ADomain: Integer);
begin
  FMode := AMode;
  if AMode = kcmDrive then begin
    FDomain := EnsureRange(ADomain, 0, DriveDomainCount - 1);
    SetDriveDomain(FDomain);
  end else
    FDomain := EnsureRange(ADomain, 0, DomainCount - 1);
  Invalidate;
end;

procedure TKentMapView.SetDriveDomain(D: Integer);
begin
  D := EnsureRange(D, 0, DriveDomainCount - 1);
  if D = FDriveDomain then Exit;
  FDriveDomain := D;
  FindIsoLabels;
end;

procedure TKentMapView.SetDriveScenario(S: Integer);
begin
  S := EnsureRange(S, 0, DriveScenarioCount - 1);
  if S = FDriveScenario then Exit;
  FDriveScenario := S;
  FindIsoLabels;
end;

// the longest line of each isochrone level, for its label
procedure TKentMapView.FindIsoLabels;
var
  k, j, lv: Integer;
  best: array[0..IsoLevelCount - 1] of Double;
  l: Double;
begin
  for lv := 0 to IsoLevelCount - 1 do begin FIsoLabel[lv] := -1; best[lv] := 0; end;
  for k := 0 to IsoCount - 1 do begin
    if (IsoDomain[k] <> FDriveDomain) or (IsoScenario[k] <> FDriveScenario) then Continue;
    lv := 0;
    while (lv < IsoLevelCount - 1) and (IsoLevels[lv] <> IsoMinutes[k]) do Inc(lv);
    l := 0;
    for j := IsoStart[k] + 1 to IsoStart[k + 1] - 1 do
      l := l + Hypot(IsoPtE[j] - IsoPtE[j - 1], IsoPtN[j] - IsoPtN[j - 1]);
    if l > best[lv] then begin best[lv] := l; FIsoLabel[lv] := k; end;
  end;
  Invalidate;
end;

procedure TKentMapView.SetBarycentre(E, N: Double);
begin
  FBaryE := E;
  FBaryN := N;
  Invalidate;
end;

procedure TKentMapView.SetCvdBarycentre(E, N: Double);
begin
  FCvdE := E;
  FCvdN := N;
  Invalidate;
end;

procedure TKentMapView.SetGeoCentre(E, N: Double);
begin
  FGeoE := E;
  FGeoN := N;
  Invalidate;
end;

procedure TKentMapView.SetBool(var F: Boolean; V: Boolean);
begin
  if F = V then Exit;
  F := V;
  Invalidate;
end;

procedure TKentMapView.SetSelected(AValue: Integer);
begin
  if FSelected = AValue then Exit;
  FSelected := AValue;
  Invalidate;
end;

procedure TKentMapView.SetShowDistricts(V: Boolean); begin SetBool(FShowDistricts, V); end;
procedure TKentMapView.SetShowLsoaLines(V: Boolean); begin SetBool(FShowLsoaLines, V); end;
procedure TKentMapView.SetShowTowns(V: Boolean); begin SetBool(FShowTowns, V); end;
procedure TKentMapView.SetShowMotorways(V: Boolean); begin SetBool(FShowMotorways, V); end;
procedure TKentMapView.SetShowTrunk(V: Boolean); begin SetBool(FShowTrunk, V); end;
procedure TKentMapView.SetShowPrimary(V: Boolean); begin SetBool(FShowPrimary, V); end;
procedure TKentMapView.SetShowRail(V: Boolean); begin SetBool(FShowRail, V); end;
procedure TKentMapView.SetShowBarycentre(V: Boolean); begin SetBool(FShowBarycentre, V); end;
procedure TKentMapView.SetShowGeoCentre(V: Boolean); begin SetBool(FShowGeoCentre, V); end;
procedure TKentMapView.SetShowCvdBarycentre(V: Boolean); begin SetBool(FShowCvdBarycentre, V); end;
procedure TKentMapView.SetShowIsochrones(V: Boolean); begin SetBool(FShowIsochrones, V); end;
procedure TKentMapView.SetShowHospitals(V: Boolean); begin SetBool(FShowHospitals, V); end;

// ---- text ---------------------------------------------------------------------

function TKentMapView.CreateTextTexture(const S: string; FontSize: Integer;
  Bold: Boolean): TKentTextTexture;
var
  Bmp: TBitmap;
  Img: TLazIntfImage;
  x, y, W, H: Integer;
  c: TFPColor;
  TexPixels: array of Byte;
begin
  Bmp := TBitmap.Create;
  try
    Bmp.Canvas.Font.Size := FontSize;
    if Bold then Bmp.Canvas.Font.Style := [fsBold];
    W := Max(1, Bmp.Canvas.TextWidth(S) + 6);
    H := Max(1, Bmp.Canvas.TextHeight(S) + 2);
    Bmp.SetSize(W, H);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.Brush.Style := bsSolid;
    Bmp.Canvas.FillRect(0, 0, W, H);
    Bmp.Canvas.Font.Size := FontSize;
    if Bold then Bmp.Canvas.Font.Style := [fsBold];
    Bmp.Canvas.Font.Color := clBlack;
    Bmp.Canvas.Brush.Style := bsClear;
    Bmp.Canvas.TextOut(3, 1, S);
    Img := Bmp.CreateIntfImage;
    try
      SetLength(TexPixels, W * H * 4);
      for y := 0 to H - 1 do
        for x := 0 to W - 1 do begin
          c := Img.Colors[x, y];
          TexPixels[(y * W + x) * 4 + 0] := 0;
          TexPixels[(y * W + x) * 4 + 1] := 0;
          TexPixels[(y * W + x) * 4 + 2] := 0;
          TexPixels[(y * W + x) * 4 + 3] := 255 - (c.red shr 8 + c.green shr 8 + c.blue shr 8) div 3;
        end;
    finally
      Img.Free;
    end;
    glGenTextures(1, @result.TexID);
    glBindTexture(GL_TEXTURE_2D, result.TexID);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, W, H, 0, GL_RGBA, GL_UNSIGNED_BYTE, @TexPixels[0]);
    result.W := W;
    result.H := H;
    result.Built := True;
  finally
    Bmp.Free;
  end;
end;

procedure TKentMapView.BuildTextures;
var
  i: Integer;
begin
  FreeTextures;
  for i := 0 to TownCount - 1 do
    FTownTex[i] := CreateTextTexture(TownName[i], 9, True);
  FBaryTex := CreateTextTexture('population barycentre', 9, True);
  FGeoTex := CreateTextTexture('geographic centre', 9, True);
  FCvdTex := CreateTextTexture('heart attack and stroke barycentre', 9, True);
  for i := 0 to AreaCount - 1 do
    FAreaTex[i] := CreateTextTexture(AreaName[i], 9, True);
  for i := 0 to HospitalCount - 1 do
    FHospTex[i] := CreateTextTexture(HospitalShort[i], 9, True);
  for i := 0 to IsoLevelCount - 1 do
    FIsoTex[i] := CreateTextTexture(IntToStr(IsoLevels[i]) + ' min', 8, True);
  FBestTex := CreateTextTexture('best single site', 9, True);
  FTexBuilt := True;
end;

procedure TKentMapView.FreeTextures;

  procedure Del(var T: TKentTextTexture);
  begin
    if T.Built then glDeleteTextures(1, @T.TexID);
    T.Built := False;
  end;

var
  i: Integer;
begin
  for i := 0 to TownCount - 1 do Del(FTownTex[i]);
  Del(FBaryTex);
  Del(FGeoTex);
  Del(FCvdTex);
  for i := 0 to AreaCount - 1 do Del(FAreaTex[i]);
  for i := 0 to HospitalCount - 1 do Del(FHospTex[i]);
  for i := 0 to IsoLevelCount - 1 do Del(FIsoTex[i]);
  Del(FBestTex);
  FTexBuilt := False;
end;

// a label with its left (or right) edge at X, centred on Y, on a white box
procedure TKentMapView.DrawLabel(const Tex: TKentTextTexture; X, Y: Double; LeftAlign: Boolean);
var
  x0, y0: Double;
begin
  if not Tex.Built then Exit;
  if LeftAlign then x0 := Round(X) else x0 := Round(X) - Tex.W;
  y0 := Round(Y - Tex.H / 2);
  glDisable(GL_TEXTURE_2D);
  glColor4f(1, 1, 1, 0.78);
  glBegin(GL_QUADS);
    glVertex2d(x0, y0); glVertex2d(x0 + Tex.W, y0);
    glVertex2d(x0 + Tex.W, y0 + Tex.H); glVertex2d(x0, y0 + Tex.H);
  glEnd;
  glEnable(GL_TEXTURE_2D);
  glColor4f(0, 0, 0, 1);
  glBindTexture(GL_TEXTURE_2D, Tex.TexID);
  glBegin(GL_QUADS);
    glTexCoord2f(0, 1); glVertex2d(x0, y0);
    glTexCoord2f(1, 1); glVertex2d(x0 + Tex.W, y0);
    glTexCoord2f(1, 0); glVertex2d(x0 + Tex.W, y0 + Tex.H);
    glTexCoord2f(0, 0); glVertex2d(x0, y0 + Tex.H);
  glEnd;
  glDisable(GL_TEXTURE_2D);
end;

// ---- drawing ------------------------------------------------------------------

procedure TKentMapView.DrawRoutes;

  procedure Strokes(Kind: Integer);
  var
    r, k: Integer;
    px, py: Double;
  begin
    for r := 0 to RouteCount - 1 do begin
      if RouteKind[r] <> Kind then Continue;
      glBegin(GL_LINE_STRIP);
        for k := RouteStart[r] to RouteStart[r + 1] - 1 do begin
          ToPixel(RoutePtE[k], RoutePtN[k], px, py);
          glVertex2d(px, py);
        end;
      glEnd;
    end;
  end;

  procedure Road(Kind: Integer; AColour: TColor; W: Single);
  begin
    glColor4f(1, 1, 1, 0.9);                  // casing, so the road reads over any fill
    glLineWidth(W + 2);
    Strokes(Kind);
    GLColour(AColour);
    glLineWidth(W);
    Strokes(Kind);
  end;

var
  zw: Single;
begin
  zw := Min(1.6, 1 + 0.15 * Log2(FZoom));     // a little thicker when zoomed in
  if FShowRail then begin
    GLColour(clRail);
    glLineWidth(3 * zw);
    Strokes(RouteRail);
    glEnable(GL_LINE_STIPPLE);                 // the railway's white dashes
    glLineStipple(3, $F0F0);
    glColor4f(1, 1, 1, 1);
    glLineWidth(1.2 * zw);
    Strokes(RouteRail);
    glDisable(GL_LINE_STIPPLE);
  end;
  if FShowPrimary then Road(RoutePrimary, clPrimary, 1.4 * zw);
  if FShowTrunk then Road(RouteTrunk, clTrunk, 2.2 * zw);
  if FShowMotorways then Road(RouteMotorway, clMotorway, 3.0 * zw);
end;

// isochrones of the chosen drive-time domain: white casing, magenta
// line, the half hours heavier (dashes would read as railways)
procedure TKentMapView.DrawIsochrones;

  procedure Strokes(Minutes: Integer);
  var
    k, j: Integer;
    px, py: Double;
  begin
    for k := 0 to IsoCount - 1 do begin
      if (IsoDomain[k] <> FDriveDomain) or (IsoScenario[k] <> FDriveScenario)
        or (IsoMinutes[k] <> Minutes) then Continue;
      glBegin(GL_LINE_STRIP);
        for j := IsoStart[k] to IsoStart[k + 1] - 1 do begin
          ToPixel(IsoPtE[j], IsoPtN[j], px, py);
          glVertex2d(px, py);
        end;
      glEnd;
    end;
  end;

var
  lv: Integer;
  w: Single;
begin
  for lv := 0 to IsoLevelCount - 1 do begin
    if IsoLevels[lv] mod 30 = 0 then w := 3.0 else w := 1.8;
    glColor4f(1, 1, 1, 0.9);
    glLineWidth(w + 2.5);
    Strokes(IsoLevels[lv]);
    GLColour(clIsochrone);
    glLineWidth(w);
    Strokes(IsoLevels[lv]);
  end;
end;

// each level's label at the middle of its longest line
procedure TKentMapView.DrawIsoLabels;
var
  lv, k, j: Integer;
  x, y: Double;
begin
  for lv := 0 to IsoLevelCount - 1 do begin
    k := FIsoLabel[lv];
    if k < 0 then Continue;
    j := (IsoStart[k] + IsoStart[k + 1] - 1) div 2;
    ToPixel(IsoPtE[j], IsoPtN[j], x, y);
    if (x < 0) or (y < 0) or (x > Width) or (y > Height) then Continue;
    DrawLabel(FIsoTex[lv], x - FIsoTex[lv].W / 2, y, True);
  end;
end;

// red squares with a white cross; the chosen domain's hospitals larger
procedure TKentMapView.DrawHospitals;
var
  h: Integer;
  x, y, r: Double;
  chosen: Boolean;
begin
  for h := 0 to HospitalCount - 1 do begin
    ToPixel(HospitalE[h], HospitalN[h], x, y);
    chosen := DriveDomainHas(FDriveDomain, h);
    if chosen then r := 8 else r := 5.5;
    glColor4f(1, 1, 1, 1);
    glBegin(GL_QUADS);
      glVertex2d(x - r - 1.5, y - r - 1.5); glVertex2d(x + r + 1.5, y - r - 1.5);
      glVertex2d(x + r + 1.5, y + r + 1.5); glVertex2d(x - r - 1.5, y + r + 1.5);
    glEnd;
    if chosen then GLColour(clHospital) else glColor4f(0.55, 0.3, 0.3, 1);
    glBegin(GL_QUADS);
      glVertex2d(x - r, y - r); glVertex2d(x + r, y - r);
      glVertex2d(x + r, y + r); glVertex2d(x - r, y + r);
    glEnd;
    glColor4f(1, 1, 1, 1);
    glBegin(GL_QUADS);                         // the cross
      glVertex2d(x - 0.22 * r, y - 0.7 * r); glVertex2d(x + 0.22 * r, y - 0.7 * r);
      glVertex2d(x + 0.22 * r, y + 0.7 * r); glVertex2d(x - 0.22 * r, y + 0.7 * r);
      glVertex2d(x - 0.7 * r, y - 0.22 * r); glVertex2d(x + 0.7 * r, y - 0.22 * r);
      glVertex2d(x + 0.7 * r, y + 0.22 * r); glVertex2d(x - 0.7 * r, y + 0.22 * r);
    glEnd;
    DrawLabel(FHospTex[h], x + r + 3, y, True);
  end;
end;

// the sites within 2 minutes (solid) and 5 minutes (dotted) of the best
// single site's mean, for the speed scenario
procedure TKentMapView.DrawBestZones;

  procedure Strokes(Extra: Integer);
  var
    k, j: Integer;
    px, py: Double;
  begin
    for k := 0 to BestZoneCount - 1 do begin
      if (BestZoneScenario[k] <> FDriveScenario) or (BestZoneExtra[k] <> Extra) then Continue;
      glBegin(GL_LINE_STRIP);
        for j := BestZoneStart[k] to BestZoneStart[k + 1] - 1 do begin
          ToPixel(BestZonePtE[j], BestZonePtN[j], px, py);
          glVertex2d(px, py);
        end;
      glEnd;
    end;
  end;

begin
  glColor4f(1, 1, 1, 0.9);
  glLineWidth(5.0);
  Strokes(2);
  glLineWidth(4.5);
  Strokes(5);
  GLColour(clBestZone);
  glLineWidth(2.5);
  Strokes(2);
  glEnable(GL_LINE_STIPPLE);
  glLineStipple(2, $3333);
  glLineWidth(2.5);
  Strokes(5);
  glDisable(GL_LINE_STIPPLE);
end;

// a green five-pointed star at the scenario's best single site
procedure TKentMapView.DrawBestSite;

  procedure Star(x, y, r: Double);
  var
    i: Integer;
    a, rr: Double;
  begin
    glBegin(GL_TRIANGLE_FAN);
      glVertex2d(x, y);
      for i := 0 to 10 do begin
        a := Pi / 2 + Pi * i / 5;
        if Odd(i) then rr := 0.45 * r else rr := r;
        glVertex2d(x + rr * Cos(a), y + rr * Sin(a));   // y up: point at the top
      end;
    glEnd;
  end;

var
  x, y, r: Double;
begin
  ToPixel(BestSiteE[FDriveScenario], BestSiteN[FDriveScenario], x, y);
  if FDriveDomain = DriveBestDomain then r := 13 else r := 10;
  glColor4f(1, 1, 1, 1);
  Star(x, y, r + 4);
  GLColour(clBestZone);
  Star(x, y, r + 2);
  GLColour(clBestSite);
  Star(x, y, r);
  DrawLabel(FBestTex, x - FBestTex.W / 2, y + r + 6 + FBestTex.H / 2, True);   // above: the barycentres' and towns' labels sit beside and below it
end;

procedure TKentMapView.DrawMarkers;

  procedure Disc(x, y, r: Double; AColour: TColor);
  var
    i: Integer;
    a: Double;
  begin
    GLColour(AColour);
    glBegin(GL_TRIANGLE_FAN);
      glVertex2d(x, y);
      for i := 0 to 24 do begin
        a := 2 * Pi * i / 24;
        glVertex2d(x + r * Cos(a), y + r * Sin(a));
      end;
    glEnd;
    glColor4f(0, 0, 0, 1);
    glLineWidth(1.2);
    glBegin(GL_LINE_LOOP);
      for i := 0 to 23 do begin
        a := 2 * Pi * i / 24;
        glVertex2d(x + r * Cos(a), y + r * Sin(a));
      end;
    glEnd;
  end;

  procedure CrossDisc(x, y: Double; AColour: TColor);
  begin
    Disc(x, y, 8, AColour);
    glColor4f(1, 1, 1, 1);                     // white cross hair
    glLineWidth(1.5);
    glBegin(GL_LINES);
      glVertex2d(x - 5, y); glVertex2d(x + 5, y);
      glVertex2d(x, y - 5); glVertex2d(x, y + 5);
    glEnd;
  end;

var
  i: Integer;
  x, y, r: Double;
  both, cvdEast: Boolean;
begin
  if FShowTowns then
    for i := 0 to TownCount - 1 do begin
      ToPixel(TownE[i], TownN[i], x, y);
      Disc(x, y, 4, clWhite);
      DrawLabel(FTownTex[i], x + 6, y, True);
    end;
  if FShowGeoCentre and not IsNan(FGeoE) then begin
    ToPixel(FGeoE, FGeoN, x, y);
    r := 7;
    glColor4f(1, 1, 1, 1);
    glBegin(GL_QUADS);
      glVertex2d(x, y - r - 1.5); glVertex2d(x + r + 1.5, y); glVertex2d(x, y + r + 1.5); glVertex2d(x - r - 1.5, y);
    glEnd;
    glColor4f(0.1, 0.1, 0.1, 1);
    glBegin(GL_QUADS);
      glVertex2d(x, y - r); glVertex2d(x + r, y); glVertex2d(x, y + r); glVertex2d(x - r, y);
    glEnd;
    DrawLabel(FGeoTex, x - 10, y, False);
  end;
  // each chosen area's own centres, smaller, when more than one is chosen
  for i := 0 to AreaCount - 1 do
    with FAreaC[i] do begin
      if IsNan(BE) then Continue;
      if FShowGeoCentre and not IsNan(GE) then begin
        ToPixel(GE, GN, x, y);
        r := 5;
        glColor4f(1, 1, 1, 1);
        glBegin(GL_QUADS);
          glVertex2d(x, y - r - 1.5); glVertex2d(x + r + 1.5, y); glVertex2d(x, y + r + 1.5); glVertex2d(x - r - 1.5, y);
        glEnd;
        glColor4f(0.1, 0.1, 0.1, 1);
        glBegin(GL_QUADS);
          glVertex2d(x, y - r); glVertex2d(x + r, y); glVertex2d(x, y + r); glVertex2d(x - r, y);
        glEnd;
      end;
      if FShowCvdBarycentre and not IsNan(CE) then begin
        ToPixel(CE, CN, x, y);
        Disc(x, y, 5.5, clCvdBary);
      end;
      if FShowBarycentre then begin
        ToPixel(BE, BN, x, y);
        Disc(x, y, 5.5, clBary);
        if FShowCvdBarycentre and not IsNan(CE) and (CE >= BE) then
          DrawLabel(FAreaTex[i], x - 8, y, False)
        else
          DrawLabel(FAreaTex[i], x + 8, y, True);
      end else if FShowCvdBarycentre and not IsNan(CE) then begin
        ToPixel(CE, CN, x, y);
        DrawLabel(FAreaTex[i], x + 8, y, True);
      end;
    end;
  // the two barycentres lie a few km apart, so with both shown each
  // label goes on the side away from the other marker
  both := FShowBarycentre and FShowCvdBarycentre and not IsNan(FBaryE) and not IsNan(FCvdE);
  cvdEast := FCvdE >= FBaryE;
  if FShowBarycentre and not IsNan(FBaryE) then begin
    ToPixel(FBaryE, FBaryN, x, y);
    CrossDisc(x, y, clBary);
    if both and cvdEast then DrawLabel(FBaryTex, x - 11, y, False)
    else DrawLabel(FBaryTex, x + 11, y, True);
  end;
  if FShowCvdBarycentre and not IsNan(FCvdE) then begin
    ToPixel(FCvdE, FCvdN, x, y);
    CrossDisc(x, y, clCvdBary);
    if both and not cvdEast then DrawLabel(FCvdTex, x - 11, y, False)
    else DrawLabel(FCvdTex, x + 11, y, True);
  end;
end;

function TKentMapView.RenderScene: Boolean;
var
  i, r: Integer;
  px, py, x0, y0, x1, y1: Double;

  procedure FanRing(First, Last: Integer; const E, N: array of Single);
  var
    j: Integer;
  begin
    glBegin(GL_TRIANGLE_FAN);
      for j := First to Last do begin
        ToPixel(E[j], N[j], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;

  procedure LoopRing(First, Last: Integer; const E, N: array of Single);
  var
    j: Integer;
  begin
    glBegin(GL_LINE_LOOP);
      for j := First to Last do begin
        ToPixel(E[j], N[j], px, py);
        glVertex2d(px, py);
      end;
    glEnd;
  end;

begin
  result := False;
  if (Width = 0) or (Height = 0) then Exit;
  if not FTexBuilt then BuildTextures;
  UpdateScale;
  glViewport(0, 0, Width, Height);
  glClearColor((clSea and $FF) / 255, ((clSea shr 8) and $FF) / 255, ((clSea shr 16) and $FF) / 255, 1);
  glClearStencil(0);
  glClear(GL_COLOR_BUFFER_BIT or GL_STENCIL_BUFFER_BIT);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(0, Width, 0, Height, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;
  glDisable(GL_BLEND);
  glDisable(GL_LINE_SMOOTH);
  glDisable(GL_TEXTURE_2D);

  // ---- land mask (bit $80) and base colour ----
  glEnable(GL_STENCIL_TEST);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glStencilMask($80);
  glStencilFunc(GL_ALWAYS, 0, $FF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
  for r := 0 to DistrictRingCount - 1 do
    FanRing(DistrictRingStart[r], DistrictRingStart[r + 1] - 1, DistrictPtE, DistrictPtN);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  glStencilFunc(GL_EQUAL, $80, $80);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
  GLColour(clLand);
  glBegin(GL_QUADS);
    glVertex2d(0, 0); glVertex2d(Width, 0); glVertex2d(Width, Height); glVertex2d(0, Height);
  glEnd;

  // ---- LSOA fills (bit $01), on land only; outside the chosen areas grey ----
  if (FMode <> kcmNone) or (FAreas <> AllAreas) then begin
    glStencilMask($01);
    for i := 0 to LsoaCount - 1 do begin
      if (FMode = kcmNone) and FLsoaOn[i] then Continue;
      ToPixel(LsoaBoxE0(i), LsoaBoxN0(i), x0, y0);
      ToPixel(LsoaBoxE1(i), LsoaBoxN1(i), x1, y1);
      if (x1 < 0) or (y1 < 0) or (x0 > Width) or (y0 > Height) then Continue;   // off screen
      glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
      glStencilFunc(GL_ALWAYS, 0, $FF);
      glStencilOp(GL_KEEP, GL_KEEP, GL_INVERT);
      for r := LsoaRingFirst[i] to LsoaRingFirst[i + 1] - 1 do
        FanRing(LsoaRingStart[r], LsoaRingStart[r + 1] - 1, LsoaPtE, LsoaPtN);
      glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
      glStencilFunc(GL_EQUAL, $81, $81);
      glStencilOp(GL_ZERO, GL_ZERO, GL_ZERO);       // write mask $01: clears only this LSOA's bit
      if FLsoaOn[i] then GLColour(LsoaFillColour(FMode, FDomain, i, FDriveScenario))
      else GLColour(clOutside);
      glBegin(GL_QUADS);
        glVertex2d(x0 - 1, y0 - 1); glVertex2d(x1 + 1, y0 - 1);
        glVertex2d(x1 + 1, y1 + 1); glVertex2d(x0 - 1, y1 + 1);
      glEnd;
    end;
  end;

  // ---- lines on land only ----
  glStencilMask($00);
  glStencilFunc(GL_EQUAL, $80, $80);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glEnable(GL_LINE_SMOOTH);
  if FShowLsoaLines then begin
    glColor4f(0.2, 0.2, 0.25, 0.35);
    glLineWidth(0.7);
    for r := 0 to LsoaRingCount - 1 do
      LoopRing(LsoaRingStart[r], LsoaRingStart[r + 1] - 1, LsoaPtE, LsoaPtN);
  end;
  DrawRoutes;
  if FShowIsochrones then DrawIsochrones;
  if FShowHospitals then DrawBestZones;
  glDisable(GL_STENCIL_TEST);
  glStencilMask($FF);

  // ---- coastline / district outlines ----
  if FShowDistricts then begin
    glColor4f(0.15, 0.15, 0.2, 0.9);
    glLineWidth(1.0);
    for r := 0 to DistrictRingCount - 1 do
      LoopRing(DistrictRingStart[r], DistrictRingStart[r + 1] - 1, DistrictPtE, DistrictPtN);
  end;
  if (FAreas <> AllAreas) and (FAreas <> []) then begin
    glColor4f(0.1, 0.1, 0.15, 1);              // the chosen districts, heavier
    glLineWidth(2.2);
    for i := 0 to DistrictCount - 1 do
      if FDistrictOn[i] then
        for r := DistrictRingFirst[i] to DistrictRingFirst[i + 1] - 1 do
          LoopRing(DistrictRingStart[r], DistrictRingStart[r + 1] - 1, DistrictPtE, DistrictPtN);
  end;
  if (FSelected >= 0) and (FSelected < LsoaCount) then begin
    glColor4f(1, 1, 1, 1);                     // white halo, black line on top
    glLineWidth(5.0);
    for r := LsoaRingFirst[FSelected] to LsoaRingFirst[FSelected + 1] - 1 do
      LoopRing(LsoaRingStart[r], LsoaRingStart[r + 1] - 1, LsoaPtE, LsoaPtN);
    glColor4f(0, 0, 0, 1);
    glLineWidth(2.2);
    for r := LsoaRingFirst[FSelected] to LsoaRingFirst[FSelected + 1] - 1 do
      LoopRing(LsoaRingStart[r], LsoaRingStart[r + 1] - 1, LsoaPtE, LsoaPtN);
  end;
  glDisable(GL_LINE_SMOOTH);
  if FShowIsochrones then DrawIsoLabels;
  DrawMarkers;
  if FShowHospitals then begin
    DrawHospitals;
    DrawBestSite;
  end;
  glDisable(GL_BLEND);
  result := True;
end;

procedure TKentMapView.Paint;
begin
  if not MakeCurrent then Exit;
  if RenderScene then SwapBuffers;
end;

procedure TKentMapView.Resize;
begin
  inherited Resize;
  Invalidate;
end;

// ---- mouse ----------------------------------------------------------------------

procedure TKentMapView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FDragging := True;
  FDragged := False;
  FDragX := X;
  FDragY := Y;
  FDragCenE := FCenE;
  FDragCenN := FCenN;
end;

procedure TKentMapView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then Exit;
  if (Abs(X - FDragX) > 3) or (Abs(Y - FDragY) > 3) then FDragged := True;
  if FDragged then begin
    UpdateScale;
    FCenE := FDragCenE - (X - FDragX) / FScale;
    FCenN := FDragCenN + (Y - FDragY) / FScale;
    Invalidate;
  end;
end;

procedure TKentMapView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  E, N: Double;
  i: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button <> mbLeft then Exit;
  FDragging := False;
  if FDragged then begin
    if Assigned(FOnViewChange) then FOnViewChange(Self);
    Exit;
  end;
  UpdateScale;
  ToWorld(X, Height - Y, E, N);
  i := LsoaAt(E, N);
  if i >= 0 then begin
    Selected := i;
    if Assigned(FOnSelectLsoa) then FOnSelectLsoa(Self, i);
  end;
end;

function TKentMapView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
var
  E, N, Z: Double;
begin
  result := True;
  UpdateScale;
  ToWorld(MousePos.X, Height - MousePos.Y, E, N);     // keep this point under the cursor
  if WheelDelta > 0 then Z := FZoom * 1.25 else Z := FZoom / 1.25;
  Z := EnsureRange(Z, MinZoom, MaxZoom);
  if Z = FZoom then Exit;
  FZoom := Z;
  UpdateScale;
  FCenE := E - (MousePos.X - Width / 2) / FScale;
  FCenN := N - (Height - MousePos.Y - Height / 2) / FScale;
  Invalidate;
  if Assigned(FOnViewChange) then FOnViewChange(Self);
end;

function TKentMapView.SaveToPNG(const FileName: string): Boolean;
var
  W, H, x, y, o: Integer;
  Buf: array of Byte;
  Img: TFPMemoryImage;
  Writer: TFPWriterPNG;
  col: TFPColor;
begin
  result := False;
  if not HandleAllocated or not MakeCurrent then Exit;
  if not RenderScene then Exit;
  W := Width;
  H := Height;
  SetLength(Buf, W * H * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadBuffer(GL_BACK);
  glReadPixels(0, 0, W, H, GL_RGBA, GL_UNSIGNED_BYTE, @Buf[0]);
  Img := TFPMemoryImage.Create(W, H);
  Writer := TFPWriterPNG.Create;
  try
    Writer.UseAlpha := False;
    for y := 0 to H - 1 do
      for x := 0 to W - 1 do begin
        o := ((H - 1 - y) * W + x) * 4;
        col.red := Buf[o] * 257;
        col.green := Buf[o + 1] * 257;
        col.blue := Buf[o + 2] * 257;
        col.alpha := alphaOpaque;
        Img.Colors[x, y] := col;
      end;
    Img.SaveToFile(FileName, Writer);
    result := True;
  finally
    Writer.Free;
    Img.Free;
  end;
  Invalidate;
end;

end.
