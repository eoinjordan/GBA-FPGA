`timescale 1ns/1ps

// =============================================================================
// gba_lcd_top -- Tang Nano 20K: GBA-FPGA display and input validation design
// =============================================================================
// Board : Sipeed Tang Nano 20K, GW2AR-LV18QN88C8/I7
// Panel : HT043IBB-16A3047-H4, 4.3" 480x272 parallel RGB, NV3047 driver,
//         on the Nano 20K 40-pin RGB connector
//
// Exercises every reusable GBA-FPGA block on real hardware without a core or
// a ROM, and reports what it sees over USB serial:
//
//   lcd_pll                27 MHz crystal -> 9 MHz DCLK        LED1, "pll=1"
//   rgb_lcd_timing         NV3047 SYNC-DE timing               stable picture
//   gba_to_480x272_mapper  240x160 frame -> 408x272 + bars     pattern 0/1 geometry
//   gba_test_pattern       four validation patterns            S1 next, S2 previous
//   gba_buttons            onboard S1/S2, debounced            LED4/LED5, "s1=/s2="
//   uart_tx                status line every second            "fps=058"
//
// Clock domains
//   clk_27m  crystal : buttons, pattern select, LEDs, frame-rate meter, UART
//   clk_pix  9 MHz   : raster timing, mapper, pattern, panel outputs
// Crossings (both are single-bit-change safe)
//   pattern select  27m -> pix  Gray-coded, 2-flop sync, applied during VSYNC
//   frame toggle    pix -> 27m  frame_count[0], 3-flop sync + edge detect
//
// NOTE: on the Nano 20K the RGB LCD shares FPGA pins 33-40 with the HDMI
// connector. This design owns those pins; leave HDMI unplugged.
// =============================================================================
module gba_lcd_top #(
    parameter integer CLK_HZ           = 27_000_000,
    parameter integer REPORT_CYCLES    = CLK_HZ,          // status line period (1 s)
    parameter integer DEBOUNCE_TICK    = CLK_HZ / 1000,   // 1 ms debounce sample tick
    parameter integer DEBOUNCE_TICKS   = 10,              // 10 ms stable before accepting
    parameter integer LCD_LATCH_RISING = 1                // 1: panel samples on DCLK rising edge
) (
    input  logic       clk_27m,      // pin 4, 27 MHz crystal
    input  logic       btn_s1,       // pin 88, S1, reads 1 when pressed
    input  logic       btn_s2,       // pin 87, S2, reads 1 when pressed
    output logic [5:0] led_n,        // pins 15-20, LED0-LED5, active-low
    output logic       uart_tx,      // pin 69 -> BL616 USB serial, 115200 8N1

    output logic       lcd_dclk,     // pin 77
    output logic       lcd_de,       // pin 48
    output logic       lcd_hsync,    // pin 25
    output logic       lcd_vsync,    // pin 26
    output logic [4:0] lcd_r,        // pins 42..38 (r[0] = 42)
    output logic [5:0] lcd_g,        // pins 37..32 (g[0] = 37)
    output logic [4:0] lcd_b         // pins 31..27 (b[0] = 31)
);
    // ---- Panel profile: HT043IBB-16A3047-H4 / NV3047 "Typ." column ------------------------------
    // Thbp = H_SYNC + H_BACK = 43, Tvbp = V_SYNC + V_BACK = 12, 531 x 292 total,
    // 58.05 Hz at 9 MHz. Change these (and nothing else) for a different panel.
    localparam integer H_ACTIVE = 480;
    localparam integer H_FRONT  = 8;
    localparam integer H_SYNC   = 4;
    localparam integer H_BACK   = 39;
    localparam integer V_ACTIVE = 272;
    localparam integer V_FRONT  = 8;
    localparam integer V_SYNC   = 4;
    localparam integer V_BACK   = 8;
    localparam logic   SYNC_ACTIVE_LEVEL = 1'b0;   // active-low HSYNC/VSYNC

    // =========================================================================
    // Clocking and resets
    // =========================================================================
    logic clk_pix;
    logic pll_locked;

    lcd_pll u_pll (
        .clk_in (clk_27m),
        .clk_out(clk_pix),
        .locked (pll_locked)
    );

    // The crystal domain comes out of reset right after configuration, even
    // if the PLL never locks, so the LEDs and UART can still report it.
    logic rst_27m_n;
    logic rst_pix_n;

    reset_sync u_rst_27m (
        .clk        (clk_27m),
        .async_rst_n(1'b1),
        .rst_n      (rst_27m_n)
    );

    reset_sync u_rst_pix (
        .clk        (clk_pix),
        .async_rst_n(pll_locked & rst_27m_n),
        .rst_n      (rst_pix_n)
    );

    // =========================================================================
    // Crystal domain: buttons and pattern select
    // =========================================================================
    logic [1:0] keys;          // {s2, s1}, debounced, 1 = pressed
    logic [1:0] keys_prev;
    logic [1:0] pattern_sel;   // binary, 0..3
    logic [1:0] pattern_gray;  // Gray-coded copy for the clock-domain crossing

    gba_buttons #(
        .BUTTON_COUNT(2),
        .ACTIVE_LOW  (0),
        .TICK_CYCLES (DEBOUNCE_TICK),
        .STABLE_TICKS(DEBOUNCE_TICKS)
    ) u_buttons (
        .clk        (clk_27m),
        .rst_n      (rst_27m_n),
        .button_pins({btn_s2, btn_s1}),
        .pressed    (keys)
    );

    // S1 press: next pattern. S2 press: previous. Steps of +/-1 mean the Gray
    // code changes one bit at a time, which is what makes the crossing safe.
    always_ff @(posedge clk_27m or negedge rst_27m_n) begin
        if (!rst_27m_n) begin
            keys_prev    <= 2'b00;
            pattern_sel  <= 2'd0;
            pattern_gray <= 2'd0;
        end else begin
            keys_prev <= keys;
            if (keys[0] && !keys_prev[0] && !(keys[1] && !keys_prev[1])) begin
                pattern_sel <= pattern_sel + 2'd1;
            end else if (keys[1] && !keys_prev[1] && !(keys[0] && !keys_prev[0])) begin
                pattern_sel <= pattern_sel - 2'd1;
            end
            pattern_gray <= pattern_sel ^ (pattern_sel >> 1);
        end
    end

    // =========================================================================
    // Pixel domain: raster -> mapper -> pattern -> panel
    // =========================================================================
    // ---- Pattern select crossing, applied only during VSYNC -------------------------------------
    logic [1:0] pattern_gray_s1;
    logic [1:0] pattern_gray_s2;
    logic [1:0] pattern_frame;     // pattern used for the current frame

    // ---- Stage 1: raster timing (registered outputs) ---------------------------------------------
    logic        t_de;
    logic        t_hsync;
    logic        t_vsync;
    /* verilator lint_off UNUSEDSIGNAL */   // 480x272 needs only bits [8:0]
    logic [11:0] t_x;
    logic [11:0] t_y;
    /* verilator lint_on UNUSEDSIGNAL */
    logic        t_frame_start;

    rgb_lcd_timing #(
        .H_ACTIVE(H_ACTIVE), .H_FRONT(H_FRONT), .H_SYNC(H_SYNC), .H_BACK(H_BACK),
        .V_ACTIVE(V_ACTIVE), .V_FRONT(V_FRONT), .V_SYNC(V_SYNC), .V_BACK(V_BACK),
        .HSYNC_ACTIVE(SYNC_ACTIVE_LEVEL), .VSYNC_ACTIVE(SYNC_ACTIVE_LEVEL)
    ) u_timing (
        .pixel_clk  (clk_pix),
        .rst_n      (rst_pix_n),
        .lcd_hsync  (t_hsync),
        .lcd_vsync  (t_vsync),
        .lcd_de     (t_de),
        .pixel_x    (t_x),
        .pixel_y    (t_y),
        .frame_start(t_frame_start)
    );

    logic [7:0] frame_count;       // bit 0 toggles every frame (crossing), bit 5 = heartbeat

    always_ff @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            pattern_gray_s1 <= 2'd0;
            pattern_gray_s2 <= 2'd0;
            pattern_frame   <= 2'd0;
            frame_count     <= 8'd0;
        end else begin
            pattern_gray_s1 <= pattern_gray;
            pattern_gray_s2 <= pattern_gray_s1;
            if (t_vsync == SYNC_ACTIVE_LEVEL) begin
                pattern_frame <= {pattern_gray_s2[1], pattern_gray_s2[1] ^ pattern_gray_s2[0]};
            end
            if (t_frame_start) begin
                frame_count <= frame_count + 8'd1;
            end
        end
    end

    // ---- Combinational: panel -> GBA coordinates -> colour ------------------------------------------
    logic        src_active;
    logic [7:0]  src_x;
    logic [7:0]  src_y;
    logic [14:0] color_bgr555;

    gba_to_480x272_mapper u_mapper (
        .panel_x      (t_x[8:0]),
        .panel_y      (t_y[8:0]),
        .panel_active (t_de),
        .source_active(src_active),
        .source_x     (src_x),
        .source_y     (src_y)
    );

    gba_test_pattern u_pattern (
        .clk          (clk_pix),
        .rst_n        (rst_pix_n),
        .frame_start  (t_frame_start),
        .frame_count  (frame_count),
        .pattern_sel  (pattern_frame),
        .source_active(src_active),
        .source_x     (src_x),
        .source_y     (src_y),
        .color_bgr555 (color_bgr555)
    );

    // ---- Stage 2: register the pixel with its framing; RGB is zero in blanking ----------------------
    logic        p_de;
    logic        p_hsync;
    logic        p_vsync;
    logic [14:0] p_color;

    always_ff @(posedge clk_pix or negedge rst_pix_n) begin
        if (!rst_pix_n) begin
            p_de    <= 1'b0;
            p_hsync <= ~SYNC_ACTIVE_LEVEL;
            p_vsync <= ~SYNC_ACTIVE_LEVEL;
            p_color <= 15'd0;
        end else begin
            p_de    <= t_de;
            p_hsync <= t_hsync;
            p_vsync <= t_vsync;
            p_color <= t_de ? color_bgr555 : 15'd0;
        end
    end

    // ---- Stage 3: panel output registers, launched half a cycle from the latch edge -------------------
    // The NV3047 samples RGB/DE/syncs on the DCLK rising edge (12 ns setup and
    // hold). Launching from the falling edge centres every transition between
    // two rising edges: ~55 ns of setup and hold at 9 MHz. BGR555 -> RGB565
    // replicates the green MSB so 5-bit full scale maps to 6-bit full scale.
    logic [4:0] out_r;
    logic [5:0] out_g;
    logic [4:0] out_b;

    assign out_r = p_color[4:0];
    assign out_g = {p_color[9:5], p_color[9]};
    assign out_b = p_color[14:10];

    generate
        if (LCD_LATCH_RISING != 0) begin : g_launch_falling
            always_ff @(negedge clk_pix or negedge rst_pix_n) begin
                if (!rst_pix_n) begin
                    lcd_de    <= 1'b0;
                    lcd_hsync <= ~SYNC_ACTIVE_LEVEL;
                    lcd_vsync <= ~SYNC_ACTIVE_LEVEL;
                    lcd_r     <= 5'd0;
                    lcd_g     <= 6'd0;
                    lcd_b     <= 5'd0;
                end else begin
                    lcd_de    <= p_de;
                    lcd_hsync <= p_hsync;
                    lcd_vsync <= p_vsync;
                    lcd_r     <= out_r;
                    lcd_g     <= out_g;
                    lcd_b     <= out_b;
                end
            end
        end else begin : g_launch_rising
            always_ff @(posedge clk_pix or negedge rst_pix_n) begin
                if (!rst_pix_n) begin
                    lcd_de    <= 1'b0;
                    lcd_hsync <= ~SYNC_ACTIVE_LEVEL;
                    lcd_vsync <= ~SYNC_ACTIVE_LEVEL;
                    lcd_r     <= 5'd0;
                    lcd_g     <= 6'd0;
                    lcd_b     <= 5'd0;
                end else begin
                    lcd_de    <= p_de;
                    lcd_hsync <= p_hsync;
                    lcd_vsync <= p_vsync;
                    lcd_r     <= out_r;
                    lcd_g     <= out_g;
                    lcd_b     <= out_b;
                end
            end
        end
    endgenerate

    // The pixel clock goes straight to the panel.
    assign lcd_dclk = clk_pix;

    // =========================================================================
    // Crystal domain: frame-rate meter, UART status, LEDs
    // =========================================================================
    logic [2:0] frame_sync;        // frame_count[0] -> clk_27m
    logic [1:0] lock_sync;
    logic       frame_tick;

    always_ff @(posedge clk_27m or negedge rst_27m_n) begin
        if (!rst_27m_n) begin
            frame_sync <= 3'b000;
            lock_sync  <= 2'b00;
        end else begin
            frame_sync <= {frame_sync[1:0], frame_count[0]};
            lock_sync  <= {lock_sync[0], pll_locked};
        end
    end

    assign frame_tick = frame_sync[2] ^ frame_sync[1];

    status_reporter #(
        .CLK_HZ       (CLK_HZ),
        .BAUD         (115_200),
        .REPORT_CYCLES(REPORT_CYCLES)
    ) u_status (
        .clk       (clk_27m),
        .rst_n     (rst_27m_n),
        .frame_tick(frame_tick),
        .pattern   (pattern_sel),
        .buttons   (keys),
        .pll_locked(lock_sync[1]),
        .uart_txd  (uart_tx)
    );

    // LEDs are active-low: 0 lights the LED.
    //   LED0 heartbeat (~0.9 Hz, from the frame counter)   LED1 PLL locked
    //   LED2/LED3 pattern bits 0/1                          LED4/LED5 S1/S2 held
    assign led_n = ~{keys[1], keys[0], pattern_sel[1], pattern_sel[0], lock_sync[1], frame_count[5]};
endmodule
