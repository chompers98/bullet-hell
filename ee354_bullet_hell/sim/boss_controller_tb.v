`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// boss_controller_tb.v — self-checking testbench for boss_controller
// (SPEC §10.3, §1.7, Q5).
//
// Coverage:
//   T1  Reset: x=92, hp=99, dir=0           — SPEC §10.3 IMPL + Q5 (HP scale)
//   T2  Phase before/after hp threshold     — Q5: phase = (hp <= 50)
//   T3  Phase 1 bounce R then L             — SPEC §10.3 "patrol" + IMPL speed=2
//   T4  Phase 1 right-edge clamp + flip     — IMPL: clamp at X_MAX=184
//   T5  Phase 2 track toward player_x       — SPEC §10.3 phase 2 + IMPL speed=1
//   T6  HP decrement on boss_hit_pulse      — SPEC §10.3 "decrement on hit pulse"
//   T7  HP saturates at 0                   — IMPL: don't underflow
//   T8  boss_death_flag asserts at hp==0    — SPEC §10.3
//   T9  X freezes at hp==0                  — IMPL: position freezes on death
//   T10 boss_y is constant                  — IMPL: SPEC §10.3 silent, fixed Y
// -----------------------------------------------------------------------------

module boss_controller_tb;

    reg         pixel_clk      = 1'b0;
    reg         reset          = 1'b1;
    reg         game_tick      = 1'b0;
    reg  [7:0]  player_x       = 8'd92;
    reg         boss_hit_pulse = 1'b0;

    wire [7:0]  boss_x;
    wire [7:0]  boss_y;
    wire [6:0]  boss_hp;
    wire        phase;
    wire        boss_death_flag;

    always #20 pixel_clk = ~pixel_clk;  // 25 MHz

    boss_controller dut (
        .pixel_clk      (pixel_clk),
        .reset          (reset),
        .game_tick      (game_tick),
        .player_x       (player_x),
        .boss_hit_pulse (boss_hit_pulse),
        .boss_x         (boss_x),
        .boss_y         (boss_y),
        .boss_hp        (boss_hp),
        .phase          (phase),
        .boss_death_flag(boss_death_flag)
    );

    integer errors = 0;
    integer passes = 0;

    task check;
        input [511:0] name;
        input         cond;
        input [511:0] spec_cite;
        begin
            if (cond) passes = passes + 1;
            else begin
                $display("FAIL: %0s -- expected per %0s", name, spec_cite);
                errors = errors + 1;
            end
        end
    endtask

    task pulse_game_tick;
        begin
            @(negedge pixel_clk);  game_tick = 1'b1;
            @(negedge pixel_clk);  game_tick = 1'b0;
        end
    endtask

    task pulse_hit;
        begin
            @(negedge pixel_clk);  boss_hit_pulse = 1'b1;
            @(negedge pixel_clk);  boss_hit_pulse = 1'b0;
        end
    endtask

    task do_reset;
        begin
            reset = 1'b1;
            @(posedge pixel_clk); @(posedge pixel_clk);
            @(negedge pixel_clk); reset = 1'b0;
        end
    endtask

    initial begin
        $dumpfile("boss_controller_tb.vcd");
        $dumpvars(0, boss_controller_tb);

        do_reset;

        // ---- T1: reset state ----
        check("T1.x_init",  boss_x  == 8'd92, "SPEC §10.3 IMPL X_INIT=92 (centered)");
        check("T1.hp_init", boss_hp == 7'd99, "SPEC §1.7 / Q5: HP scale 0..99 → start at 99");
        check("T1.y_const", boss_y  == 8'd8,  "IMPL Y_POS=8 (top of screen)");
        check("T1.phase_init",       phase           == 1'b0, "Q5: hp=99 > 50 → phase 1");
        check("T1.death_init",       boss_death_flag == 1'b0, "SPEC §10.3: hp != 0 → not dead");

        // ---- T6 + T7: HP decrement and saturate ----
        // 99 hits should bring HP to 0.
        // Verify a few intermediate values first.
        pulse_hit; #1;
        check("T6.hp_98", boss_hp == 7'd98, "SPEC §10.3: -1 on hit pulse");
        pulse_hit; #1;
        check("T6.hp_97", boss_hp == 7'd97, "SPEC §10.3: -1 on hit pulse");

        // ---- T2: phase transition at hp <= 50 ----
        // Drive HP down to 51 → still phase 1; one more pulse → phase 2.
        repeat (46) pulse_hit;  // 97-46 = 51
        #1;
        check("T2.hp_51",         boss_hp == 7'd51, "After 46 more hits, hp=51");
        check("T2.phase_at_51",   phase   == 1'b0,  "Q5: 51 > 50 → phase 1");
        pulse_hit; #1;
        check("T2.hp_50",         boss_hp == 7'd50, "After one more hit, hp=50");
        check("T2.phase_at_50",   phase   == 1'b1,  "Q5: 50 <= 50 → phase 2");

        // ---- T7 + T8 + T9: drive HP to 0 and check freeze ----
        repeat (50) pulse_hit;  // 50 → 0
        #1;
        check("T7.hp_zero",     boss_hp         == 7'd0, "After 50 more hits, hp=0");
        check("T8.death_flag",  boss_death_flag == 1'b1, "SPEC §10.3: hp==0 → death flag");
        // Extra hits should not underflow.
        pulse_hit; #1;
        check("T7.hp_saturate", boss_hp == 7'd0, "IMPL: saturate at 0, no underflow");

        // X position before tick.
        begin: t9_freeze
            reg [7:0] x_before;
            x_before = boss_x;
            pulse_game_tick; #1;
            check("T9.x_freeze_on_death", boss_x == x_before,
                  "IMPL: motion frozen when hp==0");
        end

        // -------------------------------------------------------------------
        // Re-reset and test motion behaviors with fresh HP
        // -------------------------------------------------------------------
        do_reset;

        // ---- T3: phase 1 bounce — first tick goes right by 2 ----
        // boss_x starts at 92, dir=0 (right), speed=2 → after one tick, x=94.
        pulse_game_tick; #1;
        check("T3.bounce_right_1", boss_x == 8'd94,
              "SPEC §10.3 phase 1 + IMPL speed=2");
        pulse_game_tick; #1;
        check("T3.bounce_right_2", boss_x == 8'd96,
              "Phase 1: continues +2 per tick");

        // ---- T4: drive boss_x to right edge, expect clamp + flip ----
        // From 96 → need 96+2*N = 184 → N=44. After 44 ticks: x=184.
        repeat (44) pulse_game_tick;
        #1;
        check("T4.right_clamp", boss_x == 8'd184, "IMPL: clamp at X_MAX=184");
        // One more tick: dir flipped, so we move LEFT by 2 → x=182.
        pulse_game_tick; #1;
        check("T4.dir_flipped", boss_x == 8'd182, "IMPL: dir flips at right edge");

        // -------------------------------------------------------------------
        // ---- T5: phase 2 tracking ----
        // Drive HP to 50 to enter phase 2. boss_x is somewhere mid-screen.
        // -------------------------------------------------------------------
        repeat (49) pulse_hit;  // 99 → 50
        #1;
        check("T5.phase2_active", phase == 1'b1, "After 49 hits, hp=50, phase=1");

        // Set player_x = 200 (clamp will pin to 184) and pulse ticks; boss_x
        // should advance toward player_x by 1 each tick.
        begin: t5_track_right
            reg [7:0] x_before;
            x_before = boss_x;
            player_x = 8'd200;  // clamp will limit
            pulse_game_tick; #1;
            check("T5.track_right_1", boss_x == (x_before + 8'd1),
                  "Phase 2 + IMPL speed=1: +1 toward larger player_x");
            pulse_game_tick; #1;
            check("T5.track_right_2", boss_x == (x_before + 8'd2),
                  "Phase 2 continues tracking");
        end

        // Now player_x = 0 → boss_x decrements by 1 per tick.
        begin: t5_track_left
            reg [7:0] x_before;
            x_before = boss_x;
            player_x = 8'd0;
            pulse_game_tick; #1;
            check("T5.track_left_1", boss_x == (x_before - 8'd1),
                  "Phase 2: -1 toward smaller player_x");
        end

        // -------------------------------------------------------------------
        $display("boss_controller_tb DONE: %0d passed, %0d failed", passes, errors);
        if (errors == 0) $display("boss_controller_tb: ALL PASS");
        else             $display("boss_controller_tb: FAIL");
        $finish;
    end

endmodule
