`timescale 1ns / 1ps
module sprite_rom_bbullet_p2 (
    input  wire [7:0] addr,
    output wire [3:0] data
);
    reg [3:0] mem [0:255];
    initial $readmemh("bbullet_p2.mem", mem);
    assign data = mem[addr];
endmodule
