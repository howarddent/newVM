program newPoly;

{*******************************************************************************

     Demo: least-squares polynomial fitting with newPolymath.pas's
     TPolynomial.Fit over newVM vectors. A degree-1, -2 or -3 polynomial
     is sampled at 50 points, Gaussian noise is added, a polynomial of the
     same degree is fitted back, and the data, the true curve and the fit
     are drawn on one TVMPlot2D with the residuals on a second one
     underneath - see unewpolymain.pas.

*******************************************************************************}

{$mode objfpc}{$H+}
{$I ../../newVMConfig.inc}

uses
  {$IF defined(UNIX) and not defined(DARWIN)}
  cthreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, cblas, unewpolymain;

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
