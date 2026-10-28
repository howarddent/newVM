unit ujetflowmain;

{*******************************************************************************

     Main form for the JetFlow calculator.

     Enter the driving pressure (bar gauge), the jet's internal diameter
     (mm) and its length (cm); everything recalculates on each change.
     The gas is oxygen at 20 C into 1 atm, as in JetVent.

     The cannula box fills in the bore and length of one of JetVent's six
     bench cannulae (TJetCath), and while it is selected the calculation
     uses JetVent's whole definition of it - its inlet loss and, for the
     Lindholm, its 45 degree bend. Editing either value afterwards
     sets the box back to "Custom" unless it still matches a cannula; a
     custom cannula is straight, with the metal cannulas' inlet loss.
     FUpdating stops the programmatic edits recalculating, or resetting
     the box, part-way.

     With a cannula selected, a check box shows its measured jet flow
     beside the calculated one: JetVent's bench values at 0.5 .. 3.5 bar
     (DrivingP), linearly interpolated to the driving pressure, with the
     calculated flow's difference from it; and in the memo, the whole
     bench series against the calculated flows. Outside 0.5 .. 3.5 bar it
     says so rather than extrapolating. Only the display changes: every
     result still comes from the calculated flow. (JetVent's Cook data
     repeat the Lindholm's measured flows exactly, so the two show the
     same bench values.)

     For a cannula of that bore and length (TCatheter.CreateCustom in
     ../JetVent/uJetCalcVM.pas) it shows:
       - the flow, from JetVent's Crane 3-20 estimate (CalcFlow);
       - whether the jet is choked, from the exit state the flow implies
         (ExitState: a sonic exit). Crane's own test, the pressure ratio
         against the critical one, can call a flow choked while the exit
         Mach number is still just below 1; the indicator shows that case
         amber as borderline, red for a sonic exit, green otherwise;
       - the highest Mach number and lowest temperature in the jet:
         at the exit if it is subsonic, otherwise in the free jet after
         expanding to ambient (FreeJet), where it is supersonic;
       - the lowest pressure: ambient, which the jet reaches at the exit
         if subsonic and after expanding if choked (the exit pressure is
         given beside it). The shock cells of a real under-expanded jet
         dip below ambient for a short way; that is not modelled;
       - the thrust, F = m V_e + (p_e - p_amb) A (TCatheter.Thrust);
       - the stall pressure (cmH2O) into tracheas of three editable
         diameters - an adult male, an adult female and a 7-year-old
         child; defaults 20, 16 and 10 mm are typical values, not from a
         particular reference - by JetVent's formula,
         rho Q^2 / (A_jet A_trachea) / 100 (TCatheter.StallPressure).
         That is the jet's momentum at room density spread over the
         airway. Against the bench stall pressures into a 22 mm circuit
         at 3.5 bar it is 4 % high for the 14G, 10 % high for the Biro,
         11 % low for the Lindholm and 18-33 % low for the Cook, 16G and
         18G; thrust over the airway area, also in the memo, is 29-52 %
         low (the Biro 9 %). The Cook's 15 mm measurements are well above
         it (75 cmH2O at 3.5 bar against about 51), so in narrow airways
         it is likely to underestimate.
     The memo has the working: Reynolds number, K, Crane's pressure
     ratios, the exit and free-jet states and the two parts of the thrust,
     and a warning when K is outside the Crane A-22 table (1.2 .. 100).

     Command line: --p=<bar gauge>, --d=<mm>, --l=<cm>, and
     --cannula=<1..6> (JetVent's order: Lindholm, Cook, Biro, 14G, 16G,
     18G; 0 is Custom), applied before --d and --l, and --measured.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Spin,
  uJetCalcVM;

type

  { TfmJetFlow }

  TfmJetFlow = class(TForm)
    gbInput: TGroupBox;
    gbResults: TGroupBox;
    lblP: TLabel;
    lblD: TLabel;
    lblL: TLabel;
    lblGas: TLabel;
    lblCannula: TLabel;
    cbCannula: TComboBox;
    cbMeasured: TCheckBox;
    lblMeasured: TLabel;
    seP: TFloatSpinEdit;
    seD: TFloatSpinEdit;
    seL: TFloatSpinEdit;
    lblFlowCap: TLabel;
    lblFlow: TLabel;
    shpChoked: TShape;
    lblChoked: TLabel;
    lblMachCap: TLabel;
    lblMach: TLabel;
    lblTempCap: TLabel;
    lblTemp: TLabel;
    lblPressCap: TLabel;
    lblPress: TLabel;
    lblThrustCap: TLabel;
    lblThrust: TLabel;
    gbStall: TGroupBox;
    lblAirway: TLabel;
    lblStallHdr: TLabel;
    lblMale: TLabel;
    seMale: TFloatSpinEdit;
    lblStallMale: TLabel;
    lblFemale: TLabel;
    seFemale: TFloatSpinEdit;
    lblStallFemale: TLabel;
    lblChild: TLabel;
    seChild: TFloatSpinEdit;
    lblStallChild: TLabel;
    memo: TMemo;
    procedure cbCannulaChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure InputChange(Sender: TObject);
  private
    FUpdating: Boolean;
    // bore (mm) and length (cm) of JetVent's cannulae, by TJetCath
    FCanD, FCanL: array[TJetCath] of Double;
    FCanName: array[TJetCath] of string;
    FCanFlow: array[TJetCath, 0..NumPressures - 1] of Double;   // measured l/min
    function MeasuredFlowAt(c: TJetCath; P: Double; out Flow: Double): Boolean;
    procedure MatchCannula;
    procedure Recalculate;
  end;

var
  fmJetFlow: TfmJetFlow;

implementation

{$R *.lfm}

const
  KelvinToC = 273.15;
  PaPerCmH2O = 98.0665;

{ a percentage with its sign, e.g. '+3 %' - FPC's Format has no '+' flag }
function SignedPct(x: Double): string;
begin
  Result := Format('%.0f %%', [x]);
  if Round(x) > 0 then Result := '+' + Result;
end;

{ TfmJetFlow }

procedure TfmJetFlow.FormCreate(Sender: TObject);
var
  c: TJetCath;
  Cath: TCatheter;
  i: Integer;
begin
  FUpdating := True;
  cbCannula.Items.Clear;
  cbCannula.Items.Add('Custom');
  for c := Low(TJetCath) to High(TJetCath) do
  begin
    Cath := TCatheter.Create(c);
    try
      FCanD[c] := Cath.Diameter * 1000;
      FCanL[c] := Cath.Length * 100;
      FCanName[c] := Cath.Name;
      for i := 0 to NumPressures - 1 do
        FCanFlow[c, i] := Cath.MeasuredFlow[0, i];
      cbCannula.Items.Add(Format('%s  (%.2f mm, %.1f cm)', [Cath.Name, FCanD[c], FCanL[c]]));
    finally
      Cath.Free;
    end;
  end;
  cbCannula.ItemIndex := 0;
  cbMeasured.Checked := Application.HasOption('measured');
  FUpdating := False;

  if Application.HasOption('cannula') then
  begin
    cbCannula.ItemIndex := StrToIntDef(Application.GetOptionValue('cannula'), 0);
    cbCannulaChange(nil);
  end;
  if Application.HasOption('p') then
    seP.Value := StrToFloatDef(Application.GetOptionValue('p'), seP.Value);
  if Application.HasOption('d') then
    seD.Value := StrToFloatDef(Application.GetOptionValue('d'), seD.Value);
  if Application.HasOption('l') then
    seL.Value := StrToFloatDef(Application.GetOptionValue('l'), seL.Value);
  MatchCannula;
  Recalculate;
end;

procedure TfmJetFlow.cbCannulaChange(Sender: TObject);
var
  c: TJetCath;
begin
  if cbCannula.ItemIndex <= 0 then Exit;   // Custom: keep the values
  c := TJetCath(cbCannula.ItemIndex - 1);
  FUpdating := True;
  try
    seD.Value := FCanD[c];
    seL.Value := FCanL[c];
  finally
    FUpdating := False;
  end;
  Recalculate;
end;

{ Measured jet flow of cannula c at P bar gauge, linear between the bench
  pressures; False outside them }
function TfmJetFlow.MeasuredFlowAt(c: TJetCath; P: Double; out Flow: Double): Boolean;
var
  i: Integer;
  f: Double;
begin
  Flow := 0;
  Result := (P >= DrivingP[0] - 1e-9) and (P <= DrivingP[NumPressures - 1] + 1e-9);
  if not Result then Exit;
  i := 0;
  while (i < NumPressures - 2) and (P > DrivingP[i + 1]) do Inc(i);
  f := (P - DrivingP[i]) / (DrivingP[i + 1] - DrivingP[i]);
  Flow := FCanFlow[c, i] + f * (FCanFlow[c, i + 1] - FCanFlow[c, i]);
end;

{ Shows the cannula the bore and length match, or Custom }
procedure TfmJetFlow.MatchCannula;
var
  c: TJetCath;
  Found: Integer;
begin
  Found := 0;
  for c := Low(TJetCath) to High(TJetCath) do
    if (Abs(seD.Value - FCanD[c]) < 0.005) and (Abs(seL.Value - FCanL[c]) < 0.05) then
    begin
      Found := Ord(c) + 1;
      Break;
    end;
  if cbCannula.ItemIndex <> Found then
  begin
    FUpdating := True;
    try
      cbCannula.ItemIndex := Found;
    finally
      FUpdating := False;
    end;
  end;
end;

procedure TfmJetFlow.InputChange(Sender: TObject);
begin
  if FUpdating then Exit;
  if (Sender = seD) or (Sender = seL) then MatchCannula;
  Recalculate;
end;

procedure TfmJetFlow.Recalculate;
var
  Cath: TCatheter;
  P, Q, K, CritP, Y, Thrust, Momentum: Double;
  Sonic: Boolean;
  E: TExitState;
  J: TFreeJetState;
  SelCath: TJetCath;
  ShowBench: Boolean;
  Qm: Double;
  i: Integer;

  // stall pressure into a trachea of diameter DMM (mm): the result label,
  // and a memo line with the thrust-based figure beside it
  procedure ShowStall(const Who: string; DMM: Double; Lbl: TLabel);
  var
    Dm, Pst: Double;
  begin
    Dm := DMM / 1000;
    if Dm <= Cath.Diameter then
    begin
      Lbl.Caption := 'n/a (no wider than the jet)';
      memo.Lines.Add(Format('  %-13s %5.1f mm: no wider than the jet', [Who, DMM]));
      Exit;
    end;
    Pst := Cath.StallPressure(Q, Dm);
    Lbl.Caption := Format('%.1f cmH2O', [Pst]);
    memo.Lines.Add(Format('  %-13s %5.1f mm: %6.1f cmH2O   (thrust / area %6.1f)',
      [Who, DMM, Pst, Thrust / (Pi * Sqr(Dm / 2)) / PaPerCmH2O]));
  end;

begin
  P := seP.Value;
  if (P <= 0) or (seD.Value <= 0) or (seL.Value <= 0) then Exit;
  if cbCannula.ItemIndex > 0 then
    Cath := TCatheter.Create(TJetCath(cbCannula.ItemIndex - 1))
  else
    Cath := TCatheter.CreateCustom('Custom', seL.Value / 100, seD.Value / 1000);
  try
    K := Cath.ResistanceK;
    CritP := CalcCritPRatio(K, Y);
    Q := Cath.CalcFlow(P, Sonic);
    E := Cath.ExitState(Q);
    J := FreeJet(E);
    Thrust := Cath.Thrust(E);
    Momentum := E.MassFlow * E.Velocity;

    lblFlow.Caption := Format('%.1f l/min', [Q]);

    cbMeasured.Enabled := cbCannula.ItemIndex > 0;
    ShowBench := cbMeasured.Enabled and cbMeasured.Checked;
    SelCath := Low(TJetCath);
    if ShowBench then
    begin
      SelCath := TJetCath(cbCannula.ItemIndex - 1);
      if MeasuredFlowAt(SelCath, P, Qm) then
        lblMeasured.Caption := Format('measured %.1f l/min (calc. %s)',
          [Qm, SignedPct(100 * (Q - Qm) / Qm)])
      else
        lblMeasured.Caption := 'measured: only at 0.5 - 3.5 bar';
    end
    else
      lblMeasured.Caption := '';

    if E.Choked then
    begin
      shpChoked.Brush.Color := clRed;
      lblChoked.Caption := 'CHOKED: sonic exit, jet under-expanded';
    end
    else if Sonic then
    begin
      shpChoked.Brush.Color := $0000A5FF;   // orange
      lblChoked.Caption := Format('Borderline: Crane says choked, exit Mach %.3f', [E.Mach]);
    end
    else
    begin
      shpChoked.Brush.Color := clLime;
      lblChoked.Caption := 'Not choked: subsonic exit';
    end;

    if E.Choked then
      lblMach.Caption := Format('%.2f  (free jet, expanded to ambient)', [J.Mach])
    else
      lblMach.Caption := Format('%.2f  (at the exit)', [J.Mach]);
    lblTemp.Caption := Format('%.1f K  (%.1f °C)', [J.Temperature, J.Temperature - KelvinToC]);
    lblPress.Caption := Format('%.3f bar abs (ambient); exit %.3f bar abs',
      [J.Pressure / 1e5, E.Pressure / 1e5]);
    lblThrust.Caption := Format('%.3f N  (%.0f gf)', [Thrust, 1000 * Thrust / 9.80665]);

    memo.Lines.BeginUpdate;
    try
      memo.Lines.Clear;
      memo.Lines.Add(Format('Oxygen: gamma %.2f, R %.1f J/(kg K), %.3f kg/m3 at 20 °C and 1 atm.',
        [Gamma_O2, R_O2, O2_Density_RT]));
      memo.Lines.Add(Format('Cannula: %s, %.2f mm bore, %.1f cm long (L/D %.0f)',
        [Cath.Name, seD.Value, seL.Value, Cath.Length / Cath.Diameter]));
      memo.Lines.Add(Format('Reynolds number (at 342 m/s, as JetVent): %d', [Cath.Reynolds_342]));
      memo.Lines.Add(Format('Resistance K = inlet %.1f + f L/D %.2f + bend %.2f + outlet 1 = %.2f',
        [Cath.InletK, K - Cath.InletK - Cath.BendExcessK - 1, Cath.BendExcessK, K]));
      if (K < 1.2) or (K > 100) then
        memo.Lines.Add('  WARNING: K is outside the Crane A-22 table (1.2 .. 100); the critical '
          + 'pressure ratio and expansion factor are extrapolated.');
      memo.Lines.Add(Format('Crane: pressure ratio dP/P1 %.3f, critical %.3f -> %s; Y %.3f',
        [P / (P + 1), CritP, BoolToStr(Sonic, 'sonic', 'subsonic'), Y]));
      if ShowBench then
      begin
        memo.Lines.Add('');
        memo.Lines.Add(Format('Bench jet flow, %s (JetVent), against calculated:', [FCanName[SelCath]]));
        memo.Lines.Add('  bar gauge  measured  calculated  difference');
        for i := 0 to NumPressures - 1 do
          memo.Lines.Add(Format('  %6.1f    %7.1f    %7.1f     %7s',
            [DrivingP[i], FCanFlow[SelCath, i], Cath.CalcFlow(DrivingP[i]),
             SignedPct(100 * (Cath.CalcFlow(DrivingP[i]) - FCanFlow[SelCath, i]) / FCanFlow[SelCath, i])]));
      end;
      memo.Lines.Add('');
      memo.Lines.Add(Format('Flow %.2f l/min (at room conditions); mass flow %.3f g/s',
        [Q, 1000 * E.MassFlow]));
      memo.Lines.Add(Format('Exit: Mach %.3f, velocity %.1f m/s, %.1f K, %.3f bar abs, %.3f kg/m3',
        [E.Mach, E.Velocity, E.Temperature, E.Pressure / 1e5, E.Density]));
      memo.Lines.Add(Format('  stagnation pressure at the exit %.3f bar abs (driving %.3f bar abs)',
        [J.ExitStagPressure / 1e5, (P + 1) * One_Bar / 1e5]));
      if E.Choked then
        memo.Lines.Add(Format('Free jet, ideally expanded to ambient: Mach %.3f, %.1f m/s, %.1f K',
          [J.Mach, J.Velocity, J.Temperature]))
      else
        memo.Lines.Add('Free jet: the exit is already at ambient pressure.');
      memo.Lines.Add('');
      memo.Lines.Add(Format('Thrust %.4f N = momentum m V_e %.4f N + pressure (p_e - p_amb) A %.4f N',
        [Thrust, Momentum, Thrust - Momentum]));
      if E.Choked then
        memo.Lines.Add('Shock cells in a real under-expanded jet overshoot ambient pressure '
          + 'and the expanded Mach number for a short way; not modelled.');
      memo.Lines.Add('');
      memo.Lines.Add('Stall pressure, rho Q^2 / (A_jet A_trachea) as JetVent; '
        + 'likely to underestimate in narrow airways:');
      ShowStall('Adult male', seMale.Value, lblStallMale);
      ShowStall('Adult female', seFemale.Value, lblStallFemale);
      ShowStall('Child 7 yr', seChild.Value, lblStallChild);
    finally
      memo.Lines.EndUpdate;
    end;
  finally
    Cath.Free;
  end;
end;

end.
