[CmdletBinding()]
param([string] $OutputRoot = '.deps\chapter-21-packages')

$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$absoluteOutput=[IO.Path]::GetFullPath((Join-Path $root $OutputRoot))
New-Item -ItemType Directory -Force $absoluteOutput|Out-Null
$manifest=[System.Collections.Generic.List[object]]::new()
foreach($arch in @('Win32','Win64')){
  $package=Join-Path $absoluteOutput $arch
  New-Item -ItemType Directory -Force $package|Out-Null
  New-Item -ItemType Directory -Force (Join-Path $package 'plugins')|Out-Null
  New-Item -ItemType Directory -Force (Join-Path $package 'licenses')|Out-Null
  $sources=@(
    @{Source=(Join-Path $root ".deps\build\$arch\chapter-21\Chapter21Checks.exe");Target='Chapter21Checks.exe';License='Book example / Apache-2.0'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\fbclient.dll");Target='fbclient.dll';License='Firebird IPL/IDPL'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\msvcp140.dll");Target='msvcp140.dll';License='Microsoft Visual C++ Runtime'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\msvcp140_1.dll");Target='msvcp140_1.dll';License='Microsoft Visual C++ Runtime'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\vcruntime140.dll");Target='vcruntime140.dll';License='Microsoft Visual C++ Runtime'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\zlib1.dll");Target='zlib1.dll';License='zlib'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\plugins\chacha.dll");Target='plugins/chacha.dll';License='Firebird IPL/IDPL'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\IPLicense.txt");Target='licenses/IPLicense.txt';License='IPL'},
    @{Source=(Join-Path $root ".deps\firebird\$arch\IDPLicense.txt");Target='licenses/IDPLicense.txt';License='IDPL'}
  )
  foreach($item in $sources){
    if(!(Test-Path -LiteralPath $item.Source)){throw "Dependência ausente: $($item.Source)"}
    $dest=Join-Path $package $item.Target
    Copy-Item -LiteralPath $item.Source -Destination $dest -Force
    $hash=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest.Add([ordered]@{architecture=$arch;file=$item.Target.Replace('\','/');sha256=$hash;bytes=(Get-Item $dest).Length;license=$item.License})
  }
}
$manifest|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'chapters\chapter-21\evidence\deployment-manifest.json') -Encoding utf8
Write-Output "Pacotes montados em $absoluteOutput; manifesto público atualizado."
