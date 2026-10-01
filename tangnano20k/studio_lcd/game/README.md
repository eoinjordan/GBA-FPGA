# Game folder

Copy the native Studio export `game.tang.bin` and its matching `build.json`
here. Keep exactly one `*.tang.bin`. Game binaries are ignored by Git.

From the repository root:

```sh
python scripts/gbafpga.py flash studio_lcd --port COM5 --tool gowin --cable-index 4 --location 289
```

Use your serial device on Linux/macOS. This programs the FPGA, uploads the
game, verifies its CRC and reports frame rate and CPU status. Use `--sram`
for a temporary FPGA test, `--dry-run` to inspect commands, or `--no-game`
to program just the platform. `--game PATH` selects another export folder.
The cable type and location above are the tested Windows setup. Obtain your
location with Gowin's `programmer_cli --scan-cables`; USB enumeration can change.

The game lives in SDRAM and needs another upload after power-off or FPGA
reprogramming. ARM `.gba` ROMs do not run on this RV32IM platform. Build the
same `.gbsproj` with Studio's Tang export instead.
