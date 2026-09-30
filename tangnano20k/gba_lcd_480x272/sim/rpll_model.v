`timescale 1ns/1ps

// =============================================================================
// rPLL (simulation model) -- behavioural stand-in for the Gowin rPLL primitive
// =============================================================================
// Simulation only; never add this file to a synthesis project. It measures
// the CLKIN period and produces CLKOUT = CLKIN * (FBDIV_SEL+1) / (IDIV_SEL+1)
// with a 50 % duty cycle. LOCK rises after 16 input clocks. CLKOUTP follows
// CLKOUT; CLKOUTD / CLKOUTD3 are not modelled (tied low).
// =============================================================================
module rPLL #(
    parameter FCLKIN           = "100.0",
    parameter DYN_IDIV_SEL     = "false",
    parameter IDIV_SEL         = 0,
    parameter DYN_FBDIV_SEL    = "false",
    parameter FBDIV_SEL        = 0,
    parameter DYN_ODIV_SEL     = "false",
    parameter ODIV_SEL         = 8,
    parameter PSDA_SEL         = "0000",
    parameter DYN_DA_EN        = "false",
    parameter DUTYDA_SEL       = "1000",
    parameter CLKOUT_FT_DIR    = 1'b1,
    parameter CLKOUTP_FT_DIR   = 1'b1,
    parameter CLKOUT_DLY_STEP  = 0,
    parameter CLKOUTP_DLY_STEP = 0,
    parameter CLKFB_SEL        = "internal",
    parameter CLKOUT_BYPASS    = "false",
    parameter CLKOUTP_BYPASS   = "false",
    parameter CLKOUTD_BYPASS   = "false",
    parameter DYN_SDIV_SEL     = 2,
    parameter CLKOUTD_SRC      = "CLKOUT",
    parameter CLKOUTD3_SRC     = "CLKOUT",
    parameter DEVICE           = "GW2AR-18C"
) (
    output reg        CLKOUT,
    output reg        LOCK,
    output wire       CLKOUTP,
    output wire       CLKOUTD,
    output wire       CLKOUTD3,
    input  wire       RESET,
    input  wire       RESET_P,
    input  wire       CLKIN,
    input  wire       CLKFB,
    input  wire [5:0] FBDSEL,
    input  wire [5:0] IDSEL,
    input  wire [5:0] ODSEL,
    input  wire [3:0] PSDA,
    input  wire [3:0] DUTYDA,
    input  wire [3:0] FDLY
);
    realtime last_edge = 0.0;
    realtime in_period = 0.0;
    integer  in_edges  = 0;

    initial begin
        CLKOUT = 1'b0;
        LOCK   = 1'b0;
    end

    // ---- Input period measurement and lock -------------------------------------------
    always @(posedge CLKIN) begin
        if (in_edges > 0) in_period = $realtime - last_edge;
        last_edge = $realtime;
        in_edges  = in_edges + 1;
        if (in_edges == 16) LOCK = 1'b1;
    end

    // ---- Output clock -------------------------------------------------------------------
    initial begin
        wait (in_edges >= 3);
        forever #(in_period * (IDIV_SEL + 1) / (FBDIV_SEL + 1) / 2.0) CLKOUT = ~CLKOUT;
    end

    assign CLKOUTP  = CLKOUT;
    assign CLKOUTD  = 1'b0;
    assign CLKOUTD3 = 1'b0;
endmodule
