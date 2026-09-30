# GBATang on a Tang 60K board

[GBATang](https://github.com/nand2mario/gbatang) is the working GBA core for the
Tang Mega 60K and Tang Console 60K. Fetch it with
`python3 scripts/gbafpga.py bootstrap gbatang` and follow the TangCore/GBATang
instructions in `external/gbatang`; menu paths change between releases, so the
upstream README is the reference.

This repository builds GBA Studio projects to `.gba`
(`scripts/build-gba-studio-rom.sh`) and copies them to an SD card
(`scripts/prepare-sd.sh`).
