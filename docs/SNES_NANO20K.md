# SNES on the Tang Nano 20K

SNESTang changes the project priority because it provides a practical 16-bit console target on the FPGA already owned.

## Preferred software-to-hardware proof

```text
SNES Studio project
  -> real PVSnesLib build
  -> .sfc ROM
  -> emulator validation
  -> repository ROM validator
  -> standalone SNESTang
  -> Tang Nano 20K
```

This is the strongest immediate deliverable: an original game created in SNES Studio running on a GBA-shaped FPGA handheld.

## ROM budget

The Nano 20K target is treated as accepting only ROM payloads smaller than 3.75 MiB. The repository validator uses a strict limit of 3,932,160 bytes and removes a detected 512-byte copier header when calculating payload size.

## Controls

A two-face-button GBA PCB is insufficient for normal SNES play. The handheld must expose:

- D-pad;
- A, B, X and Y;
- L and R;
- Start and Select;
- a dedicated Menu/OSD button where supported.

## Display

Use SNESTang's existing HDMI path for the first prototype. The ordered 480x272 panel remains a separate bring-up project until its exact controller, FPC pinout, I/O voltage, pixel timing and backlight specification are known.

## Storage

Use microSD first. A physical SNES cartridge connector is too large and electrically complex for the initial GBA-shaped handheld, and it adds 5 V compatibility, mapping, enhancement-chip and save-memory problems that do not improve the first demonstration.
