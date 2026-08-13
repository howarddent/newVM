unit uCheb;

{*******************************************************************************

     Ported from the Delphi/MtxVec original at
     demos/Chebyshev/Normal_Integration/uMain.pas (TCheb, BaryInterPol) -
     recoded onto newVM's TVMobj in place of MtxVec's Vector/Matrix.

     TCheb builds the (N+1)x(N+1) Chebyshev differentiation matrix D (and
     D2 = D*D, the second-derivative matrix - computed for parity with the
     original, not used by the demo) over the N+1 Chebyshev points
     x_i = cos(i*pi/N), i = 0..N - the standard construction from
     Trefethen's "Spectral Methods in MATLAB" (cheb.m). D is singular (up
     to an additive constant - constant functions have zero derivative);
     TCheb.Integrate solves D*Result = F via LinearSolve anyway, same as
     the original's direct LUSolve call on the singular matrix - in
     floating point the factorisation lands on some particular, if
     arbitrarily offset, solution rather than failing outright, and the
     caller removes the arbitrary constant afterwards (see uNormMain.pas).

     BaryInterPol reimplements the original's barycentric-interpolation
     routine as a plain nested loop over TVMobj elements rather than
     MtxVec's vectorised expressions (xdiff:=gridx-x[i]; findmask; etc) -
     no BLAS/IPP primitive does barycentric interpolation directly, same
     rationale as this codebase's own Find/Gather/Trace. One deliberate
     behavioural difference from the original: where a grid point exactly
     matches an interpolation node, the original relies on that term's
     division producing IEEE Infinity (c[i]/0), which then makes the
     numerator/denominator ratio evaluate to NaN and gets patched up
     afterwards via an index array; here the zero-difference term is
     detected and skipped explicitly instead, and the exact node value is
     substituted directly - equivalent result, without leaning on
     IEEE Inf/NaN propagation (or an FPU trap firing on the 0/0, depending
     on the platform's floating-point exception mask).

     TCheb.CurtisClenshaw fills in the original's empty `curtis_clenshaw`
     stub ("integrate function defined at chebyshev points, spectral
     methods P128") - Clenshaw-Curtis quadrature of a function sampled at
     the same N+1 Chebyshev points as X/D, via the direct O(N^2) weight
     construction from Trefethen's `clencurt.m` (the same "Spectral
     Methods in MATLAB" the original comment cites - p128 is exactly the
     clencurt.m listing). This is a second, independent way to get a
     definite integral out of a Chebyshev series, deliberately distinct
     from TCheb.Integrate: Integrate solves D*y=f for the whole
     antiderivative *function* (up to an arbitrary constant, fixed up by
     the caller), whereas CurtisClenshaw's weights dot straight into a
     single definite-integral *number* over [-1,1] - typically far more
     accurate for a smooth F than differencing two values pulled off
     Integrate's antiderivative, since it avoids that arbitrary-constant
     removal step and the D matrix's near-singularity entirely. The
     weights depend only on N (not on any particular F), so they're built
     once in the constructor (BuildWeights) and cached alongside X/D/D2.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  newVM;

type
  { TCheb }
  TCheb = class
  private
    FX: TVMobj;
    FD: TVMobj;
    FD2: TVMobj;
    FW: TVMobj;   // Clenshaw-Curtis quadrature weights, over the same N+1 points as FX
    FSize: Integer;
    procedure BuildWeights(N: Integer);
  public
    constructor Create(N: Integer);
    function Integrate(const F: TVMobj): TVMobj;
    // Clenshaw-Curtis quadrature: returns the definite integral over
    // [-1,1] of the function sampled as F at the Chebyshev points (F must
    // have Size+1 elements, row or column shaped).
    function CurtisClenshaw(const F: TVMobj): Double;
    property X: TVMobj read FX;
    property D: TVMobj read FD;
    property D2: TVMobj read FD2;
    property Weights: TVMobj read FW;
    property Size: Integer read FSize;
  end;

// Barycentric interpolation of the function sampled as (Nodes, NodeValues)
// onto the points in GridX. Nodes/NodeValues/GridX may each be row (1,N)
// or column (N,1) shaped, per newVM's usual vector convention; the result
// takes GridX's own shape. Nodes must be the (N+1) Chebyshev points a
// TCheb of the same order produced (the barycentric weights assume that).

function BaryInterpol(const Nodes, NodeValues, GridX: TVMobj): TVMobj;

implementation

function VecLen(const V: TVMobj): Integer; inline;
begin
  if V.Rows = 1 then Result := V.Cols else Result := V.Rows;
end;

function VecGet(const V: TVMobj; Index: Integer): Double; inline;
begin
  if V.Rows = 1 then Result := V.Element[0, Index]
  else Result := V.Element[Index, 0];
end;

procedure VecSet(var V: TVMobj; Index: Integer; Value: Double); inline;
begin
  if V.Rows = 1 then V.Element[0, Index] := Value
  else V.Element[Index, 0] := Value;
end;

{ TCheb }

constructor TCheb.Create(N: Integer);
const
  s = 'TCheb.Create : ';
var
  I, J, CI, CJ, Sgn: Integer;
begin
  inherited Create;
  assert(N > 0, s + 'N must be > 0');
  FSize := N;
  FX := TVMobj.Create(N + 1, 1);
  FD := TVMobj.Create(N + 1, N + 1);
  for I := 0 to N do
    FX.Element[I, 0] := cos(I * Pi / N);
  for I := 0 to N do
    for J := 0 to N do begin
      if I = J then begin
        if I = 0 then
          FD.Element[0, 0] := (2 * Sqr(N) + 1) / 6
        else if I = N then
          FD.Element[N, N] := -FD.Element[0, 0]
        else
          FD.Element[I, J] := -FX.Element[J, 0] / (2 * (1 - Sqr(FX.Element[J, 0])));
      end else begin
        if (I = 0) or (I = N) then CI := 2 else CI := 1;
        if (J = 0) or (J = N) then CJ := 2 else CJ := 1;
        if (I + J) mod 2 = 0 then Sgn := 1 else Sgn := -1;
        FD.Element[I, J] := (Sgn * CI / CJ) / (FX.Element[I, 0] - FX.Element[J, 0]);
      end;
    end;
  FD2 := FD * FD;
  BuildWeights(N);
end;

// Direct (non-FFT) Clenshaw-Curtis weight construction, per Trefethen's
// clencurt.m: theta_j = j*pi/N; interior weight w_j = 2*v_j/N where v_j is
// a truncated cosine series in theta_j, endpoint weights 1/(N^2-1) (N
// even) or 1/N^2 (N odd) - the even case additionally folds in a
// cos(N*theta_j)/(N^2-1) correction term the odd case doesn't need.
procedure TCheb.BuildWeights(N: Integer);
var
  J, K, KMax: Integer;
  Theta, V, W0: Double;
begin
  FW := TVMobj.Create(N + 1, 1);
  if Odd(N) then
    W0 := 1 / Sqr(N)
  else
    W0 := 1 / (Sqr(N) - 1);
  FW.Element[0, 0] := W0;
  FW.Element[N, 0] := W0;
  for J := 1 to N - 1 do begin
    Theta := J * Pi / N;
    V := 1;
    if Odd(N) then KMax := (N - 1) div 2 else KMax := (N div 2) - 1;
    for K := 1 to KMax do
      V := V - 2 * cos(2 * K * Theta) / (4 * Sqr(K) - 1);
    if not Odd(N) then
      V := V - cos(N * Theta) / (Sqr(N) - 1);
    FW.Element[J, 0] := 2 * V / N;
  end;
end;

function TCheb.Integrate(const F: TVMobj): TVMobj;
var
  DScratch: TVMobj;
begin
  // LinearSolve LU-factorises its A argument in place, so solve against a
  // scratch copy and leave FD reusable - same convention Invert/Det use.
  DScratch := CopyObj(FD);
  Result := CopyObj(F);
  LinearSolve(DScratch, Result);
end;

function TCheb.CurtisClenshaw(const F: TVMobj): Double;
const
  s = 'TCheb.CurtisClenshaw : ';
var
  I: Integer;
begin
  assert(VecLen(F) = FSize + 1, s + 'F must have Size+1 elements, sampled at the Chebyshev points');
  Result := 0;
  for I := 0 to FSize do
    Result := Result + FW.Element[I, 0] * VecGet(F, I);
end;

function BaryInterpol(const Nodes, NodeValues, GridX: TVMobj): TVMobj;
const
  s = 'BaryInterpol : ';
var
  NNodes, NGrid, I, K, MatchIdx: Integer;
  C: array of Double;
  Numer, Denom, XDiff, W, GX: Double;
  HasExact: Boolean;
begin
  NNodes := VecLen(Nodes);
  NGrid := VecLen(GridX);
  assert(VecLen(NodeValues) = NNodes, s + 'Nodes and NodeValues must be the same length');

  // Barycentric weights for Chebyshev points of the second kind:
  // c_i = (-1)^i, with the first and last weight halved.
  SetLength(C, NNodes);
  for I := 0 to NNodes - 1 do begin
    if Odd(I) then C[I] := -1 else C[I] := 1;
  end;
  C[0] := C[0] * 0.5;
  C[NNodes - 1] := C[NNodes - 1] * 0.5;

  Result := TVMobj.Create(GridX.Rows, GridX.Cols);

  for K := 0 to NGrid - 1 do begin
    GX := VecGet(GridX, K);
    Numer := 0;
    Denom := 0;
    HasExact := False;
    MatchIdx := -1;
    for I := 0 to NNodes - 1 do begin
      XDiff := GX - VecGet(Nodes, I);
      if XDiff = 0 then begin
        HasExact := True;
        MatchIdx := I;
        Continue;
      end;
      W := C[I] / XDiff;
      Numer := Numer + W * VecGet(NodeValues, I);
      Denom := Denom + W;
    end;
    if HasExact then
      VecSet(Result, K, VecGet(NodeValues, MatchIdx))
    else
      VecSet(Result, K, Numer / Denom);
  end;
end;

end.
