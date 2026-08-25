unit CXS.FEMLAP.StructuralEngine;

{$mode delphi}{$H+}

interface

uses newVM, newVMsparse, SysUtils,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element,
  CXS.FEMLAP.Face_T3V2,
  CXS.FEMLAP.Face_Q4V2,
  CXS.FEMLAP.Penalty,
  CXS.FEMLAP.Assembly;

type TStructuralEngine = class(TObject)

  private

    // Global stiffness and mass matrix
    FK : TVMSparseMtx;

    // Source vectors
    Fb: TVMobj;

    // Unknown vector
    Fu: TVMobj;

    // Temperature
    FT0, FT: TVMobj;

    // Solver type
    FSolverType : NSolverType;

    // Materials
    FNbMaterials : Integer;
    FMaterials : TMaterialDataArray;

    // Mesh
    FNbNodes : Integer;
    FNodes : TNodeDataArray;

    FNbElements : Integer;
    FElements : TElementDataArray;

    // Self weight on/off
    FSelfWeight : Boolean;

    // Gravity
    FGravityValue : Double;
    FGravityDirection : NDimId;

    // Control
    Fdt : Double;
    FTime : Double;
    FStep, FNbSteps : Integer;

    // BC's
    FNewSize : Integer;
    FIsFixed : TBooleanArray;
    FValues : TDoubleArray;
    FOldToNew, FNewToOld : TIntegerArray;

    // Residual
    FResidual : Double;
    FTolerance : Double;

    FPenaltyMethod : Boolean;

    // Callbacks
    FPostIterFunc : TCallbackFunc;

    // Stop execution
    FStopExec : Boolean;

    function GetDeformation(NIndex: Integer; DimId : NDimId): Double;

    procedure SetMaterial(Element : TElement; ElementId : Integer);

    procedure SetSource(Element : TElement; ElementId : Integer);

    procedure MatrixAssembly;
    procedure SetFixedDeformation;
    procedure SetNodalSources(b : TVMobj);
    procedure SetPenalty(A : TVMSparseMtx; b : TVMobj);
    procedure SolveMatrix(A : TVMSparseMtx; b : TVMobj);

    procedure StaticSolve;

    function GetCoordX(NodeId: Integer): Double;
    function GetCoordY(NodeId: Integer): Double;
    function GetCoordZ(NodeId: Integer): Double;

    function GetRHS(NodeId: Integer; DimId : NDimId): Double;
    function GetElement(ElementId: Integer): TElementData;
    function GetStress(ElementId: Integer): RStress;
    function GetTemperature(NodeId: Integer): Double;
    procedure SetTemperature(NodeId: Integer; const Value: Double);

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
      Add material to a list and returns index of the material.
    Parameters:
      rho - [in] density.
      E - [in] elastic modulus.
      poisson - [in] poisson cofficient.
      alpha - [in] thermal expansion.
    *)
    function AddMaterial(DependantVarFunc : TDependantVarFunc; rho, E, poisson, alpha: TExpressionList) : Integer;

    property NbMaterials : Integer read FNbMaterials write FNbMaterials;

    property Materials : TMaterialDataArray read FMaterials write FMaterials;

    (*
    Description:
      Return number of nodes in the mesh.
    *)
    property NbNodes : Integer read FNbNodes write FNbNodes;

    property Nodes : TNodeDataArray read FNodes write FNodes;

    (*
    Description:
      Add node to mesh and returns index of the node.
    Parameters:
      x - [in] x coordinate.
      y - [in] y coordinate.
      z - [in] z coordinate.
    *)
    function AddNode(x, y, z : Double) : Integer;

    property NbElements : Integer read FNbElements write FNbElements;

    property Elements : TElementDataArray read FElements write FElements;

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
      Set initial displacement field to a specific value.
    Parameters:
      u - [in] value of the displacement.
    *)
    procedure SetInitialDeformation(u : Double); overload;

    (*
    Description:
      Set initial temperature field to a specific value.
    Parameters:
      T - [in] value of the temperature.
    *)
    procedure SetInitialTemperature(T : Double); overload;

    (*
    Description:
      Set initial displacement field as a function.
    Parameters:
      DependantVarFunc - [in] function which returns the dependant variable.
      Expression - [in] expression which describes initial condition.
    *)
    procedure SetInitialDeformation(DependantVarFunc : TDependantVarFunc; Expression: TExpressionList); overload;

    (*
    Description:
      Should be called before setting constraints.
    Parameters:
    *)
    procedure BeginSetRestraints;

    (*
    Description:
      Set displacement restraint.
    Parameters:
      NodeId - [in] node global id.
      DependantVarFunc - [in] function which returns the dependant variable.
      u - [in] expression which describes displacement variation.
      DimId - [in] which dimension.
    *)
    procedure SetNodeRestraint(NodeId : Integer; DependantVarFunc : TDependantVarFunc; u: TExpressionList; DimId : NDimId); overload;

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
      F - [in] load.
      DimId - [in] which dimension.
    *)
    procedure AddNodeSource(NodeId : Integer; DependantVarFunc : TDependantVarFunc; F : TExpressionList; DimId : NDimId);

    (*
    Description:
      Include self weight.
    *)
    property SelfWeight : Boolean read FSelfWeight write FSelfWeight;

    (*
    Description:
      Gravity value.
    *)
    property GravityValue : Double read FGravityValue write FGravityValue;

    (*
    Description:
      Gravity direction.
    *)
    property GravityDirection : NDimId read FGravityDirection write FGravityDirection;

    (*
    Description:
      Return time interval.
    *)
    property TimeInterval : Double read Fdt write Fdt;

    (*
    Description:
      Calculate deformation.
    Parameters:
      CalcType - [in] solver type.
      UpdateMatrix - [in] update matrix during transient calculation.
    *)
    procedure CalcDeformation(CalcType : NCalcType; UpdateMatrix : Boolean = False);

    (*
    Description:
      Return nodal X coordinate.
    *)
    property CoordX[NodeId : Integer] : Double read GetCoordX;

    (*
    Description:
      Return nodal Y coordinate.
    *)
    property CoordY[NodeId : Integer] : Double read GetCoordY;

    (*
    Description:
      Return nodal Z coordinate.
    *)
    property CoordZ[NodeId : Integer] : Double read GetCoordZ;

    (*
    Description:
      Return deformation values.
    *)
    property Deformation[NodeId : Integer; DimId : NDimId] : Double read GetDeformation;


    (*
    Description:
      Set nodal temperature for thermal stresses
    Parameters:
      NodeId - [in] node global id.
    *)
    property Temperature[NodeId : Integer] : Double read GetTemperature write SetTemperature;

    (*
    Description:
      Return stress values.
    *)
    property Stress[EIndex : Integer] : RStress read GetStress;

    (*
    Description:
      Non-linear solver tolerance.
    *)
    property Tolerance : Double read FTolerance write FTolerance;

    (*
    Description:
      Residual value.
    *)
    property Residual : Double read FResidual;

    (*
    Description:
      Set callback function to be called after each iteration.
    Parameters:
      Func - [in] pointer to callback function.
    *)
    procedure SetEndPostIterationFunction(Func : TCallbackFunc);

    (*
    Description:
      Step value.
    *)
    property Step : Integer read FStep;

    (*
    Description:
      Return total number of steps.
    *)
    property NbSteps : Integer read FNbSteps write FNbSteps;

    (*
    Description:
      Right hand side vactor.
    *)
    property RHS[NIndex : Integer; VarId : NDimId] : Double read GetRHS;

    (*
    Description:
      Penalty method.
    *)
    property PenaltyMethod : Boolean read FPenaltyMethod write FPenaltyMethod;

    (*
    Description:
      Element.
    *)
    property Element[ElementId : Integer] : TElementData read GetElement;

    (*
    Description:
      Current simulation time.
    *)
    property Time : Double read FTime write FTime;

    (*
    Description:
      Stop current execution.
    *)
    property StopExec : Boolean read FStopExec write FStopExec;

    (*
    Description:
      Solver type.
    *)
    property SolverType : NSolverType read FSolverType write FSolverType;

end;

implementation

{ TStructuralEngine }

procedure TStructuralEngine.BeginAddMesh;
var

  i : Integer;

begin

  for i := 0 to FNbNodes - 1 do
  begin
    FNodes[i].Free;
  end;

  for i := 0 to FNbElements - 1 do
  begin
    FElements[i].Free;
  end;

  FNbNodes := 0;
  FNbElements := 0;

end;

procedure TStructuralEngine.BeginSetRestraints;
var

  i : Integer;

begin

  SetLength(FIsFixed, FNbNodes*2);
  SetLength(FValues, FNbNodes*2);

  SetLength(FOldToNew, FNbNodes*2);
  SetLength(FNewToOld, FNbNodes*2);

  for i := 0 to FNbNodes*2 - 1 do
  begin
    FIsFixed[i] := False;
    FValues[i] := 0;

    FOldToNew[i] := i;
    FNewToOld[i] := i;
  end;

end;

function TStructuralEngine.AddElement(Nodes: array of Integer; NbNodes : Integer;
  EleType: NEleType; MaterialId : Integer; SectionArea : Double = 0; Perimeter : Double = 0; Thickness : Double = 0): Integer;
var

  j : Integer;

begin

  SetLength(FElements, FNbElements + 1);

  FElements[FNbElements] := TElementData.Create;

  FElements[FNbElements].EleType := EleType;

  FElements[FNbElements].NbNodes := NbNodes;

  for j := 0 to NbNodes - 1 do
  begin
    FElements[FNbElements].NodeId[j] := Nodes[j];

    FElements[FNbElements].CoordX[j] := FNodes[Nodes[j]].x;
    FElements[FNbElements].CoordY[j] := FNodes[Nodes[j]].y;
    FElements[FNbElements].CoordZ[j] := FNodes[Nodes[j]].z;
  end;

  FElements[FNbElements].Thickness := Thickness;
  FElements[FNbElements].SectionArea := SectionArea;
  FElements[FNbElements].Perimeter := Perimeter;

  FElements[FNbElements].MaterialId := MaterialId;

  Result := FNbElements;

  Inc(FNbElements);

end;

procedure TStructuralEngine.SetEndPostIterationFunction(Func: TCallbackFunc);
begin

  FPostIterFunc := Func;

end;

function TStructuralEngine.AddMaterial(DependantVarFunc : TDependantVarFunc; rho, E, poisson, alpha: TExpressionList): Integer;
begin

  SetLength(FMaterials, FNbMaterials + 1);

  FMaterials[FNbMaterials].DependantVarFunc := DependantVarFunc;

  FMaterials[FNbMaterials].rho := rho;
  FMaterials[FNbMaterials].E := E;
  FMaterials[FNbMaterials].poisson := poisson;
  FMaterials[FNbMaterials].alpha := alpha;

  Result := FNbMaterials;

  Inc(FNbMaterials);

end;

function TStructuralEngine.AddNode(x, y, z : Double): Integer;
begin

  SetLength(FNodes, FNbNodes + 1);

  FNodes[FNbNodes] := TNodeData.Create;

  FNodes[FNbNodes].x := x;
  FNodes[FNbNodes].y := y;
  FNodes[FNbNodes].z := z;

  Result := FNbNodes;

  Inc(FNbNodes);

end;

procedure TStructuralEngine.AddNodeSource(NodeId: Integer;
  DependantVarFunc: TDependantVarFunc; F: TExpressionList; DimId : NDimId);
begin

  FNodes[NodeId].AddSource(DependantVarFunc, F, DimId);

end;

procedure TStructuralEngine.SetNodalSources(b: TVMobj);
var
  i,j : Integer;

  F : Double;

begin

  for i := 0 to FNbNodes - 1 do
  begin

    for j := 0 to FNodes[i].NbSources - 1 do
    begin

      if FNodes[i].Source[j].DimId = diX then
      begin
        F := FNodes[i].Source[j].F.GetValue(FNodes[i].Source[j].DependantVarFunc(-1, -1));
        b[FOldToNew[2*i+Integer(diX)],0] := b[FOldToNew[2*i+Integer(diX)],0] + F;
      end
      else if FNodes[i].Source[j].DimId = diY then
      begin
        F := FNodes[i].Source[j].F.GetValue(FNodes[i].Source[j].DependantVarFunc(-1, -1));
        b[FOldToNew[2*i+Integer(diY)],0] := b[FOldToNew[2*i+Integer(diY)],0] + F;
      end;

    end;

  end;

end;

procedure TStructuralEngine.SetNodeRestraint(NodeId: Integer;
  DependantVarFunc: TDependantVarFunc; u: TExpressionList; DimId : NDimId);
var

  FixedDeform : RFixed;

begin

  FixedDeform.DependantVarFunc := DependantVarFunc;
  FixedDeform.DimId := DimId;
  FixedDeform.u := u;

  FNodes[NodeId].Fixed[DimId] := True;
  FNodes[NodeId ].FixedValue := FixedDeform;

end;

procedure TStructuralEngine.SetSource(Element : TElement; ElementId : Integer);
var

  j : Integer;

  vn : Double;

begin

  if FSelfWeight then
  begin

    case FElements[ElementId].EleType of
    elTri:
    begin

      vn := 0;

      if Element.NbNodes > 0 then
        vn := TFace_T3V2(Element).Density * TFace_T3V2(Element).Area * TFace_T3V2(Element).Thickness * FGravityValue / Element.NbNodes;

      for j := 0 to Element.NbNodes - 1 do
      begin

        TFace_T3V2(Element).SetSourceOnNode(j, vn, Integer(FGravityDirection));

      end;

    end;
    elQuad:
    begin

      vn := 0;

      if Element.NbNodes > 0 then
        vn := TFace_Q4V2(Element).Density * TFace_Q4V2(Element).Area * TFace_Q4V2(Element).Thickness * FGravityValue / Element.NbNodes;

      for j := 0 to Element.NbNodes - 1 do
      begin

        TFace_Q4V2(Element).SetSourceOnNode(j, vn, Integer(FGravityDirection));

      end;

    end;
    end;

  end;

end;

procedure TStructuralEngine.SetTemperature(NodeId: Integer; const Value: Double);
begin

  FT[NodeId,0] := Value;

end;

// Solver dispatch: soUMFPACK -> PardisoSolve direct/SPD (matches the
// original ssUmfPack+mtSymmPosDef combination), soGMRES -> FGMRESSolve
// (ILU0-preconditioned RCI iterative, matches ssIterative+itmLUGMRES),
// soPardiso -> PardisoSolve direct/general (matches ssPardiso+mtGeneral).
// See newVMsparse.pas's own header comment for the full rationale.
procedure TStructuralEngine.SolveMatrix(A: TVMSparseMtx; b: TVMobj);
begin

  case FSolverType of
    soUMFPACK:
      begin
        Fu := PardisoSolve(A, b, True);
      end;
    soGMRES:
      begin
        Fu := FGMRESSolve(A, b);
      end;
    soPardiso:
      begin
        Fu := PardisoSolve(A, b, False);
      end;
  end;

end;

procedure TStructuralEngine.CalcDeformation(CalcType : NCalcType; UpdateMatrix : Boolean);
begin

  case CalcType of
    caStatic: StaticSolve;
  end;

end;

constructor TStructuralEngine.Create;
begin

  FNbMaterials := 0;

  FSolverType := soUMFPACK;

  FPenaltyMethod := False;

  FSelfWeight := False;

  FGravityValue := 0;
  FGravityDirection := diY;

end;

destructor TStructuralEngine.Destroy;
var
  i: Integer;
begin

  for i := 0 to FNbNodes - 1 do
  begin
    FNodes[i].Free;
  end;

  for i := 0 to FNbElements - 1 do
  begin
    FElements[i].Free;
  end;

  inherited;
end;

procedure TStructuralEngine.EndAddMesh;
begin

  Fu := TVMobj.Create(FNbNodes*2, 1);
  Fb := TVMobj.Create(FNbNodes*2, 1);

  FT0 := TVMobj.Create(FNbNodes, 1);
  FT := TVMobj.Create(FNbNodes, 1);

end;

procedure TStructuralEngine.EndSetRestraints;
var

  i, n : Integer;

begin

  n := 0;

  for i := 0 to FNbNodes - 1 do
  begin

    FIsFixed[2*i + Integer(diX)] := FNodes[i].Fixed[diX];
    FIsFixed[2*i + Integer(diY)] := FNodes[i].Fixed[diY];

    if not FPenaltyMethod then
    begin

      if not FIsFixed[2*i + Integer(diX)] then
      begin
        FOldToNew[2*i + Integer(diX)] := n;
        FNewToOld[n] := i;
        Inc(n);
      end
      else
        FOldToNew[2*i + Integer(diX)] := -1;

      if not FIsFixed[2*i + Integer(diY)] then
      begin
        FOldToNew[2*i + Integer(diY)] := n;
        FNewToOld[n] := i;
        Inc(n);
      end
      else
        FOldToNew[2*i + Integer(diY)] := -1;

    end
    else
    begin

      FOldToNew[2*i + Integer(diX)] := n;
      FNewToOld[n] := i;
      Inc(n);

      FOldToNew[2*i + Integer(diY)] := n;
      FNewToOld[n] := i;
      Inc(n);

    end;

  end;

  FNewSize := n;

  Fu := TVMobj.Create(FNewSize, 1);
  Fb := TVMobj.Create(FNewSize, 1);

end;

function TStructuralEngine.GetCoordX(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].x;

end;

function TStructuralEngine.GetCoordY(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].y;

end;

function TStructuralEngine.GetCoordZ(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].z;

end;

function TStructuralEngine.GetElement(ElementId: Integer): TElementData;
begin

  Result := FElements[ElementId];

end;

function TStructuralEngine.GetRHS(NodeId: Integer; DimId : NDimId): Double;
begin

  if FIsFixed[2*NodeId+Integer(DimId)] then
    Result := FValues[2*NodeId+Integer(DimId)]
  else
    Result := Fb[FOldToNew[2*NodeId+Integer(DimId)],0];

end;

function TStructuralEngine.GetStress(ElementId: Integer): RStress;
var

  j : Integer;
  qe : TVMobj;

  D, B : TVMobj;

  Face_T3V2 : TFace_T3V2;
  Face_Q4V2 : TFace_Q4V2;

  Sigma : TVMobj;

  Element : TElement;

  epsilon, epsilon0 : TVMobj;

  dT: Double;

begin

  Face_T3V2 := TFace_T3V2.Create;
  Face_Q4V2 := TFace_Q4V2.Create;

  Element := nil;

  case FElements[ElementId].EleType of
  elTri: Element := Face_T3V2;
  elQuad: Element := Face_Q4V2;
  end;

  if Assigned(Element) then
  begin

    try

      for j := 0 to FElements[ElementId].NbNodes - 1 do
      begin
        Element.NodeId[j] := FElements[ElementId].NodeId[j];

        Element.CoordX[j] := FElements[ElementId].CoordX[j];
        Element.CoordY[j] := FElements[ElementId].CoordY[j];
        Element.CoordZ[j] := FElements[ElementId].CoordZ[j];

      end;

      Element.CalcGeoProperties;

      SetMaterial(Element, ElementId);

      Element.ReCalcD;

      case FElements[ElementId].EleType of
      elTri:
      begin

        TFace_T3V2(Element).GetStiffnessDB(D, B);

        qe := TVMobj.Create(6,1);

        qe[0,0] := Deformation[FElements[ElementId].NodeId[0], diX];
        qe[1,0] := Deformation[FElements[ElementId].NodeId[0], diY];
        qe[2,0] := Deformation[FElements[ElementId].NodeId[1], diX];
        qe[3,0] := Deformation[FElements[ElementId].NodeId[1], diY];
        qe[4,0] := Deformation[FElements[ElementId].NodeId[2], diX];
        qe[5,0] := Deformation[FElements[ElementId].NodeId[2], diY];

      end;
      elQuad:
      begin

        TFace_Q4V2(Element).GetStiffnessDB(0, 0, D, B);

        qe := TVMobj.Create(8,1);

        qe[0,0] := Deformation[FElements[ElementId].NodeId[0], diX];
        qe[1,0] := Deformation[FElements[ElementId].NodeId[0], diY];
        qe[2,0] := Deformation[FElements[ElementId].NodeId[1], diX];
        qe[3,0] := Deformation[FElements[ElementId].NodeId[1], diY];
        qe[4,0] := Deformation[FElements[ElementId].NodeId[2], diX];
        qe[5,0] := Deformation[FElements[ElementId].NodeId[2], diY];
        qe[6,0] := Deformation[FElements[ElementId].NodeId[3], diX];
        qe[7,0] := Deformation[FElements[ElementId].NodeId[3], diY];

      end;
      end;

      // Consider thermal stresses

      epsilon := MatMult(B, qe);

      dT := 0;

      for j := 0 to Element.NbNodes - 1 do
      begin
        dT := dT + FT[Element.NodeId[j],0] - FT0[Element.NodeId[j],0];
      end;

      if Element.NbNodes > 0 then
        dT := dT / Element.NbNodes;

      epsilon0 := TVMobj.Create(3,1);

      epsilon0[0,0] := Element.ThermalExpansion * dT;
      epsilon0[1,0] := Element.ThermalExpansion * dT;
      epsilon0[2,0] := 0;

      epsilon := epsilon - epsilon0;

      Sigma := MatMult(D, epsilon);

      // Sigma xx
      Result.Sxx := Sigma[0,0];

      // Sigma yy
      Result.Syy := Sigma[1,0];

      // Sigma xy
      Result.Sxy := Sigma[2,0];

      Face_T3V2.Free;
      Face_Q4V2.Free;

    finally

    end;

  end;


end;

function TStructuralEngine.GetTemperature(NodeId: Integer): Double;
begin

  Result := FT[NodeId,0];

end;

function TStructuralEngine.GetDeformation(NIndex: Integer; DimId : NDimId): Double;
begin

  if FIsFixed[2*NIndex+Integer(DimId)] then
    Result := FValues[2*NIndex+Integer(DimId)]
  else
    Result := Fu[FOldToNew[2*NIndex+Integer(DimId)],0];

end;

procedure TStructuralEngine.SetFixedDeformation;
var

  i : Integer;

begin

  for i := 0 to FNbNodes - 1 do
  begin

    if FIsFixed[2*i+Integer(diX)] then
      FValues[2*i+Integer(diX)] := FNodes[i].FixedValue.u.GetValue(FNodes[i].FixedValue.DependantVarFunc(i,-1));

    if FIsFixed[2*i+Integer(diY)] then
      FValues[2*i+Integer(diY)] := FNodes[i].FixedValue.u.GetValue(FNodes[i].FixedValue.DependantVarFunc(i,-1));

  end;

end;

procedure TStructuralEngine.SetPenalty(A : TVMSparseMtx; b : TVMobj);
var

  Penalty : TPenalty;

begin

  Penalty := TPenalty.Create;

  Penalty.Impose(FIsFixed, FValues, A, b);

  Penalty.Free;

end;

procedure TStructuralEngine.MatrixAssembly;
var

  Assembly : TAssembly;

  i, j : Integer;

  n : Integer;

  // Element stiffness and mass matrix
  Ke : TVMobj;
  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1, V2: TDoubleArray;

  Element : TElement;

  Face_T3V2 : TFace_T3V2;
  Face_Q4V2 : TFace_Q4V2;

  dT : Double;

begin

  SetLength(R1, FNbElements * 64);
  SetLength(C1, FNbElements * 64);
  SetLength(V1, FNbElements * 64);
  SetLength(V2, FNbElements * 64);

  Fb := TVMobj.Create(Fb.Rows, Fb.Cols);

  Face_T3V2 := TFace_T3V2.Create;
  Face_Q4V2 := TFace_Q4V2.Create;

  Assembly := TAssembly.Create;

  n := 0;

  for i := 0 to FNbElements - 1 do
  begin

    Element := nil;

    case FElements[i].EleType of
    elTri:
    begin
      Element := Face_T3V2;
      TFace_T3V2(Element).Thickness := FElements[i].Thickness;

    end;
    elQuad:
    begin
      Element := Face_Q4V2;
      TFace_Q4V2(Element).Thickness := FElements[i].Thickness;

    end;
    end;

    if Assigned(Element) then
    begin

      try

        for j := 0 to FElements[i].NbNodes - 1 do
        begin
          Element.NodeId[j] := FElements[i].NodeId[j];

          Element.CoordX[j] := FElements[i].CoordX[j];
          Element.CoordY[j] := FElements[i].CoordY[j];
          Element.CoordZ[j] := FElements[i].CoordZ[j];

        end;

        SetMaterial(Element, i);

        dT := 0;

        for j := 0 to Element.NbNodes - 1 do
        begin
          dT := dT + FT[Element.NodeId[j],0] - FT0[Element.NodeId[j],0];
        end;

        if Element.NbNodes > 0 then
          dT := dT / Element.NbNodes;

        case FElements[i].EleType of
        elTri: TFace_T3V2(Element).SetTemperatureLoad(dT);
        elQuad: TFace_Q4V2(Element).SetTemperatureLoad(dT);
        end;

        Element.ReCalcD;
        Element.Calc;

        SetSource(Element, i);

        Ke := Element.K;
        be := Element.b;

        if FPenaltyMethod then
        begin

          // Penalty method
          Assembly.Add(Ke, be, Fb, R1, C1, V1, n, Element.NbNodes, Element.NodeIds, 2);

        end
        else
        begin

          // Elmination method
          Assembly.Add(Ke, be, Fb, R1, C1, V1, n, Element.NbNodes, Element.NodeIds, FNewSize, FIsFixed, FValues, FOldToNew, 2);

        end;

      finally

      end;

    end;

  end;

  Assembly.Free;

  Face_T3V2.Free;
  Face_Q4V2.Free;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);
  SetLength(V2, n);

  if n > 0 then
  begin

    FK := TripletsToSparse(FNewSize,FNewSize,R1,C1,V1);

  end;

  SetLength(R1, 0);
  SetLength(C1, 0);
  SetLength(V1, 0);
  SetLength(V2, 0);

end;

procedure TStructuralEngine.SetInitialDeformation(u: Double);
begin

  Fu := Fill(Fu, u);

end;

procedure TStructuralEngine.SetInitialDeformation(DependantVarFunc : TDependantVarFunc; Expression: TExpressionList);
var

  i : Integer;

begin

  for i := 0 to Fu.Rows - 1 do
  begin
    Fu[i,0] := Expression.GetValue(DependantVarFunc(FNewToOld[i], -1));
  end;

end;

procedure TStructuralEngine.SetInitialTemperature(T: Double);
begin

  FT0 := Fill(FT0, T);

end;

procedure TStructuralEngine.SetMaterial(Element : TElement; ElementId: Integer);
var

  DependantVarFunc : TDependantVarFunc;

begin

  DependantVarFunc := FMaterials[FElements[ElementId].MaterialId].DependantVarFunc;

  Element.Density := FMaterials[FElements[ElementId].MaterialId].rho.GetValue(DependantVarFunc(-1, ElementId));
  Element.ElasticModulus := FMaterials[FElements[ElementId].MaterialId].E.GetValue(DependantVarFunc(-1, ElementId));
  Element.Poisson := FMaterials[FElements[ElementId].MaterialId].Poisson.GetValue(DependantVarFunc(-1, ElementId));
  Element.ThermalExpansion := FMaterials[FElements[ElementId].MaterialId].alpha.GetValue(DependantVarFunc(-1, ElementId));

end;

procedure TStructuralEngine.StaticSolve;
var

  A : TVMSparseMtx;
  b : TVMobj;

begin

  try

    if FNewSize > 0 then
    begin

      SetFixedDeformation;
      MatrixAssembly;

      A := FK;
      b := Fb;

      SetNodalSources(b);

      if FPenaltyMethod then
        SetPenalty(A, b);

      SolveMatrix(A, b);

    end;

    if Assigned(FPostIterFunc) then
      FPostIterFunc;

  finally

  end;

end;

end.
