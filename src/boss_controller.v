`timescale 1ns / 1ps
// boss_controller.v
// Phase 1: boss bounces left/right at 2px/frame
// Phase 2: boss tracks player x at 1px/frame (more aggressive)
// HP: 99,999,999 (27-bit). Phase 2 triggers at 50% HP.

module boss_controller (
    input  wire        pixel_clk,
    input  wire        reset,
    input  wire        game_tick,

    input  wire [7:0]  player_x,       // needed for phase 2 tracking
    input  wire [7:0]  pb_hit,         // from collision.v — each high bit = 1 HP lost

    output reg  [7:0]  boss_x,
    output wire [7:0]  boss_y,
    output wire        phase,          // 0 = phase 1 (bounce), 1 = phase 2 (track)
    output wire        boss_death_flag
);

    // constants
    parameter SPRITE_SIZE  = 8'd16;
    parameter X_INIT       = 8'd92;
    parameter Y_POS        = 8'd2;
    parameter X_MAX        = 8'd184;
    parameter SPEED_BOUNCE = 8'd2;     // phase 1 bounce speed
    parameter SPEED_TRACK  = 8'd1;     // phase 2 tracking speed
    parameter HP_MAX       = 27'd99_999_999;
    parameter HP_HALF      = 27'd49_999_999;

    // state registers
    reg [26:0] boss_hp;
    reg        dir;        // phase 1 only: 0 = right, 1 = left

    // next state
    reg [7:0]  boss_x_n;
    reg [26:0] boss_hp_n;
    reg        dir_n;

    // static outputs
    assign boss_y          = Y_POS;
    assign phase           = (boss_hp <= HP_HALF) ? 1'b1 : 1'b0;
    assign boss_death_flag = (boss_hp == 27'd0)   ? 1'b1 : 1'b0;

    // count hits from player bullets
    wire [3:0] hits = pb_hit[0] + pb_hit[1] + pb_hit[2] + pb_hit[3] + pb_hit[4] + pb_hit[5] + pb_hit[6] + pb_hit[7];

    // combinational next state
    always @* begin
        boss_x_n  = boss_x;
        boss_hp_n = boss_hp;
        dir_n     = dir;

        if (game_tick) begin

            // Phase 1: bounce left/right 
            if (!phase) begin
                if (!dir) begin
                    // moving right
                    if (boss_x + SPEED_BOUNCE >= X_MAX) begin
                        boss_x_n = X_MAX;
                        dir_n    = 1'b1;
                    end else begin
                        boss_x_n = boss_x + SPEED_BOUNCE;
                    end
                end else begin
                    // moving left
                    if (boss_x <= SPEED_BOUNCE) begin
                        boss_x_n = 8'd0;
                        dir_n    = 1'b0;
                    end else begin
                        boss_x_n = boss_x - SPEED_BOUNCE;
                    end
                end

            // Phase 2: track player x position
            end else begin
                if (boss_x < player_x) begin
                    if (boss_x + SPEED_TRACK <= X_MAX)
                        boss_x_n = boss_x + SPEED_TRACK;
                    else
                        boss_x_n = X_MAX;
                end else if (boss_x > player_x) begin
                    if (boss_x >= SPEED_TRACK)
                        boss_x_n = boss_x - SPEED_TRACK;
                    else
                        boss_x_n = 8'd0;
                end
                // if boss_x == player_x, hold position (default)
            end

            // decrement HP  
            if (hits > 0) begin
                if (boss_hp <= {23'b0, hits})
                    boss_hp_n = 27'd0;
                else
                    boss_hp_n = boss_hp - {23'b0, hits};
            end

        end
    end

    // sequential: commit on pixel_clk
    always @(posedge pixel_clk) begin
        if (reset) begin
            boss_x  <= X_INIT;
            boss_hp <= HP_MAX;
            dir     <= 1'b0;
        end else begin
            boss_x  <= boss_x_n;
            boss_hp <= boss_hp_n;
            dir     <= dir_n;
        end
    end

endmodule
