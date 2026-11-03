unit uAbdomenFluid;

{ The abdominal contents as an incompressible fluid with moving walls,
  by linear tetrahedra, for HFJV.

  THE MODEL

  Bowel, mesentery, fat and the solid organs are treated as one
  incompressible, inviscid fluid of density rho at body temperature,
  with a linear drag alpha standing in for the friction of loops of
  bowel sliding over one another:

      rho (u_t + alpha u) = -grad p' ,   div u = 0 ,

  so u = grad phi, laplacian(phi) = 0 and the dynamic pressure is
  p' = -rho (phi_t + alpha phi). The shear stiffness of the tissue is
  left out: that is the main simplification, and the one a solid
  (u-p) formulation would remove.

  The boundary is divided into SURFACES, each with an id. A rigid
  surface (back, pelvis, pelvic floor) takes no flux, so waves reflect
  from it. A MOVING surface (anterior abdominal wall, diaphragm) carries
  its outward normal displacement eta, a membrane of surface density m
  (kg/m2) under tension T (N/m), with damping c (Pa s/m):

      m eta_tt + c eta_t - T lap_s(eta) + rho g_up eta
             + rho (phi_t + alpha phi) = -p_ext ,     phi_n = eta_t .

  g_up = -(n . g) is the part of gravity along the outward normal: the
  hydrostatic pressure at a wall point displaced by eta changes by
  -rho g_up eta, which is the restoring force of a gravity wave. Supine,
  the anterior wall has g_up ~ +g; on the flanks it vanishes. p_ext is
  the pressure outside (atmosphere, or pleural pressure on the
  diaphragm), which other parts of the model couple in through
  CouplePressure.

  Because the fluid is incompressible the moving surfaces must between
  them conserve volume: the diaphragm going down is the anterior wall
  coming up. The constant part of phi is the Lagrange multiplier that
  enforces it (the uniform pressure in the abdomen), so the potential
  needs no gauge condition.

  DISCRETISATION

  Galerkin P1 on tetrahedra for phi (K = int grad Ni . grad Nj) and P1
  on the boundary triangles for eta, with the consistent boundary mass
  S = int Ni Nj, the membrane stiffness int grad_s Ni . grad_s Nj and
  the gravity term int g_up Ni Nj. In descriptor form (uDescriptor),
  with v = eta_t:

      eta rows       eta'  = v
      momentum rows  (m S) v' + rho S' phi'
                       = -(c S) v - (T Ks + rho Sg) eta - rho alpha S' phi - S p_ext
      phi rows       0 = -K phi + S v          (algebraic)

  The momentum m v + rho S' phi is the differential quantity, as
  uDescriptor's header explains. A moving node that also lies on a
  rigid surface is clamped (eta = v = 0) if its surface asks for it - a
  membrane under tension must be held at its edge; a gravity-only free
  surface (the tank tests) must not be. }

{$mode delphi}{$H+}

interface

uses SysUtils, Math, newVM, newVMsparse, uDescriptor;

type
  TVec3 = record X, Y, Z : Double; end;

  TSurfaceProps = record
    Moving : Boolean;
    Mass : Double;      // kg/m2
    Damping : Double;   // Pa s/m
    Tension : Double;   // N/m
    Clamp : Boolean;    // hold eta = 0 where this surface meets a rigid one
  end;

  { Called once per boundary triangle with its centroid and outward unit
    normal; returns the surface id (index into Surfaces). }
  TSurfaceClassifier = function(const C, N : TVec3) : Integer of object;

  TAbdomenFluid = class
  private
    FNbNodes : Integer;
    FTets : TIntegerArray;          // 4 per tet
    FTri : TIntegerArray;           // 3 per boundary triangle, outward
    FTriSurf : TIntegerArray;
    FTriN : array of TVec3;         // outward unit normal
    FTriArea : TDoubleArray;
    FMovIndex : TIntegerArray;      // mesh node -> moving dof, or -1
    FMovNode : TIntegerArray;       // moving dof -> mesh node
    FClamped : TBooleanArray;
    FNodeNormal : array of TVec3;   // per moving dof
    FPhiBase, FEtaBase, FVBase : Integer;
    function NbMoving : Integer;
  public
    X, Y, Z : TDoubleArray;
    Rho, Alpha : Double;
    G : TVec3;                      // gravity, m/s2, pointing down
    Surfaces : array of TSurfaceProps;

    procedure SetMesh(const AX, AY, AZ : TDoubleArray; const ATets : TIntegerArray);
    { Finds the boundary faces, orients them outward and asks Classify
      for each one's surface id. }
    procedure FindBoundary(Classify : TSurfaceClassifier);
    { Adds phi, eta and v unknowns and their equations to Sys. Call after
      FindBoundary and after Surfaces is filled in. }
    procedure AddToSystem(Sys : TDescriptorSystem);

    { int N_j over surface SurfId, per moving dof (zero off it): the
      volume swept by a unit eta at node j. }
    function SurfaceWeights(SurfId : Integer) : TDoubleArray;
    { A uniform pressure unknown (system dof PDof) acting from OUTSIDE on
      surface SurfId: adds -w_i p to each momentum row. }
    procedure CouplePressure(Sys : TDescriptorSystem; SurfId, PDof : Integer);
    { Adds the load of an outside pressure p (nodal values per mesh node,
      zero where not wanted) on surface SurfId into B (system size). }
    procedure AddPressureLoad(var B : TVMobj; SurfId : Integer; const P : TDoubleArray);

    function TotalVolume : Double;
    property NbNodes : Integer read FNbNodes;
    property NbMovingDofs : Integer read NbMoving;
    property PhiBase : Integer read FPhiBase;
    property EtaBase : Integer read FEtaBase;
    property VBase : Integer read FVBase;
    property MovIndex : TIntegerArray read FMovIndex;
    property MovNode : TIntegerArray read FMovNode;
    property Clamped : TBooleanArray read FClamped;
    property TriNodes : TIntegerArray read FTri;
    property TriSurf : TIntegerArray read FTriSurf;
  end;

function Vec3(AX, AY, AZ : Double) : TVec3;

implementation

function Vec3(AX, AY, AZ : Double) : TVec3;
begin
  Result.X := AX; Result.Y := AY; Result.Z := AZ;
end;

function Sub(const A, B : TVec3) : TVec3;
begin
  Result := Vec3(A.X - B.X, A.Y - B.Y, A.Z - B.Z);
end;

function Dot(const A, B : TVec3) : Double;
begin
  Result := A.X * B.X + A.Y * B.Y + A.Z * B.Z;
end;

function Cross(const A, B : TVec3) : TVec3;
begin
  Result := Vec3(A.Y * B.Z - A.Z * B.Y, A.Z * B.X - A.X * B.Z, A.X * B.Y - A.Y * B.X);
end;

function TAbdomenFluid.NbMoving : Integer;
begin
  Result := Length(FMovNode);
end;

procedure TAbdomenFluid.SetMesh(const AX, AY, AZ : TDoubleArray; const ATets : TIntegerArray);
begin
  X := Copy(AX); Y := Copy(AY); Z := Copy(AZ);
  FNbNodes := Length(AX);
  FTets := Copy(ATets);
end;

{ ---- boundary ---- }

procedure SortKeys(var K : array of Int64; var Tag : TIntegerArray; L, R : Integer);
var
  i, j, t : Integer;
  p, tk : Int64;
begin
  while L < R do
  begin
    i := L; j := R; p := K[(L + R) shr 1];
    repeat
      while K[i] < p do Inc(i);
      while K[j] > p do Dec(j);
      if i <= j then
      begin
        tk := K[i]; K[i] := K[j]; K[j] := tk;
        t := Tag[i]; Tag[i] := Tag[j]; Tag[j] := t;
        Inc(i); Dec(j);
      end;
    until i > j;
    if j - L < R - i then
    begin
      SortKeys(K, Tag, L, j); L := i;
    end
    else
    begin
      SortKeys(K, Tag, i, R); R := j;
    end;
  end;
end;

procedure TAbdomenFluid.FindBoundary(Classify : TSurfaceClassifier);
const
  Face : array[0..3, 0..3] of Integer =
    ((1, 2, 3, 0), (0, 2, 3, 1), (0, 1, 3, 2), (0, 1, 2, 3)); // 3 nodes + opposite
var
  nt, nf, k, f, i, a, b, c, q, t, nb : Integer;
  Keys : array of Int64;
  Tag : TIntegerArray;
  s : array[0..2] of Integer;
  P0, P1, P2, PQ, Nrm, Cen : TVec3;
  ar : Double;
begin
  Assert(FNbNodes < 2097152, 'FindBoundary : too many nodes for the face key');
  nt := Length(FTets) div 4;
  nf := 4 * nt;
  SetLength(Keys, nf);
  SetLength(Tag, nf);
  for k := 0 to nt - 1 do
    for f := 0 to 3 do
    begin
      s[0] := FTets[4 * k + Face[f, 0]];
      s[1] := FTets[4 * k + Face[f, 1]];
      s[2] := FTets[4 * k + Face[f, 2]];
      // sort the three
      if s[0] > s[1] then begin t := s[0]; s[0] := s[1]; s[1] := t; end;
      if s[1] > s[2] then begin t := s[1]; s[1] := s[2]; s[2] := t; end;
      if s[0] > s[1] then begin t := s[0]; s[0] := s[1]; s[1] := t; end;
      Keys[4 * k + f] := (Int64(s[0]) shl 42) or (Int64(s[1]) shl 21) or Int64(s[2]);
      Tag[4 * k + f] := 4 * k + f;
    end;
  SortKeys(Keys, Tag, 0, nf - 1);

  SetLength(FTri, 0);
  nb := 0;
  i := 0;
  while i < nf do
  begin
    if (i + 1 < nf) and (Keys[i + 1] = Keys[i]) then
    begin
      Inc(i, 2);
      Continue;
    end;
    // a face seen once is on the boundary
    k := Tag[i] div 4; f := Tag[i] mod 4;
    a := FTets[4 * k + Face[f, 0]];
    b := FTets[4 * k + Face[f, 1]];
    c := FTets[4 * k + Face[f, 2]];
    q := FTets[4 * k + Face[f, 3]];
    P0 := Vec3(X[a], Y[a], Z[a]);
    P1 := Vec3(X[b], Y[b], Z[b]);
    P2 := Vec3(X[c], Y[c], Z[c]);
    PQ := Vec3(X[q], Y[q], Z[q]);
    Nrm := Cross(Sub(P1, P0), Sub(P2, P0));
    if Dot(Nrm, Sub(PQ, P0)) > 0 then
    begin
      t := b; b := c; c := t;
      Nrm := Vec3(-Nrm.X, -Nrm.Y, -Nrm.Z);
    end;
    ar := Sqrt(Dot(Nrm, Nrm));
    if Length(FTri) < 3 * (nb + 1) then
    begin
      SetLength(FTri, 6 * nb + 3072);
      SetLength(FTriSurf, 2 * nb + 1024);
      SetLength(FTriN, 2 * nb + 1024);
      SetLength(FTriArea, 2 * nb + 1024);
    end;
    FTri[3 * nb] := a; FTri[3 * nb + 1] := b; FTri[3 * nb + 2] := c;
    FTriN[nb] := Vec3(Nrm.X / ar, Nrm.Y / ar, Nrm.Z / ar);
    FTriArea[nb] := 0.5 * ar;
    Cen := Vec3((P0.X + P1.X + P2.X) / 3, (P0.Y + P1.Y + P2.Y) / 3, (P0.Z + P1.Z + P2.Z) / 3);
    FTriSurf[nb] := Classify(Cen, FTriN[nb]);
    Inc(nb);
    Inc(i);
  end;
  SetLength(FTri, 3 * nb);
  SetLength(FTriSurf, nb);
  SetLength(FTriN, nb);
  SetLength(FTriArea, nb);
end;

{ ---- assembly ---- }

procedure TAbdomenFluid.AddToSystem(Sys : TDescriptorSystem);
var
  nt, nb, k, i, j, a, b, nm : Integer;
  n : array[0..3] of Integer;
  D, Inv : array[0..2, 0..2] of Double;
  Gr : array[0..3, 0..2] of Double;
  det, vol, m, c, T, gup, Ml, Kl, gmag : Double;
  OnRigid, ClampSurf : TBooleanArray;
  E : array[0..2] of TVec3;
  sp : TSurfaceProps;
  tn : array[0..2] of Integer;
begin
  Assert(Length(FTriSurf) > 0, 'AddToSystem : call FindBoundary first');
  nt := Length(FTets) div 4;
  nb := Length(FTriSurf);

  // moving dofs: nodes of moving triangles
  SetLength(FMovIndex, FNbNodes);
  for i := 0 to FNbNodes - 1 do FMovIndex[i] := -1;
  SetLength(OnRigid, FNbNodes);
  SetLength(ClampSurf, FNbNodes);
  nm := 0;
  SetLength(FMovNode, FNbNodes);
  for k := 0 to nb - 1 do
    for j := 0 to 2 do
    begin
      a := FTri[3 * k + j];
      if Surfaces[FTriSurf[k]].Moving then
      begin
        if FMovIndex[a] < 0 then
        begin
          FMovIndex[a] := nm;
          FMovNode[nm] := a;
          Inc(nm);
        end;
        if Surfaces[FTriSurf[k]].Clamp then ClampSurf[a] := True;
      end
      else
        OnRigid[a] := True;
    end;
  SetLength(FMovNode, nm);
  SetLength(FClamped, nm);
  SetLength(FNodeNormal, nm);
  for i := 0 to nm - 1 do
    FClamped[i] := OnRigid[FMovNode[i]] and ClampSurf[FMovNode[i]];

  FPhiBase := Sys.NewDofs(FNbNodes);
  FEtaBase := Sys.NewDofs(nm);
  FVBase := Sys.NewDofs(nm);
  for i := 0 to FNbNodes - 1 do Sys.SetAlgebraic(FPhiBase + i);

  // K: -K phi in the phi rows
  for k := 0 to nt - 1 do
  begin
    for j := 0 to 3 do n[j] := FTets[4 * k + j];
    for j := 0 to 2 do
    begin
      D[j, 0] := X[n[j + 1]] - X[n[0]];
      D[j, 1] := Y[n[j + 1]] - Y[n[0]];
      D[j, 2] := Z[n[j + 1]] - Z[n[0]];
    end;
    det := D[0, 0] * (D[1, 1] * D[2, 2] - D[1, 2] * D[2, 1])
         - D[0, 1] * (D[1, 0] * D[2, 2] - D[1, 2] * D[2, 0])
         + D[0, 2] * (D[1, 0] * D[2, 1] - D[1, 1] * D[2, 0]);
    vol := Abs(det) / 6;
    // Inv = D^-1 ; gradient of N_{j+1} is column j of D^-1
    Inv[0, 0] := (D[1, 1] * D[2, 2] - D[1, 2] * D[2, 1]) / det;
    Inv[0, 1] := (D[0, 2] * D[2, 1] - D[0, 1] * D[2, 2]) / det;
    Inv[0, 2] := (D[0, 1] * D[1, 2] - D[0, 2] * D[1, 1]) / det;
    Inv[1, 0] := (D[1, 2] * D[2, 0] - D[1, 0] * D[2, 2]) / det;
    Inv[1, 1] := (D[0, 0] * D[2, 2] - D[0, 2] * D[2, 0]) / det;
    Inv[1, 2] := (D[0, 2] * D[1, 0] - D[0, 0] * D[1, 2]) / det;
    Inv[2, 0] := (D[1, 0] * D[2, 1] - D[1, 1] * D[2, 0]) / det;
    Inv[2, 1] := (D[0, 1] * D[2, 0] - D[0, 0] * D[2, 1]) / det;
    Inv[2, 2] := (D[0, 0] * D[1, 1] - D[0, 1] * D[1, 0]) / det;
    for j := 0 to 2 do
    begin
      Gr[j + 1, 0] := Inv[0, j];
      Gr[j + 1, 1] := Inv[1, j];
      Gr[j + 1, 2] := Inv[2, j];
    end;
    for j := 0 to 2 do
      Gr[0, j] := -(Gr[1, j] + Gr[2, j] + Gr[3, j]);
    for i := 0 to 3 do
      for j := 0 to 3 do
        Sys.AddA(FPhiBase + n[i], FPhiBase + n[j],
          -vol * (Gr[i, 0] * Gr[j, 0] + Gr[i, 1] * Gr[j, 1] + Gr[i, 2] * Gr[j, 2]));
  end;

  // eta' = v ; clamped nodes: 0 = -v
  for i := 0 to nm - 1 do
  begin
    Sys.AddE(FEtaBase + i, FEtaBase + i, 1);
    Sys.AddA(FEtaBase + i, FVBase + i, 1);
    if FClamped[i] then
    begin
      Sys.SetAlgebraic(FVBase + i);
      Sys.AddA(FVBase + i, FVBase + i, -1);
    end;
  end;

  gmag := Sqrt(Dot(G, G));
  for k := 0 to nb - 1 do
  begin
    sp := Surfaces[FTriSurf[k]];
    if not sp.Moving then Continue;
    m := sp.Mass; c := sp.Damping; T := sp.Tension;
    gup := -Dot(FTriN[k], G);
    for j := 0 to 2 do tn[j] := FTri[3 * k + j];
    // edge opposite node j
    for j := 0 to 2 do
      E[j] := Sub(Vec3(X[tn[(j + 2) mod 3]], Y[tn[(j + 2) mod 3]], Z[tn[(j + 2) mod 3]]),
                  Vec3(X[tn[(j + 1) mod 3]], Y[tn[(j + 1) mod 3]], Z[tn[(j + 1) mod 3]]));
    for i := 0 to 2 do
    begin
      a := FMovIndex[tn[i]];
      // area-weighted normal for output
      FNodeNormal[a].X := FNodeNormal[a].X + FTriArea[k] * FTriN[k].X;
      FNodeNormal[a].Y := FNodeNormal[a].Y + FTriArea[k] * FTriN[k].Y;
      FNodeNormal[a].Z := FNodeNormal[a].Z + FTriArea[k] * FTriN[k].Z;
      for j := 0 to 2 do
      begin
        b := FMovIndex[tn[j]];
        if i = j then Ml := FTriArea[k] / 6 else Ml := FTriArea[k] / 12;
        Kl := Dot(E[i], E[j]) / (4 * FTriArea[k]);
        // phi rows: + S v
        Sys.AddA(FPhiBase + tn[i], FVBase + b, Ml);
        if FClamped[a] then Continue;
        Sys.AddE(FVBase + a, FVBase + b, m * Ml);
        Sys.AddE(FVBase + a, FPhiBase + tn[j], Rho * Ml);
        Sys.AddA(FVBase + a, FVBase + b, -c * Ml);
        Sys.AddA(FVBase + a, FEtaBase + b, -(T * Kl + Rho * gup * Ml));
        Sys.AddA(FVBase + a, FPhiBase + tn[j], -Rho * Alpha * Ml);
      end;
    end;
  end;
  if gmag = 0 then ; // gravity may be off
end;

function TAbdomenFluid.SurfaceWeights(SurfId : Integer) : TDoubleArray;
var
  k, j : Integer;
begin
  SetLength(Result, NbMoving);
  for k := 0 to Length(FTriSurf) - 1 do
    if FTriSurf[k] = SurfId then
      for j := 0 to 2 do
        Result[FMovIndex[FTri[3 * k + j]]] :=
          Result[FMovIndex[FTri[3 * k + j]]] + FTriArea[k] / 3;
end;

procedure TAbdomenFluid.CouplePressure(Sys : TDescriptorSystem; SurfId, PDof : Integer);
var
  w : TDoubleArray;
  i : Integer;
begin
  w := SurfaceWeights(SurfId);
  for i := 0 to NbMoving - 1 do
    if (w[i] <> 0) and not FClamped[i] then
      Sys.AddA(FVBase + i, PDof, -w[i]);
end;

procedure TAbdomenFluid.AddPressureLoad(var B : TVMobj; SurfId : Integer; const P : TDoubleArray);
var
  k, i, j, a : Integer;
  Ml : Double;
  bp : PDouble;
begin
  bp := B.DataPtr;
  for k := 0 to Length(FTriSurf) - 1 do
    if FTriSurf[k] = SurfId then
      for i := 0 to 2 do
      begin
        a := FMovIndex[FTri[3 * k + i]];
        if FClamped[a] then Continue;
        for j := 0 to 2 do
        begin
          if i = j then Ml := FTriArea[k] / 6 else Ml := FTriArea[k] / 12;
          bp[FVBase + a] := bp[FVBase + a] - Ml * P[FTri[3 * k + j]];
        end;
      end;
end;

function TAbdomenFluid.TotalVolume : Double;
var
  k : Integer;
  D : array[0..2] of TVec3;
  n0 : Integer;
begin
  Result := 0;
  for k := 0 to Length(FTets) div 4 - 1 do
  begin
    n0 := FTets[4 * k];
    D[0] := Vec3(X[FTets[4*k+1]] - X[n0], Y[FTets[4*k+1]] - Y[n0], Z[FTets[4*k+1]] - Z[n0]);
    D[1] := Vec3(X[FTets[4*k+2]] - X[n0], Y[FTets[4*k+2]] - Y[n0], Z[FTets[4*k+2]] - Z[n0]);
    D[2] := Vec3(X[FTets[4*k+3]] - X[n0], Y[FTets[4*k+3]] - Y[n0], Z[FTets[4*k+3]] - Z[n0]);
    Result := Result + Abs(Dot(D[0], Cross(D[1], D[2]))) / 6;
  end;
end;

end.
