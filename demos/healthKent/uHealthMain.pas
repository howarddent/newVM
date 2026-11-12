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

unit uHealthMain;

{*******************************************************************************

     Main form for the healthKent demo: Kent and Medway (the NHS Kent and
     Medway ICB area) by LSOA, on two tabs.

     MAP - uKentMap.TKentMapView, coloured by
       - population density: mid-2024 ONS estimates over ONS land area,
         people per km2 on a log scale (sequential purples), or
       - deprivation: an English Indices of Deprivation 2025 national
         decile, for the IMD or any of its seven domains (a combo box);
         diverging red (decile 1, most deprived) to blue (decile 10,
         least deprived),
       - expected emergency admissions for heart attack or stroke (uKentData
         has the model): per km2 a year on a log scale (ColorBrewer
         YlOrRd), or as the risk-factor ratio against an English
         population of the same age and sex (blue below, red above);
         the combo box picks which,
       - or no fill,
     with check boxes for district and LSOA outlines, built-up areas over
     50,000 people, motorways, trunk roads, primary A roads, railways,
     the population barycentre, the heart attack and stroke barycentre
     (weighted by expected admissions) and the geographic centre. Wheel zooms,
     drag pans, a click selects an LSOA and the memo shows its figures.
     The legend beside the map shows the colour scale (and, for
     deprivation, the share of residents in each decile) and the line and
     marker key.

     AREAS: check boxes choose North, East and West Kent (whole districts,
     as uKentData's header defines them), separately or in any
     combination; all three is Kent and Medway. LSOAs outside the choice
     are grey, the memo's totals, district tables, decile shares and
     admissions are for the choice, and a "by area" table gives each
     area, the combination and Kent and Medway side by side: population,
     share, density, % aged 65+, mean IMD score, expected admissions and
     ratio, and each one's population and admissions barycentres and
     geographic centre. The map shows the combination's centres, plus,
     when more than one area is chosen, each area's own (smaller markers,
     labelled with the area's name).

     The memo also gives the area's totals, the population barycentre
     (computed with newVM - see uKentData) as a grid reference and
     latitude/longitude, how far and which way it lies from the geographic
     centre, and a table by district.

     SOURCES - a glossary of every dataset compiled in (publisher,
     edition, licence, link and what the demo uses it for) and of the
     terms used, from uKentData's Sources and Glossary tables.

     For the admissions the memo adds, for a selected LSOA, its estimated
     risk factors and each one's effect on the expected admissions; for
     the area, the totals, a table by district, and the model's check
     against OHID's observed MSOA admission ratios.

     COMMAND LINE: --snapshot=<prefix> saves the map coloured by density
     (<prefix>_density.png), by IMD decile (<prefix>_imd.png), by health
     deprivation (<prefix>_health.png), by expected admissions per km2
     (<prefix>_cvd.png) and by risk-factor ratio (<prefix>_cvdratio.png),
     a zoomed view round the barycentre (<prefix>_zoom.png) and the window
     (<prefix>_window.bmp), prints the memo and exits. --colour=<0..3>
     picks the fill (0 density, 1 deprivation, 2 admissions, 3 none),
     --domain=<0..7> the deprivation measure, --cvd=<0|1> admissions per
     km2 or the ratio, --areas=<list> the areas (e.g. north,east; default
     all three).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, Graphics, Dialogs,
  ExtCtrls, StdCtrls, ComCtrls,
  uKentData, uKentMap;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnReset: TButton;
    btnSave: TButton;
    cbDomain: TComboBox;
    cgAreas: TCheckGroup;
    cgLayers: TCheckGroup;
    dlgSave: TSaveDialog;
    lblDomain: TLabel;
    lblStatus: TLabel;
    lblTitle: TLabel;
    memInfo: TMemo;
    memSources: TMemo;
    pbLegend: TPaintBox;
    pcMain: TPageControl;
    pnlButtons: TPanel;
    pnlMap: TPanel;
    pnlSide: TPanel;
    pnlStatus: TPanel;
    rgColour: TRadioGroup;
    rgSpeeds: TRadioGroup;
    tabMap: TTabSheet;
    tabSources: TTabSheet;
    procedure btnResetClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure cbDomainChange(Sender: TObject);
    procedure cgAreasItemClick(Sender: TObject; Index: integer);
    procedure cgLayersItemClick(Sender: TObject; Index: integer);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure pbLegendPaint(Sender: TObject);
    procedure rgColourClick(Sender: TObject);
    procedure rgSpeedsClick(Sender: TObject);
  private
    FMap: TKentMapView;
    FBaryE, FBaryN, FGeoE, FGeoN, FCvdE, FCvdN: Double;
    FSnapshot: string;
    FShown: Boolean;
    FDepDomain, FCvdMeasure, FDriveDomain, FDriveScenario, FBoxMode: Integer;
    FAreas: TAreaSet;
    FInc, FDistInc: TBoolArray;    // the chosen areas' LSOAs and districts
    procedure FillMeasureBox;
    procedure ApplyAreas;
    procedure AreaTable(L: TStrings);
    procedure ApplyColouring;
    procedure ApplyLayers;
    procedure LsoaSelected(Sender: TObject; Lsoa: Integer);
    procedure ViewChanged(Sender: TObject);
    procedure ShowInfo;
    procedure CvdSummary(L: TStrings);
    procedure CorridorSummary(L: TStrings; Total: Double);
    procedure DriveSummary(L: TStrings);
    procedure WhhKchSummary(L: TStrings);
    procedure FillSources;
    function DecileShare(Domain, Decile: Integer): Double;
    procedure RunSnapshot(Data: PtrInt);
    procedure SnapshotException(Sender: TObject; E: Exception);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

const
  // colour radio items
  ciDensity = 0; ciDeprivation = 1; ciCvd = 2; ciDrive = 3; ciNone = 4;
  CvdMeasureName: array[0..1] of string = (
    'Admissions per km2 a year', 'Risk-factor ratio (against England, same age and sex)');

  // check group items
  liDistricts = 0; liLsoas = 1; liTowns = 2; liMotorways = 3; liTrunk = 4;
  liPrimary = 5; liRail = 6; liBary = 7; liGeo = 8; liCvdBary = 9;
  liIsochrones = 10; liHospitals = 11;

function Thousands(v: Double): string;
begin
  result := FormatFloat('#,##0', v);
end;

// FPC's Format has no '+' flag
function Signed(v: Double): string;
begin
  result := FormatFloat('+0.0;-0.0;0.0', v);
end;

// compass point of the bearing from (E0, N0) to (E1, N1)
function Compass(E0, N0, E1, N1: Double): string;
const
  Pts: array[0..15] of string = ('N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
                                 'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW');
var
  b: Double;
begin
  b := RadToDeg(ArcTan2(E1 - E0, N1 - N0));
  if b < 0 then b := b + 360;
  result := Pts[Round(b / 22.5) mod 16] + Format(' (%.0f deg)', [b]);
end;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  d: Integer;
  lab: string;
begin
  FMap := TKentMapView.Create(Self);
  FMap.Parent := pnlMap;
  FMap.Align := alClient;
  FMap.OnSelectLsoa := @LsoaSelected;
  FMap.OnViewChange := @ViewChanged;

  FAreas := AllAreas;
  if Application.HasOption('areas') then begin
    FAreas := [];
    lab := LowerCase(Application.GetOptionValue('areas'));
    for d := 0 to AreaCount - 1 do
      if Pos(LowerCase(Copy(AreaName[d], 1, 4)), lab) > 0 then Include(FAreas, d);
    if FAreas = [] then FAreas := AllAreas;
  end;
  for d := 0 to AreaCount - 1 do cgAreas.Checked[d] := d in FAreas;
  ApplyAreas;      // before anything that can reach ShowInfo, which needs FInc

  FBoxMode := -1;
  if Application.HasOption('colour') then
    rgColour.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('colour'), 0), 0, ciNone);
  if Application.HasOption('domain') then
    FDepDomain := EnsureRange(StrToIntDef(Application.GetOptionValue('domain'), 0), 0, DomainCount - 1);
  if Application.HasOption('cvd') then
    FCvdMeasure := EnsureRange(StrToIntDef(Application.GetOptionValue('cvd'), 0), 0, 1);
  FDriveDomain := DriveDomainCount - 1;
  if Application.HasOption('drive') then
    FDriveDomain := EnsureRange(StrToIntDef(Application.GetOptionValue('drive'), 0), 0, DriveDomainCount - 1);
  FMap.SetDriveDomain(FDriveDomain);
  if Application.HasOption('speeds') then
    FDriveScenario := EnsureRange(StrToIntDef(Application.GetOptionValue('speeds'), 0), 0, DriveScenarioCount - 1);
  rgSpeeds.ItemIndex := FDriveScenario;   // may fire rgSpeedsClick, which needs FInc: after ApplyAreas
  FMap.SetDriveScenario(FDriveScenario);
  for d := 0 to cgLayers.Items.Count - 1 do
    cgLayers.Checked[d] := d in [liDistricts, liTowns, liMotorways, liTrunk, liRail, liBary, liGeo, liCvdBary,
      liIsochrones, liHospitals];
  ApplyLayers;
  ApplyColouring;
  FillSources;
  ShowInfo;
  ViewChanged(nil);
  pcMain.ActivePage := tabMap;
  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then Application.OnException := @SnapshotException;
end;

// the chosen areas: their masks, centres (combined, and each area's own
// when more than one is chosen) and the map's grey-out
procedure TForm1.ApplyAreas;
var
  a: Integer;
  c: TKentCentres;
  m, dm: TBoolArray;
  several: Boolean;
begin
  FInc := AreaLsoaMask(FAreas);
  FDistInc := AreaDistrictMask(FAreas);
  PopulationBarycentre(FInc, FBaryE, FBaryN);
  GeographicCentre(FDistInc, FGeoE, FGeoN);
  CvdBarycentre(FInc, FCvdE, FCvdN);
  FMap.SetBarycentre(FBaryE, FBaryN);
  FMap.SetGeoCentre(FGeoE, FGeoN);
  FMap.SetCvdBarycentre(FCvdE, FCvdN);
  several := (FAreas <> []) and (FAreas <> [0]) and (FAreas <> [1]) and (FAreas <> [2]);
  for a := 0 to AreaCount - 1 do begin
    c.BE := NaN;
    if several and (a in FAreas) then begin
      m := AreaLsoaMask([a]);
      dm := AreaDistrictMask([a]);
      PopulationBarycentre(m, c.BE, c.BN);
      CvdBarycentre(m, c.CE, c.CN);
      GeographicCentre(dm, c.GE, c.GN);
    end;
    FMap.SetAreaCentre(a, c);
  end;
  if (FMap.Selected >= 0) and not FInc[FMap.Selected] then FMap.Selected := -1;
  FMap.SetAreas(FAreas);
  lblTitle.Caption := AreaSetName(FAreas)
    + IfThen(FAreas = AllAreas, ' (NHS Kent and Medway ICB area)', '');
end;

procedure TForm1.cgAreasItemClick(Sender: TObject; Index: integer);
var
  a: Integer;
  S: TAreaSet;
begin
  S := [];
  for a := 0 to AreaCount - 1 do
    if cgAreas.Checked[a] then Include(S, a);
  if S = [] then begin                        // keep at least one
    cgAreas.Checked[Index] := True;
    Exit;
  end;
  FAreas := S;
  ApplyAreas;
  pbLegend.Invalidate;
  ShowInfo;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if FShown then Exit;
  FShown := True;
  if FSnapshot <> '' then Application.QueueAsyncCall(@RunSnapshot, 0);
end;

// the combo box lists the deprivation measures or the two admissions
// measures, whichever fill is chosen; each keeps its own selection
procedure TForm1.FillMeasureBox;
var
  m, d: Integer;
begin
  if rgColour.ItemIndex in [ciCvd, ciDrive] then m := rgColour.ItemIndex else m := ciDeprivation;
  if m = FBoxMode then Exit;
  FBoxMode := m;
  cbDomain.Items.BeginUpdate;
  try
    cbDomain.Items.Clear;
    if m = ciCvd then
      for d := 0 to High(CvdMeasureName) do cbDomain.Items.Add(CvdMeasureName[d])
    else if m = ciDrive then
      for d := 0 to DriveDomainCount - 1 do cbDomain.Items.Add(DriveDomainName(d))
    else
      for d := 0 to DomainCount - 1 do cbDomain.Items.Add(DomainName[d]);
  finally
    cbDomain.Items.EndUpdate;
  end;
  if m = ciCvd then begin
    cbDomain.ItemIndex := FCvdMeasure;
    lblDomain.Caption := 'Admissions measure:';
  end else if m = ciDrive then begin
    cbDomain.ItemIndex := FDriveDomain;
    lblDomain.Caption := 'Drive time to (also sets the isochrones):';
  end else begin
    cbDomain.ItemIndex := FDepDomain;
    lblDomain.Caption := 'Deprivation measure (index or domain):';
  end;
end;

procedure TForm1.ApplyColouring;
begin
  FillMeasureBox;
  cbDomain.Enabled := rgColour.ItemIndex in [ciDeprivation, ciCvd, ciDrive];
  lblDomain.Enabled := cbDomain.Enabled;
  case rgColour.ItemIndex of
    ciDensity: FMap.SetColouring(kcmDensity, FDepDomain);
    ciDeprivation: FMap.SetColouring(kcmDeprivation, FDepDomain);
    ciCvd: FMap.SetColouring(kcmCvd, FCvdMeasure);
    ciDrive: FMap.SetColouring(kcmDrive, FDriveDomain);
  else
    FMap.SetColouring(kcmNone, FDepDomain);
  end;
  pbLegend.Invalidate;
  ShowInfo;
end;

procedure TForm1.ApplyLayers;
begin
  FMap.ShowDistricts := cgLayers.Checked[liDistricts];
  FMap.ShowLsoaLines := cgLayers.Checked[liLsoas];
  FMap.ShowTowns := cgLayers.Checked[liTowns];
  FMap.ShowMotorways := cgLayers.Checked[liMotorways];
  FMap.ShowTrunk := cgLayers.Checked[liTrunk];
  FMap.ShowPrimary := cgLayers.Checked[liPrimary];
  FMap.ShowRail := cgLayers.Checked[liRail];
  FMap.ShowBarycentre := cgLayers.Checked[liBary];
  FMap.ShowGeoCentre := cgLayers.Checked[liGeo];
  FMap.ShowCvdBarycentre := cgLayers.Checked[liCvdBary];
  FMap.ShowIsochrones := cgLayers.Checked[liIsochrones];
  FMap.ShowHospitals := cgLayers.Checked[liHospitals];
  pbLegend.Invalidate;
end;

procedure TForm1.rgColourClick(Sender: TObject);
begin
  ApplyColouring;
end;

procedure TForm1.rgSpeedsClick(Sender: TObject);
begin
  if (rgSpeeds.ItemIndex < 0) or (FInc = nil) then Exit;
  FDriveScenario := rgSpeeds.ItemIndex;
  FMap.SetDriveScenario(FDriveScenario);
  pbLegend.Invalidate;
  ShowInfo;
end;

procedure TForm1.cbDomainChange(Sender: TObject);
begin
  if cbDomain.ItemIndex < 0 then Exit;
  if FBoxMode = ciCvd then FCvdMeasure := cbDomain.ItemIndex
  else if FBoxMode = ciDrive then begin
    FDriveDomain := cbDomain.ItemIndex;
    FMap.SetDriveDomain(FDriveDomain);
  end else FDepDomain := cbDomain.ItemIndex;
  ApplyColouring;
end;

procedure TForm1.cgLayersItemClick(Sender: TObject; Index: integer);
begin
  ApplyLayers;
end;

procedure TForm1.btnResetClick(Sender: TObject);
begin
  FMap.ResetView;
end;

procedure TForm1.btnSaveClick(Sender: TObject);
begin
  dlgSave.FileName := 'kent_map.png';
  if not dlgSave.Execute then Exit;
  if FMap.SaveToPNG(dlgSave.FileName) then
    lblStatus.Caption := 'Map saved to ' + dlgSave.FileName
  else
    lblStatus.Caption := 'Could not save the map';
end;

procedure TForm1.LsoaSelected(Sender: TObject; Lsoa: Integer);
begin
  ShowInfo;
end;

procedure TForm1.ViewChanged(Sender: TObject);
begin
  lblStatus.Caption := Format('Zoom %.1fx - wheel to zoom, drag to pan, click an area for its figures. '
    + 'Population: ONS %s estimates; deprivation: English Indices of Deprivation 2025; '
    + 'admissions: a model (see the memo and Sources).',
    [FMap.Zoom, PopulationYear]);
end;

// share of the area's residents living in LSOAs of national decile Decile
function TForm1.DecileShare(Domain, Decile: Integer): Double;
var
  i: Integer;
  s, t: Int64;
begin
  s := 0; t := 0;
  for i := 0 to LsoaCount - 1 do
    if FInc[i] then begin
      t := t + LsoaPop[i];
      if LsoaDecileOf(i, Domain) = Decile then s := s + LsoaPop[i];
    end;
  result := 100 * s / Max(t, 1);
end;

procedure TForm1.ShowInfo;
var
  L: TStringList;
  i, d, t, dom: Integer;
  la, lo, dist, km, dE, dN: Double;
  Pop, Low: array of Int64;
  Land, ScoreSum: array of Double;
  KccE, KccN: Double;
  Inc: array of Boolean;
  tp: Int64;
  tl: Double;
  nl: Integer;
begin
  dom := FDepDomain;
  L := TStringList.Create;
  try
    i := FMap.Selected;
    if i >= 0 then begin
      L.Add('SELECTED AREA: ' + LsoaName[i] + '  (' + LsoaCode[i] + ')');
      L.Add('  district           ' + DistrictName[LsoaDistrict[i]]);
      if LsoaBUA[i] <> '' then
        L.Add('  built-up area      ' + LsoaBUA[i]);
      L.Add(Format('  population         %s (%s)', [Thousands(LsoaPop[i]), PopulationYear]));
      L.Add(Format('  land area          %.3f km2', [LsoaLandKm2[i]]));
      L.Add(Format('  density            %s people per km2', [Thousands(LsoaDensity(i))]));
      L.Add('  Indices of Deprivation 2025      score    rank of 33,755   decile');
      for d := 0 to DomainCount - 1 do
        L.Add(Format('    %-32s %7.3f  %8s        %2d%s',
          [DomainName[d], LsoaScoreOf(i, d), Thousands(LsoaRankOf(i, d)), LsoaDecileOf(i, d),
           IfThen(LsoaDecileOf(i, d) = 1, '  most deprived 10 %',
             IfThen(LsoaDecileOf(i, d) = 10, '  least deprived 10 %', ''))]));
      L.Add(Format('  Expected heart attack and stroke admissions: %.1f a year (%.2f per km2);',
        [LsoaCvdEvents(i), LsoaCvdDensity(i)]));
      L.Add(Format('    from age and sex alone %.1f, so a risk-factor ratio of %.2f (England 1)',
        [LsoaCvdAgeOnly(i), LsoaCvdRatio(i)]));
      L.Add('    estimated risk factor            % of 18+    effect on admissions');
      for d := 0 to CvdComponentCount - 1 do
        if d < CvdPrevCount then
          L.Add(Format('      %-28s %7.1f      %7s %%',
            [CvdComponentName[d], LsoaCvdPrevalence(i, d), Signed(100 * (LsoaCvdEffect(i, d) - 1))]))
        else
          L.Add(Format('      %-28s %7s      %7s %%',
            [CvdComponentName[d], '', Signed(100 * (LsoaCvdEffect(i, d) - 1))]));
      L.Add(Format('    (smoking and obesity from surveys; the rest diagnosed prevalence - %.0f %% of residents''',
        [100 * CvdPracticeCoverage[i]]));
      L.Add('    GP patients are at practices with QOF data.');
      L.Add(Format('    South Asian %.1f %%, Black %.1f %% of residents, Census 2021. MSOA: %s.)',
        [100 * LsoaSouthAsian[i], 100 * LsoaBlack[i], MsoaName[LsoaMsoa[i]]]));
      if MsoaObservedSAR[LsoaMsoa[i]] > 0 then
        L.Add(Format('    MSOA ratio: model %.2f, observed %.2f (OHID, MI and stroke admissions 2016/17-20/21)',
          [MsoaModelSAR(LsoaMsoa[i]), MsoaObservedSAR[LsoaMsoa[i]]]));
      L.Add('  Drive time (modelled), minutes            free-flow car   morning peak   blue light');
      for d := 0 to HospitalCount - 1 do
        L.Add(Format('    %-38s %12.1f %14.1f %12.1f', [Copy(HospitalName[d], 1, 38),
          LsoaDriveMinutes(i, d, 0), LsoaDriveMinutes(i, d, 1), LsoaDriveMinutes(i, d, 2)]));
      L.Add('');
    end else
      L.Add('Click an area on the map for its population, deprivation and expected heart attack and stroke admissions.' + LineEnding);

    tp := 0; tl := 0; nl := 0;
    for i := 0 to LsoaCount - 1 do
      if FInc[i] then begin
        tp := tp + LsoaPop[i]; tl := tl + LsoaLandKm2[i]; nl := nl + 1;   // the local Inc hides System.Inc
      end;
    L.Add(UpperCase(AreaSetName(FAreas))
      + IfThen(FAreas = AllAreas, ' (NHS Kent and Medway ICB area)', ''));
    L.Add(Format('  population %s (%s), land %s km2, %s people per km2, %d LSOAs',
      [Thousands(tp), PopulationYear, Thousands(tl), Thousands(tp / tl), nl]));
    L.Add('');
    AreaTable(L);
    BNGToWGS84(FBaryE, FBaryN, la, lo);
    L.Add('');
    L.Add('  Population barycentre  ' + GridRef(FBaryE, FBaryN) + '  ' + LatLonText(la, lo));
    t := NearestTown(FBaryE, FBaryN, km);
    i := LsoaAt(FBaryE, FBaryN);
    if i < 0 then i := NearestLsoa(FBaryE, FBaryN);
    L.Add(Format('    in %s (%s), %.1f km from %s', [LsoaName[i], DistrictName[LsoaDistrict[i]], km, TownName[t]]));
    BNGToWGS84(FGeoE, FGeoN, la, lo);
    L.Add('  Geographic centre      ' + GridRef(FGeoE, FGeoN) + '  ' + LatLonText(la, lo));
    i := LsoaAt(FGeoE, FGeoN);
    if i < 0 then i := NearestLsoa(FGeoE, FGeoN);
    L.Add(Format('    in %s (%s)', [LsoaName[i], DistrictName[LsoaDistrict[i]]]));
    dE := FBaryE - FGeoE;
    dN := FBaryN - FGeoN;
    dist := Hypot(dE, dN) / 1000;
    L.Add(Format('  The barycentre is %.1f km %s of the geographic centre:',
      [dist, Compass(FGeoE, FGeoN, FBaryE, FBaryN)]));
    if FAreas = AllAreas then begin
      L.Add('  drawn towards the Medway towns and the Thames-side and Maidstone populations.');
      SetLength(Inc, LsoaCount);
      for i := 0 to LsoaCount - 1 do Inc[i] := DistrictName[LsoaDistrict[i]] <> 'Medway';
      PopulationBarycentre(Inc, KccE, KccN);
      L.Add('  Kent County Council area alone (without Medway): ' + GridRef(KccE, KccN)
        + Format(', %.1f km %s of the combined one', [Hypot(KccE - FBaryE, KccN - FBaryN) / 1000,
          Compass(FBaryE, FBaryN, KccE, KccN)]));
    end;

    // by district
    SetLength(Pop, DistrictCount);
    SetLength(Low, DistrictCount);
    SetLength(Land, DistrictCount);
    SetLength(ScoreSum, DistrictCount);
    for d := 0 to DistrictCount - 1 do begin
      Pop[d] := 0; Low[d] := 0; Land[d] := 0; ScoreSum[d] := 0;
    end;
    for i := 0 to LsoaCount - 1 do begin
      if not FInc[i] then Continue;
      d := LsoaDistrict[i];
      Pop[d] := Pop[d] + LsoaPop[i];
      Land[d] := Land[d] + LsoaLandKm2[i];
      ScoreSum[d] := ScoreSum[d] + LsoaPop[i] * LsoaScoreOf(i, dom);
      if LsoaDecileOf(i, dom) <= 2 then Low[d] := Low[d] + LsoaPop[i];
    end;
    L.Add('');
    L.Add('BY DISTRICT - deprivation measure: ' + DomainName[dom]);
    L.Add('  district                 population   land km2   per km2   mean score*   in deciles 1-2');
    for d := 0 to DistrictCount - 1 do
      if FDistInc[d] then
      L.Add(Format('  %-23s %11s %10.1f %9s %13.2f %12.1f %%',
        [DistrictName[d], Thousands(Pop[d]), Land[d], Thousands(Pop[d] / Land[d]),
         ScoreSum[d] / Pop[d], 100 * Low[d] / Pop[d]]));
    L.Add('  * population-weighted mean of the LSOA scores; deciles 1-2 = the most deprived');
    L.Add('    20 % of LSOAs in England.');
    L.Add('');
    CvdSummary(L);
    L.Add('');
    DriveSummary(L);
    L.Add('');
    L.Add(Format('TOWNS (ONS built-up areas over %s, %s population)', [Thousands(TownMinPopulation), PopulationYear]));
    for t := 0 to TownCount - 1 do begin
      i := LsoaAt(TownE[t], TownN[t]);
      if i < 0 then i := NearestLsoa(TownE[t], TownN[t]);
      if FInc[i] then
        L.Add(Format('  %-24s %9s  %s', [TownName[t], Thousands(TownPop[t]), AreaName[LsoaArea(i)]]));
    end;
    memInfo.Lines.Text := L.Text;
  finally
    L.Free;
  end;
end;

// North, East and West Kent separately, the chosen combination and Kent
// and Medway: population, age, deprivation, expected admissions and the
// three centres of each
procedure TForm1.AreaTable(L: TStrings);
type
  TRow = record
    Name: string;
    Pop, Old, Land, Score, Ev, Ag, BE, BN, CE, CN, GE, GN: Double;
  end;
var
  Rows: array of TRow;
  tot: Double;

  procedure AddRow(const AName: string; S: TAreaSet);
  var
    r: TRow;
    m, dm: TBoolArray;
    i, b: Integer;
  begin
    r.Name := AName;
    r.Pop := 0; r.Old := 0; r.Land := 0; r.Score := 0; r.Ev := 0; r.Ag := 0;
    m := AreaLsoaMask(S);
    dm := AreaDistrictMask(S);
    for i := 0 to LsoaCount - 1 do
      if m[i] then begin
        r.Pop := r.Pop + LsoaPop[i];
        r.Land := r.Land + LsoaLandKm2[i];
        r.Score := r.Score + LsoaPop[i] * LsoaScoreOf(i, 0);
        r.Ev := r.Ev + LsoaCvdEvents(i);
        r.Ag := r.Ag + LsoaCvdAgeOnly(i);
        for b := 0 to 2 * CvdBandCount - 1 do
          if b mod CvdBandCount >= 13 then          // 65-69 and over
            r.Old := r.Old + LsoaAgePop[i * 2 * CvdBandCount + b];
      end;
    PopulationBarycentre(m, r.BE, r.BN);
    CvdBarycentre(m, r.CE, r.CN);
    GeographicCentre(dm, r.GE, r.GN);
    SetLength(Rows, Length(Rows) + 1);
    Rows[High(Rows)] := r;
  end;

var
  a, k: Integer;
  mark: string;
begin
  for a := 0 to AreaCount - 1 do AddRow(AreaName[a], [a]);
  if (FAreas <> AllAreas) and (AreaSetName(FAreas) <> AreaName[0])
    and (AreaSetName(FAreas) <> AreaName[1]) and (AreaSetName(FAreas) <> AreaName[2]) then
    AddRow(AreaSetName(FAreas), FAreas);
  AddRow('Kent and Medway', AllAreas);
  tot := Rows[High(Rows)].Pop;
  L.Add('BY AREA (whole districts: see the Sources tab)        * = chosen');
  L.Add('                                                                 IMD   admissions a year');
  L.Add('  area                        population  share  per km2  65+ %  score*   expected  ratio');
  for k := 0 to High(Rows) do
    with Rows[k] do begin
      mark := ' ';
      if (k < AreaCount) and (k in FAreas) then mark := '*';
      L.Add(Format('  %-26s%s %10s %5.1f %% %8s %6.1f %7.2f %10.0f %6.2f',
        [Name, mark, Thousands(Pop), 100 * Pop / tot, Thousands(Pop / Land), 100 * Old / Pop,
         Score / Pop, Ev, Ev / Ag]));
    end;
  L.Add('  * population-weighted mean IMD 2025 score; ratio = expected admissions against England''s');
  L.Add('    rates for the same ages and sexes.');
  L.Add('');
  L.Add('  centres                     population barycentre   admissions barycentre   geographic centre');
  for k := 0 to High(Rows) do
    with Rows[k] do
      L.Add(Format('  %-27s %-23s %-23s %s', [Name, GridRef(BE, BN), GridRef(CE, CN), GridRef(GE, GN)]));
end;

// the admissions model, for the chosen areas and by district
procedure TForm1.CvdSummary(L: TStrings);
var
  i, d, n: Integer;
  ev, ag, rm, ri, ok, mk, la, lo, w, wE, wN, tl: Double;
  Ev_, Ag_, Land, Smk, Obe, Ad: array of Double;
  b: Integer;
begin
  ev := 0; ag := 0; tl := 0;
  for i := 0 to LsoaCount - 1 do begin
    if not FInc[i] then Continue;
    tl := tl + LsoaLandKm2[i];
    ev := ev + LsoaCvdEvents(i);
    ag := ag + LsoaCvdAgeOnly(i);
  end;
  L.Add('EXPECTED HEART ATTACK AND STROKE ADMISSIONS (a model - see Sources and the glossary)');
  L.Add(Format('  %s emergency admissions a year for acute MI or stroke; %s from age and sex alone',
    [Thousands(ev), Thousands(ag)]));
  L.Add(Format('  at England''s %s rates (HES), a risk-factor ratio of %.3f; %.2f per km2 a year.',
    [CvdHesYear, ev / ag, ev / tl]));
  L.Add('  Risk factors: smoking (APS by deprivation decile, age and sex, scaled to each district),');
  L.Add('  obesity (Active Lives ' + CvdObesityPeriod + ', the same way; BMI 30+ beyond the diabetes and');
  L.Add('  hypertension it causes), diagnosed diabetes, hypertension, CKD 3-5 and AF (QOF ' + CvdQofYear + ',');
  L.Add('  fitted by age and deprivation across England''s practices and shared out to LSOAs),');
  L.Add('  ethnicity (Census 2021)');
  L.Add(Format('  and residual deprivation. Relative risks: smoking %.1f, obesity %.1f, diabetes %.1f, hypertension %.1f,',
    [CvdRRSmoking, CvdRRObesity, CvdRRFactor[0], CvdRRFactor[1]]));
  L.Add(Format('  CKD %.1f, AF %.1f, South Asian %.2f, Black %.2f, deprivation %.1f (decile 1 against 10) - assumed.',
    [CvdRRFactor[2], CvdRRFactor[3], CvdRRSouthAsian, CvdRRBlack, CvdRRDeprivation]));
  CvdMsoaCheck(rm, ri, n, ok, mk);
  L.Add(Format('  Check against OHID''s observed MSOA admission ratios (MI and stroke, 2016/17-20/21, all %d', [n]));
  L.Add('  of Kent and Medway''s MSOAs, whatever areas are chosen):');
  L.Add(Format('    correlation %.2f (the IMD score alone: %.2f). Observed Kent ratio %.2f against the model''s %.2f:',
    [rm, ri, ok, mk]));
  L.Add('    Kent''s admissions run below what its risk factors predict - the model ranks areas better than');
  L.Add('    it sets the level, and the observed period is older.');
  BNGToWGS84(FCvdE, FCvdN, la, lo);
  L.Add('');
  L.Add('  Heart attack and stroke barycentre  ' + GridRef(FCvdE, FCvdN) + '  ' + LatLonText(la, lo));
  i := LsoaAt(FCvdE, FCvdN);
  if i < 0 then i := NearestLsoa(FCvdE, FCvdN);
  L.Add(Format('    in %s (%s): the expected admissions'' weighted mean position,', [LsoaName[i], DistrictName[LsoaDistrict[i]]]));
  L.Add(Format('    %.1f km %s of the population barycentre.',
    [Hypot(FCvdE - FBaryE, FCvdN - FBaryN) / 1000, Compass(FBaryE, FBaryN, FCvdE, FCvdN)]));
  // weighted by the age-sex expectation alone, to separate age from the risk factors
  w := 0; wE := 0; wN := 0;
  for i := 0 to LsoaCount - 1 do begin
    if not FInc[i] then Continue;
    w := w + LsoaCvdAgeOnly(i);
    wE := wE + LsoaCvdAgeOnly(i) * LsoaLabelE[i];
    wN := wN + LsoaCvdAgeOnly(i) * LsoaLabelN[i];
  end;
  wE := wE / w; wN := wN / w;
  L.Add(Format('    Age and sex alone move it %.1f km %s (the older east and coast);',
    [Hypot(wE - FBaryE, wN - FBaryN) / 1000, Compass(FBaryE, FBaryN, wE, wN)]));
  L.Add(Format('    the risk factors a further %.1f km %s.',
    [Hypot(FCvdE - wE, FCvdN - wN) / 1000, Compass(wE, wN, FCvdE, FCvdN)]));

  CorridorSummary(L, ev);

  SetLength(Ev_, DistrictCount); SetLength(Ag_, DistrictCount); SetLength(Land, DistrictCount);
  SetLength(Smk, DistrictCount); SetLength(Obe, DistrictCount); SetLength(Ad, DistrictCount);
  for d := 0 to DistrictCount - 1 do begin
    Ev_[d] := 0; Ag_[d] := 0; Land[d] := 0; Smk[d] := 0; Obe[d] := 0; Ad[d] := 0;
  end;
  for i := 0 to LsoaCount - 1 do begin
    if not FInc[i] then Continue;
    d := LsoaDistrict[i];
    Ev_[d] := Ev_[d] + LsoaCvdEvents(i);
    Ag_[d] := Ag_[d] + LsoaCvdAgeOnly(i);
    Land[d] := Land[d] + LsoaLandKm2[i];
    for b := 0 to 2 * CvdBandCount - 1 do begin
      Smk[d] := Smk[d] + LsoaAgePop[i * 2 * CvdBandCount + b] * Min(1, CvdSmokeLsoa[i] * CvdSmokeBand[b]);
      Obe[d] := Obe[d] + LsoaAgePop[i * 2 * CvdBandCount + b] * Min(1, CvdObesityLsoa[i] * CvdObesityBand[b]);
      Ad[d] := Ad[d] + LsoaAgePop[i * 2 * CvdBandCount + b] * EnsureRange((5 * (b mod CvdBandCount) + 5 - 18) / 5, 0, 1);
    end;
  end;
  L.Add('');
  L.Add('                                                          smoking           obesity');
  L.Add('  district                admissions/yr   per km2   ratio   model   APS     model   ALS');
  for d := 0 to DistrictCount - 1 do
    if FDistInc[d] then
    L.Add(Format('  %-23s %12.0f %9.2f %7.2f %6.1f %6.1f %7.1f %6.1f',
      [DistrictName[d], Ev_[d], Ev_[d] / Land[d], Ev_[d] / Ag_[d], 100 * Smk[d] / Ad[d],
       100 * DistrictSmokeAPS[d], 100 * Obe[d] / Ad[d], 100 * DistrictObesitySurvey[d]]));
  L.Add('  ratio = against England''s rates for the same ages and sexes. Smoking and obesity are % of');
  L.Add('  adults; APS is the Annual Population Survey ' + CvdSmokePeriod + ', ALS Active Lives ' + CvdObesityPeriod + '.');
  L.Add('  Their district samples are small, so the model only leans towards them.');
end;

// expected admissions by road corridor: north of the A2/M2, between it
// and the M20, south of the M20 (uKentData's LsoaCorridor)
procedure TForm1.CorridorSummary(L: TStrings; Total: Double);
var
  i, c, a: Integer;
  Ev_, Ag_, Pop: array[0..CorridorCount - 1] of Double;
  ByArea: array[0..CorridorCount - 1, 0..AreaCount - 1] of Double;
  pt, aE0, aE1, mE0, mE1, eastA2, eastM20: Double;
  hdr, row: string;
begin
  pt := 0; eastA2 := 0; eastM20 := 0;
  A2M2Extent(aE0, aE1); M20Extent(mE0, mE1);
  for c := 0 to CorridorCount - 1 do begin
    Ev_[c] := 0; Ag_[c] := 0; Pop[c] := 0;
    for a := 0 to AreaCount - 1 do ByArea[c, a] := 0;
  end;
  for i := 0 to LsoaCount - 1 do begin
    if not FInc[i] then Continue;
    c := LsoaCorridor(i);
    Ev_[c] := Ev_[c] + LsoaCvdEvents(i);
    Ag_[c] := Ag_[c] + LsoaCvdAgeOnly(i);
    Pop[c] := Pop[c] + LsoaPop[i];
    pt := pt + LsoaPop[i];
    ByArea[c, LsoaArea(i)] := ByArea[c, LsoaArea(i)] + LsoaCvdEvents(i);
    if (c = 0) and (LsoaLabelE[i] > aE1) and (LsoaLabelN[i] < A2M2Northing(aE1) + 17000) then
      eastA2 := eastA2 + LsoaCvdEvents(i);          // Deal, Walmer, Sandwich - not Thanet
    if (c < 2) and (LsoaLabelE[i] > mE1) then
      eastM20 := eastM20 + LsoaCvdEvents(i);
  end;
  L.Add('');
  L.Add('  By road corridor (each LSOA by its label point):');
  hdr := '  corridor                admissions/yr   share  population  ratio';
  for a := 0 to AreaCount - 1 do
    if a in FAreas then hdr := hdr + Format('  %11s', [Copy(AreaName[a], 1, Pos(' ', AreaName[a]) - 1)]);
  L.Add(hdr);
  for c := 0 to CorridorCount - 1 do begin
    row := Format('  %-23s %12.0f %6.1f%% %10.1f%% %6.2f',
      [CorridorName[c], Ev_[c], 100 * Ev_[c] / Total, 100 * Pop[c] / pt, IfThen(Ag_[c] > 0, Ev_[c] / Max(Ag_[c], 1e-12), 0)]);
    for a := 0 to AreaCount - 1 do
      if a in FAreas then row := row + Format('  %11.0f', [ByArea[c, a]]);
    L.Add(row);
  end;
  L.Add('  A2/M2 = the trunk route: A2 from Dartford, M2 from Strood to Brenley Corner, A2 through');
  L.Add('  Canterbury to Dover (not the old A2 through the Medway towns). Each road is held level');
  L.Add('  past its ends, so Thanet, Deal and Sandwich count as north of the A2, and Dover, Deal');
  L.Add(Format('  and Thanet as north of the M20. Deal and Sandwich alone are %.0f a year (%.1f %%);', [eastA2, 100 * eastA2 / Total]));
  L.Add(Format('  everything east of the M20''s end north of it, %.0f (%.1f %%).', [eastM20, 100 * eastM20 / Total]));
end;

// a domain's name within 42 characters
function DriveDomainLabel(d: Integer): string;
begin
  if d < HospitalCount then result := HospitalName[d] else result := DriveDomainName(d);
  result := StringReplace(result, 'Queen Elizabeth the Queen Mother', 'QEQM', []);
  result := StringReplace(result, 'Kent and Canterbury', 'K&C', []);
  result := StringReplace(result, 'Nearest of all seven acute hospitals', 'Nearest of all seven', []);
  result := Copy(result, 1, 42);
end;

// drive times weighted by expected admissions: every choice side by side,
// then the chosen one by district
procedure TForm1.DriveSummary(L: TStrings);
const
  Lim: array[0..3] of Integer = (15, 30, 45, 60);
var
  i, dm, d, k: Integer;
  W, Wt, Sum, p90: Double;
  Within: array[0..3] of Double;
  Idx: array of Integer;
  T: array of Double;
  DEv, DT: array of Double;

  procedure SortByTime;                         // shell sort of Idx by T
  var
    gap, a, b, tmp: Integer;
  begin
    gap := Length(Idx) div 2;
    while gap > 0 do begin
      for a := gap to High(Idx) do begin
        tmp := Idx[a]; b := a;
        while (b >= gap) and (T[Idx[b - gap]] > T[tmp]) do begin
          Idx[b] := Idx[b - gap]; Dec(b, gap);
        end;
        Idx[b] := tmp;
      end;
      gap := gap div 2;
    end;
  end;

begin
  SetLength(T, LsoaCount);
  L.Add('DRIVE TIMES TO HOSPITAL, weighted by expected heart attack and stroke admissions');
  L.Add('  Speeds: ' + UpperCase(DriveScenarioName[FDriveScenario])
    + ' (choose under Drive speeds; OpenStreetMap roads - see Sources)');
  L.Add('  to                                          mean   90 % within   <=15    <=30    <=45    >60 min');
  for dm := 0 to DriveDomainCount - 1 do begin
    SetLength(Idx, 0);
    W := 0; Sum := 0;
    for k := 0 to 3 do Within[k] := 0;
    for i := 0 to LsoaCount - 1 do begin
      if not FInc[i] then Continue;
      T[i] := LsoaDriveMinutes(i, dm, FDriveScenario);
      Wt := LsoaCvdEvents(i);
      W := W + Wt; Sum := Sum + Wt * T[i];
      for k := 0 to 3 do if T[i] <= Lim[k] then Within[k] := Within[k] + Wt;
      SetLength(Idx, Length(Idx) + 1); Idx[High(Idx)] := i;
    end;
    SortByTime;
    Wt := 0; p90 := 0;
    for k := 0 to High(Idx) do begin
      Wt := Wt + LsoaCvdEvents(Idx[k]);
      if Wt >= 0.9 * W then begin p90 := T[Idx[k]]; Break; end;
    end;
    L.Add(Format('  %s %-42s %5.1f %8.1f %9.1f%% %6.1f%% %6.1f%% %6.1f%%',
      [IfThen(dm = FDriveDomain, '>', ' '), DriveDomainLabel(dm), Sum / W, p90,
       100 * Within[0] / W, 100 * Within[1] / W, 100 * Within[2] / W, 100 * (W - Within[3]) / W]));
  end;
  L.Add('  > the choice on the map. By district, mean minutes for the chosen areas:');
  SetLength(DEv, DistrictCount); SetLength(DT, DistrictCount);
  for i := 0 to LsoaCount - 1 do begin
    if not FInc[i] then Continue;
    d := LsoaDistrict[i];
    DEv[d] := DEv[d] + LsoaCvdEvents(i);
    DT[d] := DT[d] + LsoaCvdEvents(i) * LsoaDriveMinutes(i, FDriveDomain, FDriveScenario);
  end;
  for d := 0 to DistrictCount - 1 do
    if FDistInc[d] and (DEv[d] > 0) then
      L.Add(Format('    %-23s %6.0f admissions/yr   %5.1f min to %s',
        [DistrictName[d], DEv[d], DT[d] / DEv[d], DriveDomainShort(FDriveDomain)]));
  L.Add('');
  WhhKchSummary(L);
end;

// admissions-weighted quantile P of minutes T over the LSOAs with Use[i]
function WeightedQuantile(const T: array of Double; const Use: array of Boolean; P: Double): Double;
var
  Idx: array of Integer;
  i, n, gap, a, b, tmp: Integer;
  W, c: Double;
begin
  SetLength(Idx, LsoaCount);
  n := 0; W := 0;
  for i := 0 to LsoaCount - 1 do
    if Use[i] then begin Idx[n] := i; Inc(n); W := W + LsoaCvdEvents(i); end;
  SetLength(Idx, n);
  gap := n div 2;                               // shell sort by T
  while gap > 0 do begin
    for a := gap to n - 1 do begin
      tmp := Idx[a]; b := a;
      while (b >= gap) and (T[Idx[b - gap]] > T[tmp]) do begin
        Idx[b] := Idx[b - gap]; Dec(b, gap);
      end;
      Idx[b] := tmp;
    end;
    gap := gap div 2;
  end;
  c := 0; result := NaN;
  for a := 0 to n - 1 do begin
    c := c + LsoaCvdEvents(Idx[a]);
    if c >= P * W then Exit(T[Idx[a]]);
  end;
end;

// one centre for the whole of Kent and Medway, whatever areas are chosen:
// William Harvey (Ashford) against Kent and Canterbury
procedure TForm1.WhhKchSummary(L: TStrings);
const
  Hosp: array[0..1] of Integer = (DriveHospWHH, DriveHospKCH);
var
  i, h, d, a, k, n: Integer;
  T: array[0..1] of array of Double;
  All: array of Boolean;
  W, Ev, Sum, Mx, Q30, Q45, Q60: Double;
  DEv: array of Double;
  DT: array[0..1] of array of Double;
  AEv: array[0..AreaCount - 1] of Double;
  AT, AOver: array[0..1, 0..AreaCount - 1] of Double;
  Order: array of Integer;
  Diff: array of Double;
  NearerWHH: Double;
  TS: array of Double;
  sc: Integer;
begin
  SetLength(All, LsoaCount);
  for h := 0 to 1 do begin
    SetLength(T[h], LsoaCount);
    SetLength(DT[h], DistrictCount);
  end;
  SetLength(DEv, DistrictCount);
  for a := 0 to AreaCount - 1 do begin
    AEv[a] := 0;
    for h := 0 to 1 do begin AT[h, a] := 0; AOver[h, a] := 0; end;
  end;
  W := 0; NearerWHH := 0;
  for i := 0 to LsoaCount - 1 do begin
    All[i] := True;
    Ev := LsoaCvdEvents(i);
    W := W + Ev;
    d := LsoaDistrict[i]; a := LsoaArea(i);
    DEv[d] := DEv[d] + Ev; AEv[a] := AEv[a] + Ev;
    for h := 0 to 1 do begin
      T[h][i] := LsoaDriveMinutes(i, Hosp[h], FDriveScenario);
      DT[h][d] := DT[h][d] + Ev * T[h][i];
      AT[h, a] := AT[h, a] + Ev * T[h][i];
      if T[h][i] > 60 then AOver[h, a] := AOver[h, a] + Ev;
    end;
    if T[0][i] < T[1][i] then NearerWHH := NearerWHH + Ev;
  end;

  L.Add('ONE CENTRE FOR THE WHOLE OF KENT AND MEDWAY: WILLIAM HARVEY (ASHFORD) OR KENT AND CANTERBURY');
  L.Add(Format('  All %s expected admissions a year, whatever areas are chosen, in each speed scenario.', [Thousands(W)]));
  L.Add('                                mean  median  90 % within   <=30    <=45    <=60    >60    longest  hours/yr');
  SetLength(TS, LsoaCount);
  for sc := 0 to DriveScenarioCount - 1 do begin
    L.Add('  ' + DriveScenarioName[sc] + IfThen(sc = FDriveScenario, '  (chosen: the tables below)', ''));
    for h := 0 to 1 do begin
      Sum := 0; Mx := 0; Q30 := 0; Q45 := 0; Q60 := 0;
      for i := 0 to LsoaCount - 1 do begin
        TS[i] := LsoaDriveMinutes(i, Hosp[h], sc);
        Ev := LsoaCvdEvents(i);
        Sum := Sum + Ev * TS[i];
        Mx := Max(Mx, TS[i]);
        if TS[i] <= 30 then Q30 := Q30 + Ev;
        if TS[i] <= 45 then Q45 := Q45 + Ev;
        if TS[i] <= 60 then Q60 := Q60 + Ev;
      end;
      L.Add(Format('    %-26s %5.1f  %6.1f  %9.1f %8.1f%% %6.1f%% %6.1f%% %5.1f%% %8.1f %9.0f',
        [HospitalShort[Hosp[h]], Sum / W, WeightedQuantile(TS, All, 0.5), WeightedQuantile(TS, All, 0.9),
         100 * Q30 / W, 100 * Q45 / W, 100 * Q60 / W, 100 * (W - Q60) / W, Mx, Sum / 60]));
    end;
  end;
  L.Add(Format('  %s: %.0f %% of admissions are quicker to William Harvey, %.0f %% to Kent and Canterbury.',
    [DriveScenarioName[FDriveScenario], 100 * NearerWHH / W, 100 * (W - NearerWHH) / W]));
  L.Add('');
  L.Add('  area           admissions/yr   to WHH   to K&C    over 60 min: WHH   K&C');
  for a := 0 to AreaCount - 1 do
    L.Add(Format('  %-14s %12.0f %8.1f %8.1f %16.1f%% %5.1f%%',
      [AreaName[a], AEv[a], AT[0, a] / AEv[a], AT[1, a] / AEv[a],
       100 * AOver[0, a] / AEv[a], 100 * AOver[1, a] / AEv[a]]));
  L.Add('');
  // districts, largest William Harvey advantage first
  n := 0;
  SetLength(Order, DistrictCount); SetLength(Diff, DistrictCount);
  for d := 0 to DistrictCount - 1 do
    if DEv[d] > 0 then begin
      Diff[d] := (DT[1][d] - DT[0][d]) / DEv[d];
      k := n;
      while (k > 0) and (Diff[Order[k - 1]] < Diff[d]) do begin Order[k] := Order[k - 1]; Dec(k); end;
      Order[k] := d; Inc(n);
    end;
  L.Add('  district                admissions/yr   to WHH   to K&C   K&C - WHH  (mean minutes)');
  for k := 0 to n - 1 do begin
    d := Order[k];
    L.Add(Format('  %-23s %10.0f %9.1f %8.1f %10s',
      [DistrictName[d], DEv[d], DT[0][d] / DEv[d], DT[1][d] / DEv[d], Signed(Diff[d])]));
  end;
  L.Add('  West Kent decides it: the M20 puts Maidstone, Tonbridge, Sevenoaks and Tunbridge Wells');
  L.Add('  12-14 minutes nearer Ashford, outweighing Thanet and Canterbury''s 20 minutes the other way.');
  L.Add('  In practice West and North Kent use their own hospitals. Area and district tables: '
    + DriveScenarioName[FDriveScenario] + '.');
end;

procedure TForm1.pbLegendPaint(Sender: TObject);
const
  BarX = 10;
  BarW = 24;
var
  cv: TCanvas;
  y, y0, h, i, dec, dom: Integer;
  v, t: Double;
  lab: string;
const
  Ticks: array[0..6] of Double = (10, 30, 100, 300, 1000, 3000, 10000);
  CvdTicks: array[0..6] of Double = (0.03, 0.1, 0.3, 1, 3, 10, 30);
  RatioTicks: array[0..6] of Double = (0.6, 0.7, 0.85, 1, 1.2, 1.4, 1.7);

  procedure KeyLine(yy: Integer; AColour: TColor; W: Integer; const Txt: string; Dashed: Boolean);
  begin
    cv.Pen.Style := psSolid;
    cv.Pen.Color := AColour;
    cv.Pen.Width := W;
    cv.Line(BarX, yy, BarX + 34, yy);
    if Dashed then begin
      cv.Pen.Color := clWhite;
      cv.Pen.Width := 1;
      cv.Line(BarX + 3, yy, BarX + 10, yy);
      cv.Line(BarX + 17, yy, BarX + 24, yy);
    end;
    cv.Pen.Width := 1;
    cv.TextOut(BarX + 42, yy - cv.TextHeight(Txt) div 2, Txt);
  end;

begin
  cv := pbLegend.Canvas;
  cv.Brush.Color := clForm;
  cv.FillRect(0, 0, pbLegend.Width, pbLegend.Height);
  cv.Font.Color := clWindowText;
  cv.Brush.Style := bsClear;
  y0 := 22;
  case rgColour.ItemIndex of
    0: begin
      cv.TextOut(BarX, 2, 'People per km2 (' + PopulationYear + ', log scale)');
      h := 108;
      for y := 0 to h - 1 do begin
        t := 1 - y / (h - 1);
        v := Power(10, Log10(DensityLo) + t * (Log10(DensityHi) - Log10(DensityLo)));
        cv.Pen.Color := DensityColour(v);
        cv.Line(BarX, y0 + y, BarX + BarW, y0 + y);
      end;
      cv.Pen.Color := clBlack;
      cv.Rectangle(BarX, y0, BarX + BarW, y0 + h);
      for i := 0 to High(Ticks) do begin
        y := y0 + Round((Log10(DensityHi) - Log10(Ticks[i])) / (Log10(DensityHi) - Log10(DensityLo)) * (h - 1));
        cv.Line(BarX + BarW, y, BarX + BarW + 5, y);
        lab := Thousands(Ticks[i]);
        cv.TextOut(BarX + BarW + 8, y - cv.TextHeight(lab) div 2, lab);
      end;
      y0 := y0 + h + 14;
    end;
    1: begin
      dom := FDepDomain;
      cv.TextOut(BarX, 2, 'National decile (IoD 2025) - % of residents');
      h := 17;
      for dec := 1 to 10 do begin
        y := y0 + (dec - 1) * h;
        cv.Brush.Style := bsSolid;
        cv.Brush.Color := DecileColour(dec);
        cv.Pen.Color := clBlack;
        cv.Rectangle(BarX, y, BarX + BarW, y + h - 3);
        cv.Brush.Style := bsClear;
        lab := Format('%2d  %5.1f %%', [dec, DecileShare(dom, dec)]);
        if dec = 1 then lab := lab + '   most deprived'
        else if dec = 10 then lab := lab + '   least deprived';
        cv.TextOut(BarX + BarW + 8, y + (h - 3 - cv.TextHeight(lab)) div 2, lab);
      end;
      y0 := y0 + 10 * h + 10;
    end;
    2: begin
      h := 108;
      if FCvdMeasure = 0 then begin
        cv.TextOut(BarX, 2, 'Expected MI + stroke admissions per km2 a year');
        for y := 0 to h - 1 do begin
          t := 1 - y / (h - 1);
          v := Power(10, Log10(CvdDensityLo) + t * (Log10(CvdDensityHi) - Log10(CvdDensityLo)));
          cv.Pen.Color := CvdDensityColour(v);
          cv.Line(BarX, y0 + y, BarX + BarW, y0 + y);
        end;
        cv.Pen.Color := clBlack;
        cv.Rectangle(BarX, y0, BarX + BarW, y0 + h);
        for i := 0 to High(CvdTicks) do begin
          y := y0 + Round((Log10(CvdDensityHi) - Log10(CvdTicks[i])) / (Log10(CvdDensityHi) - Log10(CvdDensityLo)) * (h - 1));
          cv.Line(BarX + BarW, y, BarX + BarW + 5, y);
          lab := FloatToStr(CvdTicks[i]);
          cv.TextOut(BarX + BarW + 8, y - cv.TextHeight(lab) div 2, lab);
        end;
      end else begin
        cv.TextOut(BarX, 2, 'Risk-factor ratio (1 = England, same age and sex)');
        for y := 0 to h - 1 do begin
          t := 1 - y / (h - 1);
          v := Power(CvdRatioSpan, 2 * t - 1);
          cv.Pen.Color := CvdRatioColour(v);
          cv.Line(BarX, y0 + y, BarX + BarW, y0 + y);
        end;
        cv.Pen.Color := clBlack;
        cv.Rectangle(BarX, y0, BarX + BarW, y0 + h);
        for i := 0 to High(RatioTicks) do begin
          y := y0 + Round((1 - (Ln(RatioTicks[i]) / Ln(CvdRatioSpan) + 1) / 2) * (h - 1));
          cv.Line(BarX + BarW, y, BarX + BarW + 5, y);
          lab := FormatFloat('0.0#', RatioTicks[i]);
          if RatioTicks[i] = 1 then lab := lab + '  England';
          cv.TextOut(BarX + BarW + 8, y - cv.TextHeight(lab) div 2, lab);
        end;
      end;
      y0 := y0 + h + 14;
    end;
    ciDrive: begin
      cv.TextOut(BarX, 2, 'Minutes, ' + DriveScenarioName[FDriveScenario] + ' - share of admissions');
      h := 15;
      for dec := 0 to DriveBandCount - 1 do begin
        y := y0 + dec * h;
        cv.Brush.Style := bsSolid;
        cv.Brush.Color := DriveBandColour(dec);
        cv.Pen.Color := clBlack;
        cv.Rectangle(BarX, y, BarX + BarW, y + h - 3);
        cv.Brush.Style := bsClear;
        v := 0; t := 0;
        for i := 0 to LsoaCount - 1 do
          if FInc[i] then begin
            t := t + LsoaCvdEvents(i);
            if Min(Trunc(LsoaDriveMinutes(i, FDriveDomain, FDriveScenario) / DriveBandMinutes), DriveBandCount - 1) = dec then
              v := v + LsoaCvdEvents(i);
          end;
        if dec < DriveBandCount - 1 then
          lab := Format('%2d-%2d  %5.1f %%', [dec * DriveBandMinutes, (dec + 1) * DriveBandMinutes, 100 * v / t])
        else
          lab := Format('%2d+    %5.1f %%', [dec * DriveBandMinutes, 100 * v / t]);
        cv.TextOut(BarX + BarW + 8, y + (h - 3 - cv.TextHeight(lab)) div 2, lab);
      end;
      y0 := y0 + DriveBandCount * h + 10;
    end;
  else
    begin
      cv.TextOut(BarX, 2, 'No fill');
      y0 := 26;
    end;
  end;
  // line and marker key
  if cgLayers.Checked[liMotorways] then begin KeyLine(y0, clMotorway, 3, 'motorway', False); Inc(y0, 15); end;
  if cgLayers.Checked[liTrunk] then begin KeyLine(y0, clTrunk, 3, 'trunk road (primary route)', False); Inc(y0, 15); end;
  if cgLayers.Checked[liPrimary] then begin KeyLine(y0, clPrimary, 2, 'primary A road', False); Inc(y0, 15); end;
  if cgLayers.Checked[liRail] then begin KeyLine(y0, clRail, 4, 'railway', True); Inc(y0, 15); end;
  cv.Pen.Width := 1;
  if cgLayers.Checked[liTowns] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clWhite; cv.Pen.Color := clBlack;
    cv.Ellipse(BarX + 13, y0 - 4, BarX + 21, y0 + 4);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, Format('town over %s', [Thousands(TownMinPopulation)]));
    Inc(y0, 15);
  end;
  if cgLayers.Checked[liBary] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clBary; cv.Pen.Color := clBlack;
    cv.Ellipse(BarX + 10, y0 - 7, BarX + 24, y0 + 7);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'population barycentre');
    Inc(y0, 15);
  end;
  if cgLayers.Checked[liCvdBary] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clCvdBary; cv.Pen.Color := clBlack;
    cv.Ellipse(BarX + 10, y0 - 7, BarX + 24, y0 + 7);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'heart attack and stroke barycentre');
    Inc(y0, 15);
  end;
  if cgLayers.Checked[liGeo] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := TColor($1A1A1A); cv.Pen.Color := clBlack;
    cv.Polygon([Point(BarX + 17, y0 - 6), Point(BarX + 23, y0), Point(BarX + 17, y0 + 6), Point(BarX + 11, y0)]);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'geographic centre');
    Inc(y0, 15);
  end;
  if cgLayers.Checked[liIsochrones] then begin
    KeyLine(y0, clIsochrone, 3, 'isochrones to ' + DriveDomainShort(FDriveDomain) + ': 15, 30, 45, 60 min', False);
    Inc(y0, 15);
  end;
  if cgLayers.Checked[liHospitals] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clHospital; cv.Pen.Color := clWhite;
    cv.Rectangle(BarX + 10, y0 - 7, BarX + 24, y0 + 7);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'acute hospital (chosen: larger)');
    Inc(y0, 15);
  end;
  if not ((FAreas = AllAreas) or (FAreas = [0]) or (FAreas = [1]) or (FAreas = [2]))
    and (cgLayers.Checked[liBary] or cgLayers.Checked[liCvdBary] or cgLayers.Checked[liGeo]) then
    cv.TextOut(BarX, y0 - cv.TextHeight('T') div 2, 'small markers: each chosen area''s own centres');
  cv.Brush.Style := bsSolid;
end;

procedure TForm1.FillSources;
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('INFORMATION SOURCES');
    L.Add('');
    L.Add('Everything on the map is compiled into the program from the datasets below '
      + '(make_kent_data.py builds kentdata.inc from them), so it runs offline. The area is '
      + 'the NHS Kent and Medway Integrated Care Board: the 12 Kent County Council districts '
      + 'plus Medway, 1,107 LSOAs.');
    L.Add('');
    for i := 0 to High(Sources) do
      with Sources[i] do begin
        L.Add(Format('%d. %s', [i + 1, Title]));
        L.Add('     Publisher:  ' + Publisher);
        L.Add('     Edition:    ' + Edition);
        L.Add('     Licence:    ' + Licence);
        L.Add('     Link:       ' + URL);
        L.Add('     Used for:   ' + Use);
        L.Add('');
      end;
    L.Add('Coordinate conversion: British National Grid to WGS84 latitude/longitude by the '
      + 'Ordnance Survey''s published transverse Mercator and Helmert formulae '
      + '("A guide to coordinate systems in Great Britain"), accurate to a few metres.');
    L.Add('');
    L.Add('Contains public sector information licensed under the Open Government Licence v3.0. '
      + 'Contains OS data (c) Crown copyright and database right. Map data (c) OpenStreetMap '
      + 'contributors, ODbL.');
    L.Add('');
    L.Add('');
    L.Add('GLOSSARY OF TERMS');
    L.Add('');
    for i := 0 to High(Glossary) do begin
      L.Add(Glossary[i].Term);
      L.Add('     ' + Glossary[i].Meaning);
      L.Add('');
    end;
    memSources.Lines.Text := L.Text;
    memSources.SelStart := 0;
  finally
    L.Free;
  end;
end;

procedure TForm1.SnapshotException(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, 'error: ', E.ClassName, ': ', E.Message);
  Halt(2);
end;

procedure TForm1.RunSnapshot(Data: PtrInt);

  procedure Save(const Suffix: string);
  var
    F: string;
  begin
    Application.ProcessMessages;
    F := FSnapshot + '_' + Suffix + '.png';
    if FMap.SaveToPNG(F) then WriteLn('saved ', F)
    else begin
      WriteLn(StdErr, 'could not save ', F);
      ExitCode := 1;
    end;
  end;

var
  i: Integer;
begin
  Application.ProcessMessages;
  rgColour.ItemIndex := ciDensity; ApplyColouring; Save('density');
  FDepDomain := 0; rgColour.ItemIndex := ciDeprivation; ApplyColouring; Save('imd');
  FDepDomain := 4; FBoxMode := -1; ApplyColouring; Save('health');
  FCvdMeasure := 0; rgColour.ItemIndex := ciCvd; ApplyColouring; Save('cvd');
  FCvdMeasure := 1; FBoxMode := -1; ApplyColouring; Save('cvdratio');
  FCvdMeasure := 0; FBoxMode := -1; ApplyColouring;
  rgColour.ItemIndex := ciDrive; ApplyColouring; Save('drive');
  FDriveDomain := HospitalCount; FMap.SetDriveDomain(FDriveDomain); FBoxMode := -1; ApplyColouring; Save('drive_whh_kch');
  i := FDriveScenario;
  rgSpeeds.ItemIndex := 1; rgSpeedsClick(nil); Save('drive_whh_kch_peak');
  rgSpeeds.ItemIndex := 2; rgSpeedsClick(nil); Save('drive_whh_kch_blue');
  rgSpeeds.ItemIndex := i; rgSpeedsClick(nil);
  FDriveDomain := DriveDomainCount - 1; FMap.SetDriveDomain(FDriveDomain); FBoxMode := -1;
  rgColour.ItemIndex := ciCvd; ApplyColouring;
  // zoom on the barycentre, with its LSOA selected
  FMap.SetView(FBaryE, FBaryN, 6);
  i := LsoaAt(FBaryE, FBaryN);
  FMap.Selected := i;
  ShowInfo;
  Save('zoom');
  Application.ProcessMessages;
  with GetFormImage do
    try
      SaveToFile(FSnapshot + '_window.bmp');
    finally
      Free;
    end;
  WriteLn(memInfo.Lines.Text);
  Application.Terminate;
end;

end.
