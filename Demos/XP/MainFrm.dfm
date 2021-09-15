object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'MainForm'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  PixelsPerInch = 96
  TextHeight = 15
  object Label1: TLabel
    Left = 128
    Top = 136
    Width = 18
    Height = 15
    Caption = 'OS:'
  end
  object Button1: TButton
    Left = 128
    Top = 168
    Width = 100
    Height = 25
    Caption = 'GetTickCount64'
    TabOrder = 0
    OnClick = Button1Click
  end
end
