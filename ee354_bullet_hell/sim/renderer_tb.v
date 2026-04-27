`timescale 1ns / 1ps
// Simulates the Task 2 top end-to-end. Runs one full frame (~16.67 ms) and
// dumps a VCD. After sim, the framebuffer contents should stabilize to a
// static scene matching the hardcoded sprite positions in top.v.
module renderer_tb;
    reg         ClkPort = 0;
    reg         BtnC    = 0;
    wire        hSync, vSync, QuadSpiFlashCS;
    wire [3:0]  vgaR, vgaG, vgaB;

    always #5 ClkPort = ~ClkPort; // 100 MHz

    top dut (
        .ClkPort       (ClkPort),
        .BtnC          (BtnC),
        .hSync         (hSync),
        .vSync         (vSync),
        .vgaR          (vgaR),
        .vgaG          (vgaG),
        .vgaB          (vgaB),
        .QuadSpiFlashCS(QuadSpiFlashCS)
    );

    integer i;
    reg [3:0] pix;

    initial begin
        $dumpfile("renderer_tb.vcd");
        $dumpvars(0, renderer_tb);
        BtnC = 1;
        #500;
        BtnC = 0;
        // Frame-1 vblank fires at t ~= 15.4 ms; the FSM's clear+draws finish
        // within ~1.3 ms of that. Check at t = 18 ms (FSM idle, before
        // frame-2 vblank at ~32 ms).
        #18_000_000;

        // Player pixel at logical (95, 130): addr = 130*200 + 95 = 26095.
        pix = dut.u_renderer.u_fb.mem[26095];
        $display("fb[26095] (inside player square) = %h (expect 2 = white)", pix);
        // Boss pixel at (95, 10): addr = 10*200 + 95 = 2095.
        pix = dut.u_renderer.u_fb.mem[2095];
        $display("fb[2095]  (inside boss square)   = %h (expect 3 = red)",   pix);
        // Player bullet dot center at (37, 77): addr = 77*200 + 37 = 15437.
        // (sprite rel col/row 7,7 = inside the 4x4 colored region)
        pix = dut.u_renderer.u_fb.mem[15437];
        $display("fb[15437] (inside p-bullet dot)  = %h (expect 6 = cyan)",  pix);
        // Boss bullet p1 dot center at (157, 47): addr = 47*200 + 157 = 9557.
        pix = dut.u_renderer.u_fb.mem[9557];
        $display("fb[9557]  (inside bb-p1 dot)     = %h (expect 7 = yellow)",pix);
        // Boss bullet p2 dot center at (177, 67): addr = 67*200 + 177 = 13577.
        pix = dut.u_renderer.u_fb.mem[13577];
        $display("fb[13577] (inside bb-p2 dot)     = %h (expect 8 = magenta)",pix);
        // Background pixel at (0, 0):
        pix = dut.u_renderer.u_fb.mem[0];
        $display("fb[0]     (background)           = %h (expect 1 = bg)",    pix);

        $finish;
    end
endmodule
