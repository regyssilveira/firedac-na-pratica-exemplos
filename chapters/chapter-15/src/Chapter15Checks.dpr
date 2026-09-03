program Chapter15Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  System.Diagnostics,
  System.IOUtils,
  System.Variants,
  Winapi.ActiveX,
  Data.DB,
  Data.DBJson,
  Xml.Win.msxmldom,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.StorageBin,
  FireDAC.Stan.StorageXML,
  FireDAC.Stan.StorageJSON,
  FireDAC.DatS,
  FireDAC.Comp.DataSet,
  FireDAC.Comp.Client;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function WorkFile(const AName: string): string;
var
  Dir: string;
begin
  Dir := GetEnvironmentVariable('CH15_TEMP_DIR');
  if Dir = '' then
    raise Exception.Create('Variável obrigatória ausente: CH15_TEMP_DIR');
  ForceDirectories(Dir);
  Result := TPath.Combine(Dir, AName);
end;

procedure DeleteIfExists(const AFileName: string);
begin
  if TFile.Exists(AFileName) then
    TFile.Delete(AFileName);
end;

procedure DefineCache(ATable: TFDMemTable);
begin
  ATable.FieldDefs.Add('id', ftLargeint, 0, True);
  ATable.FieldDefs.Add('name', ftWideString, 100, True);
  with ATable.FieldDefs.AddFieldDef do
  begin
    Name := 'price';
    DataType := ftFMTBcd;
    Precision := 18;
    Size := 2;
    Required := True;
  end;
  ATable.FieldDefs.Add('note', ftWideString, 200, False);
  ATable.FieldDefs.Add('changed_at', ftDateTime, 0, True);
  ATable.FieldDefs.Add('payload', ftBlob, 0, False);
  ATable.CreateDataSet;
  ATable.CachedUpdates := True;
end;

procedure SeedCache(ATable: TFDMemTable);
var
  Bytes: TBytes;
begin
  ATable.Append;
  ATable.FieldByName('id').AsLargeInt := 1;
  ATable.FieldByName('name').AsString := 'Caf' + #$00E9 + ' especial';
  ATable.FieldByName('price').AsCurrency := 1234.56;
  ATable.FieldByName('note').Clear;
  ATable.FieldByName('changed_at').AsDateTime := EncodeDateTime(2026, 9, 4, 12, 34, 56, 0);
  Bytes := TBytes.Create($00, $7F, $80, $FF);
  TBlobField(ATable.FieldByName('payload')).AsBytes := Bytes;
  ATable.Post;
  ATable.AppendRecord([Int64(2), 'Teclado', Currency(199.90), 'ABNT2',
    EncodeDateTime(2026, 9, 4, 13, 0, 0, 0), Null]);
end;

procedure VerifyCache(ATable: TFDMemTable; AExpectDelta: Boolean);
var
  Bytes: TBytes;
begin
  Check(ATable.Active, 'Cache recarregado não está ativo.');
  Check(ATable.RecordCount = 2, 'Round-trip não preservou duas linhas.');
  Check(ATable.Locate('id', Int64(1), []), 'Linha 1 não foi localizada.');
  Check(ATable.FieldByName('name').AsString = 'Caf' + #$00E9 + ' especial',
    'Unicode não foi preservado.');
  Check(Abs(ATable.FieldByName('price').AsCurrency - 1234.56) < 0.001,
    'Precisão decimal não foi preservada.');
  Check(ATable.FieldByName('note').IsNull, 'NULL virou valor não nulo.');
  Check(ATable.FieldByName('changed_at').AsDateTime =
    EncodeDateTime(2026, 9, 4, 12, 34, 56, 0), 'Data/hora foi alterada.');
  Bytes := TBlobField(ATable.FieldByName('payload')).AsBytes;
  Check((Length(Bytes) = 4) and (Bytes[0] = $00) and (Bytes[3] = $FF),
    'BLOB não foi preservado.');
  if AExpectDelta then
    Check(ATable.ChangeCount = 2, 'Journal de alterações não foi preservado.');
end;

procedure RunRoundTrip(const AName: string; AFormat: TFDStorageFormat);
var
  Source, Loaded: TFDMemTable;
  FileName: string;
begin
  Source := TFDMemTable.Create(nil);
  Loaded := TFDMemTable.Create(nil);
  FileName := WorkFile(AName);
  try
    DeleteIfExists(FileName);
    DefineCache(Source);
    SeedCache(Source);
    Source.ResourceOptions.StoreItems := [siMeta, siData, siDelta];
    Source.SaveToFile(FileName, AFormat);
    Check(TFile.GetSize(FileName) > 0, 'Arquivo persistido ficou vazio.');
    Loaded.ResourceOptions.StoreItems := [siMeta, siData, siDelta];
    Loaded.LoadFromFile(FileName, AFormat);
    VerifyCache(Loaded, True);
  finally
    DeleteIfExists(FileName);
    Loaded.Free;
    Source.Free;
  end;
end;

procedure RunBinary;
begin
  RunRoundTrip('roundtrip.fds', sfBinary);
  Writeln('EX-15-01 aprovado: binário preservou schema, tipos, dados e delta.');
end;

procedure RunXml;
begin
  RunRoundTrip('roundtrip.xml', sfXML);
  Writeln('EX-15-02 aprovado: XML preservou schema, tipos, dados e delta.');
end;

procedure RunJson;
var
  Source, FireDACJson, FreeJson: TFDMemTable;
  FireDACFile, FreeFile: string;
  FreeLoadedWithoutSchema: Boolean;
begin
  Source := TFDMemTable.Create(nil);
  FireDACJson := TFDMemTable.Create(nil);
  FreeJson := TFDMemTable.Create(nil);
  FireDACFile := WorkFile('firedac.json');
  FreeFile := WorkFile('freeform.json');
  try
    DeleteIfExists(FireDACFile);
    DeleteIfExists(FreeFile);
    DefineCache(Source);
    SeedCache(Source);
    Source.ResourceOptions.StoreItems := [siMeta, siData, siDelta];
    Source.SaveToFile(FireDACFile, sfJSON);
    Source.SaveToFile(FreeFile, sfFreeFormJSON);
    FireDACJson.LoadFromFile(FireDACFile, sfJSON);
    VerifyCache(FireDACJson, True);
    FreeLoadedWithoutSchema := True;
    try
      FreeJson.LoadFromFile(FreeFile, sfFreeFormJSON);
    except
      on E: Exception do
        FreeLoadedWithoutSchema := False;
    end;
    Check(FreeJson.Active and (FreeJson.RecordCount = 2),
      'JSON livre inferido não preservou a contagem.');
    Check(FreeJson.Locate('id', Int64(1), []),
      'JSON livre não localizou a linha 1.');
    Check(FreeJson.FieldByName('name').AsString = 'Caf' + #$00E9 + ' especial',
      'JSON livre não preservou Unicode.');
    Writeln('FreeForm types: price=', Ord(FreeJson.FieldByName('price').DataType),
      '/', FieldTypeNames[FreeJson.FieldByName('price').DataType],
      '/', FreeJson.FieldByName('price').AsString,
      '; changed_at=', FieldTypeNames[FreeJson.FieldByName('changed_at').DataType],
      '; payload=', FieldTypeNames[FreeJson.FieldByName('payload').DataType],
      '; delta=', FreeJson.ChangeCount);
    Check(FreeJson.FieldByName('note').IsNull,
      'JSON livre não preservou NULL.');
    Check(FreeLoadedWithoutSchema, 'JSON livre não inferiu seu próprio schema.');
    Check(FreeJson.FieldByName('price').DataType = ftBoolean,
      'O tipo inferido de price mudou; revise a matriz de fidelidade.');
    Check(FreeJson.FieldByName('price').AsBoolean,
      'A conversão livre observada de price não resultou em True.');
    Check(FreeJson.ChangeCount = 0,
      'JSON livre preservou delta inesperadamente; revise o contrato.');
    Check(TFile.GetSize(FireDACFile) <> TFile.GetSize(FreeFile),
      'JSON FireDAC e livre produziram arquivos indistinguíveis.');
    Writeln('EX-15-03 aprovado: JSON FireDAC preservou metadata/delta; livre inferiu price como Boolean e perdeu delta.');
  finally
    DeleteIfExists(FreeFile);
    DeleteIfExists(FireDACFile);
    FreeJson.Free;
    FireDACJson.Free;
    Source.Free;
  end;
end;

procedure ConfigurePersistent(ATable: TFDMemTable; const AFileName: string);
begin
  ATable.ResourceOptions.PersistentFileName := AFileName;
  ATable.ResourceOptions.StoreItems := [siMeta, siData, siDelta];
  ATable.ResourceOptions.Persistent := True;
  ATable.ResourceOptions.Backup := True;
end;

procedure RunPersistent;
var
  First, Second, Backup: TFDMemTable;
  FileName, BackupFile: string;
begin
  FileName := WorkFile('persistent.fds');
  BackupFile := ChangeFileExt(FileName, '.bak');
  DeleteIfExists(FileName);
  DeleteIfExists(BackupFile);
  FDManager.ResourceOptions.Backup := True;
  FDManager.ResourceOptions.DefaultStoreFormat := sfBinary;
  First := TFDMemTable.Create(nil);
  try
    ConfigurePersistent(First, FileName);
    DefineCache(First);
    SeedCache(First);
    First.Close;
  finally
    First.Free;
  end;
  Check(TFile.Exists(FileName), 'Fechamento não criou o arquivo persistente.');
  Second := TFDMemTable.Create(nil);
  try
    ConfigurePersistent(Second, FileName);
    Second.Open;
    VerifyCache(Second, True);
    Second.Locate('id', Int64(2), []);
    Second.Edit;
    Second.FieldByName('name').AsString := 'Teclado revisado';
    Second.Post;
    Second.SaveToFile(FileName, sfBinary);
    Second.Close;
  finally
    Second.Free;
  end;
  Check(TFile.Exists(BackupFile), 'Substituição não criou o backup automático.');
  Backup := TFDMemTable.Create(nil);
  try
    Backup.LoadFromFile(BackupFile, sfBinary);
    Check(Backup.Locate('id', Int64(2), []), 'Backup perdeu a linha 2.');
    Check(Backup.FieldByName('name').AsString = 'Teclado',
      'Backup não contém a versão anterior.');
  finally
    Backup.Free;
    DeleteIfExists(BackupFile);
    DeleteIfExists(FileName);
  end;
  Writeln('EX-15-04 aprovado: persistência no fechamento e backup anterior conferidos.');
end;

procedure RunCorrupt;
const
  CExpectedVersion = 'cache-v1';
var
  Source, Recovery: TFDMemTable;
  FileName, BackupFile, VersionFile: string;
  Stream: TFileStream;
  Failed: Boolean;
  Junk: array[0..7] of Byte;
begin
  FileName := WorkFile('versioned.fds');
  BackupFile := WorkFile('versioned.bak');
  VersionFile := WorkFile('versioned.version');
  DeleteIfExists(FileName);
  DeleteIfExists(BackupFile);
  DeleteIfExists(VersionFile);
  Source := TFDMemTable.Create(nil);
  Recovery := TFDMemTable.Create(nil);
  try
    DefineCache(Source);
    SeedCache(Source);
    Source.SaveToFile(FileName, sfBinary);
    TFile.Copy(FileName, BackupFile, True);
    TFile.WriteAllText(VersionFile, CExpectedVersion, TEncoding.UTF8);
    Check(TFile.ReadAllText(VersionFile, TEncoding.UTF8) = CExpectedVersion,
      'Versão do cache não confere.');
    FillChar(Junk, SizeOf(Junk), $A5);
    Stream := TFileStream.Create(FileName, fmCreate or fmShareExclusive);
    try
      Stream.WriteBuffer(Junk, SizeOf(Junk));
    finally
      Stream.Free;
    end;
    Failed := False;
    try
      Recovery.LoadFromFile(FileName, sfBinary);
    except
      on E: Exception do Failed := True;
    end;
    Check(Failed, 'Arquivo truncado foi aceito como cache válido.');
    if Recovery.Active then Recovery.Close;
    Recovery.LoadFromFile(BackupFile, sfBinary);
    VerifyCache(Recovery, True);
  finally
    Recovery.Free;
    Source.Free;
    DeleteIfExists(VersionFile);
    DeleteIfExists(BackupFile);
    DeleteIfExists(FileName);
  end;
  Writeln('EX-15-05 aprovado: corrupção rejeitada e backup versionado recuperado.');
end;

procedure RunBenchmark(const AFormatName: string; ACount: Integer);
var
  Source, Loaded: TFDMemTable;
  StorageFormat: TFDStorageFormat;
  FileName, Architecture: string;
  Stopwatch: TStopwatch;
  WriteMs, ReadMs: Double;
  I: Integer;
begin
  Check((ACount > 0) and (ACount <= 100000),
    'Quantidade deve estar entre 1 e 100000.');
  if SameText(AFormatName, 'binary') then StorageFormat := sfBinary
  else if SameText(AFormatName, 'xml') then StorageFormat := sfXML
  else if SameText(AFormatName, 'json') then StorageFormat := sfJSON
  else raise Exception.Create('Formato inválido: use binary, xml ou json.');
  FileName := WorkFile('benchmark-' + LowerCase(AFormatName) + '.dat');
  Source := TFDMemTable.Create(nil);
  Loaded := TFDMemTable.Create(nil);
  try
    DeleteIfExists(FileName);
    DefineCache(Source);
    Source.CachedUpdates := False;
    Source.BeginBatch;
    try
      for I := 1 to ACount do
        Source.AppendRecord([Int64(I), 'Produto ' + IntToStr(I),
          Currency((I mod 10000) / 100), Null,
          EncodeDateTime(2026, 9, 4, 12, 0, 0, 0), Null]);
    finally
      Source.EndBatch;
    end;
    Source.ResourceOptions.StoreItems := [siMeta, siData];
    Stopwatch := TStopwatch.StartNew;
    Source.SaveToFile(FileName, StorageFormat);
    Stopwatch.Stop;
    WriteMs := Stopwatch.Elapsed.TotalMilliseconds;
    Loaded.ResourceOptions.StoreItems := [siMeta, siData];
    Stopwatch := TStopwatch.StartNew;
    Loaded.LoadFromFile(FileName, StorageFormat);
    Stopwatch.Stop;
    ReadMs := Stopwatch.Elapsed.TotalMilliseconds;
    Check(Loaded.RecordCount = ACount, 'Benchmark perdeu linhas no round-trip.');
    Architecture := GetEnvironmentVariable('CH15_ARCH');
    if Architecture = '' then Architecture := 'unknown';
    Writeln(Format('%s;%s;%d;%.3f;%.3f;%d',
      [LowerCase(AFormatName), Architecture, ACount, WriteMs, ReadMs,
       TFile.GetSize(FileName)], TFormatSettings.Invariant));
  finally
    Loaded.Free;
    Source.Free;
    DeleteIfExists(FileName);
  end;
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter15Checks binary|xml|json|persistent|corrupt');
  Writeln('  ou Chapter15Checks benchmark binary|xml|json quantidade');
end;

begin
  CoInitialize(nil);
  try
    try
      if (ParamCount = 3) and SameText(ParamStr(1), 'benchmark') then
        RunBenchmark(ParamStr(2), StrToInt(ParamStr(3)))
      else if ParamCount <> 1 then
      begin
        ShowUsage;
        ExitCode := 2;
      end
      else if SameText(ParamStr(1), 'binary') then RunBinary
      else if SameText(ParamStr(1), 'xml') then RunXml
      else if SameText(ParamStr(1), 'json') then RunJson
      else if SameText(ParamStr(1), 'persistent') then RunPersistent
      else if SameText(ParamStr(1), 'corrupt') then RunCorrupt
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
  finally
    CoUninitialize;
  end;
end.
