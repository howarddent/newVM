unit uLVMech;

{ Finite-strain mechanics of the left ventricular wall. FEM4's own
  structural engine is small-strain isotropic linear elasticity, so this
  is self-contained: only the sparse solver (newVMsparse, PARDISO) is
  shared. Units: mm, kPa, s (so forces are mN and volumes mm3).

  GEOMETRY   a thick-walled prolate ellipsoid truncated by the basal
  plane z = ZB: endocardium with semi-axes AEn (short), CEn (long),
  epicardium AEp, CEp, apex at z = -C. Structured 8-node hexahedra, NR
  through the wall, NL from apex to base, NC round; the apical ring's
  elements are hexahedra with one edge collapsed onto the axis.

  FIBRES   helix angle varying linearly through the wall from AlphaEndo
  (+60 deg, right-handed) to AlphaEpi (-60 deg), measured from the
  circumferential direction in the plane normal to the transmural one.

  PASSIVE   Guccione, McCulloch & Waldman 1991, transversely isotropic:
     W = C/2 (exp Q - 1)
     Q = bf Eff^2 + bt (Ess^2 + Enn^2 + 2 Esn^2) + 2 bfs (Efs^2 + Efn^2)
  written without a sheet direction, with f the fibre unit vector,
     Q = bt E:E + (bf + bt - 2 bfs) (f.Ef)^2 + 2 (bfs - bt) |Ef|^2 .

  INCOMPRESSIBILITY   mean dilatation per element: with theta the
  element's current over reference volume, an energy Kappa/2 V (theta-1)^2
  is added, i.e. a constant element pressure p = Kappa (theta - 1). This
  is the Q1/P0 element with the pressure eliminated.

  ACTIVE   Hill type, after Kerckhoffs, Bovendeerd et al. 2003 (Ann
  Biomed Eng 31:536): a contractile element of length lc in series with
  an elastic one, sarcomere length ls = ls0 * fibre stretch,
     Tn  = fiso(lc) ftwitch(ta, ls) Ea (ls - lc)     (nominal stress)
     fiso = T0 tanh^2(al (lc - lc0)),  lc > lc0
     ftwitch = tanh^2(ta/tauR) tanh^2((tmax - ta)/tauD), 0 < ta < tmax
     tmax = b (ls - ld)
     dlc/dt = (Ea (ls - lc) - 1) v0 .
  Force-length is fiso, force-velocity comes from the contractile
  element's kinetics, and a longer sarcomere contracts for longer. The
  second Piola-Kirchhoff active stress is (Tn / stretch) f(x)f, with an
  optional fraction CrossFibre of it across the fibres in the plane of
  the wall (Walker et al. 2005 took 0.4, from Lin & Yin's biaxial tests
  of 1998; the tangent is then unsymmetric). lc is
  stepped by backward Euler, which makes it an explicit function of the
  new ls, so the tangent is consistent; its one scalar derivative is
  taken by finite difference. ta is time since local depolarisation,
  which starts at the apical endocardium and takes TApexBase to reach
  the base and TTransmural to cross the wall.

  CAVITY   the blood is a volume V at one pressure p. V is the exact
  volume enclosed by the endocardial bilinear faces and the basal plane,
  and the pressure's nodal forces are p dV/du, so the load is
  conservative and follows the wall. p is an unknown: prescribed
  (cmPressure) or found from V(u) = VTarget(p) (cmVolume), where the
  target comes from the circulation.

  BOUNDARY CONDITIONS   base nodes stay in the plane z = ZB and slide in
  it; the endocardial basal ring cannot move circumferentially (penalty).
  No pericardium, right ventricle or papillary muscles.

  SOLUTION   Newton's method on wall and cavity together. The elements'
  forces and stiffnesses are computed in parallel (Threads), then
  scattered serially through a map, built once, from each contribution
  to its place in the matrix; PARDISO's analysis is done once and each
  iteration only refactorises. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, newVM, newVMsparse;

type
  TLVGeom = record
    AEn, CEn, AEp, CEp, ZB: Double;
    NR, NL, NC: Integer;
    AlphaEndo, AlphaEpi: Double; { degrees }
  end;

  TLVMaterial = record
    C, bf, bt, bfs, Kappa: Double;
    T0, Ea, al, lc0, ls0, v0, tauR, tauD, b, ld: Double;
    CrossFibre: Double; { active stress across the fibres, in the wall's plane, as a fraction of that along them }
    TApexBase, TTransmural: Double;
  end;

  TCavityMode = (cmPressure, cmVolume);
  TVolTarget = function(P: Double; out dVdP: Double): Double of object;

  TLVModel = class
  private
    FConn: array of array[0..7] of Integer;
    FEI, FEJ: array of Integer;
    FGW, FGdN, FGFib, FGCross, FGTdep: array of Double;
    FElemV0: array of Double;
    FQuads: array of array[0..3] of Integer;
    FFixed: array of Boolean;
    FRing: array of Integer;
    FRingT: array of Double;
    FLc, FLcTrial: array of Double;
    FU, FR, FAbs, FdV: array of Double;
    FPc: Double;
    FEndo: array of Integer;         { dofs of the endocardial nodes }
    FKe, FRe, FESum: array of Double;  { per element: 576, 24, 3 }
    FEOk: array of Boolean;
    FHe: array of Double;              { per endocardial face: 144 }
    FMap: array of Integer;            { contribution -> unique entry }
    FKill: array of Boolean;           { contribution on a fixed row or column }
    FUI, FUJ: TIntegerArray;
    FUV: TDoubleArray;
    FNT: Integer;
    FBaseQ, FBaseR, FBaseC, FBaseP, FBaseF: Integer;
    FFac: TPardisoFactor;
    FMode: TCavityMode;
    FVolFn: TVolTarget;
    FRp, FDvdp: Double;
    FVcav: Double;
    FMeanStretch, FMeanTn: Double;
    FT, FDt: Double;
    FNext: LongInt;
    FVel: array of Double;
    FVelP: Double;
    FHaveVel: Boolean;
    FActive, FBuildK: Boolean;
    FWorkers: array of TThread;
    procedure BuildPattern;
    function ActiveTn(ls, lcOld, ta, dt: Double; out lcNew: Double): Double;
    function ElementCompute(e: Integer): Boolean;
    procedure RunElements;
    function Assemble(t, dt: Double; Active, BuildK: Boolean): Boolean;
    procedure AssembleCavity(BuildK: Boolean);
    procedure BuildGauss(Ellipsoid: Boolean; const Fibre: array of Double);
    function DummyVol(P: Double; out dVdP: Double): Double;
  public
    Geom: TLVGeom;
    Mat: TLVMaterial;
    NN, NE, NDof: Integer;
    X, U: array of Double;   { reference coordinates, displacements }
    Pcav: Double;            { cavity pressure, kPa }
    ElemP: array of Double;  { element pressures Kappa (theta - 1) }
    Iterations: Integer;     { Newton iterations of the last Solve }
    Verbose: Boolean;
    RingStiffness: Double;
    Predictor: Boolean;      { start each time step from the last one's rates }
    Tolerance: Double;       { largest nodal force imbalance over largest nodal force }
    MType: Integer;          { PARDISO: 11 unsymmetric, -2 symmetric indefinite }
    TimeAssemble, TimeSparse, TimeSolve, TimeElems: Double; { seconds, accumulated }
    NAssemble: Integer;
    FExt: array of Double;   { dead nodal loads, mN (for the checks) }
    Threads: Integer;        { for the element loop; set before the first Solve }
    constructor Create(const AGeom: TLVGeom; const AMat: TLVMaterial);
    destructor Destroy; override;
    procedure ElementRange(Part: Integer);  { for the worker threads }
    { a rectangular block of nx x ny x nz elements with uniform fibres,
      symmetry planes at x = 0, y = 0, z = 0 and no cavity: for the checks }
    constructor CreateBlock(nx, ny, nz: Integer; Lx, Ly, Lz: Double;
      const Fibre: array of Double; const AMat: TLVMaterial);
    procedure FixDof(n: Integer);
    { passive strain energy of the trial state, from Guccione's law in
      its fibre-frame form: an independent check on the residual }
    function StrainEnergy: Double;
    function TrialResidual(n: Integer): Double;
    function AssembleTrial(t, dt: Double; Active: Boolean): Boolean;
    function NodeId(i, j, k: Integer): Integer;
    { One load or time step to time t (step dt; dt = 0 and Active False
      for a passive load step). On success the trial state is held until
      Accept; U, Pcav and the contractile lengths are unchanged before. }
    function Solve(t, dt: Double; Active: Boolean; Mode: TCavityMode;
      PPresc: Double; VolFn: TVolTarget): Boolean;
    procedure Accept;
    procedure ResetContractile;
    function CavityVolume: Double;       { of the accepted state, mm3 }
    function TrialVolume: Double;
    function WallVolume: Double;         { current, mm3 }
    function RingRotation(i, j: Integer): Double; { radians, + anticlockwise from the base }
    function WallThickness(j: Integer): Double;
    function EndoRadius(j: Integer): Double;
    function LongAxis: Double;           { endocardial apex to base, mm }
    { element means over the Gauss points, from the last assembly }
    function ElemStretch(e: Integer): Double;  { fibre stretch }
    function ElemActive(e: Integer): Double;   { active fibre stress, Cauchy, kPa }
    property MeanFibreStretch: Double read FMeanStretch; { last assembly }
    property MeanActiveStress: Double read FMeanTn;      { Cauchy, kPa }
    { for the checks }
    procedure CheckTangent(t, dt: Double; Active: Boolean; out MaxErr, MaxK: Double);
    procedure SetTrial(const AU: array of Double; APc: Double);
  end;

function TruncVolume(a, c, zb: Double): Double;
{ A 70 kg adult's ventricle: unloaded cavity V0 and wall volume in mL,
  endocardial apex-to-base length in mm. }
function AdultGeometry(V0mL, WallmL, CavityLength: Double): TLVGeom;
function DefaultMaterial: TLVMaterial;

implementation

const
  GP: Double = 0.57735026918962576;
  XiN: array[0..7, 0..2] of Integer = ((-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),
    (-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1));
  VI: array[0..5] of Integer = (0, 1, 2, 0, 1, 0);
  VJ: array[0..5] of Integer = (0, 1, 2, 1, 2, 2);

function TruncVolume(a, c, zb: Double): Double;
begin
  Result := Pi * a * a * ((zb + c) - (zb * zb * zb + c * c * c) / (3 * c * c));
end;

function AdultGeometry(V0mL, WallmL, CavityLength: Double): TLVGeom;
const
  Trunc = 0.36;     { basal plane this fraction of CEn above the equator }
  ApexRatio = 0.6;  { apical over equatorial wall thickness }
var
  lo, hi, h, target: Double;
  it: Integer;
begin
  Result.CEn := CavityLength / (1 + Trunc);
  Result.ZB := Trunc * Result.CEn;
  Result.AEn := Sqrt(V0mL * 1000 / TruncVolume(1, Result.CEn, Result.ZB));
  target := (V0mL + WallmL) * 1000;
  lo := 0; hi := 40; h := 10;
  for it := 1 to 60 do
  begin
    h := 0.5 * (lo + hi);
    if TruncVolume(Result.AEn + h, Result.CEn + ApexRatio * h, Result.ZB) < target then
      lo := h
    else
      hi := h;
  end;
  Result.AEp := Result.AEn + h;
  Result.CEp := Result.CEn + ApexRatio * h;
  Result.NR := 3; Result.NL := 10; Result.NC := 16;
  Result.AlphaEndo := 60; Result.AlphaEpi := -60;
end;

function DefaultMaterial: TLVMaterial;
begin
  { Guccione 1991's exponents (canine); C is fitted to the Klotz
    end-diastolic pressure-volume relation by lvrun --fitpassive }
  Result.C := 0.616; Result.bf := 18.48; Result.bt := 3.58; Result.bfs := 1.627;
  Result.Kappa := 5000;
  { Hill model after Kerckhoffs 2003 (lengths um, T0 kPa, Ea 1/um, v0
    um/s, b s/um): Ea, al, lc0, v0 and ld are that paper's. Changed
    here: ls0 2.0 (was 1.9), which puts the end-diastolic sarcomere at
    the measured 2.2 um; and the twitch's timing, tauR 0.10, tauD 0.07,
    b 0.22 (were 0.075, 0.075, 0.15, a dog's), for a human ejection
    time near 280 ms at 70 /min; and T0 145 kPa (was 180), set with the
    pulmonary venous pressure for a stroke volume of 72 mL from 125 mL }
  Result.T0 := 145; Result.Ea := 20; Result.al := 2.0; Result.lc0 := 1.5;
  Result.ls0 := 2.0; Result.v0 := 7.5; Result.tauR := 0.10; Result.tauD := 0.07;
  Result.b := 0.22; Result.ld := -0.4;
  Result.CrossFibre := 0.4;
  Result.TApexBase := 0.030; Result.TTransmural := 0.025;
end;

{ ---------------------------------------------------------------- }

function Det3(const A: array of Double): Double; inline;
begin
  Result := A[0] * (A[4] * A[8] - A[5] * A[7]) - A[1] * (A[3] * A[8] - A[5] * A[6])
    + A[2] * (A[3] * A[7] - A[4] * A[6]);
end;

procedure Inv3(const A: array of Double; d: Double; var R: array of Double); inline;
begin
  R[0] := (A[4] * A[8] - A[5] * A[7]) / d;
  R[1] := (A[2] * A[7] - A[1] * A[8]) / d;
  R[2] := (A[1] * A[5] - A[2] * A[4]) / d;
  R[3] := (A[5] * A[6] - A[3] * A[8]) / d;
  R[4] := (A[0] * A[8] - A[2] * A[6]) / d;
  R[5] := (A[2] * A[3] - A[0] * A[5]) / d;
  R[6] := (A[3] * A[7] - A[4] * A[6]) / d;
  R[7] := (A[1] * A[6] - A[0] * A[7]) / d;
  R[8] := (A[0] * A[4] - A[1] * A[3]) / d;
end;

function QuadVolume(const Xc: array of Double; const qn: array of Integer; zb: Double): Double;
{ a bilinear face's share of the volume between it and the plane z = zb:
  the integral of (z - zb) n_z dA }
const
  QS: array[0..3] of Integer = (-1, 1, 1, -1);
  QT: array[0..3] of Integer = (-1, -1, 1, 1);
var
  g, a: Integer;
  s_, t_, xs, xt, ys, yt, zz, lf: Double;
begin
  Result := 0;
  for g := 0 to 3 do
  begin
    s_ := QS[g] * GP; t_ := QT[g] * GP;
    xs := 0; xt := 0; ys := 0; yt := 0; zz := -zb;
    for a := 0 to 3 do
    begin
      lf := QS[a] * (1 + QT[a] * t_) / 4;
      xs := xs + lf * Xc[3 * qn[a]]; ys := ys + lf * Xc[3 * qn[a] + 1];
      lf := QT[a] * (1 + QS[a] * s_) / 4;
      xt := xt + lf * Xc[3 * qn[a]]; yt := yt + lf * Xc[3 * qn[a] + 1];
      zz := zz + (1 + QS[a] * s_) * (1 + QT[a] * t_) / 4 * Xc[3 * qn[a] + 2];
    end;
    Result := Result + zz * (xs * yt - xt * ys);
  end;
end;

function TLVModel.NodeId(i, j, k: Integer): Integer;
begin
  if j = 0 then
    Result := i
  else
  begin
    k := k mod Geom.NC;
    Result := (Geom.NR + 1) + ((j - 1) * Geom.NC + k) * (Geom.NR + 1) + i;
  end;
end;

constructor TLVModel.Create(const AGeom: TLVGeom; const AMat: TLVMaterial);
var
  i, j, k, e, a, n, q: Integer;
  ai, ci, phib, phi, th, vd: Double;
  qn: array[0..3] of Integer;
begin
  inherited Create;
  Geom := AGeom; Mat := AMat;
  RingStiffness := 1e5;
  NN := (Geom.NR + 1) * (1 + Geom.NL * Geom.NC);
  NE := Geom.NR * Geom.NL * Geom.NC;
  NDof := 3 * NN + 1;
  SetLength(X, 3 * NN); SetLength(U, 3 * NN); SetLength(FU, 3 * NN);
  SetLength(FR, NDof); SetLength(FAbs, NDof); SetLength(FdV, 3 * NN);
  SetLength(FFixed, 3 * NN); SetLength(FExt, 3 * NN);
  for i := 0 to Geom.NR do
  begin
    ai := Geom.AEn + (Geom.AEp - Geom.AEn) * i / Geom.NR;
    ci := Geom.CEn + (Geom.CEp - Geom.CEn) * i / Geom.NR;
    phib := ArcCos(-Geom.ZB / ci);
    for j := 0 to Geom.NL do
    begin
      phi := phib * j / Geom.NL;
      for k := 0 to Geom.NC - 1 do
      begin
        if (j = 0) and (k > 0) then Break;
        th := 2 * Pi * k / Geom.NC;
        n := NodeId(i, j, k);
        X[3 * n] := ai * Sin(phi) * Cos(th);
        X[3 * n + 1] := ai * Sin(phi) * Sin(th);
        X[3 * n + 2] := -ci * Cos(phi);
        if j = Geom.NL then
        begin
          X[3 * n + 2] := Geom.ZB;
          FFixed[3 * n + 2] := True;
          if i = 0 then
          begin
            SetLength(FRing, Length(FRing) + 1);
            FRing[High(FRing)] := n;
            SetLength(FRingT, Length(FRingT) + 2);
            FRingT[High(FRingT) - 1] := -Sin(th);
            FRingT[High(FRingT)] := Cos(th);
          end;
        end;
      end;
    end;
  end;
  { The faceted surfaces enclose less than the ellipsoids they sample.
    Each layer is scaled in x and y so that it encloses its ellipsoid's
    volume exactly; cavity and wall volumes are then the nominal ones at
    any mesh size. }
  for i := 0 to Geom.NR do
  begin
    ai := Geom.AEn + (Geom.AEp - Geom.AEn) * i / Geom.NR;
    ci := Geom.CEn + (Geom.CEp - Geom.CEn) * i / Geom.NR;
    vd := 0;
    for j := 0 to Geom.NL - 1 do
      for k := 0 to Geom.NC - 1 do
      begin
        qn[0] := NodeId(i, j, k); qn[1] := NodeId(i, j, k + 1);
        qn[2] := NodeId(i, j + 1, k + 1); qn[3] := NodeId(i, j + 1, k);
        vd := vd + QuadVolume(X, qn, Geom.ZB);
      end;
    th := Sqrt(TruncVolume(ai, ci, Geom.ZB) / vd);
    for j := 0 to Geom.NL do
      for k := 0 to Geom.NC - 1 do
      begin
        if (j = 0) and (k > 0) then Break;
        n := NodeId(i, j, k);
        X[3 * n] := X[3 * n] * th; X[3 * n + 1] := X[3 * n + 1] * th;
      end;
  end;
  SetLength(FConn, NE); SetLength(FEI, NE); SetLength(FEJ, NE);
  SetLength(FQuads, Geom.NL * Geom.NC);
  e := 0; q := 0;
  for i := 0 to Geom.NR - 1 do
    for j := 0 to Geom.NL - 1 do
      for k := 0 to Geom.NC - 1 do
      begin
        FConn[e][0] := NodeId(i, j, k);         FConn[e][1] := NodeId(i, j, k + 1);
        FConn[e][2] := NodeId(i, j + 1, k + 1); FConn[e][3] := NodeId(i, j + 1, k);
        FConn[e][4] := NodeId(i + 1, j, k);     FConn[e][5] := NodeId(i + 1, j, k + 1);
        FConn[e][6] := NodeId(i + 1, j + 1, k + 1); FConn[e][7] := NodeId(i + 1, j + 1, k);
        FEI[e] := i; FEJ[e] := j;
        if i = 0 then
        begin
          for a := 0 to 3 do FQuads[q][a] := FConn[e][a];
          Inc(q);
        end;
        Inc(e);
      end;
  BuildGauss(True, [1.0, 0, 0]);
  Tolerance := 1e-7; MType := 11; Threads := 1; Predictor := True;
end;

procedure TLVModel.BuildGauss(Ellipsoid: Boolean; const Fibre: array of Double);
var
  e, g, a, d, n, k: Integer;
  dep, lf, rho, alpha, nrm, dJ: Double;
  xi: array[0..2] of Double;
  dNl: array[0..7, 0..2] of Double;
  Jm, Ji: array[0..8] of Double;
  pos, ec, tv, nv, el: array[0..2] of Double;
begin
  { Gauss point data }
  SetLength(FGW, NE * 8); SetLength(FGdN, NE * 8 * 24); SetLength(FGFib, NE * 8 * 3); SetLength(FGCross, NE * 8 * 3);
  SetLength(FGTdep, NE * 8); SetLength(FLc, NE * 8); SetLength(FLcTrial, NE * 8);
  SetLength(FElemV0, NE); SetLength(ElemP, NE);
  for e := 0 to NE - 1 do
  begin
    FElemV0[e] := 0;
    for g := 0 to 7 do
    begin
      for d := 0 to 2 do xi[d] := XiN[g, d] * GP;
      for a := 0 to 7 do
      begin
        dNl[a, 0] := XiN[a, 0] * (1 + XiN[a, 1] * xi[1]) * (1 + XiN[a, 2] * xi[2]) / 8;
        dNl[a, 1] := XiN[a, 1] * (1 + XiN[a, 0] * xi[0]) * (1 + XiN[a, 2] * xi[2]) / 8;
        dNl[a, 2] := XiN[a, 2] * (1 + XiN[a, 0] * xi[0]) * (1 + XiN[a, 1] * xi[1]) / 8;
      end;
      for d := 0 to 8 do Jm[d] := 0;
      for d := 0 to 2 do pos[d] := 0;
      for a := 0 to 7 do
      begin
        n := FConn[e][a];
        lf := (1 + XiN[a, 0] * xi[0]) * (1 + XiN[a, 1] * xi[1]) * (1 + XiN[a, 2] * xi[2]) / 8;
        for d := 0 to 2 do
        begin
          pos[d] := pos[d] + lf * X[3 * n + d];
          { Jm[i,j] = dX_i / dxi_j }
          for k := 0 to 2 do Jm[3 * d + k] := Jm[3 * d + k] + X[3 * n + d] * dNl[a, k];
        end;
      end;
      dJ := Det3(Jm);
      if dJ <= 0 then
        raise Exception.CreateFmt('TLVModel.Create : element %d has a non-positive Jacobian', [e]);
      Inv3(Jm, dJ, Ji);
      FGW[e * 8 + g] := dJ;
      FElemV0[e] := FElemV0[e] + dJ;
      { dN/dX_i = dN/dxi_k * dxi_k/dX_i = dNl[a,k] * Ji[k,i] }
      for a := 0 to 7 do
        for d := 0 to 2 do
          FGdN[(e * 8 + g) * 24 + a * 3 + d] := dNl[a, 0] * Ji[d] + dNl[a, 1] * Ji[3 + d]
            + dNl[a, 2] * Ji[6 + d];
      FGTdep[e * 8 + g] := 0;
      if not Ellipsoid then
      begin
        for d := 0 to 2 do FGFib[(e * 8 + g) * 3 + d] := Fibre[d];
        { any direction across the fibre }
        if Abs(Fibre[2]) < 0.9 then begin ec[0] := 0; ec[1] := 0; ec[2] := 1; end
        else begin ec[0] := 1; ec[1] := 0; ec[2] := 0; end;
        el[0] := Fibre[1] * ec[2] - Fibre[2] * ec[1];
        el[1] := Fibre[2] * ec[0] - Fibre[0] * ec[2];
        el[2] := Fibre[0] * ec[1] - Fibre[1] * ec[0];
        nrm := Sqrt(el[0] * el[0] + el[1] * el[1] + el[2] * el[2]);
        for d := 0 to 2 do FGCross[(e * 8 + g) * 3 + d] := el[d] / nrm;
        Continue;
      end;
      { fibre }
      rho := Sqrt(pos[0] * pos[0] + pos[1] * pos[1]);
      ec[0] := -pos[1] / rho; ec[1] := pos[0] / rho; ec[2] := 0;
      for d := 0 to 2 do tv[d] := Jm[3 * d + 2];
      nrm := tv[0] * ec[0] + tv[1] * ec[1] + tv[2] * ec[2];
      for d := 0 to 2 do nv[d] := tv[d] - nrm * ec[d];
      nrm := Sqrt(nv[0] * nv[0] + nv[1] * nv[1] + nv[2] * nv[2]);
      for d := 0 to 2 do nv[d] := nv[d] / nrm;
      el[0] := nv[1] * ec[2] - nv[2] * ec[1];
      el[1] := nv[2] * ec[0] - nv[0] * ec[2];
      el[2] := nv[0] * ec[1] - nv[1] * ec[0];
      dep := (FEI[e] + 0.5 * (xi[2] + 1)) / Geom.NR;
      alpha := (Geom.AlphaEndo + (Geom.AlphaEpi - Geom.AlphaEndo) * dep) * Pi / 180;
      for d := 0 to 2 do
      begin
        FGFib[(e * 8 + g) * 3 + d] := Cos(alpha) * ec[d] + Sin(alpha) * el[d];
        { across the fibre, in the plane of the wall }
        FGCross[(e * 8 + g) * 3 + d] := -Sin(alpha) * ec[d] + Cos(alpha) * el[d];
      end;
      FGTdep[e * 8 + g] := Mat.TApexBase * (FEJ[e] + 0.5 * (xi[1] + 1)) / Geom.NL
        + Mat.TTransmural * dep;
    end;
  end;
  ResetContractile;
end;

procedure TLVModel.ResetContractile;
var
  g: Integer;
begin
  { resting: the series element carries Ea (ls - lc) = 1 }
  for g := 0 to High(FLc) do
  begin
    FLc[g] := Mat.ls0 - 1 / Mat.Ea;
    FLcTrial[g] := FLc[g];
  end;
end;

function TLVModel.ActiveTn(ls, lcOld, ta, dt: Double; out lcNew: Double): Double;
var
  tmax, ftw, fiso: Double;
begin
  if dt > 0 then
    lcNew := (lcOld + dt * Mat.v0 * (Mat.Ea * ls - 1)) / (1 + dt * Mat.v0 * Mat.Ea)
  else
    lcNew := lcOld;
  Result := 0;
  if ta <= 0 then Exit;
  tmax := Mat.b * (ls - Mat.ld);
  if ta >= tmax then Exit;
  if lcNew <= Mat.lc0 then Exit;
  ftw := Sqr(Tanh(ta / Mat.tauR)) * Sqr(Tanh((tmax - ta) / Mat.tauD));
  fiso := Mat.T0 * Sqr(Tanh(Mat.al * (lcNew - Mat.lc0)));
  Result := fiso * ftw * Mat.Ea * (ls - lcNew);
  if Result < 0 then Result := 0;
end;

function TLVModel.ElementCompute(e: Integer): Boolean;
{ One element's nodal forces (FRe) and tangent (FKe) from the trial
  state. Writes only that element's own storage, so elements can be
  done in parallel. False if the element is inverted or absurdly
  strained. }
const
  hl = 1e-6;
var
  g, a, bn, i, j, k, l, p, q, gi, aHi: Integer;
  ue: array[0..23] of Double;
  Re, gv: array[0..23] of Double;
  Ke: array[0..23, 0..23] of Double;
  Fg, Fi: array[0..7, 0..8] of Double;
  Jd: array[0..7] of Double;
  Cg, Ci, Eg, Sg, Mg, FS: array[0..8] of Double;
  Dm: array[0..5, 0..5] of Double;
  Bm: array[0..7, 0..5, 0..2] of Double;
  DB: array[0..5, 0..2] of Double;
  fb, cb, gE, SdN: array[0..2] of Double;
  dN: PDouble;
  w, ve, theta, pe, Eff, Qe, eQ, al_, be_, ga_, lam, Tn, Tp, Tm, lcn, gA, dgA,
    v, ta, sumW, sumL, sumT, dotS, cf, t, dt, nu: Double;
  Active, BuildK: Boolean;
begin
  Result := False;
  t := FT; dt := FDt; Active := FActive; BuildK := FBuildK;
  nu := Mat.CrossFibre;
  al_ := Mat.bt; be_ := Mat.bf + Mat.bt - 2 * Mat.bfs; ga_ := 2 * (Mat.bfs - Mat.bt);
  sumW := 0; sumL := 0; sumT := 0;
  for a := 0 to 7 do
    for i := 0 to 2 do ue[3 * a + i] := FU[3 * FConn[e][a] + i];
  { pass 1: deformation gradients, element volume and its gradient }
  ve := 0;
  for i := 0 to 23 do gv[i] := 0;
  for g := 0 to 7 do
  begin
    dN := @FGdN[(e * 8 + g) * 24];
    for i := 0 to 8 do Fg[g][i] := 0;
    Fg[g][0] := 1; Fg[g][4] := 1; Fg[g][8] := 1;
    for a := 0 to 7 do
      for i := 0 to 2 do
        for j := 0 to 2 do
          Fg[g][3 * i + j] := Fg[g][3 * i + j] + ue[3 * a + i] * dN[a * 3 + j];
    Jd[g] := Det3(Fg[g]);
    if Jd[g] <= 1e-3 then Exit;
    Inv3(Fg[g], Jd[g], Fi[g]);
    w := FGW[e * 8 + g];
    ve := ve + Jd[g] * w;
    for a := 0 to 7 do
      for i := 0 to 2 do
        gv[3 * a + i] := gv[3 * a + i] + Jd[g] * w *
          (Fi[g][i] * dN[a * 3] + Fi[g][3 + i] * dN[a * 3 + 1] + Fi[g][6 + i] * dN[a * 3 + 2]);
  end;
  theta := ve / FElemV0[e];
  pe := Mat.Kappa * (theta - 1);
  ElemP[e] := pe;
  for i := 0 to 23 do Re[i] := 0;
  if BuildK then
    for i := 0 to 23 do
      for j := 0 to 23 do Ke[i, j] := 0;
  { pass 2: stresses and tangent }
  for g := 0 to 7 do
  begin
    gi := e * 8 + g;
    dN := @FGdN[gi * 24];
    w := FGW[gi];
    for i := 0 to 2 do fb[i] := FGFib[gi * 3 + i];
    for i := 0 to 2 do cb[i] := FGCross[gi * 3 + i];
    for i := 0 to 2 do
      for j := 0 to 2 do
      begin
        Cg[3 * i + j] := Fg[g][i] * Fg[g][j] + Fg[g][3 + i] * Fg[g][3 + j] + Fg[g][6 + i] * Fg[g][6 + j];
        Ci[3 * i + j] := Fi[g][3 * i] * Fi[g][3 * j] + Fi[g][3 * i + 1] * Fi[g][3 * j + 1]
          + Fi[g][3 * i + 2] * Fi[g][3 * j + 2];
      end;
    for i := 0 to 8 do Eg[i] := 0.5 * Cg[i];
    Eg[0] := Eg[0] - 0.5; Eg[4] := Eg[4] - 0.5; Eg[8] := Eg[8] - 0.5;
    for i := 0 to 2 do gE[i] := Eg[3 * i] * fb[0] + Eg[3 * i + 1] * fb[1] + Eg[3 * i + 2] * fb[2];
    Eff := fb[0] * gE[0] + fb[1] * gE[1] + fb[2] * gE[2];
    Qe := 0;
    for i := 0 to 8 do Qe := Qe + Eg[i] * Eg[i];
    Qe := al_ * Qe + be_ * Eff * Eff + ga_ * (gE[0] * gE[0] + gE[1] * gE[1] + gE[2] * gE[2]);
    if Qe > 50 then Exit;
    eQ := Mat.C * Exp(Qe);
    for i := 0 to 2 do
      for j := 0 to 2 do
        Mg[3 * i + j] := al_ * Eg[3 * i + j] + be_ * Eff * fb[i] * fb[j]
          + 0.5 * ga_ * (fb[i] * gE[j] + gE[i] * fb[j]);
    { active }
    lam := Sqrt(2 * Eff + 1);
    gA := 0; dgA := 0; Tn := 0;
    if Active then
    begin
      ta := t - FGTdep[gi];
      Tn := ActiveTn(Mat.ls0 * lam, FLc[gi], ta, dt, lcn);
      FLcTrial[gi] := lcn;
      gA := Tn / lam;
      if BuildK then
      begin
        Tp := ActiveTn(Mat.ls0 * (lam + hl), FLc[gi], ta, dt, lcn);
        Tm := ActiveTn(Mat.ls0 * (lam - hl), FLc[gi], ta, dt, lcn);
        dgA := (Tp / (lam + hl) - Tm / (lam - hl)) / (2 * hl);
      end;
    end;
    sumW := sumW + w; sumL := sumL + w * lam; sumT := sumT + w * Tn * lam;
    for i := 0 to 2 do
      for j := 0 to 2 do
      begin
        Sg[3 * i + j] := eQ * Mg[3 * i + j] + gA * (fb[i] * fb[j] + nu * cb[i] * cb[j])
          + pe * Jd[g] * Ci[3 * i + j];
      end;
    { residual: R_ai = (F S)_iJ N_a,J }
    for i := 0 to 2 do
      for j := 0 to 2 do
        FS[3 * i + j] := Fg[g][3 * i] * Sg[j] + Fg[g][3 * i + 1] * Sg[3 + j] + Fg[g][3 * i + 2] * Sg[6 + j];
    for a := 0 to 7 do
      for i := 0 to 2 do
        Re[3 * a + i] := Re[3 * a + i] + w *
          (FS[3 * i] * dN[a * 3] + FS[3 * i + 1] * dN[a * 3 + 1] + FS[3 * i + 2] * dN[a * 3 + 2]);
    if not BuildK then Continue;
    { material tangent in Voigt form }
    for p := 0 to 5 do
      for q := 0 to 5 do
      begin
        i := VI[p]; j := VJ[p]; k := VI[q]; l := VJ[q];
        v := 2 * Mg[3 * i + j] * Mg[3 * k + l] + be_ * fb[i] * fb[j] * fb[k] * fb[l];
        if (i = k) and (j = l) then v := v + 0.5 * al_;
        if (i = l) and (j = k) then v := v + 0.5 * al_;
        cf := 0;
        if j = k then cf := cf + fb[i] * fb[l];
        if j = l then cf := cf + fb[i] * fb[k];
        if i = k then cf := cf + fb[l] * fb[j];
        if i = l then cf := cf + fb[k] * fb[j];
        v := eQ * (v + 0.25 * ga_ * cf);
        v := v + dgA / lam * (fb[i] * fb[j] + nu * cb[i] * cb[j]) * fb[k] * fb[l];
        v := v + pe * Jd[g] * (Ci[3 * i + j] * Ci[3 * k + l]
          - Ci[3 * i + k] * Ci[3 * j + l] - Ci[3 * i + l] * Ci[3 * j + k]);
        Dm[p, q] := v;
      end;
    for a := 0 to 7 do
      for k := 0 to 2 do
      begin
        Bm[a, 0, k] := Fg[g][3 * k] * dN[a * 3];
        Bm[a, 1, k] := Fg[g][3 * k + 1] * dN[a * 3 + 1];
        Bm[a, 2, k] := Fg[g][3 * k + 2] * dN[a * 3 + 2];
        Bm[a, 3, k] := Fg[g][3 * k] * dN[a * 3 + 1] + Fg[g][3 * k + 1] * dN[a * 3];
        Bm[a, 4, k] := Fg[g][3 * k + 1] * dN[a * 3 + 2] + Fg[g][3 * k + 2] * dN[a * 3 + 1];
        Bm[a, 5, k] := Fg[g][3 * k] * dN[a * 3 + 2] + Fg[g][3 * k + 2] * dN[a * 3];
      end;
    for bn := 0 to 7 do
    begin
      for p := 0 to 5 do
        for k := 0 to 2 do
        begin
          v := 0;
          for q := 0 to 5 do v := v + Dm[p, q] * Bm[bn, q, k];
          DB[p, k] := v * w;
        end;
      for i := 0 to 2 do
        SdN[i] := Sg[3 * i] * dN[bn * 3] + Sg[3 * i + 1] * dN[bn * 3 + 1] + Sg[3 * i + 2] * dN[bn * 3 + 2];
      if nu = 0 then aHi := bn else aHi := 7;
      for a := 0 to aHi do
      begin
        dotS := w * (dN[a * 3] * SdN[0] + dN[a * 3 + 1] * SdN[1] + dN[a * 3 + 2] * SdN[2]);
        for i := 0 to 2 do
        begin
          for k := 0 to 2 do
          begin
            v := 0;
            for p := 0 to 5 do v := v + Bm[a, p, i] * DB[p, k];
            Ke[3 * a + i, 3 * bn + k] := Ke[3 * a + i, 3 * bn + k] + v;
          end;
          Ke[3 * a + i, 3 * bn + i] := Ke[3 * a + i, 3 * bn + i] + dotS;
        end;
      end;
    end;
  end;
  if BuildK then
  begin
    { without cross-fibre active stress the tangent is symmetric and
      only blocks a <= b were formed }
    if nu = 0 then
    for a := 0 to 7 do
      for bn := a + 1 to 7 do
        for i := 0 to 2 do
          for k := 0 to 2 do
            Ke[3 * bn + k, 3 * a + i] := Ke[3 * a + i, 3 * bn + k];
    v := Mat.Kappa / FElemV0[e];
    for i := 0 to 23 do
      for j := 0 to 23 do Ke[i, j] := Ke[i, j] + v * gv[i] * gv[j];
  end;
  Move(Re[0], FRe[e * 24], 24 * SizeOf(Double));
  if BuildK then Move(Ke[0, 0], FKe[e * 576], 576 * SizeOf(Double));
  FESum[3 * e] := sumW; FESum[3 * e + 1] := sumL; FESum[3 * e + 2] := sumT;
  Result := True;
end;

type
  TLVWorker = class(TThread)
  public
    Model: TLVModel;
    Part: Integer;
    Go, Done: PRTLEvent;
    procedure Execute; override;
  end;

procedure TLVWorker.Execute;
begin
  while True do
  begin
    RTLEventWaitFor(Go);
    if Terminated then Break;
    Model.ElementRange(Part);
    RTLEventSetEvent(Done);
  end;
end;

procedure TLVModel.ElementRange(Part: Integer);
{ elements are taken four at a time from a shared counter, so that
  faster cores do more of them }
var
  e, e0: Integer;
begin
  while True do
  begin
    e0 := InterlockedExchangeAdd(FNext, 4);
    if e0 >= NE then Break;
    for e := e0 to Min(e0 + 3, NE - 1) do FEOk[e] := ElementCompute(e);
  end;
end;

procedure TLVModel.RunElements;
var
  i: Integer;
  W: TLVWorker;
begin
  if Threads < 1 then Threads := 1;
  if Threads > NE then Threads := NE;
  if (Threads > 1) and (Length(FWorkers) <> Threads - 1) then
  begin
    SetLength(FWorkers, Threads - 1);
    for i := 0 to Threads - 2 do
    begin
      W := TLVWorker.Create(True);
      W.Model := Self; W.Part := i + 1;
      W.Go := RTLEventCreate; W.Done := RTLEventCreate;
      W.FreeOnTerminate := False;
      FWorkers[i] := W;
      W.Start;
    end;
  end;
  FNext := 0;
  for i := 0 to Threads - 2 do RTLEventSetEvent(TLVWorker(FWorkers[i]).Go);
  ElementRange(0);
  for i := 0 to Threads - 2 do RTLEventWaitFor(TLVWorker(FWorkers[i]).Done);
end;

destructor TLVModel.Destroy;
var
  i: Integer;
  W: TLVWorker;
begin
  for i := 0 to High(FWorkers) do
  begin
    W := TLVWorker(FWorkers[i]);
    W.Terminate;
    RTLEventSetEvent(W.Go);
    W.WaitFor;
    RTLEventDestroy(W.Go); RTLEventDestroy(W.Done);
    W.Free;
  end;
  FFac.Free;
  inherited;
end;

function TLVModel.DummyVol(P: Double; out dVdP: Double): Double;
begin
  Result := FVcav; dVdP := 0;
end;

procedure TLVModel.BuildPattern;
{ The fixed list of matrix contributions, in the order Assemble writes
  them, and its map onto the unique (row, column) entries. }
var
  n, e, a, i, bn, k, q, r, c, m, P, nFixed, tot: Integer;
  TI, TJ: array of Integer;
  rowCols: array of array of Integer;
  rowLen, rowOff, loc: array of Integer;
  seen: array of Boolean;

  procedure Put(rr, cc: Integer; Fixable: Boolean);
  begin
    TI[n] := rr; TJ[n] := cc;
    FKill[n] := Fixable and (((rr < P) and FFixed[rr]) or ((cc < P) and FFixed[cc]));
    Inc(n);
  end;

begin
  P := 3 * NN;
  FreeAndNil(FFac);
  { endocardial dofs }
  SetLength(seen, NN);
  for i := 0 to NN - 1 do seen[i] := False;
  SetLength(FEndo, 0);
  for q := 0 to High(FQuads) do
    for a := 0 to 3 do
      if not seen[FQuads[q][a]] then
      begin
        seen[FQuads[q][a]] := True;
        for i := 0 to 2 do
        begin
          SetLength(FEndo, Length(FEndo) + 1);
          FEndo[High(FEndo)] := 3 * FQuads[q][a] + i;
        end;
      end;
  nFixed := 0;
  for i := 0 to P - 1 do if FFixed[i] then Inc(nFixed);
  FBaseQ := NE * 576;
  FBaseR := FBaseQ + Length(FQuads) * 144;
  FBaseC := FBaseR + Length(FRing) * 4;
  FBaseP := FBaseC + 2 * Length(FEndo);
  FBaseF := FBaseP + 1;
  tot := FBaseF + nFixed;
  SetLength(TI, tot); SetLength(TJ, tot); SetLength(FKill, tot); SetLength(FMap, tot);
  n := 0;
  for e := 0 to NE - 1 do
    for a := 0 to 7 do
      for i := 0 to 2 do
        for bn := 0 to 7 do
          for k := 0 to 2 do
            Put(3 * FConn[e][a] + i, 3 * FConn[e][bn] + k, True);
  for q := 0 to High(FQuads) do
    for a := 0 to 3 do
      for i := 0 to 2 do
        for bn := 0 to 3 do
          for k := 0 to 2 do
            Put(3 * FQuads[q][a] + i, 3 * FQuads[q][bn] + k, True);
  for r := 0 to High(FRing) do
    for i := 0 to 1 do
      for k := 0 to 1 do
        Put(3 * FRing[r] + i, 3 * FRing[r] + k, True);
  for i := 0 to High(FEndo) do Put(FEndo[i], P, True);
  for i := 0 to High(FEndo) do Put(P, FEndo[i], True);
  Put(P, P, False);
  for i := 0 to P - 1 do
    if FFixed[i] then Put(i, i, False);
  { unique entries, row by row }
  SetLength(rowCols, NDof); SetLength(rowLen, NDof); SetLength(rowOff, NDof + 1);
  SetLength(loc, tot);
  for i := 0 to NDof - 1 do rowLen[i] := 0;
  for m := 0 to tot - 1 do
  begin
    r := TI[m]; c := TJ[m];
    k := -1;
    for i := 0 to rowLen[r] - 1 do
      if rowCols[r][i] = c then begin k := i; Break; end;
    if k < 0 then
    begin
      if rowLen[r] = Length(rowCols[r]) then SetLength(rowCols[r], 2 * rowLen[r] + 32);
      rowCols[r][rowLen[r]] := c;
      k := rowLen[r];
      Inc(rowLen[r]);
    end;
    loc[m] := k;
  end;
  rowOff[0] := 0;
  for i := 0 to NDof - 1 do rowOff[i + 1] := rowOff[i] + rowLen[i];
  FNT := rowOff[NDof];
  SetLength(FUI, FNT); SetLength(FUJ, FNT); SetLength(FUV, FNT);
  for r := 0 to NDof - 1 do
    for i := 0 to rowLen[r] - 1 do
    begin
      FUI[rowOff[r] + i] := r; FUJ[rowOff[r] + i] := rowCols[r][i];
    end;
  for m := 0 to tot - 1 do FMap[m] := rowOff[TI[m]] + loc[m];
  SetLength(FKe, NE * 576); SetLength(FRe, NE * 24); SetLength(FESum, NE * 3);
  SetLength(FEOk, NE); SetLength(FHe, Length(FQuads) * 144);
end;

function TLVModel.Assemble(t, dt: Double; Active, BuildK: Boolean): Boolean;
var
  e, a, i, n, m, P: Integer;
  sumW, sumL, sumT, v: Double;
  pk: PDouble;
  tk: TDateTime;
begin
  Result := False;
  P := 3 * NN;
  if Length(FMap) = 0 then BuildPattern;
  FT := t; FDt := dt; FActive := Active; FBuildK := BuildK;
  tk := Now;
  RunElements;
  TimeElems := TimeElems + (Now - tk) * 86400; Inc(NAssemble);
  for e := 0 to NE - 1 do
    if not FEOk[e] then Exit;
  for i := 0 to NDof - 1 do begin FR[i] := 0; FAbs[i] := 0; end;
  if BuildK then
    for i := 0 to FNT - 1 do FUV[i] := 0;
  sumW := 0; sumL := 0; sumT := 0;
  for e := 0 to NE - 1 do
  begin
    sumW := sumW + FESum[3 * e]; sumL := sumL + FESum[3 * e + 1]; sumT := sumT + FESum[3 * e + 2];
    for a := 0 to 7 do
      for i := 0 to 2 do
      begin
        n := 3 * FConn[e][a] + i;
        v := FRe[e * 24 + 3 * a + i];
        FR[n] := FR[n] + v;
        FAbs[n] := FAbs[n] + Abs(v);
      end;
    if BuildK then
    begin
      pk := @FKe[e * 576];
      m := e * 576;
      for i := 0 to 575 do
        if not FKill[m + i] then FUV[FMap[m + i]] := FUV[FMap[m + i]] + pk[i];
    end;
  end;
  for i := 0 to P - 1 do FR[i] := FR[i] - FExt[i];
  FMeanStretch := sumL / sumW;
  FMeanTn := sumT / sumW;
  AssembleCavity(BuildK);
  { circumferential restraint of the endocardial basal ring }
  for a := 0 to High(FRing) do
  begin
    n := 3 * FRing[a];
    v := FRingT[2 * a] * FU[n] + FRingT[2 * a + 1] * FU[n + 1];
    for i := 0 to 1 do
    begin
      FR[n + i] := FR[n + i] + RingStiffness * v * FRingT[2 * a + i];
      if BuildK then
        for e := 0 to 1 do
        begin
          m := FBaseR + a * 4 + i * 2 + e;
          if not FKill[m] then
            FUV[FMap[m]] := FUV[FMap[m]] + RingStiffness * FRingT[2 * a + i] * FRingT[2 * a + e];
        end;
    end;
  end;
  { cavity row and column }
  FRp := 0; FDvdp := 0;
  if FMode = cmVolume then
    FRp := -(FVcav - FVolFn(FPc, FDvdp));
  FR[P] := FRp;
  if BuildK then
  begin
    if FMode = cmVolume then
    begin
      for i := 0 to High(FEndo) do
      begin
        m := FBaseC + i;
        if not FKill[m] then FUV[FMap[m]] := FUV[FMap[m]] - FdV[FEndo[i]];
        m := FBaseC + Length(FEndo) + i;
        if not FKill[m] then FUV[FMap[m]] := FUV[FMap[m]] - FdV[FEndo[i]];
      end;
      FUV[FMap[FBaseP]] := FDvdp - 1e-6;
    end
    else
      FUV[FMap[FBaseP]] := 1;
    m := FBaseF;
    for i := 0 to P - 1 do
      if FFixed[i] then begin FUV[FMap[m]] := 1; Inc(m); end;
  end;
  for i := 0 to P - 1 do
    if FFixed[i] then FR[i] := 0;
  Result := True;
end;

procedure TLVModel.AssembleCavity(BuildK: Boolean);
var
  q, g, a, bn, n, m: Integer;
  s_, t_, w, xs, xt, ys, yt, zz, v: Double;
  Nf, Ns, Nt: array[0..3] of Double;
  xq: array[0..3, 0..2] of Double;
  He: array[0..11, 0..11] of Double;
const
  QS: array[0..3] of Integer = (-1, 1, 1, -1);
  QT: array[0..3] of Integer = (-1, -1, 1, 1);
begin
  FVcav := 0;
  for n := 0 to 3 * NN - 1 do FdV[n] := 0;
  for q := 0 to High(FQuads) do
  begin
    for a := 0 to 3 do
      for n := 0 to 2 do
        xq[a, n] := X[3 * FQuads[q][a] + n] + FU[3 * FQuads[q][a] + n];
    if BuildK then
      for n := 0 to 11 do
        for m := 0 to 11 do He[n, m] := 0;
    for g := 0 to 3 do
    begin
      s_ := QS[g] * GP; t_ := QT[g] * GP;
      xs := 0; xt := 0; ys := 0; yt := 0; zz := -Geom.ZB;
      for a := 0 to 3 do
      begin
        Nf[a] := (1 + QS[a] * s_) * (1 + QT[a] * t_) / 4;
        Ns[a] := QS[a] * (1 + QT[a] * t_) / 4;
        Nt[a] := QT[a] * (1 + QS[a] * s_) / 4;
        xs := xs + Ns[a] * xq[a, 0]; xt := xt + Nt[a] * xq[a, 0];
        ys := ys + Ns[a] * xq[a, 1]; yt := yt + Nt[a] * xq[a, 1];
        zz := zz + Nf[a] * xq[a, 2];
      end;
      w := xs * yt - xt * ys;
      FVcav := FVcav + zz * w;
      for a := 0 to 3 do
      begin
        n := 3 * FQuads[q][a];
        FdV[n] := FdV[n] + zz * (Ns[a] * yt - Nt[a] * ys);
        FdV[n + 1] := FdV[n + 1] + zz * (xs * Nt[a] - xt * Ns[a]);
        FdV[n + 2] := FdV[n + 2] + Nf[a] * w;
      end;
      if BuildK then
        for a := 0 to 3 do
          for bn := 0 to 3 do
          begin
            { d2V / dx_a dy_b }
            v := zz * (Ns[a] * Nt[bn] - Nt[a] * Ns[bn]);
            He[3 * a, 3 * bn + 1] := He[3 * a, 3 * bn + 1] + v;
            He[3 * bn + 1, 3 * a] := He[3 * bn + 1, 3 * a] + v;
            { d2V / dx_a dz_b }
            v := Nf[bn] * (Ns[a] * yt - Nt[a] * ys);
            He[3 * a, 3 * bn + 2] := He[3 * a, 3 * bn + 2] + v;
            He[3 * bn + 2, 3 * a] := He[3 * bn + 2, 3 * a] + v;
            { d2V / dy_a dz_b }
            v := Nf[bn] * (xs * Nt[a] - xt * Ns[a]);
            He[3 * a + 1, 3 * bn + 2] := He[3 * a + 1, 3 * bn + 2] + v;
            He[3 * bn + 2, 3 * a + 1] := He[3 * bn + 2, 3 * a + 1] + v;
          end;
    end;
    if BuildK then
      for a := 0 to 11 do
        for bn := 0 to 11 do
        begin
          m := FBaseQ + q * 144 + a * 12 + bn;
          if not FKill[m] then FUV[FMap[m]] := FUV[FMap[m]] - FPc * He[a, bn];
        end;
  end;
  for n := 0 to 3 * NN - 1 do
    if FdV[n] <> 0 then
    begin
      FR[n] := FR[n] - FPc * FdV[n];
      FAbs[n] := FAbs[n] + Abs(FPc * FdV[n]);
    end;
end;

function TLVModel.Solve(t, dt: Double; Active: Boolean; Mode: TCavityMode;
  PPresc: Double; VolFn: TVolTarget): Boolean;
const
  MaxIt = 25;
var
  it, i, P: Integer;
  nrm, fref, rp, step, big, n0: Double;
  A: TVMSparseMtx;
  B, D: TVMobj;
  dU, U0: array of Double;
  p0: Double;
  tk: TDateTime;
  ok: Boolean;

  procedure Measure;
  var
    ii: Integer;
  begin
    nrm := 0; fref := 1e-3;
    for ii := 0 to P - 1 do
    begin
      nrm := Max(nrm, Abs(FR[ii]));
      fref := Max(fref, FAbs[ii]);
    end;
    rp := FRp;
  end;

begin
  Result := False;
  P := 3 * NN;
  Move(U[0], FU[0], P * SizeOf(Double));
  FPc := Pcav;
  if Predictor and FHaveVel and (dt > 0) then
  begin
    for i := 0 to P - 1 do FU[i] := U[i] + dt * FVel[i];
    FPc := Pcav + dt * FVelP;
  end;
  if Mode = cmPressure then FPc := PPresc;
  FMode := Mode; FVolFn := VolFn;
  SetLength(dU, NDof); SetLength(U0, P);
  step := 0; n0 := MaxDouble / 1e4; p0 := FPc;
  B := TVMobj.Create(NDof, 1);
  for it := 1 to MaxIt do
  begin
    Iterations := it;
    tk := Now;
    ok := Assemble(t, dt, Active, True);
    TimeAssemble := TimeAssemble + (Now - tk) * 86400;
    if not ok then
    begin
      { the last step inverted an element: shorten it }
      if (it = 1) and Predictor and FHaveVel and (dt > 0) then
      begin
        { the extrapolated start was bad: start from the last state }
        FHaveVel := False;
        Move(U[0], FU[0], P * SizeOf(Double));
        FPc := Pcav;
        Continue;
      end;
      if (it = 1) or (step < 1e-3) then Exit;
      step := 0.5 * step;
      for i := 0 to P - 1 do FU[i] := U0[i] + step * dU[i];
      FPc := p0 + step * dU[P];
      Continue;
    end;
    Measure;
    if IsNan(nrm) or ((it > 6) and (nrm > 1e3 * n0)) then Exit; { diverging }
    if nrm < n0 then n0 := nrm; { the smallest residual so far }
    if Verbose then
      Writeln(Format('    it %2d  |R| %.3e  fref %.3e  rV %.3e  p %.5f  step %.3g',
        [it, nrm, fref, rp, FPc, step]));
    if (nrm < Tolerance * fref) and (Abs(rp) < 1e-9 * (1 + Abs(FVcav))) then
    begin
      Result := True;
      Exit;
    end;
    tk := Now;
    A := TripletsToSparse(NDof, NDof, FUI, FUJ, FUV);
    TimeSparse := TimeSparse + (Now - tk) * 86400;
    for i := 0 to NDof - 1 do B.DataPtr[i] := -FR[i];
    tk := Now;
    if FFac = nil then
      FFac := TPardisoFactor.Create(A, MType)
    else
      FFac.Refactor(A);
    D := FFac.Solve(B);
    TimeSolve := TimeSolve + (Now - tk) * 86400;
    big := 0;
    for i := 0 to NDof - 1 do
    begin
      dU[i] := D.DataPtr[i];
      if i < P then big := Max(big, Abs(dU[i]));
    end;
    Move(FU[0], U0[0], P * SizeOf(Double)); p0 := FPc;
    { no node moves more than 3 mm in one iteration }
    step := 1;
    if big > 3 then step := 3 / big;
    for i := 0 to P - 1 do FU[i] := U0[i] + step * dU[i];
    FPc := p0 + step * dU[P];
  end;
end;

procedure TLVModel.Accept;
var
  i: Integer;
begin
  { rates of the accepted step, for the next step's first guess }
  FHaveVel := FDt > 0;
  if FHaveVel then
  begin
    SetLength(FVel, 3 * NN);
    for i := 0 to 3 * NN - 1 do FVel[i] := (FU[i] - U[i]) / FDt;
    FVelP := (FPc - Pcav) / FDt;
  end;
  Move(FU[0], U[0], 3 * NN * SizeOf(Double));
  Pcav := FPc;
  Move(FLcTrial[0], FLc[0], Length(FLc) * SizeOf(Double));
end;

procedure TLVModel.SetTrial(const AU: array of Double; APc: Double);
begin
  Move(AU[0], FU[0], 3 * NN * SizeOf(Double));
  FPc := APc;
end;

procedure TLVModel.CheckTangent(t, dt: Double; Active: Boolean; out MaxErr, MaxK: Double);
{ the assembled tangent's columns against central differences of the
  residual, at the current trial state, for a sample of dofs }
const
  h = 1e-6;
var
  Kd: array of Double;
  col, i, m: Integer;
  Rp, Rm: array of Double;
  save, fd: Double;
begin
  MaxErr := 0; MaxK := 0;
  FMode := cmVolume; FVolFn := DummyVol;
  SetLength(Rp, NDof); SetLength(Rm, NDof); SetLength(Kd, NDof);
  col := 0;
  while col <= 3 * NN do
  begin
    if (col < 3 * NN) and FFixed[col] then begin Inc(col, 7); Continue; end;
    for i := 0 to NDof - 1 do Kd[i] := 0;
    if not Assemble(t, dt, Active, True) then raise Exception.Create('CheckTangent: bad state');
    for m := 0 to FNT - 1 do
      if FUJ[m] = col then Kd[FUI[m]] := Kd[FUI[m]] + FUV[m];
    if col < 3 * NN then
    begin
      save := FU[col];
      FU[col] := save + h; Assemble(t, dt, Active, False); Move(FR[0], Rp[0], NDof * SizeOf(Double));
      FU[col] := save - h; Assemble(t, dt, Active, False); Move(FR[0], Rm[0], NDof * SizeOf(Double));
      FU[col] := save;
    end
    else
    begin
      save := FPc;
      FPc := save + h; Assemble(t, dt, Active, False); Move(FR[0], Rp[0], NDof * SizeOf(Double));
      FPc := save - h; Assemble(t, dt, Active, False); Move(FR[0], Rm[0], NDof * SizeOf(Double));
      FPc := save;
    end;
    for i := 0 to 3 * NN - 1 do
    begin
      fd := (Rp[i] - Rm[i]) / (2 * h);
      MaxErr := Max(MaxErr, Abs(fd - Kd[i]));
      MaxK := Max(MaxK, Abs(Kd[i]));
    end;
    if col = 3 * NN then Break;
    Inc(col, 7);
    if col > 3 * NN then col := 3 * NN;
  end;
  FMode := cmPressure;
end;

constructor TLVModel.CreateBlock(nx, ny, nz: Integer; Lx, Ly, Lz: Double;
  const Fibre: array of Double; const AMat: TLVMaterial);
var
  i, j, k, e, n: Integer;

  function Id(ii, jj, kk: Integer): Integer;
  begin
    Result := (kk * (ny + 1) + jj) * (nx + 1) + ii;
  end;

begin
  inherited Create;
  Mat := AMat;
  Geom.NR := 1; Geom.NL := 1; Geom.NC := 1; Geom.ZB := 0;
  RingStiffness := 0;
  NN := (nx + 1) * (ny + 1) * (nz + 1);
  NE := nx * ny * nz;
  NDof := 3 * NN + 1;
  SetLength(X, 3 * NN); SetLength(U, 3 * NN); SetLength(FU, 3 * NN);
  SetLength(FR, NDof); SetLength(FAbs, NDof); SetLength(FdV, 3 * NN);
  SetLength(FFixed, 3 * NN); SetLength(FExt, 3 * NN);
  for k := 0 to nz do
    for j := 0 to ny do
      for i := 0 to nx do
      begin
        n := Id(i, j, k);
        X[3 * n] := Lx * i / nx; X[3 * n + 1] := Ly * j / ny; X[3 * n + 2] := Lz * k / nz;
        if i = 0 then FFixed[3 * n] := True;
        if j = 0 then FFixed[3 * n + 1] := True;
        if k = 0 then FFixed[3 * n + 2] := True;
      end;
  SetLength(FConn, NE); SetLength(FEI, NE); SetLength(FEJ, NE);
  e := 0;
  for k := 0 to nz - 1 do
    for j := 0 to ny - 1 do
      for i := 0 to nx - 1 do
      begin
        FConn[e][0] := Id(i, j, k);         FConn[e][1] := Id(i + 1, j, k);
        FConn[e][2] := Id(i + 1, j + 1, k); FConn[e][3] := Id(i, j + 1, k);
        FConn[e][4] := Id(i, j, k + 1);     FConn[e][5] := Id(i + 1, j, k + 1);
        FConn[e][6] := Id(i + 1, j + 1, k + 1); FConn[e][7] := Id(i, j + 1, k + 1);
        Inc(e);
      end;
  BuildGauss(False, Fibre);
  Tolerance := 1e-8; MType := 11; Threads := 1;
end;

procedure TLVModel.FixDof(n: Integer);
begin
  FFixed[n] := True;
  SetLength(FMap, 0); { the pattern is rebuilt at the next assembly }
end;

function TLVModel.TrialResidual(n: Integer): Double;
begin
  Result := FR[n];
end;

function TLVModel.AssembleTrial(t, dt: Double; Active: Boolean): Boolean;
begin
  Result := Assemble(t, dt, Active, False);
end;

function TLVModel.StrainEnergy: Double;
var
  e, g, a, i, j, k: Integer;
  Fg, Eg, El: array[0..8] of Double;
  Rm: array[0..2, 0..2] of Double;
  dN: PDouble;
  ve, Jd, Qe, nrm, d: Double;
begin
  Result := 0;
  for e := 0 to NE - 1 do
  begin
    ve := 0;
    for g := 0 to 7 do
    begin
      dN := @FGdN[(e * 8 + g) * 24];
      for i := 0 to 8 do Fg[i] := 0;
      Fg[0] := 1; Fg[4] := 1; Fg[8] := 1;
      for a := 0 to 7 do
        for i := 0 to 2 do
          for j := 0 to 2 do
            Fg[3 * i + j] := Fg[3 * i + j] + FU[3 * FConn[e][a] + i] * dN[a * 3 + j];
      Jd := Det3(Fg);
      ve := ve + Jd * FGW[e * 8 + g];
      for i := 0 to 2 do
        for j := 0 to 2 do
        begin
          Eg[3 * i + j] := 0.5 * (Fg[i] * Fg[j] + Fg[3 + i] * Fg[3 + j] + Fg[6 + i] * Fg[6 + j]);
          if i = j then Eg[3 * i + j] := Eg[3 * i + j] - 0.5;
        end;
      { an orthonormal frame f, s, n }
      for i := 0 to 2 do Rm[0, i] := FGFib[(e * 8 + g) * 3 + i];
      if Abs(Rm[0, 0]) < 0.9 then begin Rm[1, 0] := 1; Rm[1, 1] := 0; Rm[1, 2] := 0; end
      else begin Rm[1, 0] := 0; Rm[1, 1] := 1; Rm[1, 2] := 0; end;
      d := Rm[1, 0] * Rm[0, 0] + Rm[1, 1] * Rm[0, 1] + Rm[1, 2] * Rm[0, 2];
      for i := 0 to 2 do Rm[1, i] := Rm[1, i] - d * Rm[0, i];
      nrm := Sqrt(Sqr(Rm[1, 0]) + Sqr(Rm[1, 1]) + Sqr(Rm[1, 2]));
      for i := 0 to 2 do Rm[1, i] := Rm[1, i] / nrm;
      Rm[2, 0] := Rm[0, 1] * Rm[1, 2] - Rm[0, 2] * Rm[1, 1];
      Rm[2, 1] := Rm[0, 2] * Rm[1, 0] - Rm[0, 0] * Rm[1, 2];
      Rm[2, 2] := Rm[0, 0] * Rm[1, 1] - Rm[0, 1] * Rm[1, 0];
      for i := 0 to 2 do
        for j := 0 to 2 do
        begin
          El[3 * i + j] := 0;
          for k := 0 to 2 do
            for a := 0 to 2 do
              El[3 * i + j] := El[3 * i + j] + Rm[i, k] * Eg[3 * k + a] * Rm[j, a];
        end;
      Qe := Mat.bf * Sqr(El[0])
        + Mat.bt * (Sqr(El[4]) + Sqr(El[8]) + Sqr(El[5]) + Sqr(El[7]))
        + Mat.bfs * (Sqr(El[1]) + Sqr(El[3]) + Sqr(El[2]) + Sqr(El[6]));
      Result := Result + 0.5 * Mat.C * (Exp(Qe) - 1) * FGW[e * 8 + g];
    end;
    Result := Result + 0.5 * Mat.Kappa * FElemV0[e] * Sqr(ve / FElemV0[e] - 1);
  end;
end;

function TLVModel.TrialVolume: Double;
begin
  Result := FVcav;
end;

function TLVModel.CavityVolume: Double;
var
  save: array of Double;
begin
  save := Copy(FU);
  Move(U[0], FU[0], 3 * NN * SizeOf(Double));
  AssembleCavity(False);
  Result := FVcav;
  Move(save[0], FU[0], 3 * NN * SizeOf(Double));
end;

function TLVModel.WallVolume: Double;
var
  e: Integer;
begin
  Result := 0;
  for e := 0 to NE - 1 do
    Result := Result + FElemV0[e] * (1 + ElemP[e] / Mat.Kappa);
end;

function TLVModel.RingRotation(i, j: Integer): Double;
var
  k, n: Integer;
  d: Double;
begin
  Result := 0;
  for k := 0 to Geom.NC - 1 do
  begin
    n := NodeId(i, j, k);
    d := ArcTan2(X[3 * n + 1] + U[3 * n + 1], X[3 * n] + U[3 * n]) - ArcTan2(X[3 * n + 1], X[3 * n]);
    if d > Pi then d := d - 2 * Pi;
    if d < -Pi then d := d + 2 * Pi;
    Result := Result + d / Geom.NC;
  end;
end;

function TLVModel.WallThickness(j: Integer): Double;
var
  k, n0, n1, d: Integer;
  s2: Double;
begin
  Result := 0;
  for k := 0 to Geom.NC - 1 do
  begin
    n0 := NodeId(0, j, k); n1 := NodeId(Geom.NR, j, k);
    s2 := 0;
    for d := 0 to 2 do s2 := s2 + Sqr(X[3 * n1 + d] + U[3 * n1 + d] - X[3 * n0 + d] - U[3 * n0 + d]);
    Result := Result + Sqrt(s2) / Geom.NC;
  end;
end;

function TLVModel.EndoRadius(j: Integer): Double;
var
  k, n: Integer;
begin
  Result := 0;
  for k := 0 to Geom.NC - 1 do
  begin
    n := NodeId(0, j, k);
    Result := Result + Sqrt(Sqr(X[3 * n] + U[3 * n]) + Sqr(X[3 * n + 1] + U[3 * n + 1])) / Geom.NC;
  end;
end;

function TLVModel.ElemStretch(e: Integer): Double;
begin
  if FESum[3 * e] > 0 then Result := FESum[3 * e + 1] / FESum[3 * e] else Result := 1;
end;

function TLVModel.ElemActive(e: Integer): Double;
begin
  if FESum[3 * e] > 0 then Result := FESum[3 * e + 2] / FESum[3 * e] else Result := 0;
end;

function TLVModel.LongAxis: Double;
begin
  Result := Geom.ZB - (X[2] + U[2]);
end;

end.
