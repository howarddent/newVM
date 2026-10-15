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

     WAVENUMBERS are the integers 0..N/2-1, -N/2..-1, exactly as in the
     original, with no 2 pi/L factor. That differentiates with respect
     to s = 2 pi x/L rather than x, i.e. it treats the periodic domain as
     2 pi long whatever Ax says. It is kept deliberately: checked in
     Python (scipy BDF, same parameters) before this port, the
     physically scaled version (k 2 pi/200) blows up - the step size
     collapses at t ~ 4 - while the integer scaling gives the smooth
     travelling, slowly growing long wave the original produced. x on the
     plot is still -Ax .. Ax, as the original's chart had it.

     JACOBIAN by central differences, one column per equation - 2N
     right-hand-side evaluations per Jacobian - as calc_jac did.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, newVM, newVMComplex;

type
  TBenneyParams = record
    N: Integer;          // grid points (equations)
    Ax: Double;          // domain is -Ax .. Ax
    h0: Double;          // flat (Nusselt) film thickness
    Amp, Amp2: Double;   // initial pulses at x = -85 and x = -65
    Re: Double;          // Reynolds number
    We: Double;          // Weber number
    Eps: Double;         // long-wave expansion parameter
    Theta: Double;       // plane inclination (rad)
  end;

  TBenneyModel = class
  private
    FP: TBenneyParams;
    FB: Double;                // cot Theta
    FD1, FD3: TVMobjZ;         // (i k)^1, (i k)^3 on the half-spectrum
    FCalls: Int64;
    function SpectralDiff(const y: TVMobj; const Factor: TVMobjZ): TVMobj;
  public
    X: TVMobj;                 // (N,1) grid
    constructor Create(const P: TBenneyParams);
    function InitialProfile: TVMobj;
    // the TDerivs/TJacobn of ukapsrentrop
    function Derivs(t: Double; const y: TVMobj): TVMobj;
    procedure Jacobn(t: Double; const y: TVMobj; out dfdx, dfdy: TVMobj);
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
  FD1 := TVMobjZ.Create(nc, 1);
  FD3 := TVMobjZ.Create(nc, 1);
  for i := 0 to nc - 2 do
  begin
    k := i;                                  // integer wavenumber, see header
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
  // h0 + Amp exp(-0.4 (x+85)^2) + Amp2 exp(-0.4 (x+65)^2)
  Result := TVMobj.Create(FP.N, 1);
  XP := X.DataPtr;
  YP := Result.DataPtr;
  for i := 0 to FP.N - 1 do
    YP[i] := FP.h0 + FP.Amp * Exp(-0.4 * Sqr(XP[i] + 85))
                   + FP.Amp2 * Exp(-0.4 * Sqr(XP[i] + 65));
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
