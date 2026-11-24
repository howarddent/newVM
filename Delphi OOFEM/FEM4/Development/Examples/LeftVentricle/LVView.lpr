program LVView;

{ Shows one steady beat of the finite-element left ventricle: the wall
  in motion, cut open and coloured by sarcomere length or active fibre
  stress, beside the pressure-volume loop, the pressures and the valve
  flows. See the header of uLVViewForm.pas.

  Usage:  LVView [<anim file>] [--compute] [--snapshot=<prefix>]
                 [--time=<ms> | --frame=<n>] [--colour=<0..2>] [--cut=<0..2>]

    <anim file>          a file from `lvrun --anim=<file>` (default
                         out/anim_default.txt beside the program, if it
                         is there)
    --snapshot=<prefix>  open the file at --time or --frame (default the
                         start of the beat), save <prefix>_view.png,
                         _pv.png, _pressure.png, _flow.png and
                         _window.bmp, and exit
    --colour             0 sarcomere length, 1 active fibre stress, 2 plain
    --cut                0 nothing, 1 a quarter, 2 a half cut away
    --compute            press Compute at the default settings and wait

  Compute (in the window) runs lvrun, which must be built in this folder
  (see lvrun.lpr).

  Build:  lazbuild --ws=gtk2 LVView.lpi }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, SysUtils, cblas,
  uLVAnim, uLVView, uLVViewForm;

var
  Form: TLVViewForm;
  Fn, Snapshot, Arg: string;
  Frame, Colour, Cut, i: Integer;
  TimeMs: Double;
  DoCompute: Boolean;

begin
  InitializeCBLAS;
  DefaultFormatSettings.DecimalSeparator := '.';
  Fn := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'out' + PathDelim + 'anim_default.txt';
  Snapshot := '';
  Frame := 0;
  TimeMs := -1;
  Colour := 0;
  Cut := 2;
  DoCompute := False;
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 11) = '--snapshot=' then
      Snapshot := Copy(Arg, 12, MaxInt)
    else if Copy(Arg, 1, 8) = '--frame=' then
      Frame := StrToInt(Copy(Arg, 9, MaxInt))
    else if Copy(Arg, 1, 7) = '--time=' then
      TimeMs := StrToFloat(Copy(Arg, 8, MaxInt))
    else if Copy(Arg, 1, 9) = '--colour=' then
      Colour := StrToInt(Copy(Arg, 10, MaxInt))
    else if Copy(Arg, 1, 6) = '--cut=' then
      Cut := StrToInt(Copy(Arg, 7, MaxInt))
    else if Arg = '--bench' then
    else if Arg = '--compute' then
      DoCompute := True
    else if Copy(Arg, 1, 2) <> '--' then
      Fn := Arg
    else
    begin
      WriteLn('Usage: LVView [<anim file>] [--compute] [--snapshot=<prefix>] [--time=<ms> | --frame=<n>]'
        + ' [--colour=<0..2>] [--cut=<0..2>]');
      Halt(1);
    end;
  end;

  Application.Initialize;
  Form := TLVViewForm.CreateNew(Application);
  Form.Show;
  Form.SetLook(Colour, Cut);
  if FileExists(Fn) then
    Form.LoadAnim(Fn);
  if DoCompute then
  begin
    Form.Compute;
    while Form.Computing do
    begin
      Application.ProcessMessages;
      Sleep(20);
    end;
  end;

  if ParamStr(ParamCount) = '--bench' then
  begin
    for i := 1 to 20 do begin Application.ProcessMessages; Sleep(20); end;
    WriteLn(Format('%.0f frames/s', [Form.Benchmark(300)]));
    Halt;
  end;
  if Snapshot <> '' then
  begin
    for i := 1 to 20 do
    begin
      Application.ProcessMessages;
      Sleep(20);
    end;
    if (TimeMs >= 0) and (Form.Anim.Frames > 0) then
      Frame := Form.Anim.FrameAtTime(TimeMs / 1000);
    Form.ShowFrameAt(Frame);
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
