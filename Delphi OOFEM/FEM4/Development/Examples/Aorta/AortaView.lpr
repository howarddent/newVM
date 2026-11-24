program AortaView;

{ The arterial pulse wave in motion: the aorta, iliacs and left arm of
  uAortaTree drawn in OpenGL and coloured by pressure, beside pressure
  against time at four sites, pressure against distance at the instant
  shown, and the flows. See the header of uAortaViewForm.pas.

  Usage:  AortaView [<lvrun csv>] [--stiff=<x>] [--stiffother=<x>]
                    [--cperiph=<mL/mmHg>] [--walltau=<ms>] [--beats=<n>]
                    [--snapshot=<prefix>] [--time=<ms>] [--bench]

    <lvrun csv>          the ventricle's beat (default
                         ../LeftVentricle/out/beat.csv)
    --snapshot=<prefix>  show the instant --time, save <prefix>_view.png,
                         _pressure.png, _wave.png, _flow.png and
                         _window.bmp, and exit

  Build:  lazbuild --ws=gtk2 AortaView.lpi }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, SysUtils, cblas,
  uArtery1D, uAortaTree, uAortaView, uAortaViewForm;

var
  Form: TAortaViewForm;
  Snapshot, Arg: string;
  i, Beats: Integer;
  TimeMs, Stiff, Other, CPer, WTau: Double;
  Bench: Boolean;

begin
  InitializeCBLAS;
  DefaultFormatSettings.DecimalSeparator := '.';
  Snapshot := ''; TimeMs := 0; Stiff := 1; Other := 1; CPer := 0.8; WTau := 5; Beats := 0; Bench := False;
  Application.Initialize;
  Form := TAortaViewForm.CreateNew(Application);
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 11) = '--snapshot=' then Snapshot := Copy(Arg, 12, MaxInt)
    else if Copy(Arg, 1, 7) = '--time=' then TimeMs := StrToFloat(Copy(Arg, 8, MaxInt))
    else if Copy(Arg, 1, 8) = '--stiff=' then Stiff := StrToFloat(Copy(Arg, 9, MaxInt))
    else if Copy(Arg, 1, 13) = '--stiffother=' then Other := StrToFloat(Copy(Arg, 14, MaxInt))
    else if Copy(Arg, 1, 10) = '--cperiph=' then CPer := StrToFloat(Copy(Arg, 11, MaxInt))
    else if Copy(Arg, 1, 10) = '--walltau=' then WTau := StrToFloat(Copy(Arg, 11, MaxInt))
    else if Copy(Arg, 1, 8) = '--beats=' then Beats := StrToInt(Copy(Arg, 9, MaxInt))
    else if Arg = '--bench' then Bench := True
    else if Copy(Arg, 1, 2) <> '--' then Form.LVFile := ExpandFileName(Arg)
    else
    begin
      WriteLn('Usage: AortaView [<lvrun csv>] [--stiff=<x>] [--stiffother=<x>] [--cperiph=<C>] [--walltau=<ms>] [--beats=<n>]'
        + ' [--snapshot=<prefix>] [--time=<ms>] [--bench]');
      Halt(1);
    end;
  end;
  if Beats = 0 then
    if CPer > 0 then Beats := 25 else Beats := 12;
  Form.SetModel(Stiff, Other, CPer, Beats, WTau);
  Form.Show;
  for i := 1 to 10 do begin Application.ProcessMessages; Sleep(20); end;
  Form.Compute;

  if Bench then
  begin
    WriteLn(Format('%.0f frames/s', [Form.Benchmark(300)]));
    Halt;
  end;
  if Snapshot <> '' then
  begin
    for i := 1 to 20 do begin Application.ProcessMessages; Sleep(20); end;
    Form.ShowFrameAt(Form.FrameAtTime(TimeMs / 1000));
    Application.ProcessMessages;
    Form.SaveSnapshot(Snapshot);
    with Form.GetFormImage do
    try
      SaveToFile(Snapshot + '_window.bmp');
    finally
      Free;
    end;
    Application.Terminate;
  end
  else
    Application.Run;
end.
