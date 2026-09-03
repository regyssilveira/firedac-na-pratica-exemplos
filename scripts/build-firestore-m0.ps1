[CmdletBinding()]
param([string] $StudioVersion = '37.0')

$ErrorActionPreference = 'Stop'
$studioBin = "C:\Program Files (x86)\Embarcadero\Studio\$StudioVersion\bin"
$rsvars = Join-Path $studioBin 'rsvars.bat'
if (-not (Test-Path -LiteralPath $rsvars)) {
  throw "RAD Studio $StudioVersion não encontrado em $studioBin."
}

New-Item -ItemType Directory -Force -Path '.deps\build\Win32', '.deps\build\Win64' | Out-Null
$command = "call `"$rsvars`" && dcc32 -B -E.\.deps\build\Win32 firestore\src\FireStoreBootstrap.dpr && dcc64 -B -E.\.deps\build\Win64 firestore\src\FireStoreBootstrap.dpr"
& cmd.exe /d /s /c $command
if ($LASTEXITCODE -ne 0) { throw 'A compilação do FireStore M0 falhou.' }
