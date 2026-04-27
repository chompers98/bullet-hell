`timescale 1ns / 1ps
// hud.v
// LEDs: 16 player lives, all on at start, turn off left to right on hit
// 7-seg: 8-digit multiplexed display showing boss HP (00000000-99999999)
//
// Nexys A7 notes:
//   - LEDs are active HIGH (1 = on)
//   - 7-seg anodes are active LOW (0 = digit enabled)
//   - 7-seg cathodes are active LOW (0 = segment on)
//   - Multiplexing driven by DIV_CLK bits, same pattern as ee354 reference

module hud (
    input  wire        clk,          // 25MHz pixel clock
    input  wire        reset,
    input  wire [4:0]  lives,        // 0-16
    input  wire [26:0] boss_hp,      // 0-99,999,999

    // LEDs
    output wire        Ld0,  Ld1,  Ld2,  Ld3, Ld4,  Ld5,  Ld6,  Ld7,
    output wire        Ld8,  Ld9,  Ld10, Ld11, Ld12, Ld13, Ld14, Ld15,

    // 7-seg anodes (active low)
    output wire        An0, An1, An2, An3, An4, An5, An6, An7,

    // 7-seg cathodes (active low)
    output wire        Ca, Cb, Cc, Cd, Ce, Cf, Cg, Dp
);

    // clock divider 
    // 25MHz so we use DIV_CLK[18:16] for ssdscan_clk
    // DIV_CLK[16] toggles at 25MHz/2^17 = 190.7Hz
    // each digit displayed for ~2.6ms, full 8-digit cycle ~47Hz
    reg [26:0] DIV_CLK;

    always @(posedge clk, posedge reset) begin
        if (reset)
            DIV_CLK <= 27'd0;
        else
            DIV_CLK <= DIV_CLK + 1'b1;
    end

    wire [2:0] ssdscan_clk = DIV_CLK[18:16];

    // LED output — active high
    // All 16 on at start, turn off left to right as lives lost
    // lives=16 → 1111111111111111
    // lives=0  → 0000000000000000
    wire [15:0] LED_OUT;

    assign LED_OUT = (lives >= 5'd16) ? 16'b1111111111111111 :
                     (lives == 5'd15) ? 16'b0111111111111111 :
                     (lives == 5'd14) ? 16'b0011111111111111 :
                     (lives == 5'd13) ? 16'b0001111111111111 :
                     (lives == 5'd12) ? 16'b0000111111111111 :
                     (lives == 5'd11) ? 16'b0000011111111111 :
                     (lives == 5'd10) ? 16'b0000001111111111 :
                     (lives == 5'd9)  ? 16'b0000000111111111 :
                     (lives == 5'd8)  ? 16'b0000000011111111 :
                     (lives == 5'd7)  ? 16'b0000000001111111 :
                     (lives == 5'd6)  ? 16'b0000000000111111 :
                     (lives == 5'd5)  ? 16'b0000000000011111 :
                     (lives == 5'd4)  ? 16'b0000000000001111 :
                     (lives == 5'd3)  ? 16'b0000000000000111 :
                     (lives == 5'd2)  ? 16'b0000000000000011 :
                     (lives == 5'd1)  ? 16'b0000000000000001 :
                                        16'b0000000000000000;

      assign {Ld15, Ld14, Ld13, Ld12, Ld11, Ld10, Ld9,  Ld8, Ld7,  Ld6,  Ld5,  Ld4, Ld3,  Ld2,  Ld1,  Ld0} = {LED_OUT};

      // BCD extraction — split boss_hp into 8 decimal digits
      wire [3:0] SSD7 = (boss_hp / 27'd10000000) % 27'd10; // ten-millions
      wire [3:0] SSD6 = (boss_hp / 27'd1000000)  % 27'd10; // millions
      wire [3:0] SSD5 = (boss_hp / 27'd100000)   % 27'd10; // hundred-thousands
      wire [3:0] SSD4 = (boss_hp / 27'd10000)    % 27'd10; // ten-thousands
      wire [3:0] SSD3 = (boss_hp / 27'd1000)     % 27'd10; // thousands
      wire [3:0] SSD2 = (boss_hp / 27'd100)      % 27'd10; // hundreds
      wire [3:0] SSD1 = (boss_hp / 27'd10)       % 27'd10; // tens
      wire [3:0] SSD0 =  boss_hp                 % 27'd10; // ones
  
      // anode selection — active low, one digit on at a time
      assign An0 = !(~ssdscan_clk[2] && ~ssdscan_clk[1] && ~ssdscan_clk[0]); // ssdscan_clk = 000
      assign An1 = !(~ssdscan_clk[2] && ~ssdscan_clk[1] &&  ssdscan_clk[0]); // ssdscan_clk = 001
      assign An2 = !(~ssdscan_clk[2] &&  ssdscan_clk[1] && ~ssdscan_clk[0]); // ssdscan_clk = 010
      assign An3 = !(~ssdscan_clk[2] &&  ssdscan_clk[1] &&  ssdscan_clk[0]); // ssdscan_clk = 011
      assign An4 = !( ssdscan_clk[2] && ~ssdscan_clk[1] && ~ssdscan_clk[0]); // ssdscan_clk = 100
      assign An5 = !( ssdscan_clk[2] && ~ssdscan_clk[1] &&  ssdscan_clk[0]); // ssdscan_clk = 101
      assign An6 = !( ssdscan_clk[2] &&  ssdscan_clk[1] && ~ssdscan_clk[0]); // ssdscan_clk = 110
      assign An7 = !( ssdscan_clk[2] &&  ssdscan_clk[1] &&  ssdscan_clk[0]); // ssdscan_clk = 111

      // digit mux — select which digit to display
      reg [3:0] SSD;
  
      always @(ssdscan_clk, SSD0, SSD1, SSD2, SSD3, SSD4, SSD5, SSD6, SSD7)
      begin : SSD_SCAN_OUT
          case (ssdscan_clk)
              3'b000: SSD = SSD0;
              3'b001: SSD = SSD1;
              3'b010: SSD = SSD2;
              3'b011: SSD = SSD3;
              3'b100: SSD = SSD4;
              3'b101: SSD = SSD5;
              3'b110: SSD = SSD6;
              3'b111: SSD = SSD7;
          endcase
      end
  
      // hex to 7-seg cathode decoder — active low
      // segment order: {Ca, Cb, Cc, Cd, Ce, Cf, Cg} = {a,b,c,d,e,f,g}
      reg [6:0] SSD_CATHODES;
    
        always @(SSD)
        begin : HEX_TO_SSD
            case (SSD)
                4'b0000: SSD_CATHODES = 7'b0000001; // 0
                4'b0001: SSD_CATHODES = 7'b1001111; // 1
                4'b0010: SSD_CATHODES = 7'b0010010; // 2
                4'b0011: SSD_CATHODES = 7'b0000110; // 3
                4'b0100: SSD_CATHODES = 7'b1001100; // 4
                4'b0101: SSD_CATHODES = 7'b0100100; // 5
                4'b0110: SSD_CATHODES = 7'b0100000; // 6
                4'b0111: SSD_CATHODES = 7'b0001111; // 7
                4'b1000: SSD_CATHODES = 7'b0000000; // 8
                4'b1001: SSD_CATHODES = 7'b0000100; // 9
                default: SSD_CATHODES = 7'b1111111; // blank
            endcase
        end
    
        assign {Ca, Cb, Cc, Cd, Ce, Cf, Cg} = (SSD_CATHODES};
        assign Dp = 1'b1; // decimal point off
    
    endmodule
