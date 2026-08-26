unit Unit18;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls,
  newVM, newVMsparse,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Brick_H8V1, CXS.FEMLAP.Brick_W6V1;

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

  Brick_H8V1 : TBrick_H8V1;
  Brick_W6V1 : TBrick_W6V1;

  NodeId : Array[0..7] of Integer;

  cx, cy, cz : Array[0..7] of Double;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // Diagonal
  diag : TVMobj;

  // Output data
  v : TDoubleArray;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\prism.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);

  Brick_H8V1 := TBrick_H8V1.Create;
  Brick_W6V1 := TBrick_W6V1.Create;

  Fg := TVMobj.Create(Gmsh.NbNodes, 1);

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_HEXA then
    begin

      for j := 0 to 7 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Brick_H8V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 7 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Brick_H8V1.CoordX[j] := cx[j];
        Brick_H8V1.CoordY[j] := cy[j];
        Brick_H8V1.CoordZ[j] := cz[j];
      end;

      Brick_H8V1.Calc;

      // Set convection on face !!!
      Brick_H8V1.SetSourceOnFace(3, 1, 0.5);

      Ke := Brick_H8V1.K;
      Fe := Brick_H8V1.b;

      for j := 0 to 7 do
      begin
        for k := 0 to 7 do
        begin
          R1[n] := NodeId[j];
          C1[n] := NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

      for j := 0 to 7 do
        Fg[NodeId[j],0] := Fg[NodeId[j],0] + Fe[j,0];

    end
    else if Gmsh.ElementType[i] = GMSH_PRISM then
    begin

      for j := 0 to 5 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Brick_W6V1.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 5 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Brick_W6V1.CoordX[j] := cx[j];
        Brick_W6V1.CoordY[j] := cy[j];
        Brick_W6V1.CoordZ[j] := cz[j];
      end;

      Brick_W6V1.Calc;

      Ke := Brick_W6V1.K;
      Fe := Brick_W6V1.b;

      for j := 0 to 5 do
      begin
        for k := 0 to 5 do
        begin
          R1[n] := NodeId[j];
          C1[n] := NodeId[k];
          V1[n] := Ke[j,k];
          Inc(n);
        end;
      end;

      for j := 0 to 5 do
        Fg[NodeId[j],0] := Fg[NodeId[j],0] + Fe[j,0];

    end
    else
    begin

      raise Exception.Create('Error: Only hexahedral and prism supported.');

    end;

  end;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  for i := 0 to n-1 do
  begin

    if (R1[i] > Gmsh.NbNodes) or (C1[i] > Gmsh.NbNodes) then
      raise Exception.Create('Problem');

  end;

  // Build global stiffness matrix
  Kg := TripletsToSparse(Gmsh.NbNodes,Gmsh.NbNodes,R1,C1,V1);

  // Set boundary conditions
  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if (Abs(Gmsh.CoordX[i]) < 1E-3) then
    begin
      Gmsh.NodeBCIsFixed[i] := True;
      Gmsh.NodeBCValue[i] := 1;
    end;
  end;

  diag := SparseDiag(Kg);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    if Gmsh.NodeBCIsFixed[i] = True then
    begin

      // Penalty method: factor 1000
      diag[i,0] := 1000;
      Fg[i,0] := 1000 * Gmsh.NodeBCValue[i];

    end;

  end;

  SetDiagonal(Kg, diag);

  // ssUmfPack + mtSymmetric in the original -> direct solve, treated as
  // symmetric positive-definite - PardisoSolve(...,True). This FEM
  // conductivity stiffness matrix (with a positive-penalty-factor
  // diagonal for the Dirichlet BCs) is genuinely SPD in practice, unlike
  // the plain mtGeneral/mtSymmPosDef cases the solver-mapping table
  // documents explicitly - see newVMsparse.pas's own header comment.
  ug := PardisoSolve(Kg, Fg, True);

  Screen.Cursor := crDefault;

  //ViewValues(ug);

  SetLength(v, ug.Rows);

  for i := 0 to Gmsh.NbNodes - 1 do
    v[i] := ug[i,0];

  Gmsh.OpenFile('..\Data\prism.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Brick_H8V1.Free;
  Brick_W6V1.Free;

  Gmsh.Free;

  //ShellExecute(Handle,'open', 'gmsh', '..\Data\hexa.pos', nil, SW_SHOWNORMAL) ;
  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\prism.pos', nil, SW_SHOWNORMAL) ;

end;

end.
