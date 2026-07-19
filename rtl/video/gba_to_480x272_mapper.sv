`timescale 1ns/1ps

module gba_to_480x272_mapper (
    input  logic [8:0] panel_x,
    input  logic [8:0] panel_y,
    input  logic       panel_active,
    output logic       source_active,
    output logic [7:0] source_x,
    output logic [7:0] source_y
);
    localparam integer PANEL_WIDTH   = 480;
    localparam integer PANEL_HEIGHT  = 272;
    localparam integer IMAGE_WIDTH   = 408;
    localparam integer IMAGE_HEIGHT  = 272;
    localparam integer BORDER_LEFT   = (PANEL_WIDTH - IMAGE_WIDTH) / 2;
    localparam integer SOURCE_WIDTH  = 240;
    localparam integer SOURCE_HEIGHT = 160;

    logic [8:0] image_x;
    logic [17:0] scaled_x;
    logic [17:0] scaled_y;

    always_comb begin
        source_active = panel_active &&
                        (panel_x >= BORDER_LEFT) &&
                        (panel_x < BORDER_LEFT + IMAGE_WIDTH) &&
                        (panel_y < IMAGE_HEIGHT);

        if (source_active) begin
            image_x = panel_x - BORDER_LEFT;
            scaled_x = image_x * SOURCE_WIDTH;
            scaled_y = panel_y * SOURCE_HEIGHT;
            source_x = scaled_x / IMAGE_WIDTH;
            source_y = scaled_y / IMAGE_HEIGHT;
        end else begin
            image_x = 9'd0;
            scaled_x = 18'd0;
            scaled_y = 18'd0;
            source_x = 8'd0;
            source_y = 8'd0;
        end
    end
endmodule
