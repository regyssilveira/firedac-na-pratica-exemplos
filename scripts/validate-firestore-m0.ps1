[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion = '37.0'
)

$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\build-firestore-m0.ps1" -StudioVersion $StudioVersion

$runId = [Guid]::NewGuid().ToString('N')
$dataDirectory = Join-Path (Resolve-Path '.deps').Path 'firestore'
New-Item -ItemType Directory -Force -Path $dataDirectory | Out-Null
$sqliteMigrations = (Resolve-Path 'firestore\database\sqlite\migrations').Path

foreach ($platform in @('Win32', 'Win64')) {
  $env:FIRESTORE_DRIVER = 'SQLite'
  $env:FIRESTORE_DB_NAME = Join-Path $dataDirectory "m0-$runId-$platform.sqlite"
  $env:FIRESTORE_MIGRATIONS = $sqliteMigrations
  $executable = ".deps\build\$platform\FireStoreBootstrap.exe"
  & $executable migrate
  & $executable migrate
  & $executable smoke
  if ($LASTEXITCODE -ne 0) { throw "Validação SQLite $platform falhou." }
}

$databasePath = Join-Path $dataDirectory "m0-$runId.fdb"
& "$PSScriptRoot\provision-firestore-firebird.ps1" `
  -DatabasePath $databasePath -AdminPassword $AdminPassword -AppPassword $AppPassword

$env:FIRESTORE_DRIVER = 'FB'
$env:FIRESTORE_DB_HOST = '127.0.0.1'
$env:FIRESTORE_DB_PORT = '3050'
$env:FIRESTORE_DB_NAME = $databasePath
$env:FIRESTORE_DB_USER = 'SYSDBA'
$env:FIRESTORE_DB_PASSWORD = $AdminPassword
$env:FIRESTORE_MIGRATIONS = (Resolve-Path 'firestore\database\firebird\migrations').Path

$env:FIRESTORE_FBCLIENT = (Resolve-Path '.deps\firebird\Win32\fbclient.dll').Path
& '.deps\build\Win32\FireStoreBootstrap.exe' migrate
& '.deps\build\Win32\FireStoreBootstrap.exe' migrate
if ($LASTEXITCODE -ne 0) { throw 'Migrations Firebird Win32 falharam.' }

& "$PSScriptRoot\grant-firestore-app.ps1" `
  -DatabasePath $databasePath -AdminPassword $AdminPassword
$env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD = $AppPassword
& '.deps\build\Win32\FireStoreBootstrap.exe' smoke
if ($LASTEXITCODE -ne 0) { throw 'Smoke Firebird Win32 falhou.' }

$env:FIRESTORE_FBCLIENT = (Resolve-Path '.deps\firebird\Win64\fbclient.dll').Path
& '.deps\build\Win64\FireStoreBootstrap.exe' migrate
& '.deps\build\Win64\FireStoreBootstrap.exe' smoke
if ($LASTEXITCODE -ne 0) { throw 'Validação Firebird Win64 falhou.' }

$isql = (Resolve-Path '.deps\firebird\Win32\isql.exe').Path
$serverDatabase = "127.0.0.1/3050:$databasePath"
$safeAdminPassword = $AdminPassword.Replace("'", "''")
$checksumSql = @"
CONNECT '$serverDatabase' USER SYSDBA PASSWORD '$safeAdminPassword';
UPDATE schema_version SET checksum = 'INVALID' WHERE version = 1;
COMMIT;
"@
$checksumSql | & $isql -b -quiet
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível preparar o teste de checksum.' }

$env:FIRESTORE_DB_USER = 'SYSDBA'
$env:FIRESTORE_DB_PASSWORD = $AdminPassword
$env:FIRESTORE_FBCLIENT = (Resolve-Path '.deps\firebird\Win32\fbclient.dll').Path
& '.deps\build\Win32\FireStoreBootstrap.exe' migrate
if ($LASTEXITCODE -eq 0) { throw 'Checksum divergente não foi rejeitado.' }
Write-Host 'Checksum divergente rejeitado como esperado.'

& "$PSScriptRoot\provision-firestore-firebird.ps1" `
  -DatabasePath $databasePath -AdminPassword $AdminPassword `
  -AppPassword $AppPassword -Reset
& '.deps\build\Win32\FireStoreBootstrap.exe' migrate
if ($LASTEXITCODE -ne 0) { throw 'Migration após reset falhou.' }
& "$PSScriptRoot\grant-firestore-app.ps1" `
  -DatabasePath $databasePath -AdminPassword $AdminPassword
$env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD = $AppPassword
& '.deps\build\Win32\FireStoreBootstrap.exe' smoke
if ($LASTEXITCODE -ne 0) { throw 'Smoke após reset falhou.' }

Write-Host "M0 aprovado em SQLite e Firebird, Win32 e Win64. Banco descartável: $databasePath"
