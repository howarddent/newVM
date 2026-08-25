unit Unit24;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, newVM, newVMsparse, ShellApi, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1;

type
  TForm24 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form24: TForm24;

implementation

{$R *.lfm}

procedure TForm24.Button1Click(Sender: TObject);
var

  ii, jj, kk, n: Integer;

  ti : Integer;

  // Gmsh data
  Gmsh : TGmsh;

  NbNodes : Integer;

  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;

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
  A, K, M : TVMSparseMtx;

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

  SR: TSearchRec;
  Files: TStringList;
  FileList: String;
  i: Integer;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\transient_plate.geo -3 -format msh1', ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\transient_plate.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 16);
  SetLength(C1, Gmsh.NbElements * 16);
  SetLength(V1, Gmsh.NbElements * 16);
  SetLength(V2, Gmsh.NbElements * 16);

  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;

  // Time interval
  dt := 0.01;

  n := 0;

  for ii := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[ii] = GMSH_TRI then
    begin

      for jj := 0 to 2 do
      begin
        Face_T3V1.NodeId[jj] := Gmsh.ElementNode[ii, jj];
      end;

      for jj := 0 to 2 do
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

      for jj := 0 to 2 do
      begin
        for kk := 0 to 2 do
        begin
          R1[n] := Face_T3V1.NodeId[jj];
          C1[n] := Face_T3V1.NodeId[kk];
          V1[n] := Ke[jj,kk];
          V2[n] := Me[jj,kk];
          Inc(n);
        end;
      end;

    end;

    if Gmsh.ElementType[ii] = GMSH_QUAD then
    begin

      for jj := 0 to 3 do
      begin
        Face_Q4V1.NodeId[jj] := Gmsh.ElementNode[ii, jj];
      end;

      for jj := 0 to 3 do
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

      for jj := 0 to 3 do
      begin
        for kk := 0 to 3 do
        begin
          R1[n] := Face_Q4V1.NodeId[jj];
          C1[n] := Face_Q4V1.NodeId[kk];
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

  // Build global stiffness matrix
  K := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  M := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V2);

  A := SparseAdd(K, M);

  (******************** CREATE SOURCE VECTOR ********************)
  b := TVMobj.Create(Gmsh.NbNodes, 1);

  (******************** IMPOSE BOUNDARY CONDITIONS ********************)

  for ii := 0 to Gmsh.NbNodes - 1 do
  begin

    if (Abs(Gmsh.CoordX[ii] - 0.5) < 1E-8) and (Abs(Gmsh.CoordY[ii] - 0.5) < 1E-8) then
    begin
      Gmsh.NodeBCIsFixed[ii] := True;
      Gmsh.NodeBCValue[ii] := 1;
    end;

    if (Abs(Gmsh.CoordX[ii] - 2) < 1E-8) then
    begin
      Gmsh.NodeBCIsFixed[ii] := True;
      Gmsh.NodeBCValue[ii] := 1;
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

  T := Fill(T, 0);

  SetLength(v, T.Rows);

  (******************** START ITERATION ********************)

  time := 0;

  for ti := 1 to 100 do
  begin

    time := time + dt;

    Caption := 'Iteration = ' + IntToStr(ti) + ', Time = ' + FloatToStr(time);

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

    Gmsh.OpenFile('..\Data\transient_plate_' + Format('%.3d', [ti-1]) + '.pos');
    Gmsh.WriteViewScalarNode('T', v);
    Gmsh.Close;

  end;

  (******************** END ITERATION ********************)

  Screen.Cursor := crDefault;

  Face_T3V1.Free;
  Face_Q4V1.Free;

  Gmsh.Free;

  // Windows' ShellExecute (unlike a Unix shell) never expands wildcards in
  // its Parameters string - a literal 'transient_plate_*.pos' argument
  // reaches gmsh.exe unexpanded, matches no real file, and gmsh opens with
  // an empty session. Build the actual file list ourselves instead, sorted
  // so the zero-padded transient_plate_NNN.pos sequence combines in the
  // correct time order.
  Files := TStringList.Create;
  try
    Files.Sorted := True;

    if FindFirst('..\Data\transient_plate_*.pos', faAnyFile, SR) = 0 then
    begin
      repeat
        Files.Add(SR.Name);
      until FindNext(SR) <> 0;
      FindClose(SR);
    end;

    if Files.Count = 0 then
    begin
      ShowMessage('No transient_plate_*.pos result files found in ..\Data - run Calculate first.');
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
