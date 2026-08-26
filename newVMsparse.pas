unit newVMsparse;

{*******************************************************************************

     Sparse double-precision real matrix object, leveraging Intel MKL's
     PARDISO (direct) and RCI ISS FGMRES (iterative) sparse solvers.

     Companion to newVM.pas (dense double real) - double-precision real
     only, deliberately not a fifth member of the newVM/newVMSingle/
     newVMComplex/newVMComplexSingle duplicated family (sparse solvers are
     an MKL-exclusive capability with no OpenBLAS/ArmPL/Accelerate
     equivalent, unlike the dense BLAS/LAPACK/VML routines those four units
     share). Written for the Delphi_OOFEM/FEM4 port (see that project's
     Source/ tree) but has no dependency on it - a general-purpose sparse
     type for this repo.

     TVMSparseMtx stores CSR (compressed sparse row), 0-based, matching
     newVM.pas's own row-major/0-based convention throughout - not MtxVec's
     CSC, since CSR is what PARDISO/RCI FGMRES want natively (no transpose
     step needed at the solver boundary). The only construction path is
     TripletsToSparse (bulk COO->CSR, duplicate (row,col) entries summed) -
     every sparse matrix this repo's FEM4 port builds is assembled that
     way, once per (re-)assembly, never incrementally.

     Two solver entry points:
       - PardisoSolve(A, B, SymmetricPosDef) - direct solve via MKL PARDISO.
         SymmetricPosDef=True uses mtype=2 (extracts/passes the upper
         triangle only, as PARDISO requires for symmetric types);
         SymmetricPosDef=False uses mtype=11 (general unsymmetric, full
         matrix). One-shot phase=13 (analysis+factorisation+solve combined)
         - simplicity over the performance of caching a factorisation
         across repeated solves against the same sparsity pattern.
       - FGMRESSolve(A, B, UseILU0, MaxIter, Tol) - MKL RCI ISS FGMRES,
         optionally ILU0-preconditioned (dcsrilu0), via the standard
         reverse-communication loop (dfgmres_init/dfgmres_check/dfgmres/
         dfgmres_get) driving mkl_dcsrgemv (RCI_request=1, matrix-vector
         product) and mkl_dcsrtrsv (RCI_request=3, apply the ILU0
         preconditioner via two triangular solves).
     Both raise a plain Exception on any MKL error/info code - the FEM4
     code this replaces never checked a return code from its own .Solve
     calls, so this is a small correctness improvement, not a behaviour
     change to preserve.

*******************************************************************************}

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, OneAPI, newVM;

type
  { Generic dynamic-array aliases - Dew MtxVec's Math387 unit declared
    TIntegerArray/TDoubleArray for its own triplet/BC-array plumbing, and
    CXS.FEMLAP.MtxVecExtra.pas declared TBooleanArray/PBooleanArray
    alongside its own (now-absorbed, see SetDiagonal below) SetDiagonal
    helper - all three typedef'd here so code ported from either
    convention needs no signature changes, even though these are just
    plain FPC dynamic arrays underneath. }
  TIntegerArray = array of Integer;
  TDoubleArray = array of Double;
  TBooleanArray = array of Boolean;
  PBooleanArray = ^TBooleanArray;

  { TVMSparseMtx }

  TVMSparseMtx = record
  private
    FRowPtr: array of Integer;   //CSR row pointers, 0-based, length Rows+1
    FColInd: array of Integer;   //CSR column indices, 0-based, length NonZeros; sorted ascending within each row
    FValues: array of Double;    //CSR values, length NonZeros, parallel to FColInd
    FRows, FCols: Integer;
    function GetNonZeros: Integer;
  public
    property Rows: Integer read FRows;
    property Cols: Integer read FCols;
    property NonZeros: Integer read GetNonZeros;
  end;

{ Bulk COO (triplet) -> CSR constructor - the only way to build a
  TVMSparseMtx. Duplicate (RowIdx[i],ColIdx[i]) pairs have their Val[i]
  summed (matches how FEM4's TAssembly.Add emits one triplet per
  element-pair per element - the same global (i,j) legitimately
  accumulates contributions from multiple elements). }
function TripletsToSparse(Rows, Cols: Integer; const RowIdx, ColIdx: TIntegerArray; const Val: TDoubleArray): TVMSparseMtx;

{ Extracts A's diagonal into a dense (Rows,1) TVMobj - replaces MtxVec's
  A.Diag(diag, 0). Named SparseDiag (not Diag) to avoid colliding with
  newVM.pas's own Diag (dense column-vector -> diagonal-matrix - the
  opposite operation) now that this unit uses newVM. }
function SparseDiag(const A: TVMSparseMtx): TVMobj;

{ Overwrites A's diagonal in place with Diag's values - direct port of
  Delphi_OOFEM/FEM4's CXS.FEMLAP.MtxVecExtra.SetDiagonal, now walking CSR
  (FRowPtr/FColInd) instead of MtxVec's CSC (.ap/.ai). Used by the FEM4
  port's penalty-method Dirichlet BC imposition. }
procedure SetDiagonal(var A: TVMSparseMtx; const Diag: TVMobj);

{ A+B, both same shape - replaces MtxVec's 3-arg sparse .Add(A,B,nzHint);
  no hint needed, CSR merge sizes itself. Used by transient/nonlinear FEM4
  solves to combine mass+stiffness into one effective system matrix every
  step. }
function SparseAdd(const A, B: TVMSparseMtx): TVMSparseMtx;

{ Sparse matrix x dense vector product, A*X - via the Inspector-Executor
  Sparse BLAS (mkl_sparse_d_create_csr/mkl_sparse_d_mv), the same
  machinery FGMRESSolve's own RCI_request=1 step already uses internally.
  Replaces MtxVec's TSparseMtx.MulLeft(v, out b) - used by FEM4's
  transient solves to form b := MassMatrix*PreviousTemperature every
  step. X and the result are (N,1) or (1,N) vectors. }
function SparseMatMult(const A: TVMSparseMtx; const X: TVMobj): TVMobj;

{ Direct sparse solve via MKL PARDISO. B and the result are (N,1) or (1,N)
  vectors (single right-hand side - the only shape FEM4 ever calls with).
  SymmetricPosDef picks PARDISO's mtype (2 vs 11) - see header comment. }
function PardisoSolve(const A: TVMSparseMtx; const B: TVMobj; SymmetricPosDef: Boolean): TVMobj;

{ Iterative sparse solve via MKL RCI ISS FGMRES, optionally ILU0-
  preconditioned. Same B/result shape convention as PardisoSolve. }
function FGMRESSolve(const A: TVMSparseMtx; const B: TVMobj; UseILU0: Boolean = True; MaxIter: Integer = 500; Tol: Double = 1e-8): TVMobj;

implementation

{ TVMSparseMtx }

function TVMSparseMtx.GetNonZeros: Integer;
begin
  result := Length(FValues);
end;

function TripletsToSparse(Rows, Cols: Integer; const RowIdx, ColIdx: TIntegerArray; const Val: TDoubleArray): TVMSparseMtx;
const
  s = 'Function TripletsToSparse : ';
var
  nnzIn, i, r, c, j, dst: Integer;
  rowStart, rowStart2: array of Integer; //rowStart2 is a scratch cursor copy of rowStart
  tmpColInd: array of Integer;
  tmpValues: array of Double;
  v: Double;
begin
  nnzIn := Length(RowIdx);
  assert((Rows > 0) and (Cols > 0), s+'Rows and Cols must be > 0');
  assert(Length(ColIdx) = nnzIn, s+'ColIdx must be the same length as RowIdx');
  assert(Length(Val) = nnzIn, s+'Val must be the same length as RowIdx');

  //1. Count entries per row, turn into a CSR-shaped prefix-sum row pointer
  //   for the UNMERGED (duplicates kept) triplet layout.
  SetLength(rowStart, Rows+1);
  for i := 0 to nnzIn-1 do
  begin
    assert((RowIdx[i] >= 0) and (RowIdx[i] < Rows), s+'RowIdx out of range');
    assert((ColIdx[i] >= 0) and (ColIdx[i] < Cols), s+'ColIdx out of range');
    Inc(rowStart[RowIdx[i]+1]);
  end;
  for r := 1 to Rows do rowStart[r] := rowStart[r] + rowStart[r-1];

  //2. Scatter triplets into row-bucketed (unmerged) order.
  SetLength(tmpColInd, nnzIn);
  SetLength(tmpValues, nnzIn);
  SetLength(rowStart2, Rows);
  for r := 0 to Rows-1 do rowStart2[r] := rowStart[r];
  for i := 0 to nnzIn-1 do
  begin
    r := RowIdx[i];
    dst := rowStart2[r];
    tmpColInd[dst] := ColIdx[i];
    tmpValues[dst] := Val[i];
    rowStart2[r] := dst + 1;
  end;

  //3. Per row: insertion-sort by column (FEM stencils are narrow, so this
  //   is fine - no need for a general-purpose sort here), then merge
  //   adjacent equal columns by summing, writing straight into the result.
  result.FRows := Rows;
  result.FCols := Cols;
  SetLength(result.FRowPtr, Rows+1);
  SetLength(result.FColInd, nnzIn); //upper bound; trimmed below
  SetLength(result.FValues, nnzIn);
  dst := 0;
  result.FRowPtr[0] := 0;
  for r := 0 to Rows-1 do
  begin
    for i := rowStart[r]+1 to rowStart[r+1]-1 do
    begin
      c := tmpColInd[i];
      v := tmpValues[i];
      j := i-1;
      while (j >= rowStart[r]) and (tmpColInd[j] > c) do
      begin
        tmpColInd[j+1] := tmpColInd[j];
        tmpValues[j+1] := tmpValues[j];
        Dec(j);
      end;
      tmpColInd[j+1] := c;
      tmpValues[j+1] := v;
    end;

    i := rowStart[r];
    while i <= rowStart[r+1]-1 do
    begin
      c := tmpColInd[i];
      v := tmpValues[i];
      Inc(i);
      while (i <= rowStart[r+1]-1) and (tmpColInd[i] = c) do
      begin
        v := v + tmpValues[i];
        Inc(i);
      end;
      result.FColInd[dst] := c;
      result.FValues[dst] := v;
      Inc(dst);
    end;
    result.FRowPtr[r+1] := dst;
  end;
  SetLength(result.FColInd, dst);
  SetLength(result.FValues, dst);
end;

function SparseDiag(const A: TVMSparseMtx): TVMobj;
const
  s = 'Function SparseDiag : ';
var
  r, k: Integer;
begin
  assert(A.Rows = A.Cols, s+'A must be square');
  result := TVMobj.Create(A.Rows, 1);
  for r := 0 to A.Rows-1 do
    for k := A.FRowPtr[r] to A.FRowPtr[r+1]-1 do
      if A.FColInd[k] = r then
        result[r,0] := A.FValues[k];
end;

procedure SetDiagonal(var A: TVMSparseMtx; const Diag: TVMobj);
const
  s = 'Procedure SetDiagonal : ';
var
  r, k: Integer;
begin
  assert(Diag.Rows*Diag.Cols = A.Rows, s+'Diag''s length must equal A.Rows');
  for r := 0 to A.Rows-1 do
    for k := A.FRowPtr[r] to A.FRowPtr[r+1]-1 do
      if A.FColInd[k] = r then
        A.FValues[k] := Diag.DataPtr[r];
end;

function SparseAdd(const A, B: TVMSparseMtx): TVMSparseMtx;
const
  s = 'Function SparseAdd : ';
var
  r, ka, kb, dst, maxNnz: Integer;
begin
  assert((A.Rows = B.Rows) and (A.Cols = B.Cols), s+'A and B must be the same shape');
  result.FRows := A.Rows;
  result.FCols := A.Cols;
  maxNnz := A.NonZeros + B.NonZeros;
  SetLength(result.FRowPtr, A.Rows+1);
  SetLength(result.FColInd, maxNnz);
  SetLength(result.FValues, maxNnz);
  dst := 0;
  result.FRowPtr[0] := 0;
  for r := 0 to A.Rows-1 do
  begin
    ka := A.FRowPtr[r];
    kb := B.FRowPtr[r];
    while (ka < A.FRowPtr[r+1]) or (kb < B.FRowPtr[r+1]) do
    begin
      if (kb >= B.FRowPtr[r+1]) or ((ka < A.FRowPtr[r+1]) and (A.FColInd[ka] < B.FColInd[kb])) then
      begin
        result.FColInd[dst] := A.FColInd[ka];
        result.FValues[dst] := A.FValues[ka];
        Inc(ka); Inc(dst);
      end
      else if (ka >= A.FRowPtr[r+1]) or ((kb < B.FRowPtr[r+1]) and (B.FColInd[kb] < A.FColInd[ka])) then
      begin
        result.FColInd[dst] := B.FColInd[kb];
        result.FValues[dst] := B.FValues[kb];
        Inc(kb); Inc(dst);
      end
      else
      begin
        result.FColInd[dst] := A.FColInd[ka];
        result.FValues[dst] := A.FValues[ka] + B.FValues[kb];
        Inc(ka); Inc(kb); Inc(dst);
      end;
    end;
    result.FRowPtr[r+1] := dst;
  end;
  SetLength(result.FColInd, dst);
  SetLength(result.FValues, dst);
end;

{ Filters A down to its upper triangle (col >= row), including the
  diagonal - what PARDISO's mtype=2 (symmetric positive definite) requires
  (only one triangle stored). Relies on each row's entries being
  column-sorted, an invariant TripletsToSparse and SparseAdd both
  maintain. }
function ExtractUpperCSR(const A: TVMSparseMtx): TVMSparseMtx;
var
  r, k, dst: Integer;
begin
  result.FRows := A.Rows;
  result.FCols := A.Cols;
  SetLength(result.FRowPtr, A.Rows+1);
  SetLength(result.FColInd, A.NonZeros);
  SetLength(result.FValues, A.NonZeros);
  dst := 0;
  result.FRowPtr[0] := 0;
  for r := 0 to A.Rows-1 do
  begin
    for k := A.FRowPtr[r] to A.FRowPtr[r+1]-1 do
      if A.FColInd[k] >= r then
      begin
        result.FColInd[dst] := A.FColInd[k];
        result.FValues[dst] := A.FValues[k];
        Inc(dst);
      end;
    result.FRowPtr[r+1] := dst;
  end;
  SetLength(result.FColInd, dst);
  SetLength(result.FValues, dst);
end;

function SparseMatMult(const A: TVMSparseMtx; const X: TVMobj): TVMobj;
const
  s = 'Function SparseMatMult : ';
var
  n, i, st: Integer;
  Ahandle: Pointer;
  descrGeneral: TMKLMatrixDescr;
  xvec, yvec: array of Double;
begin
  assert(A.Cols = X.Rows*X.Cols, s+'X''s length must equal A.Cols');
  n := A.Rows;

  Ahandle := nil;
  st := mkl_sparse_d_create_csr(@Ahandle, SPARSE_INDEX_BASE_ZERO, A.Rows, A.Cols,
    @A.FRowPtr[0], @A.FRowPtr[1], @A.FColInd[0], @A.FValues[0]);
  if st <> SPARSE_STATUS_SUCCESS then
    raise Exception.Create(s + 'mkl_sparse_d_create_csr failed, status ' + IntToStr(st));
  descrGeneral.mtype := SPARSE_MATRIX_TYPE_GENERAL;
  descrGeneral.mode := 0;
  descrGeneral.diag := 0;

  SetLength(xvec, A.Cols);
  for i := 0 to A.Cols-1 do xvec[i] := X.DataPtr[i];
  SetLength(yvec, n);

  st := mkl_sparse_d_mv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, Ahandle, descrGeneral,
    @xvec[0], 0.0, @yvec[0]);
  mkl_sparse_destroy(Ahandle);
  if st <> SPARSE_STATUS_SUCCESS then
    raise Exception.Create(s + 'mkl_sparse_d_mv failed, status ' + IntToStr(st));

  result := TVMobj.Create(n, 1);
  for i := 0 to n-1 do result.DataPtr[i] := yvec[i];
end;

{ Both PARDISO's own mtype=2/11 factorisation and the RCI FGMRES/dcsrilu0
  path (see FGMRESSolve below) require every row to carry an explicitly
  stored diagonal entry - a row that's structurally missing one (not
  merely a zero-valued one; genuinely absent from the CSR pattern) isn't
  a case either routine reports cleanly. dcsrilu0 raises a clear "no
  diagonal in CSR format" error for it (see newVMsparse.pas's own git
  history for the Ex16 bug this caught); PARDISO instead segfaults deep
  inside its own closed-source METIS reordering step with no useful
  diagnostic at all (the Ex35/ThermalEngine crash this check was added
  for - a 24822-row transient thermal matrix with at least one row never
  touched by any element's diagonal contribution). Checking up front is
  O(NonZeros) - negligible next to the O(N^1.5) or worse factorisation
  cost - and turns an opaque access violation into a specific row index. }
function FindMissingDiagonalRow(const A: TVMSparseMtx): Integer;
var
  r, k: Integer;
  found: Boolean;
begin
  result := -1;
  for r := 0 to A.Rows-1 do
  begin
    found := False;
    for k := A.FRowPtr[r] to A.FRowPtr[r+1]-1 do
      if A.FColInd[k] = r then
      begin
        found := True;
        Break;
      end;
    if not found then
    begin
      result := r;
      Exit;
    end;
  end;
end;

function PardisoSolve(const A: TVMSparseMtx; const B: TVMobj; SymmetricPosDef: Boolean): TVMobj;
const
  s = 'Function PardisoSolve : ';
var
  Asolve: TVMSparseMtx;
  pt: array[0..63] of Pointer;
  iparm: array[0..63] of Integer;
  mtype, maxfct, mnum, phase, n, nrhs, msglvl, error: Integer;
  perm: array of Integer;
  Bcopy, X: TVMobj;
  badRow: Integer;
begin
  assert(A.Rows = A.Cols, s+'A must be square');
  assert(B.Rows*B.Cols = A.Rows, s+'B must be a vector of length A.Rows');

  badRow := FindMissingDiagonalRow(A);
  if badRow >= 0 then
    raise Exception.Create(s + 'row ' + IntToStr(badRow) + ' of A has no ' +
      'diagonal entry (structurally absent from the sparsity pattern, not ' +
      'merely zero-valued) - PARDISO cannot factorise this matrix. This ' +
      'usually means node ' + IntToStr(badRow) + ' was never touched by ' +
      'any element''s stiffness/mass contribution during assembly (a ' +
      'disconnected node, or an Assembly.Add call with the wrong node ' +
      'count for its element type).');

  if SymmetricPosDef then
  begin
    Asolve := ExtractUpperCSR(A);
    mtype := 2;
  end
  else
  begin
    Asolve := A;
    mtype := 11;
  end;

  FillChar(pt, SizeOf(pt), 0);
  FillChar(iparm, SizeOf(iparm), 0);
  pardisoinit(@pt[0], @mtype, @iparm[0]);
  iparm[34] := 1; //zero-based row/column indexing, matching this unit's CSR

  n := A.Rows;
  SetLength(perm, n);
  maxfct := 1; mnum := 1; nrhs := 1; msglvl := 0;
  Bcopy := CopyObj(B); //PARDISO may use b as working storage; never mutate the caller's B
  X := TVMobj.Create(n, 1);

  phase := 13; //analysis + numerical factorisation + solve, combined
  error := 0;
  pardiso(@pt[0], @maxfct, @mnum, @mtype, @phase, @n,
    @Asolve.FValues[0], @Asolve.FRowPtr[0], @Asolve.FColInd[0],
    @perm[0], @nrhs, @iparm[0], @msglvl, Bcopy.DataPtr, X.DataPtr, @error);

  phase := -1; //release all internal PARDISO memory tied to pt, regardless of outcome
  pardiso(@pt[0], @maxfct, @mnum, @mtype, @phase, @n,
    @Asolve.FValues[0], @Asolve.FRowPtr[0], @Asolve.FColInd[0],
    @perm[0], @nrhs, @iparm[0], @msglvl, Bcopy.DataPtr, X.DataPtr, @error);

  if error <> 0 then
    raise Exception.Create(s + 'PARDISO reported error code ' + IntToStr(error));

  result := X;
end;

function FGMRESSolve(const A: TVMSparseMtx; const B: TVMobj; UseILU0: Boolean; MaxIter: Integer; Tol: Double): TVMobj;
const
  s = 'Function FGMRESSolve : ';
var
  n, restart, tmpSize, i, st: Integer;
  ia1, ja1: array of Integer; //1-based CSR copies, for the legacy dcsrilu0 call only
  ipar: array[0..127] of Integer;
  dpar: array[0..127] of Double;
  tmp, bilu0, trvec, xvec, bvec: array of Double;
  RCI_request, itercount, ierr: Integer;
  Ahandle, ILU0handle: Pointer;
  descrGeneral, descrL, descrU: TMKLMatrixDescr;
  X: TVMobj;
begin
  assert(A.Rows = A.Cols, s+'A must be square');
  assert(B.Rows*B.Cols = A.Rows, s+'B must be a vector of length A.Rows');
  n := A.Rows;

  //Inspector-Executor handle for A itself, used for the RCI_request=1
  //matrix-vector product step below. rows_start/rows_end are two views
  //into the same 0-based FRowPtr array (rows_start[i]=FRowPtr[i],
  //rows_end[i]=FRowPtr[i+1]) - the standard "3-array CSR" compatibility
  //trick this API documents for exactly this case.
  Ahandle := nil;
  st := mkl_sparse_d_create_csr(@Ahandle, SPARSE_INDEX_BASE_ZERO, n, n,
    @A.FRowPtr[0], @A.FRowPtr[1], @A.FColInd[0], @A.FValues[0]);
  if st <> SPARSE_STATUS_SUCCESS then
    raise Exception.Create(s + 'mkl_sparse_d_create_csr(A) failed, status ' + IntToStr(st));
  descrGeneral.mtype := SPARSE_MATRIX_TYPE_GENERAL;
  descrGeneral.mode := 0;
  descrGeneral.diag := 0;

  if UseILU0 then
  begin
    //dcsrilu0 (legacy interface) still wants 1-based ia/ja.
    SetLength(ia1, n+1);
    for i := 0 to n do ia1[i] := A.FRowPtr[i] + 1;
    SetLength(ja1, Length(A.FColInd));
    for i := 0 to High(ja1) do ja1[i] := A.FColInd[i] + 1;
  end;

  restart := Min(150, n);
  { MKL's documented minimum is (2*restart+1)*n + restart*(restart+9) div 2
    + 1. A generous fixed safety margin is added on top - cheap for
    FEM-scale problems, and closes off any risk from this formula being
    exactly-sized with zero slack against a documented minimum (a rare,
    non-deterministic heap-corruption crash was observed once during
    development with the exact minimum size, never reproduced again across
    dozens of reruns - consistent with a margin-dependent issue rather than
    a clear logic bug; not worth leaving zero headroom against). }
  tmpSize := (2*restart+1)*n + restart*(restart+9) div 2 + 1 + 64*(n+restart);
  SetLength(tmp, tmpSize);
  SetLength(xvec, n);
  SetLength(bvec, n);
  for i := 0 to n-1 do
  begin
    xvec[i] := 0.0;
    bvec[i] := B.DataPtr[i];
  end;

  FillChar(ipar, SizeOf(ipar), 0);
  FillChar(dpar, SizeOf(dpar), 0);
  RCI_request := 0;
  dfgmres_init(@n, @xvec[0], @bvec[0], @RCI_request, @ipar[0], @dpar[0], @tmp[0]);
  if RCI_request <> 0 then
    raise Exception.Create(s + 'dfgmres_init failed, code ' + IntToStr(RCI_request));

  ipar[4] := MaxIter;        //Fortran ipar(5): max iterations
  ipar[9] := 0;               //Fortran ipar(10): no user-defined stopping test
  ipar[10] := Ord(UseILU0);   //Fortran ipar(11): preconditioning on/off
  ipar[11] := 1;               //Fortran ipar(12): let dfgmres auto-check for a
                                //zero-norm current vector, rather than asking
                                //the caller to via RCI_request=4 - this MKL
                                //version's dfgmres_init does NOT default this
                                //to 1 itself (confirmed empirically: omitting
                                //this line produces an actual RCI_request=4).
  ipar[14] := restart;        //Fortran ipar(15): non-restarted iteration count
  dpar[0] := Tol;              //Fortran dpar(1): relative tolerance

  ILU0handle := nil;
  if UseILU0 then
  begin
    SetLength(bilu0, Length(A.FValues));
    ierr := 0;
    dcsrilu0(@n, @A.FValues[0], @ia1[0], @ja1[0], @bilu0[0], @ipar[0], @dpar[0], @ierr);
    if ierr <> 0 then
      raise Exception.Create(s + 'dcsrilu0 (ILU0 factorisation) failed, code ' + IntToStr(ierr));
    SetLength(trvec, n);

    //One Inspector-Executor handle over the packed L\U factors, reused for
    //both triangular solves below via a different descr each time (L is
    //implicitly unit-diagonal, U carries the real factorised diagonal).
    st := mkl_sparse_d_create_csr(@ILU0handle, SPARSE_INDEX_BASE_ZERO, n, n,
      @A.FRowPtr[0], @A.FRowPtr[1], @A.FColInd[0], @bilu0[0]);
    if st <> SPARSE_STATUS_SUCCESS then
      raise Exception.Create(s + 'mkl_sparse_d_create_csr(ILU0) failed, status ' + IntToStr(st));
    descrL.mtype := SPARSE_MATRIX_TYPE_TRIANGULAR; descrL.mode := SPARSE_FILL_MODE_LOWER; descrL.diag := SPARSE_DIAG_UNIT;
    descrU.mtype := SPARSE_MATRIX_TYPE_TRIANGULAR; descrU.mode := SPARSE_FILL_MODE_UPPER; descrU.diag := SPARSE_DIAG_NON_UNIT;
  end;

  dfgmres_check(@n, @xvec[0], @bvec[0], @RCI_request, @ipar[0], @dpar[0], @tmp[0]);
  if RCI_request <> 0 then
    raise Exception.Create(s + 'dfgmres_check reported invalid parameters, code ' + IntToStr(RCI_request));

  RCI_request := 0;
  repeat
    dfgmres(@n, @xvec[0], @bvec[0], @RCI_request, @ipar[0], @dpar[0], @tmp[0]);
    case RCI_request of
      0: Break;
      1: begin
           st := mkl_sparse_d_mv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, Ahandle, descrGeneral,
             @tmp[ipar[21]-1], 0.0, @tmp[ipar[22]-1]);
           if st <> SPARSE_STATUS_SUCCESS then
             raise Exception.Create(s + 'mkl_sparse_d_mv failed, status ' + IntToStr(st));
         end;
      3: begin
           if not UseILU0 then
             raise Exception.Create(s + 'solver requested preconditioning but UseILU0=False');
           st := mkl_sparse_d_trsv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, ILU0handle, descrL, @tmp[ipar[21]-1], @trvec[0]);
           if st <> SPARSE_STATUS_SUCCESS then
             raise Exception.Create(s + 'mkl_sparse_d_trsv(L) failed, status ' + IntToStr(st));
           st := mkl_sparse_d_trsv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, ILU0handle, descrU, @trvec[0], @tmp[ipar[22]-1]);
           if st <> SPARSE_STATUS_SUCCESS then
             raise Exception.Create(s + 'mkl_sparse_d_trsv(U) failed, status ' + IntToStr(st));
         end;
      4: raise Exception.Create(s + 'unexpected user-defined residual-norm check request');
    else
      raise Exception.Create(s + 'FGMRES failed, RCI_request=' + IntToStr(RCI_request));
    end;
  until False;

  ipar[12] := 0; //Fortran ipar(13): 0 = copy the solution into x automatically
  itercount := 0;
  dfgmres_get(@n, @xvec[0], @bvec[0], @RCI_request, @ipar[0], @dpar[0], @tmp[0], @itercount);

  mkl_sparse_destroy(Ahandle);
  if ILU0handle <> nil then mkl_sparse_destroy(ILU0handle);

  X := TVMobj.Create(n, 1);
  for i := 0 to n-1 do X.DataPtr[i] := xvec[i];
  result := X;
end;

end.
