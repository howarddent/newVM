unit Unit26;

{$mode delphi}{$H+}

interface

uses
  Windows, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, TAGraph, TASeries,
  newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Analytical, CXS.FEMLAP.Penalty,
  CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Brick_T4V1, CXS.FEMLAP.Brick_H8V1, CXS.FEMLAP.Brick_W6V1;

type
  TForm26 = class(TForm)
    Chart1: TChart;
    Button1: TButton;
    Label1: TLabel;
    ComboBox1: TComboBox;
    Label2: TLabel;
    Edit1: TEdit;
    Label3: TLabel;
    Edit2: TEdit;
    Edit3: TEdit;
    Label4: TLabel;
    CheckBox1: TCheckBox;
    CheckBox2: TCheckBox;
    Series1: TAreaSeries;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form26: TForm26;

implementation

{$R *.lfm}

procedure TForm26.Button1Click(Sender: TObject);
var

  ii, jj, kk, n1, n2: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Node : Array[0..7] of Integer;

  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;
  Brick_T4V1 : TBrick_T4V1;
  Brick_H8V1 : TBrick_H8V1;
  Brick_W6V1 : TBrick_W6V1;

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

  // BC's
  diag : TVMobj;

  bT : TVMobj;

  Analytical : TAnalytical;
  Ta : Double;

  Assembly : TAssembly;

  Penalty : TPenalty;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  MeshSize : Double;

  // For the wildcard gmsh -combine launch (see CheckBox2 handling below)
  GmshFiles : TStringList;
  GmshSR : TSearchRec;
  GmshFileList : String;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := StrToFloat(Edit1.Text);

  Gmsh.OpenFile('..\Data\tvalid.geo');
  if ComboBox1.Text = 'TRI' then
    Gmsh.GenerateRectangle(1, 1, MeshSize, GMSH_TRI)
  else if ComboBox1.Text = 'QUAD' then
    Gmsh.GenerateRectangle(1, 1, MeshSize, GMSH_QUAD)
  else if ComboBox1.Text = 'TETRA' then
    Gmsh.GenerateBox(1, 1, 0.05, MeshSize, GMSH_TETRA)
  else if ComboBox1.Text = 'HEXA' then
    Gmsh.GenerateBox(1, 1, 0.05, MeshSize, GMSH_HEXA)
  else if ComboBox1.Text = 'PRISM' then
    Gmsh.GenerateBox(1, 1, 0.05, MeshSize, GMSH_PRISM);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\tvalid.geo -3', ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\tvalid.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);
  SetLength(V2, Gmsh.NbElements * 64);

  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;
  Brick_T4V1 := TBrick_T4V1.Create;
  Brick_H8V1 := TBrick_H8V1.Create;
  Brick_W6V1 := TBrick_W6V1.Create;

  (******************** SET BOUNDARY CONDITIONS ********************)

  Caption := 'Setting boundary conditions...';

  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[ii] := False;

    if (Abs(Gmsh.CoordX[ii]) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := 0;
    end;

    if (Abs(Gmsh.CoordX[ii] - 1) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := 0;
    end;

    if (Abs(Gmsh.CoordY[ii]) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := 0;
    end;

    if (Abs(Gmsh.CoordY[ii] - 1) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := 0;
    end;

  end;

  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** TIME INTERVAL ********************)
  dt := StrToFloat(Edit2.Text);

  (******************** MATRIX SETUP ********************)

  Caption := 'Finite element assembly...';

  Assembly := TAssembly.Create;

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

      Face_T3V1.Calc;

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

      Face_Q4V1.Calc;

      Ke := Face_Q4V1.K;
      Me := Face_Q4V1.M;

      be := Face_Q4V1.b;

    end;

    if Gmsh.ElementType[ii] = GMSH_TETRA then
    begin

      NbNodes := 4;

      for jj := 0 to NbNodes-1 do
      begin
        Node[jj] := Gmsh.ElementNode[ii, jj];
        Brick_T4V1.NodeId[jj] := Node[jj];
      end;

      for jj := 0 to NbNodes - 1 do
      begin
        Brick_T4V1.CoordX[jj] := Gmsh.CoordX[Brick_T4V1.NodeId[jj]];
        Brick_T4V1.CoordY[jj] := Gmsh.CoordY[Brick_T4V1.NodeId[jj]];
        Brick_T4V1.CoordZ[jj] := Gmsh.CoordZ[Brick_T4V1.NodeId[jj]];
      end;

      // Transient
      Brick_T4V1.Transient := True;

      Brick_T4V1.TimeInterval := dt;

      Brick_T4V1.Calc;

      Ke := Brick_T4V1.K;
      Me := Brick_T4V1.M;

      be := Brick_T4V1.b;

    end;

    if Gmsh.ElementType[ii] = GMSH_HEXA then
    begin

      NbNodes := 8;

      for jj := 0 to NbNodes - 1 do
      begin
        Node[jj] := Gmsh.ElementNode[ii, jj];
        Brick_H8V1.NodeId[jj] := Node[jj];
      end;

      for jj := 0 to NbNodes - 1 do
      begin
        Brick_H8V1.CoordX[jj] := Gmsh.CoordX[Brick_H8V1.NodeId[jj]];
        Brick_H8V1.CoordY[jj] := Gmsh.CoordY[Brick_H8V1.NodeId[jj]];
        Brick_H8V1.CoordZ[jj] := Gmsh.CoordZ[Brick_H8V1.NodeId[jj]];
      end;

      // Transient
      Brick_H8V1.Transient := True;

      Brick_H8V1.TimeInterval := dt;

      Brick_H8V1.Calc;

      Ke := Brick_H8V1.K;
      Me := Brick_H8V1.M;

      be := Brick_H8V1.b;

    end;

    if Gmsh.ElementType[ii] = GMSH_PRISM then
    begin

      NbNodes := 6;

      for jj := 0 to NbNodes - 1 do
      begin
        Node[jj] := Gmsh.ElementNode[ii, jj];
        Brick_W6V1.NodeId[jj] := Node[jj];
      end;

      for jj := 0 to NbNodes - 1 do
      begin
        Brick_W6V1.CoordX[jj] := Gmsh.CoordX[Brick_W6V1.NodeId[jj]];
        Brick_W6V1.CoordY[jj] := Gmsh.CoordY[Brick_W6V1.NodeId[jj]];
        Brick_W6V1.CoordZ[jj] := Gmsh.CoordZ[Brick_W6V1.NodeId[jj]];
      end;

      // Transient
      Brick_W6V1.Transient := True;

      Brick_W6V1.TimeInterval := dt;

      Brick_W6V1.Calc;

      Ke := Brick_W6V1.K;
      Me := Brick_W6V1.M;

      be := Brick_W6V1.b;

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

  SetLength(R1, n1);
  SetLength(C1, n1);
  SetLength(V1, n1);
  SetLength(V2, n1);

  K := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);
  M := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V2);

  A := SparseAdd(K, M);

  (******************** IMPOSE BOUNDARY CONDITIONS ********************)

  Penalty := TPenalty.Create;

  Penalty.Factor := 1000;
  Penalty.Impose(IsFixed, Values, A, b);

  Penalty.Free;

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 1);

  (******************** START ITERATION ********************)

  Analytical := TAnalytical.Create;

  // Instructing UMFPACK to maintain the factorisation (A.SparsePattern :=
  // sppNumeric in the original) no longer applies - PardisoSolve always
  // does a fresh one-shot analysis+factorisation+solve.

  SetLength(v, T.Rows);

  time := 0;

  nIter := StrToInt(Edit3.Text);

  for ti := 1 to nIter do
  begin

    time := time + dt;

    Caption := 'Iteration = ' + IntToStr(ti) + ', Time = ' + Format('%.3f', [time]) + ' s';

    T0 := CopyObj(T);

    bT := SparseMatMult(M, T0);

    b := TVMobj.Create(b.Rows, b.Cols);

    for ii := 0 to Gmsh.NbNodes - 1 do
    begin

      if IsFixed[ii] then
      begin

        // Penalty method: factor 1000
        b[ii,0] := 1000 * Gmsh.NodeBCValue[ii];

      end;

    end;

    b := b + bT;

    //ViewValues(b);

    // Iterative
    //T := FGMRESSolve(A, b);

    // UMFPACK
    // ssUmfPack + mtSymmPosDef in the original -> direct solve, SPD.
    T := PardisoSolve(A, b, True);

    (******************** PLOT VALUES ********************)

    Series1.Clear;

    Chart1.LeftAxis.Title.Caption := 'Error (%)';
    //Chart1.LeftAxis.Range.Min := 0;
    //Chart1.LeftAxis.Range.Max := 100;
    //Chart1.LeftAxis.Range.UseMin := True;
    //Chart1.LeftAxis.Range.UseMax := True;

    for ii := 0 to Gmsh.NbNodes - 1 do
    begin

      if (CheckBox1.Checked) then
      begin
        Analytical.TransientHeatConduction2D(Gmsh.CoordX[ii] + 0.5, Gmsh.CoordY[ii] + 0.5, time, 1.0, Ta);

        Series1.AddXY(ii, Abs(Ta - T[ii,0]) * 100);

      end;

    end;

    //Series1.SortByLabels();

    Series1.Title := '';

    Chart1.Invalidate;

    // Save results
    if CheckBox2.Checked then
    begin

      for ii := 0 to Gmsh.NbNodes - 1 do
      begin

        v[ii] := T[ii,0];

      end;

    end;

    Gmsh.OpenFile('..\Data\tvalid_' + Format('%.3d', [ti-1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  Analytical.Free;

  (******************** END ITERATION ********************)

  Screen.Cursor := crDefault;

  Face_T3V1.Free;
  Face_Q4V1.Free;
  Brick_T4V1.Free;
  Brick_H8V1.Free;
  Brick_W6V1.Free;

  Gmsh.Free;

  if CheckBox2.Checked then
  begin

    // Windows' ShellExecute (unlike a Unix shell) never expands wildcards
    // in its Parameters string - a literal 'tvalid_*.pos' argument reaches
    // gmsh.exe unexpanded and gmsh opens with an empty session. Build the
    // actual file list ourselves instead, sorted so the zero-padded
    // tvalid_NNN.pos sequence combines in the correct time order.
    GmshFiles := TStringList.Create;
    try
      GmshFiles.Sorted := True;

      if FindFirst('..\Data\tvalid_*.pos', faAnyFile, GmshSR) = 0 then
      begin
        repeat
          GmshFiles.Add(GmshSR.Name);
        until FindNext(GmshSR) <> 0;
        FindClose(GmshSR);
      end;

      GmshFileList := '';
      for ii := 0 to GmshFiles.Count - 1 do
        GmshFileList := GmshFileList + '..\Data\' + GmshFiles[ii] + ' ';

      if GmshFileList <> '' then
        ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', PChar(GmshFileList + '-combine -noview'), nil, SW_SHOWNORMAL);

    finally
      GmshFiles.Free;
    end;

  end;

end;

procedure TForm26.FormCreate(Sender: TObject);
begin

  ComboBox1.AddItem('TRI', nil);
  ComboBox1.AddItem('QUAD', nil);
  ComboBox1.AddItem('TETRA', nil);
  ComboBox1.AddItem('HEXA', nil);
  ComboBox1.AddItem('PRISM', nil);

  ComboBox1.ItemIndex := 0;

end;

end.
