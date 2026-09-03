[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion = '37.0'
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $repositoryRoot

& "$PSScriptRoot\validate-firestore-m0.ps1" -AdminPassword $AdminPassword `
  -AppPassword $AppPassword -StudioVersion $StudioVersion
if ($LASTEXITCODE -ne 0) { throw 'Preparação do FireStore M0 falhou.' }

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
$source = 'chapters\chapter-18\src\Chapter18Checks.dpr'
foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-18"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  $command = "call `"$rsvars`" && $compiler -B -E`"$output`" -N0`"$output`" -NH`"$output`" `"$source`""
  & cmd.exe /d /s /c $command
  if ($LASTEXITCODE -ne 0) { throw "Compilação $architecture falhou." }
}

$firebirdDatabase = Get-ChildItem '.deps\firestore\m0-*.fdb' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:FIRESTORE_DB_HOST = '127.0.0.1'; $env:FIRESTORE_DB_PORT = '3050'
$env:FIRESTORE_DB_NAME = $firebirdDatabase.FullName; $env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD = $AppPassword
$bm10 = [System.Collections.Generic.List[string]]::new()
$bm02 = [System.Collections.Generic.List[string]]::new()
$bm10.Add('benchmark_id,architecture,driver,repetition,variant,duration_us,commands,checksum')
$bm02.Add('benchmark_id,architecture,driver,repetition,open_us,total_us,initial_rows,rows,memory_delta')

foreach ($architecture in @('Win32', 'Win64')) {
  $env:FIRESTORE_FBCLIENT = (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
  $sqliteDatabase = Get-ChildItem ".deps\firestore\m0-*-$architecture.sqlite" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  $env:CH18_SQLITE_DATABASE = $sqliteDatabase.FullName
  $exe = ".deps\build\$architecture\chapter-18\Chapter18Checks.exe"
  foreach ($driver in @('SQLite', 'FB')) {
    $env:CH18_DRIVER = $driver
    $env:CH18_INFO_FILE = (Join-Path (Resolve-Path 'chapters\chapter-18\evidence').Path "environment-$architecture-$driver.txt")
    $env:CH18_TRACE_FILE = (Join-Path (Resolve-Path '.deps').Path "chapter18-$architecture-$driver-nplusone-trace.txt")
    foreach ($mode in @('nplusone', 'prepare', 'fetch', 'plan', 'info')) {
      $env:CH18_ENABLE_TRACE = if ($mode -eq 'nplusone') { '1' } else { '0' }
      $output = & $exe $mode
      if ($LASTEXITCODE -ne 0) { throw "$mode/$driver/$architecture falhou: $output" }
      Write-Output $output
    }
    $trace = Get-Content -LiteralPath $env:CH18_TRACE_FILE -Raw
    if ($trace -notmatch 'benchmark_product_rows|WITH RECURSIVE seq') {
      throw "Trace $driver/$architecture não contém a consulta em lote."
    }
    if ($trace -notmatch 'MOD\(|% 10') {
      throw "Trace $driver/$architecture não contém a consulta N+1."
    }
    $env:CH18_ENABLE_TRACE = '0'
    for ($rep = 1; $rep -le 10; $rep++) {
      $n = (& $exe nplusone) -join ' '
      if ($n -notmatch 'n1_calls=(\d+) batch_calls=(\d+) checksum=(\d+) n1_us=(\d+) batch_us=(\d+)') { throw 'Saída N+1 inválida.' }
      $bm10.Add("BM-10,$architecture,$driver,$rep,n_plus_one,$($Matches[4]),$($Matches[1]),$($Matches[3])")
      $bm10.Add("BM-10,$architecture,$driver,$rep,batch,$($Matches[5]),$($Matches[2]),$($Matches[3])")
      $f = (& $exe fetch) -join ' '
      if ($f -notmatch 'open_us=(\d+) total_us=(\d+) initial_rows=(\d+) rows=(\d+) memory_delta=(-?\d+)') { throw 'Saída fetch inválida.' }
      $bm02.Add("BM-02,$architecture,$driver,$rep,$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4]),$($Matches[5])")
    }
  }
}

$bm10 | Set-Content 'chapters\chapter-18\evidence\bm-10-raw.csv' -Encoding utf8
$bm02 | Set-Content 'chapters\chapter-18\evidence\bm-02-raw.csv' -Encoding utf8
Write-Output 'Capítulo 18 aprovado: EX-18-01–05 e BM-02/BM-10 em SQLite/Firebird, Win32/Win64.'
