// 2 KiB direct-mapped instruction cache and 2 KiB scratch.
// Firmware upload bypasses this block. clear invalidates cached code on reload.
module rv_fast_bus (
    input wire clk,clear,
    input wire valid,instr, input wire [20:0] addr,
    input wire [31:0] wdata, input wire [3:0] wstrb,
    output wire ready, output wire [31:0] rdata,
    output wire slow_valid,
    input wire slow_ready, input wire [31:0] slow_data
);
    wire fast=addr>=21'h0e0000 && addr<21'h0e0800;
    reg [31:0] cache[0:511];
    reg [9:0] tags[0:511];
    reg [511:0] cached=0;
    reg [31:0] cache_q;
    reg cache_ready=0;
    wire hit=instr && cached[addr[10:2]] && tags[addr[10:2]]==addr[20:11];
    always @(posedge clk) begin
        cache_q<=cache[addr[10:2]];
        cache_ready<=valid && !fast && hit && !ready;
        if (clear) begin cached<=0; cache_ready<=0; end
        else begin
            if (valid && instr && slow_ready) begin
                cache[addr[10:2]]<=slow_data;
                tags[addr[10:2]]<=addr[20:11];
                cached[addr[10:2]]<=1;
            end
            if (valid && !instr && |wstrb) cached[addr[10:2]]<=0;
        end
    end
    reg [31:0] scratch[0:511];
    reg [31:0] scratch_q;
    reg [1:0] state=0;
    reg fast_ready=0;
    wire scratch_write=state==1 && |wstrb;
    wire [31:0] merged={wstrb[3] ? wdata[31:24] : scratch_q[31:24],
                       wstrb[2] ? wdata[23:16] : scratch_q[23:16],
                       wstrb[1] ? wdata[15:8] : scratch_q[15:8],
                       wstrb[0] ? wdata[7:0] : scratch_q[7:0]};
    always @(posedge clk) begin
        scratch_q<=scratch[addr[10:2]];
        if (scratch_write) scratch[addr[10:2]]<=merged;
        fast_ready<=0;
        if (clear) state<=0;
        else case (state)
            0: if (valid && fast) state<=1;
            1: begin fast_ready<=1; state<=2; end
            2: state<=0;
        endcase
    end
    assign slow_valid=valid && !fast && !hit;
    assign ready=fast ? fast_ready : cache_ready || slow_ready;
    assign rdata=fast ? scratch_q : cache_ready ? cache_q : slow_data;
endmodule
