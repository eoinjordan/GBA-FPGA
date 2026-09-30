# FPGBA unofficial Tang build

## What "unofficial build" means here

A port workbench, not a prebuilt or verified Tang bitstream.

Upstream FPGBA contains the VHDL core, a ModelSim compilation order, BIOS-generation tooling, and a framebuffer module. Its published target list identifies the DE2-115 as complete and the MiSTer/DE10 path as work in progress. It does not provide a Gowin project for Tang boards.

## Why target Tang 60K

The Tang Mega 60K has enough headline capacity to begin a credible port:

- 59,904 LUT4s;
- 2,124 Kbit block SRAM;
- 512 MiB external DDR3 on the dock;
- multiple PLLs;
- RGB, HDMI, SD, audio, and expansion interfaces on suitable carrier boards.

That does not prove the core fits or meets timing; it only removes the resource shortfall of the Nano 20K.

## Porting milestones

### Milestone 0 — simulation baseline

- Clone upstream FPGBA.
- Reproduce its VHDL compile order.
- Run legal test ROMs and the open BIOS path.
- Record the exact upstream commit and simulator version.

### Milestone 1 — Gowin synthesis of the core

- Create a Gowin project for GW5AT-LV60.
- Replace or infer dual-port RAMs.
- Stub external ROM, save, video, audio, and controls.
- Obtain the first synthesis resource report.

### Milestone 2 — clock and reset

- Generate the core clock and memory-controller clocks.
- Add deterministic reset release after PLL lock and DDR3 calibration.
- Add synchronisers for asynchronous inputs.

### Milestone 3 — memory

- Map fast WRAM, VRAM, palette RAM, and OAM to block RAM.
- Map slow WRAM, Game Pak ROM, and save storage to DDR3.
- Implement arbitration and bounded-latency buffering.
- Verify ROM sequential and non-sequential access timing.

### Milestone 4 — video and audio

- Connect the GBA pixel stream to a frame buffer.
- Scale 240x160 to the selected panel while preserving 3:2 aspect ratio.
- Add audio sample conversion to I2S or a PWM/PDM path.

### Milestone 5 — loader and controls

- Add SD/FAT loading using a soft core or companion MCU.
- Load ROMs only from user-provided legal images.
- Add joypad mapping and menu control.

### Milestone 6 — compatibility evidence

- Run mgba test-suite ROMs where licensing permits redistribution of results.
- Test GBA Studio output.
- Publish resource, timing, and compatibility reports.

## Files in this scaffold

- `rtl/fpgba_platform_pkg.vhd` defines platform-facing types.
- `rtl/fpgba_tang60k_platform.vhd` implements reset, joypad mapping, and a stable shell for future core wiring.
- `sim/fpgba_tang60k_platform_tb.vhd` validates the shell behaviour.
- `constraints/tang_console_60k.cst.template` is deliberately unassigned until the exact carrier revision and schematic are confirmed.
- `build.tcl` checks prerequisites and refuses to label an incomplete port as a successful build.

## Completion criteria

The port is not "working" until all of these exist:

- a reproducible `.fs` build;
- no unconstrained clocks or I/O;
- timing closure on core, video, and memory clocks;
- post-fit resource report;
- DDR3 calibration and stress test;
- legal homebrew boot demonstration;
- documented audio, save, and input status;
- source commit and toolchain version.
