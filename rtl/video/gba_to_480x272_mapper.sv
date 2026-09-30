`timescale 1ns/1ps

// =============================================================================
// gba_to_480x272_mapper -- panel pixel -> GBA source pixel (aspect-correct fit)
// =============================================================================
// The GBA frame is 240x160 (3:2). The largest 3:2 rectangle that fits a
// 480x272 panel is 408x272 (scale 1.7), centred with 36-pixel side borders:
//
//   panel x:  0 ...... 35 | 36 ............... 443 | 444 ...... 479
//             border      |  408 px GBA image      |  border
//
//   source_x = floor((panel_x - 36) * 240 / 408) = floor(ix * 10 / 17)
//   source_y = floor( panel_y       * 160 / 272) = floor(iy * 10 / 17)
//
// Both axes share the same 10/17 ratio, so the divide-by-17 is done as a
// multiply by a fixed-point reciprocal instead of two hardware dividers:
//
//   floor(n * 10 / 17) == (n * 1205) >> 11      exact for every n in 0..407
//
// 1205/2048 = 0.588379 vs 10/17 = 0.588235. (1205, >>11) is the smallest exact
// pair; the testbench checks every pixel of the panel. Cost: two 9x11 constant
// multiplies (DSP or shift-add) instead of ~330 carry cells of long division.
//
// Nearest-neighbour result: of the 240 source columns, 168 are drawn two panel
// pixels wide and 72 one pixel wide (the same 7:3 mix vertically). This is the
// expected, sharpest non-integer scale; there is no blending.
//
// Purely combinational; register the outputs in the caller's pixel pipeline.
// source_x / source_y read 0 whenever source_active is low.
// =============================================================================
module gba_to_480x272_mapper (
    input  logic [8:0] panel_x,        // 0..479 while panel_active
    input  logic [8:0] panel_y,        // 0..271 while panel_active
    input  logic       panel_active,   // panel DE
    output logic       source_active,  // pixel lies inside the 408x272 image window
    output logic [7:0] source_x,       // 0..239
    output logic [7:0] source_y        // 0..159
);
    // ---- Geometry ----------------------------------------------------------------
    localparam integer PANEL_WIDTH  = 480;
    localparam integer IMAGE_WIDTH  = 408;
    localparam integer IMAGE_HEIGHT = 272;
    localparam integer BORDER_LEFT  = (PANEL_WIDTH - IMAGE_WIDTH) / 2;   // 36
    localparam logic [8:0]  BORDER_LEFT_9 = BORDER_LEFT[8:0];
    localparam logic [10:0] SCALE_Q11     = 11'd1205;                    // 10/17 in Q0.11

    // ---- Window test -------------------------------------------------------------
    logic in_window;
    assign in_window = panel_active &&
                       (panel_x >= BORDER_LEFT) &&
                       (panel_x <  BORDER_LEFT + IMAGE_WIDTH) &&
                       (panel_y <  IMAGE_HEIGHT);

    // ---- Scale by 10/17 (multiply + shift) ------------------------------------------
    // Products stay below 2^19 (407 * 1205 = 490,435), so bits [18:11] hold the
    // 8-bit result and bit 19 is always zero.
    logic [8:0]  image_x;
    /* verilator lint_off UNUSEDSIGNAL */   // only bits [18:11] of the products are the result
    logic [19:0] scaled_x;
    logic [19:0] scaled_y;
    /* verilator lint_on UNUSEDSIGNAL */

    assign image_x  = panel_x - BORDER_LEFT_9;
    assign scaled_x = image_x * SCALE_Q11;
    assign scaled_y = panel_y * SCALE_Q11;

    // ---- Outputs ----------------------------------------------------------------------
    assign source_active = in_window;
    assign source_x      = in_window ? scaled_x[18:11] : 8'd0;
    assign source_y      = in_window ? scaled_y[18:11] : 8'd0;
endmodule
