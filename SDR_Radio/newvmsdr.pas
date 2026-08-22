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
