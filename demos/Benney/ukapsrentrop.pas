unit ukapsrentrop;

{*******************************************************************************

     Kaps-Rentrop integration of a stiff system of first-order ODEs
     dy/dx = f(x, y), on newVM column vectors.

     A port of RemiPropModel/kaps_Rentrop.PAS (H. Dent, 1994, vectorised
     with MtxVec in 2023), itself the Numerical Recipes "stiff"/"odeint"
     pair (Press et al., Numerical Recipes in Fortran, 2nd ed., p. 732):
     a fourth-order Rosenbrock method - effectively an implicit RK45 -
     with an embedded third-order error estimate for adaptive step size.
     Each step factorises (1/(gamma h)) I - J once and solves against it
     four times, one per stage.

     MtxVec -> newVM:
       - Vector -> a (N,1) TVMobj, so a stage vector goes straight to
         LinearSolve as its right-hand side.
       - a.LUSolve(mtGeneral, L, U, indx), then a.LUSolve(g, g, ...) per
         stage -> LinearSolve(a, g): the first call factorises a in place
         and caches the pivots (a.LU becomes True), the next three reuse
         that factorisation (LAPACKE_dgetrs only) - the same
         factorise-once, back-substitute-four-times shape.
       - max(abs(err/yscal)) -> a plain loop over DataPtr.

     Changes from the original, all deliberate:
       - The original appended every accepted step to a result matrix
         (yResult, rebuilt with ConcatHorz each step - quadratic in the
         step count). Here OdeInt is called once per output interval
         instead, and the caller keeps what it wants; OnStep reports each
         accepted step, for progress and for stopping.
       - OdeInt returns the step size it would try next (HNext), so a
         run split into output intervals carries its step size across
         them rather than restarting from h1 each time.
       - OdeInt ignored Stiff's result, so a step that failed MaxTry
         times was silently accepted. It now returns that failure.
       - The global progress/Abandon variables (TInterlocked) are
         replaced by the OnStep callback's Stop flag.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, newVM;

type
  TErrFlags = (TooManySteps, TooShortStep, OK, Abandoned);

  // dy/dx at x for y (a (N,1) column): returns a new (N,1) column
  TDerivs = function(x: Double; const y: TVMobj): TVMobj of object;
  // the Jacobian dfdy = df/dy (N,N) and dfdx = df/dx (N,1) at (x, y)
  TJacobn = procedure(x: Double; const y: TVMobj; out dfdx, dfdy: TVMobj) of object;
  // after each accepted step; set Stop to abandon the integration
  TStepEvent = procedure(x: Double; var Stop: Boolean) of object;

{ One adaptive Kaps-Rentrop step from (x, y), trying htry first. On
  success y and x are advanced, dydx is f at the new point's last stage
  (as in the original - OdeInt re-evaluates it anyway), hdid is the step
  taken and hnext the one to try next. }
function Stiff(var y, dydx: TVMobj; var x: Double; htry, eps: Double;
  const yscal: TVMobj; out hdid, hnext: Double;
  Derivs: TDerivs; Jacobn: TJacobn): TErrFlags;

{ Integrates yStart from x1 to x2 to relative accuracy eps, first trying
  step h1 and never going below hmin. yStart is replaced by the solution
  at x2. HNext returns the step size to try on a following interval.
  ScaleFloor is added to every component's error scale |y| + |h dy/dx|:
  the default keeps the test relative, while a floor of the solution's
  typical size makes it absolute where y is near zero (demos/KdV, whose
  flat background would otherwise demand relative accuracy on ~0). }
function OdeInt(var yStart: TVMobj; x1, x2, eps, h1, hmin: Double;
  Derivs: TDerivs; Jacobn: TJacobn; OnStep: TStepEvent;
  out HNext: Double; ScaleFloor: Double = 1e-30): TErrFlags;

implementation

function Stiff(var y, dydx: TVMobj; var x: Double; htry, eps: Double;
  const yscal: TVMobj; out hdid, hnext: Double;
  Derivs: TDerivs; Jacobn: TJacobn): TErrFlags;
const
  Safety = 0.9; Grow = 1.5; PGrow = -0.25; Shrnk = 0.5;
  PShrnk = -1/3; ErrCon = 0.1296; MaxTry = 40;
  Gam = 0.231;
  A21 = 2; A31 = 4.52470820736; A32 = 4.16352878860;
  C21 = -5.07167533877; C31 = 6.0201572865; C32 = 0.159750684673; C41 = -1.856343618677;
  C42 = -8.50538085819; C43 = -2.08407513602;
  B1 = 3.95750374663; B2 = 4.62489238836; B3 = 0.617477263873; B4 = 1.282612945268;
  E1 = -2.30215540292; E2 = -3.07363448539; E3 = 0.873280801802; E4 = 1.282612945268;
  C1X = Gam; C2X = -0.39629667752e-01; C3X = 0.550778939579; C4X = -0.5535098457e-01;
  A2X = 0.462; A3X = 0.880208333333;
var
  n, i, jtry: Integer;
  xsav, h, d, errmax: Double;
  ysav, dysav, dfdx, dfdy, a, g1, g2, g3, g4, err: TVMobj;
  AP, JP, EP, SP: PDouble;
begin
  n := y.Rows;
  xsav := x;
  ysav := CopyObj(y);
  dysav := CopyObj(dydx);
  Jacobn(xsav, ysav, dfdx, dfdy);

  h := htry;
  for jtry := 1 to MaxTry do
  begin
    // a = (1/(gam h)) I - dfdy, built fresh each try: LinearSolve
    // factorises it in place on the first stage and caches the LU
    a := TVMobj.Create(n, n);
    AP := a.DataPtr;
    JP := dfdy.DataPtr;
    for i := 0 to n * n - 1 do AP[i] := -JP[i];
    d := 1 / (Gam * h);
    for i := 0 to n - 1 do AP[i * n + i] := AP[i * n + i] + d;

    g1 := dysav + (h * C1X) * dfdx;
    LinearSolve(a, g1);                     // factorise, then solve

    y := ysav + A21 * g1;
    x := xsav + A2X * h;
    dydx := Derivs(x, y);
    g2 := dydx + (h * C2X) * dfdx + (C21 / h) * g1;
    LinearSolve(a, g2);                     // reuses the factorisation

    y := ysav + A31 * g1 + A32 * g2;
    x := xsav + A3X * h;
    dydx := Derivs(x, y);
    g3 := dydx + (h * C3X) * dfdx + (1 / h) * (C31 * g1 + C32 * g2);
    LinearSolve(a, g3);

    g4 := dydx + (h * C4X) * dfdx + (1 / h) * (C41 * g1 + C42 * g2 + C43 * g3);
    LinearSolve(a, g4);

    y := ysav + B1 * g1 + B2 * g2 + B3 * g3 + B4 * g4;
    err := E1 * g1 + E2 * g2 + E3 * g3 + E4 * g4;
    x := xsav + h;

    EP := err.DataPtr;
    SP := yscal.DataPtr;
    errmax := 0;
    for i := 0 to n - 1 do errmax := Max(errmax, Abs(EP[i] / SP[i]));
    errmax := errmax / eps;

    if errmax <= 1 then
    begin
      hdid := h;
      if errmax > ErrCon then
        hnext := Safety * h * Power(errmax, PGrow)
      else
        hnext := Grow * h;
      Exit(OK);
    end;
    // truncation error too large: shrink the step, by at most Shrnk
    hnext := Safety * h * Power(errmax, PShrnk);
    if hnext < Shrnk * h then hnext := Shrnk * h;
    h := hnext;
  end;
  // all MaxTry attempts failed: restore the starting point
  y := ysav;
  x := xsav;
  dydx := dysav;
  hdid := 0;
  hnext := h;
  Result := TooManySteps;
end;

function OdeInt(var yStart: TVMobj; x1, x2, eps, h1, hmin: Double;
  Derivs: TDerivs; Jacobn: TJacobn; OnStep: TStepEvent;
  out HNext: Double; ScaleFloor: Double): TErrFlags;
const
  MaxStp = 1000;
var
  nstp, i: Integer;
  x, h, hdid: Double;
  dydx, yscal: TVMobj;
  YP, DP, SP: PDouble;
  Stop: Boolean;
  Flag: TErrFlags;
begin
  x := x1;
  if x2 >= x1 then h := Abs(h1) else h := -Abs(h1);
  HNext := h;
  for nstp := 1 to MaxStp do
  begin
    dydx := Derivs(x, yStart);
    // scaling for the error test: |y| + |h dy/dx|, kept off zero by ScaleFloor
    yscal := TVMobj.Create(yStart.Rows, 1);
    YP := yStart.DataPtr; DP := dydx.DataPtr; SP := yscal.DataPtr;
    for i := 0 to yStart.Rows - 1 do
      SP[i] := Abs(YP[i]) + Abs(h * DP[i]) + ScaleFloor;
    if (x + h - x2) * (x + h - x1) > 0 then h := x2 - x;   // don't overshoot x2
    Flag := Stiff(yStart, dydx, x, h, eps, yscal, hdid, HNext, Derivs, Jacobn);
    if Flag <> OK then Exit(Flag);
    Stop := False;
    if Assigned(OnStep) then OnStep(x, Stop);
    if Stop then Exit(Abandoned);
    if (x - x2) * (x2 - x1) >= 0 then Exit(OK);           // reached x2
    if Abs(HNext) < hmin then Exit(TooShortStep);
    h := HNext;
  end;
  Result := TooManySteps;
end;

end.
