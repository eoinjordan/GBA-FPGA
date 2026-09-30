# Notices and upstream licences

This repository contains original integration code, documentation, scripts, and testbenches by Eoin Jordan and contributors.

It does not vendor the source code of the upstream FPGA cores or emulators. The bootstrap scripts clone those projects into the ignored `external/` directory. `tangnano20k/gbtang` and `tangnano20k/snestang` contain only generated Gowin project files that point at those checkouts.

The Tang Nano 20K pin assignments follow Sipeed's TangNano-20K-example constraint files. The LCD timing figures come from the NV3047 module specification listed in `docs/SOURCES.md`.

Important upstream licences include:

- Kitrinx/FPGBA — GPL-2.0.
- nand2mario/gbatang — GPL-3.0.
- nand2mario/snestang — GPL-3.0.
- fjpolo/GBTang — GPL-3.0, with its VerilogBoy and OSTang submodules under their own licences.
- zephray/paperboy — consult the upstream repository for the current licence.
- zephray/VerilogBoy — consult the upstream repository for the current licence.
- GBA Studio and GBA Engine — consult each upstream repository.

Nintendo, Game Boy, Game Boy Color, and Game Boy Advance are trademarks of Nintendo. This project is unaffiliated with and not endorsed by Nintendo.

Do not distribute copyrighted BIOS images or commercial ROM images with this repository.
