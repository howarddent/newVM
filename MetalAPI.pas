unit MetalAPI;

{*******************************************************************************

     Hand-curated Objective-C bindings for Apple's Metal (compute) and
     MetalPerformanceShadersGraph (FFT), backing newVMMetal.pas's TVMobjMTL -
     only the subset of each API newVMMetal.pas actually needs, not a
     wholesale header translation. Plays the same role for newVMMetal.pas
     that OpenCLAPI.pas plays for newVMCL.pas: TVMobjMTL is the Metal analogue
     of TVMobjCL (OpenCL+clFFT), added because Metal - not OpenCL, which is
     deprecated on Apple platforms and was never found on this Darwin/AArch64
     dev machine (see newvmconfigure.lpr's own HAVE_OPENCL probe, left
     Windows-only on purpose) - is this machine's real, always-present GPU
     API. newVMCL.pas itself is untouched; this is a new, parallel unit.

     WHY LINK-TIME linkframework DIRECTIVES, NOT DYNAMIC LOADING (unlike
     OpenCLAPI.pas's own OpenCL.dll/clFFT.dll dlopen approach): Metal.framework
     and MetalPerformanceShadersGraph.framework are always present, at a
     fixed, versionless location, on every real Mac since 10.11 (Metal) and
     14.0 (the MPSGraph FFT ops used here) respectively - there is no
     "might not be installed" scenario the way OpenCL/clFFT were genuinely
     optional third-party Windows installs. Framework linking (the three
     linkframework directives right below the type declarations further
     down this unit, for Metal / Foundation / MetalPerformanceShadersGraph)
     is the standard, supported way to pull in Objective-C classes/protocols
     at all - unlike a plain C DLL, you cannot dlopen a framework and
     GetProcedureAddress your way to individual ObjC classes, since class
     lookup and message dispatch go through the Objective-C runtime, which
     needs the framework's real Mach-O image loaded and registered, not just
     a couple of resolved function pointers.

     REQUIRES the objectivec1 modeswitch (hence mode objfpc, not this
     codebase's usual mode Delphi - FPC's objc protocol/class syntax is
     objfpc-mode-only; no Delphi-mode + objectivec1 precedent exists anywhere
     in FPC's own test suite, confirmed by inspection before writing this).
     newVMMetal.pas itself stays in mode Delphi with the AdvancedRecords
     modeswitch, exactly like newVMCL.pas - this unit's PUBLIC INTERFACE
     exposes only plain types (mtl_buffer = Pointer, etc - the same "opaque
     handle" convention OpenCLAPI.pas already uses for cl_mem etc), never a
     raw objcclass/objcprotocol type, so no caller needs objectivec1 itself.
     Cross-mode unit calls are already an established, working pattern here
     (OpenCLAPI.pas is itself plain mode ObjFPC, called from Delphi-mode
     newVMCL.pas today) - this just goes one step further on the callee side.

     REFERENCE-COUNTING: FPC's Objective-C bridging is plain manual
     retain/release (like classic Cocoa MRC), NOT ARC - confirmed against
     objcbase.pp, where retain/release/autorelease are declared as ordinary
     `message`-dispatched NSObject methods, not compiler-inserted calls. Every
     "new..."/"alloc"/"copy..." method (Cocoa's Fundamental Rule) returns an
     object this code owns a +1 reference to and must eventually release;
     every other factory/accessor method (deviceWithMTLDevice:,
     arrayWithObject:, commandBuffer, placeholderWithShape:..., etc) returns
     an autoreleased object this code must NOT release. This is exactly the
     same discipline newVMCL.pas's own header comment documents needing for
     OpenCL's cl_mem (clRetainMemObject/clReleaseMemObject) - only the GPU
     buffer handle (mtl_buffer, this unit's analogue of cl_mem) is something
     newVMMetal.pas's managed TVMobjMTL record needs to individually
     retain-count-track across assignment/copy/finalize, mirroring
     TVMobjCL's own Initialize/Finalize/AddRef/Copy class operators exactly.
     Every dispatch/FFT call below that creates transient autoreleased
     objects (command buffers, encoders, graph tensors, NSNumber/NSArray
     temporaries) wraps its own work in a fresh NSAutoreleasePool so those
     don't pile up silently across repeated calls (e.g. once per SDR epoch
     tick) - there is no pool on the thread by default outside one.

     THE ONE REAL GOTCHA, FOUND BY A STANDALONE PROBE BEFORE ANY OF THIS WAS
     WRITTEN (mirroring OpenCLAPI.pas's own "verified against the real API"
     discipline): a plain FPC console program that does nothing but call
     MTLCreateSystemDefaultDevice() crashes, deterministically, with
     EXC_BAD_INSTRUCTION deep inside Apple's own AGX Metal driver (on a
     background GCD dispatch queue, inside a floating-point compare while
     building an internal sampler-state table) - while the exact same call
     from a plain clang-compiled Objective-C program on this same machine
     (same GPU, "Apple M4 Max") works perfectly. Root cause: FPC's default
     AArch64 FPCR configuration leaves floating-point exception trapping
     armed in a way clang-generated code does not, and the AGX driver's own
     float code was never written expecting a caller with traps enabled -
     the exact same CLASS of bug this codebase already hit once before, on a
     different platform/library pair (see git history: "Fix Windows
     EInvalidOp crash from MKL LAPACKE complex solve calls"). Fix, confirmed
     by the same probe: call Math.SetExceptionMask to mask every FPU
     exception BEFORE the first Metal/MPSGraph call of the process - done
     once, from InitializeMetalContext below, mirroring
     EnsureOpenCLReady/InitializeOpenCLContext's own "do it once, lazily, on
     first use" shape.

     MPSGraph FFT LAYOUT AND SCALING - both confirmed against a real,
     running 16-point complex FFT of a pure bin-2 cosine (magnitude-8.0 peaks
     at bins 2 and 14, matching newVMCL.pas's own TestFFTKnownValues exactly)
     and a full IFFT(FFT(x))=x round trip, by the same standalone probe:
     - MPSDataTypeComplexFloat32's native in-memory layout IS interleaved
       (re,im) float pairs - the same CLFFT_COMPLEX_INTERLEAVED-equivalent
       layout newVMCL.pas's own FFT/IFFT already use (TVMobjMTL's Cols=2*N
       convention, unchanged from TVMobjCL's) - no repacking needed.
     - Forward FFT: MPSGraphFFTDescriptor.inverse=False,
       scalingMode=MPSGraphFFTScalingModeNone (unscaled, matching clFFT's own
       forward-transform convention). Inverse FFT:
       inverse=True, scalingMode=MPSGraphFFTScalingModeSize (automatic 1/N
       scale) - gives an EXACT round trip with no manual "/N" needed,
       matching clFFT's own already-normalised backward transform (see
       newVMCL.pas's IFFT comment for the analogous clFFT finding). Get this
       backwards (or add a manual extra /N) and, per that same newVMCL.pas
       comment's own cautionary tale, every round-trip mismatch will be off
       by exactly a factor of N - worth re-reading before "fixing" this.

*******************************************************************************}

{$mode objfpc}{$H+}
{$modeswitch objectivec1}
// FPC 3.2.4's DWARF3 debug-info generator hits a genuine internal compiler
// error ("Fatal: Internal error 200609171") on this unit's
// objcclass/objcprotocol type declarations, specifically when combined
// with -gl (the line-info unit, linked for symbolic runtime-error
// backtraces - reproduced standalone: -gw3 alone compiles fine, -gl alone
// compiles fine, -gw3 -gl together ICE every time; {$DEBUGINFO OFF} does
// NOT suppress it, since -gl's line-table generation isn't gated by that
// directive). newVMtest.lpi's DebugInfoType is therefore dsDwarf2, not the
// Lazarus default dsDwarf3 - confirmed DWARF2 (-gw2) compiles this unit
// (and the rest of the project) cleanly with -gl still enabled, so this
// costs nothing but a debug-format choice, not any actual debug capability.
// If a future FPC release fixes this and someone switches the project back
// to dsDwarf3, this is the first thing to check if MetalAPI.pas suddenly
// won't compile again.

interface

uses
  Classes, SysUtils, Math;

type
  mtl_buffer = Pointer;

  TMTLKernel = (
    mkAdd, mkSub, mkNeg, mkMul, mkScale, mkDivScalar,
    mkTranspose, mkSin, mkCos, mkTan, mkSinh, mkSqr, mkSqrt, mkExp, mkLn,
    mkLinspace, mkIdentity, mkMatMul
  );

// Lazily creates the device/command queue/compiled kernel library (once per
// process) and masks FPU exceptions (see header comment) - called
// automatically by every other function below, so callers only need it
// directly if they want to report a readiness/error status up front
// (mirrors newVMCL.pas's own OpenCLReady/OpenCLLastError contract).
function InitializeMetalContext(out ErrMsg: string): Boolean;
function MetalContextReady: Boolean;
function MetalContextLastError: string;

// NumFloats * SizeOf(Single) bytes, shared-storage (CPU+GPU visible,
// Apple Silicon unified memory - see MTLBufferContents below).
function MTLNewBuffer(NumFloats: NativeUInt): mtl_buffer;
procedure MTLReleaseBuffer(Buf: mtl_buffer);
// Raw pointer straight into the buffer's own shared-memory storage - valid
// as long as Buf is retained; read/write it directly (Move/indexing), no
// separate upload/download call needed (unlike OpenCLAPI.pas's
// clEnqueueRead/WriteBuffer round trips - Apple Silicon's unified memory
// makes that unnecessary here).
function MTLBufferContents(Buf: mtl_buffer): PSingle;
procedure MTLCopyBuffer(Src, Dst: mtl_buffer; NumFloats: NativeUInt);

// Dispatches a 1D elementwise kernel over Count threads. Buffers are bound
// at buffer indices 0..High(Buffers); ScalarArgs (if any) follow at
// Length(Buffers)..  - matches the parameter order every 1D kernel in
// MSLKernelSource below declares. Blocks until the GPU has finished (matches
// TVMobjCL's own clEnqueueNDRangeKernel + implicit-blocking-read contract -
// every TVMobjMTL operation is synchronous from its caller's point of view).
procedure MTLDispatch1D(Kernel: TMTLKernel; Count: NativeUInt;
  const Buffers: array of mtl_buffer; const ScalarArgs: array of Single);

// Dispatches a 2D kernel (mat_transpose/mat_identity/mat_mul) over a
// Rows x Cols (or M x N, for mat_mul) grid. IntArgs follow the buffers at
// the same buffer-index convention as MTLDispatch1D.
procedure MTLDispatch2D(Kernel: TMTLKernel; DimX, DimY: NativeUInt;
  const Buffers: array of mtl_buffer; const IntArgs: array of Integer);

// Complex-to-complex FFT/IFFT via MPSGraph - Src/Dst are Cols=2*N
// interleaved-(re,im) buffers (Dst may differ from Src; unlike clFFT's own
// CLFFT_INPLACE-only setup in newVMCL.pas, MPSGraph naturally supports
// separate input/output tensors, so no CopyObjMTL-first step is needed
// here - newVMMetal.pas's FFT/IFFT can allocate a fresh result and dispatch
// directly into it). Builds (and caches, keyed on N - rebuilding only when N
// changes, mirroring uVMPlotSDRSpectrum.pas's own FWindowEpochSize caching
// pattern) one small MPSGraph per direction the first time each is used at a
// given N.
procedure MTLFFT(Src, Dst: mtl_buffer; N: NativeUInt);
procedure MTLIFFT(Src, Dst: mtl_buffer; N: NativeUInt);

implementation

uses
  ctypes;

type
  NSUInteger = QWord;

  NSString = objcclass external (NSObject)
    class function stringWithUTF8String(nullTerminatedCString: PAnsiChar): id; message 'stringWithUTF8String:';
    function UTF8String: PAnsiChar; message 'UTF8String';
  end;

  NSError = objcclass external (NSObject)
    function localizedDescription: NSString; message 'localizedDescription';
  end;
  PNSErrorObj = ^NSError;

  NSNumber = objcclass external (NSObject)
    class function numberWithUnsignedInteger(value: NSUInteger): id; message 'numberWithUnsignedInteger:';
  end;

  NSArray = objcclass external (NSObject)
    class function arrayWithObject(anObject: id): id; message 'arrayWithObject:';
  end;

  NSMutableDictionary = objcclass external (NSObject)
    class function dictionary: id; message 'dictionary';
    procedure setObject_forKey(anObject: id; aKey: id); message 'setObject:forKey:';
  end;

  MTLSize = record
    width, height, depth: NSUInteger;
  end;

  MTLComputeCommandEncoder = objcprotocol external name 'MTLComputeCommandEncoder'
    procedure setComputePipelineState(state: id); message 'setComputePipelineState:';
    procedure setBuffer_offset_atIndex(buffer: id; offset: NSUInteger; index: NSUInteger); message 'setBuffer:offset:atIndex:';
    procedure setBytes_length_atIndex(bytes: Pointer; length: NSUInteger; index: NSUInteger); message 'setBytes:length:atIndex:';
    procedure dispatchThreads_threadsPerThreadgroup(threadsPerGrid: MTLSize; threadsPerThreadgroup: MTLSize); message 'dispatchThreads:threadsPerThreadgroup:';
    procedure endEncoding; message 'endEncoding';
  end;

  MTLCommandBuffer = objcprotocol external name 'MTLCommandBuffer'
    function computeCommandEncoder: MTLComputeCommandEncoder; message 'computeCommandEncoder';
    procedure commit; message 'commit';
    procedure waitUntilCompleted; message 'waitUntilCompleted';
  end;

  MTLCommandQueue = objcprotocol external name 'MTLCommandQueue'
    function commandBuffer: MTLCommandBuffer; message 'commandBuffer';
  end;

  MTLBufferProto = objcprotocol external name 'MTLBuffer'
    function contents: Pointer; message 'contents';
    procedure release; message 'release';
  end;

  MTLFunction = objcprotocol external name 'MTLFunction'
  end;

  MTLComputePipelineState = objcprotocol external name 'MTLComputePipelineState'
    function maxTotalThreadsPerThreadgroup: NSUInteger; message 'maxTotalThreadsPerThreadgroup';
  end;

  MTLLibrary = objcprotocol external name 'MTLLibrary'
    function newFunctionWithName(name: NSString): MTLFunction; message 'newFunctionWithName:';
  end;

  MTLDevice = objcprotocol external name 'MTLDevice'
    function newCommandQueue: MTLCommandQueue; message 'newCommandQueue';
    function newBufferWithLength_options(length: NSUInteger; options: NSUInteger): MTLBufferProto; message 'newBufferWithLength:options:';
    function newLibraryWithSource_options_error(source: NSString; options: id; error: PNSErrorObj): MTLLibrary; message 'newLibraryWithSource:options:error:';
    function newComputePipelineStateWithFunction_error(fn: MTLFunction; error: PNSErrorObj): MTLComputePipelineState; message 'newComputePipelineStateWithFunction:error:';
  end;

  MPSGraphDevice = objcclass external (NSObject)
    class function deviceWithMTLDevice(dev: id): id; message 'deviceWithMTLDevice:';
  end;

  MPSGraphTensor = objcclass external (NSObject)
  end;

  MPSGraphTensorData = objcclass external (NSObject)
    function initWithMTLBuffer_shape_dataType(buffer: id; shape: id; dataType: NSUInteger): id; message 'initWithMTLBuffer:shape:dataType:';
  end;

  MPSGraphFFTDescriptor = objcclass external (NSObject)
    class function descriptor: id; message 'descriptor';
    procedure setInverse(v: Boolean); message 'setInverse:';
    procedure setScalingMode(v: NSUInteger); message 'setScalingMode:';
  end;

  MPSGraph = objcclass external (NSObject)
    function placeholderWithShape_dataType_name(shape: id; dataType: NSUInteger; nm: id): id; message 'placeholderWithShape:dataType:name:';
    function fastFourierTransformWithTensor_axes_descriptor_name(tensor: id; axes: id; descriptor: id; nm: id): id; message 'fastFourierTransformWithTensor:axes:descriptor:name:';
    procedure runWithMTLCommandQueue_feeds_targetOperations_resultsDictionary(q: id; feeds: id; targetOps: id; results: id); message 'runWithMTLCommandQueue:feeds:targetOperations:resultsDictionary:';
  end;

  NSAutoreleasePool = objcclass external (NSObject)
  end;

function MTLCreateSystemDefaultDevice: id; cdecl; external name 'MTLCreateSystemDefaultDevice';

{$linkframework Metal}
{$linkframework Foundation}
{$linkframework MetalPerformanceShadersGraph}

const
  MPSDataTypeFloatBit        = $10000000;
  MPSDataTypeComplexBit      = $01000000;
  MPSDataTypeComplexFloat32  = MPSDataTypeFloatBit or MPSDataTypeComplexBit or 64;
  MTLResourceStorageModeShared = 0;
  MPSGraphFFTScalingModeNone = 0;
  MPSGraphFFTScalingModeSize = 1;

  KernelNames: array[TMTLKernel] of string = (
    'vec_add', 'vec_sub', 'vec_neg', 'vec_mul', 'vec_scale', 'vec_divscalar',
    'mat_transpose', 'vec_sin', 'vec_cos', 'vec_tan', 'vec_sinh', 'vec_sqr',
    'vec_sqrt', 'vec_exp', 'vec_ln', 'vec_linspace', 'mat_identity', 'mat_mul'
  );

  // Mechanical MSL translation of newVMCL.pas's own OpenC-C KernelSource -
  // same kernel set, same naive (non-tiled) mat_mul scope decision. MSL
  // binds buffer args via [[buffer(N)]] (set via setBuffer:offset:atIndex:)
  // and scalar constants via `constant T&` (set via setBytes:length:atIndex:,
  // Metal's direct small-constant-passing mechanism - simpler than OpenCL's
  // clSetKernelArg for the same purpose, no separate buffer object needed).
  MSLKernelSource: PAnsiChar =
    '#include <metal_stdlib>' + LineEnding +
    'using namespace metal;' + LineEnding +
    'kernel void vec_add(device const float* a [[buffer(0)]], device const float* b [[buffer(1)]], device float* c [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] + b[i]; }' + LineEnding +
    'kernel void vec_sub(device const float* a [[buffer(0)]], device const float* b [[buffer(1)]], device float* c [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] - b[i]; }' + LineEnding +
    'kernel void vec_neg(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = -a[i]; }' + LineEnding +
    'kernel void vec_mul(device const float* a [[buffer(0)]], device const float* b [[buffer(1)]], device float* c [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] * b[i]; }' + LineEnding +
    'kernel void vec_scale(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], constant float& k [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] * k; }' + LineEnding +
    'kernel void vec_divscalar(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], constant float& k [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] / k; }' + LineEnding +
    'kernel void mat_transpose(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], constant int& rows [[buffer(2)]], constant int& cols [[buffer(3)]], uint2 gid [[thread_position_in_grid]]) { uint r = gid.x; uint cc = gid.y; c[cc*uint(rows) + r] = a[r*uint(cols) + cc]; }' + LineEnding +
    'kernel void vec_sin(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = sin(a[i]); }' + LineEnding +
    'kernel void vec_cos(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = cos(a[i]); }' + LineEnding +
    'kernel void vec_tan(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = tan(a[i]); }' + LineEnding +
    'kernel void vec_sinh(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = sinh(a[i]); }' + LineEnding +
    'kernel void vec_sqr(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = a[i] * a[i]; }' + LineEnding +
    'kernel void vec_sqrt(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = sqrt(a[i]); }' + LineEnding +
    'kernel void vec_exp(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = exp(a[i]); }' + LineEnding +
    'kernel void vec_ln(device const float* a [[buffer(0)]], device float* c [[buffer(1)]], uint i [[thread_position_in_grid]]) { c[i] = log(a[i]); }' + LineEnding +
    'kernel void vec_linspace(device float* c [[buffer(0)]], constant float& start [[buffer(1)]], constant float& step [[buffer(2)]], uint i [[thread_position_in_grid]]) { c[i] = start + float(i) * step; }' + LineEnding +
    'kernel void mat_identity(device float* c [[buffer(0)]], constant int& n [[buffer(1)]], uint2 gid [[thread_position_in_grid]]) { uint r = gid.x; uint cc = gid.y; c[r*uint(n) + cc] = (r == cc) ? 1.0f : 0.0f; }' + LineEnding +
    'kernel void mat_mul(device const float* a [[buffer(0)]], device const float* b [[buffer(1)]], device float* c [[buffer(2)]], constant int& M [[buffer(3)]], constant int& N [[buffer(4)]], constant int& K [[buffer(5)]], uint2 gid [[thread_position_in_grid]]) {' + LineEnding +
    '  uint row = gid.x; uint col = gid.y; float sum = 0.0f;' + LineEnding +
    '  for (int k = 0; k < K; k++) sum += a[row*uint(K) + uint(k)] * b[uint(k)*uint(N) + col];' + LineEnding +
    '  c[row*uint(N) + col] = sum; }';

var
  GDevice: MTLDevice = nil;
  GQueue: MTLCommandQueue = nil;
  GPipelines: array[TMTLKernel] of MTLComputePipelineState;
  GReadyState: (grUntried, grReady, grFailed) = grUntried;
  GInitError: string = '';

  // FFT graph cache - see MTLFFT/MTLIFFT below. Rebuilt only when N changes,
  // mirroring uVMPlotSDRSpectrum.pas's own FWindowEpochSize caching pattern.
  GFFTGraph, GIFFTGraph: MPSGraph;
  GFFTPlaceholder, GFFTOutTensor: MPSGraphTensor;
  GIFFTPlaceholder, GIFFTOutTensor: MPSGraphTensor;
  GFFTShape: id = nil;
  GFFTN: NativeUInt = 0;

function MakeMTLSize(w, h, d: NSUInteger): MTLSize;
begin
  Result.width := w;
  Result.height := h;
  Result.depth := d;
end;

function NSStr(const S: string): NSString;
begin
  Result := NSString(NSString.stringWithUTF8String(PAnsiChar(S)));
end;

procedure EnsureMetalReady;
const
  s = 'MetalAPI initialization : ';
var
  K: TMTLKernel;
  Err: NSError;
  Lib: MTLLibrary;
  Fn: MTLFunction;
begin
  if GReadyState <> grUntried then Exit;

  // See this unit's own header comment (THE ONE REAL GOTCHA) - must happen
  // before the very first Metal/MPSGraph call in the process.
  SetExceptionMask([exInvalidOp, exOverflow, exUnderflow, exZeroDivide, exPrecision, exDenormalized]);

  GDevice := MTLDevice(MTLCreateSystemDefaultDevice);
  if GDevice = nil then begin
    GInitError := s + 'MTLCreateSystemDefaultDevice returned nil';
    GReadyState := grFailed;
    Exit;
  end;

  GQueue := GDevice.newCommandQueue;
  if GQueue = nil then begin
    GInitError := s + 'newCommandQueue returned nil';
    GReadyState := grFailed;
    Exit;
  end;

  Err := nil;
  Lib := GDevice.newLibraryWithSource_options_error(NSStr(MSLKernelSource), nil, @Err);
  if Lib = nil then begin
    if Assigned(Err) then
      GInitError := s + 'newLibraryWithSource failed: ' + string(Err.localizedDescription.UTF8String)
    else
      GInitError := s + 'newLibraryWithSource failed, no NSError';
    GReadyState := grFailed;
    Exit;
  end;

  for K := Low(TMTLKernel) to High(TMTLKernel) do begin
    Fn := Lib.newFunctionWithName(NSStr(KernelNames[K]));
    if Fn = nil then begin
      GInitError := s + 'newFunctionWithName(' + KernelNames[K] + ') returned nil';
      GReadyState := grFailed;
      Exit;
    end;
    Err := nil;
    GPipelines[K] := GDevice.newComputePipelineStateWithFunction_error(Fn, @Err);
    if GPipelines[K] = nil then begin
      if Assigned(Err) then
        GInitError := s + 'newComputePipelineStateWithFunction(' + KernelNames[K] + ') failed: ' + string(Err.localizedDescription.UTF8String)
      else
        GInitError := s + 'newComputePipelineStateWithFunction(' + KernelNames[K] + ') failed, no NSError';
      GReadyState := grFailed;
      Exit;
    end;
  end;

  GReadyState := grReady;
end;

function InitializeMetalContext(out ErrMsg: string): Boolean;
begin
  EnsureMetalReady;
  Result := GReadyState = grReady;
  ErrMsg := GInitError;
end;

function MetalContextReady: Boolean;
begin
  EnsureMetalReady;
  Result := GReadyState = grReady;
end;

function MetalContextLastError: string;
begin
  Result := GInitError;
end;

function MTLNewBuffer(NumFloats: NativeUInt): mtl_buffer;
const
  s = 'MTLNewBuffer : ';
var
  Buf: MTLBufferProto;
begin
  EnsureMetalReady;
  assert(GReadyState = grReady, s + 'Metal not available (' + GInitError + ')');
  Buf := GDevice.newBufferWithLength_options(NumFloats * SizeOf(Single), MTLResourceStorageModeShared);
  assert(Buf <> nil, s + 'newBufferWithLength:options: returned nil');
  Result := Pointer(Buf);
end;

procedure MTLReleaseBuffer(Buf: mtl_buffer);
begin
  if Buf <> nil then MTLBufferProto(Buf).release;
end;

function MTLBufferContents(Buf: mtl_buffer): PSingle;
begin
  Result := PSingle(MTLBufferProto(Buf).contents);
end;

procedure MTLCopyBuffer(Src, Dst: mtl_buffer; NumFloats: NativeUInt);
begin
  Move(MTLBufferProto(Src).contents^, MTLBufferProto(Dst).contents^, NumFloats * SizeOf(Single));
end;

// Threads-per-threadgroup must not exceed the pipeline's own
// maxTotalThreadsPerThreadgroup (typically 1024 on Apple GPUs, but not
// guaranteed) - unlike the toy sizes a first standalone probe got away with,
// TVMobjMTL's real Rows/Cols (up to MaxDimMTL) need this clamped properly.
function ClampGroup1D(PSO: MTLComputePipelineState; Count: NativeUInt): NSUInteger;
var
  MaxT: NSUInteger;
begin
  MaxT := PSO.maxTotalThreadsPerThreadgroup;
  if (MaxT = 0) or (MaxT > Count) then MaxT := Count;
  Result := MaxT;
end;

procedure MTLDispatch1D(Kernel: TMTLKernel; Count: NativeUInt;
  const Buffers: array of mtl_buffer; const ScalarArgs: array of Single);
const
  s = 'MTLDispatch1D : ';
var
  Pool: NSAutoreleasePool;
  PSO: MTLComputePipelineState;
  CB: MTLCommandBuffer;
  Enc: MTLComputeCommandEncoder;
  I: Integer;
  Grp: NSUInteger;
begin
  EnsureMetalReady;
  assert(GReadyState = grReady, s + 'Metal not available (' + GInitError + ')');
  Pool := NSAutoreleasePool(NSAutoreleasePool.alloc.init);
  try
    PSO := GPipelines[Kernel];
    CB := GQueue.commandBuffer;
    Enc := CB.computeCommandEncoder;
    Enc.setComputePipelineState(id(PSO));
    for I := 0 to High(Buffers) do
      Enc.setBuffer_offset_atIndex(id(Buffers[I]), 0, NSUInteger(I));
    for I := 0 to High(ScalarArgs) do
      Enc.setBytes_length_atIndex(@ScalarArgs[I], SizeOf(Single), NSUInteger(Length(Buffers) + I));
    Grp := ClampGroup1D(PSO, Count);
    Enc.dispatchThreads_threadsPerThreadgroup(MakeMTLSize(Count, 1, 1), MakeMTLSize(Grp, 1, 1));
    Enc.endEncoding;
    CB.commit;
    CB.waitUntilCompleted;
  finally
    Pool.release;
  end;
end;

procedure MTLDispatch2D(Kernel: TMTLKernel; DimX, DimY: NativeUInt;
  const Buffers: array of mtl_buffer; const IntArgs: array of Integer);
const
  s = 'MTLDispatch2D : ';
var
  Pool: NSAutoreleasePool;
  PSO: MTLComputePipelineState;
  CB: MTLCommandBuffer;
  Enc: MTLComputeCommandEncoder;
  I: Integer;
  MaxT, GX, GY: NSUInteger;
begin
  EnsureMetalReady;
  assert(GReadyState = grReady, s + 'Metal not available (' + GInitError + ')');
  Pool := NSAutoreleasePool(NSAutoreleasePool.alloc.init);
  try
    PSO := GPipelines[Kernel];
    CB := GQueue.commandBuffer;
    Enc := CB.computeCommandEncoder;
    Enc.setComputePipelineState(id(PSO));
    for I := 0 to High(Buffers) do
      Enc.setBuffer_offset_atIndex(id(Buffers[I]), 0, NSUInteger(I));
    for I := 0 to High(IntArgs) do
      Enc.setBytes_length_atIndex(@IntArgs[I], SizeOf(Integer), NSUInteger(Length(Buffers) + I));
    MaxT := PSO.maxTotalThreadsPerThreadgroup;
    if MaxT = 0 then MaxT := 1;
    // Simple square-ish split of the per-threadgroup budget across both
    // dims, then clamped to the actual grid size - no tuning attempted,
    // matching MatMultCL's own "naive, not a tuned GEMM" v1 scope choice.
    GX := Trunc(Sqrt(MaxT));
    if GX = 0 then GX := 1;
    GY := MaxT div GX;
    if GY = 0 then GY := 1;
    if GX > DimX then GX := DimX;
    if GY > DimY then GY := DimY;
    Enc.dispatchThreads_threadsPerThreadgroup(MakeMTLSize(DimX, DimY, 1), MakeMTLSize(GX, GY, 1));
    Enc.endEncoding;
    CB.commit;
    CB.waitUntilCompleted;
  finally
    Pool.release;
  end;
end;

// Builds (or reuses, if N matches the last call) the two small FFT graphs
// and the shared MPSShape for that N - see this unit's header comment for
// why one graph per direction, cached by N, rather than one static
// upfront graph (MPSGraph placeholders need a fixed shape at build time,
// and different TVMobjMTL callers may use different N - e.g. the test
// suite's 16-point check vs SDR_Radio's 8192-sample epochs).
procedure EnsureFFTGraphs(N: NativeUInt);
var
  Axes: id;
  FwdDesc, InvDesc: id;
begin
  if GFFTN = N then Exit;

  GFFTShape := NSArray.arrayWithObject(NSNumber.numberWithUnsignedInteger(N));
  Axes := NSArray.arrayWithObject(NSNumber.numberWithUnsignedInteger(0));

  GFFTGraph := MPSGraph(MPSGraph.alloc.init);
  GFFTPlaceholder := MPSGraphTensor(GFFTGraph.placeholderWithShape_dataType_name(GFFTShape, MPSDataTypeComplexFloat32, nil));
  FwdDesc := MPSGraphFFTDescriptor.descriptor;
  MPSGraphFFTDescriptor(FwdDesc).setInverse(False);
  MPSGraphFFTDescriptor(FwdDesc).setScalingMode(MPSGraphFFTScalingModeNone);
  GFFTOutTensor := MPSGraphTensor(GFFTGraph.fastFourierTransformWithTensor_axes_descriptor_name(
    id(GFFTPlaceholder), Axes, FwdDesc, nil));

  GIFFTGraph := MPSGraph(MPSGraph.alloc.init);
  GIFFTPlaceholder := MPSGraphTensor(GIFFTGraph.placeholderWithShape_dataType_name(GFFTShape, MPSDataTypeComplexFloat32, nil));
  InvDesc := MPSGraphFFTDescriptor.descriptor;
  MPSGraphFFTDescriptor(InvDesc).setInverse(True);
  MPSGraphFFTDescriptor(InvDesc).setScalingMode(MPSGraphFFTScalingModeSize);
  GIFFTOutTensor := MPSGraphTensor(GIFFTGraph.fastFourierTransformWithTensor_axes_descriptor_name(
    id(GIFFTPlaceholder), Axes, InvDesc, nil));

  GFFTN := N;
end;

procedure RunFFTGraph(Graph: MPSGraph; Placeholder, OutTensor: MPSGraphTensor;
  Src, Dst: mtl_buffer; N: NativeUInt);
var
  Pool: NSAutoreleasePool;
  TDIn, TDOut, Feeds, Results: id;
begin
  Pool := NSAutoreleasePool(NSAutoreleasePool.alloc.init);
  try
    TDIn := MPSGraphTensorData(MPSGraphTensorData.alloc).initWithMTLBuffer_shape_dataType(id(Src), GFFTShape, MPSDataTypeComplexFloat32);
    TDOut := MPSGraphTensorData(MPSGraphTensorData.alloc).initWithMTLBuffer_shape_dataType(id(Dst), GFFTShape, MPSDataTypeComplexFloat32);
    Feeds := NSMutableDictionary.dictionary;
    NSMutableDictionary(Feeds).setObject_forKey(TDIn, id(Placeholder));
    Results := NSMutableDictionary.dictionary;
    NSMutableDictionary(Results).setObject_forKey(TDOut, id(OutTensor));
    Graph.runWithMTLCommandQueue_feeds_targetOperations_resultsDictionary(id(GQueue), Feeds, nil, Results);
    MPSGraphTensorData(TDIn).release;
    MPSGraphTensorData(TDOut).release;
  finally
    Pool.release;
  end;
end;

procedure MTLFFT(Src, Dst: mtl_buffer; N: NativeUInt);
const
  s = 'MTLFFT : ';
begin
  EnsureMetalReady;
  assert(GReadyState = grReady, s + 'Metal not available (' + GInitError + ')');
  EnsureFFTGraphs(N);
  RunFFTGraph(GFFTGraph, GFFTPlaceholder, GFFTOutTensor, Src, Dst, N);
end;

procedure MTLIFFT(Src, Dst: mtl_buffer; N: NativeUInt);
const
  s = 'MTLIFFT : ';
begin
  EnsureMetalReady;
  assert(GReadyState = grReady, s + 'Metal not available (' + GInitError + ')');
  EnsureFFTGraphs(N);
  RunFFTGraph(GIFFTGraph, GIFFTPlaceholder, GIFFTOutTensor, Src, Dst, N);
end;

end.
