#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$repo_root/UPSTREAMS.json"
external="$repo_root/external"

command -v git >/dev/null 2>&1 || { echo "ERROR: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 1; }
mkdir -p "$external"

python3 - "$manifest" <<'PY2' | while IFS=$'\t' read -r name url path; do
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as handle:
    data = json.load(handle)
for project in data['projects']:
    print(f"{project['name']}\t{project['url']}\t{project['path']}")
PY2
    target="$repo_root/$path"
    if [[ -d "$target/.git" ]]; then
        echo "Updating $name"
        git -C "$target" pull --ff-only
        git -C "$target" submodule update --init --recursive --depth 1
    elif [[ -e "$target" ]]; then
        echo "ERROR: $target exists but is not a Git checkout" >&2
        exit 1
    else
        echo "Cloning $name"
        git clone --depth 1 --recurse-submodules --shallow-submodules "$url" "$target"
    fi
done

echo "Bootstrap complete. Upstream source is under $external"
