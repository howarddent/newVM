unit Unit27;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, Math,
  newVM, newVMsparse, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, ComCtrls;

type RBoundary = record

  NodeId : Array[0..1] of Integer;

  ElementArea : Double;
  EdgeLength : Double;

end;

type
  TForm27 = class(TForm)
    CmdCalculate: TButton;
    ProgressBar1: TProgressBar;
    GroupBox2: TGroupBox;
    Label1: TLabel;
    Label9: TLabel;
    Label8: TLabel;
    TxtThickness: TEdit;
    TxtHeight: TEdit;
    TxtWidth: TEdit;
    GroupBox3: TGroupBox;
    Label2: TLabel;
    TxtMeshSize: TEdit;
    CmbEleType: TComboBox;
    Label10: TLabel;
    GroupBox4: TGroupBox;
    Label3: TLabel;
    Label4: TLabel;
    TxtTimeInterval: TEdit;
    TxtNbTimeSteps: TEdit;
    GroupBox1: TGroupBox;
    TxtTemperature: TEdit;
    Label6: TLabel;
    TxtConvFactor: TEdit;
    Label5: TLabel;
    TxtEmissivity: TEdit;
    Label7: TLabel;
    GroupBox5: TGroupBox;
    Label11: TLabel;
    Label12: TLabel;
    Label13: TLabel;
    TxtConductivity: TEdit;
    TxtDensity: TEdit;
    TxtSpecificHeat: TEdit;
    CmdStop: TButton;
    ChkSaveResults: TCheckBox;
    Button1: TButton;
    procedure CmdCalculateClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure CmdStopClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }

    fStopCalc : Boolean;

  public
    { Public declarations }
  end;

var
  Form27: TForm27;

implementation

{$R *.lfm}

const
  // '..'+PathDelim+'Data'+PathDelim rather than a hardcoded '..\Data\' -
  // PathDelim is '\' on Windows and '/' on Unix, so this resolves
  // correctly on either platform instead of only Windows.
  DataDir = '..' + PathDelim + 'Data' + PathDelim;
{$IFDEF WINDOWS}
  GmshExecutable = 'c:\gmsh\gmsh.exe';
{$ELSE}
  // Bare name, resolved via $PATH by TProcess itself (see
  // CXS.FEMLAP.ShellExec.pas) - matches a normal `apt install gmsh`.
  GmshExecutable = 'gmsh';
{$ENDIF}

// FindFirst/FindNext already do the file-list expansion themselves (not
// delegated to the OS shell), so this works unchanged on both platforms -
// the only originally-Windows-specific things here were ShellExecute
// itself and the hardcoded gmsh.exe path/backslash Data path, both now
// routed through the cross-platform Sto_ShellExecute (see
// CXS.FEMLAP.ShellExec.pas) and DataDir/GmshExecutable above. Historical
// note: Windows' ShellExecute never expands wildcards in its Parameters
// string - a literal 'eurocode_*.pos' argument used to reach gmsh.exe
// unexpanded and match no real file, which is why the file list is still
// built explicitly here rather than passed as a glob pattern - sorted so
// the zero-padded eurocode_NNN.pos sequence combines in the correct time
// order.
procedure TForm27.Button1Click(Sender: TObject);
var
  SR: TSearchRec;
  Files: TStringList;
  Args: array of String;
  ExitCode: Cardinal;
  i: Integer;
begin

  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst(DataDir + 'eurocode_*.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
    begin
      ShowMessage('No eurocode_*.pos result files found in ' + DataDir + ' - run Calculate first.');
      Exit;
    end;

    SetLength(Args, Files.Count + 2);
    for i := 0 to Files.Count - 1 do
      Args[i] := DataDir + Files[i];
    Args[Files.Count] := '-combine';
    Args[Files.Count + 1] := '-noview';

    // Wait=0: launch the viewer and return immediately, same as the
    // original fire-and-forget ShellExecute call.
    Sto_ShellExecute(GmshExecutable, Args, ExitCode);

  finally
    Files.Free;
  end;

end;

procedure TForm27.CmdCalculateClick(Sender: TObject);
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

  b0 : TVMobj;
  b: TVMobj;

  // Unknown vector
  T0, T: TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode: Cardinal;

  nIter : Integer;

  time, dt : Double;

  bT : TVMobj;

  Assembly : TAssembly;

  MeshSize : Double;

  NbBoundaries : Integer;
  Boundary : Array of RBoundary;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := StrToFloat(TxtMeshSize.Text);

  Gmsh.OpenFile(DataDir + 'eurocode.geo');
  if CmbEleType.Text = 'TRI' then
    Gmsh.GenerateRectangle(StrToFloat(TxtWidth.Text)*0.5, StrToFloat(TxtHeight.Text)*0.5, MeshSize, GMSH_TRI)
   else if CmbEleType.Text = 'QUAD' then
    Gmsh.GenerateRectangle(StrToFloat(TxtWidth.Text)*0.5, StrToFloat(TxtHeight.Text)*0.5, MeshSize, GMSH_QUAD);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute(GmshExecutable, [DataDir + 'eurocode.geo', '-3'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile(DataDir + 'eurocode.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 16);
  SetLength(C1, Gmsh.NbElements * 16);
  SetLength(V1, Gmsh.NbElements * 16);
  SetLength(V2, Gmsh.NbElements * 16);

  Edge_B2V1 := TEdge_B2V1.Create;
  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;

  (******************** SET BOUNDARY CONDITIONS ********************)

  Caption := 'Setting boundary conditions...';


  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** TIME INTERVAL ********************)
  dt := StrToFloat(TxtTimeInterval.Text);

  (******************** MATRIX SETUP ********************)

  Caption := 'Finite element assembly...';

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

      for jj := 0 to NbNodes-1 do
      begin
        Node[jj] := Gmsh.ElementNode[ii, jj];
        Face_T3V1.NodeId[jj] := Node[jj];
      end;

      for jj := 0 to NbNodes - 1 do
      begin
        Face_T3V1.CoordX[jj] := Gmsh.CoordX[Face_T3V1.NodeId[jj]];
        Face_T3V1.CoordY[jj] := Gmsh.CoordY[Face_T3V1.NodeId[jj]];
        Face_T3V1.CoordZ[jj] := Gmsh.CoordZ[Face_T3V1.NodeId[jj]];
      end;

      Face_T3V1.Transient := True;

      Face_T3V1.TimeInterval := dt;

      Face_T3V1.Thickness := StrToFloat(TxtThickness.Text);

      Face_T3V1.Density := StrToFloat(TxtDensity.Text);
      Face_T3V1.SpecificHeat := StrToFloat(TxtSpecificHeat.Text);
      Face_T3V1.Conductivity := StrToFloat(TxtConductivity.Text);;

      Face_T3V1.Calc;

      for jj := 0 to NbNodes -  1 do
      begin
        if (Face_T3V1.CoordX[(jj + 0) mod NbNodes] = 0) and (Face_T3V1.CoordX[(jj + 1) mod NbNodes] = 0) then
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

        if (Face_T3V1.CoordY[(jj + 0) mod NbNodes] = 0) and (Face_T3V1.CoordY[(jj + 1) mod NbNodes] = 0) then
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

      for jj := 0 to NbNodes-1 do
      begin
        Node[jj] := Gmsh.ElementNode[ii, jj];
        Face_Q4V1.NodeId[jj] := Node[jj];
      end;

      for jj := 0 to NbNodes - 1 do
      begin
        Face_Q4V1.CoordX[jj] := Gmsh.CoordX[Face_Q4V1.NodeId[jj]];
        Face_Q4V1.CoordY[jj] := Gmsh.CoordY[Face_Q4V1.NodeId[jj]];
        Face_Q4V1.CoordZ[jj] := Gmsh.CoordZ[Face_Q4V1.NodeId[jj]];
      end;

      Face_Q4V1.Transient := True;

      Face_Q4V1.TimeInterval := dt;

      Face_Q4V1.Thickness := StrToFloat(TxtThickness.Text);

      Face_Q4V1.Density := StrToFloat(TxtDensity.Text);
      Face_Q4V1.SpecificHeat := StrToFloat(TxtSpecificHeat.Text);
      Face_Q4V1.Conductivity := StrToFloat(TxtConductivity.Text);;

      Face_Q4V1.Calc;

      for jj := 0 to NbNodes - 1 do
      begin
        if (Face_Q4V1.CoordX[(jj + 0) mod NbNodes] = 0) and (Face_Q4V1.CoordX[(jj + 1) mod NbNodes] = 0) then
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

        if (Face_Q4V1.CoordY[(jj + 0) mod NbNodes] = 0) and (Face_Q4V1.CoordY[(jj + 1) mod NbNodes] = 0) then
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

  (******************** IMPOSE BOUNDARY CONDITIONS ********************)

  b0 := CopyObj(b);

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 20);

  (******************** START ITERATION ********************)

  // Instructing UMFPACK to maintain the factorisation (A.SparsePattern :=
  // sppNumeric in the original) no longer applies - PardisoSolve always
  // does a fresh one-shot analysis+factorisation+solve.

  SetLength(v, T.Rows);

  time := 0;

  nIter := StrToInt(TxtNbTimeSteps.Text);

  ProgressBar1.Max := nIter;
  ProgressBar1.Step := 1;

  ProgressBar1.Position := 0;

  CmdStop.Enabled := True;
  fStopCalc := False;

  for ti := 1 to nIter do
  begin

    time := time + dt;

    Caption := 'Time = ' + Format('%.3f', [time]) + ' s';

    T0 := CopyObj(T);

    b := TVMobj.Create(b.Rows, b.Cols);

    b := b + b0;

    (******************** ADD TRANSIENT TERM ********************)

    bT := SparseMatMult(M, T0);

    b := b + bT;

    (******************** ADD THERMAL RADIATION ********************)

    for ii := 0 to NbBoundaries - 1 do
    begin

      b[Boundary[ii].NodeId[0],0] := b[Boundary[ii].NodeId[0],0] + dt / (Boundary[ii].ElementArea * StrToFloat(TxtDensity.Text) * StrToFloat(TxtSpecificHeat.Text)) * (5.67e-8 * StrToFloat(TxtEmissivity.Text) * (power(StrToFloat(TxtTemperature.Text), 4) - power(T0[Boundary[ii].NodeId[0],0], 4)) * Boundary[ii].EdgeLength * 0.5);
      b[Boundary[ii].NodeId[1],0] := b[Boundary[ii].NodeId[1],0] + dt / (Boundary[ii].ElementArea * StrToFloat(TxtDensity.Text) * StrToFloat(TxtSpecificHeat.Text)) * (5.67e-8 * StrToFloat(TxtEmissivity.Text) * (power(StrToFloat(TxtTemperature.Text), 4) - power(T0[Boundary[ii].NodeId[1],0], 4)) * Boundary[ii].EdgeLength * 0.5);

    end;

    // ssUmfPack + mtSymmPosDef in the original -> direct solve, SPD.
    T := PardisoSolve(A, b, True);

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

    Gmsh.OpenFile(DataDir + 'eurocode_' + Format('%.3d', [ti-1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

    Application.ProcessMessages;

    if fStopCalc then Break;

  end;

  (******************** END ITERATION ********************)

  CmdStop.Enabled := False;

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;

  Gmsh.Free;

end;

procedure TForm27.CmdStopClick(Sender: TObject);
begin

  fStopCalc := True;

end;

procedure TForm27.FormCreate(Sender: TObject);
begin

  CmbEleType.AddItem('TRI', nil);
  CmbEleType.AddItem('QUAD', nil);

  CmbEleType.ItemIndex := 1;

end;

end.
