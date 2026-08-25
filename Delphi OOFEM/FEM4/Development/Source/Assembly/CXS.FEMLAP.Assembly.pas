unit CXS.FEMLAP.Assembly;

{$mode delphi}{$H+}

interface

uses newVM, newVMsparse;

type TAssembly = class(TObject)

  public

    procedure Add(Ae : TVMobj; be, b : TVMobj; Row, Col: TIntegerArray; Val: TDoubleArray;
    var n : Integer; Nbnodes : Integer; Node : Array of Integer; NbVars : Integer = 1); overload;

    procedure Add(Ae, Me : TVMobj; be, b : TVMobj; Row, Col: TIntegerArray; Val1, Val2: TDoubleArray;
    var n : Integer; Nbnodes : Integer; Node : Array of Integer; NbVars : Integer = 1); overload;

    procedure Add(Ae : TVMobj; be, b : TVMobj; Row, Col: TIntegerArray; Val: TDoubleArray;
    var n : Integer; Nbnodes : Integer; Node : Array of Integer; MSize : Integer; IsFixed : TBooleanArray; KnownValues : TDoubleArray;
    OldToNew : TIntegerArray; NbVars : Integer = 1); overload;

    procedure Add(Ae, Me : TVMobj; be, b : TVMobj; Row, Col: TIntegerArray; Val1, Val2: TDoubleArray;
    var n : Integer; Nbnodes : Integer; Node : Array of Integer; MSize : Integer; IsFixed : TBooleanArray; KnownValues : TDoubleArray;
    OldToNew : TIntegerArray; NbVars : Integer = 1); overload;

  end;

implementation

{ TAssembly }

procedure TAssembly.Add(Ae : TVMobj; be, b: TVMobj; Row, Col: TIntegerArray;
  Val: TDoubleArray; var n: Integer; Nbnodes : Integer; Node: Array of Integer; NbVars : Integer);
var

  nvarj, nvark: Integer;
  j, k: Integer;

begin

  for nvarj := 0 to NbVars - 1 do
  begin

    for j := 0 to Nbnodes-1 do
    begin

      for nvark := 0 to NbVars - 1 do
      begin

        for k := 0 to Nbnodes-1 do
        begin

          Row[n] := Node[j] * NbVars + nvarj;
          Col[n] := Node[k] * NbVars + nvark;
          Val[n] := Ae[j * NbVars + nvarj, k * NbVars + nvark];
          Inc(n);

        end;

      end;

      b[Node[j] * NbVars + nvarj, 0] := b[Node[j] * NbVars + nvarj, 0] + be[j * NbVars + nvarj, 0];

    end;

  end;

end;

procedure TAssembly.Add(Ae : TVMobj; be, b : TVMobj; Row, Col: TIntegerArray; Val: TDoubleArray;
    var n : Integer; Nbnodes : Integer; Node : Array of Integer; MSize : Integer; IsFixed : TBooleanArray;
    KnownValues : TDoubleArray;
    OldToNew : TIntegerArray; NbVars : Integer);
var

  nvarj, nvark : Integer;
  j, k: Integer;

begin

  for nvarj := 0 to NbVars - 1 do
  begin

    for j := 0 to Nbnodes-1 do
    begin

      if IsFixed[Node[j] * NbVars + nvarj] then
        Continue
      else
        if (OldToNew[Node[j] * NbVars + nvarj] >= 0) and (OldToNew[Node[j] * NbVars + nvarj] < MSize) then
          b[OldToNew[Node[j] * NbVars + nvarj], 0] := b[OldToNew[Node[j] * NbVars + nvarj], 0] + be[j * NbVars + nvarj, 0];

      for nvark := 0 to NbVars - 1 do
      begin

        for k := 0 to Nbnodes-1 do
        begin

          // Elimination method
          if IsFixed[Node[k] * NbVars + nvark] then
          begin
            if (OldToNew[Node[j] * NbVars + nvarj] >= 0) and (OldToNew[Node[j] * NbVars + nvarj] < MSize) then
              b[OldToNew[Node[j] * NbVars + nvarj], 0] := b[OldToNew[Node[j] * NbVars + nvarj], 0] - Ae[j * NbVars + nvarj,k * NbVars + nvark] * KnownValues[Node[k] * NbVars + nvark];
          end
          else
          begin

            Row[n] := OldToNew[Node[j] * NbVars + nvarj];
            Col[n] := OldToNew[Node[k] * NbVars + nvark];
            Val[n] := Ae[j * NbVars + nvarj,k * NbVars + nvark];
            Inc(n);

          end;

        end;

      end;

    end;

  end;

end;

procedure TAssembly.Add(Ae, Me: TVMobj; be, b: TVMobj; Row, Col: TIntegerArray;
  Val1, Val2: TDoubleArray; var n: Integer; Nbnodes: Integer;
  Node: array of Integer; MSize: Integer; IsFixed: TBooleanArray;
  KnownValues: TDoubleArray; OldToNew: TIntegerArray; NbVars : Integer);
var

  nvarj, nvark : Integer;
  j, k: Integer;

begin

  for nvarj := 0 to NbVars - 1 do
  begin

    for nvark := 0 to NbVars - 1 do
    begin

      for j := 0 to Nbnodes-1 do
      begin

        if IsFixed[Node[j] * NbVars + nvarj] then
          Continue
        else
          if (OldToNew[Node[j] * NbVars + nvarj] >= 0) and (OldToNew[Node[j] * NbVars + nvarj] < MSize) then
            b[OldToNew[Node[j] * NbVars + nvarj], 0] := b[OldToNew[Node[j] * NbVars + nvarj], 0] + be[j * NbVars + nvarj, 0];

        for k := 0 to Nbnodes-1 do
        begin

          // Elimination method
          if IsFixed[Node[k] * NbVars + nvark] then
          begin
            if (OldToNew[Node[j] * NbVars + nvarj] >= 0) and (OldToNew[Node[j] * NbVars + nvarj] < MSize) then
              b[OldToNew[Node[j] * NbVars + nvarj], 0] := b[OldToNew[Node[j] * NbVars + nvarj], 0] - Ae[j * NbVars + nvarj,k * NbVars + nvark] * KnownValues[Node[k] * NbVars + nvark];
          end
          else
          begin

            Row[n] := OldToNew[Node[j] * NbVars + nvarj];
            Col[n] := OldToNew[Node[k] * NbVars + nvark];
            Val1[n] := Ae[j * NbVars + nvarj,k * NbVars + nvark];
            Val2[n] := Me[j * NbVars + nvarj,k * NbVars + nvark];
            Inc(n);

          end;

        end;

      end;

    end;

  end;

end;

procedure TAssembly.Add(Ae, Me: TVMobj; be, b: TVMobj; Row, Col: TIntegerArray;
  Val1, Val2: TDoubleArray; var n: Integer; Nbnodes: Integer;
  Node: array of Integer; NbVars : Integer);
var

  nvarj, nvark : Integer;
  j, k: Integer;

begin

  for nvarj := 0 to NbVars - 1 do
  begin

    for nvark := 0 to NbVars - 1 do
    begin

      for j := 0 to Nbnodes-1 do
      begin
        for k := 0 to Nbnodes-1 do
        begin

          Row[n] := Node[j] * NbVars + nvarj;
          Col[n] := Node[k] * NbVars + nvark;
          Val1[n] := Ae[j * NbVars + nvarj, k * NbVars + nvark];
          Val2[n] := Me[j * NbVars + nvarj, k * NbVars + nvark];
          Inc(n);

        end;

        b[Node[j] * NbVars + nvarj, 0] := b[Node[j] * NbVars + nvarj, 0] + be[j * NbVars + nvarj, 0];

      end;

    end;

  end;

end;

end.
