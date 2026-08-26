program Project21;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit21 in 'Unit21.pas' {Form21},
  CXS.FEMLAP.ShellExec in '..\..\Source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\Source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Element in '..\..\Source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Node in '..\..\Source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Assembly in '..\..\Source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Analytical in '..\..\Source\Analytical\CXS.FEMLAP.Analytical.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Element_Brick in '..\..\Source\Elements\CXS.FEMLAP.Element_Brick.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.CreateForm(TForm21, Form21);
  Application.Run;
end.
