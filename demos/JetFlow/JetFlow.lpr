program JetFlow;

{*******************************************************************************

     Jet flow calculator: the oxygen flow through a jet cannula of any
     bore and length at a given driving pressure, with whether the jet is
     choked and its highest Mach number, lowest temperature and lowest
     pressure. The calculation is JetVent's (../JetVent/uJetCalcVM.pas,
     the Crane 3-20 flow estimate and the exit state from the mass flow);
     the form is ujetflowmain.pas.

     Command line, for scripted screenshots: --p=<bar gauge>, --d=<mm>,
     --l=<cm> set the inputs.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, ujetflowmain;

begin
  {$IFDEF HAVE_BLAS}
  InitializeCBLAS;
  {$ENDIF}
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.CreateForm(TfmJetFlow, fmJetFlow);
  Application.Run;
end.
