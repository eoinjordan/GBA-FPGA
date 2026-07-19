[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ManifestPath = Join-Path $RepoRoot 'UPSTREAMS.json'

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'git is required.'
}

$Manifest = Get-Content -Raw -Path $ManifestPath | ConvertFrom-Json
foreach ($Project in $Manifest.projects) {
    $Target = Join-Path $RepoRoot $Project.path
    if (Test-Path (Join-Path $Target '.git')) {
        Write-Host "Updating $($Project.name)"
        & git -C $Target pull --ff-only
        if ($LASTEXITCODE -ne 0) { throw "Failed to update $($Project.name)." }
        & git -C $Target submodule update --init --recursive --depth 1
        if ($LASTEXITCODE -ne 0) { throw "Failed to update submodules for $($Project.name)." }
    }
    elseif (Test-Path $Target) {
        throw "$Target exists but is not a Git checkout."
    }
    else {
        Write-Host "Cloning $($Project.name)"
        & git clone --depth 1 --recurse-submodules --shallow-submodules $Project.url $Target
        if ($LASTEXITCODE -ne 0) { throw "Failed to clone $($Project.name)." }
    }
}

Write-Host 'Bootstrap complete.'
