"""Tests for the Game Boy ROM checks used by the GBTang SD tooling."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from tools.gb_rom import GBTANG_MAX_ROM_BYTES, header_checksum, inspect_rom


def make_rom(path: Path, *, cart_type: int = 0x00, color: int = 0x00, rom_size_code: int = 0,
             size: int = 32 * 1024, corrupt_checksum: bool = False) -> None:
    """Synthetic ROM: only the header fields the checker reads are filled in."""
    data = bytearray(size)
    data[0x134:0x134 + 11] = b"GBA FPGA TS"
    data[0x143] = color
    data[0x147] = cart_type
    data[0x148] = rom_size_code
    data[0x14D] = header_checksum(bytes(data)) ^ (0xFF if corrupt_checksum else 0x00)
    path.write_bytes(bytes(data))


class GbRomTests(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.dir = Path(self._dir.name)

    def tearDown(self) -> None:
        self._dir.cleanup()

    def test_rom_only_is_compatible(self) -> None:
        path = self.dir / "demo.gb"
        make_rom(path)
        report = inspect_rom(path)
        self.assertEqual(report.title, "GBA FPGA TS")
        self.assertEqual(report.cartridge_name, "ROM ONLY")
        self.assertTrue(report.header_checksum_valid)
        self.assertTrue(report.gbtang_compatible)
        self.assertEqual(report.warnings, ())

    def test_color_only_is_rejected(self) -> None:
        path = self.dir / "color.gbc"
        make_rom(path, color=0xC0, cart_type=0x19)
        report = inspect_rom(path)
        self.assertEqual(report.color, "cgb-only")
        self.assertFalse(report.gbtang_compatible)

    def test_color_enhanced_runs_in_dmg_mode(self) -> None:
        path = self.dir / "dual.gbc"
        make_rom(path, color=0x80, cart_type=0x1B)
        report = inspect_rom(path)
        self.assertTrue(report.gbtang_compatible)
        self.assertTrue(any("monochrome" in w for w in report.warnings))
        self.assertTrue(any("battery" in w for w in report.warnings))

    def test_unsupported_mapper_and_bad_checksum(self) -> None:
        path = self.dir / "mbc2.gb"
        make_rom(path, cart_type=0x05, corrupt_checksum=True)
        report = inspect_rom(path)
        self.assertFalse(report.gbtang_compatible)
        self.assertFalse(report.header_checksum_valid)

    def test_large_mbc1_warns(self) -> None:
        path = self.dir / "big.gb"
        make_rom(path, cart_type=0x01, rom_size_code=5, size=1024 * 1024)
        report = inspect_rom(path)
        self.assertTrue(report.gbtang_compatible)
        self.assertTrue(any("512 KiB" in w for w in report.warnings))

    def test_limit_constant(self) -> None:
        self.assertEqual(GBTANG_MAX_ROM_BYTES, 4 * 1024 * 1024)


if __name__ == "__main__":
    unittest.main()
