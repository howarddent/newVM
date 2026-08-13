unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, VCLTee.TeEngine,
  Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart, MtxVec,MtxExpr,
  VCLTee.Series, MtxVecTee,AbstractMtxVec,MtxVecInt,Math387;

Const
  N = 32;
  gN =201;

type
  TCheb = class
  private
    x : Vector;
    D : Matrix;
    D2 : Matrix;
    Size : Integer;
    constructor create(N : Integer);
  end;


type
  TfmMain = class(TForm)
    Memo1: TMemo;
    Chart1: TChart;
    btnExecute: TButton;
    Series1: TLineSeries;
    Series2: TMtxFastLineSeries;
    procedure FormCreate(Sender: TObject);
    procedure btnExecuteClick(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private

  public
    a : TCheb;
    ix,x,y,gx,gy,iy : Vector;
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

uses
 MtxExprInt;

procedure BaryInterPol(var x,fx,gridx,gridy : Vector);
var
  i : Integer;

  sx, sgrid : Integer;
  c,numer, denom, xdiff, xtemp  : Vector;
  a, Exact :  VectorInt;   // To be used for index manipulation

begin
  sx := x.Length-1;
  sgrid := gridy.Length;
  c.Length := sx+1;
  numer.Length:= sgrid;
  denom.Length:=sgrid;
  xtemp.Length:=sgrid;
  a.Length := Sgrid;
  Exact.Length:=sgrid;
  for i := 0 to sx do c[i]:=intpower(-1,i);
  c[0] := c[0] * 1/2;
  c[sx]:=c[sx]*1/2;
  numer.SetZero;
  denom.SetZero;
  for i := 0 to sx  do begin
     xdiff:=gridx-x[i];
     xtemp := c[i] / xdiff;
     numer := numer +xtemp*fx[i];
     denom := denom + xtemp;
     a.findmask(xdiff,'=',0);  // Find exact matches between interpolating
     Exact := Exact + a * (i+1) ; // grid and function points
  end;
//  ViewValues(exact,'exact');
  gridy := numer / denom;
  XTemp.Copy(Exact); // Int To Float
  a.FindIndexes(XTemp,'<>',0);
  for i:=0 to a.Length-1 do gridy[a[i]]:=fx[exact[a[i]]-1];
end;

function curtis_clenshaw(var f : vector):Double;
//
// integrate function defined at chebyshev points
// spectral methods P128
//
begin

end;

procedure TfmMain.btnExecuteClick(Sender: TObject);
begin
  baryInterpol(x,y,gx,gy);   // For the gaussian
  DrawValues(4*gx,gy,Series1);
  baryInterpol(x,iy,gx,gy);  // For the definite integral
  DrawValues(4*gx,gy,Series2);
  Memo1.lines.add('1 SD = '+FloatToStr(100*(gy[125]-gy[75]))+' %');
  Memo1.lines.add('2 SD = '+FloatToStr(100*(gy[150]-gy[50]))+' %');
  Memo1.lines.add('3 SD = '+FloatToStr(100*(gy[175]-gy[25]))+' %');
end;


procedure TfmMain.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  A.Free;
end;

procedure TfmMain.FormCreate(Sender: TObject);
begin
  A:=TCheb.create(N);
  x.Size(N+1);
  ix.Size(N+1);
  iy.Size(N+1);
  y.size(N+1);
  gx.size(gN);
  gx.ramp(-1,0.01);
  gy.size(gN);
  ix.ramp;
  x := cos(ix*pi/N);
  y := 1/math387.sqrt(2*pi)*exp(-sqr(x)*8);  //Scaled to give +/- 4 sd on chebyshev interval -1,1
  A.D.LUSolve(y,iy);  // Generate Integral By Solving D(integral) = f(x)
  iy :=4*(iy-iy[N]); // Remove constant term
  iy := iy+(0.5-iy[N div 2]); // Correct to If(0) = 0.5
end;

{ TCheb }

constructor TCheb.create(N: Integer);
var
  I,J : Integer;
  CI,CJ,Sign: Integer;
begin
  Inherited Create;
  if N>0 then begin
    Size := N;
//    CreateIt(x);
    x.Length:= N+1;
    D.Resize(N+1,N+1);
    D2.Resize(N+1,N+1);
// Set x to contain N+1 Chebychev points
    for I := 0 to N do x[I]:=cos(I*Pi/N);
// Now calculate general elements
    for I := 0 to N do
      for J := 0 to N do begin
//Check for diagonal elements
        if I=J then begin
          if I=0 then D[0,0]:=(2*sqr(N)+1)/6
          else if I=N then D[N,N]:=-D[0,0]
          else  D[I,J]:=-x[J]/(2*(1-sqr(x[J])));
        end
        else begin
          if (I =0) or (I=N) then CI:=2 else CI:=1;
          if (J =0) or (J=N) then CJ:=2 else CJ:=1;
          if ((I+J) Mod 2=0) then Sign:=1 else Sign :=-1;
          D[I,J]:= (Sign*CI/CJ)/(x[i]-x[j]);
        end;
      end;
      D2.MtxIntPower(D,2);  //Second derivative matrix
  end;
end;



end.
