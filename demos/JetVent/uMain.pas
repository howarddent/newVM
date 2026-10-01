unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, uJetCalc, VCLTee.TeEngine,
  VCLTee.Series, MtxVecTee, Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart,mtxVec,mtxExpr,Math387,
  VCLTee.TeeTools;

type
  Tcatheters = array [TJetCath] of TCatheter;
  TYValues = array [TJetCath] of vector;
  TCatheterSeries = array[TJetCath] of TChartSeries;
  TJetSet = Set of TJetCath;
  TplotOption = (Flow,Velocity,Entrain,E_Ratio,Mach,Stall22,Stall15,Mass_Flow);

type
  TfmMain = class(TForm)
    Memo1: TMemo;
    Chart1: TChart;
    btnPlot: TButton;
    Panel1: TPanel;
    cbCookActual: TCheckBox;
    cb14Actual: TCheckBox;
    cb18Actual: TCheckBox;
    cbBiroActual: TCheckBox;
    cb16Actual: TCheckBox;
    cb18Calc: TCheckBox;
    cb16Calc: TCheckBox;
    cb14Calc: TCheckBox;
    cbCookCalc: TCheckBox;
    cbBiroCalc: TCheckBox;
    Label1: TLabel;
    Label2: TLabel;
    rgPlotOption: TRadioGroup;
    SaveDialog1: TSaveDialog;
    cbLindholm: TCheckBox;
    cbLindholmActual: TCheckBox;
    btnExport: TButton;
    btnCursor: TButton;
    procedure FormCreate(Sender: TObject);
    procedure btnPlotClick(Sender: TObject);
    procedure cbBiroCalcClick(Sender: TObject);
    procedure cbBiroActualClick(Sender: TObject);
    procedure cbCookCalcClick(Sender: TObject);
    procedure cbCookActualClick(Sender: TObject);
    procedure cb14CalcClick(Sender: TObject);
    procedure cb14ActualClick(Sender: TObject);
    procedure cb16CalcClick(Sender: TObject);
    procedure cb16ActualClick(Sender: TObject);
    procedure cb18CalcClick(Sender: TObject);
    procedure cb18ActualClick(Sender: TObject);
    procedure rgPlotOptionClick(Sender: TObject);
    procedure btnExportClick(Sender: TObject);
    procedure cbLindholmClick(Sender: TObject);
    procedure cbLindholmActualClick(Sender: TObject);
    procedure btnCursorClick(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    ActualCatheters : TCatheters;
    CalculatedCatheters : TCatheters;
    PlotCalculated : TJetSet;
    PlotActual : TJetSet;
    YValues : TYValues;
    XValues : Vector;
    CatheterSeries : TcatheterSeries;
    PlotOption : TPlotOption;
    CursorOn :Boolean;
    MyCursor : TCursorTool;
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}
uses
  VCLTee.TeeSVGCanvas;


procedure TfmMain.btnCursorClick(Sender: TObject);
begin
  CursorOn := not CursorOn;
  if cursorOn and (Chart1.SeriesCount<> 0) then begin
    MyCursor:=TCursorTool.Create(Self);
    MyCursor.ParentChart:=Chart1;
    MyCursor.Series:=Chart1.Series[0];
    MyCursor.FollowMouse := True;
    MyCursor.AxisAnnotation.Active := True;
    btnCursor.Caption := 'Cursor off';

  end
  else begin
    if Not CursorOn  then begin
      MyCursor.Free;
      btnCursor.Caption := 'Cursor on';
    end;
  end;
end;

procedure TfmMain.btnExportClick(Sender: TObject);
var
  tmp : TSVGExportFormat;
  AFileName: String;
begin

  tmp := TSVGexportFormat.Create;
  try
    tmp.Panel := Chart1;
    if SaveDialog1.Execute(Self.Handle)  then
      tmp.SaveToFile(SaveDialog1.Filename);
  finally
    tmp.Free;
  end;
end;


procedure TfmMain.btnPlotClick(Sender: TObject);
var
  Catheter : TJetCath;
  i,count : integer;
  TempFlow : Vector;
begin
  memo1.Lines.Clear;
  TempFlow.Length:= Xvalues.Length;
  Chart1.RemoveAllSeries;
  count :=0;
  with chart1 do
    case PlotOption of
      Flow: begin LeftAxis.Title.Caption:= 'Flow l/s'; Title.Caption := 'Flow vs DP' end;
      Velocity: begin LeftAxis.Title.Caption:= 'Velocity m/s'; Title.Caption := 'Jet Velocity vs DP' end;
      Entrain: begin LeftAxis.Title.Caption:= 'Flow l/s'; Title.Caption := 'Total Flow vs DP' end;
      E_Ratio:begin LeftAxis.Title.Caption:= 'Ratio'; Title.Caption := 'Entrainment Ratio vs DP' end;
      Mach: begin LeftAxis.Title.Caption:= 'Mach Number'; Title.Caption := 'Catheter Tip Mach No vs DP' end;
      Stall15: begin LeftAxis.Title.Caption:= 'Pressure cmH20'; Chart1.Title.Caption := 'Stall pressure into 15mm vs DP' end;
      Stall22:  begin LeftAxis.Title.Caption:= 'Pressure cmH20'; Chart1.Title.Caption := 'Stall pressure into 22mm vs DP' end;
      Mass_Flow : begin LeftAxis.Title.Caption:= 'Mass flow kg/s x 1000'; Chart1.Title.Caption := 'Mass flow x 1000 vs DP' end;
    end;
  try
    for Catheter in PlotCalculated do begin
      CalculatedCatheters[Catheter] := TCatheter.Create(Catheter);
      Chart1.AddSeries(TMtxFastLineSeries.Create(Self));
      CatheterSeries[Catheter] := Chart1[count];
      CatheterSeries[Catheter].Title:= CalculatedCatheters[Catheter].Name +' Calculated';
      YValues[Catheter].Length := XValues.Length;
      inc(count);
      with CalculatedCatheters[Catheter] do
        memo1.Lines.Add(Name+' Reynolds Number : '+IntToStr(Reynolds_342));
    end;
    for Catheter in PlotCalculated do begin
      for i := 0 to XValues.Length do begin
        TempFlow[i] :=  CalculatedCatheters[Catheter].calc_Flow(Xvalues[i]);
        case Plotoption of
          Flow: YValues[Catheter][i] := tempFlow[i];
          Velocity: YValues[Catheter][i] := CalculatedCatheters[Catheter].calc_velocity(tempflow[i]) ;
          Mach: YValues[Catheter][i] := CalculatedCatheters[Catheter].calc_velocity(tempflow[i]) /342;
          Entrain :  YValues[Catheter][i] :=CalculatedCatheters[Catheter].MeasuredFlow[i];
          E_Ratio : YValues[Catheter][i] := 0;
          Stall15: YValues[Catheter][i] :=
            CalculatedCatheters[Catheter].calc_stall(TempFlow[i],1.3e-2);
          Stall22: YValues[Catheter][i] :=
            CalculatedCatheters[Catheter].calc_stall(TempFlow[i],2.2e-2);
          Mass_Flow :YValues[Catheter][i]:=
             XValues[i]- (0.5*O2_Density_RT*sqr(CalculatedCatheters[Catheter].calc_Velocity(tempflow[i])))/One_Bar;
        end;
      end;
      DrawValues(XValues,YValues[Catheter],CatheterSeries[Catheter]);
  end;
  finally
    for Catheter in PlotCalculated do begin
      CalculatedCatheters[Catheter].Free;
    end;
  end;
  try
    for Catheter in PlotActual  do begin
      ActualCatheters[Catheter] := TCatheter.Create(Catheter);
      Chart1.AddSeries(TMtxFastLineSeries.Create(Self));
      CatheterSeries[Catheter] := Chart1[count];
      CatheterSeries[Catheter].Title:= ActualCatheters[Catheter].Name +' Measured';
      YValues[Catheter].Length := XValues.Length;
      inc(count);
    end;
    for Catheter in PlotActual do begin
      for i := 0 to XValues.Length do begin
        TempFlow[i] :=  ActualCatheters[Catheter].MeasuredFlow[i];
        case Plotoption of
          Flow: YValues[Catheter][i] := tempFlow[i];
          Velocity: YValues[Catheter][i] := ActualCatheters[Catheter].calc_velocity(tempflow[i]) ;
          Mach: YValues[Catheter][i] := ActualCatheters[Catheter].calc_velocity(tempflow[i]) /342;
          Entrain : YValues[Catheter][i] := ActualCatheters[Catheter].EntrainedFlow[i];
          E_Ratio : YValues[Catheter][i] := (ActualCatheters[Catheter].EntrainedFlow[i]-tempFlow[i])/tempFlow[i];
          Stall15: YValues[Catheter][i] := ActualCatheters[Catheter].MeasuredStall15[i];
          Stall22: YValues[Catheter][i] := ActualCatheters[Catheter].MeasuredStall22[i];
          Mass_Flow: YValues[Catheter][i]:=
            XValues[i]- (0.5*O2_Density_RT*sqr(ActualCatheters[Catheter].calc_Velocity(tempflow[i])))/One_Bar;
        end;
      end;
      DrawValues(XValues,YValues[Catheter],CatheterSeries[Catheter]);
    end;
  finally
    for Catheter in PlotActual do begin
        ActualCatheters[Catheter].Free;
    end;
  end;
end;

procedure TfmMain.cb14ActualClick(Sender: TObject);
begin
  if cb14Actual.Checked then PlotActual := PlotActual + [IV_14] else
  PlotActual := PlotActual - [IV_14];

end;

procedure TfmMain.cb14CalcClick(Sender: TObject);
begin
   if cb14Calc.Checked then PlotCalculated := PlotCalculated + [IV_14] else
  PlotCalculated := Plotcalculated - [IV_14];
end;

procedure TfmMain.cb16ActualClick(Sender: TObject);
begin
  if cb16Actual.Checked then PlotActual := PlotActual + [IV_16] else
  PlotActual := PlotActual - [IV_16];
end;

procedure TfmMain.cb16CalcClick(Sender: TObject);
begin
  if cb16Calc.Checked then PlotCalculated := PlotCalculated + [IV_16] else
  PlotCalculated := Plotcalculated - [IV_16];
end;

procedure TfmMain.cb18ActualClick(Sender: TObject);
begin
  if cb18Actual.Checked then PlotActual := PlotActual + [IV_18] else
  PlotActual := PlotActual - [IV_18];
end;

procedure TfmMain.cb18CalcClick(Sender: TObject);
begin
  if cb18Calc.Checked then PlotCalculated := PlotCalculated + [IV_18] else
  PlotCalculated := Plotcalculated - [IV_18];
end;

procedure TfmMain.cbBiroActualClick(Sender: TObject);
begin
  if cbBiroActual.Checked then PlotActual := PlotActual + [Biro] else
  PlotActual := PlotActual - [Biro];
end;

procedure TfmMain.cbBiroCalcClick(Sender: TObject);
begin
  if cbBiroCalc.Checked then PlotCalculated := PlotCalculated + [Biro] else
  PlotCalculated := Plotcalculated - [Biro];
end;

procedure TfmMain.cbCookActualClick(Sender: TObject);
begin
  if cbCookActual.Checked then PlotActual := PlotActual + [Cook] else
  PlotActual := Plotactual - [Cook];
end;

procedure TfmMain.cbCookCalcClick(Sender: TObject);
begin
  if cbCookCalc.Checked then PlotCalculated := PlotCalculated + [Cook] else
  PlotCalculated := Plotcalculated - [Cook];
end;

procedure TfmMain.cbLindholmActualClick(Sender: TObject);
begin
   if cbLindholmActual.Checked then PlotActual := PlotActual + [Lindholm] else
   PlotActual := PlotActual - [Lindholm];
end;

procedure TfmMain.cbLindholmClick(Sender: TObject);
begin
  if cbLindholm.Checked then PlotCalculated := PlotCalculated + [Lindholm] else
  PlotCalculated := Plotcalculated - [Lindholm];
end;

procedure TfmMain.FormCreate(Sender: TObject);

begin
  XValues   := [0.5,1.0,1.5,2.0,2.5,3.0,3.5];
  PlotCalculated := [Biro];
  PlotActual := [Biro];
  PlotOption := Flow;
  CursorOn := False;
end;

procedure TfmMain.rgPlotOptionClick(Sender: TObject);
begin
  case rgPlotOption.ItemIndex of
    0: PlotOption := Flow;
    1: PlotOption := Velocity;
    2: PlotOption := Entrain;
    3: PlotOption := E_Ratio;
    4: PlotOption := Mach;
    5: PlotOption := Stall22;
    6: PlotOption := Stall15;
    7: PlotOption := Mass_Flow;
  end;
end;

end.
