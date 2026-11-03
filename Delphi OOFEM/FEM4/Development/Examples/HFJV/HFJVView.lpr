program HFJVView;

{ Shows one steady cycle of high-frequency jet ventilation in the
  abdomen: the cavity's geometry, its anterior wall and diaphragm moved
  and coloured by their displacement, the front midline's profile and
  the lung volume - anim_wall.py's animation, live. See the header of
  uHFJVViewForm.pas.

  Usage:  HFJVView [<anim file>] [--compute [--box]] [--snapshot=<prefix>]
                   [--frame=<n>]

    <anim file>          a file from `hfjvrun --anim=<file>` (default
                         mesh/wall_anim_200.txt beside the program, if
                         it is there)
    --snapshot=<prefix>  open the file at --frame (default 0), save
                         <prefix>_view.png, _profile.png, _volume.png
                         and _window.bmp, and exit
    --compute            press Compute at the default settings (with
                         --box, for the box abdomen) and wait for it

  Compute (in the window) runs hfjvrun, which must be built in this
  folder (see hfjvrun.lpr). }

{$mode delphi}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, SysUtils, cblas,
  uWallAnim, uWallView, uHFJVViewForm;

var
  Form : THFJVViewForm;
  Fn, Snapshot, Arg : String;
  Frame, i : Integer;
  DoCompute, Box : Boolean;

begin
  InitializeCBLAS;
  Fn := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'mesh' + PathDelim + 'wall_anim_200.txt';
  Snapshot := '';
  Frame := 0;
  DoCompute := False;
  Box := False;
  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if Copy(Arg, 1, 11) = '--snapshot=' then
      Snapshot := Copy(Arg, 12, MaxInt)
    else if Copy(Arg, 1, 8) = '--frame=' then
      Frame := StrToInt(Copy(Arg, 9, MaxInt))
    else if Arg = '--compute' then
      DoCompute := True
    else if Arg = '--box' then
      Box := True
    else if Copy(Arg, 1, 2) <> '--' then
      Fn := Arg
    else
    begin
      WriteLn('Usage: HFJVView [<anim file>] [--compute [--box]] [--snapshot=<prefix>] [--frame=<n>]');
      Halt(1);
    end;
  end;

  Application.Initialize;
  Form := THFJVViewForm.CreateNew(Application);
  Form.Show;
  if FileExists(Fn) then
    Form.LoadAnim(Fn);
  if DoCompute then
  begin
    Form.Compute(Box);
    while Form.Computing do
    begin
      Application.ProcessMessages;
      Sleep(20);
    end;
  end;

  if Snapshot <> '' then
  begin
    for i := 1 to 20 do
    begin
      Application.ProcessMessages;
      Sleep(20);
    end;
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
