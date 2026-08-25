unit Unit30;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, ExtCtrls, TAGraph, TASeries, CXS.FEMLAP.Analytical;

type
  TForm30 = class(TForm)
    Chart1: TChart;
    Button1: TButton;
    Series1: TLineSeries;
    Series2: TLineSeries;
    Series3: TLineSeries;
    procedure Button1Click(Sender: TObject);
  private

    { Private declarations }

    procedure GraphThickness(Series : TLineSeries; Thickness : Double; Legend : String);

  public
    { Public declarations }
  end;

var
  Form30: TForm30;

implementation

{$R *.lfm}

procedure TForm30.Button1Click(Sender: TObject);
begin

  Chart1.Title.Text.Text := 'Temperature (°C)';

  GraphThickness(Series1, 0.0015, 'Thickness = 1.5 mm');
  GraphThickness(Series2, 0.005,  'Thickness = 5 mm');
  GraphThickness(Series3, 0.100,  'Thickness = 100 mm');

end;

procedure TForm30.GraphThickness(Series : TLineSeries; Thickness: Double; Legend : String);
var

  x, T : Double;

  h, k : Double;

  Width : Double;
  Length : Double;

  Perimeter, SectionArea : Double;

  Analytical : TAnalytical;

begin

  h := 10;
  k := 52.019;

  Length := 0.3;
  Width := 0.025;

  Perimeter := 2 * Thickness + 2 * Width;
  SectionArea := Thickness * Width;

  Analytical := TAnalytical.Create;

  Series.Clear;

  Series.Title := Legend;

  x := 0;

  while (x < Length)  do
  begin

    Analytical.SteadyStateHeatConduction1D(x, 100, 20, h, 20, k, Perimeter, SectionArea, Length, T);

    Series.AddXY(x, T);

    x := x + 0.001;

  end;

  //Analytical.SteadyStateHeatConduction1D(0.097, 100, 20, h, 20, k, Perimeter, SectionArea, Length, T);
  //ShowMessage(FloatToStr(T));

  Analytical.Free;

end;

end.
