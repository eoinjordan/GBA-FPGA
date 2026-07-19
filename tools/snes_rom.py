from __future__ import annotations

from dataclasses import asdict, dataclass
from hashlib import sha256
from pathlib import Path
from typing import Iterable

COPIER_HEADER_SIZE = 512
NANO20K_MAX_ROM_BYTES = int(3.75 * 1024 * 1024)


@dataclass(frozen=True)
class HeaderCandidate:
    mapping: str
    offset: int
    score: int
    title: str
    map_mode: int
    cartridge_type: int
    declared_rom_size: int
    declared_sram_size: int
    region: int
    version: int
    checksum_complement: int
    checksum: int
    reset_vector: int


@dataclass(frozen=True)
class RomReport:
    path: str
    file_size: int
    payload_size: int
    copier_header: bool
    sha256: str
    mapping: str
    title: str
    header_offset: int
    header_score: int
    map_mode: int
    cartridge_type: int
    declared_rom_size: int
    declared_sram_size: int
    region: int
    version: int
    checksum: int
    checksum_complement: int
    reset_vector: int
    checksum_pair_valid: bool
    nano20k_limit: int
    nano20k_compatible: bool
    budget_used_percent: float
    warnings: tuple[str, ...]

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def _u16le(data: bytes, offset: int) -> int:
    return data[offset] | (data[offset + 1] << 8)


def _printable_title(raw: bytes) -> tuple[str, int]:
    score = 0
    chars: list[str] = []
    for value in raw:
        if value in (0x00, 0x20) or 0x21 <= value <= 0x7E:
            score += 1
        chars.append(chr(value) if 0x20 <= value <= 0x7E else " ")
    return "".join(chars).rstrip(), score


def _candidate(data: bytes, mapping: str, offset: int) -> HeaderCandidate | None:
    # SNES internal header is 32 bytes; reset vector is in the vector table at +0x3C.
    if offset < 0 or offset + 0x3E > len(data):
        return None

    title, printable = _printable_title(data[offset : offset + 21])
    map_mode = data[offset + 0x15]
    cartridge_type = data[offset + 0x16]
    rom_exp = data[offset + 0x17]
    sram_exp = data[offset + 0x18]
    region = data[offset + 0x19]
    version = data[offset + 0x1B]
    complement = _u16le(data, offset + 0x1C)
    checksum = _u16le(data, offset + 0x1E)
    reset_vector = _u16le(data, offset + 0x3C)

    score = printable
    if (checksum ^ complement) == 0xFFFF and checksum not in (0x0000, 0xFFFF):
        score += 12
    if reset_vector >= 0x8000:
        score += 8
    if map_mode & 0x0F in {0x0, 0x1, 0x2, 0x3, 0x5, 0xA}:
        score += 4
    if rom_exp <= 0x0D:
        score += 2
    if sram_exp <= 0x0D:
        score += 1
    if title:
        score += 2

    declared_rom_size = 0 if rom_exp == 0 else 1 << (rom_exp + 10)
    declared_sram_size = 0 if sram_exp == 0 else 1 << (sram_exp + 10)

    return HeaderCandidate(
        mapping=mapping,
        offset=offset,
        score=score,
        title=title,
        map_mode=map_mode,
        cartridge_type=cartridge_type,
        declared_rom_size=declared_rom_size,
        declared_sram_size=declared_sram_size,
        region=region,
        version=version,
        checksum_complement=complement,
        checksum=checksum,
        reset_vector=reset_vector,
    )


def candidate_headers(data: bytes) -> Iterable[HeaderCandidate]:
    candidates = (
        ("LoROM", 0x7FC0),
        ("HiROM", 0xFFC0),
        ("ExHiROM", 0x40FFC0),
    )
    for mapping, offset in candidates:
        candidate = _candidate(data, mapping, offset)
        if candidate is not None:
            yield candidate


def inspect_rom(path: str | Path, max_rom_bytes: int = NANO20K_MAX_ROM_BYTES) -> RomReport:
    rom_path = Path(path)
    raw = rom_path.read_bytes()
    has_copier_header = len(raw) >= COPIER_HEADER_SIZE and len(raw) % 1024 == COPIER_HEADER_SIZE
    payload = raw[COPIER_HEADER_SIZE:] if has_copier_header else raw

    candidates = list(candidate_headers(payload))
    if not candidates:
        raise ValueError("ROM is too small to contain a standard SNES internal header")
    best = max(candidates, key=lambda item: item.score)

    warnings: list[str] = []
    checksum_pair_valid = (best.checksum ^ best.checksum_complement) == 0xFFFF
    if not checksum_pair_valid:
        warnings.append("Internal checksum and complement do not form 0xFFFF")
    if best.reset_vector < 0x8000:
        warnings.append("Reset vector is outside the normal cartridge ROM window")
    if best.score < 35:
        warnings.append("Header confidence is low; verify the ROM in bsnes, Mesen-S or Snes9x")
    if has_copier_header:
        warnings.append("A 512-byte copier header is present; SNESTang compatibility may be better after stripping it")
    if len(payload) >= max_rom_bytes:
        warnings.append(f"ROM payload is not smaller than the Nano 20K limit of {max_rom_bytes} bytes")
    if best.declared_rom_size and best.declared_rom_size < len(payload) // 2:
        warnings.append("Declared ROM size is much smaller than the file payload")

    return RomReport(
        path=str(rom_path),
        file_size=len(raw),
        payload_size=len(payload),
        copier_header=has_copier_header,
        sha256=sha256(raw).hexdigest(),
        mapping=best.mapping,
        title=best.title,
        header_offset=best.offset,
        header_score=best.score,
        map_mode=best.map_mode,
        cartridge_type=best.cartridge_type,
        declared_rom_size=best.declared_rom_size,
        declared_sram_size=best.declared_sram_size,
        region=best.region,
        version=best.version,
        checksum=best.checksum,
        checksum_complement=best.checksum_complement,
        reset_vector=best.reset_vector,
        checksum_pair_valid=checksum_pair_valid,
        nano20k_limit=max_rom_bytes,
        nano20k_compatible=len(payload) < max_rom_bytes,
        budget_used_percent=round((len(payload) / max_rom_bytes) * 100.0, 2),
        warnings=tuple(warnings),
    )
