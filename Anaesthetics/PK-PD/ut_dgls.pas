{***********************************************************************
*                                                                      *
* Test examples for methods to solve first order ordinary systems of   *
* differential equations.                                              *
*                                                                      *
* We supply the right hand sides, their alpha-numeric description and  *
* the exact analytic solution, if known.                               *
*                                                                      *
* When running the main test program, the user can select among the    *
* examples below.                                                      *
*                                                                      *
*                                   TPW Release By J-P Moreau, Paris.  *
*                                           (www.jpmoreau.fr)          *
* -------------------------------------------------------------------- *
* REF.: "Numerical Algorithms with C, by Gisela Engeln-Muellges        *
*        and Frank Uhlig, Springer-Verlag, 1996".                      *
***********************************************************************}
UNIT ut_dgls;

INTERFACE

Uses uGauss;

Var
    bspnummer, n: Integer;
    dgltxt: Array[0..4] of String[70];

    Procedure dgl(x:double; y:pVEC; f:pVEC);


IMPLEMENTATION

  {Note: here, only examples #0 to #4 are implemented in Pascal}

  Procedure dgl(x:double; y:pVEC; f:pVEC);
  Begin
    Case bspnummer of
      0: begin
           n:=2;
           f^[0] := y^[0] * y^[1] + COS(x) - 0.5 * SIN(2.0 * x);
           f^[1] := y^[0] * y^[0] + y^[1] * y^[1] - (ONE + SIN(x));
           dgltxt[0]:=' y1'' = y1 * y2 + cos(x) - 0.5 * sin(2.0*x)';
           dgltxt[1]:=' y2'' = y1 * y1 + y2 * y2 - (1 + sin(x))'
         end;
      1: begin
           n:=1;
           f^[0]:=-Y^[0] + x/((1+x)*(1+x));
           dgltxt[0]:=' y'' = -y + x/((1+x)*(1+x))'
         end;
      2: begin   {example for m_rwp}
           n:=2;
           f^[0] := y^[1];
           f^[1] := -y^[0] * y^[0] * y^[0];
           dgltxt[0]:=' y1'' = y2';
           dgltxt[1]:=' y2'' = -y1^3'
         end;
      3: begin
           n:=5;
           f^[0] := y^[1];
           f^[1] := y^[2];
           f^[2] := y^[3];
           f^[3] := y^[4];
           f^[4] := (45.0 * y^[2] * y^[3] * y^[4] - 40.0 * y^[3] * y^[3] * y^[3]) / (9.0 * y^[2] * y^[2]);
           dgltxt[0]:=' y1'' = y2';
           dgltxt[1]:=' y2'' = y3';
           dgltxt[2]:=' y3'' = y4';
           dgltxt[3]:=' y4'' = y5';
           dgltxt[4]:=' y5'' = (45 * y3 * y4 * y5 - 40 * y4 * y4 * y4) / (9 * y3 * y3)'
         end;
      4: begin
          {y"=(2y'y'+yy)/y}
          n:=2;
          f^[0] := y^[1];
          f^[1] := (2.0*y^[1]*y^[1]+y^[0]*y^[0])/y^[0];
          dgltxt[0]:=' y1'' = y2';
          dgltxt[1]:=' y2'' = (2y2*y2+y1*y1)/y1'
         end
    end
  End;

END. {dgl}
