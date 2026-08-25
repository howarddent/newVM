unit CXS.FEMLAP.Element_Brick;

{$mode delphi}{$H+}

interface

uses CXS.FEMLAP.Node, CXS.FEMLAP.Element_Edge, CXS.FEMLAP.Element_Face, CXS.FEMLAP.Element, SysUtils;

type TElement_Brick = class(TElement)
  private

    function GetEdges(EIndex: Integer): TElement_Edge;
    function GetFaces(FIndex: Integer): TElement_Face;

  protected

    FNbEdges : Integer;
    FEdges : Array of TElement_Edge;

    FNbFaces : Integer;
    FFaces : Array of TElement_Face;

    FVolume : Double;

  public

    property Volume: Double read FVolume write FVolume;

    property NbEdges : Integer read FNbEdges;
    property Edges[EIndex : Integer] : TElement_Edge read GetEdges;

    property NbFaces : Integer read FNbFaces;
    property Faces[FIndex : Integer] : TElement_Face read GetFaces;

end;

implementation

{ TElement_Brick }

function TElement_Brick.GetEdges(EIndex: Integer): TElement_Edge;
begin

  Result := FEdges[EIndex];

end;

function TElement_Brick.GetFaces(FIndex: Integer): TElement_Face;
begin

  Result := FFaces[FIndex];

end;

end.
