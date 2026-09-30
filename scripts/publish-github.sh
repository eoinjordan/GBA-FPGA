#!/usr/bin/env bash
set -euo pipefail

owner="${1:-eoinjordan}"
repo="${2:-GBA-FPGA}"
visibility="${3:-public}"

if [[ "$visibility" != "public" && "$visibility" != "private" ]]; then
    echo "ERROR: visibility must be public or private" >&2
    exit 2
fi

command -v gh >/dev/null 2>&1 || { echo "ERROR: GitHub CLI 'gh' is required" >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

git rev-parse --is-inside-work-tree >/dev/null
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: commit or stash local changes before publishing" >&2
    exit 1
fi

if gh repo view "$owner/$repo" >/dev/null 2>&1; then
    echo "Repository $owner/$repo already exists; adding/updating origin."
    remote_url="https://github.com/$owner/$repo.git"
    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$remote_url"
    else
        git remote add origin "$remote_url"
    fi
else
    gh repo create "$owner/$repo" --"$visibility" --source . --remote origin
fi

git push -u origin HEAD:main
