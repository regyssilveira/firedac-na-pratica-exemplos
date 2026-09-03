program Chapter09Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Winapi.Windows,
  Winapi.PsAPI,
  Data.DB,
  Vcl.Forms,
  Vcl.StdCtrls,
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
  FireDAC.Moni.Base,
  FireDAC.Moni.FlatFile,
  FireDAC.Comp.Client;

type
  TLoadState = (lsLoading, lsPartial, lsComplete, lsCancelled, lsFailed);

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
  Result := SameText(RequiredEnvironment('CH09_DRIVER'), 'FB');
end;

function CurrentWorkingSet: UInt64;
var
  Counters: TProcessMemoryCounters;
begin
  ZeroMemory(@Counters, SizeOf(Counters));
  Counters.cb := SizeOf(Counters);
  if not GetProcessMemoryInfo(GetCurrentProcess, @Counters, SizeOf(Counters)) then
    RaiseLastOSError;
  Result := Counters.WorkingSetSize;
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH09_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

procedure WithConnection(const ATest: TProc<TFDConnection>);
var
  Connection: TFDConnection;
  FBLink: TFDPhysFBDriverLink;
  Monitor: TFDMoniFlatFileClientLink;
  TraceFile: string;
  TraceEnabled: Boolean;
begin
  Connection := TFDConnection.Create(nil);
  FBLink := TFDPhysFBDriverLink.Create(nil);
  Monitor := TFDMoniFlatFileClientLink.Create(nil);
  TraceEnabled := False;
  try
    TraceEnabled := SameText(GetEnvironmentVariable('CH09_ENABLE_TRACE'), '1');
    if TraceEnabled then
    begin
      TraceFile := RequiredEnvironment('CH09_TRACE_FILE');
      ForceDirectories(ExtractFilePath(TraceFile));
      if FileExists(TraceFile) then
        TFile.Delete(TraceFile);
      Monitor.FileName := TraceFile;
      { Keep automated runs non-interactive.  The trace remains on disk, but
        FireDAC must not display its finalization dialog. }
      Monitor.ShowTraces := False;
      Monitor.Tracing := True;
    end;
    ConfigureConnection(Connection, FBLink);
    if TraceEnabled then
      Connection.Params.Values['MonitorBy'] := 'FlatFile';
    Connection.Open;
    ATest(Connection);
  finally
    if TraceEnabled then
      Monitor.Tracing := False;
    Connection.Free;
    FBLink.Free;
    Monitor.Free;
  end;
end;

function SyntheticSql: string;
begin
  if IsFirebird then
    Result := 'SELECT id, category_id, name FROM benchmark_product_rows(:row_count)'
  else
    Result :=
      'WITH RECURSIVE seq(id) AS (SELECT 1 UNION ALL SELECT id + 1 FROM seq ' +
      'WHERE id < :row_count) SELECT id, id % 10 AS category_id, ' +
      '''Product '' || id AS name FROM seq';
end;

procedure ConfigureSynthetic(AQuery: TFDQuery; AMode: TFDFetchMode;
  ARowsetSize: Integer);
begin
  AQuery.FetchOptions.Mode := AMode;
  AQuery.FetchOptions.RowsetSize := ARowsetSize;
  if AMode = fmAll then
    AQuery.FetchOptions.AutoFetchAll := afAll
  else
    AQuery.FetchOptions.AutoFetchAll := afDisable;
  AQuery.SQL.Text := SyntheticSql;
  AQuery.ParamByName('row_count').AsInteger := 100000;
end;

procedure RunOnDemand;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      Timer: TStopwatch;
      OpenMs, AllMs: Int64;
      InitialRows: Integer;
      MemoryBefore, MemoryAfter: UInt64;
    begin
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;
        { Use a packet size that does not divide the fixture cardinality.  This
          makes SourceEOF observable during the final, partial packet instead
          of depending on an extra empty fetch after an exact packet boundary. }
        ConfigureSynthetic(Query, fmOnDemand, 64);
        MemoryBefore := CurrentWorkingSet;
        Timer := TStopwatch.StartNew;
        Query.Open;
        OpenMs := Timer.ElapsedMilliseconds;
        InitialRows := Query.RecordCount;
        Check((InitialRows > 0) and (InitialRows < 100000),
          'Open sob demanda materializou quantidade inesperada.');
        Check(not Query.SourceEOF, 'Open sob demanda já atingiu SourceEOF.');
        Timer := TStopwatch.StartNew;
        Query.FetchAll;
        AllMs := Timer.ElapsedMilliseconds;
        MemoryAfter := CurrentWorkingSet;
        Check(Query.SourceEOF, 'FetchAll não atingiu SourceEOF.');
        Check(Query.RecordCount = 100000, 'FetchAll não recebeu 100 mil linhas.');
        Writeln(Format(
          'EX-09-01 open_ms=%d initial_rows=%d fetch_all_ms=%d memory_delta=%d',
          [OpenMs, InitialRows, AllMs, Int64(MemoryAfter) - Int64(MemoryBefore)]));
      finally
        Query.Free;
      end;
    end);
end;

procedure RunAll;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      Timer: TStopwatch;
      OpenMs, CloseCursorMs: Int64;
      RowsAfterOpen: Integer;
      SourceEOFAfterOpen: Boolean;
      MemoryBefore, MemoryAfter: UInt64;
    begin
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;
        ConfigureSynthetic(Query, fmAll, 64);
        Query.FetchOptions.RecordCountMode := cmFetched;
        MemoryBefore := CurrentWorkingSet;
        Timer := TStopwatch.StartNew;
        Query.Open;
        OpenMs := Timer.ElapsedMilliseconds;
        MemoryAfter := CurrentWorkingSet;
        RowsAfterOpen := Query.RecordCount;
        Check(RowsAfterOpen = 100000, 'fmAll não recebeu 100 mil linhas.');
        SourceEOFAfterOpen := Query.SourceEOF;
        { Some drivers return the complete final rowset without performing the
          extra empty fetch that flips SourceEOF.  FetchAll is idempotent for
          the cache and explicitly exhausts/closes that cursor. }
        Timer := TStopwatch.StartNew;
        Query.FetchAll;
        CloseCursorMs := Timer.ElapsedMilliseconds;
        Check(Query.SourceEOF, 'FetchAll final não esgotou o cursor de origem.');
        Check(Query.RecordCount = RowsAfterOpen,
          'FetchAll final alterou um cache que já deveria estar completo.');
        Writeln(Format('EX-09-02 open_all_ms=%d rows=%d memory_delta=%d',
          [OpenMs, RowsAfterOpen,
           Int64(MemoryAfter) - Int64(MemoryBefore)]));
        Writeln(Format(
          'EX-09-02 source_eof_after_open=%s explicit_fetch_all_ms=%d',
          [BoolToStr(SourceEOFAfterOpen, True), CloseCursorMs]));
      finally
        Query.Free;
      end;
    end);
end;

procedure RunDeferredBlob;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Update, Query: TFDQuery;
      Data: TBytes;
      Input: TMemoryStream;
      I, BlobSize: Integer;
    begin
      SetLength(Data, 8192);
      for I := 0 to High(Data) do
        Data[I] := Byte((I * 17 + 3) mod 256);
      Input := TMemoryStream.Create;
      Update := TFDQuery.Create(nil);
      Query := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Input.WriteBuffer(Data[0], Length(Data));
        Input.Position := 0;
        Update.Connection := Connection;
        Update.SQL.Text := 'UPDATE product SET image_data = :image WHERE id = :id';
        Update.ParamByName('image').LoadFromStream(Input, ftBlob);
        Update.ParamByName('id').AsLargeInt := 1;
        Update.ExecSQL;

        Query.Connection := Connection;
        Query.FetchOptions.Mode := fmOnDemand;
        Query.FetchOptions.Items := Query.FetchOptions.Items - [fiBlobs];
        Query.SQL.Text :=
          'SELECT id, sku, name, image_data FROM product WHERE id = :id';
        Query.ParamByName('id').AsLargeInt := 1;
        Query.Open;
        Check(not (fiBlobs in Query.FetchOptions.Items),
          'fiBlobs permaneceu nos itens de fetch.');
        BlobSize := TBlobField(Query.FieldByName('image_data')).BlobSize;
        Check(BlobSize = 8192, 'Acesso tardio não recuperou o BLOB completo.');
        Writeln('EX-09-03 aprovado: fiBlobs removido; acesso tardio leu 8192 bytes.');
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
        Update.Free;
        Input.Free;
      end;
    end);
end;

function SlowCommandSql: string;
begin
  if IsFirebird then
    Result :=
      'EXECUTE BLOCK AS DECLARE VARIABLE i BIGINT = 0; BEGIN ' +
      'WHILE (i < 50000000) DO i = i + 1; END'
  else
    Result :=
      'CREATE TEMP TABLE ch09_cancel AS WITH RECURSIVE seq(id) AS ' +
      '(SELECT 1 UNION ALL SELECT id + 1 FROM seq WHERE id < 10000000) ' +
      'SELECT id FROM seq';
end;

procedure RunCancellation;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      Timer: TStopwatch;
      CancelMs: Int64;
      Deadline: UInt64;
      QuietRounds: Integer;
    begin
      Query := TFDQuery.Create(nil);
      try
        Query.Connection := Connection;
        Query.ResourceOptions.CmdExecMode := amAsync;
        Query.SQL.Text := SlowCommandSql;
        Query.ExecSQL;
        Sleep(20);
        Timer := TStopwatch.StartNew;
        Query.AbortJob(True);
        CancelMs := Timer.ElapsedMilliseconds;
        { The physical job may be finished while its main-thread completion
          notification is still queued.  Drain that notification before
          reusing/destroying the component (especially visible with FB). }
        Deadline := GetTickCount64 + 2000;
        QuietRounds := 0;
        repeat
          if CheckSynchronize(1) then
            QuietRounds := 0
          else
            Inc(QuietRounds);
        until (QuietRounds >= 10) or (GetTickCount64 >= Deadline);
        Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3,
          'Conexão não respondeu após AbortJob.');
        { AbortJob preserves the prepared command.  Disconnect(True) completes
          the documented cleanup sequence before the component is destroyed,
          avoiding a pending async notification during process shutdown. }
        Query.Disconnect(True);
        Writeln(Format(
          'EX-09-04 aprovado: AbortJob retornou em %d ms; active=%s; conexão utilizável.',
          [CancelMs, BoolToStr(Query.Active, True)]));
      finally
        Query.Free;
      end;
    end);
end;

procedure ApplyFeedback(AState: TLoadState; AStatus: TLabel;
  ASearch, ACancel: TButton);
begin
  case AState of
    lsLoading:
      begin AStatus.Caption := 'Carregando'; ASearch.Enabled := False;
        ACancel.Enabled := True; end;
    lsPartial:
      begin AStatus.Caption := 'Resultado parcial'; ASearch.Enabled := True;
        ACancel.Enabled := True; end;
    lsComplete:
      begin AStatus.Caption := 'Concluído'; ASearch.Enabled := True;
        ACancel.Enabled := False; end;
    lsCancelled:
      begin AStatus.Caption := 'Cancelado'; ASearch.Enabled := True;
        ACancel.Enabled := False; end;
    lsFailed:
      begin AStatus.Caption := 'Falhou'; ASearch.Enabled := True;
        ACancel.Enabled := False; end;
  end;
end;

procedure RunFeedback;
var
  Form: TForm;
  Status: TLabel;
  Search, Cancel: TButton;
  State: TLoadState;
begin
  Application.Initialize;
  Form := TForm.Create(nil);
  try
    Status := TLabel.Create(Form); Status.Parent := Form;
    Search := TButton.Create(Form); Search.Parent := Form;
    Cancel := TButton.Create(Form); Cancel.Parent := Form;
    for State := Low(TLoadState) to High(TLoadState) do
    begin
      ApplyFeedback(State, Status, Search, Cancel);
      case State of
        lsLoading: Check((not Search.Enabled) and Cancel.Enabled,
          'Estado carregando habilitou ações incorretas.');
        lsPartial: Check(Search.Enabled and Cancel.Enabled,
          'Estado parcial não permitiu nova busca e cancelamento.');
      else
        Check(Search.Enabled and not Cancel.Enabled,
          'Estado terminal manteve ações incorretas.');
      end;
    end;
    Check(Status.Caption = 'Falhou', 'Último estado visual não foi Falhou.');
    Writeln('EX-09-05 aprovado: cinco estados VCL controlaram busca e cancelamento.');
  finally
    Form.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter09Checks ondemand|all|blob|cancel|feedback');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'ondemand') then
      RunOnDemand
    else if SameText(ParamStr(1), 'all') then
      RunAll
    else if SameText(ParamStr(1), 'blob') then
      RunDeferredBlob
    else if SameText(ParamStr(1), 'cancel') then
      RunCancellation
    else if SameText(ParamStr(1), 'feedback') then
      RunFeedback
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
