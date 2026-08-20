unit uModel3Comp;

{*******************************************************************************

    Implements Various anaesthetic drug 3 Compartment Models Allowing
    calculations of plasma remifentanil concentrations for Propofol
    Remifent Mixtures run according to propofol models

    Uses the RK4 Integration routine From Numerical recipes with fixed step
    size; RKF45 from DMath library with auto-adjust stepsize and
    various published body stats Formulas.

    Uses the Pharmacokinetic data from Stanpump DRUGS.C module
    https://github.com/StevenLShafer/stanpumpR/blob/master/Original%20Stanpump/DRUGS.C

    Dr Howard Dent          Started 24/07/2022

*******************************************************************************}

interface
uses
  urkf, uTypes, Math, DateUtils, Sysutils,MtxVec,MtxExpr,Math387, uBodystats,
  usecant,ubisect;

const
  T_Pump = 10; // Pump cycle time = 10 seconds

Type
  TWeightModel = (Act_BW, I_BW, L_BM, Adj_BW);
  TCompartments = (V1=0,V2=1,V3=2);
  TDrugs = (Propofol=0,Fentanyl=1,Alfentanil=2,
    Remifentanil=3,Thiopentone=4,Midazolam=5,Dexmedetomidine=6);
  TModels =(Marsh=0,Schafer=1,Scott=2,Schneider=3,Minto=4,
    Maitre=5,Geller=6,Paedfusor=7,Eleveld=8,Dyck=9,Hannivoort=10);
  TModelParams = Record
    DrugName : String;
    ModelName : String;
    ValidModels : set of TModels;
    Plasma_Units,Compartment_Units :String;
    Inf_Rate,Concentration : Double;
    V1,V2,V3,Eff,K,k10,k12,k13,k21,k31,ke0,TTPE,Cl1,Cl2,Cl3,Ce50,BIS : Double;
    C_LOC,C_Rec : Double; // Effect compartment concentration for LOC abd recovery
    Compartments : Vector;
    DiffMatrix : Matrix;
    EigenVecs : Matrix;
    Eigenvals : Vector;
    I,W,X,A_inv,P_inv : Matrix;
  End;


  TM3Comp = class(TObject)
    fdrug : Tdrugs;
    fmodel :Tmodels;
    fCompartments : TVector;   // Vector containing compartment drug concentrations
    fModelParams : TModelParams; // used to create differential function
  private
    function diffY(t: Double; y: Vector; N: Integer): Vector;
    procedure f(X : Float; Y, Yp : TVector);
    procedure kaps_df( x : double; var y,dydx : Vector );
    procedure kaps_jac( var x :double;var y,dfdx : Vector; var dfdy :Matrix;
                           n : integer );
   function read_Ce50:double;
  Public
    FHeight, fWeight, fIBW,fBMI, fAdj_BW : Double;
    fAge : Tage;
    fSex : TSex;
    Constructor Create(Drug: TDrugs; Model:Tmodels;Actual_Weight:Integer;Height:double;Age:TAge;Sex:TSex);
    function Analytic_initBolus_solve(Bolus : Double; totalTime,Interval:Double): Matrix;
    function RK4_init_bolus_solve(Bolus, totalTime, Interval: Double): Matrix;
    function RK45_init_bolus_solve(Bolus, totalTime, Interval: Double): Matrix;
    function RK4_const_plasma_solve(Plasma_Target, totalTime,StopTime,
      Interval: Double): Matrix;
    function RK45_const_effect_solve(Effect_Target, totalTime, StopTime,
      Interval: Double): Matrix;
    function RK45_const_plasma_solve(Extra_Bolus,Plasma_Target, totalTime, StopTime,
      Interval: Double): Matrix;
    function Arbitrary_Infusion(Rate : Vector;Bolus, TotalTime, Interval : Double): Matrix;
    function Pump_Arbitrary_Infusion(Rate : Vector;Bolus, TotalTime: Double): Matrix;
    function Analytic_Single_Step(Yinit : Vector; Infusion_Rate, Tstart,Tend : Double):Vector;
    function kaps_init_bolus_solve(Bolus, totalTime, Interval: Double): Matrix;
    function y_Strang(bolus,t :double):Vector;
    function dy_strang(bolus,t : double):vector;
    function y_eff(t  :float):float; // for bisection root finder
    function find_TPeak:Double;
    function calc_eff_init_bolus(target : double):Double;
    function Bristol_10_8_6_Infusion(weight: Double;TotalTime, Interval : Double): Matrix;
    function Bristol_12_9_6_Infusion(weight : double; TotalTime, Interval : Double): Matrix;
    function BIS(Ce :Double):Double;
  published
    property pCe50 : Double read read_Ce50;
  end;

Type
  TDiffFn=Function(t:Double;y:Vector;N:Integer):Vector of object;  // for RK4
  TDiffEqs = procedure(X : Float; Y, Yp : TVector) of object;  // for RK45
  TFunc = Function(t: Float):Float of object;


const
  DrugNameStrings: Array [TDrugs] of string =('Propofol','Fentanyl','Alfentanil','Remifentanil',
    'Thiopentone','Midazolam','Dexmedetomidine');
  ModelNameStrings : Array [TModels] of String =('Marsh','Schafer','Scott','Schneider','Minto',
    'Maitre','Geller','Paedfusor','Eleveld','Dyck','Hannivoort');

implementation


uses kaps_Rentrop;


procedure TM3Comp.kaps_df( x : double; var y,dydx : Vector );
begin
  dydx:=Mul(fmodelparams.DiffMatrix,y);
//  inc(FCalls);

end;

procedure TM3Comp.kaps_jac( var x :double;var y,dfdx : Vector; var dfdy :Matrix;
                                      n : integer );
begin
  dfdx:=[0,0,0,0];
  dfdy.copy(fmodelParams.DiffMatrix);
end;


function RK4(StartT,EndT:double; InitVector :Vector;DiffFn:TDiffFn; N:Integer):Vector;
//Perform single step of Runge-Kutta fourth order algorithm
// advancing solution from startT to endT from initial vector
// using external derivative function. N = number of equations

var
 h : double;
 k1,k2,k3,k4 :Vector; //From MtxExpr - allows vectorised maths
 i : integer;
begin
  h := EndT-StartT;
  k1.Length:=N;k2.Length:=N;k3.length:=N;k4.Length:=N;
  k1 := h*diffFn(StartT,InitVector,N);
  k2 := h*diffFn(StartT+h/2,InitVector+k1/2,N);
  k3 := h*diffFn(StartT+h/2,InitVector+k2/2,N);
  k4 := h*diffFn(StartT+h,InitVector+k3,N);
  RK4:= InitVector+1/6*(k1+2*k2+2*k3+k4);
end;

{ TM3Comp }

function TM3Comp.y_Strang(bolus,t :double):Vector;
// Compute compartment concentrations at time T y(t)=PDinv(P)y(0)
var
 v_inv : Matrix;
 D : Matrix;
 C: Vector;

 begin
  with fModelParams do begin
    C:=[bolus/V1,0,0,0];
    v_inv := Inverse(EigenVecs);
    D.Eye(4,4,false,true);
    D.Diag(exp(EigenVals*t),0);
    y_strang := mul(mul(Eigenvecs,mul(D,v_inv)),C);
  end;
end;

function TM3Comp.dy_strang(bolus,t : double):vector;
//compute derivatives of y(t) = A.y
begin
  with fModelParams do begin
    dy_strang := mul(DiffMatrix,y_strang(Bolus,t));
  end;
end;

function TM3Comp.y_eff(t  :float):float; // for secant root finder
const
  Bolus = 100;
begin
  y_eff := dy_strang(Bolus,t)[3];
end;

function TM3Comp.find_TPeak:Double;
// Find effect compartment peak as root of derivative using bisection method
// from LMath non-linear solvers
var
  x,y,root: Double;
begin
  x := 0;
  y:= 20;
  bisect(y_eff,x,y,1000,1e-6,root);
  find_Tpeak := x;
end;

function TM3Comp.calc_eff_init_bolus(target : double):Double;
var
  Tau : Double;
  v_inv,D : Matrix;
begin
  Tau := Find_TPeak;
  with fmodelParams do begin
    v_inv := Inverse(EigenVecs);
    D.Eye(4,4,false,true);
    D.Diag(exp(EigenVals*Tau),0);
    calc_eff_Init_bolus :=V1*target/(mul(Eigenvecs,mul(D,v_inv))[3,0]);
  end;
end;


function TM3Comp.Analytic_initBolus_solve(Bolus : Double; totalTime, Interval:Double): Matrix;
//finds Analytic solution for initial bolus delivered into central compartment
//sim time in minutes and interval in seconds
var
  N,SimTime: Integer;
  M,P,Y,Z,time: Matrix;
  t,C,coeff : Vector;
begin
  N := Round(TotalTime*60.0 / Interval);
  t.Size(N,mvDouble);
  t.Ramp(0,interval/60);
  time.Size(1,N,mvDouble);
  time.Copy(t);
  C:=[bolus/fmodelParams.V1,0,0,0];
  fmodelParams.EigenVecs.LUSolve(C,Coeff); //Solve for Initial conditions
  M.Eye(4,4,false,true);
  M.Diag(Coeff,0);
  P.Mul(fmodelParams.EigenVecs,M);
  Y:=exp(mul(fmodelparams.Eigenvals,t));
  Z.Mul(P,Y);
  M.ConcatVert([time,z]);  //Put Time values in first row
  Analytic_InitBolus_solve:= M;
end;

function TM3Comp.diffY(t:Double;y:Vector;N:Integer):Vector;
  var
    v : vector;
  begin
    with fmodelParams do begin
    v:=Mul(DiffMatrix ,y);
    v[0]:=(v[0]+inf_rate*concentration/V1);
    diffy.Copy(v);
    end;
  end;



procedure TM3Comp.f(X: Float; Y, Yp: TVector);
// Convert from TVector to Vector and Back
var
  VY :Vector;
  VYP :Vector;
begin
  VY.Size(4,mvDouble);
  Vyp.Size(4,mvDouble);
  VY.CopyFromArray(TDoubleArray(Y),1,0,4);
  Vyp := Diffy(X,VY,4);
  Vyp.CopyToArray(TDoubleArray(Yp),1,0,4);
end;

function TM3Comp.RK4_init_bolus_solve(Bolus,totalTime, Interval : Double):Matrix;

var
  NumSteps, step : Integer;
  currentT : Double;
  M,res : Vector;
  t,output : Matrix;
begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(1,NumSteps,mvDouble);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  M := [Bolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  output.SetCol(M,0);
  while step <=NumSteps-1 do begin
    res:=RK4(CurrentT,CurrentT+Interval/60,M,diffy,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:= CurrentT+interval/60;
    M.Copy(res);
    step:=step+1;
  end;
  RK4_init_bolus_solve.ConcatVert([t,output]);
end;

function TM3Comp.RK45_init_bolus_solve(Bolus, totalTime,
  Interval: Double): Matrix;
var
  NumSteps, step : Integer;
  currentT,nextT: Double;
  M,res : Vector;
  t,output : Matrix;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(1,NumSteps,mvDouble);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  M := [Bolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  res.Size(4,mvDouble);
  output.SetCol(M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  M.CopyToArray(TDoubleArray(Y),1,0,4);
  while step <=NumSteps-1 do begin
    nextT:= currentT+interval/60;
    RKF45(f,4,Y,Yp,currentT,nextT,1.0e-6,1.0e-6,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res.CopyFromArray(TDoubleArray(Y),1,0,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:=nextT;
    M.Copy(res);
    step:=step+1;
  end;
  RK45_init_bolus_solve.ConcatVert([t,output]);
end;

function TM3Comp.Bristol_10_8_6_Infusion(Weight, TotalTime, Interval : Double): Matrix;
var
  NumSteps,Step :Integer;
  M : Matrix;
  inf : Vector;
  currentT: Double;
  Bolus : Double;
begin
  Bolus := Weight *0.2;  //   mls
  NumSteps:= Round(TotalTime * 60 / interval);
  inf.Size(NumSteps,mvDouble);
  CurrentT:= 0;
  Step:=0;
  while step <=NumSteps-1 do begin
    if currentT < 10 then inf[step]:=1*weight
    else if ((currentT>=10) and (currentT<20)) then inf[step]:= 0.8*weight
    else inf[step] := 0.6*weight;
    step := step+1;
    currentT:= currentT+interval/60;
  end;
  Bristol_10_8_6_Infusion:=  Arbitrary_Infusion(inf,Bolus, TotalTime, Interval);
end;

function TM3Comp.Bristol_12_9_6_Infusion(Weight, TotalTime, Interval : Double): Matrix;
var
  NumSteps,Step :Integer;
  M : Matrix;
  inf : Vector;
  currentT: Double;
  Bolus : Double;
begin
  Bolus := Weight *0.2;
  NumSteps:= Round(TotalTime * 60 / interval);
  inf.Size(NumSteps,mvDouble);
  CurrentT:= 0;
  Step:=0;
  while step <=NumSteps-1 do begin
    if currentT < 10 then inf[step]:=1.2*weight
    else if ((currentT>=10) and (currentT<20)) then inf[step]:= 0.9*weight
    else inf[step] := 0.6*weight;
    step := step+1;
    currentT:= currentT+interval/60;
  end;
  Bristol_12_9_6_Infusion:=  Arbitrary_Infusion(inf,Bolus, TotalTime, Interval);
end;

function TM3Comp.kaps_init_bolus_solve(Bolus, totalTime,
  Interval: Double): Matrix;
const
  err = 1e-5;
  hmin=0;
var
  NumSteps, step : Integer;
  currentT,nextT: Double;
  M,res : Vector;
  t,output : Matrix;
  flags : TerrFlags;
  Y, Yp : TVector;

begin
  M := [Bolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  Output.Size(4,1,mvDouble);
  Output.Copy(M);   // Initialize Ouput to M
  Output.size(5,1,mvDouble); // Enlarge to accommodate time
  Output[4,0]:=0;   // initialise time
  flags:=odeInt(M,4,0,TotalTime,err,Interval/60,hmin,kaps_df,kaps_jac,output);
    case flags of
      TooManySteps: raise exception.Create('Too Many Steps') ;
      TooShortStep: raise exception.Create('Cannot achieve error'
       +FloatToStr(err)+' with stepsize '+floatToStr(hmin) );
      OK: ;
    end;
  kaps_init_bolus_solve.copy(Output);
end;

function TM3Comp.RK4_const_plasma_solve(Plasma_Target,totalTime, StopTime,
          Interval : Double):Matrix;

var
  NumSteps, step : Integer;
  currentT,NextT,InitBolus : Double;
  M,res : Vector;
  t,output : Matrix;


begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(2,NumSteps,mvDouble);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=0;
  res.Size(4,mvDouble);
  InitBolus := Plasma_target * fmodelParams.V1;
  M := [InitBolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  output.SetCol(M,0);
  while step <=NumSteps-1 do begin
    with fmodelParams do begin
       if CurrentT<Stoptime then
         Inf_Rate:= ((K*Plasma_Target*V1) -(k21*M[1]*V2+k31*M[2]*V3))/Concentration
       else
         Inf_Rate:=0;
      t[1,step]:=Inf_rate*60;
    end;
    res:=RK4(CurrentT,CurrentT+Interval/60,M,diffy,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:= CurrentT+interval/60;
    M.Copy(res);
    step:=step+1;
  end;
  RK4_const_plasma_solve.ConcatVert([t,output]);
end;

function TM3Comp.RK45_const_plasma_solve(Extra_Bolus,Plasma_Target, totalTime, StopTime,
  Interval: Double): Matrix;
Const
  Err = 10e-4;
var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus: Double;
  M,res : Vector;
  t,output : Matrix;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(2,NumSteps,mvDouble);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=0;
  Flags :=1;  // Initial Mode
  InitBolus := (Plasma_target * fmodelParams.V1)+Extra_Bolus;
  M := [InitBolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  res.Size(4,mvDouble);
  output.SetCol(M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  M.CopyToArray(TDoubleArray(Y),1,0,4);
  while step <=NumSteps-1 do begin
      with fmodelParams do begin
       if CurrentT<Stoptime then
         Inf_Rate:= ((K*Plasma_Target*V1) -(k21*M[1]*V2+k31*M[2]*V3))/Concentration
       else
         Inf_Rate:=0;
       t[1,step]:=Inf_rate*60;
    end;
    nextT:= currentT+interval/60;
    RKF45(f,4,Y,Yp,currentT,nextT,Err,Err,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res.CopyFromArray(TDoubleArray(Y),1,0,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:=nextT;
    M.Copy(res);
    step:=step+1;
  end;
  RK45_const_plasma_solve.ConcatVert([t,output]);
end;

function TM3Comp.RK45_const_effect_solve(Effect_Target, totalTime, StopTime,
  Interval: Double): Matrix;
Const
  Err = 10e-4;
var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus,Tau: Double;
  M,res : Vector;
  t,output : Matrix;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(2,NumSteps,mvDouble);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  Tau := find_TPeak;
  InitBolus := calc_eff_init_bolus(Effect_target) ;
  M := [InitBolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  res.Size(4,mvDouble);
  output.SetCol(M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  M.CopyToArray(TDoubleArray(Y),1,0,4);
  while step <=NumSteps-1 do begin
      with fmodelParams do begin
       if CurrentT<Stoptime then begin
         if currentT < Tau then Inf_rate := 0
           else Inf_Rate:= ((K*Effect_Target*V1) -(k21*M[1]*V2+k31*M[2]*V3))/Concentration
       end
       else
         Inf_Rate:=0;
       t[1,step]:=Inf_rate*60;
    end;
    nextT:= currentT+interval/60;
    RKF45(f,4,Y,Yp,currentT,nextT,Err,Err,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res.CopyFromArray(TDoubleArray(Y),1,0,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:=nextT;
    M.Copy(res);
    step:=step+1;
  end;
  RK45_const_effect_solve.ConcatVert([t,output]);
end;

function TM3Comp.Arbitrary_Infusion(Rate : Vector; Bolus, TotalTime, Interval : Double):Matrix;

var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus: Double;
  M,res : Vector;
  t,output : Matrix;
  flags : Integer;
  Y, Yp : TVector;
  ABolus : Double;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output.Size(4,NumSteps,mvDouble);
  t.Size(2,NumSteps,mvDouble);
  t[0,0]:=0;
  t[1,0]:=Rate[0];
  CurrentT:= 0;
  Step:=0;
  Flags :=1;  // Initial Mode
  ABolus := Bolus*fModelParams.Concentration;
  M := [ABolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  res.Size(4,mvDouble);
  output.SetCol(M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  M.CopyToArray(TDoubleArray(Y),1,0,4);
  while step <=NumSteps-1 do begin
    with fmodelParams do begin
      Inf_Rate:=Rate[step]/60;
      t[1,step]:= Rate[step];  //  Infusion rate im mls/hr
    end;
    nextT:= currentT+interval/60;
    RKF45(f,4,Y,Yp,currentT,nextT,1.0e-5,1.0e-6,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res.CopyFromArray(TDoubleArray(Y),1,0,4);
    output.SetCol(res,step);
    t[0,step]:= CurrentT;
    currentT:=nextT;
    M.Copy(res);
    step:=step+1;
  end;
  Arbitrary_Infusion.ConcatVert([t,output]);
end;

function TM3Comp.Pump_Arbitrary_Infusion(Rate : Vector; Bolus, TotalTime : Double):Matrix;

var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus: Double;
  YCurrent, YNext,v : Vector;
  t,output : Matrix;
  ABolus : Double;

begin
  NumSteps:= Round(TotalTime * 60/T_Pump);
  output.Size(4,NumSteps,mvDouble);
  t.Size(2,NumSteps,mvDouble);
  t[0,0]:=0;
  t[1,0]:=Rate[0];
  CurrentT:= 0;
  Step:=0;
  ABolus := Bolus*fModelParams.Concentration;
  YCurrent := [ABolus / fmodelParams.V1,0,0,0]; //   set T=0 vector to initial conditions
  YNext.Copy(YCurrent);
  output.SetCol(YCurrent,0);
  while step <=NumSteps-1 do begin
    with fmodelParams do begin
      Inf_Rate:=Rate[step]/60*FmodelParams.Concentration;
      t[1,step]:= Rate[step];  //  Infusion rate im mls/min
      v:=[Inf_Rate/V1,0,0,0];// 10 seconds worth
      YNext := mul(X,YCurrent);
      YNext := YNext+mul(W,v);
    end;
    nextT:= currentT+T_Pump/60;
    output.SetCol(YNext,step);
    t[0,step]:= CurrentT;
    currentT:=nextT;
    YCurrent.Copy(YNext);
    step:=step+1;
  end;
  Pump_Arbitrary_Infusion.ConcatVert([t,output]);
end;

function TM3Comp.Analytic_Single_Step(Yinit : Vector; Infusion_Rate, Tstart,Tend : Double):Vector;
//
// Uses Strang Analytic method for constant infusion rate
//
var
  YNext,v : Vector;
  Interval : Double;
begin
  with fmodelParams do begin
    Interval := Tend-Tstart;
    v:=[Infusion_Rate*Interval/V1,0,0,0];// 1 Intervals Worth
    YNext := mul(X,YInit);
    YNext := YNext+mul(W,v);
    Analytic_single_Step.Copy(Ynext);
  end;
end;


function TM3Comp.read_Ce50:double;
begin
  if fdrug <> Propofol then begin
    raise exception.Create('Ce50 Only defined for propofol');
    read_Ce50 := 0;
  end
  else
    read_Ce50 := fmodelParams.Ce50;
end;

function TM3Comp.BIS(Ce:Double):Double;
begin
    if fdrug <> Propofol then begin
    raise exception.Create('Ce50 Only defined for propofol');
    BIS := 0;
  end
  else
    BIS:= calc_BIS(Ce,pCe50);
end;



constructor TM3Comp.Create(Drug: TDrugs; Model: Tmodels; Actual_Weight:integer; Height:Double;
  Age: TAge; Sex: TSex);
var
  M : Matrix;
  V : Vector;
begin
   fDrug := Drug;
   fmodel := Model;
   fWeight := Actual_weight;
   fHeight := Height;
   fAge := Age;
   fSex := Sex;
   fBMI := BMI(fWeight,fHeight);
   fIBW := IBW(fHeight,fSex);
   fAdj_BW := ABM(fIBW,fWeight);

   case drug of
     Propofol: begin
       fmodelParams.ValidModels := [Marsh,Schneider,Paedfusor,Eleveld];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to propofol') ;
       case Model  of
         Marsh: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             k10 := 0.119;
             k12 := 0.112;
             k13:=0.0419;
             k21:= 0.055;
             k31:= 0.0033;
             ke0 :={0.26;} {0.456;}{1.21;}0.6;
             V1 := 0.228*Actual_Weight;
             V2 :=0.464*Actual_Weight;
             V3 :=2.89*Actual_Weight;
             Inf_Rate:=0; //mls/minute
             Concentration:=10; // mg/ml
           end; {with}
         end;  {marsh  }
         Schneider: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             V1 := 4.27;
             V2 :=18.9-0.391*(age-53);
             V3 :=238;
             Cl1 := 1.89+0.0456*(Actual_Weight-77)-0.0681*(lbw(Actual_Weight,Height,Sex,James)-59)
                  +0.0264*(height*100-177);
             Cl2 := 1.29-0.024*(age-53);
             Cl3 := 0.836;
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.42;
             Inf_Rate:=0;
             Concentration:=10; // mg/ml
           end; {with}
         end ; {Schneider}
         Paedfusor: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             case age of
               0:  raise exception.Create('Paedifusor model not validated for children under 1') ;
               1..12:begin V1:= 0.458*Actual_weight;k10:=0.1527*power(actual_weight,0.3);end;
               13:   begin V1:= 0.4*Actual_weight; k10 := 0.0678; end;
               14:   begin V1 := 0.342*Actual_Weight; k10 := 0.0792; end;
               15:   begin V1 := 0.284*Actual_Weight; k10 := 0.0945; end;
               else
                 begin V1 := 0.22857*Actual_Weight; k10 := 0.119; end;
             end;
             k12 := 0.114;
             k13:=0.0419;
             k21:= 0.055;
             k31:= 0.0033;
             ke0 :=0.26;
             V2 :=V1*k12/k21;
             V3 :=V1*k13/k31;
             Inf_Rate:=0;
             Concentration:=10; // mg/ml
           end; {with}
         end ; {Paedfusor}
         Eleveld: begin  // Eleveld functions in uBodystats
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             V1 :=calc_v1_art(Actual_weight);
             V2 :=calc_v2(age,Actual_weight);
             V3 :=calc_v3(age,sex,Actual_weight,Height,False);
             Cl1 := calc_Cl(age,sex,age*52+40,Actual_weight,False);
             Cl2 := calc_q2_art(age,Actual_weight);
             Cl3 := calc_q3(age,sex,Actual_weight,Height,false);
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 := calc_ke0_art(Actual_weight);
             Inf_Rate:=0;
             Concentration:=10; // mg/ml
           end; {with}
         end ; {Eleveld}
       end; {case model}
     end; {propofol models}

     Fentanyl:begin
       fmodelParams.ValidModels:=[Schafer];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Fentanyl') ;
       case model of
         Schafer: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mcg/ml';
             Compartment_Units:= 'ng/ml';
             k10 := 0.0827;
             k12 := 0.471;
             k13:=0.225;
             k21:= 0.102;
             k31:= 0.00600;
             ke0 :=0.147;  // Calculated from Anaesthesiology 2019
             V1 :=6.09;
             V2 :=k12*V1/k21;
             V3 :=k13*V1/k31;
             Cl1 := 0;
             Cl2 := 0;
             Cl3 := 0;
             Inf_Rate:=0;
             Concentration:=50; // neat mcg/ml
           end; {with}
         end;
       end;{Models}
     end;{fentanyl models}

     Alfentanil:begin
       fmodelParams.ValidModels:=[Scott];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Alfentanil') ;
       case model of
       scott: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mcg/ml';
             Compartment_Units:= 'ng/ml';
             k10 := 0.091;
             k12 := 0.656;
             k13:=0.113;
             k21:= 0.214;
             k31:= 0.017;
             ke0 :=0.77;  // Calculated from Anaesthesiology 2019
             V1 :=(2.1853 / 70.0) * Actual_Weight;
             V2 :=k12*V1/k21;
             V3 :=k13*V1/k31;
             Cl1 := 0;
             Cl2 := 0;
             Cl3 := 0;
             Inf_Rate:=0;
             Concentration:=20; // mcg/ml
           end; {with}
         end;
       end;{Models}
     end;{alfentanil models}


     Remifentanil: begin
       fmodelParams.ValidModels:=[Minto];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Remifentanil') ;
       case model of
         Minto: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mcg/ml';
             Compartment_Units:= 'ng/ml';
             V1 := 5.1-0.0201*(age-40)+0.072*((lbw(Actual_Weight,Height,Sex,James)-55));
             V2 :=9.82-0.0811*(age-40)+0.108*((lbw(Actual_Weight,Height,Sex,James)-55));
             V3 :=5.42;
             Cl1 := 2.6-0.0162*(age-40)+0.0191*(lbw(Actual_Weight,Height,Sex,James)-55);
             Cl2 := 2.05-0.0301*(age-40);
             Cl3 := 0.076-0.00113*(age-40);
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.595-0.007*(age-40);
             Inf_Rate:=0;
             Concentration:= 40; // mcg/ml
           end; {with}
         end; {case model}
       end; {Remifentanil models}
     end; {case drug}

     Thiopentone: begin
     fmodelParams.ValidModels:=[Maitre];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Thiopentone') ;
       case model of
         Maitre: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             V1 := 0.079 * Actual_Weight;
             if age <= 35 then V2:=(0.48*V1/0.0787) else
                   V2 :=(0.48-0.00288*(age - 35))*V1/0.0787;
             V3 :=V1*0.107/0.00389;
             Cl1 := 0.00307*Actual_Weight;
             Cl2 :=0.0787*V2 ;
             Cl3 := 0.00389*V3;
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.693 / 1.17;
             Inf_Rate:=0;
             Concentration:=25; // mg/ml
           end; {with}
         end; {case model}
       end; {Thiopentonel models}
     end; {case drug}

     Midazolam: begin
       fmodelParams.ValidModels:=[Geller];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Midazolam') ;
       case model of
         Geller: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mg/ml';
             Compartment_Units:= 'mcg/ml';
             V1 :=  33;
             V2 :=3.32+32.1*bsa(Actual_Weight,Height);
             V3 :=365;
             Cl1 := 0.0889+0.151*bsa(Actual_Weight,Height);
             Cl2 := 0.622;
             Cl3 := 0.264;
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.693 / 4.0;
             Inf_Rate:=0;
             Concentration:=1; // mg/ml
           end; {with}
         end; {case model}
       end; {Midazolam models}
     end; {case drug}

     Dexmedetomidine: begin
       fmodelParams.ValidModels:=[Dyck,Hannivoort];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Dexmedetomidine') ;
       case model of
         Dyck: begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='ng/ml';
             Compartment_Units:= 'ng/ml';
             V1 :=  7.99;
             V2 :=13.8;
             V3 :=187;
             Cl1 := -0.927 + 0.791 * Height;
             Cl2 := 2.26;
             Cl3 := 1.99;
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.36;
             Inf_Rate:=0;
             Concentration:=4; // mcg/ml
           end; {with}
         end;
         Hannivoort : begin
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='ng/ml';
             Compartment_Units:= 'ng/ml';
             V1 :=  1.83*Actual_Weight/70;
             V2 :=27.8*Actual_Weight/70;
             V3 :=54.4*Actual_Weight/70;
             Cl1 := 0.695*power(actual_weight/70,0.75);
             Cl2 := 3.25*power(actual_weight/70,0.75);;
             Cl3 := 0.689*power(actual_weight/70,0.75);;
             k10 := cl1 / V1;
             k12 := cl2 / V1;
             k13:=cl3 / V1;
             k21:= cl2 / V2;
             k31:= cl3 / V3;
             ke0 :=0.36;
             Inf_Rate:=0;
             Concentration:=4; // mcg/ml
           end; {with}
         end; {case model}

       end; {Dexmedetomidine model}
     end; {case drug}
   end;
// Create Matrix for evaluation of first differentials. Can be used by
// either analytic or numerical methods to solve system.
   with fmodelParams do begin
       K := k10+k12+k13;
       DiffMatrix.Create(4,4,mvDouble);
       DiffMatrix := [[ -K,   k21, k31,   0],
                      [  k12,-k21, 0,     0],
                      [  k13,   0,-k31,   0],
                      [  ke0,   0,   0,-ke0]];

       M.Copy(DiffMatrix);
       Ce50 := calc_Ce50(age);
// Compute eigenvalues and eigenvectors of matrix for analytic solution
       DiffMatrix.Eig(EigenVals,nil,EigenVecs);
       fmodelParams.Eigenvals := Real(Eigenvals);
       fmodelParams.Eigenvecs := Real(Eigenvecs);
//  Now create W and X for special matrices for pump type calculations
       A_inv := Matrix.Create(4,4,mvDouble);
       P_inv := Matrix.Create(4,4,mvDouble);
       P_Inv.Copy(EigenVecs);
       P_Inv.Inv;  // inverse eigenvecs matrix
       A_Inv.Copy(DiffMatrix); // inverse A matrix
       A_Inv.Inv;
       I.Eye(4,4,False,True);
       X := Matrix.Create(4,4,mvDouble);
       X.Diag(exp(Eigenvals*T_Pump/60),0); // Create Gamma matrix
       W := mul(eigenvecs,mul(X,P_Inv));
       X.Copy(W);    // X Is Matrix exponent of A
       W:= mul((X-I),A_inv);
   end;
   M.Copy(fmodelParams.DiffMatrix);
end;


end.
