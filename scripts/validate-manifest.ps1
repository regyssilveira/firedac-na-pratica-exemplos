param([string]$Manifest = "$PSScriptRoot\..\manifest\examples.json")

$ErrorActionPreference = 'Stop'
$data = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$allowed = @('PL', 'IM', 'CP', 'EX', 'RV')
$ids = @{}

if ($data.schemaVersion -ne 1) { throw 'schemaVersion deve ser 1.' }
foreach ($example in $data.examples) {
  if ($example.id -notmatch '^EX-(\d{2})-(\d{2})$') { throw "ID inválido: $($example.id)" }
  if ($ids.ContainsKey($example.id)) { throw "ID duplicado: $($example.id)" }
  $ids[$example.id] = $true
  if ($allowed -notcontains $example.status) { throw "Estado inválido em $($example.id)." }
  if (($example.status -ne 'PL') -and ($example.evidence.Count -eq 0)) {
    throw "$($example.id) avançou para $($example.status) sem evidência."
  }
}

Write-Output "Manifesto válido: $($data.examples.Count) exemplos."
