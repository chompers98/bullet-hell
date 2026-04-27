`timescale 1ns / 1ps
// ============================================================================
// player_controller_tb.v
//
// Self-checking testbench for player_controller.
// All expected values are traced to docs/SPEC.md; no expectations are derived
// from the DUT's internal implementation.
//
// SPEC references:
//   - §1.1  L52-57     pixel_clk is 25 MHz; game_tick is a single-cycle pulse.
//   - §1.2  L59-64     reset is active-high SYNCHRONOUS; takes effect on
//                      rising edge of pixel_clk.
//   - §1.3  L67-73     player_x/y are logical FB coords (8-bit unsigned).
//   - §1.7  L112-131   canonical signal names + widths.
//   - §10.1 L538-545   player_controller contract (revised 2026-04-23):
//                        * Inputs  : pixel_clk, reset, game_tick, BtnU/D/L/R,
//                                    BtnCenter (debounced).
//                        * Outputs : player_x[7:0], player_y[7:0],
//                                    shoot_pulse (single-cycle).
//                        * Movement: hold-to-move. While BtnX is asserted,
//                                    player moves 1 logical pixel per
//                                    game-tick in direction X. Release ->
//                                    motion stops.
//                        * Bounds  : player_x in [0,184], player_y in [0,134].
//                        * Reset  : position to (92,126).
//   - §10.2.3 L587-602 shoot_pulse is a single pixel_clk pulse on BtnCenter
//                      rising edge, for player_bullet's FSM.
//   - GOTCHAS §G5  L69-73    active-high sync reset.
//   - GOTCHAS §G12 L138-142  single clock domain in Week 1 — no CDC.
//   - GOTCHAS §G14 L154-158  state cleared by reset only, never by initial.
//   - GOTCHAS §G15 L162-172  game_tick is a single-cycle pulse, NOT a level.
//
// Coverage (each item below has at least one check() call citing SPEC):
//   1.  Reset initial state (92,126).                   [SPEC §10.1 L544]
//   2.  Synchronous reset (no async deassert effect).   [SPEC §1.2 L61; G5]
//   3.  Idle — no buttons, many game_ticks, no motion.  [SPEC §10.1 L542,544]
//   4.  Hold-to-move semantics for BtnR, BtnL, BtnU, BtnD;
//       release stops motion immediately.               [SPEC §10.1 L542]
//   5.  One pixel per game_tick; no motion without tick.[SPEC §10.1 L542;
//                                                        §1.1 L57; G15]
//   6.  Right clamp at x=184 (no wrap).                 [SPEC §10.1 L543]
//   7.  Left clamp at x=0 (no wrap).                    [SPEC §10.1 L543]
//   8.  Bottom clamp at y=134 (no wrap).                [SPEC §10.1 L543]
//   9.  Top clamp at y=0 (no wrap).                     [SPEC §10.1 L543]
//  10.  shoot_pulse is single pixel_clk cycle on rising
//       edge of BtnCenter; holding BtnCenter = 1 pulse. [SPEC §10.1 L541,
//                                                        §10.2.3 L587-602]
//  11.  shoot_pulse re-arms on release + re-press.      [SPEC §10.1 L541]
//  12.  Reset while moving returns position to (92,126).[SPEC §10.1 L544]
//
// Verilog-2001 only (no SystemVerilog). SPEC §0 / GOTCHAS §G13.
// ============================================================================

module player_controller_tb;

    // -------- Stimulus / observation wires --------
    reg        clk;
    reg        reset;
    reg        game_tick;
    reg        BtnU, BtnD, BtnL, BtnR;
    reg        BtnCenter;

    wire [7:0] player_x;
    wire [7:0] player_y;
    wire       shoot_pulse;

    // -------- DUT --------
    player_controller dut (
        .pixel_clk  (clk),
        .reset      (reset),
        .game_tick  (game_tick),
        .BtnU       (BtnU),
        .BtnD       (BtnD),
        .BtnL       (BtnL),
        .BtnR       (BtnR),
        .BtnCenter  (BtnCenter),
        .player_x   (player_x),
        .player_y   (player_y),
        .shoot_pulse(shoot_pulse)
    );

    // -------- Clock: 25 MHz pixel clock — 40 ns period --------
    initial clk = 1'b0;
    always #20 clk = ~clk;

    // -------- Bookkeeping --------
    integer errors;
    integer passes;

    // -------- check task --------
    task check;
        input [8*96-1:0] name;
        input            cond;
        input [8*96-1:0] spec_cite;
        begin
            if (cond) begin
                $display("PASS: %0s  [%0s]", name, spec_cite);
                passes = passes + 1;
            end else begin
                $display("FAIL: %0s  — expected per %0s  (t=%0t)",
                         name, spec_cite, $time);
                errors = errors + 1;
            end
        end
    endtask

    // -------- Pulse a one-cycle game_tick --------
    task pulse_game_tick;
        begin
            @(negedge clk);
            game_tick = 1'b1;
            @(negedge clk);
            game_tick = 1'b0;
        end
    endtask

    // -------- Hold N pixel_clk cycles (no state change) --------
    task hold_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    // -------- Local helpers --------
    reg [7:0] saved_x, saved_y;
    integer   shoot_count;
    integer   k;

    // Count shoot_pulse assertions over a window.
    reg       mon_enable;
    always @(posedge clk) begin
        if (mon_enable && shoot_pulse) shoot_count = shoot_count + 1;
    end

    // ============================================================
    // Main test sequence
    // ============================================================
    initial begin
        errors      = 0;
        passes      = 0;
        reset       = 1'b1;
        game_tick   = 1'b0;
        BtnU = 0; BtnD = 0; BtnL = 0; BtnR = 0; BtnCenter = 0;
        mon_enable  = 1'b0;
        shoot_count = 0;

        // Hold reset long enough to exercise >1 posedge of pixel_clk.
        @(posedge clk); @(posedge clk); @(posedge clk);

        // ------------------------------------------------------------
        // Test 1: Reset produces (player_x, player_y) == (92, 126).
        // ------------------------------------------------------------
        @(negedge clk);
        check("reset holds player_x==92", player_x == 8'd92, "SPEC 10.1 L544");
        check("reset holds player_y==126", player_y == 8'd126, "SPEC 10.1 L544");
        check("reset holds shoot_pulse==0", shoot_pulse == 1'b0, "SPEC 10.1 L541");

        // ------------------------------------------------------------
        // Test 2: Synchronous reset semantics.
        // ------------------------------------------------------------
        @(negedge clk);
        reset = 1'b0;
        check("just after reset drop: x==92", player_x == 8'd92,
              "SPEC 1.2 L61 sync reset");
        check("just after reset drop: y==126", player_y == 8'd126,
              "SPEC 1.2 L61 sync reset");
        @(posedge clk); @(negedge clk);
        check("post-reset idle x==92", player_x == 8'd92, "SPEC 10.1 L544");
        check("post-reset idle y==126", player_y == 8'd126, "SPEC 10.1 L544");

        // ------------------------------------------------------------
        // Test 3: Idle — no buttons, many game_ticks, no motion.
        // ------------------------------------------------------------
        for (k = 0; k < 20; k = k + 1) pulse_game_tick;
        check("idle: x still 92 after 20 ticks", player_x == 8'd92,
              "SPEC 10.1 L542");
        check("idle: y still 126 after 20 ticks", player_y == 8'd126,
              "SPEC 10.1 L542");

        // ------------------------------------------------------------
        // Test 5a: game_tick gating — even with BtnR held HIGH, position
        //          must NOT advance on clocks with no tick pulse.
        // ------------------------------------------------------------
        @(negedge clk); BtnR = 1'b1;
        hold_cycles(50);
        check("BtnR held, no tick: x still 92", player_x == 8'd92,
              "SPEC 10.1 L542 + G15");

        // ------------------------------------------------------------
        // Test 4a / 5b: One game_tick with BtnR held → +1.
        //               Subsequent ticks continue advancing.
        //               Release → motion stops immediately.
        // ------------------------------------------------------------
        pulse_game_tick;
        check("1 tick with BtnR held: x==93", player_x == 8'd93,
              "SPEC 10.1 L542");
        pulse_game_tick;
        check("2 ticks with BtnR held: x==94", player_x == 8'd94,
              "SPEC 10.1 L542");
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("5 ticks with BtnR held: x==97", player_x == 8'd97,
              "SPEC 10.1 L542");

        // Release BtnR → motion stops immediately on subsequent ticks.
        @(negedge clk); BtnR = 1'b0;
        saved_x = player_x;
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("BtnR released: x frozen across 3 ticks",
              player_x == saved_x, "SPEC 10.1 L542 (release stops motion)");

        // ------------------------------------------------------------
        // Reset to (92,126) for a clean slate.
        // ------------------------------------------------------------
        @(negedge clk); reset = 1'b1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        @(negedge clk); reset = 1'b0;
        @(posedge clk); @(negedge clk);
        check("re-reset: x==92", player_x == 8'd92, "SPEC 10.1 L544");
        check("re-reset: y==126", player_y == 8'd126, "SPEC 10.1 L544");

        // ------------------------------------------------------------
        // Test 4b: BtnL hold-to-move.
        // ------------------------------------------------------------
        @(negedge clk); BtnL = 1'b1;
        pulse_game_tick;
        check("1 tick with BtnL held: x==91", player_x == 8'd91,
              "SPEC 10.1 L542");
        pulse_game_tick; pulse_game_tick;
        check("3 ticks with BtnL held: x==89", player_x == 8'd89,
              "SPEC 10.1 L542");
        @(negedge clk); BtnL = 1'b0;
        saved_x = player_x;
        pulse_game_tick; pulse_game_tick;
        check("BtnL released: x frozen",
              player_x == saved_x, "SPEC 10.1 L542 (release stops motion)");

        // ------------------------------------------------------------
        // Test 4c: BtnU hold-to-move.
        // ------------------------------------------------------------
        @(negedge clk); BtnU = 1'b1;
        pulse_game_tick;
        check("1 tick with BtnU held: y==125", player_y == 8'd125,
              "SPEC 10.1 L542");
        pulse_game_tick; pulse_game_tick;
        check("3 ticks with BtnU held: y==123", player_y == 8'd123,
              "SPEC 10.1 L542");
        @(negedge clk); BtnU = 1'b0;
        saved_y = player_y;
        pulse_game_tick; pulse_game_tick;
        check("BtnU released: y frozen",
              player_y == saved_y, "SPEC 10.1 L542 (release stops motion)");

        // ------------------------------------------------------------
        // Test 4d: BtnD hold-to-move.
        // ------------------------------------------------------------
        @(negedge clk); BtnD = 1'b1;
        pulse_game_tick;
        check("1 tick with BtnD held: y==saved+1",
              player_y == (saved_y + 8'd1), "SPEC 10.1 L542");
        pulse_game_tick; pulse_game_tick;
        check("3 ticks with BtnD held: y==saved+3",
              player_y == (saved_y + 8'd3), "SPEC 10.1 L542");
        @(negedge clk); BtnD = 1'b0;
        saved_y = player_y;
        pulse_game_tick; pulse_game_tick;
        check("BtnD released: y frozen",
              player_y == saved_y, "SPEC 10.1 L542 (release stops motion)");

        // ------------------------------------------------------------
        // Full reset before clamp tests.
        // ------------------------------------------------------------
        @(negedge clk); reset = 1'b1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        @(negedge clk); reset = 1'b0;
        @(posedge clk);

        // ------------------------------------------------------------
        // Test 6: Right clamp at x=184.
        // ------------------------------------------------------------
        @(negedge clk); BtnR = 1'b1;
        for (k = 0; k < 100; k = k + 1) pulse_game_tick;
        @(negedge clk);
        check("right clamp: x==184 after many right ticks",
              player_x == 8'd184, "SPEC 10.1 L543");
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("right clamp: x stays 184 after extra ticks (no wrap, no 185)",
              player_x == 8'd184, "SPEC 10.1 L543");
        @(negedge clk); BtnR = 1'b0;

        // ------------------------------------------------------------
        // Test 7: Left clamp at x=0.
        // ------------------------------------------------------------
        @(negedge clk); BtnL = 1'b1;
        for (k = 0; k < 200; k = k + 1) pulse_game_tick;
        @(negedge clk);
        check("left clamp: x==0 after many left ticks",
              player_x == 8'd0, "SPEC 10.1 L543");
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("left clamp: x stays 0 after extra ticks (no wrap)",
              player_x == 8'd0, "SPEC 10.1 L543");
        @(negedge clk); BtnL = 1'b0;

        // ------------------------------------------------------------
        // Test 8: Bottom clamp at y=134.
        // ------------------------------------------------------------
        @(negedge clk); BtnD = 1'b1;
        for (k = 0; k < 200; k = k + 1) pulse_game_tick;
        @(negedge clk);
        check("bottom clamp: y==134",
              player_y == 8'd134, "SPEC 10.1 L543");
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("bottom clamp: y stays 134 (no wrap, no 135)",
              player_y == 8'd134, "SPEC 10.1 L543");
        @(negedge clk); BtnD = 1'b0;

        // ------------------------------------------------------------
        // Test 9: Top clamp at y=0.
        // ------------------------------------------------------------
        @(negedge clk); BtnU = 1'b1;
        for (k = 0; k < 200; k = k + 1) pulse_game_tick;
        @(negedge clk);
        check("top clamp: y==0",
              player_y == 8'd0, "SPEC 10.1 L543");
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("top clamp: y stays 0 (no wrap)",
              player_y == 8'd0, "SPEC 10.1 L543");
        @(negedge clk); BtnU = 1'b0;

        // ------------------------------------------------------------
        // Full reset before shoot_pulse tests.
        // ------------------------------------------------------------
        @(negedge clk); reset = 1'b1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        @(negedge clk); reset = 1'b0;
        @(posedge clk);

        // ------------------------------------------------------------
        // Test 10: shoot_pulse is exactly 1 pixel_clk on BtnCenter rising.
        // ------------------------------------------------------------
        @(negedge clk);
        shoot_count = 0;
        mon_enable  = 1'b1;
        @(negedge clk);
        BtnCenter = 1'b1;
        hold_cycles(40);
        @(negedge clk);
        BtnCenter = 1'b0;
        hold_cycles(5);
        mon_enable = 1'b0;
        check("held BtnCenter yields exactly 1 shoot_pulse",
              shoot_count == 1, "SPEC 10.1 L541 (single-cycle)");

        // ------------------------------------------------------------
        // Test 11: shoot_pulse re-arms on release + re-press.
        // ------------------------------------------------------------
        @(negedge clk);
        shoot_count = 0;
        mon_enable  = 1'b1;
        @(negedge clk); BtnCenter = 1'b1;
        hold_cycles(3);
        @(negedge clk); BtnCenter = 1'b0;
        hold_cycles(3);
        @(negedge clk); BtnCenter = 1'b1;
        hold_cycles(3);
        @(negedge clk); BtnCenter = 1'b0;
        hold_cycles(3);
        @(negedge clk); BtnCenter = 1'b1;
        hold_cycles(3);
        @(negedge clk); BtnCenter = 1'b0;
        hold_cycles(3);
        mon_enable = 1'b0;
        check("3 separate BtnCenter presses yield 3 shoot_pulses",
              shoot_count == 3, "SPEC 10.1 L541 (re-arm on re-press)");

        // ------------------------------------------------------------
        // Test 12: Reset while holding-to-move returns position to (92,126).
        //          Releasing buttons after reset → no drift.
        // ------------------------------------------------------------
        @(negedge clk); reset = 1'b1;
        @(posedge clk); @(posedge clk);
        @(negedge clk); reset = 1'b0;
        @(posedge clk);

        // Phase A: hold BtnR and observe real motion.
        @(negedge clk); BtnR = 1'b1;
        pulse_game_tick; pulse_game_tick; pulse_game_tick;
        check("pre-reset sanity R: x==95", player_x == 8'd95,
              "SPEC 10.1 L542");
        // Phase B: hold BtnD also.
        @(negedge clk); BtnD = 1'b1;
        pulse_game_tick;
        check("pre-reset sanity D: y==127", player_y == 8'd127,
              "SPEC 10.1 L542");

        // Fire reset while still holding BtnR and BtnD.
        @(negedge clk); reset = 1'b1;
        @(posedge clk); @(posedge clk); @(posedge clk);
        @(negedge clk); reset = 1'b0;
        @(posedge clk); @(negedge clk);
        check("reset during motion: x==92",
              player_x == 8'd92, "SPEC 10.1 L544");
        check("reset during motion: y==126",
              player_y == 8'd126, "SPEC 10.1 L544");

        // Release buttons, tick many times, verify no drift.
        // (With buttons still held, hold-to-move would legitimately advance;
        // releasing proves the position reaches the correct post-reset state
        // and stays there in the absence of held buttons.)
        @(negedge clk); BtnR = 1'b0; BtnD = 1'b0;
        for (k = 0; k < 30; k = k + 1) pulse_game_tick;
        check("buttons released: x stays 92 after 30 ticks",
              player_x == 8'd92, "SPEC 10.1 L544");
        check("buttons released: y stays 126 after 30 ticks",
              player_y == 8'd126, "SPEC 10.1 L544");

        // ------------------------------------------------------------
        // Rollup
        // ------------------------------------------------------------
        $display("--------------------------------------------------");
        $display("Summary: %0d checks passed, %0d failed.",
                 passes, errors);
        if (errors == 0) begin
            $display("TEST PASSED");
            $finish;
        end else begin
            $display("TEST FAILED: %0d error(s)", errors);
            $finish;
        end
    end

    initial begin
        #5000000;
        $display("FAIL: testbench timeout (DUT likely hung)");
        $display("TEST FAILED: 1 error(s)");
        $finish;
    end

endmodule
