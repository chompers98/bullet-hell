`timescale 1ns / 1ps
// hud — 16 LEDs for player lives + 8-digit 7-seg multiplexed display
// for boss HP (only the low 2 digits are populated; rest blanked).
//
// IMPL DECISIONS:
//   - Reset polarity: active-high synchronous (SPEC §1.2 / GOTCHAS §G5).
//     Reverted from partner draft's async `posedge reset`.
//   - Clock: single `pixel_clk` domain (SPEC §1.1 / GOTCHAS §G12). Renamed
//     from partner draft's `clk` to match canonical name (CONVENTIONS §3).
//   - Port widths: `lives [2:0]` (0..5) and `boss_hp [6:0]` (0..99) per
//     SPEC §1.7. Partner draft used 5-bit lives + 27-bit HP — both
//     downsized to SPEC contract. No multi-million HP digits.
//   - Port form: bus-style (`led [15:0]`, `seg [6:0]`, `an [7:0]`, `dp`)
//     replacing the partner draft's per-bit Ld0..Ld15 etc. The XDC has
//     no LED/SSD pin bindings yet (added at top-integration time);
//     buses are the cleaner contract for that step. Cathode bit order
//     `seg = {a,b,c,d,e,f,g}` matches partner draft.
//   - Lives → LEDs mapping: leds[lives-1:0] lit, rest off. So lives=5
//     lights LEDs[4:0]; lives=0 = all off. SPEC §1.7 says only that
//     player_lives is "LED-mappable" — this is the conventional 1-bit-
//     per-life encoding.
//   - 7-seg refresh: 3-bit `ssdscan_clk` from a 27-bit free-running
//     counter, bits [18:16]. ~190 Hz per-digit / ~24 Hz full-cycle —
//     above the flicker threshold. Same pattern as partner draft and
//     the EE354 reference SSD multiplex.
//   - Digit assignment:
//        digit 0 (rightmost) = boss_hp % 10
//        digit 1             = (boss_hp / 10) % 10
//        digits 2..7         = blank
//     Boss HP only ranges 0..99 (SPEC §1.7), so two digits suffice.
//   - Active-low conventions on Nexys A7: anodes (an), cathodes (seg+dp)
//     are active-low; LEDs are active-high.
//   - No `initial` blocks (GOTCHAS §G14).
//
module hud (
    input  wire        pixel_clk,    // 25 MHz (SPEC §1.1)
    input  wire        reset,        // active-high sync (SPEC §1.2)

    input  wire [2:0]  lives,        // SPEC §1.7: player_lives, 0..5
    input  wire [6:0]  boss_hp,      // SPEC §1.7: 0..99

    output wire [15:0] led,          // active-high, lights[lives-1:0]
    output wire [7:0]  an,           // active-low digit-enable, one-hot
    output wire [6:0]  seg,          // active-low {a,b,c,d,e,f,g}
    output wire        dp            // active-low decimal point (always off)
);

    // ---------- localparams ----------
    localparam BLANK = 4'hF;  // sentinel for blank digits (mapped to 7'b1111111)

    // ---------- regs ----------
    reg  [26:0] div_clk;
    reg  [3:0]  ssd_digit;
    reg  [6:0]  seg_n;

    // ---------- wires ----------
    wire [2:0]  ssdscan_clk = div_clk[18:16];
    wire [3:0]  digit_ones;
    wire [3:0]  digit_tens;

    // ---------- LED bus: lives → leds[lives-1:0] ----------
    // 6-entry case is simpler (and synthesizes to a tiny LUT) than
    // a runtime shift with a non-constant width.
    reg [15:0] led_r;
    always @* begin
        case (lives)
            3'd0:    led_r = 16'h0000;
            3'd1:    led_r = 16'h0001;
            3'd2:    led_r = 16'h0003;
            3'd3:    led_r = 16'h0007;
            3'd4:    led_r = 16'h000F;
            3'd5:    led_r = 16'h001F;
            default: led_r = 16'h0000;  // lives > 5 — out-of-spec, treat as 0
        endcase
    end
    assign led = led_r;

    // ---------- BCD digit extraction (boss_hp 0..99) ----------
    // 7-bit divide-by-10: Vivado synthesizes a constant divider net,
    // ~10 LUTs total — fine for a HUD path.
    assign digit_tens = (boss_hp / 7'd10) % 7'd10;
    assign digit_ones =  boss_hp          % 7'd10;

    // ---------- sequential: digit-mux refresh counter ----------
    always @(posedge pixel_clk) begin
        if (reset)
            div_clk <= 27'd0;
        else
            div_clk <= div_clk + 27'd1;
    end

    // ---------- combinational: digit select ----------
    // Active-low one-hot anodes (only one digit lit per refresh slot).
    // Encoding: an[i] = 0 when ssdscan_clk == i. Direct 3-to-8 decoder.
    assign an[0] = ~(ssdscan_clk == 3'd0);
    assign an[1] = ~(ssdscan_clk == 3'd1);
    assign an[2] = ~(ssdscan_clk == 3'd2);
    assign an[3] = ~(ssdscan_clk == 3'd3);
    assign an[4] = ~(ssdscan_clk == 3'd4);
    assign an[5] = ~(ssdscan_clk == 3'd5);
    assign an[6] = ~(ssdscan_clk == 3'd6);
    assign an[7] = ~(ssdscan_clk == 3'd7);

    // Per-slot digit value (digits 2..7 = BLANK sentinel).
    always @* begin
        case (ssdscan_clk)
            3'd0:    ssd_digit = digit_ones;
            3'd1:    ssd_digit = digit_tens;
            default: ssd_digit = BLANK;
        endcase
    end

    // ---------- combinational: hex → 7-seg cathode (active-low) ----------
    // Order: seg = {a, b, c, d, e, f, g}. 0 = segment lit.
    always @* begin
        case (ssd_digit)
            4'h0:    seg_n = 7'b0000001;
            4'h1:    seg_n = 7'b1001111;
            4'h2:    seg_n = 7'b0010010;
            4'h3:    seg_n = 7'b0000110;
            4'h4:    seg_n = 7'b1001100;
            4'h5:    seg_n = 7'b0100100;
            4'h6:    seg_n = 7'b0100000;
            4'h7:    seg_n = 7'b0001111;
            4'h8:    seg_n = 7'b0000000;
            4'h9:    seg_n = 7'b0001100;   // EE354 lab convention: "9 without
                                           //   bottom base" — Cd off, lit a,b,c,f,g.
                                           //   See seven_segment_display_revised_tb.v.
            default: seg_n = 7'b1111111;  // BLANK
        endcase
    end

    assign seg = seg_n;
    assign dp  = 1'b1;  // decimal point always off (active-low)

endmodule
