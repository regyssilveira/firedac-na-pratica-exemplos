$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourceFiles = Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
  Where-Object { $_.Extension -in '.pas', '.dpr' }

$withUsages = Select-String -Path $sourceFiles.FullName `
  -Pattern '^\s*with\b.*\bdo\b' -CaseSensitive:$false
if ($withUsages) {
  $withUsages | ForEach-Object { Write-Error "Uso proibido de with: $($_.Path):$($_.LineNumber)" }
}

$legacyConcatenations = Select-String -Path $sourceFiles.FullName -Pattern "'\s*\+\s*$"
$legacyLimit = 135
if ($legacyConcatenations.Count -gt $legacyLimit) {
  throw "O passivo de concatenações multilinha aumentou: $($legacyConcatenations.Count) > $legacyLimit. Use strings multilinha do Delphi 13."
}

Write-Host "Convenções: with=0; concatenações legadas=$($legacyConcatenations.Count)/$legacyLimit."
