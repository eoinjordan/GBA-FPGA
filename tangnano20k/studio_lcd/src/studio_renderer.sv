// Mode 0 renderer for GBA-engine: 4bpp BG0/BG1 and regular 1D-mapped OBJ.
// CPU is stalled for SDRAM accesses while this engine draws one full frame.
module studio_renderer (
    input wire clk,resetn,start,
    input wire [15:0] control,bg0,bg1,sx0,sy0,sx1,sy1,
    output reg busy,
    output wire mem_valid, output reg [20:0] mem_addr,
    input wire mem_ready, input wire [31:0] mem_data,
    output reg [8:0] mirror_addr, input wire [31:0] mirror_data,
    output reg fb_write, output reg [14:0] fb_addr, output reg [31:0] fb_data
);
    localparam IDLE=0,BACK_WAIT=1,BACK=2,CLEAR=3,LAYER=4,MAP=5,TILE=6,
        PIXEL=7,PAL_WAIT=8,PAL=9,OBJ0_WAIT=10,OBJ0=11,OBJ1_WAIT=12,
        OBJ1=13,OBJ_PIXEL=14,OBJ_TILE=15,FLUSH=16,TILE_ADDRESS=17;
    reg [4:0] state;
    reg [18:0] row[0:239];
    reg [7:0] x,y;
    reg layer;
    reg [15:0] cnt,scroll_x,scroll_y,map_entry,backdrop;
    reg [31:0] tile_pixels;
    reg [3:0] nibble;
    reg [2:0] pixel_priority;
    reg [7:0] draw_x;
    reg palette_odd;
    reg sprite_pixel;
    reg [7:0] object_index;
    reg [15:0] a,b,c;
    reg [6:0] object_w,object_h,object_px,object_y;
    reg signed [9:0] object_origin;
    reg [20:0] tile_cached_addr;
    reg tile_cached;
    wire [8:0] bx=(x+scroll_x)&255, by=(y+scroll_y)&255;
    wire [7:0] next_bx=bx[7:0]+1'b1;
    wire [2:0] tile_x=map_entry[10] ? 7-bx[2:0] : bx[2:0];
    wire [2:0] tile_y=map_entry[11] ? 7-by[2:0] : by[2:0];
    wire [3:0] bg_nibble=(tile_pixels>>(tile_x*4))&15;
    wire [6:0] opx=b[12] ? object_w-1-object_px : object_px;
    wire signed [9:0] screen_x=object_origin+$signed({3'd0,object_px});
    wire [9:0] object_tile=c[9:0]+(object_y>>3)*(object_w>>3)+(opx>>3);
    wire [20:0] object_address=21'h110000+{object_tile,5'd0}+{16'd0,object_y[2:0],2'd0};
    wire [3:0] obj_nibble=(tile_pixels>>(opx[2:0]*4))&15;
    assign mem_valid=busy && (state==MAP || state==TILE || state==OBJ_TILE);
    function [6:0] width(input [1:0] shape,size);
        case (shape)
            0: width=7'd8<<size;
            1: case(size) 0:width=16;1,2:width=32;3:width=64;endcase
            2: case(size) 0,1:width=8;2:width=16;3:width=32;endcase
            default:width=0;
        endcase
    endfunction
    function [6:0] height(input [1:0] shape,size);
        case (shape)
            0: height=7'd8<<size;
            1: case(size) 0,1:height=8;2:height=16;3:height=32;endcase
            2: case(size) 0:height=16;1,2:height=32;3:height=64;endcase
            default:height=0;
        endcase
    endfunction
    task next_object;
        begin
            tile_cached<=0;
            if (object_index==0) begin x<=0;state<=FLUSH; end
            else begin
                object_index<=object_index-1;
                mirror_addr<=9'd256+(object_index-1)*2;
                state<=OBJ0_WAIT;
            end
        end
    endtask
    task next_background_pixel;
        begin
            if (x==239) begin
                x<=0;
                if (!layer) begin layer<=1;state<=LAYER;end
                else begin object_index<=127;mirror_addr<=510;state<=OBJ0_WAIT;end
            end else begin
                x<=x+1;
                if (bx[2:0]==7) begin
                    mem_addr<=21'h100000+{cnt[12:8],11'd0}+
                        {10'd0,by[7:3],6'd0}+{15'd0,next_bx[7:3],1'b0};
                    state<=MAP;
                end else state<=PIXEL;
            end
        end
    endtask
    task next_object_pixel;
        begin
            if (object_px+1>=object_w) next_object();
            else begin object_px<=object_px+1;state<=OBJ_PIXEL;end
        end
    endtask
    always @(posedge clk) begin
        fb_write<=0;
        if (!resetn) begin
            busy<=0;state<=IDLE;fb_write<=0;mirror_addr<=0;
            mem_addr<=0;fb_addr<=0;fb_data<=0;tile_cached<=0;
        end else case (state)
            IDLE: if (start) begin
                busy<=1;y<=0;x<=0;mirror_addr<=0;state<=BACK_WAIT;
            end
            BACK_WAIT: state<=BACK;
            BACK: begin backdrop<=mirror_data[15:0];state<=CLEAR;end
            CLEAR: begin
                row[x]<={3'd7,backdrop};
                if (x==239) begin x<=0;layer<=0;state<=LAYER;end
                else x<=x+1;
            end
            LAYER: begin
                cnt<=layer ? bg1 : bg0;
                scroll_x<=layer ? sx1 : sx0;
                scroll_y<=layer ? sy1 : sy0;
                if (layer ? control[9] : control[8]) begin
                    mem_addr<=21'h100000+
                        ((layer ? bg1[12:8] : bg0[12:8])<<11)+
                        ((((y+(layer ? sy1 : sy0))&255)>>3)<<6)+
                        ((((layer ? sx1 : sx0)&255)>>3)<<1);
                    state<=MAP;
                end else if (!layer) begin layer<=1;state<=LAYER;end
                else begin object_index<=127;mirror_addr<=510;state<=OBJ0_WAIT;end
            end
            MAP: if (mem_ready) begin
                map_entry<=mem_addr[1] ? mem_data[31:16] : mem_data[15:0];
                state<=TILE_ADDRESS;
            end
            TILE_ADDRESS: begin
                mem_addr<=21'h100000+{cnt[3:2],14'd0}+{map_entry[9:0],5'd0}+{16'd0,tile_y,2'd0};
                state<=TILE;
            end
            TILE: if (mem_ready) begin tile_pixels<=mem_data;state<=PIXEL;end
            PIXEL: begin
                if (bg_nibble==0) next_background_pixel();
                else begin
                    nibble<=bg_nibble; draw_x<=x; sprite_pixel<=0;
                    pixel_priority<={cnt[1:0],layer};
                    mirror_addr<={2'd0,map_entry[15:12],bg_nibble[3:1]};
                    palette_odd<=bg_nibble[0];state<=PAL_WAIT;
                end
            end
            PAL_WAIT: state<=PAL;
            PAL: begin
                if (pixel_priority<=row[draw_x][18:16])
                    row[draw_x]<={pixel_priority,palette_odd ? mirror_data[31:16] : mirror_data[15:0]};
                if (sprite_pixel) next_object_pixel();
                else next_background_pixel();
            end
            OBJ0_WAIT: state<=OBJ0;
            OBJ0: begin
                a<=mirror_data[15:0];b<=mirror_data[31:16];
                if (!control[12] || mirror_data[9:8]!=0 || mirror_data[13] ||
                    mirror_data[11:10]!=0 || mirror_data[15:14]==3 ||
                    ((y-mirror_data[7:0])&255)>=height(mirror_data[15:14],mirror_data[31:30]))
                    next_object();
                else begin mirror_addr<=9'd257+object_index*2;state<=OBJ1_WAIT;end
            end
            OBJ1_WAIT: state<=OBJ1;
            OBJ1: begin
                c<=mirror_data[15:0];object_w<=width(a[15:14],b[15:14]);
                object_h<=height(a[15:14],b[15:14]);
                object_y<=b[13] ? height(a[15:14],b[15:14])-1-((y-a[7:0])&255) : (y-a[7:0])&255;
                object_origin<=b[8] ? $signed({1'b1,b[8:0]}) : $signed({1'b0,b[8:0]});
                object_px<=0;tile_cached<=0;state<=OBJ_PIXEL;
            end
            OBJ_PIXEL: begin
                if (screen_x<0 || screen_x>=240) next_object_pixel();
                else if (!tile_cached || tile_cached_addr!=object_address) begin
                    mem_addr<=object_address;state<=OBJ_TILE;
                end else if (obj_nibble==0) next_object_pixel();
                else begin
                    draw_x<=screen_x;pixel_priority<={c[11:10],1'b0};sprite_pixel<=1;
                    mirror_addr<=9'd128+{c[15:12],3'd0}+obj_nibble[3:1];
                    palette_odd<=obj_nibble[0];state<=PAL_WAIT;
                end
            end
            OBJ_TILE: if (mem_ready) begin
                tile_pixels<=mem_data;tile_cached<=1;tile_cached_addr<=object_address;state<=OBJ_PIXEL;
            end
            FLUSH: begin
                fb_write<=1;fb_addr<=y*120+(x>>1);fb_data<={row[x+1][15:0],row[x][15:0]};
                if (x==238) begin
                    x<=0;
                    if (y==159) begin busy<=0;state<=IDLE;end
                    else begin y<=y+1;state<=CLEAR;end
                end else x<=x+2;
            end
        endcase
    end
endmodule
