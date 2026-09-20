$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
  Where-Object {
    $_.Extension -in '.pas', '.dpr' -and
    $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar).deps$([IO.Path]::DirectorySeparatorChar)*"
  }

$withUsages = Select-String -Path $sourceFiles.FullName `
  -Pattern '^\s*with\b.*\bdo\b' -CaseSensitive:$false
if ($withUsages) {
  $withUsages | ForEach-Object { Write-Error "Uso proibido de with: $($_.Path):$($_.LineNumber)" }
}

$legacyConcatenations = Select-String -Path $sourceFiles.FullName -Pattern "'\s*\+\s*$"
if ($legacyConcatenations) {
  $legacyConcatenations | ForEach-Object {
    Write-Error "Concatenação multilinha proibida: $($_.Path):$($_.LineNumber)"
  }
}

$singleLetterDeclarations = Select-String -Path $sourceFiles.FullName `
  -Pattern '^\s*(?:var\s+)?[A-Z](?:\s*,\s*[A-Z])*\s*:'
if ($singleLetterDeclarations) {
  $singleLetterDeclarations | ForEach-Object {
    Write-Error "Identificador abreviado proibido: $($_.Path):$($_.LineNumber)"
  }
}

Write-Host 'Convenções: with=0; concatenações multilinha=0; identificadores de uma letra=0.'
