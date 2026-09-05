program ThermEx1;

{ Core temperature of an anaesthetised adult losing heat into a cold
  theatre, using TThermalEngine. Four compartments in an elliptical
  section, conduction, blood perfusion, and a foam cushion under the
  back - see the header comment of uThermEx1.pas for what all of that
  assumes, what it leaves out, and the verification status of the
  numbers.

  Unlike the ArchEx examples this one has a window: the result is a
  temperature profile from the centre outward, taken towards the front
  and towards the back, and that is shown on a TVMPlot2D rather than as
  a field in gmsh. The numeric report still goes to stdout - the program
  keeps a console subsystem as well as the window - and the time history
  to a CSV, so --no-plot still gives a headless run.

  Usage:  ThermEx1 [1|2] [--no-plot]

    1  draped - hold the balanced state (the model's check on itself:
       nothing should move)
    2  exposed - drapes off at t = 0, bare skin and radiation into the
       theatre; this is the tracking run (default)

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
    else if TryStrToInt(Arg, v) and (v >= CaseDraped) and (v <= CaseExposed) then
      Case_ := v
    else if TryStrToFloat(Arg, Flow, DotFS) and (Flow >= 0) and (Flow <= CardiacOutputMax) then
      // A cardiac output, so the slider's value can be set headlessly too.
      Continue
    else
    begin
      WriteLn('Usage: ThermEx1 [1|2] [litres/min] [--no-plot]');
      WriteLn('  1 = draped (hold balance), 2 = exposed at t=0');
      WriteLn('  litres/min = cardiac output, 0 to 10, default 5');
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
