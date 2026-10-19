unit uburgersmain;

{*******************************************************************************

     Main form for the Burgers demo: shock formation in the inviscid
     Burgers equation u_t + u u_x = 0, solved by a finite-volume
     shock-capturing scheme (see uburgersmodel) and drawn as a waterfall
     on a TVMPlotStack, t = 0 at the front and each later time a step
     further back, as in demos/Benney and demos/KdV. The profile steepens
     until the breaking time t*, then carries a shock - a jump - that
     moves and, for the hump and N-wave, weakens as it eats into the
     profile.

     The scheme is explicit and fast (a few hundred steps of N cells), so
     Run computes every slice at once and then a timer adds them to the
     stack one at a time; Replay does the same again. "Exact solution"
     overlays the exact entropy solution (Hopf-Lax) as a white line on
     every fifth slice. The memo gives t*, mass and energy (conserved,
     and dissipated after t*, respectively) and the L1 error against the
     exact solution.

     --snapshot=<prefix>: run with the defaults, save the window as
     <prefix>.bmp, print the memo and exit (on Windows the GL area of the
     saved image is blank). --ic=<0..3>, --cells=<N>, --limiter=<0..2>.

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, Spin,
  newVM, uVMPlotStack, uburgersmodel;

type

  { TfmBurgers }

  TfmBurgers = class(TForm)
    btnRun: TButton;
    btnReplay: TButton;
    btnResetView: TButton;
    cbExact: TCheckBox;
    cbIC: TComboBox;
    cbLimiter: TComboBox;
    lblIC: TLabel;
    lblA: TLabel;
    lblCells: TLabel;
    lblLimiter: TLabel;
    lblTime: TLabel;
    lblSlices: TLabel;
    memInfo: TMemo;
    pnlControls: TPanel;
    pnlPlot: TPanel;
    seA: TFloatSpinEdit;
    seCells: TSpinEdit;
    seTime: TFloatSpinEdit;
    seSlices: TSpinEdit;
    tmrReplay: TTimer;
    procedure btnReplayClick(Sender: TObject);
    procedure btnResetViewClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure cbExactChange(Sender: TObject);
    procedure cbICChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure tmrReplayTimer(Sender: TObject);
  private
    FStack: TVMPlotStack;
    FModel: TBurgersModel;
    FProfiles: array of TDoubleArray;   // cell averages at each output time
    FTimes: array of Double;
    FReplayIndex: Integer;
    FRunMs: QWord;
    FSnapshot: string;
    function ToVM(const u: TDoubleArray): TVMobj;
    function ExactCells(t: Double): TDoubleArray;
    procedure SetupStack;
    procedure ShowProfile(i: Integer);
    procedure StartReplay;
    procedure WriteInfo;
    procedure DoSnapshot(Data: PtrInt);
  end;

var
  fmBurgers: TfmBurgers;

implementation

{$R *.lfm}

function Integral(const u: TDoubleArray; dx: Double): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(u) do Result := Result + u[i];
  Result := Result * dx;
end;

function Energy(const u: TDoubleArray; dx: Double): Double;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(u) do Result := Result + 0.5 * u[i] * u[i];
  Result := Result * dx;
end;

// FPC's Format has no '+' flag
function Signed(v: Double): string;
begin
  if v < 0 then Result := Format('-%.4g', [-v]) else Result := Format('+%.4g', [v]);
end;

{ TfmBurgers }

procedure TfmBurgers.FormCreate(Sender: TObject);
begin
  FStack := TVMPlotStack.Create(Self);
  FStack.Parent := pnlPlot;
  FStack.Align := alClient;
  FStack.Title := 'Inviscid Burgers equation - shock formation';
  FStack.XAxisTitle := 'x';
  FStack.YAxisTitle := 'u';
  FStack.ZAxisTitle := 'time';
  FStack.UseFrequencyAxis := True;    // label X in x, not cell index
  FStack.NewestAtBack := True;        // t = 0 in front (the default anyway)
  FStack.ClearStack;                  // drop the component's demo data

  if Application.GetOptionValue('ic') <> '' then
    cbIC.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('ic'), 0), 0, 3);
  cbICChange(nil);
  if Application.GetOptionValue('cells') <> '' then
    seCells.Value := StrToIntDef(Application.GetOptionValue('cells'), seCells.Value);
  if Application.GetOptionValue('limiter') <> '' then
    cbLimiter.ItemIndex := EnsureRange(StrToIntDef(Application.GetOptionValue('limiter'), 2), 0, 2);
  FSnapshot := Application.GetOptionValue('snapshot');
  Application.QueueAsyncCall(@DoSnapshot, 0);     // run on opening
end;

procedure TfmBurgers.FormDestroy(Sender: TObject);
begin
  FreeAndNil(FModel);
end;

procedure TfmBurgers.cbICChange(Sender: TObject);
begin
  // a run long enough to show the shock's life, scaled by the amplitude
  // (time scales as 1/a)
  seTime.Value := DefaultRunTime(TBurgersIC(cbIC.ItemIndex)) / Max(seA.Value, 0.05);
  if Sender <> nil then btnRunClick(nil);
end;

procedure TfmBurgers.SetupStack;
begin
  FStack.MaxSeries := seSlices.Value + 1;   // exactly the run
  FStack.ZAxisScale := seTime.Value / seSlices.Value;
  if Assigned(FModel) then
  begin
    FStack.XAxisMin := FModel.CellCentre(0);
    FStack.XAxisMax := FModel.CellCentre(FModel.Cells - 1);
  end;
end;

function TfmBurgers.ToVM(const u: TDoubleArray): TVMobj;
var
  i: Integer;
  P: PDouble;
begin
  Result := TVMobj.Create(Length(u), 1);
  P := Result.DataPtr;
  for i := 0 to High(u) do P[i] := u[i];
end;

function TfmBurgers.ExactCells(t: Double): TDoubleArray;
var
  i: Integer;
begin
  SetLength(Result, FModel.Cells);
  for i := 0 to FModel.Cells - 1 do
    Result[i] := FModel.ExactAt(FModel.CellCentre(i), t);
end;

procedure TfmBurgers.btnRunClick(Sender: TObject);
var
  u: TDoubleArray;
  k, n: Integer;
  t0: QWord;
begin
  tmrReplay.Enabled := False;
  FreeAndNil(FModel);
  FModel := TBurgersModel.Create(TBurgersIC(cbIC.ItemIndex), seA.Value,
    seCells.Value, TLimiter(cbLimiter.ItemIndex));
  n := seSlices.Value;
  SetLength(FProfiles, n + 1);
  SetLength(FTimes, n + 1);
  t0 := GetTickCount64;
  u := FModel.InitialCells;
  FProfiles[0] := Copy(u);
  FTimes[0] := 0;
  for k := 1 to n do
  begin
    FTimes[k] := seTime.Value * k / n;
    FModel.AdvanceTo(u, FTimes[k - 1], FTimes[k]);
    FProfiles[k] := Copy(u);
  end;
  FRunMs := GetTickCount64 - t0;
  btnReplay.Enabled := True;
  WriteInfo;
  StartReplay;
end;

procedure TfmBurgers.StartReplay;
begin
  FStack.ClearStack;
  SetupStack;
  FReplayIndex := 0;
  if FSnapshot <> '' then
  begin
    // no animation for a snapshot: everything at once
    while FReplayIndex <= High(FProfiles) do
    begin
      ShowProfile(FReplayIndex);
      Inc(FReplayIndex);
    end;
  end
  else
    tmrReplay.Enabled := True;
end;

procedure TfmBurgers.ShowProfile(i: Integer);
begin
  FStack.AddGraph(ToVM(FProfiles[i]));
  // the stack holds exactly the run, so slice i is stack index i
  if cbExact.Checked and (i mod 5 = 0) then
    FStack.SetSliceOverlay(i, ToVM(ExactCells(FTimes[i])));
end;

procedure TfmBurgers.tmrReplayTimer(Sender: TObject);
begin
  if FReplayIndex > High(FProfiles) then
  begin
    tmrReplay.Enabled := False;
    Exit;
  end;
  ShowProfile(FReplayIndex);
  Inc(FReplayIndex);
end;

procedure TfmBurgers.btnReplayClick(Sender: TObject);
begin
  if Length(FProfiles) > 0 then StartReplay;
end;

procedure TfmBurgers.cbExactChange(Sender: TObject);
begin
  if (Length(FProfiles) > 0) and not tmrReplay.Enabled then StartReplay;
end;

procedure TfmBurgers.btnResetViewClick(Sender: TObject);
begin
  FStack.ResetView;
end;

procedure TfmBurgers.WriteInfo;
var
  tb, xb, dx, l1, eEnd, eExact, x, v, jump, jumpN, xs, xsN: Double;
  i, n, last, ib: Integer;
  ue: TDoubleArray;
begin
  dx := FModel.Dx;
  n := FModel.Cells;
  last := High(FProfiles);
  tb := FModel.BreakingTime(xb);
  memInfo.Lines.BeginUpdate;
  try
    memInfo.Clear;
    memInfo.Lines.Add('Inviscid Burgers equation');
    memInfo.Lines.Add('');
    memInfo.Lines.Add('  u_t + u u_x = 0,  i.e. u_t + (u^2/2)_x = 0');
    memInfo.Lines.Add('');
    memInfo.Lines.Add(Format('u0 = %s, a = %.3g', [ICNames[TBurgersIC(cbIC.ItemIndex)], seA.Value]));
    memInfo.Lines.Add(Format('periodic on x = %.4g .. %.4g', [FModel.Xa, FModel.Xb]));
    memInfo.Lines.Add('');
    memInfo.Lines.Add('Each point moves at speed u, so the');
    memInfo.Lines.Add('profile steepens where u falls with x.');
    if IsInfinite(tb) then
      memInfo.Lines.Add('u0'' >= 0 everywhere: no shock forms')
    else
    begin
      memInfo.Lines.Add(Format('Breaking time t* = -1/min u0'' = %.4g,', [tb]));
      memInfo.Lines.Add(Format('  first shock at x = %.4g', [xb]));
      memInfo.Lines.Add('Shocks move at the mean of the values');
      memInfo.Lines.Add('either side (Rankine-Hugoniot).');
    end;
    memInfo.Lines.Add('');
    memInfo.Lines.Add(Format('Finite volumes: %d cells, dx = %.3g', [n, dx]));
    memInfo.Lines.Add('  exact Godunov flux, MUSCL slopes,');
    memInfo.Lines.Add('  limiter: ' + cbLimiter.Text);
    memInfo.Lines.Add(Format('  SSP-RK3, CFL %.2g', [CFL]));
    memInfo.Lines.Add(Format('Run to t = %.4g in %d slices:', [seTime.Value, seSlices.Value]));
    memInfo.Lines.Add(Format('  %d steps, %d ms', [FModel.Steps, FRunMs]));
    memInfo.Lines.Add('');

    // conservation and dissipation
    memInfo.Lines.Add(Format('Mass int u dx:  %.10f', [Integral(FProfiles[0], dx)]));
    memInfo.Lines.Add(Format('   at the end:  %.10f', [Integral(FProfiles[last], dx)]));
    eEnd := Energy(FProfiles[last], dx);
    ue := ExactCells(FTimes[last]);
    eExact := Energy(ue, dx);
    memInfo.Lines.Add(Format('Energy int u^2/2 dx: t = 0  %.5f', [Energy(FProfiles[0], dx)]));
    memInfo.Lines.Add(Format('  end %.5f, exact %.5f', [eEnd, eExact]));
    if not IsInfinite(tb) and (FTimes[last] > tb) then
      memInfo.Lines.Add('  (lost at the shock after t*)');
    memInfo.Lines.Add('');

    // error against the exact entropy solution; L1, since a captured
    // shock is a few cells wide and the pointwise error there is O(jump)
    l1 := 0;
    for i := 0 to n - 1 do l1 := l1 + Abs(FProfiles[last][i] - ue[i]);
    l1 := l1 * dx;
    memInfo.Lines.Add(Format('L1 error at the end: %.3g', [l1]));
    // the strongest shock: the largest drop between neighbouring cells,
    // numerical and exact
    jump := 0; jumpN := 0; xs := NaN; xsN := NaN; ib := -1;
    for i := 0 to n - 1 do
    begin
      x := ue[i] - ue[(i + 1) mod n];
      if x > jump then begin jump := x; xs := FModel.CellCentre(i) + dx / 2; end;
      v := FProfiles[last][i] - FProfiles[last][(i + 1) mod n];
      if v > jumpN then begin jumpN := v; xsN := FModel.CellCentre(i) + dx / 2; ib := i; end;
    end;
    // a shock on a cell face at x = 0 comes out as ~1e-16
    if Abs(xs) < 1e-9 then xs := 0;
    if Abs(xsN) < 1e-9 then xsN := 0;
    if (not IsInfinite(tb)) and (FTimes[last] > tb) then
    begin
      // the jump across the exact shock: the values a few cells away
      memInfo.Lines.Add(Format('Strongest shock at the end: x = %.4g', [xsN]));
      memInfo.Lines.Add(Format('  exact x = %.4g (%s cells)', [xs, Signed((xsN - xs) / dx)]));
      if ib >= 0 then
        memInfo.Lines.Add(Format('  jump from %.4g to %.4g', [ue[(ib - 2 + n) mod n], ue[(ib + 3) mod n]]));
    end;
    memInfo.Lines.Add('');
    memInfo.Lines.Add('t = 0 at the front, later times behind.');
    if cbExact.Checked then
      memInfo.Lines.Add('White: the exact solution, every 5th slice.');
    memInfo.Lines.Add('Drag to rotate, wheel to zoom.');
  finally
    memInfo.Lines.EndUpdate;
  end;
end;

procedure TfmBurgers.DoSnapshot(Data: PtrInt);
begin
  btnRunClick(nil);
  if FSnapshot = '' then Exit;
  Application.ProcessMessages;
  with GetFormImage do
  try
    SaveToFile(FSnapshot + '.bmp');
  finally
    Free;
  end;
  WriteLn(memInfo.Lines.Text);
  Application.Terminate;
end;

end.
