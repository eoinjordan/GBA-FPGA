# GBA-FPGA

A hardware and software integration workbench for a **GBA-shaped FPGA handheld**. The project now covers the practical systems available across the Tang board family rather than pretending that every core fits the Tang Nano 20K.

```text
Tang Nano 20K
  |-- GBTang   -> Game Boy / Game Boy Color
  `-- SNESTang -> SNES homebrew below the Nano ROM-size limit

Tang 60K class
  `-- GBATang  -> Game Boy Advance
```

The companion game-tool workflow is:

```text
SNES Studio -> PVSnesLib -> .sfc -> SNESTang
GBA Studio  -> GBA Engine/devkitARM -> .gba -> GBATang
```

## Best-value path

The highest-value immediate milestone is an original SNES Studio game running on SNESTang using the Tang Nano 20K already owned. In parallel, GBA Studio should produce a known-good `.gba` in mGBA so that a future 60K board purchase has a validated software target.

## Hardware decision

| Target | Recommended use | Status |
|---|---|---|
| Tang Nano 20K + SNESTang | GBA-shaped SNES handheld | Practical; ROM payload must be smaller than 3.75 MiB |
| Tang Nano 20K + GBTang | GB/GBC handheld | Practical |
| Tang Mega/Console 60K + GBATang | GBA handheld | Practical GBA path |
| FPGBA on Tang 60K | Research port | Integration scaffold only |
| FPGBA on Tang Nano 20K | Full GBA implementation | Rejected as a best-value route |

## Included

- SNESTang Nano 20K ROM inspection, budget validation and SD deployment scripts.
- GBTang and GBATang integration documentation.
- A synthesizable ROM-only GBA cartridge reader and self-checking testbench.
- 480x272 timing/mapping experiments that remain blocked on the exact panel datasheet.
- Button debounce and active-low input mapping.
- Four-face-button SNES control specification.
- FPGBA Tang 60K platform scaffold.
- Linux and Windows scripts for upstream checkout, GBA Studio builds and SD preparation.
- CI tests and repository checks that reject ROM/BIOS artifacts.

## SNES quick start

Validate a homebrew ROM:

```bash
python3 scripts/validate-snes-rom.py build/my-game.sfc
```

Prepare an SD card:

```bash
python3 scripts/prepare-snestang-sd.py build/my-game.sfc /media/$USER/SNESTANG_SD
```

Optionally copy a standalone core binary:

```bash
python3 scripts/prepare-snestang-sd.py build/my-game.sfc /media/$USER/SNESTANG_SD \
  --core /path/to/snestang-nano20k.bin
```

The default ROM directory is `games/snes`. Override it for a particular upstream release:

```bash
python3 scripts/prepare-snestang-sd.py build/my-game.sfc /media/$USER/SNESTANG_SD \
  --rom-dir snes
```

## GBA Studio quick start

```bash
./scripts/bootstrap.sh
./scripts/verify.sh
./scripts/build-gba-studio-rom.sh /path/to/project.gbsproj build/my-game.gba
```

Validate the ROM in mGBA before testing it on GBATang 60K hardware.

## Tests

The HDL suite requires Icarus Verilog and GHDL:

```bash
make test
```

The SNES tools can be tested independently:

```bash
python3 -m unittest discover -s tests -v
```

## Controls

A normal GBA front PCB has only A and B. SNES requires A, B, X and Y, so the handheld front and PCB must use a four-button diamond. D-pad, L/R, Start and Select remain reusable for the later GBA configuration. Keep Menu/OSD as a separate input.

## Display

Use HDMI for the first SNESTang prototype. Do not wire the ordered raw 480x272 panel until its exact controller, FPC pinout, I/O voltage, timing and backlight requirements are confirmed.

## Repository status

This is an integration workbench. It does not claim a completed FPGBA Gowin bitstream, vendor SNESTang/GBTang/GBATang source, or include Nintendo firmware or commercial game ROMs.

## Publish

```bash
./scripts/publish-github.sh eoinjordan GBA-FPGA public
```

```powershell
.\scripts\publish-github.ps1 -Owner eoinjordan -Repository GBA-FPGA -Visibility public
```

## Licence

Original integration material is GPL-2.0-or-later. Upstream repositories retain their own licences.
