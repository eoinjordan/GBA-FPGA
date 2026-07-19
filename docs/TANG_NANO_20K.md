# Tang Nano 20K plan

The Nano 20K should be used as the first handheld integration board, but with a GB/GBC core rather than a GBA core.

## Phase 1 — desktop bring-up

1. Flash a known GBTang release.
2. Confirm SD-card ROM loading over HDMI.
3. Validate the button PCB using the active-low input module in `rtl/input`.
4. Confirm I2S audio through the onboard amplifier.

## Phase 2 — 480x272 LCD

1. Identify the exact LCD part number and FPC pinout.
2. Confirm whether the interface is RGB565, RGB666, RGB888, SPI, or 8080-style parallel.
3. Confirm I/O voltage and backlight current.
4. Run only the timing/color-bar generator first.
5. Add the aspect-ratio-preserving coordinate mapper.

A 240x160 GBA frame maps cleanly to 408x272 while preserving 3:2 aspect ratio, leaving 36-pixel side borders on a 480x272 panel. The mapper in this repository generates source coordinates for that geometry.

## Phase 3 — cartridge reader

Use the Nano 20K only for controlled ROM-read tests if sufficient GPIO remains. A companion RP2350 is preferred because the raw RGB LCD and cartridge buses compete for pins.

## Phase 4 — migrate to 60K

Move the established input, display, power, audio, and enclosure design to Tang 60K hardware for GBA execution.
