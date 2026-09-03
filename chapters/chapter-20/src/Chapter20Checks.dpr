program Chapter20Checks;

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
  TAlertProbe = class
  public
    Count: Integer;
    LastName: string;
    procedure Alert(ASender: TFDCustomEventAlerter;
      const AEventName: string; const AArgument: Variant);
  end;

procedure TAlertProbe.Alert(ASender: TFDCustomEventAlerter;
  const AEventName: string; const AArgument: Variant);
begin
  Inc(Count); LastName := AEventName;
end;

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
  Result := SameText(RequiredEnvironment('CH20_DRIVER'), 'FB');
end;

procedure Configure(AConnection: TFDConnection; ALink: TFDPhysFBDriverLink);
begin
  AConnection.LoginPrompt := False;
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH20_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
    AConnection.Params.Values['BusyTimeout'] := '100';
  end;
end;

function NewConnection(ALink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try Configure(Result, ALink); Result.Open; except Result.Free; raise; end;
end;

function HasName(AList: TStrings; const AName: string): Boolean;
var I: Integer; S: string;
begin
  Result := False;
  for I := 0 to AList.Count - 1 do
  begin
    S := AList[I];
    if SameText(S, AName) or SameText(S, '"' + AName + '"') or
       (Pos(UpperCase(AName), UpperCase(S)) > 0) then Exit(True);
  end;
end;

procedure RunNames;
var Link: TFDPhysFBDriverLink; C: TFDConnection; Catalogs, Schemas, Tables: TStringList;
  ViewVisible: Boolean;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  Catalogs := TStringList.Create; Schemas := TStringList.Create; Tables := TStringList.Create;
  try
    C.GetCatalogNames('%', Catalogs); C.GetSchemaNames('', '%', Schemas);
    C.GetTableNames('', '', '%', Tables, [osMy, osOther], [tkTable, tkView], False);
    Check(HasName(Tables, 'PRODUCT'), 'Tabela product não apareceu no metadata.');
    ViewVisible := HasName(Tables, 'ORDER_TOTAL_VIEW');
    if not IsFirebird then Check(ViewVisible, 'View SQLite conhecida não apareceu.');
    Writeln(Format('EX-20-01 catalogs=%d schemas=%d tables_views=%d product=True view_visible=%s',
      [Catalogs.Count, Schemas.Count, Tables.Count, BoolToStr(ViewVisible, True)]));
  finally Tables.Free; Schemas.Free; Catalogs.Free; C.Free; Link.Free; end;
end;

procedure RunStructure;
var Link: TFDPhysFBDriverLink; C: TFDConnection; Fields, Keys, Indexes: TStringList;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  Fields := TStringList.Create; Keys := TStringList.Create; Indexes := TStringList.Create;
  try
    C.GetFieldNames('', '', 'PRODUCT', '%', Fields);
    C.GetKeyFieldNames('', '', 'PRODUCT', '%', Keys);
    C.GetIndexNames('', '', 'PRODUCT', '%', Indexes);
    Check(HasName(Fields, 'ID') and HasName(Fields, 'SKU') and HasName(Fields, 'NAME'),
      'Campos esperados de product ausentes.');
    Check(HasName(Keys, 'ID'), 'Chave ID ausente.');
    Check(HasName(Indexes, 'IX_PRODUCT_NAME'), 'Índice IX_PRODUCT_NAME ausente.');
    Writeln(Format('EX-20-02 fields=%d keys=%d indexes=%d',
      [Fields.Count, Keys.Count, Indexes.Count]));
  finally Indexes.Free; Keys.Free; Fields.Free; C.Free; Link.Free; end;
end;

procedure RunRoutines;
var Link: TFDPhysFBDriverLink; C: TFDConnection; Routines, Generators: TStringList;
  Meta: TFDMetaInfoQuery; ArgCount: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  Routines := TStringList.Create; Generators := TStringList.Create;
  Meta := TFDMetaInfoQuery.Create(nil);
  try
    C.GetStoredProcNames('', '', '', '%', Routines, [osMy, osOther], False);
    C.GetGeneratorNames('', '', '%', Generators, [osMy, osOther], False);
    if IsFirebird then
    begin
      Check(HasName(Routines, 'GET_ORDER_STATE'), 'Procedure GET_ORDER_STATE ausente.');
      Meta.Connection := C; Meta.MetaInfoKind := mkProcArgs;
      Meta.ObjectName := 'GET_ORDER_STATE'; Meta.Open; ArgCount := Meta.RecordCount;
      Check(ArgCount = 3, 'GET_ORDER_STATE deveria expor três argumentos.');
    end
    else
    begin
      Check(Routines.Count = 0, 'SQLite anunciou stored procedure persistente.');
      ArgCount := 0;
    end;
    Writeln(Format('EX-20-03 routines=%d generators=%d known_args=%d',
      [Routines.Count, Generators.Count, ArgCount]));
  finally Meta.Free; Generators.Free; Routines.Free; C.Free; Link.Free; end;
end;

procedure RunExplorer;
var Link: TFDPhysFBDriverLink; C: TFDConnection; TablesMeta, FieldsMeta: TFDMetaInfoQuery;
  Q: TFDQuery; Found: Boolean; SnapshotTables, SnapshotFields, PreviewRows: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil); C := NewConnection(Link);
  TablesMeta := TFDMetaInfoQuery.Create(nil); FieldsMeta := TFDMetaInfoQuery.Create(nil);
  Q := TFDQuery.Create(nil);
  try
    TablesMeta.Connection := C; TablesMeta.MetaInfoKind := mkTables;
    TablesMeta.ObjectScopes := [osMy, osOther];
    TablesMeta.TableKinds := [tkTable, tkView]; TablesMeta.Open;
    SnapshotTables := TablesMeta.RecordCount; Found := False; TablesMeta.First;
    while not TablesMeta.Eof do begin
      if SameText(TablesMeta.FieldByName('TABLE_NAME').AsString, 'PRODUCT') then Found := True;
      TablesMeta.Next;
    end;
    Check(Found, 'Allowlist de metadata não contém PRODUCT.');
    FieldsMeta.Connection := C; FieldsMeta.MetaInfoKind := mkTableFields;
    FieldsMeta.ObjectName := 'PRODUCT'; FieldsMeta.Open; SnapshotFields := FieldsMeta.RecordCount;
    Check(SnapshotFields >= 6, 'Snapshot de campos incompleto.');
    Q.Connection := C;
    if IsFirebird then Q.SQL.Text := 'SELECT ID, SKU, NAME FROM PRODUCT ROWS 2'
    else Q.SQL.Text := 'SELECT ID, SKU, NAME FROM PRODUCT LIMIT 2';
    Q.Open; Q.FetchAll; PreviewRows := Q.RecordCount;
    Check(PreviewRows = 2, 'Preview não respeitou limite de duas linhas.');
    Writeln(Format('EX-20-04 snapshot_tables=%d snapshot_fields=%d preview_rows=%d allowlisted=True',
      [SnapshotTables, SnapshotFields, PreviewRows]));
  finally Q.Free; FieldsMeta.Free; TablesMeta.Free; C.Free; Link.Free; end;
end;

procedure WaitAlerts(AProbe: TAlertProbe; AExpected: Integer; ATimeout: Cardinal);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64 + ATimeout;
  repeat CheckSynchronize(10); Sleep(10);
  until (AProbe.Count >= AExpected) or (GetTickCount64 >= Deadline);
end;

procedure CleanEventFixture(C: TFDConnection);
begin
  C.ExecSQL('DELETE FROM outbox_event WHERE aggregate_id = 201001');
  C.ExecSQL('DELETE FROM sales_order WHERE id = 201001');
end;

procedure RunEvents;
var MainLink, OtherLink: TFDPhysFBDriverLink; Main, Other: TFDConnection;
  Alerter, OtherAlerter: TFDEventAlerter; Probe: TAlertProbe;
  BeforeRollback, BeforeOffline: Integer;
begin
  MainLink := TFDPhysFBDriverLink.Create(nil); OtherLink := TFDPhysFBDriverLink.Create(nil);
  Main := NewConnection(MainLink); Other := NewConnection(OtherLink);
  Alerter := TFDEventAlerter.Create(nil); Probe := TAlertProbe.Create;
  OtherAlerter := nil;
  try
    CleanEventFixture(Other);
    Other.ExecSQL('INSERT INTO sales_order (id,idempotency_key,order_status,total) ' +
      'VALUES (201001,''EX-20-EVENT'',''PENDING'',0)');
    Alerter.Connection := Main; Alerter.Names.Add('ORDER_CLOSED');
    Alerter.Options.Synchronize := True; Alerter.Options.Timeout := 250;
    Alerter.OnAlert := Probe.Alert; Alerter.Register; Sleep(150);
    if IsFirebird then
    begin
      Other.StartTransaction;
      Other.ExecSQL('UPDATE sales_order SET order_status=''CLOSED'' WHERE id=201001');
      Other.Commit;
    end
    else Alerter.Signal('ORDER_CLOSED', 201001);
    WaitAlerts(Probe, 1, 3000); Check(Probe.Count >= 1, 'Evento confirmado não chegou.');

    BeforeRollback := Probe.Count;
    Other.StartTransaction;
    try
      if IsFirebird then begin
        Other.ExecSQL('UPDATE sales_order SET order_status=''PENDING'' WHERE id=201001');
        Other.ExecSQL('UPDATE sales_order SET order_status=''CLOSED'' WHERE id=201001');
      end
      else Alerter.Signal('ORDER_CLOSED', 201002);
      Other.Rollback;
    except if Other.InTransaction then Other.Rollback; raise; end;
    WaitAlerts(Probe, BeforeRollback + 1, 500);
    if IsFirebird then Check(Probe.Count = BeforeRollback, 'Rollback Firebird entregou evento.')
    else Check(Probe.Count > BeforeRollback, 'Evento local SQLite não mostrou independência da transação.');

    Alerter.Unregister; BeforeOffline := Probe.Count;
    Other.ExecSQL('INSERT INTO outbox_event ' +
      '(aggregate_type,aggregate_id,event_type,payload) VALUES ' +
      '(''SALES_ORDER'',201001,''ORDER_CLOSED'',''EX-20-OFFLINE'')');
    if IsFirebird then
    begin
      Other.ExecSQL('UPDATE sales_order SET order_status=''PENDING'' WHERE id=201001');
      Other.ExecSQL('UPDATE sales_order SET order_status=''CLOSED'' WHERE id=201001');
    end
    else
    begin
      OtherAlerter := TFDEventAlerter.Create(nil);
      OtherAlerter.Connection := Other; OtherAlerter.Names.Add('ORDER_CLOSED');
      OtherAlerter.Register; OtherAlerter.Signal('ORDER_CLOSED', 201003);
      OtherAlerter.Unregister; FreeAndNil(OtherAlerter);
    end;
    Alerter.Register; WaitAlerts(Probe, BeforeOffline + 1, 300);
    Check(Probe.Count = BeforeOffline, 'Listener recuperou evento transitório emitido offline.');
    Check(Main.ExecSQLScalar('SELECT COUNT(*) FROM outbox_event WHERE aggregate_id=201001') = 1,
      'Polling não recuperou a outbox persistida.');
    Writeln(Format('EX-20-05 driver=%s committed=True rollback_alert=%s offline_alert=False outbox=1',
      [RequiredEnvironment('CH20_DRIVER'), BoolToStr((not IsFirebird), True)]));
  finally
    if Alerter.Active then Alerter.Unregister;
    if (OtherAlerter <> nil) and OtherAlerter.Active then OtherAlerter.Unregister;
    OtherAlerter.Free;
    CleanEventFixture(Other); Probe.Free; Alerter.Free;
    Other.Free; Main.Free; OtherLink.Free; MainLink.Free;
  end;
end;

begin
  try
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter20Checks names|structure|routines|explorer|events');
    if SameText(ParamStr(1), 'names') then RunNames
    else if SameText(ParamStr(1), 'structure') then RunStructure
    else if SameText(ParamStr(1), 'routines') then RunRoutines
    else if SameText(ParamStr(1), 'explorer') then RunExplorer
    else if SameText(ParamStr(1), 'events') then RunEvents
    else raise Exception.Create('Modo inválido.');
  except
    on E: Exception do begin Writeln(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
end.
