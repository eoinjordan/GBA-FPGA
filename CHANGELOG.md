# Changelog

All notable changes to this repository are documented here.

## 0.3.0 — 2026-09-30

### Added

- `tangnano20k/`: Tang Nano 20K projects in the layout of Sipeed's example repositories.
  - `gba_lcd_480x272`: test design for the HT043IBB-16A3047-H4 (NV3047) 4.3" panel with
    four test patterns, S1/S2 pattern select, status LEDs and a once-per-second UART
    report; Gowin IDE project, pin and timing constraints, end-to-end simulation.
  - `gbtang` (v1.0.0) and `snestang` (v0.9): Gowin IDE projects generated from the
    upstream `build.tcl`; versions, commits and release checksums pinned in `UPSTREAMS.json`.
- `scripts/gbafpga.py`: doctor, bootstrap, test, lint, build (open-source or Gowin),
  fetch, flash and ide-project commands for Linux, macOS and Windows, with `.sh` and
  `.ps1` launchers.
- `rtl/video/gba_test_pattern.sv`, `rtl/common/uart_tx.sv`, `rtl/common/reset_sync.sv`.
- Game Boy ROM checks and SD preparation for GBTang (`tools/gb_rom.py`,
  `scripts/validate-gb-rom.py`, `scripts/prepare-gbtang-sd.py`).
- `docs/TOOLCHAIN.md`; CI on macOS, Verilator lint and a bitstream build.

### Changed

- `rgb_lcd_timing`: registered, glitch-free outputs; defaults are the NV3047 typical timing.
- `gba_to_480x272_mapper`: the two constant dividers are replaced by an exact
  multiply-and-shift; all 130,560 panel pixels are checked.
- `gba_buttons`: one shared debounce tick instead of a 19-bit counter per button;
  `ACTIVE_LOW` and `BUTTON_COUNT` parameters.
- `gba_cart_rom_reader`: phase counter sized to the longest phase.
- Every RTL file has section comments and passes Verilator `-Wall` (width expansion waived).
- Testbenches measure datasheet timing parameters and reject bounce and glitches;
  VCD output is opt-in.
- Shell scripts are executable and no longer need `realpath`; bootstrap and verify
  run through `gbafpga.py`.
- Docs rewritten; GBTang is documented as original Game Boy only (not Game Boy Color).

### Removed

- `ports/nano20k-gb` and `ports/nano20k-snes` (replaced by `tangnano20k/`).
- The blog drafts.

## 0.2.0 — 2026-07-19

### Added

- SNESTang Tang Nano 20K as a first-class practical handheld path.
- Structural SNES ROM inspection for LoROM, HiROM and ExHiROM header candidates.
- Strict Nano 20K ROM-size validation and SHA-256 reporting.
- Deterministic SD-card deployment scripts with configurable ROM directory and optional core copy.
- Four-face-button SNES control map and updated hardware matrix.
- Retro Studio shared-intermediate-representation guidance.
- SNESTang, NESTang and SNES Studio upstream bootstrap entries.
- Python unit tests for the SNES ROM tools.

### Changed

- Reframed the repository as a GBA-shaped multi-system handheld integration workbench.
- Promoted SNES Studio -> SNESTang -> Tang Nano 20K as the best-value immediate milestone.
- Updated CI safety checks to reject SNES ROM artifacts.

### Known limitations

- No SNESTang, GBTang or GBATang core source or bitstream is vendored.
- No verified FPGBA bitstream for a Gowin device exists in this release.
- The raw LCD still requires an exact panel datasheet (resolved in 0.3.0).
- The GBA cartridge module remains ROM-read-only.

## 0.1.0 — 2026-07-19

### Added

- Initial GBA-FPGA integration workbench.
- Tang Nano 20K versus Tang 60K resource decision and board matrix.
- FPGBA Tang 60K platform scaffold with self-checking GHDL testbench.
- ROM-only GBA cartridge reader with bus-turnaround protection and Icarus Verilog testbench.
- Active-low GBA button input and debounce logic.
- 240x160-to-480x272 aspect-ratio-preserving mapper.
- Parameterized parallel-RGB LCD timing generator.
- Linux and Windows scripts for upstream checkout, GBA Studio ROM builds, SD preparation, validation, and GitHub publication.
- Long-form article, Hackaday tip draft, and paraphrased PaperBoy S3 technical notes.
- CI checks for HDL simulation, JSON validity, and accidental ROM/BIOS inclusion.
