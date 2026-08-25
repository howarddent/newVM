unit CXS.FEMLAP.Extrapolation;

{$mode delphi}{$H+}

interface

uses Math;

type TExtrapolation = class(TObject)

  private

  public

    (*
    Description:
      Extrapolate value to the nodal position of the element.
    Parameters:
      NIndex - [in] node id (0 - 3).
      v0, v1, v2 v3 - [in] values at gauss points.
    Returns:
      Value at the node.
    *)
    function QuadExtrapolateToNode(NIndex: Integer; v0, v1, v2, v3: Double): Double;

end;

implementation


{ TExtrapolation }

function TExtrapolation.QuadExtrapolateToNode(NIndex: Integer; v0, v1, v2, v3: Double): Double;
var

  xil, etal : Double;

  f : Double;

  vn : Array[0..4] of Double;
  N : Array[0..4] of Double;

  i : Integer;

begin

  Result := 0;

  f := Sqrt(3);

  xil := 0;
  etal := 0;

  case NIndex of
  0: begin xil := -1.0 * f; etal := -1.0 * f; end;
  1: begin xil := +1.0 * f; etal := -1.0 * f; end;
  2: begin xil := +1.0 * f; etal := +1.0 * f; end;
  3: begin xil := -1.0 * f; etal := +1.0 * f; end;
  end;

  vn[0] := v0;
  vn[1] := v1;
  vn[2] := v2;
  vn[3] := v3;

  N[0] := 0.25*(1-xil)*(1-etal);
  N[1] := 0.25*(1+xil)*(1-etal);
  N[2] := 0.25*(1+xil)*(1+etal);
  N[3] := 0.25*(1-xil)*(1+etal);

  for i := 0 to 3 do
    Result := Result + vn[i]*N[i];

end;

end.
