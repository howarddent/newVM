program hfjvcheck;

{ Console checks for the HFJV model's parts against exact solutions.

  1. Sloshing in a rectangular tank, L x W x H, rigid sides and floor,
     a moving top surface under gravity, optionally a membrane with mass
     m and tension T. A standing wave eta = a cos(k x), k = n pi / L,
     obeys

        (rho g + T k^2) - w^2 (m + rho / (k tanh(k H))) = 0 ,

     the gravity wave dispersion relation with the membrane added. Its
     forced response to an outside pressure p cos(k x) is
     eta = -p / (rho g + T k^2 - w^2 (m + rho/(k tanh kH))).
     Checked: the frequency-domain amplitude against that, and the
     period of a free oscillation in the time domain against 2 pi / w_n.

  2. The lumped thorax (uThorax, diaphragm lumped) against its own
     impedances combined by hand in complex arithmetic: the lower-airway
     flow and lung volume for the jet's pattern at 1 - 15 Hz.

  3. The steady HFJV cycle by harmonics against stepping, lumped.

  4. The FEM abdomen as the diaphragm's load: the tank with its x = 0
     end as a diaphragm with no stiffness of its own and a gravity free
     top. Quasi-statically its pressure-volume stiffness is exactly
     rho g / A_top (the top rises evenly), so at 0.05 Hz, far below the
     1.6 Hz first slosh, it must match the lumped diaphragm with
     E_di = rho g / A_top. This checks the coupling's signs and weights.

  5. Harmonics against stepping with the adult box abdomen coupled,
     sloshing included.

  Build:  fpc -O2 -Fu../../../../.. -Fi../../../../.. -Fu../../../../../demos/JetVent hfjvcheck.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, cblas, oneapi, newVM, newVMsparse, uDescriptor, uAbdomenFluid,
  uAbdomenBox, uThorax, uHFJVSolve, uJetCalcVM;

function Projection(F : TAbdomenFluid; const Xv : TVMobj; k : Double) : Double;
// amplitude of cos(k x) in eta over the top surface (weights = int N)
var
  w : TDoubleArray;
  i : Integer;
  num, den, c : Double;
begin
  w := F.SurfaceWeights(1);
  num := 0; den := 0;
  for i := 0 to F.NbMovingDofs - 1 do
  begin
    c := Cos(k * F.X[F.MovNode[i]]);
    num := num + w[i] * c * Xv.DataPtr[F.EtaBase + i];
    den := den + w[i] * c * c;
  end;
  Result := num / den;
end;

var
  Fails : Integer = 0;

procedure Check(const What : String; Got, Want, RelTol : Double);
var
  e : Double;
begin
  e := Abs(Got - Want) / Max(Abs(Want), 1e-300);
  Write(Format('  %-46s %12.6g  exact %12.6g  err %7.3f %%', [What, Got, Want, 100 * e]));
  if e <= RelTol then WriteLn('  ok')
  else
  begin
    WriteLn('  FAIL');
    Inc(Fails);
  end;
end;

procedure TankCase(const Title : String; m, Ten : Double; nx, nz : Integer);
const
  Rho = 1000; g = 9.81; L = 0.3; Wd = 0.03; H = 0.2;
var
  Tank : TAbdomenBox;
  F : TAbdomenFluid;
  Sys : TDescriptorSystem;
  X, Y, Z : TDoubleArray;
  Tets : TIntegerArray;
  P : TDoubleArray;
  Br, Bi, Xr, Xi, B0, X0 : TVMobj;
  i, n, step, nsteps, crossings, iw : Integer;
  k, wn, om, eta, wantEta, prev, cur, tt, dt, tfirst, tlast, a0, amax : Double;
  St : TTrapezoidStepper;
begin
  WriteLn(Title);
  BuildBox(nx, 1, nz, L, Wd, H, X, Y, Z, Tets);
  Tank := TAbdomenBox.Create;
  Tank.DiaphragmEnd := False;
  F := TAbdomenFluid.Create;
  Sys := TDescriptorSystem.Create;
  try
    F.SetMesh(X, Y, Z, Tets);
    F.Rho := Rho; F.Alpha := 0; F.G := Vec3(0, 0, -g);
    SetLength(F.Surfaces, 2);
    F.Surfaces[1].Moving := True;
    F.Surfaces[1].Mass := m;
    F.Surfaces[1].Tension := Ten;
    F.Surfaces[1].Clamp := False;
    F.FindBoundary(Tank.Classify);
    F.AddToSystem(Sys);
    WriteLn(Format('  %d nodes, %d tets, %d surface nodes, %d unknowns, volume %.6f (%.6f)',
      [F.NbNodes, Length(Tets) div 4, F.NbMovingDofs, Sys.N, F.TotalVolume, L * Wd * H]));

    for n := 1 to 2 do
    begin
      k := n * Pi / L;
      wn := Sqrt((Rho * g + Ten * k * k) / (m + Rho / (k * Tanh(k * H))));
      WriteLn(Format('  mode %d: k = %.3f /m, f_n = %.4f Hz', [n, k, wn / (2 * Pi)]));
      // forced response at 0.5 and 1.5 f_n, unit pressure cos(kx)
      SetLength(P, F.NbNodes);
      for i := 0 to F.NbNodes - 1 do P[i] := Cos(k * X[i]);
      for iw := 0 to 1 do
      begin
        om := wn * (0.5 + iw);
        Br := TVMobj.Create(Sys.N, 1);
        Bi := TVMobj.Create(Sys.N, 1);
        F.AddPressureLoad(Br, 1, P);
        Sys.SolveFrequency(om, Br, Bi, Xr, Xi);
        eta := Projection(F, Xr, k);
        wantEta := -1 / (Rho * g + Ten * k * k - om * om * (m + Rho / (k * Tanh(k * H))));
        Check(Format('mode %d forced eta at %.1f f_n (m/Pa)', [n, 0.5 + iw]), eta, wantEta, 0.02);
      end;

      // free oscillation from eta = a cos(kx), v = 0, phi = 0
      X0 := TVMobj.Create(Sys.N, 1);
      a0 := 1e-3;
      for i := 0 to F.NbMovingDofs - 1 do
        X0.DataPtr[F.EtaBase + i] := a0 * Cos(k * X[F.MovNode[i]]);
      B0 := TVMobj.Create(Sys.N, 1);
      dt := (2 * Pi / wn) / 80;
      nsteps := 80 * 10;
      St := TTrapezoidStepper.Create(Sys, dt);
      try
        prev := Projection(F, X0, k);
        crossings := 0; tfirst := 0; tlast := 0; amax := 0;
        for step := 1 to nsteps do
        begin
          X0 := St.Step(X0, B0, B0);
          cur := Projection(F, X0, k);
          tt := step * dt;
          if step > nsteps - 160 then amax := Max(amax, Abs(cur));
          if (prev > 0) <> (cur > 0) then
          begin
            // linear interpolation of the crossing
            if crossings = 0 then tfirst := tt - dt * cur / (cur - prev)
            else tlast := tt - dt * cur / (cur - prev);
            Inc(crossings);
          end;
          prev := cur;
        end;
      finally
        St.Free;
      end;
      Check(Format('mode %d free period, %d half-cycles (s)', [n, crossings - 1]),
        2 * (tlast - tfirst) / (crossings - 1), 2 * Pi / wn, 0.02);
      Check(Format('mode %d amplitude after 10 periods (m)', [n]), amax, a0, 0.03);
    end;
  finally
    Sys.Free; F.Free; Tank.Free;
  end;
end;


function Cx(re, im : Double) : TComplex16;
begin
  Result.re := re; Result.im := im;
end;
function CAdd(const a, b : TComplex16) : TComplex16;
begin Result := Cx(a.re + b.re, a.im + b.im); end;
function CMul(const a, b : TComplex16) : TComplex16;
begin Result := Cx(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re); end;
function CDiv(const a, b : TComplex16) : TComplex16;
var d : Double;
begin
  d := b.re * b.re + b.im * b.im;
  Result := Cx((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d);
end;
function CInv(const a : TComplex16) : TComplex16;
begin Result := CDiv(Cx(1, 0), a); end;
function CAbs(const a : TComplex16) : Double;
begin Result := Sqrt(a.re * a.re + a.im * a.im); end;
{ R + i w I + E/(i w), all SI }
function Zrli(R, I, E, w : Double) : TComplex16;
begin Result := Cx(R, w * I - E / w); end;

procedure CheckC(const What : String; const Got, Want : TComplex16; RelTol : Double);
var
  e : Double;
begin
  e := CAbs(Cx(Got.re - Want.re, Got.im - Want.im)) / CAbs(Want);
  Write(Format('  %-46s |%10.4g| exact |%10.4g|  err %7.4f %%', [What, CAbs(Got), CAbs(Want), 100 * e]));
  if e <= RelTol then WriteLn('  ok') else begin WriteLn('  FAIL'); Inc(Fails); end;
end;

procedure LumpedThoraxCase;
const
  Fs : array[0..3] of Double = (1, 3, 7, 15);
var
  Sys : TDescriptorSystem;
  Th : TThorax;
  Xr, Xi : TVMobj;
  i : Integer;
  w : Double;
  Zua, Zaw, ZL, Zrc, Zdi, Zcw, ZA, Qaw, PA, QL, VLw : TComplex16;
  P : TThoraxParams;
begin
  WriteLn('Lumped thorax against its impedances combined by hand:');
  Sys := TDescriptorSystem.Create;
  Th := TThorax.Create;
  try
    Th.AddToSystem(Sys, nil, 0);
    P := Th.P;
    WriteLn(Format('  jet: %s at %.1f bar, %.1f l/min, momentum %.1f cmH2O (%s)',
      [Th.Cath.Name, P.DrivingP, Th.QOn * 60000, Th.DpOn / cmH2O, Th.JetNote]));
    for i := 0 to High(Fs) do
    begin
      w := 2 * Pi * Fs[i];
      HarmonicResponse(Sys, Th, w, Xr, Xi);
      Zua := Zrli(P.Rua * RUnit, P.Iua * IUnit, 0, w);
      Zaw := Zrli(P.Raw * RUnit, P.Iaw * IUnit, 0, w);
      ZL := Zrli(P.RL * RUnit, 0, P.EL * EUnit, w);
      Zrc := Zrli(P.Rrc * RUnit, P.Irc * IUnit, P.Erc * EUnit, w);
      Zdi := Zrli(P.Rdi * RUnit, P.Idi * IUnit, P.Edi * EUnit, w);
      Zcw := CInv(CAdd(CInv(Zrc), CInv(Zdi)));
      ZA := CInv(CAdd(CInv(CAdd(ZL, Zcw)), Cx(0, w * P.VFRC * Litre / PAtm)));
      Qaw := CDiv(CAdd(CMul(Zua, Cx(Th.QOn, 0)), Cx(Th.DpOn, 0)), CAdd(CAdd(Zua, Zaw), ZA));
      PA := CMul(ZA, Qaw);
      QL := CDiv(PA, CAdd(ZL, Zcw));
      VLw := CDiv(QL, Cx(0, w));
      CheckC(Format('Q_aw at %4.1f Hz (m3/s)', [Fs[i]]),
        Cx(Xr.DataPtr[Th.iQaw], Xi.DataPtr[Th.iQaw]), Qaw, 1e-9);
      CheckC(Format('V_L  at %4.1f Hz (m3)', [Fs[i]]),
        Cx(Th.VL(Xr), Th.VL(Xi)), VLw, 1e-9);
    end;
  finally
    Th.Free; Sys.Free;
  end;
end;

procedure CompareCycles(const What : String; const A, B : TCycle);
var
  k, j : Integer;
  vt, d, m : Double;
begin
  vt := MaxValue(A.VL) - MinValue(A.VL);
  d := 0;
  // B may be sampled more finely; match by time
  for k := 0 to High(A.T) do
  begin
    j := Round(A.T[k] / (B.T[1] - B.T[0])) mod Length(B.T);
    d := Max(d, Abs(A.VL[k] - B.VL[j]));
  end;
  Check(What + ' tidal volume (L)', (MaxValue(B.VL) - MinValue(B.VL)) / Litre, vt / Litre, 0.01);
  m := Mean(A.PA);
  Check(What + ' mean alveolar pressure (cmH2O)', Mean(B.PA) / cmH2O, m / cmH2O, 0.01);
  Check(What + ' largest V_L difference / VT', 1 + d / vt, 1, 0.01);
end;

procedure LumpedCycleCase;
var
  Sys : TDescriptorSystem;
  Th : TThorax;
  H, S : TCycle;
begin
  WriteLn('Steady cycle, lumped thorax, harmonics against stepping:');
  Sys := TDescriptorSystem.Create;
  Th := TThorax.Create;
  try
    Th.AddToSystem(Sys, nil, 0);
    H := CycleByHarmonics(Sys, Th, 200, 400);
    S := CycleByStepping(Sys, Th, 400, 200, 1e-6);
    WriteLn(Format('  stepping settled in %d cycles (last change %.1e of VT)', [S.Cycles, S.Change]));
    CompareCycles('', H, S);
  finally
    Th.Free; Sys.Free;
  end;
end;

procedure BuildBoxAbdomen(F : TAbdomenFluid; Box : TAbdomenBox; nx, ny, nz : Integer);
var
  X, Y, Z : TDoubleArray;
  Tets : TIntegerArray;
begin
  BuildBox(nx, ny, nz, Box.L, Box.W, Box.H, X, Y, Z, Tets);
  F.SetMesh(X, Y, Z, Tets);
  F.FindBoundary(Box.Classify);
end;

procedure TankDiaphragmCase;
const
  Rho = 1000; g = 9.81;
var
  Box : TAbdomenBox;
  F : TAbdomenFluid;
  SysF, SysL : TDescriptorSystem;
  ThF, ThL : TThorax;
  XrF, XiF, XrL, XiL : TVMobj;
  w : Double;
begin
  WriteLn('FEM abdomen as the diaphragm''s load, 0.05 Hz, against rho g / A_top:');
  Box := TAbdomenBox.Create;
  Box.L := 0.3; Box.W := 0.03; Box.H := 0.2; Box.DiaphragmEnd := True;
  F := TAbdomenFluid.Create;
  SysF := TDescriptorSystem.Create; SysL := TDescriptorSystem.Create;
  ThF := TThorax.Create; ThL := TThorax.Create;
  try
    F.Rho := Rho; F.Alpha := 0; F.G := Vec3(0, 0, -g);
    SetLength(F.Surfaces, 3);
    F.Surfaces[SurfWall].Moving := True;
    F.Surfaces[SurfDiaphragm].Moving := True;
    BuildBoxAbdomen(F, Box, 30, 1, 20);
    F.AddToSystem(SysF);
    ThF.AddToSystem(SysF, F, SurfDiaphragm);
    ThL.P.Edi := Rho * g / (Box.L * Box.W) / EUnit;
    ThL.P.Rdi := 0; ThL.P.Idi := 1e-9;
    ThL.AddToSystem(SysL, nil, 0);
    WriteLn(Format('  equivalent E_di = %.1f cmH2O/L', [ThL.P.Edi]));
    w := 2 * Pi * 0.05;
    HarmonicResponse(SysF, ThF, w, XrF, XiF);
    HarmonicResponse(SysL, ThL, w, XrL, XiL);
    CheckC('V_di (m3)', Cx(ThF.Vdi(XrF), ThF.Vdi(XiF)), Cx(ThL.Vdi(XrL), ThL.Vdi(XiL)), 0.01);
    CheckC('V_L (m3)', Cx(ThF.VL(XrF), ThF.VL(XiF)), Cx(ThL.VL(XrL), ThL.VL(XiL)), 0.01);
    CheckC('p_pl (Pa)', Cx(XrF.DataPtr[ThF.iPpl], XiF.DataPtr[ThF.iPpl]),
      Cx(XrL.DataPtr[ThL.iPpl], XiL.DataPtr[ThL.iPpl]), 0.01);
  finally
    ThF.Free; ThL.Free; SysF.Free; SysL.Free; F.Free; Box.Free;
  end;
end;

procedure AdultBoxCycleCase;
var
  Box : TAbdomenBox;
  F : TAbdomenFluid;
  Sys : TDescriptorSystem;
  Th : TThorax;
  H, S : TCycle;
begin
  WriteLn('Steady cycle with the adult box abdomen, harmonics against stepping:');
  Box := TAbdomenBox.Create;
  Box.L := 0.30; Box.W := 0.26; Box.H := 0.14; Box.DiaphragmEnd := True;
  F := TAbdomenFluid.Create;
  Sys := TDescriptorSystem.Create;
  Th := TThorax.Create;
  try
    F.Rho := 1040; F.Alpha := 5; F.G := Vec3(0, 0, -9.81);
    SetLength(F.Surfaces, 3);
    with F.Surfaces[SurfWall] do
    begin Moving := True; Mass := 25; Tension := 100; Damping := 0; Clamp := True; end;
    with F.Surfaces[SurfDiaphragm] do
    begin Moving := True; Mass := 4; Tension := 50; Damping := 0; Clamp := True; end;
    BuildBoxAbdomen(F, Box, 12, 10, 6);
    F.AddToSystem(Sys);
    Th.AddToSystem(Sys, F, SurfDiaphragm);
    WriteLn(Format('  %d nodes, %d unknowns', [F.NbNodes, Sys.N]));
    H := CycleByHarmonics(Sys, Th, 80, 400);
    S := CycleByStepping(Sys, Th, 400, 400, 1e-5);
    WriteLn(Format('  stepping settled in %d cycles (last change %.1e of VT)', [S.Cycles, S.Change]));
    CompareCycles('', H, S);
  finally
    Th.Free; Sys.Free; F.Free; Box.Free;
  end;
end;

begin
  InitializeCBLAS;
  TankCase('Tank 0.3 x 0.2 m, gravity only (free surface):', 0, 0, 30, 20);
  TankCase('Same tank, membrane m = 25 kg/m2, T = 100 N/m:', 25, 100, 30, 20);
  LumpedThoraxCase;
  LumpedCycleCase;
  TankDiaphragmCase;
  AdultBoxCycleCase;
  WriteLn;
  if Fails = 0 then WriteLn('All checks passed.')
  else
  begin
    WriteLn(Fails, ' check(s) FAILED.');
    Halt(1);
  end;
end.
