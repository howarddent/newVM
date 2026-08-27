unit Unit32;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls,
  newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Edge_B2V1, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.Penalty,
  ExtCtrls, TAGraph, TASeries, TAChartAxis, TATransformations;

type
  TForm32 = class(TForm)
    Button1: TButton;
    Chart1: TChart;
    Series1: TLineSeries;
    CheckBox1: TCheckBox;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form32: TForm32;

implementation

{$R *.lfm}

procedure TForm32.FormCreate(Sender: TObject);
var
  Transf: TChartAxisTransformations;
  LogTransf: TLogarithmAxisTransform;
begin

  // Original .dfm had LeftAxis.Logarithmic := True (a TeeChart-only
  // boolean, no TAChart equivalent property) - TAChart's real mechanism
  // for a log-scaled axis is attaching a TLogarithmAxisTransform via a
  // TChartAxisTransformations component, done here in code since neither
  // class is a plain published-property target the .lfm streamer can set
  // directly on TChartAxis itself.
  Transf := TChartAxisTransformations.Create(Self);
  LogTransf := TLogarithmAxisTransform.Create(Self);
  LogTransf.Transformations := Transf;
  Chart1.LeftAxis.Transformations := Transf;

end;

procedure TForm32.Button1Click(Sender: TObject);
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

  // Residual
  R : TVMobj;
  Residual : Double;

  // Output data
  v : TDoubleArray;

  ExitCode: DWORD;

  nIter : Integer;

  time, dt : Double;

  bT : TVMobj;

  Assembly : TAssembly;

  MeshSize : Double;

  Penalty : TPenalty;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;

  T1, Tinf, Te0 : Double;
  teta : Double;

begin

  Gmsh := TGmsh.Create;

  (******************** PRE-PROCESSING ********************)

  Caption := 'Building geometry...';

  MeshSize := 0.025;

  T1 := 100;
  Tinf := 250;

  Gmsh.OpenFile('..\Data\vrad.geo');
  Gmsh.GenerateRectangle(1, 1, MeshSize, GMSH_TRI);
  //Gmsh.GenerateRectangle(1, 1, MeshSize, GMSH_QUAD);
  Gmsh.Close;

  Caption := 'Meshing...';

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\vrad.geo', '-3'], ExitCode, 60000, True);

  Caption := 'Loading mesh...';

  Gmsh.OpenFile('..\Data\vrad.msh');
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

  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[ii] := False;

    if (Abs(Gmsh.CoordX[ii] - 1.0) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := T1;
    end;

    if (Abs(Gmsh.CoordY[ii] - 1.0) < 1E-8) then
    begin
      IsFixed[ii] := True;
      Values[ii] := T1;
    end;

  end;

  (******************** CREATE SYSTEM ********************)

  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** TIME INTERVAL ********************)
  dt := 0.1;

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 100);

  (******************** START ITERATION ********************)

  SetLength(v, T.Rows);

  time := 0;

  nIter := 200;

  Series1.Clear;

  Series1.Title := 'Residual';

  for ti := 1 to nIter do
  begin

    time := time + dt;

    //Caption := 'Time = ' + Format('%.3f', [time]) + ' s';

    T0 := CopyObj(T);

    (******************** RESET SOURCE VECTOR ********************)

    b := TVMobj.Create(b.Rows, b.Cols);

    (******************** MATRIX SETUP ********************)

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

        for jj := 0 to NbNodes -  1 do
        begin
          if (Face_T3V1.CoordX[(jj + 0) mod NbNodes] = 0) and (Face_T3V1.CoordX[(jj + 1) mod NbNodes] = 0) then
          begin

            Te0 := (T0[Face_T3V1.NodeId[(jj + 0) mod NbNodes],0] + T0[Face_T3V1.NodeId[(jj + 1) mod NbNodes],0]) * 0.5;

            teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

            Face_T3V1.SetSourceOnEdge(jj, 0.7, teta, Tinf);

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

        Face_Q4V1.Calc;

        for jj := 0 to NbNodes - 1 do
        begin

          if (Face_Q4V1.CoordX[(jj + 0) mod NbNodes] = 0) and (Face_Q4V1.CoordX[(jj + 1) mod NbNodes] = 0) then
          begin

            Te0 := (T0[Face_Q4V1.NodeId[(jj + 0) mod NbNodes],0] + T0[Face_Q4V1.NodeId[(jj + 1) mod NbNodes],0]) * 0.5;

            teta := (Te0*Te0*Te0 + Tinf*Te0*Te0 + Tinf*Tinf*Te0 + Tinf*Tinf*Tinf);

            Face_Q4V1.SetSourceOnEdge(jj, 0.7, teta, Tinf);

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

    (******************** IMPOSE BOUNDARY CONDITIONS ********************)

    Penalty := TPenalty.Create;

    Penalty.Factor := 1000;
    Penalty.Impose(IsFixed, Values, A, b);

    Penalty.Free;

    (******************** SOLVE ********************)

    // ssIterative + itmLUGMRES in the original -> FGMRESSolve. See
    // newVMsparse.pas's own header comment for the full solver mapping.
    T := FGMRESSolve(A, b);

    R := T - T0;
    Residual := Norm(R);

    Caption := 'Residual = ' + Format('%.3e', [Residual]) + ' s';

    if CheckBox1.Checked then
    begin
      Series1.AddXY(ti + 1, Residual);
    end;

    Application.ProcessMessages;

    if Residual < 1E-5 then Break;

    //ViewValues(T);
    //ViewValues(b);

  end;

  (******************** SAVE RESULTS ********************)

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    v[ii] := T[ii,0];

  end;

  Gmsh.OpenFile('..\Data\vrad.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  ShellExecute(Handle, 'open', 'c:\gmsh\gmsh.exe', '..\Data\vrad.pos -noview', nil, SW_SHOWNORMAL);

  (******************** END ITERATION ********************)

  Edge_B2V1.Free;
  Face_T3V1.Free;
  Face_Q4V1.Free;

  Gmsh.Free;

end;

end.
