`timescale 1ns/1ps

// =============================================================================
// status_reporter -- once-per-second board status on the USB serial port
// =============================================================================
// Every REPORT_CYCLES clocks (1 s at the default) it snapshots the counters
// and sends one line at 115200 8N1 through the Nano 20K's BL616 USB bridge:
//
//   gba-fpga tn20k lcd fps=058 pattern=0 s1=0 s2=0 pll=1 up=00042\r\n
//
//   fps      video frames counted in the last second, timed by the 27 MHz
//            crystal, so it independently checks the PLL and timing
//            generator (58 expected: 9 MHz / (531 x 292) = 58.05 Hz)
//   pattern  test pattern shown (0..3)
//   s1 / s2  debounced onboard buttons (1 = held)
//   pll      rPLL lock
//   up       seconds since configuration (wraps at 99999)
//
// Counters are kept in BCD so no binary-to-decimal converter is needed.
// =============================================================================
module status_reporter #(
    parameter integer CLK_HZ        = 27_000_000,
    parameter integer BAUD          = 115_200,
    parameter integer REPORT_CYCLES = CLK_HZ
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       frame_tick,     // one pulse per video frame, in this clock domain
    input  logic [1:0] pattern,
    input  logic [1:0] buttons,        // {s2, s1}, 1 = pressed
    input  logic       pll_locked,
    output logic       uart_txd
);
    // ---- Message template -----------------------------------------------------------------
    // Field characters in TEXT are overwritten with live values when sent.
    localparam integer TEXT_LEN = 61;
    localparam logic [8*TEXT_LEN-1:0] TEXT =
        "gba-fpga tn20k lcd fps=000 pattern=0 s1=0 s2=0 pll=0 up=00000";
    localparam integer MSG_LEN  = TEXT_LEN + 2;     // + CR LF
    localparam integer POS_FPS  = 23;               // 3 digits
    localparam integer POS_PAT  = 35;
    localparam integer POS_S1   = 40;
    localparam integer POS_S2   = 45;
    localparam integer POS_PLL  = 51;
    localparam integer POS_UP   = 56;               // 5 digits

    // ---- BCD helpers -------------------------------------------------------------------------
    // Increment a 5-digit packed BCD value; wraps 99999 -> 00000.
    function automatic logic [19:0] bcd_increment(input logic [19:0] value);
        logic   carry;
        integer digit;
        bcd_increment = value;
        carry = 1'b1;
        for (digit = 0; digit < 5; digit = digit + 1) begin
            if (carry) begin
                if (bcd_increment[4*digit +: 4] == 4'd9) begin
                    bcd_increment[4*digit +: 4] = 4'd0;
                end else begin
                    bcd_increment[4*digit +: 4] = bcd_increment[4*digit +: 4] + 4'd1;
                    carry = 1'b0;
                end
            end
        end
    endfunction

    function automatic logic [7:0] ascii_digit(input logic [3:0] nibble);
        ascii_digit = {4'h3, nibble};
    endfunction

    // ---- Report window and live counters ----------------------------------------------------------
    localparam integer WINDOW_BITS = $clog2(REPORT_CYCLES);

    logic [WINDOW_BITS-1:0] window_count;
    logic [11:0]            frames_bcd;     // frames this window, 3 digits, saturates at 999
    logic [19:0]            uptime_bcd;     // 5 digits, changes once per window
    logic                   window_end;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [19:0]            frames_next;    // frames_bcd + 1 via the 5-digit incrementer; [19:12] unused
    /* verilator lint_on UNUSEDSIGNAL */

    assign window_end  = (window_count == REPORT_CYCLES - 1);
    assign frames_next = bcd_increment({8'd0, frames_bcd});

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            window_count <= '0;
            frames_bcd   <= 12'd0;
            uptime_bcd   <= 20'd0;
        end else begin
            window_count <= window_end ? '0 : window_count + 1'b1;
            if (window_end) begin
                frames_bcd <= frame_tick ? 12'd1 : 12'd0;   // a tick on the boundary starts the next window
                uptime_bcd <= bcd_increment(uptime_bcd);
            end else if (frame_tick && frames_bcd != 12'h999) begin
                frames_bcd <= frames_next[11:0];
            end
        end
    end

    // ---- Snapshot and line sender -------------------------------------------------------------------
    // The frame count is latched at the window boundary; the other fields one
    // clock later, once uptime_bcd holds the new second. uptime_bcd itself is
    // read directly: it cannot change while a line (~5.5 ms) is being sent.
    logic [11:0] snap_fps;
    logic [1:0]  snap_pattern;
    logic [1:0]  snap_buttons;
    logic        snap_pll;
    logic        start_pending;
    logic        sending;
    logic [5:0]  char_index;
    logic [7:0]  char_byte;
    logic        tx_ready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snap_fps      <= 12'd0;
            snap_pattern  <= 2'd0;
            snap_buttons  <= 2'd0;
            snap_pll      <= 1'b0;
            start_pending <= 1'b0;
            sending       <= 1'b0;
            char_index    <= 6'd0;
        end else begin
            start_pending <= 1'b0;
            if (window_end && !sending) begin
                snap_fps      <= frames_bcd[11:0];
                start_pending <= 1'b1;
            end
            if (start_pending) begin
                snap_pattern <= pattern;
                snap_buttons <= buttons;
                snap_pll     <= pll_locked;
                sending      <= 1'b1;
                char_index   <= 6'd0;
            end else if (sending && tx_ready) begin
                if (char_index == MSG_LEN - 1) begin
                    sending <= 1'b0;
                end
                char_index <= char_index + 6'd1;
            end
        end
    end

    // Live field characters, formed outside the mux so it only selects whole bytes.
    logic [7:0] fps_char2, fps_char1, fps_char0;
    logic [7:0] up_char4, up_char3, up_char2, up_char1, up_char0;
    logic [7:0] pattern_char, s1_char, s2_char, pll_char;

    assign fps_char2    = ascii_digit(snap_fps[11:8]);
    assign fps_char1    = ascii_digit(snap_fps[7:4]);
    assign fps_char0    = ascii_digit(snap_fps[3:0]);
    assign up_char4     = ascii_digit(uptime_bcd[19:16]);
    assign up_char3     = ascii_digit(uptime_bcd[15:12]);
    assign up_char2     = ascii_digit(uptime_bcd[11:8]);
    assign up_char1     = ascii_digit(uptime_bcd[7:4]);
    assign up_char0     = ascii_digit(uptime_bcd[3:0]);
    assign pattern_char = ascii_digit({2'b00, snap_pattern});
    assign s1_char      = ascii_digit({3'b000, snap_buttons[0]});
    assign s2_char      = ascii_digit({3'b000, snap_buttons[1]});
    assign pll_char     = ascii_digit({3'b000, snap_pll});

    // Character mux: template text with the live fields substituted.
    always_comb begin
        char_byte = TEXT[8*(TEXT_LEN - 1 - char_index) +: 8];
        case (char_index)
            POS_FPS:      char_byte = fps_char2;
            POS_FPS + 1:  char_byte = fps_char1;
            POS_FPS + 2:  char_byte = fps_char0;
            POS_PAT:      char_byte = pattern_char;
            POS_S1:       char_byte = s1_char;
            POS_S2:       char_byte = s2_char;
            POS_PLL:      char_byte = pll_char;
            POS_UP:       char_byte = up_char4;
            POS_UP + 1:   char_byte = up_char3;
            POS_UP + 2:   char_byte = up_char2;
            POS_UP + 3:   char_byte = up_char1;
            POS_UP + 4:   char_byte = up_char0;
            TEXT_LEN:     char_byte = 8'h0D;   // CR
            TEXT_LEN + 1: char_byte = 8'h0A;   // LF
            default: begin
            end
        endcase
    end

    // ---- UART -------------------------------------------------------------------------------------------
    uart_tx #(
        .CLKS_PER_BIT((CLK_HZ + BAUD / 2) / BAUD)
    ) u_uart (
        .clk     (clk),
        .rst_n   (rst_n),
        .tx_valid(sending),
        .tx_data (char_byte),
        .tx_ready(tx_ready),
        .tx      (uart_txd)
    );
endmodule
