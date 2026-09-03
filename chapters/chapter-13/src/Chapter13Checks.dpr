program Chapter13Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.IOUtils,
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
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client,
  FireDAC.Comp.BatchMove,
  FireDAC.Comp.BatchMove.Text,
  FireDAC.Comp.BatchMove.SQL;

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
  Result := SameText(RequiredEnvironment('CH13_DRIVER'), 'FB');
end;

procedure ConfigureConnectionFor(AConnection: TFDConnection;
  AFBLink: TFDPhysFBDriverLink; AUseFirebird: Boolean);
begin
  AConnection.LoginPrompt := False;
  if AUseFirebird then
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH13_SQLITE_DATABASE');
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end;
end;

function NewConnectionFor(AFBLink: TFDPhysFBDriverLink;
  AUseFirebird: Boolean): TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    ConfigureConnectionFor(Result, AFBLink, AUseFirebird);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

function NewConnection(AFBLink: TFDPhysFBDriverLink): TFDConnection;
begin
  Result := NewConnectionFor(AFBLink, IsFirebird);
end;

procedure DeleteProducts(AConnection: TFDConnection; AFirstId, ALastId: Int64);
begin
  AConnection.ExecSQL(
    'DELETE FROM product WHERE id BETWEEN :first_id AND :last_id',
    [AFirstId, ALastId]);
end;

procedure ConfigureInsert(AQuery: TFDQuery);
begin
  AQuery.SQL.Text :=
    'INSERT INTO product ' +
    '(id, sku, name, category_id, price, active, version) ' +
    'VALUES (:id, :sku, :name, :category_id, :price, :active, :version)';
  AQuery.ParamByName('id').DataType := ftLargeint;
  AQuery.ParamByName('sku').DataType := ftString;
  AQuery.ParamByName('sku').Size := 30;
  AQuery.ParamByName('name').DataType := ftString;
  AQuery.ParamByName('name').Size := 120;
  AQuery.ParamByName('category_id').DataType := ftLargeint;
  AQuery.ParamByName('price').DataType := ftCurrency;
  AQuery.ParamByName('active').DataType := ftBoolean;
  AQuery.ParamByName('version').DataType := ftLargeint;
  AQuery.Prepare;
end;

procedure FillInsertParams(AQuery: TFDQuery; ACount: Integer;
  const ASkuPrefix: string; ADuplicateIndex: Integer = -1;
  AFirstId: Int64 = 130001);
var
  I, SkuIndex: Integer;
begin
  AQuery.Params.ArraySize := ACount;
  for I := 0 to ACount - 1 do
  begin
    SkuIndex := I;
    if I = ADuplicateIndex then
      SkuIndex := 0;
    AQuery.ParamByName('id').AsLargeInts[I] := AFirstId + I;
    AQuery.ParamByName('sku').AsStrings[I] :=
      Format('%s-%.6d', [ASkuPrefix, SkuIndex]);
    AQuery.ParamByName('name').AsStrings[I] :=
      Format('Produto de carga %.6d', [I]);
    AQuery.ParamByName('category_id').AsLargeInts[I] := 1;
    AQuery.ParamByName('price').AsCurrencys[I] := 10 + (I mod 100) / 10;
    AQuery.ParamByName('active').AsBooleans[I] := True;
    AQuery.ParamByName('version').AsLargeInts[I] := 1;
  end;
end;

procedure RunBenchmark(const AMethod: string; ACount: Integer);
const
  CFirstId = 140001;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
  Stopwatch: TStopwatch;
  I: Integer;
  ElapsedMs, RowsPerSecond: Double;
  DriverName, Architecture: string;
begin
  Check(ACount > 0, 'A quantidade do benchmark deve ser positiva.');
  Check(ACount <= 100000, 'O benchmark aceita no máximo 100000 linhas.');
  Check(SameText(AMethod, 'line') or SameText(AMethod, 'array'),
    'Método inválido; use line ou array.');
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    DeleteProducts(Connection, CFirstId, CFirstId + ACount - 1);
    Query.Connection := Connection;
    ConfigureInsert(Query);
    if SameText(AMethod, 'array') then
      FillInsertParams(Query, ACount, 'EX13BM-A', -1, CFirstId);
    Connection.StartTransaction;
    try
      Stopwatch := TStopwatch.StartNew;
      if SameText(AMethod, 'array') then
        Query.Execute(ACount, 0)
      else
        for I := 0 to ACount - 1 do
        begin
          Query.ParamByName('id').AsLargeInt := CFirstId + I;
          Query.ParamByName('sku').AsString := Format('EX13BM-L-%.6d', [I]);
          Query.ParamByName('name').AsString := Format('Produto benchmark %.6d', [I]);
          Query.ParamByName('category_id').AsLargeInt := 1;
          Query.ParamByName('price').AsCurrency := 10 + (I mod 100) / 10;
          Query.ParamByName('active').AsBoolean := True;
          Query.ParamByName('version').AsLargeInt := 1;
          Query.ExecSQL;
        end;
      Stopwatch.Stop;
      Connection.Commit;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE id BETWEEN :first_id AND :last_id',
      [CFirstId, CFirstId + ACount - 1]) = ACount,
      'Benchmark não persistiu a quantidade esperada.');
    ElapsedMs := Stopwatch.Elapsed.TotalMilliseconds;
    if ElapsedMs <= 0 then ElapsedMs := 0.001;
    RowsPerSecond := ACount * 1000 / ElapsedMs;
    if IsFirebird then DriverName := 'FB' else DriverName := 'SQLite';
    Architecture := GetEnvironmentVariable('CH13_ARCH');
    if Architecture = '' then Architecture := 'unknown';
    Writeln(Format('%s;%s;%s;%d;%.3f;%.2f',
      [DriverName, Architecture, LowerCase(AMethod), ACount,
       ElapsedMs, RowsPerSecond], TFormatSettings.Invariant));
  finally
    if Connection.InTransaction then Connection.Rollback;
    DeleteProducts(Connection, CFirstId, CFirstId + ACount - 1);
    Query.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunArrayInsert;
const
  CCount = 1000;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    DeleteProducts(Connection, 130001, 131000);
    Query.Connection := Connection;
    ConfigureInsert(Query);
    FillInsertParams(Query, CCount, 'EX13A');
    Connection.StartTransaction;
    try
      Query.Execute(CCount, 0);
      Connection.Commit;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE id BETWEEN 130001 AND 131000') = CCount,
      'Array DML não inseriu exatamente mil produtos.');
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE sku LIKE ''EX13A-%''') = CCount,
      'Array DML produziu SKUs ausentes ou duplicados.');
    Writeln('EX-13-01 aprovado: Array DML inseriu e confirmou 1000 produtos.');
  finally
    if Connection.InTransaction then Connection.Rollback;
    DeleteProducts(Connection, 130001, 131000);
    Query.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunArrayError;
const
  CCount = 5;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Query: TFDQuery;
  Failed: Boolean;
  ErrorSummary: string;
  I: Integer;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Query := TFDQuery.Create(nil);
  try
    DeleteProducts(Connection, 130001, 130005);
    Query.Connection := Connection;
    ConfigureInsert(Query);
    FillInsertParams(Query, CCount, 'EX13E', 2);
    Failed := False;
    ErrorSummary := '';
    Connection.StartTransaction;
    try
      try
        Query.Execute(CCount, 0);
      except
        on E: EFDDBEngineException do
        begin
          Failed := True;
          for I := 0 to E.ErrorCount - 1 do
          begin
            if ErrorSummary <> '' then ErrorSummary := ErrorSummary + ',';
            ErrorSummary := ErrorSummary + IntToStr(E.Errors[I].RowIndex);
          end;
        end;
      end;
      Check(Failed, 'SKU duplicado no array não produziu erro do banco.');
      Connection.Rollback;
    except
      if Connection.InTransaction then Connection.Rollback;
      raise;
    end;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE id BETWEEN 130001 AND 130005') = 0,
      'Rollback do array deixou linhas parciais persistidas.');
    Writeln('EX-13-02 aprovado: lote inválido revertido; RowIndex=', ErrorSummary);
  finally
    if Connection.InTransaction then Connection.Rollback;
    DeleteProducts(Connection, 130001, 130005);
    Query.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure RunCsv;
var
  Link: TFDPhysFBDriverLink;
  Connection: TFDConnection;
  Batch: TFDBatchMove;
  Reader: TFDBatchMoveTextReader;
  Writer: TFDBatchMoveSQLWriter;
  CsvFile: string;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Connection := NewConnection(Link);
  Batch := TFDBatchMove.Create(nil);
  Reader := TFDBatchMoveTextReader.Create(Batch);
  Writer := TFDBatchMoveSQLWriter.Create(Batch);
  try
    DeleteProducts(Connection, 133001, 133003);
    CsvFile := RequiredEnvironment('CH13_CSV_FILE');
    Check(TFile.Exists(CsvFile), 'Arquivo CSV não encontrado: ' + CsvFile);
    Reader.FileName := CsvFile;
    Reader.Encoding := ecUTF8;
    Reader.DataDef.Separator := ';';
    Reader.DataDef.FormatSettings.DecimalSeparator := '.';
    Reader.DataDef.FormatSettings.ThousandSeparator := ',';
    Reader.DataDef.WithFieldNames := True;
    Reader.DataDef.Fields.Add.Define('id',
      FireDAC.Stan.Intf.dtInt64, 0, 0, 0);
    Reader.DataDef.Fields.Add.Define('sku',
      FireDAC.Stan.Intf.dtWideString, 30, 0, 0);
    Reader.DataDef.Fields.Add.Define('name',
      FireDAC.Stan.Intf.dtWideString, 120, 0, 0);
    Reader.DataDef.Fields.Add.Define('category_id',
      FireDAC.Stan.Intf.dtInt64, 0, 0, 0);
    Reader.DataDef.Fields.Add.Define('price',
      FireDAC.Stan.Intf.dtFMTBcd, 0, 18, 2);
    Reader.DataDef.Fields.Add.Define('active',
      FireDAC.Stan.Intf.dtInt16, 0, 0, 0);
    Reader.DataDef.Fields.Add.Define('version',
      FireDAC.Stan.Intf.dtInt64, 0, 0, 0);
    Writer.Connection := Connection;
    Writer.TableName := 'product';
    Writer.WriteSQL :=
      'INSERT INTO product ' +
      '(id, sku, name, category_id, price, active, version) ' +
      'VALUES (:id, :sku, :name, :category_id, :price, ' +
      'CASE WHEN :active = 1 THEN TRUE ELSE FALSE END, :version)';
    Batch.Mode := dmAlwaysInsert;
    Batch.CommitCount := 100;
    Batch.Execute;
    Check(Connection.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE id BETWEEN 133001 AND 133003') = 3,
      'Batch Move CSV não gravou três produtos.');
    Check(VarToStr(Connection.ExecSQLScalar(
      'SELECT name FROM product WHERE id = 133003')) = 'Caf' + #$00E9 + ' para desenvolvedor',
      'Batch Move não preservou UTF-8.');
    Check(Abs(Double(Connection.ExecSQLScalar(
      'SELECT price FROM product WHERE id = 133002')) - 89.50) < 0.001,
      'Batch Move não preservou o decimal do preço.');
    Writeln('EX-13-03 aprovado: CSV UTF-8 importado com 3 linhas e tipos conferidos.');
  finally
    DeleteProducts(Connection, 133001, 133003);
    Batch.Free;
    Connection.Free;
    Link.Free;
  end;
end;

procedure PrepareTransferSource(AConnection: TFDConnection; ASourceIsFirebird: Boolean);
var
  ActiveLiteral: string;
begin
  DeleteProducts(AConnection, 134001, 134002);
  if ASourceIsFirebird then ActiveLiteral := 'TRUE' else ActiveLiteral := '1';
  AConnection.ExecSQL(
    'INSERT INTO product (id, sku, name, category_id, price, active, version) ' +
    'VALUES (134001, ''EX13MOVE-001'', ''Origem caf' + #$00E9 + ''', 2, 12.34, ' +
    ActiveLiteral + ', 1)');
  AConnection.ExecSQL(
    'INSERT INTO product (id, sku, name, category_id, price, active, version) ' +
    'VALUES (134002, ''EX13MOVE-002'', ''Origem teclado'', 1, 98.76, ' +
    ActiveLiteral + ', 1)');
end;

procedure RunTransfer;
var
  Link: TFDPhysFBDriverLink;
  Source, Dest: TFDConnection;
  Batch: TFDBatchMove;
  Reader: TFDBatchMoveSQLReader;
  Writer: TFDBatchMoveSQLWriter;
begin
  Link := TFDPhysFBDriverLink.Create(nil);
  Source := NewConnectionFor(Link, not IsFirebird);
  Dest := NewConnectionFor(Link, IsFirebird);
  Batch := TFDBatchMove.Create(nil);
  Reader := TFDBatchMoveSQLReader.Create(Batch);
  Writer := TFDBatchMoveSQLWriter.Create(Batch);
  try
    DeleteProducts(Dest, 134001, 134002);
    PrepareTransferSource(Source, not IsFirebird);
    Reader.Connection := Source;
    Reader.ReadSQL :=
      'SELECT id, sku, name, category_id, price, version ' +
      'FROM product WHERE id BETWEEN 134001 AND 134002 ORDER BY id';
    Writer.Connection := Dest;
    Writer.TableName := 'product';
    Writer.WriteSQL :=
      'INSERT INTO product ' +
      '(id, sku, name, category_id, price, version) ' +
      'VALUES (:id, :sku, :name, :category_id, :price, :version)';
    Batch.Mode := dmAlwaysInsert;
    Batch.CommitCount := 100;
    Batch.Execute;
    Check(Dest.ExecSQLScalar(
      'SELECT COUNT(*) FROM product WHERE id BETWEEN 134001 AND 134002') = 2,
      'Transferência não gravou duas linhas no destino.');
    Check(VarToStr(Dest.ExecSQLScalar(
      'SELECT name FROM product WHERE id = 134001')) = 'Origem caf' + #$00E9,
      'Transferência não preservou Unicode.');
    Check(Abs(Double(Dest.ExecSQLScalar(
      'SELECT price FROM product WHERE id = 134002')) - 98.76) < 0.001,
      'Transferência não preservou precisão decimal.');
    if IsFirebird then
      Writeln('EX-13-04 aprovado: SQLite -> Firebird preservou linhas, texto e decimal.')
    else
      Writeln('EX-13-04 aprovado: Firebird -> SQLite preservou linhas, texto e decimal.');
  finally
    DeleteProducts(Dest, 134001, 134002);
    DeleteProducts(Source, 134001, 134002);
    Batch.Free;
    Dest.Free;
    Source.Free;
    Link.Free;
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter13Checks array|error|csv|transfer');
  Writeln('  ou Chapter13Checks benchmark line|array quantidade');
end;

begin
  try
    if (ParamCount = 3) and SameText(ParamStr(1), 'benchmark') then
      RunBenchmark(ParamStr(2), StrToInt(ParamStr(3)))
    else if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'array') then RunArrayInsert
    else if SameText(ParamStr(1), 'error') then RunArrayError
    else if SameText(ParamStr(1), 'csv') then RunCsv
    else if SameText(ParamStr(1), 'transfer') then RunTransfer
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
