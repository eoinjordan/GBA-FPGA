# FPGBA Tang 60K port scaffold

This directory is the platform boundary for a future FPGBA port to GW5AT-LV60 hardware.

It is not a verified build.

## Current contents

- A VHDL package defining stable platform-facing types.
- A shell implementing reset release and active-low keypad mapping.
- A self-checking VHDL testbench.
- A constraint template with no fabricated pin assignments.
- A build script that checks for upstream source and stops with the remaining milestones.

## Required external source

Run `scripts/bootstrap.sh` or `scripts/bootstrap.ps1` from the repository root. Upstream FPGBA will be placed at `external/FPGBA`.

## Next implementation task

Create a synthesizable adapter around upstream `gba_top.vhd` with explicit interfaces for:

- ROM read request/response;
- save-memory request/response;
- video pixel output;
- signed audio samples;
- keypad state;
- core pause/reset/turbo controls.

Do not connect vendor DDR3 primitives directly inside the core. Keep the memory controller in the platform layer.
