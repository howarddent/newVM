unit uCheb;

{*******************************************************************************

     Ported from the Delphi/MtxVec original at
     demos/Chebyshev/Normal_Integration/uMain.pas (TCheb, BaryInterPol) -
     recoded onto newVM's TVMobj in place of MtxVec's Vector/Matrix. All
     Chebyshev-specific code shared across the demos in this directory tree
     lives here, 1D and 2D alike - TCheb (grid/differentiation-matrix
     construction, used directly by both the 1D and 2D BVP demos) plus
     BaryLag1D and BaryLag2D (barycentric interpolation, one function per
     dimensionality) - rather than splitting the 2D piece into its own
     demo-local unit, so a caller needing both only has one unit to reuse.
     BaryLag2D (and its own CountNonZero helper) moved here unchanged from
     demos/Chebyshev/2DChebBVP_FPC/uBaryLag2D.pas, which no longer exists;
     see that function's own header comment, below, for its algorithm.
     BaryInterpol was renamed to BaryLag1D at the same time, purely so the
     two interpolation routines read as a matched pair - no behavioural
     change.

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

     BaryLag1D (formerly BaryInterpol) reimplements the original's
     barycentric-interpolation routine as a plain nested loop over TVMobj
     elements rather than MtxVec's vectorised expressions (xdiff:=gridx-x[i];
     findmask; etc) - no BLAS/IPP primitive does barycentric interpolation
     directly, same rationale as this codebase's own Find/Gather/Trace. One
     deliberate behavioural difference from the original: where a grid point
     exactly matches an interpolation node, the original relies on that
     term's division producing IEEE Infinity (c[i]/0), which then makes the
     numerator/denominator ratio evaluate to NaN and gets patched up
     afterwards via an index array; here the zero-difference term is
     detected and skipped explicitly instead, and the exact node value is
     substituted directly - equivalent result, without leaning on
     IEEE Inf/NaN propagation (or an FPU trap firing on the 0/0, depending
     on the platform's floating-point exception mask). BaryLag2D (below)
     takes the more general "actually locate the zero denominators, then
     patch" approach via Find/Gather instead of this function's own inline
     skip-on-XDiff=0 loop - see BaryLag2D's own header for why 2D needs that
     extra machinery where 1D doesn't.

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
  newVM, newVMI;

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

function BaryLag1D(const Nodes, NodeValues, GridX: TVMobj): TVMobj;

// 2D barycentric Lagrange interpolation - see this function's own
// implementation-section header comment for the algorithm and the
// denominator-zero handling. Unlike BaryLag1D, XN/YN need not be a
// complete Chebyshev-Gauss-Lobatto point set (interior-only node sets are
// fine - see that header comment for why).
function BaryLag2D(const F, XN, YN, XF, YF: TVMobj): TVMobj;

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
  // MatMult, not '*': newVM's '*' between two same-shaped TVMobj is
  // element-wise (mulObj/vdMul - see newVMTests.pas's own
  // "AssertTrue(A * B = mulObj(A, B))" and Graphs/Plot2D's actual usage,
  // both of which contradict newVM.pas's own header comment and
  // CLAUDE.md's architecture notes, which still describe '*' as matrix
  // multiplication - that's stale documentation, not the current,
  // tested behaviour). FD * FD here would silently compute the
  // element-wise square of D's entries instead of composing the
  // differentiation operator with itself.
  FD2 := MatMult(FD, FD);
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

function BaryLag1D(const Nodes, NodeValues, GridX: TVMobj): TVMobj;
const
  s = 'BaryLag1D : ';
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

// 2D barycentric Lagrange interpolation - ported from the Delphi/MtxVec
// original at demos/Chebyshev/2DChebBVP/Bary2D.pas (itself after Greg von
// Winckel's barylag2d.m), recoded onto newVM's TVMobj/TVMobjI in place of
// MtxVec's Matrix/Vector. Moved here unchanged from the (now deleted)
// demos/Chebyshev/2DChebBVP_FPC/uBaryLag2D.pas, alongside BaryLag1D, per
// this unit's own header comment.
//
// Given function values F sampled on a (M,N) tensor grid of nodes XN (M
// points) x YN (N points), BaryLag2D interpolates onto a (Mf,Nf) tensor
// grid XF x YF via the standard tensor-product barycentric formula:
//
//   P[a,b] = (Hx*F*Hy')[a,b] / (RowSum(Hx)[a] * RowSum(Hy)[b])
//
// where Hx[a,i] = wx[i]/(XF[a]-XN[i]), Hy[b,j] = wy[j]/(YF[b]-YN[j]), and
// wx/wy are the 1D barycentric weights of XN/YN, computed via the general
// product formula (not BaryLag1D's closed-form (-1)^i / half-weight-at-the-
// ends shortcut - that shortcut only holds for a *complete*
// Chebyshev-Gauss-Lobatto point set including both true endpoints, and the
// 2D BVP demo feeds this routine interior-only node sets that don't
// qualify).
//
// DENOMINATOR-ZERO HANDLING - the part of this port specifically called out
// to do better than the original: whenever XF[a] (or YF[b]) exactly
// coincides with a source node, XF[a]-XN[i] (or YF[b]-YN[j]) is exactly
// zero and Hx[a,i] (Hy[b,j]) is a literal division by zero. The Delphi
// original perturbs that one distance entry to `eps` and lets the resulting
// huge-but-finite Hx/Hy values numerically swamp the rest of the weighted
// sum - an approximation that works in practice but is never exact. Here,
// newVM.Find locates every "point at which the denominator polynomial is
// zero" (XF[a]-XN[i]=0 / YF[b]-YN[j]=0) and newVMI.Gather turns that mask
// into the actual (a,i)/(b,j) index pairs; those XDiff/YDiff entries are
// then placeholder-substituted purely to keep the bulk matrix formula free
// of a literal division by zero (Windows traps a true 0/0 as a hard
// EInvalidOp - see perf/windows11ryzen9performance.txt - so this isn't just
// cosmetic), and every output cell whose row and/or column landed on a
// coincidence is afterwards overwritten with the actual function point: the
// true value F[i,j] where both axes coincide, or the exact 1D barycentric
// reduction along the non-coincident axis where only one does (a
// tensor-product interpolant built from per-axis Lagrange basis functions
// collapses exactly - not approximately - to a 1D interpolant when one axis
// is pinned to a node, since L_i(XN[i0])=delta(i,i0)). This is an exact
// patch, not an epsilon approximation like the original's.

// Number of non-zero entries in an integer mask (typically Find's output) -
// used only to decide whether it's safe to call Gather, which asserts on an
// all-zero mask (there is no "empty index list" TVMobjI representation).
function CountNonZero(const A: TVMobjI): Integer;
var
  r, c: Integer;
begin
  Result := 0;
  for r := 0 to A.Rows - 1 do
    for c := 0 to A.Cols - 1 do
      if A.Element[r, c] <> 0 then Inc(Result);
end;

function BaryLag2D(const F, XN, YN, XF, YF: TVMobj): TVMobj;
const
  s = 'BaryLag2D : ';
  SafeEps = 1e-6;  // placeholder for a literal zero denominator - see header
var
  M, N, Mf, Nf, i, j, a, b, k, idx: Integer;
  Wx, Wy: array of Double;
  XMatch, YMatch: array of Integer;  // -1 = no coincidence, else the node index
  XDiff, YDiff, Hx, Hy, Numer, Denom, OnesM, OnesN, RowSumHx, RowSumHy: TVMobj;
  XMask, YMask, XIdx, YIdx: TVMobjI;
  prod, Wj, Wi, Numer1, Denom1: Double;
begin
  M := VecLen(XN); N := VecLen(YN); Mf := VecLen(XF); Nf := VecLen(YF);
  assert((F.Rows = M) and (F.Cols = N), s + 'F must be (Length(XN), Length(YN))');

  // 1. general barycentric weights (product formula, O(M^2)/O(N^2)).
  SetLength(Wx, M);
  for i := 0 to M - 1 do begin
    prod := 1;
    for k := 0 to M - 1 do
      if k <> i then prod := prod * (VecGet(XN, i) - VecGet(XN, k));
    Wx[i] := 1 / prod;
  end;
  SetLength(Wy, N);
  for j := 0 to N - 1 do begin
    prod := 1;
    for k := 0 to N - 1 do
      if k <> j then prod := prod * (VecGet(YN, j) - VecGet(YN, k));
    Wy[j] := 1 / prod;
  end;

  // 2. distance ("denominator") matrices, and the exact coincidences in them.
  XDiff := TVMobj.Create(Mf, M);
  for a := 0 to Mf - 1 do
    for i := 0 to M - 1 do
      XDiff.Element[a, i] := VecGet(XF, a) - VecGet(XN, i);
  YDiff := TVMobj.Create(Nf, N);
  for b := 0 to Nf - 1 do
    for j := 0 to N - 1 do
      YDiff.Element[b, j] := VecGet(YF, b) - VecGet(YN, j);

  SetLength(XMatch, Mf);
  for a := 0 to Mf - 1 do XMatch[a] := -1;
  XMask := Find(XDiff, cmpEQ, 0);
  if CountNonZero(XMask) > 0 then begin
    XIdx := Gather(XMask);
    for k := 0 to XIdx.Cols - 1 do begin
      idx := XIdx.Element[0, k];
      XMatch[idx div M] := idx mod M;
      XDiff.Element[idx div M, idx mod M] := SafeEps;
    end;
  end;

  SetLength(YMatch, Nf);
  for b := 0 to Nf - 1 do YMatch[b] := -1;
  YMask := Find(YDiff, cmpEQ, 0);
  if CountNonZero(YMask) > 0 then begin
    YIdx := Gather(YMask);
    for k := 0 to YIdx.Cols - 1 do begin
      idx := YIdx.Element[0, k];
      YMatch[idx div N] := idx mod N;
      YDiff.Element[idx div N, idx mod N] := SafeEps;
    end;
  end;

  // 3. Hx/Hy - safe now that XDiff/YDiff have no literal zero left in them.
  Hx := TVMobj.Create(Mf, M);
  for a := 0 to Mf - 1 do
    for i := 0 to M - 1 do
      Hx.Element[a, i] := Wx[i] / XDiff.Element[a, i];
  Hy := TVMobj.Create(Nf, N);
  for b := 0 to Nf - 1 do
    for j := 0 to N - 1 do
      Hy.Element[b, j] := Wy[j] / YDiff.Element[b, j];

  // 4. bulk tensor-product formula: P = (Hx*F*Hy') ./ outer(RowSum(Hx), RowSum(Hy)).
  //    Rows/columns touched by a coincidence come out numerically meaningless
  //    here (fed by the SafeEps placeholder), but confined to exactly the
  //    rows/columns step 5 below overwrites - MatMult never mixes one output
  //    row/column's inputs into another's.
  Numer := MatMult(MatMult(Hx, F), Hy.Transpose);
  OnesM := TVMobj.Create(M, 1);
  for i := 0 to M - 1 do OnesM.Element[i, 0] := 1;
  OnesN := TVMobj.Create(N, 1);
  for j := 0 to N - 1 do OnesN.Element[j, 0] := 1;
  RowSumHx := MatMult(Hx, OnesM);                  // (Mf,1)
  RowSumHy := MatMult(Hy, OnesN);                  // (Nf,1)
  Denom := MatMult(RowSumHx, RowSumHy.Transpose);  // (Mf,Nf) outer product

  Result := TVMobj.Create(Mf, Nf);
  for a := 0 to Mf - 1 do
    for b := 0 to Nf - 1 do
      Result.Element[a, b] := Numer.Element[a, b] / Denom.Element[a, b];

  // 5. exact patch: overwrite every output cell whose row and/or column
  //    landed exactly on a source node with the true value, per the header
  //    comment - not the eps-driven approximation computed above.
  for a := 0 to Mf - 1 do
    for b := 0 to Nf - 1 do begin
      if (XMatch[a] >= 0) and (YMatch[b] >= 0) then
        Result.Element[a, b] := F.Element[XMatch[a], YMatch[b]]
      else if XMatch[a] >= 0 then begin
        Numer1 := 0; Denom1 := 0;
        for j := 0 to N - 1 do begin
          Wj := Wy[j] / (VecGet(YF, b) - VecGet(YN, j));
          Numer1 := Numer1 + Wj * F.Element[XMatch[a], j];
          Denom1 := Denom1 + Wj;
        end;
        Result.Element[a, b] := Numer1 / Denom1;
      end else if YMatch[b] >= 0 then begin
        Numer1 := 0; Denom1 := 0;
        for i := 0 to M - 1 do begin
          Wi := Wx[i] / (VecGet(XF, a) - VecGet(XN, i));
          Numer1 := Numer1 + Wi * F.Element[i, YMatch[b]];
          Denom1 := Denom1 + Wi;
        end;
        Result.Element[a, b] := Numer1 / Denom1;
      end;
    end;
end;

end.
