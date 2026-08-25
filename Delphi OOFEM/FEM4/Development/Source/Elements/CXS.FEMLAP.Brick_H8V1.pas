unit CXS.FEMLAP.Brick_H8V1;

// Hexa brick element with 8 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions, CXS.FEMLAP.Node, CXS.FEMLAP.Element_Brick, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Brick_T4V1;


(*
   Hexahedral element.

                zeta
                |
       4 *------|-----------* 5
        /|      |          /|
      /  |      |        /  |
  7 /    |      |     6/    |
   *------------|-----*     |
   |     |      |     |     |
   |     |      |----------------> xi
   |     |     /      |     |
   |   0 *----/-------|-----* 1
   |    /    /        |     /
   |  /    eta        |   /
   |/                 | /
   *------------------*
  3                   2

*)

type TBrick_H8V1 = class(TElement_Brick)

  private

    x1, y1, z1: Double;
    x2, y2, z2: Double;
    x3, y3, z3: Double;
    x4, y4, z4: Double;
    x5, y5, z5: Double;
    x6, y6, z6: Double;
    x7, y7, z7: Double;
    x8, y8, z8: Double;

    wxi, weta, wzeta, xi, eta, zeta : Array of Double;

    FIntegPoints : Integer;
    procedure SetGaussPoints;

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
      NIndex - [in] node id (0 - 7).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn : Double); overload;

    (*
    Description:
      Set source at center of edge.
    Parameters:
      EIndex - [in] node id (0 - 11).
      ve - [in] value at edge.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; ve : Double); overload;

    (*
    Description:
      Set source at center of face.
    Parameters:
      FIndex - [in] node id (0 - 5).
      vf - [in] value at face.
    *)
    procedure SetSourceOnFace(FIndex: Integer; vf : Double); overload;

    (*
    Description:
      Set source on face - convection.
    Parameters:
      FIndex - [in] node id (0 - 5).
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(FIndex: Integer; h, Tinf: Double); overload;

    (*
    Description:
      Set source on face - radiation.
    Parameters:
      FIndex - [in] node id (0 - 5).
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

{ TBrick_H8V1 }

procedure TBrick_H8V1.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if fTransient then SetTransientTerm;

end;

procedure TBrick_H8V1.CalcGeoProperties;
var

  i, j : Integer;

  Brick_T4V1 : TBrick_T4V1;

begin

  x1 := FNodes[0].x;
  y1 := FNodes[0].y;
  z1 := FNodes[0].z;

  x2 := FNodes[1].x;
  y2 := FNodes[1].y;
  z2 := FNodes[1].z;

  x3 := FNodes[2].x;
  y3 := FNodes[2].y;
  z3 := FNodes[2].z;

  x4 := FNodes[3].x;
  y4 := FNodes[3].y;
  z4 := FNodes[3].z;

  x5 := FNodes[4].x;
  y5 := FNodes[4].y;
  z5 := FNodes[4].z;

  x6 := FNodes[5].x;
  y6 := FNodes[5].y;
  z6 := FNodes[5].z;

  x7 := FNodes[6].x;
  y7 := FNodes[6].y;
  z7 := FNodes[6].z;

  x8 := FNodes[7].x;
  y8 := FNodes[7].y;
  z8 := FNodes[7].z;

  // Create edges
  FEdges[0].NodeId[0] := 0;
  FEdges[0].NodeId[1] := 1;

  FEdges[1].NodeId[0] := 1;
  FEdges[1].NodeId[1] := 2;

  FEdges[2].NodeId[0] := 2;
  FEdges[2].NodeId[1] := 3;

  FEdges[3].NodeId[0] := 3;
  FEdges[3].NodeId[1] := 0;

  FEdges[4].NodeId[0] := 4;
  FEdges[4].NodeId[1] := 5;

  FEdges[5].NodeId[0] := 5;
  FEdges[5].NodeId[1] := 6;

  FEdges[6].NodeId[0] := 6;
  FEdges[6].NodeId[1] := 7;

  FEdges[7].NodeId[0] := 7;
  FEdges[7].NodeId[1] := 4;

  FEdges[8].NodeId[0] := 0;
  FEdges[8].NodeId[1] := 4;

  FEdges[9].NodeId[0] := 1;
  FEdges[9].NodeId[1] := 5;

  FEdges[10].NodeId[0] := 2;
  FEdges[10].NodeId[1] := 6;

  FEdges[11].NodeId[0] := 3;
  FEdges[11].NodeId[1] := 7;

  for i := 0 to FNbEdges - 1 do
  begin
    for j := 0 to FEdges[i].NbNodes - 1 do
    begin
      FEdges[i].Node[j] := FNodes[FEdges[i].NodeId[j]];
    end;

    FEdges[i].CalcGeoProperties;
    FEdges[i].Integrate;

  end;

  // create faces
  FFaces[0].NodeId[0] := 0;
  FFaces[0].NodeId[1] := 1;
  FFaces[0].NodeId[2] := 2;
  FFaces[0].NodeId[3] := 3;

  FFaces[1].NodeId[0] := 4;
  FFaces[1].NodeId[1] := 5;
  FFaces[1].NodeId[2] := 6;
  FFaces[1].NodeId[3] := 7;

  FFaces[2].NodeId[0] := 0;
  FFaces[2].NodeId[1] := 1;
  FFaces[2].NodeId[2] := 5;
  FFaces[2].NodeId[3] := 4;

  FFaces[3].NodeId[0] := 1;
  FFaces[3].NodeId[1] := 2;
  FFaces[3].NodeId[2] := 6;
  FFaces[3].NodeId[3] := 5;

  FFaces[4].NodeId[0] := 2;
  FFaces[4].NodeId[1] := 3;
  FFaces[4].NodeId[2] := 7;
  FFaces[4].NodeId[3] := 6;

  FFaces[5].NodeId[0] := 3;
  FFaces[5].NodeId[1] := 0;
  FFaces[5].NodeId[2] := 4;
  FFaces[5].NodeId[3] := 7;

  for i := 0 to FNbFaces - 1 do
  begin
    for j := 0 to FFaces[i].NbNodes - 1 do
    begin
      FFaces[i].Node[j] := FNodes[FFaces[i].NodeId[j]];
    end;

    FFaces[i].CalcGeoProperties;
    FFaces[i].Integrate;

  end;

  Brick_T4V1 := TBrick_T4V1.Create;

  FVolume := 0;

  // Tetra 1
  Brick_T4V1.Node[0] := Self.Node[0];
  Brick_T4V1.Node[1] := Self.Node[1];
  Brick_T4V1.Node[2] := Self.Node[2];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 2
  Brick_T4V1.Node[0] := Self.Node[0];
  Brick_T4V1.Node[1] := Self.Node[4];
  Brick_T4V1.Node[2] := Self.Node[1];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 3
  Brick_T4V1.Node[0] := Self.Node[1];
  Brick_T4V1.Node[1] := Self.Node[4];
  Brick_T4V1.Node[2] := Self.Node[5];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 4
  Brick_T4V1.Node[0] := Self.Node[1];
  Brick_T4V1.Node[1] := Self.Node[2];
  Brick_T4V1.Node[2] := Self.Node[3];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 5
  Brick_T4V1.Node[0] := Self.Node[1];
  Brick_T4V1.Node[1] := Self.Node[6];
  Brick_T4V1.Node[2] := Self.Node[2];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 6
  Brick_T4V1.Node[0] := Self.Node[1];
  Brick_T4V1.Node[1] := Self.Node[5];
  Brick_T4V1.Node[2] := Self.Node[6];
  Brick_T4V1.Node[3] := Self.Node[7];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  Brick_T4V1.Free;

end;

constructor TBrick_H8V1.Create;
var

  i : Integer;

begin

  inherited;

  FNbNodes := 8;
  FNbEdges := 12;
  FNbFaces := 6;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);
  SetLength(FEdges, FNbEdges);
  SetLength(FFaces, FNbFaces);

  for i := 0 to FNbEdges - 1 do
    FEdges[i] := TEdge_B2V1.Create;

  for i := 0 to FNbFaces - 1 do
    FFaces[i] := TFace_Q4V1.Create;

  FIntegPoints := 8;
  SetGaussPoints;

  Fb := TVMobj.Create(FNbNodes, 1);

  FM := TVMobj.Create(FNbNodes, FNbNodes);
  FK := TVMobj.Create(FNbNodes, FNbNodes);

end;

destructor TBrick_H8V1.Destroy;
var
  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  for i := 0 to FNbFaces - 1 do
    FFaces[i].Free;

  inherited;
end;

procedure TBrick_H8V1.Integrate;
begin
  inherited;

end;

procedure TBrick_H8V1.ReCalcD;
begin
  inherited;

end;

procedure TBrick_H8V1.SetDiffusionTerm;
var

  p : Integer;

  xim, xip : Double;
  etam, etap : Double;
  zetam, zetap : Double;

  Jacobian : TVMobj;
  A, G : TVMobj;

  DetJ : Double;

  B, BT : TVMobj;

  Ki : TVMobj;

begin

  FK := TVMobj.Create(FK.Rows, FK.Cols);

  for p := 0 to FIntegPoints - 1 do
  begin

    xim := (1 - xi[p]);
    xip := (1 + xi[p]);

    etam := (1 - eta[p]);
    etap := (1 + eta[p]);

    zetam := (1 - zeta[p]);
    zetap := (1 + zeta[p]);

    Jacobian := TVMobj.Create(3,3);

    Jacobian[0, 0] := -etam*zetam*x1+etam*zetam*x2-etap*zetam*x3+etap*zetam*x4-etam*zetap*x5+etam*zetap*x6-etap*zetap*x7+etap*zetap*x8;
    Jacobian[0, 1] := -etam*zetam*y1+etam*zetam*y2-etap*zetam*y3+etap*zetam*y4-etam*zetap*y5+etam*zetap*y6-etap*zetap*y7+etap*zetap*y8;
    Jacobian[0, 2] := -etam*zetam*z1+etam*zetam*z2-etap*zetam*z3+etap*zetam*z4-etam*zetap*z5+etam*zetap*z6-etap*zetap*z7+etap*zetap*z8;

    Jacobian[1, 0] := -xim*zetam*x1-xip*zetam*x2+xim*zetam*x3+xip*zetam*x4-xim*zetap*x5-xip*zetap*x6+xim*zetap*x7+xip*zetap*x8;
    Jacobian[1, 1] := -xim*zetam*y1-xip*zetam*y2+xim*zetam*y3+xip*zetam*y4-xim*zetap*y5-xip*zetap*y6+xim*zetap*y7+xip*zetap*y8;
    Jacobian[1, 2] := -xim*zetam*z1-xip*zetam*z2+xim*zetam*z3+xip*zetam*z4-xim*zetap*z5-xip*zetap*z6+xim*zetap*z7+xip*zetap*z8;

    Jacobian[2, 0] := -etam*xim*x1-etam*xip*x2-etap*xim*x3-etap*xip*x4+etam*xim*x5+etam*xip*x6+etap*xim*x7+etap*xip*x8;
    Jacobian[2, 1] := -etam*xim*y1-etam*xip*y2-etap*xim*y3-etap*xip*y4+etam*xim*y5+etam*xip*y6+etap*xim*y7+etap*xip*y8;
    Jacobian[2, 2] := -etam*xim*z1-etam*xip*z2-etap*xim*z3-etap*xip*z4+etam*xim*z5+etam*xip*z6+etap*xim*z7+etap*xip*z8;

    Jacobian := Jacobian * 0.125;

    DetJ := Abs(Det(Jacobian));

    Jacobian := Invert(Jacobian);

    G := TVMobj.Create(3,8);

    G[0, 0] := -0.125*etam*zetam;
    G[0, 1] := +0.125*etam*zetam;
    G[0, 2] := -0.125*etap*zetam;
    G[0, 3] := +0.125*etap*zetam;
    G[0, 4] := -0.125*etam*zetap;
    G[0, 5] := +0.125*etam*zetap;
    G[0, 6] := -0.125*etap*zetap;
    G[0, 7] := +0.125*etap*zetap;

    G[1, 0] := -0.125*xim*zetam;
    G[1, 1] := -0.125*xip*zetam;
    G[1, 2] := +0.125*xim*zetam;
    G[1, 3] := +0.125*xip*zetam;
    G[1, 4] := -0.125*xim*zetap;
    G[1, 5] := -0.125*xip*zetap;
    G[1, 6] := +0.125*xim*zetap;
    G[1, 7] := +0.125*xip*zetap;

    G[2, 0] := -0.125*etam*xim;
    G[2, 1] := -0.125*etam*xip;
    G[2, 2] := -0.125*etap*xim;
    G[2, 3] := -0.125*etap*xip;
    G[2, 4] := +0.125*etam*xim;
    G[2, 5] := +0.125*etam*xip;
    G[2, 6] := +0.125*etap*xim;
    G[2, 7] := +0.125*etap*xip;

    B := TVMobj.Create(3,8);

    B := MatMult(Jacobian, G);

    BT := B.Transpose;

    Ki := TVMobj.Create(8,8);

    Ki := MatMult(BT, B);

    Ki := Ki * (wxi[p] * weta[p] * wzeta[p] * DetJ);

    FK := FK + Ki;

  end;

  FK := FK * FConductivity;

end;

procedure TBrick_H8V1.SetGaussPoints;
var

  p : Integer;

begin

  SetLength(wxi, FIntegPoints);
  SetLength(weta, FIntegPoints);
  SetLength(wzeta, FIntegPoints);
  SetLength(xi, FIntegPoints);
  SetLength(eta, FIntegPoints);
  SetLength(zeta, FIntegPoints);

  for p := 0 to FIntegPoints - 1 do
  begin

    // One integration point
    if FIntegPoints = 1 then
    begin
      wxi[p] := 2;
      weta[p] := 2;
      wzeta[p] := 2;

      xi[p] := 0;
      eta[p] := 0;
      zeta[p] := 0;
    end;

    // Eight integration points
    if FIntegPoints = 8 then
    begin
      wxi[p] := 1;
      weta[p] := 1;
      wzeta[p] := 1;

      case p of
      0: begin xi[p] := -0.5773502692; eta[p] := -0.5773502692; zeta[p] := -0.5773502692; end;
      1: begin xi[p] := +0.5773502692; eta[p] := -0.5773502692; zeta[p] := -0.5773502692; end;
      2: begin xi[p] := -0.5773502692; eta[p] := +0.5773502692; zeta[p] := -0.5773502692; end;
      3: begin xi[p] := +0.5773502692; eta[p] := +0.5773502692; zeta[p] := -0.5773502692; end;
      4: begin xi[p] := -0.5773502692; eta[p] := -0.5773502692; zeta[p] := +0.5773502692; end;
      5: begin xi[p] := +0.5773502692; eta[p] := -0.5773502692; zeta[p] := +0.5773502692; end;
      6: begin xi[p] := -0.5773502692; eta[p] := +0.5773502692; zeta[p] := +0.5773502692; end;
      7: begin xi[p] := +0.5773502692; eta[p] := +0.5773502692; zeta[p] := +0.5773502692; end;
      end;
    end;

    // Twenty seven integration points
    if FIntegPoints = 27 then
    begin
      wxi[p] := 1;
      weta[p] := 1;
      wzeta[p] := 1;

      case p of
      0:  begin xi[p] := -0.7745966692; eta[p] := -0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      1:  begin xi[p] := +0.7745966692; eta[p] := -0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      2:  begin xi[p] := -0.7745966692; eta[p] := +0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      3:  begin xi[p] := +0.7745966692; eta[p] := +0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      4:  begin xi[p] := -0.7745966692; eta[p] := +0.0000000000; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      5:  begin xi[p] := +0.7745966692; eta[p] := +0.0000000000; zeta[p] := -0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      6:  begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      7:  begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := -0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      8:  begin xi[p] := +0.0000000000; eta[p] := +0.0000000000; zeta[p] := -0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      9:  begin xi[p] := -0.7745966692; eta[p] := -0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      10: begin xi[p] := +0.7745966692; eta[p] := -0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      11: begin xi[p] := -0.7745966692; eta[p] := +0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      12: begin xi[p] := +0.7745966692; eta[p] := +0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      13: begin xi[p] := -0.7745966692; eta[p] := +0.0000000000; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      14: begin xi[p] := +0.7745966692; eta[p] := +0.0000000000; zeta[p] := +0.7745966692; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      15: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      16: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := +0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.5555555556; end;
      17: begin xi[p] := +0.0000000000; eta[p] := +0.0000000000; zeta[p] := +0.7745966692; wxi[p] := 0.8888888889; weta[p] := 0.8888888889; wzeta[p] := 0.5555555556; end;
      18: begin xi[p] := -0.7745966692; eta[p] := -0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      19: begin xi[p] := +0.7745966692; eta[p] := -0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      20: begin xi[p] := -0.7745966692; eta[p] := +0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      21: begin xi[p] := +0.7745966692; eta[p] := +0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      22: begin xi[p] := -0.7745966692; eta[p] := +0.0000000000; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.8888888889; end;
      23: begin xi[p] := +0.7745966692; eta[p] := +0.0000000000; zeta[p] := +0.0000000000; wxi[p] := 0.5555555556; weta[p] := 0.8888888889; wzeta[p] := 0.8888888889; end;
      24: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      25: begin xi[p] := +0.0000000000; eta[p] := -0.7745966692; zeta[p] := +0.0000000000; wxi[p] := 0.8888888889; weta[p] := 0.5555555556; wzeta[p] := 0.8888888889; end;
      26: begin xi[p] := +0.0000000000; eta[p] := +0.0000000000; zeta[p] := +0.0000000000; wxi[p] := 0.8888888889; weta[p] := 0.8888888889; wzeta[p] := 0.8888888889; end;
      end;
    end;

  end;

end;

procedure TBrick_H8V1.SetSourceOnBrick(vb: Double);
begin

  Fb := AddScalar(Fb, vb * FVolume * 0.125);

end;

procedure TBrick_H8V1.SetSourceOnEdge(EIndex: Integer; ve: Double);
var

  j : Integer;

  n : Array[0..1] of Integer;

  e : ELibException;

begin

  if (EIndex < 0) or (EIndex > FNbEdges-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FEdges[EIndex].NbNodes - 1 do
    n[j] := FEdges[EIndex].NodeId[j];

  Fb[n[0], 0] := Fb[n[0], 0] + ve * FEdges[EIndex].Length * 0.5;
  Fb[n[1], 0] := Fb[n[1], 0] + ve * FEdges[EIndex].Length * 0.5;

end;

procedure TBrick_H8V1.SetSourceOnFace(FIndex: Integer; e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnFace(FIndex, sigma * e * teta, Tinf);

end;

procedure TBrick_H8V1.SetSourceOnFace(FIndex: Integer; vf: Double);
var

  e : ELibException;

  j : Integer;

  n : Array[0..3] of Integer;

begin

  if (FIndex < 0) or (FIndex > FNbFaces - 1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbFaces-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  Fb[n[0], 0] := Fb[n[0], 0] + vf * FFaces[FIndex].Area * 0.25;
  Fb[n[1], 0] := Fb[n[1], 0] + vf * FFaces[FIndex].Area * 0.25;
  Fb[n[2], 0] := Fb[n[2], 0] + vf * FFaces[FIndex].Area * 0.25;
  Fb[n[3], 0] := Fb[n[3], 0] + vf * FFaces[FIndex].Area * 0.25;

end;

procedure TBrick_H8V1.SetSourceOnFace(FIndex: Integer; h, Tinf: Double);
var

  e : ELibException;

  Kh : TVMobj;

  j : Integer;

  n : Array[0..3] of Integer;

  i: Integer;

begin

  if (FIndex < 0) or (FIndex > FNbFaces - 1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  Fb[n[0], 0] := Fb[n[0], 0] + h * Tinf * FFaces[FIndex].Area * 0.25;
  Fb[n[1], 0] := Fb[n[1], 0] + h * Tinf * FFaces[FIndex].Area * 0.25;
  Fb[n[2], 0] := Fb[n[2], 0] + h * Tinf * FFaces[FIndex].Area * 0.25;
  Fb[n[3], 0] := Fb[n[3], 0] + h * Tinf * FFaces[FIndex].Area * 0.25;

  Kh := TVMobj.Create(FNbNodes, FNbNodes); //Create always zero-fills, so no separate SetZero needed

  Kh[n[0], n[0]] := h * FFaces[FIndex].J[0, 0];
  Kh[n[0], n[1]] := h * FFaces[FIndex].J[0, 1];
  Kh[n[0], n[2]] := h * FFaces[FIndex].J[0, 2];
  Kh[n[0], n[3]] := h * FFaces[FIndex].J[0, 3];

  Kh[n[1], n[0]] := h * FFaces[FIndex].J[1, 0];
  Kh[n[1], n[1]] := h * FFaces[FIndex].J[1, 1];
  Kh[n[1], n[2]] := h * FFaces[FIndex].J[1, 2];
  Kh[n[1], n[3]] := h * FFaces[FIndex].J[1, 3];

  Kh[n[2], n[0]] := h * FFaces[FIndex].J[2, 0];
  Kh[n[2], n[1]] := h * FFaces[FIndex].J[2, 1];
  Kh[n[2], n[2]] := h * FFaces[FIndex].J[2, 2];
  Kh[n[2], n[3]] := h * FFaces[FIndex].J[2, 3];

  Kh[n[3], n[0]] := h * FFaces[FIndex].J[3, 0];
  Kh[n[3], n[1]] := h * FFaces[FIndex].J[3, 1];
  Kh[n[3], n[2]] := h * FFaces[FIndex].J[3, 2];
  Kh[n[3], n[3]] := h * FFaces[FIndex].J[3, 3];

  FK := FK + Kh;

end;


procedure TBrick_H8V1.SetSourceOnNode(NIndex: Integer; vn: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes - 1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[NIndex, 0] := Fb[NIndex, 0] + vn;

end;

procedure TBrick_H8V1.SetTransientTerm;
var

  p : Integer;

  i, j : Integer;

  xim, xip : Double;
  etam, etap : Double;
  zetam, zetap : Double;

  Jacobian : TVMobj;
  DetJ : Double;

  Mi : TVMobj;

  N: Array[0..7] of Double;

begin

  FM := TVMobj.Create(FM.Rows, FM.Cols);

  for p := 0 to FIntegPoints - 1 do
  begin

    xim := (1 - xi[p]);
    xip := (1 + xi[p]);

    etam := (1 - eta[p]);
    etap := (1 + eta[p]);

    zetam := (1 - zeta[p]);
    zetap := (1 + zeta[p]);

    Jacobian := TVMobj.Create(3,3);

    Jacobian[0, 0] := -etam*zetam*x1+etam*zetam*x2-etap*zetam*x3+etap*zetam*x4-etam*zetap*x5+etam*zetap*x6-etap*zetap*x7+etap*zetap*x8;
    Jacobian[0, 1] := -etam*zetam*y1+etam*zetam*y2-etap*zetam*y3+etap*zetam*y4-etam*zetap*y5+etam*zetap*y6-etap*zetap*y7+etap*zetap*y8;
    Jacobian[0, 2] := -etam*zetam*z1+etam*zetam*z2-etap*zetam*z3+etap*zetam*z4-etam*zetap*z5+etam*zetap*z6-etap*zetap*z7+etap*zetap*z8;

    Jacobian[1, 0] := -xim*zetam*x1-xip*zetam*x2+xim*zetam*x3+xip*zetam*x4-xim*zetap*x5-xip*zetap*x6+xim*zetap*x7+xip*zetap*x8;
    Jacobian[1, 1] := -xim*zetam*y1-xip*zetam*y2+xim*zetam*y3+xip*zetam*y4-xim*zetap*y5-xip*zetap*y6+xim*zetap*y7+xip*zetap*y8;
    Jacobian[1, 2] := -xim*zetam*z1-xip*zetam*z2+xim*zetam*z3+xip*zetam*z4-xim*zetap*z5-xip*zetap*z6+xim*zetap*z7+xip*zetap*z8;

    Jacobian[2, 0] := -etam*xim*x1-etam*xip*x2-etap*xim*x3-etap*xip*x4+etam*xim*x5+etam*xip*x6+etap*xim*x7+etap*xip*x8;
    Jacobian[2, 1] := -etam*xim*y1-etam*xip*y2-etap*xim*y3-etap*xip*y4+etam*xim*y5+etam*xip*y6+etap*xim*y7+etap*xip*y8;
    Jacobian[2, 2] := -etam*xim*z1-etam*xip*z2-etap*xim*z3-etap*xip*z4+etam*xim*z5+etam*xip*z6+etap*xim*z7+etap*xip*z8;

    Jacobian := Jacobian * 0.125;

    DetJ := Abs(Det(Jacobian));

    N[0] := 0.125*(1-xi[p])*(1-eta[p])*(1-zeta[p]);
    N[1] := 0.125*(1+xi[p])*(1-eta[p])*(1-zeta[p]);
    N[2] := 0.125*(1-xi[p])*(1+eta[p])*(1-zeta[p]);
    N[3] := 0.125*(1+xi[p])*(1+eta[p])*(1-zeta[p]);
    N[4] := 0.125*(1-xi[p])*(1-eta[p])*(1+zeta[p]);
    N[5] := 0.125*(1+xi[p])*(1-eta[p])*(1+zeta[p]);
    N[6] := 0.125*(1-xi[p])*(1+eta[p])*(1+zeta[p]);
    N[7] := 0.125*(1+xi[p])*(1+eta[p])*(1+zeta[p]);

    Mi := TVMobj.Create(8,8);

    for i := 0 to 7 do
    begin

      for j := 0 to 7 do
      begin

        Mi[i, j] := N[i]*N[j];

      end;

    end;

    Mi := Mi * (wxi[p] * weta[p] * wzeta[p] * DetJ);

    FM := FM + Mi;

  end;

  FM := FM * (FSpecificHeat * FDensity);

  if FTimeInterval > 0 then
    FM := FM * (1 / FTimeInterval);

end;

end.
