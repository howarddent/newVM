unit CXS.FEMLAP.Face_Q4V2;

// Quadrangle face element with 4 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element,
  CXS.FEMLAP.Element_Face,
  CXS.FEMLAP.Edge_B2V1;

(*
   Quad element.

                 eta
                 |
      3 *--------|--------* 2
        |        |        |
        |        |        |
        |        |        |
        |        |--------------> xi
        |                 |
        |                 |
        |                 |
      0 *-----------------* 1

*)

type TFace_Q4V2 = class(TElement_Face)

  private

    x1, y1: Double;
    x2, y2: Double;
    x3, y3: Double;
    x4, y4: Double;

    x21, x32, x43, x14 : Double;
    y21, y32, y43, y14 : Double;

    x13 : Double;
    y13 : Double;

    wxi, weta, xi, eta : Array of Double;

    // Auxiliary matrices for stress-strain calculations
    FD : TVMobj;

    // Thermal load
    Fepsilon0 : TVMobj;

    FIntegPoints : Integer;
    procedure SetGaussPoints;

    procedure SetTransientTerm;
    procedure SetDiffusionTerm;

    procedure GetStiffnessMatrices(xi, eta: Double; var B : TVMobj; var DetJ : Double);

  public

    constructor Create; override;
    destructor Destroy; override;

    procedure CalcGeoProperties; override;
    procedure Calc; override;

    procedure ReCalcD; override;

    procedure GetStiffnessDB(xi, eta: Double; var D, B : TVMobj);

    (*
    Description:
      Set source on node.
    Parameters:
      NIndex - [in] node id (0 - 3).
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

{ TFace_Q4V1 }

procedure TFace_Q4V2.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Integrate
  Integrate;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if FTransient then SetTransientTerm;

end;

procedure TFace_Q4V2.CalcGeoProperties;
var

  i, j : Integer;

  gc1, gc2, gc3, gc4 : TVMobj;
  lc1, lc2, lc3, lc4 : TVMobj;

begin

  gc1 := TVMobj.Create(3,1);
  gc2 := TVMobj.Create(3,1);
  gc3 := TVMobj.Create(3,1);
  gc4 := TVMobj.Create(3,1);

  lc1 := TVMobj.Create(3,1);
  lc2 := TVMobj.Create(3,1);
  lc3 := TVMobj.Create(3,1);
  lc4 := TVMobj.Create(3,1);

  gc1[0,0] := FNodes[0].x;
  gc1[1,0] := FNodes[0].y;
  gc1[2,0] := FNodes[0].z;

  gc2[0,0] := FNodes[1].x;
  gc2[1,0] := FNodes[1].y;
  gc2[2,0] := FNodes[1].z;

  gc3[0,0] := FNodes[2].x;
  gc3[1,0] := FNodes[2].y;
  gc3[2,0] := FNodes[2].z;

  gc4[0,0] := FNodes[3].x;
  gc4[1,0] := FNodes[3].y;
  gc4[2,0] := FNodes[3].z;

  if (Abs(gc1[2,0]) < 1E-30) and (Abs(gc2[2,0]) < 1E-30) and (Abs(gc3[2,0]) < 1E-30) then
  begin
    lc1 := CopyObj(gc1);
    lc2 := CopyObj(gc2);
    lc3 := CopyObj(gc3);
    lc4 := CopyObj(gc4);
  end
  else
    GlobalToLocal(gc1, gc2, gc3, gc4, lc1, lc2, lc3, lc4);

  x1 := lc1[0,0];
  y1 := lc1[1,0];

  x2 := lc2[0,0];
  y2 := lc2[1,0];

  x3 := lc3[0,0];
  y3 := lc3[1,0];

  x4 := lc4[0,0];
  y4 := lc4[1,0];

  // Create edges
  FEdges[0].NodeId[0] := 0;
  FEdges[0].NodeId[1] := 1;

  FEdges[1].NodeId[0] := 1;
  FEdges[1].NodeId[1] := 2;

  FEdges[2].NodeId[0] := 2;
  FEdges[2].NodeId[1] := 3;

  FEdges[3].NodeId[0] := 3;
  FEdges[3].NodeId[1] := 0;

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
  x43 := x4 - x3;
  x14 := x1 - x4;

  y21 := y2 - y1;
  y32 := y3 - y2;
  y43 := y4 - y3;
  y14 := y1 - y4;

  x13 := x1 - x3;
  y13 := y1 - y3;

  FArea := 0.5 * Abs(-x13 * y32 + x32 * y13 - x14 * y43 + x43 * y14);

end;

constructor TFace_Q4V2.Create;
var

  i : Integer;

begin

  inherited;

  FNbNodes := 4;
  FNbEdges := 4;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);
  SetLength(FEdges, FNbEdges);

  for i := 0 to FNbEdges - 1 do
    FEdges[i] := TEdge_B2V1.Create;

  FIntegPoints := 4;
  SetGaussPoints;

  Thickness := 1;

  Fb := TVMobj.Create(FNbNodes*2, 1);

  FM := TVMobj.Create(FNbNodes*2, FNbNodes*2);
  FK := TVMobj.Create(FNbNodes*2, FNbNodes*2);

  FJ := TVMobj.Create(FNbNodes, FNbNodes);

  Fepsilon0 := TVMobj.Create(3,1);

end;

destructor TFace_Q4V2.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  inherited;

end;

procedure TFace_Q4V2.GetStiffnessDB(xi, eta: Double; var D, B : TVMobj);
var

  DetJ : Double;

begin

  GetStiffnessMatrices(xi, eta, B, DetJ);

  D := CopyObj(FD);

end;

procedure TFace_Q4V2.GetStiffnessMatrices(xi, eta: Double; var B: TVMobj; var DetJ: Double);
var

  xim, xip : Double;
  etam, etap : Double;

  Jacobian, G, A : TVMobj;

begin

  xim := (1 - xi);
  xip := (1 + xi);
  etam := (1 - eta);
  etap := (1 + eta);

  Jacobian := TVMobj.Create(2,2);

  Jacobian[0, 0] := -xim*x1+xim*x2+xip*x3-xip*x4;
  Jacobian[0, 1] := -xim*y1+xim*y2+xip*y3-xip*y4;

  Jacobian[1, 0] := -etam*x1-etap*x2+etap*x3+etam*x4;
  Jacobian[1, 1] := -etam*y1-etap*y2+etap*y3+etam*y4;

  Jacobian := Jacobian * 0.25;

  DetJ := Det(Jacobian);

  A := TVMobj.Create(3, 4);

  A[0, 0] := +Jacobian[1,1];
  A[0, 1] := -Jacobian[0,1];
  A[0, 2] := 0;
  A[0, 3] := 0;

  A[1, 0] := 0;
  A[1, 1] := 0;
  A[1, 2] := -Jacobian[1,0];
  A[1, 3] := +Jacobian[0,0];

  A[2, 0] := -Jacobian[1,0];
  A[2, 1] := +Jacobian[0,0];
  A[2, 2] := +Jacobian[1,1];
  A[2, 3] := -Jacobian[0,1];

  A := A * (1/DetJ);

  G := TVMobj.Create(4,8);

  G[0, 0] := -xim;
  G[0, 1] := 0;
  G[0, 2] := +xim;
  G[0, 3] := 0;
  G[0, 4] := +xip;
  G[0, 5] := 0;
  G[0, 6] := -xip;
  G[0, 7] := 0;

  G[1, 0] := -etam;
  G[1, 1] := 0;
  G[1, 2] := -etap;
  G[1, 3] := 0;
  G[1, 4] := +etap;
  G[1, 5] := 0;
  G[1, 6] := +etam;
  G[1, 7] := 0;

  G[2, 0] := 0;
  G[2, 1] := -xim;
  G[2, 2] := 0;
  G[2, 3] := +xim;
  G[2, 4] := 0;
  G[2, 5] := +xip;
  G[2, 6] := 0;
  G[2, 7] := -xip;

  G[3, 0] := 0;
  G[3, 1] := -etam;
  G[3, 2] := 0;
  G[3, 3] := -etap;
  G[3, 4] := 0;
  G[3, 5] := +etap;
  G[3, 6] := 0;
  G[3, 7] := +etam;

  G := G * 0.25;

  B := MatMult(A, G);

end;

procedure TFace_Q4V2.Integrate;
var

  i, j : Integer;

  p : Integer;

  xim, xip : Double;
  etam, etap : Double;

  Jacobian : TVMobj;

  DetJ : Double;

  N : Array[0..4] of Double;

  Ji : TVMobj;

begin

  FJ := TVMobj.Create(FJ.Rows, FJ.Cols);

  for p := 0 to FIntegPoints - 1 do
  begin

    xim := (1 - xi[p]);
    xip := (1 + xi[p]);
    etam := (1 - eta[p]);
    etap := (1 + eta[p]);

    Jacobian := TVMobj.Create(2,2);

    Jacobian[0, 0] := -xim*x1+xim*x2+xip*x3-xip*x4;
    Jacobian[0, 1] := -xim*y1+xim*y2+xip*y3-xip*y4;

    Jacobian[1, 0] := -etam*x1-etap*x2+etap*x3+etam*x4;
    Jacobian[1, 1] := -etam*y1-etap*y2+etap*y3+etam*y4;

    Jacobian := Jacobian * 0.25;

    DetJ := Abs(Det(Jacobian));

    Ji := TVMobj.Create(FNbNodes, FNbNodes);

    N[0] := 0.25*(1-xi[p])*(1-eta[p]);
    N[1] := 0.25*(1+xi[p])*(1-eta[p]);
    N[2] := 0.25*(1+xi[p])*(1+eta[p]);
    N[3] := 0.25*(1-xi[p])*(1+eta[p]);

    for i := 0 to FNbNodes-1 do
    begin

      for j := 0 to FNbNodes-1 do
      begin

        Ji[i, j] := N[i]*N[j];

      end;

    end;

    Ji := Ji * (wxi[p] * weta[p] * DetJ);

    FJ := FJ + Ji;

  end;

end;

procedure TFace_Q4V2.ReCalcD;
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

procedure TFace_Q4V2.SetDiffusionTerm;
var

  p : Integer;

  DetJ : Double;

  DB : TVMobj;
  B, BT : TVMobj;

  Ki : TVMobj;

  qTh : TVMobj;

begin

  FK := TVMobj.Create(FK.Rows, FK.Cols);

  for p := 0 to FIntegPoints - 1 do
  begin

    GetStiffnessMatrices(xi[p], eta[p], B, DetJ);

    DB := MatMult(FD, B);

    BT := B.Transpose;

    Ki := MatMult(BT, DB);

    Ki := Ki * (wxi[p] * weta[p] * DetJ);

    FK := FK + Ki;

  end;

  FK := FK * (FThickness * FConductivity);

  // Add thermal load
  GetStiffnessMatrices(0, 0, B, DetJ);

  BT := B.Transpose;

  qTh := MatMult(FD, Fepsilon0);

  qTh := MatMult(BT, qTh);

  qTh := qTh * (FArea * FThickness);

  Fb := Fb + qTh;

end;

procedure TFace_Q4V2.SetGaussPoints;
var

  p : Integer;

begin

  SetLength(wxi, FIntegPoints);
  SetLength(weta, FIntegPoints);
  SetLength(xi, FIntegPoints);
  SetLength(eta, FIntegPoints);

  for p := 0 to FIntegPoints - 1 do
  begin

    // One integration point
    if FIntegPoints = 1 then
    begin
      wxi[p] := 2;
      weta[p] := 2;

      xi[p] := 0;
      eta[p] := 0;
    end;

    // Two integration points
    if FIntegPoints = 4 then
    begin
      wxi[p] := 1;
      weta[p] := 1;

      case p of
      0: begin xi[p] := -0.5773502692; eta[p] := -0.5773502692; end;
      1: begin xi[p] := +0.5773502692; eta[p] := -0.5773502692; end;
      2: begin xi[p] := -0.5773502692; eta[p] := +0.5773502692; end;
      3: begin xi[p] := +0.5773502692; eta[p] := +0.5773502692; end;
      end;
    end;

    // Three integration points
    if FIntegPoints = 9 then
    begin
      wxi[p] := 1;
      weta[p] := 1;

      case p of
      0: begin xi[p] := -0.7745966692; eta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; end;
      1: begin xi[p] := +0.7745966692; eta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; end;
      2: begin xi[p] := -0.7745966692; eta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; end;
      3: begin xi[p] := +0.7745966692; eta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; end;
      4: begin xi[p] := -0.7745966692; eta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; end;
      5: begin xi[p] := +0.7745966692; eta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; end;
      6: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; end;
      7: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; end;
      8: begin xi[p] := +0.0000000000; eta[p] := +0.0000000000; wxi[p] := 0.8888888889; weta[p] := 0.8888888889; end;
      end;
    end;

  end;


end;

procedure TFace_Q4V2.SetTemperatureLoad(dT: Double);
begin

  Fepsilon0[0,0] := FThermalExpansion * dT;
  Fepsilon0[1,0] := FThermalExpansion * dT;
  Fepsilon0[2,0] := 0;

end;

procedure TFace_Q4V2.SetSourceOnNode(NIndex: Integer; vn: Double; DimId : Integer);
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

  Fb[2*NIndex + DimId,0] := Fb[2*NIndex + DimId,0] + vn;

end;

procedure TFace_Q4V2.SetTransientTerm;
begin

end;

end.
