# Architecture

## Software to hardware

```text
GBA Studio project
      |
      v
GBA Engine + generated assets --devkitARM--> game.gba
                                               |
                        +----------------------+-------------------+
                        |                                          |
                        v                                          v
           GBATang on a Tang 60K board                  real GBA / flash cart
                        |
           +------------+-------------+
           |            |             |
           v            v             v
        buttons      display        audio
           |
           +---- optional cartridge dump/load bridge ----+
                                                          |
                                                          v
                                                 GBA cartridge slot
```

## Two FPGA tracks

GBATang already provides the GBA CPU, memory system, graphics, audio, SD
loader and Tang 60K board projects; it is the route to a playable handheld.

FPGBA is a VHDL GBA core with a simulation-oriented source tree. Using it on a
Tang board means wrapping the core with:

- Gowin clock generation and reset sequencing;
- a DDR3 or SDRAM controller;
- ROM and save-memory arbitration;
- a frame buffer or direct scan-out bridge;
- RGB LCD or HDMI timing;
- audio output;
- controller input;
- a menu and storage loader;
- vendor memory primitives where inference falls short.

`ports/fpgba-tang60k` defines that boundary. It is a scaffold, not a working
port.

## Reusable RTL in this repository

| Module | Role |
|---|---|
| `rtl/video/rgb_lcd_timing.sv` | Parallel-RGB panel timing, registered outputs |
| `rtl/video/gba_to_480x272_mapper.sv` | Panel pixel to GBA pixel, 10/17 scale |
| `rtl/video/gba_test_pattern.sv` | 240x160 test image for display bring-up |
| `rtl/input/gba_buttons.sv` | Button synchronising and debouncing |
| `rtl/common/uart_tx.sv`, `reset_sync.sv` | Serial output, reset synchroniser |
| `rtl/cart/gba_cart_rom_reader.sv` | ROM-only Game Pak reader |

## Cartridge

The GBA cartridge bus multiplexes the low address with 16-bit data: a direct
reader needs 24 address bits, 16 of them shared with data, plus control
signals. That is a lot of GPIO next to a raw RGB panel, so the first
implementation should be:

```text
Cartridge slot <-> RP2350/PGA2350 <-> USB/SPI/SD file <-> FPGA loader
```

This keeps ROM dumping, save backup and electrical testing away from the
real-time FPGA core. The SystemVerilog reader here is ROM-only and suits
controlled bring-up; it has no EEPROM, SRAM, Flash, GPIO-cartridge or
write-back support. See [CARTRIDGE_READER.md](CARTRIDGE_READER.md).
