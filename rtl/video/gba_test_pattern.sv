`timescale 1ns/1ps

// =============================================================================
// gba_test_pattern -- procedural 240x160 "virtual GBA screen" for bring-up
// =============================================================================
// Stands in for a GBA/GB core's frame buffer during display validation. It is
// driven by the mapper's source coordinates, so everything it draws goes
// through the same scaling path a real core's pixels would.
//
// Colours are GBA-native BGR555: {blue[14:10], green[9:5], red[4:0]}.
//
//   pattern 0  CALIBRATION  8 colour bars (white..black) over rows 0-111, then
//                           5-bit red / green / blue ramps (16 rows each).
//                           A 1-px outline of the 240x160 frame is drawn in the
//                           inverse of the underlying colour so every edge is
//                           visible; the panel border is dark grey so the full
//                           480x272 area and the 36-px side bars can be checked.
//   pattern 1  GEOMETRY     8x8 checkerboard (GBA tile size) with a red centre
//                           crosshair and the inverted outline. Tile widths of
//                           13/14 panel pixels show the 1.7x nearest-neighbour
//                           scale; the crosshair shows centring.
//   pattern 2  MOTION       16x16 sprite bouncing at 1 px/frame over a vertical
//                           gradient. Smooth, tear-free motion confirms frame
//                           timing; the sprite's width wobbles 27/28 px by design.
//   pattern 3  PURITY       Full-panel solid colour, stepping through white, red,
//                           green, blue, cyan, magenta, yellow, black every
//                           32 frames: dead/stuck pixel and backlight check.
//
// The colour output is combinational (register it in the pixel pipeline); the
// only state is the sprite position, updated once per frame.
// =============================================================================
module gba_test_pattern (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        frame_start,     // one-cycle pulse at pixel (0,0) of each frame
    /* verilator lint_off UNUSEDSIGNAL */ // only frame_count[7:5] is used
    input  logic [7:0]  frame_count,     // free-running frame counter (colour cycling)
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [1:0]  pattern_sel,
    input  logic        source_active,   // inside the 240x160 image window
    input  logic [7:0]  source_x,        // 0..239
    input  logic [7:0]  source_y,        // 0..159
    output logic [14:0] color_bgr555
);
    // ---- Constants and colour helpers --------------------------------------------
    localparam integer SRC_W       = 240;
    localparam integer SRC_H       = 160;
    localparam integer SPRITE_SIZE = 16;
    localparam integer SPRITE_MAX_X = SRC_W - SPRITE_SIZE;       // 224
    localparam integer SPRITE_MAX_Y = SRC_H - SPRITE_SIZE;       // 144

    function automatic logic [14:0] bgr(input logic [4:0] r, input logic [4:0] g, input logic [4:0] b);
        bgr = {b, g, r};
    endfunction

    localparam logic [14:0] WHITE     = {5'd31, 5'd31, 5'd31};
    localparam logic [14:0] YELLOW    = {5'd0,  5'd31, 5'd31};
    localparam logic [14:0] CYAN      = {5'd31, 5'd31, 5'd0 };
    localparam logic [14:0] GREEN     = {5'd0,  5'd31, 5'd0 };
    localparam logic [14:0] MAGENTA   = {5'd31, 5'd0,  5'd31};
    localparam logic [14:0] RED       = {5'd0,  5'd0,  5'd31};
    localparam logic [14:0] BLUE      = {5'd31, 5'd0,  5'd0 };
    localparam logic [14:0] BLACK     = 15'd0;
    localparam logic [14:0] GREY_DARK = {5'd6,  5'd6,  5'd6 };
    localparam logic [14:0] TILE_LITE = {5'd22, 5'd22, 5'd22};
    localparam logic [14:0] TILE_DARK = {5'd12, 5'd8,  5'd8 };

    // ---- Sprite motion (pattern 2) ------------------------------------------------
    // Updated on frame_start. The first pixel inside the image window is panel
    // column 36, so every visible pixel of a frame sees the same position.
    logic [7:0] sprite_x;
    logic [7:0] sprite_y;
    logic       sprite_right;
    logic       sprite_down;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sprite_x     <= 8'd40;
            sprite_y     <= 8'd24;
            sprite_right <= 1'b1;
            sprite_down  <= 1'b1;
        end else if (frame_start) begin
            if (sprite_right ? (sprite_x == SPRITE_MAX_X) : (sprite_x == 8'd0)) begin
                sprite_right <= ~sprite_right;
                sprite_x     <= sprite_right ? sprite_x - 8'd1 : sprite_x + 8'd1;
            end else begin
                sprite_x     <= sprite_right ? sprite_x + 8'd1 : sprite_x - 8'd1;
            end

            if (sprite_down ? (sprite_y == SPRITE_MAX_Y) : (sprite_y == 8'd0)) begin
                sprite_down <= ~sprite_down;
                sprite_y    <= sprite_down ? sprite_y - 8'd1 : sprite_y + 8'd1;
            end else begin
                sprite_y    <= sprite_down ? sprite_y + 8'd1 : sprite_y - 8'd1;
            end
        end
    end

    // ---- Shared pixel features ----------------------------------------------------
    // 5-bit ramp across the width: (x * 17) >> 7 maps 0..239 onto 0..31, each
    // level 7-8 source pixels wide.
    /* verilator lint_off UNUSEDSIGNAL */   // low product bits and the sprite
    logic [11:0] ramp_product;             // offsets' low nibbles are unused
    logic [4:0]  ramp_level;
    assign ramp_product = {source_x, 4'b0000} + {4'b0000, source_x};
    assign ramp_level   = ramp_product[11:7];

    // Vertical gradient for the motion background: (y * 25) >> 7 maps 0..159 onto 0..31.
    logic [12:0] sky_product;
    logic [4:0]  sky_level;
    assign sky_product = {source_y, 4'b0000} + {1'b0, source_y, 3'b000} + {5'b00000, source_y};
    assign sky_level   = sky_product[11:7];

    logic on_outline;      // outermost row/column of the 240x160 frame
    logic on_crosshair;    // 2-px lines through the centre of the frame
    logic in_sprite;
    logic tile_light;      // 8x8 checkerboard phase
    logic [7:0] sprite_dx;
    logic [7:0] sprite_dy;
    /* verilator lint_on UNUSEDSIGNAL */
    assign on_outline   = (source_x == 8'd0) || (source_x == SRC_W - 1) ||
                          (source_y == 8'd0) || (source_y == SRC_H - 1);
    assign on_crosshair = (source_x == 8'd119) || (source_x == 8'd120) ||
                          (source_y == 8'd79)  || (source_y == 8'd80);
    // In the sprite when 0 <= x - sprite_x < 16 on both axes. With 8-bit
    // wrap-around a pixel left of/above the sprite gives a difference >= 16,
    // so one subtract and a 4-bit zero test replace two comparisons per axis.
    assign sprite_dx    = source_x - sprite_x;
    assign sprite_dy    = source_y - sprite_y;
    assign in_sprite    = (sprite_dx[7:4] == 4'd0) && (sprite_dy[7:4] == 4'd0);
    assign tile_light   = source_x[3] ^ source_y[3];

    // ---- Pattern 0: colour bars and ramps -------------------------------------------
    logic [14:0] bar_color;
    always_comb begin
        if      (source_x <  8'd30)  bar_color = WHITE;
        else if (source_x <  8'd60)  bar_color = YELLOW;
        else if (source_x <  8'd90)  bar_color = CYAN;
        else if (source_x <  8'd120) bar_color = GREEN;
        else if (source_x <  8'd150) bar_color = MAGENTA;
        else if (source_x <  8'd180) bar_color = RED;
        else if (source_x <  8'd210) bar_color = BLUE;
        else                         bar_color = BLACK;
    end

    logic [14:0] calibration_color;
    always_comb begin
        if      (source_y < 8'd112) calibration_color = bar_color;
        else if (source_y < 8'd128) calibration_color = bgr(ramp_level, 5'd0, 5'd0);
        else if (source_y < 8'd144) calibration_color = bgr(5'd0, ramp_level, 5'd0);
        else                        calibration_color = bgr(5'd0, 5'd0, ramp_level);
    end

    // ---- Pattern 3: solid colour sequence ----------------------------------------------
    logic [2:0]  purity_step;      // advances every 32 frames
    logic [14:0] purity_color;
    assign purity_step = frame_count[7:5];
    always_comb begin
        case (purity_step)
            3'd0:    purity_color = WHITE;
            3'd1:    purity_color = RED;
            3'd2:    purity_color = GREEN;
            3'd3:    purity_color = BLUE;
            3'd4:    purity_color = CYAN;
            3'd5:    purity_color = MAGENTA;
            3'd6:    purity_color = YELLOW;
            default: purity_color = BLACK;
        endcase
    end

    // ---- Output select ------------------------------------------------------------------
    always_comb begin
        case (pattern_sel)
            2'd0: begin
                if (!source_active)  color_bgr555 = GREY_DARK;
                else if (on_outline) color_bgr555 = ~calibration_color;
                else                 color_bgr555 = calibration_color;
            end
            2'd1: begin
                if (!source_active)    color_bgr555 = BLACK;
                else if (on_outline)   color_bgr555 = WHITE;
                else if (on_crosshair) color_bgr555 = RED;
                else if (tile_light)   color_bgr555 = TILE_LITE;
                else                   color_bgr555 = TILE_DARK;
            end
            2'd2: begin
                if (!source_active)  color_bgr555 = BLACK;
                else if (in_sprite)  color_bgr555 = YELLOW;
                else                 color_bgr555 = bgr(5'd0, sky_level >> 1, sky_level);
            end
            default: begin
                color_bgr555 = purity_color;   // border included: whole panel
            end
        endcase
    end
endmodule
