unit ufilmplanemodel;

{******************************************************************************
  The weighted-residual film model on the geometry of OpenFOAM's
  inclinedPlaneFilm tutorial (incompressible/pimpleFoam/laminar): a film
  entering a plate from its top edge and running down over a thin
  precursor film, round a cylinder. The FilmWRM demo runs it as its
  "OpenFOAM inclined plane" case, and demos/InclinedPlane/filmplane.lpr
  runs it from the command line and writes VTK frames for ParaView.

  The spectral model (ufilmwrmmodel.pas) can't do this case: its x
  direction is periodic, it is linearised about a flat film, and it has
  no way to hold an obstacle or a front where h falls 14-fold in a
  millimetre. So this is the same equations on finite volumes.

  The tutorial's conditions, the defaults of TPlaneParams:
    plate x = -32 .. 32 mm down the slope, y = -32 .. 32 mm across. The
    model computes the half y = 0 .. 32, with a symmetry plane at y = 0
    (as the tutorial does) and a wall at y = 32;
    a cylinder of radius 8 mm at the origin;
    30 deg incline (OpenFOAM g = (4.905, 0, -8.4957));
    water at 300 K (OpenFOAM's H2O thermo, T0 300);
    film thickness 141 um held at the inlet, x = -32 mm;
    the rest of the plate starts with a 10 um film (OpenFOAM's initial
    hf_film), which serves as the precursor film over the "dry" plate;
    air at 1 m/s blowing down the slope (nu 1e-5 m^2/s);
    2.5 s of flow (the caller's run time).

  Different on purpose - this is our model, not OpenFOAM's:
    momentum is the simplified first-order weighted-residual model
    (Ruyer-Quil & Manneville 2000, 3-D form Scheid et al. 2006), as in
    ufilmwrmmodel.pas, with laminar drag 5/2 nu q/h^2 in place of
    kinematicThinFilm's Manning-Strickler wall friction (n = 0.1);
    the air acts as a laminar (Blasius) interfacial shear stress from the
    start of the plate, 5/4 tau/rho in the q equation (that coefficient
    makes the flat-film flux exactly g s h^3/(3 nu) + tau h^2/(2 mu)), in
    place of kinematicThinFilm's Cf = 0.9 m/s gas-film relaxation. It is
    about 1 % of gravity's pull here;
    the contact line is the precursor film. An optional disjoining
    pressure (Theta, Schwartz & Eley 1998, exponents 3, 2) gives it a
    finite equilibrium contact angle. It is off by default: OpenFOAM's
    95-145 deg random angle is far outside a long-wave model;
    walls (side, symmetry plane, cylinder) are free-slip and no-flux, with
    zero normal gradient of h (a 90 deg angle at the wall).

  Equations (mm, s), Q = (q, p):
    h_t + q_x + p_y = 0
    q_t = 5/6 h [g s - g c h_x + (Sg lap h + Pi(h)/rho)_x]
          - 5/2 nu q/h^2 + 9/7 q (Q.grad h)/h^2 - 8/7 (Q.grad) q/h
          - 9/7 q div Q/h + 5/4 tau_x/rho
    p_t = the same with p, no g s or tau term, y derivatives.

  Numerics: finite volumes on a uniform Cartesian grid, h at cell
  centres, q on x-faces and p on y-faces (staggered), so mass is
  conserved exactly and a wall is just a face whose flux is zero. The
  cylinder is the cells whose centres lie inside it (staircase).
  Gradients across a closed face are zero, which gives the walls their
  zero normal gradient. The advective (Q.grad) terms are first-order
  upwind, everything else central. Time stepping is explicit SSP-RK3,
  with the step set every step from the stiffest local rates: the drag
  in the thinnest film, 5/2 nu/h^2, and the shortest capillary wave on
  the grid. The drag is what limits it: the precursor drains ahead of
  the front to ~4 um, and the step falls to 2e-5 s. At the inlet,
  h = hN and q = its Nusselt flux, with a flat Nusselt film upstream;
  the outlet has zero gradients.

  Threads: each step is twelve phases (three per right-hand side - h
  ghosts; Phi, gradients and div Q; the fluxes - and the stage update),
  each split by rows over Threads parts, the caller doing one
  (TPlanePool). A phase reads only what earlier phases wrote, so the
  parts never race, and every value is computed by the same arithmetic
  as serially: any thread count gives the same frames to the bit.

  The arrays are plain Pascal arrays and the loops plain loops: every
  operation here is a stencil over neighbouring cells and faces, which
  no BLAS/VML primitive does. Only the frames handed out are TVMobj.
*******************************************************************************}

{$mode objfpc}{$H+}
// Build at -O3: at Lazarus's default -O1 the stepping takes 1.7 times
// as long. (An {$OPTIMIZATION LEVEL3} here is ignored; it has to be the
// project's or the command line's level.)

interface

uses
  SysUtils, Classes, Math, base64, newVM;

const
  PlaneGrav  = 9810.0;      // mm/s^2
  PlaneRhoW  = 996.5;       // kg/m^3, water at 300 K
  PlaneNuW   = 0.857;       // mm^2/s (mu 8.54e-4 Pa s)
  PlaneSgW   = 71.94e3;     // sigma/rho, mm^3/s^2 (sigma 0.07169 N/m)
  PlaneRhoAir = 1.2;
  PlaneNuAir = 10.0;        // mm^2/s, the tutorial's nu = 1e-5 m^2/s
  PlaneUAir  = 1000.0;      // mm/s

type
  TPlaneParams = record
    Angle: Double;          // incline, deg
    hN, hB: Double;         // inlet film, precursor film, mm
    X0, X1: Double;         // plate, mm down the slope
    Wd: Double;             // half width (the computed half), mm
    RCyl: Double;           // cylinder radius, mm (at the origin)
    Nx, Ny: Integer;        // cells down the slope, across the half
    Theta: Double;          // contact angle for the disjoining pressure, deg; 0 = none
    UseShear, UseCyl, Flat: Boolean;   // Flat: the plate starts covered at hN
    Threads: Integer;       // the caller plus Threads - 1 workers; default min(8, CPUs)
  end;

  TPlaneTask = procedure(Part: Integer) of object;
  TPlanePool = class;

  { One worker of a TPlanePool: runs the pool's task on its own part,
    as many times as it is told to. }
  TPlaneWorker = class(TThread)
  private
    FPool: TPlanePool;
    FPart: Integer;
    FGo: PRTLEvent;
    FGoFlag: LongInt;
  protected
    procedure Execute; override;
  public
    constructor Create(APool: TPlanePool; APart: Integer);
    destructor Destroy; override;
  end;

  { Runs Task(0 .. N-1) at once, part 0 on the calling thread, and
    returns when all are done. Hand-offs spin on a flag for up to 2 ms
    before sleeping on an event (as ufilmwrmmodel's TFilmWorker): a step
    is twelve of these, ~0.1 ms apart, so a sleeping hand-off would cost
    as much as the work. }
  TPlanePool = class
  private
    FWorkers: array of TPlaneWorker;
    FTask: TPlaneTask;
    FPending: LongInt;
    FDone: PRTLEvent;
    FError: string;
  public
    constructor Create(N: Integer);
    destructor Destroy; override;
    procedure Run(Task: TPlaneTask);
  end;

  TFilmPlaneModel = class
  protected   // TFilmPlaneCL (ufilmplanecl.pas) steps the same state on a GPU
    FP: TPlaneParams;
    Nx, Ny: Integer;
    Dx, Dy, gs, gc, FqN, PiB: Double;
    FSolid: array of Boolean;        // interior cells, i + j*Nx
    XOpen: array of Boolean;         // x-faces i = 0..Nx, i + j*(Nx+1)
    YOpen: array of Boolean;         // y-faces j = 0..Ny, i + j*Nx
    TauX: array of Double;           // 5/4 tau/rho at x-face column i
    H, Q, P: array of Double;        // h on cells, q on x-faces, p on y-faces
    H0, Q0, P0, H1, Q1, P1: array of Double;
    dH, dQ, dP: array of Double;
    Hg, Phi, Hxc, Hyc, Divc: array of Double;   // cells with x ghosts
    FClips: Int64;
    FTime: Double;
    FSteps: Int64;
    FLastDt: Double;
    // threads: FNT parts per phase; the current right-hand side's input
    // and stage; per-part clip counts and h range
    FNT: Integer;
    FPool: TPlanePool;
    FHs, FQs, FPs: PDouble;
    FStage: Integer;
    FStageDt: Double;
    FPartClips: array of Int64;
    FPartMin, FPartMax: array of Double;
    function CI(i, j: Integer): Integer; inline;
    function GI(i, j: Integer): Integer; inline;
    function XI(i, j: Integer): Integer; inline;
    function YI(i, j: Integer): Integer; inline;
    function NusseltQ(hh: Double): Double; inline;
    function PiOf(hh: Double): Double; inline;
    procedure SetupGrid;
    procedure InitState;
    procedure PartRange(n, k: Integer; out lo, hi: Integer);
    procedure Par(Task: TPlaneTask);
    procedure RHS(Hs, Qs, Ps: PDouble);
    procedure PhGhost(Part: Integer);
    procedure PhPhi(Part: Integer);
    procedure PhFlux(Part: Integer);
    procedure PhUpdate(Part: Integer);
    procedure PhRange(Part: Integer);
    procedure Step(dt: Double);
  public
    constructor Create(const AP: TPlaneParams);
    destructor Destroy; override;
    function XC(i: Integer): Double; inline;     // cell centre x, mm
    function YC(j: Integer): Double; inline;     // cell centre y, mm (half plate)
    function StableDt: Double;
    // steps up to time t exactly (the last step shortened); False if the
    // film went NaN
    function AdvanceTo(t: Double): Boolean; virtual;
    function Mass: Double;                       // mm^3, the computed half
    function FrontX(j: Integer): Double;         // furthest x with h > hN/2
    procedure HRange(out hmin, hmax: Double); virtual;   // over the fluid cells
    function MaxSpeed: Double;                   // largest |U|, mm/s
    // the full plate, mirrored about y = 0: (2 Ny, Nx), row 0 at
    // y = -Wd + dy/2, h in mm; cylinder cells hold SolidValue
    function FullPlate(SolidValue: Double): TVMobj;
    // one ParaView ImageData frame of the full plate, in SI units
    procedure WriteVTI(const FileName: string);
    property Params: TPlaneParams read FP;
    property Time: Double read FTime;
    property Steps: Int64 read FSteps;
    property Clips: Int64 read FClips;
    property LastDt: Double read FLastDt;
    property CellDx: Double read Dx;
    property CellDy: Double read Dy;
    property qN: Double read FqN;
    property ContactCoeff: Double read PiB;
    property Threads: Integer read FNT;
    function Solid(i, j: Integer): Boolean;
    function AirShear(x: Double): Double;        // 5/4 tau/rho at x, mm^2/s^2
  end;

function DefaultPlaneParams: TPlaneParams;
procedure WritePlanePVD(const FileName: string; const Times: array of Double; Count: Integer);

implementation

{$IFDEF LINUX}
function sysconf(name: LongInt): LongInt; cdecl; external 'c';
{$ENDIF}

// TThread.ProcessorCount is 1 on Linux under FPC 3.2.2 whatever the
// machine; ask glibc (_SC_NPROCESSORS_ONLN = 84) instead
function CPUCount: Integer;
begin
  {$IFDEF LINUX}
  Result := Max(1, sysconf(84));
  {$ELSE}
  Result := Max(1, TThread.ProcessorCount);
  {$ENDIF}
end;

function DefaultPlaneParams: TPlaneParams;
begin
  Result.Angle := 30;
  Result.hN := 0.141;
  Result.hB := 0.010;
  Result.X0 := -32;
  Result.X1 := 32;
  Result.Wd := 32;
  Result.RCyl := 8;
  Result.Nx := 256;
  Result.Ny := 128;
  Result.Theta := 0;
  Result.UseShear := True;
  Result.UseCyl := True;
  Result.Flat := False;
  // eight is the knee on a 16-core i7-14650HX: 0.2 s of the default
  // grid takes 15.5 s on one thread, 2.1-2.3 s on eight, 2.0-2.7 on 16
  Result.Threads := Min(8, CPUCount);
end;

{ TPlaneWorker }

const
  SpinTime = 0.002;      // s

function NowSec: Double;
begin
  Result := GetTickCount64 / 1000;
end;

// wait for Flag to be 1 and set it back to 0: spin, then after SpinTime
// sleep on Event in 1 ms naps (a missed wake-up only costs a nap)
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

constructor TPlaneWorker.Create(APool: TPlanePool; APart: Integer);
begin
  FPool := APool;
  FPart := APart;
  FGo := RTLEventCreate;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TPlaneWorker.Destroy;
begin
  Terminate;
  InterLockedExchange(FGoFlag, 1);
  RTLEventSetEvent(FGo);
  WaitFor;
  RTLEventDestroy(FGo);
  inherited Destroy;
end;

procedure TPlaneWorker.Execute;
begin
  while True do
  begin
    AwaitFlag(FGoFlag, FGo);
    if Terminated then Break;
    try
      FPool.FTask(FPart);
    except
      on E: Exception do FPool.FError := E.ClassName + ': ' + E.Message;
    end;
    InterLockedDecrement(FPool.FPending);
    RTLEventSetEvent(FPool.FDone);
  end;
end;

{ TPlanePool }

constructor TPlanePool.Create(N: Integer);
var
  k: Integer;
begin
  FDone := RTLEventCreate;
  SetLength(FWorkers, N - 1);
  for k := 1 to N - 1 do FWorkers[k - 1] := TPlaneWorker.Create(Self, k);
end;

destructor TPlanePool.Destroy;
var
  k: Integer;
begin
  for k := 0 to High(FWorkers) do FWorkers[k].Free;
  RTLEventDestroy(FDone);
  inherited Destroy;
end;

procedure TPlanePool.Run(Task: TPlaneTask);
var
  k, n: Integer;
  t0: Double;
begin
  FTask := Task;
  FError := '';
  InterLockedExchange(FPending, Length(FWorkers));
  for k := 0 to High(FWorkers) do
  begin
    InterLockedExchange(FWorkers[k].FGoFlag, 1);
    RTLEventSetEvent(FWorkers[k].FGo);
  end;
  Task(0);
  n := 0;
  t0 := 0;
  while InterLockedCompareExchange(FPending, 0, 0) <> 0 do
  begin
    Inc(n);
    if n = 1000 then
    begin
      if t0 = 0 then t0 := NowSec
      else if NowSec - t0 > SpinTime then RTLEventWaitFor(FDone, 1);
      n := 0;
    end;
  end;
  if FError <> '' then raise Exception.Create('film plane worker: ' + FError);
end;

constructor TFilmPlaneModel.Create(const AP: TPlaneParams);
var
  n: Integer;
begin
  FP := AP;
  Nx := FP.Nx;
  Ny := FP.Ny;
  Dx := (FP.X1 - FP.X0) / Nx;
  Dy := FP.Wd / Ny;
  gs := PlaneGrav * Sin(DegToRad(FP.Angle));
  gc := PlaneGrav * Cos(DegToRad(FP.Angle));
  FqN := NusseltQ(FP.hN);
  // no more parts than rows, and at least one
  FNT := EnsureRange(FP.Threads, 1, Max(1, FP.Ny div 4));
  if FNT > 1 then FPool := TPlanePool.Create(FNT);
  SetLength(FPartClips, FNT);
  SetLength(FPartMin, FNT);
  SetLength(FPartMax, FNT);
  if FP.Theta > 0 then
    PiB := 2 * PlaneSgW * (1 - Cos(DegToRad(FP.Theta))) / FP.hB
  else
    PiB := 0;
  SetupGrid;
  InitState;
  n := Nx * Ny;
  SetLength(H0, n); SetLength(H1, n); SetLength(dH, n);
  SetLength(Q0, Length(Q)); SetLength(Q1, Length(Q)); SetLength(dQ, Length(Q));
  SetLength(P0, Length(P)); SetLength(P1, Length(P)); SetLength(dP, Length(P));
  SetLength(Hg, (Nx + 2) * Ny); SetLength(Phi, (Nx + 2) * Ny);
  SetLength(Hxc, (Nx + 2) * Ny); SetLength(Hyc, (Nx + 2) * Ny); SetLength(Divc, (Nx + 2) * Ny);
  FTime := 0;
  FSteps := 0;
  FClips := 0;
  FLastDt := StableDt;
end;

destructor TFilmPlaneModel.Destroy;
begin
  FPool.Free;
  inherited Destroy;
end;

function TFilmPlaneModel.CI(i, j: Integer): Integer; inline;   // interior cell
begin
  Result := i + j * Nx;
end;

function TFilmPlaneModel.GI(i, j: Integer): Integer; inline;   // cell with ghosts, i = -1..Nx
begin
  Result := (i + 1) + j * (Nx + 2);
end;

function TFilmPlaneModel.XI(i, j: Integer): Integer; inline;   // x-face i = 0..Nx
begin
  Result := i + j * (Nx + 1);
end;

function TFilmPlaneModel.YI(i, j: Integer): Integer; inline;   // y-face j = 0..Ny
begin
  Result := i + j * Nx;
end;

function TFilmPlaneModel.XC(i: Integer): Double; inline;
begin
  Result := FP.X0 + (i + 0.5) * Dx;
end;

function TFilmPlaneModel.YC(j: Integer): Double; inline;
begin
  Result := (j + 0.5) * Dy;
end;

function TFilmPlaneModel.Solid(i, j: Integer): Boolean;
begin
  Result := FSolid[CI(i, j)];
end;

function TFilmPlaneModel.NusseltQ(hh: Double): Double; inline;
begin
  Result := gs * hh * hh * hh / (3 * PlaneNuW);
end;

// disjoining pressure / rho, mm^2/s^2: zero at h = hB, the precursor
function TFilmPlaneModel.PiOf(hh: Double): Double; inline;
var
  r: Double;
begin
  if PiB = 0 then Exit(0);
  r := FP.hB / hh;
  Result := PiB * (r * r * r - r * r);
end;

// laminar boundary-layer wall shear of the air, from the inlet edge
function TFilmPlaneModel.AirShear(x: Double): Double;
var
  xf: Double;
begin
  if not FP.UseShear then Exit(0);
  xf := Max(x - FP.X0, Dx);
  Result := 1.25 * 0.332 * (PlaneRhoAir / PlaneRhoW) * PlaneUAir * PlaneUAir
            * Sqrt(PlaneNuAir / (PlaneUAir * xf));
end;

procedure TFilmPlaneModel.SetupGrid;
var
  i, j: Integer;
begin
  SetLength(FSolid, Nx * Ny);
  for j := 0 to Ny - 1 do
    for i := 0 to Nx - 1 do
      FSolid[CI(i, j)] := FP.UseCyl and (Sqr(XC(i)) + Sqr(YC(j)) < Sqr(FP.RCyl));
  SetLength(XOpen, (Nx + 1) * Ny);
  for j := 0 to Ny - 1 do
    for i := 0 to Nx do
      if i = 0 then XOpen[XI(i, j)] := not FSolid[CI(0, j)]
      else if i = Nx then XOpen[XI(i, j)] := not FSolid[CI(Nx - 1, j)]
      else XOpen[XI(i, j)] := not (FSolid[CI(i - 1, j)] or FSolid[CI(i, j)]);
  SetLength(YOpen, Nx * (Ny + 1));
  for j := 0 to Ny do
    for i := 0 to Nx - 1 do
      if (j = 0) or (j = Ny) then YOpen[YI(i, j)] := False
      else YOpen[YI(i, j)] := not (FSolid[CI(i, j - 1)] or FSolid[CI(i, j)]);
  SetLength(TauX, Nx + 1);
  for i := 0 to Nx do
    TauX[i] := AirShear(FP.X0 + i * Dx);
end;

procedure TFilmPlaneModel.InitState;
var
  i, j: Integer;
  hh, xf: Double;
begin
  SetLength(H, Nx * Ny);
  SetLength(Q, (Nx + 1) * Ny);
  SetLength(P, Nx * (Ny + 1));
  for j := 0 to Ny - 1 do
    for i := 0 to Nx - 1 do
    begin
      if FP.Flat then hh := FP.hN
      else hh := FP.hB + (FP.hN - FP.hB) * 0.5 * (1 - Tanh((XC(i) - (FP.X0 + 1.0)) / 0.3));
      if FSolid[CI(i, j)] then hh := FP.hB;
      H[CI(i, j)] := hh;
    end;
  for j := 0 to Ny - 1 do
    for i := 0 to Nx do
    begin
      xf := FP.X0 + i * Dx;
      if FP.Flat then hh := FP.hN
      else hh := FP.hB + (FP.hN - FP.hB) * 0.5 * (1 - Tanh((xf - (FP.X0 + 1.0)) / 0.3));
      if i = 0 then hh := FP.hN;
      if XOpen[XI(i, j)] then Q[XI(i, j)] := NusseltQ(hh) else Q[XI(i, j)] := 0;
    end;
  FillChar(P[0], Length(P) * SizeOf(Double), 0);
end;

// The parts of each phase: rows (or index ranges) n*k/NT .. n*(k+1)/NT - 1
procedure TFilmPlaneModel.PartRange(n, k: Integer; out lo, hi: Integer);
begin
  lo := Int64(n) * k div FNT;
  hi := Int64(n) * (k + 1) div FNT - 1;
end;

procedure TFilmPlaneModel.Par(Task: TPlaneTask);
begin
  if FPool = nil then Task(0) else FPool.Run(Task);
end;

// time derivatives of (FHs, FQs, FPs) into (dH, dQ, dP), in three phases:
// each reads only what the phase before wrote, for any row
procedure TFilmPlaneModel.RHS(Hs, Qs, Ps: PDouble);
begin
  FHs := Hs; FQs := Qs; FPs := Ps;
  Par(@PhGhost);
  Par(@PhPhi);
  Par(@PhFlux);
end;

// h with x ghosts: a flat Nusselt film upstream, mirror at the outlet
procedure TFilmPlaneModel.PhGhost(Part: Integer);
var
  i, j, j0, j1: Integer;
begin
  PartRange(Ny, Part, j0, j1);
  for j := j0 to j1 do
  begin
    for i := 0 to Nx - 1 do Hg[GI(i, j)] := FHs[CI(i, j)];
    Hg[GI(-1, j)] := FP.hN;
    Hg[GI(Nx, j)] := FHs[CI(Nx - 1, j)];
  end;
end;

// Phi = Sg lap h + Pi/rho, cell gradients of h, div Q
procedure TFilmPlaneModel.PhPhi(Part: Integer);
var
  i, j, j0, j1, c, g: Integer;
  hc, s, hx, hy, rdx, rdy, rdx2, rdy2: Double;
begin
  rdx := 1 / Dx; rdy := 1 / Dy; rdx2 := rdx * rdx; rdy2 := rdy * rdy;
  PartRange(Ny, Part, j0, j1);
  for j := j0 to j1 do
  begin
    for i := 0 to Nx - 1 do
    begin
      c := CI(i, j); g := GI(i, j);
      if FSolid[c] then
      begin
        Phi[g] := 0; Hxc[g] := 0; Hyc[g] := 0; Divc[g] := 0;
        Continue;
      end;
      hc := Hg[g];
      s := 0; hx := 0; hy := 0;
      if XOpen[XI(i, j)] then
      begin
        s := s + (Hg[g - 1] - hc) * rdx2; hx := hx + (hc - Hg[g - 1]);
      end;
      if XOpen[XI(i + 1, j)] then
      begin
        s := s + (Hg[g + 1] - hc) * rdx2; hx := hx + (Hg[g + 1] - hc);
      end;
      if YOpen[YI(i, j)] then
      begin
        s := s + (Hg[g - (Nx + 2)] - hc) * rdy2; hy := hy + (hc - Hg[g - (Nx + 2)]);
      end;
      if YOpen[YI(i, j + 1)] then
      begin
        s := s + (Hg[g + (Nx + 2)] - hc) * rdy2; hy := hy + (Hg[g + (Nx + 2)] - hc);
      end;
      Phi[g] := PlaneSgW * s + PiOf(hc);
      Hxc[g] := 0.5 * hx * rdx;
      Hyc[g] := 0.5 * hy * rdy;
      Divc[g] := (FQs[XI(i + 1, j)] - FQs[XI(i, j)]) * rdx
               + (FPs[YI(i, j + 1)] - FPs[YI(i, j)]) * rdy;
    end;
    // inlet ghost: flat film; outlet ghost: mirror
    Phi[GI(-1, j)] := PiOf(FP.hN);
    Hxc[GI(-1, j)] := 0; Hyc[GI(-1, j)] := 0; Divc[GI(-1, j)] := 0;
    Phi[GI(Nx, j)] := Phi[GI(Nx - 1, j)];
    Hxc[GI(Nx, j)] := 0; Hyc[GI(Nx, j)] := Hyc[GI(Nx - 1, j)];
    Divc[GI(Nx, j)] := Divc[GI(Nx - 1, j)];
  end;
end;

// mass, q on x-faces, p on y-faces
procedure TFilmPlaneModel.PhFlux(Part: Integer);
var
  i, j, j0, j1, c, gL, gR, kS, kN, f: Integer;
  hf, hx, hy, ph, qq, pp, pb, qb, qx, qy, px, py, dv, D, qm, qp: Double;
  rdx, rdy: Double;
begin
  rdx := 1 / Dx; rdy := 1 / Dy;
  PartRange(Ny, Part, j0, j1);
  for j := j0 to j1 do
    for i := 0 to Nx - 1 do
    begin
      c := CI(i, j);
      if FSolid[c] then dH[c] := 0
      else dH[c] := -Divc[GI(i, j)];
    end;

  for j := j0 to j1 do
  begin
    dQ[XI(0, j)] := 0;                 // inlet flux held
    for i := 1 to Nx do
    begin
      f := XI(i, j);
      if not XOpen[f] then begin dQ[f] := 0; Continue; end;
      gL := GI(i - 1, j); gR := GI(i, j);
      hf := 0.5 * (Hg[gL] + Hg[gR]);
      hx := (Hg[gR] - Hg[gL]) * rdx;
      ph := (Phi[gR] - Phi[gL]) * rdx;
      hy := 0.5 * (Hyc[gL] + Hyc[gR]);
      dv := 0.5 * (Divc[gL] + Divc[gR]);
      qq := FQs[f];
      // p at this face: the y-faces of the two cells (mirror at outlet)
      if i < Nx then
        pb := 0.25 * (FPs[YI(i - 1, j)] + FPs[YI(i - 1, j + 1)] + FPs[YI(i, j)] + FPs[YI(i, j + 1)])
      else
        pb := 0.5 * (FPs[YI(i - 1, j)] + FPs[YI(i - 1, j + 1)]);
      // upwind q_x, q_y
      qm := FQs[XI(i - 1, j)];
      if i < Nx then qp := FQs[XI(i + 1, j)] else qp := qq;
      if qq > 0 then qx := (qq - qm) * rdx else qx := (qp - qq) * rdx;
      if pb > 0 then
      begin
        if j > 0 then qy := (qq - FQs[XI(i, j - 1)]) * rdy else qy := 0;
      end
      else
      begin
        if j < Ny - 1 then qy := (FQs[XI(i, j + 1)] - qq) * rdy else qy := 0;
      end;
      D := 2.5 * PlaneNuW / (hf * hf);
      dQ[f] := (5.0 / 6.0) * hf * (gs - gc * hx + ph)
             - D * qq
             + (9.0 / 7.0) * qq * (qq * hx + pb * hy) / (hf * hf)
             - (8.0 / 7.0) * (qq * qx + pb * qy) / hf
             - (9.0 / 7.0) * qq * dv / hf
             + TauX[i];
    end;
  end;

  // the y-face rows 0 .. Ny, split on their own
  PartRange(Ny + 1, Part, j0, j1);
  for j := j0 to j1 do
    for i := 0 to Nx - 1 do
    begin
      f := YI(i, j);
      if not YOpen[f] then begin dP[f] := 0; Continue; end;
      kS := GI(i, j - 1); kN := GI(i, j);
      hf := 0.5 * (Hg[kS] + Hg[kN]);
      hy := (Hg[kN] - Hg[kS]) * rdy;
      ph := (Phi[kN] - Phi[kS]) * rdy;
      hx := 0.5 * (Hxc[kS] + Hxc[kN]);
      dv := 0.5 * (Divc[kS] + Divc[kN]);
      pp := FPs[f];
      qb := 0.25 * (FQs[XI(i, j - 1)] + FQs[XI(i + 1, j - 1)] + FQs[XI(i, j)] + FQs[XI(i + 1, j)]);
      if qb > 0 then
      begin
        if i > 0 then px := (pp - FPs[YI(i - 1, j)]) * rdx else px := pp * rdx;
      end
      else
      begin
        if i < Nx - 1 then px := (FPs[YI(i + 1, j)] - pp) * rdx else px := 0;
      end;
      if pp > 0 then py := (pp - FPs[YI(i, j - 1)]) * rdy
      else py := (FPs[YI(i, j + 1)] - pp) * rdy;
      D := 2.5 * PlaneNuW / (hf * hf);
      dP[f] := (5.0 / 6.0) * hf * (-gc * hy + ph)
             - D * pp
             + (9.0 / 7.0) * pp * (qb * hx + pp * hy) / (hf * hf)
             - (8.0 / 7.0) * (qb * px + pp * py) / hf
             - (9.0 / 7.0) * pp * dv / hf;
    end;
end;

// one SSP-RK3 stage (FStage) on this part's slice of every array, then
// h clipped at a tenth of the precursor, the clips counted per part
procedure TFilmPlaneModel.PhUpdate(Part: Integer);
var
  k, lo, hi: Integer;
  dt, hlo: Double;
  Hn: PDouble;
begin
  dt := FStageDt;
  PartRange(Length(H), Part, lo, hi);
  case FStage of
    1: for k := lo to hi do begin H0[k] := H[k]; H1[k] := H[k] + dt * dH[k]; end;
    2: for k := lo to hi do H1[k] := 0.75 * H0[k] + 0.25 * (H1[k] + dt * dH[k]);
    3: for k := lo to hi do H[k] := H0[k] / 3 + (2.0 / 3.0) * (H1[k] + dt * dH[k]);
  end;
  if FStage = 3 then Hn := @H[0] else Hn := @H1[0];
  hlo := 0.1 * FP.hB;
  for k := lo to hi do
    if Hn[k] < hlo then
    begin
      Hn[k] := hlo;
      Inc(FPartClips[Part]);
    end;
  PartRange(Length(Q), Part, lo, hi);
  case FStage of
    1: for k := lo to hi do begin Q0[k] := Q[k]; Q1[k] := Q[k] + dt * dQ[k]; end;
    2: for k := lo to hi do Q1[k] := 0.75 * Q0[k] + 0.25 * (Q1[k] + dt * dQ[k]);
    3: for k := lo to hi do Q[k] := Q0[k] / 3 + (2.0 / 3.0) * (Q1[k] + dt * dQ[k]);
  end;
  PartRange(Length(P), Part, lo, hi);
  case FStage of
    1: for k := lo to hi do begin P0[k] := P[k]; P1[k] := P[k] + dt * dP[k]; end;
    2: for k := lo to hi do P1[k] := 0.75 * P0[k] + 0.25 * (P1[k] + dt * dP[k]);
    3: for k := lo to hi do P[k] := P0[k] / 3 + (2.0 / 3.0) * (P1[k] + dt * dP[k]);
  end;
end;

procedure TFilmPlaneModel.PhRange(Part: Integer);
var
  c, lo, hi: Integer;
  mn, mx: Double;
begin
  PartRange(Length(H), Part, lo, hi);
  mn := 1e30; mx := 0;
  for c := lo to hi do
    if not FSolid[c] then
    begin
      if H[c] < mn then mn := H[c];
      if H[c] > mx then mx := H[c];
    end;
  FPartMin[Part] := mn;
  FPartMax[Part] := mx;
end;

// stable step: drag in the thinnest film, the shortest capillary wave
// (and the disjoining-pressure wave) in the thickest
function TFilmPlaneModel.StableDt: Double;
var
  hmin, hmax, kk, w, wd: Double;
begin
  HRange(hmin, hmax);
  kk := 4 / (Dx * Dx) + 4 / (Dy * Dy);
  w := Sqrt((5.0 / 6.0) * PlaneSgW * hmax) * kk;
  if PiB <> 0 then
  begin
    // |Pi'| peaks near the precursor: B (3 b^3/h^4 - 2 b^2/h^3) at h ~ b
    wd := Sqrt((5.0 / 6.0) * hmin * PiB * 3 / FP.hB * kk);
    w := Max(w, wd);
  end;
  Result := Min(0.9 * 2.5 / (2.5 * PlaneNuW / (hmin * hmin)), 0.8 * Sqrt(3) / w);
end;

// SSP-RK3: each stage a right-hand side and an update, every one of the
// twelve phases split over the threads
procedure TFilmPlaneModel.Step(dt: Double);
var
  k: Integer;
begin
  FStageDt := dt;
  RHS(@H[0], @Q[0], @P[0]);
  FStage := 1; Par(@PhUpdate);
  RHS(@H1[0], @Q1[0], @P1[0]);
  FStage := 2; Par(@PhUpdate);
  RHS(@H1[0], @Q1[0], @P1[0]);
  FStage := 3; Par(@PhUpdate);
  for k := 0 to FNT - 1 do
  begin
    Inc(FClips, FPartClips[k]);
    FPartClips[k] := 0;
  end;
end;

function TFilmPlaneModel.AdvanceTo(t: Double): Boolean;
var
  dt: Double;
begin
  while FTime < t - 1e-9 do
  begin
    dt := StableDt;
    if FTime + dt > t then dt := t - FTime;
    Step(dt);
    FTime := FTime + dt;
    FLastDt := dt;
    Inc(FSteps);
    if IsNan(H[0]) then Exit(False);
  end;
  FTime := t;
  Result := True;
end;

function TFilmPlaneModel.Mass: Double;
var
  c: Integer;
begin
  Result := 0;
  for c := 0 to High(H) do
    if not FSolid[c] then Result := Result + H[c];
  Result := Result * Dx * Dy;
end;

function TFilmPlaneModel.FrontX(j: Integer): Double;
var
  i: Integer;
begin
  Result := FP.X0;
  for i := 0 to Nx - 1 do
    if (not FSolid[CI(i, j)]) and (H[CI(i, j)] > 0.5 * FP.hN) then Result := XC(i);
end;

procedure TFilmPlaneModel.HRange(out hmin, hmax: Double);
var
  k: Integer;
begin
  Par(@PhRange);
  hmin := FPartMin[0]; hmax := FPartMax[0];
  for k := 1 to FNT - 1 do
  begin
    hmin := Min(hmin, FPartMin[k]);
    hmax := Max(hmax, FPartMax[k]);
  end;
end;

function TFilmPlaneModel.MaxSpeed: Double;
var
  i, j, c: Integer;
  u, v: Double;
begin
  Result := 0;
  for j := 0 to Ny - 1 do
    for i := 0 to Nx - 1 do
    begin
      c := CI(i, j);
      if FSolid[c] then Continue;
      u := 0.5 * (Q[XI(i, j)] + Q[XI(i + 1, j)]) / H[c];
      v := 0.5 * (P[YI(i, j)] + P[YI(i, j + 1)]) / H[c];
      Result := Max(Result, Sqrt(u * u + v * v));
    end;
end;

function TFilmPlaneModel.FullPlate(SolidValue: Double): TVMobj;
var
  i, j, r, c: Integer;
  D: PDouble;
begin
  Result := TVMobj.Create(2 * Ny, Nx);
  D := Result.DataPtr;
  for r := 0 to 2 * Ny - 1 do
  begin
    if r < Ny then j := Ny - 1 - r else j := r - Ny;
    for i := 0 to Nx - 1 do
    begin
      c := CI(i, j);
      if FSolid[c] then D[i + r * Nx] := SolidValue
      else D[i + r * Nx] := H[c];
    end;
  end;
end;

// ---------------------------------------------------------------- VTK output

// ParaView 5.11 as packaged for Ubuntu 24.04 cannot read raw appended
// data: with expat 2.6 its parser runs on into the binary block and fails
// with "not well-formed (invalid token)", even on files VTK wrote itself.
// So every array is written inline as base64 (format="binary"): a UInt32
// byte count followed by the data, encoded as one block.
function B64Block(const Buf: array of Single): string;
var
  raw: RawByteString;
  nb: LongWord;
begin
  nb := Length(Buf) * SizeOf(Single);
  SetLength(raw, 4 + nb);
  Move(nb, raw[1], 4);
  if nb > 0 then Move(Buf[0], raw[5], nb);
  Result := EncodeStringBase64(raw);
end;

// The full plate is written, y = -Wd .. Wd: rows 0 .. Ny-1 are the
// mirror image of the computed half (v reversed), rows Ny .. 2Ny-1 the
// half itself. (ParaView's Reflect turns image cells inside out, which
// spoils the lighting of the mirrored half.) Point data at the cell
// centres: h (m), U (m/s), q (m^2/s) and solid (1 in the cylinder).
procedure TFilmPlaneModel.WriteVTI(const FileName: string);
var
  F: TFileStream;
  n, i, j, r, c, o: Integer;
  bufH, bufQ, bufS, bufU: array of Single;
  hh, u, v: Double;
  procedure S(const t: string);
  begin
    if t <> '' then F.WriteBuffer(t[1], Length(t));
  end;
  procedure Arr(const AName: string; Comps: Integer; const Buf: array of Single);
  begin
    S(Format('<DataArray type="Float32" Name="%s" NumberOfComponents="%d" format="binary">'#10,
      [AName, Comps]));
    S(B64Block(Buf));
    S(#10'</DataArray>'#10);
  end;
begin
  n := Nx * 2 * Ny;
  SetLength(bufH, n); SetLength(bufQ, n); SetLength(bufS, n); SetLength(bufU, 3 * n);
  for r := 0 to 2 * Ny - 1 do
    for i := 0 to Nx - 1 do
    begin
      if r < Ny then j := Ny - 1 - r else j := r - Ny;
      c := CI(i, j);
      o := i + r * Nx;
      hh := H[c];
      if FSolid[c] then
      begin
        u := 0; v := 0; bufS[o] := 1; hh := 0;
      end
      else
      begin
        u := 0.5 * (Q[XI(i, j)] + Q[XI(i + 1, j)]) / hh;
        v := 0.5 * (P[YI(i, j)] + P[YI(i, j + 1)]) / hh;
        if r < Ny then v := -v;
        bufS[o] := 0;
      end;
      bufH[o] := hh * 1e-3;                            // m
      bufQ[o] := Sqrt(Sqr(u) + Sqr(v)) * hh * 1e-6;    // m^2/s
      bufU[3 * o] := u * 1e-3; bufU[3 * o + 1] := v * 1e-3; bufU[3 * o + 2] := 0;
    end;
  F := TFileStream.Create(FileName, fmCreate);
  try
    S('<?xml version="1.0"?>'#10);
    S('<VTKFile type="ImageData" version="1.0" byte_order="LittleEndian" header_type="UInt32">'#10);
    S(Format('<ImageData WholeExtent="0 %d 0 %d 0 0" Origin="%.9g %.9g 0" Spacing="%.9g %.9g 1">'#10,
      [Nx - 1, 2 * Ny - 1, (FP.X0 + 0.5 * Dx) * 1e-3, (0.5 * Dy - FP.Wd) * 1e-3, Dx * 1e-3, Dy * 1e-3]));
    S(Format('<Piece Extent="0 %d 0 %d 0 0">'#10, [Nx - 1, 2 * Ny - 1]));
    S('<PointData Scalars="h" Vectors="U">'#10);
    Arr('h', 1, bufH);
    Arr('U', 3, bufU);
    Arr('q', 1, bufQ);
    Arr('solid', 1, bufS);
    S('</PointData>'#10'</Piece>'#10'</ImageData>'#10'</VTKFile>'#10);
  finally
    F.Free;
  end;
end;

// the frames' time index, wrm_NNNN.vti beside it
procedure WritePlanePVD(const FileName: string; const Times: array of Double; Count: Integer);
var
  L: TStringList;
  k: Integer;
begin
  L := TStringList.Create;
  try
    L.Add('<?xml version="1.0"?>');
    L.Add('<VTKFile type="Collection" version="1.0" byte_order="LittleEndian">');
    L.Add('<Collection>');
    for k := 0 to Count - 1 do
      L.Add(Format('<DataSet timestep="%.6g" group="" part="0" file="wrm_%.4d.vti"/>',
        [Times[k], k]));
    L.Add('</Collection>');
    L.Add('</VTKFile>');
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
end;

end.
