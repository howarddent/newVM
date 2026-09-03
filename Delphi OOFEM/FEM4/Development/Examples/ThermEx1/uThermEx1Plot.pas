unit uThermEx1Plot;

{ The window ThermEx1 shows its result in: the radial temperature profile
  through the cylinder, at t = 0 and at the end of the run, on one
  TVMPlot2D.

  The model is radially symmetric - uniform generation, a uniform lateral
  boundary condition, adiabatic ends - so a field plot of the solid adds
  nothing a curve against radius does not already say, and says it less
  clearly. Two lines from the axis to the skin are the whole result.

  Beside the graph is a memo carrying the run's own report - the
  compartment table, the layered profile against its closed form, the
  step-by-step energy table - verbatim as the program also prints it to
  stdout. The text is the model's, built once through TThermalModel.Say
  and handed here, so the window and the terminal cannot disagree.

  The dashed markers are the compartment boundaries. The form is built
  in code rather than from a .lfm: three controls, docked, so a
  design-time resource would be more to keep in step than it is worth.
  TVMPlot2D is created and parented the same way Graphs/Plot2D's own
  demo does it, which is the supported route whether or not the
  newVMGraphs design-time package is installed. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math, Graphics, Forms, Controls, StdCtrls, ExtCtrls,
  newVM,
  uThermEx1,
  uVMPlot2D;

const

  // Grey for the boundaries, so they read as annotation rather than as
  // data against the red and blue profiles.
  InterfaceColour : Array[0..3] of TColor =
    (clGray, clGray, clGray, clGray);

type

  TProfileForm = class(TForm)

  private

    FPlot : TVMPlot2D;
    FMemo : TMemo;
    FSplitter : TSplitter;

  public

    constructor CreateNew(AOwner : TComponent; Dummy : Integer = 0); override;

    procedure ShowProfiles(const R, T0, TEnd : TVMobj;
                           const ACaption, ASubtitle : String;
                           const AReport : TStrings;
                           AModel : TObject);

  end;

implementation

constructor TProfileForm.CreateNew(AOwner : TComponent; Dummy : Integer);
begin

  inherited CreateNew(AOwner, Dummy);

  Caption := 'ThermEx1 - radial temperature profile';

  // Clamp to the work area rather than asking for a fixed 1400x760: on a
  // smaller screen, or under display scaling, a form wider than the
  // desktop puts its right-hand strip - which is where the memo lives -
  // off the edge, and the report simply is not there to be read.
  Width := Min(1400, Screen.WorkAreaWidth - 40);
  Height := Min(760, Screen.WorkAreaHeight - 40);

  Position := poScreenCenter;

  // Docking order matters: the memo claims the right edge, the splitter
  // the edge left of it, and the plot takes whatever is left. Created
  // the other way round, the plot would swallow the lot.
  FMemo := TMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.Align := alRight;
  // Never more than half the form, so the graph keeps usable width on a
  // narrow screen; the splitter can rebalance it either way.
  FMemo.Width := Min(560, Width div 2);
  FMemo.ReadOnly := True;
  FMemo.WordWrap := False;
  FMemo.ScrollBars := ssAutoBoth;

  // The report is columnar - the per-step table lines up only in a fixed
  // pitch face, which is also what it looks like in the terminal it is
  // still printed to.
  FMemo.Font.Name := 'Courier New';
  FMemo.Font.Size := 9;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Parent := Self;
  FSplitter.Align := alRight;
  FSplitter.Width := 5;

  FPlot := TVMPlot2D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;

end;

{ Both profiles are sampled at the same radii - they come from the same
  nodes of the same mesh - so the single shared X that SetData takes is
  exactly right here. }
procedure TProfileForm.ShowProfiles(const R, T0, TEnd : TVMobj;
                                    const ACaption, ASubtitle : String;
                                    const AReport : TStrings;
                                    AModel : TObject);
var

  i, j : Integer;

  lo, hi, v : Double;

  M : TThermalModel;

begin

  Caption := ACaption;

  FMemo.Lines.Assign(AReport);

  // Show the top of the report rather than wherever Assign left the
  // caret - the model summary is the part worth landing on.
  FMemo.SelStart := 0;

  FPlot.Title := ASubtitle;
  FPlot.XAxisTitle := 'Radius from the axis (mm)';
  FPlot.YAxisTitle := 'Temperature (C)';

  // Start red, end blue: the run only ever cools, so the warm curve is
  // the one it started from.
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'Start (t = 0)');
  FPlot.SetSeriesStyle(1, clBlue, 2.0, plsSolid, 'End of run');

  FPlot.SetData(R, [T0, TEnd]);

  // The temperature range both profiles span, so the boundary markers
  // are drawn full height whatever the run did.
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

  // Mark each compartment boundary. The outer layers are thin - 2.3 mm
  // of fat and 1.5 mm of skin on a 75.6 mm radius - so without the
  // marks the steepening at the right-hand edge reads as a plotting
  // artefact rather than as the layers it is.
  //
  // Each is a series with its OWN two-point x, which is why they are
  // built with PlotXY rather than passed to SetData - SetData takes one
  // shared x for every series it is given. The component stores an x
  // per series, so the two routes mix as long as SetData goes first.
  M := TThermalModel(AModel);

  for j := 0 to M.InterfaceCount - 1 do
  begin

    FPlot.SetSeriesStyle(2 + j, InterfaceColour[j mod 4], 1.0, plsDash,
      M.InterfaceName(j));

    FPlot.PlotXY(M.InterfaceMm(j), lo, 2 + j);
    FPlot.PlotXY(M.InterfaceMm(j), hi, 2 + j);

  end;

end;

end.
