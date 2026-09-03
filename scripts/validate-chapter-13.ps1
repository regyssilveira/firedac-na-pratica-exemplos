[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion = '37.0',
  [int] $BenchmarkRepetitions = 3
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot

& "$PSScriptRoot\validate-firestore-m0.ps1" `
  -AdminPassword $AdminPassword -AppPassword $AppPassword `
  -StudioVersion $StudioVersion
if ($LASTEXITCODE -ne 0) { throw 'Preparação do FireStore M0 falhou.' }

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
$source = 'chapters\chapter-13\src\Chapter13Checks.dpr'
foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-13"
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
$env:CH13_CSV_FILE = (Resolve-Path 'chapters\chapter-13\data\products.csv').Path

$bm01File = 'chapters\chapter-13\evidence\bm-01-raw.csv'
$bm07File = 'chapters\chapter-13\evidence\bm-07-raw.csv'
$bm01Results = [System.Collections.Generic.List[string]]::new()
$bm07Results = [System.Collections.Generic.List[string]]::new()
$header = 'driver;architecture;method;count;elapsed_ms;rows_per_second;repetition'
$bm01Results.Add($header)
$bm07Results.Add($header)

foreach ($architecture in @('Win32', 'Win64')) {
  $sqliteDatabase = Get-ChildItem ".deps\firestore\m0-*-$architecture.sqlite" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $sqliteDatabase) { throw "Banco SQLite $architecture não encontrado." }
  $env:CH13_SQLITE_DATABASE = $sqliteDatabase.FullName
  $env:FIRESTORE_FBCLIENT =
    (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
  $env:CH13_ARCH = $architecture
  $executable = ".deps\build\$architecture\chapter-13\Chapter13Checks.exe"

  foreach ($driver in @('SQLite', 'FB')) {
    $env:CH13_DRIVER = $driver
    foreach ($mode in @('array', 'error', 'csv', 'transfer')) {
      & $executable $mode
      if ($LASTEXITCODE -ne 0) {
        throw "Teste $mode/$driver/$architecture falhou."
      }
    }
    foreach ($method in @('line', 'array')) {
      foreach ($count in @(1, 100, 1000, 10000, 100000)) {
        for ($repetition = 1; $repetition -le $BenchmarkRepetitions; $repetition++) {
          $row = & $executable benchmark $method $count
          if ($LASTEXITCODE -ne 0) {
            throw "Benchmark $method/$count/$driver/$architecture falhou."
          }
          if ($method -eq 'line') {
            $bm01Results.Add("$row;$repetition")
          } else {
            $bm07Results.Add("$row;$repetition")
          }
        }
      }
    }
  }
}

$bm01Results | Set-Content -LiteralPath $bm01File -Encoding utf8
$bm07Results | Set-Content -LiteralPath $bm07File -Encoding utf8
Write-Output "Dados brutos gravados em $bm01File e $bm07File."
Write-Output 'Capítulo 13 aprovado em SQLite/Firebird e Win32/Win64.'
