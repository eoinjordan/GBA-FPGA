`timescale 1ns/1ps
module gb_uart_loader_tb;
    reg clk=0; always #5 clk=~clk;
    reg resetn=0,rx_valid=0;
    reg [7:0] rx_data=0;
    wire [21:0] write_addr;
    wire [7:0] write_data,keys,tx_data;
    wire write_valid,loaded,tx_valid;
    reg [31:0] crc;
    integer writes=0;
    gb_uart_loader dut(.clk(clk),.resetn(resetn),.rx_valid(rx_valid),.rx_data(rx_data),
        .write_addr(write_addr),.write_data(write_data),.write_valid(write_valid),
        .loaded(loaded),.keys(keys),.cart_addr(16'h1234),.fault(1'b0),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(1'b1));
    task send(input [7:0] b);
        @(negedge clk); rx_data=b; rx_valid=1;
        @(negedge clk); rx_valid=0;
    endtask
    always @(negedge clk) if (write_valid) begin
        if (write_addr !== writes || write_data !== writes[7:0])
            $fatal(1,"ROM byte/address mismatch at %0d",writes);
        writes=writes+1;
    end
    task upload(input bad);
        send("G"); send("B"); send("L"); send("D");
        send(0); send(8'h80); send(0); send(0); // 32 KiB
        for (integer i=0;i<32768;i=i+1) begin
            send(i[7:0]);
        end
        // Golden CRC from Python zlib.crc32(bytes(range(256))*128).
        crc=32'h217726b2;
        if (bad) crc=crc^1;
        send(crc[7:0]); send(crc[15:8]); send(crc[23:16]); send(crc[31:24]);
        repeat(60) @(negedge clk);
    endtask
    initial begin
        repeat(3) @(negedge clk); resetn=1;
        upload(0);
        if (!loaded || writes!=32768) $fatal(1,"Valid ROM did not start");
        send("K"); send(8'h81);
        if (keys!==8'h81) $fatal(1,"Key mapping");
        writes=0; upload(1);
        if (loaded) $fatal(1,"Bad CRC started the core");
        send("G"); send("B"); send("L"); send("D");
        send(0); send(0); send(0); send(0);
        if (loaded || dut.state!=0) $fatal(1,"Empty ROM accepted");
        $display("PASS: loader sequential bytes, CRC gate, keys, invalid length");
        $finish;
    end
endmodule
