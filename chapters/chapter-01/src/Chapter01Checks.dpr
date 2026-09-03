program Chapter01Checks;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Chapter01.Core in 'Chapter01.Core.pas';

procedure ShowUsage;
begin
  Writeln('Uso: Chapter01Checks sqlite|firebird|parameter|missing-client');
end;

begin
  try
    if ParamCount <> 1 then
    begin
      ShowUsage;
      ExitCode := 2;
    end
    else if SameText(ParamStr(1), 'sqlite') then
      RunSQLiteCatalog
    else if SameText(ParamStr(1), 'firebird') then
      RunFirebirdCatalog
    else if SameText(ParamStr(1), 'parameter') then
      RunParameterizedLookup
    else if SameText(ParamStr(1), 'missing-client') then
      RunMissingClientDiagnostic
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
