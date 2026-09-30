# gba_lcd_480x272 shortcuts; each runs ../../scripts/gbafpga.py (see README.md).

PYTHON  ?= $(shell command -v python3 2>/dev/null || command -v python 2>/dev/null)
GBAFPGA := $(PYTHON) ../../scripts/gbafpga.py

.PHONY: all bitstream gowin load flash test

all: bitstream

# Open-source flow: yosys -> nextpnr-himbaechel -> gowin_pack
bitstream:
	$(GBAFPGA) build gba_lcd_480x272 --flow open

# Gowin EDA command-line flow (gw_sh), same sources as the .gprj
gowin:
	$(GBAFPGA) build gba_lcd_480x272 --flow gowin

# SRAM load (quick, lost at power-off) / SPI flash (persistent)
load:
	$(GBAFPGA) flash gba_lcd_480x272 --sram

flash:
	$(GBAFPGA) flash gba_lcd_480x272

# All testbenches, including this design's end-to-end simulation
test:
	$(GBAFPGA) test
