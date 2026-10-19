unit uburgersmodel;

{*******************************************************************************

     The inviscid ("homogeneous") Burgers equation

         u_t + (u^2/2)_x = 0

     on a periodic domain, by a finite-volume shock-capturing scheme, with
     the exact entropy solution alongside to check it against.

     Every point of the profile moves at its own speed u, so where u
     falls with x the faster fluid behind catches the slower fluid ahead
     and the front steepens. The slope becomes infinite at the breaking
     time t* = -1 / min u0'(x) (BreakingTime); after that the solution
     carries a shock, a jump travelling at the mean of the values on
     either side (Rankine-Hugoniot), and only the entropy (Oleinik)
     solution is physical. Energy int u^2/2 is conserved until t* and
     dissipated at the shock afterwards; int u is conserved throughout.

     SCHEME: cell averages on N equal cells (no point values to ring at
     a jump, unlike the Chebyshev KdV demo):
       - reconstruction: MUSCL, a limited linear slope in each cell
         (none: first-order Godunov; minmod; or MC, the monotonised
         central limiter - the default, sharpest without oscillation);
       - flux: the exact Godunov flux for Burgers, i.e. f evaluated on
         the exact Riemann solution at the interface. For the convex
         f = u^2/2 that is F(uL, uR) = max(f(max(uL, 0)), f(min(uR, 0))):
         a shock or rarefaction, with the transonic rarefaction
         (uL < 0 < uR) giving 0, so no entropy fix is needed;
       - time: SSP-RK3 (Shu-Osher), which keeps the limiter's
         no-new-extrema property, at CFL 0.5 on max |u|;
       - periodic ghost cells, two each side.
     A shock is captured in two or three cells, and mass is conserved to
     rounding error.

     EXACT SOLUTION: the Hopf-Lax (Lax-Oleinik) formula,
         u(x, t) = (x - y*) / t,  y* = argmin_y [ U0(y) + (x - y)^2 / (2t) ],
     with U0 any antiderivative of u0. It gives the entropy solution at
     every t, shocks included, with no shock tracking: the shock is where
     the minimum jumps from one branch to the other (the equal-area
     rule). Here U0 = m y + W(y), m the mean of u0 and W the periodic
     remainder, tabulated once; the minimum is found by sampling y over
     [x - umax t, x - umin t], the range characteristics reaching x come
     from, and polished by Newton on the characteristic y + t u0(y) = x,
     so u = u0(y*) to rounding error away from the shock itself.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math;

type
  TBurgersIC = (icSine, icMovingSine, icGaussian, icNWave);
  TLimiter = (limNone, limMinmod, limMC);
  TDoubleArray = array of Double;

  TBurgersModel = class
  private
    FIC: TBurgersIC;
    FA: Double;               // amplitude
    FN: Integer;              // cells
    FXa, FXb, FP, FDx: Double;   // domain [Xa, Xb), period P, cell width
    FLimiter: TLimiter;
    FMean: Double;            // mean of u0 over a period
    FUMin, FUMax: Double;
    FW: TDoubleArray;         // W(y) = int_Xa^y (u0 - mean), tabulated
    FWh: Double;
    FSteps: Integer;
    procedure BuildTable;
    function WAt(y: Double): Double;
    function U0Anti(y: Double): Double;
    function Slope(a, b: Double): Double;
    procedure RHS(const u: TDoubleArray; var L: TDoubleArray);
  public
    constructor Create(AIC: TBurgersIC; AAmplitude: Double; ACells: Integer;
      ALimiter: TLimiter);
    function U0(x: Double): Double;
    function DU0(x: Double): Double;
    function CellCentre(i: Integer): Double;
    function InitialCells: TDoubleArray;
    // advances the cell averages from t0 to t1 exactly
    procedure AdvanceTo(var u: TDoubleArray; t0, t1: Double);
    function ExactAt(x, t: Double): Double;
    function BreakingTime(out xb: Double): Double;
    property Xa: Double read FXa;
    property Xb: Double read FXb;
    property Dx: Double read FDx;
    property Cells: Integer read FN;
    property Steps: Integer read FSteps;
    property Mean: Double read FMean;
  end;

const
  ICNames: array[TBurgersIC] of string =
    ('-a sin x', 'a (1/2 - sin x)', 'a exp(-x^2)', 'a 2x exp(-x^2)');
  CFL = 0.5;

// a sensible run time for each initial condition, at amplitude 1
function DefaultRunTime(IC: TBurgersIC): Double;

implementation

const
  TableSize = 20000;
  SearchSamples = 2000;      // per unit of the search range's length / P

function DefaultRunTime(IC: TBurgersIC): Double;
begin
  case IC of
    icSine: Result := 3;
    icMovingSine: Result := 4;
    icGaussian: Result := 8;
  else
    Result := 8;
  end;
end;

constructor TBurgersModel.Create(AIC: TBurgersIC; AAmplitude: Double;
  ACells: Integer; ALimiter: TLimiter);
begin
  FIC := AIC;
  FA := AAmplitude;
  FN := ACells;
  FLimiter := ALimiter;
  case FIC of
    icSine, icMovingSine: begin FXa := -Pi; FXb := Pi; end;
    icGaussian: begin FXa := -4; FXb := 12; end;
    icNWave: begin FXa := -8; FXb := 8; end;
  end;
  FP := FXb - FXa;
  FDx := FP / FN;
  BuildTable;
end;

function TBurgersModel.U0(x: Double): Double;
begin
  case FIC of
    icSine: Result := -FA * Sin(x);
    icMovingSine: Result := FA * (0.5 - Sin(x));
    icGaussian: Result := FA * Exp(-x * x);
  else
    Result := FA * 2 * x * Exp(-x * x);
  end;
end;

function TBurgersModel.DU0(x: Double): Double;
begin
  case FIC of
    icSine, icMovingSine: Result := -FA * Cos(x);
    icGaussian: Result := -2 * x * FA * Exp(-x * x);
  else
    Result := FA * 2 * (1 - 2 * x * x) * Exp(-x * x);
  end;
end;

function TBurgersModel.CellCentre(i: Integer): Double;
begin
  Result := FXa + (i + 0.5) * FDx;
end;

{ W(y) = int_Xa^y (u0 - mean) on a fine table (Simpson per interval), and
  the mean and range of u0. The Gaussian and N-wave domains are long
  enough that u0 is below 1e-7 at their ends, so their periodic
  extensions are smooth to plotting accuracy. }
procedure TBurgersModel.BuildTable;
var
  i: Integer;
  y, v, s: Double;
  cum: TDoubleArray;
begin
  FWh := FP / TableSize;
  SetLength(cum, TableSize + 1);
  cum[0] := 0;
  FUMin := U0(FXa); FUMax := FUMin;
  for i := 1 to TableSize do
  begin
    y := FXa + (i - 1) * FWh;
    s := (U0(y) + 4 * U0(y + FWh / 2) + U0(y + FWh)) * FWh / 6;
    cum[i] := cum[i - 1] + s;
    v := U0(y + FWh);
    FUMin := Min(FUMin, v);
    FUMax := Max(FUMax, v);
  end;
  FMean := cum[TableSize] / FP;
  SetLength(FW, TableSize + 1);
  for i := 0 to TableSize do FW[i] := cum[i] - FMean * i * FWh;
end;

function TBurgersModel.WAt(y: Double): Double;
var
  r: Double;
  i: Integer;
begin
  r := (y - FXa) - FP * Floor((y - FXa) / FP);     // into [0, P)
  i := Trunc(r / FWh);
  if i >= TableSize then i := TableSize - 1;
  r := r / FWh - i;
  Result := FW[i] + r * (FW[i + 1] - FW[i]);
end;

function TBurgersModel.U0Anti(y: Double): Double;
begin
  Result := FMean * (y - FXa) + WAt(y);
end;

function TBurgersModel.ExactAt(x, t: Double): Double;
var
  y, yBest, g, gBest, h, lo, hi, gy, dg: Double;
  i, n, it: Integer;
begin
  if t <= 0 then Exit(U0(x));
  // characteristics reaching x left from [x - umax t, x - umin t]
  lo := x - FUMax * t;
  hi := x - FUMin * t;
  n := Max(16, Round(SearchSamples * (hi - lo) / FP));
  h := (hi - lo) / n;
  yBest := lo; gBest := Infinity;
  for i := 0 to n do
  begin
    y := lo + i * h;
    g := U0Anti(y) + Sqr(x - y) / (2 * t);
    if g < gBest then begin gBest := g; yBest := y; end;
  end;
  // polish on the characteristic y + t u0(y) = x, kept within a sample
  lo := yBest - h; hi := yBest + h;
  y := yBest;
  for it := 1 to 30 do
  begin
    gy := y + t * U0(y) - x;
    dg := 1 + t * DU0(y);
    if dg <= 0 then Break;
    h := gy / dg;
    y := y - h;
    if (y < lo) or (y > hi) then begin y := EnsureRange(y, lo, hi); Break; end;
    if Abs(h) < 1e-14 * (1 + Abs(y)) then Break;
  end;
  Result := U0(y);
end;

function TBurgersModel.BreakingTime(out xb: Double): Double;
var
  i: Integer;
  x, d, dmin: Double;
begin
  dmin := 0; xb := NaN;
  for i := 0 to TableSize - 1 do
  begin
    x := FXa + i * FWh;
    d := DU0(x);
    if d < dmin then begin dmin := d; xb := x; end;
  end;
  if dmin < 0 then
  begin
    Result := -1 / dmin;
    // the first shock appears where that characteristic has got to
    xb := xb + U0(xb) * Result;
    xb := FXa + (xb - FXa) - FP * Floor((xb - FXa) / FP);
  end
  else
    Result := Infinity;
end;

function TBurgersModel.InitialCells: TDoubleArray;
var
  i: Integer;
  x: Double;
begin
  // cell averages by 3-point Gauss-Legendre
  SetLength(Result, FN);
  for i := 0 to FN - 1 do
  begin
    x := CellCentre(i);
    Result[i] := (5 * U0(x - Sqrt(0.6) * FDx / 2) + 8 * U0(x)
      + 5 * U0(x + Sqrt(0.6) * FDx / 2)) / 18;
  end;
end;

function TBurgersModel.Slope(a, b: Double): Double;
begin
  // a, b the backward and forward differences
  case FLimiter of
    limNone: Result := 0;
    limMinmod:
      if a * b <= 0 then Result := 0
      else if Abs(a) < Abs(b) then Result := a
      else Result := b;
  else
    // MC: minmod(2a, (a+b)/2, 2b)
    if a * b <= 0 then Result := 0
    else Result := Sign(a) * Min(Min(2 * Abs(a), 2 * Abs(b)), 0.5 * Abs(a + b));
  end;
end;

{ L = -(F(i+1/2) - F(i-1/2))/dx for the cell averages u }
procedure TBurgersModel.RHS(const u: TDoubleArray; var L: TDoubleArray);
var
  i, n: Integer;
  g, s, F: TDoubleArray;    // u with two ghost cells each side, slopes, fluxes
  uL, uR, a, b: Double;
begin
  n := FN;
  SetLength(g, n + 4);
  for i := 0 to n - 1 do g[i + 2] := u[i];
  g[0] := u[n - 2]; g[1] := u[n - 1];
  g[n + 2] := u[0]; g[n + 3] := u[1];
  SetLength(s, n + 4);
  for i := 1 to n + 2 do s[i] := Slope(g[i] - g[i - 1], g[i + 1] - g[i]);
  // F[i] at the interface between g[i+1] and g[i+2], i.e. cells i-1 and i
  SetLength(F, n + 1);
  for i := 0 to n do
  begin
    uL := g[i + 1] + 0.5 * s[i + 1];
    uR := g[i + 2] - 0.5 * s[i + 2];
    a := Max(uL, 0);
    b := Min(uR, 0);
    F[i] := Max(0.5 * a * a, 0.5 * b * b);
  end;
  for i := 0 to n - 1 do L[i] := -(F[i + 1] - F[i]) / FDx;
end;

procedure TBurgersModel.AdvanceTo(var u: TDoubleArray; t0, t1: Double);
var
  t, dt, umax: Double;
  i, n: Integer;
  L, u1, u2: TDoubleArray;
begin
  n := FN;
  SetLength(L, n); SetLength(u1, n); SetLength(u2, n);
  t := t0;
  while t < t1 - 1e-12 * Max(1, Abs(t1)) do
  begin
    umax := 0;
    for i := 0 to n - 1 do umax := Max(umax, Abs(u[i]));
    dt := CFL * FDx / Max(umax, 1e-12);
    if t + dt > t1 then dt := t1 - t;
    // SSP-RK3 (Shu-Osher)
    RHS(u, L);
    for i := 0 to n - 1 do u1[i] := u[i] + dt * L[i];
    RHS(u1, L);
    for i := 0 to n - 1 do u2[i] := 0.75 * u[i] + 0.25 * (u1[i] + dt * L[i]);
    RHS(u2, L);
    for i := 0 to n - 1 do u[i] := u[i] / 3 + 2 / 3 * (u2[i] + dt * L[i]);
    t := t + dt;
    Inc(FSteps);
  end;
end;

end.
