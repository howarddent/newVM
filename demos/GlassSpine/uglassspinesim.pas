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

unit uGlassSpineSim;

{*******************************************************************************

  The spread of a local anaesthetic injected into CSF, by Stam's Stable
  Fluids on the GPU (OpenCL, glassspine.cl), in the two dural sacs of
  uSpineGeom - one solution in each, so two can be compared side by side
  under the same posture.

  STEP (Stam's vel_step / dens_step, in his order, on a staggered MAC
  grid as in Fedkiw, Stam & Jensen 2001 - see glassspine.cl for why):
    forces    buoyancy (baricity - 1) C g, the needle's jet, root drag
    diffuse   implicit viscosity, Jacobi sweeps (nu = CSF, 0.7 mm^2/s)
    project   red-black SOR, warm-started from the last step's pressure
    advect    velocity by itself (RK2 backtrace, trilinear)
    project
    transport the drug: conservative finite volumes on the MAC faces
              (MUSCL, MC limiter, SSP-RK2), sub-cycled to CFL 0.3 - not
              Stam's semi-Lagrangian step, which gained or lost 10-90 %
              of the injectate within 30 s (see glassspine.cl). The
              drug's own diffusion (~1e-3 mm^2/s) is far below the
              scheme's numerical diffusion, so none is added
    inject    C += f (1 - C) in a sphere at the needle tip

  GRAVITY AND POSTURE. Gravity is fixed in the world, (0, -g, 0). The
  posture is a rotation of the body: from supine (head to world +X,
  anterior up), Roll turns the patient about the long axis (+90 = left
  lateral, left side down; 180 = prone), then Tilt tips the table (+ =
  head up, so 90 = sitting; - = Trendelenburg). The solver works in the
  body frame, so posture only changes the gravity vector there,
  R^T (0, -g, 0). Turning is treated as slow: no Coriolis or centrifugal
  terms, and the CSF moves with the dura.

  INJECTION. The dose (mL) goes in over the injection time through a
  needle of the given bore, its opening facing cephalad or caudad. The
  needle can't be resolved (a 25G lumen is a fifth of a cell), so:
    - the injectate appears in a 2.5 mm sphere at the tip, 3 mm inside the
      posterior dura, at the volume rate Q (inject_prepare, on the GPU,
      tracks how much each step really added - C saturates at 1);
    - the jet's momentum flux rho Q u, with u = Q / (needle lumen area),
      is spread over the same sphere as a body force, acceleration
      Q^2 / (A Vs). For 3 mL in 15 s through a 25G needle that is
      0.75 mN, about 11 m/s^2 over the sphere.
  The injectate replaces CSF in place: the volume it displaces (~1 mm/s
  along the sac) is too slow to matter beside the buoyant flow.

  Concentration is the injectate's volume fraction; mg/mL is that times
  the solution's strength.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, OpenCLAPI, uSpineGeom;

type
  TMat3 = array[0..2, 0..2] of Single;   // [row, column]
  TFloat4 = array[0..3] of Single;

  TSpineSim = class
  private
    FCtx: cl_context;
    FQueue: cl_command_queue;
    FDevice: cl_device_id;
    FProgram: cl_program;
    FKForces, FKDiffuse, FKDiv, FKPressure, FKGrad, FKAdvVel, FKFlux,
      FKUpdate, FKMax, FKInject, FKPrep: cl_kernel;
    FBFlags, FBFluid, FBV, FBV1, FBV2, FBC, FBC1, FBC2, FBC3, FBP, FBDiv, FBSrc, FBState,
      FBFlux, FBMax: cl_mem;
    FKernelSrc: string;
    FNFluid: Integer;
    FGlobal: NativeUInt;
    FSrcCells: array[0..1] of array of Integer;
    FHaveC: Boolean;
    procedure ZeroState;
    procedure ReleaseBuffers;
    procedure BuildProgram;
    procedure Run(K: cl_kernel);
    procedure Project(Iters: Integer);
    procedure SourceSphere(s: Integer; out F: TFloat4);
    procedure ComputeDiagnostics;
    procedure BuildSourceCells;
  public
    Geom: TSpineGeom;
    GeomVersion: Integer;      // goes up each Setup, so a view knows to re-upload
    DeviceName: string;
    Time: Double;              // s since Reset
    Dt: Single;                // s per step
    Nu: Single;                // kinematic viscosity, mm^2/s
    ViscIters, PressureIters: Integer;
    Omega: Single;
    Baricity: array[0..1] of Single;
    TiltDeg, RollDeg: Single;
    RootsDrag: Single;         // 1/s, 0 = no cauda equina drag
    // injection settings (read when an injection starts)
    Interspace: Integer;       // index into uSpineGeom.Interspaces
    DoseML, DurationS: Single;
    NeedleIDmm: Single;
    JetDir: Integer;           // +1 cephalad, -1 caudad, 0 no jet
    InjectStart: Double;       // < 0: no injection yet
    Injected: array[0..1] of Double;   // mm^3 actually added so far (at ReadBack)
    Pending: array[0..1] of Double;    // mm^3 owed but not yet added
    CFL: Single;                       // target Courant number for the drug's transport
    LastMaxSpeed: Single;              // mm/s, the last step's largest face speed
    LastSubsteps: Integer;             // the drug's transport sub-steps in the last step
    // read-back and its diagnostics (after ReadBack)
    HostC: array of Single;
    Present: array[0..1] of Double;          // mm^3 of injectate in the sac
    Profile: array[0..1, 0..NLevels - 1] of Double;   // mL per level
    LevelMax: array[0..1, 0..NLevels - 1] of Double;  // peak C per level
    CMin, CMax: Single;                      // over all fluid cells
    constructor Create(const KernelFile: string);
    destructor Destroy; override;
    procedure Setup(ADx, ACurvature: Single);
    procedure Reset;
    procedure StartInjection;
    function Injecting: Boolean;
    procedure Step;
    procedure Advance(Seconds: Double; MaxSteps: Integer = 1000);
    procedure ReadBack;
    // gravity in the body frame (mm/s^2) for the current posture
    procedure BodyGravity(out gx, gy, gz: Single);
    // the most cephalad / caudal level coordinate (0 = bottom of S2,
    // NLevels = top of T1) where C reaches Threshold, or -1
    function CephaladExtent(s: Integer; Threshold: Single): Single;
    function CaudalExtent(s: Integer; Threshold: Single): Single;
    function MaxSpeed: Single;   // reads the velocity back (slow; for checks)
    // max |div u| dx over the fluid cells, after a fresh divergence pass
    // (mm/s; for checks)
    function MaxDivergence: Single;
  end;

// columns are the body x, y, z axes in world coordinates
function PostureMatrix(TiltDeg, RollDeg: Single): TMat3;
// level coordinate as text, e.g. 'T4' or 'L1-L2'
function LevelText(c: Single): string;

const
  CSFDensity = 1.00059;    // g/mL at 37 C (Lui et al. 1998)
  GravityMM = 9810.0;      // mm/s^2
  SourceRadiusMM = 2.5;
  SourceDepthMM = 3.0;

implementation

function MatMul(const A, B: TMat3): TMat3;
var
  i, j, k: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do
    begin
      Result[i, j] := 0;
      for k := 0 to 2 do Result[i, j] := Result[i, j] + A[i, k] * B[k, j];
    end;
end;

function PostureMatrix(TiltDeg, RollDeg: Single): TMat3;
var
  Base, Rx, Rz: TMat3;
  c, s: Single;
begin
  // supine: body x (left) -> world -Z, y (anterior) -> +Y, z (head) -> +X
  FillChar(Base, SizeOf(Base), 0);
  Base[2, 0] := -1;
  Base[1, 1] := 1;
  Base[0, 2] := 1;
  // roll about world X by -Roll (so +90 puts the left side down)
  FillChar(Rx, SizeOf(Rx), 0);
  SinCos(-DegToRad(RollDeg), s, c);
  Rx[0, 0] := 1;
  Rx[1, 1] := c; Rx[1, 2] := -s;
  Rx[2, 1] := s; Rx[2, 2] := c;
  // tilt about world Z (+ = head up)
  FillChar(Rz, SizeOf(Rz), 0);
  SinCos(DegToRad(TiltDeg), s, c);
  Rz[0, 0] := c; Rz[0, 1] := -s;
  Rz[1, 0] := s; Rz[1, 1] := c;
  Rz[2, 2] := 1;
  Result := MatMul(Rz, MatMul(Rx, Base));
end;

function LevelText(c: Single): string;
var
  L: Integer;
  f: Single;
begin
  if c < 0 then Exit('-');
  L := Floor(c);
  if L >= NLevels then Exit('above ' + LevelNames[NLevels - 1]);
  f := c - L;
  if (f < 0.15) and (L > 0) then Result := LevelNames[L - 1] + '-' + LevelNames[L]
  else if (f > 0.85) and (L < NLevels - 1) then Result := LevelNames[L] + '-' + LevelNames[L + 1]
  else Result := LevelNames[L];
end;

{ TSpineSim }

constructor TSpineSim.Create(const KernelFile: string);
var
  Msg: string;
  SL: TStringList;
  Buf: array[0..255] of AnsiChar;
  Sz: NativeUInt;
begin
  inherited Create;
  Dt := 0.01;
  Nu := 0.7;
  ViscIters := 2;
  PressureIters := 30;
  Omega := 1.7;
  Baricity[0] := 1.0200;
  Baricity[1] := 0.9990;
  Interspace := 1;
  DoseML := 3.0;
  DurationS := 15;
  NeedleIDmm := 0.26;
  JetDir := 1;
  CFL := 0.3;
  InjectStart := -1;
  if not InitializeOpenCLContext(FCtx, FQueue, FDevice, Msg) then
    raise Exception.Create('OpenCL: ' + Msg);
  FillChar(Buf, SizeOf(Buf), 0);
  Sz := 0;
  clGetDeviceInfo(FDevice, CL_DEVICE_NAME, SizeOf(Buf) - 1, @Buf[0], @Sz);
  DeviceName := Trim(string(PAnsiChar(@Buf[0])));
  SL := TStringList.Create;
  try
    SL.LoadFromFile(KernelFile);
    FKernelSrc := SL.Text;
  finally
    SL.Free;
  end;
end;

destructor TSpineSim.Destroy;
begin
  ReleaseBuffers;
  Geom.Free;
  if FQueue <> nil then clReleaseCommandQueue(FQueue);
  if FCtx <> nil then clReleaseContext(FCtx);
  inherited Destroy;
end;

procedure TSpineSim.ReleaseBuffers;
  procedure M(var B: cl_mem);
  begin
    if B <> nil then clReleaseMemObject(B);
    B := nil;
  end;
  procedure K(var X: cl_kernel);
  begin
    if X <> nil then clReleaseKernel(X);
    X := nil;
  end;
begin
  M(FBFlags); M(FBFluid); M(FBV); M(FBV1); M(FBV2); M(FBC); M(FBC1); M(FBC2);
  M(FBC3); M(FBP); M(FBDiv); M(FBSrc); M(FBState); M(FBFlux); M(FBMax);
  K(FKForces); K(FKDiffuse); K(FKDiv); K(FKPressure); K(FKGrad); K(FKAdvVel);
  K(FKFlux); K(FKUpdate); K(FKMax); K(FKInject); K(FKPrep);
  if FProgram <> nil then clReleaseProgram(FProgram);
  FProgram := nil;
end;

procedure Check(Err: cl_int; const What: string);
begin
  if Err <> CL_SUCCESS then
    raise Exception.CreateFmt('%s failed: OpenCL error %d', [What, Err]);
end;

procedure TSpineSim.BuildProgram;
var
  Err: cl_int;
  P: PAnsiChar;
  Opts: AnsiString;
  Log: AnsiString;
  n: NativeUInt;
  function MakeK(const Name: string): cl_kernel;
  begin
    Result := clCreateKernel(FProgram, PAnsiChar(AnsiString(Name)), @Err);
    Check(Err, 'clCreateKernel ' + Name);
  end;
begin
  P := PAnsiChar(AnsiString(FKernelSrc));
  FProgram := clCreateProgramWithSource(FCtx, 1, @P, nil, @Err);
  Check(Err, 'clCreateProgramWithSource');
  Opts := AnsiString(Format('-cl-fast-relaxed-math -D NX=%d -D NY=%d -D NZ=%d',
    [Geom.NX, Geom.NY, Geom.NZ]));
  Err := clBuildProgram(FProgram, 1, @FDevice, PAnsiChar(Opts), nil, nil);
  if Err <> CL_SUCCESS then
  begin
    n := 0;
    clGetProgramBuildInfo(FProgram, FDevice, CL_PROGRAM_BUILD_LOG, 0, nil, @n);
    SetLength(Log, n);
    if n > 0 then
      clGetProgramBuildInfo(FProgram, FDevice, CL_PROGRAM_BUILD_LOG, n, @Log[1], nil);
    raise Exception.Create('glassspine.cl did not build:'#10 + string(Log));
  end;
  FKForces := MakeK('forces');
  FKDiffuse := MakeK('diffuse_vel');
  FKDiv := MakeK('divergence');
  FKPressure := MakeK('pressure_rb');
  FKGrad := MakeK('subtract_grad');
  FKAdvVel := MakeK('advect_vel');
  FKFlux := MakeK('c_flux');
  FKUpdate := MakeK('c_update');
  FKMax := MakeK('max_speed');
  FKInject := MakeK('inject');
  FKPrep := MakeK('inject_prepare');
end;

procedure TSpineSim.Setup(ADx, ACurvature: Single);
var
  Err: cl_int;
  N: Integer;
  function Buf(Size: NativeUInt; Host: Pointer): cl_mem;
  var
    Flags: cl_mem_flags;
  begin
    Flags := CL_MEM_READ_WRITE;
    if Host <> nil then Flags := Flags or CL_MEM_COPY_HOST_PTR;
    Result := clCreateBuffer(FCtx, Flags, Size, Host, @Err);
    Check(Err, 'clCreateBuffer');
  end;
begin
  ReleaseBuffers;
  FreeAndNil(Geom);
  Geom := TSpineGeom.Create(ADx, ACurvature);
  Inc(GeomVersion);
  N := Geom.NX * Geom.NY * Geom.NZ;
  FNFluid := Length(Geom.Fluid);
  FGlobal := ((FNFluid + 63) div 64) * 64;
  BuildProgram;
  FBFlags := Buf(N, @Geom.Flags[0]);
  FBFluid := Buf(4 * FNFluid, @Geom.Fluid[0]);
  FBV := Buf(16 * N, nil);
  FBV1 := Buf(16 * N, nil);
  FBV2 := Buf(16 * N, nil);
  FBC := Buf(4 * N, nil);
  FBC1 := Buf(4 * N, nil);
  FBC2 := Buf(4 * N, nil);
  FBC3 := Buf(4 * N, nil);
  FBP := Buf(4 * N, nil);
  FBDiv := Buf(4 * N, nil);
  FBState := Buf(4 * 8, nil);
  FBFlux := Buf(16 * N, nil);
  FBMax := Buf(4, nil);
  SetLength(HostC, N);
  BuildSourceCells;
  Reset;
end;

procedure TSpineSim.BuildSourceCells;
var
  s, i, j, k, ri: Integer;
  cx, cy, cz, sx, sy, sz, rc: Single;
  All: array of LongInt;
  Err: cl_int;
begin
  // the source cells of each sac, for inject_prepare's bookkeeping
  for s := 0 to 1 do
  begin
    SetLength(FSrcCells[s], 0);
    Geom.InjectionPoint(Interspace, s, SourceDepthMM, sx, sy, sz);
    Geom.ToCell(sx, sy, sz, cx, cy, cz);
    rc := SourceRadiusMM / Geom.Dx;
    ri := Ceil(rc) + 1;
    for k := Round(cz) - ri to Round(cz) + ri do
      for j := Round(cy) - ri to Round(cy) + ri do
        for i := Round(cx) - ri to Round(cx) + ri do
          if Sqr(i - cx) + Sqr(j - cy) + Sqr(k - cz) <= rc * rc then
            if Geom.Flags[Geom.Index(i, j, k)] and FlagFluid <> 0 then
            begin
              SetLength(FSrcCells[s], Length(FSrcCells[s]) + 1);
              FSrcCells[s][High(FSrcCells[s])] := Geom.Index(i, j, k);
            end;
  end;
  // both lists in one buffer, sac 0's first
  SetLength(All, Length(FSrcCells[0]) + Length(FSrcCells[1]) + 1);
  for i := 0 to High(FSrcCells[0]) do All[i] := FSrcCells[0][i];
  for i := 0 to High(FSrcCells[1]) do All[Length(FSrcCells[0]) + i] := FSrcCells[1][i];
  if FBSrc <> nil then clReleaseMemObject(FBSrc);
  FBSrc := clCreateBuffer(FCtx, CL_MEM_READ_WRITE or CL_MEM_COPY_HOST_PTR, 4 * Length(All),
    @All[0], @Err);
  Check(Err, 'clCreateBuffer');
end;

procedure TSpineSim.ZeroState;
var
  Z: array[0..7] of Single;
  s: Integer;
begin
  FillChar(Z, SizeOf(Z), 0);
  Check(clEnqueueWriteBuffer(FQueue, FBState, 1, 0, SizeOf(Z), @Z[0], 0, nil, nil),
    'clEnqueueWriteBuffer');
  for s := 0 to 1 do
  begin
    Injected[s] := 0;
    Pending[s] := 0;
  end;
end;

procedure TSpineSim.Reset;
var
  Z: array of Single;
  N: Integer;
  procedure Zero(B: cl_mem; Bytes: NativeUInt);
  begin
    Check(clEnqueueWriteBuffer(FQueue, B, 1, 0, Bytes, @Z[0], 0, nil, nil), 'clEnqueueWriteBuffer');
  end;
begin
  N := Geom.NX * Geom.NY * Geom.NZ;
  SetLength(Z, 4 * N);
  Zero(FBV, 16 * N); Zero(FBV1, 16 * N); Zero(FBV2, 16 * N);
  Zero(FBC, 4 * N); Zero(FBC1, 4 * N); Zero(FBC2, 4 * N); Zero(FBC3, 4 * N);
  Zero(FBP, 4 * N); Zero(FBDiv, 4 * N); Zero(FBFlux, 16 * N);
  FillChar(HostC[0], 4 * N, 0);
  Time := 0;
  InjectStart := -1;
  ZeroState;
  FHaveC := False;
  ComputeDiagnostics;
end;

procedure TSpineSim.StartInjection;
begin
  // the source sphere follows the interspace, which may have changed
  InjectStart := Time;
  BuildSourceCells;
  ZeroState;
end;

function TSpineSim.Injecting: Boolean;
begin
  Result := (InjectStart >= 0) and (Time - InjectStart < DurationS);
end;

procedure TSpineSim.Run(K: cl_kernel);
begin
  Check(clEnqueueNDRangeKernel(FQueue, K, 1, nil, @FGlobal, nil, 0, nil, nil),
    'clEnqueueNDRangeKernel');
end;

procedure SetArg(K: cl_kernel; Index: Integer; Size: NativeUInt; Value: Pointer);
begin
  Check(clSetKernelArg(K, Index, Size, Value), 'clSetKernelArg');
end;

procedure TSpineSim.Project(Iters: Integer);
var
  inv2dx, dx2: Single;
  it, colour, n: Integer;
begin
  n := FNFluid;
  inv2dx := 1 / Geom.Dx;
  dx2 := Sqr(Geom.Dx);
  SetArg(FKDiv, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKDiv, 1, 4, @n);
  SetArg(FKDiv, 2, SizeOf(cl_mem), @FBV);
  SetArg(FKDiv, 3, SizeOf(cl_mem), @FBDiv);
  SetArg(FKDiv, 4, 4, @inv2dx);
  Run(FKDiv);
  SetArg(FKPressure, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKPressure, 1, 4, @n);
  SetArg(FKPressure, 2, SizeOf(cl_mem), @FBFlags);
  SetArg(FKPressure, 3, SizeOf(cl_mem), @FBP);
  SetArg(FKPressure, 4, SizeOf(cl_mem), @FBDiv);
  SetArg(FKPressure, 5, 4, @dx2);
  SetArg(FKPressure, 7, 4, @Omega);
  for it := 1 to Iters do
    for colour := 0 to 1 do
    begin
      SetArg(FKPressure, 6, 4, @colour);
      Run(FKPressure);
    end;
  SetArg(FKGrad, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKGrad, 1, 4, @n);
  SetArg(FKGrad, 2, SizeOf(cl_mem), @FBFlags);
  SetArg(FKGrad, 3, SizeOf(cl_mem), @FBV);
  SetArg(FKGrad, 4, SizeOf(cl_mem), @FBP);
  SetArg(FKGrad, 5, 4, @inv2dx);
  Run(FKGrad);
end;

procedure TSpineSim.SourceSphere(s: Integer; out F: TFloat4);
var
  x, y, z: Single;
begin
  Geom.InjectionPoint(Interspace, s, SourceDepthMM, x, y, z);
  Geom.ToCell(x, y, z, F[0], F[1], F[2]);
  F[3] := SourceRadiusMM / Geom.Dx;
end;

procedure TSpineSim.BodyGravity(out gx, gy, gz: Single);
var
  R: TMat3;
begin
  // g_body = R^T (0, -g, 0): minus the world Y row of R
  R := PostureMatrix(TiltDeg, RollDeg);
  gx := -GravityMM * R[1, 0];
  gy := -GravityMM * R[1, 1];
  gz := -GravityMM * R[1, 2];
end;

procedure TSpineSim.Step;
var
  n, s, it: Integer;
  g: array[0..1] of TFloat4;
  src: array[0..1] of TFloat4;
  jet: array[0..1] of TFloat4;
  fs: array[0..1] of Single;   // volume owed this step, mm^3
  n0, n1: Integer;
  one: NativeUInt;
  vc: Single;
  gx, gy, gz, a, dtdx, Q, An, Vs: Single;
  zero, umaxBits: LongInt;
  nsub: Integer;
  vsrc, vdst, tmp: cl_mem;
begin
  n := FNFluid;
  BodyGravity(gx, gy, gz);
  for s := 0 to 1 do
  begin
    g[s][0] := (Baricity[s] - 1) * gx;
    g[s][1] := (Baricity[s] - 1) * gy;
    g[s][2] := (Baricity[s] - 1) * gz;
    g[s][3] := 0;
    SourceSphere(s, src[s]);
    FillChar(jet[s], SizeOf(TFloat4), 0);
    fs[s] := 0;
  end;
  if Injecting then
  begin
    Q := DoseML * 1000 / DurationS;              // mm^3/s
    An := Pi * Sqr(NeedleIDmm / 2);               // mm^2
    for s := 0 to 1 do
    begin
      Vs := Max(1, Length(FSrcCells[s])) * Geom.CellVolume;
      jet[s][2] := JetDir * Q * Q / (An * Vs);
      fs[s] := Q * Dt;
    end;
  end;

  // forces
  SetArg(FKForces, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKForces, 1, 4, @n);
  SetArg(FKForces, 2, SizeOf(cl_mem), @FBFlags);
  SetArg(FKForces, 3, SizeOf(cl_mem), @FBV);
  SetArg(FKForces, 4, SizeOf(cl_mem), @FBC);
  SetArg(FKForces, 5, 16, @g[0]);
  SetArg(FKForces, 6, 16, @g[1]);
  SetArg(FKForces, 7, 16, @src[0]);
  SetArg(FKForces, 8, 16, @src[1]);
  SetArg(FKForces, 9, 16, @jet[0]);
  SetArg(FKForces, 10, 16, @jet[1]);
  SetArg(FKForces, 11, 4, @RootsDrag);
  SetArg(FKForces, 12, 4, @Dt);
  Run(FKForces);

  // viscosity: Jacobi from FBV into FBV1/FBV2, the result copied back
  if (Nu > 0) and (ViscIters > 0) then
  begin
    a := Nu * Dt / Sqr(Geom.Dx);
    vsrc := FBV;
    SetArg(FKDiffuse, 0, SizeOf(cl_mem), @FBFluid);
    SetArg(FKDiffuse, 1, 4, @n);
    SetArg(FKDiffuse, 2, SizeOf(cl_mem), @FBFlags);
    SetArg(FKDiffuse, 3, SizeOf(cl_mem), @FBV);
    SetArg(FKDiffuse, 6, 4, @a);
    for it := 0 to ViscIters - 1 do
    begin
      if it mod 2 = 0 then vdst := FBV1 else vdst := FBV2;
      SetArg(FKDiffuse, 4, SizeOf(cl_mem), @vsrc);
      SetArg(FKDiffuse, 5, SizeOf(cl_mem), @vdst);
      Run(FKDiffuse);
      vsrc := vdst;
    end;
    Check(clEnqueueCopyBuffer(FQueue, vsrc, FBV, 0, 0, 16 * NativeUInt(Geom.NX * Geom.NY * Geom.NZ),
      0, nil, nil), 'clEnqueueCopyBuffer');
  end;

  Project(Max(1, PressureIters div 2));

  // self-advection into FBV1, then swap
  dtdx := Dt / Geom.Dx;
  SetArg(FKAdvVel, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKAdvVel, 1, 4, @n);
  SetArg(FKAdvVel, 2, SizeOf(cl_mem), @FBFlags);
  SetArg(FKAdvVel, 3, SizeOf(cl_mem), @FBV);
  SetArg(FKAdvVel, 4, SizeOf(cl_mem), @FBV1);
  SetArg(FKAdvVel, 5, 4, @dtdx);
  Run(FKAdvVel);
  tmp := FBV; FBV := FBV1; FBV1 := tmp;

  Project(PressureIters);

  // the drug: conservative MUSCL/SSP-RK2 transport, sub-cycled to the
  // target Courant number from this step's largest face speed
  zero := 0;
  Check(clEnqueueWriteBuffer(FQueue, FBMax, 0, 0, 4, @zero, 0, nil, nil), 'clEnqueueWriteBuffer');
  SetArg(FKMax, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKMax, 1, 4, @n);
  SetArg(FKMax, 2, SizeOf(cl_mem), @FBV);
  SetArg(FKMax, 3, SizeOf(cl_mem), @FBMax);
  Run(FKMax);
  Check(clEnqueueReadBuffer(FQueue, FBMax, 1, 0, 4, @umaxBits, 0, nil, nil), 'clEnqueueReadBuffer');
  LastMaxSpeed := PSingle(@umaxBits)^;
  nsub := Max(1, Min(64, Ceil(LastMaxSpeed * Dt / (Geom.Dx * CFL))));
  LastSubsteps := nsub;
  dtdx := Dt / nsub / Geom.Dx;
  SetArg(FKFlux, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKFlux, 1, 4, @n);
  SetArg(FKFlux, 2, SizeOf(cl_mem), @FBFlags);
  SetArg(FKFlux, 3, SizeOf(cl_mem), @FBV);
  SetArg(FKFlux, 5, SizeOf(cl_mem), @FBFlux);
  SetArg(FKFlux, 6, 4, @dtdx);
  SetArg(FKUpdate, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKUpdate, 1, 4, @n);
  SetArg(FKUpdate, 2, SizeOf(cl_mem), @FBFlux);
  for it := 1 to nsub do
  begin
    // C1 = C - div F(C)
    SetArg(FKFlux, 4, SizeOf(cl_mem), @FBC);
    Run(FKFlux);
    a := 0;
    SetArg(FKUpdate, 3, SizeOf(cl_mem), @FBC);
    SetArg(FKUpdate, 4, SizeOf(cl_mem), @FBC);
    SetArg(FKUpdate, 5, SizeOf(cl_mem), @FBC1);
    SetArg(FKUpdate, 6, 4, @a);
    Run(FKUpdate);
    // C2 = (C + C1 - div F(C1)) / 2
    SetArg(FKFlux, 4, SizeOf(cl_mem), @FBC1);
    Run(FKFlux);
    a := 0.5;
    SetArg(FKUpdate, 3, SizeOf(cl_mem), @FBC1);
    SetArg(FKUpdate, 4, SizeOf(cl_mem), @FBC);
    SetArg(FKUpdate, 5, SizeOf(cl_mem), @FBC2);
    SetArg(FKUpdate, 6, 4, @a);
    Run(FKUpdate);
    tmp := FBC; FBC := FBC2; FBC2 := tmp;
  end;

  if InjectStart >= 0 then
  begin
    n0 := Length(FSrcCells[0]);
    n1 := Length(FSrcCells[1]);
    vc := Geom.CellVolume;
    SetArg(FKPrep, 0, SizeOf(cl_mem), @FBSrc);
    SetArg(FKPrep, 1, 4, @n0);
    SetArg(FKPrep, 2, 4, @n1);
    SetArg(FKPrep, 3, SizeOf(cl_mem), @FBC);
    SetArg(FKPrep, 4, SizeOf(cl_mem), @FBState);
    SetArg(FKPrep, 5, 4, @fs[0]);
    SetArg(FKPrep, 6, 4, @fs[1]);
    SetArg(FKPrep, 7, 4, @vc);
    one := 1;
    Check(clEnqueueNDRangeKernel(FQueue, FKPrep, 1, nil, @one, nil, 0, nil, nil),
      'clEnqueueNDRangeKernel');
    SetArg(FKInject, 0, SizeOf(cl_mem), @FBFluid);
    SetArg(FKInject, 1, 4, @n);
    SetArg(FKInject, 2, SizeOf(cl_mem), @FBFlags);
    SetArg(FKInject, 3, SizeOf(cl_mem), @FBC);
    SetArg(FKInject, 4, 16, @src[0]);
    SetArg(FKInject, 5, 16, @src[1]);
    SetArg(FKInject, 6, SizeOf(cl_mem), @FBState);
    Run(FKInject);
  end;

  Time := Time + Dt;
end;

procedure TSpineSim.Advance(Seconds: Double; MaxSteps: Integer);
var
  n, i: Integer;
begin
  n := Min(MaxSteps, Max(0, Round(Seconds / Dt)));
  for i := 1 to n do Step;
end;

procedure TSpineSim.ReadBack;
var
  St: array[0..7] of Single;
  s: Integer;
begin
  Check(clEnqueueReadBuffer(FQueue, FBC, 1, 0, 4 * NativeUInt(Length(HostC)), @HostC[0],
    0, nil, nil), 'clEnqueueReadBuffer');
  Check(clEnqueueReadBuffer(FQueue, FBState, 1, 0, SizeOf(St), @St[0], 0, nil, nil),
    'clEnqueueReadBuffer');
  for s := 0 to 1 do
  begin
    Pending[s] := St[s];
    Injected[s] := St[2 + s];
  end;
  FHaveC := True;
  ComputeDiagnostics;
end;

procedure TSpineSim.ComputeDiagnostics;
var
  i, id, s, k, L: Integer;
  c, vc: Double;
  nxy: Integer;
begin
  vc := Geom.CellVolume;
  nxy := Geom.NX * Geom.NY;
  for s := 0 to 1 do
  begin
    Present[s] := 0;
    for L := 0 to NLevels - 1 do
    begin
      Profile[s, L] := 0;
      LevelMax[s, L] := 0;
    end;
  end;
  CMin := 0;
  CMax := 0;
  for i := 0 to High(Geom.Fluid) do
  begin
    id := Geom.Fluid[i];
    c := HostC[id];
    if c < CMin then CMin := c;
    if c > CMax then CMax := c;
    if c <= 0 then Continue;
    if Geom.Flags[id] and FlagSac1 <> 0 then s := 1 else s := 0;
    Present[s] := Present[s] + c * vc;
    k := id div nxy;
    L := Geom.LevelOfK[k];
    if L >= 0 then
    begin
      Profile[s, L] := Profile[s, L] + c * vc / 1000;
      if c > LevelMax[s, L] then LevelMax[s, L] := c;
    end;
  end;
end;

function TSpineSim.CephaladExtent(s: Integer; Threshold: Single): Single;
var
  i, id, k, nxy: Integer;
  zmax, z: Single;
  sac1: Boolean;
begin
  nxy := Geom.NX * Geom.NY;
  zmax := -1e9;
  for i := 0 to High(Geom.Fluid) do
  begin
    id := Geom.Fluid[i];
    sac1 := Geom.Flags[id] and FlagSac1 <> 0;
    if (sac1 <> (s = 1)) or (HostC[id] < Threshold) then Continue;
    k := id div nxy;
    z := Geom.Z0 + k * Geom.Dx;
    if z > zmax then zmax := z;
  end;
  if zmax < -1e8 then Result := -1 else Result := Geom.LevelCoord(zmax);
end;

function TSpineSim.CaudalExtent(s: Integer; Threshold: Single): Single;
var
  i, id, k, nxy: Integer;
  zmin, z: Single;
  sac1: Boolean;
begin
  nxy := Geom.NX * Geom.NY;
  zmin := 1e9;
  for i := 0 to High(Geom.Fluid) do
  begin
    id := Geom.Fluid[i];
    sac1 := Geom.Flags[id] and FlagSac1 <> 0;
    if (sac1 <> (s = 1)) or (HostC[id] < Threshold) then Continue;
    k := id div nxy;
    z := Geom.Z0 + k * Geom.Dx;
    if z < zmin then zmin := z;
  end;
  if zmin > 1e8 then Result := -1 else Result := Geom.LevelCoord(zmin);
end;

function TSpineSim.MaxSpeed: Single;
var
  V: array of Single;
  i, id: Integer;
  sp: Single;
begin
  SetLength(V, 4 * Length(HostC));
  Check(clEnqueueReadBuffer(FQueue, FBV, 1, 0, 16 * NativeUInt(Length(HostC)), @V[0],
    0, nil, nil), 'clEnqueueReadBuffer');
  Result := 0;
  for i := 0 to High(Geom.Fluid) do
  begin
    id := Geom.Fluid[i];
    sp := Sqrt(Sqr(V[4 * id]) + Sqr(V[4 * id + 1]) + Sqr(V[4 * id + 2]));
    if sp > Result then Result := sp;
  end;
end;

function TSpineSim.MaxDivergence: Single;
var
  D: array of Single;
  i, n: Integer;
  invdx: Single;
begin
  n := FNFluid;
  invdx := 1 / Geom.Dx;
  SetArg(FKDiv, 0, SizeOf(cl_mem), @FBFluid);
  SetArg(FKDiv, 1, 4, @n);
  SetArg(FKDiv, 2, SizeOf(cl_mem), @FBV);
  SetArg(FKDiv, 3, SizeOf(cl_mem), @FBDiv);
  SetArg(FKDiv, 4, 4, @invdx);
  Run(FKDiv);
  SetLength(D, Length(HostC));
  Check(clEnqueueReadBuffer(FQueue, FBDiv, 1, 0, 4 * NativeUInt(Length(D)), @D[0], 0, nil, nil),
    'clEnqueueReadBuffer');
  Result := 0;
  for i := 0 to High(Geom.Fluid) do
    Result := Max(Result, Abs(D[Geom.Fluid[i]]) * Geom.Dx);
end;

end.
