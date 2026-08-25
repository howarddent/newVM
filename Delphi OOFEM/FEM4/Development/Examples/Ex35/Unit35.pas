unit Unit35;

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
  TForm35 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }

    FStart, FElapsed : Double;

    // Gmsh data
    Gmsh : TGmsh;
    // Thermal engine class
    ThermalEngine : TThermalEngine;

    function T(NIndex, EIndex : Integer) : Double;
    function x(NIndex, EIndex : Integer) : Double;
    function f(NIndex, EIndex : Integer) : Double;
    function time(NIndex, EIndex : Integer) : Double;

    procedure PostProcess;

  public
    { Public declarations }
  end;

var
  Form35: TForm35;

implementation

{$R *.lfm}

procedure TForm35.Button1Click(Sender: TObject);
var

  i, j : Integer;

  MeshSize : Double;

  dx, dy, dz : Double;

  SectionArea, Perimeter, Thickness : Double;

  ExitCode: DWORD;

  NbNodes : Integer;
  Node : Array[0..7] of Integer;

  DensityExp1, SpecificHeatExp1, ThermalConductivityExp1 : TExpressionList;
  DensityExp2, SpecificHeatExp2, ThermalConductivityExp2 : TExpressionList;
  DensityExp3, SpecificHeatExp3, ThermalConductivityExp3 : TExpressionList;

  MaterialId1, MaterialId2, MaterialId3: Integer;

  SectionId, ThicknessId : Integer;

  EleType : NEleType;

  SourceExp : TExpressionList;

  k: Integer;

  Element : TElement;

  Emissivity, ConvectiveFactorExp, TinfExp : TExpressionList;

  ApplyBC : Boolean;

  T1, T2 : TExpressionList;

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;

begin

  FStart := GetTickCount;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\tamega\tamega.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  ThermalEngine := TThermalEngine.Create;

  (******************** START PROPERTIES ********************)
  // Terra

  DensityExp1 := TExpressionList.Create;
  SpecificHeatExp1 := TExpressionList.Create;
  ThermalConductivityExp1 := TExpressionList.Create;

  DensityExp1.AddExpression(0, 1000, '1', 'T');
  SpecificHeatExp1.AddExpression(0, 1000, '1', 'T');
  ThermalConductivityExp1.AddExpression(0, 1000, '20', 'T');

  MaterialId1 := ThermalEngine.AddMaterial(T, DensityExp1, SpecificHeatExp1, ThermalConductivityExp1);

  // Barragem
  DensityExp2 := TExpressionList.Create;
  SpecificHeatExp2 := TExpressionList.Create;
  ThermalConductivityExp2 := TExpressionList.Create;

  DensityExp2.AddExpression(0, 1000, '1', 'T');
  SpecificHeatExp2.AddExpression(0, 1000, '1', 'T');
  ThermalConductivityExp2.AddExpression(0, 1000, '100', 'T');

  MaterialId2 := ThermalEngine.AddMaterial(T, DensityExp2, SpecificHeatExp2, ThermalConductivityExp2);

  // Encoragem
  DensityExp3 := TExpressionList.Create;
  SpecificHeatExp3 := TExpressionList.Create;
  ThermalConductivityExp3 := TExpressionList.Create;

  DensityExp3.AddExpression(0, 1000, '1', 'T');
  SpecificHeatExp3.AddExpression(0, 1000, '1', 'T');
  ThermalConductivityExp3.AddExpression(0, 1000, '100', 'T');

  MaterialId3 := ThermalEngine.AddMaterial(T, DensityExp3, SpecificHeatExp3, ThermalConductivityExp3);

  (******************** BC METHOD ********************)
  ThermalEngine.PenaltyMethod := True;

  (******************** START NODES ********************)

  ThermalEngine.BeginAddMesh;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    ThermalEngine.AddNode(Gmsh.CoordX[i], Gmsh.CoordY[i], Gmsh.CoordZ[i]);

  end;

  (******************** START ELEMENTS ********************)

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    NbNodes := 0;

    if Gmsh.ElementType[i] = GMSH_BEAM then begin NbNodes := 2; EleType := elBeam; end
    else if Gmsh.ElementType[i] = GMSH_TRI then begin NbNodes := 3; EleType := elTri; end
    else if Gmsh.ElementType[i] = GMSH_QUAD then begin NbNodes := 4; EleType := elQuad; end
    else if Gmsh.ElementType[i] = GMSH_TETRA then begin NbNodes := 4; EleType := elTetra; end
    else if Gmsh.ElementType[i] = GMSH_HEXA then begin NbNodes := 8; EleType := elHexa; end
    else if Gmsh.ElementType[i] = GMSH_PRISM then begin NbNodes := 6; EleType := elPrism; end;

    for j := 0 to NbNodes-1 do
    begin
      Node[j] := Gmsh.ElementNode[i, j];
    end;

    case Gmsh.ElementPhysicalRegion[i] of
    1: // Terra
      ThermalEngine.AddElement(Node, NbNodes, EleType, MaterialId1, SectionArea, Perimeter, Thickness);
    3: // Barragem
      ThermalEngine.AddElement(Node, NbNodes, EleType, MaterialId2, SectionArea, Perimeter, Thickness);
    5: // Encoragem
      ThermalEngine.AddElement(Node, NbNodes, EleType, MaterialId3, SectionArea, Perimeter, Thickness);
    end;

  end;

  ThermalEngine.EndAddMesh;

  (******************** START INITIAL CONDITIONS ********************)
  ThermalEngine.SetInitialTemperature(20.0);

  (******************** START TEMPERATURE RESTRAINTS ********************)

  ThermalEngine.BeginSetRestraints;

  T1 := TExpressionList.Create;
  T1.AddExpression(-1000, +1000, '20', 'x');

  T2 := TExpressionList.Create;
  T2.AddExpression(-1000, +1000, '25*f', 'f');

  for i := 0 to ThermalEngine.NbNodes - 1 do
  begin

    (*
    if (Abs(ThermalEngine.CoordZ[i] - 107.0) < 1E-1) then
    begin

      ThermalEngine.SetNodeRestraint(i, x, T1);

    end;
    *)

    //if (Abs(ThermalEngine.CoordZ[i] - 325.0) < 1E-1) and (Abs(ThermalEngine.CoordX[i] - 0.0) > 150) then
    if (Abs(ThermalEngine.CoordZ[i] - 325.0) < 1E-1) then
    begin

      ThermalEngine.SetNodeRestraint(i, f, T2);

    end;

  end;

  ThermalEngine.EndSetRestraints;

  (******************** START BOUNDARY CONDITIONS AND SOURCES ********************)

  SourceExp := TExpressionList.Create;
  SourceExp.AddExpression(0, 1E+12, '10', 't');

  ConvectiveFactorExp := TExpressionList.Create;
  ConvectiveFactorExp.AddExpression(0,  1E+12, '0', 't');

  TinfExp := TExpressionList.Create;
  TinfExp.AddExpression(0,  1E+12, '0', 't');

  (*
  for i := 0 to ThermalEngine.NbNodes - 1 do
  begin

    if (Abs(ThermalEngine.CoordX[i] - 0.0) < 1E-1) and
       (Abs(ThermalEngine.CoordZ[i] - 325.0) < 1E-1) then
    begin

      ThermalEngine.AddNodeSource(i, time, SourceExp);

    end;

  end;
  *)

  (******************** START TIME CONTROL ********************)
  ThermalEngine.TimeInterval := 10;  // 10
  ThermalEngine.NbSteps := 1;

  (******************** START RUN ANALYSIS ********************)

  Caption := 'Running analysis...';

  ThermalEngine.SetEndPostIterationFunction(PostProcess);

  ThermalEngine.Tolerance := 1E-5;
  ThermalEngine.CalcTemperature(caTransient, False);

  (******************** START POST-PROCESSING ********************)

  if ThermalEngine.NbSteps = 0 then
    PostProcess;

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'tamega_*.pos' argument reaches
  // gmsh.exe unexpanded, matches no real file, and gmsh opens with an
  // empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded tamega_NNN.pos sequence combines in the correct
  // time order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\tamega_*.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count > 0 then
    begin

      FileList := '';
      for k := 0 to Files.Count - 1 do
        FileList := FileList + '..\Data\' + Files[k] + ' ';

      ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', PChar(FileList + '-combine -noview'), nil, SW_SHOWNORMAL) ;

    end
    else
    begin
      ShowMessage('No tamega_*.pos result files found in ..\Data - run Calculate first.');
    end;

  finally
    Files.Free;
  end;

  T1.Free;
  T2.Free;

  ThermalEngine.Free;

  SourceExp.Free;

  ConvectiveFactorExp.Free;
  TinfExp.Free;

  DensityExp1.Free;
  SpecificHeatExp1.Free;
  ThermalConductivityExp1.Free;

  DensityExp2.Free;
  SpecificHeatExp2.Free;
  ThermalConductivityExp2.Free;

  DensityExp3.Free;
  SpecificHeatExp3.Free;
  ThermalConductivityExp3.Free;

  Gmsh.Free;

end;

function TForm35.f(NIndex, EIndex: Integer): Double;
var

  d : Double;

const

  xp = -278;
  yp = -165;

begin

  d := sqrt((ThermalEngine.CoordX[NIndex] - xp) * (ThermalEngine.CoordX[NIndex] - xp) + (ThermalEngine.CoordY[NIndex] - yp) * (ThermalEngine.CoordY[NIndex] - yp));

  Result := 1 / (1 + d*0.0001);

end;

procedure TForm35.PostProcess;
var

  i : Integer;

  // Output data
  v : TDoubleArray;

begin

  FElapsed := GetTickCount - FStart;

  Caption := IntToStr(ThermalEngine.Step) + ' : ' + FloatToStr(FElapsed);

  Application.ProcessMessages;

  //if ThermalEngine.Step = ThermalEngine.NbSteps then
  begin

    SetLength(v, ThermalEngine.NbNodes);

    for i := 0 to ThermalEngine.NbNodes - 1 do
    begin

      v[i] := ThermalEngine.Temperature[i];

    end;

    Gmsh.OpenFile('..\Data\tamega_' + Format('%.3d', [ThermalEngine.Step]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  FStart := GetTickCount;

end;

function TForm35.T(NIndex, EIndex: Integer): Double;
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

function TForm35.time(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.Time;

end;

function TForm35.x(NIndex, EIndex: Integer): Double;
begin

  Result := ThermalEngine.CoordX[NIndex];

end;

end.
