`timescale 1ns/1ps

module gba_cart_rom_reader #(
    parameter integer ADDRESS_SETUP_CYCLES = 2,
    parameter integer CS_LATCH_CYCLES      = 2,
    parameter integer BUS_TURN_CYCLES      = 2,
    parameter integer RD_WAIT_CYCLES       = 12,
    parameter integer RECOVERY_CYCLES      = 2
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        start,
    input  logic [23:0] start_word_address,
    input  logic [24:0] word_count,

    output logic        busy,
    output logic        done,

    output logic [23:0] stream_word_address,
    output logic [15:0] stream_data,
    output logic        stream_valid,
    input  logic        stream_ready,

    input  logic [15:0] cart_ad_in,
    output logic [15:0] cart_ad_out,
    output logic        cart_ad_oe,
    output logic [7:0]  cart_a,
    output logic        cart_cs_n,
    output logic        cart_rd_n,
    output logic        cart_wr_n,
    output logic        cart_cs2_n
);

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

    state_t state;
    logic [15:0] phase_counter;
    logic [23:0] current_word_address;
    logic [24:0] words_remaining;

    function automatic logic phase_complete(
        input logic [15:0] counter,
        input integer target_cycles
    );
        if (target_cycles <= 1) begin
            phase_complete = 1'b1;
        end else begin
            phase_complete = (counter == target_cycles - 1);
        end
    endfunction

    always_comb begin
        cart_ad_out = current_word_address[15:0];
        cart_a      = current_word_address[23:16];

        cart_ad_oe  = 1'b0;
        cart_cs_n   = 1'b1;
        cart_rd_n   = 1'b1;
        cart_wr_n   = 1'b1;
        cart_cs2_n  = 1'b1;

        unique case (state)
            ST_ADDRESS_SETUP: begin
                cart_ad_oe = 1'b1;
            end
            ST_CS_LATCH: begin
                cart_ad_oe = 1'b1;
                cart_cs_n  = 1'b0;
            end
            ST_BUS_TURN: begin
                cart_cs_n = 1'b0;
            end
            ST_RD_ASSERT,
            ST_RD_SAMPLE: begin
                cart_cs_n = 1'b0;
                cart_rd_n = 1'b0;
            end
            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= ST_IDLE;
            phase_counter        <= 16'd0;
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
                ST_IDLE: begin
                    busy          <= 1'b0;
                    stream_valid  <= 1'b0;
                    phase_counter <= 16'd0;

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

                ST_ADDRESS_SETUP: begin
                    if (phase_complete(phase_counter, ADDRESS_SETUP_CYCLES)) begin
                        phase_counter <= 16'd0;
                        state         <= ST_CS_LATCH;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_CS_LATCH: begin
                    if (phase_complete(phase_counter, CS_LATCH_CYCLES)) begin
                        phase_counter <= 16'd0;
                        state         <= ST_BUS_TURN;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_BUS_TURN: begin
                    if (phase_complete(phase_counter, BUS_TURN_CYCLES)) begin
                        phase_counter <= 16'd0;
                        state         <= ST_RD_ASSERT;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_RD_ASSERT: begin
                    if (phase_complete(phase_counter, RD_WAIT_CYCLES)) begin
                        phase_counter <= 16'd0;
                        state         <= ST_RD_SAMPLE;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

                ST_RD_SAMPLE: begin
                    stream_data         <= cart_ad_in;
                    stream_word_address <= current_word_address;
                    phase_counter       <= 16'd0;
                    state               <= ST_RECOVERY;
                end

                ST_RECOVERY: begin
                    if (phase_complete(phase_counter, RECOVERY_CYCLES)) begin
                        phase_counter <= 16'd0;
                        stream_valid  <= 1'b1;
                        state         <= ST_STREAM;
                    end else begin
                        phase_counter <= phase_counter + 1'b1;
                    end
                end

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
