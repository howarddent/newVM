unit newVMMetal;

{*******************************************************************************

     Vector / Matrix objects leveraging Metal (GPU-resident, SINGLE PRECISION)

     The Metal analogue of newVMCL.pas's TVMobjCL (OpenCL+clFFT) - same
     object shape, same scope, same non-mutating/managed-record contract -
     built on Apple's own Metal (compute) and MetalPerformanceShadersGraph
     (FFT) APIs via MetalAPI.pas instead of OpenCL+clFFT via OpenCLAPI.pas.
     newVMCL.pas itself is untouched; this is a new, parallel unit, added
     because OpenCL is deprecated on Apple platforms and was never found on
     this Darwin/AArch64 dev machine (newvmconfigure.lpr's own HAVE_OPENCL
     probe is deliberately Windows-only), whereas Metal is this machine's
     real, always-present GPU API. See MetalAPI.pas's own header comment for
     the lower-level binding details (Objective-C interop, the FPU-exception
     driver crash and its fix, MPSGraph FFT layout/scaling) this unit builds
     on top of.

     Follows TVMobjS's/TVMobjCL's object shape exactly: constructor
     Create(r,c), a default Element[r,c] indexed property, read-only
     Rows/Cols, fillRandom/Id/linspace/Transpose, the same class-operator
     +/-/*// / = overloads with the same contract ('*' between two TVMobjMTL
     is ELEMENTWISE - use MatMultMTL explicitly for a real matrix product,
     exactly as TVMobjCL/TVMobjS/TVMobj/etc already document), and a
     free-function CopyObjMTL matching CopyObj/CopyObjS/CopyObjCL's
     "genuinely independent copy" contract.

     SCOPE - same as TVMobjCL: object shape above, the four arithmetic
     operators plus elementwise Sin/Cos/Tan/Sinh/Sqr/Sqrt/Exp/Ln, MatMultMTL
     (a naive, non-tiled matrix-multiply kernel, same v1 scope choice
     TVMobjCL's own MatMultCL makes), and FFT/IFFT via MPSGraph. Deliberately
     out of scope, same reasons as TVMobjCL: LinearSolveMTL/InvertMTL (no
     GPU LAPACK to build on here either) and
     Kron/Diag/Trace/Det/Flip*/Merge*/Reshape/Repmat/AddScalar/SubMatrix/
     DCT/DST (not needed by this unit's own motivating use case, the same
     SDR_Radio GPU spectrum pipeline TVMobjCL was built for).

     NAMING VS TVMobjCL: most free functions reuse TVMobjCL's own names as
     plain `overload`s (Sin/Cos/Tan/Sinh/Sqr/Sqrt/Exp/Ln/FFT/IFFT/ToHost all
     already take a TVMobjCL- or TVMobjMTL-typed argument respectively, so
     Pascal's overload resolution disambiguates by argument type with no
     clash - the same reason Sin/Cos/etc already coexist across all five
     other TVMobj* families). MatMultCL/CopyObjCL's own suffix convention
     carries over (MatMultMTL/CopyObjMTL). The one genuine collision:
     ToDevice(const A: TVMobjS): TVMobjCL and a same-shaped
     TVMobjS-argument function returning TVMobjMTL differ only in RETURN
     type, which Pascal cannot overload on - so this unit's upload function
     is named ToDeviceMTL, not ToDevice.

     WHY A MANAGED RECORD (THE ONE STRUCTURAL DIFFERENCE FROM EVERY
     NON-GPU TVMobj* TYPE, SAME REASON AS TVMobjCL): an mtl_buffer is just an
     opaque pointer to an Objective-C object needing EXPLICIT reference
     counting under FPC's manual (non-ARC) objc bridging - see MetalAPI.pas's
     own header comment. A plain record holding one would alias on ':='
     assignment same as TVMobjS, but nothing would ever release the GPU
     buffer, since plain records have no destructor. This unit's
     Initialize/Finalize/AddRef/Copy class operators are a direct copy of
     TVMobjCL's own (down to the exact same "release Dst's OLD reference
     before overwriting it, guarded against self-assignment" fix TVMobjCL's
     own header comment documents finding via a 20,000-iteration stress
     test) - only the release call itself changed, from
     clReleaseMemObject to MetalAPI.MTLReleaseBuffer. Like TVMobjCL, this
     Pascal-side FRefCount is a single-level scheme layered over a single
     Metal-level ownership of the buffer (acquired once at Create, released
     once when FRefCount hits zero) - never a second, Metal-level retain
     call, exactly mirroring how TVMobjCL never calls a matching
     clRetainMemObject either.

     ELEMENT[r,c], fillRandom, ToDeviceMTL/ToHost - FASTER THAN TVMobjCL'S
     OWN, NOT JUST A MECHANICAL PORT: Apple Silicon's unified memory means
     MetalAPI.MTLBufferContents is a raw CPU-visible pointer directly into
     the same memory the GPU reads/writes, so these are plain Move/pointer
     operations - not the blocking clEnqueueReadBuffer/WriteBuffer round
     trips TVMobjCL's own Element/fillRandom/ToDevice/ToHost need. Unlike
     TVMobjCL's own header comment (which specifically calls out
     Element[r,c] as "slow by design"), that caveat does NOT apply here.

     FFT/IFFT - ALSO SIMPLER THAN TVMobjCL'S OWN: clFFT only supports an
     in-place transform (CLFFT_INPLACE), so TVMobjCL's FFT/IFFT must
     CopyObjCL first, then transform the copy in place. MPSGraph naturally
     supports separate input/output tensors, so MetalAPI.MTLFFT/MTLIFFT take
     Src/Dst buffers directly - FFT/IFFT below just allocate a fresh Result
     and dispatch straight into it, no extra copy step. Layout (interleaved
     re/im pairs, Cols=2*N) and scaling (forward: unscaled; inverse:
     automatic 1/N via MPSGraphFFTScalingModeSize) are unchanged from
     TVMobjCL's own documented contract - confirmed identical by a
     standalone probe (16-point known-value FFT and a full IFFT(FFT(x))=x
     round trip) before this unit was written; see MetalAPI.pas's header
     comment for the full story.

*******************************************************************************}

{$mode Delphi}{$H+}
{$modeswitch AdvancedRecords}

interface

uses
  Classes, SysUtils, MetalAPI, newVMSingle;

const
  MaxDimMTL = 65536;

type
  TDimMTL = 0..MaxDimMTL-1;

  { TVMobjMTL }
  TVMobjMTL = record
  private
    FBuffer: mtl_buffer;
    FRefCount: PInteger;
    frows, fcols: TDimMTL;
    function getelement(r, c: TDimMTL): Single;
    procedure setelement(r, c: TDimMTL; AValue: Single);
  public
    class operator Initialize(var A: TVMobjMTL);
    class operator Finalize(var A: TVMobjMTL);
    class operator AddRef(var A: TVMobjMTL);
    class operator Copy(constref Src: TVMobjMTL; var Dst: TVMobjMTL);

    constructor Create(r, c: TDimMTL); overload;
    constructor Create(r, c: TDimMTL; const Values: array of Single); overload;
    property Element[r, c: TDimMTL]: Single read getelement write setelement; default;
    procedure fillRandom;
    procedure Id;
    procedure linspace(Start, increment: Single);
    function Transpose: TVMobjMTL;
    function writeMatrix: TStringList;
    property Handle: mtl_buffer read FBuffer;
    property Rows: TDimMTL read frows;
    property Cols: TDimMTL read fcols;

    class operator +(const A, B: TVMobjMTL): TVMobjMTL;
    class operator -(const A, B: TVMobjMTL): TVMobjMTL;
    class operator -(const A: TVMobjMTL): TVMobjMTL;
    class operator *(const A, B: TVMobjMTL): TVMobjMTL;
    class operator *(const A: TVMobjMTL; const k: Single): TVMobjMTL;
    class operator *(const k: Single; const A: TVMobjMTL): TVMobjMTL;
    class operator /(const A: TVMobjMTL; const k: Single): TVMobjMTL;
    class operator =(const A, B: TVMobjMTL): Boolean;
  end;

function CopyObjMTL(const A: TVMobjMTL): TVMobjMTL;
// Naive matrix product, same v1 scope choice as MatMultCL - see that
// function's own comment in newVMCL.pas.
function MatMultMTL(const A, B: TVMobjMTL): TVMobjMTL;

function ToDeviceMTL(const A: TVMobjS): TVMobjMTL;
function ToHost(const A: TVMobjMTL): TVMobjS; overload;

function Sin(const A: TVMobjMTL): TVMobjMTL; overload;
function Cos(const A: TVMobjMTL): TVMobjMTL; overload;
function Tan(const A: TVMobjMTL): TVMobjMTL; overload;
function Sinh(const A: TVMobjMTL): TVMobjMTL; overload;
function Sqr(const A: TVMobjMTL): TVMobjMTL; overload;
function Sqrt(const A: TVMobjMTL): TVMobjMTL; overload;
function Exp(const A: TVMobjMTL): TVMobjMTL; overload;
function Ln(const A: TVMobjMTL): TVMobjMTL; overload;

// Complex-to-complex FFT/IFFT via MPSGraph - A must be a vector (Rows=1 or
// Cols=1) with an even element count, interpreted as interleaved (re,im)
// pairs - see this unit's own header comment (FFT/IFFT).
function FFT(const A: TVMobjMTL): TVMobjMTL; overload;
function IFFT(const A: TVMobjMTL): TVMobjMTL; overload;

// True iff Metal + MetalPerformanceShadersGraph are both ready - checked
// once, lazily, by the first TVMobjMTL.Create call; mirrors TVMobjCL's own
// OpenCLReady/OpenCLLastError contract exactly, so callers with a
// GPU-optional fallback (e.g. uVMPlotSDRSpectrum.pas) can use whichever
// backend actually works on the machine they're running on.
function MetalReady: Boolean;
function MetalLastError: string;

implementation

uses
  Math;

function MetalReady: Boolean;
var
  ErrMsg: string;
begin
  Result := InitializeMetalContext(ErrMsg);
end;

function MetalLastError: string;
begin
  Result := MetalContextLastError;
end;

{ TVMobjMTL }

class operator TVMobjMTL.Initialize(var A: TVMobjMTL);
begin
  A.FBuffer := nil;
  A.FRefCount := nil;
  A.frows := 0;
  A.fcols := 0;
end;

class operator TVMobjMTL.AddRef(var A: TVMobjMTL);
begin
  if Assigned(A.FRefCount) then Inc(A.FRefCount^);
end;

class operator TVMobjMTL.Copy(constref Src: TVMobjMTL; var Dst: TVMobjMTL);
begin
  // See this unit's own header comment - release Dst's OLD reference
  // before overwriting it, guarded against self-assignment (the exact fix
  // TVMobjCL's own header comment documents needing, for the exact same
  // reason: a loop-reassigned variable would otherwise leak its previous
  // buffer on every iteration, since nothing would ever decrement its
  // refcount once Dst stopped pointing at it).
  if Assigned(Dst.FRefCount) and (Dst.FRefCount <> Src.FRefCount) then begin
    Dec(Dst.FRefCount^);
    if Dst.FRefCount^ = 0 then begin
      MTLReleaseBuffer(Dst.FBuffer);
      Dispose(Dst.FRefCount);
    end;
  end;

  Dst.FBuffer := Src.FBuffer;
  Dst.FRefCount := Src.FRefCount;
  Dst.frows := Src.frows;
  Dst.fcols := Src.fcols;
  if Assigned(Dst.FRefCount) then Inc(Dst.FRefCount^);
end;

class operator TVMobjMTL.Finalize(var A: TVMobjMTL);
begin
  if Assigned(A.FRefCount) then begin
    Dec(A.FRefCount^);
    if A.FRefCount^ = 0 then begin
      MTLReleaseBuffer(A.FBuffer);
      Dispose(A.FRefCount);
    end;
    A.FRefCount := nil;
    A.FBuffer := nil;
  end;
end;

constructor TVMobjMTL.Create(r, c: TDimMTL);
const
  s = 'Constructor TVMobjMTL.Create : ';
var
  ErrMsg: string;
begin
  assert((r > 0) and (c > 0), s + 'Rows and Cols must both be positive');
  assert(InitializeMetalContext(ErrMsg), s + 'Metal not available (' + ErrMsg + ')');
  frows := r;
  fcols := c;
  FBuffer := MTLNewBuffer(NativeUInt(r) * NativeUInt(c));
  New(FRefCount);
  FRefCount^ := 1;
end;

constructor TVMobjMTL.Create(r, c: TDimMTL; const Values: array of Single);
const
  s = 'Constructor TVMobjMTL.Create (with Values) : ';
begin
  assert(Length(Values) = NativeInt(r) * NativeInt(c), s + 'Values length must equal r*c');
  // See newVMCL.pas's own identical comment: a bare "Create(r, c);" here
  // would construct and discard an independent temporary, not initialise
  // the Self this constructor itself returns - explicit assignment to Self
  // is the correct delegation idiom for a managed record's constructor.
  Self := Create(r, c);
  Move(Values[0], MTLBufferContents(FBuffer)^, NativeUInt(r) * c * SizeOf(Single));
end;

function TVMobjMTL.getelement(r, c: TDimMTL): Single;
const
  s = 'TVMobjMTL.Element (get) : ';
begin
  assert((r < frows) and (c < fcols), s + 'index out of range');
  Result := MTLBufferContents(FBuffer)[NativeUInt(r) * fcols + c];
end;

procedure TVMobjMTL.setelement(r, c: TDimMTL; AValue: Single);
const
  s = 'TVMobjMTL.Element (set) : ';
begin
  assert((r < frows) and (c < fcols), s + 'index out of range');
  MTLBufferContents(FBuffer)[NativeUInt(r) * fcols + c] := AValue;
end;

// Same deterministic-seed contract as every other TVMobj*'s fillRandom -
// see TVMobjCL's own comment for why generating via TVMobjS.fillRandom and
// uploading is preferred over a second, separately-proven GPU-side RNG.
procedure TVMobjMTL.fillRandom;
var
  Host: TVMobjS;
begin
  Host := TVMobjS.Create(frows, fcols);
  Host.fillRandom;
  Move(Host.DataPtr^, MTLBufferContents(FBuffer)^, NativeUInt(frows) * fcols * SizeOf(Single));
end;

procedure TVMobjMTL.Id;
const
  s = 'TVMobjMTL.Id : ';
begin
  assert(frows = fcols, s + 'matrix must be square');
  MTLDispatch2D(mkIdentity, frows, fcols, [FBuffer], [Integer(frows)]);
end;

procedure TVMobjMTL.linspace(Start, increment: Single);
const
  s = 'TVMobjMTL.linspace : ';
begin
  assert((frows = 1) or (fcols = 1), s + 'must be a vector (Rows=1 or Cols=1)');
  MTLDispatch1D(mkLinspace, NativeUInt(frows) * fcols, [FBuffer], [Start, increment]);
end;

function TVMobjMTL.Transpose: TVMobjMTL;
begin
  Result := TVMobjMTL.Create(fcols, frows);
  MTLDispatch2D(mkTranspose, frows, fcols, [FBuffer, Result.FBuffer], [Integer(frows), Integer(fcols)]);
end;

// Downloads the whole buffer once and delegates to TVMobjS's own
// writeMatrix, same as TVMobjCL's own writeMatrix.
function TVMobjMTL.writeMatrix: TStringList;
begin
  Result := ToHost(Self).writeMatrix;
end;

function CopyObjMTL(const A: TVMobjMTL): TVMobjMTL;
begin
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLCopyBuffer(A.FBuffer, Result.FBuffer, NativeUInt(A.frows) * A.fcols);
end;

function ToDeviceMTL(const A: TVMobjS): TVMobjMTL;
begin
  Result := TVMobjMTL.Create(A.Rows, A.Cols);
  Move(A.DataPtr^, MTLBufferContents(Result.FBuffer)^, NativeUInt(A.Rows) * A.Cols * SizeOf(Single));
end;

function ToHost(const A: TVMobjMTL): TVMobjS;
begin
  Result := TVMobjS.Create(A.frows, A.fcols);
  Move(MTLBufferContents(A.FBuffer)^, Result.DataPtr^, NativeUInt(A.frows) * A.fcols * SizeOf(Single));
end;

// Shared body for every elementwise-binary kernel (add/sub/mul) - mirrors
// TVMobjCL's own RunBinary/RunUnary/RunScalar helpers exactly, just
// dispatching through MetalAPI.MTLDispatch1D instead of raw
// clSetKernelArg/clEnqueueNDRangeKernel calls.
function RunBinary(Kernel: TMTLKernel; const A, B: TVMobjMTL; const Routine: string): TVMobjMTL;
begin
  assert((A.frows = B.frows) and (A.fcols = B.fcols), Routine + ' : dimensions of A and B must be the same');
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLDispatch1D(Kernel, NativeUInt(A.frows) * A.fcols, [A.FBuffer, B.FBuffer, Result.FBuffer], []);
end;

function RunUnary(Kernel: TMTLKernel; const A: TVMobjMTL): TVMobjMTL;
begin
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLDispatch1D(Kernel, NativeUInt(A.frows) * A.fcols, [A.FBuffer, Result.FBuffer], []);
end;

function RunScalar(Kernel: TMTLKernel; const A: TVMobjMTL; k: Single): TVMobjMTL;
begin
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLDispatch1D(Kernel, NativeUInt(A.frows) * A.fcols, [A.FBuffer, Result.FBuffer], [k]);
end;

class operator TVMobjMTL.+(const A, B: TVMobjMTL): TVMobjMTL;
begin
  Result := RunBinary(mkAdd, A, B, 'TVMobjMTL.+');
end;

class operator TVMobjMTL.-(const A, B: TVMobjMTL): TVMobjMTL;
begin
  Result := RunBinary(mkSub, A, B, 'TVMobjMTL.-');
end;

class operator TVMobjMTL.-(const A: TVMobjMTL): TVMobjMTL;
begin
  Result := RunUnary(mkNeg, A);
end;

// Element-wise (Hadamard) product - NOT a matrix product. See this unit's
// own header comment and MatMultMTL for the real matrix product.
class operator TVMobjMTL.*(const A, B: TVMobjMTL): TVMobjMTL;
begin
  Result := RunBinary(mkMul, A, B, 'TVMobjMTL.*');
end;

class operator TVMobjMTL.*(const A: TVMobjMTL; const k: Single): TVMobjMTL;
begin
  Result := RunScalar(mkScale, A, k);
end;

class operator TVMobjMTL.*(const k: Single; const A: TVMobjMTL): TVMobjMTL;
begin
  Result := RunScalar(mkScale, A, k);
end;

class operator TVMobjMTL./(const A: TVMobjMTL; const k: Single): TVMobjMTL;
const
  s = 'TVMobjMTL./ : ';
begin
  assert(k <> 0, s + 'division by zero');
  Result := RunScalar(mkDivScalar, A, k);
end;

class operator TVMobjMTL.=(const A, B: TVMobjMTL): Boolean;
var
  HA, HB: TVMobjS;
begin
  if (A.frows <> B.frows) or (A.fcols <> B.fcols) then begin
    Result := False;
    Exit;
  end;
  // No GPU-side reduction kernel for this (rare, test-oriented) operator -
  // same rationale as TVMobjCL's own '=' operator.
  HA := ToHost(A);
  HB := ToHost(B);
  Result := HA = HB;
end;

function Sin(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkSin, A); end;
function Cos(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkCos, A); end;
function Tan(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkTan, A); end;
function Sinh(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkSinh, A); end;
function Sqr(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkSqr, A); end;
function Sqrt(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkSqrt, A); end;
function Exp(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkExp, A); end;
function Ln(const A: TVMobjMTL): TVMobjMTL; begin Result := RunUnary(mkLn, A); end;

// Naive matrix product - same v1 scope choice as MatMultCL, see that
// function's own comment in newVMCL.pas for the full rationale.
function MatMultMTL(const A, B: TVMobjMTL): TVMobjMTL;
const
  s = 'Function MatMultMTL : ';
var
  M, N, K: Integer;
begin
  assert(A.fcols = B.frows, s + 'A.Cols must equal B.Rows');
  M := A.frows;
  K := A.fcols;
  N := B.fcols;
  Result := TVMobjMTL.Create(M, N);
  MTLDispatch2D(mkMatMul, M, N, [A.FBuffer, B.FBuffer, Result.FBuffer], [M, N, K]);
end;

function FFT(const A: TVMobjMTL): TVMobjMTL;
const
  s = 'Function FFT (TVMobjMTL) : ';
var
  N: NativeUInt;
begin
  assert((A.frows = 1) or (A.fcols = 1), s + 'A must be a vector (Rows=1 or Cols=1)');
  assert((NativeUInt(A.frows) * A.fcols) mod 2 = 0, s + 'A must hold an even number of floats (interleaved re/im pairs)');
  N := (NativeUInt(A.frows) * A.fcols) div 2;
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLFFT(A.FBuffer, Result.FBuffer, N);
end;

function IFFT(const A: TVMobjMTL): TVMobjMTL;
const
  s = 'Function IFFT (TVMobjMTL) : ';
var
  N: NativeUInt;
begin
  assert((A.frows = 1) or (A.fcols = 1), s + 'A must be a vector (Rows=1 or Cols=1)');
  assert((NativeUInt(A.frows) * A.fcols) mod 2 = 0, s + 'A must hold an even number of floats (interleaved re/im pairs)');
  N := (NativeUInt(A.frows) * A.fcols) div 2;
  Result := TVMobjMTL.Create(A.frows, A.fcols);
  MTLIFFT(A.FBuffer, Result.FBuffer, N);
  // No extra /N scaling here - MetalAPI.MTLIFFT already applies
  // MPSGraphFFTScalingModeSize (automatic 1/N). See this unit's own header
  // comment (FFT/IFFT) and MetalAPI.pas's for how this was confirmed via a
  // real round-trip probe before being relied on here.
end;

end.
