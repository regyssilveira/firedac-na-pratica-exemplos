param(
  [ValidateSet('Win32','Win64','Both')][string]$Architecture = 'Both',
  [string]$Destination = "$PSScriptRoot\..\.deps\firebird"
)

$ErrorActionPreference = 'Stop'
$manifestPath = "$PSScriptRoot\..\infra\firebird\clients.json"
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$targets = if ($Architecture -eq 'Both') { @('Win32', 'Win64') } else { @($Architecture) }

function Get-PeMachine([string]$Path) {
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $reader = [System.IO.BinaryReader]::new($stream)
    $stream.Position = 0x3C
    $peOffset = $reader.ReadInt32()
    $stream.Position = $peOffset + 4
    return ('0x{0:X4}' -f $reader.ReadUInt16())
  }
  finally { $stream.Dispose() }
}

foreach ($target in $targets) {
  $entry = $manifest.architectures.$target
  $targetDir = Join-Path $Destination $target
  $archive = Join-Path $Destination $entry.archive
  New-Item -ItemType Directory -Force -Path $Destination | Out-Null

  if (-not (Test-Path -LiteralPath $archive)) {
    Write-Output "Baixando kit oficial Firebird $($manifest.version) $target..."
    Invoke-WebRequest -Uri $entry.url -OutFile $archive
  }

  $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
  if ($actualHash -ne $entry.sha256) { throw "SHA-256 inválido para $($entry.archive)." }

  $destinationFull = [System.IO.Path]::GetFullPath($Destination).TrimEnd('\') + '\'
  $targetFull = [System.IO.Path]::GetFullPath($targetDir)
  if (-not $targetFull.StartsWith($destinationFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Destino recusado fora da raiz esperada: $targetFull"
  }
  if (Test-Path -LiteralPath $targetFull) { Remove-Item -LiteralPath $targetFull -Recurse -Force }
  Expand-Archive -LiteralPath $archive -DestinationPath $targetDir
  $client = Get-ChildItem -LiteralPath $targetDir -Recurse -Filter fbclient.dll | Select-Object -First 1
  if (-not $client) { throw "fbclient.dll não encontrado no kit $target." }
  $machine = Get-PeMachine $client.FullName
  if ($machine -ne $entry.peMachine) { throw "Arquitetura incorreta: esperado $($entry.peMachine), obtido $machine." }

  Write-Output "$target aprovado: $($client.FullName) ($machine)"
}
