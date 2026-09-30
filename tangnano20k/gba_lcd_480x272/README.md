# gba_lcd_480x272

A Tang Nano 20K design that checks the GBA-FPGA display and input path on the
**HT043IBB-16A3047-H4** 4.3" 480x272 panel. It needs no core and no ROM: a
240x160 test image stands in for a GBA/GB frame and goes through the same
timing generator, scaler and pixel pipeline a core's frame buffer would use.
LEDs and a serial status line report what the FPGA sees, so the board can be
checked before the panel is connected.

## Build

The `python3 scripts/gbafpga.py` commands are `.\scripts\gbafpga.ps1` on Windows.

| Route | Command | Output |
|---|---|---|
| Open-source tools (Linux, macOS, Windows) | `python3 scripts/gbafpga.py build gba_lcd_480x272` | `build/tangnano20k/gba_lcd_480x272/gba_lcd_480x272.fs` |
| Gowin EDA, command line | `python3 scripts/gbafpga.py build gba_lcd_480x272 --flow gowin` | same folder |
| Gowin IDE | open `gba_lcd_480x272.gprj`, *Run All* | `impl/pnr/gba_lcd_480x272.fs` |

`make` in this folder runs the same commands (`make`, `make gowin`, `make load`,
`make flash`, `make test`).

## Program

```bash
python3 scripts/gbafpga.py flash gba_lcd_480x272 --sram   # quick test, lost at power-off
python3 scripts/gbafpga.py flash gba_lcd_480x272          # SPI flash, survives power-off
```

`flash` uses the newest bitstream it finds, whether from `build` or from a
Gowin IDE *Run All* (`impl/pnr/`), and prints its path; add `--dry-run` to see
the programmer commands without touching the board.

Gowin Programmer GUI: device GW2AR-18C, *SRAM Program* or
*exFlash Erase, Program thru GAO-Bridge* with the `.fs` file.

## Check it on the board

1. **Without the panel.** Flash, open the board's serial port at 115200 8N1
   (the Nano 20K's debugger shows two ports; if one stays silent, try the
   other).

   | Check | Expected |
   |---|---|
   | LED1 | on: the rPLL is locked |
   | LED0 | blinking, about once a second: pixel clock and timing generator running |
   | Serial, once a second | `gba-fpga tn20k lcd fps=058 pattern=0 s1=0 s2=0 pll=1 up=00001` |
   | `fps` | `058`: frames counted against the 27 MHz crystal, so this checks the PLL and the timing (9 MHz / (531 x 292) = 58.05 Hz) |
   | S1 / S2 held | LED4 / LED5 on, `s1=1` / `s2=1` |

2. **With the panel.** Power off, seat the panel's FPC in the 40-pin RGB
   connector, leave HDMI unplugged, power on. S1 steps to the next pattern,
   S2 to the previous one; LED2/LED3 show the pattern number in binary.

   | Pattern | What you should see | What it proves |
   |---|---|---|
   | 0 | Dark grey 36-px bars at the left and right edges. Between them, eight colour bars (white, yellow, cyan, green, magenta, red, blue, black, left to right) over the top two thirds, then red, green and blue ramps. A 1-px outline around the 408x272 picture in the inverse colour. | Full 480x272 area drawn, image window placed correctly, RGB order, every colour bit (ramps show 32 even steps) |
   | 1 | 8x8-pixel checkerboard (tiles 13-14 panel pixels wide), red crosshair through the centre, white outline, black side bars | Scaling and centring |
   | 2 | Yellow 16x16 square bouncing over a blue gradient | Frame timing: smooth motion, no tearing (the square's width alternates 27/28 px because of the 1.7x scale) |
   | 3 | Whole panel cycling white, red, green, blue, cyan, magenta, yellow, black, about every half second | Dead or stuck pixels, backlight evenness |

### If something is wrong

| Symptom | Likely cause |
|---|---|
| LED1 off, `pll=0`, `fps=000` | PLL not locking; the design will not run |
| Serial fine, panel dark | FPC not seated or reversed, or no backlight |
| Picture shimmers or pixels flicker at edges | Data sampled on the wrong DCLK edge: set `LCD_LATCH_RISING` to 0 in `src/gba_lcd_top.sv` |
| Red and blue bars swapped | Panel's RGB order differs from Sipeed's connector wiring |
| Picture shifted or rolling | Panel wants different porches: edit the profile at the top of `src/gba_lcd_top.sv` |
| `fps` not 58 | Wrong PLL settings for the crystal in `src/gowin_rpll/lcd_pll.v` |

## How it works

```text
 27 MHz ──┬─> rPLL ─> 9 MHz clk_pix ───────────────────────────────┬─> DCLK (pin 77)
          │                                                         │
          │   rgb_lcd_timing ─> gba_to_480x272_mapper ─> gba_test_pattern
          │   (raster, DE,      (panel x,y -> GBA x,y,    (BGR555 colour)
          │    syncs)            10/17 scale)                  │
          │        │                                           v
          │        └──────── stage 2 register ─> stage 3 register on the falling
          │                  (colour + DE/HS/VS)   edge ─> RGB565, DE, HSYNC, VSYNC
          │
          ├─> gba_buttons (S1, S2) ─> pattern select ──Gray code──> pixel domain
          ├─> frame counter <── frame toggle from the pixel domain ──┘
          ├─> status_reporter ─> uart_tx ─> pin 69 (USB serial)
          └─> LEDs
```

- **Panel timing.** NV3047 "Typ." values: 480 + 8 + 4 + 39 = 531 clocks per
  line, 272 + 8 + 4 + 8 = 292 lines, HSYNC-to-first-pixel 43 clocks and
  VSYNC-to-first-line 12 lines, active-low syncs, DE driven as well. See
  [docs/LCD_480X272.md](../../docs/LCD_480X272.md) for the datasheet table.
- **Clock edge.** The NV3047 samples on DCLK's rising edge with 12 ns setup and
  hold. All panel outputs leave from flops on the falling edge of the 9 MHz
  clock, which puts every data transition half a period (55 ns) from the
  sampling edge. `LCD_LATCH_RISING = 0` launches on the rising edge instead,
  as Sipeed's samples do.
- **Pipeline.** Timing registers, then the combinational mapper and pattern,
  then one register stage for colour with DE and syncs, then the falling-edge
  output stage. Every panel signal passes through the same stages, so colour
  stays aligned with DE; RGB is forced to zero outside DE.
- **Clock domains.** The crystal domain (buttons, LEDs, UART) comes out of reset
  at configuration even if the PLL never locks, so failures still get reported.
  The pixel domain is held in reset until the PLL locks. The pattern number
  crosses as a 2-bit Gray code (S1/S2 change it by one, so only one bit
  flips) and is applied during VSYNC; the frame counter's bit 0 crosses the
  other way as a toggle.

Resources and timing from the open-source flow (varies slightly per run):
about 1,080 LUT4 (5 %), 260 flip-flops, 2 of 96 9x9 multipliers (the scaler),
1 rPLL, no block RAM. The 9 MHz pixel clock closes at about 110 MHz and the
27 MHz domain at over 200 MHz. `build/tangnano20k/gba_lcd_480x272/report.txt`
has the figures for your build.

Hardware status: simulated (every pixel of two frames checked at the pins, see
`sim/`) and built with the open-source flow; not yet run on a board, and the
Gowin IDE build has not been tried.

## Files

| File | Purpose |
|---|---|
| `gba_lcd_480x272.gprj` | Gowin IDE project; the source list every flow uses |
| `impl/project_process_config.json` | IDE options: top `gba_lcd_top`, SystemVerilog 2017, MSPI/SSPI pins as GPIO |
| `src/gba_lcd_top.sv` | Board top level; panel profile and clock-edge setting at the top |
| `src/status_reporter.sv` | Once-per-second UART status line |
| `src/gowin_rpll/lcd_pll.v` | rPLL: 27 MHz to 9 MHz |
| `src/gba_lcd_480x272.cst` | Pins, from Sipeed's Nano 20K examples |
| `src/gba_lcd_480x272.sdc` | Clock constraints (nextpnr reads the `create_clock` lines) |
| `sim/gba_lcd_top_tb.sv` | End-to-end test: panel model, pixel check, buttons, UART |
| `sim/rpll_model.v` | Behavioural rPLL for simulation |
| `../../rtl/` | The reusable modules: timing, mapper, test pattern, buttons, UART, reset |
