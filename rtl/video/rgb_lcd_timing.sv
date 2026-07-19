`timescale 1ns/1ps

module rgb_lcd_timing #(
    parameter integer H_ACTIVE = 480,
    parameter integer H_FRONT  = 2,
    parameter integer H_SYNC   = 41,
    parameter integer H_BACK   = 2,
    parameter integer V_ACTIVE = 272,
    parameter integer V_FRONT  = 2,
    parameter integer V_SYNC   = 10,
    parameter integer V_BACK   = 2,
    parameter logic   HSYNC_ACTIVE = 1'b0,
    parameter logic   VSYNC_ACTIVE = 1'b0
) (
    input  logic        pixel_clk,
    input  logic        rst_n,
    output logic        lcd_hsync,
    output logic        lcd_vsync,
    output logic        lcd_de,
    output logic [11:0] pixel_x,
    output logic [11:0] pixel_y,
    output logic        frame_start
);
    localparam integer H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;
    localparam integer V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    localparam integer H_WIDTH = (H_TOTAL <= 2) ? 1 : $clog2(H_TOTAL);
    localparam integer V_WIDTH = (V_TOTAL <= 2) ? 1 : $clog2(V_TOTAL);

    logic [H_WIDTH-1:0] h_counter;
    logic [V_WIDTH-1:0] v_counter;
    logic hsync_window;
    logic vsync_window;

    always_ff @(posedge pixel_clk or negedge rst_n) begin
        if (!rst_n) begin
            h_counter <= '0;
            v_counter <= '0;
        end else if (h_counter == H_TOTAL - 1) begin
            h_counter <= '0;
            if (v_counter == V_TOTAL - 1) begin
                v_counter <= '0;
            end else begin
                v_counter <= v_counter + 1'b1;
            end
        end else begin
            h_counter <= h_counter + 1'b1;
        end
    end

    always_comb begin
        lcd_de = (h_counter < H_ACTIVE) && (v_counter < V_ACTIVE);
        hsync_window = (h_counter >= H_ACTIVE + H_FRONT) &&
                       (h_counter <  H_ACTIVE + H_FRONT + H_SYNC);
        vsync_window = (v_counter >= V_ACTIVE + V_FRONT) &&
                       (v_counter <  V_ACTIVE + V_FRONT + V_SYNC);

        lcd_hsync = hsync_window ? HSYNC_ACTIVE : ~HSYNC_ACTIVE;
        lcd_vsync = vsync_window ? VSYNC_ACTIVE : ~VSYNC_ACTIVE;
        pixel_x = lcd_de ? h_counter : 12'd0;
        pixel_y = lcd_de ? v_counter : 12'd0;
        frame_start = (h_counter == 0) && (v_counter == 0);
    end
endmodule
