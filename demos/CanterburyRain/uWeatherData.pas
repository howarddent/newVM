unit uWeatherData;

{*******************************************************************************

     Weather data for the CanterburyRain demo, for any location (the form
     passes the place chosen from uPlaces' table; Canterbury by default):
     fetched fresh from the internet on every run and reduced to the last
     12 complete calendar
     months - rainfall totals, and daily maximum/minimum temperature
     statistics - plus the 1991-2020 average for each calendar month.

     SOURCE

     Open-Meteo's historical weather API (archive-api.open-meteo.com) -
     free, no API key, daily values for any point back to 1940 from the
     ERA5 / ERA5-Land reanalysis (ECMWF, Copernicus), blended with recent
     analysis data so it runs up to the present. OpenWeather
     (openweathermap.org) was the suggested source, but its historical and
     climate-statistics endpoints need a paid subscription and an API key;
     Open-Meteo gives both the recent months and the long-term averages
     from the same dataset, so they are consistent with each other. These
     are model grid values for the nearest cell, not station readings -
     Met Office station data will differ (rain by some tens
     of percent in a showery month; the grid temperature is an area
     average, so the extremes in particular are damped).

     ONE REQUEST covers 1 Jan 1991 to today, three daily variables
     (precipitation_sum, temperature_2m_max, temperature_2m_min - ~13,000
     days, ~700 kB, about a second):

       - the last 12 COMPLETE calendar months (so each month is comparable
         with its average), with days the API returns as null counted as
         missing;
       - rain: each month's total; temperature: each month's mean daily
         maximum and minimum, its highest daily maximum and its lowest
         daily minimum;
       - the 1991-2020 average for each calendar month (the WMO standard
         30-year climate-normal period): for rain the mean of the 30
         monthly totals, for temperature the mean daily maximum and
         minimum over every day of that month in those years;
       - the current month to date, reported separately.

     CACHE

     Every successful download is saved (GetAppConfigDir, the raw JSON);
     if a later run cannot reach the server, the last saved data is used
     and the summary says so and when it was fetched. (WeatherForceOffline
     skips the download, to exercise that path.) The cache file name
     names (one per place, weather_cache_<place>.json) differ from the
     rain-only first version's, so its cache is never mistaken for a
     complete one.

     OPENSSL 3

     FPC 3.2.2's openssl unit only knows library versions up to 1.1, so on
     a system with OpenSSL 3 alone (Ubuntu 24.04, for one) every HTTPS
     request fails with "Could not initialize OpenSSL library". The unit's
     DLLVersions suffix list is a writable typed constant, so the
     initialization section below puts '.3' at the front of it before any
     connection is made; the older suffixes are still tried after it. On
     Windows the equivalent failure reads "Could not initialize OpenSSL
     library" too (the unit only knows the 1.0/1.1 DLL names), and the
     same initialization puts libcrypto-3-x64.dll/libssl-3-x64.dll into
     the first-tried name slots - the DLLs themselves have to be beside
     the exe or on PATH, Git for Windows' mingw64in being one source.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DateUtils, Math,
  fpjson, jsonparser, fphttpclient, opensslsockets, openssl,
  newVM;

const
  NormalFirstYear = 1991;
  NormalLastYear = 2020;

type
  TWeatherSummary = record
    SiteName: string;                       // as passed to GetWeatherSummary
    MonthStart: array[0..11] of TDateTime;  // 1st of each of the last 12 complete months

    // rainfall
    Totals: TVMobj;                         // (1,12) mm
    DaysMissing: array[0..11] of Integer;
    Normals: TVMobj;                        // (1,12) mm - 1991-2020 average for that calendar month
    NormalMonthlyMean: Double;              // mean of the 12 calendar-month averages, mm
    NormalAnnual: Double;                   // sum of them, mm
    MonthToDate: Double;                    // mm so far this month
    MonthToDateDays: Integer;

    // temperature, deg C, each (1,12)
    MaxMean, MinMean: TVMobj;               // mean daily maximum / minimum
    Highest, Lowest: TVMobj;                // highest daily maximum / lowest daily minimum
    MaxNormal, MinNormal: TVMobj;           // 1991-2020 mean daily max/min for that calendar month
    TempDaysMissing: array[0..11] of Integer;
    MtdMaxMean, MtdMinMean, MtdHighest, MtdLowest: Double;   // this month so far
    MtdTempDays: Integer;

    GridLat, GridLon, Elevation: Double;    // the model grid point the API used
    FetchedAt: TDateTime;                   // when the data was downloaded
    FromCache: Boolean;                     // True if the download failed and the cache was used
    DownloadError: string;                  // why, when FromCache
    Url: string;
  end;

var
  // Skip the download as if the server were unreachable - for testing the
  // cache fallback (the demo's --offline option).
  WeatherForceOffline: Boolean = False;

// Downloads (or, failing that, reads the cached copy of) the daily series
// and reduces it. False, with ErrorMsg set, only if neither works.
function GetWeatherSummary(const ASiteName: string; ALat, ALon: Double;
  out Summary: TWeatherSummary; out ErrorMsg: string): Boolean;

implementation

// One cache file per place: weather_cache_<name with anything but letters
// and digits replaced by '_'>.json
function CacheFileName(const ASiteName: string): string;
var
  i: Integer;
  Safe: string;
begin
  Safe := ASiteName;
  for i := 1 to Length(Safe) do
    if not (Safe[i] in ['A'..'Z', 'a'..'z', '0'..'9']) then Safe[i] := '_';
  result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'weather_cache_' + Safe + '.json';
end;

function BuildUrl(ALat, ALon: Double): string;
var
  fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  result := Format('https://archive-api.open-meteo.com/v1/archive?latitude=%.4f&longitude=%.4f'
    + '&start_date=%d-01-01&end_date=%s'
    + '&daily=precipitation_sum,temperature_2m_max,temperature_2m_min&timezone=Europe%%2FLondon',
    [ALat, ALon, NormalFirstYear, FormatDateTime('yyyy-mm-dd', Date)], fs);
end;

function Download(const Url: string; out Body: string; out Err: string): Boolean;
var
  Client: TFPHTTPClient;
begin
  result := False;
  Body := '';
  Err := '';
  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.AllowRedirect := True;
      Client.IOTimeout := 30000;
      Client.AddHeader('User-Agent', 'newVM CanterburyRain demo');
      Body := Client.Get(Url);
      if Client.ResponseStatusCode <> 200 then
        Err := Format('HTTP %d %s', [Client.ResponseStatusCode, Client.ResponseStatusText])
      else
        result := True;
    except
      on E: Exception do Err := E.ClassName + ': ' + E.Message;
    end;
  finally
    Client.Free;
  end;
end;

procedure SaveCache(const FileName, Body: string);
var
  sl: TStringList;
begin
  try
    ForceDirectories(ExtractFilePath(FileName));
    sl := TStringList.Create;
    try
      sl.Text := Body;
      sl.SaveToFile(FileName);
    finally
      sl.Free;
    end;
  except
    // a cache that cannot be written only costs the offline fallback
  end;
end;

function LoadCache(const FileName: string; out Body: string; out Stamp: TDateTime): Boolean;
var
  sl: TStringList;
begin
  result := FileExists(FileName);
  Body := '';
  Stamp := 0;
  if not result then Exit;
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FileName);
    Body := sl.Text;
    FileAge(FileName, Stamp);
  finally
    sl.Free;
  end;
end;

// Month index counted from year 0, so consecutive months differ by 1.
function MonthKey(D: TDateTime): Integer;
begin
  result := YearOf(D) * 12 + MonthOf(D) - 1;
end;

function Reduce(const Body: string; Today: TDateTime; var S: TWeatherSummary;
  out Err: string): Boolean;
var
  Root: TJSONData;
  Obj, Daily: TJSONObject;
  Times, Precs, TMaxs, TMins: TJSONArray;
  i, k, m, y, FirstKey, CurKey, Key, NYears: Integer;
  D: TDateTime;
  v, tx, tn: Double;
  // rain
  Present: array[0..11] of Integer;
  Sums: array[0..11] of Double;
  NormSum: array[NormalFirstYear..NormalLastYear, 1..12] of Double;
  NormDays: array[NormalFirstYear..NormalLastYear, 1..12] of Integer;
  Clim: array[1..12] of Double;
  // temperature
  TDays: array[0..11] of Integer;
  TxSum, TnSum, TxHi, TnLo: array[0..11] of Double;
  NTxSum, NTnSum: array[1..12] of Double;
  NTDays: array[1..12] of Integer;
  MtdTxSum, MtdTnSum: Double;
begin
  result := False;
  Err := '';
  Root := nil;
  try
    try
      Root := GetJSON(Body);
    except
      on E: Exception do begin
        Err := 'unreadable reply: ' + E.Message;
        Exit;
      end;
    end;
    if not (Root is TJSONObject) then begin Err := 'unexpected reply'; Exit; end;
    Obj := TJSONObject(Root);
    if Obj.Find('error') <> nil then begin
      Err := 'server error: ' + Obj.Get('reason', '?');
      Exit;
    end;
    Daily := Obj.Find('daily') as TJSONObject;
    if Daily = nil then begin Err := 'no daily data in reply'; Exit; end;
    Times := Daily.Find('time') as TJSONArray;
    Precs := Daily.Find('precipitation_sum') as TJSONArray;
    TMaxs := Daily.Find('temperature_2m_max') as TJSONArray;
    TMins := Daily.Find('temperature_2m_min') as TJSONArray;
    if (Times = nil) or (Precs = nil) or (TMaxs = nil) or (TMins = nil)
       or (Precs.Count <> Times.Count) or (TMaxs.Count <> Times.Count)
       or (TMins.Count <> Times.Count) then begin
      Err := 'daily time/precipitation/temperature arrays missing or mismatched';
      Exit;
    end;
    S.GridLat := Obj.Get('latitude', 0.0);
    S.GridLon := Obj.Get('longitude', 0.0);
    S.Elevation := Obj.Get('elevation', 0.0);

    CurKey := MonthKey(Today);
    FirstKey := CurKey - 12;
    for k := 0 to 11 do begin
      S.MonthStart[k] := EncodeDate((FirstKey + k) div 12, (FirstKey + k) mod 12 + 1, 1);
      Present[k] := 0;
      Sums[k] := 0;
      TDays[k] := 0;
      TxSum[k] := 0;
      TnSum[k] := 0;
      TxHi[k] := -Infinity;
      TnLo[k] := Infinity;
    end;
    for y := NormalFirstYear to NormalLastYear do
      for m := 1 to 12 do begin
        NormSum[y, m] := 0;
        NormDays[y, m] := 0;
      end;
    for m := 1 to 12 do begin
      NTxSum[m] := 0;
      NTnSum[m] := 0;
      NTDays[m] := 0;
    end;
    S.MonthToDate := 0;
    S.MonthToDateDays := 0;
    MtdTxSum := 0;
    MtdTnSum := 0;
    S.MtdTempDays := 0;
    S.MtdHighest := -Infinity;
    S.MtdLowest := Infinity;

    for i := 0 to Times.Count - 1 do begin
      D := ScanDateTime('yyyy-mm-dd', Times.Strings[i]);
      Key := MonthKey(D);
      y := YearOf(D);
      m := MonthOf(D);

      // rain (a null day is missing)
      if Precs.Items[i].JSONType <> jtNull then begin
        v := Precs.Items[i].AsFloat;
        if (y >= NormalFirstYear) and (y <= NormalLastYear) then begin
          NormSum[y, m] := NormSum[y, m] + v;
          Inc(NormDays[y, m]);
        end;
        if (Key >= FirstKey) and (Key < CurKey) then begin
          k := Key - FirstKey;
          Sums[k] := Sums[k] + v;
          Inc(Present[k]);
        end else if Key = CurKey then begin
          S.MonthToDate := S.MonthToDate + v;
          Inc(S.MonthToDateDays);
        end;
      end;

      // temperature (a day counts only with both its max and its min)
      if (TMaxs.Items[i].JSONType <> jtNull) and (TMins.Items[i].JSONType <> jtNull) then begin
        tx := TMaxs.Items[i].AsFloat;
        tn := TMins.Items[i].AsFloat;
        if (y >= NormalFirstYear) and (y <= NormalLastYear) then begin
          NTxSum[m] := NTxSum[m] + tx;
          NTnSum[m] := NTnSum[m] + tn;
          Inc(NTDays[m]);
        end;
        if (Key >= FirstKey) and (Key < CurKey) then begin
          k := Key - FirstKey;
          TxSum[k] := TxSum[k] + tx;
          TnSum[k] := TnSum[k] + tn;
          TxHi[k] := Max(TxHi[k], tx);
          TnLo[k] := Min(TnLo[k], tn);
          Inc(TDays[k]);
        end else if Key = CurKey then begin
          MtdTxSum := MtdTxSum + tx;
          MtdTnSum := MtdTnSum + tn;
          S.MtdHighest := Max(S.MtdHighest, tx);
          S.MtdLowest := Min(S.MtdLowest, tn);
          Inc(S.MtdTempDays);
        end;
      end;
    end;

    // 1991-2020 rain average per calendar month, over the complete months only
    for m := 1 to 12 do begin
      Clim[m] := 0;
      NYears := 0;
      for y := NormalFirstYear to NormalLastYear do
        if NormDays[y, m] = DaysInAMonth(y, m) then begin
          Clim[m] := Clim[m] + NormSum[y, m];
          Inc(NYears);
        end;
      if (NYears = 0) or (NTDays[m] = 0) then begin
        Err := Format('no %s data in %d-%d to average',
          [FormatSettings.LongMonthNames[m], NormalFirstYear, NormalLastYear]);
        Exit;
      end;
      Clim[m] := Clim[m] / NYears;
    end;

    S.Totals := TVMobj.Create(1, 12);
    S.Normals := TVMobj.Create(1, 12);
    S.MaxMean := TVMobj.Create(1, 12);
    S.MinMean := TVMobj.Create(1, 12);
    S.Highest := TVMobj.Create(1, 12);
    S.Lowest := TVMobj.Create(1, 12);
    S.MaxNormal := TVMobj.Create(1, 12);
    S.MinNormal := TVMobj.Create(1, 12);
    S.NormalAnnual := 0;
    for m := 1 to 12 do S.NormalAnnual := S.NormalAnnual + Clim[m];
    S.NormalMonthlyMean := S.NormalAnnual / 12;
    for k := 0 to 11 do begin
      m := MonthOf(S.MonthStart[k]);
      S.Totals[0, k] := Sums[k];
      S.DaysMissing[k] := DaysInMonth(S.MonthStart[k]) - Present[k];
      S.Normals[0, k] := Clim[m];
      S.TempDaysMissing[k] := DaysInMonth(S.MonthStart[k]) - TDays[k];
      if TDays[k] = 0 then begin
        Err := 'no temperature data for ' + FormatDateTime('mmmm yyyy', S.MonthStart[k]);
        Exit;
      end;
      S.MaxMean[0, k] := TxSum[k] / TDays[k];
      S.MinMean[0, k] := TnSum[k] / TDays[k];
      S.Highest[0, k] := TxHi[k];
      S.Lowest[0, k] := TnLo[k];
      S.MaxNormal[0, k] := NTxSum[m] / NTDays[m];
      S.MinNormal[0, k] := NTnSum[m] / NTDays[m];
    end;
    if S.MtdTempDays > 0 then begin
      S.MtdMaxMean := MtdTxSum / S.MtdTempDays;
      S.MtdMinMean := MtdTnSum / S.MtdTempDays;
    end;
    result := True;
  finally
    Root.Free;
  end;
end;

function GetWeatherSummary(const ASiteName: string; ALat, ALon: Double;
  out Summary: TWeatherSummary; out ErrorMsg: string): Boolean;
var
  Body, DlErr, Err, Cache: string;
  Stamp: TDateTime;
begin
  result := False;
  ErrorMsg := '';
  Summary := Default(TWeatherSummary);
  Summary.SiteName := ASiteName;
  Summary.Url := BuildUrl(ALat, ALon);
  Cache := CacheFileName(ASiteName);

  if WeatherForceOffline then DlErr := 'offline (--offline)'
  else if Download(Summary.Url, Body, DlErr) and Reduce(Body, Date, Summary, Err) then begin
    Summary.FetchedAt := Now;
    Summary.FromCache := False;
    SaveCache(Cache, Body);
    result := True;
    Exit;
  end;
  if DlErr = '' then DlErr := Err;

  // offline / server trouble: fall back to the last good download
  if LoadCache(Cache, Body, Stamp) and Reduce(Body, Date, Summary, Err) then begin
    Summary.FetchedAt := Stamp;
    Summary.FromCache := True;
    Summary.DownloadError := DlErr;
    result := True;
    Exit;
  end;
  ErrorMsg := 'Could not download the weather data for ' + ASiteName + ' (' + DlErr
    + ') and there is no saved copy to fall back on.';
end;

{$IFDEF UNIX}
procedure PreferOpenSSL3;
var
  i: Integer;
begin
  if DLLVersions[1] = '.3' then Exit;
  for i := High(DLLVersions) downto Low(DLLVersions) + 1 do
    DLLVersions[i] := DLLVersions[i - 1];
  DLLVersions[1] := '.3';
  {$IFDEF DARWIN}
  // openssl.pas copies entry 2 over entry 1 on macOS (no unversioned dylib)
  DLLVersions[2] := '.3';
  {$ENDIF}
end;
{$ENDIF}

{$IFDEF WINDOWS}
{ The Windows counterpart. openssl.pas tries DLLUtilName/DLLSSLName first
  (libeay32/ssleay32, the OpenSSL 1.0 names) and then the 1.1 names in
  DLLUtilName2/DLLSSLName2/3; none of those exist for OpenSSL 3, whose
  Windows builds are libcrypto-3-x64.dll and libssl-3-x64.dll (Git for
  Windows ships a pair in mingw64in, which is where this machine's copies
  beside the exe came from). Those typed constants are writable, so the
  OpenSSL 3 names go into the first-tried slots and the 1.1 names stay as
  the fallback. The DLLs must be beside the exe or on PATH; .gitignore
  keeps them out of the repo (demos/*/*.dll). }
procedure PreferOpenSSL3;
begin
  DLLUtilName := {$IFDEF WIN64}'libcrypto-3-x64.dll'{$ELSE}'libcrypto-3.dll'{$ENDIF};
  DLLSSLName  := {$IFDEF WIN64}'libssl-3-x64.dll'{$ELSE}'libssl-3.dll'{$ENDIF};
end;
{$ENDIF}

initialization
  PreferOpenSSL3;   // Unix: '.3' suffix first; Windows: the OpenSSL 3 DLL names first
end.
