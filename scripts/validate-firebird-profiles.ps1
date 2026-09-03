param(
  [string]$BdsRoot = ${env:ProgramFiles(x86)} + '\Embarcadero\Studio\37.0',
  [string]$RepositoryRoot = (Resolve-Path "$PSScriptRoot\..").Path
)

$ErrorActionPreference = 'Stop'
foreach ($name in @('FIRESTORE_DB_HOST','FIRESTORE_DB_PORT','FIRESTORE_DB_USER','FIRESTORE_DB_PASSWORD','FIRESTORE_FB_DATABASE')) {
  if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
    throw "Variável obrigatória ausente: $name"
  }
}

& "$PSScriptRoot\install-firebird-clients.ps1" -Architecture Both
$source = Join-Path $RepositoryRoot 'infra\firebird\ValidateFireDACConnection.dpr'

foreach ($target in @(
  @{ Name='Win32'; Compiler='dcc32.exe' },
  @{ Name='Win64'; Compiler='dcc64.exe' }
)) {
  $output = Join-Path $RepositoryRoot ".deps\build\$($target.Name)"
  New-Item -ItemType Directory -Force -Path $output | Out-Null
  & (Join-Path $BdsRoot "bin\$($target.Compiler)") -B "-E$output" "-N0$output" "-NH$output" $source
  if ($LASTEXITCODE -ne 0) { throw "Compilação $($target.Name) falhou." }

  $env:FIRESTORE_DB_NAME = $env:FIRESTORE_FB_DATABASE
  $env:FIRESTORE_FBCLIENT = Join-Path $RepositoryRoot ".deps\firebird\$($target.Name)\fbclient.dll"
  & (Join-Path $output 'ValidateFireDACConnection.exe')
  if ($LASTEXITCODE -ne 0) { throw "Conexão $($target.Name) falhou." }
}

Write-Output 'Perfis Firebird Win32 e Win64 aprovados.'
