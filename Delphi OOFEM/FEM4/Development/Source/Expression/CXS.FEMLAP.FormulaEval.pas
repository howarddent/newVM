unit CXS.FEMLAP.FormulaEval;

{*******************************************************************************

     Minimal in-house replacement for Dew MtxVec's bundled string-formula
     evaluator (MtxParseExpr/MtxParseClass), written for the
     Delphi_OOFEM/FEM4 port off MtxVec. Not part of newVM/newVMsparse -
     this is a scalar formula parser, not linear algebra, and is a purely
     FEM4-local concern (used by CXS.FEMLAP.Expression.pas for
     user-supplied load/BC/material formulas, and directly by
     CXS.FEMLAP.Analytical.pas for root-finding).

     Public surface deliberately mirrors TMtxExpression/TDoubleValue
     closely enough that CXS.FEMLAP.Expression.pas and
     CXS.FEMLAP.Analytical.pas need only a uses-clause change, not their
     own logic rewritten - see those two units for the actual call
     patterns this was built against (confirmed: every TMtxExpression
     instance across this whole codebase parses exactly ONE expression via
     a single AddExpr call, never several, even though the real MtxVec
     library supports multiple - Expression[0] is the only index ever
     read).

     Grammar (standard precedence; '^' right-associative and binds
     TIGHTER than unary minus, so '-2^2' = -4 not 4, matching conventional
     maths notation - unary wraps power, not the other way round, which is
     the one place this needs care):
       expression := term (('+' | '-') term)*
       term       := unary (('*' | '/') unary)*
       unary      := ('-' | '+')? power
       power      := primary ('^' unary)?
       primary    := NUMBER | IDENT | IDENT '(' expression ')' | '(' expression ')'
     Recognised functions (the set the real formulas in this codebase
     actually use): ln, exp, sqrt, abs, sin, cos.

     Implementation: a hand-rolled recursive-descent parser building an AST
     as a flat array of TExprNode (parent-owns-all-nodes-by-index, no
     per-node class/Free needed - the whole tree is freed for free when
     the owning TMtxExpression's FNodes dynamic array field is released).
     EvaluateDouble walks the tree recursively, looking up each variable's
     CURRENT TDoubleValue.DoubleValue at evaluation time (not parse time),
     so re-evaluating after changing a bound variable's value - exactly
     what CXS.FEMLAP.Expression.pas's TExpressionList.GetValue does in a
     tight loop - works correctly.

*******************************************************************************}

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  EFormulaEvalError = class(Exception);

  { TDoubleValue - a named bound-variable handle, per formula. Distinct
    class purely to match the real MtxParseClass.TDoubleValue shape
    (constructed by TMtxExpression.DefineDouble, never directly). }
  TDoubleValue = class
  private
    FName: String;
    FValue: Double;
  public
    property DoubleValue: Double read FValue write FValue;
  end;

  TNodeKind = (nkConst, nkVar, nkAdd, nkSub, nkMul, nkDiv, nkPow, nkNeg, nkFunc);
  TFuncKind = (fnNone, fnLn, fnExp, fnSqrt, fnAbs, fnSin, fnCos);

  TExprNode = record
    Kind: TNodeKind;
    ConstVal: Double;
    VarIndex: Integer;   //index into FVars, for nkVar
    Left, Right: Integer; //indices into FNodes; Right = -1 where unused (nkNeg, nkFunc, nkVar, nkConst)
    Func: TFuncKind;      //for nkFunc
  end;

  { TMtxExpression - holds exactly one parsed formula (see header comment
    for why "exactly one" is the real, confirmed usage pattern) plus its
    own private namespace of named bound variables. }
  TMtxExpression = class
  private
    FSourceText: String;          //the original string, for Expression[0]
    FNodes: array of TExprNode;
    FRoot: Integer;                //index into FNodes of the parsed expression's root; -1 if none yet
    FVarNames: array of String;
    FVarValues: array of TDoubleValue;
    //parser state, valid only during AddExpr's own call
    FParsePos: Integer;
    function AddNode(const Node: TExprNode): Integer;
    function FindOrAddVar(const AName: String): Integer;
    procedure SkipWhitespace;
    function AtEnd: Boolean;
    function PeekChar: Char;
    function ParseExpression: Integer;
    function ParseTerm: Integer;
    function ParsePower: Integer;
    function ParseUnary: Integer;
    function ParsePrimary: Integer;
    function ParseIdentifier: String;
    function ParseNumber: Double;
    function EvalNode(NodeIndex: Integer): Double;
    function GetExpression(Index: Integer): String;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddExpr(const S: String);
    function DefineDouble(const VarName: String): TDoubleValue;
    function EvaluateDouble: Double;
    property Expression[Index: Integer]: String read GetExpression;
  end;

implementation

const
  s = 'CXS.FEMLAP.FormulaEval : ';

{ TMtxExpression }

constructor TMtxExpression.Create;
begin
  inherited;
  FRoot := -1;
end;

destructor TMtxExpression.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FVarValues) do
    FVarValues[i].Free;
  inherited;
end;

function TMtxExpression.AddNode(const Node: TExprNode): Integer;
begin
  SetLength(FNodes, Length(FNodes)+1);
  FNodes[High(FNodes)] := Node;
  result := High(FNodes);
end;

function TMtxExpression.FindOrAddVar(const AName: String): Integer;
var
  i: Integer;
begin
  for i := 0 to High(FVarNames) do
    if SameText(FVarNames[i], AName) then
    begin
      result := i;
      Exit;
    end;
  SetLength(FVarNames, Length(FVarNames)+1);
  SetLength(FVarValues, Length(FVarValues)+1);
  FVarNames[High(FVarNames)] := AName;
  FVarValues[High(FVarValues)] := TDoubleValue.Create;
  FVarValues[High(FVarValues)].FName := AName;
  result := High(FVarNames);
end;

procedure TMtxExpression.SkipWhitespace;
begin
  while (not AtEnd) and (FSourceText[FParsePos] in [' ', #9, #13, #10]) do
    Inc(FParsePos);
end;

function TMtxExpression.AtEnd: Boolean;
begin
  result := FParsePos > Length(FSourceText);
end;

function TMtxExpression.PeekChar: Char;
begin
  if AtEnd then result := #0 else result := FSourceText[FParsePos];
end;

function TMtxExpression.ParseNumber: Double;
var
  startPos: Integer;
  intPart, fracPart, fracScale: Double;
begin
  //Hand-rolled rather than StrToFloat, to sidestep locale/decimal-separator
  //concerns entirely - the grammar only ever admits digits and '.', never
  //a locale-dependent thousands separator or exponent notation.
  startPos := FParsePos;
  intPart := 0;
  while (not AtEnd) and (PeekChar in ['0'..'9']) do
  begin
    intPart := intPart*10 + (Ord(PeekChar) - Ord('0'));
    Inc(FParsePos);
  end;
  fracPart := 0;
  if PeekChar = '.' then
  begin
    Inc(FParsePos);
    fracScale := 0.1;
    while (not AtEnd) and (PeekChar in ['0'..'9']) do
    begin
      fracPart := fracPart + (Ord(PeekChar) - Ord('0')) * fracScale;
      fracScale := fracScale * 0.1;
      Inc(FParsePos);
    end;
  end;
  if FParsePos = startPos then
    raise EFormulaEvalError.Create(s + 'expected a number at position ' +
      IntToStr(FParsePos) + ' in "' + FSourceText + '"');
  result := intPart + fracPart;
end;

function TMtxExpression.ParseIdentifier: String;
var
  startPos: Integer;
begin
  startPos := FParsePos;
  while (not AtEnd) and (PeekChar in ['A'..'Z','a'..'z','0'..'9','_']) do Inc(FParsePos);
  result := Copy(FSourceText, startPos, FParsePos-startPos);
  if result = '' then
    raise EFormulaEvalError.Create(s + 'expected identifier at position ' +
      IntToStr(FParsePos) + ' in "' + FSourceText + '"');
end;

function TMtxExpression.ParsePrimary: Integer;
var
  node: TExprNode;
  ident: String;
  funcKind: TFuncKind;
  argNode: Integer;
begin
  SkipWhitespace;
  if PeekChar = '(' then
  begin
    Inc(FParsePos);
    result := ParseExpression;
    SkipWhitespace;
    if PeekChar <> ')' then
      raise EFormulaEvalError.Create(s + 'expected ")" in "' + FSourceText + '"');
    Inc(FParsePos);
    Exit;
  end;
  if PeekChar in ['0'..'9'] then
  begin
    node.Kind := nkConst;
    node.ConstVal := ParseNumber;
    node.Left := -1; node.Right := -1; node.VarIndex := -1; node.Func := fnNone;
    result := AddNode(node);
    Exit;
  end;
  if PeekChar in ['A'..'Z','a'..'z','_'] then
  begin
    ident := ParseIdentifier;
    SkipWhitespace;
    if PeekChar = '(' then
    begin
      if SameText(ident, 'ln') then funcKind := fnLn
      else if SameText(ident, 'exp') then funcKind := fnExp
      else if SameText(ident, 'sqrt') then funcKind := fnSqrt
      else if SameText(ident, 'abs') then funcKind := fnAbs
      else if SameText(ident, 'sin') then funcKind := fnSin
      else if SameText(ident, 'cos') then funcKind := fnCos
      else
        raise EFormulaEvalError.Create(s + 'unknown function "' + ident + '" in "' + FSourceText + '"');
      Inc(FParsePos); //consume '('
      argNode := ParseExpression;
      SkipWhitespace;
      if PeekChar <> ')' then
        raise EFormulaEvalError.Create(s + 'expected ")" after "' + ident + '(" in "' + FSourceText + '"');
      Inc(FParsePos);
      node.Kind := nkFunc;
      node.Func := funcKind;
      node.Left := argNode; node.Right := -1; node.VarIndex := -1; node.ConstVal := 0;
      result := AddNode(node);
      Exit;
    end
    else
    begin
      node.Kind := nkVar;
      node.VarIndex := FindOrAddVar(ident);
      node.Left := -1; node.Right := -1; node.Func := fnNone; node.ConstVal := 0;
      result := AddNode(node);
      Exit;
    end;
  end;
  raise EFormulaEvalError.Create(s + 'unexpected character "' + PeekChar +
    '" at position ' + IntToStr(FParsePos) + ' in "' + FSourceText + '"');
end;

{ ParseUnary wraps ParsePower (not ParsePrimary) - unary minus must bind
  LOOSER than '^' so that "-2^2" parses as "-(2^2)" = -4, the standard
  maths convention (matching how MtxVec's own parser and Object
  Pascal/most languages read it), not "(-2)^2" = 4. ParsePower's own RHS
  recurses into ParseUnary (not ParsePower directly) so "2^-2" (a unary
  sign at the START of the exponent) also parses correctly, while still
  being right-associative for plain chains like "2^3^2" = 2^(3^2). }
function TMtxExpression.ParseUnary: Integer;
var
  node: TExprNode;
  negate: Boolean;
begin
  SkipWhitespace;
  negate := False;
  if PeekChar = '-' then begin negate := True; Inc(FParsePos); end
  else if PeekChar = '+' then Inc(FParsePos);
  result := ParsePower;
  if negate then
  begin
    node.Kind := nkNeg;
    node.Left := result; node.Right := -1; node.VarIndex := -1; node.Func := fnNone; node.ConstVal := 0;
    result := AddNode(node);
  end;
end;

function TMtxExpression.ParsePower: Integer;
var
  node: TExprNode;
  rhs: Integer;
begin
  result := ParsePrimary;
  SkipWhitespace;
  if PeekChar = '^' then
  begin
    Inc(FParsePos);
    rhs := ParseUnary; //right-associative, and allows a leading sign on the exponent
    node.Kind := nkPow;
    node.Left := result; node.Right := rhs; node.VarIndex := -1; node.Func := fnNone; node.ConstVal := 0;
    result := AddNode(node);
  end;
end;

function TMtxExpression.ParseTerm: Integer;
var
  node: TExprNode;
  op: Char;
  rhs: Integer;
begin
  result := ParseUnary;
  SkipWhitespace;
  while PeekChar in ['*','/'] do
  begin
    op := PeekChar;
    Inc(FParsePos);
    rhs := ParseUnary;
    if op = '*' then node.Kind := nkMul else node.Kind := nkDiv;
    node.Left := result; node.Right := rhs; node.VarIndex := -1; node.Func := fnNone; node.ConstVal := 0;
    result := AddNode(node);
    SkipWhitespace;
  end;
end;

function TMtxExpression.ParseExpression: Integer;
var
  node: TExprNode;
  op: Char;
  rhs: Integer;
begin
  result := ParseTerm;
  SkipWhitespace;
  while PeekChar in ['+','-'] do
  begin
    op := PeekChar;
    Inc(FParsePos);
    rhs := ParseTerm;
    if op = '+' then node.Kind := nkAdd else node.Kind := nkSub;
    node.Left := result; node.Right := rhs; node.VarIndex := -1; node.Func := fnNone; node.ConstVal := 0;
    result := AddNode(node);
    SkipWhitespace;
  end;
end;

procedure TMtxExpression.AddExpr(const S: String);
begin
  if FRoot >= 0 then
    raise EFormulaEvalError.Create(s + 'AddExpr called twice on the same TMtxExpression - only one expression per instance is supported (matches this codebase''s own usage)');
  FSourceText := S;
  FParsePos := 1;
  FRoot := ParseExpression;
  SkipWhitespace;
  if not AtEnd then
    raise EFormulaEvalError.Create(s + 'unexpected trailing text at position ' +
      IntToStr(FParsePos) + ' in "' + S + '"');
end;

function TMtxExpression.DefineDouble(const VarName: String): TDoubleValue;
begin
  result := FVarValues[FindOrAddVar(VarName)];
end;

function TMtxExpression.EvalNode(NodeIndex: Integer): Double;
var
  n: TExprNode;
  a: Double;
begin
  n := FNodes[NodeIndex];
  case n.Kind of
    nkConst: result := n.ConstVal;
    nkVar:   result := FVarValues[n.VarIndex].DoubleValue;
    nkAdd:   result := EvalNode(n.Left) + EvalNode(n.Right);
    nkSub:   result := EvalNode(n.Left) - EvalNode(n.Right);
    nkMul:   result := EvalNode(n.Left) * EvalNode(n.Right);
    nkDiv:   result := EvalNode(n.Left) / EvalNode(n.Right);
    nkPow:   result := Power(EvalNode(n.Left), EvalNode(n.Right));
    nkNeg:   result := -EvalNode(n.Left);
    nkFunc:
      begin
        a := EvalNode(n.Left);
        case n.Func of
          fnLn:   result := Ln(a);
          fnExp:  result := Exp(a);
          fnSqrt: result := Sqrt(a);
          fnAbs:  result := Abs(a);
          fnSin:  result := Sin(a);
          fnCos:  result := Cos(a);
        else
          raise EFormulaEvalError.Create(s + 'internal error: unhandled function kind');
        end;
      end;
  else
    raise EFormulaEvalError.Create(s + 'internal error: unhandled node kind');
  end;
end;

function TMtxExpression.EvaluateDouble: Double;
begin
  if FRoot < 0 then
    raise EFormulaEvalError.Create(s + 'EvaluateDouble called before AddExpr');
  result := EvalNode(FRoot);
end;

function TMtxExpression.GetExpression(Index: Integer): String;
begin
  assert(Index = 0, s + 'Expression[] only ever holds one formula (index 0)');
  result := FSourceText;
end;

end.
