# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Free Pascal / Lazarus library (`newVM`) providing matrix/vector objects that
wrap Intel MKL (BLAS/LAPACK/VSL) and Intel IPP for linear algebra. It is
explicitly inspired by the Dew MtxVec library for FPC, but — unlike Dew —
does not distinguish matrix and vector types: a vector is just an (N,1) or
(1,N) matrix. There are four parallel "flavors" of the same object model for
real/complex × double/single precision (see Architecture below).

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
- `*` between two same-type `TVMobj*` is matrix multiplication; it just
  delegates to the existing `MatMult`/`MatMultS`/`MatMultZ`/`MatMultC`
  rather than duplicating the `cblas_?gemm` call.
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
  `TVMobjC` with `TVMobjS`, both operand orders) by promoting the real
  operand via `RealToComplex`/`RealToComplexS` and delegating to the
  same-type complex operator — these can only live in the complex units
  since only they `uses` the real sibling unit.

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
  `ippsMulC_64f`/`_I_L`, `ippsAddC_64f_I`, `ippsSubC_64f_I`,
  `ippsDivC_64f_I`/`_32f_I`, `ippsSqr_64f_I`, `ippsExp_64f_I`, `ippInit`,
  `ippMalloc`, `ippFree`) is split across three separate DLLs even on
  Windows (`ippcore.dll`/`ippvm.dll`/`ipps.dll`, mirroring the Linux
  `libippcore.so`/`libippvm.so`/`libipps.so` triplet), and which DLL
  actually exports a given symbol is not reliably documented and can vary
  by IPP version (several of these are declared in `ipps.h` but actually
  resolve from `ippvm.dll`). `LoadIPPFunctions` resolves each one at
  runtime by trying `ipps.dll`, then `ippvm.dll`, then `ippcore.dll` via
  `IPPProc`, asserting if none of the three export it.
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
`TVMobjZTests`, `TVMobjCTests` — each registered via `RegisterTest` in the
unit's `initialization` section. Coverage per type: construction and
dimension-validation asserts, `Element[r,c]` get/set (including
out-of-range and non-square addressing), `writeMatrix`, `fillRandom`
(exploits the hard-coded seed — see below), `Id`, `DataPtr` (real types),
`CopyObj*` independence, `MatMult*`, `LinearSolve*`, every operator
overload including the assertion paths, and the elementwise VML functions.
The two complex types additionally cover `RealToComplex*`/`GetRealPart*`/
`GetImagPart*`/`SplitComplex*`, `EigDecompose*` (verified via the defining
equation `A*v = lambda*v`, not hard-coded eigenvectors, since LAPACK
doesn't guarantee a particular sign/normalisation), and the mixed
real/complex operators.

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
`clock_gettime(CLOCK_MONOTONIC, ...)` on Unix. Previously used to time MKL
routine calls in the old `newVMtest.lpr` demo; not referenced by any
current project file now that `newVMtest.lpr` is an FPCUnit console
runner, but kept in the repo as a general-purpose utility.

### `backup/`

Contains earlier revisions of `newVM.pas`/`newVMComplex.pas` and an older
test project. Treat as historical reference only, not live code — the
current top-level `.pas` files are the ones actually built by `newVMtest.lpi`.
