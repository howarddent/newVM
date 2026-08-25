unit CXS.FEMLAP.Face_T3V2;

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

type TFace_T3V2 = class(TElement_Face)

  private

    x1, y1: Double;
    x2, y2: Double;
    x3, y3: Double;

    x21, x32, x13 : Double;
    y21, y32, y13 : Double;

    // Auxiliary matrices for stress-strain calculations
    FD : TVMobj;

    // Thermal load
    Fepsilon0 : TVMobj;

    procedure SetTransientTerm;
    procedure SetDiffusionTerm;

    procedure GetStiffnessMatrices(var B : TVMobj);

  public

    constructor Create; override;
    destructor Destroy; override;

    procedure CalcGeoProperties; override;
    procedure Calc; override;

    procedure ReCalcD; override;

    procedure GetStiffnessDB(var D, B : TVMobj);

    (*
    Description:
      Set source on node.
    Parameters:
      NIndex - [in] node id (0 - 2).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn : Double; DimId : Integer); overload;

    (*
    Description:
      Set temperature load dT on node.
    Parameters:
      dT - [in] value at node.
    *)
    procedure SetTemperatureLoad(dT : Double); overload;

    procedure Integrate; override;

end;

implementation

{ TTFace_T3V1 }

procedure TFace_T3V2.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if FTransient then SetTransientTerm;

end;

procedure TFace_T3V2.CalcGeoProperties;
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

constructor TFace_T3V2.Create;
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

  Fb := TVMobj.Create(FNbNodes*2, 1);

  FM := TVMobj.Create(FNbNodes*2, FNbNodes*2);
  FK := TVMobj.Create(FNbNodes*2, FNbNodes*2);

  FThickness := 1;

  Fepsilon0 := TVMobj.Create(3, 1);

end;

destructor TFace_T3V2.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  inherited;
end;

procedure TFace_T3V2.GetStiffnessDB(var D, B: TVMobj);
begin

  GetStiffnessMatrices(B);

  D := CopyObj(FD);

end;

procedure TFace_T3V2.GetStiffnessMatrices(var B : TVMobj);
begin

  B := TVMobj.Create(3,6);

  B[0, 0] := -y32;
  B[0, 1] := 0;
  B[0, 2] := -y13;
  B[0, 3] := 0;
  B[0, 4] := -y21;
  B[0, 5] := 0;

  B[1, 0] := 0;
  B[1, 1] := +x32;
  B[1, 2] := 0;
  B[1, 3] := +x13;
  B[1, 4] := 0;
  B[1, 5] := +x21;

  B[2, 0] := +x32;
  B[2, 1] := -y32;
  B[2, 2] := +x13;
  B[2, 3] := -y13;
  B[2, 4] := +x21;
  B[2, 5] := -y21;

  if FArea > 0 then
    B := B * (1/(2 * FArea));

end;

procedure TFace_T3V2.Integrate;
begin
  inherited;

end;

procedure TFace_T3V2.ReCalcD;
begin

  FD := TVMobj.Create(3,3);

  FD[0, 0] := 1;
  FD[0, 1] := FPoisson;
  FD[0, 2] := 0;

  FD[1, 0] := FPoisson;
  FD[1, 1] := 1;
  FD[1, 2] := 0;

  FD[2, 0] := 0;
  FD[2, 1] := 0;
  FD[2, 2] := (1 - FPoisson)*0.5;

  FD := FD * (FElasticModulus / (1 - FPoisson * FPoisson));

end;

procedure TFace_T3V2.SetDiffusionTerm;
var

  B, BT : TVMobj;

  DB : TVMobj;

  qTh : TVMobj;

begin

  GetStiffnessMatrices(B);

  DB := MatMult(FD, B);

  BT := B.Transpose;

  FK := MatMult(BT, DB);

  FK := FK * (FArea * FThickness * FConductivity);

  // Add thermal load

  qTh := MatMult(FD, Fepsilon0);

  qTh := MatMult(BT, qTh);

  qTh := qTh * (FArea * FThickness);

  Fb := Fb + qTh;

end;

procedure TFace_T3V2.SetTemperatureLoad(dT: Double);
begin

  Fepsilon0[0,0] := FThermalExpansion * dT;
  Fepsilon0[1,0] := FThermalExpansion * dT;
  Fepsilon0[2,0] := 0;

end;

procedure TFace_T3V2.SetSourceOnNode(NIndex: Integer; vn: Double; DimId: Integer);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  if (DimId <> 0) and (DimId <> 1) then
  begin

    e := ELibException.Create('Error: Dimension out of bounds [0 - 1].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[2*NIndex + DimId, 0] := Fb[2*NIndex + DimId, 0] + vn;

end;

procedure TFace_T3V2.SetTransientTerm;
begin

end;

end.
