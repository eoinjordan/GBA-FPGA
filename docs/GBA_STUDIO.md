# GBA Studio and GBA Engine integration

GBA Studio is the authoring/compiler layer. GBA Engine is the C runtime linked into the generated ROM. Their output boundary is a normal `.gba` image.

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

A failure in all three environments probably belongs in the game/runtime. A failure only on one FPGA core is more likely a hardware-compatibility or timing issue.

## Build scripts

The scripts implement GBA Studio's documented CLI build path in full:

```text
npm ci                         # first run only
npm run fetch-deps
npm run make:cli
node out/cli/gb-studio-cli.js make:rom project.gbsproj game.gba
```

The wrapper scripts validate Node/npm, build the CLI bundle, invoke `make:rom`, and refuse success unless the requested `.gba` file exists. Node.js 20 or newer and devkitPro/devkitARM are required by GBA Studio.

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
