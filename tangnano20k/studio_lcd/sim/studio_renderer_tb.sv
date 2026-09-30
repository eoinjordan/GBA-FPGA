`timescale 1ns/1ps
module studio_renderer_tb;
    reg clk=0,resetn=0,start=0;
    always #5 clk=~clk;
    reg [15:0] control=16'h1140,bg0=16'h1c01,bg1=16'h1e04,sx0=0,sy0=0;
    wire busy,mem_valid,fb_write;
    wire [20:0] mem_addr;
    reg mem_ready=0;
    reg [31:0] mem_data=0;
    wire [8:0] mirror_addr;
    reg [31:0] mirror_data;
    wire [14:0] fb_addr;
    wire [31:0] fb_data;
    studio_renderer dut(.clk(clk),.resetn(resetn),.start(start),.busy(busy),
        .control(control),.bg0(bg0),.bg1(bg1),.sx0(sx0),.sy0(sy0),.sx1(16'd0),.sy1(16'd0),
        .mem_valid(mem_valid),.mem_addr(mem_addr),.mem_ready(mem_ready),.mem_data(mem_data),
        .mirror_addr(mirror_addr),.mirror_data(mirror_data),
        .fb_write(fb_write),.fb_addr(fb_addr),.fb_data(fb_data));
    reg [31:0] vram[0:24575],mirror[0:511];
    reg [15:0] frame[0:38399];
    reg [1:0] phase=0;
    reg [20:0] request_addr;
    integer words;
    always @(posedge clk) begin
        mirror_data<=mirror[mirror_addr];
        mem_ready<=0;
        case(phase)
            0: if (mem_valid) begin request_addr<=mem_addr;phase<=1;end
            1: begin mem_data<=vram[(request_addr-21'h100000)>>2];phase<=2;end
            2: begin mem_ready<=1;phase<=3;end
            3: phase<=0;
        endcase
        if (fb_write) begin
            frame[fb_addr*2]<=fb_data[15:0];frame[fb_addr*2+1]<=fb_data[31:16];
            words=words+1;
        end
    end
    task draw;
        begin
            words=0; @(negedge clk);start=1;@(negedge clk);start=0;
            wait(busy); wait(!busy); repeat(3) @(negedge clk);
            if (words!=19200) $fatal(1,"Incomplete frame: %0d words",words);
        end
    endtask
    integer i;
    initial begin
        for(i=0;i<24576;i=i+1) vram[i]=0;
        for(i=0;i<512;i=i+1) mirror[i]=0;
        for(i=0;i<128;i=i+1) mirror[256+i*2]=32'h00000200;
        mirror[0]={16'd31,16'd7}; mirror[1]=32'd992;
        mirror[128]={16'd31744,16'd0};
        vram[28*512]=1;vram[8]=32'h22222221;vram[15]=32'h11111112;
        repeat(5) @(negedge clk);resetn=1;
        control=16'h0100;draw();
        if(frame[0]!=31 || frame[1]!=992 || frame[8]!=7 || frame[38399]!=7)
            $fatal(1,"Background or framebuffer bounds mismatch %h %h %h",frame[0],frame[1],frame[8]);
        vram[28*512]=16'h0401;draw();
        if(frame[0]!=992 || frame[7]!=31) $fatal(1,"Horizontal flip");
        vram[28*512]=16'h0801;draw();
        if(frame[0]!=992 || frame[1]!=31) $fatal(1,"Vertical flip");
        vram[28*512]=1;sx0=1;draw();
        if(frame[0]!=992 || frame[7]!=7) $fatal(1,"Scroll");
        sx0=0;control=16'h0300;vram[30*512]=1;vram[16'h4000/4+8]=2;draw();
        if(frame[0]!=992 || frame[1]!=992) $fatal(1,"Dialogue transparency");
        control=16'h1140;mirror[256]=0;mirror[257]=1;vram[32'h10000/4+8]=1;draw();
        if(frame[0]!=31744 || frame[1]!=992) $fatal(1,"OBJ transparency/priority");
        mirror[257]=16'h0801;draw();
        if(frame[0]!=31) $fatal(1,"OBJ behind BG");
        mirror[256]=16'h8000;mirror[257]=1;vram[32'h10000/4+16]=32'h11111111;draw();
        if(frame[8*240]!=31744) $fatal(1,"8x16 OBJ");
        $display("PASS: hardware BG flips/scroll, BG1 transparency, OBJ priority/8x16, full frames");
        $finish;
    end
    initial begin #100000000; $fatal(1,"Renderer timeout state %0d",dut.state);end
endmodule
