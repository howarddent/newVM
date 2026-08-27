unit Unit43;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ShellApi, newVM, newVMsparse,
  CXS.FEMLAP.StructuralThermalEngine,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.ShellExec, ExtCtrls;

type
  TForm43 = class(TForm)
    Button1: TButton;
    RadioGroup1: TRadioGroup;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }

    FGmsh : TGmsh;

    FStructuralThermalEngine : TStructuralThermalEngine;

  public
    { Public declarations }

    function TemperatureFunc(NodeId, ElementId : Integer) : Double;
    function TimeFunc(NodeId, ElementId : Integer) : Double;

    procedure WriteStructuralResults;
    procedure WriteThermalResults;

  end;

var
  Form43: TForm43;

implementation

{$R *.lfm}

procedure TForm43.Button1Click(Sender: TObject);
var

  MeshSize : Double;

  dx, dy : Double;

  SectionArea, Perimeter, Thickness : Double;

  rho, E, poisson, Cp, k, alpha : TExpressionList;

  F : TExpressionList;

  restraint_ux, restraint_uy : TExpressionList;
  restraint_T1, restraint_T2 : TExpressionList;

  MaterialId : Integer;

  ExitCode : DWORD;

  EleType : NEleType;

  ii, jj: Integer;

  NbNodes : Integer;
  Node : Array[0..4] of Integer;

begin

  Screen.Cursor := crHourGlass;

  FStructuralThermalEngine := TStructuralThermalEngine.Create;

  FGmsh := TGmsh.Create;

  Caption := 'Building geometry...';

  MeshSize := 0.019;

  dx := 6;
  dy := 0.2;
  Thickness := 0.1;

  Perimeter := 2 * Thickness + 2 * dy;
  SectionArea := Thickness * dy;

  FGmsh.OpenFile('..\Data\thermalstructuralengine.geo');

  if RadioGroup1.ItemIndex = 0 then
    FGmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_TRI)
  else
    FGmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_QUAD);

  FGmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\thermalstructuralengine.geo', '-3', '-optimize'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  FGmsh.OpenFile('..\Data\thermalstructuralengine.msh');
  FGmsh.ReadMesh;
  FGmsh.Close;

  (******************** START PROPERTIES ********************)

  rho := TExpressionList.Create;
  rho.AddExpression(-1000, +1000, '1', 'T');

  E := TExpressionList.Create;
  E.AddExpression(-1000, +1000, '1E7', 'T');

  poisson := TExpressionList.Create;
  poisson.AddExpression(-1000, +1000, '0.3', 'T');

  Cp := TExpressionList.Create;
  Cp.AddExpression(-1000, +1000, '1', 'T');

  k := TExpressionList.Create;
  k.AddExpression(-1000, +1000, '1', 'T');

  alpha := TExpressionList.Create;
  alpha.AddExpression(-1000, +1000, '1E-6', 'T');

  MaterialId := FStructuralThermalEngine.AddMaterial(TemperatureFunc, rho, E, poisson, Cp, k, alpha);

  (******************** BC METHOD ********************)
  FStructuralThermalEngine.PenaltyMethod := False;

  (******************** START NODES ********************)

  FStructuralThermalEngine.BeginAddMesh;

  for ii := 0 to FGmsh.NbNodes - 1 do
  begin

    FStructuralThermalEngine.AddNode(FGmsh.CoordX[ii], FGmsh.CoordY[ii], FGmsh.CoordZ[ii]);

  end;

  (******************** START ELEMENTS ********************)

  for ii := 0 to FGmsh.NbElements - 1 do
  begin

    NbNodes := 0;

    EleType := elNone;

    if FGmsh.ElementType[ii] = GMSH_TRI then begin NbNodes := 3; EleType := elTri; end
    else if FGmsh.ElementType[ii] = GMSH_QUAD then begin NbNodes := 4; EleType := elQuad; end;

    for jj := 0 to NbNodes-1 do
    begin
      Node[jj] := FGmsh.ElementNode[ii, jj];
    end;

    FStructuralThermalEngine.AddElement(Node, NbNodes, EleType, MaterialId, SectionArea, Perimeter, Thickness);

  end;

  FStructuralThermalEngine.EndAddMesh;

  (******************** START DEFORMATION RESTRAINTS ********************)

  FStructuralThermalEngine.BeginSetRestraints;

  restraint_ux := TExpressionList.Create;
  restraint_ux.AddExpression(-1000, +1000, '0', 't');

  restraint_uy := TExpressionList.Create;
  restraint_uy.AddExpression(-1000, +1000, '0', 't');

  // Structural
  FStructuralThermalEngine.SetNodeRestraint(0, TimeFunc, restraint_ux, diX, atStructural);
  FStructuralThermalEngine.SetNodeRestraint(0, TimeFunc, restraint_uy, diY, atStructural);

  FStructuralThermalEngine.SetNodeRestraint(3, TimeFunc, restraint_ux, diX, atStructural);

  restraint_T1 := TExpressionList.Create;
  restraint_T1.AddExpression(-1000, +1000, '0.5', 't');

  restraint_T2 := TExpressionList.Create;
  restraint_T2.AddExpression(-1000, +1000, '1', 't');

  // Thermal
  FStructuralThermalEngine.SetNodeRestraint(0, TimeFunc, restraint_T1, diX, atThermal);
  FStructuralThermalEngine.SetNodeRestraint(3, TimeFunc, restraint_T1, diX, atThermal);
  FStructuralThermalEngine.SetNodeRestraint(1, TimeFunc, restraint_T2, diX, atThermal);
  FStructuralThermalEngine.SetNodeRestraint(2, TimeFunc, restraint_T2, diX, atThermal);

  FStructuralThermalEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  FStructuralThermalEngine.SetInitialTemperature(0, atStructural);
  FStructuralThermalEngine.SetInitialTemperature(0, atThermal);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  F := TExpressionList.Create;

  F.AddExpression(-1000, +1000, '-1', 't');

  FStructuralThermalEngine.AddNodeSource(2, TimeFunc, F, diY, atStructural);

  //FStructuralThermalEngine.SelfWeight := False;
  //FStructuralThermalEngine.GravityValue := -386.1;
  //FStructuralThermalEngine.GravityDirection := diY;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  FStructuralThermalEngine.SetEndPostIterationFunction(WriteThermalResults, atThermal);
  FStructuralThermalEngine.SetEndPostIterationFunction(WriteStructuralResults, atStructural);

  FStructuralThermalEngine.SolverType[atStructuralThermal] := soUMFPACK;

  FStructuralThermalEngine.Coupled := False;

  Application.ProcessMessages;

  FGmsh.OpenFile('..\Data\thermalstructuralengine.pos');

  FGmsh.ReWriteFile;

  FStructuralThermalEngine.Calc(caStatic, atStructuralThermal, True);

  FGmsh.Close;

  (******************** START POST-PROCESSING ********************)

  ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\thermalstructuralengine.pos', nil, SW_SHOWNORMAL);

  restraint_ux.Free;
  restraint_uy.Free;

  restraint_T1.Free;
  restraint_T2.Free;

  F.Free;

  rho.Free;
  E.Free;
  poisson.Free;
  Cp.Free;
  k.Free;
  alpha.Free;

  FGmsh.Free;

  FStructuralThermalEngine.Free;

end;

function TForm43.TemperatureFunc(NodeId, ElementId : Integer): Double;
var

  j : Integer;
  Element : TElementData;
  sumT: Double;

begin

  if NodeId <> -1 then
  begin
    Result := FStructuralThermalEngine.Temperature[NodeId];
  end
  else if ElementId <> -1 then
  begin

    Element := FStructuralThermalEngine.Element[ElementId, atStructural];

    sumT := 0;

    for j := 0 to Element.NbNodes - 1 do
    begin

      NodeId := Element.NodeId[j];

      sumT := sumT + FStructuralThermalEngine.Temperature[NodeId];

    end;

    if Element.NbNodes > 0 then
      sumT := sumT / Element.NbNodes;

    Result := sumT;

  end
  else
    Result := 0;

end;

function TForm43.TimeFunc(NodeId, ElementId : Integer): Double;
begin

  Result := FStructuralThermalEngine.Time;

end;

procedure TForm43.WriteStructuralResults;
var

  i : Integer;

  // Output data
  Ux, Uy, Uz : TDoubleArray;

  Stress : RStress;
  Sxx, Syy, Sxy : TDoubleArray;

begin

  SetLength(Ux, FStructuralThermalEngine.NbNodes);
  SetLength(Uy, FStructuralThermalEngine.NbNodes);
  SetLength(Uz, FStructuralThermalEngine.NbNodes);

  for i := 0 to FStructuralThermalEngine.NbNodes - 1 do
  begin
    Ux[i] := FStructuralThermalEngine.Deformation[i, diX];
    Uy[i] := FStructuralThermalEngine.Deformation[i, diY];
    Uz[i] := 0;
  end;

  SetLength(Sxx, FStructuralThermalEngine.NbElements);
  SetLength(Syy, FStructuralThermalEngine.NbElements);
  SetLength(Sxy, FStructuralThermalEngine.NbElements);

  for i := 0 to FStructuralThermalEngine.NbElements - 1 do
  begin

    Stress := FStructuralThermalEngine.Stress[i];

    Sxx[i] := Stress.Sxx;
    Syy[i] := Stress.Syy;
    Sxy[i] := Stress.Sxy;

  end;

  //FGmsh.WriteViewVector('Displacement', Ux, Uy, Uz, True);
  FGmsh.WriteViewScalarNode('Ux', Ux, False);
  FGmsh.WriteViewScalarNode('Uy', Uy, False);

  //FGmsh.WriteViewVectorElement('S', Sxx, Syy, Sxy, False);
  FGmsh.WriteViewScalarElement('Sxx', Sxx, False);
  FGmsh.WriteViewScalarElement('Syy', Syy, False);
  FGmsh.WriteViewScalarElement('Sxy', Sxy, False);

end;

procedure TForm43.WriteThermalResults;
var

  i : Integer;

  // Output data
  T : TDoubleArray;

begin

  SetLength(T, FStructuralThermalEngine.NbNodes);

  for i := 0 to FStructuralThermalEngine.NbNodes - 1 do
  begin
    T[i] := FStructuralThermalEngine.Temperature[i];
  end;

  FGmsh.WriteViewScalarNode('T', T, False);

end;

end.
