unit CXS.FEMLAP.EngineData;

{$mode delphi}{$H+}

interface

uses SysUtils,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element;

type NEleType = (elNone = -1, elBeam, elTri, elQuad, elTetra, elHexa, elPrism);

type NLocType = (loNone, loNode, loEdge, loFace);

type NCalcType = (caNone, caStatic, caStaticNonlinear, caTransient);

type NSolverType = (soNone, soUMFPACK, soGMRES, soPardiso);

type NDimId = (diX = 0, diY = 1, diZ = 2);

type TCallbackFunc = procedure of object;

type TDependantVarFunc = function(NodeId, ElementId : Integer) : Double of object;

type RFixed = record

  DependantVarFunc : TDependantVarFunc;
  DimId : NDimId;

  u : TExpressionList;

end;

type RSource = record

  LocType : NLocType;
  Index : Integer;
  DimId : NDimId;

  DependantVarFunc : TDependantVarFunc;
  F : TExpressionList;

end;

type RConvectiveBC = record

  LocType : NLocType;
  Index : Integer;

  DependantVarFunc : TDependantVarFunc;
  h, Tinf : TExpressionList;

end;

type RRadiationBC = record

  LocType : NLocType;
  Index : Integer;

  DependantVarFunc : TDependantVarFunc;
  e, Tinf : TExpressionList;

end;

type RThermalLoad = record

  LocType : NLocType;
  Index : Integer;

  DependantVarFunc : TDependantVarFunc;
  dT : TExpressionList;

end;

type TNodeData = class

  private

    Fid : Integer;
    Fx, Fy, Fz : Double;

    FNbSources : Integer;
    FSources : Array of RSource;

    FFixed : Array[0..2] of Boolean;

    FFixedValue : RFixed;

    function GetSource(SIndex: Integer): RSource;

    function GetFixed(VarId: NDimId): Boolean;
    procedure SetFixed(VarId: NDimId; const Value: Boolean);

  public

    constructor Create;
    destructor Destroy; override;

    property x : Double read Fx write Fx;
    property y : Double read Fy write Fy;
    property z : Double read Fz write Fz;

    property id : Integer read Fid write Fid;

    procedure AddSource(DependantVarFunc : TDependantVarFunc; F : TExpressionList; DimId : NDimId);

    property NbSources : Integer read FNbSources;
    property Source[SIndex : Integer] : RSource read GetSource;

    property FixedValue : RFixed read FFixedValue write FFixedValue;

    property Fixed[VarId : NDimId] : Boolean read GetFixed write SetFixed;

end;

type TElementData = class

  private

    FNbNodes : Integer;
    FNodes : Array of RNode;

    FEleType : NEleType;
    FMaterialId : Integer;

    FThickness, FSectionArea, FPerimeter : Double;

    FNbSources : Integer;
    FSources : Array of RSource;

    FNbConvectiveBCs : Integer;
    FConvectiveBCs : Array of RConvectiveBC;

    FNbRadiationBCs : Integer;
    FRadiationBCs : Array of RRadiationBC;

    function GetSource(SIndex: Integer): RSource;
    function GetNodeId(NIndex: Integer): Integer;
    procedure SetNodeId(NIndex: Integer; const Value: Integer);
    procedure SetNbNodes(const Value: Integer);

    function GetCoordX(NIndex: Integer): Double;
    function GetCoordY(NIndex: Integer): Double;
    function GetCoordZ(NIndex: Integer): Double;

    procedure SetCoordX(NIndex: Integer; const Value: Double);
    procedure SetCoordY(NIndex: Integer; const Value: Double);
    procedure SetCoordZ(NIndex: Integer; const Value: Double);

    function GetConvectiveBC(SIndex: Integer): RConvectiveBC;
    function GetRadiationBC(SIndex: Integer): RRadiationBC;

  public

    constructor Create;
    destructor Destroy; override;

    procedure AddSource(LocType : NLocType; Index : Integer; DependantVarFunc : TDependantVarFunc; F : TExpressionList);
    procedure AddConvection(LocType : NLocType; Index : Integer; DependantVarFunc : TDependantVarFunc; h, Tinf : TExpressionList);
    procedure AddRadiation(LocType : NLocType; Index : Integer; DependantVarFunc : TDependantVarFunc; e, Tinf : TExpressionList);

    property MaterialId : Integer read FMaterialId write FMaterialId;

    property NbSources : Integer read FNbSources;
    property NbConvectiveBCs : Integer read FNbConvectiveBCs;
    property NbRadiationBCs : Integer read FNbRadiationBCs;

    property Source[SIndex : Integer] : RSource read GetSource;
    property ConvectiveBC[SIndex : Integer] : RConvectiveBC read GetConvectiveBC;
    property RadiationBC[SIndex : Integer] : RRadiationBC read GetRadiationBC;

    property EleType : NEleType read FEleType write FEleType;

    property NbNodes : Integer read FNbNodes write SetNbNodes;
    property NodeId[NIndex : Integer] : Integer read GetNodeId write SetNodeId;

    property CoordX[NIndex : Integer] : Double read GetCoordX write SetCoordX;
    property CoordY[NIndex : Integer] : Double read GetCoordY write SetCoordY;
    property CoordZ[NIndex : Integer] : Double read GetCoordZ write SetCoordZ;

    property Thickness : Double read FThickness write FThickness;
    property SectionArea : Double read FSectionArea write FSectionArea;
    property Perimeter : Double read FPerimeter write FPerimeter;

end;

type RMaterialData = record

  DependantVarFunc : TDependantVarFunc;

  rho : TExpressionList;        // density
  E, Poisson : TExpressionList; // elastic modulus and poisson coefficient
  Cp, k : TExpressionList;      // specific heat and thermal conductivity
  alpha : TExpressionList;      // thermal expansion

end;

type RStress = record

  Sxx, Syy, Sxy : Double;

end;

type TMaterialDataArray = Array of RMaterialData;
type TNodeDataArray = Array of TNodeData;
type TElementDataArray = Array of TElementData;

implementation

{ TNodeData }

procedure TNodeData.AddSource(DependantVarFunc: TDependantVarFunc; F: TExpressionList; DimId: NDimId);
begin

  SetLength(FSources, FNbSources + 1);

  FSources[FNbSources].DependantVarFunc := DependantVarFunc;
  FSources[FNbSources].DimId := DimId;
  FSources[FNbSources].F := F;

  Inc(FNbSources);

end;

constructor TNodeData.Create;
begin

  FNbSources := 0;

  FFixed[Integer(diX)] := False;
  FFixed[Integer(diY)] := False;
  FFixed[Integer(diZ)] := False;

end;

destructor TNodeData.Destroy;
begin

  inherited;
end;

function TNodeData.GetFixed(VarId: NDimId): Boolean;
begin

  Result := FFixed[Integer(VarId)];

end;

function TNodeData.GetSource(SIndex: Integer): RSource;
begin

  Result := FSources[SIndex];

end;

procedure TNodeData.SetFixed(VarId: NDimId; const Value: Boolean);
begin

  FFixed[Integer(VarId)] := Value;

end;

{ TElementData }

procedure TElementData.AddConvection(LocType: NLocType; Index: Integer; DependantVarFunc: TDependantVarFunc; h, Tinf: TExpressionList);
begin

  SetLength(FConvectiveBCs, FNbConvectiveBCs + 1);

  FConvectiveBCs[FNbConvectiveBCs].LocType := LocType;
  FConvectiveBCs[FNbConvectiveBCs].Index := Index;

  FConvectiveBCs[FNbConvectiveBCs].DependantVarFunc := DependantVarFunc;
  FConvectiveBCs[FNbConvectiveBCs].h := h;
  FConvectiveBCs[FNbConvectiveBCs].Tinf := Tinf;

  Inc(FNbConvectiveBCs);

end;

procedure TElementData.AddRadiation(LocType: NLocType; Index: Integer; DependantVarFunc: TDependantVarFunc; e, Tinf: TExpressionList);
begin

  SetLength(FRadiationBCs, FNbRadiationBCs + 1);

  FRadiationBCs[FNbRadiationBCs].LocType := LocType;
  FRadiationBCs[FNbRadiationBCs].Index := Index;

  FRadiationBCs[FNbRadiationBCs].DependantVarFunc := DependantVarFunc;
  FRadiationBCs[FNbRadiationBCs].e := e;
  FRadiationBCs[FNbRadiationBCs].Tinf := Tinf;

  Inc(FNbRadiationBCs);

end;

procedure TElementData.AddSource(LocType: NLocType; Index: Integer; DependantVarFunc: TDependantVarFunc; F: TExpressionList);
begin

  SetLength(FSources, FNbSources + 1);

  FSources[FNbSources].LocType := LocType;
  FSources[FNbSources].Index := Index;

  FSources[FNbSources].DependantVarFunc := DependantVarFunc;
  FSources[FNbSources].F := F;

  Inc(FNbSources);

end;

constructor TElementData.Create;
begin

  FNbSources := 0;

end;

destructor TElementData.Destroy;
begin

  inherited;
end;

function TElementData.GetConvectiveBC(SIndex: Integer): RConvectiveBC;
begin

  Result := FConvectiveBCs[SIndex];

end;

function TElementData.GetCoordX(NIndex: Integer): Double;
begin

  Result := FNodes[NIndex].x;

end;

function TElementData.GetCoordY(NIndex: Integer): Double;
begin

  Result := FNodes[NIndex].y;

end;

function TElementData.GetCoordZ(NIndex: Integer): Double;
begin

  Result := FNodes[NIndex].z;

end;

function TElementData.GetNodeId(NIndex: Integer): Integer;
begin

  Result := FNodes[NIndex].id;

end;

function TElementData.GetRadiationBC(SIndex: Integer): RRadiationBC;
begin

  Result := FRadiationBCs[SIndex];

end;

function TElementData.GetSource(SIndex: Integer): RSource;
begin

  Result := FSources[SIndex];

end;

procedure TElementData.SetCoordX(NIndex: Integer; const Value: Double);
begin

  FNodes[NIndex].x := Value;

end;

procedure TElementData.SetCoordY(NIndex: Integer; const Value: Double);
begin

  FNodes[NIndex].y := Value;

end;

procedure TElementData.SetCoordZ(NIndex: Integer; const Value: Double);
begin

  FNodes[NIndex].z := Value;

end;

procedure TElementData.SetNbNodes(const Value: Integer);
begin

  FNbNodes := Value;
  SetLength(FNodes, FNbNodes);

end;

procedure TElementData.SetNodeId(NIndex: Integer; const Value: Integer);
begin

  FNodes[NIndex].id := Value;

end;

end.
