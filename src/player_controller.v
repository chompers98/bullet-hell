`timescale 1ns / 1ps

module player_controller(
    input clk,          // game clock (~60Hz, one tick per frame)
    input rst,
    input btn_up,
    input btn_down,
    input btn_left,
    input btn_right,
    output reg [7:0] player_x,   // top-left x, 0 to 184 (or else out of frame)
    output reg [7:0] player_y    // top-left y, 0 to 134 (or else out of frame)
);

    // parameters
    parameter SPEED       = 8'd2;	 // change position by 2 px when moving 
    parameter SPRITE_SIZE = 8'd16;
    // frame buffer is 200 x 150
    parameter X_MAX       = 8'd184   // 200 - SPRITE_SIZE
    parameter Y_MAX       = 8'd134;  // 150 - SPRITE_SIZE
    parameter Y_MIN       = 8'd52;   // keep player below boss
    parameter X_INIT      = 8'd92;   // center of 200px wide field
    parameter Y_INIT      = 8'd134;  // at bottom

    // movement flags that flip on each button press
    reg move_up, move_down, move_left, move_right;

    // previous button states for rising edge detection
    reg prev_up, prev_down, prev_left, prev_right;

    // detect rising edge of each button press
    // and flip corresponding movement flag
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            prev_up    <= 0; prev_down  <= 0;
            prev_left  <= 0; prev_right <= 0;
            move_up    <= 0; move_down  <= 0;
            move_left  <= 0; move_right <= 0;
        end else begin
            // store previous state
            prev_up    <= btn_up;
            prev_down  <= btn_down;
            prev_left  <= btn_left;
            prev_right <= btn_right;

            // rising edge detected -> flip toggle
            if (btn_up    && !prev_up)    move_up    <= ~move_up;
            if (btn_down  && !prev_down)  move_down  <= ~move_down;
            if (btn_left  && !prev_left)  move_left  <= ~move_left;
            if (btn_right && !prev_right) move_right <= ~move_right;
        end
    end

    // update position every game clock tick by SPEED px
    // also limits to playfield boundaries so never goes off screen
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            player_x <= X_INIT;
            player_y <= Y_INIT;
        end else begin

            // horizontal moves
            if (move_right) begin
                if (player_x + SPEED <= X_MAX)
                    player_x <= player_x + SPEED;
                else
                    player_x <= X_MAX;  // limit to right edge
            end else if (move_left) begin
                if (player_x >= SPEED)
                    player_x <= player_x - SPEED;
                else
                    player_x <= 0;      // limit to left edge
            end

            // vertical moves
            if (move_down) begin
                if (player_y + SPEED <= Y_MAX)
                    player_y <= player_y + SPEED;
                else
                    player_y <= Y_MAX;  // limit to bottom edge
            end else if (move_up) begin
                if (player_y >= SPEED + Y_MIN)
                    player_y <= player_y - SPEED;
                else
                    player_y <= Y_MIN;      // limit to top edge
            end

        end
    end

endmodule
