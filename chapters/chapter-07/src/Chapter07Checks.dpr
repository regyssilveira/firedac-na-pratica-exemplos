program Chapter07Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.Variants,
  System.Generics.Collections,
  System.Diagnostics,
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
  FireDAC.Comp.Client;

type
  TFilterContext = class
  private
    FText: string;
  public
    constructor Create(const AText: string);
    procedure AcceptProduct(DataSet: TDataSet; var Accept: Boolean);
  end;

constructor TFilterContext.Create(const AText: string);
begin
  inherited Create;
  FText := AText;
end;

procedure TFilterContext.AcceptProduct(DataSet: TDataSet; var Accept: Boolean);
var
  IsActive: Boolean;
begin
  if DataSet.FieldByName('active').DataType = ftBoolean then
    IsActive := DataSet.FieldByName('active').AsBoolean
  else
    IsActive := DataSet.FieldByName('active').AsInteger = 1;
  Accept := IsActive and ContainsText(DataSet.FieldByName('name').AsString, FText);
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
  Result := SameText(RequiredEnvironment('CH07_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH07_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

procedure WithConnection(const ATest: TProc<TFDConnection>);
var
  Connection: TFDConnection;
  FBLink: TFDPhysFBDriverLink;
begin
  Connection := TFDConnection.Create(nil);
  FBLink := TFDPhysFBDriverLink.Create(nil);
  try
    ConfigureConnection(Connection, FBLink);
    Connection.Open;
    ATest(Connection);
  finally
    Connection.Free;
    FBLink.Free;
  end;
end;

function OpenProducts(AConnection: TFDConnection): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := AConnection;
    Result.SQL.Text :=
      'SELECT id, sku, name, category_id, price, active FROM product ORDER BY id';
    Result.Open;
    Result.FetchAll;
  except
    Result.Free;
    raise;
  end;
end;

function VisibleCount(ADataSet: TDataSet): Integer;
begin
  Result := 0;
  ADataSet.First;
  while not ADataSet.Eof do
  begin
    Inc(Result);
    ADataSet.Next;
  end;
end;

procedure RunLocateLookup;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      Saved: TBookmark;
      Value: Variant;
      OriginalId: Int64;
    begin
      Query := OpenProducts(Connection);
      try
        Query.First;
        OriginalId := Query.FieldByName('id').AsLargeInt;
        Saved := Query.GetBookmark;
        try
          Check(Query.Locate('sku', 'beb-002', [loCaseInsensitive]),
            'Locate case-insensitive não encontrou BEB-002.');
          Check(Query.FieldByName('id').AsLargeInt = 2,
            'Locate simples posicionou no id incorreto.');
          Check(Query.Locate('category_id;sku',
            VarArrayOf([2, 'ALI-001']), []),
            'Locate composto não encontrou categoria 2/ALI-001.');
          Check(not Query.Locate('sku', 'INEXISTENTE', []),
            'Locate inexistente retornou verdadeiro.');
          Query.GotoBookmark(Saved);
          Check(Query.FieldByName('id').AsLargeInt = OriginalId,
            'Bookmark não restaurou a posição durante o mesmo snapshot.');
          Value := Query.Lookup('sku', 'BEB-001', 'id;price');
          Check(VarIsArray(Value), 'Lookup de dois campos não devolveu array Variant.');
          Check(Value[0] = 1, 'Lookup devolveu id incorreto.');
          Check(Query.FieldByName('id').AsLargeInt = OriginalId,
            'Lookup alterou o registro corrente.');
          Check(VarIsNull(Query.Lookup('sku', 'INEXISTENTE', 'id')),
            'Lookup inexistente não devolveu Null.');
        finally
          Query.FreeBookmark(Saved);
        end;
        Writeln('EX-07-01 aprovado: Locate, Lookup e bookmark mantiveram contratos.');
      finally
        Query.Free;
      end;
    end);
end;

procedure RunExpressionFilter;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
    begin
      Query := OpenProducts(Connection);
      try
        Query.Filter := 'price >= 20 AND name LIKE ''C%''';
        Query.Filtered := True;
        Check(VisibleCount(Query) = 1, 'Filtro por expressão não deixou uma linha.');
        Check(Query.FieldByName('sku').AsString = 'BEB-001',
          'Filtro por expressão deixou o produto incorreto.');
        Query.Filtered := False;
        Query.Filter := '';
        Check(VisibleCount(Query) = 3, 'Remoção do filtro não restaurou três linhas.');
        Writeln('EX-07-02 aprovado: expressão filtrou localmente e foi removida.');
      finally
        Query.Free;
      end;
    end);
end;

procedure RunCallbackFilter;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
      Context: TFilterContext;
    begin
      Query := OpenProducts(Connection);
      Context := TFilterContext.Create('queijo');
      try
        Query.OnFilterRecord := Context.AcceptProduct;
        Query.Filtered := True;
        Check(VisibleCount(Query) = 1, 'OnFilterRecord não deixou uma linha.');
        Check(Query.FieldByName('sku').AsString = 'ALI-001',
          'OnFilterRecord deixou o produto incorreto.');
        Query.Filtered := False;
        Query.OnFilterRecord := nil;
        Writeln('EX-07-03 aprovado: callback tratou booleano por driver e texto.');
      finally
        Context.Free;
        Query.Free;
      end;
    end);
end;

procedure RunLocalIndex;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Query: TFDQuery;
    begin
      Query := OpenProducts(Connection);
      try
        Query.IndexFieldNames := 'category_id;name;id';
        Check(Query.IndexFieldNames = 'category_id;name;id',
          'Índice local composto não permaneceu ativo.');
        Check(Query.Locate('category_id;name;id',
          VarArrayOf([1, 'Ch' + #$00E1 + ' mate', 2]), []),
          'Locate pela chave completa do índice falhou.');
        Query.SetRange([1], [1]);
        Check(VisibleCount(Query) = 2,
          'Range da categoria 1 não deixou dois produtos.');
        Query.CancelRange;
        Check(VisibleCount(Query) = 3,
          'CancelRange não restaurou o snapshot.');
        Writeln('EX-07-04 aprovado: índice composto sustentou Locate e range.');
      finally
        Query.Free;
      end;
    end);
end;

function CollectIds(ADataSet: TDataSet): string;
begin
  Result := '';
  ADataSet.First;
  while not ADataSet.Eof do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + ADataSet.FieldByName('id').AsString;
    ADataSet.Next;
  end;
end;

procedure RunLocalOrRemote;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Local, Remote: TFDQuery;
      LocalIds, RemoteIds: string;
    begin
      Local := OpenProducts(Connection);
      Remote := TFDQuery.Create(nil);
      try
        Local.Filter := 'category_id = 1';
        Local.Filtered := True;
        LocalIds := CollectIds(Local);

        Remote.Connection := Connection;
        Remote.SQL.Text :=
          'SELECT id FROM product WHERE category_id = :category_id ORDER BY id';
        Remote.ParamByName('category_id').AsLargeInt := 1;
        Remote.Open;
        Remote.FetchAll;
        RemoteIds := CollectIds(Remote);
        Check(LocalIds = '1,2', 'Filtro local não produziu ids 1,2.');
        Check(LocalIds = RemoteIds,
          'Filtro local e WHERE remoto produziram conjuntos diferentes.');
        Writeln('EX-07-05 aprovado: filtro local e WHERE remoto foram equivalentes.');
      finally
        Remote.Free;
        Local.Free;
      end;
    end);
end;

function SyntheticSql(ARemoteFilter: Boolean): string;
begin
  if IsFirebird then
  begin
    Result :=
      'SELECT id, category_id, name FROM benchmark_product_rows(:row_count)';
    if ARemoteFilter then
      Result := Result + ' WHERE category_id = :category_id';
  end
  else
  begin
    Result :=
      'WITH RECURSIVE seq(id) AS (SELECT 1 UNION ALL SELECT id + 1 FROM seq ' +
      'WHERE id < :row_count) SELECT id, id % 10 AS category_id, ' +
      '''Product '' || id AS name FROM seq';
    if ARemoteFilter then
      Result := Result + ' WHERE id % 10 = :category_id';
  end;
end;

procedure RunOneBenchmark(AConnection: TFDConnection; ARowCount: Integer);
var
  Local, Remote: TFDQuery;
  Timer: TStopwatch;
  FetchMs, FilterMs, RemoteMs: Int64;
  LocalCount, RemoteCount: Integer;
begin
  Local := TFDQuery.Create(nil);
  Remote := TFDQuery.Create(nil);
  try
    Local.Connection := AConnection;
    Local.SQL.Text := SyntheticSql(False);
    Local.ParamByName('row_count').AsInteger := ARowCount;
    Timer := TStopwatch.StartNew;
    Local.Open;
    Local.FetchAll;
    FetchMs := Timer.ElapsedMilliseconds;
    Timer := TStopwatch.StartNew;
    Local.Filter := 'category_id = 7';
    Local.Filtered := True;
    LocalCount := VisibleCount(Local);
    FilterMs := Timer.ElapsedMilliseconds;

    Remote.Connection := AConnection;
    Remote.SQL.Text := SyntheticSql(True);
    Remote.ParamByName('row_count').AsInteger := ARowCount;
    Remote.ParamByName('category_id').AsInteger := 7;
    Timer := TStopwatch.StartNew;
    Remote.Open;
    Remote.FetchAll;
    RemoteCount := VisibleCount(Remote);
    RemoteMs := Timer.ElapsedMilliseconds;
    Check(LocalCount = RemoteCount,
      'Benchmark comparou conjuntos com contagens diferentes.');
    Check(LocalCount = ARowCount div 10,
      'Seletividade sintética não produziu 10 por cento.');
    Writeln(Format(
      'BM-04 rows=%d local_fetch_ms=%d local_filter_ms=%d remote_ms=%d result_rows=%d',
      [ARowCount, FetchMs, FilterMs, RemoteMs, LocalCount]));
  finally
    Remote.Free;
    Local.Free;
  end;
end;

procedure RunBenchmark;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    begin
      RunOneBenchmark(Connection, 100);
      RunOneBenchmark(Connection, 10000);
      RunOneBenchmark(Connection, 1000000);
    end);
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter07Checks locate|filter|callback|index|compare|benchmark');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'locate') then
      RunLocateLookup
    else if SameText(ParamStr(1), 'filter') then
      RunExpressionFilter
    else if SameText(ParamStr(1), 'callback') then
      RunCallbackFilter
    else if SameText(ParamStr(1), 'index') then
      RunLocalIndex
    else if SameText(ParamStr(1), 'compare') then
      RunLocalOrRemote
    else if SameText(ParamStr(1), 'benchmark') then
      RunBenchmark
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
