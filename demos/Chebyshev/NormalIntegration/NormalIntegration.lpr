program NormalIntegration;

{*******************************************************************************

     Demo: standard normal PDF/CDF via Chebyshev spectral differentiation
     and barycentric interpolation, ported from the Delphi/MtxVec original
     at demos/Chebyshev/Normal_Integration - see uCheb.pas and
     uNormMain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uNormMain, newvmgraphs;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
