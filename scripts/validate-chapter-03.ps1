[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $PostgreSQLClient = 'C:\Program Files\PostgreSQL\18\bin\libpq.dll',
  [string] $StudioVersion = '37.0'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot

& "$PSScriptRoot\validate-firestore-m0.ps1" `
  -AdminPassword $AdminPassword -AppPassword $AppPassword `
  -StudioVersion $StudioVersion
if ($LASTEXITCODE -ne 0) { throw 'Preparação do FireStore M0 falhou.' }

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
$source = 'chapters\chapter-03\src\Chapter03Checks.dpr'
foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-03"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $command = "call `"$rsvars`" && $compiler -B -E`"$output`" " +
    "-N0`"$output`" -NH`"$output`" `"$source`""
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "Compilação $architecture falhou." }
}

$firebirdDatabase = Get-ChildItem '.deps\firestore\m0-*.fdb' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$sqliteDatabase = Get-ChildItem '.deps\firestore\m0-*-Win32.sqlite' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $firebirdDatabase -or -not $sqliteDatabase) {
  throw 'Bancos descartáveis M0 não encontrados.'
}
if (-not (Test-Path -LiteralPath $PostgreSQLClient)) {
  throw "Cliente PostgreSQL não encontrado: $PostgreSQLClient"
}

$env:FIRESTORE_DB_HOST = '127.0.0.1'
$env:FIRESTORE_DB_PORT = '3050'
$env:FIRESTORE_DB_NAME = $firebirdDatabase.FullName
$env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD = $AppPassword
$env:CH03_SQLITE_DATABASE = $sqliteDatabase.FullName
$env:CH03_LIBPQ = (Resolve-Path $PostgreSQLClient).Path

foreach ($architecture in @('Win32', 'Win64')) {
  $env:FIRESTORE_FBCLIENT = (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
  $executable = ".deps\build\$architecture\chapter-03\Chapter03Checks.exe"
  foreach ($mode in @('temporary', 'private', 'persistent', 'firebird',
      'postgres-config', 'environment')) {
    $definitions = Join-Path (Resolve-Path '.deps').Path `
      "chapter03-$architecture-$mode.ini"
    Remove-Item -LiteralPath $definitions -ErrorAction SilentlyContinue
    $env:CH03_CONNECTION_DEFS = $definitions
    & $executable $mode
    if ($LASTEXITCODE -ne 0) { throw "Teste $mode/$architecture falhou." }
  }
}

Write-Output 'Capítulo 3: EX-03-01/02/05 executados; EX-03-03/04 compilados e parciais.'
