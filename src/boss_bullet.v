`timescale 1ns / 1ps
// boss_bullet.v — pool of 16 boss bullets; spawn, advance, despawn.
//
// IMPL DECISIONS:
//   - Per-tick order: advance -> despawn -> spawn. Step 3 reads
//     post-step-2 state so a slot despawned this tick is immediately
//     reusable. Implemented in a single combinational always @* block
//     that produces *_n signals; a separate sequential always @(posedge
//     pixel_clk) commits them.
//   - Spawn strategy: round-robin write pointer. Boss fires 5 bullets
//     per burst so priority encoder is impractical — instead always
//     write into next 5 consecutive slots, overwriting oldest bullets.
//     By the time slots wrap around, those bullets are off-screen.
//   - game_tick sampling: single-cycle clock enable on pixel_clk.
//     State holds when game_tick is low.
//   - hit_mask semantics: bit i high on game_tick forces
//     bb_act_n[i] = 0 in step 2 (collision.v owned).
//   - Internal state: bb_x/bb_y as 16 separate 8-bit regs rather than
//     unpacked array — avoids synthesis tool array-handling quirks.
//   - Outputs packed as flat 128-bit buses (16 x 8-bit positions).

module boss_bullet (
    input  wire        pixel_clk,    // 25 MHz
    input  wire        reset,        // active-high sync reset

    input  wire        game_tick,    // single-cycle pulse ~60Hz
    input  wire        phase,        // 0 = phase 1 (spread), 1 = phase 2 (ring)

    input  wire [7:0]  boss_x,       // boss top-left x (logical FB coords)
    input  wire [7:0]  boss_y,       // boss top-left y
    input  wire [7:0]  player_x,     // player top-left x (for phase 1 aiming)
    input  wire [7:0]  player_y,

    // hit_mask: bit i high on game_tick -> despawn slot i
    // owner: collision.v
    input  wire [15:0] hit_mask,

    output wire [127:0] bb_x_flat,   // 16 x 8-bit x positions packed
    output wire [127:0] bb_y_flat,   // 16 x 8-bit y positions packed
    output wire [15:0]  bb_active    // active flag per bullet
);

    // state registers — individual regs, no unpacked arrays
    reg [7:0] bb_x0,  bb_x1,  bb_x2,  bb_x3,
              bb_x4,  bb_x5,  bb_x6,  bb_x7,
              bb_x8,  bb_x9,  bb_x10, bb_x11,
              bb_x12, bb_x13, bb_x14, bb_x15;

    reg [7:0] bb_y0,  bb_y1,  bb_y2,  bb_y3,
              bb_y4,  bb_y5,  bb_y6,  bb_y7,
              bb_y8,  bb_y9,  bb_y10, bb_y11,
              bb_y12, bb_y13, bb_y14, bb_y15;

    // signed velocities — internal only, renderer only needs position
    reg signed [3:0] bb_vx0,  bb_vx1,  bb_vx2,  bb_vx3,
                     bb_vx4,  bb_vx5,  bb_vx6,  bb_vx7,
                     bb_vx8,  bb_vx9,  bb_vx10, bb_vx11,
                     bb_vx12, bb_vx13, bb_vx14, bb_vx15;

    reg signed [3:0] bb_vy0,  bb_vy1,  bb_vy2,  bb_vy3,
                     bb_vy4,  bb_vy5,  bb_vy6,  bb_vy7,
                     bb_vy8,  bb_vy9,  bb_vy10, bb_vy11,
                     bb_vy12, bb_vy13, bb_vy14, bb_vy15;

    reg [15:0] bb_active_r;

    // round-robin write pointer and fire timer
    reg [3:0]  wr_ptr;
    reg [5:0]  fire_timer;

    // combinational next-state registers
    reg [7:0] bb_x0_n,  bb_x1_n,  bb_x2_n,  bb_x3_n,
              bb_x4_n,  bb_x5_n,  bb_x6_n,  bb_x7_n,
              bb_x8_n,  bb_x9_n,  bb_x10_n, bb_x11_n,
              bb_x12_n, bb_x13_n, bb_x14_n, bb_x15_n;

    reg [7:0] bb_y0_n,  bb_y1_n,  bb_y2_n,  bb_y3_n,
              bb_y4_n,  bb_y5_n,  bb_y6_n,  bb_y7_n,
              bb_y8_n,  bb_y9_n,  bb_y10_n, bb_y11_n,
              bb_y12_n, bb_y13_n, bb_y14_n, bb_y15_n;

    reg signed [3:0] bb_vx0_n,  bb_vx1_n,  bb_vx2_n,  bb_vx3_n,
                     bb_vx4_n,  bb_vx5_n,  bb_vx6_n,  bb_vx7_n,
                     bb_vx8_n,  bb_vx9_n,  bb_vx10_n, bb_vx11_n,
                     bb_vx12_n, bb_vx13_n, bb_vx14_n, bb_vx15_n;

    reg signed [3:0] bb_vy0_n,  bb_vy1_n,  bb_vy2_n,  bb_vy3_n,
                     bb_vy4_n,  bb_vy5_n,  bb_vy6_n,  bb_vy7_n,
                     bb_vy8_n,  bb_vy9_n,  bb_vy10_n, bb_vy11_n,
                     bb_vy12_n, bb_vy13_n, bb_vy14_n, bb_vy15_n;

    reg [15:0] bb_act_n;
    reg [3:0]  wr_ptr_n;
    reg [5:0]  fire_timer_n;

    // output packing — flat buses
    assign bb_x_flat = {bb_x15, bb_x14, bb_x13, bb_x12,
                        bb_x11, bb_x10, bb_x9,  bb_x8,
                        bb_x7,  bb_x6,  bb_x5,  bb_x4,
                        bb_x3,  bb_x2,  bb_x1,  bb_x0};

    assign bb_y_flat = {bb_y15, bb_y14, bb_y13, bb_y12,
                        bb_y11, bb_y10, bb_y9,  bb_y8,
                        bb_y7,  bb_y6,  bb_y5,  bb_y4,
                        bb_y3,  bb_y2,  bb_y1,  bb_y0};

    assign bb_active = bb_active_r;

    // boss center spawn point
    wire [7:0] boss_cx = boss_x + 8'd8;
    wire [7:0] boss_cy = boss_y + 8'd8;

    // aimed direction — octant approximation (phase 1)
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

    // Phase 1 spread offset: -2,-1, 0,+1,+2 applied to vx
    function signed [3:0] spread_offset;
        input integer idx;
        case (idx)
            0: spread_offset = -4'sd2;
            1: spread_offset = -4'sd1;
            2: spread_offset =  4'sd0;
            3: spread_offset =  4'sd1;
            4: spread_offset =  4'sd2;
            default: spread_offset = 4'sd0;
        endcase
    endfunction

    // Phase 2 ring: 5 bullets at 72 degrees apart, speed 3
    //
    //  index | angle | vx | vy
    //    0   |   0   |  3 |  0
    //    1   |  72   |  1 |  3
    //    2   | 144   | -3 |  2
    //    3   | 216   | -3 | -2
    //    4   | 288   |  1 | -3
    function signed [3:0] ring_vx;
        input integer idx;
        case (idx)
            0: ring_vx =  4'sd3;
            1: ring_vx =  4'sd1;
            2: ring_vx = -4'sd3;
            3: ring_vx = -4'sd3;
            4: ring_vx =  4'sd1;
            default: ring_vx = 4'sd0;
        endcase
    endfunction

    function signed [3:0] ring_vy;
        input integer idx;
        case (idx)
            0: ring_vy =  4'sd0;
            1: ring_vy =  4'sd3;
            2: ring_vy =  4'sd2;
            3: ring_vy = -4'sd2;
            4: ring_vy = -4'sd3;
            default: ring_vy = 4'sd0;
        endcase
    endfunction

    // Helper: next position with bounds check
    // Returns {oob, x_or_y} where oob=1 means out of bounds
    function [8:0] next_pos;
        input [7:0]      pos;
        input signed [3:0] vel;
        reg signed [8:0] result;
        begin
            result   = {1'b0, pos} + {{5{vel[3]}}, vel};
            next_pos = result;
        end
    endfunction

    // Combinational: compute next state
    // temporary wires for next position computation
    reg signed [8:0] nx, ny;

    always @* begin
        // defaults: hold current state 
        bb_x0_n  = bb_x0;  bb_x1_n  = bb_x1;  bb_x2_n  = bb_x2;  bb_x3_n  = bb_x3;
        bb_x4_n  = bb_x4;  bb_x5_n  = bb_x5;  bb_x6_n  = bb_x6;  bb_x7_n  = bb_x7;
        bb_x8_n  = bb_x8;  bb_x9_n  = bb_x9;  bb_x10_n = bb_x10; bb_x11_n = bb_x11;
        bb_x12_n = bb_x12; bb_x13_n = bb_x13; bb_x14_n = bb_x14; bb_x15_n = bb_x15;

        bb_y0_n  = bb_y0;  bb_y1_n  = bb_y1;  bb_y2_n  = bb_y2;  bb_y3_n  = bb_y3;
        bb_y4_n  = bb_y4;  bb_y5_n  = bb_y5;  bb_y6_n  = bb_y6;  bb_y7_n  = bb_y7;
        bb_y8_n  = bb_y8;  bb_y9_n  = bb_y9;  bb_y10_n = bb_y10; bb_y11_n = bb_y11;
        bb_y12_n = bb_y12; bb_y13_n = bb_y13; bb_y14_n = bb_y14; bb_y15_n = bb_y15;

        bb_vx0_n  = bb_vx0;  bb_vx1_n  = bb_vx1;  bb_vx2_n  = bb_vx2;  bb_vx3_n  = bb_vx3;
        bb_vx4_n  = bb_vx4;  bb_vx5_n  = bb_vx5;  bb_vx6_n  = bb_vx6;  bb_vx7_n  = bb_vx7;
        bb_vx8_n  = bb_vx8;  bb_vx9_n  = bb_vx9;  bb_vx10_n = bb_vx10; bb_vx11_n = bb_vx11;
        bb_vx12_n = bb_vx12; bb_vx13_n = bb_vx13; bb_vx14_n = bb_vx14; bb_vx15_n = bb_vx15;

        bb_vy0_n  = bb_vy0;  bb_vy1_n  = bb_vy1;  bb_vy2_n  = bb_vy2;  bb_vy3_n  = bb_vy3;
        bb_vy4_n  = bb_vy4;  bb_vy5_n  = bb_vy5;  bb_vy6_n  = bb_vy6;  bb_vy7_n  = bb_vy7;
        bb_vy8_n  = bb_vy8;  bb_vy9_n  = bb_vy9;  bb_vy10_n = bb_vy10; bb_vy11_n = bb_vy11;
        bb_vy12_n = bb_vy12; bb_vy13_n = bb_vy13; bb_vy14_n = bb_vy14; bb_vy15_n = bb_vy15;

        bb_act_n       = bb_active_r;
        wr_ptr_n       = wr_ptr;
        fire_timer_n   = fire_timer;

        if (game_tick) begin

            // Step 1: advance all active bullets 
            // Each bullet: compute next x/y, check bounds,
            // update position or mark out of bounds

            // slot 0
            if (bb_active_r[0]) begin
                nx = {1'b0, bb_x0} + {{5{bb_vx0[3]}}, bb_vx0};
                ny = {1'b0, bb_y0} + {{5{bb_vy0[3]}}, bb_vy0};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[0] = 1'b0;
                else begin bb_x0_n = nx[7:0]; bb_y0_n = ny[7:0]; end
            end
            // slot 1
            if (bb_active_r[1]) begin
                nx = {1'b0, bb_x1} + {{5{bb_vx1[3]}}, bb_vx1};
                ny = {1'b0, bb_y1} + {{5{bb_vy1[3]}}, bb_vy1};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[1] = 1'b0;
                else begin bb_x1_n = nx[7:0]; bb_y1_n = ny[7:0]; end
            end
            // slot 2
            if (bb_active_r[2]) begin
                nx = {1'b0, bb_x2} + {{5{bb_vx2[3]}}, bb_vx2};
                ny = {1'b0, bb_y2} + {{5{bb_vy2[3]}}, bb_vy2};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[2] = 1'b0;
                else begin bb_x2_n = nx[7:0]; bb_y2_n = ny[7:0]; end
            end
            // slot 3
            if (bb_active_r[3]) begin
                nx = {1'b0, bb_x3} + {{5{bb_vx3[3]}}, bb_vx3};
                ny = {1'b0, bb_y3} + {{5{bb_vy3[3]}}, bb_vy3};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[3] = 1'b0;
                else begin bb_x3_n = nx[7:0]; bb_y3_n = ny[7:0]; end
            end
            // slot 4
            if (bb_active_r[4]) begin
                nx = {1'b0, bb_x4} + {{5{bb_vx4[3]}}, bb_vx4};
                ny = {1'b0, bb_y4} + {{5{bb_vy4[3]}}, bb_vy4};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[4] = 1'b0;
                else begin bb_x4_n = nx[7:0]; bb_y4_n = ny[7:0]; end
            end
            // slot 5
            if (bb_active_r[5]) begin
                nx = {1'b0, bb_x5} + {{5{bb_vx5[3]}}, bb_vx5};
                ny = {1'b0, bb_y5} + {{5{bb_vy5[3]}}, bb_vy5};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[5] = 1'b0;
                else begin bb_x5_n = nx[7:0]; bb_y5_n = ny[7:0]; end
            end
            // slot 6
            if (bb_active_r[6]) begin
                nx = {1'b0, bb_x6} + {{5{bb_vx6[3]}}, bb_vx6};
                ny = {1'b0, bb_y6} + {{5{bb_vy6[3]}}, bb_vy6};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[6] = 1'b0;
                else begin bb_x6_n = nx[7:0]; bb_y6_n = ny[7:0]; end
            end
            // slot 7
            if (bb_active_r[7]) begin
                nx = {1'b0, bb_x7} + {{5{bb_vx7[3]}}, bb_vx7};
                ny = {1'b0, bb_y7} + {{5{bb_vy7[3]}}, bb_vy7};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[7] = 1'b0;
                else begin bb_x7_n = nx[7:0]; bb_y7_n = ny[7:0]; end
            end
            // slot 8
            if (bb_active_r[8]) begin
                nx = {1'b0, bb_x8} + {{5{bb_vx8[3]}}, bb_vx8};
                ny = {1'b0, bb_y8} + {{5{bb_vy8[3]}}, bb_vy8};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[8] = 1'b0;
                else begin bb_x8_n = nx[7:0]; bb_y8_n = ny[7:0]; end
            end
            // slot 9
            if (bb_active_r[9]) begin
                nx = {1'b0, bb_x9} + {{5{bb_vx9[3]}}, bb_vx9};
                ny = {1'b0, bb_y9} + {{5{bb_vy9[3]}}, bb_vy9};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[9] = 1'b0;
                else begin bb_x9_n = nx[7:0]; bb_y9_n = ny[7:0]; end
            end
            // slot 10
            if (bb_active_r[10]) begin
                nx = {1'b0, bb_x10} + {{5{bb_vx10[3]}}, bb_vx10};
                ny = {1'b0, bb_y10} + {{5{bb_vy10[3]}}, bb_vy10};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[10] = 1'b0;
                else begin bb_x10_n = nx[7:0]; bb_y10_n = ny[7:0]; end
            end
            // slot 11
            if (bb_active_r[11]) begin
                nx = {1'b0, bb_x11} + {{5{bb_vx11[3]}}, bb_vx11};
                ny = {1'b0, bb_y11} + {{5{bb_vy11[3]}}, bb_vy11};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[11] = 1'b0;
                else begin bb_x11_n = nx[7:0]; bb_y11_n = ny[7:0]; end
            end
            // slot 12
            if (bb_active_r[12]) begin
                nx = {1'b0, bb_x12} + {{5{bb_vx12[3]}}, bb_vx12};
                ny = {1'b0, bb_y12} + {{5{bb_vy12[3]}}, bb_vy12};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[12] = 1'b0;
                else begin bb_x12_n = nx[7:0]; bb_y12_n = ny[7:0]; end
            end
            // slot 13
            if (bb_active_r[13]) begin
                nx = {1'b0, bb_x13} + {{5{bb_vx13[3]}}, bb_vx13};
                ny = {1'b0, bb_y13} + {{5{bb_vy13[3]}}, bb_vy13};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[13] = 1'b0;
                else begin bb_x13_n = nx[7:0]; bb_y13_n = ny[7:0]; end
            end
            // slot 14
            if (bb_active_r[14]) begin
                nx = {1'b0, bb_x14} + {{5{bb_vx14[3]}}, bb_vx14};
                ny = {1'b0, bb_y14} + {{5{bb_vy14[3]}}, bb_vy14};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[14] = 1'b0;
                else begin bb_x14_n = nx[7:0]; bb_y14_n = ny[7:0]; end
            end
            // slot 15
            if (bb_active_r[15]) begin
                nx = {1'b0, bb_x15} + {{5{bb_vx15[3]}}, bb_vx15};
                ny = {1'b0, bb_y15} + {{5{bb_vy15[3]}}, bb_vy15};
                if (nx[8] || nx[7:0] > 8'd199 || ny[8] || ny[7:0] > 8'd149)
                    bb_act_n[15] = 1'b0;
                else begin bb_x15_n = nx[7:0]; bb_y15_n = ny[7:0]; end
            end

            // Step 2: despawn via hit_mask 
            // collision.v sets hit_mask[i] when boss bullet i hits player
            if (bb_act_n[0]  && hit_mask[0])  bb_act_n[0]  = 1'b0;
            if (bb_act_n[1]  && hit_mask[1])  bb_act_n[1]  = 1'b0;
            if (bb_act_n[2]  && hit_mask[2])  bb_act_n[2]  = 1'b0;
            if (bb_act_n[3]  && hit_mask[3])  bb_act_n[3]  = 1'b0;
            if (bb_act_n[4]  && hit_mask[4])  bb_act_n[4]  = 1'b0;
            if (bb_act_n[5]  && hit_mask[5])  bb_act_n[5]  = 1'b0;
            if (bb_act_n[6]  && hit_mask[6])  bb_act_n[6]  = 1'b0;
            if (bb_act_n[7]  && hit_mask[7])  bb_act_n[7]  = 1'b0;
            if (bb_act_n[8]  && hit_mask[8])  bb_act_n[8]  = 1'b0;
            if (bb_act_n[9]  && hit_mask[9])  bb_act_n[9]  = 1'b0;
            if (bb_act_n[10] && hit_mask[10]) bb_act_n[10] = 1'b0;
            if (bb_act_n[11] && hit_mask[11]) bb_act_n[11] = 1'b0;
            if (bb_act_n[12] && hit_mask[12]) bb_act_n[12] = 1'b0;
            if (bb_act_n[13] && hit_mask[13]) bb_act_n[13] = 1'b0;
            if (bb_act_n[14] && hit_mask[14]) bb_act_n[14] = 1'b0;
            if (bb_act_n[15] && hit_mask[15]) bb_act_n[15] = 1'b0;

            // Step 3: fire on timer 
            if (fire_timer >= 6'd25) begin
                fire_timer_n = 6'd0;

                // spawn 5 bullets at wr_ptr, wr_ptr+1 ... wr_ptr+4 (mod 16)
                // using explicit slot wires to avoid array indexing
                case (wr_ptr)
                    4'd0: begin
                        bb_x0_n  = boss_cx; bb_y0_n  = boss_cy; bb_act_n[0]  = 1'b1;
                        bb_x1_n  = boss_cx; bb_y1_n  = boss_cy; bb_act_n[1]  = 1'b1;
                        bb_x2_n  = boss_cx; bb_y2_n  = boss_cy; bb_act_n[2]  = 1'b1;
                        bb_x3_n  = boss_cx; bb_y3_n  = boss_cy; bb_act_n[3]  = 1'b1;
                        bb_x4_n  = boss_cx; bb_y4_n  = boss_cy; bb_act_n[4]  = 1'b1;
                        if (!phase) begin
                            bb_vx0_n = vx_base + spread_offset(0); bb_vy0_n = vy_base;
                            bb_vx1_n = vx_base + spread_offset(1); bb_vy1_n = vy_base;
                            bb_vx2_n = vx_base + spread_offset(2); bb_vy2_n = vy_base;
                            bb_vx3_n = vx_base + spread_offset(3); bb_vy3_n = vy_base;
                            bb_vx4_n = vx_base + spread_offset(4); bb_vy4_n = vy_base;
                        end else begin
                            bb_vx0_n = ring_vx(0); bb_vy0_n = ring_vy(0);
                            bb_vx1_n = ring_vx(1); bb_vy1_n = ring_vy(1);
                            bb_vx2_n = ring_vx(2); bb_vy2_n = ring_vy(2);
                            bb_vx3_n = ring_vx(3); bb_vy3_n = ring_vy(3);
                            bb_vx4_n = ring_vx(4); bb_vy4_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd5;
                    end
                    4'd1: begin
                        bb_x1_n  = boss_cx; bb_y1_n  = boss_cy; bb_act_n[1]  = 1'b1;
                        bb_x2_n  = boss_cx; bb_y2_n  = boss_cy; bb_act_n[2]  = 1'b1;
                        bb_x3_n  = boss_cx; bb_y3_n  = boss_cy; bb_act_n[3]  = 1'b1;
                        bb_x4_n  = boss_cx; bb_y4_n  = boss_cy; bb_act_n[4]  = 1'b1;
                        bb_x5_n  = boss_cx; bb_y5_n  = boss_cy; bb_act_n[5]  = 1'b1;
                        if (!phase) begin
                            bb_vx1_n = vx_base + spread_offset(0); bb_vy1_n = vy_base;
                            bb_vx2_n = vx_base + spread_offset(1); bb_vy2_n = vy_base;
                            bb_vx3_n = vx_base + spread_offset(2); bb_vy3_n = vy_base;
                            bb_vx4_n = vx_base + spread_offset(3); bb_vy4_n = vy_base;
                            bb_vx5_n = vx_base + spread_offset(4); bb_vy5_n = vy_base;
                        end else begin
                            bb_vx1_n = ring_vx(0); bb_vy1_n = ring_vy(0);
                            bb_vx2_n = ring_vx(1); bb_vy2_n = ring_vy(1);
                            bb_vx3_n = ring_vx(2); bb_vy3_n = ring_vy(2);
                            bb_vx4_n = ring_vx(3); bb_vy4_n = ring_vy(3);
                            bb_vx5_n = ring_vx(4); bb_vy5_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd6;
                    end
                    4'd2: begin
                        bb_x2_n  = boss_cx; bb_y2_n  = boss_cy; bb_act_n[2]  = 1'b1;
                        bb_x3_n  = boss_cx; bb_y3_n  = boss_cy; bb_act_n[3]  = 1'b1;
                        bb_x4_n  = boss_cx; bb_y4_n  = boss_cy; bb_act_n[4]  = 1'b1;
                        bb_x5_n  = boss_cx; bb_y5_n  = boss_cy; bb_act_n[5]  = 1'b1;
                        bb_x6_n  = boss_cx; bb_y6_n  = boss_cy; bb_act_n[6]  = 1'b1;
                        if (!phase) begin
                            bb_vx2_n = vx_base + spread_offset(0); bb_vy2_n = vy_base;
                            bb_vx3_n = vx_base + spread_offset(1); bb_vy3_n = vy_base;
                            bb_vx4_n = vx_base + spread_offset(2); bb_vy4_n = vy_base;
                            bb_vx5_n = vx_base + spread_offset(3); bb_vy5_n = vy_base;
                            bb_vx6_n = vx_base + spread_offset(4); bb_vy6_n = vy_base;
                        end else begin
                            bb_vx2_n = ring_vx(0); bb_vy2_n = ring_vy(0);
                            bb_vx3_n = ring_vx(1); bb_vy3_n = ring_vy(1);
                            bb_vx4_n = ring_vx(2); bb_vy4_n = ring_vy(2);
                            bb_vx5_n = ring_vx(3); bb_vy5_n = ring_vy(3);
                            bb_vx6_n = ring_vx(4); bb_vy6_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd7;
                    end
                    4'd3: begin
                        bb_x3_n  = boss_cx; bb_y3_n  = boss_cy; bb_act_n[3]  = 1'b1;
                        bb_x4_n  = boss_cx; bb_y4_n  = boss_cy; bb_act_n[4]  = 1'b1;
                        bb_x5_n  = boss_cx; bb_y5_n  = boss_cy; bb_act_n[5]  = 1'b1;
                        bb_x6_n  = boss_cx; bb_y6_n  = boss_cy; bb_act_n[6]  = 1'b1;
                        bb_x7_n  = boss_cx; bb_y7_n  = boss_cy; bb_act_n[7]  = 1'b1;
                        if (!phase) begin
                            bb_vx3_n = vx_base + spread_offset(0); bb_vy3_n = vy_base;
                            bb_vx4_n = vx_base + spread_offset(1); bb_vy4_n = vy_base;
                            bb_vx5_n = vx_base + spread_offset(2); bb_vy5_n = vy_base;
                            bb_vx6_n = vx_base + spread_offset(3); bb_vy6_n = vy_base;
                            bb_vx7_n = vx_base + spread_offset(4); bb_vy7_n = vy_base;
                        end else begin
                            bb_vx3_n = ring_vx(0); bb_vy3_n = ring_vy(0);
                            bb_vx4_n = ring_vx(1); bb_vy4_n = ring_vy(1);
                            bb_vx5_n = ring_vx(2); bb_vy5_n = ring_vy(2);
                            bb_vx6_n = ring_vx(3); bb_vy6_n = ring_vy(3);
                            bb_vx7_n = ring_vx(4); bb_vy7_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd8;
                    end
                    4'd4: begin
                        bb_x4_n  = boss_cx; bb_y4_n  = boss_cy; bb_act_n[4]  = 1'b1;
                        bb_x5_n  = boss_cx; bb_y5_n  = boss_cy; bb_act_n[5]  = 1'b1;
                        bb_x6_n  = boss_cx; bb_y6_n  = boss_cy; bb_act_n[6]  = 1'b1;
                        bb_x7_n  = boss_cx; bb_y7_n  = boss_cy; bb_act_n[7]  = 1'b1;
                        bb_x8_n  = boss_cx; bb_y8_n  = boss_cy; bb_act_n[8]  = 1'b1;
                        if (!phase) begin
                            bb_vx4_n = vx_base + spread_offset(0); bb_vy4_n = vy_base;
                            bb_vx5_n = vx_base + spread_offset(1); bb_vy5_n = vy_base;
                            bb_vx6_n = vx_base + spread_offset(2); bb_vy6_n = vy_base;
                            bb_vx7_n = vx_base + spread_offset(3); bb_vy7_n = vy_base;
                            bb_vx8_n = vx_base + spread_offset(4); bb_vy8_n = vy_base;
                        end else begin
                            bb_vx4_n = ring_vx(0); bb_vy4_n = ring_vy(0);
                            bb_vx5_n = ring_vx(1); bb_vy5_n = ring_vy(1);
                            bb_vx6_n = ring_vx(2); bb_vy6_n = ring_vy(2);
                            bb_vx7_n = ring_vx(3); bb_vy7_n = ring_vy(3);
                            bb_vx8_n = ring_vx(4); bb_vy8_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd9;
                    end
                    4'd5: begin
                        bb_x5_n  = boss_cx; bb_y5_n  = boss_cy; bb_act_n[5]  = 1'b1;
                        bb_x6_n  = boss_cx; bb_y6_n  = boss_cy; bb_act_n[6]  = 1'b1;
                        bb_x7_n  = boss_cx; bb_y7_n  = boss_cy; bb_act_n[7]  = 1'b1;
                        bb_x8_n  = boss_cx; bb_y8_n  = boss_cy; bb_act_n[8]  = 1'b1;
                        bb_x9_n  = boss_cx; bb_y9_n  = boss_cy; bb_act_n[9]  = 1'b1;
                        if (!phase) begin
                            bb_vx5_n = vx_base + spread_offset(0); bb_vy5_n = vy_base;
                            bb_vx6_n = vx_base + spread_offset(1); bb_vy6_n = vy_base;
                            bb_vx7_n = vx_base + spread_offset(2); bb_vy7_n = vy_base;
                            bb_vx8_n = vx_base + spread_offset(3); bb_vy8_n = vy_base;
                            bb_vx9_n = vx_base + spread_offset(4); bb_vy9_n = vy_base;
                        end else begin
                            bb_vx5_n = ring_vx(0); bb_vy5_n = ring_vy(0);
                            bb_vx6_n = ring_vx(1); bb_vy6_n = ring_vy(1);
                            bb_vx7_n = ring_vx(2); bb_vy7_n = ring_vy(2);
                            bb_vx8_n = ring_vx(3); bb_vy8_n = ring_vy(3);
                            bb_vx9_n = ring_vx(4); bb_vy9_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd10;
                    end
                    4'd6: begin
                        bb_x6_n  = boss_cx; bb_y6_n  = boss_cy; bb_act_n[6]  = 1'b1;
                        bb_x7_n  = boss_cx; bb_y7_n  = boss_cy; bb_act_n[7]  = 1'b1;
                        bb_x8_n  = boss_cx; bb_y8_n  = boss_cy; bb_act_n[8]  = 1'b1;
                        bb_x9_n  = boss_cx; bb_y9_n  = boss_cy; bb_act_n[9]  = 1'b1;
                        bb_x10_n = boss_cx; bb_y10_n = boss_cy; bb_act_n[10] = 1'b1;
                        if (!phase) begin
                            bb_vx6_n  = vx_base + spread_offset(0); bb_vy6_n  = vy_base;
                            bb_vx7_n  = vx_base + spread_offset(1); bb_vy7_n  = vy_base;
                            bb_vx8_n  = vx_base + spread_offset(2); bb_vy8_n  = vy_base;
                            bb_vx9_n  = vx_base + spread_offset(3); bb_vy9_n  = vy_base;
                            bb_vx10_n = vx_base + spread_offset(4); bb_vy10_n = vy_base;
                        end else begin
                            bb_vx6_n  = ring_vx(0); bb_vy6_n  = ring_vy(0);
                            bb_vx7_n  = ring_vx(1); bb_vy7_n  = ring_vy(1);
                            bb_vx8_n  = ring_vx(2); bb_vy8_n  = ring_vy(2);
                            bb_vx9_n  = ring_vx(3); bb_vy9_n  = ring_vy(3);
                            bb_vx10_n = ring_vx(4); bb_vy10_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd11;
                    end
                    4'd7: begin
                        bb_x7_n  = boss_cx; bb_y7_n  = boss_cy; bb_act_n[7]  = 1'b1;
                        bb_x8_n  = boss_cx; bb_y8_n  = boss_cy; bb_act_n[8]  = 1'b1;
                        bb_x9_n  = boss_cx; bb_y9_n  = boss_cy; bb_act_n[9]  = 1'b1;
                        bb_x10_n = boss_cx; bb_y10_n = boss_cy; bb_act_n[10] = 1'b1;
                        bb_x11_n = boss_cx; bb_y11_n = boss_cy; bb_act_n[11] = 1'b1;
                        if (!phase) begin
                            bb_vx7_n  = vx_base + spread_offset(0); bb_vy7_n  = vy_base;
                            bb_vx8_n  = vx_base + spread_offset(1); bb_vy8_n  = vy_base;
                            bb_vx9_n  = vx_base + spread_offset(2); bb_vy9_n  = vy_base;
                            bb_vx10_n = vx_base + spread_offset(3); bb_vy10_n = vy_base;
                            bb_vx11_n = vx_base + spread_offset(4); bb_vy11_n = vy_base;
                        end else begin
                            bb_vx7_n  = ring_vx(0); bb_vy7_n  = ring_vy(0);
                            bb_vx8_n  = ring_vx(1); bb_vy8_n  = ring_vy(1);
                            bb_vx9_n  = ring_vx(2); bb_vy9_n  = ring_vy(2);
                            bb_vx10_n = ring_vx(3); bb_vy10_n = ring_vy(3);
                            bb_vx11_n = ring_vx(4); bb_vy11_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd12;
                    end
                    4'd8: begin
                        bb_x8_n  = boss_cx; bb_y8_n  = boss_cy; bb_act_n[8]  = 1'b1;
                        bb_x9_n  = boss_cx; bb_y9_n  = boss_cy; bb_act_n[9]  = 1'b1;
                        bb_x10_n = boss_cx; bb_y10_n = boss_cy; bb_act_n[10] = 1'b1;
                        bb_x11_n = boss_cx; bb_y11_n = boss_cy; bb_act_n[11] = 1'b1;
                        bb_x12_n = boss_cx; bb_y12_n = boss_cy; bb_act_n[12] = 1'b1;
                        if (!phase) begin
                            bb_vx8_n  = vx_base + spread_offset(0); bb_vy8_n  = vy_base;
                            bb_vx9_n  = vx_base + spread_offset(1); bb_vy9_n  = vy_base;
                            bb_vx10_n = vx_base + spread_offset(2); bb_vy10_n = vy_base;
                            bb_vx11_n = vx_base + spread_offset(3); bb_vy11_n = vy_base;
                            bb_vx12_n = vx_base + spread_offset(4); bb_vy12_n = vy_base;
                        end else begin
                            bb_vx8_n  = ring_vx(0); bb_vy8_n  = ring_vy(0);
                            bb_vx9_n  = ring_vx(1); bb_vy9_n  = ring_vy(1);
                            bb_vx10_n = ring_vx(2); bb_vy10_n = ring_vy(2);
                            bb_vx11_n = ring_vx(3); bb_vy11_n = ring_vy(3);
                            bb_vx12_n = ring_vx(4); bb_vy12_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd13;
                    end
                    4'd9: begin
                        bb_x9_n  = boss_cx; bb_y9_n  = boss_cy; bb_act_n[9]  = 1'b1;
                        bb_x10_n = boss_cx; bb_y10_n = boss_cy; bb_act_n[10] = 1'b1;
                        bb_x11_n = boss_cx; bb_y11_n = boss_cy; bb_act_n[11] = 1'b1;
                        bb_x12_n = boss_cx; bb_y12_n = boss_cy; bb_act_n[12] = 1'b1;
                        bb_x13_n = boss_cx; bb_y13_n = boss_cy; bb_act_n[13] = 1'b1;
                        if (!phase) begin
                            bb_vx9_n  = vx_base + spread_offset(0); bb_vy9_n  = vy_base;
                            bb_vx10_n = vx_base + spread_offset(1); bb_vy10_n = vy_base;
                            bb_vx11_n = vx_base + spread_offset(2); bb_vy11_n = vy_base;
                            bb_vx12_n = vx_base + spread_offset(3); bb_vy12_n = vy_base;
                            bb_vx13_n = vx_base + spread_offset(4); bb_vy13_n = vy_base;
                        end else begin
                            bb_vx9_n  = ring_vx(0); bb_vy9_n  = ring_vy(0);
                            bb_vx10_n = ring_vx(1); bb_vy10_n = ring_vy(1);
                            bb_vx11_n = ring_vx(2); bb_vy11_n = ring_vy(2);
                            bb_vx12_n = ring_vx(3); bb_vy12_n = ring_vy(3);
                            bb_vx13_n = ring_vx(4); bb_vy13_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd14;
                    end
                    4'd10: begin
                        bb_x10_n = boss_cx; bb_y10_n = boss_cy; bb_act_n[10] = 1'b1;
                        bb_x11_n = boss_cx; bb_y11_n = boss_cy; bb_act_n[11] = 1'b1;
                        bb_x12_n = boss_cx; bb_y12_n = boss_cy; bb_act_n[12] = 1'b1;
                        bb_x13_n = boss_cx; bb_y13_n = boss_cy; bb_act_n[13] = 1'b1;
                        bb_x14_n = boss_cx; bb_y14_n = boss_cy; bb_act_n[14] = 1'b1;
                        if (!phase) begin
                            bb_vx10_n = vx_base + spread_offset(0); bb_vy10_n = vy_base;
                            bb_vx11_n = vx_base + spread_offset(1); bb_vy11_n = vy_base;
                            bb_vx12_n = vx_base + spread_offset(2); bb_vy12_n = vy_base;
                            bb_vx13_n = vx_base + spread_offset(3); bb_vy13_n = vy_base;
                            bb_vx14_n = vx_base + spread_offset(4); bb_vy14_n = vy_base;
                        end else begin
                            bb_vx10_n = ring_vx(0); bb_vy10_n = ring_vy(0);
                            bb_vx11_n = ring_vx(1); bb_vy11_n = ring_vy(1);
                            bb_vx12_n = ring_vx(2); bb_vy12_n = ring_vy(2);
                            bb_vx13_n = ring_vx(3); bb_vy13_n = ring_vy(3);
                            bb_vx14_n = ring_vx(4); bb_vy14_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd15;
                    end
                    4'd11: begin
                        bb_x11_n = boss_cx; bb_y11_n = boss_cy; bb_act_n[11] = 1'b1;
                        bb_x12_n = boss_cx; bb_y12_n = boss_cy; bb_act_n[12] = 1'b1;
                        bb_x13_n = boss_cx; bb_y13_n = boss_cy; bb_act_n[13] = 1'b1;
                        bb_x14_n = boss_cx; bb_y14_n = boss_cy; bb_act_n[14] = 1'b1;
                        bb_x15_n = boss_cx; bb_y15_n = boss_cy; bb_act_n[15] = 1'b1;
                        if (!phase) begin
                            bb_vx11_n = vx_base + spread_offset(0); bb_vy11_n = vy_base;
                            bb_vx12_n = vx_base + spread_offset(1); bb_vy12_n = vy_base;
                            bb_vx13_n = vx_base + spread_offset(2); bb_vy13_n = vy_base;
                            bb_vx14_n = vx_base + spread_offset(3); bb_vy14_n = vy_base;
                            bb_vx15_n = vx_base + spread_offset(4); bb_vy15_n = vy_base;
                        end else begin
                            bb_vx11_n = ring_vx(0); bb_vy11_n = ring_vy(0);
                            bb_vx12_n = ring_vx(1); bb_vy12_n = ring_vy(1);
                            bb_vx13_n = ring_vx(2); bb_vy13_n = ring_vy(2);
                            bb_vx14_n = ring_vx(3); bb_vy14_n = ring_vy(3);
                            bb_vx15_n = ring_vx(4); bb_vy15_n = ring_vy(4);
                        end
                        wr_ptr_n = 4'd0;
                    end
                    4'd12: begin
                        bb_x12_n = boss_cx; bb_y12_n = boss_cy; bb_act_n[12] = 1'b1;
                        bb_x13_n = boss_cx; bb_y13_n = boss_cy; bb_act_n[13] = 1'b1;
                        bb_x14_n = boss_cx; bb_y14_n = boss_cy; bb_act_n[14] = 1'b1;
                        bb_x15_n = boss_cx; bb_y15_n = boss_cy; bb_act_n[15] = 1'b1;
                        bb_x0_n  = boss_cx; bb_y0_n  = boss_cy; bb_act_n[0]  = 1'b1;
                        if (!phase) begin
                            bb_vx12_n = vx_base + spread_offset(0); bb_vy12_n = vy_base;
                            bb_vx13_n = vx_base + spread_offset(1); bb_vy13_n = vy_base;
                            bb_vx14_n = vx_base + spread_offset(2); bb_vy14_n = vy_base;
                            bb_vx15_n = vx_base + spread_offset(3); bb_vy15_n = vy_base;
                            bb_vx0_n  = vx_base + spread_offset(4); bb_vy0_n  = vy_base;
                        end else begin
                            bb_vx12_n = ring_vx(0); bb_vy12_n = ring_vy(0);
                            bb_vx13_n = ring_vx(1); bb_vy13_n = ring_vy(1);
                            bb_vx14_n = ring_vx(2); bb_vy14_n = ring_vy(2);
                            bb_vx15_n = ring_vx(3); bb_vy15_n = ring_vy(3);
                            bb_vx0_n  = ring_vx(4); bb_vy0_n  = ring_vy(4);
                        end
                        wr_ptr_n = 4'd1;
                    end
                    4'd13: begin
                        bb_x13_n = boss_cx; bb_y13_n = boss_cy; bb_act_n[13] = 1'b1;
                        bb_x14_n = boss_cx; bb_y14_n = boss_cy; bb_act_n[14] = 1'b1;
                        bb_x15_n = boss_cx; bb_y15_n = boss_cy; bb_act_n[15] = 1'b1;
                        bb_x0_n  = boss_cx; bb_y0_n  = boss_cy; bb_act_n[0]  = 1'b1;
                        bb_x1_n  = boss_cx; bb_y1_n  = boss_cy; bb_act_n[1]  = 1'b1;
                        if (!phase) begin
                            bb_vx13_n = vx_base + spread_offset(0); bb_vy13_n = vy_base;
                            bb_vx14_n = vx_base + spread_offset(1); bb_vy14_n = vy_base;
                            bb_vx15_n = vx_base + spread_offset(2); bb_vy15_n = vy_base;
                            bb_vx0_n  = vx_base + spread_offset(3); bb_vy0_n  = vy_base;
                            bb_vx1_n  = vx_base + spread_offset(4); bb_vy1_n  = vy_base;
                        end else begin
                            bb_vx13_n = ring_vx(0); bb_vy13_n = ring_vy(0);
                            bb_vx14_n = ring_vx(1); bb_vy14_n = ring_vy(1);
                            bb_vx15_n = ring_vx(2); bb_vy15_n = ring_vy(2);
                            bb_vx0_n  = ring_vx(3); bb_vy0_n  = ring_vy(3);
                            bb_vx1_n  = ring_vx(4); bb_vy1_n  = ring_vy(4);
                        end
                        wr_ptr_n = 4'd2;
                    end
                    4'd14: begin
                        bb_x14_n = boss_cx; bb_y14_n = boss_cy; bb_act_n[14] = 1'b1;
                        bb_x15_n = boss_cx; bb_y15_n = boss_cy; bb_act_n[15] = 1'b1;
                        bb_x0_n  = boss_cx; bb_y0_n  = boss_cy; bb_act_n[0]  = 1'b1;
                        bb_x1_n  = boss_cx; bb_y1_n  = boss_cy; bb_act_n[1]  = 1'b1;
                        bb_x2_n  = boss_cx; bb_y2_n  = boss_cy; bb_act_n[2]  = 1'b1;
                        if (!phase) begin
                            bb_vx14_n = vx_base + spread_offset(0); bb_vy14_n = vy_base;
                            bb_vx15_n = vx_base + spread_offset(1); bb_vy15_n = vy_base;
                            bb_vx0_n  = vx_base + spread_offset(2); bb_vy0_n  = vy_base;
                            bb_vx1_n  = vx_base + spread_offset(3); bb_vy1_n  = vy_base;
                            bb_vx2_n  = vx_base + spread_offset(4); bb_vy2_n  = vy_base;
                        end else begin
                            bb_vx14_n = ring_vx(0); bb_vy14_n = ring_vy(0);
                            bb_vx15_n = ring_vx(1); bb_vy15_n = ring_vy(1);
                            bb_vx0_n  = ring_vx(2); bb_vy0_n  = ring_vy(2);
                            bb_vx1_n  = ring_vx(3); bb_vy1_n  = ring_vy(3);
                            bb_vx2_n  = ring_vx(4); bb_vy2_n  = ring_vy(4);
                        end
                        wr_ptr_n = 4'd3;
                    end
                    4'd15: begin
                        bb_x15_n = boss_cx; bb_y15_n = boss_cy; bb_act_n[15] = 1'b1;
                        bb_x0_n  = boss_cx; bb_y0_n  = boss_cy; bb_act_n[0]  = 1'b1;
                        bb_x1_n  = boss_cx; bb_y1_n  = boss_cy; bb_act_n[1]  = 1'b1;
                        bb_x2_n  = boss_cx; bb_y2_n  = boss_cy; bb_act_n[2]  = 1'b1;
                        bb_x3_n  = boss_cx; bb_y3_n  = boss_cy; bb_act_n[3]  = 1'b1;
                        if (!phase) begin
                            bb_vx15_n = vx_base + spread_offset(0); bb_vy15_n = vy_base;
                            bb_vx0_n  = vx_base + spread_offset(1); bb_vy0_n  = vy_base;
                            bb_vx1_n  = vx_base + spread_offset(2); bb_vy1_n  = vy_base;
                            bb_vx2_n  = vx_base + spread_offset(3); bb_vy2_n  = vy_base;
                            bb_vx3_n  = vx_base + spread_offset(4); bb_vy3_n  = vy_base;
                        end else begin
                            bb_vx15_n = ring_vx(0); bb_vy15_n = ring_vy(0);
                            bb_vx0_n  = ring_vx(1); bb_vy0_n  = ring_vy(1);
                            bb_vx1_n  = ring_vx(2); bb_vy1_n  = ring_vy(2);
                            bb_vx2_n  = ring_vx(3); bb_vy2_n  = ring_vy(3);
                            bb_vx3_n  = ring_vx(4); bb_vy3_n  = ring_vy(4);
                        end
                        wr_ptr_n = 4'd4;
                    end
                    default: wr_ptr_n = 4'd0;
                endcase

            end else begin
                fire_timer_n = fire_timer + 6'd1;
            end
        end // game_tick
    end // always @*

    // Sequential: commit next state on pixel_clk
    // When game_tick is low, *_n == current state → no-op
    always @(posedge pixel_clk) begin
        if (reset) begin
            bb_x0  <= 8'd0; bb_x1  <= 8'd0; bb_x2  <= 8'd0; bb_x3  <= 8'd0;
            bb_x4  <= 8'd0; bb_x5  <= 8'd0; bb_x6  <= 8'd0; bb_x7  <= 8'd0;
            bb_x8  <= 8'd0; bb_x9  <= 8'd0; bb_x10 <= 8'd0; bb_x11 <= 8'd0;
            bb_x12 <= 8'd0; bb_x13 <= 8'd0; bb_x14 <= 8'd0; bb_x15 <= 8'd0;

            bb_y0  <= 8'd0; bb_y1  <= 8'd0; bb_y2  <= 8'd0; bb_y3  <= 8'd0;
            bb_y4  <= 8'd0; bb_y5  <= 8'd0; bb_y6  <= 8'd0; bb_y7  <= 8'd0;
            bb_y8  <= 8'd0; bb_y9  <= 8'd0; bb_y10 <= 8'd0; bb_y11 <= 8'd0;
            bb_y12 <= 8'd0; bb_y13 <= 8'd0; bb_y14 <= 8'd0; bb_y15 <= 8'd0;

            bb_vx0  <= 4'sd0; bb_vx1  <= 4'sd0; bb_vx2  <= 4'sd0; bb_vx3  <= 4'sd0;
            bb_vx4  <= 4'sd0; bb_vx5  <= 4'sd0; bb_vx6  <= 4'sd0; bb_vx7  <= 4'sd0;
            bb_vx8  <= 4'sd0; bb_vx9  <= 4'sd0; bb_vx10 <= 4'sd0; bb_vx11 <= 4'sd0;
            bb_vx12 <= 4'sd0; bb_vx13 <= 4'sd0; bb_vx14 <= 4'sd0; bb_vx15 <= 4'sd0;

            bb_vy0  <= 4'sd0; bb_vy1  <= 4'sd0; bb_vy2  <= 4'sd0; bb_vy3  <= 4'sd0;
            bb_vy4  <= 4'sd0; bb_vy5  <= 4'sd0; bb_vy6  <= 4'sd0; bb_vy7  <= 4'sd0;
            bb_vy8  <= 4'sd0; bb_vy9  <= 4'sd0; bb_vy10 <= 4'sd0; bb_vy11 <= 4'sd0;
            bb_vy12 <= 4'sd0; bb_vy13 <= 4'sd0; bb_vy14 <= 4'sd0; bb_vy15 <= 4'sd0;

            bb_active_r <= 16'd0;
            wr_ptr      <= 4'd0;
            fire_timer  <= 6'd0;

        end else begin
            bb_x0  <= bb_x0_n;  bb_x1  <= bb_x1_n;  bb_x2  <= bb_x2_n;  bb_x3  <= bb_x3_n;
            bb_x4  <= bb_x4_n;  bb_x5  <= bb_x5_n;  bb_x6  <= bb_x6_n;  bb_x7  <= bb_x7_n;
            bb_x8  <= bb_x8_n;  bb_x9  <= bb_x9_n;  bb_x10 <= bb_x10_n; bb_x11 <= bb_x11_n;
            bb_x12 <= bb_x12_n; bb_x13 <= bb_x13_n; bb_x14 <= bb_x14_n; bb_x15 <= bb_x15_n;

            bb_y0  <= bb_y0_n;  bb_y1  <= bb_y1_n;  bb_y2  <= bb_y2_n;  bb_y3  <= bb_y3_n;
            bb_y4  <= bb_y4_n;  bb_y5  <= bb_y5_n;  bb_y6  <= bb_y6_n;  bb_y7  <= bb_y7_n;
            bb_y8  <= bb_y8_n;  bb_y9  <= bb_y9_n;  bb_y10 <= bb_y10_n; bb_y11 <= bb_y11_n;
            bb_y12 <= bb_y12_n; bb_y13 <= bb_y13_n; bb_y14 <= bb_y14_n; bb_y15 <= bb_y15_n;

            bb_vx0  <= bb_vx0_n;  bb_vx1  <= bb_vx1_n;  bb_vx2  <= bb_vx2_n;  bb_vx3  <= bb_vx3_n;
            bb_vx4  <= bb_vx4_n;  bb_vx5  <= bb_vx5_n;  bb_vx6  <= bb_vx6_n;  bb_vx7  <= bb_vx7_n;
            bb_vx8  <= bb_vx8_n;  bb_vx9  <= bb_vx9_n;  bb_vx10 <= bb_vx10_n; bb_vx11 <= bb_vx11_n;
            bb_vx12 <= bb_vx12_n; bb_vx13 <= bb_vx13_n; bb_vx14 <= bb_vx14_n; bb_vx15 <= bb_vx15_n;

            bb_vy0  <= bb_vy0_n;  bb_vy1  <= bb_vy1_n;  bb_vy2  <= bb_vy2_n;  bb_vy3  <= bb_vy3_n;
            bb_vy4  <= bb_vy4_n;  bb_vy5  <= bb_vy5_n;  bb_vy6  <= bb_vy6_n;  bb_vy7  <= bb_vy7_n;
            bb_vy8  <= bb_vy8_n;  bb_vy9  <= bb_vy9_n;  bb_vy10 <= bb_vy10_n; bb_vy11 <= bb_vy11_n;
            bb_vy12 <= bb_vy12_n; bb_vy13 <= bb_vy13_n; bb_vy14 <= bb_vy14_n; bb_vy15 <= bb_vy15_n;

            bb_active_r <= bb_act_n;
            wr_ptr      <= wr_ptr_n;
            fire_timer  <= fire_timer_n;
        end
    end

endmodule
