# SNES on the Tang Nano 20K

SNESTang runs SNES games on the Nano 20K over HDMI. The version pinned here is
v0.9, the last one whose Nano 20K build keeps its menu on a PicoRV32 inside the
FPGA; setup is in [tangnano20k/snestang](../tangnano20k/snestang/README.md).

## From SNES Studio to the board

```text
SNES Studio project -> PVSnesLib build -> .sfc -> emulator (bsnes, Mesen-S)
    -> scripts/validate-snes-rom.py -> SD card -> SNESTang on the Nano 20K
```

## ROM size

Payloads must be smaller than 3.75 MiB on the Nano 20K. The validator uses
3,932,160 bytes as a strict limit and ignores a 512-byte copier header when
measuring.

## Controls

The GBA's two face buttons are not enough for SNES games. A handheld needs the
D-pad, A, B, X, Y, L, R, Start and Select, plus a menu button where the core
supports one (`hardware/snes_button_map.csv`). SNESTang reads SNES pads and
DualShock 2 pads, so a button board built like a SNES pad needs no FPGA changes.

## Display and storage

The first prototype uses SNESTang's HDMI output. The 480x272 panel works (see
`gba_lcd_480x272`), but SNESTang would need a frame buffer and scaler to drive
it. Games load from microSD; a physical SNES cartridge slot would add 5 V
interfacing, mapping, enhancement-chip and save-memory work for no gain in a
first prototype.
