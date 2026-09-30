"""Game Boy ROM header checks for GBTang v1.0.0 on the Tang Nano 20K.

Reads only the cartridge header fields at 0x134-0x14F (title, Color flag,
cartridge type, sizes, header checksum). The Nintendo logo bytes at
0x104-0x133 are neither read nor stored here.

GBTang v1.0.0 limits, taken from its source:
  * VerilogBoy core: original Game Boy (DMG) only, no Game Boy Color mode.
  * One MBC5-style mapper for every cartridge: 8-bit ROM bank register
    (bank 0 selects 1), 4-bit RAM bank, no MBC1 mode register, no MBC3 clock.
  * ROM is mapped into the first 4 MiB of SDRAM.
  * Cartridge-RAM backup is not wired (bk_save = 0): battery saves are lost
    at power-off.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
from pathlib import Path
from typing import Tuple

HEADER_END = 0x150
GBTANG_MAX_ROM_BYTES = 4 * 1024 * 1024

# Cartridge type byte (0x147) -> name.
CARTRIDGE_TYPES = {
    0x00: "ROM ONLY", 0x01: "MBC1", 0x02: "MBC1+RAM", 0x03: "MBC1+RAM+BATTERY",
    0x05: "MBC2", 0x06: "MBC2+BATTERY", 0x08: "ROM+RAM", 0x09: "ROM+RAM+BATTERY",
    0x0B: "MMM01", 0x0C: "MMM01+RAM", 0x0D: "MMM01+RAM+BATTERY",
    0x0F: "MBC3+TIMER+BATTERY", 0x10: "MBC3+TIMER+RAM+BATTERY", 0x11: "MBC3",
    0x12: "MBC3+RAM", 0x13: "MBC3+RAM+BATTERY", 0x19: "MBC5", 0x1A: "MBC5+RAM",
    0x1B: "MBC5+RAM+BATTERY", 0x1C: "MBC5+RUMBLE", 0x1D: "MBC5+RUMBLE+RAM",
    0x1E: "MBC5+RUMBLE+RAM+BATTERY", 0x20: "MBC6", 0x22: "MBC7+SENSOR+RUMBLE+RAM+BATTERY",
    0xFC: "POCKET CAMERA", 0xFD: "BANDAI TAMA5", 0xFE: "HuC3", 0xFF: "HuC1+RAM+BATTERY",
}

# RAM size byte (0x149) -> bytes.
RAM_SIZES = {0x00: 0, 0x01: 2 * 1024, 0x02: 8 * 1024, 0x03: 32 * 1024, 0x04: 128 * 1024, 0x05: 64 * 1024}


@dataclass(frozen=True)
class GbRomReport:
    path: str
    file_size: int
    sha256: str
    title: str
    color: str                 # "dmg", "cgb-enhanced" or "cgb-only"
    cartridge_type: int
    cartridge_name: str
    declared_rom_size: int
    declared_ram_size: int
    header_checksum: int
    header_checksum_valid: bool
    gbtang_compatible: bool
    warnings: Tuple[str, ...]

    def to_dict(self) -> dict:
        return asdict(self)


def header_checksum(data: bytes) -> int:
    """The value the boot ROM compares with byte 0x14D."""
    value = 0
    for byte in data[0x134:0x14D]:
        value = (value - byte - 1) & 0xFF
    return value


def _title(raw: bytes) -> str:
    text = raw.split(b"\x00", 1)[0]
    return "".join(chr(b) if 0x20 <= b <= 0x7E else " " for b in text).strip()


def inspect_rom(path: str | Path) -> GbRomReport:
    rom_path = Path(path)
    data = rom_path.read_bytes()
    if len(data) < HEADER_END:
        raise ValueError("file is too small to contain a Game Boy cartridge header")

    color_flag = data[0x143]
    color = "cgb-only" if color_flag == 0xC0 else ("cgb-enhanced" if color_flag == 0x80 else "dmg")
    title = _title(data[0x134:0x143] if color_flag in (0x80, 0xC0) else data[0x134:0x144])
    cart_type = data[0x147]
    cart_name = CARTRIDGE_TYPES.get(cart_type, f"unknown (0x{cart_type:02X})")
    rom_size = (32 * 1024) << data[0x148] if data[0x148] <= 8 else 0
    ram_size = RAM_SIZES.get(data[0x149], 0)
    checksum_ok = header_checksum(data) == data[0x14D]

    warnings = []
    compatible = True
    if color == "cgb-only":
        compatible = False
        warnings.append("Game Boy Color only: GBTang's VerilogBoy core runs original Game Boy software only")
    elif color == "cgb-enhanced":
        warnings.append("Game Boy Color enhanced: runs in original Game Boy (monochrome) mode")
    if len(data) > GBTANG_MAX_ROM_BYTES:
        compatible = False
        warnings.append(f"larger than the {GBTANG_MAX_ROM_BYTES // (1024 * 1024)} MiB GBTang maps into SDRAM")
    if cart_name.startswith("MBC1") and len(data) > 512 * 1024:
        warnings.append("MBC1 ROM over 512 KiB: needs MBC1 upper-bank switching, which GBTang's mapper lacks")
    elif cart_name.startswith("MBC3+TIMER"):
        warnings.append("MBC3 real-time clock is not implemented; clock features will not work")
    elif not (cart_name.startswith(("ROM", "MBC1", "MBC3", "MBC5"))):
        compatible = False
        warnings.append(f"{cart_name} cartridges are not supported by GBTang's MBC5-style mapper")
    if "BATTERY" in cart_name:
        warnings.append("battery save: GBTang v1.0.0 does not back up cartridge RAM, saves are lost at power-off")
    if not checksum_ok:
        warnings.append("header checksum does not match byte 0x14D: the file may be corrupt or not a ROM")
    if rom_size and rom_size != len(data):
        warnings.append(f"header declares {rom_size} bytes, file has {len(data)}")

    return GbRomReport(
        path=str(rom_path),
        file_size=len(data),
        sha256=sha256(data).hexdigest(),
        title=title,
        color=color,
        cartridge_type=cart_type,
        cartridge_name=cart_name,
        declared_rom_size=rom_size,
        declared_ram_size=ram_size,
        header_checksum=data[0x14D],
        header_checksum_valid=checksum_ok,
        gbtang_compatible=compatible,
        warnings=tuple(warnings),
    )
