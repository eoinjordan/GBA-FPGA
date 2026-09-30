# Wenting Zhang PaperBoy S3 — technical dialogue notes

These are original paraphrased notes, not a verbatim transcript. They are based on the linked Wenting Channel video and the creator's accompanying Hackster project write-up.

## Project premise

Wenting Zhang obtained an M5PaperS3, an ESP32-S3 development kit with a 4.7-inch 960x540 e-ink touchscreen. The unusual feature was access to the panel's raw row/column drive interface rather than only a slow high-level SPI refresh controller. That made it possible to bypass conventional full-screen waveform updates.

The design question was not merely whether an ESP32 could run a Game Boy emulator. The real question was whether the display could accept sufficiently frequent image changes to make the result playable.

## E-ink refresh strategy

A pigment transition may require roughly 100 ms of drive time, but that does not require accepting a new frame only once every 100 ms. The project distributes each pixel's drive state across multiple 60 Hz frames. New image data can enter every frame while a per-pixel state buffer tracks the remaining drive sequence.

This removes the global frame lock at the cost of memory bandwidth and state storage. The Game Boy's small 160x144 image makes the trade practical. The project scales the image and processes only the active game area rather than all 960x540 pixels.

The display engine uses the ESP32-S3 LCD interface and DMA. One core manages the e-ink processing and timing while double buffering gives the emulator a 60 Hz presentation boundary.

## Emulator selection

The project evaluated Peanut GB, Walnut CGB, and CrankBoy. CrankBoy was selected because its Playdate-oriented optimisation work reduced expensive emulated memory-mapping overhead.

Dynamic frame skipping allows the emulator to catch up when CPU emulation falls behind. Many games run at approximately full game speed, while rendered frame rate varies with workload. Full Game Boy Color operation is more demanding because double-speed mode raises CPU requirements.

## Sound

The PaperS3 exposes a buzzer rather than a normal audio codec. Straight PCM or PDM output was too quiet. The alternative was to approximate the Game Boy's four sound channels as rapidly multiplexed tones on a single buzzer. The result is recognisable and loud, but deliberately unlike accurate Game Boy audio.

The sound workload was moved to the second core so that it did not consume the emulator's main execution budget.

## Input and saves

Touchscreen controls are sufficient for demonstration. Experimental BLE controller support guesses common report layouts rather than implementing a complete HID stack, so compatibility is limited.

Save persistence is difficult because the device's power switch cuts power directly. The emulator cannot rely on a graceful shutdown callback. An explicit save control flushes cartridge RAM to SD and also supports quick save/load.

## Relevance to GBA-FPGA

The PaperBoy works because the display strategy was designed around the panel's
limits and a small frame (160x144). The same applies here: the 480x272 panel
timing, scaling and frame buffer size decide what the Nano 20K can show, and
save handling has to cope with power being cut without warning.
