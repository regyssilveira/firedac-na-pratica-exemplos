param(
  [Parameter(Mandatory)][ValidateSet('Win32','Win64')][string]$Architecture,
  [string]$Root = "$PSScriptRoot\..\.deps\firebird"
)

$ErrorActionPreference = 'Stop'
$client = Get-ChildItem -LiteralPath (Join-Path $Root $Architecture) -Recurse -Filter fbclient.dll | Select-Object -First 1
if (-not $client) { throw "Execute install-firebird-clients.ps1 para $Architecture." }
$hash = (Get-FileHash -LiteralPath $client.FullName -Algorithm SHA256).Hash

$port = if ($env:FIRESTORE_DB_PORT) { $env:FIRESTORE_DB_PORT } else { '3050' }
$reachable = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet
if (-not $reachable) { throw "Servidor Firebird não responde em 127.0.0.1:$port." }

Write-Output "Perfil $Architecture pronto."
Write-Output "Cliente: $($client.FullName)"
Write-Output "SHA-256 do fbclient.dll: $hash"
Write-Output "Servidor TCP alcançável em 127.0.0.1:$port."
