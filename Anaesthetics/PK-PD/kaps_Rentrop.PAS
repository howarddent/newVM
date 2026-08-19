{ *********************************************************************************************


             Routine to integrate a system of first order non-linear stiff equations.
             Uses Kaps-Rentrop algorithm translated from fortran.

             Effectively Implicit RK45. For Linear Sytems Jacobian = System Matrix

             From Numerical recipes in fortran p732.       15/1/94

             Vectorized with Dew MtxVec Library May 2023

             2024 Added matrix return of all intermediate values in yResult
             rows 0..N-1 are values af y[N] at times intermediate between times x1, x2 and
             row N contains times of evaluation

             H.Dent

**********************************************************************************************}

Unit kaps_Rentrop;


Interface

Uses
  MtxVec,MtxExpr,MtxExprInt,Math387,SysUtils;


Type
  TErrFlags = ( TooManySteps,TooShortStep,OK, Abandoned );
  TJacobn = Procedure( var x :double;var y,dfdx : Vector; var dfdy :Matrix;
                           n : integer ) of object;
  TDerivs = Procedure( x : double; var y,dydx : Vector ) of object;

  Function Stiff( var y,dydx : Vector; n : Integer; var x,htry,eps : double;
                  var yscal : Vector; var hdid,hnext : double;
                    Derivs : TDerivs;Jacobn : TJacobn; var yResult : Matrix): TErrFlags;


  Function OdeInt( Var yStart : Vector; n : integer; x1,x2,eps,h1,hmin :Double;
                      Derivs : TDerivs;Jacobn : TJacobn; var yResult :Matrix ):TErrFlags;

 var
   progress : Int64;
   Abandon : Int64;


{**********************************************************************************************

                                      Implementation

***********************************************************************************************}
implementation

Function Stiff;

Label  99;
Const
  Safety = 0.9; Grow = 1.5; PGrow = -0.25; Shrnk = 0.5;
  Pshrnk = -1/3; Errcon = 0.1296; MaxTry = 40;
  Gam = 0.231;
  A21 = 2; A31 = 4.52470820736; A32 = 4.16352878860;
  C21 = -5.07167533877; C31 = 6.0201572865; C32 = 0.159750684673; C41 = -1.856343618677;
  C42 = -8.50538085819; C43 = -2.08407513602;
  B1 = 3.95750374663; B2 = 4.62489238836; B3 = 0.617477263873; B4 = 1.282612945268;
  E1 = -2.30215540292; E2 = -3.07363448539; E3 = 0.873280801802; E4 = 1.282612945268;
  C1X = Gam;C2X = -0.39629667752e-01;C3X =0.550778939579 ; C4X =-0.5535098457e-01;
  A2X = 0.462; A3X = 0.880208333333;

var
  i,j,jtry : Integer;
  Indx : VectorInt;
  d,errmax,h,xsav,temp : double;
  a,L,U,dgnl,dfdy,tempy,tempz : Matrix;
  v,dfdx,dysav,err,g1,g2,g3,g4,g_out,ysav : Vector;

begin
  xsav := x;
  ysav.copy(y);
  dysav.copy(dydx);

  jacobn( xsav,ysav,dfdx,dfdy,n ); { this routine is specific to the application }

  h := htry;
  for  jtry := 1 to MaxTry do
  begin {Set up matrix  (I-gam * h * jacobn)  }
    a.copy(dfdy);
    v.Size(n,mvDouble); // v=0
    v.SetZero;
    dgnl.Size(n,n,mvDouble);  //dgnl=0
    v:=v+1/(gam*h);   //setup (1/gamma*h)*I
    dgnl.Diag(v,0);
    a:=dgnl-a;      // subtract d

    a.LUSolve(mtGeneral,L,U,indx);  //LU decompose matrix

    g1:=dysav+h*C1x*dfdx;

    a.LUSolve(g1,g1,mtgeneral,opNone,L,U,indx);  //backsub solve for g1

    y:=ysav+A21*g1;
    x := xsav + A2X * h;
    derivs( x,y,dydx );


    g2:=dydx+h*C2X*dfdx+C21*g1/h;    //setup fo g2 solve

    a.LUSolve(g2,g2,mtgeneral,opNone,L,U,indx);



    y:=ysav+A31*g1+A32*g2;
    x := xsav + A3X * h;
    derivs( x,y,dydx );


    g3:=dydx+h*C3X*dfdx+(C31*g1+C32*g2)/h;

    a.LUSolve(g3,g3,mtgeneral,opNone,L,U,indx); //backsub solve for g3

    g4:=dydx+h*C4X*dfdx+(C41*g1+C42*g2+C43*g3)/h;

    a.LUSolve(g4,g4,mtgeneral,opNone,L,U,indx);


    y:= ysav+B1*g1+B2*g2+B3*g3+B4*g4;
    err:= E1*g1+E2*g2+E3*g3+E4*g4;
    x := xsav + h;
    errMax:=max(abs(err/yscal))/eps;
    if errmax <= 1 then
    begin
      hdid := h;
      if errmax > ERRCON then
        hnext := Safety*h*power(errmax,pgrow)
      else
      hnext := Grow*h;
      stiff := ok;
      tempy.CopyVec(y,N);
      tempy.Size(N+1,1,mvDouble);
      tempy[N,0]:=x;
      tempz.ConcatHorz([yResult,tempy]);
      yresult.Copy(tempz);
      if abandon <> 0 then stiff := Abandoned;
      exit;

   {if errmax > errcon }
    end
    else
    begin
      hnext := safety*h*power(errmax,pshrnk);
      if hnext < Shrnk * h then hnext := Shrnk * h;
      h := hnext;
    end; { if errmax <= 1}

  end; { for jtry }
  stiff := TooManySteps;
end;


Function OdeInt( Var yStart : Vector; n : integer; x1,x2,eps,h1,hmin :Double;
                      Derivs : TDerivs;Jacobn : TJacobn; var yResult : Matrix ):TErrFlags;

label
  99;

const
  MaxStp = 1000;
  tiny = 1e-30;

var
  nstp,i : integer;
  xsav,x,hnext,hdid,h,temp :double;
  yscal,dydx : Vector;

begin
  x := x1;
  if x2 >= x1 then h := abs( h1 ) else h := -abs( h1 );
  For nstp := 1 to MaxStp do
  begin
    derivs(x,ystart,dydx );
    yscal:=abs(ystart)+abs(h*dydx)+TINY;
    if (x+h-x2)*(x+h-x1) > 0 then h := x2-x;
     stiff( yStart,dydx,n,x,h,eps,yScal,hdid,hnext,derivs,jacobn,yResult );
    if (x-x2) * (x2-x1) >= 0 then
    begin
      odeint := ok;
      progress := round((x*100)/(x2-x1));
      if abandon <> 0 then begin
        odeInt := Abandoned;
        exit;
      end;
      goto 99; {exit loop if step achieved }
    end; {if (x-x2) etc }
    if abs( hnext ) < hmin then
    begin
      odeint := TooShortStep;
      goto 99;
    end;
    h := hnext;
    progress := round((x*100)/(x2-x1));
    if abandon <> 0 then begin
      odeInt := Abandoned;
      exit;
    end;

  end;
  odeint := TooManySteps;
99:
end;

{***********************************************************************************************

                                   End of Unit kaps_Rentrop

***********************************************************************************************}

end.