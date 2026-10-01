
unit uJetCalc;

interface

uses
  MtxExpr;

const
  One_Bar = 101325; //Pa
  O2_Density_RT = 1.331;
  Air_Density_RT = 1.204;
  Air_Viscocity_RT = 1.331* 10e-5;
  O2_kin_Viscocity_RT = 15.43e-6;
  O2_dyn_Viscocity_RT = 20.27e-6;
  O2_Rel_density =1.105;
  rough_f  = 0.07; //Derived by fiddling with moody roughness calculator
  S_Temp = 288;
  R_Temp = 293;
  S_GOxygen = 1.1044;

type
  TJetCath = (Lindholm,Cook,Biro,Rav_Adult,IV_14,IV_16,IV_18);
  TCatheter = class
    Public
      Name : String;
      Length,Diameter,Radius,Area : Double;
      Reynolds_342 : Integer;
      MeasuredFlow,EntrainedFlow : Vector;
      MeasuredStall15,MeasuredStallflow,MeasuredStall22 : Vector;
      Constructor Create(Cath_Type: TJetCAth);
      function calc_Velocity(Flow: Double):Double;
      function calc_Flow(DP: Double):Double;
      function calc_f(Hyd_Diam,Reynolds,surf_Roughness: Double):double;
      function calc_stall(flow : double;D :Double):Double;
  end;

function calc_crit_PRatio(k :double; out  Y :Double):Double;


implementation

uses Math,Math387,PolyNoms;

const
  JetString : Array[TJetCath] of string = ('Lindholm','Cook','Biro','Rav_Adult',
                   '14# Venflon','16# Venflon','18 # Venflon');

{ TCatheter }

function TCatheter.calc_Flow(DP: Double): Double;
//
// Calculate jet flow using darcy-weisbach equation
//from crane 3-20
//

var
  k, kactual,Y,surd : Double;
  DPAbs, DeltaP,PRatio,CritP,Actual_DP : Double;
  Sonic : Boolean;

function calc_k(roughness:double):double;
const
  k_inlet = 0.5;
  k_outlet = 1;

begin
  k := calc_f(Diameter,Reynolds_342,Roughness)*length/Diameter;
  calc_k := k_inlet+k+k_outlet;
end;

begin
  DPAbs :=  DP+1;
  PRatio := DP/DPabs;
  kactual := Calc_K(1e-6);
  CritP := calc_crit_Pratio(kactual,Y);   // Determine if flow supersonic
  Sonic := PRatio >= CritP;
  if Sonic then Actual_DP := CritP*DPAbs else Actual_DP := DP;
// Now Apply Darcy weisbach
  surd := sqrt(Actual_DP*DPAbs/(R_Temp*kactual*S_GOxygen));
  //Y:= 0.6;
  calc_Flow := 1000*surd*Y*0.3217*sqr(Diameter*1000);
end;

function TCatheter.calc_Velocity(Flow: Double): Double;

begin
  calc_Velocity := flow/(60000*Area);
end;

function calc_crit_PRatio(k: double; out Y: Double): Double;
//
// Interpolates table from Crane A-22 for gamma 1.4
//
var
  tabK,tabDP,tabY,CoeffY,CoeffDP : vector;

begin
  tabK := [1.2,1.5,2.0,3,4,6,8,10,15,20,40,100];
  tabDP := [0.552,0.576,0.612,0.662,0.697,0.737,0.762,0.784,0.818,0.839,0.883,0.926];
  tabY := [0.588,0.606,0.622,0.639,0.649,0.671,0.685,0.695,0.702,0.710,0.710,0.710];
  PolyFit(tabK,tabDP,3,CoeffDP);
  PolyFit(tabK,tabY,3,CoeffY);
  Y := PolyEval(k,CoeffY);
  Calc_Crit_PRatio :=PolyEval(k,CoeffDP);
end;

function TCatheter.calc_f(Hyd_Diam, Reynolds, surf_Roughness: Double): double;
//
// moody formula from omnicalc
//
begin
  calc_f := 0.0055*(1+power(((2e4*surf_roughness/Hyd_Diam)+(1e6/Reynolds)),1/3));
end;

function TCatheter.calc_stall(flow: double;D : Double): Double;
var
  CircuitArea : Double;
begin
  CircuitArea := Pi * sqr(D/2);
  calc_stall := area*sqr(calc_velocity(flow))* O2_Density_RT/(100*CircuitArea);
end;

constructor TCatheter.Create(Cath_Type: TJetCAth);
begin
  case Cath_Type of
    Lindholm: begin
               Length := 9.5e-2;  // lengthened to compensate 45 degree bend
               Diameter := 2.0e-3;
               MeasuredFlow := [18.3,30.8,40.9,50.7,59.6,68.4,79.0];
               EntrainedFlow := [40,66,88,113,133,150,166];
               MeasuredStallFlow := [16,27,38,46,63,72,82];
               MeasuredStall22 := [2,8,11,15,21,26,30];
               MeasuredStall15 := [0,0,0,0,0,0,0];
              end;
    Cook: begin
               Length := 7.5e-2;
               Diameter := 1.8e-3;
               MeasuredFlow := [18.3,30.8,40.9,50.7,59.6,68.4,79.0];
               EntrainedFlow := [40,66,88,113,133,150,166];
               MeasuredStallFlow := [16,27,38,46,63,72,82];
               MeasuredStall22 := [2,8,11,15,21,26,30];
               MeasuredStall15 := [4,7,24,35,47,60,75];
          end;
    Biro: begin
            length := 4e-1;
            Diameter := 2e-3;
            MeasuredFlow := [15.75,26.4,36.2,45.0,53.3,61.0,69.7];
            EntrainedFlow := [25,46,63,80,95,109,125];
            MeasuredStallFlow := [15,26,36,46,58,67,78];
            MeasuredStall22 := [1,3,4,7,10,12,15];
            MeasuredStall15 := [0,0,0,0,0,0,0];
          end;
    Rav_Adult: ;
    IV_14: begin
              Length := 45e-3;
              Diameter := 1.5e-3;
              MeasuredFlow :=[14.4,23.75,31.6,38.4,44.7,51.2,57.6];
              EntrainedFlow := [37.7,64,80.7,97,111,122,134];
              MeasuredStallFlow := [14,23,31,40,47,55,64];
              MeasuredStall22 := [2,4,7,10,12,15,19];
              MeasuredStall15 := [0,0,0,0,0,0,0];
           end;
    IV_16:begin
               Length := 45e-3;
               Diameter := 1.35e-3;
               MeasuredFlow := [13.36,20.62,27.8,33.9,39.6,45.7,50.7];
               EntrainedFlow := [33,57,76,88,102,112,122];
               MeasuredStallFlow := [11,20,28,34,41,47,52];
               MeasuredStall22:= [2,4,7,10,13,16,19];
               MeasuredStall15 := [0,0,0,0,0,0,0];
           end;
    IV_18:begin
               Length := 45e-3;
               Diameter := 0.9e-3;
               MeasuredFlow := [7.0,10.8,14.3,17.24,20.28,23.3,26.38];
               EntrainedFlow := [28.7,43.5,54,65,66,71,79];
               MeasuredStallFlow := [5.6,8.5,11.8,14.6,16,20,22];
               MeasuredStall22 := [1,2,4,5,6,7,9];
               MeasuredStall15 := [0,0,0,0,0,0,0];
           end;
  end;
  Name := JetString[Cath_Type];
  Radius := Diameter /2;
  Area := Pi*sqr(Radius);
  Reynolds_342 := Round(342*Diameter*O2_Density_RT/O2_dyn_viscocity_RT);
end;

end.
