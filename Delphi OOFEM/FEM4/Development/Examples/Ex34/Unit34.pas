unit Unit34;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls,
  newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1,
  CXS.FEMLAP.Brick_T4V1, CXS.FEMLAP.Brick_H8V1, CXS.FEMLAP.Brick_W6V1,
  CXS.FEMLAP.Analytical,
  CXS.FEMLAP.Penalty,
  ExtCtrls, TAGraph, TASeries;

type
  TForm34 = class(TForm)
    Button1: TButton;
    Chart1: TChart;
    Series1: TLineSeries;
    Series2: TLineSeries;
    Edit1: TEdit;
    Label2: TLabel;
    Label1: TLabel;
    ComboBox1: TComboBox;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form34: TForm34;

implementation

{$R *.lfm}

procedure TForm34.Button1Click(Sender: TObject);
var

  ii, jj, kk, n1, n2: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Node : Array[0..7] of Integer;

  Edge_B2V1 : TEdge_B2V1;
  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;
  Brick_W6V1 : TBrick_W6V1;

  // Element stiffness and mass matrix
  Me : TVMobj;
  Ke : TVMobj;

  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1, V2: TDoubleArray;

  // Global stiffness and mass matrix
  A, K, M : TVMSparseMtx;

  b: TVMobj;

  // Unknown vector
  T0, T: TVMobj;

  // Residual
  R : TVMobj;
  Residual : Double;

  // Output data
  v : TDoubleArray;

  ExitCode: DWORD;

  nIter : Integer;

  time, dt : Double;

  // BC's
  diag : TVMobj;

  bT : TVMobj;

  Assembly : TAssembly;

  MeshSize : Double;

  Penalty : TPenalty;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  Tinf, Te0 : Double;
  teta : Double;

  Length, Width, Thickness : Double;
  Perimeter, SectionArea : Double;
  Tb : Double;

  hc, e : Double;
  kc : Double;

  Analytical : TAnalytical;

  Ta, err : Double;

  NodesOnSurface: Integer;

begin

  (******************** DATA ********************)

  hc := 1E-30;
  e := 0.7;

  kc := 1;

  Length := 1;
  Width := 0.05;
  Thickness := 0.05;

  Perimeter := 2 * Thickness + 2 * Width;
  SectionArea := Thickness * Width;

  Tb := 500;
  Tinf := 0;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := StrToFloat(Edit1.Text);

  Gmsh.OpenFile('..\Data\vrad.geo');
  if ComboBox1.Text = 'BEAM' then
    Gmsh.GenerateLine(Length, MeshSize, GMSH_BEAM)
  else if ComboBox1.Text = 'TRI' then
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

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\vrad.geo -3 -optimize', ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\vrad.msh');
  Gmsh.ReadMesh();
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);
  SetLength(V2, Gmsh.NbElements * 64);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;
  Brick_W6V1 := TBrick_W6V1.Create;

  (******************** SET BOUNDARY CONDITIONS ********************)

  Caption := 'Setting boundary conditions...';

  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[ii] := False;

    if (Abs(Gmsh.CoordX[ii] - 0.0) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := Tb;
    end;

  end;

  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** TIME INTERVAL ********************)
  dt := 0.01;

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 1);

  (******************** START ITERATION ********************)

  SetLength(v, T.Rows);

  time := 0;

  nIter := 10000;

  for ti := 1 to nIter do
  begin

    time := time + dt;

    //Caption := 'Time = ' + Format('%.3f', [time]) + ' s';

    T0 := CopyObj(T);

    (******************** RESET SOURCE VECTOR ********************)

    b := TVMobj.Create(Gmsh.NbNodes, 1);

    (******************** MATRIX SETUP ********************)

    Assembly := TAssembly.Create;

    n1 := 0;

    for ii := 0 to Gmsh.NbElements - 1 do
    begin

      NbNodes := 0;

      if Gmsh.ElementType[ii] = GMSH_BEAM then
      begin

        NbNodes := 2;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Edge_B2V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Edge_B2V1.CoordX[jj] := Gmsh.CoordX[Edge_B2V1.NodeId[jj]];
          Edge_B2V1.CoordY[jj] := Gmsh.CoordY[Edge_B2V1.NodeId[jj]];
          Edge_B2V1.CoordZ[jj] := Gmsh.CoordZ[Edge_B2V1.NodeId[jj]];
        end;

        Edge_B2V1.Transient := True;

        Edge_B2V1.TimeInterval := dt;

        Edge_B2V1.Conductivity := kc;

        Edge_B2V1.SectionArea := SectionArea;

        Edge_B2V1.Perimeter := Perimeter;

        Edge_B2V1.Calc;

        Te0 := 0;
        for kk := 0 to Edge_B2V1.NbNodes - 1 do
          Te0 := Te0 + T0[Edge_B2V1.NodeId[kk],0];

        if Edge_B2V1.NbNodes > 0 then
          Te0 := Te0 / Edge_B2V1.NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        Edge_B2V1.SetSourceOnEdge(e, teta, Tinf);

        Ke := Edge_B2V1.K;
        Me := Edge_B2V1.M;

        be := Edge_B2V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_TRI then
      begin

        NbNodes := 3;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Face_T3V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Face_T3V1.CoordX[jj] := Gmsh.CoordX[Face_T3V1.NodeId[jj]];
          Face_T3V1.CoordY[jj] := Gmsh.CoordY[Face_T3V1.NodeId[jj]];
          Face_T3V1.CoordZ[jj] := Gmsh.CoordZ[Face_T3V1.NodeId[jj]];
        end;

        Face_T3V1.Transient := True;

        Face_T3V1.TimeInterval := dt;

        Face_T3V1.Conductivity := kc;

        Face_T3V1.Thickness := Thickness;

        Face_T3V1.Calc;

        for jj := 0 to Face_T3V1.NbEdges -  1 do
        begin

          Te0 := 0;
          for kk := 0 to Face_T3V1.Edges[jj].NbNodes - 1 do
            Te0 := Te0 + T0[Face_T3V1.Edges[jj].NodeId[kk],0];

          if Face_T3V1.Edges[jj].NbNodes > 0 then
            Te0 := Te0 / Face_T3V1.Edges[jj].NbNodes;

          teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Face_T3V1.Edges[jj].NbNodes - 1 do
          begin
            if (Abs(Face_T3V1.Edges[jj].CoordY[kk] - 0) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Face_T3V1.Edges[jj].NbNodes) then
            Face_T3V1.SetSourceOnEdge(jj, e, teta, Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Face_T3V1.Edges[jj].NbNodes - 1 do
          begin
            if (Abs(Face_T3V1.Edges[jj].CoordY[kk] - Width) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Face_T3V1.Edges[jj].NbNodes) then
            Face_T3V1.SetSourceOnEdge(jj, e, teta, Tinf);

        end;

        Te0 := 0;
        for kk := 0 to Face_T3V1.NbNodes - 1 do
          Te0 := Te0 + T0[Face_T3V1.NodeId[kk],0];

        if Face_T3V1.NbNodes > 0 then
          Te0 := Te0 / Face_T3V1.NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        Face_T3V1.SetSourceOnFace(e, teta, Tinf);
        Face_T3V1.SetSourceOnFace(e, teta, Tinf);

        Ke := Face_T3V1.K;
        Me := Face_T3V1.M;

        be := Face_T3V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_QUAD then
      begin

        NbNodes := 4;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Face_Q4V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Face_Q4V1.CoordX[jj] := Gmsh.CoordX[Face_Q4V1.NodeId[jj]];
          Face_Q4V1.CoordY[jj] := Gmsh.CoordY[Face_Q4V1.NodeId[jj]];
          Face_Q4V1.CoordZ[jj] := Gmsh.CoordZ[Face_Q4V1.NodeId[jj]];

        end;

        Face_Q4V1.Transient := True;

        Face_Q4V1.TimeInterval := dt;

        Face_Q4V1.Conductivity := kc;

        Face_Q4V1.Thickness := Thickness;

        Face_Q4V1.Calc;

        for jj := 0 to Face_Q4V1.NbEdges -  1 do
        begin

          Te0 := 0;
          for kk := 0 to Face_Q4V1.Edges[jj].NbNodes - 1 do
            Te0 := Te0 + T0[Face_Q4V1.Edges[jj].NodeId[kk],0];

          if Face_Q4V1.Edges[jj].NbNodes > 0 then
            Te0 := Te0 / Face_Q4V1.Edges[jj].NbNodes;

          teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Face_Q4V1.Edges[jj].NbNodes - 1 do
          begin
            if (Abs(Face_Q4V1.Edges[jj].CoordY[kk] - 0) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Face_Q4V1.Edges[jj].NbNodes) then
            Face_Q4V1.SetSourceOnEdge(jj, e, teta, Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Face_Q4V1.Edges[jj].NbNodes - 1 do
          begin
            if (Abs(Face_Q4V1.Edges[jj].CoordY[kk] - Width) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Face_Q4V1.Edges[jj].NbNodes) then
            Face_Q4V1.SetSourceOnEdge(jj, e, teta, Tinf);

        end;

        Te0 := 0;
        for kk := 0 to Face_Q4V1.NbNodes - 1 do
          Te0 := Te0 + T0[Face_Q4V1.NodeId[kk],0];

        if Face_Q4V1.NbNodes > 0 then
          Te0 := Te0 / Face_Q4V1.NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        Face_Q4V1.SetSourceOnFace(e, teta, Tinf);
        Face_Q4V1.SetSourceOnFace(e, teta, Tinf);

        Ke := Face_Q4V1.K;
        Me := Face_Q4V1.M;

        be := Face_Q4V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_TETRA then
      begin

        NbNodes := 4;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Brick_T4V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Brick_T4V1.CoordX[jj] := Gmsh.CoordX[Brick_T4V1.NodeId[jj]];
          Brick_T4V1.CoordY[jj] := Gmsh.CoordY[Brick_T4V1.NodeId[jj]];
          Brick_T4V1.CoordZ[jj] := Gmsh.CoordZ[Brick_T4V1.NodeId[jj]];

        end;

        Brick_T4V1.Transient := True;

        Brick_T4V1.TimeInterval := dt;

        Brick_T4V1.Conductivity := kc;

        Brick_T4V1.Calc;

        for jj := 0 to Brick_T4V1.NbFaces -  1 do
        begin

          Te0 := 0;
          for kk := 0 to Brick_T4V1.Faces[jj].NbNodes - 1 do
            Te0 := Te0 + T0[Brick_T4V1.Faces[jj].NodeId[kk],0];

          if Brick_T4V1.Faces[jj].NbNodes > 0 then
            Te0 := Te0 / Brick_T4V1.Faces[jj].NbNodes;

          teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_T4V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_T4V1.Faces[jj].CoordY[kk] - 0) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_T4V1.Faces[jj].NbNodes) then
            Brick_T4V1.SetSourceOnFace(jj, e, teta, Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_T4V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_T4V1.Faces[jj].CoordY[kk] - Width) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_T4V1.Faces[jj].NbNodes) then
            Brick_T4V1.SetSourceOnFace(jj, e, teta, Tinf);

        end;

        Ke := Brick_T4V1.K;
        Me := Brick_T4V1.M;

        be := Brick_T4V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_HEXA then
      begin

        NbNodes := 8;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Brick_H8V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Brick_H8V1.CoordX[jj] := Gmsh.CoordX[Brick_H8V1.NodeId[jj]];
          Brick_H8V1.CoordY[jj] := Gmsh.CoordY[Brick_H8V1.NodeId[jj]];
          Brick_H8V1.CoordZ[jj] := Gmsh.CoordZ[Brick_H8V1.NodeId[jj]];

        end;

        Brick_H8V1.Transient := True;

        Brick_H8V1.TimeInterval := dt;

        Brick_H8V1.Conductivity := kc;

        Brick_H8V1.Calc;

        for jj := 0 to Brick_H8V1.NbFaces -  1 do
        begin

          Te0 := 0;
          for kk := 0 to Brick_H8V1.Faces[jj].NbNodes - 1 do
            Te0 := Te0 + T0[Brick_H8V1.Faces[jj].NodeId[kk],0];

          if Brick_H8V1.Faces[jj].NbNodes > 0 then
            Te0 := Te0 / Brick_H8V1.Faces[jj].NbNodes;

          teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_H8V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_H8V1.Faces[jj].CoordY[kk] - 0) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_H8V1.Faces[jj].NbNodes) then
            Brick_H8V1.SetSourceOnFace(jj, e, teta, Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_H8V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_H8V1.Faces[jj].CoordY[kk] - Width) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_H8V1.Faces[jj].NbNodes) then
            Brick_H8V1.SetSourceOnFace(jj, e, teta, Tinf);

        end;

        Ke := Brick_H8V1.K;
        Me := Brick_H8V1.M;

        be := Brick_H8V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_PRISM then
      begin

        NbNodes := 6;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Brick_W6V1.NodeId[jj] := Node[jj];
        end;

        for jj := 0 to NbNodes - 1 do
        begin
          Brick_W6V1.CoordX[jj] := Gmsh.CoordX[Brick_W6V1.NodeId[jj]];
          Brick_W6V1.CoordY[jj] := Gmsh.CoordY[Brick_W6V1.NodeId[jj]];
          Brick_W6V1.CoordZ[jj] := Gmsh.CoordZ[Brick_W6V1.NodeId[jj]];

        end;

        Brick_W6V1.Transient := True;

        Brick_W6V1.TimeInterval := dt;

        Brick_W6V1.Conductivity := kc;

        Brick_W6V1.Calc;

        for jj := 0 to Brick_W6V1.NbFaces -  1 do
        begin

          Te0 := 0;
          for kk := 0 to Brick_W6V1.Faces[jj].NbNodes - 1 do
            Te0 := Te0 + T0[Brick_W6V1.Faces[jj].NodeId[kk],0];

          if Brick_W6V1.Faces[jj].NbNodes > 0 then
            Te0 := Te0 / Brick_W6V1.Faces[jj].NbNodes;

          teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_W6V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_W6V1.Faces[jj].CoordY[kk] - 0) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_W6V1.Faces[jj].NbNodes) then
            Brick_W6V1.SetSourceOnFace(jj, e, teta, Tinf);

          NodesOnSurface := 0;
          for kk := 0 to Brick_W6V1.Faces[jj].NbNodes - 1 do
          begin
            if (Abs(Brick_W6V1.Faces[jj].CoordY[kk] - Width) < 1E-8) then
            begin
              Inc(NodesOnSurface);
            end;
          end;

          if (NodesOnSurface = Brick_W6V1.Faces[jj].NbNodes) then
            Brick_W6V1.SetSourceOnFace(jj, e, teta, Tinf);

        end;

        Ke := Brick_W6V1.K;
        Me := Brick_W6V1.M;

        be := Brick_W6V1.b;

      end;

      n2 := n1;

      // Standard method: Ax=b
      Assembly.Add(Ke, be, b, R1, C1, V1, n1, NbNodes, Node);

      // Mass matrix
      for jj := 0 to Nbnodes-1 do
      begin
        for kk := 0 to Nbnodes-1 do
        begin

          V2[n2] := Me[jj,kk];
          Inc(n2);

        end;

      end;

    end;

    Assembly.Free;

    SetLength(R1, n1);
    SetLength(C1, n1);
    SetLength(V1, n1);
    SetLength(V2, n1);

    K := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);
    M := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V2);

    A := SparseAdd(K, M);

    (******************** ADD TRANSIENT TERM ********************)

    bT := SparseMatMult(M, T0);

    b := b + bT;

    (******************** IMPOSE BOUNDARY CONDITIONS ********************)

    Penalty := TPenalty.Create;

    Penalty.Factor := 10000;
    Penalty.Impose(IsFixed, Values, A, b);

    Penalty.Free;

    (******************** SOLVE ********************)

    T := FGMRESSolve(A, b);

    R := T - T0;
    Residual := Norm(R);

    Caption := 'Residual = ' + Format('%.3e', [Residual]) + ' s';

    Application.ProcessMessages;

    if Residual < 1E-5 then Break;

    //ViewValues(T);
    //ViewValues(b);

  end;

  (******************** PLOT RESULTS ********************)
  Series1.Clear;
  Series2.Clear;

  Series1.Title := 'Analytical';
  Series2.Title := 'FEM';

  //Chart1.LeftAxis.Title.Caption := 'Error (%)';
  Chart1.LeftAxis.Title.Caption := 'Temperature';

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    Analytical.SteadyStateHeatConvectionRadiation1D(Gmsh.CoordX[ii], Tb, hc, e, kc, Perimeter, SectionArea, Ta);

    //err := Abs(Ta - T[ii,0]);

    Series1.AddXY(ii, Ta, FloatToStr(Gmsh.CoordX[ii]));

    Series2.AddXY(ii, T[ii,0], FloatToStr(Gmsh.CoordX[ii]));

    v[ii] := T[ii,0];

  end;

  // TAChart's TLineSeries has no SortByLabels equivalent - unneeded here
  // anyway, since points are already added in ascending X (= node index ii)
  // order above.

  (******************** SAVE RESULTS ********************)

  Gmsh.OpenFile('..\Data\vrad.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\vrad.pos -noview', nil, SW_SHOWNORMAL);

  (******************** END ITERATION ********************)

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;
  Brick_W6V1.Free;

  Gmsh.Free;

end;

procedure TForm34.FormCreate(Sender: TObject);
begin

  ComboBox1.AddItem('BEAM', nil);
  ComboBox1.AddItem('TRI', nil);
  ComboBox1.AddItem('QUAD', nil);
  ComboBox1.AddItem('TETRA', nil);
  ComboBox1.AddItem('HEXA', nil);
  ComboBox1.AddItem('PRISM', nil);

  ComboBox1.ItemIndex := 0;

end;

end.
