unit Unit4;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.Gmsh,
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

  MSize : Integer;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Assembly
  Assembly : TAssembly;

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

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\example10.4.msh');
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

    if (i = 3) or (i = 4) then
    begin
      IsFixed[i] := True;
      Values[i] := 180;
    end;

    OldToNew[i] := n;

    if (IsFixed[i] = False) then Inc(n);

  end;

  MSize := n;

  SetLength(R1, Gmsh.NbElements * 9);
  SetLength(C1, Gmsh.NbElements * 9);
  SetLength(V1, Gmsh.NbElements * 9);

  Face_T3V1 := TFace_T3V1.Create;

  Fg := TVMobj.Create(MSize, 1);

  // FE Assembly and elimination

  Assembly := TAssembly.Create;

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

      Face_T3V1.Conductivity := 1.5;

      Face_T3V1.Calc;

      if (i = 0) then
        Face_T3V1.SetSourceOnEdge(1, 50, 25);

      if (i = 2) then
        Face_T3V1.SetSourceOnEdge(1, 50, 25);

      Ke := Face_T3V1.K;
      Fe := Face_T3V1.b;

      // Elmination
      Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId, MSize, IsFixed, Values, OldToNew);

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
  Kg := TripletsToSparse(MSize,MSize,R1,C1,V1);

  // ssUmfPack + mtSymmetric in the original -> direct solve, symmetric
  // (SPD) matrix type - PardisoSolve(...,True). See newVMsparse.pas's own
  // header comment for the full solver mapping.
  ug := PardisoSolve(Kg, Fg, True);

  Screen.Cursor := crDefault;

  //ViewValues(ug);

  SetLength(v, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    if IsFixed[i] = True then
      v[i] := Values[i]
    else
      v[i] := ug[OldToNew[i],0];
  end;

  Gmsh.OpenFile('..\Data\example10.4.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Face_T3V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\example10.4.pos', nil, SW_SHOWNORMAL) ;

end;

end.
