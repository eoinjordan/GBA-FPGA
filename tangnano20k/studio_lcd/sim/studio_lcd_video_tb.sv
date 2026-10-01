`timescale 1ns/1ps
module studio_lcd_video_tb;
    reg clk=0,pix_clk=0,resetn=0,show=0,write=0;
    always #5 clk=~clk;
    always #15 pix_clk=~pix_clk;
    reg [14:0] address=0;
    reg [31:0] data=0;
    reg [3:0] strobes=15;
    wire [31:0] read_data,frames;
    wire dclk,de,hs,vs;
    wire [4:0] r,b;
    wire [5:0] g;
    studio_lcd_video dut(.clk(clk),.write(write),.address(address),.data(data),
        .strobes(strobes),.read_data(read_data),.pix_clk(pix_clk),.resetn(resetn),
        .show(show),.frames(frames),.lcd_dclk(dclk),.lcd_de(de),.lcd_hsync(hs),
        .lcd_vsync(vs),.lcd_r(r),.lcd_g(g),.lcd_b(b));
    function [15:0] color(input integer x,input integer y);
        color=(x%32)|((y%32)<<5)|(7<<10);
    endfunction
    integer i,x,y,active_pixels,image_pixels;
    reg checking=0;
    initial begin
        repeat(5) @(negedge clk);
        for (i=0;i<19200;i=i+1) begin
            address=i; x=(i%120)*2; y=i/120;
            data={color(x+1,y),color(x,y)}; write=1;
            @(negedge clk);
        end
        write=0; resetn=1; show=1;
        wait(frames==2);
        @(negedge pix_clk); #1; checking=1; active_pixels=0;image_pixels=0;
        wait(frames==3);
        @(negedge pix_clk); #1;
        if (active_pixels!=480*272 || image_pixels!=240*160)
            $fatal(1,"Raster counts: active=%0d image=%0d",active_pixels,image_pixels);
        $display("PASS: full LCD raster, framebuffer banks, RGB555-to-RGB565 and centring");
        $finish;
    end
    reg [15:0] expected;
    reg expected_active;
    always @(posedge pix_clk) begin
        expected_active=dut.active;
        expected=color(dut.x-120,dut.y-56);
    end
    always @(negedge pix_clk) begin
        #1;
        if (checking && frames==2 && de) begin
            active_pixels=active_pixels+1;
            if (expected_active) begin
                image_pixels=image_pixels+1;
                if ({b,g[5:1],r}!==expected[14:0])
                    $fatal(1,"LCD color mismatch: got %h expected %h",{b,g[5:1],r},expected);
            end else if ({r,g,b}!==16'd0) $fatal(1,"Border must be black");
        end
    end
    initial begin #20000000; $fatal(1,"Video timeout"); end
endmodule
