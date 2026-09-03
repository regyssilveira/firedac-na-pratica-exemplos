param(
  [Parameter(Mandatory)][string]$Id,
  [Parameter(Mandatory)][ValidateSet('PL','IM','CP','EX','RV')][string]$Status,
  [string]$Evidence,
  [string]$Manifest = "$PSScriptRoot\..\manifest\examples.json"
)

$ErrorActionPreference = 'Stop'
$order = @('PL', 'IM', 'CP', 'EX', 'RV')
$data = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
$example = $data.examples | Where-Object id -eq $Id
if (-not $example) { throw "Exemplo não encontrado: $Id" }

$current = [Array]::IndexOf($order, [string]$example.status)
$target = [Array]::IndexOf($order, $Status)
if ($target -gt ($current + 1)) { throw "Transição inválida: $($example.status) -> $Status" }
if (($target -gt 0) -and [string]::IsNullOrWhiteSpace($Evidence)) {
  throw 'Informe -Evidence para avançar o estado.'
}
if ($Evidence) { $example.evidence = @($example.evidence) + $Evidence }
$example.status = $Status
$data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Manifest -Encoding utf8
& "$PSScriptRoot\validate-manifest.ps1" -Manifest $Manifest
