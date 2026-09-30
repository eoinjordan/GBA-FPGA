# Retro Studio relationship

SNES Studio and GBA Studio stay separate editors for now; a shared project model can come later.

```text
Retro Studio project model
  |-- SNES exporter -> PVSnesLib -> .sfc -> SNESTang
  |-- GBA exporter  -> GBA Engine/devkitARM -> .gba -> GBATang 60K
  `-- GB exporter   -> GBDK/GBVM -> .gb -> GBTang on the Nano 20K
```

Merging the editors should wait until import/export matches and regression tests exist. Useful things to share first: per-target capabilities, ROM budgets (the Nano 20K limits are in `tools/snes_rom.py` and `tools/gb_rom.py`), asset manifests and deployment profiles.
