# Board matrix

| Board | Game Boy | SNES | GBA | Use here |
|---|---|---|---|---|
| Tang Nano 20K | GBTang (original Game Boy) | SNESTang v0.9, ROMs under 3.75 MiB | none | handheld prototype, LCD and controls |
| Tang Primer 25K | core-dependent | SNESTang | none | bench work with add-on modules |
| Tang Mega 60K | core-dependent | SNESTang | GBATang | full SNES and GBA development |
| Tang Console 60K | TangCore cores | SNESTang | GBATang | multi-core console or larger handheld |
| Terasic DE2-115 | separate cores | separate cores | FPGBA upstream | FPGBA reference and research |

## Why no GBA on the Nano 20K

FPGBA's published requirements exceed the Nano 20K's logic and block RAM, and
GBATang targets the larger Tang boards. Fitting a GBA would need a new memory
system and a reworked core, not a board wrapper.

## What the Nano 20K is good for

- GBTang and SNESTang (within the ROM-size limit);
- the 480x272 LCD, the button board, audio, power and the enclosure;
- SD-card loading and deployment manifests;
- cartridge-header experiments once the rest works.

## Before buying a 60K board

1. A GBA Studio `.gba` runs correctly in mGBA.
2. A SNES Studio `.sfc` runs on the Nano 20K.
3. The controls, power and enclosure constraints are known.
