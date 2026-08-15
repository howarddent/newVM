unit uCheb;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, MtxExpr, MtxBaseComp,
  MtxVecTools, MtxParseExpr,MtxVec, Vcl.StdCtrls, Vcl.Grids, VclTee.TeeGDIPlus,
  VCLTee.TeEngine, Vcl.ExtCtrls, VCLTee.TeeProcs, VCLTee.Chart, VCLTee.Series,
  VCLTee.TeeSpline, Sparse, Bary2D;

type
  TCheb = class
  private
    x : Vector; //Tchebychev Grid
    D : Matrix; //Differentiation Matrix
    D2 : Matrix;  //2nd Order Differentaition Matrix = D^2
    D2R : Matrix; // Reduced 2nd Order Diff Matrix for u(-1)=u(1)=0 b.c.
    u : Vector; // Reduced 1D Solution Vector  for u(-1)=u(1)=0 b.c.
    Size : Integer;
    constructor create(N : Integer);
  end;

type
  T2DGrid =class
  Private
    XGrid : Matrix;
    XLongGrid : Vector;
    YGrid : Matrix;
    YLongGrid : Vector;
  Public
    Constructor Create(N : Integer);
    Procedure MeshGrid(Src : Vector); // Create Tchebychev 2D Grid In XGrid And YGrid;
  end;

  T2DLaplace = class
    private
      Cheb1D:TCheb;  // Original Cheb 1D grid and Differentiation Matrices
      Grid2D :T2DGrid; // 2D Grid of Tchebychev Points
      kronX, KronY :Matrix; // I*D2 and D2*I Product matrices for Laplacian
      Laplace : Matrix;     // For assembled laplacian matrix
    public
      ResultGrid : Matrix;  //2_D grid for result
      PlotGrid : Matrix;
      Constructor create(N:Integer);
      Function Solve:Double;virtual;
  end;

  T2DWave = Class(T2DLaplace)
    private
      vv, vvold : Matrix;
    public
    Constructor create( N :Integer);
    Function Solve : Double; override;
  End;

implementation
uses
  MtxDialogs, MtxVecEdit,Math387,PolyNoms, uBicubic;
{ TCheb }

procedure Kronprod(M1,M2 : Matrix; var M_Out :Matrix);
// Produce a kroneker product matrix from M1,M2.

var
  i,j,p,q,r,s : Integer;
  temp : Matrix;
begin
  p:=M1.Rows;q:=M1.Cols;
  r:=M2.Rows;s:=M2.Cols;
  M_Out:=Matrix.create(p*r,q*s,mvDouble);
  for i  := 0 to p-1 do
    for j := 0 to q-1 do begin
      temp.Copy(M2);
      temp.scale(M1.values[i,j]);
      M_Out.Copy(temp,0,0,i*r,j*s,r,s,False);
    end;
end;

procedure GridToVec(M: Matrix; var v : Vector);
var
  p,q,i,j,k : integer;
begin
  p:=M.Rows;q:=M.Cols;
  k:=0;
  for j:= 0 to q-1 do begin
    for i:=0 to p-1 do begin
       v[k]:=M.Values[i,j];
       k:=k+1;
    end;
  end;
end;

Procedure VecToGrid(V:Vector; var M :Matrix);
// Takes a long vector and turns into a square N+1 by N+1 grid padded by
//zeroes in rows and columns 0 and N+1. This only works for
//Dirichlet BC's u(0)=u(N+1)=0

var
  p,q,r,i,j : Integer;
begin
  p:=M.Rows-2; q:=M.Cols-2;
  if p*q<>V.length then begin
    MessageDlg('VecToGrid - Length of vector not compatible with grid',mtError,[mbOK],0);
    Exit;
  end;
  j:=0; //Column Index
  for i := 0 to v.Length-1 do begin   //i is vector index
    r:= (i mod p)+1;
    if r=1 then j:=j+1;
    M.Values[r,j]:=v.Values[i];
  end;
end;

constructor TCheb.create(N: Integer);
var
  I,J : Integer;
  CI,CJ,Sign: Integer;
begin
  Inherited Create;
  if N>0 then begin
    Size := N;
    x:=Vector.Create(N+1,mvDouble);
    D:=Matrix.Create(N+1,N+1,mvDouble);
    D2:=Matrix.Create(N+1,N+1,mvDouble);
    D2R:= Matrix.Create(N-1,N-1,mvDouble);
    u:=Vector.Create(N-1,mvDouble);
// Set x to contain N+1 Chebychev points
    for I := 0 to N do x[I]:=-cos(I*Pi/N);
// Now calculate general elements
    for I := 0 to N do
      for J := 0 to N do begin
//Check for diagonal elements
        if I=J then begin
          if I=0 then D.Values[0,0]:=(2*sqr(N)+1)/6
          else if I=N then D.values[N,N]:=-D.Values[0,0]
          else  D.values[I,J]:=-x.Values[J]/(2*(1-sqr(x.Values[J])));
        end
        else begin
          if (I =0) or (I=N) then CI:=2 else CI:=1;
          if (J =0) or (J=N) then CJ:=2 else CJ:=1;
          if ((I+J) Mod 2=0) then Sign:=1 else Sign :=-1;
          D.Values[I,J]:= (Sign*CI/CJ)/(x.Values[i]-x.Values[j]);
        end;
      end;
      D2.MtxIntPower(D,2);  //Second derivative matrix
      D2R.Copy(D2,1,1,0,0,N-1,N-1); //Reduced differentiation matrix for for u(-1)=u(1)=0 b.c.
      u.Copy(x,1,0,N-1); //Create reduced vector for x for u(-1)=u(1)=0 b.c.
//      ViewValues(u,'u');
  end;
end;

{ T2DLaplace }

constructor T2DLaplace.create(N: Integer);
var
  I_Mat : Matrix; // Identity Matrix for Kroneker Product
begin
  Inherited Create;
  Cheb1D := TCheb.create(N);
  Grid2D:=T2DGrid.Create(N);
  Grid2D.MeshGrid(Cheb1D.u);
  Laplace :=Matrix.Create(N-1,N-1,mvDouble);
  I_Mat.Eye(N-1,N-1,mvDouble);
  KronProd(I_Mat,Cheb1D.D2R,kronX);
  KronProd(Cheb1D.D2R,I_Mat,kronY);
  Laplace:=kronX+kronY;
  ResultGrid:=Matrix.Create(N+1,N+1,mvDouble);
  ResultGrid.SetZero;
  PlotGrid:=Matrix.Create(50,50,mvDouble);
end;

function T2DLaplace.Solve:Double;
const
 InterPSize = 40;
var
 f,v,vi,xf,yf : Vector;
 x : Double;
 IP2 :TInterP2;
 lx,ly : Matrix;
 xb,yb : Matrix;
 ASparse : TSparseMtx;


begin
 With Grid2D do begin
//    ASparse := TSparseMtx.Create;
    f:=10*sin(8*XLongGrid*(YLongGrid-1));
    v:=vector.Create(f.Length,mvDouble);
    StartTimer;
//    Asparse.DenseToSparse(Laplace);
//    Asparse.IterativeMethod := itmJAC;
//    ASparse.SolveIterative(f,v);
    Laplace.LUSolve(f,v);
    Result:=StopTimer;
    VecToGrid(v,ResultGrid);
// Now create (N+1 by N+1)  Xgrid for interpolating final result:

{    vi.Create(Cheb1D.x.Length); //  Need grid longer than v
    vi.SetZero;
    vi:=vi+1;   // Vectorised set all elemts of vi to 1!
    lx.Kron(vi,Cheb1D.x); //create larger x grid
    ly.Kron(Cheb1D.x,vi); // same for y
    viewValues(lx,'lx');
    viewValues(ly,'ly');}
   //Recreate grid vectors to hold x and y values
    vi:=vector.Create(PlotGrid.Rows,mvDouble);
    vi.SetZero;
    xf.Size(200,mvDouble);xf.Ramp(-1,0.01);
    yf.copy(xf);
    xb:=Matrix.Create(50,50,mvDouble);
    yb:=Matrix.Create(50,50,mvDouble);
    vi:=vi+1;
    xb.Kron(vi,Cheb1D.x);
    yb.transp(xb);
//    IP2:= TInterp2.Create(Cheb1D.x,Cheb1D.x,ResultGrid,Cheb1D.x.length);
//    IP2.GridInterp2(xb,yb,PlotGrid);
    ViewValues(Cheb1D.x,'Cheb1D.x');
//    StartTimer;
    BaryLag2D(ResultGrid,Cheb1D.x,Cheb1D.x, xf,yf, PlotGrid);
//    Result := StopTimer;
 end;
end;

{ T2DGrid }

constructor T2DGrid.Create(N: Integer);
begin
  Inherited Create;
  XGrid := Matrix.Create(N,N,mvDouble);
  YGrid := Matrix.Create(N,N,mvDouble);
  XLongGrid := Vector.Create((N-1)*(N-1),mvDouble);
  YLongGrid.Create((N-1)*(N-1),mvDouble);
end;


procedure T2DGrid.MeshGrid(Src : Vector);
var
  i,j,len : Integer;
  v : vector;
begin
  len := Src.Length;
  v.Resize(len);
  v.SetZero;
  v:=v+1;
//  for i:=0 to src.length do v[i]:=1;
  XGrid.Kron(v,Src); // Create X grid from X Vector
  GridToVec(XGrid,XlongGrid);
//  ViewValues(XGrid,'XGrid After Copy');
  YGrid.Kron(Src,v); // Same For Y grid
  GridToVec(YGrid,YLongGrid);
//  ViewValues(Ygrid,'Ygrid After Copy');

end;


{ T2DWave }

constructor T2DWave.create(N: Integer);
var
  xf,yf : Vector;
begin
  Cheb1D := TCheb.create(N);
  Grid2D:=T2DGrid.Create(N);
  Grid2D.MeshGrid(Cheb1D.u); // for x,y coordinates;
  With Grid2D do begin
    vv := exp( -40 * Sqr(XGrid-0.4)+Sqr(yGrid));
  end;
//  ViewValues(vv,'vv');
//  ViewValues(Cheb1d.x,'Cheb1D.x');
    vvOld := vv;
   PlotGrid:=Matrix.Create(200,200,mvDouble);
   xf.Size(200,mvDouble); xf.ramp(-1,0.01);
   yf := xf;
//   BaryLag2D(vv,Cheb1D.x,Cheb1D.x,xf,yf,PlotGrid);
end;

function T2DWave.Solve: Double;
begin

end;

end.
