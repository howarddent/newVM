unit OneAPI;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DynLibs, cblas;

{$IFDEF UNIX}
{$Linklib 'mkl_rt.so'} //intel mkl 64 bit
{$Linklib 'ippcore.so'}
{$Linklib 'ippvm.so'}
{$LinkLib 'ipps.so'}
{$ENDIF}

const
  IPP_VERSION_MAJOR = 2022;
  IPP_VERSION_MINOR = 3;
  IPP_VERSION_UPDATE = 0;
  IPP_VERSION_STR = '2022.3.0';
  IPP_INTERFACE_VERSION_MAJOR = 11;
  IPP_INTERFACE_VERSION_MINOR = 3;
  { TODO : Unable to convert function-like macro: }
  (* IPPAPI ( type , name , arg ) type IPP_STDCALL name arg ; *)
  _FLOAT_16 = 2;
  _SHORT_FLOAT = 1;
  _NO_FLOAT_16 = 0;
  COMPILER_SUPPORT_SHORT_FLOAT = _NO_FLOAT_16;
  { TODO : Unable to convert function-like macro: }
  (* IPP_DEPRECATED ( comment ) __declspec ( deprecated ( comment ) ) *)
  { TODO : Macro refers to system symbol "__stdcall": }
  (* IPP_STDCALL __stdcall *)
  { TODO : Macro refers to system symbol "__cdecl": }
  (* IPP_CDECL __cdecl *)
  { TODO : Macro refers to system symbol "__int64": }
  (* IPP_INT64 __int64 *)
  { TODO : Macro probably uses invalid symbol "unsigned": }
  (* IPP_UINT64 unsigned __int64 *)
  IPP_PI = (3.14159265358979323846);
  IPP_2PI = (6.28318530717958647692);
  IPP_PI2 = (1.57079632679489661923);
  IPP_PI4 = (0.78539816339744830961);
  IPP_PI180 = (0.01745329251994329577);
  IPP_RPI = (0.31830988618379067154);
  IPP_SQRT2 = (1.41421356237309504880);
  IPP_SQRT3 = (1.73205080756887729353);
  IPP_LN2 = (0.69314718055994530942);
  IPP_LN3 = (1.09861228866810969139);
  IPP_E = (2.71828182845904523536);
  IPP_RE = (0.36787944117144232159);
  IPP_EPS23 = (1.19209289e-07);
  IPP_EPS52 = (2.2204460492503131e-016);
  IPP_MAX_8U = ($FF);
  IPP_MAX_16U = ($FFFF);
  IPP_MAX_32U = ($FFFFFFFF);
  IPP_MIN_8U = (0);
  IPP_MIN_16U = (0);
  IPP_MIN_32U = (0);
  IPP_MIN_8S = (-128);
  IPP_MAX_8S = (127);
  IPP_MIN_16S = (-32768);
  IPP_MAX_16S = (32767);
  IPP_MIN_32S = (-2147483647-1);
  IPP_MAX_32S = (2147483647);
  IPP_MIN_64U = (0);
  IPP_MAX_64S = (9223372036854775807);
  IPP_MIN_64S = (-9223372036854775807-1);
  IPP_MAX_64U = ($ffffffffffffffff);
  IPP_MINABS_32F = (1.175494351e-38);
  IPP_MAXABS_32F = (3.402823466e+38);
  IPP_EPS_32F = (1.192092890e-07);
  IPP_MINABS_64F = (2.2250738585072014e-308);
  IPP_MAXABS_64F = (1.7976931348623158e+308);
  IPP_EPS_64F = (2.2204460492503131e-016);
  { TODO : Unable to convert function-like macro: }
  (* IPP_MAX ( a , b ) ( ( ( a ) > ( b ) ) ? ( a ) : ( b ) ) *)
  { TODO : Unable to convert function-like macro: }
  (* IPP_MIN ( a , b ) ( ( ( a ) < ( b ) ) ? ( a ) : ( b ) ) *)
  { TODO : Unable to convert function-like macro: }
  (* IPP_ABS ( a ) ( ( ( a ) < 0 ) ? ( - ( a ) ) : ( a ) ) *)
  ippCPUID_MMX = $00000001;
  ippCPUID_SSE = $00000002;
  ippCPUID_SSE2 = $00000004;
  ippCPUID_SSE3 = $00000008;
  ippCPUID_SSSE3 = $00000010;
  ippCPUID_MOVBE = $00000020;
  ippCPUID_SSE41 = $00000040;
  ippCPUID_SSE42 = $00000080;
  ippCPUID_AVX = $00000100;
  ippAVX_ENABLEDBYOS = $00000200;
  ippCPUID_AES = $00000400;
  ippCPUID_CLMUL = $00000800;
  ippCPUID_ABR = $00001000;
  ippCPUID_RDRAND = $00002000;
  ippCPUID_F16C = $00004000;
  ippCPUID_AVX2 = $00008000;
  ippCPUID_ADCOX = $00010000;
  ippCPUID_RDSEED = $00020000;
  ippCPUID_PREFETCHW = $00040000;
  ippCPUID_SHA = $00080000;
  ippCPUID_AVX512F = $00100000;
  ippCPUID_AVX512CD = $00200000;
  ippCPUID_AVX512ER = $00400000;
  ippCPUID_AVX512PF = $00800000;
  ippCPUID_AVX512BW = $01000000;
  ippCPUID_AVX512DQ = $02000000;
  ippCPUID_AVX512VL = $04000000;
  ippCPUID_AVX512VBMI = $08000000;
  ippCPUID_MPX = $10000000;
  ippCPUID_AVX512_4FMADDPS = $20000000;
  ippCPUID_AVX512_4VNNIW = $40000000;
  ippCPUID_KNC = $80000000;
  { TODO : Unable to convert function-like macro: }
  (* INT64_SUFFIX ( name ) name ## L *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX512IFMA INT64_SUFFIX ( 0x100000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_NOCHECK INT64_SUFFIX ( 0x8000000000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_GETINFO_A INT64_SUFFIX ( 0x616f666e69746567 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippAVX512_ENABLEDBYOS INT64_SUFFIX ( 0x200000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX512VPOPCNTDQ INT64_SUFFIX ( 0x400000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX512_BITALG INT64_SUFFIX ( 0x800000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX512_FP16 INT64_SUFFIX ( 0x1000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX_VNNI INT64_SUFFIX ( 0x2000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX_VNNI_INT8 INT64_SUFFIX ( 0x4000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX_VNNI_INT16 INT64_SUFFIX ( 0x8000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX10_256 INT64_SUFFIX ( 0x10000000000 ) *)
  { TODO : Macro uses commented-out symbol "INT64_SUFFIX": }
  (* ippCPUID_AVX10_512 INT64_SUFFIX ( 0x20000000000 ) *)
  ABI_BAD_BX = 1;
  ABI_BAD_DI = 2;
  ABI_BAD_SI = 4;
  ABI_BAD_BP = 8;
  ABI_BAD_12 = $10;
  ABI_BAD_13 = $20;
  ABI_BAD_14 = $40;
  ABI_BAD_15 = $80;
  { TODO : Unable to convert function-like macro: }
  (* IPP_COUNT_OF ( obj ) ( sizeof ( obj ) / sizeof ( obj [ 0 ] ) ) *)
  IPP_TEMPORAL_COPY = $0;
  IPP_NONTEMPORAL_STORE = $01;
  IPP_NONTEMPORAL_LOAD = $02;
  { TODO : Unable to convert function-like macro: }
  (* IPP_DEG_TO_RAD ( deg ) ( ( deg ) / 180.0 * IPP_PI ) *)
  IPP_HOG_MAX_CELL = (16);
  IPP_HOG_MAX_BLOCK = (64);
  IPP_HOG_MAX_BINS = (16);
  IPP_SEGMENT_QUEUE = $01;
  IPP_SEGMENT_DISTANCE = $02;
  IPP_SEGMENT_BORDER_4 = $40;
  IPP_SEGMENT_BORDER_8 = $80;
  { TODO : Unable to convert function-like macro: }
  (* IPP_TRUNC ( a , b ) ( ( a ) & ~ ( ( b ) - 1 ) ) *)
  { TODO : Unable to convert function-like macro: }
  (* IPP_APPEND ( a , b ) ( ( ( a ) + ( b ) - 1 ) & ~ ( ( b ) - 1 ) ) *)
  IppZFPMINBITS = (0);
  IppZFPMAXBITS = (4171);
  IppZFPMAXPREC = (64);
  IppZFPMINEXP = (-10740);
type
   Ipp8u = Byte;
  PIpp8u = ^Ipp8u;
  PPIpp8u = ^PIpp8u;
  Ipp16u = Word;
  PIpp16u = ^Ipp16u;
  PPIpp16u = ^PIpp16u;
  Ipp32u = Cardinal;
  PIpp32u = ^Ipp32u;
  Ipp8s = UTF8Char;
  PIpp8s = PUTF8Char;
  Ipp16s = Smallint;
  PIpp16s = ^Ipp16s;
  PPIpp16s = ^PIpp16s;
  Ipp32s = Integer;
  PIpp32s = ^Ipp32s;
  PPIpp32s = ^PIpp32s;
  Ipp32f = Single;
  PIpp32f = ^Ipp32f;
  PPIpp32f = ^PIpp32f;
  Ipp64s = Int64;
  PIpp64s = ^Ipp64s;
  Ipp64u = UInt64;
  PIpp64u = ^Ipp64u;
  Ipp64f = Double;
  PIpp64f = ^Ipp64f;
  PPIpp64f = ^PIpp64f;
  Ipp16f = Ipp16s;
  PIpp16f = ^Ipp16f;
  TComplex16 = record
    re, im : Double;
  end;
  PComplex16 =^TComplex16;

  //Single-precision complex scalar - the "C" (as opposed to "Z") LAPACK/
  //BLAS type. Same two-contiguous-fields layout as TComplex16, just Single
  //instead of Double, matching MKL_Complex8.
  TComplex8 = record
    re, im : Single;
  end;
  PComplex8 = ^TComplex8;

//On Unix, every routine below (MKL and IPP alike) is declared as a plain
//"cdecl;external;" function/procedure, resolved at link time via the
//{$Linklib} block above - unchanged from how this unit always worked on
//Linux.
//
//On Windows, none of that works unmodified:
// - MKL's Windows redistributable does NOT ship a fixed "mkl_rt.dll" the
//   way mkl_rt.so is a fixed name on Linux - recent Intel oneAPI releases
//   version the dispatcher DLL itself (observed: mkl_rt.2.dll for oneAPI
//   2025.3, mkl_rt.3.dll for 2026.0/2026.1), and there is no unversioned
//   compatibility copy. A static 'external "mkl_rt.dll"' declaration is
//   therefore not just a guess but actively wrong on any real install.
// - IPP ships several separate DLLs (ippcore.dll/ippvm.dll/ipps.dll), and
//   which one exports a given "ipps*"-prefixed symbol is not reliably
//   documented and can vary by IPP version.
//Both problems have the same shape - the correct DLL/filename can't be
//known at compile time - so both are solved the same way: declare these
//as procedural-type variables instead of "external" functions, and
//resolve each one at runtime via LoadLibrary/GetProcedureAddress against
//a small list of candidate DLL names/files, in LoadMKLFunctions and
//LoadIPPFunctions (implementation section, run from this unit's
//initialization). This mirrors the pattern cblas.pas already uses for
//OpenBLAS (LoadAddresses/TryInitializeCBLAS there).

{$IFDEF UNIX}
  { Lapacke LU factorisation}
function lapacke_dgetrf(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PDouble; lda: Integer; ipiv: PInteger): Integer;cdecl;external;
{LaPacke linear solve}
function lapacke_dgesv(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PDouble; lda: Integer; ipiv: PInteger; b: PDouble; ldb: Integer):integer; cdecl;external;

function lapacke_sgesv(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PSingle; lda: Integer; ipiv: PInteger; b: PSingle; ldb: Integer):integer; cdecl;external;

function lapacke_zgesv(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PComplex16; lda: Integer; ipiv: PInteger; b: PComplex16; ldb: Integer):integer; cdecl;external;

function lapacke_cgesv(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PComplex8; lda: Integer; ipiv: PInteger; b: PComplex8; ldb: Integer):integer; cdecl;external;

{lapacke set diagonal elements}
function lapacke_dlaset(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: Double; beta: Double; a: PDouble; lda: Integer): Integer; cdecl;external;

function lapacke_slaset(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: single; beta: single; a: PSingle; lda: Integer): Integer; cdecl;external;

function lapacke_zlaset(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: TComplex16; beta: TComplex16; a: PComplex16; lda: Integer): Integer; cdecl;external;

function lapacke_claset(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: TComplex8; beta: TComplex8; a: PComplex8; lda: Integer): Integer; cdecl;external;

{lapacke copy routines}
function lapacke_dlacpy(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PDouble; lda: Integer; b: PDouble; ldb: Integer): Integer; cdecl; external;

function lapacke_slacpy(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PSingle; lda: Integer; b: PSingle; ldb: Integer): Integer; cdecl; external;

function lapacke_zlacpy(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PComplex16; lda: Integer; b: PComplex16; ldb: Integer): Integer; cdecl; external;

function lapacke_clacpy(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PComplex8; lda: Integer; b: PComplex8; ldb: Integer): Integer; cdecl; external;


{matrix inversion routines}
function lapacke_sgetrf(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PSingle; lda: Integer; ipiv: PInteger): Integer;cdecl;external;

function lapacke_zgetrf(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PComplex16; lda: Integer; ipiv: PInteger): Integer;cdecl;external;

function lapacke_cgetrf(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PComplex8; lda: Integer; ipiv: PInteger): Integer;cdecl;external;

function lapacke_dgetri(matrix_layout: CBLAS_ORDER; n: Integer; a: PDouble; lda: Integer; const ipiv: PInteger): Integer; cdecl;external;

function lapacke_sgetri(matrix_layout: CBLAS_ORDER; n: Integer; a: PSingle; lda: Integer; const ipiv: PInteger): Integer; cdecl;external;

function lapacke_zgetri(matrix_layout: CBLAS_ORDER; n: Integer; a: PComplex16; lda: Integer; const ipiv: PInteger): Integer; cdecl;external;

function lapacke_cgetri(matrix_layout: CBLAS_ORDER; n: Integer; a: PComplex8; lda: Integer; const ipiv: PInteger): Integer; cdecl;external;

{eigen values, eigenvector routines}

function lapacke_dgeev(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PDouble; lda : Integer;
                        wr ,wi : PDouble; vl : PDouble; ldvl :integer; vr : PDouble; ldvr : Integer):Integer;cdecl;external;

function lapacke_sgeev(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PSingle; lda : Integer;
                        wr ,wi : PSingle; vl : PSingle; ldvl :integer; vr : PSingle; ldvr : Integer):Integer;cdecl;external;

// routines from intel vml library

procedure vmdSqr(const n: Integer; a: PDouble; r: PDouble); cdecl; external;

procedure vmdAdd(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

procedure vmdSub(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

procedure vmdDiv(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

procedure vmdPowx(const n: Integer; a: PDouble; b: Double; r: PDouble); cdecl;external;

procedure vmdSin(const n: Integer; a: PDouble; r: PDouble); cdecl;external;

procedure vmdCos(const n: Integer; a: PDouble; r: PDouble); cdecl;external;

procedure vmdExp(const n: Integer; a: PDouble; r: PDouble); cdecl;external;

// Elementwise transcendental/algebraic functions, for newVM*'s Sin/Cos/Tan/
// Sinh/Sqr/Sqrt/Exp/Ln. These use MKL VML's plain "vd/vs/vc/vz" entry
// points (n, input array, output array; default VML accuracy mode) rather
// than the "vmd/vms/vmc/vmz" family above, which take an extra trailing
// VML-mode argument that the vmd* declarations above don't pass - so
// prefer the functions below for new code rather than extending that block.
procedure vdSin(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdCos(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdTan(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdSinh(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdSqr(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdSqrt(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdExp(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
procedure vdLn(const n: Integer; a: PDouble; r: PDouble); cdecl; external;
//plain (mode-less) elementwise multiply, for newVM's elementwise '*'
//operator (mulObj) - deliberately vdMul, not the vmdMul family above (see
//comment on that block: vmdMul silently reads a missing 5th "mode" stack
//argument as garbage under the Win64 calling convention).
procedure vdMul(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl; external;

procedure vsSin(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsCos(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsTan(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSinh(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSqr(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSqrt(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsExp(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsLn(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
//single-precision real analogue of vdMul above, for newVMSingle's
//elementwise '*' operator (MulObjS).
procedure vsMul(const n: Integer; a: PSingle; b: PSingle; r: PSingle); cdecl; external;

procedure vzSin(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzCos(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzTan(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzSinh(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzSqrt(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzExp(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
procedure vzLn(const n: Integer; a: PComplex16; r: PComplex16); cdecl; external;
//MKL VM has no dedicated complex "Sqr" (unlike vdSqr/vsSqr for real data) -
//complex Sqr(A) is implemented as A .* A via elementwise vzMul instead.
procedure vzMul(const n: Integer; a: PComplex16; b: PComplex16; r: PComplex16); cdecl; external;

procedure vcSin(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcCos(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcTan(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcSinh(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcSqrt(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcExp(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
procedure vcLn(const n: Integer; a: PComplex8; r: PComplex8); cdecl; external;
//see vzMul note above - same reason, single-precision complex.
procedure vcMul(const n: Integer; a: PComplex8; b: PComplex8; r: PComplex8); cdecl; external;

//ipp routines

function ippsCos_64f_A50(a : Pdouble; r: Pdouble; n: Integer): Integer; cdecl;external;

function ippsVectorSlope_64f( a : Pdouble; len: Integer; offset: double; slope: double): Integer; cdecl;external;

//single-precision real analogue of ippsVectorSlope_64f, for newVMSingle's linspace.
function ippsVectorSlope_32f( a : PSingle; len: Integer; offset: Single; slope: Single): Integer; cdecl;external;

//NOTE: IPP does not ship complex VectorSlope variants (ippsVectorSlope_64fc/
//_32fc are not exported by libipps - only the real 8u/16u/16s/32u/32s/32f/64f
//forms exist), so newVMComplex's/newVMComplexSingle's linspace fill their
//complex arithmetic sequence with a plain Pascal loop instead - see there.

//integer analogue of ippsVectorSlope_64f/_32f, for newVMI's linspace.
//NOTE: unlike the 64f/32f forms, IPP's 32s variant takes offset/slope as
//Ipp64f (Double), not Ipp32s - confirmed in ipps.h ("IPPAPI(IppStatus,
//ippsVectorSlope_32s, (Ipp32s* pDst, int len, Ipp64f offset, Ipp64f slope))").
//Only the destination buffer is Ipp32s (PInteger); get this wrong and the
//call reads garbage off the calling convention's float/int register split.
function ippsVectorSlope_32s( a : PInteger; len: Integer; offset: Double; slope: Double): Integer; cdecl;external;

function ippsCopy_64f(const pSrc: PDouble; pDst: PDouble; len: Integer): Integer; cdecl;external;

//integer analogue of ippsCopy_64f, for newVMI's CopyObjI.
function ippsCopy_32s(const pSrc: PInteger; pDst: PInteger; len: Integer): Integer; cdecl;external;

//ippsFlip - reverses the element order of a vector into a (possibly
//different) destination buffer, for newVM.pas's/newVMSingle.pas's/
//newVMComplex.pas's/newVMComplexSingle.pas's FlipLR (reverses each row's
//elements). PComplex16/PComplex8 stand in for Ipp64fc/Ipp32fc - bit-identical
//layout, same trick used throughout for MKL/IPP complex interop.
function ippsFlip_64f(const pSrc: PDouble; pDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsFlip_32f(const pSrc: PSingle; pDst: PSingle; len: Integer): Integer; cdecl;external;

function ippsFlip_64fc(const pSrc: PComplex16; pDst: PComplex16; len: Integer): Integer; cdecl;external;

function ippsFlip_32fc(const pSrc: PComplex8; pDst: PComplex8; len: Integer): Integer; cdecl;external;

function ippsMulC_64f_I_L(val: double; pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsMulC_64f(const pSrc: PIpp64f; val: Ipp64f; pDst: PIpp64f; len: Integer): Integer; cdecl;external;

function ippsAddC_64f_I(val: double; pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsSubC_64f_I(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsDivC_64f_I(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl; external;

function ippsDivC_32f_I(val: Single; pSrcDst: PSingle; len: Integer): Integer; cdecl; external;

function ippsSqr_64f_I(pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsExp_64f_I(PDouble: PIpp64f; len: Integer): Integer; cdecl;external;

function ippInit():Integer;cdecl;external;

function ippMalloc(length: Integer): Pointer; cdecl;external;

procedure ippFree(ptr: Pointer); cdecl;external;

// Memory management

function MKL_malloc(size: NativeUInt; align: Integer): Pointer; cdecl;external; //non initialized

function MKL_calloc(num: NativeUInt; size: NativeUInt; align: Integer): Pointer; cdecl;external;  //initialized

function MKL_realloc(ptr: Pointer; size: NativeUInt): Pointer; cdecl;external;

procedure MKL_free(ptr: Pointer); cdecl;external;

procedure MKL_Dimatcopy(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: Double; AB: PDouble; lda: NativeUInt; ldb: NativeUInt); cdecl;external;

//single/complex analogues of MKL_Dimatcopy above, for the other three
//units' Transpose methods.
procedure MKL_Simatcopy(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: Single; AB: PSingle; lda: NativeUInt; ldb: NativeUInt); cdecl;external;
procedure MKL_Zimatcopy(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: TComplex16; AB: PComplex16; lda: NativeUInt; ldb: NativeUInt); cdecl;external;
procedure MKL_Cimatcopy(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: TComplex8; AB: PComplex8; lda: NativeUInt; ldb: NativeUInt); cdecl;external;

// Random Number Generator

function vslNewStream(const p1: Pointer; const p2: Integer; const p3: Cardinal): Integer; cdecl;external;

function vslDeleteStream(p1: Pointer): Integer; cdecl;external;

{double precision}
function vdRngGaussian(const p1: Integer; p2: Pointer; const p3: Integer; p4: PDouble; const p5: Double; const p6: Double): Integer; cdecl;external;

{single precision}
function vsRngGaussian(const p1: Integer; p2: Pointer; const p3: Integer; p4: PSingle; const p5: Single; const p6: Single): Integer; cdecl;external;

{integer, bounded uniform - for newVMI's fillRandom}
function viRngUniform(const p1: Integer; p2: Pointer; const p3: Integer; p4: PInteger; const p5: Integer; const p6: Integer): Integer; cdecl;external;
{$ENDIF}

{$IFDEF WINDOWS}
type
  Tlapacke_dgetrf = function(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PDouble; lda: Integer; ipiv: PInteger): Integer; cdecl;
  Tlapacke_dgesv  = function(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PDouble; lda: Integer; ipiv: PInteger; b: PDouble; ldb: Integer): integer; cdecl;
  Tlapacke_sgesv  = function(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PSingle; lda: Integer; ipiv: PInteger; b: PSingle; ldb: Integer): integer; cdecl;
  Tlapacke_zgesv  = function(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PComplex16; lda: Integer; ipiv: PInteger; b: PComplex16; ldb: Integer): integer; cdecl;
  Tlapacke_cgesv  = function(matrix_layout: CBLAS_ORDER; n: Integer; nrhs: Integer; a: PComplex8; lda: Integer; ipiv: PInteger; b: PComplex8; ldb: Integer): integer; cdecl;
  Tlapacke_dlaset = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: Double; beta: Double; a: PDouble; lda: Integer): Integer; cdecl;
  Tlapacke_slaset = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: single; beta: single; a: PSingle; lda: Integer): Integer; cdecl;
  Tlapacke_zlaset = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: TComplex16; beta: TComplex16; a: PComplex16; lda: Integer): Integer; cdecl;
  Tlapacke_claset = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; alpha: TComplex8; beta: TComplex8; a: PComplex8; lda: Integer): Integer; cdecl;
  Tlapacke_dlacpy = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PDouble; lda: Integer; b: PDouble; ldb: Integer): Integer; cdecl;
  Tlapacke_slacpy = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PSingle; lda: Integer; b: PSingle; ldb: Integer): Integer; cdecl;
  Tlapacke_zlacpy = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PComplex16; lda: Integer; b: PComplex16; ldb: Integer): Integer; cdecl;
  Tlapacke_clacpy = function(matrix_layout: CBLAS_ORDER; uplo: UTF8Char; m: Integer; n: Integer; const a: PComplex8; lda: Integer; b: PComplex8; ldb: Integer): Integer; cdecl;
  Tlapacke_sgetrf = function(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PSingle; lda: Integer; ipiv: PInteger): Integer; cdecl;
  Tlapacke_zgetrf = function(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PComplex16; lda: Integer; ipiv: PInteger): Integer; cdecl;
  Tlapacke_cgetrf = function(matrix_layout: CBLAS_ORDER; m: Integer; n: Integer; a: PComplex8; lda: Integer; ipiv: PInteger): Integer; cdecl;
  Tlapacke_dgetri = function(matrix_layout: CBLAS_ORDER; n: Integer; a: PDouble; lda: Integer; const ipiv: PInteger): Integer; cdecl;
  Tlapacke_sgetri = function(matrix_layout: CBLAS_ORDER; n: Integer; a: PSingle; lda: Integer; const ipiv: PInteger): Integer; cdecl;
  Tlapacke_zgetri = function(matrix_layout: CBLAS_ORDER; n: Integer; a: PComplex16; lda: Integer; const ipiv: PInteger): Integer; cdecl;
  Tlapacke_cgetri = function(matrix_layout: CBLAS_ORDER; n: Integer; a: PComplex8; lda: Integer; const ipiv: PInteger): Integer; cdecl;
  Tlapacke_dgeev  = function(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PDouble; lda : Integer;
                        wr ,wi : PDouble; vl : PDouble; ldvl :integer; vr : PDouble; ldvr : Integer):Integer; cdecl;
  Tlapacke_sgeev  = function(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PSingle; lda : Integer;
                        wr ,wi : PSingle; vl : PSingle; ldvl :integer; vr : PSingle; ldvr : Integer):Integer; cdecl;

  Tvmd3 = procedure(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl; //vmdAdd/Sub/Div shape
  Tvmd2 = procedure(const n: Integer; a: PDouble; r: PDouble); cdecl; //vmdSqr/Sin/Cos/Exp shape
  Tvmdpowx = procedure(const n: Integer; a: PDouble; b: Double; r: PDouble); cdecl;

  Tvd2 = procedure(const n: Integer; a: PDouble; r: PDouble); cdecl; //vd*(n,a,r) shape
  Tvd3 = procedure(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl; //vdMul shape
  Tvs2 = procedure(const n: Integer; a: PSingle; r: PSingle); cdecl; //vs*(n,a,r) shape
  Tvs3 = procedure(const n: Integer; a: PSingle; b: PSingle; r: PSingle); cdecl; //vsMul shape
  Tvz2 = procedure(const n: Integer; a: PComplex16; r: PComplex16); cdecl; //vz*(n,a,r) shape
  Tvz3 = procedure(const n: Integer; a: PComplex16; b: PComplex16; r: PComplex16); cdecl; //vzMul shape
  Tvc2 = procedure(const n: Integer; a: PComplex8; r: PComplex8); cdecl; //vc*(n,a,r) shape
  Tvc3 = procedure(const n: Integer; a: PComplex8; b: PComplex8; r: PComplex8); cdecl; //vcMul shape

  Tippscos_64f_a50     = function(a: PDouble; r: PDouble; n: Integer): Integer; cdecl;
  Tippsvectorslope_64f = function(a: PDouble; len: Integer; offset: Double; slope: Double): Integer; cdecl;
  Tippsvectorslope_32f = function(a: PSingle; len: Integer; offset: Single; slope: Single): Integer; cdecl;
  Tippsvectorslope_32s = function(a: PInteger; len: Integer; offset: Double; slope: Double): Integer; cdecl;
  Tippscopy_64f        = function(const pSrc: PDouble; pDst: PDouble; len: Integer): Integer; cdecl;
  Tippscopy_32s        = function(const pSrc: PInteger; pDst: PInteger; len: Integer): Integer; cdecl;
  Tippsflip_64f        = function(const pSrc: PDouble; pDst: PDouble; len: Integer): Integer; cdecl;
  Tippsflip_32f        = function(const pSrc: PSingle; pDst: PSingle; len: Integer): Integer; cdecl;
  Tippsflip_64fc       = function(const pSrc: PComplex16; pDst: PComplex16; len: Integer): Integer; cdecl;
  Tippsflip_32fc       = function(const pSrc: PComplex8; pDst: PComplex8; len: Integer): Integer; cdecl;
  Tippsmulc_64f_i_l    = function(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl;
  Tippsmulc_64f        = function(const pSrc: PIpp64f; val: Ipp64f; pDst: PIpp64f; len: Integer): Integer; cdecl;
  Tippsaddc_64f_i      = function(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl;
  Tippssubc_64f_i      = function(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl;
  Tippsdivc_64f_i      = function(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl;
  Tippsdivc_32f_i      = function(val: Single; pSrcDst: PSingle; len: Integer): Integer; cdecl;
  Tippssqr_64f_i       = function(pSrcDst: PDouble; len: Integer): Integer; cdecl;
  Tippsexp_64f_i       = function(a: PIpp64f; len: Integer): Integer; cdecl;
  Tippinit             = function(): Integer; cdecl;
  Tippmalloc           = function(length: Integer): Pointer; cdecl;
  Tippfree             = procedure(ptr: Pointer); cdecl;

  Tmkl_malloc  = function(size: NativeUInt; align: Integer): Pointer; cdecl;
  Tmkl_calloc  = function(num: NativeUInt; size: NativeUInt; align: Integer): Pointer; cdecl;
  Tmkl_realloc = function(ptr: Pointer; size: NativeUInt): Pointer; cdecl;
  Tmkl_free    = procedure(ptr: Pointer); cdecl;
  Tmkl_dimatcopy = procedure(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: Double; AB: PDouble; lda: NativeUInt; ldb: NativeUInt); cdecl;
  Tmkl_simatcopy = procedure(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: Single; AB: PSingle; lda: NativeUInt; ldb: NativeUInt); cdecl;
  Tmkl_zimatcopy = procedure(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: TComplex16; AB: PComplex16; lda: NativeUInt; ldb: NativeUInt); cdecl;
  Tmkl_cimatcopy = procedure(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: TComplex8; AB: PComplex8; lda: NativeUInt; ldb: NativeUInt); cdecl;

  Tvslnewstream    = function(const p1: Pointer; const p2: Integer; const p3: Cardinal): Integer; cdecl;
  Tvsldeletestream = function(p1: Pointer): Integer; cdecl;
  Tvdrnggaussian   = function(const p1: Integer; p2: Pointer; const p3: Integer; p4: PDouble; const p5: Double; const p6: Double): Integer; cdecl;
  Tvsrnggaussian   = function(const p1: Integer; p2: Pointer; const p3: Integer; p4: PSingle; const p5: Single; const p6: Single): Integer; cdecl;
  Tvirnguniform    = function(const p1: Integer; p2: Pointer; const p3: Integer; p4: PInteger; const p5: Integer; const p6: Integer): Integer; cdecl;

var
  lapacke_dgetrf : Tlapacke_dgetrf;
  lapacke_dgesv  : Tlapacke_dgesv;
  lapacke_sgesv  : Tlapacke_sgesv;
  lapacke_zgesv  : Tlapacke_zgesv;
  lapacke_cgesv  : Tlapacke_cgesv;
  lapacke_dlaset : Tlapacke_dlaset;
  lapacke_slaset : Tlapacke_slaset;
  lapacke_zlaset : Tlapacke_zlaset;
  lapacke_claset : Tlapacke_claset;
  lapacke_dlacpy : Tlapacke_dlacpy;
  lapacke_slacpy : Tlapacke_slacpy;
  lapacke_zlacpy : Tlapacke_zlacpy;
  lapacke_clacpy : Tlapacke_clacpy;
  lapacke_sgetrf : Tlapacke_sgetrf;
  lapacke_zgetrf : Tlapacke_zgetrf;
  lapacke_cgetrf : Tlapacke_cgetrf;
  lapacke_dgetri : Tlapacke_dgetri;
  lapacke_sgetri : Tlapacke_sgetri;
  lapacke_zgetri : Tlapacke_zgetri;
  lapacke_cgetri : Tlapacke_cgetri;
  lapacke_dgeev  : Tlapacke_dgeev;
  lapacke_sgeev  : Tlapacke_sgeev;

  vmdSqr  : Tvmd2;
  vmdAdd  : Tvmd3;
  vmdSub  : Tvmd3;
  vmdDiv  : Tvmd3;
  vmdPowx : Tvmdpowx;
  vmdSin  : Tvmd2;
  vmdCos  : Tvmd2;
  vmdExp  : Tvmd2;

  vdSin  : Tvd2;
  vdCos  : Tvd2;
  vdTan  : Tvd2;
  vdSinh : Tvd2;
  vdSqr  : Tvd2;
  vdSqrt : Tvd2;
  vdExp  : Tvd2;
  vdLn   : Tvd2;
  vdMul  : Tvd3;

  vsSin  : Tvs2;
  vsCos  : Tvs2;
  vsTan  : Tvs2;
  vsSinh : Tvs2;
  vsSqr  : Tvs2;
  vsSqrt : Tvs2;
  vsExp  : Tvs2;
  vsLn   : Tvs2;
  vsMul  : Tvs3;

  vzSin  : Tvz2;
  vzCos  : Tvz2;
  vzTan  : Tvz2;
  vzSinh : Tvz2;
  vzSqrt : Tvz2;
  vzExp  : Tvz2;
  vzLn   : Tvz2;
  vzMul  : Tvz3;

  vcSin  : Tvc2;
  vcCos  : Tvc2;
  vcTan  : Tvc2;
  vcSinh : Tvc2;
  vcSqrt : Tvc2;
  vcExp  : Tvc2;
  vcLn   : Tvc2;
  vcMul  : Tvc3;

  ippsCos_64f_A50     : Tippscos_64f_a50;
  ippsVectorSlope_64f : Tippsvectorslope_64f;
  ippsVectorSlope_32f : Tippsvectorslope_32f;
  ippsVectorSlope_32s : Tippsvectorslope_32s;
  ippsCopy_64f        : Tippscopy_64f;
  ippsCopy_32s        : Tippscopy_32s;
  ippsFlip_64f        : Tippsflip_64f;
  ippsFlip_32f        : Tippsflip_32f;
  ippsFlip_64fc       : Tippsflip_64fc;
  ippsFlip_32fc       : Tippsflip_32fc;
  ippsMulC_64f_I_L    : Tippsmulc_64f_i_l;
  ippsMulC_64f        : Tippsmulc_64f;
  ippsAddC_64f_I      : Tippsaddc_64f_i;
  ippsSubC_64f_I      : Tippssubc_64f_i;
  ippsDivC_64f_I      : Tippsdivc_64f_i;
  ippsDivC_32f_I      : Tippsdivc_32f_i;
  ippsSqr_64f_I       : Tippssqr_64f_i;
  ippsExp_64f_I       : Tippsexp_64f_i;
  ippInit             : Tippinit;
  ippMalloc           : Tippmalloc;
  ippFree             : Tippfree;

  MKL_malloc  : Tmkl_malloc;
  MKL_calloc  : Tmkl_calloc;
  MKL_realloc : Tmkl_realloc;
  MKL_free    : Tmkl_free;
  MKL_Dimatcopy : Tmkl_dimatcopy;
  MKL_Simatcopy : Tmkl_simatcopy;
  MKL_Zimatcopy : Tmkl_zimatcopy;
  MKL_Cimatcopy : Tmkl_cimatcopy;

  vslNewStream    : Tvslnewstream;
  vslDeleteStream : Tvsldeletestream;
  vdRngGaussian   : Tvdrnggaussian;
  vsRngGaussian   : Tvsrnggaussian;
  viRngUniform    : Tvirnguniform;

procedure LoadMKLFunctions;
procedure LoadIPPFunctions;
{$ENDIF}

implementation

{$IFDEF WINDOWS}
//No unversioned "mkl_rt.dll" exists on recent Intel oneAPI installs - the
//dispatcher DLL itself carries a version suffix that increments across
//oneAPI releases (observed: mkl_rt.2.dll, mkl_rt.3.dll). Try the
//unversioned name first (in case some install does provide it or the user
//has renamed/copied one) then a range of versioned names, and use
//whichever one LoadLibrary actually finds on PATH.
const
  MKLCandidateLibs: array[0..10] of string = (
    'mkl_rt.dll',
    'mkl_rt.1.dll', 'mkl_rt.2.dll', 'mkl_rt.3.dll', 'mkl_rt.4.dll',
    'mkl_rt.5.dll', 'mkl_rt.6.dll', 'mkl_rt.7.dll', 'mkl_rt.8.dll',
    'mkl_rt.9.dll', 'mkl_rt.10.dll'
  );

var
  MKLLibHandle: TLibHandle = NilHandle;
  MKLLibTried: Boolean = False;

function GetMKLHandle: TLibHandle;
var
  i: Integer;
begin
  if not MKLLibTried then
  begin
    MKLLibTried := True;
    for i := Low(MKLCandidateLibs) to High(MKLCandidateLibs) do
    begin
      MKLLibHandle := LoadLibrary(MKLCandidateLibs[i]);
      if MKLLibHandle <> NilHandle then Break;
    end;
  end;
  Result := MKLLibHandle;
end;

function MKLProc(const FuncName: AnsiString): Pointer;
const
  s = 'OneAPI (Windows MKL loader) : ';
var
  h: TLibHandle;
begin
  Result := nil;
  h := GetMKLHandle;
  if h <> NilHandle then
    Result := GetProcedureAddress(h, FuncName);
  assert(Result <> nil, s + 'could not locate "' + FuncName +
    '" - is an Intel oneAPI MKL runtime DLL (mkl_rt.dll or a versioned ' +
    'mkl_rt.<N>.dll) on PATH?');
end;

procedure LoadMKLFunctions;
begin
  //MKL's Windows dispatcher only exports these under the "LAPACKE_" (capital
  //prefix, lowercase suffix) spelling used by mkl_lapacke.h - unlike every
  //other symbol resolved below, it does NOT also export an all-lowercase
  //"lapacke_*" alias, and GetProcedureAddress is case-sensitive. Confirmed
  //via the exports table of mkl_rt.3.dll. The Pascal identifiers stay
  //lowercase (matching the Unix external declarations above); only the
  //string passed to MKLProc needs the real exported casing.
  pointer(lapacke_dgetrf) := MKLProc('LAPACKE_dgetrf');
  pointer(lapacke_dgesv)  := MKLProc('LAPACKE_dgesv');
  pointer(lapacke_sgesv)  := MKLProc('LAPACKE_sgesv');
  pointer(lapacke_zgesv)  := MKLProc('LAPACKE_zgesv');
  pointer(lapacke_cgesv)  := MKLProc('LAPACKE_cgesv');
  pointer(lapacke_dlaset) := MKLProc('LAPACKE_dlaset');
  pointer(lapacke_slaset) := MKLProc('LAPACKE_slaset');
  pointer(lapacke_zlaset) := MKLProc('LAPACKE_zlaset');
  pointer(lapacke_claset) := MKLProc('LAPACKE_claset');
  pointer(lapacke_dlacpy) := MKLProc('LAPACKE_dlacpy');
  pointer(lapacke_slacpy) := MKLProc('LAPACKE_slacpy');
  pointer(lapacke_zlacpy) := MKLProc('LAPACKE_zlacpy');
  pointer(lapacke_clacpy) := MKLProc('LAPACKE_clacpy');
  pointer(lapacke_sgetrf) := MKLProc('LAPACKE_sgetrf');
  pointer(lapacke_zgetrf) := MKLProc('LAPACKE_zgetrf');
  pointer(lapacke_cgetrf) := MKLProc('LAPACKE_cgetrf');
  pointer(lapacke_dgetri) := MKLProc('LAPACKE_dgetri');
  pointer(lapacke_sgetri) := MKLProc('LAPACKE_sgetri');
  pointer(lapacke_zgetri) := MKLProc('LAPACKE_zgetri');
  pointer(lapacke_cgetri) := MKLProc('LAPACKE_cgetri');
  pointer(lapacke_dgeev)  := MKLProc('LAPACKE_dgeev');
  pointer(lapacke_sgeev)  := MKLProc('LAPACKE_sgeev');

  pointer(vmdSqr)  := MKLProc('vmdSqr');
  pointer(vmdAdd)  := MKLProc('vmdAdd');
  pointer(vmdSub)  := MKLProc('vmdSub');
  pointer(vmdDiv)  := MKLProc('vmdDiv');
  pointer(vmdPowx) := MKLProc('vmdPowx');
  pointer(vmdSin)  := MKLProc('vmdSin');
  pointer(vmdCos)  := MKLProc('vmdCos');
  pointer(vmdExp)  := MKLProc('vmdExp');

  pointer(vdSin)  := MKLProc('vdSin');
  pointer(vdCos)  := MKLProc('vdCos');
  pointer(vdTan)  := MKLProc('vdTan');
  pointer(vdSinh) := MKLProc('vdSinh');
  pointer(vdSqr)  := MKLProc('vdSqr');
  pointer(vdSqrt) := MKLProc('vdSqrt');
  pointer(vdExp)  := MKLProc('vdExp');
  pointer(vdLn)   := MKLProc('vdLn');
  pointer(vdMul)  := MKLProc('vdMul');

  pointer(vsSin)  := MKLProc('vsSin');
  pointer(vsCos)  := MKLProc('vsCos');
  pointer(vsTan)  := MKLProc('vsTan');
  pointer(vsSinh) := MKLProc('vsSinh');
  pointer(vsSqr)  := MKLProc('vsSqr');
  pointer(vsSqrt) := MKLProc('vsSqrt');
  pointer(vsExp)  := MKLProc('vsExp');
  pointer(vsLn)   := MKLProc('vsLn');
  pointer(vsMul)  := MKLProc('vsMul');

  pointer(vzSin)  := MKLProc('vzSin');
  pointer(vzCos)  := MKLProc('vzCos');
  pointer(vzTan)  := MKLProc('vzTan');
  pointer(vzSinh) := MKLProc('vzSinh');
  pointer(vzSqrt) := MKLProc('vzSqrt');
  pointer(vzExp)  := MKLProc('vzExp');
  pointer(vzLn)   := MKLProc('vzLn');
  pointer(vzMul)  := MKLProc('vzMul');

  pointer(vcSin)  := MKLProc('vcSin');
  pointer(vcCos)  := MKLProc('vcCos');
  pointer(vcTan)  := MKLProc('vcTan');
  pointer(vcSinh) := MKLProc('vcSinh');
  pointer(vcSqrt) := MKLProc('vcSqrt');
  pointer(vcExp)  := MKLProc('vcExp');
  pointer(vcLn)   := MKLProc('vcLn');
  pointer(vcMul)  := MKLProc('vcMul');

  pointer(MKL_malloc)  := MKLProc('MKL_malloc');
  pointer(MKL_calloc)  := MKLProc('MKL_calloc');
  pointer(MKL_realloc) := MKLProc('MKL_realloc');
  pointer(MKL_free)    := MKLProc('MKL_free');
  pointer(MKL_Dimatcopy) := MKLProc('MKL_Dimatcopy');
  pointer(MKL_Simatcopy) := MKLProc('MKL_Simatcopy');
  pointer(MKL_Zimatcopy) := MKLProc('MKL_Zimatcopy');
  pointer(MKL_Cimatcopy) := MKLProc('MKL_Cimatcopy');

  pointer(vslNewStream)    := MKLProc('vslNewStream');
  pointer(vslDeleteStream) := MKLProc('vslDeleteStream');
  pointer(vdRngGaussian)   := MKLProc('vdRngGaussian');
  pointer(vsRngGaussian)   := MKLProc('vsRngGaussian');
  pointer(viRngUniform)    := MKLProc('viRngUniform');
end;

function IPPProc(const FuncName: AnsiString): Pointer;
const
  s = 'OneAPI (Windows IPP loader) : ';
var
  h: TLibHandle;
begin
  Result := nil;
  h := LoadLibrary('ipps.dll');
  if h <> NilHandle then
    Result := GetProcedureAddress(h, FuncName);
  if Result = nil then
  begin
    h := LoadLibrary('ippvm.dll');
    if h <> NilHandle then
      Result := GetProcedureAddress(h, FuncName);
  end;
  if Result = nil then
  begin
    h := LoadLibrary('ippcore.dll');
    if h <> NilHandle then
      Result := GetProcedureAddress(h, FuncName);
  end;
  assert(Result <> nil, s + 'could not locate "' + FuncName + '" in ipps.dll/ippvm.dll/ippcore.dll');
end;

procedure LoadIPPFunctions;
begin
  pointer(ippsCos_64f_A50)     := IPPProc('ippsCos_64f_A50');
  pointer(ippsVectorSlope_64f) := IPPProc('ippsVectorSlope_64f');
  pointer(ippsVectorSlope_32f) := IPPProc('ippsVectorSlope_32f');
  pointer(ippsVectorSlope_32s) := IPPProc('ippsVectorSlope_32s');
  pointer(ippsCopy_64f)        := IPPProc('ippsCopy_64f');
  pointer(ippsCopy_32s)        := IPPProc('ippsCopy_32s');
  pointer(ippsFlip_64f)        := IPPProc('ippsFlip_64f');
  pointer(ippsFlip_32f)        := IPPProc('ippsFlip_32f');
  pointer(ippsFlip_64fc)       := IPPProc('ippsFlip_64fc');
  pointer(ippsFlip_32fc)       := IPPProc('ippsFlip_32fc');
  pointer(ippsMulC_64f_I_L)    := IPPProc('ippsMulC_64f_I_L');
  pointer(ippsMulC_64f)        := IPPProc('ippsMulC_64f');
  pointer(ippsAddC_64f_I)      := IPPProc('ippsAddC_64f_I');
  pointer(ippsSubC_64f_I)      := IPPProc('ippsSubC_64f_I');
  pointer(ippsDivC_64f_I)      := IPPProc('ippsDivC_64f_I');
  pointer(ippsDivC_32f_I)      := IPPProc('ippsDivC_32f_I');
  pointer(ippsSqr_64f_I)       := IPPProc('ippsSqr_64f_I');
  pointer(ippsExp_64f_I)       := IPPProc('ippsExp_64f_I');
  pointer(ippInit)             := IPPProc('ippInit');
  pointer(ippMalloc)           := IPPProc('ippMalloc');
  pointer(ippFree)             := IPPProc('ippFree');
end;

initialization
  LoadMKLFunctions;
  LoadIPPFunctions;
{$ENDIF}

end.
