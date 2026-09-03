program Chapter19Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Diagnostics,
  System.Threading,
  System.SyncObjs,
  System.Generics.Collections,
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
  TAsyncObserver = class
  public
    ErrorSeen: Boolean;
    ErrorClass: string;
    Completed: TEvent;
    constructor Create;
    destructor Destroy; override;
    procedure HandleAfterOpen(ADataSet: TDataSet);
    procedure HandleError(ASender, AInitiator: TObject; var AException: Exception);
  end;

constructor TAsyncObserver.Create;
begin
  inherited Create;
  Completed := TEvent.Create(nil, True, False, '');
end;

destructor TAsyncObserver.Destroy;
begin
  Completed.Free;
  inherited Destroy;
end;

procedure TAsyncObserver.HandleAfterOpen(ADataSet: TDataSet);
begin
  Completed.SetEvent;
end;

procedure TAsyncObserver.HandleError(ASender, AInitiator: TObject;
  var AException: Exception);
begin
  ErrorSeen := True;
  ErrorClass := AException.ClassName;
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
  Result := SameText(RequiredEnvironment('CH19_DRIVER'), 'FB');
end;

procedure FillParams(AParams: TStrings; APooled: Boolean; AMaximum: Integer);
begin
  if IsFirebird then
  begin
    AParams.Values['Protocol'] := 'TCPIP';
    AParams.Values['Server'] := RequiredEnvironment('FIRESTORE_DB_HOST');
    AParams.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
    AParams.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
    AParams.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
    AParams.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
    AParams.Values['CharacterSet'] := 'UTF8';
  end
  else
  begin
    AParams.Values['Database'] := RequiredEnvironment('CH19_SQLITE_DATABASE');
    AParams.Values['ForeignKeys'] := 'On';
  end;
  if APooled then
  begin
    AParams.Values['Pooled'] := 'True';
    AParams.Values['POOL_MaximumItems'] := IntToStr(AMaximum);
    AParams.Values['POOL_ExpireTimeout'] := '60000';
    AParams.Values['POOL_CleanupTimeout'] := '60000';
  end;
end;

procedure ConfigureDirect(AConnection: TFDConnection; ALink: TFDPhysFBDriverLink);
var P: TStringList;
begin
  AConnection.LoginPrompt := False;
  if IsFirebird then ALink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
  P := TStringList.Create;
  try
    FillParams(P, False, 0);
    P.Values['DriverID'] := IfThen(IsFirebird, 'FB', 'SQLite');
    AConnection.Params.Assign(P);
  finally P.Free; end;
end;

function NewDirect(ALink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try ConfigureDirect(Result, ALink); Result.Open; except Result.Free; raise; end;
end;

function SyntheticSql(ARows: Integer): string;
begin
  if IsFirebird then
    Result := 'SELECT id, category_id, name FROM benchmark_product_rows(' + IntToStr(ARows) + ')'
  else
    Result := 'WITH RECURSIVE seq(id) AS (SELECT 1 UNION ALL SELECT id + 1 FROM seq ' +
      'WHERE id < ' + IntToStr(ARows) + ') SELECT id, id % 10 category_id, ' +
      '''Product '' || id name FROM seq';
end;

function SlowSql: string;
begin
  if IsFirebird then
    Result := 'EXECUTE BLOCK AS DECLARE VARIABLE i BIGINT = 0; BEGIN ' +
      'WHILE (i < 50000000) DO i = i + 1; END'
  else
    Result := 'CREATE TEMP TABLE ch19_cancel AS WITH RECURSIVE seq(id) AS ' +
      '(SELECT 1 UNION ALL SELECT id + 1 FROM seq WHERE id < 10000000) SELECT id FROM seq';
end;

procedure WaitCommand(AQuery: TFDQuery);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64 + 30000;
  while AQuery.Command.State in [csExecuting, csFetching, csAborting] do
  begin
    CheckSynchronize(1); Sleep(1);
    Check(GetTickCount64 < Deadline, 'Timeout aguardando comando assíncrono.');
  end;
  CheckSynchronize(1);
end;

procedure WaitEvent(AEvent: TEvent);
var Deadline: UInt64;
begin
  Deadline := GetTickCount64 + 30000;
  while AEvent.WaitFor(0) <> wrSignaled do
  begin
    CheckSynchronize(1); Sleep(1);
    Check(GetTickCount64 < Deadline, 'Timeout aguardando evento assíncrono.');
  end;
  CheckSynchronize(1);
end;

procedure RunAsync;
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Q: TFDQuery;
  T: TStopwatch; CallUs, TotalUs: Int64; Rows: Integer; Observer: TAsyncObserver;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link);
  Q := TFDQuery.Create(nil); Observer := TAsyncObserver.Create;
  try
    Q.Connection := Conn; Q.ResourceOptions.CmdExecMode := amAsync;
    Q.AfterOpen := Observer.HandleAfterOpen;
    Q.SQL.Text := SyntheticSql(100000); T := TStopwatch.StartNew; Q.Open;
    CallUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    WaitEvent(Observer.Completed); Q.ResourceOptions.CmdExecMode := amBlocking; Q.FetchAll;
    TotalUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Q.RecordCount = 100000, 'Async não materializou cem mil linhas.');
    Rows := Q.RecordCount;
    Q.Close; Q.ResourceOptions.CmdExecMode := amAsync;
    Q.OnError := Observer.HandleError; Q.SQL.Text := 'INSERT INTO product ' +
      '(id, sku, name, category_id, price, active) ' +
      'VALUES (1, ''DUP'', ''Duplicate'', 1, 1, 1)';
    try
      Q.ExecSQL;
      Sleep(20);
      CheckSynchronize(1);
      WaitCommand(Q);
    except
      on E: Exception do
      begin
        Observer.ErrorSeen := True;
        Observer.ErrorClass := E.ClassName;
      end;
    end;
    Check(Observer.ErrorSeen, 'Erro assíncrono não chegou ao handler.');
    Writeln(Format('EX-19-01 call_us=%d total_us=%d rows=%d error=%s',
      [CallUs, TotalUs, Rows, Observer.ErrorClass]));
  finally Observer.Free; Q.Free; Conn.Free; Link.Free; end;
end;

procedure RunCancel;
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Q: TFDQuery;
  T: TStopwatch; CancelUs: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link); Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn; Q.ResourceOptions.CmdExecMode := amAsync; Q.SQL.Text := SlowSql;
    Q.ExecSQL; Sleep(20); T := TStopwatch.StartNew; Q.AbortJob(True);
    CancelUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency; WaitCommand(Q);
    Check(Conn.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3,
      'Conexão não respondeu após cancelamento.');
    Q.Disconnect(True);
    Writeln(Format('EX-19-02 cancel_us=%d active=%s reusable=True',
      [CancelUs, BoolToStr(Q.Active, True)]));
  finally Q.Free; Conn.Free; Link.Free; end;
end;

procedure RunTasks;
const Count = 12;
var Tasks: TArray<ITask>; I, Success: Integer;
begin
  SetLength(Tasks, Count); Success := 0;
  for I := 0 to Count - 1 do
    Tasks[I] := TTask.Run(TProc(
      procedure
      var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Q: TFDQuery;
      begin
        Link := TFDPhysFBDriverLink.Create(nil); Conn := nil; Q := nil;
        try
          Conn := NewDirect(Link); Q := TFDQuery.Create(nil); Q.Connection := Conn;
          Q.SQL.Text := 'SELECT COUNT(*) FROM product'; Q.Open;
          if Q.Fields[0].AsInteger = 3 then TInterlocked.Increment(Success);
        finally Q.Free; Conn.Free; Link.Free; end;
      end));
  TTask.WaitForAll(Tasks);
  Check(Success = Count, 'Nem todas as tasks concluíram com conexão própria.');
  Writeln(Format('EX-19-03 tasks=%d successes=%d ownership=per_task', [Count, Success]));
end;

procedure AddDefinition(const AName: string; APooled: Boolean; AMaximum: Integer);
var P: TStringList;
begin
  P := TStringList.Create;
  try
    FillParams(P, APooled, AMaximum);
    FDManager.AddConnectionDef(AName, IfThen(IsFirebird, 'FB', 'SQLite'), P);
  finally P.Free; end;
end;

function OpenByDef(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil); Result.LoginPrompt := False;
  try Result.ConnectionDefName := AName; Result.Open; except Result.Free; raise; end;
end;

procedure RunPool;
const Count = 4;
var Name: string; Tasks: TArray<ITask>; I, Success: Integer;
begin
  Name := 'CH19_POOL_' + IntToStr(GetCurrentProcessId); AddDefinition(Name, True, Count);
  SetLength(Tasks, Count); Success := 0;
  try
    for I := 0 to Count - 1 do Tasks[I] := TTask.Run(TProc(
      procedure
      var C: TFDConnection;
      begin
        C := OpenByDef(Name);
        try Sleep(30); if C.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3 then
          TInterlocked.Increment(Success); finally C.Free; end;
      end));
    TTask.WaitForAll(Tasks);
    Check(Success = Count, 'Pool não serviu todas as tasks.');
    Writeln(Format('EX-19-04 pool_max=%d concurrent=%d successes=%d', [Count, Count, Success]));
  finally FDManager.CloseConnectionDef(Name); FDManager.DeleteConnectionDef(Name); end;
end;

procedure RunSaturation;
var Name: string; C1, C2, C3, Recovered: TFDConnection; Rejected: Boolean;
begin
  Name := 'CH19_SAT_' + IntToStr(GetCurrentProcessId); AddDefinition(Name, True, 2);
  C1 := nil; C2 := nil; C3 := nil; Recovered := nil; Rejected := False;
  try
    C1 := OpenByDef(Name); C2 := OpenByDef(Name);
    try C3 := OpenByDef(Name); except on E: EFDException do Rejected := True; end;
    Check(Rejected, 'Terceiro lease não foi rejeitado com pool máximo 2.');
    C1.Free; C1 := nil;
    Recovered := OpenByDef(Name);
    Check(Recovered.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3,
      'Pool não recuperou capacidade após devolução.');
    Writeln('EX-19-05 pool_max=2 third_rejected=True recovered=True');
  finally
    Recovered.Free; C3.Free; C2.Free; C1.Free;
    FDManager.CloseConnectionDef(Name); FDManager.DeleteConnectionDef(Name);
  end;
end;

procedure RunBench;
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Q: TFDQuery;
  T: TStopwatch; BlockingUs, AsyncCallUs, AsyncTotalUs: Int64; Observer: TAsyncObserver;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link); Q := TFDQuery.Create(nil);
  Observer := TAsyncObserver.Create;
  try
    Q.Connection := Conn; Q.FetchOptions.Mode := fmAll; Q.SQL.Text := SyntheticSql(100000);
    T := TStopwatch.StartNew; Q.Open; Q.FetchAll;
    BlockingUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Q.RecordCount = 100000, 'Blocking divergiu.'); Q.Close;
    Q.ResourceOptions.CmdExecMode := amAsync; Q.AfterOpen := Observer.HandleAfterOpen;
    T := TStopwatch.StartNew; Q.Open;
    AsyncCallUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    WaitEvent(Observer.Completed); Q.ResourceOptions.CmdExecMode := amBlocking; Q.FetchAll;
    AsyncTotalUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Q.RecordCount = 100000, 'Async divergiu.');
    Writeln(Format('BM-09 blocking_us=%d async_call_us=%d async_total_us=%d rows=100000',
      [BlockingUs, AsyncCallUs, AsyncTotalUs]));
  finally Observer.Free; Q.Free; Conn.Free; Link.Free; end;
end;

procedure RunPoolBench;
const Leases = 10;
var NewName, PoolName: string; C: TFDConnection; I: Integer;
  T: TStopwatch; NewUs, PoolUs: Int64;
begin
  NewName := 'CH19_NEW_' + IntToStr(GetCurrentProcessId);
  PoolName := 'CH19_BENCH_POOL_' + IntToStr(GetCurrentProcessId);
  AddDefinition(NewName, False, 0); AddDefinition(PoolName, True, 4);
  try
    T := TStopwatch.StartNew;
    for I := 1 to Leases do begin C := OpenByDef(NewName); C.Free; end;
    NewUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    { Warm the pool before measuring leases that can reuse a physical connection. }
    C := OpenByDef(PoolName); C.Free;
    T := TStopwatch.StartNew;
    for I := 1 to Leases do begin C := OpenByDef(PoolName); C.Free; end;
    PoolUs := T.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Writeln(Format('BM-08 leases=%d new_us=%d pooled_us=%d', [Leases, NewUs, PoolUs]));
  finally
    FDManager.CloseConnectionDef(PoolName); FDManager.DeleteConnectionDef(PoolName);
    FDManager.CloseConnectionDef(NewName); FDManager.DeleteConnectionDef(NewName);
  end;
end;

var DriverLink: TFDPhysFBDriverLink;
begin
  DriverLink := TFDPhysFBDriverLink.Create(nil);
  try
    if IsFirebird then DriverLink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
    FDManager.Active := True;
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter19Checks async|cancel|tasks|pool|saturation|bench|poolbench');
    if SameText(ParamStr(1), 'async') then RunAsync
    else if SameText(ParamStr(1), 'cancel') then RunCancel
    else if SameText(ParamStr(1), 'tasks') then RunTasks
    else if SameText(ParamStr(1), 'pool') then RunPool
    else if SameText(ParamStr(1), 'saturation') then RunSaturation
    else if SameText(ParamStr(1), 'bench') then RunBench
    else if SameText(ParamStr(1), 'poolbench') then RunPoolBench
    else raise Exception.Create('Modo inválido.');
  except
    on E: Exception do begin Writeln(ErrOutput, E.ClassName, ': ', E.Message); ExitCode := 1; end;
  end;
  DriverLink.Free;
end.
