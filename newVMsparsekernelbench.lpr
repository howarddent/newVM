program newVMsparsekernelbench;

{*******************************************************************************

     Times MKL's Inspector-Executor sparse kernels - mkl_sparse_d_mv
     (matrix-vector product) and the lower/upper mkl_sparse_d_trsv pair
     (FGMRESSolve's ILU0 preconditioner step) - with and without the
     hint + mkl_sparse_optimize "inspector" stage, at 1 thread and at
     MKL's default thread count. This is the measurement behind the
     comments in newVMsparse.pas's FGMRESSolve.

     Deliberately calls OneAPI.pas's bindings directly rather than going
     through newVMsparse.pas, so the same handle can be timed optimised and
     unoptimised. The matrix is a 2-D 5-point Laplacian, m=1000 (1,000,000
     unknowns, ~5,000,000 non-zeros); both triangular solves run on the
     Laplacian's own lower/upper triangles (a stand-in for ILU0 factors
     with the same sparsity pattern). Every mv run is value-checked against
     two hand-computed rows, since a failed call would otherwise just look
     like a very fast one.

     Results on the development machine (Ryzen 9 7900, 12 cores, MKL
     2026.1), Reps=50:

                       1 thread     12 threads
       mv, plain        187 ms        47 ms
       mv, optimised    125 ms        15 ms
       trsv, plain      563 ms       562 ms
       trsv, optimised  468 ms       485 ms

     i.e. optimize makes mv ~3x faster when threaded, but trsv stays
     effectively sequential either way.

     Build (plain fpc, same as newVMbench.lpr):

       fpc -Fu. -Fi. newVMsparsekernelbench.lpr

     Run:

       ./newVMsparsekernelbench

*******************************************************************************}

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas, hirestimer, OneAPI, newVMsparse;

const
  m = 1000;
  Reps = 50;

var
  n, nnz: Integer;
  rp, ci: array of Integer;
  va, x, y, tmp: array of Double;
  dg, dl, du: TMKLMatrixDescr;

procedure Build;
var
  i, j, p, k: Integer;
begin
  n := m*m;
  SetLength(rp, n+1); SetLength(ci, 5*n); SetLength(va, 5*n);
  k := 0;
  for i := 0 to m-1 do
    for j := 0 to m-1 do
    begin
      p := i*m+j;
      rp[p] := k;
      //columns in ascending order within each row
      if i > 0 then begin ci[k] := p-m; va[k] := -1; Inc(k); end;
      if j > 0 then begin ci[k] := p-1; va[k] := -1; Inc(k); end;
      ci[k] := p; va[k] := 4; Inc(k);
      if j < m-1 then begin ci[k] := p+1; va[k] := -1; Inc(k); end;
      if i < m-1 then begin ci[k] := p+m; va[k] := -1; Inc(k); end;
    end;
  rp[n] := k;
  nnz := k;
end;

function Run(optimize: Boolean): string;
var
  h: Pointer;
  t0, tmv, tsv: Double;
  r, st, q: Integer;
  e0, eq: Double;
begin
  h := nil;
  st := mkl_sparse_d_create_csr(@h, SPARSE_INDEX_BASE_ZERO, n, n, @rp[0], @rp[1], @ci[0], @va[0]);
  if st <> SPARSE_STATUS_SUCCESS then
    raise Exception.Create('mkl_sparse_d_create_csr failed, status ' + IntToStr(st));
  if optimize then
  begin
    mkl_sparse_set_mv_hint(h, SPARSE_OPERATION_NON_TRANSPOSE, dg, Reps);
    mkl_sparse_set_sv_hint(h, SPARSE_OPERATION_NON_TRANSPOSE, dl, Reps);
    mkl_sparse_set_sv_hint(h, SPARSE_OPERATION_NON_TRANSPOSE, du, Reps);
    st := mkl_sparse_optimize(h);
    if st <> SPARSE_STATUS_SUCCESS then WriteLn('  optimize status ', st);
  end;

  t0 := HighResTimer.MilliSeconds;
  for r := 1 to Reps do
  begin
    st := mkl_sparse_d_mv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, h, dg, @x[0], 0.0, @y[0]);
    if st <> SPARSE_STATUS_SUCCESS then
      raise Exception.Create('mkl_sparse_d_mv failed, status ' + IntToStr(st));
  end;
  tmv := HighResTimer.MilliSeconds - t0;

  //value check: corner row 0 and an interior row q
  q := (m div 2)*m + m div 2;
  e0 := 4*x[0] - x[1] - x[m];
  eq := 4*x[q] - x[q-1] - x[q+1] - x[q-m] - x[q+m];
  if (Abs(y[0]-e0) > 1e-12) or (Abs(y[q]-eq) > 1e-12) then
    raise Exception.Create(Format('mv result wrong: y[0]=%g (expect %g), y[q]=%g (expect %g)',
      [y[0], e0, y[q], eq]));

  t0 := HighResTimer.MilliSeconds;
  for r := 1 to Reps do
  begin
    st := mkl_sparse_d_trsv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, h, dl, @x[0], @tmp[0]);
    if st <> SPARSE_STATUS_SUCCESS then
      raise Exception.Create('mkl_sparse_d_trsv(L) failed, status ' + IntToStr(st));
    st := mkl_sparse_d_trsv(SPARSE_OPERATION_NON_TRANSPOSE, 1.0, h, du, @tmp[0], @y[0]);
    if st <> SPARSE_STATUS_SUCCESS then
      raise Exception.Create('mkl_sparse_d_trsv(U) failed, status ' + IntToStr(st));
  end;
  tsv := HighResTimer.MilliSeconds - t0;

  mkl_sparse_destroy(h);
  result := Format('mv %7.1f ms   L+U trsv %7.1f ms', [tmv, tsv]);
end;

var
  i, k: Integer;
  threadCounts: array[0..1] of Integer;
begin
  InitializeCBLAS;
  dg.mtype := SPARSE_MATRIX_TYPE_GENERAL;    dg.mode := 0;                       dg.diag := 0;
  dl.mtype := SPARSE_MATRIX_TYPE_TRIANGULAR; dl.mode := SPARSE_FILL_MODE_LOWER; dl.diag := SPARSE_DIAG_UNIT;
  du.mtype := SPARSE_MATRIX_TYPE_TRIANGULAR; du.mode := SPARSE_FILL_MODE_UPPER; du.diag := SPARSE_DIAG_NON_UNIT;
  Build;
  SetLength(x, n); SetLength(y, n); SetLength(tmp, n);
  for i := 0 to n-1 do x[i] := Sin(i);

  //an array, not "for nt in [a, b]" - that's a set constructor, which
  //iterates in ascending order and can't hold values above 255
  threadCounts[0] := 1;
  threadCounts[1] := GetMKLThreads;
  WriteLn(Format('n=%d nnz=%d reps=%d', [n, nnz, Reps]));
  for k := Low(threadCounts) to High(threadCounts) do
  begin
    SetMKLThreads(threadCounts[k]);
    WriteLn(Format('%2d thr  plain     : %s', [GetMKLThreads, Run(False)]));
    WriteLn(Format('%2d thr  optimized : %s', [GetMKLThreads, Run(True)]));
  end;
  SetMKLThreads(0);
end.
