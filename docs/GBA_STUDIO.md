# GBA Studio and GBA Engine integration

GBA Studio is the editor and compiler; GBA Engine is the C runtime linked into the ROM it produces. Their output is an ordinary `.gba` image.

## Development flow

```text
project.gbsproj
      |
      v
GBA Studio compiler
      |
      +--> generated assets and scene data
      +--> GBA Engine runtime
      |
      v
devkitARM / libgba
      |
      v
game.gba
```

Validate every generated ROM in three stages:

1. mGBA or another development emulator with logs enabled.
2. GBATang on Tang 60K.
3. Real GBA hardware or a flash cartridge where available.

A bug that shows up in all three is in the game or runtime; one that appears only on an FPGA core is more likely a core compatibility or timing issue.

## Build scripts

The build scripts run GBA Studio's command-line build:

```text
npm ci                         # first run only
npm run fetch-deps
npm run make:cli
node out/cli/gb-studio-cli.js make:rom project.gbsproj game.gba
```

They check for Node and npm, build the CLI bundle, run `make:rom`, and fail unless the `.gba` file was written. GBA Studio needs Node.js 20 or newer and devkitPro with devkitARM. Fetch GBA Studio first with `python3 scripts/gbafpga.py bootstrap gba-studio`.

## Test ROM policy

Keep a dedicated homebrew hardware-validation ROM that exercises:

- Mode 0 backgrounds;
- sprites and priority;
- affine transforms when supported;
- DMA;
- timers;
- keypad input;
- sound channels;
- SRAM/Flash/EEPROM save paths;
- reset and warm boot.

Do not use commercial ROMs in public CI artifacts.
