`timescale 1ns / 1ps
// collision — 24 bbox comparators + i-frame counter.
// Adapted from partner draft (Leyaa); rewritten to match SPEC §10.5
// (sequential interface, i-frames, canonical pulse names).
//
// IMPL DECISIONS:
//   - Reset polarity / clock: SPEC §1.2 / §1.1 (active-high sync, pixel_clk).
//     Partner draft was purely combinational with no clock; SPEC §10.5 +
//     Q8 require state for i-frames, so the module is now sequential.
//   - I-frame counter location: inside `collision` (Q8, locked default).
//     Counter width 7 bits (0..127) covers 120 (Q6 default). Decrements on
//     each game_tick while > 0; reset to IFRAME_RESET on each accepted hit.
//   - Output pulse semantics: SPEC §10.5 — `boss_hit_pulse` and
//     `player_hit_pulse` are single-cycle, asserted on the game_tick that
//     observes the collision. Outside of game_tick they read 0. Partner
//     draft had `player_hit` as a level — converted.
//   - hit_mask output: per-slot 8-bit despawn mask for player_bullet
//     (SPEC §10.5 + Q9 default). Asserted only on game_tick to avoid
//     premature despawns mid-frame.
//   - bb_hit_mask output: 16-bit per-slot despawn mask for boss_bullet.
//     ⚠ SPEC-extension: SPEC §10.5 doesn't formally export this, but
//     partner's boss_bullet contract takes a `hit_mask [15:0]` input, so
//     collision must source it. Asserted on game_tick only.
//   - Hitboxes — SPEC silent. Defaults from partner draft, flagged ⚠:
//        Player        : 4×4 centered at (player_x+6, player_y+6)
//        Boss          : 16×16 at (boss_x, boss_y) — full sprite
//        Player bullet : 4×8 at (pb_x, pb_y)
//        Boss bullet   : 6×6 at (bb_x, bb_y)
//   - 9-bit arithmetic on right/bottom edges to avoid 8-bit add overflow
//     (GOTCHAS §G16).
//   - Internal unpacked arrays for bullet positions; flat-bus inputs only
//     in the port list (CONVENTIONS §1, GOTCHAS §G9).
//   - No `initial` blocks (GOTCHAS §G14).
//
// ⚠ UNCERTAINTY:
//   - Hitbox dimensions (player 4×4, boss 16×16, pb 4×8, bb 6×6) are
//     implementation choices — SPEC §10.5 says only "24 bounding-box
//     comparators". Tunable post-playtest.
//
module collision (
    input  wire        pixel_clk,
    input  wire        reset,
    input  wire        game_tick,

    // Positions (SPEC §1.7)
    input  wire [7:0]  player_x,
    input  wire [7:0]  player_y,
    input  wire [7:0]  boss_x,
    input  wire [7:0]  boss_y,

    // Bullet flat buses (SPEC §1.7, §1.8)
    input  wire [63:0]  pb_x_flat,
    input  wire [63:0]  pb_y_flat,
    input  wire [7:0]   pb_active,
    input  wire [127:0] bb_x_flat,
    input  wire [127:0] bb_y_flat,
    input  wire [15:0]  bb_active,

    // Outputs (SPEC §10.5)
    output wire [7:0]  hit_mask,        // to player_bullet (SPEC §10.5)
    output wire [15:0] bb_hit_mask,     // to boss_bullet  (SPEC-extension)
    output wire        boss_hit_pulse,  // to boss_controller
    output wire        player_hit_pulse // to top.v / lives counter
);

    // ---------- localparams ----------
    localparam [6:0] IFRAME_RESET = 7'd120;     // Q6 default

    localparam [7:0] PLAYER_HIT_OFF = 8'd6;     // 4×4 center within 16×16 sprite
    localparam [7:0] PLAYER_HIT_W   = 8'd4;
    localparam [7:0] PLAYER_HIT_H   = 8'd4;
    localparam [7:0] BOSS_W         = 8'd16;
    localparam [7:0] BOSS_H         = 8'd16;
    localparam [7:0] PB_W           = 8'd4;
    localparam [7:0] PB_H           = 8'd8;
    localparam [7:0] BB_W           = 8'd6;
    localparam [7:0] BB_H           = 8'd6;

    // ---------- regs ----------
    reg [6:0] iframe_counter;

    // ---------- bullet array unpack ----------
    wire [7:0] pb_x [0:7];
    wire [7:0] pb_y [0:7];
    wire [7:0] bb_x [0:15];
    wire [7:0] bb_y [0:15];

    genvar gi;
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin: unpack_pb
            assign pb_x[gi] = pb_x_flat[gi*8 +: 8];
            assign pb_y[gi] = pb_y_flat[gi*8 +: 8];
        end
        for (gi = 0; gi < 16; gi = gi + 1) begin: unpack_bb
            assign bb_x[gi] = bb_x_flat[gi*8 +: 8];
            assign bb_y[gi] = bb_y_flat[gi*8 +: 8];
        end
    endgenerate

    // ---------- player hit center ----------
    wire [8:0] phit_x_lo = {1'b0, player_x} + {1'b0, PLAYER_HIT_OFF};
    wire [8:0] phit_y_lo = {1'b0, player_y} + {1'b0, PLAYER_HIT_OFF};
    wire [8:0] phit_x_hi = phit_x_lo + {1'b0, PLAYER_HIT_W};
    wire [8:0] phit_y_hi = phit_y_lo + {1'b0, PLAYER_HIT_H};

    // ---------- combinational hit detection ----------
    // pb_collide[i] = 1 if active player-bullet i overlaps boss
    wire [7:0]  pb_collide;
    wire [15:0] bb_collide;

    // 9-bit AABB overlap: a.lo < b.hi && b.lo < a.hi (both axes)
    generate
        for (gi = 0; gi < 8; gi = gi + 1) begin: pb_v_boss
            wire [8:0] bx_lo = {1'b0, boss_x};
            wire [8:0] by_lo = {1'b0, boss_y};
            wire [8:0] bx_hi = bx_lo + {1'b0, BOSS_W};
            wire [8:0] by_hi = by_lo + {1'b0, BOSS_H};
            wire [8:0] px_lo = {1'b0, pb_x[gi]};
            wire [8:0] py_lo = {1'b0, pb_y[gi]};
            wire [8:0] px_hi = px_lo + {1'b0, PB_W};
            wire [8:0] py_hi = py_lo + {1'b0, PB_H};

            assign pb_collide[gi] = pb_active[gi] &&
                                    (px_lo < bx_hi) && (bx_lo < px_hi) &&
                                    (py_lo < by_hi) && (by_lo < py_hi);
        end

        for (gi = 0; gi < 16; gi = gi + 1) begin: bb_v_player
            wire [8:0] bx_lo = {1'b0, bb_x[gi]};
            wire [8:0] by_lo = {1'b0, bb_y[gi]};
            wire [8:0] bx_hi = bx_lo + {1'b0, BB_W};
            wire [8:0] by_hi = by_lo + {1'b0, BB_H};

            assign bb_collide[gi] = bb_active[gi] &&
                                    (bx_lo  < phit_x_hi) && (phit_x_lo < bx_hi) &&
                                    (by_lo  < phit_y_hi) && (phit_y_lo < by_hi);
        end
    endgenerate

    // ---------- gated outputs (game_tick-pulsed) ----------
    wire iframe_idle    = (iframe_counter == 7'd0);
    wire any_pb_collide = |pb_collide;
    wire any_bb_collide = |bb_collide;

    assign hit_mask         = game_tick ? pb_collide : 8'd0;
    assign bb_hit_mask      = game_tick ? (bb_collide & {16{iframe_idle}}) : 16'd0;
    assign boss_hit_pulse   = game_tick & any_pb_collide;
    assign player_hit_pulse = game_tick & any_bb_collide & iframe_idle;
    // Rationale: bb_hit_mask is gated on iframe_idle so boss bullets aren't
    // despawned during invulnerability — they "pass through" the player
    // visually, which matches Touhou conventions.

    // ---------- i-frame counter ----------
    always @(posedge pixel_clk) begin
        if (reset) begin
            iframe_counter <= 7'd0;
        end else if (game_tick) begin
            if (any_bb_collide && iframe_idle)
                iframe_counter <= IFRAME_RESET;       // accepted hit
            else if (iframe_counter != 7'd0)
                iframe_counter <= iframe_counter - 7'd1;
        end
    end

endmodule
