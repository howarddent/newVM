unit Unit33;

{$mode delphi}{$H+}

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, ExtCtrls, TAGraph, TASeries, StdCtrls, CXS.FEMLAP.Analytical;

type
  TForm33 = class(TForm)
    Button1: TButton;
    Chart1: TChart;
    Series1: TLineSeries;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form33: TForm33;

implementation

{$R *.lfm}

procedure TForm33.Button1Click(Sender: TObject);
var

  i : Integer;

  x : Double;

  T : Double;

  Analytical : TAnalytical;

begin

  i := 0;

  x := 0;

  Series1.Clear;

  Analytical := TAnalytical.Create;

  while (x < 11)  do
  begin

    Analytical.SteadyStateHeatConvectionRadiation1D(x, 1, 1E-12, 3/2/5.6704E-8, 1, 1, 1, T);

    Series1.AddXY(x, T);

    Inc(i);

    x := x + 1;

  end;

  Analytical.Free;

end;

end.
