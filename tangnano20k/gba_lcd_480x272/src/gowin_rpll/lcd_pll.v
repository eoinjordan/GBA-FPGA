`timescale 1ns/1ps

// =============================================================================
// lcd_pll -- 27 MHz crystal -> 9 MHz LCD pixel clock (Gowin rPLL, GW2AR-18C)
// =============================================================================
// Direct instantiation of the rPLL primitive (Gowin UG286), usable unchanged
// by Gowin IDE and by yosys/nextpnr-himbaechel.
//
//   CLKOUT = FCLKIN * (FBDIV_SEL + 1) / (IDIV_SEL + 1) = 27 * 1 / 3 = 9 MHz
//   PFD    = FCLKIN / (IDIV_SEL + 1)                   = 9 MHz
//   VCO    = CLKOUT * ODIV_SEL                         = 9 * 64 = 576 MHz
//
// 9 MHz is the NV3047 "Typ." DCLK (8-12 MHz allowed) and the value Sipeed's
// Nano 20K 480x272 samples use. LOCK is high once the output is stable; the
// top level holds the pixel domain in reset until then.
// =============================================================================
module lcd_pll (
    input  wire clk_in,       // 27 MHz crystal (pin 4)
    output wire clk_out,      // 9 MHz pixel clock
    output wire locked
);
    wire unused_clkoutp;
    wire unused_clkoutd;
    wire unused_clkoutd3;

    rPLL #(
        .FCLKIN          ("27"),
        .DYN_IDIV_SEL    ("false"),
        .IDIV_SEL        (2),          // divide input by 3
        .DYN_FBDIV_SEL   ("false"),
        .FBDIV_SEL       (0),          // multiply by 1
        .DYN_ODIV_SEL    ("false"),
        .ODIV_SEL        (64),         // VCO / 64 = CLKOUT
        .PSDA_SEL        ("0000"),
        .DYN_DA_EN       ("false"),
        .DUTYDA_SEL      ("1000"),
        .CLKOUT_FT_DIR   (1'b1),
        .CLKOUTP_FT_DIR  (1'b1),
        .CLKOUT_DLY_STEP (0),
        .CLKOUTP_DLY_STEP(0),
        .CLKFB_SEL       ("internal"),
        .CLKOUT_BYPASS   ("false"),
        .CLKOUTP_BYPASS  ("false"),
        .CLKOUTD_BYPASS  ("false"),
        .DYN_SDIV_SEL    (2),
        .CLKOUTD_SRC     ("CLKOUT"),
        .CLKOUTD3_SRC    ("CLKOUT"),
        .DEVICE          ("GW2AR-18C")
    ) u_rpll (
        .CLKOUT  (clk_out),
        .LOCK    (locked),
        .CLKOUTP (unused_clkoutp),
        .CLKOUTD (unused_clkoutd),
        .CLKOUTD3(unused_clkoutd3),
        .RESET   (1'b0),
        .RESET_P (1'b0),
        .CLKIN   (clk_in),
        .CLKFB   (1'b0),
        .FBDSEL  (6'b000000),
        .IDSEL   (6'b000000),
        .ODSEL   (6'b000000),
        .PSDA    (4'b0000),
        .DUTYDA  (4'b0000),
        .FDLY    (4'b0000)
    );
endmodule
