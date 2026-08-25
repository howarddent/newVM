program Project17;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  CXS.FEMLAP.Element in '..\..\source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Node in '..\..\source\Elements\CXS.FEMLAP.Node.pas',
  Unit17 in 'Unit17.pas' {Form1},
  CXS.FEMLAP.Face_Q4V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V1.pas',
  CXS.FEMLAP.Gmsh in '..\..\source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Assembly in '..\..\source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.ShellExec in '..\..\source\System\CXS.FEMLAP.ShellExec.pas',
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
