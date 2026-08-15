unit Bary2D;

{*******************************************************************************


   2D Barycentric  Lagrange Interpolation using vectorised Library  mtxVec


    after barylag2d.m   Written by: Greg von Winckel in Matlab  07/16/04

  Interpolates the given data using the Barycentric Lagrange Interpolation
  formula on the unit square. (Almost!!!) Vectorized to remove all loops

 Reference:

 (1) Jean-Paul Berrut & Lloyd N. Trefethen, "Barycentric Lagrange
     Interpolation"
     http://web.comlab.ox.ac.uk/oucl/work/nick.trefethen/berrut.ps.gz
 (2) Walter Gaustschi, "Numerical Analysis, An Introduction" (1997) pp. 94-95
 (3) Eugene Isaacson and Herbert Bishop Keller, "Analysis of Numerical
    Methods", Dover Edition (1994) p. 295

  Adapted for Delphi By Dr H Dent May 2020

*******************************************************************************}


interface

uses
  AbstractMtxVec, mtxVec, mtxExpr, mtxExprInt, math387,mtxVecEdit, SysUtils;

procedure BaryLag2D( f : TMtx;     //matrix of function values for interpolation
                     xn : Tvec;    // x - values at which function defined
                     yn:  Tvec;    // y - Values at which function defined
                     xf:  Tvec;    // interpolated x - values
                     yf:  Tvec;    // interpolated y - values
                     out p : Matrix);  // Interpolation polynomial
implementation

Procedure BaryLag2D;
var
  i,M,N, Mf, Nf,M1,N1 : Integer;
  X,Xt,Y,Yt, Wx,Wy, xdist, ydist : Matrix;
  a,b : MatrixInt;
  c,d : VectorInt;
  xp,yp,zx,zy : Vector;
  xtemp : double;


begin
   M := f.Rows; M1 := M-1;  // M for size M1 for zero based indexing
   N:= f.Cols;  N1 := N-1;  // Ditto for N, N1
   Mf := xf.Length;
   Nf := yf.Length;
   if (M<>xn.Length) or (N<>yn.Length)then begin
     raise exception.create(' Error in BaryLag2d - Grid and datasize do not match');
     exit;
   end;

// Compute the Barycentric Weights:  X=repmat(xn,1,M);   Y=repmat(yn,1,N);

   zx.Length:= M; zx.SetZero;
   zx:=zx+1;
   X.size(M,M,mvDouble);
   X.Kron(xn,zx);
   zy.Length := N; zy.SetZero;
   zy:=zy+1;
   Y.Size(N,N,mvDouble);
   Y.Kron(yn,zy);

// % matrix of weights
//  Wx=repmat(1./prod(X-X.'+eye(M),1),Mf,1);
//  Wy=repmat(1./prod(Y-Y.'+eye(N),1),Nf,1);

// for Wx .....

    Wx := X-Xt.Transp(X) + eye(M,M,mvDouble);
    xp.Length:=M;
    Wx.Transp;   // Need Column products but Prod() only does rows
    for i := 0 to M1 do xp[i] := 1/Wx.product(i*M,M); // Row by row no vectorisation
    zx.Size(Mf,mvDouble); zx.SetZero; zx:= zx+1;
    Wx.kron(zx, xp); // Equivalent to Repmat()

// And Now for Wy
    Wy := Y-Yt.Transp(Y) + eye(M,M,mvDouble);
    yp.Length:=N;
    Wy.Transp;
    for i := 0 to N1 do yp[i] := 1/Wy.product(i*N,N);
    zy.Size(Nf,mvDouble); zy.SetZero; zy:= zy+1;
    Wy.kron(zy, yp);

//% Get distances between nodes and interpolation points
//  xdist=repmat(xf,1,M)-repmat(xn.',Mf,1);
//  ydist=repmat(yf,1,N)-repmat(yn.',Nf,1);

    Xt.Kron(zx, xn); // ReUse Xt Matrix for transpose
    zx.ReSize(M);
    xdist.Kron(xf, zx);
    xdist := xdist-Xt;
    xdist.FlipHor;    // Need to flip for some reason!! Kron not eq repmat

 // Now the same for y:

    Yt.Kron(zy, yn );
    zy.Resize(N);
    ydist.Kron(yf, zy);
    ydist := ydist-Yt;
    ydist.FlipHor;

//  % Find all of the elements where the interpolation point is on a node
//  [xfixi,xfixj]=find(xdist==0);
//  [yfixi,yfixj]=find(ydist==0);
//% Approximate zeros (easier than exact substitution in 2D)
// xdist(xfixi,xfixj)=eps; ydist(yfixi,yfixj)=eps;

    a.findMask(xdist,'=',0);
    d.FindIndexes(a,'<>',0);
    for i := 0 to d.Length-1 do xdist.Values1D[d[i]] := eps; // set zero to eps

// and now for y:

    a.findMask(ydist,'=',0);
    d.FindIndexes(a,'<>',0);
    for i := 0 to d.Length-1 do ydist.Values1D[d[i]] := eps; // set zero to eps

// Hx=Wx./xdist;
// Hy=Wy./ydist;

   X := Wx / xdist;  // Reuse X and Y Matrices rather than new
   Y := Wy / ydist;


// % Interpolated polynomial
//p=(Hx*f*Hy.')./(repmat(sum(Hx,2),1,Nf).*repmat(sum(Hy,2).',Mf,1));

   Yt.Transp(Y);
   Xt.Mul(x,f);
   P.Mul(Xt,Yt);
   X.SumRows(xp);
   Y.SumRows(yp);
   zx.Size(Nf,mvDouble); zx.SetZero; zx := zx+1;
   zy.Size(Mf,mvDouble); zy.SetZero; zy := zy +1;
   Xt.Kron(xp,zx);
   Yt.Kron(zy,yp);   // Reversing arguments does transpose
   P:= P / (Xt * Yt);

end;

end.
