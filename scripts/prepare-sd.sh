#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <rom.gba> <mounted-sd-root>" >&2
    exit 2
fi

[[ -f "$1" ]] || { echo "ERROR: ROM not found: $1" >&2; exit 1; }
[[ -d "$2" ]] || { echo "ERROR: SD root not found: $2" >&2; exit 1; }
# Absolute paths without realpath (missing on older macOS).
rom="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
sd_root="$(cd "$2" && pwd)"

mkdir -p "$sd_root/roms/gba" "$sd_root/saves" "$sd_root/homebrew"
cp -f "$rom" "$sd_root/homebrew/"
sync

echo "Copied $(basename "$rom") to $sd_root/homebrew"
echo "Check the current GBATang/TangCore menu documentation before renaming directories."
