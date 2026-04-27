`timescale 1ns / 1ps
// 16x16 sprite, 4-bit palette index per pixel. Combinational read (infers LUT RAM).
module sprite_rom_player (
    input  wire [7:0] addr,   // {row[3:0], col[3:0]}
    output wire [3:0] data
);
    reg [3:0] mem [0:255];
    initial $readmemh("player.mem", mem);
    assign data = mem[addr];
endmodule
