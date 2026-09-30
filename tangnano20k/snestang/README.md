# SNESTang on the Tang Nano 20K

[SNESTang](https://github.com/nand2mario/snestang) (nand2mario, GPL-3.0) is a
SNES core with 720p HDMI output, ROM loading from microSD and an on-screen
menu. This folder pins **v0.9** (commit `58bb70a`, 2024-11-17) and contains a
Gowin IDE project generated from SNESTang's `build.tcl`. The sources stay
upstream: `bootstrap` clones them into `external/snestang`.

Why v0.9: it is the last release whose Nano 20K build runs its menu on a
PicoRV32 inside the FPGA, loaded from `firmware.bin` in the SPI flash. Later
SNESTang moved to TangCore, where the menu firmware runs on a separate BL616
microcontroller; TangCore supports the Tang Console and Primer boards, not the
Nano 20K.

## Hardware

- Tang Nano 20K, HDMI display, microSD card (FAT16, FAT32 or exFAT).
- Controllers, both kinds at once if you like:
  - DualShock 2 through Sipeed's controller adapter: port 1 on pins 17-20,
    port 2 on pins 52, 53, 71, 72;
  - SNES pads: port 1 latch 28, clock 27, data 25; port 2 latch 29, clock 26,
    data 30.
- Leave the RGB LCD unplugged: HDMI and the SNES-pad pins share its pins.
- ROMs must be smaller than 3.75 MiB (the Nano 20K's SDRAM budget).

## 1. Get the bitstream and firmware

The `python3 scripts/gbafpga.py` commands are `.\scripts\gbafpga.ps1` on Windows.

**Release (any OS, including macOS):**

```bash
python3 scripts/gbafpga.py fetch snestang
```

Downloads `snestang-0.9.zip` and extracts `snestang_nano20k.fs` and
`firmware.bin`. This older release has no checksum on GitHub, so only its size
is checked; the SHA-256 is printed so you can record it.

**Build with Gowin EDA from the command line (Windows, Linux):**

```bash
python3 scripts/gbafpga.py bootstrap snestang
python3 scripts/gbafpga.py build snestang
```

**Build in the Gowin IDE:** after `bootstrap snestang`, open
`tangnano20k/snestang/snestang_nano20k.gprj` and run *Run All*; the bitstream
is `tangnano20k/snestang/impl/pnr/snestang_nano20k.fs`.

Use Gowin **1.9.10.03**: upstream notes that 1.9.11.01 makes Mode 7 render
black. The firmware is not built here; take it from `fetch`, or build
`external/snestang/firmware` with a RISC-V GCC (upstream uses xpack
riscv-none-elf-gcc).

## 2. Program the board

```bash
python3 scripts/gbafpga.py flash snestang
```

Writes `firmware.bin` at `0x500000` and the bitstream at `0x000000`, with
openFPGALoader or Gowin's `programmer_cli`. The bitstream is the newest of
`build`, the Gowin IDE output (`impl/pnr/`) and `fetch`; the firmware comes
from `fetch` (the v0.9 source tree does not include a built copy), so run
`fetch snestang` once even if you build the bitstream yourself. `--dry-run`
shows what would be written; `--no-firmware` skips the firmware on later
updates. In the Gowin Programmer GUI: device GW2AR-18C,
*exFlash Erase, Program thru GAO-Bridge*, bitstream at `0x000000`, firmware at
`0x500000`.

## 3. Prepare the SD card

```bash
python3 scripts/validate-snes-rom.py game.sfc
python3 scripts/prepare-snestang-sd.py game.sfc /path/to/sdcard
```

The validator reports the header, mapping (LoROM/HiROM/ExHiROM), checksum and
the Nano 20K size budget. `.sfc` and `.smc` files are recognised. While a game
runs, SELECT plus the right shoulder button (upstream calls it SELECT-RB) opens
the menu.

## Files

| File | Purpose |
|---|---|
| `snestang_nano20k.gprj` | Gowin IDE project, sources under `../../external/snestang` |
| `impl/project_process_config.json` | IDE options from `build.tcl` |

Regenerate both after changing the pinned version in `UPSTREAMS.json`:
`python3 scripts/gbafpga.py ide-project snestang`.
