unit uThermEx1Plot;

{ The window ThermEx1 shows its result in: the radial temperature profile
  through the cylinder, at t = 0 and at the end of the run, on one
  TVMPlot2D.

  The model is radially symmetric - uniform generation, a uniform lateral
  boundary condition, adiabatic ends - so a field plot of the solid adds
  nothing a curve against radius does not already say, and says it less
  clearly. Two lines from the axis to the skin are the whole result.

  The form is built in code rather than from a .lfm: it holds one
  component, sized to fill it, so a design-time resource would be more
  to keep in step than it is worth. TVMPlot2D is created and parented the
  same way Graphs/Plot2D's own demo does it, which is the supported route
  whether or not the newVMGraphs design-time package is installed. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Graphics, Forms, Controls,
  newVM,
  uVMPlot2D;

type

  TProfileForm = class(TForm)

  private

    FPlot : TVMPlot2D;

  public

    constructor CreateNew(AOwner : TComponent; Dummy : Integer = 0); override;

    procedure ShowProfiles(const R, T0, TEnd : TVMobj;
                           const ACaption, ASubtitle : String;
                           RLeanMm : Double);

  end;

implementation

constructor TProfileForm.CreateNew(AOwner : TComponent; Dummy : Integer);
begin

  inherited CreateNew(AOwner, Dummy);

  Caption := 'ThermEx1 - radial temperature profile';

  Width := 900;
  Height := 620;

  Position := poScreenCenter;

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;

end;

{ Both profiles are sampled at the same radii - they come from the same
  nodes of the same mesh - so the single shared X that SetData takes is
  exactly right here. }
procedure TProfileForm.ShowProfiles(const R, T0, TEnd : TVMobj;
                                    const ACaption, ASubtitle : String;
                                    RLeanMm : Double);
var

  i : Integer;

  lo, hi, v : Double;

begin

  Caption := ACaption;

  FPlot.Title := ASubtitle;
  FPlot.XAxisTitle := 'Radius from the axis (mm)';
  FPlot.YAxisTitle := 'Temperature (C)';

  // Start red, end blue: the run only ever cools, so the warm curve is
  // the one it started from.
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'Start (t = 0)');
  FPlot.SetSeriesStyle(1, clBlue, 2.0, plsSolid, 'End of run');

  FPlot.SetData(R, [T0, TEnd]);

  // Mark where the fat begins. The last 2.2 mm of a 75.7 mm radius
  // carries a disproportionate share of the drop, and without the mark
  // that steepening at the right-hand edge looks like a plotting
  // artefact rather than the fat layer it is.
  //
  // This is a third series with its OWN two-point x, which is why it is
  // built with PlotXY rather than passed to SetData - SetData takes one
  // shared x for every series it is given, and this one needs a
  // different one. The component stores an x per series, so the two
  // routes mix as long as SetData goes first.
  lo := T0[0, 0];
  hi := lo;

  for i := 0 to R.Cols - 1 do
  begin

    v := T0[0, i];
    if v < lo then lo := v;
    if v > hi then hi := v;

    v := TEnd[0, i];
    if v < lo then lo := v;
    if v > hi then hi := v;

  end;

  FPlot.SetSeriesStyle(2, clGray, 1.0, plsDash, 'Fat layer begins');

  FPlot.PlotXY(RLeanMm, lo, 2);
  FPlot.PlotXY(RLeanMm, hi, 2);

end;

end.
