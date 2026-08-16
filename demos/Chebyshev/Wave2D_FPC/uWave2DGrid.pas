unit uWave2DGrid;

{*******************************************************************************

     Numerical engine for the Wave2D_FPC demo - ported from the Delphi/MtxVec
     original at demos/Chebyshev/Wave2D/{Unit1,Unit2,ufft_Wave,Bary2D}.pas.
     Solves the 2D wave equation u_tt = u_xx + u_yy on [-1,1]x[-1,1] via
     Chebyshev pseudospectral differentiation and explicit leapfrog time
     stepping, matching the original's T2DGrid class (ufft_Wave.pas) - based,
     per that unit's own header comment, on "Program 20" of Trefethen's
     "Spectral Methods in MATLAB".

     DIFFERENTIATION - the one deliberate departure from a line-for-line port.
     The original computes u_xx/u_yy via a hand-rolled FFT trick: mirror-
     extend each row/column to 2N points, FFT, multiply by precomputed -k^2
     coefficient matrices (k2_Matx/k2_Maty), inverse FFT, then apply
     correction weight matrices (Wx/Wxx) that are zeroed at the two Chebyshev
     endpoints. That machinery isn't reproduced here, for two reasons that
     made it too risky to blind-port without a reference to check against:
       1) MtxVec's own FFT1D/iFFT1D semantics (real-vs-complex storage,
          normalisation convention) aren't available to verify in this
          environment, so there's no way to confirm a hand-translation is
          faithful rather than just "looks plausible".
       2) The original's Uxx is literally "D1xx + D2xx" - the SUM of the
          first- and second-x-derivative terms - which doesn't match the
          wave equation's own u_xx-only Laplacian. Whether that's deliberate
          (e.g. a leftover coefficient copied from a more general
          advection-diffusion template) or a bug isn't something that can be
          settled without running the original interactively, so it wasn't
          carried over.
     Instead, this port reuses demos/SpectralDiff/ufuncmain.pas's own proven
     Chebyshev-differentiation recipe - DCT1 plus the Boyd coefficient-space
     recursion Recurr, verified there against an exact analytic derivative to
     ~1e-13 - see DiffRow below. Each second derivative is that SAME proven
     single-derivative recipe applied twice end-to-end (differentiate the
     grid values, then differentiate the result again), rather than chaining
     two Recurr calls in coefficient space before transforming back - the
     latter is standard textbook practice too, but the former only relies on
     machinery already proven correct elsewhere in this codebase, at a cost
     (a handful of length-(N+1) DCT1 calls per row per Solve() step) that's
     immaterial next to a 33x33 grid.

     BOUNDARY HANDLING - the original's Wx/Wxx correction-weight vectors are
     explicitly zero at the two Chebyshev endpoints (w1[0]:=0; w1[N]:=0;
     ditto w2), which has the net effect of pinning the boundary ring of the
     Laplacian to zero every step, so the leapfrog update never perturbs the
     boundary away from its initial, near-machine-zero value there (every
     initial condition below is a Gaussian bump with negligible amplitude at
     the domain edge already). DiffX2/DiffY2 here need no endpoint special-
     casing themselves - unlike the mirror-extension FFT trick, DCT1+Recurr
     is exact including at the two endpoints - but Solve zeroes the outer
     ring of the computed Laplacian explicitly, to reproduce the same net
     "boundary stays put" behaviour the original had.

     uCheb.BaryLag2D (shared with 2DChebBVP_FPC) interpolates the raw
     (N+1)x(N+1) Chebyshev solution grid onto an evenly-spaced DispN x DispN
     display grid every Solve() step, exactly as 2DChebBVP_FPC does once at
     startup - needed here too since TVMPlot3D draws its rows/columns at
     uniform screen spacing regardless of the underlying data's actual x/y
     coordinates, and the Chebyshev grid is deliberately non-uniform
     (clustered near the boundary).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  newVM, uCheb, hirestimer;

type
  TInitialFunc = (SingleG, DoubleG, CenteredG, SingleWave);

  TWave2DGrid = class
  private
    FCheb: TCheb;
    FN: Integer;
    FXF, FYF: TVMobj;            // evenly-spaced display grid coordinates
    function DiffRow(const Row: TVMobj): TVMobj;           // 1st deriv of a (1,N+1) row
    function DiffRowsSecondDeriv(const M: TVMobj): TVMobj; // 2nd deriv along each row (varies with column index)
    function DiffX2(const M: TVMobj): TVMobj;               // d^2/dx^2 - varies with row index
    function DiffY2(const M: TVMobj): TVMobj;               // d^2/dy^2 - varies with column index
  public
    vv, vvold, PlotGrid: TVMobj; // current/previous solution grid, interpolated display grid
    dt, t: Double;
    constructor Create(N, DispN: Integer);
    destructor Destroy; override;
    procedure InitialiseModel(InitFunc: TInitialFunc);
    function Solve: Int64;       // one leapfrog timestep; returns elapsed microseconds
  end;

implementation

// Differentiates a (1,N+1) Chebyshev coefficient series (as produced by
// DCT1) via the recursion c'[N]=0, c'[N-1]=Logical_N*c[N]/2,
// c'[i-1]=2*i*c[i]+c'[i+1] - Boyd, "Chebyshev and Fourier Spectral Methods"
// (2nd ed.) - ported from demos/SpectralDiff/ufuncmain.pas's own Recurr,
// parameterised by the input's own length (InVec.Cols-1) rather than that
// demo's fixed module-level N/Logical_N constants, so it works for whatever
// grid size TWave2DGrid.Create is given.
function Recurr(const InVec: TVMobj): TVMobj;
var
  i, N, LogicalN : Integer;
begin
  N := InVec.Cols - 1;
  LogicalN := 2 * N;
  Result := TVMobj.Create(1, N + 1);
  Result.Element[0, N] := 0;
  Result.Element[0, N - 1] := 0.5 * LogicalN * InVec.Element[0, N];
  for i := N - 1 downto 1 do
    Result.Element[0, i - 1] := 2 * i * InVec.Element[0, i] + Result.Element[0, i + 1];
end;

function TWave2DGrid.DiffRow(const Row: TVMobj): TVMobj;
var
  LogicalN : Integer;
begin
  LogicalN := 2 * (Row.Cols - 1);
  Result := DCT1(Recurr(DCT1(Row))) / LogicalN;
end;

function TWave2DGrid.DiffRowsSecondDeriv(const M: TVMobj): TVMobj;
var
  i, j : Integer;
  row, d1, d2 : TVMobj;
begin
  Result := TVMobj.Create(M.Rows, M.Cols);
  for i := 0 to M.Rows - 1 do begin
    row := SubMatrix(M, i, 0, 1, M.Cols);
    d1 := DiffRow(row);
    d2 := DiffRow(d1);
    for j := 0 to M.Cols - 1 do
      Result.Element[i, j] := d2.Element[0, j];
  end;
end;

function TWave2DGrid.DiffX2(const M: TVMobj): TVMobj;
begin
  Result := DiffRowsSecondDeriv(M.Transpose).Transpose;
end;

function TWave2DGrid.DiffY2(const M: TVMobj): TVMobj;
begin
  Result := DiffRowsSecondDeriv(M);
end;

constructor TWave2DGrid.Create(N, DispN: Integer);
begin
  inherited Create;
  FN := N;
  dt := 3 / Sqr(N);   // timestep - see the original's own "See book on stability!!" comment
  FCheb := TCheb.Create(N);
  FXF := TVMobj.Create(1, DispN);
  FXF.linspace(-1, 2 / (DispN - 1));
  FYF := CopyObj(FXF);
  InitialiseModel(SingleG);
end;

destructor TWave2DGrid.Destroy;
begin
  FCheb.Free;
  inherited Destroy;
end;

procedure TWave2DGrid.InitialiseModel(InitFunc: TInitialFunc);
var
  i, j : Integer;
  x, y : Double;
begin
  t := 0;
  vv := TVMobj.Create(FN + 1, FN + 1);
  // Row index -> x, column index -> y - matches 2DChebBVP_FPC's own
  // Xi.Element[I,0]/Xi.Element[J,0] convention, for consistency between the
  // two sibling demos.
  for i := 0 to FN do begin
    x := FCheb.X.Element[i, 0];
    for j := 0 to FN do begin
      y := FCheb.X.Element[j, 0];
      case InitFunc of
        SingleG:    vv.Element[i, j] := Exp(-40 * (Sqr(x - 0.4) + Sqr(y)));
        DoubleG:    vv.Element[i, j] := Exp(-40 * (Sqr(x - 0.4) + Sqr(y)))
                                       + Exp(-40 * (Sqr(x + 0.4) + Sqr(y)));
        CenteredG:  vv.Element[i, j] := Exp(-40 * (Sqr(x) + Sqr(y)));
        SingleWave: vv.Element[i, j] := 0.5 * Exp(-40 * Sqr(x));
      end;
    end;
  end;
  // Zero initial velocity (vvold=vv), matching the original's
  // "vvold.copy(vv)". Safe without CopyObj: Solve below never mutates vv/
  // vvold in place, only ever reassigns which buffer each variable refers
  // to, so aliasing the two here for one instant is harmless.
  vvold := vv;
  PlotGrid := BaryLag2D(vv, FCheb.X, FCheb.X, FXF, FYF);
end;

function TWave2DGrid.Solve: Int64;
var
  U, vvnew : TVMobj;
  i : Integer;
begin
  Profiler.Start;
  U := DiffX2(vv) + DiffY2(vv);
  for i := 0 to FN do begin
    U.Element[0, i] := 0;
    U.Element[FN, i] := 0;
    U.Element[i, 0] := 0;
    U.Element[i, FN] := 0;
  end;
  vvnew := 2 * vv - vvold + Sqr(dt) * U;   // leapfrog
  vvold := vv;
  vv := vvnew;
  t := t + dt;
  PlotGrid := BaryLag2D(vv, FCheb.X, FCheb.X, FXF, FYF);
  Result := Profiler.Stop;
end;

end.
