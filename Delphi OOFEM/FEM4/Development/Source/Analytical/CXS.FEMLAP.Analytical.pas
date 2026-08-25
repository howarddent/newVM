unit CXS.FEMLAP.Analytical;

{$mode delphi}{$H+}

interface

uses Math, CXS.FEMLAP.FormulaEval;

type TAnalytical = class(TObject)

  private

    function EvaluateFunction(f : TMtxExpression; x : TDoubleValue; Val : Double) : Double;
    function Bisection(f : TMtxExpression; x : TDoubleValue; LowerBnd, UpperBnd : Double; Tol : Double) : Double;
    function CalculateRoot(f : TMtxExpression; x : TDoubleValue; LowerBnd, UpperBnd : Double; Tol : Double) : Double;

  public

    procedure SteadyStateHeatConduction1D(x : Double; var Temp : Double); overload;
    procedure SteadyStateHeatConduction2D(x, y : Double; var Temp : Double); overload;
    procedure SteadyStateHeatConduction3D(x, y, z : Double; var Temp : Double); overload;

    procedure SteadyStateHeatConduction1D(x : Double; T1, T2 : Double; h, Tinf, k, Perimeter, SectionArea, Length : Double; var Temp : Double); overload;
    procedure SteadyStateHeatConvectionRadiation1D(x : Double; Tb : Double; h, e, k : Double; Perimeter : Double; SectionArea : Double; var Temp : Double); overload;

    procedure TransientHeatConduction1D(x, t, alpha: Double; var Temp : Double); overload;
    procedure TransientHeatConduction2D(x, y, t, alpha: Double; var Temp : Double); overload;
    procedure TransientHeatConduction3D(x, y, z, t, alpha: Double; var Temp : Double); overload;

end;

implementation

{ TAnalytical }


function TAnalytical.Bisection(f: TMtxExpression; x: TDoubleValue; LowerBnd,
  UpperBnd, Tol: Double): Double;
var

  MidPoint : Double;

begin

 //Start loop
 while (Abs(UpperBnd - LowerBnd) > Tol) do
 begin

   //Calculate midpoint of domain
   MidPoint := (UpperBnd + LowerBnd) * 0.5;

   //Find f(midpoint)
   if (EvaluateFunction(f, x, LowerBnd) * EvaluateFunction(f, x, MidPoint) > 0) then
     //Throw away left half
     LowerBnd := MidPoint
   else
     //Throw away right half
     UpperBnd := MidPoint;

 end;

 Result := (UpperBnd + LowerBnd) * 0.5;

end;

function TAnalytical.CalculateRoot(f: TMtxExpression; x : TDoubleValue; LowerBnd,
  UpperBnd: Double; Tol : Double): Double;
begin

  Result := Bisection(f, x, LowerBnd, UpperBnd, Tol);

end;

procedure TAnalytical.SteadyStateHeatConduction1D(x : Double; var Temp: Double);
begin

  // Beam of length = 1
  // Ta and Tb = 1,0
  Temp := x;

end;

function TAnalytical.EvaluateFunction(f: TMtxExpression; x: TDoubleValue; Val : Double): Double;
begin

  x.DoubleValue := Val;
  Result := f.EvaluateDouble;

end;

procedure TAnalytical.SteadyStateHeatConduction1D(x : Double; T1, T2 : Double; h, Tinf, k, Perimeter, SectionArea, Length: Double;
  var Temp : Double);
var

  m : Double;

  c1, c2 : Double;

begin

  m := sqrt(h*Perimeter/(k*SectionArea));

  c1 := -(exp(m*Length)*T2-exp(2*m*Length)*T1+Tinf*exp(2*m*Length)-Tinf*exp(m*Length))/(exp(2*m*Length)-1);
  c2 := (T1 - Tinf) - c1;

  Temp := Tinf + c1 * exp(-m*x) + c2 * exp(m*x);

end;

procedure TAnalytical.SteadyStateHeatConduction2D(x, y : Double; var Temp: Double);
var

  p: Integer;

  Tp : Double;

  sum : Double;

begin

  // Source: Myers, G. (1971). Analytical methods in conduction heat transfer. Mc-Graw Hill.

  sum := 0;

  for p := 0 to 100 do
  begin

    Tp := sin((2*p+1)*PI*x)*sinh((2*p+1)*PI*y) / ((2*p+1)*sinh((2*p+1)*PI));

    sum := sum + Tp;

  end;

  Temp := 4 / PI * sum;

end;

procedure TAnalytical.SteadyStateHeatConduction3D(x, y, z: Double;
  var Temp: Double);
var

  p, q: Integer;

  lambda : Double;

  Tpq : Double;

  sum : Double;

begin

  // Source: Carslaw, H. and Jaeger, J. (1959). Conduction of heat in solids. Oxford Clarendon Press.

  sum := 0;

  for p := 0 to 100 do
  begin

    for q := 0 to 100 do
    begin

      lambda := sqrt((2*p + 1)*(2*p + 1)*PI*PI + (2*q + 1)*(2*q + 1)*PI*PI);

      Tpq := (0.5 * sinh(lambda*(1-x)) + sinh(lambda*x)) * sin((2*p + 1)*PI*y)*sin((2*q + 1)*PI*z)/((2*p + 1)*(2*q + 1))*sinh(lambda);

      sum := sum + Tpq;

    end;

  end;

  Temp := 16 / (PI * PI) * sum;

end;

procedure TAnalytical.SteadyStateHeatConvectionRadiation1D(x, Tb, h, e, k,
  Perimeter, SectionArea: Double; var Temp : Double);
var

  G, M : TDoubleValue;
  Tb1 : TDoubleValue;
  x1 : TDoubleValue;
  T : TDoubleValue;

  f : TMtxExpression;

const
  // Stefan-boltzmann constant
  sigma = 5.6704E-8;

begin

  // Tinf = 0

  f := TMtxExpression.Create;

  f.AddExpr('1/3*M^(-1/2)*(ln(((G*Tb^3+M)^(1/2)-M^(1/2))/((G*Tb^3+M)^(1/2)+M^(1/2)))-ln(((G*T^3+M)^(1/2)-M^(1/2))/((G*T^3+M)^(1/2)+M^(1/2))))-x');

  G := f.DefineDouble('G');
  M := f.DefineDouble('M');
  x1 := f.DefineDouble('x');
  Tb1 := f.DefineDouble('Tb');

  T := f.DefineDouble('T');

  G.DoubleValue := 2/3*Perimeter*e*sigma/(k*SectionArea);
  M.DoubleValue := h*Perimeter/(k*SectionArea);
  x1.DoubleValue := x;
  Tb1.DoubleValue := Tb;

  Temp := CalculateRoot(f, T, 1E-12, Tb, 1E-12);

  f.Free;

end;

procedure TAnalytical.TransientHeatConduction1D(x, t, alpha: Double; var Temp : Double);
var

  p: Integer;

  lambda : Double;

  Tp : Double;

  sum : Double;

begin

  sum := 0;

  for p := 1 to 100 do
  begin

    lambda := (2*p-1)*PI * 0.5;

    Tp := power(-1, p + 1) / (2 * p - 1) * exp(-alpha * lambda * lambda * t) * cos(lambda*x);

    sum := sum + Tp;

  end;

  Temp := 4 / PI * sum;

end;

procedure TAnalytical.TransientHeatConduction2D(x, y, t, alpha: Double;
  var Temp: Double);
var

  p, q: Integer;

  lambda, phi : Double;

  Tpq : Double;

  sum : Double;

begin

  sum := 0;

  for p := 0 to 50 do
  begin

    for q := 0 to 50 do
    begin

      lambda := alpha * PI * PI * ((2*p + 1)*(2*p + 1) + (2*q+1)*(2*q+1));

      phi := cos((2*p + 1)*PI*x)*cos((2*q + 1)*PI*y);

      Tpq := power(-1, p + q) / ((2*p + 1)*(2*q + 1)) * phi * exp(-lambda*t);

      sum := sum + Tpq;

    end;

  end;

  Temp := 16 / (PI * PI) * sum;

end;

procedure TAnalytical.TransientHeatConduction3D(x, y, z, t, alpha: Double; var Temp: Double);
begin

end;

end.
