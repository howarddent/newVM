unit uDABStations;

{*******************************************************************************

     TDABStationList - the DAB stations known from scanning, flattened to
     one entry per station (a station carries its multiplex's details with
     it, since a listener picks a station, not an ensemble), kept across
     sessions in a small INI file.

     MERGING: a scan only replaces what it actually looked at. Every block
     a scan visited has its old stations dropped and the newly found ones
     added; blocks it didn't visit (a single-block scan, or a full scan
     stopped part way) keep what they had. So rescanning one block to
     check an aerial change never loses the rest of the list.

     HasScanned is the "has a scan ever been run" answer - true once any
     scan has been merged in or a saved list loaded, even if that scan
     found nothing, so an empty result isn't mistaken for "never scanned"
     and re-run every time.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, IniFiles, uDABDecoder, uDABScanner;

type
  TDABStation = record
    ServiceLabel: string;      // '' if the name never arrived during the scan
    SId: LongWord;
    AudioType: string;         // 'DAB', 'DAB+' or ''
    SubChId: Integer;          // -1 if unknown
    EnsembleLabel: string;
    EId: Integer;              // -1 if unknown
    BlockName: string;
    FreqHz: QWord;
    SNRdB, MERdB, FICOkPercent: Double;   // of the multiplex, at scan time
    ScannedAt: TDateTime;
  end;

  { TDABStationList }
  TDABStationList = class
  private
    FItems: array of TDABStation;
    FHasScanned: Boolean;
    function GetCount: Integer;
    function GetItem(Index: Integer): TDABStation;
    procedure Sort;
  public
    procedure Clear;
    procedure MergeScan(const Results: array of TDABScanResult);
    procedure LoadFromFile(const FileName: string);
    procedure SaveToFile(const FileName: string);
    function DisplayName(Index: Integer): string;
    property Count: Integer read GetCount;
    property Items[Index: Integer]: TDABStation read GetItem; default;
    property HasScanned: Boolean read FHasScanned;
  end;

implementation

// Fixed separators for everything written to the file, so a list saved
// under one locale reads back under another.
function FileFormatSettings: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
  Result.DateSeparator := '-';
  Result.TimeSeparator := ':';
  Result.ShortDateFormat := 'yyyy-mm-dd';
  Result.LongTimeFormat := 'hh:nn:ss';
end;

function TDABStationList.GetCount: Integer;
begin
  Result := Length(FItems);
end;

function TDABStationList.GetItem(Index: Integer): TDABStation;
begin
  Result := FItems[Index];
end;

procedure TDABStationList.Clear;
begin
  SetLength(FItems, 0);
  FHasScanned := False;
end;

function TDABStationList.DisplayName(Index: Integer): string;
begin
  Result := FItems[Index].ServiceLabel;
  if Result = '' then Result := Format('(unnamed %.4X)', [FItems[Index].SId]);
end;

// Alphabetical by name, unnamed last; ties (the same station carried on
// two multiplexes) by block.
procedure TDABStationList.Sort;
var
  i, j: Integer;
  t: TDABStation;

  function Before(const A, B: TDABStation): Boolean;
  var c: Integer;
  begin
    if (A.ServiceLabel = '') <> (B.ServiceLabel = '') then Exit(B.ServiceLabel = '');
    c := CompareText(A.ServiceLabel, B.ServiceLabel);
    if c <> 0 then Exit(c < 0);
    Result := A.FreqHz < B.FreqHz;
  end;

begin
  for i := 1 to High(FItems) do begin
    t := FItems[i];
    j := i - 1;
    while (j >= 0) and Before(t, FItems[j]) do begin
      FItems[j + 1] := FItems[j];
      Dec(j);
    end;
    FItems[j + 1] := t;
  end;
end;

procedure TDABStationList.MergeScan(const Results: array of TDABScanResult);
var
  r, i, k: Integer;
  Kept: array of TDABStation;
  Visited: Boolean;
  St: TDABStation;
  Now_: TDateTime;
begin
  if Length(Results) = 0 then Exit;
  FHasScanned := True;
  Now_ := Now;

  // Drop every station on a block this scan visited.
  SetLength(Kept, 0);
  for i := 0 to High(FItems) do begin
    Visited := False;
    for r := 0 to High(Results) do
      if Results[r].Channel.FreqHz = FItems[i].FreqHz then Visited := True;
    if not Visited then begin
      SetLength(Kept, Length(Kept) + 1);
      Kept[High(Kept)] := FItems[i];
    end;
  end;
  FItems := Kept;

  for r := 0 to High(Results) do begin
    if not Results[r].Found then Continue;
    for k := 0 to High(Results[r].Services) do begin
      St := Default(TDABStation);
      St.ServiceLabel := Results[r].Services[k].ServiceLabel;
      St.SId := Results[r].Services[k].SId;
      St.AudioType := Results[r].Services[k].AudioType;
      St.SubChId := Results[r].Services[k].SubChId;
      St.EnsembleLabel := Results[r].EnsembleLabel;
      St.EId := Results[r].EId;
      St.BlockName := Results[r].Channel.Name;
      St.FreqHz := Results[r].Channel.FreqHz;
      St.SNRdB := Results[r].SNRdB;
      St.MERdB := Results[r].MERdB;
      St.FICOkPercent := Results[r].FICOkPercent;
      St.ScannedAt := Now_;
      SetLength(FItems, Length(FItems) + 1);
      FItems[High(FItems)] := St;
    end;
  end;
  Sort;
end;

// INI rather than anything cleverer: hand-readable, and the same format
// the main settings file already uses. Doubles are written with '.' so a
// file survives a change of locale.
procedure TDABStationList.SaveToFile(const FileName: string);
var
  Ini: TIniFile;
  FS: TFormatSettings;
  Sections: TStringList;
  i: Integer;
  Sec: string;

  function D(V: Double): string;
  begin
    if IsNan(V) then Result := '' else Result := FloatToStr(V, FS);
  end;

begin
  FS := FileFormatSettings;
  ForceDirectories(ExtractFilePath(FileName));
  Ini := TIniFile.Create(FileName);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    for i := 0 to Sections.Count - 1 do Ini.EraseSection(Sections[i]);
    Ini.WriteInteger('Scan', 'Count', Length(FItems));
    for i := 0 to High(FItems) do begin
      Sec := 'Station' + IntToStr(i);
      Ini.WriteString(Sec, 'Label', FItems[i].ServiceLabel);
      Ini.WriteString(Sec, 'SId', IntToHex(FItems[i].SId, 4));
      Ini.WriteString(Sec, 'Type', FItems[i].AudioType);
      Ini.WriteInteger(Sec, 'SubChId', FItems[i].SubChId);
      Ini.WriteString(Sec, 'Ensemble', FItems[i].EnsembleLabel);
      Ini.WriteInteger(Sec, 'EId', FItems[i].EId);
      Ini.WriteString(Sec, 'Block', FItems[i].BlockName);
      Ini.WriteString(Sec, 'FreqHz', IntToStr(FItems[i].FreqHz));
      Ini.WriteString(Sec, 'SNRdB', D(FItems[i].SNRdB));
      Ini.WriteString(Sec, 'MERdB', D(FItems[i].MERdB));
      Ini.WriteString(Sec, 'FICOkPercent', D(FItems[i].FICOkPercent));
      Ini.WriteString(Sec, 'ScannedAt', FormatDateTime('yyyy-mm-dd hh:nn:ss', FItems[i].ScannedAt, FS));
    end;
    Ini.UpdateFile;
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

procedure TDABStationList.LoadFromFile(const FileName: string);
var
  Ini: TIniFile;
  FS: TFormatSettings;
  i, N: Integer;
  Sec: string;

  function D(const Key: string): Double;
  begin
    Result := StrToFloatDef(Ini.ReadString(Sec, Key, ''), NaN, FS);
  end;

begin
  Clear;
  if not FileExists(FileName) then Exit;
  FS := FileFormatSettings;
  Ini := TIniFile.Create(FileName);
  try
    N := Ini.ReadInteger('Scan', 'Count', -1);
    if N < 0 then Exit;
    FHasScanned := True;
    SetLength(FItems, N);
    for i := 0 to N - 1 do begin
      Sec := 'Station' + IntToStr(i);
      FItems[i].ServiceLabel := Ini.ReadString(Sec, 'Label', '');
      FItems[i].SId := StrToIntDef('$' + Ini.ReadString(Sec, 'SId', '0'), 0);
      FItems[i].AudioType := Ini.ReadString(Sec, 'Type', '');
      FItems[i].SubChId := Ini.ReadInteger(Sec, 'SubChId', -1);
      FItems[i].EnsembleLabel := Ini.ReadString(Sec, 'Ensemble', '');
      FItems[i].EId := Ini.ReadInteger(Sec, 'EId', -1);
      FItems[i].BlockName := Ini.ReadString(Sec, 'Block', '');
      FItems[i].FreqHz := StrToQWordDef(Ini.ReadString(Sec, 'FreqHz', '0'), 0);
      FItems[i].SNRdB := D('SNRdB');
      FItems[i].MERdB := D('MERdB');
      FItems[i].FICOkPercent := D('FICOkPercent');
      FItems[i].ScannedAt := StrToDateTimeDef(Ini.ReadString(Sec, 'ScannedAt', ''), 0, FS);
    end;
  finally
    Ini.Free;
  end;
end;

end.
