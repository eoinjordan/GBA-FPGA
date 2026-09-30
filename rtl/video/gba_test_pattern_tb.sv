`timescale 1ns/1ps

// =============================================================================
// gba_test_pattern_tb -- spot checks for every pattern plus sprite motion
// =============================================================================
// The colour path is combinational, so each check drives a source coordinate
// and compares the BGR555 output with the value the pattern description in
// gba_test_pattern.sv promises. The sprite is then run for 500 frames to
// prove it bounces off both edges on both axes and never leaves the frame.
// =============================================================================
module gba_test_pattern_tb;
    // ---- DUT -----------------------------------------------------------------------------
    logic        clk = 1'b0;
    logic        rst_n = 1'b0;
    logic        frame_start = 1'b0;
    logic [7:0]  frame_count = 8'd0;
    logic [1:0]  pattern_sel = 2'd0;
    logic        source_active = 1'b1;
    logic [7:0]  source_x = 8'd0;
    logic [7:0]  source_y = 8'd0;
    logic [14:0] color;
    integer      errors = 0;

    always #5 clk = ~clk;

    gba_test_pattern dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .frame_start  (frame_start),
        .frame_count  (frame_count),
        .pattern_sel  (pattern_sel),
        .source_active(source_active),
        .source_x     (source_x),
        .source_y     (source_y),
        .color_bgr555 (color)
    );

    // ---- Helpers ------------------------------------------------------------------------------
    function automatic logic [14:0] bgr(input integer r, input integer g, input integer b);
        bgr = {b[4:0], g[4:0], r[4:0]};
    endfunction

    task automatic probe(input string what, input logic active, input integer x, input integer y,
                         input logic [14:0] want);
        source_active = active;
        source_x      = x[7:0];
        source_y      = y[7:0];
        #1;
        if (color !== want) begin
            $display("ERROR: pattern %0d %s (%0d,%0d): got B%0d G%0d R%0d, want B%0d G%0d R%0d",
                     pattern_sel, what, x, y, color[14:10], color[9:5], color[4:0],
                     want[14:10], want[9:5], want[4:0]);
            errors = errors + 1;
        end
    endtask

    task automatic pulse_frame;
        @(negedge clk) frame_start = 1'b1;
        @(negedge clk) frame_start = 1'b0;
    endtask

    integer frame;
    integer min_x, max_x, min_y, max_y;

    // ---- Checks -------------------------------------------------------------------------------
    initial begin
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // Pattern 0: calibration bars, ramps, inverted outline, grey border.
        pattern_sel = 2'd0;
        probe("border",        1'b0, 0,   0,   bgr(6, 6, 6));
        probe("white bar",     1'b1, 15,  50,  bgr(31, 31, 31));
        probe("yellow bar",    1'b1, 45,  50,  bgr(31, 31, 0));
        probe("cyan bar",      1'b1, 75,  50,  bgr(0, 31, 31));
        probe("green bar",     1'b1, 105, 50,  bgr(0, 31, 0));
        probe("magenta bar",   1'b1, 135, 50,  bgr(31, 0, 31));
        probe("red bar",       1'b1, 165, 50,  bgr(31, 0, 0));
        probe("blue bar",      1'b1, 195, 50,  bgr(0, 0, 31));
        probe("black bar",     1'b1, 225, 50,  bgr(0, 0, 0));
        probe("outline left",  1'b1, 0,   50,  bgr(0, 0, 0));          // ~white
        probe("outline right", 1'b1, 239, 50,  bgr(31, 31, 31));       // ~black
        probe("outline top",   1'b1, 165, 0,   bgr(0, 31, 31));        // ~red
        probe("red ramp",      1'b1, 100, 120, bgr(13, 0, 0));         // (100*17)>>7 = 13
        probe("green ramp",    1'b1, 1,   136, bgr(0, 0, 0));
        probe("blue ramp max", 1'b1, 238, 150, bgr(0, 0, 31));
        probe("outline bottom",1'b1, 100, 159, ~bgr(0, 0, 13));

        // Pattern 1: tiles, crosshair, white outline, black border.
        pattern_sel = 2'd1;
        probe("border",        1'b0, 10,  10,  bgr(0, 0, 0));
        probe("dark tile",     1'b1, 4,   4,   bgr(8, 8, 12));
        probe("light tile",    1'b1, 12,  4,   bgr(22, 22, 22));
        probe("crosshair x",   1'b1, 119, 40,  bgr(31, 0, 0));
        probe("crosshair y",   1'b1, 40,  80,  bgr(31, 0, 0));
        probe("outline",       1'b1, 0,   10,  bgr(31, 31, 31));

        // Pattern 2: sprite starts at (40,24), moves +1/+1 per frame.
        pattern_sel = 2'd2;
        probe("sprite",        1'b1, 45,  30,  bgr(31, 31, 0));
        probe("sky",           1'b1, 100, 24,  bgr(0, 2, 4));          // (24*25)>>7 = 4
        pulse_frame();
        probe("moved away",    1'b1, 40,  24,  bgr(0, 2, 4));
        probe("moved to",      1'b1, 56,  40,  bgr(31, 31, 0));

        min_x = 255; max_x = 0; min_y = 255; max_y = 0;
        for (frame = 0; frame < 500; frame = frame + 1) begin
            pulse_frame();
            if (dut.sprite_x < min_x) min_x = dut.sprite_x;
            if (dut.sprite_x > max_x) max_x = dut.sprite_x;
            if (dut.sprite_y < min_y) min_y = dut.sprite_y;
            if (dut.sprite_y > max_y) max_y = dut.sprite_y;
        end
        if (min_x != 0 || max_x != 224 || min_y != 0 || max_y != 144) begin
            $display("ERROR: sprite range x %0d..%0d y %0d..%0d, expected 0..224 / 0..144",
                     min_x, max_x, min_y, max_y);
            errors = errors + 1;
        end

        // Pattern 3: whole panel (border too) follows frame_count[7:5].
        pattern_sel = 2'd3;
        frame_count = 8'd0;
        probe("white inside",  1'b1, 120, 80,  bgr(31, 31, 31));
        probe("white border",  1'b0, 0,   0,   bgr(31, 31, 31));
        frame_count = 8'd96;                                           // [7:5] = 3
        probe("blue",          1'b1, 120, 80,  bgr(0, 0, 31));
        frame_count = 8'd255;
        probe("black",         1'b0, 0,   0,   bgr(0, 0, 0));

        if (errors == 0) begin
            $display("PASS: gba_test_pattern (4 patterns, sprite bounces within 240x160)");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end
endmodule
