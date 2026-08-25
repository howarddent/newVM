program Project15;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit15 in 'Unit15.pas' {Form1},
  CXS.FEMLAP.Element in '..\..\source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Face_T3V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V1.pas',
  CXS.FEMLAP.Node in '..\..\source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Gmsh in '..\..\source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.ShellExec in '..\..\source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.Torsion in '..\..\Source\Applications\CXS.FEMLAP.Torsion.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Element_Brick in '..\..\Source\Elements\CXS.FEMLAP.Element_Brick.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
