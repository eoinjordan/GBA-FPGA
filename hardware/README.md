# Handheld hardware

The current working setup is a Tang Nano 20K with the HT043IBB-16A3047-H4
4.3-inch 480x272 RGB LCD, powered and loaded over USB. Game Boy and native
Studio games use this setup without an SD card.

- [Bill of materials](BOM.md) and [CSV parts list](nano20k_handheld_bom.csv)
- [Case v2 STL files, preview and generator](../3D-Case/README.md)
- [Compact GBA-style case and 20K/60K SOM adapters](../3D-Case/compact/README.md)
- [Compact prototype BOM CSV](compact_handheld_bom.csv)
- [LCD interface and timing](../docs/LCD_480X272.md)
- [Hardware validation report](../docs/NANO20K_HARDWARE_REPORT.md)
- [GBA cartridge pinout](gba_cartridge_pinout.csv),
  [reader BOM](gba_cartridge_reader_bom.csv) and [wiring template](wiring_template.csv)
- [SNES button labels](snes_button_map.csv)

The passive button PCBs reuse the existing GBA controls. External button
GPIO assignments, audio and a battery power system are unfinished. The
cartridge reader is a separate prototype; it is not required for USB-loaded
Studio or Game Boy games. Full GBA ROM emulation needs a larger FPGA target.
