[CmdletBinding()]
param([string] $StudioVersion = '37.0')

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot
$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
$source = 'chapters\chapter-15\src\Chapter15Checks.dpr'
$tempRoot = (Join-Path $repositoryRoot '.deps\chapter-15')
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$env:CH15_TEMP_DIR = $tempRoot

foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-15"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $command = "call `"$rsvars`" && $compiler -B -E`"$output`" " +
    "-N0`"$output`" -NH`"$output`" `"$source`""
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "Compilação $architecture falhou." }
  $executable = Join-Path $output 'Chapter15Checks.exe'
  foreach ($mode in @('binary', 'xml', 'json', 'persistent', 'corrupt')) {
    & $executable $mode
    if ($LASTEXITCODE -ne 0) { throw "Teste $mode/$architecture falhou." }
  }
  $env:CH15_ARCH = $architecture
  if (-not $benchmarkRows) {
    $benchmarkRows = [System.Collections.Generic.List[string]]::new()
    $benchmarkRows.Add('format;architecture;count;write_ms;read_ms;bytes;repetition')
  }
  foreach ($format in @('binary', 'xml', 'json')) {
    foreach ($count in @(1, 100, 1000, 10000, 100000)) {
      for ($repetition = 1; $repetition -le 3; $repetition++) {
        $row = & $executable benchmark $format $count
        if ($LASTEXITCODE -ne 0) {
          throw "Benchmark $format/$count/$architecture falhou."
        }
        $benchmarkRows.Add("$row;$repetition")
      }
    }
  }
}

$benchmarkRows | Set-Content `
  -LiteralPath 'chapters\chapter-15\evidence\bm-06-raw.csv' -Encoding utf8
Write-Output 'Capítulo 15 aprovado em Win32 e Win64.'
