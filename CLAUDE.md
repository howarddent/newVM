# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Free Pascal / Lazarus library (`newVM`) providing matrix/vector objects that
wrap Intel MKL (BLAS/LAPACK/VSL) and Intel IPP for linear algebra. It is
explicitly inspired by the Dew MtxVec library for FPC, but — unlike Dew —
does not distinguish matrix and vector types: a vector is just an (N,1) or
(1,N) matrix. There are four parallel "flavors" of the same object model for
real/complex × double/single precision (see Architecture below), plus a
fifth, non-duplicated companion unit (`newVMI.pas`) providing an integer
array/matrix type for index operations (pivot vectors, index lists) on the
other four.

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
  *any* of OpenBLAS/MKL/IPP (all three of which `newVM.pas`'s "core" linear
  algebra genuinely calls into - `cblas_*`, `LAPACKE_*`/`vd*`/`vsl*`, and
  `ipps*` respectively) is missing. FFTW absence does *not* set
  `PUREPASCAL` - DCT/DST/FFT have no plain-Pascal fallback (see below) and
  already degrade to a clear runtime assert on their own via
  `r2rTransform`'s `assert(Assigned(fftw_plan_r2r_1d), ...)` regardless of
  this define. The generated file uses `//` line comments throughout, never
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
- DCT/DST/FFT (`r2rTransform` and everything built on it) deliberately have
  **no** `PUREPASCAL` fallback - a correct pure-Pascal FFT is a
  substantially larger undertaking than the rest of this list, out of
  scope for this pass. They keep working exactly as before (FFTW is loaded
  independently of `PUREPASCAL`) and already assert clearly if FFTW itself
  isn't loaded.

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
  - `EigDecompose`/`EigDecomposeS` (`LAPACKE_dgeev`/`sgeev`) and
    `FFT_R2C`/`FFT_C2R`/`FFT`/`IFFT` (FFTW-backed) have no fallback, same
    rationale and same "already asserts cleanly if the library isn't
    loaded" behaviour as `newVM.pas`'s own DCT/DST.
- **Verified** the same way as `newVM.pas`: with `PUREPASCAL` forced on
  for all four units simultaneously, the full 256-test suite (`TVMobjTests`
  59, `TVMobjSTests` 59, `TVMobjZTests` 60 - including
  `TestEigDecomposeSatisfiesEigenEquation`, which still exercises the
  library-backed `EigDecompose` combined with a now-PUREPASCAL `MatMultZ`
  via the mixed real*complex `*` operator - `TVMobjCTests` 60, `TVMobjITests`
  18) passes with 0 errors/0 failures, and again passes unchanged back in
  the normal (all-libraries-found) state.

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

### External bindings

- `cblas.pas` — machine-generated (`h2pas`) BLAS declarations bound against
  OpenBLAS, providing `CBLAS_ORDER`, `CBLAS_TRANSPOSE`, etc. and base
  `cblas_*` function pointers/types.
- `OneAPI.pas` — hand-written bindings for LAPACKE (`lapacke_*`), Intel VML
  (`vmd*`), Intel IPP (`ipps*`), MKL memory management (`MKL_malloc` etc.),
  and MKL's VSL RNG (`vslNewStream`/`vdRngGaussian`/`vsRngGaussian`), plus the
  `TComplex16`/`TComplex8` record layouts (must stay bit-identical to
  `MKL_Complex16`/`MKL_Complex8` — two contiguous IEEE-754 floats — since
  several routines reinterpret a complex buffer as a flat real array via
  pointer casts, e.g. `fillRandom` and `RealToComplex`/`GetRealPart`).
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
`TVMobjZTests`, `TVMobjCTests`, `TVMobjITests` — each registered via
`RegisterTest` in the unit's `initialization` section. Coverage per
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

### `hirestimer.pas`

Platform-specific high-resolution timer (`THighResTimer`), using
`clock_gettime(CLOCK_MONOTONIC, ...)` on Unix, plus a `TProfiler`
convenience wrapper (`Profiler.Start`/`Profiler.Stop`, both global
singletons instantiated in the unit's `initialization` section). No
longer referenced by `newVMtest.lpr` (now an FPCUnit console runner that
doesn't time anything), but used by `demos/SpectralDiff` to time the
spectral-differentiation call, specifically so demo projects don't need
an external timing package (e.g. EpikTimer/`etpackage`) as a dependency.

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
