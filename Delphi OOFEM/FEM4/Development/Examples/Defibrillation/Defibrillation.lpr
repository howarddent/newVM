program Defibrillation;

{ How the current of a 200 J monophasic defibrillator shock spreads
  through a human torso. The torso is ThermEx1's trunk - the same
  elliptical cylinder of core, muscle, fat and skin, built from that
  unit's own tables - with a heart and lungs placed in its core and two
  pads in the anterolateral position, solved for the current by
  TThermalEngine as a steady conduction problem. See the header of
  uDefibModel.pas for the model and what it leaves out, and of
  uDefibView.pas for what the picture shows.

  Usage:  Defibrillation [--no-plot] [--anisotropic] [--biphasic]
                         [--snapshot=<prefix>] [--time=<ms>]

    --no-plot            solve and report, no window
    --anisotropic        muscle and chest wall conduct seven times better
                         along fibres running round the trunk than across
    --biphasic           start with the biphasic truncated exponential
                         shock rather than the monophasic damped sine (the
                         window switches between them either way)
    --snapshot=<prefix>  open the window at --time (default: the peak
                         current), save the 3D view as <prefix>_view.png
                         and the waveform as <prefix>_wave.png, and exit

  Run it from this folder: the mesh is written to mesh/ here, and gmsh
  is expected where ThermEx1 expects it. }

{$mode delphi}{$H+}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces,
  Forms, SysUtils, cblas,
  uDefibModel, uDefibView, uDefibForm;

const
  // ms; -1 is the peak.
  SnapTimes : Array[0..4] of Double = (0.2, 0.5, -1, 4.0, 8.0);

var
  Model : TDefibModel;
  Form : TDefibForm;
  ShowPlot, Aniso, Bi : Boolean;
  Snapshot : String;
  SnapTime : Double;
  DotFS : TFormatSettings;
  i : Integer;
  Arg : String;

begin

  InitializeCBLAS;

  DotFS := DefaultFormatSettings;
  DotFS.DecimalSeparator := '.';

  ShowPlot := True;
  Aniso := False;
  Bi := False;
  Snapshot := '';
  SnapTime := -1;

  for i := 1 to ParamCount do
  begin
    Arg := ParamStr(i);
    if (Arg = '--no-plot') or (Arg = '-n') then
      ShowPlot := False
    else if Arg = '--anisotropic' then
      Aniso := True
    else if Arg = '--biphasic' then
      Bi := True
    else if Copy(Arg, 1, 11) = '--snapshot=' then
      Snapshot := Copy(Arg, 12, MaxInt)
    else if Copy(Arg, 1, 7) = '--time=' then
      SnapTime := StrToFloat(Copy(Arg, 8, MaxInt), DotFS) / 1000
    else
    begin
      WriteLn('Usage: Defibrillation [--no-plot] [--anisotropic] [--biphasic] ' +
        '[--snapshot=<prefix>] [--time=<ms>]');
      Halt(1);
    end;
  end;

  Application.Initialize;
  Model := TDefibModel.Create;
  Model.Anisotropic := Aniso;
  Model.Biphasic := Bi;

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

      Form := TDefibForm.CreateNew(Application);
      Form.Attach(Model);
      Form.Show;

      if Snapshot <> '' then
      begin
        for i := 1 to 20 do
        begin
          Application.ProcessMessages;
          Sleep(20);
        end;
        if SnapTime >= 0 then
        begin
          Form.ShowTime(SnapTime);
          Application.ProcessMessages;
          Form.View.SaveToPNG(Snapshot + '_view.png');
        end
        else
          // The rise, the peak and the decay. A typed constant array, not
          // a for-in over a set literal, which FPC 3.2.2 compiles but
          // crashes on partway through (see CLAUDE.md, FilmWRM).
          for i := 0 to High(SnapTimes) do
          begin
            if SnapTimes[i] < 0 then
            begin
              Form.ShowTime(Model.TPeak);
              Arg := 'peak';
            end
            else
            begin
              Form.ShowTime(SnapTimes[i] / 1000);
              Arg := FormatFloat('0.0', SnapTimes[i], DotFS) + 'ms';
            end;
            Application.ProcessMessages;
            Form.View.SaveToPNG(Snapshot + '_' + Arg + '_view.png');
          end;
        Form.Wave.SaveToPNG(Snapshot + '_wave.png');
        // The whole window, for the layout. On Windows its GL areas come
        // out blank, which is why the views are saved separately above.
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

    end;

  finally
    Model.Free;
  end;

end.
