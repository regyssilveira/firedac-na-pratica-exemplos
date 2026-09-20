program Chapter18Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  Winapi.PsAPI,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Tracer,
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
  FireDAC.Moni.Base,
  FireDAC.Moni.FlatFile,
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
  Result := SameText(RequiredEnvironment('CH18_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH18_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

function NewConnection(ALink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Configure(Result, ALink);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function SyntheticSql: string;
begin
  if IsFirebird then
    Result := 'SELECT id, category_id, name FROM benchmark_product_rows(:row_count)'
  else
    Result := '''
      WITH RECURSIVE seq(id) AS (SELECT 1 UNION ALL SELECT id + 1 FROM seq
      WHERE id < :row_count) SELECT id, id % 10 AS category_id,
      'Product ' || id AS name FROM seq
      ''';
end;

function DetailSql: string;
begin
  if IsFirebird then
    Result := '''
      SELECT CAST(:id AS INTEGER) AS id,
      MOD(CAST(:id AS INTEGER), 10) AS category_id FROM RDB$DATABASE
      '''
  else
    Result := 'SELECT :id AS id, :id % 10 AS category_id';
end;

function WorkingSet: UInt64;
var MemoryCounters: TProcessMemoryCounters;
begin
  ZeroMemory(@MemoryCounters, SizeOf(MemoryCounters)); MemoryCounters.cb := SizeOf(MemoryCounters);
  if not GetProcessMemoryInfo(GetCurrentProcess, @MemoryCounters, SizeOf(MemoryCounters)) then RaiseLastOSError;
  Result := MemoryCounters.WorkingSetSize;
end;

procedure RunNPlusOne;
var
  Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
  Monitor: TFDMoniFlatFileClientLink; TraceEnabled: Boolean; TraceFile: string;
  IterationIndex, Calls, BatchCalls: Integer; SumN1, SumBatch: Int64;
  Timer: TStopwatch; N1Us, BatchUs: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := TFDConnection.Create(nil);
  Monitor := TFDMoniFlatFileClientLink.Create(nil);
  TraceEnabled := False;
  try
    Configure(Conn, Link);
    TraceEnabled := SameText(GetEnvironmentVariable('CH18_ENABLE_TRACE'), '1');
    if TraceEnabled then
    begin
      TraceFile := RequiredEnvironment('CH18_TRACE_FILE');
      if FileExists(TraceFile) then TFile.Delete(TraceFile);
      Monitor.FileName := TraceFile; Monitor.FileAppend := False;
      FADShowTraces := False;
      Monitor.ShowTraces := False; Monitor.Tracing := True;
      Conn.Params.Values['MonitorBy'] := 'FlatFile';
    end;
    Conn.Open;
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn; Query.SQL.Text := DetailSql;
      Calls := 0; SumN1 := 0; Timer := TStopwatch.StartNew;
      for IterationIndex := 1 to 100 do
      begin
        Query.Close; Query.ParamByName('id').AsInteger := IterationIndex; Query.Open;
        Inc(SumN1, Query.FieldByName('category_id').AsInteger); Inc(Calls);
      end;
      N1Us := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      Query.Close; Query.SQL.Text := SyntheticSql; Query.ParamByName('row_count').AsInteger := 100;
      SumBatch := 0; BatchCalls := 1; Timer := TStopwatch.StartNew; Query.Open;
      while not Query.Eof do begin Inc(SumBatch, Query.FieldByName('category_id').AsInteger); Query.Next; end;
      BatchUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      Check(SumN1 = SumBatch, 'N+1 e lote produziram resultados diferentes.');
      Check((Calls = 100) and (BatchCalls = 1), 'Contagem de comandos inesperada.');
      Writeln(Format('EX-18-01 n1_calls=%d batch_calls=%d checksum=%d n1_us=%d batch_us=%d',
        [Calls, BatchCalls, SumBatch, N1Us, BatchUs]));
    finally Query.Free; end;
  finally
    if TraceEnabled then Monitor.Tracing := False;
    Conn.Free; Monitor.Free; Link.Free;
  end;
end;

procedure RunPrepare;
const Iterations = 500;
var
  Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query, Fresh: TFDQuery;
  IterationIndex: Integer; SumFresh, SumReuse, SumPrepared: Int64;
  Timer: TStopwatch; FreshUs, ReuseUs, PreparedUs: Int64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewConnection(Link);
  try
    SumFresh := 0; Timer := TStopwatch.StartNew;
    for IterationIndex := 1 to Iterations do
    begin
      Fresh := TFDQuery.Create(nil);
      try
        Fresh.Connection := Conn; Fresh.SQL.Text := DetailSql;
        Fresh.ParamByName('id').AsInteger := IterationIndex; Fresh.Open;
        Inc(SumFresh, Fresh.FieldByName('category_id').AsInteger);
      finally Fresh.Free; end;
    end;
    FreshUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn; Query.SQL.Text := DetailSql; SumReuse := 0; Timer := TStopwatch.StartNew;
      for IterationIndex := 1 to Iterations do begin Query.Close; Query.ParamByName('id').AsInteger := IterationIndex; Query.Open;
        Inc(SumReuse, Query.FieldByName('category_id').AsInteger); end;
      ReuseUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      Query.Close; Query.Unprepare; Query.Prepare; SumPrepared := 0; Timer := TStopwatch.StartNew;
      for IterationIndex := 1 to Iterations do begin Query.Close; Query.ParamByName('id').AsInteger := IterationIndex; Query.Open;
        Inc(SumPrepared, Query.FieldByName('category_id').AsInteger); end;
      PreparedUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      Check((SumFresh = SumReuse) and (SumReuse = SumPrepared),
        'Variantes de prepare divergiram.');
      Writeln(Format(
        'EX-18-02 iterations=%d checksum=%d fresh_us=%d reuse_us=%d prepared_us=%d',
        [Iterations, SumPrepared, FreshUs, ReuseUs, PreparedUs]));
    finally Query.Free; end;
  finally Conn.Free; Link.Free; end;
end;

procedure RunFetch;
var
  Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query: TFDQuery;
  Timer: TStopwatch; OpenUs, TotalUs: Int64; InitialRows, Rows: Integer;
  BeforeMem, AfterMem: UInt64;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewConnection(Link);
  try
    Query := TFDQuery.Create(nil);
    try
      Query.Connection := Conn; Query.FetchOptions.Mode := fmOnDemand; Query.FetchOptions.RowsetSize := 64;
      Query.FetchOptions.AutoFetchAll := afDisable; Query.SQL.Text := SyntheticSql;
      Query.ParamByName('row_count').AsInteger := 100000; BeforeMem := WorkingSet;
      Timer := TStopwatch.StartNew; Query.Open; OpenUs := Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      InitialRows := Query.RecordCount; Timer := TStopwatch.StartNew; Query.FetchAll;
      TotalUs := OpenUs + Timer.ElapsedTicks * 1000000 div TStopwatch.Frequency;
      Rows := Query.RecordCount; AfterMem := WorkingSet;
      Check((InitialRows > 0) and (InitialRows < Rows) and (Rows = 100000),
        'Fetch sob demanda não apresentou janela parcial seguida do total.');
      Writeln(Format('EX-18-03 open_us=%d total_us=%d initial_rows=%d rows=%d memory_delta=%d',
        [OpenUs, TotalUs, InitialRows, Rows, Int64(AfterMem) - Int64(BeforeMem)]));
    finally Query.Free; end;
  finally Conn.Free; Link.Free; end;
end;

procedure RunPlan;
var
  Link: TFDPhysFBDriverLink; Conn: TFDConnection; Query, PlanQuery: TFDQuery; Plan: string;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewConnection(Link);
  try
    Query := TFDQuery.Create(nil); PlanQuery := TFDQuery.Create(nil);
    try
      Query.Connection := Conn; PlanQuery.Connection := Conn;
      if IsFirebird then
      begin
        Query.SQL.Text := 'SELECT id FROM product /* CH18_PLAN_TARGET */ WHERE name = :name';
        Query.ParamByName('name').AsString := 'Coffee'; Query.Prepare;
        PlanQuery.SQL.Text := '''
          SELECT FIRST 1 MON$EXPLAINED_PLAN FROM MON$COMPILED_STATEMENTS
          WHERE MON$SQL_TEXT CONTAINING 'CH18_PLAN_TARGET'
          ''';
        PlanQuery.Open; Plan := PlanQuery.Fields[0].AsString;
      end
      else
      begin
        PlanQuery.SQL.Text := 'EXPLAIN QUERY PLAN SELECT id FROM product WHERE name = :name';
        PlanQuery.ParamByName('name').AsString := 'Coffee'; PlanQuery.Open; Plan := PlanQuery.Fields[PlanQuery.FieldCount - 1].AsString;
      end;
      Check(Plan <> '', 'SGBD não retornou plano.');
      Check(Pos('INDEX', UpperCase(Plan)) > 0, 'Plano não registrou acesso por índice: ' + Plan);
      Writeln('EX-18-04 plan=' + StringReplace(Plan, sLineBreak, ' | ', [rfReplaceAll]));
    finally PlanQuery.Free; Query.Free; end;
  finally Conn.Free; Link.Free; end;
end;

procedure RunInfo;
var
  Link: TFDPhysFBDriverLink; Conn: TFDConnection; Report: TStringList;
  IterationIndex: Integer; Sanitized: string;
begin
  Link := TFDPhysFBDriverLink.Create(nil); Conn := NewConnection(Link); Report := TStringList.Create;
  try
    Conn.GetInfoReport(Report, [riFireDAC, riClient, riSession]);
    Check(Report.Count > 3, 'GetInfoReport retornou contexto insuficiente.');
    Sanitized := '';
    for IterationIndex := 0 to Report.Count - 1 do
      if (Pos('Password', Report[IterationIndex]) = 0) and (Pos('User_Name', Report[IterationIndex]) = 0) and
         (Pos('Database=', Report[IterationIndex]) = 0) and (Pos('Client DLL name', Report[IterationIndex]) = 0) and
         (Pos('/tcp (', Report[IterationIndex]) = 0) then
        Sanitized := Sanitized + Report[IterationIndex] + sLineBreak;
    Check(Pos('FireDAC', Sanitized) > 0, 'Relatório sanitizado perdeu versão FireDAC.');
    TFile.WriteAllText(RequiredEnvironment('CH18_INFO_FILE'), Sanitized, TEncoding.UTF8);
    Writeln(Format('EX-18-05 report_lines=%d sanitized_bytes=%d',
      [Report.Count, TEncoding.UTF8.GetByteCount(Sanitized)]));
  finally Report.Free; Conn.Free; Link.Free; end;
end;

begin
  try
    if ParamCount <> 1 then raise Exception.Create('Uso: Chapter18Checks nplusone|prepare|fetch|plan|info');
    if SameText(ParamStr(1), 'nplusone') then RunNPlusOne
    else if SameText(ParamStr(1), 'prepare') then RunPrepare
    else if SameText(ParamStr(1), 'fetch') then RunFetch
    else if SameText(ParamStr(1), 'plan') then RunPlan
    else if SameText(ParamStr(1), 'info') then RunInfo
    else raise Exception.Create('Modo inválido.');
  except
    on CaughtException: Exception do begin Writeln(ErrOutput, CaughtException.ClassName, ': ', CaughtException.Message); ExitCode := 1; end;
  end;
end.
