unit CXS.FEMLAP.Expression;

{$mode delphi}{$H+}

interface

uses CXS.FEMLAP.FormulaEval;

type TExpression = record

  VarStart, VarEnd : Double;
  Expression : TMtxExpression;

end;

type TExpressionList = class(TObject)

  private

    FNbVars : Integer;
    FVarName : Array of TDoubleValue;

    FNbExpressions : Integer;
    FExpressions : Array of TExpression;

    function GetVarStart(ExpIndex: Integer): Double;
    function GetVarEnd(ExpIndex: Integer): Double;
    function GetExpression(ExpIndex: Integer): String;

  public

    constructor Create; virtual;
    destructor Destroy; override;

    function AddExpression(VarStart, VarEnd : Double; Expression : String; VarName : String) : Integer;
    function GetValue(VarValue : Double) : Double;

    procedure Clear;

    property NbExpressions : Integer read FNbExpressions;

    property VarStart[ExpIndex : Integer] : Double read GetVarStart;
    property VarEnd[ExpIndex : Integer] : Double read GetVarEnd;
    property Expression[ExpIndex : Integer] : String read GetExpression;

end;

implementation

{ TExpressionList }

function TExpressionList.AddExpression(VarStart, VarEnd: Double;
  Expression: String; VarName : String) : Integer;
begin

  Result := FNbExpressions;

  SetLength(FExpressions, FNbExpressions + 1);

  FExpressions[FNbExpressions].VarStart := VarStart;
  FExpressions[FNbExpressions].VarEnd := VarEnd;

  FExpressions[FNbExpressions].Expression := TMtxExpression.Create;
  FExpressions[FNbExpressions].Expression.AddExpr(Expression);

  SetLength(FVarName, FNbVars + 1);
  FVarName[FNbVars] := FExpressions[FNbExpressions].Expression.DefineDouble(VarName);
  Inc(FNbVars);

  Inc(FNbExpressions);

end;

procedure TExpressionList.Clear;
var

  i : Integer;

begin

  for i := 0 to FNbExpressions - 1 do
  begin

    FExpressions[i].Expression.Free;

  end;

  FNbExpressions := 0;
  FNbVars := 0;

end;

constructor TExpressionList.Create;
begin

  FNbExpressions := 0;
  FNbVars := 0;

end;

destructor TExpressionList.Destroy;
var

  i : Integer;

begin

  for i := 0 to FNbExpressions - 1 do
  begin

    FExpressions[i].Expression.Free;

  end;

  inherited;
end;

function TExpressionList.GetExpression(ExpIndex: Integer): String;
begin

  Result := FExpressions[ExpIndex].Expression.Expression[0];

end;

function TExpressionList.GetValue(VarValue: Double) : Double;
var

  i : Integer;

  ExpressionId, ExpressionId1, ExpressionId2 : Integer;

  StartVal1, StartVal2 : Double;

  FunctionVal, FunctionVal1, FunctionVal2 : Double;

  m, b : Double;

begin

  // If value x is between a start/end
  // then evaluate the expression. If not then
  // evaluate two expressions and calculate x value
  // using lienar interpolation.

  Result := 0;

  for i := 0 to FNbVars - 1 do
  begin
    FVarName[i].DoubleValue := VarValue;
  end;

  ExpressionId := -1;

  for i := 0 to FNbExpressions - 1 do
  begin

    if (VarValue > FExpressions[i].VarStart) and (VarValue < FExpressions[i].VarEnd) then
    begin
      ExpressionId := i;
      Break;
    end
    else if (VarValue = FExpressions[i].VarStart) or (VarValue = FExpressions[i].VarEnd) then
    begin
      ExpressionId := i;
      Break;
    end;

  end;

  if ExpressionId <> -1 then
  begin

    // An interval has been found just evaluate expression.
    FunctionVal := FExpressions[ExpressionId].Expression.EvaluateDouble;

    Result := FunctionVal;

  end
  else
  begin

    // Find two points and do linear interpolation

    ExpressionId1 := -1;
    ExpressionId2 := -1;

    for i := 0 to FNbExpressions - 2 do
    begin

      if (VarValue >= FExpressions[i].VarStart) and (VarValue <= FExpressions[i + 1].VarStart) then
      begin
        ExpressionId1 := i;
        ExpressionId2 := i + 1;
        Break;
      end;

    end;

    if (ExpressionId1 <> -1) and (ExpressionId2 <> -1) then
    begin

      StartVal1 := FExpressions[ExpressionId1].VarStart;
      StartVal2 := FExpressions[ExpressionId2].VarStart;

      FunctionVal1 := FExpressions[ExpressionId1].Expression.EvaluateDouble;
      FunctionVal2 := FExpressions[ExpressionId2].Expression.EvaluateDouble;

      if (StartVal2 - StartVal1) <> 0 then
      begin
        m := (FunctionVal2 - FunctionVal1) / (StartVal2 - StartVal1);
        b :=  FunctionVal1 - m * StartVal1;

        FunctionVal := m * VarValue + b;

        Result := FunctionVal;

      end;

    end
    else
    begin

      // Return max or min point
      if (VarValue <= FExpressions[0].VarStart) then
      begin

        for i := 0 to FNbVars - 1 do
        begin
          FVarName[i].DoubleValue := FExpressions[0].VarStart;
        end;

        FunctionVal := FExpressions[0].Expression.EvaluateDouble;
        Result := FunctionVal;
      end;

      if (VarValue >= FExpressions[FNbExpressions - 1].VarEnd) then
      begin

        for i := 0 to FNbVars - 1 do
        begin
          FVarName[i].DoubleValue := FExpressions[FNbExpressions - 1].VarEnd;
        end;

        FunctionVal := FExpressions[FNbExpressions - 1].Expression.EvaluateDouble;
        Result := FunctionVal;
      end;

    end;

  end;

end;

function TExpressionList.GetVarEnd(ExpIndex: Integer): Double;
begin

  Result := FExpressions[ExpIndex].VarEnd;

end;

function TExpressionList.GetVarStart(ExpIndex: Integer): Double;
begin

  Result := FExpressions[ExpIndex].VarStart;

end;

end.
