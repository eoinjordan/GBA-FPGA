#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.snes_rom import NANO20K_MAX_ROM_BYTES, inspect_rom  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate an SNES ROM for SNESTang on Tang Nano 20K")
    parser.add_argument("rom", type=Path)
    parser.add_argument("--json", action="store_true", dest="as_json")
    parser.add_argument("--max-rom-bytes", type=int, default=NANO20K_MAX_ROM_BYTES)
    args = parser.parse_args()
    try:
        report = inspect_rom(args.rom, args.max_rom_bytes)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    data = report.to_dict()
    if args.as_json:
        print(json.dumps(data, indent=2))
    else:
        print(f"Title: {report.title or '(blank)'}")
        print(f"Mapping: {report.mapping}")
        print(f"Payload bytes: {report.payload_size}")
        print(f"SHA-256: {report.sha256}")
        print(f"Nano 20K budget used: {report.budget_used_percent:.2f}%")
        print(f"Nano 20K compatible: {'yes' if report.nano20k_compatible else 'no'}")
        for warning in report.warnings:
            print(f"WARNING: {warning}")
    return 0 if report.nano20k_compatible else 2


if __name__ == "__main__":
    raise SystemExit(main())
