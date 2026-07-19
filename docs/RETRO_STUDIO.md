# Retro Studio relationship

Keep SNES Studio and GBA Studio as separate working editor repositories while defining a shared intermediate representation for future reuse.

```text
Retro Studio project model
  |-- SNES exporter -> PVSnesLib -> .sfc -> SNESTang
  |-- GBA exporter  -> GBA Engine/devkitARM -> .gba -> GBATang 60K
  `-- GB/GBC exporter -> GBDK/GBVM -> .gb/.gbc -> GBTang Nano 20K
```

Do not merge the editors before import/export parity and regression tests exist. The first shared features should be target capability reporting, ROM budgets, deterministic asset manifests and FPGA deployment profiles.
