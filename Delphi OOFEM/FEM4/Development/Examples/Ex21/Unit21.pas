unit Unit21;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Analytical, CXS.FEMLAP.Edge_B2V1, ExtCtrls;

type
  TForm21 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form21: TForm21;

implementation

{$R *.lfm}

procedure TForm21.Button1Click(Sender: TObject);
var

  ii, jj, kk, n: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Edge_B2V1 : TEdge_B2V1;

  // Assembly
  Assembly : TAssembly;

  // Element stiffness and mass matrix
  Me : TVMobj;
  Ke : TVMobj;

  be : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1, V2: TDoubleArray;

  // Global stiffness and mass matrix
  A, M, K : TVMSparseMtx;

  y : TVMobj;
  b: TVMobj;

  // Unknown vector
  T0, T: TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode: DWORD;

  time, dt : Double;

  // BC's
  diag : TVMobj;

  bT : TVMobj;

  Analytical : TAnalytical;
  Ta : Double;
  Terr : TVMobj;

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  i: Integer;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\tbeam1D.geo');
  Gmsh.GenerateLine(1, 0.049, GMSH_BEAM);
  Gmsh.Close;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\tbeam1D.geo', '-3'], ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\tbeam1D.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 4);
  SetLength(C1, Gmsh.NbElements * 4);
  SetLength(V1, Gmsh.NbElements * 4);
  SetLength(V2, Gmsh.NbElements * 4);

  Edge_B2V1 := TEdge_B2V1.Create;

  (******************** TIME INTERVAL ********************)
  dt := 0.005;

  (******************** MATRIX SETUP ********************)

  n := 0;

  for ii := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[ii] = GMSH_BEAM then
    begin

      for jj := 0 to 1 do
      begin
        Edge_B2V1.NodeId[jj] := Gmsh.ElementNode[ii, jj];
      end;

      for jj := 0 to 1 do
      begin
        Edge_B2V1.CoordX[jj] := Gmsh.CoordX[Edge_B2V1.NodeId[jj]];
        Edge_B2V1.CoordY[jj] := Gmsh.CoordY[Edge_B2V1.NodeId[jj]];
        Edge_B2V1.CoordZ[jj] := Gmsh.CoordZ[Edge_B2V1.NodeId[jj]];
      end;

      Edge_B2V1.Transient := True;

      Edge_B2V1.TimeInterval := dt;

      Edge_B2V1.Calc;

      Ke := Edge_B2V1.K;
      Me := Edge_B2V1.M;

      for jj := 0 to 1 do
      begin
        for kk := 0 to 1 do
        begin
          R1[n] := Edge_B2V1.NodeId[jj];
          C1[n] := Edge_B2V1.NodeId[kk];
          V1[n] := Ke[jj,kk];
          V2[n] := Me[jj,kk];
          Inc(n);
        end;
      end;

    end;

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);
  SetLength(V2, n);

  K := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  M := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V2);

  A := SparseAdd(K, M);

  (******************** CREATE SOURCE VECTOR ********************)
  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** IMPOSE BOUNDARY CONDITIONS ********************)

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    if (Abs(Gmsh.CoordX[ii] - 1) < 1E-8) then
    begin
      Gmsh.NodeBCIsFixed[ii] := True;
      Gmsh.NodeBCValue[ii] := 0;
    end;

  end;

  diag := SparseDiag(A);

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    if Gmsh.NodeBCIsFixed[ii] = True then
    begin

      // Penalty method: factor 1000
      diag[ii,0] := 1000;

    end;

  end;

  SetDiagonal(A, diag);

  // Instructing UMFPACK to maintain the factorisation (A.SparsePattern :=
  // sppNumeric in the original) no longer applies - PardisoSolve always
  // does a fresh one-shot analysis+factorisation+solve.

  (******************** SET INITIAL CONDITIONS ********************)

  T := TVMobj.Create(Gmsh.NbNodes, 1);

  T := Fill(T, 1);

  SetLength(v, T.Rows);

  (******************** START ITERATION ********************)

  time := 0;

  for ti := 1 to 10 do
  begin

    time := time + dt;

    T0 := CopyObj(T);

    bT := SparseMatMult(M, T0);

    b := TVMobj.Create(b.Rows, b.Cols);

    for ii := 0 to Gmsh.NbNodes - 1 do
    begin

      if Gmsh.NodeBCIsFixed[ii] = True then
      begin

        // Penalty method: factor 1000
        b[ii,0] := 1000 * Gmsh.NodeBCValue[ii];

      end;

    end;

    b := b + bT;

    //ViewValues(b);

    // ssUmfPack + mtGeneral in the original -> direct solve, general
    // (unsymmetric) matrix type - PardisoSolve(...,False).
    T := PardisoSolve(A, b, False);

    for ii := 0 to Gmsh.NbNodes - 1 do
    begin

      v[ii] := T[ii,0];

    end;

    Gmsh.OpenFile('..\Data\tbeam1D_' + Format('%.3d', [ti-1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  (******************** END ITERATION ********************)

  Screen.Cursor := crDefault;

  (******************** CALCULATE ERROR ********************)

  Terr := TVMobj.Create(T.Rows, 1);

  Analytical := TAnalytical.Create;

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    Analytical.TransientHeatConduction1D(Gmsh.CoordX[ii], time, 1.0, Ta);

    Terr[ii,0] := T[ii,0] - Ta;

  end;

  //ViewValues(Terr);

  Analytical.Free;

  Edge_B2V1.Free;

  Gmsh.Free;

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'tbeam1D_*.pos' argument reaches
  // gmsh.exe unexpanded, matches no real file, and gmsh opens with an
  // empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded tbeam1D_NNN.pos sequence combines in the correct
  // time order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\tbeam1D_*.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
    begin
      ShowMessage('No tbeam1D_*.pos result files found in ..\Data - run Calculate first.');
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

end.
