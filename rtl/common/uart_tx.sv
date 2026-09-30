`timescale 1ns/1ps

// =============================================================================
// uart_tx -- 8N1 UART transmitter with a valid/ready byte interface
// =============================================================================
// One start bit, eight data bits (LSB first), one stop bit, no parity.
// A byte is accepted on any cycle where tx_valid && tx_ready; tx_ready stays
// low until that byte's stop bit has been fully sent.
//
// Baud divider: CLKS_PER_BIT = round(clk_hz / baud).
//   27 MHz / 115200 = 234.375 -> 234 (0.16 % fast, well inside the ~2 % a
//   UART receiver tolerates).
// Cost: 10-bit shift register + 4-bit bit counter + one baud counter.
// =============================================================================
module uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_valid,
    input  logic [7:0] tx_data,
    output logic       tx_ready,
    output logic       tx                  // serial output, idles high
);
    localparam integer BAUD_BITS = (CLKS_PER_BIT <= 2) ? 1 : $clog2(CLKS_PER_BIT);

    // ---- State ---------------------------------------------------------------
    // shift_reg[0] is the bit currently on the line. Idle = all ones, so the
    // line sits at the stop/idle level without any extra muxing.
    logic [9:0]           shift_reg;
    logic [3:0]           bits_left;       // 0 = idle, otherwise frame bits still to send
    logic [BAUD_BITS-1:0] baud_count;

    assign tx_ready = (bits_left == 4'd0);
    assign tx       = shift_reg[0];        // straight from a flop: glitch-free pin

    // ---- Frame sequencer -----------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift_reg  <= '1;
            bits_left  <= 4'd0;
            baud_count <= '0;
        end else if (bits_left == 4'd0) begin
            // Idle: load {stop, data[7:0], start} when a byte is offered.
            if (tx_valid) begin
                shift_reg  <= {1'b1, tx_data, 1'b0};
                bits_left  <= 4'd10;
                baud_count <= '0;
            end
        end else if (baud_count == CLKS_PER_BIT - 1) begin
            // End of one bit period: move to the next bit, back-filling idle '1's.
            baud_count <= '0;
            shift_reg  <= {1'b1, shift_reg[9:1]};
            bits_left  <= bits_left - 4'd1;
        end else begin
            baud_count <= baud_count + 1'b1;
        end
    end
endmodule
