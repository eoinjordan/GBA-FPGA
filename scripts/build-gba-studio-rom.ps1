[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

foreach ($Tool in @('node', 'npm')) {
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "$Tool is required. Install Node.js 20 or newer before building GBA Studio ROMs."
    }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Studio = Join-Path $RepoRoot 'external\GBA-Studio'
$Project = (Resolve-Path $ProjectPath).Path
$Output = [System.IO.Path]::GetFullPath($OutputPath)
$OutputDirectory = Split-Path -Parent $Output

if (-not (Test-Path (Join-Path $Studio '.git'))) {
    throw 'GBA-Studio is missing. Run scripts\bootstrap.ps1.'
}

if ($OutputDirectory) {
    New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
}

Push-Location $Studio
try {
    if (-not (Test-Path (Join-Path $Studio 'node_modules'))) {
        & npm ci
        if ($LASTEXITCODE -ne 0) { throw 'npm ci failed.' }
    }

    & npm run fetch-deps
    if ($LASTEXITCODE -ne 0) { throw 'npm run fetch-deps failed.' }

    & npm run make:cli
    if ($LASTEXITCODE -ne 0) { throw 'npm run make:cli failed.' }

    & node out/cli/gb-studio-cli.js make:rom $Project $Output
    if ($LASTEXITCODE -ne 0) { throw 'GBA Studio make:rom failed.' }
}
finally {
    Pop-Location
}

if (-not (Test-Path $Output)) {
    throw "GBA Studio did not create $Output."
}

Write-Host "Created $Output"
