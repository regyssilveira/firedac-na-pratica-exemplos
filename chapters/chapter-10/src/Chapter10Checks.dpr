program Chapter10Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Variants,
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
  Result := SameText(RequiredEnvironment('CH10_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH10_SQLITE_DATABASE');
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

procedure DeleteFixture(AConnection: TFDConnection; AOrderId: Int64);
begin
  AConnection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = :id', [AOrderId]);
  AConnection.ExecSQL('DELETE FROM sales_order WHERE id = :id', [AOrderId]);
end;

procedure ResetInventory(AConnection: TFDConnection);
begin
  AConnection.ExecSQL('UPDATE inventory SET quantity = 100 WHERE product_id IN (1, 2, 3)');
end;

procedure RunCommitOrder;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
const
  OrderId = 101001;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    DeleteFixture(Connection, OrderId);
    ResetInventory(Connection);
    Connection.StartTransaction;
    try
      Connection.ExecSQL(
        'INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
        'VALUES (:id, :key, :status, :total)',
        [OrderId, 'EX-10-01', 'CONFIRMED', 20.00]);
      Connection.ExecSQL(
        'INSERT INTO sales_order_item ' +
        '(id, order_id, line_no, product_id, quantity, unit_price) ' +
        'VALUES (:item_id, :order_id, 1, 1, 2, 10.00)',
        [101101, OrderId]);
      Check(Connection.ExecSQL(
        'UPDATE inventory SET quantity = quantity - 2 ' +
        'WHERE product_id = 1 AND quantity >= 2') = 1,
        'Baixa de estoque não afetou uma linha.');
      Connection.ExecSQL(
        'INSERT INTO outbox_event ' +
        '(id, aggregate_type, aggregate_id, event_type, payload) ' +
        'VALUES (:id, :kind, :aggregate_id, :event_type, :payload)',
        [101201, 'ORDER', OrderId, 'ORDER_CONFIRMED', '{"order_id":101001}']);
      Connection.Commit;
    except
      if Connection.InTransaction then
        Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order WHERE id = :id', [OrderId]) = 1,
      'Cabeçalho não foi confirmado.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order_item WHERE order_id = :id', [OrderId]) = 1,
      'Item não foi confirmado.');
    Check(Connection.ExecSQLScalar(
      'SELECT quantity FROM inventory WHERE product_id = 1') = 98,
      'Estoque confirmado divergiu de 98.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event WHERE aggregate_id = :id', [OrderId]) = 1,
      'Evento outbox não foi confirmado.');
    Writeln('EX-10-01 aprovado: pedido, item, estoque e outbox confirmados juntos.');
  finally
    if Connection.InTransaction then
      Connection.Rollback;
    DeleteFixture(Connection, OrderId);
    ResetInventory(Connection);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunRollbackDetail;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  ConstraintRaised: Boolean;
const
  OrderId = 102001;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    DeleteFixture(Connection, OrderId);
    ConstraintRaised := False;
    Connection.StartTransaction;
    try
      Connection.ExecSQL(
        'INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
        'VALUES (:id, :key, :status, :total)',
        [OrderId, 'EX-10-02', 'PENDING', 10.00]);
      try
        Connection.ExecSQL(
          'INSERT INTO sales_order_item ' +
          '(id, order_id, line_no, product_id, quantity, unit_price) ' +
          'VALUES (:item_id, :order_id, 1, 1, 0, 10.00)',
          [102101, OrderId]);
      except
        on E: EFDDBEngineException do
          ConstraintRaised := True;
      end;
      Check(ConstraintRaised, 'A constraint de quantidade não rejeitou zero.');
      raise Exception.Create('Falha intencional após o detalhe inválido.');
    except
      if Connection.InTransaction then
        Connection.Rollback;
    end;
    Check(not Connection.InTransaction, 'Rollback deixou transação ativa.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order WHERE id = :id', [OrderId]) = 0,
      'Cabeçalho parcial permaneceu após rollback.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sales_order_item WHERE order_id = :id', [OrderId]) = 0,
      'Detalhe parcial permaneceu após rollback.');
    Writeln('EX-10-02 aprovado: constraint falhou e rollback removeu o cabeçalho.');
  finally
    if Connection.InTransaction then
      Connection.Rollback;
    DeleteFixture(Connection, OrderId);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunNestedSavepoint;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
const
  AggregateId = 103001;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    Connection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = :id', [AggregateId]);
    Connection.TxOptions.EnableNested := True;
    Connection.StartTransaction;
    try
      Connection.ExecSQL(
        'INSERT INTO outbox_event ' +
        '(id, aggregate_type, aggregate_id, event_type, payload) ' +
        'VALUES (103101, ''TEST'', :id, ''OUTER_BEFORE'', ''{}'')', [AggregateId]);
      Connection.StartTransaction;
      try
        Connection.ExecSQL(
          'INSERT INTO outbox_event ' +
          '(id, aggregate_type, aggregate_id, event_type, payload) ' +
          'VALUES (103102, ''TEST'', :id, ''INNER'', ''{}'')', [AggregateId]);
        Connection.Rollback;
      except
        if Connection.InTransaction then
          Connection.Rollback;
        raise;
      end;
      Check(Connection.InTransaction,
        'Rollback aninhado encerrou a transação externa.');
      Check(Connection.ExecSQLScalar(
        'SELECT COUNT(*) FROM outbox_event WHERE id = 103102') = 0,
        'Rollback do savepoint preservou a alteração interna.');
      Connection.ExecSQL(
        'INSERT INTO outbox_event ' +
        '(id, aggregate_type, aggregate_id, event_type, payload) ' +
        'VALUES (103103, ''TEST'', :id, ''OUTER_AFTER'', ''{}'')', [AggregateId]);
      Connection.Commit;
    except
      if Connection.InTransaction then
        Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event WHERE aggregate_id = :id', [AggregateId]) = 2,
      'Commit externo não preservou exatamente os dois eventos externos.');
    Writeln('EX-10-03 aprovado: rollback aninhado voltou ao savepoint; outer fez commit.');
  finally
    if Connection.InTransaction then
      Connection.Rollback;
    Connection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = :id', [AggregateId]);
    Connection.Free;
    Link.Free;
  end;
end;

function IsolationName(AIsolation: TFDTxIsolation): string;
begin
  case AIsolation of
    xiDirtyRead: Result := 'xiDirtyRead';
    xiReadCommitted: Result := 'xiReadCommitted';
    xiRepeatableRead: Result := 'xiRepeatableRead';
    xiSerializible: Result := 'xiSerializible';
  else
    Result := 'outro';
  end;
end;

procedure ObserveIsolation(AFirst, ASecond: TFDConnection;
  AIsolation: TFDTxIsolation);
var
  BeforeValue, AfterValue: Currency;
  WriterCommitted: Boolean;
begin
  AFirst.TxOptions.Isolation := AIsolation;
  AFirst.StartTransaction;
  try
    BeforeValue := AFirst.ExecSQLScalar('SELECT price FROM product WHERE id = 3');
    WriterCommitted := False;
    try
      ASecond.StartTransaction;
      ASecond.ExecSQL('UPDATE product SET price = price + 1 WHERE id = 3');
      ASecond.Commit;
      WriterCommitted := True;
    except
      on E: EFDDBEngineException do
      begin
        if ASecond.InTransaction then
          ASecond.Rollback;
      end;
    end;
    AfterValue := AFirst.ExecSQLScalar('SELECT price FROM product WHERE id = 3');
    Writeln(Format('EX-10-04 level=%s writer_commit=%s reread_changed=%s',
      [IsolationName(AIsolation), BoolToStr(WriterCommitted, True),
       BoolToStr(AfterValue <> BeforeValue, True)]));
  finally
    if ASecond.InTransaction then
      ASecond.Rollback;
    if AFirst.InTransaction then
      AFirst.Rollback;
  end;
end;

procedure RunIsolationMatrix;
var
  Link: TFDPhysFBDriverLink;
  First, Second: TFDConnection;
  Level: TFDTxIsolation;
const
  Levels: array[0..3] of TFDTxIsolation =
    (xiDirtyRead, xiReadCommitted, xiRepeatableRead, xiSerializible);
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  First := nil;
  Second := nil;
  try
    for Level in Levels do
    begin
      First := NewConnection(Link);
      Second := NewConnection(Link);
      try
        First.ExecSQL('UPDATE product SET price = 30 WHERE id = 3');
        ObserveIsolation(First, Second, Level);
      finally
        Second.Free;
        Second := nil;
        First.Free;
        First := nil;
      end;
    end;
    First := NewConnection(Link);
    First.ExecSQL('UPDATE product SET price = 30 WHERE id = 3');
    Check(First.ExecSQLScalar('SELECT price FROM product WHERE id = 3') = 30,
      'Preço do laboratório não foi restaurado.');
    Writeln('EX-10-04 aprovado: quatro isolamentos observados com duas sessões.');
  finally
    if (Second <> nil) and Second.InTransaction then Second.Rollback;
    if (First <> nil) and First.InTransaction then First.Rollback;
    Second.Free;
    First.Free;
    Link.Free;
  end;
end;

procedure ExecuteInTransaction(AConnection: TFDConnection; const AWork: TProc);
var
  OwnsTransaction: Boolean;
begin
  OwnsTransaction := not AConnection.InTransaction;
  if OwnsTransaction then
    AConnection.StartTransaction;
  try
    AWork();
    if OwnsTransaction then
      AConnection.Commit;
  except
    if OwnsTransaction and AConnection.InTransaction then
      AConnection.Rollback;
    raise;
  end;
end;

procedure RunTransactionHelper;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Failed: Boolean;
const
  AggregateId = 105001;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    Connection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = :id', [AggregateId]);
    ExecuteInTransaction(Connection,
      procedure
      begin
        Connection.ExecSQL(
          'INSERT INTO outbox_event ' +
          '(id, aggregate_type, aggregate_id, event_type, payload) ' +
          'VALUES (105101, ''TEST'', :id, ''OWNED_COMMIT'', ''{}'')', [AggregateId]);
      end);
    Check(not Connection.InTransaction, 'Helper dono não encerrou a transação.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event WHERE id = 105101') = 1,
      'Helper dono não confirmou seu trabalho.');

    Failed := False;
    try
      ExecuteInTransaction(Connection,
        procedure
        begin
          Connection.ExecSQL(
            'INSERT INTO outbox_event ' +
            '(id, aggregate_type, aggregate_id, event_type, payload) ' +
            'VALUES (105102, ''TEST'', :id, ''OWNED_ROLLBACK'', ''{}'')', [AggregateId]);
          raise Exception.Create('Falha intencional do callback.');
        end);
    except
      on E: Exception do
        Failed := SameText(E.Message, 'Falha intencional do callback.');
    end;
    Check(Failed, 'Helper não preservou a exceção do callback.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event WHERE id = 105102') = 0,
      'Helper não reverteu a transação da qual era dono.');

    Connection.StartTransaction;
    try
      ExecuteInTransaction(Connection,
        procedure
        begin
          Connection.ExecSQL(
            'INSERT INTO outbox_event ' +
            '(id, aggregate_type, aggregate_id, event_type, payload) ' +
            'VALUES (105103, ''TEST'', :id, ''PARTICIPANT'', ''{}'')', [AggregateId]);
        end);
      Check(Connection.InTransaction,
        'Helper participante confirmou a transação externa.');
      Connection.Rollback;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event WHERE id = 105103') = 0,
      'Rollback externo não removeu trabalho do participante.');
    Writeln('EX-10-05 aprovado: helper confirmou, reverteu e participou sem usurpar ownership.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    Connection.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = :id', [AggregateId]);
    Connection.Free;
    Link.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter10Checks commit|rollback|nested|isolation|helper');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'commit') then RunCommitOrder
    else if SameText(ParamStr(1), 'rollback') then RunRollbackDetail
    else if SameText(ParamStr(1), 'nested') then RunNestedSavepoint
    else if SameText(ParamStr(1), 'isolation') then RunIsolationMatrix
    else if SameText(ParamStr(1), 'helper') then RunTransactionHelper
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
