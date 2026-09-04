program Chapter06Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Hash,
  System.Math,
  System.DateUtils,
  System.Variants,
  Data.DB,
  Data.SqlTimSt,
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
  TProductOrder = (poName, poPrice, poSku);

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
  Result := SameText(RequiredEnvironment('CH06_DRIVER'), 'FB');
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
    AConnection.Params.Values['Database'] := RequiredEnvironment('CH06_SQLITE_DATABASE');
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

procedure ConfigureOptionalParams(AQuery: TFDQuery; ACategory: Variant;
  AMinimumPrice: Variant);
begin
  with AQuery.ParamByName('category_id') do
  begin
    DataType := ftLargeint;
    if VarIsNull(ACategory) then
      Clear
    else
      AsLargeInt := ACategory;
  end;
  with AQuery.ParamByName('minimum_price') do
  begin
    DataType := ftFMTBcd;
    Precision := 18;
    NumericScale := 2;
    if VarIsNull(AMinimumPrice) then
      Clear
    else
      AsCurrency := AMinimumPrice;
  end;
end;

function SearchCount(AConnection: TFDConnection; ACategory,
  AMinimumPrice: Variant): Integer;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := '''
      SELECT id
      FROM product
      WHERE (:category_id IS NULL OR category_id = :category_id)
        AND (:minimum_price IS NULL OR price >= :minimum_price)
      ORDER BY name, id
      ''';
    ConfigureOptionalParams(Query, ACategory, AMinimumPrice);
    Query.Open;
    Result := 0;
    while not Query.Eof do
    begin
      Inc(Result);
      Query.Next;
    end;
  finally
    Query.Free;
  end;
end;

procedure RunOptionalParams;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    begin
      Check(SearchCount(Connection, Null, Null) = 3,
        'Dois filtros nulos não retornaram os três produtos.');
      Check(SearchCount(Connection, 1, Null) = 2,
        'Filtro da categoria 1 não retornou dois produtos.');
      Check(SearchCount(Connection, Null, 20.00) = 1,
        'Preço mínimo 20 não retornou um produto.');
      Check(SearchCount(Connection, 2, 20.00) = 0,
        'Combinação categoria 2 e preço 20 deveria ser vazia.');
      Writeln('EX-06-01 aprovado: quatro combinações de parâmetros e NULL.');
    end);
end;

function ParseOrder(const AValue: string): TProductOrder;
begin
  if SameText(AValue, 'name') then
    Exit(poName);
  if SameText(AValue, 'price') then
    Exit(poPrice);
  if SameText(AValue, 'sku') then
    Exit(poSku);
  raise EArgumentException.CreateFmt('Ordenação não permitida: %s', [AValue]);
end;

function OrderExpression(AOrder: TProductOrder): string;
begin
  case AOrder of
    poName: Result := 'name, id';
    poPrice: Result := 'price DESC, id';
    poSku: Result := 'sku, id';
  else
    raise EArgumentOutOfRangeException.Create('Ordenação inválida.');
  end;
end;

function FirstIdForOrder(AConnection: TFDConnection;
  AOrder: TProductOrder): Int64;
var
  Query: TFDQuery;
begin
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := AConnection;
    Query.SQL.Text := '''
      SELECT id, sku, name, price
      FROM product
      ORDER BY &order_expression
      ''';
    Query.MacroByName('order_expression').AsRaw := OrderExpression(AOrder);
    Query.Open;
    Check(not Query.IsEmpty, 'Ordenação retornou conjunto vazio.');
    Result := Query.FieldByName('id').AsLargeInt;
  finally
    Query.Free;
  end;
end;

procedure RunAllowlist;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Rejected: Boolean;
    begin
      Check(FirstIdForOrder(Connection, ParseOrder('price')) = 1,
        'Ordenação de preço não trouxe o produto mais caro.');
      Check(FirstIdForOrder(Connection, ParseOrder('sku')) = 3,
        'Ordenação de SKU não trouxe ALI-001 primeiro.');
      Rejected := False;
      try
        ParseOrder('price; delete from product');
      except
        on E: EArgumentException do
          Rejected := True;
      end;
      Check(Rejected, 'Estrutura hostil não foi rejeitada antes da macro.');
      Check(Connection.ExecSQLScalar('SELECT COUNT(*) FROM product') = 3,
        'O catálogo foi alterado pelo texto hostil.');
      Writeln('EX-06-02 aprovado: macro recebeu somente expressão da allowlist.');
    end);
end;

procedure RunDateTimeOffset;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Update: TFDQuery;
      ReadBack: TFDQuery;
      Expected, Actual: TSQLTimeStampOffset;
      ISOValue: string;
    begin
      Update := TFDQuery.Create(nil);
      ReadBack := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Expected := DateTimeToSQLTimeStampOffset(
          EncodeDateTime(2026, 9, 3, 12, 34, 56, 789), -3, 0);
        Update.Connection := Connection;
        Update.SQL.Text := 'UPDATE product SET available_at = :value WHERE id = :id';
        Update.ParamByName('id').AsLargeInt := 1;
        if IsFirebird then
        begin
          Update.ParamByName('value').DataType := ftTimeStampOffset;
          Update.ParamByName('value').AsSQLTimeStampOffset := Expected;
        end
        else
        begin
          ISOValue := '2026-09-03T15:34:56.789Z';
          Update.ParamByName('value').DataType := ftWideString;
          Update.ParamByName('value').Size := Length(ISOValue);
          Update.ParamByName('value').AsWideString := ISOValue;
        end;
        Update.ExecSQL;
        Check(Update.RowsAffected = 1, 'Instante não atualizou uma linha.');

        ReadBack.Connection := Connection;
        ReadBack.SQL.Text := 'SELECT available_at FROM product WHERE id = :id';
        ReadBack.ParamByName('id').AsLargeInt := 1;
        ReadBack.Open;
        if IsFirebird then
        begin
          Check(ReadBack.FieldByName('available_at').DataType = ftTimeStampOffset,
            'Firebird não devolveu ftTimeStampOffset.');
          Actual := ReadBack.FieldByName('available_at').AsSQLTimeStampOffset;
          Check((Actual.TimeZoneHour = -3) and (Actual.TimeZoneMinute = 0),
            'O deslocamento -03:00 não foi preservado.');
          Check(Abs(SQLTimeStampOffsetToDateTime(Actual) -
            SQLTimeStampOffsetToDateTime(Expected)) < OneMillisecond,
            'O horário local do timestamp divergiu.');
        end
        else
          Check(ReadBack.FieldByName('available_at').AsString = ISOValue,
            'SQLite não preservou a representação UTC canônica.');
        Writeln(Format('EX-06-03 aprovado: temporal=%s.',
          [ReadBack.FieldByName('available_at').ClassName]));
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        ReadBack.Free;
        Update.Free;
      end;
    end);
end;

function SameBytes(const A, B: TBytes): Boolean;
begin
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or CompareMem(@A[0], @B[0], Length(A)));
end;

procedure RunBlobStream;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Input, Output: TMemoryStream;
      Query: TFDQuery;
      Original, Returned: TBytes;
      I: Integer;
      HashBefore, HashAfter: string;
    begin
      SetLength(Original, 8192);
      for I := 0 to High(Original) do
        Original[I] := Byte((I * 31 + 17) mod 256);
      Input := TMemoryStream.Create;
      Output := TMemoryStream.Create;
      Query := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Input.WriteBuffer(Original[0], Length(Original));
        Input.Position := 0;
        HashBefore := THashSHA2.GetHashString(Input);
        Input.Position := 0;

        Query.Connection := Connection;
        Query.SQL.Text := 'UPDATE product SET image_data = :image WHERE id = :id';
        Query.ParamByName('image').LoadFromStream(Input, ftBlob);
        Query.ParamByName('id').AsLargeInt := 1;
        Query.ExecSQL;
        Check(Query.RowsAffected = 1, 'BLOB não atualizou uma linha.');

        Query.Close;
        Query.SQL.Text := 'SELECT image_data FROM product WHERE id = :id';
        Query.ParamByName('id').AsLargeInt := 1;
        Query.Open;
        TBlobField(Query.FieldByName('image_data')).SaveToStream(Output);
        Output.Position := 0;
        HashAfter := THashSHA2.GetHashString(Output);
        SetLength(Returned, Output.Size);
        Output.Position := 0;
        if Length(Returned) > 0 then
          Output.ReadBuffer(Returned[0], Length(Returned));
        Check(HashBefore = HashAfter, 'SHA-256 mudou no round-trip do BLOB.');
        Check(SameBytes(Original, Returned), 'Bytes do BLOB foram alterados.');
        Writeln(Format('EX-06-04 aprovado: BLOB de %d bytes; SHA-256=%s.',
          [Length(Returned), HashAfter]));
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
        Output.Free;
        Input.Free;
      end;
    end);
end;

procedure RunTypeMatrix;
begin
  WithConnection(
    procedure(Connection: TFDConnection)
    var
      Update, Query: TFDQuery;
    begin
      var ExternalId := '7f6a9a6e-91bb-4f99-a9c8-00e8a5dd9106';
      Update := TFDQuery.Create(nil);
      Query := TFDQuery.Create(nil);
      Connection.StartTransaction;
      try
        Update.Connection := Connection;
        Update.SQL.Text :=
          'UPDATE product SET external_id = :external_id WHERE id = :id';
        Update.ParamByName('external_id').DataType := ftWideString;
        Update.ParamByName('external_id').Size := 36;
        Update.ParamByName('external_id').AsWideString := ExternalId;
        Update.ParamByName('id').AsLargeInt := 1;
        Update.ExecSQL;

        Query.Connection := Connection;
        Query.SQL.Text := '''
          SELECT id, sku, name, price, active, external_id, available_at,
                 image_data
          FROM product
          WHERE id = :id
          ''';
        Query.ParamByName('id').AsLargeInt := 1;
        Query.Open;
        Check(Query.FieldByName('id').DataType in [ftInteger, ftLargeint],
          'Chave não foi mapeada como inteiro.');
        Check(Query.FieldByName('price').DataType = ftFMTBcd,
          'Preço não foi mapeado como ftFMTBcd.');
        if IsFirebird then
          Check(Query.FieldByName('active').AsBoolean,
            'Booleano Firebird não voltou verdadeiro.')
        else
          Check(Query.FieldByName('active').AsInteger = 1,
            'Booleano lógico SQLite não voltou como inteiro 1.');
        Check(Trim(Query.FieldByName('external_id').AsString) = ExternalId,
          'UUID textual não completou o round-trip.');
        Check(Query.FieldByName('available_at').IsNull,
          'Valor temporal deveria continuar NULL neste modo.');
        Check(Query.FieldByName('image_data').IsNull,
          'BLOB deveria continuar NULL neste modo.');
        Writeln(Format(
          'EX-06-05 aprovado: id=%s; price=%s; active=%s; uuid=%s; nulls preservados.',
          [Query.FieldByName('id').ClassName,
           Query.FieldByName('price').ClassName,
           Query.FieldByName('active').ClassName,
           Query.FieldByName('external_id').ClassName]));
      finally
        if Connection.InTransaction then
          Connection.Rollback;
        Query.Free;
        Update.Free;
      end;
    end);
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter06Checks optional|allowlist|datetime|blob|types');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'optional') then
      RunOptionalParams
    else if SameText(ParamStr(1), 'allowlist') then
      RunAllowlist
    else if SameText(ParamStr(1), 'datetime') then
      RunDateTimeOffset
    else if SameText(ParamStr(1), 'blob') then
      RunBlobStream
    else if SameText(ParamStr(1), 'types') then
      RunTypeMatrix
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
