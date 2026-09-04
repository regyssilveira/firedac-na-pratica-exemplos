program Chapter05Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Diagnostics,
  Winapi.Windows,
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
  FireDAC.Comp.Client;

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
  Result := SameText(RequiredEnvironment('CH05_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH05_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

procedure WithConnection(const ATest: TProc<TFDConnection>);
var
  Connection: TFDConnection;
  FBLink: TFDPhysFBDriverLink;
begin
  Connection := TFDConnection.Create(nil);
  FBLink := TFDPhysFBDriverLink.Create(nil);
  try
    ConfigureConnection(Connection, FBLink);
    Connection.Open;
    ATest(Connection);
  finally
    Connection.Free;
    FBLink.Free;
  end;
end;

procedure RunList;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      PreviousKey, CurrentKey: string;
      Count: Integer;
    begin
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;
        Query.SQL.Text := '''
          SELECT id, sku, name, price, active
          FROM product
          WHERE active = :active
          ORDER BY name, id
          ''';
        Query.ParamByName('active').AsBoolean := True;
        Query.Open;
        Check(Query.FieldByName('id').DataType in [ftInteger, ftLargeint],
          'id não chegou como inteiro compatível.');
        Check(Query.FieldByName('price').DataType in
          [ftFloat, ftCurrency, ftBCD, ftFMTBcd],
          'price não chegou como tipo numérico compatível.');
        Count := 0;
        PreviousKey := '';
        while not Query.Eof do
        begin
          CurrentKey := Query.FieldByName('name').AsString + '|' +
            Format('%.20d', [Query.FieldByName('id').AsLargeInt]);
          Check((PreviousKey = '') or (CompareStr(PreviousKey, CurrentKey) <= 0),
            'A lista não respeitou ORDER BY name, id.');
          PreviousKey := CurrentKey;
          Inc(Count);
          Query.Next;
        end;
        Check(Count = 3, Format('Esperados 3 produtos; recebidos %d.', [Count]));
        Writeln(Format(
          'EX-05-01 aprovado: 3 linhas; id=%s; price=%s; ordem estável.',
          [Query.FieldByName('id').ClassName,
           Query.FieldByName('price').ClassName]));
      finally
        Query.Free;
      end;
    end);
end;

procedure RunDml;
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
        OriginalPrice := Connection.ExecSQLScalar(
          'SELECT price FROM product WHERE id = :id', [1]);
        Query.SQL.Text := '''
          UPDATE product
          SET price = :price, version = version + 1
          WHERE id = :id
          ''';
        Query.ParamByName('price').AsCurrency := OriginalPrice + 1;
        Query.ParamByName('id').AsLargeInt := 1;
        Query.ExecSQL;
        Check(Query.RowsAffected = 1, 'UPDATE conhecido não afetou exatamente 1 linha.');
        Query.ParamByName('id').AsLargeInt := 999999;
        Query.ExecSQL;
        Check(Query.RowsAffected = 0, 'UPDATE inexistente não retornou 0 linhas.');
        Writeln('EX-05-02 aprovado: ExecSQL distinguiu 1 de 0 linhas afetadas.');
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
      end;
    end);
end;

procedure RunReusableCommand;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Command: TFDCommand;
      Id: Integer;
    begin
      Command := TFDCommand.Create(nil);
      Connection.StartTransaction;
      try
        Command.Connection := Connection;
        Command.CommandText.Text :=
          'UPDATE product SET price = price + :delta WHERE id = :id';
        Command.ParamByName('delta').DataType := ftCurrency;
        Command.ParamByName('id').DataType := ftLargeint;
        Command.Prepare;
        Check(Command.Prepared, 'TFDCommand não permaneceu preparado.');
        for Id := 1 to 3 do
        begin
          Command.ParamByName('delta').AsCurrency := 0.10;
          Command.ParamByName('id').AsLargeInt := Id;
          Command.Execute;
          Check(Command.RowsAffected = 1,
            Format('Execução preparada para id %d não afetou 1 linha.', [Id]));
        end;
        Check(Command.Prepared, 'A reutilização perdeu a preparação do comando.');
        Writeln('EX-05-03 aprovado: um TFDCommand preparado executou 3 vezes.');
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Command.Free;
      end;
    end);
end;

procedure RunGeneratedKey;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      GeneratedId: Int64;
    begin
      Query := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Query.Connection := Connection;
        Query.SQL.Text :=
          'INSERT INTO product (sku, name, category_id, price, active) ' +
          'VALUES (:sku, :name, :category_id, :price, :active) RETURNING id';
        Query.ParamByName('sku').AsString := 'CH05-KEY-' + IntToStr(GetCurrentProcessId);
        Query.ParamByName('name').AsString := 'Produto com chave gerada';
        Query.ParamByName('category_id').AsLargeInt := 1;
        Query.ParamByName('price').AsCurrency := 12.34;
        Query.ParamByName('active').AsBoolean := True;
        Query.Open;
        Check(not Query.IsEmpty, 'INSERT RETURNING não devolveu linha.');
        GeneratedId := Query.FieldByName('id').AsLargeInt;
        Check(GeneratedId > 3, 'A chave gerada colidiu com o seed.');
        Check(Connection.ExecSQLScalar(
          'SELECT COUNT(*) FROM product WHERE id = :id', [GeneratedId]) = 1,
          'A chave retornada não identifica a linha inserida.');
        Writeln(Format(
          'EX-05-04 aprovado: INSERT RETURNING recuperou a chave %d.', [GeneratedId]));
      finally
        Query.Close;
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
      end;
    end);
end;

procedure ReadPage(Connection: TFDConnection; AOffset, APageSize: Integer;
  AIds: TList<Int64>; AKeys: TList<string>);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    if IsFirebird then
      Query.SQL.Text :=
        'SELECT id, name FROM product WHERE active = TRUE ORDER BY name, id ' +
        'OFFSET :row_offset ROWS FETCH NEXT :page_size ROWS ONLY'
    else
      Query.SQL.Text :=
        'SELECT id, name FROM product WHERE active = 1 ORDER BY name, id ' +
        'LIMIT :page_size OFFSET :row_offset';
    Query.ParamByName('row_offset').AsInteger := AOffset;
    Query.ParamByName('page_size').AsInteger := APageSize;
    Query.Open;
    while not Query.Eof do
    begin
      AIds.Add(Query.FieldByName('id').AsLargeInt);
      AKeys.Add(Query.FieldByName('name').AsString + '|' +
        Format('%.20d', [Query.FieldByName('id').AsLargeInt]));
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

procedure ReadKeysetPage(Connection: TFDConnection; const ALastName: string;
  ALastId: Int64; APageSize: Integer; AIds: TList<Int64>);
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    if IsFirebird then
      Query.SQL.Text :=
        'SELECT id, name FROM product WHERE active = TRUE AND ' +
        '((name > :last_name) OR (name = :last_name AND id > :last_id)) ' +
        'ORDER BY name, id FETCH FIRST :page_size ROWS ONLY'
    else
      Query.SQL.Text :=
        'SELECT id, name FROM product WHERE active = 1 AND ' +
        '((name > :last_name) OR (name = :last_name AND id > :last_id)) ' +
        'ORDER BY name, id LIMIT :page_size';
    Query.ParamByName('last_name').AsString := ALastName;
    Query.ParamByName('last_id').AsLargeInt := ALastId;
    Query.ParamByName('page_size').AsInteger := APageSize;
    Query.Open;
    while not Query.Eof do
    begin
      AIds.Add(Query.FieldByName('id').AsLargeInt);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

procedure RunPagination;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Page1, Page2, Keyset2: TList<Int64>;
      Keys1, Keys2: TList<string>;
      I: Integer;
      LastName: string;
      LastId: Int64;
    begin
      Page1 := TList<Int64>.Create;
      Page2 := TList<Int64>.Create;
      Keyset2 := TList<Int64>.Create;
      Keys1 := TList<string>.Create;
      Keys2 := TList<string>.Create;
      Connection.StartTransaction;
      try
        Connection.ExecSQL(
          'INSERT INTO product (id, sku, name, category_id, price, active) ' +
          'VALUES (:id, :sku, :name, :category_id, :price, :active)',
          [9001, 'CH05-PAGE-A', 'Produto repetido', 1, 1.00, True]);
        Connection.ExecSQL(
          'INSERT INTO product (id, sku, name, category_id, price, active) ' +
          'VALUES (:id, :sku, :name, :category_id, :price, :active)',
          [9002, 'CH05-PAGE-B', 'Produto repetido', 1, 2.00, True]);
        ReadPage(Connection, 0, 3, Page1, Keys1);
        ReadPage(Connection, 3, 3, Page2, Keys2);
        Check((Page1.Count = 3) and (Page2.Count = 2),
          'As páginas não dividiram as 5 linhas em 3 + 2.');
        for I := 0 to Page1.Count - 1 do
          Check(not Page2.Contains(Page1[I]), 'As páginas por offset se sobrepõem.');
        for I := 1 to Keys1.Count - 1 do
          Check(CompareStr(Keys1[I - 1], Keys1[I]) <= 0,
            'A primeira página não está ordenada.');
        Check(CompareStr(Keys1.Last, Keys2.First) <= 0,
          'A fronteira entre as páginas não está ordenada.');
        LastName := Copy(Keys1.Last, 1, Pos('|', Keys1.Last) - 1);
        LastId := Page1.Last;
        ReadKeysetPage(Connection, LastName, LastId, 3, Keyset2);
        Check((Keyset2.Count = Page2.Count),
          'A segunda página keyset tem tamanho divergente.');
        for I := 0 to Page2.Count - 1 do
          Check(Page2[I] = Keyset2[I],
            'Offset e keyset divergiram sem mutação concorrente.');
        Writeln('EX-05-05 aprovado: offset e keyset produziram fronteira estável.');
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Keys2.Free;
        Keys1.Free;
        Keyset2.Free;
        Page2.Free;
        Page1.Free;
      end;
    end);
end;

procedure PreparePaginationMass(AConnection: TFDConnection; ACount: Integer);
var
  Query: TFDQuery;
  I: Integer;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text :=
      'INSERT INTO product (id, sku, name, category_id, price, active) ' +
      'VALUES (:id, :sku, :name, :category_id, :price, :active)';
    Query.Params.ArraySize := ACount;
    for I := 0 to ACount - 1 do
    begin
      Query.ParamByName('id').AsLargeInts[I] := 100000 + Int64(I) * 2;
      Query.ParamByName('sku').AsStrings[I] := Format('BM03-%.6d', [I]);
      Query.ParamByName('name').AsStrings[I] := Format('Página %.6d', [I]);
      Query.ParamByName('category_id').AsLargeInts[I] := 1;
      Query.ParamByName('price').AsCurrencys[I] := 1;
      Query.ParamByName('active').AsBooleans[I] := True;
    end;
    Query.Execute(ACount, 0);
  finally
    Query.Free;
  end;
end;

procedure MeasurePaginationPage(AConnection: TFDConnection; AUseKeyset: Boolean;
  AOffset: Integer; ALastId: Int64; out AElapsedUs, AFirstId, AFinalId: Int64;
  out ACount: Integer);
const
  CPageSize = 50;
var
  Query: TFDQuery;
  Timer: TStopwatch;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    if AUseKeyset then
    begin
      if IsFirebird then
        Query.SQL.Text := 'SELECT id FROM product WHERE id > :last_id ' +
          'ORDER BY id FETCH FIRST :page_size ROWS ONLY'
      else
        Query.SQL.Text := 'SELECT id FROM product WHERE id > :last_id ' +
          'ORDER BY id LIMIT :page_size';
      Query.ParamByName('last_id').AsLargeInt := ALastId;
    end
    else
    begin
      if IsFirebird then
        Query.SQL.Text := 'SELECT id FROM product WHERE id >= 100000 ORDER BY id ' +
          'OFFSET :row_offset ROWS FETCH NEXT :page_size ROWS ONLY'
      else
        Query.SQL.Text := 'SELECT id FROM product WHERE id >= 100000 ORDER BY id ' +
          'LIMIT :page_size OFFSET :row_offset';
      Query.ParamByName('row_offset').AsInteger := AOffset;
    end;
    Query.ParamByName('page_size').AsInteger := CPageSize;
    Timer := TStopwatch.StartNew;
    Query.Open;
    Query.FetchAll;
    AElapsedUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    ACount := Query.RecordCount;
    Check(ACount = CPageSize, 'Página do BM-03 não contém 50 linhas.');
    Query.First;
    AFirstId := Query.FieldByName('id').AsLargeInt;
    Query.Last;
    AFinalId := Query.FieldByName('id').AsLargeInt;
  finally
    Query.Free;
  end;
end;

procedure RunPaginationBenchmark;
const
  CRowCount = 100000;
  COffset = 90000;
  CBoundaryId = 100000 + Int64(COffset - 1) * 2;
var
  OffsetUs, KeysetUs, IgnoredUs: Int64;
  OffsetFirst, OffsetLast, KeysetFirst, KeysetLast: Int64;
  MutatedOffsetFirst, MutatedOffsetLast, MutatedKeysetFirst, MutatedKeysetLast: Int64;
  Count: Integer;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    begin
      Connection.StartTransaction;
      try
        PreparePaginationMass(Connection, CRowCount);
        MeasurePaginationPage(Connection, False, COffset, 0,
          OffsetUs, OffsetFirst, OffsetLast, Count);
        MeasurePaginationPage(Connection, True, 0, CBoundaryId,
          KeysetUs, KeysetFirst, KeysetLast, Count);
        Check((OffsetFirst = KeysetFirst) and (OffsetLast = KeysetLast),
          'Offset e keyset divergiram antes da escrita concorrente simulada.');

        Connection.ExecSQL(
          'INSERT INTO product (id, sku, name, category_id, price, active) ' +
          'VALUES (100001, ''BM03-INSERT'', ''Inserido antes da fronteira'', 1, 1, :active)',
          [True]);
        MeasurePaginationPage(Connection, False, COffset, 0,
          IgnoredUs, MutatedOffsetFirst, MutatedOffsetLast, Count);
        MeasurePaginationPage(Connection, True, 0, CBoundaryId,
          IgnoredUs, MutatedKeysetFirst, MutatedKeysetLast, Count);
        Check(MutatedOffsetFirst = CBoundaryId,
          'Offset não expôs a duplicação esperada após inserção anterior.');
        Check((MutatedKeysetFirst = KeysetFirst) and
          (MutatedKeysetLast = KeysetLast),
          'Keyset mudou após inserção anterior à fronteira.');
        Writeln(Format('BM-03 rows=%d offset=%d page_size=50 offset_us=%d ' +
          'keyset_us=%d first_id=%d offset_stable=False keyset_stable=True',
          [CRowCount, COffset, OffsetUs, KeysetUs, KeysetFirst]));
      finally
        if Connection.InTransaction then
          Connection.Rollback;
      end;
    end);
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter05Checks list|dml|command|key|pagination|benchmark-pagination');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'list') then
      RunList
    else if SameText(ParamStr(1), 'dml') then
      RunDml
    else if SameText(ParamStr(1), 'command') then
      RunReusableCommand
    else if SameText(ParamStr(1), 'key') then
      RunGeneratedKey
    else if SameText(ParamStr(1), 'pagination') then
      RunPagination
    else if SameText(ParamStr(1), 'benchmark-pagination') then
      RunPaginationBenchmark
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
