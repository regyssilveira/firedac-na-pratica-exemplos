program Chapter21Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  System.StrUtils,
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
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

type
  TRecoverProbe = class
  public
    Lost, Recover, Restored: Integer;
    procedure HandleLost(Sender: TObject);
    procedure HandleRestored(Sender: TObject);
    procedure HandleRecover(ASender, AInitiator: TObject; AException: Exception;
      var AAction: TFDPhysConnectionRecoverAction);
  end;

procedure TRecoverProbe.HandleLost(Sender: TObject);
begin Inc(Lost); end;

procedure TRecoverProbe.HandleRestored(Sender: TObject);
begin Inc(Restored); end;

procedure TRecoverProbe.HandleRecover(ASender, AInitiator: TObject;
  AException: Exception; var AAction: TFDPhysConnectionRecoverAction);
begin
  Inc(Recover); AAction := faRetry;
end;

procedure Check(ACondition: Boolean; const AMessage: string);
begin if not ACondition then raise Exception.Create(AMessage); end;

function Env(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function IsFirebird: Boolean;
begin Result := SameText(Env('CH21_DRIVER'), 'FB'); end;

procedure Configure(Connection: TFDConnection; Link: TFDPhysFBDriverLink;
  AAdmin: Boolean = False; ASecure: Boolean = False);
begin
  Connection.LoginPrompt := False;
  if IsFirebird then
  begin
    Link.VendorLib := Env('FIRESTORE_FBCLIENT');
    Connection.Params.Values['DriverID'] := 'FB'; Connection.Params.Values['Protocol'] := 'TCPIP';
    Connection.Params.Values['Server'] := Env('FIRESTORE_DB_HOST');
    Connection.Params.Values['Port'] := Env('FIRESTORE_DB_PORT');
    Connection.Params.Values['Database'] := Env('FIRESTORE_DB_NAME');
    if AAdmin then begin Connection.Params.Values['User_Name'] := Env('FIRESTORE_ADMIN_USER');
      Connection.Params.Values['Password'] := Env('FIRESTORE_ADMIN_PASSWORD'); end
    else begin Connection.Params.Values['User_Name'] := Env('FIRESTORE_DB_USER');
      Connection.Params.Values['Password'] := Env('FIRESTORE_DB_PASSWORD'); end;
    Connection.Params.Values['CharacterSet'] := 'UTF8';
    if ASecure then Connection.Params.Values['IBAdvanced'] := 'wire_crypt=Required';
  end
  else
  begin
    Connection.Params.Values['DriverID'] := 'SQLite';
    Connection.Params.Values['Database'] := Env('CH21_SQLITE_DATABASE');
    Connection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

function NewConnection(Link: TFDPhysFBDriverLink; AAdmin: Boolean = False;
  ASecure: Boolean = False): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try Configure(Result, Link, AAdmin, ASecure); Result.Open;
  except Result.Free; raise; end;
end;

procedure RunRecovery;
var Link, AdminLink: TFDPhysFBDriverLink; Connection, Admin: TFDConnection;
  Probe: TRecoverProbe; Attachment: Int64; Rows: Integer;
begin
  if not IsFirebird then
  begin
    Writeln('EX-21-01 driver=SQLite network_recovery=not_applicable file_connection=True');
    Exit;
  end;
  Link := TFDPhysFBDriverLink.Create(nil); AdminLink := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link); Admin := NewConnection(AdminLink, True); Probe := TRecoverProbe.Create;
  try
    Connection.ResourceOptions.AutoReconnect := True;
    Connection.OnLost := Probe.HandleLost; Connection.OnRecover := Probe.HandleRecover;
    Connection.OnRestored := Probe.HandleRestored;
    Attachment := Connection.ExecSQLScalar('SELECT CURRENT_CONNECTION FROM RDB$DATABASE');
    Admin.ExecSQL('DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID=:id', [Attachment]);
    Rows := Connection.ExecSQLScalar('SELECT COUNT(*) FROM product');
    Check(Rows = 3, 'Consulta não foi repetida após recuperação.');
    Writeln(Format('RECOVERY_EVENTS lost=%d recover=%d restored=%d',
      [Probe.Lost, Probe.Recover, Probe.Restored]));
    Check((Probe.Recover > 0) and (Probe.Restored > 0),
      'Eventos de recuperação incompletos.');
    Check(Connection.ExecSQLScalar('SELECT CURRENT_CONNECTION FROM RDB$DATABASE') <> Attachment,
      'Attachment físico não mudou após recovery.');
    Writeln(Format('EX-21-01 lost=%d recover=%d restored=%d rows=%d attachment_changed=True',
      [Probe.Lost, Probe.Recover, Probe.Restored, Rows]));
  finally Probe.Free; Admin.Free; Connection.Free; AdminLink.Free; Link.Free; end;
end;

procedure RunRetry;
var Link: TFDPhysFBDriverLink; Connection: TFDConnection; DuplicateSeen: Boolean; Id: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Connection := NewConnection(Link);
  try
    Connection.ExecSQL('DELETE FROM sales_order WHERE id=211001 OR idempotency_key=''EX-21-IDEMPOTENT''');
    Connection.ExecSQL('''
      INSERT INTO sales_order (id,idempotency_key,order_status,total)
      VALUES (211001,'EX-21-IDEMPOTENT','PENDING',10)
      ''');
    DuplicateSeen := False;
    try
      Connection.ExecSQL('''
        INSERT INTO sales_order (id,idempotency_key,order_status,total)
        VALUES (211001,'EX-21-IDEMPOTENT','PENDING',10)
        ''');
    except on CaughtException: EFDDBEngineException do DuplicateSeen := True; end;
    Id := Connection.ExecSQLScalar('SELECT id FROM sales_order WHERE idempotency_key=''EX-21-IDEMPOTENT''');
    Check(DuplicateSeen and (Id = 211001), 'Reconciliação idempotente falhou.');
    Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM sales_order WHERE idempotency_key=''EX-21-IDEMPOTENT''') = 1,
      'Retry duplicou pedido.');
    Writeln('EX-21-02 duplicate_classified=True existing_id=211001 rows=1 unsafe_retry=False');
  finally Connection.ExecSQL('DELETE FROM sales_order WHERE id=211001'); Connection.Free; Link.Free; end;
end;

procedure RunSecurity;
var Link, BadLink: TFDPhysFBDriverLink; Connection, Bad: TFDConnection;
  Plugin: string; NegativeFailed: Boolean;
begin
  Link := TFDPhysFBDriverLink.Create(nil); BadLink := TFDPhysFBDriverLink.Create(nil);
  Connection := nil; Bad := TFDConnection.Create(nil); NegativeFailed := False;
  try
    if IsFirebird then
    begin
      Connection := NewConnection(Link, False, True);
      Plugin := VarToStr(Connection.ExecSQLScalar('''
        SELECT MON$WIRE_CRYPT_PLUGIN FROM MON$ATTACHMENTS
        WHERE MON$ATTACHMENT_ID=CURRENT_CONNECTION
        '''));
      Check(Plugin <> '', 'Wire encryption exigida, mas plugin não foi reportado.');
      Configure(Bad, BadLink); Bad.Params.Values['Password'] := 'intentionally-wrong';
      try Bad.Open; except on CaughtException: EFDDBEngineException do NegativeFailed := True; end;
      Check(NegativeFailed, 'Credencial inválida foi aceita.');
      Writeln(Format('EX-21-03 transport=FirebirdWireCrypt plugin=%s wrong_password_failed=True tls=False',
        [Plugin]));
    end
    else
    begin
      Connection := NewConnection(Link);
      Check(Connection.ExecSQLScalar('PRAGMA integrity_check') = 'ok', 'SQLite integrity_check falhou.');
      Writeln('EX-21-03 transport=not_applicable embedded=True integrity=ok tls=False');
    end;
  finally Bad.Free; Connection.Free; BadLink.Free; Link.Free; end;
end;

procedure RunSmoke;
var Link: TFDPhysFBDriverLink; Connection: TFDConnection; BeforeCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Connection := NewConnection(Link);
  try
    Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM schema_version') = 8, 'Migration count diferente de 8.');
    Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3, 'Fixture product diferente de 3.');
    Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM product WHERE id=:id', [1]) = 1,
      'Consulta parametrizada do smoke test falhou.');
    BeforeCount := Connection.ExecSQLScalar('SELECT quantity FROM inventory WHERE product_id=1');
    Connection.StartTransaction;
    Connection.ExecSQL('UPDATE inventory SET quantity=quantity-1 WHERE product_id=1');
    Connection.Rollback;
    Check(Connection.ExecSQLScalar('SELECT quantity FROM inventory WHERE product_id=1') = BeforeCount,
      'Rollback do smoke test não restaurou estoque.');
    Writeln('EX-21-05 migrations=8 products=3 parametrized_select=True rollback=True');
  finally Connection.Free; Link.Free; end;
end;

function ErrorKindName(AKind: TFDCommandExceptionKind): string;
begin
  case AKind of
    ekUKViolated: Result := 'unique_constraint';
    ekFKViolated: Result := 'foreign_key';
    ekRecordLocked: Result := 'concurrency';
    ekUserPwdInvalid: Result := 'authentication';
    ekCmdAborted: Result := 'cancelled';
    ekServerGone: Result := 'connection_lost';
    ekObjNotExists, ekInvalidParams: Result := 'programming';
  else
    Result := 'database_other';
  end;
end;

function ClassifyDatabaseException(
  AException: EFDDBEngineException): string;
var
  ErrorIndex: Integer;
begin
  for ErrorIndex := 0 to AException.ErrorCount - 1 do
    if (AException.Errors[ErrorIndex].Kind = ekUKViolated) or
       (AException.Errors[ErrorIndex].ErrorCode = 1555) or
       (AException.Errors[ErrorIndex].ErrorCode = 2067) or
       (AException.Errors[ErrorIndex].ErrorCode = 335544334) or
       (AException.Errors[ErrorIndex].ErrorCode = 335544665) then
      Exit('unique_constraint');
  Result := ErrorKindName(AException.Kind);
end;

function BuildDatabaseErrorLog(AException: EFDDBEngineException;
  const ACorrelationId: string; ADurationMilliseconds: Int64): string;
var
  LogObject: TJSONObject;
  FirstError: TFDDBError;
begin
  LogObject := TJSONObject.Create;
  try
    LogObject.AddPair('event', 'product.insert.failed');
    LogObject.AddPair('correlationId', ACorrelationId);
    LogObject.AddPair('driver', IfThen(IsFirebird, 'FB', 'SQLite'));
    LogObject.AddPair('durationMs', TJSONNumber.Create(ADurationMilliseconds));
    LogObject.AddPair('category', ClassifyDatabaseException(AException));
    LogObject.AddPair('retryable', TJSONBool.Create(False));
    LogObject.AddPair('errorCount', TJSONNumber.Create(AException.ErrorCount));
    if AException.ErrorCount > 0 then
    begin
      FirstError := AException.Errors[0];
      LogObject.AddPair('nativeCode', TJSONNumber.Create(FirstError.ErrorCode));
      LogObject.AddPair('rowIndex', TJSONNumber.Create(FirstError.RowIndex));
    end;
    Result := LogObject.ToJSON;
  finally
    LogObject.Free;
  end;
end;

procedure RunStructuredDiagnostics;
const
  CorrelationId = 'EX-21-06-CORRELATION';
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  LogText: string;
  ParsedLog: TJSONValue;
  LogObject: TJSONObject;
  StructuredErrorSeen: Boolean;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  try
    StructuredErrorSeen := False;
    LogText := '';
    try
      Connection.ExecSQL(
        '''
          INSERT INTO product
          (id, sku, name, category_id, price, active)
          VALUES (1, 'SENSITIVE-SKU', 'Sensitive name', 1, 10, 1)
          ''');
    except
      on CaughtException: EFDDBEngineException do
      begin
        StructuredErrorSeen :=
          ClassifyDatabaseException(CaughtException) = 'unique_constraint';
        LogText := BuildDatabaseErrorLog(
          CaughtException, CorrelationId, 1);
      end;
    end;
    Check(StructuredErrorSeen,
      'A violação de chave única não recebeu classificação estruturada.');
    Check(LogText <> '', 'O evento JSON não foi produzido.');
    Check(Pos('SENSITIVE-SKU', LogText) = 0,
      'O log expôs um valor de parâmetro sensível.');
    Check(Pos('INSERT INTO', UpperCase(LogText)) = 0,
      'O log expôs o SQL completo.');
    ParsedLog := TJSONObject.ParseJSONValue(LogText);
    try
      Check(ParsedLog is TJSONObject, 'O log produzido não é um objeto JSON.');
      LogObject := TJSONObject(ParsedLog);
      Check(LogObject.GetValue<string>('correlationId') = CorrelationId,
        'O correlation ID não atravessou a fronteira de erro.');
      Check(LogObject.GetValue<string>('category') = 'unique_constraint',
        'A categoria estável do domínio divergiu.');
      Check(not LogObject.GetValue<Boolean>('retryable'),
        'Violação de chave única não deveria receber retry automático.');
    finally
      ParsedLog.Free;
    end;
    Writeln('EX-21-06 ', LogText);
  finally
    Connection.Free;
    Link.Free;
  end;
end;

begin
  try
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter21Checks recovery|retry|security|smoke|diagnostics');
    if SameText(ParamStr(1), 'recovery') then RunRecovery
    else if SameText(ParamStr(1), 'retry') then RunRetry
    else if SameText(ParamStr(1), 'security') then RunSecurity
    else if SameText(ParamStr(1), 'smoke') then RunSmoke
    else if SameText(ParamStr(1), 'diagnostics') then RunStructuredDiagnostics
    else raise Exception.Create('Modo inválido.');
  except on CaughtException: Exception do begin Writeln(ErrOutput, CaughtException.ClassName, ': ', CaughtException.Message); ExitCode := 1; end; end;
end.
