unit uLVHeart;

{ The finite-element ventricle (uLVMech) coupled to the lumped
  circulation (uLVCirc), stepped through the cardiac cycle.

  Each time step solves the wall's equilibrium together with the cavity
  volume balance  V(u) = V_old + dt (q_mitral - q_aortic), the flows
  being the circulation's backward-Euler response to the new cavity
  pressure, so the isovolumic phases need no special treatment: with
  both valves shut the balance is simply a fixed volume.

  Cycle time 0 is the start of ventricular depolarisation. Pressures are
  reported in mmHg and volumes in mL. }

{$mode delphi}{$H+}

interface

uses
  SysUtils, Math, uLVMech, uLVCirc;

type
  THeartSample = record
    T, PLV, VLV, PLA, VLA, QMV, QAV, PRoot, QAo, PWk, ZMV, ZAV: Double;
    Stretch, Tact, Twist, Thick, LongAx, Radius: Double;
  end;
  THeartSamples = array of THeartSample;

  TBeatSummary = record
    EDV, ESV, SV, EF, CO, EDP, PeakLV, AoSys, AoDia, AoMean: Double;
    DPDtMax, DPDtMin, PeakFlow, EjectStart, EjectEnd, PeakTwist, TwistED: Double;
    ThickED, ThickES, LongED, LongES, StretchED, StretchES, PLAMean: Double;
  end;

  TLVHeart = class
  private
    FVn, FT, FDt, FVFix: Double;
    function VolTarget(P: Double; out dVdP: Double): Double;
    function VolFixed(P: Double; out dVdP: Double): Double;
    function TryStep(t0, dt: Double; Depth: Integer): Boolean;
    procedure Capture(SampleIdx: Integer);
  public
    Model: TLVModel;
    Circ: TLVCirc;
    JMid: Integer;      { the ring nearest the equator }
    JApex: Integer;     { the apical slice for twist }
    Steps, NewtonIts: Integer;
    { RunBeat keeps the wall's state every FrameEvery steps (0: not at
      all): nodal displacements, mm, and each element's mean fibre
      stretch and active stress. FrameSample is the sample it belongs to. }
    FrameEvery: Integer;
    FrameSample: array of Integer;
    FrameU, FrameL, FrameT: array of array of Single;
    constructor Create(const G: TLVGeom; const M: TLVMaterial);
    destructor Destroy; override;
    { passive filling to a cavity pressure (mmHg) or volume (mL) }
    procedure InflateToPressure(P: Double; NSteps: Integer);
    procedure InflateToVolume(V: Double; NSteps: Integer);
    function Sample(t: Double): THeartSample;
    { one cardiac cycle from cycle time 0 in steps of dt }
    procedure RunBeat(dt: Double; var S: THeartSamples);
    function Summarise(const S: THeartSamples): TBeatSummary;
    { the frames of the last RunBeat and its samples, for LVView }
    procedure WriteAnim(const FileName: string; const S: THeartSamples);
  end;

implementation

constructor TLVHeart.Create(const G: TLVGeom; const M: TLVMaterial);
var
  j: Integer;
  best, z: Double;
begin
  inherited Create;
  Model := TLVModel.Create(G, M);
  Circ := TLVCirc.Create;
  best := MaxDouble; JMid := 1;
  for j := 1 to G.NL do
  begin
    z := Abs(Model.X[3 * Model.NodeId(0, j, 0) + 2]);
    if z < best then begin best := z; JMid := j; end;
  end;
  { a quarter of the cavity's length above the apex }
  best := MaxDouble; JApex := 1;
  for j := 1 to G.NL do
  begin
    z := Abs(Model.X[3 * Model.NodeId(0, j, 0) + 2] - (-G.CEn + 0.25 * (G.CEn + G.ZB)));
    if z < best then begin best := z; JApex := j; end;
  end;
end;

destructor TLVHeart.Destroy;
begin
  Model.Free; Circ.Free;
  inherited;
end;

function TLVHeart.VolTarget(P: Double; out dVdP: Double): Double;
var
  q, slope: Double;
begin
  slope := Circ.TrialSlope(P / mmHg, FT, FDt, q);
  Result := FVn + FDt * q * 1000;
  dVdP := FDt * slope * 1000 / mmHg;
end;

function TLVHeart.VolFixed(P: Double; out dVdP: Double): Double;
begin
  Result := FVFix; dVdP := 0;
end;

procedure TLVHeart.InflateToPressure(P: Double; NSteps: Integer);
{ increments are halved when one fails: the unloaded wall is very soft }
var
  p0, p1, dp: Double;
begin
  p1 := P * mmHg;
  dp := (p1 - Model.Pcav) / NSteps;
  while Abs(p1 - Model.Pcav) > 1e-12 do
  begin
    p0 := Model.Pcav;
    if Abs(dp) > Abs(p1 - p0) then dp := p1 - p0;
    if Model.Solve(0, 0, False, cmPressure, p0 + dp, nil) then
    begin
      Model.Accept;
      if Model.Iterations < 6 then dp := 1.5 * dp;
    end
    else
    begin
      dp := 0.5 * dp;
      if Abs(dp) < 1e-7 then raise Exception.Create('InflateToPressure : no convergence');
    end;
  end;
end;

procedure TLVHeart.InflateToVolume(V: Double; NSteps: Integer);
var
  v0, v1, dv: Double;
begin
  v1 := V * 1000;
  dv := (v1 - Model.CavityVolume) / NSteps;
  repeat
    v0 := Model.CavityVolume;
    if Abs(v1 - v0) < 1e-6 then Break;
    if Abs(dv) > Abs(v1 - v0) then dv := v1 - v0;
    FVFix := v0 + dv;
    if Model.Solve(0, 0, False, cmVolume, 0, VolFixed) then
    begin
      Model.Accept;
      if Model.Iterations < 6 then dv := 1.5 * dv;
    end
    else
    begin
      dv := 0.5 * dv;
      if Abs(dv) < 1e-3 then raise Exception.Create('InflateToVolume : no convergence');
    end;
  until False;
end;

function TLVHeart.Sample(t: Double): THeartSample;
begin
  Result.T := t;
  Result.PLV := Model.Pcav / mmHg;
  Result.VLV := Model.CavityVolume / 1000;
  Result.PLA := Circ.PLA(t);
  Result.VLA := Circ.S.VLA;
  Result.QMV := Circ.S.QMV; Result.QAV := Circ.S.QAV;
  Result.PRoot := Circ.S.PRoot; Result.QAo := Circ.S.QAo; Result.PWk := Circ.S.PWk;
  Result.ZMV := Circ.S.ZMV; Result.ZAV := Circ.S.ZAV;
  Result.Stretch := Model.MeanFibreStretch;
  Result.Tact := Model.MeanActiveStress;
  { rotation of the apical slice (a quarter of the way up) relative to
    the base, mean of endocardium and epicardium, from the unloaded
    shape; seen from the apex, + is anticlockwise }
  Result.Twist := -0.5 * (Model.RingRotation(0, JApex) + Model.RingRotation(Model.Geom.NR, JApex)
    - Model.RingRotation(0, Model.Geom.NL) - Model.RingRotation(Model.Geom.NR, Model.Geom.NL)) * 180 / Pi;
  Result.Thick := Model.WallThickness(JMid);
  Result.Radius := Model.EndoRadius(JMid);
  Result.LongAx := Model.LongAxis;
end;

function TLVHeart.TryStep(t0, dt: Double; Depth: Integer): Boolean;
begin
  FVn := Model.CavityVolume; FT := t0 + dt; FDt := dt;
  Result := Model.Solve(t0 + dt, dt, True, cmVolume, 0, VolTarget);
  if Result then
  begin
    Model.Accept;
    Circ.Commit(Model.Pcav / mmHg, t0 + dt, dt);
    Inc(Steps); Inc(NewtonIts, Model.Iterations);
  end
  else if Depth < 5 then
    Result := TryStep(t0, dt / 2, Depth + 1) and TryStep(t0 + dt / 2, dt / 2, Depth + 1);
end;

procedure TLVHeart.RunBeat(dt: Double; var S: THeartSamples);
var
  n, i: Integer;
  t: Double;
begin
  n := Round(Circ.Period / dt);
  dt := Circ.Period / n;
  SetLength(S, n + 1);
  S[0] := Sample(0);
  SetLength(FrameSample, 0); SetLength(FrameU, 0); SetLength(FrameL, 0); SetLength(FrameT, 0);
  for i := 1 to n do
  begin
    if (FrameEvery > 0) and ((i - 1) mod FrameEvery = 0) then Capture(i - 1);
    t := (i - 1) * dt;
    if not TryStep(t, dt, 0) then
      raise Exception.CreateFmt('RunBeat : no convergence at t = %.4f s', [t]);
    S[i] := Sample(i * dt);
  end;
end;

procedure TLVHeart.Capture(SampleIdx: Integer);
var
  f, i: Integer;
begin
  f := Length(FrameSample);
  SetLength(FrameSample, f + 1); SetLength(FrameU, f + 1);
  SetLength(FrameL, f + 1); SetLength(FrameT, f + 1);
  FrameSample[f] := SampleIdx;
  SetLength(FrameU[f], 3 * Model.NN);
  for i := 0 to 3 * Model.NN - 1 do FrameU[f][i] := Model.U[i];
  SetLength(FrameL[f], Model.NE); SetLength(FrameT[f], Model.NE);
  for i := 0 to Model.NE - 1 do
  begin
    FrameL[f][i] := Model.ElemStretch(i);
    FrameT[f][i] := Model.ElemActive(i);
  end;
end;

{ A text file, numbers separated by blanks:
    LVANIM 1
    NR NL NC  period_s  ls0_um
    NN lines        x y z of the unloaded mesh, mm (node order: uLVMech's NodeId)
    NS              then NS lines  t PLV VLV PLA PRoot QMV QAV ZMV ZAV
    NF              then per frame: its sample index; NN lines ux uy uz;
                    a line of NE fibre stretches; a line of NE active stresses
  Elements are numbered (i NL + j) NC + k: i through the wall from the
  endocardium, j from the apex, k round. }
procedure TLVHeart.WriteAnim(const FileName: string; const S: THeartSamples);
var
  f: TextFile;
  FS: TFormatSettings;
  i, k: Integer;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  AssignFile(f, FileName); Rewrite(f);
  Writeln(f, 'LVANIM 1');
  Writeln(f, Format('%d %d %d %.6f %.4f', [Model.Geom.NR, Model.Geom.NL, Model.Geom.NC,
    Circ.Period, Model.Mat.ls0], FS));
  for i := 0 to Model.NN - 1 do
    Writeln(f, Format('%.4f %.4f %.4f', [Model.X[3 * i], Model.X[3 * i + 1], Model.X[3 * i + 2]], FS));
  Writeln(f, Length(S));
  for i := 0 to High(S) do
    Writeln(f, Format('%.5f %.4f %.4f %.4f %.4f %.3f %.3f %.5f %.5f',
      [S[i].T, S[i].PLV, S[i].VLV, S[i].PLA, S[i].PRoot, S[i].QMV, S[i].QAV, S[i].ZMV, S[i].ZAV], FS));
  Writeln(f, Length(FrameSample));
  for k := 0 to High(FrameSample) do
  begin
    Writeln(f, FrameSample[k]);
    for i := 0 to Model.NN - 1 do
      Writeln(f, Format('%.4f %.4f %.4f', [FrameU[k][3 * i], FrameU[k][3 * i + 1], FrameU[k][3 * i + 2]], FS));
    for i := 0 to Model.NE - 1 do Write(f, Format('%.4f ', [FrameL[k][i]], FS));
    Writeln(f);
    for i := 0 to Model.NE - 1 do Write(f, Format('%.2f ', [FrameT[k][i]], FS));
    Writeln(f);
  end;
  CloseFile(f);
end;

function TLVHeart.Summarise(const S: THeartSamples): TBeatSummary;
var
  i, n, ied, ies: Integer;
  dt, d: Double;
begin
  n := High(S);
  dt := S[1].T - S[0].T;
  FillChar(Result, SizeOf(Result), 0);
  ied := 0; ies := 0;
  Result.AoDia := MaxDouble; Result.EjectStart := -1;
  for i := 0 to n do
  begin
    if S[i].VLV > S[ied].VLV then ied := i;
    if S[i].VLV < S[ies].VLV then ies := i;
    Result.PeakLV := Max(Result.PeakLV, S[i].PLV);
    Result.AoSys := Max(Result.AoSys, S[i].PRoot);
    Result.AoDia := Min(Result.AoDia, S[i].PRoot);
    Result.PeakFlow := Max(Result.PeakFlow, S[i].QAV);
    if i > 0 then
    begin
      Result.AoMean := Result.AoMean + S[i].PRoot / n;
      Result.PLAMean := Result.PLAMean + S[i].PLA / n;
      Result.CO := Result.CO + S[i].QAV * dt;
      d := (S[i].PLV - S[i - 1].PLV) / dt;
      Result.DPDtMax := Max(Result.DPDtMax, d);
      Result.DPDtMin := Min(Result.DPDtMin, d);
      if (S[i].QAV > 5) and (Result.EjectStart < 0) then Result.EjectStart := S[i].T;
      if S[i].QAV > 5 then Result.EjectEnd := S[i].T;
    end;
  end;
  { end diastole is the start of depolarisation, t = 0; end systole the
    smallest volume }
  ied := 0;
  Result.TwistED := S[0].Twist;
  Result.PeakTwist := -MaxDouble;
  for i := 0 to n do Result.PeakTwist := Max(Result.PeakTwist, S[i].Twist - S[0].Twist);
  Result.EDV := S[ied].VLV; Result.ESV := S[ies].VLV;
  Result.SV := Result.CO;                 { forward volume through the aortic valve }
  Result.CO := Result.SV * 60 / (n * dt) / 1000;
  Result.EF := (Result.EDV - Result.ESV) / Result.EDV;
  Result.EDP := S[0].PLV;
  Result.ThickED := S[ied].Thick; Result.ThickES := S[ies].Thick;
  Result.LongED := S[ied].LongAx; Result.LongES := S[ies].LongAx;
  Result.StretchED := S[ied].Stretch; Result.StretchES := S[ies].Stretch;
end;

end.
