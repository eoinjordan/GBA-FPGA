#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <project.gbsproj> <output.gba>" >&2
    exit 2
fi

command -v node >/dev/null 2>&1 || { echo "ERROR: Node.js 20 or newer is required" >&2; exit 1; }
command -v npm >/dev/null 2>&1 || { echo "ERROR: npm is required" >&2; exit 1; }

project="$(realpath "$1")"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
studio="$repo_root/external/GBA-Studio"

[[ -f "$project" ]] || { echo "ERROR: project not found: $project" >&2; exit 1; }
[[ -d "$studio/.git" ]] || { echo "ERROR: GBA-Studio is missing. Run scripts/bootstrap.sh." >&2; exit 1; }

output_dir="$(dirname "$2")"
mkdir -p "$output_dir"
output="$(cd "$output_dir" && pwd)/$(basename "$2")"

pushd "$studio" >/dev/null

if [[ ! -d node_modules ]]; then
    npm ci
fi

# GBA Studio's current documented build path requires fetched dependencies and
# the generated CLI bundle before invoking make:rom.
npm run fetch-deps
npm run make:cli
node out/cli/gb-studio-cli.js make:rom "$project" "$output"

popd >/dev/null

[[ -f "$output" ]] || { echo "ERROR: GBA Studio did not create $output" >&2; exit 1; }
echo "Created $output"
