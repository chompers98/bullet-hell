`timescale 1ns / 1ps
// renderer_tb — end-to-end integration check.
//
// Drives the new fully-integrated top.v with:
//   - SW0 pulsed for reset
//   - All directional + center buttons held low
//   - 100 MHz ClkPort
// After 1 frame's worth of simulation time the framebuffer should contain:
//   - Background (palette index 1) everywhere except sprite regions
//   - Player (white, index 2) at reset position (92, 126), 16×16
//   - Boss   (red,   index 3) at reset position (92, 8),  16×16
// Player bullets are inactive at reset (no shoot, no spawn). Boss bullets
// don't fire until ~26 game_ticks (≈ 430 ms) — far past our 18 ms window.
//
// IMPL NOTE: this used to drive hardcoded bullet positions through top.v.
// Now top.v owns the controllers; the test devolves to player + boss
// position checks plus a "no spurious bullet pixels" sanity check.

module renderer_tb;
    reg         ClkPort = 1'b0;
    reg         SW0     = 1'b0;
    reg         BtnC    = 1'b0;
    reg         BtnU    = 1'b0;
    reg         BtnD    = 1'b0;
    reg         BtnL    = 1'b0;
    reg         BtnR    = 1'b0;

    wire        hSync, vSync, QuadSpiFlashCS;
    wire [3:0]  vgaR, vgaG, vgaB;
    wire [15:0] Ld;
    wire [6:0]  seg;
    wire        Dp;
    wire [7:0]  An;

    always #5 ClkPort = ~ClkPort;  // 100 MHz

    top dut (
        .ClkPort       (ClkPort),
        .SW0           (SW0),
        .BtnC          (BtnC),
        .BtnU          (BtnU),
        .BtnD          (BtnD),
        .BtnL          (BtnL),
        .BtnR          (BtnR),
        .hSync         (hSync),
        .vSync         (vSync),
        .vgaR          (vgaR),
        .vgaG          (vgaG),
        .vgaB          (vgaB),
        .Ld            (Ld),
        .seg           (seg),
        .Dp            (Dp),
        .An            (An),
        .QuadSpiFlashCS(QuadSpiFlashCS)
    );

    integer errors = 0;
    integer passes = 0;
    reg [3:0] pix;

    task check;
        input [255:0] name;
        input         cond;
        begin
            if (cond) passes = passes + 1;
            else begin
                $display("FAIL: %0s", name);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("renderer_tb.vcd");
        $dumpvars(0, renderer_tb);

        // Pulse reset.
        SW0 = 1'b1;
        #500;
        SW0 = 1'b0;

        // Wait long enough for frame 1 to draw (FSM finishes ~1.3 ms after
        // vblank @ ~15.4 ms; we sample at 18 ms).
        #18_000_000;

        // ---- Player at (92, 126); pixel (95, 130) is inside ----
        // Address = 130*200 + 95 = 26095.
        pix = dut.u_renderer.u_fb.mem[26095];
        $display("fb[26095] (inside player) = %h (expect 2 = white)", pix);
        check("player_white", pix == 4'h2);

        // ---- Boss at (92, 8); pixel (95, 10) is inside ----
        // Address = 10*200 + 95 = 2095.
        pix = dut.u_renderer.u_fb.mem[2095];
        $display("fb[2095]  (inside boss)   = %h (expect 3 = red)", pix);
        check("boss_red", pix == 4'h3);

        // ---- No bullets active at reset → no bullet pixels ----
        // Sample a mid-screen point well away from player/boss.
        pix = dut.u_renderer.u_fb.mem[15437];
        $display("fb[15437] (open field)    = %h (expect 1 = background)", pix);
        check("no_pb_yet", pix == 4'h1);

        pix = dut.u_renderer.u_fb.mem[9557];
        $display("fb[9557]  (open field)    = %h (expect 1 = background)", pix);
        check("no_bb_yet", pix == 4'h1);

        // ---- Background corner ----
        pix = dut.u_renderer.u_fb.mem[0];
        $display("fb[0]     (background)    = %h (expect 1 = bg)", pix);
        check("bg_corner", pix == 4'h1);

        // ---- LEDs reflect lives = 5 ----
        check("lives_leds", Ld == 16'h001F);

        $display("renderer_tb DONE: %0d passed, %0d failed", passes, errors);
        if (errors == 0) $display("renderer_tb: ALL PASS");
        else             $display("renderer_tb: FAIL");

        $finish;
    end
endmodule
