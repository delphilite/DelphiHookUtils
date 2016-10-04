object MainForm: TMainForm
  Left = 460
  Top = 265
  Caption = 'MainForm'
  ClientHeight = 260
  ClientWidth = 424
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  Position = poScreenCenter
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  PixelsPerInch = 96
  TextHeight = 13
  object cbHookAPI: TCheckBox
    Left = 112
    Top = 84
    Width = 200
    Height = 17
    Caption = 'Hook Windows API'
    TabOrder = 0
    OnClick = cbHookAPIClick
  end
  object cbHookCOM: TCheckBox
    Left = 112
    Top = 121
    Width = 200
    Height = 17
    Caption = 'Hook COM'
    TabOrder = 1
    OnClick = cbHookCOMClick
  end
  object cbHookObject: TCheckBox
    Left = 112
    Top = 160
    Width = 200
    Height = 17
    Caption = 'Hook Method'
    TabOrder = 2
    OnClick = cbHookObjectClick
  end
end
