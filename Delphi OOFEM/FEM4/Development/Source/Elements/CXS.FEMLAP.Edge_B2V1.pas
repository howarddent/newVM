unit CXS.FEMLAP.Edge_B2V1;

// Beam edge element with 2 nodes and 1 unkown per node

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node, CXS.FEMLAP.Element_Edge;

(*
   Edge/line element.

       0                 1
       *-----------------*-----> xi

*)

type TEdge_B2V1 = class(TElement_Edge)

  private

    x1, x2: Double;
    y1, y2: Double;
    z1, z2: Double;

    x21 : Double;
    y21 : Double;
    z21 : Double;

    procedure SetTransientTerm;
    procedure SetDiffusionTerm;

  public

    constructor Create; override;

    procedure CalcGeoProperties; override;
    procedure Calc; override;
    procedure ReCalcD; override;

    (*
    Description:
      Set source on node.
    Parameters:
      NIndex - [in] node id (0 - 1).
      vn - [in] value at node.
    *)
    procedure SetSourceOnNode(NIndex: Integer; vn: Double); overload;

    (*
    Description:
      Set source on node - convection.
    Parameters:
      NIndex - [in] node id (0 - 1).
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnNode(NIndex: Integer; h, Tinf: Double); overload;

    (*
    Description:
      Set source on node - radiation.
    Parameters:
      NIndex - [in] node id (0 - 1).
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnNode(NIndex: Integer; e, teta, Tinf: Double); overload;

    (*
    Description:
      Set source at center of edge.
    Parameters:
      ve - [in] value at edge.
    *)
    procedure SetSourceOnEdge(ve: Double); overload;

    (*
    Description:
      Set source on edge - convection.
    Parameters:
      h - [in] heat transfer coefficient.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnEdge(h, Tinf: Double); overload;

    (*
    Description:
      Set source on edge - radiation.
    Parameters:
      e - [in] emissivity.
      teta - [in] explicit component.
      Tinf - [in] temperature of the surrounding medium.
    *)
    procedure SetSourceOnEdge(e, teta, Tinf: Double); overload;

    procedure Integrate; override;

end;

implementation

{ TEdge_B2V1 }

procedure TEdge_B2V1.Calc;
begin

  inherited;

  // Calculate geometrical properties
  CalcGeoProperties;

  // Diffusion term
  SetDiffusionTerm;

  // Transient term
  if fTransient then SetTransientTerm;

end;

procedure TEdge_B2V1.CalcGeoProperties;
begin

  x1 := fNodes[0].x;
  y1 := fNodes[0].y;
  z1 := fNodes[0].z;

  x2 := fNodes[1].x;
  y2 := fNodes[1].y;
  z2 := fNodes[1].z;

  x21 := x2 - x1;
  y21 := y2 - y1;
  z21 := z2 - z1;

  FLength := sqrt(x21 * x21 + y21 * y21 + z21 * z21);

end;

constructor TEdge_B2V1.Create;
begin

  inherited;

  FNbNodes := 2;

  SetLength(FNodeIds, FNbNodes);

  SetLength(FNodes, FNbNodes);

  Fb := TVMobj.Create(FNbNodes, 1);

  FM := TVMobj.Create(FNbNodes, FNbNodes);
  FK := TVMobj.Create(FNbNodes, FNbNodes);

  FSectionArea := 1;
  FPerimeter := 1;

end;

procedure TEdge_B2V1.Integrate;
begin
  inherited;

end;

procedure TEdge_B2V1.ReCalcD;
begin
  inherited;

end;

procedure TEdge_B2V1.SetSourceOnEdge(ve: Double);
begin

  Fb := AddScalar(Fb, ve * 0.5);

end;

procedure TEdge_B2V1.SetSourceOnNode(NIndex: Integer; vn: Double);
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

procedure TEdge_B2V1.SetSourceOnEdge(h, Tinf: Double);
var

  Kh : TVMobj;

begin

  Fb[0,0] := Fb[0,0] + h * Tinf * FPerimeter * FLength;
  Fb[1,0] := Fb[1,0] + h * Tinf * FPerimeter * FLength;

  Kh := TVMobj.Create(fNbNodes,fNbNodes);

  Kh[0, 0] := h * FPerimeter * FLength;
  Kh[1, 1] := h * FPerimeter * FLength;

  FK := FK + Kh;

end;

procedure TEdge_B2V1.SetSourceOnEdge(e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnEdge(sigma * e * teta, Tinf);

end;

procedure TEdge_B2V1.SetSourceOnNode(NIndex: Integer; e, teta, Tinf: Double);
const

  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  SetSourceOnNode(NIndex, sigma * e * teta, Tinf);

end;

procedure TEdge_B2V1.SetSourceOnNode(NIndex: Integer; h, Tinf: Double);
var

  e : ELibException;

  Kh : TVMobj;

begin

  if (NIndex < 0) or (NIndex > fNbNodes - 1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Fb[NIndex,0] := Fb[NIndex,0] + h * Tinf * FPerimeter * FLength;

  Kh := TVMobj.Create(fNbNodes,fNbNodes);

  Kh[NIndex, NIndex] := h * FPerimeter * FLength;

  FK := FK + Kh;

end;

procedure TEdge_B2V1.SetDiffusionTerm;
begin

  FK[0, 0] := +1;
  FK[0, 1] := -1;
  FK[1, 0] := -1;
  FK[1, 1] := +1;

  if (FLength > 0) then
    FK := FK * (FSectionArea * FConductivity / FLength);

end;

procedure TEdge_B2V1.SetTransientTerm;
begin

  FM[0, 0] := 1/3;
  FM[0, 1] := 1/6;

  FM[1, 0] := 1/6;
  FM[1, 1] := 1/3;

  FM := FM * (FSectionArea * FLength * fSpecificHeat * fDensity);

  if FTimeInterval > 0 then
    FM := FM * (1 / FTimeInterval);

end;

end.
