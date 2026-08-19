object fmMain: TfmMain
  Left = 0
  Top = 0
  Caption = 'Propofol And Refentanil Model '#169' Dr H Dent July 2022 '
  ClientHeight = 844
  ClientWidth = 1440
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Menu = MainMenu1
  Position = poDesigned
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object PageControl1: TPageControl
    Left = 0
    Top = 0
    Width = 1440
    Height = 844
    ActivePage = TabSheet3
    Align = alClient
    TabOrder = 0
    ExplicitWidth = 1430
    ExplicitHeight = 812
    object TabSheet1: TTabSheet
      Caption = 'Single Bolus'
      object Chart1: TChart
        Left = 28
        Top = 18
        Width = 781
        Height = 495
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
        Legend.Font.Height = -13
        Legend.Font.Name = 'Times New Roman'
        Legend.Frame.Visible = False
        Legend.Shadow.HorizSize = 0
        Legend.Shadow.Transparency = 0
        Legend.Shadow.VertSize = 0
        Legend.Symbol.Pen.Visible = False
        Legend.Transparent = True
        RightWall.Color = clWhite
        RightWall.Dark3D = False
        RightWall.Size = 8
        SubFoot.Font.Color = clBlack
        SubTitle.Font.Color = clBlack
        Title.Font.Color = clBlack
        Title.Font.Height = -16
        Title.Font.Name = 'Times New Roman'
        Title.Text.Strings = (
          
            'Marsh ABW 100kg Plasma target 3mcg / ml + 100mg Bolus through El' +
            'eveld 160kg 1.75 35y Male')
        BottomAxis.Axis.Width = 1
        BottomAxis.Grid.Color = clBlack
        BottomAxis.Grid.Visible = False
        BottomAxis.GridCentered = True
        BottomAxis.LabelsFormat.Font.Height = -13
        BottomAxis.LabelsFormat.Font.Name = 'Times New Roman'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = clBlack
        BottomAxis.TicksInner.Visible = False
        BottomAxis.Title.Caption = 'Time - Minutes'
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
        LeftAxis.Automatic = False
        LeftAxis.AutomaticMinimum = False
        LeftAxis.Axis.Width = 1
        LeftAxis.Grid.Color = clBlack
        LeftAxis.Grid.Visible = False
        LeftAxis.LabelsFormat.Font.Height = -13
        LeftAxis.LabelsFormat.Font.Name = 'Times New Roman'
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = clBlack
        LeftAxis.TicksInner.Visible = False
        LeftAxis.Title.Caption = 'Propfol conc mcg/ml'
        LeftAxis.Title.Font.Name = 'Times New Roman'
        RightAxis.Automatic = False
        RightAxis.AutomaticMaximum = False
        RightAxis.AutomaticMinimum = False
        RightAxis.Axis.Width = 1
        RightAxis.Grid.Color = clBlack
        RightAxis.Grid.Visible = False
        RightAxis.LabelsFormat.Font.Height = -13
        RightAxis.LabelsFormat.Font.Name = 'Times New Roman'
        RightAxis.Maximum = 100.000000000000000000
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
        TabOrder = 0
        DefaultCanvas = 'TGDIPlusCanvas'
        PrintMargins = (
          15
          9
          15
          9)
        ColorPaletteIndex = 0
        object Button3: TButton
          Left = 696
          Top = 456
          Width = 75
          Height = 25
          Caption = 'Export '
          TabOrder = 0
          OnClick = Button3Click
        end
        object Series1: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Plasma'
          LinePen.Color = clBlue
          LinePen.Width = 3
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series2: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          SeriesColor = clYellow
          Title = 'C2'
          LinePen.Color = clYellow
          LinePen.Width = 3
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series3: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'C3'
          LinePen.Color = clTeal
          LinePen.Width = 3
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series4: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Effect'
          LinePen.Color = clRed
          LinePen.Width = 3
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series5: TPointSeries
          Active = False
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'N_Central'
          ClickableLine = False
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series6: TPointSeries
          Active = False
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'N_C2'
          ClickableLine = False
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series7: TPointSeries
          Active = False
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'N_C3'
          ClickableLine = False
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series8: TPointSeries
          Active = False
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'N_eff'
          ClickableLine = False
          Pointer.InflateMargins = True
          Pointer.Style = psRectangle
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series12: TMtxFastLineSeries
          Title = 'BIS'
          VertAxis = aRightAxis
          LinePen.Color = clMaroon
          LinePen.Width = 3
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object ChartTool1: TColorLineTool
          AnnotationValue = True
          Pen.EndStyle = esRound
          Style = clMinimum
          Value = 1.000000000000000000
          AxisID = 2
          object TAnnotationTool
            Shape.Alignment = taCenter
            Shape.CustomPosition = True
            Shape.Left = 341
            Shape.Shadow.Visible = False
            Shape.Text = '0'
            Shape.Top = 410
          end
        end
        object ChartTool2: TColorLineTool
          AnnotationValue = True
          Pen.EndStyle = esRound
          Style = clMinimum
          AxisID = 0
          object TAnnotationTool
            Shape.Alignment = taCenter
            Shape.CustomPosition = True
            Shape.Left = 74
            Shape.Shadow.Visible = False
            Shape.Text = '0'
            Shape.Top = 220
          end
        end
        object ChartTool3: TColorBandTool
          Brush.Color = 65408
          Color = 8454016
          DrawBehind = False
          EndValue = 60.000000000000000000
          Pen.Style = psDash
          Pen.Visible = False
          StartValue = 40.000000000000000000
          Transparency = 80
          EndLinePen.Color = 721420288
          EndLinePen.EndStyle = esRound
          StartLinePen.EndStyle = esRound
          AxisID = 3
          object TColorLineTool
            DragRepaint = True
            Pen.EndStyle = esRound
            Value = 40.000000000000000000
            AxisID = 3
            object TAnnotationTool
              Shape.Alignment = taCenter
              Shape.Shadow.Visible = False
            end
          end
          object TColorLineTool
            DragRepaint = True
            Pen.Color = 721420288
            Pen.EndStyle = esRound
            Value = 60.000000000000000000
            AxisID = 3
            object TAnnotationTool
              Shape.Alignment = taCenter
              Shape.Shadow.Visible = False
            end
          end
        end
        object ChartTool4: TAnnotationTool
          Active = False
          Position = ppCenter
          Shape.Text = 'Bolus =13.1 mls'#13'Ke0=0.26'#13'TTPE=3.9'
          Shape.Visible = False
        end
      end
      object Panel1: TPanel
        Left = 1189
        Top = 0
        Width = 235
        Height = 801
        Align = alRight
        TabOrder = 1
        object GroupBox1: TGroupBox
          Left = 8
          Top = 18
          Width = 217
          Height = 154
          Caption = 'Drug'
          TabOrder = 0
          object TLabel
            Left = 24
            Top = 91
            Width = 26
            Height = 15
            Caption = 'Dose'
          end
          object Label1: TLabel
            Left = 151
            Top = 91
            Width = 36
            Height = 15
            Caption = 'mg/kg'
          end
          object cbDrugs: TComboBox
            Left = 32
            Top = 40
            Width = 145
            Height = 23
            TabOrder = 0
            Text = 'Propofol'
            OnChange = cbDrugsChange
            Items.Strings = (
              'Propofol'
              'Fentanyl'
              'Alfentanil'
              'Remifentanil'
              'Thiopentone'
              'Midazolam')
          end
          object MtxFloatEdit1: TMtxFloatEdit
            Left = 55
            Top = 88
            Width = 90
            Height = 24
            RegistryPath = '\Software\Dew Research\MtxVec'
            StoreInRegistry = False
            IntegerIncrement = False
            Scientific = False
            ReFormat = '0.00#;-0.00#'
            ImFormat = '+0.00#i;-0.00#i'
            Increment = '0.1'
            MaxValue = '0'
            MinValue = '0'
            TabOrder = 1
            Value = '3.00'
          end
        end
        object TreeView1: TTreeView
          Left = 0
          Top = 240
          Width = 217
          Height = 233
          Indent = 19
          ReadOnly = True
          TabOrder = 1
          OnChange = TreeView1Change
          Items.NodeData = {
            070100000009540054007200650065004E006F00640065002900000000000000
            00000000FFFFFFFFFFFFFFFF0000000000000000000200000001054400720075
            006700730000002D0000000000000000000000FFFFFFFFFFFFFFFF0000000000
            000000000300000001074F00700069006F0069006400730000002F0000000000
            000000000000FFFFFFFFFFFFFFFF000000000000000000000000000108460065
            006E00740061006E0079006C000000330000000000000000000000FFFFFFFFFF
            FFFFFF00000000000000000000000000010A41006C00660065006E0074006100
            6E0069006C000000370000000000000000000000FFFFFFFFFFFFFFFF00000000
            000000000000000000010C520065006D006900660065006E00740061006E0069
            006C000000310000000000000000000000FFFFFFFFFFFFFFFF00000000000000
            00000300000001094800790070006E006F00740069006300730000002F000000
            0000000000000000FFFFFFFFFFFFFFFF00000000000000000001000000010850
            0072006F0070006F0066006F006C0000002B0000000000000000000000FFFFFF
            FFFFFFFFFF0000000000000000000400000001064D006F00640065006C007300
            0000290000000000000000000000FFFFFFFFFFFFFFFF00000000000000000000
            00000001054D0061007200730068000000310000000000000000000000FFFFFF
            FFFFFFFFFF0000000000000000000000000001095300630068006E0065006900
            6400650072000000310000000000000000000000FFFFFFFFFFFFFFFF00000000
            000000000000000000010950006100650064006600750073006F00720000002D
            0000000000000000000000FFFFFFFFFFFFFFFF00000000000000000000000000
            010745006C006500760065006C0064000000350000000000000000000000FFFF
            FFFFFFFFFFFF00000000000000000001000000010B5400680069006F00700065
            006E0074006F006E00650000002B0000000000000000000000FFFFFFFFFFFFFF
            FF0000000000000000000100000001064D006F00640065006C00730000001F00
            00000000000000000000FFFFFFFFFFFFFFFF0000000000000000000000000001
            000000310000000000000000000000FFFFFFFFFFFFFFFF000000000000000000
            0100000001094D006900640061007A006F006C0061006D0000002B0000000000
            000000000000FFFFFFFFFFFFFFFF0000000000000000000000000001064D006F
            00640065006C007300}
        end
        object Memo2: TMemo
          Left = 16
          Top = 479
          Width = 193
          Height = 210
          Lines.Strings = (
            '')
          TabOrder = 2
        end
      end
    end
    object TTabSheet
      Caption = 'Bristol Schemes'
      ImageIndex = 1
    end
    object TabSheet2: TTabSheet
      Caption = 'BTE Schemes'
      ImageIndex = 2
      object Chart3: TChart
        Left = 48
        Top = 24
        Width = 745
        Height = 353
        BackWall.Brush.Gradient.Direction = gdBottomTop
        BackWall.Brush.Gradient.EndColor = 7895160
        BackWall.Brush.Gradient.StartColor = 4605510
        BackWall.Brush.Gradient.Visible = True
        BackWall.Pen.Visible = False
        BackWall.Transparent = False
        Foot.Font.Color = clWhite
        Foot.Font.Name = 'Verdana'
        Gradient.Direction = gdBottomTop
        Gradient.EndColor = 4605510
        Gradient.StartColor = 4605510
        Gradient.Visible = True
        LeftWall.Color = clLightyellow
        Legend.Brush.Gradient.Direction = gdBottomTop
        Legend.Brush.Gradient.EndColor = 7895160
        Legend.Brush.Gradient.StartColor = 4605510
        Legend.Brush.Gradient.Visible = True
        Legend.Font.Color = clWhite
        Legend.Font.Name = 'Verdana'
        Legend.Frame.Visible = False
        Legend.LegendStyle = lsSeries
        Legend.Shadow.HorizSize = 0
        Legend.Shadow.Transparency = 0
        Legend.Title.Text.Strings = (
          'Plasma Propofoll Concentration')
        RightWall.Color = clLightyellow
        Title.Font.Color = clWhite
        Title.Font.Name = 'Verdana'
        Title.Text.Strings = (
          'BET Scheme for plasma target 3mcg/ml')
        BottomAxis.Axis.Color = 4210752
        BottomAxis.Grid.Color = clDarkgray
        BottomAxis.LabelsFormat.Font.Color = clWhite
        BottomAxis.LabelsFormat.Font.Name = 'Verdana'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = 8553090
        BottomAxis.TicksInner.Color = clDarkgray
        BottomAxis.Title.Font.Color = clWhite
        BottomAxis.Title.Font.Name = 'Verdana'
        DepthAxis.Axis.Color = 4210752
        DepthAxis.Grid.Color = clDarkgray
        DepthAxis.LabelsFormat.Font.Color = clWhite
        DepthAxis.LabelsFormat.Font.Name = 'Verdana'
        DepthAxis.MinorTicks.Visible = False
        DepthAxis.Ticks.Color = 8553090
        DepthAxis.TicksInner.Color = clDarkgray
        DepthAxis.Title.Font.Color = clWhite
        DepthAxis.Title.Font.Name = 'Verdana'
        DepthTopAxis.Axis.Color = 4210752
        DepthTopAxis.Grid.Color = clDarkgray
        DepthTopAxis.LabelsFormat.Font.Color = clWhite
        DepthTopAxis.LabelsFormat.Font.Name = 'Verdana'
        DepthTopAxis.MinorTicks.Visible = False
        DepthTopAxis.Ticks.Color = 8553090
        DepthTopAxis.TicksInner.Color = clDarkgray
        DepthTopAxis.Title.Font.Color = clWhite
        DepthTopAxis.Title.Font.Name = 'Verdana'
        Frame.Visible = False
        LeftAxis.Axis.Color = 4210752
        LeftAxis.Grid.Color = clDarkgray
        LeftAxis.LabelsFormat.Font.Color = clWhite
        LeftAxis.LabelsFormat.Font.Name = 'Verdana'
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = 8553090
        LeftAxis.TicksInner.Color = clDarkgray
        LeftAxis.Title.Font.Color = clWhite
        LeftAxis.Title.Font.Name = 'Verdana'
        RightAxis.Axis.Color = 4210752
        RightAxis.Grid.Color = clDarkgray
        RightAxis.LabelsFormat.Font.Color = clWhite
        RightAxis.LabelsFormat.Font.Name = 'Verdana'
        RightAxis.MinorTicks.Visible = False
        RightAxis.Ticks.Color = 8553090
        RightAxis.TicksInner.Color = clDarkgray
        RightAxis.Title.Font.Color = clWhite
        RightAxis.Title.Font.Name = 'Verdana'
        TopAxis.Axis.Color = 4210752
        TopAxis.Grid.Color = clDarkgray
        TopAxis.LabelsFormat.Font.Color = clWhite
        TopAxis.LabelsFormat.Font.Name = 'Verdana'
        TopAxis.MinorTicks.Visible = False
        TopAxis.Ticks.Color = 8553090
        TopAxis.TicksInner.Color = clDarkgray
        TopAxis.Title.Font.Color = clWhite
        TopAxis.Title.Font.Name = 'Verdana'
        View3D = False
        TabOrder = 0
        DefaultCanvas = 'TGLCanvas'
        ColorPaletteIndex = -2
        ColorPalette = (
          5957320
          14456410
          2644710
          1024230)
        object Series9: TMtxFastLineSeries
          Marks.Font.Color = clWhite
          Marks.Transparent = True
          SeriesColor = clRed
          Title = 'Plasma '
          LinePen.Color = clRed
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series14: TMtxFastLineSeries
          Marks.Font.Color = clWhite
          Marks.Transparent = True
          SeriesColor = clBlue
          Title = 'C2'
          LinePen.Color = clBlue
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series15: TMtxFastLineSeries
          Marks.Font.Color = clWhite
          Marks.Transparent = True
          SeriesColor = clYellow
          Title = 'C3'
          LinePen.Color = clYellow
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series16: TMtxFastLineSeries
          Marks.Font.Color = clWhite
          Marks.Transparent = True
          SeriesColor = clLime
          Title = 'Ceff'
          LinePen.Color = clLime
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
      end
      object Button1: TButton
        Left = 920
        Top = 24
        Width = 75
        Height = 25
        Caption = 'Execute'
        TabOrder = 1
        OnClick = Button1Click
      end
      object Chart4: TChart
        Left = 48
        Top = 400
        Width = 745
        Height = 185
        BackWall.Brush.Gradient.Direction = gdBottomTop
        BackWall.Brush.Gradient.EndColor = 7895160
        BackWall.Brush.Gradient.StartColor = 4605510
        BackWall.Brush.Gradient.Visible = True
        BackWall.Pen.Visible = False
        BackWall.Transparent = False
        Foot.Font.Color = clWhite
        Foot.Font.Name = 'Verdana'
        Gradient.Direction = gdBottomTop
        Gradient.EndColor = 4605510
        Gradient.StartColor = 4605510
        Gradient.Visible = True
        LeftWall.Color = clLightyellow
        Legend.Brush.Gradient.Direction = gdBottomTop
        Legend.Brush.Gradient.EndColor = 7895160
        Legend.Brush.Gradient.StartColor = 4605510
        Legend.Brush.Gradient.Visible = True
        Legend.Font.Color = clWhite
        Legend.Font.Name = 'Verdana'
        Legend.Frame.Visible = False
        Legend.LegendStyle = lsSeries
        Legend.Shadow.HorizSize = 0
        Legend.Shadow.Transparency = 0
        RightWall.Color = clLightyellow
        Title.Font.Color = clWhite
        Title.Font.Name = 'Verdana'
        Title.Text.Strings = (
          'TChart')
        BottomAxis.Axis.Color = 4210752
        BottomAxis.Grid.Color = clDarkgray
        BottomAxis.LabelsFormat.Font.Color = clWhite
        BottomAxis.LabelsFormat.Font.Name = 'Verdana'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = 8553090
        BottomAxis.TicksInner.Color = clDarkgray
        BottomAxis.Title.Font.Color = clWhite
        BottomAxis.Title.Font.Name = 'Verdana'
        DepthAxis.Axis.Color = 4210752
        DepthAxis.Grid.Color = clDarkgray
        DepthAxis.LabelsFormat.Font.Color = clWhite
        DepthAxis.LabelsFormat.Font.Name = 'Verdana'
        DepthAxis.MinorTicks.Visible = False
        DepthAxis.Ticks.Color = 8553090
        DepthAxis.TicksInner.Color = clDarkgray
        DepthAxis.Title.Font.Color = clWhite
        DepthAxis.Title.Font.Name = 'Verdana'
        DepthTopAxis.Axis.Color = 4210752
        DepthTopAxis.Grid.Color = clDarkgray
        DepthTopAxis.LabelsFormat.Font.Color = clWhite
        DepthTopAxis.LabelsFormat.Font.Name = 'Verdana'
        DepthTopAxis.MinorTicks.Visible = False
        DepthTopAxis.Ticks.Color = 8553090
        DepthTopAxis.TicksInner.Color = clDarkgray
        DepthTopAxis.Title.Font.Color = clWhite
        DepthTopAxis.Title.Font.Name = 'Verdana'
        Frame.Visible = False
        LeftAxis.Automatic = False
        LeftAxis.AutomaticMaximum = False
        LeftAxis.AutomaticMinimum = False
        LeftAxis.Axis.Color = 4210752
        LeftAxis.Grid.Color = clDarkgray
        LeftAxis.LabelsFormat.Font.Color = clWhite
        LeftAxis.LabelsFormat.Font.Name = 'Verdana'
        LeftAxis.Maximum = 100.000000000000000000
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = 8553090
        LeftAxis.TicksInner.Color = clDarkgray
        LeftAxis.Title.Font.Color = clWhite
        LeftAxis.Title.Font.Name = 'Verdana'
        RightAxis.Axis.Color = 4210752
        RightAxis.Grid.Color = clDarkgray
        RightAxis.LabelsFormat.Font.Color = clWhite
        RightAxis.LabelsFormat.Font.Name = 'Verdana'
        RightAxis.MinorTicks.Visible = False
        RightAxis.Ticks.Color = 8553090
        RightAxis.TicksInner.Color = clDarkgray
        RightAxis.Title.Font.Color = clWhite
        RightAxis.Title.Font.Name = 'Verdana'
        TopAxis.Axis.Color = 4210752
        TopAxis.Grid.Color = clDarkgray
        TopAxis.LabelsFormat.Font.Color = clWhite
        TopAxis.LabelsFormat.Font.Name = 'Verdana'
        TopAxis.MinorTicks.Visible = False
        TopAxis.Ticks.Color = 8553090
        TopAxis.TicksInner.Color = clDarkgray
        TopAxis.Title.Font.Color = clWhite
        TopAxis.Title.Font.Name = 'Verdana'
        View3D = False
        TabOrder = 2
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = -2
        ColorPalette = (
          5957320
          14456410
          2644710
          1024230)
        object Series17: TMtxFastLineSeries
          Marks.Font.Color = clWhite
          Marks.Transparent = True
          Title = 'Infusion Rate'
          LinePen.Color = 5957320
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
      end
    end
    object TabSheet3: TTabSheet
      Caption = 'Mixtures'
      ImageIndex = 3
      object Chart5: TChart
        Left = 64
        Top = 24
        Width = 1065
        Height = 569
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
        Legend.Font.Height = -13
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
        Title.Font.Height = -16
        Title.Font.Name = 'Times New Roman'
        Title.Text.Strings = (
          'Propofol 1% +Alfentanil 20 mcg/ml Marsh target 4')
        BottomAxis.Axis.Width = 1
        BottomAxis.Grid.Color = clBlack
        BottomAxis.Grid.Visible = False
        BottomAxis.GridCentered = True
        BottomAxis.LabelsFormat.Font.Height = -13
        BottomAxis.LabelsFormat.Font.Name = 'Times New Roman'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = clBlack
        BottomAxis.TicksInner.Visible = False
        BottomAxis.Title.Caption = 'Time minutes'
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
        LeftAxis.Grid.Visible = False
        LeftAxis.LabelsFormat.Font.Height = -13
        LeftAxis.LabelsFormat.Font.Name = 'Times New Roman'
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = clBlack
        LeftAxis.TicksInner.Visible = False
        LeftAxis.Title.Caption = 'Propofol conc mcg/ml Alfentanil ng/ml'
        LeftAxis.Title.Font.Name = 'Times New Roman'
        RightAxis.Automatic = False
        RightAxis.AutomaticMaximum = False
        RightAxis.AutomaticMinimum = False
        RightAxis.Axis.Width = 1
        RightAxis.Grid.Color = clBlack
        RightAxis.Grid.Visible = False
        RightAxis.LabelsFormat.Font.Height = -13
        RightAxis.LabelsFormat.Font.Name = 'Times New Roman'
        RightAxis.Maximum = 100.000000000000000000
        RightAxis.MinorTicks.Visible = False
        RightAxis.Ticks.Color = clBlack
        RightAxis.TicksInner.Visible = False
        RightAxis.Title.Caption = 'BIS'
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
        TabOrder = 0
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = 0
        object Series18: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Plasma Remifentanil'
          LinePen.Color = clGreen
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series19: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Effect Remifentanil'
          LinePen.Color = clYellow
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series20: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Propofol Plasma'
          LinePen.Color = clBlue
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series21: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Effect_Propofol'
          LinePen.Color = clRed
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series13: TMtxFastLineSeries
          SeriesColor = 8388863
          Title = 'BIS'
          VertAxis = aRightAxis
          LinePen.Color = 8388863
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object ChartTool5: TColorBandTool
          AllowDrag = False
          Brush.Color = -855638017
          Color = clLime
          EndValue = 60.000000000000000000
          Pen.Width = 0
          StartValue = 40.000000000000000000
          Transparency = 80
          EndLinePen.Color = -922681472
          EndLinePen.EndStyle = esRound
          StartLinePen.Width = 0
          StartLinePen.EndStyle = esRound
          AxisID = 3
          object TColorLineTool
            DragRepaint = True
            Pen.Width = 0
            Pen.EndStyle = esRound
            Value = 40.000000000000000000
            AxisID = 3
            object TAnnotationTool
              Shape.Alignment = taCenter
              Shape.Shadow.Visible = False
            end
          end
          object TColorLineTool
            DragRepaint = True
            Pen.Color = -922681472
            Pen.EndStyle = esRound
            Value = 60.000000000000000000
            AxisID = 3
            object TAnnotationTool
              Shape.Alignment = taCenter
              Shape.Shadow.Visible = False
            end
          end
        end
        object ChartTool8: TColorLineTool
          AnnotationValue = True
          Pen.EndStyle = esRound
          Value = 2.000000000000000000
          AxisID = 0
          object TAnnotationTool
            Shape.Alignment = taCenter
            Shape.CustomPosition = True
            Shape.Left = 138
            Shape.Shadow.Visible = False
            Shape.Text = '2'
            Shape.Top = 257
          end
        end
      end
      object Button2: TButton
        Left = 1200
        Top = 24
        Width = 75
        Height = 25
        Caption = 'Calculate'
        TabOrder = 1
        OnClick = Button2Click
      end
      object Button5: TButton
        Left = 1008
        Top = 528
        Width = 75
        Height = 25
        Caption = 'Export'
        TabOrder = 2
        OnClick = Button5Click
      end
    end
    object TabSheet4: TTabSheet
      Caption = 'Model Param Graphs'
      ImageIndex = 4
      object Chart2: TChart
        Left = 120
        Top = 40
        Width = 569
        Height = 417
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
        Legend.Font.Height = -13
        Legend.Font.Name = 'Times New Roman'
        Legend.Frame.Visible = False
        Legend.Shadow.HorizSize = 0
        Legend.Shadow.Transparency = 0
        Legend.Shadow.VertSize = 0
        Legend.Symbol.Pen.Visible = False
        Legend.Transparent = True
        RightWall.Color = clWhite
        RightWall.Dark3D = False
        RightWall.Size = 8
        Title.Font.Color = clBlack
        Title.Font.Height = -16
        Title.Font.Name = 'Times New Roman'
        Title.Text.Strings = (
          'James Formula BMI vs LBM')
        BottomAxis.Axis.Width = 1
        BottomAxis.Grid.Color = clBlack
        BottomAxis.Grid.Visible = False
        BottomAxis.GridCentered = True
        BottomAxis.LabelsFormat.Font.Height = -13
        BottomAxis.LabelsFormat.Font.Name = 'Times New Roman'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = clBlack
        BottomAxis.TicksInner.Visible = False
        BottomAxis.Title.Caption = 'BMI'
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
        LeftAxis.Grid.Visible = False
        LeftAxis.LabelsFormat.Font.Height = -13
        LeftAxis.LabelsFormat.Font.Name = 'Times New Roman'
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = clBlack
        LeftAxis.TicksInner.Visible = False
        LeftAxis.Title.Caption = 'LBM kg'
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
        TabOrder = 0
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = 0
        object Export: TButton
          Left = 480
          Top = 384
          Width = 75
          Height = 25
          Caption = 'Button8'
          TabOrder = 0
          OnClick = ExportClick
        end
        object Series10: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Male'
          LinePen.Color = clRed
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series11: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Female'
          LinePen.Color = clGreen
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
      end
      object Button4: TButton
        Left = 744
        Top = 40
        Width = 75
        Height = 25
        Caption = 'Execute'
        TabOrder = 1
        OnClick = Button4Click
      end
      object Memo1: TMemo
        Left = 744
        Top = 304
        Width = 281
        Height = 153
        Lines.Strings = (
          '')
        TabOrder = 2
      end
    end
    object Graphics: TTabSheet
      Caption = 'Graphics'
      ImageIndex = 5
      object Panel2: TPanel
        Left = 24
        Top = 16
        Width = 721
        Height = 521
        TabOrder = 0
      end
    end
    object TabSheet5: TTabSheet
      Caption = 'Remi TCI'
      ImageIndex = 6
      object Chart6: TChart
        Left = 80
        Top = 40
        Width = 841
        Height = 521
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
        Legend.Font.Height = -13
        Legend.Font.Name = 'Times New Roman'
        Legend.Frame.Visible = False
        Legend.Shadow.HorizSize = 0
        Legend.Shadow.Transparency = 0
        Legend.Shadow.VertSize = 0
        Legend.Symbol.Pen.Visible = False
        Legend.Transparent = True
        RightWall.Color = clWhite
        RightWall.Dark3D = False
        RightWall.Size = 8
        Title.Font.Color = clBlack
        Title.Font.Height = -16
        Title.Font.Name = 'Times New Roman'
        Title.Text.Strings = (
          
            'Remifentanil 1 mcg/kg Bolus + 0.25 mcg/kg infusion 70kg vs TCI 5' +
            'ng/ml')
        BottomAxis.Axis.Width = 1
        BottomAxis.Grid.Color = clBlack
        BottomAxis.Grid.Visible = False
        BottomAxis.GridCentered = True
        BottomAxis.LabelsFormat.Font.Height = -13
        BottomAxis.LabelsFormat.Font.Name = 'Times New Roman'
        BottomAxis.MinorTicks.Visible = False
        BottomAxis.Ticks.Color = clBlack
        BottomAxis.TicksInner.Visible = False
        BottomAxis.Title.Caption = 'Time minutes'
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
        LeftAxis.Automatic = False
        LeftAxis.AutomaticMaximum = False
        LeftAxis.AutomaticMinimum = False
        LeftAxis.Axis.Width = 1
        LeftAxis.Grid.Color = clBlack
        LeftAxis.Grid.Visible = False
        LeftAxis.LabelsFormat.Font.Height = -13
        LeftAxis.LabelsFormat.Font.Name = 'Times New Roman'
        LeftAxis.Maximum = 15.000000000000000000
        LeftAxis.MinorTicks.Visible = False
        LeftAxis.Ticks.Color = clBlack
        LeftAxis.TicksInner.Visible = False
        LeftAxis.Title.Caption = 'Remi Concentration mcg/ml'
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
        TabOrder = 0
        DefaultCanvas = 'TGDIPlusCanvas'
        ColorPaletteIndex = 0
        object Button7: TButton
          Left = 736
          Top = 464
          Width = 75
          Height = 25
          Caption = 'Export'
          TabOrder = 0
          OnClick = Button7Click
        end
        object Series22: TMtxFastLineSeries
          Marks.Font.Height = -13
          Marks.Font.Name = 'Times New Roman'
          Marks.Transparent = True
          Marks.Arrow.Color = clBlack
          Marks.Callout.Arrow.Color = clBlack
          Title = 'Pump_Plasma'
          LinePen.Color = clRed
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series23: TMtxFastLineSeries
          Title = 'Pump_Effect'
          LinePen.Color = clGreen
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series24: TMtxFastLineSeries
          Title = 'Cont_Plasma'
          LinePen.Color = clYellow
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object Series25: TMtxFastLineSeries
          Title = 'Cont_Effect'
          LinePen.Color = clBlue
          XValues.Name = 'X'
          XValues.Order = loAscending
          YValues.Name = 'Y'
          YValues.Order = loNone
        end
        object ChartTool6: TColorLineTool
          AnnotationValue = True
          Pen.EndStyle = esRound
          Value = 3.000000000000000000
          AxisID = 2
          object TAnnotationTool
            Shape.Alignment = taCenter
            Shape.CustomPosition = True
            Shape.Left = 365
            Shape.Shadow.Visible = False
            Shape.Text = '3'
            Shape.Top = 354
          end
        end
        object ChartTool7: TColorLineTool
          Active = False
          AnnotationValue = True
          Pen.EndStyle = esRound
          Value = 2.000000000000000000
          AxisID = 0
          object TAnnotationTool
            Shape.Alignment = taCenter
            Shape.CustomPosition = True
            Shape.Left = 111
            Shape.Shadow.Visible = False
            Shape.Text = '2'
            Shape.Top = 247
          end
        end
      end
      object Button6: TButton
        Left = 976
        Top = 40
        Width = 75
        Height = 25
        Caption = 'Execute'
        TabOrder = 1
        OnClick = Button6Click
      end
    end
  end
  object MainMenu1: TMainMenu
    Left = 4
    Top = 62
    object miPatient: TMenuItem
      Caption = 'Patient'
      OnClick = miPatientClick
    end
  end
  object SaveDialog1: TSaveDialog
    DefaultExt = 'svg'
    Filter = 'svg'
    InitialDir = 'C:\tempCharts;'
    Left = 7
    Top = 148
  end
  object Timer1: TTimer
    Left = 4
    Top = 738
  end
end
