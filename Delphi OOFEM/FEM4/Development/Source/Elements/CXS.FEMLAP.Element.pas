unit CXS.FEMLAP.Element;

// General element class

{$mode delphi}{$H+}

interface

uses SysUtils, newVM,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node;

type
  TArrayOfInteger = array of Integer;

type TElement = class(TObject)

  private

    function GetNodeId(NIndex: Integer): Integer;
    procedure SetNodeId(NIndex: Integer; const Value: Integer);

    function GetCoordX(NIndex: Integer): Double;
    function GetCoordY(NIndex: Integer): Double;
    function GetCoordZ(NIndex: Integer): Double;

    procedure SetCoordX(NIndex: Integer; const Value: Double);
    procedure SetCoordY(NIndex: Integer; const Value: Double);
    procedure SetCoordZ(NIndex: Integer; const Value: Double);

    function GetNode(NIndex: Integer): RNode;
    procedure SetNode(NIndex: Integer; const Value: RNode);

  protected

    // Mass and stiffness matrices
    FM, FK : TVMobj;
    // Source vector - (N,1) column
    Fb : TVMobj;

    FJ : TVMobj;

    FNbNodes : Integer;
    FNodes : Array of RNode;
    FNodeIds : TArrayOfInteger;

    FTransient : Boolean;

    FTimeInterval : Double;

    FSpecificHeat : Double;
    FDensity : Double;
    FConductivity : Double;
    FElasticModulus : Double;
    FPoisson : Double;
    FThermalExpansion : Double;

    // v1/v2/vc are (3,1) column vectors, matching this file's own local
    // convention for element-local 3-vectors - see the unit's own port
    // notes below (GlobalToLocal's header comment) for why.
    procedure CrossProduct(var vc : TVMobj; v1, v2 : TVMobj);

    procedure GlobalToLocal(gc1, gc2, gc3: TVMobj; var lc1, lc2, lc3: TVMobj); overload;
    procedure GlobalToLocal(gc1, gc2, gc3, gc4: TVMobj; var lc1, lc2, lc3, lc4: TVMobj); overload;

  public

    constructor Create; virtual;
    destructor Destroy; override;

    procedure CalcGeoProperties; virtual; abstract;
    procedure Calc; virtual;
    procedure ReCalcD; virtual; abstract;

    procedure Integrate; virtual; abstract;
    property J : TVMobj read FJ;

    property NbNodes : Integer read FNbNodes;
    property NodeId[NIndex : Integer] : Integer read GetNodeId write SetNodeId;
    property NodeIds : TArrayOfInteger read FNodeIds;
    property Node[NIndex : Integer] : RNode read GetNode write SetNode;

    property CoordX[NIndex : Integer] : Double read GetCoordX write SetCoordX;
    property CoordY[NIndex : Integer] : Double read GetCoordY write SetCoordY;
    property CoordZ[NIndex : Integer] : Double read GetCoordZ write SetCoordZ;

    property Transient : Boolean read FTransient write FTransient;

    property K: TVMobj read FK;
    property M: TVMobj read FM;

    property b: TVMobj read Fb;

    property Conductivity: Double read FConductivity write FConductivity;
    property Density: Double read FDensity write FDensity;
    property SpecificHeat: Double read FSpecificHeat write FSpecificHeat;
    property ElasticModulus : Double read FElasticModulus write FElasticModulus;
    property Poisson : Double read FPoisson write FPoisson;
    property ThermalExpansion : Double read FThermalExpansion write FThermalExpansion;

    property TimeInterval: Double read FTimeInterval write FTimeInterval;

end;

implementation

{ TElement }

// Writes V's 3 elements (a (3,1) column vector) across row RowIdx of M (a
// 3x3 matrix) - replaces MtxVec's TMtx.SetRow, which newVM has no
// equivalent for (only 6 call sites total in this codebase, all in this
// file, so a small local helper rather than a new newVM.pas addition).
procedure SetMatRow3(var M: TVMobj; const V: TVMobj; RowIdx: Integer);
var
  j: Integer;
begin
  for j := 0 to 2 do
    M[RowIdx, j] := V[j, 0];
end;

procedure TElement.Calc;
begin

  Fb := TVMobj.Create(Fb.Rows, Fb.Cols); //Create always zero-fills - same shape, fresh zeros

end;

constructor TElement.Create;
begin

  FTransient := False;

  FConductivity := 1;
  FSpecificHeat := 1;
  FDensity := 1;
  FPoisson := 0;
  FElasticModulus := 1;

end;

destructor TElement.Destroy;
begin

  Inherited;

end;

procedure TElement.CrossProduct(var vc : TVMobj; v1, v2 : TVMobj);
begin

  vc[0,0] := v1[1,0] * v2[2,0] - v1[2,0] * v2[1,0];
  vc[1,0] := v1[2,0] * v2[0,0] - v1[0,0] * v2[2,0];
  vc[2,0] := v1[0,0] * v2[1,0] - v1[1,0] * v2[0,0];

end;

function TElement.GetCoordX(NIndex: Integer): Double;
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Result := FNodes[NIndex].x;

end;

function TElement.GetCoordY(NIndex: Integer): Double;
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Result := FNodes[NIndex].y;

end;

function TElement.GetCoordZ(NIndex: Integer): Double;
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Result := FNodes[NIndex].z;

end;

function TElement.GetNode(NIndex: Integer): RNode;
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Result.x := FNodes[NIndex].x;
  Result.y := FNodes[NIndex].y;
  Result.z := FNodes[NIndex].z;

end;

function TElement.GetNodeId(NIndex: Integer): Integer;
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e:=ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  Result := FNodes[NIndex].id;

end;

// gc1..gc4 and the local-frame outputs lc1..lc4 are (3,1) column vectors
// throughout this unit's port (matching TensorProd's MatMult(T,gc) usage
// below, which needs a proper column vector for a 3x3*3x1 product) -
// every element-local 3-vector (Vx/Vy/Vz/V21/V31/Vc/Vt) follows the same
// convention, indexed [i,0] rather than MtxVec's original [i].
procedure TElement.GlobalToLocal(gc1, gc2, gc3: TVMobj; var lc1, lc2, lc3: TVMobj);
var

  v21, v31 : TVMobj;
  l21, l31 : Double;

  vx, vy, vz : TVMobj;

  vc : TVMobj;
  vt : TVMobj;

  T : TVMobj;

begin

  V21 := gc2 - gc1;
  V31 := gc3 - gc1;

  l21 := Norm(V21);
  l31 := Norm(V31);

  Vx := TVMobj.Create(3,1);
  Vy := TVMobj.Create(3,1);
  Vz := TVMobj.Create(3,1);

  if l21 > 0 then
    Vx := V21 * (1/l21);

  Vt := TVMobj.Create(3,1);

  if l31 > 0 then
    Vt := V31 * (1/l31);

  Vc := TVMobj.Create(3,1);

  CrossProduct(Vc, Vx, Vt);

  Vz := Vc;

  if (Norm(Vc) > 0) then
    Vz := Vc * (1/Norm(Vc));

  CrossProduct(Vy, Vz, Vx);

  T := TVMobj.Create(3,3);

  SetMatRow3(T, Vx, 0);
  SetMatRow3(T, Vy, 1);
  SetMatRow3(T, Vz, 2);

  lc1 := MatMult(T,gc1);
  lc2 := MatMult(T,gc2);
  lc3 := MatMult(T,gc3);

end;

procedure TElement.GlobalToLocal(gc1, gc2, gc3, gc4: TVMobj; var lc1, lc2, lc3, lc4: TVMobj);
var

  v21, v31 : TVMobj;
  l21, l31 : Double;

  vx, vy, vz : TVMobj;

  vc : TVMobj;
  vt : TVMobj;

  T : TVMobj;

begin

  V21 := gc2 - gc1;
  V31 := gc3 - gc1;

  l21 := Norm(V21);
  l31 := Norm(V31);

  Vx := TVMobj.Create(3,1);
  Vy := TVMobj.Create(3,1);
  Vz := TVMobj.Create(3,1);

  if l21 > 0 then
    Vx := V21 * (1/l21);

  Vt := TVMobj.Create(3,1);

  if l31 > 0 then
    Vt := V31 * (1/l31);

  Vc := TVMobj.Create(3,1);

  CrossProduct(Vc, Vx, Vt);

  Vz := Vc;

  if (Norm(Vc) > 0) then
    Vz := Vc * (1/Norm(Vc));

  CrossProduct(Vy, Vz, Vx);

  T := TVMobj.Create(3,3);

  SetMatRow3(T, Vx, 0);
  SetMatRow3(T, Vy, 1);
  SetMatRow3(T, Vz, 2);

  lc1 := MatMult(T,gc1);
  lc2 := MatMult(T,gc2);
  lc3 := MatMult(T,gc3);
  lc4 := MatMult(T,gc4);

end;

procedure TElement.SetCoordX(NIndex: Integer; const Value: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  FNodes[NIndex].x := Value;

end;

procedure TElement.SetCoordY(NIndex: Integer; const Value: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  FNodes[NIndex].y := Value;

end;

procedure TElement.SetCoordZ(NIndex: Integer; const Value: Double);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  FNodes[NIndex].z := Value;

end;

procedure TElement.SetNode(NIndex: Integer; const Value: RNode);
begin

  FNodes[NIndex].x := Value.x;
  FNodes[NIndex].y := Value.y;
  FNodes[NIndex].z := Value.z;

end;

procedure TElement.SetNodeId(NIndex: Integer; const Value: Integer);
var

  e : ELibException;

begin

  if (NIndex < 0) or (NIndex > FNbNodes-1) then
  begin

    e := ELibException.Create('Error: Index out of bounds [0 - ' + IntToStr(FNbNodes-1) + '].');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  FNodes[NIndex].id := Value;
  FNodeIds[NIndex] := Value;

end;

end.
