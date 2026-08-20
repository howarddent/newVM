unit uBodystats;

interface

const
  // Eleveld PK parameters
  Prop_Theta1 = 6.28; //V1 referenece
  Prop_Theta2 = 25.5;  // V2 reference
  Prop_Theta3 = 273;  // V3 reference
  Prop_Theta4 = 1.79;
  Prop_Theta5 = 1.75;
  Prop_Theta6 = 1.11;
  Prop_Theta7 = 0.191;
  Prop_Theta8 = 42.3;
  Prop_Theta9 = 9.06;
  Prop_Theta10 = -0.0156;
  Prop_Theta11 = -0.00286;
  Prop_Theta12 = 33.6;
  Prop_Theta13 = -0.0138;
  Prop_Theta14 = 68.3;
  Prop_Theta15 = 2.1;
  Prop_Theta16 = 1.3;
  Prop_Theta17 = 1.42;
  Prop_Theta18 = 0.68;

// Reference human for eleveld model

  age_ref = 35;
  weight_ref = 70;
  height_ref = 1.70;

  //Eleveld P-D parameters
  Prop_Phi1 = 3.08;
  Prop_Phi2 = 0.146;
  Prop_Phi3 = 93;
  Prop_Phi4 = 1.47;
  Prop_Phi5 = 8.03;
  Prop_Phi6 = 0.0517;
  Prop_Phi7 =-0.00635;
  Prop_Phi8 = 1.24;
  Prop_Phi9 = 1.89;

// Eleveld Remifentanil params
  remi_V1_ref = 5.81; // litres
  remi_V2_ref = 8.12;
  remi_V3_ref = 5.03;
  remi_Cl_ref = 2.58; // l/min
  remi_Q2_ref = 1.72;
  remi_Q3_ref = 0.124;
  remi_Theta1 = 0.203;
  remi_Theta2 = -0.00746;
  remi_Theta3 = -0.00470;
  remi_Theta4 = -0.0416;
  remi_Theta5 = 0.374;
  remi_Theta6 = -0.0359;


type
  TSex =(Male, Female);
  TWeightModel = (Act_BW, I_BW, L_BM, Adj_BW, ffM{fat free mass});
  TAge = 0..110;
  TLBWMethod=(James,Hume);

  function ft_in_To_Meter(Feet,inches:integer):double;
  function meter_to_inches(meters :double):Integer;
  function st_lb_to_kg(Stone, Pound:integer):double;
  function kg_to_lb(kg :double):integer;
  function BMI(weight, height :double):double;
  Function BSA(weight, height : double):double; // DuBois Formula
  Function AgeFromDOB(DOB : TDate):integer;
  Function LBW(weight,Height : double; ThisSex :Tsex;LBWMethod :TLBWMethod):Integer;
  Function IBW(Height : double; ThisSex : Tsex):Integer;
  function ABM( IdealWeight,totalWeight :double):Integer;
  function fatPercent(ActualWeight,IdealWeight:double):Integer;
  function freeFatMass(Age:Tage;Sex : Tsex; aWeight, aHeight : Double):Double;
// functions required by Eleveld model
  function f_ageing(x : double ;age :Tage): double;
  function f_sigmoid(x,E50,lambda:double):double;
  function f_central(x:double):double;
  function f_CLmaturation(PMA :double):double;
  function f_Q3Maturation(Age :Tage): Double;
  function f_opiates(x:double;age : Tage; opiates:boolean):Double;
// now calculate Eleveld p_k parameters
  function calc_V1_art(weight : double):double;
  function calc_V1_venous( weight : double):double;
  function calc_V2(age : Tage;weight : double):double;
  function calc_v3( Age:Tage;Sex : Tsex; aWeight, aHeight : Double;
                   Opiates : Boolean):Double;
  function calc_CL(Age :Tage;sex :Tsex;PMA,weight : double;opiates :Boolean ):double;
  function calc_q2_art(age : Tage; weight : double):double;
  function calc_q2_ven( age : Tage; weight : double):double;
  function calc_q3(Age:Tage;Sex : Tsex; aWeight, aHeight : Double;
                   Opiates : Boolean):double;
  function calc_Ce50(age :Tage):Double;
  function calc_ke0_art(weight : double):double;
  function calc_gamma(Ce,Ce50 : Double):Double;
  function calc_bis(Ce,Ce50 : Double):Double;
  function Calc_bis_delay(age :Tage):double;


implementation

uses
  Math, DateUtils, SysUtils;

function ft_in_To_Meter(Feet,inches:integer):double;
const
  in_to_meter = 0.0254;
var
  Height_Inches : Integer;
begin
  Height_Inches := Feet * 12 + inches;
  ft_in_to_Meter := in_to_meter * Height_Inches;
end;

function meter_to_inches(meters :double):Integer;
Const
  m_to_inch = 39.37;
begin
  meter_to_Inches := round(meters * m_to_inch);
end;

function st_lb_to_kg(Stone, Pound:integer):double;
const
  lb_kg = 0.4536;
var
  total_lb : integer;
begin
  total_lb := 14 * Stone + Pound;
  st_lb_to_kg := lb_kg * total_lb;
end;

function kg_to_lb(kg :double):integer;
const
  kg_lb = 2.205;
begin
  kg_to_lb := round(kg_lb*kg);
end;

function BMI(weight, height :double):double;
begin
  BMI := weight/sqr(height);
end;

Function BSA(weight, height : double):double; // DuBois Formula
begin
  BSA := 0.20247*power(weight,0.425)*power(height,0.725);
end;

Function AgeFromDOB(DOB : TDate):integer;
var
  total_days : word;
begin
  total_days := daysBetween(Now,DOB);
  AgeFromDOB := Trunc(total_Days/365.25);
end;

Function LBW(weight,Height : double; ThisSex :Tsex;LBWMethod :TLBWMethod):Integer;

// Lean Body mass from the Hume 1971 formula - works better for obese
// than James formula

begin
  case LBWMethod of

    James: case thisSex of
             Male : LBW := round(1.1*weight-128*sqr(weight/(100*Height)));
             Female: LBW := round(1.07*weight-148*sqr(weight/(100*Height)));
           end;

   Hume: case thisSex of
           Male: LBW:= round(0.4066*weight+26.68*height-19.19);
           Female: LBW:=round( 0.2518*weight+47.2*height-48.32);
         end;
  end;
end;

Function IBW(Height : double; ThisSex : Tsex):Integer;

// Ideal Bodyweight from the devine formula
// Modified for use in Eleveld model

var
  total_inches : Integer;
begin
{  total_inches := meter_to_inches(Height);
  case ThisSex of
    Male:  IBW:= round(50 + 2.3*(total_inches-60)) ;
    Female:IBW := round(45.5 + 2.3*(total_inches-60)) ;
  end;}
  IBW := round(22*sqr(Height));
end;

function ABM( IdealWeight,totalWeight :double):Integer;

//Based on standard Ideal BW + 40% of excess

begin
  if TotalWeight <= IdealWeight then
    ABM := round(IdealWeight)
  Else
    ABM := round(IdealWeight+0.4*(TotalWeight-IdealWeight));
end;

function fatPercent(ActualWeight,IdealWeight:double):Integer;
begin
  fatPercent := round(100*((ActualWeight-IdealWeight)/ActualWeight));
end;

function freeFatMass(Age:Tage;Sex : Tsex; aWeight, aHeight : Double):Double;

//As calculated by Al-Sallami et al see BJA 120(5) 942-959

var
  aBMI : Double;
  LHTerm,RHTerm : Double;
begin
  aBMI := BMI(aWeight,aHeight);
  case sex of
    Male: begin
        LHTerm := 0.88 +(1-0.88)/(1+Power((Age/13.4),-12.7));
        RHTerm := (9270*aWeight)/(6680+216*aBMI);
    end;

    Female : begin
        LHTerm := 1.11 +(1-1.11)/(1+Power((Age/7.1),-1.1));
        RHTerm := (9270*aWeight)/(8780+244*aBMI);
    end;
  end; {case}
  freeFatMass := LHTerm*RHTerm;
end;

// Functions required by eleveld model

function f_ageing(x : double; age :Tage):Double;
begin
  f_ageing := exp( x*(age - age_ref));
end;

function f_sigmoid(x,E50,lambda:double):double;
begin
  f_sigmoid := power(x,lambda)/(power(x,lambda)+power(E50,lambda));
end;

function f_central(x:double):double;
begin
  f_central := f_sigmoid(x,Prop_Theta12,1);
end;

function f_CLmaturation(PMA:double):double;
begin
  f_CLmaturation := f_sigmoid(PMA,Prop_Theta8,Prop_Theta9);
end;

function f_Q3Maturation(Age :Tage): Double;
begin
  f_Q3Maturation := f_sigmoid((52*age+40),Prop_Theta14,1);
end;

function f_opiates(x:double;Age :TAge;opiates:boolean):Double;
begin
  if opiates  then
     f_opiates := exp(x*Age)
  else
   f_opiates := 1;
end;

function calc_V1_art(weight : double):double;
begin
  calc_V1_art := Prop_Theta1*f_central(weight)/f_central(weight_ref);
end;

function calc_V1_venous( weight : double):double;
begin
  calc_V1_venous := calc_V1_art(weight)*(1+Prop_Theta17*(1+f_central(weight)));
end;

function calc_V2(age : Tage; weight : double):double;
begin
  calc_V2 := Prop_Theta2*(weight/weight_ref)*f_ageing(Prop_Theta10,age);
end;

function calc_v3( Age:Tage;Sex : Tsex; aWeight, aHeight : Double;Opiates : Boolean):Double;
begin
  calc_v3 := Prop_Theta3*(freeFatMass(Age,sex,aWeight,aHeight)
                /freefatmass(age_ref,male,weight_ref,height_ref))
                *f_opiates(Prop_Theta13,age,opiates);
end;

function calc_CL(age :Tage;sex :Tsex;PMA,weight : double;opiates :Boolean ):double;
var
  term1,term2,term3 : Double;
begin
  case sex  of
    Male:  term1 := Prop_Theta4;
    Female: term1 := Prop_Theta15;
  end;
  term2 := (power(weight/weight_ref,0.75));
  term3 := f_Clmaturation(PMA)/f_CLMaturation(52*age_ref);
  calc_CL := term1*term2*term3*f_opiates(Prop_Theta11,age,opiates);
end;

function calc_q2_art(age : Tage; weight : double):double;
var
  term1,term2: double;
begin
  term1 := Prop_Theta5 * power(calc_V2(age,weight)/calc_v2(age_ref,weight_ref),0.75);
  term2 :=1 + Prop_Theta16*(1-f_q3Maturation(age));
  calc_q2_art := term1*term2;
end;

function calc_q2_ven( age : Tage; weight : double):double;
begin
  calc_q2_ven := Prop_Theta18 * calc_q2_art(age,weight);
end;

function calc_q3(Age:Tage;Sex : Tsex; aWeight, aHeight : Double;
                   Opiates : Boolean):double;
var
  term1, term2 : double;
begin
  term1 := power((calc_V3(age,sex,aWeight,aHeight,Opiates)
                /calc_V3(age_ref,Male,weight_ref,height_ref,Opiates)),0.75);
  term2 := f_q3Maturation(age)/f_q3Maturation(age_ref);
  calc_q3 := Prop_Theta6 * term1 * term2;
end;

function calc_Ce50(age :Tage):Double;
begin
  calc_Ce50 := Prop_Phi1 * f_ageing(Prop_Phi7,age);
end;

function calc_ke0_art(weight : double):double;
begin
  calc_ke0_art := power(weight/weight_ref,-0.25)*Prop_Phi2;
end;

function calc_gamma(Ce,Ce50 : Double):Double;
begin
  if Ce < Ce50 then calc_gamma := Prop_Phi4
    else calc_gamma := Prop_Phi9;
end;

function calc_bis(Ce,Ce50 : Double):Double;
var
  term1 : double;
begin
  term1 := f_sigmoid(Ce,Ce50,calc_Gamma(Ce,Ce50));
  calc_bis := Prop_Phi3*(1-term1);
end;

function Calc_bis_delay(age :Tage):double;
begin
  calc_bis_delay := 15+exp(Prop_Phi6*age);
end;

end.
