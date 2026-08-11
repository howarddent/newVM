{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit newvmgraphs;

{$warn 5023 off : no warning about unused units}
interface

uses
  uVMPlot2D, uVMPlot3D, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('uVMPlot2D', @uVMPlot2D.Register);
  RegisterUnit('uVMPlot3D', @uVMPlot3D.Register);
end;

initialization
  RegisterPackage('newVMGraphs', @Register);
end.
