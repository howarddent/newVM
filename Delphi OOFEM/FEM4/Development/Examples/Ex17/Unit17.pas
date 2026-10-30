unit Unit17;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, newVM, newVMsparse,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Assembly, CXS.FEMLAP.Face_Q4V1, CXS.FEMLAP.ShellExec;

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

procedure TForm1.Button1Click(Sender: TObject);
var

  i, j, n: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  Face_Q4V1 : TFace_Q4V1;

  NodeId : Array[0..3] of Integer;

  cx, cy, cz : Array[0..3] of Double;

  MSize : Integer;

  // Assembly
  Assembly : TAssembly;

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

  // BC's
  IsFixed : TBooleanArray;
  Values : TDoubleArray;
  OldToNew : TIntegerArray;

  // Output data
  v : TDoubleArray;

  ExitCode : Cardinal;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute(GmshExecutable, [DataDir + 'squareq.geo', '-3'], ExitCode, 60000, True);

  Gmsh.OpenFile(DataDir + 'squareq.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  // Set boundary conditions
  SetLength(IsFixed, Gmsh.NbNodes);
  SetLength(Values, Gmsh.NbNodes);
  SetLength(OldToNew, Gmsh.NbNodes);

  n := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    IsFixed[i] := False;

    // Nodes 1 and 3 (the two corners not pinned to a single Dirichlet
    // edge value - see the sequential-overwrite BC logic below) are
    // deliberately left free rather than run through the boundary
    // checks, but still need a reduced-system slot like any other free
    // node: OldToNew must be assigned *before* incrementing n, or this
    // slot is reserved (n advances past it) without ever being pointed
    // to, and n's own row is instead written to Assembly.Add's
    // uninitialised-array default OldToNew[i]=0 - producing an
    // orphaned reduced row with no diagonal entry (PardisoSolve then
    // refuses to factorise the matrix).
    if (i = 1) or (i = 3) then
    begin
      OldToNew[i] := n;
      Inc(n);
      Continue;
    end;

    if (Abs(Gmsh.CoordX[i]) < 1E-3) then
    begin
      IsFixed[i] := True;
      Values[i] := 0;
    end;

    if (Abs(Gmsh.CoordY[i]) < 1E-3) then
    begin
      IsFixed[i] := True;
      Values[i] := 0;
    end;

    if (Abs(Gmsh.CoordX[i] - 1) < 1E-3) then
    begin
      IsFixed[i] := True;
      Values[i] := 1;
    end;

    if (Abs(Gmsh.CoordY[i] - 1) < 1E-3) then
    begin
      IsFixed[i] := True;
      Values[i] := 1;
    end;

    OldToNew[i] := n;

    if (IsFixed[i] = False) then Inc(n);

  end;

  MSize := n;

  SetLength(R1, Gmsh.NbElements * 16);
  SetLength(C1, Gmsh.NbElements * 16);
  SetLength(V1, Gmsh.NbElements * 16);

  Face_Q4V1 := TFace_Q4V1.Create;

  Fg := TVMobj.Create(MSize, 1);

  // FE Assembly and elimination

  Assembly := TAssembly.Create;

  n := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

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

      Face_Q4V1.Conductivity := 1.0;
      Face_Q4V1.Thickness := 0.1;

      Face_Q4V1.Calc;

      Ke := Face_Q4V1.K;
      Fe := Face_Q4V1.b;

      Assembly.Add(Ke, Fe, Fg, R1, C1, V1, n, 4, NodeId, MSize, IsFixed, Values, OldToNew);

    end
    else
    begin

      raise Exception.Create('Error: Only quadrangles supported.');

    end;

  end;

  Assembly.Free;

  SetLength(R1, n);
  SetLength(C1, n);
  SetLength(V1, n);

  // Build global stiffness matrix
  Kg := TripletsToSparse(MSize,MSize,R1,C1,V1);

  // ssUmfPack + mtGeneral in the original -> direct solve, general
  // (unsymmetric) matrix type - PardisoSolve(...,False). See
  // newVMsparse.pas's own header comment for the full solver mapping.
  ug := PardisoSolve(Kg, Fg, False);

  Screen.Cursor := crDefault;

  SetLength(v, Gmsh.NbNodes);

  for i := 0 to Gmsh.NbNodes - 1 do
  begin
    if IsFixed[i] = True then
      v[i] := Values[i]
    else
      v[i] := ug[OldToNew[i],0];
  end;

  Gmsh.OpenFile(DataDir + 'squareq.pos');
  Gmsh.WriteViewScalarNode('T', v);
  Gmsh.Close;

  Face_Q4V1.Free;

  Gmsh.Free;

  Sto_ShellExecute(GmshExecutable, [DataDir + 'squareq.pos'], ExitCode);

end;

end.
