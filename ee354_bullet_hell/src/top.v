`timescale 1ns / 1ps
// Task 2 + Week 2-A top: drive renderer with LIVE player_x/y from
// player_controller, hardcoded boss + bullet positions (player_bullet and
// boss_controller are not yet integrated — Week 2-B).
//
// Expected on-screen result:
//   - Dark blue background
//   - White square (player) starts at (92, 126); moves on toggle per SPEC §10.1
//   - Red square (boss) at top-center, still hardcoded
//   - Cyan dot (one active player bullet) mid-left, still hardcoded
//   - Yellow and magenta dots (two active boss bullets) mid-right, hardcoded
//
// IMPL DECISIONS:
//   - Reset source: SW0 (J15), active-high synchronous, per SPEC §1.2. SPEC
//     §0 Q3 was "BtnC default, revisit when player_controller lands". Now
//     that player_controller needs BtnCenter for shoot (SPEC §10.1 L541),
//     reset had to move off BtnC. SW0 picked over CPU_RESETN to keep reset
//     active-high (CPU_RESETN is active-low) and visible as a flip switch.
//   - Button debouncing: SPEC §10.1 L540 annotates BtnU/D/L/R as "(debounced)".
//     All 5 buttons (BtnU/D/L/R/BtnC) run through ee201_debouncer instances
//     clocked on pixel_clk (25 MHz). N_dc=25 gives ~0.335 s debounce at
//     25 MHz — acceptably fast for gameplay.
//   - game_tick: single pixel_clk pulse when (vCount,hCount) transitions into
//     (516, 0) — first pixel of vblank line 516. One pulse per frame = 60 Hz.
//   - shoot_pulse output of player_controller is left unconnected; player_bullet
//     is not wired into top.v until Week 2-B.
module top (
    input  wire       ClkPort,            // 100 MHz board clock
    input  wire       SW0,                // active-high sync reset
    input  wire       BtnC,               // shoot (BtnCenter per SPEC)
    input  wire       BtnU,
    input  wire       BtnD,
    input  wire       BtnL,
    input  wire       BtnR,

    output wire       hSync,
    output wire       vSync,
    output wire [3:0] vgaR,
    output wire [3:0] vgaG,
    output wire [3:0] vgaB,

    output wire       QuadSpiFlashCS
);
    assign QuadSpiFlashCS = 1'b1;

    // ---------- VGA timing ----------
    wire        bright;
    wire [9:0]  hCount, vCount;
    wire        pixel_clk;

    display_controller u_dc (
        .clk      (ClkPort),
        .hSync    (hSync),
        .vSync    (vSync),
        .bright   (bright),
        .hCount   (hCount),
        .vCount   (vCount),
        .clk25_out(pixel_clk)
    );

    // ---------- reset (active-high sync) ----------
    wire reset = SW0;

    // ---------- debouncers (pixel_clk domain) ----------
    wire BtnU_db, BtnD_db, BtnL_db, BtnR_db, BtnC_db;

    ee201_debouncer u_db_u (
        .CLK(pixel_clk), .RESET(reset), .PB(BtnU),
        .DPB(BtnU_db), .SCEN(), .MCEN(), .CCEN()
    );
    ee201_debouncer u_db_d (
        .CLK(pixel_clk), .RESET(reset), .PB(BtnD),
        .DPB(BtnD_db), .SCEN(), .MCEN(), .CCEN()
    );
    ee201_debouncer u_db_l (
        .CLK(pixel_clk), .RESET(reset), .PB(BtnL),
        .DPB(BtnL_db), .SCEN(), .MCEN(), .CCEN()
    );
    ee201_debouncer u_db_r (
        .CLK(pixel_clk), .RESET(reset), .PB(BtnR),
        .DPB(BtnR_db), .SCEN(), .MCEN(), .CCEN()
    );
    ee201_debouncer u_db_c (
        .CLK(pixel_clk), .RESET(reset), .PB(BtnC),
        .DPB(BtnC_db), .SCEN(), .MCEN(), .CCEN()
    );

    // ---------- game_tick generator ----------
    // Pulse for exactly one pixel_clk cycle at the start of line 516
    // (first vblank line). 60 Hz cadence at 25 MHz pixel_clk.
    reg game_tick;
    always @(posedge pixel_clk) begin
        if (reset)
            game_tick <= 1'b0;
        else
            game_tick <= (vCount == 10'd516) && (hCount == 10'd0);
    end

    // ---------- player_controller ----------
    wire [7:0] player_x, player_y;
    wire       shoot_pulse_unused;

    player_controller u_pc (
        .pixel_clk  (pixel_clk),
        .reset      (reset),
        .game_tick  (game_tick),
        .BtnU       (BtnU_db),
        .BtnD       (BtnD_db),
        .BtnL       (BtnL_db),
        .BtnR       (BtnR_db),
        .BtnCenter  (BtnC_db),
        .player_x   (player_x),
        .player_y   (player_y),
        .shoot_pulse(shoot_pulse_unused)  // Week 2-B: wire to player_bullet
    );

    // ---------- hardcoded boss + bullets (Week 2-A) ----------
    wire [7:0] boss_x = 8'd92;
    wire [7:0] boss_y = 8'd8;

    wire [63:0] pb_x_flat = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd30};
    wire [63:0] pb_y_flat = {8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd70};
    wire [7:0]  pb_active = 8'b0000_0001;

    wire [127:0] bb_x_flat = {
        8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
        8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd170, 8'd150
    };
    wire [127:0] bb_y_flat = {
        8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0,
        8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd0, 8'd60, 8'd40
    };
    wire [15:0]  bb_active       = 16'b0000_0000_0000_0011;
    wire [31:0]  bb_pattern_flat = 32'h0000_0004;

    renderer u_renderer (
        .pixel_clk      (pixel_clk),
        .reset          (reset),
        .bright         (bright),
        .hCount         (hCount),
        .vCount         (vCount),
        .player_x       (player_x),
        .player_y       (player_y),
        .boss_x         (boss_x),
        .boss_y         (boss_y),
        .pb_x_flat      (pb_x_flat),
        .pb_y_flat      (pb_y_flat),
        .pb_active      (pb_active),
        .bb_x_flat      (bb_x_flat),
        .bb_y_flat      (bb_y_flat),
        .bb_active      (bb_active),
        .bb_pattern_flat(bb_pattern_flat),
        .vga_r          (vgaR),
        .vga_g          (vgaG),
        .vga_b          (vgaB)
    );

endmodule
