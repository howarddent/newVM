unit uLVAnim;

{ One beat of the finite-element left ventricle, as written by
  `lvrun --anim=<file>` (the format is in uLVHeart.WriteAnim): the
  unloaded mesh, the wall's displacements and each element's fibre
  stretch and active stress at a number of frames, and the pressures,
  volumes and valve flows at every time step.

  The mesh is uLVMech's structured one: NR elements through the wall
  (i, from the endocardium), NL from apex to base (j) and NC round (k),
  the apical ring collapsed onto the axis. Node and element numbering
  are repeated here so the file needs no connectivity. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math;

type
  TLVPhase = (phFilling, phIsoContraction, phEjection, phIsoRelaxation);

  TLVSample = record
    T, PLV, VLV, PLA, PRoot, QMV, QAV, ZMV, ZAV: Double;
    Phase: TLVPhase;
  end;

  TLVAnim = class
  public
    FileName: string;
    NR, NL, NC, NN, NE: Integer;
    Period, Ls0: Double;
    X: array of Single;                 { 3 NN, mm }
    S: array of TLVSample;
    Frames: Integer;
    FrameSample: array of Integer;
    U: array of array of Single;        { [frame][3 NN], mm }
    Lam, Tact: array of array of Single; { [frame][NE] }
    { over the beat }
    LamMin, LamMax, TactMax: Double;
    EDV, ESV, PeakP, EDP, AoSys, AoDia, PeakFlow: Double;
    ZMid: Double;                       { mid-height of the unloaded wall }
    procedure LoadFromFile(const Fn: string);
    function NodeId(i, j, k: Integer): Integer;
    function ElemId(i, j, k: Integer): Integer;
    function TimeAt(Frame: Integer): Double;
    function SampleAt(Frame: Integer): TLVSample;
    { the frame at or just before cycle time t }
    function FrameAtTime(t: Double): Integer;
  end;

const
  PhaseNames: array[TLVPhase] of string =
    ('filling', 'isovolumic contraction', 'ejection', 'isovolumic relaxation');

implementation

function TLVAnim.NodeId(i, j, k: Integer): Integer;
begin
  if j = 0 then
    Result := i
  else
  begin
    k := ((k mod NC) + NC) mod NC;
    Result := (NR + 1) + ((j - 1) * NC + k) * (NR + 1) + i;
  end;
end;

function TLVAnim.ElemId(i, j, k: Integer): Integer;
begin
  Result := (i * NL + j) * NC + ((k mod NC) + NC) mod NC;
end;

function TLVAnim.TimeAt(Frame: Integer): Double;
begin
  Result := S[FrameSample[Frame]].T;
end;

function TLVAnim.SampleAt(Frame: Integer): TLVSample;
begin
  Result := S[FrameSample[Frame]];
end;

function TLVAnim.FrameAtTime(t: Double): Integer;
var
  lo, hi, m: Integer;
begin
  lo := 0; hi := Frames - 1;
  while lo < hi do
  begin
    m := (lo + hi + 1) div 2;
    if TimeAt(m) <= t then lo := m else hi := m - 1;
  end;
  Result := lo;
end;

procedure TLVAnim.LoadFromFile(const Fn: string);
var
  f: TextFile;
  Tag: string;
  i, k, ns, ver, iej0, iej1: Integer;
  v: Double;
  zlo, zhi: Double;
  OldFS: TFormatSettings;
begin
  OldFS := DefaultFormatSettings;
  DefaultFormatSettings.DecimalSeparator := '.';
  AssignFile(f, Fn);
  Reset(f);
  try
    Readln(f, Tag);
    if Copy(Tag, 1, 6) <> 'LVANIM' then
      raise Exception.Create(Fn + ' is not an lvrun --anim file');
    ver := StrToIntDef(Trim(Copy(Tag, 7, MaxInt)), 0);
    if ver <> 1 then
      raise Exception.CreateFmt('%s: version %d is not known', [Fn, ver]);
    Read(f, NR, NL, NC, Period, Ls0);
    NN := (NR + 1) * (1 + NL * NC);
    NE := NR * NL * NC;
    SetLength(X, 3 * NN);
    for i := 0 to 3 * NN - 1 do begin Read(f, v); X[i] := v; end;
    Read(f, ns);
    SetLength(S, ns);
    for i := 0 to ns - 1 do
      Read(f, S[i].T, S[i].PLV, S[i].VLV, S[i].PLA, S[i].PRoot, S[i].QMV, S[i].QAV, S[i].ZMV, S[i].ZAV);
    Read(f, Frames);
    SetLength(FrameSample, Frames); SetLength(U, Frames);
    SetLength(Lam, Frames); SetLength(Tact, Frames);
    for k := 0 to Frames - 1 do
    begin
      Read(f, FrameSample[k]);
      SetLength(U[k], 3 * NN);
      for i := 0 to 3 * NN - 1 do begin Read(f, v); U[k][i] := v; end;
      SetLength(Lam[k], NE);
      for i := 0 to NE - 1 do begin Read(f, v); Lam[k][i] := v; end;
      SetLength(Tact[k], NE);
      for i := 0 to NE - 1 do begin Read(f, v); Tact[k][i] := v; end;
    end;
  finally
    CloseFile(f);
    DefaultFormatSettings := OldFS;
  end;
  FileName := Fn;

  LamMin := Infinity; LamMax := -Infinity; TactMax := 0;
  for k := 0 to Frames - 1 do
    for i := 0 to NE - 1 do
    begin
      LamMin := Min(LamMin, Lam[k][i]);
      LamMax := Max(LamMax, Lam[k][i]);
      TactMax := Max(TactMax, Tact[k][i]);
    end;
  zlo := Infinity; zhi := -Infinity;
  for i := 0 to NN - 1 do
  begin
    zlo := Min(zlo, X[3 * i + 2]);
    zhi := Max(zhi, X[3 * i + 2]);
  end;
  ZMid := 0.5 * (zlo + zhi);

  { the beat's figures, and the phase of each sample: a valve counts as
    open when its opening state is over 2 % }
  EDV := -Infinity; ESV := Infinity; PeakP := 0; AoSys := 0; AoDia := Infinity; PeakFlow := 0;
  iej0 := -1; iej1 := -1;
  for i := 0 to ns - 1 do
  begin
    EDV := Max(EDV, S[i].VLV);
    ESV := Min(ESV, S[i].VLV);
    PeakP := Max(PeakP, S[i].PLV);
    AoSys := Max(AoSys, S[i].PRoot);
    AoDia := Min(AoDia, S[i].PRoot);
    PeakFlow := Max(PeakFlow, S[i].QAV);
    if S[i].ZAV > 0.02 then
    begin
      if iej0 < 0 then iej0 := i;
      iej1 := i;
    end;
  end;
  EDP := S[0].PLV;  { at the start of depolarisation }
  for i := 0 to ns - 1 do
    if S[i].ZAV > 0.02 then
      S[i].Phase := phEjection
    else if S[i].ZMV > 0.02 then
      S[i].Phase := phFilling
    else if (iej0 >= 0) and (i > iej1) then
      S[i].Phase := phIsoRelaxation
    else
      S[i].Phase := phIsoContraction;
end;

end.
