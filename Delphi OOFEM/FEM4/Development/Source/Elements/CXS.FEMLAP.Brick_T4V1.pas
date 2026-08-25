unit CXS.FEMLAP.Brick_T4V1;

// Tetra brick element with 4 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node, CXS.FEMLAP.Element_Brick, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1;

(*
   Tetrahedral element.

                      eta

                      |
                      *2
                     /| \
                     /|   \
                      |     \
                    / |       \ 1
                      *0-------*-----> xi
                   / /      _ -
                    /   _ -
                  //  -
                  *3
                 /
               zeta

*)

type TBrick_T4V1 = class(TElement_Brick)

  private

    x1, y1, z1: Double;
    x2, y2, z2: Double;
    x3, y3, z3: Double;
    x4, y4, z4: Double;

    x14, x24, x34 : Double;
    y14, y24, y34 : Double;
    z14, z24, z34 : Double;

    procedure SetTransientTerm;
    procedure SetDiffusionTerm;

  public

    constructor Create; override;
    destructor Destroy; override;

    procedure CalcGeoProperties; override;
    procedure Calc; override;
    procedure ReCalcD; override;

    (*
    Description:
      Set source on node.
    Parameters:
      NIndex - [in] node id (0 - 3).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn : Double); overload;

    (*
    Description:
      Set source at center of edge.
    Parameters:
      EIndex - [in] node id (0 - 5).
      ve - [in] value at edge.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; ve : Double); overload;

    (*
    Description:
      Set source at center of face.
    Parameters:
      FIndex - [in] node id (0 - 3).
      vf - [in] value at face.
    *)
    procedure SetSourceOnFace(FIndex: Integer; vf : Double); overload;

    (*
    Description:
      Set source on face - convection.
    Parameters:
      FIndex - [in] node id (0 - 3).
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(FIndex: Integer; h, Tinf: Double); overload;

    (*
    Description:
      Set source on face - radiation.
    Parameters:
      FIndex - [in] node id (0 - 3).
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(FIndex: Integer; e, teta, Tinf: Double); overload;

    (*
    Description:
      Set source at center of brick.
    Parameters:
      vb - [in] value at center of brick.
    *)
    procedure SetSourceOnBrick(vb : Double); overload;

    procedure Integrate; override;

end;

implementation

{ TBrick_T4V1 }

procedure TBrick_T4V1.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if fTransient then SetTransientTerm;

end;

procedure TBrick_T4V1.CalcGeoProperties;
var

  i, j : Integer;

begin

  x1 := fNodes[0].x;
  y1 := fNodes[0].y;
  z1 := fNodes[0].z;

  x2 := fNodes[1].x;
  y2 := fNodes[1].y;
  z2 := fNodes[1].z;

  x3 := fNodes[2].x;
  y3 := fNodes[2].y;
  z3 := fNodes[2].z;

  x4 := fNodes[3].x;
  y4 := fNodes[3].y;
  z4 := fNodes[3].z;

  x14 := x1 - x4;
  y14 := y1 - y4;
  z14 := z1 - z4;

  x24 := x2 - x4;
  y24 := y2 - y4;
  z24 := z2 - z4;

  x34 := x3 - x4;
  y34 := y3 - y4;
  z34 := z3 - z4;

  // Create edges

  FEdges[0].NodeId[0] := 0;
  FEdges[0].NodeId[1] := 1;

  FEdges[1].NodeId[0] := 1;
  FEdges[1].NodeId[1] := 2;

  FEdges[2].NodeId[0] := 2;
  FEdges[2].NodeId[1] := 0;

  FEdges[3].NodeId[0] := 0;
  FEdges[3].NodeId[1] := 3;

  FEdges[4].NodeId[0] := 1;
  FEdges[4].NodeId[1] := 3;

  FEdges[5].NodeId[0] := 2;
  FEdges[5].NodeId[1] := 3;

  for i := 0 to FNbEdges - 1 do
  begin
    for j := 0 to FEdges[i].NbNodes - 1 do
    begin
      FEdges[i].Node[j] := FNodes[FEdges[i].NodeId[j]];
    end;

    FEdges[i].CalcGeoProperties;
    FEdges[i].Integrate;

  end;

  // Create faces

  FFaces[0].NodeId[0] := 0;
  FFaces[0].NodeId[1] := 1;
  FFaces[0].NodeId[2] := 2;

  FFaces[1].NodeId[0] := 1;
  FFaces[1].NodeId[1] := 3;
  FFaces[1].NodeId[2] := 2;

  FFaces[2].NodeId[0] := 2;
  FFaces[2].NodeId[1] := 3;
  FFaces[2].NodeId[2] := 0;

  FFaces[3].NodeId[0] := 3;
  FFaces[3].NodeId[1] := 1;
  FFaces[3].NodeId[2] := 0;

  for i := 0 to FNbFaces - 1 do
  begin
    for j := 0 to FFaces[i].NbNodes - 1 do
    begin
      FFaces[i].Node[j] := FNodes[FFaces[i].NodeId[j]];
    end;

    FFaces[i].CalcGeoProperties;
    FFaces[i].Integrate;

  end;

  FVolume := Abs(1 /6 * (x14*(y24*z34-y34*z24)-y14*(x24*z34-x34*z24)+(x24*y34-x34*y24)*z14));

end;

constructor TBrick_T4V1.Create;
var

  i : Integer;

begin

  inherited;

  FNbNodes := 4;
  FNbEdges := 6;
  FNbFaces := 4;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);
  SetLength(FEdges, FNbEdges);
  SetLength(FFaces, FNbFaces);

  for i := 0 to FNbEdges - 1 do
    FEdges[i] := TEdge_B2V1.Create;

  for i := 0 to FNbFaces - 1 do
    FFaces[i] := TFace_T3V1.Create;

  Fb := TVMobj.Create(FNbNodes, 1);

  FM := TVMobj.Create(FNbNodes, FNbNodes);
  FK := TVMobj.Create(FNbNodes, FNbNodes);

end;

destructor TBrick_T4V1.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  for i := 0 to FNbFaces - 1 do
    FFaces[i].Free;

  inherited;

end;

procedure TBrick_T4V1.Integrate;
begin
  inherited;

end;

procedure TBrick_T4V1.ReCalcD;
begin
  inherited;

end;

procedure TBrick_T4V1.SetDiffusionTerm;
var

  bi, bj, bk, bl : Double;
  ci, cj, ck, cl : Double;
  di, dj, dk, dl : Double;

  B, BT : TVMobj;

begin

  bi := y24 * z34 - y34 * z24;
  bj := y34 * z14 - y14 * z34;
  bk := y14 * z24 - y24 * z14;
  bl := -(bi + bj + bk);

  ci := z24 * x34 - z34 * x24;
  cj := z34 * x14 - z14 * x34;
  ck := z14 * x24 - z24 * x14;
  cl := -(ci + cj + ck);

  di := x24 * y34 - x34 * y24;
  dj := x34 * y14 - x14 * y34;
  dk := x14 * y24 - x24 * y14;
  dl := -(di + dj + dk);

  B := TVMobj.Create(3,4);

  B[0, 0] := bi;
  B[0, 1] := bj;
  B[0, 2] := bk;
  B[0, 3] := bl;

  B[1, 0] := ci;
  B[1, 1] := cj;
  B[1, 2] := ck;
  B[1, 3] := cl;

  B[2, 0] := di;
  B[2, 1] := dj;
  B[2, 2] := dk;
  B[2, 3] := dl;

  if FVolume <> 0 then B := B * (1/(6 * FVolume));

  BT := B.Transpose;

  FK := MatMult(BT, B);

  FK := FK * (FVolume * FConductivity);

end;

procedure TBrick_T4V1.SetSourceOnBrick(vb: Double);
begin

  Fb := AddScalar(Fb, vb * FVolume * 0.25);

end;

procedure TBrick_T4V1.SetSourceOnEdge(EIndex: Integer; ve: Double);
var

  e : ELibException;

  j : Integer;

  n : Array[0..2] of Integer;

begin

  if (EIndex < 0) or (EIndex > FNbEdges-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FEdges[EIndex].NbNodes - 1 do
    n[j] := FEdges[EIndex].NodeId[j];

  Fb[n[0],0] := Fb[n[0],0] + ve * FEdges[EIndex].Length * 0.5;
  Fb[n[1],0] := Fb[n[1],0] + ve * FEdges[EIndex].Length * 0.5;

end;

procedure TBrick_T4V1.SetSourceOnFace(FIndex: Integer; e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnFace(FIndex, sigma * e * teta, Tinf);

end;

procedure TBrick_T4V1.SetSourceOnFace(FIndex: Integer; vf: Double);
var

  e : ELibException;

  j : Integer;

  n : Array[0..2] of Integer;

begin

  if (FIndex < 0) or (FIndex > fNbFaces-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  Fb[n[0],0] := Fb[n[0],0] + vf * FFaces[FIndex].Area / 3;
  Fb[n[1],0] := Fb[n[1],0] + vf * FFaces[FIndex].Area / 3;
  Fb[n[2],0] := Fb[n[2],0] + vf * FFaces[FIndex].Area / 3;

end;

procedure TBrick_T4V1.SetSourceOnFace(FIndex: Integer; h, Tinf: Double);
var

  e : ELibException;

  Kh : TVMobj;

  j : Integer;

  n : Array[0..2] of Integer;

begin

  if (FIndex < 0) or (FIndex > fNbFaces - 1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  Fb[n[0],0] := Fb[n[0],0] + h * Tinf * FFaces[FIndex].Area / 3;
  Fb[n[1],0] := Fb[n[1],0] + h * Tinf * FFaces[FIndex].Area / 3;
  Fb[n[2],0] := Fb[n[2],0] + h * Tinf * FFaces[FIndex].Area / 3;

  Kh := TVMobj.Create(FNbNodes,FNbNodes);

  Kh[n[0], n[0]] := h * FFaces[FIndex].Area / 6;
  Kh[n[0], n[1]] := h * FFaces[FIndex].Area / 12;
  Kh[n[0], n[2]] := h * FFaces[FIndex].Area / 12;

  Kh[n[1], n[0]] := h * FFaces[FIndex].Area / 12;
  Kh[n[1], n[1]] := h * FFaces[FIndex].Area / 6;
  Kh[n[1], n[2]] := h * FFaces[FIndex].Area / 12;

  Kh[n[2], n[0]] := h * FFaces[FIndex].Area / 12;
  Kh[n[2], n[1]] := h * FFaces[FIndex].Area / 12;
  Kh[n[2], n[2]] := h * FFaces[FIndex].Area / 6;

  FK := FK + Kh;

end;

procedure TBrick_T4V1.SetSourceOnNode(NIndex: Integer; vn: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[NIndex,0] := Fb[NIndex,0] + vn;

end;

procedure TBrick_T4V1.SetTransientTerm;
begin

  FM[0, 0] := 0.10;
  FM[0, 1] := 0.05;
  FM[0, 2] := 0.05;
  FM[0, 3] := 0.05;

  FM[1, 0] := 0.05;
  FM[1, 1] := 0.10;
  FM[1, 2] := 0.05;
  FM[1, 3] := 0.05;

  FM[2, 0] := 0.05;
  FM[2, 1] := 0.05;
  FM[2, 2] := 0.10;
  FM[2, 3] := 0.05;

  FM[3, 0] := 0.05;
  FM[3, 1] := 0.05;
  FM[3, 2] := 0.05;
  FM[3, 3] := 0.10;

  FM := FM * (FVolume * FSpecificHeat * FDensity);

  if FTimeInterval > 0 then
    FM := FM * (1 / FTimeInterval);

end;

end.
