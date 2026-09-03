object MainForm: TMainForm
  Left = 0
  Top = 0
  Caption = 'FireDAC na Prática - Capítulo 1'
  ClientHeight = 420
  ClientWidth = 720
  Position = poScreenCenter
  OnShow = FormShow
  TextHeight = 15
  object GridProducts: TDBGrid
    Left = 16
    Top = 64
    Width = 688
    Height = 320
    DataSource = DsProducts
    TabOrder = 3
  end
  object BtnOpen: TButton
    Left = 16
    Top = 20
    Width = 112
    Height = 27
    Caption = 'Abrir catálogo'
    TabOrder = 0
    OnClick = BtnOpenClick
  end
  object EdtSku: TEdit
    Left = 144
    Top = 21
    Width = 145
    Height = 23
    TabOrder = 1
    Text = 'BEB-001'
  end
  object BtnFind: TButton
    Left = 304
    Top = 20
    Width = 96
    Height = 27
    Caption = 'Buscar SKU'
    TabOrder = 2
    OnClick = BtnFindClick
  end
  object LblStatus: TLabel
    Left = 424
    Top = 26
    Width = 91
    Height = 15
    Caption = 'Conexão fechada'
  end
  object Connection: TFDConnection
    LoginPrompt = False
    Left = 472
    Top = 200
  end
  object QryProducts: TFDQuery
    Connection = Connection
    Left = 552
    Top = 200
  end
  object DsProducts: TDataSource
    DataSet = QryProducts
    Left = 632
    Top = 200
  end
  object FBLink: TFDPhysFBDriverLink
    Left = 472
    Top = 272
  end
  object SQLiteLink: TFDPhysSQLiteDriverLink
    Left = 552
    Top = 272
  end
end
