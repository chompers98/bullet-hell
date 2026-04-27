`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// collision_tb.v — self-checking testbench for collision (SPEC §10.5, Q6, Q8).
//
// Coverage:
//   T1  Reset clears iframe_counter         — SPEC §1.2
//   T2  Outputs zero outside game_tick      — SPEC §10.5 pulse semantics
//   T3  PB hits boss → hit_mask + boss_hit_pulse  — SPEC §10.5
//   T4  Inactive PB ignored                  — IMPL: gated on pb_active
//   T5  Non-overlapping PB → no hit          — AABB correctness
//   T6  BB hits player → player_hit_pulse + bb_hit_mask  — SPEC §10.5
//   T7  I-frame suppression after hit        — SPEC §10.5 + Q6 (120 ticks)
//   T8  I-frame counter decrements per tick  — SPEC §10.5
//   T9  I-frame expiry → next hit registers  — SPEC §10.5
//   T10 Multiple PB simultaneous             — IMPL: independent comparators
//
// Timing pattern: each tick is driven manually so we can sample the
// combinational pulse outputs while game_tick is high, then check the
// post-posedge state of iframe_counter on the way down.
// -----------------------------------------------------------------------------

module collision_tb;

    reg          pixel_clk = 1'b0;
    reg          reset     = 1'b1;
    reg          game_tick = 1'b0;

    reg  [7:0]   player_x  = 8'd92;
    reg  [7:0]   player_y  = 8'd126;
    reg  [7:0]   boss_x    = 8'd92;
    reg  [7:0]   boss_y    = 8'd8;

    reg  [63:0]  pb_x_flat = 64'd0;
    reg  [63:0]  pb_y_flat = 64'd0;
    reg  [7:0]   pb_active = 8'd0;

    reg  [127:0] bb_x_flat = 128'd0;
    reg  [127:0] bb_y_flat = 128'd0;
    reg  [15:0]  bb_active = 16'd0;

    wire [7:0]   hit_mask;
    wire [15:0]  bb_hit_mask;
    wire         boss_hit_pulse;
    wire         player_hit_pulse;

    always #20 pixel_clk = ~pixel_clk;

    collision dut (
        .pixel_clk       (pixel_clk),
        .reset           (reset),
        .game_tick       (game_tick),
        .player_x        (player_x),
        .player_y        (player_y),
        .boss_x          (boss_x),
        .boss_y          (boss_y),
        .pb_x_flat       (pb_x_flat),
        .pb_y_flat       (pb_y_flat),
        .pb_active       (pb_active),
        .bb_x_flat       (bb_x_flat),
        .bb_y_flat       (bb_y_flat),
        .bb_active       (bb_active),
        .hit_mask        (hit_mask),
        .bb_hit_mask     (bb_hit_mask),
        .boss_hit_pulse  (boss_hit_pulse),
        .player_hit_pulse(player_hit_pulse)
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

    // Drive game_tick high for exactly one pixel_clk cycle. Sample outputs
    // while high (returned via output args). Counter post-tick is observable
    // after this task returns.
    task tick_and_sample;
        output [7:0]  hm;
        output [15:0] bbm;
        output        bhp;
        output        php;
        begin
            @(negedge pixel_clk);  game_tick = 1'b1;
            #1;
            hm  = hit_mask;
            bbm = bb_hit_mask;
            bhp = boss_hit_pulse;
            php = player_hit_pulse;
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

    task set_pb;
        input integer slot;
        input [7:0]   x;
        input [7:0]   y;
        begin
            pb_x_flat[slot*8 +: 8] = x;
            pb_y_flat[slot*8 +: 8] = y;
            pb_active[slot]        = 1'b1;
        end
    endtask

    task clear_pb;
        input integer slot;
        begin pb_active[slot] = 1'b0; end
    endtask

    task set_bb;
        input integer slot;
        input [7:0]   x;
        input [7:0]   y;
        begin
            bb_x_flat[slot*8 +: 8] = x;
            bb_y_flat[slot*8 +: 8] = y;
            bb_active[slot]        = 1'b1;
        end
    endtask

    task clear_bb;
        input integer slot;
        begin bb_active[slot] = 1'b0; end
    endtask

    // Sampled output bindings used across tests.
    reg [7:0]  s_hm;
    reg [15:0] s_bbm;
    reg        s_bhp, s_php;

    initial begin
        $dumpfile("collision_tb.vcd");
        $dumpvars(0, collision_tb);

        do_reset;

        // ---- T1: Reset state ----
        check("T1.iframe_zero", dut.iframe_counter == 7'd0,
              "SPEC §1.2 reset clears iframe_counter");

        // ---- T2: Outputs zero outside game_tick ----
        boss_x = 8'd50; boss_y = 8'd8;
        set_pb(0, 8'd52, 8'd10);    // overlapping
        #5;
        check("T2.hit_mask_idle",     hit_mask         == 8'd0,
              "SPEC §10.5: hit_mask zero outside game_tick");
        check("T2.boss_pulse_idle",   boss_hit_pulse   == 1'b0, "SPEC §10.5");
        check("T2.bb_hit_mask_idle",  bb_hit_mask      == 16'd0, "SPEC §10.5");
        check("T2.player_pulse_idle", player_hit_pulse == 1'b0, "SPEC §10.5");

        // ---- T3: PB → boss collision ----
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T3.hit_mask_slot0", s_hm[0]  == 1'b1, "SPEC §10.5: PB slot 0 hit");
        check("T3.boss_hit_pulse", s_bhp    == 1'b1, "SPEC §10.5: boss_hit_pulse");
        // Pulse fell at end of tick (give combinational propagation a delta).
        #1;
        check("T3.pulse_falls",    boss_hit_pulse == 1'b0,
              "SPEC §10.5: single-cycle pulse");

        // ---- T4: inactive PB ----
        clear_pb(0);
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T4.inactive_pb", s_bhp == 1'b0, "IMPL: gated on pb_active");

        // ---- T5: non-overlapping PB ----
        set_pb(1, 8'd0, 8'd140);
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T5.no_overlap", s_bhp == 1'b0, "AABB: non-overlap → no hit");
        clear_pb(1);

        // ---- T6: BB → player collision; sample during the high pulse ----
        do_reset;
        player_x = 8'd92; player_y = 8'd126;
        set_bb(0, 8'd96, 8'd130);   // overlaps with player hitbox at (98,132)+(4,4)
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T6.player_hit_pulse",  s_php   == 1'b1,
              "SPEC §10.5: player_hit_pulse on accepted BB hit");
        check("T6.bb_hit_mask_slot0", s_bbm[0] == 1'b1,
              "IMPL bb_hit_mask: BB slot 0 collided");

        // After the tick, iframe_counter should be IFRAME_RESET = 120.
        check("T7.iframe_set", dut.iframe_counter == 7'd120,
              "SPEC §10.5 + Q6: iframe_counter ← 120 on accepted hit");

        // ---- T7: subsequent hit suppressed by i-frames ----
        // BB still overlapping. Next tick: pulse must NOT fire.
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T7.pulse_suppressed",   s_php  == 1'b0,
              "SPEC §10.5: player_hit_pulse suppressed while iframe>0");
        check("T7.bb_mask_suppressed", s_bbm[0] == 1'b0,
              "IMPL: bb_hit_mask gated on iframe_idle");
        // ---- T8: counter decrement ----
        // After T6 tick, counter=120. After T7 tick (no hit, counter>0),
        // counter decremented → 119.
        check("T8.iframe_119", dut.iframe_counter == 7'd119,
              "SPEC §10.5: -1 per game_tick when counter > 0");

        // 30 more no-op ticks (we keep BB overlapping but suppression continues)
        repeat (30) tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T8.iframe_89", dut.iframe_counter == 7'd89,
              "SPEC §10.5: 30 ticks → 119-30 = 89");

        // ---- T9: drain remaining 89 ticks → counter == 0 → next hit registers ----
        repeat (89) tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T9.iframe_zero_again", dut.iframe_counter == 7'd0,
              "SPEC §10.5: counter reaches 0");

        // BB still overlapping. Next tick should fire pulse.
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T9.next_hit_registers", s_php == 1'b1,
              "SPEC §10.5: hit registers when counter == 0");

        // ---- T10: multiple PB hits same tick ----
        do_reset;
        clear_bb(0);
        boss_x = 8'd50; boss_y = 8'd8;
        set_pb(0, 8'd52, 8'd10);
        set_pb(3, 8'd55, 8'd14);
        set_pb(7, 8'd200, 8'd140);    // 200 - 50 = 150 → far away
        tick_and_sample(s_hm, s_bbm, s_bhp, s_php);
        check("T10.slot0_hit",  s_hm[0] == 1'b1, "Slot 0 overlaps boss");
        check("T10.slot3_hit",  s_hm[3] == 1'b1, "Slot 3 overlaps boss");
        check("T10.slot7_miss", s_hm[7] == 1'b0, "Slot 7 far away");
        check("T10.boss_pulse", s_bhp   == 1'b1, "boss_hit_pulse on any hit");

        $display("collision_tb DONE: %0d passed, %0d failed", passes, errors);
        if (errors == 0) $display("collision_tb: ALL PASS");
        else             $display("collision_tb: FAIL");
        $finish;
    end

endmodule
