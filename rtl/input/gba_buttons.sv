`timescale 1ns/1ps

module gba_buttons #(
    parameter integer STABLE_CYCLES = 270000
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic [9:0] buttons_n,
    output logic [9:0] pressed
);
    genvar index;
    generate
        for (index = 0; index < 10; index = index + 1) begin : generate_debouncers
            logic pressed_level;
            button_debouncer #(
                .STABLE_CYCLES(STABLE_CYCLES)
            ) debouncer (
                .clk,
                .rst_n,
                .asynchronous_in(~buttons_n[index]),
                .stable_out(pressed_level)
            );
            assign pressed[index] = pressed_level;
        end
    endgenerate
endmodule
