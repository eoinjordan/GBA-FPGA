#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT))

from tools.snes_rom import inspect_rom  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare a microSD card for a standalone SNESTang build")
    parser.add_argument("rom", type=Path)
    parser.add_argument("sd_root", type=Path)
    parser.add_argument("--rom-dir", default="games/snes")
    parser.add_argument("--core", type=Path)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    try:
        if not args.sd_root.is_dir():
            raise NotADirectoryError(args.sd_root)
        report = inspect_rom(args.rom)
        if not report.nano20k_compatible and not args.force:
            raise ValueError("ROM is not compatible with the Tang Nano 20K SNESTang size limit")

        rom_dir = args.sd_root / args.rom_dir
        cores_dir = args.sd_root / "cores"
        saves_dir = args.sd_root / "saves"
        rom_dir.mkdir(parents=True, exist_ok=True)
        cores_dir.mkdir(parents=True, exist_ok=True)
        saves_dir.mkdir(parents=True, exist_ok=True)
        destination = rom_dir / args.rom.name
        shutil.copy2(args.rom, destination)

        core_destination = None
        if args.core:
            if not args.core.is_file():
                raise FileNotFoundError(args.core)
            core_destination = cores_dir / args.core.name
            shutil.copy2(args.core, core_destination)

        manifest = {
            "schema": "gba-fpga/snestang-deployment/v1",
            "created_utc": datetime.now(timezone.utc).isoformat(),
            "target": "snestang-tang-nano-20k",
            "rom": {**report.to_dict(), "deployed_path": str(destination.relative_to(args.sd_root))},
            "core": str(core_destination.relative_to(args.sd_root)) if core_destination else None,
        }
        manifest_path = args.sd_root / "snes-handheld-manifest.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        print(f"Deployed {destination}")
        print(f"Wrote {manifest_path}")
        return 0
    except (OSError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
