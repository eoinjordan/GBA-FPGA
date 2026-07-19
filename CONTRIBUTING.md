# Contributing

Contributions should preserve the distinction between a verified hardware target and an unverified port scaffold.

## Required evidence for board-support claims

A pull request claiming a new FPGA target works should include:

1. The exact board and FPGA part number.
2. Toolchain and version.
3. Reproducible build commands.
4. Timing report with the failing and passing clocks identified.
5. Resource-utilisation report.
6. A legal homebrew or test ROM used for validation.
7. Photographs or captured video of the generated bitstream running.
8. Known failures and unsupported peripherals.

## Code requirements

- Add or update a self-checking testbench for RTL changes.
- Do not add BIOS images, commercial ROMs, or copyrighted assets.
- Keep platform-specific logic outside the reusable cartridge, input, and video modules.
- Use explicit clock-domain crossings.
- Document external-voltage requirements and bus ownership.

## Commit format

Use imperative subjects such as:

```text
Add Tang 60K SDRAM bridge
Fix cartridge AD bus turn-around
Document 480x272 panel timings
```
