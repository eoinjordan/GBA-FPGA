`timescale 1ns/1ps

// =============================================================================
// gba_to_480x272_mapper_tb -- exhaustive check of the panel -> GBA mapping
// =============================================================================
// Visits all 480x272 panel pixels (plus DE low) and compares the mapper with a
// reference model written with the original true divisions, so the
// multiply-by-reciprocal optimisation is proven exact everywhere. It also
// checks the coverage properties the display depends on: every one of the
// 240x160 source pixels is shown, and each is 1 or 2 panel pixels wide/tall.
// =============================================================================
module gba_to_480x272_mapper_tb;
    // ---- DUT ----------------------------------------------------------------------------
    logic [8:0] panel_x;
    logic [8:0] panel_y;
    logic       panel_active;
    logic       source_active;
    logic [7:0] source_x;
    logic [7:0] source_y;

    gba_to_480x272_mapper dut (
        .panel_x      (panel_x),
        .panel_y      (panel_y),
        .panel_active (panel_active),
        .source_active(source_active),
        .source_x     (source_x),
        .source_y     (source_y)
    );

    // ---- Reference model and coverage ----------------------------------------------------------
    integer errors = 0;
    integer x, y;
    integer want_active, want_x, want_y;
    integer column_hits [0:239];   // panel columns showing each source column (row 0)
    integer row_hits    [0:159];   // panel rows showing each source row (column 36)

    task automatic check_pixel(input integer px, input integer py);
        panel_x = px[8:0];
        panel_y = py[8:0];
        #1;
        want_active = (px >= 36) && (px < 444) && (py < 272);
        want_x      = want_active ? ((px - 36) * 240) / 408 : 0;
        want_y      = want_active ? (py * 160) / 272 : 0;
        if (source_active !== want_active[0] || source_x !== want_x[7:0] || source_y !== want_y[7:0]) begin
            if (errors < 10) begin
                $display("ERROR: panel (%0d,%0d) -> active=%b (%0d,%0d), expected %0d (%0d,%0d)",
                         px, py, source_active, source_x, source_y, want_active, want_x, want_y);
            end
            errors = errors + 1;
        end
    endtask

    initial begin
        for (x = 0; x < 240; x = x + 1) column_hits[x] = 0;
        for (y = 0; y < 160; y = y + 1) row_hits[y] = 0;

        // Every pixel of the panel, DE high.
        panel_active = 1'b1;
        for (y = 0; y < 272; y = y + 1) begin
            for (x = 0; x < 480; x = x + 1) begin
                check_pixel(x, y);
                if (source_active && y == 0)  column_hits[source_x] = column_hits[source_x] + 1;
                if (source_active && x == 36) row_hits[source_y]    = row_hits[source_y] + 1;
            end
        end

        // Blanking: DE low must never produce an active source pixel.
        panel_active = 1'b0;
        panel_x = 9'd240;
        panel_y = 9'd136;
        #1;
        if (source_active !== 1'b0 || source_x !== 8'd0 || source_y !== 8'd0) begin
            $display("ERROR: source active or non-zero while panel DE is low");
            errors = errors + 1;
        end

        // Coverage: all source pixels visible, each 1 or 2 panel pixels in size.
        for (x = 0; x < 240; x = x + 1) begin
            if (column_hits[x] < 1 || column_hits[x] > 2) begin
                $display("ERROR: source column %0d shown on %0d panel columns", x, column_hits[x]);
                errors = errors + 1;
            end
        end
        for (y = 0; y < 160; y = y + 1) begin
            if (row_hits[y] < 1 || row_hits[y] > 2) begin
                $display("ERROR: source row %0d shown on %0d panel rows", y, row_hits[y]);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS: gba_to_480x272_mapper (all 130560 panel pixels exact, full 240x160 coverage)");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end
endmodule
