`timescale 1ns/1ps

// =============================================================================
// gba_lcd_top_tb -- end-to-end simulation of the Tang Nano 20K design
// =============================================================================
// Runs the real top level (with the behavioural rPLL model) from power-up and
// looks only at the board pins, the way the hardware will be judged:
//
//   * panel model samples lcd_* on DCLK rising edges, as the NV3047 does, and
//     checks line/frame geometry (480 DE pixels per line, 272 lines, 531-clock
//     lines, 292-line frames, sync edge 43 clocks / 12 lines before data);
//   * every pixel of frame 0 (pattern 0) and frame 1 (pattern 1) is compared
//     with a reference built from true divisions, which also proves the
//     pipeline keeps colour aligned with DE and the RGB565 bit mapping;
//   * S1 is pressed during frame 0: the new pattern must start exactly at
//     frame 1, and LED2 / LED4 must follow;
//   * the UART status line is decoded and checked field by field.
//
// Simulated time is shortened: 1 us debounce tick, 37 ms status window.
// =============================================================================
module gba_lcd_top_tb;
    // ---- Board ---------------------------------------------------------------------------------
    localparam integer REPORT_CYCLES = 1_000_000;          // 37 ms (1 s on hardware)
    localparam integer UART_BIT      = (27_000_000 + 57_600) / 115_200;   // 234 clocks

    logic       clk_27m = 1'b0;
    logic       btn_s1  = 1'b0;
    logic       btn_s2  = 1'b0;
    wire  [5:0] led_n;
    wire        uart_tx;
    wire        lcd_dclk;
    wire        lcd_de;
    wire        lcd_hsync;
    wire        lcd_vsync;
    wire  [4:0] lcd_r;
    wire  [5:0] lcd_g;
    wire  [4:0] lcd_b;
    integer     errors = 0;

    always #18.5185 clk_27m = ~clk_27m;                     // 27 MHz crystal

    gba_lcd_top #(
        .REPORT_CYCLES (REPORT_CYCLES),
        .DEBOUNCE_TICK (27),
        .DEBOUNCE_TICKS(10)
    ) dut (
        .clk_27m  (clk_27m),
        .btn_s1   (btn_s1),
        .btn_s2   (btn_s2),
        .led_n    (led_n),
        .uart_tx  (uart_tx),
        .lcd_dclk (lcd_dclk),
        .lcd_de   (lcd_de),
        .lcd_hsync(lcd_hsync),
        .lcd_vsync(lcd_vsync),
        .lcd_r    (lcd_r),
        .lcd_g    (lcd_g),
        .lcd_b    (lcd_b)
    );

    // ---- Reference picture ------------------------------------------------------------------------
    // Written independently of the RTL: true divisions for the scaling.
    function automatic logic [14:0] bgr(input integer r, input integer g, input integer b);
        bgr = {b[4:0], g[4:0], r[4:0]};
    endfunction

    function automatic logic [14:0] reference_color(input integer pattern, input integer px, input integer py);
        integer      sx, sy, level;
        logic        in_image, outline, on_cross;
        logic [14:0] base;
        in_image = (px >= 36) && (px < 444);
        sx      = (px - 36) * 240 / 408;
        sy      = py * 160 / 272;
        outline = (sx == 0) || (sx == 239) || (sy == 0) || (sy == 159);
        on_cross = (sx == 119) || (sx == 120) || (sy == 79) || (sy == 80);
        level   = (sx * 17) / 128;          // ramp definition from gba_test_pattern.sv
        if (pattern == 0) begin
            if (!in_image) begin
                reference_color = bgr(6, 6, 6);
            end else begin
                if (sy < 112) begin
                    case (sx / 30)
                        0: base = bgr(31, 31, 31);
                        1: base = bgr(31, 31, 0);
                        2: base = bgr(0, 31, 31);
                        3: base = bgr(0, 31, 0);
                        4: base = bgr(31, 0, 31);
                        5: base = bgr(31, 0, 0);
                        6: base = bgr(0, 0, 31);
                        default: base = bgr(0, 0, 0);
                    endcase
                end else if (sy < 128) base = bgr(level, 0, 0);
                else if (sy < 144)     base = bgr(0, level, 0);
                else                   base = bgr(0, 0, level);
                reference_color = outline ? ~base : base;
            end
        end else begin
            if (!in_image)               reference_color = bgr(0, 0, 0);
            else if (outline)            reference_color = bgr(31, 31, 31);
            else if (on_cross)           reference_color = bgr(31, 0, 0);
            else if (((sx / 8) + (sy / 8)) % 2 == 1) reference_color = bgr(22, 22, 22);
            else                         reference_color = bgr(8, 8, 12);
        end
    endfunction

    // ---- Panel model: sample on DCLK rising edges ------------------------------------------------------
    integer frame        = 0;      // 0 = first frame after reset
    integer line         = 0;      // visible line within the frame
    integer column       = 0;
    integer clk_count    = 0;
    integer hs_edge      = -1;
    integer vs_edge      = -1;
    integer pixels_seen [0:1];
    logic   prev_de      = 1'b0;
    logic   prev_hs      = 1'b1;
    logic   prev_vs      = 1'b1;
    logic [14:0] want;
    logic [15:0] want_rgb565;

    initial begin
        pixels_seen[0] = 0;
        pixels_seen[1] = 0;
    end

    always @(posedge lcd_dclk) if (!$isunknown({lcd_de, lcd_hsync, lcd_vsync, lcd_r, lcd_g, lcd_b})) begin
        clk_count = clk_count + 1;

        if (!lcd_hsync && prev_hs) begin                       // HSYNC leading edge
            if (hs_edge >= 0 && clk_count - hs_edge != 531) begin
                $display("ERROR: line period %0d clocks, expected 531", clk_count - hs_edge);
                errors = errors + 1;
            end
            hs_edge = clk_count;
        end
        if (!lcd_vsync && prev_vs) begin                       // VSYNC leading edge
            if (vs_edge >= 0 && clk_count - vs_edge != 531 * 292) begin
                $display("ERROR: frame period %0d clocks, expected %0d", clk_count - vs_edge, 531 * 292);
                errors = errors + 1;
            end
            if (line != 272) begin
                $display("ERROR: frame %0d had %0d visible lines", frame, line);
                errors = errors + 1;
            end
            vs_edge = clk_count;
            frame   = frame + 1;
            line    = 0;
        end

        if (lcd_de && !prev_de) begin                          // first pixel of a line
            column = 0;
            if (hs_edge >= 0 && clk_count - hs_edge != 43) begin
                $display("ERROR: HSYNC to data %0d clocks, expected 43", clk_count - hs_edge);
                errors = errors + 1;
            end
            if (line == 0 && vs_edge >= 0 && clk_count - vs_edge != 12 * 531) begin
                $display("ERROR: VSYNC to first line %0d clocks, expected %0d", clk_count - vs_edge, 12 * 531);
                errors = errors + 1;
            end
        end
        if (!lcd_de && prev_de) begin                          // line finished
            if (column != 480) begin
                $display("ERROR: frame %0d line %0d had %0d DE pixels", frame, line, column);
                errors = errors + 1;
            end
            line = line + 1;
        end

        if (lcd_de) begin
            if (frame <= 1) begin
                want        = reference_color(frame, column, line);
                want_rgb565 = {want[4:0], want[9:5], want[9], want[14:10]};
                if ({lcd_r, lcd_g, lcd_b} !== want_rgb565) begin
                    if (errors < 10) begin
                        $display("ERROR: frame %0d pixel (%0d,%0d) rgb565=%h expected %h",
                                 frame, column, line, {lcd_r, lcd_g, lcd_b}, want_rgb565);
                    end
                    errors = errors + 1;
                end
                pixels_seen[frame] = pixels_seen[frame] + 1;
            end
            column = column + 1;
        end else if ({lcd_r, lcd_g, lcd_b} !== 16'h0000) begin
            $display("ERROR: RGB not blanked while DE is low");
            errors = errors + 1;
        end

        prev_de = lcd_de;
        prev_hs = lcd_hsync;
        prev_vs = lcd_vsync;
    end

    // ---- Buttons and LEDs ----------------------------------------------------------------------------
    initial begin
        wait (frame == 0 && line == 100);
        if (led_n[1] !== 1'b0) begin
            $display("ERROR: LED1 (PLL lock) not lit");
            errors = errors + 1;
        end
        btn_s1 = 1'b1;                                         // press S1 for 50 us
        #50_000;
        if (led_n[4] !== 1'b0 || led_n[2] !== 1'b0 || led_n[3] !== 1'b1) begin
            $display("ERROR: LEDs after S1 press: led_n=%b (want LED4 and LED2 lit)", led_n);
            errors = errors + 1;
        end
        btn_s1 = 1'b0;
    end

    // ---- UART receiver and status-line check ------------------------------------------------------------
    // '#' marks the frame-rate digits, which only need to be digits here.
    localparam integer LINE_LEN = 63;
    localparam logic [8*LINE_LEN-1:0] EXPECTED_LINE =
        "gba-fpga tn20k lcd fps=### pattern=1 s1=0 s2=0 pll=1 up=00001\015\012";

    integer     char_count = 0;
    integer     bit_index;
    integer     fps_value  = 0;
    logic [7:0] rx_byte;
    logic [7:0] want_byte;

    initial begin
        while (char_count < LINE_LEN) begin
            @(negedge uart_tx);
            repeat (UART_BIT / 2) @(posedge clk_27m);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                repeat (UART_BIT) @(posedge clk_27m);
                rx_byte[bit_index] = uart_tx;
            end
            repeat (UART_BIT) @(posedge clk_27m);             // stop bit
            want_byte = EXPECTED_LINE[8*(LINE_LEN - 1 - char_count) +: 8];
            if (want_byte == "#") begin
                if (rx_byte < "0" || rx_byte > "9") begin
                    $display("ERROR: UART fps character %0d is 0x%h, not a digit", char_count, rx_byte);
                    errors = errors + 1;
                end
                fps_value = fps_value * 10 + (rx_byte - "0");
            end else if (rx_byte !== want_byte) begin
                $display("ERROR: UART character %0d is 0x%h, expected 0x%h", char_count, rx_byte, want_byte);
                errors = errors + 1;
            end
            char_count = char_count + 1;
        end

        // 37 ms window from power-up covers frame starts at ~0, 17.3 and 34.5 ms.
        if (fps_value < 2 || fps_value > 4) begin
            $display("ERROR: reported %0d frames in the window, expected 2-4", fps_value);
            errors = errors + 1;
        end
        if (pixels_seen[0] != 480 * 272 || pixels_seen[1] != 480 * 272) begin
            $display("ERROR: checked %0d / %0d pixels in frames 0/1, expected %0d each",
                     pixels_seen[0], pixels_seen[1], 480 * 272);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: gba_lcd_top (2 full frames pixel-exact, S1 -> pattern 1, UART fps=%0d)", fps_value);
        end else begin
            $fatal(1, "FAIL: gba_lcd_top %0d error(s)", errors);
        end
        $finish;
    end

    initial begin
        #80_000_000;
        $fatal(1, "Timeout");
    end
endmodule
