"""Tests for how `gbafpga.py flash` finds bitstreams and firmware."""

from __future__ import annotations

import importlib.util
import os
import tempfile
import time
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
_spec = importlib.util.spec_from_file_location("gbafpga", REPO / "scripts" / "gbafpga.py")
gbafpga = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gbafpga)


class FlashFileTests(unittest.TestCase):
    def test_local_project_includes_ide_output(self) -> None:
        candidates = gbafpga._bitstream_candidates("gba_lcd_480x272")
        self.assertIn(REPO / "build" / "tangnano20k" / "gba_lcd_480x272" / "gba_lcd_480x272.fs", candidates)
        self.assertIn(REPO / "tangnano20k" / "gba_lcd_480x272" / "impl" / "pnr" / "gba_lcd_480x272.fs",
                      candidates)

    def test_upstream_projects_cover_every_route(self) -> None:
        for project, name in (("gbtang", "gbtang_nano20k.fs"), ("snestang", "snestang_nano20k.fs")):
            candidates = [str(p) for p in gbafpga._bitstream_candidates(project)]
            self.assertTrue(any(c.endswith(os.path.join("impl", "pnr", name)) for c in candidates))
            self.assertTrue(any(c.endswith(os.path.join("release", name)) for c in candidates))

    def test_gbtang_firmware_found_in_checkout(self) -> None:
        paths = [str(p) for p in gbafpga._firmware_candidates("gbtang")]
        self.assertTrue(any(p.endswith(os.path.join("OSTang", "firmware", "firmware.bin")) for p in paths))
        self.assertEqual(gbafpga._firmware_candidates("gba_lcd_480x272"), [])

    def test_newest_file_wins(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            older, newer, missing = (Path(directory) / n for n in ("a.fs", "b.fs", "c.fs"))
            older.write_bytes(b"old")
            newer.write_bytes(b"new")
            past = time.time() - 60
            os.utime(older, (past, past))
            self.assertEqual(gbafpga._newest([older, newer, missing]), newer)
            self.assertIsNone(gbafpga._newest([missing]))


if __name__ == "__main__":
    unittest.main()
