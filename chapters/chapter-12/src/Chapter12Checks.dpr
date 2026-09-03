program Chapter12Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
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
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

type
  TAlertProbe = class
  private
    FCount: Integer;
    FLastName: string;
  public
    procedure Alert(ASender: TFDCustomEventAlerter;
      const AEventName: string; const AArgument: Variant);
    property Count: Integer read FCount;
    property LastName: string read FLastName;
  end;

procedure TAlertProbe.Alert(ASender: TFDCustomEventAlerter;
  const AEventName: string; const AArgument: Variant);
begin
  Inc(FCount);
  FLastName := AEventName;
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
  Result := SameText(RequiredEnvironment('CH12_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH12_SQLITE_DATABASE');
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

procedure DeleteFixture(AConnection: TFDConnection);
begin
  AConnection.ExecSQL(
    'DELETE FROM outbox_event WHERE aggregate_id BETWEEN 121001 AND 121009');
  AConnection.ExecSQL(
    'DELETE FROM sales_order WHERE id BETWEEN 121001 AND 121009');
end;

procedure PrepareOrder(AConnection: TFDConnection; AOrderId: Int64 = 121001);
begin
  DeleteFixture(AConnection);
  AConnection.StartTransaction;
  try
    AConnection.ExecSQL(
      'INSERT INTO sales_order (id, idempotency_key, order_status, total) ' +
      'VALUES (:id, :key, ''PENDING'', 0)',
      [AOrderId, 'EX-12-' + IntToStr(AOrderId)]);
    AConnection.ExecSQL(
      'INSERT INTO sales_order_item ' +
      '(id, order_id, line_no, product_id, quantity, unit_price) ' +
      'VALUES (121101, :id, 1, 1, 2, 10)', [AOrderId]);
    AConnection.ExecSQL(
      'INSERT INTO sales_order_item ' +
      '(id, order_id, line_no, product_id, quantity, unit_price) ' +
      'VALUES (121102, :id, 2, 2, 1, 15)', [AOrderId]);
    AConnection.Commit;
  except
    if AConnection.InTransaction then AConnection.Rollback;
    raise;
  end;
end;

procedure RunProcedure;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Proc: TFDStoredProc;
  RoutineCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Proc := TFDStoredProc.Create(nil);
  try
    PrepareOrder(Connection);
    if IsFirebird then
    begin
      Proc.Connection := Connection;
      Proc.StoredProcName := 'GET_ORDER_STATE';
      Proc.Prepare;
      Check(Proc.Params.Count = 3,
        Format('GET_ORDER_STATE deveria expor 3 parâmetros, expôs %d.',
          [Proc.Params.Count]));
      Check(Proc.ParamByName('P_ORDER_ID').ParamType = ptInput,
        'P_ORDER_ID não foi derivado como entrada.');
      Check(Proc.ParamByName('P_STATUS').ParamType = ptOutput,
        'P_STATUS não foi derivado como saída.');
      Check(Proc.ParamByName('P_TOTAL').ParamType = ptOutput,
        'P_TOTAL não foi derivado como saída.');
      Proc.ParamByName('P_ORDER_ID').AsLargeInt := 121001;
      Proc.ExecProc;
      Check(Proc.ParamByName('P_STATUS').AsString = 'PENDING',
        'Procedure devolveu status inesperado.');
      Check(Proc.ParamByName('P_TOTAL').AsCurrency = 0,
        'Procedure devolveu total inesperado.');
      Writeln('EX-12-01 aprovado: Firebird derivou IN/OUT e devolveu os valores.');
    end
    else
    begin
      RoutineCount := Connection.ExecSQLScalar(
        'SELECT COUNT(*) FROM sqlite_master WHERE type IN (''procedure'', ''function'')');
      Check(RoutineCount = 0, 'SQLite anunciou rotina persistente inexistente.');
      Writeln('EX-12-01 aprovado: SQLite declarou procedure IN/OUT indisponível.');
    end;
  finally
    Proc.Free;
    DeleteFixture(Connection);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunFunction;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
  Total: Currency;
  LineCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    PrepareOrder(Connection);
    Query.Connection := Connection;
    if IsFirebird then
      Query.SQL.Text :=
        'SELECT order_total(:id) AS calculated_total FROM rdb$database'
    else
      Query.SQL.Text :=
        'SELECT calculated_total FROM order_total_view WHERE order_id = :id';
    Query.ParamByName('id').AsLargeInt := 121001;
    Query.Open;
    Total := Query.FieldByName('calculated_total').AsCurrency;
    Check(Total = 35, 'Total calculado deveria ser 35.');
    Query.Close;

    if IsFirebird then
      Query.SQL.Text := 'SELECT * FROM order_lines(:id) ORDER BY p_line_no'
    else
      Query.SQL.Text :=
        'SELECT line_no, product_id, quantity, unit_price ' +
        'FROM sales_order_item WHERE order_id = :id ORDER BY line_no';
    Query.ParamByName('id').AsLargeInt := 121001;
    Query.Open;
    LineCount := 0;
    while not Query.Eof do
    begin
      Inc(LineCount);
      Query.Next;
    end;
    Check(LineCount = 2, 'Contrato tabular deveria devolver duas linhas.');
    if IsFirebird then
      Writeln('EX-12-02 aprovado: função escalar e procedure selecionável Firebird.')
    else
      Writeln('EX-12-02 aprovado: SQLite usou view e SELECT, sem fingir stored function.');
  finally
    Query.Free;
    DeleteFixture(Connection);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunMultipleResults;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    if IsFirebird then
      Query.SQL.Text := 'SELECT 1 AS result_no FROM rdb$database'
    else
      Query.SQL.Text := 'SELECT 1 AS result_no';
    Query.Open;
    Check(Query.FieldByName('result_no').AsInteger = 1,
      'Primeiro resultado inesperado.');
    Query.NextRecordSet;
    Check(not Query.Active,
      'Comando de um único SELECT anunciou segundo recordset.');
    Writeln('EX-12-03 aprovado: fim dos resultados detectado; múltiplos sets não presumidos.');
  finally
    Query.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure CloseOrderSQLite(AConnection: TFDConnection; AOrderId: Int64;
  const AOperationKey: string; out AStatus: string; out ATotal: Currency;
  out AChanged: Boolean);
begin
  AStatus := VarToStr(AConnection.ExecSQLScalar(
    'SELECT order_status FROM sales_order WHERE id = :id', [AOrderId]));
  ATotal := AConnection.ExecSQLScalar(
    'SELECT calculated_total FROM order_total_view WHERE order_id = :id', [AOrderId]);
  AChanged := not SameText(AStatus, 'CLOSED');
  if AChanged then
  begin
    AConnection.ExecSQL(
      'UPDATE sales_order SET order_status = ''CLOSED'', total = :total WHERE id = :id',
      [ATotal, AOrderId]);
    AConnection.ExecSQL(
      'INSERT INTO outbox_event ' +
      '(aggregate_type, aggregate_id, event_type, payload) ' +
      'VALUES (''SALES_ORDER'', :id, ''ORDER_CLOSED'', :payload)',
      [AOrderId, AOperationKey]);
    AStatus := 'CLOSED';
  end;
end;

procedure CloseOrderFirebird(AConnection: TFDConnection; AOrderId: Int64;
  const AOperationKey: string; out AStatus: string; out ATotal: Currency;
  out AChanged: Boolean);
var
  Proc: TFDStoredProc;
begin
  Proc := TFDStoredProc.Create(nil);
  try
    Proc.Connection := AConnection;
    Proc.StoredProcName := 'CLOSE_ORDER';
    Proc.Prepare;
    Proc.ParamByName('P_ORDER_ID').AsLargeInt := AOrderId;
    Proc.ParamByName('P_OPERATION_KEY').AsString := AOperationKey;
    Proc.ExecProc;
    AStatus := Proc.ParamByName('P_STATUS').AsString;
    ATotal := Proc.ParamByName('P_TOTAL').AsCurrency;
    AChanged := Proc.ParamByName('P_CHANGED').AsInteger <> 0;
  finally
    Proc.Free;
  end;
end;

procedure ExecuteClose(AConnection: TFDConnection; AOrderId: Int64;
  const AOperationKey: string; out AStatus: string; out ATotal: Currency;
  out AChanged: Boolean);
begin
  if IsFirebird then
    CloseOrderFirebird(AConnection, AOrderId, AOperationKey,
      AStatus, ATotal, AChanged)
  else
    CloseOrderSQLite(AConnection, AOrderId, AOperationKey,
      AStatus, ATotal, AChanged);
end;

procedure RunCloseOrder;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Status: string;
  Total: Currency;
  Changed: Boolean;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    PrepareOrder(Connection);
    Connection.StartTransaction;
    try
      ExecuteClose(Connection, 121001, 'EX-12-CLOSE', Status, Total, Changed);
      Check(Changed, 'Primeiro fechamento deveria alterar o pedido.');
      Check((Status = 'CLOSED') and (Total = 35),
        'Primeiro fechamento devolveu estado incorreto.');
      Connection.Commit;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event ' +
      'WHERE aggregate_id = 121001 AND event_type = ''ORDER_CLOSED''') = 1,
      'Primeiro fechamento não gravou exatamente um evento outbox.');

    Connection.StartTransaction;
    try
      ExecuteClose(Connection, 121001, 'EX-12-CLOSE-RETRY', Status, Total, Changed);
      Check(not Changed, 'Repetição idempotente alterou pedido já fechado.');
      Connection.Commit;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM outbox_event ' +
      'WHERE aggregate_id = 121001 AND event_type = ''ORDER_CLOSED''') = 1,
      'Repetição idempotente duplicou o evento outbox.');
    Check(Connection.ExecSQLScalar(
      'SELECT total FROM sales_order WHERE id = 121001') = 35,
      'Total persistido após fechamento deveria ser 35.');
    if IsFirebird then
      Writeln('EX-12-04 aprovado: procedure Firebird fechou uma vez e retry foi idempotente.')
    else
      Writeln('EX-12-04 aprovado: adapter SQLite preservou o mesmo contrato transacional.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    DeleteFixture(Connection);
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunEvent;
var
  MainLink, OtherLink: TFDPhysFBDriverLink;
  Connection, OtherConnection: TFDConnection;
  Alerter: TFDEventAlerter;
  Probe: TAlertProbe;
  Deadline: UInt64;
  EventKinds: string;
begin
  MainLink := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(MainLink);
  if not IsFirebird then
  begin
    Alerter := TFDEventAlerter.Create(nil);
    Probe := TAlertProbe.Create;
    try
      EventKinds := Connection.ConnectionMetaDataIntf.EventKinds;
      Check(SameText(EventKinds, 'Events'),
        'EventKinds SQLite inesperado: ' + EventKinds);
      Alerter.Connection := Connection;
      Alerter.Names.Add('ORDER_CLOSED');
      Alerter.Options.Synchronize := True;
      Alerter.OnAlert := Probe.Alert;
      Alerter.Register;
      Alerter.Signal('ORDER_CLOSED', 121001);
      Deadline := GetTickCount64 + 2000;
      repeat
        CheckSynchronize(25);
        Sleep(25);
      until (Probe.Count > 0) or (GetTickCount64 >= Deadline);
      Check(Probe.Count = 1, 'Evento local SQLite não foi entregue uma vez.');
      Check(SameText(Probe.LastName, 'ORDER_CLOSED'),
        'Nome de evento SQLite inesperado: ' + Probe.LastName);
      Writeln('EX-12-05 aprovado: alerter SQLite local entregue na própria conexão.');
    finally
      if Alerter.Active then Alerter.Unregister;
      Probe.Free;
      Alerter.Free;
      Connection.Free;
      MainLink.Free;
    end;
    Exit;
  end;

  OtherLink := TFDPhysFBDriverLink.Create(nil);
  OtherConnection := NewConnection(OtherLink);
  Alerter := TFDEventAlerter.Create(nil);
  Probe := TAlertProbe.Create;
  try
    PrepareOrder(Connection);
    Alerter.Connection := Connection;
    Alerter.Names.Add('ORDER_CLOSED');
    Alerter.Options.Synchronize := True;
    Alerter.Options.Timeout := 500;
    Alerter.OnAlert := Probe.Alert;
    Alerter.Register;
    Sleep(250);
    OtherConnection.StartTransaction;
    try
      OtherConnection.ExecSQL(
        'UPDATE sales_order SET order_status = ''CLOSED'' WHERE id = 121001');
      OtherConnection.Commit;
    except
      if OtherConnection.InTransaction then OtherConnection.Rollback;
      raise;
    end;
    Deadline := GetTickCount64 + 5000;
    repeat
      CheckSynchronize(25);
      Sleep(25);
    until (Probe.Count > 0) or (GetTickCount64 >= Deadline);
    Check(Probe.Count > 0, 'Evento ORDER_CLOSED não chegou em cinco segundos.');
    Check(SameText(Probe.LastName, 'ORDER_CLOSED'),
      'Nome de evento inesperado: ' + Probe.LastName);
    Check(Connection.ExecSQLScalar(
      'SELECT order_status FROM sales_order WHERE id = 121001') = 'CLOSED',
      'Consulta compensatória não encontrou o estado fechado.');
    Writeln('EX-12-05 aprovado: alerta Firebird recebido e estado confirmado por consulta.');
  finally
    if Alerter.Active then Alerter.Unregister;
    Probe.Free;
    Alerter.Free;
    DeleteFixture(Connection);
    OtherConnection.Free;
    Connection.Free;
    OtherLink.Free;
    MainLink.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter12Checks procedure|function|multiset|close|event');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'procedure') then RunProcedure
    else if SameText(ParamStr(1), 'function') then RunFunction
    else if SameText(ParamStr(1), 'multiset') then RunMultipleResults
    else if SameText(ParamStr(1), 'close') then RunCloseOrder
    else if SameText(ParamStr(1), 'event') then RunEvent
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
