unit Unit41;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ShellApi, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Assembly, CXS.FEMLAP.Penalty, CXS.FEMLAP.Face_T3V2, CXS.FEMLAP.Face_Q4V2, ExtCtrls;

type
  TForm41 = class(TForm)
    Button1: TButton;
    RadioGroup1: TRadioGroup;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form41: TForm41;

implementation

{$R *.lfm}

procedure TForm41.Button1Click(Sender: TObject);
var

  i, j, n: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  Face_T3V2 : TFace_T3V2;
  Face_Q4V2 : TFace_Q4V2;

  NodeId : Array[0..3] of Integer;
  cx, cy, cz : Array[0..3] of Double;

  // Element stiffness and load
  Ke : TVMobj;
  Fe : TVMobj;

  // Assembly
  Assembly : TAssembly;

  Penalty : TPenalty;

  // Triplet
  R1,C1: TIntegerArray;
  V1: TDoubleArray;

  // Global stiffness matrix and load
  Kg : TVMSparseMtx;
  Fg: TVMobj;

  // Unknown vector
  ug: TVMobj;

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;
  OldToNew : TIntegerArray;

  MSize : Integer;

  // Output data
  ux, uy : TDoubleArray;

  PenaltyMethod : Boolean;

  ExitCode : DWORD;

  GmshEleType: Integer;

begin

  Screen.Cursor := crHourGlass;

  PenaltyMethod := False;

  Gmsh := TGmsh.Create;

  Gmsh.OpenFile('..\Data\wall.geo');

  if RadioGroup1.ItemIndex = 0 then
    GmshEleType := GMSH_TRI
  else
    GmshEleType := GMSH_QUAD;

  Gmsh.GenerateRectangle(20, 1, 0.49, GmshEleType);

  Gmsh.Close;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\wall.geo', '-3'], ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\wall.msh');
  Gmsh.ReadMesh();
  Gmsh.Close;

  // Set boundary conditions
  SetLength(IsFixed, 2*Gmsh.NbNodes);
  SetLength(Values, 2*Gmsh.NbNodes);
  SetLength(OldToNew, 2*Gmsh.NbNodes);

  n := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[2*i + 0] := False;
    IsFixed[2*i + 1] := False;

    if Abs(Gmsh.CoordX[i]) < 1E-2 then
    begin

      IsFixed[2*i + 0] := True;
      Values[2*i + 0] := 0;

      IsFixed[2*i + 1] := True;
      Values[2*i + 1] := 0;

    end;

    OldToNew[2*i + 0] := n;

    if (IsFixed[2*i + 0] = False) then Inc(n);

    OldToNew[2*i + 1] := n;

    if (IsFixed[2*i + 1] = False) then Inc(n);

  end;

  if PenaltyMethod then
    MSize := Gmsh.NbNodes*2
  else
    MSize := n;

  SetLength(R1, Gmsh.NbElements * 64);
  SetLength(C1, Gmsh.NbElements * 64);
  SetLength(V1, Gmsh.NbElements * 64);

  Face_T3V2 := TFace_T3V2.Create;

  Face_T3V2.ElasticModulus := 30000;
  Face_T3V2.Poisson := 0;
  Face_T3V2.Thickness := 0.1;

  Face_T3V2.ReCalcD;

  Face_Q4V2 := TFace_Q4V2.Create;

  Face_Q4V2.ElasticModulus := 30000;
  Face_Q4V2.Poisson := 0;
  Face_Q4V2.Thickness := 0.1;

  Face_Q4V2.ReCalcD;

  Fg := TVMobj.Create(MSize, 1);

  // FE Assembly and elimination

  Assembly := TAssembly.Create;

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_T3V2.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 2 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_T3V2.CoordX[j] := cx[j];
        Face_T3V2.CoordY[j] := cy[j];
        Face_T3V2.CoordZ[j] := cz[j];
      end;

      Face_T3V2.Calc;

      Ke := Face_T3V2.K;
      Fe := Face_T3V2.b;

      if PenaltyMethod then
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId, 2)
      else
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 3, NodeId, MSize, IsFixed, Values, OldToNew, 2);

    end
    else if Gmsh.ElementType[i] = GMSH_QUAD then
    begin

      for j := 0 to 3 do
      begin
        NodeId[j] := Gmsh.ElementNode[i, j];
        Face_Q4V2.NodeId[j] := NodeId[j];
      end;

      for j := 0 to 3 do
      begin
        cx[j] := Gmsh.CoordX[NodeId[j]];
        cy[j] := Gmsh.CoordY[NodeId[j]];
        cz[j] := Gmsh.CoordZ[NodeId[j]];

        Face_Q4V2.CoordX[j] := cx[j];
        Face_Q4V2.CoordY[j] := cy[j];
        Face_Q4V2.CoordZ[j] := cz[j];
      end;

      Face_Q4V2.Calc;

      Ke := Face_Q4V2.K;
      Fe := Face_Q4V2.b;

      if PenaltyMethod then
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 4, NodeId, 2)
      else
        Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 4, NodeId, MSize, IsFixed, Values, OldToNew, 2);

    end
    else
    begin

      raise Exception.Create('Error: Only tris and quads supported.');

    end;

  end;

  Assembly.Free;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  if PenaltyMethod then
    MSize := Gmsh.NbNodes*2;

  // Build global stiffness matrix
  Kg := TripletsToSparse(MSize,MSize,R1,C1,V1);

  ug := TVMobj.Create(MSize, 1);

  // Set load on node 3: uy = -1;

  if PenaltyMethod then
    Fg[5,0] := -1
  else
    Fg[OldToNew[5],0] := -1;

  if PenaltyMethod then
  begin
    Penalty := TPenalty.Create;
    Penalty.Impose(IsFixed, Values, Kg, Fg);
    Penalty.Free;
  end;

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False). See
  // newVMsparse.pas's own header comment for the full solver mapping.
  ug := PardisoSolve(Kg, Fg, False);

  Screen.Cursor := crDefault;

  SetLength(ux, Gmsh.NbNodes);
  SetLength(uy, Gmsh.NbNodes);

  if PenaltyMethod then
  begin

    for i := 0 to Gmsh.NbNodes - 1 do
    begin

      ux[i] :=  ug[2*i+0,0];
      uy[i] :=  ug[2*i+1,0];

    end;

  end
  else
  begin

    for i := 0 to Gmsh.NbNodes - 1 do
    begin

      if IsFixed[2*i + 0] = True then
        ux[i] :=  Values[2*i+0]
      else
        ux[i] := ug[OldToNew[2*i+0],0];

      if IsFixed[2*i + 1] = True then
        uy[i] :=  Values[2*i+1]
      else
        uy[i] := ug[OldToNew[2*i+1],0];

    end;

  end;

  Gmsh.OpenFile('..\Data\wall.pos');
  Gmsh.WriteViewScalarNode('Ux', ux);
  Gmsh.WriteViewScalarNode('Uy', uy, False);
  Gmsh.Close;

  Face_T3V2.Free;
  Face_Q4V2.Free;

  Gmsh.Free;

  ShellExecute(Handle,'open', 'c:\gmsh\gmsh.exe', '..\Data\wall.pos', nil, SW_SHOWNORMAL) ;

end;

end.
