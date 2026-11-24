program lvcheck;

{ Console checks of the left ventricle model's parts.

  1. Residual against energy: on a block with oblique fibres and a random
     displacement, the assembled passive nodal forces against central
     differences of the strain energy, the energy written from
     Guccione's law in its fibre-frame form (the residual uses the
     frame-free form).
  2. Tangent against residual: on a small ventricle, deformed, under
     cavity pressure and in mid-twitch, the assembled tangent against
     central differences of the residual; and the pressure load against
     differences of the cavity volume.
  3. Cavity volume of the unloaded mesh against the truncated ellipsoid's
     exact volume, at two mesh sizes.
  4. Uniaxial stretch along the fibres of an incompressible block: the
     nominal stress for the stretch reached under a dead load, against
     the closed form.
  5. Twitch at fixed length: the Hill model's stress in a block held at
     its reference length against the same formulae written out here.
     At fixed length the contractile element does not move, so this
     checks the twitch and force-length terms and the stress's route
     into the element, not the contractile element's time stepping
     (that is covered by halving the time step in lvrun).
  6. Inflation of a thick-walled sphere (a hemisphere with a symmetry
     plane) of isotropic exponential material: pressure against volume,
     against the exact radial integral.
  7. The lumped circulation: a steady jet through the open aortic valve,
     the Windkessel's decay, and volume conservation.

  Build:  fpc -O3 -FUlib -Fu../../../../.. -Fi../../../../.. lvcheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, cblas, newVM, newVMsparse, uLVMech, uLVCirc;

var
  Fails: Integer = 0;

procedure Report(const Name: string; Got, Want, Tol: Double);
var
  err: Double;
begin
  if Want <> 0 then err := Abs(Got / Want - 1) else err := Abs(Got);
  Write(Format('  %-46s %12.6g  want %12.6g  err %8.2e', [Name, Got, Want, err]));
  if err <= Tol then Writeln('  ok') else begin Writeln('  FAIL'); Inc(Fails); end;
end;

procedure EnergyCheck;
var
  M: TLVModel;
  Mat: TLVMaterial;
  Uv: array of Double;
  i, n: Integer;
  wp, wm, fd, worst, big: Double;
const
  h = 1e-6;
begin
  Writeln('1. Residual against energy (block, oblique fibres)');
  Mat := DefaultMaterial;
  Mat.Kappa := 50;
  M := TLVModel.CreateBlock(2, 2, 2, 10, 8, 6, [0.6, 0.64, 0.48], Mat);
  SetLength(Uv, 3 * M.NN);
  RandSeed := 12345;
  for i := 0 to High(Uv) do Uv[i] := 0.6 * (Random - 0.5);
  M.SetTrial(Uv, 0);
  M.AssembleTrial(0, 0, False);
  worst := 0; big := 0;
  for n := 0 to 3 * M.NN - 1 do
  begin
    { fixed dofs have their residual zeroed }
    if M.TrialResidual(n) = 0 then Continue;
    Uv[n] := Uv[n] + h; M.SetTrial(Uv, 0); wp := M.StrainEnergy;
    Uv[n] := Uv[n] - 2 * h; M.SetTrial(Uv, 0); wm := M.StrainEnergy;
    Uv[n] := Uv[n] + h; M.SetTrial(Uv, 0);
    M.AssembleTrial(0, 0, False);
    fd := (wp - wm) / (2 * h);
    worst := Max(worst, Abs(fd - M.TrialResidual(n)));
    big := Max(big, Abs(fd));
  end;
  Report('largest force difference / largest force', worst / big, 0, 1e-6);
  M.Free;
end;

procedure TangentCheck;
var
  M: TLVModel;
  G: TLVGeom;
  Uv: array of Double;
  i, n: Integer;
  err, big, vp, vm, r1, r0, worst: Double;
const
  h = 1e-6;
begin
  Writeln('2. Tangent against residual (small ventricle, loaded, mid-twitch)');
  G := AdultGeometry(68, 118, 75);
  G.NR := 2; G.NL := 4; G.NC := 6;
  M := TLVModel.Create(G, DefaultMaterial);
  SetLength(Uv, 3 * M.NN);
  RandSeed := 4321;
  for i := 0 to High(Uv) do Uv[i] := 0.8 * (Random - 0.5);
  M.SetTrial(Uv, 1.5);
  M.CheckTangent(0.12, 0.002, True, err, big);
  Report('passive+active: largest K error / largest K', err / big, 0, 1e-6);
  M.CheckTangent(0, 0, False, err, big);
  Report('passive only', err / big, 0, 1e-6);
  { pressure load = p dV/du }
  worst := 0; big := 0;
  n := 0;
  while n < 3 * M.NN do
  begin
    M.SetTrial(Uv, 1.0); M.AssembleTrial(0, 0, False); r1 := M.TrialResidual(n);
    M.SetTrial(Uv, 0.0); M.AssembleTrial(0, 0, False); r0 := M.TrialResidual(n);
    Uv[n] := Uv[n] + h; M.SetTrial(Uv, 0); M.AssembleTrial(0, 0, False); vp := M.TrialVolume;
    Uv[n] := Uv[n] - 2 * h; M.SetTrial(Uv, 0); M.AssembleTrial(0, 0, False); vm := M.TrialVolume;
    Uv[n] := Uv[n] + h;
    if not ((r1 = 0) and (r0 = 0)) then
    begin
      worst := Max(worst, Abs((r0 - r1) - (vp - vm) / (2 * h)));
      big := Max(big, Abs(r0 - r1));
    end;
    Inc(n, 5);
  end;
  Report('pressure force against dV/du', worst / big, 0, 1e-6);
  M.Free;
end;

procedure VolumeCheck;
var
  M: TLVModel;
  G: TLVGeom;
  k: Integer;
  exact: Double;
begin
  Writeln('3. Cavity volume of the unloaded mesh');
  G := AdultGeometry(68, 118, 75);
  exact := TruncVolume(G.AEn, G.CEn, G.ZB);
  for k := 1 to 2 do
  begin
    G.NR := 2; G.NL := 10 * k; G.NC := 16 * k;
    M := TLVModel.Create(G, DefaultMaterial);
    Report(Format('%d x %d faces, mL', [G.NL, G.NC]), M.CavityVolume / 1000, exact / 1000, 1e-9);
    if k = 2 then
      Report('wall volume, mL', M.WallVolume / 1000,
        (TruncVolume(G.AEp, G.CEp, G.ZB) - exact) / 1000, 0.01);
    M.Free;
  end;
end;

procedure UniaxialCheck;
var
  M: TLVModel;
  Mat: TLVMaterial;
  i, j, k, n, step: Integer;
  F, lam, Eff, Et, Qe, Sff, Stt, pr, Pnom, wy, wz: Double;
const
  nx = 2; ny = 2; nz = 2;
  Lx = 10; Ly = 4; Lz = 6;
begin
  Writeln('4. Uniaxial stretch along the fibres (incompressible block)');
  Mat := DefaultMaterial;
  Mat.Kappa := 1e5;
  M := TLVModel.CreateBlock(nx, ny, nz, Lx, Ly, Lz, [1.0, 0, 0], Mat);
  for step := 1 to 6 do
  begin
    F := 30.0 * step; { mN }
    for k := 0 to nz do
      for j := 0 to ny do
      begin
        n := (k * (ny + 1) + j) * (nx + 1) + nx;
        if (j = 0) or (j = ny) then wy := 0.5 / ny else wy := 1.0 / ny;
        if (k = 0) or (k = nz) then wz := 0.5 / nz else wz := 1.0 / nz;
        M.FExt[3 * n] := F * wy * wz;
      end;
    if not M.Solve(0, 0, False, cmPressure, 0, nil) then
    begin
      Writeln('  load step did not converge  FAIL'); Inc(Fails); Break;
    end;
    M.Accept;
    if (step mod 3) <> 0 then Continue;
    lam := 1 + M.U[3 * nx] / Lx;
    Eff := 0.5 * (lam * lam - 1); Et := 0.5 * (1 / lam - 1);
    Qe := Mat.bf * Eff * Eff + 2 * Mat.bt * Et * Et;
    Sff := Mat.C * Exp(Qe) * Mat.bf * Eff;
    Stt := Mat.C * Exp(Qe) * Mat.bt * Et;
    pr := -Stt / lam;
    Pnom := lam * (Sff + pr / (lam * lam));
    Report(Format('stretch %.4f: nominal stress, kPa', [lam]), F / (Ly * Lz), Pnom, 2e-3);
  end;
  M.Free;
end;

procedure TwitchCheck;
var
  M: TLVModel;
  Mat: TLVMaterial;
  n, step, i: Integer;
  t, lc, ls, peakM, peakE, tn, k1, k2, k3, k4, h: Double;

  function Rate(l: Double): Double;
  begin
    Result := (Mat.Ea * (ls - l) - 1) * Mat.v0;
  end;

  function Tens(tt, l: Double): Double;
  var
    tmax: Double;
  begin
    tmax := Mat.b * (ls - Mat.ld);
    if (tt <= 0) or (tt >= tmax) or (l <= Mat.lc0) then Exit(0);
    Result := Mat.T0 * Sqr(Tanh(Mat.al * (l - Mat.lc0))) * Sqr(Tanh(tt / Mat.tauR))
      * Sqr(Tanh((tmax - tt) / Mat.tauD)) * Mat.Ea * (ls - l);
  end;

const
  dt = 2.5e-4;
begin
  Writeln('5. Twitch at fixed length (Hill model)');
  Mat := DefaultMaterial;
  M := TLVModel.CreateBlock(1, 1, 1, 5, 5, 5, [1.0, 0, 0], Mat);
  for n := 0 to M.NN - 1 do M.FixDof(3 * n);
  ls := Mat.ls0;
  lc := ls - 1 / Mat.Ea;
  peakM := 0; peakE := 0; t := 0;
  for step := 1 to Round(0.4 / dt) do
  begin
    M.Solve(t + dt, dt, True, cmPressure, 0, nil);
    M.Accept;
    { RK4 on the contractile element, 10 substeps }
    h := dt / 10;
    for i := 1 to 10 do
    begin
      k1 := Rate(lc); k2 := Rate(lc + 0.5 * h * k1); k3 := Rate(lc + 0.5 * h * k2); k4 := Rate(lc + h * k3);
      lc := lc + h * (k1 + 2 * k2 + 2 * k3 + k4) / 6;
    end;
    t := t + dt;
    tn := Tens(t, lc);
    peakM := Max(peakM, M.MeanActiveStress);
    peakE := Max(peakE, tn);
    if (step = Round(0.1 / dt)) or (step = Round(0.25 / dt)) then
      Report(Format('active stress at %.2f s, kPa', [t]), M.MeanActiveStress, tn, 5e-3);
  end;
  Report('peak active stress, kPa', peakM, peakE, 5e-3);
  M.Free;
end;

function SpherePressure(A, B, ai, Cm, bb: Double): Double;
{ p = int_a^b 2 (sigma_theta - sigma_r) / r dr, incompressible }
const
  N = 4000;
var
  i: Integer;
  bo, r, Rr, lt, Et, Er, Qe, f, sum, w: Double;
begin
  bo := Power(B * B * B + ai * ai * ai - A * A * A, 1 / 3);
  sum := 0;
  for i := 0 to N do
  begin
    r := ai + (bo - ai) * i / N;
    Rr := Power(r * r * r - ai * ai * ai + A * A * A, 1 / 3);
    lt := r / Rr;
    Et := 0.5 * (lt * lt - 1); Er := 0.5 * (Power(lt, -4) - 1);
    Qe := bb * (Er * Er + 2 * Et * Et);
    f := 2 * Cm * Exp(Qe) * bb * (lt * lt * Et - Power(lt, -4) * Er) / r;
    if (i = 0) or (i = N) then w := 1 else if Odd(i) then w := 4 else w := 2;
    sum := sum + w * f;
  end;
  Result := sum * (bo - ai) / N / 3;
end;

procedure SphereCheck;
var
  M: TLVModel;
  G: TLVGeom;
  Mat: TLVMaterial;
  step, mesh: Integer;
  p, V, ai: Double;
begin
  Writeln('6. Thick-walled sphere inflation (isotropic exponential)');
  G.AEn := 20; G.CEn := 20; G.AEp := 30; G.CEp := 30; G.ZB := 0;
  G.AlphaEndo := 0; G.AlphaEpi := 0;
  Mat := DefaultMaterial;
  Mat.C := 2.0; Mat.bf := 3.0; Mat.bt := 3.0; Mat.bfs := 3.0; Mat.Kappa := 2e4;
  for mesh := 1 to 2 do
  begin
  G.NR := 3 * mesh; G.NL := 8 * mesh; G.NC := 16 * mesh;
  Writeln(Format('  mesh %d x %d x %d', [G.NR, G.NL, G.NC]));
  M := TLVModel.Create(G, Mat);
  for step := 1 to 8 do
  begin
    p := 0.5 * step;
    if not M.Solve(0, 0, False, cmPressure, p, nil) then
    begin
      Writeln('  load step did not converge  FAIL'); Inc(Fails); Break;
    end;
    M.Accept;
    if (step mod 4) <> 0 then Continue;
    V := 2 * M.CavityVolume;
    ai := Power(V / (4 * Pi / 3), 1 / 3);
    Report(Format('inner radius %.3f mm: pressure, kPa', [ai]), p, SpherePressure(20, 30, ai, Mat.C, Mat.bf), 0.04 / (mesh * mesh));
  end;
  M.Free;
  end;
end;

procedure CircCheck;
var
  Cc: TLVCirc;
  i: Integer;
  t, dt, q, B, want, v0, sumIn, pla_: Double;
begin
  Writeln('7. Lumped circulation');
  { steady jet: the Windkessel made a pressure source }
  Cc := TLVCirc.Create;
  Cc.CWk := 1e9; Cc.S.PWk := 80; Cc.S.PRoot := 80;
  dt := 1e-3; t := 0;
  for i := 1 to 3000 do begin t := t + dt; Cc.Commit(90, t, dt); end;
  B := RhoBlood / (2 * Sqr(Cc.Aortic.Area)) / 1333.22;
  want := (-Cc.Zc + Sqrt(Sqr(Cc.Zc) + 4 * B * 10)) / (2 * B);
  Report('steady aortic flow at 10 mmHg, mL/s', Cc.S.QAV, want, 1e-3);
  Report('aortic valve opening', Cc.S.ZAV, 1, 1e-3);
  Cc.Free;
  { Windkessel decay with the valve shut }
  Cc := TLVCirc.Create;
  Cc.S.PWk := 100; Cc.S.PRoot := 100;
  dt := 1e-4; t := 0;
  for i := 1 to 10000 do begin t := t + dt; Cc.Commit(5, t, dt); end;
  Report('arterial pressure after 1 s, mmHg', Cc.S.PWk,
    100 * Exp(-1 / (Cc.Rp * (Cc.CWk + Cc.CRoot))), 2e-3);
  Cc.Free;
  { volume conservation of the atrium over a filling second }
  Cc := TLVCirc.Create;
  v0 := Cc.S.VLA; sumIn := 0; dt := 1e-3; t := 0.3;
  for i := 1 to 500 do
  begin
    t := t + dt;
    Cc.Commit(2, t, dt);
    pla_ := Cc.PLA(t);
    sumIn := sumIn + dt * ((Cc.PPv - pla_) / Cc.RPv - Cc.S.QMV);
  end;
  q := Cc.S.VLA - v0;
  Report('atrial volume change, mL', q, sumIn, 1e-9);
  Cc.Free;
end;

begin
  InitializeCBLAS;
  SetMKLThreads(1);
  FormatSettings.DecimalSeparator := '.';
  EnergyCheck;
  TangentCheck;
  VolumeCheck;
  UniaxialCheck;
  TwitchCheck;
  SphereCheck;
  CircCheck;
  Writeln;
  if Fails = 0 then Writeln('All checks passed.')
  else begin Writeln(Fails, ' check(s) FAILED.'); Halt(1); end;
end.
