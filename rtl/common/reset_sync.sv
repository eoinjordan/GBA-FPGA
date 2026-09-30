`timescale 1ns/1ps

// =============================================================================
// reset_sync -- asynchronous-assert, synchronous-release reset synchroniser
// =============================================================================
// Every clock domain gets its own copy. The reset asserts immediately (no
// clock needed, so a stopped PLL still holds the domain in reset) and releases
// on a clock edge after STAGES flops, so all registers in the domain leave
// reset on the same cycle and none sees a metastable release.
//
// Typical source: the PLL LOCK output, so logic only runs on a stable clock.
// With async_rst_n tied high it is a power-on reset: the flops are
// initialised to 0 at configuration, so rst_n starts low and releases
// STAGES clocks after the clock starts.
// =============================================================================
module reset_sync #(
    parameter integer STAGES = 2          // >= 2; each stage adds one cycle of release latency
) (
    input  logic clk,
    input  logic async_rst_n,             // active-low, any clock domain (or none)
    output logic rst_n                    // active-low, released synchronously to clk
);
    // ---- Release shift register -------------------------------------------
    // Cleared asynchronously; a '1' walks in from the LSB once reset lifts.
    // Lint: the power-on value is intended, and the chain is by design both
    // shifted synchronously here and used as an asynchronous reset downstream.
    /* verilator lint_off PROCASSINIT */
    /* verilator lint_off SYNCASYNCNET */
    logic [STAGES-1:0] release_pipe = '0;
    /* verilator lint_on SYNCASYNCNET */
    /* verilator lint_on PROCASSINIT */

    always_ff @(posedge clk or negedge async_rst_n) begin
        if (!async_rst_n) begin
            release_pipe <= '0;
        end else begin
            release_pipe <= {release_pipe[STAGES-2:0], 1'b1};
        end
    end

    assign rst_n = release_pipe[STAGES-1];
endmodule
