unit Unit36;

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
  TForm36 = class(TForm)
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

    function x(NIndex, EIndex : Integer) : Double;
    function y(NIndex, EIndex : Integer) : Double;
    function z(NIndex, EIndex : Integer) : Double;

    function T(NIndex, EIndex : Integer) : Double;
    function time(NIndex, EIndex : Integer) : Double;

    procedure PostProcess;

  end;

var
  Form36: TForm36;

implementation

{$R *.lfm}

procedure TForm36.Button1Click(Sender: TObject);
var

  ii, jj : Integer;

  MeshSize : Double;

  dx, dy : Double;

  SectionArea, Perimeter, Thickness : Double;

  ExitCode: DWORD;

  NbNodes : Integer;
  Node : Array[0..7] of Integer;

  MaterialId : Integer;

  EleType : NEleType;

  rho, Cp, k : TExpressionList;

  e, h, Tinf : TExpressionList;

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  fi : Integer;

begin

  FStart := GetTickCount;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := 0.002;

  dx := 0.08*0.5;
  dy := 0.15*0.5;
  Thickness := 1;

  Perimeter := 2 * Thickness + 2 * dy;
  SectionArea := Thickness * dy;

  Gmsh.OpenFile('..\Data\thermalengine_ec.geo');
  Gmsh.GenerateRectangle(dx, dy, MeshSize, GMSH_QUAD);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\thermalengine_ec.geo', '-3', '-optimize'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\thermalengine_ec.msh');
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
  k.AddExpression(20, 1200, '1.36-0.136*(T/100)+0.0057*(T/100)^2', 'T');

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
  ThermalEngine.EndSetRestraints;

  (******************** START INITIAL CONDITIONS ********************)
  ThermalEngine.SetInitialTemperature(20);

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  e := TExpressionList.Create;
  e.AddExpression(0, 1200, '0.7', 't');

  h := TExpressionList.Create;
  h.AddExpression(0, 1200, '25', 't');

  Tinf := TExpressionList.Create;
  Tinf.AddExpression(0, 1200, '1200', 't');

  for ii := 0 to ThermalEngine.NbElements - 1 do
  begin

    for jj := 0 to ThermalEngine.Element[ii].NbNodes - 1 do
    begin

      if (Abs(ThermalEngine.CoordX[ThermalEngine.Element[ii].NodeId[(jj + 0) mod ThermalEngine.Element[ii].NbNodes]] - 0.0) < 1E-6) and
         (Abs(ThermalEngine.CoordX[ThermalEngine.Element[ii].NodeId[(jj + 1) mod ThermalEngine.Element[ii].NbNodes]] - 0.0) < 1E-6) then
      begin

        ThermalEngine.AddEdgeConvection(ii, jj, time, h, Tinf);
        ThermalEngine.AddEdgeRadiation(ii, jj, time, e, Tinf);

      end;

      if (Abs(ThermalEngine.CoordY[ThermalEngine.Element[ii].NodeId[(jj + 0) mod ThermalEngine.Element[ii].NbNodes]] - 0.0) < 1E-6) and
         (Abs(ThermalEngine.CoordY[ThermalEngine.Element[ii].NodeId[(jj + 1) mod ThermalEngine.Element[ii].NbNodes]] - 0.0) < 1E-6) then
      begin

        ThermalEngine.AddEdgeConvection(ii, jj, time, h, Tinf);
        ThermalEngine.AddEdgeRadiation(ii, jj, time, e, Tinf);

      end;

    end;

  end;

  (******************** START TIME CONTROL ********************)
  ThermalEngine.TimeInterval := 10;  // 10
  ThermalEngine.NbSteps := 180;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  ThermalEngine.SetEndPostIterationFunction(PostProcess);

  ThermalEngine.Tolerance := 1E-5;
  ThermalEngine.CalcTemperature(caTransient, True);

  (******************** START POST-PROCESSING ********************)

  if ThermalEngine.NbSteps = 0 then
    PostProcess;

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'thermalengine_ec_*.pos' argument
  // reaches gmsh.exe unexpanded, matches no real file, and gmsh opens with
  // an empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded thermalengine_ec_NNN.pos sequence combines in the
  // correct time order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\thermalengine_ec_*.pos', faAnyFile, SR) = 0 then
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
      ShowMessage('No thermalengine_ec_*.pos result files found in ..\Data - run Calculate first.');
    end;

  finally
    Files.Free;
  end;

  ThermalEngine.Free;

  h.Free;

  e.Free;

  rho.Free;
  Cp.Free;
  k.Free;

  Gmsh.Free;

end;

procedure TForm36.PostProcess;
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

    Gmsh.OpenFile('..\Data\thermalengine_ec_' + Format('%.3d', [ThermalEngine.Step - 1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  FStart := GetTickCount;

end;

function TForm36.T(NIndex, EIndex: Integer): Double;
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

function TForm36.time(NIndex, EIndex : Integer): Double;
begin

  Result := ThermalEngine.Time;

end;

function TForm36.x(NIndex, EIndex : Integer): Double;
begin

  Result := ThermalEngine.CoordX[NIndex];

end;

function TForm36.y(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordY[NIndex];

end;

function TForm36.z(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordZ[NIndex];

end;

end.
