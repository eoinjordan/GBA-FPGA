// Nano 20K LCD platform for GBTang's VerilogBoy core and SDRAM controller.
// Based on fjpolo/GBTang v1.0.0 and nand2mario's SDRAM integration.
// SPDX-License-Identifier: GPL-3.0-or-later
import configPackage::*;
module gbtang_lcd_top (
    input wire sys_clk, s1, s2, UART_RXD,
    output wire UART_TXD, output wire [1:0] led,
    output wire O_sdram_clk, O_sdram_cke, O_sdram_cs_n,
    output wire O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n,
    inout wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr, output wire [1:0] O_sdram_ba,
    output wire [3:0] O_sdram_dqm,
    output wire lcd_dclk, lcd_de, lcd_hsync, lcd_vsync,
    output wire [4:0] lcd_r,lcd_b, output wire [5:0] lcd_g
);
    wire clk, fclk, pix_clk, pll_locked;
    gowin_pll_gb pll_gb(.clkin(sys_clk),.clkoutd3(clk),
                      .clkout(fclk),.clkoutp(O_sdram_clk));
    rPLL #(.FCLKIN("27"),.IDIV_SEL(2),.FBDIV_SEL(0),.ODIV_SEL(64),
           .DEVICE("GW2AR-18C")) lcd_pll (
        .CLKOUT(pix_clk),.LOCK(pll_locked),.CLKIN(sys_clk),
        .RESET(1'b0),.RESET_P(1'b0),.CLKFB(1'b0),
        .FBDSEL(6'd0),.IDSEL(6'd0),.ODSEL(6'd0),
        .PSDA(4'd0),.DUTYDA(4'd0),.FDLY(4'd0));
    reg [7:0] reset_count=255;
    reg sys_resetn=0;
    always @(posedge clk) begin
        if (reset_count!=0) reset_count<=reset_count-1'b1;
        else sys_resetn<=1;
    end
    wire pix_resetn;
    reset_sync pix_reset(.clk(pix_clk),.async_rst_n(pll_locked),.rst_n(pix_resetn));
    reg [2:0] gb_count=0;
    reg clk_gb=0;
    always @(posedge clk or negedge sys_resetn) begin
        if (!sys_resetn) begin gb_count<=0; clk_gb<=0; end
        else if (gb_count==4) begin gb_count<=0; clk_gb<=1; end
        else begin gb_count<=gb_count+1'b1; if (gb_count==1) clk_gb<=0; end
    end
    wire [15:0] gb_addr;
    wire [7:0] gb_dout, gb_din;
    wire gb_wr,gb_rd,hs,vs,cpl,valid,fault;
    wire [1:0] pixel;
    wire loaded, rx_valid, tx_valid, tx_ready;
    wire [7:0] rx_data,tx_data,serial_keys;
    wire [21:0] loader_addr;
    wire [7:0] loader_data;
    wire loader_write;
    uart_rx #(.CLKS_PER_BIT(188)) rx(.i_Clock(clk),.i_Rx_Serial(UART_RXD),
                                  .o_Rx_DV(rx_valid),.o_Rx_Byte(rx_data));
    uart_tx #(.CLKS_PER_BIT(188)) tx(.clk(clk),.rst_n(sys_resetn),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.tx(UART_TXD));
    gb_uart_loader loader(.clk(clk),.resetn(sys_resetn),
        .rx_valid(rx_valid),.rx_data(rx_data),.write_addr(loader_addr),
        .write_data(loader_data),.write_valid(loader_write),.loaded(loaded),
        .keys(serial_keys),.cart_addr(gb_addr),.fault(fault),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready));
    wire [1:0] board_keys;
    gba_buttons #(.BUTTON_COUNT(2),.ACTIVE_LOW(0),.TICK_CYCLES(21600)) buttons (
        .clk(clk),.rst_n(sys_resetn),.button_pins({s2,s1}),.pressed(board_keys));
    reg [7:0] key_meta,key_sync;
    always @(posedge clk_gb) begin
        key_meta<=serial_keys | {4'd0,board_keys[0],2'd0,board_keys[1]};
        key_sync<=key_meta;
    end
    boy core(.rst(~sys_resetn | ~loaded),.clk(clk_gb),
        .a(gb_addr),.dout(gb_dout),.din(gb_din),.wr(gb_wr),.rd(gb_rd),
        .key(key_sync),.hs(hs),.vs(vs),.cpl(cpl),.pixel(pixel),.valid(valid),
        .left(),.right(),.phi(),.done(),.fault(fault));
    wire [22:14] rom_bank;
    wire [16:13] ram_bank;
    wire rom_cs_n,ram_cs_n;
    mbc5 mapper(.vb_clk(clk_gb),.vb_rst(~sys_resetn | ~loaded),
        .vb_a(gb_addr[15:12]),.vb_d(gb_dout),.vb_wr(gb_wr),.vb_rd(gb_rd),
        .rom_a(rom_bank),.ram_a(ram_bank),.rom_cs_n(rom_cs_n),.ram_cs_n(ram_cs_n));
    wire [21:0] cpu_addr=~rom_cs_n ? {rom_bank[21:14],gb_addr[13:0]} :
        ~ram_cs_n ? {2'b01,3'd0,ram_bank[16:13],gb_addr[12:0]} : 22'd0;
    reg clkref=0;
    always @(posedge clk) clkref<=~clkref;
    reg write_r=0;
    reg write_mem=0;
    reg [21:0] write_addr;
    reg [7:0] write_data;
    always @(posedge clk) begin
        write_r<=loader_write;
        write_mem<=loader_write | write_r;
        if (loader_write) begin write_addr<=loader_addr; write_data<=loader_data; end
    end
    wire sdram_busy;
    sdram_gb sdram(.clk(fclk),.clkref(clkref),.resetn(sys_resetn),.busy(sdram_busy),
        .SDRAM_DQ(IO_sdram_dq),.SDRAM_A(O_sdram_addr),.SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n),.SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n),.SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CKE(O_sdram_cke),.SDRAM_DQM(O_sdram_dqm),
        .addrA(22'd0),.weA(1'b0),.dinA(8'd0),.oeA(1'b0),.doutA(),
        .addrB(loaded ? cpu_addr : write_addr),
        .weB(loaded ? gb_wr & ~ram_cs_n : write_mem),
        .dinB(loaded ? gb_dout : write_data),
        .oeB(loaded & gb_rd & (~rom_cs_n | ~ram_cs_n)),.doutB(gb_din),
        .rv_addr(20'd0),.rv_din(16'd0),.rv_ds(2'd0),.rv_dout(),
        .rv_req(1'b0),.rv_req_ack(),.rv_we(1'b0));
    gb_lcd_video display(.gb_clk(clk_gb),.gb_resetn(sys_resetn),
        .hs(hs),.vs(vs),.valid(valid),.pixel(pixel),
        .pix_clk(pix_clk),.pix_resetn(pix_resetn),.lcd_dclk(lcd_dclk),
        .lcd_de(lcd_de),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    reg vs_previous=0;
    reg [5:0] frames=0;
    always @(posedge clk_gb) begin
        vs_previous<=vs;
        if (vs && !vs_previous) frames<=frames+1'b1;
    end
    assign led={~frames[5],~loaded};
endmodule
