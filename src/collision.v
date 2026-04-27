`timescale 1ns / 1ps
// collision.v — 24 bounding box comparators
//
// Two sets of checks:
//   A) 8 player bullets vs boss   → pb_hit[7:0]   (to boss_controller)
//   B) 16 boss bullets vs player  → bb_hit[15:0]  (to boss_bullet hit_mask)
//                                 → player_hit     (to top.v for lives)
//
// Hitboxes:
//   Player      : 4x4  at (player_x+6, player_y+6)
//   Boss        : 16x16 at (boss_x, boss_y)
//   Player bullet: 4x8  at (pb_x, pb_y)
//   Boss bullet  : 6x6  at (bb_x, bb_y)
//
// All inputs are in logical framebuffer coordinates (200x150)

module collision (
    // player position
    input wire [7:0] player_x,
    input wire [7:0] player_y,

    // boss position
    input wire [7:0] boss_x,
    input wire [7:0] boss_y,

    // player bullets — flat packed buses from player_bullet.v
    input wire [63:0]  pb_x_flat,    // 8 x 8-bit x positions
    input wire [63:0]  pb_y_flat,    // 8 x 8-bit y positions
    input wire [7:0]   pb_active,    // active flags

    // boss bullets — flat packed buses from boss_bullet.v
    input wire [127:0] bb_x_flat,    // 16 x 8-bit x positions
    input wire [127:0] bb_y_flat,    // 16 x 8-bit y positions
    input wire [15:0]  bb_active,    // active flags

    // outputs
    output wire [7:0]  pb_hit,       // player bullet i hit the boss
    output wire [15:0] bb_hit,       // boss bullet i hit the player
    output wire        player_hit    // any boss bullet hit player this frame
);

    // unpack player bullet positions from flat buses
    wire [7:0] pb_x [0:7];
    wire [7:0] pb_y [0:7];

    assign pb_x[0] = pb_x_flat[7:0];
    assign pb_x[1] = pb_x_flat[15:8];
    assign pb_x[2] = pb_x_flat[23:16];
    assign pb_x[3] = pb_x_flat[31:24];
    assign pb_x[4] = pb_x_flat[39:32];
    assign pb_x[5] = pb_x_flat[47:40];
    assign pb_x[6] = pb_x_flat[55:48];
    assign pb_x[7] = pb_x_flat[63:56];

    assign pb_y[0] = pb_y_flat[7:0];
    assign pb_y[1] = pb_y_flat[15:8];
    assign pb_y[2] = pb_y_flat[23:16];
    assign pb_y[3] = pb_y_flat[31:24];
    assign pb_y[4] = pb_y_flat[39:32];
    assign pb_y[5] = pb_y_flat[47:40];
    assign pb_y[6] = pb_y_flat[55:48];
    assign pb_y[7] = pb_y_flat[63:56];

    // unpack boss bullet positions from flat buses
    wire [7:0] bb_x [0:15];
    wire [7:0] bb_y [0:15];

    assign bb_x[0]  = bb_x_flat[7:0];
    assign bb_x[1]  = bb_x_flat[15:8];
    assign bb_x[2]  = bb_x_flat[23:16];
    assign bb_x[3]  = bb_x_flat[31:24];
    assign bb_x[4]  = bb_x_flat[39:32];
    assign bb_x[5]  = bb_x_flat[47:40];
    assign bb_x[6]  = bb_x_flat[55:48];
    assign bb_x[7]  = bb_x_flat[63:56];
    assign bb_x[8]  = bb_x_flat[71:64];
    assign bb_x[9]  = bb_x_flat[79:72];
    assign bb_x[10] = bb_x_flat[87:80];
    assign bb_x[11] = bb_x_flat[95:88];
    assign bb_x[12] = bb_x_flat[103:96];
    assign bb_x[13] = bb_x_flat[111:104];
    assign bb_x[14] = bb_x_flat[119:112];
    assign bb_x[15] = bb_x_flat[127:120];

    assign bb_y[0]  = bb_y_flat[7:0];
    assign bb_y[1]  = bb_y_flat[15:8];
    assign bb_y[2]  = bb_y_flat[23:16];
    assign bb_y[3]  = bb_y_flat[31:24];
    assign bb_y[4]  = bb_y_flat[39:32];
    assign bb_y[5]  = bb_y_flat[47:40];
    assign bb_y[6]  = bb_y_flat[55:48];
    assign bb_y[7]  = bb_y_flat[63:56];
    assign bb_y[8]  = bb_y_flat[71:64];
    assign bb_y[9]  = bb_y_flat[79:72];
    assign bb_y[10] = bb_y_flat[87:80];
    assign bb_y[11] = bb_y_flat[95:88];
    assign bb_y[12] = bb_y_flat[103:96];
    assign bb_y[13] = bb_y_flat[111:104];
    assign bb_y[14] = bb_y_flat[119:112];
    assign bb_y[15] = bb_y_flat[127:120];

    // Hitbox parameters
    // player hitbox: 4x4 centered in 16x16 sprite
    wire [7:0] phit_x = player_x + 8'd6;
    wire [7:0] phit_y = player_y + 8'd6;
    localparam PLAYER_HIT_W = 8'd4;
    localparam PLAYER_HIT_H = 8'd4;

    // boss hitbox: full 16x16
    localparam BOSS_HIT_W   = 8'd16;
    localparam BOSS_HIT_H   = 8'd16;

    // player bullet hitbox: 4x8 full sprite
    localparam PB_W         = 8'd4;
    localparam PB_H         = 8'd8;

    // boss bullet hitbox: 6x6
    localparam BB_W         = 8'd6;
    localparam BB_H         = 8'd6;

    // A) Player bullets vs boss (8 comparators)
    //
    // Collision if:
    //   pb_x + PB_W > boss_x      (bullet right edge past boss left)
    //   pb_x < boss_x + BOSS_W    (bullet left edge before boss right)
    //   pb_y + PB_H > boss_y      (bullet bottom past boss top)
    //   pb_y < boss_y + BOSS_H    (bullet top before boss bottom)
    assign pb_hit[0] = pb_active[0] &&
                       (pb_x[0] + PB_W  > boss_x) &&
                       (pb_x[0]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[0] + PB_H  > boss_y) &&
                       (pb_y[0]         < boss_y + BOSS_HIT_H);

    assign pb_hit[1] = pb_active[1] &&
                       (pb_x[1] + PB_W  > boss_x) &&
                       (pb_x[1]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[1] + PB_H  > boss_y) &&
                       (pb_y[1]         < boss_y + BOSS_HIT_H);

    assign pb_hit[2] = pb_active[2] &&
                       (pb_x[2] + PB_W  > boss_x) &&
                       (pb_x[2]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[2] + PB_H  > boss_y) &&
                       (pb_y[2]         < boss_y + BOSS_HIT_H);

    assign pb_hit[3] = pb_active[3] &&
                       (pb_x[3] + PB_W  > boss_x) &&
                       (pb_x[3]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[3] + PB_H  > boss_y) &&
                       (pb_y[3]         < boss_y + BOSS_HIT_H);

    assign pb_hit[4] = pb_active[4] &&
                       (pb_x[4] + PB_W  > boss_x) &&
                       (pb_x[4]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[4] + PB_H  > boss_y) &&
                       (pb_y[4]         < boss_y + BOSS_HIT_H);

    assign pb_hit[5] = pb_active[5] &&
                       (pb_x[5] + PB_W  > boss_x) &&
                       (pb_x[5]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[5] + PB_H  > boss_y) &&
                       (pb_y[5]         < boss_y + BOSS_HIT_H);

    assign pb_hit[6] = pb_active[6] &&
                       (pb_x[6] + PB_W  > boss_x) &&
                       (pb_x[6]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[6] + PB_H  > boss_y) &&
                       (pb_y[6]         < boss_y + BOSS_HIT_H);

    assign pb_hit[7] = pb_active[7] &&
                       (pb_x[7] + PB_W  > boss_x) &&
                       (pb_x[7]         < boss_x + BOSS_HIT_W) &&
                       (pb_y[7] + PB_H  > boss_y) &&
                       (pb_y[7]         < boss_y + BOSS_HIT_H);

    // B) Boss bullets vs player (16 comparators)
    //
    // Collision if:
    //   bb_x + BB_W > phit_x          (bullet right past player left)
    //   bb_x < phit_x + PLAYER_HIT_W  (bullet left before player right)
    //   bb_y + BB_H > phit_y          (bullet bottom past player top)
    //   bb_y < phit_y + PLAYER_HIT_H  (bullet top before player bottom)
    assign bb_hit[0] = bb_active[0] &&
                       (bb_x[0] + BB_W  > phit_x) &&
                       (bb_x[0]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[0] + BB_H  > phit_y) &&
                       (bb_y[0]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[1] = bb_active[1] &&
                       (bb_x[1] + BB_W  > phit_x) &&
                       (bb_x[1]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[1] + BB_H  > phit_y) &&
                       (bb_y[1]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[2] = bb_active[2] &&
                       (bb_x[2] + BB_W  > phit_x) &&
                       (bb_x[2]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[2] + BB_H  > phit_y) &&
                       (bb_y[2]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[3] = bb_active[3] &&
                       (bb_x[3] + BB_W  > phit_x) &&
                       (bb_x[3]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[3] + BB_H  > phit_y) &&
                       (bb_y[3]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[4] = bb_active[4] &&
                       (bb_x[4] + BB_W  > phit_x) &&
                       (bb_x[4]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[4] + BB_H  > phit_y) &&
                       (bb_y[4]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[5] = bb_active[5] &&
                       (bb_x[5] + BB_W  > phit_x) &&
                       (bb_x[5]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[5] + BB_H  > phit_y) &&
                       (bb_y[5]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[6] = bb_active[6] &&
                       (bb_x[6] + BB_W  > phit_x) &&
                       (bb_x[6]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[6] + BB_H  > phit_y) &&
                       (bb_y[6]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[7] = bb_active[7] &&
                       (bb_x[7] + BB_W  > phit_x) &&
                       (bb_x[7]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[7] + BB_H  > phit_y) &&
                       (bb_y[7]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[8] = bb_active[8] &&
                       (bb_x[8] + BB_W  > phit_x) &&
                       (bb_x[8]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[8] + BB_H  > phit_y) &&
                       (bb_y[8]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[9] = bb_active[9] &&
                       (bb_x[9] + BB_W  > phit_x) &&
                       (bb_x[9]         < phit_x + PLAYER_HIT_W) &&
                       (bb_y[9] + BB_H  > phit_y) &&
                       (bb_y[9]         < phit_y + PLAYER_HIT_H);

    assign bb_hit[10] = bb_active[10] &&
                        (bb_x[10] + BB_W > phit_x) &&
                        (bb_x[10]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[10] + BB_H > phit_y) &&
                        (bb_y[10]        < phit_y + PLAYER_HIT_H);

    assign bb_hit[11] = bb_active[11] &&
                        (bb_x[11] + BB_W > phit_x) &&
                        (bb_x[11]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[11] + BB_H > phit_y) &&
                        (bb_y[11]        < phit_y + PLAYER_HIT_H);

    assign bb_hit[12] = bb_active[12] &&
                        (bb_x[12] + BB_W > phit_x) &&
                        (bb_x[12]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[12] + BB_H > phit_y) &&
                        (bb_y[12]        < phit_y + PLAYER_HIT_H);

    assign bb_hit[13] = bb_active[13] &&
                        (bb_x[13] + BB_W > phit_x) &&
                        (bb_x[13]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[13] + BB_H > phit_y) &&
                        (bb_y[13]        < phit_y + PLAYER_HIT_H);

    assign bb_hit[14] = bb_active[14] &&
                        (bb_x[14] + BB_W > phit_x) &&
                        (bb_x[14]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[14] + BB_H > phit_y) &&
                        (bb_y[14]        < phit_y + PLAYER_HIT_H);

    assign bb_hit[15] = bb_active[15] &&
                        (bb_x[15] + BB_W > phit_x) &&
                        (bb_x[15]        < phit_x + PLAYER_HIT_W) &&
                        (bb_y[15] + BB_H > phit_y) &&
                        (bb_y[15]        < phit_y + PLAYER_HIT_H);

    // player_hit: high if ANY boss bullet hit player this frame
    // top.v uses this to decrement lives and trigger i-frames
    assign player_hit = |bb_hit; // ORing all bb bits

endmodule
