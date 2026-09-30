#!/usr/bin/env python3
"""Check a Game Boy ROM against GBTang v1.0.0's limits (see tools/gb_rom.py).

Exit status: 0 compatible, 2 not compatible, 1 unreadable.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.gb_rom import inspect_rom  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Check a Game Boy ROM for GBTang on the Tang Nano 20K")
    parser.add_argument("rom", type=Path)
    parser.add_argument("--json", action="store_true", dest="as_json")
    args = parser.parse_args()
    try:
        report = inspect_rom(args.rom)
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if args.as_json:
        print(json.dumps(report.to_dict(), indent=2))
    else:
        print(f"Title: {report.title or '(blank)'}")
        print(f"Cartridge: {report.cartridge_name}, {report.file_size} bytes, colour: {report.color}")
        print(f"Header checksum: {'ok' if report.header_checksum_valid else 'BAD'}")
        print(f"SHA-256: {report.sha256}")
        print(f"GBTang compatible: {'yes' if report.gbtang_compatible else 'no'}")
        for warning in report.warnings:
            print(f"WARNING: {warning}")
    return 0 if report.gbtang_compatible else 2


if __name__ == "__main__":
    raise SystemExit(main())
