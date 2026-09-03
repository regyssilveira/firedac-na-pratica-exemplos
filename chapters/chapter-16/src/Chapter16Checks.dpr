program Chapter16Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Variants,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.UI.Intf,
  FireDAC.Phys,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.ConsoleUI.Wait,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then raise Exception.Create(AMessage);
end;

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function IsFirebird: Boolean;
begin
  Result := SameText(RequiredEnvironment('CH16_DRIVER'), 'FB');
end;

procedure ConfigureConnection(AConnection: TFDConnection; ALink: TFDPhysFBDriverLink);
begin
  AConnection.LoginPrompt := False;
  AConnection.UpdateOptions.LockWait := False;
  if IsFirebird then
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH16_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
    AConnection.Params.Values['BusyTimeout'] := '500';
  end;
end;

function NewConnection(ALink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    ConfigureConnection(Result, ALink);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

procedure DeleteOrders(AConnection: TFDConnection; AFirst, ALast: Int64);
begin
  AConnection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id BETWEEN :a AND :b', [AFirst, ALast]);
  AConnection.ExecSQL('DELETE FROM sales_order WHERE id BETWEEN :a AND :b', [AFirst, ALast]);
end;

procedure PrepareOrders(AConnection: TFDConnection);
begin
  DeleteOrders(AConnection, 160001, 160002);
  AConnection.ExecSQL('INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
    'VALUES (160001, ''EX-16-A'', ''PENDING'', 25)');
  AConnection.ExecSQL('INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
    'VALUES (160002, ''EX-16-B'', ''PENDING'', 30)');
  AConnection.ExecSQL('INSERT INTO sales_order_item ' +
    '(id, order_id, line_no, product_id, quantity, unit_price) ' +
    'VALUES (160101, 160001, 1, 1, 1, 10)');
end;

procedure RunJournal;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
  Changed: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.CachedUpdates := True;
    Query.UpdateOptions.KeyFields := 'id';
    Query.SQL.Text := 'SELECT id, sku, name, category_id, price, active, version ' +
      'FROM product WHERE id IN (1, 2, 3) ORDER BY id';
    Query.Open;
    Query.First;
    Query.Edit;
    Query.FieldByName('name').AsString := 'Alterado no journal';
    Query.Post;
    Query.Next;
    Query.Delete;
    Query.Append;
    Query.FieldByName('id').AsLargeInt := 169999;
    Query.FieldByName('sku').AsString := 'EX16-JOURNAL';
    Query.FieldByName('name').AsString := 'Novo no journal';
    Query.FieldByName('category_id').AsLargeInt := 1;
    Query.FieldByName('price').AsCurrency := 10;
    if IsFirebird then Query.FieldByName('active').AsBoolean := True
    else Query.FieldByName('active').AsInteger := 1;
    Query.FieldByName('version').AsLargeInt := 1;
    Query.Post;
    Check(Query.ChangeCount = 3, 'Journal não registrou modificar/excluir/inserir.');
    Query.FilterChanges := [rtModified, rtInserted, rtDeleted];
    Changed := Query.RecordCount;
    Check(Changed = 3, 'FilterChanges não expôs três alterações.');
    Query.FilterChanges := [rtUnmodified, rtModified, rtInserted];
    Query.CancelUpdates;
    Check(not Query.UpdatesPending, 'CancelUpdates não esvaziou o journal.');
    Writeln('EX-16-01 aprovado: três estados inspecionados e cancelados localmente.');
  finally
    Query.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunUndo;
var
  Table: TFDMemTable;
  Point: Int64;
begin
  Table := TFDMemTable.Create(nil);
  try
    Table.FieldDefs.Add('id', ftInteger, 0, True);
    Table.FieldDefs.Add('name', ftString, 40, True);
    Table.CreateDataSet;
    Table.CachedUpdates := True;
    Table.AppendRecord([1, 'Original']);
    Table.CommitUpdates;
    Point := Table.SavePoint;
    Table.First;
    Table.Edit;
    Table.FieldByName('name').AsString := 'Editado';
    Table.Post;
    Table.AppendRecord([2, 'Temporário']);
    Check(Table.ChangeCount = 2, 'Duas mudanças locais eram esperadas.');
    Table.UndoLastChange(True);
    Check((Table.RecordCount = 1) and (Table.ChangeCount = 1),
      'UndoLastChange não removeu apenas a última inserção.');
    Table.SavePoint := Point;
    Check((Table.FieldByName('name').AsString = 'Original') and
      not Table.UpdatesPending, 'Retorno ao SavePoint não restaurou a base.');
    Table.Edit;
    Table.FieldByName('name').AsString := 'Descartar';
    Table.Post;
    Table.CancelUpdates;
    Check(Table.FieldByName('name').AsString = 'Original',
      'CancelUpdates não descartou a edição final.');
    Writeln('EX-16-02 aprovado: undo, savepoint e cancelamento têm escopos distintos.');
  finally
    Table.Free;
  end;
end;

procedure RunConflict;
var
  Link: TFDPhysFBDriverLink;
  Main, Other: TFDConnection;
  Query: TFDQuery;
  UpdateSQL: TFDUpdateSQL;
  Errors: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Main := NewConnection(Link);
  Other := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  UpdateSQL := TFDUpdateSQL.Create(nil);
  try
    PrepareOrders(Main);
    Query.Connection := Main;
    Query.CachedUpdates := True;
    Query.UpdateOptions.KeyFields := 'id';
    Query.UpdateOptions.CountUpdatedRecords := True;
    Query.SQL.Text := 'SELECT id, idempotency_key, order_status, total ' +
      'FROM sales_order WHERE id = 160001';
    UpdateSQL.Connection := Main;
    UpdateSQL.ModifySQL.Text := 'UPDATE sales_order SET total = :NEW_total ' +
      'WHERE id = :OLD_id AND total = :OLD_total';
    Query.UpdateObject := UpdateSQL;
    Query.Open;
    Query.Edit;
    Query.FieldByName('total').AsCurrency := 26;
    Query.Post;
    Other.ExecSQL('UPDATE sales_order SET total = 27 WHERE id = 160001');
    Main.StartTransaction;
    try
      Errors := Query.ApplyUpdates(0);
      Check(Errors > 0, 'Conflito otimista não foi detectado.');
      Query.FilterChanges := [rtModified, rtHasErrors];
      Check(Query.RecordCount = 1, 'Linha conflitante não recebeu RowError.');
      Check(Query.RowError <> nil, 'RowError não foi associado ao conflito.');
      Query.FilterChanges := [rtUnmodified, rtModified, rtInserted];
      Main.Rollback;
    except
      if Main.InTransaction then Main.Rollback;
      raise;
    end;
    Check(Query.UpdatesPending, 'Conflito apagou a intenção local.');
    Check(Main.ExecSQLScalar('SELECT total FROM sales_order WHERE id = 160001') = 27,
      'Valor concorrente foi sobrescrito.');
    Query.CancelUpdates;
    Writeln('EX-16-03 aprovado: conflito gerou erro por linha e preservou a intenção.');
  finally
    UpdateSQL.Free;
    Query.Free;
    DeleteOrders(Main, 160001, 160002);
    Other.Free;
    Main.Free;
    Link.Free;
  end;
end;

procedure RunTransaction;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
  Errors: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    PrepareOrders(Connection);
    Query.Connection := Connection;
    Query.CachedUpdates := True;
    Query.UpdateOptions.KeyFields := 'id';
    Query.SQL.Text := 'SELECT id, idempotency_key, order_status, total ' +
      'FROM sales_order WHERE id BETWEEN 160001 AND 160002 ORDER BY id';
    Query.Open;
    Query.First;
    Query.Edit;
    Query.FieldByName('total').AsCurrency := 26;
    Query.Post;
    Query.Next;
    Query.Edit;
    Query.FieldByName('total').AsCurrency := 31;
    Query.Post;
    Connection.StartTransaction;
    Errors := Query.ApplyUpdates(0);
    Check(Errors = 0, 'Primeiro apply retornou erros.');
    Connection.Rollback;
    Check(Query.UpdatesPending, 'Rollback eliminou o journal local.');
    Check(Connection.ExecSQLScalar('SELECT SUM(total) FROM sales_order ' +
      'WHERE id BETWEEN 160001 AND 160002') = 55, 'Rollback não restaurou o banco.');
    Connection.StartTransaction;
    try
      Errors := Query.ApplyUpdates(0);
      Check(Errors = 0, 'Nova tentativa após rollback retornou erros.');
      Connection.Commit;
      Query.CommitUpdates;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar('SELECT SUM(total) FROM sales_order ' +
      'WHERE id BETWEEN 160001 AND 160002') = 57, 'Commit não persistiu as duas edições.');
    Check(not Query.UpdatesPending, 'CommitUpdates não encerrou o journal.');
    Writeln('EX-16-04 aprovado: rollback preservou journal; retry/commit o encerrou.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    Query.Free;
    DeleteOrders(Connection, 160001, 160002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunCentralized;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Adapter: TFDSchemaAdapter;
  Errors: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Adapter := TFDSchemaAdapter.Create(nil);
  try
    PrepareOrders(Connection);
    Master.Connection := Connection;
    Master.SchemaAdapter := Adapter;
    Master.CachedUpdates := True;
    Master.UpdateOptions.KeyFields := 'id';
    Master.SQL.Text := 'SELECT id, idempotency_key, order_status, total ' +
      'FROM sales_order WHERE id = 160001';
    Detail.Connection := Connection;
    Detail.SchemaAdapter := Adapter;
    Detail.CachedUpdates := True;
    Detail.UpdateOptions.KeyFields := 'id';
    Detail.SQL.Text := 'SELECT id, order_id, line_no, product_id, quantity, unit_price ' +
      'FROM sales_order_item WHERE order_id = 160001 ORDER BY line_no';
    Detail.IndexFieldNames := 'order_id';
    Source.DataSet := Master;
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Master.Open;
    Detail.Open;
    Master.Edit;
    Master.FieldByName('total').AsCurrency := 26;
    Master.Post;
    Detail.AppendRecord([Int64(160199), Int64(160001), 99, Int64(1), 0, Currency(10)]);
    Connection.StartTransaction;
    try
      Errors := Adapter.ApplyUpdates(0);
      Check(Errors > 0, 'Detalhe inválido deveria falhar.');
      Connection.Rollback;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Master.UpdatesPending and Detail.UpdatesPending,
      'Rollback não preservou os dois journals do adapter.');
    Check(Connection.ExecSQLScalar('SELECT total FROM sales_order WHERE id = 160001') = 25,
      'Rollback do grafo não restaurou o mestre.');
    Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM sales_order_item WHERE id = 160199') = 0,
      'Detalhe inválido ficou persistido.');
    Adapter.CancelUpdates;
    Writeln('EX-16-05 aprovado: falha do detalhe reverteu o grafo e preservou journals.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    Detail.Free;
    Source.Free;
    Master.Free;
    Adapter.Free;
    DeleteOrders(Connection, 160001, 160002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter16Checks journal|undo|conflict|transaction|centralized');
end;

begin
  try
    FFDGUIxProvider := 'Console';
    if ParamCount <> 1 then begin ShowUsage; ExitCode := 2; end
    else if SameText(ParamStr(1), 'journal') then RunJournal
    else if SameText(ParamStr(1), 'undo') then RunUndo
    else if SameText(ParamStr(1), 'conflict') then RunConflict
    else if SameText(ParamStr(1), 'transaction') then RunTransaction
    else if SameText(ParamStr(1), 'centralized') then RunCentralized
    else begin ShowUsage; ExitCode := 2; end;
  except
    on E: Exception do begin Writeln(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
