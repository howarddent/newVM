unit Unit3;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Penalty, CXS.FEMLAP.Face_T3V1;

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

  Face_T3V1 : TFace_T3V1;

  NodeId : Array[0..2] of Integer;
  cx, cy, cz : Array[0..2] of Double;

  // Assembly and penalty
  Assembly : TAssembly;
  Penalty : TPenalty;

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

  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  // Output data
  v : TDoubleArray;

  ExitCode : DWORD;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\curved.geo', '-3'], ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\curved.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 9);
  SetLength(C1, Gmsh.NbElements * 9);
  SetLength(V1, Gmsh.NbElements * 9);

  Assembly := TAssembly.Create;

  Face_T3V1 := TFace_T3V1.Create;

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
      Fe := Face_T3V1.b;

      Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId);

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

  for i := 0 to n-1 do
  begin

    if (R1[i] > Gmsh.NbNodes) or (C1[i] > Gmsh.NbNodes) then
      raise Exception.Create('Problem');

  end;

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    IsFixed[i] := False;
    Values[i] := 0;

    if (Abs(Gmsh.CoordY[i]) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := 0;
    end;

    if (Abs(Gmsh.CoordX[i]) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := 1;
    end;

  end;

  Penalty := TPenalty.Create;

  Penalty.Factor := 1000;
  Penalty.Impose(IsFixed, Values, Kg, Fg);

  Penalty.Free;

  // ssUmfPack + mtSymmetric in the original -> the mapping table only
  // covers mtSymmPosDef/mtGeneral; PardisoSolve has no plain-symmetric
  // (indefinite) mtype, only SymmetricPosDef=True (mtype=2) or False
  // (mtype=11, general). This is a Laplace/potential (thermal-style)
  // assembly built purely from Face_T3V1.K, imposed via the penalty
  // method (which only adds to diagonal entries), so Kg is symmetric
  // positive definite for a well-posed problem - PardisoSolve(...,True)
  // is the correct nearest match, not just an arbitrary pick.
  ug := PardisoSolve(Kg, Fg, True);

  Screen.Cursor := crDefault;

  SetLength(v, ug.Rows);

  for i := 0 to Gmsh.NbNodes - 1 do
    v[i] := ug[i,0];

  Gmsh.OpenFile('..\Data\curved.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Face_T3V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\curved.pos', nil, SW_SHOWNORMAL) ;

end;

end.
