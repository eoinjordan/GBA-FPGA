# GBA-FPGA top-level targets.
#
# Every target runs scripts/gbafpga.py, which works the same without make:
#   python3 scripts/gbafpga.py <command>        (Linux, macOS)
#   .\scripts\gbafpga.ps1 <command>             (Windows PowerShell)
# Written for GNU make 3.81 (the version macOS ships).

PYTHON  ?= $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)
GBAFPGA := $(PYTHON) scripts/gbafpga.py

.PHONY: all test lint doctor bootstrap tangnano20k gowin load flash gbtang snestang clean

# ---- Checks -----------------------------------------------------------------
all: test

# REQUIRE_GHDL=1 turns the skipped VHDL test into a failure (CI sets it).
test:
	$(GBAFPGA) test $(if $(REQUIRE_GHDL),--require-ghdl,)

lint:
	$(GBAFPGA) lint

doctor:
	$(GBAFPGA) doctor

bootstrap:
	$(GBAFPGA) bootstrap

# ---- Tang Nano 20K: GBA-FPGA LCD validation design ---------------------------
tangnano20k:
	$(GBAFPGA) build gba_lcd_480x272

gowin:
	$(GBAFPGA) build gba_lcd_480x272 --flow gowin

load:
	$(GBAFPGA) flash gba_lcd_480x272 --sram

flash:
	$(GBAFPGA) flash gba_lcd_480x272

# ---- Tang Nano 20K: upstream cores (Gowin EDA required to build) ---------------
gbtang:
	$(GBAFPGA) build gbtang

snestang:
	$(GBAFPGA) build snestang

clean:
	rm -rf build
