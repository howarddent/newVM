# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Free Pascal / Lazarus library (`newVM`) providing matrix/vector objects that
wrap Intel MKL (BLAS/LAPACK/VSL) and Intel IPP for linear algebra. It is
explicitly inspired by the Dew MtxVec library for FPC, but — unlike Dew —
does not distinguish matrix and vector types: a vector is just an (N,1) or
(1,N) matrix. There are four parallel "flavors" of the same object model for
real/complex × double/single precision (see Architecture below), plus five
further non-duplicated companion units: `newVMI.pas`, providing an integer
array/matrix type for index operations (pivot vectors, index lists) on the
other four; `newPolymath.pas`, a polynomial type with a least-squares
`Fit` over `TVMobj` vectors; `newVMsparse.pas`, providing a sparse double-real matrix type
with MKL's PARDISO and RCI FGMRES solvers over it; and two GPU-resident
single-precision types, `newVMCL.pas` (OpenCL + clFFT) and `newVMMetal.pas`
(Metal + MetalPerformanceShadersGraph). The last three are each gated on a
config define and are simply absent on a machine without their backend.

Despite the name, the accelerated backends are no longer Intel-only:
`cblas.pas` will bind Arm Performance Libraries or Apple's Accelerate in
place of OpenBLAS where those are what a machine actually has — see the
`newVMConfig.inc` section for how that's detected and what it changes.

There is no README and no CI, but there is a real automated test suite:
`newVMTests.pas` (FPCUnit `TTestCase`s, one per `TVMobj*` type) plus
`newVMtest.lpr`, which now builds as a plain-text FPCUnit console runner
rather than an eyeballed demo — see the `newVMTests.pas and newVMtest.lpr`
section below.

## Build

Building requires:
- Lazarus + FPC (this repo was built against Lazarus at `~/Lazarus`; `lazbuild`
  needs `--lazarusdir=<path>` and a working `fpc`/`ppcx64` on `PATH`).
- Intel oneAPI MKL runtime (`libmkl_rt.so`) and IPP runtime (`libippcore.so`,
  `libippvm.so`, `libipps.so`) discoverable at link/run time — these are
  `dlopen`'d at runtime, not statically linked, so they must also be on
  `LD_LIBRARY_PATH` (or equivalent) when *running* the built binary, not just
  when compiling.
- OpenBLAS (`libopenblas`) — `cblas.pas` binds against it directly for the
  `CBLAS_ORDER`/`CBLAS_TRANSPOSE`/etc. enum types and some declarations, even
  though the actual matrix math at runtime comes from MKL.

Build the test program:
```
lazbuild --lazarusdir=/home/howard/Lazarus newVMtest.lpi
```
Compiled output goes to `lib/x86_64-linux/` (units) and `newVMtest` (binary),
per the `UnitOutputDirectory` in the `.lpi`.

Run it:
```
./newVMtest
```
This runs the full FPCUnit suite (`newVMTests.pas`) via a plain-text console
runner and exits non-zero if any test fails or errors — no CLI args are
handled.

There is no headless `fpc`-only build path documented here — always build via
`lazbuild` and the `.lpi`, since that's what encodes the search paths and
compiler options (assertions are force-enabled via
`IncludeAssertionCode=True`, which several routines rely on for argument
validation — see below).

### Building on Windows

The same `.lpi`/units also target Windows (confirmed compiling on Windows
11 with a real Lazarus/FPC install; see "Cross-platform library binding"
below for the runtime-loading approach this required):

- MKL and IPP move from Unix `{$Linklib 'foo.so'}` directives, resolved at
  link time, to runtime `LoadLibrary`/`GetProcedureAddress` binding on
  Windows — see "Cross-platform library binding" below for why a static
  Windows `external 'somedll.dll'` declaration doesn't work for either
  library. No source changes are needed to retarget; just build the
  `.lpi` with a Windows-targeting FPC/Lazarus install.
- Required at runtime, discoverable via `PATH` (or copied next to the
  built `.exe`): an Intel oneAPI MKL runtime DLL (recent installs ship a
  *versioned* dispatcher, e.g. `mkl_rt.2.dll` or `mkl_rt.3.dll`, not a
  plain `mkl_rt.dll` — see below), IPP's `ippcore.dll`/`ippvm.dll`/
  `ipps.dll`, and OpenBLAS's `openblas.dll` (`cblas.pas` already had
  `{$IFDEF WINDOWS} CBLASLib = 'openblas.dll'` before this Windows support
  was added). None of these ship on `PATH` by default with a oneAPI
  install — you must add the relevant `oneAPI\mkl\<version>\bin` and
  `oneAPI\<version>\bin` (IPP) directories to `PATH` yourself, or copy the
  DLLs next to `newVMtest.exe`.
- `newVMtest.lpr` gained `{$APPTYPE CONSOLE}` so it builds as a console
  subsystem executable on Windows (a no-op on Unix targets); it already
  guarded `cthreads` behind `{$IFDEF UNIX}` (not available/needed on
  Windows, where the RTL doesn't need it for thread support).

## Architecture

### The four parallel unit families

The same object model is duplicated four times, once per real/complex ×
double/single combination — there is no shared generic base:

| Unit | Element type | Object type | MKL prefix |
|---|---|---|---|
| `newVM.pas` | `Double` | `TVMobj` | `d` (e.g. `cblas_dgemm`) |
| `newVMSingle.pas` | `Single` | `TVMobjS` | `s` |
| `newVMComplex.pas` | `TComplex16` (double re/im) | `TVMobjZ` | `z` |
| `newVMComplexSingle.pas` | `TComplex8` (single re/im) | `TVMobjC` | `c` |

When fixing a bug or adding an operation in one of these, check whether the
same fix is needed in the sibling units — they are hand-copied, not
generated, so they drift independently unless kept in sync deliberately.

Complex units `uses` their same-precision real sibling (`newVMComplex`
depends on `newVM`, `newVMComplexSingle` depends on `newVMSingle`) to support
real→complex promotion (`RealToComplex`) and part extraction
(`GetRealPart`/`GetImagPart`/`SplitComplex`).

`newVMI.pas` is a fifth unit but deliberately *not* a fifth member of this
duplicated family — see "`newVMI.pas` (integer index array/matrix)" below.

### Core object shape (`TVMobj` and siblings)

Each is a Pascal `record` (not a `class`) wrapping a dynamic array (`fData`)
plus `frows`/`fcols`. Elements are stored **row-major**, 0-based, and
addressed via the default indexed property `Element[r,c]`, backed by
`calcoffset(r,c,cols) = r*cols+c` — the standard row-major formula, and the
same one `writeMatrix` and the complex-unit `fillRandom`/copy tricks use
directly via `i*cols+j`. (Historical note: `calcoffset` originally took only
`(r,c)` and computed `(r*(c-1))+r-1`, which algebraically reduces to
`r*c-1` — a function of the *product* r*c, not position, so e.g. `[1,3]`
and `[3,1]` silently aliased the same storage slot in any matrix with more
than one row and column, and `[0,anything]` produced a negative index. It
only ever happened to work for row/column vectors. Fixed to take `cols` as
a third argument and use the standard formula; nothing in the library
itself depended on the old behavior, since every internal routine already
bypassed the property and read `FData` directly.)

Because these are records, not classes, **value semantics apply**: assigning
one `TVMobj` to another copies the record header but `fData` is a dynamic
array, so plain assignment aliases the underlying buffer. Use `CopyObj`
(`CopyObjZ`/etc. in the other units) when an independent copy is required —
several routines (e.g. `EigDecompose`) do this deliberately because the
underlying LAPACK call overwrites its input matrix in place.

All bounds/shape checks are done via `assert(...)` with a descriptive
message, not exceptions — they only fire because the `.lpi` enables
`IncludeAssertionCode`. Follow this pattern (guard clause + `assert`, with a
unit-local `const s = 'Routine Name : '` prefix on the message) rather than
introducing exception-based validation.

`DataPtr` (on `TVMobj`/`TVMobjS`) and the equivalent raw-pointer access on
the other records exist specifically so sibling units can hand a raw buffer
pointer straight into an MKL call without needing friend/private access —
this is the established pattern for cross-unit interop; use it rather than
exposing more internal fields. All four types expose public read-only
`Rows`/`Cols` properties (the complex units gained theirs alongside the
`calcoffset` fix below, for parity with the real units and so external code
— including the test suite — can query dimensions without reaching into
private fields).

### Operator overloads

Each of the four units declares `+`, `-` (binary and unary), `*`, and `/`
for its `TVMobj*` type as **`class operator` members of the record**
(e.g. `class operator +(const A, B: TVMobj): TVMobj;` inside `TVMobj`,
implemented as `class operator TVMobj.+(const A, B: TVMobj): TVMobj;`).
This is required, not stylistic: all four units compile under `{$mode
Delphi}`, and Delphi mode only recognises operator overloading declared
as `class operator` inside the type — the free-standing "`operator + (a,
b: T): T;`" form declared at unit scope (as seen in plenty of `{$mode
ObjFPC}` code elsewhere, e.g. `components/tachart/tageometry.pas` in the
Lazarus source tree) is an ObjFPC/FPC-mode-only extension and gets
rejected under Delphi mode with a parser error that reads "IMPLEMENTATION
expected but OPERATOR found" (because the parser doesn't treat `operator`
as a declaration keyword there at all under this mode). Like a normal
function, the implementation body uses the implicit `Result` variable —
there is no named custom result identifier in FPC's operator syntax,
class or global. Declaration (inside the record) and implementation
(qualified `TypeName.symbol`) signatures must match exactly.

The two complex units' *mixed* real/complex operators (e.g. `TVMobjZ +
TVMobj`) are declared as `class operator` members of the complex type
(`TVMobjZ`/`TVMobjC`), never the real type — Delphi's rule is that a
`class operator` must be a member of one of its operand types, and since
only the complex unit `uses` the real sibling unit, `TVMobjZ`/`TVMobjC`
is the only one of the two records that can see both types at the point
of declaration.

What backs each operator, and why:
- `+`/`-` are element-wise, via `cblas_?axpy` (`Y := alpha*X + Y`, with
  alpha = ±1) applied on top of a `CopyObj`-produced scratch buffer, not a
  hand-rolled loop.
- unary `-` negates via `cblas_?scal` (real units) or `cblas_?dscal`/
  `cblas_?sscal` (complex units — MKL's "scale a complex vector by a real
  scalar" routine, used here with -1).
- `*` between two same-type `TVMobj*` is **element-wise** multiplication
  (the Hadamard product), via `mulObj`/`MulObjS`/`MulObjZ`/`MulObjC` (MKL
  VML's `vdMul`/`vsMul`/`vzMul`/`vcMul`) — **not** matrix multiplication.
  Use the separate `MatMult`/`MatMultS`/`MatMultZ`/`MatMultC` function
  (`cblas_?gemm`) explicitly for a real matrix product.
  `newVMTests.pas`'s own `AssertTrue(A * B = mulObj(A, B))` (and the
  `S`/`Z`/`C` analogues) is the operator's actual, tested contract, and
  `Graphs/Plot2D`'s `YSin := Envelope * Sin(3 * X);` (two same-shaped row
  vectors — dimensionally impossible as a matrix product) already relies
  on it being element-wise. Getting this backwards compiles and runs
  fine, just on the wrong values: see
  `demos/Chebyshev/NormalIntegration/uCheb.pas`'s git history, where
  `FD2 := FD * FD` (intended as `D` composed with itself) silently
  computed the element-wise square of `D`'s entries instead, and the bug
  only surfaced once a second demo actually solved against `D2`.
- `*`/`/` against a scalar scale every element via `cblas_?scal`. The real
  units' `/` uses IPP's `ippsDivC_64f_I`/`ippsDivC_32f_I` directly (division
  by a constant is a native IPP primitive); the complex units' `/` instead
  computes the scalar reciprocal in Pascal and calls `cblas_?scal`, since
  BLAS has no "divide vector by scalar" routine. The complex units accept
  *either* their native complex scalar (`TComplex16`/`TComplex8`, via
  `cblas_zscal`/`cblas_cscal`) *or* a plain real scalar (`Double`/`Single`,
  via `cblas_zdscal`/`cblas_csscal`) for `*` and `/` — two overloads
  distinguished by the scalar's type, so both `Z * Cplx(1,2)` and `Z * 2.0`
  work without an explicit cast.
- `newVMComplex.pas`/`newVMComplexSingle.pas` additionally overload `+`,
  `-`, `*` for mixed complex/real operands (`TVMobjZ` with `TVMobj`,
  `TVMobjC` with `TVMobjS`, both operand orders) — these can only live in
  the complex units since only they `uses` the real sibling unit. `+`/`-`
  promote the real operand via `RealToComplex`/`RealToComplexS` and
  delegate to the same-type complex operator, same rationale as the
  real units. Mixed-type `*` does **not** follow that pattern, though,
  and does not match the same-type `*` above either: `TVMobjZ * TVMobj`
  and `TVMobj * TVMobjZ` (and the `C`/`S` analogues) call
  `MatMultZ`/`MatMultC` directly — a genuine matrix product — while
  same-type `Z * Z` is element-wise. This split is deliberately exercised
  by `newVMTests.pas`'s `TestEigDecomposeSatisfiesEigenEquation`, which
  computes `Av := A * vcol` (real eigenvector matrix times complex
  eigenvector) to verify the defining equation `A*v = lambda*v` — a real
  matrix-vector product is exactly what's needed there. Whether this
  same-type-vs-mixed-type inconsistency is intentional isn't documented
  anywhere in the source; treat it as the current, tested behaviour
  rather than assuming consistency with the same-type operator.

### `Kron`/`KronS`/`KronZ`/`KronC` (Kronecker product)

Each of the four `TVMobj*` units declares a Kronecker-product function
following the `Invert`/`InvertS`/`InvertZ`/`InvertC` per-unit naming
convention: `Kron(const A, B: TVMobj): TVMobj` in `newVM.pas`, `KronS` in
`newVMSingle.pas`, `KronZ` in `newVMComplex.pas`, `KronC` in
`newVMComplexSingle.pas`. For A (m,n) and B (p,q), returns an (m*p, n*q)
result whose (i,j) block (each p×q) is `A[i,j]*B`.

No BLAS/LAPACK routine computes a Kronecker product directly, so each
block is placed via `cblas_?axpy` (`Y := alpha*X + Y`) called once per
source row of B — a block's rows aren't contiguous in the result's
row-major layout, so the single whole-buffer axpy trick `+`/`-` use
doesn't apply here. The result buffer starts zero-filled (from `Create`),
so `alpha = A[i,j]` directly deposits the scaled row with nothing to add
onto. Real units pass alpha by value (`cblas_daxpy`/`cblas_saxpy`);
complex units pass alpha by pointer to a local `TComplex16`/`TComplex8`
holding `A[i,j]` (`cblas_zaxpy`/`cblas_caxpy`), per the CBLAS complex
scalar convention noted in "CBLAS/LAPACKE calling convention gotchas"
below. Unlike `MatMult`, no dimension-compatibility assert is needed —
Kronecker product is defined for any A/B shapes.

### `Diag`/`DiagS`/`DiagZ`/`DiagC` and `Norm`/`NormS`/`NormZ`/`NormC`

Two more single-argument, per-unit functions following the same
`Invert`/`Kron` suffix naming convention (base name in `newVM.pas`, `S`/
`Z`/`C` suffixes elsewhere) rather than `overload` — unlike `Sin`/`Find`,
these aren't a shared elementwise-function family visible together under
one name in `newVMTests.pas`, they're one-argument transforms like
`Invert`.

- `Diag` turns a column vector A (n,1) into an (n,n) diagonal matrix with
  A's elements on the leading diagonal (asserts `A.Cols = 1`). No loop
  needed: diagonal element i sits at flat row-major offset `i*n+i =
  i*(n+1)`, so this is a single `cblas_?copy(n, A, 1, result, n+1)` —
  copying the source at stride 1 into the zero-filled result (from
  `Create`) at stride `(n+1)` deposits exactly the diagonal entries and
  nothing else.
- `Norm` computes the Euclidean (L2) norm of a vector A (`Rows=1` or
  `Cols=1`, same vector-only assert convention as the DCT/DST functions
  above), via `cblas_?nrm2`. The complex units' `NormZ`/`NormC` use
  `cblas_dznrm2`/`cblas_scnrm2` — CBLAS's complex-vector norm functions,
  which correctly return a real-valued `Double`/`Single` (not a complex
  number), since a Euclidean norm is always a non-negative real.
- Both `cblas_?copy` and `cblas_?nrm2` were already declared and
  cross-platform bound in `cblas.pas` (unconditionally, not gated by
  `{$IFDEF UNIX}`/`{$IFDEF WINDOWS}` the way `OneAPI.pas`'s MKL/IPP
  bindings are — see "Cross-platform library binding" below) before this
  addition, so no new external bindings were needed for either function.

### `Trace`/`TraceS`/`TraceZ`/`TraceC`

Sum of a square matrix's leading-diagonal elements (asserts `A.Rows =
A.Cols`), same suffix naming convention as `Diag`/`Norm` above. No
BLAS/LAPACK/IPP routine computes a trace directly, and IPP's `ippsSum`
only sums a *contiguous* buffer — extracting the diagonal into one first
via `cblas_?copy` (the trick `Diag` uses, in reverse) would cost an
allocation for no benefit over just summing in a loop directly - so, like
`Find`/`Gather` and `newVMI.pas`'s `Id`/`Transpose`, this is a plain loop
over `A[i,i]`. The complex units' `TraceZ`/`TraceC` return
`TComplex16`/`TComplex8` (unlike `Norm`'s always-real result, a complex
matrix's trace is generally complex, not real) accumulated by summing
`.re`/`.im` separately.

### `Det`/`DetS`/`DetZ`/`DetC` (determinant)

Determinant of a square matrix (asserts `A.Cols = A.Rows`), same suffix
naming convention as `Invert`/`Diag`/`Norm`/`Trace`. Computed via
`LAPACKE_?getrf` — the same LU factorisation (`A = P*L*U`, partial
pivoting) `Invert` already uses for `?getri` — run on a `CopyObj*`
scratch buffer so `A` itself is left untouched:

- `det(A) = det(P) * det(L) * det(U)`. `det(L) = 1` (unit lower
  triangular, never stored). `det(U)` is the product of the diagonal
  entries `getrf` leaves in the scratch buffer (L\U combined storage puts
  U, including its diagonal, in the upper triangle). `det(P) = -1` per
  row actually interchanged — checked via `ipiv[i] <> i+1`, using
  `getrf`'s pivot-array convention (1-based, matching Fortran LAPACK, even
  though the surrounding call is the row-major LAPACKE C interface).
- Unlike `Invert`, there's **no `info = 0` assert**: `Invert` must reject
  a singular matrix because the follow-up `?getri` call would fail on
  one, but `Det` has no such follow-up call, and a singular matrix has a
  perfectly well-defined determinant (zero). `getrf` reports singularity
  via `info > 0` without failing the factorisation itself, and the
  singular row's diagonal entry in the scratch buffer comes out exactly
  0, so the running product naturally lands on the correct answer with no
  special-casing (see `TestDetSingularIsZero`). The only assert is
  `info >= 0`, which only fires on an illegal-argument LAPACKE call —
  something this codebase's own dimension checks should already prevent.
- The complex units' `DetZ`/`DetC` accumulate the running product as
  `TComplex16`/`TComplex8` by hand (`result := Cplx(re*d.re - im*d.im,
  re*d.im + im*d.re)` per diagonal entry `d`), since no complex-multiply
  helper exists for raw `TComplex16`/`TComplex8` values outside the
  `TVMobjZ`/`TVMobjC` operator overloads (which operate on whole
  matrices, not two loose scalars).

### `FlipUD`/`FlipUDS`/`FlipUDZ`/`FlipUDC` and `FlipLR`/`FlipLRS`/`FlipLRZ`/`FlipLRC`

Two more single-argument, per-unit functions following the `Diag`/`Norm`/
`Trace`/`Det` suffix naming convention. Both return a new object of the
same shape as `A`; neither has a dimension assert, since row/column
reversal is defined for any shape.

- `FlipUD` reverses the order of `A`'s rows (row 0 swaps with row
  `Rows-1`, etc). No BLAS/LAPACK/IPP primitive reverses whole rows as a
  block - IPP's `ippsFlip` (see `FlipLR` below) reverses individual
  elements, not row-sized chunks, and a block's source/dest rows aren't
  related by a single fixed stride the way `Diag`'s diagonal is - so this
  copies each source row to its mirrored destination row via
  `cblas_?copy`, one call per row, the same "no block primitive -> loop of
  per-row BLAS calls" idiom `Kron` uses.
- `FlipLR` reverses the order of elements *within* each row. Unlike
  `FlipUD`, IPP has an exact primitive for this: `ippsFlip_64f`/`_32f`/
  `_64fc`/`_32fc` reverses a vector's element order into a (possibly
  different) destination buffer, so this calls it once per row with
  `len=Cols`. These four `ippsFlip_*` bindings were newly added to
  `OneAPI.pas` for this (both the Unix `external` declarations and the
  Windows procedural-type/`LoadIPPFunctions` bindings - see "Cross-platform
  library binding" below) since nothing before `FlipLR` needed them; no
  other new bindings were required. The complex variants take
  `PComplex16`/`PComplex8` in place of IPP's own `Ipp64fc`/`Ipp32fc`
  pointer types - bit-identical layout, the same interop trick used
  throughout (see `TComplex16`/`TComplex8` in "External bindings" below).

### `MergeUD`/`MergeUDS`/`MergeUDZ`/`MergeUDC` and `MergeLR`/`MergeLRS`/`MergeLRZ`/`MergeLRC`

Two-argument, per-unit functions, same suffix convention as `Kron`. `A`
and `B` are combined into one larger result; unlike `Kron`, dimensions
*do* have to agree along the non-merged axis, so each asserts that.

- `MergeUD(A, B)` stacks `A` above `B` into an `(A.Rows+B.Rows, Cols)`
  result (asserts `A.Cols = B.Cols`). Row-major storage makes this
  trivial: `A`'s rows and `B`'s rows are each already one contiguous
  block in memory, so the whole operation is just two whole-buffer
  `cblas_?copy` calls - `A`'s buffer straight into the start of the
  result, `B`'s straight after - no per-row loop needed, unlike every
  other multi-row routine in this file (`Kron`, `FlipUD`, `MergeLR`).
- `MergeLR(A, B)` places `A` to the left of `B` into an `(Rows,
  A.Cols+B.Cols)` result (asserts `A.Rows = B.Rows`). Here a source row's
  data is *not* contiguous with the next row's in the merged result
  (each result row is `A`'s row immediately followed by `B`'s row), so
  this copies both halves of each row separately via `cblas_?copy` - two
  calls per row, the same "no block primitive -> loop of per-row BLAS
  calls" idiom `Kron`/`FlipUD` use.
- No new external bindings needed for either - both are built entirely on
  `cblas_?copy`, already cross-platform bound (see `Diag`/`Norm` above for
  why that means zero Windows-specific work).

### `Reshape`/`ReshapeS`/`ReshapeZ`/`ReshapeC` and `Repmat`/`RepmatS`/`RepmatZ`/`RepmatC`

Two more per-unit functions, same suffix convention as `Diag`/`Kron`.

- `Reshape(A, NewRows, NewCols)` reinterprets `A`'s `Rows*Cols` elements as
  a `(NewRows,NewCols)` matrix (asserts `NewRows*NewCols = A.Rows*A.Cols`).
  `NewRows`/`NewCols` are typed as each unit's own `TDim`/`TDimS`/`TDimZ`/
  `TDimC` (matching what `Create` itself takes), not a plain `Integer`.
  Row-major storage means the flat element order never changes, only how
  it's carved into rows, so this is a single whole-buffer `cblas_?copy`
  into a differently-shaped result - the same "reinterpret the contiguous
  buffer" trick half of `MergeUD` already uses.
- `Repmat(A, RowReps, ColReps)` tiles `A` into a `(A.Rows*RowReps,
  A.Cols*ColReps)` result, `RowReps` copies down and `ColReps` copies
  across (asserts `RowReps > 0` and `ColReps > 0`). No BLAS/LAPACK/IPP
  primitive tiles a block, and unlike `Reshape` a tile's rows aren't
  contiguous with the next tile's, so this copies each source row into
  every `(row-tile, col-tile)` destination slot via `cblas_?copy` - the
  same "no block primitive -> loop of per-row BLAS calls" idiom
  `Kron`/`MergeLR` use, just with an extra nesting level for the two tile
  axes.
- No new external bindings needed for either - both are built entirely on
  `cblas_?copy`, same rationale as `MergeUD`/`MergeLR` above.

### `AddScalar`/`AddScalarS`/`AddScalarZ`/`AddScalarC` and `SubMatrix`/`SubMatrixS`/`SubMatrixZ`/`SubMatrixC`

Two more per-unit functions, same suffix convention as `Diag`/`Kron`.
Originally written as demo-local helpers in
`demos/Chebyshev/ChebBVP_FPC/uBVPMain.pas` (and `AddScalar` duplicated
again in `demos/Chebyshev/NormalIntegration/uNormMain.pas`), first
promoted into `newVM.pas` alone once a second demo needed the same logic,
then extended to the other three units on request even though no
complex/single-precision caller exists yet - both demos now call the
`newVM.pas` versions instead of their own copies.

- `AddScalar(A, K)`/`AddScalarS`/etc add the scalar `K` to every element
  of `A`, returning a new same-shape result (no dimension assert - valid
  for any shape). There's no `'+'`/scalar operator overload to fall back
  on (only `'*'`/`'/'` accept a plain scalar - see "OPERATOR OVERLOADS" in
  each unit's own header comment), so these are the named-function
  equivalent, via IPP's `ippsAddC_64f_I`/`_32f_I`/`_64fc_I`/`_32fc_I`
  (in-place add-a-constant) on a `CopyObj*` scratch buffer - the same
  idiom the `'*'`/`k` and `'/'`/`k` scalar operators already use
  (`ippsDivC_64f_I`/`_32f_I` for `'/'`). `ippsAddC_64f_I`/`_32f_I` were
  already bound in `OneAPI.pas` before this addition (alongside
  `ippsSubC_64f_I`/`ippsMulC_64f_I_L`), just never called from
  `newVM.pas`/`newVMSingle.pas` themselves; `ippsAddC_64fc_I`/`_32fc_I`
  (the complex analogues) are genuinely new bindings, added for this - see
  "Cross-platform library binding" below for the by-value-complex-struct
  detail that made those two worth extra care. The complex units'
  `AddScalarZ`/`AddScalarC` follow the same two-overload convention as
  their `'*'`/`'/'` operators: a native `TComplex16`/`TComplex8` constant,
  or a plain `Double`/`Single` treated as a real scalar - promoted via
  `Cplx`/`Cplx8` to add only to each element's real part, leaving
  imaginary parts untouched (`AddScalarZ(A, K: Double)` is a one-line
  wrapper around `AddScalarZ(A, Cplx(K, 0))`), rather than a third IPP
  binding of its own.
- `SubMatrix(A, R0, C0, RCount, CCount)`/`SubMatrixS`/etc extract the
  `(RCount,CCount)` submatrix of `A` starting at `(R0,C0)` (asserts the
  requested block stays within `A`'s bounds; `RCount`/`CCount > 0` is
  enforced by `Create` itself, so no separate check is needed for that).
  No loop needed despite the submatrix's rows not being contiguous in
  `A`'s buffer: `LAPACKE_dlacpy`/`_slacpy`/`_zlacpy`/`_clacpy` take
  independent `lda`/`ldb` (leading dimension) parameters for their source
  and destination, so pointing at `A`'s data offset by `R0*A.Cols+C0` with
  `lda=A.Cols` (`A`'s own row stride, not `CCount`) does the strided copy
  in a single call - the same "differing leading dimensions do the
  strided work" trick `CopyObj`'s own whole-matrix copy (`lda=ldb=A.Cols`)
  is simply a degenerate case of. All four `lacpy` variants were already
  bound (Unix and Windows alike) before this addition - `CopyObjS`/`Z`/`C`
  already used them for their own whole-matrix copies - so `SubMatrixS`/
  `Z`/`C` needed no new binding work at all, unlike `AddScalarZ`/`C`.

### Elementwise math functions

Each unit also declares plain (non-operator) functions `Sin`, `Cos`, `Tan`,
`Sinh`, `Sqr`, `Sqrt`, `Exp`, `Ln` — each takes a `TVMobj*` and returns a
new one of the same dimensions with the function applied to every element.
Backed by MKL VML's plain `vd*`/`vs*`/`vc*`/`vz*` entry points (declared in
`OneAPI.pas` right after the pre-existing `vmd*` block — deliberately a
*different* function family, see the comment there: the `vmd*`/`vms*`/
`vmc*`/`vmz*` names take an extra trailing VML-mode argument that those
existing bindings don't pass, so don't extend that block by analogy;
extend the `vd*`/`vs*`/`vc*`/`vz*` block instead).

These are declared `overload` in every unit, which is load-bearing, not
decorative: without it, each unit's `Sin`/`Cos`/etc. would simply *hide*
`System`/`Math`'s versions (and each other's, across units) rather than
extending them, since plain identifier redeclaration in Pascal shadows by
default. `overload` is what lets `newVMTests.pas` — which `uses` all four
`TVMobj*` units together — call `Sin(dblA)`, `Sin(sngA)`, `Sin(cplA)`,
`Sin(cplsA)` and have each resolve to the right unit's version purely by
argument type, with the plain-numeric `Sin` still reachable too.

Complex `Sqrt`/`Ln` return principal-branch values (standard for MKL VML);
there's no attempt to unwrap branch cuts.

### FFT/DCT/DST functions (`fftw3.pas`)

`fftw3.pas` is a runtime (`dlopen`-based) binding to FFTW3, double
precision (`libfftw3`, `fftw_` prefix) and single precision (`libfftw3f`,
`fftwf_` prefix) — see "External bindings" below for why it loads at
runtime via `LoadLibrary`/`GetProcedureAddress` (mirroring `cblas.pas`)
rather than link-time `external`. It self-initializes both libraries from
its own `initialization` section (`InitializeFFTW3`), so no explicit
init call is needed anywhere else, unlike `InitializeCBLAS`.

Each of the four `newVM*` units adds functions built on top of it,
vector-only (`A.Rows=1` or `A.Cols=1`; asserts otherwise) and never
mutating their input (every FFTW plan is created with
`FFTW_PRESERVE_INPUT`, matching this library's general non-mutating
convention):

- `newVM.pas`/`newVMSingle.pas` (real): `DCT1`..`DCT4` and `DST1`..`DST4`,
  one per r2r transform kind (FFTW's `REDFT00/10/01/11` and
  `RODFT00/10/01/11` respectively). These are **unnormalized**, matching
  FFTW's own convention - e.g. `DCT1(DCT1(x)) = x * 2*(N-1)` (DCT-I is
  self-inverse up to that scale); `DCT2`/`DCT3` are each other's inverse
  up to `2*N`; `DCT4`/`DST4` are each self-inverse up to `2*N`; `DST1` is
  self-inverse up to `2*(N+1)`. Get the scale factor wrong and a
  round-trip test will fail by orders of magnitude, not silently drift -
  see `newVMTests.pas`'s `TestDCT*RoundTrip`/`TestDST*RoundTrip` for the
  exact factor per kind, empirically verified there.
- `newVMComplex.pas`/`newVMComplexSingle.pas` (complex): `FFT_R2C`
  (real vector of length N -> FFTW's packed half-spectrum, length
  `N div 2 + 1`, exploiting conjugate symmetry), `FFT_C2R` (the inverse -
  takes the target real length `N` explicitly, since the half-spectrum's
  own length doesn't disambiguate even vs odd `N`), and `FFT`/`IFFT`
  (complex-to-complex, forward/inverse). Unlike the raw DCT/DST functions
  above, these **are normalized** (`FFT_C2R` and `IFFT` divide by `N`), so
  `FFT_C2R(FFT_R2C(x), N) = x` and `IFFT(FFT(x)) = x` hold directly - no
  manual rescaling needed at call sites.
- Marked `overload` throughout, same reason as `Sin`/`Cos`/etc: all four
  units' versions of these names are visible together in
  `newVMTests.pas`, and would otherwise just hide each other.

Ported the original raw-FFTW3 spectral-differentiation demo
(`/home/howard/projects/Lazarus/fftw3`) to `DCT1` for
`demos/SpectralDiff/` - see the "`demos/`" section below.

### `newvmconfigure.lpr`/`newVMConfig.inc` (platform/library detection, PUREPASCAL fallback)

Every `newVM*.pas` unit's `{$IFDEF UNIX}{$Linklib 'mkl_rt.so'}...{$ENDIF}`
block (and `OneAPI.pas`'s own `mkl_rt.so`/`ippcore.so`/`ippvm.so`/`ipps.so`
ones) previously assumed MKL/IPP/OpenBLAS were simply present, unconditionally,
on any machine that would ever build this project - true on this dev machine,
but not guaranteed elsewhere (a different architecture, a machine without the
Intel oneAPI runtime installed, etc). `{$IFDEF}`/`{$Linklib}` are resolved at
*compile* time, but "is `libmkl_rt.so` actually installed on this machine" is
a fact about the *build* machine - not something the compiler can know on its
own. `newvmconfigure.lpr` bridges that gap:

- It's a small standalone console program (only `uses SysUtils, DynLibs` -
  deliberately no dependency on `cblas.pas`/`OneAPI.pas`/`fftw3.pas`/
  `newVM*.pas` themselves, since it has to build and run on a machine that
  might have *none* of MKL/IPP/OpenBLAS/FFTW installed) - build it once with
  a plain `fpc newvmconfigure.lpr` (no `lazbuild`/`.lpi` needed, unlike the
  rest of this project - see its own header comment for why), then run
  `./newvmconfigure` from the repo root before building `newVMtest.lpi` (or
  after installing/removing any of these libraries on this machine).
- OS and CPU architecture detection is free at compile time via FPC's own
  built-in macros (`WINDOWS`/`LINUX`/`DARWIN`, `CPUX86_64`/`CPUAARCH64`/
  `CPUARM`/`CPUI386`) - the tool just relays them into `PLATFORM_*` defines
  so the generated file documents what it was generated for. Library
  presence is genuinely runtime-only, so it's probed via `LoadLibrary`
  (`DynLibs`) - try to `dlopen` each candidate name, unload again
  immediately if it succeeds - the exact same technique `cblas.pas` already
  uses for OpenBLAS (`TryInitializeCBLAS`/`LoadAddresses`) and `fftw3.pas`
  uses for FFTW, just run once ahead of the real build rather than every
  time the built program starts. IPP requires all three of
  `ippcore`/`ippvm`/`ipps` to be found; FFTW requires both the double
  (`libfftw3`) and single (`libfftw3f`) libraries.
- The result is written to `newVMConfig.inc`: `{$DEFINE HAVE_OPENBLAS}`/
  `HAVE_MKL`/`HAVE_IPP`/`HAVE_FFTW` per library actually found, plus
  `PLATFORM_*` defines, plus a derived `{$DEFINE PUREPASCAL}` set whenever
  *any* of OpenBLAS/MKL/IPP (all three of which the "core" linear algebra of
  all four `TVMobj*` units genuinely calls into - `cblas_*`, `LAPACKE_*`/
  `vd*`/`vsl*`, and `ipps*` respectively) is missing. FFTW absence does
  *not* set `PUREPASCAL` - it drives its own, separate `HAVE_FFTW`-gated
  fallback for DCT/DST/FFT instead (a direct O(N²) evaluation - see "FFT/
  DCT/DST fallback" below), independent of whether OpenBLAS/MKL/IPP are
  present. The generated file uses `//` line comments throughout, never
  a `{ ... }` block comment - Pascal block comments don't nest, so a
  generated (or hand-written) comment that happens to mention a real
  `{$IFDEF ...}` directive by name inside a `{ }` block truncates the
  comment at its first `}` and feeds the rest of the sentence to the
  compiler as code; hit and fixed (in both `newvmconfigure.lpr`'s own
  comment-writing code and in `newVM.pas`'s hand-written header comment
  introducing its `{$I newVMConfig.inc}`) while building this.
- `newVMConfig.inc` is a per-machine build artifact in spirit (regenerate
  it after moving to a different machine or changing what's installed) but
  is currently committed with this dev machine's detected values (all four
  libraries present) as a working default, so a fresh checkout still builds
  out of the box without remembering to run `newvmconfigure` first; the
  binary `newvmconfigure`/`newvmconfigure.exe` itself is `.gitignore`d,
  same as `newVMtest`/`newVMtest.exe`.
- `OneAPI.pas` and `newVM.pas` both `{$I newVMConfig.inc}` near their top
  and additionally gate their pre-existing `{$IFDEF UNIX}{$Linklib ...}`
  blocks on `HAVE_MKL`/`HAVE_IPP` (`OneAPI.pas` for its own MKL/IPP
  `$Linklib`s; `newVM.pas` for its separate `mkl_rt.so`+`pthread`+`m`+`dl`
  preload block - see "External bindings" above for why that one exists).
  Harmless/unchanged on this machine, where both are always found true;
  necessary groundwork for a machine where they aren't.

`newVM.pas` (double-precision real) is the **reference implementation** of
the resulting `PUREPASCAL` fallback - every routine that would otherwise
call into `cblas`/`OneAPI` now has a second, plain-Pascal-only body,
individually `{$IFDEF PUREPASCAL}`-guarded right next to the
library-backed one, so both stay visible side by side rather than one
replacing the other:

- `LinearSolve`/`Invert`/`Det` (the three routines LAPACKE's `dgetrf`
  backed) share a hand-written `PurePascalLU`/`PurePascalLUSolve` pair -
  in-place LU decomposition with partial pivoting, deliberately matching
  `LAPACKE_dgetrf`'s own storage convention (unit lower-triangular `L`
  below the diagonal, `U` on/above it, both packed into one buffer) and
  its 1-based `ipiv` convention, so `Det`'s sign-from-pivots logic
  (`ipiv[i] <> i+1`) and `LinearSolve`'s `A.fIpiv`/`A.LU` caching contract
  work unchanged regardless of which body actually ran. `Invert`'s
  fallback solves `A*X=I` against an identity right-hand side via the same
  two routines, rather than porting LAPACKE's dedicated `dgetri` algorithm.
  A singular matrix surfaces as an exactly-zero pivot (matching
  `LAPACKE_dgetrf`'s `info>0` case) that `Det` multiplies through to a
  correct zero result with no special-casing, same as the library-backed
  version; `LinearSolve`'s fallback has no illegal-argument path to report
  (unlike `LAPACKE_dgesv`), so it always returns 0.
- `fillRandom` has no VSL to call, so it generates via a fixed-seed
  Box-Muller transform over FPC's own `Random()` instead of
  `vdRngGaussian` - reseeding `RandSeed` to the same constant (777) on
  every call preserves the tested contract (`TestFillRandomDeterministic`
  et al: two same-sized `fillRandom` calls produce bit-identical data, via
  `=`) even though the specific values differ from `vdRngGaussian`'s own.
- Every other routine (`MatMult`, `Kron`, `Diag`, `Norm`, `Trace` -
  already a plain loop either way -, `FlipUD`/`FlipLR`,
  `MergeUD`/`MergeLR`, `Reshape`, `Repmat`, `AddScalar`, `SubMatrix`, `Id`,
  `linspace`, `Transpose`, `CopyObj`, all six operators, `mulObj`, and the
  elementwise `Sin`/`Cos`/`Tan`/`Sinh`/`Sqr`/`Sqrt`/`Exp`/`Ln` family) is a
  direct triple/double/single loop or a `Move` in place of the
  `cblas_?copy`/`LAPACKE_?lacpy` call it replaces - no LU dependency
  needed. The elementwise functions call `System.Sin`/`Math.Tan`/etc
  explicitly (rather than bare `Sin`/`Tan`) purely for readability at the
  call site; Pascal's overload resolution already picks the scalar
  `Double` version correctly either way, since the enclosing function's
  own parameter type is `TVMobj`, not `Double` - no actual ambiguity.
- **Verified**, not just written to compile: with `PUREPASCAL` forced on
  in `newVMConfig.inc` (independent of what's actually installed - MKL/IPP/
  OpenBLAS stay linked for the *other* three `TVMobj*` units regardless),
  all 59 of `TVMobjTests`' own tests pass unchanged - the same known-value
  and round-trip checks (`TestMatMultKnownValues`,
  `TestLinearSolveReusesFactorization`, `TestInvertRecoversIdentity`,
  `TestDetKnownValues`/`TestDetSingularIsZero`, `TestKronKnownValues`,
  etc) that already exercise the library-backed path, now exercising the
  plain-Pascal one instead. The full 256-test suite (all five `TVMobj*`/
  `TVMobjI` type test cases together) passes both with `PUREPASCAL` forced
  on and back in its normal (all-libraries-found) state.
- DCT/DST (`r2rTransform` and the 8 `DCT1`..`DST4` functions built on it)
  *do* have a fallback, gated on `{$IFDEF HAVE_FFTW}` rather than
  `PUREPASCAL` - FFTW availability is a separate concern from BLAS/LAPACK/
  IPP, so this uses its own independent define (see `newvmconfigure.lpr`'s
  own header comment and the `newVMConfig.inc` section above). `PPr2rTransform`
  evaluates each of the 8 kinds via its exact FFTW-documented unnormalized
  trigonometric-sum formula directly (e.g. DCT-II: `Y[k] = 2*sum_j
  X[j]*cos(pi*(j+0.5)*k/N)`) - a direct O(N²) summation, not a ported fast
  transform: DCT/DST have no radix-2-simple fast algorithm the way a plain
  complex FFT does (see `newVMComplex.pas`'s own FFT fallback below), and
  this is a fallback path where O(N²) correctness/simplicity is an
  acceptable trade against speed, same rationale as `MatMult`'s own plain
  triple-loop `PUREPASCAL` body above. Verified against the *exact* same
  scale-factor contracts `newVMTests.pas`'s round-trip tests already check
  (e.g. `DCT1(DCT1(x)) = x*2*(N-1)`), run with `HAVE_FFTW` forced off.

The same treatment has since been rolled out to all three sibling units -
`newVM.pas` was the proof-of-concept, not the final scope:

- **`newVMSingle.pas`** (single-precision real) mirrors `newVM.pas`
  routine-for-routine, `Single`-typed throughout (`PurePascalLUS`/
  `PurePascalLUSolveS`, the same fixed-seed-777 Box-Muller `fillRandom`,
  etc) - there's no real conceptual difference from the double-precision
  version, just the element type and the `cblas_s*`/`lapacke_s*`/`vs*`/
  `ippsAddC_32f_I`/etc calls it replaces.
- **`newVMComplex.pas`** (double-precision complex, `TVMobjZ`/
  `TComplex16`) and **`newVMComplexSingle.pas`** (single-precision
  complex, `TVMobjC`/`TComplex8`) needed genuinely new work, not just a
  type-swapped copy: a small block of complex-arithmetic helpers
  (`CAddZ`/`CSubZ`/`CMulZ`/`CDivZ`/`CAbsSqZ` and the `C`-suffixed
  single-precision analogues - plain functions over `TComplex16`/
  `TComplex8`, since those record types have no operator overloads of
  their own outside `TVMobjZ`/`TVMobjC`'s whole-matrix operators)
  underpins everything else in both units:
  - `PurePascalLUZ`/`PurePascalLUC` use `CAbsSqZ`/`CAbsSqC` (magnitude
    *squared*, monotonic in `|z|` so pivot-comparison order is unaffected,
    and cheaper than an actual `Sqrt`) in place of `Abs()` for pivot
    selection, and complex multiply/subtract/divide (`CDivZ`/`CDivC` -
    the standard `a*conj(b)/|b|^2` formula, self-contained rather than
    calling the unit's own later `ReciprocalZ`/`ReciprocalC`, since the LU
    routines have to come before `LinearSolveZ`/`InvertZ`/`DetZ`, well
    before those functions' own position further down each file) in place
    of real division for the elimination step - otherwise an exact
    structural match for `PurePascalLU`/`PurePascalLUSolve`.
  - The elementwise complex transcendentals have no VML equivalent to
    fall back from directly (`vzSin`/`vzCos`/etc take a complex buffer
    in one call; there's no "give me the scalar formula" primitive), so
    each got its own closed-form principal-branch implementation:
    `Exp(a+bi) = e^a(cos b + i sin b)`, `Ln(a+bi) = ln|z| + i*atan2(b,a)`,
    `Sin(a+bi) = sin(a)cosh(b) + i cos(a)sinh(b)`,
    `Cos(a+bi) = cos(a)cosh(b) - i sin(a)sinh(b)`,
    `Sinh(a+bi) = sinh(a)cos(b) + i cosh(a)sin(b)`,
    `Tan(z) = Sin(z)/Cos(z)` (via `CDivZ`, no separate closed form), and
    `Sqrt` via the standard `r=|z|, re=sqrt((r+a)/2),
    im=sign(b)*sqrt((r-a)/2)` principal-square-root construction. `Sqr`
    needed no new formula either way - both the library-backed body
    (`vzMul(A,A,...)`, since MKL VM has no `vzSqr`) and the PUREPASCAL one
    (`CMulZ(A[i],A[i])` in a loop) were already "multiply A by itself".
  - `RealToComplex`/`GetRealPart`/`GetImagPart` (and their `S`-suffixed
    single-precision analogues) - previously a `cblas_?copy` with a
    stride-2 source/destination exploiting `TComplex16`/`TComplex8`'s
    "two contiguous reals" layout - become a plain per-element loop
    reading/writing `.re`/`.im` directly; `SplitComplex`/`SplitComplexS`
    needed no change at all, since they're just a two-line wrapper calling
    the other two.
  - The **mixed** real/complex operators (`TVMobjZ + TVMobj`, `TVMobjZ *
    TVMobj`, etc, and the `C`/`TVMobjS` analogues) needed **no changes** -
    they already delegate to `RealToComplex`/`RealToComplexS` plus either
    the same-type operator or `MatMultZ`/`MatMultC`, so once those have
    PUREPASCAL bodies the mixed operators inherit correctness for free.
  - `EigDecompose`/`EigDecomposeS` (`LAPACKE_dgeev`/`sgeev`) *do* now have a
    `PUREPASCAL` fallback (`PurePascalEigHqr2`/`PurePascalEigHqr2S`), ported
    from a general real-matrix eigenvalue/eigenvector algorithm the user
    supplied in a local `LMath` directory (`LMath/ULineAlgebra/ubalance.pas`,
    `uelmhes.pas`, `ueltran.pas`, `uhqr2.pas`, `ubalbak.pas`) - itself a
    Pascal translation of the classic EISPACK Balance/Elmhes/Eltran/Hqr2/
    Balbak pipeline, the same algorithm family LAPACK's `dgeev` descends
    from. Ported close to line-for-line - including `Hqr2`'s own
    goto-heavy control flow ("a crude translation, many gotos kept" per
    LMath's own comment on it) rather than risk a bug restructuring 400
    lines of QR-iteration into structured control flow - onto local
    1-based-usable scratch arrays (index 0 unused, matching LMath's own
    `Lb=1` convention) that only the outer wrapper converts to/from newVM's
    usual 0-based row-major buffers. `Hqr2`'s own eigenvectors are
    documented unnormalised, unlike `LAPACKE_dgeev`'s unit-Euclidean-norm
    ones, so the wrapper normalises each eigenvector (or a
    complex-conjugate pair's two columns together) before returning, on
    the packed real/imaginary column-pair form both paths share - keeping
    `EigDecompose`'s own unpacking loop identical and correct either way.
  - `FFT_R2C`/`FFT_C2R`/`FFT`/`IFFT` also now have a fallback, gated on
    `HAVE_FFTW` like `newVM.pas`'s DCT/DST above rather than `PUREPASCAL`.
    `PPDirectDFT`/`PPDirectDFTS` evaluate a direct O(N²) DFT - deliberately
    *not* a ported radix-2 fast FFT (e.g. LMath's own `uRegression/ufft.pas`,
    which only handles power-of-two lengths): a direct summation is simpler
    and works for *any* N, matching FFTW's own generality, which matters
    since these functions accept arbitrary vector lengths. `FFT`/`IFFT` call
    it directly; `FFT_R2C` computes only the `N div 2 + 1` needed
    half-spectrum bins; `FFT_C2R` expands the half-spectrum to the full
    N-point spectrum via conjugate symmetry (`X[N-k] = conj(X[k])`, the same
    assumption FFTW's own C2R transform makes) before inverse-transforming.
    One real bug surfaced and fixed while verifying this: `FFT_C2R`'s first
    draft passed the same buffer as both input and output to the direct-DFT
    routine, so later output indices silently corrupted input the loop's
    earlier iterations still needed - caught immediately by
    `TestFFTR2CC2RRoundTrip` failing (`expected: <2> but was: <-1>`) the
    first time this ran with `HAVE_FFTW` forced off; fixed by using a
    separate output array.
- **Verified** the same way as `newVM.pas`: with `PUREPASCAL` forced on for
  all four units simultaneously, the full test suite (262 tests as of this
  writing, across `TVMobjTests`/`TVMobjSTests`/`TVMobjZTests`/`TVMobjCTests`/
  `TVMobjITests` - including `TestEigDecomposeSatisfiesEigenEquation`, which
  under this config now exercises `PurePascalEigHqr2` itself, not
  `LAPACKE_dgeev`, since `EigDecompose` gained its own `PUREPASCAL` branch -
  see above) passes with 0 errors/0 failures, and again passes unchanged
  back in the normal (all-libraries-found) state. Because `HAVE_FFTW` is
  now an independent define from `PUREPASCAL` (see the DCT/DST/FFT fallback
  notes above), all **four** combinations of the two were exercised, not
  just "both on" and "both off": `PUREPASCAL` off/`HAVE_FFTW` off (FFTW
  missing only), `PUREPASCAL` on/`HAVE_FFTW` on (BLAS/LAPACK/IPP missing
  only), and the two uniform states - all 262/262 in every combination.


#### The define set, as it stands now

`newVMConfig.inc` has grown well past the original
`HAVE_OPENBLAS`/`HAVE_MKL`/`HAVE_IPP`/`HAVE_FFTW` + `PUREPASCAL` set
described above, in two directions: more BLAS/LAPACK backends (so a Mac
or an Arm machine with no Intel libraries can still run accelerated
bodies rather than dropping wholesale to plain Pascal), and the two GPU
backends. `newvmconfigure.lpr` probes per-platform candidate name lists
(Windows `.dll` / Darwin `.dylib` + framework paths / Unix `.so`), and
leaves a list empty rather than guessing where a naming convention hasn't
been confirmed against a real install — which is why, for example,
`HAVE_ARMPL` simply never fires on Windows.

Detected directly:

| Define | Means |
|---|---|
| `HAVE_OPENBLAS` | OpenBLAS found |
| `HAVE_ACCELERATE` | Apple Accelerate/vecLib found (Darwin only) |
| `HAVE_ARMPL` | Arm Performance Libraries (`libarmpl_lp64`) found |
| `HAVE_MKL` | MKL found |
| `HAVE_IPP` | all three of ippcore/ippvm/ipps found |
| `HAVE_FFTW` | both double and single FFTW found |
| `HAVE_OPENCL` | OpenCL **and** clFFT both found — gates `newVMCL.pas` |
| `HAVE_METAL` | Metal **and** MPSGraph found **and** AArch64 — gates `newVMMetal.pas` |

Derived from those:

- **`HAVE_BLAS`** — any of OpenBLAS / Accelerate / ArmPL.
- **`HAVE_LAPACKE`** — a `LAPACKE_*` implementation from *either* MKL or
  ArmPL (which exports a standard `LAPACKE_*` ABI alongside its `cblas_*`
  one). Deliberately **narrower than `PUREPASCAL`**: it gates only
  `LinearSolve`/`Invert`/`Det`/`Id`/`EigDecompose` — the routines that call
  `LAPACKE_*` and nothing else — so ArmPL alone can take those off the
  plain-Pascal path while the VML/VSL/IPP-dependent routines
  (`Sin`/`Cos`/…, `fillRandom`, `linspace`/`AddScalar`/`FlipLR`/…) stay on
  their fallback, ArmPL providing no equivalent under matching names.
- **`PUREPASCAL`** — unchanged in meaning: set when *any* of
  OpenBLAS/MKL/IPP is missing.
- **`PUREPASCAL_BLAS`** — a finer-grained sibling, for the subset of
  `newVM.pas` whose library-backed body calls **only** `cblas_*` (no
  LAPACKE/ipps/vd*/vsl*): `MatMult`, `Kron`, `Diag`, `Norm`, `FlipUD`,
  `MergeUD`/`MergeLR`, `Reshape`, `Repmat`, and the `+`/`-`/unary-`-`/
  scalar-`*` operators. Those run their real accelerated body whenever
  *any* CBLAS-compatible backend is present, even on a machine that sets
  `PUREPASCAL` for everything else.

Both `PUREPASCAL` defines follow the same convention as the original: left
**undefined** when a backend is found, never defined to False.

`HAVE_METAL` is explicitly narrowed to AArch64 in the tool rather than
inferred from the frameworks alone — Intel Macs carry both frameworks too,
so their presence isn't itself an Apple Silicon signal.

**Two non-Intel backends now sit behind `cblas.pas`**, which is no longer
just the `h2pas` OpenBLAS binding the "External bindings" section
describes:

- **ArmPL** is wired in through the `CBLASLib` constant, *preferred over*
  OpenBLAS when both are present, and additionally supplies `LAPACKE_*`
  through `OneAPI.pas`'s own `LoadArmPLLAPACKEFunctions` (a
  `GetArmPLHandle`/`ArmPLProc` loader mirroring the MKL one). ArmPL spells
  those symbols `LAPACKE_*` exactly, so unlike the MKL loader the casing
  needs no special handling. When ArmPL is absent these vars are simply
  never assigned and stay nil, which is safe because `HAVE_LAPACKE` gates
  every call site.
- **Accelerate** is selected as `CBLASLib` on Darwin only when OpenBLAS
  *isn't* present (it defers to OpenBLAS, unlike ArmPL which wins). Two
  awkward details it forces, both handled at the `newVM.pas` call site
  rather than hidden in the binding:
  - Accelerate exposes **classic Fortran LAPACK only** — column-major,
    pointer arguments, trailing underscore (`dgetrf_`/`dgetri_`/
    `dgetrs_`), with no row-major `LAPACKE_*` C wrapper anywhere in the
    macOS SDK. `LinearSolve`/`Invert`/`Det` call these three directly from
    a nested `HAVE_ACCELERATE` guard *inside* their `PUREPASCAL` branch,
    doing the row-major/column-major adaptation themselves; the
    declarations stay a literal, unadapted mirror of the Fortran
    signatures. They're loaded via their own `LoadLibrary` call,
    independent of whatever `CBLASLib` resolved to, so they can't silently
    depend on OpenBLAS having been chosen for the plain CBLAS symbols.
  - **vForce and vDSP stand in for MKL VML and IPP**: `vvsin`/`vvcos`/
    `vvtan`/`vvsinh`/`vvsqrt`/`vvexp`/`vvlog` cover the elementwise
    transcendentals, and `vDSP_vsqD`/`vmulD`/`vrampD`/`vrvrsD`/`vsaddD`/
    `vsdivD` cover `Sqr`/`mulObj` plus the IPP-only routines
    (`linspace`/`FlipLR`/`AddScalar`/the `/` operator). Their calling
    conventions differ from each other *and* from MKL's, so they're worth
    checking against the header before extending: **vForce** takes output
    pointer first, then input, then a **pointer** to the count (the
    reverse of MKL's `vd*(n, x, y)`, with `n` by reference); **vDSP**
    takes everything **by value**, including 8-byte strides and counts.
    One asymmetry: `vDSP_vrvrsD` reverses a single array **in place** (no
    separate src/dst the way `ippsFlip_64f` has), so `FlipLR`'s Accelerate
    body copies the row into the result first and reverses it there.


### `newVMI.pas` (integer index array/matrix)

`newVMI.pas` provides `TVMobjI`, an integer-valued companion to the four
`TVMobj*` types above, for index operations (pivot vectors, index lists)
rather than linear algebra. It mirrors as much of the "core object shape"
(see above) as MKL/IPP's integer support allows - `create`, `Element[r,c]`
(via its own `calcoffsetI`), `writeMatrix`, `DataPtr`, `Rows`/`Cols`,
`fillRandom`, `Id`, `Transpose`, `CopyObjI`, `linspace` - plus `Gather`
(see below), which has no analogue in the other four units - but is
*deliberately not* a fifth member of the four-way duplicated family above:
there is no `MatMult`/`LinearSolve`/`Invert`, no operator overloads, and no
elementwise VML functions, since BLAS/LAPACK/VML have no integer datatype
to back them with.

Where the underlying library has no integer entry point, the method falls
back to a plain Pascal loop instead of an MKL/IPP call, unlike the other
four units' equivalents:
- `Id` and `Transpose` are plain loops - there is no `LAPACKE_?laset` or
  `MKL_?imatcopy` for integers (only s/d/c/z exist for the latter).
- `fillRandom(loBound, hiBound: Integer)` - unlike the other units'
  no-argument `fillRandom` (always fixed-seed continuous N(0,1)), integers
  have no such continuous fill, so this takes explicit bounds and generates
  fixed-seed (777) uniform integers in `[loBound, hiBound)` via MKL VSL's
  `viRngUniform` - the integer analogue of `vdRngGaussian`/`vsRngGaussian`.
- `linspace(Start, increment: Integer)` - integer arithmetic sequence via
  IPP's `ippsVectorSlope_32s`, the integer sibling of
  `ippsVectorSlope_64f`/`_32f` used by `newVM.pas`/`newVMSingle.pas`.
- `CopyObjI` - via IPP's `ippsCopy_32s`, the integer sibling of
  `ippsCopy_64f`.

**Gotcha, confirmed against the real `ipps.h`:** unlike
`ippsVectorSlope_64f`/`_32f` (whose `offset`/`slope` match the output
type), `ippsVectorSlope_32s`'s `offset`/`slope` parameters are `Ipp64f`
(**Double**), not `Ipp32s` - only the destination buffer is `Ipp32s`
(`PInteger`). Declaring them as `Integer` compiles fine but silently
corrupts the result (observed: asking for `linspace(10, 2)` produced
`46241` instead of `10` in element 0) rather than raising any error,
because it's a calling-convention/register-class mismatch, not a type
error the compiler can catch. If a future integer-typed IPP/MKL binding
misbehaves the same way (right value shape, wrong values), check the real
header for this pattern before assuming the bug is somewhere else.

`newVMI.pas` also declares `TVMCompareOp` (`cmpEQ`/`cmpLT`/`cmpLE`/
`cmpGT`/`cmpGE`) here rather than duplicating it in each real unit, since
two same-named enums declared in units used together (as `newVMTests.pas`
does — `uses ... newVM, newVMSingle, ... newVMI`) would collide. See
"`Find`/`Gather` (element search)" below for what uses it.

### `Find`/`Gather` (element search)

`newVM.pas`/`newVMSingle.pas` each declare `Find(const A: TVMobj*; Op:
TVMCompareOp; Value: Double/Single): TVMobjI` (marked `overload`, same
reason as `Sin`/`Cos`/etc above — both units' versions are visible
together in `newVMTests.pas`). It compares every element of A against
Value using Op and returns a same-shape `TVMobjI` with 1 where the
criterion holds, 0 elsewhere. No IPP/MKL primitive produces a comparison
mask — IPP's `ippsThreshold*` family clips values in place, it doesn't
emit a 0/1 mask — so this is a plain element loop, same rationale as this
unit's own `Id`/`Transpose` loop fallbacks. Both real units `uses newVMI`
for `TVMobjI`/`TVMCompareOp` (no cycle: `newVMI.pas` doesn't depend on
either real unit).

`Gather(const A: TVMobjI): TVMobjI`, in `newVMI.pas` itself, is the
complement — typically fed `Find`'s output, it returns a 1-row `TVMobjI`
containing the row-major linear index (`calcoffsetI` convention) of every
non-zero element of A, in ascending order. Also a plain loop (no MKL/IPP
compaction primitive exists either). It lives here rather than in the
real units since it operates purely on `TVMobjI`. Asserts if A has no
non-zero elements, since `TVMobjI.Create` disallows a zero-length result
— there is no "empty index list" representation in this type.

### `newPolymath.pas` (`TPolynomial`, and least-squares fitting over `TVMobj`)

`newPolymath.pas` is a polynomial type - `TPolynomial`, a record holding
`P(x) = a0 + a1*x + ... + an*x^n` as a dynamic array of `Double`
coefficients, `FCoeff[i] = ai`, with arithmetic/calculus/division
operators and methods on it (see its own header comment). It was written
as a Delphi unit ("Modern Delphi Polynomial Mathematics Library") and
brought into this repo to gain one thing from newVM: a least-squares fit
to data held in a `TVMobj` vector. Two consequences of that origin are
worth knowing before touching it:

- **It is `{$mode delphi}` but was never compiled by FPC before `Fit`
  was added**, and three things had to change to get it through:
  `System.SysUtils`/`System.Math`/`System.Generics.Collections` become
  the plain FPC unit names (FPC has no default unit-scope mapping
  without `-FN`); the record helper's `DivideBy` has to be called as
  `Self.DivideBy` from inside the record's own `Modulus` method (FPC
  doesn't search helpers for a bare identifier there); and the unit is
  named `newPolymath` to match its filename, as every other unit here
  does, so a case-sensitive filesystem can find it.
- **FPC does not hand a record-returning function a fresh, zeroed
  `Result`.** `Result` is the caller's destination variable (or a reused
  temporary) by hidden reference, so `SetLength(Result.FCoeff, N)` keeps
  whatever coefficients were already there. Every routine that
  accumulated into, or only partly filled, its result (`Add`,
  `Subtract`, `Multiply`, `Shift`, `Reverse`) silently relied on zeros
  and had to be changed to build into a local array and assign it to
  `Result.FCoeff` at the end - which as a side effect makes `P := P * Q`
  safe when `Result` aliases an operand. Found, not reasoned out: a
  probe program showed `P*Q` with stale low-order terms and `DivideBy`
  looping forever on a `Shift` result with garbage in it, and the FPCUnit
  runner hung in the first `DivideBy` test. The remaining "function
  result variable of a managed type does not seem to be initialized"
  warnings on `Zero`/`One`/`Negative`/scalar `Multiply`/`Integral` are
  benign - those assign every element after `SetLength`, in place, with
  the same index on both sides.

**`TPolynomial.Fit(const X, Y: TVMobj; Degree: Integer): TPolynomial`**
(a static class function, alongside `Zero`/`One`) fits a polynomial of
the given degree to the `N` points `(X[i], Y[i])` in the least-squares
sense. `X` and `Y` are vectors - row `(1,N)` or column `(N,1)`, same
vector-only convention as `DCT1`/`Norm` - of equal length, and
`0 <= Degree <= N-1`: at `N-1` the fit is exact interpolation (for
distinct `X`), at 0 it is the mean of `Y`. Neither input is modified.
Argument errors raise `EArgumentException`/`EArgumentOutOfRangeException`
rather than `assert`, following this unit's own exception-based
convention rather than newVM's assert one; a rank-deficient design
matrix raises `EMathError`.

- **Library-backed (`HAVE_LAPACKE`)**: `LAPACKE_dgels` on the
  `N x (Degree+1)` row-major Vandermonde matrix `[1, x, x^2, ..., x^d]` -
  a QR factorisation of the design matrix itself, far better conditioned
  than the normal equations (condition number of `V` rather than
  `V'V`). `dgels` wants the right-hand side sized `max(N, d+1) = N` and
  overwrites both array arguments, so `Fit` works on copies (checked by
  `TestFitLeavesInputsUntouched`); the solution comes back in the first
  `d+1` entries. `lapacke_dgels` is a new binding, added to all five
  places in `OneAPI.pas` (Unix MKL `external`, the Unix-no-MKL/ArmPL
  type+var+loader, the Windows type+var+loader) - the "22 LAPACKE_*
  entry points" the ArmPL comments count is now 23. Gated on
  `HAVE_LAPACKE` (not `PUREPASCAL`) because it needs real LAPACK and
  nothing else, same as `LinearSolve`/`Invert`/`Det`.
- **Fallback (no `HAVE_LAPACKE`)**: the normal equations, ported from
  LMath's `PolFit` (`LMath/uRegression/upolfit.pas`): the
  `(d+1)x(d+1)` matrix of power sums `V[i,j] = sum x^(i+j)` is Hankel,
  so only its first row (`x^0..x^d`) and last column (`x^(d+1)..x^(2d)`)
  are accumulated and the rest copied along the anti-diagonals, exactly
  as LMath does, with `B[i] = sum x^i*y` on the right. Solved with
  newVM's own `LinearSolve` in place of LMath's `LinEq`, so it routes to
  whichever LU this machine has (Accelerate's `dgetrf_`, or
  `PurePascalLU`) and the unit carries no linear algebra of its own.
  There is deliberately no Accelerate `dgels_` branch: on a Mac without
  MKL the fallback already gets a real LU via `LinearSolve`, and the
  normal equations are adequate at the modest degrees a fit to `N`
  points sensibly uses.
- **Weighted overload `Fit(X, Y, W, Degree)`** minimises
  `sum W[i]*(P(X[i])-Y[i])^2`. `W` is a vector of plain non-negative
  weights, one per point (either vector shape, like `X`/`Y`); a zero
  weight drops its point, a negative one raises `EArgumentException`.
  This is weights, **not** the standard deviations LMath's `WPolFit`
  takes (it forms `w = 1/S^2` itself). Both overloads call one private
  `FitImpl` taking `W` plus a `Weighted` flag, so the two backends
  aren't duplicated. (Not a `PDouble`-or-nil parameter, which was the
  first attempt: `PDouble` names System's type in the interface but
  cblas's own `Pdouble` alias in the implementation, where the LAPACKE
  units are `uses`d, and FPC rejects the method header as not matching
  any declaration - a trap for any record method here whose signature
  mentions `PDouble`.) On the `dgels` path row `i` of the
  design matrix and of `Y` are scaled by `sqrt(W[i])`, turning the
  weighted problem into an ordinary one; on the normal-equations path
  every power sum and right-hand-side term carries `W[i]`, exactly as
  `WPolFit` does.
- **Residual-returning overloads** `Fit(X, Y, Degree, out Residuals)`
  and `Fit(X, Y, W, Degree, out Residuals)` return the same polynomial
  plus `Y[i] - P(X[i])` as a `TVMobj` in `Y`'s shape (X's and Y's may
  differ - one a row, one a column - so they are indexed flat). The
  residuals are raw differences, not weight-scaled, so a point given
  weight 0 still shows its distance from the curve. They are thin
  wrappers: the matching fit, then the public `Residuals(X, Y)` method,
  which works on any polynomial. An intercept fit's unweighted residuals
  sum to zero, which `TestFitResidualsKnownValuesSumToZero` checks.
- **Standard-error overloads** `Fit(X, Y, Degree, out Residuals, out
  StdError)` and the weighted twin add the standard error of the
  regression - the residual standard error `s = sqrt(SSR/(N-(d+1)))`,
  one number for the fit, **not** per-coefficient standard errors
  (those would need the covariance matrix, i.e. LMath's `V`, which
  isn't computed). Weighted: `sqrt(sum w*r^2 / (N+ - (d+1)))` with `N+`
  the points of positive weight, R's `lm` convention of dropping
  zero-weight observations from both the sum and the degrees of
  freedom. At zero degrees of freedom (the interpolating `Degree=N-1`
  fit) it returns `NaN` rather than raising, so the full-degree fit
  stays usable; callers test it with `IsNan`. Computed by a private
  `StdErrorOf` over the residuals, after the residual-returning overload.
- **`Evaluate(const X: TVMobj): TVMobj`** is the vector form of the
  scalar `Evaluate(X: Double)` (both marked `overload`): Horner's method
  on every element of `X`, returning a `TVMobj` of the same shape - any
  shape, not only vectors, since it's elementwise - so a `Fit` can be
  evaluated on a whole plotting grid in one call. A plain loop, like
  `Trace`/`Find` in newVM: there is no BLAS/VML polynomial primitive, and
  vectorising each Horner step as a whole-buffer axpy would cost one
  pass over `X` per coefficient for nothing. No backend gating needed.
- `Fit` returns through `TPolynomial.Create`, so trailing coefficients
  within `DefaultTolerance` (1e-12) of zero are trimmed like any other
  polynomial here - a fit that comes back of lower degree than asked
  for simply had a negligible leading coefficient.
- **Tests**: `TPolynomialTests` in `newVMTests.pas` - a few checks of
  the pre-existing arithmetic (`+`, `*`, `Evaluate`, `Derivative`,
  `DivideBy`/`Modulus`, since none of it had run under FPC before),
  then `Fit` against known values rather than hard-coded solver output:
  an exact quadratic recovered from 5 points, a degree-`N-1` cubic that
  interpolates all 4 points, a degree-1 line checked against the
  closed-form slope/intercept (`Sxy/Sxx`), degree 0 as the mean, the
  same quadratic from column vectors, inputs left untouched, the
  four argument-error paths, the weighted overload (a common weight
  reproduces the unweighted fit, a zero weight drops a point to a
  closed-form 9/7 line, degree 0 is the weighted mean, negative/miscounted
  weights raise), the residual-returning overloads (zero residuals on an
  exact fit with Y a column and X a row, the known -0.1/0.8/-1.3/0.6 line
  residuals summing to zero, a dropped point's raw -13/7 residual under
  weights), the standard-error overloads (`sqrt(1.35)` for the line,
  0 for the exact quadratic, `NaN` for the interpolating fit, `sqrt(2/7)`
  weighted with a zero-weight point dropped), and the `TVMobj` `Evaluate` overload (agrees
  with the scalar one elementwise, keeps a 2x3 shape, zero polynomial). Verified both ways: 321/321 with
  `HAVE_LAPACKE` on, and again with it forced off in `newVMConfig.inc`
  so `Fit` ran the LMath-derived normal-equations path through
  `PurePascalLU`. One gotcha for repeating that: force `HAVE_LAPACKE`
  off **and** `PUREPASCAL` on together. `PurePascalLU`/`PurePascalLUSolve`
  are only compiled under `PUREPASCAL`, but `LinearSolve`/`Invert`/`Det`
  call them under `{$IFNDEF HAVE_LAPACKE}` (minus the Accelerate case),
  so "no LAPACKE, not PUREPASCAL" fails to compile with "Identifier not
  found PurePascalLU". The configure tool can never emit that pair (no
  MKL/ArmPL always sets `PUREPASCAL` too), so it only bites a hand edit.

### `newVMsparse.pas` (sparse double-real matrix and MKL sparse solvers)

`newVMsparse.pas` provides `TVMSparseMtx`, a sparse double-precision real
matrix, plus a direct (PARDISO) and an iterative (RCI ISS FGMRES) sparse
solver over it. Like `newVMI.pas` it's a companion to the four-way family
rather than a member of it, but for a different reason: `newVMI.pas` is
excluded because BLAS/LAPACK/VML have no integer datatype, whereas this
unit is excluded because **sparse solvers are MKL-exclusive** — there is
no OpenBLAS/ArmPL/Accelerate equivalent for PARDISO or the RCI ISS
routines, unlike the dense BLAS/LAPACK/VML calls the other units share.
Two consequences follow from that, and they're the main thing to know
before touching this file:

- The whole unit is gated on `{$IFDEF HAVE_MKL}` end to end — its
  `OneAPI.pas` bindings, its entry in `newVMTests.pas`'s `uses` clause,
  the `TVMSparseTests` class, its implementation, and its `RegisterTest`
  call.
- **There is no `PUREPASCAL` fallback**, and deliberately so — unlike
  every routine in `newVM.pas`/`newVMSingle.pas`/`newVMComplex.pas`/
  `newVMComplexSingle.pas` (see the `newVMConfig.inc` section above).
  Don't add `{$IFDEF PUREPASCAL}` bodies here by analogy with those
  units: a hand-rolled sparse direct solver is a different order of
  undertaking from `PurePascalLU`, and the unit simply doesn't exist on
  a machine without MKL.

Written for the `Delphi OOFEM/FEM4` port (most of that tree's `Examples/`
`uses` it), but it has no dependency on it — it's a general-purpose
sparse type for this repo.

**Storage.** CSR (compressed sparse row), **0-based**, matching
`newVM.pas`'s own row-major/0-based convention — deliberately *not*
MtxVec's CSC, since CSR is what PARDISO and RCI FGMRES want natively and
there's no transpose step at the solver boundary. The record's three
parallel private arrays are `FRowPtr` (length `Rows+1`), `FColInd` and
`FValues` (both length `NonZeros`), with public read-only `Rows`/`Cols`/
`NonZeros` properties. Each row's entries are **sorted ascending by
column index** — an invariant `TripletsToSparse` and `SparseAdd` both
maintain and `ExtractUpperCSR` relies on; preserve it in anything new.
Like `TVMobj`, this is a record wrapping dynamic arrays, so the same
value-semantics caveat applies (plain assignment aliases the buffers),
but note there is **no `CopyObj` equivalent** for it — `PardisoSolve`'s
non-symmetric path deliberately aliases (`Asolve := A`) because it only
ever reads from it.

The unit also declares `TIntegerArray`/`TDoubleArray`/`TBooleanArray`/
`PBooleanArray` — plain FPC dynamic-array aliases, typedef'd here purely
so code ported from MtxVec's `Math387` or FEM4's
`CXS.FEMLAP.MtxVecExtra.pas` needs no signature changes.

**Construction.** `TripletsToSparse(Rows, Cols, RowIdx, ColIdx, Val)` is
the *only* way to build a `TVMSparseMtx` — a bulk COO→CSR conversion,
with duplicate `(row,col)` pairs **summed**. Summing isn't incidental: it
is exactly how FEM assembly works, where the same global `(i,j)`
legitimately accumulates a contribution from every element touching it.
There is no incremental/insert-one-entry path, because every sparse
matrix this repo builds is assembled in bulk once per (re-)assembly. The
implementation is a counting sort into row buckets, then per row an
insertion sort by column followed by a merge of adjacent equal columns —
insertion sort is a deliberate choice, not an oversight, since FEM
stencils are narrow enough that a general-purpose sort would buy nothing.

**Operations** (all plain Pascal loops over the CSR arrays unless noted):

- `SparseDiag(A)` extracts the diagonal into a dense `(Rows,1)` `TVMobj`.
  Named `SparseDiag`, **not** `Diag`, to avoid colliding with
  `newVM.pas`'s own `Diag` — which is the *opposite* operation (dense
  column vector → diagonal matrix) — now that this unit `uses newVM`.
- `SetDiagonal(var A, Diag)` overwrites `A`'s diagonal in place from a
  dense vector; a direct port of FEM4's
  `CXS.FEMLAP.MtxVecExtra.SetDiagonal`, walking CSR rather than MtxVec's
  CSC. Used by the FEM4 port's penalty-method Dirichlet BC imposition.
  Only overwrites diagonal entries that are already structurally present
  — it cannot introduce one (see the missing-diagonal note below).
- `SparseAdd(A, B)` is a standard two-cursor CSR row merge. Replaces
  MtxVec's 3-argument sparse `.Add(A, B, nzHint)`; no non-zero hint is
  needed since the merge sizes itself (allocate `A.NonZeros+B.NonZeros`
  as an upper bound, `SetLength` down to the true count at the end — the
  same trim-at-the-end pattern `TripletsToSparse` and `ExtractUpperCSR`
  use). Used by transient/nonlinear FEM4 solves to combine mass and
  stiffness into one effective system matrix each step.
- `SparseMatMult(A, X)` is sparse-matrix × dense-vector, via the
  Inspector-Executor Sparse BLAS (`mkl_sparse_d_create_csr` +
  `mkl_sparse_d_mv`) — the same machinery `FGMRESSolve`'s own
  `RCI_request=1` step uses internally. Replaces MtxVec's
  `TSparseMtx.MulLeft`.

**`PardisoSolve(A, B, SymmetricPosDef)`** — direct solve, single
right-hand side (`B` and the result are `(N,1)` or `(1,N)`; a single RHS
is the only shape FEM4 ever calls with).

- `SymmetricPosDef=True` selects PARDISO `mtype=2` and passes the **upper
  triangle only** (`ExtractUpperCSR`), as PARDISO requires for symmetric
  types; `False` selects `mtype=11` (general unsymmetric) and passes the
  full matrix.
- `iparm[34] := 1` after `pardisoinit`, selecting zero-based indexing to
  match this unit's CSR.
- One-shot `phase=13` (analysis + numerical factorisation + solve
  combined), then **always** a second call with `phase=-1` to release
  PARDISO's internal memory tied to `pt`, regardless of outcome, before
  the error code is examined. Nothing caches a factorisation across
  repeated solves against the same sparsity pattern — simplicity over
  speed, a deliberate trade worth revisiting only if profiling says so.
- `B` is `CopyObj`'d first, since PARDISO may use `b` as working storage
  and the caller's `B` must never be mutated.

**`FGMRESSolve(A, B, UseILU0 = True, MaxIter = 500, Tol = 1e-8)`** — MKL
RCI ISS FGMRES, optionally ILU0-preconditioned, driven by the standard
reverse-communication loop (`dfgmres_init` → `dfgmres_check` →
`dfgmres` → `dfgmres_get`), dispatching on `RCI_request`: `1` is a
matrix-vector product (`mkl_sparse_d_mv`), `3` applies the
preconditioner as two triangular solves (`mkl_sparse_d_trsv` against `L`
then `U`). Several non-obvious details, all of which took a debugging
pass to establish:

- **`ipar`/`dpar` are Fortran-indexed in the docs, 0-based here** — MKL's
  `ipar(5)` is `ipar[4]`, `dpar(1)` is `dpar[0]`, and so on; every
  assignment in the source carries its Fortran index as a comment. Keep
  that up if more are added, since an off-by-one here misconfigures the
  solver silently rather than erroring.
- **`ipar[11] := 1` (Fortran `ipar(12)`) must be set explicitly.** This
  MKL version's `dfgmres_init` does *not* default it to 1, confirmed
  empirically: omit the line and the loop is handed an actual
  `RCI_request=4` (user-defined residual-norm check), which this
  implementation deliberately treats as an error rather than
  implementing.
- **`dcsrilu0` is the legacy interface and wants 1-based `ia`/`ja`**, so
  `FGMRESSolve` builds 1-based copies of `FRowPtr`/`FColInd` *solely* for
  that one call; everything else in the unit stays 0-based.
- The ILU0 factors come back packed into a single `L\U` buffer sharing
  `A`'s own sparsity pattern, so one Inspector-Executor handle covers
  both triangular solves — the two are distinguished by descriptor alone
  (`L`: lower + `SPARSE_DIAG_UNIT`; `U`: upper + `SPARSE_DIAG_NON_UNIT`).
- `restart := Min(150, n)`. The `tmp` workspace is MKL's documented
  minimum **plus a generous fixed margin** (`64*(n+restart)`). The margin
  is there because a rare, non-deterministic heap-corruption crash was
  observed once at exactly the documented minimum and never reproduced
  across dozens of reruns — consistent with a margin-dependent issue
  rather than a clear logic bug. It's cheap at FEM scale; don't trim it
  back to the exact formula.

**The missing-diagonal check** (`FindMissingDiagonalRow`, run by
`PardisoSolve`) is the most valuable thing in this unit to know about.
Both PARDISO's factorisation and the `dcsrilu0` path require every row to
carry an **explicitly stored** diagonal entry — a row structurally absent
from the sparsity pattern, not merely one holding a zero value. Neither
routine reports that cleanly: `dcsrilu0` at least raises a "no diagonal
in CSR format" error (this caught the Ex16 bug), but PARDISO **segfaults
deep inside its own closed-source METIS reordering step with no useful
diagnostic at all** (the Ex35/ThermalEngine crash this check was added
for — a 24822-row transient thermal matrix with at least one row never
touched by any element's diagonal contribution). The up-front scan is
`O(NonZeros)`, negligible against an `O(N^1.5)`-or-worse factorisation,
and converts an opaque access violation into a named row index plus the
likely assembly cause. If a sparse solve ever crashes with no Pascal
stack, suspect this class of problem first.

**Error handling deviates from the repo's `assert` convention, on
purpose.** Shape/argument validation still uses the usual guard-clause
`assert` with a unit-local `const s = 'Function Name : '` prefix, as
everywhere else. But any non-zero MKL status or `info` code raises a
plain `Exception` carrying the raw code, because those are runtime
library failures rather than programmer errors, and `assert`s compile out
under a build without `IncludeAssertionCode`. (The FEM4 code this
replaces never checked a return code from its own `.Solve` calls at all,
so this is a small correctness improvement, not a behaviour change to
preserve.)

**Bindings** live in `OneAPI.pas`, declared only in the `HAVE_MKL` branch
(both the Unix `external` declarations and the Windows procedural-type/
`LoadMKLFunctions` bindings — see "Cross-platform library binding"
below): `pardisoinit`/`pardiso`, `dfgmres_init`/`dfgmres_check`/
`dfgmres`/`dfgmres_get`, `dcsrilu0`, and the Inspector-Executor quartet
`mkl_sparse_d_create_csr`/`mkl_sparse_d_mv`/`mkl_sparse_d_trsv`/
`mkl_sparse_destroy`, plus the `TMKLMatrixDescr` record and the
`SPARSE_*` enum-value constants. Four gotchas worth carrying forward:

- **The legacy 3-array-CSR routines are not usable.** `mkl_dcsrgemv`/
  `mkl_dcsrtrsv` (which this unit originally tried) are **not exported
  under their plain names** by this MKL version — confirmed via
  `dumpbin`, which shows only `mkl_internal_dcsrgemv`/
  `mkl_cspblas_internal_*`, both explicitly internal. Intel moved the
  functionality to the Inspector-Executor Sparse BLAS API, which *is*
  still exported. Don't reintroduce the legacy names.
- **The "3-array CSR" compatibility trick**: the Inspector-Executor API
  wants separate `rows_start`/`rows_end` arrays, satisfied here by
  passing two overlapping views into the same `FRowPtr`
  (`@FRowPtr[0]` and `@FRowPtr[1]`) — the standard approach this API
  documents for exactly this case, no extra allocation needed.
- `TMKLMatrixDescr` (three packed 32-bit C enums) is passed **by value**,
  the same by-value-record convention `lapacke_zlaset`/`claset` already
  use — see "External bindings" below for why that's safe under `cdecl`
  on Windows x64. `sparse_matrix_t` is an opaque MKL-owned handle, just
  `Pointer` here.
- All `MKL_INT` parameters are plain 32-bit `Integer`, matching the LP64
  interface every other binding in the file already assumes.

**Tests**: `TVMSparseTests` in `newVMTests.pas` (8 tests) — duplicate
merging in `TripletsToSparse`, `SparseDiag`, `SetDiagonal`, `SparseAdd`,
`PardisoSolve` in both symmetric and general modes, and `FGMRESSolve`
with and without the ILU0 preconditioner. The solve tests assert the
**residual** `A*X - B ≈ 0` row by row rather than hard-coded `X` values,
since a known-value expectation rounded to fixed digits would be fragile
where the residual is the actual contract.

### GPU backends: `newVMCL.pas`/`OpenCLAPI.pas` and `newVMMetal.pas`/`MetalAPI.pas`

Two further companion units put a `TVMobj`-shaped type on the GPU, both
**single precision**, both GPU-resident: `TVMobjCL` (`newVMCL.pas`, via
OpenCL + AMD's clFFT) and `TVMobjMTL` (`newVMMetal.pas`, via Apple's Metal
+ MetalPerformanceShadersGraph). They are **parallel, not layered** —
`newVMMetal.pas` was added without touching `newVMCL.pas`, because OpenCL
is deprecated on Apple platforms and was never found on the Darwin/AArch64
dev machine, while Metal is that machine's real, always-present GPU API.
Each is gated end to end on its own config define (`HAVE_OPENCL`,
`HAVE_METAL`) — `uses` clause, unit, test class, `RegisterTest` call — so
a machine without that backend never references the unit at all.

Both follow `TVMobjS`'s object shape as closely as a GPU-buffer-backed
type can: `Create(r,c)` (plus a `Create(r,c,Values)` convenience overload
for test fixtures), default `Element[r,c]`, read-only `Rows`/`Cols`,
`fillRandom`/`Id`/`linspace`/`Transpose`/`writeMatrix`, the same
`+`/`-`/`*`/`/`/`=` class operators with the **same contract** (`*`
between two GPU objects is **elementwise** — use `MatMultCL`/`MatMultMTL`
explicitly for a real matrix product, exactly as everywhere else in this
repo), and a `CopyObjCL`/`CopyObjMTL` matching `CopyObj`'s "genuinely
independent copy" contract. `MaxDimCL`/`MaxDimMTL` track `newVM.pas`'s own
`MaxDim` (currently 2097152), raised in step across every unit.

**Scope is deliberately narrower than the four host units.** In: the
object shape above, the four arithmetic operators, elementwise
`Sin`/`Cos`/`Tan`/`Sinh`/`Sqr`/`Sqrt`/`Exp`/`Ln`, a matrix multiply, and
`FFT`/`IFFT`. Explicitly **out**: `LinearSolve*`/`Invert*` (there is no
GPU LAPACK to build on, and a numerically robust from-scratch GPU LU is a
separate undertaking), and `Kron`/`Diag`/`Trace`/`Det`/`Flip*`/`Merge*`/
`Reshape`/`Repmat`/`AddScalar`/`SubMatrix`/`DCT`/`DST` (straightforward in
principle, simply not needed yet). The motivating use case for both is
GPU-accelerated spectrum work for the `SDR_Radio` project, which needs FFT
and elementwise/matrix arithmetic and nothing else. `MatMultCL`/
`MatMultMTL` are **naive, non-tiled** kernels (one work-item per output
element, a plain dot-product loop over K) — an intentional v1 choice, not
an oversight.

**Managed records — the one structural difference from every other
`TVMobj*` type.** The host types get value semantics for free: `fData` is
an FPC dynamic array, already reference-counted by the language. A
`cl_mem` or `mtl_buffer` is just an opaque pointer with *explicit*
reference counting, so a plain record holding one would alias on
assignment like `TVMobjS` but **nothing would ever release the GPU
buffer**, records having no destructor. Both units therefore use
`{$modeswitch AdvancedRecords}` and implement
`Initialize`/`Finalize`/`AddRef`/`Copy` class operators over a shared
`FRefCount: PInteger`. Two things to know before touching them:

- **`Copy` is not optional.** FPC does *not* fall back to a bitwise copy
  plus `AddRef` for plain `:=` when a `Copy` operator exists — confirmed
  empirically: removing `Copy` and keeping only `AddRef` produces a
  use-after-free within the first few thousand iterations of a stress
  loop.
- **`Copy` must release `Dst`'s OLD reference before overwriting it.**
  Its first version only ever added a reference to `Src`, so a reassigned
  variable (e.g. a loop body's `B := A * 2.0;`) leaked one GPU buffer and
  one refcount cell per iteration — found via a 20,000-iteration stress
  test (process memory climbed by hundreds of MB and never came back)
  and fixed, guarded against self-assignment so reassigning a variable to
  itself can't transiently hit refcount zero and free a live buffer. The
  identical bug was found and fixed separately in both units (see commits
  `0c65878` and `1e51cc6`). The Pascal-side `FRefCount` is a single-level
  scheme over a *single* GPU-level ownership (acquired once at `Create`,
  released once at zero) — there is never a matching
  `clRetainMemObject`/Metal retain call. The practical upshot: neither
  type needs a manual `Free`/`Release` anywhere.

**Where the two diverge, and why it isn't a mechanical port:**

- **`Element[r,c]` is slow by design in `TVMobjCL`, but not in
  `TVMobjMTL`.** Each OpenCL access is its own blocking
  `clEnqueueReadBuffer`/`WriteBuffer` round trip — fine for tests and
  debug inspection (all this repo's test convention needs), never for a
  hot per-element loop. Apple Silicon's unified memory means
  `MTLBufferContents` is a raw CPU-visible pointer into the very memory
  the GPU uses, so `TVMobjMTL`'s `Element`/`fillRandom`/`ToDeviceMTL`/
  `ToHost` are plain `Move`/pointer operations and that caveat does not
  apply.
- **Bulk transfer is the real bridge.** `ToDevice`/`ToHost` (OpenCL) and
  `ToDeviceMTL`/`ToHost` (Metal) move a whole buffer in one transfer, to
  and from `TVMobjS` — genuinely new relative to the host types, which
  never needed one.
- **One naming collision worth remembering**: the Metal upload function
  is `ToDeviceMTL`, not `ToDevice`, because `ToDevice(const A: TVMobjS)`
  already exists returning `TVMobjCL` and the two would differ only in
  *return* type, which Pascal cannot overload on. Everything else
  (`Sin`/`Cos`/…/`FFT`/`IFFT`/`ToHost`) reuses the same names as plain
  `overload`s, disambiguated by argument type exactly as the five host
  families already do.
- **FFT is simpler on Metal.** clFFT only supports an in-place transform
  (`CLFFT_INPLACE`), so `TVMobjCL`'s `FFT`/`IFFT` must `CopyObjCL` first
  and transform the copy; MPSGraph takes separate input/output tensors,
  so the Metal versions allocate a fresh result and dispatch straight
  into it.

**FFT layout and scaling (identical across both, and a real trap).**
Neither GPU type has a complex sibling the way `newVM.pas` can hand off
to `newVMComplex.pas`, so complex data — input *and* output — is a GPU
object of `Cols = 2*N` floats, consecutive pairs being `(re,im)`. That is
exactly clFFT's `CLFFT_COMPLEX_INTERLEAVED` and
`MPSDataTypeComplexFloat32`'s own native layout, so no packing step
exists on either side, and it matches what an SDR IQ epoch already looks
like. **Neither needs a manual `/N`**: the forward transform is unscaled,
and both clFFT's backward plan and MPSGraph's
`MPSGraphFFTScalingModeSize` already apply `1/N`, so `IFFT(FFT(x)) = x`
directly. This is the **opposite** of the FFTW convention the rest of this
codebase's FFT/DCT/DST code uses (see "FFT/DCT/DST functions" above),
which never auto-normalises either direction. An earlier `IFFT` added its
own extra `/N` on that FFTW-shaped assumption; every round-trip mismatch
was off by exactly a factor of N, and it was only caught once the
round-trip test was strengthened to check *every* element rather than one
that happened to be 0. If either unit ever grows an FFTW-backed DCT/DST,
that scaling convention does not carry over.

**clFFT plan caching** (`GFFTPlanCache`/`GetFFTPlan` in `newVMCL.pas`):
plans are baked once per distinct N and reused, not baked and destroyed
per call. Baking is a genuinely expensive driver-side operation (roughly
1–4 ms even warm on this repo's test hardware, against tens of
microseconds for the transform itself), so replanning every call made a
single GPU FFT dozens to hundreds of times slower than the equivalent
host FFTW call. This was diagnosed by `newVMCLfft8192bench.lpr` and fixed
in commit `e982929` — see the "Benchmarks" section below and
`perf/newVMCUDAvsCLFFTperformance.rtf`.

**`OpenCLReady`/`OpenCLLastError`**: the OpenCL context, queue and kernel
program are built once, lazily, by the first `TVMobjCL.Create`.
`OpenCLReady` reports whether that succeeded and `OpenCLLastError` says
why it didn't, so calling code (a status bar, say) can explain a CPU
fallback rather than silently taking one — the same "probe once, degrade
gracefully" pattern the `HAVE_*` defines establish at config time, just
at runtime.

#### `OpenCLAPI.pas`

Hand-curated **runtime (`LoadLibrary`) bindings** for OpenCL core and
clFFT — only the subset `newVMCL.pas` calls, not a wholesale header
translation. Plays the role for `newVMCL.pas` that `OneAPI.pas` plays for
the host units. Three findings from the standalone probe that preceded it
(an AMD Radeon PRO W6600, device `gfx1032`), all worth not rediscovering:

- **Static linkage fails here even though the DLL is present.**
  `OpenCL.dll` lives in `C:\Windows\System32` (put there by the GPU
  driver), so a plain `external 'OpenCL.dll'` *should* work. It doesn't:
  a probe with static `external` declarations failed at **process
  startup** with `STATUS_DLL_NOT_FOUND` (0xC0000135), even with
  `clFFT.dll` beside the exe — while the same probe rewritten to use
  `LoadLibrary`/`GetProcedureAddress` loaded and ran both libraries
  correctly, including a full compute-kernel round trip and a real clFFT
  transform. Root cause not pinned down (plausibly a Windows loader quirk
  in resolving transitive MSVCP140/VCRUNTIME140/`api-ms-win-crt-*`
  dependencies at static-import time); dynamic loading is already this
  codebase's established answer for exactly this class of problem.
- **`clfftInitSetupData` is not exported** by this machine's clFFT build
  (confirmed via `dumpbin /exports` — genuinely absent, not a naming
  mismatch), and calling through the resulting nil pointer crashed the
  probe. It only fills in cosmetic version/debug fields anyway, and
  `clfftSetup(nil)` is documented to work without it — so this binding
  doesn't declare it at all.
- **`clFFT` isn't on a standard search path**, so `LoadclFFT` tries the
  bare name first (for a future deployment that puts it on `PATH` or
  beside the exe) then falls back to known-good build/install locations —
  the same pattern `uSDRplay.pas` uses for `sdrplay_api.dll`. On Unix the
  fallback is a *name* rather than a path (`libclFFT.so.2`), since a real
  Linux dev machine had only the newer SONAME with no `.so.0` symlink.

#### `MetalAPI.pas`

Hand-curated **Objective-C bindings** for Metal and
MetalPerformanceShadersGraph. Unlike `OpenCLAPI.pas` these are **link-time
`linkframework` directives, not dynamic loading** — both frameworks are
always present at a fixed, versionless location on every real Mac, so
there is no "might not be installed" case; and more fundamentally you
*cannot* `dlopen` a framework and `GetProcedureAddress` your way to ObjC
classes, since class lookup and message dispatch go through the
Objective-C runtime, which needs the real Mach-O image loaded and
registered.

- **Mode**: `{$mode objfpc}` + `{$modeswitch objectivec1}`, not this
  codebase's usual `mode Delphi` — FPC's objc class/protocol syntax is
  ObjFPC-only. The *public interface* exposes only plain types
  (`mtl_buffer = Pointer`, the same opaque-handle convention
  `OpenCLAPI.pas` uses for `cl_mem`), never a raw `objcclass`, so
  `newVMMetal.pas` stays in `mode Delphi` + `AdvancedRecords` exactly like
  `newVMCL.pas` and no caller needs `objectivec1`.
- **Reference counting is manual MRC, not ARC** — confirmed against
  `objcbase.pp`, where `retain`/`release` are ordinary `message`-dispatched
  methods. Cocoa's Fundamental Rule applies: `new…`/`alloc`/`copy…`
  return a +1 reference this code owns; every other factory/accessor
  returns an autoreleased object it must *not* release. Every dispatch/FFT
  call wraps its transient objects in a fresh `NSAutoreleasePool`, since
  there is no pool on the thread by default and these run once per SDR
  epoch tick.
- **The FPU-exception driver crash.** A plain FPC console program that
  does nothing but call `MTLCreateSystemDefaultDevice()` crashes
  deterministically with `EXC_BAD_INSTRUCTION` deep inside Apple's AGX
  driver — while the identical call from clang-compiled Objective-C on
  the same machine works. Cause: FPC's default AArch64 FPCR leaves
  floating-point exception trapping armed in a way clang-generated code
  does not, and the driver's float code never expected a caller with traps
  enabled. **This is the same class of bug this repo already hit once**
  (see git history: "Fix Windows EInvalidOp crash from MKL LAPACKE complex
  solve calls"). Fix: `Math.SetExceptionMask` masking every FPU exception
  *before* the first Metal/MPSGraph call of the process, done once from
  `InitializeMetalContext`. If a GPU/native library ever crashes
  inexplicably inside its own float code, check this first.
- **DWARF3 breaks this unit.** FPC 3.2.4's DWARF3 generator hits a real
  internal compiler error (`200609171`) on this unit's `objcclass`/
  `objcprotocol` declarations, specifically when combined with `-gl` —
  reproduced standalone (`-gw3` alone fine, `-gl` alone fine, together ICE
  every time; `{$DEBUGINFO OFF}` does *not* suppress it). **That is why
  `newVMtest.lpi`'s `DebugInfoType` is `dsDwarf2`, not the Lazarus default
  `dsDwarf3`** — it costs nothing but a debug-format choice. If someone
  switches the project back to DWARF3 and `MetalAPI.pas` suddenly won't
  compile, this is the reason.
- **MPSGraph FFT layout/scaling** was confirmed against a real 16-point
  FFT of a pure bin-2 cosine (magnitude-8.0 peaks at bins 2 and 14,
  matching `newVMCL.pas`'s own `TestFFTKnownValues` exactly) plus a full
  round trip, before the unit was written — see the shared FFT notes
  above.


### External bindings

- `cblas.pas` — machine-generated (`h2pas`) BLAS declarations, originally
  bound against OpenBLAS, providing `CBLAS_ORDER`, `CBLAS_TRANSPOSE`, etc.
  and base `cblas_*` function pointers/types. It now also selects Arm
  Performance Libraries or Apple Accelerate as the CBLAS backend where
  those are what's present, and hand-adds Accelerate's Fortran LAPACK
  (`dgetrf_`/`dgetri_`/`dgetrs_`) and its vForce/vDSP stand-ins for MKL
  VML and IPP — see "The define set, as it stands now" under
  `newVMConfig.inc` above for the selection rules and the calling
  conventions, which differ from MKL's.
- `OneAPI.pas` — hand-written bindings for LAPACKE (`lapacke_*`), Intel VML
  (`vmd*`), Intel IPP (`ipps*`), MKL memory management (`MKL_malloc` etc.),
  and MKL's VSL RNG (`vslNewStream`/`vdRngGaussian`/`vsRngGaussian`), plus the
  `TComplex16`/`TComplex8` record layouts (must stay bit-identical to
  `MKL_Complex16`/`MKL_Complex8` — two contiguous IEEE-754 floats — since
  several routines reinterpret a complex buffer as a flat real array via
  pointer casts, e.g. `fillRandom` and `RealToComplex`/`GetRealPart`).
  It additionally carries the sparse-solver bindings (PARDISO, RCI ISS
  FGMRES, `dcsrilu0`, and the Inspector-Executor Sparse BLAS quartet) plus
  `TMKLMatrixDescr` and the `SPARSE_*` constants — all declared only in
  the `HAVE_MKL` branch, since `newVMsparse.pas` is their sole caller and
  requires MKL unconditionally; see the `newVMsparse.pas` section above.
- `fftw3.pas` — see the dedicated "FFT/DCT/DST functions" section above.
  Like `cblas.pas`, it resolves its library at runtime via
  `LoadLibrary`/`GetProcedureAddress` rather than a link-time `external`:
  on this development machine, double-precision `libfftw3` only exists as
  a static `.a` (from a manual source build), while single-precision
  `libfftw3f` is only installed as a versioned runtime `.so.3` (via the
  distro's apt package, no `-dev` package, so no unversioned symlink) -
  dynamic loading against the exact versioned name works regardless of
  which of those a given machine happens to have.
- All four `newVM*` units declare `{$Linklib 'mkl_rt.so'}` plus `pthread`,
  `m`, and `dl`, guarded by `{$IFDEF UNIX}` — the comment in each file
  header explains why: `mkl_rt.so` `dlopen`s `libmkl_core.so` at runtime,
  which expects `libm`/`pthread`/`dl` already resolved in the process's
  global symbol table, or you get `symbol lookup error: ... undefined
  symbol: log10`-style failures. Don't remove these linklib directives
  even though nothing in the unit calls into them directly. This is purely
  a Unix/ELF dynamic-linker quirk — Windows PE imports are resolved per-DLL
  independently, so nothing analogous is needed (or emitted) there; see
  "Cross-platform library binding" below.

### Cross-platform library binding (`{$IFDEF UNIX}`/`{$IFDEF WINDOWS}` in `OneAPI.pas`)

`OneAPI.pas` targets Linux and Windows from the same source. On Unix,
every MKL- and IPP-backed routine keeps its original plain
`cdecl;external;` declaration (inside one big `{$IFDEF UNIX}` block),
resolved at link time via the `{$Linklib}` block — completely unchanged
from how the unit always worked.

On Windows, a static `external 'somedll.dll'` declaration turned out not
to be viable for *either* library, for related but distinct reasons — so
both are handled the same way: every MKL- and IPP-backed routine is
declared as a `var` of a matching procedural type (inside one big
`{$IFDEF WINDOWS}` block) instead of an `external` function, and resolved
at runtime via `LoadLibrary`/`GetProcedureAddress` (from `DynLibs`) in the
unit's `initialization` section. This mirrors the pattern `cblas.pas`
already uses for OpenBLAS (`LoadAddresses`/`TryInitializeCBLAS`), and
means call sites elsewhere (`newVM.pas` etc.) are unaffected either way —
calling a procedural variable uses the same syntax as calling a plain
external function.

- **MKL** (`lapacke_*`, `vmd*`/`vd*`/`vs*`/`vc*`/`vz*`, `MKL_malloc`
  et al., `MKL_*imatcopy`, `vslNewStream`/`vdRngGaussian`/`vsRngGaussian`)
  was originally assumed to ship one fixed-name merged runtime-dispatch
  DLL on Windows the way `mkl_rt.so` is fixed on Linux — **this turned out
  to be wrong**: real Intel oneAPI installs (confirmed on this machine for
  2025.3 and 2026.0/2026.1) ship a *versioned* dispatcher DLL
  (`mkl_rt.2.dll`, `mkl_rt.3.dll`, ...) with no unversioned `mkl_rt.dll`
  compatibility copy, and the version suffix increments across oneAPI
  releases. A hard-coded `external 'mkl_rt.dll'` therefore fails at
  runtime with "DLL not found" on every real install. `LoadMKLFunctions`
  resolves this by trying a fixed list of candidate names
  (`MKLCandidateLibs`: unversioned `mkl_rt.dll` first, then
  `mkl_rt.1.dll` through `mkl_rt.10.dll`) via `LoadLibrary`, caching
  whichever one is found (`GetMKLHandle`), then resolving every MKL
  symbol from that one handle via `MKLProc`. If a future oneAPI release
  bumps the suffix past 10, extend `MKLCandidateLibs`.
- **IPP** (`ippsCos_64f_A50`, `ippsVectorSlope_64f`/`_32f`, `ippsCopy_64f`,
  `ippsFlip_64f`/`_32f`/`_64fc`/`_32fc`, `ippsMulC_64f`/`_I_L`,
  `ippsAddC_64f_I`/`_32f_I`/`_64fc_I`/`_32fc_I`, `ippsSubC_64f_I`,
  `ippsDivC_64f_I`/`_32f_I`, `ippsSqr_64f_I`, `ippsExp_64f_I`, `ippInit`,
  `ippMalloc`, `ippFree`) is split across three separate DLLs even on
  Windows (`ippcore.dll`/`ippvm.dll`/`ipps.dll`, mirroring the Linux
  `libippcore.so`/`libippvm.so`/`libipps.so` triplet), and which DLL
  actually exports a given symbol is not reliably documented and can vary
  by IPP version (several of these are declared in `ipps.h` but actually
  resolve from `ippvm.dll`). `LoadIPPFunctions` resolves each one at
  runtime by trying `ipps.dll`, then `ippvm.dll`, then `ippcore.dll` via
  `IPPProc`, asserting if none of the three export it.
  `ippsAddC_64fc_I`/`ippsAddC_32fc_I` (added for `AddScalarZ`/`AddScalarC`
  - see `Diag`/`Norm` above) take their constant `val` **by value** as a
  `TComplex16`/`TComplex8` record, matching Intel IPP's own C signature
  (`IppStatus ippsAddC_64fc_I(Ipp64fc val, Ipp64fc* pSrcDst, int len)`) -
  the same by-value-record convention `lapacke_zlaset`/`lapacke_claset`
  already use for their `alpha`/`beta` parameters. Before wiring this into
  `newVMComplex.pas`/`newVMComplexSingle.pas`, a standalone scratch
  program (outside the project tree) called the real, linked
  `ippvm.dll`/`ipps.dll` on the development machine directly and
  round-tripped known complex values correctly - confirming FPC's `cdecl`
  on Windows x64 passes >8-byte structs "by value" via the same invisible-
  reference convention the DLL's own C compiler targets, rather than just
  assuming it from the `lapacke_zlaset` precedent alone.
- Both loaders are called from `OneAPI`'s `initialization` section
  (Windows-only), so nothing in `newVMtest.lpr` or elsewhere needs to call
  them explicitly.
- If `LoadMKLFunctions`'s or `LoadIPPFunctions`'s assert fires for a given
  symbol on Windows: for MKL, it means none of `MKLCandidateLibs` was
  found on `PATH` at all (check the oneAPI `mkl/<version>/bin` directory
  is actually on `PATH`, and consider whether the installed version's
  suffix exceeds the hard-coded range); for IPP, it means none of the
  three DLLs export that exact symbol name (check the installed IPP
  version's actual DLL layout, e.g. via `dumpbin /exports`, and extend
  `IPPProc`'s search list if needed).

### CBLAS/LAPACKE calling convention gotchas (complex units)

When touching `newVMComplex.pas`/`newVMComplexSingle.pas`:
- `cblas_zgemm`/`cblas_cgemm` take `alpha`/`beta` **by pointer**
  (`@alpha`/`@beta`), per the CBLAS C convention for complex scalars — unlike
  the real `dgemm`/`sgemm`, which take them by value.
- `lapacke_zlaset`/`lapacke_claset` take alpha/beta **by value** as complex
  scalars, matching the LAPACKE C signature.
- MKL's VSL has no complex Gaussian generator, so `fillRandom` on the complex
  types reinterprets the complex buffer as a real array of twice the length
  and calls the real generator once (valid only because the complex record
  layout is exactly two contiguous reals).

### Row-major matrix layout throughout

Every LAPACKE/CBLAS call passes `CBlasRowMajor` explicitly — this codebase
consistently uses row-major storage, unlike Fortran-native
column-major LAPACK. Keep new routines consistent with this.

### `newVMTests.pas` and `newVMtest.lpr`

`newVMTests.pas` is the real automated test suite, using FPCUnit
(`fpcunit`/`testregistry` — the `TestRegistry` unit already pulled into
every `newVM*` unit's `uses` clause turned out to be exactly this
framework). One `TTestCase` per type — `TVMobjTests`, `TVMobjSTests`,
`TVMobjZTests`, `TVMobjCTests`, `TVMobjITests`, plus three conditionally
compiled ones (`TVMobjCLTests`, `TVMobjMTLTests`, `TVMSparseTests`, all
described below) — each registered via `RegisterTest` in the unit's
`initialization` section. Coverage per
`TVMobj`/`TVMobjS`/`TVMobjZ`/`TVMobjC` type: construction and
dimension-validation asserts, `Element[r,c]` get/set (including
out-of-range and non-square addressing), `writeMatrix`, `fillRandom`
(exploits the hard-coded seed — see below), `Id`, `DataPtr` (real types),
`CopyObj*` independence, `MatMult*`, `LinearSolve*`, `Invert*` (verified
via `A*Invert(A) ≈ Identity`, and that `A` itself is left untouched),
`Kron*` (a small known-value 2×2⊗2×2 case, checked block-by-block),
`Diag*` (known-value column-vector-to-diagonal-matrix check, plus the
non-column-vector assertion path), `Norm*` (a classic 3-4-5 known value,
complex-valued via two purely-real/purely-imaginary components so
`|3|²+|4i|²=25`), `Trace*` (a known-value 3×3 case, plus the non-square
assertion path — the complex types' cases check both `.re` and `.im` of
the summed diagonal), `Det*` (a known-value 2×2 case checked against
`ad-bc`, plus a deliberately-singular 2×2 case verifying the determinant
comes out exactly 0 with no special-casing, and the non-square assertion
path), `FlipUD*`/`FlipLR*` (a known-value non-square 2×3 case each,
checked element-by-element), `MergeUD*`/`MergeLR*` (a known-value case
each checked element-by-element plus the result's `Rows`/`Cols`, and the
column/row-mismatch assertion path respectively), `Reshape*` (a known-value
2×3 -> 3×2 case verifying the row-major element order is preserved, plus
the element-count-mismatch assertion path) and `Repmat*` (a known-value
1×2 tiled 2×2 case, plus the non-positive-repetition assertion path),
every operator overload including the assertion paths, the elementwise VML
functions, and
`DCT1`..`DCT4`/`DST1`..`DST4` (each verified as a self-inverse or
mutual-inverse round trip at the exact FFTW scale factor for that kind -
see the "FFT/DCT/DST functions" architecture section above), `AddScalar*`
(a known-value case, plus confirming `A` itself is left untouched - the
two complex types additionally cover the plain-`Double`/`Single`
overload, verifying it only shifts the real part) and `SubMatrix*` (a
known-value 3×3→2×2 case, plus the out-of-bounds assertion path). The two
real types (`TVMobjTests`/`TVMobjSTests`) additionally
cover `Find` (known-value checks against each `TVMCompareOp`). The two
complex types additionally cover
`RealToComplex*`/`GetRealPart*`/`GetImagPart*`/`SplitComplex*`,
`EigDecompose*` (verified via the defining equation `A*v = lambda*v`, not
hard-coded eigenvectors, since LAPACK doesn't guarantee a particular
sign/normalisation), the mixed real/complex operators, and
`FFT_R2C`/`FFT_C2R`/`FFT`/`IFFT` (round-trip and a known-value DC-component
check). `TVMobjITests` covers the narrower subset that actually applies to
`TVMobjI` (see "`newVMI.pas`" above) — construction, `Element[r,c]`,
`writeMatrix`, `fillRandom` (both determinism and bounds), `Id`, `DataPtr`,
`CopyObjI`, `Transpose`, `linspace`, `Gather` (including the
no-non-zero-elements assertion path) — with no operator/MatMult/
LinearSolve/Invert/VML coverage, since `TVMobjI` has no such members.

**Three test cases are conditionally compiled** rather than always
present, each gated on its config define across all four of its `uses`
entry, class declaration, implementation, and `RegisterTest` call — so on
a machine without that backend the suite never references the unit at
all, and simply reports a smaller test count. This is the same "probe once
at config time, degrade gracefully" contract `PUREPASCAL`/`HAVE_FFTW`
already establish, chosen deliberately over registering tests that would
need their own runtime skip-or-pass-vacuously logic.

`TVMobjCLTests` (`HAVE_OPENCL`) and `TVMobjMTLTests` (`HAVE_METAL`) are
the GPU pair, covering the same core-object-shape subset as
`TVMobjSTests` — construction including the `Create(r,c,Values)` overload,
`Element` get/set, `writeMatrix`, `fillRandom`, `Id`, `CopyObjCL`/
`CopyObjMTL`, `Transpose`, `linspace`, every operator overload, the
elementwise functions, `MatMultCL`/`MatMultMTL` — plus the two things
only a GPU type has: the `ToDevice`/`ToHost` bridge to `TVMobjS`, and
`FFT`/`IFFT`. No `LinearSolve`/`Invert`/`Kron`/`Diag`/`Det`/`Flip*`/etc,
since neither unit implements them (see the GPU backends section above).

`TVMSparseTests` (`HAVE_MKL`) is gated for a different reason than the two
above — not an optional accelerator, but the fact that PARDISO/RCI FGMRES
have no fallback of any kind (see the `newVMsparse.pas` section). Its 8
tests cover `TripletsToSparse`'s duplicate merging,
`SparseDiag`, `SetDiagonal`, `SparseAdd`, `PardisoSolve` in both
symmetric-positive-definite and general modes, and `FGMRESSolve` with and
without the ILU0 preconditioner. Unlike most known-value tests elsewhere
in this suite, the four solve tests assert the **residual** `A*X - B ≈ 0`
row by row rather than comparing `X` against hard-coded expected values,
which would be fragile at any fixed number of digits.

One reusable trick worth knowing: `fillRandom` seeds a fresh VSL stream
with a hard-coded constant (777) on every call, so two same-sized
`fillRandom` calls produce bit-identical data — several tests exploit this
via the `=` operator (e.g. `TestFillRandomDeterministic`) instead of
needing a real "are these matrices approximately equal" helper.

`newVMtest.lpr` is now a thin FPCUnit console runner (based on the
`simpletestrunner` pattern: `TPlainResultsWriter` + `TTestResult` over
`GetTestRegistry`) — it just runs everything `newVMTests.pas` registered,
prints a plain-text pass/fail report, and sets a non-zero exit code on any
failure or error, so `./newVMtest` is a real CI-style gate. It no longer
does the old eyeballed demo (real→complex promotion, identity fill, timed
matmult/solve/eigendecompose) or handles any CLI args (including the old
`-h`/`--help`); `hirestimer.pas` is consequently unused by the current
project files, though it still exists in the repo as a general-purpose
`THighResTimer` if timing is needed again.

Building this suite surfaced two real, pre-existing bugs, both fixed as
part of adding the tests (not just worked around):
- `calcoffset` — see the "Core object shape" section above.
- `LinearSolve`/`LinearSolveS`/`LinearSolveZ`/`LinearSolveC` all asserted
  `A.Rows = B.cols` instead of `A.Rows = B.Rows` before checking the solve.
  Since `B.cols` is actually the LAPACKE `nrhs` (number of independent
  right-hand-side vectors, unconstrained relative to `A.Rows`), this
  incorrectly rejected the common single-RHS case (`B` as an Nx1 column)
  for any N other than 1. Undetected before because the old demo always
  passed a square `B`.

Note: `newVMtest.lpi` lists `newvmconvert.pas` (unit `newVMConvert`) as a
project file, but that file does not currently exist in the repo — check
before assuming it's present when the `.lpi` is the source of truth for
project membership.

### Benchmarks (`newVMbench.lpr`, `newVMCLbench.lpr`, `newVMCLfft8192bench.lpr`)

Three standalone timing programs, separate from the correctness suite.
All three build with **plain `fpc`, no `lazbuild`/`.lpi`** — the same
approach `newvmconfigure.lpr` uses, since none needs an LCL/GUI
dependency:

```
fpc -Fu. -Fi. newVMbench.lpr
```

- **`newVMbench.lpr`** — host only, all four `TVMobj*` types. Times
  `MatMult`/`LinearSolve`/`Invert` at N = 10/100/1000, plus `FFT`/`IFFT`
  (complex double and single, round-tripped and checked against the
  original) and `EigDecompose`/`EigDecomposeS` (checked via `A*v =
  lambda*v` for every eigenpair, the same verification
  `TestEigDecomposeSatisfiesEigenEquation` uses). `EigDecompose` gets its
  own shorter `NsEig` list (10/50/100, no 1000): `PurePascalEigHqr2` is
  the same asymptotic O(N³) as LU-based `Invert` but with a materially
  larger constant, so N=1000 under `PUREPASCAL` risks dwarfing every other
  row for little insight.
- **`newVMCLbench.lpr`** — host versus GPU, on the only two operations
  both sides implement: complex `FFT`/`IFFT` and real matrix multiply.
  Host is `TVMobjS`/`TVMobjC`, GPU is `TVMobjCL`. N runs 1024 → 16384 by
  doublings, same input data on both sides, and every row reports a
  correctness residual alongside the two timings so a suspiciously fast
  GPU number can be told apart from a genuinely fast one. Builds and runs
  without `HAVE_OPENCL`, printing a notice and leaving the GPU columns
  blank.
- **`newVMCLfft8192bench.lpr`** — a follow-up narrowed to N=8192 but with
  much finer timing: it separates each side's very *first* `FFT`/`IFFT`
  call from the average/min/max of 100 repeats.

Two measurement subtleties documented in the programs themselves, both
worth knowing before reading or extending a results table:

- **`PUREPASCAL` versus library-backed is a compile-time choice, not a
  runtime switch**, so getting both numbers means building `newVMbench`
  **twice** against two different `newVMConfig.inc` contents and running
  the two binaries separately. `PrintBackend` reports which defines the
  binary was actually built with, so a table assembled from two runs stays
  self-documenting. Note also that FFT/IFFT's backend is driven by
  `HAVE_FFTW`, *independently* of `PUREPASCAL` — so the common
  "`PUREPASCAL` forced on, FFTW still detected" build still times FFTW for
  the FFT rows while everything else runs its plain-Pascal body.
- **The GPU MatMult timing deliberately includes one readback.**
  `MatMultCL` enqueues its kernel and returns without waiting (OpenCL
  queues are asynchronous), so timing it alone would measure enqueue cost,
  not execution. `newVMCLbench` therefore wraps `MatMultCL` *together
  with* the following `ToHost` — whose `clEnqueueReadBuffer` is blocking
  and, on `newVMCL.pas`'s single in-order queue, cannot complete before
  the kernel does. That is the only way to observe real kernel time from
  outside the unit, and a real caller pays for the readback anyway.
  `FFT`/`IFFT` need no such wrapping, since they already `clFinish` before
  returning.

`newVMCLfft8192bench` earned its keep: `newVMCLbench`'s GPU FFT numbers
were flat at ~190–380 ms across *every* N from 1024 to 16384 — not
scaling with N the way an O(N log N) transform must. The repeat-versus-
first-call split confirmed the cost was per-call clFFT plan baking rather
than the transform, which is what motivated `newVMCL.pas`'s plan cache
(commit `e982929`). Measurements live in
`perf/newVMCUDAvsCLFFTperformance.rtf`.

One asymmetry to expect in `newVMbench`'s complex results, which is
correct rather than a bug: `LinearSolveZ`/`LinearSolveC` have **no
Accelerate branch at all** — Apple's `zgetrs_`/`cgetrs_` crash with an
access violation whenever a factored pivot has an exactly-zero imaginary
part — so both always run their `PurePascalLU*` path in *either* build,
and their two timings should come out essentially identical.


### `hirestimer.pas`

Platform-specific high-resolution timer (`THighResTimer`), using
`clock_gettime(CLOCK_MONOTONIC, ...)` on Unix, plus a `TProfiler`
convenience wrapper (`Profiler.Start`/`Profiler.Stop`, both global
singletons instantiated in the unit's `initialization` section). No
longer referenced by `newVMtest.lpr` (now an FPCUnit console runner that
doesn't time anything), but used by `demos/SpectralDiff` to time the
spectral-differentiation call, and by all three benchmark programs (see
"Benchmarks" above) — specifically so neither the demos nor the benches
need an external timing package (e.g. EpikTimer/`etpackage`) as a
dependency.

### `demos/`

Each subdirectory is a standalone Lazarus GUI project (own `.lpi`/`.lpr`/
form unit/`.lfm`) demonstrating `newVM` capabilities, built against the
top-level units in place via `OtherUnitFiles=../..` in its `.lpi` (no
copying) - build with `lazbuild --lazarusdir=<path> demos/<Name>/<Name>.lpi`
same as the main project. Both require the `TAChartLazarusPkg` and `LCL`
packages. Compiled binaries and each demo's own `lib/` output are
`.gitignore`d via a pattern scoped to `demos/*/` (see the top of
`.gitignore`), not hardcoded per demo.

- **`FunctionPlot`** — plots `y = f(x)` over the real line via a
  `TChart`/`TLineSeries`, computed with `TVMobj.linspace` plus the
  elementwise `Exp`/`Sin`/`Sqr`/`*` functions from `newVM.pas`. Default
  function is `y = exp(-0.1*x^2) * sin(3*x)`, 1000 points over `[-10,10]`.
- **`newPoly`** — least-squares polynomial fitting with
  `newPolymath.pas`'s `TPolynomial.Fit` (see its own section above),
  shown on two `TVMPlot2D` components stacked in one form, the fit above
  and the residuals underneath. A radio group picks degree 1, 2 or 3; a
  fixed "true" polynomial of that degree (`TruePoly` - `1 + 2x`, then
  `- 1.5x^2`, then `+ 0.8x^3`, each extending the last) is sampled at 50
  evenly spaced x in [-3, 3], N(0, sigma) noise from a spin edit is
  added, and a polynomial of the same degree is fitted back with the
  `Fit(X, Y, Degree, out Residuals, out StdError)` overload, so the
  residual plot and the standard error come from the one call. Upper
  plot: noisy points as circles (`plsNone` + `pmsCircle`), true curve
  dashed blue, fit solid red - all three on the same 50-point grid, a
  cubic being smooth enough at that spacing that one `SetData` call
  carries them (`SetData` needs one shared `X`). Lower plot: residuals
  as circles against a dotted zero line. A memo lists true and fitted
  coefficients and `s` against the generating sigma - with the right
  degree `s` lands near sigma. "New data" redraws the noise with
  `Math.RandG`, deliberately not `TVMobj.fillRandom`, whose fixed 777
  seed would return the identical noise every click. Both plots are
  created in code inside a client-aligned panel (fit plot `alTop` at
  three fifths of the height, kept there by the panel's `OnResize`,
  residual plot `alClient`), the same pattern as `Graphs/Plot2D`.
  Requires `LazOpenGLContext` and `LCL`, with `OtherUnitFiles=
  ../..;../../Graphs` for `uVMPlot2D`. One `.lfm` gotcha hit while
  writing it: a hand-written `ChildSizing.ShrinkHorizontal =
  crsScaleChildsToFit` on the `TRadioGroup` is not a valid enum name and
  fails at form load with "Error reading rgDegree.ChildSizing..." -
  caught only by screenshotting the running demo, not by the build;
  `AutoFill` alone lays the buttons out fine.
- **`SpectralDiff`** — Chebyshev spectral differentiation of
  `f(x) = exp(x)*sin(5x)` (the example function, from Trefethen's
  *Spectral Methods in MATLAB*) via `DCT1` (newVM.pas's FFTW-backed
  DCT-I), recoded from the original raw-FFTW3 demo at
  `/home/howard/projects/Lazarus/fftw3` (`unit1.pas`/`project1.lpr`) so it
  goes through `TVMobj`/`DCT1` instead of calling
  `fftw_plan_r2r_1d`/`fftw_execute_r2r` directly. Samples `f` at the `N+1`
  Chebyshev points `x_i = cos(pi*i/N)` (`N=32`), transforms to Chebyshev
  coefficient space via `DCT1`, differentiates the coefficient series via
  the recursion from Boyd's *Chebyshev and Fourier Spectral Methods*
  (`Recurr`, ported verbatim from the original demo's `recurr`), then
  transforms back via `DCT1` again (each `DCT1` call is unnormalized -
  see "FFT/DCT/DST functions" above - so the result is scaled by
  `Logical_N = 2*N`, divided back out explicitly). Plots the spectral
  derivative against the exact derivative plus their difference; the
  error plot typically shows ~1e-13 to 1e-14 (double-precision noise),
  demonstrating spectral accuracy. Times the whole differentiation
  `NumRuns=5` times from scratch and reports the average over all but the
  first run (which pays FFTW's one-time internal setup cost and would
  otherwise skew a single-shot timing).

### `Graphs/`

Two standalone Lazarus GUI projects (same shape as `demos/` - own
`.lpi`/`.lpr`/form unit/`.lfm`, built against the top-level units in place
via `OtherUnitFiles=../..`) demonstrating OpenGL-rendered 2D/3D graphs of
real (`TVMobj`) vectors and matrices, as opposed to `demos/FunctionPlot`'s
`TAChart`-based 2D line plot. Build with `lazbuild --lazarusdir=<path>
Graphs/<Name>/<Name>.lpi`, same as `demos/`. Both require the
`LazOpenGLContext` package (not `TAChartLazarusPkg`) and `LCL`, and both
`uses ... GL, ... OpenGLContext` (`Plot3D` additionally `uses GLU` for
`gluPerspective`) - FPC's own bundled OpenGL 1.x bindings plus the LCL's
`TOpenGLControl`, which creates/manages the GL context the same way
`TChart` manages its own drawing surface. `lib/` output is covered by the
top-level `.gitignore`'s unscoped `lib/` pattern; the extensionless Linux
binaries (`Graphs/Plot2D/Plot2D`, `Graphs/Plot3D/Plot3D`) needed their own
`Graphs/*/[A-Za-z]*` rule, mirroring the one `demos/*/` already has (the
unscoped `*.exe` rule alone only catches Windows builds).

`Plot2D`'s rendering logic no longer lives in the demo itself - it's a
standalone, reusable component (`uVMPlot2D.pas`, top level of `Graphs/`,
alongside `OpenGLAdapter.pas`) that any form can drop in; see the dedicated
`Graphs/uVMPlot2D.pas` section below. `Plot3D` has not been componentised
the same way and still keeps its rendering code directly in its form unit.

`OpenGLAdapter.pas` (top level of `Graphs/`, not part of either project) is
**not used by either demo** and can't currently be built into anything:
despite the filename, it's actually `GLS.OpenGLAdapter.pas` from the
GLScene engine, and it `uses` six further GLScene units (`Stage.Defines.inc`,
`Stage.OpenGLTokens`, `Stage.Strings`, `Stage.Logger`,
`Stage.VectorGeometry`, `Stage.VectorTypes`) that aren't present anywhere
in this repo, plus Delphi-only namespaced units (`Winapi.OpenGL`,
`Winapi.Windows`) that don't exist in Free Pascal at all - pulling in the
rest of GLScene just to compile this one adapter file would be a large,
fragile undertaking for no benefit over the units FPC/Lazarus already
ship. Both demos use FPC's native `GL`/`GLU` units and the LCL's
`TOpenGLControl` instead (confirmed present in this Lazarus install:
`fpc/3.2.2/units/x86_64-win64/opengl/{gl,glu}.ppu`,
`lazarus/components/opengl/`) - the standard, well-supported path for
OpenGL in Lazarus, requiring no GLScene dependency at all. Leave
`OpenGLAdapter.pas` alone rather than trying to wire it in.

- **`Plot2D`** — demonstrates `uVMPlot2D.pas`'s `TVMPlot2D` component (see
  the dedicated section below) by plotting two related series over the
  same `x`: `y = exp(-0.1*x^2) * sin(3*x)` (same base function as
  `demos/FunctionPlot`) and its cosine-phase sibling
  `exp(-0.1*x^2) * cos(3*x)`, styled as a solid red line and a dashed blue
  line respectively (`TForm1.FormCreate`, `uplot2dmain.pas`). The form
  itself has no `TOpenGLControl` in its `.lfm` at all - `TVMPlot2D` is
  created and `Parent`ed to the form entirely in code, the same way any
  LCL component can be added to a form at runtime without a design-time
  package installed. All the OpenGL rendering logic that used to live
  directly in this demo's form unit (auto-fitted `glOrtho` projection,
  GL-texture-cached title/tick text, the two-pass data/chrome paint
  handler) has moved into the component; this unit now only builds the
  `TVMobj` data and sets a few properties.

### `Graphs/uVMPlot2D.pas` (`TVMPlot2D` component)

A reusable `TOpenGLControl`-descended LCL component - not tied to the
`Plot2D` demo - that plots up to `VMPlotMaxSeries` (10) series, each its
own `x`/`y` pair, generalising what used to be `Plot2D`'s single-series,
hand-rolled-per-form OpenGL code (see git history of `uplot2dmain.pas`
for the original version this was lifted from) into something any form
in this repo (or a future one) can drop in and reuse. Like the rest of
`Graphs/`, it requires the `LazOpenGLContext` package and `uses GL,
OpenGLContext`. Internally, `FXData`/`FYData` are both
`array[0..VMPlotMaxSeries-1] of TVMPlotSeriesData` - i.e. every series
has always stored its own `X` array, even though `SetData` (below) makes
those all identical copies of one shared `X` for callers who don't need
per-series grids.

- **Data, bulk**: `procedure SetData(const X: TVMobj; const YSeries:
  array of TVMobj)` - a single call takes `X` plus an open array of 1..10
  `Y` vectors (asserted; `TVMPlot2D.SetData` rejects 0 or >10), all
  sharing that one `X`. Each vector may be row `(1,N)` or column `(N,1)`
  shaped, per newVM's usual convention. `TVMobj` is a record, not a
  class, so it can't be a published/streamable property (Delphi/Lazarus
  property streaming only supports simple types, sets, classes, and
  interfaces) - data assignment is necessarily a method call, not
  something editable in the Object Inspector. Replaces every series
  passed in wholesale - `FXData[iser] := Copy(XVals, 0, N)` (its own copy
  of `X`, not a shared reference) and a fresh `FYData[iser]`, discarding
  whatever was there before, marking `FUserDataStarted` (see `PlotXY`).
- **Data, incremental**: `procedure PlotXY(X, Y: Double; PlotLine:
  Integer)` appends one `(X,Y)` point to series `PlotLine`, extending it
  by one - for building a series up over time (streaming/interactive
  data) rather than from a pre-built `TVMobj` vector. Since every series
  already stores its own `X` internally, appending to one `PlotLine`
  never touches any other series, and different series can have
  completely different point counts and grids - e.g. a coarse discrete
  series and a fine interpolated one plotted together, which `SetData`
  alone can't do (its `X` is shared across the whole call). The one
  wrinkle: a fresh component's series 0/1 already hold the constructor's
  own placeholder demo data (see "Default demo data" below) - without
  special-casing that, a caller's first-ever `PlotXY` call on a new
  component would silently append onto the tail of that demo data rather
  than starting the caller's own series from scratch. `FUserDataStarted`
  (`False` only until a real caller's first `SetData`/`PlotXY` call - the
  constructor's own default-demo `SetData` call explicitly resets it to
  `False` again immediately after, since that call doesn't count) is the
  fix: `PlotXY`'s first real invocation clears every series before
  appending its own point, exactly once.
- Both recompute the combined bounding box (every series' `X` and `Y`
  alike) plus tick positions from scratch on every call - factored into
  the shared private `RecomputeBounds` - so the auto-fit `glOrtho`
  projection and axis labels always cover whichever series are currently
  plotted, whichever of the two methods populated them. Fine for
  interactive/streaming `PlotXY` use at a reasonable point rate, but each
  call is `O(total points across every series)`, not optimised for very
  high-frequency appends against an already-large series.
- **Per-series style**: `LineColor`/`LineWidth`/`LineStyle`
  (`plsSolid`/`plsDash`/`plsDot`/`plsNone`, drawn via `GL_LINE_STIPPLE` -
  the only way to get non-solid `GL_LINE_STRIP` rendering in fixed-function
  OpenGL 1.x; `plsSolid` explicitly disables stippling rather than using an
  all-ones pattern, since a stipple factor can still subtly affect
  anti-aliased line rendering on some drivers; `plsNone` skips the line
  strip entirely, both in `Paint` and in `DrawLegend`'s swatch) plus
  `MarkerShape`/`MarkerSize` (see below) live on `TVMPlotSeriesStyle`
  (a `TCollectionItem`), collected in the published `Series:
  TVMPlotSeriesStyles` property (a `TOwnedCollection`) - editable per-slot
  in the Object Inspector at design time regardless of whether data has
  been assigned yet. The constructor pre-populates all 10 slots with a
  fixed "tab10"-style categorical default palette
  (`DefaultPaletteR`/`G`/`B`), so multiple series are already
  distinguishable even if the caller never touches styling. For runtime
  code, `procedure SetSeriesStyle(Index: Integer; AColor: TColor;
  ALineWidth: Single; AStyle: TVMPlotLineStyle; const AName: string = '';
  AMarkerShape: TVMPlotMarkerShape = pmsNone; AMarkerSize: Single = 6.0)`
  is a one-call convenience wrapper over setting the `TVMPlotSeriesStyle`
  properties individually - the two marker parameters are trailing/
  optional specifically so every pre-existing call site (across all the
  demos) keeps compiling unchanged. `TVMPlotSeriesStyles.Update` (the
  standard `TCollection`/`TOwnedCollection` change-notification hook)
  calls back into the owning `TVMPlot2D.Invalidate` whenever any series
  property changes, so edits - whether from the Object Inspector or from
  `SetSeriesStyle` - repaint immediately without the caller needing to
  call `Invalidate` themselves.
- **Point markers**: `MarkerShape` (`pmsNone`/`pmsSquare`/`pmsDiamond`/
  `pmsCircle`, default `pmsNone` - markers are strictly opt-in, so no
  existing series' appearance changes) and `MarkerSize` (pixels, constant
  regardless of the data-space zoom/aspect ratio, the same convention
  `LineWidth`'s `glLineWidth` already uses) draw a glyph at every data
  vertex, filled with the series' own `LineColor` and outlined in a fixed
  thin black line - `DrawMarker` draws one glyph (two `glBegin`/`glEnd`
  passes, fill then outline, since a single filled OpenGL 1.x primitive
  can't carry a differently-coloured edge), `DrawMarkers` calls it once
  per vertex for every series with a shape set. Markers are independent
  of `LineStyle`: a series can show a line, markers, or both together;
  `LineStyle=plsNone` with a `MarkerShape` set gives a points-only series
  (e.g. a discrete/collocation series plotted point-by-point, as distinct
  from a smooth interpolated one drawn as a line) - the original
  motivating case (`demos/Chebyshev/ChebBVP_FPC`'s raw N+1-point
  collocation solution `V`, currently *not* plotted at all - see that
  demo's own header comment) still can't combine with the fine
  interpolated curve in one `SetData` call even with markers available,
  since `SetData` requires one shared `X` across every series and `V`
  lives on a different, coarser grid than the interpolated curve's
  display grid. Drawn in pass 2 (pixel space), not pass 1's data-space
  `glOrtho`, precisely so `MarkerSize` stays a constant pixel size - the
  same reason tick labels are pixel-space chrome rather than data-space
  text; `DrawMarkers`' `PX`/`PY` reuse the exact linear-map formula
  `Paint`'s own tick-mark loop already uses to go from a data value to a
  pixel position. `DrawLegend` draws a matching marker glyph (capped to
  the row height) beside each named series' line swatch, in its own pass
  after the swatches (`DrawMarker` sets its own colours per call, so
  interleaving it into the swatch loop would mean re-establishing
  `ApplyLineStyle`'s state after every marker).
- **Titles**: `Title`/`XAxisTitle`/`YAxisTitle` are plain published
  `string` properties (unlike series data, ordinary types stream and
  edit fine).
- **Text rendering, layout, and everything else** (the GL-texture-cached
  title/axis-title/tick-label approach, the two-pass data-space-then-
  pixel-space paint handler, `ComputeTicks`/`NiceNum` for "nice"
  round-number tick values) is unchanged from the original single-series
  `Plot2D` demo code - see the TEXT RENDERING/LAYOUT notes in
  `uVMPlot2D.pas`'s header comment for the full rationale, not repeated
  here. Two things *did* need to change versus that original one-shot-demo
  code, since a reusable component can have its data/titles changed
  arbitrarily many times over its life rather than being set once in
  `FormCreate`: text textures are rebuilt (`BuildTextures`, called lazily
  from `Paint`) whenever `InvalidateTextures` marks them stale (on any
  `SetData` or title-property change), and the old GL textures are
  explicitly deleted first (`FreeAllTextures`, called from both
  `BuildTextures` and `Destroy`) rather than only ever allocated once, to
  avoid leaking a texture per change over the component's lifetime.
- Overrides `Paint` (not `OnPaint`) and `Resize` directly rather than
  wiring the `.lfm`-based `OnPaint`/`OnResize` event pattern the original
  demo used, since a genuinely reusable component shouldn't require its
  *user* to hook up paint/resize events by hand for it to work - it just
  needs `Parent`/`Align` set and `SetData` called. `RegisterComponents`
  is wired up via a `Register` procedure, picked up by the `newVMGraphs`
  design-time package (see below) for IDE component-palette installation;
  it also still works exactly as `Plot2D`'s demo form uses it, with no
  package involved at all - `TVMPlot2D.Create(Owner)` plus `Parent :=
  SomeForm` in code.
- One naming gotcha hit while writing this: a local variable in
  `CreateTextTexture` was originally named `RGBA` (matching the original
  demo code's variable name for its pixel buffer), which collides with
  `TCustomOpenGLControl`'s own inherited `RGBA` property - FPC treats this
  as a hard "duplicate identifier" compile error inside a method of a
  descendant class, not a shadowing warning, because inherited class
  members are in scope alongside locals there. Renamed to `TexPixels`.
  Worth checking for if a future edit reintroduces a local/field named
  after any `TCustomOpenGLControl` property (`RGBA`, `AlphaBits`,
  `DepthBits`, etc.).
- **Default demo data**: the constructor populates the same
  `exp(-0.1x^2).{sin(3x),cos(3x)}` example `Plot2D`'s demo form builds in
  `FormCreate`, calling `SetData`/`SetSeriesStyle` itself, so a
  freshly-dropped component already shows a representative plot rather
  than a blank white rectangle - both in the Form Designer at design time
  and at runtime before any real `SetData` call (a caller's own `SetData`,
  as the demo's `FormCreate` still does, simply replaces it). Built via a
  plain per-element loop and scalar `Math.Sin`/`Cos`/`Exp`, **not** the
  demo's own `linspace`/elementwise-VML/operator-overload version (which
  calls into MKL/IPP) - see "Design-time rendering" below for why.
- **Design-time rendering** (applies to `TVMPlot3D` too, see below): two
  separate problems surfaced when first testing "drop the component in the
  IDE and see the default plot live", both found by comparing why
  `TVMPlot3D` (which never calls MKL/IPP for its default data - see its
  own section below) behaved differently from `TVMPlot2D` (which
  originally did):
  1. Calling into MKL/IPP (`linspace`, elementwise VML `Exp`/`Sin`/`Cos`,
     the `cblas`-backed operator overloads) from a constructor that also
     runs *inside the Lazarus IDE's own process* - true for any
     `RunAndDesignTime` package's components, since they're statically
     linked into the IDE binary (see `newvmgraphs.lpk` below) - crashed
     the IDE with an access violation the moment a `TVMPlot2D` was dropped
     from the palette, even though the exact same MKL calls work fine in
     the standalone `Plot2D.exe` demo. Root cause not pinned down further
     (never got past "MKL/IPP calls are unsafe from inside this
     particular host process"); the fix was to stop making those calls in
     the constructor at all, converging on the same MKL/IPP-free
     plain-loop approach `TVMPlot3D.BuildDefaultDemoMatrix` already used
     (for an unrelated reason) - not just a workaround, since it's a
     strictly simpler/safer implementation with identical numeric output.
  2. Separately, `TCustomOpenGLControl` (`LazOpenGLContext`,
     `openglcontext.pas`) deliberately skips real GL rendering under
     `csDesigning` unless `ocoRenderAtDesignTime` is set in its `Options`
     property (`TCustomOpenGLControl.IsOpenGLRenderAllowed`) - without
     this, `TVMPlot3D` dropped onto a form with no crash, `SetData`
     completed and `FHasData` was `True`, yet the Form Designer still
     showed nothing (confirmed via testing: it *did* render correctly at
     runtime, and resizing/reselecting the design-time control made no
     difference - ruling out a simple missed-repaint theory). Fixed by
     setting `Options := Options + [ocoRenderAtDesignTime];` early in each
     component's constructor.
  Both fixes are required together for the Form Designer preview to work
  at all; either alone leaves one of the two components broken (crash, or
  silently blank).
- **Palette icon**: a 24x24 PNG (`Graphs/TVMPlot2D.png` - a small red
  decaying-sine curve over grey axes) compiled to a Lazarus resource
  include via `lazres` (`C:\Lazarus\tools\lazres.exe` on this machine):
  `lazres uvmplot2d_icon.lrs "TVMPlot2D.png=TVMPlot2D"` - the explicit
  `=TVMPlot2D` resource name (matching the class name exactly, `T`
  included) is required since `lazres`'s default (derived from the input
  filename) would otherwise be case-sensitive-fragile. The generated
  `uvmplot2d_icon.lrs` is a *text* `LazarusResources.Add('TVMPlot2D',
  'PNG', [...])` call (not a compiled binary resource), pulled in via
  `{$I uvmplot2d_icon.lrs}` right before `RegisterComponents` inside
  `Register` - this exact pattern (name/placement) was confirmed against
  Lazarus's own bundled `components/anchordocking/anchordockpanel.pas`
  before writing it here. Requires `LResources` in the `uses` clause (the
  global `LazarusResources.Add` the generated file calls into) - omitted
  at first, which fails to compile with "Identifier not found
  'LazarusResources'". The source `.png` is kept in the repo alongside the
  generated `.lrs` so the icon can be regenerated/edited later without
  needing to reverse-engineer the resource file.

### `Graphs/newvmgraphs.lpk` (`newVMGraphs` design-time package)

The Lazarus package that gets `TVMPlot2D` and `TVMPlot3D` into the IDE's
component palette, following the same two-file shape every Lazarus
package uses (compare `lazopenglcontext.lpk`/`.pas` in the Lazarus source
tree itself, under `components/opengl/`): `newvmgraphs.lpk` is the
package's XML definition (`Type=RunAndDesignTime`, `RequiredPkgs`:
`LazOpenGLContext` and `LCL`, `OtherUnitFiles=..` so it can find
`newVM.pas` and its sibling units one level up in the repo root, plus
`GL`/`GLU` for `TVMPlot3D` - see the `uVMPlot3D.pas` section above for why
those need no extra `RequiredPkgs` entry of their own); `newvmgraphs.pas`
is the small auto-generated-style registration unit (`uses uVMPlot2D,
uVMPlot3D, LazarusPackageIntf`, calling `RegisterUnit`/`RegisterPackage`
once per component) - **do not hand-edit this file**, the same "Do not
edit!" comment Lazarus itself puts at the top of every package unit
applies here too; when `TVMPlot3D` was added, both the `.lpk`'s `<Files>`
list and this unit's `uses`/`RegisterUnit` calls needed the same
one-line-per-component addition as `TVMPlot2D`'s existing entries - if
`Graphs/` grows further components later, follow that same pattern rather
than editing this unit's `uses` clause by hand outside the IDE's package
editor.

Only `<Files>` entries are actual component units - the package's own
`newvmgraphs.pas` is *not* listed there (it's implicit: a package's main
source file is always `<PackageName lowercased>.pas`, matching the
`<Name>` in the `.lpk`), which was confirmed against several of Lazarus's
own bundled packages (`lazopenglcontext.lpk`, `components/sdf/sdflaz.lpk`)
before writing this one - a `.lpk` that also lists its own main unit under
`<Files>` would double-compile it.

Installing this **rebuilds the Lazarus IDE binary itself** (packages
marked `RunAndDesignTime` get statically linked into the IDE executable,
not `dlopen`'d at runtime) - a real, if routine and reversible, change to
the local Lazarus install, done here via:
```
lazbuild --lazarusdir=<path> --add-package-link Graphs/newvmgraphs.lpk
lazbuild --lazarusdir=<path> --add-package newVMGraphs --build-ide=
```
(equivalently: open `Graphs/newvmgraphs.lpk` in the IDE's Package Editor
and use Install). Once the package link and install-list entry already
exist (as they do after the first install), picking up a *newly added*
component - as when `TVMPlot3D` joined `TVMPlot2D` here - only needs the
second `--build-ide=` line rerun, not `--add-package-link`/`--add-package`
again. `--build-ide=` backs up the previous IDE binary to `lazarus.old`
before relinking - Lazarus's own safety net if a rebuilt IDE somehow fails
to start, not something this repo manages. After installing, both
components appear in the component palette under the "newVM" tab
(`RegisterComponents('newVM', [TVMPlot2D])` in `uVMPlot2D.pas`,
`RegisterComponents('newVM', [TVMPlot3D])` in `uVMPlot3D.pas`) and can be
dropped onto any form's `.lfm` directly, in addition to the
always-available `TVMPlotN.Create(Owner)` code path both demos use.
- **`Plot3D`** — demonstrates `uVMPlot3D.pas`'s `TVMPlot3D` component (see
  the dedicated section below) with the same `z = sin(r)/r`, `r =
  sqrt(x^2+y^2)` "sinc ripple" surface as before, over a 51x51 grid, built
  as a real `TVMobj` matrix (`TForm1.BuildDemoMatrix`, `r=0`'s removable
  singularity still handled explicitly). As with `Plot2D`, the form's
  `.lfm` no longer contains a `TOpenGLControl` at all - `TVMPlot3D` is
  created and `Parent`ed to the form in code (`FormCreate`, which also
  sets `Title`/`XAxisTitle`/`YAxisTitle`/`ZAxisTitle` before `SetData`),
  and the `WireframeCheckBox`/`ShowAxesCheckBox`/`LevelCurvesCheckBox`/
  `ResetViewButton` controls (still declared in the `.lfm`, since they're
  ordinary `TCheckBox`/`TButton` chrome outside the plot itself) just
  forward to the component's `Wireframe`/`ShowAxes`/`ShowLevelCurves`
  properties and `ResetView` method instead of reading/writing form-level
  fields directly.

### `Graphs/uVMPlot3D.pas` (`TVMPlot3D` component)

A reusable `TOpenGLControl`-descended LCL component - not tied to the
`Plot3D` demo, added to the `newVMGraphs` design-time package (see above)
alongside `TVMPlot2D` - that renders a real `TVMobj` matrix as a lit,
Gouraud-shaded height-field surface. Lifted out of the original
single-form `Plot3D` demo code the same way `TVMPlot2D` was lifted out of
`Plot2D`'s (see git history of `uplot3dmain.pas` for the pre-extraction
version); requires `LazOpenGLContext` and `uses GL, GLU, OpenGLContext`
(`GLU` only for `gluPerspective` - like `GL`, it's an FPC-bundled unit,
not part of the `LazOpenGLContext` Lazarus package, so no extra
`RequiredPkgs` entry was needed for it).

- **Data**: `procedure SetData(const M: TVMobj)` - takes any real `TVMobj`
  matrix (no shape assert - unlike `TVMPlot2D`'s vectors-only contract,
  a height field is defined for any `Rows`x`Cols`, degenerate 1-row/1-col
  cases included). Named `SetData` for parity with `TVMPlot2D`'s entry
  point, though the underlying rescale-and-centre logic (`WorldSize`/
  `ZScale` constants, per-vertex normal via `ComputeNormal`, per-vertex
  colour via the 4-stop `HeightToColor` gradient) is ported unchanged
  from the demo's original `BuildSurface` - see that function's own
  comments for why it rescales any matrix to the same on-screen scale
  regardless of actual magnitude or dimensions.
- **Interactive camera, self-contained**: unlike `TVMPlot2D` (a static
  orthographic view needing no interaction) a 3D height field is far less
  legible without being able to orbit it, so - unlike the original demo,
  which wired `OpenGLControl1`'s `OnMouseDown`/`OnMouseMove`/`OnMouseUp`/
  `OnMouseWheel` events by hand in the form - `TVMPlot3D` overrides
  `MouseDown`/`MouseMove`/`MouseUp`/`DoMouseWheel` directly so the camera
  works with zero wiring: drag rotates (yaw/pitch, pitch clamped to
  ±179° via `EnsureRange` - see below for why this isn't the tighter ±89°
  a first glance might expect), wheel zooms (`FDistance`, clamped to
  `[3,40]`). `ResetView` (a public method) restores the tuned default
  framing (`DefaultYaw=20, DefaultPitch=-45, DefaultDistance=16`);
  there's no published `Yaw`/`Pitch`/`Distance` property, since those are
  live interactive camera state driven by mouse input, not meaningful
  design-time configuration - `ResetView` is the supported way to reset
  them programmatically.

  Getting the camera to actually show the *top* of the height field,
  correctly lit, took several screenshotted iterations and two real wrong
  turns worth recording so they aren't retried. The underlying fact that
  resolves all of them: the camera's own WORLD-space position, given the
  `glTranslatef(0,0,-FDistance); glRotatef(FPitch,1,0,0);
  glRotatef(FYaw,0,1,0)` transform `Paint` applies to the *scene* (not the
  camera - so it has to be un-transformed to find where the camera itself
  actually sits), works out to `(-D*cos(pitch)*sin(yaw), D*sin(pitch),
  D*cos(pitch)*cos(yaw))`. With the original `FYaw=35, FPitch=45`, that Z
  component is negative - the camera is genuinely *below* the surface
  (whose own Z only spans roughly ±1.25), not just apparently so from a
  bad viewing angle.
  - First wrong turn: shrinking yaw towards 0 (tried at `FYaw=20`,
    `FPitch` still `45`) only reduces the Value/Z axis's on-screen
    horizontal drift (`WorldToScreen`'s sign for that direction is
    `-cos(yaw)*sin(pitch)`) - it doesn't flip which vertical direction
    Value points, and it doesn't fix the camera-Z sign either. A
    more-vertical *downward* line is easy to mistake for an upward one at
    a glance, which is what made this look like a fix at the time.
  - Second wrong turn: pushing `FYaw` on to `-160` instead (keeping
    `FPitch=45`) does correctly flip Value's vertical sign and gives a
    well-proportioned view - but `cos(pitch)*cos(yaw)` is still negative
    at that combination, so the camera is *still* below the surface. Two
    lighting-side attempts to paper over this - `GL_LIGHT_MODEL_TWO_SIDE`
    (relying on GL's winding-based front/back test to auto-flip the
    normal for back-facing triangles) and then `FPitch=135` (a further
    +90, on the theory that it flips the same sign `FPitch=-45` would
    have) - both fell short: the two-sided-lighting flip isn't guaranteed
    to agree with `ComputeNormal`'s own sign convention, so it didn't
    reliably fix the reported "lit from underneath" symptom; and
    `sin(135)=sin(45)` exactly (a supplementary-angle identity), so that
    pitch change left Value's direction completely unchanged and instead
    flipped *Row's* (which depends on `cos(pitch)`) from up to down -
    worse, not better, and *still* doesn't touch the camera-Z sign either.

  The fix that actually works, arrived at by solving `cos(pitch)*cos(yaw)
  > 0` (camera above the surface) simultaneously with `cos(pitch) > 0`
  (Row points up) and `-cos(yaw)*sin(pitch) > 0` (Value points up):
  `FYaw=20, FPitch=-45`. Because this needs `FPitch` well past the
  original ±89° drag clamp, that clamp is widened to ±179° (`MouseMove`) -
  avoiding only the exact poles at ±180°, where this simple sequential-
  Euler-angle camera would degenerate into gimbal lock. `Paint` also now
  positions the light in EYE space (i.e. specifies it before the camera
  rotate/translate calls run, while `GL_MODELVIEW` is still identity)
  rather than in the same scene-fixed space as the geometry - a "headlamp"
  that shines from the viewer's own position, so whatever face is actually
  visible is - by construction, regardless of which side of the mesh that
  turns out to be - the one facing the light. `GL_LIGHT_MODEL_TWO_SIDE`
  is kept as a second line of defence alongside it. The headlamp's
  direction is deliberately offset up and to one side
  (`lightPos=(0.5,-0.6,0.65,0)`) rather than aimed straight down the view
  axis (`(0,0,1,0)`, tried first): a light aimed exactly along the view
  direction lights every visible triangle almost head-on, which is
  technically correct but reads as flat and dim, since there's no `N.L`
  falloff left to create the light/dark contrast that makes a
  Gouraud-shaded surface read as three-dimensional. `Paint` also raises
  `GL_LIGHT_MODEL_AMBIENT` from GL's own default `(0.2,0.2,0.2,1)` to
  `(0.35,0.35,0.35,1)` - purely a brightness floor for whatever the
  angled directional light doesn't reach, independent of the
  directionality fix above. `lightPos[1]` (Y) is negative despite that
  being meant to place the light "above" the viewer - confirmed
  empirically rather than derived, since reasoning through eye-space sign
  conventions for this light kept not matching what actually rendered: a
  positive Y showed the surface's actual peak (which `HeightToColor`
  should render as the most saturated red) dark/muted while a lower
  side-slope lit up instead - the signature of light hitting the
  underside of the slopes - and only flipping the sign to negative, then
  re-screenshotting to confirm the peak became the brightest point as
  expected, actually fixed it.
- **Published toggles**: `Wireframe: Boolean` (drives
  `glPolygonMode(GL_FRONT_AND_BACK, GL_LINE/GL_FILL)` - previously the
  paint handler read an external `WireframeCheckBox.Checked` directly,
  which only worked because the demo happened to have exactly that
  checkbox; a reusable component needs its own field, with a host
  `TCheckBox`'s `OnChange` forwarding into it instead, same as `Plot3D`'s
  demo now does) and `ShowAxes: Boolean` (default `True`, matching the
  original always-on behaviour) toggling the X/Y/Z axis lines
  (`DrawAxisLines`) plus their tick marks/labels and axis titles
  (`DrawAxisLabels`) - the main `Title` stays visible either way, since it
  isn't part of the axis gizmo. A third toggle, `ShowLevelCurves: Boolean`
  (default `False`), draws contour ("level curve") lines on the surface at
  each of the same "nice" Z values already labelled on the Value axis
  (`FZTicks`) - see `DrawLevelCurves` below. Skipped entirely in wireframe
  mode (`if (not FWireframe) and FShowLevelCurves` in `Paint`), since a
  contour line has no independent visual meaning against a mesh that
  already shows every grid edge.
- **`DrawLevelCurves`**: per-tick, per-quad marching-triangles contour
  extraction - for each `FZTicks[i]` strictly between `FZMin`/`FZMax`
  (converted to the same world-space Z the surface itself is drawn in, via
  the `((tick-FZMin)/zRange - 0.5)*ZScale` formula used throughout this
  unit), every grid quad is split into its two existing triangles
  (matching the `GL_TRIANGLE_STRIP` winding `Paint` already draws) and each
  triangle's three edges are tested for a sign change in `Z - level`
  (`TryEdge`); exactly two edges of a triangle can cross a given level (a
  triangle can't cross a plane on all three edges), so `ContourTriangle`
  collects up to two linearly-interpolated crossing points and emits them
  as one `GL_LINES` segment. No BLAS/LAPACK/IPP/GL primitive does contour
  extraction, so - like `Find`/`Gather` in the main library - this is a
  plain nested loop. Drawn unlit (`glDisable(GL_LIGHTING)`, dark grey,
  `glLineWidth(1.5)`) directly on top of the already-drawn filled surface;
  to avoid z-fighting between the contour lines and the coplanar filled
  triangles, `Paint` enables `GL_POLYGON_OFFSET_FILL`/`glPolygonOffset(1.0,
  1.0)` around the filled-surface draw call whenever `FShowLevelCurves` is
  set (pushing the filled polygons back very slightly in depth), then
  disables it before calling `DrawLevelCurves`.
- **Title/axis titles and axis scales**: `Title`/`XAxisTitle`/
  `YAxisTitle`/`ZAxisTitle` are published string properties (each setter
  calls `InvalidateTextures` + `Invalidate`, mirroring `TVMPlot2D`'s
  `Title`/`XAxisTitle`/`YAxisTitle`), plus full-span axis lines with a
  point marker and "nice"-rounded value label at each tick
  (`ComputeTicks`/`NiceNum`, ported the same as `TVMPlot2D`'s). Since
  `SetData` only ever sees a plain `Rows x Cols` matrix - not whatever
  domain, if any, the caller sampled it over - the X/Y ticks are labelled
  by column/row index (the one thing always knowable about an arbitrary
  matrix) and the Z ticks by `M`'s actual value range (`FZMin`/`FZMax`,
  persisted as fields precisely so the tick/label code can use them after
  `SetData` returns).
- **Text rendering** reuses `TVMPlot2D`'s texture-based technique (each
  title/tick-label string rendered once via the LCL font engine to a
  `TVMPlotTextTexture`, with the same `Built`-flag/`FreeAllTextures`/
  `InvalidateTextures` lifecycle and the same termination-safe
  `destructor Destroy` guard - `if HandleAllocated and MakeCurrent then
  FreeAllTextures`, see `TVMPlot2D.Destroy`'s comment for why) - with one
  deliberate difference: `TVMPlot2D`'s plot background is white, so its
  `CreateTextTexture` bakes in always-black text, but this control's
  background is dark (`glClearColor 0.12,0.12,0.16`), so black text there
  would be nearly invisible - `CreateTextTexture` here takes an explicit
  `TR,TG,TB` colour parameter instead, and `BuildTextures` uses yellow for
  `Title` and light grey for the axis titles/tick labels.
- **`WorldToScreen`**: unlike `TVMPlot2D`'s fixed pixel-space label
  positions, this control's axes rotate with the mouse-driven camera, so
  tick/title screen positions must be recomputed every frame.
  `WorldToScreen` projects a 3D world point to screen pixel coordinates by
  replaying - in plain Pascal, not via a GL matrix query - the exact
  camera transform `Paint` sets up on the GL matrix stack
  (`glTranslatef(0,0,-FDistance); glRotatef(FPitch,1,0,0);
  glRotatef(FYaw,0,1,0)`, then `gluPerspective`), by hand: deliberate,
  over calling `gluProject` to read the GL matrices back out, since GLU's
  exact FPC signature isn't available to check locally (only a compiled
  `glu.ppu`, no bundled `.pas` source) and this camera transform is simple
  enough to duplicate directly with no ambiguity about what it computes.
  `Paint` therefore does *not* switch to a pixel-space `glOrtho`/
  `glViewport` before computing label positions - `DrawAxisLabels` runs
  and calls `WorldToScreen` for every tick/title while the 3D camera
  transform is still the active `GL_MODELVIEW`/`GL_PROJECTION` state, and
  only the final `glOrtho(0,Width,0,Height,...)`/`glViewport` switch (for
  actually drawing the resulting 2D label quads) happens afterward.
- `Paint` unconditionally clears/lights the scene and draws the axis
  gizmo (if `ShowAxes`) even before any `SetData` call (`FHasData` only
  gates the actual surface `GL_TRIANGLE_STRIP` draw), so a freshly-dropped
  component with no data yet still renders a sane, non-blank dark-grey
  viewport rather than nothing.
- `Resize` is overridden the same way as `TVMPlot2D`'s (`inherited
  Resize; Invalidate;`), since `AutoResizeViewport` is left at its default
  `False` and the viewport is instead recomputed by hand from `Width`/
  `Height` at the top of every `Paint` call.
- **Default demo data**: the constructor calls a new `BuildDefaultDemoMatrix`
  method (the same 51x51 `z = sin(r)/r` "sinc ripple" surface as the
  `Plot3D` demo's own `TForm1.BuildDemoMatrix`) and feeds it straight into
  `SetData`, plus sets the same `Title`/axis titles - same rationale and
  same "harmless to overwrite, a caller's own `SetData` just replaces it"
  caveat as `TVMPlot2D`'s default data (see that unit's section above).
  Built entirely from a plain nested loop and scalar `Math.Sin`/`Sqrt` -
  no MKL/IPP calls at all (`TVMobj.Create`/`Element[r,c]` are themselves
  plain dynamic-array operations) - which is exactly why this component
  never hit the MKL-in-the-IDE-process access violation `TVMPlot2D`'s
  original (elementwise-VML) default-data version did; see that unit's
  "Design-time rendering" note for the full story, including the separate
  `ocoRenderAtDesignTime` fix this component also needed (confirmed by
  testing: without it, this component dropped into the Form Designer
  without crashing and `FHasData` genuinely was `True`, yet nothing
  rendered - and it stayed blank even after resizing/reselecting the
  control, which is what pointed at `TCustomOpenGLControl` suppressing GL
  rendering under `csDesigning` rather than a missed-repaint).
- **Palette icon**: same `lazres`-compiled, `{$I}`-included-in-`Register`
  approach as `TVMPlot2D`'s (see that unit's section above for the full
  mechanism) - `Graphs/TVMPlot3D.png`, a small rotated-square "mesh"
  glyph (a bilinear-subdivided diamond, blue-to-red gradient fill echoing
  `HeightToColor`'s own palette) compiled via `lazres uvmplot3d_icon.lrs
  "TVMPlot3D.png=TVMPlot3D"` into `uvmplot3d_icon.lrs`, pulled in via
  `{$I uvmplot3d_icon.lrs}` in `Register`. Also needed `LResources` added
  to this unit's `uses` clause.

### `backup/`

Contains earlier revisions of `newVM.pas`/`newVMComplex.pas` and an older
test project. Treat as historical reference only, not live code — the
current top-level `.pas` files are the ones actually built by `newVMtest.lpi`.

### `LMath/`

A third-party pure-Pascal numerical library (algorithms, integrals, line
algebra, math/stat, non-linear equations, optimisation, plotting, random
numbers, regression), vendored into the repo whole. None of `newVM.pas`/
`newVMSingle.pas`/`newVMComplex.pas`/`newVMComplexSingle.pas` actually
`uses` any `LMath` unit at build time - it's a reference source, not a
dependency: `PurePascalEigHqr2`/`PurePascalEigHqr2S` (see `newVMComplex.pas`/
`newVMComplexSingle.pas`'s own `EigDecompose`/`EigDecomposeS` sections
above) were ported from `LMath/ULineAlgebra/{ubalance,uelmhes,ueltran,uhqr2,
ubalbak}.pas` onto newVM's own 0-based `TVMobj`/`TVMobjZ` types and Double/
Single element types, not linked against directly - the precision-agnostic
`Float` type those units compile with (`{$IFDEF SINGLEREAL}`-selected,
resolved once per compiled program) can't otherwise coexist with newVM's
own four-way real/complex × double/single split, which needs both
precisions live in the same program at once (`newVMTests.pas` `uses` all
four `TVMobj*` units together). The rest of `LMath/` (FFT, statistics,
regression, plotting, etc) is unused - vendored for reference/future use,
not because anything in this repo currently calls into it.
