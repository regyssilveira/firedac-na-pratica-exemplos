object CatalogData: TCatalogData
  Height = 240
  Width = 360
  object Connection: TFDConnection
    LoginPrompt = False
    Left = 64
    Top = 48
  end
  object Products: TFDQuery
    Connection = Connection
    Left = 144
    Top = 48
  end
  object FBLink: TFDPhysFBDriverLink
    Left = 64
    Top = 120
  end
  object SQLiteLink: TFDPhysSQLiteDriverLink
    Left = 144
    Top = 120
  end
end
