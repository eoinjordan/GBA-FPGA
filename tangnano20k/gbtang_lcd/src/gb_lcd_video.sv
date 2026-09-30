// Game Boy 160x144 pixels centred at native resolution on the 480x272 LCD.
// The dual-clock framebuffer follows GBTang's pixel-write convention.
// One framebuffer is used; frame-rate mismatch can cause tearing.
module gb_lcd_video (
    input wire gb_clk, gb_resetn, hs, vs, valid,
    input wire [1:0] pixel,
    input wire pix_clk, pix_resetn,
    output wire lcd_dclk,
    output reg lcd_de, lcd_hsync, lcd_vsync,
    output reg [4:0] lcd_r, lcd_b, output reg [5:0] lcd_g
);
    reg [1:0] mem [0:65535];
    reg [7:0] wx, wy;
    reg [15:0] wa;
    reg [1:0] wd;
    reg we;
    reg initializing=1;
    always @(posedge gb_clk) begin
        if (we) mem[wa]<=wd;
        if (!gb_resetn) begin
            wx<=0; wy<=0; we<=0; initializing<=1;
        end else if (initializing) begin
            wa<={wy,wx}; wd<=0; we<=1;
            wx<=wx+1'b1;
            if (wx==255) wy<=wy+1'b1;
            if (wx==255 && wy==255) initializing<=0;
        end else if (vs) begin wx<=0; wy<=0; we<=0; end
        else if (hs) begin wx<=0; we<=0; end
        else if (valid) begin
            wa<={wy,wx}; wd<=pixel; we<=1;
            if (wx==159) begin wx<=0; wy<=wy==143 ? 0 : wy+1'b1; end
            else wx<=wx+1'b1;
        end else we<=0;
    end
    wire de, hsync, vsync, frame_start;
    wire [11:0] x,y;
    rgb_lcd_timing #(.H_ACTIVE(480),.H_FRONT(8),.H_SYNC(4),.H_BACK(39),
                     .V_ACTIVE(272),.V_FRONT(8),.V_SYNC(4),.V_BACK(8),
                     .HSYNC_ACTIVE(0),.VSYNC_ACTIVE(0)) timing (
        .pixel_clk(pix_clk),.rst_n(pix_resetn),.lcd_de(de),
        .lcd_hsync(hsync),.lcd_vsync(vsync),.pixel_x(x),.pixel_y(y),
        .frame_start(frame_start));
    wire active=de && x>=160 && x<320 && y>=64 && y<208;
    wire [7:0] rx=x-160, ry=y-64;
    reg [1:0] rd;
    reg qde,qhs,qvs,qactive;
    // BRAM read and control delay must match.
    always @(posedge pix_clk) begin
        rd<=mem[{ry,rx}];
        qde<=de; qhs<=hsync; qvs<=vsync; qactive<=active;
    end
    reg [4:0] shade;
    always @* case (rd)
        0: shade=31; 1: shade=21; 2: shade=10; 3: shade=0;
    endcase
    assign lcd_dclk=pix_clk;
    always @(negedge pix_clk or negedge pix_resetn) begin
        if (!pix_resetn) begin
            lcd_de<=0; lcd_hsync<=1; lcd_vsync<=1;
            lcd_r<=0; lcd_g<=0; lcd_b<=0;
        end else begin
            lcd_de<=qde; lcd_hsync<=qhs; lcd_vsync<=qvs;
            lcd_r<=qactive ? shade : 0;
            lcd_g<=qactive ? {shade,shade[4]} : 0;
            lcd_b<=qactive ? shade : 0;
        end
    end
endmodule
