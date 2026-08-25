program Project31;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit31 in 'Unit31.pas' {Form31},
  CXS.FEMLAP.Analytical in '..\..\Source\Analytical\CXS.FEMLAP.Analytical.pas',
  CXS.FEMLAP.Assembly in '..\..\source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Element in '..\..\source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Face_Q4V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V1.pas',
  CXS.FEMLAP.Face_T3V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V1.pas',
  CXS.FEMLAP.Node in '..\..\source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Penalty in '..\..\Source\Imposer\CXS.FEMLAP.Penalty.pas',
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.ShellExec in '..\..\source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.Brick_T4V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_T4V1.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Brick_H8V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_H8V1.pas',
  CXS.FEMLAP.Brick_W6V1 in '..\..\Source\Elements\CXS.FEMLAP.Brick_W6V1.pas',
  CXS.FEMLAP.Element_Brick in '..\..\Source\Elements\CXS.FEMLAP.Element_Brick.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.CreateForm(TForm31, Form31);
  Application.Run;
end.
