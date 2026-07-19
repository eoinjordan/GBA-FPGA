[CmdletBinding()]
param(
    [string]$Owner = 'eoinjordan',
    [string]$Repository = 'GBA-FPGA',
    [ValidateSet('public', 'private')]
    [string]$Visibility = 'public'
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    throw "GitHub CLI 'gh' is required."
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Push-Location $RepoRoot
try {
    & git rev-parse --is-inside-work-tree | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Not a Git working tree.' }

    $Dirty = (& git status --porcelain)
    if ($Dirty) { throw 'Commit or stash local changes before publishing.' }

    & gh repo view "$Owner/$Repository" *> $null
    if ($LASTEXITCODE -eq 0) {
        $RemoteUrl = "https://github.com/$Owner/$Repository.git"
        & git remote get-url origin *> $null
        if ($LASTEXITCODE -eq 0) {
            & git remote set-url origin $RemoteUrl
        }
        else {
            & git remote add origin $RemoteUrl
        }
    }
    else {
        & gh repo create "$Owner/$Repository" "--$Visibility" --source . --remote origin
        if ($LASTEXITCODE -ne 0) { throw 'Failed to create GitHub repository.' }
    }

    & git push -u origin HEAD:main
    if ($LASTEXITCODE -ne 0) { throw 'Failed to push repository.' }
}
finally {
    Pop-Location
}
