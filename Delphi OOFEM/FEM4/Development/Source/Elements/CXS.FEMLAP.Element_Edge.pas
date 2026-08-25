unit CXS.FEMLAP.Element_Edge;

{$mode delphi}{$H+}

interface

uses CXS.FEMLAP.Node, CXS.FEMLAP.Element, SysUtils;

type TElement_Edge = class(TElement)

  protected

    FLength : Double;
    FSectionArea : Double;
    FPerimeter : Double;

  public

    property Length : Double read FLength;
    property SectionArea: Double read FSectionArea write FSectionArea;
    property Perimeter : Double  read FPerimeter write FPerimeter;

end;

implementation

end.
