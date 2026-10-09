program Resonance;

{*******************************************************************************

     Demo: resonance and damping of a second-order system

         H(s) = wn^2 / (s^2 + 2 zeta wn s + wn^2)

     computed on newVM vectors with the elementwise Exp/Sin/Sqr/Ln/Sqrt
     functions and operator overloads, and drawn on two TVMPlot2D
     components: the impulse response h(t) above, the magnitude response
     |H(j w)| below, one curve per chosen damping ratio - see
     uresonancemain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, uresonancemain;

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
