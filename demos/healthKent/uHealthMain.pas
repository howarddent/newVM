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
       - or no fill,
     with check boxes for district and LSOA outlines, built-up areas over
     50,000 people, motorways, trunk roads, primary A roads, railways,
     the population barycentre and the geographic centre. Wheel zooms,
     drag pans, a click selects an LSOA and the memo shows its figures.
     The legend beside the map shows the colour scale (and, for
     deprivation, the share of residents in each decile) and the line and
     marker key.

     The memo also gives the area's totals, the population barycentre
     (computed with newVM - see uKentData) as a grid reference and
     latitude/longitude, how far and which way it lies from the geographic
     centre, and a table by district.

     SOURCES - a glossary of every dataset compiled in (publisher,
     edition, licence, link and what the demo uses it for) and of the
     terms used, from uKentData's Sources and Glossary tables.

     COMMAND LINE: --snapshot=<prefix> saves the map coloured by density
     (<prefix>_density.png), by IMD decile (<prefix>_imd.png), by health
     deprivation (<prefix>_health.png), a zoomed view round the barycentre
     (<prefix>_zoom.png) and the window (<prefix>_window.bmp), prints the
     memo and exits.

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
    tabMap: TTabSheet;
    tabSources: TTabSheet;
    procedure btnResetClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure cbDomainChange(Sender: TObject);
    procedure cgLayersItemClick(Sender: TObject; Index: integer);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure pbLegendPaint(Sender: TObject);
    procedure rgColourClick(Sender: TObject);
  private
    FMap: TKentMapView;
    FBaryE, FBaryN, FGeoE, FGeoN: Double;
    FSnapshot: string;
    FShown: Boolean;
    procedure ApplyColouring;
    procedure ApplyLayers;
    procedure LsoaSelected(Sender: TObject; Lsoa: Integer);
    procedure ViewChanged(Sender: TObject);
    procedure ShowInfo;
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
  // check group items
  liDistricts = 0; liLsoas = 1; liTowns = 2; liMotorways = 3; liTrunk = 4;
  liPrimary = 5; liRail = 6; liBary = 7; liGeo = 8;

function Thousands(v: Double): string;
begin
  result := FormatFloat('#,##0', v);
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
begin
  FMap := TKentMapView.Create(Self);
  FMap.Parent := pnlMap;
  FMap.Align := alClient;
  FMap.OnSelectLsoa := @LsoaSelected;
  FMap.OnViewChange := @ViewChanged;

  PopulationBarycentre([], FBaryE, FBaryN);
  GeographicCentre(FGeoE, FGeoN);
  FMap.SetBarycentre(FBaryE, FBaryN);
  FMap.SetGeoCentre(FGeoE, FGeoN);

  cbDomain.Items.BeginUpdate;
  try
    cbDomain.Items.Clear;
    for d := 0 to DomainCount - 1 do cbDomain.Items.Add(DomainName[d]);
  finally
    cbDomain.Items.EndUpdate;
  end;
  cbDomain.ItemIndex := 0;
  if Application.HasOption('colour') then
    rgColour.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('colour'), 0), 0, 2);
  if Application.HasOption('domain') then
    cbDomain.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('domain'), 0), 0, DomainCount - 1);
  for d := 0 to cgLayers.Items.Count - 1 do
    cgLayers.Checked[d] := d in [liDistricts, liTowns, liMotorways, liTrunk, liRail, liBary, liGeo];
  ApplyLayers;
  ApplyColouring;
  FillSources;
  ShowInfo;
  ViewChanged(nil);
  pcMain.ActivePage := tabMap;
  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then Application.OnException := @SnapshotException;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if FShown then Exit;
  FShown := True;
  if FSnapshot <> '' then Application.QueueAsyncCall(@RunSnapshot, 0);
end;

procedure TForm1.ApplyColouring;
begin
  cbDomain.Enabled := rgColour.ItemIndex = 1;
  lblDomain.Enabled := cbDomain.Enabled;
  case rgColour.ItemIndex of
    0: FMap.SetColouring(kcmDensity, cbDomain.ItemIndex);
    1: FMap.SetColouring(kcmDeprivation, cbDomain.ItemIndex);
  else
    FMap.SetColouring(kcmNone, cbDomain.ItemIndex);
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
  pbLegend.Invalidate;
end;

procedure TForm1.rgColourClick(Sender: TObject);
begin
  ApplyColouring;
end;

procedure TForm1.cbDomainChange(Sender: TObject);
begin
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
    + 'Population: ONS %s estimates; deprivation: English Indices of Deprivation 2025.',
    [FMap.Zoom, PopulationYear]);
end;

// share of the area's residents living in LSOAs of national decile Decile
function TForm1.DecileShare(Domain, Decile: Integer): Double;
var
  i: Integer;
  s: Int64;
begin
  s := 0;
  for i := 0 to LsoaCount - 1 do
    if LsoaDecileOf(i, Domain) = Decile then s := s + LsoaPop[i];
  result := 100 * s / TotalPopulation;
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
begin
  dom := cbDomain.ItemIndex;
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
      L.Add('');
    end else
      L.Add('Click an area on the map for its population and deprivation.' + LineEnding);

    tp := TotalPopulation;
    L.Add('KENT AND MEDWAY (NHS Kent and Medway ICB area)');
    L.Add(Format('  population %s (%s), land %s km2, %s people per km2, %d LSOAs',
      [Thousands(tp), PopulationYear, Thousands(TotalLandKm2), Thousands(tp / TotalLandKm2), LsoaCount]));
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
    L.Add('  drawn towards the Medway towns and the Thames-side and Maidstone populations.');
    SetLength(Inc, LsoaCount);
    for i := 0 to LsoaCount - 1 do Inc[i] := DistrictName[LsoaDistrict[i]] <> 'Medway';
    PopulationBarycentre(Inc, KccE, KccN);
    L.Add('  Kent County Council area alone (without Medway): ' + GridRef(KccE, KccN)
      + Format(', %.1f km %s of the combined one', [Hypot(KccE - FBaryE, KccN - FBaryN) / 1000,
        Compass(FBaryE, FBaryN, KccE, KccN)]));

    // by district
    SetLength(Pop, DistrictCount);
    SetLength(Low, DistrictCount);
    SetLength(Land, DistrictCount);
    SetLength(ScoreSum, DistrictCount);
    for d := 0 to DistrictCount - 1 do begin
      Pop[d] := 0; Low[d] := 0; Land[d] := 0; ScoreSum[d] := 0;
    end;
    for i := 0 to LsoaCount - 1 do begin
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
      L.Add(Format('  %-23s %11s %10.1f %9s %13.2f %12.1f %%',
        [DistrictName[d], Thousands(Pop[d]), Land[d], Thousands(Pop[d] / Land[d]),
         ScoreSum[d] / Pop[d], 100 * Low[d] / Pop[d]]));
    L.Add('  * population-weighted mean of the LSOA scores; deciles 1-2 = the most deprived');
    L.Add('    20 % of LSOAs in England.');
    L.Add('');
    L.Add(Format('TOWNS (ONS built-up areas over %s, %s population)', [Thousands(TownMinPopulation), PopulationYear]));
    for t := 0 to TownCount - 1 do
      L.Add(Format('  %-24s %9s', [TownName[t], Thousands(TownPop[t])]));
    memInfo.Lines.Text := L.Text;
  finally
    L.Free;
  end;
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
      h := 160;
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
      dom := cbDomain.ItemIndex;
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
  else
    begin
      cv.TextOut(BarX, 2, 'No fill');
      y0 := 26;
    end;
  end;
  // line and marker key
  if cgLayers.Checked[liMotorways] then begin KeyLine(y0, clMotorway, 3, 'motorway', False); Inc(y0, 18); end;
  if cgLayers.Checked[liTrunk] then begin KeyLine(y0, clTrunk, 3, 'trunk road (primary route)', False); Inc(y0, 18); end;
  if cgLayers.Checked[liPrimary] then begin KeyLine(y0, clPrimary, 2, 'primary A road', False); Inc(y0, 18); end;
  if cgLayers.Checked[liRail] then begin KeyLine(y0, clRail, 4, 'railway', True); Inc(y0, 18); end;
  cv.Pen.Width := 1;
  if cgLayers.Checked[liTowns] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clWhite; cv.Pen.Color := clBlack;
    cv.Ellipse(BarX + 13, y0 - 4, BarX + 21, y0 + 4);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, Format('town over %s', [Thousands(TownMinPopulation)]));
    Inc(y0, 18);
  end;
  if cgLayers.Checked[liBary] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := clBary; cv.Pen.Color := clBlack;
    cv.Ellipse(BarX + 10, y0 - 7, BarX + 24, y0 + 7);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'population barycentre');
    Inc(y0, 18);
  end;
  if cgLayers.Checked[liGeo] then begin
    cv.Brush.Style := bsSolid; cv.Brush.Color := TColor($1A1A1A); cv.Pen.Color := clBlack;
    cv.Polygon([Point(BarX + 17, y0 - 6), Point(BarX + 23, y0), Point(BarX + 17, y0 + 6), Point(BarX + 11, y0)]);
    cv.Brush.Style := bsClear;
    cv.TextOut(BarX + 42, y0 - cv.TextHeight('T') div 2, 'geographic centre');
  end;
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
  rgColour.ItemIndex := 0; ApplyColouring; Save('density');
  rgColour.ItemIndex := 1; cbDomain.ItemIndex := 0; ApplyColouring; Save('imd');
  cbDomain.ItemIndex := 4; ApplyColouring; Save('health');
  cbDomain.ItemIndex := 0; ApplyColouring;
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
