unit uplot2dmain;

{*******************************************************************************

     Main form for the Plot2D demo. Computes two related y = f(x) series
     elementwise on TVMobj row vectors (see newVM.pas) - the same base
     function as demos/FunctionPlot, plus its cosine-phase sibling - and
     hands both to a TVMPlot2D component (Graphs/uVMPlot2D.pas) rather than
     hand-rolling OpenGL plotting code here: TVMPlot2D is created and
     parented to this form entirely in code (FormCreate), the same way any
     LCL component can be instantiated and added to a form at runtime
     without needing a design-time package installed. See uVMPlot2D.pas for
     the component itself - its rendering approach (auto-fitted orthographic
     projection, GL-texture-cached title/tick text, dashed/dotted lines via
     GL_LINE_STIPPLE) is documented there, not duplicated here.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs,
  newVM, uVMPlot2D;

type

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
  private
    FPlot: TVMPlot2D;
  end;

var
  Form1: TForm1;

const
  NumPoints = 1000;
  XRangeMin = -10.0;
  XRangeMax = 10.0;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  X, YSin, YCos, Envelope: TVMobj;
begin
  X := TVMobj.Create(1, NumPoints);
  X.linspace(XRangeMin, (XRangeMax - XRangeMin) / (NumPoints - 1));
  Envelope := Exp(-0.1 * Sqr(X));
  YSin := Envelope * Sin(3 * X);   // y = exp(-0.1*x^2) * sin(3*x)
  YCos := Envelope * Cos(3 * X);   // y = exp(-0.1*x^2) * cos(3*x)

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'y = exp(-0.1x^2) . {sin(3x), cos(3x)}';
  FPlot.XAxisTitle := 'x';
  FPlot.YAxisTitle := 'y';
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'exp(-0.1x^2).sin(3x)');
  FPlot.SetSeriesStyle(1, clBlue, 1.5, plsDash, 'exp(-0.1x^2).cos(3x)');
  FPlot.SetData(X, [YSin, YCos]);
end;

end.

