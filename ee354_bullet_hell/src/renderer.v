`timescale 1ns / 1ps
// 200x150 x 4bpp palette framebuffer. Dual-port BRAM; scanout reads at pixel_clk,
// blitter writes via the rdprogress FSM. Outputs 12-bit RGB through palette_lut.
//
// Bullet arrays are flat buses (Verilog-2001 compatible; no packed arrays).
// Bullet i occupies bits [i*8 +: 8] of pb_x_flat / pb_y_flat / bb_x_flat / bb_y_flat,
// and [i*2 +: 2] of bb_pattern_flat. bit0 of pattern selects phase-1 vs phase-2 rom.
module renderer (
    input  wire         pixel_clk,
    input  wire         reset,

    // From display_controller
    input  wire         bright,
    input  wire [9:0]   hCount,
    input  wire [9:0]   vCount,

    // Sprite positions in logical framebuffer coords (0..199 / 0..149)
    input  wire [7:0]   player_x,
    input  wire [7:0]   player_y,
    input  wire [7:0]   boss_x,
    input  wire [7:0]   boss_y,

    // 8 player bullets
    input  wire [63:0]  pb_x_flat,
    input  wire [63:0]  pb_y_flat,
    input  wire [7:0]   pb_active,

    // 16 boss bullets
    input  wire [127:0] bb_x_flat,
    input  wire [127:0] bb_y_flat,
    input  wire [15:0]  bb_active,
    input  wire [31:0]  bb_pattern_flat,

    output reg  [3:0]   vga_r,
    output reg  [3:0]   vga_g,
    output reg  [3:0]   vga_b
);

    // ---------- Geometry ----------
    localparam FB_W        = 200;
    localparam FB_H        = 150;
    localparam FB_SIZE     = 30000;
    // display_controller active region: hCount 144..783, vCount 35..515
    // Center a 200x150 x3 = 600x450 view: 20 px H border, 15 px V border
    localparam H_FB_START  = 164;   // 144 + 20
    localparam H_FB_END    = 764;   // 164 + 600
    localparam V_FB_START  = 50;    // 35 + 15
    localparam V_FB_END    = 500;   // 50 + 450

    // ---------- Sync inputs into pixel_clk domain ----------
    reg [9:0] hCount_r, vCount_r;
    reg       bright_r;
    always @(posedge pixel_clk) begin
        hCount_r <= hCount;
        vCount_r <= vCount;
        bright_r <= bright;
    end

    wire in_fb_h = (hCount_r >= H_FB_START) && (hCount_r < H_FB_END);
    wire in_fb_v = (vCount_r >= V_FB_START) && (vCount_r < V_FB_END);
    wire in_fb   = in_fb_h && in_fb_v && bright_r;

    // ---------- Scanout: combinational /3 scaling ----------
    // Vivado compiles the constant divide to a small LUT net. The *200 likewise
    // maps to shift-and-add. BRAM has 1-cycle read latency so the displayed pixel
    // lags hCount by one cycle; invisible at 25 MHz.
    wire [9:0] h_off    = hCount_r - H_FB_START[9:0];
    wire [9:0] v_off    = vCount_r - V_FB_START[9:0];
    wire [7:0] fb_x     = h_off / 10'd3;
    wire [7:0] fb_y     = v_off / 10'd3;
    wire [14:0] rd_addr = {7'b0, fb_y} * 15'd200 + {7'b0, fb_x};

    // ---------- Framebuffer ----------
    wire [3:0]  fb_pixel;
    reg         fb_we;
    reg  [14:0] fb_wr_addr;
    reg  [3:0]  fb_wr_data;

    framebuffer u_fb (
        .clk    (pixel_clk),
        .we     (fb_we),
        .wr_addr(fb_wr_addr),
        .wr_data(fb_wr_data),
        .rd_addr(rd_addr),
        .rd_data(fb_pixel)
    );

    // ---------- Palette + RGB output ----------
    // Inside fb region: use fb_pixel. Outside (border within active video): bg.
    // During blanking: forced black.
    wire [3:0]  px_idx = in_fb ? fb_pixel : 4'd1;
    wire [11:0] px_rgb;
    palette_lut u_pal (.index(px_idx), .rgb(px_rgb));

    always @(posedge pixel_clk) begin
        if (bright_r) begin
            vga_r <= px_rgb[11:8];
            vga_g <= px_rgb[7:4];
            vga_b <= px_rgb[3:0];
        end else begin
            vga_r <= 4'd0;
            vga_g <= 4'd0;
            vga_b <= 4'd0;
        end
    end

    // ---------- rdprogress FSM (write side) ----------
    //
    // WEEK 1 STRATEGY: NAIVE FULL CLEAR + SPRITE DRAWS.
    // Writes per frame: 30000 clear + 256 player + 256 boss + 8*256 pb + 16*256 bb
    // ~= 36.5K cycles. Triggered at vblank start (vCount crosses 480). Overruns
    // raw vblank (~36K cycles) by a few hundred; spill bleeds into the first
    // active scanlines of the next frame. For a static Week 1 scene this is
    // invisible because the data being written equals the data being read.
    //
    // TODO(Week 2): when bullet counts stress the budget, swap S_CLEAR for
    //               dirty-region tracking — clear only previous-frame sprite
    //               bounding boxes. See handoff_doc.md section 5.6.

    localparam S_WAIT_VBL  = 3'd0;
    localparam S_CLEAR     = 3'd1;
    localparam S_DRAW_PL   = 3'd2;
    localparam S_DRAW_BOSS = 3'd3;
    localparam S_DRAW_PB   = 3'd4;
    localparam S_DRAW_BB   = 3'd5;
    localparam S_DONE      = 3'd6;

    reg [2:0]  state;
    reg [14:0] clear_addr;
    reg [3:0]  spr_row;
    reg [3:0]  spr_col;
    reg [3:0]  spr_idx;
    reg [7:0]  cur_sx, cur_sy;
    reg        vbl_prev;

    wire vbl_now  = (vCount >= 10'd480);
    wire vbl_rise = vbl_now && !vbl_prev;

    // Sprite ROMs (combinational, LUT-inferred)
    wire [7:0] spr_addr = {spr_row, spr_col};
    wire [3:0] px_player, px_boss, px_pb, px_bb_p1, px_bb_p2;

    sprite_rom_player     u_rom_pl   (.addr(spr_addr), .data(px_player));
    sprite_rom_boss       u_rom_bs   (.addr(spr_addr), .data(px_boss));
    sprite_rom_pbullet    u_rom_pb   (.addr(spr_addr), .data(px_pb));
    sprite_rom_bbullet_p1 u_rom_bbp1 (.addr(spr_addr), .data(px_bb_p1));
    sprite_rom_bbullet_p2 u_rom_bbp2 (.addr(spr_addr), .data(px_bb_p2));

    // Per-bullet accessors via flat-bus slicing
    wire [7:0] pb_x_cur   = pb_x_flat[spr_idx[2:0]*8 +: 8];
    wire [7:0] pb_y_cur   = pb_y_flat[spr_idx[2:0]*8 +: 8];
    wire [7:0] bb_x_cur   = bb_x_flat[spr_idx*8 +: 8];
    wire [7:0] bb_y_cur   = bb_y_flat[spr_idx*8 +: 8];
    wire [1:0] bb_pat_cur = bb_pattern_flat[spr_idx*2 +: 2];
    wire [3:0] px_bb_sel  = bb_pat_cur[0] ? px_bb_p2 : px_bb_p1;

    // Write-target addresses
    wire [8:0] tgt_x_ps  = cur_sx  + {1'b0, spr_col};  // player / boss (ps = position sprite)
    wire [8:0] tgt_y_ps  = cur_sy  + {1'b0, spr_row};
    wire [8:0] tgt_x_pb  = pb_x_cur + {1'b0, spr_col};
    wire [8:0] tgt_y_pb  = pb_y_cur + {1'b0, spr_row};
    wire [8:0] tgt_x_bb  = bb_x_cur + {1'b0, spr_col};
    wire [8:0] tgt_y_bb  = bb_y_cur + {1'b0, spr_row};

    wire [14:0] wr_addr_ps = {6'b0, tgt_y_ps} * 15'd200 + {6'b0, tgt_x_ps};
    wire [14:0] wr_addr_pb = {6'b0, tgt_y_pb} * 15'd200 + {6'b0, tgt_x_pb};
    wire [14:0] wr_addr_bb = {6'b0, tgt_y_bb} * 15'd200 + {6'b0, tgt_x_bb};

    always @(posedge pixel_clk) begin
        vbl_prev <= vbl_now;
        if (reset) begin
            state      <= S_WAIT_VBL;
            fb_we      <= 1'b0;
            clear_addr <= 15'd0;
            spr_row    <= 4'd0;
            spr_col    <= 4'd0;
            spr_idx    <= 4'd0;
            cur_sx     <= 8'd0;
            cur_sy     <= 8'd0;
        end else begin
            fb_we <= 1'b0; // default; states below assert it when writing
            case (state)
                S_WAIT_VBL: begin
                    if (vbl_rise) begin
                        clear_addr <= 15'd0;
                        state      <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    fb_we      <= 1'b1;
                    fb_wr_addr <= clear_addr;
                    fb_wr_data <= 4'd1; // background
                    if (clear_addr == FB_SIZE - 1) begin
                        clear_addr <= 15'd0;
                        spr_row    <= 4'd0;
                        spr_col    <= 4'd0;
                        cur_sx     <= player_x;
                        cur_sy     <= player_y;
                        state      <= S_DRAW_PL;
                    end else begin
                        clear_addr <= clear_addr + 15'd1;
                    end
                end

                S_DRAW_PL: begin
                    if (px_player != 4'd0 && tgt_x_ps < FB_W && tgt_y_ps < FB_H) begin
                        fb_we      <= 1'b1;
                        fb_wr_addr <= wr_addr_ps;
                        fb_wr_data <= px_player;
                    end
                    if (spr_col == 4'd15) begin
                        spr_col <= 4'd0;
                        if (spr_row == 4'd15) begin
                            spr_row <= 4'd0;
                            cur_sx  <= boss_x;
                            cur_sy  <= boss_y;
                            state   <= S_DRAW_BOSS;
                        end else begin
                            spr_row <= spr_row + 4'd1;
                        end
                    end else begin
                        spr_col <= spr_col + 4'd1;
                    end
                end

                S_DRAW_BOSS: begin
                    if (px_boss != 4'd0 && tgt_x_ps < FB_W && tgt_y_ps < FB_H) begin
                        fb_we      <= 1'b1;
                        fb_wr_addr <= wr_addr_ps;
                        fb_wr_data <= px_boss;
                    end
                    if (spr_col == 4'd15) begin
                        spr_col <= 4'd0;
                        if (spr_row == 4'd15) begin
                            spr_row <= 4'd0;
                            spr_idx <= 4'd0;
                            state   <= S_DRAW_PB;
                        end else begin
                            spr_row <= spr_row + 4'd1;
                        end
                    end else begin
                        spr_col <= spr_col + 4'd1;
                    end
                end

                S_DRAW_PB: begin
                    if (pb_active[spr_idx[2:0]] && px_pb != 4'd0 &&
                        tgt_x_pb < FB_W && tgt_y_pb < FB_H) begin
                        fb_we      <= 1'b1;
                        fb_wr_addr <= wr_addr_pb;
                        fb_wr_data <= px_pb;
                    end
                    if (spr_col == 4'd15) begin
                        spr_col <= 4'd0;
                        if (spr_row == 4'd15) begin
                            spr_row <= 4'd0;
                            if (spr_idx == 4'd7) begin
                                spr_idx <= 4'd0;
                                state   <= S_DRAW_BB;
                            end else begin
                                spr_idx <= spr_idx + 4'd1;
                            end
                        end else begin
                            spr_row <= spr_row + 4'd1;
                        end
                    end else begin
                        spr_col <= spr_col + 4'd1;
                    end
                end

                S_DRAW_BB: begin
                    if (bb_active[spr_idx] && px_bb_sel != 4'd0 &&
                        tgt_x_bb < FB_W && tgt_y_bb < FB_H) begin
                        fb_we      <= 1'b1;
                        fb_wr_addr <= wr_addr_bb;
                        fb_wr_data <= px_bb_sel;
                    end
                    if (spr_col == 4'd15) begin
                        spr_col <= 4'd0;
                        if (spr_row == 4'd15) begin
                            spr_row <= 4'd0;
                            if (spr_idx == 4'd15) begin
                                state <= S_DONE;
                            end else begin
                                spr_idx <= spr_idx + 4'd1;
                            end
                        end else begin
                            spr_row <= spr_row + 4'd1;
                        end
                    end else begin
                        spr_col <= spr_col + 4'd1;
                    end
                end

                S_DONE: begin
                    state <= S_WAIT_VBL;
                end

                default: state <= S_WAIT_VBL;
            endcase
        end
    end

endmodule
