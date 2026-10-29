{
  This file is part of newVM.
  Copyright (C) 2026 Howard Dent
  SPDX-License-Identifier: GPL-3.0-or-later

  newVM is free software: you can redistribute it and/or modify it under
  the terms of the GNU General Public License as published by the Free
  Software Foundation, either version 3 of the License, or (at your
  option) any later version. It is distributed WITHOUT ANY WARRANTY; see
  the file LICENSE at the top of the repository for details.
}

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
