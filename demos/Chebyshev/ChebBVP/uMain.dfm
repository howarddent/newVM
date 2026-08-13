object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'fmMain'
  ClientHeight = 738
  ClientWidth = 1046
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object PageControl1: TPageControl
    Left = 0
    Top = 0
    Width = 1046
    Height = 738
    ActivePage = TabSheet1
    Align = alClient
    TabOrder = 0
    object TabSheet1: TTabSheet
      Caption = 'Graphics'
      ExplicitLeft = 0
      ExplicitTop = 0
      ExplicitWidth = 0
      ExplicitHeight = 0
      object Button1: TButton
        Left = 32
        Top = 668
        Width = 75
        Height = 25
        Caption = 'Execute'
        TabOrder = 0
        OnClick = Button1Click
      end
      object Chart1: TChart
        Left = 32
        Top = 40
        Width = 945
        Height = 598
        Legend.Visible = False
        Title.Text.Strings = (
          'TChart')
        BottomAxis.Automatic = False
        BottomAxis.AutomaticMaximum = False
        BottomAxis.AutomaticMinimum = False
        BottomAxis.ExactDateTime = False
        BottomAxis.Increment = 0.200000000000000000
        BottomAxis.LabelsSeparation = 0
        BottomAxis.Maximum = 1.000000000000000000
        BottomAxis.Minimum = -1.000000000000000000
        LeftAxis.Automatic = False
        LeftAxis.AutomaticMaximum = False
        LeftAxis.AutomaticMinimum = False
        LeftAxis.Increment = 0.500000000000000000
        LeftAxis.LabelsSeparation = 0
        LeftAxis.Maximum = 0.500000000000000000
        LeftAxis.Minimum = -2.500000000000000000
        Panning.MouseWheel = pmwNone
        View3D = False
        TabOrder = 1
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = 13
        object Series1: TPointSeries
          ClickableLine = False
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series2: TLineSeries
          Brush.BackColor = clDefault
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loNone
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
      end
    end
    object TabSheet2: TTabSheet
      Caption = 'Matrices'
      ImageIndex = 1
      ExplicitLeft = 0
      ExplicitTop = 0
      ExplicitWidth = 0
      ExplicitHeight = 0
      object StringGrid1: TStringGrid
        Left = 24
        Top = 20
        Width = 753
        Height = 317
        TabOrder = 0
      end
      object StringGrid2: TStringGrid
        Left = 24
        Top = 356
        Width = 753
        Height = 313
        TabOrder = 1
      end
      object Memo1: TMemo
        Left = 816
        Top = 20
        Width = 201
        Height = 657
        Lines.Strings = (
          '')
        TabOrder = 2
      end
    end
  end
end
