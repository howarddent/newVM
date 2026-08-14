program newVMtest;

{*******************************************************************************

     FPCUnit console test runner for the newVM* matrix/vector library.

     The actual test cases live in newVMTests.pas (one TTestCase per
     TVMobj/TVMobjS/TVMobjZ/TVMobjC type, registered there via RegisterTest).
     This program just runs everything in GetTestRegistry through a plain-text
     results writer and sets the process exit code to non-zero on any
     failure or error, so it can be used as a real pass/fail gate rather than
     an eyeballed demo.

*******************************************************************************}

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{$I newVMConfig.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpcunit, testregistry, fpcunitreport, plaintestreport,
  newVMTests, cblas;

var
  ResultsWriter: TCustomResultsWriter;
  TestResult: TTestResult;
begin
  {$IFDEF HAVE_BLAS}
  InitializeCblas;
  {$ENDIF}
  ResultsWriter := TPlainResultsWriter.Create(nil);
  TestResult := TTestResult.Create;
  try
    TestResult.AddListener(ResultsWriter);
    GetTestRegistry.Run(TestResult);
    ResultsWriter.WriteResult(TestResult);
    if (TestResult.NumberOfErrors <> 0) or (TestResult.NumberOfFailures <> 0) then
      ExitCode := 1;
  finally
    TestResult.Free;
    ResultsWriter.Free;
  end;
end.
