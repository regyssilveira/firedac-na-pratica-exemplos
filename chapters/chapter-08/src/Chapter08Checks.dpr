program Chapter08Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
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
  FireDAC.Phys.Intf,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  FireDAC.Moni.Base,
  FireDAC.Moni.FlatFile,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

type
  TCalcContext = class
  public
    Calls: Integer;
    procedure Calculate(DataSet: TDataSet);
  end;

procedure TCalcContext.Calculate(DataSet: TDataSet);
begin
  Inc(Calls);
  DataSet.FieldByName('display_name').AsString :=
    DataSet.FieldByName('sku').AsString + ' - ' +
    DataSet.FieldByName('name').AsString;
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function IsFirebird: Boolean;
begin
  Result := SameText(RequiredEnvironment('CH08_DRIVER'), 'FB');
end;

procedure ConfigureConnection(AConnection: TFDConnection;
  AFBLink: TFDPhysFBDriverLink);
begin
  AConnection.LoginPrompt := False;
  if IsFirebird then
  begin
    AFBLink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH08_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
    AConnection.Params.Values['BusyTimeout'] := '5000';
  end;
end;

procedure WithConnection(const ATest: TProc<TFDConnection>);
var
  Connection: TFDConnection;
  FBLink: TFDPhysFBDriverLink;
  Monitor: TFDMoniFlatFileClientLink;
  TraceFile: string;
begin
  Connection := TFDConnection.Create(nil);
  FBLink := TFDPhysFBDriverLink.Create(nil);
  Monitor := TFDMoniFlatFileClientLink.Create(nil);
  try
    TraceFile := RequiredEnvironment('CH08_TRACE_FILE');
    ForceDirectories(ExtractFilePath(TraceFile));
    if FileExists(TraceFile) then
      TFile.Delete(TraceFile);
    Monitor.FileName := TraceFile;
    Monitor.Tracing := True;
    ConfigureConnection(Connection, FBLink);
    Connection.Params.Values['MonitorBy'] := 'FlatFile';
    Connection.Open;
    ATest(Connection);
  finally
    Monitor.Tracing := False;
    Connection.Free;
    FBLink.Free;
    Monitor.Free;
  end;
end;

procedure AddPhysicalFields(AMemTable: TFDMemTable);
var
  I: Integer;
begin
  for I := 0 to AMemTable.FieldDefs.Count - 1 do
    AMemTable.FieldDefs[I].CreateField(AMemTable);
end;

procedure RunCalculated;
var
  Mem: TFDMemTable;
  DisplayName: TStringField;
  Context: TCalcContext;
begin
  Mem := TFDMemTable.Create(nil);
  Context := TCalcContext.Create;
  try
    Mem.FieldDefs.Add('sku', ftString, 30);
    Mem.FieldDefs.Add('name', ftWideString, 120);
    AddPhysicalFields(Mem);
    DisplayName := TStringField.Create(Mem);
    DisplayName.FieldName := 'display_name';
    DisplayName.Size := 160;
    DisplayName.FieldKind := fkCalculated;
    DisplayName.ProviderFlags := [];
    DisplayName.DataSet := Mem;
    Mem.OnCalcFields := Context.Calculate;
    Mem.CreateDataSet;
    Mem.AppendRecord(['BEB-001', 'Caf' + #$00E9 + ' especial']);
    Check(Mem.FieldByName('display_name').AsString =
      'BEB-001 - Caf' + #$00E9 + ' especial',
      'Campo calculado devolveu texto incorreto.');
    Check(Context.Calls > 0, 'OnCalcFields não foi chamado.');
    Check(not (pfInUpdate in DisplayName.ProviderFlags),
      'Campo calculado entrou nos campos atualizáveis.');
    Writeln(Format('EX-08-01 aprovado: display_name calculado; chamadas=%d.',
      [Context.Calls]));
  finally
    Context.Free;
    Mem.Free;
  end;
end;

procedure BuildCategories(AMem: TFDMemTable);
begin
  AMem.FieldDefs.Add('id', ftLargeint);
  AMem.FieldDefs.Add('name', ftWideString, 80);
  AddPhysicalFields(AMem);
  AMem.CreateDataSet;
  AMem.AppendRecord([1, 'Bebidas']);
  AMem.AppendRecord([2, 'Alimentos']);
end;

procedure RunLookup;
var
  Categories, Products: TFDMemTable;
  LookupField: TStringField;
begin
  Categories := TFDMemTable.Create(nil);
  Products := TFDMemTable.Create(nil);
  try
    BuildCategories(Categories);
    Products.FieldDefs.Add('id', ftLargeint);
    Products.FieldDefs.Add('category_id', ftLargeint);
    AddPhysicalFields(Products);
    LookupField := TStringField.Create(Products);
    LookupField.FieldName := 'category_name';
    LookupField.Size := 80;
    LookupField.FieldKind := fkLookup;
    LookupField.ProviderFlags := [];
    LookupField.KeyFields := 'category_id';
    LookupField.LookupDataSet := Categories;
    LookupField.LookupKeyFields := 'id';
    LookupField.LookupResultField := 'name';
    LookupField.DataSet := Products;
    Products.CreateDataSet;
    Products.AppendRecord([1, 1]);
    Check(Products.FieldByName('category_name').AsString = 'Bebidas',
      'Lookup não encontrou categoria válida.');
    Products.AppendRecord([2, 999]);
    Check(Products.FieldByName('category_name').IsNull,
      'Lookup de chave ausente não devolveu Null.');
    Check(not (pfInUpdate in LookupField.ProviderFlags),
      'Campo lookup entrou nos campos atualizáveis.');
    Writeln('EX-08-02 aprovado: lookup resolveu chave válida e deixou ausente nula.');
  finally
    Products.Free;
    Categories.Free;
  end;
end;

procedure RunAggregate;
var
  Items: TFDMemTable;
  Total: TAggregateField;
begin
  Items := TFDMemTable.Create(nil);
  try
    Items.FieldDefs.Add('quantity', ftInteger);
    Items.FieldDefs.Add('unit_price', ftCurrency);
    AddPhysicalFields(Items);
    Total := TAggregateField.Create(Items);
    Total.FieldName := 'order_total';
    Total.FieldKind := fkAggregate;
    Total.Expression := 'SUM(quantity * unit_price)';
    Total.DataSet := Items;
    Total.Active := True;
    Items.CreateDataSet;
    Items.AggregatesActive := True;
    Items.AppendRecord([2, 10.00]);
    Items.AppendRecord([3, 5.00]);
    Check(Abs(Currency(VarAsType(Total.Value, varCurrency)) - 35.00) < 0.001,
      'Agregado inicial não totalizou 35.');
    Items.Edit;
    Items.FieldByName('quantity').AsInteger := 4;
    Items.Post;
    Check(Abs(Currency(VarAsType(Total.Value, varCurrency)) - 40.00) < 0.001,
      'Agregado não reagiu ao post.');
    Items.Edit;
    Items.FieldByName('quantity').AsInteger := 9;
    Items.Cancel;
    Check(Abs(Currency(VarAsType(Total.Value, varCurrency)) - 40.00) < 0.001,
      'Cancel alterou o total confirmado.');
    Writeln('EX-08-03 aprovado: agregado passou por append, post e cancel.');
  finally
    Items.Free;
  end;
end;

procedure RunJoinUpdate;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      OriginalPrice: Currency;
    begin
      Query := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Query.Connection := Connection;
        Query.UpdateOptions.UpdateTableName := 'product';
        Query.UpdateOptions.KeyFields := 'id';
        Query.UpdateOptions.UpdateMode := upWhereKeyOnly;
        Query.SQL.Text :=
          'SELECT p.id, p.sku, p.name, p.price, p.category_id, ' +
          'c.name AS category_name, p.version FROM product p ' +
          'JOIN category c ON c.id = p.category_id WHERE p.id = :id';
        Query.ParamByName('id').AsLargeInt := 1;
        Query.Open;
        Query.FieldByName('category_name').ProviderFlags := [];
        Check(not (pfInUpdate in Query.FieldByName('category_name').ProviderFlags),
          'Coluna do join permaneceu atualizável.');
        Check(pfInKey in Query.FieldByName('id').ProviderFlags,
          'id não foi reconhecido como chave.');
        OriginalPrice := Query.FieldByName('price').AsCurrency;
        Query.Edit;
        Check(Query.State = dsEdit, 'Edit não colocou o dataset em dsEdit.');
        Query.FieldByName('price').AsCurrency := OriginalPrice + 1;
        Query.Post;
        Check(Query.State = dsBrowse, 'Post não devolveu dsBrowse.');
        Check(Abs(Currency(Connection.ExecSQLScalar(
          'SELECT price FROM product WHERE id = :id', [1])) -
          (OriginalPrice + 1)) < 0.001,
          'Post do join não atualizou product.');
        Writeln('EX-08-04 aprovado: join atualizou somente product em transação aberta.');
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
      end;
    end);
end;

procedure ConfigureExplicitUpdate(AQuery: TFDQuery; AUpdateSQL: TFDUpdateSQL);
begin
  AUpdateSQL.Connection := AQuery.Connection;
  AUpdateSQL.ModifySQL.Text :=
    'UPDATE product SET price = :NEW_price, version = :OLD_version + 1 ' +
    'WHERE id = :OLD_id AND version = :OLD_version';
  AQuery.UpdateObject := AUpdateSQL;
end;

procedure RunExplicitConflict;
var
  ConnectionA, ConnectionB: TFDConnection;
  LinkA, LinkB: TFDPhysFBDriverLink;
  Query: TFDQuery;
  UpdateSQL: TFDUpdateSQL;
  ConflictRaised: Boolean;
  ConflictMessage: string;
  OriginalPrice: Currency;
  OriginalVersion: Int64;
begin
  OriginalPrice := 0;
  OriginalVersion := 0;
  ConnectionA := TFDConnection.Create(nil);
  ConnectionB := TFDConnection.Create(nil);
  LinkA := TFDPhysFBDriverLink.Create(nil);
  LinkB := TFDPhysFBDriverLink.Create(nil);
  Query := TFDQuery.Create(nil);
  UpdateSQL := TFDUpdateSQL.Create(nil);
  try
    ConfigureConnection(ConnectionA, LinkA);
    ConfigureConnection(ConnectionB, LinkB);
    ConnectionA.Open;
    ConnectionB.Open;
    Query.Connection := ConnectionA;
    Query.SQL.Text := 'SELECT id, price, version FROM product WHERE id = :id';
    Query.ParamByName('id').AsLargeInt := 1;
    Query.Open;
    Query.FetchAll;
    OriginalPrice := Query.FieldByName('price').AsCurrency;
    OriginalVersion := Query.FieldByName('version').AsLargeInt;
    ConfigureExplicitUpdate(Query, UpdateSQL);

    ConnectionB.ExecSQL(
      'UPDATE product SET version = version + 1 WHERE id = :id', [1]);
    ConflictRaised := False;
    ConflictMessage := '';
    try
      Query.Edit;
      Query.FieldByName('price').AsCurrency := OriginalPrice + 2;
      Query.Post;
    except
      on E: EFDException do
      begin
        ConflictRaised := True;
        ConflictMessage := E.Message;
        if Query.State in dsEditModes then
          Query.Cancel;
      end;
    end;
    Check(ConflictRaised, 'Update stale não produziu conflito FireDAC.');
    Check(Pos('updated [0] instead of [1]', LowerCase(ConflictMessage)) > 0,
      'A exceção não confirmou zero linhas no update otimista: ' + ConflictMessage);
    Check(Currency(ConnectionB.ExecSQLScalar(
      'SELECT price FROM product WHERE id = :id', [1])) = OriginalPrice,
      'Update stale sobrescreveu o preço.');
    Check(ConnectionB.ExecSQLScalar(
      'SELECT version FROM product WHERE id = :id', [1]) = OriginalVersion + 1,
      'Versão concorrente não permaneceu no servidor.');
    Writeln('EX-08-05 aprovado: OLD_version converteu zero linhas em conflito.');
  finally
    if ConnectionB.Connected and (OriginalVersion > 0) then
      ConnectionB.ExecSQL(
        'UPDATE product SET price = :price, version = :version WHERE id = :id',
        [OriginalPrice, OriginalVersion, 1]);
    UpdateSQL.Free;
    Query.Free;
    ConnectionB.Free;
    ConnectionA.Free;
    LinkB.Free;
    LinkA.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter08Checks calculated|lookup|aggregate|join|conflict');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'calculated') then
      RunCalculated
    else if SameText(ParamStr(1), 'lookup') then
      RunLookup
    else if SameText(ParamStr(1), 'aggregate') then
      RunAggregate
    else if SameText(ParamStr(1), 'join') then
      RunJoinUpdate
    else if SameText(ParamStr(1), 'conflict') then
      RunExplicitConflict
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
