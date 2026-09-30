// Two halfword transactions per PicoRV32 bus access. The SDRAM port uses
// toggle request/ack; its data settles one SDRAM clock after ack.
module rv_sdram_bus (
    input wire clk, resetn,
    input wire valid, input wire [20:0] addr,
    input wire [31:0] wdata, input wire [3:0] wstrb,
    output reg ready, output reg [31:0] rdata,
    output reg [19:0] rv_addr, output reg [15:0] rv_din,
    output reg [1:0] rv_ds, output reg rv_we, rv_req,
    input wire rv_ack, input wire [15:0] rv_dout
);
    (* async_reg = "true" *) reg ack_meta,ack_sync;
    reg [2:0] state;
    reg [20:0] address;
    reg [31:0] data;
    reg [3:0] strobes;
    always @(posedge clk) begin ack_meta<=rv_ack; ack_sync<=ack_meta; end
    always @(posedge clk) begin
        if (!resetn) begin
            ready<=0; state<=0; rv_req<=0; rv_addr<=0; rv_din<=0;
            rv_ds<=0; rv_we<=0; rdata<=0;
        end else begin
            ready<=0;
            case (state)
                0: if (valid) begin
                    address<=addr; data<=wdata; strobes<=wstrb;
                    rv_addr<={addr[20:2],1'b0}; rv_din<=wdata[15:0];
                    rv_ds<=wstrb==0 ? 2'b11 : wstrb[1:0]; rv_we<=|wstrb;
                    rv_req<=~rv_req; state<=1;
                end
                1: if (ack_sync==rv_req) state<=2;
                2: begin
                    rdata[15:0]<=rv_dout;
                    rv_addr<={address[20:2],1'b1}; rv_din<=data[31:16];
                    rv_ds<=strobes==0 ? 2'b11 : strobes[3:2]; rv_we<=|strobes;
                    rv_req<=~rv_req; state<=3;
                end
                3: if (ack_sync==rv_req) state<=4;
                4: begin rdata[31:16]<=rv_dout; ready<=1; state<=5; end
                5: state<=0;
                default: state<=0;
            endcase
        end
    end
endmodule
