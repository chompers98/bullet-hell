`timescale 1ns / 1ps
// Task 1 top: VGA bring-up with SMPTE-style color bars + a 20x20 bouncing square.
// Does NOT use the renderer. Pure combinational test pattern driven by hCount/vCount
// plus a once-per-frame square-position update. Run this first to prove the VGA
// pipeline + display_controller + xdc all work on hardware.
module vga_test_top (
    input  wire       ClkPort,      // 100 MHz board clock
    input  wire       BtnC,         // reset (momentary)

    output wire       hSync,
    output wire       vSync,
    output wire [3:0] vgaR,
    output wire [3:0] vgaG,
    output wire [3:0] vgaB,

    output wire       QuadSpiFlashCS
);
    assign QuadSpiFlashCS = 1'b1;

    wire        bright;
    wire [9:0]  hCount, vCount;
    wire        clk25;

    display_controller u_dc (
        .clk      (ClkPort),
        .hSync    (hSync),
        .vSync    (vSync),
        .bright   (bright),
        .hCount   (hCount),
        .vCount   (vCount),
        .clk25_out(clk25)
    );

    // ---- Bouncing square (updates once per frame on vblank rise) ----
    reg [9:0] sq_x;
    reg [9:0] sq_y;
    reg       dx_pos;   // 1 = moving right
    reg       dy_pos;   // 1 = moving down
    reg       vbl_prev;

    wire vbl_now  = (vCount >= 10'd480);
    wire vbl_rise = vbl_now && !vbl_prev;

    localparam SQ_SIZE  = 10'd20;
    localparam H_MIN    = 10'd144;
    localparam H_MAX    = 10'd763;  // 784 - SQ_SIZE - 1
    localparam V_MIN    = 10'd35;
    localparam V_MAX    = 10'd494;  // 515 - SQ_SIZE - 1

    always @(posedge clk25) begin
        vbl_prev <= vbl_now;
        if (BtnC) begin
            sq_x   <= 10'd300;
            sq_y   <= 10'd200;
            dx_pos <= 1'b1;
            dy_pos <= 1'b1;
        end else if (vbl_rise) begin
            // horizontal
            if (dx_pos) begin
                if (sq_x >= H_MAX - 10'd2) begin
                    dx_pos <= 1'b0;
                    sq_x   <= sq_x - 10'd2;
                end else begin
                    sq_x <= sq_x + 10'd2;
                end
            end else begin
                if (sq_x <= H_MIN + 10'd2) begin
                    dx_pos <= 1'b1;
                    sq_x   <= sq_x + 10'd2;
                end else begin
                    sq_x <= sq_x - 10'd2;
                end
            end
            // vertical
            if (dy_pos) begin
                if (sq_y >= V_MAX - 10'd2) begin
                    dy_pos <= 1'b0;
                    sq_y   <= sq_y - 10'd2;
                end else begin
                    sq_y <= sq_y + 10'd2;
                end
            end else begin
                if (sq_y <= V_MIN + 10'd2) begin
                    dy_pos <= 1'b1;
                    sq_y   <= sq_y + 10'd2;
                end else begin
                    sq_y <= sq_y - 10'd2;
                end
            end
        end
    end

    // ---- Pattern: 8 vertical SMPTE-style color bars across the 640-px active
    // region (80 px per bar). hCount active starts at 144. ----
    wire [9:0] h_act = hCount - 10'd144;
    reg  [11:0] bar_rgb;
    always @(*) begin
        if      (h_act < 10'd80)  bar_rgb = 12'h000; // black
        else if (h_act < 10'd160) bar_rgb = 12'h00F; // blue
        else if (h_act < 10'd240) bar_rgb = 12'h0F0; // green
        else if (h_act < 10'd320) bar_rgb = 12'h0FF; // cyan
        else if (h_act < 10'd400) bar_rgb = 12'hF00; // red
        else if (h_act < 10'd480) bar_rgb = 12'hF0F; // magenta
        else if (h_act < 10'd560) bar_rgb = 12'hFF0; // yellow
        else                      bar_rgb = 12'hFFF; // white
    end

    wire in_sq = (hCount >= sq_x) && (hCount < sq_x + SQ_SIZE) &&
                 (vCount >= sq_y) && (vCount < sq_y + SQ_SIZE);

    reg [11:0] rgb;
    always @(*) begin
        if (!bright)   rgb = 12'h000;
        else if (in_sq) rgb = 12'hFFF; // white square overlay
        else            rgb = bar_rgb;
    end

    assign vgaR = rgb[11:8];
    assign vgaG = rgb[7:4];
    assign vgaB = rgb[3:0];

endmodule
