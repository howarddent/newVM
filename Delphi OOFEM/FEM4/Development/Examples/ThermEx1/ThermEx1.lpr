program ThermEx1;

{ Core temperature of an anaesthetised adult losing heat into a cold
  theatre, using TThermalEngine. Conduction only - see the header comment
  of uThermEx1.pas for what that leaves out, blood perfusion above all,
  and for the verification status of the numbers.

  Unlike the ArchEx examples this one has a window: the model is radially
  symmetric, so its whole result is a temperature profile against radius,
  and that is shown on a TVMPlot2D rather than as a field in gmsh. The
  numeric report still goes to stdout - the program keeps a console
  subsystem as well as the window - and the time history to a CSV, so
  --no-plot still gives a headless run.

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
  newVM,
  uThermEx1,
  uThermEx1Plot;

var

  Model : TThermalModel;

  Form : TProfileForm;

  Case_, i, v : Integer;

  ShowPlot : Boolean;

  Arg, Sub : String;

  R, T0, TEnd : TVMobj;

begin

  InitializeCBLAS;

  Case_ := CaseExposed;
  ShowPlot := True;

  for i := 1 to ParamCount do
  begin

    Arg := ParamStr(i);

    if (Arg = '--no-plot') or (Arg = '--no-view') or (Arg = '-n') then
      ShowPlot := False
    else if TryStrToInt(Arg, v) and (v >= CaseDraped) and (v <= CaseExposed) then
      Case_ := v
    else
    begin
      WriteLn('Usage: ThermEx1 [1|2] [--no-plot]');
      WriteLn('  1 = draped (hold balance), 2 = exposed at t=0');
      Halt(1);
    end;

  end;

  Application.Initialize;

  Model := TThermalModel.Create(Case_);

  try

    try
      Model.Run;
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

      Model.GetRadialProfiles(R, T0, TEnd);

      if Model.CaseNumber = CaseDraped then
        Sub := 'Draped: the balanced state held for the whole run'
      else
        Sub := 'Exposed at t = 0: bare skin and radiation into 16 C';

      Form := TProfileForm.CreateNew(Application);

      Form.ShowProfiles(R, T0, TEnd,
        Format('ThermEx1 - radial temperature profile, case %d',
          [Model.CaseNumber]),
        Sub, Model.LeanRadiusMm);

      Form.Show;

      Application.Run;

    end;

  finally

    Model.Free;

  end;

end.
