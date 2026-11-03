unit uAbdomenBox;

{ A box-shaped abdomen, supine, for the HFJV model until the torso mesh
  from gmsh exists, and the tank of the checks.

  x runs cranio-caudal, from the diaphragm (x = 0) to the pelvis
  (x = L); y across; z up from the back (z = 0) to the anterior wall
  (z = H), gravity along -z. Surface ids:

      0  rigid: back, flanks, pelvis - waves reflect here
      1  anterior abdominal wall (top)
      2  diaphragm (x = 0), when DiaphragmEnd

  The default adult box is 0.30 x 0.26 x 0.14 m, 10.9 L, the size of
  ThermEx1's trunk core below the chest: its ellipse of 0.30 x 0.15 m
  over 0.30 m is 10.6 L. Meshed in cubes split into six tetrahedra
  (Kuhn's split, conforming between cubes). }

{$mode delphi}{$H+}

interface

uses SysUtils, Math, newVMsparse, uAbdomenFluid;

const
  SurfRigid = 0;
  SurfWall = 1;
  SurfDiaphragm = 2;

type
  TAbdomenBox = class
  public
    L, W, H : Double;
    DiaphragmEnd : Boolean;
    function Classify(const C, N : TVec3) : Integer;
  end;

procedure BuildBox(nx, ny, nz : Integer; L, W, H : Double;
  out X, Y, Z : TDoubleArray; out Tets : TIntegerArray);

implementation

function TAbdomenBox.Classify(const C, N : TVec3) : Integer;
begin
  if N.Z > 0.9 then Result := SurfWall
  else if DiaphragmEnd and (N.X < -0.9) then Result := SurfDiaphragm
  else Result := SurfRigid;
end;

procedure BuildBox(nx, ny, nz : Integer; L, W, H : Double;
  out X, Y, Z : TDoubleArray; out Tets : TIntegerArray);
const
  perms : array[0..5, 0..2] of Integer =
    ((1, 2, 4), (1, 4, 2), (2, 1, 4), (2, 4, 1), (4, 1, 2), (4, 2, 1));
var
  i, j, k, p, b, t : Integer;
  v : array[0..7] of Integer;

  function Id(ii, jj, kk : Integer) : Integer;
  begin
    Result := ii + (nx + 1) * (jj + (ny + 1) * kk);
  end;

begin
  SetLength(X, (nx + 1) * (ny + 1) * (nz + 1));
  SetLength(Y, Length(X)); SetLength(Z, Length(X));
  for k := 0 to nz do
    for j := 0 to ny do
      for i := 0 to nx do
      begin
        X[Id(i, j, k)] := L * i / nx;
        Y[Id(i, j, k)] := W * j / ny;
        Z[Id(i, j, k)] := H * k / nz;
      end;
  SetLength(Tets, 24 * nx * ny * nz);
  t := 0;
  for k := 0 to nz - 1 do
    for j := 0 to ny - 1 do
      for i := 0 to nx - 1 do
      begin
        for b := 0 to 7 do
          v[b] := Id(i + (b and 1), j + ((b shr 1) and 1), k + ((b shr 2) and 1));
        for p := 0 to 5 do
        begin
          Tets[t] := v[0];
          Tets[t + 1] := v[perms[p, 0]];
          Tets[t + 2] := v[perms[p, 0] + perms[p, 1]];
          Tets[t + 3] := v[7];
          Inc(t, 4);
        end;
      end;
end;

end.
