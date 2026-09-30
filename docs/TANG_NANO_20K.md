# Tang Nano 20K

Gowin GW2AR-LV18QN88C8/I7: 20,736 LUT4, 15,552 flip-flops, 828 Kbit block RAM
(46 x 18 Kbit), 48 18x18 multipliers, 2 rPLLs, 64 Mbit SDR SDRAM in the
package. The board adds a 27 MHz crystal, HDMI, a 40-pin RGB LCD connector,
microSD, a MAX98357A amplifier, 6 LEDs, 2 buttons and a BL616 USB debugger
(JTAG plus a serial port).

## What runs on it

| Project | Status |
|---|---|
| `tangnano20k/gba_lcd_480x272` (this repository) | Simulated and built; waiting for a board test |
| GBTang v1.0.0 (Game Boy) | Upstream release; build, flash and SD tooling here |
| SNESTang v0.9 (SNES) | Upstream release; build, flash and SD tooling here |
| Game Boy Advance | Does not fit; see [BOARD_MATRIX.md](BOARD_MATRIX.md) |

Details, commands and pin tables: [tangnano20k/README.md](../tangnano20k/README.md).

## Bring-up order

1. **Board and tools.** Flash `gba_lcd_480x272` without the panel. LED1 on,
   LED0 blinking and `fps=058` on the serial port show the FPGA, PLL and
   programming path work.
2. **LCD.** Connect the HT043IBB panel and go through the four test patterns
   ([LCD_480X272.md](LCD_480X272.md) has the panel data).
3. **GBTang over HDMI** with a DualShock 2 or SNES pad.
4. **SNESTang over HDMI**, same controllers.
5. **Buttons.** GBTang and SNESTang already read SNES pads (latch, clock, data)
   and DualShock 2 pads. A handheld button board built like a SNES pad (two
   CD4021 or 74HC165 shift registers, A/B/X/Y/L/R/Start/Select and the D-pad)
   works with both cores unchanged. `rtl/input/gba_buttons.sv` covers the other
   option, one FPGA pin per button, for designs of our own.
6. **LCD for the cores.** GBTang and SNESTang output HDMI only. Driving the
   480x272 panel from a core needs a frame buffer (the GB's 160x144 at 2 bits
   per pixel fits in block RAM) followed by a scaler like
   `gba_to_480x272_mapper`.

## Pin sharing

The RGB LCD connector shares pins 33-40 with HDMI, and the cores' SNES-pad
inputs (pins 25-30) are also LCD pins. One bitstream drives either the LCD or
HDMI with SNES pads; the DualShock 2 ports (17-20 and 52, 53, 71, 72) do not
conflict with the LCD.
