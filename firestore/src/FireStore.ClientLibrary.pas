unit FireStore.ClientLibrary;

interface

function FirebirdClientLibrary(const ARoot: string): string;

implementation

uses
  System.IOUtils;

function FirebirdClientLibrary(const ARoot: string): string;
begin
{$IF Defined(WIN64)}
  Result := TPath.Combine(ARoot, '.deps\firebird\Win64\fbclient.dll');
{$ELSEIF Defined(WIN32)}
  Result := TPath.Combine(ARoot, '.deps\firebird\Win32\fbclient.dll');
{$ELSE}
  {$MESSAGE FATAL 'Este perfil Firebird requer Windows Win32 ou Win64.'}
{$ENDIF}
end;

end.
