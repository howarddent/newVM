unit uDABScanForm;

{*******************************************************************************

     TDABScanForm - the window for uDABScanner.pas's TDABScanner: pick all
     Band III blocks or one, scan, and see each ensemble found and the
     stations it carries, with how well it is being received.

     Built entirely in code (CreateNew, no .lfm), the same way uSDRMain.pas
     builds its receiver panel. Non-modal, so the main window's spectrum
     shows each block as the scan steps through it.

     Getting the radio into a state a scan can use - connected, streaming,
     at 2.048 Msps - is the main form's job, since it owns those controls;
     it supplies that as OnPrepare, which Scan calls first.

     One row per station. SNR, MER and FIC are per ensemble (they describe
     the multiplex, which every station on it shares) and so repeat down
     each ensemble's rows; see uDABDecoder.pas for what each measures. A
     block with a DAB signal that couldn't be decoded gets a single row
     saying so, since "something is there but too weak" is worth knowing
     when positioning an aerial; blocks with nothing at all are only
     counted in the status line.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  uSDRRFSource, uDABDecoder, uDABScanner;

type
  TDABPrepareEvent = function(out Msg: string): Boolean of object;

  { TDABScanForm }
  TDABScanForm = class(TForm)
  private
    FScanner: TDABScanner;
    FOnPrepare: TDABPrepareEvent;
    FOnScanFinished: TNotifyEvent;
    FTopPanel: TPanel;
    FScanButton: TButton;
    FBlockCombo: TComboBox;
    FProgress: TProgressBar;
    FStatusLabel: TLabel;
    FList: TListView;
    FEnsembles, FStations, FEmpty: Integer;
    procedure ScanButtonClick(Sender: TObject);
    procedure ScannerChannelStart(Sender: TObject; Index, Count: Integer; const Channel: TDABChannel);
    procedure ScannerChannelResult(Sender: TObject; const R: TDABScanResult);
    procedure ScannerFinished(Sender: TObject; Aborted: Boolean; const Msg: string);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure AddRow(const R: TDABScanResult; const Station, SIdText, AudioType: string);
    function Summary: string;
  public
    constructor CreateFor(AOwner: TComponent; ASource: TSDRRFSource);
    procedure StopScan;
    // Scans every block, as if "All blocks" were chosen and Scan pressed.
    procedure StartFullScan;
    property Scanner: TDABScanner read FScanner;
    property OnPrepare: TDABPrepareEvent read FOnPrepare write FOnPrepare;
    // After every scan, complete or stopped part way - Scanner.Results
    // holds the blocks it did visit.
    property OnScanFinished: TNotifyEvent read FOnScanFinished write FOnScanFinished;
  end;

implementation

function FmtDB(V: Double): string;
begin
  if IsNan(V) then Result := '-' else Result := Format('%.1f', [V]);
end;

constructor TDABScanForm.CreateFor(AOwner: TComponent; ASource: TSDRRFSource);
var
  i: Integer;

  procedure AddCol(const Cap: string; W: Integer; Right: Boolean = False);
  var C: TListColumn;
  begin
    C := FList.Columns.Add;
    C.Caption := Cap;
    C.Width := W;
    if Right then C.Alignment := taRightJustify;
  end;

begin
  inherited CreateNew(AOwner);
  Caption := 'DAB Scan';
  Width := 900;
  Height := 560;
  Position := poOwnerFormCenter;
  OnCloseQuery := @FormCloseQuery;

  FScanner := TDABScanner.Create(Self);
  FScanner.Source := ASource;
  FScanner.OnChannelStart := @ScannerChannelStart;
  FScanner.OnChannelResult := @ScannerChannelResult;
  FScanner.OnFinished := @ScannerFinished;

  FTopPanel := TPanel.Create(Self);
  FTopPanel.Parent := Self;
  FTopPanel.Align := alTop;
  FTopPanel.Height := 70;
  FTopPanel.BevelOuter := bvNone;

  FBlockCombo := TComboBox.Create(Self);
  FBlockCombo.Parent := FTopPanel;
  FBlockCombo.SetBounds(10, 10, 150, 23);
  FBlockCombo.Style := csDropDownList;
  FBlockCombo.Items.Add('All blocks (5A-13F)');
  for i := 0 to UKDABChannelCount - 1 do
    FBlockCombo.Items.Add(Format('%s  %.3f MHz', [UKDABChannels[i].Name, UKDABChannels[i].FreqHz / 1e6]));
  FBlockCombo.ItemIndex := 0;

  FScanButton := TButton.Create(Self);
  FScanButton.Parent := FTopPanel;
  FScanButton.SetBounds(170, 9, 100, 25);
  FScanButton.Caption := 'Scan';
  FScanButton.OnClick := @ScanButtonClick;

  FProgress := TProgressBar.Create(Self);
  FProgress.Parent := FTopPanel;
  FProgress.SetBounds(285, 12, 300, 18);
  FProgress.Min := 0;
  FProgress.Max := UKDABChannelCount;

  FStatusLabel := TLabel.Create(Self);
  FStatusLabel.Parent := FTopPanel;
  FStatusLabel.SetBounds(10, 44, 860, 15);
  FStatusLabel.Caption := 'Scanning retunes the radio to 2.048 Msps. Turn on Bias-T in the main window if your aerial needs it.';

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.GridLines := True;
  AddCol('Block', 55);
  AddCol('MHz', 70, True);
  AddCol('Ensemble', 150);
  AddCol('Station', 160);
  AddCol('SId', 55);
  AddCol('Type', 50);
  AddCol('SNR dB', 65, True);
  AddCol('MER dB', 65, True);
  AddCol('FIC OK %', 70, True);
  AddCol('Freq err Hz', 80, True);
end;

procedure TDABScanForm.StopScan;
begin
  FScanner.Stop;
end;

procedure TDABScanForm.StartFullScan;
begin
  if FScanner.Scanning then Exit;
  FBlockCombo.ItemIndex := 0;
  ScanButtonClick(Self);
end;

procedure TDABScanForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  FScanner.Stop;
  CanClose := True;
end;

procedure TDABScanForm.ScanButtonClick(Sender: TObject);
var
  Msg: string;
begin
  if FScanner.Scanning then begin
    FScanButton.Enabled := False;
    FScanner.Stop;   // ScannerFinished re-enables
    Exit;
  end;

  if Assigned(FOnPrepare) and not FOnPrepare(Msg) then begin
    FStatusLabel.Caption := 'Cannot scan: ' + Msg;
    Exit;
  end;

  if FBlockCombo.ItemIndex <= 0 then
    FScanner.SetChannels([])
  else
    FScanner.SetChannels([UKDABChannels[FBlockCombo.ItemIndex - 1].Name]);

  FList.Items.Clear;
  FEnsembles := 0; FStations := 0; FEmpty := 0;
  FProgress.Max := FScanner.ChannelCount;
  FProgress.Position := 0;
  if not FScanner.Start(Msg) then begin
    FStatusLabel.Caption := 'Cannot scan: ' + Msg;
    Exit;
  end;
  FScanButton.Caption := 'Stop';
  FBlockCombo.Enabled := False;
end;

function TDABScanForm.Summary: string;
begin
  Result := Format('%d ensemble(s), %d station(s); %d block(s) empty', [FEnsembles, FStations, FEmpty]);
end;

procedure TDABScanForm.ScannerChannelStart(Sender: TObject; Index, Count: Integer;
  const Channel: TDABChannel);
begin
  FProgress.Position := Index;
  FStatusLabel.Caption := Format('Scanning %s (%.3f MHz), block %d of %d - %s',
    [Channel.Name, Channel.FreqHz / 1e6, Index + 1, Count, Summary]);
end;

procedure TDABScanForm.AddRow(const R: TDABScanResult; const Station, SIdText, AudioType: string);
var
  It: TListItem;
begin
  It := FList.Items.Add;
  It.Caption := R.Channel.Name;
  It.SubItems.Add(Format('%.3f', [R.Channel.FreqHz / 1e6]));
  It.SubItems.Add(R.EnsembleLabel);
  It.SubItems.Add(Station);
  It.SubItems.Add(SIdText);
  It.SubItems.Add(AudioType);
  It.SubItems.Add(FmtDB(R.SNRdB));
  It.SubItems.Add(FmtDB(R.MERdB));
  It.SubItems.Add(Format('%.0f', [R.FICOkPercent]));
  if IsNan(R.FreqOffsetHz) then It.SubItems.Add('-')
  else It.SubItems.Add(Format('%.0f', [R.FreqOffsetHz]));
end;

procedure TDABScanForm.ScannerChannelResult(Sender: TObject; const R: TDABScanResult);
var
  Order: array of Integer;
  i, j, t: Integer;
  Station: string;
begin
  FProgress.Position := FProgress.Position + 1;
  if not R.Found then begin
    if R.Locked then AddRow(R, '(DAB signal, too weak to decode)', '', '')
    else Inc(FEmpty);
    Exit;
  end;
  Inc(FEnsembles);
  if Length(R.Services) = 0 then begin
    AddRow(R, '(no services listed yet)', '', '');
    Exit;
  end;

  // Alphabetical by station name, unnamed ones last.
  SetLength(Order, Length(R.Services));
  for i := 0 to High(Order) do Order[i] := i;
  for i := 1 to High(Order) do begin
    t := Order[i]; j := i - 1;
    while (j >= 0) and (
      ((R.Services[Order[j]].ServiceLabel = '') and (R.Services[t].ServiceLabel <> '')) or
      ((R.Services[Order[j]].ServiceLabel <> '') and (R.Services[t].ServiceLabel <> '') and
       (CompareText(R.Services[Order[j]].ServiceLabel, R.Services[t].ServiceLabel) > 0))) do begin
      Order[j + 1] := Order[j]; Dec(j);
    end;
    Order[j + 1] := t;
  end;

  for i := 0 to High(Order) do begin
    Station := R.Services[Order[i]].ServiceLabel;
    if Station = '' then Station := '(name not received)';
    AddRow(R, Station, IntToHex(R.Services[Order[i]].SId, 4), R.Services[Order[i]].AudioType);
    Inc(FStations);
  end;
end;

procedure TDABScanForm.ScannerFinished(Sender: TObject; Aborted: Boolean; const Msg: string);
begin
  FScanButton.Caption := 'Scan';
  FScanButton.Enabled := True;
  FBlockCombo.Enabled := True;
  if Aborted then begin
    FStatusLabel.Caption := 'Scan stopped (' + Msg + ') - ' + Summary;
  end else begin
    FProgress.Position := FProgress.Max;
    FStatusLabel.Caption := 'Scan complete - ' + Summary;
  end;
  if Assigned(FOnScanFinished) then FOnScanFinished(Self);
end;

end.
