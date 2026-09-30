# GBA-FPGA

FPGA work towards a GBA-shaped handheld on Sipeed Tang boards.

For the Tang Nano 20K, this repository provides:

- **gba_lcd_480x272**: a test design for the 4.3" 480x272 LCD
  (HT043IBB-16A3047-H4) that exercises this repository's display, input and
  UART RTL, with a checklist for the board;
- **GBTang** (Game Boy) and **SNESTang** (SNES): pinned upstream versions with
  Gowin IDE projects, build and flash commands, and ROM/SD-card tools.
- **gbtang_lcd**: Game Boy LCD target with CRC-checked ROM loading over USB
  UART. See [its build and controls](tangnano20k/gbtang_lcd/README.md).
- **studio_lcd**: native GBA Studio/GBA-engine games with a RISC-V CPU,
  hardware tiles/sprites and USB loading. See [the Studio flow](tangnano20k/studio_lcd/README.md).

The available complete GBA core targets Tang 60K-class boards with GBATang; see
[docs/BOARD_MATRIX.md](docs/BOARD_MATRIX.md).

## Quick start

Install the tools for your OS ([docs/TOOLCHAIN.md](docs/TOOLCHAIN.md)), then
from the repository root:

```bash
python3 scripts/gbafpga.py doctor                        # what is installed, what this machine can do
python3 scripts/gbafpga.py test                          # all testbenches and Python tests

python3 scripts/gbafpga.py build gba_lcd_480x272         # LCD test design
python3 scripts/gbafpga.py flash gba_lcd_480x272 --sram

python3 scripts/gbafpga.py fetch gbtang                  # Game Boy: release bitstream + firmware
python3 scripts/gbafpga.py flash gbtang
python3 scripts/prepare-gbtang-sd.py game.gb /path/to/sdcard
```

On Windows, run `.\scripts\gbafpga.ps1` wherever this README says
`python3 scripts/gbafpga.py`. `make test`, `make lint`, `make tangnano20k` and
`make flash` do the same where make is installed.

The Tang Nano 20K projects, board notes and pin tables are in
[tangnano20k/](tangnano20k/README.md).

## Commands

| Command | What it does |
|---|---|
| `doctor` | Lists tools found (OSS CAD Suite, Gowin EDA, programmers) and what each project can do here |
| `bootstrap [NAME ...]` | Clones upstream projects into `external/` at the versions pinned in `UPSTREAMS.json` (`bootstrap gbtang snestang` for the Nano 20K cores) |
| `test [--require-ghdl]` | Runs every testbench and the Python unit tests |
| `lint` | Verilator `-Wall` lint of the synthesizable RTL |
| `build PROJECT [--flow open\|gowin]` | Builds a Tang Nano 20K bitstream into `build/tangnano20k/PROJECT/` |
| `fetch gbtang\|snestang` | Downloads the pinned release bitstream and menu firmware, with size/checksum checks |
| `flash PROJECT [--sram] [--no-firmware] [--dry-run]` | Programs the board with openFPGALoader or Gowin's programmer, using the newest bitstream from `build`, a Gowin IDE build or `fetch`; `--dry-run` shows the files and commands |
| `ide-project gbtang\|snestang` | Regenerates the Gowin IDE project from the upstream `build.tcl` |

Projects: `gba_lcd_480x272`, `gbtang`, `snestang`.

## Tests

`test` runs seven Icarus Verilog testbenches and the Python tests:

| Testbench | Checks |
|---|---|
| `rgb_lcd_timing` | Measures Th, Thw, Thbp, Thfp and the vertical equivalents from the pins, for three panel profiles |
| `gba_to_480x272_mapper` | All 130,560 panel pixels against true division; every GBA pixel shown 1-2 times |
| `gba_test_pattern` | Each pattern's colours; sprite bounces inside the frame |
| `gba_buttons` | Bounce and one-clock glitches rejected, both pin polarities |
| `uart_tx` | 8N1 framing, back-to-back bytes |
| `gba_cart_rom_reader` | No bus contention, no write strobes, correct data |
| `tangnano20k gba_lcd_top` | Whole board design from power-up: two frames pixel-exact at the panel pins, S1 pattern change, LEDs, decoded UART line |

The VHDL scaffold test under `ports/fpgba-tang60k` runs when GHDL is installed.
CI runs the tests on Linux and macOS, lints the RTL and builds the
gba_lcd_480x272 bitstream with OSS CAD Suite (downloadable from the run).

## Layout

```text
rtl/           reusable RTL: video timing, GBA-to-480x272 scaler, test pattern,
               buttons, UART, reset, ROM-only cartridge reader (+ testbenches)
tangnano20k/   Tang Nano 20K projects: gba_lcd_480x272, gbtang, snestang
ports/         other boards: FPGBA Tang 60K scaffold, GBATang notes
scripts/       gbafpga.py, ROM and SD-card tools, .sh/.ps1 launchers
tools/         SNES and Game Boy ROM header parsers used by the scripts
tests/         Python unit tests
docs/          design notes and hardware documentation
hardware/      cartridge pinout, reader BOM, button map, wiring template
external/      upstream checkouts made by bootstrap (not committed)
```

## Other workflows

SNES Studio games (PVSnesLib `.sfc`) for SNESTang:

```bash
python3 scripts/validate-snes-rom.py build/my-game.sfc
python3 scripts/prepare-snestang-sd.py build/my-game.sfc /path/to/sdcard
```

GBA Studio games (`.gba`, for mGBA or GBATang on a 60K board) after
`bootstrap gba-studio`:

```bash
./scripts/build-gba-studio-rom.sh /path/to/project.gbsproj build/my-game.gba
```

See [docs/GBA_STUDIO.md](docs/GBA_STUDIO.md) and [docs/SNES_NANO20K.md](docs/SNES_NANO20K.md).

## Status

- gba_lcd_480x272: passes simulation and builds with the open-source tools
  (about 1,080 LUT4, timing met with a wide margin). Not yet run on hardware;
  the Gowin IDE build is untested.
- GBTang and SNESTang: upstream code at pinned versions; this repository adds
  the tooling, IDE projects and ROM checks.
- GBA on the Nano 20K: not feasible with the available cores.
- Cartridge reader: ROM-only and simulation-only.

No BIOS images, commercial ROMs or bitstreams are committed; CI rejects them.

## Licence

Original material is GPL-2.0-or-later. Upstream projects keep their own
licences; see [NOTICE.md](NOTICE.md).
