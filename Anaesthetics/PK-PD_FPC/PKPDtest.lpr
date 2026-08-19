program PKPDtest;

{*******************************************************************************

     FPCUnit console test runner for the Anaesthetics/PK-PD_FPC demo's ported
     PK/PD engine. Test cases live in uPKPDTests.pas. Same shape as newVM's
     own newVMtest.lpr - a plain-text pass/fail gate, not a demo.

*******************************************************************************}

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}
{$I ../../newVMConfig.inc}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpcunit, testregistry, fpcunitreport, plaintestreport,
  uPKPDTests, cblas;

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
