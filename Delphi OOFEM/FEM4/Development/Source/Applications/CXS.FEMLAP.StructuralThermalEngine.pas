unit CXS.FEMLAP.StructuralThermalEngine;

{$mode delphi}{$H+}

interface

uses CXS.FEMLAP.EngineData,
     CXS.FEMLAP.ThermalEngine, CXS.FEMLAP.StructuralEngine,
     CXS.FEMLAP.Expression;

type NAnalysisType = (atNone, atStructural, atThermal, atStructuralThermal);

type TStructuralThermalEngine = class(TObject)

  private

    FStructuralEngine : TStructuralEngine;
    FThermalEngine : TThermalEngine;

    FPenaltyMethod : Boolean;

    // Control
    Fdt : Double;
    FTime : Double;
    FStep, FNbSteps : Integer;

    FCoupled: Boolean;

    function GetSolverType(AnalysisType: NAnalysisType): NSolverType;
    procedure SetSolverType(AnalysisType: NAnalysisType; const Value: NSolverType);
    function GetStep(AnalysisType: NAnalysisType): Integer;
    function GetResult(NIndex: Integer; VarId: NDimId; AnalysisType: NAnalysisType): Double;
    function GetNbSteps(AnalysisType: NAnalysisType): Integer;

    procedure StaticSolve;
    procedure TransientSolve(UpdateMatrix : Boolean);

    function GetDeformation(NIndex: Integer; VarId: NDimId): Double;
    function GetStress(EIndex: Integer): RStress;
    function GetTemperature(NIndex: Integer): Double;
    function GetNbElements: Integer;
    function GetNbNodes: Integer;
    function GetElement(ElementId: Integer; AnalysisType : NAnalysisType): TElementData;
    procedure SetCoupled(const Value: Boolean);

  public

    constructor Create;
    destructor Destroy; override;

    (*
    Description:
      Call before start adding mesh.
    Parameters:
    *)
    procedure BeginAddMesh;

    (*
    Description:
      Call after adding mesh.
    Parameters:
    *)
    procedure EndAddMesh;

    (*
    Description:
      Return number of nodes in the mesh.
    *)
    property NbNodes : Integer read GetNbNodes;

    (*
    Description:
      Add node to mesh and returns index of the node.
    Parameters:
      x - [in] x coordinate.
      y - [in] y coordinate.
      z - [in] z coordinate.
    *)
    function AddNode(x, y, z : Double) : Integer;

    property NbElements : Integer read GetNbElements;

    (*
    Description:
      Add element to mesh.
    Parameters:
      Nodes - [in] array of node ids.
      NbNodes - [in] number of node ids.
      EleType - [in] type of element.
      MaterialId - [in] id of the material.
      SectionArea - [in] section area.
      Perimeter - [in] perimeter of the section.
      Thickness - [in] thickness.
    *)
    function AddElement(Nodes : Array of Integer; NbNodes : Integer; EleType : NEleType; MaterialId : Integer; SectionArea : Double = 0; Perimeter : Double = 0; Thickness : Double = 0) : Integer;

    (*
    Description:
      Add material to a list and returns index of the material.
    Parameters:
      rho - [in] density.
      E - [in] elastic modulus.
      poisson - [in] poisson cofficient.
      Cp - [in] specific heat.
      k - [in] conductivity.
      alpha - [in] thermal expansion.
    *)
    function AddMaterial(DependantVarFunc : TDependantVarFunc; rho, E, poisson, Cp, k, alpha: TExpressionList) : Integer;

    (*
    Description:
      Should be called before setting constraints.
    Parameters:
    *)
    procedure BeginSetRestraints;

    (*
    Description:
      Set temperature restraint.
    Parameters:
      NodeId - [in] node global id.
      DependantVarFunc - [in] function which returns the dependant variable.
      u - [in] expression which describes temperature variation.
      DimId - [in] which dimension.
      AnalysisType - [in] analysis type.
    *)
    procedure SetNodeRestraint(NodeId : Integer; DependantVarFunc : TDependantVarFunc; u: TExpressionList; DimId : NDimId; AnalysisType : NAnalysisType);

    (*
    Description:
      Should be called after setting constraints.
    Parameters:
    *)
    procedure EndSetRestraints;

    (*
    Description:
      Set displacement on a node.
    Parameters:
      NodeId - [in] node global id.
      DependantVarFunc - [in] function which returns the dependant variable.
      F - [in] source.
      DimId - [in] which dimension.
      AnalysisType - [in] analysis type.
    *)
    procedure AddNodeSource(NodeId : Integer; DependantVarFunc : TDependantVarFunc; F : TExpressionList; DimId : NDimId; AnalysisType : NAnalysisType);

    (*
    Description:
      Set initial displacement field to a specific value.
    Parameters:
      u - [in] value of the displacement.
      AnalysisType - [in] analysis type.
    *)
    procedure SetInitialDeformation(u : Double); overload;

    (*
    Description:
      Set initial displacement field to a specific value.
    Parameters:
      T - [in] value of the displacement.
      AnalysisType - [in] analysis type.
    *)
    procedure SetInitialTemperature(T : Double; AnalysisType : NAnalysisType); overload;

    (*
    Description:
      Set callback function to be called after each iteration.
    Parameters:
      Func - [in] pointer to callback function.
    *)
    procedure SetEndPostIterationFunction(Func : TCallbackFunc; AnalysisType : NAnalysisType);

    (*
    Description:
      Penalty method.
    *)
    property PenaltyMethod : Boolean read FPenaltyMethod write FPenaltyMethod;

    (*
    Description:
      Solver type.
    *)
    property SolverType[AnalysisType : NAnalysisType] : NSolverType read GetSolverType write SetSolverType;

    (*
    Description:
      Calculate results.
    Parameters:
      CalcType - [in] solver type.
      UpdateMatrix - [in] update matrix during transient calculation.
    *)
    procedure Calc(CalcType : NCalcType; AnalysisType : NAnalysisType; UpdateMatrix : Boolean = False);

    property Coupled : Boolean read FCoupled write SetCoupled;

    (*
    Description:
      Step value.
    *)
    property Step[AnalysisType : NAnalysisType] : Integer read GetStep;

    (*
    Description:
      Return total number of steps.
    *)
    property NbSteps[AnalysisType : NAnalysisType] : Integer read GetNbSteps;

    (*
    Description:
      Current simulation time.
    *)
    property Time : Double read FTime write FTime;

    (*
    Description:
      Element.
    *)
    property Element[ElementId : Integer; AnalysisType : NAnalysisType] : TElementData read GetElement;

    (*
    Description:
      Return results (displacement or temperature).
    *)
    property Result[NIndex : Integer; VarId : NDimId; AnalysisType : NAnalysisType] : Double read GetResult;

    (*
    Description:
      Return deformation values.
    *)
    property Deformation[NIndex : Integer; VarId : NDimId] : Double read GetDeformation;

    (*
    Description:
      Return temperature values.
    *)
    property Temperature[NIndex : Integer] : Double read GetTemperature;

    (*
    Description:
      Return stress values.
    *)
    property Stress[EIndex : Integer] : RStress read GetStress;

end;

implementation

{ TStructuralThermalEngine }

function TStructuralThermalEngine.AddElement(Nodes: array of Integer; NbNodes: Integer; EleType: NEleType; MaterialId: Integer; SectionArea, Perimeter, Thickness: Double): Integer;
var

  Result1, Result2 : Integer;

begin

  Result1 := FStructuralEngine.AddElement(Nodes, NbNodes, EleType, MaterialId, SectionArea, Perimeter, Thickness);

  Result2 := FThermalEngine.AddElement(Nodes, NbNodes, EleType, MaterialId, SectionArea, Perimeter, Thickness);

  if Result1 <> Result2 then
  begin
    Result := -1;
    Exit;
  end;

  Result := Result1;

end;

function TStructuralThermalEngine.AddMaterial(DependantVarFunc: TDependantVarFunc; rho, E, poisson, Cp, k, alpha: TExpressionList): Integer;
var

  Result1, Result2 : Integer;

begin

  Result1 := FStructuralEngine.AddMaterial(DependantVarFunc, rho, E, poisson, alpha);

  Result2 := FThermalEngine.AddMaterial(DependantVarFunc, rho, Cp, k);

  if Result1 <> Result2 then
  begin
    Result := -1;
    Exit;
  end;

  Result := Result1;

end;

function TStructuralThermalEngine.AddNode(x, y, z: Double): Integer;
var

  Result1, Result2 : Integer;

begin

  Result1 := FStructuralEngine.AddNode(x, y, z);

  Result2 := FThermalEngine.AddNode(x, y, z);

  if Result1 <> Result2 then
  begin
    Result := -1;
    Exit;
  end;

  Result := Result1;

end;

procedure TStructuralThermalEngine.AddNodeSource(NodeId: Integer; DependantVarFunc: TDependantVarFunc; F: TExpressionList; DimId: NDimId; AnalysisType: NAnalysisType);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.AddNodeSource(NodeId, DependantVarFunc, F, DimId);
    atThermal: FThermalEngine.AddNodeSource(NodeId, DependantVarFunc, F);
  end;

end;

procedure TStructuralThermalEngine.BeginAddMesh;
begin

  FStructuralEngine.BeginAddMesh;

  FThermalEngine.BeginAddMesh;

end;

procedure TStructuralThermalEngine.BeginSetRestraints;
begin

  FStructuralEngine.BeginSetRestraints;

  FThermalEngine.BeginSetRestraints;

end;

procedure TStructuralThermalEngine.Calc(CalcType: NCalcType; AnalysisType : NAnalysisType; UpdateMatrix: Boolean);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.CalcDeformation(CalcType);
    atThermal: FThermalEngine.CalcTemperature(CalcType, UpdateMatrix);
    atStructuralThermal:
    begin

      case CalcType of
        caStatic: begin Fdt := 0; StaticSolve; end;
        caTransient: TransientSolve(UpdateMatrix);
      end;

    end;
  end;

end;

constructor TStructuralThermalEngine.Create;
begin

  FStructuralEngine := TStructuralEngine.Create;

  FThermalEngine := TThermalEngine.Create;

end;

destructor TStructuralThermalEngine.Destroy;
begin

  FStructuralEngine.Free;

  FThermalEngine.Free;

  inherited;
end;

procedure TStructuralThermalEngine.EndAddMesh;
begin

  FStructuralEngine.EndAddMesh;

  FThermalEngine.EndAddMesh;

end;

procedure TStructuralThermalEngine.EndSetRestraints;
begin

  FStructuralEngine.EndSetRestraints;

  FThermalEngine.EndSetRestraints;

end;

function TStructuralThermalEngine.GetDeformation(NIndex: Integer; VarId: NDimId): Double;
begin

  Result := FStructuralEngine.Deformation[NIndex, VarId];

end;

function TStructuralThermalEngine.GetElement(ElementId: Integer; AnalysisType : NAnalysisType): TElementData;
begin

  Result := nil;

  case AnalysisType of
    atStructural: Result := FStructuralEngine.Element[ElementId];
    atThermal: Result := FThermalEngine.Element[ElementId];
  end;

end;

function TStructuralThermalEngine.GetNbElements: Integer;
var

  Result1, Result2 : Integer;

begin

  Result1 := FStructuralEngine.NbElements;

  Result2 := FThermalEngine.NbElements;

  if Result1 <> Result2 then
  begin
    Result := -1;
    Exit;
  end;

  Result := Result1;

end;

function TStructuralThermalEngine.GetNbNodes: Integer;
var

  Result1, Result2 : Integer;

begin

  Result1 := FStructuralEngine.NbNodes;

  Result2 := FThermalEngine.NbNodes;

  if Result1 <> Result2 then
  begin
    Result := -1;
    Exit;
  end;

  Result := Result1;

end;

function TStructuralThermalEngine.GetNbSteps(AnalysisType: NAnalysisType): Integer;
begin

  Result := 0;

  case AnalysisType of
    atStructural: Result := FStructuralEngine.NbSteps;
    atThermal: Result := FThermalEngine.NbSteps;
    atStructuralThermal: Result := FNbSteps;
  end;

end;

function TStructuralThermalEngine.GetResult(NIndex: Integer; VarId: NDimId; AnalysisType: NAnalysisType): Double;
begin

  Result := 0;

  case AnalysisType of
    atStructural: Result := FStructuralEngine.Deformation[NIndex, Varid];
    atThermal: Result := FThermalEngine.Temperature[NIndex];
  end;

end;

function TStructuralThermalEngine.GetSolverType(AnalysisType: NAnalysisType): NSolverType;
begin

  Result := soNone;

  case AnalysisType of
    atStructural: Result := FStructuralEngine.SolverType;
    atThermal: Result := FThermalEngine.SolverType;
  end;

end;

function TStructuralThermalEngine.GetStep(AnalysisType: NAnalysisType): Integer;
begin

  Result := 0;

  case AnalysisType of
    atStructural: Result := FStructuralEngine.Step;
    atThermal: Result := FThermalEngine.Step;
    atStructuralThermal: Result := FStep;
  end;

end;

function TStructuralThermalEngine.GetStress(EIndex: Integer): RStress;
begin

  // Stress
  Result := FStructuralEngine.Stress[EIndex];

end;

function TStructuralThermalEngine.GetTemperature(NIndex: Integer): Double;
begin

  Result := FThermalEngine.Temperature[NIndex];

end;

procedure TStructuralThermalEngine.SetInitialTemperature(T: Double; AnalysisType: NAnalysisType);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.SetInitialTemperature(T);
    atThermal: FThermalEngine.SetInitialTemperature(T);
  end;

end;

procedure TStructuralThermalEngine.SetCoupled(const Value: Boolean);
begin

  FCoupled := Value;

end;

procedure TStructuralThermalEngine.SetEndPostIterationFunction(Func: TCallbackFunc; AnalysisType : NAnalysisType);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.SetEndPostIterationFunction(Func);
    atThermal: FThermalEngine.SetEndPostIterationFunction(Func);
    atStructuralThermal:
    begin
      FStructuralEngine.SetEndPostIterationFunction(Func);
      FThermalEngine.SetEndPostIterationFunction(Func);
    end;
  end;

end;

procedure TStructuralThermalEngine.SetInitialDeformation(u: Double);
begin

  FStructuralEngine.SetInitialDeformation(u);

end;

procedure TStructuralThermalEngine.SetNodeRestraint(NodeId: Integer; DependantVarFunc: TDependantVarFunc; u: TExpressionList; DimId : NDimId; AnalysisType : NAnalysisType);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.SetNodeRestraint(NodeId, DependantVarFunc, u, DimId);
    atThermal: FThermalEngine.SetNodeRestraint(NodeId, DependantVarFunc, u);
  end;

end;

procedure TStructuralThermalEngine.SetSolverType(AnalysisType: NAnalysisType; const Value: NSolverType);
begin

  case AnalysisType of
    atStructural: FStructuralEngine.SolverType := Value;
    atThermal: FThermalEngine.SolverType := Value;
    atStructuralThermal:
    begin

      FStructuralEngine.SolverType := Value;
      FThermalEngine.SolverType := Value;

    end;
  end;

end;

procedure TStructuralThermalEngine.StaticSolve;
var

  i : Integer;

begin

  FThermalEngine.CalcTemperature(caStatic, False);

  if Coupled then
  begin

    for i := 0 to FStructuralEngine.NbNodes - 1 do
    begin

      FStructuralEngine.Temperature[i] := FThermalEngine.Temperature[i];

    end;

  end;

  FStructuralEngine.CalcDeformation(caStatic);

end;

procedure TStructuralThermalEngine.TransientSolve(UpdateMatrix: Boolean);
var

  i : Integer;

  Step : Integer;

begin

  for Step := 1 to FNbSteps do
  begin

    FTime := FTime + Fdt;

    FThermalEngine.CalcTemperature(caTransient, True);

    if Coupled then
    begin

      for i := 0 to FStructuralEngine.NbNodes - 1 do
      begin

        FStructuralEngine.Temperature[i] := FThermalEngine.Temperature[i];

      end;

    end;

    FStructuralEngine.CalcDeformation(caStatic);

  end;

end;

end.
