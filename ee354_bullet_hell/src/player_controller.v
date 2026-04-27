`timescale 1ns / 1ps
// player_controller — hold-to-move 4-direction movement + shoot pulse.
// Adapted from initial draft by Leyaa; rewritten to match SPEC §10.1
// (toggle→hold revision 2026-04-23 per Beaux after hardware bring-up).
//
// IMPL DECISIONS:
//   - Reset polarity: active-high synchronous per SPEC §1.2 / GOTCHAS §G5.
//   - Clock: single `pixel_clk` domain per SPEC §1.1 / GOTCHAS §G12.
//     Position updates gate on `game_tick` (SPEC §1.1 L57, GOTCHAS §G15).
//   - Movement model: while a debounced direction button is held, position
//     advances ±1 per game_tick in that direction (SPEC §10.1 L542 revised).
//     No edge-detection or toggle state on the 4 direction buttons — the
//     debouncer already gives us a clean level.
//   - Speed: 1 logical pixel per game-tick per SPEC §10.1 L542.
//   - Bounds: clamp (not wrap) at [0, X_MAX] × [0, Y_MAX]. SPEC §10.1 L543
//     is silent on clamp-vs-wrap; clamping is the safe default.
//   - Opposing-button precedence: if both BtnR and BtnL (or BtnU and BtnD)
//     are held simultaneously, the positive direction (Right / Down) wins
//     this tick. SPEC silent; matches Leyaa's original `else if` structure.
//   - Reset spawn: (92, 126) per SPEC §10.1 L544.
//   - shoot_pulse: rising-edge detect on BtnCenter producing a single-
//     `pixel_clk`-cycle pulse, per SPEC §10.2.3 L587-602 (downstream
//     player_bullet expects the pulse in pixel_clk domain).
//   - No `initial` blocks used for state (GOTCHAS §G14).
//
module player_controller (
    input  wire        pixel_clk,    // 25 MHz, from display_controller.clk25_out
    input  wire        reset,        // active-high sync
    input  wire        game_tick,    // single-cycle pulse, start of vblank

    input  wire        BtnU,         // debounced directional buttons (levels)
    input  wire        BtnD,
    input  wire        BtnL,
    input  wire        BtnR,
    input  wire        BtnCenter,    // debounced shoot button

    output reg  [7:0]  player_x,     // logical FB coords, 0..184
    output reg  [7:0]  player_y,     // logical FB coords, 0..134
    output wire        shoot_pulse   // single-cycle, rising edge of BtnCenter
);

    // ---------- localparams ----------
    localparam SPEED  = 8'd1;    // SPEC §10.1 L542: 1 logical pixel per tick
    localparam X_MAX  = 8'd184;  // SPEC §10.1 L543: 200 - 16-px sprite
    localparam Y_MAX  = 8'd134;  // SPEC §10.1 L543: 150 - 16-px sprite
    localparam X_INIT = 8'd92;   // SPEC §10.1 L544
    localparam Y_INIT = 8'd126;  // SPEC §10.1 L544

    // ---------- regs ----------
    // previous BtnCenter state for shoot-pulse edge detect
    reg prev_center;

    // ---------- combinational outputs ----------
    // Single-cycle pulse on rising edge of debounced BtnCenter.
    // Pulse width = 1 pixel_clk cycle, per SPEC §10.2.3 L587-602.
    assign shoot_pulse = BtnCenter & ~prev_center;

    // ---------- sequential ----------
    // BtnCenter edge detect, every pixel_clk cycle.
    always @(posedge pixel_clk) begin
        if (reset)
            prev_center <= 1'b0;
        else
            prev_center <= BtnCenter;
    end

    // Position update — advances on game_tick, driven by live button levels.
    always @(posedge pixel_clk) begin
        if (reset) begin
            player_x <= X_INIT;
            player_y <= Y_INIT;
        end else if (game_tick) begin
            // horizontal: +SPEED if BtnR held, -SPEED if BtnL held.
            // Right wins if both are somehow asserted.
            if (BtnR) begin
                if (player_x + SPEED <= X_MAX)
                    player_x <= player_x + SPEED;
                else
                    player_x <= X_MAX;        // clamp at right edge
            end else if (BtnL) begin
                if (player_x >= SPEED)
                    player_x <= player_x - SPEED;
                else
                    player_x <= 8'd0;         // clamp at left edge
            end

            // vertical: +SPEED if BtnD held, -SPEED if BtnU held.
            // Down wins if both are asserted.
            if (BtnD) begin
                if (player_y + SPEED <= Y_MAX)
                    player_y <= player_y + SPEED;
                else
                    player_y <= Y_MAX;        // clamp at bottom edge
            end else if (BtnU) begin
                if (player_y >= SPEED)
                    player_y <= player_y - SPEED;
                else
                    player_y <= 8'd0;         // clamp at top edge
            end
        end
    end

endmodule
