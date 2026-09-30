`timescale 1ns/1ps

// =============================================================================
// uart_tx_tb -- frame format and back-to-back throughput
// =============================================================================
// A behavioural receiver samples the line in the middle of each bit period
// and checks start bit, 8 data bits (LSB first) and stop bit for a sequence of
// bytes queued back to back through the valid/ready handshake. A short
// CLKS_PER_BIT keeps the simulation fast; the logic is rate-independent.
// =============================================================================
module uart_tx_tb;
    localparam integer CLKS_PER_BIT = 8;
    localparam integer BYTES        = 5;

    // ---- DUT ------------------------------------------------------------------------------
    logic       clk = 1'b0;
    logic       rst_n = 1'b0;
    logic       tx_valid = 1'b0;
    logic [7:0] tx_data = 8'h00;
    logic       tx_ready;
    logic       tx;
    integer     errors = 0;

    always #5 clk = ~clk;

    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk(clk), .rst_n(rst_n), .tx_valid(tx_valid), .tx_data(tx_data),
        .tx_ready(tx_ready), .tx(tx)
    );

    logic [7:0] message [0:BYTES-1];
    initial begin
        message[0] = 8'h55; message[1] = 8'hA3; message[2] = 8'h00;
        message[3] = 8'hFF; message[4] = "G";
    end

    // ---- Sender: hold valid high; a byte is taken on each edge where ready is high ----------------
    integer sent = 0;
    logic   accepted;
    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        while (sent < BYTES) begin
            @(negedge clk);
            tx_valid = 1'b1;
            tx_data  = message[sent];
            accepted = tx_ready;              // ready as the DUT will see it at the next edge
            @(posedge clk);
            if (accepted) sent = sent + 1;
        end
        @(negedge clk) tx_valid = 1'b0;
    end

    // ---- Receiver: mid-bit sampling ---------------------------------------------------------------
    integer received = 0;
    integer bit_index;
    logic [7:0] shift;
    initial begin
        wait (rst_n);
        while (received < BYTES) begin
            @(negedge tx);                                   // start bit edge
            repeat (CLKS_PER_BIT / 2) @(posedge clk);
            if (tx !== 1'b0) begin
                $display("ERROR: byte %0d start bit not low at mid-bit", received);
                errors = errors + 1;
            end
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (CLKS_PER_BIT) @(posedge clk);
                shift[bit_index] = tx;
            end
            repeat (CLKS_PER_BIT) @(posedge clk);
            if (tx !== 1'b1) begin
                $display("ERROR: byte %0d stop bit not high", received);
                errors = errors + 1;
            end
            if (shift !== message[received]) begin
                $display("ERROR: byte %0d = %h, expected %h", received, shift, message[received]);
                errors = errors + 1;
            end
            received = received + 1;
        end

        repeat (CLKS_PER_BIT * 2) @(posedge clk);
        if (tx !== 1'b1 || !tx_ready) begin
            $display("ERROR: line not idle-high / ready after the last byte");
            errors = errors + 1;
        end
        if (errors == 0) begin
            $display("PASS: uart_tx (%0d back-to-back 8N1 frames)", BYTES);
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end

    initial begin
        #1_000_000;
        $fatal(1, "Timeout");
    end
endmodule
