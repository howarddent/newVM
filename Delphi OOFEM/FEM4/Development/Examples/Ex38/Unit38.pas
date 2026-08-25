unit Unit38;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, newVMsparse,
  CXS.FEMLAP.Gmsh,
  CXS.FEMLAP.Node,
  CXS.FEMLAP.Element,
  CXS.FEMLAP.Edge_B2V1,
  CXS.FEMLAP.Face_T3V1,
  CXS.FEMLAP.Face_Q4V1,
  CXS.FEMLAP.Brick_T4V1,
  CXS.FEMLAP.Brick_H8V1,
  CXS.FEMLAP.Brick_W6V1,
  CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.EngineData,
  CXS.FEMLAP.ThermalEngine,
  CXS.FEMLAP.Expression,
  ShellAPI,
  StdCtrls, ExtCtrls;

type
  TForm38 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }

    FStart, FElapsed : Double;

    // Gmsh data
    Gmsh : TGmsh;
    // Thermal engine class
    ThermalEngine : TThermalEngine;

  public
    { Public declarations }

    function T(NIndex, EIndex : Integer) : Double;
    function time(NIndex, EIndex : Integer) : Double;

    procedure PostProcess;

  end;

var
  Form38: TForm38;

implementation

{$R *.lfm}

procedure TForm38.Button1Click(Sender: TObject);
var

  ii, jj : Integer;

  SectionArea, Perimeter, Thickness : Double;

  NbNodes : Integer;
  Node : Array[0..7] of Integer;

  MaterialId : Integer;

  EleType : NEleType;

  rho, Cp, k : TExpressionList;

  HeatFlux : TExpressionList;

  T1 : TExpressionList;

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  fi : Integer;

begin

  FStart := GetTickCount;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Thickness := 0.2;
  Perimeter := 2;
  SectionArea := 1;

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\building\building.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  ThermalEngine := TThermalEngine.Create;

  (******************** START PROPERTIES ********************)

  // Density
  rho := TExpressionList.Create;
  rho.AddExpression(20, 115, '2300', 'T');
  rho.AddExpression(115, 200, '2300*(1-0.02*(T-115)/85)', 'T');
  rho.AddExpression(200, 400, '2300*(0.98-0.03*(T-200)/200)', 'T');
  rho.AddExpression(400, 1200, '2300*(0.95-0.07*(T-400)/800)', 'T');

  // Specific heat
  Cp := TExpressionList.Create;
  Cp.AddExpression(20, 20, '897', 'T');
  Cp.AddExpression(100, 100, '897', 'T');
  Cp.AddExpression(102, 102, '2020', 'T');
  Cp.AddExpression(116, 116, '2020', 'T');
  Cp.AddExpression(200, 200, '1006', 'T');
  Cp.AddExpression(400, 400, '1094', 'T');
  Cp.AddExpression(1200, 1200, '1094', 'T');

  // Thermal conductivity heat
  k := TExpressionList.Create;
  k.AddExpression(20, 1200, '20', 'T');

  MaterialId := ThermalEngine.AddMaterial(T, rho, Cp, k);

  (******************** BC METHOD ********************)
  ThermalEngine.PenaltyMethod := False;

  (******************** START NODES ********************)

  ThermalEngine.BeginAddMesh;

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    ThermalEngine.AddNode(Gmsh.CoordX[ii], Gmsh.CoordY[ii], Gmsh.CoordZ[ii]);

  end;

  (******************** START ELEMENTS ********************)

  for ii := 0 to Gmsh.NbElements - 1 do
  begin

    NbNodes := 0;

    EleType := elNone;

    if Gmsh.ElementType[ii] = GMSH_BEAM then begin NbNodes := 2; EleType := elBeam; end
    else if Gmsh.ElementType[ii] = GMSH_TRI then begin NbNodes := 3; EleType := elTri; end
    else if Gmsh.ElementType[ii] = GMSH_QUAD then begin NbNodes := 4; EleType := elQuad; end
    else if Gmsh.ElementType[ii] = GMSH_TETRA then begin NbNodes := 4; EleType := elTetra; end
    else if Gmsh.ElementType[ii] = GMSH_HEXA then begin NbNodes := 8; EleType := elHexa; end
    else if Gmsh.ElementType[ii] = GMSH_PRISM then begin NbNodes := 6; EleType := elPrism; end;

    for jj := 0 to NbNodes-1 do
    begin
      Node[jj] := Gmsh.ElementNode[ii, jj];
    end;

    ThermalEngine.AddElement(Node, NbNodes, EleType, MaterialId, SectionArea, Perimeter, Thickness);

  end;

  ThermalEngine.EndAddMesh;

  (******************** START TEMPERATURE RESTRAINTS ********************)

  ThermalEngine.BeginSetRestraints;

  T1 := TExpressionList.Create;
  T1.AddExpression(-1000, +1000, '20', 't');

  for ii := 0 to ThermalEngine.NbNodes - 1 do
  begin

    if (Abs(ThermalEngine.CoordZ[ii] - 0.0) < 1E-6) then
      ThermalEngine.SetNodeRestraint(ii, time, T1);

  end;

  //ThermalEngine.SetNodeTemperatureRestraint(0, 20);

  ThermalEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  ThermalEngine.SetInitialTemperature(20);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  HeatFlux := TExpressionList.Create;
  HeatFlux.AddExpression(20, 1200, '100', 't');

  // The original hardcoded node index here was 1748 - out of range for
  // building.msh, which only has 264 nodes (0..263), so this always
  // crashed (confirmed against the Delphi source's own __history: 1748
  // was already there, so this predates the port and its true original
  // intent is unrecoverable). Substituted node 10 (0-based; raw .msh id
  // 11), the mesh's highest point at Z=1440 - distinct from the Z=0 base
  // nodes already pinned to a fixed temperature by the restraint loop
  // above, and a physically reasonable spot for a standalone heat source.
  ThermalEngine.AddNodeSource(10, time, HeatFlux);

  (******************** START TIME CONTROL ********************)
  ThermalEngine.TimeInterval := 360000;  // 10
  ThermalEngine.NbSteps := 20;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  ThermalEngine.SetEndPostIterationFunction(PostProcess);

  ThermalEngine.Tolerance := 1E-5;
  ThermalEngine.CalcTemperature(caStatic, True);

  (******************** START POST-PROCESSING ********************)

  if ThermalEngine.NbSteps = 0 then
    PostProcess;

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'building_???.pos' argument reaches
  // gmsh.exe unexpanded, matches no real file, and gmsh opens with an
  // empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded building_NNN.pos sequence combines in the correct
  // order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\building_???.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count > 0 then
    begin

      FileList := '';
      for fi := 0 to Files.Count - 1 do
        FileList := FileList + '..\Data\' + Files[fi] + ' ';

      ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', PChar(FileList + '-combine -noview'), nil, SW_SHOWNORMAL) ;

    end
    else
    begin
      ShowMessage('No building_???.pos result files found in ..\Data - run Calculate first.');
    end;

  finally
    Files.Free;
  end;

  T1.Free;

  ThermalEngine.Free;

  rho.Free;
  Cp.Free;
  k.Free;

  Gmsh.Free;

end;

procedure TForm38.PostProcess;
var

  i : Integer;

  // Output data
  v : TDoubleArray;

begin

  FElapsed := GetTickCount - FStart;

  Caption := IntToStr(ThermalEngine.Step) + ' : ' + FloatToStr(FElapsed);

  Application.ProcessMessages;

  //if (ThermalEngine.Step = ThermalEngine.NbSteps) or (ThermalEngine.TimeInterval = 0) then
  begin

    SetLength(v, ThermalEngine.NbNodes);

    for i := 0 to ThermalEngine.NbNodes - 1 do
    begin

      v[i] := ThermalEngine.Temperature[i];
      //v[i] := ThermalEngine.RHS[i];

    end;

    Gmsh.OpenFile('..\Data\building_' + Format('%.3d', [ThermalEngine.Step]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  FStart := GetTickCount;

end;

function TForm38.T(NIndex, EIndex: Integer): Double;
var
  j : Integer;
begin

  Result := 0;

  for j := 0 to ThermalEngine.Element[EIndex].NbNodes - 1 do
  begin

    Result := Result + ThermalEngine.Temperature[ThermalEngine.Element[EIndex].NodeId[j]];

  end;

  if ThermalEngine.Element[EIndex].NbNodes > 0 then
    Result := Result / ThermalEngine.Element[EIndex].NbNodes;

end;

function TForm38.time(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.Time;

end;

end.
