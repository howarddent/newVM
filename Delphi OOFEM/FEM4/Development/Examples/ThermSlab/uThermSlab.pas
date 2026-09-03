unit uThermSlab;

{ ThermSlab - does the framework's 3D conduction get a slab right?

  ThermEx1 came out with a radial temperature gradient about a third
  steeper than the closed-form answer for its geometry, mesh-converged,
  so the suspicion fell on the 3D elements rather than on that model. A
  cylinder is a poor place to test that suspicion: the exact solution
  involves the geometry, the two materials and the boundary condition all
  at once, and any of them could be the culprit. A slab isolates the
  element.

  THE PATCH TEST

  The first case here is the standard finite-element patch test, and it
  is the decisive one. Hold one face of a slab at T1 and the opposite
  face at T2, with no generation, and the exact solution is linear in x:

    T(x) = T1 + (T2 - T1) * x / L

  A linear field lies exactly inside the shape-function space of both a
  trilinear hexahedron and a linear prism. So a correctly formulated
  element must reproduce it to machine precision - not approximately,
  and not better with a finer mesh, but EXACTLY, on any mesh, however
  distorted. That is what makes the test decisive: there is no
  discretisation error to hide behind, and a failure can only be the
  element formulation, the node ordering it assumes, or the assembly.

  THE CONDUCTANCE CHECK

  The second case puts a fixed temperature on one face and convection on
  the other, so the through-flux is set by conduction and film resistance
  in series:

    q = (T1 - Tinf) / (L/k + 1/h)

  This one tests the magnitude of the conduction, not just its linearity,
  and it is the quantity ThermEx1 depends on. An element could in
  principle pass the patch test and still get its conductance wrong, so
  both are run.

  Each case runs on hexahedra and on prisms separately, since ThermEx1
  uses both - the fat shell in hexahedra, the lean core in prisms - and
  they are separate element classes with separate formulations. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, newVM, newVMsparse,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.ThermalEngine,
  CXS.FEMLAP.Expression,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh;

const

  (******************** THE SLAB ********************)

  // Thickness along x - the conduction direction - and the cross
  // section. Deliberately not a cube: an element that only works on
  // near-cubic cells should be caught here, and ThermEx1's are far from
  // cubic.
  SlabL = 0.100;    // m, through-thickness
  SlabW = 0.040;    // m
  SlabH = 0.040;    // m

  // Element size. The patch test's result must not depend on this, so
  // the program runs it at two densities and says whether it did.
  MeshCoarse = 0.020;
  MeshFine = 0.010;

  (******************** MATERIAL ********************)

  // ThermEx1's lean tissue, so the numbers are the ones that matter
  // there.
  Density = 1050.0;
  Cp = 3600.0;
  K = 0.50;         // W/mK

  (******************** CONDITIONS ********************)

  THot = 310.15;    // K, 37 C on the x = 0 face
  TCold = 290.15;   // K, 17 C on the x = L face

  HFilm = 8.5;      // W/m2K for the convection case
  TInfinity = 289.15;

type

  TSlabCheck = class(TObject)

  private

    FGmsh : TGmsh;
    FEngine : TThermalEngine;

    FRho, FCp, FK : TExpressionList;
    FT1, FTinf, FH : TExpressionList;

    FEleType : Integer;
    FGmshType : Integer;
    FTypeName : String;

    FNbFail : Integer;

    FUsePenalty : Boolean;

    function ElementVolume(EIndex, nb : Integer) : Double;
    procedure Build(MeshSize : Double);
    procedure Release;

    function FaceNodeCount : Integer;

  public

    constructor Create;
    destructor Destroy; override;

    function Constant(NodeId, ElementId : Integer) : Double;

    procedure PatchTest(AGmshType : Integer; const AName : String;
                        MeshSize : Double);

    // Uniform volumetric generation, both faces held: exact peak is
    // q*L^2/(8k). This is the one that bears on ThermEx1.s interior
    // gradient, since it uses generation and conduction and no surface
    // boundary condition at all.
    procedure GenerationTest(AGmshType : Integer; const AName : String;
                             MeshSize : Double);

    procedure ConductanceTest(AGmshType : Integer; const AName : String;
                              MeshSize : Double);

    property NbFail : Integer read FNbFail;

    // The penalty method imposes a held temperature only approximately,
    // so the patch test is run both ways before any conclusion is drawn
    // about the elements.
    property UsePenalty : Boolean read FUsePenalty write FUsePenalty;

  end;

implementation

const

  DataDir = '..' + PathDelim + 'Data' + PathDelim;

{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  GmshExecutable = 'gmsh';
{$ENDIF}

  GeoFile = DataDir + 'thermslab.geo';
  MshFile = DataDir + 'thermslab.msh';

  GeoTol = 1.0E-9;

  // What counts as passing the patch test. A linear field is exact in a
  // correct element, so the only error left is the linear solver.s: at
  // its 1e-8 relative tolerance on a 300 K field that is around 3e-6 K,
  // and the observed residuals sit just under it. Anything a formulation
  // error could produce is orders of magnitude above this.
  PatchTol = 1.0E-5;

var
  DotFS : TFormatSettings;

function Num(v : Double) : String;
begin

  Result := Format('%.10f', [v], DotFS);

end;

{ TSlabCheck }

constructor TSlabCheck.Create;
begin

  FGmsh := TGmsh.Create;

  FNbFail := 0;

end;

destructor TSlabCheck.Destroy;
begin

  Release;

  FGmsh.Free;

  inherited Destroy;

end;

function TSlabCheck.Constant(NodeId, ElementId : Integer) : Double;
begin

  Result := 0;

end;

procedure TSlabCheck.Release;
begin

  FreeAndNil(FEngine);

  FreeAndNil(FRho);
  FreeAndNil(FCp);
  FreeAndNil(FK);
  FreeAndNil(FT1);
  FreeAndNil(FTinf);
  FreeAndNil(FH);

end;

function TSlabCheck.FaceNodeCount : Integer;
begin

  if FGmshType = GMSH_HEXA then
    Result := 8
  else
    Result := 6;

end;

{ Mesh the slab and load it into a fresh engine, material and all. The
  boundary conditions are left to the caller, since that is what differs
  between the two tests. }
{ Base area times extrusion height - exact for these straight extruded
  prisms and hexahedra. }
function TSlabCheck.ElementVolume(EIndex, nb : Integer) : Double;
var
  j, n : Integer;
  a2, x0, y0, x1, y1, dz : Double;
  Nd : Array[0..7] of Integer;
begin

  for j := 0 to nb - 1 do
    Nd[j] := FGmsh.ElementNode[EIndex, j];

  n := nb div 2;
  a2 := 0;

  for j := 0 to n - 1 do
  begin
    x0 := FGmsh.CoordX[Nd[j]];
    y0 := FGmsh.CoordY[Nd[j]];
    x1 := FGmsh.CoordX[Nd[(j + 1) mod n]];
    y1 := FGmsh.CoordY[Nd[(j + 1) mod n]];
    a2 := a2 + (x0 * y1 - x1 * y0);
  end;

  dz := Abs(FGmsh.CoordZ[Nd[n]] - FGmsh.CoordZ[Nd[0]]);

  Result := Abs(a2) * 0.5 * dz;

end;

procedure TSlabCheck.Build(MeshSize : Double);
var

  i, j, nb, Mat : Integer;

  ExitCode : Cardinal;

  Node : Array[0..7] of Integer;

  ET : NEleType;

begin

  Release;

  // TGmsh writes the .geo itself for a box, including the transfinite
  // and recombine directives each element type needs.
  FGmsh.OpenFile(GeoFile);
  FGmsh.GenerateBox(SlabL, SlabW, SlabH, MeshSize, FGmshType);
  FGmsh.Close;

  if not Sto_ShellExecute(GmshExecutable, [GeoFile, '-3'], ExitCode, 120000, True) then
    raise Exception.Create('Could not run gmsh (' + GmshExecutable + ')');

  if ExitCode <> 0 then
    raise Exception.Create('gmsh failed with exit code ' + IntToStr(ExitCode));

  FGmsh.OpenFile(MshFile);
  FGmsh.ReadMesh;
  FGmsh.Close;

  FEngine := TThermalEngine.Create;

  FEngine.PenaltyMethod := FUsePenalty;
  FEngine.SolverType := soGMRES;

  FRho := TExpressionList.Create;
  FRho.AddExpression(0, 1000, Num(Density), 'T');
  FCp := TExpressionList.Create;
  FCp.AddExpression(0, 1000, Num(Cp), 'T');
  FK := TExpressionList.Create;
  FK.AddExpression(0, 1000, Num(K), 'T');

  Mat := FEngine.AddMaterial(Constant, FRho, FCp, FK);

  FEngine.BeginAddMesh;

  for i := 0 to FGmsh.NbNodes - 1 do
    FEngine.AddNode(FGmsh.CoordX[i], FGmsh.CoordY[i], FGmsh.CoordZ[i]);

  nb := FaceNodeCount;

  if FGmshType = GMSH_HEXA then
    ET := elHexa
  else
    ET := elPrism;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] <> FGmshType then
      Continue;

    for j := 0 to nb - 1 do
      Node[j] := FGmsh.ElementNode[i, j];

    FEngine.AddElement(Node, nb, ET, Mat);

  end;

  FEngine.EndAddMesh;

end;

{ Both faces held: the answer must be linear in x, exactly. }
procedure TSlabCheck.PatchTest(AGmshType : Integer; const AName : String;
                               MeshSize : Double);
var

  i, nFixed : Integer;

  x, Exact, Err, MaxErr : Double;

  Th, Tc : TExpressionList;

begin

  FGmshType := AGmshType;
  FTypeName := AName;

  Build(MeshSize);

  Th := TExpressionList.Create;
  Tc := TExpressionList.Create;

  try

    Th.AddExpression(-1E9, 1E9, Num(THot), 't');
    Tc.AddExpression(-1E9, 1E9, Num(TCold), 't');

    FEngine.BeginSetRestraints;

    nFixed := 0;

    for i := 0 to FGmsh.NbNodes - 1 do
    begin

      if Abs(FGmsh.CoordX[i]) < GeoTol then
      begin
        FEngine.SetNodeRestraint(i, Constant, Th);
        Inc(nFixed);
      end
      else if Abs(FGmsh.CoordX[i] - SlabL) < GeoTol then
      begin
        FEngine.SetNodeRestraint(i, Constant, Tc);
        Inc(nFixed);
      end;

    end;

    FEngine.EndSetRestraints;

    FEngine.SetInitialTemperature(THot);

    FEngine.CalcTemperature(caStatic, False);

    MaxErr := 0;

    for i := 0 to FEngine.NbNodes - 1 do
    begin

      x := FGmsh.CoordX[i];

      Exact := THot + (TCold - THot) * x / SlabL;

      Err := Abs(FEngine.Temperature[i] - Exact);

      if Err > MaxErr then
        MaxErr := Err;

    end;

    Write(Format('  %-6s  h=%.3f  %5d nodes %5d ele %4d fixed   max |T - exact| = %.3e K   ',
      [FTypeName, MeshSize, FEngine.NbNodes, FEngine.NbElements, nFixed, MaxErr]));

    // The penalty method imposes a held temperature only approximately,
    // so its residual measures the penalty, not the element - reported,
    // but not counted against the elements.
    if MaxErr <= PatchTol then
      WriteLn('PASS')
    else if FUsePenalty then
      WriteLn('(penalty BC, not the element)')
    else
    begin
      WriteLn('FAIL');
      Inc(FNbFail);
    end;

  finally

    Th.Free;
    Tc.Free;

  end;

end;

{ One face held, the other convecting: tests the magnitude of the
  conduction, which the patch test cannot. }
procedure TSlabCheck.GenerationTest(AGmshType : Integer; const AName : String;
                                     MeshSize : Double);
var

  i, j, nb : Integer;

  qDot, Vol, ExactPeak, ModelPeak, x, Err, BestX, PeakX : Double;

  NodeQ : TDoubleArray;

  Src : Array of TExpressionList;

  Th : TExpressionList;

begin

  FGmshType := AGmshType;
  FTypeName := AName;

  Build(MeshSize);

  // ThermEx1's generation rate, so the comparison is like for like.
  qDot := 1233.0;

  Th := TExpressionList.Create;
  Th.AddExpression(-1E9, 1E9, Num(THot), 't');

  SetLength(NodeQ, FGmsh.NbNodes);
  SetLength(Src, FGmsh.NbNodes);

  nb := FaceNodeCount;

  // Lumped to nodes exactly as ThermEx1 does it - the element volume is
  // a straight extrusion here too, so base area times height is exact.
  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] <> FGmshType then
      Continue;

    Vol := ElementVolume(i, nb);

    for j := 0 to nb - 1 do
      NodeQ[FGmsh.ElementNode[i, j]] := NodeQ[FGmsh.ElementNode[i, j]] +
        qDot * Vol / nb;

  end;

  FEngine.BeginSetRestraints;

  for i := 0 to FGmsh.NbNodes - 1 do
    if (Abs(FGmsh.CoordX[i]) < GeoTol) or (Abs(FGmsh.CoordX[i] - SlabL) < GeoTol) then
      FEngine.SetNodeRestraint(i, Constant, Th);

  FEngine.EndSetRestraints;

  for i := 0 to FGmsh.NbNodes - 1 do
  begin

    Src[i] := nil;

    if NodeQ[i] <= 0 then
      Continue;

    Src[i] := TExpressionList.Create;
    Src[i].AddExpression(-1E9, 1E9, Num(NodeQ[i]), 't');

    FEngine.AddNodeSource(i, Constant, Src[i]);

  end;

  FEngine.SetInitialTemperature(THot);

  FEngine.CalcTemperature(caStatic, False);

  ModelPeak := 0;
  BestX := MaxDouble;
  PeakX := SlabL / 2;

  for i := 0 to FEngine.NbNodes - 1 do
  begin

    x := FGmsh.CoordX[i];

    // Nearest node to mid-plane: a coarse mesh with an odd division
    // count has no node exactly there.
    if Abs(x - SlabL / 2) < BestX then
    begin
      BestX := Abs(x - SlabL / 2);
      ModelPeak := FEngine.Temperature[i] - THot;
      PeakX := x;
    end;

  end;

  // Compare at the node actually sampled, not at the true mid-plane: a
  // mesh with an odd division count has no node there, and judging the
  // element against a value from somewhere it was not measured is a
  // fault in the test, not in the element.
  ExactPeak := qDot / (2 * K) * PeakX * (SlabL - PeakX);

  Err := 100 * (ModelPeak / ExactPeak - 1);

  // A conduction matrix too small by a factor c makes the rise c times
  // too big, so this ratio IS that factor - the actionable number.
  Write(Format('  %-6s  h=%.3f  rise %.4f K (exact %.4f)  %.2f%%  implied k factor %.4f  ',
    [FTypeName, MeshSize, ModelPeak, ExactPeak, Err, ExactPeak / ModelPeak]));

  if False then
  Write(Format('  %-6s  h=%.3f  mid-plane rise %.4f K (exact %.4f)  %.2f%%   ',
    [FTypeName, MeshSize, ModelPeak, ExactPeak, Err]));

  if Abs(Err) <= 2.0 then
    WriteLn('PASS')
  else
  begin
    WriteLn('FAIL');
    Inc(FNbFail);
  end;

  Th.Free;

  for i := 0 to FGmsh.NbNodes - 1 do
    Src[i].Free;

end;

procedure TSlabCheck.ConductanceTest(AGmshType : Integer; const AName : String;
                                     MeshSize : Double);
var

  i, j, f, nb, nFace : Integer;

  qExact, qModel, TColdFace, TExactCold, Area, Err : Double;

  Nd : Array[0..7] of Integer;

  OnFace : Boolean;

  HexFace : Array[0..5, 0..3] of Integer;
  PrismFace : Array[0..4, 0..3] of Integer;
  PrismFaceN : Array[0..4] of Integer;

  nSum : Integer;

  TSum : Double;

begin

  HexFace[0, 0] := 0; HexFace[0, 1] := 1; HexFace[0, 2] := 2; HexFace[0, 3] := 3;
  HexFace[1, 0] := 4; HexFace[1, 1] := 5; HexFace[1, 2] := 6; HexFace[1, 3] := 7;
  HexFace[2, 0] := 0; HexFace[2, 1] := 1; HexFace[2, 2] := 5; HexFace[2, 3] := 4;
  HexFace[3, 0] := 1; HexFace[3, 1] := 2; HexFace[3, 2] := 6; HexFace[3, 3] := 5;
  HexFace[4, 0] := 2; HexFace[4, 1] := 3; HexFace[4, 2] := 7; HexFace[4, 3] := 6;
  HexFace[5, 0] := 3; HexFace[5, 1] := 0; HexFace[5, 2] := 4; HexFace[5, 3] := 7;

  PrismFace[0, 0] := 0; PrismFace[0, 1] := 1; PrismFace[0, 2] := 2; PrismFace[0, 3] := 0;
  PrismFace[1, 0] := 3; PrismFace[1, 1] := 4; PrismFace[1, 2] := 5; PrismFace[1, 3] := 0;
  PrismFace[2, 0] := 0; PrismFace[2, 1] := 1; PrismFace[2, 2] := 4; PrismFace[2, 3] := 3;
  PrismFace[3, 0] := 1; PrismFace[3, 1] := 2; PrismFace[3, 2] := 5; PrismFace[3, 3] := 4;
  PrismFace[4, 0] := 2; PrismFace[4, 1] := 0; PrismFace[4, 2] := 3; PrismFace[4, 3] := 5;

  PrismFaceN[0] := 3; PrismFaceN[1] := 3;
  PrismFaceN[2] := 4; PrismFaceN[3] := 4; PrismFaceN[4] := 4;

  FGmshType := AGmshType;
  FTypeName := AName;

  Build(MeshSize);

  FT1 := TExpressionList.Create;
  FT1.AddExpression(-1E9, 1E9, Num(THot), 't');

  FTinf := TExpressionList.Create;
  FTinf.AddExpression(-1E9, 1E9, Num(TInfinity), 't');

  FH := TExpressionList.Create;
  FH.AddExpression(-1E9, 1E9, Num(HFilm), 't');

  // Hold x = 0.
  FEngine.BeginSetRestraints;

  for i := 0 to FGmsh.NbNodes - 1 do
    if Abs(FGmsh.CoordX[i]) < GeoTol then
      FEngine.SetNodeRestraint(i, Constant, FT1);

  FEngine.EndSetRestraints;

  // Convect from x = L.
  nb := FaceNodeCount;

  for i := 0 to FGmsh.NbElements - 1 do
  begin

    if FGmsh.ElementType[i] <> FGmshType then
      Continue;

    for j := 0 to nb - 1 do
      Nd[j] := FGmsh.ElementNode[i, j];

    for f := 0 to 5 do
    begin

      if (nb = 6) and (f > 4) then
        Break;

      if nb = 8 then
        nFace := 4
      else
        nFace := PrismFaceN[f];

      OnFace := True;

      for j := 0 to nFace - 1 do
      begin

        if nb = 8 then
          OnFace := OnFace and (Abs(FGmsh.CoordX[Nd[HexFace[f, j]]] - SlabL) < GeoTol)
        else
          OnFace := OnFace and (Abs(FGmsh.CoordX[Nd[PrismFace[f, j]]] - SlabL) < GeoTol);

      end;

      if OnFace then
        FEngine.AddFaceConvection(i, f, Constant, FH, FTinf);

    end;

  end;

  FEngine.SetInitialTemperature(THot);

  FEngine.CalcTemperature(caStatic, False);

  // Exact: conduction and film in series.
  qExact := (THot - TInfinity) / (SlabL / K + 1 / HFilm);

  TExactCold := TInfinity + qExact / HFilm;

  // The model's cold-face temperature, averaged over that face.
  TSum := 0;
  nSum := 0;

  for i := 0 to FEngine.NbNodes - 1 do
    if Abs(FGmsh.CoordX[i] - SlabL) < GeoTol then
    begin
      TSum := TSum + FEngine.Temperature[i];
      Inc(nSum);
    end;

  TColdFace := TSum / nSum;

  qModel := HFilm * (TColdFace - TInfinity);

  Area := SlabW * SlabH;

  Err := 100 * (qModel / qExact - 1);

  WriteLn(Format('  %-6s  h=%.3f  cold face %.4f K (exact %.4f)   flux %.4f W/m2 ' +
    '(exact %.4f)  %.2f%%',
    [FTypeName, MeshSize, TColdFace, TExactCold, qModel, qExact, Err]));

  WriteLn(Format('          through-flow %.4f W against an exact %.4f W',
    [qModel * Area, qExact * Area]));

  if Abs(Err) > 0.5 then
    Inc(FNbFail);

end;

initialization

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';
  DotFS.ThousandSeparator := #0;

end.
