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

$studioBin = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin"
$rsvars = Join-Path $studioBin 'rsvars.bat'
$source = 'chapters\chapter-02\src'

foreach ($architecture in @('Win32', 'Win64')) {
  $compiler = if ($architecture -eq 'Win32') { 'dcc32' } else { 'dcc64' }
  $output = ".deps\build\$architecture\chapter-02"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  foreach ($project in @('Chapter02Checks.dpr', 'Chapter02Vcl.dpr')) {
    $command = "call `"$rsvars`" && $compiler -B -E`"$output`" " +
      "-N0`"$output`" -NH`"$output`" `"$source\$project`""
    & cmd.exe /d /s /c $command
    if ($LASTEXITCODE -ne 0) { throw "Compilação de $project para $architecture falhou." }
  }
}

$firebirdDatabase = Get-ChildItem '.deps\firestore\m0-*.fdb' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$sqliteDatabase = Get-ChildItem '.deps\firestore\m0-*-Win32.sqlite' |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $firebirdDatabase -or -not $sqliteDatabase) {
  throw 'Bancos descartáveis M0 não encontrados.'
}

$env:FIRESTORE_DB_HOST = '127.0.0.1'
$env:FIRESTORE_DB_PORT = '3050'
$env:FIRESTORE_DB_NAME = $firebirdDatabase.FullName
$env:FIRESTORE_DB_USER = 'FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD = $AppPassword
$env:CH02_SQLITE_DATABASE = $sqliteDatabase.FullName
$env:CH02_AUTORUN = '1'

foreach ($architecture in @('Win32', 'Win64')) {
  $output = ".deps\build\$architecture\chapter-02"
  $checks = Join-Path $output 'Chapter02Checks.exe'
  $vcl = Join-Path $output 'Chapter02Vcl.exe'
  $env:FIRESTORE_FBCLIENT = (Resolve-Path ".deps\firebird\$architecture\fbclient.dll").Path

  foreach ($driver in @('SQLite', 'FB')) {
    $env:FIRESTORE_DRIVER = $driver
    foreach ($mode in @('core', 'flow', 'report')) {
      & $checks $mode
      if ($LASTEXITCODE -ne 0) { throw "Teste $mode/$driver/$architecture falhou." }
    }

    $resultFile = Join-Path (Resolve-Path '.deps').Path `
      "chapter02-vcl-$architecture-$driver.txt"
    Remove-Item -LiteralPath $resultFile -ErrorAction SilentlyContinue
    $env:CH02_AUTORUN_RESULT = $resultFile
    $process = Start-Process -FilePath $vcl -PassThru -Wait -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
      $diagnostic = if (Test-Path $resultFile) { Get-Content $resultFile -Raw } `
        else { 'resultado não gravado' }
      throw "Autoteste VCL $driver/$architecture falhou: $diagnostic"
    }
    if ((Get-Content $resultFile -Raw) -ne 'OK') {
      throw "Autoteste VCL $driver/$architecture não confirmou o compartilhamento."
    }
  }

  $env:FIRESTORE_DRIVER = 'FB'
  & $checks drivers
  if ($LASTEXITCODE -ne 0) { throw "Teste de drivers/$architecture falhou." }
}

$dfm = Get-Content "$source\Chapter02.CatalogData.dfm" -Raw
foreach ($forbidden in @('Password=', 'Password =', 'Connected = True', 'Active = True')) {
  if ($dfm -match [regex]::Escape($forbidden)) {
    throw "O DFM contém configuração proibida: $forbidden"
  }
}

Write-Output 'Capítulo 2 aprovado: cinco exemplos em Win32/Win64 e SQLite/Firebird.'
