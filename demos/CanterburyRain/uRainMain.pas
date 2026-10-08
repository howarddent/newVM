unit uRainMain;

{*******************************************************************************

     Main form for the CanterburyRain demo: the weather over the last 12
     complete months at a chosen place in the UK or Ireland (Canterbury by
     default), on two tabs, each a TVMPlot2D (Graphs/uVMPlot2D.pas) over a
     table, with a location panel on the right.

     LOCATION - an alphabetical dropdown of every UK and Irish place with
     a population over 50,000 (uPlaces - GeoNames, compiled in), and under
     it an OpenGL outline map of the two islands (uUKMap.TUKMapView,
     Natural Earth coastline) showing every one of those places as a grey
     dot and the selected one as a red dot. Choosing a place in either -
     the dropdown, or a click on the map - fetches its weather. Canterbury
     is selected at every start (--location=<name> overrides that).

     RAINFALL - monthly totals as bars (the component's pstBar series type
     and SetXTickLabels category labels were added for this demo), with
     the 1991-2020 average for each month as a line with markers and the
     overall 1991-2020 mean monthly total as a dotted line.

     TEMPERATURE - one box-and-whisker per month (pstWhisker, also added
     for this demo): the box spans the month's mean daily minimum to mean
     daily maximum, the whiskers reach its lowest daily minimum and its
     highest daily maximum. Through the boxes, the mean daily maximum (red)
     and minimum (blue) as trend lines with markers, and the 1991-2020
     averages of each for the same months as dashed lines.

     The data is fetched fresh on every run (uWeatherData.pas - one
     Open-Meteo request for rain and temperature together; see that unit
     for why not OpenWeather, and for the offline cache). The download
     starts once the form is on screen (QueueAsyncCall from OnShow), so the
     window appears at once with a "fetching" status; "Fetch again"
     repeats it. "Save chart..." writes the chart on the visible tab as a
     PNG (TVMPlot2D.SaveToPNG).

     COUNTY RAINFALL MAP - a third tab: an OpenGL map of the 218 UK
     counties and unitary authorities (uCountyMap.TCountyMapView, ONS
     boundaries) coloured by rainfall over the latest 12 published months
     from the Met Office's HadUK-Grid (uCountyRain - downloaded when the
     tab is first opened, then with "Fetch again"). A radio group switches
     between the 12-month total (sequential yellow-green-blue scale) and
     the anomaly against each county's own 1991-2020 average for the same
     months (white = average, blues wetter, browns drier, in % of the
     average), with a matching colour bar beside it. Clicking a county
     shows its figures; the selected place's county is outlined and the
     place itself shown as a red dot; a table lists every county. While
     this tab is showing, the location panel's town map (no use here) is
     replaced by an alphabetical drop-down of the counties, kept in step
     with clicks on the county map.

     COMMAND LINE: --snapshot=<file.png> fetches the data, saves the
     rainfall chart to that file, the temperature chart to
     <file>_temperature.png, the map to <file>_map.png, the county map
     in both modes to <file>_county_total.png / _county_anomaly.png and
     the window's layout to <file>_window.bmp (and with the county tab
     showing, <file>_window_county.bmp), prints the
     status and both tables and exits -
     for checking the rendering without a screen capture (which Wayland
     desktops generally refuse). --offline skips the download and uses the
     saved copy, to test that fallback.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, DateUtils, Forms, Controls, Graphics, Dialogs,
  ExtCtrls, StdCtrls, ComCtrls,
  newVM, uVMPlot2D, uWeatherData, uPlaces, uUKMap, uCountyRain, uCountyMap;

type

  { TForm1 }

  TForm1 = class(TForm)
    btnRefresh: TButton;
    btnSave: TButton;
    cbLocation: TComboBox;
    cbCounty: TComboBox;
    lblCounty: TLabel;
    pnlCountyPick: TPanel;
    lblAttribution: TLabel;
    lblLocation: TLabel;
    lblPlaceInfo: TLabel;
    pnlMap: TPanel;
    pnlRight: TPanel;
    dlgSave: TSaveDialog;
    lblStatus: TLabel;
    memRain: TMemo;
    memTemp: TMemo;
    pcMain: TPageControl;
    pnlRainPlot: TPanel;
    pnlStatus: TPanel;
    pnlTempPlot: TPanel;
    tabRain: TTabSheet;
    tabTemp: TTabSheet;
    tabCounty: TTabSheet;
    pnlCountyMap: TPanel;
    pnlCountySide: TPanel;
    lblCountyTitle: TLabel;
    rgCountyMode: TRadioGroup;
    pbCountyLegend: TPaintBox;
    lblCountyInfo: TLabel;
    memCounty: TMemo;
    procedure btnRefreshClick(Sender: TObject);
    procedure pcMainChange(Sender: TObject);
    procedure rgCountyModeClick(Sender: TObject);
    procedure pbCountyLegendPaint(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure cbLocationChange(Sender: TObject);
    procedure cbCountyChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FRainPlot: TVMPlot2D;
    FTempPlot: TVMPlot2D;
    FMap: TUKMapView;
    FPlace: Integer;      // index into uPlaces.Places
    FLoadedOnce: Boolean;
    FSnapshot: string;    // --snapshot=<file>: save both charts, then exit
    FCountyMap: TCountyMapView;
    FCounty: TCountyRainSummary;
    FCountyLoaded: Boolean;          // a load has been attempted
    FCountyOK: Boolean;              // and succeeded
    FCountySel: Integer;             // selected county, or -1
    FCountyLo, FCountyHi: Double;    // colour range in use
    function LoadCountyData: Boolean;
    procedure CountyLoadAsync(Data: PtrInt);
    procedure ShowCounty;
    procedure ShowCountyInfo;
    procedure CountySelected(Sender: TObject; County: Integer);
    function CountyValue(c: Integer): Double;
    procedure UpdateRightPanel;
    procedure LoadData(Data: PtrInt);
    procedure SelectPlace(Index: Integer);
    procedure MapSelectPlace(Sender: TObject; Index: Integer);
    procedure ShowPlaceInfo;
    procedure ShowRain(const S: TWeatherSummary);
    procedure ShowTemperature(const S: TWeatherSummary);
    procedure ShowStatus(const S: TWeatherSummary);
    function SnapshotChart(Tab: TTabSheet; Plot: TVMPlot2D; const FileName: string): Boolean;
    procedure SnapshotException(Sender: TObject; E: Exception);
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

function LatLonText(Lat, Lon: Double): string; forward;

const
  clRainBar = TColor($B48246);    // steel blue (BGR)
  clTempBox = TColor($A0DCF5);    // pale amber (BGR)
  clMaxLine = TColor($2020D0);    // red
  clMinLine = TColor($C06020);    // blue

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FRainPlot := TVMPlot2D.Create(Self);
  FRainPlot.Parent := pnlRainPlot;
  FRainPlot.Align := alClient;
  FRainPlot.Title := 'monthly rainfall';
  FRainPlot.XAxisTitle := 'month';
  FRainPlot.YAxisTitle := 'rainfall (mm)';
  FRainPlot.SetSeriesBar(0, clRainBar, 'monthly total', 0.75);
  FRainPlot.SetSeriesStyle(1, clRed, 2.0, plsSolid,
    Format('%d-%d average for the month', [NormalFirstYear, NormalLastYear]), pmsCircle, 7);
  FRainPlot.SetSeriesStyle(2, TColor($404040), 1.5, plsDot, '');

  FTempPlot := TVMPlot2D.Create(Self);
  FTempPlot.Parent := pnlTempPlot;
  FTempPlot.Align := alClient;
  FTempPlot.Title := 'monthly temperatures';
  FTempPlot.XAxisTitle := 'month';
  FTempPlot.YAxisTitle := 'temperature (deg C)';
  FTempPlot.SetSeriesStyle(0, clMaxLine, 2.0, plsSolid, 'mean daily maximum', pmsCircle, 7);
  FTempPlot.SetSeriesStyle(1, clMinLine, 2.0, plsSolid, 'mean daily minimum', pmsCircle, 7);
  FTempPlot.SetSeriesStyle(2, clMaxLine, 1.5, plsDash,
    Format('%d-%d mean daily maximum', [NormalFirstYear, NormalLastYear]));
  FTempPlot.SetSeriesStyle(3, clMinLine, 1.5, plsDash,
    Format('%d-%d mean daily minimum', [NormalFirstYear, NormalLastYear]));
  FTempPlot.Series[4].LineColor := clTempBox;
  FTempPlot.Series[4].BarWidth := 0.55;
  FTempPlot.Series[4].Name := 'box: mean min to max; whiskers: lowest min, highest max';
  FTempPlot.LegendCorner := lcTopLeft;     // the winter highs leave that corner clear

  // location panel: the dropdown (Places is already alphabetical) and map
  cbLocation.Items.BeginUpdate;
  try
    cbLocation.Items.Clear;
    for i := 0 to PlaceCount - 1 do cbLocation.Items.Add(PlaceCaption(i));
  finally
    cbLocation.Items.EndUpdate;
  end;
  FPlace := -1;
  if Application.HasOption('location') then
    FPlace := FindPlace(Application.GetOptionValue('location'));
  if FPlace < 0 then FPlace := FindPlace(DefaultPlaceName);
  cbLocation.ItemIndex := FPlace;
  FMap := TUKMapView.Create(Self);
  FMap.Parent := pnlMap;
  FMap.Align := alClient;
  FMap.Selected := FPlace;
  FMap.OnSelectPlace := @MapSelectPlace;

  FCountyMap := TCountyMapView.Create(Self);
  FCountyMap.Parent := pnlCountyMap;
  FCountyMap.Align := alClient;
  FCountyMap.OnSelectCounty := @CountySelected;
  FCountyMap.SetPlace(Places[FPlace].East, Places[FPlace].North);
  FCountySel := CountyAt(Places[FPlace].East, Places[FPlace].North);
  FCountyMap.Selected := FCountySel;
  cbCounty.Items.BeginUpdate;
  try
    for i := 0 to CountyCount - 1 do cbCounty.Items.Add(CountyName[i]);   // already alphabetical
  finally
    cbCounty.Items.EndUpdate;
  end;
  cbCounty.ItemIndex := FCountySel;
  ShowPlaceInfo;

  pcMain.ActivePage := tabRain;
  lblStatus.Caption := 'Fetching weather data...';
  btnSave.Enabled := False;
  FSnapshot := Application.GetOptionValue('snapshot');
  if FSnapshot <> '' then Application.OnException := @SnapshotException;
  WeatherForceOffline := Application.HasOption('offline');
end;

procedure TForm1.cbLocationChange(Sender: TObject);
begin
  if cbLocation.ItemIndex >= 0 then SelectPlace(cbLocation.ItemIndex);
end;

procedure TForm1.MapSelectPlace(Sender: TObject; Index: Integer);
begin
  SelectPlace(Index);
end;

// Makes Index the current place in both the dropdown and the map, and
// fetches its weather.
procedure TForm1.SelectPlace(Index: Integer);
begin
  if (Index < 0) or (Index >= PlaceCount) then Exit;
  FPlace := Index;
  if cbLocation.ItemIndex <> Index then cbLocation.ItemIndex := Index;
  FMap.Selected := Index;
  FCountyMap.SetPlace(Places[Index].East, Places[Index].North);
  FCountySel := CountyAt(Places[Index].East, Places[Index].North);   // -1 outside the UK
  FCountyMap.Selected := FCountySel;
  cbCounty.ItemIndex := FCountySel;
  ShowCountyInfo;
  ShowPlaceInfo;
  LoadData(0);
end;

procedure TForm1.ShowPlaceInfo;
begin
  with Places[FPlace] do
    lblPlaceInfo.Caption := Format('%s'#10'population %s (GeoNames)'#10'%s',
      [PlaceCaption(FPlace), FormatFloat('#,##0', Population), LatLonText(Lat, Lon)]);
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if FLoadedOnce then Exit;
  FLoadedOnce := True;
  Application.QueueAsyncCall(@LoadData, 0);
end;

procedure TForm1.btnRefreshClick(Sender: TObject);
begin
  LoadData(0);
  if FCountyLoaded then LoadCountyData;
end;

procedure TForm1.pcMainChange(Sender: TObject);
begin
  UpdateRightPanel;
  if (pcMain.ActivePage = tabCounty) and not FCountyLoaded then
    Application.QueueAsyncCall(@CountyLoadAsync, 0);
end;

procedure TForm1.CountyLoadAsync(Data: PtrInt);
begin
  LoadCountyData;
end;

procedure TForm1.btnSaveClick(Sender: TObject);
var
  Plot: TVMPlot2D;
  What: string;
begin
  if pcMain.ActivePage = tabCounty then begin
    dlgSave.FileName := 'uk_county_rainfall_' + IfThen(rgCountyMode.ItemIndex = 1, 'anomaly', 'total')
      + '_' + FormatDateTime('yyyy-mm-dd', Date) + '.png';
    if not dlgSave.Execute then Exit;
    if FCountyMap.SaveToPNG(dlgSave.FileName) then
      lblStatus.Caption := 'Map saved to ' + dlgSave.FileName
    else
      lblStatus.Caption := 'Could not save the map';
    Exit;
  end;
  if pcMain.ActivePage = tabTemp then begin
    Plot := FTempPlot;
    What := 'temperature';
  end else begin
    Plot := FRainPlot;
    What := 'rainfall';
  end;
  dlgSave.FileName := LowerCase(StringReplace(Places[FPlace].Name, ' ', '_', [rfReplaceAll]))
    + '_' + What + '_' + FormatDateTime('yyyy-mm-dd', Date) + '.png';
  if not dlgSave.Execute then Exit;
  if Plot.SaveToPNG(dlgSave.FileName) then
    lblStatus.Caption := 'Chart saved to ' + dlgSave.FileName
  else
    lblStatus.Caption := 'Could not save the chart';
end;

// --snapshot runs unattended: report an exception and quit rather than
// wait on the LCL's modal "Abort / OK" dialog.
procedure TForm1.SnapshotException(Sender: TObject; E: Exception);
begin
  WriteLn(StdErr, 'error: ', E.ClassName, ': ', E.Message);
  Halt(2);
end;

// Shows Tab (a hidden tab's GL control has no context until it has been
// shown), lets it paint, and saves Plot.
function TForm1.SnapshotChart(Tab: TTabSheet; Plot: TVMPlot2D; const FileName: string): Boolean;
begin
  pcMain.ActivePage := Tab;
  Application.ProcessMessages;
  result := Plot.SaveToPNG(FileName);
  if result then WriteLn('chart saved to ', FileName)
  else WriteLn(StdErr, 'could not save ', FileName);
end;

procedure TForm1.LoadData(Data: PtrInt);
var
  i: Integer;
  S: TWeatherSummary;
  Err: string;
  ok: Boolean;
begin
  lblStatus.Caption := 'Fetching weather data for ' + PlaceCaption(FPlace)
    + ' from archive-api.open-meteo.com ...';
  btnRefresh.Enabled := False;
  cbLocation.Enabled := False;
  Screen.Cursor := crHourGlass;
  Application.ProcessMessages;
  try
    ok := GetWeatherSummary(PlaceCaption(FPlace), Places[FPlace].Lat, Places[FPlace].Lon, S, Err);
  finally
    Screen.Cursor := crDefault;
    btnRefresh.Enabled := True;
    cbLocation.Enabled := True;
  end;
  if not ok then begin
    lblStatus.Caption := 'No data: ' + Err;
    memRain.Lines.Text := Err;
    memTemp.Lines.Text := Err;
    if FSnapshot <> '' then begin
      WriteLn(StdErr, Err);
      ExitCode := 1;
      Application.Terminate;
    end;
    Exit;
  end;
  ShowRain(S);
  ShowTemperature(S);
  ShowStatus(S);
  btnSave.Enabled := True;

  if FSnapshot <> '' then begin
    if not SnapshotChart(tabRain, FRainPlot, FSnapshot) then ExitCode := 1;
    if not SnapshotChart(tabTemp, FTempPlot,
      ChangeFileExt(FSnapshot, '') + '_temperature' + ExtractFileExt(FSnapshot)) then ExitCode := 1;
    // the window's ordinary controls (the GL areas come out blank) - a
    // layout check
    with GetFormImage do
      try
        SaveToFile(ChangeFileExt(FSnapshot, '') + '_window.bmp');
      finally
        Free;
      end;
    if FMap.SaveToPNG(ChangeFileExt(FSnapshot, '') + '_map' + ExtractFileExt(FSnapshot)) then
      WriteLn('map saved to ', ChangeFileExt(FSnapshot, '') + '_map' + ExtractFileExt(FSnapshot))
    else
      ExitCode := 1;
    WriteLn(lblStatus.Caption);
    if LoadCountyData then begin
      pcMain.ActivePage := tabCounty;
      UpdateRightPanel;
      for i := 0 to 1 do begin
        rgCountyMode.ItemIndex := i;
        ShowCounty;
        Application.ProcessMessages;
        if FCountyMap.SaveToPNG(ChangeFileExt(FSnapshot, '') + '_county_'
          + IfThen(i = 1, 'anomaly', 'total') + ExtractFileExt(FSnapshot)) then
          WriteLn('county map saved (', IfThen(i = 1, 'anomaly', 'total'), ')')
        else
          ExitCode := 1;
        WriteLn(lblCountyInfo.Caption);
        WriteLn(Copy(memCounty.Lines.Text, 1, 1500));
      end;
      with GetFormImage do
        try
          SaveToFile(ChangeFileExt(FSnapshot, '') + '_window_county.bmp');
        finally
          Free;
        end;
    end else begin
      WriteLn(StdErr, lblStatus.Caption);
      ExitCode := 1;
    end;
    WriteLn(memRain.Lines.Text);
    WriteLn(memTemp.Lines.Text);
    Application.Terminate;
  end;
end;

// Month labels and positions shared by both charts.
procedure MonthAxis(const S: TWeatherSummary; out X: TVMobj;
  out Pos: TVMPlotDoubleArray; out Labels: TStringArray);
var
  k: Integer;
begin
  X := TVMobj.Create(1, 12);
  SetLength(Pos, 12);
  SetLength(Labels, 12);
  for k := 0 to 11 do begin
    X[0, k] := k;
    Pos[k] := k;
    Labels[k] := FormatDateTime('mmm yy', S.MonthStart[k]);
  end;
end;

// v with an explicit sign, e.g. '+1.3' / '-0.4' (FPC's Format has no '+' flag).
function Signed(v: Double; Width: Integer): string;
begin
  if v >= 0 then result := '+' + FormatFloat('0.0', v)
  else result := FormatFloat('0.0', v);
  while Length(result) < Width do result := ' ' + result;
end;

function PeriodText(const S: TWeatherSummary): string;
begin
  result := FormatDateTime('mmm yyyy', S.MonthStart[0]) + ' to '
    + FormatDateTime('mmm yyyy', S.MonthStart[11]);
end;

// '53.322N 9.068W'
function LatLonText(Lat, Lon: Double): string;
var
  NS, EW: string;
begin
  if Lat >= 0 then NS := 'N' else NS := 'S';
  if Lon >= 0 then EW := 'E' else EW := 'W';
  result := Format('%.3f%s %.3f%s', [Abs(Lat), NS, Abs(Lon), EW]);
end;

function SourceLine(const S: TWeatherSummary): string;
begin
  result := Format('Source: Open-Meteo historical weather API (ERA5/ERA5-Land reanalysis), '
    + 'grid point %s, %.0f m - model values, not station readings.',
    [LatLonText(S.GridLat, S.GridLon), S.Elevation]);
end;

procedure TForm1.ShowRain(const S: TWeatherSummary);
var
  X, Mean: TVMobj;
  Pos: TVMPlotDoubleArray;
  Labels: TStringArray;
  k: Integer;
  Total, Normal: Double;
  Flag: string;
begin
  MonthAxis(S, X, Pos, Labels);
  Mean := TVMobj.Create(1, 12);
  for k := 0 to 11 do Mean[0, k] := S.NormalMonthlyMean;
  FRainPlot.Series[2].Name := Format('%d-%d mean of all months (%.0f mm)',
    [NormalFirstYear, NormalLastYear, S.NormalMonthlyMean]);
  FRainPlot.Title := S.SiteName + ' - monthly rainfall, ' + PeriodText(S);
  FRainPlot.SetXTickLabels(Pos, Labels);
  FRainPlot.SetData(X, [S.Totals, S.Normals, Mean]);

  memRain.Lines.BeginUpdate;
  try
    memRain.Lines.Clear;
    memRain.Lines.Add(Format('%-10s %9s %12s %8s', ['month', 'total mm',
      Format('%d-%d', [NormalFirstYear, NormalLastYear]), 'of avg']));
    Total := 0;
    Normal := 0;
    for k := 0 to 11 do begin
      Total := Total + S.Totals[0, k];
      Normal := Normal + S.Normals[0, k];
      if S.DaysMissing[k] > 0 then
        Flag := Format('   (%d day(s) missing)', [S.DaysMissing[k]])
      else
        Flag := '';
      memRain.Lines.Add(Format('%-10s %9.1f %12.1f %7.0f%%%s',
        [FormatDateTime('mmm yyyy', S.MonthStart[k]), S.Totals[0, k], S.Normals[0, k],
         100 * S.Totals[0, k] / Max(S.Normals[0, k], 1e-9), Flag]));
    end;
    memRain.Lines.Add(Format('%-10s %9.1f %12.1f %7.0f%%',
      ['12 months', Total, Normal, 100 * Total / Max(Normal, 1e-9)]));
    memRain.Lines.Add('');
    memRain.Lines.Add(Format('%s so far (%d days): %.1f mm',
      [FormatDateTime('mmmm yyyy', Date), S.MonthToDateDays, S.MonthToDate]));
    memRain.Lines.Add(Format('%d-%d: %.0f mm a year, %.0f mm a month on average',
      [NormalFirstYear, NormalLastYear, S.NormalAnnual, S.NormalMonthlyMean]));
    memRain.Lines.Add('');
    memRain.Lines.Add(SourceLine(S));
    memRain.Lines.Add(S.Url);
  finally
    memRain.Lines.EndUpdate;
  end;
end;

procedure TForm1.ShowTemperature(const S: TWeatherSummary);
var
  X: TVMobj;
  Pos: TVMPlotDoubleArray;
  Labels: TStringArray;
  k: Integer;
  Anom, AnomSum: Double;
  Flag: string;
begin
  MonthAxis(S, X, Pos, Labels);
  FTempPlot.Title := S.SiteName + ' - monthly temperatures, ' + PeriodText(S);
  FTempPlot.SetXTickLabels(Pos, Labels);
  // lines first (SetData fills series 0..3), the whiskers after them
  FTempPlot.SetData(X, [S.MaxMean, S.MinMean, S.MaxNormal, S.MinNormal]);
  FTempPlot.SetWhiskerData(4, X, S.Lowest, S.MinMean, S.MaxMean, S.Highest);

  memTemp.Lines.BeginUpdate;
  try
    memTemp.Lines.Clear;
    memTemp.Lines.Add(Format('%-10s %8s %8s %8s %8s   %-11s %8s',
      ['deg C', 'mean max', 'mean min', 'highest', 'lowest',
       Format('%d-%d', [NormalFirstYear, NormalLastYear]), 'vs avg']));
    AnomSum := 0;
    for k := 0 to 11 do begin
      // anomaly of the month's mean temperature, (max + min) / 2
      Anom := 0.5 * (S.MaxMean[0, k] + S.MinMean[0, k])
            - 0.5 * (S.MaxNormal[0, k] + S.MinNormal[0, k]);
      AnomSum := AnomSum + Anom;
      if S.TempDaysMissing[k] > 0 then
        Flag := Format('   (%d day(s) missing)', [S.TempDaysMissing[k]])
      else
        Flag := '';
      memTemp.Lines.Add(Format('%-10s %8.1f %8.1f %8.1f %8.1f   %5.1f/%5.1f %s%s',
        [FormatDateTime('mmm yyyy', S.MonthStart[k]), S.MaxMean[0, k], S.MinMean[0, k],
         S.Highest[0, k], S.Lowest[0, k], S.MaxNormal[0, k], S.MinNormal[0, k],
         Signed(Anom, 8), Flag]));
    end;
    memTemp.Lines.Add(Format('12 months: %s deg C against the %d-%d average',
      [Signed(AnomSum / 12, 0), NormalFirstYear, NormalLastYear]));
    memTemp.Lines.Add('');
    if S.MtdTempDays > 0 then
      memTemp.Lines.Add(Format('%s so far (%d days): mean max %.1f, mean min %.1f, highest %.1f, lowest %.1f',
        [FormatDateTime('mmmm yyyy', Date), S.MtdTempDays, S.MtdMaxMean, S.MtdMinMean,
         S.MtdHighest, S.MtdLowest]));
    memTemp.Lines.Add('"vs avg" is the month''s mean temperature, (mean max + mean min) / 2, '
      + 'against the same for its 1991-2020 average.');
    memTemp.Lines.Add('');
    memTemp.Lines.Add(SourceLine(S));
    memTemp.Lines.Add(S.Url);
  finally
    memTemp.Lines.EndUpdate;
  end;
end;

procedure TForm1.ShowStatus(const S: TWeatherSummary);
begin
  if S.FromCache then
    lblStatus.Caption := Format('%s: OFFLINE - showing data saved %s (download failed: %s)',
      [S.SiteName, FormatDateTime('dd mmm yyyy hh:nn', S.FetchedAt), S.DownloadError])
  else
    lblStatus.Caption := Format('%s: data downloaded %s from Open-Meteo',
      [S.SiteName, FormatDateTime('dd mmm yyyy hh:nn', S.FetchedAt)]);
end;


{ ---- county rainfall map -------------------------------------------------- }

// Downloads/reads the Met Office grids and shows them. True on success.
function TForm1.LoadCountyData: Boolean;
var
  Err: string;
begin
  FCountyLoaded := True;
  lblStatus.Caption := 'Fetching Met Office HadUK-Grid rainfall for the county map ...';
  Screen.Cursor := crHourGlass;
  Application.ProcessMessages;
  try
    FCountyOK := GetCountyRain(FCounty, Err, WeatherForceOffline);
  finally
    Screen.Cursor := crDefault;
  end;
  result := FCountyOK;
  if not FCountyOK then begin
    lblStatus.Caption := 'County map: ' + Err;
    memCounty.Lines.Text := Err;
    Exit;
  end;
  lblCountyTitle.Caption := Format('Rainfall by county, %s to %s',
    [FormatDateTime('mmm yyyy', FCounty.FirstMonth), FormatDateTime('mmm yyyy', FCounty.LastMonth)]);
  if FCounty.Offline then
    lblStatus.Caption := 'County map: OFFLINE - Met Office grids from the local cache'
  else
    lblStatus.Caption := Format('County map: Met Office HadUK-Grid, %s to %s (%d of 12 months from the cache)',
      [FormatDateTime('mmm yyyy', FCounty.FirstMonth), FormatDateTime('mmm yyyy', FCounty.LastMonth),
       FCounty.CachedMonths]);
  ShowCounty;
end;

// The value shown for county c: the 12-month total (mm) or its anomaly
// (% of the county's 1991-2020 average for the same months).
function TForm1.CountyValue(c: Integer): Double;
begin
  if rgCountyMode.ItemIndex = 1 then
    result := 100 * (FCounty.Total[c] / FCounty.Normal[c] - 1)
  else
    result := FCounty.Total[c];
end;

procedure TForm1.ShowCounty;
var
  V: TCountyValues;
  c, i, j, t: Integer;
  lo, hi: Double;
  Order: array[0..CountyCount - 1] of Integer;
  Anom: Boolean;
begin
  if not FCountyOK then Exit;
  Anom := rgCountyMode.ItemIndex = 1;
  lo := Infinity;
  hi := -Infinity;
  for c := 0 to CountyCount - 1 do begin
    V[c] := CountyValue(c);
    if not IsNan(V[c]) then begin
      lo := Min(lo, V[c]);
      hi := Max(hi, V[c]);
    end;
  end;
  if Anom then begin
    // symmetric about 0 (white = the county's own average), in steps of 10 %
    FCountyHi := Max(20, 10 * Ceil(Max(Abs(lo), Abs(hi)) / 10));
    FCountyLo := -FCountyHi;
    FCountyMap.SetValues(V, cmAnomaly, FCountyLo, FCountyHi);
  end else begin
    FCountyLo := 100 * Floor(lo / 100);
    FCountyHi := 100 * Ceil(hi / 100);
    FCountyMap.SetValues(V, cmTotal, FCountyLo, FCountyHi);
  end;
  pbCountyLegend.Invalidate;

  // table, largest first
  for c := 0 to CountyCount - 1 do Order[c] := c;
  for i := 1 to CountyCount - 1 do begin
    t := Order[i];
    j := i - 1;
    while (j >= 0) and (V[Order[j]] < V[t]) do begin
      Order[j + 1] := Order[j];
      Dec(j);
    end;
    Order[j + 1] := t;
  end;
  memCounty.Lines.BeginUpdate;
  try
    memCounty.Lines.Clear;
    memCounty.Lines.Add(Format('%-22s %5s %5s %6s', ['county', 'total', '91-20', 'anom']));
    memCounty.Lines.Add(Format('%-22s %5s %5s %6s', ['', 'mm', 'mm', '%']));
    memCounty.Lines.Add(Format('%-22s %5.0f %5.0f %s%%',
      ['UK (12 km cells)', FCounty.UKTotal, FCounty.UKNormal,
       Signed(100 * (FCounty.UKTotal / FCounty.UKNormal - 1), 5)]));
    for i := 0 to CountyCount - 1 do begin
      c := Order[i];
      memCounty.Lines.Add(Format('%-22s %5.0f %5.0f %s%%%s',
        [Copy(CountyName[c], 1, 22), FCounty.Total[c], FCounty.Normal[c],
         Signed(100 * (FCounty.Total[c] / FCounty.Normal[c] - 1), 5),
         IfThen(CountySingleCell[c], ' *', '')]));
    end;
    memCounty.Lines.Add('');
    memCounty.Lines.Add('* small area: the single 12 km cell nearest it');
    memCounty.Lines.Add('Rainfall: Met Office HadUK-Grid 12 km (provisional), Crown copyright, OGL.');
    memCounty.Lines.Add('Boundaries: ONS Counties and Unitary Authorities Dec 2024, OGL.');
  finally
    memCounty.Lines.EndUpdate;
  end;
  ShowCountyInfo;
end;

procedure TForm1.ShowCountyInfo;
var
  c: Integer;
  d: Double;
begin
  c := FCountySel;
  if not FCountyOK then Exit;
  if c < 0 then begin
    lblCountyInfo.Caption := 'Click a county for its figures. (The selected place is outside the UK.)';
    Exit;
  end;
  d := FCounty.Total[c] - FCounty.Normal[c];
  lblCountyInfo.Caption := Format('%s (%s)'#10'%s to %s: %.0f mm'#10
    + '1991-2020 average for those months: %.0f mm'#10'%s mm, %s%% of average%s',
    [CountyName[c], CountyCode[c],
     FormatDateTime('mmm yyyy', FCounty.FirstMonth), FormatDateTime('mmm yyyy', FCounty.LastMonth),
     FCounty.Total[c], FCounty.Normal[c],
     IfThen(d >= 0, '+', '') + FormatFloat('0', d),
     FormatFloat('0', 100 * FCounty.Total[c] / FCounty.Normal[c]),
     IfThen(CountySingleCell[c], #10'(small area: the single 12 km grid cell nearest it)', '')]);
end;

procedure TForm1.CountySelected(Sender: TObject; County: Integer);
begin
  FCountySel := County;
  cbCounty.ItemIndex := County;
  ShowCountyInfo;
end;

procedure TForm1.cbCountyChange(Sender: TObject);
begin
  FCountySel := cbCounty.ItemIndex;
  FCountyMap.Selected := FCountySel;
  ShowCountyInfo;
end;

// The location panel's town map is no use on the county tab: there it is
// hidden and the county drop-down shown in its place.
procedure TForm1.UpdateRightPanel;
var
  OnCounty: Boolean;
begin
  OnCounty := pcMain.ActivePage = tabCounty;
  pnlRight.DisableAlign;
  try
    pnlMap.Visible := not OnCounty;
    pnlCountyPick.Visible := OnCounty;
    if OnCounty then begin
      pnlCountyPick.Top := lblPlaceInfo.Top + lblPlaceInfo.Height + 1;   // keep it under the place details
      lblAttribution.Caption := 'Counties: ONS Counties and Unitary Authorities (OGL). '
        + 'Rainfall: Met Office HadUK-Grid (OGL). Click a county on the map to choose it.';
    end else
      lblAttribution.Caption := 'Places: GeoNames (CC-BY 4.0). Outline: Natural Earth. '
        + 'Click a dot to choose a place.';
  finally
    pnlRight.EnableAlign;
  end;
end;

procedure TForm1.rgCountyModeClick(Sender: TObject);
begin
  ShowCounty;
end;

// Vertical colour bar for the current mode, with tick labels.
procedure TForm1.pbCountyLegendPaint(Sender: TObject);
const
  BarX = 12;
  BarW = 26;
  Top0 = 24;
var
  cv: TCanvas;
  BarH, y, i, n: Integer;
  v, step: Double;
  Anom: Boolean;
  lab: string;
begin
  cv := pbCountyLegend.Canvas;
  cv.Brush.Color := clForm;
  cv.FillRect(0, 0, pbCountyLegend.Width, pbCountyLegend.Height);
  if not FCountyOK then Exit;
  Anom := rgCountyMode.ItemIndex = 1;
  BarH := pbCountyLegend.Height - Top0 - 12;
  cv.Font.Color := clWindowText;
  if Anom then
    cv.TextOut(BarX, 2, '% of the county''s 1991-2020 average')
  else
    cv.TextOut(BarX, 2, 'total over 12 months, mm');
  for y := 0 to BarH - 1 do begin
    v := FCountyHi - (FCountyHi - FCountyLo) * y / (BarH - 1);
    cv.Pen.Color := CountyColour(TCountyColourMode(Ord(Anom)), v, FCountyLo, FCountyHi);
    cv.Line(BarX, Top0 + y, BarX + BarW, Top0 + y);
  end;
  cv.Brush.Style := bsClear;
  cv.Pen.Color := clBlack;
  cv.Rectangle(BarX, Top0, BarX + BarW, Top0 + BarH);
  // ticks: 5 for the anomaly (-R, -R/2, 0, R/2, R), round steps for totals
  if Anom then begin
    n := 4;
    step := (FCountyHi - FCountyLo) / n;
  end else begin
    step := 100;
    while (FCountyHi - FCountyLo) / step > 8 do
      if (FCountyHi - FCountyLo) / (step * 2.5) <= 8 then step := step * 2.5 else step := step * 2;
    n := Round((FCountyHi - FCountyLo) / step);
  end;
  for i := 0 to n do begin
    v := FCountyLo + i * step;
    y := Top0 + Round((FCountyHi - v) / (FCountyHi - FCountyLo) * (BarH - 1));
    cv.Line(BarX + BarW, y, BarX + BarW + 5, y);
    if Anom then begin
      lab := FormatFloat('0', 100 + v) + '%';
      if v > 0 then lab := lab + '  (' + FormatFloat('0', v) + '% wetter)'
      else if v < 0 then lab := lab + '  (' + FormatFloat('0', -v) + '% drier)'
      else lab := lab + '  = average';
    end else
      lab := FormatFloat('0', v);
    cv.TextOut(BarX + BarW + 9, y - cv.TextHeight(lab) div 2, lab);
  end;
  cv.Brush.Style := bsSolid;
end;

end.
