program Project37;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit37 in 'Unit37.pas' {Form37},
  CXS.FEMLAP.ThermalEngine in '..\..\Source\Applications\CXS.FEMLAP.ThermalEngine.pas',
  CXS.FEMLAP.Assembly in '..\..\Source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Brick_H8V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_H8V1.pas',
  CXS.FEMLAP.Brick_T4V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_T4V1.pas',
  CXS.FEMLAP.Brick_W6V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_W6V1.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\Source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Element in '..\..\Source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Element_Brick in '..\..\Source\Elements\CXS.FEMLAP.Element_Brick.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Face_Q4V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V1.pas',
  CXS.FEMLAP.Face_T3V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V1.pas',
  CXS.FEMLAP.Node in '..\..\Source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Expression in '..\..\Source\Expression\CXS.FEMLAP.Expression.pas',
  CXS.FEMLAP.Penalty in '..\..\Source\Imposer\CXS.FEMLAP.Penalty.pas',
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.ShellExec in '..\..\Source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas',
  CXS.FEMLAP.EngineData in '..\..\Source\Applications\CXS.FEMLAP.EngineData.pas';

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.CreateForm(TForm37, Form37);
  Application.Run;
end.
