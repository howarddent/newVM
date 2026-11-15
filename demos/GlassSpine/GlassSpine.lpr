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

program GlassSpine;

{*******************************************************************************

     Demo: the spread of hyperbaric and plain (isobaric) bupivacaine in
     two transparent dural sacs, by Stam's Stable Fluids in OpenCL with an
     OpenGL ray-marched view; the sacs can be turned in any posture while
     gravity stays fixed. See uglassspinemain.pas, uglassspinesim.pas and
     glassspine.cl.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uglassspinemain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmGlassSpine, fmGlassSpine);
  Application.Run;
end.
