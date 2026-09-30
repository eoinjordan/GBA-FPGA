// CPU RGB555 framebuffer, native 240x160 centred on the existing RGB565 LCD.
module studio_lcd_video (
    input wire clk, input wire write, input wire [14:0] address,
    input wire [31:0] data, input wire [3:0] strobes,
    output reg [31:0] read_data,
    input wire pix_clk, resetn, show,
    output reg [31:0] frames,
    output wire lcd_dclk, output reg lcd_de,lcd_hsync,lcd_vsync,
    output reg [4:0] lcd_r,lcd_b, output reg [5:0] lcd_g
);
    assign read_data=0; // The CPU framebuffer interface is write-only.
    wire de,hs,vs,frame;
    wire [11:0] x,y;
    rgb_lcd_timing #(.H_ACTIVE(480),.H_FRONT(8),.H_SYNC(4),.H_BACK(39),
        .V_ACTIVE(272),.V_FRONT(8),.V_SYNC(4),.V_BACK(8)) timing (
        .pixel_clk(pix_clk),.rst_n(resetn),.lcd_de(de),.lcd_hsync(hs),
        .lcd_vsync(vs),.pixel_x(x),.pixel_y(y),.frame_start(frame));
    wire active=de && x>=120 && x<360 && y>=56 && y<216;
    wire [11:0] dx=x-120,dy=y-56;
    wire [14:0] ra=active ? dy*120+(dx>>1) : 0;
    // Explicit 2048-byte banks avoid rounding the whole framebuffer up to
    // 128 KiB. Forty BSRAM blocks hold the four byte lanes of 19200 words.
    wire [31:0] bank_data[0:9];
    genvar bank,lane;
    generate for (bank=0;bank<10;bank=bank+1) begin: banks
        for (lane=0;lane<4;lane=lane+1) begin: lanes
            reg [7:0] mem[0:2047];
            reg [7:0] q;
            always @(posedge clk)
                if (write && address[14:11]==bank && strobes[lane])
                    mem[address[10:0]]<=data[lane*8+:8];
            always @(posedge pix_clk) q<=mem[ra[10:0]];
            assign bank_data[bank][lane*8+:8]=q;
        end
    end endgenerate
    reg [3:0] read_bank;
    reg qde,qhs,qvs,qa,odd;
    (* async_reg = "true" *) reg show_meta,show_sync;
    always @(posedge pix_clk) begin
        show_meta<=show; show_sync<=show_meta;
        read_bank<=ra[14:11];
        qde<=de; qhs<=hs; qvs<=vs; qa<=active && show_sync; odd<=dx[0];
        if (!resetn) frames<=0;
        else if (frame) frames<=frames+1'b1;
    end
    wire [31:0] word_data=bank_data[read_bank];
    wire [15:0] color=odd ? word_data[31:16] : word_data[15:0];
    assign lcd_dclk=pix_clk;
    always @(negedge pix_clk) begin
        lcd_de<=resetn && qde; lcd_hsync<=!resetn || qhs; lcd_vsync<=!resetn || qvs;
        lcd_r<=qa ? color[4:0] : 0;
        lcd_g<=qa ? {color[9:5],color[9]} : 0;
        lcd_b<=qa ? color[14:10] : 0;
    end
endmodule
