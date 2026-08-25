program Project42;

{$mode delphi}{$H+}

uses
  Interfaces, // this includes the LCL widgetset
  Forms, cblas,
  Unit42 in 'Unit42.pas' {Form42},
  CXS.FEMLAP.Edge_B2V1 in '..\..\Source\Elements\CXS.FEMLAP.Edge_B2V1.pas',
  CXS.FEMLAP.Element in '..\..\source\Elements\CXS.FEMLAP.Element.pas',
  CXS.FEMLAP.Element_Edge in '..\..\Source\Elements\CXS.FEMLAP.Element_Edge.pas',
  CXS.FEMLAP.Element_Face in '..\..\Source\Elements\CXS.FEMLAP.Element_Face.pas',
  CXS.FEMLAP.Face_Q4V2 in '..\..\Source\Elements\CXS.FEMLAP.Face_Q4V2.pas',
  CXS.FEMLAP.Face_T3V2 in '..\..\Source\Elements\CXS.FEMLAP.Face_T3V2.pas',
  CXS.FEMLAP.Node in '..\..\Source\Elements\CXS.FEMLAP.Node.pas',
  CXS.FEMLAP.Assembly in '..\..\Source\Assembly\CXS.FEMLAP.Assembly.pas',
  CXS.FEMLAP.Penalty in '..\..\Source\Imposer\CXS.FEMLAP.Penalty.pas',
  CXS.FEMLAP.Gmsh in '..\..\Source\Mesh\CXS.FEMLAP.Gmsh.pas',
  CXS.FEMLAP.Exceptions in '..\..\Source\System\CXS.FEMLAP.Exceptions.pas',
  CXS.FEMLAP.ShellExec in '..\..\Source\System\CXS.FEMLAP.ShellExec.pas',
  CXS.FEMLAP.StructuralEngine in '..\..\Source\Applications\CXS.FEMLAP.StructuralEngine.pas',
  CXS.FEMLAP.Expression in '..\..\Source\Expression\CXS.FEMLAP.Expression.pas',
  CXS.FEMLAP.Extrapolation in '..\..\Source\Algebra\CXS.FEMLAP.Extrapolation.pas',
  CXS.FEMLAP.EngineData in '..\..\Source\Applications\CXS.FEMLAP.EngineData.pas';

{$R *.res}

begin
  InitializeCBLAS;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm42, Form42);
  Application.Run;
end.
