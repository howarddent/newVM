unit uJetMain;

{*******************************************************************************

     Main form for the JetVent demo - the Lazarus port of the Delphi uMain.pas
     (TeeChart + MtxVec), drawing on a TVMPlot2D instead.

     Pick which cannulae to show, calculated and/or measured, in the two
     check groups, and which variable to plot in the radio group; the plot
     redraws on every change (there is no Plot button to press now). The
     seven driving pressures are the x axis for everything.

     Series are coloured by cannula and styled by kind: a calculated curve
     is a solid line, a measured one a dashed line through circle markers,
     so a cannula's two curves can be read against each other. The memo
     lists each calculated cannula's Reynolds number as before, and for
     the Mach and exit-velocity plots also the exit state at the highest
     driving pressure - temperature, density, exit pressure and whether
     the exit is choked - since that is what the corrected Mach number
     rests on (see uJetCalcVM.pas).

     Entrained flow and entrainment ratio have no calculated model (the
     original plotted the measured jet flow under the "calculated" label
     for entrainment, and zero for the ratio); here those two options
     draw the measured series only and the memo says so.

     Dropped from the original: the TeeChart SVG export and cursor tool.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  newVM, uJetCalcVM, uVMPlot2D;

type
  TPlotOption = (poFlow, poVelocity, poEntrain, poERatio, poMach, poStall22,
                 poStall15, poMassFlow, poExitVelocity);

  { TfmMain }

  TfmMain = class(TForm)
    cgCalculated: TCheckGroup;
    cgMeasured: TCheckGroup;
    memo: TMemo;
    pnlRight: TPanel;
    rgPlotOption: TRadioGroup;
    procedure cgCalculatedItemClick(Sender: TObject; Index: integer);
    procedure cgMeasuredItemClick(Sender: TObject; Index: integer);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure rgPlotOptionSelectionChanged(Sender: TObject);
  private
    FPlot: TVMPlot2D;
    FX: TVMobj;
    FCatheters: array[TJetCath] of TCatheter;
    procedure Replot;
  end;

var
  fmMain: TfmMain;

implementation

{$R *.lfm}

const
  CathColour: array[TJetCath] of TColor =
    ($B47719, $0E7FFF, $2CA02C, $2827D6, $BD6794, $4B568C);   // tab10 in BGR

{ TfmMain }

procedure TfmMain.FormCreate(Sender: TObject);
var
  c: TJetCath;
begin
  FX := DrivingPressures;
  for c := Low(TJetCath) to High(TJetCath) do
    FCatheters[c] := TCatheter.Create(c);

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.XAxisTitle := 'Driving pressure (bar gauge)';

  // Biro calculated and measured on by default, as the original
  cgCalculated.Checked[Ord(Biro)] := True;
  cgMeasured.Checked[Ord(Biro)] := True;
  Replot;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
var
  c: TJetCath;
begin
  for c := Low(TJetCath) to High(TJetCath) do
    FCatheters[c].Free;
end;

procedure TfmMain.cgCalculatedItemClick(Sender: TObject; Index: integer);
begin
  Replot;
end;

procedure TfmMain.cgMeasuredItemClick(Sender: TObject; Index: integer);
begin
  Replot;
end;

procedure TfmMain.rgPlotOptionSelectionChanged(Sender: TObject);
begin
  Replot;
end;

procedure TfmMain.Replot;
var
  Option: TPlotOption;
  c: TJetCath;
  Cath: TCatheter;
  Flow, Y: TVMobj;
  Series: array of TVMobj;
  n: Integer;

  { the y series for this option from a jet-flow vector; False when the
    option has no series of this kind (no calculated entrainment model) }
  function YFor(const Flow: TVMobj; Calculated: Boolean; out Y: TVMobj): Boolean;
  var
    i: Integer;
  begin
    Result := True;
    case Option of
      poFlow:         Y := Flow;
      poVelocity:     Y := Cath.Velocity(Flow);
      poMach:         Y := Cath.Mach(Flow);
      poExitVelocity: Y := Cath.ExitVelocity(Flow);
      poMassFlow:     Y := Cath.MassFlow(Flow);
      poStall15:      if Calculated then Y := Cath.Stall(Flow, 1.3e-2)
                      else Y := Cath.MeasuredStall15;
      poStall22:      if Calculated then Y := Cath.Stall(Flow, 2.2e-2)
                      else Y := Cath.MeasuredStall22;
      poEntrain:      begin
                        Result := not Calculated;
                        Y := Cath.EntrainedFlow;
                      end;
      poERatio:       begin
                        Result := not Calculated;
                        Y := TVMobj.Create(1, NumPressures);
                        for i := 0 to NumPressures - 1 do
                          Y[0, i] := (Cath.EntrainedFlow[0, i] - Flow[0, i]) / Flow[0, i];
                      end;
    end;
  end;

  procedure ReportExit(const Kind: string; const Flow: TVMobj);
  var
    E: TExitState;
    s: string;
  begin
    E := Cath.ExitState(Flow[0, NumPressures - 1]);
    if E.Choked then s := 'choked' else s := 'subsonic';
    memo.Lines.Add(Format('  %s at %.1f bar: Q/A = %.0f m/s, exit V = %.0f m/s, M = %.2f, T = %.0f K, rho = %.2f kg/m3, p = %.2f bar abs (%s)',
      [Kind, DrivingP[NumPressures - 1], Flow[0, NumPressures - 1] / (60000 * Cath.Area),
       E.Velocity, E.Mach, E.Temperature, E.Density, E.Pressure / One_Bar, s]));
  end;

begin
  Option := TPlotOption(rgPlotOption.ItemIndex);
  memo.Lines.BeginUpdate;
  try
    memo.Clear;
    case Option of
      poFlow:         begin FPlot.YAxisTitle := 'Flow l/min';        FPlot.Title := 'Jet flow vs driving pressure'; end;
      poVelocity:     begin FPlot.YAxisTitle := 'Velocity m/s';      FPlot.Title := 'Jet velocity Q/A (ambient density) vs driving pressure'; end;
      poEntrain:      begin FPlot.YAxisTitle := 'Flow l/min';        FPlot.Title := 'Total (entrained) flow vs driving pressure - measured only'; end;
      poERatio:       begin FPlot.YAxisTitle := 'Ratio';             FPlot.Title := 'Entrainment ratio vs driving pressure - measured only'; end;
      poMach:         begin FPlot.YAxisTitle := 'Mach number';       FPlot.Title := 'Exit Mach number vs driving pressure (exit temperature and density)'; end;
      poStall22:      begin FPlot.YAxisTitle := 'Pressure cmH2O';    FPlot.Title := 'Stall pressure into 22 mm vs driving pressure'; end;
      poStall15:      begin FPlot.YAxisTitle := 'Pressure cmH2O';    FPlot.Title := 'Stall pressure into 15 mm vs driving pressure'; end;
      poMassFlow:     begin FPlot.YAxisTitle := 'Mass flow g/s';     FPlot.Title := 'Mass flow vs driving pressure'; end;
      poExitVelocity: begin FPlot.YAxisTitle := 'Exit velocity m/s'; FPlot.Title := 'True exit velocity (exit density) vs driving pressure'; end;
    end;

    if Option in [poEntrain, poERatio] then
      memo.Lines.Add('No calculated model for entrainment - measured series only.');

    SetLength(Series, 2 * (Ord(High(TJetCath)) + 1));
    n := 0;

    for c := Low(TJetCath) to High(TJetCath) do
    begin
      Cath := FCatheters[c];

      if cgCalculated.Checked[Ord(c)] then
      begin
        Flow := Cath.CalcFlows(FX);
        memo.Lines.Add(Format('%s: Reynolds number %d, K-fitted flow %.1f l/min at %.1f bar',
          [Cath.Name, Cath.Reynolds_342, Flow[0, NumPressures - 1], DrivingP[NumPressures - 1]]));
        if Option in [poMach, poExitVelocity] then
          ReportExit('calculated', Flow);
        if YFor(Flow, True, Y) then
        begin
          Series[n] := Y;
          FPlot.SetSeriesStyle(n, CathColour[c], 2.0, plsSolid, Cath.Name + ' calculated');
          Inc(n);
        end;
      end;

      if cgMeasured.Checked[Ord(c)] then
      begin
        Flow := Cath.MeasuredFlow;
        if Option in [poMach, poExitVelocity] then
        begin
          if not cgCalculated.Checked[Ord(c)] then
            memo.Lines.Add(Cath.Name + ':');
          ReportExit('measured', Flow);
        end;
        if YFor(Flow, False, Y) then
        begin
          Series[n] := Y;
          FPlot.SetSeriesStyle(n, CathColour[c], 1.5, plsDash, Cath.Name + ' measured', pmsCircle, 6.0);
          Inc(n);
        end;
      end;
    end;

    if n = 0 then
    begin
      memo.Lines.Add('Nothing selected.');
      FPlot.SetSeriesStyle(0, clWhite, 1.0, plsNone, '');
      FPlot.SetData(FX, [TVMobj.Create(1, NumPressures)]);
    end
    else
    begin
      SetLength(Series, n);
      FPlot.SetData(FX, Series);
    end;
  finally
    memo.Lines.EndUpdate;
  end;
end;

end.
