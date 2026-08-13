program ChebBVP;

{*******************************************************************************

     Demo: Chebyshev-collocation solution of the linear boundary-value
     problem u_xx = exp(4x), u(-1)=u(1)=0, ported from the Delphi/MtxVec
     original at demos/Chebyshev/ChebBVP - see uBVPMain.pas. Reuses TCheb/
     BaryInterpol from demos/Chebyshev/NormalIntegration/uCheb.pas rather
     than duplicating them.

*******************************************************************************}

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uBVPMain, newvmgraphs;

begin
  InitializeCBLAS;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmMain, fmMain);
  Application.Run;
end.
