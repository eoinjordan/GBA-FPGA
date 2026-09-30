// =============================================================================
// Timing constraints -- gba_lcd_480x272
// =============================================================================
// Two clocks: the 27 MHz crystal and the 9 MHz rPLL output. The only paths
// between them go through 2- and 3-flop synchronisers, so they are cut.
//
// The pixel clock is named by the rPLL output pin, as Sipeed's HDMI example
// does for its CLKDIV. A net name is not stable here: clk_pix also drives the
// lcd_dclk pin, and Gowin synthesis names that merged net after the port.
// =============================================================================

create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
create_clock -name clk_pix -period 111.111 [get_pins {u_rpll/CLKOUT}]

set_clock_groups -asynchronous -group [get_clocks {clk_27m}] -group [get_clocks {clk_pix}]

// ---- Open-source flow ----------------------------------------------------------
// nextpnr uses yosys net names and supports only create_clock, so
// scripts/gbafpga.py passes it the lines below (Gowin ignores comments).
// The crystal is constrained with nextpnr's --freq 27.
// nextpnr: create_clock -period 111.111 [get_nets {clk_pix}]
