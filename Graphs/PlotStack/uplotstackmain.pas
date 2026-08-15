unit uplotstackmain;

{*******************************************************************************

     Main form for the PlotStack demo. Hands off entirely to a
     TVMPlotStack component (Graphs/uVMPlotStack.pas) - created and
     parented to this form in code, same as Plot2D's/Plot3D's demos use
     TVMPlot2D/TVMPlot3D - rather than hand-rolling any OpenGL waterfall
     rendering here. "Add Graph" builds one more phase-shifted decaying
     sine wave (BuildNextSlice) and pushes it in via FPlot.AddGraph;
     AnimateCheckBox/ShowAxesCheckBox/ResetViewButton simply forward to
     the component's Animate/ShowAxes properties and ResetView method,
     the same pattern Plot3D's demo uses for its own checkboxes/button.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls,
  newVM, uVMPlotStack;

type

  { TForm1 }

  TForm1 = class(TForm)
    ControlPanel: TPanel;
    AddGraphButton: TButton;
    AnimateCheckBox: TCheckBox;
    ShowAxesCheckBox: TCheckBox;
    ResetViewButton: TButton;
    HintLabel: TLabel;
    procedure FormCreate(Sender: TObject);
    procedure AddGraphButtonClick(Sender: TObject);
    procedure AnimateCheckBoxChange(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
  private
    FPlot: TVMPlotStack;
    FPhase: Double;
    function BuildNextSlice: TVMobj;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  FPlot := TVMPlotStack.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'Waterfall Stack';
  FPlot.XAxisTitle := 'Index';
  FPlot.YAxisTitle := 'Value';
  FPlot.ZAxisTitle := 'Time';
  FPlot.MaxSeries := 40;
end;

// One more phase-shifted decaying sine wave, cycling FPhase forward each
// call - same shape as the component's own default demo data
// (TVMPlotStack.BuildDefaultDemoSlice) but driven from this form so
// clicking "Add Graph" keeps advancing the phase rather than repeating
// the same curve.
function TForm1.BuildNextSlice: TVMobj;
const
  N = 60;
var
  M: TVMobj;
  i: Integer;
  x: Double;
begin
  M := TVMobj.Create(1, N);
  for i := 0 to N - 1 do begin
    x := i / (N - 1) * 4 * Pi;
    M[0, i] := Sin(x + FPhase) * Exp(-0.15 * x);
  end;
  FPhase := FPhase + 0.3;
  result := M;
end;

procedure TForm1.AddGraphButtonClick(Sender: TObject);
begin
  FPlot.AddGraph(BuildNextSlice);
end;

procedure TForm1.AnimateCheckBoxChange(Sender: TObject);
begin
  FPlot.Animate := AnimateCheckBox.Checked;
end;

procedure TForm1.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TForm1.ResetViewButtonClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

end.
