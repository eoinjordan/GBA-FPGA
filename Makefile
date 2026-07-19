SHELL := /bin/bash
BUILD_DIR := build/tests
GHDL_DIR := build/ghdl

.PHONY: all test test-python test-cart test-buttons test-video test-video-mapper test-lcd test-vhdl clean verify

all: test

test: verify test-python test-cart test-buttons test-video test-vhdl

test-python:
	python3 -m unittest discover -s tests -v

verify:
	@command -v iverilog >/dev/null 2>&1 || { echo "ERROR: iverilog is required"; exit 1; }
	@command -v vvp >/dev/null 2>&1 || { echo "ERROR: vvp is required"; exit 1; }
	@command -v ghdl >/dev/null 2>&1 || { echo "ERROR: ghdl is required"; exit 1; }
	@mkdir -p $(BUILD_DIR) $(GHDL_DIR)

test-cart:
	iverilog -g2012 -Wall -s gba_cart_rom_reader_tb -o $(BUILD_DIR)/gba_cart_reader \
		rtl/cart/gba_cart_rom_reader.sv \
		rtl/cart/gba_cart_rom_reader_tb.sv
	vvp $(BUILD_DIR)/gba_cart_reader

test-buttons:
	iverilog -g2012 -Wall -s gba_buttons_tb -o $(BUILD_DIR)/gba_buttons \
		rtl/input/button_debouncer.sv \
		rtl/input/gba_buttons.sv \
		rtl/input/gba_buttons_tb.sv
	vvp $(BUILD_DIR)/gba_buttons

test-video: test-video-mapper test-lcd

test-video-mapper:
	iverilog -g2012 -Wall -s gba_to_480x272_mapper_tb -o $(BUILD_DIR)/gba_video_mapper \
		rtl/video/gba_to_480x272_mapper.sv \
		rtl/video/gba_to_480x272_mapper_tb.sv
	vvp $(BUILD_DIR)/gba_video_mapper

test-lcd:
	iverilog -g2012 -Wall -s rgb_lcd_timing_tb -o $(BUILD_DIR)/rgb_lcd_timing \
		rtl/video/rgb_lcd_timing.sv \
		rtl/video/rgb_lcd_timing_tb.sv
	vvp $(BUILD_DIR)/rgb_lcd_timing

test-vhdl:
	cd $(GHDL_DIR) && ghdl -a --std=08 ../../ports/fpgba-tang60k/rtl/fpgba_platform_pkg.vhd
	cd $(GHDL_DIR) && ghdl -a --std=08 ../../ports/fpgba-tang60k/rtl/fpgba_tang60k_platform.vhd
	cd $(GHDL_DIR) && ghdl -a --std=08 ../../ports/fpgba-tang60k/sim/fpgba_tang60k_platform_tb.vhd
	cd $(GHDL_DIR) && ghdl -e --std=08 fpgba_tang60k_platform_tb
	cd $(GHDL_DIR) && ghdl -r --std=08 fpgba_tang60k_platform_tb --assert-level=error --stop-time=200ns

clean:
	rm -rf build
