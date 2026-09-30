// Local ROM loading protocol: GBLD, uint32 length, bytes, uint32 CRC32 (LE).
// Q returns GBST + loaded + byte count + CRC32 + cart address + CPU fault.
// K followed by an active-high GB key mask changes the serial buttons.
module gb_uart_loader #(
    parameter [7:0] MAGIC0="G", MAGIC1="B",
    parameter [31:0] MIN_BYTES=32768, MAX_BYTES=1048576
) (
    input wire clk, resetn,
    input wire rx_valid, input wire [7:0] rx_data,
    output reg [21:0] write_addr,
    output reg [7:0] write_data, output reg write_valid,
    output reg loaded, output reg [7:0] keys,
    input wire [15:0] cart_addr, input wire fault,
    input wire [31:0] debug_pc, debug_addr,
    output wire tx_valid, output reg [7:0] tx_data, input wire tx_ready
);
    function automatic [31:0] crc_byte(input [31:0] crc, input [7:0] value);
        reg [31:0] c;
        begin
            c = crc ^ value;
            for (integer i=0; i<8; i=i+1)
                c = c[0] ? (c >> 1) ^ 32'hedb88320 : c >> 1;
            crc_byte = c;
        end
    endfunction
    localparam IDLE=0, MAGIC_B=1, MAGIC_L=2, MAGIC_D=3,
               LENGTH=4, PAYLOAD=5, CHECKSUM=6, KEY=7, SETTLE=8;
    reg [3:0] state;
    reg [1:0] index;
    reg [31:0] length, count, crc, expected;
    reg [4:0] settle;
    reg [4:0] tx_index;
    reg sending;
    reg [31:0] reply_count, reply_crc;
    reg [15:0] reply_addr;
    reg reply_loaded, reply_fault;
    assign tx_valid = sending;
    always @* begin
        case (tx_index)
          0: tx_data=MAGIC0; 1: tx_data=MAGIC1; 2: tx_data="S"; 3: tx_data="T";
          4: tx_data={7'd0,reply_loaded};
          5,6,7,8: tx_data=reply_count >> ((tx_index-5)*8);
          9,10,11,12: tx_data=reply_crc >> ((tx_index-9)*8);
          13: tx_data=reply_addr[7:0]; 14: tx_data=reply_addr[15:8];
          15: tx_data={7'd0,reply_fault};
          default: tx_data=0;
        endcase
    end
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state<=IDLE; index<=0; loaded<=0; keys<=0;
            length<=0; count<=0; crc<=32'hffffffff; expected<=0;
            write_valid<=0; write_addr<=0; write_data<=0;
            sending<=0; tx_index<=0; settle<=0;
            reply_count<=0; reply_crc<=0; reply_addr<=0;
            reply_loaded<=0; reply_fault<=0;
        end else begin
            write_valid<=0;
            if (sending && tx_ready) begin
                if (tx_index==15) sending<=0;
                else tx_index<=tx_index+1'b1;
            end
            if (state==SETTLE) begin
                settle<=settle+1'b1;
                if (settle==31) begin
                    loaded <= (expected == ~crc);
                    reply_loaded <= (expected == ~crc);
                    reply_count<=count; reply_crc<=~crc;
                    reply_addr<=cart_addr; reply_fault<=fault;
                    sending<=1; tx_index<=0; state<=IDLE;
                end
            end else if (rx_valid) begin
                case (state)
                  IDLE: case (rx_data)
                    MAGIC0: state<=MAGIC_B;
                    "K": state<=KEY;
                    "Q": if (!sending) begin
                        reply_loaded<=loaded; reply_count<=count; reply_crc<=~crc;
                        reply_addr<=cart_addr; reply_fault<=fault;
                        sending<=1; tx_index<=0;
                    end
                    "P","H","A": if (!sending) begin
                        reply_loaded<=loaded; reply_count<=count; reply_crc<=~crc;
                        reply_addr<=rx_data=="P" ? debug_pc[15:0] :
                            rx_data=="H" ? debug_pc[31:16] : debug_addr[15:0];
                        reply_fault<=fault; sending<=1; tx_index<=0;
                    end
                    default: ;
                  endcase
                  MAGIC_B: state <= rx_data==MAGIC1 ? MAGIC_L : IDLE;
                  MAGIC_L: state <= rx_data=="L" ? MAGIC_D : IDLE;
                  MAGIC_D: if (rx_data=="D") begin
                      loaded<=0; length<=0; count<=0; crc<=32'hffffffff;
                      index<=0; state<=LENGTH; keys<=0;
                  end else state<=IDLE;
                  LENGTH: begin
                      length <= length | ({24'd0,rx_data} << (index*8));
                      index<=index+1'b1;
                      if (index==3) begin
                          // Cart RAM begins at 1 MiB in the upstream memory map.
                          if (rx_data==0 && length>=MIN_BYTES && length<=MAX_BYTES)
                              state<=PAYLOAD;
                          else state<=IDLE;
                      end
                  end
                  PAYLOAD: begin
                      write_addr<=count[21:0]; write_data<=rx_data; write_valid<=1;
                      count<=count+1'b1; crc<=crc_byte(crc,rx_data);
                      if (count+1==length) begin
                          expected<=0; index<=0; state<=CHECKSUM;
                      end
                  end
                  CHECKSUM: begin
                      expected<=expected | ({24'd0,rx_data} << (index*8));
                      index<=index+1'b1;
                      if (index==3) begin state<=SETTLE; settle<=0; end
                  end
                  KEY: begin keys<=rx_data; state<=IDLE; end
                  default: state<=IDLE;
                endcase
            end
        end
    end
endmodule
