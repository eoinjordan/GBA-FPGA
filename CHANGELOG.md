# Changelog

All notable changes to this repository are documented here.

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
- The raw LCD still requires an exact panel datasheet.
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
