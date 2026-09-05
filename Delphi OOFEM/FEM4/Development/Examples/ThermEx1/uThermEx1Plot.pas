unit uThermEx1Plot;

{ The window ThermEx1 shows its result in: the temperature profile from
  the centre of the body outward, at t = 0 and at the end of the run and
  taken both towards the front and towards the back, on one TVMPlot2D,
  with the run's own report beside it and a cardiac-output slider under
  it.

  Generation is uniform within each compartment and the ends are
  adiabatic, so a field plot of the solid adds little that a profile
  does not already say. What it can no longer be is ONE profile: the
  patient lies on a foam cushion, so the back of the section conducts
  into foam while the front loses heat to the room, and the difference
  between the two curves is the whole point of the model. Front is drawn
  solid and back dashed; red is the balanced starting state and blue the
  end of the run; the dotted verticals are the compartment boundaries.

  The horizontal axis is s, the semi-major axis of the similar ellipse
  through a point - the section's own radial coordinate, and the plain
  radius again if AspectRatio is set back to 1. Each compartment
  boundary is one value of s, which is what lets a single set of
  verticals mark them for both curves.

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

{ The front pair shares one X and goes in through SetData; the back pair
  cannot, since it is drawn from a different set of nodes and so lands
  on a different set of s values, and is built point by point with
  PlotXY instead. TVMPlot2D keeps an X per series, so the two routes mix
  freely as long as SetData goes first - which is also how the boundary
  markers below get their own two-point X. }
procedure TProfileForm.RefreshDisplay;
var

  i, j : Integer;

  lo, hi : Double;

  SF, F0, FE, SB, B0, BE : TVMobj;

  procedure Span(const T : TVMobj);
  var
    c : Integer;
  begin

    for c := 0 to T.Cols - 1 do
    begin
      if T[0, c] < lo then lo := T[0, c];
      if T[0, c] > hi then hi := T[0, c];
    end;

  end;

begin

  FModel.GetRadialProfiles(psFront, SF, F0, FE);
  FModel.GetRadialProfiles(psBack, SB, B0, BE);

  Caption := Format('ThermEx1 - case %d, cardiac output %.1f L/min',
    [FModel.CaseNumber, FModel.CardiacOutput]);

  FMemo.Lines.Assign(FModel.Report);

  // Show the top of the report rather than wherever Assign left the
  // caret - the model summary is the part worth landing on.
  FMemo.SelStart := 0;

  if FModel.CaseNumber = CaseDraped then
    FPlot.Title := 'Draped: the balanced state held for the whole run'
  else
    FPlot.Title := 'Exposed at t = 0: bare front and radiation into 16 C, ' +
                   'back still on the cushion';

  FPlot.XAxisTitle := 'Similar-ellipse coordinate s (mm)';
  FPlot.YAxisTitle := 'Temperature (C)';

  // Red starts, blue ends - the run only ever cools, so the warm curve
  // is the one it started from. Solid is the exposed front, dashed the
  // part lying on the foam.
  FPlot.SetSeriesStyle(0, clRed, 2.0, plsSolid, 'Front, t = 0');
  FPlot.SetSeriesStyle(1, clBlue, 2.0, plsSolid, 'Front, end of run');
  FPlot.SetSeriesStyle(2, clRed, 2.0, plsDash, 'Back (on cushion), t = 0');
  FPlot.SetSeriesStyle(3, clBlue, 2.0, plsDash, 'Back (on cushion), end');

  FPlot.SetData(SF, [F0, FE]);

  for i := 0 to SB.Cols - 1 do
  begin
    FPlot.PlotXY(SB[0, i], B0[0, i], 2);
    FPlot.PlotXY(SB[0, i], BE[0, i], 3);
  end;

  // The temperature range all four profiles span, so the boundary
  // markers are drawn full height whatever the run did.
  lo := F0[0, 0];
  hi := lo;

  Span(F0);
  Span(FE);
  Span(B0);
  Span(BE);

  // Mark each compartment boundary. The outer layers are thin - 3.5 mm
  // of fat and 2.3 mm of skin on a 116.6 mm semi-major axis, and half
  // that towards the front and back - so without the marks the
  // steepening at the right-hand edge reads as a plotting artefact
  // rather than as the layers it is.
  //
  // Each is a series with its OWN two-point x, which is why they are
  // built with PlotXY, as the back profile above is.
  for j := 0 to FModel.InterfaceCount - 1 do
  begin

    FPlot.SetSeriesStyle(4 + j, clGray, 1.0, plsDot, FModel.InterfaceName(j));

    FPlot.PlotXY(FModel.InterfaceMm(j), lo, 4 + j);
    FPlot.PlotXY(FModel.InterfaceMm(j), hi, 4 + j);

  end;

end;

end.
