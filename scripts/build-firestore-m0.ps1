[CmdletBinding()]
param(
  [string] $StudioVersion = '37.0',
  [ValidateSet('Win32', 'Win64', 'Both')]
  [string] $Architecture = 'Both'
)

$ErrorActionPreference = 'Stop'
$studioBin = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin"
$rsvars = Join-Path $studioBin 'rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) {
  throw "RAD Studio $StudioVersion não encontrado em $studioBin."
}

$targets = if ($Architecture -eq 'Both') { @('Win32', 'Win64') } else { @($Architecture) }
foreach ($target in $targets) {
  $compiler = if ($target -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$target"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $command = "call `"$rsvars`" && $compiler -B -E.\$output firestore\src\FireStoreBootstrap.dpr"
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "A compilação $target do FireStore M0 falhou." }
}
