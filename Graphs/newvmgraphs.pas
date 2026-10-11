{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit newvmgraphs;

{$warn 5023 off : no warning about unused units}
interface

uses
  uVMPlot2D, uVMPlot3D, uVMPlotStack, uVMSpeech, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('uVMPlot2D', @uVMPlot2D.Register);
  RegisterUnit('uVMPlot3D', @uVMPlot3D.Register);
  RegisterUnit('uVMPlotStack', @uVMPlotStack.Register);
  RegisterUnit('uVMSpeech', @uVMSpeech.Register);
end;

initialization
  RegisterPackage('newVMGraphs', @Register);
end.
