program aortarun;

{ Pulse waves from the left ventricle to the wrist and the groin: the
  aorta, iliacs and left arm as one-dimensional finite-element vessels
  (uArtery1D, uAortaTree), driven by the finite-element ventricle's
  aortic valve flow.

  Options (defaults in brackets):
    --lv=<file>      the ventricle's beat, from lvrun --csv
                     [../LeftVentricle/out/beat.csv]
    --stiff=<x>      aortic elastance, times normal [1]
    --stiffother=<x> the same for the iliacs and the arm [1]
    --rtot=<R>       total peripheral resistance, mmHg s/mL [1.147]
    --walltau=<ms>   wall retardation time phi/E, ms [5]; 0 = elastic wall
    --cperiph=<C>    compliance of the lumped beds, mL/mmHg [0.8]; each bed
                     a matched Windkessel. 0: pure resistances
    --beats=<n>      cycles to run; the last is reported [25]
    --h=<cm>         element length [0.5]
    --cfl=<x>        fraction of the stable time step [0.6]
    --csv=<file>     the last beat's pressures and flows at the sites
    --field=<file>   pressure along the paths to the wrist and the groin
    --sweep          a table over aortic elastance 0.5, 1, 2, 4 instead
    --tree           list the vessels and the resistances

  Build:  fpc -O2 -FUlib aortarun.lpr }

{$mode delphi}{$H+}

uses
  SysUtils, StrUtils, Math, uArtery1D, uAortaTree;

function Opt(const Name: string; Def: Double): Double;
var
  i: Integer;
begin
  Result := Def;
  for i := 1 to ParamCount do
    if StartsText('--' + Name + '=', ParamStr(i)) then
      Result := StrToFloat(Copy(ParamStr(i), Length(Name) + 4, MaxInt));
end;

function OptS(const Name, Def: string): string;
var
  i: Integer;
begin
  Result := Def;
  for i := 1 to ParamCount do
    if StartsText('--' + Name + '=', ParamStr(i)) then
      Result := Copy(ParamStr(i), Length(Name) + 4, MaxInt);
end;

function Flag(const Name: string): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if SameText('--' + Name, ParamStr(i)) then Result := True;
end;

function NewSim: TAortaSim;
begin
  Result := TAortaSim.Create;
  Result.LV.Load(OptS('lv', '../LeftVentricle/out/beat.csv'));
  Result.AorticStiff := Opt('stiff', 1);
  Result.OtherStiff := Opt('stiffother', 1);
  Result.RTotal := Opt('rtot', Result.RTotal);
  Result.CPeriph := Opt('cperiph', Result.CPeriph);
  Result.WallTau := Opt('walltau', Result.WallTau);
  Result.Beats := Round(Opt('beats', Result.Beats));
  Result.HTarget := Opt('h', Result.HTarget);
  Result.CFL := Opt('cfl', Result.CFL);
end;

procedure ListTree(S: TAortaSim);
var
  i, ne: Integer;
begin
  Writeln('Vessel                     length    radius cm     wave speed m/s   elements  compliance');
  Writeln('                               cm    in     out       in     out              mL/mmHg');
  ne := 0;
  for i := 0 to High(S.Tree.Vessels) do
    with S.Tree.Vessels[i] do
    begin
      Writeln(Format('%-25s %6.1f  %5.3f  %5.3f   %6.2f  %6.2f   %6d    %7.4f',
        [Name, Len, RIn, ROut, C0[0] / 100, C0[NNode - 1] / 100, NNode - 1, Compliance * mmHg]));
      Inc(ne, NNode - 1);
    end;
  Writeln(Format('%d elements; compliance of the modelled vessels %.3f mL/mmHg, volume at 80 mmHg %.0f mL',
    [ne, S.Tree.Compliance * mmHg, S.Tree.Volume]));
  Writeln;
  Writeln('Beds: resistance, series impedance (mmHg s/mL), compliance (mL/mmHg), mean flow in the last beat');
  for i := 0 to High(S.Tree.J) do
    if S.Tree.J[i].G > 0 then
      Writeln(Format('  %-32s %7.1f  %6.2f  %6.3f   %6.2f mL/s  %5.1f %%', [S.Tree.J[i].Leaks,
        S.RTotal * 100 / S.Tree.J[i].Fraction, S.Tree.J[i].Zc / mmHg, S.Tree.J[i].C * mmHg, S.LeakMean[i], 100 * S.LeakMean[i] * S.LV.Period / S.VolIn]));
  Writeln;
end;

var
  S: TAortaSim;
  i, ir, ifm, ib: Integer;
  tick: QWord;
  x: Double;
const
  Factors: array[0..3] of Double = (0.5, 1, 2, 4);
begin
  FormatSettings.DecimalSeparator := '.';
  if Flag('sweep') then
  begin
    Writeln('Aortic     root           radial (wrist)   femoral        pulse wave speed m/s   transit ms');
    Writeln('elastance  sys/dia  PP    sys/dia  PP      sys/dia  PP    to femoral  to radial   femoral radial');
    for i := 0 to High(Factors) do
    begin
      S := NewSim;
      S.AorticStiff := Factors[i];
      S.Run;
      ir := S.ProbeIndex('left radial (wrist)'); ifm := S.ProbeIndex('left common femoral');
      Writeln(Format('  x %-4.1f   %3.0f/%-3.0f %4.0f    %3.0f/%-3.0f %4.0f     %3.0f/%-3.0f %4.0f     %6.2f     %6.2f      %5.0f  %5.0f',
        [Factors[i], S.Probes[0].Sys, S.Probes[0].Dia, S.Probes[0].Sys - S.Probes[0].Dia,
         S.Probes[ir].Sys, S.Probes[ir].Dia, S.Probes[ir].Sys - S.Probes[ir].Dia,
         S.Probes[ifm].Sys, S.Probes[ifm].Dia, S.Probes[ifm].Sys - S.Probes[ifm].Dia,
         S.Probes[ifm].PWV / 100, S.Probes[ir].PWV / 100,
         1000 * (S.Probes[ifm].TFoot - S.Probes[0].TFoot), 1000 * (S.Probes[ir].TFoot - S.Probes[0].TFoot)]));
      if OptS('csv', '') <> '' then
        S.WriteCSV(ChangeFileExt(OptS('csv', ''), '') + Format('_x%.1f.csv', [Factors[i]]));
      S.Free;
    end;
    Halt;
  end;

  S := NewSim;
  tick := GetTickCount64;
  S.Run;
  Writeln(Format('Ventricle: %s, %.1f /min, stroke volume through the valve %.1f mL',
    [OptS('lv', '../LeftVentricle/out/beat.csv'), 60 / S.LV.Period, S.LV.StrokeVolume]));
  Writeln(Format('Aortic elastance x %.2f, other vessels x %.2f; total peripheral resistance %.3f mmHg s/mL',
    [S.AorticStiff, S.OtherStiff, S.RTotal]));
  Writeln(Format('%d beats in %.1f s; last beat %d steps (mean %.0f us)',
    [S.Beats, (GetTickCount64 - tick) / 1000, S.Steps, 1e6 * S.LV.Period / S.Steps]));
  Writeln(Format('Last beat: pressures repeat to %.3f mmHg; volume in %.2f mL, out %.2f, stored %.3f',
    [S.PeriodicErr, S.VolIn, S.VolOut, S.VolStored]));
  Writeln;
  if Flag('tree') then ListTree(S);
  Writeln('Site                    from valve   systolic diastolic  mean   pulse   foot    peak   wave speed');
  Writeln('                                cm       mmHg     mmHg   mmHg   mmHg     ms      ms   from root m/s');
  for i := 0 to High(S.Probes) do
    with S.Probes[i] do
    begin
      Write(Format('%-24s %8.1f   %8.1f %8.1f %6.1f %6.1f %7.1f %7.0f',
        [Name, Dist, Sys, Dia, Mean, Sys - Dia, 1000 * TFoot, 1000 * TSys]));
      if Dist > 0 then Writeln(Format('   %7.2f', [PWV / 100])) else Writeln;
    end;
  ir := S.ProbeIndex('left radial (wrist)'); ib := S.ProbeIndex('left brachial (elbow)');
  ifm := S.ProbeIndex('left common femoral');
  Writeln;
  Writeln(Format('Pulse wave: valve to wrist %.0f ms (%.1f m/s over %.0f cm), valve to groin %.0f ms (%.1f m/s over %.1f cm)',
    [1000 * (S.Probes[ir].TFoot - S.Probes[0].TFoot), S.Probes[ir].PWV / 100, S.Probes[ir].Dist,
     1000 * (S.Probes[ifm].TFoot - S.Probes[0].TFoot), S.Probes[ifm].PWV / 100, S.Probes[ifm].Dist]));
  x := (S.Probes[ir].Sys - S.Probes[ir].Dia) / (S.Probes[0].Sys - S.Probes[0].Dia);
  Writeln(Format('Pulse pressure at the wrist is %.2f times that at the root (brachial %.2f, femoral %.2f)',
    [x, (S.Probes[ib].Sys - S.Probes[ib].Dia) / (S.Probes[0].Sys - S.Probes[0].Dia),
     (S.Probes[ifm].Sys - S.Probes[ifm].Dia) / (S.Probes[0].Sys - S.Probes[0].Dia)]));
  if OptS('csv', '') <> '' then
  begin
    S.WriteCSV(OptS('csv', ''));
    Writeln('Last beat written to ', OptS('csv', ''));
  end;
  if OptS('field', '') <> '' then
  begin
    S.WriteField(OptS('field', ''));
    Writeln('Pressure along the paths written to ', OptS('field', ''));
  end;
  S.Free;
end.
