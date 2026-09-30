#!/usr/bin/env python3
"""Copy Game Boy ROMs to a microSD card for GBTang on the Tang Nano 20K.

Each ROM is checked first (tools/gb_rom.py); incompatible ROMs are skipped
unless --force is given. The card needs a FAT32 or exFAT file system; the
GBTang menu browses folders, so the default gb/ folder is only a convention.
A manifest (gbtang-manifest.json) records what was copied and its SHA-256.
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.gb_rom import inspect_rom  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare a microSD card for GBTang (Tang Nano 20K)")
    parser.add_argument("roms", type=Path, nargs="+", help=".gb / .gbc files")
    parser.add_argument("sd_root", type=Path, help="mounted SD card, e.g. /Volumes/SD, /media/$USER/SD, E:\\")
    parser.add_argument("--rom-dir", default="gb", help="folder on the card (default: gb)")
    parser.add_argument("--force", action="store_true", help="copy ROMs that fail the compatibility check")
    args = parser.parse_args()

    if not args.sd_root.is_dir():
        print(f"ERROR: {args.sd_root} is not a directory", file=sys.stderr)
        return 1

    rom_dir = args.sd_root / args.rom_dir
    rom_dir.mkdir(parents=True, exist_ok=True)
    copied, skipped = [], []
    for rom in args.roms:
        try:
            report = inspect_rom(rom)
        except (OSError, ValueError) as exc:
            print(f"skip  {rom}: {exc}")
            skipped.append(str(rom))
            continue
        for warning in report.warnings:
            print(f"      {rom.name}: {warning}")
        if not report.gbtang_compatible and not args.force:
            print(f"skip  {rom.name} (not compatible; --force to copy anyway)")
            skipped.append(str(rom))
            continue
        destination = rom_dir / rom.name
        shutil.copy2(rom, destination)
        print(f"copy  {rom.name} -> {destination}")
        copied.append({**report.to_dict(), "deployed_path": str(destination.relative_to(args.sd_root))})

    manifest = {
        "schema": "gba-fpga/gbtang-deployment/v1",
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "target": "gbtang-v1.0.0-tang-nano-20k",
        "roms": copied,
        "skipped": skipped,
    }
    manifest_path = args.sd_root / "gbtang-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {manifest_path}; {len(copied)} copied, {len(skipped)} skipped")
    return 0 if copied else 1


if __name__ == "__main__":
    raise SystemExit(main())
