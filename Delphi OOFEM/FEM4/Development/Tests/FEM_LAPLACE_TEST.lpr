program FEM_LAPLACE_TEST;

{*******************************************************************************

     FPCUnit console test runner for the Delphi_OOFEM/FEM4 (CXS.FEMLAP)
     element test suite, replacing the original DUnit
     GUI/console-runner project (FEM_LAPLACE_TEST.dpr) now that the
     library itself has been ported off Dew MtxVec onto newVM - same
     shape as newVM's own newVMtest.lpr (TPlainResultsWriter over
     GetTestRegistry, non-zero exit code on any failure/error).

     Calls InitializeCBLAS explicitly before running, same as
     newVMtest.lpr - the library code under test (newVM/newVMsparse) never
     initialises CBLAS/MKL itself, so whatever program links it in has to.

*******************************************************************************}

{$mode objfpc}{$H+}
{$APPTYPE CONSOLE}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, fpcunit, testregistry, fpcunitreport, plaintestreport,
  cblas,
  CXS.FEMLAP.TestBrick_H8V1,
  CXS.FEMLAP.TestBrick_T4V1,
  CXS.FEMLAP.TestBrick_W6V1,
  CXS.FEMLAP.TestEdge_B2V1,
  CXS.FEMLAP.TestFace_Q4V1,
  CXS.FEMLAP.TestFace_T3V1,
  CXS.FEMLAP.TestFace_T3V2,
  CXS.FEMLAP.TestFace_Q4V2;

var
  ResultsWriter: TCustomResultsWriter;
  TestResult: TTestResult;
begin
  InitializeCBLAS;
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
