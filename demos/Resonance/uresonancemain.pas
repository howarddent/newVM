unit uresonancemain;

{*******************************************************************************

     Main form for the Resonance demo: the impulse response and the
     magnitude response of the standard second-order system

         H(s) = wn^2 / (s^2 + 2 zeta wn s + wn^2)

     for a set of damping ratios zeta chosen in a check group, at a
     natural frequency fn (Hz) from a spin edit (wn = 2 pi fn), on two
     TVMPlot2D components stacked in a panel - impulse response above,
     magnitude response below - with the curves coloured consistently
     between the two so a damping ratio can be followed from one plot to
     the other.

     THE MATHS, AND HOW IT IS DONE ON newVM VECTORS

     Impulse response h(t), the inverse Laplace transform of H(s):

       zeta < 1  (underdamped)    h = wn/sqrt(1-z^2) e^(-z wn t) sin(wd t),
                                    wd = wn sqrt(1-z^2)
       zeta = 1  (critical)       h = wn^2 t e^(-wn t)
       zeta > 1  (overdamped)     h = wn/(2 sqrt(z^2-1)) (e^(s1 t) - e^(s2 t)),
                                    s1,2 = -z wn +/- wn sqrt(z^2-1)

     each a one-liner over the time vector T with newVM's elementwise
     Exp/Sin and the TVMobj operators - e.g. the underdamped case is
     literally  K * (Exp((-z*wn) * T) * Sin(wd * T)) , the '*' between
     two TVMobj being elementwise (the Hadamard product), as everywhere
     in this library.

     Magnitude response, with r = w/wn the frequency ratio:

       |H(j w)| = 1 / sqrt( (1 - r^2)^2 + (2 zeta r)^2 )

     newVM has no elementwise reciprocal (only '/' by a scalar), so the
     1/sqrt(D) is done as  Exp(-0.5 * Ln(D)) = D^(-1/2) with the
     elementwise Exp and Ln - two VML calls instead of a loop. The
     1 - r^2 term uses AddScalar(-Sqr(R), 1), there being no
     scalar-minus-vector operator either.

     The memo gives, per damping ratio, the figures a textbook quotes:
     the quality factor Q = 1/(2 zeta); the resonant frequency
     fr = fn sqrt(1 - 2 zeta^2) and the peak gain 1/(2 zeta sqrt(1-zeta^2))
     (both only for zeta < 1/sqrt 2 - above that the magnitude has no peak
     and falls monotonically from 1); and the damped frequency
     fd = fn sqrt(1 - zeta^2) for zeta < 1. The 2 % settling time
     4/(zeta wn) is given for every zeta.

     The time axis spans a chosen number of natural periods 1/fn (spin
     edit, default 10) at 1000 points; the frequency axis runs 0 .. 3 fn
     at 600 points, which is wide enough to show the roll-off and fine
     enough to resolve the sharpest peak offered (zeta = 0.05, Q = 10).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Spin,
  newVM, uVMPlot2D;

type

  { TForm1 }

  TForm1 = class(TForm)
    cgZeta: TCheckGroup;
    lblFn: TLabel;
    lblPeriods: TLabel;
    memResults: TMemo;
    pnlControls: TPanel;
    pnlPlots: TPanel;
    seFn: TFloatSpinEdit;
    sePeriods: TSpinEdit;
    procedure cgZetaItemClick(Sender: TObject; Index: integer);
    procedure FormCreate(Sender: TObject);
    procedure pnlPlotsResize(Sender: TObject);
    procedure seFnChange(Sender: TObject);
    procedure sePeriodsChange(Sender: TObject);
  private
    FPlotImpulse: TVMPlot2D;
    FPlotMag: TVMPlot2D;
    function ImpulseResponse(const T: TVMobj; wn, z: Double): TVMobj;
    function Magnitude(const F: TVMobj; fn, z: Double): TVMobj;
    procedure Replot;
  end;

var
  Form1: TForm1;

const
  NumZeta = 8;
  Zetas: array[0..NumZeta - 1] of Double = (0.05, 0.1, 0.2, 0.3, 0.5, 0.707, 1.0, 2.0);
  NumTimePoints = 1000;
  NumFreqPoints = 600;
  FreqSpan = 3.0;   // magnitude plotted over 0 .. FreqSpan * fn

implementation

{$R *.lfm}

const
  // tab10, in TColor's BGR byte order
  ZetaColour: array[0..NumZeta - 1] of TColor =
    ($B47719, $0E7FFF, $2CA02C, $2827D6, $BD6794, $4B568C, $C277E3, $7F7F7F);

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
var
  i: Integer;
begin
  FPlotImpulse := TVMPlot2D.Create(Self);
  FPlotImpulse.Parent := pnlPlots;
  FPlotImpulse.Align := alTop;
  FPlotImpulse.Height := pnlPlots.Height div 2;
  FPlotImpulse.XAxisTitle := 'time (s)';
  FPlotImpulse.YAxisTitle := 'h(t)';

  FPlotMag := TVMPlot2D.Create(Self);
  FPlotMag.Parent := pnlPlots;
  FPlotMag.Align := alClient;
  FPlotMag.XAxisTitle := 'frequency (Hz)';
  FPlotMag.YAxisTitle := '|H(jw)|';

  // the check group lists the damping ratios in Zetas, three on by default
  for i := 0 to NumZeta - 1 do
    cgZeta.Checked[i] := i in [1, 4, 6];   // 0.1, 0.5, 1.0
  Replot;
end;

procedure TForm1.pnlPlotsResize(Sender: TObject);
begin
  if Assigned(FPlotImpulse) then
    FPlotImpulse.Height := pnlPlots.Height div 2;
end;

procedure TForm1.cgZetaItemClick(Sender: TObject; Index: integer);
begin
  Replot;
end;

procedure TForm1.seFnChange(Sender: TObject);
begin
  Replot;
end;

procedure TForm1.sePeriodsChange(Sender: TObject);
begin
  Replot;
end;

function TForm1.ImpulseResponse(const T: TVMobj; wn, z: Double): TVMobj;
var
  wd, s1, s2, k: Double;
begin
  if z < 1.0 then
  begin
    wd := wn * Sqrt(1 - z * z);
    k := wn / Sqrt(1 - z * z);
    Result := k * (Exp((-z * wn) * T) * Sin(wd * T));
  end
  else if z = 1.0 then
    Result := (wn * wn) * (T * Exp((-wn) * T))
  else
  begin
    s1 := -z * wn + wn * Sqrt(z * z - 1);
    s2 := -z * wn - wn * Sqrt(z * z - 1);
    k := wn / (2 * Sqrt(z * z - 1));
    Result := k * (Exp(s1 * T) - Exp(s2 * T));
  end;
end;

function TForm1.Magnitude(const F: TVMobj; fn, z: Double): TVMobj;
var
  R, D: TVMobj;
begin
  R := F * (1.0 / fn);                                      // frequency ratio w/wn
  D := Sqr(AddScalar(-Sqr(R), 1.0)) + Sqr((2 * z) * R);     // (1-r^2)^2 + (2 z r)^2
  Result := Exp((-0.5) * Ln(D));                            // D^(-1/2), elementwise
end;

procedure TForm1.Replot;
var
  fn, wn, z, dur: Double;
  T, F: TVMobj;
  HSeries, MSeries: array of TVMobj;
  n, i: Integer;
  line: string;
begin
  fn := seFn.Value;
  wn := 2 * Pi * fn;
  dur := sePeriods.Value / fn;

  T := TVMobj.Create(1, NumTimePoints);
  T.linspace(0, dur / (NumTimePoints - 1));
  F := TVMobj.Create(1, NumFreqPoints);
  F.linspace(0, FreqSpan * fn / (NumFreqPoints - 1));

  SetLength(HSeries, NumZeta);
  SetLength(MSeries, NumZeta);
  n := 0;

  memResults.Lines.BeginUpdate;
  try
    memResults.Clear;
    memResults.Lines.Add(Format('fn = %.3g Hz  (wn = %.4g rad/s), %d periods shown', [fn, wn, sePeriods.Value]));

    for i := 0 to NumZeta - 1 do
      if cgZeta.Checked[i] then
      begin
        z := Zetas[i];
        HSeries[n] := ImpulseResponse(T, wn, z);
        MSeries[n] := Magnitude(F, fn, z);
        FPlotImpulse.SetSeriesStyle(n, ZetaColour[i], 2.0, plsSolid, Format('zeta = %.3g', [z]));
        FPlotMag.SetSeriesStyle(n, ZetaColour[i], 2.0, plsSolid, Format('zeta = %.3g', [z]));
        Inc(n);

        line := Format('zeta %.3g: Q = %.3g, settling (2%%) %.3g s', [z, 1 / (2 * z), 4 / (z * wn)]);
        if z < 1 then
          line := line + Format(', fd = %.4g Hz', [fn * Sqrt(1 - z * z)]);
        if z < 1 / Sqrt(2) then
          line := line + Format(', peak |H| = %.3g at fr = %.4g Hz',
            [1 / (2 * z * Sqrt(1 - z * z)), fn * Sqrt(1 - 2 * z * z)])
        else
          line := line + ', no resonant peak';
        memResults.Lines.Add(line);
      end;

    FPlotImpulse.ClearSeries;
    FPlotMag.ClearSeries;
    if n = 0 then
      memResults.Lines.Add('No damping ratio selected.')
    else
    begin
      SetLength(HSeries, n);
      SetLength(MSeries, n);
      FPlotImpulse.Title := Format('Impulse response h(t), fn = %.3g Hz', [fn]);
      FPlotImpulse.SetData(T, HSeries);
      FPlotMag.Title := 'Magnitude response |H(jw)| vs frequency';
      FPlotMag.SetData(F, MSeries);
    end;
  finally
    memResults.Lines.EndUpdate;
  end;
end;

end.
