unit CXS.FEMLAP.Penalty;

{$mode delphi}{$H+}

interface

uses Math, newVM, newVMsparse,
  CXS.FEMLAP.Exceptions;

type TPenalty = class(TObject)

  private
    FFactor : Double;
    procedure SetFactor(const Value: Double);

    function CalcPenalty(diag : TVMobj) : Double;

  public

    constructor Create;

    procedure Impose(IsFixed : TBooleanArray; Values : TDoubleArray; var A : TVMSparseMtx; b : TVMobj);
    property Factor : Double write SetFactor;

end;

implementation

{ TPenalty }

function TPenalty.CalcPenalty(diag: TVMobj): Double;
var

  amax,amin:Double;
  p : Double;

begin

  MaxMinValues(diag, amax, amin);

  p := Max(abs(amin), abs(amax));

  Result:=p*1e5;

end;

constructor TPenalty.Create;
begin

  FFactor := 0;

end;

procedure TPenalty.Impose(IsFixed : TBooleanArray; Values : TDoubleArray; var A : TVMSparseMtx; b : TVMobj);
var

  e : ELibException;

  i: Integer;

  diag : TVMobj;

begin

  if A.Cols <> b.Rows*b.Cols then
  begin

    e := ELibException.Create('Error: b.Length <> A.Cols');
    e.Error := erIndexOutOfBounds;
    Raise e;

  end;

  diag := SparseDiag(A);

  if FFactor = 0 then
  begin
    FFactor := CalcPenalty(diag);
  end;

  for i := 0 to A.Cols-1 do
  begin

    if IsFixed[i] = True then
    begin

      // Penalty method: factor
      diag[i,0] := FFactor;
      b[i,0] := FFactor * Values[i];

    end;

  end;

  SetDiagonal(A, diag);

end;

procedure TPenalty.SetFactor(const Value: Double);
begin

  FFactor := Value;

end;

end.
