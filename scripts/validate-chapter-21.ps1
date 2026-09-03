[CmdletBinding()]
param(
  [Parameter(Mandatory)] [string] $AdminPassword,
  [Parameter(Mandatory)] [string] $AppPassword,
  [string] $StudioVersion='37.0'
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path;Set-Location $root
& "$PSScriptRoot\validate-firestore-m0.ps1" -AdminPassword $AdminPassword -AppPassword $AppPassword -StudioVersion $StudioVersion
if($LASTEXITCODE-ne 0){throw 'Preparação M0 falhou.'}
$rsvars="C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin\rsvars.bat"
foreach($arch in @('Win32','Win64')){
  $compiler=if($arch-eq'Win32'){'dcc32'}else{'dcc64'};$out=".deps\build\$arch\chapter-21"
  New-Item -ItemType Directory -Force $out|Out-Null
  $cmd="call `"$rsvars`" && $compiler -B -E`"$out`" -N0`"$out`" -NH`"$out`" `"chapters\chapter-21\src\Chapter21Checks.dpr`""
  &cmd.exe /d /s /c $cmd;if($LASTEXITCODE-ne 0){throw "Compilação $arch falhou."}
}
$fdb=Get-ChildItem '.deps\firestore\m0-*.fdb'|Sort-Object LastWriteTime -Descending|Select-Object -First 1
$env:FIRESTORE_DB_HOST='127.0.0.1';$env:FIRESTORE_DB_PORT='3050';$env:FIRESTORE_DB_NAME=$fdb.FullName
$env:FIRESTORE_DB_USER='FIRESTORE_APP';$env:FIRESTORE_DB_PASSWORD=$AppPassword
$env:FIRESTORE_ADMIN_USER='SYSDBA';$env:FIRESTORE_ADMIN_PASSWORD=$AdminPassword
foreach($arch in @('Win32','Win64')){
  $env:FIRESTORE_FBCLIENT=(Resolve-Path ".deps\firebird\$arch\fbclient.dll").Path
  $env:CH21_SQLITE_DATABASE=(Get-ChildItem ".deps\firestore\m0-*-$arch.sqlite"|Sort-Object LastWriteTime -Descending|Select-Object -First 1).FullName
  $exe=".deps\build\$arch\chapter-21\Chapter21Checks.exe"
  foreach($driver in @('SQLite','FB')){
    $env:CH21_DRIVER=$driver
    foreach($mode in @('recovery','retry','security','smoke')){
      $result=&$exe $mode;if($LASTEXITCODE-ne 0){throw "$mode/$driver/$arch falhou: $result"};Write-Output $result
    }
  }
}

& "$PSScriptRoot\build-chapter-21-packages.ps1"
foreach($arch in @('Win32','Win64')){
  $env:CH21_DRIVER='FB';$env:FIRESTORE_FBCLIENT=(Resolve-Path ".deps\chapter-21-packages\$arch\fbclient.dll").Path
  & ".deps\chapter-21-packages\$arch\Chapter21Checks.exe" smoke
  if($LASTEXITCODE-ne 0){throw "Smoke do pacote $arch falhou."}
}

$restoreRoot='.deps\chapter-21-restore';New-Item -ItemType Directory -Force $restoreRoot|Out-Null
$backup=(Resolve-Path $restoreRoot).Path+'\firestore.fbk';$restored=(Resolve-Path $restoreRoot).Path+'\firestore-restored.fdb'
Remove-Item -LiteralPath $backup,$restored -Force -ErrorAction SilentlyContinue
$env:ISC_USER='SYSDBA';$env:ISC_PASSWORD=$AdminPassword
$gbak=(Resolve-Path '.deps\firebird\Win64\gbak.exe').Path
&$gbak -b "127.0.0.1/3050:$($fdb.FullName)" $backup
if($LASTEXITCODE-ne 0){throw 'Backup gbak falhou.'}
&$gbak -c $backup "127.0.0.1/3050:$restored"
if($LASTEXITCODE-ne 0){throw 'Restore gbak falhou.'}
$env:FIRESTORE_DB_NAME=$restored;$env:FIRESTORE_FBCLIENT=(Resolve-Path '.deps\chapter-21-packages\Win64\fbclient.dll').Path
& '.deps\chapter-21-packages\Win64\Chapter21Checks.exe' smoke
if($LASTEXITCODE-ne 0){throw 'Smoke sobre restore falhou.'}
Write-Output 'Capítulo 21 local aprovado; TLS CA/hostname e VM limpa permanecem gates externos.'
