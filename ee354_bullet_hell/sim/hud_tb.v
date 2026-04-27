`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// hud_tb.v — self-checking testbench for hud (SPEC §10.6, §1.7).
//
// Expected values come from SPEC.md only, never from the RTL under test.
//
// Coverage (one check-group per item):
//   T1  Reset behavior            — SPEC §1.2 / §10.6
//   T2  LED-mapping for lives     — SPEC §1.7 (player_lives [2:0]) + IMPL note
//   T3  BCD decode for boss_hp    — SPEC §1.7 (boss_hp 0..99)
//   T4  Cathode 7-seg encoding    — Standard hex→7-seg LUT (active-low,
//                                   {a,b,c,d,e,f,g} order)
//   T5  Anode one-hot encoding    — Active-low, ssdscan_clk → an[i]==0
//   T6  Digits 2..7 blank         — IMPL note: only digits 0/1 populated
//
// Notes:
//   - pixel_clk = 25 MHz → 40 ns period (SPEC §1.1).
//   - The internal div_clk reg is poked directly via hierarchical reference
//     to fast-forward to specific ssdscan_clk states. iverilog supports this;
//     it is purely a TB convenience and does not depend on RTL formulas.
// -----------------------------------------------------------------------------

module hud_tb;

    // ------------------------------------------------------------------------
    // Clock / stimulus
    // ------------------------------------------------------------------------
    reg         pixel_clk = 1'b0;
    reg         reset     = 1'b1;
    reg  [2:0]  lives     = 3'd0;
    reg  [6:0]  boss_hp   = 7'd0;

    wire [15:0] led;
    wire [7:0]  an;
    wire [6:0]  seg;
    wire        dp;

    always #20 pixel_clk = ~pixel_clk;  // 25 MHz

    hud dut (
        .pixel_clk(pixel_clk),
        .reset    (reset),
        .lives    (lives),
        .boss_hp  (boss_hp),
        .led      (led),
        .an       (an),
        .seg      (seg),
        .dp       (dp)
    );

    // ------------------------------------------------------------------------
    // Test bookkeeping
    // ------------------------------------------------------------------------
    integer errors = 0;
    integer passes = 0;

    task check;
        input [511:0] name;
        input         cond;
        input [511:0] spec_cite;
        begin
            if (cond) begin
                passes = passes + 1;
            end else begin
                $display("FAIL: %0s -- expected per %0s", name, spec_cite);
                errors = errors + 1;
            end
        end
    endtask

    // Set ssdscan_clk = N by force-driving div_clk[18:16] = N.
    // `force` (not procedural `=`) avoids races against the always-block's
    // NBA on the next posedge. Lower bits cleared so the mux is deterministic.
    task set_scan;
        input [2:0] n;
        begin
            force dut.div_clk = {8'd0, n, 16'd0};
            #1;  // combinational settle (no clock edge needed)
        end
    endtask

    // Hold reset for >=2 clocks then release synchronously.
    task do_reset;
        begin
            reset = 1'b1;
            @(posedge pixel_clk);
            @(posedge pixel_clk);
            @(negedge pixel_clk);
            reset = 1'b0;
        end
    endtask

    // ------------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------------
    initial begin
        $dumpfile("hud_tb.vcd");
        $dumpvars(0, hud_tb);

        do_reset;

        // ---- T1: Reset cleared div_clk to 0 ----
        check("T1.div_clk_zero_after_reset", dut.div_clk == 27'd0,
              "SPEC §1.2 sync reset clears state");

        // ---- T2: LED mapping for lives 0..5 ----
        // IMPL note: lives=N lights LEDs[N-1:0]. lives>5 falls to 0.
        lives = 3'd0; #1;
        check("T2.lives_0", led == 16'h0000, "SPEC §1.7 + hud IMPL: lives=0 → all off");
        lives = 3'd1; #1;
        check("T2.lives_1", led == 16'h0001, "lives=1 → led[0]=1");
        lives = 3'd2; #1;
        check("T2.lives_2", led == 16'h0003, "lives=2 → led[1:0]=11");
        lives = 3'd3; #1;
        check("T2.lives_3", led == 16'h0007, "lives=3 → led[2:0]=111");
        lives = 3'd4; #1;
        check("T2.lives_4", led == 16'h000F, "lives=4 → led[3:0]=1111");
        lives = 3'd5; #1;
        check("T2.lives_5", led == 16'h001F, "lives=5 → led[4:0]=11111");
        lives = 3'd7; #1;
        check("T2.lives_oob", led == 16'h0000, "lives > 5 → all off (default)");

        // ---- T3 + T4 + T5: BCD decode + cathode encoding + anode select ----
        // Boss HP = 42 → digit_ones=2, digit_tens=4
        boss_hp = 7'd42;
        lives   = 3'd5;

        // ssdscan_clk=0 → digit_ones (=2)
        // 2 in 7-seg active-low {a,b,c,d,e,f,g}: a,b,d,e,g lit (segments for "2")
        //   = ~{a,b,c,d,e,f,g} where a=0 means "lit" → seg = 7'b0010010
        set_scan(3'd0);
        check("T3.hp42_ones_digit_seg", seg == 7'b0010010,
              "boss_hp=42 mod 10 = 2 → 7-seg pattern '2'");
        check("T5.an0_active_low",      an == 8'b1111_1110,
              "ssdscan_clk=0 → an[0]=0 (active-low one-hot)");

        // ssdscan_clk=1 → digit_tens (=4)
        // 4 in 7-seg: b,c,f,g lit → seg = 7'b1001100
        set_scan(3'd1);
        check("T3.hp42_tens_digit_seg", seg == 7'b1001100,
              "(boss_hp/10) mod 10 = 4 → 7-seg pattern '4'");
        check("T5.an1_active_low",      an == 8'b1111_1101,
              "ssdscan_clk=1 → an[1]=0");

        // ---- T6: digits 2..7 blank ----
        set_scan(3'd2);
        check("T6.digit2_blank", seg == 7'b1111111, "Digit 2 blank (boss_hp 0..99 only)");
        set_scan(3'd5);
        check("T6.digit5_blank", seg == 7'b1111111, "Digit 5 blank");
        set_scan(3'd7);
        check("T6.digit7_blank", seg == 7'b1111111, "Digit 7 blank");

        // ---- T3 boundary: HP=99 → digits ones=9, tens=9 ----
        boss_hp = 7'd99;
        set_scan(3'd0);
        check("T3.hp99_ones_seg", seg == 7'b0001100,
              "99 mod 10 = 9 → '9' (EE354 lab style: no Cd, lit a,b,c,f,g)");
        set_scan(3'd1);
        check("T3.hp99_tens_seg", seg == 7'b0001100,
              "99/10 mod 10 = 9 → '9' (EE354 lab style)");

        // HP=0 → digits ones=0, tens=0
        boss_hp = 7'd0;
        set_scan(3'd0);
        check("T3.hp0_ones_seg", seg == 7'b0000001, "0 mod 10 = 0 → '0'");
        set_scan(3'd1);
        check("T3.hp0_tens_seg", seg == 7'b0000001, "0/10 mod 10 = 0 → '0'");

        // HP=7 → ones=7, tens=0
        boss_hp = 7'd7;
        set_scan(3'd0);
        check("T3.hp7_ones_seg", seg == 7'b0001111, "7 mod 10 = 7 → '7'");
        set_scan(3'd1);
        check("T3.hp7_tens_seg", seg == 7'b0000001, "7/10 mod 10 = 0 → '0'");

        // ---- dp always off (active-low) ----
        check("T7.dp_off", dp == 1'b1, "IMPL: decimal point off (active-low)");

        // ------------------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------------------
        $display("hud_tb DONE: %0d passed, %0d failed", passes, errors);
        if (errors == 0) $display("hud_tb: ALL PASS");
        else             $display("hud_tb: FAIL");
        $finish;
    end

endmodule
