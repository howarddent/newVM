program SpectralDiff;

{*******************************************************************************

     Demo: Chebyshev spectral differentiation via DCT-I (newVM's DCT1),
     recoded from the original raw-FFTW3 demo at
     /home/howard/projects/Lazarus/fftw3 (unit1.pas/project1.lpr) to use
     newVM.pas's TVMobj and its new DCT1 function instead of calling
     fftw_plan_r2r_1d/fftw_execute_r2r directly - see ufuncmain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ufuncmain;

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
