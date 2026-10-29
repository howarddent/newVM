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

unit ufilmwrmmodel;

{*******************************************************************************

     A water film falling down an inclined plate, in two dimensions, by
     the weighted-residual model of Ruyer-Quil & Manneville (2000) in
     its 3-D form (Scheid, Ruyer-Quil & Manneville 2006), in physical
     units (mm, s). It is the model for films too thick for the Benney
     equation (demos/Benney2D): a 1 mm water film, which Benney blows up
     on, here settles into finite waves.

     Unknowns. The thickness h(x, y, t) and the flow rates per unit
     width q (down the slope, x) and p (across, y), Q = (q, p). The
     velocity profile is taken as the flat film's half-parabola, scaled
     by the local flux, and the momentum equation is weighted by that
     same profile and integrated across the film (Galerkin), which
     gives (s = sin theta, c = cos theta, Sg = sigma/rho):

       h_t + q_x + p_y = 0
       q_t = 5/6 [g s h - g c h h_x + Sg h (lap h)_x] - 5/2 nu q/h^2
             + 9/7 q (Q.grad h)/h^2 - 8/7 (Q.grad) q/h - 9/7 q div Q/h
       p_t = 5/6 [      - g c h h_y + Sg h (lap h)_y] - 5/2 nu p/h^2
             + 9/7 p (Q.grad h)/h^2 - 8/7 (Q.grad) p/h - 9/7 p div Q/h

     This is the "simplified" first-order model: consistent to first
     order in the long-wave parameter, with the second-order streamwise
     viscous terms left out (their 3-D form is long and they mainly
     refine the capillary ripples ahead of large waves). The inertia
     terms are the 1-D model's 9/7 q^2/h^2 h_x - 17/7 q/h q_x written
     in a form covariant under rotation in the plane (8/7 + 9/7 = 17/7),
     which is what fixes the cross terms. Unlike the Kapitza-Shkadov
     model (a plain average with the same profile) it gets the onset of
     waves exactly: Re_c = (5/6) cot theta, Re = qN/nu with the Nusselt
     flux qN = g s hN^3/(3 nu). Linear theory checked in numpy against
     that onset, and at 0.2 mm on 11.2 deg it gives the fastest wave
     53.7 mm, growth 0.036 /s, against the Benney equation's 53.4 mm
     and 0.037 /s - the two agree where both apply.

     Why Benney fails at 1 mm and this doesn't: Benney slaves q to h
     through a long-wave expansion of the profile, and the expansion's
     higher terms grow without bound once inertia matters. Here q has
     its own equation with the wall drag -5/2 nu q/h^2 in it, which
     caps the flux. Checked in a numpy prototype (1-D, 300 mm periodic):
     1 mm on 2 deg (Re 114, 4.8 x onset) from a small bump saturates in
     ~8 s into a steady wave train with crests at 1.69 hN and troughs
     0.65 hN, the same at 256, 512 and 1024 points; on 1 deg (1.2 x
     onset) the waves grow slowly; on 4 deg the crests reach 1.97 hN.

     Grid. x periodic on 0 .. Lx, Nx points, Fourier (FFT_R2C/FFT_C2R
     row by row). y across, -W/2 .. W/2, Ny+1 equally spaced points
     y_j = -W/2 + j W/Ny, and here the side walls are free-slip mirrors:
     h and q are even about each wall, p odd, so h and q are cosine
     series cos(n pi (y + W/2)/W), n = 0 .. Ny, and p a sine series,
     n = 1 .. Ny-1. That is exact for this model, whose equations keep
     that symmetry, and it builds the wall conditions in: p = 0 and
     h_y = h_yyy = 0 at both walls. (Real side walls are no-slip and
     grow a boundary layer the model leaves out.) Every derivative is
     then a multiplier on the modes, and the y transforms are one
     MatMult each with the (Ny+1)^2 cosine or sine matrix, the complex
     mode array read as a real one twice as wide.

     Time stepping: semi-implicit BDF2 (SBDF2), variable step, as in
     Benney2D, but with all three fields: for each (kx, n) mode the
     linearisation about the flat film, L, is a 3 x 3 matrix (2 x 2
     where there is no sine mode), so each step inverts ~8000 3 x 3
     systems - cheap enough to redo whenever the step size changes,
     unlike Benney2D's dense per-mode factorisations. L contains
     gravity, drag, the linearised inertia (advection at 17/7 and 8/7
     of the mean velocity) and surface tension; the rest is explicit.
     Surface tension enters L with factor beta (at least 1.5, raised as
     the crests grow past beta/1.2): the explicit remainder
     Sg (h - beta hN) (lap h)_x would otherwise anti-damp the shortest
     waves under the crests. The cosine mode n = Ny and the x Nyquist
     mode are kept at zero (they have no derivative on the grid).

     Excitation, absorbing zone: as in Benney2D. The source
     a hN c cos(2 pi t/T) g(x) (1 + m cos(n pi (y + W/2)/W)) is added
     to h_t, c = 3 qN/hN the kinematic wave speed, so a narrow source
     launches roughly thickness a hN; the absorbing zone relaxes h, q
     and p back to the flat film, -sigma(x) (h - hN, q - qN, p).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

interface

uses
  Classes, SysUtils, Math, newVM, newVMComplex, oneapi;

const
  GravMM = 9810.0;     // mm/s^2

type
  TFilmParams = record
    hN: Double;          // flat film thickness, mm
    Theta: Double;       // inclination, radians
    Lx, W: Double;       // downslope period and plate width, mm
    Nx, Ny: Integer;     // Fourier points; Ny intervals across (Ny+1 points)
    Nu: Double;          // kinematic viscosity, mm^2/s
    SigmaRho: Double;    // surface tension / density, mm^3/s^2
    Tol: Double;         // local error per step, relative to the largest departure from flat
    Threaded: Boolean;   // half the transforms on a second thread
    Excite: Boolean;
    ExciteAmp, ExcitePeriod, ExciteWidth: Double;   // amp in hN, s, mm
    ExciteMod: Double;
    ExciteModN: Integer;
    Absorb: Boolean;
    AbsorbLength, AbsorbRate, AbsorbGap: Double;
  end;

  TMat3 = array[0..2, 0..2] of TComplex16;

  TFilmState = record
    H, Q, P: TVMobjZ;    // modes of h - hN, q - qN, p
  end;

  { Runs a method on its own thread on request, as Benney2D's
    TDerivWorker: Run starts it, Wait blocks until it is done, both
    spinning briefly on a flag before sleeping on an event (a sleeping
    hand-off costs ~0.1 ms, as long as the work). }
  TFilmWorker = class(TThread)
  private
    FGo, FDone: PRTLEvent;
    FGoFlag, FDoneFlag: LongInt;
    FTask: TThreadMethod;
    FError: string;
  protected
    procedure Execute; override;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Run(ATask: TThreadMethod);
    procedure Wait;
  end;

  TFilmWRMModel = class
  private
    FWorker: TFilmWorker;
    // transform jobs, split between the worker (0 .. FSplit-1) and the
    // calling thread
    FJobE: array of TVMobjZ;
    FJobF: array of TVMobj;
    FJobOdd: array of Boolean;
    FJobCount, FSplit: Integer;
    FLc: array of TMat3;               // L for every mode, at FLBeta
    FLBeta: Double;
    FP: TFilmParams;
    FS, FC, FqN, FU: Double;
    FBeta: Double;
    FNx, FNc, FNy1: Integer;
    FKX, FKX1, FKY: array of Double;   // FKX1: Nyquist 0, for odd orders
    FCa, FCs, FSa, FSs: TVMobj;        // cosine/sine analysis and synthesis
    FX, FY: TVMobj;
    FSponge: TVMobj;
    FSourceH: TVMobjZ;                 // modes of the source shape, mm/s
    // stepping: history 0 (oldest) .. 2 (newest); FF = modes of the
    // full right-hand side, so N = FF - L E can follow a change of beta
    FT: array[0..2] of Double;
    FE, FF: array[0..2] of TFilmState;
    FN: array[0..2] of TFilmState;    // F - L E, valid at FNBeta
    FNBeta: Double;
    FH, FQh, FPh: TVMobj;              // h/hN, q, p at FT[2]
    FDt: Double;
    FSteps, FRejected, FRHSCalls, FSystems: Integer;
    // inverse of (a0 I - dt L) for every mode, nine entries each
    FInv: array[0..8] of array of TComplex16;
    FInvA0, FInvDt, FInvBeta: Double;
    FRHSTime, FSolveTime, FTransTime: Double;
    function Synth(const E: TVMobjZ; OddY: Boolean): TVMobj;
    function Anal(const F: TVMobj; OddY: Boolean): TVMobjZ;
    function DX(const E: TVMobjZ): TVMobjZ;
    function DY(const E: TVMobjZ; OddY: Boolean): TVMobjZ;
    function Lap(const E: TVMobjZ): TVMobjZ;
    procedure ModeL(n, m: Integer; Beta: Double; out A: TMat3);
    function ApplyL(const S: TFilmState): TFilmState;
    procedure BuildInverse(a0, dt: Double);
    function Solve(const R: TFilmState): TFilmState;
    function RHSModes(const S: TFilmState; t: Double; out hf, qf, pf: TVMobj): TFilmState;
    procedure Filter(var E: TVMobjZ);
    procedure FilterState(var S: TFilmState);
    function NOf(i: Integer): TFilmState;
    procedure EnsureL;
    function Comb(const A, B, Cc, D: TVMobjZ; ca, cb, cc_, cd: Double): TVMobjZ;
    procedure SynthJobsLo;
    procedure SynthJobsHi;
    procedure AnalJobsLo;
    procedure AnalJobsHi;
    procedure RunJobs(Lo, Hi: TThreadMethod);
  public
    constructor Create(const P: TFilmParams);
    destructor Destroy; override;
    function Flat: TVMobj;
    function Bump(Amp, X0, Radius: Double): TVMobj;
    function Noise(Amp: Double; Seed: LongInt): TVMobj;
    function UniformRows(Nyd: Integer): TVMobj;
    procedure Start(const H0: TVMobj; dt0: Double);
    procedure StartState(const H0, Q0, P0: TVMobj; dt0: Double);  // q, p in mm^2/s
    function Advance(out Msg: string): Boolean;
    property Time: Double read FT[2];
    property H: TVMobj read FH;        // h/hN
    property FlowQ: TVMobj read FQh;   // mm^2/s
    property FlowP: TVMobj read FPh;
    property Dt: Double read FDt;
    property Steps: Integer read FSteps;
    property Rejected: Integer read FRejected;
    property Systems: Integer read FSystems;
    property Beta: Double read FBeta;
    property RHSCalls: Integer read FRHSCalls;
    property RHSTime: Double read FRHSTime;
    property SolveTime: Double read FSolveTime;
    property TransTime: Double read FTransTime;
    property Params: TFilmParams read FP;
    property X: TVMobj read FX;
    property Y: TVMobj read FY;
    property qN: Double read FqN;
    // physics
    function Re: Double;                       // qN/nu
    function ReCrit: Double;                   // (5/6) cot theta
    function MeanVelocity: Double;             // qN/hN, mm/s
    function KinematicSpeed: Double;           // 3 qN/hN
    function Growth(kx, ky: Double; out Speed: Double): Double;  // 1/s; Speed = -Im/kx
    function GrowthAt(k: Double): Double;
    function GrowthAt2(kx, ky: Double): Double;
    function FastestK: Double;
    function MaxGrowth: Double;
    function WaveSpeed: Double;                // phase speed of the fastest wave
    function ForcedK(Period: Double): Double;  // the wave a source of that period launches
    function SpongeRate(xx: Double): Double;
    function AbsorbStart: Double;
    function AbsorbedFraction: Double;
    function ExciteSource(t: Double): TVMobj;  // mm/s on the grid
  end;

function DefaultFilmParams: TFilmParams;
function CentreRow(const P: TFilmParams): Integer;

implementation

uses
  {$IFDEF LINUX} Linux, UnixType, {$ENDIF}
  dynlibs, cblas;

type
  TSetNumThreads = procedure(n: LongInt); cdecl;

procedure SingleThreadedBLAS;
var
  Lib: TLibHandle;
  SetN: TSetNumThreads;
begin
  Lib := LoadLibrary(CBLASLib);
  if Lib = NilHandle then Exit;
  SetN := TSetNumThreads(GetProcedureAddress(Lib, 'openblas_set_num_threads'));
  if Assigned(SetN) then SetN(1);
  UnloadLibrary(Lib);
end;

function NowSec: Double;
{$IFDEF LINUX}
var
  ts: TTimeSpec;
begin
  clock_gettime(CLOCK_MONOTONIC, @ts);
  Result := ts.tv_sec + ts.tv_nsec * 1e-9;
end;
{$ELSE}
begin
  Result := GetTickCount64 / 1000;
end;
{$ENDIF}

{ TFilmWorker }

const
  SpinTime = 0.002;      // s

constructor TFilmWorker.Create;
begin
  FGo := RTLEventCreate;
  FDone := RTLEventCreate;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TFilmWorker.Destroy;
begin
  Terminate;
  InterLockedExchange(FGoFlag, 1);
  RTLEventSetEvent(FGo);
  WaitFor;
  RTLEventDestroy(FGo);
  RTLEventDestroy(FDone);
  inherited Destroy;
end;

procedure AwaitFlag(var Flag: LongInt; Event: PRTLEvent);
var
  t0: Double;
  n: Integer;
begin
  n := 0;
  t0 := 0;
  while InterLockedCompareExchange(Flag, 0, 1) <> 1 do
  begin
    Inc(n);
    if n = 1000 then
    begin
      if t0 = 0 then t0 := NowSec
      else if NowSec - t0 > SpinTime then RTLEventWaitFor(Event, 1);
      n := 0;
    end;
  end;
end;

procedure TFilmWorker.Execute;
begin
  while True do
  begin
    AwaitFlag(FGoFlag, FGo);
    if Terminated then Break;
    try
      FTask();
    except
      on E: Exception do FError := E.ClassName + ': ' + E.Message;
    end;
    InterLockedExchange(FDoneFlag, 1);
    RTLEventSetEvent(FDone);
  end;
end;

procedure TFilmWorker.Run(ATask: TThreadMethod);
begin
  FTask := ATask;
  FError := '';
  InterLockedExchange(FGoFlag, 1);
  RTLEventSetEvent(FGo);
end;

procedure TFilmWorker.Wait;
begin
  AwaitFlag(FDoneFlag, FDone);
  if FError <> '' then raise Exception.Create('transform thread: ' + FError);
end;

{ ---- complex scalars ---- }

function C(re, im: Double): TComplex16; inline;
begin
  Result.re := re;
  Result.im := im;
end;

function CAdd(const a, b: TComplex16): TComplex16; inline;
begin
  Result.re := a.re + b.re;
  Result.im := a.im + b.im;
end;

function CSub(const a, b: TComplex16): TComplex16; inline;
begin
  Result.re := a.re - b.re;
  Result.im := a.im - b.im;
end;

function CMul(const a, b: TComplex16): TComplex16; inline;
begin
  Result.re := a.re * b.re - a.im * b.im;
  Result.im := a.re * b.im + a.im * b.re;
end;

function CDiv(const a, b: TComplex16): TComplex16;
var
  d: Double;
begin
  d := b.re * b.re + b.im * b.im;
  Result.re := (a.re * b.re + a.im * b.im) / d;
  Result.im := (a.im * b.re - a.re * b.im) / d;
end;

function CSqrt(const a: TComplex16): TComplex16;
var
  r: Double;
begin
  r := Hypot(a.re, a.im);
  Result.re := Sqrt(Max(0, (r + a.re) / 2));
  Result.im := Sqrt(Max(0, (r - a.re) / 2));
  if a.im < 0 then Result.im := -Result.im;
end;

{ The eigenvalue of largest real part of a 3 x 3 complex matrix (or of
  its leading 2 x 2 block, Size = 2). 2 x 2 by the quadratic formula,
  3 x 3 by Durand-Kerner iteration on the characteristic polynomial. }
function TopEigen(const A: TMat3; Size: Integer): TComplex16;
var
  tr, dt, disc, l1, l2, c2, c1, c0, num, den: TComplex16;
  z: array[0..2] of TComplex16;
  it, i, j: Integer;
begin
  if Size = 2 then
  begin
    tr := CAdd(A[0, 0], A[1, 1]);
    dt := CSub(CMul(A[0, 0], A[1, 1]), CMul(A[0, 1], A[1, 0]));
    disc := CSqrt(CSub(CMul(tr, tr), CMul(C(4, 0), dt)));
    l1 := CMul(CAdd(tr, disc), C(0.5, 0));
    l2 := CMul(CSub(tr, disc), C(0.5, 0));
    if l1.re >= l2.re then Exit(l1) else Exit(l2);
  end;
  // lambda^3 + c2 lambda^2 + c1 lambda + c0
  c2 := C(-(A[0, 0].re + A[1, 1].re + A[2, 2].re), -(A[0, 0].im + A[1, 1].im + A[2, 2].im));
  c1 := CAdd(CAdd(CSub(CMul(A[0, 0], A[1, 1]), CMul(A[0, 1], A[1, 0])),
                  CSub(CMul(A[0, 0], A[2, 2]), CMul(A[0, 2], A[2, 0]))),
             CSub(CMul(A[1, 1], A[2, 2]), CMul(A[1, 2], A[2, 1])));
  dt := CAdd(CAdd(CMul(A[0, 0], CSub(CMul(A[1, 1], A[2, 2]), CMul(A[1, 2], A[2, 1]))),
                  CMul(C(-1, 0), CMul(A[0, 1], CSub(CMul(A[1, 0], A[2, 2]), CMul(A[1, 2], A[2, 0]))))),
             CMul(A[0, 2], CSub(CMul(A[1, 0], A[2, 1]), CMul(A[1, 1], A[2, 0]))));
  c0 := C(-dt.re, -dt.im);
  // starting points on a circle of the size of the roots
  num.re := Max(1, Max(Hypot(c2.re, c2.im), Max(Sqrt(Hypot(c1.re, c1.im)), Power(Hypot(c0.re, c0.im), 1 / 3))));
  for i := 0 to 2 do z[i] := C(num.re * Cos(0.4 + 2 * Pi * i / 3), num.re * Sin(0.4 + 2 * Pi * i / 3));
  for it := 1 to 500 do
    for i := 0 to 2 do
    begin
      num := CAdd(CMul(CAdd(CMul(CAdd(z[i], c2), z[i]), c1), z[i]), c0);
      den := C(1, 0);
      for j := 0 to 2 do
        if j <> i then den := CMul(den, CSub(z[i], z[j]));
      if (den.re <> 0) or (den.im <> 0) then z[i] := CSub(z[i], CDiv(num, den));
    end;
  Result := z[0];
  for i := 1 to 2 do
    if z[i].re > Result.re then Result := z[i];
end;

function DefaultFilmParams: TFilmParams;
begin
  Result.hN := 1.0;
  Result.Theta := DegToRad(2.0);
  Result.Lx := 300;
  Result.W := 300;
  Result.Nx := 256;            // dx 1.2 mm; de-aliased (see Filter)
  Result.Ny := 64;
  Result.Nu := 1.0;
  Result.SigmaRho := 72.0e3;
  Result.Threaded := True;
  Result.Tol := 1e-4;             // 1e-3 put a mode's growth 3 % low
  Result.Excite := False;
  Result.ExciteAmp := 0.01;      // 10 um on 1 mm
  Result.ExcitePeriod := 0.3;
  Result.ExciteWidth := 5.0;
  Result.ExciteMod := 0;
  Result.ExciteModN := 2;
  Result.Absorb := False;
  Result.AbsorbLength := 75;
  Result.AbsorbRate := 30;       // ~1 % of a linear wave passes at 2 deg
  Result.AbsorbGap := 15;
end;

function CentreRow(const P: TFilmParams): Integer;
begin
  Result := P.Ny div 2;
end;

{ TFilmWRMModel }

constructor TFilmWRMModel.Create(const P: TFilmParams);
var
  i, j, n, Ny: Integer;
  w: Double;
begin
  inherited Create;
  Assert(P.Nx mod 2 = 0, 'Nx must be even');
  Assert(P.Ny mod 2 = 0, 'Ny must be even (y = 0 is then a grid line)');
  FP := P;
  FS := Sin(P.Theta);
  FC := Cos(P.Theta);
  FqN := GravMM * FS * IntPower(P.hN, 3) / (3 * P.Nu);
  FU := FqN / P.hN;
  FBeta := 1.5;
  FNx := P.Nx;
  FNc := P.Nx div 2 + 1;
  FNy1 := P.Ny + 1;
  Ny := P.Ny;

  FX := TVMobj.Create(1, FNx);
  for i := 0 to FNx - 1 do FX.DataPtr[i] := i * P.Lx / FNx;
  SetLength(FKX, FNc);
  SetLength(FKX1, FNc);
  for i := 0 to FNc - 1 do
  begin
    FKX[i] := 2 * Pi * i / P.Lx;
    FKX1[i] := FKX[i];
  end;
  FKX1[FNc - 1] := 0;
  FY := TVMobj.Create(FNy1, 1);
  SetLength(FKY, FNy1);
  for j := 0 to Ny do
  begin
    FY.DataPtr[j] := -P.W / 2 + j * P.W / Ny;
    FKY[j] := j * Pi / P.W;
  end;

  // cosine: f_j = sum_n a_n cos(n pi j/Ny), n = 0..Ny (DCT-I), and its
  // inverse a_n = (c_n/Ny) sum_j w_j f_j cos(n pi j/Ny), w_j = 1/2 at
  // the walls, c_n = 1 for n = 0, Ny and 2 otherwise. Sine: f_j =
  // sum_n b_n sin(n pi j/Ny), n = 1..Ny-1 (DST-I), b_n = (2/Ny) sum_j
  // f_j sin(n pi j/Ny); rows and columns 0 and Ny stay zero.
  FCs := TVMobj.Create(FNy1, FNy1);
  FCa := TVMobj.Create(FNy1, FNy1);
  FSs := TVMobj.Create(FNy1, FNy1);
  FSa := TVMobj.Create(FNy1, FNy1);
  for j := 0 to Ny do
    for n := 0 to Ny do
    begin
      FCs.DataPtr[j * FNy1 + n] := Cos(n * Pi * j / Ny);
      if (j = 0) or (j = Ny) then w := 0.5 else w := 1;
      if (n = 0) or (n = Ny) then w := w / Ny else w := 2 * w / Ny;
      FCa.DataPtr[n * FNy1 + j] := w * Cos(n * Pi * j / Ny);
      if (j > 0) and (j < Ny) and (n > 0) and (n < Ny) then
      begin
        FSs.DataPtr[j * FNy1 + n] := Sin(n * Pi * j / Ny);
        FSa.DataPtr[n * FNy1 + j] := 2 / Ny * Sin(n * Pi * j / Ny);
      end;
    end;

  if P.Excite then
  begin
    FSourceH := Anal(ExciteSource(0), False);
    Filter(FSourceH);
  end;
  if P.Absorb then
  begin
    FSponge := TVMobj.Create(FNy1, FNx);
    for i := 0 to FNx - 1 do
    begin
      w := SpongeRate(FX.DataPtr[i]);
      for j := 0 to FNy1 - 1 do FSponge.DataPtr[j * FNx + i] := w;
    end;
  end;
  {$IFDEF HAVE_MKL}
  MKL_Set_Num_Threads(1);     // small products; see Benney2D
  {$ENDIF}
  SingleThreadedBLAS;
end;

destructor TFilmWRMModel.Destroy;
begin
  FWorker.Free;
  inherited Destroy;
end;

procedure TFilmWRMModel.SynthJobsLo;
var i: Integer;
begin
  for i := 0 to FSplit - 1 do FJobF[i] := Synth(FJobE[i], FJobOdd[i]);
end;

procedure TFilmWRMModel.SynthJobsHi;
var i: Integer;
begin
  for i := FSplit to FJobCount - 1 do FJobF[i] := Synth(FJobE[i], FJobOdd[i]);
end;

procedure TFilmWRMModel.AnalJobsLo;
var i: Integer;
begin
  for i := 0 to FSplit - 1 do FJobE[i] := Anal(FJobF[i], FJobOdd[i]);
end;

procedure TFilmWRMModel.AnalJobsHi;
var i: Integer;
begin
  for i := FSplit to FJobCount - 1 do FJobE[i] := Anal(FJobF[i], FJobOdd[i]);
end;

// the jobs 0 .. FSplit-1 on the worker, the rest here
procedure TFilmWRMModel.RunJobs(Lo, Hi: TThreadMethod);
begin
  if FP.Threaded then
  begin
    if FWorker = nil then FWorker := TFilmWorker.Create;
    FWorker.Run(Lo);
    try
      Hi();
    finally
      FWorker.Wait;
    end;
  end
  else
  begin
    Lo();
    Hi();
  end;
end;

{ L for every mode at the current beta, rebuilt when beta changes }
procedure TFilmWRMModel.EnsureL;
var
  n, m: Integer;
begin
  if (Length(FLc) = FNy1 * FNc) and (FLBeta = FBeta) then Exit;
  SetLength(FLc, FNy1 * FNc);
  for n := 0 to FNy1 - 1 do
    for m := 0 to FNc - 1 do ModeL(n, m, FBeta, FLc[n * FNc + m]);
  FLBeta := FBeta;
end;

{ ---- physics ---- }

function TFilmWRMModel.Re: Double;
begin
  Result := FqN / FP.Nu;
end;

function TFilmWRMModel.ReCrit: Double;
begin
  Result := 5 / 6 / Tan(FP.Theta);
end;

function TFilmWRMModel.MeanVelocity: Double;
begin
  Result := FU;
end;

function TFilmWRMModel.KinematicSpeed: Double;
begin
  Result := 3 * FU;
end;

// L for wavenumbers (kx, ky); kx1 is kx for the odd (first) derivatives
procedure LinOp(kx, kx1, ky: Double; HasP: Boolean; Beta, hN, u, gs, gc, Sg, Nu: Double;
  out A: TMat3);
var
  kk: Double;
  i, j: Integer;
begin
  for i := 0 to 2 do
    for j := 0 to 2 do A[i, j] := C(0, 0);
  kk := kx * kx + ky * ky;
  A[0, 1] := C(0, -kx1);
  A[1, 0] := C(5 / 6 * gs + 5 * Nu * u / Sqr(hN),
               kx1 * (9 / 7 * u * u - 5 / 6 * gc * hN - 5 / 6 * Sg * Beta * hN * kk));
  A[1, 1] := C(-5 / 2 * Nu / Sqr(hN), -kx1 * 17 / 7 * u);
  if HasP then
  begin
    A[0, 2] := C(-ky, 0);
    A[1, 2] := C(-9 / 7 * u * ky, 0);
    A[2, 0] := C(5 / 6 * hN * ky * (gc + Sg * Beta * kk), 0);
    A[2, 2] := C(-5 / 2 * Nu / Sqr(hN), -kx1 * 8 / 7 * u);
  end;
end;

procedure TFilmWRMModel.ModeL(n, m: Integer; Beta: Double; out A: TMat3);
begin
  LinOp(FKX[m], FKX1[m], FKY[n], (n > 0) and (n < FP.Ny), Beta, FP.hN, FU,
    GravMM * FS, GravMM * FC, FP.SigmaRho, FP.Nu, A);
end;

function TFilmWRMModel.Growth(kx, ky: Double; out Speed: Double): Double;
var
  A: TMat3;
  ev: TComplex16;
begin
  LinOp(kx, kx, ky, ky > 0, 1, FP.hN, FU, GravMM * FS, GravMM * FC, FP.SigmaRho, FP.Nu, A);
  if ky > 0 then ev := TopEigen(A, 3) else ev := TopEigen(A, 2);
  if kx > 0 then Speed := -ev.im / kx else Speed := 0;
  Result := ev.re;
end;

function TFilmWRMModel.GrowthAt(k: Double): Double;
var
  sp: Double;
begin
  Result := Growth(k, 0, sp);
end;

function TFilmWRMModel.GrowthAt2(kx, ky: Double): Double;
var
  sp: Double;
begin
  Result := Growth(kx, ky, sp);
end;

function TFilmWRMModel.FastestK: Double;
var
  i: Integer;
  k, g, best: Double;
begin
  Result := 0;
  best := 0;
  for i := 1 to 4000 do
  begin
    k := i * 1e-3;                       // up to 4 /mm (1.6 mm waves)
    g := GrowthAt(k);
    if g > best then
    begin
      best := g;
      Result := k;
    end;
  end;
end;

function TFilmWRMModel.MaxGrowth: Double;
var
  k: Double;
begin
  k := FastestK;
  if k > 0 then Result := GrowthAt(k) else Result := 0;
end;

function TFilmWRMModel.WaveSpeed: Double;
var
  k, sp: Double;
begin
  k := FastestK;
  if k = 0 then Exit(KinematicSpeed);
  Growth(k, 0, sp);
  Result := sp;
end;

// the wavenumber whose linear frequency c(k) k is 2 pi/Period, by
// bisection (the frequency rises with k)
function TFilmWRMModel.ForcedK(Period: Double): Double;
var
  i: Integer;
  lo, hi, sp, om: Double;
begin
  om := 2 * Pi / Period;
  lo := 1e-6;
  hi := 4;
  for i := 1 to 60 do
  begin
    Result := 0.5 * (lo + hi);
    Growth(Result, 0, sp);
    if sp * Result < om then lo := Result else hi := Result;
  end;
end;

function TFilmWRMModel.AbsorbStart: Double;
begin
  Result := FP.Lx - FP.AbsorbGap - FP.AbsorbLength;
end;

function TFilmWRMModel.SpongeRate(xx: Double): Double;
var
  u: Double;
begin
  u := (xx - AbsorbStart) / FP.AbsorbLength;
  if (u <= 0) or (u >= 1) then Result := 0
  else Result := FP.AbsorbRate * Sqr(Sin(Pi * u));
end;

function TFilmWRMModel.AbsorbedFraction: Double;
begin
  Result := 1 - Exp(-FP.AbsorbRate * FP.AbsorbLength / (2 * WaveSpeed));
end;

function TFilmWRMModel.ExciteSource(t: Double): TVMobj;
var
  i, j: Integer;
  d, w, g, my: Double;
begin
  Result := TVMobj.Create(FNy1, FNx);
  w := FP.ExciteWidth;
  for i := 0 to FNx - 1 do
  begin
    d := FX.DataPtr[i] - FP.Lx * Round(FX.DataPtr[i] / FP.Lx);
    g := Exp(-Sqr(d / w)) / (w * Sqrt(Pi));
    for j := 0 to FNy1 - 1 do
    begin
      my := 1 + FP.ExciteMod * Cos(FP.ExciteModN * Pi * (FY.DataPtr[j] + FP.W / 2) / FP.W);
      Result.DataPtr[j * FNx + i] := FP.ExciteAmp * FP.hN * KinematicSpeed * g * my
        * Cos(2 * Pi * t / FP.ExcitePeriod);
    end;
  end;
end;

{ ---- transforms ---- }

function TFilmWRMModel.Synth(const E: TVMobjZ; OddY: Boolean): TVMobj;
var
  j: Integer;
  R, Yd, back: TVMobj;
  row: TVMobjZ;
begin
  // the complex (Ny1, Nc) modes as a real (Ny1, 2 Nc) matrix: the y
  // transform is real and acts on real and imaginary parts alike
  R := TVMobj.Create(FNy1, 2 * FNc);
  Move(E.DataPtr^, R.DataPtr^, FNy1 * FNc * SizeOf(TComplex16));
  if OddY then Yd := MatMult(FSs, R) else Yd := MatMult(FCs, R);
  Result := TVMobj.Create(FNy1, FNx);
  row := TVMobjZ.Create(1, FNc);
  for j := 0 to FNy1 - 1 do
  begin
    Move(Yd.DataPtr[j * 2 * FNc], row.DataPtr^, FNc * SizeOf(TComplex16));
    back := FFT_C2R(row, FNx);
    Move(back.DataPtr^, Result.DataPtr[j * FNx], FNx * SizeOf(Double));
  end;
end;

function TFilmWRMModel.Anal(const F: TVMobj; OddY: Boolean): TVMobjZ;
var
  j: Integer;
  R, Yd, row: TVMobj;
  S: TVMobjZ;
begin
  R := TVMobj.Create(FNy1, 2 * FNc);
  row := TVMobj.Create(1, FNx);
  for j := 0 to FNy1 - 1 do
  begin
    Move(F.DataPtr[j * FNx], row.DataPtr^, FNx * SizeOf(Double));
    S := FFT_R2C(row);
    Move(S.DataPtr^, R.DataPtr[j * 2 * FNc], FNc * SizeOf(TComplex16));
  end;
  if OddY then Yd := MatMult(FSa, R) else Yd := MatMult(FCa, R);
  Result := TVMobjZ.Create(FNy1, FNc);
  Move(Yd.DataPtr^, Result.DataPtr^, FNy1 * FNc * SizeOf(TComplex16));
end;

// d/dx on modes: i kx
function TFilmWRMModel.DX(const E: TVMobjZ): TVMobjZ;
var
  n, m: Integer;
  EP, RP: PComplex16;
begin
  Result := TVMobjZ.Create(FNy1, FNc);
  EP := E.DataPtr; RP := Result.DataPtr;
  for n := 0 to FNy1 - 1 do
    for m := 0 to FNc - 1 do
    begin
      RP[n * FNc + m].re := -FKX1[m] * EP[n * FNc + m].im;
      RP[n * FNc + m].im := FKX1[m] * EP[n * FNc + m].re;
    end;
end;

// d/dy on modes: cosine -> sine is -ky, sine -> cosine +ky
function TFilmWRMModel.DY(const E: TVMobjZ; OddY: Boolean): TVMobjZ;
var
  n, m: Integer;
  f: Double;
  EP, RP: PComplex16;
begin
  Result := TVMobjZ.Create(FNy1, FNc);
  EP := E.DataPtr; RP := Result.DataPtr;
  for n := 1 to FNy1 - 2 do
  begin
    if OddY then f := FKY[n] else f := -FKY[n];
    for m := 0 to FNc - 1 do
    begin
      RP[n * FNc + m].re := f * EP[n * FNc + m].re;
      RP[n * FNc + m].im := f * EP[n * FNc + m].im;
    end;
  end;
end;

function TFilmWRMModel.Lap(const E: TVMobjZ): TVMobjZ;
var
  n, m: Integer;
  f: Double;
  EP, RP: PComplex16;
begin
  Result := TVMobjZ.Create(FNy1, FNc);
  EP := E.DataPtr; RP := Result.DataPtr;
  for n := 0 to FNy1 - 1 do
    for m := 0 to FNc - 1 do
    begin
      f := -(Sqr(FKX[m]) + Sqr(FKY[n]));
      RP[n * FNc + m].re := f * EP[n * FNc + m].re;
      RP[n * FNc + m].im := f * EP[n * FNc + m].im;
    end;
end;

{ Zeroes the modes the grid can't differentiate (the x Nyquist, the
  cosine n = Ny) and, the 2/3 rule, every mode above two thirds of the
  largest wavenumber in x or in y. The products in the right-hand side
  alias their upper third back onto the resolved modes; without this a
  256-point run blew up in the numpy prototype once its steps were
  small enough not to damp the aliasing numerically, while 512 and 1024
  points converged - de-aliased, 256 points match them (crests 1.44,
  troughs 0.39 hN at t = 4.5 s). Applied to the right-hand side and to
  the state, so the cut modes stay exactly zero. }
procedure TFilmWRMModel.Filter(var E: TVMobjZ);
var
  n, m, mc, nc: Integer;
  EP: PComplex16;
begin
  EP := E.DataPtr;
  mc := (2 * (FNc - 1)) div 3;
  nc := (2 * FP.Ny) div 3;
  for n := 0 to FNy1 - 1 do
    for m := 0 to FNc - 1 do
      if (m > mc) or (n > nc) then EP[n * FNc + m] := C(0, 0);
end;

procedure TFilmWRMModel.FilterState(var S: TFilmState);
begin
  Filter(S.H);
  Filter(S.Q);
  Filter(S.P);
end;

{ ---- right-hand side ---- }

function TFilmWRMModel.RHSModes(const S: TFilmState; t: Double; out hf, qf, pf: TVMobj): TFilmState;
var
  hx, hy, lx, ly, qx, qy, px, py, Ht, Qt, Pt: TVMobj;
  LapH: TVMobjZ;
  i, n: Integer;
  t0, t1, hv, qv, pv, ih, G, D, gs, gc, Sg, nu, sg2: Double;
  HP, QP, PP, HX_, HY_, LX_, LY_, QX_, QY_, PX_, PY_, HT_, QT_, PT_, SP: PDouble;
begin
  t0 := NowSec;
  Inc(FRHSCalls);
  // the eleven fields, by synthesis from the modes: h, q, p and their
  // derivatives, h's through lap h
  LapH := Lap(S.H);
  FJobCount := 11;
  SetLength(FJobE, 11); SetLength(FJobF, 11); SetLength(FJobOdd, 11);
  FJobE[0] := S.H;                FJobOdd[0] := False;
  FJobE[1] := S.Q;                FJobOdd[1] := False;
  FJobE[2] := S.P;                FJobOdd[2] := True;
  FJobE[3] := DX(S.H);            FJobOdd[3] := False;
  FJobE[4] := DY(S.H, False);     FJobOdd[4] := True;
  FJobE[5] := DX(LapH);           FJobOdd[5] := False;
  FJobE[6] := DY(LapH, False);    FJobOdd[6] := True;
  FJobE[7] := DX(S.Q);            FJobOdd[7] := False;
  FJobE[8] := DY(S.Q, False);     FJobOdd[8] := True;
  FJobE[9] := DX(S.P);            FJobOdd[9] := True;
  FJobE[10] := DY(S.P, True);     FJobOdd[10] := False;
  FSplit := 5;
  t1 := NowSec;
  RunJobs(@SynthJobsLo, @SynthJobsHi);
  FTransTime := FTransTime + NowSec - t1;
  hf := AddScalar(FJobF[0], FP.hN);
  qf := AddScalar(FJobF[1], FqN);
  pf := FJobF[2];
  hx := FJobF[3]; hy := FJobF[4]; lx := FJobF[5]; ly := FJobF[6];
  qx := FJobF[7]; qy := FJobF[8]; px := FJobF[9]; py := FJobF[10];
  n := FNy1 * FNx;
  Ht := TVMobj.Create(FNy1, FNx);
  Qt := TVMobj.Create(FNy1, FNx);
  Pt := TVMobj.Create(FNy1, FNx);
  HP := hf.DataPtr; QP := qf.DataPtr; PP := pf.DataPtr;
  HX_ := hx.DataPtr; HY_ := hy.DataPtr; LX_ := lx.DataPtr; LY_ := ly.DataPtr;
  QX_ := qx.DataPtr; QY_ := qy.DataPtr; PX_ := px.DataPtr; PY_ := py.DataPtr;
  HT_ := Ht.DataPtr; QT_ := Qt.DataPtr; PT_ := Pt.DataPtr;
  gs := GravMM * FS; gc := GravMM * FC; Sg := FP.SigmaRho; nu := FP.Nu;
  for i := 0 to n - 1 do
  begin
    hv := HP[i]; qv := QP[i]; pv := PP[i];
    ih := 1 / hv;
    G := (qv * HX_[i] + pv * HY_[i]) * ih * ih;     // Q.grad h / h^2
    D := QX_[i] + PY_[i];                           // div Q
    HT_[i] := -D;
    QT_[i] := 5 / 6 * (gs * hv - gc * hv * HX_[i] + Sg * hv * LX_[i])
      - 5 / 2 * nu * qv * ih * ih
      + 9 / 7 * qv * G - 8 / 7 * (qv * QX_[i] + pv * QY_[i]) * ih - 9 / 7 * qv * D * ih;
    PT_[i] := 5 / 6 * (-gc * hv * HY_[i] + Sg * hv * LY_[i])
      - 5 / 2 * nu * pv * ih * ih
      + 9 / 7 * pv * G - 8 / 7 * (qv * PX_[i] + pv * PY_[i]) * ih - 9 / 7 * pv * D * ih;
  end;
  if FP.Absorb then
  begin
    SP := FSponge.DataPtr;
    for i := 0 to n - 1 do
    begin
      sg2 := SP[i];
      if sg2 = 0 then Continue;
      HT_[i] := HT_[i] - sg2 * (HP[i] - FP.hN);
      QT_[i] := QT_[i] - sg2 * (QP[i] - FqN);
      PT_[i] := PT_[i] - sg2 * PP[i];
    end;
  end;
  FJobCount := 3;
  FJobF[0] := Ht; FJobOdd[0] := False;
  FJobF[1] := Qt; FJobOdd[1] := False;
  FJobF[2] := Pt; FJobOdd[2] := True;
  FSplit := 1;
  t1 := NowSec;
  RunJobs(@AnalJobsLo, @AnalJobsHi);
  FTransTime := FTransTime + NowSec - t1;
  Result.H := FJobE[0];
  Result.Q := FJobE[1];
  Result.P := FJobE[2];
  if FP.Excite then
    Result.H := Result.H + FSourceH * Cos(2 * Pi * t / FP.ExcitePeriod);
  FilterState(Result);
  FRHSTime := FRHSTime + NowSec - t0;
end;

function TFilmWRMModel.ApplyL(const S: TFilmState): TFilmState;
var
  k: Integer;
  u: array[0..2] of TComplex16;
  EH, EQ, EP, RH, RQ, RP: PComplex16;
begin
  EnsureL;
  Result.H := TVMobjZ.Create(FNy1, FNc);
  Result.Q := TVMobjZ.Create(FNy1, FNc);
  Result.P := TVMobjZ.Create(FNy1, FNc);
  EH := S.H.DataPtr; EQ := S.Q.DataPtr; EP := S.P.DataPtr;
  RH := Result.H.DataPtr; RQ := Result.Q.DataPtr; RP := Result.P.DataPtr;
  for k := 0 to FNy1 * FNc - 1 do
  begin
    u[0] := EH[k]; u[1] := EQ[k]; u[2] := EP[k];
    RH[k] := CAdd(CAdd(CMul(FLc[k][0, 0], u[0]), CMul(FLc[k][0, 1], u[1])), CMul(FLc[k][0, 2], u[2]));
    RQ[k] := CAdd(CAdd(CMul(FLc[k][1, 0], u[0]), CMul(FLc[k][1, 1], u[1])), CMul(FLc[k][1, 2], u[2]));
    RP[k] := CAdd(CAdd(CMul(FLc[k][2, 0], u[0]), CMul(FLc[k][2, 1], u[1])), CMul(FLc[k][2, 2], u[2]));
  end;
end;

// ca A + cb B + cc C + cd D in one pass (each of these arrays is
// ~130 kB, and every temporary costs an allocation and its page faults)
function TFilmWRMModel.Comb(const A, B, Cc, D: TVMobjZ; ca, cb, cc_, cd: Double): TVMobjZ;
var
  k: Integer;
  PA, PB, PC, PD, PR: PDouble;
begin
  Result := TVMobjZ.Create(FNy1, FNc);
  PA := PDouble(A.DataPtr); PB := PDouble(B.DataPtr);
  PC := PDouble(Cc.DataPtr); PD := PDouble(D.DataPtr);
  PR := PDouble(Result.DataPtr);
  for k := 0 to 2 * FNy1 * FNc - 1 do
    PR[k] := ca * PA[k] + cb * PB[k] + cc_ * PC[k] + cd * PD[k];
end;

// N_i = F_i - L E_i at the current beta
function TFilmWRMModel.NOf(i: Integer): TFilmState;
var
  LE: TFilmState;
begin
  LE := ApplyL(FE[i]);
  Result.H := FF[i].H - LE.H;
  Result.Q := FF[i].Q - LE.Q;
  Result.P := FF[i].P - LE.P;
end;

{ (a0 I - dt L)^-1 for every mode, by the adjugate. Modes without a
  sine part get p's row and column of the identity; the dead modes
  (x Nyquist, cosine n = Ny) the zero matrix. }
procedure TFilmWRMModel.BuildInverse(a0, dt: Double);
var
  n, m, k, i, j: Integer;
  A, Mt: TMat3;
  det: TComplex16;
  cof: TMat3;
begin
  if (Length(FInv[0]) = FNy1 * FNc) and (FInvA0 = a0) and (FInvDt = dt) and (FInvBeta = FBeta) then Exit;
  EnsureL;
  for i := 0 to 8 do SetLength(FInv[i], FNy1 * FNc);
  for n := 0 to FNy1 - 1 do
    for m := 0 to FNc - 1 do
    begin
      k := n * FNc + m;
      if (m > (2 * (FNc - 1)) div 3) or (n > (2 * FP.Ny) div 3) then
      begin
        // the modes Filter cuts: the solution stays zero there
        for i := 0 to 8 do FInv[i][k] := C(0, 0);
        Continue;
      end;
      A := FLc[k];
      for i := 0 to 2 do
        for j := 0 to 2 do
        begin
          Mt[i, j] := C(-dt * A[i, j].re, -dt * A[i, j].im);
          if i = j then Mt[i, j].re := Mt[i, j].re + a0;
        end;
      if n = 0 then
      begin
        Mt[2, 0] := C(0, 0); Mt[2, 1] := C(0, 0); Mt[0, 2] := C(0, 0); Mt[1, 2] := C(0, 0);
        Mt[2, 2] := C(1, 0);
      end;
      cof[0, 0] := CSub(CMul(Mt[1, 1], Mt[2, 2]), CMul(Mt[1, 2], Mt[2, 1]));
      cof[0, 1] := CSub(CMul(Mt[1, 2], Mt[2, 0]), CMul(Mt[1, 0], Mt[2, 2]));
      cof[0, 2] := CSub(CMul(Mt[1, 0], Mt[2, 1]), CMul(Mt[1, 1], Mt[2, 0]));
      cof[1, 0] := CSub(CMul(Mt[0, 2], Mt[2, 1]), CMul(Mt[0, 1], Mt[2, 2]));
      cof[1, 1] := CSub(CMul(Mt[0, 0], Mt[2, 2]), CMul(Mt[0, 2], Mt[2, 0]));
      cof[1, 2] := CSub(CMul(Mt[0, 1], Mt[2, 0]), CMul(Mt[0, 0], Mt[2, 1]));
      cof[2, 0] := CSub(CMul(Mt[0, 1], Mt[1, 2]), CMul(Mt[0, 2], Mt[1, 1]));
      cof[2, 1] := CSub(CMul(Mt[0, 2], Mt[1, 0]), CMul(Mt[0, 0], Mt[1, 2]));
      cof[2, 2] := CSub(CMul(Mt[0, 0], Mt[1, 1]), CMul(Mt[0, 1], Mt[1, 0]));
      det := CAdd(CAdd(CMul(Mt[0, 0], cof[0, 0]), CMul(Mt[0, 1], cof[0, 1])), CMul(Mt[0, 2], cof[0, 2]));
      // inverse = adjugate / det, adjugate = cofactor transposed
      for i := 0 to 2 do
        for j := 0 to 2 do
          FInv[i * 3 + j][k] := CDiv(cof[j, i], det);
    end;
  FInvA0 := a0;
  FInvDt := dt;
  FInvBeta := FBeta;
  Inc(FSystems);
end;

function TFilmWRMModel.Solve(const R: TFilmState): TFilmState;
var
  k: Integer;
  t0: Double;
  RH, RQ, RP, OH, OQ, OP: PComplex16;
begin
  t0 := NowSec;
  Result.H := TVMobjZ.Create(FNy1, FNc);
  Result.Q := TVMobjZ.Create(FNy1, FNc);
  Result.P := TVMobjZ.Create(FNy1, FNc);
  RH := R.H.DataPtr; RQ := R.Q.DataPtr; RP := R.P.DataPtr;
  OH := Result.H.DataPtr; OQ := Result.Q.DataPtr; OP := Result.P.DataPtr;
  for k := 0 to FNy1 * FNc - 1 do
  begin
    OH[k] := CAdd(CAdd(CMul(FInv[0][k], RH[k]), CMul(FInv[1][k], RQ[k])), CMul(FInv[2][k], RP[k]));
    OQ[k] := CAdd(CAdd(CMul(FInv[3][k], RH[k]), CMul(FInv[4][k], RQ[k])), CMul(FInv[5][k], RP[k]));
    OP[k] := CAdd(CAdd(CMul(FInv[6][k], RH[k]), CMul(FInv[7][k], RQ[k])), CMul(FInv[8][k], RP[k]));
  end;
  FSolveTime := FSolveTime + NowSec - t0;
end;

{ ---- initial conditions (h/hN) ---- }

function TFilmWRMModel.Flat: TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(FNy1, FNx);
  for i := 0 to FNy1 * FNx - 1 do Result.DataPtr[i] := 1;
end;

function TFilmWRMModel.Bump(Amp, X0, Radius: Double): TVMobj;
var
  i, j: Integer;
  d: Double;
begin
  Result := TVMobj.Create(FNy1, FNx);
  for j := 0 to FNy1 - 1 do
    for i := 0 to FNx - 1 do
    begin
      d := FX.DataPtr[i] - X0;
      d := d - FP.Lx * Round(d / FP.Lx);
      Result.DataPtr[j * FNx + i] := Amp * Exp(-(Sqr(d) + Sqr(FY.DataPtr[j])) / Sqr(Radius));
    end;
end;

function TFilmWRMModel.Noise(Amp: Double; Seed: LongInt): TVMobj;
var
  i, j, mx, my: Integer;
  a, ph, mx0, cy: Double;
  P: PDouble;
begin
  RandSeed := Seed;
  Result := TVMobj.Create(FNy1, FNx);
  P := Result.DataPtr;
  for my := 0 to 8 do
    for mx := 0 to 12 do
    begin
      if (mx = 0) and (my = 0) then Continue;
      a := RandG(0, 1);
      ph := 2 * Pi * Random;
      for j := 0 to FNy1 - 1 do
      begin
        cy := Cos(my * Pi * (FY.DataPtr[j] + FP.W / 2) / FP.W);
        for i := 0 to FNx - 1 do
          P[j * FNx + i] := P[j * FNx + i] + a * cy * Cos(2 * Pi * mx * FX.DataPtr[i] / FP.Lx + ph);
      end;
    end;
  mx0 := 0;
  for i := 0 to FNy1 * FNx - 1 do mx0 := Max(mx0, Abs(P[i]));
  if mx0 > 0 then Result := Result * (Amp / mx0);
end;

{ Rows at Nyd equally spaced y from the cosine series (n < Ny, the
  modes a solution carries): exact interpolation, (Nyd, Ny+1). }
function TFilmWRMModel.UniformRows(Nyd: Integer): TVMobj;
var
  i, n: Integer;
  B: TVMobj;
begin
  B := TVMobj.Create(Nyd, FNy1);
  for i := 0 to Nyd - 1 do
    for n := 0 to FNy1 - 2 do
      B.DataPtr[i * FNy1 + n] := Cos(n * Pi * i / (Nyd - 1));
  Result := MatMult(B, FCa);
end;

{ ---- integration ---- }

procedure TFilmWRMModel.Start(const H0: TVMobj; dt0: Double);
var
  Q0, P0: TVMobj;
  i: Integer;
begin
  // the flux in local equilibrium with the thickness, qN H^3, no p
  Q0 := TVMobj.Create(FNy1, FNx);
  for i := 0 to FNy1 * FNx - 1 do Q0.DataPtr[i] := FqN * IntPower(H0.DataPtr[i], 3);
  P0 := TVMobj.Create(FNy1, FNx);
  StartState(H0, Q0, P0, dt0);
end;

procedure TFilmWRMModel.StartState(const H0, Q0, P0: TVMobj; dt0: Double);
var
  i: Integer;
  R, N0: TFilmState;
  hf, qf, pf: TVMobj;
begin
  FSteps := 0;
  FRejected := 0;
  FSystems := 0;
  FRHSCalls := 0;
  FRHSTime := 0; FSolveTime := 0; FTransTime := 0;
  FBeta := 1.5;
  FInv[0] := nil;
  FDt := dt0;
  FT[0] := 0;
  FE[0].H := Anal(AddScalar(H0, -1) * FP.hN, False);
  FE[0].Q := Anal(AddScalar(Q0, -FqN), False);
  FE[0].P := Anal(P0, True);
  FilterState(FE[0]);
  FF[0] := RHSModes(FE[0], 0, hf, qf, pf);
  // two SBDF1 steps to start the history
  BuildInverse(1, dt0);
  for i := 1 to 2 do
  begin
    FN[i - 1] := NOf(i - 1);
    N0 := FN[i - 1];
    R.H := FE[i - 1].H + N0.H * dt0;
    R.Q := FE[i - 1].Q + N0.Q * dt0;
    R.P := FE[i - 1].P + N0.P * dt0;
    FE[i] := Solve(R);
    FT[i] := FT[i - 1] + dt0;
    FF[i] := RHSModes(FE[i], FT[i], hf, qf, pf);
    Inc(FSteps);
  end;
  FN[2] := NOf(2);
  FNBeta := FBeta;
  FH := hf * (1 / FP.hN);
  FQh := qf;
  FPh := pf;
end;

function TFilmWRMModel.Advance(out Msg: string): Boolean;
const
  MinDt = 1e-7;
var
  w, a0, hs, tn, l0, l1, l2, err, fac, hmax, hmin, sh, sq, v: Double;
  R, En, N1, N2: TFilmState;
  FNew: TFilmState;
  DH, DQ, hf, qf, pf: TVMobj;
  i: Integer;
  ok: Boolean;
begin
  Msg := '';
  if FNBeta <> FBeta then
  begin
    // beta moved L: the explicit parts move with it
    FN[1] := NOf(1);
    FN[2] := NOf(2);
    FNBeta := FBeta;
  end;
  N1 := FN[1];
  N2 := FN[2];
  while True do
  begin
    hs := FDt;
    w := hs / (FT[2] - FT[1]);
    a0 := (1 + 2 * w) / (1 + w);
    R.H := Comb(FE[2].H, FE[1].H, N2.H, N1.H, 1 + w, -w * w / (1 + w), (1 + w) * hs, -w * hs);
    R.Q := Comb(FE[2].Q, FE[1].Q, N2.Q, N1.Q, 1 + w, -w * w / (1 + w), (1 + w) * hs, -w * hs);
    R.P := Comb(FE[2].P, FE[1].P, N2.P, N1.P, 1 + w, -w * w / (1 + w), (1 + w) * hs, -w * hs);
    BuildInverse(a0, hs);
    En := Solve(R);              // zero in the filtered modes
    // the predictor: the quadratic through the last three steps
    tn := FT[2] + hs;
    l0 := (tn - FT[1]) * (tn - FT[0]) / ((FT[2] - FT[1]) * (FT[2] - FT[0]));
    l1 := (tn - FT[2]) * (tn - FT[0]) / ((FT[1] - FT[2]) * (FT[1] - FT[0]));
    l2 := (tn - FT[2]) * (tn - FT[1]) / ((FT[0] - FT[2]) * (FT[0] - FT[1]));
    DH := Synth(Comb(En.H, FE[2].H, FE[1].H, FE[0].H, 1, -l0, -l1, -l2), False);
    DQ := Synth(Comb(En.Q, FE[2].Q, FE[1].Q, FE[0].Q, 1, -l0, -l1, -l2), False);
    // the error relative to the size of the departure from the flat
    // film, so a small wave is followed as closely as a large one
    ok := True;
    FNew := RHSModes(En, tn, hf, qf, pf);
    hmin := 1e30;
    hmax := -1e30;
    sh := 0;
    sq := 0;
    for i := 0 to FNy1 * FNx - 1 do
    begin
      v := hf.DataPtr[i];
      if IsNan(v) or IsInfinite(v) then ok := False
      else
      begin
        hmax := Max(hmax, v);
        hmin := Min(hmin, v);
        sh := Max(sh, Abs(v - FP.hN));
        sq := Max(sq, Abs(qf.DataPtr[i] - FqN));
      end;
    end;
    hmax := hmax / FP.hN;
    hmin := hmin / FP.hN;
    sh := Max(sh, 1e-12 * FP.hN);
    sq := Max(sq, 1e-12 * FqN);
    err := 0;
    if ok then
      for i := 0 to FNy1 * FNx - 1 do
      begin
        v := Max(Abs(DH.DataPtr[i]) / sh, Abs(DQ.DataPtr[i]) / sq);
        if IsNan(v) or IsInfinite(v) then ok := False
        else err := Max(err, v);
      end;
    err := err * 2 / 11;
    if GetEnvironmentVariable('WRMDEBUG') <> '' then
      WriteLn(Format('t %.5f dt %.3e err %.3e h %.4f .. %.4f beta %.2f', [FT[2], hs, err, hmin, hmax, FBeta]));
    if (not ok) or (hmin <= 0.02) or (hmax > 20) or (err > FP.Tol) then
    begin
      Inc(FRejected);
      if ok and (err > FP.Tol) then
        FDt := hs * Max(0.2, 0.9 * Power(FP.Tol / err, 1 / 3))
      else
        FDt := hs * 0.25;
      if FDt < MinDt then
      begin
        Msg := Format('the step size collapsed at t = %.4g s', [FT[2]]);
        Exit(False);
      end;
      Continue;
    end;
    for i := 0 to 1 do
    begin
      FT[i] := FT[i + 1];
      FE[i] := FE[i + 1];
      FF[i] := FF[i + 1];
      FN[i] := FN[i + 1];
    end;
    FT[2] := tn;
    FE[2] := En;
    FF[2] := FNew;
    FN[2] := NOf(2);           // at the current beta; Advance redoes all if it changes
    FH := hf * (1 / FP.hN);
    FQh := qf;
    FPh := pf;
    Inc(FSteps);
    // keep the explicit surface-tension remainder damped: h < beta/1.2
    if hmax > FBeta / 1.2 then FBeta := 1.25 * hmax;
    if err > 0 then fac := Min(2, Max(0.5, 0.9 * Power(FP.Tol / err, 1 / 3))) else fac := 2;
    // small changes aren't worth rebuilding the systems for
    if (fac > 1.2) or (fac < 1) then FDt := hs * fac;
    Exit(True);
  end;
end;

end.
