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
$source = 'chapters\chapter-05\src\Chapter05Checks.dpr'
foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-05"
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
$bm03 = [System.Collections.Generic.List[string]]::new()
$bm03.Add('benchmark_id,architecture,driver,repetition,rows,offset,page_size,offset_us,keyset_us,first_id,offset_stable,keyset_stable')

foreach ($architecture in @('Win32', 'Win64')) {
  $sqliteDatabase = Get-ChildItem ".deps\firestore\m0-*-$architecture.sqlite" |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if (-not $sqliteDatabase) { throw "Banco SQLite $architecture não encontrado." }
  $env:CH05_SQLITE_DATABASE = $sqliteDatabase.FullName
  $env:FIRESTORE_FBCLIENT =
    (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path
  $executable = ".deps\build\$architecture\chapter-05\Chapter05Checks.exe"

  foreach ($driver in @('SQLite', 'FB')) {
    $env:CH05_DRIVER = $driver
    foreach ($mode in @('list', 'dml', 'command', 'key', 'pagination')) {
      & $executable $mode
      if ($LASTEXITCODE -ne 0) {
        throw "Teste $mode/$driver/$architecture falhou."
      }
    }
    $warmup = & $executable benchmark-pagination
    if ($LASTEXITCODE -ne 0) { throw "Aquecimento BM-03/$driver/$architecture falhou." }
    for ($rep = 1; $rep -le 5; $rep++) {
      $result = (& $executable benchmark-pagination) -join ' '
      if ($LASTEXITCODE -ne 0) { throw "BM-03/$driver/$architecture/repetição $rep falhou." }
      if ($result -notmatch '^BM-03 rows=(\d+) offset=(\d+) page_size=(\d+) offset_us=(\d+) keyset_us=(\d+) first_id=(\d+) offset_stable=(True|False) keyset_stable=(True|False)$') {
        throw "Saída BM-03 inválida: $result"
      }
      $bm03.Add("BM-03,$architecture,$driver,$rep,$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4]),$($Matches[5]),$($Matches[6]),$($Matches[7]),$($Matches[8])")
    }
  }
}

$bm03 | Set-Content 'chapters\chapter-05\evidence\bm-03-raw.csv' -Encoding utf8
Write-Output 'Capítulo 5 aprovado em SQLite/Firebird, Win32/Win64; BM-03 normalizado.'
