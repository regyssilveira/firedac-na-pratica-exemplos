[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $DatabasePath,
  [Parameter(Mandatory)] [string] $AdminPassword,
  [string] $AdminUser = 'SYSDBA',
  [string] $AppUser = 'FIRESTORE_APP',
  [string] $HostName = '127.0.0.1',
  [int] $Port = 3050,
  [string] $Isql = '.deps\firebird\Win32\isql.exe'
)

$ErrorActionPreference = 'Stop'
if ($AdminUser -notmatch '^[A-Za-z][A-Za-z0-9_]{0,30}$' -or
    $AppUser -notmatch '^[A-Za-z][A-Za-z0-9_]{0,30}$') {
  throw 'Os nomes dos usuários devem ser identificadores SQL simples.'
}

$resolvedIsql = (Resolve-Path -LiteralPath $Isql).Path
$absoluteDatabase = [System.IO.Path]::GetFullPath($DatabasePath)
$serverDatabase = "${HostName}/${Port}:$absoluteDatabase"
$safeServerDatabase = $serverDatabase.Replace("'", "''")
$safeAdminPassword = $AdminPassword.Replace("'", "''")
$grantSql = @"
CONNECT '$safeServerDatabase' USER $AdminUser PASSWORD '$safeAdminPassword';
GRANT SELECT, INSERT, UPDATE, DELETE ON schema_version TO USER $AppUser;
GRANT SELECT, INSERT, UPDATE, DELETE ON category TO USER $AppUser;
GRANT SELECT, INSERT, UPDATE, DELETE ON product TO USER $AppUser;
GRANT EXECUTE ON PROCEDURE benchmark_product_rows TO USER $AppUser;
COMMIT;
"@
$grantSql | & $resolvedIsql -b -quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha ao conceder privilégios ao usuário da aplicação.' }

Write-Host "Privilégios mínimos concedidos a $AppUser."
