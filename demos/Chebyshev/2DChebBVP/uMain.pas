unit uMain;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs,uCheb, Vcl.StdCtrls, SDL_plot3d,
  SDL_Rot3D, Vcl.ExtCtrls;

type
  Tfm2D = class(TForm)
    Plot3D1: TPlot3D;
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure Plot3D1DataRendered(Sender: TObject; Canvas: TCanvas);
  private
    { Private declarations }
    Laplace2D: T2DLaplace;
  public
    { Public declarations }
  end;

var
  fm2D: Tfm2D;

implementation

{$R *.dfm}
uses
  Math387,uBicubic;

procedure Tfm2D.FormCreate(Sender: TObject);
begin
  Inherited;
  Laplace2D:=T2DLaplace.create(24);
end;

procedure Tfm2D.FormShow(Sender: TObject);
const
  xres=41;
  yres=41;

var
  i,j : Integer;
begin
  fm2D.Caption:=' 2D Poisson u_xx+u_yy=10sin(8x(y-1)) u=0 on boundary.  Time to solve: '+FloatTostr(1000*Laplace2D.Solve)+' ms';
  Plot3D1.GridMat.Resize (XRes,YRes);
  for i := 1 to xres do
    for j:=1 to yres do
      Plot3D1.GridMat.Elem[i,j]:=Laplace2D.PlotGrid.Values[i-1,j-1];
    Plot3D1.SuppressPaint:=False;
    Plot3D1.Invalidate;
end;

procedure Tfm2D.Plot3D1DataRendered(Sender: TObject; Canvas: TCanvas);
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := clWhite;
  Canvas.TextOut(50,50,'Specified point has value:  '+floatToStr(Laplace2D.ResultGrid[18,18]));
end;


end.
