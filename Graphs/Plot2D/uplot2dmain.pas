unit uplot2dmain;

{*******************************************************************************

     Main form for the Plot2D demo: three TVMPlot2D components
     (Graphs/uVMPlot2D.pas), each created and parented in code (FormCreate),
     the same way any LCL component can be instantiated and added to a form
     at runtime without needing a design-time package installed. See
     uVMPlot2D.pas for the component itself - its rendering approach
     (auto-fitted orthographic projection, GL-texture-cached title/tick
     text, dashed/dotted lines via GL_LINE_STIPPLE) is documented there,
     not duplicated here.

     TOP - LINES: two related y = f(x) series computed elementwise on TVMobj
     row vectors (see newVM.pas) - the same base function as
     demos/FunctionPlot, plus its cosine-phase sibling.

     BOTTOM LEFT - BARS (pstBar, SetSeriesBar): a histogram of 2000
     samples from N(0, 1) in 24 bins over [-4, 4], with the expected count
     per bin, N * binwidth * pdf(x), as a smooth red curve. The bars come
     from SetData on the bin centres; the curve lives on its own, finer
     grid, so it is added point by point with PlotXY - the two ways of
     getting data in, on one plot.

     BOTTOM RIGHT - WHISKERS (pstWhisker, SetWhiskerData): a box plot of 8
     groups of 40 samples whose centre and spread drift from group to
     group. Box = lower to upper quartile, whiskers = minimum to maximum,
     and the medians as a line with markers through the boxes; the groups
     are labelled with SetXTickLabels.

     The random samples use a fixed RandSeed, so every run shows the same
     picture. COMMAND LINE: --snapshot=<prefix> saves the three plots as
     <prefix>_lines.png, <prefix>_bars.png and <prefix>_whiskers.png
     (TVMPlot2D.SaveToPNG) and exits - for checking the rendering without
     a screen capture.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  newVM, uVMPlot2D;

type

  { TForm1 }

  TForm1 = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FPlot: TVMPlot2D;      // lines (top)
    FHist: TVMPlot2D;      // bars (bottom left)
    FBox: TVMPlot2D;       // whiskers (bottom right)
    FBottom: TPanel;
    procedure BuildLines;
    procedure BuildHistogram;
    procedure BuildBoxPlot;
    procedure Snapshot(Data: PtrInt);
  end;

var
  Form1: TForm1;

const
  NumPoints = 1000;
  XRangeMin = -10.0;
  XRangeMax = 10.0;

  HistSamples = 2000;
  HistBins = 24;
  HistMin = -4.0;
  HistMax = 4.0;

  BoxGroups = 8;
  BoxSamples = 40;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.FormCreate(Sender: TObject);
begin
  RandSeed := 20261008;    // fixed: the same samples every run

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alTop;

  FBottom := TPanel.Create(Self);
  FBottom.Parent := Self;
  FBottom.Align := alClient;
  FBottom.BevelOuter := bvNone;

  FHist := TVMPlot2D.Create(Self);
  FHist.Parent := FBottom;
  FHist.Align := alLeft;

  FBox := TVMPlot2D.Create(Self);
  FBox.Parent := FBottom;
  FBox.Align := alClient;

  FormResize(Self);
  BuildLines;
  BuildHistogram;
  BuildBoxPlot;
end;

// Top plot half the height, the two bottom plots half the width each.
procedure TForm1.FormResize(Sender: TObject);
begin
  if FPlot = nil then Exit;
  FPlot.Height := ClientHeight div 2;
  FHist.Width := ClientWidth div 2;
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if Application.HasOption('snapshot') then
    Application.QueueAsyncCall(@Snapshot, 0);
end;

procedure TForm1.Snapshot(Data: PtrInt);
var
  Prefix: string;
  ok: Boolean;
begin
  Application.ProcessMessages;   // let all three plots get a first real paint
  Prefix := Application.GetOptionValue('snapshot');
  ok := FPlot.SaveToPNG(Prefix + '_lines.png')
    and FHist.SaveToPNG(Prefix + '_bars.png')
    and FBox.SaveToPNG(Prefix + '_whiskers.png');
  if ok then WriteLn('saved ', Prefix, '_{lines,bars,whiskers}.png')
  else begin
    WriteLn(StdErr, 'could not save the plots');
    ExitCode := 1;
  end;
  Application.Terminate;
end;

procedure TForm1.BuildLines;
var
  X, YSin, YCos, Envelope: TVMobj;
begin
  X := TVMobj.Create(1, NumPoints);
  X.linspace(XRangeMin, (XRangeMax - XRangeMin) / (NumPoints - 1));
  Envelope := Exp(-0.1 * Sqr(X));
  YSin := Envelope * Sin(3 * X);   // y = exp(-0.1*x^2) * sin(3*x)
  YCos := Envelope * Cos(3 * X);   // y = exp(-0.1*x^2) * cos(3*x)

  FPlot.Title := 'Lines: y = exp(-0.1x^2) . {sin(3x), cos(3x)}';
  FPlot.XAxisTitle := 'x';
  FPlot.YAxisTitle := 'y';
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'exp(-0.1x^2).sin(3x)');
  FPlot.SetSeriesStyle(1, clBlue, 1.5, plsDash, 'exp(-0.1x^2).cos(3x)');
  FPlot.SetData(X, [YSin, YCos]);
end;

procedure TForm1.BuildHistogram;
const
  CurvePoints = 200;
var
  Centres, Counts: TVMobj;
  i, b: Integer;
  w, x: Double;
begin
  w := (HistMax - HistMin) / HistBins;
  Centres := TVMobj.Create(1, HistBins);
  Counts := TVMobj.Create(1, HistBins);
  for b := 0 to HistBins - 1 do begin
    Centres[0, b] := HistMin + (b + 0.5) * w;
    Counts[0, b] := 0;
  end;
  for i := 1 to HistSamples do begin
    x := RandG(0, 1);
    b := Floor((x - HistMin) / w);
    if (b >= 0) and (b < HistBins) then Counts[0, b] := Counts[0, b] + 1;
  end;

  FHist.Title := Format('Bars: histogram of %d samples from N(0, 1)', [HistSamples]);
  FHist.XAxisTitle := 'x';
  FHist.YAxisTitle := 'count per bin';
  FHist.SetSeriesBar(0, TColor($C8A064), 'samples per bin', 0.9);
  FHist.SetSeriesStyle(1, clRed, 2.0, plsSolid, 'expected: N w pdf(x)');
  FHist.SetData(Centres, [Counts]);
  // the expected-count curve on its own fine grid, point by point
  for i := 0 to CurvePoints - 1 do begin
    x := HistMin + (HistMax - HistMin) * i / (CurvePoints - 1);
    FHist.PlotXY(x, HistSamples * w * Exp(-0.5 * x * x) / Sqrt(2 * Pi), 1);
  end;
end;

// Linear-interpolation quantile (R's type 7, numpy's default) of a sorted
// array.
function Quantile(const S: array of Double; p: Double): Double;
var
  h: Double;
  i: Integer;
begin
  h := (Length(S) - 1) * p;
  i := Floor(h);
  if i >= High(S) then Exit(S[High(S)]);
  result := S[i] + (h - i) * (S[i + 1] - S[i]);
end;

procedure SortDoubles(var A: array of Double);
var
  i, j: Integer;
  t: Double;
begin
  for i := 1 to High(A) do begin      // insertion sort: 40 values
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

procedure TForm1.BuildBoxPlot;
var
  X, Lo, Q1, Med, Q3, Hi: TVMobj;
  Pos: array[0..BoxGroups - 1] of Double;
  Labels: array[0..BoxGroups - 1] of string;
  S: array[0..BoxSamples - 1] of Double;
  g, i: Integer;
  Centre, Spread: Double;
begin
  X := TVMobj.Create(1, BoxGroups);
  Lo := TVMobj.Create(1, BoxGroups);
  Q1 := TVMobj.Create(1, BoxGroups);
  Med := TVMobj.Create(1, BoxGroups);
  Q3 := TVMobj.Create(1, BoxGroups);
  Hi := TVMobj.Create(1, BoxGroups);
  for g := 0 to BoxGroups - 1 do begin
    Centre := 10 + 4 * Sin(0.8 * g);          // the groups drift ...
    Spread := 1 + 0.35 * g;                   // ... and spread out
    for i := 0 to BoxSamples - 1 do S[i] := RandG(Centre, Spread);
    SortDoubles(S);
    X[0, g] := g;
    Lo[0, g] := S[0];
    Q1[0, g] := Quantile(S, 0.25);
    Med[0, g] := Quantile(S, 0.5);
    Q3[0, g] := Quantile(S, 0.75);
    Hi[0, g] := S[BoxSamples - 1];
    Pos[g] := g;
    Labels[g] := 'group ' + Chr(Ord('A') + g);
  end;

  FBox.Title := Format('Whiskers: %d groups of %d samples', [BoxGroups, BoxSamples]);
  FBox.XAxisTitle := 'group';
  FBox.YAxisTitle := 'value';
  FBox.SetXTickLabels(Pos, Labels);
  FBox.SetSeriesStyle(0, TColor($2060C0), 2.0, plsSolid, 'median', pmsDiamond, 8);
  FBox.Series[1].LineColor := TColor($A0E0B0);
  FBox.Series[1].BarWidth := 0.6;
  FBox.Series[1].Name := 'box: quartiles; whiskers: min to max';
  FBox.LegendCorner := lcBottomLeft;    // groups A-C have no low values
  // lines first (SetData fills series 0), the whiskers after
  FBox.SetData(X, [Med]);
  FBox.SetWhiskerData(1, X, Lo, Q1, Q3, Hi);
end;

end.
