program filmplane;

{******************************************************************************
  Weighted-residual film model on the geometry of OpenFOAM's
  inclinedPlaneFilm tutorial (incompressible/pimpleFoam/laminar), written
  as a VTK ImageData series for ParaView.

  Same conditions as the OpenFOAM case:
    plate x = -32 .. 32 mm down the slope, y = 0 .. 32 mm across, with a
    symmetry plane at y = 0 (so a 64 mm wide plate) and a wall at y = 32;
    a cylinder of radius 8 mm at the origin;
    30 deg incline (OpenFOAM g = (4.905, 0, -8.4957));
    water at 300 K (OpenFOAM's H2O thermo, T0 300);
    film thickness 141 um held at the inlet, x = -32 mm;
    the rest of the plate starts with a 10 um film (OpenFOAM's initial
    hf_film), which serves as the precursor film over the "dry" plate;
    air at 1 m/s blowing down the slope (nu 1e-5 m^2/s);
    2.5 s of flow, written every 0.02 s.

  Different on purpose - this is our model, not OpenFOAM's:
    momentum is the simplified first-order weighted-residual model
    (Ruyer-Quil & Manneville 2000, 3-D form Scheid et al. 2006), as in
    demos/FilmWRM, with laminar drag 5/2 nu q/h^2 in place of
    kinematicThinFilm's Manning-Strickler wall friction (n = 0.1);
    the air acts as a laminar (Blasius) interfacial shear stress from the
    start of the plate, 5/4 tau/rho in the q equation (that coefficient
    makes the flat-film flux exactly g s h^3/(3 nu) + tau h^2/(2 mu)), in
    place of kinematicThinFilm's Cf = 0.9 m/s gas-film relaxation. It is
    about 1 % of gravity's pull here;
    the contact line is the precursor film; an optional disjoining
    pressure (--theta, Schwartz & Eley 1998, exponents 3, 2) gives it a
    finite equilibrium contact angle. Off by default: OpenFOAM's
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
  in the precursor film, 5/2 nu/b^2, and the shortest capillary wave on
  the grid. At the inlet, h = 141 um and q = its Nusselt flux, with a
  flat Nusselt film upstream; the outlet has zero gradients.

  Output: <out>/wrm_NNNN.vti plus <out>/wrm.pvd (times), in SI units
  like OpenFOAM's: point data h (m), U (m/s), q (m^2/s) and solid (1 in
  the cylinder) at the cell centres, mirrored to the full plate
  (y = -32 .. 32 mm). Arrays are inline base64, not raw appended data,
  which Ubuntu 24.04's ParaView 5.11 cannot read.

  The model itself is demos/FilmWRM/ufilmplanemodel.pas, which the
  FilmWRM demo also runs as its "OpenFOAM inclined plane" case; this
  program only drives it and writes the frames.

  Build: fpc -O3 -Fu../.. -Fi../.. -Fu../FilmWRM filmplane.lpr
  Run:   ./filmplane [--out=<dir>] [--dx=<mm>] [--tend=<s>] [--dtout=<s>]
                     [--theta=<deg>] [--noshear] [--nocyl] [--flat]
                     [--ny=<n>] [--threads=<n>] [--gpu]
                     (--ny=4 --nocyl is a 1-D front check)
  --gpu steps the model on the GPU through OpenCL (ufilmplanecl.pas),
  bit-identical to the CPU; without OpenCL or a double-precision device
  it says why and runs on the CPU.
*******************************************************************************}

{$mode objfpc}{$H+}
{$I newVMConfig.inc}

uses
  {$IFDEF UNIX} cthreads, {$ENDIF}
  SysUtils, Math, cblas, ufilmplanemodel{$IFDEF HAVE_OPENCL}, ufilmplanecl{$ENDIF};

var
  M: TFilmPlaneModel;
  PP: TPlaneParams;
  OutDir: string;

procedure Report;
var
  hmin, hmax: Double;
begin
  M.HRange(hmin, hmax);
  WriteLn(Format('t %6.3f  steps %7d  dt %.2e  h %.4f .. %.4f mm  front %6.2f (y=0) %6.2f (wall) mm  mass %.4f mm^3  clips %d',
    [M.Time, M.Steps, M.StableDt, hmin, hmax, M.FrontX(0), M.FrontX(PP.Ny - 1), M.Mass, M.Clips]));
end;

function Opt(const Name: string; Def: Double): Double;
var
  k: Integer;
  a: string;
begin
  Result := Def;
  for k := 1 to ParamCount do
  begin
    a := ParamStr(k);
    if Pos('--' + Name + '=', a) = 1 then
      Result := StrToFloat(Copy(a, Length(Name) + 4, MaxInt));
  end;
end;

function Flag(const Name: string): Boolean;
var
  k: Integer;
begin
  Result := False;
  for k := 1 to ParamCount do
    if ParamStr(k) = '--' + Name then Result := True;
end;

function OptS(const Name, Def: string): string;
var
  k: Integer;
  a: string;
begin
  Result := Def;
  for k := 1 to ParamCount do
  begin
    a := ParamStr(k);
    if Pos('--' + Name + '=', a) = 1 then Result := Copy(a, Length(Name) + 4, MaxInt);
  end;
end;

function FrameName(k: Integer): string;
begin
  Result := IncludeTrailingPathDelimiter(OutDir) + Format('wrm_%.4d.vti', [k]);
end;

var
  TEnd, DtOut, Dx, tNext, wall0: Double;
  nOut: Integer;
  Times: array of Double;
begin
  DefaultFormatSettings.DecimalSeparator := '.';
  InitializeCBLAS;
  PP := DefaultPlaneParams;
  Dx := Opt('dx', 0.25);
  TEnd := Opt('tend', 2.5);
  DtOut := Opt('dtout', 0.02);
  PP.Theta := Opt('theta', 0);
  PP.UseShear := not Flag('noshear');
  PP.UseCyl := not Flag('nocyl');
  PP.Flat := Flag('flat');
  PP.Threads := Round(Opt('threads', PP.Threads));
  OutDir := OptS('out', 'wrm');
  PP.Nx := Round((PP.X1 - PP.X0) / Dx);
  PP.Ny := Round(Opt('ny', Round(PP.Wd / Dx)));

  ForceDirectories(OutDir);
  {$IFDEF HAVE_OPENCL}
  if Flag('gpu') then M := TFilmPlaneCL.Create(PP) else
  {$ENDIF}
  M := TFilmPlaneModel.Create(PP);
  try
    WriteLn(Format('plate %.0f x %.0f mm, %d x %d cells (dx %.3f, dy %.3f mm), cylinder %s, %d threads',
      [PP.X1 - PP.X0, PP.Wd, PP.Nx, PP.Ny, M.CellDx, M.CellDy, BoolToStr(PP.UseCyl, 'r = 8 mm', 'off'), M.Threads]));
    {$IFDEF HAVE_OPENCL}
    if M is TFilmPlaneCL then
      with TFilmPlaneCL(M) do
        if GPUReady then WriteLn('stepping on the GPU: ', DeviceName)
        else WriteLn('GPU unavailable (', GPUError, '); stepping on the CPU');
    {$ELSE}
    if Flag('gpu') then WriteLn('built without OpenCL (HAVE_OPENCL); stepping on the CPU');
    {$ENDIF}
    WriteLn(Format('water %.0f deg, inlet h %.3f mm, q %.3f mm^2/s (Re %.2f, onset %.2f), u %.1f mm/s; precursor %.3f mm',
      [PP.Angle, PP.hN, M.qN, M.qN / PlaneNuW, 5 / 6 / Tan(DegToRad(PP.Angle)), M.qN / PP.hN, PP.hB]));
    WriteLn(Format('1-D front speed (qN - qb)/(hN - b) = %.2f mm/s; air shear 5/4 tau/rho at x = 0: %.2f mm^2/s^2 (gravity 5/6 g s hN %.0f)',
      [(M.qN - M.qN * Power(PP.hB / PP.hN, 3)) / (PP.hN - PP.hB), M.AirShear(0),
       5 / 6 * PlaneGrav * Sin(DegToRad(PP.Angle)) * PP.hN]));
    if PP.Theta > 0 then WriteLn(Format('disjoining pressure: contact angle %.0f deg', [PP.Theta]));

    SetLength(Times, Round(TEnd / DtOut) + 2);
    M.WriteVTI(FrameName(0));
    Times[0] := 0; nOut := 1;
    WritePlanePVD(IncludeTrailingPathDelimiter(OutDir) + 'wrm.pvd', Times, nOut);
    tNext := DtOut;
    wall0 := Now;
    Report;
    while M.Time < TEnd - 1e-9 do
    begin
      if not M.AdvanceTo(tNext) then
      begin
        WriteLn('NaN at t = ', M.Time:0:4);
        Halt(1);
      end;
      M.WriteVTI(FrameName(nOut));
      if nOut >= Length(Times) then SetLength(Times, nOut + 16);
      Times[nOut] := tNext; Inc(nOut);
      WritePlanePVD(IncludeTrailingPathDelimiter(OutDir) + 'wrm.pvd', Times, nOut);
      if (nOut - 1) mod 5 = 0 then Report;
      tNext := tNext + DtOut;
    end;
    WriteLn(Format('done: %d steps, %d frames, %.1f s wall', [M.Steps, nOut, (Now - wall0) * 86400]));
  finally
    M.Free;
  end;
end.
