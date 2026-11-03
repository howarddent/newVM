unit uWallAnim;

{ One steady ventilator cycle of the abdomen's moving surfaces, as
  `hfjvrun --anim=<file>` writes it, read back for display (HFJVView).

  The file holds:
    a header line  rate <per min> ti <fraction> dp <bar> frames <n>
                   period <s> box <0|1>
    nodes <n>      then x y z per node, m (every mesh node)
    tris <m>       then a b c surface per boundary triangle, 0-based
                   nodes; surface 0 rigid, 1 anterior wall, 2 diaphragm
    moving <k>     then node clamped eta_0 .. eta_(n-1) per moving node,
                   the outward displacement in um at each frame (all
                   harmonics, the mean taken out)
    vl ...         the lung volume at each frame, mL (mean removed)

  On reading, the nodes are put into a display frame, the same one
  anim_wall.py uses: across the body, along it, and up (the front, for
  the supine torso). The torso keeps Defibrillation's coordinates (y up
  from the back, z from the perineum), the box has z up and x along it.
  Vertex normals are area-weighted over the boundary triangles and
  turned outwards (away from the centroid, on average), so a
  displacement is drawn by moving the node along its normal.

  The front midline - the anterior wall's nodes within 10 mm of the
  body's midplane on its upper side, one every 5 mm along the body,
  nearest the plane - is picked out for the profile plot, as in
  anim_wall.py. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math;

type

  TV3 = record
    X, Y, Z : Double;
  end;

  TWallAnim = class
  public
    FileName : String;
    Rate, Ti, DrivingP, Period : Double;   // /min, fraction, bar, s
    Frames : Integer;
    IsBox : Boolean;

    // the display frame: X across, Y along (head +), Z up
    P : array of TV3;           // m
    N : array of TV3;           // unit outward vertex normals
    Tri : array of Integer;     // 3 per triangle
    Surf : array of Integer;    // per triangle
    D : array of array of Single;   // m, [node][frame]; 0 off the moving surfaces
    VL : array of Double;       // mL, per frame
    MaxDisp : Double;           // m, the largest |displacement|
    Lo, Hi, Centre : TV3;       // bounding box, m
    Mid : array of Integer;     // front-midline nodes, along the body
    NMoving : Integer;

    procedure LoadFromFile(const Fn : String);
    function NbNodes : Integer;
    function NbTris : Integer;
    // the time at frame j, s
    function TimeAt(j : Integer) : Double;
    function JetOn(j : Integer) : Boolean;
  end;

implementation

function TWallAnim.NbNodes : Integer;
begin
  Result := Length(P);
end;

function TWallAnim.NbTris : Integer;
begin
  Result := Length(Surf);
end;

function TWallAnim.TimeAt(j : Integer) : Double;
begin
  Result := Period * j / Frames;
end;

function TWallAnim.JetOn(j : Integer) : Boolean;
begin
  Result := TimeAt(j) < Ti * Period;
end;

procedure TWallAnim.LoadFromFile(const Fn : String);
var
  L : TStringList;
  Line : Integer;
  FS : TFormatSettings;

  function NextLine : String;
  begin
    if Line >= L.Count then
      raise Exception.Create(Fn + ': the file ends early');
    Result := L[Line];
    Inc(Line);
  end;

  // the line's whitespace-separated words
  procedure Split(const S : String; W : TStrings);
  begin
    W.Clear;
    ExtractStrings([' ', #9], [], PChar(S), W);
  end;

  function Count(const S, Key : String) : Integer;
  var
    W : TStringList;
  begin
    W := TStringList.Create;
    try
      Split(S, W);
      if (W.Count < 2) or (W[0] <> Key) then
        raise Exception.CreateFmt('%s: expected "%s <count>" at line %d', [Fn, Key, Line]);
      Result := StrToInt(W[1]);
    finally
      W.Free;
    end;
  end;

var
  W : TStringList;
  i, k, j, a, b, c, nn, nt, nm, half : Integer;
  Raw : array of TV3;
  e1, e2, fn_, Sum : TV3;
  s, sMed : Double;
  Cand : array of Integer;
  Bin, LastBin : Integer;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  L := TStringList.Create;
  W := TStringList.Create;
  try
    L.LoadFromFile(Fn);
    Line := 0;

    // header
    Split(NextLine, W);
    Rate := 200; Ti := 0.5; DrivingP := 2; Frames := 0; Period := 0.3; IsBox := False;
    i := 0;
    while i + 1 < W.Count do
    begin
      if W[i] = 'rate' then Rate := StrToFloat(W[i + 1], FS)
      else if W[i] = 'ti' then Ti := StrToFloat(W[i + 1], FS)
      else if W[i] = 'dp' then DrivingP := StrToFloat(W[i + 1], FS)
      else if W[i] = 'frames' then Frames := StrToInt(W[i + 1])
      else if W[i] = 'period' then Period := StrToFloat(W[i + 1], FS)
      else if W[i] = 'box' then IsBox := W[i + 1] = '1';
      Inc(i, 2);
    end;
    if Frames <= 0 then
      raise Exception.Create(Fn + ': not an hfjvrun --anim file (no frame count)');

    // nodes, into the display frame
    nn := Count(NextLine, 'nodes');
    SetLength(Raw, nn);
    SetLength(P, nn);
    for k := 0 to nn - 1 do
    begin
      Split(NextLine, W);
      Raw[k].X := StrToFloat(W[0], FS);
      Raw[k].Y := StrToFloat(W[1], FS);
      Raw[k].Z := StrToFloat(W[2], FS);
      if IsBox then
      begin
        P[k].X := Raw[k].Y; P[k].Y := Raw[k].X; P[k].Z := Raw[k].Z;
      end
      else
      begin
        P[k].X := Raw[k].X; P[k].Y := Raw[k].Z; P[k].Z := Raw[k].Y;
      end;
    end;

    nt := Count(NextLine, 'tris');
    SetLength(Tri, 3 * nt);
    SetLength(Surf, nt);
    for k := 0 to nt - 1 do
    begin
      Split(NextLine, W);
      Tri[3 * k] := StrToInt(W[0]);
      Tri[3 * k + 1] := StrToInt(W[1]);
      Tri[3 * k + 2] := StrToInt(W[2]);
      Surf[k] := StrToInt(W[3]);
    end;

    nm := Count(NextLine, 'moving');
    NMoving := nm;
    SetLength(D, nn, Frames);
    for k := 0 to nn - 1 do
      for j := 0 to Frames - 1 do
        D[k][j] := 0;
    MaxDisp := 0;
    for k := 0 to nm - 1 do
    begin
      Split(NextLine, W);
      a := StrToInt(W[0]);
      for j := 0 to Frames - 1 do
      begin
        D[a][j] := 1E-6 * StrToFloat(W[2 + j], FS);
        MaxDisp := Max(MaxDisp, Abs(D[a][j]));
      end;
    end;

    Split(NextLine, W);
    SetLength(VL, Frames);
    for j := 0 to Frames - 1 do
      VL[j] := StrToFloat(W[1 + j], FS);
  finally
    W.Free;
    L.Free;
  end;
  FileName := Fn;

  // bounding box
  Lo := P[0]; Hi := P[0];
  for k := 1 to nn - 1 do
  begin
    Lo.X := Min(Lo.X, P[k].X); Hi.X := Max(Hi.X, P[k].X);
    Lo.Y := Min(Lo.Y, P[k].Y); Hi.Y := Max(Hi.Y, P[k].Y);
    Lo.Z := Min(Lo.Z, P[k].Z); Hi.Z := Max(Hi.Z, P[k].Z);
  end;
  Centre.X := (Lo.X + Hi.X) / 2;
  Centre.Y := (Lo.Y + Hi.Y) / 2;
  Centre.Z := (Lo.Z + Hi.Z) / 2;

  // area-weighted vertex normals
  SetLength(N, nn);
  for k := 0 to nn - 1 do
  begin
    N[k].X := 0; N[k].Y := 0; N[k].Z := 0;
  end;
  for k := 0 to nt - 1 do
  begin
    a := Tri[3 * k]; b := Tri[3 * k + 1]; c := Tri[3 * k + 2];
    e1.X := P[b].X - P[a].X; e1.Y := P[b].Y - P[a].Y; e1.Z := P[b].Z - P[a].Z;
    e2.X := P[c].X - P[a].X; e2.Y := P[c].Y - P[a].Y; e2.Z := P[c].Z - P[a].Z;
    fn_.X := e1.Y * e2.Z - e1.Z * e2.Y;
    fn_.Y := e1.Z * e2.X - e1.X * e2.Z;
    fn_.Z := e1.X * e2.Y - e1.Y * e2.X;
    for i := 0 to 2 do
    begin
      j := Tri[3 * k + i];
      N[j].X := N[j].X + fn_.X;
      N[j].Y := N[j].Y + fn_.Y;
      N[j].Z := N[j].Z + fn_.Z;
    end;
  end;
  // outwards: away from the centroid of the surface nodes, on average
  Sum.X := 0; Sum.Y := 0; Sum.Z := 0;
  s := 0;
  for k := 0 to nn - 1 do
  begin
    sMed := Sqrt(Sqr(N[k].X) + Sqr(N[k].Y) + Sqr(N[k].Z));
    if sMed > 0 then
    begin
      N[k].X := N[k].X / sMed; N[k].Y := N[k].Y / sMed; N[k].Z := N[k].Z / sMed;
      s := s + (P[k].X - Centre.X) * N[k].X + (P[k].Y - Centre.Y) * N[k].Y
             + (P[k].Z - Centre.Z) * N[k].Z;
    end;
  end;
  if s < 0 then
    for k := 0 to nn - 1 do
    begin
      N[k].X := -N[k].X; N[k].Y := -N[k].Y; N[k].Z := -N[k].Z;
    end;

  // the front midline: anterior-wall nodes near the midplane, upper half
  // (anim_wall.py takes "upper" as above the median height; the mean
  // height does the same job here, only separating front from back)
  sMed := 0;
  for k := 0 to nn - 1 do
    sMed := sMed + P[k].Z;
  sMed := sMed / Max(nn, 1);
  half := 0;
  // the across-midplane: the box's is its middle, the torso's x = 0
  if IsBox then
    s := Centre.X
  else
    s := 0;
  SetLength(Cand, nn);
  for k := 0 to nt - 1 do
    if Surf[k] = 1 then
      for i := 0 to 2 do
      begin
        j := Tri[3 * k + i];
        if (Abs(P[j].X - s) < IfThen(IsBox, 0.012, 0.010)) and (P[j].Z > sMed) then
        begin
          Cand[half] := j;
          Inc(half);
        end;
      end;
  SetLength(Cand, half);
  // sort by position along the body (shell sort on a few hundred)
  i := half div 2;
  while i > 0 do
  begin
    for k := i to half - 1 do
    begin
      a := Cand[k];
      j := k;
      while (j >= i) and (P[Cand[j - i]].Y > P[a].Y) do
      begin
        Cand[j] := Cand[j - i];
        Dec(j, i);
      end;
      Cand[j] := a;
    end;
    i := i div 2;
  end;
  // one per 5 mm, the nearest the midplane
  SetLength(Mid, 0);
  LastBin := Low(Integer);
  for k := 0 to half - 1 do
  begin
    a := Cand[k];
    Bin := Round(P[a].Y / 0.005);
    if Bin <> LastBin then
    begin
      SetLength(Mid, Length(Mid) + 1);
      Mid[High(Mid)] := a;
      LastBin := Bin;
    end
    else if Abs(P[a].X - s) < Abs(P[Mid[High(Mid)]].X - s) then
      Mid[High(Mid)] := a;
  end;
end;

end.
