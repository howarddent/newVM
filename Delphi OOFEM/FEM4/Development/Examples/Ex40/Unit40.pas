unit Unit40;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.Gmsh,
  CXS.FEMLAP.Assembly, CXS.FEMLAP.Penalty, CXS.FEMLAP.Face_T3V2, CXS.FEMLAP.Face_Q4V2,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.StructuralEngine, CXS.FEMLAP.Expression;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
    CheckBox1: TCheckBox;
    Button2: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
  private
    { Private declarations }

    FStart, FElapsed : Double;

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
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.Button1Click(Sender: TObject);
var

  i, j, n: Integer;

  Face_T3V2 : TFace_T3V2;

  NodeId : Array[0..2] of Integer;
  cx, cy, cz : Array[0..2] of Double;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Assembly
  Assembly : TAssembly;

  Penalty : TPenalty;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;
  OldToNew : TIntegerArray;

  MSize : Integer;

  // Output data
  ux, uy : TDoubleArray;

  PenaltyMethod : Boolean;

  // Stress output

  D, B : Array of TVMobj;

  DB : TVMobj;

  qe : TVMobj;

  Sigma : TVMobj;

begin

  Screen.Cursor := crHourGlass;

  PenaltyMethod := CheckBox1.Checked;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\example5.6_t.msh');
  Gmsh.ReadMesh();
  Gmsh.Close;

  // Set boundary conditions
  SetLength(IsFixed, 2*Gmsh.NbNodes);
  SetLength(Values, 2*Gmsh.NbNodes);
  SetLength(OldToNew, 2*Gmsh.NbNodes);

  n := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[2*i + 0] := False;
    IsFixed[2*i + 1] := False;

    if (i = 0) then
    begin

      IsFixed[2*i + 1] := True;
      Values[2*i + 1] := 0;

    end
    else if (i = 2) or (i = 3) then
    begin

      IsFixed[2*i + 0] := True;
      Values[2*i + 0] := 0;

      IsFixed[2*i + 1] := True;
      Values[2*i + 1] := 0;

    end;

    OldToNew[2*i + 0] := n;

    if (IsFixed[2*i + 0] = False) then Inc(n);

    OldToNew[2*i + 1] := n;

    if (IsFixed[2*i + 1] = False) then Inc(n);

  end;

  if PenaltyMethod then
    MSize := Gmsh.NbNodes*2
  else
    MSize := n;

  SetLength(R1, Gmsh.NbElements * 18);
  SetLength(C1, Gmsh.NbElements * 18);
  SetLength(V1, Gmsh.NbElements * 18);

  Face_T3V2 := TFace_T3V2.Create;

  Face_T3V2.ElasticModulus := 30E+6;
  Face_T3V2.Poisson := 0.25;
  Face_T3V2.Thickness := 0.5;

  Face_T3V2.ReCalcD;

  Fg := TVMobj.Create(MSize, 1);

  // FE Assembly and elimination

  Assembly := TAssembly.Create;

  n := 0;

  SetLength(D, Gmsh.NbElements);
  SetLength(B, Gmsh.NbElements);

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V2.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 2 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_T3V2.CoordX[j] := cx[j];
        Face_T3V2.CoordY[j] := cy[j];
        Face_T3V2.CoordZ[j] := cz[j];
      end;

      Face_T3V2.Calc;

      Face_T3V2.GetStiffnessDB(D[i], B[i]);

      Ke := Face_T3V2.K;
      Fe := Face_T3V2.b;

      if PenaltyMethod then
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId, 2)
      else
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId, MSize, IsFixed, Values, OldToNew, 2);

    end
    else
    begin

      raise Exception.Create('Error: Only triangles supported.');

    end;

  end;

  Assembly.Free;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  if PenaltyMethod then
    MSize := Gmsh.NbNodes*2;

  // Build global stiffness matrix
  Kg := TripletsToSparse(MSize,MSize,R1,C1,V1);

  ug := TVMobj.Create(MSize, 1);

  // Set load on node 2: uy = 1000;

  if PenaltyMethod then
    Fg[3,0] := -1000
  else
    Fg[OldToNew[3],0] := -1000;

  if PenaltyMethod then
  begin
    Penalty := TPenalty.Create;
    Penalty.Impose(IsFixed, Values, Kg, Fg);
    Penalty.Free;
  end;

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False).
  ug := PardisoSolve(Kg, Fg, False);

  //ViewValues(ug, 'Displacements');

  Screen.Cursor := crDefault;

  SetLength(ux, Gmsh.NbNodes);
  SetLength(uy, Gmsh.NbNodes);

  if PenaltyMethod then
  begin

    for i := 0 to Gmsh.NbNodes - 1 do
    begin

      ux[i] :=  ug[2*i+0,0];
      uy[i] :=  ug[2*i+1,0];

    end;

  end
  else
  begin

    for i := 0 to Gmsh.NbNodes - 1 do
    begin

      if IsFixed[2*i + 0] = True then
        ux[i] :=  Values[2*i+0]
      else
        ux[i] := ug[OldToNew[2*i+0],0];

      if IsFixed[2*i + 1] = True then
        uy[i] :=  Values[2*i+1]
      else
        uy[i] := ug[OldToNew[2*i+1],0];

    end;

  end;

  Gmsh.OpenFile('..\Data\example5.6_t.pos');
  Gmsh.WriteViewScalarNode('Ux', ux);
  Gmsh.WriteViewScalarNode('Uy', uy, False);
  Gmsh.Close;

  qe := TVMobj.Create(6, 1);

  // Stress calculations
  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      qe[0,0] := ux[Gmsh.ElementNode[i, 0]];
      qe[1,0] := uy[Gmsh.ElementNode[i, 0]];
      qe[2,0] := ux[Gmsh.ElementNode[i, 1]];
      qe[3,0] := uy[Gmsh.ElementNode[i, 1]];
      qe[4,0] := ux[Gmsh.ElementNode[i, 2]];
      qe[5,0] := uy[Gmsh.ElementNode[i, 2]];

      DB := MatMult(D[i], B[i]);

      Sigma := MatMult(DB, qe);

      //ViewValues(Sigma, 'Stress' + IntToStr(i));

    end
    else
    begin

      raise Exception.Create('Error: Only triangles supported.');

    end;

  end;

  Face_T3V2.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\example5.6_t.pos', nil, SW_SHOWNORMAL) ;

end;

procedure TForm1.Button2Click(Sender: TObject);
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

  F : TExpressionList;

  time1 : TExpressionList;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := 0.49;

  dx := 20;
  dy := 1;
  Thickness := 0.5;

  Perimeter := 2 * Thickness + 2 * dy;
  SectionArea := Thickness * dy;

  Gmsh.OpenFile('..\Data\example5.6_t.msh');
  Gmsh.ReadMesh();
  Gmsh.Close;

  StructuralEngine := TStructuralEngine.Create;

  (******************** START PROPERTIES ********************)

  time1 := TExpressionList.Create;
  time1.AddExpression(-1000, +1000, '0', 't');

  rho := TExpressionList.Create;
  rho.AddExpression(-1000, +1000, '1', 'T');

  E := TExpressionList.Create;
  E.AddExpression(-1000, +1000, '30E+6', 'T');

  poisson := TExpressionList.Create;
  poisson.AddExpression(-1000, +1000, '0.25', 'T');

  alpha := TExpressionList.Create;
  alpha.AddExpression(-1000, +1000, '1', 'T');

  MaterialId := StructuralEngine.AddMaterial(T, rho, E, poisson, alpha);

  (******************** BC METHOD ********************)
  StructuralEngine.PenaltyMethod := False;

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

  StructuralEngine.SetNodeRestraint(0, time, time1, diY);

  StructuralEngine.SetNodeRestraint(2, time, time1, diX);
  StructuralEngine.SetNodeRestraint(2, time, time1, diY);

  StructuralEngine.SetNodeRestraint(3, time, time1, diX);
  StructuralEngine.SetNodeRestraint(3, time, time1, diY);

  StructuralEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  StructuralEngine.SetInitialDeformation(0);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  F := TExpressionList.Create;
  F.AddExpression(-1000, +1000, '-1000', 't');

  StructuralEngine.AddNodeSource(1, time, F, diY);

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  StructuralEngine.SetEndPostIterationFunction(PostProcess);

  StructuralEngine.SolverType := soUMFPACK;

  FStart := GetTickCount;

  StructuralEngine.CalcDeformation(caStatic, False);

  (******************** START POST-PROCESSING ********************)

  ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\example5.6_t.pos -noview', nil, SW_SHOWNORMAL) ;

  time1.Free;

  StructuralEngine.Free;

  F.Free;

  rho.Free;
  E.Free;
  poisson.Free;
  alpha.Free;

  Gmsh.Free;

end;

procedure TForm1.PostProcess;
var

  i : Integer;

  // Output data
  ux, uy : TDoubleArray;

  Stress : RStress;

  Sigma : TVMobj;

begin

  FElapsed := GetTickCount - FStart;

  Caption := IntToStr(StructuralEngine.Step) + ' : ' + FloatToStr(FElapsed);

  Application.ProcessMessages;

  Gmsh.OpenFile('..\Data\structuralengine.pos');

  SetLength(ux, StructuralEngine.NbNodes);
  SetLength(uy, StructuralEngine.NbNodes);

  for i := 0 to StructuralEngine.NbNodes - 1 do
  begin

    ux[i] := StructuralEngine.Deformation[i, diX];
    uy[i] := StructuralEngine.Deformation[i, diY];

  end;

  Gmsh.WriteViewScalarNode('ux', ux, True);
  Gmsh.WriteViewScalarNode('uy', uy, False);

  Gmsh.Close;

  Stress := StructuralEngine.Stress[0];

  Sigma := TVMobj.Create(3, 1);

  Sigma[0,0] := Stress.Sxx;
  Sigma[1,0] := Stress.Syy;
  Sigma[2,0] := Stress.Sxy;

  //ViewValues(Sigma);

  FStart := GetTickCount;

end;

function TForm1.T(NIndex, EIndex: Integer): Double;
begin

  Result := 0;

end;

function TForm1.time(NIndex, EIndex: Integer): Double;
begin

  Result := 0;

end;

end.
