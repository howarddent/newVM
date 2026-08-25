unit CXS.FEMLAP.Face_T3V1;

// Triangle face element with 3 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node, CXS.FEMLAP.Element_Face, CXS.FEMLAP.Edge_B2V1;

(*
   Triangle element.

          eta

          |
          *2
          | \
          |   \
          |     \
          |       \ 1
          *0-------*-----> xi

*)

type TFace_T3V1 = class(TElement_Face)

  private

    x1, y1: Double;
    x2, y2: Double;
    x3, y3: Double;

    x21, x32, x13 : Double;
    y21, y32, y13 : Double;

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
      NIndex - [in] node id (0 - 2).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn : Double); overload;

    (*
    Description:
      Set source at center of edge.
    Parameters:
      EIndex - [in] node id (0 - 2).
      ve - [in] value at edge.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; ve : Double); overload;

    (*
    Description:
      Set source on edge - convection.
    Parameters:
      EIndex - [in] node id (0 - 2).
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; h, Tinf: Double); overload;

    (*
    Description:
      Set source on edge - radiation.
    Parameters:
      EIndex - [in] node id (0 - 2).
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; e, teta, Tinf: Double); overload;

    (*
    Description:
      Set source at center of face.
    Parameters:
      vf - [in] value at face.
    *)
    procedure SetSourceOnFace(vf : Double); overload;

    (*
    Description:
      Set source on face - convection.
    Parameters:
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(h, Tinf: Double); overload;

    (*
    Description:
      Set source on face - radiation.
    Parameters:
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(e, teta, Tinf: Double); overload;

    procedure Integrate; override;

end;

implementation

{ TTFace_T3V1 }

procedure TFace_T3V1.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if FTransient then SetTransientTerm;

end;

procedure TFace_T3V1.CalcGeoProperties;
var

  i, j : Integer;

  gc1, gc2, gc3 : TVMobj;
  lc1, lc2, lc3 : TVMobj;

begin

  gc1 := TVMobj.Create(3,1);
  gc2 := TVMobj.Create(3,1);
  gc3 := TVMobj.Create(3,1);

  lc1 := TVMobj.Create(3,1);
  lc2 := TVMobj.Create(3,1);
  lc3 := TVMobj.Create(3,1);

  gc1[0,0] := FNodes[0].x;
  gc1[1,0] := FNodes[0].y;
  gc1[2,0] := FNodes[0].z;

  gc2[0,0] := FNodes[1].x;
  gc2[1,0] := FNodes[1].y;
  gc2[2,0] := FNodes[1].z;

  gc3[0,0] := FNodes[2].x;
  gc3[1,0] := FNodes[2].y;
  gc3[2,0] := FNodes[2].z;

  if (Abs(gc1[2,0]) < 1E-30) and (Abs(gc2[2,0]) < 1E-30) and (Abs(gc3[2,0]) < 1E-30) then
  begin
    lc1 := CopyObj(gc1);
    lc2 := CopyObj(gc2);
    lc3 := CopyObj(gc3);
  end
  else
    GlobalToLocal(gc1, gc2, gc3, lc1, lc2, lc3);

  x1 := lc1[0,0];
  y1 := lc1[1,0];

  x2 := lc2[0,0];
  y2 := lc2[1,0];

  x3 := lc3[0,0];
  y3 := lc3[1,0];

  // Create edges

  FEdges[0].NodeId[0] := 0;
  FEdges[0].NodeId[1] := 1;

  FEdges[1].NodeId[0] := 1;
  FEdges[1].NodeId[1] := 2;

  FEdges[2].NodeId[0] := 2;
  FEdges[2].NodeId[1] := 0;

  for i := 0 to FNbEdges - 1 do
  begin
    for j := 0 to FEdges[i].NbNodes - 1 do
    begin
      FEdges[i].Node[j] := FNodes[FEdges[i].NodeId[j]];
    end;

    FEdges[i].CalcGeoProperties;
    FEdges[i].Integrate;

  end;

  x21 := x2 - x1;
  x32 := x3 - x2;
  x13 := x1 - x3;

  y21 := y2 - y1;
  y32 := y3 - y2;
  y13 := y1 - y3;

  FArea := 0.5 * Abs(-x13 * y32 + x32 * y13);

end;

constructor TFace_T3V1.Create;
var

  i : Integer;

begin

  inherited;

  FNbNodes := 3;
  FNbEdges := 3;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);
  SetLength(FEdges, FNbEdges);

  for i := 0 to FNbEdges - 1 do
    FEdges[i] := TEdge_B2V1.Create;

  Fb := TVMobj.Create(FNbNodes, 1);

  FM := TVMobj.Create(FNbNodes, FNbNodes);
  FK := TVMobj.Create(FNbNodes, FNbNodes);

  FThickness := 1;

end;

destructor TFace_T3V1.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  inherited;
end;

procedure TFace_T3V1.Integrate;
begin
  inherited;

end;

procedure TFace_T3V1.ReCalcD;
begin
  inherited;

end;

// Convection
procedure TFace_T3V1.SetSourceOnEdge(EIndex: Integer; h, Tinf: Double);
var

  j : Integer;

  n : Array [0..1] of Integer;

  Kh : TVMobj;

  e : ELibException;

begin

  if (EIndex < 0) or (EIndex > FNbEdges-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to 1 do
    n[j] := FEdges[EIndex].NodeId[j];

  Fb[n[0],0] := Fb[n[0],0] + h * Tinf * FEdges[EIndex].Length * FThickness * 0.5;
  Fb[n[1],0] := Fb[n[1],0] + h * Tinf * FEdges[EIndex].Length * FThickness * 0.5;

  Kh := TVMobj.Create(FNbNodes,FNbNodes);

  Kh[n[0], n[0]] := h * FEdges[EIndex].Length * FThickness / 3;
  Kh[n[0], n[1]] := h * FEdges[EIndex].Length * FThickness / 6;

  Kh[n[1], n[0]] := h * FEdges[EIndex].Length * FThickness / 6;
  Kh[n[1], n[1]] := h * FEdges[EIndex].Length * FThickness / 3;

  FK := FK + Kh;

end;

procedure TFace_T3V1.SetSourceOnEdge(EIndex: Integer; e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnEdge(EIndex, sigma * e * teta, Tinf);

end;

procedure TFace_T3V1.SetSourceOnFace(e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnFace(sigma * e * teta, Tinf);

end;

procedure TFace_T3V1.SetSourceOnFace(h, Tinf: Double);
var

  Kh : TVMobj;

begin

  Fb := AddScalar(Fb, h * Tinf * FArea / 3);

  Kh := TVMobj.Create(FNbNodes,FNbNodes);

  Kh[0, 0] := h * FArea / 6;
  Kh[0, 1] := h * FArea / 12;
  Kh[0, 2] := h * FArea / 12;

  Kh[1, 0] := h * FArea / 12;
  Kh[1, 1] := h * FArea / 6;
  Kh[1, 2] := h * FArea / 12;

  Kh[2, 0] := h * FArea / 12;
  Kh[2, 1] := h * FArea / 12;
  Kh[2, 2] := h * FArea / 6;

  FK := FK + Kh;

end;

procedure TFace_T3V1.SetSourceOnEdge(EIndex: Integer; ve: Double);
var

  e : ELibException;

  j : Integer;

  n : Array[0..1] of Integer;

begin

  if (EIndex < 0) or (EIndex > FNbEdges - 1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to 1 do
    n[j] := FEdges[EIndex].NodeId[j];

  Fb[n[0],0] := Fb[n[0],0] + ve * FEdges[EIndex].Length * 0.5;
  Fb[n[1],0] := Fb[n[1],0] + ve * FEdges[EIndex].Length * 0.5;

end;

procedure TFace_T3V1.SetSourceOnFace(vf : Double);
begin

  Fb := AddScalar(Fb, vf * FArea / 3);

end;

procedure TFace_T3V1.SetSourceOnNode(NIndex: Integer; vn: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes - 1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[NIndex,0] := Fb[NIndex,0] + vn;

end;

procedure TFace_T3V1.SetDiffusionTerm;
var

  B, BT : TVMobj;

begin

  B := TVMobj.Create(2,3);

  B[0, 0] := -y32;
  B[0, 1] := -y13;
  B[0, 2] := -y21;
  B[1, 0] := +x32;
  B[1, 1] := +x13;
  B[1, 2] := +x21;

  if FArea > 0 then
    B := B * (1/(2 * FArea));

  BT := B.Transpose;

  FK := MatMult(BT, B);

  FK := FK * (FArea * FThickness * FConductivity);

end;

procedure TFace_T3V1.SetTransientTerm;
begin

  FM[0, 0] := 1/6;
  FM[0, 1] := 1/12;
  FM[0, 2] := 1/12;

  FM[1, 0] := 1/12;
  FM[1, 1] := 1/6;
  FM[1, 2] := 1/12;

  FM[2, 0] := 1/12;
  FM[2, 1] := 1/12;
  FM[2, 2] := 1/6;

  FM := FM * (FThickness * FArea * FSpecificHeat * FDensity);

  if FTimeInterval > 0 then
    FM := FM * (1 / FTimeInterval);

end;

end.
