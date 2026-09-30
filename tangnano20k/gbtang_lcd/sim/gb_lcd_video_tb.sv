`timescale 1ns/1ps
module gb_lcd_video_tb;
    reg pix_clk=0; always #5 pix_clk=~pix_clk;
    reg resetn=0;
    wire dclk,de,hs,vs;
    wire [4:0] r,b; wire [5:0] g;
    gb_lcd_video dut(.gb_clk(1'b0),.gb_resetn(1'b0),.hs(1'b0),.vs(1'b0),
        .valid(1'b0),.pixel(2'd0),.pix_clk(pix_clk),.pix_resetn(resetn),
        .lcd_dclk(dclk),.lcd_de(de),.lcd_hsync(hs),.lcd_vsync(vs),
        .lcd_r(r),.lcd_g(g),.lcd_b(b));
    reg [11:0] x,y;
    reg ede;
    reg [1:0] sample;
    reg [4:0] shade;
    integer active=0,image_pixels=0;
    always @(posedge pix_clk) begin x=dut.x; y=dut.y; ede=dut.de; end
    initial begin
        for (integer i=0;i<65536;i=i+1) dut.mem[i]=i[1:0];
        repeat(3) @(negedge pix_clk); resetn=1;
        // Wait for the raster's first active pixel; check one complete frame.
        while (!(dut.de && dut.x==0 && dut.y==0)) @(negedge pix_clk);
        for (integer n=0;n<531*292;n=n+1) begin
            @(negedge pix_clk); #1;
            if (de!==ede) $fatal(1,"DE pipeline mismatch");
            if (ede) begin
                active=active+1;
                if (x>=160 && x<320 && y>=64 && y<208) begin
                    image_pixels=image_pixels+1;
                    sample=(x-160)&3;
                    case(sample) 0:shade=31;1:shade=21;2:shade=10;3:shade=0;endcase
                end else shade=0;
                if (r!==shade || b!==shade || g!=={shade,shade[4]})
                    $fatal(1,"RGB mismatch x=%0d y=%0d",x,y);
            end
        end
        if(active!=480*272 || image_pixels!=160*144) $fatal(1,"Geometry count");
        $display("PASS: video full raster, native GB centring, RGB565 pipeline");
        $finish;
    end
endmodule
