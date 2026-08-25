unit CXS.FEMLAP.ShellExec;

{$mode delphi}{$H+}

interface

uses Windows, ShellApi;

function Sto_ShellExecute(const FileName, Parameters: String;
  var ExitCode: DWORD; const Wait: DWORD = 0;
  const Hide: Boolean = False): Boolean;

implementation

/// <summary>
///   Executes an external program or opens a document with its
///   standard application.</summary>
/// <param name="FileName">Full path of application or document.</param>
/// <param name="Parameters">Command line arguments.</param>
/// <param name="ExitCode">Exitcode of application (only avaiable
///   if Wait > 0).</param>
/// <param name="Wait">[milliseconds] Maximum of time to wait,
///   until application has finished. After reaching this timeout,
///   the application will be terminated and False is returned as
///   result. 0 = don't wait on application, return immediately.</param>
/// <param name="Hide">If True, application runs invisible in the
///   background.</param>
/// <returns>True if application could be started successfully, False
///   if app could not be started or timeout was reached.</returns>
function Sto_ShellExecute(const FileName, Parameters: String;
  var ExitCode: DWORD; const Wait: DWORD = 0;
  const Hide: Boolean = False): Boolean;
var
  myInfo: SHELLEXECUTEINFO;
  iWaitRes: DWORD;
begin
  // prepare SHELLEXECUTEINFO structure
  ZeroMemory(@myInfo, SizeOf(SHELLEXECUTEINFO));
  myInfo.cbSize := SizeOf(SHELLEXECUTEINFO);
  myInfo.fMask := SEE_MASK_NOCLOSEPROCESS or SEE_MASK_FLAG_NO_UI;
  myInfo.lpFile := PChar(FileName);
  myInfo.lpParameters := PChar(Parameters);
  if Hide then
    myInfo.nShow := SW_HIDE
  else
    myInfo.nShow := SW_SHOWNORMAL;
  // start file
  ExitCode := 0;
  // FPC's ShellApi declares both an ANSI and a WIDE ShellExecuteEx
  // overload and can't infer which from a bare "@myInfo" (the generic
  // SHELLEXECUTEINFO alias doesn't disambiguate for overload resolution
  // the way it does in Delphi) - this codebase uses plain 8-bit
  // AnsiString throughout (no {$mode delphiunicode}/UNICODE define), so
  // pick the ANSI overload explicitly.
  Result := ShellExecuteEx(LPSHELLEXECUTEINFOA(@myInfo));
  // if process could be started
  if Result then
  begin
    // wait on process ?
    if (Wait > 0) then
    begin
      iWaitRes := WaitForSingleObject(myInfo.hProcess, Wait);
      // timeout reached ?
      if (iWaitRes = WAIT_TIMEOUT) then
      begin
        Result := False;
        TerminateProcess(myInfo.hProcess, 0);
      end;
      // get the exitcode
      GetExitCodeProcess(myInfo.hProcess, ExitCode);
    end;
    // close handle, because SEE_MASK_NOCLOSEPROCESS was set
    CloseHandle(myInfo.hProcess);
  end;
end;

end.
