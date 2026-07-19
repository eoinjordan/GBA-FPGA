# Tip: A GBA-shaped FPGA handheld, with an honest 20K/60K split

I am building a GBA-shaped open FPGA handheld around my GBA Studio and GBA Engine homebrew toolchain.

The first result was discovering that the Tang Nano 20K is a useful handheld-development board but not a credible target for the available FPGBA core. The Nano provides 20,736 LUT4s and 828 Kbit of block RAM; FPGBA reports roughly 26,000 logic elements and 2 Mbit of on-chip RAM before framebuffer and board peripherals.

The project therefore has two tracks:

- Tang Nano 20K + GBTang for a working GB/GBC handheld and peripheral bring-up.
- Tang 60K + GBATang for a working GBA handheld, with a separate FPGBA VHDL port workbench.

The repository also includes a conservative ROM-only GBA cartridge reader, an aspect-ratio-preserving 240x160-to-480x272 display mapper, LCD timing code, button debouncing, GBA Studio build scripts, and a companion-RP2350 cartridge architecture.

The design approach was influenced by Wenting Zhang's 60 Hz PaperBoy S3: identify the hard peripheral constraint, match the workload geometry to it, reuse the mature core, and state the compromises rather than calling a scaffold a finished build.

No BIOS or commercial ROMs are included.
