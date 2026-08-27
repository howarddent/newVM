unit Unit31;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls,
  newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Analytical, CXS.FEMLAP.Penalty,
  CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Brick_T4V1, CXS.FEMLAP.Brick_H8V1, CXS.FEMLAP.Brick_W6V1,
  TAGraph, TASeries;

type
  TForm31 = class(TForm)
    Label1: TLabel;
    Label2: TLabel;
    Chart1: TChart;
    Series1: TAreaSeries;
    Button1: TButton;
    ComboBox1: TComboBox;
    Edit1: TEdit;
    CheckBox1: TCheckBox;
    CheckBox2: TCheckBox;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form31: TForm31;

implementation

{$R *.lfm}

procedure TForm31.Button1Click(Sender: TObject);
var

  i, j, k, n1: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Node : Array[0..7] of Integer;

  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;
  Brick_W6V1 : TBrick_W6V1;

  // Element stiffness and mass matrix
  Ke : TVMobj;

  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness and mass matrix
  A : TVMSparseMtx;

  b: TVMobj;

  // Unknown vector
  T: TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode: DWORD;

  // BC's
  diag : TVMobj;

  Analytic : TAnalytical;
  Ta : Double;

  Assembly : TAssembly;

  Penalty : TPenalty;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  MeshSize : Double;

  hc, kc : Double;

  Width : Double;
  Length : Double;

  Thickness, Perimeter, SectionArea : Double;

  T1, T2, Tinf : Double;

  NodesOnSurface : Integer;

  Err : Double;

begin

  Screen.Cursor := crHourGlass;

  (******************** DATA ********************)

  hc := 10;
  kc := 52.019;

  Length := 0.3;
  Width := 0.025;
  Thickness := 0.005;

  Perimeter := 2 * Thickness + 2 * Width;
  SectionArea := Thickness * Width;

  T1 := 100;
  T2 := 20;
  Tinf := 20;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := StrToFloat(Edit1.Text);

  Gmsh.OpenFile('..\Data\tvalid.geo');
  if ComboBox1.Text = 'TRI' then
    Gmsh.GenerateRectangle(Length, Width, MeshSize, GMSH_TRI)
  else if ComboBox1.Text = 'QUAD' then
    Gmsh.GenerateRectangle(Length, Width, MeshSize, GMSH_QUAD)
  else if ComboBox1.Text = 'TETRA' then
    Gmsh.GenerateBox(Length, Width, Thickness, MeshSize, GMSH_TETRA)
  else if ComboBox1.Text = 'HEXA' then
    Gmsh.GenerateBox(Length, Width, Thickness, MeshSize, GMSH_HEXA)
  else if ComboBox1.Text = 'PRISM' then
    Gmsh.GenerateBox(Length, Width, Thickness, MeshSize, GMSH_PRISM);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\tvalid.geo', '-3'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\tvalid.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);

  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;
  Brick_W6V1 := TBrick_W6V1.Create;

  (******************** SET BOUNDARY CONDITIONS ********************)

  Caption := 'Setting boundary conditions...';

  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[i] := False;

    if (Abs(Gmsh.CoordX[i] - 0.0) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := T1;
    end;

    if (Abs(Gmsh.CoordX[i] - Length) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := T2;
    end;

  end;

  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** MATRIX SETUP ********************)

  Caption := 'Finite element assembly...';

  Assembly := TAssembly.Create;

  n1 := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    NbNodes := 0;

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      NbNodes := 3;

      for j := 0 to NbNodes-1 do
      begin
        Node[j] := Gmsh.ElementNode[i, j];
        Face_T3V1.NodeId[j] := Node[j];
      end;

      for j := 0 to NbNodes - 1 do
      begin
        Face_T3V1.CoordX[j] := Gmsh.CoordX[Face_T3V1.NodeId[j]];
        Face_T3V1.CoordY[j] := Gmsh.CoordY[Face_T3V1.NodeId[j]];
        Face_T3V1.CoordZ[j] := Gmsh.CoordZ[Face_T3V1.NodeId[j]];
      end;

      Face_T3V1.Thickness := Thickness;

      Face_T3V1.Conductivity := kc;

      Face_T3V1.Calc;

      for j := 0 to Face_T3V1.NbEdges -  1 do
      begin

        NodesOnSurface := 0;
        for k := 0 to Face_T3V1.Edges[j].NbNodes - 1 do
        begin
          if (Abs(Face_T3V1.Edges[j].CoordY[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 2) then
          Face_T3V1.SetSourceOnEdge(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Face_T3V1.Edges[j].NbNodes - 1 do
        begin
          if (Abs(Face_T3V1.Edges[j].CoordY[k] - Width) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 2) then
          Face_T3V1.SetSourceOnEdge(j, hc, Tinf);

      end;

      Face_T3V1.SetSourceOnFace(hc, Tinf);
      Face_T3V1.SetSourceOnFace(hc, Tinf);

      Ke := Face_T3V1.K;
      be := Face_T3V1.b;

    end;

    if Gmsh.ElementType[i] = GMSH_QUAD then
    begin

      NbNodes := 4;

      for j := 0 to NbNodes-1 do
      begin
        Node[j] := Gmsh.ElementNode[i, j];
        Face_Q4V1.NodeId[j] := Node[j];
      end;

      for j := 0 to NbNodes - 1 do
      begin
        Face_Q4V1.CoordX[j] := Gmsh.CoordX[Face_Q4V1.NodeId[j]];
        Face_Q4V1.CoordY[j] := Gmsh.CoordY[Face_Q4V1.NodeId[j]];
        Face_Q4V1.CoordZ[j] := Gmsh.CoordZ[Face_Q4V1.NodeId[j]];
      end;

      Face_Q4V1.Thickness := Thickness;

      Face_Q4V1.Conductivity := kc;

      Face_Q4V1.Calc;

      for j := 0 to Face_Q4V1.NbEdges -  1 do
      begin

        NodesOnSurface := 0;
        for k := 0 to Face_Q4V1.Edges[j].NbNodes - 1 do
        begin
          if (Abs(Face_Q4V1.Edges[j].CoordY[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 2) then
          Face_Q4V1.SetSourceOnEdge(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Face_Q4V1.Edges[j].NbNodes - 1 do
        begin
          if (Abs(Face_Q4V1.Edges[j].CoordY[k] - Width) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 2) then
          Face_Q4V1.SetSourceOnEdge(j, hc, Tinf);

      end;

      Face_Q4V1.SetSourceOnFace(hc, Tinf);
      Face_Q4V1.SetSourceOnFace(hc, Tinf);

      Ke := Face_Q4V1.K;
      be := Face_Q4V1.b;

    end;

    if Gmsh.ElementType[i] = GMSH_TETRA then
    begin

      NbNodes := 4;

      for j := 0 to NbNodes-1 do
      begin
        Node[j] := Gmsh.ElementNode[i, j];
        Brick_T4V1.NodeId[j] := Node[j];
      end;

      for j := 0 to NbNodes - 1 do
      begin
        Brick_T4V1.CoordX[j] := Gmsh.CoordX[Brick_T4V1.NodeId[j]];
        Brick_T4V1.CoordY[j] := Gmsh.CoordY[Brick_T4V1.NodeId[j]];
        Brick_T4V1.CoordZ[j] := Gmsh.CoordZ[Brick_T4V1.NodeId[j]];
      end;

      Brick_T4V1.Conductivity := kc;

      Brick_T4V1.Calc;

      for j := 0 to Brick_T4V1.NbFaces -  1 do
      begin

        NodesOnSurface := 0;
        for k := 0 to Brick_T4V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_T4V1.Faces[j].CoordZ[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 3) then
          Brick_T4V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_T4V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_T4V1.Faces[j].CoordZ[k] - Thickness) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 3) then
          Brick_T4V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_T4V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_T4V1.Faces[j].CoordY[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 3) then
          Brick_T4V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_T4V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_T4V1.Faces[j].CoordY[k] - Width) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = 3) then
          Brick_T4V1.SetSourceOnFace(j, hc, Tinf);

      end;

      Ke := Brick_T4V1.K;
      be := Brick_T4V1.b;

    end;

    if Gmsh.ElementType[i] = GMSH_HEXA then
    begin

      NbNodes := 8;

      for j := 0 to NbNodes-1 do
      begin
        Node[j] := Gmsh.ElementNode[i, j];
        Brick_H8V1.NodeId[j] := Node[j];
      end;

      for j := 0 to NbNodes - 1 do
      begin
        Brick_H8V1.CoordX[j] := Gmsh.CoordX[Brick_H8V1.NodeId[j]];
        Brick_H8V1.CoordY[j] := Gmsh.CoordY[Brick_H8V1.NodeId[j]];
        Brick_H8V1.CoordZ[j] := Gmsh.CoordZ[Brick_H8V1.NodeId[j]];
      end;

      Brick_H8V1.Conductivity := kc;

      Brick_H8V1.Calc;

      for j := 0 to Brick_H8V1.NbFaces -  1 do
      begin

        NodesOnSurface := 0;
        for k := 0 to Brick_H8V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_H8V1.Faces[j].CoordZ[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_H8V1.Faces[j].NbNodes) then
          Brick_H8V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_H8V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_H8V1.Faces[j].CoordZ[k] - Thickness) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_H8V1.Faces[j].NbNodes) then
          Brick_H8V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_H8V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_H8V1.Faces[j].CoordY[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_H8V1.Faces[j].NbNodes) then
          Brick_H8V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_H8V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_H8V1.Faces[j].CoordY[k] - Width) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_H8V1.Faces[j].NbNodes) then
          Brick_H8V1.SetSourceOnFace(j, hc, Tinf);

      end;

      Ke := Brick_H8V1.K;
      be := Brick_H8V1.b;

    end;

    if Gmsh.ElementType[i] = GMSH_PRISM then
    begin

      NbNodes := 6;

      for j := 0 to NbNodes-1 do
      begin
        Node[j] := Gmsh.ElementNode[i, j];
        Brick_W6V1.NodeId[j] := Node[j];
      end;

      for j := 0 to NbNodes - 1 do
      begin
        Brick_W6V1.CoordX[j] := Gmsh.CoordX[Brick_W6V1.NodeId[j]];
        Brick_W6V1.CoordY[j] := Gmsh.CoordY[Brick_W6V1.NodeId[j]];
        Brick_W6V1.CoordZ[j] := Gmsh.CoordZ[Brick_W6V1.NodeId[j]];
      end;

      Brick_W6V1.Conductivity := kc;

      Brick_W6V1.Calc;

      for j := 0 to Brick_W6V1.NbFaces -  1 do
      begin

        NodesOnSurface := 0;
        for k := 0 to Brick_W6V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_W6V1.Faces[j].CoordZ[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_W6V1.Faces[j].NbNodes) then
          Brick_W6V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_W6V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_W6V1.Faces[j].CoordZ[k] - Thickness) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_W6V1.Faces[j].NbNodes) then
          Brick_W6V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_W6V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_W6V1.Faces[j].CoordY[k] - 0) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_W6V1.Faces[j].NbNodes) then
          Brick_W6V1.SetSourceOnFace(j, hc, Tinf);

        NodesOnSurface := 0;
        for k := 0 to Brick_W6V1.Faces[j].NbNodes - 1 do
        begin
          if (Abs(Brick_W6V1.Faces[j].CoordY[k] - Width) < 1E-8) then
          begin
            Inc(NodesOnSurface);
          end;
        end;

        if (NodesOnSurface = Brick_W6V1.Faces[j].NbNodes) then
          Brick_W6V1.SetSourceOnFace(j, hc, Tinf);

      end;

      Ke := Brick_W6V1.K;
      be := Brick_W6V1.b;

    end;

    // Standard method: Ax=b
    Assembly.Add(Ke, be, b, R1, C1, V1, n1, NbNodes, Node);

  end;

  Assembly.Free;

  SetLength(R1, n1);
  SetLength(C1, n1);
  SetLength(V1, n1);

  A := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  (******************** IMPOSE BOUNDARY CONDITIONS ********************)

  Penalty := TPenalty.Create;

  Penalty.Factor := 1000;
  Penalty.Impose(IsFixed, Values, A, b);

  Penalty.Free;

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 1);

  (******************** START ITERATION ********************)

  Analytic := TAnalytical.Create;

  // Instructing UMFPACK to maintain the factorisation (A.SparsePattern :=
  // sppNumeric in the original) no longer applies - PardisoSolve always
  // does a fresh one-shot analysis+factorisation+solve.

  SetLength(v, T.Rows);

  Caption := 'Solving...';

  // Iterative
  //T := FGMRESSolve(A, b);

  // ssUmfPack + mtSymmPosDef in the original -> direct solve, SPD.
  T := PardisoSolve(A, b, True);

  (******************** PLOT VALUES ********************)

  Series1.Clear;

  Chart1.LeftAxis.Title.Caption := 'Error (%)';
  //Chart1.LeftAxis.SetMinMax(0, 100);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if (CheckBox1.Checked) then
    begin
      Analytic.SteadyStateHeatConduction1D(Gmsh.CoordX[i], T1, T2, hc, Tinf, kc, Perimeter, SectionArea, Length, Ta);

      err := Abs(Ta - T[i,0]);

      Series1.AddXY(i, err);

    end;

  end;

  Series1.Title := '';

  Chart1.Invalidate;

  // Save results
  if CheckBox2.Checked then
  begin

    for i := 0 to Gmsh.NbNodes - 1 do
    begin

      v[i] := T[i,0];

    end;

  end;

  Gmsh.OpenFile('..\Data\tvalid.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Analytic.Free;

  (******************** END ITERATION ********************)

  Caption := 'Done.';

  Screen.Cursor := crDefault;

  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;
  Brick_W6V1.Free;

  Gmsh.Free;

  if CheckBox2.Checked then
  begin
    ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\tvalid.pos -noview', nil, SW_SHOWNORMAL);
  end;

end;

procedure TForm31.FormCreate(Sender: TObject);
begin

  ComboBox1.AddItem('TRI', nil);
  ComboBox1.AddItem('QUAD', nil);
  ComboBox1.AddItem('TETRA', nil);
  ComboBox1.AddItem('HEXA', nil);
  ComboBox1.AddItem('PRISM', nil);

  ComboBox1.ItemIndex := 0;

end;

end.
