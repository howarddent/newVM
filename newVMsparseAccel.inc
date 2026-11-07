{ ---------------------------------------------------------------------------
  newVMsparse.pas's Accelerate back end - included at the end of that unit's
  implementation, and compiled only when HAVE_MKL is undefined. Provides the
  same four public entry points PARDISO/RCI FGMRES provide above, so a
  caller (FEM4, hfjvrun, newVMsparsetest) needs no change:

    PardisoSolve    -> Accelerate SparseFactor/SparseSolve (Cholesky or LU)
    TPardisoFactor  -> the same, kept alive across repeated solves
    FGMRESSolve     -> GMRES(m) with optional ILU(0), implemented here

  WHY FGMRES IS HAND-WRITTEN WHILE THE DIRECT SOLVE IS NOT. Accelerate does
  ship iterative solvers (_SparseCGSolve/_SparseGMRESSolve), but they are
  unusable here for two independent reasons: their preconditioner set is
  None/User/Diagonal/DiagScaling with no ILU(0) at all, and the operator and
  user preconditioner are passed as Objective-C BLOCKS, which FPC cannot
  construct from Pascal in Delphi mode. GMRES with Givens rotations plus
  an ILU(0) on CSR is, by contrast, a well-defined few hundred lines with no
  binding risk and exact control over the stopping test - which matters,
  because the contract being matched is MKL's dfgmres, whose tolerance is
  relative to the INITIAL residual.

  This is the one place this file departs from CLAUDE.md's "don't hand-roll
  a sparse solver here" rule, and deliberately: that rule is about the
  DIRECT solver (PARDISO's supernodal factorisation), which is exactly what
  is NOT hand-rolled - Accelerate's is a real supernodal implementation with
  fill-reducing ordering. A restarted Krylov method is a different order of
  undertaking from a sparse LU, and without it half this unit's interface
  would simply be missing on Darwin.
  --------------------------------------------------------------------------- }

{ Maps PARDISO's mtype onto Accelerate's factorisation type:
    11 real unsymmetric       -> LU         (full matrix)
     2 real symmetric pos def -> Cholesky   (lower triangle only)
    -2 real symmetric indef   -> LDLT       (lower triangle only)
  Symmetric is returned separately because it decides both which triangle
  ToCSC extracts and which pair of entry points is called. }
procedure AccelFactorKind(MType: Integer; out FactorType: Byte; out Symmetric: Boolean);
const
  s = 'TPardisoFactor : ';
begin
  case MType of
    11: begin FactorType := SparseFactorizationLU;       Symmetric := False; end;
     2: begin FactorType := SparseFactorizationCholesky; Symmetric := True;  end;
    -2: begin FactorType := SparseFactorizationLDLT;     Symmetric := True;  end;
  else
    raise Exception.Create(s + 'unsupported MType ' + IntToStr(MType) +
      ' on the Accelerate back end (11 unsymmetric, 2 symmetric positive definite, -2 symmetric indefinite)');
  end;
end;

{ Analysis + numerical factorisation, i.e. PARDISO's phases 11 and 22. The
  private Accelerate entry points, unlike the public inline wrappers, do NOT
  allocate their own factor storage or scratch workspace - passing nil for
  either crashes inside the library - so both are allocated here from the
  sizes the symbolic factorisation reports. Workspace is scratch and freed
  as soon as the numeric factorisation returns; Store holds the factors and
  must live exactly as long as Num does. }
procedure AccelFactor(const M: SparseMatrix_Double; FactorType: Byte; Symmetric: Boolean;
  out Sym: SparseOpaqueSymbolicFactorization; out Num: SparseOpaqueFactorization_Double;
  out Store: Pointer);
const
  s = 'Accelerate sparse factorisation : ';
var
  so: SparseSymbolicFactorOptions;
  no: SparseNumericFactorOptions;
  ws: Pointer;
begin
  so := DefaultSymbolicOptions;
  no := DefaultNumericOptions;

  if Symmetric then
    Sym := _SparseSymbolicFactorSymmetric(FactorType, @M.structure, @so)
  else
    Sym := _SparseSymbolicFactorLU(FactorType, @M.structure, @so);
  if Sym.status <> SparseStatusOK then
    raise Exception.Create(s + 'symbolic factorisation failed: ' + SparseStatusText(Sym.status));

  Store := GetMem(Sym.factorSize_Double);
  ws := GetMem(Sym.workspaceSize_Double);
  try
    if Symmetric then
      Num := _SparseNumericFactorSymmetric_Double(@Sym, @M, @no, Store, ws)
    else
      Num := _SparseNumericFactorLU_Double(@Sym, @M, @no, Store, ws);
  finally
    FreeMem(ws);
  end;

  if Num.status <> SparseStatusOK then
  begin
    _SparseDestroyOpaqueSymbolic(@Sym);
    FreeMem(Store);
    Store := nil;
    raise Exception.Create(s + 'numerical factorisation failed: ' + SparseStatusText(Num.status));
  end;
end;

{ PARDISO phase 33. B and X may be the same buffer. }
procedure AccelSolveWith(var Num: SparseOpaqueFactorization_Double; Bp, Xp: PDouble; n: Integer);
var
  Bm, Xm: DenseMatrix_Double;
  ws: Pointer;
begin
  Bm := AccelVector(Bp, n);
  Xm := AccelVector(Xp, n);
  ws := GetMem(Num.solveWorkspaceRequiredStatic + 1 * Num.solveWorkspaceRequiredPerRHS);
  try
    _SparseSolveOpaque_Double(@Num, @Bm, @Xm, ws);
  finally
    FreeMem(ws);
  end;
end;

function PardisoSolve(const A: TVMSparseMtx; const B: TVMobj; SymmetricPosDef: Boolean): TVMobj;
const
  s = 'Function PardisoSolve : ';
var
  n, r: Integer;
  C: TAccelCSC;
  M: SparseMatrix_Double;
  Sym: SparseOpaqueSymbolicFactorization;
  Num: SparseOpaqueFactorization_Double;
  Store: Pointer;
  FactorType: Byte;
  Symmetric: Boolean;
  Bcopy: TVMobj;
begin
  assert(A.Rows = A.Cols, s+'A must be square');
  assert(A.Rows = B.Rows*B.Cols, s+'B''s length must equal A.Rows');
  n := A.Rows;

  //Same up-front scan the MKL path runs: a structurally missing diagonal
  //entry is a factorisation failure in any sparse direct solver, and is
  //far better reported as a row index than as whatever the library does
  //with it. See the MKL path's own comment for the Ex35 crash behind it.
  r := FindMissingDiagonalRow(A);
  if r >= 0 then
    raise Exception.Create(s + 'row ' + IntToStr(r) +
      ' has no explicitly stored diagonal entry - a sparse direct factorisation requires one in every row');

  if SymmetricPosDef then
  begin
    AccelFactorKind(2, FactorType, Symmetric);
    C := ToCSC(A, True);          //lower triangle only, as Cholesky wants
  end
  else
  begin
    AccelFactorKind(11, FactorType, Symmetric);
    C := ToCSC(A, False);
  end;
  M := AccelMatrix(C, n, n, Symmetric);

  AccelFactor(M, FactorType, Symmetric, Sym, Num, Store);
  try
    //B is copied: the caller's B must never be mutated, and the solve is
    //given its own output buffer anyway.
    Bcopy := CopyObj(B);
    result := TVMobj.Create(n, 1);
    AccelSolveWith(Num, Bcopy.DataPtr, result.DataPtr, n);
  finally
    _SparseDestroyOpaqueNumeric_Double(@Num);
    _SparseDestroyOpaqueSymbolic(@Sym);
    FreeMem(Store);
  end;
end;

{ TPardisoFactor - a factorisation kept for repeated solves. Create does
  phases 11+22, Solve phase 33, Destroy phase -1, exactly as the MKL
  version does. }

constructor TPardisoFactor.Create(const A: TVMSparseMtx; MType: Integer);
const
  s = 'TPardisoFactor.Create : ';
var
  r: Integer;
  M: SparseMatrix_Double;
  FactorType: Byte;
  Symmetric: Boolean;
begin
  inherited Create;
  assert(A.Rows = A.Cols, s+'A must be square');
  FA := A;
  FN := A.Rows;
  FMType := MType;
  FStore := nil;

  r := FindMissingDiagonalRow(A);
  if r >= 0 then
    raise Exception.Create(s + 'row ' + IntToStr(r) +
      ' has no explicitly stored diagonal entry - a sparse direct factorisation requires one in every row');

  AccelFactorKind(MType, FactorType, Symmetric);
  //FCSC is a field, not a local: Accelerate's SparseMatrixStructure only
  //points at these arrays, and they have to stay valid for every later
  //Solve, not just for the factorisation call.
  FCSC := ToCSC(A, Symmetric);
  M := AccelMatrix(FCSC, FN, FN, Symmetric);
  AccelFactor(M, FactorType, Symmetric, FSym, FNum, FStore);
end;

function TPardisoFactor.Solve(const B: TVMobj): TVMobj;
const
  s = 'TPardisoFactor.Solve : ';
var
  Bcopy: TVMobj;
begin
  assert(FN = B.Rows*B.Cols, s+'B''s length must equal N');
  Bcopy := CopyObj(B);
  result := TVMobj.Create(FN, 1);
  AccelSolveWith(FNum, Bcopy.DataPtr, result.DataPtr, FN);
end;

destructor TPardisoFactor.Destroy;
begin
  if FStore <> nil then
  begin
    _SparseDestroyOpaqueNumeric_Double(@FNum);
    _SparseDestroyOpaqueSymbolic(@FSym);
    FreeMem(FStore);
    FStore := nil;
  end;
  inherited Destroy;
end;

{ ---------------------------------------------------------------------------
  FGMRESSolve: restarted GMRES with optional ILU(0).

  Right-preconditioned GMRES(m): solve A*M^-1*y = b, x = M^-1*y. Right rather
  than left preconditioning because the Arnoldi residual norm is then the
  norm of the TRUE residual, so the stopping test needs no extra
  matrix-vector product per iteration and means the same thing as MKL's.
  --------------------------------------------------------------------------- }

{ ILU(0): an incomplete LU sharing A's own sparsity pattern exactly - no
  fill-in is kept. The factors come back packed into one L\\U buffer parallel
  to A's CSR arrays (unit lower triangle implied, not stored), which is the
  same packing MKL's dcsrilu0 produces, so ILUApply below reads it the same
  way the MKL path's two triangular solves do.

  The IKJ ordering is the standard one: for each row i, eliminate against
  every earlier row k that row i actually touches. Diag[] caches the offset
  of each row's diagonal entry, which both the elimination and the solves
  need; the caller has already guaranteed one exists in every row. }
procedure ILU0(const A: TVMSparseMtx; out LU: TDoubleArray; out Diag: TIntegerArray);
const
  s = 'Function FGMRESSolve : ';
var
  n, i, j, k, kk, jj, jw: Integer;
  mult: Double;
  pos: TIntegerArray;    //column -> offset in the current row, or -1
begin
  n := A.Rows;
  SetLength(LU, Length(A.FValues));
  if Length(LU) > 0 then
    Move(A.FValues[0], LU[0], Length(LU)*SizeOf(Double));
  SetLength(Diag, n);
  SetLength(pos, A.Cols);
  for i := 0 to A.Cols - 1 do pos[i] := -1;

  for i := 0 to n - 1 do
  begin
    //Scatter row i's pattern so a column can be located in O(1).
    for k := A.FRowPtr[i] to A.FRowPtr[i+1] - 1 do
      pos[A.FColInd[k]] := k;

    Diag[i] := -1;
    for k := A.FRowPtr[i] to A.FRowPtr[i+1] - 1 do
      if A.FColInd[k] = i then begin Diag[i] := k; Break; end;
    if Diag[i] < 0 then
      raise Exception.Create(s + 'ILU0: row ' + IntToStr(i) + ' has no diagonal entry');

    //Eliminate against each earlier row k in ascending column order.
    k := A.FRowPtr[i];
    while (k < A.FRowPtr[i+1]) and (A.FColInd[k] < i) do
    begin
      j := A.FColInd[k];                 //the earlier row to eliminate with
      if LU[Diag[j]] = 0.0 then
        raise Exception.Create(s + 'ILU0: zero pivot in row ' + IntToStr(j));
      mult := LU[k] / LU[Diag[j]];
      LU[k] := mult;                     //L's multiplier, stored in place
      //Row i -= mult * row j, but only where row i already has an entry.
      for kk := Diag[j] + 1 to A.FRowPtr[j+1] - 1 do
      begin
        jj := A.FColInd[kk];
        jw := pos[jj];
        if jw >= 0 then
          LU[jw] := LU[jw] - mult * LU[kk];
      end;
      Inc(k);
    end;

    if LU[Diag[i]] = 0.0 then
      raise Exception.Create(s + 'ILU0: zero pivot in row ' + IntToStr(i));

    //Reset the scatter for the next row.
    for k := A.FRowPtr[i] to A.FRowPtr[i+1] - 1 do
      pos[A.FColInd[k]] := -1;
  end;
end;

{ Applies the ILU(0) preconditioner: z := U^-1 * L^-1 * r, a forward solve
  against the unit lower triangle then a back solve against U. }
procedure ILUApply(const A: TVMSparseMtx; const LU: TDoubleArray;
  const Diag: TIntegerArray; const r: TDoubleArray; var z: TDoubleArray);
var
  n, i, k: Integer;
  acc: Double;
begin
  n := A.Rows;
  //Forward: L has an implied unit diagonal, so no division here.
  for i := 0 to n - 1 do
  begin
    acc := r[i];
    for k := A.FRowPtr[i] to Diag[i] - 1 do
      acc := acc - LU[k] * z[A.FColInd[k]];
    z[i] := acc;
  end;
  //Back: U carries its own diagonal.
  for i := n - 1 downto 0 do
  begin
    acc := z[i];
    for k := Diag[i] + 1 to A.FRowPtr[i+1] - 1 do
      acc := acc - LU[k] * z[A.FColInd[k]];
    z[i] := acc / LU[Diag[i]];
  end;
end;

{ y := A*x over raw buffers (SparseMatMult's TVMobj wrapper would allocate
  a fresh result on every one of the thousands of iterations below). }
procedure CSRMul(const A: TVMSparseMtx; const x: TDoubleArray; var y: TDoubleArray);
var
  r, k: Integer;
  acc: Double;
begin
  for r := 0 to A.Rows - 1 do
  begin
    acc := 0.0;
    for k := A.FRowPtr[r] to A.FRowPtr[r+1] - 1 do
      acc := acc + A.FValues[k] * x[A.FColInd[k]];
    y[r] := acc;
  end;
end;

function FGMRESSolve(const A: TVMSparseMtx; const B: TVMobj; UseILU0: Boolean;
  MaxIter: Integer; Tol: Double; Restart: Integer): TVMobj;
const
  s = 'Function FGMRESSolve : ';
var
  n, m, i, j, k, inner, total: Integer;
  LU: TDoubleArray;
  Diag: TIntegerArray;
  V: array of TDoubleArray;      //Arnoldi basis, m+1 vectors of length n
  Z: array of TDoubleArray;      //preconditioned basis (flexible form)
  H: array of TDoubleArray;      //Hessenberg, column-major: H[j][0..j+1]
  cs, sn, g, yv: TDoubleArray;
  x, r, w: TDoubleArray;
  Bp: PDouble;
  beta, bnorm, hv, denom, tmp, resid, target: Double;
  converged: Boolean;
begin
  assert(A.Rows = A.Cols, s+'A must be square');
  assert(A.Rows = B.Rows*B.Cols, s+'B''s length must equal A.Rows');
  n := A.Rows;
  m := Restart;
  if m > n then m := n;
  if m < 1 then m := 1;

  if UseILU0 then
    ILU0(A, LU, Diag);

  SetLength(x, n); SetLength(r, n); SetLength(w, n);
  SetLength(V, m+1); SetLength(Z, m+1);
  for i := 0 to m do begin SetLength(V[i], n); SetLength(Z[i], n); end;
  SetLength(H, m); for j := 0 to m-1 do SetLength(H[j], m+1);
  SetLength(cs, m); SetLength(sn, m); SetLength(g, m+1); SetLength(yv, m);

  Bp := B.DataPtr;
  bnorm := 0.0;
  for i := 0 to n-1 do begin x[i] := 0.0; bnorm := bnorm + Sqr(Bp[i]); end;
  bnorm := Sqrt(bnorm);
  if bnorm = 0.0 then
  begin
    //A zero right-hand side has the zero solution; nothing to iterate on.
    result := TVMobj.Create(n, 1);
    Exit;
  end;

  //MKL's dfgmres stops on ||r_k|| <= Tol * ||r_0||, and with x0 = 0 that
  //initial residual is b itself. Matching that exactly is the whole reason
  //this is right-preconditioned - see this file's header.
  target := Tol * bnorm;
  total := 0;
  converged := False;

  while (total < MaxIter) and (not converged) do
  begin
    //r := b - A*x, and start a new Krylov space from it.
    CSRMul(A, x, w);
    beta := 0.0;
    for i := 0 to n-1 do begin r[i] := Bp[i] - w[i]; beta := beta + Sqr(r[i]); end;
    beta := Sqrt(beta);
    if beta <= target then begin converged := True; Break; end;

    for i := 0 to n-1 do V[0][i] := r[i] / beta;
    for i := 0 to m do g[i] := 0.0;
    g[0] := beta;

    inner := 0;
    for j := 0 to m-1 do
    begin
      if total >= MaxIter then Break;
      Inc(total); inner := j + 1;

      //z_j := M^-1 v_j, then w := A z_j.
      if UseILU0 then ILUApply(A, LU, Diag, V[j], Z[j])
      else for i := 0 to n-1 do Z[j][i] := V[j][i];
      CSRMul(A, Z[j], w);

      //Modified Gram-Schmidt against the basis so far.
      for k := 0 to j do
      begin
        hv := 0.0;
        for i := 0 to n-1 do hv := hv + w[i] * V[k][i];
        H[j][k] := hv;
        for i := 0 to n-1 do w[i] := w[i] - hv * V[k][i];
      end;
      hv := 0.0;
      for i := 0 to n-1 do hv := hv + Sqr(w[i]);
      hv := Sqrt(hv);
      H[j][j+1] := hv;

      //Happy breakdown: the Krylov space is exhausted and the solution is
      //exactly in it. Don't divide by the zero, just stop extending.
      if hv > 1e-300 then
        for i := 0 to n-1 do V[j+1][i] := w[i] / hv;

      //Apply the previous Givens rotations to the new column, then build
      //the one that zeroes its subdiagonal entry.
      for k := 0 to j-1 do
      begin
        tmp      :=  cs[k]*H[j][k] + sn[k]*H[j][k+1];
        H[j][k+1] := -sn[k]*H[j][k] + cs[k]*H[j][k+1];
        H[j][k]   := tmp;
      end;
      denom := Sqrt(Sqr(H[j][j]) + Sqr(H[j][j+1]));
      if denom = 0.0 then begin cs[j] := 1.0; sn[j] := 0.0; end
      else begin cs[j] := H[j][j]/denom; sn[j] := H[j][j+1]/denom; end;
      H[j][j]   := cs[j]*H[j][j] + sn[j]*H[j][j+1];
      H[j][j+1] := 0.0;
      g[j+1] := -sn[j]*g[j];
      g[j]   :=  cs[j]*g[j];

      //|g[j+1]| is the residual norm of the least-squares problem, which
      //for right preconditioning IS the true residual norm - no extra
      //matrix-vector product needed to test convergence.
      resid := Abs(g[j+1]);
      if (resid <= target) or (hv <= 1e-300) then begin converged := True; Break; end;
    end;

    if inner > 0 then
    begin
      //Back-substitute the triangular least-squares system, then update x
      //in the PRECONDITIONED basis: x += sum y_j z_j.
      for i := inner-1 downto 0 do
      begin
        tmp := g[i];
        for k := i+1 to inner-1 do tmp := tmp - H[k][i]*yv[k];
        if H[i][i] <> 0.0 then yv[i] := tmp / H[i][i] else yv[i] := 0.0;
      end;
      for j := 0 to inner-1 do
        for i := 0 to n-1 do x[i] := x[i] + yv[j]*Z[j][i];
    end
    else
      Break;   //no iteration was possible; avoid spinning on MaxIter
  end;

  result := TVMobj.Create(n, 1);
  for i := 0 to n-1 do result.DataPtr[i] := x[i];
end;
