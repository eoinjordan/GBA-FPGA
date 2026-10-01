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

## Nano 20K capacity and hardware results

Studio and Game Boy games have run on the Nano 20K with the 4.3" 480x272
RGB LCD. These capacity figures come from the 1 October 2026 Gowin
V1.9.12.04 place-and-route reports. Percentages retain Gowin's reported values.
See the [hardware report](docs/NANO20K_HARDWARE_REPORT.md) for timing paths,
warning analysis, power assumptions and build hashes.

| Resource | Studio LCD | Game Boy LCD |
|---|---:|---:|
| Logic | 14,251 / 20,736 (69%) | 4,108 / 20,736 (20%) |
| Registers | 5,142 / 15,915 (33%) | 1,843 / 15,915 (12%) |
| Configurable logic sections (CLS) | 8,060 / 10,368 (78%) | 2,815 / 10,368 (28%) |
| Block RAM | 46 / 46 (100%; 2 SP, 44 SDPB) | 16 / 46 (35%; 8 SP, 8 SDPB) |
| DSP | 1 MULT9X9, 2 MULTADDALU18X18 (10%) | No DSP usage entry |
| rPLL | 2 / 2 (100%) | 2 / 2 (100%) |
| Primary clock resources | 5 / 8 (63%) | 5 / 8 (63%) |
| Local clock resources (LW) | 8 / 8 (100%) | 5 / 8 (63%) |
| I/O ports | 27 / 66 (41%) | 27 / 66 (41%) |

Gowin reported **zero setup and hold violations** for this Studio build.
The Game Boy build has zero setup violations and **one hold violation at
-1.323 ns** on the fabric divider feedback path; timing closure remains open.
The CPU runs at 21.6 MHz, the SDRAM clock at 64.8 MHz, and the LCD pixel
clock at 9 MHz. Block RAM and both PLLs are fully allocated; adding another
large buffer or debug capture core requires a resource budget change.

| Hardware workload | Measured game update rate | Result |
|---|---:|---|
| Studio starter title | 57.8-57.9 fps | CRC-checked upload; no CPU fault |
| Blank GBA template | 57.8 fps | CRC-checked upload; no CPU fault |
| Poachermon | 28.9 fps | CRC-checked upload; no CPU fault |
| Sunstone Relay isometric test | 29.0 fps | CRC-checked upload; no CPU fault; LCD and dialogue input confirmed |
| Pokemon Red on `gbtang_lcd` | Not benchmarked | CRC-checked upload; gameplay confirmed on LCD |

The Studio figures are approximately five-second UART frame-counter
measurements. The LCD scans at about 58 Hz even when a game updates more
slowly. Studio games compile to native `game.tang.bin` firmware; this target
does not execute ARM `.gba` ROMs. Games load over USB UART without an SD card.
Reload game firmware after FPGA programming or a reset: a platform reporting
`loaded=false` displays black while waiting for an upload.

Gowin's FPGA power estimate was **262.5 mW total**, split into **122.8 mW
quiescent** and **139.7 mW dynamic** power. It used default switching activity
without VCD/SAIF input. These are model estimates, not measured board power
or supply voltages, and do not account for the complete handheld/LCD load.

See [the Studio target](tangnano20k/studio_lcd/README.md) for supported
graphics, controls and build instructions. Audio, persistent saves and
external button GPIO assignments remain unfinished. The Game Boy target's
[separate timing limitation](tangnano20k/gbtang_lcd/README.md) is still open.

## Flash a Studio game

GBA Studio's **Handheld** button builds the open project and can program the
FPGA before loading the native game. The earlier Studio 4.4.9 source-to-hardware checks
passed for both demos: Sunstone Relay at **28.915 fps** and Poachermon at
**28.928 fps**, with verified CRCs and no CPU faults. See the
[updated report](docs/NANO20K_HARDWARE_REPORT.md#studio-build-flash-and-browser-update).
The resource table above still describes the current FPGA image; these game
and asset changes do not alter its logic or RAM usage.

Studio 4.4.10 adds a title and three playable areas to each game. Both new
native exports compiled and passed their campaign checks through the C engine.
Both games also reached their endings in the browser. A fresh board upload is
pending because COM5 and all other serial ports were absent during this check.
See the [current game report](docs/reports/three-scene-games-2026-10-01.json).

For a project-directory workflow, put one `*.tang.bin` and its adjacent
`build.json` in `tangnano20k/studio_lcd/game/`, then run:

```sh
python3 scripts/gbafpga.py flash studio_lcd --sram --port /dev/ttyUSB0
```

On this Windows setup the tested Gowin command uses `--port COM5 --tool gowin
--cable-index 4 --location 289`. USB locations can change; obtain the current
location with `programmer_cli --scan-cables`. Use `--game /path/to/firmware`
for another directory, or `--no-game` to program only the FPGA. A `.gba` ARM
ROM cannot be loaded into this native Studio target. FPGA flash persists,
but the game must be loaded again after power-off because it runs from SDRAM.

## Quick start

The [hardware BOM](hardware/BOM.md) lists the working board/LCD setup and
unfinished handheld parts. The [case v2 package](3D-Case/README.md) includes
seven STL files, the preview and a Python generator. The owner reported the
larger 3D print as verified on 1 October 2026; the specific parts and assembly
checks have not yet been recorded. These models assume the larger 4.3-inch LCD.
The new [compact GBA-style prototype](3D-Case/compact/README.md) uses an
original-sized front footprint and includes 20K/60K SOM mounting adapters.
Its smaller LCD envelope and physical fit remain provisional.

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

Projects: `gba_lcd_480x272`, `gbtang_lcd`, `studio_lcd`, `gbtang`, `snestang`.

## Tests

`test` runs twelve Icarus Verilog testbenches and twelve Python tests:

| Testbench | Checks |
|---|---|
| `rgb_lcd_timing` | Measures Th, Thw, Thbp, Thfp and the vertical equivalents from the pins, for three panel profiles |
| `gba_to_480x272_mapper` | All 130,560 panel pixels against true division; every GBA pixel shown 1-2 times |
| `gba_test_pattern` | Each pattern's colours; sprite bounces inside the frame |
| `gba_buttons` | Bounce and one-clock glitches rejected, both pin polarities |
| `uart_tx` | 8N1 framing, back-to-back bytes |
| `GB LCD UART loader` | Sequential uploads, CRC gate, serial keys and invalid lengths |
| `GB LCD video` | Complete LCD raster, centred Game Boy image and RGB565 output |
| `Studio memory bus` | SDRAM halfwords, byte strobes, cache collisions/invalidation and scratch RAM |
| `Studio LCD video` | Complete LCD raster, framebuffer banks, RGB555 conversion and centring |
| `Studio hardware renderer` | BG scrolling/flips, transparent dialogue, sprite priority and 8x16 objects |
| `gba_cart_rom_reader` | No bus contention, no write strobes, correct data |
| `tangnano20k gba_lcd_top` | Whole board design from power-up: two frames pixel-exact at the panel pins, S1 pattern change, LEDs, decoded UART line |

The VHDL scaffold test under `ports/fpgba-tang60k` runs when GHDL is installed.
CI runs the tests on Linux and macOS, lints the RTL and builds the
gba_lcd_480x272 bitstream with OSS CAD Suite (downloadable from the run).

## Layout

```text
rtl/           reusable RTL: video timing, GBA-to-480x272 scaler, test pattern,
               buttons, UART, reset, ROM-only cartridge reader (+ testbenches)
tangnano20k/   Tang Nano 20K projects: gba_lcd_480x272, gbtang_lcd,
               studio_lcd, gbtang, snestang
ports/         other boards: FPGBA Tang 60K scaffold, GBATang notes
scripts/       gbafpga.py, ROM and SD-card tools, .sh/.ps1 launchers
tools/         SNES and Game Boy ROM header parsers used by the scripts
tests/         Python unit tests
docs/          design notes and hardware documentation
hardware/      handheld BOM, cartridge pinout, reader BOM, button map, wiring template
3D-Case/       seven v2 enclosure STLs, dimensions, preview and generator
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
  (about 1,080 LUT4, timing met with a wide margin). Gowin builds, SRAM
  programming and LCD test patterns have also been verified on hardware.
- gbtang_lcd: Pokemon Red loaded over UART and confirmed running on the LCD;
  the documented fabric-clock timing issue still needs work.
- studio_lcd: native Studio/GBA-engine games run on hardware. Resource use,
  timing, performance and remaining limits are listed above.
- GBTang and SNESTang: upstream code at pinned versions; this repository adds
  the tooling, IDE projects and ROM checks.
- Full GBA ROM execution: the available cores target Tang 60K-class boards.
  The Nano 20K Studio target compiles the authored game for its native CPU.
- Cartridge reader: ROM-only and simulation-only.

No BIOS images, commercial ROMs or bitstreams are committed; CI rejects them.

## Licence

Original material is GPL-2.0-or-later. Upstream projects keep their own
licences; see [NOTICE.md](NOTICE.md).
