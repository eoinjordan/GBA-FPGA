`timescale 1ns/1ps

// =============================================================================
// gba_buttons_tb -- debounce behaviour for both pin polarities
// =============================================================================
// Two instances share one clock:
//   pad   10 buttons, ACTIVE_LOW=1 (GBA pad wiring)
//   board  2 buttons, ACTIVE_LOW=0 (Tang Nano 20K S1/S2 wiring)
// Tick = 2 clocks, STABLE_TICKS = 4, so a level must hold for 7-8 clocks.
//
// Checks: released after reset; bounce shorter than the window is ignored;
// a held press is accepted within the window; only the pressed bit changes;
// release is debounced the same way; the active-high variant mirrors it.
// While `hold_steady` is set, a monitor fails the test if either output moves
// at any clock, so a debouncer that merely samples periodically is caught.
// =============================================================================
module gba_buttons_tb;
    // ---- Clock, reset, DUTs ---------------------------------------------------------------
    localparam integer TICK_CYCLES  = 2;
    localparam integer STABLE_TICKS = 4;
    localparam integer WINDOW       = TICK_CYCLES * STABLE_TICKS;   // debounce window, clocks
    localparam integer SETTLE       = WINDOW + 6;   // + 2 sync + tick phase + margin

    logic       clk   = 1'b0;
    logic       rst_n = 1'b0;
    logic [9:0] pad_pins   = 10'h3FF;   // active-low: all released
    logic [1:0] board_pins = 2'b00;     // active-high: all released
    logic [9:0] pad_pressed;
    logic [1:0] board_pressed;
    integer     errors = 0;
    logic       hold_steady = 1'b0;   // outputs must not change while set

    always #5 clk = ~clk;

    gba_buttons #(
        .BUTTON_COUNT(10), .ACTIVE_LOW(1), .TICK_CYCLES(TICK_CYCLES), .STABLE_TICKS(STABLE_TICKS)
    ) pad (
        .clk(clk), .rst_n(rst_n), .button_pins(pad_pins), .pressed(pad_pressed)
    );

    gba_buttons #(
        .BUTTON_COUNT(2), .ACTIVE_LOW(0), .TICK_CYCLES(TICK_CYCLES), .STABLE_TICKS(STABLE_TICKS)
    ) board (
        .clk(clk), .rst_n(rst_n), .button_pins(board_pins), .pressed(board_pressed)
    );

    task automatic expect_state(input string what, input logic [9:0] pad_want, input logic [1:0] board_want);
        if (pad_pressed !== pad_want || board_pressed !== board_want) begin
            $display("ERROR: %s: pad=%b (want %b) board=%b (want %b)",
                     what, pad_pressed, pad_want, board_pressed, board_want);
            errors = errors + 1;
        end
    endtask

    // ---- Continuous monitor ---------------------------------------------------------------------
    logic [9:0] pad_seen;
    logic [1:0] board_seen;
    always @(posedge clk) begin
        if (hold_steady && (pad_pressed !== pad_seen || board_pressed !== board_seen)) begin
            $display("ERROR: output changed during a bounce/glitch window (pad=%b board=%b)",
                     pad_pressed, board_pressed);
            errors = errors + 1;
        end
        pad_seen   <= pad_pressed;
        board_seen <= board_pressed;
    end

    // ---- Stimulus ---------------------------------------------------------------------------------
    initial begin
        repeat (3) @(posedge clk);
        rst_n <= 1'b1;
        repeat (SETTLE) @(posedge clk);
        expect_state("after reset", 10'b0, 2'b00);

        // Bounce: alternate every 2 clocks, never stable for a full window.
        hold_steady = 1'b1;
        repeat (6) begin
            pad_pins[0] <= 1'b0; board_pins[1] <= 1'b1;
            repeat (2) @(posedge clk);
            pad_pins[0] <= 1'b1; board_pins[1] <= 1'b0;
            repeat (2) @(posedge clk);
        end
        repeat (4) @(posedge clk);
        hold_steady = 1'b0;
        expect_state("bounce rejected", 10'b0, 2'b00);

        // Held press is accepted within SETTLE clocks.
        pad_pins[0] <= 1'b0; board_pins[1] <= 1'b1;
        repeat (SETTLE) @(posedge clk);
        expect_state("press accepted", 10'b00_0000_0001, 2'b10);

        // Another button: only its own bit changes.
        pad_pins[9] <= 1'b0;
        repeat (SETTLE) @(posedge clk);
        expect_state("second press", 10'b10_0000_0001, 2'b10);

        // A one-clock glitch back to "released" must not release the button.
        hold_steady = 1'b1;
        pad_pins[0] <= 1'b1; board_pins[1] <= 1'b0;
        @(posedge clk);
        pad_pins[0] <= 1'b0; board_pins[1] <= 1'b1;
        repeat (SETTLE) @(posedge clk);
        hold_steady = 1'b0;
        expect_state("glitch ignored", 10'b10_0000_0001, 2'b10);

        // Release everything.
        pad_pins   <= 10'h3FF;
        board_pins <= 2'b00;
        repeat (SETTLE) @(posedge clk);
        expect_state("release accepted", 10'b0, 2'b00);

        if (errors == 0) begin
            $display("PASS: gba_buttons (active-low pad and active-high board buttons)");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end
endmodule
