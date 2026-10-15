unit ubenney2dmodel;

{*******************************************************************************

     The 2-D Benney equation for a thin liquid film flowing down an
     inclined plane, in physical units (mm, s), on a Fourier x Chebyshev
     tensor grid.

     Equation. With h(x, y, t) the film thickness, x down the slope and
     y across it, mass conservation h_t + div q = 0 with the Benney flux

       q_x = g s/(3 nu) h^3 + [2 g^2 s^2/(15 nu^3) h^6 - g c/(3 nu) h^3] h_x
             + sigma/(3 rho nu) h^3 (lap h)_x
       q_y =                  - g c/(3 nu) h^3 h_y
             + sigma/(3 rho nu) h^3 (lap h)_y

     (s = sin theta, c = cos theta): gravity along the slope drives the
     flow, inertia (the h^6 term) is the long-wave instability and acts
     downslope only, the normal component of gravity (hydrostatic
     pressure) and surface tension (the curvature lap h) smooth the
     film in both directions. Everything is scaled by the flat-film
     thickness hN, H = h/hN, so the code works with

       H_t = -(d/dx Qx + d/dy Qy),
       Qx = A H^3 + (I H^6 - G H^3) H_x + S H^3 (lap H)_x
       Qy =       - G H^3 H_y         + S H^3 (lap H)_y
       A = g s hN^2/(3 nu), I = 2 g^2 s^2 hN^6/(15 nu^3),
       G = g c hN^3/(3 nu), S = (sigma/rho) hN^3/(3 nu).

     Linear theory for H = 1 + e: growth rate (I - G) kx^2 - G ky^2
     - S (kx^2 + ky^2)^2, so the film is unstable when I > G, i.e.
     Re > Re_c = (5/6) cot theta with Re = g s hN^3/(3 nu^2) (the
     flow rate over nu); waves travel at 3A mm/s.

     Excitation (optional, Excite): a source added to H_t,

       s(x, t) = a c cos(2 pi t/T) g(x),

     g a Gaussian of half-width ExciteWidth (5 mm) about x = 0 with
     unit integral, uniform across the plate - a line source, like a
     pulsed inlet. In the kinematic limit h_t + c h_x = s a narrow
     source launches h = (1/c) int s dx downstream, so a is the
     thickness amplitude of the wave it launches (in hN; the form takes
     um) and the wavelength is c T. Its time mean is zero: no net water
     is added. The domain is periodic, so the waves come round to x = 0
     again after Lx/c seconds and pass through the source.
     ExciteMod > 0 modulates the source across the plate,
     x (1 + ExciteMod cos(n pi (y + W/2)/W)) with n = ExciteModN: the
     cosine has zero slope and third derivative at both walls, so it
     meets the wall conditions, and its plate average is unchanged. It
     seeds the transverse structure a uniform source never can: from a
     flat film a y-uniform source keeps the film y-uniform to rounding
     error. (As in the spanwise-forced experiments of Liu, Schneider &
     Gollub 1995.)

     Absorbing zone (optional, Absorb): -sigma(x) (H - 1) added to H_t,
     sigma = AbsorbRate sin^2(pi u) for u = (x - x0)/AbsorbLength in
     0..1, the zone ending AbsorbGap short of x = Lx so it stays clear
     of the source at x = 0 (the same point, periodically). It relaxes
     the film back to flat, so waves leave at x = Lx instead of coming
     round again: with the excitation, x = 0 behaves as an inlet. The
     smooth bell avoids the reflection a step in sigma would cause. A
     linear wave keeps exp(-AbsorbRate AbsorbLength/(2c)) of itself
     (0.7 % at the defaults). It is explicit, like the excitation.

     Validity. The Benney equation is a long-wave expansion and blows
     up in finite time once Re is more than a few (Pumir, Manneville &
     Pomeau 1983). Checked with scipy's stiff BDF in 1-D, 20 % above
     onset: a 1 mm water film (Re 57) blows up, so do 0.5 mm (Re 20)
     and 0.3 mm (Re 9.4); 0.2 mm on 11.2 deg (Re 5.1) is stable, which
     is the default here. Even at 0.2 mm the film blows up once it is
     50 % above onset.

     Grid. x is periodic on 0 .. Lx with Nx equally spaced points
     (Fourier, through FFT_R2C/FFT_C2R row by row); y runs across the
     plate, -W/2 .. W/2, on the Ny+1 Chebyshev-Gauss-Lobatto points
     y_j = (W/2) cos(pi j/Ny), differentiated with the Chebyshev
     matrix D (one MatMult for the whole grid). A field is a (Ny+1, Nx)
     TVMobj: row j is the x-line at y_j.

     Side walls: no flux, h_y = 0 and h_yyy = 0 at y = +-W/2 (the film
     meets the walls square, as if mirrored). With h_y = 0 along the
     whole wall h_xxy = 0 there too, so q_y = 0.

     Threads. The x and y derivatives are independent, so each
     right-hand side runs three phases, each one x part on a worker
     thread (TDerivWorker) while the calling thread does the y part:
       1. H_x, H_xx  |  H_y, H_yy          then lap H = H_xx + H_yy
       2. (lap H)_x  |  (lap H)_y          then Qx, Qy
       3. (Qx)_x     |  (Qy)_y             then H_t
     Threaded = False runs them one after the other, for comparison;
     the time spent in each half is kept (XTime, YTime, RHSTime). The
     halves are unequal: 65 rows of FFTs (three transforms a row in
     phase 1) cost about seven times the y half's few MatMults, so the
     overlap saves only the y half's time. MKL and OpenBLAS are each set
     to one thread (see Create): their own thread pools cost more than
     they saved on matrices this small, and fought the worker.

     Time stepping. A dense Jacobian (the 1-D demo's Kaps-Rentrop) is
     out of the question at (Ny+1) Nx ~ 8000 unknowns. Instead the
     stiff linear part is implicit and the rest explicit (semi-implicit
     BDF2, "SBDF2"): with E the x-Fourier modes of H - 1,

       E_t = L E + N(H),   N = modes(H_t) - L E

     where for mode kx, L = c(kx) + beta (G + 2 S kx^2) D2 - beta S D4,
     c(kx) = -3A i kx + I kx^2 - beta G kx^2 - beta S kx^4 - the
     linearised operator about the flat film, with the smoothing terms
     multiplied by beta. Each step solves, for every kx separately, one
     (Ny+1) x (Ny+1) complex system (a0 - dt L) E_new = rhs, LU-factored
     once per step size and reused (LinearSolveZ). The wall conditions
     replace the system's rows 0 and Ny (D1 = 0) and 1 and Ny-1
     (D3 = 0). Checked in a numpy prototype: with those rows the
     operator has no spurious unstable modes, each mode's largest
     growth rate matching linear theory to nine digits.
     - beta: where the film is thicker than 1 the explicit remainder
       S (H^3 - beta) lap^2 is anti-damping; SBDF2 needs H^3 < 4/3 beta.
       beta = 1 blew up a 0.2 bump; beta = 1.5 is the default and is
       raised (refactorising) if max H^3 approaches it.
     - Variable step: the BDF2 coefficients for step ratio w are
       a0 = (1 + 2w)/(1 + w), rhs = (1 + w) E_n - w^2/(1 + w) E_n-1
       + dt ((1 + w) N_n - w N_n-1). The local error is estimated from
       the gap to a quadratic extrapolation of the last three steps
       (x 2/11, the BDF2/predictor error constants) and kept below Tol.
       A new step size costs two refactorisations of every mode, so the
       step shrinks only on a rejected step and grows (by up to 2x)
       only when the error is under a fifth of Tol.
     - Accuracy check (prototype and here): a small cos(kx x) cos(pi y'/W)
       mode grows at the linear rate to 1 %.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

interface

uses
  Classes, SysUtils, Math, newVM, newVMComplex, oneapi;

type
  TBenney2DParams = record
    hN: Double;          // flat film thickness, mm
    Theta: Double;       // inclination, radians
    Lx, W: Double;       // downslope period and plate width, mm
    Nx, Ny: Integer;     // Fourier points; Chebyshev intervals (Ny+1 points)
    Nu: Double;          // kinematic viscosity, mm^2/s
    SigmaRho: Double;    // surface tension / density, mm^3/s^2
    Tol: Double;         // local error per step, in units of hN
    Threaded: Boolean;   // x and y derivatives on two threads
    // excitation at x = 0: a source a c cos(2 pi t/T) g(x) in H_t - see
    // the header. ExciteAmp is a, the thickness amplitude it launches
    // (in units of hN); ExciteWidth the Gaussian's half-width, mm
    Excite: Boolean;
    ExciteAmp, ExcitePeriod, ExciteWidth: Double;
    // transverse modulation of the source: x (1 + ExciteMod cos(n pi
    // (y + W/2)/W)), n = ExciteModN half-waves across the plate
    ExciteMod: Double;
    ExciteModN: Integer;
    // absorbing zone before x = Lx: -sigma(x) (H - 1) in H_t, sigma a
    // sin^2 bell of peak AbsorbRate (1/s) over AbsorbLength (mm),
    // ending AbsorbGap (mm) short of Lx - see the header
    Absorb: Boolean;
    AbsorbLength, AbsorbRate, AbsorbGap: Double;
  end;

  { Runs a method on its own thread on request: Run starts it, Wait
    blocks until it has finished. One per model, kept for its life.
    Both sides spin on a flag for up to SpinTime before sleeping on an
    event: a sleeping thread took ~115 us to wake (measured: a threaded
    right-hand side cost 1 s more over 2890 calls than a serial one,
    three hand-offs each), as long as the work being overlapped. }
  TDerivWorker = class(TThread)
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

  TBenney2DModel = class
  private
    FP: TBenney2DParams;
    FA, FI, FG, FS: Double;
    FBeta: Double;
    FNx, FNc, FNy1: Integer;
    FK, FK1: array of Double;         // FK1: Nyquist 0, for odd orders
    FFac: array[1..3] of TVMobjZ;     // (i k)^order, (1, Nc)
    FD1, FD2, FD3, FD4: TVMobj;       // Chebyshev, d/dy in mm
    FX, FY: TVMobj;                   // grid coordinates, (1, Nx), (Ny1, 1)
    FWorker: TDerivWorker;
    // phase inputs and outputs, shared with the worker
    FIn, FKap, FQx, FQy: TVMobj;
    FHx, FHxx, FHy, FHyy, FKx, FKy, FDqx, FDqy: TVMobj;
    FXTime, FYTime, FRHSTime: Double;
    FRHSCalls: Int64;
    FSolveTime, FApplyLTime, FModesTime, FSysTime: Double;
    // stepping state: history 0 (oldest) .. 2 (newest)
    FT: array[0..2] of Double;
    FE, FN: array[0..2] of TVMobjZ;
    FH: TVMobj;                       // H at FT[2]
    FDt: Double;
    FSteps, FRejected, FFactorisations: Integer;
    // two cached sets of per-mode factorised systems, keyed (a0, dt)
    FSys: array[0..1] of array of TVMobjZ;
    FSysA0, FSysDt: array[0..1] of Double;
    FSysNext: Integer;
    FSource: TVMobjZ;                 // modes of S0 g(x), every row
    FSponge: TVMobj;                  // sigma(x) on every row, 1/s
    function XDeriv(const F: TVMobj; Order: Integer): TVMobj;
    procedure XDeriv2(const F: TVMobj; O1, O2: Integer; out R1, R2: TVMobj);
    procedure XPhase1;
    procedure YPhase1;
    procedure XPhase2;
    procedure YPhase2;
    procedure XPhase3;
    procedure YPhase3;
    procedure RunPhase(XP, YP: TThreadMethod);
    function NHat(const H: TVMobj; const E: TVMobjZ; t: Double): TVMobjZ;
    function ApplyL(const E: TVMobjZ): TVMobjZ;
    function ModeCoef(m: Integer): TComplex16;
    function Systems(a0, dt: Double): Integer;
    function SolveModes(Slot: Integer; const R: TVMobjZ): TVMobjZ;
  public
    constructor Create(const P: TBenney2DParams);
    destructor Destroy; override;
    function RHS(const H: TVMobj): TVMobj;          // H_t
    function ToModes(const F: TVMobj): TVMobjZ;     // (Ny1, Nx) -> (Ny1, Nc)
    function FromModes(const E: TVMobjZ): TVMobj;   // and back
    // initial conditions, in units of hN
    function Flat: TVMobj;
    function Bump(Amp, X0, Radius: Double): TVMobj;
    function Noise(Amp: Double; Seed: LongInt): TVMobj;
    // (Nyd, Ny+1): values on the Chebyshev points -> Nyd equally spaced
    // y from -W/2 to W/2 (row 0 at -W/2), by barycentric interpolation
    function UniformRows(Nyd: Integer): TVMobj;
    // integration
    procedure Start(const H0: TVMobj; dt0: Double);
    function Advance(out Msg: string): Boolean;     // one accepted step
    property Time: Double read FT[2];
    property H: TVMobj read FH;
    property Dt: Double read FDt;
    property Steps: Integer read FSteps;
    property Rejected: Integer read FRejected;
    property Factorisations: Integer read FFactorisations;
    property Beta: Double read FBeta;
    // the physics
    function Re: Double;              // flow rate / nu
    function ReCrit: Double;          // (5/6) cot theta
    function WaveSpeed: Double;       // 3A, mm/s
    function FastestK: Double;        // 1/mm, 0 if stable
    function GrowthAt(k: Double): Double;   // 1/s, a downslope wave of wavenumber k
    function GrowthAt2(kx, ky: Double): Double;   // 1/s, an oblique wave
    function ExciteSource(t: Double): TVMobj; // the source term at t, for checks
    function SpongeRate(x: Double): Double;   // sigma(x), 1/s
    function AbsorbStart: Double;             // where the zone begins, mm
    function AbsorbedFraction: Double;        // of a linear wave crossing it
    function MaxGrowth: Double;       // 1/s
    property Params: TBenney2DParams read FP;
    property X: TVMobj read FX;
    property Y: TVMobj read FY;
    property XTime: Double read FXTime;
    property YTime: Double read FYTime;
    property RHSTime: Double read FRHSTime;
    property RHSCalls: Int64 read FRHSCalls;
    property SolveTime: Double read FSolveTime;
    property ApplyLTime: Double read FApplyLTime;
    property ModesTime: Double read FModesTime;
    property SysTime: Double read FSysTime;
  end;

const
  GravMM = 9810.0;     // mm/s^2

function DefaultBenney2DParams: TBenney2DParams;
function CentreRow(const P: TBenney2DParams): Integer;   // y = 0 (or nearest)

implementation

uses
  {$IFDEF LINUX} Linux, UnixType, {$ENDIF}
  dynlibs, cblas;

type
  TSetNumThreads = procedure(n: LongInt); cdecl;

{ OpenBLAS (behind MatMult) runs its own pool of busy-waiting threads.
  Pinned to two cores, the y half's MatMults went from 0.20 s to 3.0 s
  once the x half ran beside them, the pool fighting the worker. The
  CBLAS library is already loaded by InitializeCBLAS, so LoadLibrary
  just returns its handle; ArmPL and Accelerate have no such entry
  point and are left alone. }
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

function DefaultBenney2DParams: TBenney2DParams;
begin
  Result.hN := 0.2;
  Result.Theta := DegToRad(11.2);
  Result.Lx := 300;
  Result.W := 300;
  Result.Nx := 128;
  Result.Ny := 64;
  Result.Nu := 1.0;            // water, 20 C: 1.0e-6 m^2/s
  Result.SigmaRho := 72.0e3;   // 0.072 N/m / 1000 kg/m^3 = 7.2e-5 m^3/s^2
  Result.Tol := 1e-4;
  Result.Threaded := True;
  Result.Excite := False;
  Result.ExciteAmp := 0.005;     // 1 um on 0.2 mm
  Result.ExcitePeriod := 1.0;
  Result.ExciteWidth := 5.0;
  Result.ExciteMod := 0;
  Result.ExciteModN := 2;
  Result.Absorb := False;
  Result.AbsorbLength := 75;     // about one fastest-growing wavelength
  Result.AbsorbRate := 10;       // passes ~0.7 % of a wave at 76 mm/s
  Result.AbsorbGap := 15;        // clear of the 5 mm source at x = 0 = Lx
end;

function CentreRow(const P: TBenney2DParams): Integer;
begin
  Result := P.Ny div 2;
end;

{ Seconds on a monotonic clock, microsecond-or-better resolution: the
  phases being timed take tens of microseconds, so GetTickCount64's
  milliseconds won't do. Thread-safe (no shared buffer). }
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

{ TDerivWorker }

const
  SpinTime = 0.002;      // s

constructor TDerivWorker.Create;
begin
  FGo := RTLEventCreate;
  FDone := RTLEventCreate;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TDerivWorker.Destroy;
begin
  Terminate;
  InterLockedExchange(FGoFlag, 1);
  RTLEventSetEvent(FGo);
  WaitFor;
  RTLEventDestroy(FGo);
  RTLEventDestroy(FDone);
  inherited Destroy;
end;

// spin on Flag for up to SpinTime, then sleep on Event in 1 ms slices;
// clears Flag once it is seen set. The event can be left set by a
// hand-off the spin already caught - harmless, the flag decides.
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

procedure TDerivWorker.Execute;
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

procedure TDerivWorker.Run(ATask: TThreadMethod);
begin
  FTask := ATask;
  FError := '';
  InterLockedExchange(FGoFlag, 1);      // a full barrier: FTask is visible first
  RTLEventSetEvent(FGo);
end;

procedure TDerivWorker.Wait;
begin
  AwaitFlag(FDoneFlag, FDone);
  if FError <> '' then raise Exception.Create('x-derivative thread: ' + FError);
end;

{ TBenney2DModel }

constructor TBenney2DModel.Create(const P: TBenney2DParams);
var
  i, j, n: Integer;
  s, c, k: Double;
  cc: array of Double;
  YP, DP: PDouble;
  F1, F2, F3: PComplex16;
begin
  inherited Create;
  Assert(P.Nx mod 2 = 0, 'Nx must be even');
  Assert(P.Ny mod 2 = 0, 'Ny must be even (y = 0 is then a grid line)');
  FP := P;
  s := Sin(P.Theta);
  c := Cos(P.Theta);
  FA := GravMM * s * Sqr(P.hN) / (3 * P.Nu);
  FI := 2 * Sqr(GravMM * s) * IntPower(P.hN, 6) / (15 * IntPower(P.Nu, 3));
  FG := GravMM * c * IntPower(P.hN, 3) / (3 * P.Nu);
  FS := P.SigmaRho * IntPower(P.hN, 3) / (3 * P.Nu);
  FBeta := 1.5;

  FNx := P.Nx;
  FNc := P.Nx div 2 + 1;
  FNy1 := P.Ny + 1;

  // x: Fourier
  FX := TVMobj.Create(1, FNx);
  for i := 0 to FNx - 1 do FX.DataPtr[i] := i * P.Lx / FNx;
  SetLength(FK, FNc);
  SetLength(FK1, FNc);
  for i := 0 to FNc - 1 do
  begin
    FK[i] := 2 * Pi * i / P.Lx;
    FK1[i] := FK[i];
  end;
  FK1[FNc - 1] := 0;                 // the Nyquist bin, for odd derivatives
  for n := 1 to 3 do FFac[n] := TVMobjZ.Create(1, FNc);
  F1 := FFac[1].DataPtr; F2 := FFac[2].DataPtr; F3 := FFac[3].DataPtr;
  for i := 0 to FNc - 1 do
  begin
    k := FK[i];
    F1[i] := Cplx(0, FK1[i]);                 // i k
    F2[i] := Cplx(-k * k, 0);                 // (i k)^2
    F3[i] := Cplx(0, -IntPower(FK1[i], 3));   // (i k)^3
  end;

  // y: Chebyshev-Gauss-Lobatto, Trefethen's cheb, scaled to -W/2 .. W/2
  n := P.Ny;
  FY := TVMobj.Create(FNy1, 1);
  YP := FY.DataPtr;
  SetLength(cc, FNy1);
  for j := 0 to n do
  begin
    YP[j] := Cos(Pi * j / n);            // on [-1, 1] for now
    if (j = 0) or (j = n) then cc[j] := 2 else cc[j] := 1;
    if Odd(j) then cc[j] := -cc[j];
  end;
  FD1 := TVMobj.Create(FNy1, FNy1);
  DP := FD1.DataPtr;
  for i := 0 to n do
  begin
    s := 0;
    for j := 0 to n do
      if i <> j then
      begin
        DP[i * FNy1 + j] := cc[i] / cc[j] / (YP[i] - YP[j]);
        s := s + DP[i * FNy1 + j];
      end;
    DP[i * FNy1 + i] := -s;              // rows sum to zero: exact on constants
  end;
  FD1 := FD1 * (2 / P.W);
  for j := 0 to n do YP[j] := YP[j] * P.W / 2;
  FD2 := MatMult(FD1, FD1);
  FD3 := MatMult(FD2, FD1);
  FD4 := MatMult(FD2, FD2);

  if P.Excite then FSource := ToModes(ExciteSource(0));
  if P.Absorb then
  begin
    FSponge := TVMobj.Create(FNy1, FNx);
    for i := 0 to FNx - 1 do
    begin
      k := SpongeRate(FX.DataPtr[i]);
      for j := 0 to FNy1 - 1 do FSponge.DataPtr[j * FNx + i] := k;
    end;
  end;
  // FWorker is created on the first threaded right-hand side, so a
  // model built only for its physics (the form's memo) starts no thread
  {$IFDEF HAVE_MKL}
  // every LAPACK/BLAS call here is small (65 x 65 solves, 65 x 128
  // products) and MKL's own thread team cost more than it saved -
  // measured: a 20 s run took 16.4 s of wall time with MKL threaded and
  // 8.7 s with it single-threaded, the per-mode solves going from 10.3
  // to 3.0 s. The parallelism here is the x/y split instead. This
  // setting is process-wide.
  MKL_Set_Num_Threads(1);
  {$ENDIF}
  SingleThreadedBLAS;
end;

destructor TBenney2DModel.Destroy;
begin
  FWorker.Free;
  inherited Destroy;
end;

function TBenney2DModel.Re: Double;
begin
  Result := GravMM * Sin(FP.Theta) * IntPower(FP.hN, 3) / (3 * Sqr(FP.Nu));
end;

function TBenney2DModel.ReCrit: Double;
begin
  Result := 5 / 6 / Tan(FP.Theta);
end;

function TBenney2DModel.WaveSpeed: Double;
begin
  Result := 3 * FA;
end;

function TBenney2DModel.FastestK: Double;
begin
  if FI > FG then Result := Sqrt((FI - FG) / (2 * FS)) else Result := 0;
end;

function TBenney2DModel.GrowthAt(k: Double): Double;
begin
  Result := (FI - FG) * k * k - FS * k * k * k * k;
end;

// linear theory: (I - G) kx^2 - G ky^2 - S (kx^2 + ky^2)^2
function TBenney2DModel.GrowthAt2(kx, ky: Double): Double;
begin
  Result := (FI - FG) * kx * kx - FG * ky * ky - FS * Sqr(kx * kx + ky * ky);
end;

function TBenney2DModel.MaxGrowth: Double;
begin
  if FI > FG then Result := Sqr(FI - FG) / (4 * FS) else Result := 0;
end;

{ ---- x derivatives: FFT along each row ---- }

procedure TBenney2DModel.XDeriv2(const F: TVMobj; O1, O2: Integer; out R1, R2: TVMobj);
var
  j: Integer;
  row, back: TVMobj;
  S: TVMobjZ;
  FPtr: PDouble;
begin
  R1 := TVMobj.Create(FNy1, FNx);
  if O2 > 0 then R2 := TVMobj.Create(FNy1, FNx);
  row := TVMobj.Create(1, FNx);
  FPtr := F.DataPtr;
  for j := 0 to FNy1 - 1 do
  begin
    Move(FPtr[j * FNx], row.DataPtr^, FNx * SizeOf(Double));
    S := FFT_R2C(row);
    back := FFT_C2R(S * FFac[O1], FNx);         // * is elementwise here
    Move(back.DataPtr^, R1.DataPtr[j * FNx], FNx * SizeOf(Double));
    if O2 > 0 then
    begin
      back := FFT_C2R(S * FFac[O2], FNx);
      Move(back.DataPtr^, R2.DataPtr[j * FNx], FNx * SizeOf(Double));
    end;
  end;
end;

function TBenney2DModel.XDeriv(const F: TVMobj; Order: Integer): TVMobj;
var
  dummy: TVMobj;
begin
  XDeriv2(F, Order, 0, Result, dummy);
end;

{ ---- the six phase halves ---- }

procedure TBenney2DModel.XPhase1;
var t0: Double;
begin
  t0 := NowSec;
  XDeriv2(FIn, 1, 2, FHx, FHxx);
  FXTime := FXTime + NowSec - t0;
end;

procedure TBenney2DModel.YPhase1;
var t0: Double;
begin
  t0 := NowSec;
  FHy := MatMult(FD1, FIn);
  FHyy := MatMult(FD2, FIn);
  FYTime := FYTime + NowSec - t0;
end;

procedure TBenney2DModel.XPhase2;
var t0: Double;
begin
  t0 := NowSec;
  FKx := XDeriv(FKap, 1);
  FXTime := FXTime + NowSec - t0;
end;

procedure TBenney2DModel.YPhase2;
var t0: Double;
begin
  t0 := NowSec;
  FKy := MatMult(FD1, FKap);
  FYTime := FYTime + NowSec - t0;
end;

procedure TBenney2DModel.XPhase3;
var t0: Double;
begin
  t0 := NowSec;
  FDqx := XDeriv(FQx, 1);
  FXTime := FXTime + NowSec - t0;
end;

procedure TBenney2DModel.YPhase3;
var t0: Double;
begin
  t0 := NowSec;
  FDqy := MatMult(FD1, FQy);
  FYTime := FYTime + NowSec - t0;
end;

procedure TBenney2DModel.RunPhase(XP, YP: TThreadMethod);
begin
  if FP.Threaded then
  begin
    if FWorker = nil then FWorker := TDerivWorker.Create;
    FWorker.Run(XP);
    try
      YP();
    finally
      FWorker.Wait;       // always, so the worker is idle again
    end;
  end
  else
  begin
    XP();
    YP();
  end;
end;

function TBenney2DModel.RHS(const H: TVMobj): TVMobj;
var
  i, n: Integer;
  t0, h3: Double;
  HP, HX, HY, KX, KY, QX, QY: PDouble;
begin
  t0 := NowSec;
  Inc(FRHSCalls);
  n := FNy1 * FNx;
  FIn := H;
  RunPhase(@XPhase1, @YPhase1);
  FKap := FHxx + FHyy;
  RunPhase(@XPhase2, @YPhase2);
  FQx := TVMobj.Create(FNy1, FNx);
  FQy := TVMobj.Create(FNy1, FNx);
  HP := H.DataPtr; HX := FHx.DataPtr; HY := FHy.DataPtr;
  KX := FKx.DataPtr; KY := FKy.DataPtr;
  QX := FQx.DataPtr; QY := FQy.DataPtr;
  for i := 0 to n - 1 do
  begin
    h3 := HP[i] * HP[i] * HP[i];
    QX[i] := FA * h3 + (FI * h3 * h3 - FG * h3) * HX[i] + FS * h3 * KX[i];
    QY[i] := -FG * h3 * HY[i] + FS * h3 * KY[i];
  end;
  RunPhase(@XPhase3, @YPhase3);
  Result := -(FDqx + FDqy);
  FRHSTime := FRHSTime + NowSec - t0;
end;

{ ---- modes ---- }

function TBenney2DModel.ToModes(const F: TVMobj): TVMobjZ;
var
  j: Integer;
  row: TVMobj;
  S: TVMobjZ;
  FPtr: PDouble;
  t0: Double;
begin
  t0 := NowSec;
  Result := TVMobjZ.Create(FNy1, FNc);
  row := TVMobj.Create(1, FNx);
  FPtr := F.DataPtr;
  for j := 0 to FNy1 - 1 do
  begin
    Move(FPtr[j * FNx], row.DataPtr^, FNx * SizeOf(Double));
    S := FFT_R2C(row);
    Move(S.DataPtr^, Result.DataPtr[j * FNc], FNc * SizeOf(TComplex16));
  end;
  FModesTime := FModesTime + NowSec - t0;
end;

function TBenney2DModel.FromModes(const E: TVMobjZ): TVMobj;
var
  j: Integer;
  row: TVMobjZ;
  back: TVMobj;
  t0: Double;
begin
  t0 := NowSec;
  Result := TVMobj.Create(FNy1, FNx);
  row := TVMobjZ.Create(1, FNc);
  for j := 0 to FNy1 - 1 do
  begin
    Move(E.DataPtr[j * FNc], row.DataPtr^, FNc * SizeOf(TComplex16));
    back := FFT_C2R(row, FNx);
    Move(back.DataPtr^, Result.DataPtr[j * FNx], FNx * SizeOf(Double));
  end;
  FModesTime := FModesTime + NowSec - t0;
end;

// the diagonal part of L for mode m
function TBenney2DModel.ModeCoef(m: Integer): TComplex16;
var
  k: Double;
begin
  k := FK[m];
  Result := Cplx(FI * k * k - FBeta * FG * k * k - FBeta * FS * k * k * k * k,
                 -3 * FA * FK1[m]);
end;

// L E for every mode at once: c(k) E + beta (G + 2 S k^2) D2 E - beta S D4 E
function TBenney2DModel.ApplyL(const E: TVMobjZ): TVMobjZ;
var
  j, m: Integer;
  D2E, D4E: TVMobjZ;
  EP, P2, P4, RP: PComplex16;
  cm, ev: TComplex16;
  d2, t0: Double;
begin
  t0 := NowSec;
  D2E := FD2 * E;               // real x complex: a matrix product (MatMultZ)
  D4E := FD4 * E;
  Result := TVMobjZ.Create(FNy1, FNc);
  EP := E.DataPtr; P2 := D2E.DataPtr; P4 := D4E.DataPtr; RP := Result.DataPtr;
  for m := 0 to FNc - 1 do
  begin
    cm := ModeCoef(m);
    d2 := FBeta * (FG + 2 * FS * Sqr(FK[m]));
    for j := 0 to FNy1 - 1 do
    begin
      ev := EP[j * FNc + m];
      RP[j * FNc + m].re := cm.re * ev.re - cm.im * ev.im + d2 * P2[j * FNc + m].re - FBeta * FS * P4[j * FNc + m].re;
      RP[j * FNc + m].im := cm.re * ev.im + cm.im * ev.re + d2 * P2[j * FNc + m].im - FBeta * FS * P4[j * FNc + m].im;
    end;
  end;
  FApplyLTime := FApplyLTime + NowSec - t0;
end;

function TBenney2DModel.NHat(const H: TVMobj; const E: TVMobjZ; t: Double): TVMobjZ;
begin
  Result := ToModes(RHS(H)) - ApplyL(E);
  // the excitation is explicit, like the nonlinear terms: it is slow
  // (periods ~1 s against steps ~0.01 s) and its modes are fixed
  if FP.Excite then
    Result := Result + FSource * Cos(2 * Pi * t / FP.ExcitePeriod);
  // the absorbing zone, explicit too: sigma varies with x, so it can't
  // join the per-mode implicit operator; sigma dt is only ~0.1 .. 0.3
  if FP.Absorb then
    Result := Result - ToModes(AddScalar(H, -1) * FSponge);   // * elementwise
end;

function TBenney2DModel.AbsorbStart: Double;
begin
  Result := FP.Lx - FP.AbsorbGap - FP.AbsorbLength;
end;

function TBenney2DModel.SpongeRate(x: Double): Double;
var
  u: Double;
begin
  u := (x - AbsorbStart) / FP.AbsorbLength;
  if (u <= 0) or (u >= 1) then Result := 0
  else Result := FP.AbsorbRate * Sqr(Sin(Pi * u));
end;

// a wave at speed c spends dx/c in each dx: it keeps
// exp(-int sigma dx / c) = exp(-AbsorbRate AbsorbLength/(2 c))
function TBenney2DModel.AbsorbedFraction: Double;
begin
  Result := 1 - Exp(-FP.AbsorbRate * FP.AbsorbLength / (2 * WaveSpeed));
end;

{ The source shape S0 g(x) on every row: g a periodic Gaussian about
  x = 0 of half-width ExciteWidth with unit integral, S0 = a c. A narrow
  source in a kinematic wave h_t + c h_x = s launches h = (1/c) int s dx
  downstream, so S0 = a c launches thickness amplitude a (in hN). }
function TBenney2DModel.ExciteSource(t: Double): TVMobj;
var
  i, j: Integer;
  d, w, g, my: Double;
begin
  Result := TVMobj.Create(FNy1, FNx);
  w := FP.ExciteWidth;
  for i := 0 to FNx - 1 do
  begin
    d := FX.DataPtr[i] - FP.Lx * Round(FX.DataPtr[i] / FP.Lx);   // nearest image of 0
    g := Exp(-Sqr(d / w)) / (w * Sqrt(Pi));
    for j := 0 to FNy1 - 1 do
    begin
      // the transverse modulation: a cosine with zero slope (and third
      // derivative) at both walls, so it meets the wall conditions
      my := 1 + FP.ExciteMod * Cos(FP.ExciteModN * Pi * (FY.DataPtr[j] + FP.W / 2) / FP.W);
      Result.DataPtr[j * FNx + i] := FP.ExciteAmp * WaveSpeed * g * my * Cos(2 * Pi * t / FP.ExcitePeriod);
    end;
  end;
end;

{ The per-mode systems (a0 - dt L) with the wall rows, LU-factored on
  their first solve. Two sets are cached: after a step-size change the
  first step has its own a0 (step ratio <> 1), the ones after it the
  constant-step a0 = 3/2. Returns the slot. }
function TBenney2DModel.Systems(a0, dt: Double): Integer;
var
  s, m, i, j, n: Integer;
  cm: TComplex16;
  d2: Double;
  MP: PComplex16;
  D1P, D2P, D3P, D4P: PDouble;

  procedure SetRow(r: Integer; Src: PDouble; SrcRow: Integer);
  var c: Integer;
  begin
    for c := 0 to FNy1 - 1 do MP[r * FNy1 + c] := Cplx(Src[SrcRow * FNy1 + c], 0);
  end;

begin
  for s := 0 to 1 do
    if (Length(FSys[s]) = FNc) and (FSysA0[s] = a0) and (FSysDt[s] = dt) then Exit(s);
  s := FSysNext;
  FSysNext := 1 - FSysNext;
  SetLength(FSys[s], FNc);
  n := FNy1 - 1;
  D1P := FD1.DataPtr; D2P := FD2.DataPtr; D3P := FD3.DataPtr; D4P := FD4.DataPtr;
  for m := 0 to FNc - 1 do
  begin
    FSys[s][m] := TVMobjZ.Create(FNy1, FNy1);
    MP := FSys[s][m].DataPtr;
    cm := ModeCoef(m);
    d2 := FBeta * (FG + 2 * FS * Sqr(FK[m]));
    for i := 0 to n do
      for j := 0 to n do
      begin
        MP[i * FNy1 + j] := Cplx(-dt * (d2 * D2P[i * FNy1 + j] - FBeta * FS * D4P[i * FNy1 + j]), 0);
        if i = j then
          MP[i * FNy1 + j] := Cplx(MP[i * FNy1 + j].re + a0 - dt * cm.re, -dt * cm.im);
      end;
    // the walls: H_y = 0 (rows 0, n) and H_yyy = 0 (rows 1, n-1)
    SetRow(0, D1P, 0);
    SetRow(n, D1P, n);
    SetRow(1, D3P, 0);
    SetRow(n - 1, D3P, n);
  end;
  FSysA0[s] := a0;
  FSysDt[s] := dt;
  Inc(FFactorisations);
  Result := s;
end;

function TBenney2DModel.SolveModes(Slot: Integer; const R: TVMobjZ): TVMobjZ;
var
  m, j, n: Integer;
  b: TVMobjZ;
  RP, BP, OP: PComplex16;
  t0: Double;
begin
  t0 := NowSec;
  n := FNy1 - 1;
  Result := TVMobjZ.Create(FNy1, FNc);      // zero: the Nyquist mode stays 0
  RP := R.DataPtr;
  OP := Result.DataPtr;
  for m := 0 to FNc - 2 do
  begin
    b := TVMobjZ.Create(FNy1, 1);
    BP := b.DataPtr;
    for j := 2 to n - 2 do BP[j] := RP[j * FNc + m];   // wall rows stay 0
    LinearSolveZ(FSys[Slot][m], b);         // factorises on first use, then reuses
    for j := 0 to n do OP[j * FNc + m] := BP[j];
  end;
  FSolveTime := FSolveTime + NowSec - t0;
end;

{ ---- initial conditions ---- }

function TBenney2DModel.Flat: TVMobj;
var
  i: Integer;
begin
  Result := TVMobj.Create(FNy1, FNx);
  for i := 0 to FNy1 * FNx - 1 do Result.DataPtr[i] := 1;
end;

function TBenney2DModel.Bump(Amp, X0, Radius: Double): TVMobj;
var
  i, j: Integer;
  dx: Double;
begin
  Result := TVMobj.Create(FNy1, FNx);
  for j := 0 to FNy1 - 1 do
    for i := 0 to FNx - 1 do
    begin
      // nearest periodic image in x
      dx := FX.DataPtr[i] - X0;
      dx := dx - FP.Lx * Round(dx / FP.Lx);
      Result.DataPtr[j * FNx + i] :=
        Amp * Exp(-(Sqr(dx) + Sqr(FY.DataPtr[j])) / Sqr(Radius));
    end;
end;

{ Smooth random noise that already meets the wall conditions: a sum of
  cos(my pi (y + W/2)/W) cos(2 pi mx x/Lx + phase) for my <= 8,
  mx <= 12 with Gaussian weights, scaled to a peak of Amp. Rough
  (gridpoint) noise does not: its Chebyshev D4 is enormous and it blew
  the explicit terms up in the prototype. }
function TBenney2DModel.Noise(Amp: Double; Seed: LongInt): TVMobj;
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

{ Barycentric Lagrange interpolation on the Chebyshev-Lobatto points
  (weights (-1)^j, halved at the ends - Berrut & Trefethen 2004),
  which is exact for the degree-Ny polynomial the grid represents. }
function TBenney2DModel.UniformRows(Nyd: Integer): TVMobj;
var
  i, j, hit: Integer;
  yt, d, sum: Double;
  w: array of Double;
  RP, YP: PDouble;
begin
  Result := TVMobj.Create(Nyd, FNy1);
  RP := Result.DataPtr;
  YP := FY.DataPtr;
  SetLength(w, FNy1);
  for j := 0 to FNy1 - 1 do
  begin
    if Odd(j) then w[j] := -1 else w[j] := 1;
    if (j = 0) or (j = FNy1 - 1) then w[j] := w[j] / 2;
  end;
  for i := 0 to Nyd - 1 do
  begin
    yt := -FP.W / 2 + FP.W * i / (Nyd - 1);
    hit := -1;
    for j := 0 to FNy1 - 1 do
      if Abs(yt - YP[j]) < 1e-12 * FP.W then hit := j;
    if hit >= 0 then
    begin
      RP[i * FNy1 + hit] := 1;
      Continue;
    end;
    sum := 0;
    for j := 0 to FNy1 - 1 do
    begin
      d := w[j] / (yt - YP[j]);
      RP[i * FNy1 + j] := d;
      sum := sum + d;
    end;
    for j := 0 to FNy1 - 1 do RP[i * FNy1 + j] := RP[i * FNy1 + j] / sum;
  end;
end;

{ ---- integration ---- }

procedure TBenney2DModel.Start(const H0: TVMobj; dt0: Double);
var
  i, s: Integer;
begin
  FSteps := 0;
  FRejected := 0;
  FFactorisations := 0;
  FSys[0] := nil;
  FSys[1] := nil;
  FBeta := 1.5;
  FXTime := 0; FYTime := 0; FRHSTime := 0; FRHSCalls := 0;
  FDt := dt0;
  // history: H0, then two backward-Euler/forward-Euler (SBDF1) steps
  FT[0] := 0;
  FE[0] := ToModes(AddScalar(H0, -1));
  FH := CopyObj(H0);
  FN[0] := NHat(FH, FE[0], FT[0]);
  s := Systems(1.0, dt0);
  for i := 1 to 2 do
  begin
    FE[i] := SolveModes(s, FE[i - 1] + FN[i - 1] * dt0);
    FT[i] := FT[i - 1] + dt0;
    FH := AddScalar(FromModes(FE[i]), 1);
    FN[i] := NHat(FH, FE[i], FT[i]);
    Inc(FSteps);
  end;
end;

function TBenney2DModel.Advance(out Msg: string): Boolean;
const
  MinDt = 1e-7;
var
  w, a0, hs, tn, l0, l1, l2, err, fac, m3, hmax: Double;
  R, En, Pn: TVMobjZ;
  Hn, Dn: TVMobj;
  s, i: Integer;
  ok: Boolean;
  P: PDouble;
begin
  Msg := '';
  while True do
  begin
    hs := FDt;
    w := hs / (FT[2] - FT[1]);
    a0 := (1 + 2 * w) / (1 + w);
    R := FE[2] * (1 + w) - FE[1] * (w * w / (1 + w))
         + (FN[2] * (1 + w) - FN[1] * w) * hs;
    s := Systems(a0, hs);
    En := SolveModes(s, R);
    // predictor: the quadratic through the last three steps, at tn
    tn := FT[2] + hs;
    l0 := (tn - FT[1]) * (tn - FT[0]) / ((FT[2] - FT[1]) * (FT[2] - FT[0]));
    l1 := (tn - FT[2]) * (tn - FT[0]) / ((FT[1] - FT[2]) * (FT[1] - FT[0]));
    l2 := (tn - FT[2]) * (tn - FT[1]) / ((FT[0] - FT[2]) * (FT[0] - FT[1]));
    Pn := FE[2] * l0 + FE[1] * l1 + FE[0] * l2;
    Dn := FromModes(En - Pn);
    Hn := AddScalar(FromModes(En), 1);
    err := 0;
    ok := True;
    P := Dn.DataPtr;
    for i := 0 to FNy1 * FNx - 1 do
      if IsNan(P[i]) or IsInfinite(P[i]) then ok := False
      else err := Max(err, Abs(P[i]));
    err := err * 2 / 11;
    hmax := 0;
    P := Hn.DataPtr;
    for i := 0 to FNy1 * FNx - 1 do
      if IsNan(P[i]) or IsInfinite(P[i]) then ok := False
      else hmax := Max(hmax, P[i]);
    if (not ok) or (hmax > 5) or (err > FP.Tol) then
    begin
      Inc(FRejected);
      if ok and (err > 0) then
        FDt := hs * Max(0.2, 0.9 * Power(FP.Tol / err, 1 / 3))
      else
        FDt := hs * 0.25;
      if FDt < MinDt then
      begin
        Msg := Format('the step size collapsed at t = %.4g s: the film is blowing up', [FT[2]]);
        Exit(False);
      end;
      Continue;
    end;
    // accepted
    for i := 0 to 1 do
    begin
      FT[i] := FT[i + 1];
      FE[i] := FE[i + 1];
      FN[i] := FN[i + 1];
    end;
    FT[2] := tn;
    FE[2] := En;
    FH := Hn;
    Inc(FSteps);
    // keep the explicit remainder S (H^3 - beta) lap^2 safe: H^3 < 4/3 beta
    m3 := IntPower(hmax, 3);
    if m3 > 1.2 * FBeta then
    begin
      FBeta := 1.25 * m3;
      FSys[0] := nil;
      FSys[1] := nil;
      FN[0] := NHat(AddScalar(FromModes(FE[0]), 1), FE[0], FT[0]);
      FN[1] := NHat(AddScalar(FromModes(FE[1]), 1), FE[1], FT[1]);
    end;
    FN[2] := NHat(FH, FE[2], FT[2]);
    // a new step size means refactorising every mode's system (twice:
    // once for the step-ratio step, once for the steady one), so it only
    // grows when there is clear room - the error under a fifth of Tol -
    // and only shrinks through a rejection
    if err > 0 then fac := Min(2, 0.9 * Power(FP.Tol / err, 1 / 3)) else fac := 2;
    if fac > 1.5 then FDt := hs * fac;
    Exit(True);
  end;
end;

end.
