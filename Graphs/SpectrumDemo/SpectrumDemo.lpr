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

program SpectrumDemo;

{*******************************************************************************

     Demo: a live power-spectrum waterfall. Every 20ms (FTimer, see
     uspectrummain.pas), a fresh 4096-point white-noise vector is
     generated, multiplied by a fixed Hamming window, FFT'd via newVM's
     FFT_R2C (newVMComplex.pas, FFTW3-backed), reduced to a 2048-point
     power spectrum, and pushed into a TVMPlotStack (Graphs/uVMPlotStack.pas)
     via AddGraph - so the stack itself, at ~50 pushes/second, is what
     produces the flowing waterfall motion; TVMPlotStack's own Animate
     property is deliberately left off (see uspectrummain.pas).

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uspectrummain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.
