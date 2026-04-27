`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// player_bullet_tb.v — self-checking testbench for player_bullet (SPEC §10.2).
//
// All expected values are derived from docs/SPEC.md. The RTL under test
// (src/player_bullet.v) does not exist at the time this testbench was written;
// expected outputs are traced back to SPEC sections, never to an
// implementation.
//
// Coverage (one check-group per item):
//   T1  Reset correctness           — SPEC §10.2.6
//   T2  Spawn basic                 — SPEC §10.2.2 step 3; §10.2.5
//   T3  Spawn priority              — SPEC §10.2.5 "lowest-index-first"
//   T4  Overflow drop               — SPEC §10.2.5 "Overflow: drop silently"
//   T5  Multi-pulse collapse        — SPEC §10.2.3
//   T6  Advance                     — SPEC §10.2.2 step 1 (N=2, Q7)
//   T7  Despawn via top-exit        — SPEC §10.2.2 step 2 (pb_y_next >= 150)
//   T8  Despawn via hit_mask        — SPEC §10.2.2 step 2; §10.2.1
//   T9  Spawn underflow edge        — SPEC §10.2.2 step 3 + step 2
//   T10 shoot_latch clears on full  — SPEC §10.2.5; §10.2.3
//
// Pending (none — all behaviors in SPEC §10.2 are pinned; Q9 default noted in
// §10.2.1 and exercised via hit_mask direct-clear semantics).
//
// Timing notes (per SPEC §1.1, §10.2.3, GOTCHAS §G15):
//   - pixel_clk is 25 MHz → 40 ns period.
//   - game_tick is a single-cycle pulse on pixel_clk. Modeled as a
//     pulse_game_tick task that raises game_tick for exactly one cycle.
//   - shoot_pulse likewise single-cycle on pixel_clk.
//   - shoot_pulse must occur on a DIFFERENT pixel_clk cycle from game_tick
//     because §10.2.3's latch writes `else if (game_tick) ... else if
//     (shoot_pulse)` — a same-cycle coincidence would let game_tick win and
//     drop the pulse.
//
// Bus packing (SPEC §1.8): slot i lives at bits [i*8 +: 8]; slot 0 at LSB.
// -----------------------------------------------------------------------------

module player_bullet_tb;

    // ------------------------------------------------------------------------
    // Clock / stimulus
    // ------------------------------------------------------------------------
    reg         pixel_clk   = 1'b0;
    reg         reset       = 1'b1;
    reg         game_tick   = 1'b0;
    reg         shoot_pulse = 1'b0;
    reg  [7:0]  player_x    = 8'd0;
    reg  [7:0]  player_y    = 8'd0;
    reg  [7:0]  hit_mask    = 8'd0;

    wire [63:0] pb_x_flat;
    wire [63:0] pb_y_flat;
    wire [7:0]  pb_active;

    // 25 MHz pixel clock (SPEC §1.1)
    always #20 pixel_clk = ~pixel_clk;

    // ------------------------------------------------------------------------
    // DUT instantiation — port names per SPEC §10.2.1 / §1.7
    // ------------------------------------------------------------------------
    player_bullet dut (
        .pixel_clk   (pixel_clk),
        .reset       (reset),
        .game_tick   (game_tick),
        .shoot_pulse (shoot_pulse),
        .player_x    (player_x),
        .player_y    (player_y),
        .hit_mask    (hit_mask),
        .pb_x_flat   (pb_x_flat),
        .pb_y_flat   (pb_y_flat),
        .pb_active   (pb_active)
    );

    // ------------------------------------------------------------------------
    // Convenience slot accessors (SPEC §1.8 packing)
    // ------------------------------------------------------------------------
    wire [7:0] pb_x0 = pb_x_flat[ 7: 0];
    wire [7:0] pb_x1 = pb_x_flat[15: 8];
    wire [7:0] pb_x2 = pb_x_flat[23:16];
    wire [7:0] pb_x3 = pb_x_flat[31:24];
    wire [7:0] pb_x4 = pb_x_flat[39:32];
    wire [7:0] pb_x5 = pb_x_flat[47:40];
    wire [7:0] pb_x6 = pb_x_flat[55:48];
    wire [7:0] pb_x7 = pb_x_flat[63:56];

    wire [7:0] pb_y0 = pb_y_flat[ 7: 0];
    wire [7:0] pb_y1 = pb_y_flat[15: 8];
    wire [7:0] pb_y2 = pb_y_flat[23:16];
    wire [7:0] pb_y3 = pb_y_flat[31:24];
    wire [7:0] pb_y4 = pb_y_flat[39:32];
    wire [7:0] pb_y5 = pb_y_flat[47:40];
    wire [7:0] pb_y6 = pb_y_flat[55:48];
    wire [7:0] pb_y7 = pb_y_flat[63:56];

    // ------------------------------------------------------------------------
    // Test bookkeeping and assertion macro (Verilog-2001 check task)
    // ------------------------------------------------------------------------
    integer errors = 0;
    integer passes = 0;

    task check;
        input [511:0] name;
        input         cond;
        input [511:0] spec_cite;
        begin
            if (cond) begin
                passes = passes + 1;
                // Uncomment for verbose logging:
                // $display("PASS: %0s (%0s)", name, spec_cite);
            end else begin
                $display("FAIL: %0s -- expected per %0s", name, spec_cite);
                errors = errors + 1;
            end
        end
    endtask

    // Pulse game_tick high for exactly one pixel_clk cycle (GOTCHAS §G15).
    // Enter: at any point; exits one cycle after the posedge that sampled it.
    task pulse_game_tick;
        begin
            @(negedge pixel_clk);
            game_tick = 1'b1;
            @(negedge pixel_clk);
            game_tick = 1'b0;
        end
    endtask

    // Pulse shoot_pulse high for exactly one pixel_clk cycle (SPEC §10.2.3).
    task pulse_shoot;
        begin
            @(negedge pixel_clk);
            shoot_pulse = 1'b1;
            @(negedge pixel_clk);
            shoot_pulse = 1'b0;
        end
    endtask

    // Pulse shoot_pulse, then pulse game_tick (distinct cycles so the latch
    // write path per §10.2.3 actually captures the pulse before game_tick).
    task fire_and_tick;
        begin
            pulse_shoot;
            pulse_game_tick;
            @(negedge pixel_clk); // let one settled cycle pass for observation
        end
    endtask

    // Pulse game_tick only (no shoot_pulse).
    task tick_only;
        begin
            pulse_game_tick;
            @(negedge pixel_clk);
        end
    endtask

    // Hold reset for a few cycles, then release.
    task do_reset;
        begin
            reset       = 1'b1;
            shoot_pulse = 1'b0;
            game_tick   = 1'b0;
            hit_mask    = 8'd0;
            player_x    = 8'd0;
            player_y    = 8'd0;
            @(negedge pixel_clk);
            @(negedge pixel_clk);
            @(negedge pixel_clk);
            reset = 1'b0;
            @(negedge pixel_clk);
            @(negedge pixel_clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------------
    initial begin
        // --- Safety timeout ---
        #200000;
        $display("FAIL: simulation timeout -- DUT likely not advancing");
        $display("TEST FAILED: %0d error(s)", errors + 1);
        $finish;
    end

    initial begin
        // ====================================================================
        // T1 — Reset correctness (SPEC §10.2.6)
        //   After reset deasserts: pb_active == 8'd0, every pb_x/pb_y slot
        //   reads 0, and shoot_latch is 0 (observed via behavioral symptom:
        //   a game_tick with no prior shoot_pulse causes no spawn).
        // ====================================================================
        do_reset;

        check("T1.a pb_active == 0 after reset",
              pb_active === 8'd0,
              "SPEC §10.2.6");

        check("T1.b pb_x_flat all slots 0 after reset",
              pb_x_flat === 64'd0,
              "SPEC §10.2.6");

        check("T1.c pb_y_flat all slots 0 after reset",
              pb_y_flat === 64'd0,
              "SPEC §10.2.6");

        // Tick with no shoot_pulse: confirms shoot_latch was 0 (no phantom spawn)
        player_x = 8'd100;
        player_y = 8'd140;
        tick_only;
        check("T1.d no spawn on bare tick after reset (shoot_latch==0)",
              pb_active === 8'd0,
              "SPEC §10.2.6 + §10.2.2 step 3");

        // ====================================================================
        // T2 — Spawn basic (SPEC §10.2.2 step 3; §10.2.5)
        //   shoot_pulse -> game_tick -> slot 0 active at
        //   (player_x, player_y - 16). Lowest-index-first per §10.2.5.
        // ====================================================================
        do_reset;
        player_x = 8'd100;
        player_y = 8'd140;

        fire_and_tick;

        check("T2.a slot 0 active after first spawn",
              pb_active === 8'b0000_0001,
              "SPEC §10.2.5 lowest-index-first");

        check("T2.b slot 0 x == player_x",
              pb_x0 === 8'd100,
              "SPEC §10.2.2 step 3 (pb_x_next = player_x)");

        check("T2.c slot 0 y == player_y - 16",
              pb_y0 === 8'd124, // 140 - 16
              "SPEC §10.2.2 step 3 (pb_y_next = player_y - 16)");

        check("T2.d other slots remain inactive",
              pb_active[7:1] === 7'b000_0000,
              "SPEC §10.2.5 lowest-index-first (single spawn)");

        // ====================================================================
        // T3 — Spawn priority (SPEC §10.2.5)
        //   With slots 0 and 2 active, shoot_pulse -> game_tick selects
        //   slot 1 (lowest free). Constructed by spawning 3 bullets and
        //   then clearing slot 1 via hit_mask.
        // ====================================================================
        do_reset;
        player_x = 8'd50;
        player_y = 8'd140; // high y keeps bullets above despawn threshold 150

        // Spawn 3 consecutive bullets: slots 0, 1, 2 become active.
        fire_and_tick; // slot 0
        fire_and_tick; // slot 1
        fire_and_tick; // slot 2

        check("T3.a three bullets active after 3 spawns",
              pb_active === 8'b0000_0111,
              "SPEC §10.2.5 lowest-index-first");

        // Clear slot 1 via hit_mask (SPEC §10.2.2 step 2). One-cycle pulse on
        // the game_tick cycle.
        @(negedge pixel_clk);
        hit_mask = 8'b0000_0010;
        game_tick = 1'b1;
        @(negedge pixel_clk);
        hit_mask = 8'd0;
        game_tick = 1'b0;
        @(negedge pixel_clk);

        check("T3.b slot 1 cleared by hit_mask",
              pb_active === 8'b0000_0101,
              "SPEC §10.2.2 step 2 (hit_mask clears)");

        // Now request another spawn. With slots 0 and 2 busy, slot 1 is the
        // lowest free index and must be chosen.
        fire_and_tick;

        check("T3.c spawn fills slot 1 (lowest-free-index)",
              pb_active === 8'b0000_0111,
              "SPEC §10.2.5 lowest-index-first");

        // Slot 1 x/y should be the fresh spawn coords, not a stale value.
        // player_x=50, and the current player_y=140 (unchanged this test).
        // Since step 1 (advance) runs before step 3 (spawn), the freshly
        // spawned bullet's y was not touched by advance: SPEC §10.2.2 says
        // advance iterates over pb_active[i] (pre-spawn state); new spawn
        // assigns pb_y_next[i] = player_y - 16 directly.
        check("T3.d slot 1 x == player_x at spawn",
              pb_x1 === 8'd50,
              "SPEC §10.2.2 step 3 (pb_x_next = player_x)");

        check("T3.e slot 1 y == player_y - 16 at spawn",
              pb_y1 === 8'd124, // 140 - 16
              "SPEC §10.2.2 step 3 (pb_y_next = player_y - 16)");

        // ====================================================================
        // T4 — Overflow drop (SPEC §10.2.5 "drop silently")
        //   With all 8 slots full, a shoot_pulse + game_tick must not
        //   change pb_active. shoot_latch is still cleared (T10 exercises
        //   that symptom directly).
        // ====================================================================
        do_reset;
        player_x = 8'd80;
        player_y = 8'd140;

        // Fill all 8 slots.
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;

        check("T4.a pool full (all 8 slots active)",
              pb_active === 8'b1111_1111,
              "SPEC §10.2.5 lowest-index-first (sequential fill)");

        // Extra spawn attempt with all slots full.
        fire_and_tick;

        check("T4.b pb_active unchanged when pool full on shoot",
              pb_active === 8'b1111_1111,
              "SPEC §10.2.5 Overflow: drop silently");

        // ====================================================================
        // T5 — Multi-pulse collapse (SPEC §10.2.3)
        //   Three shoot_pulses between ticks collapse to one spawn.
        // ====================================================================
        do_reset;
        player_x = 8'd120;
        player_y = 8'd140;

        pulse_shoot;
        pulse_shoot;
        pulse_shoot;
        pulse_game_tick;
        @(negedge pixel_clk);

        check("T5.a three shoot_pulses between ticks -> exactly 1 spawn",
              pb_active === 8'b0000_0001,
              "SPEC §10.2.3 multi-pulse collapse");

        // ====================================================================
        // T6 — Advance (SPEC §10.2.2 step 1, N=2 per Q7)
        //   Single active slot at y=100 -> after one game_tick, y=98.
        //   Achieved by spawning with player_y=116 (so spawn y = 100), then
        //   issuing a game_tick with no shoot_pulse and no hit_mask.
        // ====================================================================
        do_reset;
        player_x = 8'd75;
        player_y = 8'd116; // spawn y = 116 - 16 = 100
        fire_and_tick;     // slot 0 now at y = 100

        check("T6.a slot 0 y == 100 after initial spawn",
              pb_y0 === 8'd100,
              "SPEC §10.2.2 step 3 (spawn at player_y - 16)");

        // Advance one tick (no spawn).
        tick_only;

        check("T6.b slot 0 y advances by N=2 -> 98",
              pb_y0 === 8'd98,
              "SPEC §10.2.2 step 1; Q7 N=2");

        check("T6.c slot 0 still active (98 < 150, no hit)",
              pb_active === 8'b0000_0001,
              "SPEC §10.2.2 step 2 (pb_y_next < 150 stays active)");

        // ====================================================================
        // T7 — Despawn via top-exit (SPEC §10.2.2 step 2)
        //   Slot at y=1 -> game_tick -> y_next = 1 - 2 = 8'd255 (underflow),
        //   255 >= 150 triggers despawn. pb_active[0] clears this tick.
        //
        //   Setup: spawn a bullet with player_y=17 (spawn y=1). Then the
        //   very next tick advances it to y_next=255 and clears the slot.
        // ====================================================================
        do_reset;
        player_x = 8'd60;
        player_y = 8'd17; // spawn y = 17 - 16 = 1
        fire_and_tick;

        check("T7.a pre-condition: slot 0 y == 1 after spawn",
              pb_y0 === 8'd1,
              "SPEC §10.2.2 step 3 (spawn at player_y - 16)");
        check("T7.b pre-condition: slot 0 active",
              pb_active === 8'b0000_0001,
              "SPEC §10.2.2 step 3");

        // Next tick: 1 - 2 underflows to 255; 255 >= 150 => despawn.
        tick_only;

        check("T7.c slot 0 despawned via top-exit (y underflow >= 150)",
              pb_active[0] === 1'b0,
              "SPEC §10.2.2 step 2 (pb_y_next >= 150 clears slot)");
        check("T7.d no other slots accidentally active",
              pb_active === 8'b0000_0000,
              "SPEC §10.2.2 step 2");

        // ====================================================================
        // T8 — Despawn via hit_mask (SPEC §10.2.2 step 2; §10.2.1)
        //   Slot i active, hit_mask[i] = 1 for one game_tick cycle ->
        //   pb_active[i] clears.
        // ====================================================================
        do_reset;
        player_x = 8'd90;
        player_y = 8'd140;
        fire_and_tick; // slot 0 active at (90, 124)
        fire_and_tick; // slot 1 active
        fire_and_tick; // slot 2 active

        check("T8.a pre-condition: slots 0,1,2 active",
              pb_active === 8'b0000_0111,
              "SPEC §10.2.5");

        // Hit slot 2 only, on game_tick.
        @(negedge pixel_clk);
        hit_mask = 8'b0000_0100;
        game_tick = 1'b1;
        @(negedge pixel_clk);
        hit_mask = 8'd0;
        game_tick = 1'b0;
        @(negedge pixel_clk);

        check("T8.b slot 2 cleared by hit_mask, others retained",
              pb_active === 8'b0000_0011,
              "SPEC §10.2.2 step 2 + §10.2.1");

        // ====================================================================
        // T9 — Spawn underflow edge case (SPEC §10.2.2 step 3 + step 2)
        //   player_y = 10 -> spawn y = 10 - 16 = 8'd250 (underflow).
        //   Next game_tick: 250 - 2 = 248. 248 >= 150 -> despawn.
        //   The "hidden bullet" lives for one tick only.
        // ====================================================================
        do_reset;
        player_x = 8'd64;
        player_y = 8'd10; // spawn y = 10 - 16 = -6 mod 256 = 250
        fire_and_tick;

        check("T9.a spawn y = 250 (underflow of player_y - 16)",
              pb_y0 === 8'd250,
              "SPEC §10.2.2 step 3 (8-bit subtraction wraps)");
        check("T9.b slot 0 active one tick post-spawn",
              pb_active === 8'b0000_0001,
              "SPEC §10.2.2 step 3");

        // Next tick: y advances to 248, despawn because 248 >= 150.
        tick_only;

        check("T9.c slot 0 despawns on the next tick (y_next=248 >= 150)",
              pb_active === 8'b0000_0000,
              "SPEC §10.2.2 step 2 (pb_y_next >= 150 clears slot)");

        // ====================================================================
        // T10 — shoot_latch clears on spawn failure (SPEC §10.2.5; §10.2.3)
        //   Pool-full tick clears shoot_latch regardless of spawn outcome.
        //   We observe this behaviorally: after the pool-full tick, free a
        //   slot via hit_mask and issue a game_tick with NO intervening
        //   shoot_pulse. If shoot_latch had remained set (buggy), slot 0
        //   would be re-filled on this tick. It must stay cleared.
        // ====================================================================
        do_reset;
        player_x = 8'd30;
        player_y = 8'd140;

        // Fill all 8 slots.
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;
        fire_and_tick;

        check("T10.a pre-condition: pool full",
              pb_active === 8'b1111_1111,
              "SPEC §10.2.5 lowest-index-first (sequential fill)");

        // Pool-full spawn attempt: shoot_pulse fires, then game_tick fires.
        // Per §10.2.5 + §10.2.3, shoot_latch must clear even though no slot
        // was free to receive the spawn.
        fire_and_tick;

        check("T10.b pool-full tick leaves pb_active unchanged",
              pb_active === 8'b1111_1111,
              "SPEC §10.2.5 Overflow: drop silently");

        // Now free slot 0 via hit_mask, and issue a game_tick with NO
        // shoot_pulse. If shoot_latch leaked through (bug), slot 0 would be
        // re-filled with (player_x, player_y-16). It must not.
        @(negedge pixel_clk);
        hit_mask = 8'b0000_0001;
        game_tick = 1'b1;
        @(negedge pixel_clk);
        hit_mask = 8'd0;
        game_tick = 1'b0;
        @(negedge pixel_clk);

        check("T10.c slot 0 stays empty (latch cleared on full tick)",
              pb_active[0] === 1'b0,
              "SPEC §10.2.5 + §10.2.3 (latch clears every game_tick)");

        check("T10.d other 7 slots still active",
              pb_active[7:1] === 7'b111_1111,
              "SPEC §10.2.2 (no unrelated state change)");

        // Sanity: a real shoot_pulse + tick now DOES spawn into slot 0.
        fire_and_tick;
        check("T10.e new shoot_pulse + tick refills slot 0 as expected",
              pb_active[0] === 1'b1,
              "SPEC §10.2.2 step 3");

        // ====================================================================
        // Summary
        // ====================================================================
        $display("--------------------------------------------------");
        $display("Checks passed: %0d", passes);
        $display("Checks failed: %0d", errors);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d error(s)", errors);
        $finish;
    end

endmodule
