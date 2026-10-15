unit ubenneymodel;

{*******************************************************************************

     The 1-D Benney equation for a thin liquid film flowing down a plane
     inclined at Theta to the horizontal - h(x, t) the film thickness
     scaled by the flat-film (Nusselt) thickness h0:

       h_t + h^2 h_x
           + eps [ (2/5 Re h^6 - (cot Theta)/3 h^3) h_x
                   + (1/3) We eps^2 h^3 h_xxx ]_x  =  0

     Re the Reynolds number, We the Weber number, eps the long-wave
     expansion parameter. Inertia (Re) destabilises the flat film,
     gravity across the plane (cot Theta) and surface tension (We)
     stabilise it; the flat film is unstable for Re > (5/6) cot Theta, so
     a small bump grows into travelling waves.

     A port of the right-hand side and Jacobian in Benney/ukapsmain.pas
     (TfmMain.benney/calc_jac/spectral_diff), from MtxVec to newVM, kept
     out of the form so the integration can run on a worker thread.

     SPATIAL DERIVATIVES are spectral, on a periodic grid of N points:
     transform, multiply by (i k)^order, transform back. Here that is
     FFT_R2C to the packed half-spectrum, an elementwise multiply by a
     precomputed TVMobjZ factor, FFT_C2R back - where the original took
     the full complex FFT and the real part of the inverse. The two agree
     exactly: for every bin but Nyquist the half-spectrum carries the
     same information, and the original's Nyquist term, (-i N/2)^order
     times a real coefficient for odd order, is purely imaginary and so
     contributed nothing to the real part; here its factor is simply 0.

     WAVENUMBERS are k = (2 pi/L) n, n = 0..N/2-1, -N/2..-1, with L =
     2 Ax the domain length - true derivatives with respect to x
     (ScaleByLength, the default since 15 Oct 2026). The original used
     the bare integers n, which differentiates with respect to
     s = 2 pi x/L instead, i.e. treats the periodic domain as 2 pi long
     whatever Ax says; ScaleByLength := False reproduces that. The two
     are different problems, not two resolutions of one: in x the 0.2
     bump (width ~1.6) is resolved by a few dozen modes and steepens,
     while in s it is a spike of width 0.05 that the k^4 surface-tension
     term flattens at once into a domain-length wave.

     JACOBIAN by central differences, one column per equation - 2N
     right-hand-side evaluations per Jacobian - as calc_jac did.

     SOLITARY WAVES (SolitaryWave, added 15 Oct 2026). The equation is a
     conservation law, h_t + F(h)_x = 0 with the flux

       F = h^3/3 + eps [ (2/5 Re h^6 - cot(theta)/3 h^3) h_x
                         + We eps^2/3 h^3 h_xxx ],

     so a wave of permanent form h = H(x - c t) satisfies, integrated
     once, F(H) - c H = q. A SOLITARY wave returns to the flat film h = 1
     far from its crest, which fixes q = F(1) - c = 1/3 - c. Solved on
     the run's own grid by Newton's method (dense Jacobian by central
     differences, LinearSolve), with the crest-side point x = 0 pinned
     by H'(0) = 0. The flat film itself satisfies these equations at
     every speed, so Newton is kept off it by continuation in the
     height A = H(0) - 1: at fixed A, Re is the extra unknown, and A is
     stepped by a factor 1.12 from a converged A = 0.02 wave (a sech^2
     first guess, Re ~ 3.8), each step predicted by extrapolating the
     last two, until Re passes the run's Re; the bracketing pair is
     interpolated and a last Newton solve at that Re (now fixed, A free)
     gives the wave. The family runs from vanishing height and growing
     width at the instability threshold Re_c = (5/6) cot(theta) (2.56
     here) to about 0.15 at Re ~ 5.6, beyond which it was not found
     (verified in scipy, where each wave run forward in time kept its
     shape to 1e-5 or better). Outside that range SolitaryWave says so.
     Note A is the height at the pinned point; near threshold the wave
     carries small ripples and its true maximum is a little higher, so
     the maximum is what gets reported.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, newVM, newVMComplex;

type
  TBenneyParams = record
    N: Integer;          // grid points (equations)
    Ax: Double;          // domain is -Ax .. Ax
    h0: Double;          // flat (Nusselt) film thickness
    Amp, Amp2: Double;   // initial pulses 15 and 35 in from x = -Ax
    Re: Double;          // Reynolds number
    We: Double;          // Weber number
    Eps: Double;         // long-wave expansion parameter
    Theta: Double;       // plane inclination (rad)
    ScaleByLength: Boolean;  // wavenumbers 2 pi n/L (True) or n - see header
  end;

  TBenneyModel = class
  private
    FP: TBenneyParams;
    FB: Double;                // cot Theta
    FD1, FD3: TVMobjZ;         // (i k)^1, (i k)^3 on the half-spectrum
    FCalls: Int64;
    FK: array of Double;       // wavenumber of each half-spectrum bin
    function SpectralDiff(const y: TVMobj; const Factor: TVMobjZ): TVMobj;
    // solitary-wave machinery - see SOLITARY WAVES
    function SWResidual(const u: TVMobj; FixedRe, A, Re: Double): TVMobj;
    function SWNewton(var u: TVMobj; FixedRe, A, Re: Double): Boolean;
  public
    X: TVMobj;                 // (N,1) grid
    constructor Create(const P: TBenneyParams);
    function InitialProfile: TVMobj;
    // the TDerivs/TJacobn of ukapsrentrop
    function Derivs(t: Double; const y: TVMobj): TVMobj;
    procedure Jacobn(t: Double; const y: TVMobj; out dfdx, dfdy: TVMobj);
    // the flux F(h) at the given Reynolds number - see SOLITARY WAVES
    function Flux(const y: TVMobj; Re: Double): TVMobj;
    // the solitary wave at Params.Re, crest at x = 0: profile H (N,1),
    // speed c, maximum height above the film Amp, full width at half
    // height Width. False, with Msg saying why, if there is none.
    // OnProgress, if given, is told about each continuation step.
    function SolitaryWave(out H: TVMobj; out c, Amp, Width: Double;
      out Msg: string; OnProgress: TGetStrProc = nil): Boolean;
    // y moved s along x (periodically), by a phase shift of its spectrum
    function Shift(const y: TVMobj; s: Double): TVMobj;
    property Params: TBenneyParams read FP;
    property Calls: Int64 read FCalls;
  end;

function DefaultBenneyParams: TBenneyParams;

implementation

function DefaultBenneyParams: TBenneyParams;
begin
  // the original's constants
  Result.N := 512;
  Result.Ax := 100;
  Result.h0 := 1.0;
  Result.Amp := 0.2;
  Result.Amp2 := 0.0;
  Result.Re := 5.0;
  Result.We := 250;
  Result.Eps := 0.04;
  Result.Theta := Pi / 10;
  Result.ScaleByLength := True;
end;

constructor TBenneyModel.Create(const P: TBenneyParams);
var
  i, nc: Integer;
  k: Double;
  XP: PDouble;
begin
  inherited Create;
  FP := P;
  FB := 1 / Tan(P.Theta);
  X := TVMobj.Create(P.N, 1);
  XP := X.DataPtr;
  for i := 0 to P.N - 1 do XP[i] := -P.Ax + i * 2 * P.Ax / P.N;

  nc := P.N div 2 + 1;
  SetLength(FK, nc);                         // FK[nc-1] (Nyquist) stays 0
  FD1 := TVMobjZ.Create(nc, 1);
  FD3 := TVMobjZ.Create(nc, 1);
  for i := 0 to nc - 2 do
  begin
    if P.ScaleByLength then
      k := i * 2 * Pi / (2 * P.Ax)           // true d/dx on -Ax .. Ax
    else
      k := i;                                // the original's integers
    FK[i] := k;
    FD1[i, 0] := Cplx(0, k);                 // i k
    FD3[i, 0] := Cplx(0, -k * k * k);        // (i k)^3 = -i k^3
  end;
  // the Nyquist bin (index N/2) stays 0 - see the header
end;

function TBenneyModel.InitialProfile: TVMobj;
var
  i: Integer;
  XP, YP: PDouble;
begin
  // h0 + Amp exp(-0.4 (x-x1)^2) + Amp2 exp(-0.4 (x-x2)^2), with the
  // pulses 15 and 35 in from the left boundary (x = -85 and -65 on the
  // original's -100 .. 100)
  Result := TVMobj.Create(FP.N, 1);
  XP := X.DataPtr;
  YP := Result.DataPtr;
  for i := 0 to FP.N - 1 do
    YP[i] := FP.h0 + FP.Amp * Exp(-0.4 * Sqr(XP[i] + FP.Ax - 15))
                   + FP.Amp2 * Exp(-0.4 * Sqr(XP[i] + FP.Ax - 35));
end;

function TBenneyModel.SpectralDiff(const y: TVMobj; const Factor: TVMobjZ): TVMobj;
begin
  Result := FFT_C2R(FFT_R2C(y) * Factor, FP.N);   // * is elementwise here
end;

function TBenneyModel.Derivs(t: Double; const y: TVMobj): TVMobj;
var
  d1, d3, h3, inert, visc: TVMobj;
begin
  d1 := SpectralDiff(y, FD1);
  d3 := SpectralDiff(y, FD3);
  h3 := y * y * y;                                               // elementwise
  inert := ((2 / 5 * FP.Re) * Sqr(h3) - (FB / 3) * h3) * d1;     // h^6 = (h^3)^2
  visc := ((1 / 3 * FP.We * Sqr(FP.Eps)) * h3) * d3;
  Result := -(d1 * Sqr(y) + FP.Eps * SpectralDiff(visc + inert, FD1));
  Inc(FCalls);
end;

function TBenneyModel.Flux(const y: TVMobj; Re: Double): TVMobj;
var
  d1, d3, h3: TVMobj;
begin
  d1 := SpectralDiff(y, FD1);
  d3 := SpectralDiff(y, FD3);
  h3 := y * y * y;
  Result := (1 / 3) * h3 + FP.Eps * (((2 / 5 * Re) * Sqr(h3) - (FB / 3) * h3) * d1
                                     + ((1 / 3 * FP.We * Sqr(FP.Eps)) * h3) * d3);
end;

function TBenneyModel.Shift(const y: TVMobj; s: Double): TVMobj;
var
  F: TVMobjZ;
  i: Integer;
  cs, sn, re, im: Double;
begin
  F := FFT_R2C(y);
  // multiply bin k by exp(-i k s); the Nyquist bin (FK = 0) is unchanged
  for i := 0 to F.Rows - 1 do
  begin
    cs := Cos(FK[i] * s);
    sn := -Sin(FK[i] * s);
    re := F[i, 0].re;
    im := F[i, 0].im;
    F[i, 0] := Cplx(re * cs - im * sn, re * sn + im * cs);
  end;
  Result := FFT_C2R(F, FP.N);
end;

{ The solitary-wave equations at u: FixedRe < 0 (A-mode) means
  u = [H; c; q; Re] with the height A at x = 0 fixed - N+3 equations;
  otherwise u = [H; c; q] at Re = FixedRe - N+2 equations:
    F(H) - c H - q = 0      (N)    travelling wave, integrated once
    H'(0) = 0                       the crest-side point pinned at x = 0
    q - (1/3 - c) = 0               flat film h = 1 far from the crest
    H(0) - 1 - A = 0                A-mode only }
function TBenneyModel.SWResidual(const u: TVMobj; FixedRe, A, Re: Double): TVMobj;
var
  n, i0, i: Integer;
  H, R, d1: TVMobj;
  c, q: Double;
  UP, RP, OP: PDouble;
begin
  n := FP.N;
  i0 := n div 2;                               // x = 0
  UP := u.DataPtr;
  c := UP[n];
  q := UP[n + 1];
  if FixedRe < 0 then Re := UP[n + 2] else Re := FixedRe;
  H := SubMatrix(u, 0, 0, n, 1);
  R := Flux(H, Re) - c * H;
  d1 := SpectralDiff(H, FD1);
  if FixedRe < 0 then Result := TVMobj.Create(n + 3, 1)
  else Result := TVMobj.Create(n + 2, 1);
  OP := Result.DataPtr;
  RP := R.DataPtr;
  for i := 0 to n - 1 do OP[i] := RP[i] - q;
  OP[n] := d1.DataPtr[i0];
  OP[n + 1] := q - (1 / 3 - c);
  if FixedRe < 0 then OP[n + 2] := UP[i0] - 1 - A;
end;

function TBenneyModel.SWNewton(var u: TVMobj; FixedRe, A, Re: Double): Boolean;
const
  hs = 1e-7;          // central-difference step for the Jacobian
  MaxIter = 40;
var
  m, it, j, r: Integer;
  res, up, dn, col, Jac, du, trial: TVMobj;
  nr, lam: Double;
  JP, CP: PDouble;
begin
  Result := False;
  m := u.Rows;
  for it := 1 to MaxIter do
  begin
    res := SWResidual(u, FixedRe, A, Re);
    nr := Norm(res);
    if nr < 1e-10 then Exit(True);
    if IsNan(nr) then Exit(False);
    Jac := TVMobj.Create(m, m);
    JP := Jac.DataPtr;
    for j := 0 to m - 1 do
    begin
      up := CopyObj(u); up.DataPtr[j] := up.DataPtr[j] + hs;
      dn := CopyObj(u); dn.DataPtr[j] := dn.DataPtr[j] - hs;
      col := SWResidual(up, FixedRe, A, Re) - SWResidual(dn, FixedRe, A, Re);
      CP := col.DataPtr;
      for r := 0 to m - 1 do JP[r * m + j] := CP[r] / (2 * hs);
    end;
    du := -res;
    if LinearSolve(Jac, du) <> 0 then Exit(False);   // singular
    // halve the step until the residual falls
    lam := 1;
    repeat
      trial := u + lam * du;
      if Norm(SWResidual(trial, FixedRe, A, Re)) < nr then Break;
      lam := lam / 2;
    until lam < 1e-4;
    u := trial;
  end;
end;

function TBenneyModel.SolitaryWave(out H: TVMobj; out c, Amp, Width: Double;
  out Msg: string; OnProgress: TGetStrProc): Boolean;
const
  A0 = 0.02;          // the starting wave, safely between the ends
  Factor = 1.12;      // continuation step in A
  MaxSteps = 80;
var
  n, i, step: Integer;
  Rc, Target, A, Aprev, f, t, Re1, Re2, hm: Double;
  u, uprev, guess, w: TVMobj;
  UP, XP, HP, WP: PDouble;
  idx0, idx1: Integer;

  function ReOf(const v: TVMobj): Double;
  begin
    Result := v.DataPtr[n + 2];
  end;

begin
  Result := False;
  n := FP.N;
  Target := FP.Re;
  Rc := 5 / 6 * FB;
  H := TVMobj.Create(n, 1);
  c := 0; Amp := 0; Width := 0;
  if Target <= Rc then
  begin
    Msg := Format('none: below the instability threshold Re_c = %.3g', [Rc]);
    Exit;
  end;

  // the A = A0 wave from a sech^2 guess, Re free
  u := TVMobj.Create(n + 3, 1);
  UP := u.DataPtr;
  XP := X.DataPtr;
  for i := 0 to n - 1 do UP[i] := 1 + A0 / Sqr(Cosh(XP[i] / 10));
  UP[n] := 1 + A0;
  UP[n + 1] := 1 / 3 - UP[n];
  UP[n + 2] := 2.8;
  if not SWNewton(u, -1, A0, 0) then
  begin
    Msg := 'none: the starting wave did not converge';
    Exit;
  end;

  // continue in A towards the target Re
  if ReOf(u) < Target then f := Factor else f := 1 / Factor;
  A := A0;
  uprev := u;
  Aprev := A;
  for step := 1 to MaxSteps do
  begin
    if ReOf(u) = Target then Break;
    Re1 := ReOf(u);
    A := Aprev * f;
    if step = 1 then guess := CopyObj(u)
    else guess := u + ((A - Aprev) / (Aprev - Aprev / f)) * (u - uprev);
    w := guess;
    if not SWNewton(w, -1, A, 0) then
    begin
      if f > 1 then
        Msg := Format('none: the family ends near Re = %.3g (height %.3g)', [Re1, Aprev])
      else
        Msg := 'none: too close to the threshold for this domain';
      Exit;
    end;
    Re2 := ReOf(w);
    if Assigned(OnProgress) then
      OnProgress(Format('solitary wave: height %.4g -> Re %.4g', [A, Re2]));
    if (Re2 - Target) * (Re1 - Target) <= 0 then
    begin
      // bracketed: interpolate, then solve at the target Re
      t := (Target - Re1) / (Re2 - Re1);
      guess := SubMatrix(u + t * (w - u), 0, 0, n + 2, 1);
      if not SWNewton(guess, Target, 0, 0) then
      begin
        Msg := 'none: the final solve did not converge';
        Exit;
      end;
      H := SubMatrix(guess, 0, 0, n, 1);
      c := guess.DataPtr[n];
      // height and width from the profile itself
      HP := H.DataPtr;
      hm := 0;
      for i := 0 to n - 1 do hm := Max(hm, HP[i] - 1);
      Amp := hm;
      idx0 := n; idx1 := -1;
      for i := 0 to n - 1 do
        if HP[i] - 1 >= hm / 2 then
        begin
          if i < idx0 then idx0 := i;
          if i > idx1 then idx1 := i;
        end;
      Width := (idx1 - idx0) * 2 * FP.Ax / n;
      if Width > FP.Ax then
      begin
        Msg := Format('none in this domain: the wave (width %.3g) is too broad', [Width]);
        Exit;
      end;
      Msg := 'found';
      Exit(True);
    end;
    uprev := u;
    Aprev := A;
    u := w;
    if A < 1e-4 then
    begin
      Msg := 'none: too close to the threshold for this domain';
      Exit;
    end;
  end;
  Msg := 'none: continuation did not reach this Re';
end;

procedure TBenneyModel.Jacobn(t: Double; const y: TVMobj; out dfdx, dfdy: TVMobj);
const
  h = 1e-3;
var
  n, r, c: Integer;
  up, down, res: TVMobj;
  JP, RP: PDouble;
begin
  n := FP.N;
  dfdx := TVMobj.Create(n, 1);               // autonomous: df/dt = 0
  dfdy := TVMobj.Create(n, n);
  JP := dfdy.DataPtr;
  for c := 0 to n - 1 do
  begin
    up := CopyObj(y);
    up.DataPtr[c] := up.DataPtr[c] + h;
    down := CopyObj(y);
    down.DataPtr[c] := down.DataPtr[c] - h;
    res := (Derivs(t, up) - Derivs(t, down)) * (1 / (2 * h));
    RP := res.DataPtr;
    for r := 0 to n - 1 do JP[r * n + c] := RP[r];   // column c
  end;
end;

end.
