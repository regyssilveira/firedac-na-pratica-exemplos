[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $DatabasePath,
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $AdminUser = 'SYSDBA',
  [string] $AppUser = 'FIRESTORE_APP',
  [string] $HostName = '127.0.0.1',
  [int] $Port = 3050,
  [string] $Isql = '.deps\firebird\Win32\isql.exe',
  [switch] $Reset
)

$ErrorActionPreference = 'Stop'

if ($AdminUser -notmatch '^[A-Za-z][A-Za-z0-9_]{0,30}$' -or
    $AppUser -notmatch '^[A-Za-z][A-Za-z0-9_]{0,30}$') {
  throw 'Os nomes dos usuários devem ser identificadores SQL simples.'
}

$resolvedIsql = (Resolve-Path -LiteralPath $Isql).Path
$absoluteDatabase = [System.IO.Path]::GetFullPath($DatabasePath)
$databaseDirectory = Split-Path -Parent $absoluteDatabase
New-Item -ItemType Directory -Force -Path $databaseDirectory | Out-Null

function ConvertTo-SqlLiteral([string] $Value) {
  return $Value.Replace("'", "''")
}

$serverDatabase = "${HostName}/${Port}:$absoluteDatabase"
$safeServerDatabase = ConvertTo-SqlLiteral $serverDatabase
$safeAdminPassword = ConvertTo-SqlLiteral $AdminPassword
$safeAppPassword = ConvertTo-SqlLiteral $AppPassword

if ($Reset) {
  $dropSql = "CONNECT '$safeServerDatabase' USER $AdminUser PASSWORD '$safeAdminPassword';`nDROP DATABASE;"
  $dropSql | & $resolvedIsql -b -quiet
  if ($LASTEXITCODE -ne 0) { throw 'Não foi possível remover o banco FireStore.' }
}

if (Test-Path -LiteralPath $absoluteDatabase) {
  throw "O banco já existe. Use -Reset somente quando quiser recriá-lo: $absoluteDatabase"
}

$createSql = @"
CREATE DATABASE '$safeServerDatabase' USER $AdminUser PASSWORD '$safeAdminPassword'
  PAGE_SIZE 16384 DEFAULT CHARACTER SET UTF8;
CREATE OR ALTER USER $AppUser PASSWORD '$safeAppPassword';
COMMIT;
"@
$createSql | & $resolvedIsql -b -quiet
if ($LASTEXITCODE -ne 0) { throw 'Falha no provisionamento do banco FireStore.' }

Write-Host "Banco FireStore provisionado em $serverDatabase para o usuário $AppUser."
