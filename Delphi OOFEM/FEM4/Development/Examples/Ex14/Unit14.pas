unit Unit14;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, CXS.FEMLAP.Gmsh, StdCtrls, newVM, newVMsparse,
  ShellApi, CXS.FEMLAP.ShellExec, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Brick_T4V1, CXS.FEMLAP.Brick_H8V1;

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.Button1Click(Sender: TObject);
var

  i, j, k, n: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  Edge_B2V1 : TEdge_B2V1;
  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;

  // Element stiffness and load
  Ke : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // BC's
  bc : TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode : DWORD;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\mixed.geo -3', ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\mixed.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;

  Fg := TVMobj.Create(Gmsh.NbNodes, 1);

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_BEAM then
    begin

      for j := 0 to 1 do
      begin
        Edge_B2V1.NodeId[j] := Gmsh.ElementNode[i, j];
      end;

      for j := 0 to 1 do
      begin
        Edge_B2V1.CoordX[j] := Gmsh.CoordX[Edge_B2V1.NodeId[j]];
        Edge_B2V1.CoordY[j] := Gmsh.CoordY[Edge_B2V1.NodeId[j]];
        Edge_B2V1.CoordZ[j] := Gmsh.CoordZ[Edge_B2V1.NodeId[j]];
      end;

      Edge_B2V1.Calc;

      Ke := Edge_B2V1.K;

      for j := 0 to 1 do
      begin
        for k := 0 to 1 do
        begin
          R1[n] := Edge_B2V1.NodeId[j];
          C1[n] := Edge_B2V1.NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

    end;

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        Face_T3V1.NodeId[j] := Gmsh.ElementNode[i, j];
      end;

      for j := 0 to 2 do
      begin
        Face_T3V1.CoordX[j] := Gmsh.CoordX[Face_T3V1.NodeId[j]];
        Face_T3V1.CoordY[j] := Gmsh.CoordY[Face_T3V1.NodeId[j]];
        Face_T3V1.CoordZ[j] := Gmsh.CoordZ[Face_T3V1.NodeId[j]];
      end;

      Face_T3V1.Calc;

      Face_T3V1.Thickness := 0.5;
      Face_T3V1.Conductivity := 1.0;

      Ke := Face_T3V1.K;

      for j := 0 to 2 do
      begin
        for k := 0 to 2 do
        begin
          R1[n] := Face_T3V1.NodeId[j];
          C1[n] := Face_T3V1.NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

    end;

    if Gmsh.ElementType[i] = GMSH_QUAD then
    begin

      for j := 0 to 3 do
      begin
        Face_Q4V1.NodeId[j] := Gmsh.ElementNode[i, j];
      end;

      for j := 0 to 3 do
      begin
        Face_Q4V1.CoordX[j] := Gmsh.CoordX[Face_Q4V1.NodeId[j]];
        Face_Q4V1.CoordY[j] := Gmsh.CoordY[Face_Q4V1.NodeId[j]];
        Face_Q4V1.CoordZ[j] := Gmsh.CoordZ[Face_Q4V1.NodeId[j]];
      end;

      Face_Q4V1.Calc;

      Face_Q4V1.Thickness := 0.5;
      Face_Q4V1.Conductivity := 1.0;

      Ke := Face_Q4V1.K;

      for j := 0 to 3 do
      begin
        for k := 0 to 3 do
        begin
          R1[n] := Face_Q4V1.NodeId[j];
          C1[n] := Face_Q4V1.NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

    end;

    if Gmsh.ElementType[i] = GMSH_TETRA then
    begin

      for j := 0 to 3 do
      begin
        Brick_T4V1.NodeId[j] := Gmsh.ElementNode[i, j];
      end;

      for j := 0 to 3 do
      begin
        Brick_T4V1.CoordX[j] := Gmsh.CoordX[Brick_T4V1.NodeId[j]];
        Brick_T4V1.CoordY[j] := Gmsh.CoordY[Brick_T4V1.NodeId[j]];
        Brick_T4V1.CoordZ[j] := Gmsh.CoordZ[Brick_T4V1.NodeId[j]];
      end;

      Brick_T4V1.Calc;

      Brick_T4V1.Conductivity := 1.0;

      Ke := Brick_T4V1.K;

      for j := 0 to 3 do
      begin
        for k := 0 to 3 do
        begin
          R1[n] := Brick_T4V1.NodeId[j];
          C1[n] := Brick_T4V1.NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

    end;

    if Gmsh.ElementType[i] = GMSH_HEXA then
    begin

      for j := 0 to 7 do
      begin
        Brick_H8V1.NodeId[j] := Gmsh.ElementNode[i, j];
      end;

      for j := 0 to 7 do
      begin
        Brick_H8V1.CoordX[j] := Gmsh.CoordX[Brick_H8V1.NodeId[j]];
        Brick_H8V1.CoordY[j] := Gmsh.CoordY[Brick_H8V1.NodeId[j]];
        Brick_H8V1.CoordZ[j] := Gmsh.CoordZ[Brick_H8V1.NodeId[j]];
      end;

      Brick_H8V1.Calc;

      Brick_H8V1.Conductivity := 1.0;

      Ke := Brick_H8V1.K;

      for j := 0 to 7 do
      begin
        for k := 0 to 7 do
        begin
          R1[n] := Brick_H8V1.NodeId[j];
          C1[n] := Brick_H8V1.NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

    end;

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if (Abs(Gmsh.CoordZ[i]) < 1E-3) then
    begin
      Gmsh.NodeBCIsFixed[i] := True;
      Gmsh.NodeBCValue[i] := 0;
    end;

    if (Abs(Gmsh.CoordX[i] + 1) < 1E-3) then
    begin
      Gmsh.NodeBCIsFixed[i] := True;
      Gmsh.NodeBCValue[i] := 1;
    end;

  end;

  bc := SparseDiag(Kg);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if Gmsh.NodeBCIsFixed[i] = True then
    begin

      // Penalty method: factor 1000
      bc[i,0] := 1000;
      Fg[i,0] := 1000 * Gmsh.NodeBCValue[i];

    end;

  end;

  SetDiagonal(Kg, bc);

  // UMFPACK
  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False).
  ug := PardisoSolve(Kg, Fg, False);

  Screen.Cursor := crDefault;

  SetLength(v, ug.Rows);

  for i := 0 to Gmsh.NbNodes - 1 do
    v[i] := ug[i,0];

  Gmsh.OpenFile('..\Data\mixed.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\mixed.pos', nil, SW_SHOWNORMAL) ;

end;

end.
