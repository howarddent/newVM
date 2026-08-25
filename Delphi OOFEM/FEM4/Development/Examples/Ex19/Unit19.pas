unit Unit19;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ShellApi, CXS.FEMLAP.ShellExec,
  newVM, newVMsparse,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Brick_T4V1, CXS.FEMLAP.Brick_H8V1;

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

  i, j, n: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Edge_B2V1 : TEdge_B2V1;
  Face_Q4V1 : TFace_Q4V1;
  Face_T3V1 : TFace_T3V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;

  NodeId : Array[0..7] of Integer;
  cx, cy, cz : Array[0..7] of Double;

  MSize : Integer;

  // Assembly
  Assembly : TAssembly;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

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

  // Output data
  v : TDoubleArray;

  ExitCode : DWORD;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\cxs.geo -3', ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\cxs.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  // Set boundary conditions
  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);
  SetLength(OldToNew, Gmsh.NbNodes);

  n := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[i] := False;

    if (Abs(Gmsh.CoordX[i]) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := 1;
    end;

    OldToNew[i] := n;

    if (IsFixed[i] = False) then Inc(n);

  end;

  MSize := n;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;

  Fg := TVMobj.Create(MSize, 1);

  // FE Assembly and elimination

  Assembly := TAssembly.Create;

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    case Gmsh.ElementType[i] of
    GMSH_BEAM :
    begin

      NbNodes := 2;

      for j := 0 to NbNodes-1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Edge_B2V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to NbNodes-1 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Edge_B2V1.CoordX[j] := cx[j];
        Edge_B2V1.CoordY[j] := cy[j];
        Edge_B2V1.CoordZ[j] := cz[j];
      end;

      Edge_B2V1.Calc;

      Ke := Edge_B2V1.K;
      Fe := Edge_B2V1.b;

    end;
    GMSH_TRI :
    begin

      NbNodes := 3;

      for j := 0 to NbNodes-1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to NbNodes-1 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_T3V1.CoordX[j] := cx[j];
        Face_T3V1.CoordY[j] := cy[j];
        Face_T3V1.CoordZ[j] := cz[j];
      end;

      Face_T3V1.Calc;

      Ke := Face_T3V1.K;
      Fe := Face_T3V1.b;

    end;
    GMSH_QUAD :
    begin

      NbNodes := 4;

      for j := 0 to NbNodes-1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_Q4V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to NbNodes-1 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_Q4V1.CoordX[j] := cx[j];
        Face_Q4V1.CoordY[j] := cy[j];
        Face_Q4V1.CoordZ[j] := cz[j];
      end;

      Face_Q4V1.Calc;

      Ke := Face_Q4V1.K;
      Fe := Face_Q4V1.b;

    end;
    GMSH_TETRA :
    begin

      NbNodes := 4;

      for j := 0 to NbNodes-1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Brick_T4V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to NbNodes-1 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Brick_T4V1.CoordX[j] := cx[j];
        Brick_T4V1.CoordY[j] := cy[j];
        Brick_T4V1.CoordZ[j] := cz[j];
      end;

      Brick_T4V1.Calc;

      Ke := Brick_T4V1.K;
      Fe := Brick_T4V1.b;

    end;
    GMSH_HEXA :
    begin

      NbNodes := 8;

      for j := 0 to NbNodes-1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Brick_H8V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to NbNodes-1 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Brick_H8V1.CoordX[j] := cx[j];
        Brick_H8V1.CoordY[j] := cy[j];
        Brick_H8V1.CoordZ[j] := cz[j];
      end;

      Brick_H8V1.Calc;

      Ke := Brick_H8V1.K;
      Fe := Brick_H8V1.b;

    end;
    else

      raise Exception.Create('Error: Unkown element.');

    end;

    Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, NbNodes, NodeId, MSize, IsFixed, Values, OldToNew);

  end;

  Assembly.Free;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  // Build global stiffness matrix
  Kg := TripletsToSparse(MSize,MSize,R1,C1,V1);

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False). See
  // newVMsparse.pas's own header comment for the full solver mapping.
  ug := PardisoSolve(Kg, Fg, False);

  Screen.Cursor := crDefault;

  SetLength(v, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    if IsFixed[i] = True then
      v[i] := Values[i]
    else
      v[i] := ug[OldToNew[i],0];
  end;

  Gmsh.OpenFile('..\Data\cxs.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\cxs.pos', nil, SW_SHOWNORMAL) ;

end;

end.
