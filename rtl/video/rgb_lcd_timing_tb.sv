`timescale 1ns/1ps

module rgb_lcd_timing_tb;
    logic pixel_clk = 1'b0;
    logic rst_n = 1'b0;
    logic lcd_hsync;
    logic lcd_vsync;
    logic lcd_de;
    logic [11:0] pixel_x;
    logic [11:0] pixel_y;
    logic frame_start;
    integer active_pixels = 0;
    integer frames = 0;
    integer errors = 0;

    always #5 pixel_clk = ~pixel_clk;

    rgb_lcd_timing #(
        .H_ACTIVE(4),
        .H_FRONT(1),
        .H_SYNC(1),
        .H_BACK(1),
        .V_ACTIVE(3),
        .V_FRONT(1),
        .V_SYNC(1),
        .V_BACK(1)
    ) dut (
        .pixel_clk,
        .rst_n,
        .lcd_hsync,
        .lcd_vsync,
        .lcd_de,
        .pixel_x,
        .pixel_y,
        .frame_start
    );

    always_ff @(posedge pixel_clk) begin
        if (rst_n) begin
            if (frame_start) begin
                frames <= frames + 1;
                if (frames == 1 && active_pixels != 12) begin
                    $display("ERROR: active pixel count %0d expected 12", active_pixels);
                    errors <= errors + 1;
                end
                // frame_start coincides with active pixel (0,0).
                active_pixels <= lcd_de ? 1 : 0;
            end else if (lcd_de) begin
                active_pixels <= active_pixels + 1;
            end
        end
    end

    initial begin
        repeat (3) @(posedge pixel_clk);
        rst_n <= 1'b1;
        wait(frames == 2);
        @(posedge pixel_clk);
        if (errors == 0) begin
            $display("PASS: rgb_lcd_timing");
        end else begin
            $fatal(1, "FAIL: %0d error(s)", errors);
        end
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "Timeout");
    end
endmodule
