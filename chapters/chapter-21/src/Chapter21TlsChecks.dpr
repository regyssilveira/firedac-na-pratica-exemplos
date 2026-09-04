program Chapter21TlsChecks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.Variants,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.Intf,
  FireDAC.Phys.PG,
  FireDAC.Phys.PGDef,
  FireDAC.DApt,
  FireDAC.Comp.Client;

procedure Check(ACondition: Boolean; const AMessage: string);
begin
  if not ACondition then
    raise Exception.Create(AMessage);
end;

function Env(const AName: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result = '' then
    raise Exception.CreateFmt('Variável obrigatória ausente: %s', [AName]);
end;

function TryTlsConnection(const AServer, ARootCertificate: string;
  out AError: string): Boolean;
var
  Connection: TFDConnection;
  Link: TFDPhysPgDriverLink;
begin
  Connection := TFDConnection.Create(nil);
  Link := TFDPhysPgDriverLink.Create(nil);
  try
    Link.VendorLib := Env('CH21_LIBPQ');
    Connection.LoginPrompt := False;
    Connection.Params.Values['DriverID'] := 'PG';
    Connection.Params.Values['Server'] := AServer;
    Connection.Params.Values['Port'] := Env('CH21_TLS_PORT');
    Connection.Params.Values['Database'] := 'postgres';
    Connection.Params.Values['User_Name'] := 'postgres';
    Connection.Params.Values['Password'] := Env('CH21_TLS_PASSWORD');
    Connection.Params.Values['PGAdvanced'] :=
      'sslmode=verify-full;sslrootcert=' + ARootCertificate +
      ';connect_timeout=3;application_name=FireDACNaPraticaTLS';
    try
      Connection.Open;
      Result := True;
      AError := '';
    except
      on E: EFDDBEngineException do
      begin
        Result := False;
        AError := E.Message;
      end;
    end;
  finally
    Link.Free;
    Connection.Free;
  end;
end;

procedure RunTls;
var
  Connection: TFDConnection;
  Link: TFDPhysPgDriverLink;
  Certificate, WrongCertificate, ErrorText: string;
  HostnameRejected, WrongCaRejected: Boolean;
begin
  Certificate := Env('CH21_TLS_CA');
  WrongCertificate := Env('CH21_TLS_WRONG_CA');
  Connection := TFDConnection.Create(nil);
  Link := TFDPhysPgDriverLink.Create(nil);
  try
    Link.VendorLib := Env('CH21_LIBPQ');
    Connection.LoginPrompt := False;
    Connection.Params.Values['DriverID'] := 'PG';
    Connection.Params.Values['Server'] := 'localhost';
    Connection.Params.Values['Port'] := Env('CH21_TLS_PORT');
    Connection.Params.Values['Database'] := 'postgres';
    Connection.Params.Values['User_Name'] := 'postgres';
    Connection.Params.Values['Password'] := Env('CH21_TLS_PASSWORD');
    Connection.Params.Values['PGAdvanced'] :=
      'sslmode=verify-full;sslrootcert=' + Certificate +
      ';connect_timeout=3;application_name=FireDACNaPraticaTLS';
    Connection.Open;
    Check(Connection.ExecSQLScalar(
      'select case when ssl then 1 else 0 end from pg_stat_ssl ' +
      'where pid=pg_backend_pid()') = 1,
      'O servidor não confirmou TLS para a sessão.');
    Check(VarToStr(Connection.ExecSQLScalar(
      'select current_setting(''application_name'')')) = 'FireDACNaPraticaTLS',
      'PGAdvanced não chegou ao servidor TLS.');
  finally
    Link.Free;
    Connection.Free;
  end;

  HostnameRejected := not TryTlsConnection('127.0.0.1', Certificate, ErrorText);
  Check(HostnameRejected, 'Certificado com hostname divergente foi aceito.');
  WrongCaRejected := not TryTlsConnection('localhost', WrongCertificate, ErrorText);
  Check(WrongCaRejected, 'Certificado assinado por CA desconhecida foi aceito.');
  Writeln('EX-21-03 tls=True sslmode=verify-full hostname_failure=True wrong_ca_failure=True');
end;

begin
  try
    RunTls;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
