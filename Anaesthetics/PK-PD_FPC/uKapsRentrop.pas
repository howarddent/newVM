unit uKapsRentrop;

{*******************************************************************************

     Kaps-Rentrop stiff-ODE integrator (effectively implicit RK4/5; for a
     linear system the Jacobian is just the system matrix itself), from
     Numerical Recipes in Fortran p732. Ported from
     Anaesthetics/PK-PD/kaps_Rentrop.PAS (H.Dent, MtxVec-based) onto this
     repo's own newVM.pas TVMobj.

     The only structural change from the MtxVec original: MtxVec's
     `a.LUSolve(mtGeneral,L,U,indx)` (factorise) followed by four
     `a.LUSolve(g,g,...,L,U,indx)` calls (solve, reusing the factors) becomes
     four plain `LinearSolve(a, gN)` calls - newVM's LinearSolve caches its
     LU factorisation on A itself (A.LU/A's internal pivots, see
     newVM.pas's own header comment on LinearSolve), so the first call
     factorises `a` and the next three transparently reuse it. No separate
     L/U/pivot bookkeeping needed at all.

     Everything else is a direct syntactic port: MtxVec's Vector and Matrix
     both become TVMobj (a vector is just an (n,1) column here, same
     convention newVM already uses throughout). newVM has no elementwise
     Abs or a max-of-elements reduction (this file's error-norm line is
     the only place either is needed), so two small local helpers cover
     them rather than growing newVM.pas for a single caller's use.
     Elementwise divide, previously a third local helper here for the same
     reason, is now just newVM's own divObj function - see that error-norm
     line below. (newVM's '/' operator itself stays scalar-only - TVMobj
     has no same-type TVMobj/TVMobj '/' operator, only divObj.)

     Ported for the Anaesthetics/PK-PD_FPC newVM demo. Original: Dr Howard
     Dent, 15/1/94 (Numerical Recipes port), vectorized with Dew MtxVec
     05/2023.

*******************************************************************************}

{$mode delphi}{$H+}

interface

uses
  newVM, Math, SysUtils;

Type
  TErrFlags = ( TooManySteps,TooShortStep,OK, Abandoned );
  TJacobn = Procedure( var x :double;var y,dfdx : TVMobj; var dfdy :TVMobj;
                           n : integer ) of object;
  TDerivs = Procedure( x : double; var y,dydx : TVMobj ) of object;

  Function Stiff( var y,dydx : TVMobj; n : Integer; var x,htry,eps : double;
                  var yscal : TVMobj; var hdid,hnext : double;
                    Derivs : TDerivs;Jacobn : TJacobn; var yResult : TVMobj): TErrFlags;

  Function OdeInt( Var yStart : TVMobj; n : integer; x1,x2,eps,h1,hmin :Double;
                      Derivs : TDerivs;Jacobn : TJacobn; var yResult :TVMobj ):TErrFlags;

 var
   progress : Int64;
   Abandon : Int64;


{**********************************************************************************************

                                      Implementation

***********************************************************************************************}
implementation

// Small local helpers - see header comment above for why these live here
// rather than in newVM.pas itself.

function ElementwiseAbs(const A: TVMobj): TVMobj;
var
  r, c : Integer;
begin
  result := TVMobj.Create(A.Rows, A.Cols);
  for r := 0 to A.Rows-1 do
    for c := 0 to A.Cols-1 do
      result[r,c] := Abs(A[r,c]);
end;

function MaxElement(const A: TVMobj): Double;
var
  r, c : Integer;
begin
  result := A[0,0];
  for r := 0 to A.Rows-1 do
    for c := 0 to A.Cols-1 do
      if A[r,c] > result then result := A[r,c];
end;

Function Stiff( var y,dydx : TVMobj; n : Integer; var x,htry,eps : double;
                  var yscal : TVMobj; var hdid,hnext : double;
                    Derivs : TDerivs;Jacobn : TJacobn; var yResult : TVMobj): TErrFlags;

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
  jtry : Integer;
  errmax,h,xsav : double;
  a,dgnl,dfdy,tempy : TVMobj;
  v,dfdx,dysav,err,g1,g2,g3,g4,ysav : TVMobj;

begin
  xsav := x;
  ysav := CopyObj(y);
  dysav := CopyObj(dydx);

  jacobn( xsav,ysav,dfdx,dfdy,n ); { this routine is specific to the application }

  h := htry;
  for  jtry := 1 to MaxTry do
  begin {Set up matrix  (I-gam * h * jacobn)  }
    a := CopyObj(dfdy);
    v := TVMobj.Create(n,1);     // zero-filled
    dgnl := TVMobj.Create(n,n);  // zero-filled
    v := AddScalar(v, 1/(gam*h));  //setup (1/gamma*h)*I
    dgnl := Diag(v);
    a := dgnl - a;      // subtract d

    g1 := dysav+h*C1x*dfdx;

    LinearSolve(a, g1);  // factorises a, then backsub-solves for g1

    y := ysav+A21*g1;
    x := xsav + A2X * h;
    derivs( x,y,dydx );

    g2 := dydx+h*C2X*dfdx+C21*g1/h;    //setup fo g2 solve

    LinearSolve(a, g2);   // a is already factorised - reuses the cached LU

    y := ysav+A31*g1+A32*g2;
    x := xsav + A3X * h;
    derivs( x,y,dydx );

    g3 := dydx+h*C3X*dfdx+(C31*g1+C32*g2)/h;

    LinearSolve(a, g3); //backsub solve for g3

    g4 := dydx+h*C4X*dfdx+(C41*g1+C42*g2+C43*g3)/h;

    LinearSolve(a, g4);

    y := ysav+B1*g1+B2*g2+B3*g3+B4*g4;
    err := E1*g1+E2*g2+E3*g3+E4*g4;
    x := xsav + h;
    errMax := MaxElement(ElementwiseAbs(divObj(err,yscal))) / eps;
    if errmax <= 1 then
    begin
      hdid := h;
      if errmax > ERRCON then
        hnext := Safety*h*power(errmax,pgrow)
      else
      hnext := Grow*h;
      Stiff := ok;
      tempy := MergeUD(CopyObj(y), TVMobj.Create(1,1,[x]));
      yResult := MergeLR(yResult, tempy);
      if abandon <> 0 then Stiff := Abandoned;
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
  Stiff := TooManySteps;
end;


Function OdeInt( Var yStart : TVMobj; n : integer; x1,x2,eps,h1,hmin :Double;
                      Derivs : TDerivs;Jacobn : TJacobn; var yResult : TVMobj ):TErrFlags;

label
  99;

const
  MaxStp = 1000;
  tiny = 1e-30;

var
  nstp : integer;
  x,hnext,hdid,h :double;
  yscal,dydx : TVMobj;

begin
  x := x1;
  if x2 >= x1 then h := abs( h1 ) else h := -abs( h1 );
  For nstp := 1 to MaxStp do
  begin
    derivs(x,ystart,dydx );
    yscal := AddScalar(ElementwiseAbs(ystart) + ElementwiseAbs(h*dydx), TINY);
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

                                   End of Unit uKapsRentrop

***********************************************************************************************}

end.
