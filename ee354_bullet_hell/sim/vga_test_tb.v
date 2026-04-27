`timescale 1ns / 1ps
// Simulates vga_test_top for long enough to verify one full frame of hsync/vsync.
// 100 MHz -> 10 ns period; one frame at 60 Hz = 16.67 ms. Simulate ~20 ms.
module vga_test_tb;
    reg         ClkPort = 0;
    reg         BtnC    = 0;
    wire        hSync, vSync, QuadSpiFlashCS;
    wire [3:0]  vgaR, vgaG, vgaB;

    always #5 ClkPort = ~ClkPort; // 100 MHz

    vga_test_top dut (
        .ClkPort       (ClkPort),
        .BtnC          (BtnC),
        .hSync         (hSync),
        .vSync         (vSync),
        .vgaR          (vgaR),
        .vgaG          (vgaG),
        .vgaB          (vgaB),
        .QuadSpiFlashCS(QuadSpiFlashCS)
    );

    initial begin
        $dumpfile("vga_test_tb.vcd");
        $dumpvars(0, vga_test_tb);
        BtnC = 1;
        #200;
        BtnC = 0;
        // Run for ~20 ms to cover one full frame + some margin.
        #20_000_000;
        $finish;
    end

    // Monitor hsync/vsync toggles to sanity-check timing.
    initial begin
        $monitor("t=%0t hSync=%b vSync=%b bright=%b", $time, hSync, vSync, dut.bright);
    end
endmodule
