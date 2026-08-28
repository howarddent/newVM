unit CXS.FEMLAP.Gmsh;

{$mode delphi}{$H+}

interface

uses SysUtils, newVMsparse; //for TDoubleArray only - see newVMsparse.pas's own header comment

const
      GMSH_BEAM      = 1;
      GMSH_TRI       = 2;
      GMSH_QUAD      = 3;
      GMSH_TETRA     = 4;
      GMSH_HEXA      = 5;
      GMSH_PRISM     = 6;

type RGmshNode = record

  Id : Integer;
  x, y, z : Double;
  OnBoundary : Boolean;

end;

type RGmshElement = record

  Id : Integer;
  EleType : Integer;
  PhysReg : Integer;
  EleReg : Integer;
  NbNodes : Integer;
  Node : Array of Integer;

end;

type RGmshNodeBC = record

  IsFixed : Boolean;
  Value : Double;

end;

type TGmsh = class(TObject)

  private

    FGmshFile : TextFile;

    FNbNodes : Integer;
    FNbElements : Integer;

    FNodes : Array of RGmshNode;
    FElements : Array of RGmshElement;
    FNodesBC : Array of RGmshNodeBC;
    
    function GetElementPhysicalRegion(EIndex: Integer): Integer;

    function GetNodeBCIsFixed(NIndex: Integer): Boolean;
    function GetNodeBCValue(NIndex: Integer): Double;
    procedure SetNodeBCIsFixed(NIndex: Integer; const Value: Boolean);
    procedure SetNodeBCValue(NIndex: Integer; const Value: Double);

    function GetCoordX(NIndex: Integer): Double;
    function GetCoordY(NIndex: Integer): Double;
    function GetCoordZ(NIndex: Integer): Double;
    function GetElementNode(EIndex, NIndex: Integer): Integer;
    function GetElementType(EIndex: Integer): Integer;
    function GetNbElements: Integer;
    function GetNbNodes: Integer;
    function GetNodeOnBoundary(NIndex : Integer): Boolean;

  public

    procedure OpenFile(FileName : String);

    procedure ReWriteFile;

    procedure GenerateLine(dx : Double; meshsize : Double; EleType : Integer);
    procedure GenerateRectangle(dx, dy : Double; meshsize : Double; EleType : Integer);
    procedure GenerateBox(dx, dy, dz : Double; meshsize : Double; EleType : Integer);

    procedure ReadMesh;

    procedure WriteViewScalarNode(ViewName : String; v : TDoubleArray; ReWriteFile : Boolean = True);
    procedure WriteViewVectorNode(ViewName : String; u, v, w : TDoubleArray; ReWriteFile : Boolean = True);

    procedure WriteViewScalarElement(ViewName : String; v : TDoubleArray; ReWriteFile : Boolean = True);
    procedure WriteViewVectorElement(ViewName : String; u, v, w : TDoubleArray; ReWriteFile : Boolean = True);

    procedure WriteViewScalarNodeExt(ViewName : String; v : TDoubleArray; ReWriteFile : Boolean = True);

    procedure Close;

    property NbNodes : Integer read GetNbNodes;
    property NbElements : Integer read GetNbElements;
    property ElementType[EIndex: Integer] : Integer read GetElementType;
    property ElementPhysicalRegion[EIndex: Integer] : Integer read GetElementPhysicalRegion;
    property ElementNode[EIndex, NIndex : Integer] : Integer read GetElementNode;
    property CoordX[NIndex : Integer] : Double read GetCoordX;
    property CoordY[NIndex : Integer] : Double read GetCoordY;
    property CoordZ[NIndex : Integer] : Double read GetCoordZ;

    property NodeBCIsFixed[NIndex : Integer] : Boolean read GetNodeBCIsFixed write SetNodeBCIsFixed;
    property NodeBCValue[NIndex : Integer] : Double read GetNodeBCValue write SetNodeBCValue;

    procedure CalculateBoundary(EleBndType : Array of Integer);

    property NodeOnBoundary[NIndex : Integer] : Boolean read GetNodeOnBoundary;


end;

implementation

uses CXS.FEMLAP.Extrapolation;

{ Reading or (re)creating a .msh/.pos file right after another part of the
  same pipeline just wrote it - the exact pattern every FEM4 example
  follows, calling OpenFile/Reset or OpenFile/ReWrite repeatedly across a
  multi-step solve - occasionally hits a transient "Invalid filename"
  I/O error with no code-level cause: nothing about the path or the
  Pascal side changes between a failing attempt and an immediately
  following successful retry. The working theory (confirmed operationally
  across several examples: Windows Defender or another background handle
  briefly opens/scans a just-written file, and Reset/ReWrite's own
  underlying CreateFile call collides with that window) can't be fixed
  from this side of the API - only ridden out. A short retry loop is the
  standard way to absorb exactly this class of transient sharing
  violation, so both Reset (open a file for reading) and ReWrite (create/
  truncate one for writing) route through here now instead of being
  called directly. }
procedure SafeReset(var F: TextFile);
const
  MaxAttempts = 8;
  RetryDelayMs = 50;
var
  Attempt: Integer;
begin
  for Attempt := 1 to MaxAttempts do
  begin
    try
      Reset(F);
      Exit;
    except
      if Attempt = MaxAttempts then
        raise;
      Sleep(RetryDelayMs);
    end;
  end;
end;

procedure SafeReWrite(var F: TextFile);
const
  MaxAttempts = 8;
  RetryDelayMs = 50;
var
  Attempt: Integer;
begin
  for Attempt := 1 to MaxAttempts do
  begin
    try
      ReWrite(F);
      Exit;
    except
      if Attempt = MaxAttempts then
        raise;
      Sleep(RetryDelayMs);
    end;
  end;
end;

{ TGmsh }

procedure TGmsh.GenerateLine(dx: Double; meshsize : Double; EleType: Integer);
begin

    SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'Mesh.MshFileVersion=1;');

    WriteLn(FGmshFile, 'cl = ' + FloatToStr(meshsize) + ';');

    WriteLn(FGmshFile, 'dx = ' + FloatToStr(dx) + ';');

    WriteLn(FGmshFile, 'Point(1) = {0,0,0,cl};');
    WriteLn(FGmshFile, 'Point(2) = {dx,0,0,cl};');

    WriteLn(FGmshFile, 'Line(1) = {1,2};');

    if (EleType = GMSH_BEAM) then
    begin

      WriteLn(FGmshFile, 'Physical Line(2) = {1};');

    end;

end;

procedure TGmsh.CalculateBoundary(EleBndType: Array of Integer);
var

  i, j, k : Integer;

begin

  for i := 0 to NbNodes - 1 do
  begin

    FNodes[i].OnBoundary := False;

  end;

  for i := 0 to NbElements - 1 do
  begin

    for j := 0 to Length(EleBndType) - 1 do
    begin

      if FElements[i].EleType = EleBndType[j] then
      begin

        for k := 0 to FElements[i].NbNodes - 1 do
        begin

          FNodes[FElements[i].Node[k]].OnBoundary := True;

        end;

      end;

    end;

  end;


end;

procedure TGmsh.Close;
begin

  CloseFile(FGmshFile);

end;

procedure TGmsh.GenerateBox(dx, dy, dz: Double; meshsize : Double; EleType: Integer);
begin

    SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'Mesh.MshFileVersion=1;');

    WriteLn(FGmshFile, 'cl = ' + FloatToStr(meshsize) + ';');

    WriteLn(FGmshFile, 'dx = ' + FloatToStr(dx) + ';');
    WriteLn(FGmshFile, 'dy = ' + FloatToStr(dy) + ';');
    WriteLn(FGmshFile, 'dz = ' + FloatToStr(dz) + ';');

    WriteLn(FGmshFile, 'Point(1) = {0,0,0,cl};');
    WriteLn(FGmshFile, 'Point(2) = {dx,0,0,cl};');
    WriteLn(FGmshFile, 'Point(3) = {dx,dy,0,cl};');
    WriteLn(FGmshFile, 'Point(4) = {0,dy,0,cl};');

    WriteLn(FGmshFile, 'Line(1) = {1,2};');
    WriteLn(FGmshFile, 'Line(2) = {2,3};');
    WriteLn(FGmshFile, 'Line(3) = {3,4};');
    WriteLn(FGmshFile, 'Line(4) = {4,1};');

    WriteLn(FGmshFile, 'Line Loop(5) = {1,2,3,4};');
    WriteLn(FGmshFile, 'Plane Surface(6) = {5};');

    if (EleType = GMSH_TETRA) then
    begin

      WriteLn(FGmshFile, 'ext() = Extrude {0,0,dz} { Surface{6}; };');
      WriteLn(FGmshFile, 'Physical Volume(7) = {ext(1)};');

    end;

    if (EleType = GMSH_HEXA) or (EleType = GMSH_PRISM) then
    begin

      if EleType = GMSH_HEXA then
        WriteLn(FGmshFile, 'Recombine Surface {6};');

      WriteLn(FGmshFile, 'Transfinite Surface {6} = {1,2,3,4};');

      WriteLn(FGmshFile, 'ext() = Extrude {0,0,dz} { Surface{6}; Layers { {' + IntToStr(Trunc(dz / meshsize + 1)) + '}, {1}}; Recombine; };');

      WriteLn(FGmshFile, 'Physical Volume(7) = {ext(1)};');

    end;

end;

procedure TGmsh.GenerateRectangle(dx, dy: Double; meshsize : Double; EleType: Integer);
begin

    SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'Mesh.MshFileVersion=1;');

    WriteLn(FGmshFile, 'cl = ' + FloatToStr(meshsize) + ';');

    WriteLn(FGmshFile, 'dx = ' + FloatToStr(dx) + ';');
    WriteLn(FGmshFile, 'dy = ' + FloatToStr(dy) + ';');

    WriteLn(FGmshFile, 'Point(1) = {0,0,0,cl};');
    WriteLn(FGmshFile, 'Point(2) = {dx,0,0,cl};');
    WriteLn(FGmshFile, 'Point(3) = {dx,dy,0,cl};');
    WriteLn(FGmshFile, 'Point(4) = {0,dy,0,cl};');

    WriteLn(FGmshFile, 'Line(1) = {1,2};');
    WriteLn(FGmshFile, 'Line(2) = {2,3};');
    WriteLn(FGmshFile, 'Line(3) = {3,4};');
    WriteLn(FGmshFile, 'Line(4) = {4,1};');

    WriteLn(FGmshFile, 'Line Loop(5) = {1,2,3,4};');
    WriteLn(FGmshFile, 'Plane Surface(6) = {5};');

    if (EleType = GMSH_TRI) then
    begin

      WriteLn(FGmshFile, 'Physical Surface(7) = {6};');

    end;

    if (EleType = GMSH_QUAD) then
    begin

      WriteLn(FGmshFile, 'Recombine Surface {6};');
      WriteLn(FGmshFile, 'Transfinite Surface {6} = {1,2,3,4};');

      WriteLn(FGmshFile, 'Physical Surface(7) = {6};');

    end;

end;

function TGmsh.GetCoordX(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= FNbNodes-1) then
    Result := FNodes[NIndex].x
  else
    Result := 0;

end;

function TGmsh.GetCoordY(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= FNbNodes-1) then
    Result := FNodes[NIndex].y
  else
    Result := 0;

end;

function TGmsh.GetCoordZ(NIndex: Integer): Double;
begin

  if (NIndex >= 0) and (NIndex <= FNbNodes-1) then
    Result := FNodes[NIndex].z
  else
    Result := 0;

end;

function TGmsh.GetElementNode(EIndex, NIndex: Integer): Integer;
begin

  Result := FElements[EIndex].Node[NIndex];

end;

function TGmsh.GetElementPhysicalRegion(EIndex: Integer): Integer;
begin

  Result := FElements[EIndex].PhysReg;

end;

function TGmsh.GetElementType(EIndex: Integer): Integer;
begin

  Result := FElements[EIndex].EleType;

end;

function TGmsh.GetNbElements: Integer;
begin

  Result := FNbElements;

end;

function TGmsh.GetNbNodes: Integer;
begin

  Result := FNbNodes;

end;

function TGmsh.GetNodeBCIsFixed(NIndex: Integer): Boolean;
begin

  Result := FNodesBC[NIndex].IsFixed;

end;

function TGmsh.GetNodeBCValue(NIndex: Integer): Double;
begin

  Result := FNodesBC[NIndex].Value;

end;

function TGmsh.GetNodeOnBoundary(NIndex : Integer): Boolean;
begin

  Result := FNodes[NIndex].OnBoundary;

end;

procedure TGmsh.OpenFile(FileName: String);
begin

  AssignFile(FGmshFile, FileName);

end;

procedure TGmsh.ReadMesh;
var

  i, j: Integer;

  Node : Integer;
  RenNode : Array of Integer;

  Tag : String;

begin

    SafeReset(FGmshFile);

    ReadLn(FGmshFile, Tag); //$NOD

    ReadLn(FGmshFile, FNbNodes);

    SetLength(FNodes, FNbNodes);
    SetLength(FNodesBC, FNbNodes);

    SetLength(RenNode, FNbNodes);

    for i := 0 to FNbNodes-1 do
    begin

      ReadLn(FGmshFile, FNodes[i].Id, FNodes[i].x, FNodes[i].y, FNodes[i].z);

      FNodesBC[i].IsFixed := False;
      FNodesBC[i].Value := 0;

      if (FNodes[i].Id >= Length(RenNode)) then
        SetLength(RenNode, Length(RenNode) + FNodes[i].Id + 1);

      // Renumber nodes from 0 to n-1
      RenNode[FNodes[i].id] := i;
      FNodes[i].id := i;

    end;

    ReadLn(FGmshFile, Tag); //$ENDNOD

    ReadLn(FGmshFile, Tag); //$ELM

    ReadLn(FGmshFile, FNbElements);

    SetLength(FElements, FNbElements);

    for i := 0 to FNbElements-1 do
    begin

      Read(FGmshFile, FElements[i].id, FElements[i].EleType, FElements[i].PhysReg, FElements[i].EleReg);

      Read(FGmshFile, FElements[i].NbNodes);

      SetLength(FElements[i].Node, FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes-1 do
      begin

        Read(FGmshFile, Node);

        // Set renumbered node index
        FElements[i].Node[j] := RenNode[Node];

      end;

    end;

    ReadLn(FGmshFile, Tag); //$ENDELM

end;

procedure TGmsh.ReWriteFile;
begin

  SafeReWrite(FGmshFile);

end;

procedure TGmsh.SetNodeBCIsFixed(NIndex: Integer; const Value: Boolean);
begin

  FNodesBC[NIndex].IsFixed := Value;

end;

procedure TGmsh.SetNodeBCValue(NIndex: Integer; const Value: Double);
begin

  FNodesBC[NIndex].Value := Value;

end;

procedure TGmsh.WriteViewScalarElement(ViewName: String; v: TDoubleArray; ReWriteFile: Boolean);
var

  i, j: Integer;

  node : Array of Integer;
  cx, cy, cz : Array of Double;

begin

    if ReWriteFile then
      SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'View "'+ ViewName + '" {');

    for i := 0 to FNbElements - 1 do
    begin

      SetLength(node,  FElements[i].NbNodes);

      SetLength(cx,  FElements[i].NbNodes);
      SetLength(cy,  FElements[i].NbNodes);
      SetLength(cz,  FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        node[j] := FElements[i].Node[j];
      end;

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        cx[j] := FNodes[node[j]].x;
        cy[j] := FNodes[node[j]].y;
        cz[j] := FNodes[node[j]].z;
      end;

      if (FElements[i].EleType = GMSH_BEAM) then
      begin
        WriteLn(FGmshFile, Format('SL(%e,%e,%e,%e,%e,%e){%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1],
          v[i], v[i]]));
      end;

      if (FElements[i].EleType = GMSH_TRI) then
      begin
        WriteLn(FGmshFile, Format('ST(%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2],
          v[i], v[i], v[i]]));
      end;

      if (FElements[i].EleType = GMSH_QUAD) then
      begin
        WriteLn(FGmshFile, Format('SQ(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          v[i], v[i], v[i], v[i]]));
      end;

      if (FElements[i].EleType = GMSH_TETRA) then
      begin
        WriteLn(FGmshFile, Format('SS(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          v[i], v[i], v[i], v[i]]));
      end;

      if (FElements[i].EleType = GMSH_HEXA) then
      begin
        WriteLn(FGmshFile, Format('SH(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5], cx[6], cy[6], cz[6], cx[7], cy[7], cz[7],
          v[i], v[i], v[i], v[i], v[i], v[i], v[i], v[i]]));
      end;

      if (FElements[i].EleType = GMSH_PRISM) then
      begin
        WriteLn(FGmshFile, Format('SI(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5],
          v[i], v[i], v[i], v[i], v[i], v[i]]));
      end;

    end;

    WriteLn(FGmshFile, '};');

end;

procedure TGmsh.WriteViewScalarNode(ViewName : String; v : TDoubleArray; ReWriteFile : Boolean);
var

  i, j: Integer;

  node : Array of Integer;
  cx, cy, cz : Array of Double;

begin

    if ReWriteFile then
      SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'View "'+ ViewName + '" {');

    for i := 0 to FNbElements - 1 do
    begin

      SetLength(node,  FElements[i].NbNodes);

      SetLength(cx,  FElements[i].NbNodes);
      SetLength(cy,  FElements[i].NbNodes);
      SetLength(cz,  FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        node[j] := FElements[i].Node[j];
      end;

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        cx[j] := FNodes[node[j]].x;
        cy[j] := FNodes[node[j]].y;
        cz[j] := FNodes[node[j]].z;
      end;

      if (FElements[i].EleType = GMSH_BEAM) then
      begin
        WriteLn(FGmshFile, Format('SL(%e,%e,%e,%e,%e,%e){%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1],
          v[node[0]], v[node[1]]]));
      end;

      if (FElements[i].EleType = GMSH_TRI) then
      begin
        WriteLn(FGmshFile, Format('ST(%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2],
          v[node[0]], v[node[1]], v[node[2]]]));
      end;

      if (FElements[i].EleType = GMSH_QUAD) then
      begin
        WriteLn(FGmshFile, Format('SQ(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          v[node[0]], v[node[1]], v[node[2]], v[node[3]]]));
      end;

      if (FElements[i].EleType = GMSH_TETRA) then
      begin
        WriteLn(FGmshFile, Format('SS(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          v[node[0]], v[node[1]], v[node[2]], v[node[3]]]));
      end;

      if (FElements[i].EleType = GMSH_HEXA) then
      begin
        WriteLn(FGmshFile, Format('SH(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5], cx[6], cy[6], cz[6], cx[7], cy[7], cz[7],
          v[node[0]], v[node[1]], v[node[2]], v[node[3]], v[node[4]], v[node[5]], v[node[6]], v[node[7]]]));
      end;

      if (FElements[i].EleType = GMSH_PRISM) then
      begin
        WriteLn(FGmshFile, Format('SI(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5],
          v[node[0]], v[node[1]], v[node[2]], v[node[3]], v[node[4]], v[node[5]]]));
      end;

    end;

    WriteLn(FGmshFile, '};');

end;

procedure TGmsh.WriteViewScalarNodeExt(ViewName: String; v: TDoubleArray; ReWriteFile: Boolean);
var

  i, j: Integer;

  node : Array of Integer;
  cx, cy, cz : Array of Double;

  vn : Array[0..7] of Double;

  Extrapolation : TExtrapolation;

begin

    Extrapolation := TExtrapolation.Create;

    if ReWriteFile then
      SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'View "'+ ViewName + '" {');

    for i := 0 to FNbElements - 1 do
    begin

      SetLength(node,  FElements[i].NbNodes);

      SetLength(cx,  FElements[i].NbNodes);
      SetLength(cy,  FElements[i].NbNodes);
      SetLength(cz,  FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        node[j] := FElements[i].Node[j];
      end;

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        cx[j] := FNodes[node[j]].x;
        cy[j] := FNodes[node[j]].y;
        cz[j] := FNodes[node[j]].z;
      end;

      if (FElements[i].EleType = GMSH_BEAM) then
      begin

        for j := 0 to 1 do
          vn[j] := v[node[j]];

        WriteLn(FGmshFile, Format('SL(%e,%e,%e,%e,%e,%e){%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1],
          vn[0], vn[1]]));

      end;

      if (FElements[i].EleType = GMSH_TRI) then
      begin

        for j := 0 to 2 do
          vn[j] := v[node[j]];

        WriteLn(FGmshFile, Format('ST(%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2],
          vn[0], vn[1], vn[2]]));

      end;

      if (FElements[i].EleType = GMSH_QUAD) then
      begin

        vn[0] := Extrapolation.QuadExtrapolateToNode(0, v[node[0]], v[node[1]], v[node[2]], v[node[3]]);
        vn[1] := Extrapolation.QuadExtrapolateToNode(1, v[node[0]], v[node[1]], v[node[2]], v[node[3]]);
        vn[2] := Extrapolation.QuadExtrapolateToNode(2, v[node[0]], v[node[1]], v[node[2]], v[node[3]]);
        vn[3] := Extrapolation.QuadExtrapolateToNode(3, v[node[0]], v[node[1]], v[node[2]], v[node[3]]);

        WriteLn(FGmshFile, Format('SQ(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          vn[0], vn[1], vn[2], vn[3]]));

      end;

      if (FElements[i].EleType = GMSH_TETRA) then
      begin

        for j := 0 to 3 do
          vn[j] := v[node[j]];

        WriteLn(FGmshFile, Format('SS(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          v[0], v[1], v[2], v[3]]));

      end;

      if (FElements[i].EleType = GMSH_HEXA) then
      begin

        for j := 0 to 7 do
          vn[j] := v[node[j]];

        WriteLn(FGmshFile, Format('SH(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5], cx[6], cy[6], cz[6], cx[7], cy[7], cz[7],
          v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]]));

      end;

      if (FElements[i].EleType = GMSH_PRISM) then
      begin

        for j := 0 to 5 do
          vn[j] := v[node[j]];

        WriteLn(FGmshFile, Format('SI(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5],
          v[0], v[1], v[2], v[3], v[4], v[5]]));

      end;

    end;

    WriteLn(FGmshFile, '};');

    Extrapolation.Free;

end;

procedure TGmsh.WriteViewVectorElement(ViewName: String; u, v, w: TDoubleArray; ReWriteFile: Boolean);
var

  i, j: Integer;

  node : Array of Integer;
  cx, cy, cz : Array of Double;

begin

    if ReWriteFile then
      SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'View "'+ ViewName + '" {');

    for i := 0 to FNbElements - 1 do
    begin

      SetLength(node,  FElements[i].NbNodes);

      SetLength(cx,  FElements[i].NbNodes);
      SetLength(cy,  FElements[i].NbNodes);
      SetLength(cz,  FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        node[j] := FElements[i].Node[j];
      end;

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        cx[j] := FNodes[node[j]].x;
        cy[j] := FNodes[node[j]].y;
        cz[j] := FNodes[node[j]].z;
      end;

      if (FElements[i].EleType = GMSH_BEAM) then
      begin
        WriteLn(FGmshFile, Format('VL(%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

      if (FElements[i].EleType = GMSH_TRI) then
      begin
        WriteLn(FGmshFile, Format('VT(%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

      if (FElements[i].EleType = GMSH_QUAD) then
      begin
        WriteLn(FGmshFile, Format('VQ(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

      if (FElements[i].EleType = GMSH_TETRA) then
      begin
        WriteLn(FGmshFile, Format('VS(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

      if (FElements[i].EleType = GMSH_HEXA) then
      begin
        WriteLn(FGmshFile, Format('VH(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5], cx[6], cy[6], cz[6], cx[7], cy[7], cz[7],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

      if (FElements[i].EleType = GMSH_PRISM) then
      begin
        WriteLn(FGmshFile, Format('VI(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i],
          u[i], v[i], w[i]]));
      end;

    end;

    WriteLn(FGmshFile, '};');

end;

procedure TGmsh.WriteViewVectorNode(ViewName: String; u, v, w: TDoubleArray; ReWriteFile: Boolean);
var

  i, j: Integer;

  node : Array of Integer;
  cx, cy, cz : Array of Double;

begin

    if ReWriteFile then
      SafeReWrite(FGmshFile);

    WriteLn(FGmshFile, 'View "'+ ViewName + '" {');

    for i := 0 to FNbElements - 1 do
    begin

      SetLength(node,  FElements[i].NbNodes);

      SetLength(cx,  FElements[i].NbNodes);
      SetLength(cy,  FElements[i].NbNodes);
      SetLength(cz,  FElements[i].NbNodes);

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        node[j] := FElements[i].Node[j];
      end;

      for j := 0 to FElements[i].NbNodes - 1 do
      begin
        cx[j] := FNodes[node[j]].x;
        cy[j] := FNodes[node[j]].y;
        cz[j] := FNodes[node[j]].z;
      end;

      if (FElements[i].EleType = GMSH_BEAM) then
      begin
        WriteLn(FGmshFile, Format('VL(%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]]]));
      end;

      if (FElements[i].EleType = GMSH_TRI) then
      begin
        WriteLn(FGmshFile, Format('VT(%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]],
          u[node[2]], v[node[2]], w[node[2]]]));
      end;

      if (FElements[i].EleType = GMSH_QUAD) then
      begin
        WriteLn(FGmshFile, Format('VQ(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]],
          u[node[2]], v[node[2]], w[node[2]],
          u[node[3]], v[node[3]], w[node[3]]]));
      end;

      if (FElements[i].EleType = GMSH_TETRA) then
      begin
        WriteLn(FGmshFile, Format('VS(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]],
          u[node[2]], v[node[2]], w[node[2]],
          u[node[3]], v[node[3]], w[node[3]]]));
      end;

      if (FElements[i].EleType = GMSH_HEXA) then
      begin
        WriteLn(FGmshFile, Format('VH(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5], cx[6], cy[6], cz[6], cx[7], cy[7], cz[7],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]],
          u[node[2]], v[node[2]], w[node[2]],
          u[node[3]], v[node[3]], w[node[3]],
          u[node[4]], v[node[4]], w[node[4]],
          u[node[5]], v[node[5]], w[node[5]],
          u[node[6]], v[node[6]], w[node[6]],
          u[node[7]], v[node[7]], w[node[7]]]));
      end;

      if (FElements[i].EleType = GMSH_PRISM) then
      begin
        WriteLn(FGmshFile, Format('VI(%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e){%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e,%e};',
          [cx[0], cy[0], cz[0], cx[1], cy[1], cz[1], cx[2], cy[2], cz[2], cx[3], cy[3], cz[3],cx[4], cy[4], cz[4], cx[5], cy[5], cz[5],
          u[node[0]], v[node[0]], w[node[0]],
          u[node[1]], v[node[1]], w[node[1]],
          u[node[2]], v[node[2]], w[node[2]],
          u[node[3]], v[node[3]], w[node[3]],
          u[node[4]], v[node[4]], w[node[4]],
          u[node[5]], v[node[5]], w[node[5]]]));
      end;

    end;

    WriteLn(FGmshFile, '};');

end;

end.
