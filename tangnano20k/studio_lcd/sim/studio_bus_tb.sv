`timescale 1ns/1ps
module studio_bus_tb;
    reg clk=0, memory_clk=0,resetn=0,clear=1;
    always #5 clk=~clk;
    always #2 memory_clk=~memory_clk;
    reg valid=0,instr=0;
    reg [20:0] addr=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=0;
    wire ready,slow_valid,slow_ready;
    wire [31:0] rdata,slow_data;
    wire [19:0] rv_addr;
    wire [15:0] rv_din;
    wire [1:0] rv_ds;
    wire rv_we,rv_req;
    reg rv_ack=0;
    reg [15:0] rv_dout=0;
    rv_fast_bus fast(.clk(clk),.clear(clear),.valid(valid),.instr(instr),
        .addr(addr),.wdata(wdata),.wstrb(wstrb),.ready(ready),.rdata(rdata),
        .slow_valid(slow_valid),.slow_ready(slow_ready),.slow_data(slow_data));
    rv_sdram_bus bridge(.clk(clk),.resetn(resetn),.valid(slow_valid),
        .addr(addr),.wdata(wdata),.wstrb(wstrb),.ready(slow_ready),.rdata(slow_data),
        .rv_addr(rv_addr),.rv_din(rv_din),.rv_ds(rv_ds),.rv_we(rv_we),
        .rv_req(rv_req),.rv_ack(rv_ack),.rv_dout(rv_dout));
    reg [15:0] memory[0:2047];
    reg [3:0] phase=0;
    reg [15:0] pending;
    integer requests=0;
    always @(posedge memory_clk) begin
        case (phase)
            0: if (rv_req!=rv_ack) begin
                requests=requests+1;
                if (rv_we) begin
                    if (rv_ds[0]) memory[rv_addr[10:0]][7:0]<=rv_din[7:0];
                    if (rv_ds[1]) memory[rv_addr[10:0]][15:8]<=rv_din[15:8];
                end
                pending<=memory[rv_addr[10:0]]; phase<=1;
            end
            1,2,3: phase<=phase+1;
            4: begin rv_ack<=rv_req; phase<=5; end
            5: begin rv_dout<=pending; phase<=0; end
        endcase
    end
    task access(input [20:0] a,input [31:0] d,input [3:0] s,input ins,
                input [31:0] expected);
        integer timeout;
        begin
            @(negedge clk); addr=a; wdata=d; wstrb=s; instr=ins; valid=1;
            timeout=0;
            while (!ready) begin
                @(negedge clk); timeout=timeout+1;
                if (timeout>100) $fatal(1,"Bus timeout at %h",a);
            end
            if (!s && rdata!==expected) $fatal(1,"Read %h at %h, expected %h",rdata,a,expected);
            @(negedge clk); valid=0;
            repeat (2) @(negedge clk);
        end
    endtask
    integer before_count;
    initial begin
        repeat (5) @(negedge clk); resetn=1; clear=0;
        access(0,32'h12345678,15,0,0);
        access(0,0,0,1,32'h12345678);
        before_count=requests;
        access(0,0,0,1,32'h12345678);
        if (requests!=before_count) $fatal(1,"Instruction cache miss on repeat");
        access(0,32'haabbccdd,4'b0101,0,0);
        access(0,0,0,1,32'h12bb56dd);
        access(21'h00800,32'h98765432,15,0,0);
        access(21'h00800,0,0,1,32'h98765432);
        access(0,0,0,1,32'h12bb56dd);
        access(21'h0e0000,32'h12345678,15,0,0);
        access(21'h0e0000,32'hff00aa00,4'b1010,0,0);
        access(21'h0e0000,0,0,0,32'hff34aa78);
        before_count=requests;
        access(21'h0e07fc,32'hdeadbeef,15,0,0);
        access(21'h0e07fc,0,0,0,32'hdeadbeef);
        if (requests!=before_count) $fatal(1,"Scratch RAM reached SDRAM");
        clear=1; repeat (3) @(negedge clk); clear=0;
        before_count=requests;
        access(0,0,0,1,32'h12bb56dd);
        if (requests==before_count) $fatal(1,"Reload did not invalidate code cache");
        $display("PASS: SDRAM halfwords, byte strobes, cache collision/invalidation, fast RAM");
        $finish;
    end
    initial begin #100000; $fatal(1,"Timeout"); end
endmodule
