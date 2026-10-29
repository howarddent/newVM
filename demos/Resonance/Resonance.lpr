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

program Resonance;

{*******************************************************************************

     Demo: resonance and damping of a second-order system

         H(s) = wn^2 / (s^2 + 2 zeta wn s + wn^2)

     computed on newVM vectors with the elementwise Exp/Sin/Sqr/Ln/Sqrt
     functions and operator overloads, and drawn on two TVMPlot2D
     components: the impulse response h(t) above, the magnitude response
     |H(j w)| below, one curve per chosen damping ratio - see
     uresonancemain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uresonancemain;

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
