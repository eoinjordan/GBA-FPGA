# Tang Nano 20K projects

Projects for the Sipeed Tang Nano 20K (Gowin GW2AR-LV18QN88C8/I7), one folder
each with a Gowin IDE project, laid out like Sipeed's
[TangNano-20K-example](https://github.com/sipeed/TangNano-20K-example).

| Folder | What it runs | Output | Source |
|---|---|---|---|
| [gba_lcd_480x272](gba_lcd_480x272/) | GBA-FPGA display and input check: test image through the 240x160 to 408x272 scaler | 4.3" 480x272 RGB LCD | this repository |
| [gbtang](gbtang/) | GBTang v1.0.0, original Game Boy | 720p HDMI | [fjpolo/GBTang](https://github.com/fjpolo/GBTang), pinned |
| [snestang](snestang/) | SNESTang v0.9, SNES | 720p HDMI | [nand2mario/snestang](https://github.com/nand2mario/snestang), pinned |

A Game Boy Advance core does not fit this board; GBA needs a Tang 60K-class
board with GBATang.

## Commands

From the repository root; on Windows use `.\scripts\gbafpga.ps1` in place of
`python3 scripts/gbafpga.py`. Tool setup per OS: [docs/TOOLCHAIN.md](../docs/TOOLCHAIN.md).

```bash
python3 scripts/gbafpga.py doctor                          # what this machine can build and flash

python3 scripts/gbafpga.py build gba_lcd_480x272           # open-source flow, or --flow gowin
python3 scripts/gbafpga.py flash gba_lcd_480x272 --sram

python3 scripts/gbafpga.py fetch gbtang                    # release bitstream + firmware, any OS
python3 scripts/gbafpga.py bootstrap gbtang snestang       # sources, to build with Gowin EDA
python3 scripts/gbafpga.py build gbtang                    # Gowin EDA (Windows, Linux)
python3 scripts/gbafpga.py flash gbtang                    # firmware at 0x500000 + bitstream at 0
```

## Board notes

- The 40-pin RGB LCD connector and the HDMI connector share FPGA pins 33-40.
  A bitstream drives one or the other; unplug the one not in use.
- S1 (pin 88) and S2 (pin 87) read 1 when pressed (pull-downs on the board).
- LED0-LED5 (pins 15-20) are active-low. Pins 17-20 are also the header pins
  that GBTang and SNESTang use for the first DualShock 2 port.
- The onboard BL616 provides JTAG and a USB serial port on pins 69 (FPGA TX)
  and 70 (FPGA RX).
- SPI flash: the bitstream starts at `0x000000`; GBTang and SNESTang load their
  menu firmware from `0x500000`.

## gba_lcd_480x272 pins

All taken from Sipeed's Nano 20K constraint files.

| Port | Pin | Port | Pin | Port | Pin |
|---|---|---|---|---|---|
| clk_27m | 4 | btn_s1 | 88 | btn_s2 | 87 |
| led_n[0] | 15 | led_n[1] | 16 | led_n[2] | 17 |
| led_n[3] | 18 | led_n[4] | 19 | led_n[5] | 20 |
| uart_tx | 69 | lcd_dclk | 77 | lcd_de | 48 |
| lcd_hsync | 25 | lcd_vsync | 26 | | |
| lcd_r[0] | 42 | lcd_r[1] | 41 | lcd_r[2] | 40 |
| lcd_r[3] | 39 | lcd_r[4] | 38 | | |
| lcd_g[0] | 37 | lcd_g[1] | 36 | lcd_g[2] | 35 |
| lcd_g[3] | 34 | lcd_g[4] | 33 | lcd_g[5] | 32 |
| lcd_b[0] | 31 | lcd_b[1] | 30 | lcd_b[2] | 29 |
| lcd_b[3] | 28 | lcd_b[4] | 27 | | |

## Controller pins used by GBTang and SNESTang

| Signal | Port 1 | Port 2 |
|---|---|---|
| DualShock 2 clk / cs / miso / mosi | 17 / 18 / 19 / 20 | 52 / 72 / 71 / 53 |
| SNES/NES pad latch / clock / data | 28 / 27 / 25 | 29 / 26 / 30 |

A handheld button board wired like a SNES pad (two CD4021 or 74HC165 shift
registers) works with both cores without FPGA changes.
