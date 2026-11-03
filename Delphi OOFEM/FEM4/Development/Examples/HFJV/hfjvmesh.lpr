program hfjvmesh;

{ Builds the torso abdomen's mesh (uTorsoAbdomen) and reports on it:
  the cavity's volume, each surface's area, the diaphragm's mean height
  against Defibrillation's flat one, and its landmarks. Writes
  mesh/<tag>_surfaces.vtk, the boundary triangles coloured by surface,
  for ParaView.

  Options: --height=<m> (1.75), --weight=<kg> (70), --size=<mm> (12).

  Build: fpc -O2 @../path list, see hfjvrun.lpr }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, cblas, newVM, newVMsparse, uAbdomenFluid, uTorsoAbdomen;

function Opt(const Name : String; Def : Double) : Double;
var
  i : Integer;
begin
  Result := Def;
  for i := 1 to ParamCount do
    if Pos('--' + Name + '=', ParamStr(i)) = 1 then
      Result := StrToFloat(Copy(ParamStr(i), Length(Name) + 4, MaxInt));
end;

var
  Ab : TTorsoAbdomen;
  F : TAbdomenFluid;
  X, Y, Z : TDoubleArray;
  Tets : TIntegerArray;
  Area : array[0..2] of Double;
  ZA : array[0..2] of Double;
  k, s, a, b, c : Integer;
  ar, zc : Double;
  Vf : TextFile;
  tri : TIntegerArray;
  Fn : String;
begin
  FormatSettings.DecimalSeparator := '.';
  InitializeCBLAS;
  Ab := TTorsoAbdomen.Create(Opt('height', 1.75), Opt('weight', 70));
  F := TAbdomenFluid.Create;
  try
    Ab.MeshSize := Opt('size', 12) / 1000;
    Ab.BuildMesh(X, Y, Z, Tets);
    F.SetMesh(X, Y, Z, Tets);
    F.FindBoundary(Ab.Classify);
    WriteLn(Format('Body: %.2f m, %.0f kg; abdomen section %.0f x %.0f mm outside, cavity %.0f x %.0f mm',
      [Ab.Body.Height, Ab.Body.Weight, 2000 * Ab.Body.A, 2000 * Ab.Body.B, 2000 * Ab.CavA, 2000 * Ab.CavB]));
    WriteLn(Format('Landmarks (mm above the perineum): pelvic floor %.0f, pubis %.0f, brim %.0f, iliac crest %.0f',
      [1000 * Ab.ZFloor, 1000 * Ab.ZPubis, 1000 * Ab.ZBrim, 1000 * Ab.ZCrest]));
    WriteLn(Format('  costal margin: front (xiphoid) %.0f, side (rib 10) %.0f, back (rib 12) %.0f',
      [1000 * Ab.CostalZ(Pi / 2), 1000 * Ab.CostalZ(0), 1000 * Ab.CostalZ(-Pi / 2)]));
    WriteLn(Format('  diaphragm: insertion %.0f / %.0f / %.0f, apex %.0f; Defibrillation''s flat diaphragm %.0f',
      [1000 * Ab.RimZ(Pi / 2), 1000 * Ab.RimZ(0), 1000 * Ab.RimZ(-Pi / 2), 1000 * Ab.ZTop,
       1000 * (Ab.Body.Len - Ab.Body.ThoraxLen)]));
    WriteLn(Format('Mesh: %d nodes, %d tetrahedra, %d boundary triangles; cavity %.2f L',
      [F.NbNodes, Length(Tets) div 4, Length(F.TriSurf), 1000 * F.TotalVolume]));
    tri := F.TriNodes;
    for s := 0 to 2 do begin Area[s] := 0; ZA[s] := 0; end;
    for k := 0 to High(F.TriSurf) do
    begin
      a := tri[3 * k]; b := tri[3 * k + 1]; c := tri[3 * k + 2];
      ar := 0.5 * Sqrt(Sqr((Y[b] - Y[a]) * (Z[c] - Z[a]) - (Z[b] - Z[a]) * (Y[c] - Y[a])) +
                       Sqr((Z[b] - Z[a]) * (X[c] - X[a]) - (X[b] - X[a]) * (Z[c] - Z[a])) +
                       Sqr((X[b] - X[a]) * (Y[c] - Y[a]) - (Y[b] - Y[a]) * (X[c] - X[a])));
      zc := (Z[a] + Z[b] + Z[c]) / 3;
      s := F.TriSurf[k];
      Area[s] := Area[s] + ar;
      ZA[s] := ZA[s] + ar * zc;
    end;
    WriteLn(Format('Surfaces: rigid %.0f cm2, anterior wall %.0f cm2, diaphragm %.0f cm2 (mean height %.0f mm)',
      [1e4 * Area[0], 1e4 * Area[1], 1e4 * Area[2], 1000 * ZA[2] / Area[2]]));

    Fn := Ab.MeshDir + 'abdomen_surfaces.vtk';
    AssignFile(Vf, Fn);
    ReWrite(Vf);
    WriteLn(Vf, '# vtk DataFile Version 3.0');
    WriteLn(Vf, 'HFJV abdomen surfaces');
    WriteLn(Vf, 'ASCII');
    WriteLn(Vf, 'DATASET POLYDATA');
    WriteLn(Vf, 'POINTS ', F.NbNodes, ' double');
    for k := 0 to F.NbNodes - 1 do
      WriteLn(Vf, X[k]:0:6, ' ', Y[k]:0:6, ' ', Z[k]:0:6);
    WriteLn(Vf, 'POLYGONS ', Length(F.TriSurf), ' ', 4 * Length(F.TriSurf));
    for k := 0 to High(F.TriSurf) do
      WriteLn(Vf, '3 ', tri[3 * k], ' ', tri[3 * k + 1], ' ', tri[3 * k + 2]);
    WriteLn(Vf, 'CELL_DATA ', Length(F.TriSurf));
    WriteLn(Vf, 'SCALARS surface int 1');
    WriteLn(Vf, 'LOOKUP_TABLE default');
    for k := 0 to High(F.TriSurf) do
      WriteLn(Vf, F.TriSurf[k]);
    CloseFile(Vf);
    WriteLn('Wrote ', Fn);
  finally
    F.Free; Ab.Free;
  end;
end.
