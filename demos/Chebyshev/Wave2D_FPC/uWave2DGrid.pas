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
     ~1e-13. A single derivative of row X is DiffRow(X) = DCT1(Recurr(DCT1(X)))
     / LogicalN. The second derivative is computed by DiffRow2 below via
     DCT1(Recurr(Recurr(DCT1(X)))) / LogicalN - i.e. Recurr applied TWICE in
     coefficient space, with only one forward and one inverse DCT1, rather
     than calling DiffRow(DiffRow(X)) (forward+inverse DCT1 twice each, four
     DCT1 calls total). These are not just similarly-shaped formulas - they
     are algebraically identical, by DCT1's own documented round-trip
     identity DCT1(DCT1(y)) = LogicalN*y (exact for any y, LogicalN = the
     same 2*(Cols-1) used throughout this unit) and Recurr's linearity (its
     recursion coefficients don't depend on the input's own values, only on
     fixed indices, so Recurr(c*y) = c*Recurr(y)):
       DiffRow(DiffRow(X))
         = DCT1(Recurr(DCT1( DCT1(Recurr(DCT1(X)))/LogicalN ))) / LogicalN
         = DCT1(Recurr( DCT1(DCT1(Recurr(DCT1(X)))) /LogicalN )) / LogicalN   [DCT1 linear]
         = DCT1(Recurr( LogicalN*Recurr(DCT1(X)) /LogicalN )) / LogicalN      [round-trip identity, y=Recurr(DCT1(X))]
         = DCT1(Recurr(Recurr(DCT1(X)))) / LogicalN                          [LogicalN cancels; Recurr linear]
     Confirmed numerically (not just algebraically) with a standalone scratch
     program against both a random row and an exact f(x)=x^4 case (f''=12x^2):
     DiffRow(DiffRow(X)) and DiffRow2(X) agree to ~1e-11 (double-precision
     noise), and DiffRow2 matches the analytic 12x^2 to the same tolerance.
     Net effect: half as many DCT1/FFTW calls per row for the same result -
     this is the "run the recurrence twice before the inverse transform"
     optimisation, done for both DiffX2 and DiffY2 below.

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

     PARALLELISM - u_yy's rows (differentiating each row of vv) and u_xx's
     rows (differentiating each row of Transpose(vv), i.e. each column of
     vv) are all independent of each other, and this WAS multi-threaded at
     one point (row-parallel plus a separate X/Y split), but that work was
     backed out again after measuring it - kept here as a record of why,
     since the conclusion is unintuitive and worth not re-discovering by
     accident:
       - A raw TThread.Create per row-chunk plus two more threads for the
         X/Y split, spun up fresh every single Solve() call, measured
         SLOWER than plain single-threaded code end-to-end - unsurprising
         in hindsight, since Windows OS-thread creation/teardown costs far
         more than one row's DiffRow2 call.
       - Switching to the LCL's MTProcs unit (ProcThreadPool - a pool of
         worker threads created once and kept alive, dispatching work via
         synchronisation primitives instead of fresh OS threads) fixed the
         creation/teardown cost, but nesting DoParallel calls (one for the
         X/Y split, each of whose two callbacks made its own nested
         DoParallel call for that axis's rows) crashed outright - two
         outer DoParallel calls running concurrently, each trying to
         recruit a nested group from the same shared pool at the same
         moment, corrupted state badly enough to fail a SubMatrix bounds
         assert inside a worker callback under a headless stress run.
         Flattening to one single non-nested DoParallel call over every
         row of both axes at once fixed the crash and was confirmed
         correct (bit-for-bit identical vv values to the single-threaded
         version over a 500-step headless run) - but was STILL 3.6x-15x
         SLOWER than plain single-threaded code, even in that
         crash-free, non-nested form, and even after also fixing the
         separate FFTW plan-caching problem below. Measured across
         MaxThreads=24/4/1: avg solve time got WORSE as thread count went
         up (15.5ms/8.9ms/0.5ms respectively) - i.e. even ProcThreadPool's
         persistent-pool dispatch overhead (thread wake/signal
         synchronisation, not thread creation) dominates once each row's
         own work drops to a few microseconds, which is exactly what
         DiffRow2 plus newVM.pas's FFTW plan cache (see r2rTransform's own
         comment there) get it down to at this grid size (33x33). More
         threads at that point just means more synchronisation overhead
         paid for the same fixed amount of real work.
       - Net conclusion: at ChebN=32, the algorithmic fixes alone
         (DiffRow2's halved DCT1 count, and newVM.pas's FFTW plan cache) are
         both necessary AND sufficient - they took the measured per-step
         solve time from ~2.4ms down to ~0.5ms on their own, comfortably
         inside even the speed slider's tightest 5ms frame budget
         (AnimTimer.Interval = Round(50/TrackBar1.Position), Position up
         to 10 - see uWave2DMain.pas), with no threading at all. Adding
         thread-pool dispatch on top of that measured strictly worse.
         A much larger ChebN, where a single row's DiffRow2 call is
         genuinely expensive rather than a handful of microseconds, could
         tip this balance back the other way - if this demo's grid size
         ever grows substantially, re-measure before assuming either
         answer still holds.
       - The FFTW thread-safety fix below (FFTWPlanLock, in newVM.pas) was
         added to support the threaded attempts above and stayed even
         after they were backed out: DCT1 (and DST1/etc) building and
         destroying a plan with no locking at all is a latent bug for ANY
         future multi-threaded caller of those functions, not just this
         demo, independent of whether this particular demo ends up
         threaded.

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

// Second derivative of a (1,N+1) Chebyshev row: one forward DCT1, Recurr
// applied TWICE in coefficient space, one inverse DCT1 - algebraically
// identical to (and ~2x fewer DCT1/FFTW calls than) calling the single-
// derivative recipe DCT1(Recurr(DCT1(X)))/LogicalN twice end-to-end - see
// this unit's own header comment (DIFFERENTIATION) for the derivation and
// its numerical verification.
function DiffRow2(const Row: TVMobj): TVMobj;
var
  LogicalN : Integer;
begin
  LogicalN := 2 * (Row.Cols - 1);
  Result := DCT1(Recurr(Recurr(DCT1(Row)))) / LogicalN;
end;

function TWave2DGrid.DiffRowsSecondDeriv(const M: TVMobj): TVMobj;
var
  i, j : Integer;
  row, d2 : TVMobj;
begin
  Result := TVMobj.Create(M.Rows, M.Cols);
  for i := 0 to M.Rows - 1 do begin
    row := SubMatrix(M, i, 0, 1, M.Cols);
    d2 := DiffRow2(row);
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
