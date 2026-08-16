unit u2DBVPMain;

{*******************************************************************************

     Main form for the 2DChebBVP demo - ported from the Delphi/MtxVec
     original at demos/Chebyshev/2DChebBVP/{uMain,uCheb,Bary2D}.pas. Solves
     the 2D Poisson equation u_xx+u_yy = 10*sin(8*x*(y-1)), u=0 on the
     boundary of [-1,1]x[-1,1], by Chebyshev collocation on an N=24 grid
     (matching the original's Laplace2D.create(24)):

       - TCheb (reused as-is from ../NormalIntegration/uCheb.pas, not
         copied - see 2DChebBVP.lpi's OtherUnitFiles) builds the (N+1)x(N+1)
         Chebyshev grid/second-derivative matrix D2, exactly as ChebBVP_FPC
         already does for the 1D case. uCheb.pas is the one shared unit for
         all Chebyshev-specific code in this demo tree, 1D and 2D alike -
         TCheb, BaryLag1D (1D barycentric interpolation, used by ChebBVP_FPC)
         and BaryLag2D (below) all live there together.
       - The interior (N-1)x(N-1) block of D2 (D2R, via newVM's SubMatrix -
         the boundary values are already known to be zero) is the 1D
         second-derivative operator; applied to the (N-1)x(N-1) interior
         solution grid U, the full 2D Laplacian is D2R*U + U*D2R' (second
         derivative in x via left-multiplication, in y via
         right-multiplication-by-transpose). Vectorised via the standard
         Kronecker identity vec(D2R*U + U*D2R') =
         [(I(kron)D2R)+(D2R(kron)I)]*vec(U) - newVM's Kron plus '+' assemble
         the (N-1)^2 x (N-1)^2 system exactly as the original's kronX+kronY
         did. newVM's Reshape (a pure reinterpret of the row-major buffer,
         no data movement) stands in directly for vec()/unvec() here: unlike
         the original's GridToVec/VecToGrid (which flatten column-major,
         the natural convention for the *standard* column-major vec
         identity), the identity above holds *identically* for newVM's
         native row-major storage too - summing both Kronecker terms
         together makes the identity insensitive to which flattening
         convention is used (transposing U swaps which term is which, but
         the sum of the two is unchanged), so no bespoke column-major
         GridToVec/VecToGrid helpers are needed.
       - LinearSolve solves the resulting (N-1)^2 x (N-1)^2 system against
         the RHS 10*sin(8*x_i*(x_j-1)) sampled directly on the interior
         grid, and the interior solution is zero-padded back up to the full
         (N+1)x(N+1) grid (TVMobj.Create already zero-fills, matching
         ChebBVP_FPC's own zero-pad).
       - uCheb.BaryLag2D (ported from the original's Bary2D.pas, see that
         function's own header comment in uCheb.pas) interpolates the
         (N+1)x(N+1) solution grid - sampled at the *full* Chebyshev node
         set FCheb.X, boundary values included, same as the original's
         ResultGrid/Cheb1D.x - onto a finer DispN x DispN display grid,
         which TVMPlot3D (Graphs/uVMPlot3D.pas) then renders as a lit
         height-field surface, same as this repo's own Graphs/Plot3D demo -
         including that demo's TVMLightPad (Graphs/uVMLightPad.pas), a small
         circular control the user drags within to steer the surface's
         OpenGL headlamp direction; wired up identically here (FLightPad,
         LightPadChange), see uplot3dmain.pas's own header comment for the
         pattern.

     DispN=65 (a power-of-2-plus-one, not the original's mismatched 50/200)
     is deliberately chosen so linspace's offset+i*slope construction lands
     the display grid's own midpoint on *exactly* 0.0 in floating point
     (2/64=0.03125 and 32*0.03125=1.0 are both exact in binary) - this
     doesn't, on its own, guarantee an exact bit-for-bit coincidence with
     any particular Chebyshev node (cos() of a finite-precision Pi/2
     approximation isn't bit-exact 0 either), so BaryLag2D's
     exact-coincidence path is not expected to fire in an ordinary run of
     this demo; it exists, and was verified separately via a scratch test
     with deliberately-coincident grids, for correctness whenever a
     caller's grids genuinely do coincide (e.g. interpolating back onto the
     source's own nodes).

*******************************************************************************}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  newVM, uVMPlot3D, uVMLightPad, uCheb, hirestimer;

const
  ChebN = 24;   // matches the original Laplace2D.create(24)
  DispN = 65;   // display grid resolution (both axes), -1..1 - see header

type

  { TfmMain }

  TfmMain = class(TForm)
    ControlPanel: TPanel;
    WireframeCheckBox: TCheckBox;
    ShowAxesCheckBox: TCheckBox;
    LevelCurvesCheckBox: TCheckBox;
    ResetViewButton: TButton;
    Memo1: TMemo;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure ResetViewButtonClick(Sender: TObject);
    procedure WireframeCheckBoxChange(Sender: TObject);
    procedure ShowAxesCheckBoxChange(Sender: TObject);
    procedure LevelCurvesCheckBoxChange(Sender: TObject);
  private
    FCheb: TCheb;
    FPlot: TVMPlot3D;
    FLightPad: TVMLightPad;
    procedure LightPadChange(Sender: TObject);
  end;

var
  fmMain: TfmMain;

implementation

{$R *.lfm}

{ TfmMain }

procedure TfmMain.FormCreate(Sender: TObject);
var
  Nint: Integer;
  D2R, Ident, Laplace, LaplaceScratch, Xi, FRhs, f, v, U, UFull, XF, YF, PlotGrid: TVMobj;
  I, J: Integer;
  ElapsedUs: Int64;
  LightLabel: TLabel;
begin
  Profiler.Start;
  FCheb := TCheb.Create(ChebN);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time to create TCheb object: ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  Nint := ChebN - 1;

  // Dirichlet boundary u=0 on the whole edge is already known, so only the
  // (N-1)x(N-1) interior grid is unknown - drop D2's first/last row and
  // column, same reasoning as ChebBVP_FPC's 1D SubMatrix(FCheb.D2,...).
  D2R := SubMatrix(FCheb.D2, 1, 1, Nint, Nint);
  Xi := SubMatrix(FCheb.X, 1, 0, Nint, 1);

  Ident := TVMobj.Create(Nint, Nint);
  Ident.Id;
  Laplace := Kron(Ident, D2R) + Kron(D2R, Ident);

  FRhs := TVMobj.Create(Nint, Nint);
  for I := 0 to Nint - 1 do
    for J := 0 to Nint - 1 do
      FRhs.Element[I, J] := 10 * Sin(8 * Xi.Element[I, 0] * (Xi.Element[J, 0] - 1));
  f := Reshape(FRhs, Nint * Nint, 1);

  Profiler.Start;
  LaplaceScratch := CopyObj(Laplace);
  v := CopyObj(f);
  LinearSolve(LaplaceScratch, v);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time for direct solve (' + IntToStr(Nint) + 'x' + IntToStr(Nint) +
    ' interior grid, ' + IntToStr(Nint * Nint) + 'x' + IntToStr(Nint * Nint) +
    ' system): ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  U := Reshape(v, Nint, Nint);

  // Zero-pad the interior solution back up to the full (N+1)x(N+1) grid -
  // TVMobj.Create already zero-fills, so the boundary ring needs no
  // explicit assignment.
  UFull := TVMobj.Create(ChebN + 1, ChebN + 1);
  for I := 0 to Nint - 1 do
    for J := 0 to Nint - 1 do
      UFull.Element[I + 1, J + 1] := U.Element[I, J];

  XF := TVMobj.Create(1, DispN);
  XF.linspace(-1, 2 / (DispN - 1));
  YF := CopyObj(XF);

  Profiler.Start;
  PlotGrid := BaryLag2D(UFull, FCheb.X, FCheb.X, XF, YF);
  ElapsedUs := Profiler.Stop;
  Memo1.Lines.Add('Time for 2D barycentric interpolation (' + IntToStr(DispN) +
    'x' + IntToStr(DispN) + '): ' + FloatToStr(ElapsedUs / 1000) + ' ms');

  FPlot := TVMPlot3D.Create(Self);
  FPlot.Parent := Self;
  FPlot.Align := alClient;
  FPlot.Title := '2D Poisson: u_xx+u_yy = 10 sin(8x(y-1)), u=0 on boundary';
  FPlot.XAxisTitle := 'x';
  FPlot.YAxisTitle := 'y';
  FPlot.ZAxisTitle := 'u';
  // Label the X/Y axes with the actual solution-domain coordinate (PlotGrid
  // is sampled over XF/YF, both exactly [-1,1] - see their construction
  // above) rather than TVMPlot3D's default column/row index.
  FPlot.XAxisMin := -1;
  FPlot.XAxisMax := 1;
  FPlot.YAxisMin := -1;
  FPlot.YAxisMax := 1;
  FPlot.SetData(PlotGrid);

  // Grow the control bar to fit the light pad below the existing checkbox/
  // button row, then create+position the pad itself - same code-only
  // approach (no .lfm changes) as Graphs/Plot3D/uplot3dmain.pas's own
  // FormCreate, see this unit's header comment.
  ControlPanel.Height := 120;
  LightLabel := TLabel.Create(Self);
  LightLabel.Parent := ControlPanel;
  LightLabel.Left := 750;
  LightLabel.Top := 4;
  LightLabel.Caption := 'Light (drag)';
  FLightPad := TVMLightPad.Create(Self);
  FLightPad.Parent := ControlPanel;
  FLightPad.Left := 750;
  FLightPad.Top := 20;
  FLightPad.OnChange := @LightPadChange;
  FPlot.LightX := FLightPad.LightX;
  FPlot.LightY := FLightPad.LightY;

  // ChebN div 4 lands exactly on the Chebyshev node x=cos((ChebN div 4)*Pi/ChebN)
  // = cos(Pi/4) = 1/sqrt(2) (the same node index arithmetic the header comment's
  // "(0,0)" case used with ChebN div 2 -> cos(Pi/2) = 0) - this is the original
  // Delphi demo's own evaluation point (Laplace2D.ResultGrid[18,18] there, whose
  // reversed node ordering - x[I]:=-cos(I*Pi/N) there vs cos(I*Pi/N) here - put
  // the same node at index N-6=18 rather than index 6).
  Memo1.Lines.Add('');
  Memo1.Lines.Add('u at (x,y)~=(1/sqrt(2),1/sqrt(2)): ' +
    FloatToStr(UFull.Element[ChebN div 4, ChebN div 4]));
end;

procedure TfmMain.LightPadChange(Sender: TObject);
begin
  FPlot.LightX := FLightPad.LightX;
  FPlot.LightY := FLightPad.LightY;
end;

procedure TfmMain.FormDestroy(Sender: TObject);
begin
  FCheb.Free;
end;

procedure TfmMain.ResetViewButtonClick(Sender: TObject);
begin
  FPlot.ResetView;
end;

procedure TfmMain.WireframeCheckBoxChange(Sender: TObject);
begin
  FPlot.Wireframe := WireframeCheckBox.Checked;
end;

procedure TfmMain.ShowAxesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowAxes := ShowAxesCheckBox.Checked;
end;

procedure TfmMain.LevelCurvesCheckBoxChange(Sender: TObject);
begin
  FPlot.ShowLevelCurves := LevelCurvesCheckBox.Checked;
end;

end.
