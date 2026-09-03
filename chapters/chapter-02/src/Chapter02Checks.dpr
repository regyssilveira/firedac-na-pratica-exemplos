program Chapter02Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Util,
  FireDAC.Phys.Intf,
  FireDAC.Comp.Client,
  Chapter02.CatalogData in 'Chapter02.CatalogData.pas' {CatalogData: TDataModule};

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

procedure RunCore;
var
  Catalog: TCatalogData;
begin
  Catalog := TCatalogData.Create(nil);
  try
    Catalog.Configure;
    Catalog.OpenProducts;
    Check(Catalog.Products.RecordCount > 0, 'O núcleo não retornou produtos.');
    Writeln('EX-02-03 aprovado: núcleo sem VCL retornou ',
      Catalog.Products.RecordCount, ' produto(s).');
  finally
    Catalog.Free;
  end;
end;

procedure RunFlow;
var
  Catalog: TCatalogData;
  Source: TDataSource;
begin
  Catalog := TCatalogData.Create(nil);
  Source := TDataSource.Create(nil);
  try
    Catalog.Configure;
    Catalog.OpenProducts;
    Source.DataSet := Catalog.Products;
    Check(Catalog.Products.Connection = Catalog.Connection,
      'A query perdeu a conexão esperada.');
    Check(Source.DataSet = Catalog.Products,
      'O datasource perdeu o dataset esperado.');
    Writeln('EX-02-01 aprovado: interface -> datasource -> dataset -> conexão -> driver.');
  finally
    Source.Free;
    Catalog.Free;
  end;
end;

procedure RunDrivers;
var
  Catalog: TCatalogData;
  Drivers: TStringList;
begin
  Catalog := TCatalogData.Create(nil);
  Drivers := TStringList.Create;
  try
    FDManager.GetDriverNames(Drivers, False);
    Check(Drivers.IndexOf('FB') >= 0, 'Driver FB não registrado.');
    Check(Drivers.IndexOf('SQLite') >= 0, 'Driver SQLite não registrado.');
    Catalog.Configure;
    Check(SameText(Catalog.FBLink.VendorLib,
      GetEnvironmentVariable('FIRESTORE_FBCLIENT')),
      'DriverLink explícito não recebeu VendorLib.');
    Check(FileExists(Catalog.FBLink.VendorLib),
      'A biblioteca cliente explícita não existe.');
    Writeln('EX-02-04 aprovado: drivers registrados e VendorLib explícita validada.');
  finally
    Drivers.Free;
    Catalog.Free;
  end;
end;

procedure RunReport;
var
  Catalog: TCatalogData;
  Meta: IFDPhysConnectionMetadata;
begin
  Catalog := TCatalogData.Create(nil);
  try
    Catalog.Configure;
    Catalog.OpenProducts;
    Meta := Catalog.Connection.ConnectionMetaDataIntf;
    Check(Meta <> nil, 'Metadados físicos da conexão não disponíveis.');
    Writeln('EX-02-05 relatório de capacidades');
    Writeln('RDBMSKind=', Ord(Meta.Kind));
    Writeln('ClientVersion=', FDVerInt2Str(Meta.ClientVersion));
    Writeln('ServerVersion=', FDVerInt2Str(Meta.ServerVersion));
    Writeln('Unicode=', BoolToStr(Meta.IsUnicode, True));
    Writeln('FileBased=', BoolToStr(Meta.IsFileBased, True));
    Writeln('Transactions=', BoolToStr(Meta.TxSupported, True));
    Writeln('Savepoints=', BoolToStr(Meta.TxSavepoints, True));
    Writeln('Events=', BoolToStr(Meta.EventSupported, True));
    Check(Meta.TxSupported, 'O driver não informou suporte transacional esperado.');
  finally
    Catalog.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter02Checks core|flow|drivers|report');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'core') then
      RunCore
    else if SameText(ParamStr(1), 'flow') then
      RunFlow
    else if SameText(ParamStr(1), 'drivers') then
      RunDrivers
    else if SameText(ParamStr(1), 'report') then
      RunReport
    else
    begin
      ShowUsage;
      ExitCode := 2;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
