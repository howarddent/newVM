object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'Jet Ventilation Calculator '#169' Dr H Dent 2023'
  ClientHeight = 774
  ClientWidth = 1118
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  TextHeight = 15
  object Memo1: TMemo
    Left = 877
    Top = 270
    Width = 233
    Height = 482
    Lines.Strings = (
      '')
    TabOrder = 0
  end
  object Chart1: TChart
    Left = 24
    Top = 24
    Width = 833
    Height = 593
    BackWall.Color = clWhite
    BackWall.Dark3D = False
    BackWall.Size = 8
    BackWall.Transparent = False
    Border.Visible = True
    BottomWall.Dark3D = False
    BottomWall.Size = 8
    Foot.Font.Color = clBlue
    LeftWall.Color = clWhite
    LeftWall.Dark3D = False
    LeftWall.Size = 8
    Legend.Font.Height = -25
    Legend.Font.Name = 'Times New Roman'
    Legend.Frame.Visible = False
    Legend.LegendStyle = lsSeries
    Legend.Shadow.HorizSize = 0
    Legend.Shadow.Transparency = 0
    Legend.Shadow.VertSize = 0
    Legend.Symbol.Pen.Visible = False
    Legend.Transparent = True
    RightWall.Color = clWhite
    RightWall.Dark3D = False
    RightWall.Size = 8
    Title.Font.Color = clBlack
    Title.Font.Height = -31
    Title.Font.Name = 'Times New Roman'
    Title.Text.Strings = (
      'Flow vs Driving Pressure ')
    BottomAxis.Axis.Width = 1
    BottomAxis.Grid.Color = clBlack
    BottomAxis.Grid.Style = psDot
    BottomAxis.GridCentered = True
    BottomAxis.LabelsFormat.Font.Height = -21
    BottomAxis.LabelsFormat.Font.Name = 'Times New Roman'
    BottomAxis.MinorTicks.Visible = False
    BottomAxis.Ticks.Color = clBlack
    BottomAxis.TicksInner.Visible = False
    BottomAxis.Title.Caption = 'DP Bar'
    BottomAxis.Title.Font.Height = -28
    BottomAxis.Title.Font.Name = 'Times New Roman'
    DepthAxis.Axis.Width = 1
    DepthAxis.Grid.Color = clBlack
    DepthAxis.LabelsFormat.Font.Height = -13
    DepthAxis.LabelsFormat.Font.Name = 'Times New Roman'
    DepthAxis.MinorTicks.Visible = False
    DepthAxis.Ticks.Color = clBlack
    DepthAxis.TicksInner.Visible = False
    DepthAxis.Title.Font.Name = 'Times New Roman'
    DepthTopAxis.Axis.Width = 1
    DepthTopAxis.Grid.Color = clBlack
    DepthTopAxis.LabelsFormat.Font.Height = -13
    DepthTopAxis.LabelsFormat.Font.Name = 'Times New Roman'
    DepthTopAxis.MinorTicks.Visible = False
    DepthTopAxis.Ticks.Color = clBlack
    DepthTopAxis.TicksInner.Visible = False
    DepthTopAxis.Title.Font.Name = 'Times New Roman'
    LeftAxis.Axis.Width = 1
    LeftAxis.Grid.Color = clBlack
    LeftAxis.Grid.Style = psDot
    LeftAxis.LabelsFormat.Font.Height = -21
    LeftAxis.LabelsFormat.Font.Name = 'Times New Roman'
    LeftAxis.MinorTicks.Visible = False
    LeftAxis.Ticks.Color = clBlack
    LeftAxis.TicksInner.Visible = False
    LeftAxis.Title.Caption = 'Flow l/min'
    LeftAxis.Title.Font.Height = -28
    LeftAxis.Title.Font.Name = 'Times New Roman'
    RightAxis.Axis.Width = 1
    RightAxis.Grid.Color = clBlack
    RightAxis.LabelsFormat.Font.Height = -13
    RightAxis.LabelsFormat.Font.Name = 'Times New Roman'
    RightAxis.MinorTicks.Visible = False
    RightAxis.Ticks.Color = clBlack
    RightAxis.TicksInner.Visible = False
    RightAxis.Title.Font.Name = 'Times New Roman'
    TopAxis.Axis.Width = 1
    TopAxis.Grid.Color = clBlack
    TopAxis.LabelsFormat.Font.Height = -13
    TopAxis.LabelsFormat.Font.Name = 'Times New Roman'
    TopAxis.MinorTicks.Visible = False
    TopAxis.Ticks.Color = clBlack
    TopAxis.TicksInner.Visible = False
    TopAxis.Title.Font.Name = 'Times New Roman'
    View3D = False
    BevelOuter = bvNone
    Color = clWhite
    TabOrder = 1
    DefaultCanvas = 'TGDIPlusCanvas'
    PrintMargins = (
      15
      14
      15
      14)
    ColorPaletteIndex = -2
    ColorPalette = (
      16711680
      65280
      16776960
      255
      16711935
      65535
      8388608
      32768
      8421376
      128
      8388736
      32896)
  end
  object btnPlot: TButton
    Left = 24
    Top = 640
    Width = 113
    Height = 25
    Caption = 'Plot'
    TabOrder = 2
    OnClick = btnPlotClick
  end
  object Panel1: TPanel
    Left = 877
    Top = 24
    Width = 233
    Height = 233
    TabOrder = 3
    object Label1: TLabel
      Left = 24
      Top = 8
      Width = 56
      Height = 15
      Caption = 'Calculated'
    end
    object Label2: TLabel
      Left = 112
      Top = 8
      Width = 52
      Height = 15
      Caption = 'Measured'
    end
    object cbCookActual: TCheckBox
      Left = 112
      Top = 68
      Width = 49
      Height = 17
      TabOrder = 0
      OnClick = cbCookActualClick
    end
    object cb14Actual: TCheckBox
      Left = 112
      Top = 104
      Width = 49
      Height = 17
      TabOrder = 1
      OnClick = cb14ActualClick
    end
    object cb18Actual: TCheckBox
      Left = 112
      Top = 176
      Width = 49
      Height = 17
      TabOrder = 2
      OnClick = cb18ActualClick
    end
    object cbBiroActual: TCheckBox
      Left = 112
      Top = 32
      Width = 49
      Height = 17
      Checked = True
      State = cbChecked
      TabOrder = 3
      OnClick = cbBiroActualClick
    end
    object cb16Actual: TCheckBox
      Left = 112
      Top = 140
      Width = 49
      Height = 17
      TabOrder = 4
      OnClick = cb16ActualClick
    end
    object cb18Calc: TCheckBox
      Left = 25
      Top = 176
      Width = 56
      Height = 17
      Caption = '18#'
      TabOrder = 5
      OnClick = cb18CalcClick
    end
    object cb16Calc: TCheckBox
      Left = 25
      Top = 140
      Width = 56
      Height = 17
      Caption = '16#'
      TabOrder = 6
      OnClick = cb16CalcClick
    end
    object cb14Calc: TCheckBox
      Left = 25
      Top = 104
      Width = 56
      Height = 17
      Caption = '14#'
      TabOrder = 7
      OnClick = cb14CalcClick
    end
    object cbCookCalc: TCheckBox
      Left = 25
      Top = 68
      Width = 56
      Height = 17
      Caption = 'Cook'
      TabOrder = 8
      OnClick = cbCookCalcClick
    end
    object cbBiroCalc: TCheckBox
      Left = 25
      Top = 32
      Width = 56
      Height = 17
      Caption = 'Biro'
      Checked = True
      State = cbChecked
      TabOrder = 9
      OnClick = cbBiroCalcClick
    end
    object cbLindholm: TCheckBox
      Left = 24
      Top = 208
      Width = 73
      Height = 17
      Caption = 'Lindholm'
      TabOrder = 10
      OnClick = cbLindholmClick
    end
    object cbLindholmActual: TCheckBox
      Left = 112
      Top = 208
      Width = 97
      Height = 17
      Enabled = False
      TabOrder = 11
      OnClick = cbLindholmActualClick
    end
  end
  object rgPlotOption: TRadioGroup
    Left = 24
    Top = 687
    Width = 833
    Height = 65
    Caption = 'Plot option'
    Columns = 5
    ItemIndex = 0
    Items.Strings = (
      'Flow'
      'Velocity'
      'Entrainment Flow'
      'Entrainment Ratio'
      'Mach Number'
      'Stall Pressure 2.2cm'
      'Stall Pressure 1.5cm'
      'Mass Flow')
    TabOrder = 4
    OnClick = rgPlotOptionClick
  end
  object btnExport: TButton
    Left = 782
    Top = 640
    Width = 75
    Height = 25
    Caption = 'Export'
    TabOrder = 5
    OnClick = btnExportClick
  end
  object btnCursor: TButton
    Left = 664
    Top = 640
    Width = 75
    Height = 25
    Caption = 'Cursor On'
    TabOrder = 6
    OnClick = btnCursorClick
  end
  object SaveDialog1: TSaveDialog
    DefaultExt = 'svg'
    Filter = 'svg'
    InitialDir = 'C:\tempCharts;'
    Left = 896
    Top = 32
  end
end
