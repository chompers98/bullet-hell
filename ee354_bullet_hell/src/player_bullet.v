`timescale 1ns / 1ps
// player_bullet.v — pool of 8 player bullets; spawn, advance, despawn.
//
// IMPL DECISIONS:
//   - Per-tick order: advance -> despawn -> spawn (SPEC §10.2.2). Step 3
//     reads post-step-2 state so a slot despawned this tick is immediately
//     reusable. Implemented in a single combinational always @* block that
//     produces *_next signals; a separate sequential always @(posedge clk)
//     commits them. Blocking assigns in combinational block only; non-blocking
//     in sequential block only (CONVENTIONS §7).
//   - Priority encoder: LSB-first scan over pb_active_next (SPEC §10.2.5
//     "lowest-index-first"). Unrolled if/else-if chain with a `found` guard,
//     8 slots.
//   - game_tick sampling: single-cycle clock enable on pixel_clk (GOTCHAS
//     §G15). State holds when game_tick is low (combinational block
//     reproduces current state so the non-blocking commit is a no-op).
//   - shoot_pulse sampling: latched into shoot_latch every pixel_clk per the
//     SPEC §10.2.3 boilerplate (reset / game_tick / shoot_pulse priority
//     chain). Multi-pulse collapse and pool-full clear both follow from the
//     latch resetting on every game_tick.
//   - Internal state: pb_x/pb_y as 8 separate 8-bit regs rather than an
//     unpacked array — keeps the reset branch and output packing explicit
//     and avoids any risk of synthesis tool array-handling quirks.
//   - hit_mask semantics: bit i high on the game_tick cycle forces
//     pb_active_next[i] = 0 in step 2 (SPEC §10.2.1 Q9 default; Leyaa-owned,
//     flagged inline at the port).
//
module player_bullet (
    input  wire        pixel_clk,     // 25 MHz (SPEC §1.1)
    input  wire        reset,         // active-high sync (SPEC §1.2)

    input  wire        game_tick,     // single-cycle pulse (GOTCHAS §G15)
    input  wire        shoot_pulse,   // single-cycle, from player_controller
    input  wire [7:0]  player_x,      // logical FB coords (SPEC §1.3)
    input  wire [7:0]  player_y,

    // hit_mask: bit i high on game_tick -> despawn slot i (SPEC §10.2.2
    // step 2). Q9 default per SPEC §10.2.1 — owner: Leyaa. If Q9 resolves
    // to a different encoding (e.g. level-held, multi-cycle latched), this
    // module must change.
    input  wire [7:0]  hit_mask,

    output wire [63:0] pb_x_flat,     // SPEC §1.7, §1.8 packing
    output wire [63:0] pb_y_flat,
    output wire [7:0]  pb_active
);

    // ---------- State registers ----------
    reg [7:0] pb_x0, pb_x1, pb_x2, pb_x3, pb_x4, pb_x5, pb_x6, pb_x7;
    reg [7:0] pb_y0, pb_y1, pb_y2, pb_y3, pb_y4, pb_y5, pb_y6, pb_y7;
    reg [7:0] pb_active_r;
    reg       shoot_latch;

    // ---------- Combinational next-state ----------
    reg [7:0] pb_x0_n, pb_x1_n, pb_x2_n, pb_x3_n,
              pb_x4_n, pb_x5_n, pb_x6_n, pb_x7_n;
    reg [7:0] pb_y0_n, pb_y1_n, pb_y2_n, pb_y3_n,
              pb_y4_n, pb_y5_n, pb_y6_n, pb_y7_n;
    reg [7:0] pb_act_n;
    reg       found;

    // ---------- Output packing (SPEC §10.2.4) ----------
    assign pb_x_flat = {pb_x7, pb_x6, pb_x5, pb_x4,
                        pb_x3, pb_x2, pb_x1, pb_x0};
    assign pb_y_flat = {pb_y7, pb_y6, pb_y5, pb_y4,
                        pb_y3, pb_y2, pb_y1, pb_y0};
    assign pb_active = pb_active_r;

    // ---------- Combinational: compute *_next ----------
    // Defaults = current state (CONVENTIONS §6, GOTCHAS §G18 — no latches).
    // If game_tick is low, *_next == current state and the sequential commit
    // is a no-op.
    always @* begin
        // Defaults
        pb_x0_n = pb_x0; pb_x1_n = pb_x1; pb_x2_n = pb_x2; pb_x3_n = pb_x3;
        pb_x4_n = pb_x4; pb_x5_n = pb_x5; pb_x6_n = pb_x6; pb_x7_n = pb_x7;
        pb_y0_n = pb_y0; pb_y1_n = pb_y1; pb_y2_n = pb_y2; pb_y3_n = pb_y3;
        pb_y4_n = pb_y4; pb_y5_n = pb_y5; pb_y6_n = pb_y6; pb_y7_n = pb_y7;
        pb_act_n = pb_active_r;
        found    = 1'b0;

        if (game_tick) begin
            // ---- Step 1: advance (SPEC §10.2.2 step 1; N=2) ----
            if (pb_active_r[0]) pb_y0_n = pb_y0 - 8'd2;
            if (pb_active_r[1]) pb_y1_n = pb_y1 - 8'd2;
            if (pb_active_r[2]) pb_y2_n = pb_y2 - 8'd2;
            if (pb_active_r[3]) pb_y3_n = pb_y3 - 8'd2;
            if (pb_active_r[4]) pb_y4_n = pb_y4 - 8'd2;
            if (pb_active_r[5]) pb_y5_n = pb_y5 - 8'd2;
            if (pb_active_r[6]) pb_y6_n = pb_y6 - 8'd2;
            if (pb_active_r[7]) pb_y7_n = pb_y7 - 8'd2;

            // ---- Step 2: despawn (SPEC §10.2.2 step 2) ----
            // Despawn condition evaluated against pb_y_next (post-advance).
            if (pb_act_n[0] && ((pb_y0_n >= 8'd150) || hit_mask[0])) pb_act_n[0] = 1'b0;
            if (pb_act_n[1] && ((pb_y1_n >= 8'd150) || hit_mask[1])) pb_act_n[1] = 1'b0;
            if (pb_act_n[2] && ((pb_y2_n >= 8'd150) || hit_mask[2])) pb_act_n[2] = 1'b0;
            if (pb_act_n[3] && ((pb_y3_n >= 8'd150) || hit_mask[3])) pb_act_n[3] = 1'b0;
            if (pb_act_n[4] && ((pb_y4_n >= 8'd150) || hit_mask[4])) pb_act_n[4] = 1'b0;
            if (pb_act_n[5] && ((pb_y5_n >= 8'd150) || hit_mask[5])) pb_act_n[5] = 1'b0;
            if (pb_act_n[6] && ((pb_y6_n >= 8'd150) || hit_mask[6])) pb_act_n[6] = 1'b0;
            if (pb_act_n[7] && ((pb_y7_n >= 8'd150) || hit_mask[7])) pb_act_n[7] = 1'b0;

            // ---- Step 3: spawn (SPEC §10.2.2 step 3; §10.2.5) ----
            // LSB-first scan over pb_act_n (post-despawn). shoot_latch clears
            // unconditionally via the separate latch always-block below.
            if (shoot_latch) begin
                if (!found && !pb_act_n[0]) begin
                    pb_act_n[0] = 1'b1;
                    pb_x0_n = player_x;
                    pb_y0_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[1]) begin
                    pb_act_n[1] = 1'b1;
                    pb_x1_n = player_x;
                    pb_y1_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[2]) begin
                    pb_act_n[2] = 1'b1;
                    pb_x2_n = player_x;
                    pb_y2_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[3]) begin
                    pb_act_n[3] = 1'b1;
                    pb_x3_n = player_x;
                    pb_y3_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[4]) begin
                    pb_act_n[4] = 1'b1;
                    pb_x4_n = player_x;
                    pb_y4_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[5]) begin
                    pb_act_n[5] = 1'b1;
                    pb_x5_n = player_x;
                    pb_y5_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[6]) begin
                    pb_act_n[6] = 1'b1;
                    pb_x6_n = player_x;
                    pb_y6_n = player_y - 8'd16;
                    found   = 1'b1;
                end
                if (!found && !pb_act_n[7]) begin
                    pb_act_n[7] = 1'b1;
                    pb_x7_n = player_x;
                    pb_y7_n = player_y - 8'd16;
                    found   = 1'b1;
                end
            end
        end
    end

    // ---------- Sequential: shoot_pulse latch (SPEC §10.2.3 verbatim shape) ----------
    always @(posedge pixel_clk) begin
        if (reset)
            shoot_latch <= 1'b0;
        else if (game_tick)
            shoot_latch <= 1'b0;
        else if (shoot_pulse)
            shoot_latch <= 1'b1;
    end

    // ---------- Sequential: commit bullet state ----------
    always @(posedge pixel_clk) begin
        if (reset) begin
            // SPEC §10.2.6
            pb_x0 <= 8'd0; pb_x1 <= 8'd0; pb_x2 <= 8'd0; pb_x3 <= 8'd0;
            pb_x4 <= 8'd0; pb_x5 <= 8'd0; pb_x6 <= 8'd0; pb_x7 <= 8'd0;
            pb_y0 <= 8'd0; pb_y1 <= 8'd0; pb_y2 <= 8'd0; pb_y3 <= 8'd0;
            pb_y4 <= 8'd0; pb_y5 <= 8'd0; pb_y6 <= 8'd0; pb_y7 <= 8'd0;
            pb_active_r <= 8'd0;
        end else begin
            // When game_tick is low, *_n == current state, so these commits
            // are functional no-ops.
            pb_x0 <= pb_x0_n; pb_x1 <= pb_x1_n; pb_x2 <= pb_x2_n; pb_x3 <= pb_x3_n;
            pb_x4 <= pb_x4_n; pb_x5 <= pb_x5_n; pb_x6 <= pb_x6_n; pb_x7 <= pb_x7_n;
            pb_y0 <= pb_y0_n; pb_y1 <= pb_y1_n; pb_y2 <= pb_y2_n; pb_y3 <= pb_y3_n;
            pb_y4 <= pb_y4_n; pb_y5 <= pb_y5_n; pb_y6 <= pb_y6_n; pb_y7 <= pb_y7_n;
            pb_active_r <= pb_act_n;
        end
    end

endmodule
