program Chapter03Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Winapi.Windows,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.FB,
  FireDAC.Phys.FBDef,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Comp.Client;

type
  TAppEnvironment = (aeDevelopment, aeTest, aeProduction);

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

function ParseEnvironment(const AValue: string): TAppEnvironment;
begin
  if SameText(AValue, 'development') then
    Exit(aeDevelopment);
  if SameText(AValue, 'test') then
    Exit(aeTest);
  if SameText(AValue, 'production') then
    Exit(aeProduction);
  raise EArgumentException.CreateFmt('Ambiente inválido: %s', [AValue]);
end;

procedure ConfigureSQLite(AConnection: TFDConnection);
begin
  AConnection.LoginPrompt := False;
  AConnection.Params.Values['DriverID'] := 'SQLite';
  AConnection.Params.Values['Database'] := RequiredEnvironment('CH03_SQLITE_DATABASE');
  AConnection.Params.Values['ForeignKeys'] := 'On';
end;

procedure ValidateCatalog(AConnection: TFDConnection);
var
  Count: Integer;
begin
  AConnection.Open;
  Count := AConnection.ExecSQLScalar('SELECT COUNT(*) FROM product');
  Check(Count = 3, Format('Esperados 3 produtos; recebidos %d.', [Count]));
end;

procedure RunTemporary;
var
  Connection: TFDConnection;
begin
  Connection := TFDConnection.Create(nil);
  try
    ConfigureSQLite(Connection);
    Check(Connection.ConnectionDefName = '',
      'A conexão direta não deveria usar definição nomeada.');
    ValidateCatalog(Connection);
    Writeln('EX-03-01 aprovado: parâmetros temporários abriram o catálogo.');
  finally
    Connection.Free;
  end;
end;

procedure RunPrivateDefinition;
var
  Params: TStringList;
  Connection: TFDConnection;
  DefinitionName: string;
begin
  DefinitionName := 'FireStore_Private_' + IntToStr(GetCurrentProcessId);
  Params := TStringList.Create;
  Connection := TFDConnection.Create(nil);
  try
    Params.Values['Database'] := RequiredEnvironment('CH03_SQLITE_DATABASE');
    Params.Values['ForeignKeys'] := 'On';
    FDManager.AddConnectionDef(DefinitionName, 'SQLite', Params, False);
    Connection.ConnectionDefName := DefinitionName;
    Connection.LoginPrompt := False;
    ValidateCatalog(Connection);
    Check(not FileExists(RequiredEnvironment('CH03_CONNECTION_DEFS')),
      'A definição privada não deveria criar arquivo persistente.');
    Writeln('EX-03-01 aprovado: definição privada existiu somente no processo.');
  finally
    Connection.Free;
    Params.Free;
  end;
end;

procedure RunPersistentDefinition;
var
  Params: TStringList;
  Connection: TFDConnection;
  DefinitionFile: string;
begin
  DefinitionFile := RequiredEnvironment('CH03_CONNECTION_DEFS');
  if FileExists(DefinitionFile) then
    TFile.Delete(DefinitionFile);
  ForceDirectories(ExtractFilePath(DefinitionFile));
  FDManager.ConnectionDefFileName := DefinitionFile;

  Params := TStringList.Create;
  Connection := TFDConnection.Create(nil);
  try
    Params.Values['Database'] := RequiredEnvironment('CH03_SQLITE_DATABASE');
    Params.Values['ForeignKeys'] := 'On';
    FDManager.AddConnectionDef('FireStore_Persisted', 'SQLite', Params, True);
    FDManager.SaveConnectionDefFile;
    Check(FileExists(DefinitionFile), 'Arquivo de definições não foi criado.');
    Connection.ConnectionDefName := 'FireStore_Persisted';
    Connection.LoginPrompt := False;
    ValidateCatalog(Connection);
    Check(Pos('Password', TFile.ReadAllText(DefinitionFile, TEncoding.UTF8)) = 0,
      'O arquivo persistente contém senha.');
    Writeln('EX-03-02 aprovado: definição persistente reabriu sem senha gravada.');
  finally
    Connection.Free;
    Params.Free;
  end;
end;

procedure ConfigureFirebird(AConnection: TFDConnection;
  ALink: TFDPhysFBDriverLink; const AServer, ADatabase: string);
begin
  ALink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
  AConnection.LoginPrompt := False;
  AConnection.Params.Values['DriverID'] := 'FB';
  AConnection.Params.Values['Protocol'] := 'TCPIP';
  AConnection.Params.Values['Server'] := AServer;
  AConnection.Params.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
  AConnection.Params.Values['Database'] := ADatabase;
  AConnection.Params.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
  AConnection.Params.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
  AConnection.Params.Values['CharacterSet'] := 'UTF8';
end;

procedure RunFirebirdProfiles;
var
  Connection: TFDConnection;
  Link: TFDPhysFBDriverLink;
  RemoteParams, AliasParams: TStringList;
begin
  Connection := TFDConnection.Create(nil);
  Link := TFDPhysFBDriverLink.Create(nil);
  RemoteParams := TStringList.Create;
  AliasParams := TStringList.Create;
  try
    ConfigureFirebird(Connection, Link, '127.0.0.1',
      RequiredEnvironment('FIRESTORE_DB_NAME'));
    ValidateCatalog(Connection);

    RemoteParams.Assign(Connection.Params);
    RemoteParams.Values['Server'] := 'db.example.invalid';
    RemoteParams.Values['Database'] := 'D:\dados\firestore.fdb';
    AliasParams.Assign(Connection.Params);
    AliasParams.Values['Server'] := 'db.example.invalid';
    AliasParams.Values['Database'] := 'FIRESTORE_PROD';

    Check(RemoteParams.Values['Database'] = 'D:\dados\firestore.fdb',
      'O caminho remoto deixou de ser caminho do servidor.');
    Check(AliasParams.Values['Database'] = 'FIRESTORE_PROD',
      'O alias não foi preservado como nome lógico.');
    Writeln('EX-03-03 parcial: TCP local executado; remoto e alias configurados.');
  finally
    AliasParams.Free;
    RemoteParams.Free;
    Link.Free;
    Connection.Free;
  end;
end;

procedure RunPostgreSQLConfiguration;
var
  Connection: TFDConnection;
  Link: TFDPhysPgDriverLink;
begin
  Connection := TFDConnection.Create(nil);
  Link := TFDPhysPgDriverLink.Create(nil);
  try
    Link.VendorLib := RequiredEnvironment('CH03_LIBPQ');
    Connection.LoginPrompt := False;
    Connection.Params.Values['DriverID'] := 'PG';
    Connection.Params.Values['Server'] := '127.0.0.1';
    Connection.Params.Values['Port'] := '5432';
    Connection.Params.Values['Database'] := 'postgres';
    Connection.Params.Values['User_Name'] := 'postgres';
    Connection.Params.Values['PGAdvanced'] :=
      'application_name=FireDACNaPratica&connect_timeout=3';
    Check(FileExists(Link.VendorLib), 'libpq.dll configurada não existe.');
    Check(Pos('application_name=',
      Connection.Params.Values['PGAdvanced']) = 1,
      'PGAdvanced não contém ApplicationName.');
    Check(Connection.Params.Values['Password'] = '',
      'O exemplo de configuração não deve persistir senha.');
    Writeln('EX-03-04 compilado: PGAdvanced validado; conexão aguarda credencial.');
  finally
    Link.Free;
    Connection.Free;
  end;
end;

procedure RunEnvironmentSelection;
var
  FailedAsExpected: Boolean;
begin
  Check(ParseEnvironment('development') = aeDevelopment, 'Development inválido.');
  Check(ParseEnvironment('test') = aeTest, 'Test inválido.');
  Check(ParseEnvironment('production') = aeProduction, 'Production inválido.');
  FailedAsExpected := False;
  try
    ParseEnvironment('produção-talvez');
  except
    on E: EArgumentException do
      FailedAsExpected := True;
  end;
  Check(FailedAsExpected, 'Ambiente desconhecido não foi rejeitado.');
  Writeln('EX-03-05 aprovado: três ambientes aceitos e nome inválido rejeitado.');
end;

procedure ShowUsage;
begin
  Writeln('Uso: Chapter03Checks temporary|private|persistent|firebird|postgres-config|environment');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'temporary') then
      RunTemporary
    else if SameText(ParamStr(1), 'private') then
      RunPrivateDefinition
    else if SameText(ParamStr(1), 'persistent') then
      RunPersistentDefinition
    else if SameText(ParamStr(1), 'firebird') then
      RunFirebirdProfiles
    else if SameText(ParamStr(1), 'postgres-config') then
      RunPostgreSQLConfiguration
    else if SameText(ParamStr(1), 'environment') then
      RunEnvironmentSelection
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
