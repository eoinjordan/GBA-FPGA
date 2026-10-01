# GBA Studio on the Nano 20K LCD

This target runs Studio's C game data and GBA-engine on a PicoRV32 RV32IM
CPU, with a hardware tile/sprite renderer and the 480x272 RGB565 LCD.
The game view is 240x160 at native resolution. Games load over USB UART;
no SD card is required. The firmware format is `game.tang.bin`.

Run `python scripts/gbafpga.py bootstrap gbtang`, then open
`studio_lcd.gprj` in Gowin IDE. Select `GW2AR-LV18QN88C8/I7` and top
`studio_lcd_top`. Build and program SRAM. Keep HDMI unplugged because it
shares the LCD data pins.

The equivalent command on Windows/Linux is:

```sh
python scripts/gbafpga.py build studio_lcd --flow gowin
python scripts/gbafpga.py flash studio_lcd --sram --tool gowin --cable-index 1
```

Use the cable index reported by your programmer; index 1 was used on the
development PC. On macOS, use an already-built bitstream with
openFPGALoader. Gowin synthesis requires Windows or Linux. The Python
export, firmware build, USB loading and simulations also work on macOS.

In GBA Studio, run `npm run make:cli` once. Its Tang build command exports
GBA C data, compiles the pinned engine with LLVM, and loads the board:

```sh
python scripts/build-tang.py path/to/project.gbsproj out/tang/my-game --port COM5
```

See [Studio's full instructions](https://github.com/eoinjordan/gba-studio)
for the engine and FPGA path options. For a firmware already compiled:

```sh
python scripts/load-studio-lcd.py --port COM5 --firmware path/to/game.tang.bin --report build/hardware.json
```

Install pyserial with `python -m pip install pyserial`. Use `/dev/ttyUSB*`
on Linux or `/dev/cu.*` on macOS. Close Gowin Programmer before opening
the UART. The loader checks a Tang build manifest, firmware SHA256,
received byte count and CRC32 before releasing the CPU. CRC verifies the
serial stream; it does not independently read back SDRAM.

S1 is Start, S2 is A. Serial masks are A=1, B=2, Select=4, Start=8,
Right=16, Left=32, Up=64, Down=128. For example:

```sh
python scripts/load-studio-lcd.py --port COM5 --keys 16 --hold 0.5
```

The loader reports game frames, measured game fps, CPU faults and the last
instruction address. UART commands are `TGLD` + uint32 length + payload +
CRC32 (all integers little-endian), `Q` for status, and `K` + key mask.
`P`/`H` return the low/high program counter halves; `A` returns the last
bus address's low half. Replies use the 16-byte `TGST` status layout.

Game firmware is volatile. After FPGA programming or a reset, upload it
again; `loaded=false` with zero frames explains a black display while the
platform waits for a game. To run the Sunstone Relay isometric example,
from the Studio repository:

```sh
python scripts/build-tang.py examples/isometric-adventure/project.gbsproj out/tang/isometric --port COM5
```

The renderer supports the engine's Mode 0 BG0/BG1 4bpp tiles, scrolling,
tile flips, palette banks, dialogue and regular sprites with 1D tile
mapping. Affine sprites, 8bpp tiles, blending, audio and persistent saves
are unsupported. External passive button PCBs are not assigned GPIO yet.
The framebuffer is single-buffered, so tearing is possible.

Hardware validation used Gowin 1.9.12.04 on this LCD. The Studio starter
title measured 57.9 game fps; its menu scenes measured about 29 fps.
The 1 October build used 14251/20736 logic resources and all 46 block RAMs. Gowin
reported zero setup and hold violations. Larger scenes and scripts can
reduce the game update rate. The LCD raster runs at approximately 58 Hz.
The current isometric firmware measured about 29 game fps with no CPU fault;
camera captures confirm the scene and dialogue advancing with A. See the
[hardware report](../../docs/NANO20K_HARDWARE_REPORT.md) for evidence and limits.

Run `python scripts/gbafpga.py test` for the memory bus, complete LCD
raster, and renderer tests. Bitstreams and local ROMs stay in ignored build
directories; selected camera captures accompany the hardware report.
PicoRV32 retains its ISC licence in
`src/picorv32.v`; the SDRAM platform derives from GPL-3.0-or-later GBTang.
