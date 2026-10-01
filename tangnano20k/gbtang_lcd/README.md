# Game Boy on the 480x272 LCD

This Nano 20K target connects GBTang v1.0.0's VerilogBoy core and SDRAM
controller to the same RGB565 LCD as `gba_lcd_480x272`. It loads a local
Game Boy ROM over the BL616 USB UART into volatile SDRAM.

Run `python scripts/gbafpga.py bootstrap gbtang`, then open
`gbtang_lcd.gprj` in Gowin IDE. The device is
`GW2AR-LV18QN88C8/I7`, top module `gbtang_lcd_top`. Build and program SRAM.
Keep HDMI unplugged: it shares the LCD data pins.

Windows and Linux can also build with
`python scripts/gbafpga.py build gbtang_lcd --flow gowin`.
ROM loading and simulation work on Windows, Linux and macOS; the vendor
build requires Windows or Linux. The current Gowin timing report has one
hold violation on the fabric clock divider's feedback path. This remains
a bring-up build until the divider clocking and timing constraints are resolved.
The 1 October report uses 4108/20736 logic resources and 16/46 block RAMs,
with worst hold slack of -1.323 ns. See the
[hardware report](../../docs/NANO20K_HARDWARE_REPORT.md) for the path and warnings.

Install pyserial once with `python -m pip install pyserial`, then:

```sh
python scripts/load-gbtang-lcd.py --port COM5 --rom "tests/roms/your-game.gb"
python scripts/load-gbtang-lcd.py --port COM5 --keys 8
```

On Linux or macOS, use the board's `/dev/ttyUSB*` or `/dev/cu.*` port.
Close Gowin Programmer before opening the UART. A 1 MiB ROM takes about
92 seconds at 115200 baud. CRC32 and received byte count must match before
the core leaves reset. This verifies the serial transfer; it does not
independently read back SDRAM.

S1 is Start, S2 is A. Serial key bits are A, B, Select, Start, Right,
Left, Up, Down, from bit 0 to bit 7. `--keys` holds that mask for 0.2
seconds and releases it; `--hold` changes the duration. Passive external
button PCBs are not assigned GPIO in this target yet.

The picture is 160x144 at native resolution, centred on the 480x272 panel.
The framebuffer is shared between the Game Boy and LCD clocks, so tearing
is possible. This bring-up target has no audio output, SD menu, or save
persistence. It accepts DMG ROMs of 32 KiB to 1 MiB; mapper compatibility
is limited to the upstream MBC5-style implementation, including the
MBC3 RAM banking used by Pokemon Red. RTC and rumble are unsupported.

The loader and full LCD raster have self-checking simulations in `sim/`.
They run with `python scripts/gbafpga.py test`. Hardware observations belong
in `.gowin-lab/`, which stays local together with bitstreams and ROMs.

Pokemon Red was loaded over COM5 and confirmed running on this LCD on
30 September 2026. Its 1 MiB transfer passed CRC32 (`9f7fdd53`) with no
reported CPU fault. This target requires `config.v` first in the project:
the `NANO` define selects the Nano 20K SDRAM geometry and byte masks.

The platform is derived from GPL-3.0-or-later GBTang. Upstream source and
licence notices remain in `external/GBTang`; no game ROM is bundled.
