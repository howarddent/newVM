unit ufuncplotmain;

{*******************************************************************************

     Main form for the FunctionPlot demo. Computes y = f(x) elementwise on a
     TVMobj (1 x NumPoints row vector, see newVM.pas) and feeds the result
     into a TAChart TLineSeries.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  TAGraph, TASeries,
  newVM;

type

  { TForm1 }

  TForm1 = class(TForm)
    Chart1: TChart;
    Chart1LineSeries1: TLineSeries;
    procedure FormCreate(Sender: TObject);
  private
    procedure PlotFunction;
  end;

var
  Form1: TForm1;

const
  NumPoints = 1000;
  XMin = -10.0;
  XMax = 10.0;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  PlotFunction;
end;

// y = exp(-0.1*x^2) * sin(3*x), x in [XMin, XMax], NumPoints samples.
procedure TForm1.PlotFunction;
var
  X, Y : TVMobj;
  i : Integer;
begin
  X := TVMobj.Create(1, NumPoints);
  X.linspace(XMin, (XMax - XMin) / (NumPoints - 1));
  Y := Exp(-0.1 * Sqr(X)) * Sin(3 * X);

  Chart1LineSeries1.Clear;
  for i := 0 to NumPoints - 1 do
    Chart1LineSeries1.AddXY(X[0, i], Y[0, i]);
end;

end.
