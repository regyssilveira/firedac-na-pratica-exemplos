program ValidateClientProfile;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FireStore.ClientLibrary in '..\..\firestore\src\FireStore.ClientLibrary.pas';

var
  ClientPath: string;

begin
  try
    ClientPath := FirebirdClientLibrary(GetCurrentDir);
    if not FileExists(ClientPath) then
      raise Exception.CreateFmt('Cliente não encontrado: %s', [ClientPath]);
    Writeln(ClientPath);
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
