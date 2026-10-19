unit ukdvmodel;

{*******************************************************************************

     The Korteweg-de Vries equation

         u_t + 6 u u_x + u_xxx = 0,      -L <= x <= L,

     on a Chebyshev grid, started from two solitons of different heights
     at the same time. A soliton of height a is

         u = a sech^2( k (x - x0 - c t) / 2 ),   k = sqrt(2 a),  c = k^2 = 2 a,

     so the taller one is faster and, started behind the shorter one,
     catches it up, passes through it and comes out with both shapes
     intact - shifted forward (taller) and back (shorter) by the
     interaction. The initial condition is the exact two-soliton solution
     (Hirota) at t = 0,

         u = 2 (ln F)_xx,  F = 1 + e1 + e2 + A e1 e2,
         ei = exp(ki (x - xi) - ki^3 t),  A = ((k1 - k2)/(k1 + k2))^2,

     which for well separated solitons is the two single solitons side by
     side, and which also gives the exact answer at every later time to
     check the integration against (Exact, ExactAt). The xi are not
     quite the crests, though: the soliton on the right sits at its xi
     - ln(A)/ki, since there the other's ej is large and A ej plays the
     part of 1. So the crest positions the form asks for go in as
     X1/X2, and the one on the right is moved back by that much for the
     formula (FXF1/FXF2) - found when the first run put the shorter
     soliton 2.2 ahead of where it was asked for. After the collision
     the faster soliton is the one on the right, so it comes out
     -ln(A)/k_fast = (2/k) ln(1/sqrt A) ahead of free motion and the
     slower one the same in its own k behind (PhaseShift).

     GRID: one low-order Chebyshev polynomial over the whole domain. The
     points are x_j = L cos(pi j/N), j = 0..N, and the boundary conditions
     are u(-L) = u(L) = u_x(L) = 0 - the third-order term needs three,
     and u_x = 0 belongs at the right-hand end, where it makes the
     dispersive energy flux d/dt int u^2/2 = -u_x(-L)^2/2 <= 0 rather than
     feeding the solution. Imposing them by replacing collocation rows
     (the usual trick) gave spurious eigenvalues with real parts of
     1e7..1e10 - the scheme blew up at once in a numpy prototype. So they
     are built into the basis instead:

         u(xi) = s(xi) q(xi),   s = (1 - xi)^2 (1 + xi),   xi = x/L,

     with q the degree N-2 polynomial through the N-1 interior points.
     Every such u meets all three conditions exactly, and the linear
     operator's eigenvalues all have negative real parts (checked to
     N = 256). The unknowns are u at the interior points, j = 1..N-1.

     BARYCENTRIC INTERPOLATION throughout. The interior points are the
     zeros of the Chebyshev polynomial U_(N-1), whose barycentric weights
     are w_j = (-1)^j sin^2(pi j/N) - no products of differences, so no
     overflow at any N. They give
       - Dq, the differentiation matrix of q on the interior points:
         Dq_ij = (w_j/w_i)/(xi_i - xi_j), the diagonal minus the row sum;
       - the derivatives of u = s q by the product rule,
           u'   = s' q + s q',
           u''' = s''' q + 3 s'' q' + 3 s' q'' + s q''',
         with q = u/s at the interior points, giving the matrices M1 and
         M3 (u at the interior -> u_x, u_xxx there), scaled by 1/L, 1/L^3;
       - the display: the same polynomial s q evaluated on a uniform grid
         by the barycentric formula (InterpMatrix), so the ribbons show
         the solution the scheme actually holds, not a re-interpolation.

     HOW LOW AN ORDER: KdV is scale invariant (u -> l^2 u(l x, l^3 t)), so
     what matters is how many soliton widths the domain spans, not the
     heights. In the prototype, with heights 2 and 0.5 on -20 .. 20 run
     through the collision to t = 5.7: N = 128 tracks the exact solution
     to 2e-3 (0.1 % of the taller soliton); N = 96 to 0.7 by the end;
     N = 64 and below fail. A larger domain needs proportionally more: N =
     384 on -40 .. 40 gives 1.7e-5.

     TIME STEPPING: Kaps-Rentrop (demos/Benney's ukapsrentrop), with the
     analytic Jacobian -6 (diag(u) M1 + diag(u_x)) - M3. M3's eigenvalues
     run to ~N^6/L^3, so an implicit method is a must. The error scale has
     a floor of the taller soliton's height (OdeInt's ScaleFloor): on the
     flat background u ~ 0, a purely relative test asks for accuracy on
     nothing.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, newVM;

type
  TKdVParams = record
    N: Integer;          // polynomial order: N+1 Chebyshev points
    L: Double;           // x runs from -L to L
    A1, A2: Double;      // soliton heights
    X1, X2: Double;      // and where their crests start
  end;

  TKdVModel = class
  private
    FP: TKdVParams;
    FK1, FK2, FLogA: Double;   // ln A, -Infinity when k1 = k2
    FXF1, FXF2: Double;        // the xi in the formula - see the header
    FX: TVMobj;                // interior points, (N-1, 1)
    FM1, FM3: TVMobj;          // u -> u_x, u -> u_xxx at the interior points
    FCalls: Integer;
    procedure BuildMatrices;
  public
    constructor Create(const AParams: TKdVParams);
    function InitialProfile: TVMobj;
    function Derivs(t: Double; const y: TVMobj): TVMobj;
    procedure Jacobn(t: Double; const y: TVMobj; out dfdx, dfdy: TVMobj);
    // the exact two-soliton solution at x, t
    function ExactAt(x, t: Double): Double;
    // ... at the interior points, (N-1, 1)
    function Exact(t: Double): TVMobj;
    // (M, N-1): u at the interior points -> u at M uniform points on
    // -L .. L, by the barycentric formula for s q
    function InterpMatrix(M: Integer): TVMobj;
    // where each soliton would be at t with no interaction, and the
    // shifts the interaction gives them
    function FreeCrest(i: Integer; t: Double): Double;
    function PhaseShift(i: Integer): Double;
    function Mass: Double;     // int u dx = 2 (k1 + k2), conserved
    property Params: TKdVParams read FP;
    property X: TVMobj read FX;
    property K1: Double read FK1;
    property K2: Double read FK2;
    property Calls: Integer read FCalls;
  end;

function DefaultKdVParams: TKdVParams;

implementation

function DefaultKdVParams: TKdVParams;
begin
  Result.N := 128;
  Result.L := 20;
  Result.A1 := 2;
  Result.A2 := 0.5;
  Result.X1 := -12;
  Result.X2 := -5;
end;

constructor TKdVModel.Create(const AParams: TKdVParams);
var
  j: Integer;
begin
  FP := AParams;
  FK1 := Sqrt(2 * FP.A1);
  FK2 := Sqrt(2 * FP.A2);
  if SameValue(FK1, FK2) then
    FLogA := NegInfinity
  else
    FLogA := 2 * Ln(Abs(FK1 - FK2) / (FK1 + FK2));
  FXF1 := FP.X1;
  FXF2 := FP.X2;
  if not IsInfinite(FLogA) then
    if FP.X2 > FP.X1 then FXF2 := FP.X2 + FLogA / FK2
    else FXF1 := FP.X1 + FLogA / FK1;
  FX := TVMobj.Create(FP.N - 1, 1);
  for j := 1 to FP.N - 1 do
    FX[j - 1, 0] := FP.L * Cos(Pi * j / FP.N);
  BuildMatrices;
end;

procedure TKdVModel.BuildMatrices;
var
  n, i, j: Integer;
  xi, w, s, s1, s2: array of Double;
  Dq, Dq2, Dq3, B: TVMobj;
  DP, D2P, D3P, BP: PDouble;
  L3: Double;
begin
  n := FP.N - 1;
  SetLength(xi, n); SetLength(w, n);
  SetLength(s, n); SetLength(s1, n); SetLength(s2, n);
  for i := 0 to n - 1 do
  begin
    xi[i] := Cos(Pi * (i + 1) / FP.N);
    w[i] := Sqr(Sin(Pi * (i + 1) / FP.N));
    if Odd(i + 1) then w[i] := -w[i];
    s[i] := Sqr(1 - xi[i]) * (1 + xi[i]);
    s1[i] := (1 - xi[i]) * (-1 - 3 * xi[i]);
    s2[i] := 6 * xi[i] - 2;           // and s''' = 6
  end;

  // barycentric differentiation matrix of q on the interior points
  Dq := TVMobj.Create(n, n);
  DP := Dq.DataPtr;
  for i := 0 to n - 1 do
  begin
    DP[i * n + i] := 0;
    for j := 0 to n - 1 do
      if j <> i then
      begin
        DP[i * n + j] := (w[j] / w[i]) / (xi[i] - xi[j]);
        DP[i * n + i] := DP[i * n + i] - DP[i * n + j];
      end;
  end;
  Dq2 := MatMult(Dq, Dq);
  Dq3 := MatMult(Dq2, Dq);
  D2P := Dq2.DataPtr;
  D3P := Dq3.DataPtr;

  // M1 = (diag(s') + diag(s) Dq) diag(1/s) / L
  FM1 := TVMobj.Create(n, n);
  BP := FM1.DataPtr;
  for i := 0 to n - 1 do
    for j := 0 to n - 1 do
    begin
      BP[i * n + j] := s[i] * DP[i * n + j];
      if i = j then BP[i * n + j] := BP[i * n + j] + s1[i];
      BP[i * n + j] := BP[i * n + j] / (s[j] * FP.L);
    end;

  // M3 = (6 I + 3 diag(s'') Dq + 3 diag(s') Dq^2 + diag(s) Dq^3) diag(1/s) / L^3
  L3 := FP.L * FP.L * FP.L;
  B := TVMobj.Create(n, n);
  BP := B.DataPtr;
  for i := 0 to n - 1 do
    for j := 0 to n - 1 do
    begin
      BP[i * n + j] := 3 * s2[i] * DP[i * n + j] + 3 * s1[i] * D2P[i * n + j]
        + s[i] * D3P[i * n + j];
      if i = j then BP[i * n + j] := BP[i * n + j] + 6;
      BP[i * n + j] := BP[i * n + j] / (s[j] * L3);
    end;
  FM3 := B;
end;

function TKdVModel.ExactAt(x, t: Double): Double;
var
  e1, e2, e12, m, F, dF1, dF2, ks: Double;
begin
  // every term divided by the largest exponential, so nothing overflows;
  // u = 2 (F F" - F'^2)/F^2 doesn't change
  e1 := FK1 * (x - FXF1) - FK1 * FK1 * FK1 * t;
  e2 := FK2 * (x - FXF2) - FK2 * FK2 * FK2 * t;
  e12 := e1 + e2 + FLogA;
  m := Max(Max(0, e1), Max(e2, e12));
  ks := FK1 + FK2;
  e1 := Exp(e1 - m);
  e2 := Exp(e2 - m);
  e12 := Exp(e12 - m);           // 0 when ln A = -Infinity
  F := Exp(-m) + e1 + e2 + e12;
  dF1 := FK1 * e1 + FK2 * e2 + ks * e12;
  dF2 := FK1 * FK1 * e1 + FK2 * FK2 * e2 + ks * ks * e12;
  Result := 2 * (F * dF2 - dF1 * dF1) / (F * F);
end;

function TKdVModel.Exact(t: Double): TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(FP.N - 1, 1);
  for i := 0 to FP.N - 2 do Result[i, 0] := ExactAt(FX[i, 0], t);
end;

function TKdVModel.InitialProfile: TVMobj;
begin
  Result := Exact(0);
end;

function TKdVModel.Derivs(t: Double; const y: TVMobj): TVMobj;
begin
  Inc(FCalls);
  Result := (-6.0) * (y * MatMult(FM1, y)) - MatMult(FM3, y);  // * is elementwise
end;

procedure TKdVModel.Jacobn(t: Double; const y: TVMobj; out dfdx, dfdy: TVMobj);
var
  n, i, j: Integer;
  ux: TVMobj;
  JP, M1P, M3P, YP, UP: PDouble;
begin
  n := FP.N - 1;
  dfdx := TVMobj.Create(n, 1);       // autonomous: zero
  ux := MatMult(FM1, y);
  dfdy := TVMobj.Create(n, n);
  JP := dfdy.DataPtr; M1P := FM1.DataPtr; M3P := FM3.DataPtr;
  YP := y.DataPtr; UP := ux.DataPtr;
  // -6 (diag(u) M1 + diag(u_x)) - M3
  for i := 0 to n - 1 do
  begin
    for j := 0 to n - 1 do
      JP[i * n + j] := -6 * YP[i] * M1P[i * n + j] - M3P[i * n + j];
    JP[i * n + i] := JP[i * n + i] - 6 * UP[i];
  end;
end;

function TKdVModel.InterpMatrix(M: Integer): TVMobj;
var
  n, r, j, hit: Integer;
  z, sz, den: Double;
  w, xi, c: array of Double;
  RP: PDouble;
begin
  n := FP.N - 1;
  SetLength(w, n); SetLength(xi, n); SetLength(c, n);
  for j := 0 to n - 1 do
  begin
    xi[j] := Cos(Pi * (j + 1) / FP.N);
    w[j] := Sqr(Sin(Pi * (j + 1) / FP.N));
    if Odd(j + 1) then w[j] := -w[j];
  end;
  Result := TVMobj.Create(M, n);     // zero-filled
  RP := Result.DataPtr;
  for r := 0 to M - 1 do
  begin
    z := -1 + 2 * r / (M - 1);
    if (r = 0) or (r = M - 1) then Continue;   // u = 0 at both ends
    sz := Sqr(1 - z) * (1 + z);
    // a display point on an interior node takes that node's value
    hit := -1;
    for j := 0 to n - 1 do
      if Abs(z - xi[j]) < 1e-14 then hit := j;
    if hit >= 0 then
    begin
      RP[r * n + hit] := 1;
      Continue;
    end;
    // q(z) = sum c_j q_j / sum c_j, c_j = w_j/(z - xi_j), q_j = u_j/s_j
    den := 0;
    for j := 0 to n - 1 do
    begin
      c[j] := w[j] / (z - xi[j]);
      den := den + c[j];
    end;
    for j := 0 to n - 1 do
      RP[r * n + j] := sz * c[j] / (den * Sqr(1 - xi[j]) * (1 + xi[j]));
  end;
end;

function TKdVModel.FreeCrest(i: Integer; t: Double): Double;
begin
  if i = 1 then Result := FP.X1 + 2 * FP.A1 * t
  else Result := FP.X2 + 2 * FP.A2 * t;
end;

function TKdVModel.PhaseShift(i: Integer): Double;
begin
  // the faster soliton moves forward, the slower back; none if equal
  if IsInfinite(FLogA) then Exit(0);
  if i = 1 then Result := -FLogA / FK1 else Result := -FLogA / FK2;
  if (FK1 > FK2) = (i = 2) then Result := -Result;
end;

function TKdVModel.Mass: Double;
begin
  Result := 2 * (FK1 + FK2);
end;

end.
