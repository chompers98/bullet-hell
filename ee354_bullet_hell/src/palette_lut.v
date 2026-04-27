`timescale 1ns / 1ps
// 16-entry palette (4-bit index -> 12-bit RGB 4:4:4)
// Index 0 is sentinel transparent / forced black; sprite blitter must skip writes for it.
module palette_lut (
    input  wire [3:0]  index,
    output reg  [11:0] rgb
);
    always @(*) begin
        case (index)
            4'd0:  rgb = 12'h000; // transparent sentinel
            4'd1:  rgb = 12'h112; // dark blue background
            4'd2:  rgb = 12'hFFF; // white - player
            4'd3:  rgb = 12'hF00; // red - boss
            4'd4:  rgb = 12'h800; // dark red - boss shadow
            4'd5:  rgb = 12'hF8C; // pink - boss detail
            4'd6:  rgb = 12'h0FF; // cyan - player bullets
            4'd7:  rgb = 12'hFF0; // yellow - boss bullets phase 1
            4'd8:  rgb = 12'hF0F; // magenta - boss bullets phase 2
            4'd9:  rgb = 12'hF80; // orange
            4'd10: rgb = 12'h0F0; // green
            4'd11: rgb = 12'h333; // dark gray - HUD borders
            4'd12: rgb = 12'hAAA; // light gray - HUD text
            default: rgb = 12'h000;
        endcase
    end
endmodule
