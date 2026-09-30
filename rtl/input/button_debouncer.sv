`timescale 1ns/1ps

// =============================================================================
// button_debouncer -- one-bit integrating debouncer on a shared sample tick
// =============================================================================
// The output only changes after the (already synchronised) input has held the
// new level for STABLE_TICKS consecutive sample ticks. Any return to the old
// level, even for one clock, restarts the count, so contact bounce and short
// noise spikes are rejected.
//
// The slow sample tick is generated once and shared by every button (see
// gba_buttons), so each button only needs a tiny tick counter instead of a
// full-rate 19-bit cycle counter: 10 ms of debounce at 27 MHz costs 4 flops
// per button here versus 19 before.
//
// Accept latency: between STABLE_TICKS-1 and STABLE_TICKS tick periods.
// =============================================================================
module button_debouncer #(
    parameter integer STABLE_TICKS = 10
) (
    input  logic clk,
    input  logic rst_n,
    input  logic sample_tick,     // one-clock strobe, shared by all buttons
    input  logic level_in,        // synchronised level, 1 = pressed
    output logic stable_out       // debounced level, 1 = pressed
);
    localparam integer COUNT_BITS = (STABLE_TICKS <= 2) ? 1 : $clog2(STABLE_TICKS);

    // ---- Disagreement counter ------------------------------------------------------
    // Counts ticks while level_in differs from stable_out; flips the output
    // when the count completes.
    logic [COUNT_BITS-1:0] tick_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stable_out <= 1'b0;
            tick_count <= '0;
        end else if (level_in == stable_out) begin
            tick_count <= '0;
        end else if (sample_tick) begin
            if (tick_count == STABLE_TICKS - 1) begin
                stable_out <= level_in;
                tick_count <= '0;
            end else begin
                tick_count <= tick_count + 1'b1;
            end
        end
    end
endmodule
