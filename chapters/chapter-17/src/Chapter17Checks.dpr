program Chapter17Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.IOUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Phys.SQLiteVDataSet,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  FireDAC.Comp.BatchMove,
  FireDAC.Comp.BatchMove.Text,
  FireDAC.Comp.BatchMove.DataSet;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function CurrentIsFirebird: Boolean;
begin
  Result := SameText(RequiredEnvironment('CH17_DRIVER'), 'FB');
end;

procedure ConfigureExternal(AConnection: TFDConnection; ALink: TFDPhysFBDriverLink;
  AUseFirebird: Boolean);
begin
  AConnection.LoginPrompt := False;
  if AUseFirebird then
  begin
    ALink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
    AConnection.Params.Values['DriverID'] := 'FB';
    AConnection.Params.Values['Protocol'] := 'TCPIP';
    AConnection.Params.Values['Server'] := RequiredEnvironment('FIRESTORE_DB_HOST');
    AConnection.Params.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
    AConnection.Params.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
    AConnection.Params.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
    AConnection.Params.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
    AConnection.Params.Values['CharacterSet'] := 'UTF8';
  end
  else
  begin
    AConnection.Params.Values['DriverID'] := 'SQLite';
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH17_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

function NewExternal(ALink: TFDPhysFBDriverLink; AUseFirebird: Boolean): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    ConfigureExternal(Result, ALink, AUseFirebird);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

procedure ConfigureLocal(AConnection: TFDConnection; ALocalSQL: TFDLocalSQL);
begin
  AConnection.LoginPrompt := False;
  AConnection.Params.Values['DriverID'] := 'SQLite';
  AConnection.Params.Values['Database'] := ':memory:';
  AConnection.Open;
  ALocalSQL.Connection := AConnection;
end;

procedure DefineProducts(ATable: TFDMemTable);
begin
  ATable.FieldDefs.Add('product_id', ftLargeint, 0, True);
  ATable.FieldDefs.Add('sku', ftWideString, 30, True);
  ATable.FieldDefs.Add('name', ftWideString, 120, True);
  ATable.FieldDefs.Add('price', ftCurrency, 0, True);
  ATable.FieldDefs.Add('active', ftInteger, 0, True);
  ATable.CreateDataSet;
end;

procedure SeedProducts(ATable: TFDMemTable);
begin
  ATable.AppendRecord([Int64(1), 'BEB-001', 'Caf' + #$00E9, Currency(24.90), 1]);
  ATable.AppendRecord([Int64(2), 'BEB-002', 'Chá', Currency(8.50), 1]);
  ATable.AppendRecord([Int64(3), 'ALI-001', 'Pão', Currency(18.75), 0]);
end;

procedure RunMemTable;
var
  Products: TFDMemTable;
  Connection: TFDConnection;
  LocalSQL: TFDLocalSQL;
  Query: TFDQuery;
begin
  Products := TFDMemTable.Create(nil);
  Connection := TFDConnection.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    DefineProducts(Products);
    SeedProducts(Products);
    ConfigureLocal(Connection, LocalSQL);
    LocalSQL.DataSets.Add(Products, '', 'products');
    LocalSQL.Active := True;
    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT active, COUNT(*) AS qty, SUM(price) AS total ' +
      'FROM products GROUP BY active ORDER BY active';
    Query.Open;
    Check(Query.RecordCount = 2, 'Agrupamento local deveria ter dois grupos.');
    Check(Query.FieldByName('active').AsInteger = 0, 'Primeiro grupo incorreto.');
    Check(Query.FieldByName('qty').AsInteger = 1, 'Contagem do grupo inativo incorreta.');
    Query.Next;
    Check(Query.FieldByName('qty').AsInteger = 2, 'Contagem do grupo ativo incorreta.');
    Check(Abs(Query.FieldByName('total').AsFloat - 33.40) < 0.001,
      'Soma local do grupo ativo incorreta.');
    Writeln('EX-17-01 aprovado: MemTable consultada com filtro, grupo e soma locais.');
  finally
    Query.Free;
    LocalSQL.Free;
    Connection.Free;
    Products.Free;
  end;
end;

procedure LoadTargets(ATable: TFDMemTable);
var
  Batch: TFDBatchMove;
  Reader: TFDBatchMoveTextReader;
  Writer: TFDBatchMoveDataSetWriter;
begin
  ATable.FieldDefs.Add('sku', ftWideString, 30, False);
  ATable.FieldDefs.Add('target_quantity', ftInteger, 0, False);
  ATable.CreateDataSet;
  Batch := TFDBatchMove.Create(nil);
  Reader := TFDBatchMoveTextReader.Create(Batch);
  Writer := TFDBatchMoveDataSetWriter.Create(Batch);
  try
    Reader.FileName := RequiredEnvironment('CH17_CSV_FILE');
    Reader.Encoding := ecUTF8;
    Reader.DataDef.Separator := ';';
    Reader.DataDef.WithFieldNames := True;
    Reader.DataDef.Fields.Add.Define('sku', FireDAC.Stan.Intf.dtWideString, 30, 0, 0);
    Reader.DataDef.Fields.Add.Define('target_quantity', FireDAC.Stan.Intf.dtInt32, 0, 0, 0);
    Writer.DataSet := ATable;
    Batch.Mode := dmAlwaysInsert;
    Batch.Execute;
  finally
    Batch.Free;
  end;
end;

procedure RunCsvJoin;
var
  Products, Targets: TFDMemTable;
  Connection: TFDConnection;
  LocalSQL: TFDLocalSQL;
  Query: TFDQuery;
begin
  Products := TFDMemTable.Create(nil);
  Targets := TFDMemTable.Create(nil);
  Connection := TFDConnection.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    DefineProducts(Products);
    SeedProducts(Products);
    LoadTargets(Targets);
    ConfigureLocal(Connection, LocalSQL);
    LocalSQL.DataSets.Add(Products, '', 'products');
    LocalSQL.DataSets.Add(Targets, '', 'targets');
    LocalSQL.Active := True;
    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT p.sku, p.name, COALESCE(t.target_quantity, 0) AS target ' +
      'FROM products p LEFT JOIN targets t ON t.sku = p.sku ORDER BY p.product_id';
    Query.Open;
    Check(Query.RecordCount = 3, 'LEFT JOIN não preservou os três produtos.');
    Check(Query.FieldByName('target').AsInteger = 10, 'Meta do primeiro SKU incorreta.');
    Query.Last;
    Check(Query.FieldByName('target').AsInteger = 0, 'Chave ausente não virou zero.');
    Check(Products.RecordCount = 3, 'Join local alterou a fonte.');
    Writeln('EX-17-02 aprovado: CSV tipado participou de LEFT JOIN com chave ausente.');
  finally
    Query.Free;
    LocalSQL.Free;
    Connection.Free;
    Targets.Free;
    Products.Free;
  end;
end;

procedure RunTwoConnections;
var
  Link: TFDPhysFBDriverLink;
  SQLiteConnection, FBConnection, LocalConnection: TFDConnection;
  Products, Inventory, ResultQuery: TFDQuery;
  LocalSQL: TFDLocalSQL;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  SQLiteConnection := NewExternal(Link, False);
  FBConnection := NewExternal(Link, True);
  LocalConnection := TFDConnection.Create(nil);
  Products := TFDQuery.Create(nil);
  Inventory := TFDQuery.Create(nil);
  ResultQuery := TFDQuery.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  try
    Products.Connection := SQLiteConnection;
    Products.SQL.Text := 'SELECT id AS product_id, sku, name FROM product WHERE id <= 3';
    Products.Open;
    Products.FetchAll;
    Inventory.Connection := FBConnection;
    Inventory.SQL.Text := 'SELECT product_id, quantity FROM inventory WHERE product_id <= 3';
    Inventory.Open;
    Inventory.FetchAll;
    ConfigureLocal(LocalConnection, LocalSQL);
    LocalSQL.DataSets.Add(Products, '', 'source_products');
    LocalSQL.DataSets.Add(Inventory, '', 'fb_inventory');
    LocalSQL.Active := True;
    ResultQuery.Connection := LocalConnection;
    ResultQuery.SQL.Text := 'SELECT p.sku, i.quantity FROM source_products p ' +
      'JOIN fb_inventory i ON i.product_id = p.product_id ORDER BY p.product_id';
    ResultQuery.Open;
    Check(ResultQuery.RecordCount = 3, 'Composição de duas conexões perdeu linhas.');
    Check((Products.RecordCount = 3) and (Inventory.RecordCount = 3),
      'Fontes reduzidas não possuem três linhas cada.');
    Writeln('EX-17-03 aprovado: SQLite e Firebird compuseram dois snapshots de 3 linhas.');
  finally
    ResultQuery.Free;
    LocalSQL.Free;
    Inventory.Free;
    Products.Free;
    LocalConnection.Free;
    FBConnection.Free;
    SQLiteConnection.Free;
    Link.Free;
  end;
end;

procedure RunAggregate;
var
  Link: TFDPhysFBDriverLink;
  External, LocalConnection: TFDConnection;
  Source, Query: TFDQuery;
  LocalSQL: TFDLocalSQL;
  ServerTotal, LocalTotal: Double;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  External := NewExternal(Link, CurrentIsFirebird);
  LocalConnection := TFDConnection.Create(nil);
  Source := TFDQuery.Create(nil);
  Query := TFDQuery.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  try
    Source.Connection := External;
    Source.SQL.Text := 'SELECT id, price FROM product WHERE id <= 3';
    Source.Open;
    Source.FetchAll;
    ServerTotal := External.ExecSQLScalar('SELECT SUM(price) FROM product WHERE id <= 3');
    ConfigureLocal(LocalConnection, LocalSQL);
    LocalSQL.DataSets.Add(Source, '', 'source_prices');
    LocalSQL.Active := True;
    Query.Connection := LocalConnection;
    Query.SQL.Text := 'SELECT SUM(price) AS total FROM source_prices';
    Query.Open;
    LocalTotal := Query.FieldByName('total').AsFloat;
    Check(Abs(LocalTotal - ServerTotal) < 0.001,
      'Agregação local divergiu do mesmo recorte no servidor.');
    Check(Source.RecordCount = 3, 'Fonte não foi reduzida antes da composição.');
    Writeln('EX-17-04 aprovado: soma local e servidor coincidiram para 3 linhas.');
  finally
    LocalSQL.Free;
    Query.Free;
    Source.Free;
    LocalConnection.Free;
    External.Free;
    Link.Free;
  end;
end;

procedure RunLimits;
var
  Products: TFDMemTable;
  Connection: TFDConnection;
  LocalSQL: TFDLocalSQL;
  Query: TFDQuery;
  FunctionRejected, SyntaxRejected: Boolean;
  Version: string;
begin
  Products := TFDMemTable.Create(nil);
  Connection := TFDConnection.Create(nil);
  LocalSQL := TFDLocalSQL.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    DefineProducts(Products);
    SeedProducts(Products);
    ConfigureLocal(Connection, LocalSQL);
    LocalSQL.DataSets.Add(Products, '', 'products');
    LocalSQL.Active := True;
    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT sqlite_version() AS version, typeof(price) AS storage_type ' +
      'FROM products LIMIT 1';
    Query.Open;
    Version := Query.FieldByName('version').AsString;
    Check(Version <> '', 'Versão SQLite local não foi obtida.');
    Query.Close;
    FunctionRejected := False;
    try
      Query.SQL.Text := 'SELECT GEN_UUID() FROM products LIMIT 1';
      Query.Open;
    except
      on E: Exception do FunctionRejected := True;
    end;
    if Query.Active then Query.Close;
    SyntaxRejected := False;
    try
      Query.SQL.Text := 'SELECT FIRST 1 sku FROM products';
      Query.Open;
    except
      on E: Exception do SyntaxRejected := True;
    end;
    Check(FunctionRejected, 'Função específica do Firebird foi aceita inesperadamente.');
    Check(SyntaxRejected, 'Sintaxe FIRST do Firebird foi aceita inesperadamente.');
    Writeln('EX-17-05 aprovado: SQLite local ', Version,
      ' aceitou seu dialeto e rejeitou GEN_UUID/FIRST.');
  finally
    Query.Free;
    LocalSQL.Free;
    Connection.Free;
    Products.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter17Checks memtable|csv|connections|aggregate|limits');
end;

begin
  try
    if ParamCount <> 1 then begin ShowUsage; ExitCode := 2; end
    else if SameText(ParamStr(1), 'memtable') then RunMemTable
    else if SameText(ParamStr(1), 'csv') then RunCsvJoin
    else if SameText(ParamStr(1), 'connections') then RunTwoConnections
    else if SameText(ParamStr(1), 'aggregate') then RunAggregate
    else if SameText(ParamStr(1), 'limits') then RunLimits
    else begin ShowUsage; ExitCode := 2; end;
  except
    on E: Exception do begin Writeln(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
