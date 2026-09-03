[CmdletBinding()]
param([string] $StudioVersion = '37.0')

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
$source = 'chapters\chapter-14\src\Chapter14Checks.dpr'

foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-14"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $command = "call `"$rsvars`" && $compiler -B -E`"$output`" " +
    "-N0`"$output`" -NH`"$output`" `"$source`""
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "Compilação $architecture falhou." }
  $executable = Join-Path $output 'Chapter14Checks.exe'
  foreach ($mode in @('create', 'copy', 'clone', 'master-detail', 'nested')) {
    & $executable $mode
    if ($LASTEXITCODE -ne 0) { throw "Teste $mode/$architecture falhou." }
  }
}

Write-Output 'Capítulo 14 aprovado em Win32 e Win64.'
