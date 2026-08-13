program newvmconfigure;

{*******************************************************************************

     Build-time platform/library detector for newVM.

     FPC's {$IFDEF}/{$Linklib} directives are resolved at COMPILE time, but
     "is libmkl_rt.so actually installed on this machine" is a fact about
     the BUILD machine, not something the compiler can know on its own.
     This standalone console program bridges that gap: run it once (before
     lazbuild) on whatever machine you're about to build newVM* on, and it
     writes newVMConfig.inc - a plain {$DEFINE ...} include file that
     newVM.pas (and, as they gain the same fallback treatment, its sibling
     units) {$I} at the top, gating their {$Linklib} blocks and choosing
     between MKL/IPP/OpenBLAS-backed and plain-Pascal implementations.

     Detection has two halves:
       - OS and CPU architecture: free at compile time via FPC's own
         built-in macros (WINDOWS/LINUX/DARWIN, CPUX86_64/CPUAARCH64/...) -
         this tool just relays them into PLATFORM_* defines so the
         generated include file documents what it was generated for.
       - Library presence: NOT knowable at compile time, so this probes at
         RUNTIME via LoadLibrary (DynLibs), the exact same "try to dlopen
         it, see if it works" technique cblas.pas already uses for OpenBLAS
         (TryInitializeCBLAS/LoadAddresses) and fftw3.pas uses for FFTW -
         just done once here, ahead of the real build, rather than every
         time the built program starts.

     This program deliberately has no dependency on cblas.pas/OneAPI.pas/
     fftw3.pas/newVM*.pas themselves (only SysUtils/DynLibs) - it has to be
     buildable and runnable on a machine that might have NONE of MKL/IPP/
     OpenBLAS/FFTW installed, which rules out anything that {$Linklib}s
     against them.

     Usage:
       fpc newvmconfigure.lpr          (one-off compile; no MKL/IPP/
                                         OpenBLAS/FFTW needed to build this
                                         tool itself)
       ./newvmconfigure                (writes newVMConfig.inc into the
                                         current directory - run this from
                                         the repo root)
       lazbuild --lazarusdir=<path> newVMtest.lpi   (as before)

     Re-run ./newvmconfigure whenever you build on a different machine, or
     after installing/removing MKL/IPP/OpenBLAS/FFTW on this one - it is a
     snapshot of the machine it ran on, not a portability guarantee.

*******************************************************************************}

{$mode objfpc}{$H+}

uses
  SysUtils, DynLibs;

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
  HaveMKL, HaveIPPCore, HaveIPPVM, HaveIPPS, HaveIPP, HaveOpenBLAS, HaveFFTWD, HaveFFTWS, HaveFFTW: Boolean;
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

  HaveFFTWD := ProbeLibrary(FFTWDoubleCandidates, FoundName);
  HaveFFTWS := ProbeLibrary(FFTWSingleCandidates, FoundName);
  HaveFFTW := HaveFFTWD and HaveFFTWS;
  Report('FFTW3 (double+single, both)', HaveFFTW,
    Format('double=%s single=%s', [BoolToStr(HaveFFTWD,True), BoolToStr(HaveFFTWS,True)]));

  WriteLn;
  WriteLn('Writing newVMConfig.inc ...');

  { NOTE: every generated line below uses '//' line comments, never a
    '{ ... }' block comment - Pascal block comments aren't nestable, so a
    literal '{' or '}' anywhere in the prose (e.g. naming the very
    {$IFDEF PUREPASCAL} directive this file drives) would silently
    truncate the comment early and feed the rest of the sentence to the
    compiler as code. '//' comments can't have that problem since they
    always end at the line break regardless of their content. }
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
  if HaveOpenBLAS then WriteLn(OutFile, '{$DEFINE HAVE_OPENBLAS}   // libopenblas found');
  if HaveMKL      then WriteLn(OutFile, '{$DEFINE HAVE_MKL}        // libmkl_rt found');
  if HaveIPP      then WriteLn(OutFile, '{$DEFINE HAVE_IPP}        // libippcore+libippvm+libipps all found');
  if HaveFFTW     then WriteLn(OutFile, '{$DEFINE HAVE_FFTW}       // libfftw3+libfftw3f both found');
  WriteLn(OutFile);
  WriteLn(OutFile, '// Derived: set whenever any of the three libraries newVM.pas''s "core"');
  WriteLn(OutFile, '// linear algebra (MatMult/Invert/LinearSolve/Det/operators/elementwise');
  WriteLn(OutFile, '// math/etc) actually calls into - OpenBLAS (cblas_*), MKL (LAPACKE_*/vd*/');
  WriteLn(OutFile, '// vsl*) and IPP (ipps*) - is missing, so those routines fall back to plain');
  WriteLn(OutFile, '// Pascal implementations instead of failing to link. FFTW absence is NOT');
  WriteLn(OutFile, '// included here: DCT/DST/FFT have no plain-Pascal fallback (out of scope -');
  WriteLn(OutFile, '// see newVM.pas''s r2rTransform) and already degrade to a clear runtime');
  WriteLn(OutFile, '// assert on their own when FFTW isn''t loaded, regardless of this define.');
  WriteLn(OutFile, '// Presently only newVM.pas (double-precision real) actually implements the');
  WriteLn(OutFile, '// PUREPASCAL-guarded bodies this drives - newVMSingle.pas/newVMComplex.pas/');
  WriteLn(OutFile, '// newVMComplexSingle.pas still hard-require MKL/IPP/OpenBLAS unconditionally.');
  if not (HaveOpenBLAS and HaveMKL and HaveIPP) then
    WriteLn(OutFile, '{$DEFINE PUREPASCAL}')
  else
    WriteLn(OutFile, '// {$DEFINE PUREPASCAL} left undefined: all three backends found');
  CloseFile(OutFile);

  WriteLn('Done.');
  if not (HaveOpenBLAS and HaveMKL and HaveIPP) then
    WriteLn('PUREPASCAL will be active for newVM.pas''s core linear algebra (a backend is missing).')
  else
    WriteLn('All three linear-algebra backends found - newVM.pas will build against them as usual.');
end.
