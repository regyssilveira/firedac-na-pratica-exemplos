unit Chapter01.Core;

interface

procedure RunSQLiteCatalog;
procedure RunFirebirdCatalog;
procedure RunParameterizedLookup;
procedure RunMissingClientDiagnostic;

implementation

uses
  System.SysUtils,
  System.IOUtils,
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

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

procedure ConfigureFirebird(AConnection: TFDConnection;
  ADriverLink: TFDPhysFBDriverLink; const AClientLibrary: string);
begin
  ADriverLink.VendorLib := AClientLibrary;
  AConnection.LoginPrompt := False;
  AConnection.Params.Values['DriverID'] := 'FB';
  AConnection.Params.Values['Protocol'] := 'TCPIP';
  AConnection.Params.Values['Server'] := RequiredEnvironment('FIRESTORE_DB_HOST');
  AConnection.Params.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
  AConnection.Params.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
  AConnection.Params.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
  AConnection.Params.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
  AConnection.Params.Values['CharacterSet'] := 'UTF8';
end;

procedure CreateSQLiteCatalog(AConnection: TFDConnection);
begin
  AConnection.ExecSQL(
    'CREATE TABLE product (' +
    'id INTEGER PRIMARY KEY, sku VARCHAR(30) NOT NULL UNIQUE, ' +
    'name VARCHAR(120) NOT NULL, price NUMERIC(15, 2) NOT NULL)');
  AConnection.ExecSQL(
    'INSERT INTO product (id, sku, name, price) VALUES (:id, :sku, :name, :price)',
    [1, 'BEB-001', 'Caf' + #$00E9 + ' especial', 29.90]);
  AConnection.ExecSQL(
    'INSERT INTO product (id, sku, name, price) VALUES (:id, :sku, :name, :price)',
    [2, 'ACE-001', 'Caneca t' + #$00E9 + 'rmica', 79.90]);
end;

procedure RunSQLiteCatalog;
var
  Connection: TFDConnection;
  Query: TFDQuery;
  DatabaseFile: string;
begin
  DatabaseFile := RequiredEnvironment('CH01_SQLITE_DATABASE');
  if FileExists(DatabaseFile) then
    DeleteFile(DatabaseFile);
  ForceDirectories(ExtractFilePath(DatabaseFile));

  Connection := TFDConnection.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    Connection.LoginPrompt := False;
    Connection.Params.Values['DriverID'] := 'SQLite';
    Connection.Params.Values['Database'] := DatabaseFile;
    Connection.Params.Values['OpenMode'] := 'CreateUTF8';
    Connection.Params.Values['ForeignKeys'] := 'On';
    Connection.Open;
    CreateSQLiteCatalog(Connection);

    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT sku, name, price FROM product ORDER BY name, id';
    Query.Open;
    if Query.RecordCount <> 2 then
      raise Exception.CreateFmt('Esperados 2 produtos; recebidos %d.', [Query.RecordCount]);
    Writeln('EX-01-02 aprovado: SQLite abriu e retornou 2 produtos.');
  finally
    Query.Free;
    Connection.Free;
  end;
end;

procedure RunFirebirdCatalog;
var
  Connection: TFDConnection;
  DriverLink: TFDPhysFBDriverLink;
  Query: TFDQuery;
begin
  Connection := TFDConnection.Create(nil);
  DriverLink := TFDPhysFBDriverLink.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    ConfigureFirebird(Connection, DriverLink,
      RequiredEnvironment('FIRESTORE_FBCLIENT'));
    Connection.Open;
    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT sku, name, price FROM product ORDER BY name, id';
    Query.Open;
    if Query.RecordCount <> 3 then
      raise Exception.CreateFmt('Esperados 3 produtos; recebidos %d.', [Query.RecordCount]);
    Writeln('EX-01-01 aprovado: Firebird abriu e retornou 3 produtos.');
  finally
    Query.Free;
    Connection.Free;
    DriverLink.Free;
  end;
end;

procedure RunParameterizedLookup;
var
  Connection: TFDConnection;
  Query: TFDQuery;
begin
  Connection := TFDConnection.Create(nil);
  Query := TFDQuery.Create(nil);
  try
    Connection.LoginPrompt := False;
    Connection.Params.Values['DriverID'] := 'SQLite';
    Connection.Params.Values['Database'] := ':memory:';
    Connection.Open;
    CreateSQLiteCatalog(Connection);

    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT name FROM product WHERE sku = :sku';
    Query.ParamByName('sku').AsString := 'BEB-001';
    Query.Open;
    if Query.IsEmpty then
      raise Exception.Create('SKU conhecido não foi localizado.');

    Query.Close;
    Query.ParamByName('sku').AsString := 'BEB-001'' OR ''1''=''1';
    Query.Open;
    if not Query.IsEmpty then
      raise Exception.Create('Entrada hostil alterou a estrutura da consulta.');
    Writeln('EX-01-03 aprovado: parâmetro preservou o valor sem injeção de SQL.');
  finally
    Query.Free;
    Connection.Free;
  end;
end;

procedure RunMissingClientDiagnostic;
var
  Connection: TFDConnection;
  DriverLink: TFDPhysFBDriverLink;
  MissingLibrary: string;
begin
  MissingLibrary := TPath.Combine(TPath.GetTempPath,
    'firedac-na-pratica-cliente-ausente\fbclient.dll');
  Connection := TFDConnection.Create(nil);
  DriverLink := TFDPhysFBDriverLink.Create(nil);
  try
    ConfigureFirebird(Connection, DriverLink, MissingLibrary);
    try
      Connection.Open;
      raise Exception.Create('O teste deveria falhar com a biblioteca ausente.');
    except
      on E: EFDException do
      begin
        if Pos('fbclient.dll', LowerCase(E.Message)) = 0 then
          raise Exception.CreateFmt('Falha sem contexto da biblioteca: %s', [E.Message]);
        Writeln('EX-01-05 aprovado: cliente ausente produziu diagnóstico preservado.');
      end;
    end;
  finally
    Connection.Free;
    DriverLink.Free;
  end;
end;

end.
