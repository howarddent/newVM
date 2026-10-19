unit ufilmplanecl;

{******************************************************************************
  TFilmPlaneModel (ufilmplanemodel.pas) stepped on a GPU through OpenCL.

  The state lives on the GPU for the whole run. Each SSP-RK3 step is the
  CPU model's twelve phases as twelve kernels - per stage: h with its x
  ghosts, then Phi/gradients/div Q, then the three tendencies, then the
  stage update with the clip at a tenth of the precursor - plus one
  reduction for the h range that StableDt needs. That range (one small
  blocking read per step) is the only traffic while stepping; h, q and p
  come back to the host when AdvanceTo returns, so the inherited Mass,
  FrontX, FullPlate and WriteVTI work unchanged on the copy.

  The kernels are the CPU loops transcribed expression for expression,
  in double precision (cl_khr_fp64), with FP_CONTRACT OFF so no a*b + c
  becomes a fused multiply-add. Every operation is then the same IEEE
  operation on the same operands in the same order, and the frames come
  out bit-identical to the CPU model's. The constants that the CPU code
  folds at compile time (5/6, 9/7, 8/7, 2/3, 2.5 nu) are folded the same
  way here in Pascal and handed to the kernels as values, not retyped as
  OpenCL literals. Two places can't be one loop: the outlet ghost of
  Phi/Hyc/Divc copies cell Nx-1, which another work-item computes in the
  same kernel, so the ghost's work-item computes that cell again (same
  arithmetic, same result); and the clip count is an atomic counter.

  If OpenCL, a double-precision device or the kernel build is missing,
  the object steps on the CPU as the base class does; GPUReady and
  GPUError say which, and why.
*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, OpenCLAPI, ufilmplanemodel;

type
  TFilmPlaneCL = class(TFilmPlaneModel)
  private
    FReady: Boolean;
    FError, FDeviceName: string;
    FCtx: cl_context;
    FQueue: cl_command_queue;
    FDevice: cl_device_id;
    FProg: cl_program;
    // buffers
    bH, bQ, bP, bH0, bQ0, bP0, bH1, bQ1, bP1, bdH, bdQ, bdP: cl_mem;
    bHg, bPhi, bHxc, bHyc, bDivc: cl_mem;
    bSolid, bXOpen, bYOpen, bTauX, bConst, bClips, bRange: cl_mem;
    // the right-hand side kernels twice: input (H, Q, P) and (H1, Q1, P1)
    kGhost, kPhi, kFlux: array[0..1] of cl_kernel;
    kUpdate, kRange: cl_kernel;
    FRangeGroups: Integer;
    FRangeBuf: array of Double;
    FH0Value: Double;          // h in cell 0 at the last range, the NaN check
    procedure Check(Err: cl_int; const What: string);
    function NewBuffer(Bytes: NativeUInt; Data: Pointer): cl_mem;
    procedure Arg(K: cl_kernel; Index: Integer; const M: cl_mem);
    procedure ArgI(K: cl_kernel; Index: Integer; V: LongInt);
    procedure ArgD(K: cl_kernel; Index: Integer; V: Double);
    procedure Run2D(K: cl_kernel; N0, N1: Integer);
    procedure Run1D(K: cl_kernel; N: Integer);
    procedure InitGPU;
    procedure ReleaseGPU;
    procedure StepGPU(dt: Double);
    procedure Download;
  public
    constructor Create(const AP: TPlaneParams);
    destructor Destroy; override;
    function AdvanceTo(t: Double): Boolean; override;
    procedure HRange(out hmin, hmax: Double); override;
    property GPUReady: Boolean read FReady;
    property GPUError: string read FError;
    property DeviceName: string read FDeviceName;
  end;

implementation

const
  RangeLocal = 256;

  KernelSource =
    '#pragma OPENCL EXTENSION cl_khr_fp64 : enable'#10 +
    '#pragma OPENCL FP_CONTRACT OFF'#10 +
    // Nx, Ny come in as -D options
    '#define CI(i,j) ((i) + (j)*Nx)'#10 +
    '#define GI(i,j) ((i) + 1 + (j)*(Nx + 2))'#10 +
    '#define XI(i,j) ((i) + (j)*(Nx + 1))'#10 +
    '#define YI(i,j) ((i) + (j)*Nx)'#10 +
    // the constants, in the order TFilmPlaneCL.InitGPU fills them
    '#define hN   C[0]'#10 +
    '#define hB   C[1]'#10 +
    '#define PiB  C[2]'#10 +
    '#define Sg   C[3]'#10 +
    '#define rdx  C[4]'#10 +
    '#define rdy  C[5]'#10 +
    '#define rdx2 C[6]'#10 +
    '#define rdy2 C[7]'#10 +
    '#define gs   C[8]'#10 +
    '#define gc   C[9]'#10 +
    '#define c56  C[10]'#10 +
    '#define D0   C[11]'#10 +
    '#define c97  C[12]'#10 +
    '#define c87  C[13]'#10 +
    '#define c23  C[14]'#10 +
    '#define hlo  C[15]'#10 +
    #10 +
    'double PiOf(double hh, __global const double *C) {'#10 +
    '  if (PiB == 0.0) return 0.0;'#10 +
    '  double r = hB / hh;'#10 +
    '  return PiB * (r * r * r - r * r);'#10 +
    '}'#10 +
    #10 +
    // PhGhost
    '__kernel void ghost(__global const double *Hs, __global double *Hg, __global const double *C) {'#10 +
    '  int i = (int)get_global_id(0) - 1, j = (int)get_global_id(1);'#10 +
    '  double v;'#10 +
    '  if (i < 0) v = hN;'#10 +
    '  else if (i == Nx) v = Hs[CI(Nx - 1, j)];'#10 +
    '  else v = Hs[CI(i, j)];'#10 +
    '  Hg[GI(i, j)] = v;'#10 +
    '}'#10 +
    #10 +
    // PhPhi's loop body for one cell
    'void cellphi(int i, int j, __global const double *Hg, __global const double *Qs,'#10 +
    '    __global const double *Ps, __global const uchar *solid, __global const uchar *xopen,'#10 +
    '    __global const uchar *yopen, __global const double *C,'#10 +
    '    double *phi, double *hxc, double *hyc, double *divc) {'#10 +
    '  int c = CI(i, j), g = GI(i, j);'#10 +
    '  if (solid[c]) { *phi = 0.0; *hxc = 0.0; *hyc = 0.0; *divc = 0.0; return; }'#10 +
    '  double hc = Hg[g], s = 0.0, hx = 0.0, hy = 0.0;'#10 +
    '  if (xopen[XI(i, j)]) { s = s + (Hg[g - 1] - hc) * rdx2; hx = hx + (hc - Hg[g - 1]); }'#10 +
    '  if (xopen[XI(i + 1, j)]) { s = s + (Hg[g + 1] - hc) * rdx2; hx = hx + (Hg[g + 1] - hc); }'#10 +
    '  if (yopen[YI(i, j)]) { s = s + (Hg[g - (Nx + 2)] - hc) * rdy2; hy = hy + (hc - Hg[g - (Nx + 2)]); }'#10 +
    '  if (yopen[YI(i, j + 1)]) { s = s + (Hg[g + (Nx + 2)] - hc) * rdy2; hy = hy + (Hg[g + (Nx + 2)] - hc); }'#10 +
    '  *phi = Sg * s + PiOf(hc, C);'#10 +
    '  *hxc = 0.5 * hx * rdx;'#10 +
    '  *hyc = 0.5 * hy * rdy;'#10 +
    '  *divc = (Qs[XI(i + 1, j)] - Qs[XI(i, j)]) * rdx + (Ps[YI(i, j + 1)] - Ps[YI(i, j)]) * rdy;'#10 +
    '}'#10 +
    #10 +
    // PhPhi, ghosts included: work-item 0 the inlet, Nx+1 the outlet
    '__kernel void phi(__global const double *Hg, __global const double *Qs, __global const double *Ps,'#10 +
    '    __global const uchar *solid, __global const uchar *xopen, __global const uchar *yopen,'#10 +
    '    __global const double *C, __global double *Phi, __global double *Hxc,'#10 +
    '    __global double *Hyc, __global double *Divc) {'#10 +
    '  int i = (int)get_global_id(0) - 1, j = (int)get_global_id(1);'#10 +
    '  double a, b, cc, d;'#10 +
    '  int g = GI(i, j);'#10 +
    '  if (i < 0) {'#10 +
    '    Phi[g] = PiOf(hN, C); Hxc[g] = 0.0; Hyc[g] = 0.0; Divc[g] = 0.0;'#10 +
    '  } else if (i == Nx) {'#10 +
    '    cellphi(Nx - 1, j, Hg, Qs, Ps, solid, xopen, yopen, C, &a, &b, &cc, &d);'#10 +
    '    Phi[g] = a; Hxc[g] = 0.0; Hyc[g] = cc; Divc[g] = d;'#10 +
    '  } else {'#10 +
    '    cellphi(i, j, Hg, Qs, Ps, solid, xopen, yopen, C, &a, &b, &cc, &d);'#10 +
    '    Phi[g] = a; Hxc[g] = b; Hyc[g] = cc; Divc[g] = d;'#10 +
    '  }'#10 +
    '}'#10 +
    #10 +
    // PhFlux: work-item (i, j) does cell (i, j), x-face (i, j), y-face (i, j)
    '__kernel void flux(__global const double *Hg, __global const double *Qs, __global const double *Ps,'#10 +
    '    __global const uchar *solid, __global const uchar *xopen, __global const uchar *yopen,'#10 +
    '    __global const double *C, __global const double *Phi, __global const double *Hxc,'#10 +
    '    __global const double *Hyc, __global const double *Divc, __global const double *TauX,'#10 +
    '    __global double *dH, __global double *dQ, __global double *dP) {'#10 +
    '  int i = (int)get_global_id(0), j = (int)get_global_id(1);'#10 +
    '  int c, f, gL, gR, kS, kN;'#10 +
    '  double hf, hx, hy, ph, qq, pp, pb, qb, qx, qy, px, py, dv, D, qm, qp;'#10 +
    '  if (i < Nx && j < Ny) {'#10 +
    '    c = CI(i, j);'#10 +
    '    if (solid[c]) dH[c] = 0.0; else dH[c] = -Divc[GI(i, j)];'#10 +
    '  }'#10 +
    '  if (j < Ny) {'#10 +
    '    f = XI(i, j);'#10 +
    '    if (i == 0 || !xopen[f]) dQ[f] = 0.0;'#10 +
    '    else {'#10 +
    '      gL = GI(i - 1, j); gR = GI(i, j);'#10 +
    '      hf = 0.5 * (Hg[gL] + Hg[gR]);'#10 +
    '      hx = (Hg[gR] - Hg[gL]) * rdx;'#10 +
    '      ph = (Phi[gR] - Phi[gL]) * rdx;'#10 +
    '      hy = 0.5 * (Hyc[gL] + Hyc[gR]);'#10 +
    '      dv = 0.5 * (Divc[gL] + Divc[gR]);'#10 +
    '      qq = Qs[f];'#10 +
    '      if (i < Nx)'#10 +
    '        pb = 0.25 * (Ps[YI(i - 1, j)] + Ps[YI(i - 1, j + 1)] + Ps[YI(i, j)] + Ps[YI(i, j + 1)]);'#10 +
    '      else'#10 +
    '        pb = 0.5 * (Ps[YI(i - 1, j)] + Ps[YI(i - 1, j + 1)]);'#10 +
    '      qm = Qs[XI(i - 1, j)];'#10 +
    '      if (i < Nx) qp = Qs[XI(i + 1, j)]; else qp = qq;'#10 +
    '      if (qq > 0.0) qx = (qq - qm) * rdx; else qx = (qp - qq) * rdx;'#10 +
    '      if (pb > 0.0) { if (j > 0) qy = (qq - Qs[XI(i, j - 1)]) * rdy; else qy = 0.0; }'#10 +
    '      else { if (j < Ny - 1) qy = (Qs[XI(i, j + 1)] - qq) * rdy; else qy = 0.0; }'#10 +
    '      D = D0 / (hf * hf);'#10 +
    '      dQ[f] = c56 * hf * (gs - gc * hx + ph)'#10 +
    '            - D * qq'#10 +
    '            + c97 * qq * (qq * hx + pb * hy) / (hf * hf)'#10 +
    '            - c87 * (qq * qx + pb * qy) / hf'#10 +
    '            - c97 * qq * dv / hf'#10 +
    '            + TauX[i];'#10 +
    '    }'#10 +
    '  }'#10 +
    '  if (i < Nx) {'#10 +
    '    f = YI(i, j);'#10 +
    '    if (!yopen[f]) dP[f] = 0.0;'#10 +
    '    else {'#10 +
    '      kS = GI(i, j - 1); kN = GI(i, j);'#10 +
    '      hf = 0.5 * (Hg[kS] + Hg[kN]);'#10 +
    '      hy = (Hg[kN] - Hg[kS]) * rdy;'#10 +
    '      ph = (Phi[kN] - Phi[kS]) * rdy;'#10 +
    '      hx = 0.5 * (Hxc[kS] + Hxc[kN]);'#10 +
    '      dv = 0.5 * (Divc[kS] + Divc[kN]);'#10 +
    '      pp = Ps[f];'#10 +
    '      qb = 0.25 * (Qs[XI(i, j - 1)] + Qs[XI(i + 1, j - 1)] + Qs[XI(i, j)] + Qs[XI(i + 1, j)]);'#10 +
    '      if (qb > 0.0) { if (i > 0) px = (pp - Ps[YI(i - 1, j)]) * rdx; else px = pp * rdx; }'#10 +
    '      else { if (i < Nx - 1) px = (Ps[YI(i + 1, j)] - pp) * rdx; else px = 0.0; }'#10 +
    '      if (pp > 0.0) py = (pp - Ps[YI(i, j - 1)]) * rdy;'#10 +
    '      else py = (Ps[YI(i, j + 1)] - pp) * rdy;'#10 +
    '      D = D0 / (hf * hf);'#10 +
    '      dP[f] = c56 * hf * (-(gc * hy) + ph)'#10 +
    '            - D * pp'#10 +
    '            + c97 * pp * (qb * hx + pp * hy) / (hf * hf)'#10 +
    '            - c87 * (qb * px + pp * py) / hf'#10 +
    '            - c97 * pp * dv / hf;'#10 +
    '    }'#10 +
    '  }'#10 +
    '}'#10 +
    #10 +
    // PhUpdate over every k of every array, then the clip
    '__kernel void update(int stage, double dt, __global const double *C,'#10 +
    '    __global double *H, __global double *H0, __global double *H1, __global const double *dH,'#10 +
    '    __global double *Q, __global double *Q0, __global double *Q1, __global const double *dQ,'#10 +
    '    __global double *P, __global double *P0, __global double *P1, __global const double *dP,'#10 +
    '    __global uint *clips) {'#10 +
    '  int k = (int)get_global_id(0);'#10 +
    '  if (k < Nx * Ny) {'#10 +
    '    double hn;'#10 +
    '    if (stage == 1) { H0[k] = H[k]; hn = H[k] + dt * dH[k]; }'#10 +
    '    else if (stage == 2) hn = 0.75 * H0[k] + 0.25 * (H1[k] + dt * dH[k]);'#10 +
    '    else hn = H0[k] / 3.0 + c23 * (H1[k] + dt * dH[k]);'#10 +
    '    if (hn < hlo) { hn = hlo; atomic_inc(clips); }'#10 +
    '    if (stage == 3) H[k] = hn; else H1[k] = hn;'#10 +
    '  }'#10 +
    '  if (k < (Nx + 1) * Ny) {'#10 +
    '    if (stage == 1) { Q0[k] = Q[k]; Q1[k] = Q[k] + dt * dQ[k]; }'#10 +
    '    else if (stage == 2) Q1[k] = 0.75 * Q0[k] + 0.25 * (Q1[k] + dt * dQ[k]);'#10 +
    '    else Q[k] = Q0[k] / 3.0 + c23 * (Q1[k] + dt * dQ[k]);'#10 +
    '  }'#10 +
    '  if (k < Nx * (Ny + 1)) {'#10 +
    '    if (stage == 1) { P0[k] = P[k]; P1[k] = P[k] + dt * dP[k]; }'#10 +
    '    else if (stage == 2) P1[k] = 0.75 * P0[k] + 0.25 * (P1[k] + dt * dP[k]);'#10 +
    '    else P[k] = P0[k] / 3.0 + c23 * (P1[k] + dt * dP[k]);'#10 +
    '  }'#10 +
    '}'#10 +
    #10 +
    // PhRange: min and max of h over the fluid cells, per work-group; the
    // comparisons are the CPU's, so a NaN is skipped the same way. The
    // last slot gets h in cell 0, for AdvanceTo's NaN check.
    '__kernel void hrange(__global const double *H, __global const uchar *solid,'#10 +
    '    __global double *Out, __local double *Lmn, __local double *Lmx) {'#10 +
    '  int k = (int)get_global_id(0), l = (int)get_local_id(0), n = (int)get_local_size(0);'#10 +
    '  double mn = 1e30, mx = 0.0, v;'#10 +
    '  if (k < Nx * Ny && !solid[k]) { v = H[k]; if (v < mn) mn = v; if (v > mx) mx = v; }'#10 +
    '  Lmn[l] = mn; Lmx[l] = mx;'#10 +
    '  barrier(CLK_LOCAL_MEM_FENCE);'#10 +
    '  for (int s = n / 2; s > 0; s >>= 1) {'#10 +
    '    if (l < s) {'#10 +
    '      if (Lmn[l + s] < Lmn[l]) Lmn[l] = Lmn[l + s];'#10 +
    '      if (Lmx[l + s] > Lmx[l]) Lmx[l] = Lmx[l + s];'#10 +
    '    }'#10 +
    '    barrier(CLK_LOCAL_MEM_FENCE);'#10 +
    '  }'#10 +
    '  if (l == 0) {'#10 +
    '    int grp = (int)get_group_id(0);'#10 +
    '    Out[2 * grp] = Lmn[0]; Out[2 * grp + 1] = Lmx[0];'#10 +
    '    if (grp == 0) Out[2 * get_num_groups(0)] = H[0];'#10 +
    '  }'#10 +
    '}'#10;

constructor TFilmPlaneCL.Create(const AP: TPlaneParams);
begin
  // the base class sets up the grid and the initial state on the CPU
  // (and keeps its threads for the CPU fallback)
  inherited Create(AP);
  try
    InitGPU;
    FReady := True;
  except
    on E: Exception do
    begin
      FError := E.Message;
      ReleaseGPU;
      FReady := False;
    end;
  end;
end;

destructor TFilmPlaneCL.Destroy;
begin
  ReleaseGPU;
  inherited Destroy;
end;

procedure TFilmPlaneCL.Check(Err: cl_int; const What: string);
begin
  if Err <> CL_SUCCESS then
    raise Exception.CreateFmt('OpenCL %s failed with code %d', [What, Err]);
end;

function TFilmPlaneCL.NewBuffer(Bytes: NativeUInt; Data: Pointer): cl_mem;
var
  Err: cl_int;
  Flags: cl_mem_flags;
begin
  Err := 0;
  Flags := CL_MEM_READ_WRITE;
  if Data <> nil then Flags := Flags or CL_MEM_COPY_HOST_PTR;
  Result := clCreateBuffer(FCtx, Flags, Bytes, Data, @Err);
  Check(Err, 'clCreateBuffer');
end;

procedure TFilmPlaneCL.Arg(K: cl_kernel; Index: Integer; const M: cl_mem);
begin
  Check(clSetKernelArg(K, Index, SizeOf(cl_mem), @M), 'clSetKernelArg');
end;

procedure TFilmPlaneCL.ArgI(K: cl_kernel; Index: Integer; V: LongInt);
begin
  Check(clSetKernelArg(K, Index, SizeOf(V), @V), 'clSetKernelArg');
end;

procedure TFilmPlaneCL.ArgD(K: cl_kernel; Index: Integer; V: Double);
begin
  Check(clSetKernelArg(K, Index, SizeOf(V), @V), 'clSetKernelArg');
end;

procedure TFilmPlaneCL.Run2D(K: cl_kernel; N0, N1: Integer);
var
  G: array[0..1] of NativeUInt;
begin
  G[0] := N0; G[1] := N1;
  Check(clEnqueueNDRangeKernel(FQueue, K, 2, nil, @G[0], nil, 0, nil, nil), 'clEnqueueNDRangeKernel');
end;

procedure TFilmPlaneCL.Run1D(K: cl_kernel; N: Integer);
var
  G: NativeUInt;
begin
  G := N;
  Check(clEnqueueNDRangeKernel(FQueue, K, 1, nil, @G, nil, 0, nil, nil), 'clEnqueueNDRangeKernel');
end;

procedure TFilmPlaneCL.InitGPU;
var
  Msg, Opts: string;
  Src: AnsiString;
  PSrc: PAnsiChar;
  Err: cl_int;
  Sz: NativeUInt;
  Log: AnsiString;
  NameBuf: array[0..255] of AnsiChar;
  Ext: AnsiString;
  C: array[0..15] of Double;
  Zero: LongWord;
  function MakeKernel(const Name: AnsiString): cl_kernel;
  begin
    Err := 0;
    Result := clCreateKernel(FProg, PAnsiChar(Name), @Err);
    Check(Err, 'clCreateKernel ' + Name);
  end;
  procedure SetRHS(s: Integer; Hs, Qs, Ps: cl_mem);
  begin
    kGhost[s] := MakeKernel('ghost');
    Arg(kGhost[s], 0, Hs); Arg(kGhost[s], 1, bHg); Arg(kGhost[s], 2, bConst);
    kPhi[s] := MakeKernel('phi');
    Arg(kPhi[s], 0, bHg); Arg(kPhi[s], 1, Qs); Arg(kPhi[s], 2, Ps);
    Arg(kPhi[s], 3, bSolid); Arg(kPhi[s], 4, bXOpen); Arg(kPhi[s], 5, bYOpen);
    Arg(kPhi[s], 6, bConst); Arg(kPhi[s], 7, bPhi); Arg(kPhi[s], 8, bHxc);
    Arg(kPhi[s], 9, bHyc); Arg(kPhi[s], 10, bDivc);
    kFlux[s] := MakeKernel('flux');
    Arg(kFlux[s], 0, bHg); Arg(kFlux[s], 1, Qs); Arg(kFlux[s], 2, Ps);
    Arg(kFlux[s], 3, bSolid); Arg(kFlux[s], 4, bXOpen); Arg(kFlux[s], 5, bYOpen);
    Arg(kFlux[s], 6, bConst); Arg(kFlux[s], 7, bPhi); Arg(kFlux[s], 8, bHxc);
    Arg(kFlux[s], 9, bHyc); Arg(kFlux[s], 10, bDivc); Arg(kFlux[s], 11, bTauX);
    Arg(kFlux[s], 12, bdH); Arg(kFlux[s], 13, bdQ); Arg(kFlux[s], 14, bdP);
  end;
begin
  if not InitializeOpenCLContext(FCtx, FQueue, FDevice, Msg) then
    raise Exception.Create(Msg);
  FillChar(NameBuf, SizeOf(NameBuf), 0);
  if clGetDeviceInfo(FDevice, CL_DEVICE_NAME, SizeOf(NameBuf) - 1, @NameBuf[0], @Sz) = CL_SUCCESS then
    FDeviceName := Trim(string(PAnsiChar(@NameBuf[0])));
  // double precision is required: the frames must match the CPU's
  Sz := 0;
  clGetDeviceInfo(FDevice, $1030 {CL_DEVICE_EXTENSIONS}, 0, nil, @Sz);
  SetLength(Ext, Sz);
  if Sz > 0 then clGetDeviceInfo(FDevice, $1030, Sz, @Ext[1], nil);
  if Pos('cl_khr_fp64', Ext) = 0 then
    raise Exception.Create(FDeviceName + ' has no double precision (cl_khr_fp64)');

  Src := KernelSource;
  PSrc := PAnsiChar(Src);
  Err := 0;
  FProg := clCreateProgramWithSource(FCtx, 1, @PSrc, nil, @Err);
  Check(Err, 'clCreateProgramWithSource');
  Opts := Format('-D Nx=%d -D Ny=%d', [Nx, Ny]);
  Err := clBuildProgram(FProg, 1, @FDevice, PAnsiChar(AnsiString(Opts)), nil, nil);
  if Err <> CL_SUCCESS then
  begin
    Sz := 0;
    clGetProgramBuildInfo(FProg, FDevice, CL_PROGRAM_BUILD_LOG, 0, nil, @Sz);
    SetLength(Log, Sz);
    if Sz > 0 then clGetProgramBuildInfo(FProg, FDevice, CL_PROGRAM_BUILD_LOG, Sz, @Log[1], nil);
    raise Exception.Create('kernel build failed: ' + Trim(string(Log)));
  end;

  // the constants, folded by the same Pascal expressions the CPU model
  // uses, so they are the same doubles
  C[0] := FP.hN;
  C[1] := FP.hB;
  C[2] := PiB;
  C[3] := PlaneSgW;
  C[4] := 1 / Dx;
  C[5] := 1 / Dy;
  C[6] := C[4] * C[4];
  C[7] := C[5] * C[5];
  C[8] := gs;
  C[9] := gc;
  C[10] := 5.0 / 6.0;
  C[11] := 2.5 * PlaneNuW;
  C[12] := 9.0 / 7.0;
  C[13] := 8.0 / 7.0;
  C[14] := 2.0 / 3.0;
  C[15] := 0.1 * FP.hB;
  bConst := NewBuffer(SizeOf(C), @C[0]);

  bH := NewBuffer(Length(H) * 8, @H[0]);
  bQ := NewBuffer(Length(Q) * 8, @Q[0]);
  bP := NewBuffer(Length(P) * 8, @P[0]);
  bH0 := NewBuffer(Length(H) * 8, nil); bH1 := NewBuffer(Length(H) * 8, nil); bdH := NewBuffer(Length(H) * 8, nil);
  bQ0 := NewBuffer(Length(Q) * 8, nil); bQ1 := NewBuffer(Length(Q) * 8, nil); bdQ := NewBuffer(Length(Q) * 8, nil);
  bP0 := NewBuffer(Length(P) * 8, nil); bP1 := NewBuffer(Length(P) * 8, nil); bdP := NewBuffer(Length(P) * 8, nil);
  bHg := NewBuffer(Length(Hg) * 8, nil);
  bPhi := NewBuffer(Length(Phi) * 8, nil);
  bHxc := NewBuffer(Length(Hxc) * 8, nil);
  bHyc := NewBuffer(Length(Hyc) * 8, nil);
  bDivc := NewBuffer(Length(Divc) * 8, nil);
  // Pascal Booleans are one byte, 0 or 1: the kernels read them as uchar
  bSolid := NewBuffer(Length(FSolid), @FSolid[0]);
  bXOpen := NewBuffer(Length(XOpen), @XOpen[0]);
  bYOpen := NewBuffer(Length(YOpen), @YOpen[0]);
  bTauX := NewBuffer(Length(TauX) * 8, @TauX[0]);
  Zero := 0;
  bClips := NewBuffer(SizeOf(Zero), @Zero);
  FRangeGroups := (Nx * Ny + RangeLocal - 1) div RangeLocal;
  SetLength(FRangeBuf, 2 * FRangeGroups + 1);
  bRange := NewBuffer(Length(FRangeBuf) * 8, nil);

  SetRHS(0, bH, bQ, bP);
  SetRHS(1, bH1, bQ1, bP1);
  kUpdate := MakeKernel('update');
  ArgI(kUpdate, 0, 1); ArgD(kUpdate, 1, 0); Arg(kUpdate, 2, bConst);
  Arg(kUpdate, 3, bH); Arg(kUpdate, 4, bH0); Arg(kUpdate, 5, bH1); Arg(kUpdate, 6, bdH);
  Arg(kUpdate, 7, bQ); Arg(kUpdate, 8, bQ0); Arg(kUpdate, 9, bQ1); Arg(kUpdate, 10, bdQ);
  Arg(kUpdate, 11, bP); Arg(kUpdate, 12, bP0); Arg(kUpdate, 13, bP1); Arg(kUpdate, 14, bdP);
  Arg(kUpdate, 15, bClips);
  kRange := MakeKernel('hrange');
  Arg(kRange, 0, bH); Arg(kRange, 1, bSolid); Arg(kRange, 2, bRange);
  Check(clSetKernelArg(kRange, 3, RangeLocal * 8, nil), 'clSetKernelArg');
  Check(clSetKernelArg(kRange, 4, RangeLocal * 8, nil), 'clSetKernelArg');
  Check(clFinish(FQueue), 'clFinish');
end;

procedure TFilmPlaneCL.ReleaseGPU;
  procedure RelM(var M: cl_mem);
  begin
    if M <> nil then clReleaseMemObject(M);
    M := nil;
  end;
  procedure RelK(var K: cl_kernel);
  begin
    if K <> nil then clReleaseKernel(K);
    K := nil;
  end;
var
  s: Integer;
begin
  for s := 0 to 1 do
  begin
    RelK(kGhost[s]); RelK(kPhi[s]); RelK(kFlux[s]);
  end;
  RelK(kUpdate); RelK(kRange);
  RelM(bH); RelM(bQ); RelM(bP); RelM(bH0); RelM(bQ0); RelM(bP0);
  RelM(bH1); RelM(bQ1); RelM(bP1); RelM(bdH); RelM(bdQ); RelM(bdP);
  RelM(bHg); RelM(bPhi); RelM(bHxc); RelM(bHyc); RelM(bDivc);
  RelM(bSolid); RelM(bXOpen); RelM(bYOpen); RelM(bTauX); RelM(bConst);
  RelM(bClips); RelM(bRange);
  if FProg <> nil then clReleaseProgram(FProg);
  FProg := nil;
  if FQueue <> nil then clReleaseCommandQueue(FQueue);
  FQueue := nil;
  if FCtx <> nil then clReleaseContext(FCtx);
  FCtx := nil;
end;

// one SSP-RK3 step: three right-hand sides and three updates, all queued;
// nothing waits for the GPU here
procedure TFilmPlaneCL.StepGPU(dt: Double);
var
  stage, s: Integer;
begin
  for stage := 1 to 3 do
  begin
    if stage = 1 then s := 0 else s := 1;
    Run2D(kGhost[s], Nx + 2, Ny);
    Run2D(kPhi[s], Nx + 2, Ny);
    Run2D(kFlux[s], Nx + 1, Ny + 1);
    ArgI(kUpdate, 0, stage);
    ArgD(kUpdate, 1, dt);
    Run1D(kUpdate, Max(Nx * (Ny + 1), (Nx + 1) * Ny));
  end;
end;

procedure TFilmPlaneCL.HRange(out hmin, hmax: Double);
var
  g: Integer;
  G1, L1: NativeUInt;
begin
  if not FReady then
  begin
    inherited HRange(hmin, hmax);
    Exit;
  end;
  G1 := FRangeGroups * RangeLocal;
  L1 := RangeLocal;
  Check(clEnqueueNDRangeKernel(FQueue, kRange, 1, nil, @G1, @L1, 0, nil, nil), 'clEnqueueNDRangeKernel');
  Check(clEnqueueReadBuffer(FQueue, bRange, CL_TRUE, 0, Length(FRangeBuf) * 8, @FRangeBuf[0], 0, nil, nil),
    'clEnqueueReadBuffer');
  // the CPU model combines its parts in this order, from these starts
  hmin := FRangeBuf[0];
  hmax := FRangeBuf[1];
  for g := 1 to FRangeGroups - 1 do
  begin
    hmin := Min(hmin, FRangeBuf[2 * g]);
    hmax := Max(hmax, FRangeBuf[2 * g + 1]);
  end;
  FH0Value := FRangeBuf[2 * FRangeGroups];
end;

// h, q, p and the clip count back to the host
procedure TFilmPlaneCL.Download;
var
  n: LongWord;
begin
  Check(clEnqueueReadBuffer(FQueue, bH, CL_FALSE, 0, Length(H) * 8, @H[0], 0, nil, nil), 'clEnqueueReadBuffer');
  Check(clEnqueueReadBuffer(FQueue, bQ, CL_FALSE, 0, Length(Q) * 8, @Q[0], 0, nil, nil), 'clEnqueueReadBuffer');
  Check(clEnqueueReadBuffer(FQueue, bP, CL_FALSE, 0, Length(P) * 8, @P[0], 0, nil, nil), 'clEnqueueReadBuffer');
  n := 0;
  Check(clEnqueueReadBuffer(FQueue, bClips, CL_TRUE, 0, SizeOf(n), @n, 0, nil, nil), 'clEnqueueReadBuffer');
  Inc(FClips, n);
  n := 0;
  Check(clEnqueueWriteBuffer(FQueue, bClips, CL_TRUE, 0, SizeOf(n), @n, 0, nil, nil), 'clEnqueueWriteBuffer');
end;

// as TFilmPlaneModel.AdvanceTo, the NaN check made on cell 0 as each
// step's h range comes back (so a NaN step is caught before the next one)
function TFilmPlaneCL.AdvanceTo(t: Double): Boolean;
var
  dt: Double;
begin
  if not FReady then Exit(inherited AdvanceTo(t));
  Result := True;
  while FTime < t - 1e-9 do
  begin
    dt := StableDt;
    if (FSteps > 0) and IsNan(FH0Value) then
    begin
      Result := False;
      Break;
    end;
    if FTime + dt > t then dt := t - FTime;
    StepGPU(dt);
    FTime := FTime + dt;
    FLastDt := dt;
    Inc(FSteps);
  end;
  Download;
  if IsNan(H[0]) then Result := False;
  if Result then FTime := t;
end;

end.
