unit CXS.FEMLAP.Brick_W6V1;

// Hexa brick element with 8 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node, CXS.FEMLAP.Element_Face, CXS.FEMLAP.Element_Brick, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Brick_T4V1;

(*
   Wedge element.



                       5*
                 eta   /|\
                  |   / |  \
                  |  /  |    \
                  | /   |      \
                  |/    |        \
              +1.0-     |          \
                 /|     |            \
                / |    3*-------------*4
               /  |    /             /
              /   |   /             /
             /    |  /             /
           2*     | /             /
            |\    |/             /
            |  \  O-------------|----> xi
            |    \             /+1.0
            |   /  \          /
            |  /     \       /
            | /        \    /
            |/           \ /
           0*-------------*1
           /+1.0
          /
         zeta
*)

type TFace = class(TObject)

  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;

end;

type TBrick_W6V1 = class(TElement_Brick)

  private

    x1, y1, z1: Double;
    x2, y2, z2: Double;
    x3, y3, z3: Double;
    x4, y4, z4: Double;
    x5, y5, z5: Double;
    x6, y6, z6: Double;

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
      NIndex - [in] node id (0 - 5).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn : Double); overload;

    (*
    Description:
      Set source at center of edge.
    Parameters:
      EIndex - [in] node id (0 - 8).
      ve - [in] value at edge.
    *)
    procedure SetSourceOnEdge(EIndex: Integer; ve : Double); overload;

    (*
    Description:
      Set source at center of face.
    Parameters:
      FIndex - [in] node id (0 - 4).
      vf - [in] value at face.
    *)
    procedure SetSourceOnFace(FIndex: Integer; vf : Double); overload;

    (*
    Description:
      Set source on face - convection.
    Parameters:
      FIndex - [in] node id (0 - 4).
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(FIndex: Integer; h, Tinf: Double); overload;

    (*
    Description:
      Set source on face - radiation.
    Parameters:
      FIndex - [in] node id (0 - 4).
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnFace(FIndex: Integer; e, teta, Tinf: Double); overload;

    (*
    Description:
      Set source at center of wedge.
    Parameters:
      vb - [in] value at center of brick.
    *)
    procedure SetSourceOnBrick(vb : Double); overload;

    procedure Integrate; override;

end;

implementation

{ TBrick_W6V1 }

procedure TBrick_W6V1.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if fTransient then SetTransientTerm;

end;

procedure TBrick_W6V1.CalcGeoProperties;
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

  // Create edges
  FEdges[0].NodeId[0] := 0;
  FEdges[0].NodeId[1] := 1;

  FEdges[1].NodeId[0] := 1;
  FEdges[1].NodeId[1] := 2;

  FEdges[2].NodeId[0] := 2;
  FEdges[2].NodeId[1] := 0;

  FEdges[3].NodeId[0] := 3;
  FEdges[3].NodeId[1] := 4;

  FEdges[4].NodeId[0] := 4;
  FEdges[4].NodeId[1] := 5;

  FEdges[5].NodeId[0] := 5;
  FEdges[5].NodeId[1] := 3;

  FEdges[6].NodeId[0] := 0;
  FEdges[6].NodeId[1] := 3;

  FEdges[7].NodeId[0] := 1;
  FEdges[7].NodeId[1] := 4;

  FEdges[8].NodeId[0] := 2;
  FEdges[8].NodeId[1] := 5;

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

  FFaces[1].NodeId[0] := 3;
  FFaces[1].NodeId[1] := 4;
  FFaces[1].NodeId[2] := 5;

  FFaces[2].NodeId[0] := 0;
  FFaces[2].NodeId[1] := 1;
  FFaces[2].NodeId[2] := 4;
  FFaces[2].NodeId[3] := 3;

  FFaces[3].NodeId[0] := 1;
  FFaces[3].NodeId[1] := 2;
  FFaces[3].NodeId[2] := 5;
  FFaces[3].NodeId[3] := 4;

  FFaces[4].NodeId[0] := 2;
  FFaces[4].NodeId[1] := 0;
  FFaces[4].NodeId[2] := 3;
  FFaces[4].NodeId[3] := 5;

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
  Brick_T4V1.Node[3] := Self.Node[4];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 2
  Brick_T4V1.Node[0] := Self.Node[0];
  Brick_T4V1.Node[1] := Self.Node[2];
  Brick_T4V1.Node[2] := Self.Node[4];
  Brick_T4V1.Node[3] := Self.Node[5];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  // Tetra 3
  Brick_T4V1.Node[0] := Self.Node[0];
  Brick_T4V1.Node[1] := Self.Node[3];
  Brick_T4V1.Node[2] := Self.Node[4];
  Brick_T4V1.Node[3] := Self.Node[5];

  Brick_T4V1.CalcGeoProperties;
  FVolume := FVolume + Brick_T4V1.Volume;

  Brick_T4V1.Free;

end;

constructor TBrick_W6V1.Create;
var

  i : Integer;

begin

  inherited;

  FNbNodes := 6;
  FNbEdges := 9;
  FNbFaces := 5;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);
  SetLength(FEdges, FNbEdges);
  SetLength(FFaces, FNbFaces);

  for i := 0 to FNbEdges - 1 do
    FEdges[i] := TEdge_B2V1.Create;

  for i := 0 to 1 do
    FFaces[i] := TFace_T3V1.Create;

  for i := 2 to FNbFaces - 1 do
    FFaces[i] := TFace_Q4V1.Create;

  FIntegPoints := 6;
  SetGaussPoints;

  Fb := TVMobj.Create(FNbNodes, 1);

  FM := TVMobj.Create(FNbNodes, FNbNodes);
  FK := TVMobj.Create(FNbNodes, FNbNodes);

end;

destructor TBrick_W6V1.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbEdges - 1 do
    FEdges[i].Free;

  for i := 0 to FNbFaces - 1 do
    FFaces[i].Free;

  inherited;

end;

procedure TBrick_W6V1.Integrate;
begin
  inherited;

end;

procedure TBrick_W6V1.ReCalcD;
begin
  inherited;

end;

procedure TBrick_W6V1.SetDiffusionTerm;
var

  p : Integer;

  xieta : Double;
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

    Jacobian := TVMobj.Create(3,3);

    xieta := (-xi[p] - eta[p] + 1);
    zetam := (1 - zeta[p]);
    zetap := (1 + zeta[p]);

    Jacobian[0, 0] := 0.5*x5*zetap-0.5*x4*zetap+0.5*x2*zetam-0.5*x1*zetam;
    Jacobian[0, 1] := 0.5*y5*zetap-0.5*y4*zetap+0.5*y2*zetam-0.5*y1*zetam;
    Jacobian[0, 2] := 0.5*z5*zetap-0.5*z4*zetap+0.5*z2*zetam-0.5*z1*zetam;

    Jacobian[1, 0] := 0.5*x6*zetap-0.5*x4*zetap+0.5*x3*zetam-0.5*x1*zetam;
    Jacobian[1, 1] := 0.5*y6*zetap-0.5*y4*zetap+0.5*y3*zetam-0.5*y1*zetam;
    Jacobian[1, 2] := 0.5*z6*zetap-0.5*z4*zetap+0.5*z3*zetam-0.5*z1*zetam;

    Jacobian[2, 0] := 0.5*x5*xi[p]-0.5*x2*xi[p]+0.5*x4*xieta-0.5*x1*xieta+0.5*eta[p]*x6-0.5*eta[p]*x3;
    Jacobian[2, 1] := 0.5*eta[p]*y6+0.5*xi[p]*y5+0.5*xieta*y4-0.5*eta[p]*y3-0.5*xi[p]*y2-0.5*xieta*y1;
    Jacobian[2, 2] := 0.5*eta[p]*z6+0.5*xi[p]*z5+0.5*xieta*z4-0.5*eta[p]*z3-0.5*xi[p]*z2-0.5*xieta*z1;

    DetJ := Abs(Det(Jacobian));

    Jacobian := Invert(Jacobian);

    G := TVMobj.Create(3,6);

    G[0, 0] := -0.5*zetam;
    G[0, 1] := 0.5*zetam;
    G[0, 2] := 0;
    G[0, 3] := -0.5*zetap;
    G[0, 4] := 0.5*zetap;
    G[0, 5] := 0;

    G[1, 0] := -0.5*zetam;
    G[1, 1] := 0;
    G[1, 2] := 0.5*zetam;
    G[1, 3] := -0.5*zetap;
    G[1, 4] := 0;
    G[1, 5] := 0.5*zetap;

    G[2, 0] := -0.5*xieta;
    G[2, 1] := -0.5*xi[p];
    G[2, 2] := -0.5*eta[p];
    G[2, 3] := 0.5*xieta;
    G[2, 4] := 0.5*xi[p];
    G[2, 5] := 0.5*eta[p];

    B := TVMobj.Create(3,6);

    B := MatMult(Jacobian, G);

    BT := B.Transpose;

    Ki := TVMobj.Create(6,6);

    Ki := MatMult(BT, B);

    Ki := Ki * (wxi[p] * weta[p] * wzeta[p] * DetJ);

    FK := FK + Ki;

  end;

  FK := FK * FConductivity;

end;

procedure TBrick_W6V1.SetGaussPoints;
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

    // Six integration points: the three-point degree-two rule on the
    // triangle, at each of two Gauss stations along the prism axis.
    //
    // The weights are multiplied together at the integration site
    // (wxi*weta*wzeta*DetJ), so their PRODUCT is what has to come to the
    // right total: the reference triangle's area of 1/2 times the
    // 2 of the zeta range, i.e. 1 over the six points. Carrying 1/6 on
    // wxi - the triangle rule's own weight - and 1 on the other two does
    // that, and keeps each factor recognisable.
    //
    // Both of these were wrong before, and ThermSlab measured the
    // consequences exactly. The weights were 1/2 each, so the product
    // came to (1/2)^3 * 6 = 3/4 of what it should be, and every
    // conduction matrix this element built was 3/4 of its correct
    // magnitude. The two off-diagonal triangle points were at 1/3 rather
    // than 2/3, which is not the degree-two rule at all - the three
    // points have to sit at the midpoints of the lines from the centroid
    // to the vertices for the rule to be exact on a quadratic.
    if FIntegPoints = 6 then
    begin
      wxi[p] := 1/6;
      weta[p] := 1;
      wzeta[p] := 1;

      case p of
      0: begin xi[p] := 1/6; eta[p] := 1/6; zeta[p] := -1/sqrt(3); end;
      1: begin xi[p] := 2/3; eta[p] := 1/6; zeta[p] := -1/sqrt(3); end;
      2: begin xi[p] := 1/6; eta[p] := 2/3; zeta[p] := -1/sqrt(3); end;
      3: begin xi[p] := 1/6; eta[p] := 1/6; zeta[p] :=  1/sqrt(3); end;
      4: begin xi[p] := 2/3; eta[p] := 1/6; zeta[p] :=  1/sqrt(3); end;
      5: begin xi[p] := 1/6; eta[p] := 2/3; zeta[p] :=  1/sqrt(3); end;
      end;
    end;

    // Nine integration points
    if FIntegPoints = 9 then
    begin
      wxi[p] := 1;
      weta[p] := 1;
      wzeta[p] := 1;

      case p of
      0: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/6; eta[p] := 1/6; zeta[p] := -sqrt(3)/sqrt(5); end;
      1: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/3; eta[p] := 1/6; zeta[p] := -sqrt(3)/sqrt(5); end;
      2: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/6; eta[p] := 1/3; zeta[p] := -sqrt(3)/sqrt(5); end;
      3: begin wxi[p] := 8/18; weta[p] := 8/18; wzeta[p] := 8/18; xi[p] := 1/6; eta[p] := 1/6; zeta[p] := 0; end;
      4: begin wxi[p] := 8/18; weta[p] := 8/18; wzeta[p] := 8/18; xi[p] := 1/3; eta[p] := 1/6; zeta[p] := 0; end;
      5: begin wxi[p] := 8/18; weta[p] := 8/18; wzeta[p] := 8/18; xi[p] := 1/6; eta[p] := 1/3; zeta[p] := 0; end;
      6: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/6; eta[p] := 1/6; zeta[p] := +sqrt(3)/sqrt(5); end;
      7: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/3; eta[p] := 1/6; zeta[p] := +sqrt(3)/sqrt(5); end;
      8: begin wxi[p] := 5/18; weta[p] := 5/18; wzeta[p] := 5/18; xi[p] := 1/6; eta[p] := 1/3; zeta[p] := +sqrt(3)/sqrt(5); end;
      end;
    end;

  end;

end;

procedure TBrick_W6V1.SetSourceOnBrick(vb: Double);
begin

  Fb := AddScalar(Fb, vb * FVolume / 6);

end;

procedure TBrick_W6V1.SetSourceOnEdge(EIndex: Integer; ve: Double);
var

  e : ELibException;

  j : Integer;

  n : Array[0..1] of Integer;

begin

  if (EIndex < 0) or (EIndex > FNbEdges-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbEdges-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to 1 do
    n[j] := FEdges[EIndex].NodeId[j];

  Fb[n[0], 0] := Fb[n[0], 0] + ve * FEdges[EIndex].Length * 0.5;
  Fb[n[1], 0] := Fb[n[1], 0] + ve * FEdges[EIndex].Length * 0.5;

end;

procedure TBrick_W6V1.SetSourceOnFace(FIndex: Integer; e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnFace(FIndex, sigma * e * teta, Tinf);

end;

procedure TBrick_W6V1.SetSourceOnFace(FIndex: Integer; vf: Double);
var

  e : ELibException;

  j : Integer;
  n : Array[0..3] of Integer;

begin

  if (FIndex < 0) or (FIndex > FNbFaces-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbFaces-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  if FFaces[FIndex].NbNodes = 3 then
  begin

    // Tri element
    Fb[n[0], 0] := Fb[n[0], 0] + vf * FFaces[FIndex].Area / 3;
    Fb[n[1], 0] := Fb[n[1], 0] + vf * FFaces[FIndex].Area / 3;
    Fb[n[2], 0] := Fb[n[2], 0] + vf * FFaces[FIndex].Area / 3;

  end
  else if FFaces[FIndex].NbNodes = 4 then
  begin

    // Quad element
    Fb[n[0], 0] := Fb[n[0], 0] + vf * FFaces[FIndex].Area * 0.25;
    Fb[n[1], 0] := Fb[n[1], 0] + vf * FFaces[FIndex].Area * 0.25;
    Fb[n[2], 0] := Fb[n[2], 0] + vf * FFaces[FIndex].Area * 0.25;
    Fb[n[3], 0] := Fb[n[3], 0] + vf * FFaces[FIndex].Area * 0.25;

  end;

end;

procedure TBrick_W6V1.SetSourceOnFace(FIndex: Integer; h, Tinf: Double);
var

  e : ELibException;

  Kh : TVMobj;

  j : Integer;

  n : Array[0..3] of Integer;

begin

  if (FIndex < 0) or (FIndex > fNbFaces-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbFaces-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  for j := 0 to FFaces[FIndex].NbNodes - 1 do
    n[j] := FFaces[FIndex].NodeId[j];

  if FFaces[FIndex].NbNodes = 3 then
  begin

    // Tri element
    Fb[n[0], 0] := Fb[n[0], 0] + h * Tinf * FFaces[FIndex].Area / 3;
    Fb[n[1], 0] := Fb[n[1], 0] + h * Tinf * FFaces[FIndex].Area / 3;
    Fb[n[2], 0] := Fb[n[2], 0] + h * Tinf * FFaces[FIndex].Area / 3;

    Kh := TVMobj.Create(FNbNodes, FNbNodes); //Create always zero-fills, so no separate SetZero needed

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

  end
  else if FFaces[FIndex].NbNodes = 4 then
  begin

    // Quad element
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

end;


procedure TBrick_W6V1.SetSourceOnNode(NIndex: Integer; vn: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[NIndex, 0] := Fb[NIndex, 0] + vn;

end;

procedure TBrick_W6V1.SetTransientTerm;
var

  p : Integer;

  i, j : Integer;

  xieta : Double;
  zetam, zetap : Double;

  Jacobian : TVMobj;
  DetJ : Double;

  Mi : TVMobj;

  N: Array[0..5] of Double;

begin

  fM := TVMobj.Create(fM.Rows, fM.Cols);

  for p := 0 to FIntegPoints - 1 do
  begin

    Jacobian := TVMobj.Create(3,3);

    xieta := -xi[p] - eta[p] + 1;
    zetam := (1 - zeta[p]);
    zetap := (1 + zeta[p]);

    Jacobian[0, 0] := 0.5*x5*zetap-0.5*x4*zetap+0.5*x2*zetam-0.5*x1*zetam;
    Jacobian[0, 1] := 0.5*y5*zetap-0.5*y4*zetap+0.5*y2*zetam-0.5*y1*zetam;
    Jacobian[0, 2] := 0.5*z5*zetap-0.5*z4*zetap+0.5*z2*zetam-0.5*z1*zetam;

    Jacobian[1, 0] := 0.5*x6*zetap-0.5*x4*zetap+0.5*x3*zetam-0.5*x1*zetam;
    Jacobian[1, 1] := 0.5*y6*zetap-0.5*y4*zetap+0.5*y3*zetam-0.5*y1*zetam;
    Jacobian[1, 2] := 0.5*z6*zetap-0.5*z4*zetap+0.5*z3*zetam-0.5*z1*zetam;

    Jacobian[2, 0] := 0.5*x5*xi[p]-0.5*x2*xi[p]+0.5*x4*xieta-0.5*x1*xieta+0.5*eta[p]*x6-0.5*eta[p]*x3;
    Jacobian[2, 1] := 0.5*eta[p]*y6+0.5*xi[p]*y5+0.5*xieta*y4-0.5*eta[p]*y3-0.5*xi[p]*y2-0.5*xieta*y1;
    Jacobian[2, 2] := 0.5*eta[p]*z6+0.5*xi[p]*z5+0.5*xieta*z4-0.5*eta[p]*z3-0.5*xi[p]*z2-0.5*xieta*z1;

    DetJ := Abs(Det(Jacobian));

    N[0] := 0.5*(1-xi[p]-eta[p])*(1-zeta[p]);
    N[1] := 0.5*xi[p]*(1-zeta[p]);
    N[2] := 0.5*eta[p]*(1-zeta[p]);
    N[3] := 0.5*(1-xi[p]-eta[p])*(1+zeta[p]);
    N[4] := 0.5*xi[p]*(1+zeta[p]);
    N[5] := 0.5*eta[p]*(1+zeta[p]);

    Mi := TVMobj.Create(6,6);

    for i := 0 to 5 do
    begin

      for j := 0 to 5 do
      begin

        Mi[i, j] := N[i]*N[j];

      end;

    end;

    Mi := Mi * (wxi[p] * weta[p] * wzeta[p] * DetJ);

    fM := fM + Mi;

  end;

  FM := FM * (FSpecificHeat * FDensity);

  if FTimeInterval > 0 then
    FM := FM * (1 / FTimeInterval);

end;

end.
