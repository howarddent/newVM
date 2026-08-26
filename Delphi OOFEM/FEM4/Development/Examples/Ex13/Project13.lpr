program Project13;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit13 in 'Unit13.pas' {Form1},
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Edge_B2V1 in '..\..\Source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Face_T3V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V1.pas',
  CXS.FEMLAP.Face_Q4V1 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V1.pas',
  CXS.FEMLAP.Element in '..\..\Source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Node in '..\..\Source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Assembly in '..\..\Source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Penalty in '..\..\Source\Imposer\CXS.FEMLAP.Penalty.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Element_Brick in '..\..\Source\Elements\CXS.FEMLAP.Element_Brick.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.ShellExec in '..\..\Source\System\CXS.FEMLAP.ShellExec.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
