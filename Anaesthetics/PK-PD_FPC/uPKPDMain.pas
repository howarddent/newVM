unit uPKPDMain;

{*******************************************************************************

     Main form for the Anaesthetics/PK-PD_FPC demo: a redesigned clinical
     simulation UI (patient setup, drug/model pickers, a regimen designer,
     Run/Reset, plots) built on top of uModel3Comp.pas's TM3Comp, replacing
     the original Anaesthetics/PK-PD/uMain.pas's fixed tab-per-demo-button
     layout. See this project's approved plan for the rationale.

     Regimen modes and the TM3Comp method(s) each one drives:
       Bolus (RK4)               -> RK4_init_bolus_solve
       Bolus (RK45 adaptive)     -> RK45_init_bolus_solve
       Bolus (Kaps-Rentrop)      -> kaps_init_bolus_solve (uKapsRentrop.pas)
       Bolus (Analytic)          -> Analytic_initBolus_solve
       Constant Plasma Target    -> RK45_const_plasma_solve
       Constant Effect Target    -> RK45_const_effect_solve
       Bristol 10-8-6 Infusion   -> Bristol_10_8_6_Infusion
       Bristol 12-9-6 Infusion   -> Bristol_12_9_6_Infusion
                                    (both Bristol regimens are propofol
                                     protocols, so they're only listed when
                                     Drug A is Propofol - PopulateRegimenCombo)
       Constant Infusion Rate    -> RK45_bolus_infusion_solve
       Linked TCI (A drives B)   -> a propofol + remifentanil mixed syringe:
                                     ModelA (locked to Propofol/Marsh) runs
                                     RK45_const_plasma_solve; its computed
                                     infusion-rate row, plus the volume of its
                                     t=0 loading dose, is fed as-is into
                                     ModelB.Arbitrary_Infusion, so model B
                                     passively follows the same pump.

     There is no separate "bolus + infusion" regimen: every infusion-type
     regimen above (everything except the four plain Bolus regimens, where
     EditBolus.Text already *is* the entire dose) takes EditBolus.Text as an
     extra t=0 loading dose layered on top of whatever that regimen already
     computes - RK45_const_plasma/effect_solve's own Extra_Bolus parameter,
     Bristol_10_8_6/12_9_6_Infusion's and Arbitrary_Infusion's new
     ExtraBolus parameter, and RK45_bolus_infusion_solve's Bolus parameter
     directly. A non-zero Bolus field therefore always adds a bolus,
     regardless of which regimen is currently selected - set it to 0 to run
     a regimen with no loading dose.

     Every TM3Comp solve method returns a TVMobj with one row of elapsed
     time (minutes) and, for the "rate-tracking" methods (const-plasma/
     const-effect/Bristol/Arbitrary_Infusion), one row of infusion rate
     alongside the four state rows - see ExtractTimeState below for the
     per-method row layout each mode actually returns.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Dialogs,
  TAGraph, TASeries,
  newVM, uBodyStats, uModel3Comp, uPatientDialog;

type

  { TfmMain }

  TfmMain = class(TForm)
    PageControl1: TPageControl;
    TabSimulation: TTabSheet;
    TabDiagnostics: TTabSheet;
    PanelControls: TPanel;
    PanelCharts: TPanel;
    LabelPatient: TLabel;
    ButtonEditPatient: TButton;
    LabelDrugA: TLabel;
    cbDrugA: TComboBox;
    LabelModelA: TLabel;
    cbModelA: TComboBox;
    LabelRegimen: TLabel;
    cbRegimen: TComboBox;
    LabelDrugB: TLabel;
    cbDrugB: TComboBox;
    LabelModelB: TLabel;
    cbModelB: TComboBox;
    LabelTotalTime: TLabel;
    EditTotalTime: TEdit;
    LabelInterval: TLabel;
    EditInterval: TEdit;
    LabelTarget: TLabel;
    EditTarget: TEdit;
    LabelBolus: TLabel;
    EditBolus: TEdit;
    LabelBolusB: TLabel;
    EditBolusB: TEdit;
    LabelMixConcB: TLabel;
    EditMixConcB: TEdit;
    LabelConcA: TLabel;
    EditConcA: TEdit;
    LabelInfusionRate: TLabel;
    EditInfusionRate: TEdit;
    LabelStopTime: TLabel;
    EditStopTime: TEdit;
    ButtonRun: TButton;
    ButtonReset: TButton;
    MemoInfo: TMemo;
    ChartConc: TChart;
    SeriesC1: TLineSeries;
    SeriesCe: TLineSeries;
    SeriesBIS: TLineSeries;
    ChartRate: TChart;
    SeriesRate: TLineSeries;
    SeriesC1B: TLineSeries;
    SeriesCeB: TLineSeries;
    ChartLBW: TChart;
    SeriesLBWMale: TLineSeries;
    SeriesLBWFemale: TLineSeries;
    ChartKapsCompare: TChart;
    SeriesKapsC1: TLineSeries;
    SeriesRK45C1: TLineSeries;
    procedure FormCreate(Sender: TObject);
    procedure ButtonEditPatientClick(Sender: TObject);
    procedure cbDrugAChange(Sender: TObject);
    procedure cbDrugBChange(Sender: TObject);
    procedure cbRegimenChange(Sender: TObject);
    procedure ButtonRunClick(Sender: TObject);
    procedure ButtonResetClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure PanelChartsResize(Sender: TObject);
  private
    FWeight, FHeight : Double;
    FAge : TAge;
    FSex : TSex;
    FModelA, FModelB : TM3Comp;
    // ChartConc's left (concentration) and right (BIS) axes share one
    // TAChart extent (confirmed empirically - AxisIndexY/a fixed Range or
    // TAutoScaleAxisTransform on either axis still pulls the OTHER axis's
    // scale along with it, rather than giving each axis a genuinely
    // independent auto-range). Worked around entirely in code instead:
    // BIS's plotted values are rescaled from 0..100 onto the concentration
    // axis's own current range (FConcMax, recomputed every RunCurrentRegimen
    // call from the actual data), and BISMarkText relabels that axis's tick
    // marks back to the true 0..100 BIS scale - see both below.
    FConcMax : Double;
    procedure PopulateModelCombo(Drug: TDrugs; ModelCombo: TComboBox);
    procedure UpdateBolusUnitLabels;
    procedure UpdateLinkedTCIVisibility;
    procedure PopulateRegimenCombo(Drug: TDrugs);
    function CurrentMode: Integer;
    procedure UpdateMixConcLabel(ResetDefault: Boolean);
    procedure UpdateInfusateConc(ResetDefault: Boolean);
    procedure RebuildModels;
    procedure RunCurrentRegimen;
    procedure UpdatePatientLabel;
    procedure PlotDiagnostics;
    procedure BISMarkText(Sender: TObject; var AText: String; AMark: Double);
  public
  end;

var
  fmMain: TfmMain;

const
  // Mirrors TM3Comp.Create's own per-drug ValidModels sets (uModel3Comp.pas)
  // - duplicated here only so the UI can populate cbModelA/cbModelB without
  //   constructing a throwaway TM3Comp just to read the real table.
  DrugValidModelSets: array[TDrugs] of set of TModels = (
    [Marsh,Schneider,Paedfusor,Eleveld],  // Propofol
    [Schafer],                             // Fentanyl
    [Scott],                               // Alfentanil
    [Minto],                               // Remifentanil
    [Maitre],                              // Thiopentone
    [Geller],                              // Midazolam
    [Dyck,Hannivoort],                     // Dexmedetomidine
    [Domino]                               // Ketamine
  );
  // Drug B (the driven side of "Linked TCI") only ever makes sense as an
  // opioid/opioid-style adjunct co-administered alongside model A -
  // restricting cbDrugB to these keeps the picker from offering nonsensical
  // pairings (e.g. two hypnotics). Also doubles as the "mcg-dose" group for
  // bolus units (LabelBolus/LabelBolusB - see UpdateBolusUnitLabels) and the
  // ng/ml concentration scale (ConcDisplayScale): the three opioids plus
  // Dexmedetomidine (an alpha-2 agonist, not an opioid, but dosed/scaled the
  // same way - a real clinical adjunct infusion alongside a hypnotic, unlike
  // the drug this list used to contain here, Ketamine, which is a hypnotic
  // itself and never belongs in this group).
  McgDoseDrugs: array[0..3] of TDrugs = (Fentanyl, Alfentanil, Remifentanil, Dexmedetomidine);
  // What cbDrugB actually offers for Linked TCI: the McgDoseDrugs adjuncts
  // plus Ketamine, for a propofol/ketamine mixed syringe. Kept separate from
  // McgDoseDrugs because ketamine is mg-dosed and already mcg/ml in plasma,
  // so it must not pick up that group's mcg units or ng/ml display scaling.
  DrugBChoices: array[0..4] of TDrugs = (Fentanyl, Alfentanil, Remifentanil, Dexmedetomidine, Ketamine);

  // Fixed regimen numbers, carried in cbRegimen.Items.Objects[] - the list
  // is rebuilt per drug (the Bristol regimens are propofol-only), so an
  // item's list position is not its regimen. See PopulateRegimenCombo.
  RMBolusRK4 = 0; RMBolusRK45 = 1; RMBolusKaps = 2; RMBolusAnalytic = 3;
  RMConstPlasma = 4; RMConstEffect = 5; RMBristol1086 = 6; RMBristol1296 = 7;
  RMConstRate = 8; RMLinked = 9;
  RegimenNames: array[RMBolusRK4..RMLinked] of String = (
    'Bolus (RK4)', 'Bolus (RK45 adaptive)', 'Bolus (Kaps-Rentrop, stiff)',
    'Bolus (Analytic)', 'Constant Plasma Target', 'Constant Effect Target',
    'Bristol 10-8-6 Infusion', 'Bristol 12-9-6 Infusion',
    'Constant Infusion Rate', 'Linked TCI (A drives B)');

implementation

{$R *.lfm}

{ TfmMain }

procedure TfmMain.PopulateModelCombo(Drug: TDrugs; ModelCombo: TComboBox);
var
  Model : TModels;
begin
  ModelCombo.Items.Clear;
  for Model := Low(TModels) to High(TModels) do
    if Model in DrugValidModelSets[Drug] then
      ModelCombo.Items.Add(ModelNameStrings[Model]);
  ModelCombo.ItemIndex := 0;
end;

procedure TfmMain.cbDrugAChange(Sender: TObject);
begin
  PopulateModelCombo(TDrugs(cbDrugA.ItemIndex), cbModelA);
  PopulateRegimenCombo(TDrugs(cbDrugA.ItemIndex));
  UpdateBolusUnitLabels;
  UpdateInfusateConc(True);
  UpdateLinkedTCIVisibility;
end;

procedure TfmMain.cbDrugBChange(Sender: TObject);
begin
  PopulateModelCombo(DrugBChoices[cbDrugB.ItemIndex], cbModelB);
  UpdateBolusUnitLabels;
  UpdateMixConcLabel(True);
end;

procedure TfmMain.UpdateLinkedTCIVisibility;
var
  IsLinked, ShowConcA : Boolean;
begin
  IsLinked := CurrentMode = RMLinked;
  // Infusate strength for the constant infusions (plasma/effect TCI and
  // constant rate) - shares the mix box's row, which is hidden outside
  // Linked TCI. The Bristol regimens are fixed 1% propofol protocols, so no box.
  ShowConcA := CurrentMode in [RMConstPlasma, RMConstEffect, RMConstRate];
  LabelConcA.Visible := ShowConcA;
  EditConcA.Visible := ShowConcA;
  LabelDrugB.Visible := IsLinked;
  cbDrugB.Visible := IsLinked;
  LabelModelB.Visible := IsLinked;
  cbModelB.Visible := IsLinked;
  LabelBolusB.Visible := IsLinked;
  EditBolusB.Visible := IsLinked;
  LabelMixConcB.Visible := IsLinked;
  EditMixConcB.Visible := IsLinked;
  // Model A is fixed to Propofol/Marsh while linked (see cbRegimenChange).
  cbDrugA.Enabled := not IsLinked;
  cbModelA.Enabled := not IsLinked;
end;

procedure TfmMain.BISMarkText(Sender: TObject; var AText: String; AMark: Double);
begin
  // AMark arrives in the shared graph-value space BIS was rescaled into
  // (see the FConcMax comment on its declaration) - convert back to the
  // true 0-100 BIS value for display.
  if FConcMax > 0 then
    AText := FormatFloat('0', AMark * 100 / FConcMax)
  else
    AText := '0';
end;

procedure TfmMain.cbRegimenChange(Sender: TObject);
var
  i : Integer;
begin
  // Linked TCI is a propofol (Marsh) mixed syringe - pin model A to that,
  // and default drug B to Remifentanil on entry (Ketamine etc. can then be
  // picked instead).
  if CurrentMode = RMLinked then begin
    cbDrugA.ItemIndex := Ord(Propofol);
    PopulateModelCombo(Propofol, cbModelA);
    cbModelA.ItemIndex := cbModelA.Items.IndexOf(ModelNameStrings[Marsh]);
    PopulateRegimenCombo(Propofol); // restores the Bristol entries, keeps Linked TCI selected
    for i := Low(DrugBChoices) to High(DrugBChoices) do
      if DrugBChoices[i] = Remifentanil then cbDrugB.ItemIndex := i;
    PopulateModelCombo(DrugBChoices[cbDrugB.ItemIndex], cbModelB);
    UpdateBolusUnitLabels;
    UpdateMixConcLabel(True);
    UpdateInfusateConc(True);
    // The TCI computes its own loading dose. Bolus A's bolus-mode default
    // (140 mg) would be drawn from the same mixed syringe on top of it,
    // carrying ~4x the intended drug B load and overshooting the propofol
    // target - so both extra boluses start at zero here.
    EditBolus.Text := '0';
    EditBolusB.Text := '0';
  end;
  UpdateLinkedTCIVisibility;
end;

procedure TfmMain.UpdatePatientLabel;
var
  SexStr : String;
begin
  if FSex = Male then SexStr := 'Male' else SexStr := 'Female';
  LabelPatient.Caption := Format('Patient: %.0f kg, %.2f m, age %d, %s  (BMI %.1f)',
    [FWeight, FHeight, FAge, SexStr, BMI(FWeight, FHeight)]);
end;

procedure TfmMain.ButtonEditPatientClick(Sender: TObject);
begin
  PatientDialogForm.Weight := FWeight;
  PatientDialogForm.Height := FHeight;
  PatientDialogForm.Age := FAge;
  PatientDialogForm.Sex := FSex;
  PatientDialogForm.LoadFromFields;
  if PatientDialogForm.ShowModal = mrOK then begin
    FWeight := PatientDialogForm.Weight;
    FHeight := PatientDialogForm.Height;
    FAge := PatientDialogForm.Age;
    FSex := PatientDialogForm.Sex;
    UpdatePatientLabel;
    RebuildModels;
    RunCurrentRegimen;
  end;
end;

procedure TfmMain.RebuildModels;
var
  DrugA, DrugB : TDrugs;
  ModelNameA, ModelNameB : String;
  ModelA, ModelB, M : TModels;
begin
  DrugA := TDrugs(cbDrugA.ItemIndex);
  ModelNameA := cbModelA.Text;
  ModelA := Low(TModels);
  for M := Low(TModels) to High(TModels) do
    if ModelNameStrings[M] = ModelNameA then ModelA := M;

  FreeAndNil(FModelA);
  FModelA := TM3Comp.Create(DrugA, ModelA, Round(FWeight), FHeight, FAge, FSex);

  // Always build model B too, even when its picker is hidden for the
  // current regimen mode - it's cheap (pure arithmetic plus one 4x4
  // eigendecomposition), and keeps it ready the instant the user switches
  // to "Linked TCI" without needing a separate rebuild step. cbDrugB only
  // lists a subset of drugs (see DrugBChoices), so its ItemIndex must be
  // mapped through that array, not cast to TDrugs directly.
  DrugB := DrugBChoices[cbDrugB.ItemIndex];
  ModelNameB := cbModelB.Text;
  ModelB := Low(TModels);
  for M := Low(TModels) to High(TModels) do
    if ModelNameStrings[M] = ModelNameB then ModelB := M;
  FreeAndNil(FModelB);
  FModelB := TM3Comp.Create(DrugB, ModelB, Round(FWeight), FHeight, FAge, FSex);
end;

// Extracts the time row and the C1 (plasma)/Ce (effect) rows from a solve
// result, regardless of which row layout the originating method used - see
// this unit's header comment for the per-method layout.
procedure ExtractTimeC1Ce(const R: TVMobj; HasRateRow, IsKaps: Boolean;
  out T, C1, Ce: TVMobj);
var
  TimeRow, C1Row, CeRow : Integer;
begin
  if IsKaps then begin
    TimeRow := 4; C1Row := 0; CeRow := 3;
  end else if HasRateRow then begin
    TimeRow := 0; C1Row := 2; CeRow := 5;
  end else begin
    TimeRow := 0; C1Row := 1; CeRow := 4;
  end;
  T := SubMatrix(R, TimeRow, 0, 1, R.Cols);
  C1 := SubMatrix(R, C1Row, 0, 1, R.Cols);
  Ce := SubMatrix(R, CeRow, 0, 1, R.Cols);
end;

// True for the four McgDoseDrugs (the three opioids plus Dexmedetomidine) -
// see that array's own comment for why they're grouped together (mcg bolus
// dosing, ng/ml plasma display) rather than mg/mcg-ml like the hypnotics.
function IsMcgDoseDrug(Drug: TDrugs): Boolean;
var
  i : Integer;
begin
  result := False;
  for i := Low(McgDoseDrugs) to High(McgDoseDrugs) do
    if McgDoseDrugs[i] = Drug then begin
      result := True;
      Exit;
    end;
end;

// The left concentration axis is labelled mcg/ml for hypnotics and ng/ml
// for opioids - opioid C1/Ce need dividing by 1000 to read correctly on
// that ng/ml scale (per direct observation against the running app).
function ConcDisplayScale(Drug: TDrugs): Double;
begin
  if IsMcgDoseDrug(Drug) then result := 1/1000 else result := 1.0;
end;

// Keeps LabelBolus/LabelBolusB's units in sync with whichever drug is
// currently selected: mg for the hypnotics (Propofol/Midazolam/
// Thiopentone/Ketamine), mcg for the McgDoseDrugs group Drug B is always
// drawn from. Called from cbDrugAChange/cbDrugBChange and once from
// FormCreate (ItemIndex assignments made directly in code don't fire
// OnChange, so FormCreate has to trigger this explicitly - same reasoning
// as its own explicit cbRegimenChange(nil) call).
procedure TfmMain.UpdateBolusUnitLabels;
begin
  if IsMcgDoseDrug(TDrugs(cbDrugA.ItemIndex)) then
    LabelBolus.Caption := 'Bolus A (mcg):'
  else
    LabelBolus.Caption := 'Bolus A (mg):';
  if IsMcgDoseDrug(DrugBChoices[cbDrugB.ItemIndex]) then
    LabelBolusB.Caption := 'Bolus B (mcg):'
  else
    LabelBolusB.Caption := 'Bolus B (mg):';
end;

// Rebuilds cbRegimen for Drug. Each item's Objects[] slot carries its fixed
// RM* regimen number, so RunCurrentRegimen dispatches by regimen rather than
// list position - the Bristol regimens are propofol-only and are left out
// for every other drug, which shifts the later items up. Keeps the current
// regimen selected if it's still offered, otherwise selects the first.
procedure TfmMain.PopulateRegimenCombo(Drug: TDrugs);
var
  Prev, i, m : Integer;
begin
  Prev := CurrentMode;
  cbRegimen.Items.Clear;
  for m := Low(RegimenNames) to High(RegimenNames) do
    if (Drug = Propofol) or not (m in [RMBristol1086, RMBristol1296]) then
      cbRegimen.Items.AddObject(RegimenNames[m], TObject(PtrInt(m)));
  cbRegimen.ItemIndex := 0;
  for i := 0 to cbRegimen.Items.Count-1 do
    if PtrInt(cbRegimen.Items.Objects[i]) = Prev then cbRegimen.ItemIndex := i;
end;

function TfmMain.CurrentMode: Integer;
begin
  if cbRegimen.ItemIndex < 0 then
    result := -1
  else
    result := PtrInt(cbRegimen.Items.Objects[cbRegimen.ItemIndex]);
end;

// Mixed-syringe strength box for Drug B in Linked TCI: mg/ml for ketamine
// (mg-dosed, as in a propofol/ketamine mix), mcg/ml for the mcg-dosed
// adjuncts. ResetDefault puts back that drug's typical mix strength - 10
// mg/ml ketamine, or 20 mcg/ml (e.g. 1 mg remifentanil in 50 ml propofol 1%).
procedure TfmMain.UpdateMixConcLabel(ResetDefault: Boolean);
var
  DrugB : TDrugs;
begin
  DrugB := DrugBChoices[cbDrugB.ItemIndex];
  if DrugB = Ketamine then begin
    LabelMixConcB.Caption := 'Ketamine in mix (mg/ml):';
    if ResetDefault then EditMixConcB.Text := '10';
  end else begin
    if DrugB = Remifentanil then
      LabelMixConcB.Caption := 'Remi in mix (mcg/ml):'
    else
      LabelMixConcB.Caption := 'Drug B in mix (mcg/ml):';
    if ResetDefault then EditMixConcB.Text := '20';
  end;
end;

// Infusate strength box for Drug A's constant infusions: mcg/ml for the
// mcg-dosed drugs, mg/ml for the hypnotics - the same units as TM3Comp's own
// Concentration. ResetDefault fills in that drug's TM3Comp Concentration
// (e.g. 500 mcg/ml alfentanil), read from a throwaway instance (the value
// depends only on the drug, so any valid model/patient will do). A drug
// used as Linked TCI's drug B has its own mix box and default instead - see
// UpdateMixConcLabel (e.g. 20 mcg/ml alfentanil in a propofol mix).
procedure TfmMain.UpdateInfusateConc(ResetDefault: Boolean);
var
  Drug : TDrugs;
  Model, M : TModels;
  Tmp : TM3Comp;
begin
  Drug := TDrugs(cbDrugA.ItemIndex);
  if IsMcgDoseDrug(Drug) then
    LabelConcA.Caption := 'Infusate (mcg/ml):'
  else
    LabelConcA.Caption := 'Infusate (mg/ml):';
  if ResetDefault then begin
    Model := Low(TModels);
    for M := High(TModels) downto Low(TModels) do
      if M in DrugValidModelSets[Drug] then Model := M;
    Tmp := TM3Comp.Create(Drug, Model, Round(FWeight), FHeight, FAge, FSex);
    try
      EditConcA.Text := FloatToStr(Tmp.fModelParams.Concentration);
    finally
      Tmp.Free;
    end;
  end;
end;

procedure PlotSeries(const T, Y: TVMobj; Series: TLineSeries);
var
  i : Integer;
begin
  Series.Clear;
  for i := 0 to T.Cols-1 do
    Series.AddXY(T[0,i], Y[0,i]);
end;

function MaxElementOf(const A: TVMobj): Double;
var
  i : Integer;
begin
  result := 0;
  for i := 0 to A.Cols-1 do
    if A[0,i] > result then result := A[0,i];
end;

procedure TfmMain.RunCurrentRegimen;
var
  TotalTime, Interval, Target, Bolus, BolusB, StopTime, InfusionRate, MixConcB, ConcA : Double;
  R, S, T, TB, C1, Ce, C1B, CeB, Rate, DrivingRate : TVMobj;
  i : Integer;
  Mode : Integer;
begin
  if not TryStrToFloat(EditTotalTime.Text, TotalTime) then TotalTime := 20;
  if not TryStrToFloat(EditInterval.Text, Interval) then Interval := 10;
  if not TryStrToFloat(EditTarget.Text, Target) then Target := 3;
  if not TryStrToFloat(EditBolus.Text, Bolus) then Bolus := 140;
  if not TryStrToFloat(EditBolusB.Text, BolusB) then BolusB := Bolus;
  if not TryStrToFloat(EditInfusionRate.Text, InfusionRate) then InfusionRate := 200;
  if not TryStrToFloat(EditStopTime.Text, StopTime) then StopTime := TotalTime;
  if not TryStrToFloat(EditMixConcB.Text, MixConcB) or (MixConcB <= 0) then
    if FModelB.fdrug = Ketamine then MixConcB := 10 else MixConcB := 20;
  if not TryStrToFloat(EditConcA.Text, ConcA) or (ConcA <= 0) then
    ConcA := FModelA.fModelParams.Concentration; // the drug's own TM3Comp default

  SeriesC1.Clear; SeriesCe.Clear; SeriesBIS.Clear;
  SeriesRate.Clear; SeriesC1B.Clear; SeriesCeB.Clear;

  Mode := CurrentMode; // an RM* regimen number, not the list position
  case Mode of
    0: R := FModelA.RK4_init_bolus_solve(Bolus, TotalTime, Interval);
    1: R := FModelA.RK45_init_bolus_solve(Bolus, TotalTime, Interval);
    2: R := FModelA.kaps_init_bolus_solve(Bolus, TotalTime, Interval);
    3: R := FModelA.Analytic_initBolus_solve(Bolus, TotalTime, Interval);
    // Modes 4-9 are all infusion-type regimens - each takes EditBolus.Text
    // as an extra t=0 loading dose on top of whatever the regimen itself
    // computes, rather than as a separate "bolus + infusion" dropdown entry
    // (see this unit's header comment).
    // Modes 4, 5 and 8 draw from a syringe of the strength in EditConcA
    // (mg/ml or mcg/ml), which sets the mL/hr each reports and, for mode 8,
    // the drug mass a given mL/hr delivers. Safe to overwrite: RebuildModels
    // recreates FModelA on every run.
    4: begin
         FModelA.fModelParams.Concentration := ConcA;
         R := FModelA.RK45_const_plasma_solve(Bolus, Target, TotalTime, StopTime, Interval);
       end;
    5: begin
         FModelA.fModelParams.Concentration := ConcA;
         R := FModelA.RK45_const_effect_solve(Bolus, Target, TotalTime, StopTime, Interval);
       end;
    6: R := FModelA.Bristol_10_8_6_Infusion(FWeight, TotalTime, Interval, Bolus);
    7: R := FModelA.Bristol_12_9_6_Infusion(FWeight, TotalTime, Interval, Bolus);
    8: begin
         FModelA.fModelParams.Concentration := ConcA;
         R := FModelA.RK45_bolus_infusion_solve(Bolus, InfusionRate, TotalTime, StopTime, Interval);
       end;
    9: begin
         // Mixed syringe: propofol (model A, locked to Marsh - see
         // cbRegimenChange) runs a constant plasma TCI; drug B (e.g.
         // remifentanil or ketamine) passively follows, receiving whatever
         // volume the pump delivers.
         R := FModelA.RK45_const_plasma_solve(Bolus, Target, TotalTime, StopTime, Interval);
         // Infusion: drop R's t=0 column (index 0), feed the remaining
         // NumSteps interval rates (mL/hr) straight into model B.
         DrivingRate := SubMatrix(R, 1, 1, 1, R.Cols-1);
         // Model B's mg or mcg per mL delivered is the mix strength the user made
         // up (EditMixConcB), not its neat-stock default - Arbitrary_Infusion
         // converts every mL (rate and loading volume) via Concentration.
         // Safe to overwrite: RebuildModels recreates FModelB on every run.
         FModelB.fModelParams.Concentration := MixConcB;
         // Loading: the TCI's own t=0 dose (Target*V1 + Bolus, mg) comes out
         // of the same syringe, so model B gets the matching volume
         // (mL = mg / propofol mg/ml) as Arbitrary_Infusion's mL-of-stock
         // Bolus. BolusB is a separate direct mg/mcg dose (LabelBolusB's units),
         // so it goes in as ExtraBolus, not the mL-based Bolus.
         S := FModelB.Arbitrary_Infusion(DrivingRate,
           (Target * FModelA.fModelParams.V1 + Bolus) / FModelA.fModelParams.Concentration,
           TotalTime, Interval, BolusB);
       end;
  else
    Exit;
  end;

  ExtractTimeC1Ce(R, Mode in [4,5,6,7,8,9], Mode = 2, T, C1, Ce);
  C1 := C1 * ConcDisplayScale(FModelA.fdrug);
  Ce := Ce * ConcDisplayScale(FModelA.fdrug);
  FConcMax := Max(MaxElementOf(C1), MaxElementOf(Ce));

  if Mode = 9 then begin
    ExtractTimeC1Ce(S, True, False, TB, C1B, CeB);
    // Linked TCI plots Drug B on the same axis as Drug A (propofol, mcg/ml).
    // An mcg-dosed adjunct (e.g. remifentanil, ng/ml) is shown x1000 so it
    // reads at a comparable scale rather than hugging zero; ketamine is
    // already mcg/ml, so it's plotted as-is.
    if IsMcgDoseDrug(FModelB.fdrug) then begin
      C1B := C1B * (ConcDisplayScale(FModelB.fdrug) * 1000);
      CeB := CeB * (ConcDisplayScale(FModelB.fdrug) * 1000);
      SeriesC1B.Title := 'Plasma B (C1) x1000';
      SeriesCeB.Title := 'Effect B (Ce) x1000';
    end else begin
      SeriesC1B.Title := 'Plasma B (C1)';
      SeriesCeB.Title := 'Effect B (Ce)';
    end;
    FConcMax := Max(FConcMax, Max(MaxElementOf(C1B), MaxElementOf(CeB)));
  end;
  FConcMax := FConcMax * 1.15; // headroom so the topmost curve isn't clipped at the axis edge

  PlotSeries(T, C1, SeriesC1);
  PlotSeries(T, Ce, SeriesCe);
  if FModelA.fdrug = Propofol then begin
    // BIS shares the concentration axis (see the FConcMax comment on its
    // declaration) - rescale its 0-100 value onto that axis's current
    // range; BISMarkText undoes this for the tick labels. Ce is already in
    // display units here, but propofol's own ConcDisplayScale is always 1
    // (only the opioid group gets rescaled), so it's also the raw value
    // BIS() needs.
    SeriesBIS.Clear;
    for i := 0 to T.Cols-1 do
      SeriesBIS.AddXY(T[0,i], FModelA.BIS(Ce[0,i]) * FConcMax / 100);
  end;

  // Bolus/Analytic modes have no rate row of their own (the dose is
  // delivered instantaneously at t=0, then the infusion rate is genuinely
  // zero throughout) - plot a flat zero line rather than leaving the chart
  // empty, so it always shows something meaningful.
  if Mode in [4,5,6,7,8,9] then
    Rate := SubMatrix(R, 1, 0, 1, R.Cols)
  else
    Rate := TVMobj.Create(1, T.Cols);
  PlotSeries(T, Rate, SeriesRate);

  if Mode = 9 then begin
    PlotSeries(TB, C1B, SeriesC1B);
    PlotSeries(TB, CeB, SeriesCeB);
  end;

  MemoInfo.Lines.Clear;
  MemoInfo.Lines.Add('Model A: '+FModelA.fModelParams.DrugName+' / '+FModelA.fModelParams.ModelName);
  MemoInfo.Lines.Add('  V1='+FloatToStrF(FModelA.fModelParams.V1,ffFixed,6,2)+
    '  V2='+FloatToStrF(FModelA.fModelParams.V2,ffFixed,6,2)+
    '  V3='+FloatToStrF(FModelA.fModelParams.V3,ffFixed,6,2));
  if Mode = 9 then begin
    MemoInfo.Lines.Add('Model B: '+FModelB.fModelParams.DrugName+' / '+FModelB.fModelParams.ModelName);
    MemoInfo.Lines.Add('  V1='+FloatToStrF(FModelB.fModelParams.V1,ffFixed,6,2)+
      '  V2='+FloatToStrF(FModelB.fModelParams.V2,ffFixed,6,2)+
      '  V3='+FloatToStrF(FModelB.fModelParams.V3,ffFixed,6,2));
  end;
end;

procedure TfmMain.PlotDiagnostics;
const
  NumPoints = 100;
var
  i : Integer;
  W : Double;
  K, RK, T, C1, Ce : TVMobj;
begin
  SeriesLBWMale.Clear;
  SeriesLBWFemale.Clear;
  for i := 0 to NumPoints do begin
    W := 30 + (170.0/NumPoints)*i;
    SeriesLBWMale.AddXY(W, freeFatMass(24, Male, W, 1.75));
    SeriesLBWFemale.AddXY(W, freeFatMass(24, Female, W, 1.75));
  end;

  // Kaps-Rentrop vs RK45 plasma-concentration comparison, same bolus/time
  // span - see uModel3Comp.pas's header comment on the off-by-one fix that
  // now makes both reach the same final time.
  K := FModelA.kaps_init_bolus_solve(140, 20, 10);
  ExtractTimeC1Ce(K, False, True, T, C1, Ce);
  PlotSeries(T, C1, SeriesKapsC1);
  RK := FModelA.RK45_init_bolus_solve(140, 20, 10);
  ExtractTimeC1Ce(RK, False, False, T, C1, Ce);
  PlotSeries(T, C1, SeriesRK45C1);
end;

procedure TfmMain.FormCreate(Sender: TObject);
var
  D : TDrugs;
  i : Integer;
begin
  for D := Low(TDrugs) to High(TDrugs) do
    cbDrugA.Items.Add(DrugNameStrings[D]);
  for i := Low(DrugBChoices) to High(DrugBChoices) do
    cbDrugB.Items.Add(DrugNameStrings[DrugBChoices[i]]);
  cbDrugA.ItemIndex := 0; // Propofol
  cbDrugB.ItemIndex := 2; // Remifentanil - the classic co-induction pairing
  PopulateModelCombo(TDrugs(cbDrugA.ItemIndex), cbModelA);
  PopulateModelCombo(DrugBChoices[cbDrugB.ItemIndex], cbModelB);
  UpdateBolusUnitLabels;
  UpdateMixConcLabel(True);

  PopulateRegimenCombo(TDrugs(cbDrugA.ItemIndex));
  cbRegimen.ItemIndex := 0;
  cbRegimenChange(nil);

  FWeight := 70; FHeight := 1.75; FAge := 35; FSex := Male;
  UpdatePatientLabel;

  EditTotalTime.Text := '20';
  EditInterval.Text := '10';
  EditTarget.Text := '3';
  EditBolus.Text := '140';
  EditBolusB.Text := '50';
  UpdateInfusateConc(True); // drug A's own TM3Comp Concentration (needs the patient fields above)
  EditInfusionRate.Text := '200';
  EditStopTime.Text := '20';

  ChartConc.AxisList[2].OnGetMarkText := @BISMarkText;

  RebuildModels;
  RunCurrentRegimen;
  PlotDiagnostics;
end;

procedure TfmMain.ButtonRunClick(Sender: TObject);
begin
  RebuildModels;
  RunCurrentRegimen;
end;

procedure TfmMain.ButtonResetClick(Sender: TObject);
begin
  RebuildModels;
  RunCurrentRegimen;
end;

// ChartConc (alTop) takes 60% of the chart panel's height, ChartRate
// (alClient) the rest - kept proportional as the form is resized.
procedure TfmMain.PanelChartsResize(Sender: TObject);
begin
  ChartConc.Height := Round(PanelCharts.ClientHeight * 0.6);
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FModelA.Free;
  FModelB.Free;
end;

end.
