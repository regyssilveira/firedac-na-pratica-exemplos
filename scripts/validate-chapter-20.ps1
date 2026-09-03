[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion = '37.0'
)

$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path; Set-Location $root
& "$PSScriptRoot\validate-firestore-m0.ps1" -AdminPassword $AdminPassword `
  -AppPassword $AppPassword -StudioVersion $StudioVersion
if($LASTEXITCODE-ne 0){throw 'Preparação do FireStore M0 falhou.'}
$rsvars="C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
foreach($arch in @('Win32','Win64')){
  $compiler=if($arch-eq'Win32'){'dcc32'}else{'dcc64'}
  $out=".deps\build\$arch\chapter-20";New-Item -ItemType Directory -Force $out|Out-Null
  $cmd="call `"$rsvars`" && $compiler -B -E`"$out`" -N0`"$out`" -NH`"$out`" `"chapters\chapter-20\src\Chapter20Checks.dpr`""
  & cmd.exe /d /s /c $cmd
  if($LASTEXITCODE-ne 0){throw "Compilação $arch falhou."}
}
$fdb=Get-ChildItem '.deps\firestore\m0-*.fdb'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$env:FIRESTORE_DB_HOST='127.0.0.1';$env:FIRESTORE_DB_PORT='3050';$env:FIRESTORE_DB_NAME=$fdb.FullName
$env:FIRESTORE_DB_USER='FIRESTORE_APP';$env:FIRESTORE_DB_PASSWORD=$AppPassword
foreach($arch in @('Win32','Win64')){
  $env:FIRESTORE_FBCLIENT=(Resolve-Path ".deps\firebird\$arch\fbclient.dll").Path
  $env:CH20_SQLITE_DATABASE=(Get-ChildItem ".deps\firestore\m0-*-$arch.sqlite"|Sort-Object LastWriteTime -Descending|Select-Object -First 1).FullName
  $exe=".deps\build\$arch\chapter-20\Chapter20Checks.exe"
  foreach($driver in @('SQLite','FB')){
    $env:CH20_DRIVER=$driver
    foreach($mode in @('names','structure','routines','explorer','events')){
      $result=&$exe $mode
      if($LASTEXITCODE-ne 0){throw "$mode/$driver/$arch falhou: $result"}
      Write-Output $result
    }
  }
}
Write-Output 'Capítulo 20 aprovado: EX-20-01–05 em SQLite/Firebird, Win32/Win64.'
