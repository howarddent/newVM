unit uThermEx1Plot;

{ The window ThermEx1 shows its result in: the radial temperature profile
  through the body, at t = 0 and at the end of the run, on one TVMPlot2D,
  with the run's own report beside it and a cardiac-output slider under
  it.

  The model is radially symmetric - uniform generation within each
  compartment, a uniform lateral boundary condition, adiabatic ends - so
  a field plot of the solid adds nothing a curve against radius does not
  already say, and says it less clearly. Two lines from the axis to the
  skin are the whole result, and the dashed markers are the compartment
  boundaries.

  The memo carries the report verbatim as the program also prints it to
  stdout. The text is the model's, built once through TThermalModel.Say
  and handed here, so the window and the terminal cannot disagree.

  THE SLIDER

  Cardiac output, 0 to 10 L/min. Zero is the conduction-only model this
  began as; 5 is a normal resting output; 10 is twice that. Moving it
  re-solves.

  The re-solve takes the better part of a minute, so it deliberately does
  NOT fire on every tick of the drag - the label follows the slider
  continuously, and the solve happens once, when the mouse or the key is
  released. The window is disabled and says so while it runs, since
  there is nothing useful to do with a half-solved model.

  The form is built in code rather than from a .lfm: a handful of docked
  controls, so a design-time resource would be more to keep in step than
  it is worth. TVMPlot2D is created and parented the same way
  Graphs/Plot2D's own demo does it, which is the supported route whether
  or not the newVMGraphs design-time package is installed. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math, Graphics, Forms, Controls, StdCtrls, ExtCtrls,
  ComCtrls,
  newVM,
  uThermEx1,
  uVMPlot2D;

const

  // Ten slider steps per L/min, so the slider lands on 0.1 L/min.
  TrackPerLitre = 10;

type

  TProfileForm = class(TForm)

  private

    FPlot : TVMPlot2D;
    FMemo : TMemo;
    FSplitter : TSplitter;

    FPanel : TPanel;
    FTrack : TTrackBar;
    FCaption : TLabel;

    FModel : TThermalModel;
    FSolving : Boolean;

    procedure TrackChange(Sender : TObject);
    procedure TrackReleased(Sender : TObject; Button : TMouseButton;
                            Shift : TShiftState; X, Y : Integer);
    procedure TrackKeyUp(Sender : TObject; var Key : Word;
                         Shift : TShiftState);

    procedure ShowFlow;
    procedure Resolve;
    procedure RefreshDisplay;

  public

    constructor CreateNew(AOwner : TComponent; Dummy : Integer = 0); override;

    // Take the model as it stands - already prepared and solved once -
    // and show it.
    procedure Attach(AModel : TThermalModel);

  end;

implementation

constructor TProfileForm.CreateNew(AOwner : TComponent; Dummy : Integer);
begin

  inherited CreateNew(AOwner, Dummy);

  Caption := 'ThermEx1';

  // Clamp to the work area rather than asking for a fixed size: on a
  // smaller screen, or under display scaling, a form wider than the
  // desktop puts its right-hand strip - which is where the memo lives -
  // off the edge, and the report simply is not there to be read.
  Width := Min(1400, Screen.WorkAreaWidth - 40);
  Height := Min(800, Screen.WorkAreaHeight - 40);

  Position := poScreenCenter;

  // Docking order matters: the panel takes the bottom, the memo the
  // right edge, the splitter the edge left of it, and the plot whatever
  // is left. A client-aligned control created first would take the lot.
  FPanel := TPanel.Create(Self);
  FPanel.Parent := Self;
  FPanel.Align := alBottom;
  FPanel.Height := 60;
  FPanel.BevelOuter := bvNone;

  FCaption := TLabel.Create(Self);
  FCaption.Parent := FPanel;
  FCaption.Left := 12;
  FCaption.Top := 8;
  FCaption.Width := 460;

  FTrack := TTrackBar.Create(Self);
  FTrack.Parent := FPanel;
  FTrack.Left := 8;
  FTrack.Top := 26;
  FTrack.Width := 620;
  FTrack.Height := 30;
  FTrack.Min := 0;
  FTrack.Max := Round(CardiacOutputMax * TrackPerLitre);
  FTrack.Frequency := TrackPerLitre;
  FTrack.PageSize := TrackPerLitre;
  FTrack.OnChange := TrackChange;
  FTrack.OnMouseUp := TrackReleased;
  FTrack.OnKeyUp := TrackKeyUp;

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

procedure TProfileForm.Attach(AModel : TThermalModel);
begin

  FModel := AModel;

  FTrack.Position := Round(FModel.CardiacOutput * TrackPerLitre);

  ShowFlow;

  RefreshDisplay;

end;

procedure TProfileForm.ShowFlow;
begin

  FCaption.Caption := Format('Cardiac output %.1f L/min' +
    '     (0 = conduction only, 5 = resting, 10 = twice resting)',
    [FTrack.Position / TrackPerLitre]);

end;

{ The label follows the drag; the solve does not - see the header. }
procedure TProfileForm.TrackChange(Sender : TObject);
begin

  ShowFlow;

end;

procedure TProfileForm.TrackReleased(Sender : TObject; Button : TMouseButton;
                                     Shift : TShiftState; X, Y : Integer);
begin

  Resolve;

end;

procedure TProfileForm.TrackKeyUp(Sender : TObject; var Key : Word;
                                  Shift : TShiftState);
begin

  Resolve;

end;

procedure TProfileForm.Resolve;
var
  Flow : Double;
begin

  if FSolving or (FModel = nil) then
    Exit;

  Flow := FTrack.Position / TrackPerLitre;

  // Nothing to do if the slider came back to where it started.
  if Abs(Flow - FModel.CardiacOutput) < 1E-6 then
    Exit;

  FSolving := True;

  try

    FPanel.Enabled := False;

    Caption := Format('ThermEx1 - solving at %.1f L/min...', [Flow]);

    // Let the caption and the disabled panel actually paint before the
    // solve takes the thread for the next minute.
    Application.ProcessMessages;

    FModel.Solve(Flow);

    RefreshDisplay;

  finally

    FPanel.Enabled := True;

    FSolving := False;

  end;

end;

{ Both profiles are sampled at the same radii - they come from the same
  nodes of the same mesh - so the single shared X that SetData takes is
  exactly right here. }
procedure TProfileForm.RefreshDisplay;
var

  i, j : Integer;

  lo, hi, v : Double;

  R, T0, TEnd : TVMobj;

begin

  FModel.GetRadialProfiles(R, T0, TEnd);

  Caption := Format('ThermEx1 - case %d, cardiac output %.1f L/min',
    [FModel.CaseNumber, FModel.CardiacOutput]);

  FMemo.Lines.Assign(FModel.Report);

  // Show the top of the report rather than wherever Assign left the
  // caret - the model summary is the part worth landing on.
  FMemo.SelStart := 0;

  if FModel.CaseNumber = CaseDraped then
    FPlot.Title := 'Draped: the balanced state held for the whole run'
  else
    FPlot.Title := 'Exposed at t = 0: bare skin and radiation into 16 C';

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
  // of fat and 1.5 mm of skin on a 75.6 mm radius - so without the marks
  // the steepening at the right-hand edge reads as a plotting artefact
  // rather than as the layers it is.
  //
  // Each is a series with its OWN two-point x, which is why they are
  // built with PlotXY rather than passed to SetData - SetData takes one
  // shared x for every series it is given. The component stores an x per
  // series, so the two routes mix as long as SetData goes first.
  for j := 0 to FModel.InterfaceCount - 1 do
  begin

    FPlot.SetSeriesStyle(2 + j, clGray, 1.0, plsDash, FModel.InterfaceName(j));

    FPlot.PlotXY(FModel.InterfaceMm(j), lo, 2 + j);
    FPlot.PlotXY(FModel.InterfaceMm(j), hi, 2 + j);

  end;

end;

end.
