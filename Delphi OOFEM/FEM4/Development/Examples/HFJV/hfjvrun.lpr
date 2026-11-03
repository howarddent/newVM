program hfjvrun;

{ HFJV in a supine adult: the steady ventilator cycle against rate, with
  the abdomen as a fluid (FEM, uAbdomenFluid) or lumped.

  Prints:
    1. the jet, from JetVent's bench data;
    2. the respiratory system's impedance below the jet, Zrs = Rrs + i Xrs
       (lower airways, lung, chest wall, abdomen), and with the upper
       airway added - the second is what forced oscillation at the mouth
       measures, for comparison with the literature;
    3. a sweep of rate at the chosen pressure and I:E: tidal volume, how
       much of it the diaphragm carries, mean and peak alveolar pressure,
       mean tracheal pressure, jet and entrained volumes per cycle, VT/VD
       and f VT^2;
    4. at the chosen rate, the anterior abdominal wall's motion at the
       fundamental along the midline from diaphragm to pelvis -
       amplitude and phase, which show the gravity-tension waves and
       their reflection from the pelvis.

  Options: --dp=<bar> (2), --rate=<per min> (200), --ie=<I:E as E/I> (1),
           --cannula=<0..5> (2, Biro: Lindholm, Cook, Biro, 14G, 16G, 18G),
           --calculated (Crane flow instead of the bench), --lumped,
           --vfile=<file> (only write the cycle every 20 /min, 40-900, as
           CSV for plot_ventilation.py; 20 harmonics unless --harm),
           --zfile=<file> (only write the impedance, 0.25-20 Hz, as CSV
           for plot_impedance.py),
           --anim=<file> (only write one cycle of the wall's motion for
           anim_wall.py, nothing else),
           --alpha=<1/s> (5, abdominal drag), --steps (also time-step the
           chosen rate as a check), --harm=<n> (30, harmonics per cycle;
           VT within ~1 % of 60).
  Abdomen: the gmsh torso (uTorsoAbdomen, Defibrillation's trunk) by
           default, --height=<m> (1.75), --weight=<kg> (70), --size=<mm>
           (12, mesh size); or --box for the 300 x 260 x 140 mm box.

  Build (from this folder; the FEM4 paths are for the torso's gmsh reader):
    fpc -O2 -FUlib -Fu../../../../.. -Fi../../../../.. -Fu../../../../../demos/JetVent
        -Fu../Defibrillation -Fu../ThermEx1 -Fu../../../../../Anaesthetics/PK-PD_FPC
        -Fu../../../../../Graphs -Fu../../Source/<each of Algebra Analytical
        Applications Assembly Elements Expression Imposer Mesh System> hfjvrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, StrUtils, Math, cblas, newVM, newVMsparse, uDescriptor, uAbdomenFluid,
  uAbdomenBox, uTorsoAbdomen, uThorax, uHFJVSolve, uJetCalcVM;

function Opt(const Name : String; Def : Double) : Double;
var
  i : Integer;
  s : String;
begin
  Result := Def;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if Pos('--' + Name + '=', s) = 1 then
      Result := StrToFloat(Copy(s, Length(Name) + 4, MaxInt));
  end;
end;

function StrOpt(const Name : String) : String;
var
  i : Integer;
begin
  Result := '';
  for i := 1 to ParamCount do
    if Pos('--' + Name + '=', ParamStr(i)) = 1 then
      Result := Copy(ParamStr(i), Length(Name) + 4, MaxInt);
end;

function Flag(const Name : String) : Boolean;
var
  i : Integer;
begin
  Result := False;
  for i := 1 to ParamCount do
    if ParamStr(i) = '--' + Name then Result := True;
end;

var
  Lumped, UseBox : Boolean;
  Alpha : Double;
  NHarm : Integer;
  Box : TAbdomenBox;
  Torso : TTorsoAbdomen;
  F : TAbdomenFluid;
  Sys : TDescriptorSystem;
  Th : TThorax;
  P0 : TThoraxParams;

procedure BuildModel(const P : TThoraxParams);
var
  X, Y, Z : TDoubleArray;
  Tets : TIntegerArray;
begin
  FreeAndNil(Th); FreeAndNil(Sys); FreeAndNil(F);
  Sys := TDescriptorSystem.Create;
  Th := TThorax.Create;
  Th.P := P;
  if Lumped then
  begin
    Th.AddToSystem(Sys, nil, 0);
    Exit;
  end;
  F := TAbdomenFluid.Create;
  F.Rho := 1040;              // soft tissue and fat at 37 C
  F.Alpha := Alpha;
  // supine, anterior wall up: +z in the box, +y in the torso
  if UseBox then F.G := Vec3(0, 0, -9.81) else F.G := Vec3(0, -9.81, 0);
  SetLength(F.Surfaces, 3);
  with F.Surfaces[SurfWall] do
  begin
    // the box's 25 kg/m2; the torso's wall is 35 mm of muscle and fat
    Moving := True; Tension := 100; Damping := 0; Clamp := True;
    if UseBox then Mass := 25 else Mass := 36;
  end;
  with F.Surfaces[SurfDiaphragm] do
  begin
    Moving := True; Mass := 4; Tension := 50; Damping := 0; Clamp := True;
  end;
  if UseBox then
  begin
    BuildBox(20, 18, 10, Box.L, Box.W, Box.H, X, Y, Z, Tets);
    F.SetMesh(X, Y, Z, Tets);
    F.FindBoundary(Box.Classify);
  end
  else
  begin
    Torso.BuildMesh(X, Y, Z, Tets);
    F.SetMesh(X, Y, Z, Tets);
    F.FindBoundary(Torso.Classify);
  end;
  F.AddToSystem(Sys);
  Th.AddToSystem(Sys, F, SurfDiaphragm);
end;

procedure ImpedanceAt(f : Double; out Rrs, Xrs : Double);
// Zrs below the jet: a unit pressure source in the lower airway with no
// jet flow drives Q_aw = 1/(Zua + Zrs)
var
  w, q2 : Double;
  B, Zr, Xr, Xi : TVMobj;
begin
  w := 2 * Pi * f;
  B := TVMobj.Create(Sys.N, 1);
  Zr := TVMobj.Create(Sys.N, 1);
  B.DataPtr[Th.iQaw] := 1;
  Sys.SolveFrequency(w, B, Zr, Xr, Xi);
  q2 := Sqr(Xr.DataPtr[Th.iQaw]) + Sqr(Xi.DataPtr[Th.iQaw]);
  Rrs := Xr.DataPtr[Th.iQaw] / q2 - Th.P.Rua * RUnit;
  Xrs := -Xi.DataPtr[Th.iQaw] / q2 - w * Th.P.Iua * IUnit;
end;

procedure Impedance;
const
  Fs : array[0..9] of Double = (1, 2, 3, 4, 5, 6, 8, 10, 15, 20);
var
  i : Integer;
  w, Rrs, Xrs : Double;
begin
  WriteLn('Impedance below the jet (and at the mouth, + upper airway), cmH2O/(L/s):');
  WriteLn('    f Hz      Rrs      Xrs    |   Rmouth   Xmouth');
  for i := 0 to High(Fs) do
  begin
    w := 2 * Pi * Fs[i];
    ImpedanceAt(Fs[i], Rrs, Xrs);
    WriteLn(Format('  %6.1f  %7.2f  %7.2f    |  %7.2f  %7.2f',
      [Fs[i], Rrs / RUnit, Xrs / RUnit, (Rrs + Th.P.Rua * RUnit) / RUnit,
       (Xrs + w * Th.P.Iua * IUnit) / RUnit]));
  end;
  WriteLn;
end;

procedure ImpedanceFile(const Fn : String);
// 0.25 to 20 Hz in 0.25 Hz steps, for plot_impedance.py
var
  i : Integer;
  f, Rrs, Xrs : Double;
  Fo : TextFile;
begin
  AssignFile(Fo, Fn);
  ReWrite(Fo);
  WriteLn(Fo, 'f_Hz,Rrs,Xrs,Rmouth,Xmouth');
  for i := 1 to 80 do
  begin
    f := 0.25 * i;
    ImpedanceAt(f, Rrs, Xrs);
    WriteLn(Fo, Format('%.2f,%.4f,%.4f,%.4f,%.4f', [f, Rrs / RUnit, Xrs / RUnit,
      (Rrs + Th.P.Rua * RUnit) / RUnit, (Xrs + 2 * Pi * f * Th.P.Iua * IUnit) / RUnit]));
    Write(#13'  ', i, ' of 80');
  end;
  WriteLn;
  CloseFile(Fo);
  WriteLn('Wrote ', Fn);
end;

procedure Sweep;
const
  Rates : array[0..9] of Integer = (60, 100, 150, 200, 250, 300, 400, 500, 600, 800);
var
  i : Integer;
  P : TThoraxParams;
  C : TCycle;
  S : TCycleSummary;
  Cache : TResponseCache;
begin
  // the forcing pattern doesn't change with rate, so each frequency is
  // solved once however many rates share it as a harmonic
  Cache := TResponseCache.Create;
  WriteLn(Format('Sweep of rate at %.1f bar, I:E 1:%.2g (Ti %.2f):', [P0.DrivingP, (1 - P0.Ti) / P0.Ti, P0.Ti]));
  WriteLn(' rate/min   VT mL  dia %  PAmean PAmax PAmin  Ptmean  jet mL entr mL  VT/VD  fVT2 L2/s');
  for i := 0 to High(Rates) do
  begin
    P := P0;
    P.Freq := Rates[i] / 60;
    Th.P := P;   // only the forcing changes with rate: no rebuild needed
    C := CycleByHarmonics(Sys, Th, NHarm, 600, Cache);
    S := Summarise(C, Th);
    WriteLn(Format('  %5d   %7.1f  %5.0f  %6.2f %5.2f %5.2f  %6.2f  %6.1f  %6.1f  %5.2f   %7.4f',
      [Rates[i], 1000 * S.VT, 100 * S.VTdi / S.VT, S.PAmean, S.PAmax, S.PAmin, S.Ptmean,
       1000 * S.JetVol, 1000 * S.EntrainVol, S.VTVD, S.FVT2]));
  end;
  Th.P := P0;
  Cache.Free;
  WriteLn;
end;

procedure WallWaves;
const
  NX = 9;
var
  Xr, Xi : TVMobj;
  i, k, best : Integer;
  w, x, d, bd, amp, ph, hn, z0, z1, zk, yk : Double;
  nd : Integer;
begin
  w := 2 * Pi * P0.Freq;
  HarmonicResponse(Sys, Th, w, Xr, Xi);
  // the fundamental's complex amplitude is 2 c_1 times this response
  hn := 2 * Sqrt(Sqr(Sin(2 * Pi * P0.Ti)) + Sqr(1 - Cos(2 * Pi * P0.Ti))) / (2 * Pi);
  WriteLn(Format('Anterior wall at the fundamental (%.2f Hz), midline, diaphragm to pelvis:', [P0.Freq]));
  if UseBox then
    WriteLn('    x mm   |eta| um   phase deg')
  else
  begin
    // the torso's wall runs from the pubis to the xiphoid
    z0 := Torso.LowZ(Pi / 2); z1 := Torso.CostalZ(Pi / 2);
    WriteLn('    z mm   |eta| um   phase deg   (z above the perineum: pubis ',
      Round(1000 * z0), ', xiphoid ', Round(1000 * z1), ')');
  end;
  for i := 0 to NX - 1 do
  begin
    best := -1; bd := 1e30;
    if UseBox then
    begin
      x := Box.L * i / (NX - 1);
      for k := 0 to F.NbMovingDofs - 1 do
        if Abs(F.Z[F.MovNode[k]] - Box.H) < 1e-9 then
        begin
          d := Sqr(F.X[F.MovNode[k]] - x) + Sqr(F.Y[F.MovNode[k]] - Box.W / 2);
          if d < bd then begin bd := d; best := k; end;
        end;
    end
    else
    begin
      // from the xiphoid down to the pubis, the wall node nearest the
      // front midline (x = 0, highest y) at each height
      x := z1 + (z0 - z1) * i / (NX - 1);
      for k := 0 to F.NbMovingDofs - 1 do
      begin
        nd := F.MovNode[k];
        yk := F.Y[nd]; zk := F.Z[nd];
        if Abs(zk - x) > 0.6 * Torso.MeshSize then Continue;
        if yk < Torso.Body.Cy then Continue;
        // wall nodes only: below the diaphragm's rim at the front
        if zk > Torso.RimZ(Pi / 2) - 0.002 then Continue;
        d := Sqr(F.X[nd]) + 0.25 * Sqr(zk - x);
        if d < bd then begin bd := d; best := k; end;
      end;
    end;
    if best < 0 then Continue;
    amp := hn * Sqrt(Sqr(Xr.DataPtr[F.EtaBase + best]) + Sqr(Xi.DataPtr[F.EtaBase + best]));
    ph := RadToDeg(ArcTan2(Xi.DataPtr[F.EtaBase + best], Xr.DataPtr[F.EtaBase + best]));
    if UseBox then x := F.X[F.MovNode[best]] else x := F.Z[F.MovNode[best]];
    WriteLn(Format('  %6.0f  %9.1f   %8.1f%s', [1000 * x, 1e6 * amp, ph,
      StrUtils.IfThen(F.Clamped[best], '  (clamped edge)', '')]));
  end;
  WriteLn;
end;

procedure VentFile(const Fn : String);
// the steady cycle every 20 /min from 40 to 900 /min, as CSV for
// plot_ventilation.py; 20 harmonics unless --harm is given
var
  r, nh : Integer;
  P : TThoraxParams;
  C : TCycle;
  S : TCycleSummary;
  Cache : TResponseCache;
  Fo : TextFile;
begin
  nh := Round(Opt('harm', 20));
  Cache := TResponseCache.Create;
  AssignFile(Fo, Fn);
  ReWrite(Fo);
  WriteLn(Fo, 'rate_min,VT_mL,VTdi_mL,VD_mL,PAmean,PAmax,jet_mL,entrained_mL');
  r := 40;
  while r <= 900 do
  begin
    P := P0;
    P.Freq := r / 60;
    Th.P := P;
    C := CycleByHarmonics(Sys, Th, nh, 600, Cache);
    S := Summarise(C, Th);
    WriteLn(Fo, Format('%d,%.3f,%.3f,%.1f,%.4f,%.4f,%.3f,%.3f',
      [r, 1000 * S.VT, 1000 * S.VTdi, 1000 * P.VD, S.PAmean, S.PAmax,
       1000 * S.JetVol, 1000 * S.EntrainVol]));
    Write(#13'  ', r, ' /min');
    Inc(r, 20);
  end;
  WriteLn;
  Th.P := P0;
  Cache.Free;
  CloseFile(Fo);
  WriteLn('Wrote ', Fn);
end;

procedure AnimFile(const Fn : String);
// one steady cycle of every moving node's displacement (the mean taken
// out), summed over harmonics 1..NHarm, plus the lung volume, for an
// animation: see anim_wall.py
const
  NS = 48;
var
  Xr, Xi : TVMobj;
  n, k, j, a : Integer;
  w, th_, ar, ai, yr, yi, t, Per : Double;
  Eta : array of array of Double;
  VLt : array[0..NS - 1] of Double;
  tri : TIntegerArray;
  Fo : TextFile;
begin
  Per := 1 / P0.Freq;
  SetLength(Eta, F.NbMovingDofs, NS);
  for j := 0 to NS - 1 do VLt[j] := 0;
  for n := 1 to NHarm do
  begin
    w := 2 * Pi * P0.Freq * n;
    th_ := 2 * Pi * n * P0.Ti;
    ar := 2 * Sin(th_) / (2 * Pi * n);
    ai := -2 * (1 - Cos(th_)) / (2 * Pi * n);
    HarmonicResponse(Sys, Th, w, Xr, Xi);
    for j := 0 to NS - 1 do
    begin
      t := Per * j / NS;
      for k := 0 to F.NbMovingDofs - 1 do
      begin
        yr := ar * Xr.DataPtr[F.EtaBase + k] - ai * Xi.DataPtr[F.EtaBase + k];
        yi := ai * Xr.DataPtr[F.EtaBase + k] + ar * Xi.DataPtr[F.EtaBase + k];
        Eta[k][j] := Eta[k][j] + yr * Cos(w * t) - yi * Sin(w * t);
      end;
      yr := ar * Th.VL(Xr) - ai * Th.VL(Xi);
      yi := ai * Th.VL(Xr) + ar * Th.VL(Xi);
      VLt[j] := VLt[j] + yr * Cos(w * t) - yi * Sin(w * t);
    end;
    Write(#13'  harmonic ', n, ' of ', NHarm);
  end;
  WriteLn;
  tri := F.TriNodes;
  AssignFile(Fo, Fn);
  ReWrite(Fo);
  WriteLn(Fo, 'rate ', 60 * P0.Freq:0:1, ' ti ', P0.Ti:0:3, ' dp ', P0.DrivingP:0:2, ' frames ', NS,
    ' period ', Per:0:6, ' box ', Ord(UseBox));
  WriteLn(Fo, 'nodes ', F.NbNodes);
  for k := 0 to F.NbNodes - 1 do
    WriteLn(Fo, F.X[k]:0:6, ' ', F.Y[k]:0:6, ' ', F.Z[k]:0:6);
  WriteLn(Fo, 'tris ', Length(F.TriSurf));
  for k := 0 to High(F.TriSurf) do
    WriteLn(Fo, tri[3 * k], ' ', tri[3 * k + 1], ' ', tri[3 * k + 2], ' ', F.TriSurf[k]);
  WriteLn(Fo, 'moving ', F.NbMovingDofs);
  for k := 0 to F.NbMovingDofs - 1 do
  begin
    a := F.MovNode[k];
    Write(Fo, a, ' ', Ord(F.Clamped[k]));
    for j := 0 to NS - 1 do Write(Fo, ' ', 1e6 * Eta[k][j]:0:2);   // um
    WriteLn(Fo);
  end;
  Write(Fo, 'vl');
  for j := 0 to NS - 1 do Write(Fo, ' ', 1e6 * VLt[j]:0:3);   // mL
  WriteLn(Fo);
  CloseFile(Fo);
  WriteLn('Wrote ', Fn);
end;

procedure StepCheck;
var
  C : TCycle;
  S : TCycleSummary;
begin
  C := CycleByStepping(Sys, Th, 400, 400, 1e-5);
  S := Summarise(C, Th);
  WriteLn(Format('Time-stepped at %.0f /min: %d cycles to settle; VT %.1f mL, PA mean %.2f cmH2O',
    [60 * P0.Freq, C.Cycles, 1000 * S.VT, S.PAmean]));
end;

var
  t0 : TDateTime;
begin
  InitializeCBLAS;
  FormatSettings.DecimalSeparator := '.';
  Lumped := Flag('lumped');
  Alpha := Opt('alpha', 5);
  P0 := DefaultThoraxParams;
  P0.DrivingP := Opt('dp', P0.DrivingP);
  P0.Freq := Opt('rate', 200) / 60;
  P0.Ti := 1 / (1 + Opt('ie', 1));
  P0.Cannula := TJetCath(Round(Opt('cannula', Ord(P0.Cannula))));
  if Flag('calculated') then P0.JetSource := jsCalculated;

  UseBox := Flag('box');
  NHarm := Round(Opt('harm', 30));
  Box := TAbdomenBox.Create;
  Box.L := 0.30; Box.W := 0.26; Box.H := 0.14; Box.DiaphragmEnd := True;
  Torso := nil;
  if not (UseBox or Lumped) then
  begin
    Torso := TTorsoAbdomen.Create(Opt('height', 1.75), Opt('weight', 70));
    Torso.MeshSize := Opt('size', 12) / 1000;
  end;
  t0 := Now;
  BuildModel(P0);
  WriteLn(Format('Jet: %s cannula at %.2f bar: %.1f l/min while open (Crane %.1f), momentum %.1f cmH2O (formula %.1f)',
    [Th.Cath.Name, P0.DrivingP, 60000 * Th.QOn, 60000 * Th.QOnCalc, Th.DpOn / cmH2O, Th.DpOnCalc / cmH2O]));
  WriteLn('     ', Th.JetNote);
  if not IsNan(Th.BenchEntrained) then
    WriteLn(Format('     bench total (jet + entrained) flow, open circuit: %.0f l/min', [60000 * Th.BenchEntrained]));
  if Lumped then
    WriteLn('Abdomen: lumped with the diaphragm')
  else if UseBox then
    WriteLn(Format('Abdomen: fluid box %.0f x %.0f x %.0f mm (%.1f L), %d nodes, drag %.1f /s; %d unknowns',
      [1000 * Box.L, 1000 * Box.W, 1000 * Box.H, 1000 * F.TotalVolume, F.NbNodes, Alpha, Sys.N]))
  else
    WriteLn(Format('Abdomen: gmsh torso, %.2f m %.0f kg, cavity %.1f L, pelvic floor to diaphragm apex %.0f mm, '
      + '%d nodes (mesh %.0f mm), drag %.1f /s; %d unknowns',
      [Torso.Body.Height, Torso.Body.Weight, 1000 * F.TotalVolume, 1000 * (Torso.ZTop - Torso.ZFloor),
       F.NbNodes, 1000 * Torso.MeshSize, Alpha, Sys.N]));
  WriteLn;
  if StrOpt('vfile') <> '' then
  begin
    VentFile(StrOpt('vfile'));
    Th.Free; Sys.Free; F.Free; Box.Free; Torso.Free;
    Exit;
  end;
  if StrOpt('zfile') <> '' then
  begin
    ImpedanceFile(StrOpt('zfile'));
    Th.Free; Sys.Free; F.Free; Box.Free; Torso.Free;
    Exit;
  end;
  if (not Lumped) and (StrOpt('anim') <> '') then
  begin
    AnimFile(StrOpt('anim'));
    Th.Free; Sys.Free; F.Free; Box.Free; Torso.Free;
    Exit;
  end;
  Impedance;
  Sweep;
  if not Lumped then WallWaves;
  if Flag('steps') then StepCheck;
  WriteLn(Format('(%.1f s)', [(Now - t0) * 86400]));
  Th.Free; Sys.Free; F.Free; Box.Free; Torso.Free;
end.
