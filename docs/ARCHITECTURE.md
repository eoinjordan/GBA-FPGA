# Architecture

## Product architecture

```text
GBA Studio project
      |
      v
GBA Engine + generated assets --devkitARM--> game.gba
                                              |
                       +----------------------+-------------------+
                       |                                          |
                       v                                          v
          GBATang on Tang 60K                         Real GBA / flash cart
                       |
          +------------+-------------+
          |            |             |
          v            v             v
       buttons       display       audio
          |
          +---- optional cartridge-dump/load bridge ----+
                                                         |
                                                         v
                                                GBA cartridge slot
```

## Two FPGA tracks

### Working track

GBATang already supplies the GBA CPU, memory system, graphics, audio, SD loader, and Tang 60K board projects. This is the route for a playable handheld.

### Research track

FPGBA supplies a VHDL GBA core and simulation-oriented source tree. Its board-independent core must be wrapped with:

- Gowin clock generation and reset sequencing;
- a DDR3 or SDRAM controller;
- game ROM and save-memory arbitration;
- a frame buffer or direct scan-out bridge;
- RGB LCD or HDMI timing;
- audio sample output;
- controller input;
- a menu and storage loader;
- vendor memory primitive substitutions where inference is insufficient.

The `ports/fpgba-tang60k` directory defines this platform boundary. It intentionally does not claim completion.

## Cartridge architecture

The GBA cartridge bus multiplexes the lower address and 16-bit data bus. A direct reader needs 24 address bits, 16 multiplexed data/address signals, and control signals. This is expensive in GPIO when a raw RGB panel is also connected.

The recommended first implementation is:

```text
Cartridge slot <-> RP2350/PGA2350 <-> USB/SPI/SD file <-> FPGA loader
```

This allows ROM dumping, save backup, and electrical validation to be separated from the real-time FPGA core.

The included SystemVerilog reader is ROM-only. It is suitable for controlled bring-up but does not implement EEPROM, SRAM, Flash, GPIO-equipped cartridges, or writeback.
