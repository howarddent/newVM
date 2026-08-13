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

{ Loads both libraries and resolves every entry point above. Safe to call
  more than once (a precision already loaded is left alone). Returns True
  iff both libraries loaded; a caller only needing one precision may still
  proceed on a partial False result - each newVM* wrapper asserts that its
  own precision's function pointers are actually Assigned before use. }
function InitializeFFTW3: Boolean;

implementation

var
  FFTWDoubleHandle: TLibHandle = NilHandle;
  FFTWSingleHandle: TLibHandle = NilHandle;

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
  InitializeFFTW3;

finalization
  if FFTWDoubleHandle <> NilHandle then UnloadLibrary(FFTWDoubleHandle);
  if FFTWSingleHandle <> NilHandle then UnloadLibrary(FFTWSingleHandle);
end.
