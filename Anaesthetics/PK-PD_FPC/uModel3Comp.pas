unit uModel3Comp;

{*******************************************************************************

    Implements various anaesthetic drug 3-compartment models, allowing
    calculation of plasma/effect-site drug concentrations for propofol,
    remifentanil, and five other agents under various infusion regimens.

    Uses newVM.pas's TVMobj for the linear algebra (eigendecomposition,
    matrix exponentials via eigenvalues, LU-based linear solves), LMath's
    RKF45 (urkf.pas) for adaptive-step integration, LMath's Bisect
    (ubisect.pas) for the effect-site-peak root find, and this project's own
    uKapsRentrop.pas (a from-scratch port of the original's Kaps-Rentrop
    stiff-ODE solver) as a third integration option.

    Uses the Pharmacokinetic data from Stanpump DRUGS.C module
    https://github.com/StevenLShafer/stanpumpR/blob/master/Original%20Stanpump/DRUGS.C

    Ported from Anaesthetics/PK-PD/uModel3Comp.pas (Delphi/MtxVec) onto
    newVM for the Anaesthetics/PK-PD_FPC demo. Original: Dr Howard Dent,
    started 24/07/2022.

    Porting note - LMath's callback types are plain (non-method) procedural
    types (LMath/UGenMath/types.inc: TDiffEqs, TFunc have no "of object"),
    unlike the original's Dew-DMath-based uModel3Comp.pas, which relied on
    an externally-installed uTypes.pas declaring method-pointer-compatible
    versions of the same names. Two different bridges are used below:
      - RKF45 (urkf.pas) has no context-pointer overload at all, so `f`'s
        instance state reaches it via a unit-level "currently active
        instance" pointer (gActiveM3Comp) set immediately before each call -
        safe here because every RK45_* solve method runs its stepping loop
        to synchronous completion before returning (no concurrent/reentrant
        RKF45 calls ever occur in this single-threaded batch-solve app).
      - Bisect (ubisect.pas) DOES have a context-pointer overload
        (TParamFunc, taking an extra untyped Params: Pointer alongside X) -
        exactly the mechanism intended for this, so find_TPeak uses that
        instead of any global state.

    Porting note - a real bug fixed, not carried forward: the original's
    RK4/RK45/Analytic bolus and constant-target solve methods (and
    Arbitrary_Infusion/Pump_Arbitrary_Infusion) all pre-seed column 0 with
    the t=0 state, then loop "step := 1 to NumSteps-1" (or, for the two
    Infusion methods, re-write column 0 from inside a "step := 0 to
    NumSteps-1" loop) - either way, only NumSteps-1 genuine integration
    advances happen despite NumSteps being sized from the caller's own
    TotalTime/Interval, so the returned data silently falls one interval
    short of the requested TotalTime; the time row is also recorded
    *before* each step advances (CurrentT, not the post-advance time),
    mislabelling every column after the first. kaps_init_bolus_solve
    (Kaps-Rentrop) doesn't share either defect - OdeInt's own boundary
    clamp integrates to the exact requested end time. Caught by
    uPKPDTests.pas's TestKapsRentropVsRK45Agree disagreeing by a full
    interval's worth of decay. Fixed uniformly here: every solve method
    below allocates NumSteps+1 columns (t=0 plus NumSteps genuine advances,
    reaching TotalTime exactly) and records each column's time label
    *after* advancing.

*******************************************************************************}

{$mode delphi}{$H+}

interface
uses
  urkf, ubisect, utypes, Math, DateUtils, Sysutils, newVM, newVMComplex,
  uBodyStats, uKapsRentrop;

const
  T_Pump = 10; // Pump cycle time = 10 seconds

Type
  TCompartments = (V1=0,V2=1,V3=2);
  TDrugs = (Propofol=0,Fentanyl=1,Alfentanil=2,
    Remifentanil=3,Thiopentone=4,Midazolam=5,Dexmedetomidine=6,Ketamine=7);
  TModels =(Marsh=0,Schafer=1,Scott=2,Schneider=3,Minto=4,
    Maitre=5,Geller=6,Paedfusor=7,Eleveld=8,Dyck=9,Hannivoort=10,Domino=11);
  TModelParams = Record
    DrugName : String;
    ModelName : String;
    ValidModels : set of TModels;
    Plasma_Units,Compartment_Units :String;
    Inf_Rate,Concentration : Double;
    V1,V2,V3,Eff,K,k10,k12,k13,k21,k31,ke0,TTPE,Cl1,Cl2,Cl3,Ce50,BIS : Double;
    C_LOC,C_Rec : Double; // Effect compartment concentration for LOC and recovery
    DiffMatrix : TVMobj;      // 4x4 system matrix (was Matrix)
    EigenVecs : TVMobj;       // 4x4, real part of DiffMatrix's eigenvectors
    Eigenvals : TVMobj;       // 4x1, real part of DiffMatrix's eigenvalues
    I,W,X,A_inv,P_inv : TVMobj;
  End;


  TM3Comp = class(TObject)
    fdrug : Tdrugs;
    fmodel :Tmodels;
    fModelParams : TModelParams; // used to create differential function
  private
    function diffY(t: Double; y: TVMobj; N: Integer): TVMobj;
    procedure f(X : Float; Y, Yp : TVector);
    procedure kaps_df( x : double; var y,dydx : TVMobj );
    procedure kaps_jac( var x :double;var y,dfdx : TVMobj; var dfdy :TVMobj;
                           n : integer );
   function read_Ce50:double;
  Public
    FHeight, fWeight, fIBW,fBMI, fAdj_BW : Double;
    fAge : Tage;
    fSex : TSex;
    Constructor Create(Drug: TDrugs; Model:Tmodels;Actual_Weight:Integer;Height:double;Age:TAge;Sex:TSex);
    function Analytic_initBolus_solve(Bolus : Double; totalTime,Interval:Double): TVMobj;
    function RK4_init_bolus_solve(Bolus, totalTime, Interval: Double): TVMobj;
    function RK45_init_bolus_solve(Bolus, totalTime, Interval: Double): TVMobj;
    function RK4_const_plasma_solve(Plasma_Target, totalTime,StopTime,
      Interval: Double): TVMobj;
    function RK45_const_effect_solve(Effect_Target, totalTime, StopTime,
      Interval: Double): TVMobj;
    function RK45_const_plasma_solve(Extra_Bolus,Plasma_Target, totalTime, StopTime,
      Interval: Double): TVMobj;
    function Arbitrary_Infusion(Rate : TVMobj;Bolus, TotalTime, Interval : Double): TVMobj;
    function Pump_Arbitrary_Infusion(Rate : TVMobj;Bolus, TotalTime: Double): TVMobj;
    function Analytic_Single_Step(Yinit : TVMobj; Infusion_Rate, Tstart,Tend : Double):TVMobj;
    function kaps_init_bolus_solve(Bolus, totalTime, Interval: Double): TVMobj;
    function y_Strang(bolus,t :double):TVMobj;
    function dy_strang(bolus,t : double):TVMobj;
    function y_eff(t  :float):float; // for bisection root finder
    function find_TPeak:Double;
    function calc_eff_init_bolus(target : double):Double;
    function Bristol_10_8_6_Infusion(weight: Double;TotalTime, Interval : Double): TVMobj;
    function Bristol_12_9_6_Infusion(weight : double; TotalTime, Interval : Double): TVMobj;
    function BIS(Ce :Double):Double;
  published
    property pCe50 : Double read read_Ce50;
  end;

Type
  TDiffFn=Function(t:Double;y:TVMobj;N:Integer):TVMobj of object;  // for RK4

const
  DrugNameStrings: Array [TDrugs] of string =('Propofol','Fentanyl','Alfentanil','Remifentanil',
    'Thiopentone','Midazolam','Dexmedetomidine','Ketamine');
  ModelNameStrings : Array [TModels] of String =('Marsh','Schafer','Scott','Schneider','Minto',
    'Maitre','Geller','Paedfusor','Eleveld','Dyck','Hannivoort','Domino');

implementation

// --- small local helpers -----------------------------------------------
// newVM has no GetRow/SetCol (confirmed absent - see plan) and LMath's
// TVector (urkf.pas/ubisect.pas) is used 1-based-by-convention (index 0
// left unused by DimVector) - these bridge both gaps, local to this unit.

function VMGetRow(const A: TVMobj; r: Integer): TVMobj;
begin
  result := SubMatrix(A, r, 0, 1, A.Cols);
end;

procedure VMSetCol(var A: TVMobj; const v: TVMobj; c: Integer);
var
  i : Integer;
begin
  for i := 0 to A.Rows-1 do
    if v.Cols = 1 then A[i,c] := v[i,0] else A[i,c] := v[0,i];
end;

function LVectorToTVMobj(const V: TVector; N: Integer): TVMobj;
var
  i : Integer;
begin
  result := TVMobj.Create(N,1);
  for i := 0 to N-1 do result[i,0] := V[i+1];
end;

procedure TVMobjToLVector(const A: TVMobj; var V: TVector; N: Integer);
var
  i : Integer;
begin
  for i := 0 to N-1 do V[i+1] := A[i,0];
end;

// --- LMath callback bridges (see unit header comment) -------------------

var
  gActiveM3Comp : TM3Comp;

procedure GlobalDiffEqs(X: Float; Y, Yp: TVector);
begin
  gActiveM3Comp.f(X, Y, Yp);
end;

function GlobalYEffParam(t: Float; Params: Pointer): Float;
begin
  result := TM3Comp(Params).y_eff(t);
end;

function RK4(StartT,EndT:double; InitVector :TVMobj;DiffFn:TDiffFn; N:Integer):TVMobj;
//Perform single step of Runge-Kutta fourth order algorithm
// advancing solution from startT to endT from initial vector
// using external derivative function. N = number of equations
var
 h : double;
 k1,k2,k3,k4 :TVMobj;
begin
  h := EndT-StartT;
  k1 := h*diffFn(StartT,InitVector,N);
  k2 := h*diffFn(StartT+h/2,InitVector+k1/2,N);
  k3 := h*diffFn(StartT+h/2,InitVector+k2/2,N);
  k4 := h*diffFn(StartT+h,InitVector+k3,N);
  result := InitVector+(1/6)*(k1+2*k2+2*k3+k4);
end;

{ TM3Comp }

function TM3Comp.y_Strang(bolus,t :double):TVMobj;
// Compute compartment concentrations at time T y(t)=P.exp(D.t).Pinv.y(0)
var
 v_inv, D, C : TVMobj;
 begin
  with fModelParams do begin
    C := TVMobj.Create(4,1,[bolus/V1,0,0,0]);
    v_inv := Invert(EigenVecs);
    D := Diag(Exp(Eigenvals*t));
    result := MatMult(MatMult(Eigenvecs,MatMult(D,v_inv)),C);
  end;
end;

function TM3Comp.dy_strang(bolus,t : double):TVMobj;
//compute derivatives of y(t) = A.y
begin
  with fModelParams do begin
    result := MatMult(DiffMatrix,y_strang(Bolus,t));
  end;
end;

function TM3Comp.y_eff(t  :float):float; // for bisection root finder
const
  Bolus = 100;
begin
  y_eff := dy_strang(Bolus,t)[3,0];
end;

function TM3Comp.find_TPeak:Double;
// Find effect compartment peak as root of derivative using bisection method
var
  x,y,root: Double;
begin
  x := 0;
  y:= 20;
  Bisect(GlobalYEffParam, Self, x, y, 1000, 1e-6, root);
  find_Tpeak := x;
end;

function TM3Comp.calc_eff_init_bolus(target : double):Double;
var
  Tau : Double;
  v_inv,D : TVMobj;
begin
  Tau := Find_TPeak;
  with fmodelParams do begin
    v_inv := Invert(EigenVecs);
    D := Diag(Exp(Eigenvals*Tau));
    calc_eff_Init_bolus := V1*target/(MatMult(Eigenvecs,MatMult(D,v_inv))[3,0]);
  end;
end;


function TM3Comp.Analytic_initBolus_solve(Bolus : Double; totalTime, Interval:Double): TVMobj;
//finds Analytic solution for initial bolus delivered into central compartment
//sim time in minutes and interval in seconds
var
  N: Integer;
  M,P,Y,Z,time,EigVecsScratch : TVMobj;
  C,Coeff : TVMobj;
begin
  // N-1 intervals of Interval seconds span TotalTime minutes exactly (N points,
  // t=0..TotalTime inclusive) - see the "off-by-one" note in this unit's
  // header comment; every solve method in this class uses this same convention.
  N := Round(TotalTime*60.0 / Interval) + 1;
  time := TVMobj.Create(1,N);
  time.linspace(0,interval/60);
  C := TVMobj.Create(4,1,[bolus/fmodelParams.V1,0,0,0]);
  EigVecsScratch := CopyObj(fmodelParams.EigenVecs);
  Coeff := CopyObj(C);
  LinearSolve(EigVecsScratch,Coeff); //Solve for Initial conditions
  M := Diag(Coeff);
  P := MatMult(fmodelParams.EigenVecs,M);
  Y := Exp(MatMult(fmodelparams.Eigenvals,time));
  Z := MatMult(P,Y);
  result := MergeUD(time,Z);  //Put Time values in first row
end;

function TM3Comp.diffY(t:Double;y:TVMobj;N:Integer):TVMobj;
  var
    v : TVMobj;
  begin
    with fmodelParams do begin
    v := MatMult(DiffMatrix,y);
    v[0,0] := v[0,0]+inf_rate*concentration/V1;
    result := v;
    end;
  end;

procedure TM3Comp.f(X: Float; Y, Yp: TVector);
// Convert from LMath's TVector to TVMobj and back
var
  VY, VYp : TVMobj;
begin
  VY := LVectorToTVMobj(Y, 4);
  VYp := Diffy(X,VY,4);
  TVMobjToLVector(VYp, Yp, 4);
end;

function TM3Comp.RK4_init_bolus_solve(Bolus,totalTime, Interval : Double):TVMobj;
var
  NumSteps, step : Integer;
  currentT : Double;
  M,res,t,output : TVMobj;
begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(1,NumSteps+1);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  M := TVMobj.Create(4,1,[Bolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  while step <=NumSteps do begin
    res:=RK4(CurrentT,CurrentT+Interval/60,M,diffy,4);
    VMSetCol(output,res,step);
    currentT:= CurrentT+interval/60;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.RK45_init_bolus_solve(Bolus, totalTime,
  Interval: Double): TVMobj;
var
  NumSteps, step : Integer;
  currentT,nextT: Double;
  M,res,t,output : TVMobj;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(1,NumSteps+1);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  M := TVMobj.Create(4,1,[Bolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  TVMobjToLVector(M, Y, 4);
  gActiveM3Comp := Self;
  while step <=NumSteps do begin
    nextT:= currentT+interval/60;
    RKF45(GlobalDiffEqs,4,Y,Yp,currentT,nextT,1.0e-6,1.0e-6,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res := LVectorToTVMobj(Y, 4);
    VMSetCol(output,res,step);
    currentT:=nextT;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.Bristol_10_8_6_Infusion(Weight, TotalTime, Interval : Double): TVMobj;
var
  NumSteps,Step :Integer;
  inf : TVMobj;
  currentT: Double;
  Bolus : Double;
begin
  Bolus := Weight *0.2;  //   mls
  NumSteps:= Round(TotalTime * 60 / interval);
  inf := TVMobj.Create(1,NumSteps);
  CurrentT:= 0;
  Step:=0;
  while step <=NumSteps-1 do begin
    if currentT < 10 then inf[0,step]:=1*weight
    else if ((currentT>=10) and (currentT<20)) then inf[0,step]:= 0.8*weight
    else inf[0,step] := 0.6*weight;
    step := step+1;
    currentT:= currentT+interval/60;
  end;
  result :=  Arbitrary_Infusion(inf,Bolus, TotalTime, Interval);
end;

function TM3Comp.Bristol_12_9_6_Infusion(Weight, TotalTime, Interval : Double): TVMobj;
var
  NumSteps,Step :Integer;
  inf : TVMobj;
  currentT: Double;
  Bolus : Double;
begin
  Bolus := Weight *0.2;
  NumSteps:= Round(TotalTime * 60 / interval);
  inf := TVMobj.Create(1,NumSteps);
  CurrentT:= 0;
  Step:=0;
  while step <=NumSteps-1 do begin
    if currentT < 10 then inf[0,step]:=1.2*weight
    else if ((currentT>=10) and (currentT<20)) then inf[0,step]:= 0.9*weight
    else inf[0,step] := 0.6*weight;
    step := step+1;
    currentT:= currentT+interval/60;
  end;
  result :=  Arbitrary_Infusion(inf,Bolus, TotalTime, Interval);
end;

function TM3Comp.kaps_init_bolus_solve(Bolus, totalTime,
  Interval: Double): TVMobj;
const
  err = 1e-5;
  hmin=0;
var
  M, Output : TVMobj;
  flags : TerrFlags;

begin
  M := TVMobj.Create(4,1,[Bolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  Output := MergeUD(M, TVMobj.Create(1,1,[0]));  // append t=0 as the 5th row
  flags:=odeInt(M,4,0,TotalTime,err,Interval/60,hmin,kaps_df,kaps_jac,output);
    case flags of
      TooManySteps: raise exception.Create('Too Many Steps') ;
      TooShortStep: raise exception.Create('Cannot achieve error'
       +FloatToStr(err)+' with stepsize '+floatToStr(hmin) );
      OK: ;
    end;
  result := Output;
end;

function TM3Comp.RK4_const_plasma_solve(Plasma_Target,totalTime, StopTime,
          Interval : Double):TVMobj;
var
  NumSteps, step : Integer;
  currentT,InitBolus : Double;
  M,res,t,output : TVMobj;
begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(2,NumSteps+1);
  t[0,0]:=0;
  t[1,0]:=0;
  CurrentT:= 0;
  Step:=1;
  InitBolus := Plasma_target * fmodelParams.V1;
  M := TVMobj.Create(4,1,[InitBolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  while step <=NumSteps do begin
    with fmodelParams do begin
       if CurrentT<Stoptime then
         Inf_Rate:= ((K*Plasma_Target*V1) -(k21*M[1,0]*V2+k31*M[2,0]*V3))/Concentration
       else
         Inf_Rate:=0;
      t[1,step]:=Inf_rate*60;
    end;
    res:=RK4(CurrentT,CurrentT+Interval/60,M,diffy,4);
    VMSetCol(output,res,step);
    currentT:= CurrentT+interval/60;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.RK45_const_plasma_solve(Extra_Bolus,Plasma_Target, totalTime, StopTime,
  Interval: Double): TVMobj;
Const
  Err = 10e-4;
var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus: Double;
  M,res,t,output : TVMobj;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(2,NumSteps+1);
  t[0,0]:=0;
  t[1,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  InitBolus := (Plasma_target * fmodelParams.V1)+Extra_Bolus;
  M := TVMobj.Create(4,1,[InitBolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  TVMobjToLVector(M, Y, 4);
  gActiveM3Comp := Self;
  while step <=NumSteps do begin
      with fmodelParams do begin
       if CurrentT<Stoptime then
         Inf_Rate:= ((K*Plasma_Target*V1) -(k21*M[1,0]*V2+k31*M[2,0]*V3))/Concentration
       else
         Inf_Rate:=0;
       t[1,step]:=Inf_rate*60;
    end;
    nextT:= currentT+interval/60;
    RKF45(GlobalDiffEqs,4,Y,Yp,currentT,nextT,Err,Err,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res := LVectorToTVMobj(Y, 4);
    VMSetCol(output,res,step);
    currentT:=nextT;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.RK45_const_effect_solve(Effect_Target, totalTime, StopTime,
  Interval: Double): TVMobj;
Const
  Err = 10e-4;
var
  NumSteps, step : Integer;
  currentT,nextT,Initbolus,Tau: Double;
  M,res,t,output : TVMobj;
  flags : Integer;
  Y, Yp : TVector;

begin
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(2,NumSteps+1);
  t[0,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  Tau := find_TPeak;
  InitBolus := calc_eff_init_bolus(Effect_target) ;
  M := TVMobj.Create(4,1,[InitBolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  TVMobjToLVector(M, Y, 4);
  gActiveM3Comp := Self;
  while step <=NumSteps do begin
      with fmodelParams do begin
       if CurrentT<Stoptime then begin
         if currentT < Tau then Inf_rate := 0
           else Inf_Rate:= ((K*Effect_Target*V1) -(k21*M[1,0]*V2+k31*M[2,0]*V3))/Concentration
       end
       else
         Inf_Rate:=0;
       t[1,step]:=Inf_rate*60;
    end;
    nextT:= currentT+interval/60;
    RKF45(GlobalDiffEqs,4,Y,Yp,currentT,nextT,Err,Err,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res := LVectorToTVMobj(Y, 4);
    VMSetCol(output,res,step);
    currentT:=nextT;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.Arbitrary_Infusion(Rate : TVMobj; Bolus, TotalTime, Interval : Double):TVMobj;
var
  NumSteps, step : Integer;
  currentT,nextT: Double;
  M,res,t,output : TVMobj;
  flags : Integer;
  Y, Yp : TVector;
  ABolus : Double;

begin
  // Rate has one entry per interval (indices 0..NumSteps-1); output/t have
  // one extra column for the t=0 initial condition (see this unit's header
  // comment), so interval index i (Rate[0,i]) drives the advance into
  // column i+1.
  NumSteps:= Round(TotalTime * 60 / interval);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(2,NumSteps+1);
  t[0,0]:=0;
  t[1,0]:=0;
  CurrentT:= 0;
  Step:=1;
  Flags :=1;  // Initial Mode
  ABolus := Bolus*fModelParams.Concentration;
  M := TVMobj.Create(4,1,[ABolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,M,0);
  DimVector(Y,4);
  DimVector(Yp,4);
  TVMobjToLVector(M, Y, 4);
  gActiveM3Comp := Self;
  while step <=NumSteps do begin
    with fmodelParams do begin
      Inf_Rate:=Rate[0,step-1]/60;
      t[1,step]:= Rate[0,step-1];  //  Infusion rate in mls/hr, active over this interval
    end;
    nextT:= currentT+interval/60;
    RKF45(GlobalDiffEqs,4,Y,Yp,currentT,nextT,1.0e-5,1.0e-6,flags);
    if flags in [2,7] then flags:=2 else
      raise Exception.Create('RKF45 Flags ='+IntToStr(Flags));
    res := LVectorToTVMobj(Y, 4);
    VMSetCol(output,res,step);
    currentT:=nextT;
    t[0,step]:= CurrentT;
    M := CopyObj(res);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.Pump_Arbitrary_Infusion(Rate : TVMobj; Bolus, TotalTime : Double):TVMobj;
var
  NumSteps, step : Integer;
  currentT,nextT: Double;
  YCurrent, YNext,v,t,output : TVMobj;
  ABolus : Double;

begin
  NumSteps:= Round(TotalTime * 60/T_Pump);
  output := TVMobj.Create(4,NumSteps+1);
  t := TVMobj.Create(2,NumSteps+1);
  t[0,0]:=0;
  t[1,0]:=0;
  CurrentT:= 0;
  Step:=1;
  ABolus := Bolus*fModelParams.Concentration;
  YCurrent := TVMobj.Create(4,1,[ABolus / fmodelParams.V1,0,0,0]); //   set T=0 vector to initial conditions
  VMSetCol(output,YCurrent,0);
  while step <=NumSteps do begin
    with fmodelParams do begin
      Inf_Rate:=Rate[0,step-1]/60*FmodelParams.Concentration;
      t[1,step]:= Rate[0,step-1];  //  Infusion rate in mls/min, active over this pump cycle
      v:=TVMobj.Create(4,1,[Inf_Rate/V1,0,0,0]);// 10 seconds worth
      YNext := MatMult(X,YCurrent);
      YNext := YNext+MatMult(W,v);
    end;
    nextT:= currentT+T_Pump/60;
    VMSetCol(output,YNext,step);
    currentT:=nextT;
    t[0,step]:= CurrentT;
    YCurrent := CopyObj(YNext);
    step:=step+1;
  end;
  result := MergeUD(t,output);
end;

function TM3Comp.Analytic_Single_Step(Yinit : TVMobj; Infusion_Rate, Tstart,Tend : Double):TVMobj;
//
// Uses Strang Analytic method for constant infusion rate
//
var
  YNext,v : TVMobj;
  Interval : Double;
begin
  with fmodelParams do begin
    Interval := Tend-Tstart;
    v:=TVMobj.Create(4,1,[Infusion_Rate*Interval/V1,0,0,0]);// 1 Interval's Worth
    YNext := MatMult(X,YInit);
    YNext := YNext+MatMult(W,v);
    result := YNext;
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

procedure TM3Comp.kaps_df( x : double; var y,dydx : TVMobj );
begin
  dydx:=MatMult(fmodelparams.DiffMatrix,y);
end;

procedure TM3Comp.kaps_jac( var x :double;var y,dfdx : TVMobj; var dfdy :TVMobj;
                                      n : integer );
begin
  dfdx:=TVMobj.Create(4,1,[0,0,0,0]);
  dfdy := CopyObj(fmodelParams.DiffMatrix);
end;


constructor TM3Comp.Create(Drug: TDrugs; Model: Tmodels; Actual_Weight:integer; Height:Double;
  Age: TAge; Sex: TSex);
var
  EigValsZ, EigVecsZ : TVMobjZ;
  Ones4R : TVMobj;
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
             ke0 := 0.6;
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
         Eleveld: begin  // Eleveld functions in uBodyStats
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
             Cl2 := 3.25*power(actual_weight/70,0.75);
             Cl3 := 0.689*power(actual_weight/70,0.75);
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

     Ketamine: begin
       fmodelParams.ValidModels:=[Domino];
       if not (Model in FmodelParams.ValidModels) then
         raise exception.Create(modelNameStrings[Model]+'model Not applicable to Ketamine') ;
       case model of
         Domino: begin
           // Domino, Domino, Kollef & Kilpatrick, Clin Pharmacol Ther
           // 36:645-653, 1991 - the "human" kinetic set from Stanpump's own
           // DRUGS.C (ketamine(), kinetic_set=1; see Anaesthetics/PK-PD_FPC/
           // DRUGS.C), not the horse set also offered there. DRUGS.C has no
           // real effect-site data for ketamine (effect_data=0) and sets its
           // k41 (=ke0 in this codebase's naming - confirmed against
           // DRUGS.C's own custom-kinetics loader, which reads k41 as the
           // 17th "ke0" field) to 10 with the comment "no idea" - kept as-is
           // rather than inventing a value Stanpump itself doesn't claim.
           with fmodelParams do begin
             DrugName:=DrugNameStrings[Drug];
             ModelName:=ModelNameStrings[Model];
             Plasma_units:='mcg/ml';
             Compartment_Units:= 'mcg/ml';
             V1 := 0.063*Actual_Weight;
             k10 := 0.438;
             k12 := 0.592;
             k13 := 0.590;
             k21 := 0.247;
             k31 := 0.0146;
             V2 := V1*k12/k21;
             V3 := V1*k13/k31;
             ke0 := 10; // DRUGS.C: "no idea" - no real effect-site data for ketamine
             Inf_Rate:=0;
             Concentration:=100000; // mcg/ml (100mg/ml ketamine stock)
           end; {with}
         end; {case model}
       end; {Ketamine models}
     end; {case drug}
   end;
// Create Matrix for evaluation of first differentials. Can be used by
// either analytic or numerical methods to solve system.
   with fmodelParams do begin
       K := k10+k12+k13;
       DiffMatrix := TVMobj.Create(4,4,[-K,   k21, k31,   0,
                                          k12,-k21, 0,     0,
                                          k13,   0,-k31,   0,
                                          ke0,   0,   0,-ke0]);

       Ce50 := calc_Ce50(age);
// Compute eigenvalues and eigenvectors of matrix for analytic solution.
// EigDecompose (newVMComplex.pas) always returns complex results (a real
// nonsymmetric matrix can have complex eigenvalues in general); this
// system's eigenvalues are physically real, so only the real part is kept -
// same as the original's own Real(...) calls right after MtxVec's .Eig.
       EigDecompose(DiffMatrix, EigValsZ, EigVecsZ);
       Eigenvals := GetRealPart(EigValsZ);
       EigenVecs := GetRealPart(EigVecsZ);
//  Now create W and X, the matrix-exponential-based transition matrices
//  used by Pump_Arbitrary_Infusion/Analytic_Single_Step for one pump-cycle
//  (T_Pump seconds) steps: X = exp(A*T_Pump/60), W = (X-I)*A^-1.
       P_Inv := Invert(EigenVecs);
       A_Inv := Invert(DiffMatrix);
       Ones4R := TVMobj.Create(4,1,[1,1,1,1]);
       I := Diag(Ones4R);                       // 4x4 identity
       X := Diag(Exp(Eigenvals*(T_Pump/60)));   // Gamma: exp(D*T_Pump/60) in eigenbasis
       W := MatMult(EigenVecs,MatMult(X,P_Inv)); // X is now the true matrix exponential
       X := CopyObj(W);
       W := MatMult((X-I),A_inv);
   end;
end;


end.
