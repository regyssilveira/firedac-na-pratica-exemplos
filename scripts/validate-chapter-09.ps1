[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
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
$source = 'chapters\chapter-09\src\Chapter09Checks.dpr'
foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-09"
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
$bm05 = [System.Collections.Generic.List[string]]::new()
$bm05.Add('benchmark_id,architecture,driver,repetition,mode,rows,blob_size,open_us,total_us,bytes,memory_delta')

foreach ($architecture in @('Win32', 'Win64')) {
  $sqliteDatabase = Get-ChildItem ".deps\firestore\m0-*-$architecture.sqlite" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $sqliteDatabase) { throw "Banco SQLite $architecture não encontrado." }
  $env:CH09_SQLITE_DATABASE = $sqliteDatabase.FullName
  $env:FIRESTORE_FBCLIENT =
    (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
  $executable = ".deps\build\$architecture\chapter-09\Chapter09Checks.exe"

  foreach ($driver in @('SQLite', 'FB')) {
    $env:CH09_DRIVER = $driver
    foreach ($mode in @('ondemand', 'all', 'blob', 'cancel')) {
      $traceFile = Join-Path (Resolve-Path '.deps').Path `
        "chapter09-$architecture-$driver-$mode-trace.txt"
      $env:CH09_TRACE_FILE = $traceFile
      $env:CH09_ENABLE_TRACE = if ($mode -eq 'blob') { '1' } else { '0' }
      Remove-Item -LiteralPath $traceFile -ErrorAction SilentlyContinue
      & $executable $mode
      if ($LASTEXITCODE -ne 0) {
        throw "Teste $mode/$driver/$architecture falhou."
      }
    }
    $env:CH09_ENABLE_TRACE = '0'
    foreach ($blobMode in @('immediate', 'deferred', 'stream')) {
      $warmup = & $executable "benchmark-blob-$blobMode"
      if ($LASTEXITCODE -ne 0) { throw "Aquecimento BM-05/$blobMode/$driver/$architecture falhou." }
      for ($rep = 1; $rep -le 5; $rep++) {
        $result = (& $executable "benchmark-blob-$blobMode") -join ' '
        if ($LASTEXITCODE -ne 0) { throw "BM-05/$blobMode/$driver/$architecture/repetição $rep falhou." }
        if ($result -notmatch '^BM-05 mode=(immediate|deferred|stream) rows=(\d+) blob_size=(\d+) open_us=(\d+) total_us=(\d+) bytes=(\d+) memory_delta=(-?\d+)$') {
          throw "Saída BM-05 inválida: $result"
        }
        $bm05.Add("BM-05,$architecture,$driver,$rep,$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4]),$($Matches[5]),$($Matches[6]),$($Matches[7])")
      }
    }
  }

  $env:CH09_DRIVER = 'SQLite'
  $env:CH09_ENABLE_TRACE = '0'
  $env:CH09_TRACE_FILE = Join-Path (Resolve-Path '.deps').Path `
    "chapter09-$architecture-feedback-unused.txt"
  & $executable feedback
  if ($LASTEXITCODE -ne 0) { throw "Feedback VCL/$architecture falhou." }
}

$bm05 | Set-Content 'chapters\chapter-09\evidence\bm-05-raw.csv' -Encoding utf8

Write-Output 'Capítulo 9 aprovado em SQLite/Firebird, Win32/Win64; BM-05 normalizado.'
