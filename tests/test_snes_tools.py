"""Tests for the SNES ROM inspection used by the SNESTang SD tooling."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.snes_rom import NANO20K_MAX_ROM_BYTES, inspect_rom


def make_rom(path: Path) -> None:
    data = bytearray([0xFF] * 0x8000)
    offset = 0x7FC0
    data[offset : offset + 21] = b"GBA SHAPED SNES TEST ".ljust(21, b" ")
    data[offset + 0x15] = 0x20
    data[offset + 0x17] = 0x05
    checksum = 0x4567
    data[offset + 0x1C : offset + 0x1E] = (checksum ^ 0xFFFF).to_bytes(2, "little")
    data[offset + 0x1E : offset + 0x20] = checksum.to_bytes(2, "little")
    data[offset + 0x3C : offset + 0x3E] = (0x8000).to_bytes(2, "little")
    path.write_bytes(data)


class SnesToolTests(unittest.TestCase):
    def test_inspect_lorom(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.sfc"
            make_rom(path)
            report = inspect_rom(path)
            self.assertEqual(report.mapping, "LoROM")
            self.assertTrue(report.nano20k_compatible)
            self.assertTrue(report.checksum_pair_valid)

    def test_limit(self) -> None:
        self.assertEqual(NANO20K_MAX_ROM_BYTES, 3_932_160)


if __name__ == "__main__":
    unittest.main()
