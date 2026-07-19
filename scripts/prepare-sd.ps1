[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RomPath,

    [Parameter(Mandatory = $true)]
    [string]$SdRoot
)

$ErrorActionPreference = 'Stop'
$Rom = (Resolve-Path $RomPath).Path
$Root = (Resolve-Path $SdRoot).Path

$Directories = @(
    (Join-Path $Root 'roms\gba'),
    (Join-Path $Root 'saves'),
    (Join-Path $Root 'homebrew')
)

foreach ($Directory in $Directories) {
    New-Item -ItemType Directory -Force -Path $Directory | Out-Null
}

Copy-Item -Force -Path $Rom -Destination (Join-Path $Root 'homebrew')
Write-Host "Copied $(Split-Path -Leaf $Rom) to $(Join-Path $Root 'homebrew')"
Write-Host 'Check the current GBATang/TangCore menu documentation before renaming directories.'
