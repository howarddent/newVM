unit uAortaTree;

{ The aorta from the valve to the common femoral arteries, with the left
  arm's arteries to the wrist, as a tree of one-dimensional vessels
  (uArtery1D) driven by the finite-element left ventricle's aortic valve
  flow (LeftVentricle/lvrun --csv).

  VESSELS (lengths and radii in cm; proximal -> distal radius)

      ascending aorta                4.0   1.47 -> 1.44
      aortic arch A                  2.0   1.20 -> 1.12
      aortic arch B                  3.9   1.12 -> 1.07
      thoracic aorta A               5.2   1.00 -> 0.95
      thoracic aorta B              10.4   0.95 -> 0.65
      abdominal aorta A              5.3   0.65 -> 0.61   coeliac to SMA
      abdominal aorta B              1.0   0.60 -> 0.59   SMA to renals
      abdominal aorta C             10.6   0.58 -> 0.55   renals to IMA
      abdominal aorta D              1.0   0.52 -> 0.52   IMA to bifurcation
      common iliac, left and right   5.8   0.40 -> 0.37
      external iliac, both          14.4   0.32 -> 0.27   to the common femoral
      left subclavian                3.4   0.42 -> 0.40   to the vertebral
      left axillary and brachial    42.2   0.40 -> 0.24
      left radial                   23.5   0.174 -> 0.142

  These follow the arterial tree of Stergiopulos, Young & Rogge 1992
  (J Biomech 25:1477) as used by Alastruey et al.; they are typical
  values set down from memory of those tables, not one subject's
  measurements. Wave speeds come from the diameters (uArtery1D.WaveSpeed).

  OTHER BRANCHES are lumped beds at the junction where they leave: coronaries, brachiocephalic, left common
  carotid, left vertebral, intercostals (lumped at mid-thorax), coeliac,
  superior mesenteric, both renals, inferior mesenteric, internal iliacs
  and the ulnar (with the interosseous). The common femoral arteries and
  the radial at the wrist end in beds too. Each bed's resistance is the
  total peripheral resistance divided by its share of the cardiac output
  (typical resting values, my estimates).

  With CPeriph = 0 a bed is that resistance alone, which reflects most of
  the wave. Otherwise (the default, 0.8 mL/mmHg in all) it is a
  three-element Windkessel: in series the characteristic impedance of the
  artery that leads to it - for a side branch from the radius given in
  BuildTree (typical values, from memory; the intercostals' is a guess
  for many small arteries), for the femoral and radial ends the vessel's
  own - then the bed's share of CPeriph beside the rest of the resistance.
  The wave front then passes into each branch as into a tube, and the
  ends are matched.

  AORTIC ELASTANCE   AorticStiff multiplies beta (dp/dA at a given area)
  in the nine aortic vessels; OtherStiff does the same for the iliacs
  and the arm. The wave speed goes as the square root.

  INPUT   One-way: the valve flow of the ventricle's last beat is
  imposed at the inlet, repeated every period. The ventricle does not
  feel the aorta here. }

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils, Math, uArtery1D;

type
  TLVInput = class
  public
    T, Q, PRoot, PLV: array of Double;   { s, mL/s, mmHg }
    Period: Double;
    procedure Load(const FileName: string);
    function Flow(tt: Double): Double;
    function StrokeVolume: Double;
  end;

  TProbe = record
    Name: string;
    V: TVessel;
    S: Double;          { fraction of the vessel's length }
    Dist: Double;       { from the valve, cm }
    P, Q: array of Double;   { the last beat: mmHg, mL/s }
    Sys, Dia, Mean, TSys, TFoot, PWV: Double;  { mmHg, s, cm/s from the root }
  end;

  TPathNode = record
    V: TVessel;
    Node: Integer;
    Dist: Double;
  end;
  TPath = record
    Name: string;
    Nodes: array of TPathNode;
    P: array of array of Single;   { [frame][node], mmHg }
  end;

  TAortaSim = class
  public
    Tree: TArterialTree;
    LV: TLVInput;
    AorticStiff, OtherStiff: Double;
    HTarget, CFL: Double;
    RTotal: Double;             { mmHg s/mL }
    CPeriph: Double;            { mL/mmHg in the lumped beds; 0 = pure resistances }
    WallTau: Double;            { wall retardation time phi/E, ms; 0 = elastic wall }
    Beats: Integer;
    DtOut, DtFrame: Double;
    Probes: array of TProbe;
    Paths: array[0..1] of TPath;   { to the left radial, to the left femoral }
    TOut: array of Double;
    NFrames: Integer;
    { every node of every vessel at each frame, for a viewer: vessel v's
      node k is at VOff[v] + k. Pressure in mmHg; radius over its value
      at the reference pressure. }
    VOff: array of Integer;
    FrameEvery: Integer;        { output samples per frame }
    FrameP, FrameR: array of array of Single;
    PMin, PMax: Double;         { over all frames and nodes }
    { of the last beat }
    Steps: Integer;
    PeriodicErr: Double;        { largest change of a probe's pressure over the beat, mmHg }
    VolIn, VolOut, VolStored: Double;
    LeakMean: array of Double;  { mean flow through each junction's resistance, mL/s }
    constructor Create;
    destructor Destroy; override;
    procedure BuildTree;
    procedure Run;
    function ProbeIndex(const AName: string): Integer;
    procedure WriteCSV(const FileName: string);
    procedure WriteField(const FileName: string);
  end;

implementation

{ ---- TLVInput ---- }

procedure TLVInput.Load(const FileName: string);
var
  L, H, F: TStringList;
  i, it, iq, ip, il, n: Integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  L := TStringList.Create; H := TStringList.Create; F := TStringList.Create;
  try
    L.LoadFromFile(FileName);
    H.Delimiter := ','; H.StrictDelimiter := True; H.DelimitedText := L[0];
    it := H.IndexOf('t_s'); iq := H.IndexOf('Qaortic_mL_s');
    ip := H.IndexOf('Proot_mmHg'); il := H.IndexOf('PLV_mmHg');
    if (it < 0) or (iq < 0) or (ip < 0) or (il < 0) then
      raise Exception.Create(FileName + ' : not an lvrun --csv file');
    n := 0;
    SetLength(T, L.Count); SetLength(Q, L.Count); SetLength(PRoot, L.Count); SetLength(PLV, L.Count);
    F.Delimiter := ','; F.StrictDelimiter := True;
    for i := 1 to L.Count - 1 do
    begin
      if Trim(L[i]) = '' then Continue;
      F.DelimitedText := L[i];
      T[n] := StrToFloat(F[it], FS); Q[n] := StrToFloat(F[iq], FS);
      PRoot[n] := StrToFloat(F[ip], FS); PLV[n] := StrToFloat(F[il], FS);
      Inc(n);
    end;
    SetLength(T, n); SetLength(Q, n); SetLength(PRoot, n); SetLength(PLV, n);
    Period := T[n - 1] - T[0];
  finally
    L.Free; H.Free; F.Free;
  end;
end;

function TLVInput.Flow(tt: Double): Double;
var
  n, i: Integer;
  f: Double;
begin
  n := High(T);
  tt := tt - Period * Floor(tt / Period);
  f := tt / Period * n;
  i := Min(Floor(f), n - 1);
  f := f - i;
  Result := (1 - f) * Q[i] + f * Q[i + 1];
end;

function TLVInput.StrokeVolume: Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to High(T) do Result := Result + 0.5 * (Q[i] + Q[i - 1]) * (T[i] - T[i - 1]);
end;

{ ---- TAortaSim ---- }

constructor TAortaSim.Create;
begin
  inherited Create;
  LV := TLVInput.Create;
  AorticStiff := 1; OtherStiff := 1;
  HTarget := 0.5; CFL := 0.6;
  CPeriph := 0.8;
  WallTau := 5;       { assumed: see uArtery1D }
  RTotal := 1.147;    { the ventricle model's Windkessel: Zc + Rp }
  Beats := 25;
  DtOut := 0.001; DtFrame := 0.004;
end;

destructor TAortaSim.Destroy;
begin
  Tree.Free;
  LV.Free;
  inherited Destroy;
end;

procedure TAortaSim.BuildTree;
var
  T: TArterialTree;

  procedure Probe(const AName, Vessel: string; AS_, ADist: Double);
  var
    k: Integer;
  begin
    k := Length(Probes);
    SetLength(Probes, k + 1);
    Probes[k].Name := AName;
    Probes[k].V := T.FindVessel(Vessel);
    Probes[k].S := AS_;
    Probes[k].Dist := ADist;
  end;

  procedure Path(Index: Integer; const AName: string; const Names: array of string);
  var
    i, k, m: Integer;
    d: Double;
    V: TVessel;
  begin
    Paths[Index].Name := AName;
    SetLength(Paths[Index].Nodes, 0);
    d := 0;
    for i := 0 to High(Names) do
    begin
      V := T.FindVessel(Names[i]);
      for k := 0 to V.NNode - 1 do
      begin
        m := Length(Paths[Index].Nodes);
        SetLength(Paths[Index].Nodes, m + 1);
        Paths[Index].Nodes[m].V := V;
        Paths[Index].Nodes[m].Node := k;
        Paths[Index].Nodes[m].Dist := d + k * V.Dx;
      end;
      d := d + V.Len;
    end;
  end;

begin
  Tree.Free;
  SetLength(Probes, 0);
  T := TArterialTree.Create;
  Tree := T;
  { the aorta }
  T.AddVessel('ascending aorta', 0, 1, 4.0, 1.47, 1.44, True);
  T.AddVessel('aortic arch A', 1, 2, 2.0, 1.20, 1.12, True);
  T.AddVessel('aortic arch B', 2, 3, 3.9, 1.12, 1.07, True);
  T.AddVessel('thoracic aorta A', 3, 4, 5.2, 1.00, 0.95, True);
  T.AddVessel('thoracic aorta B', 4, 5, 10.4, 0.95, 0.65, True);
  T.AddVessel('abdominal aorta A', 5, 6, 5.3, 0.65, 0.61, True);
  T.AddVessel('abdominal aorta B', 6, 7, 1.0, 0.60, 0.59, True);
  T.AddVessel('abdominal aorta C', 7, 8, 10.6, 0.58, 0.55, True);
  T.AddVessel('abdominal aorta D', 8, 9, 1.0, 0.52, 0.52, True);
  { the legs, to the common femoral arteries }
  T.AddVessel('left common iliac', 9, 10, 5.8, 0.40, 0.37, False);
  T.AddVessel('left external iliac', 10, 11, 14.4, 0.32, 0.27, False);
  T.AddVessel('right common iliac', 9, 12, 5.8, 0.40, 0.37, False);
  T.AddVessel('right external iliac', 12, 13, 14.4, 0.32, 0.27, False);
  { the left arm }
  T.AddVessel('left subclavian', 3, 14, 3.4, 0.42, 0.40, False);
  T.AddVessel('left brachial', 14, 15, 42.2, 0.40, 0.24, False);
  T.AddVessel('left radial', 15, 16, 23.5, 0.174, 0.142, False);
  { the branches not modelled, with their share of the cardiac output, % }
  T.SetInlet(0);
  T.AddLeak(0, 'coronaries', 4.5, 0.17, 2);
  T.AddLeak(1, 'brachiocephalic', 11.5, 0.62);
  T.AddLeak(2, 'left common carotid', 6.5, 0.37);
  T.AddLeak(4, 'intercostals', 4.0, 0.30);
  T.AddLeak(5, 'coeliac', 14.0, 0.39);
  T.AddLeak(6, 'superior mesenteric', 12.0, 0.43);
  T.AddLeak(7, 'renals', 20.0, 0.26, 2);
  T.AddLeak(8, 'inferior mesenteric', 3.5, 0.16);
  T.AddLeak(10, 'left internal iliac', 3.5, 0.20);
  T.AddLeak(11, 'left common femoral (leg)', 6.0);
  T.AddLeak(12, 'right internal iliac', 3.5, 0.20);
  T.AddLeak(13, 'right common femoral (leg)', 6.0);
  T.AddLeak(14, 'left vertebral', 1.5, 0.19);
  T.AddLeak(15, 'left ulnar and interosseous', 2.2, 0.21);
  T.AddLeak(16, 'left radial at the wrist (hand)', 1.3);
  T.WallTau := WallTau / 1000;
  T.Build(HTarget, AorticStiff, OtherStiff, RTotal * mmHg, CPeriph / mmHg);
  T.Inflow := LV.Flow;

  Probe('aortic root', 'ascending aorta', 0, 0);
  Probe('aortic arch', 'aortic arch B', 1, 9.9);
  Probe('thoracic aorta', 'thoracic aorta B', 0.5, 20.3);
  Probe('abdominal aorta', 'abdominal aorta C', 0.5, 37.1);
  Probe('aortic bifurcation', 'abdominal aorta D', 1, 43.4);
  Probe('left common femoral', 'left external iliac', 1, 63.6);
  Probe('left subclavian', 'left subclavian', 0.5, 11.6);
  Probe('left brachial (elbow)', 'left brachial', 1, 55.5);
  Probe('left radial (wrist)', 'left radial', 1, 79.0);
  Path(0, 'valve to left radial', ['ascending aorta', 'aortic arch A', 'aortic arch B',
    'left subclavian', 'left brachial', 'left radial']);
  Path(1, 'valve to left common femoral', ['ascending aorta', 'aortic arch A', 'aortic arch B',
    'thoracic aorta A', 'thoracic aorta B', 'abdominal aorta A', 'abdominal aorta B',
    'abdominal aorta C', 'abdominal aorta D', 'left common iliac', 'left external iliac']);
end;

function TAortaSim.ProbeIndex(const AName: string): Integer;
var
  i: Integer;
begin
  for i := 0 to High(Probes) do
    if SameText(Probes[i].Name, AName) then Exit(i);
  Result := -1;
end;

procedure TAortaSim.Run;
var
  beat, k, i, n, nOut, fr, every, im, i0: Integer;
  tNext, dt, tb, v0, slope, s: Double;
  Last: Boolean;

  procedure Sample(idx: Integer);
  var
    a, b, fi: Integer;
    pv: Double;
  begin
    TOut[idx] := idx * LV.Period / nOut;
    for a := 0 to High(Probes) do
    begin
      Probes[a].P[idx] := Probes[a].V.PressureAt(Probes[a].S) / mmHg;
      Probes[a].Q[idx] := Probes[a].V.FlowAt(Probes[a].S);
    end;
    if (idx mod every = 0) and (idx div every < NFrames) then
      for a := 0 to 1 do
        for b := 0 to High(Paths[a].Nodes) do
          Paths[a].P[idx div every][b] := Paths[a].Nodes[b].V.Pressure(Paths[a].Nodes[b].Node) / mmHg;
    if (idx mod every = 0) and (idx div every < NFrames) then
    begin
      fi := idx div every;
      for a := 0 to High(Tree.Vessels) do
        for b := 0 to Tree.Vessels[a].NNode - 1 do
        begin
          pv := Tree.Vessels[a].Pressure(b) / mmHg;
          FrameP[fi][VOff[a] + b] := pv;
          FrameR[fi][VOff[a] + b] := Sqrt(Tree.Vessels[a].A[b] / Tree.Vessels[a].A0[b]);
          PMin := Min(PMin, pv); PMax := Max(PMax, pv);
        end;
    end;
  end;

begin
  BuildTree;
  nOut := Round(LV.Period / DtOut);
  every := Max(1, Round(DtFrame / DtOut));
  NFrames := nOut div every;
  SetLength(TOut, nOut + 1);
  for i := 0 to High(Probes) do
  begin
    SetLength(Probes[i].P, nOut + 1); SetLength(Probes[i].Q, nOut + 1);
  end;
  for i := 0 to 1 do
  begin
    SetLength(Paths[i].P, NFrames);
    for k := 0 to NFrames - 1 do SetLength(Paths[i].P[k], Length(Paths[i].Nodes));
  end;
  SetLength(LeakMean, Length(Tree.J));
  FrameEvery := every;
  SetLength(VOff, Length(Tree.Vessels) + 1);
  VOff[0] := 0;
  for i := 0 to High(Tree.Vessels) do VOff[i + 1] := VOff[i] + Tree.Vessels[i].NNode;
  SetLength(FrameP, NFrames); SetLength(FrameR, NFrames);
  for k := 0 to NFrames - 1 do
  begin
    SetLength(FrameP[k], VOff[Length(Tree.Vessels)]);
    SetLength(FrameR[k], VOff[Length(Tree.Vessels)]);
  end;
  PMin := Infinity; PMax := -Infinity;
  for beat := 1 to Beats do
  begin
    Last := beat = Beats;
    tb := (beat - 1) * LV.Period;
    if Last then
    begin
      Steps := 0; VolIn := 0; VolOut := 0; v0 := Tree.Volume;
      for i := 0 to High(LeakMean) do LeakMean[i] := 0;
      Sample(0);
    end;
    for k := 1 to nOut do
    begin
      tNext := tb + k * LV.Period / nOut;
      while Tree.Time < tNext - 1e-12 do
      begin
        dt := Tree.StableDt(CFL);
        n := Ceil((tNext - Tree.Time) / dt - 1e-9);
        dt := (tNext - Tree.Time) / n;
        Tree.Step(dt);
        if Last then
        begin
          Inc(Steps);
          VolIn := VolIn + dt * LV.Flow(Tree.Time);
          for i := 0 to High(Tree.J) do
          begin
            VolOut := VolOut + dt * Tree.J[i].QLeak;
            LeakMean[i] := LeakMean[i] + dt * Tree.J[i].QLeak / LV.Period;
          end;
        end;
      end;
      if Last then Sample(k);
    end;
  end;
  VolStored := Tree.Volume - v0;
  PeriodicErr := 0;
  { each probe's figures; the foot of the wave by intersecting tangents:
    where the tangent at the steepest upstroke meets the diastolic minimum
    before it }
  for i := 0 to High(Probes) do
    with Probes[i] do
    begin
      PeriodicErr := Max(PeriodicErr, Abs(P[nOut] - P[0]));
      Sys := -Infinity; Dia := Infinity; Mean := 0;
      for k := 1 to nOut do
      begin
        if P[k] > Sys then begin Sys := P[k]; TSys := TOut[k]; end;
        Dia := Min(Dia, P[k]);
        Mean := Mean + P[k] / nOut;
      end;
      { the first upstroke: from the diastolic minimum to half the pulse }
      i0 := 0;
      for k := 0 to nOut - 1 do
        if P[k] < P[i0] then i0 := k;
      slope := 0; im := i0 + 1;
      for k := i0 + 1 to i0 + nOut do
      begin
        fr := (k - 1) mod nOut;
        s := (P[fr + 1] - P[fr]) / DtOut;
        if s > slope then begin slope := s; im := k; end;
        if P[fr + 1] > Dia + 0.5 * (Sys - Dia) then Break;
      end;
      fr := (im - 1) mod nOut;
      TFoot := (im - 0.5) * LV.Period / nOut - (0.5 * (P[fr] + P[fr + 1]) - Dia) / slope;
      if TFoot > LV.Period then TFoot := TFoot - LV.Period;
    end;
  for i := 0 to High(Probes) do
    if Probes[i].Dist > 0 then
      Probes[i].PWV := Probes[i].Dist / (Probes[i].TFoot - Probes[0].TFoot)
    else
      Probes[i].PWV := 0;
end;

procedure TAortaSim.WriteCSV(const FileName: string);
var
  f: TextFile;
  i, k: Integer;
  FS: TFormatSettings;
  nm: string;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  AssignFile(f, FileName); Rewrite(f);
  Write(f, 't_s,Qvalve_mL_s,PLV_mmHg,Proot_LVmodel_mmHg');
  for i := 0 to High(Probes) do
  begin
    nm := StringReplace(StringReplace(StringReplace(Probes[i].Name, ' ', '_', [rfReplaceAll]),
      '(', '', [rfReplaceAll]), ')', '', [rfReplaceAll]);
    Write(f, ',P_', nm, ',Q_', nm);
  end;
  Writeln(f);
  for k := 0 to High(TOut) do
  begin
    i := Min(Round(TOut[k] / LV.Period * High(LV.T)), High(LV.T));
    Write(f, Format('%.5f,%.3f,%.3f,%.3f', [TOut[k], LV.Flow(TOut[k]), LV.PLV[i], LV.PRoot[i]], FS));
    for i := 0 to High(Probes) do
      Write(f, Format(',%.4f,%.4f', [Probes[i].P[k], Probes[i].Q[k]], FS));
    Writeln(f);
  end;
  CloseFile(f);
end;

{ per path: a line "path <name> <nodes> <frames> <frame interval s>", a
  line of distances (cm), then one line of pressures (mmHg) per frame }
procedure TAortaSim.WriteField(const FileName: string);
var
  f: TextFile;
  a, i, k: Integer;
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  AssignFile(f, FileName); Rewrite(f);
  for a := 0 to 1 do
  begin
    Writeln(f, Format('path %s;%d;%d;%.6f', [Paths[a].Name, Length(Paths[a].Nodes), NFrames,
      LV.Period / NFrames], FS));
    for i := 0 to High(Paths[a].Nodes) do Write(f, Format('%.3f ', [Paths[a].Nodes[i].Dist], FS));
    Writeln(f);
    for k := 0 to NFrames - 1 do
    begin
      for i := 0 to High(Paths[a].Nodes) do Write(f, Format('%.2f ', [Paths[a].P[k][i]], FS));
      Writeln(f);
    end;
  end;
  CloseFile(f);
end;

end.
