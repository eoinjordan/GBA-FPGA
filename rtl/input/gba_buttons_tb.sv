`timescale 1ns/1ps

module gba_buttons_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic [9:0] buttons_n = 10'h3FF;
    logic [9:0] pressed;
    integer errors = 0;

    always #5 clk = ~clk;

    gba_buttons #(
        .STABLE_CYCLES(3)
    ) dut (
        .clk,
        .rst_n,
        .buttons_n,
        .pressed
    );

    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (6) @(posedge clk);

        if (pressed !== 10'b0) begin
            $display("ERROR: buttons should be released after reset");
            errors = errors + 1;
        end

        buttons_n[0] <= 1'b0;
        @(posedge clk);
        buttons_n[0] <= 1'b1;
        @(posedge clk);
        buttons_n[0] <= 1'b0;
        repeat (6) @(posedge clk);

        if (pressed[0] !== 1'b1) begin
            $display("ERROR: button press did not debounce");
            errors = errors + 1;
        end

        buttons_n[0] <= 1'b1;
        repeat (6) @(posedge clk);
        if (pressed[0] !== 1'b0) begin
            $display("ERROR: button release did not debounce");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: gba_buttons");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end
endmodule
