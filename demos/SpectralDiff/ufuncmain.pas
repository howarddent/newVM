unit ufuncmain;

{*******************************************************************************

     Main form for the SpectralDiff demo: differentiates
     f(x) = exp(x)*sin(5x) on a Chebyshev grid via DCT-I (newVM.pas's
     DCT1), using the classic coefficient-space recursion from Trefethen's
     "Spectral Methods in MATLAB" (Recurr, below) - ported from the
     original raw-FFTW3 demo's recurr() so it now goes through TVMobj and
     DCT1 instead of calling fftw_plan_r2r_1d/fftw_execute_r2r directly.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, Dialogs,
  TAGraph, TASeries,
  newVM, hirestimer;

const
  N = 32;
  GridSize = N+1;
  Logical_N = 2*N;

type

  { TForm1 }

  TForm1 = class(TForm)
    Button1: TButton;
    Chart1: TChart;
    Chart1LineSeries1: TLineSeries;
    Chart1LineSeries2: TLineSeries;
    Chart1LineSeries3: TLineSeries;
    Chart1LineSeries4: TLineSeries;
    Chart2: TChart;
    Chart2LineSeries1: TLineSeries;
    Memo1: TMemo;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    xv, v1, v3 : TVMobj;   //Chebyshev grid points, function values, exact derivative
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

// Differentiates a Chebyshev coefficient series (as produced by DCT1) via
// the recursion c'[N]=0, c'[N-1]=N*Logical_N*c[N]/2, c'[i-1]=2*i*c[i]+c'[i+1]
// - ported verbatim (just re-expressed over TVMobj) from the original
// fftw3 demo's recurr().
function Recurr(const InVec: TVMobj): TVMobj;
var
  i : integer;
begin
  Result := TVMobj.Create(1, GridSize);
  Result[0, N] := 0;
  Result[0, N-1] := 0.5 * Logical_N * InVec[0, N];
  for i := N-1 downto 1 do
    Result[0, i-1] := 2*i*InVec[0, i] + Result[0, i+1];
end;

procedure TForm1.FormCreate(Sender: TObject);
var
  i : integer;
  x : Double;
begin
  xv := TVMobj.Create(1, GridSize);
  v1 := TVMobj.Create(1, GridSize);
  v3 := TVMobj.Create(1, GridSize);
  for i := 0 to N do begin
    x := cos(Pi*i/N);
    xv[0, i] := x;
    v1[0, i] := exp(x)*sin(5*x);
    v3[0, i] := exp(x)*(sin(5*x)+5*cos(5*x));  //exact derivative, for comparison
    Chart1LineSeries1.AddXY(xv[0, i], v1[0, i]);
    Chart1LineSeries2.AddXY(xv[0, i], v1[0, i]);
  end;
  Memo1.Lines.Add('Grid ready: ' + IntToStr(GridSize) + ' Chebyshev points');
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  coeffs, coeffsDeriv, deriv : TVMobj;
  j : integer;
  elapsedUs : Int64;
begin
  Profiler.Start;
  coeffs := DCT1(v1);                      //grid values -> scaled Chebyshev coefficients
  coeffsDeriv := Recurr(coeffs);           //differentiate the Chebyshev series
  deriv := DCT1(coeffsDeriv) / Logical_N;  //DCT-I is self-inverse, up to this scale
  elapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time for spectral diff: ' + FloatToStr(elapsedUs/1000) + ' ms');

  for j := 0 to N do begin
    Chart1LineSeries3.AddXY(xv[0, j], deriv[0, j]);
    Chart1LineSeries4.AddXY(xv[0, j], v3[0, j]);
    Chart2LineSeries1.AddXY(xv[0, j], v3[0, j]-deriv[0, j]);
  end;
end;

end.
