unit uplot3dmain;

{*******************************************************************************

     Main form for the Plot3D demo. Builds a real TVMobj matrix (see
     newVM.pas) sampling z = sin(r)/r, r = sqrt(x^2+y^2) - the classic
     "sinc ripple" surface - over a 51x51 grid, then hands it to a
     TVMPlot3D component (Graphs/uVMPlot3D.pas) rather than hand-rolling
     OpenGL surface-rendering code here: TVMPlot3D is created and parented
     to this form entirely in code (FormCreate), the same way Plot2D's
     demo uses TVMPlot2D. See uVMPlot3D.pas for the component itself -
     its rendering approach (world-scaled height field, Gouraud lighting,
     built-in mouse-drag-to-rotate/wheel-to-zoom camera) is documented
     there, not duplicated here. WireframeCheckBox/ResetViewButton simply
     forward to the component's Wireframe property and ResetView method.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  newVM, uVMPlot3D;

type

  { TForm1 }

  TForm1 = class(TForm)
    ControlPanel: TPanel;
    WireframeCheckBox: TCheckBox;
    ShowAxesCheckBox: TCheckBox;
    LevelCurvesCheckBox: TCheckBox;
    ResetViewButton: TButton;
    HintLabel: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure WireframeCheckBoxChange(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure LevelCurvesCheckBoxChange(Sender: TObject);
  private
    FPlot: TVMPlot3D;
    function BuildDemoMatrix: TVMobj;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FPlot := TVMPlot3D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'z = sin(r)/r  (sinc ripple)';
  FPlot.XAxisTitle := 'Column';
  FPlot.YAxisTitle := 'Row';
  FPlot.ZAxisTitle := 'Value';
  FPlot.SetData(BuildDemoMatrix);
end;

// z = sin(r)/r, r = sqrt(x^2+y^2), x,y in [-Extent,Extent] - the classic
// "sombrero"/sinc-ripple demo surface. r=0's removable singularity (limit
// sin(r)/r -> 1) is handled explicitly rather than dividing by ~0.
function TForm1.BuildDemoMatrix: TVMobj;
const
  Rows = 51; Cols = 51;
  Extent = 6.0;
var
  M: TVMobj;
  r, c: Integer;
  x, y, dist: Double;
begin
  M := TVMobj.Create(Rows, Cols);
  for r := 0 to Rows - 1 do begin
    y := -Extent + 2 * Extent * r / (Rows - 1);
    for c := 0 to Cols - 1 do begin
      x := -Extent + 2 * Extent * c / (Cols - 1);
      dist := Sqrt(x * x + y * y);
      if dist < 1e-6 then
        M[r, c] := 1.0
      else
        M[r, c] := Sin(dist) / dist;
    end;
  end;
  result := M;
end;

procedure TForm1.ResetViewButtonClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

procedure TForm1.WireframeCheckBoxChange(Sender: TObject);
begin
  FPlot.Wireframe := WireframeCheckBox.Checked;
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.LevelCurvesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowLevelCurves := LevelCurvesCheckBox.Checked;
end;

end.
