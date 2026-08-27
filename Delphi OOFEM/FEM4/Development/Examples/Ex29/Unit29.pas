unit Unit29;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, TAGraph, TASeries, ExtCtrls, ComCtrls, Math,
  newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1,
  CXS.FEMLAP.Expression;

type RBoundary = record

  NodeId : Array[0..1] of Integer;

  ElementArea : Double;
  EdgeLength : Double;

end;

type
  TForm29 = class(TForm)
    CmdCalculate: TButton;
    ProgressBar1: TProgressBar;
    GroupBox4: TGroupBox;
    Label3: TLabel;
    Label4: TLabel;
    TxtTimeInterval: TEdit;
    TxtNbTimeSteps: TEdit;
    GroupBox1: TGroupBox;
    Label6: TLabel;
    Label5: TLabel;
    Label7: TLabel;
    TxtTemperature: TEdit;
    TxtConvFactor: TEdit;
    TxtEmissivity: TEdit;
    GroupBox5: TGroupBox;
    TabControl1: TTabControl;
    ListView1: TListView;
    Chart1: TChart;
    Series1: TLineSeries;
    CmdStop: TButton;
    ChkSaveResults: TCheckBox;
    Button1: TButton;
    procedure CmdCalculateClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure CmdStopClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure TabControl1Change(Sender: TObject);
  private
    { Private declarations }

    FStopCalc : Boolean;

    FDensityExp, FSpecificHeatExp, FThermalConductivityExp : TExpressionList;

    procedure FillList(Title : String; FExp : TExpressionList);
    procedure GraphFunction(Title : String; FExp : TExpressionList);

  public
    { Public declarations }
  end;

var
  Form29: TForm29;

implementation

{$R *.lfm}

// Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
// its Parameters string - a literal 'sectionT_*.pos' argument reaches
// gmsh.exe unexpanded, matches no real file, and gmsh opens with an
// empty session. Build the actual file list ourselves instead, sorted so
// the zero-padded sectionT_NNNN.pos sequence combines in the correct
// time order.
procedure TForm29.Button1Click(Sender: TObject);
var
  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  i: Integer;
begin

  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\sectionT_*.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
    begin
      ShowMessage('No sectionT_*.pos result files found in ..\Data - run Calculate first.');
      Exit;
    end;

    FileList := '';
    for i := 0 to Files.Count - 1 do
      FileList := FileList + '..\Data\' + Files[i] + ' ';

    ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', PChar(FileList + '-combine -noview'), nil, SW_SHOWNORMAL) ;

  finally
    Files.Free;
  end;

end;

procedure TForm29.CmdCalculateClick(Sender: TObject);
var

  ii, jj, kk, n1, n2: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Node : Array[0..7] of Integer;

  Edge_B2V1 : TEdge_B2V1;
  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;

  // Element stiffness and mass matrix
  Me : TVMobj;
  Ke : TVMobj;

  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1, V2: TDoubleArray;

  // Global stiffness and mass matrix
  A, K, M : TVMSparseMtx;

  b: TVMobj;

  // Unknown vector
  T0, T: TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode: DWORD;

  nIter : Integer;

  time, dt : Double;

  bT : TVMobj;

  Assembly : TAssembly;

  NbBoundaries : Integer;
  Boundary : Array of RBoundary;

  Te : Double;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\sectionT.geo', '-3'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\sectionT.msh');
  Gmsh.ReadMesh();
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 16);
  SetLength(C1, Gmsh.NbElements * 16);
  SetLength(V1, Gmsh.NbElements * 16);
  SetLength(V2, Gmsh.NbElements * 16);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;

  (******************** GET BOUNDARY ********************)

  Caption := 'Calculating boundary...';

  Gmsh.CalculateBoundary([GMSH_BEAM]);

  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** TIME INTERVAL ********************)
  dt := StrToFloat(TxtTimeInterval.Text);

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 20);

  (******************** START ITERATION ********************)

  SetLength(v, T.Rows);

  time := 0;

  nIter := StrToInt(TxtNbTimeSteps.Text);

  ProgressBar1.Max := nIter;
  ProgressBar1.Step := 1;

  ProgressBar1.Position := 0;

  CmdStop.Enabled := True;
  FStopCalc := False;

  for ti := 1 to nIter do
  begin

    time := time + dt;

    Caption := 'Time = ' + Format('%.3f', [time]) + ' s';

    T0 := CopyObj(T);

    (******************** RESET SOURCE VECTOR ********************)

    b := TVMobj.Create(Gmsh.NbNodes, 1);

    (******************** MATRIX SETUP ********************)

    Assembly := TAssembly.Create;

    NbBoundaries := 0;
    SetLength(Boundary, Gmsh.NbElements * 4);

    n1 := 0;

    for ii := 0 to Gmsh.NbElements - 1 do
    begin

      NbNodes := 0;

      if Gmsh.ElementType[ii] = GMSH_TRI then
      begin

        NbNodes := 3;

        Te := 0;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Face_T3V1.NodeId[jj] := Node[jj];

          Te := Te + T0[Node[jj],0];

        end;

        Te := Te / NbNodes;

        for jj := 0 to NbNodes - 1 do
        begin
          Face_T3V1.CoordX[jj] := Gmsh.CoordX[Face_T3V1.NodeId[jj]];
          Face_T3V1.CoordY[jj] := Gmsh.CoordY[Face_T3V1.NodeId[jj]];
          Face_T3V1.CoordZ[jj] := Gmsh.CoordZ[Face_T3V1.NodeId[jj]];
        end;

        Face_T3V1.Transient := True;

        Face_T3V1.TimeInterval := dt;

        Face_T3V1.Density := FDensityExp.GetValue(Te);
        Face_T3V1.SpecificHeat := FSpecificHeatExp.GetValue(Te);
        Face_T3V1.Conductivity := FThermalConductivityExp.GetValue(Te);

        Face_T3V1.Calc;

        for jj := 0 to NbNodes -  1 do
        begin

          if (Gmsh.NodeOnBoundary[Face_T3V1.NodeId[(jj + 0) mod NbNodes]]) and
             (Gmsh.NodeOnBoundary[Face_T3V1.NodeId[(jj + 1) mod NbNodes]]) then
          begin

            Boundary[NbBoundaries].NodeId[0] := Node[(jj + 0) mod NbNodes];
            Boundary[NbBoundaries].NodeId[1] := Node[(jj + 1) mod NbNodes];
            Boundary[NbBoundaries].ElementArea := Face_T3V1.Area;

            Edge_B2V1.CoordX[0] := Face_T3V1.CoordX[(jj + 0) mod NbNodes];
            Edge_B2V1.CoordY[0] := Face_T3V1.CoordY[(jj + 0) mod NbNodes];

            Edge_B2V1.CoordX[1] := Face_T3V1.CoordX[(jj + 1) mod NbNodes];
            Edge_B2V1.CoordY[1] := Face_T3V1.CoordY[(jj + 1) mod NbNodes];

            Edge_B2V1.CalcGeoProperties;

            Boundary[NbBoundaries].EdgeLength := Edge_B2V1.Length;

            Inc(NbBoundaries);

            Face_T3V1.SetSourceOnEdge(jj, StrToFloat(TxtConvFactor.Text), StrToFloat(TxtTemperature.Text));

          end;

        end;

        Ke := Face_T3V1.K;
        Me := Face_T3V1.M;

        be := Face_T3V1.b;

      end;

      if Gmsh.ElementType[ii] = GMSH_QUAD then
      begin

        NbNodes := 4;

        Te := 0;

        for jj := 0 to NbNodes-1 do
        begin
          Node[jj] := Gmsh.ElementNode[ii, jj];
          Face_Q4V1.NodeId[jj] := Node[jj];

          Te := Te + T0[Node[jj],0];

        end;

        Te := Te / NbNodes;

        for jj := 0 to NbNodes - 1 do
        begin
          Face_Q4V1.CoordX[jj] := Gmsh.CoordX[Face_Q4V1.NodeId[jj]];
          Face_Q4V1.CoordY[jj] := Gmsh.CoordY[Face_Q4V1.NodeId[jj]];
          Face_Q4V1.CoordZ[jj] := Gmsh.CoordZ[Face_Q4V1.NodeId[jj]];

        end;

        Face_Q4V1.Transient := True;

        Face_Q4V1.TimeInterval := dt;

        Face_Q4V1.Density := FDensityExp.GetValue(Te);
        Face_Q4V1.SpecificHeat := FSpecificHeatExp.GetValue(Te);
        Face_Q4V1.Conductivity := FThermalConductivityExp.GetValue(Te);

        Face_Q4V1.Calc;

        for jj := 0 to NbNodes - 1 do
        begin

          if (Gmsh.NodeOnBoundary[Face_Q4V1.NodeId[(jj + 0) mod NbNodes]]) and
             (Gmsh.NodeOnBoundary[Face_Q4V1.NodeId[(jj + 1) mod NbNodes]]) then
          begin

            Boundary[NbBoundaries].NodeId[0] := Node[(jj + 0) mod NbNodes];
            Boundary[NbBoundaries].NodeId[1] := Node[(jj + 1) mod NbNodes];
            Boundary[NbBoundaries].ElementArea := Face_Q4V1.Area;

            Edge_B2V1.CoordX[0] := Face_Q4V1.CoordX[(jj + 0) mod NbNodes];
            Edge_B2V1.CoordY[0] := Face_Q4V1.CoordY[(jj + 0) mod NbNodes];

            Edge_B2V1.CoordX[1] := Face_Q4V1.CoordX[(jj + 1) mod NbNodes];
            Edge_B2V1.CoordY[1] := Face_Q4V1.CoordY[(jj + 1) mod NbNodes];

            Edge_B2V1.CalcGeoProperties;

            Boundary[NbBoundaries].EdgeLength := Edge_B2V1.Length;

            Inc(NbBoundaries);

            Face_Q4V1.SetSourceOnEdge(jj, StrToFloat(TxtConvFactor.Text), StrToFloat(TxtTemperature.Text));

          end;

        end;

        Ke := Face_Q4V1.K;
        Me := Face_Q4V1.M;

        be := Face_Q4V1.b;

      end;

      n2 := n1;

      // Standard method: Ax=b
      Assembly.Add(Ke, be, b, R1, C1, V1, n1, NbNodes, Node);

      // Mass matrix
      for jj := 0 to Nbnodes-1 do
      begin
        for kk := 0 to Nbnodes-1 do
        begin

          V2[n2] := Me[jj,kk];
          Inc(n2);

        end;

      end;

    end;

    Assembly.Free;

    SetLength(Boundary, NbBoundaries);

    SetLength(R1, n1);
    SetLength(C1, n1);
    SetLength(V1, n1);
    SetLength(V2, n1);

    K := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);
    M := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V2);

    A := SparseAdd(K, M);

    (******************** ADD TRANSIENT TERM ********************)

    bT := SparseMatMult(M, T0);

    b := b + bT;

    (******************** ADD THERMAL RADIATION ********************)

    for ii := 0 to NbBoundaries - 1 do
    begin

      b[Boundary[ii].NodeId[0],0] := b[Boundary[ii].NodeId[0],0] + dt / (Boundary[ii].ElementArea * FDensityExp.GetValue(T0[Boundary[ii].NodeId[0],0]) * FSpecificHeatExp.GetValue(T0[Boundary[ii].NodeId[0],0])) * (5.67e-8 * StrToFloat(TxtEmissivity.Text) * (power(StrToFloat(TxtTemperature.Text), 4) - power(T0[Boundary[ii].NodeId[0],0], 4)) * Boundary[ii].EdgeLength * 0.5);
      b[Boundary[ii].NodeId[1],0] := b[Boundary[ii].NodeId[1],0] + dt / (Boundary[ii].ElementArea * FDensityExp.GetValue(T0[Boundary[ii].NodeId[1],0]) * FSpecificHeatExp.GetValue(T0[Boundary[ii].NodeId[1],0])) * (5.67e-8 * StrToFloat(TxtEmissivity.Text) * (power(StrToFloat(TxtTemperature.Text), 4) - power(T0[Boundary[ii].NodeId[1],0], 4)) * Boundary[ii].EdgeLength * 0.5);

    end;

    // ssIterative + itmLUGMRES in the original -> iterative GMRES solve.
    T := FGMRESSolve(A, b);

    //ViewValues(T);
    //ViewValues(b);

    (******************** ADVANCE PROGRESS BAR ********************)

    ProgressBar1.StepIt;

    (******************** SAVE RESULTS ********************)

    if ChkSaveResults.Checked then
    begin

      for ii := 0 to Gmsh.NbNodes - 1 do
      begin

        v[ii] := T[ii,0];

      end;

    end;

    Gmsh.OpenFile('..\Data\sectionT_' + Format('%.4d', [ti-1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

    Application.ProcessMessages;

    if FStopCalc then Break;

  end;

  (******************** END ITERATION ********************)

  CmdStop.Enabled := False;

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;

  Gmsh.Free;

end;

procedure TForm29.CmdStopClick(Sender: TObject);
begin

  FStopCalc := True;

end;

procedure TForm29.FillList(Title : String; FExp: TExpressionList);
var

  i : Integer;

  Header : TListColumn;
  Data : TListItem;

begin

  ListView1.Columns.Clear;
  ListView1.Items.Clear;

  Header := ListView1.Columns.Add;
  Header.Caption := 'Id';
  Header := ListView1.Columns.Add;
  Header.Caption := 'Start (°C)';
  Header := ListView1.Columns.Add;
  Header.Caption := 'End (°C)';
  Header := ListView1.Columns.Add;
  Header.Caption := Title;

  ListView1.Column[0].Width := 60;
  ListView1.Column[1].Width := 60;
  ListView1.Column[2].Width := 60;
  ListView1.Column[3].Width := 210;

  for i := 0 to FExp.NbExpressions - 1 do
  begin

    Data := ListView1.Items.Add;
    Data.Caption := IntToStr(i+1);
    Data.SubItems.Add(FloatToStr(FExp.VarStart[i]));
    Data.SubItems.Add(FloatToStr(FExp.VarEnd[i]));
    Data.SubItems.Add(FExp.Expression[i]);

  end;

end;

procedure TForm29.FormCreate(Sender: TObject);
begin

  FDensityExp := TExpressionList.Create;
  FSpecificHeatExp := TExpressionList.Create;
  FThermalConductivityExp := TExpressionList.Create;

  // Density
  FDensityExp.AddExpression(20, 115, '2300', 'T');
  FDensityExp.AddExpression(115, 200, '2300*(1-0.02*(T-115)/85)', 'T');
  FDensityExp.AddExpression(200, 400, '2300*(0.98-0.03*(T-200)/200)', 'T');
  FDensityExp.AddExpression(400, 1200, '2300*(0.95-0.07*(T-400)/800)', 'T');

  // Specific heat
  FSpecificHeatExp.AddExpression(20, 20, '897', 'T');
  FSpecificHeatExp.AddExpression(100, 100, '897', 'T');
  FSpecificHeatExp.AddExpression(102, 102, '2020', 'T');
  FSpecificHeatExp.AddExpression(116, 116, '2020', 'T');
  FSpecificHeatExp.AddExpression(200, 200, '1006', 'T');
  FSpecificHeatExp.AddExpression(400, 400, '1094', 'T');
  FSpecificHeatExp.AddExpression(1200, 1200, '1094', 'T');

  // Thermal conductivity heat
  FThermalConductivityExp.AddExpression(20, 1200, '1.36-0.136*(T/100)+0.0057*(T/100)^2', 'T');

  TabControl1.TabIndex := 0;
  FillList('Density (kg/m^3)', FDensityExp);
  GraphFunction('Density (kg/m^3)', FDensityExp);

end;

procedure TForm29.FormDestroy(Sender: TObject);
begin

  FDensityExp.Free;
  FSpecificHeatExp.Free;
  FThermalConductivityExp.Free;

end;

procedure TForm29.GraphFunction(Title: String; FExp: TExpressionList);
var

  i : Integer;
  T : Double;

  F : Double;

begin

  Chart1.Title.Text.Text := Title;
  Chart1.BottomAxis.Title.Caption := 'T (°C)';
  Chart1.LeftAxis.Title.Caption := '';

  Series1.Clear;

  i := 0;

  T := 20;

  while T < 1200 do
  begin

    T := T + 1;

    F := FExp.GetValue(T);

    //OutputDebugString(Pchar(FloatToStr(F)));

    Series1.AddXY(T, F);
    Inc(i);

  end;

end;

procedure TForm29.TabControl1Change(Sender: TObject);
begin

  if TabControl1.TabIndex = 0 then
  begin
    FillList('Density (kg/m^3)', FDensityExp);
    GraphFunction('Density (kg/m^3)', FDensityExp);
  end
  else if TabControl1.TabIndex = 1 then
  begin
    FillList('Specific Heat (J/(kg·°C)', FSpecificHeatExp);
    GraphFunction('Specific Heat (J/(kg·°C)', FSpecificHeatExp);
  end
  else if TabControl1.TabIndex = 2 then
  begin
    FillList('Thermal Conductivity (W/(m·°C)', FThermalConductivityExp);
    GraphFunction('Thermal Conductivity (W/(m·°C)', FThermalConductivityExp);
  end;

end;

end.
