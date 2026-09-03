program ValidateFireDACConnection;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
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
  FireDAC.Comp.Client;

function RequiredEnvironment(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

var
  Connection: TFDConnection;
  DriverLink: TFDPhysFBDriverLink;
  EngineVersion: Variant;

begin
  Connection := TFDConnection.Create(nil);
  DriverLink := TFDPhysFBDriverLink.Create(nil);
  try
    try
      DriverLink.VendorLib := RequiredEnvironment('FIRESTORE_FBCLIENT');
      Connection.LoginPrompt := False;
      Connection.Params.Values['DriverID'] := 'FB';
      Connection.Params.Values['Protocol'] := 'TCPIP';
      Connection.Params.Values['Server'] := RequiredEnvironment('FIRESTORE_DB_HOST');
      Connection.Params.Values['Port'] := RequiredEnvironment('FIRESTORE_DB_PORT');
      Connection.Params.Values['Database'] := RequiredEnvironment('FIRESTORE_DB_NAME');
      Connection.Params.Values['User_Name'] := RequiredEnvironment('FIRESTORE_DB_USER');
      Connection.Params.Values['Password'] := RequiredEnvironment('FIRESTORE_DB_PASSWORD');
      Connection.Connected := True;
      EngineVersion := Connection.ExecSQLScalar(
        'SELECT RDB$GET_CONTEXT(''SYSTEM'', ''ENGINE_VERSION'') FROM RDB$DATABASE');
      Writeln('FireDAC conectado ao Firebird ', EngineVersion);
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, E.ClassName, ': ', E.Message);
        ExitCode := 1;
      end;
    end;
  finally
    Connection.Free;
    DriverLink.Free;
  end;
end.
