`timescale 1ns/1ps

module gba_cart_rom_reader_tb;
    logic clk = 1'b0;
    logic rst_n = 1'b0;
    logic start = 1'b0;
    logic [23:0] start_word_address = 24'h001234;
    logic [24:0] word_count = 25'd4;

    logic busy;
    logic done;
    logic [23:0] stream_word_address;
    logic [15:0] stream_data;
    logic stream_valid;
    logic stream_ready = 1'b1;

    logic [15:0] cart_ad_in;
    logic [15:0] cart_ad_out;
    logic cart_ad_oe;
    logic [7:0] cart_a;
    logic cart_cs_n;
    logic cart_rd_n;
    logic cart_wr_n;
    logic cart_cs2_n;

    logic [23:0] model_latched_address = 24'd0;
    logic previous_cs_n = 1'b1;
    integer received = 0;
    integer errors = 0;

    always #5 clk = ~clk;

    gba_cart_rom_reader #(
        .ADDRESS_SETUP_CYCLES(2),
        .CS_LATCH_CYCLES(2),
        .BUS_TURN_CYCLES(2),
        .RD_WAIT_CYCLES(3),
        .RECOVERY_CYCLES(2)
    ) dut (
        .clk,
        .rst_n,
        .start,
        .start_word_address,
        .word_count,
        .busy,
        .done,
        .stream_word_address,
        .stream_data,
        .stream_valid,
        .stream_ready,
        .cart_ad_in,
        .cart_ad_out,
        .cart_ad_oe,
        .cart_a,
        .cart_cs_n,
        .cart_rd_n,
        .cart_wr_n,
        .cart_cs2_n
    );

    always_comb begin
        if (!cart_cs_n && !cart_rd_n && !cart_ad_oe) begin
            cart_ad_in = model_latched_address[15:0] ^ 16'hA5A5;
        end else begin
            cart_ad_in = 16'hZZZZ;
        end
    end

    always_ff @(posedge clk) begin
        previous_cs_n <= cart_cs_n;
        if (previous_cs_n && !cart_cs_n) begin
            if (!cart_ad_oe) begin
                $display("ERROR: /CS fell without the FPGA driving the address bus");
                errors <= errors + 1;
            end
            model_latched_address <= {cart_a, cart_ad_out};
        end

        if (!cart_wr_n || !cart_cs2_n) begin
            $display("ERROR: ROM-only reader asserted a write/save control");
            errors <= errors + 1;
        end

        if (stream_valid && stream_ready) begin
            logic [23:0] expected_address;
            logic [15:0] expected_data;
            expected_address = start_word_address + received;
            expected_data = expected_address[15:0] ^ 16'hA5A5;

            if (stream_word_address !== expected_address) begin
                $display("ERROR: address %h expected %h", stream_word_address, expected_address);
                errors <= errors + 1;
            end
            if (stream_data !== expected_data) begin
                $display("ERROR: data %h expected %h", stream_data, expected_data);
                errors <= errors + 1;
            end
            received <= received + 1;
        end
    end

    initial begin
        $dumpfile("gba_cart_rom_reader_tb.vcd");
        $dumpvars(0, gba_cart_rom_reader_tb);

        repeat (5) @(posedge clk);
        rst_n <= 1'b1;
        repeat (2) @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done);
        @(posedge clk);

        if (received != 4) begin
            $display("ERROR: received %0d words, expected 4", received);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: gba_cart_rom_reader completed all ROM-only transactions");
        end else begin
            $display("FAIL: %0d error(s)", errors);
            $fatal(1);
        end
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "Timeout");
    end
endmodule
