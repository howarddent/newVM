unit uBaryLag2D;

{*******************************************************************************

     2D barycentric Lagrange interpolation - ported from the Delphi/MtxVec
     original at demos/Chebyshev/2DChebBVP/Bary2D.pas (itself after Greg von
     Winckel's barylag2d.m), recoded onto newVM's TVMobj/TVMobjI in place of
     MtxVec's Matrix/Vector.

     Given function values F sampled on a (M,N) tensor grid of nodes XN (M
     points) x YN (N points), BaryLag2D interpolates onto a (Mf,Nf) tensor
     grid XF x YF via the standard tensor-product barycentric formula:

       P[a,b] = (Hx*F*Hy')[a,b] / (RowSum(Hx)[a] * RowSum(Hy)[b])

     where Hx[a,i] = wx[i]/(XF[a]-XN[i]), Hy[b,j] = wy[j]/(YF[b]-YN[j]), and
     wx/wy are the 1D barycentric weights of XN/YN, computed via the general
     product formula (not the closed-form (-1)^i / half-weight-at-the-ends
     shortcut ../NormalIntegration/uCheb.pas's BaryInterpol uses - that
     shortcut only holds for a *complete* Chebyshev-Gauss-Lobatto point set
     including both true endpoints, and u2DBVPMain.pas feeds this routine
     interior-only node sets that don't qualify).

     DENOMINATOR-ZERO HANDLING - the part of this port specifically called
     out to do better than the original: whenever XF[a] (or YF[b]) exactly
     coincides with a source node, XF[a]-XN[i] (or YF[b]-YN[j]) is exactly
     zero and Hx[a,i] (Hy[b,j]) is a literal division by zero. The Delphi
     original perturbs that one distance entry to `eps` and lets the
     resulting huge-but-finite Hx/Hy values numerically swamp the rest of
     the weighted sum - an approximation that works in practice but is never
     exact. Here, newVM.Find locates every "point at which the denominator
     polynomial is zero" (XF[a]-XN[i]=0 / YF[b]-YN[j]=0) and newVMI.Gather
     turns that mask into the actual (a,i)/(b,j) index pairs; those XDiff/
     YDiff entries are then placeholder-substituted purely to keep the bulk
     matrix formula free of a literal division by zero (Windows traps a true
     0/0 as a hard EInvalidOp - see perf/windows11ryzen9performance.txt - so
     this isn't just cosmetic), and every output cell whose row and/or
     column landed on a coincidence is afterwards overwritten with the
     actual function point: the true value F[i,j] where both axes coincide,
     or the exact 1D barycentric reduction along the non-coincident axis
     where only one does (a tensor-product interpolant built from per-axis
     Lagrange basis functions collapses exactly - not approximately - to a
     1D interpolant when one axis is pinned to a node, since
     L_i(XN[i0])=delta(i,i0)). This is an exact patch, not an epsilon
     approximation like the original's.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  newVM, newVMI;

// Nodes/NodeValues on F's two axes, plus the interpolated grid's own axes,
// may each be row (1,N) or column (N,1) shaped, per newVM's usual vector
// convention.
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
