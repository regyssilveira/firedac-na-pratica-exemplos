program FireStoreBootstrap;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Classes,
  System.Variants,
  System.IOUtils,
  System.Hash,
  System.Generics.Collections,
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
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Phys.SQLiteWrapper.Stat,
  FireDAC.Comp.Client,
  FireDAC.Comp.Script,
  FireDAC.Comp.ScriptCommands;

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function MigrationVersion(const AFileName: string): Integer;
var
  Name: string;
begin
  Name := TPath.GetFileName(AFileName);
  if (Length(Name) < 6) or (Name[1] <> 'V') or (Copy(Name, 5, 2) <> '__') or
     not TryStrToInt(Copy(Name, 2, 3), Result) then
    raise Exception.CreateFmt('Nome de migration inválido: %s', [Name]);
end;

function MigrationDescription(const AFileName: string): string;
begin
  Result := ChangeFileExt(Copy(TPath.GetFileName(AFileName), 7, MaxInt), '');
end;

function IsFirebird(const AConnection: TFDConnection): Boolean;
begin
  Result := SameText(AConnection.Params.Values['DriverID'], 'FB');
end;

procedure ConfigureConnection(AConnection: TFDConnection; AFBLink: TFDPhysFBDriverLink);
var
  Driver: string;
begin
  Driver := RequiredEnvironment('FIRESTORE_DRIVER');
  AConnection.LoginPrompt := False;
  if SameText(Driver, 'SQLite') then
  begin
    AConnection.Params.Values['DriverID'] := 'SQLite';
    AConnection.Params.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
    AConnection.Params.Values['OpenMode'] := 'CreateUTF8';
    AConnection.Params.Values['ForeignKeys'] := 'On';
  end
  else if SameText(Driver, 'FB') then
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
    raise Exception.CreateFmt('Driver não suportado no M0: %s', [Driver]);
end;

procedure EnsureVersionTable(AConnection: TFDConnection);
var
  Exists: Boolean;
begin
  if IsFirebird(AConnection) then
    Exists := AConnection.ExecSQLScalar(
      'SELECT COUNT(*) FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ''SCHEMA_VERSION''') > 0
  else
    Exists := AConnection.ExecSQLScalar(
      'SELECT COUNT(*) FROM sqlite_master WHERE type = ''table'' AND name = ''schema_version''') > 0;
  if Exists then
    Exit;

  AConnection.ExecSQL(
    'CREATE TABLE schema_version (' +
    'version INTEGER NOT NULL PRIMARY KEY, ' +
    'description VARCHAR(120) NOT NULL, ' +
    'checksum CHAR(64) NOT NULL, ' +
    'applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL)');
end;

procedure ExecuteScript(AConnection: TFDConnection; const AFileName: string);
var
  Script: TFDScript;
  SingleCommand: TStringList;
begin
  SingleCommand := TStringList.Create;
  try
    SingleCommand.LoadFromFile(AFileName, TEncoding.UTF8);
    if (SingleCommand.Count > 0) and
       SameText(Trim(SingleCommand[0]), '-- FIRESTORE:SINGLE-COMMAND') then
    begin
      SingleCommand.Delete(0);
      AConnection.ExecSQL(SingleCommand.Text);
      Exit;
    end;
  finally
    SingleCommand.Free;
  end;

  Script := TFDScript.Create(nil);
  try
    Script.Connection := AConnection;
    with Script.SQLScripts.Add do
    begin
      Name := TPath.GetFileName(AFileName);
      SQL.LoadFromFile(AFileName, TEncoding.UTF8);
    end;
    Script.ValidateAll;
    Script.ExecuteAll;
  finally
    Script.Free;
  end;
end;

procedure ApplyMigrations(AConnection: TFDConnection);
var
  Files: TArray<string>;
  FileName, Description, Checksum, ExistingChecksum: string;
  Version: Integer;
begin
  EnsureVersionTable(AConnection);
  Files := TDirectory.GetFiles(RequiredEnvironment('FIRESTORE_MIGRATIONS'), 'V*.sql');
  TArray.Sort<string>(Files);
  for FileName in Files do
  begin
    Version := MigrationVersion(FileName);
    Description := MigrationDescription(FileName);
    Checksum := THashSHA2.GetHashStringFromFile(FileName);
    ExistingChecksum := VarToStr(AConnection.ExecSQLScalar(
      'SELECT MAX(checksum) FROM schema_version WHERE version = :version', [Version]));
    if ExistingChecksum <> '' then
    begin
      if not SameText(ExistingChecksum, Checksum) then
        raise Exception.CreateFmt('Checksum divergente na migration V%.3d.', [Version]);
      Writeln(Format('V%.3d já aplicada.', [Version]));
      Continue;
    end;

    AConnection.StartTransaction;
    try
      ExecuteScript(AConnection, FileName);
      AConnection.ExecSQL(
        'INSERT INTO schema_version (version, description, checksum) ' +
        'VALUES (:version, :description, :checksum)',
        [Version, Description, Checksum]);
      AConnection.Commit;
      Writeln(Format('V%.3d aplicada: %s', [Version, Description]));
    except
      if AConnection.InTransaction then
        AConnection.Rollback;
      raise;
    end;
  end;
end;

procedure SmokeTest(AConnection: TFDConnection);
var
  VersionCount, CategoryCount, ProductCount, InventoryCount: Integer;
  ProductName: string;
begin
  VersionCount := AConnection.ExecSQLScalar('SELECT COUNT(*) FROM schema_version');
  CategoryCount := AConnection.ExecSQLScalar('SELECT COUNT(*) FROM category');
  ProductCount := AConnection.ExecSQLScalar('SELECT COUNT(*) FROM product');
  InventoryCount := AConnection.ExecSQLScalar('SELECT COUNT(*) FROM inventory');
  ProductName := VarToStr(AConnection.ExecSQLScalar(
    'SELECT name FROM product WHERE sku = :sku', ['BEB-001']));
  if (VersionCount <> 7) or (CategoryCount <> 2) or (ProductCount <> 3) or
     (InventoryCount <> 3) or
     (ProductName <> 'Caf' + #$00E9 + ' especial') then
    raise Exception.CreateFmt(
      'Smoke test falhou: versões=%d categorias=%d produtos=%d estoque=%d produto=%s',
      [VersionCount, CategoryCount, ProductCount, InventoryCount, ProductName]);
  Writeln('Smoke test aprovado: 7 migrations, 2 categorias, 3 produtos e 3 estoques.');
end;

var
  Connection: TFDConnection;
  FBLink: TFDPhysFBDriverLink;
  Command: string;

begin
  Connection := TFDConnection.Create(nil);
  FBLink := TFDPhysFBDriverLink.Create(nil);
  try
    try
      if ParamCount <> 1 then
        raise Exception.Create('Uso: FireStoreBootstrap migrate|smoke');
      Command := LowerCase(ParamStr(1));
      ConfigureConnection(Connection, FBLink);
      Connection.Connected := True;
      if Command = 'migrate' then
        ApplyMigrations(Connection)
      else if Command = 'smoke' then
        SmokeTest(Connection)
      else
        raise Exception.CreateFmt('Comando inválido: %s', [Command]);
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Connection.Free;
    FBLink.Free;
  end;
end.
