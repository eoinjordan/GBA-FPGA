# GBA cartridge reader

## Connector signals

The 32-pin GBA cartridge connector exposes:

- 3.3 V and ground;
- multiplexed `AD[15:0]` lower address/data;
- dedicated `A[23:16]` upper address;
- `/CS`, `/RD`, `/WR`, `/CS2`;
- clock and IRQ signals used by selected cartridge functions.

## Read sequence

For a conservative random 16-bit ROM read:

1. Drive the lower word address on `AD[15:0]` and upper address on `A[23:16]`.
2. Assert `/CS` so the cartridge latches the address.
3. Release the FPGA output enable on `AD[15:0]`.
4. Wait for bus turnaround.
5. Assert `/RD`.
6. Wait for cartridge access time.
7. Sample `AD[15:0]`.
8. Deassert `/RD` and `/CS`.
9. Wait for recovery before the next transaction.

The included reader repeats this full sequence for every halfword. It is slower than a burst reader but easier to validate safely.

## Electrical rules

- GBA cartridges use 3.3 V signalling.
- Never connect a 5 V MCU or FPGA bank directly.
- Never enable the FPGA output driver while the cartridge is driving data.
- Keep `/WR` and `/CS2` inactive during ROM-only testing.
- Add series resistors near the active driver to reduce contention current during faults.
- Add a current-limited 3.3 V supply and measure cartridge inrush.
- Insert and remove cartridges only with power off unless the final design explicitly supports hot insertion.

## Recommended companion-MCU architecture

An RP2350 or similar high-GPIO 3.3 V MCU can dump ROM and save data to SD or expose them over USB. This reduces FPGA pin pressure and isolates irreversible save writes from the core.

Reference projects should be used for save-memory support rather than guessing protocols. SRAM, Flash, and EEPROM require different address and command behaviour.

## Legal use

Use the reader for cartridges you own, homebrew, preservation, diagnostics, and save backup where lawful. Do not distribute copyrighted ROM images.
