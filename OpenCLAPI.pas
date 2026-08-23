unit OpenCLAPI;

{*******************************************************************************

     Hand-curated runtime (dlopen-based) bindings for OpenCL core (OpenCL.dll)
     and AMD's clFFT (clFFT.dll), backing newVMCL.pas's TVMobjCL - only the
     subset of each API newVMCL.pas actually calls, not a wholesale header
     translation. Plays the same role for newVMCL.pas that OneAPI.pas plays
     for newVM.pas/newVMSingle.pas/newVMComplex.pas/newVMComplexSingle.pas
     (MKL/IPP), and cblas.pas for OpenBLAS.

     WHY DYNAMIC LOADING, NOT LINK-TIME EXTERNAL - AND WHY THAT MATTERS HERE
     MORE THAN IT DID FOR THE OTHER BINDINGS: every other runtime-bound
     library in this codebase (cblas.pas/OpenBLAS, fftw3.pas/FFTW,
     uHackRF.pas/uRTLSDR.pas/uSDRplay.pas) chose dlopen because the library
     wasn't guaranteed to be link-time-resolvable (unversioned .so symlink
     missing, or the DLL living outside the standard search path).
     OpenCL.dll here is a different case entirely: it's already present at
     C:\Windows\System32\OpenCL.dll (this machine's own AMD/NVIDIA GPU
     drivers put it there), so a plain link-time `external 'OpenCL.dll'`
     declaration SHOULD have worked. It didn't - confirmed directly: a
     standalone probe with static `external` declarations for both
     OpenCL.dll and clFFT.dll failed at PROCESS STARTUP with
     STATUS_DLL_NOT_FOUND (0xC0000135), even with clFFT.dll sitting right
     next to the probe's own .exe - while the exact same probe rewritten to
     use LoadLibrary/GetProcedureAddress at runtime (this unit's own
     pattern) loaded and ran both libraries correctly, including a full
     OpenCL compute-kernel round trip and a real clFFT forward transform,
     against the actual GPU (confirmed on an AMD Radeon PRO W6600, device
     name "gfx1032"). Root cause not fully pinned down (plausibly a
     Windows loader quirk specific to resolving a DLL's own transitive
     dependencies - MSVCP140/VCRUNTIME140/the api-ms-win-crt-* forwarders -
     differently at static-import resolution time than at a later dynamic
     LoadLibrary call) - not worth chasing further given dynamic loading is
     already this codebase's own established, working pattern for exactly
     this class of problem.

     A SECOND GOTCHA THE SAME PROBE CAUGHT: clFFT.h declares
     clfftInitSetupData, the "conventional" first call before clfftSetup,
     but this machine's actual clFFT.dll build does NOT export it
     (confirmed via `dumpbin /exports` - genuinely absent, not a naming
     mismatch) - calling through the resulting nil function pointer
     crashed the probe with an access violation before this was caught.
     clfftInitSetupData only fills in clfftSetupData's version/debugFlags
     fields anyway (cosmetic/diagnostic, not behavioural), and
     clfftSetup(nil) is documented to work without it - so this binding
     doesn't declare clfftInitSetupData at all, and InitializeOpenCL below
     calls clfftSetup(nil) directly.

     clFFT.dll ISN'T ON A STANDARD SEARCH PATH ON THIS MACHINE (there's no
     official installer the way SDRplay's API has - it's wherever this
     machine's own clFFT build happens to live), so - same "try the bare
     name first, fall back to a known location" pattern uSDRplay.pas
     already uses for sdrplay_api.dll - LoadclFFT tries 'clFFT.dll' bare
     first (in case a future deployment puts it on PATH or beside the
     built exe, the documented convention this project's other
     runtime-bound Windows DLLs - openblas.dll, libfftw3-3.dll - already
     follow) and falls back to this machine's own confirmed-working build
     output path.

     STRUCT LAYOUTS AND FUNCTION SIGNATURES were taken from the real
     clFFT.h/cl.h headers (both present on this machine, and from Chet's
     already-correct Pascal translation of them at
     C:\Users\howard\clFFT\src\clFFTpas\clFFT.pas, used here as a
     cross-check on type sizes/field order rather than compiled directly -
     that generated file bundles BOTH OpenCL and clFFT declarations under
     one placeholder library constant, `LIB_SAMPLE = 'sample.dll'`, which
     would need splitting into the two real libraries before it could be
     used as-is) and confirmed against the real, running DLLs by the same
     standalone probe mentioned above: platform/device enumeration, buffer
     create/write/read, program compile, kernel dispatch (a trivial
     "double every element" kernel, verified against known output), and a
     clFFT forward transform (16-point complex FFT of a pure bin-2 cosine,
     verified against the exact expected magnitude-8.0 peaks at bins 2 and
     14) all matched expectations exactly before this binding was written.

*******************************************************************************}

{$mode ObjFPC}{$H+}
{$MINENUMSIZE 4}

interface

uses
  Classes, SysUtils, DynLibs;

const
  {$IFDEF WINDOWS}
  OpenCLLibName = 'OpenCL.dll';
  clFFTLibName = 'clFFT.dll';
  // Confirmed working build/install outputs across the machines this
  // project has been built on - see this unit's own header comment for why
  // clFFT.dll needs a fallback path at all. Tried in order after the bare
  // name.
  clFFTLibFallbackPath = 'C:\Users\howard\clFFT\src\clFFTpas\clFFT.dll';
  clFFTLibFallbackPath2 = 'C:\Users\howar\vcpkg\installed\x64-windows\bin\clFFT.dll';
  {$ELSE}
  OpenCLLibName = 'libOpenCL.so.1';
  clFFTLibName = 'libclFFT.so.0';
  // Confirmed on a real Linux dev machine: clFFT is only present as
  // libclFFT.so.2 (a newer major SONAME than libclFFT.so.0), no
  // libclFFT.so.0 compatibility symlink - same "try the primary name, fall
  // back to a known-good alternate" pattern the Windows branch above uses
  // for clFFT.dll's own fallback path, just reusing that path as a library
  // name rather than a filesystem path since LoadLibrary/dlopen resolves it
  // via the standard search path either way.
  clFFTLibFallbackPath = 'libclFFT.so.2';
  clFFTLibFallbackPath2 = '';   // no second non-Windows fallback needed yet
  {$ENDIF}

  // ---- A minimal subset of OpenCL's own constants - just what newVMCL.pas
  // needs (device/platform query, buffer flags, a few info enums, and the
  // handful of error codes worth naming instead of printing a bare number). ----
  CL_SUCCESS = 0;
  CL_DEVICE_NOT_FOUND = -1;
  CL_BUILD_PROGRAM_FAILURE = -11;

  CL_DEVICE_TYPE_GPU = LongWord(1 shl 2);
  CL_DEVICE_TYPE_ALL = LongWord($FFFFFFFF);

  CL_DEVICE_NAME = $102B;
  CL_DEVICE_MAX_COMPUTE_UNITS = $1002;
  CL_PROGRAM_BUILD_LOG = $1183;

  CL_MEM_READ_WRITE   = LongWord(1 shl 0);
  CL_MEM_WRITE_ONLY   = LongWord(1 shl 1);
  CL_MEM_READ_ONLY    = LongWord(1 shl 2);
  CL_MEM_COPY_HOST_PTR = LongWord(1 shl 5);

  CL_TRUE = 1;
  CL_FALSE = 0;

type
  cl_int = LongInt;
  Pcl_int = ^cl_int;
  cl_uint = LongWord;
  Pcl_uint = ^cl_uint;
  cl_ulong = UInt64;
  cl_bitfield = UInt64;

  // Every OpenCL "object" (platform/device/context/queue/mem/program/
  // kernel/event) is an opaque handle - a bare Pointer in every real
  // implementation, confirmed by the probe's own successful round trip
  // (context/queue/buffer handles created, passed back into later calls,
  // and released, all without needing any structure behind them here).
  cl_platform_id = Pointer;
  Pcl_platform_id = ^cl_platform_id;
  cl_device_id = Pointer;
  Pcl_device_id = ^cl_device_id;
  cl_context = Pointer;
  cl_command_queue = Pointer;
  cl_mem = Pointer;
  cl_program = Pointer;
  cl_kernel = Pointer;
  cl_event = Pointer;

  cl_device_type = cl_bitfield;
  cl_mem_flags = cl_bitfield;
  cl_command_queue_properties = cl_bitfield;

  // ---- clFFT ----
  clfftStatus = LongInt;   // CLFFT_SUCCESS = CL_SUCCESS = 0; negative/positive codes otherwise - see clFFT.h
  clfftDim = (CLFFT_1D = 1, CLFFT_2D = 2, CLFFT_3D = 3);
  clfftLayout = (CLFFT_COMPLEX_INTERLEAVED = 1, CLFFT_COMPLEX_PLANAR = 2,
    CLFFT_HERMITIAN_INTERLEAVED = 3, CLFFT_HERMITIAN_PLANAR = 4, CLFFT_REAL = 5);
  clfftPrecision = (CLFFT_SINGLE = 1, CLFFT_DOUBLE = 2, CLFFT_SINGLE_FAST = 3, CLFFT_DOUBLE_FAST = 4);
  clfftDirection = (CLFFT_FORWARD = -1, CLFFT_BACKWARD = 1);
  clfftResultLocation = (CLFFT_INPLACE = 1, CLFFT_OUTOFPLACE = 2);
  // An abstract handle to an FFT plan's state - NativeUInt (size_t in C),
  // NOT a pointer, per clFFT.h's own typedef - confirmed by the probe
  // (plan handle printed as a small integer, "1", not a pointer-sized
  // address).
  clfftPlanHandle = NativeUInt;
  PclfftPlanHandle = ^clfftPlanHandle;

// ==== OpenCL core (OpenCL.dll) ====
type
  Tcl_GetPlatformIDs = function(num_entries: cl_uint; platforms: Pcl_platform_id; num_platforms: Pcl_uint): cl_int; cdecl;
  Tcl_GetDeviceIDs = function(platform_: cl_platform_id; device_type: cl_device_type; num_entries: cl_uint;
    devices: Pcl_device_id; num_devices: Pcl_uint): cl_int; cdecl;
  Tcl_GetDeviceInfo = function(device: cl_device_id; param_name: cl_uint; param_value_size: NativeUInt;
    param_value: Pointer; param_value_size_ret: PNativeUInt): cl_int; cdecl;
  Tcl_CreateContext = function(properties: Pointer; num_devices: cl_uint; const devices: Pcl_device_id;
    pfn_notify: Pointer; user_data: Pointer; errcode_ret: Pcl_int): cl_context; cdecl;
  Tcl_CreateCommandQueue = function(context: cl_context; device: cl_device_id;
    properties: cl_command_queue_properties; errcode_ret: Pcl_int): cl_command_queue; cdecl;
  Tcl_CreateBuffer = function(context: cl_context; flags: cl_mem_flags; size: NativeUInt; host_ptr: Pointer;
    errcode_ret: Pcl_int): cl_mem; cdecl;
  Tcl_EnqueueWriteBuffer = function(command_queue: cl_command_queue; buffer: cl_mem; blocking_write: cl_uint;
    offset: NativeUInt; size: NativeUInt; ptr: Pointer; num_events_in_wait_list: cl_uint;
    const event_wait_list: Pointer; event: Pointer): cl_int; cdecl;
  Tcl_EnqueueReadBuffer = function(command_queue: cl_command_queue; buffer: cl_mem; blocking_read: cl_uint;
    offset: NativeUInt; size: NativeUInt; ptr: Pointer; num_events_in_wait_list: cl_uint;
    const event_wait_list: Pointer; event: Pointer): cl_int; cdecl;
  Tcl_EnqueueCopyBuffer = function(command_queue: cl_command_queue; src_buffer, dst_buffer: cl_mem;
    src_offset, dst_offset, size: NativeUInt; num_events_in_wait_list: cl_uint;
    const event_wait_list: Pointer; event: Pointer): cl_int; cdecl;
  Tcl_CreateProgramWithSource = function(context: cl_context; count: cl_uint; const strings: PPAnsiChar;
    const lengths: PNativeUInt; errcode_ret: Pcl_int): cl_program; cdecl;
  Tcl_BuildProgram = function(program_: cl_program; num_devices: cl_uint; const device_list: Pcl_device_id;
    const options: PAnsiChar; pfn_notify: Pointer; user_data: Pointer): cl_int; cdecl;
  Tcl_GetProgramBuildInfo = function(program_: cl_program; device: cl_device_id; param_name: cl_uint;
    param_value_size: NativeUInt; param_value: Pointer; param_value_size_ret: PNativeUInt): cl_int; cdecl;
  Tcl_CreateKernel = function(program_: cl_program; const kernel_name: PAnsiChar; errcode_ret: Pcl_int): cl_kernel; cdecl;
  Tcl_SetKernelArg = function(kernel: cl_kernel; arg_index: cl_uint; arg_size: NativeUInt;
    const arg_value: Pointer): cl_int; cdecl;
  Tcl_EnqueueNDRangeKernel = function(command_queue: cl_command_queue; kernel: cl_kernel; work_dim: cl_uint;
    const global_work_offset: PNativeUInt; const global_work_size: PNativeUInt; const local_work_size: PNativeUInt;
    num_events_in_wait_list: cl_uint; const event_wait_list: Pointer; event: Pointer): cl_int; cdecl;
  Tcl_Finish = function(command_queue: cl_command_queue): cl_int; cdecl;
  Tcl_ReleaseMemObject = function(memobj: cl_mem): cl_int; cdecl;
  Tcl_ReleaseKernel = function(kernel: cl_kernel): cl_int; cdecl;
  Tcl_ReleaseProgram = function(program_: cl_program): cl_int; cdecl;
  Tcl_ReleaseCommandQueue = function(command_queue: cl_command_queue): cl_int; cdecl;
  Tcl_ReleaseContext = function(context: cl_context): cl_int; cdecl;

var
  clGetPlatformIDs: Tcl_GetPlatformIDs;
  clGetDeviceIDs: Tcl_GetDeviceIDs;
  clGetDeviceInfo: Tcl_GetDeviceInfo;
  clCreateContext: Tcl_CreateContext;
  clCreateCommandQueue: Tcl_CreateCommandQueue;
  clCreateBuffer: Tcl_CreateBuffer;
  clEnqueueWriteBuffer: Tcl_EnqueueWriteBuffer;
  clEnqueueReadBuffer: Tcl_EnqueueReadBuffer;
  clEnqueueCopyBuffer: Tcl_EnqueueCopyBuffer;
  clCreateProgramWithSource: Tcl_CreateProgramWithSource;
  clBuildProgram: Tcl_BuildProgram;
  clGetProgramBuildInfo: Tcl_GetProgramBuildInfo;
  clCreateKernel: Tcl_CreateKernel;
  clSetKernelArg: Tcl_SetKernelArg;
  clEnqueueNDRangeKernel: Tcl_EnqueueNDRangeKernel;
  clFinish: Tcl_Finish;
  clReleaseMemObject: Tcl_ReleaseMemObject;
  clReleaseKernel: Tcl_ReleaseKernel;
  clReleaseProgram: Tcl_ReleaseProgram;
  clReleaseCommandQueue: Tcl_ReleaseCommandQueue;
  clReleaseContext: Tcl_ReleaseContext;

// ==== clFFT (clFFT.dll) ====
type
  TclfftSetup = function(setupData: Pointer): clfftStatus; cdecl;
  TclfftTeardown = function(): clfftStatus; cdecl;
  TclfftCreateDefaultPlan = function(plHandle: PclfftPlanHandle; context: cl_context; dim: clfftDim;
    const clLengths: PNativeUInt): clfftStatus; cdecl;
  TclfftSetPlanPrecision = function(plHandle: clfftPlanHandle; precision: clfftPrecision): clfftStatus; cdecl;
  TclfftSetLayout = function(plHandle: clfftPlanHandle; iLayout, oLayout: clfftLayout): clfftStatus; cdecl;
  TclfftSetResultLocation = function(plHandle: clfftPlanHandle; placeness: clfftResultLocation): clfftStatus; cdecl;
  TclfftBakePlan = function(plHandle: clfftPlanHandle; numQueues: cl_uint; const commQueueFFT: Pointer;
    pfn_notify: Pointer; user_data: Pointer): clfftStatus; cdecl;
  TclfftEnqueueTransform = function(plHandle: clfftPlanHandle; dir: clfftDirection; numQueuesAndEvents: cl_uint;
    const commQueues: Pointer; numWaitEvents: cl_uint; const waitEvents: Pointer; outEvents: Pointer;
    const inputBuffers: Pointer; const outputBuffers: Pointer; tmpBuffer: cl_mem): clfftStatus; cdecl;
  TclfftDestroyPlan = function(plHandle: PclfftPlanHandle): clfftStatus; cdecl;
  // Queries the scratch buffer a baked plan needs for its transform (0 if
  // none) - see newVMCL.pas's own plan-cache comment for why this is
  // queried once per cached plan and the result handed to
  // clfftEnqueueTransform's own tmpBuffer argument, rather than always
  // passing nil the way this unit's FFT()/IFFT() did originally.
  // Deliberately NOT added to LoadOpenCLAPI's required-symbols check
  // (Result :=...and Assigned(...) below): older clFFT builds that lack
  // it should still work exactly as before (tmp buffer simply never
  // provided, same as prior behaviour), not fail to load altogether.
  TclfftGetTmpBufSize = function(plHandle: clfftPlanHandle; buffersize: PNativeUInt): clfftStatus; cdecl;

var
  clfftSetup: TclfftSetup;
  clfftTeardown: TclfftTeardown;
  clfftCreateDefaultPlan: TclfftCreateDefaultPlan;
  clfftSetPlanPrecision: TclfftSetPlanPrecision;
  clfftSetLayout: TclfftSetLayout;
  clfftSetResultLocation: TclfftSetResultLocation;
  clfftBakePlan: TclfftBakePlan;
  clfftEnqueueTransform: TclfftEnqueueTransform;
  clfftDestroyPlan: TclfftDestroyPlan;
  clfftGetTmpBufSize: TclfftGetTmpBufSize;

  OpenCLAPILoaded: Boolean = False;   // True iff both OpenCL.dll and clFFT.dll loaded and every symbol resolved

// Creates a context+queue on the first available GPU device (falling back
// to any device type if no GPU is found), and runs clfftSetup - the
// one-time process-wide state every TVMobjCL needs. Idempotent: a second
// call is a no-op that returns the already-created context/queue. Called
// lazily from newVMCL.pas's own TVMobjCL.Create rather than requiring an
// explicit call site, mirroring cblas.pas's InitializeCblas/TryInitializeCBLAS
// self-contained pattern rather than OneAPI.pas's (which relies on MKL/IPP
// self-initialising) - OpenCL has no such auto-init, so this unit provides
// it directly instead of pushing that responsibility onto every caller.
function InitializeOpenCLContext(out Ctx: cl_context; out Queue: cl_command_queue;
  out Device: cl_device_id; out ErrMsg: string): Boolean;

implementation

var
  OpenCLHandle: TLibHandle = NilHandle;
  clFFTHandle: TLibHandle = NilHandle;

function LoadCLProc(Lib: TLibHandle; const Name: string): Pointer;
begin
  Result := GetProcedureAddress(Lib, Name);
end;

function LoadOpenCLAPI: Boolean;
begin
  OpenCLHandle := LoadLibrary(OpenCLLibName);
  if OpenCLHandle = NilHandle then begin
    Result := False;
    Exit;
  end;

  clFFTHandle := LoadLibrary(clFFTLibName);
  if (clFFTHandle = NilHandle) and (clFFTLibFallbackPath <> '') then
    clFFTHandle := LoadLibrary(clFFTLibFallbackPath);
  if (clFFTHandle = NilHandle) and (clFFTLibFallbackPath2 <> '') then
    clFFTHandle := LoadLibrary(clFFTLibFallbackPath2);
  if clFFTHandle = NilHandle then begin
    Result := False;
    Exit;
  end;

  Pointer(clGetPlatformIDs)         := LoadCLProc(OpenCLHandle, 'clGetPlatformIDs');
  Pointer(clGetDeviceIDs)           := LoadCLProc(OpenCLHandle, 'clGetDeviceIDs');
  Pointer(clGetDeviceInfo)          := LoadCLProc(OpenCLHandle, 'clGetDeviceInfo');
  Pointer(clCreateContext)          := LoadCLProc(OpenCLHandle, 'clCreateContext');
  Pointer(clCreateCommandQueue)     := LoadCLProc(OpenCLHandle, 'clCreateCommandQueue');
  Pointer(clCreateBuffer)           := LoadCLProc(OpenCLHandle, 'clCreateBuffer');
  Pointer(clEnqueueWriteBuffer)     := LoadCLProc(OpenCLHandle, 'clEnqueueWriteBuffer');
  Pointer(clEnqueueReadBuffer)      := LoadCLProc(OpenCLHandle, 'clEnqueueReadBuffer');
  Pointer(clEnqueueCopyBuffer)      := LoadCLProc(OpenCLHandle, 'clEnqueueCopyBuffer');
  Pointer(clCreateProgramWithSource):= LoadCLProc(OpenCLHandle, 'clCreateProgramWithSource');
  Pointer(clBuildProgram)           := LoadCLProc(OpenCLHandle, 'clBuildProgram');
  Pointer(clGetProgramBuildInfo)    := LoadCLProc(OpenCLHandle, 'clGetProgramBuildInfo');
  Pointer(clCreateKernel)           := LoadCLProc(OpenCLHandle, 'clCreateKernel');
  Pointer(clSetKernelArg)           := LoadCLProc(OpenCLHandle, 'clSetKernelArg');
  Pointer(clEnqueueNDRangeKernel)   := LoadCLProc(OpenCLHandle, 'clEnqueueNDRangeKernel');
  Pointer(clFinish)                 := LoadCLProc(OpenCLHandle, 'clFinish');
  Pointer(clReleaseMemObject)       := LoadCLProc(OpenCLHandle, 'clReleaseMemObject');
  Pointer(clReleaseKernel)          := LoadCLProc(OpenCLHandle, 'clReleaseKernel');
  Pointer(clReleaseProgram)         := LoadCLProc(OpenCLHandle, 'clReleaseProgram');
  Pointer(clReleaseCommandQueue)    := LoadCLProc(OpenCLHandle, 'clReleaseCommandQueue');
  Pointer(clReleaseContext)         := LoadCLProc(OpenCLHandle, 'clReleaseContext');

  // clfftInitSetupData deliberately NOT resolved/called - see this unit's
  // own header comment for why (not exported by this machine's clFFT.dll
  // build, and not required - clfftSetup(nil) works without it).
  Pointer(clfftSetup)               := LoadCLProc(clFFTHandle, 'clfftSetup');
  Pointer(clfftTeardown)            := LoadCLProc(clFFTHandle, 'clfftTeardown');
  Pointer(clfftCreateDefaultPlan)   := LoadCLProc(clFFTHandle, 'clfftCreateDefaultPlan');
  Pointer(clfftSetPlanPrecision)    := LoadCLProc(clFFTHandle, 'clfftSetPlanPrecision');
  Pointer(clfftSetLayout)           := LoadCLProc(clFFTHandle, 'clfftSetLayout');
  Pointer(clfftSetResultLocation)   := LoadCLProc(clFFTHandle, 'clfftSetResultLocation');
  Pointer(clfftBakePlan)            := LoadCLProc(clFFTHandle, 'clfftBakePlan');
  Pointer(clfftEnqueueTransform)    := LoadCLProc(clFFTHandle, 'clfftEnqueueTransform');
  Pointer(clfftDestroyPlan)         := LoadCLProc(clFFTHandle, 'clfftDestroyPlan');
  Pointer(clfftGetTmpBufSize)       := LoadCLProc(clFFTHandle, 'clfftGetTmpBufSize');

  Result := Assigned(clGetPlatformIDs) and Assigned(clCreateContext) and Assigned(clfftSetup)
    and Assigned(clfftEnqueueTransform);
end;

function InitializeOpenCLContext(out Ctx: cl_context; out Queue: cl_command_queue;
  out Device: cl_device_id; out ErrMsg: string): Boolean;
var
  Platforms: array of cl_platform_id;
  PlatDevices: array of cl_device_id;
  NumPlatforms, NumDevices, CU: cl_uint;
  BestCU: cl_uint;
  BestDevice: cl_device_id;
  Sz: NativeUInt;
  p, d : Integer;
  Err: cl_int;
  Status: clfftStatus;
begin
  Result := False;
  Ctx := nil;
  Queue := nil;
  Device := nil;

  if not OpenCLAPILoaded then begin
    ErrMsg := 'OpenCL/clFFT runtime libraries not found (' + OpenCLLibName + ' / ' + clFFTLibName + ')';
    Exit;
  end;

  NumPlatforms := 0;
  if (clGetPlatformIDs(0, nil, @NumPlatforms) <> CL_SUCCESS) or (NumPlatforms = 0) then begin
    ErrMsg := 'no OpenCL platform found';
    Exit;
  end;
  SetLength(Platforms, NumPlatforms);
  if clGetPlatformIDs(NumPlatforms, @Platforms[0], nil) <> CL_SUCCESS then begin
    ErrMsg := 'clGetPlatformIDs failed';
    Exit;
  end;

  // A machine can expose more than one OpenCL platform at once (e.g. an
  // Intel iGPU platform alongside a discrete NVIDIA/AMD one) - taking
  // simply the FIRST platform clGetPlatformIDs happens to report (this
  // function's original behaviour) silently picked whichever the ICD
  // loader lists first, which on this project's own dev machine turned
  // out to be the much weaker integrated Intel UHD Graphics (16 compute
  // units) instead of the discrete NVIDIA GPU sitting right next to it
  // (36 compute units) - confirmed via a standalone clGetDeviceInfo probe
  // before this fix. So: scan every platform's GPU device(s) and keep the
  // one reporting the highest CL_DEVICE_MAX_COMPUTE_UNITS - a simple,
  // portable proxy for "biggest/most powerful GPU available" that needs no
  // vendor-name special-casing and naturally favours a discrete GPU over
  // an integrated one in the common case. Falls back to CL_DEVICE_TYPE_ALL
  // on the first platform (this function's original fallback) only if NO
  // platform exposes a GPU device at all.
  BestDevice := nil;
  BestCU := 0;
  for p := 0 to NumPlatforms-1 do begin
    NumDevices := 0;
    if (clGetDeviceIDs(Platforms[p], CL_DEVICE_TYPE_GPU, 0, nil, @NumDevices) <> CL_SUCCESS)
      or (NumDevices = 0) then Continue;
    SetLength(PlatDevices, NumDevices);
    if clGetDeviceIDs(Platforms[p], CL_DEVICE_TYPE_GPU, NumDevices, @PlatDevices[0], nil) <> CL_SUCCESS then Continue;
    for d := 0 to NumDevices-1 do begin
      CU := 0;
      if (clGetDeviceInfo(PlatDevices[d], CL_DEVICE_MAX_COMPUTE_UNITS, SizeOf(CU), @CU, @Sz) = CL_SUCCESS)
        and ((BestDevice = nil) or (CU > BestCU)) then begin
        BestDevice := PlatDevices[d];
        BestCU := CU;
      end;
    end;
  end;

  if BestDevice <> nil then
    Device := BestDevice
  else begin
    // No GPU device found on any platform - fall back to whatever the
    // first platform offers (e.g. a CPU OpenCL implementation) rather
    // than failing outright - still correct, just not accelerated.
    NumDevices := 0;
    if (clGetDeviceIDs(Platforms[0], CL_DEVICE_TYPE_ALL, 0, nil, @NumDevices) <> CL_SUCCESS) or (NumDevices = 0) then begin
      ErrMsg := 'no OpenCL device found on any platform';
      Exit;
    end;
    if clGetDeviceIDs(Platforms[0], CL_DEVICE_TYPE_ALL, 1, @Device, nil) <> CL_SUCCESS then begin
      ErrMsg := 'clGetDeviceIDs failed';
      Exit;
    end;
  end;

  Err := 0;
  Ctx := clCreateContext(nil, 1, @Device, nil, nil, @Err);
  if (Err <> CL_SUCCESS) or not Assigned(Ctx) then begin
    ErrMsg := 'clCreateContext failed with code ' + IntToStr(Err);
    Exit;
  end;

  Err := 0;
  Queue := clCreateCommandQueue(Ctx, Device, 0, @Err);
  if (Err <> CL_SUCCESS) or not Assigned(Queue) then begin
    ErrMsg := 'clCreateCommandQueue failed with code ' + IntToStr(Err);
    clReleaseContext(Ctx);
    Ctx := nil;
    Exit;
  end;

  Status := clfftSetup(nil);
  if Status <> CL_SUCCESS then begin
    ErrMsg := 'clfftSetup failed with code ' + IntToStr(Status);
    clReleaseCommandQueue(Queue);
    clReleaseContext(Ctx);
    Ctx := nil;
    Queue := nil;
    Exit;
  end;

  Result := True;
end;

initialization
  OpenCLAPILoaded := LoadOpenCLAPI;

finalization
  if OpenCLAPILoaded then clfftTeardown();
  if clFFTHandle <> NilHandle then UnloadLibrary(clFFTHandle);
  if OpenCLHandle <> NilHandle then UnloadLibrary(OpenCLHandle);

end.
