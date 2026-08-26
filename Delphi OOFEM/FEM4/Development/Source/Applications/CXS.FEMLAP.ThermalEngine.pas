unit CXS.FEMLAP.ThermalEngine;

{$mode delphi}{$H+}

interface

uses newVM, newVMsparse, SysUtils,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.Exceptions,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element,
  CXS.FEMLAP.Edge_B2V1,
  CXS.FEMLAP.Face_T3V1,
  CXS.FEMLAP.Face_Q4V1,
  CXS.FEMLAP.Brick_T4V1,
  CXS.FEMLAP.Brick_H8V1,
  CXS.FEMLAP.Brick_W6V1,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.Penalty,
  CXS.FEMLAP.Assembly;

type TThermalEngine = class(TObject)

  private

    // Global stiffness and mass matrix
    FM : TVMSparseMtx;
    FK : TVMSparseMtx;

    // Source vectors
    Fb: TVMobj;

    // Unknown vector
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

    function GetTemperature(NodeId: Integer): Double;

    procedure SetMaterial(Element : TElement; ElementId : Integer);

    procedure SetSource(Element : TElement; ElementId : Integer);
    procedure SetConvection(Element : TElement; ElementId : Integer);
    procedure SetRadiation(Element : TElement; ElementId : Integer);

    procedure MatrixAssembly;
    procedure SetFixedTemperature;
    procedure SetNodalSources(b : TVMobj);
    procedure SetPenalty(A : TVMSparseMtx; b : TVMobj);
    procedure SolveMatrix(A : TVMSparseMtx; b : TVMobj);

    procedure StaticSolve;
    procedure NonLinearStaticSolve;
    procedure TransientSolve(UpdateMatrix : Boolean);

    function GetCoordX(NodeId: Integer): Double;
    function GetCoordY(NodeId: Integer): Double;
    function GetCoordZ(NodeId: Integer): Double;

    function GetRHS(NodeId: Integer): Double;

    function GetElement(ElementId: Integer): TElementData;

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
      Cp - [in] specific heat.
      k - [in] conductivity.
    *)
    function AddMaterial(DependantVarFunc : TDependantVarFunc; rho, Cp, k: TExpressionList) : Integer;

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
      Set initial temperature field to a specific value.
    Parameters:
      T - [in] value of the temperature.
    *)
    procedure SetInitialTemperature(T : Double); overload;

    (*
    Description:
      Set initial temperature field as a function.
    Parameters:
      DependantVarFunc - [in] function which returns the dependant variable.
      Expression - [in] expression which describes initial condition.
    *)
    procedure SetInitialTemperature(DependantVarFunc : TDependantVarFunc; Expression: TExpressionList); overload;

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
      T - [in] expression which describes temperature variation.
    *)
    procedure SetNodeRestraint(NodeId : Integer; DependantVarFunc : TDependantVarFunc; T: TExpressionList); overload;

    (*
    Description:
      Should be called after setting constraints.
    Parameters:
    *)
    procedure EndSetRestraints;

    (*
    Description:
      Set temperature heat flux on a node.
    Parameters:
      NodeId - [in] node global id.
      DependantVarFunc - [in] function which returns the dependant variable.
      Q - [in] heat flux.
    *)
    procedure AddNodeSource(NodeId : Integer; DependantVarFunc : TDependantVarFunc; Q : TExpressionList);

    (*
    Description:
      Add temperature convection on a node.
    Parameters:
      ElementId - [in] element global id.
      NIndex - [in] node local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      h - [in] expression which describes heat transfer coefficient.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddNodeConvection(ElementId : Integer; NIndex : Integer; DependantVarFunc : TDependantVarFunc; h, Tinf : TExpressionList);

    (*
    Description:
      Add temperature convection on an edge.
    Parameters:
      ElementId - [in] element global id.
      EIndex - [in] edge local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      h - [in] expression which describes heat transfer coefficient.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddEdgeConvection(ElementId : Integer; EIndex : Integer; DependantVarFunc : TDependantVarFunc; h, Tinf : TExpressionList);

    (*
    Description:
      Add temperature convection on a face.
    Parameters:
      ElementId - [in] element global id.
      FIndex - [in] face local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      h - [in] expression which describes heat transfer coefficient.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddFaceConvection(ElementId : Integer; FIndex : Integer; DependantVarFunc : TDependantVarFunc; h, Tinf : TExpressionList);

    (*
    Description:
      Add temperature radiation on a node.
    Parameters:
      ElementId - [in] element global id.
      NIndex - [in] node local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      e - [in] expression which describes emissivity.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddNodeRadiation(ElementId : Integer; NIndex : Integer; DependantVarFunc : TDependantVarFunc; e, Tinf : TExpressionList);

    (*
    Description:
      Add temperature radiation on an edge.
    Parameters:
      ElementId - [in] element global id.
      EIndex - [in] edge local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      e - [in] expression which describes emissivity.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddEdgeRadiation(ElementId : Integer; EIndex : Integer; DependantVarFunc : TDependantVarFunc; e, Tinf : TExpressionList);

    (*
    Description:
      Add temperature radiation on a node.
    Parameters:
      ElementId - [in] element global id.
      FIndex - [in] face local index.
      DependantVarFunc - [in] function which returns the dependant variable.
      e - [in] expression which describes emissivity.
      Tinf - [in] expression which describes temperature of the surrounding medium.
    *)
    procedure AddFaceRadiation(ElementId : Integer; FIndex : Integer; DependantVarFunc : TDependantVarFunc; e, Tinf : TExpressionList);

    (*
    Description:
      Return time interval.
    *)
    property TimeInterval : Double read Fdt write Fdt;

    (*
    Description:
      Calculate temperature.
    Parameters:
      CalcType - [in] solver type.
      UpdateMatrix - [in] update matrix during transient calculation.
    *)
    procedure CalcTemperature(CalcType : NCalcType; UpdateMatrix : Boolean = False);

    (*
    Description:
      Return nodal X coordinate.
    *)
    property CoordX[NIndex : Integer] : Double read GetCoordX;

    (*
    Description:
      Return nodal Y coordinate.
    *)
    property CoordY[NIndex : Integer] : Double read GetCoordY;

    (*
    Description:
      Return nodal Z coordinate.
    *)
    property CoordZ[NIndex : Integer] : Double read GetCoordZ;

    (*
    Description:
      Return temperature values.
    *)
    property Temperature[NIndex : Integer] : Double read GetTemperature;

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
    property RHS[NIndex : Integer] : Double read GetRHS;

    (*
    Description:
      Penalty method.
    *)
    property PenaltyMethod : Boolean read FPenaltyMethod write FPenaltyMethod;

    (*
    Description:
      Element.
    *)
    property Element[EIndex : Integer] : TElementData read GetElement;

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

{ TThermalEngine }

procedure TThermalEngine.BeginAddMesh;
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

procedure TThermalEngine.BeginSetRestraints;
var

  i : Integer;

begin

  SetLength(FIsFixed, FNbNodes);
  SetLength(FValues, FNbNodes);

  SetLength(FOldToNew, FNbNodes);
  SetLength(FNewToOld, FNbNodes);

  for i := 0 to FNbNodes - 1 do
  begin
    FIsFixed[i] := False;
    FValues[i] := 0;

    FOldToNew[i] := i;
    FNewToOld[i] := i;
  end;

end;

function TThermalEngine.AddElement(Nodes: array of Integer; NbNodes : Integer;
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

procedure TThermalEngine.SetConvection(Element : TElement; ElementId : Integer);
var

  i : Integer;

  h, Tinf : Double;

  Index : Integer;

  DependantVarFunc : TDependantVarFunc;

begin

  for i := 0 to FElements[ElementId].NbConvectiveBCs - 1 do
  begin

    DependantVarFunc := FElements[ElementId].ConvectiveBC[i].DependantVarFunc;

    Index := FElements[ElementId].ConvectiveBC[i].Index;

    h := FElements[ElementId].ConvectiveBC[i].h.GetValue(DependantVarFunc(-1,ElementId));
    Tinf := FElements[ElementId].ConvectiveBC[i].Tinf.GetValue(DependantVarFunc(-1,-1));

    if Element.ClassName = 'TEdge_B2V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loNode) then
        TEdge_B2V1(Element).SetSourceOnNode(Index, h, Tinf);

      if (FElements[ElementId].ConvectiveBC[i].LocType = loEdge) then
        TEdge_B2V1(Element).SetSourceOnEdge(FElements[ElementId].ConvectiveBC[i].Index, h, Tinf);

    end;

    if Element.ClassName = 'TFace_T3V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loEdge) then
        TFace_T3V1(Element).SetSourceOnEdge(FElements[ElementId].ConvectiveBC[i].Index, h, Tinf);

      if (FElements[ElementId].ConvectiveBC[i].LocType = loFace) then
        TFace_T3V1(Element).SetSourceOnFace(h, Tinf);

    end;

    if Element.ClassName = 'TFace_Q4V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loEdge) then
        TFace_Q4V1(Element).SetSourceOnEdge(FElements[ElementId].ConvectiveBC[i].Index, h, Tinf);

      if (FElements[ElementId].ConvectiveBC[i].LocType = loFace) then
        TFace_Q4V1(Element).SetSourceOnFace(h, Tinf);

    end;

    if Element.ClassName = 'TBrick_T4V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loFace) then
        TBrick_T4V1(Element).SetSourceOnFace(Index, h, Tinf);

    end;

    if Element.ClassName = 'TBrick_H8V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loFace) then
        TBrick_H8V1(Element).SetSourceOnFace(Index, h, Tinf);

    end;

    if Element.ClassName = 'TBrick_W6V1' then
    begin

      if (FElements[ElementId].ConvectiveBC[i].LocType = loFace) then
        TBrick_W6V1(Element).SetSourceOnFace(Index, h, Tinf);

    end;

  end;

end;

procedure TThermalEngine.SetEndPostIterationFunction(Func: TCallbackFunc);
begin

  FPostIterFunc := Func;

end;

procedure TThermalEngine.AddEdgeConvection(ElementId,
  EIndex: Integer; DependantVarFunc : TDependantVarFunc; h, Tinf: TExpressionList);
begin

  FElements[ElementId].AddConvection(loEdge, EIndex, DependantVarFunc, h, Tinf);

end;

procedure TThermalEngine.AddEdgeRadiation(ElementId, EIndex: Integer;
  DependantVarFunc : TDependantVarFunc; e, Tinf: TExpressionList);
begin

  FElements[ElementId].AddRadiation(loEdge, EIndex, DependantVarFunc, e, Tinf);

end;

procedure TThermalEngine.AddFaceConvection(ElementId,
  FIndex: Integer; DependantVarFunc : TDependantVarFunc; h, Tinf: TExpressionList);
begin

  FElements[ElementId].AddConvection(loFace, FIndex, DependantVarFunc, h, Tinf);

end;

procedure TThermalEngine.AddFaceRadiation(ElementId, FIndex: Integer;
  DependantVarFunc : TDependantVarFunc; e, Tinf: TExpressionList);
begin

  FElements[ElementId].AddRadiation(loFace, FIndex, DependantVarFunc, e, Tinf);

end;

function TThermalEngine.AddMaterial(DependantVarFunc : TDependantVarFunc; rho, Cp, k: TExpressionList): Integer;
begin

  SetLength(FMaterials, FNbMaterials + 1);

  FMaterials[FNbMaterials].DependantVarFunc := DependantVarFunc;

  FMaterials[FNbMaterials].rho := rho;
  FMaterials[FNbMaterials].Cp := Cp;
  FMaterials[FNbMaterials].k := k;

  Result := FNbMaterials;

  Inc(FNbMaterials);

end;

function TThermalEngine.AddNode(x, y, z : Double): Integer;
begin

  SetLength(FNodes, FNbNodes + 1);

  FNodes[FNbNodes] := TNodeData.Create;

  FNodes[FNbNodes].x := x;
  FNodes[FNbNodes].y := y;
  FNodes[FNbNodes].z := z;

  Result := FNbNodes;

  Inc(FNbNodes);

end;

procedure TThermalEngine.AddNodeConvection(ElementId,
  NIndex: Integer; DependantVarFunc : TDependantVarFunc; h, Tinf: TExpressionList);
begin

  FElements[ElementId].AddConvection(loNode, NIndex, DependantVarFunc, h, Tinf);

end;

procedure TThermalEngine.AddNodeRadiation(ElementId, NIndex: Integer;
  DependantVarFunc : TDependantVarFunc; e, Tinf: TExpressionList);
begin

  FElements[ElementId].AddRadiation(loNode, NIndex, DependantVarFunc, e, Tinf);

end;

procedure TThermalEngine.AddNodeSource(NodeId: Integer;
  DependantVarFunc: TDependantVarFunc; Q: TExpressionList);
begin

  // A hardcoded NodeId that doesn't match the mesh actually loaded (e.g.
  // left over from an earlier/larger version of the same mesh file - see
  // Ex38's own AddNodeSource(1748, ...) call against building.msh, which
  // only has 264 nodes) indexes FNodes out of bounds with no range
  // checking, and crashes with an opaque access violation deep inside
  // AddSource rather than reporting anything useful. Checking here turns
  // that into a specific, actionable message.
  if (NodeId < 0) or (NodeId >= FNbNodes) then
    raise Exception.Create('Procedure TThermalEngine.AddNodeSource : NodeId ' +
      IntToStr(NodeId) + ' is out of range - this mesh has ' + IntToStr(FNbNodes) +
      ' nodes (valid range 0..' + IntToStr(FNbNodes-1) + ').');

  FNodes[NodeId].AddSource(DependantVarFunc, Q, diX);

end;

procedure TThermalEngine.SetNodalSources(b: TVMobj);
var
  i,j : Integer;

  Q : Double;

begin

  for i := 0 to FNbNodes - 1 do
  begin

    for j := 0 to FNodes[i].NbSources - 1 do
    begin

      Q := FNodes[i].Source[j].F.GetValue(FNodes[i].Source[j].DependantVarFunc(-1, -1));

      b[FOldToNew[i],0] := b[FOldToNew[i],0] + Q;

    end;

  end;

end;

procedure TThermalEngine.SetNodeRestraint(NodeId: Integer;
  DependantVarFunc: TDependantVarFunc; T: TExpressionList);
var

  FixedTemp : RFixed;

begin

  FixedTemp.DependantVarFunc := DependantVarFunc;
  FixedTemp.u := T;

  FNodes[NodeId].Fixed[diX] := True;
  FNodes[NodeId].FixedValue := FixedTemp;

end;

procedure TThermalEngine.SetRadiation(Element : TElement; ElementId : Integer);
var

  i, j : Integer;

  Te0 : Double;

  e : Double;
  teta : Double;
  Tinf : Double;

  Index : Integer;

  DependantVarFunc : TDependantVarFunc;

begin

  for i := 0 to FElements[ElementId].NbRadiationBCs - 1 do
  begin

    DependantVarFunc := FElements[ElementId].RadiationBC[i].DependantVarFunc;

    Index := FElements[ElementId].RadiationBC[i].Index;

    Tinf := FElements[ElementId].RadiationBC[i].Tinf.GetValue(DependantVarFunc(-1,-1));

    e := FElements[ElementId].RadiationBC[i].e.GetValue(DependantVarFunc(-1,-1));

    if Element.ClassName = 'TEdge_B2V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loNode) then
      begin

        Te0 := 0;
        for j := 0 to TEdge_B2V1(Element).NbNodes - 1 do
          Te0 := Te0 + FT0[TEdge_B2V1(Element).NodeId[j],0];

        if TEdge_B2V1(Element).NbNodes > 0 then
          Te0 := Te0 / TEdge_B2V1(Element).NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TEdge_B2V1(Element).SetSourceOnNode(Index, e, teta, Tinf);

      end;

      if (FElements[ElementId].RadiationBC[i].LocType = loEdge) then
      begin

        Te0 := 0;
        for j := 0 to TEdge_B2V1(Element).NbNodes - 1 do
          Te0 := Te0 + FT0[TEdge_B2V1(Element).NodeId[j],0];

        if TEdge_B2V1(Element).NbNodes > 0 then
          Te0 := Te0 / TEdge_B2V1(Element).NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TEdge_B2V1(Element).SetSourceOnEdge(e, teta, Tinf);

      end;

    end;

    if Element.ClassName = 'TFace_T3V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loEdge) then
      begin

        Te0 := 0;
        for j := 0 to TFace_T3V1(Element).Edges[Index].NbNodes - 1 do
          Te0 := Te0 + FT0[TFace_T3V1(Element).Edges[Index].NodeId[j],0];

        if TFace_T3V1(Element).Edges[Index].NbNodes > 0 then
          Te0 := Te0 / TFace_T3V1(Element).Edges[Index].NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TFace_T3V1(Element).SetSourceOnEdge(Index, e, teta, Tinf);
      end;

      if (FElements[ElementId].RadiationBC[i].LocType = loFace) then
      begin

        Te0 := 0;
        for j := 0 to TFace_T3V1(Element).NbNodes - 1 do
          Te0 := Te0 + FT0[TFace_T3V1(Element).NodeId[j],0];

        if TFace_T3V1(Element).NbNodes > 0 then
          Te0 := Te0 / TFace_T3V1(Element).NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TFace_T3V1(Element).SetSourceOnFace(e, teta, Tinf);
      end;

    end;

    if Element.ClassName = 'TFace_Q4V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loEdge) then
      begin

        Index := FElements[ElementId].RadiationBC[i].Index;

        Te0 := 0;
        for j := 0 to TFace_Q4V1(Element).Edges[Index].NbNodes - 1 do
          Te0 := Te0 + FT0[TFace_Q4V1(Element).Edges[Index].NodeId[j],0];

        if TFace_Q4V1(Element).Edges[Index].NbNodes > 0 then
          Te0 := Te0 / TFace_Q4V1(Element).Edges[Index].NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TFace_Q4V1(Element).SetSourceOnEdge(Index, e, teta, Tinf);
      end;

      if (FElements[ElementId].RadiationBC[i].LocType = loFace) then
      begin

        Te0 := 0;
        for j := 0 to TFace_T3V1(Element).NbNodes - 1 do
          Te0 := Te0 + FT0[TFace_Q4V1(Element).NodeId[j],0];

        if TFace_T3V1(Element).NbNodes > 0 then
          Te0 := Te0 / TFace_Q4V1(Element).NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TFace_Q4V1(Element).SetSourceOnFace(e, teta, Tinf);
      end;

    end;

    if Element.ClassName = 'TBrick_T4V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loFace) then
      begin

        Te0 := 0;
        for j := 0 to TBrick_T4V1(Element).Faces[Index].NbNodes - 1 do
          Te0 := Te0 + FT0[TBrick_T4V1(Element).Faces[Index].NodeId[j],0];

        if TBrick_T4V1(Element).Faces[Index].NbNodes > 0 then
          Te0 := Te0 / TBrick_T4V1(Element).Faces[Index].NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TBrick_T4V1(Element).SetSourceOnFace(Index, e, teta, Tinf);
      end;

    end;

    if Element.ClassName = 'TBrick_H8V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loFace) then
      begin

        Te0 := 0;
        for j := 0 to TBrick_H8V1(Element).Faces[Index].NbNodes - 1 do
          Te0 := Te0 + FT0[TBrick_H8V1(Element).Faces[Index].NodeId[j],0];

        if TBrick_H8V1(Element).Faces[Index].NbNodes > 0 then
          Te0 := Te0 / TBrick_H8V1(Element).Faces[Index].NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TBrick_H8V1(Element).SetSourceOnFace(Index, e, teta, Tinf);
      end;

    end;

    if Element.ClassName = 'TBrick_W6V1' then
    begin

      if (FElements[ElementId].RadiationBC[i].LocType = loFace) then
      begin

        Te0 := 0;
        for j := 0 to TBrick_W6V1(Element).Faces[Index].NbNodes - 1 do
          Te0 := Te0 + FT0[TBrick_W6V1(Element).Faces[Index].NodeId[j],0];

        if TBrick_W6V1(Element).Faces[Index].NbNodes > 0 then
          Te0 := Te0 / TBrick_W6V1(Element).Faces[Index].NbNodes;

        teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

        TBrick_W6V1(Element).SetSourceOnFace(Index, e, teta, Tinf);
      end;

    end;

  end;

end;

procedure TThermalEngine.SetSource(Element : TElement; ElementId : Integer);
var

  i : Integer;

  DependantVarFunc : TDependantVarFunc;

begin

  for i := 0 to FElements[ElementId].NbSources - 1 do
  begin

    DependantVarFunc := FElements[ElementId].Source[i].DependantVarFunc;

    if Element.ClassName = 'TEdge_B2V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TEdge_B2V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

    if Element.ClassName = 'TFace_T3V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TFace_T3V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

    if Element.ClassName = 'TFace_Q4V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TFace_Q4V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

    if Element.ClassName = 'TBrick_T4V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TBrick_T4V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

    if Element.ClassName = 'TBrick_H8V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TBrick_H8V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

    if Element.ClassName = 'TBrick_W6V1' then
    begin

      if (FElements[ElementId].Source[i].LocType = loNode) then
      begin
        TBrick_W6V1(Element).SetSourceOnNode(FElements[ElementId].Source[i].Index, FElements[ElementId].Source[i].F.GetValue(DependantVarFunc(-1,-1)));
      end;

    end;

  end;

end;

// See CXS.FEMLAP.StructuralEngine.pas's SolveMatrix for the full solver-
// mapping rationale - identical mapping here, just writing into FT
// instead of Fu.
procedure TThermalEngine.SolveMatrix(A: TVMSparseMtx; b: TVMobj);
begin

  case FSolverType of
    soUMFPACK:
      begin
        FT := PardisoSolve(A, b, True);
      end;
    soGMRES:
      begin
        FT := FGMRESSolve(A, b);
      end;
    soPardiso:
      begin
        FT := PardisoSolve(A, b, False);
      end;
  end;

end;

procedure TThermalEngine.CalcTemperature(CalcType : NCalcType; UpdateMatrix : Boolean);
begin

  case CalcType of
    caStatic: begin Fdt := 0; StaticSolve; end;
    caStaticNonlinear: NonLinearStaticSolve;
    caTransient: TransientSolve(UpdateMatrix);
  end;

end;

constructor TThermalEngine.Create;
begin

  FNbMaterials := 0;

  FSolverType := soUMFPACK;

  FPenaltyMethod := False;

end;

destructor TThermalEngine.Destroy;
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

procedure TThermalEngine.EndAddMesh;
begin

  FT := TVMobj.Create(FNbNodes, 1);
  Fb := TVMobj.Create(FNbNodes, 1);

end;

procedure TThermalEngine.EndSetRestraints;
var

  i, n : Integer;

begin

  n := 0;

  for i := 0 to FNbNodes - 1 do
  begin

    FIsFixed[i] := FNodes[i].Fixed[diX];

    if not FPenaltyMethod then
    begin

      if not FIsFixed[i] then
      begin
        FOldToNew[i] := n;
        FNewToOld[n] := i;
        Inc(n);
      end
      else
        FOldToNew[i] := -1;

    end
    else
    begin
      FOldToNew[i] := n;
      FNewToOld[n] := i;
      Inc(n);
    end;

  end;

  FNewSize := n;

  FT := TVMobj.Create(FNewSize, 1);
  Fb := TVMobj.Create(FNewSize, 1);

end;

function TThermalEngine.GetCoordX(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].x;

end;

function TThermalEngine.GetCoordY(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].y;

end;

function TThermalEngine.GetCoordZ(NodeId: Integer): Double;
begin

  Result := FNodes[NodeId].z;

end;

function TThermalEngine.GetElement(ElementId: Integer): TElementData;
begin

  Result := FElements[ElementId];

end;

function TThermalEngine.GetRHS(NodeId: Integer): Double;
begin

  if FIsFixed[NodeId] then
    Result := FValues[NodeId]
  else
    Result := Fb[FOldToNew[NodeId],0];

end;

function TThermalEngine.GetTemperature(NodeId: Integer): Double;
begin

  if FIsFixed[NodeId] then
    Result := FValues[NodeId]
  else
    Result := FT[FOldToNew[NodeId],0];

end;

procedure TThermalEngine.SetFixedTemperature;
var

  i : Integer;

begin

  for i := 0 to FNbNodes - 1 do
  begin

    if FIsFixed[i] then
      FValues[i] := FNodes[i].FixedValue.u.GetValue(FNodes[i].FixedValue.DependantVarFunc(i,-1));

  end;

end;

procedure TThermalEngine.SetPenalty(A : TVMSparseMtx; b : TVMobj);
var

  Penalty : TPenalty;

begin

  Penalty := TPenalty.Create;

  Penalty.Impose(FIsFixed, FValues, A, b);

  Penalty.Free;

end;

procedure TThermalEngine.MatrixAssembly;
var

  Assembly : TAssembly;

  i, j : Integer;

  n : Integer;

  // Element stiffness and mass matrix
  Ke, Me : TVMobj;
  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1, V2: TDoubleArray;

  Element : TElement;

  Edge_B2V1 : TEdge_B2V1;
  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;
  Brick_W6V1 : TBrick_W6V1;

begin

  SetLength(R1, FNbElements * 64);
  SetLength(C1, FNbElements * 64);
  SetLength(V1, FNbElements * 64);
  SetLength(V2, FNbElements * 64);

  Fb := TVMobj.Create(Fb.Rows, Fb.Cols);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;
  Brick_W6V1 := TBrick_W6V1.Create;

  Assembly := TAssembly.Create;

  n := 0;

  for i := 0 to FNbElements - 1 do
  begin

    Element := nil;

    case FElements[i].EleType of
    elBeam:
    begin
      Element := Edge_B2V1;
      TEdge_B2V1(Element).SectionArea := FElements[i].SectionArea;
      TEdge_B2V1(Element).Perimeter := FElements[i].Perimeter;
    end;
    elTri:
    begin
      Element := Face_T3V1;
      TFace_T3V1(Element).Thickness := FElements[i].Thickness;
    end;
    elQuad:
    begin
      Element := Face_Q4V1;
      TFace_Q4V1(Element).Thickness := FElements[i].Thickness;
    end;
    elTetra:
    begin
      Element := Brick_T4V1;
    end;
    elHexa:
    begin
      Element := Brick_H8V1;
    end;
    elPrism:
    begin
      Element := Brick_W6V1;
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

        if Fdt > 0 then
        begin
          Element.Transient := True;
          Element.TimeInterval := Fdt;
        end;

        SetMaterial(Element, i);

        Element.Calc;

        SetSource(Element, i);
        SetConvection(Element, i);
        SetRadiation(Element, i);

        Ke := Element.K;
        Me := Element.M;

        be := Element.b;

        if FPenaltyMethod then
        begin

          // Penalty method
          if Fdt = 0 then
            Assembly.Add(Ke, be, Fb, R1, C1, V1, n, Element.NbNodes, Element.NodeIds)
          else
            Assembly.Add(Ke, Me, be, Fb, R1, C1, V1, V2, n, Element.NbNodes, Element.NodeIds);
          end

        else
        begin

          // Elmination method
          if Fdt = 0 then
            Assembly.Add(Ke, be, Fb, R1, C1, V1, n, Element.NbNodes, Element.NodeIds, FNewSize, FIsFixed, FValues, FOldToNew)
          else
            Assembly.Add(Ke, Me, be, Fb, R1, C1, V1, V2, n, Element.NbNodes, Element.NodeIds, FNewSize, FIsFixed, FValues, FOldToNew);

        end;

      finally

      end;

    end;

  end;

  Assembly.Free;

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;
  Brick_W6V1.Free;

  // A node not touched by any element (a genuinely orphaned point in the
  // mesh - real meshes from external tools can and do contain these, e.g.
  // tamega.msh, which has 46 such nodes) gets no triplet contribution at
  // all above, leaving its row structurally absent from the CSR matrix -
  // not merely zero-valued. PARDISO has no graceful way to report that:
  // it segfaults deep inside its own closed-source reordering step
  // instead of erroring (see newVMsparse.pas's PardisoSolve, which now
  // catches this earlier with a clear message - this loop is the actual
  // fix, guaranteeing every node index has a diagonal entry before that
  // check ever runs). A tiny epsilon diagonal is negligible next to any
  // real element's stiffness/mass contribution (duplicate (row,col)
  // triplets are summed by TripletsToSparse), so already-connected nodes
  // are unaffected; an orphaned node instead gets its own trivial,
  // decoupled 1x1 equation - numerically harmless, physically
  // meaningless for a point with no element, but solvable.
  SetLength(R1, n+FNewSize);
  SetLength(C1, n+FNewSize);
  SetLength(V1, n+FNewSize);
  SetLength(V2, n+FNewSize);
  for i := 0 to FNewSize - 1 do
  begin
    R1[n] := i;
    C1[n] := i;
    V1[n] := 1E-12;
    V2[n] := 1E-12;
    Inc(n);
  end;

  if n > 0 then
  begin

    if Fdt = 0 then
    begin
      FK := TripletsToSparse(FNewSize,FNewSize,R1,C1,V1);
    end
    else
    begin
      FK := TripletsToSparse(FNewSize,FNewSize,R1,C1,V1);
      FM := TripletsToSparse(FNewSize,FNewSize,R1,C1,V2);
    end;

  end;

  SetLength(R1, 0);
  SetLength(C1, 0);
  SetLength(V1, 0);
  SetLength(V2, 0);

end;

procedure TThermalEngine.NonLinearStaticSolve;
var

  Iter : Integer;
  NbIter : Integer;

  // Residual
  R : TVMobj;
  ResidualOld : Double;

  A : TVMSparseMtx;
  b, b0 : TVMobj;

begin

  try

    // Instructing UMFPACK to maintain the factorisation (A.SparsePattern
    // := sppNumeric in the original) no longer applies - PardisoSolve
    // always does a fresh one-shot analysis+factorisation+solve.

    // pseudo-time stepping
    Fdt := 0.1;
    Iter := 1;
    NbIter := 10;

    FResidual := 1E+30;

    if FNewSize > 0 then
    begin

      FTime := 0;

      while Iter < NbIter do
      begin

        if FStopExec then Break;

        FTime := FTime + Fdt;

        FT0 := CopyObj(FT);

        SetFixedTemperature;
        MatrixAssembly;
        b0 := CopyObj(Fb);

        // Matrix A
        A := SparseAdd(FM, FK);

        // Source b
        b := SparseMatMult(FM, FT0);
        b := b + b0;

        SetNodalSources(b);

        if FPenaltyMethod then
          SetPenalty(A, b);

        SolveMatrix(A, b);

        ResidualOld := FResidual;
        R := FT - FT0;
        FResidual := Norm(R);

        if FResidual < ResidualOld then
        begin
          NbIter := NbIter + 10;
        end
        else
        begin

          Fdt := Fdt * 0.1;

          if Fdt < 1E-5 then
            NbIter := NbIter - 5;

        end;

        if (FResidual < FTolerance) then Break;

      end;

    end;

    if Assigned(FPostIterFunc) then
      FPostIterFunc;

  finally

  end;

end;

procedure TThermalEngine.SetInitialTemperature(T: Double);
begin

  FT := Fill(FT, T);

end;

procedure TThermalEngine.SetInitialTemperature(DependantVarFunc : TDependantVarFunc; Expression: TExpressionList);
var

  i : Integer;

begin

  for i := 0 to FT.Rows - 1 do
  begin
    FT[i,0] := Expression.GetValue(DependantVarFunc(FNewToOld[i], -1));
  end;

end;

procedure TThermalEngine.SetMaterial(Element : TElement; ElementId: Integer);
var

  DependantVarFunc : TDependantVarFunc;

begin

  DependantVarFunc := FMaterials[FElements[ElementId].MaterialId].DependantVarFunc;

  Element.Density := FMaterials[FElements[ElementId].MaterialId].rho.GetValue(DependantVarFunc(-1, ElementId));
  Element.SpecificHeat := FMaterials[FElements[ElementId].MaterialId].Cp.GetValue(DependantVarFunc(-1, ElementId));
  Element.Conductivity := FMaterials[FElements[ElementId].MaterialId].k.GetValue(DependantVarFunc(-1, ElementId));

end;

procedure TThermalEngine.StaticSolve;
var

  A : TVMSparseMtx;
  b : TVMobj;

begin

  try

    if FNewSize > 0 then
    begin

      SetFixedTemperature;
      MatrixAssembly;

      A := FK;
      b := Fb;

      SetNodalSources(b);

      if FPenaltyMethod then
        SetPenalty(A, b);

      SolveMatrix(A, b);

    end;

    FPostIterFunc;

  finally

  end;

end;

procedure TThermalEngine.TransientSolve(UpdateMatrix : Boolean);
var

  Step : Integer;

  A : TVMSparseMtx;
  b0, b : TVMobj;

begin

  try

    // A.SparsePattern hints (sppNone/sppNumeric in the original, telling
    // UMFPACK whether to refactorise) no longer apply - PardisoSolve
    // always does a fresh one-shot solve; A itself is still only
    // recomputed when UpdateMatrix or on the first step, matching the
    // original's own reassembly gating below.

    if FNewSize > 0 then
    begin

      FTime := 0;

      for Step := 1 to FNbSteps do
      begin

        if FStopExec then Break;

        FTime := FTime + Fdt;

        FT0 := CopyObj(FT);

        if UpdateMatrix or (Step = 1) then
        begin

          SetFixedTemperature;
          MatrixAssembly;
          b0 := CopyObj(Fb);

          // Matrix A
          A := SparseAdd(FM, FK);

        end;

        // Source b
        b := SparseMatMult(FM, FT0);
        b := b + b0;

        SetNodalSources(b);

        if FPenaltyMethod then
          SetPenalty(A, b);

        SolveMatrix(A, b);

        FStep := Step;

        FPostIterFunc;

      end;

    end;

  finally

  end;

end;

end.
