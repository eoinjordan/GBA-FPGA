`timescale 1ns/1ps

// =============================================================================
// gba_buttons -- synchronise and debounce a bank of push buttons
// =============================================================================
// Default configuration is the GBA pad: 10 buttons, each pulling its pin low
// when pressed (external or internal pull-ups). The Tang Nano 20K's onboard
// S1/S2 are the opposite (pull-down, pressed = 1): use ACTIVE_LOW = 0.
//
//   pin -> polarity -> 2-flop synchroniser -> button_debouncer -> pressed[i]
//                                                  ^
//            one shared prescaler -> sample_tick --+ (every TICK_CYCLES clocks)
//
// Debounce window = TICK_CYCLES * STABLE_TICKS clocks. Defaults: 27 MHz clock,
// 1 ms tick, 10 ticks = 10 ms (the same window as the original 270000-cycle
// per-button counters, at about a quarter of the flops).
//
// Suggested bit order for a GBA pad (matches the KEYINPUT register):
//   0 A, 1 B, 2 Select, 3 Start, 4 Right, 5 Left, 6 Up, 7 Down, 8 R, 9 L
// =============================================================================
module gba_buttons #(
    parameter integer BUTTON_COUNT = 10,
    parameter integer ACTIVE_LOW   = 1,        // 1: pressed = 0 on the pin
    parameter integer TICK_CYCLES  = 27000,    // clocks per sample tick
    parameter integer STABLE_TICKS = 10        // ticks a new level must hold
) (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic [BUTTON_COUNT-1:0] button_pins,   // raw, asynchronous
    output logic [BUTTON_COUNT-1:0] pressed        // debounced, 1 = pressed
);
    // ---- Polarity and synchroniser -----------------------------------------------------
    // Normalise to 1 = pressed first, so reset (all zeros) means "released".
    logic [BUTTON_COUNT-1:0] pressed_raw;
    logic [BUTTON_COUNT-1:0] sync_stage1;
    logic [BUTTON_COUNT-1:0] sync_stage2;

    assign pressed_raw = (ACTIVE_LOW != 0) ? ~button_pins : button_pins;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_stage1 <= '0;
            sync_stage2 <= '0;
        end else begin
            sync_stage1 <= pressed_raw;
            sync_stage2 <= sync_stage1;
        end
    end

    // ---- Shared sample tick ----------------------------------------------------------------
    localparam integer TICK_BITS = (TICK_CYCLES <= 2) ? 1 : $clog2(TICK_CYCLES);

    logic [TICK_BITS-1:0] tick_count;
    logic                 sample_tick;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_count  <= '0;
            sample_tick <= 1'b0;
        end else if (tick_count == TICK_CYCLES - 1) begin
            tick_count  <= '0;
            sample_tick <= 1'b1;
        end else begin
            tick_count  <= tick_count + 1'b1;
            sample_tick <= 1'b0;
        end
    end

    // ---- One debouncer per button -----------------------------------------------------------
    genvar index;
    generate
        for (index = 0; index < BUTTON_COUNT; index = index + 1) begin : g_debounce
            button_debouncer #(
                .STABLE_TICKS(STABLE_TICKS)
            ) u_debouncer (
                .clk        (clk),
                .rst_n      (rst_n),
                .sample_tick(sample_tick),
                .level_in   (sync_stage2[index]),
                .stable_out (pressed[index])
            );
        end
    endgenerate
endmodule
