unit Unit15;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ShellApi, Math, newVM, newVMsparse, CXS.FEMLAP.ShellExec,
  CXS.FEMLAP.Gmsh, CXS.FEMLAP.Torsion, CXS.FEMLAP.Face_T3V1;

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

  i, j: Integer;

  // Gmsh data
  Gmsh : TGmsh;

  nt, nn, nb : Integer;

  Nodes : TDoubleArray;
  Triangles: TIntegerArray;
  Boundary : TIntegerArray;

  // Torsion class
  Torsion : TTorsion;

  J1, J2 : Double;

  s : String;

  ExitCode : DWORD;

begin

  Screen.Cursor := crHourGlass;

  Gmsh := TGmsh.Create;

  Sto_ShellExecute('c:\gmsh\gmsh.exe', ['..\Data\torsion.geo', '-3'], ExitCode, 60000, True);

  Gmsh.OpenFile('..\Data\torsion.msh');
  Gmsh.ReadMesh;
  Gmsh.Close;

  Torsion := TTorsion.Create;

  SetLength(Nodes, Gmsh.NbNodes * 3);

  nn := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

     Nodes[nn] := Gmsh.CoordX[i];
     Inc(nn);
     Nodes[nn] := Gmsh.CoordY[i];
     Inc(nn);
     Nodes[nn] := Gmsh.CoordZ[i];
     Inc(nn);

  end;

  SetLength(Nodes, nn);

  SetLength(Triangles, Gmsh.NbElements * 3);

  nt := 0;

  for i := 0 to Gmsh.NbElements - 1 do
  begin

    if Gmsh.ElementType[i] = GMSH_TRI then
    begin

      for j := 0 to 2 do
      begin
        Triangles[nt] := Gmsh.ElementNode[i, j];
        Inc(nt);
      end;

    end
    else
    begin

      raise Exception.Create('Error: Only triangles supported.');

    end;

  end;

  SetLength(Triangles, nt);

  // Set boundary conditions

  SetLength(Boundary, Gmsh.NbNodes);

  nb := 0;

  for i := 0 to Gmsh.NbNodes - 1 do
  begin

    // Constraint outer border at radius = 3
    if (Abs(sqrt(Gmsh.CoordX[i]*Gmsh.CoordX[i] + Gmsh.CoordY[i]*Gmsh.CoordY[i]) - 3) < 1E-3) then
    begin
      Boundary[nb] := i;
      Inc(nb);
    end;

  end;

  SetLength(Boundary, nb);

  // Calculated using FEM
  J1 := Torsion.CalcTorsionalConstant(Nodes, Triangles, Boundary);

  // Analytical r = 3: J = (pi r^4) / 2
  J2 := (PI * power(3, 4)) / 2;

  Screen.Cursor := crDefault;

  Torsion.Free;
  Gmsh.Free;

  s := 'Torsional constant (FEM) (J1) = ' + FloatToStr(J1) + Chr(13);
  s := s + 'Torsional constant (Analytical) (J2) = ' + FloatToStr(J2);

  ShowMessage(s);

end;

end.
