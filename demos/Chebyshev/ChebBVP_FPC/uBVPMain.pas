unit uBVPMain;

{*******************************************************************************

     Main form for the ChebBVP demo - ported from the Delphi/MtxVec
     original at demos/Chebyshev/ChebBVP/uMain.pas. Solves the linear
     boundary-value problem u_xx = exp(4x), u(-1)=u(1)=0 by Chebyshev
     collocation (Trefethen's "Spectral Methods in MATLAB", program p13):
     build the (N+1)x(N+1) second-derivative matrix D2 via TCheb - reused
     as-is from demos/Chebyshev/NormalIntegration/uCheb.pas, not copied
     (see ChebBVP.lpi's OtherUnitFiles search path) - drop the first/last
     row and column via newVM.pas's SubMatrix (the Dirichlet boundary
     values are already known to be zero, so only the N-1 interior points
     are unknowns), solve the resulting (N-1)x(N-1) system directly via
     newVM's LinearSolve, zero-pad the result back up to N+1 points, and
     barycentrically interpolate (BaryInterpol, also from uCheb.pas) onto
     a fine 201-point display grid, plotted as a solid line - "the
     interpolated line of the approximated function". The problem's known
     closed-form solution (built with newVM.pas's AddScalar, alongside
     the existing '*'/'/' scalar operators, since there's no '+'/scalar
     operator overload) is evaluated on that same fine grid too, but only
     internally, to compute the reported max-error figure - it isn't
     plotted as a curve of its own. Instead, the exact solution is
     evaluated directly at the N+1=17 Chebyshev points themselves and
     plotted as square point markers via TVMPlot2D.PlotXY (one call per
     node - see Graphs/uVMPlot2D.pas), overlaid on top of the
     approximation's line: since PlotXY gives every series its own
     independent X, this doesn't need to share a grid with the
     interpolated line the way TVMPlot2D.SetData's series would - it's
     exactly the discrete-points-alongside-a-different-resolution-line
     case SetData alone can't do. AddScalar and SubMatrix both started
     out as demo-local helpers here (AddScalar duplicated a second time
     in NormalIntegration's own uNormMain.pas) before being promoted into
     newVM.pas itself - see that unit's own header comment and CLAUDE.md's
     architecture notes for the library-level version now used by both
     demos.

     As with that demo, everything is computed once in FormCreate rather
     than behind a separate "Execute" button. The original's second tab
     (StringGrid1/StringGrid2, showing the DD matrix and - though never
     actually populated in the original code - a value grid) and its
     PolyFit/PolyEval cross-check (used only to compute a comparison
     error figure, with its own interpolated curve never actually
     plotted - see the original's commented-out AddXY call) aren't
     ported: BaryInterpol already stands in as the accuracy cross-check
     here, same as it does for the demo's own plotted curve.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, StdCtrls,
  newVM, uVMPlot2D, uCheb, hirestimer;

const
  ChebN = 16;   // Chebyshev series order (N+1 = 17 nodes), matches the original
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
  Xi, F, DD, U, V, IX, IY, Exact: TVMobj;
  I: Integer;
  MaxErr, Err, XNode: Double;
  ElapsedUs: Int64;
begin
  Profiler.Start;
  FCheb := TCheb.Create(ChebN);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time to create TCheb object: ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  // Dirichlet boundary values u(-1)=u(1)=0 are already known, so only the
  // N-1 interior collocation points (indices 1..N-1) are unknowns: drop
  // D2's first/last row and column, and solve against the interior x's.
  Xi := SubMatrix(FCheb.X, 1, 0, ChebN - 1, 1);
  F := Exp(4 * Xi);
  DD := SubMatrix(FCheb.D2, 1, 1, ChebN - 1, ChebN - 1);

  Profiler.Start;
  U := CopyObj(F);
  LinearSolve(DD, U);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time for direct solve: ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  // Zero-pad the interior solution back up to the full N+1 collocation
  // points - TVMobj.Create already zero-fills, so the two boundary
  // entries (indices 0 and ChebN) need no explicit assignment.
  V := TVMobj.Create(ChebN + 1, 1);
  for I := 1 to ChebN - 1 do
    V.Element[I, 0] := U.Element[I - 1, 0];

  IX := TVMobj.Create(1, GridN);
  IX.linspace(-1, 0.01);

  Profiler.Start;
  IY := BaryInterpol(FCheb.X, V, IX);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time for barycentric interpolation: ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  // Closed-form solution of u_xx = exp(4x), u(-1)=u(1)=0.
  Exact := Exp(4 * IX) - Sinh(4.0) * IX;
  Exact := AddScalar(Exact, -Cosh(4.0));
  Exact := Exact / 16;

  MaxErr := 0;
  for I := 0 to GridN - 1 do begin
    Err := Abs(IY.Element[0, I] - Exact.Element[0, I]);
    if Err > MaxErr then MaxErr := Err;
  end;

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := Format('u_xx = exp(4x), u(-1)=u(1)=0 (Spectral Methods p13); max err = %.3e', [MaxErr]);
  FPlot.XAxisTitle := 'x';
  FPlot.YAxisTitle := 'u';
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'u (Chebyshev, N=' + IntToStr(ChebN) + ')');
  FPlot.SetSeriesStyle(1, clBlue, 1.5, plsNone, 'u exact (Chebyshev points)', pmsSquare);
  FPlot.SetData(IX, [IY]);

  // Exact solution at the N+1 Chebyshev points themselves, one PlotXY
  // call per node - see the header comment for why this is PlotXY rather
  // than a second SetData series.
  for I := 0 to ChebN do begin
    XNode := FCheb.X.Element[I, 0];
    FPlot.PlotXY(XNode, (Exp(4 * XNode) - Sinh(4.0) * XNode - Cosh(4.0)) / 16, 1);
  end;

  Memo1.Lines.Add('');
  Memo1.Lines.Add('Max error = ' + FloatToStr(MaxErr));
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FCheb.Free;
end;

end.
