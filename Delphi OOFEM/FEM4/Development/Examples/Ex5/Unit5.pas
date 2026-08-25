unit Unit5;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Penalty, CXS.FEMLAP.Edge_B2V1;

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

  Edge_B2V1 : TEdge_B2V1;

  NodeId : Array[0..1] of Integer;
  cx, cy, cz : Array[0..1] of Double;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Assembly and penalty
  Assembly : TAssembly;
  Penalty : TPenalty;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  // Output data
  v : TDoubleArray;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\beam.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  Assembly := TAssembly.Create;

  SetLength(R1, Gmsh.NbElements * 6);
  SetLength(C1, Gmsh.NbElements * 6);
  SetLength(V1, Gmsh.NbElements * 6);

  Edge_B2V1 := TEdge_B2V1.Create;

  Fg := TVMobj.Create(Gmsh.NbNodes, 1);

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_BEAM then
    begin

      for j := 0 to 1 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Edge_B2V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 1 do
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

      Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 2, NodeId);

    end
    else
    begin

      raise Exception.Create('Errror: Only beams supported.');

    end;

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  for i := 0 to n-1 do
  begin

    if (R1[i] > Gmsh.NbNodes) or (C1[i] > Gmsh.NbNodes) then
      raise Exception.Create('Problem');

  end;

  Assembly.Free;

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    IsFixed[i] := False;
    Values[i] := 0;

    if (Abs(Gmsh.CoordX[i]) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := 0;
    end;

    if (Abs(Gmsh.CoordX[i] - 1) < 1E-8) then
    begin
      IsFixed[i] := True;
      Values[i] := 1;
    end;

  end;

  Penalty := TPenalty.Create;

  Penalty.Factor := 1000;
  Penalty.Impose(IsFixed, Values, Kg, Fg);

  Penalty.Free;

  // ssUmfPack + mtSymmetric in the original -> the assembled matrix here is
  // a symmetric, penalty-imposed 1D conduction/stiffness matrix (same
  // [[1,-1],[-1,1]]*k/L diffusion operator as CXS.FEMLAP.Edge_B2V1's
  // SetDiffusionTerm, with Dirichlet-type fixed-value boundaries at both
  // ends of the beam), which is symmetric positive definite - so this maps
  // to the SPD direct solve, PardisoSolve(...,True), same reasoning as
  // Ex2's mtSymmetric -> True mapping (see Unit2.pas's own comment).
  ug := PardisoSolve(Kg, Fg, True);

  Screen.Cursor := crDefault;

  //ViewValues(ug);

  SetLength(v, ug.Rows);

  for i := 0 to Gmsh.NbNodes - 1 do
    v[i] := ug[i,0];

  Gmsh.OpenFile('..\Data\beam.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Edge_B2V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\beam.pos', nil, SW_SHOWNORMAL) ;

end;

end.
