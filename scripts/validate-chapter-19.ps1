[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion = '37.0'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location $root
& "$PSScriptRoot\validate-firestore-m0.ps1" -AdminPassword $AdminPassword `
  -AppPassword $AppPassword -StudioVersion $StudioVersion
if ($LASTEXITCODE -ne 0) { throw 'Preparação do FireStore M0 falhou.' }

$rsvars = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
foreach ($arch in @('Win32','Win64')) {
  $compiler = if ($arch -eq 'Win32') {'dcc32'} else {'dcc64'}
  $out = ".deps\build\$arch\chapter-19"; New-Item -ItemType Directory -Force $out | Out-Null
  $cmd = "call `"$rsvars`" && $compiler -B -E`"$out`" -N0`"$out`" -NH`"$out`" `"chapters\chapter-19\src\Chapter19Checks.dpr`""
  & cmd.exe /d /s /c $cmd
  if ($LASTEXITCODE -ne 0) { throw "Compilação $arch falhou." }
}

$fdb = Get-ChildItem '.deps\firestore\m0-*.fdb' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$env:FIRESTORE_DB_HOST='127.0.0.1'; $env:FIRESTORE_DB_PORT='3050'
$env:FIRESTORE_DB_NAME=$fdb.FullName; $env:FIRESTORE_DB_USER='FIRESTORE_APP'
$env:FIRESTORE_DB_PASSWORD=$AppPassword
$bm08=[System.Collections.Generic.List[string]]::new(); $bm09=[System.Collections.Generic.List[string]]::new()
$bm08.Add('benchmark_id,architecture,driver,repetition,leases,new_us,pooled_us')
$bm09.Add('benchmark_id,architecture,driver,repetition,blocking_us,async_call_us,async_total_us,rows')

foreach ($arch in @('Win32','Win64')) {
  $env:FIRESTORE_FBCLIENT=(Resolve-Path ".deps\firebird\$arch\fbclient.dll").Path
  $env:CH19_SQLITE_DATABASE=(Get-ChildItem ".deps\firestore\m0-*-$arch.sqlite" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
  $exe=".deps\build\$arch\chapter-19\Chapter19Checks.exe"
  foreach ($driver in @('SQLite','FB')) {
    $env:CH19_DRIVER=$driver
    foreach ($mode in @('async','cancel','tasks','pool','saturation')) {
      $result=& $exe $mode
      if ($LASTEXITCODE -ne 0) { throw "$mode/$driver/$arch falhou: $result" }
      Write-Output $result
    }
    for($rep=1;$rep -le 10;$rep++) {
      $p=(& $exe poolbench)-join ' '
      if($p -notmatch 'leases=(\d+) new_us=(\d+) pooled_us=(\d+)'){throw 'Saída BM-08 inválida.'}
      $bm08.Add("BM-08,$arch,$driver,$rep,$($Matches[1]),$($Matches[2]),$($Matches[3])")
      $a=(& $exe bench)-join ' '
      if($a -notmatch 'blocking_us=(\d+) async_call_us=(\d+) async_total_us=(\d+) rows=(\d+)'){throw 'Saída BM-09 inválida.'}
      $bm09.Add("BM-09,$arch,$driver,$rep,$($Matches[1]),$($Matches[2]),$($Matches[3]),$($Matches[4])")
    }
  }
}
$bm08 | Set-Content 'chapters\chapter-19\evidence\bm-08-raw.csv' -Encoding utf8
$bm09 | Set-Content 'chapters\chapter-19\evidence\bm-09-raw.csv' -Encoding utf8
Write-Output 'Capítulo 19 aprovado: EX-19-01–05, BM-08 e BM-09 em SQLite/Firebird, Win32/Win64.'
