unit CXS.FEMLAP.Torsion;

{$mode delphi}{$H+}

interface

uses SysUtils, newVM, newVMsparse,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node, CXS.FEMLAP.Element, CXS.FEMLAP.Face_T3V1;

type TTorsion = class(TObject)

  public

    (*
    Description:
      Returns torsional constant of a section.
    Parameters:
      Nodes - [in] array with nodal coordinates (x0, y0, z0, x1, y1, z1, x2, y2, z2, ...).
      Triangles - [in] triangle connectivity.
      Boundary - [in] boundary connectvity.
    *)
    function CalcTorsionalConstant(Nodes : TDoubleArray; Triangles: TIntegerArray; Boundary : TIntegerArray) : Double;

end;

implementation

{ TTorsion }

function TTorsion.CalcTorsionalConstant(Nodes: TDoubleArray; Triangles,
  Boundary: TIntegerArray) : Double;
var

  i, j, k, n : Integer;

  NbNodes : Integer;
  NbTriangles : Integer;

  Face_T3V1 : TFace_T3V1;

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

  diag : TVMobj;

  // Torsional constant
  c : Double;

  e : ELibException;

begin

  if Length(Nodes) mod 3 <> 0 then
  begin

    e := ELibException.Create('Error: Array of nodes has wrong size.');
    e.Error := erWrongSizedArray;
    Raise e;

  end;

  if Length(Triangles) mod 3 <> 0 then
  begin

    e := ELibException.Create('Error: Array of triangles has wrong size.');
    e.Error := erWrongSizedArray;
    Raise e;

  end;

  Face_T3V1 := TFace_T3V1.Create;

  NbNodes := Round(Length(Nodes) / 3);
  NbTriangles := Round(Length(Triangles) / 3);

  Fg := TVMobj.Create(NbNodes, 1);
  ug := TVMobj.Create(NbNodes, 1);

  SetLength(R1, NbTriangles * 9);
  SetLength(C1, NbTriangles * 9);
  SetLength(V1, NbTriangles * 9);

  n := 0;

  for i := 0 to NbTriangles - 1 do
  begin

    for j := 0 to 2 do
    begin
      Face_T3V1.NodeId[j] := Triangles[3*i + j];
    end;

    for j := 0 to 2 do
    begin
      Face_T3V1.CoordX[j] := Nodes[3*Face_T3V1.NodeId[j] + 0];
      Face_T3V1.CoordY[j] := Nodes[3*Face_T3V1.NodeId[j] + 1];
      Face_T3V1.CoordZ[j] := Nodes[3*Face_T3V1.NodeId[j] + 2];
    end;

    Face_T3V1.Calc;

    Face_T3V1.Conductivity := 1.0;

    Ke := Face_T3V1.K;

    Face_T3V1.SetSourceOnFace(2);

    Fe := Face_T3V1.b;

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

    Fg[Face_T3V1.NodeId[0],0] := Fg[Face_T3V1.NodeId[0],0] + Fe[0,0];
    Fg[Face_T3V1.NodeId[1],0] := Fg[Face_T3V1.NodeId[1],0] + Fe[1,0];
    Fg[Face_T3V1.NodeId[2],0] := Fg[Face_T3V1.NodeId[2],0] + Fe[2,0];

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  // Build global stiffness matrix
  Kg := TripletsToSparse(NbNodes,NbNodes,R1,C1,V1);

  // Set boundary conditions
  diag := SparseDiag(Kg);

  for i := 0 to Length(Boundary) - 1 do
  begin

    // Penalty method: factor 1000
    diag[Boundary[i],0] := 1000;
    Fg[Boundary[i],0] := 0;

  end;

  SetDiagonal(Kg, diag);

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False).
  ug := PardisoSolve(Kg, Fg, False);

  c := 0;

  for i := 0 to NbTriangles - 1 do
  begin

    for j := 0 to 2 do
    begin
      Face_T3V1.NodeId[j] := Triangles[3*i + j];
    end;

    for j := 0 to 2 do
    begin
      Face_T3V1.CoordX[j] := Nodes[3*Face_T3V1.NodeId[j] + 0];
      Face_T3V1.CoordY[j] := Nodes[3*Face_T3V1.NodeId[j] + 1];
      Face_T3V1.CoordZ[j] := Nodes[3*Face_T3V1.NodeId[j] + 2];
    end;

    Face_T3V1.Calc;

    c := c + 2 * Face_T3V1.Area / 3 * (ug[Face_T3V1.NodeId[0],0] + ug[Face_T3V1.NodeId[1],0] + ug[Face_T3V1.NodeId[2],0]);

  end;

  Result := c;

  Face_T3V1.Free;

end;

end.
