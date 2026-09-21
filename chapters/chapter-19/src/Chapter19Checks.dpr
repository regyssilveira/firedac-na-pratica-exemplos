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

  TSearchResult = class
  public
    Generation: Integer;
    Value: string;
    constructor Create(AGeneration: Integer; const AValue: string);
  end;

  TGenerationController = class
  private
    FCurrentGeneration: Integer;
    FDeliveredCount: Integer;
    FDiscardedCount: Integer;
    FPublishedValue: string;
    FCompleted: TEvent;
  public
    constructor Create(ACurrentGeneration: Integer);
    destructor Destroy; override;
    procedure Accept(AResult: TSearchResult);
    property Completed: TEvent read FCompleted;
    property DeliveredCount: Integer read FDeliveredCount;
    property DiscardedCount: Integer read FDiscardedCount;
    property PublishedValue: string read FPublishedValue;
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

constructor TSearchResult.Create(AGeneration: Integer; const AValue: string);
begin
  inherited Create;
  Generation := AGeneration;
  Value := AValue;
end;

constructor TGenerationController.Create(ACurrentGeneration: Integer);
begin
  inherited Create;
  FCurrentGeneration := ACurrentGeneration;
  FCompleted := TEvent.Create(nil, True, False, '');
end;

destructor TGenerationController.Destroy;
begin
  FCompleted.Free;
  inherited Destroy;
end;

procedure TGenerationController.Accept(AResult: TSearchResult);
begin
  try
    if AResult.Generation = FCurrentGeneration then
    begin
      Inc(FDeliveredCount);
      FPublishedValue := AResult.Value;
    end
    else
      Inc(FDiscardedCount);
    if FDeliveredCount + FDiscardedCount = 2 then
      FCompleted.SetEvent;
  finally
    AResult.Free;
  end;
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
var ConnectionParams: TStringList;
begin
  AConnection.LoginPrompt := False;
  if IsFirebird then ALink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
  ConnectionParams := TStringList.Create;
  try
    FillParams(ConnectionParams, False, 0);
    ConnectionParams.Values['DriverID'] := IfThen(IsFirebird, 'FB', 'SQLite');
    AConnection.Params.Assign(ConnectionParams);
  finally ConnectionParams.Free; end;
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
    Result := Format(
      '''
        WITH RECURSIVE seq(id) AS (
          SELECT 1
          UNION ALL
          SELECT id + 1 FROM seq WHERE id < %d
        )
        SELECT id, id %% 10 AS category_id, 'Product ' || id AS name
        FROM seq
        ''',
      [ARows]);
end;

function SlowSql: string;
begin
  if IsFirebird then
    Result := '''
      EXECUTE BLOCK AS DECLARE VARIABLE i BIGINT = 0; BEGIN
      WHILE (i < 50000000) DO i = i + 1; END
      '''
  else
    Result := '''
      CREATE TEMP TABLE ch19_cancel AS WITH RECURSIVE seq(id) AS
      (SELECT 1 UNION ALL SELECT id + 1 FROM seq WHERE id < 10000000) SELECT id FROM seq
      ''';
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
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
  Timer: TStopwatch; CallUs, TotalUs: Int64; Rows: Integer; Observer: TAsyncObserver;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link);
  Query := TFDQuery.Create(nil); Observer := TAsyncObserver.Create;
  try
    Query.Connection := Conn; Query.ResourceOptions.CmdExecMode := amAsync;
    Query.AfterOpen := Observer.HandleAfterOpen;
    Query.SQL.Text := SyntheticSql(100000); Timer := TStopwatch.StartNew; Query.Open;
    CallUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    WaitEvent(Observer.Completed); Query.ResourceOptions.CmdExecMode := amBlocking; Query.FetchAll;
    TotalUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Query.RecordCount = 100000, 'Async não materializou cem mil linhas.');
    Rows := Query.RecordCount;
    Query.Close; Query.ResourceOptions.CmdExecMode := amAsync;
    Query.OnError := Observer.HandleError; Query.SQL.Text := '''
      INSERT INTO product
      (id, sku, name, category_id, price, active)
      VALUES (1, 'DUP', 'Duplicate', 1, 1, 1)
      ''';
    try
      Query.ExecSQL;
      Sleep(20);
      CheckSynchronize(1);
      WaitCommand(Query);
    except
      on CaughtException: Exception do
      begin
        Observer.ErrorSeen := True;
        Observer.ErrorClass := CaughtException.ClassName;
      end;
    end;
    Check(Observer.ErrorSeen, 'Erro assíncrono não chegou ao handler.');
    Writeln(Format('EX-19-01 call_us=%d total_us=%d rows=%d error=%s',
      [CallUs, TotalUs, Rows, Observer.ErrorClass]));
  finally Observer.Free; Query.Free; Conn.Free; Link.Free; end;
end;

procedure RunCancel;
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
  Timer: TStopwatch; CancelUs: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link); Query := TFDQuery.Create(nil);
  try
    Query.Connection := Conn; Query.ResourceOptions.CmdExecMode := amAsync; Query.SQL.Text := SlowSql;
    Query.ExecSQL; Sleep(20); Timer := TStopwatch.StartNew; Query.AbortJob(True);
    CancelUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency; WaitCommand(Query);
    Check(Conn.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3,
      'Conexão não respondeu após cancelamento.');
    Query.Disconnect(True);
    Writeln(Format('EX-19-02 cancel_us=%d active=%s reusable=True',
      [CancelUs, BoolToStr(Query.Active, True)]));
  finally Query.Free; Conn.Free; Link.Free; end;
end;

procedure RunTasks;
const Count = 12;
var Tasks: TArray<ITask>; TaskIndex, Success: Integer;
begin
  SetLength(Tasks, Count); Success := 0;
  for TaskIndex := 0 to Count - 1 do
    Tasks[TaskIndex] := TTask.Run(TProc(
      procedure
      var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
      begin
        Link := TFDPhysFBDriverLink.Create(nil); Conn := nil; Query := nil;
        try
          Conn := NewDirect(Link); Query := TFDQuery.Create(nil); Query.Connection := Conn;
          Query.SQL.Text := 'SELECT COUNT(*) FROM product'; Query.Open;
          if Query.Fields[0].AsInteger = 3 then TInterlocked.Increment(Success);
        finally Query.Free; Conn.Free; Link.Free; end;
      end));
  TTask.WaitForAll(Tasks);
  Check(Success = Count, 'Nem todas as tasks concluíram com conexão própria.');
  Writeln(Format('EX-19-03 tasks=%d successes=%d ownership=per_task', [Count, Success]));
end;

procedure QueueSearchResult(AController: TGenerationController;
  AGeneration, ADelayMilliseconds: Integer; const AValue: string;
  out ATask: ITask);
begin
  ATask := TTask.Run(TProc(
    procedure
    var
      ResultData: TSearchResult;
    begin
      Sleep(ADelayMilliseconds);
      ResultData := TSearchResult.Create(AGeneration, AValue);
      TThread.Queue(nil,
        procedure
        begin
          AController.Accept(ResultData);
        end);
    end));
end;

procedure RunGenerationGuard;
var
  Controller: TGenerationController;
  OlderTask: ITask;
  CurrentTask: ITask;
begin
  Controller := TGenerationController.Create(2);
  try
    QueueSearchResult(Controller, 1, 50, 'resultado antigo', OlderTask);
    QueueSearchResult(Controller, 2, 5, 'resultado atual', CurrentTask);
    TTask.WaitForAll([OlderTask, CurrentTask]);
    WaitEvent(Controller.Completed);
    Check(Controller.DeliveredCount = 1,
      'A geração atual deveria ser publicada exatamente uma vez.');
    Check(Controller.DiscardedCount = 1,
      'A geração antiga deveria ser descartada exatamente uma vez.');
    Check(Controller.PublishedValue = 'resultado atual',
      'Uma resposta obsoleta venceu a geração atual.');
    Writeln('EX-19-06 delivered=1 discarded=1 ownership=single_transfer');
  finally
    Controller.Free;
  end;
end;

procedure AddDefinition(const AName: string; APooled: Boolean; AMaximum: Integer);
var ConnectionParams: TStringList;
begin
  ConnectionParams := TStringList.Create;
  try
    FillParams(ConnectionParams, APooled, AMaximum);
    FDManager.AddConnectionDef(AName, IfThen(IsFirebird, 'FB', 'SQLite'), ConnectionParams);
  finally ConnectionParams.Free; end;
end;

function OpenByDef(const AName: string): TFDConnection;
begin
  Result := TFDConnection.Create(nil); Result.LoginPrompt := False;
  try Result.ConnectionDefName := AName; Result.Open; except Result.Free; raise; end;
end;

procedure RunPool;
const Count = 4;
var Name: string; Tasks: TArray<ITask>; TaskIndex, Success: Integer;
begin
  Name := 'CH19_POOL_' + IntToStr(GetCurrentProcessId); AddDefinition(Name, True, Count);
  SetLength(Tasks, Count); Success := 0;
  try
    for TaskIndex := 0 to Count - 1 do Tasks[TaskIndex] := TTask.Run(TProc(
      procedure
      var LeasedConnection: TFDConnection;
      begin
        LeasedConnection := OpenByDef(Name);
        try Sleep(30); if LeasedConnection.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3 then
          TInterlocked.Increment(Success); finally LeasedConnection.Free; end;
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
    try C3 := OpenByDef(Name); except on CaughtException: EFDException do Rejected := True; end;
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
var Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
  Timer: TStopwatch; BlockingUs, AsyncCallUs, AsyncTotalUs: Int64; Observer: TAsyncObserver;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewDirect(Link); Query := TFDQuery.Create(nil);
  Observer := TAsyncObserver.Create;
  try
    Query.Connection := Conn; Query.FetchOptions.Mode := fmAll; Query.SQL.Text := SyntheticSql(100000);
    Timer := TStopwatch.StartNew; Query.Open; Query.FetchAll;
    BlockingUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Query.RecordCount = 100000, 'Blocking divergiu.'); Query.Close;
    Query.ResourceOptions.CmdExecMode := amAsync; Query.AfterOpen := Observer.HandleAfterOpen;
    Timer := TStopwatch.StartNew; Query.Open;
    AsyncCallUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    WaitEvent(Observer.Completed); Query.ResourceOptions.CmdExecMode := amBlocking; Query.FetchAll;
    AsyncTotalUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Check(Query.RecordCount = 100000, 'Async divergiu.');
    Writeln(Format('BM-09 blocking_us=%d async_call_us=%d async_total_us=%d rows=100000',
      [BlockingUs, AsyncCallUs, AsyncTotalUs]));
  finally Observer.Free; Query.Free; Conn.Free; Link.Free; end;
end;

procedure RunPoolBench;
const Leases = 10;
var NewName, PoolName: string; LeasedConnection: TFDConnection; TaskIndex: Integer;
  Timer: TStopwatch; NewUs, PoolUs: Int64;
begin
  NewName := 'CH19_NEW_' + IntToStr(GetCurrentProcessId);
  PoolName := 'CH19_BENCH_POOL_' + IntToStr(GetCurrentProcessId);
  AddDefinition(NewName, False, 0); AddDefinition(PoolName, True, 4);
  try
    Timer := TStopwatch.StartNew;
    for TaskIndex := 1 to Leases do begin LeasedConnection := OpenByDef(NewName); LeasedConnection.Free; end;
    NewUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    { Warm the pool before measuring leases that can reuse a physical connection. }
    LeasedConnection := OpenByDef(PoolName); LeasedConnection.Free;
    Timer := TStopwatch.StartNew;
    for TaskIndex := 1 to Leases do begin LeasedConnection := OpenByDef(PoolName); LeasedConnection.Free; end;
    PoolUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
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
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter19Checks async|cancel|tasks|generation|pool|saturation|bench|poolbench');
    if SameText(ParamStr(1), 'async') then RunAsync
    else if SameText(ParamStr(1), 'cancel') then RunCancel
    else if SameText(ParamStr(1), 'tasks') then RunTasks
    else if SameText(ParamStr(1), 'generation') then RunGenerationGuard
    else if SameText(ParamStr(1), 'pool') then RunPool
    else if SameText(ParamStr(1), 'saturation') then RunSaturation
    else if SameText(ParamStr(1), 'bench') then RunBench
    else if SameText(ParamStr(1), 'poolbench') then RunPoolBench
    else raise Exception.Create('Modo inválido.');
  except
    on CaughtException: Exception do begin Writeln(ErrOutput, CaughtException.ClassName, ': ', CaughtException.Message); ExitCode := 1; end;
  end;
  DriverLink.Free;
end.
