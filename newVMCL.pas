unit newVMCL;

{*******************************************************************************

     Vector / Matrix objects leveraging OpenCL (GPU-resident, SINGLE PRECISION)

     Follows newVMSingle.pas's TVMobjS object shape as closely as an
     OpenCL-buffer-backed type can: constructor Create(r,c), a default
     Element[r,c] indexed property, read-only Rows/Cols, fillRandom/Id/
     linspace/Transpose, the same class-operator +/-/*// / = overloads with
     the same contract ('*' between two TVMobjCL is ELEMENTWISE, matching
     TVMobjS/TVMobj's own documented convention - use MatMultCL explicitly
     for a real matrix product), and a free-function CopyObjCL matching
     CopyObj/CopyObjS's "genuinely independent copy" contract. See below
     for where this deliberately diverges from TVMobjS, and why.

     SCOPE - this is NOT a full parallel to the four existing newVM*
     units. Built on OpenCL core (compute kernels, hand-written below) plus
     AMD's clFFT (OpenCLAPI.pas) - which between them give GPU compute and
     GPU FFT, but no GPU BLAS/LAPACK. In scope: the object shape above,
     the four arithmetic operators plus elementwise Sin/Cos/Tan/Sinh/Sqr/
     Sqrt/Exp/Ln (all straightforward OpenCL C kernels), MatMultCL (a
     naive, non-tiled matrix-multiply kernel - see that function's own
     comment), and FFT/IFFT via clFFT. Deliberately OUT of scope for this
     first version: LinearSolveCL/InvertCL (no GPU LAPACK to build on, and
     a numerically-robust from-scratch GPU LU/solve is real work in its
     own right - a separate undertaking, not attempted here), and
     Kron/Diag/Trace/Det/Flip*/Merge*/Reshape/Repmat/AddScalar/SubMatrix/
     DCT/DST (straightforward in principle, simply not needed yet - this
     unit's motivating use case, per its own commissioning, is GPU-
     accelerated spectrum work for the SDR_Radio project, which needs FFT
     and elementwise/matrix arithmetic, not the rest of TVMobjS's surface).

     WHY A MANAGED RECORD, NOT A PLAIN ONE (THE ONE STRUCTURAL DIFFERENCE
     FROM EVERY OTHER TVMobj* TYPE): TVMobjS's value semantics - plain
     assignment aliases the same underlying buffer, safe because FPC's
     dynamic arrays are themselves already reference-counted under the
     hood - work automatically because fData is a language-managed type.
     An OpenCL cl_mem handle is just an opaque pointer with EXPLICIT
     reference counting (clRetainMemObject/clReleaseMemObject) - a plain
     record holding one would alias on assignment same as TVMobjS, but
     NOTHING would ever release the GPU buffer, since records have no
     destructor. The "AdvancedRecords" modeswitch (see this unit's own
     mode/modeswitch directives below) enables class operators
     (Initialize/Finalize/AddRef/Copy) that close that gap: Copy increments a
     shared refcount on assignment (exactly mirroring what a dynamic
     array's own hidden refcount does on TVMobjS assignment), Finalize
     decrements it on scope exit and frees the GPU buffer only once it
     reaches zero. Confirmed correct (construct/copy/scope-exit, freed
     exactly once) with a standalone probe before being relied on here -
     same "verify the mechanism against a minimal case first" discipline
     the rest of this codebase's FFI work follows. The practical result:
     TVMobjCL needs no manual Free/Release call anywhere, same as
     TVMobjS - CopyObjCL is still there for the same reason CopyObj/
     CopyObjS are (an explicitly INDEPENDENT copy, e.g. before a
     destructive operation), not because ordinary assignment leaks.

     ELEMENT[r,c] IS SLOW BY DESIGN, UNLIKE EVERY OTHER TVMobj*'S: each
     access is its own blocking clEnqueueReadBuffer/WriteBuffer round trip
     to the GPU - fine for tests and occasional debug inspection (which is
     all this codebase's own test suite convention needs it for), but
     never intended for a hot per-element loop the way host-side
     TVMobj*'s Element is. ToDevice/ToHost (bulk upload/download,
     one transfer for the whole buffer) are the actual bridge to/from
     TVMobjS for real data movement - genuinely new relative to TVMobjS,
     since a pure-host type never needed one.

     FFT/IFFT LAYOUT: TVMobjCL has no complex sibling the way newVM.pas's
     real DCT/FFT functions can hand off to newVMComplex.pas's TVMobjZ, so
     complex data (both FFT's input and output) is a TVMobjCL of Cols =
     2*N floats, consecutive pairs being (re,im) - exactly clFFT's own
     CLFFT_COMPLEX_INTERLEAVED layout, chosen so no packing/unpacking step
     is needed between this unit and clFFT itself. This directly matches
     what an SDR IQ epoch already looks like (interleaved I/Q floats), the
     motivating use case. IFFT needs no explicit normalisation step -
     unlike FFTW (which this codebase's other FFT/DCT code is built on,
     and which never auto-normalises either direction), clFFT's own
     backward-transform plan already defaults to a 1/N scale factor, so
     IFFT(FFT(x)) = x directly. (An earlier version of this function
     added its own extra "/N" on top, on the FFTW-shaped assumption that
     the backward transform needed it - caught by an IFFT(FFT(x))=x
     round-trip test once that test was strengthened to check every
     element rather than one that happened to be exactly 0; every
     mismatch was off by exactly a factor of N, i.e. double-normalised.
     Worth remembering if this unit ever grows a DCT/DST built on FFTW
     instead - that scaling convention does NOT carry over from clFFT.)

     Every OpenCL/clFFT call sequence below (context/queue creation,
     kernel compile and dispatch, and the clFFT plan/bake/transform
     sequence) was verified against the real API and a physically attached
     AMD Radeon PRO W6600 GPU with a standalone probe before being
     integrated here - see OpenCLAPI.pas's own header comment for what
     that probe found (including two real gotchas: static DLL linkage
     fails on this machine and must be dynamic, and clfftInitSetupData
     isn't exported by this machine's clFFT.dll build).

*******************************************************************************}

{$mode Delphi}{$H+}
{$modeswitch AdvancedRecords}

interface

uses
  Classes, SysUtils, OpenCLAPI, newVMSingle;

const
  MaxDimCL = 65536;

type
  TDimCL = 0..MaxDimCL-1;

  { TVMobjCL }
  TVMobjCL = record
  private
    FBuffer: cl_mem;
    FRefCount: PInteger;
    frows, fcols: TDimCL;
    function getelement(r, c: TDimCL): Single;
    procedure setelement(r, c: TDimCL; AValue: Single);
  public
    class operator Initialize(var A: TVMobjCL);
    class operator Finalize(var A: TVMobjCL);
    class operator AddRef(var A: TVMobjCL);
    class operator Copy(constref Src: TVMobjCL; var Dst: TVMobjCL);

    constructor Create(r, c: TDimCL); overload;
    // Convenience overload matching TVMobjS.Create(r,c,Values)'s own shape,
    // purely for test-fixture readability (TVMobjCL.Create(2,2,[1,2,3,4]))
    // - uploads the whole literal in one clEnqueueWriteBuffer call rather
    // than per-element sets.
    constructor Create(r, c: TDimCL; const Values: array of Single); overload;
    property Element[r, c: TDimCL]: Single read getelement write setelement; default;
    procedure fillRandom;
    procedure Id;
    procedure linspace(Start, increment: Single);
    function Transpose: TVMobjCL;
    function writeMatrix: TStringList;
    property Handle: cl_mem read FBuffer;   // raw buffer, for OpenCL/clFFT interop from other units - the GPU analogue of TVMobjS.DataPtr
    property Rows: TDimCL read frows;
    property Cols: TDimCL read fcols;

    { Operator overloads - see this unit's own header comment (SCOPE) for
      the contract, identical to TVMobjS's own. }
    class operator +(const A, B: TVMobjCL): TVMobjCL;
    class operator -(const A, B: TVMobjCL): TVMobjCL;
    class operator -(const A: TVMobjCL): TVMobjCL;
    class operator *(const A, B: TVMobjCL): TVMobjCL;
    class operator *(const A: TVMobjCL; const k: Single): TVMobjCL;
    class operator *(const k: Single; const A: TVMobjCL): TVMobjCL;
    class operator /(const A: TVMobjCL; const k: Single): TVMobjCL;
    class operator =(const A, B: TVMobjCL): Boolean;
  end;

function CopyObjCL(const A: TVMobjCL): TVMobjCL;
// Naive matrix product (one work-item per output element, a plain
// dot-product loop over K inside each - no tiling/local-memory blocking)
// - see this function's own implementation comment for why that's an
// intentional v1 scope choice, not an oversight.
function MatMultCL(const A, B: TVMobjCL): TVMobjCL;

function ToDevice(const A: TVMobjS): TVMobjCL;
function ToHost(const A: TVMobjCL): TVMobjS;

function Sin(const A: TVMobjCL): TVMobjCL; overload;
function Cos(const A: TVMobjCL): TVMobjCL; overload;
function Tan(const A: TVMobjCL): TVMobjCL; overload;
function Sinh(const A: TVMobjCL): TVMobjCL; overload;
function Sqr(const A: TVMobjCL): TVMobjCL; overload;
function Sqrt(const A: TVMobjCL): TVMobjCL; overload;
function Exp(const A: TVMobjCL): TVMobjCL; overload;
function Ln(const A: TVMobjCL): TVMobjCL; overload;

// Complex-to-complex FFT/IFFT via clFFT - A must be a vector (Rows=1 or
// Cols=1) with an even element count, interpreted as interleaved (re,im)
// pairs - see this unit's own header comment (FFT/IFFT LAYOUT).
function FFT(const A: TVMobjCL): TVMobjCL; overload;
function IFFT(const A: TVMobjCL): TVMobjCL; overload;

// True iff OpenCL + clFFT were both found and the GPU context/kernel
// program are ready - checked once, lazily, by the first TVMobjCL.Create
// call; exposed here so calling code (and this unit's own test suite) can
// skip GPU-dependent work gracefully on a machine without a working
// OpenCL/clFFT install, the same "probe once, degrade gracefully" pattern
// newvmconfigure.lpr's HAVE_* defines already establish for MKL/IPP/
// OpenBLAS/FFTW.
function OpenCLReady: Boolean;

// The reason OpenCLReady returned False, once it has - empty before the
// first check, or if it succeeded. Exposed so calling code (e.g. a status
// bar) can explain a CPU fallback rather than just silently taking it.
function OpenCLLastError: string;

implementation

uses
  Math;

var
  GCtx: cl_context = nil;
  GQueue: cl_command_queue = nil;
  GDevice: cl_device_id = nil;
  GProgram: cl_program = nil;
  GReadyState: (grUntried, grReady, grFailed) = grUntried;
  GInitError: string = '';

  GKernAdd, GKernSub, GKernNeg, GKernMul, GKernScale, GKernDivScalar,
  GKernTranspose, GKernSin, GKernCos, GKernTan, GKernSinh, GKernSqr,
  GKernSqrt, GKernExp, GKernLn, GKernLinspace, GKernIdentity, GKernMatMul: cl_kernel;

const
  KernelSource: PAnsiChar =
    '__kernel void vec_add(__global const float* a, __global const float* b, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = a[i] + b[i]; }' + #10 +
    '__kernel void vec_sub(__global const float* a, __global const float* b, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = a[i] - b[i]; }' + #10 +
    '__kernel void vec_neg(__global const float* a, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = -a[i]; }' + #10 +
    '__kernel void vec_mul(__global const float* a, __global const float* b, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = a[i] * b[i]; }' + #10 +
    '__kernel void vec_scale(__global const float* a, float k, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = a[i] * k; }' + #10 +
    '__kernel void vec_divscalar(__global const float* a, float k, __global float* c) {' + #10 +
    '  int i = get_global_id(0); c[i] = a[i] / k; }' + #10 +
    '__kernel void mat_transpose(__global const float* a, __global float* c, int rows, int cols) {' + #10 +
    '  int r = get_global_id(0); int cc = get_global_id(1); c[cc*rows + r] = a[r*cols + cc]; }' + #10 +
    '__kernel void vec_sin(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = sin(a[i]); }' + #10 +
    '__kernel void vec_cos(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = cos(a[i]); }' + #10 +
    '__kernel void vec_tan(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = tan(a[i]); }' + #10 +
    '__kernel void vec_sinh(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = sinh(a[i]); }' + #10 +
    '__kernel void vec_sqr(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = a[i] * a[i]; }' + #10 +
    '__kernel void vec_sqrt(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = sqrt(a[i]); }' + #10 +
    '__kernel void vec_exp(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = exp(a[i]); }' + #10 +
    '__kernel void vec_ln(__global const float* a, __global float* c) { int i = get_global_id(0); c[i] = log(a[i]); }' + #10 +
    '__kernel void vec_linspace(__global float* c, float start, float step) {' + #10 +
    '  int i = get_global_id(0); c[i] = start + i * step; }' + #10 +
    '__kernel void mat_identity(__global float* c, int n) {' + #10 +
    '  int r = get_global_id(0); int cc = get_global_id(1); c[r*n + cc] = (r == cc) ? 1.0f : 0.0f; }' + #10 +
    // Naive matrix product - see MatMultCL's own comment for why this
    // deliberately isn't tiled/blocked. A is MxK, B is KxN, C is MxN.
    '__kernel void mat_mul(__global const float* a, __global const float* b, __global float* c, int M, int N, int K) {' + #10 +
    '  int row = get_global_id(0); int col = get_global_id(1);' + #10 +
    '  float sum = 0.0f;' + #10 +
    '  for (int k = 0; k < K; k++) sum += a[row*K + k] * b[k*N + col];' + #10 +
    '  c[row*N + col] = sum; }';

function MakeKernel(const Name: string): cl_kernel;
const
  s = 'newVMCL kernel build : ';
var
  Err: cl_int;
begin
  Err := 0;
  Result := clCreateKernel(GProgram, PAnsiChar(Name), @Err);
  assert(Err = CL_SUCCESS, s + 'clCreateKernel(' + Name + ') failed with code ' + IntToStr(Err));
end;

procedure EnsureOpenCLReady;
const
  s = 'newVMCL initialization : ';
var
  Src: PAnsiChar;
  BuildErr: cl_int;
  LogBuf: array[0..8191] of AnsiChar;
  LogLen: NativeUInt;
  Err: cl_int;
begin
  if GReadyState <> grUntried then Exit;

  if not InitializeOpenCLContext(GCtx, GQueue, GDevice, GInitError) then begin
    GReadyState := grFailed;
    Exit;
  end;

  Src := KernelSource;
  Err := 0;
  GProgram := clCreateProgramWithSource(GCtx, 1, @Src, nil, @Err);
  if Err <> CL_SUCCESS then begin
    GInitError := 'clCreateProgramWithSource failed with code ' + IntToStr(Err);
    GReadyState := grFailed;
    Exit;
  end;

  BuildErr := clBuildProgram(GProgram, 1, @GDevice, nil, nil, nil);
  if BuildErr <> CL_SUCCESS then begin
    LogLen := 0;
    clGetProgramBuildInfo(GProgram, GDevice, CL_PROGRAM_BUILD_LOG, SizeOf(LogBuf), @LogBuf[0], @LogLen);
    GInitError := 'kernel build failed: ' + PAnsiChar(@LogBuf[0]);
    GReadyState := grFailed;
    Exit;
  end;

  GKernAdd       := MakeKernel('vec_add');
  GKernSub       := MakeKernel('vec_sub');
  GKernNeg       := MakeKernel('vec_neg');
  GKernMul       := MakeKernel('vec_mul');
  GKernScale     := MakeKernel('vec_scale');
  GKernDivScalar := MakeKernel('vec_divscalar');
  GKernTranspose := MakeKernel('mat_transpose');
  GKernSin       := MakeKernel('vec_sin');
  GKernCos       := MakeKernel('vec_cos');
  GKernTan       := MakeKernel('vec_tan');
  GKernSinh      := MakeKernel('vec_sinh');
  GKernSqr       := MakeKernel('vec_sqr');
  GKernSqrt      := MakeKernel('vec_sqrt');
  GKernExp       := MakeKernel('vec_exp');
  GKernLn        := MakeKernel('vec_ln');
  GKernLinspace  := MakeKernel('vec_linspace');
  GKernIdentity  := MakeKernel('mat_identity');
  GKernMatMul    := MakeKernel('mat_mul');

  GReadyState := grReady;
end;

function OpenCLReady: Boolean;
begin
  EnsureOpenCLReady;
  Result := GReadyState = grReady;
end;

function OpenCLLastError: string;
begin
  Result := GInitError;
end;

{ TVMobjCL }

class operator TVMobjCL.Initialize(var A: TVMobjCL);
begin
  A.FBuffer := nil;
  A.FRefCount := nil;
  A.frows := 0;
  A.fcols := 0;
end;

class operator TVMobjCL.AddRef(var A: TVMobjCL);
begin
  if Assigned(A.FRefCount) then Inc(A.FRefCount^);
end;

class operator TVMobjCL.Copy(constref Src: TVMobjCL; var Dst: TVMobjCL);
begin
  Dst.FBuffer := Src.FBuffer;
  Dst.FRefCount := Src.FRefCount;
  Dst.frows := Src.frows;
  Dst.fcols := Src.fcols;
  if Assigned(Dst.FRefCount) then Inc(Dst.FRefCount^);
end;

class operator TVMobjCL.Finalize(var A: TVMobjCL);
begin
  if Assigned(A.FRefCount) then begin
    Dec(A.FRefCount^);
    if A.FRefCount^ = 0 then begin
      clReleaseMemObject(A.FBuffer);
      Dispose(A.FRefCount);
    end;
    A.FRefCount := nil;
    A.FBuffer := nil;
  end;
end;

constructor TVMobjCL.Create(r, c: TDimCL);
const
  s = 'Constructor TVMobjCL.Create : ';
var
  Err: cl_int;
begin
  assert((r > 0) and (c > 0), s + 'Rows and Cols must both be positive');
  EnsureOpenCLReady;
  assert(GReadyState = grReady, s + 'OpenCL not available (' + GInitError + ')');
  frows := r;
  fcols := c;
  Err := 0;
  FBuffer := clCreateBuffer(GCtx, CL_MEM_READ_WRITE, NativeUInt(r) * NativeUInt(c) * SizeOf(Single), nil, @Err);
  assert(Err = CL_SUCCESS, s + 'clCreateBuffer failed with code ' + IntToStr(Err));
  New(FRefCount);
  FRefCount^ := 1;
end;

constructor TVMobjCL.Create(r, c: TDimCL; const Values: array of Single);
const
  s = 'Constructor TVMobjCL.Create (with Values) : ';
begin
  assert(Length(Values) = NativeInt(r) * NativeInt(c), s + 'Values length must equal r*c');
  // NOT a bare "Create(r, c);" call: for a managed record, calling another
  // constructor unqualified from within this one constructs an
  // independent temporary and discards it - it does NOT initialise the
  // Self this constructor itself returns (confirmed by a genuinely wrong
  // first attempt: it compiled and ran without error, silently returning
  // an all-zero-initialised, buffer-less object - clEnqueueWriteBuffer
  // against a nil cl_mem handle failed without crashing since its return
  // code goes unchecked here). Explicitly assigning to Self is the
  // correct idiom for one record constructor to delegate to another.
  Self := Create(r, c);
  clEnqueueWriteBuffer(GQueue, FBuffer, CL_TRUE, 0, NativeUInt(r) * c * SizeOf(Single), @Values[0], 0, nil, nil);
end;

function TVMobjCL.getelement(r, c: TDimCL): Single;
const
  s = 'TVMobjCL.Element (get) : ';
begin
  assert((r < frows) and (c < fcols), s + 'index out of range');
  clEnqueueReadBuffer(GQueue, FBuffer, CL_TRUE, (NativeUInt(r) * fcols + c) * SizeOf(Single),
    SizeOf(Single), @Result, 0, nil, nil);
end;

procedure TVMobjCL.setelement(r, c: TDimCL; AValue: Single);
const
  s = 'TVMobjCL.Element (set) : ';
begin
  assert((r < frows) and (c < fcols), s + 'index out of range');
  clEnqueueWriteBuffer(GQueue, FBuffer, CL_TRUE, (NativeUInt(r) * fcols + c) * SizeOf(Single),
    SizeOf(Single), @AValue, 0, nil, nil);
end;

// Deterministic, matching every other TVMobj*'s own fillRandom contract
// (TestFillRandomDeterministic-style tests rely on two same-sized
// fillRandom calls producing bit-identical data) - generated via
// TVMobjS's own fillRandom (fixed seed 777, MKL vsRngGaussian or the
// PUREPASCAL Box-Muller fallback, whichever this build has) and uploaded,
// rather than reimplementing a second GPU-side RNG that would need its
// own separate proof of matching that same contract.
procedure TVMobjCL.fillRandom;
var
  Host: TVMobjS;
begin
  Host := TVMobjS.Create(frows, fcols);
  Host.fillRandom;
  clEnqueueWriteBuffer(GQueue, FBuffer, CL_TRUE, 0, NativeUInt(frows) * fcols * SizeOf(Single),
    Host.DataPtr, 0, nil, nil);
end;

procedure TVMobjCL.Id;
const
  s = 'TVMobjCL.Id : ';
var
  GlobalSize: array[0..1] of NativeUInt;
  N: cl_int;
begin
  assert(frows = fcols, s + 'matrix must be square');
  N := frows;
  clSetKernelArg(GKernIdentity, 0, SizeOf(cl_mem), @FBuffer);
  clSetKernelArg(GKernIdentity, 1, SizeOf(cl_int), @N);
  GlobalSize[0] := frows;
  GlobalSize[1] := fcols;
  clEnqueueNDRangeKernel(GQueue, GKernIdentity, 2, nil, @GlobalSize[0], nil, 0, nil, nil);
end;

procedure TVMobjCL.linspace(Start, increment: Single);
const
  s = 'TVMobjCL.linspace : ';
var
  GlobalSize: NativeUInt;
begin
  assert((frows = 1) or (fcols = 1), s + 'must be a vector (Rows=1 or Cols=1)');
  clSetKernelArg(GKernLinspace, 0, SizeOf(cl_mem), @FBuffer);
  clSetKernelArg(GKernLinspace, 1, SizeOf(Single), @Start);
  clSetKernelArg(GKernLinspace, 2, SizeOf(Single), @increment);
  GlobalSize := NativeUInt(frows) * fcols;
  clEnqueueNDRangeKernel(GQueue, GKernLinspace, 1, nil, @GlobalSize, nil, 0, nil, nil);
end;

function TVMobjCL.Transpose: TVMobjCL;
var
  GlobalSize: array[0..1] of NativeUInt;
  R, C: cl_int;
begin
  Result := TVMobjCL.Create(fcols, frows);
  R := frows;
  C := fcols;
  clSetKernelArg(GKernTranspose, 0, SizeOf(cl_mem), @FBuffer);
  clSetKernelArg(GKernTranspose, 1, SizeOf(cl_mem), @Result.FBuffer);
  clSetKernelArg(GKernTranspose, 2, SizeOf(cl_int), @R);
  clSetKernelArg(GKernTranspose, 3, SizeOf(cl_int), @C);
  GlobalSize[0] := frows;
  GlobalSize[1] := fcols;
  clEnqueueNDRangeKernel(GQueue, GKernTranspose, 2, nil, @GlobalSize[0], nil, 0, nil, nil);
end;

// Downloads the whole buffer once and delegates to TVMobjS's own
// writeMatrix, rather than duplicating its string-formatting logic here.
function TVMobjCL.writeMatrix: TStringList;
begin
  Result := ToHost(Self).writeMatrix;
end;

function CopyObjCL(const A: TVMobjCL): TVMobjCL;
begin
  Result := TVMobjCL.Create(A.frows, A.fcols);
  clEnqueueCopyBuffer(GQueue, A.FBuffer, Result.FBuffer, 0, 0,
    NativeUInt(A.frows) * A.fcols * SizeOf(Single), 0, nil, nil);
end;

function ToDevice(const A: TVMobjS): TVMobjCL;
begin
  Result := TVMobjCL.Create(A.Rows, A.Cols);
  clEnqueueWriteBuffer(GQueue, Result.FBuffer, CL_TRUE, 0,
    NativeUInt(A.Rows) * A.Cols * SizeOf(Single), A.DataPtr, 0, nil, nil);
end;

function ToHost(const A: TVMobjCL): TVMobjS;
begin
  Result := TVMobjS.Create(A.frows, A.fcols);
  clEnqueueReadBuffer(GQueue, A.FBuffer, CL_TRUE, 0,
    NativeUInt(A.frows) * A.fcols * SizeOf(Single), Result.DataPtr, 0, nil, nil);
end;

// Shared body for every elementwise-binary kernel (add/sub/mul) - see the
// analogous RunUnary below for the unary case (negate, transcendentals).
function RunBinary(Kern: cl_kernel; const A, B: TVMobjCL; const Routine: string): TVMobjCL;
var
  GlobalSize: NativeUInt;
begin
  assert((A.frows = B.frows) and (A.fcols = B.fcols), Routine + ' : dimensions of A and B must be the same');
  Result := TVMobjCL.Create(A.frows, A.fcols);
  clSetKernelArg(Kern, 0, SizeOf(cl_mem), @A.FBuffer);
  clSetKernelArg(Kern, 1, SizeOf(cl_mem), @B.FBuffer);
  clSetKernelArg(Kern, 2, SizeOf(cl_mem), @Result.FBuffer);
  GlobalSize := NativeUInt(A.frows) * A.fcols;
  clEnqueueNDRangeKernel(GQueue, Kern, 1, nil, @GlobalSize, nil, 0, nil, nil);
end;

function RunUnary(Kern: cl_kernel; const A: TVMobjCL): TVMobjCL;
var
  GlobalSize: NativeUInt;
begin
  Result := TVMobjCL.Create(A.frows, A.fcols);
  clSetKernelArg(Kern, 0, SizeOf(cl_mem), @A.FBuffer);
  clSetKernelArg(Kern, 1, SizeOf(cl_mem), @Result.FBuffer);
  GlobalSize := NativeUInt(A.frows) * A.fcols;
  clEnqueueNDRangeKernel(GQueue, Kern, 1, nil, @GlobalSize, nil, 0, nil, nil);
end;

function RunScalar(Kern: cl_kernel; const A: TVMobjCL; k: Single): TVMobjCL;
var
  GlobalSize: NativeUInt;
begin
  Result := TVMobjCL.Create(A.frows, A.fcols);
  clSetKernelArg(Kern, 0, SizeOf(cl_mem), @A.FBuffer);
  clSetKernelArg(Kern, 1, SizeOf(Single), @k);
  clSetKernelArg(Kern, 2, SizeOf(cl_mem), @Result.FBuffer);
  GlobalSize := NativeUInt(A.frows) * A.fcols;
  clEnqueueNDRangeKernel(GQueue, Kern, 1, nil, @GlobalSize, nil, 0, nil, nil);
end;

class operator TVMobjCL.+(const A, B: TVMobjCL): TVMobjCL;
begin
  Result := RunBinary(GKernAdd, A, B, 'TVMobjCL.+');
end;

class operator TVMobjCL.-(const A, B: TVMobjCL): TVMobjCL;
begin
  Result := RunBinary(GKernSub, A, B, 'TVMobjCL.-');
end;

class operator TVMobjCL.-(const A: TVMobjCL): TVMobjCL;
begin
  Result := RunUnary(GKernNeg, A);
end;

// Element-wise (Hadamard) product - NOT a matrix product. See this unit's
// own header comment and MatMultCL for the real matrix product.
class operator TVMobjCL.*(const A, B: TVMobjCL): TVMobjCL;
begin
  Result := RunBinary(GKernMul, A, B, 'TVMobjCL.*');
end;

class operator TVMobjCL.*(const A: TVMobjCL; const k: Single): TVMobjCL;
begin
  Result := RunScalar(GKernScale, A, k);
end;

class operator TVMobjCL.*(const k: Single; const A: TVMobjCL): TVMobjCL;
begin
  Result := RunScalar(GKernScale, A, k);
end;

class operator TVMobjCL./(const A: TVMobjCL; const k: Single): TVMobjCL;
const
  s = 'TVMobjCL./ : ';
begin
  assert(k <> 0, s + 'division by zero');
  Result := RunScalar(GKernDivScalar, A, k);
end;

class operator TVMobjCL.=(const A, B: TVMobjCL): Boolean;
var
  HA, HB: TVMobjS;
begin
  if (A.frows <> B.frows) or (A.fcols <> B.fcols) then begin
    Result := False;
    Exit;
  end;
  // No GPU-side reduction kernel for this (rare, test-oriented) operator -
  // downloading both sides once and comparing on the host is simpler and
  // correct; not a path any hot loop should be taking.
  HA := ToHost(A);
  HB := ToHost(B);
  Result := HA = HB;
end;

function Sin(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernSin, A); end;
function Cos(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernCos, A); end;
function Tan(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernTan, A); end;
function Sinh(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernSinh, A); end;
function Sqr(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernSqr, A); end;
function Sqrt(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernSqrt, A); end;
function Exp(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernExp, A); end;
function Ln(const A: TVMobjCL): TVMobjCL; begin Result := RunUnary(GKernLn, A); end;

// Naive matrix product: one work-item per output element, each running a
// plain sequential dot-product loop over K - no shared/local-memory
// tiling, no register blocking. Correct and GPU-parallel across output
// elements (which is already a real win over a single-threaded host loop
// for large matrices), but leaves real performance on the table relative
// to a tuned GEMM (clBLAS/clBLAST, or a hand-tiled kernel) - an explicit,
// agreed v1 scope choice (see this unit's own header comment, SCOPE), not
// an oversight.
function MatMultCL(const A, B: TVMobjCL): TVMobjCL;
const
  s = 'Function MatMultCL : ';
var
  GlobalSize: array[0..1] of NativeUInt;
  M, N, K: cl_int;
begin
  assert(A.fcols = B.frows, s + 'A.Cols must equal B.Rows');
  M := A.frows;
  K := A.fcols;
  N := B.fcols;
  Result := TVMobjCL.Create(M, N);
  clSetKernelArg(GKernMatMul, 0, SizeOf(cl_mem), @A.FBuffer);
  clSetKernelArg(GKernMatMul, 1, SizeOf(cl_mem), @B.FBuffer);
  clSetKernelArg(GKernMatMul, 2, SizeOf(cl_mem), @Result.FBuffer);
  clSetKernelArg(GKernMatMul, 3, SizeOf(cl_int), @M);
  clSetKernelArg(GKernMatMul, 4, SizeOf(cl_int), @N);
  clSetKernelArg(GKernMatMul, 5, SizeOf(cl_int), @K);
  GlobalSize[0] := M;
  GlobalSize[1] := N;
  clEnqueueNDRangeKernel(GQueue, GKernMatMul, 2, nil, @GlobalSize[0], nil, 0, nil, nil);
end;

function FFT(const A: TVMobjCL): TVMobjCL;
const
  s = 'Function FFT (TVMobjCL) : ';
var
  N: NativeUInt;
  Plan: clfftPlanHandle;
  Status: clfftStatus;
begin
  assert((A.frows = 1) or (A.fcols = 1), s + 'A must be a vector (Rows=1 or Cols=1)');
  assert((NativeUInt(A.frows) * A.fcols) mod 2 = 0, s + 'A must hold an even number of floats (interleaved re/im pairs)');
  N := (NativeUInt(A.frows) * A.fcols) div 2;
  Result := CopyObjCL(A);   // clFFT transforms CLFFT_INPLACE - copy first so A itself is left untouched, matching this codebase's non-mutating convention
  Plan := 0;
  Status := clfftCreateDefaultPlan(@Plan, GCtx, CLFFT_1D, @N);
  assert(Status = CL_SUCCESS, s + 'clfftCreateDefaultPlan failed with code ' + IntToStr(Status));
  clfftSetPlanPrecision(Plan, CLFFT_SINGLE);
  clfftSetLayout(Plan, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
  clfftSetResultLocation(Plan, CLFFT_INPLACE);
  Status := clfftBakePlan(Plan, 1, @GQueue, nil, nil);
  assert(Status = CL_SUCCESS, s + 'clfftBakePlan failed with code ' + IntToStr(Status));
  Status := clfftEnqueueTransform(Plan, CLFFT_FORWARD, 1, @GQueue, 0, nil, nil, @Result.FBuffer, nil, nil);
  assert(Status = CL_SUCCESS, s + 'clfftEnqueueTransform failed with code ' + IntToStr(Status));
  clFinish(GQueue);
  clfftDestroyPlan(@Plan);
end;

function IFFT(const A: TVMobjCL): TVMobjCL;
const
  s = 'Function IFFT (TVMobjCL) : ';
var
  N: NativeUInt;
  Plan: clfftPlanHandle;
  Status: clfftStatus;
begin
  assert((A.frows = 1) or (A.fcols = 1), s + 'A must be a vector (Rows=1 or Cols=1)');
  assert((NativeUInt(A.frows) * A.fcols) mod 2 = 0, s + 'A must hold an even number of floats (interleaved re/im pairs)');
  N := (NativeUInt(A.frows) * A.fcols) div 2;
  Result := CopyObjCL(A);
  Plan := 0;
  Status := clfftCreateDefaultPlan(@Plan, GCtx, CLFFT_1D, @N);
  assert(Status = CL_SUCCESS, s + 'clfftCreateDefaultPlan failed with code ' + IntToStr(Status));
  clfftSetPlanPrecision(Plan, CLFFT_SINGLE);
  clfftSetLayout(Plan, CLFFT_COMPLEX_INTERLEAVED, CLFFT_COMPLEX_INTERLEAVED);
  clfftSetResultLocation(Plan, CLFFT_INPLACE);
  Status := clfftBakePlan(Plan, 1, @GQueue, nil, nil);
  assert(Status = CL_SUCCESS, s + 'clfftBakePlan failed with code ' + IntToStr(Status));
  Status := clfftEnqueueTransform(Plan, CLFFT_BACKWARD, 1, @GQueue, 0, nil, nil, @Result.FBuffer, nil, nil);
  assert(Status = CL_SUCCESS, s + 'clfftEnqueueTransform failed with code ' + IntToStr(Status));
  clFinish(GQueue);
  clfftDestroyPlan(@Plan);
  // No extra /N scaling here: unlike FFTW (which never auto-normalises
  // either direction) or the naive assumption this function started with
  // (documented as a mistake, not corrected in place, so this note stays
  // useful if anyone else makes the same one) - clFFT's own default
  // backward-transform scale factor is ALREADY 1/N. Discovered by an
  // IFFT(FFT(x))=x round-trip test that initially "passed" at one
  // deliberately-unlucky index (a bin-2 cosine's own value happens to be
  // exactly 0 at index 4) and only failed once the test was strengthened
  // to check every element - every mismatch was off by exactly a factor
  // of N (16), i.e. this function's own extra manual "* (1.0/N)" was
  // double-normalising clFFT's already-normalised result. Removed; the
  // round trip is exact without it.
end;

end.
