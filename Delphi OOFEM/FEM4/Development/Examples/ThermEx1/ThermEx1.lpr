program ThermEx1;

{ Core temperature of an anaesthetised adult losing heat into a cold
  theatre, using TThermalEngine. A spherical head, an elliptical trunk
  and cylindrical arms and legs, each built from core, muscle, fat and
  skin compartments (the limbs without a core), with conduction, blood
  perfusion, and a foam cushion under the back - see the header comment
  of uThermEx1.pas for what all of that assumes, what it leaves out, and
  the verification status of the numbers.

  Unlike the ArchEx examples this one has a window: the result is a
  temperature profile through the trunk from its centre outward, taken
  towards the front and towards the back, and that is shown on a
  TVMPlot2D on the window's front tab rather than as a field in gmsh,
  with the numeric report on a second tab. The report still goes to
  stdout too - the program keeps a console subsystem as well as the
  window - and the time history to a CSV, so --no-plot still gives a
  headless run.

  Usage:  ThermEx1 [1|2|3] [--no-plot]

    1  draped - hold the balanced state (the model's check on itself:
       nothing should move)
    2  exposed - drapes off at t = 0, bare skin and radiation into the
       theatre; this is the tracking run (default)
    3  gowned - drapes off at t = 0 as in 2, but the front of the trunk
       and the arms stay under a thin cotton gown over a millimetre of
       still air, so the room sees the cloth there rather than the skin

    --no-plot   run and report, but do not open the plot window }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  Interfaces,           // the LCL widgetset
  Forms,
  SysUtils, cblas,
  uThermEx1,
  uThermEx1Plot;

var

  DotFS : TFormatSettings;

  Model : TThermalModel;

  Form : TProfileForm;

  Case_, i, v : Integer;

  Flow : Double;

  ShowPlot : Boolean;

  Arg : String;

begin

  InitializeCBLAS;

  // Parse the cardiac output with a dot separator whatever the locale.
  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';

  Case_ := CaseExposed;
  ShowPlot := True;
  Flow := CardiacOutputDefault;

  for i := 1 to ParamCount do
  begin

    Arg := ParamStr(i);

    if (Arg = '--no-plot') or (Arg = '--no-view') or (Arg = '-n') then
      ShowPlot := False
    else if TryStrToInt(Arg, v) and (v >= CaseDraped) and (v <= CaseGowned) then
      Case_ := v
    else if TryStrToFloat(Arg, Flow, DotFS) and (Flow >= CardiacOutputMin) and
            (Flow <= CardiacOutputMax) then
      // A cardiac output, so the slider's value can be set headlessly too.
      Continue
    else
    begin
      WriteLn('Usage: ThermEx1 [1|2|3] [litres/min] [--no-plot]');
      WriteLn('  1 = draped (hold the drapes on), 2 = exposed at t=0,');
      WriteLn('  3 = exposed at t=0 but gowned over the trunk and arms');
      WriteLn('  litres/min = cardiac output, 1 to 10, default 5 - give 1, 2 or 3');
      WriteLn('               as 1.0, 2.0 or 3.0, or they are read as the case');
      Halt(1);
    end;

  end;

  Application.Initialize;
  Model := TThermalModel.Create(Case_);

  try

    try
      Model.Prepare;
      Model.Solve(Flow);
    except
      on E : Exception do
      begin
        WriteLn;
        WriteLn('ERROR: ', E.Message);
        Halt(1);
      end;
    end;

    if ShowPlot then
    begin

      Form := TProfileForm.CreateNew(Application);

      Form.Attach(Model);

      Form.Show;

      Application.Run;

    end;

  finally

    Model.Free;

  end;

end.
