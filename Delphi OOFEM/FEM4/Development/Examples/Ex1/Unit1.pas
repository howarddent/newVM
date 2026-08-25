unit Unit1;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, newVM, newVMsparse, CXS.FEMLAP.Gmsh,
  CXS.FEMLAP.Assembly, CXS.FEMLAP.Penalty, CXS.FEMLAP.Face_T3V1;

type
  TForm1 = class(TForm)
    Button1: TButton;
    Memo1: TMemo;
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

  Face_T3V1 : TFace_T3V1;

  NodeId : Array[0..2] of Integer;
  cx, cy, cz : Array[0..2] of Double;

  // Element stiffness and load
  Assembly : TAssembly;
  Penalty : TPenalty;

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

  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  c : Double;

begin

  {***********************************************************
  Introduction to finite elements in engineering, 3rd Edition,
  Tirupathi R. Chandrupatla, Ashok D. Belegundu
  Example 10.5, Page 334
  ***********************************************************}

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\example10.5.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 9);
  SetLength(C1, Gmsh.NbElements * 9);
  SetLength(V1, Gmsh.NbElements * 9);

  Face_T3V1 := TFace_T3V1.Create;

  Assembly := TAssembly.Create;

  Fg := TVMobj.Create(Gmsh.NbNodes, 1);

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 2 do
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

      Face_T3V1.SetSourceOnFace(2);

      Fe := Face_T3V1.b;

      Assembly.Add(Ke, fe, Fg, R1, C1, V1, n, 3, NodeId);

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

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    IsFixed[i] := False;
    Values[i] := 0;
  end;

  IsFixed[2] := True;
  Values[2] := 0;

  IsFixed[3] := True;
  Values[3] := 0;

  IsFixed[4] := True;
  Values[4] := 0;

  Penalty := TPenalty.Create;

  Penalty.Factor := 1000;

  Penalty.Impose(IsFixed, Values, Kg, Fg);

  Penalty.Free;

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False). See
  // newVMsparse.pas's own header comment for the full solver mapping.
  ug := PardisoSolve(Kg, Fg, False);

  Screen.Cursor := crDefault;

  //ViewValues(ug);

  c := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 2 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_T3V1.CoordX[j] := cx[j];
        Face_T3V1.CoordY[j] := cy[j];
        Face_T3V1.CoordZ[j] := cz[j];
      end;

      Face_T3V1.Calc;

      c := c + 8 * Face_T3V1.Area / 3 * (ug[NodeId[0],0] + ug[NodeId[1],0] + ug[NodeId[2],0]);

    end;

  end;

  Face_T3V1.Free;

  Gmsh.Free;

  ShowMessage('alpha = ' + FloatToStr(1/c) + ' x M/G');

end;

end.
