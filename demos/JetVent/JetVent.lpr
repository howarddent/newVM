program JetVent;

{*******************************************************************************

     Jet ventilation calculator - Free Pascal / newVM port of prjJetVent.dpr
     (the Delphi/MtxVec/TeeChart original, kept alongside for reference).

     Calculates jet flow, velocity, Mach number, stall pressure and mass
     flow for a set of jet cannulae over a range of driving pressures, and
     plots them against the measured values, on a TVMPlot2D. The
     calculations live in uJetCalcVM.pas (newVM vectors, newPolymath fits
     for the Crane A-22 tables, and a corrected Mach number from the gas
     state at the cannula exit rather than a fixed 342 m/s); the form is
     uJetMain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uJetMain;

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
