unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, VclTee.TeeGDIPlus, VCLTee.TeEngine,
  VCLTee.Series, Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart, Vcl.StdCtrls,uModel3Comp,
  MtxExpr,Math387,MtxVecTee,mtxVec, Vcl.Tabs, Vcl.ComCtrls, Vcl.Mask, Vcl.Menus,
  MtxComCtrls, uBodystats, VCLTee.TeeTools,UPatient;


type
   TPatientData = class
     private
       fweight : double;
       fheight : Double;
       fAge : TAge;
       fsex : Tsex;
      procedure setweight(Value :Double);
       procedure setheight(Value :Double);
       procedure setAge(Value :TAge);
       procedure setSex(Value :Tsex);
     published
       property Weight: Double read fweight write setweight;
       property Height: Double read fHeight write setHeight;
       property Age: TAge read fAge write setAge;
       property Sex: TSex read fsex write setSex;
   End;
type
  TfmMain = class(TForm)
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    Chart1: TChart;
    Series5: TPointSeries;
    Series6: TPointSeries;
    Series7: TPointSeries;
    Series8: TPointSeries;
    TabSheet2: TTabSheet;
    TabSheet3: TTabSheet;
    Panel1: TPanel;
    Chart3: TChart;
    Button1: TButton;
    Chart4: TChart;
    Series17: TMtxFastLineSeries;
    Series14: TMtxFastLineSeries;
    Series15: TMtxFastLineSeries;
    Series16: TMtxFastLineSeries;
    Series9: TMtxFastLineSeries;
    Chart5: TChart;
    Series18: TMtxFastLineSeries;
    Button2: TButton;
    Series19: TMtxFastLineSeries;
    Series20: TMtxFastLineSeries;
    Series21: TMtxFastLineSeries;
    MainMenu1: TMainMenu;
    miPatient: TMenuItem;
    GroupBox1: TGroupBox;
    cbDrugs: TComboBox;
    MtxFloatEdit1: TMtxFloatEdit;
    Label1: TLabel;
    Button3: TButton;
    SaveDialog1: TSaveDialog;
    TreeView1: TTreeView;
    TabSheet4: TTabSheet;
    Chart2: TChart;
    Button4: TButton;
    Memo1: TMemo;
    Memo2: TMemo;
    Series2: TMtxFastLineSeries;
    Series3: TMtxFastLineSeries;
    Series4: TMtxFastLineSeries;
    ChartTool1: TColorLineTool;
    ChartTool2: TColorLineTool;
    ChartTool3: TColorBandTool;
    Graphics: TTabSheet;
    Panel2: TPanel;
    Timer1: TTimer;
    ChartTool4: TAnnotationTool;
    Series12: TMtxFastLineSeries;
    Button5: TButton;
    Series13: TMtxFastLineSeries;
    ChartTool5: TColorBandTool;
    TabSheet5: TTabSheet;
    Chart6: TChart;
    Series22: TMtxFastLineSeries;
    Button6: TButton;
    Series23: TMtxFastLineSeries;
    Series24: TMtxFastLineSeries;
    Series25: TMtxFastLineSeries;
    ChartTool6: TColorLineTool;
    ChartTool7: TColorLineTool;
    Button7: TButton;
    Export: TButton;
    Series10: TMtxFastLineSeries;
    Series11: TMtxFastLineSeries;
    ChartTool8: TColorLineTool;
    Series1: TMtxFastLineSeries;
    procedure FormCreate(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure miPatientClick(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure cbDrugsChange(Sender: TObject);
    procedure TreeView1Change(Sender: TObject; Node: TTreeNode);
    procedure Button4Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure Button7Click(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    Prop_marsh : TM3Comp;
    Prop_Schneider : TM3Comp;
    Prop_PaedFusor :TM3Comp;
    Prop_Eleveld,Prop_Paed_eleveld :TM3Comp;
    Remi_minto : TM3Comp;
    PatientData :TPatientData;
    Drug,SelectedDrug : TDrugs;
    Model,SelectedModel : TModels;
  public
  end;

var
  fmMain: TfmMain;

implementation

uses
 VCLTee.TeeSVGCanvas;


{$R *.dfm}



procedure TfmMain.Button1Click(Sender: TObject);
var
  R : Matrix;
  X,Y : Vector;

begin
   R:=Prop_Marsh.RK45_const_effect_solve(3,20,60,10);
   with chart3 do begin
     series9.Clear;
     series14.Clear;
     series15.Clear;
     series16.Clear;
     X.GetRow(R,0);
     DrawValues([X,Y.GetRow(R,2)],Series9);
     DrawValues([X,Y.GetRow(R,3)],Series14);
     DrawValues([X,Y.GetRow(R,4)],Series15);
     DrawValues([X,Y.GetRow(R,5)],Series16);
   end;
   with chart4 do begin
     series17.Clear;
     DrawValues([X,Y.GetRow(R,1)],Series17);
   end;
end;

procedure TfmMain.Button2Click(Sender: TObject);

var
  R,S : Matrix;
  X,Y : Vector;
  ABolus : Double;
  i : Integer;
  BIS_Score : Vector;

begin
   R:=Prop_Marsh.RK45_const_plasma_solve(0,2.5,60,60,10);
   ABolus := 0.3 * Prop_Marsh.fmodelParams.V1;  //Bolus Size In mls
   Y.GetRow(R,1);
   S:=Remi_Minto.Arbitrary_Infusion(Y,ABolus,60,10);
   with chart5 do begin
     series18.Clear;
     series19.Clear;
     series20.Clear;
     series21.Clear;
     X.GetRow(R,0);
     BIS_Score.Length := X.Length;
     for i := 0 to Bis_Score.length-1 do Bis_Score[i] := prop_marsh.BIS(R[5,i]);
     DrawValues([X,Y.GetRow(S,2)],Series18);
     DrawValues([X,Y.GetRow(S,5)],Series19);
     DrawValues([X,Y.GetRow(R,2)],Series20);
     DrawValues([X,Y.GetRow(R,5)],Series21);
     DrawValues([X,BIS_Score],Series13);
   end;
end;



procedure TfmMain.Button3Click(Sender: TObject);
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

procedure TfmMain.Button4Click(Sender: TObject);
Const
  NumPoints = 100;
var
  x,y_male,y_female,vBMI : Vector;
  I : Integer;
begin
   x.Size(NumPoints+1,mvDouble);
   y_male.Size(NumPoints+1,mvDouble);
   y_female.Size(NumPoints+1,mvDouble);
   vBMI.Size(NumPoints+1,mvDouble);
   x.Ramp(30,170/NumPoints);
   for I := 0 to Numpoints do  begin
   y_male[i] := //lbw({weight}x[i],{height}1.75,{sex}male,{Method}James);
               //ABM( IBW(1.75,Male),x[i] );

     freeFatMass( {Age}24,male{Sex},x[i]{weight},1.75{height});
   y_female[i] :=  //lbw({weight}x[i],{height}1.75,{sex}female,{Method}James);
      //ABM( IBW(1.75,Female),x[i] );

     freeFatMass( {Age}24,female{Sex},x[i]{weight},1.75{height});
   vBMI[i] := BMI(x[i],1.6);
   end;
   DrawValues(vBMI,y_male,Series10);
   DrawValues(vBMI,y_female,Series11);
   memo1.Lines.Add('male :'+floatToStr(freeFatMass(24,male,150,1.75)));
   memo1.Lines.Add('female :'+floatToStr(freeFatMass(24,female,150,1.75)));
end;

procedure TfmMain.Button5Click(Sender: TObject);
var
  tmp : TSVGExportFormat;
  AFileName: String;
begin
  tmp := TSVGexportFormat.Create;
  try
    tmp.Panel := Chart5;
    if SaveDialog1.Execute(Self.Handle)  then
      tmp.SaveToFile(SaveDialog1.Filename);
  finally
    tmp.Free;
  end;

end;

procedure TfmMain.Button6Click(Sender: TObject);
const
  TotalTime =20;
  Interval = 10;
  StopTime = 1;
  PointOneMcg_per_kg_min =8.4; // mls/hr

var
  inf,z,X,Y : Vector;
  NumSteps,StopStep,i : Integer;
  R,Q : Matrix;
begin
  NumSteps:= Round(TotalTime * 60 / T_Pump);
  StopStep := round(StopTime * 60/T_Pump);
  inf.Length := NumSteps;
  z.Length := NumSteps;
  z.SetVal(0);
  inf.SetVal(1200);   // mls/min
  for i := stopStep  to inf.Length-1 do inf[i] := 0;
  R := Prop_Marsh.Pump_Arbitrary_Infusion(inf,{1.4}0,TotalTime);
  Q := Prop_Marsh.Arbitrary_Infusion(z,20,TotalTime,T_Pump);
  X.GetRow(R,0);
  Series22.Clear;
  Series23.Clear;
  DrawValues([X,Y.GetRow(R,2)],Series22);
  DrawValues([X,Y.GetRow(R,5)],Series23);
  DrawValues([X,Y.GetRow(Q,2)],Series24);
  DrawValues([X,Y.GetRow(Q,5)],Series25);
end;

procedure TfmMain.Button7Click(Sender: TObject);
var
  tmp : TSVGExportFormat;
  AFileName: String;
begin
  tmp := TSVGexportFormat.Create;
  try
    tmp.Panel := Chart6;
    if SaveDialog1.Execute(Self.Handle)  then
      tmp.SaveToFile(SaveDialog1.Filename);
  finally
    tmp.Free;
  end;

end;

procedure TfmMain.cbDrugsChange(Sender: TObject);
begin
  Drug := TDrugs(cbDrugs.ItemIndex);
end;

procedure TfmMain.ExportClick(Sender: TObject);
var
  tmp : TSVGExportFormat;
  AFileName: String;
begin
  tmp := TSVGexportFormat.Create;
  try
    tmp.Panel := Chart2;
    if SaveDialog1.Execute(Self.Handle)  then
      tmp.SaveToFile(SaveDialog1.Filename);
  finally
    tmp.Free;
  end;


end;

procedure TfmMain.FormCreate(Sender: TObject);
const
  errMult = 1e9;
var
  R,Q : Matrix;
  X,Y,Z,Err,BIS_score,inf  :Vector;
  s : String;
  t,Tau,ymax : Double;
  i : Integer;
  aBolus : Double;
begin
  inf.Length:= 15*6;
  inf.SetVal(0);
  Prop_marsh:= TM3Comp.Create(Propofol,Marsh,70,1.75,35,Male);
  Prop_Schneider := TM3Comp.Create(Propofol,Schneider,160,1.75,35,Male);
  Prop_Paedfusor := TM3Comp.Create(Propofol,Paedfusor,50,1.2,12,Male);
  Prop_Eleveld := TM3Comp.Create(Propofol,Eleveld,50,1.2,50,Male);
  Prop_paed_Eleveld := TM3Comp.Create(Propofol,Eleveld,21,1.09,5,Male);
  Remi_Minto := TM3Comp.Create(Remifentanil,Minto,70,1.75,35,Male);
//  R := Prop_Marsh.Bristol_10_8_6_Infusion(70,60,10);
  R := Prop_marsh.Analytic_initbolus_solve(140,10,10);
  Q := Prop_marsh.Pump_Arbitrary_Infusion(inf,20,15);
  Y.GetRow(Q,2);
  Z.GetRow(R,1);
  aBolus := 0.3 * prop_paedfusor.fModelParams.V1;
//  aBolus := Prop_Schneider.calc_eff_init_bolus(3.0)/10;
//  Err := Z-Y;

//    Q:=Prop_marsh.Bristol_12_9_6_Infusion(70,90,30);
//  err:=Prop_Marsh.Analytic_initBolus_solve(70,20,10);
  with chart1 do begin
    //s :=Prop_Marsh.fModelParams.DrugName+'Levels Following '+IntToStr(Bolus);
    Series1.Clear;
    Series2.Clear;
    Series3.Clear;
    Series4.Clear;
    X.GetRow(R,0);
    Bis_Score.Length:=X.Length;
    for i := 0 to Bis_Score.length-1 do Bis_Score[i] := prop_marsh.BIS(R[4,i]);
//     DrawValues([X,Err],Series1);
    DrawValues([X,Y.GetRow(R,1)],Series1);
    DrawValues([X,Y.GetRow(R,2)],Series2);
    DrawValues([X,Y.GetRow(R,3)],Series3);
    DrawValues([X,Y.GetRow(R,4)],Series4);
    DrawValues([X,BIS_Score],Series12);
  end;
  Tau := Prop_Marsh.find_TPeak;
  ymax := Prop_Marsh.y_Strang(200,Tau)[3];
  memo2.Lines.Add('TPeak at : '+floatToStr(Tau));
  memo2.Lines.Add('Required Bolus : '+floatToStr(Prop_Marsh.calc_eff_init_bolus(3) ));
  with Prop_Marsh.fModelParams do begin
    memo2.Lines.Add('Model is '+ModelName );
    memo2.Lines.Add('BMI =  '+floatToStr(prop_Marsh.fBMI ));
    memo2.Lines.Add('Adjusted BW =  '+floatToStr(prop_Marsh.fadj_BW ));
    memo2.Lines.Add('V1 = '+floatToStr(V1));
    memo2.Lines.Add('V2 = '+floatToStr(V2));
    memo2.Lines.Add('V3 = '+floatToStr(V3));
    memo2.Lines.Add('Cl = '+floatToStr(Cl1));
    memo2.Lines.Add('ke0 = '+floatToStr(ke0));
//    memo2.Lines.Add('Ce50 = '+floatToStr(Prop_Marsh.pCe50));


  end;
  chartTool1.AllowDrag := True;
  chartTool2.AllowDrag := True;
  ChartTool1.Value := ymax;
  ChartTool2.Value := Tau;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  Prop_marsh.free;
  Prop_Schneider.Free;
  Prop_Paedfusor.Free;;
  Prop_Eleveld.Free;
  Prop_paed_Eleveld.Free;
  Remi_Minto.Free;
end;

procedure TfmMain.miPatientClick(Sender: TObject);
begin
  dlgPatient.show;
end;

procedure TfmMain.TreeView1Change(Sender: TObject; Node: TTreeNode);
begin

end;

{ TPatientData }

procedure TPatientData.setAge(Value: TAge);
begin
  fage := Value;
end;

procedure TPatientData.setheight(Value: Double);
begin
  fHeight := Value;
end;

procedure TPatientData.setSex(Value: Tsex);
begin
  fsex := Value;
end;

procedure TPatientData.setweight(Value: Double);
begin
  fweight := Value;
end;

end.
