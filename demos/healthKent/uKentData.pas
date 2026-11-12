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

     EXPECTED HEART ATTACK AND STROKE ADMISSIONS (cvddata.inc, from
     make_cvd_data.py, whose header has the method). For LSOA i:
       events_i = sum over 36 age-sex bands b of pop_ib * I_b * M_ib
     I_b is England's 2024-25 emergency admission rate for acute MI
     (I21-I22) or stroke (I61-I64) at that age and sex (HES), and
       M_ib = exp( sum over components k of ln m_kib )
     with, for smoking, obesity and the four QOF registers,
       m = (1 + p (RR - 1)) / (1 + pbar (RR - 1)),
     p the LSOA's estimated prevalence in that band and pbar England's;
     for ethnicity the same over the South Asian and Black shares; for
     residual deprivation RR^((5.5 - decile)/9) over its England mean.
     So an LSOA of England-average risk factors has M = 1 and gets the
     age-sex expectation. The relative risks are the CvdRR... constants
     below - round, literature-typical values, editable. Every
     multiplier divides by England's average for that age and sex, which
     is what the HES baseline already contains.
     Computed once with newVM: the (N, 36) population matrix times the
     elementwise exponential of the summed log multipliers (the Hadamard
     '*'), then MatMult with the (36, 1) rate column. A component's effect
     is events with it over events without it: the same product with its
     log multiplier subtracted.
     The factors are combined as if independent within an LSOA (diabetes,
     hypertension, obesity and smoking cluster in reality), and hyper-
     tension, diabetes, CKD and AF are diagnosed (QOF) prevalence.

     POPULATION BARYCENTRE: the population-weighted mean of the LSOA
     label points, sum(p_i x_i) / sum(p_i), computed with newVM: the
     populations as a (1, N) TVMobj times the (N, 2) [E N] matrix,
     divided by the population times a column of ones. With ~1,750 people
     per LSOA the label points stand in well for the people; ONS's own
     population-weighted LSOA centroids aren't on its open service. It is
     the point that minimises the population's summed squared distance -
     the mean, not the median, centre. The heart attack and stroke
     barycentre is the same with each LSOA weighted by its expected
     admissions instead of its residents: where the events would
     balance. The geographic centre is the area
     centroid of the districts' land (shoelace formula over every ring).

     SUB-AREAS: North, East and West Kent, by whole district, following
     the acute trusts' catchments (Darent Valley and Medway Maritime,
     East Kent Hospitals, Maidstone and Tunbridge Wells):
       North  Dartford, Gravesham, Medway, Swale
       East   Ashford, Canterbury, Dover, Folkestone and Hythe, Thanet
       West   Maidstone, Sevenoaks, Tonbridge and Malling, Tunbridge Wells
     All three together are Kent and Medway. The NHS's own four Health and
     Care Partnerships split differently (Swanley, in Sevenoaks, goes with
     Dartford and Gravesham; Swale with Medway), and LSOA-level HCP
     membership isn't compiled in, so whole districts are used.

     ROAD CORRIDORS: each LSOA's label point is put north of the A2/M2
     (the trunk route: A2 from Dartford, M2 Strood - Brenley Corner, A2
     on through Canterbury to Dover docks; the old A2 through the Medway
     towns and Sittingbourne is a primary road and not used), south of
     the M20, or between. Each road is reduced to its northing against
     easting - the OSM points in 500 m easting bins, the median northing
     of each bin (merging carriageways and slips), linearly interpolated -
     and held level past its ends: so Thanet, Deal and Sandwich, east of
     the A2's end, count as north of it, and Dover as north of the M20.
     Both roads run west to east, and the A2/M2 lies north of the M20 at
     every easting, so the three bands don't overlap.

     DRIVE TIMES (drivedata.inc, make_drive_data.py): free-flow car
     minutes from each LSOA's label point to each of the seven acute
     hospitals, over OpenStreetMap's roads from motorways down to
     residential streets (one-way streets respected), in three speed
     scenarios: free-flow car, weekday morning peak (anchored on DfT's
     local 'A' road speeds) and blue light (1.25 x free-flow, capped);
     plus the nearer of William Harvey and Kent and Canterbury
     and the nearest of all seven. Isochrones at 15, 30, 45 and 60 minutes
     come from the same model on a 500 m grid. No traffic, junction
     delays beyond the peak factors, no turn costs; hospital positions
     are approximate.

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
{$I cvddata.inc}
{$I drivedata.inc}

const
  RouteMotorway = 0;
  RouteTrunk = 1;
  RoutePrimary = 2;
  RouteRail = 3;
  MostDeprivedDecile = 1;
  NationalLsoaCount = 33755;       // LSOAs ranked in IoD 2025

  // sub-areas (see the header)
  AreaCount = 3;
  AreaName: array[0..AreaCount - 1] of string = ('North Kent', 'East Kent', 'West Kent');
  AreaDistricts: array[0..AreaCount - 1] of string = (
    'Dartford|Gravesham|Medway|Swale',
    'Ashford|Canterbury|Dover|Folkestone and Hythe|Thanet',
    'Maidstone|Sevenoaks|Tonbridge and Malling|Tunbridge Wells');

type
  TAreaSet = set of 0..AreaCount - 1;
  TBoolArray = array of Boolean;

const
  AllAreas: TAreaSet = [0..AreaCount - 1];

type
  TSourceEntry = record
    Title, Publisher, Edition, Licence, URL, Use: string;
  end;
  TGlossaryEntry = record
    Term, Meaning: string;
  end;

const
  Sources: array[0..18] of TSourceEntry = (
    (Title: 'Lower layer Super Output Area population estimates (small area, 2021-based), mid-2024';
     Publisher: 'Office for National Statistics (via Nomis, dataset NM_2014_1)';
     Edition: 'mid-2024 estimates, released 7 November 2025 - the latest published';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://www.nomisweb.co.uk/datasets/pestsyoala';
     Use: 'Population of every LSOA (all ages, and by sex in five-year age bands, plus England''s by age and sex); population density, the barycentre, town populations and the expected heart attack and stroke admissions are all built from it.'),
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
     Use: 'Motorways, trunk roads (mostly primary routes), primary A roads and railways, simplified to 20 m.'),
    (Title: 'Hospital Admitted Patient Care Activity 2024-25: primary diagnosis, 3 character (CSV)';
     Publisher: 'NHS England (Hospital Episode Statistics)';
     Edition: '2024-25';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://digital.nhs.uk/data-and-information/publications/statistical/hospital-admitted-patient-care-activity/2024-25';
     Use: 'England''s emergency admissions for acute myocardial infarction (I21-I22) and stroke (I61-I64), split by age (episode age profile) and sex: the age-sex baseline rates of the expected admissions.'),
    (Title: 'Quality and Outcomes Framework 2024-25: prevalence (registers) by practice';
     Publisher: 'NHS England';
     Edition: '2024-25 (year to 31 March 2025)';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://digital.nhs.uk/data-and-information/publications/statistical/quality-and-outcomes-framework-achievement-prevalence-and-exceptions-data/2024-25';
     Use: 'Diagnosed diabetes (17+), hypertension, CKD stages 3-5 (18+) and atrial fibrillation for every practice in England: age curves and deprivation gradients fitted across all practices, and each practice''s excess or shortfall.'),
    (Title: 'Patients Registered at a GP Practice, April 2025: by LSOA (2021), and by five-year age and sex';
     Publisher: 'NHS England';
     Edition: 'April 2025';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://digital.nhs.uk/data-and-information/publications/statistical/patients-registered-at-a-gp-practice/april-2025';
     Use: 'Each practice''s list by age (for the QOF age curves) and where its patients live: a practice''s figures are shared out to LSOAs by its patients there.'),
    (Title: 'Smoking prevalence in adults (18+) - current smokers (APS), indicator 92443';
     Publisher: 'Office for Health Improvement and Disparities, Fingertips (Local Tobacco Control Profiles), from the ONS Annual Population Survey';
     Edition: '2023-25 pooled (district values and England by LSOA IMD 2025 decile); 2025 age and sex gradients';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://fingertips.phe.org.uk/profile/tobacco-control';
     Use: 'Smoking by national deprivation decile, age and sex, scaled to each district''s survey figure (shrunk towards the decile model, since district samples are small).'),
    (Title: 'Obesity prevalence in adults (18+), using adjusted self-reported height and weight, indicator 93881';
     Publisher: 'Office for Health Improvement and Disparities, Fingertips (Obesity, physical activity and nutrition), from Sport England''s Active Lives Adult Survey';
     Edition: '2024/25 (district values; England by LSOA 2011 IMD 2019 decile, age and sex)';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://fingertips.phe.org.uk/profile/obesity-physical-activity-nutrition';
     Use: 'Obesity (BMI 30+) by national deprivation decile, age and sex, scaled towards each district''s survey figure, as for smoking. The deciles are IMD 2019''s, applied to IMD 2025 deciles.'),
    (Title: 'Census 2021 TS021 - Ethnic group';
     Publisher: 'Office for National Statistics (via Nomis, dataset NM_2041_1)';
     Edition: 'Census 2021';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://www.nomisweb.co.uk/sources/census_2021';
     Use: 'Share of residents of South Asian (Indian, Pakistani, Bangladeshi) and Black ethnicity in each LSOA and England.'),
    (Title: 'Local Health: emergency hospital admissions for myocardial infarction (93232) and for stroke (93231), MSOA';
     Publisher: 'Office for Health Improvement and Disparities, Fingertips (Local Health), from HES and ONS';
     Edition: '2016/17 - 2020/21 pooled, MSOA 2011';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://fingertips.phe.org.uk/profile/local-health';
     Use: 'Observed indirectly age-standardised admission ratios for each MSOA - the check of the model''s ratios (not an input).'),
    (Title: 'OA (2021) to LSOA to MSOA to LAD (2023) lookup, and MSOA (2011) to MSOA (2021) lookup';
     Publisher: 'Office for National Statistics, Open Geography Portal';
     Edition: '2023 / 2022';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://geoportal.statistics.gov.uk (services OA21_LAD23_LSOA21_MSOA21_LEP23_EN_LU, MSOA11_MSOA21_LAD22_EW_LU_v2)';
     Use: 'Which MSOA each LSOA lies in, to compare the model with the observed MSOA ratios.'),
    (Title: 'OpenStreetMap - drivable roads, highway=motorway .. residential (with links and living streets)';
     Publisher: 'OpenStreetMap contributors, via the Overpass API';
     Edition: 'snapshot of ' + DriveOsmTimestamp;
     Licence: 'Open Database Licence (ODbL) 1.0 - (c) OpenStreetMap contributors';
     URL: 'https://www.openstreetmap.org/copyright';
     Use: 'Drive times to the seven acute hospitals and the isochrones (make_drive_data.py): fastest routes at '
       + 'assumed free-flow car speeds - motorway 105 km/h, dual trunk 80, single trunk 72, primary 65, '
       + 'secondary 55, tertiary 48, unclassified 40, residential 28 - capped by tagged speed limits, '
       + 'one-way streets respected, joining the network at 20 km/h. Hospital positions approximate. '
       + 'Peak and blue-light scenarios: see the next two sources.'),
    (Title: 'Travel time measures for local ''A'' roads, Great Britain: April 2025 to March 2026';
     Publisher: 'Department for Transport';
     Edition: 'year ending March 2026';
     Licence: 'Open Government Licence v3.0';
     URL: 'https://www.gov.uk/government/statistics/travel-time-measures-for-the-strategic-road-network-england-and-local-a-roads-great-britain-april-2025-to-march-2026';
     Use: 'Anchors the weekday-morning-peak scenario: average speeds on local A roads of 17.6 mph urban and 34.4 mph '
       + 'rural (all day), 23.3 mph in the weekday morning peak against 24.6 all day. The model''s A and B road '
       + 'speeds are scaled (x0.61 urban, x0.88 rural) to match; motorway, trunk and minor-road factors are assumed.'),
    (Title: 'Blue-light driving: Rehn et al., Emerg Med J 2017;34:819-24 (London), and the Green Beacon pilot, Rural Remote Health 2020;20:6114';
     Publisher: 'BMJ; Rural and Remote Health';
     Edition: '2017, 2020';
     Licence: 'cited figures only';
     URL: 'https://www.rrh.org.au/journal/article/6114';
     Use: 'Anchors the blue-light scenario: 46 km/h on blue lights against 20 km/h driving normally in London, and 1.26x '
       + 'normal driving on rural roads. Modelled as 1.25x the free-flow speed, at most 113 km/h on motorways and dual '
       + 'carriageways and 100 km/h elsewhere, traffic ignored.')
  );

  Glossary: array[0..19] of TGlossaryEntry = (
    (Term: 'LSOA'; Meaning: 'Lower layer Super Output Area: a Census 2021 statistical area of about 1,000-3,000 residents (400-1,200 households). Kent and Medway has 1,107.'),
    (Term: 'Mid-year population estimate'; Meaning: 'ONS estimate of the usual resident population on 30 June, rolled forward from the 2021 Census with births, deaths and migration.'),
    (Term: 'Population density'; Meaning: 'Mid-2024 population divided by the LSOA''s land area (ONS Standard Area Measurements), people per km2.'),
    (Term: 'IMD'; Meaning: 'Index of Multiple Deprivation 2025: a weighted combination of seven domains - income 22.5 %, employment 22.5 %, education 13.5 %, health 13.5 %, crime 9.3 %, barriers to housing and services 9.3 %, living environment 9.3 %.'),
    (Term: 'Decile'; Meaning: 'National tenth of the 33,755 LSOAs in England ranked by score: decile 1 is the most deprived 10 %, decile 10 the least deprived. Deciles are relative - decile 10 is the least deprived, not necessarily wealthy.'),
    (Term: 'Built-up area (BUA)'; Meaning: 'ONS 2022 definition of a town or city from land use (built-up land at 25 m resolution); Medway''s towns are separate BUAs (Gillingham, Chatham, Rochester).'),
    (Term: 'Population barycentre'; Meaning: 'Population-weighted mean position of the residents - where a rigid map with each person as an equal weight would balance. It minimises the summed squared distance to everyone.'),
    (Term: 'Heart attack and stroke barycentre'; Meaning: 'The population barycentre with each LSOA weighted by its expected heart attack and stroke admissions instead of its residents: the mean position of the events. Its offset from the population barycentre shows which way risk leans - mostly towards older areas, then towards areas with more risk factors.'),
    (Term: 'Geographic centre'; Meaning: 'Area centroid of the land: where the map would balance if every square kilometre weighed the same.'),
    (Term: 'British National Grid'; Meaning: 'The OS transverse Mercator grid (OSGB36): eastings and northings in metres; a grid reference such as TQ 87979 58078 names the 100 km square and the position inside it.'),
    (Term: 'ICB'; Meaning: 'Integrated Care Board: the NHS body planning health services for an area - here NHS Kent and Medway, covering the 12 Kent districts and Medway.'),
    (Term: 'Expected heart attack and stroke admissions'; Meaning: 'Modelled emergency hospital admissions a year for acute myocardial infarction (ICD-10 I21-I22) or stroke (I61-I64): the LSOA''s residents by age and sex times England''s 2024-25 rates, times a multiplier for its estimated smoking, diabetes, hypertension, CKD, atrial fibrillation, ethnicity and residual deprivation against England''s. Admissions, not people: one person can be admitted twice. Per km2, it maps where the events would be; it is an estimate, not a count.'),
    (Term: 'Risk-factor ratio'; Meaning: 'Expected admissions over those from age and sex alone at England''s rates: 1.25 means 25 % more than an English population of the same age and sex. It is the model''s counterpart of an indirectly standardised admission ratio.'),
    (Term: 'Relative risk (RR)'; Meaning: 'How many times more likely an admission is with a risk factor than without, other things equal. The model''s values (smoking 2.0, obesity 1.2 - beyond the diabetes and hypertension it causes, which are counted separately -, diabetes 2.0, hypertension 1.6, CKD 1.4, AF 1.5, South Asian 1.4, Black 0.75, most against least deprived decile 1.3) are round, assumed values typical of the literature, not measured here.'),
    (Term: 'QOF register'; Meaning: 'The Quality and Outcomes Framework''s count of a practice''s patients with a recorded diagnosis (e.g. diabetes, 17+). It counts diagnosed cases only: undiagnosed diabetes and hypertension are missed.'),
    (Term: 'Indirectly standardised ratio (SAR)'; Meaning: 'Observed events over those expected if England''s age-specific rates applied to the local population; 1 (or 100) = England.'),
    (Term: 'MSOA'; Meaning: 'Middle layer Super Output Area: about 5,000-15,000 residents, built from 4-6 LSOAs. Kent and Medway has 221 (2021).'),
    (Term: 'APS'; Meaning: 'The ONS Annual Population Survey, source of the official adult smoking prevalence. District samples are a few hundred people, so district figures carry wide confidence intervals.'),
    (Term: 'Drive time and isochrone'; Meaning: 'Modelled minutes to a hospital along the fastest OpenStreetMap route, in three scenarios: a car at free-flow speeds, a car in the weekday morning peak, and an ambulance on blue lights. An isochrone is the line joining places the same time away - here 15, 30, 45 and 60 minutes.'),
    (Term: 'Best single site'; Meaning: 'The point on the road network in Kent and Medway with the shortest mean drive time from every LSOA, weighted by expected heart attack and stroke admissions - where one centre for the whole county would minimise average travel. Found separately for each speed scenario by timing every LSOA to every road node (motorways and trunk roads themselves excluded). The green outlines enclose the sites within 2 and 5 minutes of that best mean. It ignores land, existing buildings and ambulance logistics.')
  );

const
  // relative risks of an emergency MI or stroke admission (assumed round
  // values typical of adjusted cohort estimates - edit to explore)
  CvdRRSmoking = 2.0;              // current smoker (Banks et al., BMC Med 2019)
  // obese (BMI 30+), over and above the diabetes and hypertension it causes,
  // which are counted separately. ERFC (Lancet 2011;377:1085): CVD HR per
  // SD of BMI 1.23 adjusted for age, sex and smoking, 1.07 also adjusted
  // for blood pressure, diabetes and cholesterol; obese against not is
  // about 1.75 SD, so 1.44 and 1.13. The model has diabetes and diagnosed
  // hypertension but not cholesterol or undiagnosed blood pressure: 1.2.
  CvdRRObesity = 1.2;
  CvdRRFactor: array[0..CvdFactorCount - 1] of Double = (
    2.0,                           // diabetes (ERFC, Lancet 2010: 2.0 for CHD)
    1.6,                           // diagnosed hypertension
    1.4,                           // CKD stages 3-5
    1.5);                          // atrial fibrillation (mainly stroke)
  CvdRRSouthAsian = 1.4;           // Indian, Pakistani, Bangladeshi (cf. QRISK3)
  CvdRRBlack = 0.75;               // Black African and Caribbean (cf. QRISK3)
  CvdRRDeprivation = 1.3;          // residual, most against least deprived decile

  // model components, for the breakdown: 0 smoking, 1 obesity, 2..5 the
  // QOF registers (CvdFactorName), 6 ethnicity, 7 residual deprivation.
  // The first CvdPrevCount have an estimated prevalence.
  CvdComponentCount = 8;
  CvdPrevCount = 6;
  CvdQofFirst = 2;
  CvdComponentName: array[0..CvdComponentCount - 1] of string = (
    'smoking', 'obesity (BMI 30+)', 'diabetes', 'hypertension', 'CKD 3-5',
    'atrial fibrillation', 'ethnicity', 'deprivation (residual)');

// expected emergency admissions for heart attack or stroke a year
function LsoaCvdEvents(i: Integer): Double;
// the same from age and sex alone (England's rates)
function LsoaCvdAgeOnly(i: Integer): Double;
// per km2 of land a year
function LsoaCvdDensity(i: Integer): Double;
// events / age-sex expectation: the risk-factor ratio, 1 = England
function LsoaCvdRatio(i: Integer): Double;
// events with component k over events without it
function LsoaCvdEffect(i, k: Integer): Double;
// estimated prevalence of component k (0 .. CvdPrevCount - 1), % of residents aged 18+
function LsoaCvdPrevalence(i, k: Integer): Double;
// MSOA k: model ratio (sum of events / sum of age-sex expectation)
function MsoaModelSAR(k: Integer): Double;
// Pearson r of model against observed MSOA ratios, and of the
// population-weighted IMD score against them, over MSOAs with data
procedure CvdMsoaCheck(out RModel, RImd: Double; out Count: Integer;
  out ObservedKent, ModelKent: Double);

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
// the same weighted by expected heart attack and stroke admissions
procedure CvdBarycentre(const Include: array of Boolean; out E, N: Double);
// geographic centre of the districts with IncDistrict[d] true ([] = all)
procedure GeographicCentre(const IncDistrict: array of Boolean; out E, N: Double);

// road corridors (see the header): 0 north of the A2/M2, 1 between
// it and the M20, 2 south of the M20
const
  CorridorCount = 3;
  CorridorName: array[0..CorridorCount - 1] of string = (
    'north of the A2/M2', 'between A2/M2 and M20', 'south of the M20');
function LsoaCorridor(i: Integer): Integer;
// the road's northing at easting E (held level past its ends)
function A2M2Northing(E: Double): Double;
function M20Northing(E: Double): Double;
// the road's easting extent
procedure A2M2Extent(out E0, E1: Double);
procedure M20Extent(out E0, E1: Double);

// drive times (see the header). Domains 0 .. HospitalCount - 1 are the
// hospitals, then the nearer of William Harvey and Kent and Canterbury
// (HospitalCount), the nearest of all (DriveNearestDomain), and the best
// single site for the scenario (DriveBestDomain, BestSiteE/N)
function DriveDomainName(d: Integer): string;
function DriveDomainShort(d: Integer): string;
// Scenario 0 free-flow car, 1 weekday morning peak, 2 blue light
function LsoaDriveMinutes(i, Domain: Integer; Scenario: Integer = 0): Double;
// for each domain, the hospital it means (-1 for the combined ones)
function DriveDomainHospital(d: Integer): Integer;
// is hospital h part of domain d
function DriveDomainHas(d, h: Integer): Boolean;

// sub-areas
function DistrictArea(d: Integer): Integer;                // 0 North, 1 East, 2 West
function LsoaArea(i: Integer): Integer;
function AreaSetName(S: TAreaSet): string;                 // 'Kent and Medway', 'North Kent + West Kent'
function AreaLsoaMask(S: TAreaSet): TBoolArray;            // per LSOA
function AreaDistrictMask(S: TAreaSet): TBoolArray;        // per district

procedure BNGToWGS84(E, N: Double; out Lat, Lon: Double);
function GridRef(E, N: Double): string;               // 'TQ 87979 58078'
function LatLonText(Lat, Lon: Double): string;        // '51.297N 0.678E'

implementation

var
  BoxE0, BoxE1, BoxN0, BoxN1: array[0..LsoaCount - 1] of Single;
  CvdEv, CvdAge: array[0..LsoaCount - 1] of Double;
  CvdEff: array[0..LsoaCount * CvdComponentCount - 1] of Double;
  CvdPrev: array[0..LsoaCount * CvdPrevCount - 1] of Double;
  CvdDone: Boolean = False;

procedure ComputeCvd; forward;

// computed on first use, not in initialization: MatMult needs CBLAS,
// which the program loads (InitializeCBLAS) after the units initialise
procedure NeedCvd; inline;
begin
  if not CvdDone then ComputeCvd;
end;

function LsoaCvdEvents(i: Integer): Double; begin NeedCvd; result := CvdEv[i]; end;
function LsoaCvdAgeOnly(i: Integer): Double; begin NeedCvd; result := CvdAge[i]; end;
function LsoaCvdRatio(i: Integer): Double; begin NeedCvd; result := CvdEv[i] / CvdAge[i]; end;
function LsoaCvdEffect(i, k: Integer): Double; begin NeedCvd; result := CvdEff[i * CvdComponentCount + k]; end;
function LsoaCvdPrevalence(i, k: Integer): Double; begin NeedCvd; result := CvdPrev[i * CvdPrevCount + k]; end;

function LsoaCvdDensity(i: Integer): Double;
begin
  NeedCvd;
  if LsoaLandKm2[i] > 0 then result := CvdEv[i] / LsoaLandKm2[i]
  else result := NaN;
end;

function MsoaModelSAR(k: Integer): Double;
var
  i: Integer;
  e, a: Double;
begin
  NeedCvd;
  e := 0; a := 0;
  for i := 0 to LsoaCount - 1 do
    if LsoaMsoa[i] = k then begin
      e := e + CvdEv[i];
      a := a + CvdAge[i];
    end;
  result := e / a;
end;

function Pearson(const X, Y: array of Double; n: Integer): Double;
var
  i: Integer;
  mx, my, sxy, sxx, syy: Double;
begin
  mx := 0; my := 0;
  for i := 0 to n - 1 do begin mx := mx + X[i]; my := my + Y[i]; end;
  mx := mx / n; my := my / n;
  sxy := 0; sxx := 0; syy := 0;
  for i := 0 to n - 1 do begin
    sxy := sxy + (X[i] - mx) * (Y[i] - my);
    sxx := sxx + Sqr(X[i] - mx);
    syy := syy + Sqr(Y[i] - my);
  end;
  result := sxy / Sqrt(sxx * syy);
end;

procedure CvdMsoaCheck(out RModel, RImd: Double; out Count: Integer;
  out ObservedKent, ModelKent: Double);
var
  i, k: Integer;
  Model, Imd, Obs: array of Double;
  ImdSum, PopSum, AgeSum, EvSum: array[0..MsoaCount - 1] of Double;
  oa, a: Double;
begin
  NeedCvd;
  for k := 0 to MsoaCount - 1 do begin
    ImdSum[k] := 0; PopSum[k] := 0; AgeSum[k] := 0; EvSum[k] := 0;
  end;
  for i := 0 to LsoaCount - 1 do begin
    k := LsoaMsoa[i];
    ImdSum[k] := ImdSum[k] + LsoaPop[i] * LsoaScoreOf(i, 0);
    PopSum[k] := PopSum[k] + LsoaPop[i];
    AgeSum[k] := AgeSum[k] + CvdAge[i];
    EvSum[k] := EvSum[k] + CvdEv[i];
  end;
  SetLength(Model, MsoaCount);
  SetLength(Imd, MsoaCount);
  SetLength(Obs, MsoaCount);
  Count := 0;
  oa := 0; a := 0;
  for k := 0 to MsoaCount - 1 do
    if MsoaObservedSAR[k] > 0 then begin
      Model[Count] := EvSum[k] / AgeSum[k];
      Imd[Count] := ImdSum[k] / PopSum[k];
      Obs[Count] := MsoaObservedSAR[k];
      oa := oa + MsoaObservedSAR[k] * AgeSum[k];
      a := a + AgeSum[k];
      Inc(Count);
    end;
  RModel := Pearson(Model, Obs, Count);
  RImd := Pearson(Imd, Obs, Count);
  ObservedKent := oa / a;
  oa := 0; a := 0;
  for i := 0 to LsoaCount - 1 do begin oa := oa + CvdEv[i]; a := a + CvdAge[i]; end;
  ModelKent := oa / a;
end;

procedure ComputeCvd;
const
  NB2 = 2 * CvdBandCount;
var
  Pop, Rate, LogM, Comp, Ev, Age, EvWithout: TVMobj;
  Comps: array[0..CvdComponentCount - 1] of TVMobj;
  i, b, f, k: Integer;
  p, pbar, adult, w, sa0, depMean, eth: Double;
  adultN: array[0..LsoaCount - 1] of Double;

  // fraction of age band b (5-year, within its sex) aged 18 or over
  function Adult18(b: Integer): Double;
  var
    lo: Integer;
  begin
    lo := 5 * (b mod CvdBandCount);
    result := EnsureRange((lo + 5 - 18) / 5, 0, 1);
  end;

begin
  Pop := TVMobj.Create(LsoaCount, NB2);
  Rate := TVMobj.Create(NB2, 1);
  for b := 0 to NB2 - 1 do Rate[b, 0] := CvdRateMI[b] + CvdRateStroke[b];
  for k := 0 to CvdComponentCount - 1 do Comps[k] := TVMobj.Create(LsoaCount, NB2);
  for i := 0 to LsoaCount * CvdPrevCount - 1 do CvdPrev[i] := 0;
  sa0 := 1 + CvdSouthAsianEngland * (CvdRRSouthAsian - 1) + CvdBlackEngland * (CvdRRBlack - 1);
  depMean := 0;
  for k := 1 to 10 do depMean := depMean + Power(CvdRRDeprivation, (5.5 - k) / 9) / 10;
  for i := 0 to LsoaCount - 1 do begin
    adultN[i] := 0;
    eth := Ln((1 + LsoaSouthAsian[i] * (CvdRRSouthAsian - 1) + LsoaBlack[i] * (CvdRRBlack - 1)) / sa0);
    w := Ln(Power(CvdRRDeprivation, (5.5 - LsoaDecileOf(i, 0)) / 9) / depMean);
    for b := 0 to NB2 - 1 do begin
      Pop[i, b] := LsoaAgePop[i * NB2 + b];
      adult := Adult18(b) * Pop[i, b];
      adultN[i] := adultN[i] + adult;
      // smoking
      p := Min(1, CvdSmokeLsoa[i] * CvdSmokeBand[b]);
      pbar := CvdSmokeEngland * CvdSmokeBand[b];
      Comps[0][i, b] := Ln((1 + p * (CvdRRSmoking - 1)) / (1 + pbar * (CvdRRSmoking - 1)));
      CvdPrev[i * CvdPrevCount] := CvdPrev[i * CvdPrevCount] + p * Pop[i, b];
      // obesity
      p := Min(1, CvdObesityLsoa[i] * CvdObesityBand[b]);
      pbar := CvdObesityEngland * CvdObesityBand[b];
      Comps[1][i, b] := Ln((1 + p * (CvdRRObesity - 1)) / (1 + pbar * (CvdRRObesity - 1)));
      CvdPrev[i * CvdPrevCount + 1] := CvdPrev[i * CvdPrevCount + 1] + p * Pop[i, b];
      // diagnosed conditions
      for f := 0 to CvdFactorCount - 1 do begin
        p := Min(1, CvdPrevRate[f * NB2 + b] * CvdPrevScale[i * CvdFactorCount + f]);
        pbar := CvdPrevEngland[f * NB2 + b];
        Comps[CvdQofFirst + f][i, b] := Ln((1 + p * (CvdRRFactor[f] - 1)) / (1 + pbar * (CvdRRFactor[f] - 1)));
        CvdPrev[i * CvdPrevCount + CvdQofFirst + f] := CvdPrev[i * CvdPrevCount + CvdQofFirst + f] + p * Pop[i, b];
      end;
      Comps[6][i, b] := eth;
      Comps[7][i, b] := w;
    end;
    for k := 0 to CvdPrevCount - 1 do
      CvdPrev[i * CvdPrevCount + k] := 100 * CvdPrev[i * CvdPrevCount + k] / adultN[i];
  end;

  LogM := Comps[0];
  for k := 1 to CvdComponentCount - 1 do LogM := LogM + Comps[k];
  Ev := MatMult(Pop * Exp(LogM), Rate);          // (N, 1)
  Age := MatMult(Pop, Rate);
  for i := 0 to LsoaCount - 1 do begin
    CvdEv[i] := Ev[i, 0];
    CvdAge[i] := Age[i, 0];
  end;
  for k := 0 to CvdComponentCount - 1 do begin
    Comp := LogM - Comps[k];
    EvWithout := MatMult(Pop * Exp(Comp), Rate);
    for i := 0 to LsoaCount - 1 do
      CvdEff[i * CvdComponentCount + k] := CvdEv[i] / EvWithout[i, 0];
  end;
  CvdDone := True;
end;

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

// weighted mean of the label points: the (1, N) weights times the (N, 2)
// [E N] matrix, over the weights times a column of ones
procedure WeightedBarycentre(const Wt: array of Double; const Include: array of Boolean;
  out E, N: Double);
var
  W, XY, Ones, Num, Den: TVMobj;
  i: Integer;
begin
  W := TVMobj.Create(1, LsoaCount);
  XY := TVMobj.Create(LsoaCount, 2);
  Ones := TVMobj.Create(LsoaCount, 1);
  for i := 0 to LsoaCount - 1 do begin
    if (Length(Include) = 0) or Include[i] then W[0, i] := Wt[i] else W[0, i] := 0;
    XY[i, 0] := LsoaLabelE[i];
    XY[i, 1] := LsoaLabelN[i];
    Ones[i, 0] := 1;
  end;
  Num := MatMult(W, XY);          // (1, 2): sum w E, sum w N
  Den := MatMult(W, Ones);        // (1, 1): sum w
  if Den[0, 0] > 0 then begin
    E := Num[0, 0] / Den[0, 0];
    N := Num[0, 1] / Den[0, 0];
  end else begin
    E := NaN;
    N := NaN;
  end;
end;

procedure PopulationBarycentre(const Include: array of Boolean; out E, N: Double);
var
  Wt: array of Double;
  i: Integer;
begin
  SetLength(Wt, LsoaCount);
  for i := 0 to LsoaCount - 1 do Wt[i] := LsoaPop[i];
  WeightedBarycentre(Wt, Include, E, N);
end;

procedure CvdBarycentre(const Include: array of Boolean; out E, N: Double);
begin
  NeedCvd;
  WeightedBarycentre(CvdEv, Include, E, N);
end;

type
  TRoadProfile = record
    E, N: array of Double;
  end;

var
  ProfA2M2, ProfM20: TRoadProfile;
  ProfDone: Boolean = False;
  LsoaCor: array[0..LsoaCount - 1] of Integer;

// northing against easting of the route segments matching (Ref, Kind):
// median northing of each 500 m easting bin
function BuildProfile(const Refs: array of string; const Kinds: array of Integer): TRoadProfile;
const
  BinW = 500;
var
  i, j, k, b, b0, b1, n: Integer;
  Lists: array of array of Double;
  Cnt: array of Integer;
  v: array of Double;
  t: Double;

  function Wanted(seg: Integer): Boolean;
  var
    m: Integer;
  begin
    for m := 0 to High(Refs) do
      if (RouteRef[seg] = Refs[m]) and (RouteKind[seg] = Kinds[m]) then Exit(True);
    result := False;
  end;

begin
  b0 := MaxInt; b1 := -MaxInt;
  for i := 0 to High(RouteKind) do
    if Wanted(i) then
      for j := RouteStart[i] to RouteStart[i + 1] - 1 do begin
        b := Floor(RoutePtE[j] / BinW);
        b0 := Min(b0, b); b1 := Max(b1, b);
      end;
  if b0 > b1 then raise Exception.Create('uKentData: no route points for ' + Refs[0]);
  SetLength(Lists, b1 - b0 + 1); SetLength(Cnt, b1 - b0 + 1);
  for i := 0 to High(RouteKind) do
    if Wanted(i) then
      for j := RouteStart[i] to RouteStart[i + 1] - 1 do begin
        b := Floor(RoutePtE[j] / BinW) - b0;
        if Cnt[b] = Length(Lists[b]) then SetLength(Lists[b], 2 * Cnt[b] + 4);
        Lists[b][Cnt[b]] := RoutePtN[j];
        Inc(Cnt[b]);
      end;
  n := 0;
  SetLength(result.E, Length(Cnt)); SetLength(result.N, Length(Cnt));
  for b := 0 to High(Cnt) do begin
    if Cnt[b] = 0 then Continue;
    v := Copy(Lists[b], 0, Cnt[b]);
    for j := 1 to High(v) do begin           // insertion sort: bins are small
      t := v[j]; k := j - 1;
      while (k >= 0) and (v[k] > t) do begin v[k + 1] := v[k]; Dec(k); end;
      v[k + 1] := t;
    end;
    result.E[n] := (b + b0 + 0.5) * BinW;
    if Odd(Cnt[b]) then result.N[n] := v[Cnt[b] div 2]
    else result.N[n] := 0.5 * (v[Cnt[b] div 2 - 1] + v[Cnt[b] div 2]);
    Inc(n);
  end;
  SetLength(result.E, n); SetLength(result.N, n);
end;

function ProfileAt(const P: TRoadProfile; E: Double): Double;
var
  lo, hi, m: Integer;
begin
  if E <= P.E[0] then Exit(P.N[0]);
  if E >= P.E[High(P.E)] then Exit(P.N[High(P.N)]);
  lo := 0; hi := High(P.E);
  while hi - lo > 1 do begin
    m := (lo + hi) div 2;
    if P.E[m] <= E then lo := m else hi := m;
  end;
  result := P.N[lo] + (P.N[hi] - P.N[lo]) * (E - P.E[lo]) / (P.E[hi] - P.E[lo]);
end;

procedure NeedProfiles;
var
  i: Integer;
begin
  if ProfDone then Exit;
  ProfA2M2 := BuildProfile(['A2', 'M2'], [RouteTrunk, RouteMotorway]);
  ProfM20 := BuildProfile(['M20'], [RouteMotorway]);
  for i := 0 to LsoaCount - 1 do
    if LsoaLabelN[i] > ProfileAt(ProfA2M2, LsoaLabelE[i]) then LsoaCor[i] := 0
    else if LsoaLabelN[i] < ProfileAt(ProfM20, LsoaLabelE[i]) then LsoaCor[i] := 2
    else LsoaCor[i] := 1;
  ProfDone := True;
end;

function LsoaCorridor(i: Integer): Integer; begin NeedProfiles; result := LsoaCor[i]; end;
function A2M2Northing(E: Double): Double; begin NeedProfiles; result := ProfileAt(ProfA2M2, E); end;
function M20Northing(E: Double): Double; begin NeedProfiles; result := ProfileAt(ProfM20, E); end;

procedure A2M2Extent(out E0, E1: Double);
begin
  NeedProfiles; E0 := ProfA2M2.E[0]; E1 := ProfA2M2.E[High(ProfA2M2.E)];
end;

procedure M20Extent(out E0, E1: Double);
begin
  NeedProfiles; E0 := ProfM20.E[0]; E1 := ProfM20.E[High(ProfM20.E)];
end;

function DriveDomainName(d: Integer): string;
begin
  if d < HospitalCount then result := HospitalName[d]
  else if d = HospitalCount then result := 'Nearer of William Harvey and Kent and Canterbury'
  else if d = DriveBestDomain then result := 'Best single site (lowest county mean time)'
  else result := 'Nearest of all seven acute hospitals';
end;

function DriveDomainShort(d: Integer): string;
begin
  if d < HospitalCount then result := HospitalShort[d]
  else if d = HospitalCount then result := 'WHH or K&C'
  else if d = DriveBestDomain then result := 'best site'
  else result := 'nearest';
end;

function LsoaDriveMinutes(i, Domain: Integer; Scenario: Integer): Double;
begin
  result := LsoaDriveMin[(Scenario * DriveDomainCount + Domain) * LsoaCount + i];
end;

function DriveDomainHospital(d: Integer): Integer;
begin
  if d < HospitalCount then result := d else result := -1;
end;

function DriveDomainHas(d, h: Integer): Boolean;
begin
  if d < HospitalCount then result := h = d
  else if d = HospitalCount then result := (h = DriveHospWHH) or (h = DriveHospKCH)
  else result := d = DriveNearestDomain;
end;

var
  DistArea: array[0..DistrictCount - 1] of Integer;

function DistrictArea(d: Integer): Integer; begin result := DistArea[d]; end;
function LsoaArea(i: Integer): Integer; begin result := DistArea[LsoaDistrict[i]]; end;

function AreaSetName(S: TAreaSet): string;
var
  a: Integer;
begin
  if S = AllAreas then Exit('Kent and Medway');
  result := '';
  for a := 0 to AreaCount - 1 do
    if a in S then begin
      if result <> '' then result := result + ' + ';
      result := result + AreaName[a];
    end;
  if result = '' then result := 'no area';
end;

function AreaLsoaMask(S: TAreaSet): TBoolArray;
var
  i: Integer;
begin
  SetLength(result, LsoaCount);
  for i := 0 to LsoaCount - 1 do result[i] := LsoaArea(i) in S;
end;

function AreaDistrictMask(S: TAreaSet): TBoolArray;
var
  d: Integer;
begin
  SetLength(result, DistrictCount);
  for d := 0 to DistrictCount - 1 do result[d] := DistArea[d] in S;
end;

procedure AssignAreas;
var
  d, a: Integer;
begin
  for d := 0 to DistrictCount - 1 do begin
    DistArea[d] := -1;
    for a := 0 to AreaCount - 1 do
      if Pos('|' + DistrictName[d] + '|', '|' + AreaDistricts[a] + '|') > 0 then DistArea[d] := a;
    if DistArea[d] < 0 then
      raise Exception.Create('uKentData: district ' + DistrictName[d] + ' is in no sub-area');
  end;
end;

procedure GeographicCentre(const IncDistrict: array of Boolean; out E, N: Double);
var
  r, k, j, d: Integer;
  Ar, Cxr, Cyr, cr, x0, y0, W, Sx, Sy: Double;
begin
  // area-weighted mean of each land ring's centroid (shoelace, relative to
  // a local origin for precision). The district rings are islands and
  // mainland, with no holes, so every ring counts positive whatever its
  // winding.
  x0 := DistrictPtE[0];
  y0 := DistrictPtN[0];
  W := 0; Sx := 0; Sy := 0;
  d := 0;
  for r := 0 to DistrictRingCount - 1 do begin
    while r >= DistrictRingFirst[d + 1] do Inc(d);
    if (Length(IncDistrict) > 0) and not IncDistrict[d] then Continue;
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
  if W = 0 then begin E := NaN; N := NaN; Exit; end;
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
  AssignAreas;
end.
