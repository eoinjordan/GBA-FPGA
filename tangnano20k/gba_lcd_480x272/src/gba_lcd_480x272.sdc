// =============================================================================
// Timing constraints -- gba_lcd_480x272 (Gowin IDE and nextpnr)
// =============================================================================
// Two clocks: the 27 MHz crystal and the 9 MHz rPLL output. The only paths
// between them go through 2- and 3-flop synchronisers, so they are cut.
// The pixel domain's falling-edge output stage gives a half-period (55.5 ns)
// path from the stage-2 registers, which the tools check automatically.
// =============================================================================

create_clock -name clk_27m -period 37.037 [get_ports {clk_27m}]
create_clock -name clk_pix -period 111.111 [get_nets {clk_pix}]

set_clock_groups -asynchronous -group [get_clocks {clk_27m}] -group [get_clocks {clk_pix}]
