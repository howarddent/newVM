unit uplot2dmain;

{*******************************************************************************

     Main form for the Plot2D demo. Computes y = f(x) elementwise on a TVMobj
     (1 x NumPoints row vector, see newVM.pas) - the same function as
     demos/FunctionPlot - but renders it with raw OpenGL (TOpenGLControl,
     the LazOpenGLContext package, plus FPC's own GL unit) instead of
     TAChart: an anti-aliased line strip inside an orthographic projection
     auto-fitted to the data's bounding box, with simple axis/border
     overlays drawn in GL rather than left to a charting component.

     BuildPlotData accepts any real TVMobj vector (row or column shaped,
     per newVM's (1,N)/(N,1) convention) plus an optional X vector - the
     one concrete function plotted here is just a demonstration of that
     general path, the same way FunctionPlot's y=f(x) is one concrete use
     of TAChart.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs,
  GL, OpenGLContext,
  newVM;

type

  { TForm1 }

  TForm1 = class(TForm)
    OpenGLControl1: TOpenGLControl;
    procedure FormCreate(Sender: TObject);
    procedure OpenGLControl1Paint(Sender: TObject);
    procedure OpenGLControl1Resize(Sender: TObject);
  private
    FXData, FYData: array of Double;
    FXMin, FXMax, FYMin, FYMax: Double;
    procedure BuildPlotData(const X, Y: TVMobj);
    procedure DrawAxes;
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
  X, Y: TVMobj;
begin
  X := TVMobj.Create(1, NumPoints);
  X.linspace(XRangeMin, (XRangeMax - XRangeMin) / (NumPoints - 1));
  Y := Exp(-0.1 * Sqr(X)) * Sin(3 * X);   // y = exp(-0.1*x^2) * sin(3*x)
  BuildPlotData(X, Y);
end;

// Extracts a TVMobj vector pair into plain Double arrays for the paint
// handler (avoids a bounds-checked Element[] call per vertex per frame),
// and computes the data's bounding box - with a margin - so the
// orthographic projection auto-fits it regardless of what X/Y contain.
// X and Y may each be either row (1,N) or column (N,1) shaped.
procedure TForm1.BuildPlotData(const X, Y: TVMobj);
const
  MarginFrac = 0.08;

  function VecLen(const V: TVMobj): Integer;
  begin
    result := V.Rows * V.Cols;
  end;

  function VecAt(const V: TVMobj; i: Integer): Double;
  begin
    if V.Rows = 1 then result := V[0, i] else result := V[i, 0];
  end;

var
  N, i: Integer;
  XMargin, YMargin: Double;
begin
  N := VecLen(Y);
  assert(VecLen(X) = N, 'BuildPlotData: X and Y must have the same length');
  SetLength(FXData, N);
  SetLength(FYData, N);
  for i := 0 to N - 1 do begin
    FXData[i] := VecAt(X, i);
    FYData[i] := VecAt(Y, i);
  end;

  FXMin := FXData[0]; FXMax := FXData[0];
  FYMin := FYData[0]; FYMax := FYData[0];
  for i := 1 to N - 1 do begin
    if FXData[i] < FXMin then FXMin := FXData[i];
    if FXData[i] > FXMax then FXMax := FXData[i];
    if FYData[i] < FYMin then FYMin := FYData[i];
    if FYData[i] > FYMax then FYMax := FYData[i];
  end;
  XMargin := (FXMax - FXMin) * MarginFrac;
  YMargin := (FYMax - FYMin) * MarginFrac;
  if XMargin = 0 then XMargin := 1;   // guard a constant-X vector
  if YMargin = 0 then YMargin := 1;   // guard a constant-Y vector
  FXMin := FXMin - XMargin; FXMax := FXMax + XMargin;
  FYMin := FYMin - YMargin; FYMax := FYMax + YMargin;
end;

// Border rectangle at the data bounds, plus X/Y=0 gridlines where those
// fall inside the plotted range.
procedure TForm1.DrawAxes;
begin
  glColor3f(0.75, 0.75, 0.75);
  glBegin(GL_LINE_LOOP);
    glVertex2d(FXMin, FYMin);
    glVertex2d(FXMax, FYMin);
    glVertex2d(FXMax, FYMax);
    glVertex2d(FXMin, FYMax);
  glEnd;

  glColor3f(0.55, 0.55, 0.55);
  glBegin(GL_LINES);
    if (FYMin < 0) and (FYMax > 0) then begin
      glVertex2d(FXMin, 0); glVertex2d(FXMax, 0);
    end;
    if (FXMin < 0) and (FXMax > 0) then begin
      glVertex2d(0, FYMin); glVertex2d(0, FYMax);
    end;
  glEnd;
end;

procedure TForm1.OpenGLControl1Paint(Sender: TObject);
var
  i: Integer;
begin
  if not OpenGLControl1.MakeCurrent then Exit;
  if (OpenGLControl1.Width = 0) or (OpenGLControl1.Height = 0) then Exit;

  glViewport(0, 0, OpenGLControl1.Width, OpenGLControl1.Height);
  glMatrixMode(GL_PROJECTION);
  glLoadIdentity;
  glOrtho(FXMin, FXMax, FYMin, FYMax, -1, 1);
  glMatrixMode(GL_MODELVIEW);
  glLoadIdentity;

  glClearColor(1.0, 1.0, 1.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);

  glEnable(GL_LINE_SMOOTH);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glHint(GL_LINE_SMOOTH_HINT, GL_NICEST);

  DrawAxes;

  glColor3f(0.1, 0.3, 0.9);
  glLineWidth(2.0);
  glBegin(GL_LINE_STRIP);
    for i := 0 to High(FXData) do
      glVertex2d(FXData[i], FYData[i]);
  glEnd;

  OpenGLControl1.SwapBuffers;
end;

procedure TForm1.OpenGLControl1Resize(Sender: TObject);
begin
  OpenGLControl1.Invalidate;
end;

end.
