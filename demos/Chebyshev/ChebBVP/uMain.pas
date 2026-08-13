unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, MtxExpr, MtxBaseComp,
  MtxVecTools, MtxParseExpr,MtxVec, Vcl.StdCtrls, Vcl.Grids, VclTee.TeeGDIPlus,
  VCLTee.TeEngine, Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart, VCLTee.Series,
  VCLTee.TeeSpline;



type
  TCheb = class
  private
    x : Vector;
    D : TMtx;
    D2 : TMtx;
    Size : Integer;
    constructor create(N : Integer);
    destructor Destroy;
  end;



  type
    TfmMain = class(TForm)
    PageControl1: TPageControl;
    TabSheet1: TTabSheet;
    TabSheet2: TTabSheet;
    StringGrid1: TStringGrid;
    StringGrid2: TStringGrid;
    Memo1: TMemo;
    Button1: TButton;
    Chart1: TChart;
    Series1: TPointSeries;
    Series2: TLineSeries;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Button1Click(Sender: TObject);
  private
    ACheb : TCheb;
    f,u :Vector;
    DD : Matrix;
  public
    { Public declarations }
  end;

var
  fmMain: TfmMain;

implementation

{$R *.dfm}

uses
  MtxDialogs, MtxVecEdit,MtxExprInt,Math387,PolyNoms,MtxVecTee;

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


procedure TfmMain.Button1Click(Sender: TObject);
var
  v,ix,iy,Coeff,Delta,exact: Vector;
  R : Matrix;
  L2R,eps : Tsample;
  I,DegF: Integer;
  s : String;
begin
  StartTimer;
// Straightforward direct solve
  u:=LUSolve(f,DD);
  Memo1.Lines.Add('Time for Direct Solve '+FloatTostr(1000*StopTimer)+' ms');
// Now need to reize solution vector back to fullsize ading zeroes at begining
// and end
  v.resize(ACheb.Size+1,True);
  v.Copy(u,0,1,ACheb.Size-1);
//  Plot the Calculated Points
  for i:= 0 to Acheb.Size do Chart1.Series[0].AddXY(ACheb.x[i],v[i]);
  ix.length:=201;
  iy.length:=201;
  ix.Ramp(-1,0.01);
// Polynomial interpolation (For Practice!!!)
// TeeChart Can do a nice interpolated line itself!
  StartTimer;
  PolyFit(Acheb.x,v,16,Coeff,R,DegF,L2R); //Fit 16th order for exact fit
  PolyEval(ix,Coeff,R,DegF,L2R,iy,Delta); //  evaluate
  Memo1.Lines.Add('Time for Exact Interpolation '+FloatTostr(1000*StopTimer)+' ms');

//  for i:=0 to ix.length-1 do Chart1.Series[1].AddXY(ix[i],iy[i]);
//Now for error Calculation use NormC function
  exact:=(exp(4*ix)-sinh(4)*ix-cosh(4))/16;
  s:= ' max err = '+floatToStr(exact.NormC(iy,0,0,201,False));
  Chart1.Title.Caption:=Chart1.Title.Caption+s;
  startTimer;
  BaryInterpol( Acheb.x, v, ix, iy);
  Memo1.Lines.Add('Time for Barycentric Interpolation '+FloatTostr(1000*StopTimer)+' ms');
  for i:=0 to ix.length-1 do Chart1.Series[1].AddXY(ix[i],iy[i]);
end;

procedure TfmMain.FormCreate(Sender: TObject);
const
  MtxDim = 16;
begin
  Inherited;
  StringGrid1.RowCount := MtxDim+1;
  StringGrid1.ColCount := MtxDim+1;
  StringGrid2.RowCount := 200;
  StringGrid2.ColCount := MtxDim+2;
  StringGrid1.Cells[0,0] := 'A';
  StringGrid2.Cells[0,0] := 'V';
  Chart1.Title.Color:= clBlack;
  Chart1.Title.Caption:='u_xx = exp(4x), u(-1)=u(1)=0 Spectral Methods p13';
 {Write A to StringGrid1 }
  StartTimer;
  ACheb:=TCheb.create(MtxDim);
  DD:=Matrix.Create(MtxDim-1,MtxDim-1);
  u.Resize(MtxDim-1);
  F.Resize(MtxDim-1);
  Memo1.Lines.Add('Time to create Tcheb Object '+FloatTostr(1000*StopTimer)+' ms');
  With Acheb do begin
//  To accomodate boundary conditions 1st an last rows and columns of matrix zero
//  So copy Second derivative matrix to smaller matrix
    DD.Copy(D2,1,1,0,0,MtxDim-1,MtxDim-1);
    ValuesToGrid(DD,StringGrid1,0,0,'0.0000',True);
//  Function zero at boundaries so compute solution on smaller vector
    u.Copy(x,1,0,MtxDim-1);
    f:=exp(4*u);
  end;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  ACheb.Destroy;
  Inherited;
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
    CreateIt(D,D2);
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

destructor TCheb.Destroy;
begin
  FreeIt(D);
  FreeIt(D2);
//  FreeIt(x);
  inherited;
end;




end.
