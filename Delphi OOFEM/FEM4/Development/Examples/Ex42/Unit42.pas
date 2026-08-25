unit Unit42;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ShellApi, newVM, newVMsparse,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.StructuralEngine, CXS.FEMLAP.Expression,
  CXS.FEMLAP.ShellExec, CXS.FEMLAP.Gmsh;

type
  TForm42 = class(TForm)
    Button1: TButton;
    ComboBox1: TComboBox;
    Label1: TLabel;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }

    FStart, FElapsed : Double;

    LoadCase : Integer;

    // Gmsh data
    Gmsh : TGmsh;
    // Thermal engine class
    StructuralEngine : TStructuralEngine;

  public
    { Public declarations }

    function T(NIndex, EIndex : Integer) : Double;
    function time(NIndex, EIndex : Integer) : Double;

    procedure PostProcess;

  end;

var
  Form42: TForm42;

implementation

{$R *.lfm}

procedure TForm42.Button1Click(Sender: TObject);
var

  ii, jj : Integer;

  MeshSize : Double;

  dx, dy : Double;

  SectionArea, Perimeter, Thickness : Double;

  ExitCode: DWORD;

  NbNodes : Integer;
  Node : Array[0..4] of Integer;

  MaterialId : Integer;

  EleType : NEleType;

  rho, E, poisson, alpha : TExpressionList;

  F1, F2 : TExpressionList;

  time1 : TExpressionList;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := 0.019;

  dx := 6;
  dy := 0.2;
  Thickness := 0.1;

  Perimeter := 2 * Thickness + 2 * dy;
  SectionArea := Thickness * dy;

  Gmsh.OpenFile('..\Data\structuralengine.geo');
  Gmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_TRI);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\structuralengine.geo -3 -optimize', ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\structuralengine.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  StructuralEngine := TStructuralEngine.Create;

  (******************** START PROPERTIES ********************)

  time1 := TExpressionList.Create;
  time1.AddExpression(-1000, +1000, '0', 't');

  rho := TExpressionList.Create;
  rho.AddExpression(-1000, +1000, '1', 'T');

  E := TExpressionList.Create;
  E.AddExpression(-1000, +1000, '1E7', 'T');

  poisson := TExpressionList.Create;
  poisson.AddExpression(-1000, +1000, '0.3', 'T');

  alpha := TExpressionList.Create;
  alpha.AddExpression(-1000, +1000, '0.3', 'T');

  MaterialId := StructuralEngine.AddMaterial(T, rho, E, poisson, alpha);

  (******************** BC METHOD ********************)
  StructuralEngine.PenaltyMethod := True;

  (******************** START NODES ********************)

  StructuralEngine.BeginAddMesh;

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    StructuralEngine.AddNode(Gmsh.CoordX[ii], Gmsh.CoordY[ii], Gmsh.CoordZ[ii]);

  end;

  (******************** START ELEMENTS ********************)

  for ii := 0 to Gmsh.NbElements - 1 do
  begin

    NbNodes := 0;

    EleType := elNone;

    if Gmsh.ElementType[ii] = GMSH_TRI then begin NbNodes := 3; EleType := elTri; end
    else if Gmsh.ElementType[ii] = GMSH_QUAD then begin NbNodes := 4; EleType := elQuad; end;

    for jj := 0 to NbNodes-1 do
    begin
      Node[jj] := Gmsh.ElementNode[ii, jj];
    end;

    StructuralEngine.AddElement(Node, NbNodes, EleType, MaterialId, SectionArea, Perimeter, Thickness);

  end;

  StructuralEngine.EndAddMesh;

  (******************** START DEFORMATION RESTRAINTS ********************)

  StructuralEngine.BeginSetRestraints;

  StructuralEngine.SetNodeRestraint(0, time, time1, diX);
  StructuralEngine.SetNodeRestraint(0, time, time1, diY);

  StructuralEngine.SetNodeRestraint(3, time, time1, diX);

  StructuralEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  StructuralEngine.SetInitialDeformation(0);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  F1 := TExpressionList.Create;
  F2 := TExpressionList.Create;

  LoadCase := StrToInt(ComboBox1.Text);

  // Load case 1
  case LoadCase of
  1:
  begin

    // Load case 1
    F1.AddExpression(-1000, +1000, '0.5', 't');

    StructuralEngine.AddNodeSource(1, time, F1, diX);
    StructuralEngine.AddNodeSource(2, time, F1, diX);

  end;
  2:
  begin

    // Load case 2
    F1.AddExpression(-1000, +1000, '0.5', 't');

    StructuralEngine.AddNodeSource(1, time, F1, diY);
    StructuralEngine.AddNodeSource(2, time, F1, diY);

    F2.AddExpression(-1000, +1000, '-0.5', 't');

    StructuralEngine.AddNodeSource(3, time, F2, diY);

  end;
  3:
  begin

    // Load case 3
    F1.AddExpression(-1000, +1000, '-5', 't');

    StructuralEngine.AddNodeSource(1, time, F1, diX);

    F2.AddExpression(-1000, +1000, '+5', 't');

    StructuralEngine.AddNodeSource(2, time, F2, diX);

  end;
  end;

  //StructuralEngine.SelfWeight := False;
  //StructuralEngine.GravityValue := -386.1;
  //StructuralEngine.GravityDirection := diY;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  StructuralEngine.SetEndPostIterationFunction(PostProcess);

  StructuralEngine.SolverType := soUMFPACK;

  FStart := GetTickCount;

  StructuralEngine.CalcDeformation(caStatic, False);

  (******************** START POST-PROCESSING ********************)

  //ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\structuralengine.scr', nil, SW_SHOWNORMAL);
  ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\structuralengine.pos', nil, SW_SHOWNORMAL);

  time1.Free;

  StructuralEngine.Free;

  F1.Free;
  F2.Free;

  rho.Free;
  E.Free;
  poisson.Free;
  alpha.Free;

  Gmsh.Free;

end;

procedure TForm42.FormCreate(Sender: TObject);
begin

  ComboBox1.AddItem('1', nil);
  ComboBox1.AddItem('2', nil);
  ComboBox1.AddItem('3', nil);

  ComboBox1.ItemIndex := 0;

end;

procedure TForm42.PostProcess;
var

  i : Integer;

  // Output data
  ux, uy, uz : TDoubleArray;

  //Stress : RStress;

  //Sigma : TVMobj;

begin

  FElapsed := GetTickCount - FStart;

  Caption := IntToStr(StructuralEngine.Step) + ' : ' + FloatToStr(FElapsed);

  Application.ProcessMessages;

  Gmsh.OpenFile('..\Data\structuralengine.pos');

  SetLength(ux, StructuralEngine.NbNodes);
  SetLength(uy, StructuralEngine.NbNodes);
  SetLength(uz, StructuralEngine.NbNodes);

  for i := 0 to StructuralEngine.NbNodes - 1 do
  begin

    ux[i] := StructuralEngine.Deformation[i, diX];
    uy[i] := StructuralEngine.Deformation[i, diY];
    uz[i] := 0;

  end;

  //Gmsh.WriteViewVector('Displacement', ux, uy, uz, True);
  Gmsh.WriteViewScalarNode('Ux', ux, True);
  Gmsh.WriteViewScalarNode('Uy', uy, False);

  Gmsh.Close;

  (*
  Stress := StructuralEngine.Stress[0];

  Sigma := TVMobj.Create(4, 1);

  for i := 0 to 3 do
    Sigma[i,0] := Stress[i];

  //ViewValues(Sigma);
  *)

  FStart := GetTickCount;

end;

function TForm42.T(NIndex, EIndex: Integer): Double;
begin

  Result := 0;

end;

function TForm42.time(NIndex, EIndex: Integer): Double;
begin

  Result := 0;

end;

end.
