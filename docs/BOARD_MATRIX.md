# Board matrix

| Board | GB/GBC | SNES | GBA | Recommended project |
|---|---:|---:|---:|---|
| Tang Nano 20K | GBTang | SNESTang, ROM payload smaller than 3.75 MiB | No practical current route | GBA-shaped GB/GBC/SNES handheld and peripheral bring-up |
| Tang Primer 25K | Core-dependent | SNESTang | No practical current route | Bench development with external modules |
| Tang Mega 60K | Core-dependent | SNESTang | GBATang | Full SNES/GBA development platform |
| Tang Console 60K | TangCore/individual cores | SNESTang | GBATang | Compact multi-core console or larger handheld base |
| Terasic DE2-115 | Separate cores | Separate cores | Upstream FPGBA | FPGBA research and reference validation |

## Why the Nano 20K does not fit the current GBA route

Upstream FPGBA reports requirements beyond the Nano 20K's logic and block-memory budget, while GBATang targets larger Tang devices. Porting a full GBA implementation to the Nano would require a substantial memory-system and core-architecture redesign rather than a board wrapper.

## Correct use of the Nano 20K

The Nano 20K is now the primary immediate board because it can validate:

- GBTang GB/GBC operation;
- SNESTang SNES operation within the Nano ROM-size limit;
- a four-face-button handheld control PCB;
- SD-card loading and deployment manifests;
- audio, power and enclosure integration;
- HDMI display operation;
- cartridge-header and raw-panel experiments after the software-to-FPGA path is stable.

## Board purchase gate

Buy or commit to Tang 60K hardware only after:

1. a real GBA Studio `.gba` passes emulator validation;
2. a real SNES Studio `.sfc` runs on the Nano 20K;
3. the reusable controls, power and enclosure constraints are known.
