unit CXS.FEMLAP.ShellExec;

{$mode delphi}{$H+}

interface

uses Process;

// Cross-platform replacement for the original Windows-only
// ShellExecuteEx-based implementation (see git history). TProcess (unit
// Process, part of FPC's fcl-process, already on the default unit search
// path with no extra Lazarus package needed) runs on both Windows and
// Unix, so this now works unchanged on either platform. Args is an array
// of already-split command-line arguments rather than one Parameters
// string - TProcess.Parameters takes each argument as its own TStrings
// entry (no shell-style re-splitting/quoting the way ShellExecute's single
// Parameters string got parsed by Windows itself), so callers must split
// their own arguments rather than passing one space-joined string.
function Sto_ShellExecute(const FileName: String; const Args: array of String;
  var ExitCode: Cardinal; const Wait: Cardinal = 0;
  const Hide: Boolean = False): Boolean;

implementation

uses SysUtils;

/// <summary>
///   Executes an external program.</summary>
/// <param name="FileName">Full path (or, on Unix, a bare name resolved via
///   PATH) of the executable.</param>
/// <param name="Args">Command line arguments, one per array element.</param>
/// <param name="ExitCode">Exitcode of application (only available
///   if Wait > 0 and the process didn't time out).</param>
/// <param name="Wait">[milliseconds] Maximum time to wait until the
///   application has finished. After reaching this timeout, the
///   application is terminated and False is returned. 0 = don't wait,
///   return immediately once launched.</param>
/// <param name="Hide">If True, application runs with no visible window
///   (Windows only - TProcess's ShowWindow option is a no-op on Unix,
///   where a GUI app's window visibility isn't controlled this way).</param>
/// <returns>True if the application could be started (and, if Wait > 0,
///   finished within the timeout); False if it could not be started or
///   the timeout was reached.</returns>
function Sto_ShellExecute(const FileName: String; const Args: array of String;
  var ExitCode: Cardinal; const Wait: Cardinal = 0;
  const Hide: Boolean = False): Boolean;
var
  Proc: TProcess;
  i: Integer;
  StartTick: QWord;
begin
  ExitCode := 0;
  Result := False;

  Proc := TProcess.Create(nil);
  try
    Proc.Executable := FileName;
    for i := 0 to High(Args) do
      Proc.Parameters.Add(Args[i]);

    if Hide then
      Proc.ShowWindow := swoHIDE
    else
      Proc.ShowWindow := swoShowNormal;

    try
      Proc.Execute;
    except
      Exit(False);
    end;

    Result := True;

    if Wait > 0 then
    begin
      // TProcess's own poWaitOnExit blocks with no timeout, so poll
      // Running instead and Terminate if the deadline passes - the same
      // "wait up to N ms, then kill it" contract the original
      // WaitForSingleObject/TerminateProcess implementation had.
      StartTick := GetTickCount64;
      while Proc.Running do
      begin
        if GetTickCount64 - StartTick > Wait then
        begin
          Proc.Terminate(0);
          Result := False;
          Break;
        end;
        Sleep(20);
      end;
      if Result then
        ExitCode := Cardinal(Proc.ExitStatus);
    end;
  finally
    Proc.Free;
  end;
end;

end.
