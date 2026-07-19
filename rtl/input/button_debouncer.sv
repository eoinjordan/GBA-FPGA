`timescale 1ns/1ps

module button_debouncer #(
    parameter integer STABLE_CYCLES = 270000
) (
    input  logic clk,
    input  logic rst_n,
    input  logic asynchronous_in,
    output logic stable_out
);
    localparam integer COUNTER_WIDTH = (STABLE_CYCLES <= 1) ? 1 : $clog2(STABLE_CYCLES);

    logic sync_ff1;
    logic sync_ff2;
    logic [COUNTER_WIDTH-1:0] counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= asynchronous_in;
            sync_ff2 <= sync_ff1;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable_out <= 1'b0;
            counter    <= '0;
        end else if (sync_ff2 == stable_out) begin
            counter <= '0;
        end else if (STABLE_CYCLES <= 1 || counter == STABLE_CYCLES - 1) begin
            stable_out <= sync_ff2;
            counter    <= '0;
        end else begin
            counter <= counter + 1'b1;
        end
    end
endmodule
