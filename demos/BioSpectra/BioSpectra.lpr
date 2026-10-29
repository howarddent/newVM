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

program BioSpectra;

{*******************************************************************************

     Demo: frequency spectra of three biological signals - an ECG, an EEG
     and an invasive arterial pressure - from PhysioNet records (20-second
     excerpts in data/, see data/README.md). Each signal has its own tab:
     the time-domain trace above, its Hamming-windowed power spectral
     density up to the Nyquist frequency below (newVMComplex's FFT_R2C over
     FFTW), and the recording parameters from the WFDB header in a memo
     alongside - see ubiospectramain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ubiospectramain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmBio, fmBio);
  Application.Run;
end.
