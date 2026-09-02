program ThermEx1;

{ Core temperature of an anaesthetised adult losing heat into a cold
  theatre, using TThermalEngine. Conduction only - see the header comment
  of uThermEx1.pas for what that leaves out, blood perfusion above all.

  A plain console program, like the ArchEx examples: the core temperature
  history goes to stdout and to a CSV, and the temperature fields are
  viewed in gmsh, so it runs headless.

  Usage:  ThermEx1 [1|2] [--no-view]

    1  draped - hold the balanced state (the model's check on itself:
       nothing should move)
    2  exposed - drapes off at t = 0, bare skin and radiation into the
       theatre; this is the tracking run (default)

    --no-view   write the results but do not launch gmsh afterwards }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  SysUtils, cblas,
  uThermEx1;

var

  Model : TThermalModel;

  Case_, i, v : Integer;

  ViewResults : Boolean;

  Arg : String;

begin

  InitializeCBLAS;

  Case_ := CaseExposed;
  ViewResults := True;

  for i := 1 to ParamCount do
  begin

    Arg := ParamStr(i);

    if (Arg = '--no-view') or (Arg = '-n') then
      ViewResults := False
    else if TryStrToInt(Arg, v) and (v >= CaseDraped) and (v <= CaseExposed) then
      Case_ := v
    else
    begin
      WriteLn('Usage: ThermEx1 [1|2] [--no-view]');
      WriteLn('  1 = draped (hold balance), 2 = exposed at t=0');
      Halt(1);
    end;

  end;

  Model := TThermalModel.Create(Case_);

  try

    try
      Model.Run(ViewResults);
    except
      on E : Exception do
      begin
        WriteLn;
        WriteLn('ERROR: ', E.Message);
        Halt(1);
      end;
    end;

  finally

    Model.Free;

  end;

end.
