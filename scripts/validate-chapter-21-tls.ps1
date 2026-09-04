[CmdletBinding()]
param(
  [string] $PostgreSQLPassword = 'PostgreSQL-Ch21-TLS-Only!',
  [string] $StudioVersion = '37.0',
  [string] $PostgreSQLClientWin32 =
    'D:\Delphi\delphimvcframework\samples\activerecord_showcase\bin32\libpq.dll',
  [string] $PostgreSQLClientWin64 =
    'D:\Delphi\delphimvcframework\samples\activerecord_showcase\bin64\libpq.dll'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot
$container = 'firedac-book-ch21-tls'
$port = '15433'
$tlsRoot = Join-Path $repositoryRoot '.deps\chapter-21-tls'

function Remove-TlsContainer {
  if (docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $container }) {
    docker rm -f $container | Out-Null
  }
}

foreach ($client in @($PostgreSQLClientWin32, $PostgreSQLClientWin64)) {
  if (-not (Test-Path -LiteralPath $client)) {
    throw "Cliente PostgreSQL não encontrado: $client"
  }
}

New-Item -ItemType Directory -Force -Path $tlsRoot | Out-Null
Get-ChildItem -LiteralPath $tlsRoot -File -ErrorAction SilentlyContinue |
  Remove-Item -Force
$dockerTlsRoot = $tlsRoot.Replace('\', '/')

try {
  Remove-TlsContainer
  docker pull alpine/openssl:latest | Out-Null
  docker pull postgres:18 | Out-Null

  docker run --rm --volume "${dockerTlsRoot}:/work" alpine/openssl:latest `
    req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=FireDAC Book Test CA' `
    -keyout /work/ca.key -out /work/ca.crt | Out-Null
  docker run --rm --volume "${dockerTlsRoot}:/work" alpine/openssl:latest `
    req -newkey rsa:2048 -nodes -subj '/CN=localhost' `
    -addext 'subjectAltName=DNS:localhost' `
    -keyout /work/server.key -out /work/server.csr | Out-Null
  docker run --rm --volume "${dockerTlsRoot}:/work" alpine/openssl:latest `
    x509 -req -days 2 -in /work/server.csr -CA /work/ca.crt -CAkey /work/ca.key `
    -CAcreateserial -copy_extensions copy -out /work/server.crt | Out-Null
  docker run --rm --volume "${dockerTlsRoot}:/work" alpine/openssl:latest `
    req -x509 -newkey rsa:2048 -nodes -days 2 -subj '/CN=Wrong Test CA' `
    -keyout /work/wrong-ca.key -out /work/wrong-ca.crt | Out-Null

  docker run --detach --name $container --publish "${port}:5432" `
    --mount "type=bind,src=$tlsRoot,dst=/tls,readonly" `
    --env 'POSTGRES_USER=postgres' `
    --env "POSTGRES_PASSWORD=$PostgreSQLPassword" `
    --env 'POSTGRES_DB=postgres' `
    postgres:18 bash -c `
    'cp /tls/server.crt /tmp/server.crt && cp /tls/server.key /tmp/server.key && chown postgres:postgres /tmp/server.* && chmod 600 /tmp/server.key && exec docker-entrypoint.sh postgres -c ssl=on -c ssl_cert_file=/tmp/server.crt -c ssl_key_file=/tmp/server.key' |
    Out-Null

  foreach ($attempt in 1..60) {
    docker exec $container pg_isready -U postgres -d postgres 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 1
  }
  if ($LASTEXITCODE -ne 0) {
    docker logs $container
    throw 'PostgreSQL TLS não ficou pronto.'
  }

  $rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
  $source = 'chapters\chapter-21\src\Chapter21TlsChecks.dpr'
  foreach ($architecture in @('Win32', 'Win64')) {
    $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
    $output = ".deps\build\$architecture\chapter-21-tls"
    New-Item -ItemType Directory -Force -Path $output | Out-Null
    $command = "call `"$rsvars`" && $compiler -B -E`"$output`" " +
      "-N0`"$output`" -NH`"$output`" `"$source`""
    & cmd.exe /d /s /c $command
    if ($LASTEXITCODE -ne 0) { throw "Compilação TLS $architecture falhou." }

    $env:CH21_LIBPQ = if ($architecture -eq 'Win32') {
      (Resolve-Path $PostgreSQLClientWin32).Path
    } else {
      (Resolve-Path $PostgreSQLClientWin64).Path
    }
    $env:CH21_TLS_PORT = $port
    $env:CH21_TLS_PASSWORD = $PostgreSQLPassword
    $env:CH21_TLS_CA = (Resolve-Path (Join-Path $tlsRoot 'ca.crt')).Path
    $env:CH21_TLS_WRONG_CA =
      (Resolve-Path (Join-Path $tlsRoot 'wrong-ca.crt')).Path
    & "$output\Chapter21TlsChecks.exe"
    if ($LASTEXITCODE -ne 0) { throw "EX-21-03/$architecture falhou." }
  }

  Write-Output 'Capítulo 21 TLS: verify-full e falhas de hostname/CA aprovados em Win32 e Win64.'
}
finally {
  Remove-TlsContainer
}
