{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

unit AccelerateSparse;

{*******************************************************************************

     Pascal binding for Apple Accelerate's Sparse Solve API - the Darwin
     counterpart to the PARDISO half of OneAPI.pas, and the backend
     newVMsparse.pas's {$IFDEF HAVE_ACCELERATE_SPARSE} bodies call into.

     WHY THIS UNIT EXISTS. newVMsparse.pas was MKL-only: PARDISO for the
     direct solve, RCI ISS FGMRES for the iterative one. Intel ships
     neither for AArch64, so on an Apple Silicon machine the whole unit
     simply failed to compile. Accelerate's Sparse Solve API is a genuine
     equivalent of PARDISO's direct half - supernodal, multithreaded,
     fill-reducing-ordered, and (unlike anything on the GPU here) honestly
     double precision, which is what FEM4 needs. It maps onto PARDISO's
     own shape almost one for one:

       PARDISO                            Accelerate
       -------                            ----------
       mtype  2 (real SPD)                SparseFactorizationCholesky
       mtype -2 (real symmetric indef)    SparseFactorizationLDLT
       mtype 11 (real unsymmetric)        SparseFactorizationLU
       phase 11      (analyse)            SparseFactor on a structure
       phase 22      (factorise)          SparseFactor on a matrix
       phase 33      (solve)              SparseSolve
       phase -1      (release)            SparseCleanup

     THE PUBLIC C API IS UNUSABLE FROM PASCAL, the private one is fine.
     <Sparse/Solve.h>'s public SparseFactor/SparseSolve/SparseCleanup are
     C11 _Generic macros over inline wrappers that take their matrix
     arguments BY VALUE - neither a macro nor a by-value aggregate
     parameter is something an external declaration can name. Those
     wrappers all resolve to the genuinely exported _Sparse* entry points
     declared below, which take pointers instead, so those are what this
     unit binds. They are stable, versioned symbols (API_AVAILABLE in the
     SDK headers), not an implementation detail of the inline layer; the
     leading underscore is Apple's namespacing, not a private marker.
     Verified present on this machine before being bound - see
     newvmconfigure.lpr, which dlsym's the same four names it needs.

     ACCELERATE IS CSC, newVMsparse IS CSR. SparseMatrixStructure's
     columnStarts/rowIndices are compressed-column; TVMSparseMtx is
     compressed-row. The conversion lives in newVMsparse.pas (ToCSC /
     LowerTriangleCSC), not here - this unit stays a transliteration of
     the C header and nothing more.

     MACOS 15.5 FOR THE LU PATH. SparseFactorizationLU and its
     _SparseSymbolicFactorLU/_SparseNumericFactorLU_Double entry points
     are new in macOS 15.5; Cholesky and LDLT go back to 10.13. A machine
     older than 15.5 therefore has the symmetric half and not the
     unsymmetric one, which is why newvmconfigure.lpr probes for the LU
     symbols specifically rather than assuming Accelerate implies all of
     it.

*******************************************************************************}

{$mode delphi}{$H+}

interface

const
  { Framework the symbols below live in. Accelerate is an umbrella
    framework and always present on Darwin, so unlike OneAPI.pas's
    dlopen'd MKL/IPP this can be a plain link-time dependency. }
  {$IFDEF DARWIN}
  {$LINKFRAMEWORK Accelerate}
  {$ENDIF}

  { SparseFactorization_t - which factorisation to perform. }
  SparseFactorizationCholesky      = 0;
  SparseFactorizationLDLT          = 1;
  SparseFactorizationLDLTUnpivoted = 2;
  SparseFactorizationLDLTSBK       = 3;
  SparseFactorizationLDLTTPP       = 4;
  SparseFactorizationQR            = 40;
  SparseFactorizationCholeskyAtA   = 41;
  SparseFactorizationLU            = 80;   //macOS 15.5+
  SparseFactorizationLUUnpivoted   = 81;
  SparseFactorizationLUSPP         = 82;
  SparseFactorizationLUTPP         = 83;

  { SparseStatus_t - SparseOpaqueFactorization_Double.status. }
  SparseStatusOK            =  0;
  SparseFactorizationFailed = -1;
  SparseMatrixIsSingular    = -2;
  SparseInternalError       = -3;
  SparseParameterError      = -4;

  { SparseKind_t, as it sits in SparseAttributes_t's kind bitfield. }
  SparseOrdinary       = 0;
  SparseTriangular     = 1;
  SparseUnitTriangular = 2;
  SparseSymmetric      = 3;

  { SparseTriangle_t. }
  SparseUpperTriangle = 0;
  SparseLowerTriangle = 1;

  { SparseOrder_t - fill-reducing ordering, PARDISO's iparm[1] analogue. }
  SparseOrderDefault = 0;
  SparseOrderUser    = 1;
  SparseOrderAMD     = 2;
  SparseOrderMetis   = 3;
  SparseOrderCOLAMD  = 4;

  { SparseScaling_t and SparseControl_t. }
  SparseScalingDefault = 0;
  SparseDefaultControl = 0;

type
  { SparseAttributes_t is a C bitfield:

      bool             transpose : 1;   //bit 0
      SparseTriangle_t  triangle : 1;   //bit 1
      SparseKind_t          kind : 2;   //bits 2-3
      unsigned int     _reserved : 11;  //bits 4-14
      bool    _allocatedBySparse : 1;   //bit 15

    Clang allocates bitfields from the least significant bit upwards on
    every little-endian target, so the layout is exactly those bit
    positions. FPC has no bitfield syntax, so it is a plain integer here,
    built by MakeAttributes rather than by field assignment.

    It is FOUR bytes wide, not the two the sixteen used bits suggest: the
    `unsigned int _reserved` member gives the whole bitfield unit int's
    4-byte alignment, so clang rounds the struct up to match. Confirmed
    against sizeof on this machine rather than assumed - at two bytes
    every field after `attributes` in the three structures below lands
    two bytes early, which is exactly the silent corruption the
    SizeOf assertions at the end of this unit exist to catch. }
  SparseAttributes_t = LongWord;

  { SparseMatrixStructure - the symbolic half of a sparse matrix, shared
    between the Float and Double variants. Note the asymmetry in the two
    index arrays' widths, which is Apple's and not a transcription slip:
    columnStarts is 64-bit (C long), rowIndices is 32-bit (C int). }
  SparseMatrixStructure = record
    rowCount: LongInt;
    columnCount: LongInt;
    columnStarts: PInt64;
    rowIndices: PLongInt;
    attributes: SparseAttributes_t;
    blockSize: Byte;
  end;
  PSparseMatrixStructure = ^SparseMatrixStructure;

  SparseMatrix_Double = record
    structure: SparseMatrixStructure;
    data: PDouble;
  end;
  PSparseMatrix_Double = ^SparseMatrix_Double;

  { Dense right-hand side / solution. _SparseSolveOpaque_Double takes the
    Matrix form (the Vector form is only used by the inline layer), so a
    single right-hand side is passed as an (n,1) column with stride n. }
  DenseMatrix_Double = record
    rowCount: LongInt;
    columnCount: LongInt;
    columnStride: LongInt;
    attributes: SparseAttributes_t;
    data: PDouble;
  end;
  PDenseMatrix_Double = ^DenseMatrix_Double;

  DenseVector_Double = record
    count: LongInt;
    data: PDouble;
  end;
  PDenseVector_Double = ^DenseVector_Double;

  { Options. The two function pointers in the symbolic options are
    _Nonnull in the header - Accelerate calls them to allocate the
    factorisation - so they must be filled in with something real;
    DefaultSymbolicOptions wires them to the C library's own malloc/free. }
  SparseSymbolicFactorOptions = record
    control: LongInt;
    orderMethod: Byte;     //SparseOrder_t is a 1-byte enum; `order` pads to 8
    order: PLongInt;
    ignoreRowsAndColumns: PLongInt;
    malloc: function(size: NativeUInt): Pointer; cdecl;
    free: procedure(p: Pointer); cdecl;
    reportError: procedure(msg: PAnsiChar); cdecl;
  end;
  PSparseSymbolicFactorOptions = ^SparseSymbolicFactorOptions;

  SparseNumericFactorOptions = record
    control: LongInt;
    scalingMethod: Byte;   //SparseScaling_t is a 1-byte enum
    scaling: Pointer;
    pivotTolerance: Double;
    zeroTolerance: Double;
  end;
  PSparseNumericFactorOptions = ^SparseNumericFactorOptions;

  { The two opaque factorisation handles. Their fields are never touched
    here beyond `status` - they are declared in full only because both
    are returned BY VALUE, so the record's size and layout have to be
    right for the AArch64 indirect-return convention to work. }
  SparseOpaqueSymbolicFactorization = record
    status: LongInt;
    rowCount: LongInt;
    columnCount: LongInt;
    attributes: SparseAttributes_t;
    blockSize: Byte;
    factorizationType: Byte;   //SparseFactorization_t is a 1-byte enum
    factorization: Pointer;
    workspaceSize_Float: NativeUInt;
    workspaceSize_Double: NativeUInt;
    factorSize_Float: NativeUInt;
    factorSize_Double: NativeUInt;
  end;
  PSparseOpaqueSymbolicFactorization = ^SparseOpaqueSymbolicFactorization;

  SparseOpaqueFactorization_Double = record
    status: LongInt;
    attributes: SparseAttributes_t;
    symbolicFactorization: SparseOpaqueSymbolicFactorization;
    userFactorStorage: ByteBool;
    numericFactorization: Pointer;
    solveWorkspaceRequiredStatic: NativeUInt;
    solveWorkspaceRequiredPerRHS: NativeUInt;
  end;
  PSparseOpaqueFactorization_Double = ^SparseOpaqueFactorization_Double;

{ --- the exported entry points ------------------------------------------- }

{ Symbolic analysis (PARDISO phase 11). Symmetric covers Cholesky and all
  the LDLT variants; LU is its own entry point and its own macOS floor. }
function _SparseSymbolicFactorSymmetric(factorType: Byte;
  Matrix: PSparseMatrixStructure;
  options: PSparseSymbolicFactorOptions): SparseOpaqueSymbolicFactorization; cdecl; external;

function _SparseSymbolicFactorLU(factorType: Byte;
  Matrix: PSparseMatrixStructure;
  options: PSparseSymbolicFactorOptions): SparseOpaqueSymbolicFactorization; cdecl; external;

{ Numeric factorisation (PARDISO phase 22). factorStorage/workspace are
  nil here, which asks Accelerate to allocate both itself. }
function _SparseNumericFactorSymmetric_Double(symbolicFactor: PSparseOpaqueSymbolicFactorization;
  Matrix: PSparseMatrix_Double; options: PSparseNumericFactorOptions;
  factorStorage, workspace: Pointer): SparseOpaqueFactorization_Double; cdecl; external;

function _SparseNumericFactorLU_Double(symbolicFactor: PSparseOpaqueSymbolicFactorization;
  Matrix: PSparseMatrix_Double; options: PSparseNumericFactorOptions;
  factorStorage, workspace: Pointer): SparseOpaqueFactorization_Double; cdecl; external;

{ Solve (PARDISO phase 33). RHS and Soln may be the same buffer; passing
  nil workspace asks Accelerate to allocate its own. }
procedure _SparseSolveOpaque_Double(Factored: PSparseOpaqueFactorization_Double;
  RHS, Soln: PDenseMatrix_Double; workspace: Pointer); cdecl; external;

{ Release (PARDISO phase -1). }
procedure _SparseDestroyOpaqueNumeric_Double(toFree: PSparseOpaqueFactorization_Double); cdecl; external;
procedure _SparseDestroyOpaqueSymbolic(toFree: PSparseOpaqueSymbolicFactorization); cdecl; external;

{ --- helpers -------------------------------------------------------------- }

{ Packs the four meaningful bitfields into SparseAttributes_t. }
function MakeAttributes(Kind: Integer; Triangle: Integer = SparseUpperTriangle;
  Transpose: Boolean = False): SparseAttributes_t;

{ Options records filled as the header's own _SparseDefault*Options are. }
function DefaultSymbolicOptions: SparseSymbolicFactorOptions;
function DefaultNumericOptions: SparseNumericFactorOptions;

{ Maps a SparseStatus_t to the text used in the exceptions newVMsparse
  raises, so a failed Accelerate solve reads like a failed PARDISO one. }
function SparseStatusText(Status: LongInt): string;

implementation

uses
  SysUtils, Math;

function cmalloc(size: NativeUInt): Pointer; cdecl; external name 'malloc';
procedure cfree(p: Pointer); cdecl; external name 'free';

function MakeAttributes(Kind: Integer; Triangle: Integer = SparseUpperTriangle;
  Transpose: Boolean = False): SparseAttributes_t;
begin
  result := 0;
  if Transpose then result := result or $0001;        //bit 0
  result := result or (Word(Triangle and 1) shl 1);   //bit 1
  result := result or (Word(Kind and 3) shl 2);       //bits 2-3
end;

function DefaultSymbolicOptions: SparseSymbolicFactorOptions;
begin
  FillChar(result, SizeOf(result), 0);
  result.control := SparseDefaultControl;
  result.orderMethod := SparseOrderDefault;
  result.order := nil;
  result.ignoreRowsAndColumns := nil;
  result.malloc := @cmalloc;
  result.free := @cfree;
  result.reportError := nil;   //nil means "stay quiet"; status is checked instead
end;

function DefaultNumericOptions: SparseNumericFactorOptions;
begin
  FillChar(result, SizeOf(result), 0);
  result.control := SparseDefaultControl;
  result.scalingMethod := SparseScalingDefault;
  result.scaling := nil;
  //THESE TWO ARE NOT "0 MEANS LIBRARY DEFAULT" - 0 is a meaningful, and
  //catastrophic, value. pivotTolerance is the threshold partial pivoting
  //threshold (clamped to [0,0.5]); at 0 the factorisation accepts ANY
  //pivot including an exact zero, and silently returns a factorisation
  //full of infinities with status SparseStatusOK. zeroTolerance is the
  //magnitude below which an entry counts as zero.
  //
  //These are the values Accelerate's own _SparseDefaultNumericFactorOptions
  //_Double holds, read out of the live framework rather than guessed.
  //
  //Found the hard way: a 2x2 [[0,1],[1,0]] - perfectly nonsingular, but
  //needing one row interchange - solved to NaN with status OK. Every
  //earlier test passed because a 3x3 and a 2-D Laplacian both have
  //strongly nonzero diagonals and never need to pivot at all. The real
  //caller that caught it was FEM4's HFJV, whose frequency-domain block
  //system deliberately carries EXPLICIT ZERO diagonal entries (a sparse
  //direct solver wants every row to have a diagonal slot, even an empty
  //one), i.e. precisely the case where pivoting is not optional.
  result.pivotTolerance := 0.01;
  result.zeroTolerance := 2.2204460492503131e-20;
end;

function SparseStatusText(Status: LongInt): string;
begin
  case Status of
    SparseStatusOK:            result := 'ok';
    SparseFactorizationFailed: result := 'factorization failed (not positive definite, or a zero pivot)';
    SparseMatrixIsSingular:    result := 'matrix is singular';
    SparseInternalError:       result := 'internal error in Accelerate';
    SparseParameterError:      result := 'parameter error';
  else
    result := 'unknown status ' + IntToStr(Status);
  end;
end;

{ The layouts above are hand-transcribed from <Sparse/Solve.h>, and a
  wrong one does not fail loudly - it silently reads the next field from
  the wrong offset, which surfaces as a crash deep inside Accelerate with
  no hint of the cause (exactly how the 2-vs-4-byte SparseAttributes_t
  above was found). These are the sizes C reports on this machine; if a
  future SDK changes one, this stops the build here instead. }
initialization
  { THE SAME FPU-EXCEPTION TRAP THIS REPO HAS NOW HIT THREE TIMES - see
    MetalAPI.pas's header (Apple's AGX driver) and the git history's "Fix
    Windows EInvalidOp crash from MKL LAPACKE complex solve calls". FPC's
    default AArch64 FPCR leaves floating-point exception trapping armed in
    a way clang-generated code does not, and Accelerate's sparse kernels -
    like every other vendor numerical library this project has bound - are
    compiled by a toolchain that never expected a caller with traps on.

    Symptom here: _SparseSymbolicFactor* and _SparseNumericFactor* both
    return status 0, and the crash lands in _SparseSolveOpaque_Double as a
    bare EAccessViolation with no Pascal stack - which reads like a struct
    layout or lifetime bug and sent the first debugging pass chasing
    offsets. The giveaway was that the identical call sequence against the
    identical private entry points, with the identical data, ran correctly
    from clang-compiled C. Masking here, once, before any Accelerate sparse
    call in the process, fixes it; the layout was never wrong.

    If a future Accelerate (or any other native numerical) binding in this
    repo crashes inexplicably inside the library's own float code, check
    this first. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
                    exOverflow, exUnderflow, exPrecision]);

  Assert(SizeOf(SparseMatrixStructure) = 32, 'AccelerateSparse: SparseMatrixStructure must be 32 bytes');
  Assert(SizeOf(SparseMatrix_Double) = 40, 'AccelerateSparse: SparseMatrix_Double must be 40 bytes');
  Assert(SizeOf(DenseMatrix_Double) = 24, 'AccelerateSparse: DenseMatrix_Double must be 24 bytes');
  Assert(SizeOf(SparseSymbolicFactorOptions) = 48, 'AccelerateSparse: SparseSymbolicFactorOptions must be 48 bytes');
  Assert(SizeOf(SparseNumericFactorOptions) = 32, 'AccelerateSparse: SparseNumericFactorOptions must be 32 bytes');
  Assert(SizeOf(SparseOpaqueSymbolicFactorization) = 64, 'AccelerateSparse: SparseOpaqueSymbolicFactorization must be 64 bytes');
  Assert(SizeOf(SparseOpaqueFactorization_Double) = 104, 'AccelerateSparse: SparseOpaqueFactorization_Double must be 104 bytes');

end.