unit CXS.FEMLAP.Element_Face;

{$mode delphi}{$H+}

interface

uses CXS.FEMLAP.Node, CXS.FEMLAP.Element_Edge, CXS.FEMLAP.Element, SysUtils;

type TElement_Face = class(TElement)
  private

    function GetEdges(EIndex : Integer): TElement_Edge;

  protected

    FNbEdges : Integer;
    FEdges : Array of TElement_Edge;

    FArea : Double;
    FThickness : Double;

  public

    property Thickness: Double read FThickness write FThickness;
    property Area: Double read FArea write FArea;

    property NbEdges : Integer read FNbEdges;
    property Edges[EIndex : Integer] : TElement_Edge read GetEdges;

end;

implementation

{ TElement_Face }

function TElement_Face.GetEdges(EIndex : Integer): TElement_Edge;
begin

  Result := FEdges[EIndex];

end;

end.
