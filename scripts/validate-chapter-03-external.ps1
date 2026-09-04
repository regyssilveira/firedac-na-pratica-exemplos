[CmdletBinding()]
param(
  [string] $AdminPassword = 'masterkey',
  [string] $AppPassword = 'FireStore-Ch03-Only!',
  [string] $PostgreSQLPassword = 'PostgreSQL-Ch03-Only!',
  [string] $StudioVersion = '37.0',
  [string] $PostgreSQLClientWin32 =
    'D:\Delphi\delphimvcframework\samples\activerecord_showcase\bin32\libpq.dll',
  [string] $PostgreSQLClientWin64 =
    'D:\Delphi\delphimvcframework\samples\activerecord_showcase\bin64\libpq.dll'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot

$firebirdContainer = 'firedac-book-ch03-firebird'
$postgresContainer = 'firedac-book-ch03-postgres'
$firebirdPort = '13050'
$postgresPort = '15432'
$firebirdImage = 'firebirdsql/firebird:5.0.4'
$postgresImage = 'postgres:18'

function Remove-LabContainer([string] $Name) {
  if (docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $Name }) {
    docker rm -f $Name | Out-Null
  }
}

function Wait-ContainerReady([string] $Name, [scriptblock] $Probe) {
  foreach ($attempt in 1..60) {
    if (& $Probe) { return }
    Start-Sleep -Seconds 1
  }
  docker logs $Name
  throw "O contêiner $Name não ficou pronto."
}

foreach ($client in @($PostgreSQLClientWin32, $PostgreSQLClientWin64)) {
  if (-not (Test-Path -LiteralPath $client)) {
    throw "Cliente PostgreSQL não encontrado: $client"
  }
}

try {
  Remove-LabContainer $firebirdContainer
  Remove-LabContainer $postgresContainer

  docker pull $firebirdImage | Out-Null
  docker pull $postgresImage | Out-Null

  $databaseConfig = (Resolve-Path 'chapters\chapter-03\lab\databases.conf').Path
  $initSql = (Resolve-Path 'chapters\chapter-03\lab\firestore.sql').Path
  docker run --detach --name $firebirdContainer `
    --publish "${firebirdPort}:3050" `
    --mount "type=bind,src=$databaseConfig,dst=/opt/firebird/databases.conf,readonly" `
    --mount "type=bind,src=$initSql,dst=/docker-entrypoint-initdb.d/010-firestore.sql,readonly" `
    --env "FIREBIRD_ROOT_PASSWORD=$AdminPassword" `
    --env 'FIREBIRD_USER=FIRESTORE_APP' `
    --env "FIREBIRD_PASSWORD=$AppPassword" `
    --env 'FIREBIRD_DATABASE=firestore.fdb' `
    --env 'FIREBIRD_DATABASE_DEFAULT_CHARSET=UTF8' `
    $firebirdImage | Out-Null

  docker run --detach --name $postgresContainer `
    --publish "${postgresPort}:5432" `
    --env 'POSTGRES_USER=postgres' `
    --env "POSTGRES_PASSWORD=$PostgreSQLPassword" `
    --env 'POSTGRES_DB=postgres' `
    $postgresImage | Out-Null

  Wait-ContainerReady $firebirdContainer {
    $client = [System.Net.Sockets.TcpClient]::new()
    try {
      $client.Connect('127.0.0.1', [int] $firebirdPort)
      return $client.Connected
    }
    catch { return $false }
    finally { $client.Dispose() }
  }
  Wait-ContainerReady $postgresContainer {
    docker exec $postgresContainer pg_isready -U postgres -d postgres 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
  }

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
  if (-not $firebirdDatabase) { throw 'Banco Firebird M0 não encontrado.' }

  $env:FIRESTORE_DB_HOST = '127.0.0.1'
  $env:FIRESTORE_DB_PORT = '3050'
  $env:FIRESTORE_DB_NAME = $firebirdDatabase.FullName
  $env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
  $env:FIRESTORE_DB_PASSWORD = $AppPassword
  $env:CH03_REMOTE_FB_HOST = '127.0.0.1'
  $env:CH03_REMOTE_FB_PORT = $firebirdPort
  $env:CH03_REMOTE_FB_DATABASE = '/var/lib/firebird/data/firestore.fdb'
  $env:CH03_REMOTE_FB_ALIAS = 'FIRESTORE_PROD'
  $env:CH03_PG_HOST = '127.0.0.1'
  $env:CH03_PG_PORT = $postgresPort
  $env:CH03_PG_DATABASE = 'postgres'
  $env:CH03_PG_USER = 'postgres'
  $env:CH03_PG_PASSWORD = $PostgreSQLPassword

  foreach ($architecture in @('Win32', 'Win64')) {
    $env:FIRESTORE_FBCLIENT =
      (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
    $env:CH03_LIBPQ = if ($architecture -eq 'Win32') {
      (Resolve-Path $PostgreSQLClientWin32).Path
    } else {
      (Resolve-Path $PostgreSQLClientWin64).Path
    }
    $executable = ".deps\build\$architecture\chapter-03\Chapter03Checks.exe"
    & $executable firebird
    if ($LASTEXITCODE -ne 0) { throw "EX-03-03/$architecture falhou." }
    & $executable postgres-config
    if ($LASTEXITCODE -ne 0) { throw "EX-03-04/$architecture falhou." }
  }

  Write-Output 'Capítulo 3 externo: EX-03-03 e EX-03-04 aprovados em Win32 e Win64.'
}
finally {
  Remove-LabContainer $firebirdContainer
  Remove-LabContainer $postgresContainer
}
