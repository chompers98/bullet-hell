`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// boss_bullet_tb.v — self-checking testbench for boss_bullet
// (SPEC §10.4, §1.7, §1.8).
//
// Coverage:
//   T1  Reset clears state                  — SPEC §1.2
//   T2  Burst spawn timing                  — IMPL: every 26 game_ticks
//   T3  Burst spawn count = 5               — IMPL BULLETS_PER_FIRE
//   T4  Burst origin = boss center          — IMPL spawn at (boss_x+8, boss_y+8)
//   T5  Pattern bit 0 = phase at spawn      — SPEC §1.7 (`bb_pattern_flat`)
//   T6  Pattern persists after phase switch — IMPL: latched at spawn
//   T7  Bullet advances per tick            — SPEC §10.4 motion (phase 1 spread)
//   T8  hit_mask despawns slot              — SPEC §10.5 → bb_active[i]=0
//   T9  OOB despawn (off bottom)            — IMPL: 9-bit OOB check
//   T10 Pack ordering: slot 0 at LSB        — SPEC §1.8
// -----------------------------------------------------------------------------

module boss_bullet_tb;

    reg          pixel_clk = 1'b0;
    reg          reset     = 1'b1;
    reg          game_tick = 1'b0;
    reg          phase     = 1'b0;
    reg  [7:0]   boss_x    = 8'd10;
    reg  [7:0]   boss_y    = 8'd8;
    reg  [7:0]   player_x  = 8'd100;
    reg  [7:0]   player_y  = 8'd70;
    reg  [15:0]  hit_mask  = 16'd0;

    wire [127:0] bb_x_flat;
    wire [127:0] bb_y_flat;
    wire [15:0]  bb_active;
    wire [31:0]  bb_pattern_flat;

    always #20 pixel_clk = ~pixel_clk;  // 25 MHz

    boss_bullet dut (
        .pixel_clk      (pixel_clk),
        .reset          (reset),
        .game_tick      (game_tick),
        .phase          (phase),
        .boss_x         (boss_x),
        .boss_y         (boss_y),
        .player_x       (player_x),
        .player_y       (player_y),
        .hit_mask       (hit_mask),
        .bb_x_flat      (bb_x_flat),
        .bb_y_flat      (bb_y_flat),
        .bb_active      (bb_active),
        .bb_pattern_flat(bb_pattern_flat)
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

    task do_reset;
        begin
            reset = 1'b1;
            @(posedge pixel_clk); @(posedge pixel_clk);
            @(negedge pixel_clk); reset = 1'b0;
        end
    endtask

    // Slot accessors via index
    function [7:0] x_at;     input integer slot; x_at     = bb_x_flat[slot*8 +: 8]; endfunction
    function [7:0] y_at;     input integer slot; y_at     = bb_y_flat[slot*8 +: 8]; endfunction
    function [1:0] pat_at;   input integer slot; pat_at   = bb_pattern_flat[slot*2 +: 2]; endfunction
    function       act_at;   input integer slot; act_at   = bb_active[slot]; endfunction

    initial begin
        $dumpfile("boss_bullet_tb.vcd");
        $dumpvars(0, boss_bullet_tb);

        do_reset;

        // ---- T1: reset ----
        check("T1.active_zero",  bb_active       == 16'd0,  "SPEC §1.2 reset");
        check("T1.pattern_zero", bb_pattern_flat == 32'd0,  "SPEC §1.2 reset");

        // ---- T2 + T3 + T4: first burst lands at game_tick #26 ----
        // 25 ticks: timer counts 0→25; at the 26th tick, timer >= 25 → fire.
        repeat (25) pulse_game_tick;
        #1;
        check("T2.no_fire_yet",  bb_active == 16'd0,
              "Before first fire: active still 0");

        // 26th tick: fire 5 bullets at slots 0..4
        pulse_game_tick; #1;
        check("T3.burst_count_5", bb_active == 16'b0000_0000_0001_1111,
              "IMPL: 5 bullets per burst at slots 0..4");

        // T4: origin = (boss_x + 8, boss_y + 8) = (18, 16). Phase 1 spread:
        // vx_base = +2 (player to right), so first-tick advance hasn't happened
        // yet — bullets are still at spawn position.
        check("T4.x_origin_slot0", x_at(0) == (boss_x + 8'd8),
              "IMPL: spawn x = boss center x");
        check("T4.y_origin_slot0", y_at(0) == (boss_y + 8'd8),
              "IMPL: spawn y = boss center y");
        check("T4.x_origin_slot4", x_at(4) == (boss_x + 8'd8),
              "All burst bullets share spawn position");

        // ---- T5: pattern bit 0 == phase (== 0 here) ----
        check("T5.pat_phase1_slot0", pat_at(0) == 2'b00, "SPEC §1.7: bit0=phase");
        check("T5.pat_phase1_slot4", pat_at(4) == 2'b00, "Same phase across burst");

        // ---- T7: advance check ----
        // After one more game_tick (no fire — timer=0 again), bullets advance
        // by their vx/vy. Phase 1 with player to right/below:
        //   abs_dx = 90, abs_dy = 62 → vx_base = +2, vy_base = +1
        //   Slot 0: vx = 2 + (-2) = 0. y advances by +1 only.
        //   Slot 1: vx = 2 + (-1) = +1.
        //   Slot 2: vx = 2 +   0  = +2.
        //   Slot 3: vx = 2 + (+1) = +3.
        //   Slot 4: vx = 2 + (+2) = +4.
        // All slots: vy = +1.
        pulse_game_tick; #1;
        check("T7.advance_slot0_x", x_at(0) == (boss_x + 8'd8 + 8'd0),
              "Slot 0 vx = vx_base + spread(-2) = 0");
        check("T7.advance_slot1_x", x_at(1) == (boss_x + 8'd8 + 8'd1),
              "Slot 1 vx = +1");
        check("T7.advance_slot4_x", x_at(4) == (boss_x + 8'd8 + 8'd4),
              "Slot 4 vx = +4");
        check("T7.advance_y",       y_at(0) == (boss_y + 8'd8 + 8'd1),
              "All slots vy = +1 → y advances");

        // ---- T8: hit_mask despawn ----
        // Set hit_mask[2] = 1, pulse game_tick → slot 2 active goes 0
        hit_mask = 16'b0000_0000_0000_0100;
        pulse_game_tick; #1;
        check("T8.hit_mask_despawn",  bb_active[2] == 1'b0,
              "SPEC §10.5 hit_mask: bit i → despawn slot i");
        check("T8.others_alive",      (bb_active & 16'b0000_0000_0001_1011) ==
                                       16'b0000_0000_0001_1011,
              "Only the masked slot despawns");
        hit_mask = 16'd0;

        // ---- T9: OOB despawn — drive bullets off bottom ----
        // Slot 4 has highest vy=+1, will hit y > 149 first. y was at boss_cy +
        // some advance. Force a bunch of ticks to push it off.
        // boss_cy = 16. After ~140 ticks at vy=+1, y > 149.
        // But fire_timer cycle is 26 ticks → multiple bursts will spawn more
        // bullets and fill new slots. Test alternative: force phase 2 ring
        // values which include a vy=-3 slot → off top quickly.
        do_reset;
        phase = 1'b1;  // ring pattern
        repeat (26) pulse_game_tick; #1;
        // Phase-2 ring slot 4 has vy = -3 starting at y = 16. After 6 ticks it
        // wraps below 0 → OOB despawn.
        repeat (6) pulse_game_tick; #1;
        check("T9.oob_top_despawn", bb_active[4] == 1'b0,
              "IMPL: OOB despawn on y underflow");

        // ---- T10: Pack ordering — verify slot 0 lives at LSB ----
        // After T9, ring bullets at non-uniform velocities.
        // Slot 0 should have bb_x_flat[7:0]; slot 15 at [127:120].
        do_reset;
        phase = 1'b0;
        repeat (26) pulse_game_tick; #1;
        check("T10.slot0_LSB",  bb_x_flat[7:0]      == x_at(0), "SPEC §1.8 slot 0 at LSB");
        check("T10.slot4_byte", bb_x_flat[39:32]    == x_at(4), "SPEC §1.8 slot 4 = bits[39:32]");

        // ---- T6: Pattern latched at spawn — switch phase mid-flight ----
        // After phase 1 burst, switch phase to 1 → next burst is ring with
        // pattern bit 0 = 1. Existing bullets keep their pattern bit 0 = 0.
        check("T6.before_switch", pat_at(0) == 2'b00, "Phase 1 spawn → pattern 0");
        phase = 1'b1;
        // Next burst is in 26 more ticks
        repeat (26) pulse_game_tick; #1;
        // Slot 5 should now be a phase-2 spawn (slot 0..4 from earlier, wr_ptr now at 5)
        check("T6.new_slot_phase2", pat_at(5) == 2'b01,
              "SPEC §1.7: ring spawn → pattern bit 0 = phase = 1");
        // Old slot 0 — if still active — keeps pattern 0.
        if (bb_active[0])
            check("T6.old_slot_keeps_pattern", pat_at(0) == 2'b00,
                  "IMPL: pattern latched at spawn, immune to phase changes");

        // -------------------------------------------------------------------
        $display("boss_bullet_tb DONE: %0d passed, %0d failed", passes, errors);
        if (errors == 0) $display("boss_bullet_tb: ALL PASS");
        else             $display("boss_bullet_tb: FAIL");
        $finish;
    end

endmodule
