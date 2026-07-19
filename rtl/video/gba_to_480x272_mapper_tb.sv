`timescale 1ns/1ps

module gba_to_480x272_mapper_tb;
    logic [8:0] panel_x;
    logic [8:0] panel_y;
    logic panel_active;
    logic source_active;
    logic [7:0] source_x;
    logic [7:0] source_y;
    integer errors = 0;

    gba_to_480x272_mapper dut (
        .panel_x,
        .panel_y,
        .panel_active,
        .source_active,
        .source_x,
        .source_y
    );

    task automatic check_point(
        input integer x,
        input integer y,
        input logic expected_active,
        input integer expected_x,
        input integer expected_y
    );
        begin
            panel_x = x;
            panel_y = y;
            panel_active = 1'b1;
            #1;
            if (source_active !== expected_active) begin
                $display("ERROR: (%0d,%0d) active=%b expected=%b", x, y, source_active, expected_active);
                errors = errors + 1;
            end
            if (expected_active && (source_x !== expected_x || source_y !== expected_y)) begin
                $display("ERROR: (%0d,%0d) source=(%0d,%0d) expected=(%0d,%0d)",
                         x, y, source_x, source_y, expected_x, expected_y);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        panel_x = 0;
        panel_y = 0;
        panel_active = 0;
        #1;

        check_point(0,   0,   0, 0,   0);
        check_point(35,  0,   0, 0,   0);
        check_point(36,  0,   1, 0,   0);
        check_point(443, 271, 1, 239, 159);
        check_point(444, 10,  0, 0,   0);
        check_point(240, 136, 1, 120, 80);

        if (errors == 0) begin
            $display("PASS: gba_to_480x272_mapper");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end
endmodule
