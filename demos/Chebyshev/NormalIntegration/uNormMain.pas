unit uNormMain;

{*******************************************************************************

     Main form for the NormalIntegration demo - ported from the Delphi/
     MtxVec original at demos/Chebyshev/Normal_Integration/uMain.pas.
     Computes the standard normal PDF at N+1=33 Chebyshev points, recovers
     its antiderivative (the CDF, up to a constant) by solving the
     Chebyshev differentiation matrix equation D*iy = y (TCheb.Integrate,
     uCheb.pas), barycentrically interpolates both onto a 201-point display
     grid (BaryInterpol, uCheb.pas), and hands the two series to a
     TVMPlot2D component (Graphs/uVMPlot2D.pas) instead of the original's
     TChart/TeeSeries. Unlike the original, everything is computed directly
     in FormCreate rather than behind a separate "Execute" button - nothing
     here is reconfigurable between the two steps, so the split served no
     purpose once ported (matches the other demos/Graphs projects in this
     repo, which all compute their data once in FormCreate).

     Also exercises TCheb.CurtisClenshaw (the newly-filled-in Clenshaw-
     Curtis quadrature - see uCheb.pas) two ways, both reported in the
     memo: against a test function with a known closed-form integral
     (exp(x) over [-1,1], exact = e - 1/e) to demonstrate its accuracy
     directly, and against the demo's own Gaussian PDF to report the total
     probability mass actually captured within the +/-4 SD Chebyshev
     domain (a number strictly less than 100%, unlike the 1/2/3 SD figures
     above which are differences of two CDF values and so don't depend on
     where the domain's own edges sit).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  newVM, uVMPlot2D, uCheb;

const
  ChebN = 32;   // Chebyshev series order (N+1 = 33 nodes), matches the original
  GridN = 201;  // display grid points, ramped -1..1 in steps of 0.01

type

  { TfmMain }

  TfmMain = class(TForm)
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    FCheb: TCheb;
    FPlot: TVMPlot2D;
  end;

var
  fmMain: TfmMain;

implementation

{$R *.lfm}

{ TfmMain }

procedure TfmMain.FormCreate(Sender: TObject);
var
  Y, IY, GX, GYPdf, GYCdf, TestF: TVMobj;
  P1SD, M1SD, P2SD, M2SD, P3SD, M3SD: Double;
  QuadApprox, QuadExact, TotalMass: Double;
begin
  FCheb := TCheb.Create(ChebN);

  // Standard normal PDF sampled at the Chebyshev points, scaled so the
  // Chebyshev domain [-1,1] spans +/-4 standard deviations (the real
  // variable u = 4*x, so exp(-(4x)^2/2) = exp(-8x^2)).
  Y := (1 / Sqrt(2 * Pi)) * Exp(-8 * Sqr(FCheb.X));

  // Antiderivative via D*IY = Y. D is singular up to an additive constant
  // (see uCheb.pas), so the arbitrary constant of integration is removed
  // by hand: zero IY at x=-1 (u=-4sd, where the CDF is ~0), rescale for
  // du = 4*dx, then shift so IY(x=0) = 0.5 (the CDF at the median).
  IY := FCheb.Integrate(Y);
  IY := AddScalar(IY, -IY.Element[ChebN, 0]);
  IY := 4 * IY;
  IY := AddScalar(IY, 0.5 - IY.Element[ChebN div 2, 0]);

  GX := TVMobj.Create(1, GridN);
  GX.linspace(-1, 0.01);

  GYPdf := BaryInterpol(FCheb.X, Y, GX);
  GYCdf := BaryInterpol(FCheb.X, IY, GX);

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := 'Standard Normal distribution and its integral by Chebyshev methods';
  FPlot.XAxisTitle := 'standard deviations';
  FPlot.YAxisTitle := 'y';
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'pdf');
  FPlot.SetSeriesStyle(1, clBlue, 1.5, plsDash, 'cdf');
  FPlot.SetData(4 * GX, [GYPdf, GYCdf]);

  P1SD := GYCdf.Element[0, 125]; M1SD := GYCdf.Element[0, 75];
  P2SD := GYCdf.Element[0, 150]; M2SD := GYCdf.Element[0, 50];
  P3SD := GYCdf.Element[0, 175]; M3SD := GYCdf.Element[0, 25];
  Memo1.Lines.Add('1 SD = ' + FloatToStr(100 * (P1SD - M1SD)) + ' %');
  Memo1.Lines.Add('2 SD = ' + FloatToStr(100 * (P2SD - M2SD)) + ' %');
  Memo1.Lines.Add('3 SD = ' + FloatToStr(100 * (P3SD - M3SD)) + ' %');

  // Clenshaw-Curtis quadrature (TCheb.CurtisClenshaw), test function:
  // Int exp(x) dx over [-1,1], exact = e - 1/e.
  TestF := Exp(FCheb.X);
  QuadApprox := FCheb.CurtisClenshaw(TestF);
  QuadExact := Exp(1.0) - Exp(-1.0);
  Memo1.Lines.Add('');
  Memo1.Lines.Add('Clenshaw-Curtis test: Int exp(x)dx, [-1,1]');
  Memo1.Lines.Add('  approx = ' + FloatToStr(QuadApprox));
  Memo1.Lines.Add('  exact  = ' + FloatToStr(QuadExact));
  Memo1.Lines.Add('  error  = ' + FloatToStr(Abs(QuadApprox - QuadExact)));

  // Same quadrature applied to the demo's own PDF: the total probability
  // mass actually captured within +/-4 SD (du = 4*dx, as above).
  TotalMass := 4 * FCheb.CurtisClenshaw(Y);
  Memo1.Lines.Add('');
  Memo1.Lines.Add('Mass in [-4,4] SD = ' + FloatToStr(100 * TotalMass) + ' %');
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FCheb.Free;
end;

end.
