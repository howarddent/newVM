program newvmconfigure;

// Build-time platform/library detector for newVM.
//
// FPC's IFDEF/Linklib directives are resolved at COMPILE time, but
// "is libmkl_rt.so actually installed on this machine" is a fact about
// the BUILD machine, not something the compiler can know on its own.
// This standalone console program bridges that gap: run it once (before
// lazbuild) on whatever machine you're about to build newVM* on, and it
// writes newVMConfig.inc - a plain DEFINE ... include file that
// newVM.pas (and, as they gain the same fallback treatment, its sibling
// units) includes at the top, gating their Linklib blocks and choosing
// between MKL/IPP/OpenBLAS-backed and plain-Pascal implementations.
//
// Detection has two halves:
//   - OS and CPU architecture: free at compile time via FPC's own
//     built-in macros (WINDOWS/LINUX/DARWIN, CPUX86_64/CPUAARCH64/...) -
//     this tool just relays them into PLATFORM_* defines so the
//     generated include file documents what it was generated for.
//   - Library presence: NOT knowable at compile time, so this probes at
//     RUNTIME via LoadLibrary (DynLibs), the exact same "try to dlopen
//     it, see if it works" technique cblas.pas already uses for OpenBLAS
//     (TryInitializeCBLAS/LoadAddresses) and fftw3.pas uses for FFTW -
//     just done once here, ahead of the real build, rather than every
//     time the built program starts.
//
// This program deliberately has no dependency on cblas.pas/OneAPI.pas/
// fftw3.pas/newVM*.pas themselves (only SysUtils/DynLibs) - it has to be
// buildable and runnable on a machine that might have NONE of MKL/IPP/
// OpenBLAS/FFTW installed, which rules out anything that links
// against them.
//
// Usage:
//   fpc newvmconfigure.lpr          (one-off compile; no MKL/IPP/
//                                     OpenBLAS/FFTW needed to build this
//                                     tool itself)
//   ./newvmconfigure                (writes newVMConfig.inc into the
//                                     current directory - run this from
//                                     the repo root)
//   lazbuild --lazarusdir=<path> newVMtest.lpi   (as before)
//
// Re-run ./newvmconfigure whenever you build on a different machine, or
// after installing/removing MKL/IPP/OpenBLAS/FFTW on this one - it is a
// snapshot of the machine it ran on, not a portability guarantee.

{$mode objfpc}{$H+}

uses
  SysUtils, StrUtils, DynLibs;

{$IFDEF WINDOWS}
const
  PlatformDefine = 'PLATFORM_WINDOWS';
  MKLCandidates: array of string = ('mkl_rt.dll','mkl_rt.1.dll','mkl_rt.2.dll',
    'mkl_rt.3.dll','mkl_rt.4.dll','mkl_rt.5.dll','mkl_rt.6.dll','mkl_rt.7.dll',
    'mkl_rt.8.dll','mkl_rt.9.dll','mkl_rt.10.dll');
  IPPCoreCandidates: array of string = ('ippcore.dll');
  IPPVMCandidates: array of string = ('ippvm.dll');
  IPPSCandidates: array of string = ('ipps.dll');
  OpenBLASCandidates: array of string = ('openblas.dll');
  FFTWDoubleCandidates: array of string = ('libfftw3-3.dll');
  FFTWSingleCandidates: array of string = ('libfftw3f-3.dll');
  AccelerateCandidates: array of string = (); // Darwin-only framework
  // ArmPL's Windows DLL naming hasn't been confirmed against a real install
  // (unlike every other candidate list here) - left empty rather than
  // guessing, so HAVE_ARMPL simply never fires on Windows until someone
  // verifies and fills this in.
  ArmPLCandidates: array of string = ();
  // OpenCL.dll is a normal Windows driver-installed DLL (this machine's
  // AMD/NVIDIA GPU drivers put it in System32) - bare name only. clFFT.dll
  // has no such standard install location (there's no official installer
  // the way SDRplay's API has - see OpenCLAPI.pas's own header comment);
  // the fallback paths are confirmed-working build/install outputs across
  // the different machines this project has been built on (a self-built
  // clFFT.pas tree under user "howard", a vcpkg install under user
  // "howar") - same "bare name first, then a known location" pattern
  // uSDRplay.pas/OpenCLAPI.pas already use for their own non-standard DLLs.
  OpenCLCandidates: array of string = ('OpenCL.dll');
  clFFTCandidates: array of string = ('clFFT.dll',
    'C:\Users\howard\clFFT\src\clFFTpas\clFFT.dll',
    'C:\Users\howar\vcpkg\installed\x64-windows\bin\clFFT.dll');
  MetalCandidates: array of string = (); // Darwin-only framework
  MPSGraphCandidates: array of string = (); // Darwin-only framework
{$ELSE}
  {$IFDEF DARWIN}
const
  PlatformDefine = 'PLATFORM_DARWIN';
  MKLCandidates: array of string = ('libmkl_rt.dylib');
  IPPCoreCandidates: array of string = ('libippcore.dylib');
  IPPVMCandidates: array of string = ('libippvm.dylib');
  IPPSCandidates: array of string = ('libipps.dylib');
  OpenBLASCandidates: array of string = ('libopenblas.dylib');
  FFTWDoubleCandidates: array of string = ('libfftw3.dylib','libfftw3.3.dylib');
  FFTWSingleCandidates: array of string = ('libfftw3f.dylib','libfftw3f.3.dylib');
  // Apple's Accelerate framework ships on every Mac (no install needed) and
  // exposes a standard, symbol-compatible CBLAS interface - see cblas.pas's
  // header comment for how this gets used as a second BLAS provider
  // alongside OpenBLAS. dlopen'ing a framework by its full binary path
  // (rather than a bare library name) is the standard way to load one at
  // runtime; confirmed working on this machine even though modern macOS no
  // longer ships the actual dylib bytes on disk (they live in the dyld
  // shared cache - LoadLibrary/dlopen still resolves this path correctly,
  // only filesystem-level tools like `file`/`nm` see a broken symlink).
  AccelerateCandidates: array of string = ('/System/Library/Frameworks/Accelerate.framework/Accelerate');
  // ArmPL doesn't ship a Darwin build - left empty.
  ArmPLCandidates: array of string = ();
  // Not verified on a Darwin machine - left empty rather than guessing,
  // same rationale as ArmPLCandidates on Windows above.
  OpenCLCandidates: array of string = ();
  clFFTCandidates: array of string = ();
  // Metal and MetalPerformanceShadersGraph ship on every Mac (no install
  // needed, unlike OpenCL/clFFT above - see MetalAPI.pas's own header
  // comment for why this codebase links these at compile time rather than
  // dlopen-probing them the way OpenCL.dll/clFFT.dll needed on Windows).
  // Probed here the same way anyway (dlopen'ing the framework's full binary
  // path, same as AccelerateCandidates above), purely as a presence check -
  // this is only ever False on a Darwin machine too old to have these
  // frameworks at all (Metal: pre-10.11; the MPSGraph FFT ops MetalAPI.pas
  // uses: pre-14.0). HAVE_METAL itself is further restricted to AArch64
  // below (Apple Silicon only, matching the machine this was built/verified
  // on) even though these two frameworks alone don't require it.
  MetalCandidates: array of string = ('/System/Library/Frameworks/Metal.framework/Metal');
  MPSGraphCandidates: array of string = ('/System/Library/Frameworks/MetalPerformanceShadersGraph.framework/MetalPerformanceShadersGraph');
  {$ELSE}
const
  PlatformDefine = 'PLATFORM_LINUX';
  MKLCandidates: array of string = ('libmkl_rt.so');
  IPPCoreCandidates: array of string = ('libippcore.so');
  IPPVMCandidates: array of string = ('libippvm.so');
  IPPSCandidates: array of string = ('libipps.so');
  OpenBLASCandidates: array of string = ('libopenblas.so');
  FFTWDoubleCandidates: array of string = ('libfftw3.so','libfftw3.so.3');
  FFTWSingleCandidates: array of string = ('libfftw3f.so','libfftw3f.so.3');
  AccelerateCandidates: array of string = (); // Darwin-only framework
  // Arm Performance Libraries' LP64 (32-bit int) CBLAS+LAPACKE shared
  // library - matches this codebase's Integer/longint N/incX/incY
  // parameters the same way OpenBLAS's default build does. Confirmed
  // present under this bare name once /opt/arm/armpl_*/lib is registered
  // with the dynamic linker (see the armpl.conf ld.so.conf.d entry added
  // alongside the ArmPL install - LoadLibrary here relies on the system
  // linker search path, same as every other candidate in this file, and
  // ArmPL's own installer does not add such an entry itself).
  ArmPLCandidates: array of string = ('libarmpl_lp64.so');
  // Not verified on a Linux machine - left empty rather than guessing,
  // same rationale as ArmPLCandidates on Windows above.
  OpenCLCandidates: array of string = ();
  clFFTCandidates: array of string = ();
  MetalCandidates: array of string = (); // Darwin-only framework
  MPSGraphCandidates: array of string = (); // Darwin-only framework
  {$ENDIF}
{$ENDIF}

const
{$IFDEF CPUX86_64}
  ArchDefine = 'PLATFORM_X86_64';
{$ELSE}
  {$IFDEF CPUAARCH64}
  ArchDefine = 'PLATFORM_AARCH64';
  {$ELSE}
    {$IFDEF CPUARM}
  ArchDefine = 'PLATFORM_ARM32';
    {$ELSE}
      {$IFDEF CPUI386}
  ArchDefine = 'PLATFORM_X86';
      {$ELSE}
  ArchDefine = 'PLATFORM_UNKNOWN';
      {$ENDIF}
    {$ENDIF}
  {$ENDIF}
{$ENDIF}

{ Tries each candidate name in turn via LoadLibrary; returns True (and
  unloads again immediately - this is a probe, not a real load) on the
  first one that succeeds. Mirrors TryInitializeCBLAS's own
  LoadLibrary/success-check shape in cblas.pas, just without keeping the
  handle around afterwards. }
function ProbeLibrary(const Candidates: array of string; out FoundAs: string): Boolean;
var
  i: Integer;
  h: TLibHandle;
begin
  Result := False;
  FoundAs := '';
  for i := 0 to High(Candidates) do begin
    h := LoadLibrary(Candidates[i]);
    if h <> NilHandle then begin
      UnloadLibrary(h);
      Result := True;
      FoundAs := Candidates[i];
      Exit;
    end;
  end;
end;

var
  OutFile: TextFile;
  HaveMKL, HaveIPPCore, HaveIPPVM, HaveIPPS, HaveIPP, HaveOpenBLAS, HaveFFTWD, HaveFFTWS, HaveFFTW,
  HaveAccelerate, HaveArmPL, HaveBLAS, HaveLAPACKE, HaveOpenCLLib, HaveclFFTLib, HaveOpenCL,
  HaveMetalLib, HaveMPSGraphLib, HaveMetal: Boolean;
  FoundName: string;

  procedure Report(const Label_: string; Found: Boolean; const Via: string);
  begin
    if Found then
      WriteLn('  ', Label_, ': FOUND (', Via, ')')
    else
      WriteLn('  ', Label_, ': not found');
  end;

begin
  WriteLn('newvmconfigure: probing this machine for newVM''s optional numerical backends...');
  WriteLn('Platform: ', PlatformDefine, ' / ', ArchDefine);
  WriteLn;

  HaveMKL := ProbeLibrary(MKLCandidates, FoundName);
  Report('MKL (mkl_rt)', HaveMKL, FoundName);

  HaveIPPCore := ProbeLibrary(IPPCoreCandidates, FoundName);
  HaveIPPVM   := ProbeLibrary(IPPVMCandidates, FoundName);
  HaveIPPS    := ProbeLibrary(IPPSCandidates, FoundName);
  HaveIPP := HaveIPPCore and HaveIPPVM and HaveIPPS;
  Report('IPP (ippcore+ippvm+ipps, all three)', HaveIPP,
    Format('core=%s vm=%s s=%s', [BoolToStr(HaveIPPCore,True), BoolToStr(HaveIPPVM,True), BoolToStr(HaveIPPS,True)]));

  HaveOpenBLAS := ProbeLibrary(OpenBLASCandidates, FoundName);
  Report('OpenBLAS', HaveOpenBLAS, FoundName);

  HaveAccelerate := ProbeLibrary(AccelerateCandidates, FoundName);
  Report('Apple Accelerate (CBLAS via vecLib)', HaveAccelerate, FoundName);

  HaveArmPL := ProbeLibrary(ArmPLCandidates, FoundName);
  Report('Arm Performance Libraries (ArmPL, cblas via libarmpl_lp64)', HaveArmPL, FoundName);

  HaveBLAS := HaveOpenBLAS or HaveAccelerate or HaveArmPL;
  HaveLAPACKE := HaveMKL or HaveArmPL;

  HaveFFTWD := ProbeLibrary(FFTWDoubleCandidates, FoundName);
  HaveFFTWS := ProbeLibrary(FFTWSingleCandidates, FoundName);
  HaveFFTW := HaveFFTWD and HaveFFTWS;
  Report('FFTW3 (double+single, both)', HaveFFTW,
    Format('double=%s single=%s', [BoolToStr(HaveFFTWD,True), BoolToStr(HaveFFTWS,True)]));

  HaveOpenCLLib := ProbeLibrary(OpenCLCandidates, FoundName);
  Report('OpenCL', HaveOpenCLLib, FoundName);
  HaveclFFTLib := ProbeLibrary(clFFTCandidates, FoundName);
  Report('clFFT', HaveclFFTLib, FoundName);
  HaveOpenCL := HaveOpenCLLib and HaveclFFTLib;
  Report('OpenCL+clFFT (both, gates newVMCL.pas/TVMobjCL)', HaveOpenCL,
    Format('opencl=%s clfft=%s', [BoolToStr(HaveOpenCLLib,True), BoolToStr(HaveclFFTLib,True)]));

  HaveMetalLib := ProbeLibrary(MetalCandidates, FoundName);
  Report('Metal', HaveMetalLib, FoundName);
  HaveMPSGraphLib := ProbeLibrary(MPSGraphCandidates, FoundName);
  Report('MetalPerformanceShadersGraph', HaveMPSGraphLib, FoundName);
  // Apple Silicon only (see MetalAPI.pas's own header comment) - both
  // frameworks being present isn't itself an AArch64 signal (Intel Macs
  // have them too), so HAVE_METAL is explicitly narrowed here rather than
  // relying on MetalCandidates/MPSGraphCandidates alone.
  {$IFDEF CPUAARCH64}
  HaveMetal := HaveMetalLib and HaveMPSGraphLib;
  {$ELSE}
  HaveMetal := False;
  {$ENDIF}
  Report('Metal+MetalPerformanceShadersGraph on Apple Silicon (both, gates newVMMetal.pas/TVMobjMTL)', HaveMetal,
    Format('metal=%s mpsgraph=%s aarch64=%s', [BoolToStr(HaveMetalLib,True), BoolToStr(HaveMPSGraphLib,True),
      {$IFDEF CPUAARCH64}'True'{$ELSE}'False'{$ENDIF}]));

  WriteLn;
  WriteLn('Writing newVMConfig.inc ...');

  // NOTE: every generated line below uses '//' line comments, never a
  // '{ ... }' block comment - Pascal block comments aren't nestable, so a
  // literal '{' or '}' anywhere in the prose (e.g. naming the very
  // IFDEF PUREPASCAL directive this file drives) would silently
  // truncate the comment early and feed the rest of the sentence to the
  // compiler as code. '//' comments can't have that problem since they
  // always end at the line break regardless of their content.
  AssignFile(OutFile, 'newVMConfig.inc');
  Rewrite(OutFile);
  WriteLn(OutFile, '// newVMConfig.inc');
  WriteLn(OutFile, '// Auto-generated by newvmconfigure - DO NOT EDIT BY HAND.');
  WriteLn(OutFile, '// Regenerate with: ./newvmconfigure   (run from the repo root, on the');
  WriteLn(OutFile, '// machine you are about to build newVM* on - this is a snapshot of THIS');
  WriteLn(OutFile, '// machine''s installed libraries, not a portability guarantee for any');
  WriteLn(OutFile, '// other machine.)');
  WriteLn(OutFile, '// Generated: ', DateTimeToStr(Now));
  WriteLn(OutFile);
  WriteLn(OutFile, '{$DEFINE ', PlatformDefine, '}');
  WriteLn(OutFile, '{$DEFINE ', ArchDefine, '}');
  WriteLn(OutFile);
  if HaveOpenBLAS   then WriteLn(OutFile, '{$DEFINE HAVE_OPENBLAS}   // libopenblas found');
  if HaveAccelerate then WriteLn(OutFile, '{$DEFINE HAVE_ACCELERATE} // Apple Accelerate/vecLib found (Darwin only)');
  if HaveArmPL      then WriteLn(OutFile, '{$DEFINE HAVE_ARMPL}      // Arm Performance Libraries (libarmpl_lp64) found - cblas.pas prefers this over HAVE_OPENBLAS when both are present');
  if HaveBLAS       then WriteLn(OutFile, '{$DEFINE HAVE_BLAS}       // derived: HAVE_OPENBLAS or HAVE_ACCELERATE or HAVE_ARMPL');
  if HaveMKL        then WriteLn(OutFile, '{$DEFINE HAVE_MKL}        // libmkl_rt found');
  if HaveIPP        then WriteLn(OutFile, '{$DEFINE HAVE_IPP}        // libippcore+libippvm+libipps all found');
  if HaveFFTW       then WriteLn(OutFile, '{$DEFINE HAVE_FFTW}       // libfftw3+libfftw3f both found');
  if HaveOpenCL     then WriteLn(OutFile, '{$DEFINE HAVE_OPENCL}     // OpenCL.dll+clFFT.dll both found - gates newVMCL.pas/TVMobjCL and its test registration');
  if HaveMetal      then WriteLn(OutFile, '{$DEFINE HAVE_METAL}      // Metal+MetalPerformanceShadersGraph found on Apple Silicon - gates newVMMetal.pas/TVMobjMTL and its test registration');
  WriteLn(OutFile);
  WriteLn(OutFile, '// Derived: true when a LAPACKE_* implementation is available from EITHER');
  WriteLn(OutFile, '// MKL or Arm Performance Libraries (ArmPL exports a standard LAPACKE_* ABI');
  WriteLn(OutFile, '// from its libarmpl_lp64.so alongside its cblas_* one - see oneapi.pas''s');
  WriteLn(OutFile, '// LoadArmPLLAPACKEFunctions). Deliberately narrower than PUREPASCAL below:');
  WriteLn(OutFile, '// gates only LinearSolve/Invert/Det/Id/EigDecompose (the routines that call');
  WriteLn(OutFile, '// LAPACKE_* and nothing else) across all four TVMobj* units, so ArmPL alone');
  WriteLn(OutFile, '// (no MKL) can take those specific routines off PUREPASCAL while VML/VSL/IPP-');
  WriteLn(OutFile, '// dependent routines (Sin/Cos/etc, fillRandom, linspace/AddScalar/FlipLR/etc)');
  WriteLn(OutFile, '// stay on their PUREPASCAL fallback, since ArmPL provides no equivalent for');
  WriteLn(OutFile, '// those under matching names.');
  if HaveLAPACKE then
    WriteLn(OutFile, '{$DEFINE HAVE_LAPACKE}')
  else
    WriteLn(OutFile, '// {$DEFINE HAVE_LAPACKE} left undefined: no LAPACKE_* implementation found');
  WriteLn(OutFile);
  WriteLn(OutFile, '// Derived: set whenever any of the three libraries the "core" linear algebra');
  WriteLn(OutFile, '// (MatMult/Invert/LinearSolve/Det/operators/elementwise math/EigDecompose/etc)');
  WriteLn(OutFile, '// of all four TVMobj* units actually calls into - OpenBLAS (cblas_*), MKL');
  WriteLn(OutFile, '// (LAPACKE_*/vd*/vsl*) and IPP (ipps*) - is missing, so those routines fall');
  WriteLn(OutFile, '// back to plain Pascal implementations instead of failing to link. FFTW');
  WriteLn(OutFile, '// absence is NOT included here: it drives its own, separate HAVE_FFTW-gated');
  WriteLn(OutFile, '// fallback for DCT/DST/FFT (r2rTransform and friends, and FFT_R2C/FFT_C2R/');
  WriteLn(OutFile, '// FFT/IFFT in the complex units) instead, independent of this define - see');
  WriteLn(OutFile, '// HAVE_FFTW''s own line above.');
  if not (HaveOpenBLAS and HaveMKL and HaveIPP) then
    WriteLn(OutFile, '{$DEFINE PUREPASCAL}')
  else
    WriteLn(OutFile, '// {$DEFINE PUREPASCAL} left undefined: all three backends found');
  WriteLn(OutFile);
  WriteLn(OutFile, '// Finer-grained sibling of PUREPASCAL above, for the subset of newVM.pas''s');
  WriteLn(OutFile, '// routines (MatMult/Kron/Diag/Norm/FlipUD/MergeUD/MergeLR/Reshape/Repmat, the');
  WriteLn(OutFile, '// +/-/unary-/scalar-* operators) whose library-backed body calls ONLY');
  WriteLn(OutFile, '// cblas_* - no LAPACKE/ipps/vd*/vsl* - so they can run their real,');
  WriteLn(OutFile, '// hardware-accelerated body whenever ANY CBLAS-compatible backend (Arm');
  WriteLn(OutFile, '// Performance Libraries, OpenBLAS, or, on Darwin, Apple''s built-in Accelerate');
  WriteLn(OutFile, '// framework) is present, even on a machine missing MKL/IPP that still forces');
  WriteLn(OutFile, '// PUREPASCAL above for the VML/VSL/IPP-dependent routines - ArmPL''s cblas_*');
  WriteLn(OutFile, '// layer is wired in via cblas.pas''s CBLASLib constant (preferring');
  WriteLn(OutFile, '// libarmpl_lp64.so over libopenblas whenever HAVE_ARMPL is defined); its');
  WriteLn(OutFile, '// LAPACKE_* layer is a separate concern, see HAVE_LAPACKE below. Left');
  WriteLn(OutFile, '// undefined (not set to False) when a BLAS backend is found, matching');
  WriteLn(OutFile, '// PUREPASCAL''s own convention.');
  if not HaveBLAS then
    WriteLn(OutFile, '{$DEFINE PUREPASCAL_BLAS}')
  else
    WriteLn(OutFile, '// {$DEFINE PUREPASCAL_BLAS} left undefined: a CBLAS-compatible backend was found');
  CloseFile(OutFile);

  WriteLn('Done.');
  if not (HaveOpenBLAS and HaveMKL and HaveIPP) then
    WriteLn('PUREPASCAL will be active for newVM.pas''s core linear algebra (a backend is missing).')
  else
    WriteLn('All three linear-algebra backends found - newVM.pas will build against them as usual.');
  if HaveBLAS then
    WriteLn('PUREPASCAL_BLAS is inactive - newVM.pas''s CBLAS-only routines will use ',
      IfThen(HaveArmPL, 'Arm Performance Libraries', IfThen(HaveOpenBLAS, 'OpenBLAS', 'Apple Accelerate')), '.')
  else
    WriteLn('PUREPASCAL_BLAS will be active - no CBLAS-compatible backend found.');
  if HaveLAPACKE then
    WriteLn('HAVE_LAPACKE is active - LinearSolve/Invert/Det/Id/EigDecompose will use ',
      IfThen(HaveMKL, 'MKL', 'Arm Performance Libraries'), '''s LAPACKE_*, not their PUREPASCAL fallback.')
  else
    WriteLn('HAVE_LAPACKE is inactive - LinearSolve/Invert/Det/Id/EigDecompose will use their PUREPASCAL fallback (no MKL or ArmPL found).');
  if HaveOpenCL then
    WriteLn('HAVE_OPENCL is active - newVMCL.pas/TVMobjCL will build and its tests will run.')
  else
    WriteLn('HAVE_OPENCL is inactive - newVMCL.pas/TVMobjCL is excluded from the build (OpenCL.dll and/or clFFT.dll not found).');
  if HaveMetal then
    WriteLn('HAVE_METAL is active - newVMMetal.pas/TVMobjMTL will build and its tests will run.')
  else
    WriteLn('HAVE_METAL is inactive - newVMMetal.pas/TVMobjMTL is excluded from the build (not Apple Silicon, or Metal/MetalPerformanceShadersGraph not found).');
end.
