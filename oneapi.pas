unit OneAPI;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils,cblas;

{$Linklib 'mkl_rt.so'} //intel mkl 64 bit
{$Linklib 'ippcore.so'}
{$Linklib 'ippvm.so'}
{$LinkLib 'ipps.so'}

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
function lapacke_dgetri(matrix_layout: CBLAS_ORDER; n: Integer; a: PDouble; lda: Integer; const ipiv: PInteger): Integer; cdecl;external;

{eigen values, eigenvector routines}

function lapacke_dgeev(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PDouble; lda : Integer;
                        wr ,wi : PDouble; vl : PDouble; ldvl :integer; vr : PDouble; ldvr : Integer):Integer;cdecl;external;

function lapacke_sgeev(matrix_layout : CBLAS_ORDER; jobvl,jobvr :UTF8Char; n : Integer; A : PSingle; lda : Integer;
                        wr ,wi : PSingle; vl : PSingle; ldvl :integer; vr : PSingle; ldvr : Integer):Integer;cdecl;external;

// routines from intel vml library

procedure vmdSqr(const n: Integer; a: PDouble; r: PDouble); cdecl; external;

procedure vmdAdd(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

procedure vmdSub(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

procedure vmdMul(const n: Integer; a: PDouble; b: PDouble; r: PDouble); cdecl;external;

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

procedure vsSin(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsCos(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsTan(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSinh(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSqr(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsSqrt(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsExp(const n: Integer; a: PSingle; r: PSingle); cdecl; external;
procedure vsLn(const n: Integer; a: PSingle; r: PSingle); cdecl; external;

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

function ippsCopy_64f(const pSrc: PDouble; pDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsMulC_64f_I_L(val: double; pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsMulC_64f(const pSrc: PIpp64f; val: Ipp64f; pDst: PIpp64f; len: Integer): Integer; cdecl;external;

function ippsAddC_64f_I(val: double; pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsSubC_64f_I(val: Double; pSrcDst: PDouble; len: Integer): Integer cdecl;external;

function ippsDivC_64f_I(val: Double; pSrcDst: PDouble; len: Integer): Integer; cdecl; external;

function ippsDivC_32f_I(val: Single; pSrcDst: PSingle; len: Integer): Integer; cdecl; external;

function ippsSqr_64f_I(pSrcDst: PDouble; len: Integer): Integer; cdecl;external;

function ippsExp_64f_I(PDouble: PIpp64f; len: Integer): Integer; cdecl;external;

function ippInit():Integer;cdecl;external;


// Memory management

function MKL_malloc(size: NativeUInt; align: Integer): Pointer; cdecl;external; //non initialized

function MKL_calloc(num: NativeUInt; size: NativeUInt; align: Integer): Pointer; cdecl;external;  //initialized

function MKL_realloc(ptr: Pointer; size: NativeUInt): Pointer; cdecl;external;

procedure MKL_free(ptr: Pointer); cdecl;external;

function ippMalloc(length: Integer): Pointer; cdecl;external;

procedure ippFree(ptr: Pointer); cdecl;external;

procedure MKL_Dimatcopy(const ordering: UTF8Char; const trans: UTF8Char; rows: NativeUInt; cols: NativeUInt; const alpha: Double; AB: PDouble; lda: NativeUInt; ldb: NativeUInt); cdecl;external;

// Random Number Generator

function vslNewStream(const p1: Pointer; const p2: Integer; const p3: Cardinal): Integer; cdecl;external;

function vslDeleteStream(p1: Pointer): Integer; cdecl;external;

{double precision}
function vdRngGaussian(const p1: Integer; p2: Pointer; const p3: Integer; p4: PDouble; const p5: Double; const p6: Double): Integer; cdecl;external;

{single precision}
function vsRngGaussian(const p1: Integer; p2: Pointer; const p3: Integer; p4: PSingle; const p5: Single; const p6: Single): Integer; cdecl;external;


//cblas routines

{ MKL BLAS declarations }






implementation

end.

