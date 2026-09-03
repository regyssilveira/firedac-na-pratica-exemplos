program Chapter21Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
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

procedure Configure(C: TFDConnection; Link: TFDPhysFBDriverLink;
  AAdmin: Boolean = False; ASecure: Boolean = False);
begin
  C.LoginPrompt := False;
  if IsFirebird then
  begin
    Link.VendorLib := Env('FIRESTORE_FBCLIENT');
    C.Params.Values['DriverID'] := 'FB'; C.Params.Values['Protocol'] := 'TCPIP';
    C.Params.Values['Server'] := Env('FIRESTORE_DB_HOST');
    C.Params.Values['Port'] := Env('FIRESTORE_DB_PORT');
    C.Params.Values['Database'] := Env('FIRESTORE_DB_NAME');
    if AAdmin then begin C.Params.Values['User_Name'] := Env('FIRESTORE_ADMIN_USER');
      C.Params.Values['Password'] := Env('FIRESTORE_ADMIN_PASSWORD'); end
    else begin C.Params.Values['User_Name'] := Env('FIRESTORE_DB_USER');
      C.Params.Values['Password'] := Env('FIRESTORE_DB_PASSWORD'); end;
    C.Params.Values['CharacterSet'] := 'UTF8';
    if ASecure then C.Params.Values['IBAdvanced'] := 'wire_crypt=Required';
  end
  else
  begin
    C.Params.Values['DriverID'] := 'SQLite';
    C.Params.Values['Database'] := Env('CH21_SQLITE_DATABASE');
    C.Params.Values['ForeignKeys'] := 'On';
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
var Link, AdminLink: TFDPhysFBDriverLink; C, Admin: TFDConnection;
  Probe: TRecoverProbe; Attachment: Int64; Rows: Integer;
begin
  if not IsFirebird then
  begin
    Writeln('EX-21-01 driver=SQLite network_recovery=not_applicable file_connection=True');
    Exit;
  end;
  Link := TFDPhysFBDriverLink.Create(nil); AdminLink := TFDPhysFBDriverLink.Create(nil);
  C := NewConnection(Link); Admin := NewConnection(AdminLink, True); Probe := TRecoverProbe.Create;
  try
    C.ResourceOptions.AutoReconnect := True;
    C.OnLost := Probe.HandleLost; C.OnRecover := Probe.HandleRecover;
    C.OnRestored := Probe.HandleRestored;
    Attachment := C.ExecSQLScalar('SELECT CURRENT_CONNECTION FROM RDB$DATABASE');
    Admin.ExecSQL('DELETE FROM MON$ATTACHMENTS WHERE MON$ATTACHMENT_ID=:id', [Attachment]);
    Rows := C.ExecSQLScalar('SELECT COUNT(*) FROM product');
    Check(Rows = 3, 'Consulta não foi repetida após recuperação.');
    Writeln(Format('RECOVERY_EVENTS lost=%d recover=%d restored=%d',
      [Probe.Lost, Probe.Recover, Probe.Restored]));
    Check((Probe.Recover > 0) and (Probe.Restored > 0),
      'Eventos de recuperação incompletos.');
    Check(C.ExecSQLScalar('SELECT CURRENT_CONNECTION FROM RDB$DATABASE') <> Attachment,
      'Attachment físico não mudou após recovery.');
    Writeln(Format('EX-21-01 lost=%d recover=%d restored=%d rows=%d attachment_changed=True',
      [Probe.Lost, Probe.Recover, Probe.Restored, Rows]));
  finally Probe.Free; Admin.Free; C.Free; AdminLink.Free; Link.Free; end;
end;

procedure RunRetry;
var Link: TFDPhysFBDriverLink; C: TFDConnection; DuplicateSeen: Boolean; Id: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  try
    C.ExecSQL('DELETE FROM sales_order WHERE id=211001 OR idempotency_key=''EX-21-IDEMPOTENT''');
    C.ExecSQL('INSERT INTO sales_order (id,idempotency_key,order_status,total) ' +
      'VALUES (211001,''EX-21-IDEMPOTENT'',''PENDING'',10)');
    DuplicateSeen := False;
    try
      C.ExecSQL('INSERT INTO sales_order (id,idempotency_key,order_status,total) ' +
        'VALUES (211001,''EX-21-IDEMPOTENT'',''PENDING'',10)');
    except on E: EFDDBEngineException do DuplicateSeen := True; end;
    Id := C.ExecSQLScalar('SELECT id FROM sales_order WHERE idempotency_key=''EX-21-IDEMPOTENT''');
    Check(DuplicateSeen and (Id = 211001), 'Reconciliação idempotente falhou.');
    Check(C.ExecSQLScalar('SELECT COUNT(*) FROM sales_order WHERE idempotency_key=''EX-21-IDEMPOTENT''') = 1,
      'Retry duplicou pedido.');
    Writeln('EX-21-02 duplicate_classified=True existing_id=211001 rows=1 unsafe_retry=False');
  finally C.ExecSQL('DELETE FROM sales_order WHERE id=211001'); C.Free; Link.Free; end;
end;

procedure RunSecurity;
var Link, BadLink: TFDPhysFBDriverLink; C, Bad: TFDConnection;
  Plugin: string; NegativeFailed: Boolean;
begin
  Link := TFDPhysFBDriverLink.Create(nil); BadLink := TFDPhysFBDriverLink.Create(nil);
  C := nil; Bad := TFDConnection.Create(nil); NegativeFailed := False;
  try
    if IsFirebird then
    begin
      C := NewConnection(Link, False, True);
      Plugin := VarToStr(C.ExecSQLScalar('SELECT MON$WIRE_CRYPT_PLUGIN FROM MON$ATTACHMENTS ' +
        'WHERE MON$ATTACHMENT_ID=CURRENT_CONNECTION'));
      Check(Plugin <> '', 'Wire encryption exigida, mas plugin não foi reportado.');
      Configure(Bad, BadLink); Bad.Params.Values['Password'] := 'intentionally-wrong';
      try Bad.Open; except on E: EFDDBEngineException do NegativeFailed := True; end;
      Check(NegativeFailed, 'Credencial inválida foi aceita.');
      Writeln(Format('EX-21-03 transport=FirebirdWireCrypt plugin=%s wrong_password_failed=True tls=False',
        [Plugin]));
    end
    else
    begin
      C := NewConnection(Link);
      Check(C.ExecSQLScalar('PRAGMA integrity_check') = 'ok', 'SQLite integrity_check falhou.');
      Writeln('EX-21-03 transport=not_applicable embedded=True integrity=ok tls=False');
    end;
  finally Bad.Free; C.Free; BadLink.Free; Link.Free; end;
end;

procedure RunSmoke;
var Link: TFDPhysFBDriverLink; C: TFDConnection; BeforeCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  try
    Check(C.ExecSQLScalar('SELECT COUNT(*) FROM schema_version') = 8, 'Migration count diferente de 8.');
    Check(C.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3, 'Fixture product diferente de 3.');
    Check(C.ExecSQLScalar('SELECT COUNT(*) FROM product WHERE id=:id', [1]) = 1,
      'Consulta parametrizada do smoke test falhou.');
    BeforeCount := C.ExecSQLScalar('SELECT quantity FROM inventory WHERE product_id=1');
    C.StartTransaction;
    C.ExecSQL('UPDATE inventory SET quantity=quantity-1 WHERE product_id=1');
    C.Rollback;
    Check(C.ExecSQLScalar('SELECT quantity FROM inventory WHERE product_id=1') = BeforeCount,
      'Rollback do smoke test não restaurou estoque.');
    Writeln('EX-21-05 migrations=8 products=3 parametrized_select=True rollback=True');
  finally C.Free; Link.Free; end;
end;

begin
  try
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter21Checks recovery|retry|security|smoke');
    if SameText(ParamStr(1), 'recovery') then RunRecovery
    else if SameText(ParamStr(1), 'retry') then RunRetry
    else if SameText(ParamStr(1), 'security') then RunSecurity
    else if SameText(ParamStr(1), 'smoke') then RunSmoke
    else raise Exception.Create('Modo inválido.');
  except on E: Exception do begin Writeln(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end; end;
end.
