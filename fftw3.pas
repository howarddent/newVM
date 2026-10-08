unit fftw3;

{*******************************************************************************

     Runtime (dlopen-based) bindings to FFTW3, double precision (libfftw3,
     "fftw_" prefix) and single precision (libfftw3f, "fftwf_" prefix).

     WHY DLOPEN INSTEAD OF LINK-TIME EXTERNAL:
     On this development machine libfftw3 (double) only exists as a static
     .a in /usr/local/lib (from a manual source build), while libfftw3f
     (single) and libfftw3l (long double) are only installed as versioned
     runtime .so.3 files via the distro's apt packages (libfftw3-single3
     etc.) - there is no -dev package, so no unversioned libfftw3f.so
     symlink exists for a plain "external 'fftw3f';" link-time declaration
     to find. Rather than depend on a particular machine's package layout,
     this unit follows the same runtime-loading pattern cblas.pas already
     uses for OpenBLAS: LoadLibrary/GetProcedureAddress against the exact
     versioned .so name, resolved once via InitializeFFTW3. This works
     regardless of whether a -dev package is installed.

     Only the subset of the FFTW3 API newVM*.pas need is bound: 1D r2r
     (DCT/DST kinds I-IV), 1D r2c/c2r, and 1D c2c (dft) plan/execute/
     destroy, for both precisions.

     PLAN CACHE (CachedPlanD/CachedPlanF): plan once per size, then just
     execute. Building an FFTW plan is far more expensive than running
     one, and every newVM*.pas FFT/DCT/DST wrapper used to build and
     destroy a fresh plan on every call - for a caller transforming the
     same length over and over (a live spectrum display, one FFT per IQ
     epoch) that was planning cost on every single epoch, for a plan that
     was identical each time. These two functions return a plan for a
     given (transform, length[, r2r kind]), building it only the first
     time that combination is asked for and handing back the same plan
     ever after - so a new plan is made exactly when the length changes
     (e.g. a new epoch size) and never otherwise. Plans are executed with
     FFTW's new-array execute functions on the caller's own buffers.

     Two things make that reuse safe:
       - Alignment. FFTW only guarantees a plan executed on arrays other
         than the ones it was planned with if the new arrays have the same
         alignment class (fftw_alignment_of) as the originals - its SIMD
         kernels depend on it. So the alignment class of the caller's
         input and output buffers is part of the cache key, and each plan
         is built on the caller's own buffers (FFTW_ESTIMATE never reads
         or writes them while planning). In practice FPC's dynamic arrays
         all come out 16-byte aligned, so this is one plan per size; an
         oddly-aligned buffer just gets a second plan of its own rather
         than a crash. FFTW_UNALIGNED, the other way to make reuse safe,
         was measured here and rejected: it switches the SIMD kernels off
         and executes 2-3x slower (2048 points: 11.4 vs 3.6 us; 8192: 68
         vs 26.5 us) - several times what re-planning ever cost, since an
         ESTIMATE re-plan of a size FFTW has already seen is only ~3-6 us.
         Plans are out-of-place and must be executed out-of-place
         (distinct input and output buffers), as every wrapper does. If a
         library predates fftw_alignment_of (FFTW < 3.3), the cache falls
         back to FFTW_UNALIGNED plans: slower, but still correct.
       - A lock per library around lookup and planning. FFTW's planner
         shares global state and is not thread-safe; executing an
         existing plan is, so only the (rare) plan-building path needs
         serialising. The lock is per LIBRARY, not per newVM unit:
         newVM.pas and newVMComplex.pas both plan through libfftw3, so
         two unit-local locks (which is how newVM.pas's DCT/DST cache
         first did it) would not have stopped them planning concurrently.

     Cached plans are never destroyed: the distinct sizes in use are
     bounded by the calling code, not by how often it calls, and the
     libraries themselves are never fftw_cleanup()'d either.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, OneAPI;

const
  FFTW_FORWARD  = -1;
  FFTW_BACKWARD = 1;

  FFTW_MEASURE        = 0;
  FFTW_DESTROY_INPUT  = 1;   {1U << 0}
  FFTW_UNALIGNED      = 2;   {1U << 1}
  FFTW_PRESERVE_INPUT = 16;  {1U << 4 - cancels FFTW_DESTROY_INPUT}
  FFTW_ESTIMATE       = 64;  {1U << 6}

{$IFDEF WINDOWS}
  FFTWDoubleLib = 'libfftw3-3.dll';
  FFTWSingleLib = 'libfftw3f-3.dll';
{$ELSE}
  {$IFDEF DARWIN}
  FFTWDoubleLib = 'libfftw3.dylib';
  FFTWSingleLib = 'libfftw3f.dylib';
  {$ELSE}
  FFTWDoubleLib = 'libfftw3.so.3';
  FFTWSingleLib = 'libfftw3f.so.3';
  {$ENDIF}
{$ENDIF}

type
  {$MINENUMSIZE 4}  //must match FFTW's C enum size for both precisions
  TFFTW_r2r_kind = (
    FFTW_R2HC=0, FFTW_HC2R=1, FFTW_DHT=2,
    FFTW_REDFT00=3, FFTW_REDFT01=4, FFTW_REDFT10=5, FFTW_REDFT11=6,   //DCT I..IV
    FFTW_RODFT00=7, FFTW_RODFT01=8, FFTW_RODFT10=9, FFTW_RODFT11=10   //DST I..IV
  );

  fftw_plan = Pointer;

  //--- double precision ("fftw_") ---
  Tfftw_plan_r2r_1d = function(n: Integer; inD, outD: PDouble;
    kind: TFFTW_r2r_kind; flags: LongWord): fftw_plan; cdecl;
  Tfftw_plan_dft_r2c_1d = function(n: Integer; inD: PDouble;
    outD: PComplex16; flags: LongWord): fftw_plan; cdecl;
  Tfftw_plan_dft_c2r_1d = function(n: Integer; inD: PComplex16;
    outD: PDouble; flags: LongWord): fftw_plan; cdecl;
  Tfftw_plan_dft_1d = function(n: Integer; inD, outD: PComplex16;
    sign: Integer; flags: LongWord): fftw_plan; cdecl;
  Tfftw_execute_r2r = procedure(plan: fftw_plan; inD, outD: PDouble); cdecl;
  Tfftw_execute_dft_r2c = procedure(plan: fftw_plan; inD: PDouble; outD: PComplex16); cdecl;
  Tfftw_execute_dft_c2r = procedure(plan: fftw_plan; inD: PComplex16; outD: PDouble); cdecl;
  Tfftw_execute_dft = procedure(plan: fftw_plan; inD, outD: PComplex16); cdecl;
  Tfftw_destroy_plan = procedure(plan: fftw_plan); cdecl;
  Tfftw_alignment_of = function(p: Pointer): Integer; cdecl;

  //--- single precision ("fftwf_") ---
  Tfftwf_plan_r2r_1d = function(n: Integer; inD, outD: PSingle;
    kind: TFFTW_r2r_kind; flags: LongWord): fftw_plan; cdecl;
  Tfftwf_plan_dft_r2c_1d = function(n: Integer; inD: PSingle;
    outD: PComplex8; flags: LongWord): fftw_plan; cdecl;
  Tfftwf_plan_dft_c2r_1d = function(n: Integer; inD: PComplex8;
    outD: PSingle; flags: LongWord): fftw_plan; cdecl;
  Tfftwf_plan_dft_1d = function(n: Integer; inD, outD: PComplex8;
    sign: Integer; flags: LongWord): fftw_plan; cdecl;
  Tfftwf_execute_r2r = procedure(plan: fftw_plan; inD, outD: PSingle); cdecl;
  Tfftwf_execute_dft_r2c = procedure(plan: fftw_plan; inD: PSingle; outD: PComplex8); cdecl;
  Tfftwf_execute_dft_c2r = procedure(plan: fftw_plan; inD: PComplex8; outD: PSingle); cdecl;
  Tfftwf_execute_dft = procedure(plan: fftw_plan; inD, outD: PComplex8); cdecl;
  Tfftwf_destroy_plan = procedure(plan: fftw_plan); cdecl;

var
  //double precision entry points - Nil until InitializeFFTW3 loads FFTWDoubleLib
  fftw_plan_r2r_1d: Tfftw_plan_r2r_1d;
  fftw_plan_dft_r2c_1d: Tfftw_plan_dft_r2c_1d;
  fftw_plan_dft_c2r_1d: Tfftw_plan_dft_c2r_1d;
  fftw_plan_dft_1d: Tfftw_plan_dft_1d;
  fftw_execute_r2r: Tfftw_execute_r2r;
  fftw_execute_dft_r2c: Tfftw_execute_dft_r2c;
  fftw_execute_dft_c2r: Tfftw_execute_dft_c2r;
  fftw_execute_dft: Tfftw_execute_dft;
  fftw_destroy_plan: Tfftw_destroy_plan;
  fftw_alignment_of: Tfftw_alignment_of;

  //single precision entry points - Nil until InitializeFFTW3 loads FFTWSingleLib
  fftwf_plan_r2r_1d: Tfftwf_plan_r2r_1d;
  fftwf_plan_dft_r2c_1d: Tfftwf_plan_dft_r2c_1d;
  fftwf_plan_dft_c2r_1d: Tfftwf_plan_dft_c2r_1d;
  fftwf_plan_dft_1d: Tfftwf_plan_dft_1d;
  fftwf_execute_r2r: Tfftwf_execute_r2r;
  fftwf_execute_dft_r2c: Tfftwf_execute_dft_r2c;
  fftwf_execute_dft_c2r: Tfftwf_execute_dft_c2r;
  fftwf_execute_dft: Tfftwf_execute_dft;
  fftwf_destroy_plan: Tfftwf_destroy_plan;
  fftwf_alignment_of: Tfftw_alignment_of;

type
  TFFTWTransform = (ftR2R, ftDFTForward, ftDFTBackward, ftR2C, ftC2R);

{ See PLAN CACHE in the header. N is the transform length (for ftR2C/ftC2R
  the REAL length - the complex side is N div 2 + 1). InP/OutP are the
  buffers the caller is about to execute the plan on - distinct (out-of-
  place) - used for their alignment class and, the first time, planned
  against directly. Kind is used only for ftR2R. Asserts if the library
  for that precision isn't loaded. }
function CachedPlanD(Transform: TFFTWTransform; N: Integer; InP, OutP: Pointer;
  Kind: TFFTW_r2r_kind = FFTW_R2HC): fftw_plan;
function CachedPlanF(Transform: TFFTWTransform; N: Integer; InP, OutP: Pointer;
  Kind: TFFTW_r2r_kind = FFTW_R2HC): fftw_plan;

{ Loads both libraries and resolves every entry point above. Safe to call
  more than once (a precision already loaded is left alone). Returns True
  iff both libraries loaded; a caller only needing one precision may still
  proceed on a partial False result - each newVM* wrapper asserts that its
  own precision's function pointers are actually Assigned before use. }
function InitializeFFTW3: Boolean;

implementation

type
  TPlanCacheEntry = record
    Transform: TFFTWTransform;
    N: Integer;
    Kind: TFFTW_r2r_kind;
    InAlign, OutAlign: Integer;   // fftw_alignment_of, or -1 for an FFTW_UNALIGNED plan
    Plan: fftw_plan;
  end;
  TPlanCache = array of TPlanCacheEntry;

var
  FFTWDoubleHandle: TLibHandle = NilHandle;
  FFTWSingleHandle: TLibHandle = NilHandle;
  PlanLockD, PlanLockF: TRTLCriticalSection;
  PlanCacheD, PlanCacheF: TPlanCache;

function FindPlan(const Cache: TPlanCache; Transform: TFFTWTransform; N: Integer;
  Kind: TFFTW_r2r_kind; InAlign, OutAlign: Integer; out Plan: fftw_plan): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(Cache) do
    if (Cache[i].Transform = Transform) and (Cache[i].N = N) and
       ((Transform <> ftR2R) or (Cache[i].Kind = Kind)) and
       (Cache[i].InAlign = InAlign) and (Cache[i].OutAlign = OutAlign) then begin
      Plan := Cache[i].Plan;
      Exit(True);
    end;
  Result := False;
end;

procedure AddPlan(var Cache: TPlanCache; Transform: TFFTWTransform; N: Integer;
  Kind: TFFTW_r2r_kind; InAlign, OutAlign: Integer; Plan: fftw_plan);
begin
  SetLength(Cache, Length(Cache) + 1);
  Cache[High(Cache)].Transform := Transform;
  Cache[High(Cache)].N := N;
  Cache[High(Cache)].Kind := Kind;
  Cache[High(Cache)].InAlign := InAlign;
  Cache[High(Cache)].OutAlign := OutAlign;
  Cache[High(Cache)].Plan := Plan;
end;

function CachedPlanD(Transform: TFFTWTransform; N: Integer; InP, OutP: Pointer;
  Kind: TFFTW_r2r_kind): fftw_plan;
const
  s = 'fftw3 CachedPlanD : ';
var
  InAlign, OutAlign: Integer;
  Flags: LongWord;
begin
  assert(N > 0, s + 'N must be positive');
  assert(Assigned(fftw_plan_dft_1d), s + 'FFTW3 (double) library not loaded');
  assert(InP <> OutP, s + 'cached plans are out-of-place only');
  Flags := FFTW_ESTIMATE or FFTW_PRESERVE_INPUT;
  if Assigned(fftw_alignment_of) then begin
    InAlign := fftw_alignment_of(InP);
    OutAlign := fftw_alignment_of(OutP);
  end else begin
    InAlign := -1; OutAlign := -1;
    Flags := Flags or FFTW_UNALIGNED;
  end;
  EnterCriticalSection(PlanLockD);
  try
    if FindPlan(PlanCacheD, Transform, N, Kind, InAlign, OutAlign, Result) then Exit;
    case Transform of
      ftR2R:         Result := fftw_plan_r2r_1d(N, InP, OutP, Kind, Flags);
      ftDFTForward:  Result := fftw_plan_dft_1d(N, InP, OutP, FFTW_FORWARD, Flags);
      ftDFTBackward: Result := fftw_plan_dft_1d(N, InP, OutP, FFTW_BACKWARD, Flags);
      ftR2C:         Result := fftw_plan_dft_r2c_1d(N, InP, OutP, Flags);
      ftC2R:         Result := fftw_plan_dft_c2r_1d(N, InP, OutP, Flags);
    end;
    assert(Result <> nil, s + 'FFTW planning failed');
    AddPlan(PlanCacheD, Transform, N, Kind, InAlign, OutAlign, Result);
  finally
    LeaveCriticalSection(PlanLockD);
  end;
end;

function CachedPlanF(Transform: TFFTWTransform; N: Integer; InP, OutP: Pointer;
  Kind: TFFTW_r2r_kind): fftw_plan;
const
  s = 'fftw3 CachedPlanF : ';
var
  InAlign, OutAlign: Integer;
  Flags: LongWord;
begin
  assert(N > 0, s + 'N must be positive');
  assert(Assigned(fftwf_plan_dft_1d), s + 'FFTW3 (single) library not loaded');
  assert(InP <> OutP, s + 'cached plans are out-of-place only');
  Flags := FFTW_ESTIMATE or FFTW_PRESERVE_INPUT;
  if Assigned(fftwf_alignment_of) then begin
    InAlign := fftwf_alignment_of(InP);
    OutAlign := fftwf_alignment_of(OutP);
  end else begin
    InAlign := -1; OutAlign := -1;
    Flags := Flags or FFTW_UNALIGNED;
  end;
  EnterCriticalSection(PlanLockF);
  try
    if FindPlan(PlanCacheF, Transform, N, Kind, InAlign, OutAlign, Result) then Exit;
    case Transform of
      ftR2R:         Result := fftwf_plan_r2r_1d(N, InP, OutP, Kind, Flags);
      ftDFTForward:  Result := fftwf_plan_dft_1d(N, InP, OutP, FFTW_FORWARD, Flags);
      ftDFTBackward: Result := fftwf_plan_dft_1d(N, InP, OutP, FFTW_BACKWARD, Flags);
      ftR2C:         Result := fftwf_plan_dft_r2c_1d(N, InP, OutP, Flags);
      ftC2R:         Result := fftwf_plan_dft_c2r_1d(N, InP, OutP, Flags);
    end;
    assert(Result <> nil, s + 'FFTW planning failed');
    AddPlan(PlanCacheF, Transform, N, Kind, InAlign, OutAlign, Result);
  finally
    LeaveCriticalSection(PlanLockF);
  end;
end;

procedure LoadFFTWDoubleAddresses(LibHandle: TLibHandle);
begin
  pointer(fftw_plan_r2r_1d)      := GetProcedureAddress(LibHandle, 'fftw_plan_r2r_1d');
  pointer(fftw_plan_dft_r2c_1d)  := GetProcedureAddress(LibHandle, 'fftw_plan_dft_r2c_1d');
  pointer(fftw_plan_dft_c2r_1d)  := GetProcedureAddress(LibHandle, 'fftw_plan_dft_c2r_1d');
  pointer(fftw_plan_dft_1d)      := GetProcedureAddress(LibHandle, 'fftw_plan_dft_1d');
  pointer(fftw_execute_r2r)      := GetProcedureAddress(LibHandle, 'fftw_execute_r2r');
  pointer(fftw_execute_dft_r2c)  := GetProcedureAddress(LibHandle, 'fftw_execute_dft_r2c');
  pointer(fftw_execute_dft_c2r)  := GetProcedureAddress(LibHandle, 'fftw_execute_dft_c2r');
  pointer(fftw_execute_dft)      := GetProcedureAddress(LibHandle, 'fftw_execute_dft');
  pointer(fftw_destroy_plan)     := GetProcedureAddress(LibHandle, 'fftw_destroy_plan');
  pointer(fftw_alignment_of)     := GetProcedureAddress(LibHandle, 'fftw_alignment_of');   // nil before FFTW 3.3
end;

procedure LoadFFTWSingleAddresses(LibHandle: TLibHandle);
begin
  pointer(fftwf_plan_r2r_1d)     := GetProcedureAddress(LibHandle, 'fftwf_plan_r2r_1d');
  pointer(fftwf_plan_dft_r2c_1d) := GetProcedureAddress(LibHandle, 'fftwf_plan_dft_r2c_1d');
  pointer(fftwf_plan_dft_c2r_1d) := GetProcedureAddress(LibHandle, 'fftwf_plan_dft_c2r_1d');
  pointer(fftwf_plan_dft_1d)     := GetProcedureAddress(LibHandle, 'fftwf_plan_dft_1d');
  pointer(fftwf_execute_r2r)     := GetProcedureAddress(LibHandle, 'fftwf_execute_r2r');
  pointer(fftwf_execute_dft_r2c) := GetProcedureAddress(LibHandle, 'fftwf_execute_dft_r2c');
  pointer(fftwf_execute_dft_c2r) := GetProcedureAddress(LibHandle, 'fftwf_execute_dft_c2r');
  pointer(fftwf_execute_dft)     := GetProcedureAddress(LibHandle, 'fftwf_execute_dft');
  pointer(fftwf_destroy_plan)    := GetProcedureAddress(LibHandle, 'fftwf_destroy_plan');
  pointer(fftwf_alignment_of)    := GetProcedureAddress(LibHandle, 'fftwf_alignment_of');
end;

function InitializeFFTW3: Boolean;
begin
  if FFTWDoubleHandle = NilHandle then begin
    FFTWDoubleHandle := LoadLibrary(FFTWDoubleLib);
    if FFTWDoubleHandle <> NilHandle then
      LoadFFTWDoubleAddresses(FFTWDoubleHandle);
  end;
  if FFTWSingleHandle = NilHandle then begin
    FFTWSingleHandle := LoadLibrary(FFTWSingleLib);
    if FFTWSingleHandle <> NilHandle then
      LoadFFTWSingleAddresses(FFTWSingleHandle);
  end;
  result := (FFTWDoubleHandle <> NilHandle) and (FFTWSingleHandle <> NilHandle);
end;

initialization
  //Auto-load on unit init (like OneAPI.pas's Windows MKL/IPP loader) rather
  //than requiring every caller to remember an explicit Initialize call, as
  //newVMtest.lpr must for InitializeCBLAS - a missing FFTW3 library is a
  //setup problem best caught once here, not per program. Callers that only
  //need one precision are unaffected by the other failing to load; each
  //newVM*.pas FFT/DCT/DST wrapper asserts its own function pointers are
  //Assigned before use, so a partial load still fails with a clear message
  //rather than a null-pointer-call crash.
  InitCriticalSection(PlanLockD);
  InitCriticalSection(PlanLockF);
  InitializeFFTW3;

finalization
  DoneCriticalSection(PlanLockD);
  DoneCriticalSection(PlanLockF);
  if FFTWDoubleHandle <> NilHandle then UnloadLibrary(FFTWDoubleHandle);
  if FFTWSingleHandle <> NilHandle then UnloadLibrary(FFTWSingleHandle);
end.
