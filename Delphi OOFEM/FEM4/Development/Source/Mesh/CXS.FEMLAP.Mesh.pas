unit Mesh;

{$mode delphi}{$H+}

interface

uses SysUtils;

const
      MESH_BEAM      = 1;
      MESH_TRI       = 2;
      MESH_QUAD      = 3;
      MESH_TETRA     = 4;
      MESH_HEXA      = 5;
      MESH_PRISM     = 6;

type TMeshNode = record

  Id : Integer;
  x, y, z : Double;

end;

type TMeshElement = record

  Id : Integer;
  EleType : Integer;
  NbNodes : Integer;
  Node : Array of Integer;

end;

type TMesh = class(TObject)

  private

    fNbNodes : Integer;
    fNbElements : Integer;

    fNodes : Array of TMeshNode;
    fElements : Array of TMeshElement;

    function GetCoordX(NIndex: Integer): Double;
    function GetCoordY(NIndex: Integer): Double;
    function GetCoordZ(NIndex: Integer): Double;
    function GetElementNode(EIndex, NIndex: Integer): Integer;
    function GetElementType(EIndex: Integer): Integer;
    function GetNbElements: Integer;
    function GetNbNodes: Integer;

  public
    property NbNodes : Integer read GetNbNodes;
    property NbElements : Integer read GetNbElements;
    property ElementType[EIndex: Integer] : Integer read GetElementType;
    property ElementNode[EIndex, NIndex : Integer] : Integer read GetElementNode;
    property CoordX[NIndex : Integer] : Double read GetCoordX;
    property CoordY[NIndex : Integer] : Double read GetCoordY;
    property CoordZ[NIndex : Integer] : Double read GetCoordZ;

end;

implementation

{ TMesh }

function TMesh.GetCoordX(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= fNbNodes-1) then
    Result := fNodes[NIndex].x
  else
    Result := 0;

end;

function TMesh.GetCoordY(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= fNbNodes-1) then
    Result := fNodes[NIndex].y
  else
    Result := 0;

end;

function TMesh.GetCoordZ(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= fNbNodes-1) then
    Result := fNodes[NIndex].z
  else
    Result := 0;

end;

function TMesh.GetElementNode(EIndex, NIndex: Integer): Integer;
begin

  Result := fElements[EIndex].Node[NIndex];

end;

function TMesh.GetElementType(EIndex: Integer): Integer;
begin

  Result := fElements[EIndex].EleType;

end;

function TMesh.GetNbElements: Integer;
begin

  Result := fNbElements;

end;

function TMesh.GetNbNodes: Integer;
begin

  Result := fNbNodes;

end;

end.
