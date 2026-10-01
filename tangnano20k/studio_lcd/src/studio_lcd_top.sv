// SPDX-License-Identifier: GPL-3.0-or-later
// Native RV32IM build of GBA-engine; this platform does not execute ARM ROMs.
import configPackage::*;
module studio_lcd_top (
    input wire sys_clk,s1,s2,UART_RXD,
    output wire UART_TXD, output wire [1:0] led,
    output wire O_sdram_clk,O_sdram_cke,O_sdram_cs_n,
    output wire O_sdram_cas_n,O_sdram_ras_n,O_sdram_wen_n,
    inout wire [31:0] IO_sdram_dq,
    output wire [10:0] O_sdram_addr, output wire [1:0] O_sdram_ba,
    output wire [3:0] O_sdram_dqm,
    output wire lcd_dclk,lcd_de,lcd_hsync,lcd_vsync,
    output wire [4:0] lcd_r,lcd_b, output wire [5:0] lcd_g
);
    wire clk,fclk,pix_clk,pll_locked;
    gowin_pll_gb pll_gb(.clkin(sys_clk),.clkoutd3(clk),
        .clkout(fclk),.clkoutp(O_sdram_clk));
    rPLL #(.FCLKIN("27"),.IDIV_SEL(2),.FBDIV_SEL(0),.ODIV_SEL(64),
        .DEVICE("GW2AR-18C")) lcd_pll (
        .CLKOUT(pix_clk),.LOCK(pll_locked),.CLKIN(sys_clk),
        .RESET(1'b0),.RESET_P(1'b0),.CLKFB(1'b0),
        .FBDSEL(6'd0),.IDSEL(6'd0),.ODSEL(6'd0),
        .PSDA(4'd0),.DUTYDA(4'd0),.FDLY(4'd0));
    reg [7:0] reset_count=255;
    reg resetn=0;
    always @(posedge clk) begin
        if (reset_count!=0) reset_count<=reset_count-1'b1;
        else resetn<=1;
    end
    wire pix_resetn;
    reset_sync pix_reset(.clk(pix_clk),.async_rst_n(pll_locked),.rst_n(pix_resetn));
    wire rx_valid,tx_valid,tx_ready,loaded,loader_write,trap;
    wire [7:0] rx_data,tx_data,loader_data,keys;
    wire [21:0] loader_addr;
    reg [31:0] game_frames=0;
    reg draw_start=0;
    wire draw_busy,draw_mem_valid,draw_fb_write;
    wire [20:0] draw_mem_addr;
    wire [14:0] draw_fb_addr;
    wire [31:0] draw_fb_data;
    reg [31:0] last_pc=0,last_addr=0;
    uart_rx #(.CLKS_PER_BIT(188)) rx(.i_Clock(clk),.i_Rx_Serial(UART_RXD),
        .o_Rx_DV(rx_valid),.o_Rx_Byte(rx_data));
    uart_tx #(.CLKS_PER_BIT(188)) tx(.clk(clk),.rst_n(resetn),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready),.tx(UART_TXD));
    gb_uart_loader #(.MAGIC0("T"),.MAGIC1("G"),.MIN_BYTES(4)) loader (
        .clk(clk),.resetn(resetn),.rx_valid(rx_valid),.rx_data(rx_data),
        .write_addr(loader_addr),.write_data(loader_data),.write_valid(loader_write),
        .loaded(loaded),.keys(keys),.cart_addr(game_frames[15:0]),.fault(trap),
        .debug_pc(last_pc),.debug_addr(last_addr),
        .tx_valid(tx_valid),.tx_data(tx_data),.tx_ready(tx_ready));
    wire [1:0] board_keys;
    gba_buttons #(.BUTTON_COUNT(2),.ACTIVE_LOW(0),.TICK_CYCLES(21600)) buttons (
        .clk(clk),.rst_n(resetn),.button_pins({s2,s1}),.pressed(board_keys));
    wire [9:0] all_keys={2'd0,keys} | {6'd0,board_keys[0],2'd0,board_keys[1]};
    wire mem_valid,mem_instr;
    wire [31:0] mem_addr,mem_wdata;
    wire [3:0] mem_wstrb;
    wire [31:0] mem_rdata;
    wire mem_ready;
    always @(posedge clk) begin
        if (!loaded) begin last_pc<=0; last_addr<=0; end
        else if (mem_valid && mem_ready) begin
            last_addr<=mem_addr;
            if (mem_instr) last_pc<=mem_addr;
        end
    end
    picorv32 #(.ENABLE_COUNTERS(0),.ENABLE_COUNTERS64(0),
        .ENABLE_MUL(1),.ENABLE_DIV(1),.BARREL_SHIFTER(1),
        .PROGADDR_RESET(0),.STACKADDR(32'h00100000)) cpu (
        .clk(clk),.resetn(resetn && loaded),.trap(trap),
        .mem_valid(mem_valid),.mem_instr(mem_instr),.mem_ready(mem_ready),
        .mem_addr(mem_addr),.mem_wdata(mem_wdata),.mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata),.pcpi_wr(1'b0),.pcpi_rd(32'd0),
        .pcpi_wait(1'b0),.pcpi_ready(1'b0),.irq(32'd0));
    wire io=mem_addr[31:12]==20'h04000 || mem_addr[31:12]==20'h80000;
    wire fb=mem_addr>=32'h10000000 && mem_addr<32'h10012c00;
    wire ram=mem_addr<32'h00100000 ||
        (mem_addr>=32'h06000000 && mem_addr<32'h06018000) ||
        (mem_addr>=32'h05000000 && mem_addr<32'h05000400) ||
        (mem_addr>=32'h07000000 && mem_addr<32'h07000400);
    wire [20:0] physical=mem_addr[31:24]==6 ? 21'h100000+mem_addr[16:0] :
        mem_addr[31:24]==5 ? 21'h118000+mem_addr[9:0] :
        mem_addr[31:24]==7 ? 21'h118400+mem_addr[9:0] : mem_addr[20:0];
    reg [31:0] regs[0:79];
    reg [31:0] local_data;
    reg local_ready=0;
    wire [31:0] fb_data;
    wire [31:0] lcd_frames;
    // Gray counter avoids sampling a binary rollover across unrelated clocks.
    wire [31:0] lcd_gray=lcd_frames ^ (lcd_frames>>1);
    (* async_reg = "true" *) reg [31:0] gray_meta,gray_sync;
    reg [31:0] lcd_sync;
    always @* begin
        lcd_sync[31]=gray_sync[31];
        for (integer b=30;b>=0;b=b-1) lcd_sync[b]=lcd_sync[b+1]^gray_sync[b];
    end
    integer n;
    always @(posedge clk) begin
        gray_meta<=lcd_gray; gray_sync<=gray_meta;
        local_ready<=0;
        draw_start<=0;
        if (!loaded) begin
            game_frames<=0;
            for (n=0;n<80;n=n+1) regs[n]<=0;
        end else if (mem_valid && !mem_ready && !ram) begin
            local_ready<=1;
            local_data<=0;
            if (io) begin
                if (mem_addr[31]) begin
                    case (mem_addr[3:2])
                        0:local_data<=lcd_sync;
                        1: begin
                            local_data<=game_frames;
                            if (|mem_wstrb) game_frames<=mem_wdata;
                        end
                        2: begin
                            local_data<={31'd0,draw_busy};
                            if (|mem_wstrb && mem_wdata[0]) draw_start<=1;
                        end
                        3:local_data<=32'h54475231;
                    endcase
                end else if (mem_addr[11:2]==76) local_data<={16'd0,~all_keys & 10'h3ff};
                else if (mem_addr[11:2]<80) begin
                    local_data<=regs[mem_addr[8:2]];
                    if (mem_wstrb[0]) regs[mem_addr[8:2]][7:0]<=mem_wdata[7:0];
                    if (mem_wstrb[1]) regs[mem_addr[8:2]][15:8]<=mem_wdata[15:8];
                    if (mem_wstrb[2]) regs[mem_addr[8:2]][23:16]<=mem_wdata[23:16];
                    if (mem_wstrb[3]) regs[mem_addr[8:2]][31:24]<=mem_wdata[31:24];
                end
            end
        end
    end
    wire slow_valid,ram_ready;
    wire [31:0] ram_data;
    rv_fast_bus fast_bus(.clk(clk),.clear(!loaded),
        .valid(mem_valid && ram && loaded && !draw_busy),.instr(mem_instr),.addr(physical),
        .wdata(mem_wdata),.wstrb(mem_wstrb),.ready(ram_ready),.rdata(ram_data),
        .slow_valid(slow_valid),.slow_ready(bus_ready && loaded && !draw_busy),.slow_data(bus_rdata));
    wire bus_valid=loaded ? (draw_busy ? draw_mem_valid : slow_valid) : loader_write;
    wire [20:0] bus_addr=loaded ? (draw_busy ? draw_mem_addr : physical) : loader_addr[20:0];
    wire [31:0] bus_data=loaded ? mem_wdata : {4{loader_data}};
    wire [3:0] bus_strobes=loaded ? (draw_busy ? 4'd0 : mem_wstrb) : (4'b0001<<loader_addr[1:0]);
    wire bus_ready;
    wire [31:0] bus_rdata;
    wire [19:0] rv_addr;
    wire [15:0] rv_din,rv_dout;
    wire [1:0] rv_ds;
    wire rv_we,rv_req,rv_ack;
    rv_sdram_bus bus(.clk(clk),.resetn(resetn),.valid(bus_valid),
        .addr(bus_addr),.wdata(bus_data),.wstrb(bus_strobes),.ready(bus_ready),
        .rdata(bus_rdata),.rv_addr(rv_addr),.rv_din(rv_din),.rv_ds(rv_ds),
        .rv_we(rv_we),.rv_req(rv_req),.rv_ack(rv_ack),.rv_dout(rv_dout));
    assign mem_ready=ram ? ram_ready && !draw_busy : local_ready;
    assign mem_rdata=ram ? ram_data : fb ? fb_data : local_data;
    reg clkref=0;
    always @(posedge clk) clkref<=~clkref;
    sdram_gb sdram(.clk(fclk),.clkref(clkref),.resetn(resetn),.busy(),
        .SDRAM_DQ(IO_sdram_dq),.SDRAM_A(O_sdram_addr),.SDRAM_BA(O_sdram_ba),
        .SDRAM_nCS(O_sdram_cs_n),.SDRAM_nWE(O_sdram_wen_n),
        .SDRAM_nRAS(O_sdram_ras_n),.SDRAM_nCAS(O_sdram_cas_n),
        .SDRAM_CKE(O_sdram_cke),.SDRAM_DQM(O_sdram_dqm),
        .addrA(22'd0),.weA(1'b0),.dinA(8'd0),.oeA(1'b0),.doutA(),
        .addrB(22'd0),.weB(1'b0),.dinB(8'd0),.oeB(1'b0),.doutB(),
        .rv_addr(rv_addr),.rv_din(rv_din),.rv_ds(rv_ds),.rv_dout(rv_dout),
        .rv_req(rv_req),.rv_req_ack(rv_ack),.rv_we(rv_we));
    // Palette and OAM shadow share one on-chip RAM. Reads belong to the
    // renderer during a draw; CPU byte writes merge while SDRAM acknowledges.
    wire mirror_select=mem_addr[31:24]==5 || mem_addr[31:24]==7;
    wire [8:0] cpu_mirror_addr={mem_addr[25],mem_addr[9:2]};
    wire [8:0] draw_mirror_addr;
    wire [8:0] mirror_address=draw_busy ? draw_mirror_addr : cpu_mirror_addr;
    reg [31:0] mirror[0:511];
    reg [31:0] mirror_q;
    wire [31:0] mirror_merged={mem_wstrb[3] ? mem_wdata[31:24] : mirror_q[31:24],
        mem_wstrb[2] ? mem_wdata[23:16] : mirror_q[23:16],
        mem_wstrb[1] ? mem_wdata[15:8] : mirror_q[15:8],
        mem_wstrb[0] ? mem_wdata[7:0] : mirror_q[7:0]};
    always @(posedge clk) begin
        mirror_q<=mirror[mirror_address];
        if (loaded && !draw_busy && mem_valid && mirror_select && bus_ready && |mem_wstrb)
            mirror[mirror_address]<=mirror_merged;
    end
    studio_renderer renderer(.clk(clk),.resetn(loaded),.start(draw_start),.busy(draw_busy),
        .control(regs[0][15:0]),.bg0(regs[2][15:0]),.bg1(regs[2][31:16]),
        .sx0(regs[4][15:0]),.sy0(regs[4][31:16]),.sx1(regs[5][15:0]),.sy1(regs[5][31:16]),
        .mem_valid(draw_mem_valid),.mem_addr(draw_mem_addr),
        .mem_ready(bus_ready && draw_busy),.mem_data(bus_rdata),
        .mirror_addr(draw_mirror_addr),.mirror_data(mirror_q),
        .fb_write(draw_fb_write),.fb_addr(draw_fb_addr),.fb_data(draw_fb_data));
    studio_lcd_video display(.clk(clk),.write(draw_fb_write || (mem_valid && fb && !mem_ready)),
        .address(draw_fb_write ? draw_fb_addr : mem_addr[16:2]),
        .data(draw_fb_write ? draw_fb_data : mem_wdata),.strobes(draw_fb_write ? 4'b1111 : mem_wstrb),
        .read_data(fb_data),.pix_clk(pix_clk),.resetn(pix_resetn),
        .show(loaded && game_frames!=0),.frames(lcd_frames),
        .lcd_dclk(lcd_dclk),.lcd_de(lcd_de),.lcd_hsync(lcd_hsync),.lcd_vsync(lcd_vsync),
        .lcd_r(lcd_r),.lcd_g(lcd_g),.lcd_b(lcd_b));
    assign led={~game_frames[2],~loaded};
endmodule
