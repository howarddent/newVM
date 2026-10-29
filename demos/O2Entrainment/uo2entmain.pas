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

unit uo2entmain;

{*******************************************************************************

     Main form for the O2Entrainment demo: the oxygen percentage a jet of
     oxygen delivers once it has entrained room air, against the
     entrainment ratio, on one TVMPlot2D (Graphs/uVMPlot2D.pas).

     THE MIXING RULE

     One volume of source gas at oxygen fraction Fs entrains R volumes of
     room air at Fa. Oxygen is conserved, so the mixture is

         F(R) = (Fs + Fa R) / (1 + R)

     and, the other way round, the ratio needed for a target F is

         R = (Fs - F) / (F - Fa).

     R is by volume, at the same temperature and pressure: litres of air
     per litre of oxygen, the form Venturi valve ratings are quoted in
     ("40 %: 3 : 1" etc). F falls from Fs at R = 0 towards Fa as R grows,
     steeply at first: most of the dilution happens in the first few
     volumes of air.

     The curve is one newVM vector expression over a linspace of R. There
     is no elementwise division operator (only by a scalar), so 1/(1 + R)
     is Exp(-Ln(1 + R)), as the Resonance demo does for D^(-1/2).

     WHAT IS MARKED

     - Venturi valves (check box): the six common colour-coded ratings,
       24, 28, 31, 35, 40 and 60 %. Their nominal air : O2 ratios are
       (100 - F)/(F - 21), i.e. for pure oxygen into 21 % air; the points
       are drawn at that ratio on the current curve, so with the default
       Fs and Fa they sit on it and with others they show what the same
       valve would deliver.
     - Trachea jet LES (check box): the entrainment ratio measured in the
       trachLESpeep run (Biro catheter, 4 bar, against +10 cmH2O auto-
       PEEP): 2.42 over the last 1 ms (14-15 ms) and 2.01 over 10-15 ms,
       from the glottis inflow against the jet's mass flow. That model has
       a single gas (the jet is air), so its mass ratio is also its volume
       ratio; the point shows what an oxygen jet entraining the same volume
       of air would deliver. The run ended before a steady state, the
       ratio still rising, so these are not final values.
     - Your ratio (spin edit): a marker and its read-out.

     The memo tabulates the valves and the inverse rule.

     --snapshot=<file.png> saves the plot and exits, for checking.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Spin,
  newVM, uVMPlot2D;

type

  { TForm1 }

  TForm1 = class(TForm)
    cbLES: TCheckBox;
    cbVenturi: TCheckBox;
    lblAmbient: TLabel;
    lblRatio: TLabel;
    lblRmax: TLabel;
    lblSource: TLabel;
    memResults: TMemo;
    pnlControls: TPanel;
    pnlPlot: TPanel;
    seAmbient: TFloatSpinEdit;
    seRatio: TFloatSpinEdit;
    seRmax: TFloatSpinEdit;
    seSource: TFloatSpinEdit;
    procedure ControlChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FPlot: TVMPlot2D;
    FSnapshot: string;
    procedure Replot;
    procedure DoSnapshot(Data: PtrInt);
  end;

var
  Form1: TForm1;

const
  NumPoints = 601;
  VenturiPct: array[0..5] of Double = (24, 28, 31, 35, 40, 60);
  LESRatio: array[0..1] of Double = (2.42, 2.01);
  LESLabel: array[0..1] of string = ('LES 14-15 ms', 'LES 10-15 ms');

implementation

{$R *.lfm}

{ The mixture's O2 fraction (same units as Fs, Fa) at ratio R. }
function MixO2(Fs, Fa, R: Double): Double;
begin
  Result := (Fs + Fa * R) / (1 + R);
end;

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := pnlPlot;
  FPlot.Align := alClient;
  FPlot.XAxisTitle := 'entrainment ratio  (volumes of air per volume of O2)';
  FPlot.YAxisTitle := 'O2 delivered (%)';
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'O2 % of the mixture');
  FPlot.SetSeriesStyle(1, clGray, 1.0, plsDot, 'room air');
  FPlot.SetSeriesStyle(2, clBlue, 1.0, plsNone, 'Venturi valve ratings', pmsDiamond, 9.0);
  FPlot.SetSeriesStyle(3, clBlack, 1.0, plsNone, 'trachea jet LES', pmsCircle, 8.0);
  FPlot.SetSeriesStyle(4, clGreen, 1.0, plsNone, 'your ratio', pmsSquare, 9.0);

  FSnapshot := '';
  for i := 1 to ParamCount do
    if Pos('--snapshot=', ParamStr(i)) = 1 then
      FSnapshot := Copy(ParamStr(i), 12, MaxInt);

  Replot;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if FSnapshot <> '' then
    Application.QueueAsyncCall(@DoSnapshot, 0);
end;

procedure TForm1.DoSnapshot(Data: PtrInt);
begin
  Application.ProcessMessages;
  if FPlot.SaveToPNG(FSnapshot) then
    WriteLn('saved ', FSnapshot)
  else
    WriteLn('could not save ', FSnapshot);
  WriteLn(memResults.Lines.Text);
  Application.Terminate;
end;

procedure TForm1.ControlChange(Sender: TObject);
begin
  if Assigned(FPlot) then
    Replot;
end;

procedure TForm1.Replot;
var
  Fs, Fa, Rmax, Ru, R, F, Rnom: Double;
  X, Y, Air: TVMobj;
  i: Integer;
begin
  Fs := seSource.Value;
  Fa := seAmbient.Value;
  Rmax := seRmax.Value;
  Ru := seRatio.Value;

  { F(R) = (Fs + Fa R) / (1 + R), as vectors: 1/(1 + R) = exp(-ln(1 + R)) }
  X := TVMobj.Create(1, NumPoints);
  X.linspace(0.0, Rmax / (NumPoints - 1));
  Y := AddScalar(Fa * X, Fs) * Exp(-Ln(AddScalar(X, 1.0)));
  Air := AddScalar(TVMobj.Create(1, NumPoints), Fa);   // Create zero-fills

  FPlot.ClearSeries;
  FPlot.ClearXMarkers;
  FPlot.Title := Format('O2 from a %.0f %% jet entraining %.1f %% room air', [Fs, Fa]);
  FPlot.SetData(X, [Y, Air]);

  if cbVenturi.Checked then
    for i := 0 to High(VenturiPct) do
    begin
      Rnom := (100 - VenturiPct[i]) / (VenturiPct[i] - 21);
      if Rnom <= Rmax then
        FPlot.PlotXY(Rnom, MixO2(Fs, Fa, Rnom), 2);
    end;

  if cbLES.Checked then
    for i := 0 to High(LESRatio) do   // no X marker: its caption would collide with yours
      FPlot.PlotXY(LESRatio[i], MixO2(Fs, Fa, LESRatio[i]), 3);

  if Ru <= Rmax then
  begin
    FPlot.PlotXY(Ru, MixO2(Fs, Fa, Ru), 4);
    FPlot.AddXMarker(Ru, clGreen, Format('%.2f : 1 -> %.1f %%', [Ru, MixO2(Fs, Fa, Ru)]));
  end;

  memResults.Lines.BeginUpdate;
  try
    memResults.Clear;
    memResults.Lines.Add(Format('F = (Fs + Fa R)/(1 + R)    R = (Fs - F)/(F - Fa)    Fs = %.1f %%, Fa = %.1f %%', [Fs, Fa]));
    memResults.Lines.Add(Format('Your ratio %.2f : 1  ->  %.1f %% O2;  total flow %.2f x the O2 flow', [Ru, MixO2(Fs, Fa, Ru), 1 + Ru]));
    memResults.Lines.Add('');
    memResults.Lines.Add('Valve    nominal air:O2   O2 % here   ratio needed here   L/min total per 10 L/min O2');
    for i := 0 to High(VenturiPct) do
    begin
      Rnom := (100 - VenturiPct[i]) / (VenturiPct[i] - 21);
      F := VenturiPct[i];
      if (F > Fa) and (F < Fs) then
        R := (Fs - F) / (F - Fa)
      else
        R := NaN;
      if IsNan(R) then
        memResults.Lines.Add(Format('%3.0f %%   %8.2f : 1     %7.1f       (not reachable)      %6.0f',
          [VenturiPct[i], Rnom, MixO2(Fs, Fa, Rnom), 10 * (1 + Rnom)]))
      else
        memResults.Lines.Add(Format('%3.0f %%   %8.2f : 1     %7.1f       %8.2f : 1          %6.0f',
          [VenturiPct[i], Rnom, MixO2(Fs, Fa, Rnom), R, 10 * (1 + Rnom)]));
    end;
    memResults.Lines.Add('');
    for i := 0 to High(LESRatio) do
      memResults.Lines.Add(Format('%s: entrainment %.2f : 1  ->  %.1f %% O2 if the jet were this source gas',
        [LESLabel[i], LESRatio[i], MixO2(Fs, Fa, LESRatio[i])]));
  finally
    memResults.Lines.EndUpdate;
  end;
end;

end.
