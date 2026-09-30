`timescale 1ns/1ps

// =============================================================================
// rgb_lcd_timing -- raster timing generator for parallel-RGB ("TTL") TFT panels
// =============================================================================
// Produces DE / HSYNC / VSYNC framing plus the raster position for a panel
// that takes one pixel per DCLK.
//
// Line layout in pixel clocks (the frame uses the same order, in lines):
//
//   h_count: 0 ........ H_ACTIVE-1 | H_FRONT | H_SYNC | H_BACK |
//            DE = 1 (visible)      | blank   | HSYNC  | blank  |
//
// Starting each line/frame with the visible area means pixel_x == h_count and
// pixel_y == v_count, so no offset subtraction is needed downstream.
//
// Default profile: HT043IBB-16A3047-H4 (4.3" 480x272, NV3047 driver), the
// "Typ." column of the NV3047 input-timing table:
//
//   Thbp = H_SYNC + H_BACK = 4 + 39 = 43 DCLK  (sync leading edge -> 1st pixel)
//   Thfp = 8,  Thw = 4,  Th = 531 DCLK
//   Tvbp = V_SYNC + V_BACK = 4 + 8  = 12 lines,  Tvfp = 8,  Tvw = 4,  Tv = 292
//   9 MHz DCLK -> 9e6 / (531 * 292) = 58.05 Hz
//
// The datasheet asks for exactly these values in SYNC mode; in DE mode only DE
// matters. Driving DE *and* both syncs (SYNC-DE mode) is correct in all three.
// The previous profile (H 2/41/2, V 2/10/2, 525x286, Sipeed's 480x272 sample)
// also gives Thbp = 43 / Tvbp = 12 and remains valid by overriding parameters.
//
// Outputs are registered: they are glitch-free on the pins and, in any given
// cycle, all six describe the same raster position (latency: 1 clock after
// the internal counters). pixel_x / pixel_y are the raw counters: they keep
// counting through blanking, so qualify them with lcd_de.
// =============================================================================
module rgb_lcd_timing #(
    parameter integer H_ACTIVE     = 480,
    parameter integer H_FRONT      = 8,
    parameter integer H_SYNC       = 4,
    parameter integer H_BACK       = 39,
    parameter integer V_ACTIVE     = 272,
    parameter integer V_FRONT      = 8,
    parameter integer V_SYNC       = 4,
    parameter integer V_BACK       = 8,
    parameter         HSYNC_ACTIVE = 1'b0,  // level driven during the sync pulse
    parameter         VSYNC_ACTIVE = 1'b0
) (
    input  logic        pixel_clk,
    input  logic        rst_n,
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic [11:0] pixel_x,
    output logic [11:0] pixel_y,
    output logic        frame_start         // high with the first visible pixel (0,0)
);
    // ---- Derived geometry ------------------------------------------------------
    localparam integer H_TOTAL  = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL  = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam integer H_BITS   = (H_TOTAL <= 2) ? 1 : $clog2(H_TOTAL);
    localparam integer V_BITS   = (V_TOTAL <= 2) ? 1 : $clog2(V_TOTAL);
    localparam integer HS_START = H_ACTIVE + H_FRONT;   // sync windows are [start, end)
    localparam integer HS_END   = HS_START + H_SYNC;
    localparam integer VS_START = V_ACTIVE + V_FRONT;
    localparam integer VS_END   = VS_START + V_SYNC;

    // ---- Raster counters -------------------------------------------------------
    // h_count wraps every line; v_count advances once per line and wraps per frame.
    logic [H_BITS-1:0] h_count;
    logic [V_BITS-1:0] v_count;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_count <= '0;
            v_count <= '0;
        end else if (h_count == H_TOTAL - 1) begin
            h_count <= '0;
            v_count <= (v_count == V_TOTAL - 1) ? '0 : v_count + 1'b1;
        end else begin
            h_count <= h_count + 1'b1;
        end
    end

    // ---- Registered panel outputs -------------------------------------------------
    // Decoded from the counters and registered together, so the pins never see
    // decode glitches and DE, syncs and coordinates stay mutually aligned.
    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            lcd_de      <= 1'b0;
            lcd_hsync   <= ~HSYNC_ACTIVE;
            lcd_vsync   <= ~VSYNC_ACTIVE;
            pixel_x     <= 12'd0;
            pixel_y     <= 12'd0;
            frame_start <= 1'b0;
        end else begin
            lcd_de      <= (h_count < H_ACTIVE) && (v_count < V_ACTIVE);
            lcd_hsync   <= ((h_count >= HS_START) && (h_count < HS_END)) ? HSYNC_ACTIVE : ~HSYNC_ACTIVE;
            lcd_vsync   <= ((v_count >= VS_START) && (v_count < VS_END)) ? VSYNC_ACTIVE : ~VSYNC_ACTIVE;
            pixel_x     <= h_count;     // zero-extended
            pixel_y     <= v_count;
            frame_start <= (h_count == 0) && (v_count == 0);
        end
    end
endmodule
