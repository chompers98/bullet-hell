`timescale 1ns / 1ps
// top — Week 2-B fully integrated bullet-hell game.
// Wires player_controller + player_bullet + boss_controller + boss_bullet +
// collision + hud into the existing display_controller + renderer pipeline.
//
// Expected on-screen + board behavior:
//   - White player square moves on BtnU/D/L/R, fires cyan player-bullets on
//     BtnC.  Bullets travel up at 2 px/tick, despawn off-screen or on hit.
//   - Red boss patrols left/right (phase 1) above 50 HP, then tracks the
//     player's x (phase 2) at and below 50 HP.  Boss freezes at 0 HP.
//   - Yellow boss-bullets (phase 1 spread) and magenta (phase 2 ring) fire
//     in 5-bullet bursts every 26 game-ticks.
//   - LD0..LD(lives-1) lit, others off. 7-seg shows boss HP (00..99) on the
//     two rightmost digits; remaining digits blanked.
//
// IMPL DECISIONS:
//   - Reset source: SW0 (J15), active-high synchronous, per SPEC §1.2.
//     SPEC §0 Q3 default revised when player_controller took BtnC for shoot.
//   - Button debouncing: ee201_debouncer on all 5 buttons in pixel_clk
//     domain (SPEC §10.1 + GOTCHAS §G19 reference).
//   - game_tick: single pixel_clk pulse on (vCount,hCount) entering (516,0).
//     1 pulse/frame ≈ 60 Hz. SPEC §1.1 specifies "rising edge of vCount==480"
//     — line 516 differs by ~36 µs, functionally equivalent for game-tick
//     consumers (any single-cycle vblank pulse satisfies GOTCHAS §G15).
//   - Lives counter: 3-bit reg, resets to 5 (SPEC §1.7 player_lives [2:0]).
//     Decrements on player_hit_pulse, saturates at 0. No "game over" gating
//     yet — bullets/boss continue running at lives=0 (next-step decision).
//   - Wire-naming for collision masks:
//       hit_mask    [7:0]  — collision → player_bullet (SPEC §10.5 canonical)
//       bb_hit_mask [15:0] — collision → boss_bullet (SPEC-extension noted in
//                            collision IMPL block).
//   - bb_pattern_flat: passed straight from boss_bullet to renderer; boss_bullet
//     latches the spawn-time phase per slot.
//   - QuadSpiFlashCS held high to suppress flash chip activity (XDC pin L13).
//
module top (
    input  wire        ClkPort,            // 100 MHz board clock
    input  wire        SW0,                // active-high sync reset
    input  wire        BtnC,               // shoot (BtnCenter per SPEC §10.1)
    input  wire        BtnU,
    input  wire        BtnD,
    input  wire        BtnL,
    input  wire        BtnR,

    // VGA outputs
    output wire        hSync,
    output wire        vSync,
    output wire [3:0]  vgaR,
    output wire [3:0]  vgaG,
    output wire [3:0]  vgaB,

    // Player-lives LEDs (active-high)
    output wire [15:0] Ld,

    // Boss-HP 7-segment display (active-low cathodes/anodes per Nexys A7)
    output wire [6:0]  seg,                // {Ca, Cb, Cc, Cd, Ce, Cf, Cg}
    output wire        Dp,
    output wire [7:0]  An,

    output wire        QuadSpiFlashCS
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

    // ---------- game_tick generator (1 pulse per frame) ----------
    reg game_tick;
    always @(posedge pixel_clk) begin
        if (reset)
            game_tick <= 1'b0;
        else
            game_tick <= (vCount == 10'd516) && (hCount == 10'd0);
    end

    // ---------- inter-module wires ----------
    wire [7:0]   player_x, player_y;
    wire         shoot_pulse;

    wire [63:0]  pb_x_flat, pb_y_flat;
    wire [7:0]   pb_active;

    wire [7:0]   boss_x, boss_y;
    wire [6:0]   boss_hp;
    wire         phase, boss_death_flag;

    wire [127:0] bb_x_flat, bb_y_flat;
    wire [15:0]  bb_active;
    wire [31:0]  bb_pattern_flat;

    wire [7:0]   hit_mask;            // collision → player_bullet (SPEC §10.5)
    wire [15:0]  bb_hit_mask;         // collision → boss_bullet (SPEC-ext)
    wire         boss_hit_pulse;      // collision → boss_controller
    wire         player_hit_pulse;    // collision → lives counter

    // ---------- player_controller ----------
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
        .shoot_pulse(shoot_pulse)
    );

    // ---------- player_bullet ----------
    player_bullet u_pb (
        .pixel_clk  (pixel_clk),
        .reset      (reset),
        .game_tick  (game_tick),
        .shoot_pulse(shoot_pulse),
        .player_x   (player_x),
        .player_y   (player_y),
        .hit_mask   (hit_mask),
        .pb_x_flat  (pb_x_flat),
        .pb_y_flat  (pb_y_flat),
        .pb_active  (pb_active)
    );

    // ---------- boss_controller ----------
    boss_controller u_bc (
        .pixel_clk      (pixel_clk),
        .reset          (reset),
        .game_tick      (game_tick),
        .player_x       (player_x),
        .boss_hit_pulse (boss_hit_pulse),
        .boss_x         (boss_x),
        .boss_y         (boss_y),
        .boss_hp        (boss_hp),
        .phase          (phase),
        .boss_death_flag(boss_death_flag)
    );

    // ---------- boss_bullet ----------
    boss_bullet u_bb (
        .pixel_clk      (pixel_clk),
        .reset          (reset),
        .game_tick      (game_tick),
        .phase          (phase),
        .boss_x         (boss_x),
        .boss_y         (boss_y),
        .player_x       (player_x),
        .player_y       (player_y),
        .hit_mask       (bb_hit_mask),       // 16-bit mask from collision
        .bb_x_flat      (bb_x_flat),
        .bb_y_flat      (bb_y_flat),
        .bb_active      (bb_active),
        .bb_pattern_flat(bb_pattern_flat)
    );

    // ---------- collision (24 bbox + i-frame counter) ----------
    collision u_coll (
        .pixel_clk       (pixel_clk),
        .reset           (reset),
        .game_tick       (game_tick),
        .player_x        (player_x),
        .player_y        (player_y),
        .boss_x          (boss_x),
        .boss_y          (boss_y),
        .pb_x_flat       (pb_x_flat),
        .pb_y_flat       (pb_y_flat),
        .pb_active       (pb_active),
        .bb_x_flat       (bb_x_flat),
        .bb_y_flat       (bb_y_flat),
        .bb_active       (bb_active),
        .hit_mask        (hit_mask),
        .bb_hit_mask     (bb_hit_mask),
        .boss_hit_pulse  (boss_hit_pulse),
        .player_hit_pulse(player_hit_pulse)
    );

    // ---------- lives counter ----------
    // SPEC §1.7: player_lives [2:0], 0..5. Reset to 5; -1 on player_hit_pulse;
    // saturate at 0. Game-over gating deferred to next-step.
    reg [2:0] lives;
    always @(posedge pixel_clk) begin
        if (reset)
            lives <= 3'd5;
        else if (player_hit_pulse && lives != 3'd0)
            lives <= lives - 3'd1;
    end

    // ---------- hud ----------
    hud u_hud (
        .pixel_clk(pixel_clk),
        .reset    (reset),
        .lives    (lives),
        .boss_hp  (boss_hp),
        .led      (Ld),
        .an       (An),
        .seg      (seg),
        .dp       (Dp)
    );

    // ---------- renderer ----------
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
