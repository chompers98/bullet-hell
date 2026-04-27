`timescale 1ns / 1ps
// boss_bullet — pool of 16 boss bullets; spawn, advance, despawn.
// Adapted from partner draft (Leyaa); rewritten to match SPEC §10.4 +
// canonical packing (SPEC §1.7, §1.8) — adds the missing
// `bb_pattern_flat` output that the renderer requires.
//
// IMPL DECISIONS:
//   - Reset polarity / clock: SPEC §1.2 / §1.1 (active-high sync, pixel_clk).
//   - Per-tick order: advance → hit_mask despawn → spawn (SPEC §10.4 mirror
//     of §10.2.2). State held when game_tick is low.
//   - 16-slot pool: stored as unpacked arrays (`reg [7:0] bb_x [0:15]`,
//     etc.). Output flat-bus packing per SPEC §1.8 via a generate-for
//     `assign bus[i*W +: W] = arr[i]` chain (slot 0 at LSB).
//   - bb_pattern_flat output: 16×2-bit packed bus per SPEC §1.7. Bit 0 of
//     each 2-bit slot = phase at spawn time. Latched at spawn so a bullet
//     fired in phase 1 keeps its yellow sprite even after the boss
//     transitions to phase 2 mid-flight.
//   - Spawn strategy: round-robin write pointer, 5 bullets per burst,
//     fire interval = 25 game_ticks (~0.42 s @ 60 Hz). Overwrites in-flight
//     bullets at slot wrap, but at the timing above the oldest bullets
//     have left the screen by then.
//   - Phase 1 (spread): aim toward player using octant-vx/vy approximation,
//     then add per-bullet spread offset {-2,-1,0,+1,+2} on vx.
//   - Phase 2 (ring): 5-bullet ring at 72° spacing, speed 3. Vector table
//     hardcoded.
//   - Out-of-bounds detection: 9-bit add catches wrap on both add (bit 8)
//     and subtract (sign extension); also clamp to [0,199] / [0,149]
//     (logical FB extents per SPEC §1.6).
//   - hit_mask semantics: bit i high on game_tick → despawn slot i this
//     tick (collision-owned, SPEC §10.5).
//   - No `initial` blocks (GOTCHAS §G14).
//
module boss_bullet (
    input  wire        pixel_clk,
    input  wire        reset,
    input  wire        game_tick,

    input  wire        phase,           // 0 = phase 1 spread, 1 = phase 2 ring (Q5)
    input  wire [7:0]  boss_x,
    input  wire [7:0]  boss_y,
    input  wire [7:0]  player_x,        // for phase 1 aiming
    input  wire [7:0]  player_y,

    input  wire [15:0] hit_mask,        // SPEC §10.5: bit i → despawn slot i

    output wire [127:0] bb_x_flat,      // SPEC §1.7, §1.8 packing
    output wire [127:0] bb_y_flat,
    output wire [15:0]  bb_active,
    output wire [31:0]  bb_pattern_flat // SPEC §1.7: 16×2-bit; bit0 = phase
);

    // ---------- localparams ----------
    localparam X_MAX            = 8'd199;   // FB right (SPEC §1.6)
    localparam Y_MAX            = 8'd149;   // FB bottom (SPEC §1.6)
    localparam BULLETS_PER_FIRE = 4'd5;
    localparam FIRE_PERIOD      = 6'd25;    // game_ticks between bursts
    localparam BOSS_CENTER_OFF  = 8'd8;     // half of 16-px boss sprite

    // ---------- regs (state) ----------
    reg [7:0]        bb_x [0:15];
    reg [7:0]        bb_y [0:15];
    reg signed [3:0] bb_vx [0:15];
    reg signed [3:0] bb_vy [0:15];
    reg [1:0]        bb_pat [0:15];
    reg [15:0]       bb_active_r;
    reg [3:0]        wr_ptr;
    reg [5:0]        fire_timer;

    // ---------- regs (combinational next-state) ----------
    reg [7:0]        bb_x_n [0:15];
    reg [7:0]        bb_y_n [0:15];
    reg signed [3:0] bb_vx_n [0:15];
    reg signed [3:0] bb_vy_n [0:15];
    reg [1:0]        bb_pat_n [0:15];
    reg [15:0]       bb_act_n;
    reg [3:0]        wr_ptr_n;
    reg [5:0]        fire_timer_n;

    // ---------- aimed-vector (phase 1, octant approximation) ----------
    // dx, dy in 9-bit signed so subtraction doesn't wrap.
    wire signed [8:0] dx     = {1'b0, player_x} - {1'b0, boss_x};
    wire signed [8:0] dy     = {1'b0, player_y} - {1'b0, boss_y};
    wire        [7:0] abs_dx = dx[8] ? -dx[7:0] : dx[7:0];
    wire        [7:0] abs_dy = dy[8] ? -dy[7:0] : dy[7:0];

    wire signed [3:0] vx_base = (abs_dx >= abs_dy) ?
                                    (dx[8] ? -4'sd2 : 4'sd2) :
                                    (dx[8] ? -4'sd1 : 4'sd1);
    wire signed [3:0] vy_base = (abs_dx >= abs_dy) ?
                                    (dy[8] ? -4'sd1 : 4'sd1) :
                                    (dy[8] ? -4'sd2 : 4'sd2);

    // boss center as spawn point
    wire [7:0] boss_cx = boss_x + BOSS_CENTER_OFF;
    wire [7:0] boss_cy = boss_y + BOSS_CENTER_OFF;

    // ---------- spread / ring vector tables ----------
    // Phase 1: vx offset by burst-index. Returned as 4-bit signed.
    function signed [3:0] spread_offset;
        input [2:0] idx;
        case (idx)
            3'd0:    spread_offset = -4'sd2;
            3'd1:    spread_offset = -4'sd1;
            3'd2:    spread_offset =  4'sd0;
            3'd3:    spread_offset =  4'sd1;
            3'd4:    spread_offset =  4'sd2;
            default: spread_offset =  4'sd0;
        endcase
    endfunction

    // Phase 2 ring: 5 bullets at 72° spacing, speed ~3.
    //   idx 0 →   0° → ( 3,  0)
    //   idx 1 →  72° → ( 1,  3)
    //   idx 2 → 144° → (-3,  2)
    //   idx 3 → 216° → (-3, -2)
    //   idx 4 → 288° → ( 1, -3)
    function signed [3:0] ring_vx;
        input [2:0] idx;
        case (idx)
            3'd0:    ring_vx =  4'sd3;
            3'd1:    ring_vx =  4'sd1;
            3'd2:    ring_vx = -4'sd3;
            3'd3:    ring_vx = -4'sd3;
            3'd4:    ring_vx =  4'sd1;
            default: ring_vx =  4'sd0;
        endcase
    endfunction

    function signed [3:0] ring_vy;
        input [2:0] idx;
        case (idx)
            3'd0:    ring_vy =  4'sd0;
            3'd1:    ring_vy =  4'sd3;
            3'd2:    ring_vy =  4'sd2;
            3'd3:    ring_vy = -4'sd2;
            3'd4:    ring_vy = -4'sd3;
            default: ring_vy =  4'sd0;
        endcase
    endfunction

    // ---------- output packing ----------
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin: pack_bb
            assign bb_x_flat      [gi*8 +: 8] = bb_x  [gi];
            assign bb_y_flat      [gi*8 +: 8] = bb_y  [gi];
            assign bb_pattern_flat[gi*2 +: 2] = bb_pat[gi];
        end
    endgenerate
    assign bb_active = bb_active_r;

    // ---------- combinational next-state ----------
    integer          i;
    reg [3:0]        slot;       // slot index for spawn loop
    reg [8:0]        nx, ny;     // 9-bit OOB-safe arithmetic
    reg signed [3:0] sp_off;     // per-burst-index spread offset

    always @* begin
        // Defaults: hold (CONVENTIONS §6, GOTCHAS §G18 — no latches).
        for (i = 0; i < 16; i = i + 1) begin
            bb_x_n  [i] = bb_x  [i];
            bb_y_n  [i] = bb_y  [i];
            bb_vx_n [i] = bb_vx [i];
            bb_vy_n [i] = bb_vy [i];
            bb_pat_n[i] = bb_pat[i];
        end
        bb_act_n     = bb_active_r;
        wr_ptr_n     = wr_ptr;
        fire_timer_n = fire_timer;
        nx           = 9'd0;
        ny           = 9'd0;
        slot         = 4'd0;
        sp_off       = 4'sd0;

        if (game_tick) begin
            // ---- Step 1: advance ----
            for (i = 0; i < 16; i = i + 1) begin
                if (bb_active_r[i]) begin
                    nx = {1'b0, bb_x[i]} + {{5{bb_vx[i][3]}}, bb_vx[i]};
                    ny = {1'b0, bb_y[i]} + {{5{bb_vy[i][3]}}, bb_vy[i]};
                    if (nx[8] || nx[7:0] > X_MAX || ny[8] || ny[7:0] > Y_MAX) begin
                        bb_act_n[i] = 1'b0;
                    end else begin
                        bb_x_n[i] = nx[7:0];
                        bb_y_n[i] = ny[7:0];
                    end
                end
            end

            // ---- Step 2: hit_mask despawn ----
            for (i = 0; i < 16; i = i + 1) begin
                if (bb_act_n[i] && hit_mask[i]) bb_act_n[i] = 1'b0;
            end

            // ---- Step 3: fire on timer ----
            if (fire_timer >= FIRE_PERIOD) begin
                fire_timer_n = 6'd0;
                for (i = 0; i < 5; i = i + 1) begin
                    slot = wr_ptr + i[3:0];   // mod-16 via 4-bit truncation
                    bb_x_n  [slot] = boss_cx;
                    bb_y_n  [slot] = boss_cy;
                    bb_act_n[slot] = 1'b1;
                    bb_pat_n[slot] = {1'b0, phase};   // SPEC §1.7 bit-0 encoding
                    if (!phase) begin
                        sp_off          = spread_offset(i[2:0]);
                        bb_vx_n[slot]   = vx_base + sp_off;
                        bb_vy_n[slot]   = vy_base;
                    end else begin
                        bb_vx_n[slot]   = ring_vx(i[2:0]);
                        bb_vy_n[slot]   = ring_vy(i[2:0]);
                    end
                end
                wr_ptr_n = wr_ptr + BULLETS_PER_FIRE;
            end else begin
                fire_timer_n = fire_timer + 6'd1;
            end
        end
    end

    // ---------- sequential commit ----------
    integer j;
    always @(posedge pixel_clk) begin
        if (reset) begin
            for (j = 0; j < 16; j = j + 1) begin
                bb_x  [j] <= 8'd0;
                bb_y  [j] <= 8'd0;
                bb_vx [j] <= 4'sd0;
                bb_vy [j] <= 4'sd0;
                bb_pat[j] <= 2'd0;
            end
            bb_active_r <= 16'd0;
            wr_ptr      <= 4'd0;
            fire_timer  <= 6'd0;
        end else begin
            for (j = 0; j < 16; j = j + 1) begin
                bb_x  [j] <= bb_x_n  [j];
                bb_y  [j] <= bb_y_n  [j];
                bb_vx [j] <= bb_vx_n [j];
                bb_vy [j] <= bb_vy_n [j];
                bb_pat[j] <= bb_pat_n[j];
            end
            bb_active_r <= bb_act_n;
            wr_ptr      <= wr_ptr_n;
            fire_timer  <= fire_timer_n;
        end
    end

endmodule
