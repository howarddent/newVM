program Project41;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit41 in 'Unit41.pas' {Form41},
  CXS.FEMLAP.Edge_B2V1 in '..\..\Source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Element in '..\..\source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Face_Q4V2 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V2.pas',
  CXS.FEMLAP.Face_T3V2 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V2.pas',
  CXS.FEMLAP.Node in '..\..\Source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Penalty in '..\..\Source\Imposer\CXS.FEMLAP.Penalty.pas',
  CXS.FEMLAP.Assembly in '..\..\Source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.ShellExec in '..\..\Source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm41, Form41);
  Application.Run;
end.
