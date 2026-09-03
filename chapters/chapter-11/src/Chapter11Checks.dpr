program Chapter11Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  Winapi.Windows,
  Vcl.Forms,
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
  FireDAC.VCLUI.Wait,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

type
  TExecutionProbe = class
  private
    FCount: Integer;
  public
    procedure CountExecution(ADataSet: TFDDataSet);
    property Count: Integer read FCount;
  end;

procedure TExecutionProbe.CountExecution(ADataSet: TFDDataSet);
begin
  Inc(FCount);
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
  Result := SameText(RequiredEnvironment('CH11_DRIVER'), 'FB');
end;

procedure ConfigureConnection(AConnection: TFDConnection;
  AFBLink: TFDPhysFBDriverLink);
begin
  AConnection.LoginPrompt := False;
  AConnection.UpdateOptions.LockWait := False;
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH11_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
    AConnection.Params.Values['BusyTimeout'] := '100';
  end;
end;

function NewConnection(AFBLink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    ConfigureConnection(Result, AFBLink);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

procedure DeleteOrders(AConnection: TFDConnection; AFirstId, ALastId: Int64);
begin
  AConnection.ExecSQL(
    'DELETE FROM outbox_event WHERE aggregate_id BETWEEN :first_id AND :last_id',
    [AFirstId, ALastId]);
  AConnection.ExecSQL(
    'DELETE FROM sales_order WHERE id BETWEEN :first_id AND :last_id',
    [AFirstId, ALastId]);
end;

procedure PrepareTwoOrders(AConnection: TFDConnection);
begin
  DeleteOrders(AConnection, 111001, 111002);
  AConnection.StartTransaction;
  try
    AConnection.ExecSQL(
      'INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
      'VALUES (111001, ''EX-11-A'', ''PENDING'', 25)');
    AConnection.ExecSQL(
      'INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
      'VALUES (111002, ''EX-11-B'', ''PENDING'', 30)');
    AConnection.ExecSQL(
      'INSERT INTO sales_order_item ' +
      '(id, order_id, line_no, product_id, quantity, unit_price) ' +
      'VALUES (111101, 111001, 1, 1, 1, 10)');
    AConnection.ExecSQL(
      'INSERT INTO sales_order_item ' +
      '(id, order_id, line_no, product_id, quantity, unit_price) ' +
      'VALUES (111102, 111001, 2, 2, 1, 15)');
    AConnection.ExecSQL(
      'INSERT INTO sales_order_item ' +
      '(id, order_id, line_no, product_id, quantity, unit_price) ' +
      'VALUES (111103, 111002, 1, 3, 1, 30)');
    AConnection.Commit;
  except
    if AConnection.InTransaction then AConnection.Rollback;
    raise;
  end;
end;

procedure RunParameterized;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SQL.Text :=
      'SELECT id, idempotency_key FROM sales_order ' +
      'WHERE id BETWEEN 111001 AND 111002 ORDER BY id';
    Source.DataSet := Master;
    Detail.Connection := Connection;
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no, product_id, quantity, unit_price ' +
      'FROM sales_order_item WHERE order_id = :id ORDER BY line_no';
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Master.Open;
    Detail.Open;
    Check(Master.FieldByName('id').AsLargeInt = 111001, 'Mestre inicial incorreto.');
    Check(Detail.RecordCount = 2, 'Primeiro mestre não exibiu dois detalhes.');
    Check(Detail.FieldByName('order_id').AsLargeInt = 111001,
      'Detalhe inicial pertence a outro mestre.');
    Master.Next;
    Check(Detail.RecordCount = 1, 'Segundo mestre não exibiu um detalhe.');
    Check(Detail.FieldByName('order_id').AsLargeInt = 111002,
      'Parâmetro não acompanhou a navegação do mestre.');
    Check(SameText(Detail.ActualDetailFields, 'order_id'),
      'ActualDetailFields não resolveu order_id.');
    Writeln('EX-11-01 aprovado: parâmetro acompanhou dois mestres e ActualDetailFields.');
  finally
    Detail.Free;
    Source.Free;
    Master.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunRange;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SQL.Text :=
      'SELECT id FROM sales_order WHERE id BETWEEN 111001 AND 111002 ORDER BY id';
    Detail.Connection := Connection;
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no FROM sales_order_item ' +
      'WHERE order_id BETWEEN 111001 AND 111002 ORDER BY order_id, line_no';
    Detail.IndexFieldNames := 'order_id';
    Source.DataSet := Master;
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Master.Open;
    Detail.Open;
    Check(Detail.RecordCount = 2, 'Range inicial não selecionou dois detalhes.');
    Master.Next;
    Check(Detail.RecordCount = 1, 'Range local não acompanhou o segundo mestre.');
    Master.First;
    Check(Detail.RecordCount = 2, 'Range local não retornou ao primeiro mestre.');
    Check(SameText(Detail.IndexFieldNames, 'order_id'), 'Índice do range foi alterado.');
    Writeln('EX-11-02 aprovado: um cache de três linhas serviu ranges 2/1/2.');
  finally
    Detail.Free;
    Source.Free;
    Master.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunGeneratedKey;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  GeneratedId: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    Connection.ExecSQL(
      'DELETE FROM sales_order WHERE idempotency_key = ''EX-11-GENERATED''');
    Connection.StartTransaction;
    try
      Connection.ExecSQL(
        'INSERT INTO sales_order (idempotency_key, order_status, total) ' +
        'VALUES (''EX-11-GENERATED'', ''PENDING'', 30)');
      GeneratedId := Connection.ExecSQLScalar(
        'SELECT id FROM sales_order WHERE idempotency_key = ''EX-11-GENERATED''');
      Check(GeneratedId > 0, 'Banco não devolveu uma identidade válida.');
      Connection.ExecSQL(
        'INSERT INTO sales_order_item ' +
        '(id, order_id, line_no, product_id, quantity, unit_price) ' +
        'VALUES (113101, :order_id, 1, 3, 1, 30)', [GeneratedId]);
      Connection.Commit;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order_item WHERE order_id = :id', [GeneratedId]) = 1,
      'Detalhe não recebeu a chave gerada.');
    Writeln(Format('EX-11-03 aprovado: chave gerada %d propagada ao detalhe.',
      [GeneratedId]));
  finally
    if Connection.InTransaction then Connection.Rollback;
    Connection.ExecSQL(
      'DELETE FROM sales_order WHERE idempotency_key = ''EX-11-GENERATED''');
    Connection.Free;
    Link.Free;
  end;
end;

procedure DefineCompositeMaster(ATable: TFDMemTable);
begin
  ATable.FieldDefs.Add('company_id', ftInteger);
  ATable.FieldDefs.Add('order_id', ftInteger);
  ATable.FieldDefs.Add('description', ftString, 40);
  ATable.CreateDataSet;
  ATable.AppendRecord([1, 10, 'C1-O10']);
  ATable.AppendRecord([2, 10, 'C2-O10']);
  ATable.First;
end;

procedure DefineCompositeDetail(ATable: TFDMemTable);
begin
  ATable.FieldDefs.Add('company_id', ftInteger);
  ATable.FieldDefs.Add('order_id', ftInteger);
  ATable.FieldDefs.Add('line_no', ftInteger);
  ATable.FieldDefs.Add('description', ftString, 40);
  ATable.CreateDataSet;
  ATable.AppendRecord([1, 10, 1, 'C1 item 1']);
  ATable.AppendRecord([1, 10, 2, 'C1 item 2']);
  ATable.AppendRecord([2, 10, 1, 'C2 item 1']);
  ATable.IndexFieldNames := 'company_id;order_id';
end;

procedure RunCompositeKey;
var
  Master, Detail: TFDMemTable;
  Source: TDataSource;
begin
  Master := TFDMemTable.Create(nil);
  Detail := TFDMemTable.Create(nil);
  Source := TDataSource.Create(nil);
  try
    DefineCompositeMaster(Master);
    DefineCompositeDetail(Detail);
    Source.DataSet := Master;
    Detail.MasterSource := Source;
    Detail.MasterFields := 'company_id;order_id';
    Detail.DetailFields := 'company_id;order_id';
    Check(Detail.RecordCount = 2, 'Chave composta não filtrou empresa 1.');
    Master.Next;
    Check(Detail.RecordCount = 1, 'Chave composta não separou empresa 2.');
    Check(SameText(Detail.ActualDetailFields, 'company_id;order_id'),
      'ActualDetailFields perdeu ordem da chave composta.');
    Writeln('EX-11-08 aprovado: chave composta distinguiu pedidos com mesmo número.');
  finally
    Detail.Free;
    Source.Free;
    Master.Free;
  end;
end;

procedure RunDetailCache;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Probe: TExecutionProbe;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Probe := TExecutionProbe.Create;
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SQL.Text :=
      'SELECT id FROM sales_order WHERE id BETWEEN 111001 AND 111002 ORDER BY id';
    Source.DataSet := Master;
    Detail.Connection := Connection;
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no FROM sales_order_item ' +
      'WHERE order_id = :id ORDER BY line_no';
    Detail.IndexFieldNames := 'order_id';
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Detail.FetchOptions.Cache := Detail.FetchOptions.Cache + [fiDetails];
    Detail.BeforeGetRecords := Probe.CountExecution;
    Master.Open;
    Detail.Open;
    Check(Detail.RecordCount = 2, 'Cache: primeiro mestre incorreto.');
    Master.Next;
    Check(Detail.RecordCount = 1, 'Cache: segundo mestre incorreto.');
    Master.First;
    Check(Detail.RecordCount = 2, 'Cache: retorno ao primeiro mestre incorreto.');
    Check(Detail.Table.Rows.Count = 3,
      Format('fiDetails deveria manter três linhas no DatS, manteve %d.',
        [Detail.Table.Rows.Count]));
    Writeln(Format(
      'EX-11-06 aprovado: navegação A/B/A preservou 3 linhas; callbacks=%d.',
      [Probe.Count]));
  finally
    Detail.Free;
    Probe.Free;
    Source.Free;
    Master.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunDetailDelay;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Probe: TExecutionProbe;
  Deadline: UInt64;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Probe := TExecutionProbe.Create;
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SQL.Text :=
      'SELECT id FROM sales_order WHERE id BETWEEN 111001 AND 111002 ORDER BY id';
    Source.DataSet := Master;
    Detail.Connection := Connection;
    Detail.SQL.Text :=
      'SELECT id, order_id FROM sales_order_item WHERE order_id = :id';
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Detail.FetchOptions.DetailDelay := 150;
    Detail.BeforeGetRecords := Probe.CountExecution;
    Master.Open;
    Detail.Open;
    Master.Next;
    Master.First;
    Master.Next;
    Deadline := GetTickCount64 + 400;
    repeat
      Application.ProcessMessages;
      Sleep(10);
    until GetTickCount64 >= Deadline;
    Check(Master.FieldByName('id').AsLargeInt = 111002,
      'Navegação rápida não terminou no segundo mestre.');
    Check(Detail.RecordCount = 1, 'Detalhe atrasado não carregou o mestre final.');
    Check(Probe.Count <= 2,
      Format('DetailDelay executou %d vezes durante navegação rápida.', [Probe.Count]));
    Writeln(Format('EX-11-07 aprovado: navegação rápida terminou com %d execução(ões).',
      [Probe.Count]));
  finally
    Detail.Free;
    Probe.Free;
    Source.Free;
    Master.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunNewMasterDetails;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Adapter: TFDSchemaAdapter;
  Count: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Adapter := TFDSchemaAdapter.Create(nil);
  try
    Master.Connection := Connection;
    Master.SchemaAdapter := Adapter;
    Master.CachedUpdates := True;
    Master.SQL.Text :=
      'SELECT id, idempotency_key, order_status, total FROM sales_order WHERE id < 0';
    Detail.Connection := Connection;
    Detail.SchemaAdapter := Adapter;
    Detail.CachedUpdates := True;
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no, product_id, quantity, unit_price ' +
      'FROM sales_order_item WHERE order_id < 0';
    Detail.IndexFieldNames := 'order_id';
    Source.DataSet := Master;
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Detail.FetchOptions.DetailCascade := True;
    Master.Open;
    Detail.Open;
    Master.AppendRecord([-1001, 'EX-11-TEMP', 'PENDING', 30]);
    Detail.AppendRecord([-1101, -1001, 1, 1, 1, 10]);
    Detail.AppendRecord([-1102, -1001, 2, 2, 1, 10]);
    Detail.AppendRecord([-1103, -1001, 3, 3, 1, 10]);
    Master.Edit;
    Master.FieldByName('id').AsLargeInt := 119001;
    Master.Post;
    Detail.First;
    Count := 0;
    while not Detail.Eof do
    begin
      Check(Detail.FieldByName('order_id').AsLargeInt = 119001,
        'DetailCascade não propagou a chave definitiva.');
      Inc(Count);
      Detail.Next;
    end;
    Check(Count = 3, 'Quantidade de detalhes mudou durante a cascata.');
    Writeln('EX-11-09 aprovado: chave temporária foi propagada a três detalhes.');
  finally
    Detail.Free;
    Source.Free;
    Master.Free;
    Adapter.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunCascade;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Adapter: TFDSchemaAdapter;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Adapter := TFDSchemaAdapter.Create(nil);
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SchemaAdapter := Adapter;
    Master.CachedUpdates := True;
    Master.SQL.Text :=
      'SELECT id, idempotency_key, order_status, total FROM sales_order ' +
      'WHERE id = 111001';
    Detail.Connection := Connection;
    Detail.SchemaAdapter := Adapter;
    Detail.CachedUpdates := True;
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no, product_id, quantity, unit_price ' +
      'FROM sales_order_item WHERE order_id = 111001 ORDER BY line_no';
    Detail.IndexFieldNames := 'order_id';
    Source.DataSet := Master;
    Detail.MasterSource := Source;
    Detail.MasterFields := 'id';
    Detail.DetailFields := 'order_id';
    Detail.FetchOptions.DetailCascade := True;
    Master.Open;
    Detail.Open;
    Check(Detail.RecordCount = 2, 'Fixture local deveria conter dois detalhes.');
    Master.Delete;
    Check(Detail.RecordCount = 0,
      'DetailCascade não ocultou/excluiu os detalhes no cache local.');
    Adapter.CancelUpdates;

    Connection.ExecSQL('DELETE FROM sales_order WHERE id = 111001');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order_item WHERE order_id = 111001') = 0,
      'FK ON DELETE CASCADE não removeu os detalhes no servidor.');
    Writeln('EX-11-04 aprovado: cascatas local e do servidor foram verificadas separadamente.');
  finally
    Detail.Free;
    Source.Free;
    Master.Free;
    Adapter.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunAtomicAdapter;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Master, Detail: TFDQuery;
  Source: TDataSource;
  Adapter: TFDSchemaAdapter;
  ApplyFailed: Boolean;
  ErrorCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Master := TFDQuery.Create(nil);
  Detail := TFDQuery.Create(nil);
  Source := TDataSource.Create(nil);
  Adapter := TFDSchemaAdapter.Create(nil);
  try
    PrepareTwoOrders(Connection);
    Master.Connection := Connection;
    Master.SchemaAdapter := Adapter;
    Master.CachedUpdates := True;
    Master.UpdateOptions.KeyFields := 'id';
    Master.SQL.Text :=
      'SELECT id, idempotency_key, order_status, total FROM sales_order ' +
      'WHERE id = 111001';
    Detail.Connection := Connection;
    Detail.SchemaAdapter := Adapter;
    Detail.CachedUpdates := True;
    Detail.UpdateOptions.KeyFields := 'id';
    Detail.SQL.Text :=
      'SELECT id, order_id, line_no, product_id, quantity, unit_price ' +
      'FROM sales_order_item WHERE order_id = 111001 ORDER BY line_no';
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
    Detail.AppendRecord([115199, 111001, 99, 1, 0, 10]);

    ErrorCount := 0;
    Connection.StartTransaction;
    try
      try
        ErrorCount := Adapter.ApplyUpdates(0);
        ApplyFailed := ErrorCount > 0;
      except
        on E: Exception do
          ApplyFailed := True;
      end;
      Check(ApplyFailed, 'ApplyUpdates deveria rejeitar quantidade zero.');
      Connection.Rollback;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Master.UpdatesPending, 'Rollback apagou indevidamente o delta do mestre.');
    Check(Detail.UpdatesPending, 'Rollback apagou indevidamente o delta do detalhe.');
    Check(Connection.ExecSQLScalar(
      'SELECT total FROM sales_order WHERE id = 111001') = 25,
      'Rollback não restaurou o total persistido.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order_item WHERE id = 115199') = 0,
      'Rollback deixou o detalhe inválido persistido.');
    Adapter.CancelUpdates;
    Writeln(Format(
      'EX-11-05 aprovado: erro coordenado (%d) preservou deltas e rollback foi atômico.',
      [ErrorCount]));
  finally
    if Connection.InTransaction then Connection.Rollback;
    Detail.Free;
    Source.Free;
    Master.Free;
    Adapter.Free;
    DeleteOrders(Connection, 111001, 111002);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunConflictRetry;
var
  MainLink, OtherLink: TFDPhysFBDriverLink;
  Connection, OtherConnection: TFDConnection;
  OrderQuery: TFDQuery;
  UpdateSQL: TFDUpdateSQL;
  ConflictDetected: Boolean;
  ErrorCount: Integer;
  DesiredTotal: Currency;
begin
  MainLink := TFDPhysFBDriverLink.Create(nil);
  OtherLink := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(MainLink);
  OtherConnection := NewConnection(OtherLink);
  OrderQuery := TFDQuery.Create(nil);
  UpdateSQL := TFDUpdateSQL.Create(nil);
  try
    PrepareTwoOrders(Connection);
    OrderQuery.Connection := Connection;
    OrderQuery.CachedUpdates := True;
    OrderQuery.UpdateOptions.KeyFields := 'id';
    OrderQuery.UpdateOptions.CountUpdatedRecords := True;
    OrderQuery.SQL.Text :=
      'SELECT id, idempotency_key, order_status, total FROM sales_order ' +
      'WHERE id = 111001';
    UpdateSQL.Connection := Connection;
    UpdateSQL.ModifySQL.Text :=
      'UPDATE sales_order SET total = :NEW_total ' +
      'WHERE id = :OLD_id AND total = :OLD_total';
    OrderQuery.UpdateObject := UpdateSQL;
    OrderQuery.Open;
    DesiredTotal := 26;
    OrderQuery.Edit;
    OrderQuery.FieldByName('total').AsCurrency := DesiredTotal;
    OrderQuery.Post;

    OtherConnection.ExecSQL(
      'UPDATE sales_order SET total = 27 WHERE id = 111001');
    Connection.StartTransaction;
    try
      try
        ErrorCount := OrderQuery.ApplyUpdates(0);
        ConflictDetected := ErrorCount > 0;
      except
        on E: Exception do
          ConflictDetected := True;
      end;
      Check(ConflictDetected, 'Atualização otimista não detectou a versão concorrente.');
      Connection.Rollback;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(OrderQuery.UpdatesPending,
      'Rollback do conflito descartou a intenção local antes da decisão.');
    Check(Connection.ExecSQLScalar(
      'SELECT total FROM sales_order WHERE id = 111001') = 27,
      'Conflito sobrescreveu o valor concorrente.');

    OrderQuery.CancelUpdates;
    OrderQuery.Close;
    OrderQuery.Open;
    Check(OrderQuery.FieldByName('total').AsCurrency = 27,
      'Releitura não trouxe a versão concorrente.');
    OrderQuery.Edit;
    OrderQuery.FieldByName('total').AsCurrency := DesiredTotal;
    OrderQuery.Post;
    Connection.StartTransaction;
    try
      ErrorCount := OrderQuery.ApplyUpdates(0);
      Check(ErrorCount = 0, 'Nova tentativa encontrou erro inesperado.');
      Connection.Commit;
      OrderQuery.CommitUpdates;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT total FROM sales_order WHERE id = 111001') = DesiredTotal,
      'Nova tentativa não persistiu a decisão local.');
    Check(not OrderQuery.UpdatesPending,
      'CommitUpdates não encerrou o journal após o commit real.');
    Writeln('EX-11-10 aprovado: conflito preservado, relido e resolvido em nova tentativa.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    UpdateSQL.Free;
    OrderQuery.Free;
    DeleteOrders(Connection, 111001, 111002);
    OtherConnection.Free;
    Connection.Free;
    OtherLink.Free;
    MainLink.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter11Checks parameter|range|generated|cascade|atomic|' +
    'cache|delay|composite|newdetails|conflict');
end;

begin
  try
    FFDGUIxProvider := 'Forms';
    Application.Initialize;
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'parameter') then RunParameterized
    else if SameText(ParamStr(1), 'range') then RunRange
    else if SameText(ParamStr(1), 'generated') then RunGeneratedKey
    else if SameText(ParamStr(1), 'cascade') then RunCascade
    else if SameText(ParamStr(1), 'atomic') then RunAtomicAdapter
    else if SameText(ParamStr(1), 'cache') then RunDetailCache
    else if SameText(ParamStr(1), 'delay') then RunDetailDelay
    else if SameText(ParamStr(1), 'composite') then RunCompositeKey
    else if SameText(ParamStr(1), 'newdetails') then RunNewMasterDetails
    else if SameText(ParamStr(1), 'conflict') then RunConflictRetry
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
