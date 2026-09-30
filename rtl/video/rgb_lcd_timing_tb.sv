`timescale 1ns/1ps

// =============================================================================
// rgb_lcd_timing_tb -- measures panel timing parameters off the output pins
// =============================================================================
// Rather than mirroring the RTL's arithmetic, each checker measures what a
// panel would see, in datasheet terms, and compares it with the requested
// profile:
//
//   Th / Tv       sync leading edge to next sync leading edge
//   Thw / Tvw     sync pulse width
//   Thbp / Tvbp   sync leading edge to first visible pixel / line
//   Thfp / Tvfp   last visible pixel / line to next sync leading edge
//   Thdisp        DE-high pixels per line;  visible lines per frame
//   pixel_x/y     equal the pixel's position while DE is high
//   frame_start   high exactly on the first visible pixel of each frame
//
// Three profiles run side by side on one clock:
//   tiny     4x3 with active-HIGH syncs (fast; exercises the polarity knobs)
//   ht043    HT043IBB / NV3047 typical timing (the module defaults)
//   legacy   Sipeed's 525x286 480x272 sample timing
// =============================================================================

// ---- Per-profile checker -------------------------------------------------------------
module rgb_lcd_timing_check #(
    parameter integer H_ACTIVE     = 480,
    parameter integer H_FRONT      = 8,
    parameter integer H_SYNC       = 4,
    parameter integer H_BACK       = 39,
    parameter integer V_ACTIVE     = 272,
    parameter integer V_FRONT      = 8,
    parameter integer V_SYNC       = 4,
    parameter integer V_BACK       = 8,
    parameter         HSYNC_ACTIVE = 1'b0,
    parameter         VSYNC_ACTIVE = 1'b0,
    parameter integer FRAMES       = 2
) (
    input  logic   clk,
    input  logic   rst_n,
    output logic   finished,
    output integer error_count
);
    localparam integer H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    // ---- Device under test ---------------------------------------------------------------
    logic        lcd_hsync;
    logic        lcd_vsync;
    logic        lcd_de;
    logic [11:0] pixel_x;
    logic [11:0] pixel_y;
    logic        frame_start;

    rgb_lcd_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .HSYNC_ACTIVE(HSYNC_ACTIVE), .VSYNC_ACTIVE(VSYNC_ACTIVE)
    ) dut (
        .pixel_clk  (clk),
        .rst_n      (rst_n),
        .lcd_hsync  (lcd_hsync),
        .lcd_vsync  (lcd_vsync),
        .lcd_de     (lcd_de),
        .pixel_x    (pixel_x),
        .pixel_y    (pixel_y),
        .frame_start(frame_start)
    );

    // ---- Measurement state (cycle stamps of the most recent edges) ---------------------------
    integer cycle          = 0;
    integer hs_rise        = -1;
    integer de_rise        = -1;
    integer de_fall        = -1;
    integer vs_rise        = -1;
    integer lines_in_frame = 0;
    integer frames_seen    = 0;
    logic   prev_hs        = 1'b0;
    logic   prev_vs        = 1'b0;
    logic   prev_de        = 1'b0;
    logic   first_line_due = 1'b0;   // next DE rise is the first line after VSYNC

    wire hs_on = (lcd_hsync == HSYNC_ACTIVE);
    wire vs_on = (lcd_vsync == VSYNC_ACTIVE);

    initial begin
        finished    = 1'b0;
        error_count = 0;
    end

    task automatic expect_eq(input string what, input integer got, input integer want);
        if (got != want) begin
            $display("ERROR [%0dx%0d] %s = %0d, expected %0d", H_ACTIVE, V_ACTIVE, what, got, want);
            error_count = error_count + 1;
        end
    endtask

    // ---- Checks, evaluated every clock --------------------------------------------------------
    always @(posedge clk) begin
        if (rst_n && !finished) begin
            // Horizontal sync: period and width.
            if (hs_on && !prev_hs) begin
                if (hs_rise >= 0) expect_eq("Th (clocks)", cycle - hs_rise, H_TOTAL);
                if (de_fall > hs_rise && hs_rise >= 0) expect_eq("Thfp (clocks)", cycle - de_fall, H_FRONT);
                hs_rise = cycle;
            end
            if (!hs_on && prev_hs) expect_eq("Thw (clocks)", cycle - hs_rise, H_SYNC);

            // Vertical sync: period, width and front porch; closes the previous frame.
            if (vs_on && !prev_vs) begin
                if (vs_rise >= 0) begin
                    expect_eq("Tv (clocks)", cycle - vs_rise, H_TOTAL * V_TOTAL);
                    expect_eq("visible lines", lines_in_frame, V_ACTIVE);
                    expect_eq("Tvfp (clocks)", cycle - (de_rise + H_TOTAL), V_FRONT * H_TOTAL);
                    frames_seen = frames_seen + 1;
                end
                vs_rise        = cycle;
                lines_in_frame = 0;
                first_line_due = 1'b1;
            end
            if (!vs_on && prev_vs) expect_eq("Tvw (clocks)", cycle - vs_rise, V_SYNC * H_TOTAL);

            // Data enable: back porches, visible width, coordinates and frame_start.
            if (lcd_de && !prev_de) begin
                if (hs_rise >= 0) expect_eq("Thbp (clocks)", cycle - hs_rise, H_SYNC + H_BACK);
                if (first_line_due) begin
                    expect_eq("Tvbp (clocks)", cycle - vs_rise, (V_SYNC + V_BACK) * H_TOTAL);
                end
                de_rise        = cycle;
                lines_in_frame = lines_in_frame + 1;
            end
            if (!lcd_de && prev_de) begin
                expect_eq("Thdisp (clocks)", cycle - de_rise, H_ACTIVE);
                de_fall = cycle;
            end

            if (lcd_de) begin
                expect_eq("pixel_x", pixel_x, cycle - de_rise);
                if (vs_rise >= 0) expect_eq("pixel_y", pixel_y, lines_in_frame - 1);
            end
            if (lcd_de && (hs_on || vs_on)) begin
                $display("ERROR [%0dx%0d] DE high during a sync pulse", H_ACTIVE, V_ACTIVE);
                error_count = error_count + 1;
            end

            if (vs_rise >= 0 && frame_start !== (lcd_de && !prev_de && first_line_due)) begin
                $display("ERROR [%0dx%0d] frame_start=%b at x=%0d y=%0d", H_ACTIVE, V_ACTIVE,
                         frame_start, pixel_x, pixel_y);
                error_count = error_count + 1;
            end
            if (lcd_de && !prev_de) first_line_due = 1'b0;

            prev_hs = hs_on;
            prev_vs = vs_on;
            prev_de = lcd_de;
            cycle   = cycle + 1;
            if (frames_seen == FRAMES) finished = 1'b1;
        end
    end
endmodule

// ---- Top-level testbench ---------------------------------------------------------------
module rgb_lcd_timing_tb;
    logic   clk   = 1'b0;
    logic   rst_n = 1'b0;
    logic   done_tiny;
    logic   done_ht043;
    logic   done_legacy;
    integer errors_tiny;
    integer errors_ht043;
    integer errors_legacy;

    always #5 clk = ~clk;

    rgb_lcd_timing_check #(
        .H_ACTIVE(4), .H_FRONT(1), .H_SYNC(1), .H_BACK(1),
        .V_ACTIVE(3), .V_FRONT(1), .V_SYNC(1), .V_BACK(1),
        .HSYNC_ACTIVE(1'b1), .VSYNC_ACTIVE(1'b1), .FRAMES(4)
    ) tiny (.clk(clk), .rst_n(rst_n), .finished(done_tiny), .error_count(errors_tiny));

    rgb_lcd_timing_check ht043 (
        .clk(clk), .rst_n(rst_n), .finished(done_ht043), .error_count(errors_ht043)
    );

    rgb_lcd_timing_check #(
        .H_ACTIVE(480), .H_FRONT(2), .H_SYNC(41), .H_BACK(2),
        .V_ACTIVE(272), .V_FRONT(2), .V_SYNC(10), .V_BACK(2)
    ) legacy (.clk(clk), .rst_n(rst_n), .finished(done_legacy), .error_count(errors_legacy));

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        wait (done_tiny && done_ht043 && done_legacy);
        @(posedge clk);
        if (errors_tiny + errors_ht043 + errors_legacy == 0) begin
            $display("PASS: rgb_lcd_timing (tiny, HT043IBB/NV3047, legacy profiles)");
        end else begin
            $fatal(1, "FAIL: rgb_lcd_timing %0d error(s)", errors_tiny + errors_ht043 + errors_legacy);
        end
        $finish;
    end

    initial begin
        #20_000_000;
        $fatal(1, "Timeout");
    end
endmodule
