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

{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit newVMSDR;

{$warn 5023 off : no warning about unused units}
interface

uses
  uSDRRFSource, uVMPlotSDRSpectrum, uDSPBlocks, uWaveOutPlayer, uFMReceiver,
  uAMReceiver, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('uSDRRFSource', @uSDRRFSource.Register);
  RegisterUnit('uVMPlotSDRSpectrum', @uVMPlotSDRSpectrum.Register);
  RegisterUnit('uFMReceiver', @uFMReceiver.Register);
  RegisterUnit('uAMReceiver', @uAMReceiver.Register);
end;

initialization
  RegisterPackage('newVMSDR', @Register);
end.
