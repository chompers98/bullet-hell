`timescale 1ns / 1ps
module sprite_rom_pbullet (
    input  wire [7:0] addr,
    output wire [3:0] data
);
    reg [3:0] mem [0:255];
    initial $readmemh("pbullet.mem", mem);
    assign data = mem[addr];
endmodule
