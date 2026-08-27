unit Unit39;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs,
  CXS.FEMLAP.Gmsh,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element,
  CXS.FEMLAP.Edge_B2V1,
  CXS.FEMLAP.Face_T3V1,
  CXS.FEMLAP.Face_Q4V1,
  CXS.FEMLAP.Brick_T4V1,
  CXS.FEMLAP.Brick_H8V1,
  CXS.FEMLAP.Brick_W6V1,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.ThermalEngine,
  CXS.FEMLAP.Expression,
  StdCtrls, TAGraph, TASeries, ExtCtrls;

type
  TForm39 = class(TForm)
    Button1: TButton;
    Chart1: TChart;
    Image1: TImage;
    Label1: TLabel;
    Edit1: TEdit;
    Label2: TLabel;
    Edit2: TEdit;
    Edit3: TEdit;
    Label3: TLabel;
    Series1: TLineSeries;
    Edit4: TEdit;
    Label4: TLabel;
    ComboBox1: TComboBox;
    Label5: TLabel;
    Button2: TButton;
    Label6: TLabel;
    Edit5: TEdit;
    CheckBox1: TCheckBox;
    Edit6: TEdit;
    Label7: TLabel;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }

    start : Double;

    rho, Cp, k : TExpressionList;

    InitFunc : TExpressionList;

    T1, T2 : TExpressionList;

    // Thermal engine class
    ThermalEngine : TThermalEngine;

  public
    { Public declarations }

    function T(NIndex, EIndex : Integer) : Double;
    function time(NIndex, EIndex : Integer) : Double;

    function x(NIndex, EIndex : Integer) : Double;
    function y(NIndex, EIndex : Integer) : Double;
    function z(NIndex, EIndex : Integer) : Double;

    procedure PostProcess;
    procedure GraphTemperature;

  end;

var
  Form39: TForm39;

implementation

{$R *.lfm}

procedure TForm39.Button1Click(Sender: TObject);
var

  ii : Integer;

  cx, dx : Double;

  SectionArea, Perimeter, Thickness : Double;

  NbNodes : Integer;
  NbElements : Integer;

  Node : Array[0..1] of Integer;

  MaterialId : Integer;

begin

  Button1.Enabled := False;

  try

    (******************** PRE-PROCESSING ********************)

    Caption := 'Building geometry...';

    Thickness := 1;
    Perimeter := 1;
    SectionArea := 1;

    (******************** START PROPERTIES ********************)

    // Density
    rho.Clear;
    rho.AddExpression(-1000, +1000, '1', 'T');

    // Specific heat
    Cp.Clear;
    Cp.AddExpression(-1000, +1000, '1', 'T');

    // Thermal conductivity heat
    k.Clear;
    k.AddExpression(-1000, +1000, '1', 'T');

    MaterialId := ThermalEngine.AddMaterial(T, rho, Cp, k);

    (******************** BC METHOD ********************)
    if CheckBox1.Checked then
      ThermalEngine.PenaltyMethod := True
    else
      ThermalEngine.PenaltyMethod := False;

    (******************** START NODES ********************)

    ThermalEngine.BeginAddMesh;

    NbElements := StrToInt(Edit5.Text);
    NbNodes := NbElements + 1;

    dx := 1.0 / NbNodes;
    cx := 0;

    for ii := 0 to NbNodes - 1 do
    begin

      ThermalEngine.AddNode(cx, 0, 0);
      cx := cx + dx;

    end;

    (******************** START ELEMENTS ********************)

    for ii := 0 to NbElements - 1 do
    begin

      Node[0] := ii;
      Node[1] := ii+1;

      ThermalEngine.AddElement(Node, 2, elBeam, MaterialId, SectionArea, Perimeter, Thickness);

    end;

    ThermalEngine.EndAddMesh;

    (******************** START TEMPERATURE RESTRAINTS ********************)

    ThermalEngine.BeginSetRestraints;

    // Thermal conductivity heat
    T1.Clear;
    T1.AddExpression(-1000, +1000, Edit1.Text, 't');
    T2.Clear;
    T2.AddExpression(-1000, +1000, Edit2.Text, 't');

    ThermalEngine.SetNodeRestraint(0, time, T1);
    ThermalEngine.SetNodeRestraint(NbElements-1, time, T2);

    ThermalEngine.EndSetRestraints;

    (******************** START INITIAL CONDITIONS ********************)
    InitFunc.Clear;
    InitFunc.AddExpression(-1000, +1000, Edit3.Text, 'x');

    ThermalEngine.SetInitialTemperature(x, InitFunc);

    (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

    (******************** START TIME CONTROL ********************)
    ThermalEngine.Time := 0;
    ThermalEngine.TimeInterval := StrToFloat(Edit6.Text);
    ThermalEngine.NbSteps := StrToInt(Edit4.Text);

    (******************** START RUN ANALYSIS ********************)

    Caption := 'Running analysis...';

    ThermalEngine.SetEndPostIterationFunction(PostProcess);

    ThermalEngine.Tolerance := 1E-5;

    ThermalEngine.StopExec := False;
    Button2.Enabled := True;
    Button2.Caption := '&Stop';

    start := GetTickCount;

    case ComboBox1.ItemIndex of
    0: ThermalEngine.CalcTemperature(caStatic, True);
    1: ThermalEngine.CalcTemperature(caTransient, True);
    2: ThermalEngine.CalcTemperature(caStaticNonlinear, True);
    end;

    (******************** START POST-PROCESSING ********************)

  finally

    if ThermalEngine.NbSteps = 0 then
    begin
      PostProcess;
    end;

    if not ThermalEngine.StopExec then
    begin
      Button1.Enabled := True;
      Button2.Enabled := False;
    end;

  end;

end;

procedure TForm39.Button2Click(Sender: TObject);
begin

  if not ThermalEngine.StopExec then
  begin
    ThermalEngine.StopExec := True;

    Button2.Caption := '&Resume';
    Button1.Enabled := True;

  end
  else
  begin

    Button1.Enabled := False;
    Button2.Caption := '&Stop';
    ThermalEngine.StopExec := False;

    ThermalEngine.NbSteps := ThermalEngine.NbSteps - ThermalEngine.Step;

    case ComboBox1.ItemIndex of
    0: ThermalEngine.CalcTemperature(caStatic, True);
    1: ThermalEngine.CalcTemperature(caTransient, True);
    2: ThermalEngine.CalcTemperature(caStaticNonlinear, True);
    end;

  end;

end;

procedure TForm39.FormCreate(Sender: TObject);
begin

  // The original .dfm embedded this PNG directly as Image1.Picture.Data;
  // ported here as a runtime load of the same image file (500x37 "rod.png",
  // shipped alongside this unit) rather than hand-embedding the binary
  // blob in the .lfm.
  Image1.Picture.LoadFromFile('rod.png');

  ComboBox1.AddItem('Static', nil);
  ComboBox1.AddItem('Transient', nil);
  ComboBox1.AddItem('Non-linear Static', nil);

  ComboBox1.ItemIndex := 0;

  ThermalEngine := TThermalEngine.Create;

  rho := TExpressionList.Create;
  Cp := TExpressionList.Create;
  k := TExpressionList.Create;

  T1 := TExpressionList.Create;
  T2 := TExpressionList.Create;

  InitFunc := TExpressionList.Create;

end;

procedure TForm39.FormDestroy(Sender: TObject);
begin

  InitFunc.Free;

  T1.Free;
  T2.Free;

  rho.Free;
  Cp.Free;
  k.Free;

  ThermalEngine.Free;

end;

procedure TForm39.GraphTemperature;
var

  i : Integer;

  //myFile : TextFile;

begin

    Series1.Clear;

    //AssignFile(myFile, 'Test.txt');
    //ReWrite(myFile);

    for i := 0 to ThermalEngine.NbNodes - 1 do
    begin

      //Writeln(myFile, ThermalEngine.Temperature[i]);

      Series1.Add(ThermalEngine.Temperature[i]);

    end;

    Series1.Title := '';

    Chart1.Invalidate;

    Application.ProcessMessages;

    Sleep(20);

end;

procedure TForm39.PostProcess;
begin

  case ComboBox1.ItemIndex of
  0:
  begin

    Caption := 'Static (Elapsed solver time = ' + FloatToStr((GetTickCount - start)*1E-3) + 's )';

    GraphTemperature;

  end;
  1:
  begin

    Caption := 'Transient (time = ' + FloatToStr(ThermalEngine.Time) + 's )';

    GraphTemperature;

  end;
  2:
  begin

    Caption := 'Non-linear static (residual = ' + FloatToStr(ThermalEngine.Residual) + ')';

    if ThermalEngine.Residual < ThermalEngine.Tolerance then
    begin

      GraphTemperature;

    end
    else
    begin

      MessageDlg('Not converged.', mtError, [mbOK], 0);

      Series1.Clear;

      Exit;

    end;

  end;
  end;

end;

function TForm39.T(NIndex, EIndex: Integer): Double;
var
  j : Integer;
begin

  Result := 0;

  for j := 0 to ThermalEngine.Element[EIndex].NbNodes - 1 do
  begin

    Result := Result + ThermalEngine.Temperature[ThermalEngine.Element[EIndex].NodeId[j]];

  end;

  if ThermalEngine.Element[EIndex].NbNodes > 0 then
    Result := Result / ThermalEngine.Element[EIndex].NbNodes;


end;

function TForm39.time(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.Time;

end;

function TForm39.x(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordX[NIndex];

end;

function TForm39.y(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordY[NIndex];

end;

function TForm39.z(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordZ[NIndex];

end;

end.
