program newVMtest;

{$mode objfpc}{$H+}


uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, newVM, newVMComplex, newVMSingle,
  newVMComplexSingle, cblas, hirestimer
  { you can add units after this };

type

  { TMyApplication }

  TMyApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    x : TVMObjS;
    y,z,r,eival,eivec : TVMObjC;
    { operator overload test fields - one pair (+ a scratch result) per
      TVMobj* type, kept separate from x/y/z/r/eival/eivec above so the
      existing demo pipeline isn't disturbed }
    dblA, dblB, dblC : TVMObj;        //newVM.pas          (real double)
    sngA, sngB, sngC : TVMObjS;       //newVMSingle.pas    (real single)
    cplA, cplB, cplC : TVMObjZ;       //newVMComplex.pas   (complex double)
    cplsA, cplsB, cplsC : TVMObjC;    //newVMComplexSingle.pas (complex single)
    Time : THighResTimer;
    s : TStringList;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

procedure ShowMatrix(const Title: String; M: TStringList);
var
  Item : String;
begin
  writeln(Title);
  for Item in M do writeln(Item);
  M.Free;
end;

{ TMyApplication }

procedure TMyApplication.DoRun;
const
  N = 5;
  OpN = 3;   //matrix size for the operator overload tests below
var
  ErrorMsg,Item : String;
  t : double;

begin
  // quick check parameters
  x := TVMObjS.create(N,N);
  x.fillRandom;
  z :=  RealToComplexS(x);
  r := copyObjC(z);
  y := TVMObjC.create(N,N);
  y.id;
  writeln('x = ');
  s := x.writematrix;
  for item in s do writeln(item);
  s.free;
  writeln('z = ');
  s := z.writematrix;
  for item in s do writeln(item);
  s.free;
  writeln('r = ');
  s := r.writematrix;
  for item in s do writeln(item);
  s.free;
  Time := THighresTimer.Create;
  t := Time.MilliSeconds;
  LinearSolveC(z,y);
  t := time.MilliSeconds-t;
  writeln( 'time solve = ',floatTostrf(t,ffgeneral,4,4),' ms');
  z := matmultC(r,y);
  s := z.writematrix;
  for item in s do writeln(item);
  s.free;
  t := time.MilliSeconds;
  EigDecomposeS(x,eival,eivec);
  t := time.MilliSeconds-t;
  writeln( 'time eigendecompose = ',floatTostrf(t,ffgeneral,4,4),' ms');
  writeln('Eigenvals =');
  s := eival.writematrix;
  for item in s do writeln(item);
  s.free;
  writeln('Eigenvecs =');
  s := eivec.writematrix;
  for item in s do writeln(item);
  s.free;

  // ----------------------------------------------------------------------
  // Operator overload tests - exercise +, -, unary -, *, / for each of the
  // four TVMobj* types, plus the mixed real/complex forms on the two
  // complex types.
  // ----------------------------------------------------------------------

  writeln;
  writeln('=== TVMobj (real double) operator overload tests ===');
  dblA := TVMobj.Create(OpN,OpN);
  dblA.fillRandom;
  dblB := TVMobj.Create(OpN,OpN);
  dblB.fillRandom;
  ShowMatrix('dblA =', dblA.writeMatrix);
  ShowMatrix('dblB =', dblB.writeMatrix);
  dblC := dblA + dblB;  ShowMatrix('dblA + dblB =', dblC.writeMatrix);
  dblC := dblA - dblB;  ShowMatrix('dblA - dblB =', dblC.writeMatrix);
  dblC := -dblA;        ShowMatrix('-dblA =', dblC.writeMatrix);
  dblC := dblA * dblB;  ShowMatrix('dblA * dblB (matrix multiply) =', dblC.writeMatrix);
  dblC := dblA * 2.0;   ShowMatrix('dblA * 2.0 =', dblC.writeMatrix);
  dblC := 2.0 * dblA;   ShowMatrix('2.0 * dblA =', dblC.writeMatrix);
  dblC := dblA / 2.0;   ShowMatrix('dblA / 2.0 =', dblC.writeMatrix);

  writeln;
  writeln('=== TVMobjS (real single) operator overload tests ===');
  sngA := TVMobjS.Create(OpN,OpN);
  sngA.fillRandom;
  sngB := TVMobjS.Create(OpN,OpN);
  sngB.fillRandom;
  ShowMatrix('sngA =', sngA.writeMatrix);
  ShowMatrix('sngB =', sngB.writeMatrix);
  sngC := sngA + sngB;  ShowMatrix('sngA + sngB =', sngC.writeMatrix);
  sngC := sngA - sngB;  ShowMatrix('sngA - sngB =', sngC.writeMatrix);
  sngC := -sngA;        ShowMatrix('-sngA =', sngC.writeMatrix);
  sngC := sngA * sngB;  ShowMatrix('sngA * sngB (matrix multiply) =', sngC.writeMatrix);
  sngC := sngA * 2.0;   ShowMatrix('sngA * 2.0 =', sngC.writeMatrix);
  sngC := 2.0 * sngA;   ShowMatrix('2.0 * sngA =', sngC.writeMatrix);
  sngC := sngA / 2.0;   ShowMatrix('sngA / 2.0 =', sngC.writeMatrix);

  writeln;
  writeln('=== TVMobjZ (complex double) operator overload tests ===');
  cplA := TVMobjZ.Create(OpN,OpN);
  cplA.fillRandom;
  cplB := TVMobjZ.Create(OpN,OpN);
  cplB.fillRandom;
  ShowMatrix('cplA =', cplA.writeMatrix);
  ShowMatrix('cplB =', cplB.writeMatrix);
  cplC := cplA + cplB;         ShowMatrix('cplA + cplB =', cplC.writeMatrix);
  cplC := cplA - cplB;         ShowMatrix('cplA - cplB =', cplC.writeMatrix);
  cplC := -cplA;               ShowMatrix('-cplA =', cplC.writeMatrix);
  cplC := cplA * cplB;         ShowMatrix('cplA * cplB (matrix multiply) =', cplC.writeMatrix);
  cplC := cplA * Cplx(0,1);    ShowMatrix('cplA * i (complex scalar) =', cplC.writeMatrix);
  cplC := cplA * 2.0;          ShowMatrix('cplA * 2.0 (real scalar) =', cplC.writeMatrix);
  cplC := cplA / Cplx(2,0);    ShowMatrix('cplA / (2+0i) (complex scalar) =', cplC.writeMatrix);
  cplC := cplA / 2.0;          ShowMatrix('cplA / 2.0 (real scalar) =', cplC.writeMatrix);
  //mixed real/complex - real TVMobj promoted to TVMobjZ automatically
  cplC := dblA + cplA;         ShowMatrix('dblA + cplA (mixed real+complex) =', cplC.writeMatrix);
  cplC := cplA * dblB;         ShowMatrix('cplA * dblB (mixed matrix multiply) =', cplC.writeMatrix);

  writeln;
  writeln('=== TVMobjC (complex single) operator overload tests ===');
  cplsA := TVMobjC.Create(OpN,OpN);
  cplsA.fillRandom;
  cplsB := TVMobjC.Create(OpN,OpN);
  cplsB.fillRandom;
  ShowMatrix('cplsA =', cplsA.writeMatrix);
  ShowMatrix('cplsB =', cplsB.writeMatrix);
  cplsC := cplsA + cplsB;         ShowMatrix('cplsA + cplsB =', cplsC.writeMatrix);
  cplsC := cplsA - cplsB;         ShowMatrix('cplsA - cplsB =', cplsC.writeMatrix);
  cplsC := -cplsA;                ShowMatrix('-cplsA =', cplsC.writeMatrix);
  cplsC := cplsA * cplsB;         ShowMatrix('cplsA * cplsB (matrix multiply) =', cplsC.writeMatrix);
  cplsC := cplsA * Cplx8(0,1);    ShowMatrix('cplsA * i (complex scalar) =', cplsC.writeMatrix);
  cplsC := cplsA * 2.0;           ShowMatrix('cplsA * 2.0 (real scalar) =', cplsC.writeMatrix);
  cplsC := cplsA / Cplx8(2,0);    ShowMatrix('cplsA / (2+0i) (complex scalar) =', cplsC.writeMatrix);
  cplsC := cplsA / 2.0;           ShowMatrix('cplsA / 2.0 (real scalar) =', cplsC.writeMatrix);
  //mixed real/complex - real TVMobjS promoted to TVMobjC automatically
  cplsC := sngA + cplsA;          ShowMatrix('sngA + cplsA (mixed real+complex) =', cplsC.writeMatrix);
  cplsC := cplsA * sngB;          ShowMatrix('cplsA * sngB (mixed matrix multiply) =', cplsC.writeMatrix);

  // ----------------------------------------------------------------------
  // Elementwise function tests - exercise Sin/Cos/Tan/Sinh/Sqr/Sqrt/Exp/Ln
  // for each of the four TVMobj* types. dblA/sngA/cplA/cplsA (filled with
  // random data above) are reused as the input matrix for each type.
  // ----------------------------------------------------------------------

  writeln;
  writeln('=== TVMobj (real double) elementwise function tests ===');
  ShowMatrix('sin(dblA) =', Sin(dblA).writeMatrix);
  ShowMatrix('cos(dblA) =', Cos(dblA).writeMatrix);
  ShowMatrix('tan(dblA) =', Tan(dblA).writeMatrix);
  ShowMatrix('sinh(dblA) =', Sinh(dblA).writeMatrix);
  ShowMatrix('sqr(dblA) =', Sqr(dblA).writeMatrix);
  ShowMatrix('sqrt(sqr(dblA)) [should equal abs(dblA)] =', Sqrt(Sqr(dblA)).writeMatrix);
  ShowMatrix('exp(dblA) =', Exp(dblA).writeMatrix);
  ShowMatrix('ln(exp(dblA)) [should recover dblA] =', Ln(Exp(dblA)).writeMatrix);

  writeln;
  writeln('=== TVMobjS (real single) elementwise function tests ===');
  ShowMatrix('sin(sngA) =', Sin(sngA).writeMatrix);
  ShowMatrix('cos(sngA) =', Cos(sngA).writeMatrix);
  ShowMatrix('tan(sngA) =', Tan(sngA).writeMatrix);
  ShowMatrix('sinh(sngA) =', Sinh(sngA).writeMatrix);
  ShowMatrix('sqr(sngA) =', Sqr(sngA).writeMatrix);
  ShowMatrix('sqrt(sqr(sngA)) [should equal abs(sngA)] =', Sqrt(Sqr(sngA)).writeMatrix);
  ShowMatrix('exp(sngA) =', Exp(sngA).writeMatrix);
  ShowMatrix('ln(exp(sngA)) [should recover sngA] =', Ln(Exp(sngA)).writeMatrix);

  writeln;
  writeln('=== TVMobjZ (complex double) elementwise function tests ===');
  ShowMatrix('sin(cplA) =', Sin(cplA).writeMatrix);
  ShowMatrix('cos(cplA) =', Cos(cplA).writeMatrix);
  ShowMatrix('tan(cplA) =', Tan(cplA).writeMatrix);
  ShowMatrix('sinh(cplA) =', Sinh(cplA).writeMatrix);
  ShowMatrix('sqr(cplA) =', Sqr(cplA).writeMatrix);
  ShowMatrix('sqrt(sqr(cplA)) (principal branch) =', Sqrt(Sqr(cplA)).writeMatrix);
  ShowMatrix('exp(cplA) =', Exp(cplA).writeMatrix);
  ShowMatrix('ln(exp(cplA)) [should approx. recover cplA] =', Ln(Exp(cplA)).writeMatrix);

  writeln;
  writeln('=== TVMobjC (complex single) elementwise function tests ===');
  ShowMatrix('sin(cplsA) =', Sin(cplsA).writeMatrix);
  ShowMatrix('cos(cplsA) =', Cos(cplsA).writeMatrix);
  ShowMatrix('tan(cplsA) =', Tan(cplsA).writeMatrix);
  ShowMatrix('sinh(cplsA) =', Sinh(cplsA).writeMatrix);
  ShowMatrix('sqr(cplsA) =', Sqr(cplsA).writeMatrix);
  ShowMatrix('sqrt(sqr(cplsA)) (principal branch) =', Sqrt(Sqr(cplsA)).writeMatrix);
  ShowMatrix('exp(cplsA) =', Exp(cplsA).writeMatrix);
  ShowMatrix('ln(exp(cplsA)) [should approx. recover cplsA] =', Ln(Exp(cplsA)).writeMatrix);

  Time.destroy;

  ErrorMsg:=CheckOptions('h', 'help');
  if ErrorMsg<>'' then begin
    ShowException(Exception.Create(ErrorMsg));
    Terminate;
    Exit;
  end;

  // parse parameters
  if HasOption('h', 'help') then begin
    WriteHelp;
    Terminate;
    Exit;
  end;



  // stop program loop
  Terminate;
end;

constructor TMyApplication.Create(TheOwner: TComponent);
begin
  inherited Create(TheOwner);
  StopOnException:=True;
  InitializeCblas;
end;

destructor TMyApplication.Destroy;
begin
  inherited Destroy;
//  s.free;
end;

procedure TMyApplication.WriteHelp;
begin
  { add your help code here }
  writeln('Usage: ', ExeName, ' -h');
end;

var
  Application: TMyApplication;
begin
  Application:=TMyApplication.Create(nil);
  Application.Title:='My Application';
  Application.Run;
  Application.Free;
end.

