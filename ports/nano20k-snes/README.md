# SNESTang on Tang Nano 20K

This directory documents the practical SNES path for the Tang Nano 20K. It does not vendor or modify SNESTang.

## Scope

- Use the standalone upstream SNESTang Nano 20K release or build.
- Load legal homebrew `.sfc`/`.smc` images from microSD.
- Enforce the upstream Nano 20K rule that ROM payloads must be smaller than 3.75 MiB.
- Validate a custom four-face-button PCB with A, B, X and Y.
- Reuse the same enclosure, power, audio and display work for a later 60K GBA board.

## Commands

```bash
python3 scripts/validate-snes-rom.py build/game.sfc
python3 scripts/prepare-snestang-sd.py build/game.sfc /media/$USER/SD
```

The SD directory layout is configurable because upstream release conventions can change:

```bash
python3 scripts/prepare-snestang-sd.py build/game.sfc /media/$USER/SD --rom-dir snes
```

## Non-goals

- No SNESTang source or bitstream is copied into this repository.
- No commercial ROM is included.
- The Nano 20K path is not a GBA implementation.
