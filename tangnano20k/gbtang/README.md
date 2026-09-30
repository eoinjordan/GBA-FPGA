# GBTang on the Tang Nano 20K

[GBTang](https://github.com/fjpolo/GBTang) (fjpolo, GPL-3.0) runs original
Game Boy games from a microSD card, with 720p HDMI output and an on-screen menu.
This folder pins **v1.0.0** (commit `90005dc`, 2026-09-23) and contains a Gowin
IDE project generated from GBTang's own `build.tcl`. The sources stay upstream:
`bootstrap` clones them into `external/GBTang`.

## Hardware

- Tang Nano 20K, HDMI display, microSD card (FAT32 or exFAT).
- A controller, either:
  - DualShock 2 through Sipeed's controller adapter: port 1 on pins 17-20,
    port 2 on pins 52, 53, 71, 72; or
  - NES/SNES pad: port 1 latch 28, clock 27, data 25; port 2 latch 29,
    clock 26, data 30.
- Leave the RGB LCD unplugged: HDMI and the SNES-pad pins share its pins.

## 1. Get the bitstream and firmware

Any of these; the `python3 scripts/gbafpga.py` commands are
`.\scripts\gbafpga.ps1` on Windows.

**Release (any OS, including macOS).** Downloads `gbtang_nano20k.fs` and
`firmware.bin` from the v1.0.0 release and checks both against the SHA-256
published on GitHub:

```bash
python3 scripts/gbafpga.py fetch gbtang
```

**Build with Gowin EDA from the command line (Windows, Linux).** Runs
upstream's `build.tcl` with `gw_sh`, exactly as upstream builds releases:

```bash
python3 scripts/gbafpga.py bootstrap gbtang
python3 scripts/gbafpga.py build gbtang
```

**Build in the Gowin IDE.** After `bootstrap gbtang`, open
`tangnano20k/gbtang/gbtang_nano20k.gprj` and run *Run All*. The bitstream is
`tangnano20k/gbtang/impl/pnr/gbtang_nano20k.fs`. (Upstream's own
`gbtang_nano20k.gprj` also lists six old NESTang files, one of them a header
and one a second copy of `dpram`; this generated project leaves them out.)

Upstream builds with Gowin **1.9.9**, Standard edition (free licence). The menu
firmware is not built here; it comes from `fetch`, or build it from
`external/GBTang/OSTang/firmware` with a RISC-V GCC.

## 2. Program the board

```bash
python3 scripts/gbafpga.py flash gbtang
```

This writes `firmware.bin` to the SPI flash at `0x500000` and the bitstream at
`0x000000`. It uses openFPGALoader when installed, otherwise Gowin's
`programmer_cli` (`--tool` chooses). Once the firmware is on the board, use
`--no-firmware` for bitstream-only updates.

With the Gowin Programmer GUI instead: device GW2AR-18C, operation
*exFlash Erase, Program thru GAO-Bridge*; program `gbtang_nano20k.fs` at
start address `0x000000`, then `firmware.bin` at `0x500000`.

## 3. Prepare the SD card

```bash
python3 scripts/prepare-gbtang-sd.py game.gb other.gb /path/to/sdcard
```

Each ROM is checked first (`scripts/validate-gb-rom.py` shows the details);
incompatible ones are skipped unless `--force`. ROMs go in `gb/` by default;
the menu can browse any folder.

## Limits of v1.0.0

From GBTang's source (`src/gbtang_top.sv`, VerilogBoy `mbc5.v`):

- Original Game Boy only. Game Boy Color-only games do not run; dual-mode
  `.gbc` games run in monochrome.
- One MBC5-style mapper serves every cartridge: ROM-only and MBC5 games are
  the safe choice; MBC1 games up to 512 KiB and MBC3 games without the clock
  usually work; MBC2, MMM01, HuC and camera cartridges do not.
- ROM size up to 4 MiB.
- Cartridge RAM is not backed up (`bk_save` is tied to 0): battery saves are
  lost at power-off.

## Files

| File | Purpose |
|---|---|
| `gbtang_nano20k.gprj` | Gowin IDE project, sources under `../../external/GBTang` |
| `impl/project_process_config.json` | IDE options from `build.tcl` (top module, SV2017, dual-purpose pins as GPIO) |

Regenerate both after changing the pinned version in `UPSTREAMS.json`:
`python3 scripts/gbafpga.py ide-project gbtang`.
