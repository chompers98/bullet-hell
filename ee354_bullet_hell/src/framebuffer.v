`timescale 1ns / 1ps
// 200x150 = 30000 pixels, 4 bits each. Simple dual-port: one write, one read,
// both synchronous on a single clock. Vivado should infer BRAM for this pattern.
module framebuffer (
    input  wire        clk,
    // write port
    input  wire        we,
    input  wire [14:0] wr_addr,
    input  wire [3:0]  wr_data,
    // read port
    input  wire [14:0] rd_addr,
    output reg  [3:0]  rd_data
);
    reg [3:0] mem [0:29999];

    always @(posedge clk) begin
        if (we) mem[wr_addr] <= wr_data;
        rd_data <= mem[rd_addr];
    end
endmodule
