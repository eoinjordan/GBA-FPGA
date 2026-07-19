#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <rom.gba> <mounted-sd-root>" >&2
    exit 2
fi

rom="$(realpath "$1")"
sd_root="$(realpath "$2")"
[[ -f "$rom" ]] || { echo "ERROR: ROM not found: $rom" >&2; exit 1; }
[[ -d "$sd_root" ]] || { echo "ERROR: SD root not found: $sd_root" >&2; exit 1; }

mkdir -p "$sd_root/roms/gba" "$sd_root/saves" "$sd_root/homebrew"
cp -f "$rom" "$sd_root/homebrew/"
sync

echo "Copied $(basename "$rom") to $sd_root/homebrew"
echo "Check the current GBATang/TangCore menu documentation before renaming directories."
