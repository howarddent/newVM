unit Unit13;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, CXS.FEMLAP.Gmsh, StdCtrls, newVM, newVMsparse,
  ShellApi, CXS.FEMLAP.ShellExec, CXS.FEMLAP.Face_T3V1, CXS.FEMLAP.Face_Q4V1;

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

procedure TForm1.Button1Click(Sender: TObject);
var

  i, j, k, n: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  Face_T3V1 : TFace_T3V1;
  Face_Q4V1 : TFace_Q4V1;

  NodeId : Array[0..3] of Integer;

  cx, cy, cz : Array[0..3] of Double;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Kt : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // BC's
  bc : TVMobj;

  // Output data
  v : TDoubleArray;

  ExitCode : DWORD;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', '..\Data\shellgt.geo -3', ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\shellgt.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 16);
  SetLength(C1, Gmsh.NbElements * 16);
  SetLength(V1, Gmsh.NbElements * 16);

  Face_T3V1 := TFace_T3V1.Create;
  Face_Q4V1 := TFace_Q4V1.Create;

  Fg := TVMobj.Create(Gmsh.NbNodes, 1);

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 2 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_T3V1.CoordX[j] := cx[j];
        Face_T3V1.CoordY[j] := cy[j];
        Face_T3V1.CoordZ[j] := cz[j];
      end;

      Face_T3V1.Calc;

      Face_T3V1.Conductivity := 1.0;

      Ke := Face_T3V1.K;
      Fe := Face_T3V1.b;

      for j := 0 to 2 do
      begin
        for k := 0 to 2 do
        begin
          R1[n] := NodeId[j];
          C1[n] := NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

      Fg[NodeId[0],0] := Fg[NodeId[0],0] + Fe[0,0];
      Fg[NodeId[1],0] := Fg[NodeId[1],0] + Fe[1,0];
      Fg[NodeId[2],0] := Fg[NodeId[2],0] + Fe[2,0];

    end;

    if Gmsh.ElementType[i] = GMSH_QUAD then
    begin

      for j := 0 to 3 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_Q4V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 3 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_Q4V1.CoordX[j] := cx[j];
        Face_Q4V1.CoordY[j] := cy[j];
        Face_Q4V1.CoordZ[j] := cz[j];
      end;

      Face_Q4V1.Calc;

      Face_Q4V1.Conductivity := 1.0;

      Ke := Face_Q4V1.K;
      Fe := Face_Q4V1.b;

      for j := 0 to 3 do
      begin
        for k := 0 to 3 do
        begin
          R1[n] := NodeId[j];
          C1[n] := NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

      Fg[NodeId[0],0] := Fg[NodeId[0],0] + Fe[0,0];
      Fg[NodeId[1],0] := Fg[NodeId[1],0] + Fe[1,0];
      Fg[NodeId[2],0] := Fg[NodeId[2],0] + Fe[2,0];

    end;

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if (Abs(Gmsh.CoordZ[i]) < 1E-3) then
    begin
      Gmsh.NodeBCIsFixed[i] := True;
      Gmsh.NodeBCValue[i] := 0;
    end;

    if (Abs(Gmsh.CoordZ[i] - 2) < 1E-3) then
    begin
      Gmsh.NodeBCIsFixed[i] := True;
      Gmsh.NodeBCValue[i] := 1;
    end;

  end;

  bc := SparseDiag(Kg);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if Gmsh.NodeBCIsFixed[i] = True then
    begin

      // Penalty method: factor 1000
      bc[i,0] := 1000;
      Fg[i,0] := 1000 * Gmsh.NodeBCValue[i];

    end;

  end;

  SetDiagonal(Kg, bc);

  // UMFPACK
  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False).
  ug := PardisoSolve(Kg, Fg, False);

  // TAUCS
  (*
  Kg.SparseSolver := ssTaucs;
  Kt := TSparseMtx.Create;
  Kt.LowerTriangle(Kg, True);
  Kg.Assign(Kt);
  Kt.Free;
  *)

  // The original solves twice into the same ug - the first (general)
  // solve's result is unconditionally overwritten by this second
  // (SPD) solve, which is still against ssUmfPack since the TAUCS
  // block above stayed commented out. Preserved as two sequential
  // PardisoSolve calls so ug ends up holding exactly the same final
  // value as the original: the mtSymmPosDef solve's result.
  ug := PardisoSolve(Kg, Fg, True);

  Screen.Cursor := crDefault;

  SetLength(v, ug.Rows);

  for i := 0 to Gmsh.NbNodes - 1 do
    v[i] := ug[i,0];

  Gmsh.OpenFile('..\Data\shellgt.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Face_T3V1.Free;
  Face_Q4V1.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\shellgt.pos', nil, SW_SHOWNORMAL) ;

end;

end.
