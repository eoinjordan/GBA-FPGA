#!/usr/bin/env bash
set -euo pipefail

required=(git python3 iverilog vvp ghdl)
optional=(node npm gowin_sh gw_sh gh)
failed=0

for tool in "${required[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK       %s\n' "$tool"
    else
        printf 'MISSING  %s (required)\n' "$tool"
        failed=1
    fi
done

for tool in "${optional[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        printf 'OK       %s\n' "$tool"
    else
        printf 'OPTIONAL %s\n' "$tool"
    fi
done

if [[ $failed -ne 0 ]]; then
    exit 1
fi
