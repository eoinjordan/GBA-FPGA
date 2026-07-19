#!/usr/bin/env bash
set -euo pipefail
if [[ $# -lt 2 ]]; then
  echo "Usage: $0 GAME.sfc /path/to/sd [SNESTang-core.bin]" >&2
  exit 2
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
args=("$repo_root/scripts/prepare-snestang-sd.py" "$1" "$2")
if [[ $# -ge 3 ]]; then args+=(--core "$3"); fi
python3 "${args[@]}"
