`timescale 1ns/1ps

// =============================================================================
// gba_cart_rom_reader -- conservative ROM-only GBA Game Pak reader
// =============================================================================
// Reads a run of 16-bit ROM halfwords with a full, independent bus cycle per
// halfword (no sequential bursts), which is slow but easy to validate safely:
//
//   ADDRESS_SETUP  drive A[23:16] and AD[15:0] with the halfword address
//   CS_LATCH       assert /CS while still driving AD -> cartridge latches address
//   BUS_TURN       release AD (FPGA stops driving), keep /CS low
//   RD_ASSERT      assert /RD and wait for the ROM access time
//   RD_SAMPLE      capture AD[15:0] as data
//   RECOVERY       release /RD and /CS, wait before the next cycle
//   STREAM         present {address, data} until the consumer takes it
//
// Bus-safety invariants (checked by the testbench):
//   * AD is only driven while /RD is high, so FPGA and ROM never fight;
//   * /CS only falls while the FPGA is driving a valid address;
//   * /WR and /CS2 are never asserted: no write or save-memory access at all.
//
// Phase lengths are clock counts; the defaults suit a 27 MHz clock with wide
// margins (RD_WAIT 12 cycles = 444 ns). Tighten only against measurements.
// =============================================================================
module gba_cart_rom_reader #(
    parameter integer ADDRESS_SETUP_CYCLES = 2,
    parameter integer CS_LATCH_CYCLES      = 2,
    parameter integer BUS_TURN_CYCLES      = 2,
    parameter integer RD_WAIT_CYCLES       = 12,
    parameter integer RECOVERY_CYCLES      = 2
) (
    input  logic        clk,
    input  logic        rst_n,

    // ---- Command: read word_count halfwords starting at start_word_address ----
    input  logic        start,
    input  logic [23:0] start_word_address,   // halfword address (byte address >> 1)
    input  logic [24:0] word_count,           // 0 completes immediately
    output logic        busy,
    output logic        done,                 // one-cycle pulse when the run ends

    // ---- Data stream (valid/ready) ---------------------------------------------
    output logic [23:0] stream_word_address,
    output logic [15:0] stream_data,
    output logic        stream_valid,
    input  logic        stream_ready,

    // ---- Cartridge bus (split into in/out/oe for an external IO buffer) --------
    input  logic [15:0] cart_ad_in,
    output logic [15:0] cart_ad_out,
    output logic        cart_ad_oe,           // 1 = FPGA drives AD[15:0]
    output logic [7:0]  cart_a,               // A[23:16]
    output logic        cart_cs_n,
    output logic        cart_rd_n,
    output logic        cart_wr_n,
    output logic        cart_cs2_n
);
    // ---- State encoding ------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_IDLE,
        ST_ADDRESS_SETUP,
        ST_CS_LATCH,
        ST_BUS_TURN,
        ST_RD_ASSERT,
        ST_RD_SAMPLE,
        ST_RECOVERY,
        ST_STREAM,
        ST_FINISH
    } state_t;

    // ---- Phase counter sizing ---------------------------------------------------------
    // Wide enough for the longest phase only (4 bits for the defaults, not 16).
    localparam integer MAX_PHASE_A = (ADDRESS_SETUP_CYCLES > CS_LATCH_CYCLES) ? ADDRESS_SETUP_CYCLES : CS_LATCH_CYCLES;
    localparam integer MAX_PHASE_B = (BUS_TURN_CYCLES > RD_WAIT_CYCLES) ? BUS_TURN_CYCLES : RD_WAIT_CYCLES;
    localparam integer MAX_PHASE_C = (MAX_PHASE_A > MAX_PHASE_B) ? MAX_PHASE_A : MAX_PHASE_B;
    localparam integer MAX_PHASE   = (MAX_PHASE_C > RECOVERY_CYCLES) ? MAX_PHASE_C : RECOVERY_CYCLES;
    localparam integer PHASE_BITS  = (MAX_PHASE <= 2) ? 1 : $clog2(MAX_PHASE);

    state_t                state;
    logic [PHASE_BITS-1:0] phase_counter;
    logic [23:0]           current_word_address;
    logic [24:0]           words_remaining;

    // True on the last cycle of a phase that lasts target_cycles clocks.
    function automatic logic phase_complete(
        input logic [PHASE_BITS-1:0] counter,
        input integer                target_cycles
    );
        if (target_cycles <= 1) begin
            phase_complete = 1'b1;
        end else begin
            phase_complete = (counter == target_cycles - 1);
        end
    endfunction

    // ---- Bus drive decode (Moore outputs) ------------------------------------------------
    // The address is always presented on the output side; cart_ad_oe decides
    // whether it actually reaches the AD pins.
    always_comb begin
        cart_ad_out = current_word_address[15:0];
        cart_a      = current_word_address[23:16];

        cart_ad_oe  = 1'b0;
        cart_cs_n   = 1'b1;
        cart_rd_n   = 1'b1;
        cart_wr_n   = 1'b1;    // never written: ROM-only
        cart_cs2_n  = 1'b1;    // save memory never selected

        unique case (state)
            ST_ADDRESS_SETUP: begin
                cart_ad_oe = 1'b1;
            end
            ST_CS_LATCH: begin
                cart_ad_oe = 1'b1;
                cart_cs_n  = 1'b0;
            end
            ST_BUS_TURN: begin
                cart_cs_n  = 1'b0;
            end
            ST_RD_ASSERT,
            ST_RD_SAMPLE: begin
                cart_cs_n  = 1'b0;
                cart_rd_n  = 1'b0;
            end
            default: begin
            end
        endcase
    end

    // ---- Transaction sequencer ---------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            phase_counter        <= '0;
            current_word_address <= 24'd0;
            words_remaining      <= 25'd0;
            stream_word_address  <= 24'd0;
            stream_data          <= 16'd0;
            stream_valid         <= 1'b0;
            busy                 <= 1'b0;
            done                 <= 1'b0;
        end else begin
            done <= 1'b0;

            unique case (state)
                // Wait for a command; an empty run finishes immediately.
                ST_IDLE: begin
                    busy          <= 1'b0;
                    stream_valid  <= 1'b0;
                    phase_counter <= '0;

                    if (start) begin
                        if (word_count == 0) begin
                            done <= 1'b1;
                        end else begin
                            busy                 <= 1'b1;
                            current_word_address <= start_word_address;
                            words_remaining      <= word_count;
                            state                <= ST_ADDRESS_SETUP;
                        end
                    end
                end

                // Timed bus phases: each holds for its parameterised length.
                ST_ADDRESS_SETUP: begin
                    if (phase_complete(phase_counter, ADDRESS_SETUP_CYCLES)) begin
                        phase_counter <= '0;
                        state         <= ST_CS_LATCH;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_CS_LATCH: begin
                    if (phase_complete(phase_counter, CS_LATCH_CYCLES)) begin
                        phase_counter <= '0;
                        state         <= ST_BUS_TURN;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_BUS_TURN: begin
                    if (phase_complete(phase_counter, BUS_TURN_CYCLES)) begin
                        phase_counter <= '0;
                        state         <= ST_RD_ASSERT;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_RD_ASSERT: begin
                    if (phase_complete(phase_counter, RD_WAIT_CYCLES)) begin
                        phase_counter <= '0;
                        state         <= ST_RD_SAMPLE;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                // Capture the halfword while /RD is still low.
                ST_RD_SAMPLE: begin
                    stream_data         <= cart_ad_in;
                    stream_word_address <= current_word_address;
                    phase_counter       <= '0;
                    state               <= ST_RECOVERY;
                end

                ST_RECOVERY: begin
                    if (phase_complete(phase_counter, RECOVERY_CYCLES)) begin
                        phase_counter <= '0;
                        stream_valid  <= 1'b1;
                        state         <= ST_STREAM;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                // Hold the word until accepted, then advance or finish.
                ST_STREAM: begin
                    if (stream_valid && stream_ready) begin
                        stream_valid <= 1'b0;

                        if (words_remaining == 1) begin
                            words_remaining <= 25'd0;
                            state           <= ST_FINISH;
                        end else begin
                            words_remaining      <= words_remaining - 1'b1;
                            current_word_address <= current_word_address + 1'b1;
                            state                <= ST_ADDRESS_SETUP;
                        end
                    end
                end

                ST_FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
