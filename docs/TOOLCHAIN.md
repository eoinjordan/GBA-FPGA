# Toolchain

`scripts/gbafpga.py` drives everything and needs only Python 3.8 or newer.
Run `doctor` after installing to see what it finds:

```bash
python3 scripts/gbafpga.py doctor          # Linux, macOS
```

```powershell
.\scripts\gbafpga.ps1 doctor               # Windows
```

| Task | Needs |
|---|---|
| `test` | Icarus Verilog (`iverilog`, `vvp`); GHDL for the VHDL scaffold test (skipped if missing) |
| `lint` | Verilator |
| `build gba_lcd_480x272` (open flow) | `yosys`, `nextpnr-himbaechel`, `gowin_pack` |
| `build` with Gowin, any project | Gowin EDA (Windows or Linux only) |
| `flash` | `openFPGALoader`, or Gowin Programmer |
| `ide-project` | Python's Tcl support (`tkinter`) |

[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build/releases) contains
every open-source tool above (Icarus, GHDL on Linux, Verilator, yosys, nextpnr,
apicula's `gowin_pack`, openFPGALoader). The helper uses it from `PATH`, from
`$OSS_CAD_SUITE`, or from `~/oss-cad-suite` (`%USERPROFILE%\oss-cad-suite` on
Windows), so unpacking it there is enough.

## Linux

```bash
sudo apt install python3 iverilog ghdl            # enough for `test`
```

For `lint`, the open-source build and flashing, unpack OSS CAD Suite to
`~/oss-cad-suite`. openFPGALoader needs USB access: install the udev rules from
the openFPGALoader documentation (or run it with `sudo`).

Gowin EDA for Linux: unpack it and either set `GOWIN_HOME` to the folder that
contains `IDE/` or keep it under `~/` or `/opt/`, where the helper looks.

## macOS

```bash
xcode-select --install                             # python3 (or: brew install python)
brew install icarus-verilog openfpgaloader         # `test` and `flash`
```

OSS CAD Suite has macOS builds (Intel and Apple silicon) for `lint` and the
open-source build. There is no Gowin EDA for macOS, so:

- `gba_lcd_480x272` builds with the open-source flow;
- GBTang and SNESTang use the release bitstreams: `fetch`, then `flash`.

## Windows

- Python from python.org (tick "Add python.exe to PATH"). `scripts\gbafpga.ps1`
  uses the `py` launcher and skips the Microsoft Store stubs.
- OSS CAD Suite: unpack to `%USERPROFILE%\oss-cad-suite`.
- Gowin EDA: installed to `C:\Gowin\...` it is found automatically; otherwise
  set `GOWIN_HOME` or pass `--gowin`.
- `make` is optional; every target is a `gbafpga.ps1` command.

Flashing on Windows: Gowin Programmer works with the board's standard driver
(`flash --tool gowin`). openFPGALoader needs a libusb driver (WinUSB, installed
with Zadig) on the debugger's first interface, and Gowin Programmer cannot use
the board while that driver is attached.

## Gowin EDA versions

Several versions can be installed side by side; `build` picks the one each
project was released with, or the one given by `--gowin`.

| Project | Upstream builds with | Notes |
|---|---|---|
| `gbtang` | 1.9.9 | GBTang's README asks for the Standard edition (free licence) |
| `snestang` | 1.9.10.03 | upstream notes that 1.9.11.01 breaks Mode 7 |
| `gba_lcd_480x272` | 1.9.9 or newer | untested with Gowin so far; the open-source flow is tested |
