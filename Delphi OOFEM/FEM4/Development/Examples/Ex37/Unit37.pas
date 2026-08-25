unit Unit37;

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
  TForm37 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private

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
  Form37: TForm37;

implementation

{$R *.lfm}

procedure TForm37.Button1Click(Sender: TObject);
var

  ii, jj : Integer;

  MeshSize : Double;

  dx, dy, dz : Double;

  SectionArea, Perimeter, Thickness : Double;

  ExitCode: DWORD;

  NbNodes : Integer;
  Node : Array[0..7] of Integer;

  MaterialId : Integer;

  EleType : NEleType;

  rho, Cp, k : TExpressionList;

  time1, time2 : TExpressionList;

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  fi : Integer;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := 0.003;

  dx := 1;
  dy := 0.1;
  dz := 0.1;
  Thickness := 1;

  Perimeter := 2 * Thickness + 2 * dy;
  SectionArea := Thickness * dy;

  Gmsh.OpenFile('..\Data\thermalengine.geo');
  //Gmsh.GenerateLine(dx, MeshSize, GMSH_BEAM);
  //Gmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_TRI);
  //Gmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_QUAD);
  //Gmsh.GenerateBox(dx, dy, dz, MeshSize, GMSH_TETRA);
  Gmsh.GenerateBox(dx, dy, dz, MeshSize, GMSH_HEXA);
  //Gmsh.GenerateBox(, dx, dy, dz, MeshSize, GMSH_PRISM);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\thermalengine.geo -3 -optimize', ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\thermalengine.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  ThermalEngine := TThermalEngine.Create;

  (******************** START PROPERTIES ********************)

  // Density
  rho := TExpressionList.Create;
  rho.AddExpression(-1000, +1000, '1', 'T');

  // Specific heat
  Cp := TExpressionList.Create;
  Cp.AddExpression(-1000, +1000, '1', 'T');

  // Thermal conductivity heat
  k := TExpressionList.Create;
  k.AddExpression(-1000, +1000, '1', 'T');

  MaterialId := ThermalEngine.AddMaterial(T, rho, Cp, k);

  (******************** BC METHOD ********************)
  ThermalEngine.PenaltyMethod := True;

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

  time1 := TExpressionList.Create;
  time1.AddExpression(-1000, +1000, '1', 't');

  time2 := TExpressionList.Create;
  time2.AddExpression(-1000, +1000, '0', 't');

  for ii := 0 to ThermalEngine.NbNodes - 1 do
  begin

    if (Abs(ThermalEngine.CoordX[ii] - 0.0) < 1E-6) then
      ThermalEngine.SetNodeRestraint(ii, time, time1);

    if (Abs(ThermalEngine.CoordX[ii] - dx) < 1E-6) then
      ThermalEngine.SetNodeRestraint(ii, time, time2);

  end;

  ThermalEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  ThermalEngine.SetInitialTemperature(0);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  (******************** START TIME CONTROL ********************)
  ThermalEngine.TimeInterval := 0.01;  // 10
  ThermalEngine.NbSteps := 20;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  ThermalEngine.SetEndPostIterationFunction(PostProcess);

  ThermalEngine.Tolerance := 1E-5;

  FStart := GetTickCount;

  ThermalEngine.CalcTemperature(caStatic, False);

  (******************** START POST-PROCESSING ********************)

  if ThermalEngine.NbSteps = 0 then
  begin
    PostProcess;
  end;

  //Caption := FloatToStr(ThermalEngine.Residual);

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'thermalengine_???.pos' argument
  // reaches gmsh.exe unexpanded, matches no real file, and gmsh opens with
  // an empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded thermalengine_NNN.pos sequence combines in the
  // correct order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\thermalengine_???.pos', faAnyFile, SR) = 0 then
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
      ShowMessage('No thermalengine_???.pos result files found in ..\Data - run Calculate first.');
    end;

  finally
    Files.Free;
  end;

  time1.Free;
  time2.Free;

  ThermalEngine.Free;

  rho.Free;
  Cp.Free;
  k.Free;

  Gmsh.Free;

end;

procedure TForm37.PostProcess;
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

    Gmsh.OpenFile('..\Data\thermalengine_' + Format('%.3d', [ThermalEngine.Step]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  FStart := GetTickCount;

end;

function TForm37.T(NIndex, EIndex: Integer): Double;
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

function TForm37.time(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.Time;

end;

end.
