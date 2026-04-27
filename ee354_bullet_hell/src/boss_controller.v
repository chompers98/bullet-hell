`timescale 1ns / 1ps
// boss_controller — boss patrol + HP, two-phase pattern toggle.
// Adapted from partner draft (Leyaa); rewritten to match SPEC §10.3 +
// canonical signal widths (SPEC §1.7).
//
// IMPL DECISIONS:
//   - Reset polarity: active-high synchronous (SPEC §1.2 / GOTCHAS §G5).
//   - Clock: single `pixel_clk` domain (SPEC §1.1 / GOTCHAS §G12).
//   - HP width: 7-bit, scale 0..99 (SPEC §1.7, Q5). Reduced from partner
//     draft's 27-bit/0..99,999,999 — that scale doesn't match the SPEC
//     contract or the HUD's 2-digit display.
//   - HP decrement: by 1 on each `boss_hit_pulse` (SPEC §10.3 "decrement
//     on hit pulse" — singular). Switched from partner draft's
//     popcount-of-mask. The hit-pulse comes from collision (SPEC §10.5,
//     `boss_hit_pulse = | hit_mask`).
//   - Phase: `phase = (boss_hp <= 50)` per Q5 (locked default). Single
//     bit; pattern selection is the boss_bullet's responsibility.
//   - Phase 1 motion: bounce L↔R at 2 px/game_tick. SPEC silent on speed
//     (§10.3 says "Boss patrol along top of screen"); 2 px matches the
//     partner draft and gives ~92 px traversal in ~1 s at 60 Hz —
//     visually appropriate.
//   - Phase 2 motion: track player_x at 1 px/game_tick. SPEC silent;
//     partner draft. Slower than Phase 1 because aimed bullets compensate.
//   - X bounds: clamp to [0, 184] (200 - 16-px sprite). Same convention as
//     player_controller (SPEC §10.1 L543).
//   - Y position: fixed at 8'd8. SPEC §10.3 says "top of screen" with no
//     specific value; matches `top.v` hardcoded boss_y for Week 2-A.
//   - Direction-flip behavior at the bouncing wall: pre-clamp the position
//     and reverse direction next tick. Same as partner draft.
//   - On death (hp == 0): position freezes (no further x updates), HP
//     stays at 0. SPEC silent on death state; freezing is the safe default
//     until top.v / collision define an end-of-game flow.
//   - boss_death_flag asserted (level) when boss_hp == 0, per SPEC §10.3.
//   - No `initial` blocks (GOTCHAS §G14).
//
module boss_controller (
    input  wire        pixel_clk,         // 25 MHz (SPEC §1.1)
    input  wire        reset,             // active-high sync (SPEC §1.2)
    input  wire        game_tick,         // single-cycle pulse (GOTCHAS §G15)

    input  wire [7:0]  player_x,          // for phase 2 tracking
    input  wire        boss_hit_pulse,    // single-cycle, from collision (SPEC §10.5)

    output reg  [7:0]  boss_x,            // logical FB coords, 0..184
    output wire [7:0]  boss_y,            // fixed at Y_POS
    output wire [6:0]  boss_hp,           // SPEC §1.7: 0..99
    output wire        phase,             // 0 = phase 1, 1 = phase 2 (Q5)
    output wire        boss_death_flag    // 1 when boss_hp == 0
);

    // ---------- localparams ----------
    localparam SPRITE_SIZE  = 8'd16;
    localparam X_INIT       = 8'd92;
    localparam Y_POS        = 8'd8;
    localparam X_MAX        = 8'd184;        // 200 - 16
    localparam SPEED_BOUNCE = 8'd2;          // phase 1
    localparam SPEED_TRACK  = 8'd1;          // phase 2
    localparam HP_MAX       = 7'd99;
    localparam HP_PHASE2    = 7'd50;         // Q5 — toggle at hp <= 50

    // ---------- regs ----------
    reg [6:0] boss_hp_r;
    reg       dir_r;       // phase 1 only: 0 = moving right, 1 = moving left

    // ---------- combinational outputs ----------
    assign boss_y          = Y_POS;
    assign boss_hp         = boss_hp_r;
    assign phase           = (boss_hp_r <= HP_PHASE2);
    assign boss_death_flag = (boss_hp_r == 7'd0);

    // ---------- sequential ----------
    // One always-block per state group. boss_x update depends on phase, dir,
    // and player_x; boss_hp on boss_hit_pulse; dir flips at X bounds in phase 1.
    always @(posedge pixel_clk) begin
        if (reset) begin
            boss_x    <= X_INIT;
            boss_hp_r <= HP_MAX;
            dir_r     <= 1'b0;     // start moving right
        end else begin
            // ---- HP decrement ----
            // SPEC §10.3: decrement on hit pulse. Saturate at 0.
            if (boss_hit_pulse && boss_hp_r != 7'd0)
                boss_hp_r <= boss_hp_r - 7'd1;

            // ---- X motion (gated on game_tick) ----
            if (game_tick && boss_hp_r != 7'd0) begin
                if (!phase) begin
                    // Phase 1: bounce
                    if (!dir_r) begin
                        // moving right
                        if (boss_x + SPEED_BOUNCE >= X_MAX) begin
                            boss_x <= X_MAX;
                            dir_r  <= 1'b1;
                        end else begin
                            boss_x <= boss_x + SPEED_BOUNCE;
                        end
                    end else begin
                        // moving left
                        if (boss_x <= SPEED_BOUNCE) begin
                            boss_x <= 8'd0;
                            dir_r  <= 1'b0;
                        end else begin
                            boss_x <= boss_x - SPEED_BOUNCE;
                        end
                    end
                end else begin
                    // Phase 2: track player_x at 1 px/tick, clamped to bounds
                    if (boss_x < player_x) begin
                        if (boss_x + SPEED_TRACK <= X_MAX)
                            boss_x <= boss_x + SPEED_TRACK;
                        else
                            boss_x <= X_MAX;
                    end else if (boss_x > player_x) begin
                        if (boss_x >= SPEED_TRACK)
                            boss_x <= boss_x - SPEED_TRACK;
                        else
                            boss_x <= 8'd0;
                    end
                    // boss_x == player_x: hold (default)
                end
            end
        end
    end

endmodule
