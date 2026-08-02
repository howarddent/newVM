program newVMtest;

{$mode objfpc}{$H+}


uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, CustApp, newVM, newVMSingle, newVMComplexSingle, cblas,
  hirestimer
  { you can add units after this };

type

  { TMyApplication }

  TMyApplication = class(TCustomApplication)
  protected
    procedure DoRun; override;
  public
    x : TVMObjS;
    y,z,r,eival,eivec : TVMObjC;
    Time : THighResTimer;
    s : TStringList;
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure WriteHelp; virtual;
  end;

{ TMyApplication }

procedure TMyApplication.DoRun;
const
  N = 5;
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
  EigDecompose(x,eival,eivec);
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

